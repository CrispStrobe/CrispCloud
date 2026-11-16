import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  test('a controller starts on the first visible worksheet', () {
    final workbook = SmlWorkbook(
      sheets: [
        SmlWorksheet(name: 'Hidden', sheetId: 1, hidden: true),
        SmlWorksheet(name: 'Visible', sheetId: 2),
      ],
    );
    final controller = SheetEditorController(workbook: workbook);
    addTearDown(controller.dispose);
    expect(controller.activeSheetIndex, 1);
    expect(controller.sheet.name, 'Visible');
  });
}
