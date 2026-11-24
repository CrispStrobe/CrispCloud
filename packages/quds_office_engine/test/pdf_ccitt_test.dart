import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/pdf_file.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_ccitt.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_filters.dart';
import 'package:test/test.dart';

// Original synthetic 37x8 bilevel pixels, independently encoded using
// Pillow 12.3.0 / libtiff 4.7.1 as WhiteIsZero single-strip TIFF images.
// Extracted strip payloads (Compression=3 or 4; T4Options=0, 1, 5).
const _rows = <String>[
  '0000011111000001111100000111110000011',
  '0000001111100000111110000011111000001',
  '0001111100000111110000011111000001111',
  '1111111111111111111111111111111111111',
  '0000000000000000000000000000000000000',
  '1010101010101010101010101010101010101',
  '0101010101010101010101010101010101010',
  '0011111111111111100000000000000000001',
];
const _g3 =
    'ABNTw8PDcAE1LDw8McAE1sPDw7ABFgATUNUAEdDodDodDodDodDodDodDodDodDocAE1Q6HQ6HQ6HQ6HQ6HQ6HQ6HQ6HQ6HQAJr6hnHA';
// Regenerated from the rows above using Pillow 13.0.0 / libtiff 4.7.2.
const _mixed =
    'ABmp4eHhuACtttuADNbDw8OwAQiIwAZqGqACZQ5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q5Q4IJQAZqh0Oh0Oh0Oh0Oh0Oh0Oh0Oh0Oh0OgAViIiIsRERERc';
const _filled =
    'AAGanh4eG4ABW223AAGa2Hh4dgABCIjAAZqGqAABMococococococococococococococococEEoAAGaodDodDodDodDodDodDodDodDodDoAAFYiIiLEREREXA=';
const _g4 =
    'JqZwzhnD2223ggQIECBAoiIyahqsococococococococococococococococEEqSSSSSSSSSSSSSSSSSS2IiIixERERFwAQAQA==';
const _long = 'ABAfKQNAXABNQHwbDeoAEB83WQATUB8DQCg=';

PdfCosDict _parms(int columns, int rows, int k, {
  bool eol = false,
  bool align = false,
  bool blackIs1 = false,
  bool endOfBlock = true,
}) => PdfCosDict(<String, PdfCos>{
  'Columns': PdfCosInt(columns),
  'Rows': PdfCosInt(rows),
  'K': PdfCosInt(k),
  'EndOfLine': PdfCosBool(eol),
  'EncodedByteAlign': PdfCosBool(align),
  'BlackIs1': PdfCosBool(blackIs1),
  'EndOfBlock': PdfCosBool(endOfBlock),
});

List<int> _pixels(List<String> rows) => [
  for (final row in rows)
    for (final bit in row.codeUnits) bit == 49 ? 255 : 0,
];

Uint8List _bits(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 8)
    int.parse(
      value.substring(i, i + 8 < value.length ? i + 8 : value.length)
          .padRight(8, '0'),
      radix: 2,
    ),
]);

void main() {
  test('libtiff Group 3, mixed mode with fill, and Group 4 match pixels', () {
    for (final (payload, k) in [
      (_g3, 0), (_mixed, 2), (_filled, 2), (_g4, -1),
    ]) {
      for (final invert in [false, true]) {
        final expected = _pixels(_rows);
        expect(
          PdfCcitt.decode(base64Decode(payload),
              _parms(37, 8, k, eol: k >= 0, blackIs1: invert)),
          invert ? expected.map((v) => 255 - v).toList() : expected,
          reason: 'K=$k, BlackIs1=$invert',
        );
      }
    }
  });

  test('long black and white runs include shared makeup codes', () {
    final pixels = PdfCcitt.decode(base64Decode(_long),
        _parms(3000, 4, 0, eol: true));
    expect(pixels, [
      ...List<int>.filled(2600, 255), ...List<int>.filled(400, 0),
      ...List<int>.filled(2600, 0), ...List<int>.filled(400, 255),
      ...List<int>.filled(3000, 255), ...List<int>.filled(3000, 0),
    ]);
  });

  test('mixed mode without EOL still consumes the 1D/2D tag', () {
    expect(PdfCcitt.decode(_bits('11001101'), _parms(8, 2, 2)),
        List<int>.filled(16, 255));
    expect(PdfCcitt.decode(_bits('11001100' '01'), _parms(8, 2, 2, align: true)),
        List<int>.filled(16, 255));
  });

  test('unknown row count honors RTC, EOFB, or explicit no-end-block', () {
    const eol = '000000000001';
    final rtc = List<String>.filled(6, eol).join();
    final mixedRtc = List<String>.filled(6, '${eol}1').join();
    for (final (data, k) in [
      (_bits('10011$rtc'), 0),
      (_bits('${eol}110011$mixedRtc'), 2),
      (_bits('1$eol$eol'), -1),
    ]) {
      expect(PdfCcitt.decode(data, _parms(8, 0, k)), List<int>.filled(8, 255));
    }
    expect(PdfCcitt.decode(_bits('10011'), _parms(8, 0, 0, endOfBlock: false)),
        List<int>.filled(8, 255));
  });

  test('short, overflowing, illegal mode and oversized rows are typed', () {
    for (final (data, parm) in [
      (_bits('00000000'), _parms(8, 1, 0)),
      (_bits('1111'), _parms(4, 1, 0)),
      (_bits('10011'), _parms(8, 2, 0)),
      (_bits('01'), _parms(8, 1, 2)), // First mixed row must be 1D.
      (_bits('0000001'), _parms(8, 1, -1)), // Unsupported extension.
      (_bits('10011'), _parms(8192, 8192, 0)),
      (_bits('10011'), _parms(8, 0, 0)), // Missing RTC.
      (_bits('10011'), _parms(8, 1, 0, eol: true)),
    ]) {
      expect(() => PdfCcitt.decode(data, parm),
          throwsA(isA<PdfFilterUnsupported>()));
    }
  });

  test('filter uses image height when Rows is absent and rejects mismatch', () {
    final parms = _parms(37, 0, 2, eol: true);
    final dict = PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('CCITTFaxDecode'),
      'Width': const PdfCosInt(37),
      'Height': const PdfCosInt(8),
      'DecodeParms': parms,
    });
    expect(PdfFilters.decode(base64Decode(_mixed), dict), _pixels(_rows));
    dict['Width'] = const PdfCosInt(36);
    expect(PdfFilters.decodeResult(base64Decode(_mixed), dict).unsupported,
        'CCITTFaxDecode');
  });
}
