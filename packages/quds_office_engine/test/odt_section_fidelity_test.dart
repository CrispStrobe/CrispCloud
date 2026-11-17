import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlParagraph _p(String text, {WmlParagraphProps? properties}) => WmlParagraph(
  properties: properties,
  inlines: [WmlRun(text: text)],
);

WmlContentControlBlock _control(List<WmlBlock> blocks) =>
    WmlContentControlBlock(
      control: WmlContentControlData(
        xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtContent/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: const [],
      ),
      blocks: blocks,
    );

WmlTable _table(String text) => WmlTable(
  grid: [120],
  rows: [
    WmlTableRow(
      cells: [
        WmlTableCell(blocks: [_p(text)]),
      ],
    ),
  ],
);

WmlDocument _two(
  List<WmlBlock> second, {
  WmlSectionBreakKind kind = WmlSectionBreakKind.nextPage,
}) => WmlDocument(
  sections: [
    WmlSection(blocks: [_p('First')]),
    WmlSection(blocks: second, breakKind: kind),
  ],
);

({XmlElement content, XmlElement styles}) _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  XmlElement part(String name) =>
      XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;
  return (content: part('content'), styles: part('styles'));
}

XmlElement _body(XmlElement content) =>
    content.firstChild('body')!.firstChild('text')!;

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

