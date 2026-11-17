import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

String _display(BrokenLine line) =>
    String.fromCharCodes(line.glyphs.map((glyph) => glyph.codePoint));

void main() {
  group('licensed English patterns', () {
    test('American and British patterns preserve distinct break choices', () {
      expect(EnglishHyphenator.wordOffsets('dictionary'), [3, 6]);
      expect(EnglishHyphenator.wordOffsets('dictionary', language: 'en-GB'), [
        3,
        7,
      ]);
      expect(EnglishHyphenator.wordOffsets('hyphenation'), [2, 6]);
      expect(EnglishHyphenator.wordOffsets('hyphenation', language: 'en-GB'), [
        2,
        6,
        7,
      ]);
      expect(EnglishHyphenator.wordOffsets('internationalization'), [
        2,
        5,
        7,
        11,
        13,
        16,
      ]);
      expect(
        EnglishHyphenator.wordOffsets(
          'internationalisation',
          language: 'en-GB',
        ),
        [2, 5, 7, 11, 13, 16],
      );
    });

    test('only explicitly supported dialects receive automatic candidates', () {
      for (final language in ['en', 'en-US', 'EN_us', ' en-US ']) {
        expect(EnglishHyphenator.supports(language), isTrue);
        expect(
          EnglishHyphenator.wordOffsets('dictionary', language: language),
          [3, 6],
        );
      }
      for (final language in <String?>[
        null,
        '',
        'en-CA',
        'en-AU',
        'en-IN',
        'en-NZ',
        'de-DE',
        'fr-FR',
      ]) {
        expect(EnglishHyphenator.supports(language), isFalse);
        expect(
          EnglishHyphenator.wordOffsets('dictionary', language: language),
          isEmpty,
        );
      }
      expect(EnglishHyphenator.breakOffsets('dictionary'), isEmpty);
    });

    test(
      'US upstream exceptions override patterns including no-break entries',
      () {
        const exceptions = <String, List<int>>{
          'associate': [2, 4],
          'associates': [2, 4],
          'declination': [3, 5, 7],
          'obligatory': [5, 6],
          'philanthropic': [4, 6],
          'present': [],
          'presents': [],
          'project': [],
          'projects': [],
          'reciprocity': [4],
          'recognizance': [2, 5, 7],
          'reformation': [3, 5, 7],
          'retribution': [3, 5, 7],
          'table': [2],
        };
        for (final entry in exceptions.entries) {
          expect(
            EnglishHyphenator.wordOffsets(entry.key),
            entry.value,
            reason: entry.key,
          );
        }
      },
    );

    test('British upstream exceptions remain unchanged', () {
      const exceptions = <String, List<int>>{
        'university': [3, 6],
        'universities': [3, 6, 9],
        'however': [3],
        'manuscript': [2, 4],
        'manuscripts': [2, 4],
        'reciprocity': [2, 4, 7],
        'throughout': [7],
        'something': [4],
      };
      for (final entry in exceptions.entries) {
        expect(
          EnglishHyphenator.wordOffsets(entry.key, language: 'en-GB'),
          entry.value,
          reason: entry.key,
        );
      }
      expect(EnglishHyphenator.wordOffsets('project', language: 'en-GB'), [3]);
    });

    test('English minimum fragments are two before and three after', () {
      for (final language in ['en-US', 'en-GB']) {
        for (final word in [
          'table',
          'British',
          'grammar',
          'dictionary',
          'hyphenation',
          'internationalization',
          'internationalisation',
          'representation',
          'algorithm',
          'extraordinary',
        ]) {
          for (final offset in EnglishHyphenator.wordOffsets(
            word,
            language: language,
          )) {
            expect(offset, greaterThanOrEqualTo(2), reason: word);
            expect(word.length - offset, greaterThanOrEqualTo(3), reason: word);
          }
        }
      }
      expect(EnglishHyphenator.wordOffsets('four'), isEmpty);
      expect(EnglishHyphenator.wordOffsets('color'), isEmpty);
      expect(EnglishHyphenator.wordOffsets('British', language: 'en-GB'), [4]);
    });

    test(
      'casing does not change positions or expose mutable cache storage',
      () {
        expect(EnglishHyphenator.wordOffsets('DICTIONARY'), [3, 6]);
        expect(EnglishHyphenator.wordOffsets('Dictionary'), [3, 6]);
        final offsets = EnglishHyphenator.wordOffsets('dictionary')..clear();
        expect(offsets, isEmpty);
        expect(EnglishHyphenator.wordOffsets('dictionary'), [3, 6]);
      },
    );

    test('manual hyphens and non-ASCII words are not partially normalized', () {
      for (final word in [
        'dic\u00adtionary',
        'dictiona\u0308ry',
        'dictionäry',
        "dictionary's",
        'dictionary’s',
        'dictionaryʼs',
        'dictionary1',
        'dictionary_name',
        'dictionary\u200d',
        '😀dictionary',
        'a' * 129,
      ]) {
        expect(EnglishHyphenator.wordOffsets(word), isEmpty, reason: word);
      }
    });

    test(
      'paragraph offsets retain emoji prefixes and surrounding quotation',
      () {
        const text = '😀 “dictionary” ‘hyphenation’';
        expect(EnglishHyphenator.breakOffsets(text, language: 'en-US'), [
          7,
          10,
          19,
          23,
        ]);
        expect(text.substring(4, 14), 'dictionary');
        expect(text.substring(17, 28), 'hyphenation');
      },
    );

    test(
      'apostrophes keep contractions whole while compounds use components',
      () {
        for (final text in [
          "dictionary's",
          'dictionary’s',
          'dictionaryʼs',
          "internationalization's",
        ]) {
          expect(
            EnglishHyphenator.breakOffsets(text, language: 'en-US'),
            isEmpty,
            reason: text,
          );
        }
        expect(
          EnglishHyphenator.breakOffsets(
            'dictionary-based',
            language: 'en-US',
          ).where((offset) => offset < 10),
          [3, 6],
        );
        expect(
          EnglishHyphenator.breakOffsets("'dictionary'", language: 'en-US'),
          [4, 7],
        );
      },
    );

    test(
      'identifiers and number-adjacent fragments are not ordinary words',
      () {
        for (final text in [
          'dictionary123',
          '123dictionary',
          'dictionary_name',
          'name_dictionary',
          'dictionary\u203fhyphenation',
          'dictionary@grammar',
          '\u{1d7d8}dictionary',
          'dictionary\u{1d7d8}',
        ]) {
          expect(
            EnglishHyphenator.breakOffsets(text, language: 'en-US'),
            isEmpty,
            reason: text,
          );
        }
      },
    );

    test(
      'URL, email and closed backtick spans do not gain dictionary breaks',
      () {
        for (final text in [
          'HTTPS://internationalization.example/dictionary',
          'www.internationalization.example',
          'internationalization@dictionary.example',
          '`dictionary`',
          '``dictionary``',
          '```dictionary\nhyphenation```',
          '``dictionary `hyphenation` organization``',
        ]) {
          expect(
            EnglishHyphenator.breakOffsets(text, language: 'en-US'),
            isEmpty,
            reason: text,
          );
        }
        const prose = 'dictionary (HTTPS://example.invalid). hyphenation';
        final start = prose.indexOf('hyphenation');
        expect(EnglishHyphenator.breakOffsets(prose, language: 'en-US'), [
          3,
          6,
          start + 2,
          start + 6,
        ]);
        expect(
          EnglishHyphenator.breakOffsets('`dictionary', language: 'en-US'),
          [4, 7],
        );
        expect(
          EnglishHyphenator.breakOffsets('``dictionary`', language: 'en-US'),
          [5, 8],
        );
      },
    );

    test('join controls suppress adjoining lexical fragments', () {
      for (final joiner in ['\u200c', '\u200d', '\u2060', '\ufeff']) {
        expect(
          EnglishHyphenator.breakOffsets(
            'dictionary${joiner}hyphenation',
            language: 'en-US',
          ),
          isEmpty,
        );
      }
      expect(
        EnglishHyphenator.breakOffsets(
          'dictionary\u200bhyphenation',
          language: 'en-US',
        ),
        [3, 6, 13, 17],
      );
    });

    test('unqualified English and US aliases share the same dialect', () {
      expect(
        EnglishHyphenator.breakOffsets(
          'dictionary',
          languageAt: (offset) => offset < 4 ? 'en' : 'en-US',
        ),
        [3, 6],
      );
    });

    test('words crossing run language boundaries receive no candidates', () {
      expect(
        EnglishHyphenator.breakOffsets(
          'dictionary',
          language: 'en-US',
          languageAt: (offset) => offset < 4 ? 'en-US' : 'en-GB',
        ),
        isEmpty,
      );
      expect(
        EnglishHyphenator.breakOffsets(
          'dictionary',
          language: 'en-US',
          languageAt: (offset) => offset < 4 ? 'en-US' : 'de-DE',
        ),
        isEmpty,
      );
      expect(
        EnglishHyphenator.breakOffsets(
          'dictionary',
          languageAt: (_) => 'EN_us',
        ),
        [3, 6],
      );
    });
  });

  group('English and German shared layout dispatch', () {
    test(
      'mixed paragraphs return sorted UTF-16 candidates in each language',
      () {
        const text = 'dictionary Silbentrennung dictionary';
        expect(
          OfficeHyphenator.breakOffsets(
            text,
            languageAt: (offset) {
              if (offset < 11) return 'en-US';
              if (offset < 25) return 'de-DE';
              return 'en-GB';
            },
          ),
          [3, 6, 14, 17, 21, 29, 33],
        );
        expect(OfficeHyphenator.supports('de-CH'), isTrue);
        expect(OfficeHyphenator.supports('en-GB'), isTrue);
        expect(OfficeHyphenator.supports('fr-FR'), isFalse);
        expect(
          OfficeHyphenator.wordOffsets('Silbentrennung', language: 'de-DE'),
          GermanHyphenator.wordOffsets('Silbentrennung'),
        );
        expect(
          OfficeHyphenator.breakOffsets('dictionary', language: 'fr-FR'),
          isEmpty,
        );
      },
    );

    test('English selected hyphens own no authored units', () {
      const text = 'dictionary';
      final lines = LineBreaker.breakLines(
        text: text,
        maxWidth: 27,
        widthOf: (cp) => cp == 0x2d ? 3 : 6,
        justify: false,
        hyphenationOffsets: OfficeHyphenator.breakOffsets(
          text,
          language: 'en-US',
        ),
      );
      expect(lines.map(_display), ['dic-', 'tio-', 'nary']);
      expect(lines.map((line) => line.logicalStart), [0, 3, 6]);
      expect(lines.map((line) => line.logicalEnd), [3, 6, 10]);
      final hyphens = lines
          .expand((line) => line.glyphs)
          .where((glyph) => glyph.isDiscretionaryHyphen);
      expect(hyphens, hasLength(2));
      expect(hyphens.every((glyph) => glyph.sourceLength == 0), isTrue);
      expect(text, 'dictionary');
    });

    test(
      'Word layout dispatches English defaults and paragraph suppression',
      () {
        final doc = WmlDocument.empty(text: 'internationalization')
          ..proofingLanguage = 'en-US'
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
        bool hasHyphen() => WordLayoutEngine(font: null)
            .layout(doc)
            .pages
            .expand((page) => page.lines)
            .expand((line) => line.glyphs)
            .any((glyph) => glyph.glyph.isDiscretionaryHyphen);
        expect(hasHyphen(), isTrue);
        expect(doc.paragraphs.single.text, 'internationalization');
        doc.paragraphs.single.properties.suppressAutoHyphens = true;
        expect(hasHyphen(), isFalse);
        doc.paragraphs.single.properties.suppressAutoHyphens = false;
        doc.proofingLanguage = 'en-CA';
        expect(hasHyphen(), isFalse);
      },
    );
  });
}
