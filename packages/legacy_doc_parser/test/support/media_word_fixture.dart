// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import 'structured_word_fixture.dart';

Uint8List mediaFixturePng() => base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aB3sAAAAASUVORK5CYII=',
);

Uint8List officeArtRecord(
  int type,
  List<int> payload, {
  int version = 0,
  int instance = 0,
}) => Uint8List.fromList([
  ...wordU16(version | (instance << 4)),
  ...wordU16(type),
  ...wordU32(payload.length),
  ...payload,
]);

Uint8List pictureBlip({Uint8List? png}) => officeArtRecord(0xf01e, [
  ...List.filled(16, 0),
  255,
  ...png ?? mediaFixturePng(),
], instance: 0x6e0);

Uint8List pictureShape({
  int shapeId = 1025,
  int imageIndex = 1,
  int? textboxId,
  int? nextShapeId,
  int shapeFlags = 0x0a00,
  Map<int, int> extraProperties = const {},
}) {
  final properties = <int, int>{
    0x4104: imageIndex,
    ...extraProperties,
    if (nextShapeId != null) 0x008a: nextShapeId,
  };
  return officeArtRecord(0xf004, [
    ...officeArtRecord(
      0xf00a,
      [...wordU32(shapeId), ...wordU32(shapeFlags)],
      version: 2,
      instance: 75,
    ),
    ...officeArtRecord(
      0xf00b,
      [
        for (final property in properties.entries) ...[
          ...wordU16(property.key),
          ...wordU32(property.value),
        ],
      ],
      version: 3,
      instance: properties.length,
    ),
    if (textboxId != null) ...officeArtRecord(0xf00d, wordU32(textboxId)),
  ], version: 15);
}

Uint8List inlinePictureData({
  Uint8List? blip,
  String? storedName,
  Map<int, int> properties = const {},
  int shapeFlags = 0x0a00,
}) {
  final shape = pictureShape(
    extraProperties: properties,
    shapeFlags: shapeFlags,
  );
  final image = blip ?? pictureBlip();
  final name = storedName?.codeUnits;
  final header = Uint8List(68);
  final data = ByteData.sublistView(header);
  data.setUint32(
    0,
    68 + (name == null ? 0 : name.length + 1) + shape.length + image.length,
    Endian.little,
  );
  data.setUint16(4, 68, Endian.little);
  data.setUint16(6, name == null ? 0x64 : 0x66, Endian.little);
  data.setInt16(28, 1440, Endian.little);
  data.setInt16(30, 720, Endian.little);
  data.setUint16(32, 1000, Endian.little);
  data.setUint16(34, 1000, Endian.little);
  return Uint8List.fromList([
    ...header,
    if (name != null) ...[name.length, ...name],
    ...shape,
    ...image,
  ]);
}

Uint8List inlinePictureWordFixture({
  Uint8List? picture,
  bool special = true,
  int location = 16,
  List<int> characterProperties = const [],
}) {
  final payload = picture ?? inlinePictureData();
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('A\x01B\r')],
    characterRuns: [
      const WordFixtureFkpRun(8192, 8193),
      WordFixtureFkpRun(
        8193,
        8194,
        properties: [
          ...wordSprm(0x0855, [special ? 1 : 0]),
          ...wordSprm(0x6a03, wordU32(location)),
          ...characterProperties,
        ],
      ),
      const WordFixtureFkpRun(8194, 8196),
    ],
    extraStreams: {
      'Data': Uint8List.fromList([...List.filled(16, 0xab), ...payload]),
    },
  ).build();
}

Uint8List blipStoreEntry(Uint8List blip, {int? delayOffset}) => officeArtRecord(
  0xf007,
  [
    6,
    6,
    ...List.filled(16, 0),
    ...wordU16(255),
    ...wordU32(blip.length),
    ...wordU32(1),
    ...wordU32(delayOffset ?? 0xffffffff),
    0,
    0,
    0,
    0,
    if (delayOffset == null) ...blip,
  ],
  version: 2,
  instance: 6,
);

Uint8List drawingContent({
  required Uint8List shape,
  Uint8List? blip,
  int? delayOffset,
}) => Uint8List.fromList([
  ...officeArtRecord(0xf000, [
    if (blip != null)
      ...officeArtRecord(
        0xf001,
        blipStoreEntry(blip, delayOffset: delayOffset),
        version: 15,
        instance: 1,
      ),
  ], version: 15),
  0,
  ...officeArtRecord(
    0xf002,
    officeArtRecord(0xf003, shape, version: 15),
    version: 15,
  ),
]);

