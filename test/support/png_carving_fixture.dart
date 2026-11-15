// Original PNG unit fixture builder. MIT licensed with the carving service.
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;

const pngCarvingSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Uint8List pngCarvingChunk(String type, List<int> data, {int? crc}) {
  final result = Uint8List(data.length + 12);
  final view = ByteData.sublistView(result);
  view.setUint32(0, data.length, Endian.big);
  result.setRange(4, 8, type.codeUnits);
  result.setRange(8, 8 + data.length, data);
  view.setUint32(
    8 + data.length,
    crc ?? codecs.getCrc32(Uint8List.sublistView(result, 4, 8 + data.length)),
    Endian.big,
  );
  return result;
}

Uint8List pngCarvingHeader({
  int width = 2,
  int height = 2,
  int colorType = 2,
  int bitDepth = 8,
  int interlace = 0,
}) {
  final result = Uint8List(13);
  final view = ByteData.sublistView(result);
  view.setUint32(0, width, Endian.big);
  view.setUint32(4, height, Endian.big);
  result[8] = bitDepth;
  result[9] = colorType;
  result[12] = interlace;
  return result;
}

Uint8List pngCarvingPng({
  int width = 2,
  int height = 2,
  int colorType = 2,
  int bitDepth = 8,
  int interlace = 0,
  int seed = 7,
  List<int>? rawScanlines,
  List<int>? compressed,
  List<List<int>> beforeData = const [],
  List<List<int>> afterData = const [],
  int? splitIdatAt,
}) {
  final channels = switch (colorType) {
    0 || 3 => 1,
    2 => 3,
    4 => 2,
    _ => 4,
  };
  final rowBytes = (width * channels * bitDepth + 7) ~/ 8;
  final raw =
      rawScanlines ??
      [
        for (var y = 0; y < height; y++) ...[
          0,
          for (var x = 0; x < rowBytes; x++) (seed + y * 29 + x * 13) & 255,
        ],
      ];
  final encoded = compressed ?? const codecs.ZLibEncoder().encode(raw);
  final chunks = <List<int>>[
    pngCarvingSignature,
    pngCarvingChunk(
      'IHDR',
      pngCarvingHeader(
        width: width,
        height: height,
        colorType: colorType,
        bitDepth: bitDepth,
        interlace: interlace,
      ),
    ),
    ...beforeData,
    if (splitIdatAt != null) ...[
      pngCarvingChunk('IDAT', encoded.sublist(0, splitIdatAt)),
      pngCarvingChunk('IDAT', encoded.sublist(splitIdatAt)),
    ] else
      pngCarvingChunk('IDAT', encoded),
    ...afterData,
    pngCarvingChunk('IEND', []),
  ];
  return pngCarvingJoin(chunks);
}

Uint8List pngCarvingJoin(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final part in parts) {
    out.add(part);
  }
  return out.takeBytes();
}

/// Two valid images in unrelated source bytes; neither source nor output names
/// assert that original filesystem names or directories were recovered.
Uint8List pngCarvingWorkflowFixture() => pngCarvingJoin([
  List<int>.filled(17, 0x5a),
  pngCarvingPng(),
  List<int>.filled(23, 0xa5),
  pngCarvingPng(width: 1, height: 3, colorType: 6, seed: 29),
  [1, 2, 3, 4, 5],
]);
