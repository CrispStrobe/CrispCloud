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

Uint8List _urlHfd(String url, {bool absolute = true}) {
  // Independently authored MS-DOC NilPICF/HFD and MS-OSHARED URLMoniker.
  final result = Uint8List.fromList([
    ...List.filled(68, 0),
    0,
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
    ...wordU32(absolute ? 3 : 1),
    0xe0,
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
    ...wordU32((url.length + 1) * 2),
    for (final unit in url.codeUnits) ...wordU16(unit),
    0,
    0,
  ]);
  final data = ByteData.sublistView(result);
  data.setUint32(0, result.length, Endian.little);
  data.setUint16(4, 68, Endian.little);
  return result;
}

Uint8List _source({
  String url = 'https://example.com/path?x=1&y=2',
  bool quoted = true,
  bool referenced = true,
  Uint8List? payload,
  String suffix = '',
}) {
  final instruction = quoted ? '"$url"' : url;
  final text = 'α\x13 HYPERLINK $instruction\x01$suffix\x14Link\x15\r';
  final start = 8192 + text.indexOf('\x01') * 2;
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
        ...payload ?? _urlHfd(url),
      ]),
    },
  ).build();
}

(XmlDocument, LegacyWordStructuredConversion) _convert(Uint8List bytes) {
  final result = convertLegacyWord(bytes);
  final zip = ZipDecoder().decodeBytes(result.bytes);
  return (
    XmlDocument.parse(utf8.decode(zip.findFile('word/document.xml')!.content)),
    result,
  );
}

