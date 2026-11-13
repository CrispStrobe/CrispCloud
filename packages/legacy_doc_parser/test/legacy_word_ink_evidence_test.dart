// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

// Independently assembled MS-ODRAW IMsoInkData. The default stream is the
// documented ISF 1.0 version plus a zero-byte object. This tests extraction,
// not the rendering of pen packets or the behavior of native Office ink.
Uint8List _envelope([List<int> data = const [0, 0]]) => Uint8List.fromList([
  0x34,
  0x1a,
  0x7c,
  0x93,
  0x1d,
  0x15,
  0x10,
  0x46,
  0x9c,
  0xa6,
  0xa8,
  0xcc,
  0x9b,
  0xdb,
  0x5d,
  0x83,
  ...wordU32(data.length),
  ...data,
]);

LegacyWordOfficeArtShape _shape(Uint8List bytes) =>
    parseLegacyWordDocument(bytes).media.drawings.single.shape!;

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes))
    if (file.isFile) file.name: file.content,
};

List<Map<String, dynamic>> _records(Map<String, Uint8List> files) =>
    (jsonDecode(utf8.decode(files['word/evidence/manifest.json']!))['records']
            as List)
        .cast<Map<String, dynamic>>();

void _noActiveInk(Map<String, Uint8List> files) {
  for (final entry in files.entries) {
    if (!entry.key.endsWith('.xml')) continue;
    final xml = XmlDocument.parse(utf8.decode(entry.value));
    expect(
      xml.findAllElements(
        'ink',
        namespace: 'urn:schemas-microsoft-com:office:office',
      ),
      isEmpty,
      reason: entry.key,
    );
  }
}

Uint8List _unrelatedComment({bool ink = false, bool withPayload = true}) {
  const main = 'A\x08B\x05C\r', comment = '\x05Comment\r';
  final shape = officeArtRecord(0xf004, [
    ...officeArtRecord(
      0xf00a,
      [...wordU32(1025), ...wordU32(0x0a00)],
      version: 2,
      instance: 1,
    ),
    ...shapePropertyRecord(
      values: {0x0307: 1, 0x073f: 0x00090009},
      complex: {if (withPayload) 0x0700: _envelope()},
    ),
  ], version: 15);
  return storyWordFixture(
    main: main,
    comments: '$comment\r',
    characterRuns: [
      const WordFixtureFkpRun(8192, 16386),
      WordFixtureFkpRun(16386, 16388, properties: wordSprm(0x0855, [1])),
      const WordFixtureFkpRun(16388, 28672),
    ],
    tablePairs: {
      4: storyPlc([3, 0xffffffff], storyCommentRecord()),
      5: storyPlc([0, comment.length, 0xffffffff]),
      36: storyXst('Author'),
      40: drawingAnchor(),
      50: [
        ...officeArtRecord(0xf000, [], version: 15),
        0,
        ...officeArtRecord(
          0xf002,
          officeArtRecord(0xf003, shape, version: 15),
          version: 15,
        ),
      ],
      112: [
        ...wordU32(0),
        ...wordU16(0),
        ...wordU32(0),
        ...wordU32(0),
        ...wordU32(ink ? 2 : 0),
      ],
    },
    mutate: (fib, _) {
      fib.setUint16(2, 0x101, Endian.little);
      fib.setUint16(152, 136, Endian.little);
    },
  );
}

