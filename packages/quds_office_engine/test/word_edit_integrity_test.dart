import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

OpcPackage _source(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr/></w:body></w:document>',
      );
  return package;
}

WmlDocument _document(WmlBlock block) => WmlDocument(
  sections: <WmlSection>[
    WmlSection(blocks: <WmlBlock>[block]),
  ],
);

WmlParagraph _noteParagraph() => WmlParagraph(
  inlines: <WmlInline>[
    WmlRun(text: 'Before '),
    WmlRun(text: '12', noteRefId: 12, noteRefEndnote: true),
    WmlRun(text: ' after'),
  ],
);

void main() {
  group('run boundaries preserve export semantics', () {
    final variants = <String, void Function(WmlRunProps)>{
      'character style': (p) => p.styleId = 'Emphasis',
      'unmodeled source property': (p) => p.sourcePropertiesXml =
          '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:lang w:val="fr-FR"/>'
          '</w:rPr>',
      'import baseline': (p) =>
          p.importedValues = <String, String>{'bold': 'false'},
      'explicit default': (p) => p.explicitProperties.add('bold'),
    };
    for (final variant in variants.entries) {
      test('coalesce keeps a distinct ${variant.key}', () {
        final second = WmlRunProps();
        variant.value(second);
        final paragraph = WmlParagraph(
          inlines: <WmlInline>[
            WmlRun(text: 'one'),
            WmlRun(text: 'two', properties: second),
          ],
        );
        WmlRunEdit.coalesce(paragraph);
        expect(paragraph.inlines, hasLength(2));
        expect(paragraph.text, 'onetwo');
      });
    }

    test('equivalent copied provenance can still coalesce', () {
      final properties = WmlRunProps(styleId: 'Emphasis')
        ..sourcePropertiesXml = '<rPr/>'
        ..importedValues = <String, String>{'color': '000000', 'bold': 'false'}
        ..explicitProperties.addAll(<String>['bold', 'color']);
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(text: 'one', properties: properties),
          WmlRun(text: 'two', properties: properties.copy()),
        ],
      );
      WmlRunEdit.coalesce(paragraph);
      expect(paragraph.inlines, hasLength(1));
      expect(paragraph.text, 'onetwo');
    });

    test('formatting an imported range retains language on each run', () {
      WmlDocument document = WordDeserializer().read(
        _source(
          '<w:p><w:r><w:rPr><w:lang w:val="en-GB"/></w:rPr>'
          '<w:t>Hello</w:t></w:r>'
          '<w:r><w:rPr><w:lang w:val="fr-FR"/></w:rPr>'
          '<w:t>Bonjour</w:t></w:r></w:p>',
        ),
      );
      WmlRunEdit.applyRange(
        document.paragraphs.single,
        0,
        document.paragraphs.single.text.length,
        (p) => p.bold = true,
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = WordSerializer().write(document);
        final paragraph = XmlDocument.parse(
          saved.getPart('/word/document.xml')!.readText(),
        ).root!.firstChild('body')!.firstChild('p')!;
        final runs = paragraph.childrenNamed('r');
        expect(runs, hasLength(2));
        expect(
          runs.map(
            (r) => r.firstChild('rPr')!.firstChild('lang')!.getAttribute('val'),
          ),
          <String>['en-GB', 'fr-FR'],
        );
        expect(runs.map((r) => r.firstChild('t')!.text), <String>[
          'Hello',
          'Bonjour',
        ]);
        expect(
          runs.every((r) => r.firstChild('rPr')!.firstChild('b') != null),
          isTrue,
        );
        document = WordDeserializer().readBytes(saved.save());
      }
    });

    test('internal and file links with equal labels remain distinct', () {
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(
            text: 'Bookmark',
            hyperlink: const WmlHyperlink(anchor: 'topic'),
          ),
          WmlRun(
            text: 'File',
            hyperlink: const WmlHyperlink(file: 'topic'),
          ),
        ],
      );
      WmlRunEdit.coalesce(paragraph);
      expect(paragraph.inlines, hasLength(2));
      final saved = WordSerializer().write(_document(paragraph));
      final links = XmlDocument.parse(
        saved.getPart('/word/document.xml')!.readText(),
      ).root!.firstChild('body')!.firstChild('p')!.childrenNamed('hyperlink');
      expect(links, hasLength(2));
      expect(links.first.getAttribute('anchor'), 'topic');
      final fileId = links.last.getAttribute(
        'id',
        namespaceUri: OfficeNamespaces.r,
      );
      expect(fileId, isNotNull);
      final relationship = saved
          .relationshipsFor('/word/document.xml')
          .byId(fileId!);
      expect(relationship!.target, 'topic');
      expect(relationship.targetMode, RelationshipTargetMode.external);
      final copy = WordDeserializer().readBytes(saved.save());
      final imported = copy.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(imported.first.hyperlink!.anchor, 'topic');
      expect(imported.last.hyperlink!.isInternal, isFalse);
    });
  });

  group('note marks are atomic fields', () {
    for (final bounds in <(int, int)>[(7, 8), (8, 9), (9, 8), (8, 8)]) {
      test('normalize selection $bounds', () {
        final range = WmlRunEdit.normalizeRange(
          _noteParagraph(),
          bounds.$1,
          bounds.$2,
        );
        expect(
          range,
          bounds.$1 == bounds.$2 ? (start: 9, end: 9) : (start: 7, end: 9),
        );
      });
    }

    test('partial deletion removes the complete note mark', () {
      final paragraph = _noteParagraph();
      WmlRunEdit.replaceRange(paragraph, 8, 9, '');
      expect(paragraph.text, 'Before  after');
      expect(
        paragraph.inlines.whereType<WmlRun>().where((r) => r.noteRefId != null),
        isEmpty,
      );
    });

    test(
      'partial replacement removes the note without deleting adjacent text',
      () {
        final paragraph = _noteParagraph();
        WmlRunEdit.replaceRange(paragraph, 7, 8, 'replacement');
        expect(paragraph.text, 'Before replacement after');
        expect(
          paragraph.inlines.whereType<WmlRun>().where(
            (r) => r.noteRefId != null,
          ),
          isEmpty,
        );
      },
    );

    test('typing inside a mark inserts immediately after it', () {
      final paragraph = _noteParagraph();
      WmlRunEdit.replaceRange(paragraph, 8, 8, '!');
      expect(paragraph.text, 'Before 12! after');
      final reference = paragraph.inlines.whereType<WmlRun>().singleWhere(
        (r) => r.noteRefId != null,
      );
      expect(reference.text, '12');
      expect(reference.noteRefEndnote, isTrue);
    });

    test('sliced paragraph and extraction retain the whole note label', () {
      final paragraph = _noteParagraph();
      final slice = WmlClone.slicedParagraph(paragraph, 8, 9);
      final extracted = WmlRunEdit.extractRuns(paragraph, 8, 9);
      for (final run in <WmlRun>[
        slice.inlines.whereType<WmlRun>().single,
        extracted.single,
      ]) {
        expect(run.text, '12');
        expect(run.noteRefId, 12);
        expect(run.noteRefEndnote, isTrue);
      }
      expect(paragraph.text, 'Before 12 after');
    });
  });

  test(
    'saving TOC page tabs does not mutate the live paragraph properties',
    () {
      final entry = WmlParagraph(
        properties: WmlParagraphProps(styleId: 'TOC1'),
        inlines: <WmlInline>[WmlRun(text: 'Chapter')],
      );
      final originalTabs = entry.properties.tabs;
      final toc = WmlToc(
        entries: <WmlTocEntry>[
          WmlTocEntry(
            text: 'Chapter',
            level: 1,
            headingParagraphIndex: 0,
            pageNumber: 3,
          ),
        ],
        itemParagraphs: <WmlParagraph>[entry],
      );
      final document = _document(toc);
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = WordSerializer().write(document);
        expect(identical(entry.properties.tabs, originalTabs), isTrue);
        expect(entry.properties.tabs, isEmpty);
        expect(entry.text, 'Chapter');
        expect(
          saved.getPart('/word/document.xml')!.readText(),
          contains('w:leader="dot"'),
        );
      }
    },
  );

  test('reusing a deserializer cannot leak an unfinished comment range', () {
    final reader = WordDeserializer();
    final first = reader.read(
      _source(
        '<w:p><w:commentRangeStart w:id="41"/>'
        '<w:r><w:t>Marked</w:t></w:r></w:p>',
      ),
    );
    expect(
      first.paragraphs.single.inlines.whereType<WmlRun>().single.commentIds,
      <int>[41],
    );
    final second = reader.read(
      _source('<w:p><w:r><w:t>Unrelated document</w:t></w:r></w:p>'),
    );
    expect(
      second.paragraphs.single.inlines.whereType<WmlRun>().single.commentIds,
      isEmpty,
    );
  });

  test('comment copies own their paragraph formatting for undo snapshots', () {
    final original = WmlComment(
      id: 5,
      paragraphs: <WmlParagraph>[
        WmlParagraph(
          properties: WmlParagraphProps(
            spacingAfter: 14,
            tabs: <WmlTabStop>[const WmlTabStop(position: 40)],
          ),
          inlines: <WmlInline>[WmlRun(text: 'Review this')],
        ),
      ],
    );
    final snapshot = original.copy();
    original.paragraphs.single.properties
      ..spacingAfter = 28
      ..tabs.add(const WmlTabStop(position: 80));
    expect(snapshot.paragraphs.single.properties.spacingAfter, 14);
    expect(snapshot.paragraphs.single.properties.tabs, hasLength(1));
  });
}
