import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;

WmlDocument _source(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" '
        'w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

WmlDocument _formattedSource() => _source(
  '<w:p><w:pPr><w:contextualSpacing/><w:spacing w:after="123"/></w:pPr>'
  '<w:r><w:rPr><w:i/><w:lang w:val="en-GB"/><w:color w:val="112233"/>'
  '</w:rPr><w:t>Alpha beta</w:t></w:r></w:p>',
);

String _xml(WmlDocument doc) =>
    WordSerializer().write(doc).getPart('/word/document.xml')!.readText();

List<XmlElement> _elements(XmlElement root, String name) => [
  for (final child in root.childElements) ...[
    if (child.localName == name) child,
    ..._elements(child, name),
  ],
];

void main() {
  for (final invalid in <Map<String, Object?>>[
    {'color': 'invalid'},
    {'highlight': 'red'},
    {'size': double.nan},
    {'underline': 'unknown'},
    {'font': 123},
    {'italic': 'true'},
  ]) {
    test(
      'runFormat rejects $invalid before splitting or touching source properties',
      () {
        final doc = _formattedSource();
        final p = doc.paragraphs.single;
        final run = p.inlines.whereType<WmlRun>().single;
        final properties = run.properties;
        final imported = Map<String, String>.from(properties.importedValues!);
        final explicit = Set<String>.from(properties.explicitProperties);
        final before = _xml(doc);
        expect(
          () => cli.applyStep(doc, {
            'op': 'runFormat',
            'paragraph': 0,
            'start': 1,
            'end': 4,
            'bold': true,
            ...invalid,
          }),
          throwsArgumentError,
        );
        expect(p.inlines, [same(run)]);
        expect(run.properties, same(properties));
        expect(properties.importedValues, imported);
        expect(properties.explicitProperties, explicit);
        expect(_xml(doc), before);
      },
    );
  }

  test(
    'successful run patch preserves unrelated imported formatting',
    () async {
      var doc = _formattedSource();
      cli.applyStep(doc, {
        'op': 'runFormat',
        'paragraph': 0,
        'start': 0,
        'end': 5,
        'bold': true,
        'color': '00AA22',
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(doc);
        final root = XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!;
        final runs = _elements(root, 'r');
        expect(runs, hasLength(2));
        expect(
          runs.first.firstChild('rPr')!.firstChild('b')?.getAttribute('val'),
          '1',
        );
        expect(
          runs.first
              .firstChild('rPr')!
              .firstChild('color')
              ?.getAttribute('val'),
          '00AA22',
        );
        expect(
          runs.last.firstChild('rPr')!.firstChild('color')?.getAttribute('val'),
          '112233',
        );
        expect(
          _elements(root, 'lang').map((node) => node.getAttribute('val')),
          ['en-GB', 'en-GB'],
        );
        expect(_elements(root, 'i'), hasLength(2));
        expect(_elements(root, 'contextualSpacing'), hasLength(1));
        doc = WordDeserializer().readBytes(bytes);
        expect(doc.paragraphs.single.text, 'Alpha beta');
      }
    },
  );

  test('imageSize validates both dimensions before changing either', () {
    final doc = _formattedSource();
    final visual = OfficeVisual(
      kind: OfficeVisualKind.picture,
      width: 48,
      height: 24,
      imageBytes: File(
        'test/fixtures/fidelity/scripts/replacement.png',
      ).readAsBytesSync(),
    );
    doc.sections.single.blocks.add(WmlVisual(visual: visual));
    final before = _xml(doc);
    expect(
      () => cli.applyStep(doc, {
        'op': 'imageSize',
        'image': 0,
        'width': 222,
        'height': 0,
      }),
      throwsArgumentError,
    );
    expect((visual.width, visual.height), (48.0, 24.0));
    expect(_xml(doc), before);
  });

  test(
    'tableCellText rejects invalid text without removing the cell story',
    () {
      final doc = _formattedSource();
      cli.applyStep(doc, {
        'op': 'tableAdd',
        'rows': 1,
        'columns': 1,
        'width': 240,
      });
      final cell = doc.sections.single.blocks
          .whereType<WmlTable>()
          .single
          .rows
          .single
          .cells
          .single;
      final paragraph = cell.blocks.single;
      final frame = WmlFrame(
        blocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Keep drawing')]),
        ],
      );
      cell.blocks.add(frame);
      final before = _xml(doc);
      expect(
        () => cli.applyStep(doc, {
          'op': 'tableCellText',
          'table': 0,
          'row': 0,
          'column': 0,
          'text': 123,
        }),
        throwsArgumentError,
      );
      expect(cell.blocks, [same(paragraph), same(frame)]);
      expect(_xml(doc), before);
    },
  );

  test(
    'headerFooterText rejects invalid text before appending a paragraph',
    () {
      final doc = _formattedSource();
      final header = doc.sections.single.header;
      expect(header, isEmpty);
      expect(
        () => cli.applyStep(doc, {
          'op': 'headerFooterText',
          'story': 'header',
          'paragraph': 0,
          'text': 123,
        }),
        throwsArgumentError,
      );
      expect(header, isEmpty);
    },
  );

  for (final invalid in <Map<String, Object?>>[
    {'columnSep': 'true'},
    {'breakKind': 'unknown'},
    {'differentFirstPage': 'true'},
    {'differentOddEven': 'false'},
  ]) {
    test('sectionFormat rejects $invalid before replacing geometry', () {
      final doc = _formattedSource();
      final section = doc.sections.single;
      final page = section.pageSize, margins = section.margins;
      final before = _xml(doc);
      expect(
        () => cli.applyStep(doc, {
          'op': 'sectionFormat',
          'width': 700,
          'top': 30,
          'columns': 2,
          'columnSpace': 12,
          ...invalid,
        }),
        throwsArgumentError,
      );
      expect(section.pageSize, same(page));
      expect(section.margins, same(margins));
      expect(section.columnCount, 1);
      expect(_xml(doc), before);
    });
  }

  for (final step in <Map<String, Object?>>[
    {'op': 'replaceText', 'paragraph': 0, 'start': 2, 'end': 2, 'text': 'X'},
    {'op': 'runFormat', 'paragraph': 0, 'start': 2, 'end': 3, 'bold': true},
    {'op': 'paragraphSplit', 'paragraph': 0, 'offset': 2},
    {'op': 'addNote', 'paragraph': 0, 'offset': 2, 'text': 'Note'},
    {
      'op': 'commentAdd',
      'paragraph': 0,
      'start': 2,
      'end': 3,
      'text': 'Comment',
    },
  ]) {
    test('${step['op']} rejects a boundary inside an atomic cached field', () {
      final field = WmlRun(text: '12', fieldInstruction: ' PAGE ');
      final p = WmlParagraph(
        inlines: [
          WmlRun(text: 'A'),
          field,
          WmlRun(text: 'Z'),
        ],
      );
      final doc = WmlDocument(
        sections: [
          WmlSection(blocks: [p]),
        ],
      );
      final inlines = List<WmlInline>.from(p.inlines);
      final before = _xml(doc);
      expect(() => cli.applyStep(doc, step), throwsArgumentError);
      expect(p.inlines, orderedEquals(inlines));
      expect(p.inlines[1], same(field));
      expect(doc.footnotes, isEmpty);
      expect(doc.comments, isEmpty);
      expect(_xml(doc), before);
    });
  }

  test(
    'an empty REF result clears the stale cache through update and three exports',
    () async {
      var doc = _source(
        '<w:p><w:bookmarkStart w:id="7" w:name="Empty"/><w:r><w:t></w:t></w:r>'
        '<w:bookmarkEnd w:id="7"/></w:p><w:p><w:r><w:t>PLACEHOLDER</w:t></w:r></w:p>',
      );
      cli.applyStep(doc, {
        'op': 'reference',
        'paragraph': 1,
        'bookmark': 'Empty',
      });
      expect(doc.paragraphs.elementAt(1).text, isEmpty);
      for (var cycle = 0; cycle < 3; cycle++) {
        WordFields.update(doc);
        final bytes = await OfficeIsolateSave.word(doc);
        final root = XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!;
        expect(_elements(root, 'instrText').single.text.trim(), 'REF Empty');
        expect(
          _elements(
            root,
            'fldChar',
          ).map((node) => node.getAttribute('fldCharType')),
          ['begin', 'separate', 'end'],
        );
        doc = WordDeserializer().readBytes(bytes);
        expect(doc.paragraphs.elementAt(1).text, isEmpty);
      }
    },
  );

  test(
    'updating a formerly populated REF clears its cache when the target empties',
    () {
      final doc = _source(
        '<w:p><w:bookmarkStart w:id="7" w:name="Target"/><w:r><w:t>Populated</w:t></w:r>'
        '<w:bookmarkEnd w:id="7"/></w:p><w:p><w:r><w:t>Placeholder</w:t></w:r></w:p>',
      );
      cli.applyStep(doc, {
        'op': 'reference',
        'paragraph': 1,
        'bookmark': 'Target',
      });
      expect(doc.paragraphs.elementAt(1).text, 'Populated');
      cli.applyStep(doc, {'op': 'replaceText', 'paragraph': 0, 'text': ''});
      WordFields.update(doc);
      expect(doc.paragraphs.elementAt(1).text, isEmpty);
    },
  );

  test('stamp distinguishes omitted and explicitly empty cached results', () {
    final p = WmlParagraph(inlines: [WmlRun(text: 'Cached date')]);
    WordFields.stamp(p, WmlFieldKind.date);
    expect(p.text, 'Cached date');
    WordFields.stamp(p, WmlFieldKind.date, result: '');
    expect(p.text, isEmpty);
  });

  test(
    'native headings receive unique stable TOC targets without stealing imported names',
    () async {
      var doc = _source(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Repeated</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Repeated</w:t></w:r></w:p>'
        '<w:p><w:bookmarkStart w:id="7" w:name="_Heading1_Repeated"/>'
        '<w:r><w:t>Reserved target</w:t></w:r><w:bookmarkEnd w:id="7"/></w:p>',
      );
      cli.applyStep(doc, {'op': 'tocAdd'});
      final targets = doc.paragraphs
          .take(3)
          .map((p) => p.properties.bookmarkName)
          .toList();
      expect(targets, [
        '_Heading1_Repeated_2',
        '_Heading1_Repeated_3',
        '_Heading1_Repeated',
      ]);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(doc);
        final root = XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!;
        expect(
          _elements(
            root,
            'bookmarkStart',
          ).map((node) => node.getAttribute('name')),
          targets,
        );
        expect(
          _elements(
            root,
            'hyperlink',
          ).map((node) => node.getAttribute('anchor')),
          targets.take(2),
        );
        doc = WordDeserializer().readBytes(bytes);
        cli.applyStep(doc, {'op': 'tocUpdate', 'toc': 0});
        expect(
          WordToc.tocs(doc).single.entries.map((e) => e.headingParagraphIndex),
          [0, 1],
        );
      }
    },
  );

  test(
    'scripted duplicate headings are disambiguated and heading changes keep references',
    () {
      final doc = _source(
        '<w:p><w:r><w:t>Same</w:t></w:r></w:p><w:p><w:r><w:t>Same</w:t></w:r></w:p>',
      );
      cli.applyStep(doc, {'op': 'heading', 'paragraph': 0, 'level': 1});
      cli.applyStep(doc, {'op': 'heading', 'paragraph': 1, 'level': 1});
      final targets = doc.paragraphs
          .map((p) => p.properties.bookmarkName)
          .toList();
      expect(targets, ['_Heading1_Same', '_Heading1_Same_2']);
      cli.applyStep(doc, {'op': 'heading', 'paragraph': 0, 'level': 2});
      expect(doc.paragraphs.first.properties.bookmarkName, targets.first);
      cli.applyStep(doc, {
        'op': 'reference',
        'paragraph': 1,
        'bookmark': targets.first,
      });
      expect(
        doc.paragraphs.elementAt(1).properties.fieldInstruction,
        contains(targets.first!),
      );
    },
  );

  test('generated bookmark names remain valid and unique after truncation', () {
    final paragraphs = [
      for (var index = 0; index < 3; index++)
        WmlParagraph(
          inlines: [WmlRun(text: '${'Long title-' * 10}$index')],
          properties: WmlParagraphProps(styleId: 'Heading1'),
        ),
      WmlParagraph(
        inlines: [WmlRun(text: 'عنوان')],
        properties: WmlParagraphProps(styleId: 'Heading1'),
      ),
    ];
    final doc = WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
    WordLink.ensureHeadingBookmarks(doc);
    final names = paragraphs.map((p) => p.properties.bookmarkName!).toList();
    expect(names.toSet(), hasLength(4));
    for (final name in names) {
      expect(RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,39}$').hasMatch(name), isTrue);
    }
    WordLink.ensureHeadingBookmarks(doc);
    expect(paragraphs.map((p) => p.properties.bookmarkName), names);
  });

  test(
    'explicit TOC page visibility clears imported partial omission only when supplied',
    () {
      final p = WmlParagraph(
        inlines: [WmlRun(text: 'Heading')],
        properties: WmlParagraphProps(headingLevel: 2),
      );
      final toc = WmlToc(
        minLevel: 1,
        maxLevel: 3,
        omitPageNumbersFromLevel: 2,
        omitPageNumbersThroughLevel: 3,
      );
      final doc = WmlDocument(
        sections: [
          WmlSection(blocks: [p, toc]),
        ],
      );
      cli.applyStep(doc, {
        'op': 'tocUpdate',
        'toc': 0,
        'title': 'New contents',
      });
      expect(
        (toc.omitPageNumbersFromLevel, toc.omitPageNumbersThroughLevel),
        (2, 3),
      );
      cli.applyStep(doc, {
        'op': 'tocUpdate',
        'toc': 0,
        'showPageNumbers': true,
      });
      expect(toc.showPageNumbers, isTrue);
      expect(
        (toc.omitPageNumbersFromLevel, toc.omitPageNumbersThroughLevel),
        (null, null),
      );
      final xml = _xml(doc);
      expect(xml, isNot(contains(r'\n')));
      final copy = WordDeserializer().readBytes(
        WordSerializer().write(doc).save(),
      );
      expect(WordToc.tocs(copy).single.showsPageNumberForLevel(2), isTrue);
    },
  );
}
