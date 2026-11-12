import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ftp_security_mode.dart';

/// Independent loopback peer: parses command bytes and implements REST itself.
/// It never calls the production reply, snapshot, transfer or TLS helpers.
class FtpResumeFixture {
  FtpResumeFixture._(this.listener, this.mode) {
    listener.listen((socket) {
      final index = controlConnections++;
      sessions[index] = [];
      _sockets.add(socket);
      unawaited(
        _serve(socket, index)
            .catchError((Object error) {
              if (!_closing &&
                  error is! SocketException &&
                  error is! TlsException) {
                errors.add(error);
              }
            })
            .whenComplete(socket.destroy),
      );
    });
  }

  final ServerSocket listener;
  final FtpSecurityMode mode;
  final _sockets = <Socket>{};
  final _passive = <ServerSocket>{};
  final commands = <String>[];
  final protectedCommands = <String>[];
  final cleartextCommands = <String>[];
  final sessions = <int, List<String>>{};
  final offsets = <int?>[];
  final errors = <Object>[];
  final restReceived = Completer<void>();
  final retrReceived = Completer<void>();
  final stalledCommandReceived = Completer<void>();
  final dataChunkSent = Completer<void>();
  final controlPeerClosed = Completer<void>();
  final dataPeerClosed = Completer<void>();
  final dataHandshakeStarted = Completer<void>();
  final stalledTlsPrefix = <int>[];
  Uint8List payload = Uint8List.fromList(
    List.generate(196733, (index) => (index * 47 + index ~/ 251) % 256),
  );
  String modified = '20261112080000.123456';
  String controlCertificate = 'server.pem';
  String dataCertificate = 'server.pem';
  String? modifiedReply;
  String? sizeReply;
  String? stallCommand;
  int featureCode = 211;
  String feature = 'REST STREAM';
  int restCode = 350;
  int retrCode = 150;
  int finalCode = 226;
  bool useEpsv = true;
  bool ignoreOffset = false;
  bool corruptResumedPayload = false;
  bool changeModifiedAfterData = false;
  bool changeSizeAfterData = false;
  bool closeBeforeCompletion = false;
  bool stallDataHandshake = false;
  int truncateTail = 0;
  int? pauseAfterBytes;
  Completer<void>? releaseData;
  int controlConnections = 0;
  int protectedDataConnections = 0;
  bool _closing = false;

  int get port => listener.port;

