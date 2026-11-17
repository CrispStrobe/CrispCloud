import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

XmlElement _content(WmlDocument document) => XmlDocument.parse(
  OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(document),
  ).getPart('/content.xml')!.readText(),
).root!;

WmlDocument _document(List<WmlParagraphProps> properties) => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        for (var index = 0; index < properties.length; index++)
          WmlParagraph(
            properties: properties[index],
            inlines: [WmlRun(text: 'Paragraph $index')],
          ),
      ],
    ),
  ],
);

List<XmlElement> _paragraphs(XmlElement content) => content
    .firstChild('body')!
    .firstChild('text')!
    .childElements
    .where((element) => element.localName == 'p' || element.localName == 'h')
    .toList();

XmlElement _style(XmlElement content, int index) {
  final name = _paragraphs(
    content,
  )[index].getAttribute('style-name', namespaceUri: _textNs);
  return content
      .firstChild('automatic-styles')!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (element) =>
            element.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

XmlElement _properties(XmlElement content, int index) =>
    _style(content, index).firstChild('paragraph-properties')!;

String? _fo(XmlElement properties, String name) =>
    properties.getAttribute(name, namespaceUri: _foNs);

String? _odfStyle(XmlElement properties, String name) =>
    properties.getAttribute(name, namespaceUri: _styleNs);

double? _lineHeightPercent(XmlElement properties) {
  final value = _fo(properties, 'line-height');
  if (value == null || !value.endsWith('%')) return null;
  return double.tryParse(value.substring(0, value.length - 1));
}

void main() {
  for (final rule in WmlLineSpacingRule.values) {
    test('preserves imported $rule line spacing units', () {
      final source = OpcPackage.create(OpcPackageKind.word);
      final sourceXml =
          '''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
<w:pPr><w:spacing w:line="360" w:lineRule="${rule.name}"/></w:pPr>
<w:r><w:t>Imported paragraph</w:t></w:r></w:p></w:body></w:document>''';
      source.getPart('/word/document.xml')!.writeText(sourceXml);
      final document = WordDeserializer().read(source);
      final props = document.paragraphs.single.properties;
      final original = WordSerializer().paragraphPropertiesXml(props);
      expect(props.lineSpacingRule, rule);
      expect(props.lineSpacing, rule == WmlLineSpacingRule.auto ? 1.5 : 18);

      final properties = _properties(_content(document), 0);
      switch (rule) {
        case WmlLineSpacingRule.auto:
          expect(_lineHeightPercent(properties), 150);
          expect(_odfStyle(properties, 'line-height-at-least'), isNull);
        case WmlLineSpacingRule.exact:
          expect(_fo(properties, 'line-height'), '18.00pt');
          expect(_odfStyle(properties, 'line-height-at-least'), isNull);
        case WmlLineSpacingRule.atLeast:
          expect(_odfStyle(properties, 'line-height-at-least'), '18.00pt');
          expect(_fo(properties, 'line-height'), isNull);
      }
      expect(WordSerializer().paragraphPropertiesXml(props), original);
      expect(source.getPart('/word/document.xml')!.readText(), sourceXml);
    });
  }

  test('spacing rules remain distinct while equivalent styles are reused', () {
    final properties = [
      for (final rule in WmlLineSpacingRule.values)
        WmlParagraphProps(lineSpacing: 2, lineSpacingRule: rule),
      WmlParagraphProps(
        lineSpacing: 2,
        lineSpacingRule: WmlLineSpacingRule.exact,
      ),
    ];
    final content = _content(_document(properties));
    final styleNames = [
      for (final paragraph in _paragraphs(content))
        paragraph.getAttribute('style-name', namespaceUri: _textNs),
    ];
    expect(styleNames.take(3).toSet(), hasLength(3));
    expect(styleNames[1], styleNames[3]);
    expect(_lineHeightPercent(_properties(content, 0)), 200);
    expect(_fo(_properties(content, 1), 'line-height'), '2.00pt');
    expect(
      _odfStyle(_properties(content, 2), 'line-height-at-least'),
      '2.00pt',
    );
  });

  test('retains fractional automatic line spacing', () {
    final content = _content(
      _document([WmlParagraphProps(lineSpacing: 1.125)]),
    );
    expect(_lineHeightPercent(_properties(content, 0)), 112.5);
  });

  test(
    'retains direction independently of physical alignment and style reuse',
    () {
      final properties = [
        for (final direction in <bool?>[true, false, null, true])
          WmlParagraphProps(rightToLeft: direction),
        WmlParagraphProps(
          rightToLeft: true,
          justification: WmlJustification.right,
        ),
      ];
      final content = _content(_document(properties));
      final paragraphs = _paragraphs(content);
      final names = [
        for (final paragraph in paragraphs)
          paragraph.getAttribute('style-name', namespaceUri: _textNs),
      ];
      expect(names.take(3).toSet(), hasLength(3));
      expect(names[0], names[3]);
      expect(_odfStyle(_properties(content, 0), 'writing-mode'), 'rl-tb');
      expect(_odfStyle(_properties(content, 1), 'writing-mode'), 'lr-tb');
      expect(_odfStyle(_properties(content, 2), 'writing-mode'), isNull);
      expect(
        _odfStyle(_properties(content, 0), 'writing-mode-automatic'),
        'false',
      );
      expect(
        _odfStyle(_properties(content, 1), 'writing-mode-automatic'),
        'false',
      );
      expect(_fo(_properties(content, 0), 'text-align'), 'left');
      expect(_fo(_properties(content, 4), 'text-align'), 'right');
      expect(properties.map((props) => props.rightToLeft), [
        true,
        false,
        null,
        true,
        true,
      ]);
    },
  );

  test(
    'retains explicitly authored heading alignment and paragraph spacing',
    () {
      final props = WmlParagraphProps(
        headingLevel: 2,
        justification: WmlJustification.center,
        spacingBefore: 12,
        spacingAfter: 0,
        lineSpacing: 24,
        lineSpacingRule: WmlLineSpacingRule.exact,
        rightToLeft: true,
        explicitJustification: true,
        explicitSpacingBefore: true,
        explicitSpacingAfter: true,
        explicitLineSpacing: true,
      );
      final before = WordSerializer().paragraphPropertiesXml(props);
      final content = _content(_document([props]));
      final paragraph = _paragraphs(content).single;
      final style = _style(content, 0);
      final properties = _properties(content, 0);
      expect(paragraph.localName, 'h');
      expect(
        paragraph.getAttribute('outline-level', namespaceUri: _textNs),
        '2',
      );
      expect(_odfStyle(style, 'parent-style-name'), 'Heading_20_2');
      expect(_fo(properties, 'text-align'), 'center');
      expect(_fo(properties, 'margin-top'), '12.00pt');
      expect(_fo(properties, 'margin-bottom'), '0.00pt');
      expect(_fo(properties, 'line-height'), '24.00pt');
      expect(_odfStyle(properties, 'writing-mode'), 'rl-tb');
      expect(WordSerializer().paragraphPropertiesXml(props), before);
    },
  );

  test('zero body spacing overrides the generated default style', () {
    final content = _content(
      _document([
        WmlParagraphProps(spacingBefore: 0, spacingAfter: 0),
        WmlParagraphProps(spacingBefore: 0, spacingAfter: 8),
      ]),
    );
    expect(_fo(_properties(content, 0), 'margin-top'), '0.00pt');
    expect(_fo(_properties(content, 0), 'margin-bottom'), '0.00pt');
    expect(_fo(_properties(content, 1), 'margin-bottom'), '8.00pt');
  });

  test('paragraph style reuse preserves heading and body distinction', () {
    final content = _content(
      _document([
        WmlParagraphProps(),
        WmlParagraphProps(headingLevel: 0),
        WmlParagraphProps(headingLevel: 1),
        WmlParagraphProps(headingLevel: 1),
      ]),
    );
    expect(_odfStyle(_style(content, 0), 'parent-style-name'), 'Standard');
    expect(_odfStyle(_style(content, 1), 'parent-style-name'), 'Heading_20_1');
    expect(_odfStyle(_style(content, 2), 'parent-style-name'), 'Heading_20_1');
    expect(
      _odfStyle(_style(content, 2), 'name'),
      _odfStyle(_style(content, 3), 'name'),
    );
  });

  for (final rule in WmlLineSpacingRule.values) {
    test('ignores nonfinite and unrepresentable $rule paragraph lengths', () {
      for (final invalid in [
        double.nan,
        double.infinity,
        -double.infinity,
        1e308,
      ]) {
        final props = WmlParagraphProps(
          lineSpacing: invalid,
          lineSpacingRule: rule,
          spacingBefore: invalid,
          spacingAfter: invalid,
          indent: WmlIndent(left: invalid, right: invalid, firstLine: invalid),
        );
        final content = _content(_document([props]));
        final properties = _properties(content, 0);
        expect(_fo(properties, 'line-height'), isNull);
        expect(_odfStyle(properties, 'line-height-at-least'), isNull);
        expect(_fo(properties, 'margin-top'), isNull);
        expect(_fo(properties, 'margin-bottom'), isNull);
        expect(_fo(properties, 'margin-left'), isNull);
        expect(_fo(properties, 'margin-right'), isNull);
        expect(_fo(properties, 'text-indent'), isNull);
        expect(
          props.lineSpacing.isNaN
              ? invalid.isNaN
              : props.lineSpacing == invalid,
          isTrue,
        );
      }
    });
  }

  test('retains signed finite indentation and hanging-indent precedence', () {
    final content = _content(
      _document([
        WmlParagraphProps(
          indent: const WmlIndent(
            left: -12,
            right: 4,
            firstLine: 10,
            hanging: 6,
          ),
        ),
      ]),
    );
    final properties = _properties(content, 0);
    expect(_fo(properties, 'margin-left'), '-12.00pt');
    expect(_fo(properties, 'margin-right'), '4.00pt');
    expect(_fo(properties, 'text-indent'), '-6.00pt');
  });
}
