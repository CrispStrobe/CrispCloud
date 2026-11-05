import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/b2_operation_strings.dart';
import 'package:crisp_cloud/services/b2_client_adapter.dart';
import 'package:crisp_cloud/services/b2_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unauthenticated B2 retains StateError and its legacy message', () async {
    final adapter = B2ClientAdapter(config: null);
    await expectLater(adapter.downloadFileBytes('/report.pdf'), throwsA(
      isA<B2StateFailure>()
          .having((e) => e.code, 'code', B2OperationCode.unauthenticated)
          .having((e) => e.toString(), 'legacy text', 'Bad state: Not authenticated'),
    ));
    expect(B2FormatFailure(B2OperationCode.invalidJson, 'B2 response is not valid JSON: bad'),
        isA<FormatException>());
  });
  testWidgets('B2 errors retain server details in every locale', (tester) async {
    final failure = B2StateFailure(B2OperationCode.api,
        'B2 b2_list_buckets failed with 403: denied',
        {'operation': 'b2_list_buckets', 'status': 403, 'body': 'denied'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedB2Error(context, failure))),
      ));
      expect(find.textContaining('b2_list_buckets'), findsOneWidget);
      expect(find.textContaining('403'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{status}'), findsNothing);
    }
  });
}