Uint8List drawingAnchor({
  int shapeId = 1025,
  int cp = 1,
  int limit = 4,
  int? flags,
  int left = 120,
  int top = 240,
  int right = 1560,
  int bottom = 960,
}) => Uint8List.fromList([
  ...wordU32(cp),
  ...wordU32(limit),
  ...wordU32(shapeId),
  ...wordU32(left),
  ...wordU32(top),
  ...wordU32(right),
  ...wordU32(bottom),
  ...wordU16(flags ?? ((1 << 1) | (2 << 3) | (3 << 5) | 0xc000)),
  ...wordU32(0),
]);

Uint8List floatingPictureWordFixture({
  bool delayed = false,
  bool special = true,
  int? textboxId,
  int? nextShapeId,
  List<int> characterProperties = const [],
  Map<int, int> imageProperties = const {},
  int shapeFlags = 0x0a00,
  int? anchorFlags,
  (int, int, int, int) anchorBounds = (120, 240, 1560, 960),
}) {
  final blip = pictureBlip();
  return StructuredWordFixture(
    pieces: const [WordFixturePiece('A\x08B\r')],
    extraTablePairs: {
      40: drawingAnchor(
        flags: anchorFlags,
        left: anchorBounds.$1,
        top: anchorBounds.$2,
        right: anchorBounds.$3,
        bottom: anchorBounds.$4,
      ),
      50: drawingContent(
        shape: pictureShape(
          textboxId: textboxId,
          nextShapeId: nextShapeId,
          extraProperties: imageProperties,
          shapeFlags: shapeFlags,
        ),
        blip: blip,
        delayOffset: delayed ? 20000 : null,
      ),
    },
    characterRuns: [
      WordFixtureFkpRun(
        8192,
        8196,
        properties: [
          ...wordSprm(0x0855, [special ? 1 : 0]),
          ...characterProperties,
        ],
      ),
    ],
  ).build(
    mutate: delayed
        ? (word, _) {
            for (var i = 0; i < blip.length; i++) {
              word.setUint8(20000 + i, blip[i]);
            }
          }
        : null,
  );
}

Uint8List oleWordFixture({
  bool linked = false,
  bool zombie = false,
  bool fieldTable = true,
  List<int> characterProperties = const [],
  Uint8List? oleRecord,
}) {
  final original = StructuredWordFixture(
    pieces: const [WordFixturePiece('\x13EMBED\x14X\x15\r')],
    characterRuns: [
      const WordFixtureFkpRun(8192, 8198),
      WordFixtureFkpRun(
        8198,
        8199,
        properties: [
          ...wordSprm(0x0855, [1]),
          ...wordSprm(0x080a, [1]),
          ...wordSprm(0x6a03, wordU32(42)),
          ...characterProperties,
        ],
      ),
      const WordFixtureFkpRun(8199, 8202),
    ],
    extraTablePairs: {
      if (fieldTable)
        16: [
          ...wordU32(0),
          ...wordU32(6),
          ...wordU32(8),
          ...wordU32(10),
          0x13,
          58,
          0x14,
          0,
          0x15,
          zombie ? 0x82 : 0x80,
        ],
    },
    extraStreams: {
      'ObjectPool/_42/\x01Ole':
          oleRecord ??
          Uint8List.fromList([
            ...wordU32(0x02000001),
            ...wordU32(linked ? 1 : 0),
            ...List.filled(12, 0),
          ]),
      'ObjectPool/_42/CONTENTS': Uint8List.fromList([1, 2, 3, 4]),
      'ObjectPool/_42/Nested/extra': Uint8List.fromList([5, 6, 7]),
    },
  ).build();
  return rewriteCompoundFixture(original, (writer) {
    writer.addStorage(
      'ObjectPool/_42',
      clsid: Uint8List.fromList(List.generate(16, (i) => i + 1)),
      stateBits: 0x1234,
      createdFiletime: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 0]),
    );
    writer.addStorage(
      'ObjectPool/_42/Nested',
      clsid: Uint8List.fromList(List.filled(16, 7)),
    );
  });
}

Uint8List rewriteCompoundFixture(
  Uint8List original,
  void Function(CfbfWriter writer) update,
) {
  final source = BoundedCfbReader(original);
  final writer = CfbfWriter();
  void copy(CfbfDirectoryEntry parent, String prefix) {
    for (final entry in source.childrenOf(parent)) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isStorage) {
        writer.addStorage(path);
        copy(entry, path);
      } else {
        writer.addStream(path, source.readEntry(entry));
      }
    }
  }

  copy(source.root, '');
  update(writer);
  return writer.build();
}
