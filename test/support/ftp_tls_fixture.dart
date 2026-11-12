import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Loopback FTP peer with real TLS. The certificates/private key are the
/// repository's public test fixtures, never a production credential.
class FtpTlsFixture {
  FtpTlsFixture._(this.listener, {required this.implicit}) {
    listener.listen((socket) {
      _sockets.add(socket);
      unawaited(
        _serve(socket)
            .catchError((Object error) {
              // Rejected certificates and client cancellation deliberately terminate
              // the socket. Protocol fixture defects remain observable to the test.
              if (error is! TlsException &&
                  error is! SocketException &&
                  error is! StateError)
                errors.add(error);
            })
            .whenComplete(() => socket.destroy()),
      );
    });
  }

  final ServerSocket listener;
  final bool implicit;
  final _sockets = <Socket>{};
  final _passive = <ServerSocket>{};
  final commands = <String>[];
  final cleartextCommands = <String>[];
  final protectedCommands = <String>[];
  final uploads = <List<int>>[];
  final errors = <Object>[];
  List<int> payload = List.generate(100000, (index) => index % 251);
  String controlCertificate = 'server.pem';
  String dataCertificate = 'server.pem';
  int authReply = 234;
  int pbszReply = 200;
  int protReply = 200;
  int controlTlsConnections = 0;
  int dataTlsConnections = 0;
  bool stallControlHandshake = false;
  final controlHandshakeStarted = Completer<void>();

  int get port => listener.port;

  static Future<FtpTlsFixture> open({bool implicit = false}) async =>
      FtpTlsFixture._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        implicit: implicit,
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

  Future<void> _serve(Socket original) async {
    var control = original;
    var protected = implicit;
    if (implicit) {
      control = await SecureSocket.secureServer(
        control,
        _serverContext(controlCertificate),
      );
      _sockets.add(control);
      controlTlsConnections++;
    }
    void reply(String value) => control.add(utf8.encode('$value\r\n'));
    reply('220 Test FTP ready');
    var lines = _lines(control);
    Future<Socket>? nextData;
    var privateData = false;
    try {
      while (await lines.moveNext()) {
        final command = lines.current;
        commands.add(command);
        (protected ? protectedCommands : cleartextCommands).add(command);
        final verb = command.split(' ').first.toUpperCase();
        switch (verb) {
          case 'AUTH':
            reply('$authReply TLS negotiation');
            await control.flush();
            if (authReply != 234) continue;
            if (!controlHandshakeStarted.isCompleted)
              controlHandshakeStarted.complete();
            if (stallControlHandshake) {
              await lines.moveNext();
              return;
            }
            final oldLines = lines;
            control = await SecureSocket.secureServer(
              control,
              _serverContext(controlCertificate),
            );
            _sockets.add(control);
            lines = _lines(control);
            await oldLines.cancel();
            protected = true;
            controlTlsConnections++;
          case 'USER':
            reply('331 Password required');
          case 'PASS':
            reply('230 Signed in');
          case 'PBSZ':
            reply('$pbszReply Buffer size');
          case 'PROT':
            privateData = command == 'PROT P' && protReply == 200;
            reply('$protReply Data protection');
          case 'TYPE':
            reply('200 Transfer type');
          case 'PWD':
            reply('257 "/" is the current directory');
          case 'CWD':
            reply('250 Directory changed');
          case 'SIZE':
            reply('213 ${payload.length}');
          case 'EPSV' || 'PASV':
            final passive = await ServerSocket.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            _passive.add(passive);
            nextData = passive.first.then((socket) {
              _sockets.add(socket);
              return socket;
            });
            reply(
              verb == 'EPSV'
                  ? '229 Entering Extended Passive Mode (|||${passive.port}|)'
                  : '227 Entering Passive Mode (127,0,0,1,${passive.port ~/ 256},${passive.port % 256})',
            );
          case 'RETR' || 'STOR' || 'MLSD' || 'LIST':
            reply('150 Data channel ready');
            await control.flush();
            var data = await nextData!;
            if (privateData) {
              data = await SecureSocket.secureServer(
                data,
                _serverContext(dataCertificate),
              );
              _sockets.add(data);
              dataTlsConnections++;
            }
            if (verb == 'STOR') {
              uploads.add(await data.expand((chunk) => chunk).toList());
            } else {
              data.add(
                verb == 'RETR'
                    ? payload
                    : utf8.encode(
                        'type=file;size=3;modify=20261112080000; sample.txt\r\n',
                      ),
              );
              await data.flush();
            }
            await data.close();
            reply('226 Transfer complete');
          case 'QUIT':
            reply('221 Bye');
            await control.flush();
            return;
          default:
            reply('502 Unknown command');
        }
      }
    } finally {
      control.destroy();
      await lines.cancel();
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) socket.destroy();
    for (final server in _passive) await server.close();
    await listener.close();
  }
}
