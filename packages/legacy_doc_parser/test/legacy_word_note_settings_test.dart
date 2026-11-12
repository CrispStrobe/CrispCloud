// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Uint8List _dop({
  int length = 500,
  int footPosition = 1,
  int endPosition = 3,
  int footStart = 1,
  int endStart = 1,
  int footRestart = 0,
  int endRestart = 0,
  int footFormat = 0,
  int endFormat = 2,
}) {
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  // Literal DopBase bit positions and Dop97 offsets are independently
  // authored from MS-DOC 2.7.2/2.7.4, rather than a serializer under test.
  bytes[0] = footPosition << 5;
  data.setUint16(2, (footStart << 2) | footRestart, Endian.little);
  data.setUint16(52, (endStart << 2) | endRestart, Endian.little);
  bytes[54] = endPosition;
  if (length >= 496) {
    data.setUint16(492, footFormat, Endian.little);
    data.setUint16(494, endFormat, Endian.little);
  }
  return bytes;
}

Uint8List _source({
  Uint8List? dop,
  int version = 0xc1,
  int? newVersion,
  int pairs = 93,
  List<List<int>> sectionProperties = const [],
}) {
  final text = sectionProperties.length == 2 ? 'A\fB\r' : 'A\r';
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text)],
    extraTablePairs: {if (dop != null) 31: dop},
    sections: [
      for (var i = 0; i < sectionProperties.length; i++)
        WordFixtureSection((i + 1) * 2, sectionProperties[i]),
    ],
  ).build(
    mutate: (word, table) {
      word.setUint16(2, version, Endian.little);
      word.setUint16(152, pairs, Endian.little);
      final extension = 154 + pairs * 8;
      word.setUint16(
        extension,
        newVersion == null
            ? 0
            : newVersion == 0x112
            ? 5
            : 2,
        Endian.little,
      );
      if (newVersion != null) {
        word.setUint16(extension + 2, newVersion, Endian.little);
      }
    },
  );
}

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};

XmlDocument _xml(Map<String, Uint8List> parts, String path) =>
    XmlDocument.parse(utf8.decode(parts[path]!));

Iterable<XmlElement> _elements(XmlNode node, String name) =>
    node.findAllElements(name, namespace: _w);

String? _value(XmlNode node, String name) =>
    _elements(node, name).single.getAttribute('val', namespace: _w);

