import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_zotero_document_sources.dart';
import 'package:quds_office_editor/src/embed/word_zotero_sources.dart';

ZoteroCitationItem _item(String id, String title) =>
    ZoteroCitationItem.fromJson({
      'id': id,
      'itemData': {'id': id, 'type': 'book', 'title': title},
    });

void _cite(
  WmlParagraph paragraph,
  String id,
  String text,
  ZoteroCitationItem item,
) {
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation(citationId: id, plainCitation: text, items: [item]),
  );
}

WmlDocument _document() {
  final document = WmlDocument.empty(text: 'Before ');
  _cite(document.paragraphs.single, 'first', '(First)', _item('a', 'Alpha'));
  final second = WmlParagraph(inlines: [WmlRun(text: 'Next ')]);
  _cite(second, 'second', '(Second)', _item('b', 'Beta'));
  document.sections.single.blocks.add(second);
  return document;
}

class _Result {
  bool completed = false;
  List<String>? keys;
  WmlZoteroField? destination;
  bool navigated = false;
}

class _Fixture {
  _Fixture(this.controller, this.references, this.selected, this.result);

  final WordEditorController controller;
  final List<ZoteroDocumentReference> references;
  final Set<String> selected;
  final _Result result;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<_Fixture> _open(
  WidgetTester tester,
  WmlDocument document, {
  Size size = const Size(1200, 1000),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = WordEditorController(
    document: document,
    config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.selecting),
  );
  controller.proofing.enabled = false;
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  final fields = controller.zoteroFields;
  final references = zoteroDocumentReferences([
    for (final field in fields) ...?field.citation?.items,
  ]);
  final selected = {references.first.selectionKey};
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.keys = await showDialog<List<String>>(
                context: context,
                builder: (_) => ZoteroDocumentSourcesDialog(
                  references: references,
                  selectedKeys: selected,
                  otherSelectionCount: 0,
                  occurrences: zoteroDocumentCitationOccurrences(
                    document,
                    fields,
                  ),
                  canReveal: controller.canRevealZoteroField,
                  onNavigate: (field) {
                    result.destination = field;
                    result.navigated = controller.revealZoteroField(field);
                  },
                ),
              );
              result.completed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open'));
  return _Fixture(controller, references, selected, result);
}

Finder _sourceList() =>
    find.byKey(const ValueKey('zotero-document-source-list'));
Finder _occurrenceList() =>
    find.byKey(const ValueKey('zotero-source-occurrences-list'));
Finder _search() => find.byKey(const ValueKey('zotero-document-source-search'));

Finder _scrollable(Finder list) => find.descendant(
  of: list,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  ),
);

Future<void> _scrollTo(WidgetTester tester, Finder list, Finder target) async {
  await tester.ensureVisible(list);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    140,
    maxScrolls: 20,
    scrollable: _scrollable(list),
  );
  await tester.pumpAndSettle();
}

Future<void> _showOccurrences(WidgetTester tester, int source) async {
  final button = find.byKey(
    ValueKey('zotero-document-source-occurrences-$source'),
  );
  await _scrollTo(tester, _sourceList(), button);
  await _tap(tester, button);
}

Future<void> _go(WidgetTester tester, int occurrence) async {
  final button = find.byKey(
    ValueKey('zotero-source-occurrence-go-$occurrence'),
  );
  await _scrollTo(tester, _occurrenceList(), button);
  await _tap(tester, button);
}

void _unchanged(WordEditorController controller) {
  expect(controller.isDirty, isFalse);
  expect(controller.canUndo, isFalse);
  expect(controller.contentRevision, 0);
}

