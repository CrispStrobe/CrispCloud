import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _linkNs = 'http://www.w3.org/1999/xlink';

WmlDocument _import(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body'
        '<w:sectPr><w:cols w:num="2" w:space="360"/></w:sectPr>'
        '</w:body></w:document>',
      );
  return WordDeserializer().read(package);
}

XmlElement _export(WmlDocument document) {
  final paragraphs = document.paragraphs.toList();
  final properties = [for (final paragraph in paragraphs) paragraph.properties];
  final inlines = [
    for (final paragraph in paragraphs) List<WmlInline>.of(paragraph.inlines),
  ];
  final texts = [for (final paragraph in paragraphs) paragraph.text];
  final flags = [
    for (final paragraph in paragraphs)
      (
        paragraph.properties.pageBreakBefore,
        paragraph.properties.columnBreakBefore,
      ),
  ];
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  for (var i = 0; i < paragraphs.length; i++) {
    expect(identical(paragraphs[i].properties, properties[i]), isTrue);
    expect(paragraphs[i].inlines, orderedEquals(inlines[i]));
    expect(paragraphs[i].text, texts[i]);
    expect((
      paragraphs[i].properties.pageBreakBefore,
      paragraphs[i].properties.columnBreakBefore,
    ), flags[i]);
  }
  return XmlDocument.parse(package.getPart('/content.xml')!.readText()).root!;
}

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

XmlElement _body(XmlElement content) => content
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!;

XmlElement _style(XmlElement content, XmlElement element) {
  final name = element.getAttribute('style-name', namespaceUri: _textNs);
  return content
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

XmlElement _properties(XmlElement content, XmlElement element) => _style(
  content,
  element,
).firstChild('paragraph-properties', namespaceUri: _styleNs)!;

String? _breakBefore(XmlElement content, XmlElement paragraph) => _properties(
  content,
  paragraph,
).getAttribute('break-before', namespaceUri: _foNs);

String _visible(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    switch (node.localName) {
      case 's':
        return ' ' *
            int.parse(node.getAttribute('c', namespaceUri: _textNs) ?? '1');
      case 'tab':
        return '\t';
      case 'line-break':
        return '\n';
      case 'page-number':
        return '{PAGE}';
    }
  }
  return node.children.map(_visible).join();
}

