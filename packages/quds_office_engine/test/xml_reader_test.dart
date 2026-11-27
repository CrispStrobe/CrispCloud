import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('XML writer keeps repeated local names scoped to their prefixes', () {
    final writer = XmlWriter()
      ..writeStartElement('root', namespaceUri: 'urn:r');
    writer.writeStartElement('node', prefix: 'q', namespaceUri: 'urn:q');
    writer.writeEmptyElement('node', prefix: 'v', namespaceUri: 'urn:v');
    writer.writeEmptyElement('node', prefix: 'q');
    writer.writeEmptyElement('node', prefix: '');
    expect(
      writer.toXml(),
      '<root xmlns="urn:r"><q:node xmlns:q="urn:q">'
      '<v:node xmlns:v="urn:v"/><q:node/><node/></q:node></root>',
    );
  });

  test('XML escaping preserves pairs and sanitizes isolated code units', () {
    final raw = String.fromCharCodes([
      0xD83D, 0xDE00, // Valid supplementary character before an escape.
      0x26, 0x3C, 0x3E, 0x22, 0x27, // &, <, >, double and single quotes.
      0xD800, 0xD83D, 0xDE00, 0xDC00, // A valid pair between lone surrogates.
      0x00, 0xFFFE, 0xFFFF, 0x09, 0x0A, 0x0D,
    ]);
    expect(encodeXmlText(raw), '😀&amp;&lt;&gt;"\'�😀����\t\n\r');
    expect(encodeXmlAttribute(raw), '😀&amp;&lt;&gt;&quot;\'�😀����\t\n\r');
  });

  test('pruning an XML subtree still validates its text entities', () {
    expect(
      () => XmlDocument.parse(
        '<root><skip><nested>&undefined;</nested></skip><keep/></root>',
        keepRootChild: (_, child) => child.localName == 'keep',
      ),
      throwsA(isA<XmlParseException>()),
    );
  });

  test('entity validation in a pruned subtree stays inside its text token', () {
    expect(
      () => XmlDocument.parse(
        '<root><skip>x &lt</skip><keep>&gt;</keep></root>',
        keepRootChild: (_, child) => child.localName == 'keep',
      ),
      throwsA(
        isA<XmlParseException>()
            .having((error) => error.message, 'message', 'Unterminated entity')
            .having((error) => error.position, 'position', 2),
      ),
    );
    expect(
      () => XmlDocument.parse(
        '<root><skip>&#x110000;</skip><keep/></root>',
        keepRootChild: (_, child) => child.localName == 'keep',
      ),
      throwsRangeError,
    );
  });

  test('attribute validation stops at the closing quote', () {
    final reader = XmlPullReader('<root a="x &lt" b="&gt;"/>');
    expect(
      reader.next,
      throwsA(
        isA<XmlParseException>()
            .having((error) => error.message, 'message', 'Unterminated entity')
            .having((error) => error.position, 'position', 2),
      ),
    );
  });

  test('normalizes literal and entity-encoded XML carriage returns', () {
    expect(decodeXmlEntities('A\r\nB\rC'), 'A\nB\nC');
    expect(decodeXmlEntities('&gt;&#xD;&#xA;A&#13;B&lt;'), '>\nA\nB<');
  });

  test('a known raw element leaves the reader at its matching close', () {
    const packet = '<p:run xmlns:p="urn:inner"><p:rPr/></p:run>';
    final reader = XmlPullReader(
      '<root xmlns:p="urn:outer">$packet$packet<p:sibling/></root>',
    );
    expect(reader.next(), isTrue);
    expect(reader.next(), isTrue);
    final fragment = reader.readRawElement();
    expect(fragment, packet);
    expect(reader.next(), isTrue);
    expect(reader.trySkipKnownElement('<p:run/>'), isFalse);
    expect(reader.localName, 'run');
    expect(reader.namespaceUri, 'urn:inner');
    expect(reader.trySkipKnownElement(fragment), isTrue);
    expect(reader.eventType, XmlEventType.endElement);
    expect(reader.localName, 'run');
    expect(reader.depth, 1);
    expect(reader.next(), isTrue);
    expect(reader.localName, 'sibling');
    expect(reader.namespaceUri, 'urn:outer');
  });

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
      expect(reader.hasLocalName('root'), isTrue);
      expect(reader.hasLocalName('p:root'), isFalse);
      expect(reader.hasLocalName('roo'), isFalse);
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
      final reader = XmlPullReader(
        '<é xmlns:p="urn:p"><p:élément></p:élément \n></é>',
      );
      for (final name in ['é', 'p:élément', 'p:élément', 'é']) {
        expect(reader.next(), isTrue);
        expect(reader.qualifiedName, name);
        if (name.startsWith('p:')) {
          expect(reader.localName, 'élément');
          expect(reader.namespaceUri, 'urn:p');
        }
      }
      for (final closing in ['é', 'élémentSuffix']) {
        final mismatched = XmlPullReader('<élément></$closing>')..next();
        expect(
          mismatched.next,
          throwsA(
            isA<XmlParseException>().having(
              (error) => error.message,
              'message',
              'Mismatched end tag: expected </élément> but found </$closing>',
            ),
          ),
        );
      }
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
