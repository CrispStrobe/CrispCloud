import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String text) => ZoteroCitation(
  citationId: 'note-source',
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': 'source', 'type': 'book', 'title': 'Notes research'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

class _Desktop {
  _Desktop({this.edit = false, this.cancel = false});
  final bool edit;
  final bool cancel;
  final requests = <ZoteroHttpRequest>[];
  String documentId = '';
  String fieldId = '';

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final index = requests.length;
    requests.add(request);
    final decoded = jsonDecode(request.body!);
    if (index == 0) {
      documentId = (decoded as Map)['docId'] as String;
      expect(decoded['command'], 'addEditCitation');
    } else if (decoded is Map && decoded['id'] is String) {
      fieldId = decoded['id'] as String;
    }
    final steps = <(String, List<Object?>)>[
      ('Application.getActiveDocument', []),
      if (!cancel) ...[
        (
          edit ? 'Document.cursorInField' : 'Document.insertField',
          [documentId, 'Http', if (!edit) 0],
        ),
        (
          'Field.setCode',
          [
            documentId,
            fieldId,
            'ITEM CSL_CITATION ${jsonEncode(_citation('(Updated)').toJson())}',
          ],
        ),
        ('Field.setText', [documentId, fieldId, '<i>(Updated)</i>', true]),
      ],
      ('Document.complete', [documentId]),
    ];
    expect(index, lessThan(steps.length));
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({
        'command': steps[index].$1,
        'arguments': steps[index].$2,
      }),
    );
  }
}

typedef _Fixture = ({WordEditorController controller, WmlNote note});

Future<_Fixture> _mount(
  WidgetTester tester, {
  bool endnote = false,
  bool existing = false,
  bool secondParagraph = false,
  bool paneOnly = false,
  _Desktop? desktop,
  bool rtl = false,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = paneOnly
      ? const Size(320, 640)
      : const Size(1100, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final document = WmlDocument.empty(text: 'Body stays here');
  final note = WordNotes.insert(
    document,
    document.paragraphs.single,
    endnote: endnote,
    text: secondParagraph ? 'First paragraph' : 'Before ',
  );
  if (secondParagraph) {
    note.paragraphs.add(WmlParagraph(inlines: [WmlRun(text: 'Before ')]));
  }
  if (existing) {
    WordZotero.insertCitation(note.paragraphs.last, _citation('(Old)'));
  }
  note.paragraphs.last.inlines.add(WmlRun(text: ' after'));
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(
      showNotesPane: true,
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    ),
  );
  controller.proofing.enabled = false;
  controller.caret.logicalIndex = 2;
  controller.caret.collapseSelection();
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => showWordZoteroDialog(
                      context,
                      controller: controller,
                      localTransport: desktop?.send,
                    ),
                    child: const Text('References'),
                  ),
                  TextButton(
                    onPressed: () => showWordZoteroDialog(
                      context,
                      controller: controller,
                      localTransport: desktop?.send,
                      initialCommand: ZoteroCitingCommand.addEditCitation,
                    ),
                    child: const Text('Add/Edit citation'),
                  ),
                ],
              ),
              Expanded(
                child: paneOnly
                    ? WordNotesPane(controller: controller, arabic: rtl)
                    : QudsWordEditor(controller: controller),
              ),
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

Future<void> _select(
  WidgetTester tester,
  WmlNote note,
  TextSelection selection,
) async {
  // Large text can place the Notes editor below the shared scroll viewport.
  final field = _field(note);
  await tester.ensureVisible(field);
  await tester.pump();
  expect(field.hitTestable(), findsOneWidget);
  await tester.tap(field);
  await tester.pump();
  final widget = tester.widget<TextField>(field);
  expect(widget.focusNode!.hasFocus, isTrue);
  widget.controller!.selection = selection;
  await tester.pump();
}

