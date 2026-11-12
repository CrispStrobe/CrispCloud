import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/ftp_security_mode.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';

void main() {
  test('legacy saved TLS flags preserve implicit mode', () {
    expect(
      FtpSecurityMode.fromStored(legacyUseTls: 'true'),
      FtpSecurityMode.implicitTls,
    );
    expect(
      FtpSecurityMode.fromStored(legacyUseTls: 'false'),
      FtpSecurityMode.plain,
    );
    expect(FtpSecurityMode.fromStored(), FtpSecurityMode.plain);
    expect(
      FtpSecurityMode.fromStored(mode: 'explicitTls', legacyUseTls: 'true'),
      FtpSecurityMode.explicitTls,
    );
  });

  test('unknown stored security settings cannot downgrade to plaintext', () {
    for (final unknown in ['', 'tls', 'futureMode']) {
      expect(
        () => FtpSecurityMode.fromStored(mode: unknown),
        throwsFormatException,
      );
    }
    expect(
      () => FtpSecurityMode.fromStored(legacyUseTls: 'maybe'),
      throwsFormatException,
    );
  });

  test(
    'legacy identities keep their explicit ports and support email usernames',
    () {
      final identity = FtpLoginIdentity.parse(
        'user@example.org@ftp.example.org:21?tls=true',
      );
      expect(identity.username, 'user@example.org');
      expect(identity.host, 'ftp.example.org');
      expect(identity.port, 21);
      expect(identity.securityMode, FtpSecurityMode.implicitTls);
    },
  );

  test('security mode determines the default port when it is omitted', () {
    expect(FtpLoginIdentity.parse('user@host?security=implicitTls').port, 990);
    expect(FtpLoginIdentity.parse('user@host?security=explicitTls').port, 21);
    expect(FtpLoginIdentity.parse('user@host').port, 21);
  });

  test('dialog identity round trips IPv6, security and custom ports', () {
    final original = FtpLoginIdentity(
      username: 'account@example.org',
      host: '::1',
      port: 2121,
      securityMode: FtpSecurityMode.explicitTls,
    );
    final parsed = FtpLoginIdentity.parse(original.encode());
    expect(parsed.host, '::1');
    expect(parsed.username, original.username);
    expect(parsed.port, original.port);
    expect(parsed.securityMode, original.securityMode);
  });

  for (final identity in [
    'user@host?security=typo',
    'user@host?security=plain&tls=true',
    'user@host?security=explicitTls&security=plain',
    'user@host?tls=true&unrecognized=true',
    'user@host:0',
    'user@host:65536',
    'user@host/path',
    'user\r\nPASS injected@host',
  ]) {
    test('invalid FTP identity is rejected: $identity', () {
      expect(() => FtpLoginIdentity.parse(identity), throwsFormatException);
    });
  }

  for (final mode in FtpSecurityMode.values) {
    test(
      '${mode.name} persists and selects the same metadata transport',
      () async {
        final config = FTPConfigService(
          configPath: '',
          secureStorage: InMemorySecureStorage(),
        );
        SecurityType? selected;
        final adapter = FTPClientAdapter(
          config: config,
          clientFactory:
              (
                String host, {
                required int port,
                required String user,
                required String pass,
                required SecurityType securityType,
                required int timeout,
              }) {
                selected = securityType;
                expect(port, 2121);
                expect(user, 'fixture');
                return _ConnectedFtp();
              },
        );
        addTearDown(adapter.logout);
        await adapter.login(
          'fixture@localhost:2121?security=${mode.name}',
          'test-password',
        );
        expect(selected, switch (mode) {
          FtpSecurityMode.plain => SecurityType.ftp,
          FtpSecurityMode.implicitTls => SecurityType.ftps,
          FtpSecurityMode.explicitTls => SecurityType.ftpes,
        });
        final saved = (await config.readCredentials())!;
        expect(saved['securityMode'], mode.name);
        expect(saved['port'], '2121');
        expect(saved['useTLS'], '${mode.isSecure}');
      },
    );
  }

  test('unknown saved mode rejects before opening a socket or rewriting credentials', () async {
    final config = FTPConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    final saved = {
      'host': 'localhost',
      'username': 'fixture',
      'password': 'test-password',
      'port': '21',
      'securityMode': 'unsupported',
      'useTLS': 'false',
    };
    await config.saveCredentials(saved);
    var opened = false;
    final adapter = FTPClientAdapter(
      config: config,
      clientFactory:
          (
            String host, {
            required int port,
            required String user,
            required String pass,
            required SecurityType securityType,
            required int timeout,
          }) {
            opened = true;
            return _ConnectedFtp();
          },
    );
    await expectLater(adapter.restoreSession(), throwsFormatException);
    expect(opened, isFalse);
    expect(await config.readCredentials(), saved);
  });
}

class _ConnectedFtp implements FTPConnect {
  @override
  Future<bool> connect() async => true;
  @override
  Future<bool> disconnect() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
