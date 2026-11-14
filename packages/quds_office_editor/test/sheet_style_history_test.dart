import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _a1 = SmlCellRef(0, 0);
const _b1 = SmlCellRef(1, 0);
const _c1 = SmlCellRef(2, 0);
const _x = OfficeNamespaces.x;

typedef _StyleEdit = ({
  String name,
  void Function(SheetEditorController) apply,
  Map<String, Object?> changes,
});

final _edits = <_StyleEdit>[
  (
    name: 'bold',
    apply: (controller) => controller.setSelectionFontBold(true),
    changes: {'bold': true},
  ),
  (
    name: 'font size',
    apply: (controller) => controller.setSelectionFontSize(14.5),
    changes: {'size': 14.5},
  ),
  (
    name: 'alignment',
    apply: (controller) =>
        controller.setSelectionHorizontalAlign(SmlHAlign.center),
    changes: {'alignment': SmlHAlign.center},
  ),
  (
    name: 'clear formatting',
    apply: (controller) => controller.clearSelectionFormatting(),
    changes: {
      'bold': false,
      'size': 11.0,
      'alignment': SmlHAlign.general,
      'fill': '',
      'explicitFill': true,
      'font': '',
      'explicitFont': true,
      'styleIndex': 0,
    },
  ),
];

SheetEditorController _controller({
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
}) {
  final first = SmlWorksheet(name: 'Original', sheetId: 1);
  first.cell(_a1)
    ..type = SmlCellType.string
    ..value = 'Original';
  first.cell(_b1)
    ..type = SmlCellType.string
    ..value = 'Selected neighbor';
  first.cell(_c1)
    ..type = SmlCellType.string
    ..value = 'Outside selection';
  final second = SmlWorksheet(name: 'Neighbor', sheetId: 2);
  second.cell(_a1)
    ..value = 19
    ..fontBold = true
    ..fontSize = 22
    ..fillRgb = '00FF00';
  final controller = SheetEditorController(
    workbook: SmlWorkbook(sheets: [first, second]),
    config: OfficeSurfaceConfig(mode: mode),
  );
  addTearDown(controller.dispose);
  return controller;
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

Map<String, Map<String, Object?>> _cells(SmlWorksheet sheet) => {
  for (final cell in sheet.allCells) cell.ref.a1: _cellState(cell),
};

Map<String, Object?> _visibleStyle(SmlCell cell) => {
  'bold': cell.fontBold,
  'size': cell.fontSize,
  'alignment': cell.horizontalAlign,
  'fill': cell.fillRgb,
  'font': cell.fontRgb,
};

void _type(SheetEditorController controller, String text) {
  controller.cellEditor.bridge.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}

void _edit(SheetEditorController controller, String text) {
  controller.beginCellEdit();
  _type(controller, text);
  controller.commitPendingEdits();
}

Future<Uint8List> _save(
  SheetEditorController controller,
  bool asynchronous,
) async =>
    asynchronous ? await controller.saveBytesAsync() : controller.saveBytes();

Uint8List _nativeBytes() {
  final package = OpcPackage.create(OpcPackageKind.sheet);
  final styles =
      File('../quds_office_engine/test/fixtures/fidelity/sheet-fill-native.xml')
          .readAsStringSync()
          .replaceFirst('<s:color rgb="FF000000"/>', '<s:color theme="1"/>');
  package
      .createPart('/xl/styles.xml', OfficeContentTypes.sheetStyles)
      .writeText(styles);
  package
      .relationshipsFor('/xl/workbook.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  package
      .getPart('/xl/worksheets/sheet1.xml')!
      .writeText(
        '<s:worksheet xmlns:s="$_x"><s:sheetData><s:row r="1">'
        '<s:c r="A1" s="2"><s:v>1</s:v></s:c>'
        '<s:c r="B1" s="1"><s:v>2</s:v></s:c>'
        '<s:c r="C1" s="3"><s:v>3</s:v></s:c>'
        '<s:c r="D1" s="0"><s:v>4</s:v></s:c>'
        '<s:c r="E1"><s:v>5</s:v></s:c>'
        '</s:row></s:sheetData></s:worksheet>',
      );
  return package.save();
}

SheetEditorController _nativeController(Uint8List bytes) {
  final controller = SheetEditorController.fromBytes(
    bytes,
    columnMetricsResolver: (_) => null,
  );
  addTearDown(controller.dispose);
  controller.selection.extendTo(const SmlCellRef(4, 0));
  return controller;
}

String _xml(XmlElement element) =>
    XmlDocument(root: element).toXmlString(declaration: false);

Map<String, Map<String, Object?>> _nativeStyles(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final sheet = XmlDocument.parse(
    package.getPart('/xl/worksheets/sheet1.xml')!.readText(),
  ).root!;
  final styles = XmlDocument.parse(
    package.getPart('/xl/styles.xml')!.readText(),
  ).root!;
  final formats = styles.firstChild('cellXfs')!.childrenNamed('xf');
  final fills = styles.firstChild('fills')!.childrenNamed('fill');
  final fonts = styles.firstChild('fonts')!.childrenNamed('font');
  final result = <String, Map<String, Object?>>{};
  for (final row in sheet.firstChild('sheetData')!.childrenNamed('row')) {
    for (final cell in row.childrenNamed('c')) {
      final styleIndex = cell.getAttribute('s');
      final format = formats[int.parse(styleIndex ?? '0')];
      final fill = fills[int.parse(format.getAttribute('fillId') ?? '0')];
      final font = fonts[int.parse(format.getAttribute('fontId') ?? '0')];
      final color = font.firstChild('color');
      result[cell.getAttribute('r')!] = {
        'style': styleIndex,
        'fill': _xml(fill),
        'fontColor': color == null ? null : _xml(color),
        'gradient': fill.firstChild('gradientFill') != null,
        'pattern': fill.firstChild('patternFill')?.getAttribute('patternType'),
      };
    }
  }
  return result;
}

void _expectNativeColors(
  Map<String, Map<String, Object?>> actual,
  Map<String, Map<String, Object?>> source,
) {
  expect(actual.keys, source.keys);
  for (final address in source.keys) {
    expect(actual[address]!['fill'], source[address]!['fill'], reason: address);
    expect(
      actual[address]!['fontColor'],
      source[address]!['fontColor'],
      reason: address,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final edit in _edits) {
    test('${edit.name} history retains its owner, range and modeled state', () {
      final controller = _controller();
      final owner = controller.sheet;
      for (final ref in [_a1, _b1]) {
        owner.cell(ref)
          ..type = SmlCellType.number
          ..value = 3
          ..formula = '=1+2'
          ..styleIndex = 7
          ..hasExplicitStyleIndex = ref.col == 0
          ..horizontalAlign = SmlHAlign.right
          ..fillRgb = 'FFFF00'
          ..hasExplicitFillColorEdit = false
          ..fontRgb = '0070C0'
          ..hasExplicitFontColorEdit = false
          ..fontSize = 12
          ..borderRgb = '00B050'
          ..borderWidth = 1.5
          ..locked = false;
      }
      controller.recalculateWorkbook();
      final original = owner.cell(_a1);
      final neighbor = controller.workbook.sheets[1];
      final before = _cells(owner);
      final neighborBefore = _cells(neighbor);
      final expected = {
        for (final entry in before.entries)
          entry.key: {
            ...entry.value,
            if (entry.key == 'A1' || entry.key == 'B1') ...edit.changes,
          },
      };
      controller.selection.extendTo(_b1);
      final revision = controller.contentRevision;
      var commands = 0;
      controller.commands.addListener(() => commands++);
      edit.apply(controller);
      expect(_cells(owner), expected);
      expect(controller.isDirty, isTrue);
      expect(controller.contentRevision, revision + 1);
      expect(commands, 1);
      controller.setActiveSheet(1);
      controller.selection.selectCell(const SmlCellRef(5, 4));
      controller.undo();
      expect(_cells(owner), before);
      expect(_cells(neighbor), neighborBefore);
      expect(owner.cell(_a1), same(original));
      controller.redo();
      expect(_cells(owner), expected);
      expect(_cells(neighbor), neighborBefore);
      expect(controller.activeSheetIndex, 1);
      expect(controller.contentRevision, revision + 3);
      expect(commands, 3);
      controller.undo();
      controller.setActiveSheet(0);
      controller.selection.selectCell(_c1);
      controller.redo();
      expect(_cells(owner), expected);
      expect(owner.cell(_a1), same(original));
    });
  }

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test('$mode rejects every typed style mutation', () {
      final controller = _controller(mode: mode);
      controller.selection.extendTo(const SmlCellRef(4, 1));
      final before = _cells(controller.sheet);
      final revision = controller.contentRevision;
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (final edit in _edits) {
        edit.apply(controller);
      }
      expect(_cells(controller.sheet), before);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);
      expect(controller.contentRevision, revision);
      expect(notifications, 0);
    });
  }

  test(
    'scalar no-ops and invalid sizes retain redo without creating cells',
    () {
      final controller = _controller();
      controller.setSelectionFontBold(true);
      controller.undo();
      controller.markClean();
      const absent = SmlCellRef(6, 9);
      controller.selection.selectCell(absent);
      final revision = controller.contentRevision;
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setSelectionFontBold(false);
      controller.setSelectionFontSize(11);
      controller.setSelectionHorizontalAlign(SmlHAlign.general);
      for (final size in [
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        -double.infinity,
      ]) {
        controller.setSelectionFontSize(size);
      }
      expect(controller.sheet.cellOrNull(absent), isNull);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      expect(controller.isDirty, isFalse);
      expect(controller.contentRevision, revision);
      expect(notifications, 0);
      controller.redo();
      expect(controller.sheet.cell(_a1).fontBold, isTrue);
      expect(controller.sheet.cellOrNull(absent), isNull);
    },
  );

  test('typed styles skip covered cells and covered-only selections', () {
    for (final edit in _edits) {
      final controller = _controller();
      final owner = controller.sheet;
      owner.merges.add(SmlMerge(c0: 0, r0: 0, c1: 1, r1: 0));
      final originBefore = _cellState(owner.cell(_a1));
      final coveredBefore = _cellState(owner.cell(_b1));
      controller.selection.extendTo(_b1);
      edit.apply(controller);
      expect(_cellState(owner.cell(_a1)), {...originBefore, ...edit.changes});
      expect(_cellState(owner.cell(_b1)), coveredBefore);
      controller.undo();
      controller.markClean();
      controller.selection.selectCell(_b1);
      final revision = controller.contentRevision;
      edit.apply(controller);
      expect(_cellState(owner.cell(_a1)), originBefore);
      expect(_cellState(owner.cell(_b1)), coveredBefore);
      expect(controller.contentRevision, revision);
      expect(controller.canRedo, isTrue);
      expect(controller.isDirty, isFalse);
    }
  });

  test('clear formatting records explicit intent even for default scalars', () {
    final controller = _controller();
    final cell = controller.sheet.cell(_a1);
    final before = _cellState(cell);
    controller.clearSelectionFormatting();
    expect(cell.hasExplicitFillColorEdit, isTrue);
    expect(cell.hasExplicitFontColorEdit, isTrue);
    expect(controller.isDirty, isTrue);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(_cellState(cell), before);
    controller.redo();
    expect(cell.hasExplicitFillColorEdit, isTrue);
    expect(cell.hasExplicitFontColorEdit, isTrue);
  });

  test('cell, style and structural history keeps the original cell object', () {
    final controller = _controller();
    final owner = controller.sheet;
    final original = owner.cell(_a1);
    _edit(controller, 'Before style');
    controller.setSelectionFontBold(true);
    controller.insertSheetRows(index: 0, after: false);
    controller.selection.selectCell(const SmlCellRef(0, 1));
    _edit(controller, 'After row');
    expect(owner.cellA1('A2'), same(original));
    controller.undo();
    expect(original.value, 'Before style');
    controller.undo();
    expect(owner.cell(_a1), same(original));
    expect(original.ref.a1, 'A1');
    controller.undo();
    expect(original.fontBold, isFalse);
    controller.undo();
    expect(original.value, 'Original');
    for (var step = 0; step < 4; step++) {
      controller.redo();
    }
    expect(owner.cellA1('A2'), same(original));
    expect(original.ref.a1, 'A2');
    expect(original.value, 'After row');
    expect(original.fontBold, isTrue);
  });

  for (final asynchronous in [false, true]) {
    final saveKind = asynchronous ? 'isolate' : 'direct';
    for (final edit in _edits.take(3)) {
      test(
        '${edit.name} retains native colors through $saveKind history saves',
        () async {
          final source = _nativeBytes();
          final expected = _nativeStyles(source);
          expect(expected['A1']!['gradient'], isTrue);
          expect(expected['B1']!['pattern'], 'darkGrid');
          expect(expected['D1']!['fontColor'], contains('theme="1"'));
          expect(expected['D1']!['style'], '0');
          expect(expected['E1']!['style'], isNull);
          final controller = _nativeController(source);
          edit.apply(controller);
          for (final cell in controller.sheet.allCells) {
            expect(cell.hasExplicitFillColorEdit, isFalse);
            expect(cell.hasExplicitFontColorEdit, isFalse);
          }
          final changed = await _save(controller, asynchronous);
          _expectNativeColors(_nativeStyles(changed), expected);
          final reopened = SheetDeserializer().readBytes(changed);
          for (final cell in reopened.firstSheet.allCells) {
            for (final change in edit.changes.entries) {
              expect(_cellState(cell)[change.key], change.value);
            }
          }
          controller.undo();
          expect(
            _nativeStyles(await _save(controller, asynchronous)),
            expected,
          );
          expect(controller.sheet.cellA1('D1').hasExplicitStyleIndex, isTrue);
          expect(controller.sheet.cellA1('E1').hasExplicitStyleIndex, isFalse);
          controller.selection.selectCell(const SmlCellRef(8, 4));
          controller.redo();
          _expectNativeColors(
            _nativeStyles(await _save(controller, asynchronous)),
            expected,
          );
          expect(controller.sheet.cellOrNull(const SmlCellRef(8, 4)), isNull);
        },
      );
    }

    test(
      'clear and undo restore native definitions through $saveKind saves',
      () async {
        final source = _nativeBytes();
        final expected = _nativeStyles(source);
        final controller = _nativeController(source);
        controller.clearSelectionFormatting();
        for (var cycle = 0; cycle < 2; cycle++) {
          final bytes = await _save(controller, asynchronous);
          final saved = _nativeStyles(bytes);
          for (final state in saved.values) {
            expect(state['gradient'], isFalse);
            expect(state['pattern'], 'none');
            expect(state['fontColor'], isNull);
          }
          for (final cell
              in SheetDeserializer().readBytes(bytes).firstSheet.allCells) {
            expect(_visibleStyle(cell), {
              'bold': false,
              'size': 11.0,
              'alignment': SmlHAlign.general,
              'fill': '',
              'font': '',
            });
          }
          controller.undo();
          expect(
            _nativeStyles(await _save(controller, asynchronous)),
            expected,
          );
          for (final cell in controller.sheet.allCells) {
            expect(cell.hasExplicitFillColorEdit, isFalse);
            expect(cell.hasExplicitFontColorEdit, isFalse);
          }
          controller.redo();
        }
      },
    );

    test(
      'typed styles retain cell drafts until $saveKind save commits them',
      () async {
        for (final edit in _edits) {
          final controller = _controller();
          final original = controller.sheet.cell(_a1);
          final before = _cellState(original);
          controller.beginCellEdit();
          _type(controller, 'Pending value');
          final revision = controller.contentRevision;
          edit.apply(controller);
          expect(controller.cellEditor.editing, isTrue, reason: edit.name);
          expect(controller.cellEditor.formulaBar, 'Pending value');
          expect(original.value, 'Original');
          expect(controller.contentRevision, revision + 1);
          final expectedStyle = _visibleStyle(original);
          final bytes = await _save(controller, asynchronous);
          final saved = SheetDeserializer()
              .readBytes(bytes)
              .firstSheet
              .cell(_a1);
          expect(saved.value, 'Pending value');
          expect(_visibleStyle(saved), expectedStyle);
          expect(controller.cellEditor.editing, isFalse);
          controller.undo();
          expect(original.value, 'Original');
          expect(_visibleStyle(original), expectedStyle);
          controller.undo();
          expect(controller.sheet.cell(_a1), same(original));
          expect(_cellState(original), before);
        }
      },
    );
  }
}
