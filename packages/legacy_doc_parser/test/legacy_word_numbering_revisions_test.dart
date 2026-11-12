// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/list_word_fixture.dart';
import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _date = 45 | (8 << 6) | (12 << 11) | (11 << 16) | (126 << 20);

Uint8List _record({
  bool numbered = true,
  String text = '\u0000.\u0001.\u0002.',
  List<int> positions = const [1, 3, 5],
  List<int> formats = const [0, 2, 0],
  List<int> values = const [1, 1, 3],
}) {
  final bytes = Uint8List(128);
  final data = ByteData.sublistView(bytes);
  bytes[0] = numbered ? 1 : 0;
  bytes[1] = 0xff; // Ignored, not a second Boolean operand.
  data.setUint16(2, 1, Endian.little);
  data.setUint32(4, _date, Endian.little);
  bytes.setRange(8, 8 + positions.length, positions);
  bytes.setRange(17, 17 + formats.length, formats);
  for (var i = 0; i < values.length; i++) {
    data.setUint32(28 + i * 4, values[i], Endian.little);
  }
  data.setUint16(64, text.length, Endian.little);
  for (var i = 0; i < text.length; i++) {
    data.setUint16(66 + i * 2, text.codeUnitAt(i), Endian.little);
  }
  return bytes;
}

Uint8List _source({
  Uint8List? record,
  int? inserted,
  int currentId = 1,
  bool styleReset = false,
  int prm = 0,
}) => StructuredWordFixture(
  pieces: [WordFixturePiece('Item\r', prm: prm)],
  paragraphRuns: [
    WordFixtureFkpRun(
      8192,
      8197,
      properties: [
        if (record != null) ...wordSprm(0xc645, [record.length, ...record]),
        if (inserted != null) ...wordSprm(0x2443, [inserted]),
        if (styleReset) ...wordSprm(0x4600, wordU16(1)),
        ...wordSprm(0x460b, wordU16(currentId)),
        ...wordSprm(0x260a, [0]),
      ],
    ),
  ],
  styles: const {
    0: WordFixtureStyle(name: 'Normal', builtinId: 0),
    1: WordFixtureStyle(name: 'Changed style', builtinId: 0xffe),
  },
  extraTablePairs: {
    51: [
      ...wordU16(0xffff),
      ...wordU16(2),
      ...wordU16(0),
      for (final name in ['Unknown', 'Alice']) ...[
        ...wordU16(name.length),
        for (final c in name.codeUnits) ...wordU16(c),
      ],
    ],
    73: listFixtureDefinitions([listFixtureLevel(format: 1, start: 9)]),
    74: listFixtureInstances(),
  },
).build(mutate: (word, _) => word.setUint32(158 + 73 * 8, 30, Endian.little));

Map<String, Uint8List> _parts(Uint8List value) => {
  for (final file in ZipDecoder().decodeBytes(value))
    if (file.isFile) file.name: file.content,
};
XmlDocument _xml(Uint8List value) =>
    XmlDocument.parse(utf8.decode(_parts(value)['word/document.xml']!));
String? _attr(XmlElement element, String name) =>
    element.getAttribute(name, namespace: _w);

// Independent oracle for the fixture's decimal/Roman original states. It reads
// the emitted standardized grammar and never calls parser numbering code.
String _oldMarker(String original) {
  final tokens = RegExp(
    r'%(\d+):(\d+):(\d+):([^%]*)',
  ).allMatches(original).toList();
  expect(tokens.map((m) => m.group(0)).join(), original);
  return tokens.map((m) {
    final value = int.parse(m.group(2)!), format = int.parse(m.group(3)!);
    final number = switch (format) {
      0 => '$value',
      2 => const ['i', 'ii', 'iii', 'iv', 'v'][value - 1],
      _ => throw StateError('Unexpected fixture number format'),
    };
    return number + m.group(4)!;
  }).join();
}

