import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/b2_operation_strings.dart';
import 'package:crisp_cloud/services/b2_client_adapter.dart';
import 'package:crisp_cloud/services/b2_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'B2 authorization failures preserve structured HTTP and response details',
    () async {
      final client = B2ClientAdapter(config: null);
      await expectLater(
        http.runWithClient(
          () => client.login('fixture-key', 'fixture-secret'),
          () => MockClient((_) async => http.Response('access denied', 403)),
        ),
        throwsA(
          isA<B2StateFailure>()
              .having((error) => error.code, 'code', B2OperationCode.api)
              .having((error) => error.arguments['status'], 'status', 403)
              .having(
                (error) => error.arguments['operation'],
                'operation',
                'b2_authorize_account',
              )
              .having(
                (error) => error.arguments['body'],
                'body',
                'access denied',
              ),
        ),
      );
      await expectLater(
        http.runWithClient(
          () => client.login('fixture-key', 'fixture-secret'),
          () => MockClient(
            (_) async =>
                http.Response(jsonEncode({'accountId': 'account'}), 200),
          ),
        ),
        throwsA(
          isA<B2StateFailure>().having(
            (error) => error.code,
            'code',
            B2OperationCode.authorizationResponse,
          ),
        ),
      );
    },
  );

  test(
    'unauthenticated B2 retains StateError and its legacy message',
    () async {
      final adapter = B2ClientAdapter(config: null);
      await expectLater(
        adapter.downloadFileBytes('/report.pdf'),
        throwsA(
          isA<B2StateFailure>()
              .having((e) => e.code, 'code', B2OperationCode.unauthenticated)
              .having(
                (e) => e.toString(),
                'legacy text',
                'Bad state: Backblaze B2 is not authenticated.',
              ),
        ),
      );
      expect(
        B2FormatFailure(
          B2OperationCode.invalidJson,
          'B2 response is not valid JSON: bad',
        ),
        isA<FormatException>(),
      );
    },
  );
  testWidgets('B2 errors retain server details in every locale', (
    tester,
  ) async {
    final failure = B2StateFailure(
      B2OperationCode.api,
      'B2 b2_list_buckets failed with 403: denied',
      {'operation': 'b2_list_buckets', 'status': 403, 'body': 'denied'},
    );
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Text(localizedB2Error(context, failure)),
          ),
        ),
      );
      expect(find.textContaining('b2_list_buckets'), findsOneWidget);
      expect(find.textContaining('403'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{status}'), findsNothing);
    }
  });
}
