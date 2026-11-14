import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

SheetEditorController _controller() {
  final first = SmlWorksheet(name: 'Original', sheetId: 1)
    ..cellA1('A1').value = 'Original';
  final second = SmlWorksheet(name: 'Neighbor', sheetId: 2)
    ..cellA1('A1').value = 'Neighbor';
  final controller = SheetEditorController(
    workbook: SmlWorkbook(sheets: [first, second]),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _edit(SheetEditorController controller, String text) {
  controller.beginCellEdit();
  controller.cellEditor.bridge.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  controller.commitPendingEdits();
}

Map<String, Object?> _cellState(SmlCell cell) => {
  'ref': cell.ref.a1,
  'type': cell.type,
  'value': cell.value,
  'formula': cell.formula,
  'styleIndex': cell.styleIndex,
  'explicitStyle': cell.hasExplicitStyleIndex,
  'alignment': cell.horizontalAlign,
  'fill': cell.fillRgb,
  'explicitFill': cell.hasExplicitFillColorEdit,
  'font': cell.fontRgb,
  'explicitFont': cell.hasExplicitFontColorEdit,
  'bold': cell.fontBold,
  'size': cell.fontSize,
  'border': cell.borderRgb,
  'borderWidth': cell.borderWidth,
  'locked': cell.locked,
};

Map<String, Object?> _gridState(SmlWorksheet sheet) => {
  'rows': {
    for (final entry in sheet.rows.entries) entry.key: entry.value.index,
  },
  'cells': {for (final cell in sheet.allCells) cell.ref.a1: _cellState(cell)},
  'columns': {
    for (final col in {
      ...sheet.columnWidths.keys,
      ...sheet.columnProperties.keys,
    })
      col: [
        sheet.columnWidth(col),
        sheet.exportColumnWidth(col),
        sheet.exportColumnProperties(col),
      ],
  },
  'heights': Map<int, double>.from(sheet.rowHeights),
  'merges': [for (final merge in sheet.merges) merge.a1],
};

void _expectCellLocations(SmlWorksheet sheet) {
  for (final row in sheet.rows.entries) {
    expect(row.value.index, row.key);
    for (final cell in row.value.cells.entries) {
      expect((cell.value.ref.col, cell.value.ref.row), (cell.key, row.key));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('grid undo and redo never replace a different worksheet', () {
    final controller = _controller();
    final owner = controller.sheet;
    final neighbor = controller.workbook.sheets[1];
    final neighborBefore = _gridState(neighbor);
    controller.setSelectionFillRgb('FF0000');
    controller.setActiveSheet(1);
    controller.undo();
    expect(_gridState(neighbor), neighborBefore);
    expect(owner.cellA1('A1').fillRgb, isEmpty);
    controller.redo();
    expect(owner.cellA1('A1').fillRgb, 'FF0000');
    expect(_gridState(neighbor), neighborBefore);
    expect(controller.activeSheetIndex, 1);
  });

  for (final fill in [true, false]) {
    test(
      '${fill ? 'fill' : 'font'} redo retains its original selected range',
      () {
        final controller = _controller();
        if (fill) {
          controller.setSelectionFillRgb('FF0000');
        } else {
          controller.setSelectionFontRgb('0070C0');
        }
        controller.undo();
        controller.selection.selectCell(const SmlCellRef(1, 0));
        controller.redo();
        final first = controller.sheet.cellA1('A1');
        expect(
          fill ? first.fillRgb : first.fontRgb,
          fill ? 'FF0000' : '0070C0',
        );
        final neighbor = controller.sheet.cellA1('B1');
        expect(fill ? neighbor.fillRgb : neighbor.fontRgb, isEmpty);
      },
    );
  }

  test(
    'a cell edit before grid history remains attached through undo redo',
    () {
      final controller = _controller();
      final original = controller.sheet.cellA1('A1');
      _edit(controller, 'Edited');
      controller.setSelectionFillRgb('FF0000');
      controller.undo();
      expect(controller.sheet.cellA1('A1'), same(original));
      controller.undo();
      expect(controller.sheet.cellA1('A1').value, 'Original');
      controller.redo();
      controller.redo();
      expect(controller.sheet.cellA1('A1'), same(original));
      expect(original.value, 'Edited');
      expect(original.fillRgb, 'FF0000');
    },
  );

  test('a cell created by grid formatting retains its later edit history', () {
    final controller = _controller();
    controller.selection.selectCell(const SmlCellRef(2, 0));
    expect(controller.sheet.cellOrNull(const SmlCellRef(2, 0)), isNull);
    controller.setSelectionFillRgb('FF0000');
    final created = controller.sheet.cellA1('C1');
    _edit(controller, 'Created then edited');
    controller.undo();
    controller.undo();
    expect(controller.sheet.cellOrNull(const SmlCellRef(2, 0)), isNull);
    controller.redo();
    expect(controller.sheet.cellA1('C1'), same(created));
    controller.redo();
    expect(controller.sheet.cellA1('C1').value, 'Created then edited');
    expect(created.fillRgb, 'FF0000');
  });

  for (final rows in [true, false]) {
    for (final deletion in [true, false]) {
      test('${rows ? 'row' : 'column'} ${deletion ? 'deletion' : 'insertion'} '
          'restores cells and metadata on its owning worksheet', () {
        final controller = _controller();
        final owner = controller.sheet;
        final neighbor = controller.workbook.sheets[1];
        final neighborBefore = _gridState(neighbor);
        final original = owner.cellA1('A1');
        final moved = owner.cellA1('B2')..value = 'Moved';
        owner.cellA1('C3').value = 'Last';
        owner.row(7); // An imported empty row must survive restoration too.
        owner.setRowHeight(1, 31.5);
        owner.importColumnWidth(1, 8.7109375);
        owner.columnProperties[1] = {'hidden': '1', 'style': '0'};
        owner.merges.add(SmlMerge(c0: 3, r0: 3, c1: 4, r1: 4));
        _edit(controller, 'Edited original');
        final before = _gridState(owner);
        if (rows) {
          if (deletion) {
            controller.deleteSheetRows(index: 0);
          } else {
            controller.insertSheetRows(index: 0, after: false);
          }
        } else if (deletion) {
          controller.deleteSheetCols(index: 0);
        } else {
          controller.insertSheetCols(index: 0, after: false);
        }
        final after = _gridState(owner);
        final movedRef = rows
            ? SmlCellRef(1, deletion ? 0 : 2)
            : SmlCellRef(deletion ? 0 : 2, 1);
        expect(owner.cell(movedRef), same(moved));
        _expectCellLocations(owner);
        controller.setActiveSheet(1);
        controller.selection.selectCell(const SmlCellRef(5, 8));
        controller.undo();
        expect(_gridState(neighbor), neighborBefore);
        expect(_gridState(owner), before);
        expect(owner.cellA1('A1'), same(original));
        expect(owner.cellA1('B2'), same(moved));
        expect(owner.rows[7]!.cells, isEmpty);
        _expectCellLocations(owner);
        controller.undo();
        expect(original.value, 'Original');
        expect(owner.cellA1('A1').value, 'Original');
        controller.redo();
        controller.redo();
        expect(_gridState(owner), after);
        expect(owner.cell(movedRef), same(moved));
        expect(_gridState(neighbor), neighborBefore);
        expect(controller.activeSheetIndex, 1);
        _expectCellLocations(owner);
      });
    }
  }

  test('unmerge redo keeps its original merge after selection changes', () {
    final controller = _controller();
    controller.sheet.merges.addAll([
      SmlMerge(c0: 0, r0: 0, c1: 1, r1: 0),
      SmlMerge(c0: 2, r0: 0, c1: 3, r1: 0),
    ]);
    controller.unmergeCells();
    expect(controller.sheet.merges.map((merge) => merge.a1), ['C1:D1']);
    controller.undo();
    controller.selection.selectCell(const SmlCellRef(2, 0));
    controller.redo();
    expect(controller.sheet.merges.map((merge) => merge.a1), ['C1:D1']);
  });

  test(
    'grid restoration retains every modeled cell field and its identity',
    () {
      final controller = _controller();
      final cell = controller.sheet.cellA1('A1')
        ..type = SmlCellType.number
        ..value = 3
        ..formula = '=1+2'
        ..styleIndex = 0
        ..hasExplicitStyleIndex = true
        ..horizontalAlign = SmlHAlign.center
        ..fillRgb = 'FFFF00'
        ..hasExplicitFillColorEdit = false
        ..fontRgb = '0070C0'
        ..hasExplicitFontColorEdit = false
        ..fontBold = true
        ..fontSize = 14
        ..borderRgb = '00B050'
        ..borderWidth = 1.5
        ..locked = false;
      controller.recalculateWorkbook();
      final before = _cellState(cell);
      controller.setSelectionFillRgb('FF0000');
      final after = _cellState(cell);
      for (var cycle = 0; cycle < 3; cycle++) {
        controller.undo();
        expect(_cellState(controller.sheet.cellA1('A1')), before);
        expect(controller.sheet.cellA1('A1'), same(cell));
        controller.redo();
        expect(_cellState(controller.sheet.cellA1('A1')), after);
        expect(controller.sheet.cellA1('A1'), same(cell));
      }
    },
  );

  test(
    'interleaved cell and grid history recalculates dependent worksheets',
    () {
      final controller = _controller();
      final owner = controller.sheet;
      final neighbor = controller.workbook.sheets[1];
      owner.cellA1('A1').value = 2;
      owner.cellA1('B1').formula = '=A1*3';
      neighbor.cellA1('A1').formula = '=Original!A1*2';
      controller.recalculateWorkbook();
      controller.setSelectionFillRgb('FF0000');
      _edit(controller, '4');
      expect(owner.cellA1('B1').value, 12);
      expect(neighbor.cellA1('A1').value, 8);
      controller.undo();
      controller.undo();
      expect(owner.cellA1('B1').value, 6);
      expect(neighbor.cellA1('A1').value, 4);
      controller.redo();
      controller.redo();
      expect(owner.cellA1('A1').value, 4);
      expect(owner.cellA1('B1').value, 12);
      expect(neighbor.cellA1('A1').value, 8);
    },
  );

  for (final asynchronous in [false, true]) {
    test(
      'interleaved grid history survives ${asynchronous ? 'isolate' : 'direct'} saves',
      () async {
        final controller = _controller();
        controller.setSelectionFillRgb('FF0000');
        _edit(controller, 'Edited');
        controller.insertSheetRows(index: 0, after: false);
        final states = [
          ('A2', 'Edited', 'FF0000'),
          ('A1', 'Edited', 'FF0000'),
          ('A1', 'Original', 'FF0000'),
          ('A1', 'Original', ''),
          ('A2', 'Edited', 'FF0000'),
        ];
        for (var step = 0; step < states.length; step++) {
          if (step > 0 && step < 4) {
            controller.undo();
          } else if (step == 4) {
            controller.redo();
            controller.redo();
            controller.redo();
          }
          final bytes = asynchronous
              ? await controller.saveBytesAsync()
              : controller.saveBytes();
          final reopened = SheetDeserializer().readBytes(bytes);
          final (address, value, fill) = states[step];
          final cell = reopened.firstSheet.cellA1(address);
          expect(cell.value, value, reason: 'step $step');
          expect(cell.fillRgb, fill, reason: 'step $step');
          expect(reopened.sheets[1].cellA1('A1').value, 'Neighbor');
        }
      },
    );
  }
}