XmlElement _style(XmlElement content, XmlElement owner) {
  final name = owner.getAttribute(
    'style-name',
    namespaceUri: owner.namespaceUri == _tableNs
        ? _tableNs
        : owner.namespaceUri == _drawNs
        ? _drawNs
        : _textNs,
  );
  return content
      .firstChild('automatic-styles')!
      .childrenNamed('style')
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

String? _master(XmlElement content, XmlElement owner) => _style(
  content,
  owner,
).getAttribute('master-page-name', namespaceUri: _styleNs);

XmlElement _paragraph(XmlElement content, String text) => [
  ..._elements(_body(content), 'p'),
  ..._elements(_body(content), 'h'),
].singleWhere((element) => _text(element) == text);

String _text(XmlNode node) => switch (node) {
  XmlText() => node.text,
  XmlElement() => node.children.map(_text).join(),
  _ => '',
};

void main() {
  WmlToc generatedToc({String title = 'Contents'}) => WmlToc(
    title: title,
    entries: [
      WmlTocEntry(
        text: 'Introduction',
        level: 1,
        headingParagraphIndex: 0,
        pageNumber: 2,
      ),
      WmlTocEntry(
        text: 'Details',
        level: 2,
        headingParagraphIndex: 1,
        pageNumber: 4,
      ),
    ],
  );

  for (final titled in [true, false]) {
    for (final cached in [true, false]) {
      test(
        'leading TOC inherits section once: titled=$titled cached=$cached',
        () {
          final toc = generatedToc(title: titled ? 'Contents' : '');
          if (cached) {
            toc.itemParagraphs = [
              _p('Cached introduction'),
              _p('Cached details'),
            ];
          }
          final beforeTitle = toc.titleParagraph.properties;
          final document = _two([toc, _p('After contents')]);
          document.sections.last.pageSize = const WmlPageSize(
            width: 600,
            height: 400,
          );
          final result = _export(document);
          final paragraphs = _body(result.content).childElements.toList();
          expect(paragraphs, hasLength(titled ? 5 : 4));
          expect(_master(result.content, paragraphs[1]), 'mp1');
          for (final paragraph in paragraphs.skip(2)) {
            expect(_master(result.content, paragraph), isNull);
          }
          expect(
            _text(paragraphs[1]),
            titled
                ? 'Contents'
                : cached
                ? 'Cached introduction'
                : 'Introduction2',
          );
          expect(
            _master(
              result.content,
              _paragraph(result.content, 'After contents'),
            ),
            isNull,
          );
          expect(identical(toc.titleParagraph.properties, beforeTitle), isTrue);
          expect(beforeTitle.pageBreakBefore, isFalse);
          expect(toc.entries.map((entry) => entry.pageNumber), [2, 4]);
        },
      );
    }
  }

  test('TOC-only section has no trailing synthetic page anchor', () {
    final content = _export(_two([generatedToc()])).content;
    expect(_body(content).childElements, hasLength(4));
    expect(_master(content, _paragraph(content, 'Contents')), 'mp1');
    expect(
      _body(content).childElements.where((element) => _text(element).isEmpty),
      isEmpty,
    );
  });

  test('title-only TOC carries its section activation', () {
    final content = _export(_two([WmlToc(title: 'Empty contents')])).content;
    expect(_body(content).childElements, hasLength(2));
    expect(_master(content, _paragraph(content, 'Empty contents')), 'mp1');
  });

  test('empty titleless TOC leaves the next visible section anchor intact', () {
    final content = _export(
      _two([WmlToc(title: ''), _p('After empty contents')]),
    ).content;
    expect(_body(content).childElements, hasLength(2));
    expect(
      _master(content, _paragraph(content, 'After empty contents')),
      'mp1',
    );
  });

  test('TOC inside a content control receives the pending section', () {
    final content = _export(
      _two([
        _control([generatedToc()]),
        _p('Tail'),
      ]),
    ).content;
    expect(_master(content, _paragraph(content, 'Contents')), 'mp1');
    expect(_master(content, _paragraph(content, 'Tail')), isNull);
    expect(_body(content).childElements, hasLength(5));
  });

  for (final kind in [
    WmlSectionBreakKind.oddPage,
    WmlSectionBreakKind.evenPage,
  ]) {
    test('leading TOC selects the correct parity master for $kind', () {
      final content = _export(_two([generatedToc()], kind: kind)).content;
      expect(_master(content, _paragraph(content, 'Contents')), 'mp1Start');
      expect(_body(content).childElements, hasLength(4));
    });
  }

  test(
    'continuous TOC does not append a blank paragraph or force a master',
    () {
      final content = _export(
        _two([generatedToc()], kind: WmlSectionBreakKind.continuous),
      ).content;
      expect(_body(content).childElements, hasLength(4));
      expect(_master(content, _paragraph(content, 'Contents')), isNull);
    },
  );

  test('a first list item selects the section while its siblings do not', () {
    final content = _export(
      _two([
        _p(
          'List first',
          properties: WmlParagraphProps(numId: 1, listLabel: '1.'),
        ),
        _p(
          'List second',
          properties: WmlParagraphProps(numId: 1, listLabel: '2.'),
        ),
      ]),
    ).content;
    expect(_master(content, _paragraph(content, 'List first')), 'mp1');
    expect(_master(content, _paragraph(content, 'List second')), isNull);
    expect(_elements(_body(content), 'list-item'), hasLength(2));
  });

  test(
    'table-only sections activate the table without inserting a paragraph',
    () {
      final content = _export(_two([_table('Cell')])).content;
      final children = _body(content).childElements.toList();
      expect(children.map((child) => child.localName), ['p', 'table']);
      expect(_master(content, children.last), 'mp1');
      expect(_master(content, _paragraph(content, 'Cell')), isNull);
      final props = _style(
        content,
        children.last,
      ).firstChild('table-properties')!;
      expect(props.getAttribute('break-before', namespaceUri: _foNs), 'page');
    },
  );

  test(
    'nested controls and empty wrappers preserve a leading list activation',
    () {
      final content = _export(
        _two([
          _control([]),
          _control([
            _control([]),
            _control([
              _p('Nested list', properties: WmlParagraphProps(numId: 7)),
            ]),
          ]),
          _p('Tail'),
        ]),
      ).content;
      expect(_master(content, _paragraph(content, 'Nested list')), 'mp1');
      expect(_master(content, _paragraph(content, 'Tail')), isNull);
    },
  );

  test('nested controls pass section activation to a leading table', () {
    final content = _export(
      _two([
        _control([
          _control([_table('Nested cell')]),
        ]),
      ]),
    ).content;
    expect(_master(content, _elements(_body(content), 'table').single), 'mp1');
    expect(_master(content, _paragraph(content, 'Nested cell')), isNull);
  });

  test('ignored blocks do not consume the next visible section anchor', () {
    final content = _export(
      _two([
        WmlOpaqueBlock(
          xml: '<unknown/>',
          sourcePartUri: '/word/document.xml',
          relationships: const [],
        ),
        _control([]),
        _p('Visible'),
      ]),
    ).content;
    expect(_master(content, _paragraph(content, 'Visible')), 'mp1');
    expect(_body(content).childElements, hasLength(2));
  });

  test('a first picture is anchored inside the section paragraph', () {
    final content = _export(
      _two([
        WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.picture,
            title: 'Pixel',
            width: 20,
            height: 10,
            imageBytes: base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
            ),
          ),
        ),
        _p('After picture'),
      ]),
    ).content;
    final pictureParagraph = _body(content).childElements.elementAt(1);
    expect(pictureParagraph.localName, 'p');
    expect(_master(content, pictureParagraph), 'mp1');
    expect(_elements(pictureParagraph, 'image'), hasLength(1));
    expect(
      _elements(
        pictureParagraph,
        'frame',
      ).single.getAttribute('anchor-type', namespaceUri: _textNs),
      'as-char',
    );
    expect(_master(content, _paragraph(content, 'After picture')), isNull);
  });

  test('a visual fallback stays in one paragraph carrying its section', () {
    final content = _export(
      _two([
        WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.picture,
            title: 'Missing image',
            width: 20,
            height: 10,
          ),
        ),
      ]),
    ).content;
    final paragraph = _paragraph(content, 'Missing image');
    expect(_master(content, paragraph), 'mp1');
    expect(_elements(paragraph, 'p'), hasLength(1));
  });

  test(
    'a first frame anchors on the current page with physical page coordinates',
    () {
      final content = _export(
        _two([
          WmlFrame(
            x: 60,
            y: 100,
            width: 180,
            height: 40,
            blocks: [_p('Frame')],
          ),
          _p('After frame'),
        ]),
      ).content;
      final anchor = _body(content).childElements.elementAt(1);
      expect(anchor.localName, 'p');
      expect(_master(content, anchor), 'mp1');
      final frame = _elements(anchor, 'frame').single;
      expect(
        frame.getAttribute('anchor-type', namespaceUri: _textNs),
        'paragraph',
      );
      final graphic = _style(content, frame).firstChild('graphic-properties')!;
      expect(
        graphic.getAttribute('horizontal-rel', namespaceUri: _styleNs),
        'page',
      );
      expect(
        graphic.getAttribute('vertical-rel', namespaceUri: _styleNs),
        'page',
      );
      expect(_master(content, _paragraph(content, 'After frame')), isNull);
    },
  );

  test(
    'empty sections keep their own boundary and do not steal the next one',
    () {
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [_p('Before')]),
          WmlSection(),
          WmlSection(blocks: [_p('After')]),
        ],
      );
      final content = _export(document).content;
      final children = _body(content).childElements.toList();
      expect(children, hasLength(3));
      expect(_text(children[1]), isEmpty);
      expect(_master(content, children[1]), 'mp1');
      expect(_master(content, children[2]), 'mp2');
      expect(document.sections[1].blocks, isEmpty);
    },
  );

  test(
    'an empty document has a usable default master without changing the model',
    () {
      final document = WmlDocument(sections: []);
      final result = _export(document);
      expect(
        _elements(
          result.styles,
          'master-page',
        ).single.getAttribute('name', namespaceUri: _styleNs),
        'Standard',
      );
      expect(_elements(result.styles, 'page-layout'), hasLength(1));
      // A synthetic section supplies default styles, but must not add an
      // authored body paragraph to an explicitly empty document.
      expect(_body(result.content).childElements, isEmpty);
      expect(document.sections, isEmpty);
    },
  );

  test(
    'section headings retain resolved spacing, direction and indents directly',
    () {
      final properties = WmlParagraphProps(
        headingLevel: 2,
        justification: WmlJustification.right,
        rightToLeft: true,
        lineSpacing: 18,
        lineSpacingRule: WmlLineSpacingRule.exact,
        spacingBefore: 6,
        spacingAfter: 0,
        indent: const WmlIndent(left: 12, right: 3, firstLine: 4),
      );
      final content = _export(
        _two([_p('Heading', properties: properties)]),
      ).content;
      final heading = _paragraph(content, 'Heading');
      expect(heading.localName, 'h');
      final style = _style(content, heading);
      expect(
        style.getAttribute('parent-style-name', namespaceUri: _styleNs),
        'Heading_20_2',
      );
      final p = style.firstChild('paragraph-properties')!;
      expect(p.getAttribute('line-height', namespaceUri: _foNs), '18.00pt');
      expect(p.getAttribute('margin-top', namespaceUri: _foNs), '6.00pt');
      expect(p.getAttribute('margin-bottom', namespaceUri: _foNs), '0.00pt');
      expect(p.getAttribute('margin-left', namespaceUri: _foNs), '3.00pt');
      expect(p.getAttribute('margin-right', namespaceUri: _foNs), '12.00pt');
      expect(p.getAttribute('text-indent', namespaceUri: _foNs), '4.00pt');
      expect(p.getAttribute('text-align', namespaceUri: _foNs), 'right');
      expect(p.getAttribute('writing-mode', namespaceUri: _styleNs), 'rl-tb');
      expect(properties.pageBreakBefore, isFalse);
    },
  );

  test(
    'continuous equal page styles do not select a new master or add a break',
    () {
      final content = _export(
        _two([_p('Continuous')], kind: WmlSectionBreakKind.continuous),
      ).content;
      final paragraph = _paragraph(content, 'Continuous');
      expect(_master(content, paragraph), isNull);
      expect(
        _style(content, paragraph)
            .firstChild('paragraph-properties')!
            .getAttribute('break-before', namespaceUri: _foNs),
        isNull,
      );
    },
  );

  test(
    'continuous equal normal header and footer content can reuse a master',
    () {
      WmlSection section(String body, WmlSectionBreakKind kind) => WmlSection(
        blocks: [_p(body)],
        breakKind: kind,
        header: [_p('Same header')],
        footer: [_p('Same footer')],
      );
      final content = _export(
        WmlDocument(
          sections: [
            section('First', WmlSectionBreakKind.nextPage),
            section('Continuous', WmlSectionBreakKind.continuous),
          ],
        ),
      ).content;
      expect(_master(content, _paragraph(content, 'Continuous')), isNull);
    },
  );

  test('continuous changed geometry still selects the authored page style', () {
    final document = _two([
      _p('Different geometry'),
    ], kind: WmlSectionBreakKind.continuous);
    document.sections.last.pageSize = const WmlPageSize(
      width: 600,
      height: 400,
    );
    final result = _export(document);
    expect(
      _master(result.content, _paragraph(result.content, 'Different geometry')),
      'mp1',
    );
    final page = _elements(
      result.styles,
      'page-layout',
    ).last.firstChild('page-layout-properties')!;
    expect(page.getAttribute('page-width', namespaceUri: _foNs), '600.00pt');
    expect(page.getAttribute('page-height', namespaceUri: _foNs), '400.00pt');
  });

  test('continuous changed header keeps a distinct section master', () {
    final document = _two([
      _p('Different header'),
    ], kind: WmlSectionBreakKind.continuous);
    document.sections.last.header = [_p('New header')];
    final result = _export(document);
    expect(
      _master(result.content, _paragraph(result.content, 'Different header')),
      'mp1',
    );
  });

  test('authored paragraph page breaks survive a continuous section', () {
    final content = _export(
      _two([
        _p(
          'Explicit break',
          properties: WmlParagraphProps(pageBreakBefore: true),
        ),
      ], kind: WmlSectionBreakKind.continuous),
    ).content;
    final paragraph = _paragraph(content, 'Explicit break');
    expect(_master(content, paragraph), isNull);
    expect(
      _style(content, paragraph)
          .firstChild('paragraph-properties')!
          .getAttribute('break-before', namespaceUri: _foNs),
      'page',
    );
  });

  for (final (kind, parity) in [
    (WmlSectionBreakKind.oddPage, 'right'),
    (WmlSectionBreakKind.evenPage, 'left'),
  ]) {
    test(
      '$kind selects a parity entry master that returns to normal pages',
      () {
        final result = _export(_two([_p('Parity')], kind: kind));
        expect(
          _master(result.content, _paragraph(result.content, 'Parity')),
          'mp1Start',
        );
        final masters = _elements(result.styles, 'master-page').toList();
        final start = masters.singleWhere(
          (master) =>
              master.getAttribute('name', namespaceUri: _styleNs) == 'mp1Start',
        );
        expect(
          start.getAttribute('next-style-name', namespaceUri: _styleNs),
          'mp1',
        );
        final normal = masters.singleWhere(
          (master) =>
              master.getAttribute('name', namespaceUri: _styleNs) == 'mp1',
        );
        final normalLayoutName = normal.getAttribute(
          'page-layout-name',
          namespaceUri: _styleNs,
        );
        final layouts = _elements(result.styles, 'page-layout').toList();
        final firstLayout = layouts.singleWhere(
          (layout) =>
              layout.getAttribute('name', namespaceUri: _styleNs) == 'pm1Start',
        );
        expect(
          firstLayout.getAttribute('page-usage', namespaceUri: _styleNs),
          parity,
        );
        final normalLayout = layouts.singleWhere(
          (layout) =>
              layout.getAttribute('name', namespaceUri: _styleNs) ==
              normalLayoutName,
        );
        expect(
          normalLayout.getAttribute('page-usage', namespaceUri: _styleNs),
          isNull,
        );
      },
    );
  }

  test(
    'a first section does not inject a page break from its boundary kind',
    () {
      final result = _export(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [_p('Only page')],
              breakKind: WmlSectionBreakKind.evenPage,
            ),
          ],
        ),
      );
      final paragraph = _paragraph(result.content, 'Only page');
      expect(_master(result.content, paragraph), isNull);
      expect(_elements(result.styles, 'master-page'), hasLength(1));
    },
  );

  test('explicit numbering removal remains an ordinary section paragraph', () {
    final content = _export(
      _two([
        _p(
          'Unnumbered',
          properties: WmlParagraphProps(numId: 0, listLabel: '3.'),
        ),
      ]),
    ).content;
    expect(_elements(_body(content), 'list'), isEmpty);
    expect(_master(content, _paragraph(content, 'Unnumbered')), 'mp1');
  });

  test(
    'parity masters repeat visible headers but emit each comment only once',
    () {
      final document = _two([
        _p('Odd section'),
      ], kind: WmlSectionBreakKind.oddPage);
      document.sections.last.header = [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'Reviewed header', commentIds: [1]),
          ],
        ),
      ];
      document.comments.add(WmlComment(id: 1, text: 'Review on first page'));
      final result = _export(document);
      final masters = _elements(result.styles, 'master-page').toList();
      final first = masters.singleWhere(
        (master) =>
            master.getAttribute('name', namespaceUri: _styleNs) == 'mp1Start',
      );
      final normal = masters.singleWhere(
        (master) =>
            master.getAttribute('name', namespaceUri: _styleNs) == 'mp1',
      );
      expect(_elements(result.styles, 'annotation'), hasLength(1));
      expect(_elements(first, 'annotation'), hasLength(1));
      expect(_elements(normal, 'annotation'), isEmpty);
      expect(_text(normal.firstChild('header')!), 'Reviewed header');
      expect(_text(first.firstChild('header')!), contains('Reviewed header'));
    },
  );

  test(
    'empty unchanged continuous sections add no paragraph or vertical gap',
    () {
      final result = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [_p('Before')]),
            WmlSection(breakKind: WmlSectionBreakKind.continuous),
            WmlSection(
              blocks: [_p('After')],
              breakKind: WmlSectionBreakKind.continuous,
            ),
          ],
        ),
      );
      expect(_body(result.content).childElements.map(_text), [
        'Before',
        'After',
      ]);
      expect(
        _master(result.content, _paragraph(result.content, 'After')),
        isNull,
      );
    },
  );

  test(
    'equal header image bytes do not turn a continuous section into a new page',
    () {
      WmlParagraph picture() => WmlParagraph(
        inlines: [
          WmlRun(
            inlineVisual: WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: 'Logo',
                width: 20,
                height: 10,
                imageBytes: base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
                ),
              ),
            ),
          ),
        ],
      );
      final document = _two([
        _p('Continuous'),
      ], kind: WmlSectionBreakKind.continuous);
      document.sections[0].header = [picture()];
      document.sections[1].header = [picture()];
      final result = _export(document);
      expect(
        _master(result.content, _paragraph(result.content, 'Continuous')),
        isNull,
      );
      expect(_elements(result.styles, 'image'), hasLength(2));
    },
  );

  test('repeated header comments do not force a continuous section break', () {
    final document = _two([
      _p('Continuous'),
    ], kind: WmlSectionBreakKind.continuous);
    for (final section in document.sections) {
      section.header = [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'Header', commentIds: [1]),
          ],
        ),
      ];
    }
    document.comments.add(WmlComment(id: 1, text: 'Review'));
    final result = _export(document);
    expect(
      _master(result.content, _paragraph(result.content, 'Continuous')),
      isNull,
    );
    expect(_elements(result.styles, 'annotation'), hasLength(1));
    expect(
      document.sections.last.header.single.inlines
          .whereType<WmlRun>()
          .single
          .commentIds,
      [1],
    );
  });

  test(
    'different authored header comment references retain distinct masters',
    () {
      final document = _two([
        _p('Continuous'),
      ], kind: WmlSectionBreakKind.continuous);
      for (var index = 0; index < document.sections.length; index++) {
        document.sections[index].header = [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Header', commentIds: [index + 1]),
            ],
          ),
        ];
      }
      document.comments.addAll([
        WmlComment(id: 1, text: 'First review'),
        WmlComment(id: 2, text: 'Second review'),
      ]);
      final result = _export(document);
      expect(
        _master(result.content, _paragraph(result.content, 'Continuous')),
        'mp1',
      );
      expect(_elements(result.styles, 'annotation'), hasLength(2));
    },
  );

  test(
    'header and footer list stories restart independently and compare equally',
    () {
      WmlParagraph item(String text) =>
          _p(text, properties: WmlParagraphProps(numId: 4, listLabel: '1.'));
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [item('Body first')],
            header: [item('Header')],
            footer: [item('Footer')],
          ),
          WmlSection(
            blocks: [item('Body second')],
            header: [item('Header')],
            footer: [item('Footer')],
            breakKind: WmlSectionBreakKind.continuous,
          ),
        ],
      );
      final result = _export(document);
      expect(
        _elements(result.content, 'list-item').map(
          (item) => item.getAttribute('start-value', namespaceUri: _textNs),
        ),
        ['1', '2'],
      );
      expect(
        _elements(result.styles, 'list-item').map(
          (item) => item.getAttribute('start-value', namespaceUri: _textNs),
        ),
        ['1', '1', '1', '1'],
      );
      expect(
        _master(result.content, _paragraph(result.content, 'Body second')),
        isNull,
      );
    },
  );
}
