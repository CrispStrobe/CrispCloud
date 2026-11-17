import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

WmlParagraph _paragraph(String text, List<WmlTabStop> tabs) => WmlParagraph(
  properties: WmlParagraphProps(tabs: tabs),
  inlines: [WmlRun(text: text)],
);

({XmlElement root, List<XmlElement> paragraphs}) _export(
  List<WmlParagraph> paragraphs,
) {
  final package = OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(
      WmlDocument(
        sections: [
          WmlSection(blocks: [_paragraph('Section start', []), ...paragraphs]),
        ],
      ),
    ),
  );
  final root = XmlDocument.parse(
    package.getPart('/content.xml')!.readText(),
  ).root!;
  return (
    root: root,
    paragraphs: root
        .firstChild('body', namespaceUri: _office)!
        .firstChild('text', namespaceUri: _office)!
        .childrenNamed('p', namespaceUri: _text)
        .skip(1)
        .toList(),
  );
}

List<List<String?>> _tabs(XmlElement root, XmlElement paragraph) {
  final name = paragraph.getAttribute('style-name', namespaceUri: _text);
  final properties = root
      .firstChild('automatic-styles', namespaceUri: _office)!
      .childrenNamed('style', namespaceUri: _style)
      .singleWhere(
        (element) => element.getAttribute('name', namespaceUri: _style) == name,
      )
      .firstChild('paragraph-properties', namespaceUri: _style)!;
  final stops = properties.firstChild('tab-stops', namespaceUri: _style);
  return [
    if (stops != null)
      for (final tab in stops.childrenNamed('tab-stop', namespaceUri: _style))
        [
          tab.getAttribute('position', namespaceUri: _style),
          tab.getAttribute('type', namespaceUri: _style),
          tab.getAttribute('char', namespaceUri: _style),
          tab.getAttribute('leader-style', namespaceUri: _style),
        ],
  ];
}

void main() {
  test(
    'neighboring paragraphs retain each tab position, alignment and leader',
    () {
      final result = _export([
        _paragraph('left 72', const [WmlTabStop(position: 72)]),
        _paragraph('left 144', const [WmlTabStop(position: 144)]),
        _paragraph('center 72', const [
          WmlTabStop(position: 72, alignment: WmlTabAlignment.center),
        ]),
        _paragraph('right dotted 72', const [
          WmlTabStop(
            position: 72,
            alignment: WmlTabAlignment.right,
            leader: WmlTabLeader.dot,
          ),
        ]),
        _paragraph('right plain 72', const [
          WmlTabStop(position: 72, alignment: WmlTabAlignment.right),
        ]),
        _paragraph('decimal 72', const [
          WmlTabStop(position: 72, alignment: WmlTabAlignment.decimal),
        ]),
      ]);
      expect(result.paragraphs.map((p) => _tabs(result.root, p)), [
        [
          ['72.00pt', 'left', null, null],
        ],
        [
          ['144.00pt', 'left', null, null],
        ],
        [
          ['72.00pt', 'center', null, null],
        ],
        [
          ['72.00pt', 'right', null, 'dotted'],
        ],
        [
          ['72.00pt', 'right', null, null],
        ],
        [
          ['72.00pt', 'char', '.', null],
        ],
      ]);
    },
  );

  for (final tabbedFirst in [false, true]) {
    test(
      'plain and tabbed paragraphs stay independent: tabbedFirst=$tabbedFirst',
      () {
        final plain = _paragraph('plain', []);
        final tabbed = _paragraph('tabbed', const [WmlTabStop(position: 72)]);
        final result = _export(tabbedFirst ? [tabbed, plain] : [plain, tabbed]);
        for (final paragraph in result.paragraphs) {
          expect(
            _tabs(result.root, paragraph),
            paragraph.text == 'plain'
                ? <List<String?>>[]
                : <List<String?>>[
                    ['72.00pt', 'left', null, null],
                  ],
          );
        }
      },
    );
  }

  test('tab lists retain their full order and do not mutate the source', () {
    const first = WmlTabStop(position: 72);
    const second = WmlTabStop(position: 144, alignment: WmlTabAlignment.right);
    final forward = [first, second];
    final reverse = [second, first];
    final result = _export([
      _paragraph('forward', forward),
      _paragraph('reverse', reverse),
      _paragraph('prefix', [first]),
    ]);
    expect(result.paragraphs.map((p) => _tabs(result.root, p)), [
      [
        ['72.00pt', 'left', null, null],
        ['144.00pt', 'right', null, null],
      ],
      [
        ['144.00pt', 'right', null, null],
        ['72.00pt', 'left', null, null],
      ],
      [
        ['72.00pt', 'left', null, null],
      ],
    ]);
    expect(forward, [first, second]);
    expect(reverse, [second, first]);
  });

  test('equivalent independently constructed tab stops share a style', () {
    final result = _export([
      _paragraph('one', [WmlTabStop(position: 72)]),
      _paragraph('two', [WmlTabStop(position: 72)]),
    ]);
    expect(
      result.paragraphs.first.getAttribute('style-name', namespaceUri: _text),
      result.paragraphs.last.getAttribute('style-name', namespaceUri: _text),
    );
    expect(_tabs(result.root, result.paragraphs.last), [
      ['72.00pt', 'left', null, null],
    ]);
  });
}
