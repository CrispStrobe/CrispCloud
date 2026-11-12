import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

List<XmlElement> _all(XmlElement node, String name) => <XmlElement>[
  for (final child in node.childElements) ...<XmlElement>[
    if (child.localName == name) child,
    ..._all(child, name),
  ],
];

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

XmlElement _main(OpcPackage package) =>
    XmlDocument.parse(package.getPart('/word/document.xml')!.readText()).root!;

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: <WmlInline>[WmlRun(text: text)]);

WmlDocument _document(WmlBlock block) => WmlDocument(
  sections: <WmlSection>[
    WmlSection(blocks: <WmlBlock>[block]),
  ],
);

void main() {
  test(
    'TOC page-number suppression and numbered titles survive three saves',
    () {
      final toc = WmlToc(
        showPageNumbers: false,
        entries: <WmlTocEntry>[
          WmlTocEntry(
            text: 'Chapter 2',
            level: 1,
            headingParagraphIndex: 0,
            pageNumber: 7,
          ),
        ],
      );
      WmlDocument document = _document(toc);
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = WordSerializer().write(document);
        final xml = _main(saved);
        expect(_all(xml, 'instrText').single.text, contains(r'\n'));
        final entries = _all(xml, 'p').where(
          (p) =>
              p.firstChild('pPr')?.firstChild('pStyle')?.getAttribute('val') ==
              'TOC1',
        );
        expect(entries, hasLength(1));
        expect(_all(entries.single, 'tab'), isEmpty);
        document = WordDeserializer().readBytes(saved.save());
        final copy = WordToc.tocs(document).single;
        expect(copy.showPageNumbers, isFalse);
        expect(copy.entries.single.text, 'Chapter 2');
        expect(copy.itemParagraphs.single.text, 'Chapter 2');
        final layout = WordLayoutEngine(font: null).layout(document);
        expect(
          layout.pages.expand((p) => p.lines).where((line) => line.tocLeader),
          isEmpty,
        );
      }
    },
  );

  test('native partial TOC suppression preserves the level range and layout', () {
    var document = WordDeserializer().read(
      _source(
        '<w:p><w:pPr><w:pStyle w:val="TOCHeading"/></w:pPr><w:r><w:t>Contents</w:t></w:r></w:p>'
        '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText> TOC \\o "1-4" \\n "2-3" \\h </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="TOC1"/></w:pPr><w:r><w:t>Alpha</w:t><w:tab/><w:t>1</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="TOC2"/></w:pPr><w:r><w:t>Chapter 2</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="TOC3"/></w:pPr><w:r><w:t>Subheading 3</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="TOC4"/></w:pPr><w:r><w:t>Deep</w:t><w:tab/><w:t>9</w:t></w:r></w:p>'
        '<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final toc = WordToc.tocs(document).single;
      expect(toc.omitPageNumbersFromLevel, 2);
      expect(toc.omitPageNumbersThroughLevel, 3);
      expect(toc.entries.map((e) => e.text), <String>[
        'Alpha',
        'Chapter 2',
        'Subheading 3',
        'Deep',
      ]);
      expect(
        [
          for (var level = 1; level <= 4; level++)
            toc.showsPageNumberForLevel(level),
        ],
        <bool>[true, false, false, true],
      );
      final clone = WmlClone.toc(toc);
      expect(clone.omitPageNumbersFromLevel, 2);
      expect(clone.omitPageNumbersThroughLevel, 3);
      final layout = WordLayoutEngine(font: null).layout(document);
      expect(
        layout.pages.expand((p) => p.lines).where((line) => line.tocLeader),
        hasLength(2),
      );
      final saved = WordSerializer().write(document);
      expect(
        _all(_main(saved), 'instrText').single.text,
        contains(r'\n "2-3"'),
      );
      document = WordDeserializer().readBytes(saved.save());
    }
  });

  test('TOC export preserves custom right tabs and the live source tabs', () {
    final entry = WmlParagraph(
      properties: WmlParagraphProps(
        styleId: 'TOC1',
        tabs: <WmlTabStop>[
          const WmlTabStop(position: 30),
          const WmlTabStop(
            position: 390,
            alignment: WmlTabAlignment.right,
            leader: WmlTabLeader.hyphen,
          ),
        ],
      ),
      inlines: <WmlInline>[WmlRun(text: 'Chapter')],
    );
    final toc = WmlToc(
      entries: <WmlTocEntry>[
        WmlTocEntry(
          text: 'Chapter',
          level: 1,
          headingParagraphIndex: 0,
          pageNumber: 5,
        ),
      ],
      itemParagraphs: <WmlParagraph>[entry],
    );
    final saved = WordSerializer().write(_document(toc));
    final tabGroups = _all(_main(saved), 'tabs');
    expect(tabGroups, hasLength(1));
    final stops = tabGroups.single.childrenNamed('tab');
    expect(stops.map((t) => t.getAttribute('pos')), <String>['600', '7800']);
    expect(stops.last.getAttribute('leader'), 'hyphen');
    expect(entry.properties.tabs.map((t) => t.position), <double>[30, 390]);
    expect(entry.text, 'Chapter');
  });

  test(
    'leading column flag and mid-paragraph column break remain separate',
    () {
      WmlDocument document = _document(
        WmlParagraph(
          properties: WmlParagraphProps(columnBreakBefore: true),
          inlines: <WmlInline>[
            WmlRun(text: 'Before'),
            WmlBreak(WmlBreakType.column),
            WmlRun(text: 'After'),
          ],
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        final saved = WordSerializer().write(document);
        final paragraph = _main(saved).firstChild('body')!.firstChild('p')!;
        final breaks = _all(paragraph, 'br');
        expect(breaks, hasLength(2));
        expect(breaks.every((b) => b.getAttribute('type') == 'column'), isTrue);
        expect(paragraph.childrenNamed('r').first.firstChild('br'), isNotNull);
        document = WordDeserializer().readBytes(saved.save());
        expect(document.paragraphs.single.text, 'BeforeAfter');
      }
    },
  );

  test(
    'table merge moves every rich cell block in order with stable identity',
    () {
      final first = _paragraph('First');
      final anchor = WmlParagraph(
        properties: WmlParagraphProps(bookmarkName: 'EmptyAnchor'),
      );
      final picture = WmlVisual(
        visual: OfficeVisual(
          kind: OfficeVisualKind.picture,
          imageBytes: PngBytes.studioCard(),
          width: 40,
          height: 30,
        ),
      );
      final nested = WmlTable(
        grid: <double>[50],
        rows: <WmlTableRow>[
          WmlTableRow(
            cells: <WmlTableCell>[
              WmlTableCell(blocks: <WmlBlock>[_paragraph('Nested')]),
            ],
          ),
        ],
      );
      final frame = WmlFrame(blocks: <WmlBlock>[_paragraph('Frame')]);
      final equation = WmlEquation(math: OmmlEquation.empty());
      final opaque = WmlOpaqueBlock(
        xml: '<w:customXml xmlns:w="${OfficeNamespaces.w}"/>',
        sourcePartUri: '/word/document.xml',
        relationships: <WmlOpaqueRelationship>[],
      );
      final ordered = <WmlBlock>[
        first,
        anchor,
        picture,
        nested,
        frame,
        equation,
        opaque,
      ];
      final table = WmlTable(
        grid: <double>[120, 120],
        rows: <WmlTableRow>[
          WmlTableRow(
            cells: <WmlTableCell>[
              WmlTableCell(blocks: <WmlBlock>[first]),
              WmlTableCell(blocks: <WmlBlock>[anchor, picture]),
            ],
          ),
          WmlTableRow(
            cells: <WmlTableCell>[
              WmlTableCell(blocks: <WmlBlock>[nested, frame]),
              WmlTableCell(blocks: <WmlBlock>[equation, opaque]),
            ],
          ),
        ],
      );
      WordTable.merge(table, 0, 0, 1, 1);
      expect(table.rows.first.cells.single.blocks, ordered);
      for (var i = 0; i < ordered.length; i++) {
        expect(
          identical(table.rows.first.cells.single.blocks[i], ordered[i]),
          isTrue,
        );
      }
      expect(table.rows.first.cells.single.vMerge, WmlVMerge.restart);
      expect(table.rows.last.cells.single.vMerge, WmlVMerge.cont);
      WordTable.unmerge(table, 0, 0);
      expect(table.rows.first.cells.first.blocks, ordered);
    },
  );

  test('table snapshots restore all properties and never alias live edits', () {
    final table = WmlTable(
      grid: <double>[80],
      properties: WmlTableProps(
        borders: false,
        borderColor: '123456',
        borderWidth: 2,
        styleId: 'Custom',
        cellMargin: 8,
        rightToLeft: true,
      ),
      rows: <WmlTableRow>[
        WmlTableRow(
          cells: <WmlTableCell>[
            WmlTableCell(
              borderTop: false,
              borderBottom: true,
              borderLeft: false,
              borderRight: true,
              blocks: <WmlBlock>[_paragraph('Original')],
            ),
          ],
        ),
      ],
    );
    table.properties
      ..sourcePropertiesXml = '<source/>'
      ..importedValues = <String, String>{'borders': 'false'};
    final snapshot = WordTable.snapshot(table);
    for (var cycle = 0; cycle < 3; cycle++) {
      table.properties
        ..borders = true
        ..borderColor = 'FFFFFF'
        ..borderWidth = 8
        ..styleId = 'Changed';
      WordTable.restore(table, snapshot);
      expect(table.properties.borders, isFalse);
      expect(table.properties.borderColor, '123456');
      expect(table.properties.borderWidth, 2);
      expect(table.properties.styleId, 'Custom');
      expect(table.properties.sourcePropertiesXml, '<source/>');
      final cell = table.rows.single.cells.single;
      expect(
        [cell.borderTop, cell.borderBottom, cell.borderLeft, cell.borderRight],
        <bool>[false, true, false, true],
      );
      (cell.blocks.single as WmlParagraph).inlines
              .whereType<WmlRun>()
              .single
              .text =
          'Later edit';
      table.properties.importedValues!['borders'] = 'true';
      expect(
        (snapshot.rows.single.cells.single.blocks.single as WmlParagraph).text,
        'Original',
      );
      expect(snapshot.properties.importedValues!['borders'], 'false');
    }
  });

  test('native picture title is separate from name and description', () {
    final source = OpcPackage.openBytes(
      File('test/fixtures/fidelity/word.docx').readAsBytesSync(),
    );
    final xml = _main(source);
    final docPr = _all(xml, 'docPr').single;
    final picturePr = _all(xml, 'cNvPr').single;
    docPr
      ..setAttribute('name', 'Picture display name')
      ..setAttribute('title', 'Accessible title')
      ..setAttribute('descr', 'Accessible description');
    picturePr
      ..setAttribute('name', 'image-file.png')
      ..setAttribute('title', 'Secondary title')
      ..setAttribute('descr', 'Secondary description');
    source
        .getPart('/word/document.xml')!
        .writeText(XmlDocument(root: xml).toXmlString());
    var document = WordDeserializer().read(source);
    for (var cycle = 0; cycle < 3; cycle++) {
      final visual = document.visuals.single.visual;
      expect(visual.title, 'Picture display name');
      expect(visual.picture.altTitle, 'Accessible title');
      expect(visual.picture.altDescription, 'Accessible description');
      final saved = WordSerializer().write(document);
      final out = _main(saved);
      for (final properties in <XmlElement>[
        _all(out, 'docPr').single,
        _all(out, 'cNvPr').single,
      ]) {
        expect(properties.getAttribute('name'), 'Picture display name');
        expect(properties.getAttribute('title'), 'Accessible title');
        expect(properties.getAttribute('descr'), 'Accessible description');
      }
      document = WordDeserializer().readBytes(saved.save());
    }
  });

  test(
    'legacy picture names remain the title fallback when native title is absent',
    () {
      final source = OpcPackage.openBytes(
        File('test/fixtures/fidelity/word.docx').readAsBytesSync(),
      );
      final xml = _main(source);
      for (final node in <XmlElement>[
        ..._all(xml, 'docPr'),
        ..._all(xml, 'cNvPr'),
      ]) {
        node.removeAttribute('title');
        node.setAttribute('name', 'Legacy title');
      }
      source
          .getPart('/word/document.xml')!
          .writeText(XmlDocument(root: xml).toXmlString());
      final document = WordDeserializer().read(source);
      expect(document.visuals.single.visual.title, 'Legacy title');
      expect(document.visuals.single.visual.picture.altTitle, 'Legacy title');
    },
  );
}