Future<void> _finish(
  WidgetTester tester,
  WordEditorController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _pump(WidgetTester tester) async {
  // The canvas keeps a caret animation active; wait for route/native-command
  // frames without requiring the entire editor ticker to become idle.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close Zotero'));
  await _pump(tester);
}

void main() {
  for (final parkedSelection in [false, true]) {
    testWidgets(
      'typing undo keeps the visible note target with parked body selection $parkedSelection',
      (tester) async {
        final (:controller, :note) = await _mount(tester);
        if (parkedSelection) {
          controller.caret
            ..logicalIndex = 2
            ..selectionAnchor = 0
            ..selectionAnchorParagraph = 0;
        }
        final original = controller.noteEditText(note);
        await _select(tester, note, const TextSelection.collapsed(offset: 7));
        await tester.enterText(_field(note), 'A much longer explanatory note');
        await tester.pump();
        controller.undo();
        await tester.pump();
        final field = tester.widget<TextField>(_field(note));
        expect(field.focusNode!.hasFocus, isTrue);
        expect(field.controller!.text, original);
        expect(controller.noteEditingTarget?.note, same(note));
        expect(
          controller.noteEditingTarget?.selection,
          field.controller!.selection,
        );
        expect(
          controller.noteEditingTarget!.selection.extentOffset,
          original.length,
        );
        final transaction = controller.beginZoteroTransaction(
          documentId: 'after-typing-undo',
        );
        expect(
          transaction.session.insertionParagraph,
          same(note.paragraphs.single),
        );
        controller.redo();
        await tester.pump();
        expect(field.controller!.text, 'A much longer explanatory note');
        expect(controller.noteEditingTarget?.note, same(note));
        expect(
          controller.noteEditingTarget?.selection,
          field.controller!.selection,
        );
        await _finish(tester, controller);
      },
    );
  }

  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';

    testWidgets(
      '$kind selection survives toolbar focus and opens current field',
      (tester) async {
        final (:controller, :note) = await _mount(
          tester,
          endnote: endnote,
          existing: true,
          secondParagraph: true,
        );
        final start = controller.noteEditText(note).indexOf('(Old)');
        final selection = TextSelection(
          baseOffset: start + 5,
          extentOffset: start,
        );
        await _select(tester, note, selection);
        expect(controller.noteEditingTarget?.selection, selection);
        expect(controller.zoteroFieldAtCaret?.cachedText, '(Old)');
        await tester.tap(find.text('References'));
        await _pump(tester);
        expect(find.text('Citation at the caret'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('zotero-edit-current')).hitTestable(),
          findsOneWidget,
        );
        expect(controller.noteEditingTarget?.note, same(note));
        expect(controller.noteEditingTarget?.selection, selection);
        expect(controller.caret.logicalIndex, 2);
        expect(controller.canUndo, isFalse);
        await _close(tester);
        expect(
          tester.widget<TextField>(_field(note)).controller!.selection,
          selection,
        );
        await _finish(tester, controller);
      },
    );

    testWidgets(
      '$kind native insertion updates pane and exact undo/redo caret',
      (tester) async {
        final desktop = _Desktop();
        final (:controller, :note) = await _mount(
          tester,
          endnote: endnote,
          desktop: desktop,
        );
        final original = controller.noteEditText(note);
        final body = controller.document.paragraphs.single.text;
        const selection = TextSelection.collapsed(offset: 7);
        await _select(tester, note, selection);
        await tester.tap(find.text('Add/Edit citation'));
        await _pump(tester);
        expect(desktop.requests, hasLength(5));
        expect(
          controller.zoteroFields.single.paragraph,
          same(note.paragraphs.single),
        );
        expect(controller.noteEditText(note), 'Before (Updated) after');
        expect(controller.document.paragraphs.single.text, body);
        expect(
          controller.document.footnotes.length +
              controller.document.endnotes.length,
          1,
        );
        await _close(tester);
        final edit = tester.widget<TextField>(_field(note)).controller!;
        expect(edit.text, 'Before (Updated) after');
        expect(edit.selection, const TextSelection.collapsed(offset: 16));
        controller.undo();
        await tester.pump();
        expect(edit.text, original);
        expect(edit.selection, selection);
        expect(controller.canUndo, isFalse);
        controller.redo();
        await tester.pump();
        expect(edit.text, 'Before (Updated) after');
        expect(edit.selection, const TextSelection.collapsed(offset: 16));
        expect(tester.takeException(), isNull);
        await _finish(tester, controller);
      },
    );

    testWidgets('$kind native editing keeps note text and selection on undo', (
      tester,
    ) async {
      final desktop = _Desktop(edit: true);
      final (:controller, :note) = await _mount(
        tester,
        endnote: endnote,
        desktop: desktop,
        existing: true,
      );
      const selection = TextSelection(baseOffset: 12, extentOffset: 7);
      await _select(tester, note, selection);
      await tester.tap(find.text('Add/Edit citation'));
      await _pump(tester);
      expect(desktop.requests, hasLength(5));
      expect(controller.zoteroFields.single.cachedText, '(Updated)');
      await _close(tester);
      controller.undo();
      await tester.pump();
      final edit = tester.widget<TextField>(_field(note)).controller!;
      expect(edit.text, 'Before (Old) after');
      expect(edit.selection, selection);
      expect(controller.canUndo, isFalse);
      await _finish(tester, controller);
    });
  }

  testWidgets('returning to the canvas clears the retained note target', (
    tester,
  ) async {
    final (:controller, :note) = await _mount(tester, existing: true);
    await _select(tester, note, const TextSelection.collapsed(offset: 8));
    expect(controller.noteEditingTarget, isNotNull);
    controller.onRequestFocus!();
    await tester.pump();
    expect(controller.noteEditingTarget, isNull);
    expect(controller.zoteroFieldAtCaret, isNull);
    await _finish(tester, controller);
  });

  testWidgets('native cancellation preserves note text and pane selection', (
    tester,
  ) async {
    final desktop = _Desktop(cancel: true);
    final (:controller, :note) = await _mount(tester, desktop: desktop);
    const selection = TextSelection.collapsed(offset: 7);
    await _select(tester, note, selection);
    final original = controller.noteEditText(note);
    await tester.tap(find.text('Add/Edit citation'));
    await _pump(tester);
    expect(desktop.requests, hasLength(2));
    expect(controller.noteEditText(note), original);
    expect(controller.noteEditingTarget?.selection, selection);
    expect(controller.canUndo, isFalse);
    await _close(tester);
    await _finish(tester, controller);
  });

  testWidgets('changing the note target invalidates an open workspace', (
    tester,
  ) async {
    final desktop = _Desktop(edit: true);
    final (:controller, :note) = await _mount(
      tester,
      existing: true,
      desktop: desktop,
    );
    await _select(tester, note, const TextSelection.collapsed(offset: 8));
    await tester.tap(find.text('References'));
    await _pump(tester);
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 0),
    );
    final action = find.text('Citation in Zotero…');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await _pump(tester);
    expect(find.textContaining('insertion point changed'), findsOneWidget);
    expect(desktop.requests, isEmpty);
    expect(controller.zoteroFields.single.cachedText, '(Old)');
    expect(controller.canUndo, isFalse);
    await _close(tester);
    await _finish(tester, controller);
  });

  for (final rtl in [false, true]) {
    testWidgets(
      'narrow ${rtl ? 'RTL' : 'LTR'} pane retains citation selection',
      (tester) async {
        final (:controller, :note) = await _mount(
          tester,
          existing: true,
          paneOnly: true,
          rtl: rtl,
          scale: 2,
        );
        await _select(tester, note, const TextSelection.collapsed(offset: 8));
        expect(controller.zoteroFieldAtCaret?.cachedText, '(Old)');
        controller.updateZoteroCitation(
          controller.zoteroFieldAtCaret!,
          _citation('(Updated)'),
        );
        await tester.pump();
        expect(
          tester.widget<TextField>(_field(note)).controller!.text,
          'Before (Updated) after',
        );
        controller.undo();
        await tester.pump();
        expect(
          tester.widget<TextField>(_field(note)).controller!.text,
          'Before (Old) after',
        );
        expect(tester.takeException(), isNull);
        await _finish(tester, controller);
      },
    );
  }
}
