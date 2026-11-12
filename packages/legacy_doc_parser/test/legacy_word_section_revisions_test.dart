// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);

List<int> _byte(int code, int value) => wordSprm(code, [value]);
List<int> _word(int code, int value) => wordSprm(code, wordU16(value));
List<int> _mark({int author = 1, int enabled = 1}) =>
    wordSprm(0xd243, [7, enabled, ...wordU16(author), ...wordU32(_date)]);

Uint8List _source(
  List<WordFixtureSection> sections, {
  String text = 'Text\r',
}) => StructuredWordFixture(
  pieces: [WordFixturePiece(text)],
  sections: sections,
  extraTablePairs: {
    51: [
      ...wordU16(0xffff),
      ...wordU16(3),
      ...wordU16(0),
      for (final name in ['Unknown', 'Alice', 'Bob']) ...[
        ...wordU16(name.length),
        for (final c in name.codeUnits) ...wordU16(c),
      ],
    ],
  },
).build();

Map<String, Uint8List> _parts(Uint8List value) => {
  for (final file in ZipDecoder().decodeBytes(value))
    if (file.isFile) file.name: file.content,
};

List<XmlElement> _sections(Uint8List value) {
  final xml = XmlDocument.parse(
    utf8.decode(_parts(value)['word/document.xml']!),
  );
  return xml
      .findAllElements('sectPr', namespace: _w)
      .where((e) => e.parentElement?.name.local != 'sectPrChange')
      .toList();
}

String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w);

// Independently apply OOXML's accept/reject property semantics to the emitted
// XML. This uses neither the parser model nor converter helper code. Accept
// keeps the current children; reject restores the complete historical set.
Map<String, List<Map<String, String>>> _state(
  XmlElement section, {
  bool reject = false,
}) {
  final change = section.getElement('sectPrChange', namespace: _w);
  final source = reject && change != null
      ? change.getElement('sectPr', namespace: _w)!
      : section;
  return {
    for (final child in source.childElements)
      if (child.name.local != 'sectPrChange')
        child.name.local: [
          {for (final a in child.attributes) a.name.local: a.value},
          for (final nested in child.childElements)
            {for (final a in nested.attributes) a.name.local: a.value},
        ],
  };
}

