import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test('canonical German language aliases stay homogeneous across runs', () {
    for (final language in ['de', 'de-DE', ' DE_de ', 'de-1996']) {
      expect(GermanHyphenator.supports(language), isTrue);
      expect(
        GermanHyphenator.wordOffsets('Silbentrennung', language: language),
        [3, 6, 10],
      );
      expect(
        GermanHyphenator.breakOffsets(
          'Silbentrennung',
          languageAt: (offset) => offset < 5 ? language : 'de-DE',
        ),
        [3, 6, 10],
      );
    }
    for (final language in ['de-AT', 'de-CH', 'en-US', 'fr-FR']) {
      expect(
        GermanHyphenator.breakOffsets(
          'Silbentrennung',
          languageAt: (offset) => offset < 5 ? 'de-DE' : language,
        ),
        isEmpty,
      );
    }
  });

  test('German technical tokens never gain automatic lexical breaks', () {
    for (final text in [
      'HTTPS://Silbentrennung.example/Straße',
      'www.Silbentrennung.example',
      'Büro@Silbentrennung.example',
      'Silbentrennung@ba\u0308r.de',
      "https://example.invalid/'Silbentrennung",
      "https://example.invalid/a'/Silbentrennung",
      '`Silbentrennung`',
      '``Silbentrennung `Straße` Schifffahrt``',
      '```Silbentrennung\nSchifffahrt```',
      'Silbentrennung123',
      '123Silbentrennung',
      'Silbentrennung_name',
      'name_Silbentrennung',
      'Silbentrennung\u203fSchifffahrt',
      '\u{1d7d8}Silbentrennung',
      'Silbentrennung\u{1d7d8}',
      "Silbentrennung's",
      'Silbentrennung’s',
      'Silbentrennungʼs',
    ]) {
      expect(
        GermanHyphenator.breakOffsets(text, language: 'de-DE'),
        isEmpty,
        reason: text,
      );
      expect(
        OfficeHyphenator.breakOffsets(text, language: 'de-DE'),
        isEmpty,
        reason: text,
      );
    }
  });

  test('German join controls protect both adjoining word fragments', () {
    for (final joiner in ['\u200c', '\u200d', '\u2060', '\ufeff']) {
      expect(
        GermanHyphenator.breakOffsets(
          'Silbentrennung${joiner}Schifffahrt',
          language: 'de-DE',
        ),
        isEmpty,
      );
    }
    expect(
      GermanHyphenator.breakOffsets(
        'Silbentrennung\u200bSchifffahrt',
        language: 'de-DE',
      ),
      [3, 6, 10, 21],
    );
  });

  test(
    'surrounding prose, quotes and explicit compounds remain hyphenatable',
    () {
      const text = '😀 „Silbentrennung“ (https://example.invalid). Schifffahrt';
      final last = text.indexOf('Schifffahrt');
      expect(GermanHyphenator.breakOffsets(text, language: 'de-DE'), [
        7,
        10,
        14,
        last + 6,
      ]);
      expect(
        GermanHyphenator.breakOffsets('`Silbentrennung', language: 'de-DE'),
        [4, 7, 11],
      );
      expect(
        GermanHyphenator.breakOffsets(
          'Silbentrennung-Schifffahrt',
          language: 'de-DE',
        ),
        [3, 6, 10, 21],
      );
    },
  );

  test('mixed English and German runs share protected source ranges', () {
    const text = 'dictionary `Silbentrennung dictionary` Silbentrennung';
    final last = text.lastIndexOf('Silbentrennung');
    expect(
      OfficeHyphenator.breakOffsets(
        text,
        languageAt: (offset) => offset < 10 ? 'en-US' : 'de-DE',
      ),
      [3, 6, last + 3, last + 6, last + 10],
    );
  });

  test('Word layout protects German URLs without changing authored text', () {
    const text = 'https://Silbentrennung.example/Schifffahrt';
    final document = WmlDocument.empty(text: text)
      ..proofingLanguage = 'de-DE'
      ..autoHyphenation = true;
    document.sections.single.pageSize = const WmlPageSize(
      width: 80,
      height: 180,
    );
    document.sections.single.margins = const WmlPageMargins(
      left: 10,
      right: 10,
      top: 10,
      bottom: 10,
    );
    final glyphs = WordLayoutEngine(font: null)
        .layout(document)
        .pages
        .expand((page) => page.lines)
        .expand((line) => line.glyphs);
    expect(glyphs.any((glyph) => glyph.glyph.isDiscretionaryHyphen), isFalse);
    expect(document.paragraphs.single.text, text);
  });
}
