import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _xlinkNs = 'http://www.w3.org/1999/xlink';

WmlFieldBoundary _boundary(WmlFieldBoundaryKind kind, {String? source}) =>
    WmlFieldBoundary(kind: kind, sourceXml: source);

List<WmlInline> _field(
  String instruction,
  List<WmlInline> result, {
  String? beginSource,
  String? codeProperties,
}) => [
  _boundary(WmlFieldBoundaryKind.begin, source: beginSource),
  WmlFieldBoundary(
    kind: WmlFieldBoundaryKind.instruction,
    text: instruction,
    runPropertiesXml: codeProperties,
  ),
  _boundary(WmlFieldBoundaryKind.separate),
  ...result,
  _boundary(WmlFieldBoundaryKind.end),
];

WmlParagraph _paragraph(List<WmlInline> inlines) =>
    WmlParagraph(inlines: inlines);

WmlDocument _document(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

({XmlElement content, XmlElement styles}) _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  XmlElement part(String name) =>
      XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;
  return (content: part('content'), styles: part('styles'));
}

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name && root.namespaceUri == _textNs) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
  }
}

Iterable<XmlElement> _nativeFields(XmlElement root) sync* {
  for (final name in ['page-number', 'page-count', 'date', 'time', 'title']) {
    yield* _elements(root, name);
  }
}

String _visibleText(XmlNode node) {
  if (node is XmlText) return node.text;
  if (node is! XmlElement) return '';
  if (node.namespaceUri == _textNs) {
    switch (node.localName) {
      case 's':
        return ' ' * int.parse(node.getAttribute('c') ?? '1');
      case 'tab':
        return '\t';
      case 'line-break':
        return '\n';
    }
  }
  return node.children.map(_visibleText).join();
}

List<XmlElement> _paragraphs(XmlElement root) => _elements(root, 'p').toList();

void _expectCached(List<WmlInline> inlines, String text) {
  final output = _export(_document([_paragraph(inlines)])).content;
  expect(_nativeFields(output), isEmpty);
  expect(_visibleText(_paragraphs(output).single), text);
}

