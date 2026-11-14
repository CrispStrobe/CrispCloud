import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

typedef _View = (bool, int, int);
typedef _ViewEdit = ({
  String name,
  _View before,
  _View after,
  void Function(SheetEditorController) apply,
});

const _plain = (false, 0, 0);
const _a1 = SmlCellRef(0, 0);
const _c5 = SmlCellRef(2, 4);

_View _view(SmlWorksheet sheet) =>
    (sheet.rightToLeft, sheet.freezeRows, sheet.freezeCols);

SheetEditorController _controller({
  _View initial = _plain,
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
}) {
  final first = SmlWorksheet(
    name: 'Original',
    sheetId: 1,
    rightToLeft: initial.$1,
    freezeRows: initial.$2,
    freezeCols: initial.$3,
  )..cell(_a1).value = 'Original';
  final neighbor = SmlWorksheet(
    name: 'Neighbor',
    sheetId: 2,
    freezeRows: 7,
    freezeCols: 1,
  )..cell(_a1).value = 'Neighbor';
  final controller = SheetEditorController(
    workbook: SmlWorkbook(sheets: [first, neighbor]),
    config: OfficeSurfaceConfig(mode: mode),
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

final _edits = <_ViewEdit>[
  (
    name: 'RTL setter',
    before: _plain,
    after: (true, 0, 0),
    apply: (controller) => controller.setSheetRightToLeft(true),
  ),
  (
    name: 'RTL toggle',
    before: (true, 0, 0),
    after: _plain,
    apply: (controller) => controller.toggleSheetRightToLeft(),
  ),
  (
    name: 'selection freeze',
    before: _plain,
    after: (false, 4, 2),
    apply: (controller) {
      controller.selection.selectCell(_c5);
      controller.freezePanesFromSelection();
    },
  ),
  (
    name: 'top row freeze',
    before: (true, 4, 2),
    after: (true, 1, 0),
    apply: (controller) => controller.freezeTopRow(),
  ),
  (
    name: 'first column freeze',
    before: (true, 4, 2),
    after: (true, 0, 1),
    apply: (controller) => controller.freezeFirstColumn(),
  ),
  (
    name: 'unfreeze',
    before: (true, 4, 2),
    after: (true, 0, 0),
    apply: (controller) => controller.unfreezePanes(),
  ),
  (
    name: 'toggle unfreeze',
    before: (true, 4, 2),
    after: (true, 0, 0),
    apply: (controller) => controller.toggleFreezePanes(),
  ),
  (
    name: 'toggle freeze',
    before: _plain,
    after: (false, 4, 2),
    apply: (controller) {
      controller.selection.selectCell(_c5);
      controller.toggleFreezePanes();
    },
  ),
  (
    name: 'origin selection unfreeze',
    before: (true, 4, 2),
    after: (true, 0, 0),
    apply: (controller) => controller.freezePanesFromSelection(),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final edit in _edits) {
    test('${edit.name} is one dirty revision and reversible command', () {
      final controller = _controller(initial: edit.before);
      var commands = 0;
      controller.commands.addListener(() => commands++);
      final revision = controller.contentRevision;
      edit.apply(controller);
      expect(_view(controller.sheet), edit.after);
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      expect(commands, 1);
      expect(controller.contentRevision, revision + 1);
      controller.undo();
      expect(_view(controller.sheet), edit.before);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      expect(commands, 2);
      expect(controller.contentRevision, revision + 2);
      controller.redo();
      expect(_view(controller.sheet), edit.after);
      expect(commands, 3);
      expect(controller.contentRevision, revision + 3);
    });
  }

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode blocks every worksheet view mutation', () {
      for (final edit in _edits) {
        final controller = _controller(initial: edit.before, mode: mode);
        final revision = controller.contentRevision;
        edit.apply(controller);
        expect(_view(controller.sheet), edit.before, reason: edit.name);
        expect(controller.isDirty, isFalse, reason: edit.name);
        expect(controller.canUndo, isFalse, reason: edit.name);
        expect(controller.contentRevision, revision, reason: edit.name);
      }
    });
  }

  test('view history stays on its owner and reuses captured freeze counts', () {
    final controller = _controller();
    final owner = controller.sheet;
    final neighbor = controller.workbook.sheets[1];
    final neighborView = _view(neighbor);
    controller.setSheetRightToLeft(true);
    controller.selection.selectCell(_c5);
    controller.freezePanesFromSelection();
    controller.setActiveSheet(1);
    controller.selection.selectCell(const SmlCellRef(5, 8));
    controller.viewport.origin = const Offset(70, 80);
    final origin = controller.viewport.origin;
    controller.undo();
    expect(_view(owner), (true, 0, 0));
    controller.undo();
    expect(_view(owner), _plain);
    controller.redo();
    controller.redo();
    expect(_view(owner), (true, 4, 2));
    expect(_view(neighbor), neighborView);
    expect(neighbor.cell(_a1).value, 'Neighbor');
    expect(controller.activeSheetIndex, 1);
    expect(controller.selection.focus, const SmlCellRef(5, 8));
    expect(controller.viewport.origin, origin);
  });

  test('unchanged view calls preserve redo, drafts, revision and viewport', () {
    final noOps = <_ViewEdit>[
      (
        name: 'unchanged RTL',
        before: _plain,
        after: _plain,
        apply: (controller) => controller.setSheetRightToLeft(false),
      ),
      (
        name: 'already unfrozen',
        before: _plain,
        after: _plain,
        apply: (controller) => controller.unfreezePanes(),
      ),
      (
        name: 'same top row',
        before: (false, 1, 0),
        after: (false, 1, 0),
        apply: (controller) => controller.freezeTopRow(),
      ),
      (
        name: 'same first column',
        before: (false, 0, 1),
        after: (false, 0, 1),
        apply: (controller) => controller.freezeFirstColumn(),
      ),
      (
        name: 'same selection freeze',
        before: (false, 4, 2),
        after: (false, 4, 2),
        apply: (controller) {
          controller.selection.selectCell(_c5);
          controller.freezePanesFromSelection();
        },
      ),
      (
        name: 'origin freeze',
        before: _plain,
        after: _plain,
        apply: (controller) => controller.freezePanesFromSelection(),
      ),
      (
        name: 'origin toggle',
        before: _plain,
        after: _plain,
        apply: (controller) => controller.toggleFreezePanes(),
      ),
    ];
    for (final edit in noOps) {
      final controller = _controller(initial: edit.before);
      controller.beginCellEdit();
      _type(controller, 'Undoable cell edit');
      controller.commitPendingEdits();
      controller.undo();
      controller.markClean();
      controller.beginCellEdit();
      controller.viewport.origin = const Offset(10000, 5000);
      final origin = controller.viewport.origin;
      final revision = controller.contentRevision;
      var notifications = 0;
      controller.addListener(() => notifications++);
      edit.apply(controller);
      expect(_view(controller.sheet), edit.before, reason: edit.name);
      expect(controller.canRedo, isTrue, reason: edit.name);
      expect(controller.isDirty, isFalse, reason: edit.name);
      expect(controller.contentRevision, revision, reason: edit.name);
      expect(controller.cellEditor.editing, isTrue, reason: edit.name);
      expect(controller.viewport.origin, origin, reason: edit.name);
      expect(notifications, 0, reason: edit.name);
    }
  });

  test('undoing an active freeze clamps the reduced scroll extent', () {
    final controller = _controller();
    controller.viewport.extent = const Size(400, 300);
    controller.selection.selectCell(const SmlCellRef(20, 100));
    controller.freezePanesFromSelection();
    controller.selection.selectCell(_a1);
    controller.viewport.origin = const Offset(1200, 1600);
    controller.clampSheetViewport();
    final frozenOrigin = controller.viewport.origin;
    controller.undo();
    expect(_view(controller.sheet), _plain);
    expect(controller.viewport.origin.dx, lessThan(frozenOrigin.dx));
    expect(controller.viewport.origin.dy, lessThan(frozenOrigin.dy));
    controller.redo();
    expect(_view(controller.sheet), (false, 100, 20));
  });

  for (final rtl in [false, true]) {
    test('${rtl ? 'RTL' : 'freeze'} retains a cancelable cell draft', () {
      final controller = _controller();
      controller.beginCellEdit();
      _type(controller, 'Cancelable draft');
      final revision = controller.contentRevision;
      if (rtl) {
        controller.setSheetRightToLeft(true);
      } else {
        controller.freezeTopRow();
      }
      expect(controller.cellEditor.editing, isTrue);
      expect(controller.cellEditor.formulaBar, 'Cancelable draft');
      expect(controller.sheet.cell(_a1).value, 'Original');
      expect(controller.contentRevision, revision + 1);
      controller.cancelCellEdit();
      expect(controller.isDirty, isTrue);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(_view(controller.sheet), _plain);
      expect(controller.sheet.cell(_a1).value, 'Original');
    });
  }

  test('view edits leave an invalid cell draft available for correction', () {
    final controller = _controller();
    controller.sheet.cell(_a1).value = 1;
    controller.sheet.validations.add(
      SmlDataValidation(
        range: const SmlRange(_a1, _a1),
        kind: SmlValidationKind.whole,
        formula1: '1',
        formula2: '10',
      ),
    );
    controller.beginCellEdit();
    _type(controller, 'Invalid');
    controller.freezeTopRow();
    controller.setSheetRightToLeft(true);
    expect(controller.cellEditor.editing, isTrue);
    expect(controller.cellEditor.formulaBar, 'Invalid');
    expect(controller.sheet.cell(_a1).value, 1);
    expect(controller.commitPendingEdits, throwsStateError);
    expect(controller.cellEditor.editing, isTrue);
    expect(_view(controller.sheet), (true, 1, 0));
    controller.cancelCellEdit();
    expect(controller.isDirty, isTrue);
    controller.undo();
    controller.undo();
    expect(_view(controller.sheet), _plain);
  });

  for (final asynchronous in [false, true]) {
    test(
      'view history survives ${asynchronous ? 'isolate' : 'direct'} saves',
      () async {
        final controller = _controller();
        controller.setSheetRightToLeft(true);
        controller.selection.selectCell(_c5);
        controller.freezePanesFromSelection();
        for (final expected in [
          (true, 4, 2),
          (true, 0, 0),
          _plain,
          (true, 4, 2),
        ]) {
          if (expected == (true, 0, 0) || expected == _plain) {
            controller.undo();
          } else if (_view(controller.sheet) == _plain) {
            controller.redo();
            controller.redo();
          }
          final bytes = asynchronous
              ? await controller.saveBytesAsync()
              : controller.saveBytes();
          final reopened = SheetDeserializer().readBytes(bytes);
          expect(_view(reopened.firstSheet), expected);
          expect(_view(reopened.sheets[1]), (false, 7, 1));
          expect(reopened.firstSheet.cell(_a1).value, 'Original');
          expect(reopened.sheets[1].cell(_a1).value, 'Neighbor');
        }
      },
    );
  }

  test(
    'a view edit invalidates an older asynchronous upload revision',
    () async {
      final controller = _controller();
      controller.setSheetRightToLeft(true);
      final uploadingRevision = controller.contentRevision;
      final bytes = await controller.saveBytesAsync();
      controller.freezeTopRow();
      if (controller.contentRevision == uploadingRevision) {
        controller.markClean();
      }
      expect(controller.contentRevision, greaterThan(uploadingRevision));
      expect(controller.isDirty, isTrue);
      expect(_view(SheetDeserializer().readBytes(bytes).firstSheet), (
        true,
        0,
        0,
      ));
      expect(_view(controller.sheet), (true, 1, 0));
    },
  );
}
