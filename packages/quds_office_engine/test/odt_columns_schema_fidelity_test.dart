import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

XmlElement _content(List<WmlSection> sections) {
  final package = OpcPackage.openBytes(
    OdtDocumentWriter.writeBytes(WmlDocument(sections: sections)),
  );
  return XmlDocument.parse(package.getPart('/content.xml')!.readText()).root!;
}

WmlSection _section(int count, double gap, String text) => WmlSection(
  columnCount: count,
  columnSpace: gap,
  blocks: [
    WmlParagraph(inlines: [WmlRun(text: text)]),
  ],
);

void main() {
  test('section column counts and gaps use the ODF columns child', () {
    final settings = [(2, 18.0), (2, 12.0), (3, 18.0)];
    final content = _content([
      for (var index = 0; index < settings.length; index++)
        _section(settings[index].$1, settings[index].$2, 'Columns $index'),
      _section(1, 18, 'Single column'),
    ]);
    final body = content.firstChild('body')!.firstChild('text')!;
    final sections = body.childElements
        .where(
          (element) =>
              element.namespaceUri == _textNs && element.localName == 'section',
        )
        .toList();
    expect(sections, hasLength(settings.length));
    final styles = content.firstChild('automatic-styles')!.childElements;
    final names = <String>{};
    for (var index = 0; index < sections.length; index++) {
      final name = sections[index].getAttribute(
        'style-name',
        namespaceUri: _textNs,
      )!;
      names.add(name);
      final style = styles.singleWhere(
        (element) =>
            element.namespaceUri == _styleNs &&
            element.getAttribute('name', namespaceUri: _styleNs) == name,
      );
      expect(style.getAttribute('family', namespaceUri: _styleNs), 'section');
      final properties = style.firstChild('section-properties')!;
      // ODF 1.3 sections 17.11/17.12 place these attributes on style:columns.
      expect(
        properties.getAttribute('column-count', namespaceUri: _foNs),
        isNull,
      );
      expect(
        properties.getAttribute('column-gap', namespaceUri: _foNs),
        isNull,
      );
      final columns = properties.childElements
          .where(
            (element) =>
                element.namespaceUri == _styleNs &&
                element.localName == 'columns',
          )
          .toList();
      expect(columns, hasLength(1));
      expect(
        columns.single.getAttribute('column-count', namespaceUri: _foNs),
        '${settings[index].$1}',
      );
      expect(
        columns.single.getAttribute('column-gap', namespaceUri: _foNs),
        '${settings[index].$2.toStringAsFixed(2)}pt',
      );
    }
    expect(names, hasLength(settings.length));
    expect(body.childrenNamed('p'), hasLength(1));
  });

  test(
    'a single column retains the ordinary body without a section wrapper',
    () {
      final content = _content([_section(1, 18, 'Ordinary paragraph')]);
      final body = content.firstChild('body')!.firstChild('text')!;
      expect(body.childElements.map((element) => element.localName), ['p']);
      expect(
        content
            .firstChild('automatic-styles')!
            .childElements
            .where(
              (element) =>
                  element.getAttribute('family', namespaceUri: _styleNs) ==
                  'section',
            ),
        isEmpty,
      );
    },
  );
}