void main() {
  test('absent note settings use documented defaults', () {
    final parsed = parseLegacyWordDocument(_source());
    expect(parsed.footnotes.position, LegacyWordFootnotePosition.pageBottom);
    expect(parsed.footnotes.numbering.startAt, 1);
    expect(
      parsed.footnotes.numbering.format,
      LegacyWordNoteNumberFormat.decimal,
    );
    expect(parsed.endnotes.position, LegacyWordEndnotePosition.documentEnd);
    expect(
      parsed.endnotes.numbering.format,
      LegacyWordNoteNumberFormat.lowerRoman,
    );
    expect(parsed.sections.single.footnotes, isNull);
    final package = _parts(convertLegacyWordToStructuredDocx(_source()).bytes);
    final settings = _xml(package, 'word/settings.xml');
    final foot = _elements(settings, 'footnotePr').single;
    final end = _elements(settings, 'endnotePr').single;
    expect(_value(foot, 'pos'), 'pageBottom');
    expect(_value(end, 'pos'), 'docEnd');
    expect(_value(end, 'numFmt'), 'lowerRoman');
    expect(_value(foot, 'numStart'), '1');
    expect(_value(foot, 'numRestart'), 'continuous');
  });

  test(
    'legacy DOP numbering, independent formats and positions survive DOCX',
    () {
      final source = _source(
        dop: _dop(
          footPosition: 2,
          endPosition: 0,
          footStart: 4,
          endStart: 9,
          footRestart: 1,
          endRestart: 0,
          footFormat: 2,
          endFormat: 3,
        ),
      );
      final original = Uint8List.fromList(source);
      final parsed = parseLegacyWordDocument(source);
      expect(parsed.footnotes.numbering.startAt, 4);
      expect(
        parsed.footnotes.numbering.restart,
        LegacyWordNoteRestart.eachSection,
      );
      expect(parsed.footnotes.position, LegacyWordFootnotePosition.beneathText);
      expect(parsed.endnotes.position, LegacyWordEndnotePosition.sectionEnd);
      final package = _parts(convertLegacyWordToStructuredDocx(source).bytes);
      final settings = _xml(package, 'word/settings.xml');
      final foot = _elements(settings, 'footnotePr').single;
      final end = _elements(settings, 'endnotePr').single;
      expect(_value(foot, 'numFmt'), 'lowerRoman');
      expect(_value(foot, 'numStart'), '4');
      expect(_value(foot, 'numRestart'), 'eachSect');
      expect(_value(foot, 'pos'), 'beneathText');
      expect(_value(end, 'numFmt'), 'upperLetter');
      expect(_value(end, 'numStart'), '9');
      expect(_value(end, 'pos'), 'sectEnd');
      expect(source, orderedEquals(original));
    },
  );

  test(
    'effective modern FIB ignores stale DOP numbering and validates live position',
    () {
      final source = _source(
        newVersion: 0x101,
        dop: _dop(
          length: 594,
          footPosition: 3,
          footRestart: 3,
          footStart: 31,
          footFormat: 0xffff,
          endPosition: 0,
        ),
      );
      final parsed = parseLegacyWordDocument(source);
      expect(parsed.footnotes.numbering.startAt, 1);
      expect(parsed.footnotes.position, LegacyWordFootnotePosition.pageBottom);
      expect(parsed.endnotes.position, LegacyWordEndnotePosition.sectionEnd);
      expect(
        parsed.warnings,
        isNot(contains(LegacyWordWarning.recoveredLegacyNoteSettings)),
      );
      expect(
        () => parseLegacyWordDocument(
          _source(newVersion: 0x101, dop: _dop(length: 594, endPosition: 1)),
        ),
        throwsFormatException,
      );
    },
  );

  test('mixed base and extended FIB versions gate legacy note defaults', () {
    for (final variant in <(int, int?, int, int, bool)>[
      (0xc1, null, 93, 500, true),
      (0xd9, null, 108, 544, true),
      (0xc1, 0xd9, 108, 544, true),
      (0xc1, 0x101, 136, 594, false),
      (0xc1, 0x10c, 164, 616, false),
      (0xc1, 0x112, 183, 674, false),
      (0x101, null, 93, 610, false),
    ]) {
      final source = _source(
        version: variant.$1,
        newVersion: variant.$2,
        pairs: variant.$3,
        dop: _dop(length: variant.$4, footStart: 8, footFormat: 3),
      );
      final parsed = parseLegacyWordDocument(source);
      expect(parsed.footnotes.numbering.startAt, variant.$5 ? 8 : 1);
      expect(
        parsed.footnotes.numbering.format,
        variant.$5
            ? LegacyWordNoteNumberFormat.upperLetter
            : LegacyWordNoteNumberFormat.decimal,
      );
      expect(
        parsed.warnings,
        isNot(contains(LegacyWordWarning.recoveredLegacyNoteSettings)),
      );
    }
  });

  test(
    'the exact native-export DOP dialect recovers start4 and section overrides',
    () {
      // The pinned native word-compatibility.doc carries these exact header,
      // DopBase/Dop97 values and section SPRMs, including no SNFtn operand.
      final source = _source(
        version: 0x101,
        pairs: 136,
        dop: _dop(length: 610, footStart: 4, footRestart: 1, footFormat: 2),
        sectionProperties: [
          [
            ...wordSprm(0x303c, [1]),
            ...wordSprm(0x5040, wordU16(2)),
          ],
          [
            ...wordSprm(0x303c, [1]),
            ...wordSprm(0x5040, wordU16(3)),
          ],
        ],
      );
      final parsed = parseLegacyWordDocument(source);
      expect(
        parsed.warnings,
        contains(LegacyWordWarning.recoveredLegacyNoteSettings),
      );
      expect(parsed.sections.map((s) => s.footnotes!.numbering.startAt), [
        4,
        4,
      ]);
      expect(
        parsed.sections.last.footnotes!.numbering.format,
        LegacyWordNoteNumberFormat.upperLetter,
      );
      final package = _parts(convertLegacyWordToStructuredDocx(source).bytes);
      final sections = _elements(
        _xml(package, 'word/document.xml'),
        'sectPr',
      ).toList();
      expect(
        _value(_elements(sections[0], 'footnotePr').single, 'numStart'),
        '4',
      );
      expect(
        _value(_elements(sections[1], 'footnotePr').single, 'numFmt'),
        'upperLetter',
      );
      expect(
        _value(_elements(sections[1], 'footnotePr').single, 'numRestart'),
        'eachSect',
      );
      // One changed predicate cannot activate stale legacy settings.
      for (final alternate in [
        _source(
          version: 0x101,
          pairs: 135,
          dop: _dop(length: 610, footStart: 4),
        ),
        _source(
          version: 0x101,
          pairs: 136,
          dop: _dop(length: 612, footStart: 4),
        ),
        _source(
          version: 0x101,
          newVersion: 0x101,
          pairs: 136,
          dop: _dop(length: 610, footStart: 4),
        ),
      ]) {
        final other = parseLegacyWordDocument(alternate);
        expect(other.footnotes.numbering.startAt, 1);
        expect(
          other.warnings,
          isNot(contains(LegacyWordWarning.recoveredLegacyNoteSettings)),
        );
      }
    },
  );

  test(
    'section settings override each family without leaking to the next section',
    () {
      final source = _source(
        version: 0x101,
        sectionProperties: [
          [
            ...wordSprm(0x303b, [2]),
            ...wordSprm(0x303c, [2]),
            ...wordSprm(
              0x503f,
              wordU16(12),
            ), // ignored for a restarting section
            ...wordSprm(0x5040, wordU16(3)),
            ...wordSprm(0x303e, [0]),
            ...wordSprm(0x5041, wordU16(7)),
            ...wordSprm(0x5042, wordU16(4)),
          ],
          [],
        ],
      );
      final parsed = parseLegacyWordDocument(source);
      final section = parsed.sections.first;
      expect(section.footnotes!.numbering.startAt, 1);
      expect(
        section.footnotes!.numbering.restart,
        LegacyWordNoteRestart.eachPage,
      );
      expect(section.endnotes!.numbering.startAt, 7);
      expect(parsed.sections.last.footnotes, isNull);
      final package = _parts(convertLegacyWordToStructuredDocx(source).bytes);
      final sections = _elements(
        _xml(package, 'word/document.xml'),
        'sectPr',
      ).toList();
      expect(sections.first.childElements.take(3).map((e) => e.name.local), [
        'footnotePr',
        'endnotePr',
        'type',
      ]);
      expect(
        _value(_elements(sections.first, 'footnotePr').single, 'numStart'),
        '1',
      );
      expect(
        _value(_elements(sections.first, 'footnotePr').single, 'numRestart'),
        'eachPage',
      );
      expect(
        _value(_elements(sections.first, 'endnotePr').single, 'numStart'),
        '7',
      );
      expect(_elements(sections.last, 'footnotePr'), isEmpty);
    },
  );

  test(
    'end-of-section deferral is retained only for section-end placement',
    () {
      for (final position in [0, 3]) {
        final source = _source(
          dop: _dop(endPosition: position),
          sectionProperties: [
            wordSprm(0x3012, [0]),
          ],
        );
        final parsed = parseLegacyWordDocument(source);
        expect(parsed.sections.single.suppressEndnotes, isTrue);
        final package = _parts(convertLegacyWordToStructuredDocx(source).bytes);
        expect(
          _elements(_xml(package, 'word/document.xml'), 'noEndnote'),
          hasLength(position == 0 ? 1 : 0),
        );
      }
    },
  );

  test(
    'legacy section-end footnotes, zero start and per-page endnotes stay typed',
    () {
      final parsed = parseLegacyWordDocument(
        _source(dop: _dop(footPosition: 0, footStart: 0, endRestart: 2)),
      );
      expect(parsed.footnotes.position, LegacyWordFootnotePosition.sectionEnd);
      expect(parsed.footnotes.numbering.startAt, 0);
      expect(parsed.endnotes.numbering.restart, LegacyWordNoteRestart.eachPage);
    },
  );

  test('section operand bounds and complete operands remain mandatory', () {
    for (final properties in [
      wordSprm(0x303b, [0]),
      wordSprm(0x303b, [3]),
      wordSprm(0x303c, [3]),
      wordSprm(0x303e, [2]),
      wordSprm(0x503f, wordU16(16384)),
      wordSprm(0x5041, wordU16(65535)),
      wordSprm(0x5040, wordU16(60)),
      wordSprm(0x5042, wordU16(65535)),
      [0x3f, 0x50, 0x01],
    ]) {
      expect(
        () => parseLegacyWordDocument(_source(sectionProperties: [properties])),
        throwsFormatException,
      );
    }
  });

  test(
    'active legacy DOP reserved positions and restart values are rejected',
    () {
      for (final dop in [
        _dop(footPosition: 3),
        _dop(endPosition: 2),
        _dop(footRestart: 3),
        _dop(endRestart: 3),
        _dop(footFormat: 60),
      ]) {
        expect(
          () => parseLegacyWordDocument(_source(dop: dop)),
          throwsFormatException,
        );
      }
    },
  );

  test('valid non-counting note formats use an explicit bounded fallback', () {
    for (final raw in [23, 40]) {
      final parsed = parseLegacyWordDocument(
        _source(dop: _dop(footFormat: raw)),
      );
      expect(
        parsed.footnotes.numbering.format,
        LegacyWordNoteNumberFormat.decimal,
      );
      expect(
        parsed.warnings,
        contains(LegacyWordWarning.unsupportedFormatting),
      );
    }
    final none = parseLegacyWordDocument(_source(dop: _dop(footFormat: 255)));
    expect(none.footnotes.numbering.format, LegacyWordNoteNumberFormat.none);
  });

  test('invalid public start metadata cannot be written into the package', () {
    for (final start in [-1, 16384]) {
      final document = LegacyWordDocument(
        blocks: const [],
        sections: const [],
        plainText: '',
        safeHtml: '',
        footnotes: LegacyWordFootnoteSettings(
          numbering: LegacyWordNoteNumbering(startAt: start),
        ),
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
    }
  });

  test(
    'explicit zero header/footer distances remain zero; absence keeps defaults',
    () {
      for (final explicit in [false, true]) {
        final source = _source(
          sectionProperties: [
            [
              ...wordSprm(0x9023, wordU16(1440)),
              if (explicit) ...wordSprm(0xb017, wordU16(0)),
              if (explicit) ...wordSprm(0xb018, wordU16(0)),
            ],
          ],
        );
        final parsed = parseLegacyWordDocument(source).sections.single;
        expect(parsed.headerDistanceTwips, explicit ? 0 : null);
        expect(parsed.footerDistanceTwips, explicit ? 0 : null);
        final package = _parts(convertLegacyWordToStructuredDocx(source).bytes);
        final margin = _elements(
          _xml(package, 'word/document.xml'),
          'pgMar',
        ).single;
        expect(
          margin.getAttribute('header', namespace: _w),
          explicit ? '0' : '720',
        );
        expect(
          margin.getAttribute('footer', namespace: _w),
          explicit ? '0' : '720',
        );
      }
    },
  );

  test(
    'special-note settings follow active parts and never activate hidden notes',
    () {
      const note = '\x02Private footnote\r';
      for (final hidden in [false, true]) {
        final source = storyWordFixture(
          main: 'A\x02\r',
          footnotes: '$note\r',
          tablePairs: {
            2: storyPlc([1, 0xffffffff], wordU16(1)),
            3: storyPlc([0, note.length, 0xffffffff]),
            31: _dop(),
          },
          characterRuns: [
            const WordFixtureFkpRun(8192, 16386),
            WordFixtureFkpRun(
              16386,
              16388,
              properties: wordSprm(0x083c, [hidden ? 1 : 0]),
            ),
            const WordFixtureFkpRun(16388, 28672),
          ],
        );
        final package = _parts(convertLegacyWordToStructuredDocx(source).bytes);
        final settings = _xml(package, 'word/settings.xml');
        expect(package.containsKey('word/footnotes.xml'), !hidden);
        expect(_elements(settings, 'footnote'), hasLength(hidden ? 0 : 2));
        if (!hidden) {
          expect(
            _elements(
              settings,
              'footnote',
            ).map((e) => e.getAttribute('id', namespace: _w)),
            ['-1', '0'],
          );
        }
      }
    },
  );
}
