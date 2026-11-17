import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

WmlParagraph _paragraph(String text, {String? fill, String? border}) =>
    WmlParagraph(
      properties: WmlParagraphProps(shadingFill: fill, borderColor: border),
      inlines: [WmlRun(text: text)],
    );

({XmlElement content, XmlElement styles}) _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  XmlElement part(String name) =>
      XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;
  return (content: part('content'), styles: part('styles'));
}

XmlElement _body(XmlElement root) => root
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!;

XmlElement _properties(XmlElement root, XmlElement paragraph) {
  final name = paragraph.getAttribute('style-name', namespaceUri: _textNs);
  return root
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      )
      .firstChild('paragraph-properties', namespaceUri: _styleNs)!;
}

void _expectDecoration(
  XmlElement root,
  XmlElement paragraph, {
  String? fill,
  String? border,
}) {
  final properties = _properties(root, paragraph);
  expect(
    properties.getAttribute('background-color', namespaceUri: _foNs),
    fill,
  );
  expect(properties.getAttribute('border', namespaceUri: _foNs), border);
}

void main() {
  test('neighboring paragraphs retain distinct shading and border colors', () {
    final paragraphs = [
      _paragraph('red', fill: 'FF0000'),
      _paragraph('green', fill: '00FF00'),
      _paragraph('blue border', border: '0000FF'),
      _paragraph('black border', border: '000000'),
      _paragraph('both', fill: 'FFFF00', border: 'FF00FF'),
      _paragraph('plain'),
    ];
    final content = _export(
      WmlDocument(sections: [WmlSection(blocks: paragraphs)]),
    ).content;
    final exported = _body(
      content,
    ).childrenNamed('p', namespaceUri: _textNs).toList();
    expect(exported.map((paragraph) => paragraph.text), [
      'red',
      'green',
      'blue border',
      'black border',
      'both',
      'plain',
    ]);
    _expectDecoration(content, exported[0], fill: '#ff0000');
    _expectDecoration(content, exported[1], fill: '#00ff00');
    _expectDecoration(content, exported[2], border: '0.5pt solid #0000ff');
    _expectDecoration(content, exported[3], border: '0.5pt solid #000000');
    _expectDecoration(
      content,
      exported[4],
      fill: '#ffff00',
      border: '0.5pt solid #ff00ff',
    );
    _expectDecoration(content, exported[5]);
  });

  for (final decoratedFirst in [false, true]) {
    test(
      'plain paragraph cannot inherit decoration: first=$decoratedFirst',
      () {
        final plain = _paragraph('plain');
        final decorated = _paragraph(
          'decorated',
          fill: 'ABCDEF',
          border: '123456',
        );
        final content = _export(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: decoratedFirst
                    ? [decorated, plain]
                    : [plain, decorated],
              ),
            ],
          ),
        ).content;
        for (final paragraph in _body(content).childElements) {
          if (paragraph.text == 'plain') {
            _expectDecoration(content, paragraph);
          } else {
            _expectDecoration(
              content,
              paragraph,
              fill: '#abcdef',
              border: '0.5pt solid #123456',
            );
          }
        }
      },
    );
  }

  test('normalizes valid color case without changing the model', () {
    final paragraphs = [
      _paragraph('upper', fill: 'ABCDEF', border: 'FEDCBA'),
      _paragraph('mixed', fill: 'aBcDeF', border: 'fEdCbA'),
    ];
    final content = _export(
      WmlDocument(sections: [WmlSection(blocks: paragraphs)]),
    ).content;
    for (final paragraph in _body(content).childElements) {
      _expectDecoration(
        content,
        paragraph,
        fill: '#abcdef',
        border: '0.5pt solid #fedcba',
      );
    }
    expect(paragraphs.map((p) => p.properties.shadingFill), [
      'ABCDEF',
      'aBcDeF',
    ]);
    expect(paragraphs.map((p) => p.properties.borderColor), [
      'FEDCBA',
      'fEdCbA',
    ]);
  });

  final invalidColors = <String?>[
    null,
    '',
    'ABC',
    '1234567',
    '#123456',
    ' 123456',
    '123456 ',
    '123456\n',
    'GG0000',
    'bad"color',
    '000000" fo:color="FF0000',
    '12<456',
    '１２３４５６',
    'auto',
  ];
  for (var index = 0; index < invalidColors.length; index++) {
    final color = invalidColors[index];
    test(
      'omits invalid paragraph colors without malformed XML: case $index',
      () {
        final paragraph = _paragraph('invalid', fill: color, border: color);
        final content = _export(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: [
                  _paragraph('valid', fill: '112233', border: '445566'),
                  paragraph,
                ],
              ),
            ],
          ),
        ).content;
        final exported = _body(content).childElements.toList();
        _expectDecoration(
          content,
          exported.first,
          fill: '#112233',
          border: '0.5pt solid #445566',
        );
        _expectDecoration(content, exported.last);
        expect(paragraph.properties.shadingFill, color);
        expect(paragraph.properties.borderColor, color);
      },
    );
  }

  test(
    'invalid colors cannot corrupt XML when their style is emitted first',
    () {
      for (final color in ['bad"color', '12<456', '123456\n']) {
        final content = _export(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: [
                  _paragraph('invalid first', fill: color, border: color),
                  _paragraph('valid next', fill: 'ABCDEF', border: '123456'),
                ],
              ),
            ],
          ),
        ).content;
        final paragraphs = _body(content).childElements.toList();
        _expectDecoration(content, paragraphs.first);
        _expectDecoration(
          content,
          paragraphs.last,
          fill: '#abcdef',
          border: '0.5pt solid #123456',
        );
      }
    },
  );

  test('header and footer paragraph decorations retain their own styles', () {
    final result = _export(
      WmlDocument(
        sections: [
          WmlSection(
            header: [
              _paragraph('header red', fill: 'FF0000'),
              _paragraph('header plain'),
            ],
            footer: [
              _paragraph('footer blue', fill: '0000FF'),
              _paragraph('footer border', border: '00FF00'),
            ],
            blocks: [_paragraph('body', fill: 'FFFFFF')],
          ),
        ],
      ),
    );
    final master = result.styles
        .firstChild('master-styles', namespaceUri: _officeNs)!
        .firstChild('master-page', namespaceUri: _styleNs)!;
    final header = master
        .firstChild('header', namespaceUri: _styleNs)!
        .childElements
        .toList();
    final footer = master
        .firstChild('footer', namespaceUri: _styleNs)!
        .childElements
        .toList();
    _expectDecoration(result.styles, header[0], fill: '#ff0000');
    _expectDecoration(result.styles, header[1]);
    _expectDecoration(result.styles, footer[0], fill: '#0000ff');
    _expectDecoration(result.styles, footer[1], border: '0.5pt solid #00ff00');
    _expectDecoration(
      result.content,
      _body(result.content).childElements.single,
      fill: '#ffffff',
    );
  });
}
