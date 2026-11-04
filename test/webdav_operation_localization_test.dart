import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/webdav_operation_strings.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_operation_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invalid identity retains its legacy exception text', () async {
    final adapter = WebDavClientAdapter(config: null);
    await expectLater(adapter.login('invalid', 'password'), throwsA(
      isA<WebDavException>()
          .having((e) => e.code, 'code', WebDavOperationCode.invalidIdentity)
          .having((e) => e.toString(), 'legacy text', 'Exception: Format must be user@ServerURL'),
    ));
    expect(WebDavUnsupportedError(WebDavOperationCode.webDownload,
        'Use the browser download stream on web'), isA<UnsupportedError>());
  });
  testWidgets('list failures retain path and remote detail in each locale', (tester) async {
    final failure = WebDavException(WebDavOperationCode.listFailed,
        'Failed to list path /docs: denied', {'path': '/docs', 'error': 'denied'});
    for (final locale in AppLocalizations.supportedLocales) {
      await tester.pumpWidget(MaterialApp(
        locale: locale, supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(localizedWebDavError(context, failure))),
      ));
      expect(find.textContaining('/docs'), findsOneWidget);
      expect(find.textContaining('denied'), findsOneWidget);
      expect(find.textContaining('{path}'), findsNothing);
    }
  });
}
