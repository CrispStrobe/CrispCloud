import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SheetEditorController _controller() {
  final book = SmlWorkbook();
  book.firstSheet.cellA1('A1')
    ..value = 'Editable'
    ..locked = false
    ..borderRgb = '0070C0'
    ..borderWidth = 1.5;
  book.firstSheet.cellA1('B1').value = 'Locked';
  book.firstSheet.protection = SmlSheetProtection(enabled: true);
  final controller = SheetEditorController(workbook: book);
  addTearDown(controller.dispose);
  return controller;
}

void _expectCellState(SheetEditorController controller, String address) {
  final cell = controller.sheet.cellA1(address);
  expect(cell.value, 'Editable');
  expect(cell.locked, isFalse);
  expect(cell.borderRgb, '0070C0');
  expect(cell.borderWidth, 1.5);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fill undo and redo retain an unlocked cell and its PDF border', () {
    final controller = _controller();
    controller.setSelectionFillRgb('FFF2CC');
    _expectCellState(controller, 'A1');
    controller.undo();
    _expectCellState(controller, 'A1');
    expect(controller.sheet.cellA1('A1').fillRgb, isEmpty);

    // The modeled lock controls actual editing of a protected sheet.
    controller.beginCellEdit();
    expect(controller.cellEditor.editing, isTrue);
    controller.cancelCellEdit();
    controller.redo();
    _expectCellState(controller, 'A1');
    expect(controller.sheet.cellA1('A1').fillRgb, 'FFF2CC');
    expect(controller.sheet.cellA1('B1').locked, isTrue);
    expect(controller.sheet.cellA1('B1').borderRgb, isEmpty);
  });

  test('row deletion undo restores cell lock and PDF border through redo', () {
    final controller = _controller();
    controller.deleteSheetRows(index: 0);
    expect(controller.sheet.cellA1('A1').value, isNull);
    controller.undo();
    _expectCellState(controller, 'A1');
    controller.redo();
    expect(controller.sheet.cellA1('A1').value, isNull);
    controller.undo();
    _expectCellState(controller, 'A1');
    expect(controller.sheet.cellA1('B1').locked, isTrue);
    expect(controller.sheet.cellA1('B1').borderRgb, isEmpty);
  });
}
