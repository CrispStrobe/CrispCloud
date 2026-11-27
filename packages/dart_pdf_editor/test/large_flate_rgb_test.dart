import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dart_pdf_editor/src/large_flate_rgb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streams selected pixels at the requested display size', () {
    final source = List<int>.generate(8 * 4 * 3, (index) => index);
    final compressed = Uint8List.fromList(const ZLibEncoder().encode(source));

    final preview = decodeLargePdfRgb(compressed, 8, 4, maxSide: 2);

    expect((preview.width, preview.height), (2, 1));
    expect(preview.rgb, [54, 55, 56, 66, 67, 68]);
  });

  test('rejects mismatched sample counts and excessive source dimensions', () {
    final compressed = Uint8List.fromList(
      const ZLibEncoder().encode(List<int>.filled(24, 0)),
    );

    expect(() => decodeLargePdfRgb(compressed, 3, 3), throwsFormatException);
    expect(() => decodeLargePdfRgb(compressed, 2, 2), throwsFormatException);
    expect(
      () => decodeLargePdfRgb(compressed, 10000, 10000),
      throwsFormatException,
    );
  });
}
