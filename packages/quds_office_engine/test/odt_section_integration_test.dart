import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _tableNs = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlParagraph _paragraph(String text, {WmlParagraphProps? properties}) =>
    WmlParagraph(
      properties: properties,
      inlines: [WmlRun(text: text)],
    );

OpcPackage _package(WmlDocument document) =>
    OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));

XmlElement _part(OpcPackage package, String path) =>
    XmlDocument.parse(package.getPart('/$path')!.readText()).root!;

String _visibleText(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    if (node.localName == 's') {
      return ' ' *
          int.parse(node.getAttribute('c', namespaceUri: _textNs) ?? '1');
    }
    if (node.localName == 'tab') return '\t';
    if (node.localName == 'line-break') return '\n';
  }
  return node.children.map(_visibleText).join();
}

XmlElement _body(XmlElement content) => content
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!;

String? _attribute(XmlElement element, String name, String namespace) =>
    element.getAttribute(name, namespaceUri: namespace);

XmlElement _named(XmlElement parent, String localName, String name) => parent
    .childrenNamed(localName, namespaceUri: _styleNs)
    .singleWhere((element) => _attribute(element, 'name', _styleNs) == name);

XmlElement _style(XmlElement content, String name) => _named(
  content.firstChild('automatic-styles', namespaceUri: _officeNs)!,
  'style',
  name,
);

Iterable<XmlElement> _elements(
  XmlElement root,
  String name,
  String namespace,
) sync* {
  if (root.localName == name && root.namespaceUri == namespace) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name, namespace);
  }
}

WmlTable _table() => WmlTable(
  rows: [
    WmlTableRow(
      cells: [
        WmlTableCell(blocks: [_paragraph('Cell story')]),
      ],
    ),
  ],
);

WmlBlock _leadingBlock(String kind) => switch (kind) {
  'table' => _table(),
  'frame' => WmlFrame(blocks: [_paragraph('Frame story')]),
  'control' => WmlContentControlBlock(
    control: WmlContentControlData(
      xml:
          '<w:sdt xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"/>',
      sourcePartUri: '/word/document.xml',
      relationships: const <WmlOpaqueRelationship>[],
    ),
    blocks: [_paragraph('Control story')],
  ),
  _ => throw ArgumentError.value(kind),
};

WmlDocument _twoSections(
  List<WmlBlock> blocks, {
  WmlSectionBreakKind breakKind = WmlSectionBreakKind.nextPage,
}) => WmlDocument(
  sections: [
    WmlSection(blocks: [_paragraph('First section')]),
    WmlSection(blocks: blocks, breakKind: breakKind),
  ],
);

WmlRun _reference({required bool endnote}) =>
    WmlRun(text: '7', noteRefId: 7, noteRefEndnote: endnote);

Map<String, String> _resolvedProperties(XmlElement style) => {
  for (final attribute
      in style
          .firstChild('paragraph-properties', namespaceUri: _styleNs)!
          .attributes)
    if (!(attribute.namespaceUri == _foNs &&
            attribute.localName == 'break-before') &&
        !(attribute.namespaceUri == _styleNs &&
            attribute.localName == 'page-number'))
      '${attribute.namespaceUri}|${attribute.localName}': attribute.value,
};

