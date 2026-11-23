import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _document(String text) {
  final document = WmlDocument.empty(text: text);
  document.paragraphs.single.inlines.whereType<WmlRun>().single.properties =
      WmlRunProps(smallCaps: true, fontSizeHalfPoints: 20);
  return document;
}

void main() {
  test(
    'CSL small capitals inherit, reset and restore without changing text',
    () {
      final rich = ZoteroFormattedText.fromHtml(
        '<span style="font-variant:small-caps">Müller '
        '<i>Book</i><span style="font-variant-caps:normal"> Reset</span>'
        ' Again</span> plain',
      );
      expect(rich.plainText, 'Müller Book Reset Again plain');
      expect(rich.unsupportedFormatting, isEmpty);
      expect(rich.hasUniformCharacterFormatting, isFalse);
      expect(rich.toRuns().map((r) => (r.text, r.properties.smallCaps)), [
        ('Müller', true),
        (' Book', true),
        (' Reset', false),
        (' Again', true),
        (' plain', false),
      ]);
      expect(rich.toRuns()[1].properties.italic, isTrue);
      expect(
        ZoteroFormattedText.fromHtml('plain')
            .toRuns(baseProperties: WmlRunProps(smallCaps: true))
            .single
            .properties
            .smallCaps,
        isFalse,
      );
      for (final variant in [
        'all-small-caps',
        'petite-caps',
        'small-caps garbage',
      ]) {
        expect(
          ZoteroFormattedText.fromHtml(
            '<span style="font-variant:$variant">x</span>',
          ).unsupportedFormatting,
          contains('unsupported inline style'),
        );
      }
    },
  );

  test(
    'native small-capital properties and explicit resets survive repeated saves',
    () async {
      var document = WmlDocument.empty();
      document.paragraphs.single.inlines
        ..clear()
        ..addAll([
          WmlRun(text: 'Small', properties: WmlRunProps(smallCaps: true)),
          WmlRun(text: ' Normal', properties: WmlRunProps()),
        ]);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        final xml = OpcPackage.openBytes(
          bytes,
        ).getPart('/word/document.xml')!.readText();
        expect(xml, contains('<w:smallCaps w:val="1"'));
        expect(xml, contains('<w:smallCaps w:val="0"'));
        document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.single.text, 'Small Normal');
        expect(
          document.paragraphs.single.inlines.whereType<WmlRun>().map(
            (r) => r.properties.smallCaps,
          ),
          [true, false],
        );
      }
    },
  );

  test('native style inheritance and direct off remain sparse after edits', () {
    final package = OpcPackage.create(OpcPackageKind.word);
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      utf8.encode('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
 <w:style w:type="paragraph" w:styleId="Caps"><w:name w:val="Caps"/>
  <w:rPr><w:smallCaps/></w:rPr></w:style>
</w:styles>'''),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
    package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
 <w:pPr><w:pStyle w:val="Caps"/></w:pPr>
 <w:r><w:t>Inherited</w:t></w:r>
 <w:r><w:rPr><w:smallCaps w:val="0"/></w:rPr><w:t> Off</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
    var document = WordDeserializer().read(package);
    var runs = document.paragraphs.single.inlines.whereType<WmlRun>().toList();
    expect(runs.map((r) => r.properties.smallCaps), [true, false]);
    runs.first.properties.smallCaps = false;
    WordDeserializer().refreshStyles(document);
    expect(
      document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .first
          .properties
          .smallCaps,
      isFalse,
    );
    document = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    runs = document.paragraphs.single.inlines.whereType<WmlRun>().toList();
    expect(runs.map((r) => r.properties.smallCaps), [false, false]);
    expect(document.paragraphs.single.text, 'Inherited Off');
  });

  test('run copying, split and coalescing keep small-capital boundaries', () {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Small', properties: WmlRunProps(smallCaps: true)),
        WmlRun(text: 'Normal'),
      ],
    );
    WmlRunEdit.splitAt(paragraph, 2);
    expect(
      paragraph.inlines.whereType<WmlRun>().map((r) => r.properties.smallCaps),
      [true, true, false],
    );
    WmlRunEdit.coalesce(paragraph);
    expect(
      paragraph.inlines.whereType<WmlRun>().map(
        (r) => (r.text, r.properties.smallCaps),
      ),
      [('Small', true), ('Normal', false)],
    );
    final clones = WmlClone.inlines(paragraph.inlines).cast<WmlRun>();
    expect(clones.first.properties.smallCaps, isTrue);
    clones.first.properties.smallCaps = false;
    expect((paragraph.inlines.first as WmlRun).properties.smallCaps, isTrue);
  });

  test(
    'a derived Word heading style can turn off inherited small capitals',
    () {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.createPart(
        '/word/styles.xml',
        OfficeContentTypes.wordStyles,
        utf8.encode('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
 <w:style w:type="paragraph" w:styleId="Base">
  <w:rPr><w:smallCaps/></w:rPr>
 </w:style>
 <w:style w:type="paragraph" w:styleId="Derived">
  <w:basedOn w:val="Base"/><w:rPr><w:smallCaps w:val="0"/></w:rPr>
 </w:style>
</w:styles>'''),
      );
      package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
      package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
 <w:p><w:pPr><w:pStyle w:val="Base"/></w:pPr><w:r><w:t>Base heading</w:t></w:r></w:p>
 <w:p><w:pPr><w:pStyle w:val="Derived"/></w:pPr><w:r><w:t>Derived heading</w:t></w:r></w:p>
 <w:sectPr/>
</w:body></w:document>''');

      final imported = WordDeserializer().read(package);
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(imported),
      );
      for (final document in [imported, reopened]) {
        final paragraphs = document.paragraphs.toList();
        expect(
          paragraphs.map(
            (p) => p.inlines.whereType<WmlRun>().single.properties.smallCaps,
          ),
          [true, false],
        );
        expect(
          paragraphs.map((p) => p.properties.importedParagraphMark?.smallCaps),
          [true, false],
        );
        final lines = WordLayoutEngine(
          font: null,
        ).layout(document).pages.single.lines;
        expect(lines.last.text, 'Derived heading');
      }
    },
  );

  test(
    'mixed native citation retains authored letters, metadata and protection',
    () {
      final rich = ZoteroFormattedText.fromHtml(
        '<span style="font-variant:small-caps">Müller</span>, 12',
      );
      final citation = ZoteroCitation(
        citationId: 'small-capital-citation',
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
      WordZotero.insertNativeCitation(
        document.paragraphs.single,
        instruction: citation.fieldInstruction,
        text: rich.plainText,
        formattedText: rich,
        index: 7,
      );
      WmlRunEdit.replaceRange(document.paragraphs.single, 9, 9, '!');
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final field = WordZotero.fields(document).single;
      expect(field.cachedText, 'Müller, 12');
      expect(field.citation!.items.single.locator, '12');
      expect(field.canEdit, isTrue);
      expect(document.paragraphs.single.text, 'Before Müller, 12! after');
      expect(
        field.paragraph.inlines
            .whereType<WmlRun>()
            .singleWhere((r) => r.text == 'Müller')
            .properties
            .smallCaps,
        isTrue,
      );
      expect(WordFieldSpans.unbalanced(document), isEmpty);
    },
  );

  test('synthetic capitals use uppercase widths before line breaking', () {
    final document = _document('Smith 12');
    final calls = <(int, double)>[];
    final layout = WordLayoutEngine(
      font: null,
      measure: (cp, size, props) {
        calls.add((cp, size));
        return size / 2;
      },
    ).layout(document);
    final glyphs = layout.pages.single.lines.single.glyphs;
    expect(
      String.fromCharCodes(glyphs.map((g) => g.glyph.codePoint)),
      'SMITH 12',
    );
    expect(glyphs.map((g) => g.fontSize), [10, 8, 8, 8, 8, 10, 10, 10]);
    expect(glyphs.map((g) => g.glyph.logicalIndex), [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(glyphs.map((g) => g.logicalEnd), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(calls, contains(('M'.codeUnitAt(0), 8)));
    expect(document.paragraphs.single.text, 'Smith 12');
  });

  test(
    'graphemes, Unicode expansion and supplementary letters keep source ranges',
    () {
      const source = 'a\u0301ßﬃ𐐨 مرحبا';
      final document = _document(source);
      final glyphs = WordLayoutEngine(
        font: null,
      ).layout(document).pages.single.lines.single.glyphs;
      for (final segment in WordSmallCaps.segments(
        source,
      ).where((s) => s.scale != 1)) {
        final group = glyphs
            .where((g) => g.glyph.logicalIndex == segment.start)
            .toList();
        expect(group.map((g) => g.glyph.codePoint), segment.text.runes);
        expect(group.every((g) => g.logicalEnd == segment.end), isTrue);
        expect(group.every((g) => g.displayText == segment.text), isTrue);
        expect(group.every((g) => g.fontSize == 8), isTrue);
        var displayOffset = 0;
        for (final glyph in group) {
          expect(glyph.displayOffset, displayOffset);
          displayOffset += glyph.glyph.codePoint > 0xffff ? 2 : 1;
        }
      }
      expect(document.paragraphs.single.text, source);
      expect(
        glyphs.every(
          (g) => g.glyph.logicalIndex >= 0 && g.logicalEnd <= source.length,
        ),
        isTrue,
      );
    },
  );

  test('full uppercase display retains marks and uppercase letter size', () {
    final segments = WordSmallCaps.segments('ßﬃև\u1ffcα\u0345\u0301');
    expect(segments.map((s) => (s.text, s.scale)), [
      ('SS', 0.8),
      ('FFI', 0.8),
      ('ԵՒ', 0.8),
      ('ΩΙ', 1.0),
      ('Α\u0301Ι', 0.8),
    ]);
  });

  test(
    'narrow cells never split a display expansion or duplicate PDF text',
    () {
      final paragraph = _document('aßﬃb').paragraphs.single;
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                grid: [18],
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(blocks: [paragraph]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final lines = WordLayoutEngine(
        font: null,
        measure: (cp, size, props) => size / 2,
      ).layout(document).pages.expand((page) => page.lines).toList();
      expect(lines.length, greaterThan(1));
      for (final (index, count) in [(0, 1), (1, 2), (2, 3), (3, 1)]) {
        final owners = lines
            .where(
              (line) => line.glyphs.any((g) => g.glyph.logicalIndex == index),
            )
            .toList();
        expect(owners, hasLength(1));
        final glyphs = owners.single.glyphs.where(
          (g) => g.glyph.logicalIndex == index,
        );
        expect(glyphs, hasLength(count));
        expect(glyphs.every((g) => g.logicalEnd == index + 1), isTrue);
      }
      final font = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final pdf = PdfFile.open(OfficePdfExport.word(document, font: font));
      expect(PdfExtract.documentText(pdf).replaceAll('\n', ''), 'aßﬃb');
    },
  );

  test('PDF paints actual capital outlines at the same scaled sizes', () {
    final font = SfntFont.parse(
      File(
        '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
      ).readAsBytesSync(),
    );
    final document = _document('Smith');
    final glyphs = WordLayoutEngine(
      font: font,
    ).layout(document).pages.single.lines.single.glyphs;
    for (final glyph in glyphs) {
      expect(glyph.glyph.glyphId, font.glyphIdFor(glyph.glyph.codePoint));
      expect(
        glyph.advance,
        closeTo(
          FontMetrics(
            font: font,
            fontSizePoints: glyph.fontSize,
          ).characterWidth(glyph.glyph.codePoint),
          0.000001,
        ),
      );
    }
    final pdf = PdfFile.open(OfficePdfExport.word(document, font: font));
    final painted = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(painted.map((op) => op.text).join(), 'SMITH');
    expect(painted.map((op) => op.size), [10, 8, 8, 8, 8]);
    expect(painted.every((op) => op.fontBytes != null), isTrue);
    expect(PdfExtract.pageText(pdf, 0), 'Smith');
    expect(document.paragraphs.single.text, 'Smith');
  });

  for (final endnote in [false, true]) {
    test(
      'PDF preserves authored expansions and ${endnote ? 'endnote' : 'footnote'} text',
      () {
        final font = SfntFont.parse(
          File(
            '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
          ).readAsBytesSync(),
        );
        final document = _document('Straße ﬃ');
        document.paragraphs.single.inlines.add(
          WmlRun(
            text: '42',
            noteRefId: 42,
            noteRefEndnote: endnote,
            properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
          ),
        );
        (endnote ? document.endnotes : document.footnotes).add(
          WmlNote(
            id: 42,
            endnote: endnote,
            paragraphs: [
              WmlParagraph(
                inlines: [
                  WmlRun(
                    text: 'Müller',
                    properties: WmlRunProps(smallCaps: true),
                  ),
                ],
              ),
            ],
          ),
        );
        final pdf = PdfFile.open(OfficePdfExport.word(document, font: font));
        final painted = [
          for (var page = 0; page < pdf.pageCount; page++)
            ...pdf.displayList(page).ops.whereType<PdfDrawText>(),
        ].map((op) => op.text).join();
        expect(painted, contains('STRASSE FFI'));
        expect(painted, contains('MÜLLER'));
        final extracted = PdfExtract.documentText(pdf);
        expect(extracted, contains('Straße ﬃ'));
        expect(extracted, contains('Müller'));
        expect('ß'.allMatches(extracted), hasLength(1));
        expect('ﬃ'.allMatches(extracted), hasLength(1));
      },
    );
  }
}
