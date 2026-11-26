import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  testWidgets('the sheet editor gives the active cell an editable fx bar', (
    tester,
  ) async {
    final controller = SheetEditorController(
      workbook: SmlWorkbook(
        sheets: <SmlWorksheet>[
          SmlWorksheet(name: 'Sheet1', sheetId: 1)..cellA1('A1').value = 5,
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: QudsSheetEditor(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    final cell = controller.activeCell;

    expect(find.text('fx'), findsOneWidget);
    final bar = find.byKey(const ValueKey<String>('sheet-formula-input'));
    expect(bar, findsOneWidget);
    final field = tester.widget<EditableText>(bar);
    expect(field.controller.text, controller.formulaBarText);

    await tester.tap(bar);
    await tester.pump();
    expect(field.focusNode.hasPrimaryFocus, isTrue);
    tester.testTextInput.enterText('=2+3');
    await tester.pump();
    expect(controller.formulaBarText, '=2+3');
    // The draft belongs to the formula bar until it is committed.
    expect(controller.sheet.cell(cell).formula, isNot('=2+3'));

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.sheet.cell(cell).formula, '=2+3');
    expect(tester.takeException(), isNull);
  });
}
