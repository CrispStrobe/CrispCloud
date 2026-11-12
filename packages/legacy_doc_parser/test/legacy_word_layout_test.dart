// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';
import 'support/table_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
List<int> _one(int code, int value) => wordSprm(code, [value]);
List<int> _two(int code, int value) => wordSprm(code, wordU16(value));

Uint8List _fixture({
  List<int> paragraph = const [],
  List<int> section = const [],
  String text = 'A\r',
}) => StructuredWordFixture(
  pieces: [WordFixturePiece(text)],
  paragraphRuns: [
    WordFixtureFkpRun(8192, 8192 + text.length, properties: paragraph),
  ],
  sections: [WordFixtureSection(text.length, section)],
).build();

XmlDocument _xml(LegacyWordDocument document) {
  final converted = convertLegacyWordDocument(document);
  final archive = ZipDecoder().decodeBytes(converted.bytes);
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

Iterable<XmlElement> _all(XmlNode root, String name) =>
    root.findAllElements(name, namespace: _w);
String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w);

void main() {
  test(
    'preserves manual column breaks as column breaks, never text omission',
    () {
      final document = parseLegacyWordDocument(
        _fixture(text: 'Left\x0eRight\r'),
      );
      final paragraph = document.blocks.single as LegacyWordParagraph;
      expect(paragraph.runs.map((r) => r.text).join(), 'Left\x0eRight');
      expect(document.safeHtml, contains('break-after:column'));
      final xml = _xml(document);
      expect(_attr(_all(xml, 'br').single, 'type'), 'column');
      expect(_all(xml, 't').map((e) => e.innerText), ['Left', 'Right']);
    },
  );

  test('resolves pagination flags through stylesheet and direct overrides', () {
    final document = parseLegacyWordDocument(
      _fixture(
        paragraph: [
          ..._one(0x2431, 0),
          ..._one(0x242a, 1),
          ..._one(0x240c, 1),
          ..._one(0x2441, 1),
          ..._one(0x246d, 1),
          ..._one(0x2470, 1),
          ..._one(0x245b, 1),
          ..._one(0x245c, 1),
          ..._one(0x2433, 0),
          ..._one(0x2434, 0),
          ..._one(0x2435, 0),
          ..._one(0x2437, 0),
          ..._one(0x2438, 1),
        ],
      ),
    );
    final layout = (document.blocks.single as LegacyWordParagraph).style.layout;
    expect(layout.widowControl, isFalse);
    expect(layout.rightToLeft, isTrue);
    final xml = _xml(document);
    for (final name in [
      'suppressAutoHyphens',
      'suppressLineNumbers',
      'bidi',
      'contextualSpacing',
      'mirrorIndents',
      'autoSpaceDN',
    ]) {
      expect(_attr(_all(xml, name).single, 'val'), '1');
    }
    for (final name in [
      'widowControl',
      'kinsoku',
      'wordWrap',
      'overflowPunct',
      'autoSpaceDE',
    ]) {
      expect(_attr(_all(xml, name).single, 'val'), '0');
    }
    expect(_attr(_all(xml, 'spacing').first, 'beforeAutospacing'), '1');
    expect(_attr(_all(xml, 'spacing').first, 'afterAutospacing'), '1');
  });

  test(
    'PRM0 indexes match current MS-DOC instead of shifted legacy entries',
    () {
      for (final (index, read)
          in <(int, bool Function(LegacyWordParagraphLayout))>[
            (0x2c, (p) => p.suppressAutoHyphens),
            (0x0d, (p) => p.mirrorIndents),
            (0x0e, (p) => p.suppressLineNumbers),
            (0x35, (p) => p.kinsoku!),
            (0x39, (p) => p.autoSpaceEastAsianLatin!),
          ]) {
        final d = parseLegacyWordDocument(
          StructuredWordFixture(
            pieces: [WordFixturePiece('A\r', prm: (1 << 8) | (index << 1))],
          ).build(),
        );
        expect(
          read((d.blocks.single as LegacyWordParagraph).style.layout),
          isTrue,
          reason: 'PRM0 $index',
        );
      }
      final d = parseLegacyWordDocument(
        StructuredWordFixture(
          pieces: [const WordFixturePiece('A\r', prm: 0x33 << 1)],
        ).build(),
      );
      expect(
        (d.blocks.single as LegacyWordParagraph).style.layout.widowControl,
        isFalse,
      );
    },
  );

  test(
    'unequal columns, line numbering, page restart and grid remain editable',
    () {
      final document = parseLegacyWordDocument(
        _fixture(
          section: [
            ..._two(0x500b, 1),
            ..._one(0x3005, 0),
            ...wordSprm(0xf203, [0, ...wordU16(2400)]),
            ...wordSprm(0xf203, [1, ...wordU16(4800)]),
            ...wordSprm(0xf204, [0, ...wordU16(720)]),
            ..._one(0x3019, 1),
            ..._one(0x301a, 2),
            ..._two(0x5015, 5),
            ..._two(0x501b, 6),
            ..._two(0x9016, 240),
            ..._one(0x3013, 2),
            ..._one(0x3011, 1),
            ..._one(0x300e, 2),
            ...wordSprm(0x7044, wordU32(42)),
            ..._two(0x5032, 1),
            ..._two(0x9031, 360),
            ...wordSprm(0x7030, wordU32(-4096)),
          ],
        ),
      );
      final section = document.sections.single;
      expect(
        section.layout.columns.map((c) => (c.widthTwips, c.spaceAfterTwips)),
        [(2400, 720), (4800, 0)],
      );
      final xml = _xml(document);
      expect(_attr(_all(xml, 'cols').single, 'equalWidth'), '0');
      expect(_attr(_all(xml, 'cols').single, 'sep'), '1');
      expect(_all(xml, 'col').map((e) => _attr(e, 'w')), ['2400', '4800']);
      expect(_attr(_all(xml, 'lnNumType').single, 'start'), '7');
      expect(_attr(_all(xml, 'lnNumType').single, 'restart'), 'continuous');
      expect(_attr(_all(xml, 'pgNumType').single, 'start'), '42');
      expect(_attr(_all(xml, 'pgNumType').single, 'fmt'), 'lowerRoman');
      expect(_attr(_all(xml, 'vAlign').single, 'val'), 'both');
      expect(_attr(_all(xml, 'docGrid').single, 'charSpace'), '-4096');
    },
  );

  test('a stored page number start does not activate restart', () {
    final document = parseLegacyWordDocument(
      _fixture(section: _two(0x501c, 9)),
    );
    expect(document.sections.single.layout.pageNumberStart, 9);
    expect(_all(_xml(document), 'pgNumType'), isEmpty);
  });

  for (final (name, operations) in [
    (
      'missing column width',
      [
        ..._two(0x500b, 1),
        ..._one(0x3005, 0),
        ...wordSprm(0xf203, [0, ...wordU16(2400)]),
      ],
    ),
    ('column index', wordSprm(0xf203, [44, ...wordU16(2400)])),
    ('column width', wordSprm(0xf203, [0, ...wordU16(717)])),
    ('line number interval', _two(0x5015, 101)),
    ('grid without pitch', _two(0x5032, 1)),
    ('invalid grid pitch', _two(0x9031, 0)),
    ('invalid boolean', _one(0x3005, 2)),
  ]) {
    test('rejects $name rather than inventing pagination', () {
      expect(
        () => parseLegacyWordDocument(_fixture(section: operations)),
        throwsFormatException,
      );
    });
  }

  test(
    'recovers a native final note table only at a closed table boundary',
    () {
      const main = 'A\x02\r', note = '\x02N\rCell\x07\x07';
      Uint8List make({bool rowEnd = true}) => storyWordFixture(
        main: main,
        footnotes: '$note\r',
        tablePairs: {
          2: storyPlc([1, main.length], wordU16(1)),
          3: storyPlc([0, note.length, 0xffffffff]),
        },
        paragraphRuns: [
          const WordFixtureFkpRun(8192, 8198),
          WordFixtureFkpRun(8198, 8208, properties: _one(0x2416, 1)),
          WordFixtureFkpRun(
            8208,
            8210,
            properties: [
              ..._one(0x2416, 1),
              if (rowEnd) ..._one(0x2417, 1),
              ...tableFixtureDefinition([2400]),
            ],
          ),
          const WordFixtureFkpRun(8210, 28672),
        ],
      );
      final document = parseLegacyWordDocument(make());
      expect(
        document.warnings,
        contains(LegacyWordWarning.recoveredTableStoryBoundary),
      );
      final noteStory = document.stories.singleWhere(
        (s) => s.kind == LegacyWordStoryKind.footnote,
      );
      expect(noteStory.blocks.last, isA<LegacyWordTable>());
      expect(noteStory.plainText, 'N\nCell');
      expect(
        convertLegacyWordDocument(document).preservedCounts['footnotes'],
        1,
      );
      expect(
        () => parseLegacyWordDocument(make(rowEnd: false)),
        throwsFormatException,
      );
    },
  );
}
