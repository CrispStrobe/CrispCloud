import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _a1 = SmlCellRef(0, 0);
const _b1 = SmlCellRef(1, 0);

SheetEditorController _sheet({String text = 'Original'}) {
  final sheet = SmlWorksheet(name: 'Sheet1', sheetId: 1);
  sheet.cell(_a1)
    ..value = text
    ..type = SmlCellType.string;
  sheet.cell(_b1)
    ..value = 'Neighbor'
    ..type = SmlCellType.string;
  final editor = SheetEditorController(workbook: SmlWorkbook(sheets: [sheet]));
  addTearDown(editor.dispose);
  return editor;
}

SlideEditorController _slides({bool table = false}) {
  final shape = PmlShape(
    id: 2,
    name: table ? 'Table' : 'Title',
    text: table ? 'Table caption' : 'Original',
    table: table
        ? PmlTable(
            rows: [
              [PmlTableCell(text: 'Original'), PmlTableCell(text: 'Neighbor')],
            ],
          )
        : null,
  );
  final editor = SlideEditorController(
    presentation: PmlPresentation(
      slides: [
        PmlSlide(id: 256, shapes: [shape]),
      ],
    ),
  );
  addTearDown(editor.dispose);
  if (table) {
    editor.selectTableCell(shape, 0, 0);
  } else {
    editor.selectShape(shape);
  }
  return editor;
}

void _type(InlineCellEditor input, String text) {
  input.bridge.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
}

String _shapeText(PmlShape shape) =>
    shape.table?.cellAt(0, 0).text ?? shape.text;

