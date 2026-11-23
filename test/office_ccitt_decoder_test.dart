import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/pdf_file.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_ccitt.dart';

Uint8List _encoded(String bits) {
  final padded = bits.padRight((bits.length + 7) ~/ 8 * 8, '0');
  return Uint8List.fromList([
    for (var i = 0; i < padded.length; i += 8)
      int.parse(padded.substring(i, i + 8), radix: 2),
  ]);
}

void main() {
  test('Group 3 decodes a wide white run followed by a black run', () {
    final pixels = PdfCcitt.decode(
      _encoded(
        '000000011111' // 2560 white, make-up
        '0010011' // 26 white, terminating
        '000001010010', // 50 black, terminating
      ),
      PdfCosDict({
        'Columns': const PdfCosInt(2636),
        'Rows': const PdfCosInt(1),
      }),
    );
    expect(pixels, [...List.filled(2586, 255), ...List.filled(50, 0)]);
  });

  test('Group 3 keeps initial black pixels and byte-aligned rows', () {
    final pixels = PdfCcitt.decode(
      _encoded(
        '0000000000000001' // EOL with four fill bits
        '00110101' // Zero white pixels
        '000101' // Eight black pixels
        '00' // Byte alignment
        '000000000001' // EOL
        '10011', // Eight white pixels
      ),
      PdfCosDict({
        'Columns': const PdfCosInt(8),
        'Rows': const PdfCosInt(2),
        'EncodedByteAlign': const PdfCosBool(true),
      }),
    );
    expect(pixels, [...List.filled(8, 0), ...List.filled(8, 255)]);
  });

  test('Group 3 pads a short row with white at the end-of-line marker', () {
    final pixels = PdfCcitt.decode(
      _encoded(
        '00110101' // Zero white pixels
        '000101' // Eight black pixels
        '000000000001' // EOL before the declared row width
        '10011' // Eight white pixels on the next row
        '11', // Two black pixels
      ),
      PdfCosDict({'Columns': const PdfCosInt(10), 'Rows': const PdfCosInt(2)}),
    );
    expect(pixels, [
      ...List.filled(8, 0),
      ...List.filled(10, 255),
      ...List.filled(2, 0),
    ]);
  });
}
