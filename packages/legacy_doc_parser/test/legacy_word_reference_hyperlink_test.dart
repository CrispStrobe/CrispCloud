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

Uint8List _location(String target, {bool nativePadding = false}) {
  final bytes = Uint8List.fromList([
    ...List.filled(68, 0),
    8,
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
    0,
    0xaa,
    0,
    0x4b,
    0xa9,
    0x0b,
    ...wordU32(2),
    ...wordU32(8),
    ...wordU32(target.length + 1),
    for (final unit in target.codeUnits) ...wordU16(unit),
    0,
    0,
    if (nativePadding) ...[0, 0],
  ]);
  final data = ByteData.sublistView(bytes);
  data.setInt32(0, bytes.length, Endian.little);
  data.setUint16(4, 68, Endian.little);
  return bytes;
}

Uint8List _source({
  String type = 'REF',
  String target = 'Target_A',
  bool quoted = false,
  bool nativePadding = false,
  bool referenced = true,
  String? instruction,
  Uint8List? payload,
}) {
  final targetToken = quoted ? '"$target"' : target;
  final text =
      'α\x13${instruction ?? ' $type $targetToken \\h \x01'}\x14CACHED\x15\r';
  final marker = 8192 + text.indexOf('\x01') * 2;
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text, compressed: false)],
    characterRuns: [
      WordFixtureFkpRun(8192, marker),
      WordFixtureFkpRun(
        marker,
        marker + 2,
        properties: [
          ...wordSprm(0x0855, [1]),
          if (referenced) ...[
            ...wordSprm(0x0806, [1]),
            ...wordSprm(0x6a03, wordU32(16)),
          ],
        ],
      ),
      WordFixtureFkpRun(marker + 2, 8192 + 2 * text.length),
    ],
    extraStreams: {
      'Data': Uint8List.fromList([
        ...List.filled(16, 0),
        ...payload ?? _location(target, nativePadding: nativePadding),
      ]),
    },
  ).build();
}

(XmlDocument, Map, LegacyWordStructuredConversion) _convert(Uint8List bytes) {
  final output = convertLegacyWord(bytes);
  final zip = ZipDecoder().decodeBytes(output.bytes);
  return (
    XmlDocument.parse(utf8.decode(zip.findFile('word/document.xml')!.content)),
    jsonDecode(
          utf8.decode(zip.findFile('word/evidence/manifest.json')!.content),
        )
        as Map,
    output,
  );
}