void main() {
  test(
    'unwraps the exact bounded IMsoInkData bytes without changing source',
    () {
      final source = officeArtShapeWordFixture(
        values: {0x073f: 0x000f000d},
        complex: {0x0700: _envelope()},
      );
      final before = Uint8List.fromList(source);
      final ink = _shape(source).ink!;
      expect(ink.data, [0, 0]);
      expect(ink.headerStatus, LegacyWordInkHeaderStatus.version1Extent);
      expect(ink.annotation, isTrue);
      expect(ink.hitTestInk, isTrue);
      expect(ink.renderShape, isFalse);
      expect(ink.renderInk, isTrue);
      expect(() => ink.data![0] = 42, throwsUnsupportedError);
      expect(source, before);
      source.fillRange(0, source.length, 0);
      expect(ink.data, [0, 0]);
    },
  );

  test('cascades independent ink use bits and preserves unspecified flags', () {
    final shape = _shape(
      officeArtShapeWordFixture(
        defaults: {0x073f: 0x000d000d},
        values: {0x073f: 0x00010000},
        additionalProperties: [
          shapePropertyRecord(values: {0x073f: 0x00020002}),
        ],
      ),
    );
    final ink = shape.ink!;
    expect(ink.annotation, isTrue);
    expect(ink.hitTestInk, isTrue);
    expect(ink.renderInk, isFalse);
    expect(ink.renderShape, isTrue);
    expect(ink.data, isNull);
    expect(ink.headerStatus, isNull);
    final unused = _shape(
      officeArtShapeWordFixture(values: {0x073f: 0xffff}),
    ).ink!;
    expect(
      [
        unused.annotation,
        unused.hitTestInk,
        unused.renderInk,
        unused.renderShape,
      ],
      [null, null, null, null],
    );
  });

  test('keeps envelope validation distinct from ISF packet validation', () {
    for (final (bytes, status) in <(List<int>, LegacyWordInkHeaderStatus)>[
      ([0, 0], LegacyWordInkHeaderStatus.version1Extent),
      ([0, 1, 255], LegacyWordInkHeaderStatus.version1Extent),
      (
        [0, 0x80, 1, ...List.filled(128, 255)],
        LegacyWordInkHeaderStatus.version1Extent,
      ),
      ([1, 0], LegacyWordInkHeaderStatus.unsupportedVersion),
      ([], LegacyWordInkHeaderStatus.invalidHeader),
      ([0], LegacyWordInkHeaderStatus.invalidHeader),
      ([0, 2, 255], LegacyWordInkHeaderStatus.invalidHeader),
      ([0, 0, 255], LegacyWordInkHeaderStatus.invalidHeader),
      ([0, ...List.filled(10, 0x80)], LegacyWordInkHeaderStatus.invalidHeader),
      (
        [0, 0xff, 0xff, 0xff, 0xff, 0x0f],
        LegacyWordInkHeaderStatus.invalidHeader,
      ),
    ]) {
      final ink = _shape(
        officeArtShapeWordFixture(complex: {0x0700: _envelope(bytes)}),
      ).ink!;
      expect(ink.data, bytes);
      expect(ink.headerStatus, status);
      expect(
        ink.annotation,
        isNull,
        reason: 'an ISF payload does not imply an annotation',
      );
    }
  });

  test('rejects forged envelope identity, lengths and noncomplex pointers', () {
    final badGuid = _envelope()..[0] = 0;
    final badCount = _envelope();
    ByteData.sublistView(badCount).setUint32(16, 0xffffffff, Endian.little);
    for (final bytes in [
      Uint8List(0),
      Uint8List(19),
      badGuid,
      badCount,
      _envelope().sublist(0, 21),
    ]) {
      expect(
        () => _shape(officeArtShapeWordFixture(complex: {0x0700: bytes})),
        throwsFormatException,
      );
    }
    expect(
      () => _shape(officeArtShapeWordFixture(values: {0x0700: 42})),
      throwsFormatException,
    );
    expect(
      () => _shape(officeArtShapeWordFixture(complex: {0x073f: Uint8List(4)})),
      throwsFormatException,
    );
    expect(
      _shape(officeArtShapeWordFixture(values: {0x0700: 0})).ink!.data,
      isNull,
    );
    expect(
      () => LegacyWordOfficeArtInk(
        data: Uint8List(LegacyWordOfficeArtInk.maxDataLength + 1),
      ),
      throwsFormatException,
    );
  });

  test(
    'evidence has exact ISF bytes and source artifact, without native ink',
    () {
      final source = officeArtShapeWordFixture(
        values: {0x073f: 0x00090009},
        complex: {0x0700: _envelope()},
      );
      final document = parseLegacyWordDocument(source);
      final result = convertLegacyWordDocument(document),
          files = _parts(result.bytes);
      final evidence = _records(files);
      final ink = evidence.singleWhere((row) => row['kind'] == 'officeArtInk');
      expect(files[ink['part']], [0, 0]);
      expect(ink['shapeId'], 1025);
      expect(ink['story'], 'main');
      expect(ink['cp'], 1);
      expect(ink['headerStatus'], 'version1Extent');
      expect(ink['strokeSemanticsDecoded'], isTrue);
      expect(ink['strokeDecodeStatus'], 'decoded');
      expect(ink['strokeCount'], 0);
      expect(ink['pointCount'], 0);
      expect(ink['nativeInkEmitted'], isFalse);
      expect(ink['annotation'], isTrue);
      expect(ink.containsKey('commentId'), isFalse);
      final artifact = document.media.artifacts.singleWhere(
        (a) => a.id == ink['officeArtArtifactId'],
      );
      final copied = evidence.singleWhere((row) => row['id'] == artifact.id);
      expect(files[copied['part']], artifact.bytes);
      expect(result.preservedCounts['inkPayloads'], 1);
      expect(result.preservedCounts['editableShapes'], isNull);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.notesComments),
      );
      _noActiveInk(files);
    },
  );

  for (final mode in ['compressed', 'uncompressed']) {
    test(
      'nonempty WPF $mode strokes retain exact OfficeArt occurrence evidence',
      () {
        final payload = File(
          'test/fixtures/ink_wpf/pressure-ramp/$mode.isf',
        ).readAsBytesSync();
        final source = officeArtShapeWordFixture(
          values: {0x073f: 0x00090009},
          complex: {0x0700: _envelope(payload)},
        );
        final document = parseLegacyWordDocument(source);
        final decoded = document.media.drawings.single.shape!.ink!.decoding!;
        expect(decoded.status, LegacyWordInkDecodeStatus.decoded);
        expect(
          decoded.strokes.single.points.map((point) => point.normalPressure),
          [0, 127, 511, 895, 1023],
        );
        final result = convertLegacyWordDocument(document),
            parts = _parts(result.bytes);
        final ink = _records(
          parts,
        ).singleWhere((row) => row['kind'] == 'officeArtInk');
        expect(parts[ink['part']], orderedEquals(payload));
        expect(ink['strokeSemanticsDecoded'], isTrue);
        expect(ink['strokeCount'], 1);
        expect(ink['pointCount'], 5);
        expect(ink['nativeInkEmitted'], isFalse);
        expect(ink.containsKey('commentId'), isFalse);
        expect(result.preservedCounts['decodedInkPayloads'], 1);
        expect(result.preservedCounts['decodedInkStrokes'], 1);
        _noActiveInk(parts);
      },
    );
  }

  test('discussion anchors do not join unrelated ink payloads to comments', () {
    final document = parseLegacyWordDocument(_unrelatedComment());
    expect(document.media.drawings.single.shape!.discussionAnchor, isTrue);
    expect(document.commentReferences.single.ink, isFalse);
    final files = _parts(convertLegacyWordDocument(document).bytes);
    final record = _records(
      files,
    ).singleWhere((row) => row['kind'] == 'officeArtInk');
    expect(record['discussionAnchor'], isTrue);
    expect(record['story'], 'main');
    expect(record.containsKey('commentId'), isFalse);
    expect(
      _records(files).where((row) => row['kind'] == 'inkComment'),
      isEmpty,
    );
    for (final value in [0, 2, 42, 0xffffffff]) {
      expect(
        _shape(
          officeArtShapeWordFixture(values: {0x0307: value}),
        ).discussionAnchor,
        isFalse,
      );
    }
    _noActiveInk(files);
  });

  test('annotation flags without a payload remain explicit loss evidence', () {
    final result = convertLegacyWord(
      _unrelatedComment(ink: true, withPayload: false),
    );
    final files = _parts(result.bytes), records = _records(files);
    final shape = records.singleWhere((row) => row['kind'] == 'officeArtInk');
    expect(shape['hasPayload'], isFalse);
    expect(shape.containsKey('part'), isFalse);
    expect(records.where((row) => row['kind'] == 'inkComment'), hasLength(1));
    expect(result.preservedCounts['inkPayloads'], isNull);
    expect(
      result.limitations,
      contains(LegacyWordConversionLimitation.notesComments),
    );
    _noActiveInk(files);
  });

  test('inline picture occurrences also retain their separate ink payload', () {
    final shape = officeArtRecord(0xf004, [
      ...officeArtRecord(
        0xf00a,
        [...wordU32(1025), ...wordU32(0x0a00)],
        version: 2,
        instance: 75,
      ),
      ...shapePropertyRecord(
        values: {0x4104: 1, 0x073f: 0x00010001},
        complex: {0x0700: _envelope()},
      ),
    ], version: 15);
    final blip = pictureBlip();
    final header = inlinePictureData().sublist(0, 68);
    ByteData.sublistView(
      header,
    ).setUint32(0, 68 + shape.length + blip.length, Endian.little);
    final source = inlinePictureWordFixture(
      picture: Uint8List.fromList([...header, ...shape, ...blip]),
    );
    final parsed = parseLegacyWordDocument(source);
    expect(parsed.media.pictures.single.shape!.ink!.data, [0, 0]);
    final result = convertLegacyWordDocument(parsed),
        files = _parts(result.bytes);
    final record = _records(
      files,
    ).singleWhere((row) => row['kind'] == 'officeArtInk');
    expect(record['pictureId'], parsed.media.pictures.single.id);
    expect(files[record['part']], [0, 0]);
    expect(result.preservedCounts['images'], 1);
    expect(result.preservedCounts['inkPayloads'], 1);
    _noActiveInk(files);
  });

  test('public ink models stay inert even without an OfficeArt artifact', () {
    final base = parseLegacyWordDocument(officeArtShapeWordFixture());
    final old = base.media.drawings.single;
    final data = Uint8List.fromList([0, 0]);
    final ink = LegacyWordOfficeArtInk(data: data, renderInk: true);
    data[1] = 255;
    final source = LegacyWordDocument(
      blocks: base.blocks,
      sections: base.sections,
      plainText: base.plainText,
      safeHtml: '',
      media: LegacyWordMediaCatalog.from(
        drawings: [
          LegacyWordDrawing(
            shapeId: old.shapeId,
            anchorCp: old.anchorCp,
            headerStory: false,
            leftTwips: old.leftTwips,
            topTwips: old.topTwips,
            rightTwips: old.rightTwips,
            bottomTwips: old.bottomTwips,
            horizontalOrigin: old.horizontalOrigin,
            verticalOrigin: old.verticalOrigin,
            wrapMode: old.wrapMode,
            wrapSide: old.wrapSide,
            behindText: old.behindText,
            anchorLocked: false,
            source: old.source,
            shape: LegacyWordOfficeArtShape(
              type: 1,
              geometry: old.shape!.geometry,
              ink: ink,
            ),
          ),
        ],
      ),
    );
    final result = convertLegacyWordDocument(source),
        files = _parts(result.bytes);
    final record = _records(
      files,
    ).singleWhere((row) => row['kind'] == 'officeArtInk');
    expect(files[record['part']], [0, 0]);
    expect(record['officeArtArtifactId'], isNull);
    expect(result.preservedCounts['editableShapes'], isNull);
    _noActiveInk(files);
  });
}
