import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  group('XmlPullReader', () {
    test('parses namespaced Office-style documents', () {
      const String xml =
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    <w:p w:rsidR="00AB">
      <w:r><w:t xml:space="preserve">Hello &amp; مرحبا</w:t></w:r>
    </w:p>
  </w:body>
</w:document>''';

      final XmlPullReader reader = XmlPullReader(xml);
      final List<String> starts = <String>[];
      String? text;
      String? space;
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement) {
          starts.add(
            '${reader.prefix}:${reader.localName}|${reader.namespaceUri}',
          );
          if (reader.localName == 't') {
            space = reader.getAttribute(
              'space',
              namespaceUri: OfficeNamespaces.xml,
            );
          }
        } else if (reader.eventType == XmlEventType.characters &&
            !reader.isWhitespace) {
          text = reader.text;
        }
      }

      expect(starts.first, contains('document'));
      expect(starts.any((String s) => s.contains(OfficeNamespaces.w)), isTrue);
      expect(text, 'Hello & مرحبا');
      expect(space, 'preserve');
    });

    test('handles empty elements, comments, and CDATA', () {
      const String xml =
          '<root><!--c--><empty attr="x"/><![CDATA[raw <&>]]></root>';
      final XmlPullReader reader = XmlPullReader(xml);
      final List<XmlEventType> events = <XmlEventType>[];
      String? cdata;
      while (reader.next()) {
        events.add(reader.eventType);
        if (reader.eventType == XmlEventType.cdata) {
          cdata = reader.text;
        }
        if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'empty') {
          expect(reader.isEmptyElement, isTrue);
          expect(reader.getAttribute('attr'), 'x');
        }
      }
      expect(events, contains(XmlEventType.comment));
      expect(cdata, 'raw <&>');
      expect(
        events.where((XmlEventType e) => e == XmlEventType.endElement).length,
        2,
      );
    });

    test('round-trips through XmlDocument and XmlWriter', () {
      const String xml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="app"/>'
          '</Types>';
      final XmlDocument doc = XmlDocument.parse(xml);
      expect(doc.root!.localName, 'Types');
      expect(
        doc.root!.childrenNamed('Default').single.getAttribute('Extension'),
        'xml',
      );
      final String out = doc.toXmlString();
      final XmlDocument again = XmlDocument.parse(out);
      expect(
        again.root!.childrenNamed('Override').single.getAttribute('PartName'),
        '/word/document.xml',
      );
    });

    test('decodes numeric entities', () {
      final XmlPullReader reader = XmlPullReader('<t>&#x644;&#1604;</t>');
      while (reader.next()) {
        if (reader.eventType == XmlEventType.characters) {
          expect(reader.text, 'لل');
        }
      }
    });
  });
}
