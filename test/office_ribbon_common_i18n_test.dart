import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_editor_strings.dart';
import 'package:crisp_cloud/l10n/office_ribbon_common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('common ribbon translations cover all seven languages and shortcuts',
      () {
    const translations = OfficeRibbonCommonStrings.translations;
    expect(translations.keys.toSet(),
        {'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar'});
    final keys = translations['fr']!.keys.toSet();
    expect(
        keys,
        containsAll([
          'Heading 2',
          'Heading 7',
          'Heading 8',
          'Heading 9',
          'Words',
          'No shading',
          'Spell checking uses the host integration. No spell-check provider is configured in this build.'
        ]));
    for (final locale
        in translations.entries.where((entry) => entry.key != 'de')) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      expect(locale.value.values.every((value) => value.isNotEmpty), isTrue,
          reason: locale.key);
      for (final shortcut in ['Ctrl+B', 'Ctrl+I', 'Ctrl+U', 'Ctrl+F']) {
        final source =
            locale.value.keys.singleWhere((key) => key.contains(shortcut));
        expect(locale.value[source], contains(shortcut), reason: locale.key);
      }
    }
  });

  testWidgets('existing office translation resolves newly translated controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) {
        return Text(OfficeEditorStrings.translate(context, 'Bold (Ctrl+B)'));
      }),
    ));
    expect(find.text('Gras (Ctrl+B)'), findsOneWidget);
  });
}
