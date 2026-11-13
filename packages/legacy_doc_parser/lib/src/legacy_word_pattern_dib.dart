// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

/// Adds only a BITMAPFILEHEADER to the bounded monochrome OfficeArt pattern.
/// The original BITMAPINFOHEADER, palette and scanlines remain byte-exact.
/// Other DIB dimensions, compression modes and header variants remain inert.
Uint8List? wrapOfficeArtPatternDib(Uint8List dib) {
  if (dib.length != 80) return null;
  final input = ByteData.sublistView(dib);
  if (input.getUint32(0, Endian.little) != 40 ||
      input.getInt32(4, Endian.little) != 8 ||
      input.getInt32(8, Endian.little).abs() != 8 ||
      input.getUint16(12, Endian.little) != 1 ||
      input.getUint16(14, Endian.little) != 1 ||
      input.getUint32(16, Endian.little) != 0 ||
      !const {0, 32}.contains(input.getUint32(20, Endian.little)) ||
      !const {0, 2}.contains(input.getUint32(32, Endian.little)) ||
      input.getUint32(36, Endian.little) > 2) {
    return null;
  }
  final first = input.getUint32(40, Endian.little);
  final second = input.getUint32(44, Endian.little);
  if (!((first == 0 && second == 0x00ffffff) ||
      (first == 0x00ffffff && second == 0))) {
    return null;
  }
  final bitmap = Uint8List(14 + dib.length);
  final output = ByteData.sublistView(bitmap);
  output.setUint16(0, 0x4d42, Endian.little);
  output.setUint32(2, bitmap.length, Endian.little);
  output.setUint32(10, 14 + 40 + 8, Endian.little);
  bitmap.setRange(14, bitmap.length, dib);
  return bitmap.asUnmodifiableView();
}
