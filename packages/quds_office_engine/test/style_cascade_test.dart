import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;
import '../tool/fidelity/style_fixture.dart';

OpcPackage _fontSizeFixture(String direct, {String defaults = ''}) {
  final builder = DocxDocumentBuilder()..paragraph('Regular size');
  final package = OpcPackage.openBytes(builder.build());
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p><w:r>'
        '<w:rPr>$direct</w:rPr><w:t>Regular size</w:t></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  package
      .getPart('/word/styles.xml')!
      .writeText(
        '<w:styles xmlns:w="${OfficeNamespaces.w}"><w:docDefaults>'
        '<w:rPrDefault><w:rPr>$defaults</w:rPr></w:rPrDefault>'
        '</w:docDefaults></w:styles>',
      );
  return package;
}

Map<String, String?> _sizeProperties(String xml) => <String, String?>{
  for (final element in XmlDocument.parse(xml).root!.childElements)
    if (element.namespaceUri == OfficeNamespaces.w &&
        (element.localName == 'sz' || element.localName == 'szCs'))
      element.localName: element.getAttribute('val'),
};

void main() {
  group('regular font size projection', () {
    for (final (name, direct, defaults, expected)
        in <(String, String, String, int)>[
          (
            'direct regular size overrides default complex-script size',
            '<w:sz w:val="21"/>',
            '<w:sz w:val="20"/><w:szCs w:val="20"/>',
            21,
          ),
          (
            'regular size wins with complex-script size last',
            '<w:sz w:val="21"/><w:szCs w:val="32"/>',
            '',
            21,
          ),
          (
            'regular size wins with reversed source element order',
            '<w:szCs w:val="32"/><w:sz w:val="21"/>',
            '',
            21,
          ),
          (
            'complex-script-only input retains the compatibility fallback',
            '<w:szCs w:val="32"/>',
            '',
            32,
          ),
          (
            'direct complex-script size does not replace inherited regular size',
            '<w:szCs w:val="32"/>',
            '<w:sz w:val="22"/>',
            22,
          ),
        ]) {
      test(name, () {
        final package = _fontSizeFixture(direct, defaults: defaults);
        final originalStyles = XmlDocument.parse(
          package.getPart('/word/styles.xml')!.readText(),
        ).toXmlString();
        var document = WordDeserializer().read(package);
        final source = _sizeProperties(
          document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .sourcePropertiesXml!,
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final properties = document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties;
          expect(
            properties.fontSizeHalfPoints,
            expected,
            reason: 'cycle $cycle',
          );
          expect(
            _sizeProperties(properties.sourcePropertiesXml!),
            source,
            reason: 'retained direct size properties, cycle $cycle',
          );
          final saved = WordSerializer().write(document);
          expect(
            XmlDocument.parse(
              saved.getPart('/word/styles.xml')!.readText(),
            ).toXmlString(),
            originalStyles,
          );
          document = WordDeserializer().readBytes(saved.save());
        }
      });
    }

    test('native regular size edits retain separate complex-script XML', () {
      var document = WordDeserializer().read(
        _fontSizeFixture(
          '<w:szCs w:val="32"/>',
          defaults: '<w:sz w:val="20"/><w:szCs w:val="24"/>',
        ),
      );
      cli.applyStep(document, <String, Object?>{
        'op': 'runFormat',
        'paragraph': 0,
        'size': 10.5,
      });
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final properties = document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties;
        expect(properties.fontSizeHalfPoints, 21, reason: 'cycle $cycle');
        expect(
          _sizeProperties(properties.sourcePropertiesXml!),
          <String, String>{'sz': '21', 'szCs': '32'},
        );
      }
    });
  });

  test(
    'scripts apply character/table styles and edit table run definitions',
    () {
      final doc = WordDeserializer().read(styleFixture());
      cli.applyStep(doc, {
        'op': 'characterStyle',
        'paragraph': 2,
        'run': 0,
        'style': 'Accent',
      });
      expect(
        doc.paragraphs
            .elementAt(2)
            .inlines
            .whereType<WmlRun>()
            .first
            .properties
            .color,
        'AA3300',
      );
      cli.applyStep(doc, {
        'op': 'styleDefinition',
        'style': 'Regional',
        'type': 'table',
        'rPr': {
          'color': {'val': '778899'},
        },
      });
      cli.applyStep(doc, {'op': 'tableStyle', 'table': 0, 'style': 'Regional'});
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      final table = reopened.sections.first.blocks.whereType<WmlTable>().single;
      final body = (table.rows[1].cells[0].blocks.first as WmlParagraph).inlines
          .whereType<WmlRun>()
          .first;
      expect(body.properties.color, '778899');
      expect(
        reopened.paragraphs
            .elementAt(2)
            .inlines
            .whereType<WmlRun>()
            .first
            .properties
            .styleId,
        'Accent',
      );
    },
  );
  void check(WmlDocument d, {bool edited = false}) {
    final p = d.paragraphs.first;
    final r = p.inlines.whereType<WmlRun>().first.properties;
    expect(r.bold, true);
    expect(r.fontSizePoints, 14);
    expect(r.color, '225588');
    expect(r.asciiFont, 'Calibri');
    expect(p.properties.spacingBefore, 12);
    expect(p.properties.spacingAfter, 3);
    final second = d.paragraphs.elementAt(1);
    final runs = second.inlines.whereType<WmlRun>().toList();
    expect(second.properties.spacingBefore, 0);
    expect(runs[0].properties.styleId, 'Accent');
    expect(runs[0].properties.italic, true);
    expect(runs[0].properties.color, edited ? '008844' : 'AA3300');
    expect(runs[0].properties.fontSizePoints, 16);
    expect(runs[1].properties.bold, false);
    expect(runs[1].properties.color, '000000');
    expect(runs[1].properties.fontSizePoints, 11);
    expect(
      d.paragraphs
          .elementAt(2)
          .inlines
          .whereType<WmlRun>()
          .first
          .properties
          .fontSizePoints,
      12,
    );
    final table = d.sections.first.blocks.whereType<WmlTable>().single;
    final header = (table.rows[0].cells[0].blocks.first as WmlParagraph).inlines
        .whereType<WmlRun>()
        .first;
    final body = (table.rows[1].cells[0].blocks.first as WmlParagraph).inlines
        .whereType<WmlRun>()
        .first;
    expect(header.properties.bold, true);
    expect(header.properties.color, 'FFFFFF');
    expect(body.properties.color, '334455');
  }

  test(
    'defaults basedOn theme character table and direct values survive 3 cycles',
    () async {
      var doc = WordDeserializer().read(styleFixture());
      check(doc);
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(doc);
        (Directory('build/fidelity-styles')..createSync(recursive: true));
        File(
          'build/fidelity-styles/unchanged-$cycle.docx',
        ).writeAsBytesSync(bytes);
        doc = WordDeserializer().readBytes(bytes);
        check(doc);
      }
      cli.applyStep(doc, {
        'op': 'styleDefinition',
        'style': 'Accent',
        'type': 'character',
        'rPr': {
          'color': {'val': '008844'},
        },
      });
      check(doc, edited: true);
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(doc);
        File(
          'build/fidelity-styles/edited-$cycle.docx',
        ).writeAsBytesSync(bytes);
        doc = WordDeserializer().readBytes(bytes);
        check(doc, edited: true);
      }
    },
  );
  test(
    'direct edits survive style refresh and inherited values remain editable',
    () {
      final doc = WordDeserializer().read(styleFixture());
      doc.paragraphs.first.inlines.whereType<WmlRun>().first.properties.bold =
          false;
      WordDeserializer().refreshStyles(doc);
      expect(
        doc.paragraphs.first.inlines.whereType<WmlRun>().first.properties.bold,
        false,
      );
      final copied = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(
        copied.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .bold,
        false,
      );
    },
  );
  test('style toggles compose while direct on/off is absolute', () async {
    final package = styleFixture();
    final styles = package.getPart('/word/styles.xml')!;
    styles.writeText(
      styles.readText().replaceFirst(
        '</w:styles>',
        '<w:style w:type="paragraph" w:styleId="Toggle"><w:basedOn w:val="Base"/><w:rPr><w:b/><w:i/></w:rPr></w:style>'
            '<w:style w:type="paragraph" w:styleId="Unchanged"><w:basedOn w:val="Base"/><w:rPr><w:b w:val="0"/></w:rPr></w:style>'
            '</w:styles>',
      ),
    );
    package
        .getPart('/word/document.xml')!
        .writeText(
          '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>'
          '<w:p><w:pPr><w:pStyle w:val="Toggle"/></w:pPr>'
          '<w:r><w:t>Toggled off</w:t></w:r>'
          '<w:r><w:rPr><w:b/></w:rPr><w:t>Direct on</w:t></w:r>'
          '<w:r><w:rPr><w:b w:val="0"/><w:i w:val="0"/></w:rPr><w:t>Direct off</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:pStyle w:val="Unchanged"/></w:pPr><w:r><w:t>False style leaves parent on</w:t></w:r></w:p>'
          '<w:sectPr/></w:body></w:document>',
        );
    var doc = WordDeserializer().read(package);
    for (int cycle = 0; cycle < 4; cycle++) {
      final runs = doc.paragraphs.first.inlines.whereType<WmlRun>().toList();
      expect(runs.map((r) => r.properties.bold), [false, true, false]);
      expect(runs.map((r) => r.properties.italic), [true, true, false]);
      expect(
        doc.paragraphs.last.inlines.whereType<WmlRun>().first.properties.bold,
        true,
      );
      final bytes = await OfficeIsolateSave.word(doc);
      if (cycle > 0) {
        Directory('build/fidelity-style-toggles').createSync(recursive: true);
        File(
          'build/fidelity-style-toggles/toggle-$cycle.docx',
        ).writeAsBytesSync(bytes);
      }
      doc = WordDeserializer().readBytes(bytes);
    }
  });
  test(
    'custom style part location stays authoritative after style edits',
    () async {
      final package = styleFixture();
      final original = package.getPart('/word/styles.xml')!;
      package.createPart(
        '/word/resources/custom-styles.xml',
        original.contentType,
        original.readBytes(),
      );
      package.deletePart('/word/styles.xml');
      final rels = package.relationshipsFor('/word/document.xml');
      final rel = rels.firstByType(RelationshipTypes.styles)!;
      rels.removeById(rel.id);
      rels.add(
        id: rel.id,
        type: rel.type,
        target: 'resources/custom-styles.xml',
      );
      var doc = WordDeserializer().read(package);
      cli.applyStep(doc, {
        'op': 'styleDefinition',
        'style': 'Accent',
        'type': 'character',
        'rPr': {
          'color': {'val': '123456'},
        },
      });
      for (int cycle = 0; cycle < 3; cycle++) {
        doc = WordDeserializer().readBytes(await OfficeIsolateSave.word(doc));
        expect(doc.package!.getPart('/word/styles.xml'), isNull);
        expect(
          doc.paragraphs
              .elementAt(1)
              .inlines
              .whereType<WmlRun>()
              .first
              .properties
              .color,
          '123456',
        );
        expect(
          doc.package!
              .relationshipsFor('/word/document.xml')
              .firstByType(RelationshipTypes.styles)!
              .target,
          'resources/custom-styles.xml',
        );
      }
    },
  );
}