void main() {
  test(
    'section change retains independently rejectable dimensions, columns and margins',
    () {
      final document = parseLegacyWordDocument(
        _source([
          WordFixtureSection(5, [
            ..._word(0xb01f, 12240),
            ..._word(0xb020, 15840),
            ..._word(0xb021, 1200),
            ..._word(0xb022, 1300),
            ..._word(0x500b, 1),
            ..._byte(0x3005, 0),
            ...wordSprm(0xf203, [0, ...wordU16(4000)]),
            ...wordSprm(0xf203, [1, ...wordU16(5000)]),
            ...wordSprm(0xf204, [0, ...wordU16(360)]),
            ..._byte(0x300a, 1),
            ..._byte(0x3239, 1),
            ..._word(0xb01f, 15840),
            ..._word(0xb020, 12240),
            ..._byte(0x301d, 2),
            ..._word(0xb021, 1800),
            ..._word(0x500b, 0),
            ..._byte(0x3005, 1),
            ..._byte(0x300a, 0),
            ..._mark(),
            ...wordSprm(0x703a, wordU32(0x12345678)),
          ]),
        ]),
      );
      final section = document.sections.single;
      final old = section.formattingRevision!;
      expect(section.pageWidthTwips, 15840);
      expect(section.landscape, isTrue);
      expect(old.previousSection!.pageWidthTwips, 12240);
      expect(old.previousSection!.landscape, isFalse);
      expect(old.previousSection!.layout.columns.map((c) => c.widthTwips), [
        4000,
        5000,
      ]);
      expect(old.previousSection!.formattingRevision, isNull);
      expect(old.revision.author, 'Alice');
      expect(old.revision.saveId, 0x12345678);
      expect(old.previousPropertiesComplete, isTrue);

      final converted = convertLegacyWordDocument(document);
      final xml = _sections(converted.bytes).single;
      expect(_attr(xml, 'rsidR'), '12345678');
      expect(xml.childElements.last.name.local, 'sectPrChange');
      final change = xml.getElement('sectPrChange', namespace: _w)!;
      expect(_attr(change, 'author'), 'Alice');
      expect(_attr(change, 'date'), '2026-11-12T08:45:00');
      final accepted = _state(xml), rejected = _state(xml, reject: true);
      expect(accepted['pgSz']!.single, {
        'w': '15840',
        'h': '12240',
        'orient': 'landscape',
      });
      expect(rejected['pgSz']!.single, {
        'w': '12240',
        'h': '15840',
        'orient': 'portrait',
      });
      expect(accepted['pgMar']!.single['left'], '1800');
      expect(rejected['pgMar']!.single['left'], '1200');
      expect(accepted['cols']!.first['num'], '1');
      expect(rejected['cols'], [
        {'num': '2', 'equalWidth': '0', 'sep': '0'},
        {'w': '4000', 'space': '360'},
        {'w': '5000', 'space': '0'},
      ]);
      expect(accepted.containsKey('titlePg'), isFalse);
      expect(rejected.containsKey('titlePg'), isTrue);
      expect(converted.preservedCounts['sections'], 1);
      expect(converted.preservedCounts['sectionFormattingRevisions'], 1);
      expect(
        converted.limitations,
        isNot(contains(LegacyWordConversionLimitation.revisions)),
      );
    },
  );

  test('a revised terminating break moves to the following native section', () {
    final document = parseLegacyWordDocument(
      _source([
        WordFixtureSection(2, [
          ..._byte(0x3009, 0),
          ..._byte(0x3239, 1),
          ..._byte(0x3009, 3),
          ..._mark(),
        ]),
        const WordFixtureSection(4, []),
      ], text: 'A\fB\r'),
    );
    final converted = convertLegacyWordDocument(document);
    final sections = _sections(converted.bytes);
    expect(_state(sections.first)['type']!.single['val'], 'nextPage');
    expect(
      _state(sections.first, reject: true)['type']!.single['val'],
      'nextPage',
    );
    expect(_state(sections.last)['type']!.single['val'], 'evenPage');
    expect(
      _state(sections.last, reject: true)['type']!.single['val'],
      'continuous',
    );
    expect(
      _attr(sections.last.getElement('sectPrChange', namespace: _w)!, 'author'),
      'Alice',
    );
    expect(
      converted.limitations,
      isNot(contains(LegacyWordConversionLimitation.revisions)),
    );
  });

  test(
    'independent break and layout authors are never merged or misattributed',
    () {
      final document = parseLegacyWordDocument(
        _source([
          WordFixtureSection(2, [
            ..._byte(0x3009, 0),
            ..._byte(0x3239, 1),
            ..._byte(0x3009, 3),
            ..._mark(),
          ]),
          WordFixtureSection(4, [
            ..._word(0xb01f, 12240),
            ..._byte(0x3239, 1),
            ..._word(0xb01f, 14400),
            ..._mark(author: 2),
          ]),
        ], text: 'A\fB\r'),
      );
      final converted = convertLegacyWordDocument(document);
      final section = _sections(converted.bytes).last;
      expect(
        _attr(section.getElement('sectPrChange', namespace: _w)!, 'author'),
        'Bob',
      );
      expect(_state(section, reject: true)['pgSz']!.single['w'], '12240');
      expect(_state(section, reject: true)['type']!.single['val'], 'evenPage');
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      final evidence = utf8.decode(
        _parts(converted.bytes)['word/evidence/manifest.json']!,
      );
      expect(evidence, contains('sectionBreakRevision'));
      expect(evidence, contains('two independent revisions'));
    },
  );

  test('false walls and unmarked snapshots cannot invent native revisions', () {
    for (final properties in [
      [
        ..._word(0xb01f, 12240),
        ..._byte(0x3239, 1),
        ..._byte(0x3239, 0),
        ..._mark(),
      ],
      [..._byte(0x3239, 1), ..._word(0xb01f, 14000)],
    ]) {
      final document = parseLegacyWordDocument(
        _source([WordFixtureSection(5, properties)]),
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.revisionMetadataIncomplete),
      );
      final converted = convertLegacyWordDocument(document);
      expect(
        _sections(
          converted.bytes,
        ).single.findAllElements('sectPrChange', namespace: _w),
        isEmpty,
      );
      expect(
        converted.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
      expect(
        utf8.decode(_parts(converted.bytes)['word/evidence/manifest.json']!),
        contains('sectionFormatting'),
      );
    }
  });

  test('unsupported historical properties remain an explicit limitation', () {
    final document = parseLegacyWordDocument(
      _source([
        WordFixtureSection(5, [
          ..._byte(0x3000, 1),
          ..._byte(0x3239, 1),
          ..._mark(),
        ]),
      ]),
    );
    expect(
      document.sections.single.formattingRevision!.previousPropertiesComplete,
      isFalse,
    );
    expect(
      document.warnings,
      contains(LegacyWordWarning.revisionMetadataIncomplete),
    );
    expect(
      convertLegacyWordDocument(document).limitations,
      contains(LegacyWordConversionLimitation.revisions),
    );
  });

  test(
    'old malformed section layout and malformed revision records are rejected',
    () {
      for (final properties in [
        [
          ..._word(0xb01f, 12),
          ..._byte(0x3239, 1),
          ..._word(0xb01f, 12240),
          ..._mark(),
        ],
        [
          ..._word(0x500b, 1),
          ..._byte(0x3005, 0),
          ..._byte(0x3239, 1),
          ..._byte(0x3005, 1),
          ..._mark(),
        ],
        _byte(0x3239, 2),
        wordSprm(0xd243, [6, ...List.filled(6, 0)]),
        _mark(enabled: 2),
      ]) {
        expect(
          () => parseLegacyWordDocument(
            _source([WordFixtureSection(5, properties)]),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('revision save IDs remain present without an active revision', () {
    final document = parseLegacyWordDocument(
      _source([
        WordFixtureSection(
          5,
          [wordSprm(0x703a, wordU32(0xabcdef01))].expand((e) => e).toList(),
        ),
      ]),
    );
    expect(document.sections.single.formattingRevision, isNull);
    expect(
      _attr(
        _sections(convertLegacyWordDocument(document).bytes).single,
        'rsidR',
      ),
      'ABCDEF01',
    );
  });
}
