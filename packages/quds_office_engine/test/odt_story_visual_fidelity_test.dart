import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _drawNs = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _linkNs = 'http://www.w3.org/1999/xlink';
const _svgNs = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlVisual _picture({String title = 'Logo', double width = 36}) => WmlVisual(
  visual: OfficeVisual(
    kind: OfficeVisualKind.picture,
    title: title,
    imageBytes: _png,
    width: width,
    height: 18,
  ),
);

XmlElement _xml(OpcPackage package, String name) =>
    XmlDocument.parse(package.getPart('/$name.xml')!.readText()).root!;

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

String _text(XmlNode node) {
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
  return node.children.map(_text).join();
}

XmlElement _style(XmlElement root, XmlElement paragraph) {
  final name = paragraph.getAttribute('style-name', namespaceUri: _textNs);
  return root
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

String? _bodyMaster(XmlElement content, String text) {
  final paragraph = _elements(
    content.firstChild('body', namespaceUri: _officeNs)!,
    'p',
    _textNs,
  ).singleWhere((paragraph) => _text(paragraph) == text);
  return _style(
    content,
    paragraph,
  ).getAttribute('master-page-name', namespaceUri: _styleNs);
}

void main() {
  test(
    'standalone default header and footer pictures retain package media',
    () {
      final header = _picture(title: 'Header logo');
      final footer = _picture(title: 'Footer logo', width: 24);
      final section = WmlSection(
        blocks: [_picture(title: 'Body picture')],
        headerVisuals: [header],
        footerVisuals: [footer],
      );
      final document = WmlDocument(sections: [section]);
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(document),
      );
      final styles = _xml(package, 'styles');
      expect(_elements(styles, 'header', _styleNs), hasLength(1));
      expect(_elements(styles, 'footer', _styleNs), hasLength(1));
      final headerStory = _elements(styles, 'header', _styleNs).single;
      final footerStory = _elements(styles, 'footer', _styleNs).single;
      final headerFrame = _elements(headerStory, 'frame', _drawNs).single;
      final footerFrame = _elements(footerStory, 'frame', _drawNs).single;
      expect(
        headerFrame.getAttribute('name', namespaceUri: _drawNs),
        'Header logo',
      );
      expect(
        headerFrame.getAttribute('width', namespaceUri: _svgNs),
        '36.00pt',
      );
      expect(
        footerFrame.getAttribute('name', namespaceUri: _drawNs),
        'Footer logo',
      );
      expect(
        footerFrame.getAttribute('width', namespaceUri: _svgNs),
        '24.00pt',
      );
      expect(
        headerStory.childrenNamed('p', namespaceUri: _textNs),
        hasLength(1),
      );
      expect(
        footerStory.childrenNamed('p', namespaceUri: _textNs),
        hasLength(1),
      );
      final paths = [
        for (final root in [_xml(package, 'content'), styles])
          for (final image in _elements(root, 'image', _drawNs))
            image.getAttribute('href', namespaceUri: _linkNs)!,
      ];
      expect(paths, hasLength(3));
      expect(paths.toSet(), hasLength(3));
      final manifest = package.getPart('/META-INF/manifest.xml')!.readText();
      for (final path in paths) {
        expect(package.getPart('/$path')!.readBytes(), _png);
        expect(manifest, contains('manifest:full-path="$path"'));
      }
      final repeated = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(document),
      );
      expect(
        repeated.getPart('/styles.xml')!.readText(),
        package.getPart('/styles.xml')!.readText(),
      );
      expect(identical(section.headerVisuals.single, header), isTrue);
      expect(identical(section.footerVisuals.single, footer), isTrue);
      expect(section.header, isEmpty);
      expect(section.footer, isEmpty);
    },
  );

  test('DOCX default story pictures survive import followed by ODT export', () {
    final document = WordDeserializer().readBytes(
      File('test/fixtures/fidelity/story-media.docx').readAsBytesSync(),
    );
    final section = document.sections.single;
    expect(section.headerVisuals, hasLength(1));
    expect(section.footerVisuals, hasLength(1));
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final styles = _xml(package, 'styles');
    for (final story in [
      ('header', section.headerVisuals.single),
      ('footer', section.footerVisuals.single),
    ]) {
      expect(_elements(styles, story.$1, _styleNs), hasLength(1));
      final element = _elements(styles, story.$1, _styleNs).single;
      expect(_elements(element, 'image', _drawNs), hasLength(1));
      final image = _elements(element, 'image', _drawNs).single;
      final path = image.getAttribute('href', namespaceUri: _linkNs)!;
      expect(
        package.getPart('/$path')!.readBytes(),
        story.$2.visual.imageBytes,
      );
    }
  });

  test(
    'standalone story visual fallbacks preserve authored text and spacing',
    () {
      WmlVisual label(String title) => WmlVisual(
        visual: OfficeVisual(kind: OfficeVisualKind.chartColumn, title: title),
      );
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(
          WmlDocument(
            sections: [
              WmlSection(
                header: [_paragraph('Header')],
                footer: [_paragraph('Footer')],
                headerVisuals: [label(' Chart\tlabel  ')],
                footerVisuals: [label(' Foot\nlabel ')],
              ),
            ],
          ),
        ),
      );
      final styles = _xml(package, 'styles');
      final header = _elements(styles, 'header', _styleNs).single;
      final footer = _elements(styles, 'footer', _styleNs).single;
      expect(header.childrenNamed('p', namespaceUri: _textNs).map(_text), [
        'Header',
        ' Chart\tlabel  ',
      ]);
      expect(footer.childrenNamed('p', namespaceUri: _textNs).map(_text), [
        'Footer',
        ' Foot\nlabel ',
      ]);
    },
  );

  test('continuous masters compare standalone story picture geometry', () {
    final document = WmlDocument(
      sections: [
        for (var index = 0; index < 3; index++)
          WmlSection(
            blocks: [_paragraph('Body $index')],
            headerVisuals: [_picture(width: index == 2 ? 48 : 36)],
            footerVisuals: [_picture(title: 'Footer')],
            breakKind: WmlSectionBreakKind.continuous,
          ),
      ],
    );
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(document),
    );
    final content = _xml(package, 'content');
    expect(_bodyMaster(content, 'Body 1'), isNull);
    expect(_bodyMaster(content, 'Body 2'), 'mp2');
    expect(_elements(_xml(package, 'styles'), 'image', _drawNs), hasLength(6));
  });

  test(
    'continuous picture stories compare authored names despite collisions',
    () {
      const titles = [
        'Logo',
        'Logo',
        'Logo 2',
        'Logo 2',
        '',
        '',
        'Picture',
        'Picture',
      ];
      final document = WmlDocument(
        sections: [
          for (var index = 0; index < titles.length; index++)
            WmlSection(
              blocks: [_paragraph('Body $index')],
              headerVisuals: [_picture(title: titles[index])],
              breakKind: WmlSectionBreakKind.continuous,
            ),
        ],
      );
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(document),
      );
      final content = _xml(package, 'content');
      for (var index = 1; index < titles.length; index++) {
        expect(
          _bodyMaster(content, 'Body $index'),
          titles[index] == titles[index - 1] ? isNull : 'mp$index',
        );
      }
      final names = _elements(_xml(package, 'styles'), 'frame', _drawNs)
          .map((frame) => frame.getAttribute('name', namespaceUri: _drawNs))
          .toList();
      expect(names, hasLength(titles.length));
      expect(names.toSet(), hasLength(titles.length));
      expect(names, everyElement(isNotEmpty));
      expect(
        document.sections.map(
          (section) => section.headerVisuals.single.visual.title,
        ),
        titles,
      );
    },
  );

  for (final highlight in [false, true]) {
    test(
      'hex case in ${highlight ? 'highlight' : 'foreground'} cannot split a continuous story',
      () {
        const colors = ['ABCDEF', 'abcdef', '123456'];
        final properties = [
          for (final color in colors)
            WmlRunProps(
              color: highlight ? '000000' : color,
              highlight: highlight ? color : null,
            ),
        ];
        final document = WmlDocument(
          sections: [
            for (var index = 0; index < colors.length; index++)
              WmlSection(
                blocks: [_paragraph('Body $index')],
                header: [
                  WmlParagraph(
                    inlines: [
                      WmlRun(text: 'Header', properties: properties[index]),
                    ],
                  ),
                ],
                breakKind: WmlSectionBreakKind.continuous,
              ),
          ],
        );
        final package = OpcPackage.openBytes(
          OdtDocumentWriter.writeBytes(document),
        );
        final content = _xml(package, 'content');
        expect(_bodyMaster(content, 'Body 1'), isNull);
        expect(_bodyMaster(content, 'Body 2'), 'mp2');
        final styles = _xml(package, 'styles');
        final spans = _elements(styles, 'span', _textNs).toList();
        expect(spans, hasLength(colors.length));
        expect(
          spans[0].getAttribute('style-name', namespaceUri: _textNs),
          spans[1].getAttribute('style-name', namespaceUri: _textNs),
        );
        for (var index = 0; index < spans.length; index++) {
          expect(
            _style(styles, spans[index])
                .firstChild('text-properties', namespaceUri: _styleNs)!
                .getAttribute(
                  highlight ? 'background-color' : 'color',
                  namespaceUri: _foNs,
                ),
            '#${colors[index].toLowerCase()}',
          );
        }
        expect(
          properties.map((props) => highlight ? props.highlight : props.color),
          colors,
        );
      },
    );
  }
}
