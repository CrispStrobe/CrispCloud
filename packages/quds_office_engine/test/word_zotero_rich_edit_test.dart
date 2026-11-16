import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

ZoteroCitation _citation([String id = 'mixed']) => ZoteroCitation(
  citationId: id,
  plainCitation: 'Book 12',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Book'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
      locator: '12',
      label: 'page',
    ),
  ],
);

List<WmlInline> _packet({String? code, bool locked = false}) => [
  WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.begin,
    sourceXml: locked
        ? '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
              'w:fldCharType="begin" w:fldLock="1"/>'
        : null,
  ),
  WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.instruction,
    text: code ?? _citation().fieldInstruction,
  ),
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
  WmlRun(text: 'Book', properties: WmlRunProps(italic: true)),
  WmlRun(text: ' 12'),
  WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
];

WmlDocument _document() {
  final document = WmlDocument.empty();
  document.paragraphs.single.inlines
    ..clear()
    ..addAll([
      WmlRun(text: 'Before ', commentIds: [42]),
      ..._packet(),
      WmlRun(text: ' after', properties: WmlRunProps(bold: true)),
    ]);
  return document;
}

void _expectIntact(WmlDocument document) {
  final field = WordZotero.fields(document).single;
  expect(field.cachedText, 'Book 12');
  expect(field.citation!.items.single.locator, '12');
  expect(field.canEdit, isTrue);
  expect(WordFieldSpans.unbalanced(document), isEmpty);
  final runs = field.paragraph.inlines.whereType<WmlRun>();
  expect(runs.singleWhere((r) => r.text == 'Book').properties.italic, isTrue);
  expect(runs.singleWhere((r) => r.text == ' 12').properties.italic, isFalse);
}

