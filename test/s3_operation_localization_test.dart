import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/panel_error_strings.dart';
import 'package:crisp_cloud/l10n/provider_operation_strings.dart';
import 'package:crisp_cloud/providers/error_provider.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/s3_operation_failure.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('S3 HTTP connection failure preserves response and legacy message',
      () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 403;
      request.response.write('provider detail');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final client = S3ClientAdapter(
        config: S3ConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    ));
    await expectLater(
      client.login(
          'access@http://127.0.0.1:${server.port}/bucket?region=us-east-1',
          'secret'),
      throwsA(isA<S3OperationFailure>()
          .having((e) => e.code, 'code', S3OperationCode.connection)
          .having((e) => e.arguments['status'], 'status', 403)
          .having((e) => e.arguments['body'], 'body', 'provider detail')
          .having((e) => e.toString(), 'legacy text',
              'Exception: S3 connection test failed (HTTP 403): provider detail')),
    );
  });

  testWidgets('S3 errors and nested panel errors retain details in all locales',
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
      final cause = S3OperationFailure(
          S3OperationCode.delete,
          'S3 delete failed (HTTP 403): provider detail',
          {'status': 403, 'body': 'provider detail'});
      final direct = localizedProviderError(context, cause);
      expect(direct, contains('403'));
      expect(direct, contains('provider detail'));
      final wrapped = AppError('Delete failed: $cause',
          code: PanelErrorCode.deleteFailed, arguments: {'error': cause});
      expect(localizedPanelError(context, wrapped), contains(direct));
      expect(
          localizedPanelError(
              context, AppError(cause.toString(), cause: cause)),
          direct);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('S3 remote paths with placeholder-like text remain unchanged',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    final error = S3OperationFailure(S3OperationCode.missingInterruptedUpload,
        'fallback', {'path': '/{status}'});
    expect(localizedProviderError(context, error), contains('/{status}'));
    expect(localizedKnownProviderError(context, Exception('external')), isNull);
  });
  testWidgets('every S3 error code has a complete message in every locale',
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
      for (final code in S3OperationCode.values) {
        final error = S3OperationFailure(code, 'fallback', {
          'status': 403,
          'body': 'server detail',
          'path': '/test',
          'part': 5,
        });
        final result = localizedKnownProviderError(context, error);
        expect(result, isNotNull, reason: '${locale.languageCode}: $code');
        expect(result, isNot('fallback'),
            reason: '${locale.languageCode}: $code');
        expect(result, isNot(contains('{')),
            reason: '${locale.languageCode}: $code');
      }
    }
  });
}
