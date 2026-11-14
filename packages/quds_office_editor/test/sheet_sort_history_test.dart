import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SheetEditorController _controller({OfficeInteractionMode? mode}) {
  final book = SmlWorkbook(
    sheets: [
      SmlWorksheet(name: 'Sort here', sheetId: 1),
      SmlWorksheet(name: 'Neighbor', sheetId: 2),
    ],
  );
  book.firstSheet.cellA1('A1').value = 'Header';
  book.firstSheet.cellA1('A2')
    ..value = 2
    ..locked = false
    ..borderRgb = 'FF0000'
    ..borderWidth = 2;
  book.firstSheet.cellA1('A3')
    ..value = 1
    ..borderRgb = '0000FF'
    ..borderWidth = 0.75;
  book.sheets[1].cellA1('A1').value = 'Unchanged';
  final controller = SheetEditorController(
    workbook: book,
    config: OfficeSurfaceConfig(mode: mode ?? OfficeInteractionMode.editing),
  );
  addTearDown(controller.dispose);
  _select(controller, 'A1', 'A3');
  return controller;
}

void _select(SheetEditorController controller, String first, String last) {
  controller.selection
    ..anchor = SmlCellRef.parse(first)
    ..focus = SmlCellRef.parse(last);
}

List<Object?> _values(SmlWorksheet sheet) => [
  for (final address in ['A1', 'A2', 'A3']) sheet.cellA1(address).value,
];

void _edit(SheetEditorController controller, String address, String text) {
  controller.selection.selectCell(SmlCellRef.parse(address));
  controller.beginCellEdit(initial: text, replace: true);
  controller.commitCellEdit();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sort becomes dirty and history stays on its owning sheet', () {
    final controller = _controller();
    final target = controller.sheet;
    final revision = controller.contentRevision;
    controller.sortSelection();
    expect(_values(target), ['Header', 1, 2]);
    expect(controller.contentRevision, revision + 1);
    expect(controller.isDirty, isTrue);
    expect(controller.canUndo, isTrue);
    expect(target.cellA1('A2').locked, isTrue);
    expect(target.cellA1('A2').borderRgb, '0000FF');
    expect(target.cellA1('A3').locked, isFalse);
    expect(target.cellA1('A3').borderWidth, 2);

    controller.setActiveSheet(1);
    final neighbor = controller.sheet;
    controller.undo();
    expect(_values(target), ['Header', 2, 1]);
    expect(target.cellA1('A2').locked, isFalse);
    expect(target.cellA1('A2').borderRgb, 'FF0000');
    expect(controller.sheet, same(neighbor));
    expect(neighbor.allCells.map((cell) => cell.value), ['Unchanged']);
    controller.redo();
    expect(_values(target), ['Header', 1, 2]);
    expect(controller.sheet, same(neighbor));
    expect(neighbor.allCells.map((cell) => cell.value), ['Unchanged']);
    expect(controller.contentRevision, revision + 3);
  });

  test('sort undo and redo compose with earlier and later cell text edits', () {
    final controller = _controller();
    final target = controller.sheet;
    target.cellA1('B3').value = 'Label';
    _edit(controller, 'A2', '4');
    _select(controller, 'A1', 'B3');
    controller.sortSelection();
    expect(_values(target), ['Header', 1, 4]);
    expect(target.cellA1('B2').value, 'Label');
    _edit(controller, 'B2', 'Changed label');
    controller.undo();
    expect(target.cellA1('B2').value, 'Label');
    controller.undo();
    expect(_values(target), ['Header', 4, 1]);
    expect(target.cellOrNull(const SmlCellRef(1, 1)), isNull);
    controller.undo();
    expect(_values(target), ['Header', 2, 1]);
    controller.redo();
    expect(_values(target), ['Header', 4, 1]);
    controller.redo();
    expect(_values(target), ['Header', 1, 4]);
    controller.redo();
    expect(target.cellA1('B2').value, 'Changed label');
  });

  test('a pending cell edit is committed before its sort history entry', () {
    final controller = _controller();
    controller.selection.selectCell(const SmlCellRef(0, 1));
    controller.beginCellEdit(initial: '0', replace: true);
    _select(controller, 'A1', 'A3');
    controller.sortSelection(ascending: false);
    expect(controller.cellEditor.editing, isFalse);
    expect(_values(controller.sheet), ['Header', 1, 0]);
    controller.undo();
    expect(_values(controller.sheet), ['Header', 0, 1]);
    controller.undo();
    expect(_values(controller.sheet), ['Header', 2, 1]);
  });

  test('header-only and single-body-row selections do not create history', () {
    final controller = _controller();
    _select(controller, 'A1', 'A1');
    controller.sortSelection();
    _select(controller, 'A1', 'A2');
    controller.sortSelection();
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(controller.contentRevision, 0);
    expect(_values(controller.sheet), ['Header', 2, 1]);
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode blocks sorting without history or dirty changes', () {
      final controller = _controller(mode: mode);
      controller.sortSelection();
      expect(_values(controller.sheet), ['Header', 2, 1]);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.contentRevision, 0);
    });
  }

  test(
    'sorted values survive saved bytes and undo remains available',
    () async {
      final controller = _controller();
      controller.sortSelection();
      final sorted = SheetDeserializer().read(
        OpcPackage.openBytes(await controller.saveBytesAsync()),
      );
      expect(_values(sorted.firstSheet), ['Header', 1, 2]);
      controller.markClean();
      controller.undo();
      expect(controller.isDirty, isTrue);
      final restored = SheetDeserializer().read(
        OpcPackage.openBytes(controller.saveBytes()),
      );
      expect(_values(restored.firstSheet), ['Header', 2, 1]);
    },
  );
}