void main() {
  test('native insertion retains mixed citation formatting as one field', () {
    final document = WmlDocument.empty(text: 'Before  after');
    final paragraph = document.paragraphs.single;
    final rich = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
    WordZotero.insertNativeCitation(
      paragraph,
      instruction: _citation().fieldInstruction,
      text: rich.plainText,
      formattedText: rich,
      index: 7,
    );
    expect(paragraph.text, 'Before Book 12 after');
    _expectIntact(document);
  });

  test(
    'native replacement upgrades a simple field without losing neighbors',
    () {
      final document = WmlDocument.empty(text: 'Before  after');
      final paragraph = document.paragraphs.single;
      WordZotero.insertCitation(paragraph, _citation(), index: 7);
      final before = paragraph.inlines.first;
      final after = paragraph.inlines.last;
      final rich = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
      WordZotero.replaceNativeResult(
        WordZotero.fields(document).single,
        instruction: _citation().fieldInstruction,
        text: rich.plainText,
        formattedText: rich,
      );
      expect(identical(paragraph.inlines.first, before), isTrue);
      expect(identical(paragraph.inlines.last, after), isTrue);
      _expectIntact(document);
    },
  );

  test('a caret inside a mixed citation moves after the complete packet', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    expect(WmlRunEdit.normalizeRange(paragraph, 9, 9), (start: 14, end: 14));
    WmlRunEdit.replaceRange(paragraph, 9, 9, '!');
    expect(paragraph.text, 'Before Book 12! after');
    _expectIntact(document);
  });

  for (final replacement in ['', 'Replacement']) {
    test(
      'partial mixed citation replacement removes its entire packet: "$replacement"',
      () {
        final document = _document();
        final paragraph = document.paragraphs.single;
        final before = paragraph.inlines.first;
        final after = paragraph.inlines.last;
        WmlRunEdit.replaceRange(paragraph, 9, 11, replacement);
        expect(paragraph.text, 'Before $replacement after');
        expect(WordZotero.fields(document), isEmpty);
        expect(paragraph.inlines.whereType<WmlFieldBoundary>(), isEmpty);
        expect(identical(paragraph.inlines.first, before), isTrue);
        expect(identical(paragraph.inlines.last, after), isTrue);
        expect((before as WmlRun).commentIds, [42]);
        expect((after as WmlRun).properties.bold, isTrue);
      },
    );
  }

  for (final position in [7, 9, 14]) {
    test(
      'paste at citation position $position keeps the field packet intact',
      () {
        final document = _document();
        final paragraph = document.paragraphs.single;
        WmlRunEdit.insertRuns(paragraph, position, [
          WmlRun(
            text: 'PASTE',
            properties: WmlRunProps(underline: WmlUnderline.single),
          ),
        ]);
        expect(
          paragraph.text,
          position == 7
              ? 'Before PASTEBook 12 after'
              : 'Before Book 12PASTE after',
        );
        _expectIntact(document);
        final field = WordZotero.fields(document).single;
        expect(field.cachedText, isNot(contains('PASTE')));
      },
    );
  }

  for (final position in [7, 14]) {
    test(
      'paragraph split at citation edge $position keeps every marker together',
      () {
        final document = _document();
        final paragraph = document.paragraphs.single;
        final tail = WmlRunEdit.splitParagraphInlines(paragraph, position);
        document.sections.single.blocks.add(WmlParagraph(inlines: tail));
        expect(
          document.paragraphs.map((p) => p.text).toList(),
          position == 7
              ? ['Before ', 'Book 12 after']
              : ['Before Book 12', ' after'],
        );
        _expectIntact(document);
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        _expectIntact(reopened);
      },
    );
  }

  test('paragraph split within a mixed citation refuses before mutation', () {
    final document = _document();
    final paragraph = document.paragraphs.single;
    final before = List<WmlInline>.of(paragraph.inlines);
    expect(
      () => WmlRunEdit.splitParagraphInlines(paragraph, 9),
      throwsArgumentError,
    );
    expect(paragraph.inlines, orderedEquals(before));
    _expectIntact(document);
  });

  test(
    'formatting a partial citation selects all result runs without splitting it',
    () {
      final document = _document();
      final paragraph = document.paragraphs.single;
      WmlRunEdit.applyRange(
        paragraph,
        9,
        10,
        (p) => p.underline = WmlUnderline.single,
      );
      _expectIntact(document);
      final result = paragraph.inlines.whereType<WmlRun>().where(
        (r) => r.text == 'Book' || r.text == ' 12',
      );
      expect(
        result.every((r) => r.properties.underline == WmlUnderline.single),
        isTrue,
      );
      expect(
        (paragraph.inlines.first as WmlRun).properties.underline,
        WmlUnderline.none,
      );
    },
  );

  for (final kind in [
    'locked',
    'malformed',
    'unbalanced',
    'nested',
    'duplicate separator',
    'late instruction',
  ]) {
    test(
      '$kind Zotero packets refuse generic interior editing without mutation',
      () {
        final document = WmlDocument.empty();
        final paragraph = document.paragraphs.single;
        final packet = _packet(
          locked: kind == 'locked',
          code: kind == 'malformed'
              ? ' ADDIN ZOTERO_ITEM CSL_CITATION {broken} '
              : null,
        );
        if (kind == 'unbalanced') packet.removeLast();
        if (kind == 'duplicate separator') {
          packet.insert(
            3,
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          );
        }
        if (kind == 'late instruction') {
          packet.insert(
            3,
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: ' '),
          );
        }
        if (kind == 'nested') {
          packet.insertAll(3, [
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
            WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.instruction,
              text: ' PAGE ',
            ),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
            WmlRun(text: '1'),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          ]);
        }
        paragraph.inlines
          ..clear()
          ..addAll([
            WmlRun(text: 'Before '),
            ...packet,
            WmlRun(text: ' after'),
          ]);
        final before = List<WmlInline>.of(paragraph.inlines);
        final text = paragraph.text;
        if (kind != 'unbalanced') {
          expect(WordZotero.fields(document).single.canEdit, isFalse);
        }
        expect(
          () => WmlRunEdit.replaceRange(paragraph, 8, 9, 'X'),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines, orderedEquals(before));
        expect(paragraph.text, text);
      },
    );
  }

  for (final isolate in [false, true]) {
    test(
      'mixed citation styles survive repeated ${isolate ? "isolate" : "direct"} DOCX saves',
      () async {
        var document = _document();
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          document = WordDeserializer().readBytes(bytes);
          _expectIntact(document);
          final paragraph = document.paragraphs.single;
          WmlRunEdit.insertRuns(paragraph, 9, [WmlRun(text: '!')]);
          _expectIntact(document);
        }
      },
    );
  }

  for (final range in [(7, 14), (9, 11)]) {
    test('copy range $range retains one complete linked rich citation', () {
      final source = _document();
      final copied = WmlClone.slicedParagraph(
        source.paragraphs.single,
        range.$1,
        range.$2,
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [copied]),
        ],
      );
      expect(copied.text, 'Book 12');
      _expectIntact(document);
      final destination = WmlDocument.empty(text: 'Paste here: ');
      WmlRunEdit.insertInlines(
        destination.paragraphs.single,
        12,
        copied.inlines,
      );
      expect(destination.paragraphs.single.text, 'Paste here: Book 12');
      _expectIntact(destination);
      expect(
        identical(
          WordZotero.fields(source).single.paragraph,
          WordZotero.fields(destination).single.paragraph,
        ),
        isFalse,
      );
    });
  }

  test('copying text beside a citation omits all unselected field markers', () {
    final source = _document().paragraphs.single;
    for (final range in [(0, 7), (14, source.text.length)]) {
      final copied = WmlClone.slicedParagraph(source, range.$1, range.$2);
      expect(copied.inlines.whereType<WmlFieldBoundary>(), isEmpty);
    }
  });

  for (final position in [7, 9, 14]) {
    test(
      'clone split at $position keeps complete Zotero packets on one side',
      () {
        final source = _document().paragraphs.single;
        final split = WmlClone.splitInlines(source, position);
        final document = WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(inlines: split.head),
                WmlParagraph(inlines: split.tail),
              ],
            ),
          ],
        );
        _expectIntact(document);
        expect(
          document.paragraphs.map((p) => p.text).toList(),
          position == 7
              ? ['Before ', 'Book 12 after']
              : ['Before Book 12', ' after'],
        );
      },
    );
  }

  test(
    'adjacent citations accept paste between packets and delete as complete units',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      paragraph.inlines
        ..clear()
        ..addAll([
          ..._packet(code: _citation('a').fieldInstruction),
          ..._packet(code: _citation('b').fieldInstruction),
        ]);
      WmlRunEdit.insertRuns(paragraph, 7, [WmlRun(text: ' gap ')]);
      final fields = WordZotero.fields(document);
      expect(fields.map((f) => f.cachedText), ['Book 12', 'Book 12']);
      expect(fields.map((f) => f.nested), [false, false]);
      expect(paragraph.text, 'Book 12 gap Book 12');
      WmlRunEdit.replaceRange(paragraph, 6, 13, 'One');
      expect(paragraph.text, 'One');
      expect(WordZotero.fields(document), isEmpty);
      expect(paragraph.inlines.whereType<WmlFieldBoundary>(), isEmpty);
    },
  );

  test(
    'empty citation packets are not captured by text inserted at their offset',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      final packet = _packet();
      for (final run in packet.whereType<WmlRun>()) {
        run.text = '';
      }
      paragraph.inlines
        ..clear()
        ..addAll([...packet, WmlRun(text: 'After')]);
      WmlRunEdit.insertRuns(paragraph, 0, [WmlRun(text: 'Before')]);
      expect(paragraph.text, 'BeforeAfter');
      expect(WordZotero.fields(document).single.cachedText, isEmpty);
      expect(WordFieldSpans.unbalanced(document), isEmpty);
    },
  );

  test(
    'bookmarks and content controls surrounding a deleted citation survive',
    () {
      final document = _document();
      final paragraph = document.paragraphs.single;
      final control = WmlContentControlData(
        xml:
            '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr><w:id w:val="5"/></w:sdtPr><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: [],
        id: '5',
      );
      final start = WmlContentControlBoundary(control: control, start: true);
      final end = WmlContentControlBoundary(control: control, start: false);
      final bookmarkStart = WmlBookmarkBoundary(
        id: '6',
        isStart: true,
        name: 'AroundCitation',
      );
      final bookmarkEnd = WmlBookmarkBoundary(id: '6', isStart: false);
      paragraph.inlines.insertAll(1, [start, bookmarkStart]);
      paragraph.inlines.insertAll(paragraph.inlines.length - 1, [
        bookmarkEnd,
        end,
      ]);
      WmlRunEdit.replaceRange(paragraph, 9, 11, 'Replacement');
      expect(paragraph.text, 'Before Replacement after');
      expect(WordZotero.fields(document), isEmpty);
      expect(paragraph.inlines.whereType<WmlContentControlBoundary>(), [
        start,
        end,
      ]);
      expect(paragraph.inlines.whereType<WmlBookmarkBoundary>(), [
        bookmarkStart,
        bookmarkEnd,
      ]);
      expect(
        WordContentControls.spans(paragraph).single.control,
        same(control),
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(reopened.paragraphs.single.text, paragraph.text);
      expect(
        WordContentControls.spans(reopened.paragraphs.single),
        hasLength(1),
      );
    },
  );

  test(
    'mixed native replacement refuses annotated cache text without losing comment ownership',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      WordZotero.insertCitation(paragraph, _citation());
      final original = WordZotero.fields(document).single;
      original.run!.commentIds.add(9);
      final rich = ZoteroFormattedText.fromHtml('<i>Book</i> 12');
      expect(
        () => WordZotero.replaceNativeResult(
          original,
          instruction: original.instruction,
          text: rich.plainText,
          formattedText: rich,
        ),
        throwsUnsupportedError,
      );
      expect(WordZotero.fields(document).single.run!.commentIds, [9]);
      expect(paragraph.text, 'Book 12');
    },
  );
}
