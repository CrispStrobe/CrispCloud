import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/office_surface_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/office_editor_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('embedded editor strings resolve for $language',
        (tester) async {
      late OfficeStrings strings;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          strings = OfficeSurfaceStrings.of(context);
          return Text(strings.cut);
        }),
      ));
      final values = OfficeSurfaceStrings.values(strings);
      expect(values, hasLength(82));
      expect(values.every((value) => value.isNotEmpty), isTrue);
      final english = OfficeSurfaceStrings.values(OfficeStrings.english);
      for (var index = 0; index < values.length; index++) {
        // French uses the same word "Page" as English in two fields.
        if (language == 'fr' && english[index] == 'Page') continue;
        expect(values[index], isNot(english[index]),
            reason: '$language field $index (${english[index]})');
      }
      expect(strings.wordEditor, isNot(OfficeStrings.english.wordEditor));
      expect(strings.cut, isNot(OfficeStrings.english.cut));
      expect(strings.pictureHint, isNot(OfficeStrings.english.pictureHint));
      if (language == 'ar') {
        expect(identical(strings, OfficeStrings.arabic), isTrue);
      }
    });
  }

  testWidgets('open editor updates embedded labels when locale changes',
      (tester) async {
    final bytes = (DocxDocumentBuilder()..paragraph('Hello')).build();
    final file = FileItem(name: 'report.docx', isFolder: false);
    Widget host(Locale locale) => ProviderScope(
          child: MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: OfficeEditorDialog(
                file: file, side: PanelSide.local, bytesOverride: bytes),
          ),
        );

    await tester.pumpWidget(host(const Locale('en')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
        tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .config!
            .strings
            .cut,
        'Cut');

    await tester.pumpWidget(host(const Locale('de')));
    await tester.pump();
    expect(
        tester
            .widget<QudsWordEditor>(find.byType(QudsWordEditor))
            .config!
            .strings
            .cut,
        'Ausschneiden');
    await tester.pumpWidget(const SizedBox());
  });
}