void main() {
  testWidgets(
    'back from occurrences preserves source search and staged choices',
    (tester) async {
      final fixture = await _open(tester, _document());
      final row = find.byKey(const ValueKey('zotero-document-source-1'));
      await _scrollTo(tester, _sourceList(), row);
      await _tap(
        tester,
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.scrollUntilVisible(
        _search(),
        -160,
        scrollable: _scrollable(_sourceList()),
      );
      await tester.enterText(_search(), 'Beta');
      await tester.pumpAndSettle();
      await _showOccurrences(tester, 1);
      expect(find.text('Body · section 1 · paragraph 2'), findsOneWidget);
      expect(find.text('(Second)'), findsOneWidget);
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-source-occurrences-back')),
      );
      expect(tester.widget<TextField>(_search()).controller!.text, 'Beta');
      expect(tester.widget<CheckboxListTile>(row).value, isTrue);
      expect(fixture.result.destination, isNull);
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-document-sources-apply')),
      );
      expect(
        fixture.result.keys,
        fixture.references.map((item) => item.selectionKey),
      );
      expect(fixture.selected, {fixture.references.first.selectionKey});
      _unchanged(fixture.controller);
    },
  );

  for (final story in ['body', 'footnote', 'endnote']) {
    testWidgets('read-only $story navigation leaves source choices unapplied', (
      tester,
    ) async {
      final document = _document();
      var occurrence = 0;
      if (story != 'body') {
        final note = WordNotes.insert(
          document,
          document.paragraphs.first,
          endnote: story == 'endnote',
          text: 'Note ',
        );
        _cite(note.paragraphs.single, story, '(In note)', _item('a', 'Alpha'));
        occurrence = 1;
      }
      final before = [
        for (final field in WordZotero.fields(document))
          (field.instruction, field.cachedText),
      ];
      final fixture = await _open(tester, document);
      final row = find.byKey(const ValueKey('zotero-document-source-1'));
      await _scrollTo(tester, _sourceList(), row);
      await _tap(
        tester,
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('zotero-document-source-occurrences-0')),
        -160,
        scrollable: _scrollable(_sourceList()),
      );
      await _showOccurrences(tester, 0);
      await _go(tester, occurrence);

      expect(fixture.result.completed, isTrue);
      expect(fixture.result.keys, isNull);
      expect(fixture.result.navigated, isTrue);
      expect(
        fixture.controller.zoteroFieldAtCaret?.citation?.citationId,
        story == 'body' ? 'first' : story,
      );
      expect(fixture.selected, {fixture.references.first.selectionKey});
      expect(
        find.byKey(const ValueKey('zotero-document-sources-dialog')),
        findsNothing,
      );
      expect([
        for (final field in WordZotero.fields(document))
          (field.instruction, field.cachedText),
      ], before);
      _unchanged(fixture.controller);
    });
  }

  testWidgets(
    'stale cache is refused by final navigation without selecting text',
    (tester) async {
      final document = _document();
      final fixture = await _open(tester, document);
      await _showOccurrences(tester, 0);
      // Simulates a host edit which bypassed the ordinary revision counters.
      // The navigation availability hint is intentionally insufficient here.
      fixture.controller.zoteroFields.first.run!.text = '(Other)';
      await _go(tester, 0);

      expect(fixture.result.destination, isNotNull);
      expect(fixture.result.navigated, isFalse);
      expect(fixture.controller.caret.isCollapsed, isTrue);
      expect(fixture.controller.caret.logicalIndex, 0);
      _unchanged(fixture.controller);
    },
  );

  testWidgets('removed paragraph is refused at click time and permits Back', (
    tester,
  ) async {
    final document = _document();
    final fixture = await _open(tester, document);
    await _showOccurrences(tester, 0);
    final button = find.byKey(const ValueKey('zotero-source-occurrence-go-0'));
    await _scrollTo(tester, _occurrenceList(), button);
    document.sections.single.blocks.removeAt(0);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(fixture.result.destination, isNull);
    expect(
      find.byKey(const ValueKey('zotero-source-occurrences-dialog')),
      findsOneWidget,
    );
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    await _tap(
      tester,
      find.byKey(const ValueKey('zotero-source-occurrences-back')),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('zotero-document-sources-cancel')),
    );
    expect(fixture.result.keys, isNull);
    expect(fixture.selected, {fixture.references.first.selectionKey});
    _unchanged(fixture.controller);
  });

  testWidgets(
    'unsupported header citation is inspectable with navigation disabled',
    (tester) async {
      final document = WmlDocument.empty(text: 'Body');
      final header = WmlParagraph(inlines: [WmlRun(text: 'Header ')]);
      _cite(header, 'header', '(Header citation)', _item('a', 'Alpha'));
      document.sections.single.header.add(header);
      final fixture = await _open(tester, document);
      await _showOccurrences(tester, 0);
      final button = find.byKey(
        const ValueKey('zotero-source-occurrence-go-0'),
      );
      await _scrollTo(tester, _occurrenceList(), button);

      expect(find.text('Header · section 1 · paragraph 1'), findsOneWidget);
      expect(find.text('(Header citation)'), findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(fixture.result.destination, isNull);
      _unchanged(fixture.controller);
    },
  );

  testWidgets(
    '320 by 640 doubled-text occurrence browser can navigate and go back',
    (tester) async {
      final fixture = await _open(
        tester,
        _document(),
        size: const Size(320, 640),
        textScale: 2,
      );
      await _showOccurrences(tester, 0);
      final go = find.byKey(const ValueKey('zotero-source-occurrence-go-0'));
      await _scrollTo(tester, _occurrenceList(), go);
      expect(tester.takeException(), isNull);
      await _tap(
        tester,
        find.byKey(const ValueKey('zotero-source-occurrences-back')),
      );
      await _showOccurrences(tester, 0);
      await _go(tester, 0);

      expect(fixture.result.navigated, isTrue);
      expect(fixture.result.keys, isNull);
      _unchanged(fixture.controller);
    },
  );
}
