// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/media_word_fixture.dart';
import 'support/structured_word_fixture.dart';

Uint8List _source({
  int declared = 1,
  int actual = 2,
  int imageIndex = 2,
  bool duplicateStore = false,
  bool embedded = false,
  int entryVersion = 2,
  bool trailing = false,
  void Function(ByteData)? mutateSecond,
}) {
  final blip = pictureBlip();
  final entries = [
    for (var i = 0; i < actual; i++)
      Uint8List.fromList(
        blipStoreEntry(blip, delayOffset: embedded ? null : 20000 + i * 512),
      ),
  ];
  for (final entry in entries) {
    final data = ByteData.sublistView(entry);
    data.setUint16(0, (6 << 4) | entryVersion, Endian.little);
  }
  if (entries.length > 1) {
    mutateSecond?.call(ByteData.sublistView(entries[1]));
  }
  final store = officeArtRecord(
    0xf001,
    [for (final entry in entries) ...entry, if (trailing) 0],
    version: 15,
    instance: declared,
  );
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('A\x08B\r')],
    extraTablePairs: {
      40: drawingAnchor(),
      50: [
        ...officeArtRecord(0xf000, [
          ...store,
          if (duplicateStore) ...store,
        ], version: 15),
        0,
        ...officeArtRecord(
          0xf002,
          officeArtRecord(
            0xf003,
            pictureShape(imageIndex: imageIndex),
            version: 15,
          ),
          version: 15,
        ),
      ],
    },
    characterRuns: [
      WordFixtureFkpRun(8192, 8196, properties: wordSprm(0x0855, [1])),
    ],
  ).build(
    mutate: (word, _) {
      for (var i = 0; i < actual; i++) {
        for (var j = 0; j < blip.length; j++) {
          word.setUint8(20000 + i * 512 + j, blip[j]);
        }
      }
    },
  );
}

void main() {
  test('matching BLIP entry counts retain the ordinary strict path', () {
    final document = parseLegacyWordDocument(_source(declared: 2));
    expect(document.media.notices, isEmpty);
    expect(document.media.assets, hasLength(1));
    expect(document.media.assets.single.bytes, mediaFixturePng());
  });

  test(
    'constant-one delayed store resolves all bounded entries with evidence',
    () {
      final bytes = _source(), before = Uint8List.fromList(_source());
      final document = parseLegacyWordDocument(bytes);
      expect(bytes, before);
      expect(document.media.assets, hasLength(2));
      expect(
        document.media.drawings.single.imageId,
        document.media.assets[1].id,
      );
      expect(document.media.assets.every((a) => a.isRenderable), isTrue);
      final notice = document.media.notices.single;
      expect(notice.issue, LegacyWordMediaIssue.recoveredBlipStoreCount);
      expect(notice.source.structure, 'OfficeArtBStoreContainer/recInstance');
      expect(notice.source.length, 96);
      final conversion = convertLegacyWordDocument(document);
      expect(
        conversion.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      final archive = ZipDecoder().decodeBytes(conversion.bytes);
      expect(
        archive.files
            .where((f) => f.name.endsWith('.json'))
            .any(
              (f) => utf8
                  .decode(f.content as List<int>)
                  .contains('recoveredBlipStoreCount'),
            ),
        isTrue,
      );
    },
  );

  test('recovery does not relax other counts or record forms', () {
    for (final bytes in [
      _source(declared: 0),
      _source(declared: 3),
      _source(declared: 1, actual: 0),
      _source(duplicateStore: true),
      _source(embedded: true),
      _source(entryVersion: 0),
      _source(trailing: true),
      _source(mutateSecond: (d) => d.setUint16(2, 0xf008, Endian.little)),
      _source(mutateSecond: (d) => d.setUint8(8 + 33, 2)),
      _source(mutateSecond: (d) => d.setUint32(8 + 24, 0, Endian.little)),
      _source(
        mutateSecond: (d) => d.setUint32(8 + 28, 0xffffffff, Endian.little),
      ),
    ]) {
      expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
    }
  });

  test(
    'all delayed payloads validate even when the corrupt slot is unreferenced',
    () {
      for (final bytes in [
        _source(
          imageIndex: 1,
          mutateSecond: (d) => d.setUint32(8 + 28, 0xfffffff0, Endian.little),
        ),
        _source(
          imageIndex: 1,
          mutateSecond: (d) => d.setUint32(8 + 20, 7, Endian.little),
        ),
        _source(
          imageIndex: 1,
          mutateSecond: (d) => d.setUint32(8 + 20, 500, Endian.little),
        ),
        _source(imageIndex: 3),
      ]) {
        expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
      }
    },
  );

  test('native regenerated Word16 DOC retains both linked images', () {
    final bytes = File(
      'test/fixtures/word_native/word16-page-origin-lo-blip-count.doc',
    ).readAsBytesSync();
    final before = Uint8List.fromList(bytes);
    final document = parseLegacyWordDocument(bytes);
    expect(document.media.assets, hasLength(2));
    expect(document.media.drawings, hasLength(2));
    expect(
      document.media.drawings.map((d) => d.imageId).toSet(),
      document.media.assets.map((a) => a.id).toSet(),
    );
    expect(
      document.media.notices.map((n) => n.issue),
      contains(LegacyWordMediaIssue.recoveredBlipStoreCount),
    );
    final conversion = convertLegacyWordDocument(document);
    expect(conversion.preservedCounts['drawingReferences'], 2);
    expect(bytes, before);
  });
}
