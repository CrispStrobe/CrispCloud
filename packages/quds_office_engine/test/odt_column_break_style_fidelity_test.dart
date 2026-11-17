import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

XmlElement _export(WmlDocument document) {
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  return XmlDocument.parse(package.getPart('/content.xml')!.readText()).root!;
}

XmlElement _body(XmlElement root) => root
    .firstChild('body', namespaceUri: _office)!
    .firstChild('text', namespaceUri: _office)!;

XmlElement _properties(XmlElement root, XmlElement node, String family) => root
    .firstChild('automatic-styles', namespaceUri: _office)!
    .childrenNamed('style', namespaceUri: _style)
    .singleWhere(
      (style) =>
          style.getAttribute('name', namespaceUri: _style) ==
          node.getAttribute('style-name', namespaceUri: _text),
    )
    .firstChild('$family-properties', namespaceUri: _style)!;

({XmlElement root, List<XmlElement> paragraphs}) _paragraphs(
  List<WmlParagraphProps> properties,
) {
  final root = _export(
    WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            // The section boundary has its own style. Exercise the ordinary
            // paragraph cache where the two omitted booleans caused a loss.
            WmlParagraph(inlines: [WmlRun(text: 'Section start')]),
            for (var index = 0; index < properties.length; index++)
              WmlParagraph(
                properties: properties[index],
                inlines: [WmlRun(text: 'Paragraph $index')],
              ),
          ],
        ),
      ],
    ),
  );
  final paragraphs = _body(
    root,
  ).childrenNamed('p', namespaceUri: _text).skip(1).toList();
  expect(paragraphs, hasLength(properties.length));
  return (root: root, paragraphs: paragraphs);
}

WmlSection _section(int columns, double gap, String text) => WmlSection(
  columnCount: columns,
  columnSpace: gap,
  blocks: [
    WmlParagraph(inlines: [WmlRun(text: text)]),
  ],
);

XmlElement _columns(XmlElement root, XmlElement section) {
  final properties = _properties(root, section, 'section');
  // ODF 1.3 sections 17.11/17.12 and 19.232/19.233 put these attributes on
  // a style:columns child, not directly on style:section-properties.
  expect(properties.getAttribute('column-count', namespaceUri: _fo), isNull);
  expect(properties.getAttribute('column-gap', namespaceUri: _fo), isNull);
  return properties.childrenNamed('columns', namespaceUri: _style).single;
}

