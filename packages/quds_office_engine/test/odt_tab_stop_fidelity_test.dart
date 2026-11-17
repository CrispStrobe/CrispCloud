import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

typedef _ParagraphStyle = ({String name, XmlElement properties});

List<_ParagraphStyle> _styles(List<WmlParagraphProps> properties) {
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          // A section-leading paragraph owns a unique boundary style. Exercise
          // ordinary paragraphs, whose style deduplication caused the loss.
          WmlParagraph(inlines: [WmlRun(text: 'Leading paragraph')]),
          for (var index = 0; index < properties.length; index++)
            WmlParagraph(
              properties: properties[index],
              inlines: [WmlRun(text: 'Paragraph $index')],
            ),
        ],
      ),
    ],
  );
  final package = OpcPackage.openBytes(OdtDocumentWriter.writeBytes(document));
  final content = XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!;
  final automaticStyles = content.firstChild(
    'automatic-styles',
    namespaceUri: _officeNs,
  )!;
  final paragraphs = content
      .firstChild('body', namespaceUri: _officeNs)!
      .firstChild('text', namespaceUri: _officeNs)!
      .childrenNamed('p', namespaceUri: _textNs)
      .skip(1)
      .toList();
  expect(paragraphs, hasLength(properties.length));
  return [
    for (final paragraph in paragraphs)
      (
        name: paragraph.getAttribute('style-name', namespaceUri: _textNs)!,
        properties: automaticStyles
            .childrenNamed('style', namespaceUri: _styleNs)
            .singleWhere(
              (style) =>
                  style.getAttribute('name', namespaceUri: _styleNs) ==
                  paragraph.getAttribute('style-name', namespaceUri: _textNs),
            )
            .firstChild('paragraph-properties', namespaceUri: _styleNs)!,
      ),
  ];
}

List<Map<String, String?>> _tabs(_ParagraphStyle style) => [
  for (final stop
      in style.properties
              .firstChild('tab-stops', namespaceUri: _styleNs)
              ?.childrenNamed('tab-stop', namespaceUri: _styleNs) ??
          const <XmlElement>[])
    {
      'position': stop.getAttribute('position', namespaceUri: _styleNs),
      'type': stop.getAttribute('type', namespaceUri: _styleNs),
      'char': stop.getAttribute('char', namespaceUri: _styleNs),
      'leader': stop.getAttribute('leader-style', namespaceUri: _styleNs),
    },
];

