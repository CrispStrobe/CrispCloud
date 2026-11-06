import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/nextcloud_operation_strings.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/nextcloud_operation_failure.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nextcloud preserves HTTP body and legacy text in structured failure', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'PROPFIND') {
        request.response.statusCode = request.uri.path.endsWith('/new-folder')
            ? 404
            : 207;
      } else {
        request.response.statusCode = 403;
        request.response.write('provider detail');
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final client = NextcloudClientAdapter(
      config: NextcloudConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      ),
    );
    await client.login('user@http://127.0.0.1:${server.port}', 'password');
    await expectLater(
      client.deletePath('/example.txt'),
      throwsA(
        isA<NextcloudOperationFailure>()
            .having((e) => e.code, 'code', NextcloudOperationCode.delete)
            .having((e) => e.arguments['status'], 'status', 403)
            .having((e) => e.arguments['body'], 'body', 'provider detail')
            .having(
              (e) => e.toString(),
              'legacy text',
              'Exception: Nextcloud delete failed (HTTP 403): provider detail',
            ),
      ),
    );
    for (final operation in <(NextcloudOperationCode, Future<void> Function())>[
      (
        NextcloudOperationCode.download,
        () async {
          await client.downloadFileBytes('/example.txt');
        },
      ),
      (
        NextcloudOperationCode.move,
        () async {
          await client.movePath('/example.txt', '/renamed.txt');
        },
      ),
      (
        NextcloudOperationCode.share,
        () async {
          await client.createShareLink('/example.txt');
        },
      ),
      (
        NextcloudOperationCode.restoreVersion,
        () async {
          await client.restoreVersion('file', 'version', '/example.txt');
        },
      ),
      (
        NextcloudOperationCode.rangeDownload,
        () async {
          await client.downloadRange('/example.txt', 0, 4);
        },
      ),
      (
        NextcloudOperationCode.createFolder,
        () async {
          await client.createFolderPath('/new-folder');
        },
      ),
    ]) {
      await expectLater(
        operation.$2(),
        throwsA(
          isA<NextcloudOperationFailure>()
              .having((error) => error.code, 'operation', operation.$1)
              .having((error) => error.arguments['status'], 'HTTP status', 403)
              .having(
                (error) => localizedNextcloudErrorForLanguage('de', error),
                'complete translation',
                isNot(contains('{')),
              ),
        ),
      );
    }
  });

  testWidgets(
    'nested provider errors localize without changing server details',
    (tester) async {
      const locales = AppLocalizations.supportedLocales;
      for (final locale in locales) {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: locales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        );
        final cause = NextcloudOperationFailure(
          NextcloudOperationCode.delete,
          'Nextcloud delete failed (HTTP 403): provider detail',
          {'status': 403, 'body': 'provider detail'},
        );
        expect(
          localizedNextcloudError(context, cause),
          contains('provider detail'),
        );
        final error = AppError(
          'Delete failed: $cause',
          code: PanelErrorCode.deleteFailed,
          arguments: {'error': cause},
        );
        final text = localizedPanelError(context, error);
        expect(text, contains('403'));
        expect(text, contains('provider detail'));
        expect(text, isNot(contains('{')));
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('placeholder-like text in remote paths stays intact', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final error = NextcloudOperationFailure(
      NextcloudOperationCode.list,
      'fallback',
      {'path': '/{status}', 'status': 403},
    );
    expect(localizedNextcloudError(context, error), contains('/{status}'));
  });
}
