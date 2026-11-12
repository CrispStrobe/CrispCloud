import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _a1 = SmlCellRef(0, 0);

SheetEditorController _editor({bool native = false, bool readOnly = false}) {
  final book = native
      ? SheetDeserializer().readBytes(
          File(
            '../quds_office_engine/test/fixtures/fidelity/sheet-rename-native.xlsx',
          ).readAsBytesSync(),
        )
      : SmlWorkbook(
          sheets: [
            SmlWorksheet(name: 'Data', sheetId: 1),
            SmlWorksheet(name: 'Summary', sheetId: 2),
          ],
        );
  if (!native) {
    book.firstSheet.cellA1('B2').value = 2;
    book.sheets[1].cellA1('A1').formula = 'Data!B2';
    book.namedRanges.add(
      SmlNamedRange(
        name: 'Source',
        sheetName: 'Data',
        range: SmlRange.parse('B2:B2'),
      ),
    );
  }
  final editor = SheetEditorController(
    workbook: book,
    config: OfficeSurfaceConfig(
      mode: readOnly
          ? OfficeInteractionMode.viewing
          : OfficeInteractionMode.editing,
    ),
  );
  addTearDown(editor.dispose);
  return editor;
}

void _type(SheetEditorController editor, String text) {
  editor.cellEditor.bridge.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rename has one history entry and monotonic content revisions', () {
    final editor = _editor();
    final sheet = editor.workbook.firstSheet;
    final dependent = editor.workbook.sheets[1].cellA1('A1');
    var commands = 0;
    editor.commands.addListener(() => commands++);
    final initial = editor.contentRevision;
    expect(editor.renameSheet("O'Brien 2026"), isTrue);
    expect(commands, 1);
    expect(editor.isDirty, isTrue);
    expect(editor.contentRevision, greaterThan(initial));
    expect(identical(sheet, editor.workbook.firstSheet), isTrue);
    expect(
      identical(dependent, editor.workbook.sheets[1].cellA1('A1')),
      isTrue,
    );
    expect(dependent.formula, "'O''Brien 2026'!B2");
    expect(dependent.value, 2);
    expect(editor.workbook.namedRanges.single.sheetName, "O'Brien 2026");
    final renamed = editor.contentRevision;
    editor.undo();
    expect(sheet.name, 'Data');
    expect(dependent.formula, 'Data!B2');
    expect(editor.canUndo, isFalse);
    expect(editor.contentRevision, greaterThan(renamed));
    final undone = editor.contentRevision;
    editor.redo();
    expect(sheet.name, "O'Brien 2026");
    expect(editor.contentRevision, greaterThan(undone));
  });

  test('same-name no-op leaves a buffered draft and history untouched', () {
    final editor = _editor();
    final initial = editor.contentRevision;
    expect(editor.renameSheet('Data'), isFalse);
    expect(editor.isDirty, isFalse);
    expect(editor.contentRevision, initial);
    editor.beginCellEdit();
    _type(editor, 'Pending');
    final changed = editor.contentRevision;
    expect(editor.renameSheet('Data'), isFalse);
    expect(editor.cellEditor.editing, isTrue);
    expect(editor.cellEditor.formulaBar, 'Pending');
    expect(editor.contentRevision, changed);
    expect(editor.commands.canUndo, isFalse);
    expect(editor.sheet.cell(_a1).value, isNull);
  });

  test('invalid name and malformed draft reject before committing input', () {
    final editor = _editor();
    editor.beginCellEdit();
    _type(editor, 'Pending');
    final changed = editor.contentRevision;
    for (final name in ['Summary', 'a/b', '', "'Invalid"]) {
      expect(() => editor.renameSheet(name), throwsArgumentError);
    }
    expect(() => editor.renameSheet('Next', sheetIndex: 99), throwsRangeError);
    expect(editor.contentRevision, changed);
    expect(editor.cellEditor.editing, isTrue);
    expect(editor.commands.canUndo, isFalse);
    _type(editor, "='Data!B2");
    final malformed = editor.contentRevision;
    expect(() => editor.renameSheet('Next'), throwsFormatException);
    expect(editor.contentRevision, malformed);
    expect(editor.cellEditor.editing, isTrue);
    expect(editor.cellEditor.formulaBar, "='Data!B2");
    expect(editor.sheet.name, 'Data');
    expect(editor.sheet.cell(_a1).formula, isNull);
  });

  test('unsupported native owners leave the active draft intact', () {
    final editor = _editor(native: true);
    editor.workbook.package!.createPart(
      '/customXml/reference.xml',
      'application/xml',
      utf8.encode('<root target="Data!B2"/>'),
    );
    editor.beginCellEdit();
    _type(editor, 'Pending');
    final before = editor.contentRevision;
    final bytes = {
      for (final part in editor.workbook.package!.parts)
        part.uri: editor.workbook.package!.getPart(part.uri)!.readBytes(),
    };
    expect(() => editor.renameSheet('Next'), throwsUnsupportedError);
    expect(editor.contentRevision, before);
    expect(editor.cellEditor.editing, isTrue);
    expect(editor.commands.canUndo, isFalse);
    expect(editor.sheet.name, 'Data');
    expect({
      for (final part in editor.workbook.package!.parts)
        part.uri: editor.workbook.package!.getPart(part.uri)!.readBytes(),
    }, bytes);
  });

  test(
    'a valid pending formula is committed then renamed and undone in order',
    () {
      final editor = _editor();
      editor.setActiveSheet(1);
      editor.beginCellEdit();
      _type(editor, '=Data!B2+1');
      expect(editor.renameSheet('Next', sheetIndex: 0), isTrue);
      expect(editor.activeSheetIndex, 1);
      expect(editor.cellEditor.editing, isFalse);
      expect(editor.sheet.cell(_a1).formula, "='Next'!B2+1");
      expect(editor.sheet.cell(_a1).value, 3);
      editor.undo();
      expect(editor.workbook.firstSheet.name, 'Data');
      expect(editor.sheet.cell(_a1).formula, '=Data!B2+1');
      expect(editor.sheet.cell(_a1).value, 3);
      editor.undo();
      expect(editor.sheet.cell(_a1).formula, 'Data!B2');
      expect(editor.sheet.cell(_a1).value, 2);
      expect(editor.commands.canUndo, isFalse);
      editor.redo();
      editor.redo();
      expect(editor.workbook.firstSheet.name, 'Next');
      expect(editor.sheet.cell(_a1).formula, "='Next'!B2+1");
    },
  );

  test('validation rejection retains the draft and original sheet names', () {
    final editor = _editor();
    editor.sheet.cell(_a1).value = 1;
    editor.sheet.validations.add(
      SmlDataValidation(
        range: SmlRange(_a1, _a1),
        kind: SmlValidationKind.whole,
        formula1: '1',
        formula2: '10',
        error: 'Enter a number.',
      ),
    );
    editor.beginCellEdit();
    _type(editor, 'Invalid');
    final before = editor.contentRevision;
    expect(() => editor.renameSheet('Next'), throwsStateError);
    expect(editor.contentRevision, before);
    expect(editor.commands.canUndo, isFalse);
    expect(editor.cellEditor.formulaBar, 'Invalid');
    expect(editor.cellEditor.editing, isTrue);
    expect(editor.sheet.name, 'Data');
    expect(editor.sheet.cell(_a1).value, 1);
  });

  test('read-only mode cannot rename or create a revision', () {
    final editor = _editor(readOnly: true);
    final before = editor.contentRevision;
    expect(editor.renameSheet('Next'), isFalse);
    expect(editor.sheet.name, 'Data');
    expect(editor.contentRevision, before);
    expect(editor.isDirty, isFalse);
    expect(editor.canUndo, isFalse);
  });

  test(
    'native rename survives direct and isolate saves with working undo',
    () async {
      final editor = _editor(native: true);
      final captured = editor.contentRevision;
      editor.renameSheet("O'Brien 2026");
      expect(editor.contentRevision, greaterThan(captured));
      final bytes = editor.saveBytes();
      expect(editor.isDirty, isFalse);
      expect(
        SheetDeserializer().readBytes(bytes).sheets[1].cellA1('D1').formula,
        r"'O''Brien 2026'!$B$2",
      );
      editor.undo();
      expect(editor.isDirty, isTrue);
      expect(editor.workbook.firstSheet.name, 'Data');
      editor.redo();
      final latest = await editor.saveBytesAsync();
      expect(
        SheetDeserializer().readBytes(latest).sheets[1].cellA1('D1').formula,
        r"'O''Brien 2026'!$B$2",
      );
      editor.undo();
      expect(editor.workbook.firstSheet.name, 'Data');
      expect(editor.workbook.sheets[1].cellA1('D1').formula, r'Data!$B$2');
    },
  );

  test(
    'native pending formula remains undoable after the renamed workbook saves',
    () {
      final editor = _editor(native: true);
      editor.setActiveSheet(1);
      editor.selection.selectCell(const SmlCellRef(3, 0));
      editor.beginCellEdit();
      _type(editor, '=Data!B2+1');
      editor.renameSheet('Next', sheetIndex: 0);
      final saved = editor.saveBytes();
      expect(
        SheetDeserializer().readBytes(saved).sheets[1].cellA1('D1').formula,
        "'Next'!B2+1",
      );
      editor.undo();
      expect(editor.workbook.firstSheet.name, 'Data');
      expect(editor.sheet.cellA1('D1').formula, '=Data!B2+1');
      final undone = editor.saveBytes();
      expect(
        SheetDeserializer().readBytes(undone).sheets[1].cellA1('D1').formula,
        'Data!B2+1',
      );
    },
  );
  test(
    'later saved cell edits can be undone before the earlier native rename',
    () {
      final editor = _editor(native: true);
      editor.renameSheet('Next');
      editor.setActiveSheet(1);
      editor.selection.selectCell(const SmlCellRef(3, 0));
      editor.beginCellEdit();
      _type(editor, '=Next!B2+10');
      editor.commitPendingEdits();
      editor.saveBytes();
      editor.undo();
      expect(editor.sheet.cellA1('D1').formula, r"'Next'!$B$2");
      editor.undo();
      expect(editor.workbook.firstSheet.name, 'Data');
      expect(editor.sheet.cellA1('D1').formula, r'Data!$B$2');
      final reopened = SheetDeserializer().readBytes(editor.saveBytes());
      expect(reopened.sheets[1].cellA1('D1').formula, r'Data!$B$2');
      expect(reopened.sheets[1].cellA1('D1').value, 2);
    },
  );

  for (final entry in <String, ({String value, SmlCellType type})>{
    '="#REF!"': (value: '#REF!', type: SmlCellType.string),
    '=IF(TRUE,"#N/A","other")': (value: '#N/A', type: SmlCellType.string),
    '=NA()': (value: '#N/A', type: SmlCellType.error),
  }.entries) {
    test(
      'pending formula type survives rename, save and history: ${entry.key}',
      () async {
        final editor = _editor();
        editor.setActiveSheet(1);
        editor.beginCellEdit();
        _type(editor, entry.key);
        editor.renameSheet('Next', sheetIndex: 0);
        final cell = editor.sheet.cell(_a1);
        expect(cell.value, entry.value.value);
        expect(cell.type, entry.value.type);
        final direct = SheetDeserializer().readBytes(editor.saveBytes());
        expect(direct.sheets[1].cell(_a1).value, entry.value.value);
        expect(direct.sheets[1].cell(_a1).type, entry.value.type);
        editor.undo();
        editor.undo();
        expect(cell.formula, 'Data!B2');
        editor.redo();
        editor.redo();
        expect(editor.workbook.firstSheet.name, 'Next');
        final isolated = SheetDeserializer().readBytes(
          await editor.saveBytesAsync(),
        );
        expect(isolated.sheets[1].cell(_a1).value, entry.value.value);
        expect(isolated.sheets[1].cell(_a1).type, entry.value.type);
      },
    );
  }
}
