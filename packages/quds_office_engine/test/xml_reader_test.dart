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

    test('token matching checks the full name and attribute namespace', () {
      final reader = XmlPullReader(
        '<p:root xmlns:p="urn:p" xmlns:q="urn:q" '
        'p:identifier="long" q:id="other" p:id="wanted"></q:root>',
      );
      expect(reader.next(), isTrue);
      expect(reader.getAttribute('id'), 'other');
      expect(reader.getAttribute('id', namespaceUri: 'urn:p'), 'wanted');
      expect(reader.getAttribute('identi'), isNull);
      expect(
        reader.next,
        throwsA(
          isA<XmlParseException>().having(
            (error) => error.toString(),
            'message',
            contains('expected </p:root> but found </q:root>'),
          ),
        ),
      );
    });

    test('closing tags match the complete opening name at their depth', () {
      final reader = XmlPullReader('<é><élément></élément></é>');
      for (final name in ['é', 'élément', 'élément', 'é']) {
        expect(reader.next(), isTrue);
        expect(reader.qualifiedName, name);
      }
      final shorter = XmlPullReader('<élément></é>')..next();
      expect(shorter.next, throwsA(isA<XmlParseException>()));
    });

    test('event names survive empty tags and follow namespace scope', () {
      final reader = XmlPullReader(
        '<root xmlns:p="urn:outer"><p:child xmlns:p="urn:inner"/>'
        '<p:sibling/></root>',
      );
      expect(reader.next(), isTrue);
      expect(reader.localName, 'root');
      expect(reader.next(), isTrue);
      expect(reader.localName, 'child');
      expect(reader.namespaceUri, 'urn:inner');
      expect(reader.next(), isTrue);
      expect(reader.eventType, XmlEventType.endElement);
      expect(reader.localName, 'child');
      expect(reader.qualifiedName, 'p:child');
      expect(reader.namespaceUri, 'urn:outer');
      expect(reader.next(), isTrue);
      expect(reader.localName, 'sibling');
      expect(reader.namespaceUri, 'urn:outer');
    });

    test('closing nested tags restores only the scope declared there', () {
      final reader = XmlPullReader(
        '<p:root xmlns:p="urn:root"><p:parent xmlns:p="urn:parent">'
        '<p:plain><p:child xmlns:p="urn:child"></p:child></p:plain>'
        '</p:parent></p:root>',
      );
      final namespaces = <Map<String, String>>[];
      while (reader.nextTag()) {
        namespaces.add(reader.inScopeNamespaces);
      }
      expect(namespaces.map((scope) => scope['p']), [
        'urn:root',
        'urn:parent',
        'urn:parent',
        'urn:child',
        'urn:parent',
        'urn:parent',
        'urn:root',
        null,
      ]);
      expect(identical(namespaces[1], namespaces[2]), isTrue);
      expect(identical(namespaces[1], namespaces[4]), isTrue);
    });

    test('tag and attribute prefixes use their current namespace scope', () {
      final reader = XmlPullReader(
        '<p:root xmlns:p="urn:outer" xmlns:q="urn:other" p:id="parent">'
        '<p:child xmlns:p="urn:inner" q:id="other" p:id="child"/>'
        '<p:sibling p:id="sibling"/></p:root>',
      );
      expect(reader.next(), isTrue);
      expect(reader.namespaceUri, 'urn:outer');
      expect(reader.getAttribute('id', namespaceUri: 'urn:outer'), 'parent');
      expect(reader.next(), isTrue);
      expect(reader.namespaceUri, 'urn:inner');
      expect(reader.getAttribute('id', namespaceUri: 'urn:inner'), 'child');
      expect(reader.getAttribute('id', namespaceUri: 'urn:other'), 'other');
      expect(reader.next(), isTrue);
      expect(reader.next(), isTrue);
      expect(reader.namespaceUri, 'urn:outer');
      expect(reader.getAttribute('id', namespaceUri: 'urn:outer'), 'sibling');
      expect(reader.getAttribute('id', namespaceUri: 'urn:inner'), isNull);
    });

    test('attribute slots reset when the next tag has fewer attributes', () {
      final many = List.generate(20, (i) => 'a$i="$i"').join(' ');
      final reader = XmlPullReader(
        '<root xmlns:p="urn:p"><p:wide $many p:val="&amp;"/>'
        '<p:narrow val="plain"/><p:empty/><p:wide $many p:val="again"/>'
        '</root>',
      );
      expect(reader.next(), isTrue);
      expect(reader.next(), isTrue);
      expect(reader.attributeCount, 21);
      expect(reader.getAttribute('val', namespaceUri: 'urn:p'), '&');
      expect(reader.getAttribute('a19'), '19');
      expect(reader.next(), isTrue);
      expect(reader.eventType, XmlEventType.endElement);
      expect(reader.attributeCount, 21);
      expect(reader.next(), isTrue);
      expect(reader.attributeCount, 1);
      expect(reader.attributesAsMap(), {'val': 'plain'});
      expect(reader.getAttribute('val', namespaceUri: 'urn:p'), isNull);
      expect(() => reader.attributeValue(1), throwsRangeError);
      expect(reader.next(), isTrue);
      expect(reader.next(), isTrue);
      expect(reader.attributeCount, 0);
      expect(() => reader.attributeNamespace(0), throwsRangeError);
      expect(reader.next(), isTrue);
      expect(reader.next(), isTrue);
      expect(reader.attributeCount, 21);
      expect(reader.getAttribute('val', namespaceUri: 'urn:p'), 'again');
      expect(reader.attributeValue(19), '19');
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
