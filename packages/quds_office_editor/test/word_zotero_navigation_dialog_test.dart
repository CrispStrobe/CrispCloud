import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation() => ZoteroCitation(
  citationId: 'navigate',
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
    throw StateError('Navigation must not request a network connection.');
  }
}

Future<WordEditorController> _mount(
  WidgetTester tester,
  WmlDocument document,
  _Requests requests, {
  WordZoteroTab? initialTab = WordZoteroTab.document,
}) async {
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
                  initialTab: initialTab,
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
  await tester.tap(find.text('References workspace'));
  await _pump(tester);
  return controller;
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openMenu(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('zotero-reference-actions-0'));
  await tester.scrollUntilVisible(
    menu,
    240,
    maxScrolls: 8,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  await _pump(tester);
  await tester.tap(menu);
  await _pump(tester);
  expect(find.text('Go to reference'), findsOneWidget);
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
  for (final inNote in [false, true]) {
    testWidgets(
      'read-only menu closes and reveals ${inNote ? 'note' : 'body'} citation offline',
      (tester) async {
        final document = WmlDocument.empty(text: 'Before ');
        final note = inNote
            ? WordNotes.insert(
                document,
                document.paragraphs.single,
                endnote: false,
                text: 'Note before ',
              )
            : null;
        final paragraph = note?.paragraphs.single ?? document.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation());
        paragraph.inlines.add(WmlRun(text: ' after'));
        final requests = _Requests();
        final controller = await _mount(tester, document, requests);
        final field = controller.zoteroFields.single;
        final before = paragraph.text;
        await _openMenu(tester);
        expect(find.text('Edit citation'), findsNothing);
        expect(find.text('Edit in Zotero…'), findsNothing);
        await tester.tap(find.text('Go to reference'));
        await _pump(tester);
        expect(find.byTooltip('Close Zotero'), findsNothing);
        expect(controller.zoteroFieldAtCaret?.citation?.citationId, 'navigate');
        if (note != null) {
          final editor = tester.widget<TextField>(
            find.byKey(ValueKey<String>('notes-edit-${note.id}')),
          );
          expect(editor.readOnly, isTrue);
          expect(editor.focusNode!.hasFocus, isTrue);
          expect(
            editor.controller!.selection,
            controller.noteEditingTarget?.selection,
          );
        } else {
          expect(controller.caret.normalizedRange, (
            startPara: 0,
            startIdx: field.start,
            endPara: 0,
            endIdx: field.end,
          ));
        }
        expect(paragraph.text, before);
        expect(requests.requests, isEmpty);
        expect(controller.canUndo, isFalse);
        expect(controller.contentRevision, 0);
        expect(controller.isDirty, isFalse);
        await _finish(tester, controller);
      },
    );
  }

  testWidgets(
    'bibliography navigation is recognized when normal workspace reopens',
    (tester) async {
      final document = WmlDocument.empty(text: 'Before bibliography');
      document.sections.single.blocks.addAll(
        WordZotero.nativeBibliographyParagraphs(
          instruction:
              ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ',
          text: 'First entry.\nSecond entry.',
        ),
      );
      final requests = _Requests();
      final controller = await _mount(
        tester,
        document,
        requests,
        initialTab: null,
      );
      await tester.tap(find.text('Document'));
      await _pump(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Go to reference'));
      await _pump(tester);
      expect(controller.zoteroFieldAtCaret?.kind, ZoteroFieldKind.bibliography);
      await tester.tap(find.text('References workspace'));
      await _pump(tester);
      expect(find.text('Bibliography at the caret'), findsOneWidget);
      expect(requests.requests, isEmpty);
      expect(controller.canUndo, isFalse);
      await _finish(tester, controller);
    },
  );

  testWidgets('unsupported header reference keeps navigation disabled', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Body');
    final header = WmlParagraph(inlines: [WmlRun(text: 'Header ')]);
    WordZotero.insertCitation(header, _citation());
    document.sections.single.header.add(header);
    final requests = _Requests();
    final controller = await _mount(tester, document, requests);
    await _openMenu(tester);
    final action = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Go to reference'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(action.enabled, isFalse);
    expect(controller.caret.isCollapsed, isTrue);
    expect(controller.isEditingHeaderFooter, isFalse);
    expect(requests.requests, isEmpty);
    expect(controller.canUndo, isFalse);
    await _finish(tester, controller);
  });

  testWidgets('a field changed after opening its menu is not selected', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Before ');
    WordZotero.insertCitation(document.paragraphs.single, _citation());
    final requests = _Requests();
    final controller = await _mount(tester, document, requests);
    await _openMenu(tester);
    controller.zoteroFields.single.run!.text = '(Changed by host)';
    await tester.tap(find.text('Go to reference'));
    await _pump(tester);
    expect(find.byTooltip('Close Zotero'), findsNothing);
    expect(controller.caret.isCollapsed, isTrue);
    expect(controller.caret.logicalIndex, 0);
    expect(requests.requests, isEmpty);
    expect(controller.canUndo, isFalse);
    await _finish(tester, controller);
  });
}