void main() {
  test('imported leading column break belongs only to its kept paragraph', () {
    final document = _import(
      '<w:p><w:r><w:t>Before</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:keepLines/></w:pPr>'
      '<w:bookmarkStart w:id="7" w:name="Column"/>'
      '<w:r><w:br w:type="column"/><w:t>Column kept</w:t></w:r>'
      '<w:bookmarkEnd w:id="7"/></w:p>'
      '<w:p><w:r><w:t>After</w:t></w:r></w:p>',
    );
    final kept = document.paragraphs.elementAt(1);
    expect(kept.properties.columnBreakBefore, isFalse);
    expect(kept.inlines.whereType<WmlBreak>().single.type, WmlBreakType.column);
    final content = _export(document);
    final paragraphs = _elements(_body(content), 'p').toList();
    expect(paragraphs.map(_visible), ['Before', 'Column kept', 'After']);
    expect(paragraphs.map((p) => _breakBefore(content, p)), [
      null,
      'column',
      null,
    ]);
    expect(
      _properties(
        content,
        paragraphs[1],
      ).getAttribute('keep-together', namespaceUri: _foNs),
      'always',
    );
    expect(_elements(paragraphs[1], 'bookmark-start'), hasLength(1));
    expect(_elements(paragraphs[1], 'bookmark-end'), hasLength(1));
    expect(_elements(content, 'soft-page-break'), isEmpty);
  });

  test(
    'imported middle column break retains exact runs, links and bookmark extent',
    () {
      final document = _import(
        '<w:p><w:pPr><w:spacing w:before="120" w:after="160"/>'
        '<w:ind w:left="400" w:firstLine="240"/></w:pPr>'
        '<w:bookmarkStart w:id="1" w:name="Across"/>'
        '<w:r><w:rPr><w:b/><w:color w:val="1234AB"/></w:rPr>'
        '<w:t xml:space="preserve"> Left </w:t><w:tab/>'
        '<w:br w:type="column"/><w:t xml:space="preserve"> Right </w:t></w:r>'
        '<w:hyperlink w:anchor="Across"><w:r><w:t>Link</w:t></w:r></w:hyperlink>'
        '<w:bookmarkEnd w:id="1"/></w:p>',
      );
      final source = document.paragraphs.single;
      final content = _export(document);
      final paragraphs = _elements(_body(content), 'p').toList();
      expect(paragraphs.map(_visible), [' Left \t', ' Right Link']);
      expect(paragraphs.map((p) => _breakBefore(content, p)), [null, 'column']);
      final first = _properties(content, paragraphs.first);
      final last = _properties(content, paragraphs.last);
      expect(first.getAttribute('margin-top', namespaceUri: _foNs), '6.00pt');
      expect(
        first.getAttribute('margin-bottom', namespaceUri: _foNs),
        '0.00pt',
      );
      expect(first.getAttribute('text-indent', namespaceUri: _foNs), '12.00pt');
      expect(last.getAttribute('margin-top', namespaceUri: _foNs), '0.00pt');
      expect(last.getAttribute('margin-bottom', namespaceUri: _foNs), '8.00pt');
      expect(last.getAttribute('text-indent', namespaceUri: _foNs), isNull);
      for (final paragraph in paragraphs) {
        expect(
          _properties(
            content,
            paragraph,
          ).getAttribute('margin-left', namespaceUri: _foNs),
          '20.00pt',
        );
        final span = _elements(paragraph, 'span').first;
        final textProperties = _style(
          content,
          span,
        ).firstChild('text-properties')!;
        expect(
          textProperties.getAttribute('color', namespaceUri: _foNs),
          '#1234ab',
        );
        expect(
          textProperties.getAttribute('font-weight', namespaceUri: _foNs),
          'bold',
        );
      }
      expect(_elements(paragraphs.first, 'bookmark-start'), hasLength(1));
      expect(_elements(paragraphs.first, 'bookmark-end'), isEmpty);
      expect(_elements(paragraphs.last, 'bookmark-start'), isEmpty);
      expect(_elements(paragraphs.last, 'bookmark-end'), hasLength(1));
      expect(
        _elements(
          paragraphs.last,
          'a',
        ).single.getAttribute('href', namespaceUri: _linkNs),
        '#Across',
      );
      expect(source.properties.spacingBefore, 6);
      expect(source.properties.spacingAfter, 8);
      expect(source.properties.indent.firstLine, 12);
    },
  );

  test(
    'authored whitespace before a column break remains before that break',
    () {
      final content = _export(
        _import(
          '<w:p><w:r><w:t xml:space="preserve"> </w:t><w:tab/>'
          '<w:t xml:space="preserve"> </w:t><w:br w:type="column"/>'
          '<w:t>After whitespace</w:t></w:r></w:p>',
        ),
      );
      final paragraphs = _elements(_body(content), 'p').toList();
      expect(paragraphs.map(_visible), [' \t ', 'After whitespace']);
      expect(paragraphs.map((p) => _breakBefore(content, p)), [null, 'column']);
    },
  );

  test('middle column break stays within one imported list item', () {
    final content = _export(
      _import(
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr>'
        '<w:r><w:t>Item left</w:t><w:br w:type="column"/><w:t>Item right</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr>'
        '<w:r><w:t>Next item</w:t></w:r></w:p>',
      ),
    );
    final items = _elements(_body(content), 'list-item').toList();
    expect(items, hasLength(2));
    final first = items.first
        .childrenNamed('p', namespaceUri: _textNs)
        .toList();
    expect(first.map(_visible), ['Item left', 'Item right']);
    expect(first.map((p) => _breakBefore(content, p)), [null, 'column']);
    expect(items.last.childrenNamed('p', namespaceUri: _textNs).map(_visible), [
      'Next item',
    ]);
  });

  test(
    'consecutive and trailing column breaks retain each authored boundary',
    () {
      final content = _export(
        _import(
          '<w:p><w:r><w:t>Left</w:t><w:br w:type="column"/>'
          '<w:br w:type="column"/><w:t>Right</w:t><w:br w:type="column"/></w:r></w:p>',
        ),
      );
      final paragraphs = _elements(_body(content), 'p').toList();
      expect(paragraphs.map(_visible), ['Left', '', 'Right', '']);
      expect(paragraphs.map((p) => _breakBefore(content, p)), [
        null,
        'column',
        'column',
        'column',
      ]);
      expect(_elements(content, 'soft-page-break'), isEmpty);
    },
  );

  test(
    'section and page precedence stay on the first column fragment only',
    () {
      final document = _import(
        '<w:p><w:pPr><w:sectPr><w:cols w:num="2"/></w:sectPr></w:pPr>'
        '<w:r><w:t>First section</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pageBreakBefore/></w:pPr>'
        '<w:r><w:br w:type="column"/><w:t>Second section</w:t>'
        '<w:br w:type="column"/><w:t>Continuation</w:t></w:r></w:p>',
      );
      expect(document.sections, hasLength(2));
      final content = _export(document);
      final paragraphs = _elements(_body(content), 'p').toList();
      expect(paragraphs.map(_visible), [
        'First section',
        'Second section',
        'Continuation',
      ]);
      final first = paragraphs[1];
      final last = paragraphs[2];
      expect(_breakBefore(content, first), 'page');
      expect(
        _style(
          content,
          first,
        ).getAttribute('master-page-name', namespaceUri: _styleNs),
        'mp1',
      );
      expect(
        _properties(
          content,
          first,
        ).getAttribute('page-number', namespaceUri: _styleNs),
        'auto',
      );
      expect(_breakBefore(content, last), 'column');
      expect(
        _style(
          content,
          last,
        ).getAttribute('master-page-name', namespaceUri: _styleNs),
        isNull,
      );
      expect(
        _properties(
          content,
          last,
        ).getAttribute('page-number', namespaceUri: _styleNs),
        isNull,
      );
    },
  );

  test(
    'line and page breaks retain their existing position beside a column break',
    () {
      final content = _export(
        _import(
          '<w:p><w:r><w:t>One</w:t><w:br/><w:t>Two</w:t><w:br w:type="page"/>'
          '<w:t>Three</w:t><w:br w:type="column"/><w:t>Four</w:t></w:r></w:p>',
        ),
      );
      final paragraphs = _elements(_body(content), 'p').toList();
      expect(paragraphs.map(_visible), ['One\nTwoThree', 'Four']);
      expect(_elements(paragraphs.first, 'line-break'), hasLength(1));
      expect(_elements(paragraphs.first, 'soft-page-break'), hasLength(1));
      expect(_elements(paragraphs.last, 'soft-page-break'), isEmpty);
      expect(_breakBefore(content, paragraphs.first), isNull);
      expect(_breakBefore(content, paragraphs.last), 'column');
    },
  );

  test(
    'split paragraph retains single comment, note and field result ownership',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' ADDIN PRIVATE ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'Citation', commentIds: [4]),
          WmlBreak(WmlBreakType.column),
          WmlRun(text: ' result'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(text: '5', noteRefId: 5),
        ],
      );
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph], columnCount: 2),
          ],
          comments: [WmlComment(id: 4, text: 'One comment')],
          footnotes: [
            WmlNote(
              id: 5,
              endnote: false,
              paragraphs: [
                WmlParagraph(inlines: [WmlRun(text: 'One note')]),
              ],
            ),
          ],
        ),
      );
      final paragraphs = _body(content)
          .firstChild('section')!
          .childrenNamed('p', namespaceUri: _textNs)
          .toList();
      expect(paragraphs, hasLength(2));
      expect(_elements(paragraphs.first, 'annotation'), hasLength(1));
      expect(_elements(paragraphs.last, 'annotation'), isEmpty);
      expect(_elements(paragraphs.first, 'note'), isEmpty);
      expect(_elements(paragraphs.last, 'note'), hasLength(1));
      expect(_elements(content, 'annotation'), hasLength(1));
      expect(_elements(content, 'note-body').single.text, contains('One note'));
      expect(_visible(content), isNot(contains('PRIVATE')));
      expect(_visible(paragraphs.first), contains('Citation'));
      expect(_visible(paragraphs.last), startsWith(' result'));
    },
  );

  test(
    'paragraph PAGE field is generated once across a column continuation',
    () {
      final paragraph = WmlParagraph(
        properties: WmlParagraphProps(pageNumberField: true),
        inlines: [
          WmlRun(text: '12'),
          WmlBreak(WmlBreakType.column),
          WmlRun(text: ' | Title'),
        ],
      );
      final content = _export(
        WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph], columnCount: 2),
          ],
        ),
      );
      final paragraphs = _elements(_body(content), 'p').toList();
      expect(paragraphs.map(_visible), ['{PAGE}', ' | Title']);
      expect(_elements(content, 'page-number'), hasLength(1));
      expect(_breakBefore(content, paragraphs.last), 'column');
    },
  );
}
