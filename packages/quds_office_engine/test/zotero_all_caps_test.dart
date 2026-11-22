import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:zotero-caps-tests';
const _html = '<span style="font-variant:small-caps">Ab</span> cd';

Uint8List _fixture({String run = '', String? styles}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w" xmlns:x="$_x"><w:body><w:p><w:r><w:rPr>$run</w:rPr>'
        '<w:t>Source</w:t></w:r></w:p><w:sectPr/></w:body></w:document>',
      );
  if (styles != null) {
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w">$styles</w:styles>');
  }
  return package.save();
}

List<WmlRun> _runs(WmlDocument doc) =>
    doc.paragraphs.single.inlines.whereType<WmlRun>().toList();

List<XmlElement> _properties(Uint8List bytes) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .firstChild('p', namespaceUri: _w)!
        .childrenNamed('r', namespaceUri: _w)
        .map((run) => run.firstChild('rPr', namespaceUri: _w)!)
        .toList();

void main() {
  test(
    'CSL small capitals override host allCaps without changing ordinary spans',
    () {
      final base = WmlRunProps(
        allCaps: true,
        fontSizeHalfPoints: 20,
        color: '123456',
        asciiFont: 'Host Font',
        proofingLanguage: 'de-DE',
      );
      final rich = ZoteroFormattedText.fromHtml(_html);
      final runs = rich.toRuns(baseProperties: base);
      expect(
        runs.map(
          (run) => (run.text, run.properties.allCaps, run.properties.smallCaps),
        ),
        [('Ab', false, true), (' cd', true, false)],
      );
      expect(runs.map((run) => run.properties.color), everyElement('123456'));
      expect(
        runs.map((run) => run.properties.asciiFont),
        everyElement('Host Font'),
      );
      expect(
        runs.map((run) => run.properties.proofingLanguage),
        everyElement('de-DE'),
      );
      expect(base.allCaps, isTrue);
      expect(base.smallCaps, isFalse);
      final document = WmlDocument.empty();
      document.paragraphs.single.inlines = runs;
      final line = WordLayoutEngine(
        font: null,
      ).layout(document).pages.single.lines.single;
      expect(
        String.fromCharCodes(line.glyphs.map((g) => g.glyph.codePoint)),
        'AB CD',
      );
      expect(line.glyphs.map((g) => g.fontSize), [10, 8, 10, 10, 10]);
      expect(document.paragraphs.single.text, 'Ab cd');
    },
  );

  test(
    'direct caps metadata is reset sparsely for explicit CSL small capitals',
    () {
      var document = WordDeserializer().readBytes(
        _fixture(
          run:
              '<q:caps xmlns:q="$_w" q:val="1" x:keep="host"><x:child/></q:caps>'
              '<x:caps w:val="1"/><w:color w:val="123456"/>',
        ),
      );
      final base = _runs(document).single.properties;
      final before = WordSerializer().runPropertiesXml(base);
      document.paragraphs.single.inlines = ZoteroFormattedText.fromHtml(
        _html,
      ).toRuns(baseProperties: base);
      expect(WordSerializer().runPropertiesXml(base), before);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = WordSerializer().writeBytes(document);
        final properties = _properties(bytes);
        expect(
          properties.map(
            (p) => p
                .firstChild('caps', namespaceUri: _w)!
                .getAttribute('val', namespaceUri: _w),
          ),
          ['0', '1'],
        );
        for (final property in properties) {
          final caps = property.firstChild('caps', namespaceUri: _w)!;
          expect(caps.getAttribute('keep', namespaceUri: _x), 'host');
          expect(caps.firstChild('child', namespaceUri: _x), isNotNull);
          expect(property.firstChild('caps', namespaceUri: _x), isNotNull);
        }
        document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.single.text, 'Ab cd');
        expect(_runs(document).map((r) => r.properties.allCaps), [false, true]);
        expect(_runs(document).map((r) => r.properties.smallCaps), [
          true,
          false,
        ]);
      }
    },
  );

  for (final inherited in [false, true]) {
    test(
      'CSL owns caps-off against inherited $inherited while ordinary style remains live',
      () {
        final document = WordDeserializer().readBytes(
          _fixture(
            run: '<w:rStyle w:val="Host"/>',
            styles:
                '<w:style w:type="character" w:styleId="Host"><w:rPr>'
                '<w:caps w:val="${inherited ? 1 : 0}"/><w:color w:val="123456"/>'
                '</w:rPr></w:style>',
          ),
        );
        final base = _runs(document).single.properties;
        expect(base.allCaps, inherited);
        document.paragraphs.single.inlines = ZoteroFormattedText.fromHtml(
          _html,
        ).toRuns(baseProperties: base);
        final bytes = WordSerializer().writeBytes(document);
        final properties = _properties(bytes);
        expect(
          properties.first
              .firstChild('caps', namespaceUri: _w)!
              .getAttribute('val', namespaceUri: _w),
          '0',
        );
        expect(properties.last.firstChild('caps', namespaceUri: _w), isNull);
        expect(
          properties.every(
            (p) => p.firstChild('color', namespaceUri: _w) == null,
          ),
          isTrue,
        );
        var reopened = WordDeserializer().readBytes(bytes);
        expect(_runs(reopened).map((r) => r.properties.allCaps), [
          false,
          inherited,
        ]);
        final package = OpcPackage.openBytes(bytes);
        final styles = package.getPart('/word/styles.xml')!;
        styles.writeText(
          styles
              .readText()
              .replaceAll(
                '<w:caps w:val="${inherited ? 1 : 0}"/>',
                '<w:caps w:val="${inherited ? 0 : 1}"/>',
              )
              .replaceAll('123456', '654321'),
        );
        reopened = WordDeserializer().read(package);
        expect(_runs(reopened).map((r) => r.properties.allCaps), [
          false,
          !inherited,
        ]);
        expect(_runs(reopened).map((r) => r.properties.smallCaps), [
          true,
          false,
        ]);
        expect(
          _runs(reopened).map((r) => r.properties.color),
          everyElement('654321'),
        );
        expect(reopened.paragraphs.single.text, 'Ab cd');
      },
    );
  }

  test(
    'native citation insertion into allCaps retains CSL small-cap display and live fields',
    () {
      final rich = ZoteroFormattedText.fromHtml(
        '<span style="font-variant:small-caps">Müller</span>, 12',
      );
      final citation = ZoteroCitation(
        citationId: 'all-caps-host',
        plainCitation: rich.plainText,
        items: [
          ZoteroCitationItem.fromCsl(
            itemData: {'type': 'book', 'title': 'Book'},
            uris: ['http://zotero.org/users/42/items/ABCD1234'],
            locator: '12',
          ),
        ],
      );
      var document = WmlDocument.empty(text: 'Before  after');
      _runs(document).single.properties.allCaps = true;
      WordZotero.insertNativeCitation(
        document.paragraphs.single,
        instruction: citation.fieldInstruction,
        text: rich.plainText,
        formattedText: rich,
        index: 7,
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final field = WordZotero.fields(document).single;
        expect(field.cachedText, 'Müller, 12');
        expect(field.citation!.items.single.locator, '12');
        expect(field.canEdit, isTrue);
        expect(WordFieldSpans.unbalanced(document), isEmpty);
        final run = _runs(document).singleWhere((r) => r.text == 'Müller');
        expect(run.properties.smallCaps, isTrue);
        expect(run.properties.allCaps, isFalse);
        expect(document.paragraphs.single.text, 'Before Müller, 12 after');
        expect(_runs(document).first.properties.allCaps, isTrue);
        expect(_runs(document).last.properties.allCaps, isTrue);
      }
    },
  );
}
