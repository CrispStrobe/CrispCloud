// test/hex_viewer_test.dart
//
// Unit tests for the pure helpers used by the virtualized hex viewer and its
// status bar (row geometry must agree with the dialog's scroll math).

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/widgets/hex_viewer.dart';

void main() {
  test('hexRowExtent scales with the font scale', () {
    expect(hexRowExtent(1.0), closeTo(kHexBaseFontSize * 1.6 + 6, 1e-9));
    expect(hexRowExtent(2.0), closeTo(kHexBaseFontSize * 2 * 1.6 + 6, 1e-9));
  });

  test('hexRowCharCount covers offset, hex pairs and the ASCII column', () {
    expect(hexRowCharCount(16), 8 + 2 + (16 * 3 - 1) + 2 + 16);
    expect(hexRowCharCount(8, offsetDigits: 12), 12 + 2 + 23 + 2 + 8);
    expect(hexRowCharCount(32), 8 + 2 + 95 + 2 + 32);
  });

  test('byteStatusText shows offset, hex, decimal, binary and glyph', () {
    final text = byteStatusText(0x41, 0x10);
    expect(text, contains('0x00000010'));
    expect(text, contains('0x41'));
    expect(text, contains('65'));
    expect(text, contains('01000001'));
    expect(text, contains('"A"'));
  });

  test('byteStatusText hides non-printable glyphs', () {
    expect(byteStatusText(0x00, 0), contains('"·"'));
    expect(byteStatusText(0x1B, 0), contains('"·"'));
  });
}