void main() {
  for (final (url, quoted, absolute) in [
    ('https://example.com/path?x=1&y=2', true, true),
    ('https://example.com/path', false, true),
    ('https://example.com/東京😀', true, true),
    ('mailto:person@example.com', true, true),
    ('../relative/document.html', true, false),
  ]) {
    test('qualifies exact URLMoniker $url, quoted=$quoted', () {
      final bytes = _source(
        url: url,
        quoted: quoted,
        payload: _urlHfd(url, absolute: absolute),
      );
      final before = Uint8List.fromList(bytes);
      final source = parseLegacyWordDocument(bytes).fields.single;
      final (xml, result) = _convert(bytes);
      final emitted = xml
          .findAllElements('instrText', namespace: _w)
          .single
          .innerText;
      expect(emitted, source.instruction.replaceAll('\x01', ' '));
      expect(emitted.length, source.instruction.length);
      expect(result.preservedCounts['binaryHyperlinkFields'], 1);
      expect(xml.findAllElements('fldChar', namespace: _w), hasLength(3));
      expect(
        xml
            .findAllElements('fldChar', namespace: _w)
            .first
            .getAttribute('fldLock', namespace: _w),
        '1',
      );
      expect(
        xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
        'αLink',
      );
      expect(bytes, orderedEquals(before));
    });
  }

  final malformed = <String, void Function(Uint8List)>{
    'wrong hyperlink CLSID': (b) => b[69] ^= 1,
    'wrong URL moniker CLSID': (b) => b[93] ^= 1,
    'wrong serialization version': (b) => b[85] = 3,
    'new-window traversal behavior': (b) => b[68] = 1,
    'claimed location': (b) => b[68] = 8,
    'display string flags': (b) => b[89] |= 0x10,
    'location flags': (b) => b[89] |= 8,
    'no moniker flags': (b) => b[89] = 2,
    'string moniker instead': (b) => b[90] = 1,
    'short URL byte count': (b) => b[109] -= 2,
    'odd URL byte count': (b) => b[109] -= 1,
    'oversized URL byte count': (b) =>
        ByteData.sublistView(b).setUint32(109, 0xffffffff, Endian.little),
    'unterminated URL': (b) => b[b.length - 2] = 65,
    'embedded NUL': (b) {
      b[113] = 0;
      b[114] = 0;
    },
    'unpaired surrogate': (b) {
      b[113] = 0;
      b[114] = 0xd8;
    },
  };
  for (final entry in malformed.entries) {
    test('${entry.key} stays inert', () {
      final payload = _urlHfd('https://example.com/path?x=1&y=2');
      entry.value(payload);
      final (xml, result) = _convert(_source(payload: payload));
      expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
      expect(xml.findAllElements('instrText', namespace: _w), isEmpty);
      expect(result.preservedCounts['binaryHyperlinkFields'], isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.fieldsLists),
      );
      expect(
        xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
        'αLink',
      );
    });
  }

  test(
    'unreferenced, conflicting and extra metadata cannot authorize stripping',
    () {
      final trailing = Uint8List.fromList([
        ..._urlHfd('https://example.com/path?x=1&y=2'),
        0,
        0,
      ]);
      ByteData.sublistView(
        trailing,
      ).setUint32(0, trailing.length, Endian.little);
      for (final bytes in [
        _source(referenced: false),
        _source(payload: _urlHfd('https://other.example/path')),
        _source(payload: trailing),
        _source(suffix: '\x01'),
        _source(suffix: ' \\t "OtherFrame"'),
      ]) {
        final (xml, result) = _convert(bytes);
        expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
        expect(result.preservedCounts['binaryHyperlinkFields'], isNull);
      }
    },
  );

  test('ambiguous or misplaced public-model artifacts remain inert', () {
    final document = parseLegacyWordDocument(_source());
    final artifact = document.media.artifacts.singleWhere(
      (a) => a.kind == LegacyWordArtifactKind.binaryData,
    );
    final source = artifact.source;
    LegacyWordOpaqueArtifact copied(LegacyWordSourceReference reference) =>
        LegacyWordOpaqueArtifact(
          id: 'copied-data',
          kind: artifact.kind,
          bytes: artifact.bytes,
          source: reference,
        );
    for (final artifacts in [
      [artifact, copied(source)],
      [
        copied(
          LegacyWordSourceReference(
            streamPath: 'Other',
            offset: source.offset,
            length: source.length,
            structure: source.structure,
            cp: source.cp,
          ),
        ),
      ],
      [
        copied(
          LegacyWordSourceReference(
            streamPath: source.streamPath,
            offset: source.offset,
            length: source.length - 1,
            structure: source.structure,
            cp: source.cp,
          ),
        ),
      ],
      [
        copied(
          LegacyWordSourceReference(
            streamPath: source.streamPath,
            offset: source.offset,
            length: source.length,
            structure: source.structure,
            cp: source.cp! + 1,
          ),
        ),
      ],
    ]) {
      final output = convertLegacyWordDocument(
        LegacyWordDocument(
          blocks: document.blocks,
          sections: document.sections,
          plainText: document.plainText,
          safeHtml: document.safeHtml,
          fields: document.fields,
          media: LegacyWordMediaCatalog.from(artifacts: artifacts),
        ),
      );
      final zip = ZipDecoder().decodeBytes(output.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(zip.findFile('word/document.xml')!.content),
      );
      expect(xml.findAllElements('fldChar', namespace: _w), isEmpty);
      expect(output.preservedCounts['binaryHyperlinkFields'], isNull);
    }
  });

  test('native source retains exact body, note and both header URL fields', () {
    final bytes = File(
      'test/fixtures/word_native/external-hyperlinks-native.doc',
    ).readAsBytesSync();
    final before = Uint8List.fromList(bytes);
    final source = parseLegacyWordDocument(bytes);
    final result = convertLegacyWord(bytes);
    final zip = ZipDecoder().decodeBytes(result.bytes);
    final expected = <String, String>{
      'word/document.xml': 'https://example.com/body',
      'word/footnotes.xml': 'https://example.com/note',
    };
    final body = XmlDocument.parse(
      utf8.decode(zip.findFile('word/document.xml')!.content),
    );
    final relationships = XmlDocument.parse(
      utf8.decode(zip.findFile('word/_rels/document.xml.rels')!.content),
    );
    for (final type in ['default', 'first']) {
      final reference = body
          .findAllElements('headerReference', namespace: _w)
          .singleWhere((e) => e.getAttribute('type', namespace: _w) == type);
      final id = reference.getAttribute(
        'id',
        namespace:
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
      );
      final target = relationships
          .findAllElements('Relationship')
          .singleWhere((e) => e.getAttribute('Id') == id)
          .getAttribute('Target');
      expected['word/$target'] = 'https://example.com/header';
    }
    expect(expected, hasLength(4));
    expect(source.fields, hasLength(4));
    for (final entry in expected.entries) {
      final xml = XmlDocument.parse(
        utf8.decode(zip.findFile(entry.key)!.content),
      );
      expect(
        xml.findAllElements('instrText', namespace: _w).single.innerText,
        ' HYPERLINK "${entry.value}" ',
      );
      expect(
        xml
            .findAllElements('fldChar', namespace: _w)
            .first
            .getAttribute('fldLock', namespace: _w),
        '1',
      );
    }
    expect(result.preservedCounts['binaryHyperlinkFields'], 4);
    final evidence =
        jsonDecode(
              utf8.decode(zip.findFile('word/evidence/manifest.json')!.content),
            )
            as Map;
    final records = (evidence['records'] as List)
        .where((r) => r['kind'] == 'binaryHyperlinkField')
        .toList();
    expect(records, hasLength(4));
    for (final record in records) {
      final original = source.fields.singleWhere(
        (f) => f.storyId == record['story'] && f.startCp == record['startCp'],
      );
      expect(record['instruction'], original.instruction);
      expect(
        record['emittedInstruction'],
        original.instruction.replaceAll('\x01', ' '),
      );
    }
    expect(bytes, orderedEquals(before));
  });
}
