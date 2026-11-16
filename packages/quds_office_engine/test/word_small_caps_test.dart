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
}