Future<Uint8List> _save(OfficeController editor, {required bool async}) async =>
    async ? await editor.saveBytesAsync() : editor.saveBytes();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sheet begin, focus, caret and unchanged commit stay clean', () {
    // A string resembling a number must remain a string on an unchanged edit.
    final editor = _sheet(text: '0012');
    final initial = editor.contentRevision;
    editor.beginCellEdit();
    editor.cellEditor.bridge.attach();
    editor.placeEditCaret(1);
    editor.moveEditCaret(1, extend: true);
    editor.cellEditor.selectAll();
    _type(editor.cellEditor, '0012');
    editor.refresh();
    expect(editor.isDirty, isFalse);
    expect(editor.contentRevision, initial);
    expect(editor.canUndo, isFalse);
    editor.commitPendingEdits();
    expect(editor.cellEditor.editing, isFalse);
    expect(editor.sheet.cell(_a1).value, '0012');
    expect(editor.sheet.cell(_a1).type, SmlCellType.string);
    expect(editor.isDirty, isFalse);
    expect(editor.contentRevision, initial);
    expect(editor.canUndo, isFalse);
    editor.beginCellEdit();
    editor.cancelCellEdit();
    expect(editor.contentRevision, initial);
    expect(editor.isDirty, isFalse);
  });

  test(
    'sheet drafts track text changes before any command or cell mutation',
    () {
      final editor = _sheet();
      var commands = 0;
      editor.commands.addListener(() => commands++);
      final initial = editor.contentRevision;
      editor.beginCellEdit();
      _type(editor.cellEditor, 'Draft');
      final changed = editor.contentRevision;
      expect(changed, greaterThan(initial));
      expect(editor.isDirty, isTrue);
      expect(editor.canUndo, isTrue);
      expect(editor.sheet.cell(_a1).value, 'Original');
      expect(commands, 0);
      editor.placeEditCaret(0);
      _type(editor.cellEditor, 'Draft');
      expect(editor.contentRevision, changed);
      _type(editor.cellEditor, 'Original');
      final restored = editor.contentRevision;
      expect(restored, greaterThan(changed));
      expect(editor.isDirty, isFalse);
      editor.commitPendingEdits();
      expect(editor.contentRevision, restored);
      expect(commands, 0);
    },
  );

  test('sheet canceled draft restores clean state without an undo step', () {
    final editor = _sheet();
    editor.beginCellEdit(initial: 'Replacement', replace: true);
    final changed = editor.contentRevision;
    expect(editor.isDirty, isTrue);
    editor.cancelCellEdit();
    expect(editor.sheet.cell(_a1).value, 'Original');
    expect(editor.isDirty, isFalse);
    expect(editor.canUndo, isFalse);
    expect(editor.contentRevision, greaterThan(changed));
  });

  test(
    'canceling a sheet draft keeps an unrelated formatting command dirty',
    () {
      final editor = _sheet();
      editor.beginCellEdit();
      _type(editor.cellEditor, 'Discard this');
      editor.setSelectionFillRgb('FF0000');
      final changed = editor.contentRevision;
      editor.cancelCellEdit();
      expect(editor.isDirty, isTrue);
      expect(editor.sheet.cell(_a1).value, 'Original');
      expect(editor.sheet.cell(_a1).fillRgb, 'FF0000');
      expect(editor.contentRevision, greaterThan(changed));
      editor.undo();
      expect(editor.sheet.cell(_a1).fillRgb, isEmpty);
      expect(editor.sheet.cell(_a1).value, 'Original');
    },
  );

  test('sheet undo commits the active draft as the step to undo', () {
    final editor = _sheet();
    editor.beginCellEdit();
    _type(editor.cellEditor, 'Undo this');
    final changed = editor.contentRevision;
    editor.undo();
    expect(editor.cellEditor.editing, isFalse);
    expect(editor.sheet.cell(_a1).value, 'Original');
    expect(editor.contentRevision, greaterThan(changed));
    expect(editor.canRedo, isTrue);
    final undone = editor.contentRevision;
    editor.redo();
    expect(editor.sheet.cell(_a1).value, 'Undo this');
    expect(editor.contentRevision, greaterThan(undone));
  });

  test(
    'sheet saves the edited cell even if selection changed before commit',
    () {
      final editor = _sheet();
      editor.beginCellEdit();
      _type(editor.cellEditor, 'A1 draft');
      editor.selection.selectCell(_b1);
      final reopened = SheetDeserializer().readBytes(editor.saveBytes());
      expect(reopened.sheets.single.cell(_a1).value, 'A1 draft');
      expect(reopened.sheets.single.cell(_b1).value, 'Neighbor');
    },
  );

  for (final async in [false, true]) {
    final api = async ? 'asynchronous' : 'synchronous';
    test(
      'sheet $api save commits a formula draft once with working history',
      () async {
        final editor = _sheet();
        var commands = 0;
        editor.commands.addListener(() => commands++);
        editor.beginCellEdit();
        _type(editor.cellEditor, '=1+2');
        final bytes = await _save(editor, async: async);
        expect(editor.cellEditor.editing, isFalse);
        expect(commands, 1);
        expect(editor.isDirty, async);
        final revision = editor.contentRevision;
        editor.commitPendingEdits();
        expect(editor.contentRevision, revision);
        expect(commands, 1);
        final reopened = SheetDeserializer()
            .readBytes(bytes)
            .sheets
            .single
            .cell(_a1);
        expect(reopened.formula, '1+2');
        expect(reopened.value, 3);
        editor.undo();
        expect(editor.sheet.cell(_a1).value, 'Original');
        expect(editor.sheet.cell(_a1).formula, isNull);
        editor.redo();
        expect(editor.sheet.cell(_a1).formula, '=1+2');
        expect(editor.sheet.cell(_a1).value, 3);
      },
    );

    test('sheet $api save retains a rejected validation draft', () async {
      final editor = _sheet(text: '1');
      editor.sheet.validations.add(
        SmlDataValidation(
          range: SmlRange(_a1, _a1),
          kind: SmlValidationKind.whole,
          formula1: '1',
          formula2: '10',
          error: 'Enter a whole number from 1 to 10.',
        ),
      );
      editor.beginCellEdit();
      _type(editor.cellEditor, 'Invalid');
      await expectLater(_save(editor, async: async), throwsStateError);
      expect(editor.cellEditor.editing, isTrue);
      expect(editor.cellEditor.formulaBar, 'Invalid');
      expect(editor.sheet.cell(_a1).value, '1');
      expect(editor.isDirty, isTrue);
      expect(editor.commands.canUndo, isFalse);
      expect(editor.lastValidationError, 'Enter a whole number from 1 to 10.');
      _type(editor.cellEditor, '5');
      final bytes = await _save(editor, async: async);
      expect(
        SheetDeserializer().readBytes(bytes).sheets.single.cell(_a1).value,
        5,
      );
    });

    test('Word $api save uses the shared pending-edit boundary', () async {
      final editor = WordEditorController(
        document: WmlDocument.empty(text: 'Body'),
      );
      addTearDown(editor.dispose);
      editor.insertFootnote(text: 'Original');
      editor.commitPendingEdits();
      final note = editor.document.footnotes.single;
      editor.setNoteText(note, 'Pending note');
      final bytes = await _save(editor, async: async);
      expect(
        WordNotes.editableText(
          WordDeserializer().readBytes(bytes).footnotes.single,
        ),
        'Pending note',
      );
      editor.undo();
      expect(editor.noteEditText(note), 'Original');
      editor.redo();
      expect(editor.noteEditText(note), 'Pending note');
    });
  }

  for (final table in [false, true]) {
    final target = table ? 'table cell' : 'shape';
    test(
      'slide $target begin, focus, caret and unchanged commit stay clean',
      () {
        final editor = _slides(table: table);
        final initial = editor.contentRevision;
        editor.beginTextEdit();
        editor.textEditor.bridge.attach(multiline: true);
        editor.placeTextCaret(1);
        editor.moveTextCaret(2, extend: true);
        editor.textEditor.selectAll();
        _type(editor.textEditor, 'Original');
        editor.refresh();
        editor.commitPendingEdits();
        expect(editor.isDirty, isFalse);
        expect(editor.contentRevision, initial);
        expect(editor.canUndo, isFalse);
        expect(_shapeText(editor.selected!), 'Original');
        editor.beginTextEdit();
        editor.cancelTextEdit();
        expect(editor.isDirty, isFalse);
        expect(editor.contentRevision, initial);
      },
    );

    test('slide $target drafts advance revisions only when text changes', () {
      final editor = _slides(table: table);
      var commands = 0;
      editor.commands.addListener(() => commands++);
      final initial = editor.contentRevision;
      editor.beginTextEdit();
      _type(editor.textEditor, 'Draft');
      final changed = editor.contentRevision;
      expect(changed, greaterThan(initial));
      expect(editor.isDirty, isTrue);
      expect(_shapeText(editor.selected!), 'Draft');
      expect(commands, 0);
      editor.placeTextCaret(0);
      _type(editor.textEditor, 'Draft');
      expect(editor.contentRevision, changed);
      _type(editor.textEditor, 'Original');
      final restored = editor.contentRevision;
      expect(restored, greaterThan(changed));
      expect(editor.isDirty, isFalse);
      editor.commitPendingEdits();
      expect(editor.contentRevision, restored);
      expect(commands, 0);
    });

    test(
      'slide $target cancel restores the original target without history',
      () {
        final editor = _slides(table: table);
        editor.beginTextEdit(initial: 'Replacement', replace: true);
        final changed = editor.contentRevision;
        expect(editor.isDirty, isTrue);
        expect(_shapeText(editor.selected!), 'Replacement');
        editor.cancelTextEdit();
        expect(_shapeText(editor.selected!), 'Original');
        if (table) {
          expect(editor.selected!.text, 'Table caption');
          expect(editor.selected!.table!.cellAt(0, 1).text, 'Neighbor');
        }
        expect(editor.isDirty, isFalse);
        expect(editor.canUndo, isFalse);
        expect(editor.contentRevision, greaterThan(changed));
      },
    );

    test(
      'canceling a slide $target draft keeps an unrelated command dirty',
      () {
        final editor = _slides(table: table);
        final shape = editor.selected!;
        final x = shape.transform.x;
        editor.beginTextEdit();
        _type(editor.textEditor, 'Discard this');
        editor.nudgeSelected(12700, 0);
        final changed = editor.contentRevision;
        editor.cancelTextEdit();
        expect(_shapeText(shape), 'Original');
        expect(editor.isDirty, isTrue);
        expect(shape.transform.x, x + 12700);
        expect(editor.contentRevision, greaterThan(changed));
        editor.undo();
        expect(shape.transform.x, x);
        expect(_shapeText(shape), 'Original');
      },
    );

    test('slide $target undo commits the active draft as the step to undo', () {
      final editor = _slides(table: table);
      editor.beginTextEdit();
      _type(editor.textEditor, 'Undo this');
      expect(editor.canUndo, isTrue);
      final changed = editor.contentRevision;
      editor.undo();
      expect(editor.textEditor.editing, isFalse);
      expect(_shapeText(editor.selected!), 'Original');
      expect(editor.contentRevision, greaterThan(changed));
      final undone = editor.contentRevision;
      editor.redo();
      expect(_shapeText(editor.selected!), 'Undo this');
      expect(editor.contentRevision, greaterThan(undone));
    });

    for (final async in [false, true]) {
      final api = async ? 'asynchronous' : 'synchronous';
      test(
        'slide $target $api save commits a draft once with working history',
        () async {
          final editor = _slides(table: table);
          var commands = 0;
          editor.commands.addListener(() => commands++);
          editor.beginTextEdit();
          _type(editor.textEditor, 'Saved draft');
          final bytes = await _save(editor, async: async);
          expect(editor.textEditor.editing, isFalse);
          expect(commands, 1);
          expect(editor.isDirty, async);
          final revision = editor.contentRevision;
          editor.commitPendingEdits();
          expect(editor.contentRevision, revision);
          expect(commands, 1);
          final shape = SlideDeserializer()
              .readBytes(bytes)
              .slides
              .single
              .shapes
              .single;
          expect(_shapeText(shape), 'Saved draft');
          if (table) {
            expect(shape.table!.cellAt(0, 1).text, 'Neighbor');
          }
          editor.undo();
          expect(_shapeText(editor.selected!), 'Original');
          editor.redo();
          expect(_shapeText(editor.selected!), 'Saved draft');
        },
      );
    }
  }

  test('switching slide table cells commits to the original edited cell', () {
    final editor = _slides(table: true);
    final shape = editor.selected!;
    editor.beginTextEdit();
    _type(editor.textEditor, 'First cell');
    editor.selectTableCell(shape, 0, 1);
    expect(editor.textEditor.editing, isFalse);
    editor.beginTextEdit();
    _type(editor.textEditor, 'Second cell');
    editor.cancelTextEdit();
    expect(shape.table!.cellAt(0, 0).text, 'First cell');
    expect(shape.table!.cellAt(0, 1).text, 'Neighbor');
    editor.undo();
    expect(shape.table!.cellAt(0, 0).text, 'Original');
  });

  for (final kind in ['sheet', 'shape', 'table']) {
    test(
      '$kind pending typing invalidates an older save before upload completes',
      () async {
        final OfficeController editor;
        final InlineCellEditor input;
        final void Function() begin;
        final String Function(Uint8List) savedText;
        if (kind == 'sheet') {
          final sheet = _sheet();
          editor = sheet;
          input = sheet.cellEditor;
          begin = () => sheet.beginCellEdit();
          savedText = (bytes) => SheetDeserializer()
              .readBytes(bytes)
              .sheets
              .single
              .cell(_a1)
              .asString;
        } else {
          final slides = _slides(table: kind == 'table');
          editor = slides;
          input = slides.textEditor;
          begin = () => slides.beginTextEdit();
          savedText = (bytes) => _shapeText(
            SlideDeserializer().readBytes(bytes).slides.single.shapes.single,
          );
        }
        begin();
        _type(input, 'Saved snapshot');
        editor.commitPendingEdits();
        final captured = editor.contentRevision;
        final upload = Completer<void>();
        final encoded = Completer<Uint8List>();
        final save = () async {
          encoded.complete(await editor.saveBytesAsync());
          await upload.future;
          if (captured == editor.contentRevision) {
            editor.markClean();
          }
        }();
        final bytes = await encoded.future;
        var commands = 0;
        editor.commands.addListener(() => commands++);
        begin();
        _type(input, 'Newer unsaved draft');
        expect(commands, 0);
        expect(editor.contentRevision, greaterThan(captured));
        upload.complete();
        await save;
        expect(savedText(bytes), 'Saved snapshot');
        expect(input.formulaBar, 'Newer unsaved draft');
        expect(editor.isDirty, isTrue);
        final retry = await editor.saveBytesAsync();
        expect(savedText(retry), 'Newer unsaved draft');
      },
    );

    test('$kind clipboard editing uses the same draft revision path', () async {
      final clipboard = OfficeClipboard.instance;
      final system = clipboard.useSystem;
      clipboard.useSystem = false;
      clipboard.clear();
      addTearDown(() {
        clipboard.clear();
        clipboard.useSystem = system;
      });
      final OfficeController editor;
      final InlineCellEditor input;
      if (kind == 'sheet') {
        final sheet = _sheet();
        editor = sheet;
        input = sheet.cellEditor;
        sheet.beginCellEdit();
      } else {
        final slides = _slides(table: kind == 'table');
        editor = slides;
        input = slides.textEditor;
        slides.beginTextEdit();
      }
      input.selectAll();
      final before = editor.contentRevision;
      await clipboard.write(OfficeClipboardPayload.fromPlain('Pasted draft'));
      await editor.pasteFromClipboard();
      expect(input.formulaBar, 'Pasted draft');
      expect(editor.contentRevision, greaterThan(before));
      expect(editor.isDirty, isTrue);
      final bytes = await editor.saveBytesAsync();
      if (kind == 'sheet') {
        expect(
          SheetDeserializer().readBytes(bytes).sheets.single.cell(_a1).value,
          'Pasted draft',
        );
      } else {
        expect(
          _shapeText(
            SlideDeserializer().readBytes(bytes).slides.single.shapes.single,
          ),
          'Pasted draft',
        );
      }
    });
  }
}
