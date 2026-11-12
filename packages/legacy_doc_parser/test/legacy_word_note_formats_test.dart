// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/note_format_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

// Independent expected values from MS-OSHARED 2.2.1.3. This is deliberately
// not imported from the production table: an index shift must fail the test.
const _formats = <int, String>{
  0x00: 'decimal',
  0x01: 'upperRoman',
  0x02: 'lowerRoman',
  0x03: 'upperLetter',
  0x04: 'lowerLetter',
  0x05: 'ordinal',
  0x06: 'cardinalText',
  0x07: 'ordinalText',
  0x08: 'hex',
  0x09: 'chicago',
  0x0a: 'ideographDigital',
  0x0b: 'japaneseCounting',
  0x0c: 'aiueo',
  0x0d: 'iroha',
  0x0e: 'decimalFullWidth',
  0x0f: 'decimalHalfWidth',
  0x10: 'japaneseLegal',
  0x11: 'japaneseDigitalTenThousand',
  0x12: 'decimalEnclosedCircle',
  0x13: 'decimalFullWidth2',
  0x14: 'aiueoFullWidth',
  0x15: 'irohaFullWidth',
  0x16: 'decimalZero',
  0x18: 'ganada',
  0x19: 'chosung',
  0x1a: 'decimalEnclosedFullstop',
  0x1b: 'decimalEnclosedParen',
  0x1c: 'decimalEnclosedCircleChinese',
  0x1d: 'ideographEnclosedCircle',
  0x1e: 'ideographTraditional',
  0x1f: 'ideographZodiac',
  0x20: 'ideographZodiacTraditional',
  0x21: 'taiwaneseCounting',
  0x22: 'ideographLegalTraditional',
  0x23: 'taiwaneseCountingThousand',
  0x24: 'taiwaneseDigital',
  0x25: 'chineseCounting',
  0x26: 'chineseLegalSimplified',
  0x27: 'chineseCountingThousand',
  0x29: 'koreanDigital',
  0x2a: 'koreanCounting',
  0x2b: 'koreanLegal',
  0x2c: 'koreanDigital2',
  0x2d: 'hebrew1',
  0x2e: 'arabicAlpha',
  0x2f: 'hebrew2',
  0x30: 'arabicAbjad',
  0x31: 'hindiVowels',
  0x32: 'hindiConsonants',
  0x33: 'hindiNumbers',
  0x34: 'hindiCounting',
  0x35: 'thaiLetters',
  0x36: 'thaiNumbers',
  0x37: 'thaiCounting',
  0x38: 'vietnameseCounting',
  0x39: 'numberInDash',
  0x3a: 'russianLower',
  0x3b: 'russianUpper',
  0xff: 'none',
};

Map<String, Uint8List> _parts(LegacyWordDocument document) => {
  for (final file in ZipDecoder().decodeBytes(
    convertLegacyWordDocument(document).bytes,
  ))
    if (file.isFile) file.name: file.content,
};

XmlDocument _xml(Map<String, Uint8List> parts) =>
    XmlDocument.parse(utf8.decode(parts['word/document.xml']!));

String? _format(XmlElement section, String kind) => section
    .getElement('${kind}Pr', namespace: _w)!
    .getElement('numFmt', namespace: _w)
    ?.getAttribute('val', namespace: _w);

XmlElement _section(Map<String, Uint8List> parts) => _xml(parts)
    .findAllElements('sectPr', namespace: _w)
    .firstWhere((e) => e.parentElement?.name.local != 'sectPrChange');

List<Map<String, dynamic>> _evidence(Map<String, Uint8List> parts) =>
    ((jsonDecode(utf8.decode(parts['word/evidence/manifest.json']!))
                as Map<String, dynamic>)['records']
            as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['kind'] == 'noteNumberFormat')
        .toList();

Uint8List _source(int foot, int end, {required bool dop}) => dop
    ? noteFormatFixture(dopFootnoteFormat: foot, dopEndnoteFormat: end)
    : noteFormatFixture(sectionProperties: noteFormatSection(foot, end));

