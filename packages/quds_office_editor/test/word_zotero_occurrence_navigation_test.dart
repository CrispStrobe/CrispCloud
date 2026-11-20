import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: '(Research)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': 'source', 'type': 'book', 'title': 'Offline research'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

class _Requests {
  final requests = <ZoteroHttpRequest>[];

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    requests.add(request);
    throw StateError('Source occurrence navigation must work offline.');
  }
}

Future<void> _pump(WidgetTester tester) async {
  // An active editor caret can schedule frames indefinitely.
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await _pump(tester);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await _pump(tester);
  expect(tester.takeException(), isNull);
}

Finder _verticalScroll(Finder parent) => find.descendant(
  of: parent,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

Future<WordEditorController> _mount(
  WidgetTester tester,
  WmlDocument document,
  _Requests requests,
) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = WordEditorController(
    document: document,
    config: const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.selecting,
      showNotesPane: true,
    ),
  );
  controller.proofing.enabled = false;
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
                onPressed: () => showWordZoteroDialog(
                  context,
                  controller: controller,
                  transport: requests.send,
                  localTransport: requests.send,
                  initialTab: WordZoteroTab.document,
                ),
                child: const Text('References workspace'),
              ),
              Expanded(child: QudsWordEditor(controller: controller)),
            ],
          ),
        ),
      ),
    ),
  );
  await _pump(tester);
  await _tap(tester, find.text('References workspace'));
  await _tap(tester, find.byKey(const ValueKey('zotero-cited-references')));
  final sources = find.byKey(const ValueKey('zotero-document-source-list'));
  final show = find.byKey(
    const ValueKey('zotero-document-source-occurrences-0'),
  );
  await tester.scrollUntilVisible(
    show,
    160,
    maxScrolls: 8,
    scrollable: _verticalScroll(sources),
  );
  await _tap(tester, show);
  expect(
    find.byKey(const ValueKey('zotero-source-occurrences-dialog')),
    findsOneWidget,
  );
  return controller;
}

Future<Finder> _goButton(WidgetTester tester, int index) async {
  final list = find.byKey(const ValueKey('zotero-source-occurrences-list'));
  final button = find.byKey(ValueKey('zotero-source-occurrence-go-$index'));
  await tester.scrollUntilVisible(
    button,
    160,
    maxScrolls: 8,
    scrollable: _verticalScroll(list),
  );
  await _pump(tester);
  return button;
}

void _clean(WordEditorController controller, _Requests requests) {
  expect(requests.requests, isEmpty);
  expect(controller.canUndo, isFalse);
  expect(controller.canRedo, isFalse);
  expect(controller.isDirty, isFalse);
  expect(controller.contentRevision, 0);
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

void main() {
  for (final story in ['body', 'footnote', 'endnote']) {
    testWidgets(
      'cited-source navigation reveals the read-only $story editor offline',
      (tester) async {
        final document = WmlDocument.empty(text: 'Body before ');
        final note = story == 'body'
            ? null
            : WordNotes.insert(
                document,
                document.paragraphs.single,
                endnote: story == 'endnote',
                text: 'Note before ',
              );
        final paragraph = note?.paragraphs.single ?? document.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation(story));
        paragraph.inlines.add(WmlRun(text: ' after'));
        final before = paragraph.text;
        final requests = _Requests();
        final controller = await _mount(tester, document, requests);
        final field = controller.zoteroFields.single;

        await _tap(tester, await _goButton(tester, 0));

        expect(find.byTooltip('Close Zotero'), findsNothing);
        expect(
          find.byKey(const ValueKey('zotero-document-sources-dialog')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('zotero-source-occurrences-dialog')),
          findsNothing,
        );
        expect(controller.zoteroFieldAtCaret?.citation?.citationId, story);
        if (note == null) {
          expect(controller.caret.normalizedRange, (
            startPara: 0,
            startIdx: field.start,
            endPara: 0,
            endIdx: field.end,
          ));
        } else {
          final editor = tester.widget<TextField>(
            find.byKey(
              ValueKey<String>(
                'notes-edit-${note.endnote ? 'E' : ''}${note.id}',
              ),
            ),
          );
          expect(editor.readOnly, isTrue);
          expect(editor.focusNode!.hasFocus, isTrue);
          expect(identical(controller.noteEditingTarget?.note, note), isTrue);
          expect(
            editor.controller!.selection,
            controller.noteEditingTarget!.selection,
          );
        }
        expect(paragraph.text, before);
        _clean(controller, requests);
        await _finish(tester, controller);
      },
    );
  }

  testWidgets(
    'a replaced document invalidates occurrence navigation before closing',
    (tester) async {
      final document = WmlDocument.empty(text: 'Before ');
      WordZotero.insertCitation(document.paragraphs.single, _citation('old'));
      final requests = _Requests();
      final controller = await _mount(tester, document, requests);
      final button = await _goButton(tester, 0);
      final replacement = WmlDocument.empty(text: 'Replacement document');
      controller.document = replacement;

      // Click the already-painted enabled action: its callback must recheck.
      await tester.tap(button);
      await _pump(tester);

      expect(
        find.byKey(const ValueKey('zotero-source-occurrences-dialog')),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(controller.document, same(replacement));
      expect(controller.caret.isCollapsed, isTrue);
      expect(controller.caret.logicalIndex, 0);
      expect(controller.noteEditingTarget, isNull);
      expect(replacement.paragraphs.single.text, 'Replacement document');
      _clean(controller, requests);
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'a changed field cache fails final validation after all dialogs close',
    (tester) async {
      final document = WmlDocument.empty(text: 'Before ');
      WordZotero.insertCitation(document.paragraphs.single, _citation('old'));
      final requests = _Requests();
      final controller = await _mount(tester, document, requests);
      final button = await _goButton(tester, 0);
      // Equal-length replacement bypasses ordinary revision counters and still
      // satisfies the lightweight range check; final field matching must refuse.
      controller.zoteroFields.single.run!.text = '(Modified)';

      await _tap(tester, button);

      expect(find.byTooltip('Close Zotero'), findsNothing);
      expect(controller.caret.isCollapsed, isTrue);
      expect(controller.caret.logicalIndex, 0);
      expect(controller.noteEditingTarget, isNull);
      expect(document.paragraphs.single.text, 'Before (Modified)');
      _clean(controller, requests);
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'moving the caret while reviewing occurrences keeps the new caret',
    (tester) async {
      final document = WmlDocument.empty(text: 'Before ');
      WordZotero.insertCitation(document.paragraphs.single, _citation('old'));
      final requests = _Requests();
      final controller = await _mount(tester, document, requests);
      final button = await _goButton(tester, 0);
      controller.caret.logicalIndex = 3;
      controller.caret.collapseSelection();

      await tester.tap(button);
      await _pump(tester);

      expect(
        find.byKey(const ValueKey('zotero-source-occurrences-dialog')),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(controller.caret.logicalIndex, 3);
      expect(controller.caret.isCollapsed, isTrue);
      _clean(controller, requests);
      await _finish(tester, controller);
    },
  );
}