void main() {
  test('ordinary paragraphs retain different tab stop positions', () {
    final styles = _styles([
      WmlParagraphProps(tabs: const [WmlTabStop(position: 72)]),
      WmlParagraphProps(tabs: const [WmlTabStop(position: 144)]),
    ]);
    expect(_tabs(styles[0]).single['position'], '72.00pt');
    expect(_tabs(styles[1]).single['position'], '144.00pt');
    expect(styles[0].name, isNot(styles[1].name));
  });

  for (final plainFirst in [false, true]) {
    test(
      'tabbed and plain paragraphs stay independent: plainFirst=$plainFirst',
      () {
        final plain = WmlParagraphProps();
        final tabbed = WmlParagraphProps(
          tabs: const [WmlTabStop(position: 72)],
        );
        final styles = _styles(plainFirst ? [plain, tabbed] : [tabbed, plain]);
        final plainStyle = styles[plainFirst ? 0 : 1];
        final tabbedStyle = styles[plainFirst ? 1 : 0];
        expect(_tabs(plainStyle), isEmpty);
        expect(_tabs(tabbedStyle).single['position'], '72.00pt');
        expect(plainStyle.name, isNot(tabbedStyle.name));
      },
    );
  }

  test('tab alignment and leader stay with their owning paragraph', () {
    final styles = _styles([
      WmlParagraphProps(tabs: const [WmlTabStop(position: 90)]),
      WmlParagraphProps(
        tabs: const [
          WmlTabStop(
            position: 90,
            alignment: WmlTabAlignment.center,
            leader: WmlTabLeader.dot,
          ),
        ],
      ),
      WmlParagraphProps(
        tabs: const [
          WmlTabStop(
            position: 90,
            alignment: WmlTabAlignment.right,
            leader: WmlTabLeader.hyphen,
          ),
        ],
      ),
      WmlParagraphProps(
        tabs: const [
          WmlTabStop(
            position: 90,
            alignment: WmlTabAlignment.decimal,
            leader: WmlTabLeader.underscore,
          ),
        ],
      ),
    ]);
    expect(styles.map((style) => _tabs(style).single), [
      {'position': '90.00pt', 'type': 'left', 'char': null, 'leader': null},
      {
        'position': '90.00pt',
        'type': 'center',
        'char': null,
        'leader': 'dotted',
      },
      {'position': '90.00pt', 'type': 'right', 'char': null, 'leader': 'solid'},
      {'position': '90.00pt', 'type': 'char', 'char': '.', 'leader': 'solid'},
    ]);
    expect(styles.map((style) => style.name).toSet(), hasLength(4));
  });

  test(
    'equivalent serialized tab stops share a style without changing the model',
    () {
      final properties = [
        WmlParagraphProps(
          tabs: const [
            WmlTabStop(position: 72.001, leader: WmlTabLeader.hyphen),
          ],
        ),
        WmlParagraphProps(
          tabs: const [
            WmlTabStop(position: 72.004, leader: WmlTabLeader.hyphen),
          ],
        ),
        WmlParagraphProps(
          tabs: const [
            WmlTabStop(position: 72.004, leader: WmlTabLeader.underscore),
          ],
        ),
      ];
      final styles = _styles(properties);
      expect(styles[0].name, styles[1].name);
      // Both solid leaders retain their authored character in the integrated
      // writer, so only matching characters can share their serialized style.
      expect(styles[1].name, isNot(styles[2].name));
      expect(
        [
          for (final style in styles)
            style.properties
                .firstChild('tab-stops', namespaceUri: _styleNs)!
                .childrenNamed('tab-stop', namespaceUri: _styleNs)
                .single
                .getAttribute('leader-text', namespaceUri: _styleNs),
        ],
        ['-', '-', '_'],
      );
      for (final style in styles) {
        expect(_tabs(style), [
          {
            'position': '72.00pt',
            'type': 'left',
            'char': null,
            'leader': 'solid',
          },
        ]);
      }
      expect(properties.map((props) => props.tabs.single.position), [
        72.001,
        72.004,
        72.004,
      ]);
      expect(properties.map((props) => props.tabs.single.leader), [
        WmlTabLeader.hyphen,
        WmlTabLeader.hyphen,
        WmlTabLeader.underscore,
      ]);
    },
  );

  test(
    'tabbed paragraph styles still distinguish shading and border colors',
    () {
      final styles = _styles([
        WmlParagraphProps(
          tabs: const [WmlTabStop(position: 72)],
          shadingFill: 'ABCDEF',
          borderColor: '123456',
        ),
        WmlParagraphProps(
          tabs: const [WmlTabStop(position: 72)],
          shadingFill: 'abcdef',
          borderColor: '123456',
        ),
        WmlParagraphProps(
          tabs: const [WmlTabStop(position: 72)],
          shadingFill: '112233',
          borderColor: '445566',
        ),
      ]);
      expect(styles[0].name, styles[1].name);
      expect(styles[0].name, isNot(styles[2].name));
      expect(
        styles[0].properties.getAttribute(
          'background-color',
          namespaceUri: _foNs,
        ),
        '#abcdef',
      );
      expect(
        styles[2].properties.getAttribute(
          'background-color',
          namespaceUri: _foNs,
        ),
        '#112233',
      );
      expect(
        styles[2].properties.getAttribute('border', namespaceUri: _foNs),
        '0.5pt solid #445566',
      );
      for (final style in styles) {
        expect(_tabs(style).single['position'], '72.00pt');
      }
    },
  );

  test(
    'unrepresentable stops cannot inherit valid stops or create malformed lengths',
    () {
      final styles = _styles([
        WmlParagraphProps(tabs: const [WmlTabStop(position: 72)]),
        WmlParagraphProps(
          tabs: const [
            WmlTabStop(position: double.nan),
            WmlTabStop(position: double.infinity),
            WmlTabStop(position: double.negativeInfinity),
            WmlTabStop(position: 1e21),
          ],
        ),
        WmlParagraphProps(),
        WmlParagraphProps(tabs: const [WmlTabStop(position: 72.001)]),
      ]);
      expect(_tabs(styles[0]).single['position'], '72.00pt');
      expect(_tabs(styles[1]), isEmpty);
      expect(_tabs(styles[2]), isEmpty);
      expect(styles[1].name, styles[2].name);
      expect(styles[0].name, styles[3].name);
      expect(styles[0].name, isNot(styles[1].name));
    },
  );

  test('different authored tab sequences retain every stop in order', () {
    final styles = _styles([
      WmlParagraphProps(
        tabs: const [WmlTabStop(position: 72), WmlTabStop(position: 144)],
      ),
      WmlParagraphProps(tabs: const [WmlTabStop(position: 72)]),
      WmlParagraphProps(
        tabs: const [WmlTabStop(position: 144), WmlTabStop(position: 72)],
      ),
    ]);
    expect(_tabs(styles[0]).map((tab) => tab['position']), [
      '72.00pt',
      '144.00pt',
    ]);
    expect(_tabs(styles[1]).map((tab) => tab['position']), ['72.00pt']);
    expect(_tabs(styles[2]).map((tab) => tab['position']), [
      '144.00pt',
      '72.00pt',
    ]);
    expect(styles.map((style) => style.name).toSet(), hasLength(3));
  });
}
