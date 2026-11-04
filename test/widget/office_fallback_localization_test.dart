import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_editor_strings.dart';
import 'package:crisp_cloud/l10n/office_fallback_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('close confirmation keeps the filename in every supported language', () {
    for (final code in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final message = OfficeFallbackStrings.closeConfirmation(code, 'report.docx');
      expect(message, contains('report.docx'));
      expect(message, isNot(contains('{filename}')));
    }
    expect(OfficeFallbackStrings.closeConfirmation('ja', 'report.docx'),
        '閉じる前に report.docx への変更を保存しますか？');
    expect(OfficeFallbackStrings.closeConfirmation('it', 'report.docx'),
        'Save changes to report.docx before closing?');
  });
  testWidgets('Office save failure is translated in each non-English locale', (tester) async {
    for (final language in ['fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Text(
          OfficeEditorStrings.translate(context, 'Save failed'),
        )),
      ));
      expect(find.text('Save failed'), findsNothing, reason: language);
    }
  });
  testWidgets('unknown Office labels keep English fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Text(
        OfficeEditorStrings.translate(context, 'Unknown command'),
      )),
    ));
    expect(find.text('Unknown command'), findsOneWidget);
  });
}
