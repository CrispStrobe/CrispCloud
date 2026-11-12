import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Socks4Request {
  const Socks4Request({
    required this.address,
    required this.host,
    required this.port,
    required this.userId,
    required this.remoteDns,
  });

  final List<int> address;
  final String host;
  final int port;
  final String userId;
  final bool remoteDns;
}

/// Independent loopback implementation of the SOCKS4/4a CONNECT wire format.
/// Only the server maps requested destinations to loopback; the recorded
/// request distinguishes actual IPv4 requests from remote DNS requests.
class Socks4Fixture {
  Socks4Fixture._(
    this._server, {
    this.replyVersion = 0,
    this.replyCode = 90,
    this.replyLength = 8,
    this.fragmentReplies = false,
    this.stallReply = false,
    this.stallAfterConnect = false,
    this.inlinePayload,
  });

  final ServerSocket _server;
  final int replyVersion;
  final int replyCode;
  final int replyLength;
  final bool fragmentReplies;
  final bool stallReply;
  final bool stallAfterConnect;
  final List<int>? inlinePayload;
  final requests = <Socks4Request>[];
  final errors = <Object>[];
  final _sockets = <Socket>{};
  final _tasks = <Future<void>>{};
  final connected = Completer<void>();
  final tunnelData = Completer<void>();
  final firstClosed = Completer<void>();
  int acceptedConnections = 0;
  int originsOpened = 0;
  int get port => _server.port;

  static Future<Socks4Fixture> start({
    int replyVersion = 0,
    int replyCode = 90,
    int replyLength = 8,
    bool fragmentReplies = false,
    bool stallReply = false,
    bool stallAfterConnect = false,
    List<int>? inlinePayload,
  }) async {
    final fixture = Socks4Fixture._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      replyVersion: replyVersion,
      replyCode: replyCode,
      replyLength: replyLength,
      fragmentReplies: fragmentReplies,
      stallReply: stallReply,
      stallAfterConnect: stallAfterConnect,
      inlinePayload: inlinePayload,
    );
    fixture._server.listen((socket) {
      fixture.acceptedConnections++;
      final task = fixture._handle(socket);
      fixture._tasks.add(task);
      unawaited(task.whenComplete(() => fixture._tasks.remove(task)));
    });
    return fixture;
  }

  Future<void> _send(Socket socket, List<int> bytes) async {
    if (!fragmentReplies) {
      socket.add(bytes);
      await socket.flush();
      return;
    }
    for (final byte in bytes) {
      socket.add([byte]);
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<void> _handle(Socket socket) async {
    _sockets.add(socket);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final input = _FixtureReader(socket);
    Socket? target;
    try {
      final header = await input.read(8);
      if (header[0] != 4 || header[1] != 1) {
        throw StateError('Expected a SOCKS4 CONNECT request.');
      }
      final requestedPort = (header[2] << 8) | header[3];
      final address = header.sublist(4, 8);
      final remoteDns =
          address[0] == 0 &&
          address[1] == 0 &&
          address[2] == 0 &&
          address[3] != 0;
      final userId = await input.nulTerminated();
      final host = remoteDns
          ? await input.nulTerminated()
          : InternetAddress.fromRawAddress(Uint8List.fromList(address)).address;
      requests.add(
        Socks4Request(
          address: address,
          host: host,
          port: requestedPort,
          userId: userId,
          remoteDns: remoteDns,
        ),
      );
      if (!connected.isCompleted) connected.complete();
      if (stallReply) {
        await input.remaining().drain<void>();
        return;
      }
      final reply = [replyVersion, replyCode, 0, 0, 127, 0, 0, 1];
      if (replyLength < reply.length) {
        await _send(socket, reply.take(replyLength).toList());
        await socket.close();
        await input.remaining().drain<void>();
        return;
      }
      if (replyVersion != 0 || replyCode != 90) {
        await _send(socket, reply);
        await input.remaining().drain<void>();
        return;
      }
      if (inlinePayload != null || stallAfterConnect) {
        await _send(socket, [...reply, ...?inlinePayload]);
        await for (final bytes in input.remaining()) {
          if (bytes.isNotEmpty && !tunnelData.isCompleted) {
            tunnelData.complete();
          }
        }
        return;
      }
      target = await Socket.connect(
        InternetAddress.loopbackIPv4,
        requestedPort,
      );
      _sockets.add(target);
      originsOpened++;
      await _send(socket, reply);
      final remote = target;
      await Future.wait([
        socket.addStream(remote).then((_) => socket.close()),
        remote.addStream(input.remaining()).then((_) => remote.close()),
      ]);
    } on SocketException {
      // Deliberate rejection/cancellation can close either side of the tunnel.
    } on _FixtureClosed {
      // The client can cancel before sending a complete request.
    } catch (error) {
      errors.add(error);
    } finally {
      socket.destroy();
      target?.destroy();
      _sockets.remove(socket);
      _sockets.remove(target);
      await input.cancel();
      if (!firstClosed.isCompleted) firstClosed.complete();
    }
  }

  Future<void> close() async {
    await _server.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    await Future.wait(_tasks.toList());
  }
}

class _FixtureClosed implements Exception {}

class _FixtureReader {
  _FixtureReader(Socket socket) : _input = StreamIterator(socket);
  final StreamIterator<Uint8List> _input;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  Future<List<int>> read(int count) async {
    final bytes = <int>[];
    while (bytes.length < count) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) throw _FixtureClosed();
        _chunk = _input.current;
        _offset = 0;
      }
      final remaining = count - bytes.length;
      final available = _chunk.length - _offset;
      final length = remaining < available ? remaining : available;
      bytes.addAll(_chunk.sublist(_offset, _offset + length));
      _offset += length;
    }
    return bytes;
  }

  Future<String> nulTerminated() async {
    final bytes = <int>[];
    while (bytes.length <= 255) {
      final byte = (await read(1)).single;
      if (byte == 0) return ascii.decode(bytes);
      bytes.add(byte);
    }
    throw StateError('SOCKS4 test request exceeded its field limit.');
  }

  Stream<Uint8List> remaining() async* {
    if (_offset < _chunk.length) yield Uint8List.sublistView(_chunk, _offset);
    while (await _input.moveNext()) {
      yield _input.current;
    }
  }

  Future<void> cancel() => _input.cancel();
}
