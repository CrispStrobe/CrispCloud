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
        r'\{\{[^{}]*\}\}|\{\d+\}|\{[A-Za-z][A-Za-z0-9_]*\}|<\w+>|\bdataSet\b|\bRow\.(?:color|code|amount|total)\b|\bstats\.sum\b|\bEPSG:4326\b|\bQudsReport\b|\.qrep\b|#hex');
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

  test('dynamic report diagnostics localize while retaining user data', () {
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      final function =
          strings.diagnostic('Unknown function MYFUNC() in "source" at 9');
      expect(function, contains('MYFUNC()'), reason: language);
      expect(function, contains('"source"'), reason: language);
      expect(function, contains('9'), reason: language);
      expect(function, isNot(startsWith('Unknown function')), reason: language);
      final invalid = strings.diagnostic('Invalid number width="{0}"');
      expect(invalid, contains('width'), reason: language);
      expect(invalid, contains('{0}'), reason: language);
      expect(invalid, isNot(startsWith('Invalid number')), reason: language);
      final enumError = strings.diagnostic(
          'Invalid orientation="sideways" (expected portrait, landscape)');
      expect(enumError, contains('orientation'), reason: language);
      expect(enumError, contains('sideways'), reason: language);
      expect(enumError, contains('portrait, landscape'), reason: language);
      final arguments =
          strings.diagnostic('SUM() expects 1–3 argument(s), got 4');
      expect(arguments, contains('SUM()'), reason: language);
      expect(arguments, contains('1–3'), reason: language);
      expect(arguments, contains('4'), reason: language);
      expect(arguments, isNot('SUM() expects 1–3 argument(s), got 4'),
          reason: language);
      final length = strings.diagnostic(
          'ReportFormatException: Unknown length unit "xx" in "12xx"');
      expect(length, contains('xx'), reason: language);
      expect(length, contains('12xx'), reason: language);
      expect(length, isNot(contains('ReportFormatException')),
          reason: language);
      final nonNumber = strings.diagnostic('"12x" is not a number');
      expect(nonNumber, contains('12x'), reason: language);
      expect(nonNumber, isNot('"12x" is not a number'), reason: language);
      final badValue = strings.diagnostic('"{1}" is not a valid date');
      expect(badValue, contains('{1}'), reason: language);
      expect(badValue, contains('date'), reason: language);
      expect(badValue, isNot('"{1}" is not a valid date'), reason: language);
      final duplicate =
          strings.diagnostic('Element name "Revenue" is used more than once');
      expect(duplicate, contains('Revenue'), reason: language);
      expect(duplicate, isNot('Element name "Revenue" is used more than once'),
          reason: language);
      final mismatch =
          strings.diagnostic('RowTemplate has 3 cells for 5 columns');
      expect(mismatch, contains('3'), reason: language);
      expect(mismatch, contains('5'), reason: language);
      expect(mismatch, isNot('RowTemplate has 3 cells for 5 columns'),
          reason: language);
      expect(strings.diagnostic('unrecognized host error'),
          'unrecognized host error');
    }
    expect(
        ReportDesignerStrings.english.diagnostic('Unknown function MYFUNC()'),
        'Unknown function MYFUNC()');
  });

  test('dynamic status translations do not reinterpret file names', () {
    for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportDesignerStrings.forLocale(Locale(language));
      final message = strings.format('Could not load {name}: {error}',
          {'name': '{error}.ttf', 'error': 'denied'});
      expect(message, contains('{error}.ttf'), reason: language);
      expect(message, contains('denied'), reason: language);
      expect(message, isNot(startsWith('Could not load')), reason: language);
      final rename = strings.format('Rename column "{name}"', {'name': 'Q1'});
      expect(rename, contains('Q1'), reason: language);
      expect(rename, isNot('Rename column "Q1"'), reason: language);
      expect(strings.format('{count} selected', {'count': 3}), contains('3'),
          reason: language);
    }
  });

  test('band captions localize interface labels without changing data paths',
      () {
    final band = ReportBand(
        kind: ReportBandKind.detail,
        dataSet: 'Data.items',
        groupBy: 'Row.category');
    expect(RenderReportDesigner.captionOf(band),
        'Detail  ·  data: Data.items  ·  group: Row.category');
    final label =
        RenderReportDesigner.captionOf(band, strings: ReportDesignerStrings.de);
    expect(label, contains('Daten: Data.items'));
    expect(label, contains('Gruppe: Row.category'));
  });

  testWidgets('preview semantics update when the selected locale changes',
      (tester) async {
    final handle = tester.ensureSemantics();
    Widget host(ReportDesignerStrings strings) => MaterialApp(
          home: Scaffold(
              body: ReportPreviewSurface(document: null, strings: strings)),
        );
    await tester.pumpWidget(host(ReportDesignerStrings.english));
    expect(find.bySemanticsLabel('Report preview'), findsOneWidget);
    await tester.pumpWidget(host(ReportDesignerStrings.de));
    await tester.pump();
    expect(find.bySemanticsLabel('Berichtsvorschau'), findsOneWidget);
    handle.dispose();
  });

  test('inspector headings translate prefixes and preserve user names', () {
    const strings = ReportDesignerStrings.de;
    expect(strings.inspectorTitle('Report: My report', objectSelected: false),
        'Bericht: My report');
    expect(strings.inspectorTitle('Band: PageHeader', objectSelected: false),
        'Band: Seitenkopf');
    expect(strings.inspectorTitle('2 elements', objectSelected: false),
        '2 Elemente');
    expect(strings.inspectorTitle('Report: My object', objectSelected: true),
        'Report: My object');
    expect(strings.inspectorTitle('2 elements', objectSelected: true),
        '2 elements');
    expect(strings.inspectorTitle('Data', objectSelected: true), 'Data');
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
