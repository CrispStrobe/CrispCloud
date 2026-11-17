import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _officeNs = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

XmlElement _xml(OpcPackage package, String part) =>
    XmlDocument.parse(package.getPart('/$part.xml')!.readText()).root!;

XmlElement _style(XmlElement root, XmlElement paragraph) {
  final name = paragraph.getAttribute('style-name', namespaceUri: _textNs);
  return root
      .firstChild('automatic-styles', namespaceUri: _officeNs)!
      .childrenNamed('style', namespaceUri: _styleNs)
      .singleWhere(
        (style) => style.getAttribute('name', namespaceUri: _styleNs) == name,
      );
}

List<XmlElement> _paragraphs(XmlElement content) => content
    .firstChild('body', namespaceUri: _officeNs)!
    .firstChild('text', namespaceUri: _officeNs)!
    .childrenNamed('p', namespaceUri: _textNs)
    .toList();

void main() {
  test('neighboring paragraph styles retain independent tab stops', () {
    const tabs = <List<WmlTabStop>>[
      [],
      [WmlTabStop(position: 72)],
      [WmlTabStop(position: 144)],
      [WmlTabStop(position: 72, alignment: WmlTabAlignment.center)],
      [WmlTabStop(position: 72, leader: WmlTabLeader.dot)],
      [WmlTabStop(position: 72.004)],
      [],
    ];
    final paragraphs = [
      for (var index = 0; index < tabs.length; index++)
        WmlParagraph(
          properties: WmlParagraphProps(tabs: tabs[index]),
          inlines: [WmlRun(text: 'Paragraph $index\tValue')],
        ),
    ];
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(
        WmlDocument(sections: [WmlSection(blocks: paragraphs)]),
      ),
    );
    final content = _xml(package, 'content');
    final exported = _paragraphs(content);
    expect(exported, hasLength(tabs.length));
    final names = <String?>[];
    for (var index = 0; index < exported.length; index++) {
      final properties = _style(
        content,
        exported[index],
      ).firstChild('paragraph-properties', namespaceUri: _styleNs)!;
      final stops = properties.firstChild('tab-stops', namespaceUri: _styleNs);
      names.add(
        exported[index].getAttribute('style-name', namespaceUri: _textNs),
      );
      if (index == 0 || index == 6) {
        expect(stops, isNull);
      } else {
        expect(stops, isNotNull);
        final stop = stops!
            .childrenNamed('tab-stop', namespaceUri: _styleNs)
            .single;
        expect(
          stop.getAttribute('position', namespaceUri: _styleNs),
          index == 2 ? '144.00pt' : '72.00pt',
        );
        expect(
          stop.getAttribute('type', namespaceUri: _styleNs),
          index == 3 ? 'center' : 'left',
        );
        expect(
          stop.getAttribute('leader-style', namespaceUri: _styleNs),
          index == 4 ? 'dotted' : null,
        );
      }
    }
    expect(names.take(5).toSet(), hasLength(5));
    expect(names[5], names[1]);
    expect(names[6], names[0]);
    for (var index = 0; index < paragraphs.length; index++) {
      expect(identical(paragraphs[index].properties.tabs, tabs[index]), isTrue);
      expect(paragraphs[index].text, 'Paragraph $index\tValue');
    }
  });

  test(
    'continuous headers compare emitted tab stops before reusing masters',
    () {
      const tabs = <List<WmlTabStop>>[
        [WmlTabStop(position: 72, leader: WmlTabLeader.hyphen)],
        [WmlTabStop(position: 72.004, leader: WmlTabLeader.hyphen)],
        [WmlTabStop(position: 72, leader: WmlTabLeader.underscore)],
        [
          WmlTabStop(
            position: 144,
            alignment: WmlTabAlignment.right,
            leader: WmlTabLeader.dot,
          ),
        ],
      ];
      final document = WmlDocument(
        sections: [
          for (var index = 0; index < tabs.length; index++)
            WmlSection(
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Body $index')]),
              ],
              header: [
                WmlParagraph(
                  properties: WmlParagraphProps(tabs: tabs[index]),
                  inlines: [WmlRun(text: 'Header\tTitle')],
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
      final body = _paragraphs(content);
      expect(body, hasLength(tabs.length));
      expect(
        _style(
          content,
          body[1],
        ).getAttribute('master-page-name', namespaceUri: _styleNs),
        isNull,
      );
      expect(
        _style(
          content,
          body[2],
        ).getAttribute('master-page-name', namespaceUri: _styleNs),
        'mp2',
      );
      expect(
        _style(
          content,
          body[3],
        ).getAttribute('master-page-name', namespaceUri: _styleNs),
        'mp3',
      );
      final styles = _xml(package, 'styles');
      final masters = styles
          .firstChild('master-styles', namespaceUri: _officeNs)!
          .childrenNamed('master-page', namespaceUri: _styleNs)
          .toList();
      expect(masters, hasLength(tabs.length));
      final names = <String?>[];
      for (var index = 0; index < masters.length; index++) {
        final header = masters[index]
            .firstChild('header', namespaceUri: _styleNs)!
            .firstChild('p', namespaceUri: _textNs)!;
        names.add(header.getAttribute('style-name', namespaceUri: _textNs));
        final stop = _style(styles, header)
            .firstChild('paragraph-properties', namespaceUri: _styleNs)!
            .firstChild('tab-stops', namespaceUri: _styleNs)!
            .childrenNamed('tab-stop', namespaceUri: _styleNs)
            .single;
        expect(
          stop.getAttribute('position', namespaceUri: _styleNs),
          index == 3 ? '144.00pt' : '72.00pt',
        );
        expect(
          stop.getAttribute('leader-style', namespaceUri: _styleNs),
          index == 3 ? 'dotted' : 'solid',
        );
        expect(
          stop.getAttribute('leader-text', namespaceUri: _styleNs),
          ['-', '-', '_', '.'][index],
        );
      }
      expect(names[0], names[1]);
      expect(names[2], isNot(names[1]));
      expect(names[3], isNot(names[2]));
    },
  );
}