void main() {
  for (final dop in [false, true]) {
    final source = dop ? 'DOP' : 'SEPX';
    test('$source retains all fixed note formats and explicit none', () {
      for (final entry in _formats.entries) {
        final document = parseLegacyWordDocument(
          _source(entry.key, entry.key, dop: dop),
        );
        final layout = document.sections.single.layout;
        for (final numbering in [
          layout.footnoteNumbering,
          layout.endnoteNumbering,
        ]) {
          expect(numbering.format, entry.value, reason: '$source ${entry.key}');
          expect(numbering.sourceFormatCode, entry.key);
          expect(numbering.usesDecimalFallback, isFalse);
        }
        expect(document.noteReferences, hasLength(2));
        expect(
          document.warnings,
          isNot(contains(LegacyWordWarning.unsupportedNoteNumberFormat)),
        );
        final parts = _parts(document), section = _section(parts);
        expect(_format(section, 'footnote'), entry.value);
        expect(_format(section, 'endnote'), entry.value);
        for (final kind in ['footnote', 'endnote']) {
          final noteXml = XmlDocument.parse(
            utf8.decode(parts['word/${kind}s.xml']!),
          );
          expect(
            noteXml.findAllElements('${kind}Ref', namespace: _w),
            hasLength(1),
          );
        }
      }
    });

    test('$source discloses bullet and legacy application-format fallback', () {
      final document = parseLegacyWordDocument(_source(0x17, 0x28, dop: dop));
      final layout = document.sections.single.layout;
      expect(layout.footnoteNumbering.sourceFormatCode, 0x17);
      expect(layout.endnoteNumbering.sourceFormatCode, 0x28);
      expect(layout.footnoteNumbering.usesDecimalFallback, isTrue);
      expect(layout.endnoteNumbering.usesDecimalFallback, isTrue);
      expect(
        document.warnings,
        contains(LegacyWordWarning.unsupportedNoteNumberFormat),
      );
      expect(
        convertLegacyWordDocument(document).limitations,
        contains(LegacyWordConversionLimitation.notesComments),
      );
      final parts = _parts(document), section = _section(parts);
      expect(_format(section, 'footnote'), 'decimal');
      expect(_format(section, 'endnote'), 'decimal');
      expect(
        _evidence(parts).map(
          (e) => (
            e['sourceFormatCode'],
            e['historical'],
            e['format'],
            e['usesDecimalFallback'],
          ),
        ),
        [(0x17, false, 'decimal', true), (0x28, false, 'decimal', true)],
      );
    });

    test('$source retains unknown 16-bit codes without invented formats', () {
      for (final raw in [0x3c, 0xfe, 0x100, 0xffff]) {
        final document = parseLegacyWordDocument(_source(raw, raw, dop: dop));
        final numbering = document.sections.single.layout.footnoteNumbering;
        expect(numbering.sourceFormatCode, raw);
        expect(numbering.format, isNull);
        expect(numbering.usesDecimalFallback, isFalse);
        expect(
          document.warnings,
          contains(LegacyWordWarning.unsupportedNoteNumberFormat),
        );
        final parts = _parts(document), section = _section(parts);
        expect(_format(section, 'footnote'), isNull);
        expect(_format(section, 'endnote'), isNull);
        expect(_evidence(parts).map((e) => e['sourceFormatCode']), [raw, raw]);
      }
    });
  }

  for (final size in [496, 499]) {
    test(
      'truncated DOP size $size keeps the existing complete-record gate',
      () {
        expect(
          () => parseLegacyWordDocument(
            noteFormatFixture(
              dopFootnoteFormat: 0x17,
              dopEndnoteFormat: 0xffff,
              dopSize: size,
            ),
          ),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'Word 2000 DOP stays active but Word 2002 reserved codes stay ignored',
    () {
      final old = parseLegacyWordDocument(
        noteFormatFixture(
          dopFootnoteFormat: 0x2d,
          dopEndnoteFormat: 0x30,
          dopSize: 544,
          fibNewVersion: 0xd9,
        ),
      );
      expect(old.sections.single.layout.footnoteNumbering.format, 'hebrew1');
      expect(old.sections.single.layout.endnoteNumbering.format, 'arabicAbjad');
      final current = parseLegacyWordDocument(
        noteFormatFixture(
          dopFootnoteFormat: 0x17,
          dopEndnoteFormat: 0xffff,
          dopSize: 594,
          fibNewVersion: 0x101,
          sectionProperties: noteFormatSection(0x0b, 0x37),
        ),
      );
      final layout = current.sections.single.layout;
      expect(layout.footnoteNumbering.format, 'japaneseCounting');
      expect(layout.endnoteNumbering.format, 'thaiCounting');
      expect(layout.footnoteNumbering.sourceFormatCode, 0x0b);
      expect(layout.footnoteNumbering.start, 1);
      expect(layout.endnotePosition, LegacyWordEndnotePosition.docEnd);
      expect(
        current.warnings,
        isNot(contains(LegacyWordWarning.unsupportedNoteNumberFormat)),
      );
    },
  );

  test(
    'accepting or rejecting section review keeps independent note formats',
    () {
      final document = parseLegacyWordDocument(noteFormatRevisionFixture());
      final section = _section(_parts(document));
      final oldSection = section
          .getElement('sectPrChange', namespace: _w)!
          .getElement('sectPr', namespace: _w)!;
      // Project current versus historical XML directly, without consulting the
      // parser's previousSection model or its number-format lookup.
      expect(_format(section, 'footnote'), 'none');
      expect(_format(section, 'endnote'), 'thaiCounting');
      expect(_format(oldSection, 'footnote'), 'japaneseCounting');
      expect(_format(oldSection, 'endnote'), 'hebrew1');
      final previous =
          document.sections.single.formattingRevision!.previousSection!;
      expect(previous.layout.footnoteNumbering.sourceFormatCode, 0x0b);
      expect(previous.layout.endnoteNumbering.sourceFormatCode, 0x2d);
    },
  );

  test(
    'fallback evidence identifies historical state without tainting current',
    () {
      final document = parseLegacyWordDocument(
        noteFormatRevisionFixture(fallbackHistory: true),
      );
      expect(document.sections.single.layout.footnoteNumbering.format, 'none');
      expect(
        document.sections.single.layout.footnoteNumbering.usesDecimalFallback,
        isFalse,
      );
      final record = _evidence(_parts(document)).single;
      expect(record['sourceFormatCode'], 0x17);
      expect(record['format'], 'decimal');
      expect(record['historical'], isTrue);
      expect(record['usesDecimalFallback'], isTrue);
    },
  );
}
