import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('report toolbar help is translated in all supported locales', () {
    const tooltips = [
      'Start from a ready-made report',
      'Insert or edit template variables',
      'Undo (Ctrl+Z)',
      'Redo (Ctrl+Y)',
      'Duplicate (Ctrl+D)',
      'Delete (Del)',
      'Bring to front',
      'Send to back',
      'Add band',
      'Grid and snapping',
      'Zoom out (Ctrl+-)',
      'Zoom in (Ctrl+=)',
      'Fit page width',
      'Export with preview data',
      'Print with preview data (Ctrl+P)',
    ];
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      expect(strings.languageCode, language);
      for (final tooltip in tooltips) {
        expect(strings.t(tooltip), isNot(tooltip),
            reason: '$language: $tooltip');
      }
    }
    expect(ReportDesignerStrings.forLocale(const Locale('xx')),
        same(ReportDesignerStrings.english));
  });

  test('report inspector labels use localized text', () {
    const labels = [
      'Report properties',
      'Shared properties of the selection',
      'Font family',
      'Visible when',
      'Padding',
      'Keep together',
      'Word wrap',
      'Import image…',
      'New folder',
      'Delete folder',
      'No embedded fonts yet',
      'Axis minimum',
      'Filter installed fonts',
      'Remove band',
      'Pick a color',
    ];
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      for (final label in labels) {
        expect(strings.t(label), isNot(label), reason: '$language: $label');
      }
    }
  });

  test('report diagnostics translate and retain technical tokens', () {
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      expect(strings.t('Unreadable file'), isNot('Unreadable file'),
          reason: language);
      expect(strings.t('Root element must be <QudsReport>'),
          contains('<QudsReport>'),
          reason: language);
      expect(strings.t('Unclosed "{{"'), contains('{{'), reason: language);
      final diagnostic =
          strings.diagnostic('Unknown function in "example" at 9');
      expect(diagnostic, contains('"example"'), reason: language);
      expect(diagnostic, contains('9'), reason: language);
    }
  });

  test('report locales cover the reference catalog and retain template tokens',
      () {
    final reference = ReportDesignerStrings.arabic.translatedKeys.toSet();
    final tokens = RegExp(
        r'\{\{[^{}]*\}\}|<\w+>|\bdataSet\b|\bRow\.(?:color|code|amount|total)\b|\bstats\.sum\b|\bEPSG:4326\b|\bQudsReport\b|\.qrep\b');
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      expect(reference.difference(strings.translatedKeys.toSet()), isEmpty,
          reason: language);
      for (final source in reference) {
        for (final match in tokens.allMatches(source)) {
          expect(strings.t(source), contains(match.group(0)),
              reason: '$language: $source');
        }
      }
    }
  });

  test('report counts follow the selected language', () {
    const nouns = [
      'element',
      'variable',
      'image',
      'family',
      'font',
      'band',
      'problem',
      'error',
      'warning',
      'row',
      'column',
      'field',
      'value',
    ];
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      for (final noun in nouns) {
        expect(strings.count(1, noun), startsWith('1'),
            reason: '$language: $noun');
        expect(strings.count(2, noun), startsWith('2'),
            reason: '$language: $noun');
      }
    }
    expect(ReportDesignerStrings.de.count(1, 'row'), '1 Zeile');
    expect(ReportDesignerStrings.de.count(2, 'row'), '2 Zeilen');
    expect(ReportDesignerStrings.fr.count(0, 'row'), '0 ligne');
    expect(ReportDesignerStrings.zh.count(3, 'row'), '3行');
    expect(ReportDesignerStrings.english.count(2, 'row'), '2 rows');
    expect(ReportDesignerStrings.arabic.count(2, 'row'), 'صفان');
  });

  testWidgets(
      'context menu search hint follows locale without forcing a filter',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () => OfficeContextMenu.show(
            context: context,
            globalPosition: const Offset(200, 100),
            actions: [
              for (var i = 0; i < 9; i++)
                OfficeContextAction(id: '$i', label: 'Action $i'),
            ],
            onSelect: (_) {},
          ),
          child: const Text('Open'),
        );
      })),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Zum Suchen eingeben'), findsOneWidget);
  });
}
