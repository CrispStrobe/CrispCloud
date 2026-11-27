import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/word_settings_io.dart';
import 'package:test/test.dart';

String display(BrokenLine line) =>
    String.fromCharCodes(line.glyphs.map((g) => g.codePoint));
double width(int cp) => cp == 0x2d ? 3 : 6;
List<BrokenLine> lines(
  String text,
  double max, {
  Iterable<int> offsets = const [],
}) => LineBreaker.breakLines(
  text: text,
  maxWidth: max,
  widthOf: width,
  justify: false,
  hyphenationOffsets: offsets,
);

void main() {
  group('licensed German patterns', () {
    test('orthographic examples and regional language selection', () {
      expect(GermanHyphenator.wordOffsets('Silbentrennung'), [3, 6, 10]);
      expect(GermanHyphenator.wordOffsets('Straße'), [4]);
      expect(GermanHyphenator.wordOffsets('Schifffahrt'), [6]);
      expect(GermanHyphenator.wordOffsets('Äpfel', language: 'de-AT'), [2]);
      expect(GermanHyphenator.wordOffsets('Bäume', language: 'de-CH'), [3]);
      expect(
        GermanHyphenator.wordOffsets('Silbentrennung', language: 'en-US'),
        isEmpty,
      );
      expect(GermanHyphenator.wordOffsets('Haus'), isEmpty);
    });
    test('decomposed umlauts preserve original UTF-16 source', () {
      const word = 'Ba\u0308ume';
      expect(GermanHyphenator.wordOffsets(word), [4]);
      expect(word.substring(0, 4), 'Ba\u0308u');
      expect(GermanHyphenator.breakOffsets('😀 $word', language: 'de-DE'), [7]);
    });
    test('manual opportunities and language boundaries are respected', () {
      expect(GermanHyphenator.wordOffsets('Sil\u00adbentrennung'), isEmpty);
      expect(
        GermanHyphenator.breakOffsets(
          'Silbentrennung',
          language: 'de-DE',
          languageAt: (i) => i < 4 ? 'de-DE' : 'en-US',
        ),
        isEmpty,
      );
      expect(GermanHyphenator.breakOffsets('Silbentrennung'), isEmpty);
    });

    test(
      'Word can consider a later German break without losing the soft hyphen',
      () {
        const word = 'ge\u00adhender';
        final automatic = OfficeHyphenator.breakOffsets(
          word,
          language: 'de-DE',
          allowGermanSoftHyphenAlternatives: true,
        );
        expect(automatic, [3, 6]);
        final breaks = LineBreaker.breakLines(
          text: word,
          maxWidth: 6,
          widthOf: (_) => 1,
          hyphenationOffsets: automatic,
          justify: false,
          balanceLines: false,
        );
        final hyphen = breaks.first.glyphs.last;
        expect(hyphen.isDiscretionaryHyphen, isTrue);
        expect(hyphen.sourceLength, 0);
        expect(hyphen.logicalIndex, 6);
        expect(OfficeHyphenator.breakOffsets(word, language: 'de-DE'), isEmpty);
      },
    );
  });
  group('source-preserving discretionary layout', () {
    test('soft hyphen is invisible and zero-width when text fits', () {
      final result = lines('Sil\u00adben', 36);
      expect(result, hasLength(1));
      expect(display(result.single), 'Silben');
      expect(result.single.width, 36);
      expect(result.single.logicalEnd, 7);
    });
    test('selected manual break consumes soft hyphen exactly once', () {
      const text = 'Sil\u00adben';
      final result = lines(text, 22);
      expect(result.map(display), ['Sil-', 'ben']);
      expect(result.map((l) => l.width), [21, 18]);
      expect(result.first.logicalEnd, 4);
      expect(result.last.logicalStart, 4);
      final hyphen = result.first.glyphs.last;
      expect(hyphen.isDiscretionaryHyphen, true);
      expect(hyphen.logicalIndex, 3);
      expect(hyphen.sourceLength, 1);
      expect(text, 'Sil\u00adben');
    });
    test('hyphen width participates in fitting instead of overflowing', () {
      final result = lines('Sil\u00adben', 19);
      expect(result, hasLength(1));
      expect(display(result.single), 'Silben');
      expect(result.single.glyphs.any((g) => g.isDiscretionaryHyphen), false);
    });
    test('automatic hyphen owns no source units and keeps end offsets', () {
      const text = 'Silben';
      final result = lines(text, 22, offsets: [3]);
      expect(result.map(display), ['Sil-', 'ben']);
      expect(result.first.logicalEnd, 3);
      expect(result.last.logicalStart, 3);
      final hyphen = result.first.glyphs.last;
      expect(hyphen.logicalIndex, 3);
      expect(hyphen.sourceLength, 0);
      expect(visualXToLogical(result.first, 20), 3);
      expect(text, 'Silben');
    });
    test('invalid candidates cannot split a surrogate pair or grapheme', () {
      final result = lines('😀a\u0308b', 12, offsets: [1, 3]);
      expect(result, hasLength(1));
      expect(result.single.glyphs.any((g) => g.isDiscretionaryHyphen), false);
    });
    test(
      'prepared variable-width layout matches fixed lines and exact consumption',
      () {
        const text = '😀 Sil\u00adben\r\nSilben';
        final offsets = [15];
        final expected = lines(text, 27, offsets: offsets);
        final prepared = LineBreaker.prepare(
          text: text,
          widthOf: width,
          justify: false,
          hyphenationOffsets: offsets,
        );
        final actual = <BrokenLine>[];
        var offset = 0;
        while (offset < text.length) {
          final next = prepared.breakNext(start: offset, maxWidth: 27);
          expect(next.nextOffset, greaterThan(offset));
          actual.add(next.line);
          offset = next.nextOffset;
        }
        expect(offset, text.length);
        expect(actual.map(display), expected.map(display));
        expect(actual.map((l) => l.width), expected.map((l) => l.width));
      },
    );
    test(
      'RTL context retains all authored glyph positions around German breaks',
      () {
        const text = 'مرحبا Silbentrennung';
        final offsets = GermanHyphenator.breakOffsets(text, language: 'de-DE');
        final result = lines(text, 48, offsets: offsets);
        final source =
            result
                .expand((l) => l.glyphs)
                .where((g) => !g.isSpace && !g.isDiscretionaryHyphen)
                .map((g) => g.logicalIndex)
                .toList()
              ..sort();
        expect(source, [
          0,
          1,
          2,
          3,
          4,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19,
        ]);
      },
    );
  });
  group('Word language and hyphenation settings', () {
    test('header tab overlays map repeated text to exact authored offsets', () {
      const text = '  Wieder\t  Wieder\tEnde\tText  ';
      final header = WmlParagraph(inlines: [WmlRun(text: text)]);
      final doc = WmlDocument.empty(text: 'Body');
      doc.sections.single.header.add(header);
      final overlays = WordLayoutEngine(
        font: null,
      ).layout(doc).pages.single.header;
      expect(overlays.map((line) => line.overlayText), [
        'Wieder',
        'Wieder',
        'Ende Text',
      ]);
      expect(
        overlays.every((line) => identical(line.sourceParagraph, header)),
        isTrue,
      );
      expect(overlays.every((line) => line.sourceText == text), isTrue);
      expect(overlays[0].proofingOffsetAt(0), text.indexOf('Wieder'));
      expect(overlays[1].proofingOffsetAt(0), text.lastIndexOf('Wieder'));
      expect(overlays[2].proofingOffsetAt(0), text.indexOf('Ende'));
      expect(overlays[2].proofingOffsetAt(4), isNull);
      expect(overlays[2].proofingOffsetAt(5), text.indexOf('Text'));
      expect(overlays[2].proofingOffsetAt(9), text.indexOf('Text') + 4);
    });

    test(
      'literal header text and generated page fields keep separate offsets',
      () {
        final header = WmlParagraph(inlines: [WmlRun(text: 'Title\t1')]);
        final headerPage = WmlParagraph(
          properties: WmlParagraphProps(pageNumberField: true),
        );
        final footer = WmlParagraph(
          properties: WmlParagraphProps(pageNumberField: true),
          inlines: [WmlRun(text: '1')],
        );
        final doc = WmlDocument.empty(text: 'Body');
        doc.sections.single
          ..header.addAll([header, headerPage])
          ..footer.add(footer);
        final page = WordLayoutEngine(font: null).layout(doc).pages.single;
        expect(page.header.first.proofingOffsetAt(0), 0);
        expect(page.header[1].overlayText, '1');
        expect(page.header[1].proofingOffsetAt(0), 6);
        expect(page.header[1].proofingOffsetAt(1), 7);
        for (final line in [page.header.last, page.footer.single]) {
          expect(line.overlayText, '1');
          expect(line.proofingOffsetAt(0), isNull);
          expect(line.proofingOffsetAt(1), isNull);
        }
      },
    );

    test(
      'native Word discretionary and nonbreaking hyphens survive import/save',
      () {
        final package = WordSerializer().write(
          WmlDocument.empty(text: 'Silben'),
        );
        final part = package.getPart('/word/document.xml')!;
        part.writeText(
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Sil</w:t><w:softHyphen/><w:t>ben</w:t><w:noBreakHyphen/><w:t>Test</w:t></w:r></w:p></w:body></w:document>',
        );
        var doc = WordDeserializer().read(package);
        for (var cycle = 0; cycle < 2; cycle++) {
          expect(doc.paragraphs.single.text, 'Sil\u00adben\u2011Test');
          final output = WordSerializer().write(doc);
          final xml = output.getPart('/word/document.xml')!.readText();
          expect(xml, contains('<w:softHyphen'));
          expect(xml, contains('<w:noBreakHyphen'));
          doc = WordDeserializer().readBytes(output.save());
        }
        final layout = lines(doc.paragraphs.single.text, 100);
        expect(display(layout.single), 'Silben\u2011Test');
      },
    );

    test('PDF paints the same break but copying omits automatic hyphens', () {
      final font = SfntFont.parse(
        File(
          '../quds_office_editor/fonts/LiberationSans-Regular.ttf',
        ).readAsBytesSync(),
      );
      final doc = WmlDocument.empty(text: 'Silbentrennung')
        ..proofingLanguage = 'de-DE'
        ..autoHyphenation = true;
      doc.sections.single.pageSize = const WmlPageSize(width: 70, height: 160);
      doc.sections.single.margins = const WmlPageMargins(
        left: 10,
        right: 10,
        top: 10,
        bottom: 10,
      );
      final layout = WordLayoutEngine(font: font).layout(doc);
      final painted = layout.pages
          .expand((p) => p.lines)
          .expand((l) => l.glyphs)
          .map((g) => g.glyph.codePoint);
      expect(painted, contains(0x2d));
      final pdf = PdfFile.open(
        OfficePdfExport.word(doc, font: font, laidOut: layout),
      );
      expect(
        PdfExtract.documentText(pdf).replaceAll('\n', ''),
        'Silbentrennung',
      );
      final outlines = pdf
          .displayList(0)
          .ops
          .whereType<PdfDrawText>()
          .map((op) => op.text)
          .join();
      expect(outlines, contains('-'));
      expect(doc.paragraphs.single.text, 'Silbentrennung');
    });

    test(
      'language edits preserve independent native language and marker metadata',
      () {
        final package = WordSerializer().write(
          WmlDocument.empty(text: 'Sprache'),
        );
        final part = package.getPart('/word/document.xml')!;
        part.writeText(
          '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:pPr><w:rPr><w:b/><w:lang w:val="de-DE" w:eastAsia="ja-JP"/></w:rPr></w:pPr><w:r><w:rPr><w:lang w:val="de-DE" w:eastAsia="zh-CN" w:bidi="ar-SA"/><w:noProof/></w:rPr><w:t>Sprache</w:t></w:r></w:p></w:body></w:document>''',
        );
        final doc = WordDeserializer().read(package);
        final p = doc.paragraphs.single;
        p.properties.proofingLanguage = 'de-AT';
        final r = p.inlines.whereType<WmlRun>().single;
        r.properties.proofingLanguage = 'de-CH';
        r.properties.noProof = false;
        final exported = WordSerializer()
            .write(doc)
            .getPart('/word/document.xml')!
            .readText();
        final root = XmlDocument.parse(exported).root!;
        final paragraph = root.firstChild('body')!.firstChild('p')!;
        final marker = paragraph.firstChild('pPr')!.firstChild('rPr')!;
        expect(marker.firstChild('b'), isNotNull);
        expect(marker.firstChild('lang')!.getAttribute('eastAsia'), 'ja-JP');
        expect(marker.firstChild('lang')!.getAttribute('val'), 'de-AT');
        final run = paragraph.firstChild('r')!.firstChild('rPr')!;
        expect(run.firstChild('lang')!.getAttribute('eastAsia'), 'zh-CN');
        expect(run.firstChild('lang')!.getAttribute('bidi'), 'ar-SA');
        expect(run.firstChild('lang')!.getAttribute('val'), 'de-CH');
        expect(run.firstChild('noProof')!.getAttribute('val'), '0');

        p.properties.proofingLanguage = null;
        final cleared = WordSerializer()
            .write(doc)
            .getPart('/word/document.xml')!
            .readText();
        final clearedMarker = XmlDocument.parse(cleared).root!
            .firstChild('body')!
            .firstChild('p')!
            .firstChild('pPr')!
            .firstChild('rPr')!;
        expect(clearedMarker.firstChild('b'), isNotNull);
        expect(clearedMarker.firstChild('lang')!.getAttribute('val'), isNull);
        expect(
          clearedMarker.firstChild('lang')!.getAttribute('eastAsia'),
          'ja-JP',
        );
      },
    );
    test(
      'proofing source identity and offsets survive note display labels',
      () {
        final source = WmlParagraph(inlines: [WmlRun(text: 'Silbentrennung')]);
        final note = WmlNote(id: 1, endnote: false, blocks: [source]);
        final doc = WmlDocument.empty(text: 'Text')
          ..footnotes.add(note)
          ..proofingLanguage = 'de-DE'
          ..autoHyphenation = true;
        doc.paragraphs.single.inlines.add(WmlRun(text: '1', noteRefId: 1));
        final layout = WordLayoutEngine(font: null).layout(doc);
        final noteLines = layout.pages
            .expand((p) => p.notes)
            .where((l) => identical(l.sourceParagraph, source))
            .toList();
        expect(noteLines, isNotEmpty);
        final mapped = noteLines
            .expand(
              (l) =>
                  l.glyphs.map((g) => l.proofingOffsetAt(g.glyph.logicalIndex)),
            )
            .whereType<int>()
            .toSet();
        expect(
          mapped,
          containsAll(List.generate(source.text.length, (i) => i)),
        );
        expect(noteLines.first.proofingOffsetAt(0), isNull);
        expect(doc.paragraphs.single.text, 'Text1');
        expect(note.text, 'Silbentrennung');
      },
    );

    test(
      'document defaults, paragraph and run overrides survive two DOCX cycles',
      () {
        var doc = WmlDocument.empty(text: 'Silbentrennung');
        doc.proofingLanguage = 'de-DE';
        doc.autoHyphenation = true;
        final p = doc.paragraphs.single;
        p.properties.proofingLanguage = 'de-AT';
        p.properties.suppressAutoHyphens = false;
        final run = p.inlines.whereType<WmlRun>().single;
        run.properties.proofingLanguage = 'de-CH';
        run.properties.noProof = true;
        for (var cycle = 0; cycle < 2; cycle++) {
          doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
          expect(doc.proofingLanguage, 'de-DE');
          expect(doc.autoHyphenation, true);
          final p = doc.paragraphs.single;
          expect(p.properties.proofingLanguage, 'de-AT');
          expect(p.properties.suppressAutoHyphens, false);
          final r = p.inlines.whereType<WmlRun>().single.properties;
          expect(r.proofingLanguage, 'de-CH');
          expect(r.noProof, true);
          expect(p.text, 'Silbentrennung');
        }
      },
    );
    test('changing document default stays live for inherited runs', () {
      final doc = WmlDocument.empty(text: 'Sprache')
        ..proofingLanguage = 'de-DE';
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(doc),
      );
      expect(
        reopened.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .proofingLanguage,
        isNull,
      );
      reopened.proofingLanguage = 'de-CH';
      WordDeserializer().refreshStyles(reopened);
      expect(reopened.proofingLanguage, 'de-CH');
      final again = WordDeserializer().readBytes(
        WordSerializer().writeBytes(reopened),
      );
      expect(again.proofingLanguage, 'de-CH');
      expect(
        again.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single
            .properties
            .proofingLanguage,
        isNull,
      );
    });
    test('settings toggle preserves other native controls and absence', () {
      expect(
        WordSettingsIo.merge(
          null,
          tracking: false,
          protection: false,
          oddEven: false,
        ),
        isNull,
      );
      const source =
          '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:zoom w:percent="125"/><w:autoHyphenation/><w:doNotHyphenateCaps w:val="1"/><w:hyphenationZone w:val="360"/></w:settings>';
      final unchanged = WordSettingsIo.merge(
        source,
        tracking: false,
        protection: false,
        oddEven: false,
      );
      expect(unchanged, source);
      final changed = WordSettingsIo.merge(
        source,
        tracking: false,
        protection: false,
        oddEven: false,
        autoHyphenation: false,
      )!;
      expect(WordSettingsIo.read(changed).autoHyphenation, false);
      expect(changed, contains('percent="125"'));
      expect(changed, contains('doNotHyphenateCaps'));
      expect(changed, contains('hyphenationZone'));
    });
    test(
      'Word layout uses document setting and paragraph suppression without editing source',
      () {
        final doc = WmlDocument.empty(text: 'Silbentrennung')
          ..proofingLanguage = 'de-DE'
          ..autoHyphenation = true;
        doc.sections.single.pageSize = const WmlPageSize(
          width: 80,
          height: 180,
        );
        doc.sections.single.margins = const WmlPageMargins(
          left: 10,
          right: 10,
          top: 10,
          bottom: 10,
        );
        final pages = WordLayoutEngine(font: null).layout(doc).pages;
        expect(
          pages
              .expand((p) => p.lines)
              .expand((l) => l.glyphs)
              .any((g) => g.glyph.isDiscretionaryHyphen),
          true,
        );
        expect(doc.paragraphs.single.text, 'Silbentrennung');
        doc.paragraphs.single.properties.suppressAutoHyphens = true;
        final suppressed = WordLayoutEngine(font: null).layout(doc).pages;
        expect(
          suppressed
              .expand((p) => p.lines)
              .expand((l) => l.glyphs)
              .any((g) => g.glyph.isDiscretionaryHyphen),
          false,
        );
      },
    );
  });
}
