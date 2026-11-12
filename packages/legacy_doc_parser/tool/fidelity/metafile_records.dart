// SPDX-License-Identifier: MPL-2.0

// Independent native-renderer inputs. This file deliberately does not import
// the parser, converter, their binary fixtures, or their geometry model.
// Record layouts: MS-EMF 2.3 and MS-WMF 2.3. All graphics are authored here;
// there is no text/font, escape, URL, or imported third-party artwork.
import 'dart:typed_data';

List<int> _u16(int value) => [value & 255, (value >> 8) & 255];
List<int> _u32(int value) => [
  value & 255,
  (value >> 8) & 255,
  (value >> 16) & 255,
  (value >> 24) & 255,
];

Uint8List _emr(int type, List<int> fields) => Uint8List.fromList([
  ..._u32(type),
  ..._u32(8 + fields.length * 4),
  for (final field in fields) ..._u32(field),
]);

/// A five-shape control: rectangle, ellipse, two-segment cubic, affine triangle,
/// and a rectangle with signed anisotropic window/viewport mapping.
Uint8List authoredEmfVectors() {
  final matrix = ByteData(24);
  for (final (i, value) in [1.0, 0.2, 0.2, 1.0, 50.0, 245.0].indexed) {
    matrix.setFloat32(i * 4, value, Endian.little);
  }
  final records = <Uint8List>[
    _emr(38, [1, 0, 3, 0, 0x00552211]), // Solid 3-unit pen, RGB 112255.
    _emr(39, [2, 0, 0x00ddcc99, 0]), // Solid RGB 99CCDD brush.
    _emr(37, [1]),
    _emr(37, [2]),
    _emr(43, [30, 30, 260, 135]),
    _emr(42, [320, 30, 570, 135]),
    _emr(2, [
      25,
      130,
      575,
      310,
      7,
      30,
      220,
      130,
      130,
      170,
      310,
      300,
      220,
      410,
      130,
      450,
      310,
      570,
      220,
    ]),
    _emr(33, []), // SaveDC isolates the following world transform.
    Uint8List.fromList([
      ..._u32(35),
      ..._u32(32),
      ...matrix.buffer.asUint8List(),
    ]),
    _emr(3, [0, 0, 160, 60, 3, 0, 0, 160, 0, 80, 60]),
    _emr(34, [-1]),
    _emr(33, []),
    _emr(17, [8]), // MM_ANISOTROPIC.
    _emr(10, [-50, -40]),
    _emr(9, [150, 100]),
    _emr(12, [370, 350]),
    _emr(11, [180, -80]),
    _emr(43, [-50, -40, 90, 50]),
    _emr(34, [-1]),
    _emr(14, [0, 16, 20]),
  ];
  final header = ByteData(88);
  void u32(int offset, int value) =>
      header.setUint32(offset, value, Endian.little);
  u32(0, 1);
  u32(4, 88);
  u32(16, 600);
  u32(20, 360);
  u32(32, 15875); // 600 pixels at 96 dpi, in 0.01 millimeters.
  u32(36, 9525);
  u32(40, 0x464d4520);
  u32(44, 0x10000);
  u32(48, 88 + records.fold<int>(0, (sum, record) => sum + record.length));
  u32(52, records.length + 1);
  header.setUint16(56, 3, Endian.little);
  u32(72, 960);
  u32(76, 960);
  u32(80, 254);
  u32(84, 254);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    for (final record in records) ...record,
  ]);
}

Uint8List _wmr(int type, List<int> words) => Uint8List.fromList([
  ..._u32(words.length + 3),
  ..._u16(type),
  for (final word in words) ..._u16(word),
]);

/// A placeable WMF control with solid rectangle/ellipse/polygon/line and signed
/// window mapping. Multiword COLORREF values are written explicitly low-first.
Uint8List authoredWmfVectors() {
  final records = <Uint8List>[
    // MS-WMF 3.1.1: establish mapping/window before painting; leave the
    // viewport to the player so the metafile remains independently sizable.
    _wmr(0x0103, [8]),
    _wmr(0x020b, [0, 0]),
    _wmr(0x020c, [360, 600]),
    _wmr(0x02fa, [0, 3, 0, 0x2211, 0x0055]),
    _wmr(0x02fc, [0, 0xcc99, 0x00dd, 0]),
    _wmr(0x012d, [0]),
    _wmr(0x012d, [1]),
    _wmr(0x041b, [135, 260, 30, 30]),
    _wmr(0x0418, [135, 570, 30, 320]),
    _wmr(0x0324, [4, 30, 190, 110, 165, 215, 250, 75, 270]),
    _wmr(0x0214, [190, 320]),
    _wmr(0x0213, [250, 570]),
    _wmr(0x001e, []),
    _wmr(0x020b, [-40, -50]),
    _wmr(0x041b, [290, 510, 230, 320]),
    _wmr(0x0127, [-1]),
    _wmr(0, []),
  ];
  final size = 18 + records.fold<int>(0, (sum, record) => sum + record.length);
  final maximum = records.fold<int>(
    0,
    (n, record) => n > record.length ? n : record.length,
  );
  final header = [
    ..._u16(1),
    ..._u16(9),
    ..._u16(0x300),
    ..._u32(size ~/ 2),
    ..._u16(2),
    ..._u32(maximum ~/ 2),
    ..._u16(0),
  ];
  final placeable = ByteData(22);
  placeable.setUint32(0, 0x9ac6cdd7, Endian.little);
  placeable.setInt16(10, 600, Endian.little);
  placeable.setInt16(12, 360, Endian.little);
  placeable.setUint16(14, 96, Endian.little);
  var checksum = 0;
  for (var offset = 0; offset < 20; offset += 2) {
    checksum ^= placeable.getUint16(offset, Endian.little);
  }
  placeable.setUint16(20, checksum, Endian.little);
  return Uint8List.fromList([
    ...placeable.buffer.asUint8List(),
    ...header,
    for (final record in records) ...record,
  ]);
}