  static Future<FtpResumeFixture> open({
    FtpSecurityMode mode = FtpSecurityMode.plain,
  }) async => FtpResumeFixture._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    mode,
  );

  static SecurityContext trustedContext() =>
      SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('test/fixtures/tls/ca.pem');

  SecurityContext _serverContext(String certificate) => SecurityContext()
    ..useCertificateChain('test/fixtures/tls/$certificate')
    ..usePrivateKey('test/fixtures/tls/server.key');

  StreamIterator<String> _lines(Socket socket) => StreamIterator(
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );

  Future<void> _serve(Socket original, int index) async {
    var control = original;
    var protected = mode == FtpSecurityMode.implicitTls;
    if (protected) {
      control = await SecureSocket.secureServer(
        control,
        _serverContext(controlCertificate),
      );
      _sockets.add(control);
    }
    Future<void> reply(String line) async {
      control.add(utf8.encode('$line\r\n'));
      await control.flush();
    }

    await reply('220 Independent restart fixture');
    var lines = _lines(control);
    Future<Socket>? dataFuture;
    int? restart;
    var privateData = false;
    try {
      while (await lines.moveNext()) {
        final command = lines.current;
        commands.add(command);
        sessions[index]!.add(command);
        (protected ? protectedCommands : cleartextCommands).add(command);
        final separator = command.indexOf(' ');
        final verb = (separator < 0 ? command : command.substring(0, separator))
            .toUpperCase();
        final argument = separator < 0 ? '' : command.substring(separator + 1);
        if (verb == stallCommand) {
          if (!stalledCommandReceived.isCompleted) {
            stalledCommandReceived.complete();
          }
          // Keep reading only to observe client EOF/reset, without replying.
          await lines.moveNext();
          if (!_closing && !controlPeerClosed.isCompleted) {
            controlPeerClosed.complete();
          }
          return;
        }
        switch (verb) {
          case 'AUTH':
            await reply('234 Proceed with TLS');
            final old = lines;
            control = await SecureSocket.secureServer(
              control,
              _serverContext(controlCertificate),
            );
            _sockets.add(control);
            lines = _lines(control);
            await old.cancel();
            protected = true;
          case 'USER':
            await reply('331 Password required');
          case 'PASS':
            await reply('230 Signed in');
          case 'PBSZ':
            await reply('200 Buffer accepted');
          case 'PROT':
            privateData = argument == 'P';
            await reply('200 Protection accepted');
          case 'TYPE' || 'MODE' || 'STRU' || 'OPTS':
            await reply('200 Accepted');
          case 'PWD':
            await reply('257 "/" is the current directory');
          case 'CWD':
            await reply(
              argument == '/' ? '250 Directory changed' : '550 Not a directory',
            );
          case 'FEAT':
            if (featureCode != 211) {
              await reply('$featureCode Features unavailable');
            } else {
              await reply('211-Features');
              await reply(' SIZE');
              await reply(' MDTM');
              if (feature.isNotEmpty) await reply(' $feature');
              await reply('211 End');
            }
          case 'SIZE':
            await reply(sizeReply ?? '213 ${payload.length}');
          case 'MDTM':
            await reply(modifiedReply ?? '213 $modified');
          case 'EPSV' || 'PASV':
            if (verb == 'EPSV' && !useEpsv) {
              await reply('502 EPSV unsupported');
              continue;
            }
            final listener = await ServerSocket.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            _passive.add(listener);
            dataFuture = listener.first.then((socket) {
              _sockets.add(socket);
              return socket;
            });
            await reply(
              verb == 'EPSV'
                  ? '229 Passive (|||${listener.port}|)'
                  : '227 Passive (192,0,2,99,${listener.port ~/ 256},${listener.port % 256})',
            );
          case 'REST':
            if (!restReceived.isCompleted) restReceived.complete();
            if (restCode == 350) restart = int.parse(argument);
            await reply('$restCode Restart response');
          case 'RETR' || 'MLSD' || 'LIST':
            if (verb == 'RETR') {
              offsets.add(restart);
              if (!retrReceived.isCompleted) retrReceived.complete();
              if (retrCode != 150) {
                await reply('$retrCode Retrieve rejected');
                continue;
              }
            }
            await reply('150 Opening data');
            var data = await dataFuture!;
            if (privateData) {
              if (stallDataHandshake) {
                await _observeStalledHandshake(data);
                return;
              }
              data = await SecureSocket.secureServer(
                data,
                _serverContext(dataCertificate),
              );
              _sockets.add(data);
              protectedDataConnections++;
            }
            final peerClosed = Completer<void>();
            data.listen(
              (_) {},
              onError: (Object _) {
                if (!peerClosed.isCompleted) peerClosed.complete();
              },
              onDone: () {
                if (!peerClosed.isCompleted) peerClosed.complete();
              },
            );
            unawaited(
              peerClosed.future.then((_) {
                if (!_closing && !dataPeerClosed.isCompleted) {
                  dataPeerClosed.complete();
                }
              }),
            );
            List<int> bytes;
            if (verb == 'RETR') {
              final offset = ignoreOffset ? 0 : restart ?? 0;
              bytes = payload.sublist(offset, payload.length - truncateTail);
              if (corruptResumedPayload && (restart ?? 0) > 0) {
                bytes = bytes.map((byte) => byte ^ 0x5a).toList();
              }
            } else {
              bytes = utf8.encode(
                'type=file;size=${payload.length};modify=$modified; payload.bin\r\n',
              );
            }
            restart = null;
            if (verb == 'RETR' && pauseAfterBytes != null) {
              final count = pauseAfterBytes!.clamp(0, bytes.length);
              data.add(bytes.sublist(0, count));
              await data.flush();
              if (!dataChunkSent.isCompleted) dataChunkSent.complete();
              await Future.any([releaseData!.future, peerClosed.future]);
              if (peerClosed.isCompleted) return;
              bytes = bytes.sublist(count);
            }
            data.add(bytes);
            await data.flush();
            await data.close();
            if (verb == 'RETR') {
              if (changeModifiedAfterData) modified = '20261112090000';
              if (changeSizeAfterData) {
                payload = Uint8List.fromList([...payload, 17]);
              }
              if (closeBeforeCompletion) return;
            }
            await reply('$finalCode Transfer finished');
          case 'QUIT':
            await reply('221 Goodbye');
            return;
          default:
            await reply('502 Unknown command');
        }
      }
      if (!_closing && !controlPeerClosed.isCompleted) {
        controlPeerClosed.complete();
      }
    } on SocketException {
      if (!_closing && !controlPeerClosed.isCompleted) {
        controlPeerClosed.complete();
      }
      rethrow;
    } finally {
      control.destroy();
      await lines.cancel();
    }
  }

  Future<void> _observeStalledHandshake(Socket data) async {
    try {
      await for (final chunk in data) {
        stalledTlsPrefix.addAll(chunk.take(16 - stalledTlsPrefix.length));
        if (!dataHandshakeStarted.isCompleted) dataHandshakeStarted.complete();
      }
    } on SocketException {
      // A physically cancelled TLS socket can terminate with a TCP reset.
    } finally {
      if (!_closing && !dataPeerClosed.isCompleted) dataPeerClosed.complete();
    }
  }

  Future<void> close() async {
    _closing = true;
    if (releaseData != null && !releaseData!.isCompleted) {
      releaseData!.complete();
    }
    for (final socket in _sockets) {
      socket.destroy();
    }
    for (final listener in _passive) {
      await listener.close();
    }
    await listener.close();
  }
}