void main() {
  for (final kind in [('PAGE', 'page-number'), ('NUMPAGES', 'page-count')]) {
    test('${kind.$1} preserves its cached text, style and hyperlink', () {
      final cache = WmlRun(
        text: '17',
        properties: WmlRunProps(bold: true),
        hyperlink: const WmlHyperlink(url: 'https://example.test/page'),
      );
      final inlines = [
        WmlRun(text: 'Before '),
        ..._field(
          ' ${kind.$1} ',
          [cache],
          beginSource:
              '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
              'w:fldCharType="begin" w:fldLock="false" w:dirty="true"/>',
        ),
        WmlRun(text: ' after'),
      ];
      final output = _export(_document([_paragraph(inlines)])).content;
      final field = _elements(output, kind.$2).single;
      expect(field.text, '17');
      expect(field.childElements, isEmpty);
      expect(_visibleText(_paragraphs(output).single), 'Before 17 after');
      final link = _elements(output, 'a').single;
      expect(
        link.getAttribute('href', namespaceUri: _xlinkNs),
        'https://example.test/page',
      );
      final span = link.childrenNamed('span', namespaceUri: _textNs).single;
      expect(span.childElements.single, same(field));
      final styleName = span.getAttribute('style-name', namespaceUri: _textNs);
      final style = output
          .firstChild('automatic-styles')!
          .childrenNamed('style', namespaceUri: _styleNs)
          .singleWhere(
            (style) =>
                style.getAttribute('name', namespaceUri: _styleNs) == styleName,
          );
      expect(
        style
            .firstChild('text-properties')!
            .getAttribute('font-weight', namespaceUri: _foNs),
        'bold',
      );
      expect(cache.text, '17');
      expect(cache.properties.bold, isTrue);
      expect(inlines.length, 7);
    });
  }

  test('assembles instruction fragments before selecting a native field', () {
    final output = _export(
      _document([
        _paragraph([
          _boundary(WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: ' PA'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: 'GE '),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: r'\* MERGEFORMAT ',
          ),
          _boundary(WmlFieldBoundaryKind.separate),
          WmlRun(text: '4'),
          _boundary(WmlFieldBoundaryKind.end),
        ]),
      ]),
    ).content;
    expect(_elements(output, 'page-number').single.text, '4');
    expect(_paragraphs(output).single.text, '4');
  });

  test('adjacent fields keep one native field and one cache each', () {
    final output = _export(
      _document([
        _paragraph([
          ..._field('PAGE', [WmlRun(text: '4')]),
          WmlRun(text: ' of '),
          ..._field('NUMPAGES', [WmlRun(text: '9')]),
        ]),
      ]),
    ).content;
    expect(_elements(output, 'page-number').single.text, '4');
    expect(_elements(output, 'page-count').single.text, '9');
    expect(_visibleText(_paragraphs(output).single), '4 of 9');
  });

  for (final instruction in [
    'DATE',
    'TIME',
    'TITLE',
    r'PAGE \* ROMAN',
    'REF target',
  ]) {
    test('unsupported instruction $instruction retains its visible cache', () {
      _expectCached(
        _field(instruction, [WmlRun(text: 'Authored result')]),
        'Authored result',
      );
    });
  }

  test('locked fields retain their cached display', () {
    _expectCached(
      _field(
        'PAGE',
        [WmlRun(text: 'Locked 8')],
        beginSource:
            '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
            'w:fldCharType="begin" w:fldLock="true"/>',
      ),
      'Locked 8',
    );
  });

  test('field instruction run formatting retains the cache', () {
    _expectCached(
      _field(
        'PAGE',
        [WmlRun(text: 'Formatted 8')],
        codeProperties: '<w:rPr xmlns:w="${OfficeNamespaces.w}"><w:b/></w:rPr>',
      ),
      'Formatted 8',
    );
  });

  test('malformed source metadata falls back without throwing', () {
    for (final source in [
      '<w:fldChar',
      '<w:fldChar xmlns:w="${OfficeNamespaces.w}" w:fldCharType="begin">',
      '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
          'w:fldCharType="begin" w:fldLock="&#xno;"/>',
      '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
          'w:fldCharType="begin" w:fldLock="&#-1;"/>',
      '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
          'w:fldCharType="begin" w:fldLock="&#x110000;"/>',
    ]) {
      _expectCached(
        _field('PAGE', [WmlRun(text: 'Malformed 8')], beginSource: source),
        'Malformed 8',
      );
    }
  });

  test('form state retains the cache without a partial native field', () {
    _expectCached(
      _field(
        'PAGE',
        [WmlRun(text: 'Form 8')],
        beginSource:
            '<w:fldChar xmlns:w="${OfficeNamespaces.w}" '
            'w:fldCharType="begin"><w:ffData/></w:fldChar>',
      ),
      'Form 8',
    );
  });

  test('unterminated fields preserve the cache and following paragraphs', () {
    final packet = _field('PAGE', [WmlRun(text: 'Open result')])..removeLast();
    final output = _export(
      _document([
        _paragraph(packet),
        _paragraph([WmlRun(text: 'Following paragraph')]),
      ]),
    ).content;
    expect(_nativeFields(output), isEmpty);
    expect(_paragraphs(output).map((paragraph) => paragraph.text), [
      'Open result',
      'Following paragraph',
    ]);
  });

  test('orphan instruction leaves following text visible', () {
    _expectCached([
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: 'PAGE'),
      WmlRun(text: 'Orphan result'),
      _boundary(WmlFieldBoundaryKind.end),
      WmlRun(text: ' after'),
    ], 'Orphan result after');
  });

  test('missing separator retains all cached content', () {
    _expectCached([
      _boundary(WmlFieldBoundaryKind.begin),
      WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: 'PAGE'),
      WmlRun(text: 'No separator'),
      _boundary(WmlFieldBoundaryKind.end),
    ], 'No separator');
  });

  test('nested fields preserve all cached runs without partial conversion', () {
    _expectCached(
      _field('PAGE', [
        WmlRun(text: 'Outer '),
        ..._field('NUMPAGES', [WmlRun(text: 'inner')]),
        WmlRun(text: ' tail'),
      ]),
      'Outer inner tail',
    );
  });

  test('atomic note results retain their reference and note body', () {
    final document = _document([
      _paragraph(_field('PAGE', [WmlRun(text: '1', noteRefId: 1)])),
    ]);
    document.footnotes.add(
      WmlNote(
        id: 1,
        endnote: false,
        blocks: [
          _paragraph([WmlRun(text: 'Note body')]),
        ],
      ),
    );
    final output = _export(document).content;
    expect(_nativeFields(output), isEmpty);
    expect(_elements(output, 'note'), hasLength(1));
    expect(_elements(output, 'note-citation').single.text, '1');
    expect(_elements(output, 'note-body').single.text, contains('Note body'));
  });

  test('multiple styled result runs remain visible and separate', () {
    final output = _export(
      _document([
        _paragraph(
          _field('PAGE', [
            WmlRun(text: 'First', properties: WmlRunProps(bold: true)),
            WmlRun(text: 'Second', properties: WmlRunProps(italic: true)),
          ]),
        ),
      ]),
    ).content;
    expect(_nativeFields(output), isEmpty);
    expect(_paragraphs(output).single.text, 'FirstSecond');
    final spans = _elements(output, 'span').toList();
    expect(spans.map((span) => span.text), ['First', 'Second']);
    expect(
      spans[0].getAttribute('style-name'),
      isNot(spans[1].getAttribute('style-name')),
    );
  });

  test('an unfinished header field cannot consume a footer cache', () {
    final header = _field('PAGE', [WmlRun(text: 'Header cache')])..removeLast();
    final output = _export(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              _paragraph([WmlRun(text: 'Body text')]),
            ],
            header: [_paragraph(header)],
            footer: [
              _paragraph(_field('NUMPAGES', [WmlRun(text: '9')])),
            ],
          ),
        ],
      ),
    );
    expect(_paragraphs(output.content).single.text, 'Body text');
    expect(_paragraphs(output.styles).map((paragraph) => paragraph.text), [
      'Header cache',
      '9',
    ]);
    expect(_elements(output.styles, 'page-number'), isEmpty);
    expect(_elements(output.styles, 'page-count').single.text, '9');
  });

  test('a cross-paragraph outer field prevents nested conversion only', () {
    final output = _export(
      _document([
        _paragraph([
          _boundary(WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: 'REF x',
          ),
          _boundary(WmlFieldBoundaryKind.separate),
          WmlRun(text: 'Outer start'),
        ]),
        _paragraph(_field('PAGE', [WmlRun(text: 'Nested cache')])),
        _paragraph([
          WmlRun(text: 'Outer end'),
          _boundary(WmlFieldBoundaryKind.end),
          ..._field('NUMPAGES', [WmlRun(text: '9')]),
        ]),
      ]),
    ).content;
    expect(_elements(output, 'page-number'), isEmpty);
    expect(_elements(output, 'page-count').single.text, '9');
    expect(_paragraphs(output).map((paragraph) => paragraph.text), [
      'Outer start',
      'Nested cache',
      'Outer end9',
    ]);
  });

  test(
    'native cached character data is escaped without adding child nodes',
    () {
      final output = _export(
        _document([
          _paragraph(_field('PAGE', [WmlRun(text: '7 & <eight>')])),
        ]),
      ).content;
      final field = _elements(output, 'page-number').single;
      expect(field.text, '7 & <eight>');
      expect(field.childElements, isEmpty);
    },
  );
  test('field cache fallback retains an authored inline column break', () {
    final output = _export(
      _document([
        _paragraph(
          _field('PAGE', [
            WmlRun(text: 'Before column'),
            WmlBreak(WmlBreakType.column),
            WmlRun(text: 'After column'),
          ]),
        ),
      ]),
    ).content;
    expect(_nativeFields(output), isEmpty);
    final paragraphs = _paragraphs(output);
    expect(paragraphs.map((p) => p.text), ['Before column', 'After column']);
    final styleName = paragraphs.last.getAttribute(
      'style-name',
      namespaceUri: _textNs,
    );
    final properties = output
        .firstChild('automatic-styles')!
        .childrenNamed('style')
        .singleWhere(
          (s) => s.getAttribute('name', namespaceUri: _styleNs) == styleName,
        )
        .firstChild('paragraph-properties')!;
    expect(
      properties.getAttribute('break-before', namespaceUri: _foNs),
      'column',
    );
  });
}
