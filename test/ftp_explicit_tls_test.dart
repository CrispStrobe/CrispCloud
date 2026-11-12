import 'dart:io';

import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/ftp_security_mode.dart';
import 'package:crisp_cloud/services/ftp_transfer_session.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';

import 'support/ftp_tls_fixture.dart';

void main() {
  Future<FtpTlsFixture> server({bool implicit = false}) async {
    final fixture = await FtpTlsFixture.open(implicit: implicit);
    addTearDown(() async {
      await fixture.close();
      expect(fixture.errors, isEmpty);
    });
    return fixture;
  }

  FtpTransferSession session(FtpTlsFixture server, {bool trust = true}) {
    final client = FtpTransferSession(
      host: '127.0.0.1',
      port: server.port,
      username: 'fixture',
      password: 'synthetic-password',
      securityMode: server.implicit
          ? FtpSecurityMode.implicitTls
          : FtpSecurityMode.explicitTls,
      securityContext: trust ? FtpTlsFixture.trustedContext() : null,
      isCurrent: () => true,
      timeout: const Duration(seconds: 3),
    );
    addTearDown(client.close);
    return client;
  }

  for (final implicit in [false, true]) {
    test(
      '${implicit ? 'implicit' : 'explicit'} TLS protects download and upload bytes',
      () async {
        final fixture = await server(implicit: implicit);
        final download = session(fixture);
        await download.connect();
        expect(
          await download.download('/sample').expand((part) => part).toList(),
          fixture.payload,
        );
        final upload = session(fixture);
        await upload.connect();
        await upload.upload('/uploaded', Stream.value([3, 1, 4, 1, 5]), 5);
        expect(fixture.uploads.single, [3, 1, 4, 1, 5]);
        expect(fixture.controlTlsConnections, 2);
        expect(fixture.dataTlsConnections, 2);
        expect(
          fixture.cleartextCommands,
          implicit ? isEmpty : everyElement('AUTH TLS'),
        );
        expect(
          fixture.protectedCommands,
          containsAll([
            'USER fixture',
            'PASS synthetic-password',
            'PBSZ 0',
            'PROT P',
          ]),
        );
      },
    );

    for (final certificate in [
      'wrong-host.pem',
      'expired.pem',
      'forged-issuer.pem',
    ]) {
      test(
        '${implicit ? 'implicit' : 'explicit'} TLS rejects control certificate $certificate before credentials',
        () async {
          final fixture = await server(implicit: implicit);
          fixture.controlCertificate = certificate;
          await expectLater(
            session(fixture).connect(),
            throwsA(isA<TlsException>()),
          );
          expect(
            fixture.commands.where(
              (command) =>
                  command.startsWith('USER') || command.startsWith('PASS'),
            ),
            isEmpty,
          );
        },
      );
    }

    test(
      '${implicit ? 'implicit' : 'explicit'} TLS rejects an untrusted CA',
      () async {
        final fixture = await server(implicit: implicit);
        await expectLater(
          session(fixture, trust: false).connect(),
          throwsA(isA<TlsException>()),
        );
        expect(fixture.protectedCommands, isEmpty);
      },
    );

    test(
      '${implicit ? 'implicit' : 'explicit'} TLS verifies the data certificate separately',
      () async {
        final fixture = await server(implicit: implicit);
        fixture.dataCertificate = 'wrong-host.pem';
        final upload = session(fixture);
        await upload.connect();
        await expectLater(
          upload.upload('/file', Stream.value([1, 2]), 2),
          throwsA(isA<TlsException>()),
        );
        expect(fixture.uploads, isEmpty);
        expect(fixture.dataTlsConnections, 0);
      },
    );
  }

  for (final rejection in [500, 534, 200]) {
    test(
      'AUTH TLS reply $rejection fails closed without login or downgrade',
      () async {
        final fixture = await server();
        fixture.authReply = rejection;
        await expectLater(session(fixture).connect(), throwsStateError);
        expect(fixture.commands, ['AUTH TLS']);
      },
    );
  }

  for (final rejected in ['PBSZ', 'PROT']) {
    test('$rejected refusal never opens a data connection', () async {
      final fixture = await server();
      if (rejected == 'PBSZ') fixture.pbszReply = 500;
      if (rejected == 'PROT') fixture.protReply = 534;
      await expectLater(session(fixture).connect(), throwsStateError);
      expect(
        fixture.commands.where(
          (command) => command == 'PASV' || command == 'EPSV',
        ),
        isEmpty,
      );
    });
  }

  for (final implicit in [false, true]) {
    test(
      'adapter ${implicit ? 'legacy implicit' : 'explicit'} mode protects directory data and bounded transfers',
      () async {
        final fixture = await server(implicit: implicit);
        final config = FTPConfigService(
          configPath: '',
          secureStorage: InMemorySecureStorage(),
        );
        await config.saveCredentials({
          'host': '127.0.0.1',
          'port': '${fixture.port}',
          'username': 'fixture',
          'password': 'synthetic-password',
          if (!implicit) 'securityMode': FtpSecurityMode.explicitTls.name,
          'useTLS': 'true',
        });
        final adapter = FTPClientAdapter(
          config: config,
          securityContext: FtpTlsFixture.trustedContext(),
        );
        addTearDown(adapter.logout);
        await adapter.restoreSession();
        final listing = await adapter.listPath('/');
        expect((listing['files'] as List).single['name'], 'sample.txt');
        expect(
          await adapter
              .downloadStream('/sample')
              .expand((part) => part)
              .toList(),
          fixture.payload,
        );
        expect(fixture.dataTlsConnections, 2);
        expect(
          fixture.cleartextCommands,
          implicit ? isEmpty : everyElement('AUTH TLS'),
        );
        expect((await config.readCredentials())!['port'], '${fixture.port}');
      },
    );
  }

  test(
    'metadata runtime rejects AUTH TLS refusal without AUTH SSL or credentials',
    () async {
      final fixture = await server();
      fixture.authReply = 534;
      final client = FTPConnect(
        '127.0.0.1',
        port: fixture.port,
        user: 'fixture',
        pass: 'synthetic-password',
        securityType: SecurityType.ftpes,
        securityContext: FtpTlsFixture.trustedContext(),
        timeout: 3,
      );
      addTearDown(client.disconnect);
      await expectLater(client.connect(), throwsA(anything));
      expect(fixture.commands, ['AUTH TLS']);
    },
  );

  test(
    'metadata runtime validates control certificates before credentials',
    () async {
      final fixture = await server();
      fixture.controlCertificate = 'wrong-host.pem';
      final client = FTPConnect(
        '127.0.0.1',
        port: fixture.port,
        user: 'fixture',
        pass: 'synthetic-password',
        securityType: SecurityType.ftpes,
        securityContext: FtpTlsFixture.trustedContext(),
        timeout: 3,
      );
      addTearDown(client.disconnect);
      await expectLater(client.connect(), throwsA(anything));
      expect(fixture.commands, ['AUTH TLS']);
    },
  );

  test('metadata runtime validates directory data certificates', () async {
    final fixture = await server();
    fixture.dataCertificate = 'wrong-host.pem';
    final client = FTPConnect(
      '127.0.0.1',
      port: fixture.port,
      user: 'fixture',
      pass: 'synthetic-password',
      securityType: SecurityType.ftpes,
      securityContext: FtpTlsFixture.trustedContext(),
      timeout: 3,
    );
    addTearDown(client.disconnect);
    await client.connect();
    await expectLater(
      client.listDirectoryContent(),
      throwsA(isA<TlsException>()),
    );
    expect(fixture.dataTlsConnections, 0);
  });
}
