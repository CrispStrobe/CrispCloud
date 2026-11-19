import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation() => ZoteroCitation(
  citationId: 'target',
  plainCitation: '(Target)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': 'source', 'type': 'book', 'title': 'Reference'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

typedef _Fixture = ({WordEditorController controller, WmlNote note});

Future<_Fixture> _mount(
  WidgetTester tester, {
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
  bool showNotes = true,
  int noteCount = 1,
  bool longNote = false,
  bool returnFocusFromDialog = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final document = WmlDocument.empty(text: 'Body keeps its caret');
  late WmlNote note;
  for (var i = 0; i < noteCount; i++) {
    note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: longNote && i == noteCount - 1
          ? List<String>.filled(
              30,
              'Long explanatory note paragraph.',
            ).join('\n')
          : 'Note $i before ',
    );
  }
  WordZotero.insertCitation(note.paragraphs.last, _citation());
  note.paragraphs.last.inlines.add(WmlRun(text: ' after'));
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(mode: mode, showNotesPane: showNotes),
  );
  controller.proofing.enabled = false;
  controller.caret
    ..logicalIndex = 3
    ..collapseSelection();
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Helper dialog'),
                      actions: [
                        TextButton(
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close helper'),
                        ),
                      ],
                    ),
                  );
                  if (returnFocusFromDialog) controller.requestEditingFocus();
                },
                child: const Text('Open helper'),
              ),
              Expanded(child: QudsWordEditor(controller: controller)),
            ],
          ),
        ),
      ),
    ),
  );
  await _pump(tester);
  return (controller: controller, note: note);
}

Finder _field(WmlNote note) => find.byKey(
  ValueKey<String>('notes-edit-${note.endnote ? 'E' : ''}${note.id}'),
);

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _finish(WidgetTester tester, WordEditorController c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final mode in [
    OfficeInteractionMode.editing,
    OfficeInteractionMode.selecting,
  ]) {
    testWidgets('navigation focuses and scrolls distant note in $mode', (
      tester,
    ) async {
      final (:controller, :note) = await _mount(
        tester,
        mode: mode,
        noteCount: 15,
      );
      final before = controller.noteEditText(note);
      expect(_field(note).hitTestable(), findsNothing);
      expect(
        controller.revealZoteroField(controller.zoteroFields.single),
        isTrue,
      );
      await _pump(tester);
      final field = tester.widget<TextField>(_field(note));
      final start = before.indexOf('(Target)');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(_field(note).hitTestable(), findsOneWidget);
      expect(
        field.controller!.selection,
        TextSelection(
          baseOffset: start,
          extentOffset: start + '(Target)'.length,
        ),
      );
      expect(field.enabled, isTrue);
      expect(field.readOnly, mode == OfficeInteractionMode.selecting);
      if (mode == OfficeInteractionMode.selecting) {
        expect(field.onChanged, isNull);
      }
      expect(controller.noteEditingTarget?.note, same(note));
      expect(controller.noteEditText(note), before);
      expect(controller.caret.logicalIndex, 3);
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
      expect(controller.contentRevision, 0);
      await _finish(tester, controller);
    });
  }

  testWidgets(
    'revealing a note opens the initially hidden default Notes pane',
    (tester) async {
      final (:controller, :note) = await _mount(tester, showNotes: false);
      expect(find.byType(WordNotesPane), findsNothing);
      expect(
        controller.revealZoteroField(controller.zoteroFields.single),
        isTrue,
      );
      await _pump(tester);
      expect(find.byType(WordNotesPane), findsOneWidget);
      final field = tester.widget<TextField>(_field(note));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        controller.noteEditingTarget?.selection,
      );
      expect(controller.canUndo, isFalse);
      await _finish(tester, controller);
    },
  );

  testWidgets('closing a modal returns to the retained Notes caret', (
    tester,
  ) async {
    final (:controller, :note) = await _mount(tester);
    await tester.tap(_field(note));
    await tester.pump();
    final field = tester.widget<TextField>(_field(note));
    const caret = TextSelection.collapsed(offset: 5);
    field.controller!.selection = caret;
    await tester.pump();
    await tester.tap(find.text('Open helper'));
    await _pump(tester);
    expect(find.text('Helper dialog'), findsOneWidget);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(controller.noteEditingTarget?.selection, caret);
    await tester.tap(find.text('Close helper'));
    await _pump(tester);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection, caret);
    expect(controller.noteEditingTarget?.selection, caret);
    expect(controller.caret.logicalIndex, 3);
    expect(controller.canUndo, isFalse);
    await _finish(tester, controller);
  });

  testWidgets('focus signal does not steal input from an active modal route', (
    tester,
  ) async {
    final (:controller, :note) = await _mount(
      tester,
      returnFocusFromDialog: false,
    );
    controller.revealZoteroField(controller.zoteroFields.single);
    await _pump(tester);
    await tester.tap(find.text('Open helper'));
    await _pump(tester);
    final field = tester.widget<TextField>(_field(note));
    controller.requestEditingFocus();
    await _pump(tester);
    expect(find.text('Helper dialog'), findsOneWidget);
    expect(field.focusNode!.hasFocus, isFalse);
    await tester.tap(find.text('Close helper'));
    await _pump(tester);
    controller.requestEditingFocus();
    await _pump(tester);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(
      field.controller!.selection,
      controller.noteEditingTarget?.selection,
    );
    await _finish(tester, controller);
  });

  testWidgets('focus restoration preserves an updated caret in a long note', (
    tester,
  ) async {
    final (:controller, :note) = await _mount(tester, longNote: true);
    final text = controller.noteEditText(note);
    final caret = TextSelection.collapsed(offset: text.length);
    controller.setNoteEditingTarget(note, caret);
    controller.requestEditingFocus();
    await _pump(tester);
    final field = tester.widget<TextField>(_field(note));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection, caret);
    final editable = tester.state<EditableTextState>(
      find.descendant(of: _field(note), matching: find.byType(EditableText)),
    );
    final localCaret = editable.renderEditable.getLocalRectForCaret(
      TextPosition(offset: text.length),
    );
    final globalCaret = editable.renderEditable.localToGlobal(
      localCaret.center,
    );
    final pane = tester.getRect(find.byType(WordNotesPane));
    expect(globalCaret.dy, inInclusiveRange(pane.top, pane.bottom));
    expect(controller.noteEditingTarget?.selection, caret);
    expect(controller.canUndo, isFalse);
    await _finish(tester, controller);
  });

  testWidgets('queued focus for a removed note never targets another note', (
    tester,
  ) async {
    final (:controller, :note) = await _mount(tester, noteCount: 2);
    controller.revealZoteroField(controller.zoteroFields.single);
    controller.document.footnotes.remove(note);
    controller.refresh();
    await _pump(tester);
    expect(_field(note), findsNothing);
    final remaining = tester.widget<TextField>(find.byType(TextField));
    expect(remaining.focusNode!.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    expect(controller.canUndo, isFalse);
    await _finish(tester, controller);
  });

  testWidgets('viewing mode leaves Notes text disabled and unselected', (
    tester,
  ) async {
    final (:controller, :note) = await _mount(
      tester,
      mode: OfficeInteractionMode.viewing,
    );
    final field = tester.widget<TextField>(_field(note));
    expect(field.enabled, isFalse);
    expect(field.readOnly, isTrue);
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isFalse,
    );
    controller.requestEditingFocus();
    await _pump(tester);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(controller.noteEditingTarget, isNull);
    expect(controller.noteFocusRequest, 0);
    await _finish(tester, controller);
  });
}
