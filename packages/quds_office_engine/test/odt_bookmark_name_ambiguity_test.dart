import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';

void main() {
  test('a malformed bookmark id still reserves its emitted name', () {
    final paragraph = WmlParagraph(
      inlines: [
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'Shared'),
        WmlRun(text: 'First'),
        WmlBookmarkBoundary(id: 'bad', isStart: true, name: 'Shared'),
        WmlRun(text: 'Second'),
        WmlBookmarkBoundary(id: '1', isStart: false),
        WmlBookmarkBoundary(id: '2', isStart: true, name: 'Independent'),
        WmlRun(text: 'Third'),
        WmlBookmarkBoundary(id: '2', isStart: false),
      ],
    );
    final original = List<WmlInline>.of(paragraph.inlines);
    final package = OpcPackage.openBytes(
      OdtDocumentWriter.writeBytes(
        WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph]),
          ],
        ),
      ),
    );
    final content = XmlDocument.parse(
      package.getPart('/content.xml')!.readText(),
    ).root!;
    final output = content
        .firstChild('body')!
        .firstChild('text')!
        .firstChild('p')!;
    Iterable<String?> names(String element) => output
        .childrenNamed(element, namespaceUri: _textNs)
        .map((node) => node.getAttribute('name', namespaceUri: _textNs));
    expect(names('bookmark-start'), ['Shared', 'Shared', 'Independent']);
    expect(names('bookmark-end'), ['Independent']);
    expect(output.text, 'FirstSecondThird');
    expect(paragraph.inlines, orderedEquals(original));
    expect((paragraph.inlines[2] as WmlBookmarkBoundary).id, 'bad');
  });
}
