import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _a1 = SmlCellRef(0, 0);
const _b2 = SmlCellRef(1, 1);
const _c4 = SmlCellRef(2, 3);

SheetEditorController _controller({
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
}) {
  final first = SmlWorksheet(name: 'Budget', sheetId: 1);
  first.cell(_a1)
    ..value = 5
    ..type = SmlCellType.number;
  first.cell(_b2).value = 'Find first';
  first.cell(_c4).value = 'Find second';
  final second = SmlWorksheet(name: 'Summary', sheetId: 2);
  second.cell(_a1).value = 'Neighbor';
  second.cell(_b2).value = 'Find third';
  final controller = SheetEditorController(
    workbook: SmlWorkbook(sheets: [first, second]),
    config: OfficeSurfaceConfig(mode: mode, autofocus: false),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _type(SheetEditorController controller, String text) {
  controller.cellEditor.bridge.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}

void _validateNumber(SheetEditorController controller) {
  controller.sheet.validations.add(
    SmlDataValidation(
      range: SmlRange(_a1, _a1),
      kind: SmlValidationKind.whole,
      formula1: '1',
      formula2: '10',
      error: 'Enter a whole number from 1 to 10.',
    ),
  );
}

OfficeFindHit _hit({String sheet = 'Budget', String cell = 'B2'}) =>
    OfficeFindHit(
      kind: OpcPackageKindHint.sheet,
      preview: 'Find',
      sheetName: sheet,
      a1: cell,
    );

Object _view(SheetEditorController controller) => (
  controller.activeSheetIndex,
  controller.selection.kind,
  controller.selection.anchor,
  controller.selection.focus,
  controller.selectedDrawingIndex,
  controller.viewport.origin,
  controller.viewport.scale,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'formula locale follows the controller across worker save and open',
    () async {
      final source = SmlWorkbook();
      source.firstSheet.cellA1('A1').formula = '=TEXT(1234.5,"#.##0,00")';
      source.firstSheet.cellA1('A2').formula =
          '=NUMBERVALUE("01.02.2025",",",";")';
      final bytes = SheetSerializer().writeBytes(source, recalculate: false);
      final controller = SheetEditorController.fromBytes(
        bytes,
        formulaLocale: 'de-DE',
      );
      addTearDown(controller.dispose);
      expect(controller.sheet.cellA1('A1').value, '1.234,50');
      expect(controller.sheet.cellA1('A2').value, 45689);

      final saved = SheetDeserializer().readBytes(
        await controller.saveBytesAsync(),
      );
      expect(saved.firstSheet.cellA1('A1').value, '1.234,50');
      expect(saved.firstSheet.cellA1('A2').value, 45689);
      expect(saved.formulaLocale, isNull);

      await controller.loadBytesAsync(bytes);
      expect(controller.sheet.cellA1('A1').value, '1.234,50');
      expect(controller.sheet.cellA1('A2').value, 45689);
    },
  );

  test(
    'switch commits a valid draft to its owner and preserves owner history',
    () {
      final controller = _controller();
      final owner = controller.sheet;
      final neighbor = controller.workbook.sheets[1];
      controller.beginCellEdit();
      _type(controller, '8');
      controller.viewport.origin = const Offset(140, 180);
      final before = controller.contentRevision;
      controller.setActiveSheet(1);
      expect(controller.activeSheetIndex, 1);
      expect(controller.cellEditor.editing, isFalse);
      expect(owner.cell(_a1).value, 8);
      expect(neighbor.cell(_a1).value, 'Neighbor');
      expect(controller.selection.focus, _a1);
      expect(controller.viewport.origin, Offset.zero);
      expect(controller.contentRevision, before + 1);
      final saved = SheetDeserializer().readBytes(controller.saveBytes());
      expect(saved.sheets[0].cell(_a1).value, 8);
      expect(saved.sheets[1].cell(_a1).value, 'Neighbor');
      controller.selection.selectCell(_c4);
      controller.undo();
      expect(owner.cell(_a1).value, 5);
      expect(neighbor.cell(_a1).value, 'Neighbor');
      expect(controller.activeSheetIndex, 1);
      expect(controller.selection.focus, _c4);
      expect(controller.commands.canUndo, isFalse);
      controller.redo();
      expect(owner.cell(_a1).value, 8);
      expect(neighbor.cell(_a1).value, 'Neighbor');
    },
  );

  for (final entry in <String, (Object, SmlCellType)>{
    '=1/0': ('#DIV/0!', SmlCellType.error),
    '="#REF!"': ('#REF!', SmlCellType.string),
  }.entries) {
    test('switch retains formula evaluation semantics for ${entry.key}', () {
      final controller = _controller();
      final owner = controller.sheet;
      controller.beginCellEdit();
      _type(controller, entry.key);
      controller.setActiveSheet(1);
      expect(controller.activeSheetIndex, 1);
      expect(owner.cell(_a1).formula, entry.key);
      expect(owner.cell(_a1).value, entry.value.$1);
      expect(owner.cell(_a1).type, entry.value.$2);
      expect(controller.lastValidationError, isNull);
    });
  }

  test(
    'rejected switch retains the visible draft, location and redo history',
    () {
      final controller = _controller();
      _validateNumber(controller);
      controller.setSheetRightToLeft(true);
      controller.undo();
      controller.markClean();
      controller.beginCellEdit();
      _type(controller, 'invalid');
      controller.cellEditor.setCaret(2, extend: true);
      controller.viewport.origin = const Offset(110, 150);
      final before = controller.contentRevision;
      final view = _view(controller);
      final caret = controller.cellEditor.caretIndex;
      final base = controller.cellEditor.selectionBase;
      final redo = controller.commands.nextRedoCommand;
      expect(() => controller.setActiveSheet(1), throwsStateError);
      expect(_view(controller), view);
      expect(controller.cellEditor.editing, isTrue);
      expect(controller.formulaBarText, 'invalid');
      expect(controller.cellEditor.caretIndex, caret);
      expect(controller.cellEditor.selectionBase, base);
      expect(controller.sheet.cell(_a1).value, 5);
      expect(controller.lastValidationError, isNotNull);
      expect(controller.isDirty, isTrue);
      expect(controller.contentRevision, before);
      expect(controller.commands.canUndo, isFalse);
      expect(controller.commands.nextRedoCommand, same(redo));
      _type(controller, '9');
      controller.setActiveSheet(1);
      expect(controller.activeSheetIndex, 1);
      expect(controller.workbook.firstSheet.cell(_a1).value, 9);
      expect(controller.lastValidationError, isNull);
    },
  );

  test(
    'protection introduced during editing blocks navigation without loss',
    () {
      final controller = _controller();
      controller.beginCellEdit();
      _type(controller, '9');
      controller.sheet.protection = SmlSheetProtection(enabled: true);
      final before = controller.contentRevision;
      expect(() => controller.setActiveSheet(1), throwsStateError);
      expect(controller.activeSheetIndex, 0);
      expect(controller.formulaBarText, '9');
      expect(controller.cellEditor.editing, isTrue);
      expect(controller.sheet.cell(_a1).value, 5);
      expect(controller.contentRevision, before);
      expect(controller.commands.canUndo, isFalse);
    },
  );

  for (final requested in [0, -100]) {
    test(
      'effective same-sheet $requested preserves a changed draft exactly',
      () {
        final controller = _controller();
        controller.beginCellEdit();
        _type(controller, '8');
        controller.cellEditor.setCaret(0, extend: true);
        controller.viewport.origin = const Offset(80, 120);
        final before = controller.contentRevision;
        final view = _view(controller);
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.setActiveSheet(requested);
        expect(_view(controller), view);
        expect(controller.cellEditor.editing, isTrue);
        expect(controller.formulaBarText, '8');
        expect(controller.cellEditor.caretIndex, 0);
        expect(controller.cellEditor.selectionBase, 1);
        expect(controller.sheet.cell(_a1).value, 5);
        expect(controller.contentRevision, before);
        expect(controller.commands.canUndo, isFalse);
        expect(notifications, 0);
      },
    );
  }

  test('effective same-sheet does not validate a rejected draft', () {
    final controller = _controller();
    _validateNumber(controller);
    controller.beginCellEdit();
    _type(controller, 'invalid');
    final before = controller.contentRevision;
    controller.setActiveSheet(0);
    expect(controller.cellEditor.editing, isTrue);
    expect(controller.lastValidationError, isNull);
    expect(controller.formulaBarText, 'invalid');
    expect(controller.contentRevision, before);
  });

  test(
    'clamped current last sheet retains selection, drawing, viewport and redo',
    () {
      final controller = _controller();
      controller.setSheetRightToLeft(true);
      controller.undo();
      controller.markClean();
      controller.setActiveSheet(1);
      controller.selection
        ..selectColumn(2)
        ..extendColumnsTo(4);
      controller.selectedDrawingIndex = 3;
      controller.viewport
        ..origin = const Offset(80, 120)
        ..scale = 1.5;
      final view = _view(controller);
      final before = controller.contentRevision;
      final redo = controller.commands.nextRedoCommand;
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setActiveSheet(100);
      expect(_view(controller), view);
      expect(controller.contentRevision, before);
      expect(controller.commands.nextRedoCommand, same(redo));
      expect(controller.isDirty, isFalse);
      expect(notifications, 0);
    },
  );

  for (final mode in OfficeInteractionMode.values) {
    test('$mode permits clamped navigation without dirtying the workbook', () {
      final controller = _controller(mode: mode);
      final before = controller.contentRevision;
      controller.selection.selectCell(_c4);
      controller.viewport.origin = const Offset(70, 80);
      controller.selectedDrawingIndex = 2;
      controller.setActiveSheet(100);
      expect(controller.activeSheetIndex, 1);
      expect(controller.selection.focus, _a1);
      expect(controller.selectedDrawingIndex, isNull);
      expect(controller.viewport.origin, Offset.zero);
      controller.setActiveSheet(-100);
      expect(controller.activeSheetIndex, 0);
      expect(controller.isDirty, isFalse);
      expect(controller.contentRevision, before);
      expect(controller.canUndo, isFalse);
    });
  }

  test(
    'switching an unchanged draft keeps string type, clean state and redo',
    () {
      final controller = _controller();
      controller.sheet.cell(_a1)
        ..value = '0012'
        ..type = SmlCellType.string;
      controller.setSheetRightToLeft(true);
      controller.undo();
      controller.markClean();
      controller.beginCellEdit();
      final before = controller.contentRevision;
      final redo = controller.commands.nextRedoCommand;
      controller.setActiveSheet(1);
      expect(controller.cellEditor.editing, isFalse);
      expect(controller.workbook.firstSheet.cell(_a1).value, '0012');
      expect(controller.workbook.firstSheet.cell(_a1).type, SmlCellType.string);
      expect(controller.contentRevision, before);
      expect(controller.commands.nextRedoCommand, same(redo));
      expect(controller.isDirty, isFalse);
    },
  );

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    for (final sync in [false, true]) {
      test(
        '$mode via ${sync ? 'syncConfig' : 'config'} retains a changed draft',
        () {
          final controller = _controller();
          controller.beginCellEdit();
          _type(controller, '8');
          final config = controller.config.copyWith(mode: mode);
          if (sync) {
            controller.syncConfig(config);
          } else {
            controller.config = config;
          }
          final before = controller.contentRevision;
          expect(() => controller.setActiveSheet(1), throwsStateError);
          expect(controller.activeSheetIndex, 0);
          expect(controller.sheet.cell(_a1).value, 5);
          expect(controller.cellEditor.editing, isTrue);
          expect(controller.formulaBarText, '8');
          expect(controller.contentRevision, before);
          expect(controller.commands.canUndo, isFalse);
          controller.config = controller.config.copyWith(
            mode: OfficeInteractionMode.editing,
          );
          controller.setActiveSheet(1);
          expect(controller.workbook.firstSheet.cell(_a1).value, 8);
        },
      );
    }
  }

  for (final destination in ['Budget', 'Summary']) {
    test(
      'find reveal in $destination commits at the original cell before moving',
      () {
        final controller = _controller();
        controller.beginCellEdit();
        _type(controller, '8');
        controller.selectedDrawingIndex = 1;
        controller.revealFindHit(_hit(sheet: destination));
        expect(controller.workbook.firstSheet.cell(_a1).value, 8);
        expect(controller.workbook.sheets[1].cell(_a1).value, 'Neighbor');
        expect(controller.sheet.name, destination);
        expect(controller.selection.focus.a1, 'B2');
        expect(controller.selectedDrawingIndex, isNull);
        expect(controller.cellEditor.editing, isFalse);
        controller.undo();
        expect(controller.workbook.firstSheet.cell(_a1).value, 5);
        expect(controller.selection.focus.a1, 'B2');
      },
    );

    test(
      'find reveal in $destination retains a rejected draft and location',
      () {
        final controller = _controller();
        _validateNumber(controller);
        controller.beginCellEdit();
        _type(controller, 'invalid');
        controller.viewport.origin = const Offset(60, 90);
        final view = _view(controller);
        final before = controller.contentRevision;
        expect(
          () => controller.revealFindHit(_hit(sheet: destination)),
          throwsStateError,
        );
        expect(_view(controller), view);
        expect(controller.cellEditor.editing, isTrue);
        expect(controller.formulaBarText, 'invalid');
        expect(controller.workbook.firstSheet.cell(_a1).value, 5);
        expect(controller.contentRevision, before);
        expect(controller.commands.canUndo, isFalse);
      },
    );
  }

  test(
    'a rejected search preserves the previous session and result callback',
    () {
      final controller = _controller();
      const original = OfficeFindOptions(query: 'Find');
      controller.find(original);
      controller.findNext();
      final hits = controller.findSession.hits;
      final index = controller.findSession.index;
      controller.selection.selectCell(_a1);
      _validateNumber(controller);
      controller.beginCellEdit();
      _type(controller, 'invalid');
      var callbacks = 0;
      controller.onFindResult = (_) => callbacks++;
      expect(
        () => controller.find(const OfficeFindOptions(query: 'Neighbor')),
        throwsStateError,
      );
      expect(controller.findSession.hits, same(hits));
      expect(controller.findSession.options, same(original));
      expect(controller.findSession.index, index);
      expect(controller.findSession.active, isTrue);
      expect(controller.activeSheetIndex, 0);
      expect(controller.selection.focus, _a1);
      expect(controller.formulaBarText, 'invalid');
      expect(callbacks, 0);
    },
  );

  test('a rejected first search leaves the empty find session intact', () {
    final controller = _controller();
    _validateNumber(controller);
    controller.beginCellEdit();
    _type(controller, 'invalid');
    expect(
      () => controller.find(const OfficeFindOptions(query: 'Find')),
      throwsStateError,
    );
    expect(controller.findSession.hits, isEmpty);
    expect(controller.findSession.options, isNull);
    expect(controller.findSession.index, -1);
    expect(controller.findSession.active, isFalse);
    expect(controller.cellEditor.editing, isTrue);
  });

  for (final forward in [true, false]) {
    test(
      'rejected find ${forward ? 'next' : 'previous'} keeps its cursor and retries',
      () {
        final controller = _controller();
        controller.find(const OfficeFindOptions(query: 'Find'));
        final previous = controller.findSession.current;
        controller.selection.selectCell(_a1);
        _validateNumber(controller);
        controller.beginCellEdit();
        _type(controller, 'invalid');
        OfficeFindHit? step() =>
            forward ? controller.findNext() : controller.findPrevious();
        var callbacks = 0;
        controller.onFindResult = (_) => callbacks++;
        expect(step, throwsStateError);
        expect(controller.findSession.index, 0);
        expect(controller.findSession.current, same(previous));
        expect(controller.selection.focus, _a1);
        expect(controller.cellEditor.editing, isTrue);
        expect(callbacks, 0);
        _type(controller, '9');
        final hit = step();
        expect(controller.findSession.index, forward ? 1 : 2);
        expect(controller.findSession.current, same(hit));
        expect(controller.sheet.name, forward ? 'Budget' : 'Summary');
        expect(controller.selection.focus.a1, forward ? 'C4' : 'B2');
        expect(controller.workbook.firstSheet.cell(_a1).value, 9);
        expect(callbacks, 1);
      },
    );
  }

  test(
    'find with no hits and a nonwrapping boundary leave drafts in place',
    () {
      final controller = _controller();
      controller.find(const OfficeFindOptions(query: 'third'));
      controller.beginCellEdit();
      _type(controller, 'draft');
      final before = controller.contentRevision;
      final view = _view(controller);
      final current = controller.findSession.current;
      expect(controller.findNext(wrap: false), same(current));
      expect(_view(controller), view);
      expect(controller.cellEditor.editing, isTrue);
      expect(
        controller.find(const OfficeFindOptions(query: 'absent')),
        isEmpty,
      );
      expect(_view(controller), view);
      expect(controller.cellEditor.editing, isTrue);
      expect(controller.contentRevision, before);
      expect(controller.commands.canUndo, isFalse);
    },
  );
}