void main() {
  test(
    'NumRM preserves historical multilevel values independent of current list',
    () {
      final sourceRecord = _record();
      final document = parseLegacyWordDocument(_source(record: sourceRecord));
      final paragraph = document.blocks.single as LegacyWordParagraph;
      final change = paragraph.numberingRevision!;
      expect(change.previouslyNumbered, isTrue);
      expect(change.original, '%1:1:0:.%2:1:2:.%3:3:0:.');
      expect(change.revision.author, 'Alice');
      expect(change.sourceRecord, sourceRecord);
      expect(() => change.sourceRecord![0] = 0, throwsUnsupportedError);
      sourceRecord[0] = 0;
      expect(change.sourceRecord![0], 1);
      expect(document.plainText, 'Item');
      expect(document.safeHtml, contains('IX.'));
      final result = convertLegacyWordDocument(document);
      final xml = _xml(result.bytes);
      final numPr = xml.findAllElements('numPr', namespace: _w).single;
      final old = numPr.getElement('numberingChange', namespace: _w)!;
      expect(_attr(old, 'author'), 'Alice');
      expect(_attr(old, 'date'), '2026-11-12T08:45:00');
      expect(_oldMarker(_attr(old, 'original')!), '1.i.3.');
      expect(_attr(numPr.getElement('numId', namespace: _w)!, 'val'), '1');
      expect(result.preservedCounts['numberingRevisions'], 1);
      expect(
        result.limitations,
        isNot(contains(LegacyWordConversionLimitation.revisions)),
      );
      final parts = _parts(result.bytes);
      expect(
        utf8.decode(parts['word/evidence/manifest.json']!),
        contains('NumRM'),
      );
      expect(parts.values, contains(orderedEquals(change.sourceRecord!)));
    },
  );

  test(
    'numbering insertion is independent from insertion of paragraph text',
    () {
      final document = parseLegacyWordDocument(
        _source(record: _record(numbered: false), inserted: 1),
      );
      final result = convertLegacyWordDocument(document);
      final xml = _xml(result.bytes);
      final numPr = xml.findAllElements('numPr', namespace: _w).single;
      final insertion = numPr.getElement('ins', namespace: _w)!;
      expect(_attr(insertion, 'author'), 'Alice');
      expect(insertion.childElements, isEmpty);
      expect(xml.findAllElements('ins', namespace: _w).length, 1);
      expect(numPr.getElement('numberingChange', namespace: _w), isNull);
      expect(xml.findAllElements('t', namespace: _w).single.innerText, 'Item');
      // Rejecting numPr/ins removes numbering, not the paragraph's text.
      expect(
        (document.blocks.single as LegacyWordParagraph)
            .numberingRevision!
            .previouslyNumbered,
        isFalse,
      );
      expect(result.preservedCounts['numberingInsertions'], 1);
    },
  );

  test('paragraph style changes preserve both numbering revision records', () {
    final document = parseLegacyWordDocument(
      _source(record: _record(), inserted: 1, styleReset: true),
    );
    final paragraph = document.blocks.single as LegacyWordParagraph;
    expect(paragraph.style.styleIndex, 1);
    expect(paragraph.numberingRevision!.inserted, isTrue);
    final numPr = _xml(
      convertLegacyWordDocument(document).bytes,
    ).findAllElements('numPr', namespace: _w).single;
    expect(numPr.childElements.map((e) => e.name.local), [
      'ilvl',
      'numId',
      'numberingChange',
      'ins',
    ]);
  });

  test(
    'removed numbering retains its prior label and an explicit native reset',
    () {
      final document = parseLegacyWordDocument(
        _source(record: _record(), currentId: 0),
      );
      final numPr = _xml(
        convertLegacyWordDocument(document).bytes,
      ).findAllElements('numPr', namespace: _w).single;
      expect(_attr(numPr.getElement('numId', namespace: _w)!, 'val'), '0');
      expect(
        _oldMarker(
          _attr(
            numPr.getElement('numberingChange', namespace: _w)!,
            'original',
          )!,
        ),
        '1.i.3.',
      );
    },
  );

  test(
    'PRM0 insertion without an author record remains an incomplete native mark',
    () {
      final document = parseLegacyWordDocument(
        _source(prm: (1 << 8) | (0x7e << 1)),
      );
      expect(
        (document.blocks.single as LegacyWordParagraph)
            .numberingRevision!
            .inserted,
        isTrue,
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.revisionMetadataIncomplete),
      );
      final result = convertLegacyWordDocument(document);
      expect(
        _xml(result.bytes).findAllElements('ins', namespace: _w).length,
        1,
      );
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.revisions),
      );
    },
  );

  test(
    'unrepresentable historical syntax stays intact evidence with no invented label',
    () {
      for (final record in [
        _record(text: '(\u0000)', positions: [2], formats: [0], values: [3]),
        _record(text: '\u0000%', positions: [1], formats: [0], values: [3]),
        _record(text: '\u0000.', positions: [1], formats: [255], values: [3]),
      ]) {
        final document = parseLegacyWordDocument(_source(record: record));
        expect(
          (document.blocks.single as LegacyWordParagraph)
              .numberingRevision!
              .original,
          isNull,
        );
        final result = convertLegacyWordDocument(document);
        expect(
          _attr(
            _xml(
              result.bytes,
            ).findAllElements('numberingChange', namespace: _w).single,
            'original',
          ),
          isNull,
        );
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.revisions),
        );
      }
    },
  );

  test(
    'bad numbering record bounds, booleans and placeholders fail before export',
    () {
      final tooLong = _record();
      ByteData.sublistView(tooLong).setUint16(64, 32, Endian.little);
      final badBoolean = _record()..[0] = 2;
      for (final record in [
        Uint8List(127),
        badBoolean,
        tooLong,
        _record(positions: [1, 1]),
        _record(positions: [9]),
        _record(text: '\ud800', positions: []),
      ]) {
        expect(
          () => parseLegacyWordDocument(_source(record: record)),
          throwsFormatException,
        );
      }
      expect(
        () => parseLegacyWordDocument(_source(inserted: 2)),
        throwsFormatException,
      );
    },
  );
}
