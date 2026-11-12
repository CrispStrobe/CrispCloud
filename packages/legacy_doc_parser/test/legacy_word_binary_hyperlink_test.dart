// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Uint8List _hfd(String anchor) {
  final bytes = Uint8List.fromList([
    ...List.filled(68, 0),
    0x08,
    0xd0,
    0xc9,
    0xea,
    0x79,
    0xf9,
    0xba,
    0xce,
    0x11,
    0x8c,
    0x82,
    0x00,
    0xaa,
    0x00,
    0x4b,
    0xa9,
    0x0b,
    ...wordU32(2),
    ...wordU32(0x0a),
    ...wordU32(anchor.length + 1),
    for (final unit in anchor.codeUnits) ...wordU16(unit),
    0,
    0,
  ]);
  final data = ByteData.sublistView(bytes);
  data.setInt32(0, bytes.length, Endian.little);
  data.setUint16(4, 68, Endian.little);
  return bytes;
}

Uint8List _source({
  String anchor = 'Target',
  bool quoted = true,
  bool referenced = true,
  Uint8List? payload,
  String extraInstruction = '',
}) {
  final target = quoted ? '"$anchor"' : anchor;
  final text = 'α\x13 HYPERLINK \\l $target\x01$extraInstruction\x14Link\x15\r';
  final marker = text.indexOf('\x01');
  final start = 8192 + 2 * marker;
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text, compressed: false)],
    characterRuns: [
      WordFixtureFkpRun(8192, start),
      WordFixtureFkpRun(
        start,
        start + 2,
        properties: [
          ...wordSprm(0x0855, [1]),
          if (referenced) ...[
            ...wordSprm(0x0806, [1]),
            ...wordSprm(0x6a03, wordU32(16)),
          ],
        ],
      ),
      WordFixtureFkpRun(start + 2, 8192 + 2 * text.length),
    ],
    extraStreams: {
      'Data': Uint8List.fromList([
        ...List.filled(16, 0),
        ...payload ?? _hfd(anchor),
      ]),
    },
  ).build();
}

(XmlDocument, Map<String, dynamic>, LegacyWordStructuredConversion) _convert(
  Uint8List bytes,
) {
  final result = convertLegacyWord(bytes);
  final archive = ZipDecoder().decodeBytes(result.bytes);
  return (
    XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    ),
    jsonDecode(
          utf8.decode(archive.findFile('word/evidence/manifest.json')!.content),
        )
        as Map<String, dynamic>,
    result,
  );
}

void main() {
  for (final (anchor, quoted) in [
    ('Target', true),
    ('Target', false),
    ('Ziel東京😀', true),
  ]) {
    test(
      'retains a referenced internal hyperlink to $anchor, quoted=$quoted',
      () {
        final bytes = _source(anchor: anchor, quoted: quoted);
        final original = Uint8List.fromList(bytes);
        final (xml, evidence, result) = _convert(bytes);
        final instructions = xml
            .findAllElements('instrText', namespace: _w)
            .toList();
        expect(instructions, hasLength(1));
        expect(instructions.single.innerText, contains(anchor));
        expect(instructions.single.innerText, isNot(contains('\x01')));
        expect(xml.findAllElements('fldChar', namespace: _w), hasLength(3));
        expect(
          xml
              .findAllElements('fldChar', namespace: _w)
              .first
              .getAttribute('fldLock', namespace: _w),
          '1',
        );
        expect(
          xml
              .findAllElements('t', namespace: _w)
              .map((e) => e.innerText)
              .join(),
          'αLink',
        );
        expect(result.preservedCounts['binaryHyperlinkFields'], 1);
        expect(result.preservedCounts['fields'], 1);
        final record = (evidence['records'] as List).singleWhere(
          (r) => r['kind'] == 'binaryHyperlinkField',
        );
        expect(record['instruction'], contains('\x01'));
        expect(record['emittedInstruction'], instructions.single.innerText);
        expect(bytes, orderedEquals(original));
      },
    );
  }

  final malformed = <String, void Function(Uint8List)>{
    'wrong CLSID': (b) => b[69] ^= 1,
    'unsupported traversal flags': (b) => b[68] = 0x09,
    'wrong serialization version': (b) => b[85] = 3,
    'external moniker flags': (b) => b[89] = 0x09,
    'additional unparsed fields': (b) => b[89] = 0x18,
    'excessive string length': (b) =>
        ByteData.sublistView(b).setUint32(93, 0xffffffff, Endian.little),
    'short string extent': (b) => b[93] -= 1,
    'unterminated location': (b) => b[b.length - 2] = 65,
    'embedded NUL': (b) {
      b[97] = 0;
      b[98] = 0;
    },
    'unpaired surrogate': (b) {
      b[97] = 0;
      b[98] = 0xd8;
    },
  };
  for (final entry in malformed.entries) {
    test('${entry.key} retains the field as inert evidence', () {
      final payload = _hfd('Target');
      entry.value(payload);
      final (xml, evidence, result) = _convert(_source(payload: payload));
      expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
      expect(xml.findAllElements('instrText', namespace: _w), isEmpty);
      expect(
        xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
        'αLink',
      );
      expect(result.preservedCounts['binaryHyperlinkFields'], isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
      expect(
        (evidence['records'] as List).any((r) => r['kind'] == 'field'),
        isTrue,
      );
    });
  }

  test(
    'unreferenced data and conflicting targets cannot authorize a field',
    () {
      for (final bytes in [
        _source(referenced: false),
        _source(payload: _hfd('Different')),
        _source(extraInstruction: '\x01'),
        _source(extraInstruction: ' \\t "ExternalFrame"'),
      ]) {
        final (xml, _, result) = _convert(bytes);
        expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
        expect(result.preservedCounts['binaryHyperlinkFields'], isNull);
      }
    },
  );

  test(
    'native bookmark field keeps its HFD-backed target and source bytes',
    () {
      final bytes = File(
        'test/fixtures/word_native/bookmarks-native-hyperlink.doc',
      ).readAsBytesSync();
      final original = Uint8List.fromList(bytes);
      final (xml, _, result) = _convert(bytes);
      expect(
        xml.findAllElements('instrText', namespace: _w).single.innerText,
        contains(r'\l "Beta"'),
      );
      expect(result.preservedCounts['binaryHyperlinkFields'], 1);
      expect(result.preservedCounts['bookmarks'], 16);
      expect(bytes, orderedEquals(original));
    },
  );
}
