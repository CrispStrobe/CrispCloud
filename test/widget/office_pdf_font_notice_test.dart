import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_pdf_font_notice_strings.dart';
import 'package:crisp_cloud/services/office_pdf_service.dart';
import 'package:crisp_cloud/widgets/office_pdf_font_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficePdfFontReport _report({
  List<int> missing = const [],
  List<OfficeFontSubstitution> substitutions = const [],
  bool truncated = false,
}) => OfficePdfFontReport(
  missingCodePoints: missing,
  substitutions: substitutions,
  diagnosticsTruncated: truncated,
);

const _details = ValueKey('office-pdf-font-details');
const _close = ValueKey('office-pdf-font-close');
const _missing = ValueKey('office-pdf-font-missing');
const _substitutions = ValueKey('office-pdf-font-substitutions');
const _limited = ValueKey('office-pdf-font-limited');

Future<void> _show(
  WidgetTester tester,
  OfficePdfFontReport report, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          OfficePdfFontNotice(report: report),
          const Expanded(child: Center(child: Text('Existing PDF pane'))),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('clean PDF result does not reserve notice space', (tester) async {
    await _show(tester, _report());
    expect(find.byKey(_details), findsNothing);
    expect(find.byKey(const ValueKey('office-pdf-font-notice')), findsNothing);
    expect(tester.getSize(find.byType(OfficePdfFontNotice)).height, 0);
    expect(find.text('Existing PDF pane'), findsOneWidget);
  });

  testWidgets(
    'substitutions are visible and actual font families are selectable',
    (tester) async {
      await _show(
        tester,
        _report(
          substitutions: const [
            OfficeFontSubstitution('Times New Roman', 'Liberation Serif'),
            OfficeFontSubstitution('Calibri', 'Carlito'),
          ],
        ),
      );
      expect(
        find.text('Substitute fonts are used; page layout may differ.'),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(OfficePdfFontNotice)).height,
        lessThanOrEqualTo(72),
      );
      await tester.tap(find.byKey(_details));
      await tester.pumpAndSettle();
      final text = tester.widget<SelectableText>(find.byKey(_substitutions));
      expect(
        text.data,
        'Times New Roman → Liberation Serif\nCalibri → Carlito',
      );
      expect(find.byKey(_missing), findsNothing);
      expect(find.byKey(_limited), findsNothing);
      expect(find.textContaining('original application'), findsOneWidget);
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Existing PDF pane'), findsOneWidget);
    },
  );

  testWidgets('missing characters show code points and complementary views', (
    tester,
  ) async {
    await _show(tester, _report(missing: [0x4e2d, 0x1f680]));
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    await tester.tap(find.byKey(_details));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byKey(_missing)).data,
      'U+4E2D  U+1F680',
    );
    expect(find.textContaining('Formatted view'), findsOneWidget);
    expect(find.textContaining('installed application'), findsOneWidget);
    expect(find.byKey(_substitutions), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caps displayed diagnostics and sanitizes font-name controls', (
    tester,
  ) async {
    await _show(
      tester,
      _report(
        missing: List.generate(1000, (index) => 0x4e00 + index),
        substitutions: [
          OfficeFontSubstitution(
            '${'A' * 300}\nInjected',
            'Resolved\nFamily\u202e',
          ),
          for (var index = 1; index < 1000; index++)
            OfficeFontSubstitution('Requested $index', 'Resolved $index'),
        ],
      ),
    );
    await tester.tap(find.byKey(_details));
    await tester.pumpAndSettle();
    final values = tester.widget<SelectableText>(find.byKey(_missing)).data!;
    expect(RegExp(r'U\+[0-9A-F]+').allMatches(values), hasLength(64));
    expect(values, isNot(contains('U+4E40')));
    final families = tester
        .widget<SelectableText>(find.byKey(_substitutions))
        .data!;
    expect(families.split('\n'), hasLength(32));
    expect(families, contains('${'A' * 96}… → Resolved Family '));
    expect(families, isNot(contains('Requested 32')));
    expect(families, isNot(contains('\u202e')));
    expect(find.byKey(_limited), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'exporter truncation remains visible even without retained entries',
    (tester) async {
      await _show(tester, _report(truncated: true));
      expect(
        find.text('Font information is limited; page layout may differ.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(_details));
      await tester.pumpAndSettle();
      expect(find.byKey(_limited), findsOneWidget);
      expect(find.byKey(_missing), findsNothing);
      expect(find.byKey(_substitutions), findsNothing);
    },
  );

  testWidgets('all nine localized notices fit beside the existing PDF pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final locale in AppLocalizations.supportedLocales) {
      await _show(
        tester,
        _report(
          missing: [0x4e2d],
          substitutions: const [OfficeFontSubstitution('Calibri', 'Carlito')],
        ),
        locale: locale,
        scale: 1.4,
      );
      await tester.pumpAndSettle();
      final strings = OfficePdfFontNoticeStrings(locale);
      expect(find.text(strings.text('summaryBoth')), findsOneWidget);
      expect(
        tester.getSize(find.byType(OfficePdfFontNotice)).height,
        lessThanOrEqualTo(96),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '${locale.languageCode} notice',
      );
      await tester.tap(find.byKey(_details));
      await tester.pumpAndSettle();
      expect(find.text(strings.text('title')), findsOneWidget);
      expect(find.byKey(_missing), findsOneWidget);
      expect(find.byKey(_substitutions), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: '${locale.languageCode} details',
      );
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
    }
  });
}