void main() {
  for (final type in ['REF', 'PAGEREF', 'NOTEREF']) {
    for (final padded in [false, true]) {
      test('$type retains matching location; nativePadding=$padded', () {
        final bytes = _source(type: type, nativePadding: padded);
        final before = Uint8List.fromList(bytes);
        final original = parseLegacyWordDocument(bytes).fields.single;
        final (xml, evidence, output) = _convert(bytes);
        final instruction = xml
            .findAllElements('instrText', namespace: _w)
            .single
            .innerText;
        expect(instruction, original.instruction.replaceAll('\x01', ' '));
        expect(instruction.length, original.instruction.length);
        expect(output.preservedCounts['binaryReferenceFields'], 1);
        expect(output.preservedCounts['binaryHyperlinkFields'], isNull);
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
          'αCACHED',
        );
        final record = (evidence['records'] as List).singleWhere(
          (r) => r['kind'] == 'binaryReferenceField',
        );
        expect(record['instruction'], original.instruction);
        expect(record['emittedInstruction'], instruction);
        expect(record['recoveredNativeTerminator'], padded);
        expect(bytes, orderedEquals(before));
      });
    }
  }
  test('quoted Unicode reference retains exact target spelling', () {
    final (xml, _, output) = _convert(
      _source(target: 'Ziel東京😀', quoted: true, nativePadding: true),
    );
    expect(
      xml.findAllElements('instrText', namespace: _w).single.innerText,
      ' REF "Ziel東京😀" \\h  ',
    );
    expect(output.preservedCounts['binaryReferenceFields'], 1);
  });

  final invalid = <String, void Function(Uint8List)>{
    'wrong CLSID': (b) => b[69] ^= 1,
    'wrong version': (b) => b[85] = 3,
    'additional traversal flags': (b) => b[68] |= 1,
    'absolute location flags': (b) => b[89] = 10,
    'extra field flags': (b) => b[89] |= 0x10,
    'unbounded length': (b) =>
        ByteData.sublistView(b).setUint32(93, 0xffffffff, Endian.little),
    'short length': (b) => b[93] -= 1,
    'unterminated location': (b) => b[b.length - 4] = 65,
    'nonzero extra word': (b) => b[b.length - 1] = 1,
    'embedded NUL': (b) {
      b[97] = 0;
      b[98] = 0;
    },
    'unpaired surrogate': (b) {
      b[97] = 0;
      b[98] = 0xd8;
    },
  };
  for (final entry in invalid.entries) {
    test('reference ${entry.key} stays inert', () {
      final payload = _location('Target_A', nativePadding: true);
      entry.value(payload);
      final (xml, _, output) = _convert(_source(payload: payload));
      expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
      expect(output.preservedCounts['binaryReferenceFields'], isNull);
      expect(
        output.limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
      expect(
        xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
        'αCACHED',
      );
    });
  }
  test(
    'recovery requires reference type, explicit h, exact target and one extra word',
    () {
      final extra = Uint8List.fromList([
        ..._location('Target_A', nativePadding: true),
        0,
        0,
      ]);
      ByteData.sublistView(extra).setInt32(0, extra.length, Endian.little);
      for (final bytes in [
        _source(referenced: false, nativePadding: true),
        _source(payload: _location('Other', nativePadding: true)),
        _source(payload: extra),
        _source(instruction: ' REF Target_A \x01', nativePadding: true),
        _source(instruction: ' REF Target_A \\h \\p \x01', nativePadding: true),
        _source(instruction: ' REF Target_A \\h \x01\x01', nativePadding: true),
        _source(
          instruction: ' HYPERLINK \\l "Target_A"\x01',
          nativePadding: true,
        ),
        _source(type: 'QUOTE', nativePadding: true),
      ]) {
        final (xml, _, output) = _convert(bytes);
        expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
        expect(output.preservedCounts['binaryReferenceFields'], isNull);
        expect(output.preservedCounts['binaryHyperlinkFields'], isNull);
      }
    },
  );
  test(
    'native REF location retains cached result and discloses exact padding',
    () {
      final bytes = File(
        'test/fixtures/word_native/reference-hyperlink-native.doc',
      ).readAsBytesSync();
      final before = Uint8List.fromList(bytes);
      final source = parseLegacyWordDocument(bytes);
      final (xml, evidence, output) = _convert(bytes);
      final instructions = xml
          .findAllElements('instrText', namespace: _w)
          .map((e) => e.innerText)
          .toList();
      expect(instructions, [
        ' REF Target_A \\h  ',
        ' HYPERLINK  \\l "Target_A" ',
        'QUOTE "LITERAL-β"',
      ]);
      expect(source.fields.map((f) => f.storedResult), [
        'CACHED-REF',
        'CACHED-LINK',
        'CACHED-QUOTE',
      ]);
      expect(
        xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
        'ANCHOR-αREF:[CACHED-REF]LINK:[CACHED-LINK]QUOTE:[CACHED-QUOTE]',
      );
      expect(output.preservedCounts['binaryReferenceFields'], 1);
      expect(output.preservedCounts['binaryHyperlinkFields'], 1);
      expect(output.preservedCounts['fields'], 3);
      final record = (evidence['records'] as List).singleWhere(
        (r) => r['kind'] == 'binaryReferenceField',
      );
      expect(record['recoveredNativeTerminator'], isTrue);
      expect(record['instruction'], source.fields.first.instruction);
      expect(bytes, orderedEquals(before));
    },
  );
}
