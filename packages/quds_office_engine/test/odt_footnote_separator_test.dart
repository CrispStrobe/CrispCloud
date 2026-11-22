import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_styles.dart';
import 'package:test/test.dart';

const _separator = WmlFootnoteSeparator(
  beforeSpacing: 4,
  thickness: 1,
  afterSpacing: 7,
  relativeWidth: 0.5,
  alignment: WmlFootnoteSeparatorAlignment.right,
  color: 0x176346,
);
const _generator =
    'LibreOfficeDev/26.8.0.0.alpha0\$Linux_X86_64 '
    'LibreOffice_project/0123456789abcdef0123456789abcdef01234567';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document([WmlFootnoteSeparator separator = _separator]) {
  final body = _paragraph('Body العربية 😀 ');
  body.inlines.add(WmlRun(text: '1', noteRefId: 1));
  final note = _paragraph('Note ');
  WordZotero.insertCitation(
    note,
    ZoteroCitation.fromJson({
      'citationID': 'separator-note',
      'citationItems': [
        {
          'id': 17,
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '12',
          'itemData': {'id': 17, 'type': 'book', 'title': 'Source العربية 😀'},
          'futureItem': {'retain': true},
        },
      ],
      'properties': {'plainCitation': '(Source)', 'noteIndex': 1},
      'futureCitation': ['keep', 42],
    }),
    index: 5,
  );
  return WmlDocument(
    footnoteSeparator: separator,
    sections: [
      WmlSection(blocks: [body, _paragraph('After')]),
    ],
    footnotes: [
      WmlNote(id: 1, endnote: false, paragraphs: [note]),
    ],
    zoteroDocumentData: jsonEncode({
      'dataVersion': 4,
      'style': {
        'styleID': 'http://www.zotero.org/styles/apa',
        'locale': 'en-US',
      },
      'prefs': {'fieldType': 'Field', 'noteType': 0},
      'futureDocument': {'retain': 'العربية 😀'},
    }),
  );
}

Uint8List _rewrite(
  Uint8List bytes, {
  String Function(String)? styles,
  String Function(String)? content,
  String Function(String)? metadata,
}) {
  final zip = ZipReader.fromBytes(bytes);
  final writer = ZipWriter();
  for (final entry in zip.entries) {
    var data = zip.read(entry.fileName);
    final transform = switch (entry.fileName) {
      'styles.xml' => styles,
      'content.xml' => content,
      'meta.xml' => metadata,
      _ => null,
    };
    if (transform != null) data = utf8.encode(transform(utf8.decode(data)));
    writer.addFile(
      entry.fileName,
      data,
      store: entry.compressionMethod == zipMethodStore,
    );
  }
  return writer.close();
}

String _generatorMetadata(String xml, String producer) => xml.replaceFirst(
  RegExp(r'<meta:generator>[^<]*</meta:generator>'),
  '<meta:generator>$producer</meta:generator>',
);

