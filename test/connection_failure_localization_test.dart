import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/connection_failure_strings.dart';
import 'package:crisp_cloud/services/connection_failure.dart';
import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_storage/crisp_storage.dart' show RemoteException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nextcloud HTTP failure preserves its status and existing message',
      () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final client = NextcloudClientAdapter(
        config: NextcloudConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    ));
    await expectLater(
        client.login('user@http://127.0.0.1:${server.port}', 'password'),
        throwsA(isA<ConnectionFailure>()
            .having((e) => e.code, 'code', ConnectionFailureCode.nextcloudHttp)
            .having((e) => e.arguments['status'], 'status', 503)
            .having((e) => e.toString(), 'message',
                'Exception: Connection test failed (HTTP 503)')));
  });

  test('SFTP failure remains a RemoteException', () {
    const error = SftpConnectionFailure();
    expect(error, isA<RemoteException>());
    expect(error.toString(),
        'SFTP connection failed. Check server access and credentials.');
  });

  testWidgets('connection errors preserve details in all locales',
      (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        }),
      ));
      const error = ConnectionFailure(ConnectionFailureCode.nextcloudHttp,
          'Connection test failed (HTTP 503)', {'status': 503});
      expect(localizedConnectionFailure(context, error), contains('503'));
      const oauth = ConnectionFailure(
          ConnectionFailureCode.oauthCancelled,
          'Example authorization was cancelled or failed',
          {'provider': 'Example'});
      expect(localizedConnectionFailure(context, oauth), contains('Example'));
      expect(localizedConnectionFailure(context, const SftpConnectionFailure()),
          isNotEmpty);
      expect(localizedConnectionFailure(context, Exception('external detail')),
          isNull);
    }
  });
}
