// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'textbox_boundary_fixture.dart';

/// Independently declared source operands, not values read from parser output.
const textboxFillCases = <String, Map<int, int>>{
  'gradient-hundred': {
    0x0180: 7,
    0x0183: 0x003366cc,
    0x018c: 100,
    0x01bf: 0x00300030,
  },
  'gradient-axial': {
    0x0180: 7,
    0x0183: 0x003366cc,
    0x018b: -45 * 65536,
    0x018c: -50,
    0x01bf: 0x00300010,
  },
  'gradient-alpha': {
    0x0180: 7,
    0x0183: 0x003366cc,
    0x0182: 32768,
    0x0184: 16384,
  },
  'picture': {0x0180: 3, 0x4186: 1},
  'texture': {0x0180: 2, 0x4186: 1},
  'pattern': {0x0180: 1, 0x4186: 1, 0x0183: 0x003366cc},
  'unknown-gradient': {0x0180: 8, 0x0183: 0x003366cc},
  'unknown-bitmap': {0x0180: 1, 0x4186: 1},
};

Uint8List monochromePatternDib({bool reversePalette = false, int height = 8}) {
  final bytes = Uint8List(80), data = ByteData(80);
  data.setUint32(0, 40, Endian.little);
  data.setInt32(4, 8, Endian.little);
  data.setInt32(8, height, Endian.little);
  data.setUint16(12, 1, Endian.little);
  data.setUint16(14, 1, Endian.little);
  data.setUint32(20, 32, Endian.little);
  data.setInt32(24, 3780, Endian.little);
  data.setInt32(28, 3780, Endian.little);
  data.setUint32(32, 2, Endian.little);
  data.setUint32(40, reversePalette ? 0x00ffffff : 0, Endian.little);
  data.setUint32(44, reversePalette ? 0 : 0x00ffffff, Endian.little);
  bytes.setAll(0, data.buffer.asUint8List());
  for (var row = 0; row < 8; row++) {
    bytes[48 + row * 4] = row.isEven ? 0x77 : 0xdd;
  }
  return bytes;
}

Uint8List dibPatternBlip(
  Uint8List dib, {
  bool twoUids = false,
  int? instance,
}) => officeArtRecord(0xf01f, [
  ...List.filled(twoUids ? 32 : 16, 0),
  0xff,
  ...dib,
], instance: instance ?? (twoUids ? 0x7a9 : 0x7a8));

Uint8List textboxFillFixture(
  String name, {
  Map<int, int> extra = const {},
  Map<int, Uint8List> complex = const {},
  Uint8List? blip,
  int? blipType,
}) {
  final properties = textboxFillCases[name]!;
  final bitmap = const {1, 2, 3}.contains(properties[0x0180]);
  final pattern = name == 'pattern' || name == 'unknown-bitmap';
  final image =
      blip ??
      (pattern
          ? dibPatternBlip(
              monochromePatternDib(height: name == 'unknown-bitmap' ? 7 : 8),
            )
          : pictureBlip());
  final resolvedProperties = <int, int>{
    0x0181: 0x00cc9966,
    0x01cb: 25400,
    ...properties,
  };
  for (final entry in extra.entries) {
    resolvedProperties.removeWhere(
      (key, _) => (key & 0x3fff) == (entry.key & 0x3fff),
    );
    resolvedProperties[entry.key] = entry.value;
  }
  return textboxBoundaryFixture(
    ['FILL\r\r'],
    shapeProperties: resolvedProperties,
    shapeComplex: complex,
    globalBlips: bitmap ? [(blipType ?? (pattern ? 7 : 6), image)] : [],
  );
}
