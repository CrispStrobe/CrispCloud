import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _styleNs = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const _foNs = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

void main() {
  test('an empty bookmarked PAGE field precedes its trailing column break', () {
    final paragraph = WmlParagraph(
      properties: WmlParagraphProps(pageNumberField: true),
      inlines: [
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'EmptyPage'),
        WmlBookmarkBoundary(id: '1', isStart: false),
        WmlBreak(WmlBreakType.column),
      ],
    );
    final original = List<WmlInline>.of(paragraph.inlines);
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(
        WmlDocument(
          sections: [
            WmlSection(columnCount: 2, blocks: [paragraph]),
          ],
        ),
      ),
    );
    final content = XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!;
    final body = content
        .firstChild('body')!
        .firstChild('text')!
        .firstChild('section')!;
    final paragraphs = body.childrenNamed('p', namespaceUri: _textNs).toList();
    expect(paragraphs, hasLength(2));
    expect(paragraphs.first.childElements.map((element) => element.localName), [
      'bookmark-start',
      'page-number',
      'bookmark-end',
    ]);
    expect(paragraphs.last.childElements, isEmpty);
    String? breakBefore(XmlElement owner) {
      final name = owner.getAttribute('style-name', namespaceUri: _textNs);
      return content
          .firstChild('automatic-styles')!
          .childrenNamed('style', namespaceUri: _styleNs)
          .singleWhere(
            (style) =>
                style.getAttribute('name', namespaceUri: _styleNs) == name,
          )
          .firstChild('paragraph-properties')!
          .getAttribute('break-before', namespaceUri: _foNs);
    }

    expect(breakBefore(paragraphs.first), isNull);
    expect(breakBefore(paragraphs.last), 'column');
    expect(paragraph.inlines, orderedEquals(original));
    expect(paragraph.properties.columnBreakBefore, isFalse);
  });
}
