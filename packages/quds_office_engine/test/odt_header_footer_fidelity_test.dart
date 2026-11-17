import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _linkNs = 'http://www.w3.org/1999/xlink';

Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
  if (root.localName == name) yield root;
  for (final child in root.childElements) {
    yield* _elements(child, name);
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

OpcPackage _export(WmlSection section, {String? fixture}) {
  final bytes = OdtDocumentWriter.writeBytes(WmlDocument(sections: [section]));
  final output = Platform.environment['QUDS_ODF_FIXTURE_OUTPUT'];
  if (fixture != null && output != null && output.isNotEmpty) {
    Directory(output).createSync(recursive: true);
    File('$output/$fixture').writeAsBytesSync(bytes);
  }
  return OpcPackage.openBytes(bytes);
}

XmlElement _xml(OpcPackage package, String part) =>
    XmlDocument.parse(package.getPart('/$part')!.readText()).root!;

XmlElement _properties(XmlElement root, XmlElement owner, String family) {
  final name = owner.getAttribute('style-name', namespaceUri: _textNs);
  expect(name, isNotNull);
  final styles = root.firstChild('automatic-styles')!.childrenNamed('style');
  final matches = styles.where(
    (style) =>
        style.getAttribute('name', namespaceUri: _styleNs) == name &&
        style.getAttribute('family', namespaceUri: _styleNs) == family,
  );
  expect(
    matches,
    hasLength(1),
    reason: 'Style $name must exist in this XML part',
  );
  return matches.single.firstChild('$family-properties')!;
}

WmlParagraph _paragraph(String text, {String color = '', bool bold = false}) =>
    WmlParagraph(
      inlines: [
        WmlRun(
          text: text,
          properties: WmlRunProps(color: color, bold: bold),
        ),
      ],
    );

void main() {
  test('explicit inline breaks survive in headers and footers', () {
    WmlParagraph paragraph(String first, String last) => WmlParagraph(
      inlines: [
        WmlRun(text: first),
        WmlBreak(WmlBreakType.textWrapping),
        WmlRun(text: last),
      ],
    );
    final package = _export(
      WmlSection(
        header: [paragraph(' First\tline ', 'Second ')],
        footer: [paragraph('Footer', 'Tail')],
        blocks: [_paragraph('Body')],
      ),
      fixture: 'word-header-breaks.odt',
    );
    final root = _xml(package, 'styles.xml');
    expect(_text(_elements(root, 'header').single), ' First\tline \nSecond ');
    expect(_text(_elements(root, 'footer').single), 'Footer\nTail');
    expect(_elements(root, 'line-break'), hasLength(2));
  });

  test('header and body run styles resolve in their own XML part', () {
    final package = _export(
      WmlSection(
        header: [_paragraph('Header blue', color: '1234AB', bold: true)],
        footer: [_paragraph('Footer green', color: '118833')],
        blocks: [_paragraph('Body red', color: 'BB2211')],
      ),
      fixture: 'word-header-styles.odt',
    );
    final content = _xml(package, 'content.xml');
    final styles = _xml(package, 'styles.xml');
    final body = _elements(content, 'span').single;
    final header = _elements(_elements(styles, 'header').single, 'span').single;
    final footer = _elements(_elements(styles, 'footer').single, 'span').single;
    expect(
      _properties(
        content,
        body,
        'text',
      ).getAttribute('color', namespaceUri: _foNs),
      '#bb2211',
    );
    expect(
      _properties(
        styles,
        header,
        'text',
      ).getAttribute('color', namespaceUri: _foNs),
      '#1234ab',
    );
    expect(
      _properties(
        styles,
        header,
        'text',
      ).getAttribute('font-weight', namespaceUri: _foNs),
      'bold',
    );
    expect(
      _properties(
        styles,
        footer,
        'text',
      ).getAttribute('color', namespaceUri: _foNs),
      '#118833',
    );
  });

  test('equivalent header and footer styles are reused once', () {
    final styles = _xml(
      _export(
        WmlSection(
          header: [_paragraph('Header', color: '123456')],
          footer: [_paragraph('Footer', color: '123456')],
        ),
      ),
      'styles.xml',
    );
    final spans = _elements(styles, 'span').toList();
    expect(spans, hasLength(2));
    expect(
      spans[0].getAttribute('style-name'),
      spans[1].getAttribute('style-name'),
    );
    _properties(styles, spans[0], 'text');
    final names = styles
        .firstChild('automatic-styles')!
        .childrenNamed('style')
        .map(
          (style) =>
              '${style.getAttribute('family')}|${style.getAttribute('name')}',
        )
        .toList();
    expect(names.toSet(), hasLength(names.length));
  });

  test('header heading properties and explicit direction are retained', () {
    final styles = _xml(
      _export(
        WmlSection(
          header: [
            WmlParagraph(
              properties: WmlParagraphProps(
                headingLevel: 2,
                justification: WmlJustification.right,
                rightToLeft: true,
                lineSpacingRule: WmlLineSpacingRule.exact,
                lineSpacing: 18,
                spacingAfter: 0,
              ),
              inlines: [WmlRun(text: 'عنوان')],
            ),
          ],
        ),
      ),
      'styles.xml',
    );
    final heading = _elements(_elements(styles, 'header').single, 'h').toList();
    expect(heading, hasLength(1));
    expect(heading.single.getAttribute('outline-level'), '2');
    final properties = _properties(styles, heading.single, 'paragraph');
    expect(
      properties.getAttribute('writing-mode', namespaceUri: _styleNs),
      'rl-tb',
    );
    expect(properties.getAttribute('text-align', namespaceUri: _foNs), 'right');
    expect(
      properties.getAttribute('line-height', namespaceUri: _foNs),
      '18.00pt',
    );
    expect(
      properties.getAttribute('margin-bottom', namespaceUri: _foNs),
      '0.00pt',
    );
  });

  test(
    'header hyperlinks and inline visual fallbacks retain their boundaries',
    () {
      final styles = _xml(
        _export(
          WmlSection(
            header: [
              WmlParagraph(
                inlines: [
                  WmlRun(
                    text: ' A ',
                    hyperlink: WmlHyperlink(
                      url: 'https://example.test/?a=1&b=2',
                    ),
                  ),
                  WmlRun(
                    inlineVisual: WmlVisual(
                      visual: OfficeVisual(
                        kind: OfficeVisualKind.chartColumn,
                        title: ' Chart\tlabel ',
                      ),
                    ),
                  ),
                  WmlRun(text: 'Z'),
                ],
              ),
            ],
          ),
        ),
        'styles.xml',
      );
      final header = _elements(styles, 'header').single;
      final links = _elements(header, 'a').toList();
      expect(links, hasLength(1));
      expect(
        links.single.getAttribute('href', namespaceUri: _linkNs),
        'https://example.test/?a=1&b=2',
      );
      expect(_elements(header, 'p'), hasLength(1));
      expect(_text(header), ' A  Chart\tlabel Z');
    },
  );

  test(
    'header cached fields stay visible while hidden instructions stay absent',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: 'PRIVATE_FIELD_INSTRUCTION',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'Cached', properties: WmlRunProps(italic: true)),
          WmlBreak(WmlBreakType.textWrapping),
          WmlRun(text: 'result'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      );
      final package = _export(WmlSection(header: [paragraph]));
      final styles = _xml(package, 'styles.xml');
      final header = _elements(styles, 'header').single;
      expect(_text(header), 'Cached\nresult');
      expect(
        package.getPart('/styles.xml')!.readText(),
        isNot(contains('PRIVATE_FIELD_INSTRUCTION')),
      );
      final firstSpan = _elements(header, 'span').first;
      expect(
        _properties(
          styles,
          firstSpan,
          'text',
        ).getAttribute('font-style', namespaceUri: _foNs),
        'italic',
      );
      expect(
        paragraph.inlines.whereType<WmlFieldBoundary>().map(
          (field) => field.text,
        ),
        ['', 'PRIVATE_FIELD_INSTRUCTION', '', ''],
      );
    },
  );

  test('header footer and body pictures share collision-free package media', () {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
    );
    WmlParagraph picture() => WmlParagraph(
      inlines: [
        WmlRun(
          inlineVisual: WmlVisual(
            visual: OfficeVisual(
              kind: OfficeVisualKind.picture,
              imageBytes: png,
              width: 12,
              height: 12,
            ),
          ),
        ),
      ],
    );
    final package = _export(
      WmlSection(header: [picture()], footer: [picture()], blocks: [picture()]),
      fixture: 'word-header-pictures.odt',
    );
    final hrefs = [
      for (final part in ['content.xml', 'styles.xml'])
        for (final image in _elements(_xml(package, part), 'image'))
          image.getAttribute('href', namespaceUri: _linkNs)!,
    ];
    for (final part in ['content.xml', 'styles.xml']) {
      for (final image in _elements(_xml(package, part), 'image')) {
        expect(image.getAttribute('type', namespaceUri: _linkNs), 'simple');
      }
    }
    expect(hrefs, hasLength(3));
    expect(hrefs.toSet(), hasLength(3));
    for (final path in hrefs) {
      expect(package.getPart('/$path')?.readBytes(), png);
      expect(
        package.getPart('/META-INF/manifest.xml')!.readText(),
        contains('manifest:full-path="$path"'),
      );
    }
  });

  test('exports neither header nor footer when both are absent', () {
    final styles = _xml(
      _export(WmlSection(blocks: [_paragraph('Body')])),
      'styles.xml',
    );
    expect(_elements(styles, 'header'), isEmpty);
    expect(_elements(styles, 'footer'), isEmpty);
    expect(
      styles.firstChild('automatic-styles')!.childrenNamed('style'),
      isEmpty,
    );
  });

  test('repeated export preserves source story objects and formatting', () {
    final paragraph = _paragraph('Styled', color: '102030', bold: true);
    final section = WmlSection(
      header: [paragraph],
      footer: [paragraph],
      blocks: [_paragraph('Body')],
    );
    final run = paragraph.inlines.single as WmlRun;
    final before = WordSerializer().runPropertiesXml(run.properties);
    final first = _export(section);
    final second = _export(section);
    for (final part in [
      '/content.xml',
      '/styles.xml',
      '/META-INF/manifest.xml',
    ]) {
      expect(second.getPart(part)!.readText(), first.getPart(part)!.readText());
    }
    expect(identical(section.header.single, paragraph), isTrue);
    expect(identical(section.footer.single, paragraph), isTrue);
    expect(identical(paragraph.inlines.single, run), isTrue);
    expect(WordSerializer().runPropertiesXml(run.properties), before);
  });
}
