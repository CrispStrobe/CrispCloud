import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/widgets/office_worksheet_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  testWidgets('hidden worksheets stay out of the selector', (tester) async {
    final controller = SheetEditorController(
      workbook: SmlWorkbook(
        sheets: [
          SmlWorksheet(name: 'Hidden', sheetId: 1, hidden: true),
          SmlWorksheet(name: 'Visible', sheetId: 2),
          SmlWorksheet(name: 'Also hidden', sheetId: 3, hidden: true),
        ],
      ),
    );
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OfficeWorksheetBar(
            controller: controller,
            editorFocusNode: focus,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.activeSheetIndex, 1);
    expect(controller.sheet.name, 'Visible');
    await tester.tap(find.byKey(const Key('office-worksheet-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Visible'), findsWidgets);
    expect(find.text('Hidden'), findsNothing);
    expect(find.text('Also hidden'), findsNothing);
  });
}
