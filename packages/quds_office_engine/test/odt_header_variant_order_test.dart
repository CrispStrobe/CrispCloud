import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

String _text(XmlNode node) => switch (node) {
  XmlText() => node.text,
  XmlElement() => node.children.map(_text).join(),
  _ => '',
};

void main() {
  for (final (name, defaults, first, even, expected) in [
    (
      'all variants',
      true,
      true,
      true,
      [
        'header',
        'header-left',
        'header-first',
        'footer',
        'footer-left',
        'footer-first',
      ],
    ),
    (
      'variants with empty defaults',
      false,
      true,
      true,
      [
        'header',
        'header-left',
        'header-first',
        'footer',
        'footer-left',
        'footer-first',
      ],
    ),
    (
      'first variants with empty defaults',
      false,
      true,
      false,
      ['header', 'header-first', 'footer', 'footer-first'],
    ),
    (
      'even variants with empty defaults',
      false,
      false,
      true,
      ['header', 'header-left', 'footer', 'footer-left'],
    ),
  ]) {
    test('$name follow the ODF master-page child sequence', () {
      final section = WmlSection(
        differentFirstPage: first,
        differentOddEven: even,
        header: [if (defaults) _paragraph('DefaultHeader')],
        footer: [if (defaults) _paragraph('DefaultFooter')],
        firstHeader: [if (first) _paragraph('FirstHeader')],
        firstFooter: [if (first) _paragraph('FirstFooter')],
        evenHeader: [if (even) _paragraph('EvenHeader')],
        evenFooter: [if (even) _paragraph('EvenFooter')],
        blocks: [_paragraph('Body')],
      );
      final package = OpcPackage.openBytes(
        OdtDocumentWriter.writeBytes(WmlDocument(sections: [section])),
      );
      final styles = XmlDocument.parse(
        package.getPart('/styles.xml')!.readText(),
      ).root!;
      final children = styles
          .firstChild('master-styles')!
          .firstChild('master-page')!
          .childElements
          .toList();
      // ODF 1.3 style-master-page is an ordered sequence. A default story
      // must precede its optional left and first variants, even when empty.
      expect(children.map((child) => child.localName), expected);
      final text = {
        for (final child in children) child.localName: _text(child),
      };
      expect(text['header'], defaults ? 'DefaultHeader' : '');
      expect(text['footer'], defaults ? 'DefaultFooter' : '');
      if (first) {
        expect(text['header-first'], 'FirstHeader');
        expect(text['footer-first'], 'FirstFooter');
      }
      if (even) {
        expect(text['header-left'], 'EvenHeader');
        expect(text['footer-left'], 'EvenFooter');
      }
    });
  }
}
