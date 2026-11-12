import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Receives ClientHello but never completes TLS. Peer closure is observed on
/// the unencrypted TCP stream before fixture teardown, not inferred from a
/// client-side Future or from destruction of the fixture's own socket.
class FtpControlStallFixture {
  FtpControlStallFixture._(this.listener, this.implicit) {
    listener.listen((socket) {
      _sockets.add(socket);
      unawaited(
        _serve(socket)
            .catchError((Object error) {
              if (error is! SocketException) errors.add(error);
            })
            .whenComplete(socket.destroy),
      );
    });
  }

  final ServerSocket listener;
  final bool implicit;
  final _sockets = <Socket>[];
  final commands = <String>[];
  final errors = <Object>[];
  final handshakeStarted = Completer<void>();
  final peerClosed = Completer<void>();
  final helloPrefix = <int>[];
  int get port => listener.port;

  static Future<FtpControlStallFixture> open({required bool implicit}) async =>
      FtpControlStallFixture._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        implicit,
      );

  Future<void> _serve(Socket socket) async {
    final chunks = StreamIterator(socket);
    try {
      if (!implicit) {
        socket.add(utf8.encode('220 TLS fixture ready\r\n'));
        await socket.flush();
        final line = <int>[];
        var complete = false;
        while (!complete && await chunks.moveNext()) {
          for (final byte in chunks.current) {
            line.add(byte);
            if (line.length > 1024) throw StateError('Unexpected FTP command.');
            if (byte == 10) {
              complete = true;
              break;
            }
          }
        }
        final command = utf8.decode(line).trim();
        commands.add(command);
        if (command != 'AUTH TLS') throw StateError('Expected AUTH TLS.');
        socket.add(utf8.encode('234 Begin TLS\r\n'));
        await socket.flush();
      }
      while (await chunks.moveNext()) {
        final bytes = chunks.current;
        if (bytes.isEmpty) continue;
        if (helloPrefix.length < 16) {
          helloPrefix.addAll(bytes.take(16 - helloPrefix.length));
        }
        if (!handshakeStarted.isCompleted) handshakeStarted.complete();
      }
    } on SocketException {
      // A peer abort may reset TCP rather than sending an orderly EOF.
    } finally {
      if (handshakeStarted.isCompleted && !peerClosed.isCompleted) {
        peerClosed.complete();
      }
      await chunks.cancel();
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) socket.destroy();
    await listener.close();
  }
}