void main() {
  for (final flag in ['column break', 'keep together']) {
    for (final enabledFirst in [false, true]) {
      test('$flag stays with its paragraph: enabledFirst=$enabledFirst', () {
        final values = [enabledFirst, !enabledFirst, enabledFirst];
        final properties = [
          for (final enabled in values)
            WmlParagraphProps(
              columnBreakBefore: flag == 'column break' && enabled,
              keepTogether: flag == 'keep together' && enabled,
              tabs: const [WmlTabStop(position: 72)],
            ),
        ];
        final output = _paragraphs(properties);
        for (var index = 0; index < values.length; index++) {
          final actual = _properties(
            output.root,
            output.paragraphs[index],
            'paragraph',
          );
          expect(
            actual.getAttribute('break-before', namespaceUri: _fo),
            properties[index].columnBreakBefore ? 'column' : null,
          );
          expect(
            actual.getAttribute('keep-together', namespaceUri: _fo),
            properties[index].keepTogether ? 'always' : null,
          );
          expect(
            actual
                .firstChild('tab-stops', namespaceUri: _style)!
                .childrenNamed('tab-stop', namespaceUri: _style)
                .single
                .getAttribute('position', namespaceUri: _style),
            '72.00pt',
          );
        }
        expect(
          output.paragraphs.first.getAttribute(
            'style-name',
            namespaceUri: _text,
          ),
          output.paragraphs.last.getAttribute(
            'style-name',
            namespaceUri: _text,
          ),
        );
        expect(
          properties.map(
            (props) => flag == 'column break'
                ? props.columnBreakBefore
                : props.keepTogether,
          ),
          values,
        );
      });
    }
  }

  test('all break and keep combinations retain page-break precedence', () {
    final properties = [
      for (final page in [false, true])
        for (final column in [false, true])
          for (final keep in [false, true])
            WmlParagraphProps(
              pageBreakBefore: page,
              columnBreakBefore: column,
              keepTogether: keep,
            ),
    ];
    final output = _paragraphs(properties);
    for (var index = 0; index < properties.length; index++) {
      final expected = properties[index];
      final actual = _properties(
        output.root,
        output.paragraphs[index],
        'paragraph',
      );
      expect(
        actual.getAttribute('break-before', namespaceUri: _fo),
        expected.pageBreakBefore
            ? 'page'
            : expected.columnBreakBefore
            ? 'column'
            : null,
      );
      expect(
        actual.getAttribute('keep-together', namespaceUri: _fo),
        expected.keepTogether ? 'always' : null,
      );
    }
  });

  test('section boundaries retain page breaks with column and keep flags', () {
    final root = _export(
      WmlDocument(
        sections: [
          for (var index = 0; index < 2; index++)
            WmlSection(
              blocks: [
                WmlParagraph(
                  properties: WmlParagraphProps(
                    columnBreakBefore: true,
                    keepTogether: true,
                  ),
                  inlines: [WmlRun(text: 'Section $index')],
                ),
              ],
            ),
        ],
      ),
    );
    final paragraphs = _body(root).childrenNamed('p', namespaceUri: _text);
    expect(paragraphs, hasLength(2));
    expect(
      paragraphs.map(
        (paragraph) => _properties(
          root,
          paragraph,
          'paragraph',
        ).getAttribute('break-before', namespaceUri: _fo),
      ),
      ['column', 'page'],
    );
    for (final paragraph in paragraphs) {
      expect(
        _properties(
          root,
          paragraph,
          'paragraph',
        ).getAttribute('keep-together', namespaceUri: _fo),
        'always',
      );
    }
  });

  test('section column styles use the ODF child and preserve each owner', () {
    final sections = [
      _section(2, 18, 'First columns'),
      _section(3, 24, 'Second columns'),
      _section(2, 18, 'Repeated columns'),
    ];
    final root = _export(WmlDocument(sections: sections));
    final output = _body(
      root,
    ).childrenNamed('section', namespaceUri: _text).toList();
    expect(output, hasLength(sections.length));
    for (var index = 0; index < output.length; index++) {
      final columns = _columns(root, output[index]);
      expect(
        columns.getAttribute('column-count', namespaceUri: _fo),
        '${sections[index].columnCount}',
      );
      expect(
        columns.getAttribute('column-gap', namespaceUri: _fo),
        '${sections[index].columnSpace.toStringAsFixed(2)}pt',
      );
      expect(
        output[index].getAttribute('name', namespaceUri: _text),
        'Section$index',
      );
      expect(
        output[index].text,
        sections[index].blocks.whereType<WmlParagraph>().single.text,
      );
    }
    expect(
      output.first.getAttribute('style-name', namespaceUri: _text),
      output.last.getAttribute('style-name', namespaceUri: _text),
    );
    expect(
      sections.map((section) => (section.columnCount, section.columnSpace)),
      [(2, 18), (3, 24), (2, 18)],
    );
  });

  for (final (label, gap) in <(String, double)>[
    ('NaN', double.nan),
    ('positive infinity', double.infinity),
    ('negative infinity', double.negativeInfinity),
    ('exponent', 1e21),
  ]) {
    test('unrepresentable $label gap omits only that attribute', () {
      final section = _section(2, gap, 'Visible columns');
      final root = _export(WmlDocument(sections: [section]));
      final output = _body(
        root,
      ).childrenNamed('section', namespaceUri: _text).single;
      final columns = _columns(root, output);
      expect(columns.getAttribute('column-count', namespaceUri: _fo), '2');
      expect(columns.getAttribute('column-gap', namespaceUri: _fo), isNull);
      expect(output.text, 'Visible columns');
      expect(
        section.columnSpace.isNaN ? gap.isNaN : section.columnSpace == gap,
        isTrue,
      );
    });
  }

  test(
    'finite gaps retain signed lengths and canonical precision in styles',
    () {
      final sections = [
        _section(2, 18.001, 'Rounded first'),
        _section(2, 18.004, 'Rounded second'),
        _section(2, -0.0, 'Negative zero'),
        _section(2, 0, 'Zero'),
        _section(2, -6.25, 'Signed length'),
      ];
      final root = _export(WmlDocument(sections: sections));
      final output = _body(
        root,
      ).childrenNamed('section', namespaceUri: _text).toList();
      expect(
        output
            .map(
              (section) => _columns(
                root,
                section,
              ).getAttribute('column-gap', namespaceUri: _fo),
            )
            .toList(),
        ['18.00pt', '18.00pt', '0.00pt', '0.00pt', '-6.25pt'],
      );
      expect(
        output[0].getAttribute('style-name', namespaceUri: _text),
        output[1].getAttribute('style-name', namespaceUri: _text),
      );
      expect(
        output[2].getAttribute('style-name', namespaceUri: _text),
        output[3].getAttribute('style-name', namespaceUri: _text),
      );
      expect(sections[2].columnSpace.isNegative, isTrue);
      expect(sections[4].columnSpace, -6.25);
    },
  );
}