void main() {
  test(
    'supported dormant settings survive ODT before a later footnote insertion',
    () async {
      var document = WmlDocument(footnoteSeparator: _separator);
      document.sections.single.blocks.add(_paragraph('Body without notes'));
      for (var cycle = 0; cycle < 2; cycle++) {
        document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
        expect(document.footnotes, isEmpty);
        expect(document.footnoteSeparator, _separator);
      }
      WordNotes.insert(
        document,
        document.paragraphs.first,
        endnote: false,
        text: 'Later footnote',
      );
      document = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
      );
      expect(document.footnotes, hasLength(1));
      expect(document.footnoteSeparator, _separator);
    },
  );

  test(
    'unsupported dormant line presets keep their validation-only contract',
    () async {
      final document = WmlDocument(footnoteSeparator: _separator);
      document.sections.single.blocks.add(_paragraph('No footnotes'));
      final bytes = _rewrite(
        OdtDocumentWriter.writeEditableZoteroBytes(document),
        styles: (xml) => xml.replaceFirst(
          'style:line-style="solid"',
          'style:line-style="dash"',
        ),
      );
      final reopened = await OdtDocumentReader.readBytes(bytes);
      expect(reopened.footnoteSeparator, isNull);
      expect(reopened.paragraphs.single.text, 'No footnotes');
    },
  );

  test(
    'ODT export refuses geometry exhausted only by emitted page precision',
    () {
      const separator = WmlFootnoteSeparator(
        beforeSpacing: 99.489,
        thickness: 0.5,
        afterSpacing: 0,
      );
      final document = _document(separator);
      document.sections.single
        ..pageSize = const WmlPageSize(width: 200, height: 120.004)
        ..margins = const WmlPageMargins(
          top: 10.006,
          bottom: 10.006,
          left: 10,
          right: 10,
        );
      expect(
        separator.reservedHeight,
        lessThan(document.sections.single.contentHeight),
      );
      expect(
        () => OdtDocumentWriter.writeEditableZoteroBytes(document),
        throwsUnsupportedError,
      );
      expect(document.footnoteSeparator, same(separator));
    },
  );

  test(
    'dormant exported separator lengths remain inside the reader envelope',
    () {
      final document = WmlDocument(
        footnoteSeparator: const WmlFootnoteSeparator(beforeSpacing: 1000001),
      );
      expect(
        () => OdtDocumentWriter.writeBytes(document),
        throwsUnsupportedError,
      );
    },
  );

  for (final alignment in WmlFootnoteSeparatorAlignment.values) {
    test(
      'active $alignment geometry and note citation survive repeated ODT',
      () async {
        final geometry = WmlFootnoteSeparator(
          beforeSpacing: 4,
          thickness: 1,
          afterSpacing: 7,
          relativeWidth: 0.5,
          alignment: alignment,
          color: 0x176346,
        );
        var document = _document(geometry);
        final metadata = WordZotero.fields(document).single.citation!.toJson();
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
          final inventory = await OdfZotero.inspect(bytes);
          expect(inventory.issues, isEmpty);
          expect(inventory.fields, hasLength(1));
          document = await OdtDocumentReader.readBytes(bytes);
          expect(document.footnoteSeparator, geometry);
          final field = WordZotero.fields(document).single;
          expect(field.citation!.toJson(), metadata);
          expect(document.footnotes.single.id, 1);
          expect(
            document.footnotes.single.allParagraphs,
            contains(field.paragraph),
          );
          expect(field.cachedText, '(Source)');
        }
      },
    );
  }

  test(
    'native DOCX cycles retain separator and editable ODT note ownership',
    () async {
      var document = _document();
      for (var cycle = 0; cycle < 3; cycle++) {
        document = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        expect(document.footnoteSeparator, _separator);
        final field = WordZotero.fields(document).single;
        expect(field.citation!.citationId, 'separator-note');
        expect(
          document.footnotes.single.allParagraphs,
          contains(field.paragraph),
        );
        expect(field.cachedText, '(Source)');
        expect(
          WordZoteroDocumentData.read(document),
          contains('futureDocument'),
        );
      }
    },
  );

  test(
    'hidden line retains both independent gaps and geometry in ODT',
    () async {
      const geometry = WmlFootnoteSeparator(
        lineStyle: WmlFootnoteSeparatorLineStyle.none,
        beforeSpacing: 5,
        afterSpacing: 9,
        thickness: 3,
        relativeWidth: 0.6,
        color: 0x123456,
      );
      final document = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(_document(geometry)),
      );
      expect(document.footnoteSeparator, geometry);
      expect(document.footnoteSeparator!.reservedHeight, 17);
    },
  );

  test('zero line width retains the reserved nominal thickness', () async {
    const geometry = WmlFootnoteSeparator(relativeWidth: 0, thickness: 7);
    final document = await OdtDocumentReader.readBytes(
      OdtDocumentWriter.writeEditableZoteroBytes(_document(geometry)),
    );
    expect(document.footnoteSeparator, geometry);
    expect(document.footnoteSeparator!.reservedHeight, 13);
  });

  test(
    'lengths round to explicit ODT precision without changing source',
    () async {
      const geometry = WmlFootnoteSeparator(
        beforeSpacing: 2.8656,
        thickness: 0.5112,
        afterSpacing: 2.8656,
      );
      final source = _document(geometry);
      final reopened = await OdtDocumentReader.readBytes(
        OdtDocumentWriter.writeEditableZoteroBytes(source),
      );
      expect(source.footnoteSeparator, same(geometry));
      expect(reopened.footnoteSeparator!.beforeSpacing, 2.87);
      expect(reopened.footnoteSeparator!.thickness, 0.51);
      expect(reopened.footnoteSeparator!.afterSpacing, 2.87);
    },
  );

  for (final name in ['width', 'distance-before-sep', 'distance-after-sep']) {
    test('stock LibreOffice zero $name omission is producer-scoped', () async {
      final original = OdtDocumentWriter.writeEditableZoteroBytes(_document());
      Uint8List rewritten(String producer) => _rewrite(
        original,
        styles: (xml) => xml.replaceFirst(RegExp(' style:$name="[^"]*"'), ''),
        metadata: (xml) => _generatorMetadata(xml, producer),
      );
      final document = await OdtDocumentReader.readBytes(rewritten(_generator));
      final separator = document.footnoteSeparator!;
      expect(switch (name) {
        'width' => separator.thickness,
        'distance-before-sep' => separator.beforeSpacing,
        _ => separator.afterSpacing,
      }, 0);
      for (final producer in [
        'Other/1',
        '$_generator extra',
        _generator.replaceFirst('LibreOfficeDev/', 'Other/'),
      ]) {
        await expectLater(
          OdtDocumentReader.readBytes(rewritten(producer)),
          throwsUnsupportedError,
        );
      }
    });
  }

  for (final attribute in ['color', 'rel-width', 'line-style']) {
    test('even LibreOffice must state active $attribute', () async {
      final bytes = _rewrite(
        OdtDocumentWriter.writeEditableZoteroBytes(_document()),
        styles: (xml) =>
            xml.replaceFirst(RegExp(' style:$attribute="[^"]*"'), ''),
        metadata: (xml) => _generatorMetadata(xml, _generator),
      );
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsUnsupportedError,
      );
    });
  }

  test(
    'physical left alignment is the normative absent adjustment default',
    () async {
      final bytes = _rewrite(
        OdtDocumentWriter.writeEditableZoteroBytes(_document()),
        styles: (xml) => xml.replaceFirst(' style:adjustment="right"', ''),
      );
      expect(
        (await OdtDocumentReader.readBytes(bytes)).footnoteSeparator!.alignment,
        WmlFootnoteSeparatorAlignment.left,
      );
    },
  );

  for (final replacement in [
    ('style:line-style="solid"', 'style:line-style="dash"'),
    ('style:line-style="solid"', 'style:line-style="dotted"'),
    ('style:width="1.00pt"', 'style:width="-1pt"'),
    ('style:width="1.00pt"', 'style:width="NaNpt"'),
    ('style:rel-width="50.000000%"', 'style:rel-width="101%"'),
    ('style:rel-width="50.000000%"', 'style:rel-width="-1%"'),
    ('style:color="#176346"', 'style:color="red"'),
    ('style:adjustment="right"', 'style:adjustment="start"'),
    (
      'style:distance-before-sep="4.00pt"',
      'style:distance-before-sep="10000pt"',
    ),
    (
      'style:width="1.00pt"',
      'style:width="1pt" foreign:setting="yes" xmlns:foreign="urn:foreign"',
    ),
  ]) {
    test(
      'refuses unsupported active separator ${replacement.$2} atomically',
      () async {
        final bytes = _rewrite(
          OdtDocumentWriter.writeEditableZoteroBytes(_document()),
          styles: (xml) {
            expect(xml, contains(replacement.$1));
            return xml.replaceFirst(replacement.$1, replacement.$2);
          },
        );
        final before = List<int>.of(bytes);
        await expectLater(
          OdtDocumentReader.readBytes(bytes),
          throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
        );
        expect(bytes, before);
      },
    );
  }

  test('conflicting active master-page separators refuse', () {
    const namespaces =
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
        'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"';
    String rule(String color) =>
        '<style:footnote-sep style:width="1pt" style:distance-before-sep="2pt" '
        'style:distance-after-sep="3pt" style:line-style="solid" style:rel-width="50%" style:color="$color"/>';
    final styles = OdtReaderStyles(
      XmlDocument.parse(
        '<office:document-content $namespaces><office:automatic-styles>'
        '<style:style style:name="A" style:family="paragraph" style:master-page-name="A"/>'
        '<style:style style:name="B" style:family="paragraph" style:master-page-name="B"/>'
        '</office:automatic-styles></office:document-content>',
      ).root!,
      styles: XmlDocument.parse(
        '<office:document-styles $namespaces><office:automatic-styles>'
        '<style:page-layout style:name="A"><style:page-layout-properties>${rule('#000000')}</style:page-layout-properties></style:page-layout>'
        '<style:page-layout style:name="B"><style:page-layout-properties>${rule('#ff0000')}</style:page-layout-properties></style:page-layout>'
        '</office:automatic-styles><office:master-styles>'
        '<style:master-page style:name="A" style:page-layout-name="A"/>'
        '<style:master-page style:name="B" style:page-layout-name="B"/>'
        '</office:master-styles></office:document-styles>',
      ).root!,
    );
    styles.paragraphProperties('A');
    styles.paragraphProperties('B');
    expect(
      () => styles.applyPageLayout(WmlSection(), hasFootnotes: true),
      throwsUnsupportedError,
    );
  });

  test(
    'retained LibreOffice prose fixture now admits an authored footnote',
    () async {
      final source = File(
        'test/fixtures/zotero/odt/native-prose.odt',
      ).readAsBytesSync();
      final bytes = _rewrite(
        source,
        content: (xml) => xml.replaceFirst(
          'Research ',
          'Research <text:note text:id="synthetic-note" text:note-class="footnote">'
              '<text:note-citation>1</text:note-citation><text:note-body>'
              '<text:p text:style-name="P1">Authored note.</text:p></text:note-body></text:note>',
        ),
      );
      final document = await OdtDocumentReader.readBytes(bytes);
      expect(document.footnotes, hasLength(1));
      expect(
        document.footnotes.single.allParagraphs.map((p) => p.text).join(),
        contains('Authored note.'),
      );
      expect(document.footnoteSeparator, isNotNull);
      expect(document.footnoteSeparator!.thickness, closeTo(0.5112, 0.000001));
      expect(document.footnoteSeparator!.relativeWidth, 0.25);
      expect(
        source,
        File('test/fixtures/zotero/odt/native-prose.odt').readAsBytesSync(),
      );
    },
  );
}
