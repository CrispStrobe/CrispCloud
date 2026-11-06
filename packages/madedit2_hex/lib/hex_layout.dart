// Adapted from madedit/madedit2 lib/editor/hex_view.dart, revision 288d35747.
// Copyright (c) 2026 madedit. MIT license: ../LICENSE. Host-independent metrics.
import 'dart:typed_data';

const int hexBytesPerRow = 16;
int hexOffsetDigits(int length) {
  final digits = length.toRadixString(16).length;
  return digits < 8 ? 8 : digits;
}
int hexCharCol(int i, int digits) => digits + 2 + i * 3 + (i >= hexBytesPerRow ~/ 2 ? 1 : 0);
int asciiCharCol(int i, int digits) => digits + 2 + hexBytesPerRow * 3 + 1 + 2 + i;
int hexRowChars(int digits) => asciiCharCol(hexBytesPerRow, digits) + 1;
String hexNumber(int value, int digits) => value.toRadixString(16).toUpperCase().padLeft(digits, '0');
String asciiOf(int byte, {bool latin1 = false}) =>
    (byte >= 0x20 && byte < 0x7f) || (latin1 && byte >= 0xa0)
        ? String.fromCharCode(byte) : '.';
String hexRowLine(Uint8List bytes, int offset, int digits, {bool latin1 = false}) {
  final hex = StringBuffer(), ascii = StringBuffer();
  for (var i = 0; i < hexBytesPerRow; i++) {
    if (i == hexBytesPerRow ~/ 2) hex.write(' ');
    if (i < bytes.length) {
      hex.write('${hexNumber(bytes[i], 2)} ');
      ascii.write(asciiOf(bytes[i], latin1: latin1));
    } else { hex.write('   '); ascii.write(' '); }
  }
  return '${hexNumber(offset, digits)}  $hex |$ascii|';
}
int hexClampNibblePos(int position, int length, {bool allowEnd = false}) {
  if (length <= 0) return 0;
  final max = allowEnd ? length * 2 : length * 2 - 1;
  return position < 0 ? 0 : position > max ? max : position;
}
enum HexArea { hex, ascii }

/// Strict parser: malformed paste never silently drops characters or a nibble.
Uint8List parseHexBytes(String input) {
  final clean = input.trim().replaceAll(RegExp(r'0[xX](?=[0-9a-fA-F]{2})'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (clean.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(clean)) {
    throw const FormatException('Enter complete hexadecimal bytes, for example 48 65 6C 6C 6F.');
  }
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}
