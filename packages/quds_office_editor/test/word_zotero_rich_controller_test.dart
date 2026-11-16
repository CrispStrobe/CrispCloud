import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _docId = 'rich-controller';
ZoteroCitation _citation() => ZoteroCitation(
  citationId: 'mixed-citation',
  plainCitation: 'Book 12',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Book'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '12',
    ),
  ],
);

WordEditorController _controller({bool rich = true}) {
  final document = WmlDocument.empty(text: 'Before  after');
  WordZotero.insertNativeCitation(
    document.paragraphs.single,
    instruction: _citation().fieldInstruction,
    text: 'Book 12',
    index: 7,
    formattedText: rich ? ZoteroFormattedText.fromHtml('<i>Book</i> 12') : null,
  );
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

void _at(WordEditorController controller, int offset, {int paragraph = 0}) {
  controller.caret
    ..paragraphIndex = paragraph
    ..logicalIndex = offset
    ..collapseSelection();
}

void _select(WordEditorController controller, int start, int end) {
  controller.caret
    ..paragraphIndex = 0
    ..logicalIndex = end
    ..selectionAnchorParagraph = 0
    ..selectionAnchor = start;
}

void _expectRich(WmlDocument document, {int fields = 1}) {
  final citations = WordZotero.fields(document);
  expect(citations, hasLength(fields));
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  for (final field in citations) {
    expect(field.cachedText, 'Book 12');
    expect(field.canEdit, isTrue);
    final runs = field.paragraph.inlines.whereType<WmlRun>();
    expect(
      runs.where((r) => r.text == 'Book').every((r) => r.properties.italic),
      isTrue,
    );
    expect(
      runs.where((r) => r.text == ' 12').every((r) => !r.properties.italic),
      isTrue,
    );
    expect(runs.where((r) => r.text == 'Book'), isNotEmpty);
  }
}

Object? _call(
  WordZoteroTransaction tx,
  String command, [
  List<Object?> args = const [],
]) => tx.session.handle(command, [_docId, ...args]);

void _convert(WordEditorController controller, int note) {
  final tx = controller.beginZoteroTransaction(documentId: _docId);
  final fields = _call(tx, 'Document.getFields', ['Http']) as List;
  _call(tx, 'Document.convert', [
    [(fields.single as Map)['id']],
    'Http',
    [note],
  ]);
  // Zotero may leave an unchanged cached result alone during a conversion.
  _call(tx, 'Document.complete');
  tx.apply();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => OfficeClipboard.instance.useSystem = false);
  tearDown(() {
    OfficeClipboard.instance.clear();
    OfficeClipboard.instance.useSystem = true;
  });

  test('native mixed refresh is one undo step and survives DOCX', () {
    final controller = _controller(rich: false);
    final tx = controller.beginZoteroTransaction(documentId: _docId);
    final fields = _call(tx, 'Document.getFields', ['Http']) as List;
    final id = (fields.single as Map)['id'];
    _call(tx, 'Field.setCode', [
      id,
      'ITEM CSL_CITATION ${jsonEncode(_citation().toJson())}',
    ]);
    _call(tx, 'Field.setText', [id, '<i>Book</i> 12', true]);
    _call(tx, 'Document.complete');
    tx.apply();
    _expectRich(controller.document);
    _expectRich(
      WordDeserializer().readBytes(
        WordSerializer().writeBytes(controller.document),
      ),
    );
    controller.undo();
    expect(controller.zoteroFields.single.run, isNotNull);
    expect(controller.zoteroFields.single.run!.properties.italic, isFalse);
    expect(controller.canUndo, isFalse);
    controller.redo();
    _expectRich(controller.document);
  });

  test(
    'typing inside a mixed citation appends outside it and undo restores the packet',
    () {
      final controller = _controller();
      _at(controller, 9);
      controller.insertText('!');
      expect(
        controller.document.paragraphs.single.text,
        'Before Book 12! after',
      );
      expect(controller.caret.logicalIndex, 15);
      _expectRich(controller.document);
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before Book 12 after',
      );
      _expectRich(controller.document);
    },
  );

  test(
    'partial selection deletion removes one complete citation with undo and redo',
    () {
      final controller = _controller();
      _select(controller, 9, 11);
      controller.deleteSelectionOr(backward: true);
      expect(controller.document.paragraphs.single.text, 'Before  after');
      expect(controller.zoteroFields, isEmpty);
      expect(
        controller.document.paragraphs.single.inlines
            .whereType<WmlFieldBoundary>(),
        isEmpty,
      );
      controller.undo();
      _expectRich(controller.document);
      controller.redo();
      expect(controller.zoteroFields, isEmpty);
    },
  );

  test(
    'Enter inside the citation splits after its complete field and is undoable',
    () {
      final controller = _controller();
      _at(controller, 9);
      controller.insertParagraphBreak();
      expect(controller.document.paragraphs.map((p) => p.text), [
        'Before Book 12',
        ' after',
      ]);
      _expectRich(controller.document);
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before Book 12 after',
      );
      _expectRich(controller.document);
    },
  );

  test(
    'multiline paste inside the citation starts outside the complete field',
    () async {
      final controller = _controller();
      _at(controller, 9);
      await OfficeClipboard.instance.write(
        OfficeClipboardPayload.fromPlain('!\nNext'),
      );
      await controller.pasteFromClipboard();
      expect(controller.document.paragraphs.map((p) => p.text), [
        'Before Book 12!',
        'Next after',
      ]);
      _expectRich(controller.document);
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before Book 12 after',
      );
      _expectRich(controller.document);
    },
  );

  test(
    'partial citation copy retains linked mixed content through internal paste and undo',
    () async {
      final controller = _controller();
      controller.document.sections.single.blocks.add(
        WmlParagraph(inlines: [WmlRun(text: 'Target ')]),
      );
      _select(controller, 9, 11);
      await controller.copyToClipboard();
      expect(OfficeClipboard.instance.local!.plain, 'Book 12');
      _at(controller, 7, paragraph: 1);
      await controller.pasteFromClipboard();
      expect(controller.document.paragraphs.last.text, 'Target Book 12');
      _expectRich(controller.document, fields: 2);
      controller.undo();
      _expectRich(controller.document);
      expect(controller.document.paragraphs.last.text, 'Target ');
      controller.redo();
      _expectRich(controller.document, fields: 2);
    },
  );

  for (final note in [1, 2]) {
    test(
      'mixed cache moves inline to note type $note and back without setText',
      () {
        final controller = _controller();
        _at(controller, 0);
        _convert(controller, note);
        _expectRich(controller.document);
        expect(
          note == 1
              ? controller.document.footnotes
              : controller.document.endnotes,
          hasLength(1),
        );
        final bytes = WordSerializer().writeBytes(controller.document);
        _expectRich(WordDeserializer().readBytes(bytes));
        controller.undo();
        _expectRich(controller.document);
        expect(
          controller.document.paragraphs.single.text,
          'Before Book 12 after',
        );
        controller.redo();
        _expectRich(controller.document);
        _at(controller, 0);
        _convert(controller, 0);
        expect(controller.document.footnotes, isEmpty);
        expect(controller.document.endnotes, isEmpty);
        expect(
          controller.document.paragraphs.single.text,
          'Before Book 12 after',
        );
        _expectRich(controller.document);
        controller.undo();
        expect(
          note == 1
              ? controller.document.footnotes
              : controller.document.endnotes,
          hasLength(1),
        );
        _expectRich(controller.document);
      },
    );
  }
}