void main() {
  for (final ordered in [false, true]) {
    test(
      'section style applies only to the first list item: ordered=$ordered',
      () {
        final paragraphs = [
          for (final text in ['First item', 'Second item'])
            _paragraph(
              text,
              properties: WmlParagraphProps(
                numId: 1,
                listLabel: ordered ? '1.' : '•',
                rightToLeft: true,
                justification: WmlJustification.right,
              ),
            ),
        ];
        final document = _twoSections(paragraphs);
        final package = _package(document);
        final content = _part(package, 'content.xml');
        final body = _body(content);
        final children = body.childElements.toList();
        expect(children, hasLength(2));
        final list = children.last;
        expect(list.namespaceUri, _textNs);
        expect(list.localName, 'list');
        // Marker styles may be shared in styles.xml or generated in
        // content.xml; assert their semantics independently of their names.
        final listStyle =
            [
              ..._elements(content, 'list-style', _textNs),
              ..._elements(_part(package, 'styles.xml'), 'list-style', _textNs),
            ].singleWhere(
              (style) =>
                  _attribute(style, 'name', _styleNs) ==
                  _attribute(list, 'style-name', _textNs),
            );
        final marker = listStyle.childElements.first;
        expect(
          marker.localName,
          ordered ? 'list-level-style-number' : 'list-level-style-bullet',
        );
        expect(
          _attribute(
            marker,
            ordered ? 'num-format' : 'bullet-char',
            ordered ? _styleNs : _textNs,
          ),
          ordered ? '1' : '•',
        );
        final items = list
            .childrenNamed('list-item', namespaceUri: _textNs)
            .toList();
        expect(items, hasLength(2));
        final first = items.first.firstChild('p', namespaceUri: _textNs)!;
        final second = items.last.firstChild('p', namespaceUri: _textNs)!;
        expect(_attribute(first, 'style-name', _textNs), 'SB1');
        expect(_attribute(second, 'style-name', _textNs), isNot('SB1'));
        final sectionStyle = _style(content, 'SB1');
        expect(
          _attribute(sectionStyle, 'parent-style-name', _styleNs),
          'Standard',
        );
        expect(_attribute(sectionStyle, 'master-page-name', _styleNs), 'mp1');
        final properties = sectionStyle.firstChild('paragraph-properties')!;
        expect(_attribute(properties, 'writing-mode', _styleNs), 'rl-tb');
        expect(_attribute(properties, 'text-align', _foNs), 'right');
        expect(paragraphs.map((paragraph) => paragraph.text), [
          'First item',
          'Second item',
        ]);
        expect(document.sections.last.blocks.length, 2);
      },
    );
    test(
      'nested section list applies its page boundary once: ordered=$ordered',
      () {
        final entries = [
          ('Parent', 0),
          ('Child one', 1),
          ('Grandchild', 2),
          ('Child two', 1),
          ('Sibling', 0),
        ];
        final paragraphs = [
          for (final (text, level) in entries)
            _paragraph(
              text,
              properties: WmlParagraphProps(
                numId: 1,
                ilvl: level,
                listLabel: ordered ? '1.' : '•',
              ),
            ),
        ];
        final document = _twoSections(paragraphs);
        final content = _part(_package(document), 'content.xml');
        final list = _body(
          content,
        ).childrenNamed('list', namespaceUri: _textNs).single;
        final roots = list
            .childrenNamed('list-item', namespaceUri: _textNs)
            .toList();
        expect(roots, hasLength(2));
        final children = roots.first
            .firstChild('list', namespaceUri: _textNs)!
            .childrenNamed('list-item', namespaceUri: _textNs)
            .toList();
        expect(children, hasLength(2));
        expect(
          children.first
              .firstChild('list', namespaceUri: _textNs)!
              .childrenNamed('list-item', namespaceUri: _textNs),
          hasLength(1),
        );
        final written = _elements(list, 'p', _textNs).toList();
        expect(written.map(_visibleText), entries.map((entry) => entry.$1));
        expect(_attribute(written.first, 'style-name', _textNs), 'SB1');
        for (final paragraph in written.skip(1)) {
          final styleName = _attribute(paragraph, 'style-name', _textNs)!;
          expect(styleName, isNot('SB1'));
          expect(
            _attribute(
              _style(content, styleName),
              'master-page-name',
              _styleNs,
            ),
            isNull,
          );
        }
        final sectionStyle = _style(content, 'SB1');
        expect(_attribute(sectionStyle, 'master-page-name', _styleNs), 'mp1');
        expect(
          _attribute(
            sectionStyle.firstChild('paragraph-properties')!,
            'break-before',
            _foNs,
          ),
          'page',
        );
        expect(
          paragraphs.map((paragraph) => paragraph.properties.ilvl),
          entries.map((entry) => entry.$2),
        );
        expect(document.sections.last.blocks, orderedEquals(paragraphs));
      },
    );
  }

  for (final kind in ['table', 'frame', 'control']) {
    test(
      'a leading $kind activates its section without an extra body paragraph',
      () {
        final leading = _leadingBlock(kind);
        final document = _twoSections([leading, _paragraph('After story')]);
        final content = _part(_package(document), 'content.xml');
        final children = _body(content).childElements.toList();
        expect(children, hasLength(3));
        // The new section activation follows exported content: a table owns
        // its boundary, a frame uses its containing paragraph, and a content
        // control passes the boundary to its first visible paragraph.
        final owner = children[1];
        expect(owner.localName, kind == 'table' ? 'table' : 'p');
        expect(owner.namespaceUri, kind == 'table' ? _tableNs : _textNs);
        final style = _style(
          content,
          _attribute(
            owner,
            'style-name',
            kind == 'table' ? _tableNs : _textNs,
          )!,
        );
        expect(_attribute(style, 'master-page-name', _styleNs), 'mp1');
        final properties = style.firstChild(
          kind == 'table' ? 'table-properties' : 'paragraph-properties',
          namespaceUri: _styleNs,
        )!;
        expect(_attribute(properties, 'break-before', _foNs), 'page');
        if (kind == 'table') {
          expect(_elements(owner, 'table-cell', _tableNs), hasLength(1));
        }
        if (kind == 'frame') {
          expect(_elements(owner, 'frame', _drawNs), hasLength(1));
        }
        final expectedText = switch (kind) {
          'table' => 'Cell story',
          'frame' => 'Frame story',
          _ => 'Control story',
        };
        expect(owner.text, expectedText);
        expect(children.last.text, 'After story');
        // Inner table/frame stories do not acquire their own page boundary.
        for (final paragraph in _elements(owner, 'p', _textNs)) {
          if (identical(paragraph, owner)) continue;
          final innerStyle = _style(
            content,
            _attribute(paragraph, 'style-name', _textNs)!,
          );
          expect(_attribute(innerStyle, 'master-page-name', _styleNs), isNull);
        }
        final afterStyle = _style(
          content,
          _attribute(children.last, 'style-name', _textNs)!,
        );
        expect(_attribute(afterStyle, 'master-page-name', _styleNs), isNull);
        expect(document.sections.last.blocks, hasLength(2));
        expect(identical(document.sections.last.blocks.first, leading), isTrue);
      },
    );
  }

  test('an empty noncontinuous section retains an explicit boundary', () {
    final document = _twoSections([]);
    final content = _part(_package(document), 'content.xml');
    final paragraphs = _body(
      content,
    ).childrenNamed('p', namespaceUri: _textNs).toList();
    expect(paragraphs, hasLength(2));
    expect(paragraphs.last.text, isEmpty);
    expect(_attribute(paragraphs.last, 'style-name', _textNs), 'SB1');
    expect(document.sections, hasLength(2));
    expect(document.sections.last.blocks, isEmpty);
  });

  test(
    'an explicitly empty document has default master geometry without mutation',
    () {
      final document = WmlDocument(sections: []);
      final package = _package(document);
      expect(_body(_part(package, 'content.xml')).childElements, isEmpty);
      final styles = _part(package, 'styles.xml');
      final masters = styles.firstChild(
        'master-styles',
        namespaceUri: _officeNs,
      )!;
      expect(masters.childElements, hasLength(1));
      final master = _named(masters, 'master-page', 'Standard');
      expect(_attribute(master, 'page-layout-name', _styleNs), 'pm0');
      final layout = _named(
        styles.firstChild('automatic-styles', namespaceUri: _officeNs)!,
        'page-layout',
        'pm0',
      );
      final properties = layout.firstChild(
        'page-layout-properties',
        namespaceUri: _styleNs,
      )!;
      const page = WmlPageSize();
      expect(
        _attribute(properties, 'page-width', _foNs),
        '${page.width.toStringAsFixed(2)}pt',
      );
      expect(
        _attribute(properties, 'page-height', _foNs),
        '${page.height.toStringAsFixed(2)}pt',
      );
      expect(document.sections, isEmpty);
    },
  );

  for (final tableFirst in [false, true]) {
    test(
      'continuous section does not assign a page-breaking master: table=$tableFirst',
      () {
        final document = _twoSections([
          tableFirst ? _table() : _paragraph('Continuous content'),
        ], breakKind: WmlSectionBreakKind.continuous);
        final content = _part(_package(document), 'content.xml');
        expect(_body(content).childElements, hasLength(2));
        final styles = content.firstChild(
          'automatic-styles',
          namespaceUri: _officeNs,
        )!;
        expect(
          styles
              .childrenNamed('style', namespaceUri: _styleNs)
              .where(
                (style) =>
                    _attribute(style, 'master-page-name', _styleNs) != null,
              ),
          isEmpty,
        );
        // Deferred section styles may exist after equivalent-master reuse;
        // their presence must not introduce an actual page break.
        final owner = _body(content).childElements.last;
        final ownerStyle = _style(
          content,
          _attribute(owner, 'style-name', tableFirst ? _tableNs : _textNs)!,
        );
        final properties = ownerStyle.firstChild(
          tableFirst ? 'table-properties' : 'paragraph-properties',
          namespaceUri: _styleNs,
        )!;
        expect(_attribute(properties, 'break-before', _foNs), isNull);
      },
    );
  }

  test(
    'section paragraph keeps direct formatting and a defined common parent',
    () {
      final properties = WmlParagraphProps(
        headingLevel: 2,
        rightToLeft: true,
        justification: WmlJustification.right,
        spacingBefore: 6,
        spacingAfter: 0,
        lineSpacingRule: WmlLineSpacingRule.exact,
        lineSpacing: 18,
      );
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [_paragraph('First heading', properties: properties)],
          ),
          WmlSection(
            blocks: [_paragraph('Second heading', properties: properties)],
          ),
        ],
      );
      final package = _package(document);
      final content = _part(package, 'content.xml');
      final headings = _body(
        content,
      ).childrenNamed('h', namespaceUri: _textNs).toList();
      expect(headings, hasLength(2));
      final firstStyle = _style(
        content,
        _attribute(headings.first, 'style-name', _textNs)!,
      );
      final sectionStyle = _style(content, 'SB1');
      expect(
        _attribute(sectionStyle, 'parent-style-name', _styleNs),
        'Heading_20_2',
      );
      expect(
        _resolvedProperties(sectionStyle),
        _resolvedProperties(firstStyle),
      );
      final common = _part(
        package,
        'styles.xml',
      ).firstChild('styles', namespaceUri: _officeNs)!;
      expect(_named(common, 'style', 'Heading_20_2'), isNotNull);
      final sectionProperties = sectionStyle.firstChild(
        'paragraph-properties',
        namespaceUri: _styleNs,
      )!;
      expect(_attribute(sectionProperties, 'break-before', _foNs), 'page');
      expect(_attribute(sectionStyle, 'master-page-name', _styleNs), 'mp1');
    },
  );

  for (final endnote in [false, true]) {
    test(
      'section masters and comment stories preserve visible notes: endnote=$endnote',
      () {
        final note = WmlNote(
          id: 7,
          endnote: endnote,
          paragraphs: [_paragraph('Note body')],
        );
        final document = WmlDocument(
          footnotes: endnote ? null : [note],
          endnotes: endnote ? [note] : null,
          comments: [
            for (final id in [1, 2])
              WmlComment(
                id: id,
                author: 'Reviewer',
                paragraphs: [
                  WmlParagraph(
                    inlines: [
                      WmlRun(text: 'Comment story '),
                      _reference(endnote: endnote),
                    ],
                  ),
                ],
              ),
          ],
          sections: [
            WmlSection(
              header: [_paragraph('First header')],
              blocks: [
                WmlParagraph(
                  inlines: [
                    WmlRun(text: 'First body', commentIds: [1]),
                  ],
                ),
              ],
            ),
            WmlSection(
              pageSize: WmlPageSize.letter(),
              margins: WmlPageMargins.narrow,
              header: [
                WmlParagraph(
                  inlines: [
                    WmlRun(text: 'Second header ', commentIds: [2]),
                    _reference(endnote: endnote),
                  ],
                ),
              ],
              footer: [
                WmlParagraph(
                  inlines: [
                    WmlRun(text: 'Second footer '),
                    _reference(endnote: endnote),
                  ],
                ),
              ],
              blocks: [
                WmlParagraph(
                  inlines: [
                    WmlRun(text: 'Second body '),
                    _reference(endnote: endnote),
                    _reference(endnote: endnote),
                  ],
                ),
              ],
            ),
          ],
        );
        final package = _package(document);
        final content = _part(package, 'content.xml');
        final styles = _part(package, 'styles.xml');
        final notes = _elements(content, 'note', _textNs).toList();
        expect(notes, hasLength(1));
        expect(_elements(content, 'note-ref', _textNs), hasLength(1));
        expect(
          _elements(content, 'note-body', _textNs).single.text,
          contains('Note body'),
        );
        final label = endnote ? 'i' : '1';
        expect(_elements(content, 'note-citation', _textNs).single.text, label);
        final bodyComment = _elements(content, 'annotation', _officeNs).single;
        expect(_elements(bodyComment, 'note', _textNs), isEmpty);
        expect(_elements(bodyComment, 'note-ref', _textNs), isEmpty);
        expect(_visibleText(bodyComment), contains('Comment story $label'));
        expect(_elements(styles, 'note', _textNs), isEmpty);
        expect(_elements(styles, 'note-ref', _textNs), isEmpty);
        final masters = styles.firstChild(
          'master-styles',
          namespaceUri: _officeNs,
        )!;
        expect(
          masters.childrenNamed('master-page', namespaceUri: _styleNs),
          hasLength(2),
        );
        final masterName = _attribute(
          _style(content, 'SB1'),
          'master-page-name',
          _styleNs,
        )!;
        final master = _named(masters, 'master-page', masterName);
        final layoutName = _attribute(master, 'page-layout-name', _styleNs)!;
        final pageLayout = _named(
          styles.firstChild('automatic-styles', namespaceUri: _officeNs)!,
          'page-layout',
          layoutName,
        );
        expect(layoutName, 'pm1');
        expect(
          _attribute(
            pageLayout.firstChild('page-layout-properties')!,
            'page-width',
            _foNs,
          ),
          '612.00pt',
        );
        expect(
          master.firstChild('header', namespaceUri: _styleNs)!.text,
          contains('Second header'),
        );
        expect(
          _visibleText(master.firstChild('footer', namespaceUri: _styleNs)!),
          'Second footer $label',
        );
        expect(
          _visibleText(_elements(master, 'annotation', _officeNs).single),
          contains('Comment story $label'),
        );
        expect(note.id, 7);
        expect(note.text, 'Note body');
        expect(
          document.comments.map((comment) => comment.paragraphs.single.text),
          ['Comment story 7', 'Comment story 7'],
        );
        expect(document.sections.last.blocks, hasLength(1));
      },
    );
  }
}
