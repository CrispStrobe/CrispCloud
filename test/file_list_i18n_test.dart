import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/file_list_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('file list labels preserve translations and placeholders', () {
    final translations = FileListStrings.translations;
    expect(translations.keys.toSet(), {
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    final keys = translations['de']!.keys.toSet();
    for (final locale in translations.entries) {
      expect(locale.value.keys.toSet(), keys, reason: locale.key);
      for (final entry in locale.value.entries) {
        expect(entry.value, isNotEmpty, reason: '${locale.key}: ${entry.key}');
        for (final match in RegExp(r'\{[^}]+\}').allMatches(entry.key)) {
          expect(entry.value, contains(match.group(0)), reason: locale.key);
        }
      }
    }
    final strings = FileListStrings.forLanguage('de');
    expect(
      strings.semantic(folder: false, name: 'a.txt', selected: true),
      'Datei a.txt, unbekannte Größe, ausgewählt',
    );
  });

  testWidgets('compact file tile exposes localized screen reader text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final file = FileItem(name: 'a.txt', isFolder: false, size: 100);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: CompactFileTile(
              file: file,
              side: PanelSide.local,
              isSelected: true,
              onTap: (_, __) {},
              onDoubleTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.startsWith('Datei a.txt,') ?? false) &&
            (widget.properties.label?.endsWith('ausgewählt') ?? false),
      ),
      findsOneWidget,
    );
  });
}
