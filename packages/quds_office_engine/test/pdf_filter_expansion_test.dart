import 'dart:convert';
import 'dart:typed_data';

import 'package:jbig2/jbig2.dart' as jb;
import 'package:quds_office_engine/pdf_file.dart';
import 'package:quds_office_engine/src/pdf/file/decode/pdf_filters.dart';
import 'package:quds_office_engine/src/pdf/pdf_stream.dart';
import 'package:test/test.dart';

// Independent lossless OpenJPEG 2.5.4 fixtures, generated with Pillow from
// synthetic pixels. No third-party PDF or restricted ITU test data is copied.
const _rgbJp2 =
    'AAAADGpQICANCocKAAAAFGZ0eXBqcDIgAAAAAGpwMiAAAAAtanAyaAAAABZpaGRyAAAAAgAAAAIAAwcHAAAAAAAPY29scgEAAAAAABAAAACZanAyY/9P/1EALwAAAAAAAgAAAAIAAAAAAAAAAAAAAAIAAAACAAAAAAAAAAAAAwcBAQcBAQcBAf9SAAwAAAABAAEEBAAB/1wAB0BASEhQ/2QAJQABQ3JlYXRlZCBieSBPcGVuSlBFRyB2ZXJzaW9uIDIuNS40/5AACgAAAAAAHgAB/5OAgICT8wIA38/ABACn4AIA/9k=';
const _rgbJ2k =
    '/0//UQAvAAAAAAACAAAAAgAAAAAAAAAAAAAAAgAAAAIAAAAAAAAAAAADBwEBBwEBBwEB/1IADAAAAAEAAQQEAAH/XAAHQEBISFD/ZAAlAAFDcmVhdGVkIGJ5IE9wZW5KUEVHIHZlcnNpb24gMi41LjT/kAAKAAAAAAAeAAH/k4CAgJPzAgDfz8AEAKfgAgD/2Q==';
const _grayJp2 =
    'AAAADGpQICANCocKAAAAFGZ0eXBqcDIgAAAAAGpwMiAAAAAtanAyaAAAABZpaGRyAAAAAgAAAAMAAQcHAAAAAAAPY29scgEAAAAAABEAAACZanAyY/9P/1EAKQAAAAAAAwAAAAIAAAAAAAAAAAAAAAMAAAACAAAAAAAAAAAAAQcBAf9SAAwAAAABAAEEBAAB/1wAB0BASEhQ/2QAJQABQ3JlYXRlZCBieSBPcGVuSlBFRyB2ZXJzaW9uIDIuNS40/5AACgAAAAAAJAAB/5PD5wYMIX/H2gV+YHH4AQAEFwRjDwQ//9k=';
const _rgbaJp2 =
    'AAAADGpQICANCocKAAAAFGZ0eXBqcDIgAAAAAGpwMiAAAABPanAyaAAAABZpaGRyAAAAAgAAAAIABAcHAAAAAAAPY29scgEAAAAAABAAAAAiY2RlZgAEAAAAAAABAAEAAAACAAIAAAADAAMAAQAAAAAArmpwMmP/T/9RADIAAAAAAAIAAAACAAAAAAAAAAAAAAACAAAAAgAAAAAAAAAAAAQHAQEHAQEHAQEHAQH/UgAMAAAAAQABBAQAAf9cAAdAQEhIUP9kACUAAUNyZWF0ZWQgYnkgT3BlbkpQRUcgdmVyc2lvbiAyLjUuNP+QAAoAAAAAADAAAf+TgICAw+cCB5PzAgDfz8AEAKfgAgDH2gU/ACg+oBACfwLXAP/Z';

const _rgb = <int>[255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255];

PdfCosDict _jpx(int width, int height, {int alpha = 0}) =>
    PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('JPXDecode'),
      'Width': PdfCosInt(width),
      'Height': PdfCosInt(height),
      'SMaskInData': PdfCosInt(alpha),
    });

Uint8List _hex(Uint8List data) => Uint8List.fromList(ascii.encode(
  '${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>',
));

PdfCosDict _predictor(int columns, int colors, int bits, {int predictor = 2}) =>
    PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('FlateDecode'),
      'DecodeParms': PdfCosDict(<String, PdfCos>{
        'Predictor': PdfCosInt(predictor),
        'Columns': PdfCosInt(columns),
        'Colors': PdfCosInt(colors),
        'BitsPerComponent': PdfCosInt(bits),
      }),
    });

// Independent synthetic JPEGs from Pillow/libjpeg, quality 95, 4:4:4.
const _grayJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/wAALCAAIAAgBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AP9//2Q==';
const _rgbJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wAARCAAIAAgDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAAB//EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAAAAAFCf/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AA8Wqw//2Q==';
const _progressiveJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/2wBDAQICAgICAgUDAwUKBwYHCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgr/wgARCAAIAAgDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAABP/EABUBAQEAAAAAAAAAAAAAAAAAAAYI/9oADAMBAAIQAxAAAAEZubf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAn//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/AX//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/AX//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/An//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IX//2gAMAwEAAgADAAAAEB//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==';
const _rawRgbJpeg =
    '/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwACAQEBAQECAQEBAgICAgIEAwICAgIFBAQDBAYFBgYGBQYGBgcJCAYHCQcGBggLCAkKCgoKCgYICwwLCgwJCgoK/8AAEQgACAAIA1IRAEcRAEIRAP/EABUAAQEAAAAAAAAAAAAAAAAAAAkI/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAwDUgBHAEIAAD8AXAT6Z3//2Q==';
const _orientedJpeg =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAIBAQEBAQIBAQECAgICAgQDAgICAgUEBAMEBgUGBgYFBgYGBwkIBgcJBwYGCAsICQoKCgoKBggLDAsKDAkKCgr/wAALCAAIABABAREA/8QAFQABAQAAAAAAAAAAAAAAAAAACQr/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAA/AB/WAP/Z';
const _cmykJpeg =
    '/9j/7gAOQWRvYmUAZAAAAAAA/9sAQwACAQEBAQECAQEBAgICAgIEAwICAgIFBAQDBAYFBgYGBQYGBgcJCAYHCQcGBggLCAkKCgoKCgYICwwLCgwJCgoK/8AAFAgACAAIBEMRAE0RAFkRAEsRAP/EABUAAQEAAAAAAAAAAAAAAAAAAAkI/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAA4EQwBNAFkASwAAPwBhCGKUNY//2Q==';
// Pillow 13.0.0/libjpeg-turbo 3.2.0, quality 95, 4:4:4. Encode inverted
// (Y, Cb, Cr, K) tuples (102,173,88,208) and (198,55,199,70) in 8x8 blocks,
// then set the Adobe transform byte to 2. The same independent decoder
// reports CMYK inks (46,115,182,47) and (255,172,69,185).
const _ycckJpeg =
    '/9j/7gAOQWRvYmUAZAAAAAAC/9sAQwACAQEBAQECAQEBAgICAgIEAwICAgIFBAQDBAYFBgYGBQYGBgcJCAYHCQcGBggLCAkKCgoKCgYICwwLCgwJCgoK'
    '/8AAFAgACAAQBEMRAE0RAFkRAEsRAP/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBh'
    'NRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SV'
    'lpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/aAA4EQwBNAFkASwAAPwDxevrSvl+v1Ar9gK'
    '/Cev28r+dev//Z';

final _invertCmyk = PdfCosArray([
  for (var channel = 0; channel < 4; channel++) ...[
    const PdfCosInt(1),
    const PdfCosInt(0),
  ],
]);

PdfCosDict _dct(String cs, {int width = 8, int height = 8}) =>
    PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('DCTDecode'),
      'Width': PdfCosInt(width),
      'Height': PdfCosInt(height),
      'BitsPerComponent': const PdfCosInt(8),
      'ColorSpace': PdfCosName(cs),
    });

void _expectSolid(Uint8List? pixels, List<int> rgb) {
  expect(pixels, isNotNull);
  final samples = pixels!;
  expect(samples.length, 8 * 8 * 3);
  for (var i = 0; i < samples.length; i++) {
    expect(samples[i], closeTo(rgb[i % 3], 3));
  }
}

void main() {
  test('inline image framing preserves delimiter-like binary payload bytes', () {
    const samples = [32, 69, 73, 32, 128, 37];
    for (final (filter, payload) in [
      ('', samples),
      ('/F /RL', [5, ...samples, 128]),
      ('/F [/AHx /RL]', ascii.encode('0520454920802580>')),
      // Python zlib level 0 keeps the literal " EI " inside the stored block.
      ('/F /Fl', base64Decode('eAEBBgD5/yBFSSCAJQTIAXQ=')),
      ('/F [/Fl /RL]', base64Decode('eJxjVXD1VGhQbQAABuUB+Q==')),
    ]) {
      final list = _inlineDisplayList(
        '/W 2 /H 1 /CS /RGB /BPC 8 $filter',
        payload,
      );
      expect(list.issues, isEmpty, reason: filter);
      expect(list.ops.whereType<PdfDrawImage>().single.bytes, samples);
      expect(list.ops.whereType<PdfFillPath>(), hasLength(2));
    }
  });

  test('inline Flate applies PNG predictor and verifies its zlib checksum', () {
    final encoded = base64Decode('eJxj5JGQ42HjAgABgABg');
    const parms = '/W 2 /H 1 /CS /RGB /F /Fl '
        '/DP << /Predictor 15 /Colors 3 /Columns 2 /BitsPerComponent 8 >>';
    final list = _inlineDisplayList(parms, encoded);
    expect(list.issues, isEmpty);
    expect(list.ops.whereType<PdfDrawImage>().single.bytes,
        [12, 24, 30, 24, 30, 40]);

    encoded[encoded.length - 1] ^= 1;
    final corrupt = _inlineDisplayList(parms, encoded);
    expect(corrupt.issues, {PdfPageRenderIssue.inlineImage});
    expect(corrupt.ops.whereType<PdfDrawImage>(), isEmpty);
    expect(corrupt.ops.whereType<PdfFillPath>(), hasLength(1));
  });

  test('inline JPEG framing skips false end markers inside metadata', () {
    final rgb = base64Decode(_rgbJpeg);
    final withComment = <int>[
      ...rgb.take(2),
      0xff, 0xfe, 0, 8,
      32, 69, 73, 32, 0xff, 0xd9,
      ...rgb.skip(2),
    ];
    const parameters = '/W 8 /H 8 /CS /RGB /BPC 8 /F /DCT';
    final page = _inlineDisplayList(parameters, withComment);
    expect(page.issues, isEmpty);
    final image = page.ops.whereType<PdfDrawImage>().single;
    expect(image.jpeg, isFalse);
    _expectSolid(image.bytes, [221, 40, 91]);
    expect(page.ops.whereType<PdfFillPath>(), hasLength(2));

    final truncated = _inlineDisplayList(
      parameters,
      withComment.sublist(0, withComment.length - 2),
    );
    expect(truncated.issues, {PdfPageRenderIssue.inlineImage});
    expect(truncated.ops.whereType<PdfDrawImage>(), isEmpty);
    expect(truncated.ops.whereType<PdfFillPath>(), hasLength(1));
  });

  test('ASCII85 inline images reuse the device gray raster path', () {
    final list = _inlineDisplayList('/W 4 /H 1 /CS /G /F /A85', [
      ...ascii.encode('z~>'),
    ]);
    expect(list.issues, isEmpty);
    final image = list.ops.whereType<PdfDrawImage>().single;
    expect(image.pixelWidth, 4);
    expect(image.bytes, List<int>.filled(12, 0));
  });

  test('one-pixel inline rows keep their packed sample depth', () {
    final list = _inlineDisplayList('/W 1 /H 2 /CS /G /BPC 1', [0x80, 0]);
    expect(list.issues, isEmpty);
    expect(list.ops.whereType<PdfDrawImage>().single.bytes,
        [255, 255, 255, 0, 0, 0]);
    final packed = _inlineDisplayList('/W 4 /H 1 /CS /G /BPC 2', [0x1B]);
    expect(packed.issues, isEmpty);
    expect(packed.ops.whereType<PdfDrawImage>().single.bytes,
        [0, 0, 0, 85, 85, 85, 170, 170, 170, 255, 255, 255]);
  });

  test('unreadable inline images preserve already painted content', () {
    final list = _inlineDisplayList(
      '/W 4 /H 1 /CS /G /F /RL',
      [127, 0],
    );
    expect(list.issues, {PdfPageRenderIssue.inlineImage});
    expect(list.ops.whereType<PdfDrawImage>(), isEmpty);
    expect(list.ops.whereType<PdfFillPath>(), hasLength(1));
    expect(list.ops.whereType<PdfRestoreGState>(), hasLength(1));
  });

  test('PDF filters distinguish stream limits from invalid filters', () {
    final dict = PdfCosDict({'Filter': const PdfCosName('RunLengthDecode')});
    final encoded = Uint8List.fromList([253, 65, 128]);
    expect(PdfFilters.decodeResult(encoded, dict, maxOutputBytes: 4).bytes,
        [65, 65, 65, 65]);
    final limited = PdfFilters.decodeResult(encoded, dict, maxOutputBytes: 3);
    expect(limited.bytes, isNull);
    expect(limited.unsupported, 'RunLengthDecode');
    expect(limited.limitExceeded, isTrue);

    dict['Filter'] = const PdfCosName('NoSuchFilter');
    expect(PdfFilters.decodeResult(encoded, dict).limitExceeded, isFalse);
  });

  test('engine DCT baseline gray/RGB and progressive independent pixels', () {
    for (final (encoded, cs, expected) in [
      (_grayJpeg, 'DeviceGray', [64, 64, 64]),
      (_rgbJpeg, 'DeviceRGB', [221, 40, 91]),
      (_progressiveJpeg, 'DeviceRGB', [20, 180, 90]),
    ]) {
      final result = PdfFilters.decodeResult(
        base64Decode(encoded), _dct(cs), decodeDct: true,
      );
      expect(result.unsupported, isNull);
      expect(result.jpegEncoded, isFalse);
      expect(result.dctImage?.isGray, cs == 'DeviceGray');
      _expectSolid(result.bytes, expected);
    }
  });

  test('DCT ColorTransform zero, Adobe override and PDF Decode array', () {
    final original = base64Decode(_rawRgbJpeg);
    final withoutAdobe = Uint8List.fromList([
      ...original.sublist(0, 2), ...original.sublist(18),
    ]);
    final dict = _dct('DeviceRGB')
      ..['DecodeParms'] = PdfCosDict({'ColorTransform': const PdfCosInt(0)})
      ..['Decode'] = PdfCosArray([
        const PdfCosInt(1), const PdfCosInt(0),
        const PdfCosInt(0), const PdfCosInt(1),
        const PdfCosInt(0), const PdfCosReal(0.5),
      ]);
    _expectSolid(PdfFilters.decodeResult(
      withoutAdobe, dict, decodeDct: true,
    ).bytes, [35, 40, 45]);
    dict['DecodeParms'] = PdfCosDict({'ColorTransform': const PdfCosInt(1)});
    _expectSolid(PdfFilters.decodeResult(
      original, dict, decodeDct: true,
    ).bytes, [35, 40, 45]);
  });

  test('DCT ignores standalone EXIF orientation', () {
    final result = PdfFilters.decodeResult(
      base64Decode(_orientedJpeg),
      _dct('DeviceGray', width: 16, height: 8),
      decodeDct: true,
    );
    expect(result.unsupported, isNull);
    final pixels = result.bytes!;
    expect(pixels.length, 16 * 8 * 3);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 16; x++) {
        expect(pixels[(y * 16 + x) * 3], closeTo(x < 8 ? 32 : 224, 3));
      }
    }
  });

  test('DCT XObject, filter chain, indirect parms and JPEG soft mask', () {
    final pdf = PdfFile.open(_imagePdf(
      _hex(base64Decode(_rgbJpeg)),
      '/Width 8 /Height 8 /ColorSpace /DeviceRGB /BitsPerComponent 8 '
      '/Filter [/ASCIIHexDecode /DCT] /DecodeParms [null 6 0 R] /SMask 7 0 R',
      extras: [
        ascii.encode('<< /ColorTransform 1 >>'),
        _stream(base64Decode(_grayJpeg),
          '/Type /XObject /Subtype /Image /Width 8 /Height 8 '
          '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode '
          '/Decode [1 0]'),
      ],
    ));
    final op = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
    expect(op.placeholder, isFalse);
    expect(op.jpeg, isFalse);
    expect(op.hasAlpha, isTrue);
    expect(op.softMaskJpeg, isNull);
    expect(op.bytes.length, 8 * 8 * 4);
    for (var i = 0; i < op.bytes.length; i += 4) {
      expect(op.bytes[i], closeTo(221, 3));
      expect(op.bytes[i + 1], closeTo(40, 3));
      expect(op.bytes[i + 2], closeTo(91, 3));
      expect(op.bytes[i + 3], closeTo(191, 3));
    }
  });

  test('malformed, oversized and mismatched JPEGs are typed unsupported', () {
    final valid = base64Decode(_grayJpeg);
    final huge = Uint8List.fromList(valid);
    for (var i = 0; i < huge.length - 8; i++) {
      if (huge[i] == 0xff && huge[i + 1] == 0xc0) {
        huge[i + 5] = huge[i + 6] = 0xff;
        break;
      }
    }
    for (final bytes in [
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      valid.sublist(0, valid.length - 2),
      huge,
    ]) {
      expect(PdfFilters.decodeResult(bytes, _dct('DeviceGray'),
        decodeDct: true).unsupported, 'DCTDecode');
    }
    expect(PdfFilters.decodeResult(valid, _dct('DeviceGray', width: 7),
      decodeDct: true).unsupported, 'DCTDecode');
    expect(PdfFilters.decodeResult(valid, _dct('DeviceRGB'),
      decodeDct: true).unsupported, 'DCTDecode');
    final pdf = PdfFile.open(_imagePdf(valid.sublist(0, valid.length - 2),
      '/Width 8 /Height 8 /ColorSpace /DeviceGray /Filter /DCTDecode'));
    expect(pdf.displayList(0).ops.whereType<PdfDrawImage>().single.placeholder,
      isTrue);
  });

  test('DCT CMYK applies PDF Decode to the original four samples', () {
    // libjpeg decodes this Adobe CMYK fixture to inks (30, 60, 90, 20).
    // The actual codestream samples are (225, 195, 165, 235).
    final raw = base64Decode(_cmykJpeg);
    final dict = _dct('DeviceCMYK');
    final markerless = Uint8List.fromList([
      ...raw.sublist(0, 2),
      ...raw.sublist(18),
    ]);
    for (final input in [raw, markerless]) {
      final identity = PdfFilters.decodeResult(input, dict, decodeDct: true);
      expect(identity.unsupported, isNull);
      _expectSolid(identity.bytes, [2, 5, 7]);
    }

    dict['Decode'] = _invertCmyk;
    dict['DecodeParms'] =
        PdfCosDict({'ColorTransform': const PdfCosInt(1)});
    final inverted = PdfFilters.decodeResult(raw, dict, decodeDct: true);
    expect(inverted.unsupported, isNull);
    expect(inverted.jpegEncoded, isFalse);
    expect(inverted.dctImage?.isGray, isFalse);
    _expectSolid(inverted.bytes, [207, 180, 152]);

    final invalidAdobe = Uint8List.fromList(raw)..[17] = 1;
    final unsupported = PdfFilters.decodeResult(invalidAdobe, dict,
        decodeDct: true);
    expect(unsupported.unsupported, 'DCTDecode');
  });

  test('DCT YCCK reconstructs CMYK before applying PDF Decode', () {
    final adobe = base64Decode(_ycckJpeg);
    final markerless = Uint8List.fromList([
      ...adobe.sublist(0, 2),
      ...adobe.sublist(18),
    ]);
    for (final (raw, transform) in [(adobe, 0), (markerless, 1)]) {
      final dict = _dct('DeviceCMYK', width: 16)
        ..['Decode'] = _invertCmyk
        ..['DecodeParms'] = PdfCosDict({'ColorTransform': PdfCosInt(transform)});
      final result = PdfFilters.decodeResult(raw, dict, decodeDct: true);
      expect(result.unsupported, isNull);
      expect(result.jpegEncoded, isFalse);
      final pixels = result.bytes!;
      expect(pixels.length, 16 * 8 * 3);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 16; x++) {
          final expected = x < 8 ? [170, 114, 60] : [0, 23, 51];
          final offset = (y * 16 + x) * 3;
          for (var i = 0; i < 3; i++) {
            expect(pixels[offset + i], closeTo(expected[i], 2));
          }
        }
      }
    }
  });

  test('DCT CMYK XObject composes a JPEG soft mask in the display list', () {
    final pdf = PdfFile.open(_imagePdf(
      base64Decode(_cmykJpeg),
      '/Width 8 /Height 8 /ColorSpace /DeviceCMYK /Filter /DCTDecode '
      '/Decode [1 0 1 0 1 0 1 0] /SMask 6 0 R',
      extras: [
        _stream(base64Decode(_grayJpeg),
            '/Type /XObject /Subtype /Image /Width 8 /Height 8 '
            '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode'),
      ],
    ));
    final op = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
    expect(op.placeholder, isFalse);
    expect(op.jpeg, isFalse);
    expect(op.hasAlpha, isTrue);
    expect(op.bytes.length, 8 * 8 * 4);
    const rgba = [207, 180, 152, 64];
    for (var i = 0; i < op.bytes.length; i++) {
      expect(op.bytes[i], closeTo(rgba[i % 4], 3));
    }
  });

  test('four-component JPEG retains the encoded API and ICC host path', () {
    final raw = base64Decode(_cmykJpeg);
    final icc = _dct('DeviceCMYK')
      ..['ColorSpace'] = PdfCosArray([
        const PdfCosName('ICCBased'),
        const PdfCosRef(6, 0),
      ]);
    for (final result in [
      PdfFilters.decodeResult(raw, _dct('DeviceCMYK')),
      PdfFilters.decodeResult(raw, icc, decodeDct: true),
    ]) {
      expect(result.unsupported, isNull);
      expect(result.jpegEncoded, isTrue);
      expect(result.bytes, raw);
      expect(result.dctImage, isNull);
    }
  });


  test('JP2 and raw J2K reconstruct independent RGB reference', () {
    for (final fixture in [_rgbJp2, _rgbJ2k]) {
      final decoded = PdfFilters.decodeResult(
        base64Decode(fixture), _jpx(2, 2),
      );
      expect(decoded.unsupported, isNull);
      expect(decoded.bytes, _rgb);
      expect(decoded.jpxImage?.hasAlpha, isFalse);
    }
  });

  test('gray JPX with omitted ColorSpace uses codestream channels', () {
    final decoded = PdfFilters.decodeResult(base64Decode(_grayJp2), _jpx(3, 2));
    expect(decoded.jpxImage?.isGray, isTrue);
    expect(decoded.bytes, [
      for (final tone in [0, 64, 128, 192, 255, 17]) ...[tone, tone, tone],
    ]);
  });

  test('JPX honors SMaskInData and omits unused alpha', () {
    final data = base64Decode(_rgbaJp2);
    final decoded = PdfFilters.decodeResult(data, _jpx(2, 2, alpha: 1));
    expect(decoded.jpxImage?.hasAlpha, isTrue);
    expect(decoded.bytes, [255, 0, 0, 0, 0, 255, 0, 64,
      0, 0, 255, 128, 255, 255, 255, 255]);
    expect(PdfFilters.decode(data, _jpx(2, 2)), _rgb);
  });

  test('ASCIIHex then JPX preserves terminal image metadata', () {
    final dict = _jpx(2, 2)
      ..['Filter'] = PdfCosArray(<PdfCos>[
        const PdfCosName('ASCIIHexDecode'), const PdfCosName('JPXDecode'),
      ])
      ..['DecodeParms'] = PdfCosArray(<PdfCos>[
        const PdfCosNull(), PdfCosDict(),
      ]);
    final decoded = PdfFilters.decodeResult(_hex(base64Decode(_rgbJp2)), dict);
    expect(decoded.bytes, _rgb);
    expect(decoded.jpxImage, isNotNull);
  });

  test('bad JPX and mismatched dimensions remain typed unsupported', () {
    expect(PdfFilters.decodeResult(Uint8List(3), _jpx(2, 2)).unsupported,
        'JPXDecode');
    expect(PdfFilters.decodeResult(base64Decode(_rgbJp2), _jpx(1, 2)).unsupported,
        'JPXDecode');
  });

  test('JPX XObject reaches the display list without a JPEG host codec', () {
    final pdf = PdfFile.open(_imagePdf(
      base64Decode(_rgbJp2), '/Width 2 /Height 2 /Filter /JPXDecode',
    ));
    final image = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
    expect(image.placeholder, isFalse);
    expect(image.jpeg, isFalse);
    expect(image.pixelWidth, 2);
    expect(image.pixelHeight, 2);
    expect(image.bytes, _rgb);
  });

  test('JBIG2 generic region and symbol dictionary preserve polarity', () {
    final packed = Uint8List.fromList([0x81, 0x42, 0x24, 0x18,
      0x81, 0x42, 0x24, 0x18]);
    final expected = [
      for (final row in packed)
        for (int x = 7; x >= 0; x--) (row & (1 << x)) != 0 ? 0 : 255,
    ];
    for (final mode in [jb.Jbig2EncodeMode.genericRegion,
      jb.Jbig2EncodeMode.symbolDictionary]) {
      final data = jb.encodeJbig2Packed(packed, width: 8, height: 8,
        options: jb.Jbig2EncodeOptions(mode: mode));
      final dict = PdfCosDict(<String, PdfCos>{
        'Filter': const PdfCosName('JBIG2Decode'),
        'Width': const PdfCosInt(8),
        'Height': const PdfCosInt(8),
      });
      expect(PdfFilters.decode(data, dict), expected);
    }
  });

  test('indirect Flate-wrapped JBIG2Globals resolves through PdfCosStore', () {
    final packed = Uint8List.fromList(List<int>.generate(16,
        (i) => i.isEven ? 0x44 : 0x22));
    final single = jb.decodeJbig2Embedded(jb.encodeJbig2Packed(
      packed, width: 16, height: 8,
    ));
    final shared = jb.encodeJbig2EmbeddedPages([single, single],
      options: const jb.Jbig2EncodeOptions(
        mode: jb.Jbig2EncodeMode.symbolDictionary,
      ),
    );
    expect(shared.globals, isNotEmpty);
    final pdf = PdfFile.open(_imagePdf(shared.pages.first,
      '/Width 16 /Height 8 /BitsPerComponent 1 /ColorSpace /DeviceGray '
      '/Filter /JBIG2Decode /DecodeParms 6 0 R',
      extras: [
        ascii.encode('<< /JBIG2Globals 7 0 R >>'),
        _stream(PdfFlate.compress(shared.globals), '/Filter /FlateDecode'),
      ],
    ));
    final image = pdf.displayList(0).ops.whereType<PdfDrawImage>().single;
    expect(image.placeholder, isFalse);
    expect(image.bytes, [
      for (final tone in single.toGrayscale()) ...[tone, tone, tone],
    ]);
  });

  test('unresolved JBIG2Globals never silently falls back to a blank image', () {
    final dict = PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('JBIG2Decode'),
      'DecodeParms': PdfCosDict(<String, PdfCos>{
        'JBIG2Globals': const PdfCosRef(99),
      }),
    });
    expect(PdfFilters.decodeResult(Uint8List(12), dict).unsupported,
        'JBIG2Decode');
  });

  test('TIFF predictor undoes packed and 16-bit sample deltas by component', () {
    // 4-bit samples [1, 4, 15], padding nibble zero.
    expect(PdfFilters.decode(PdfFlate.compress([0x13, 0xb0]),
      _predictor(3, 1, 4)), [0x14, 0xf0]);
    // 2-bit samples [3, 0, 1, 3] (mod 4 wrap).
    expect(PdfFilters.decode(PdfFlate.compress([0xd6]),
      _predictor(4, 1, 2)), [0xc7]);
    // Two 16-bit RGB-like two-channel pixels:
    // [0x12ff,0xfffe] + [0x0002,0x0003] -> [0x1301,0x0001].
    expect(PdfFilters.decode(PdfFlate.compress(
      [0x12, 0xff, 0xff, 0xfe, 0, 2, 0, 3]),
      _predictor(2, 2, 16)),
      [0x12, 0xff, 0xff, 0xfe, 0x13, 1, 0, 1]);
  });

  test('predictor rejects incomplete rows and unknown PNG row tags', () {
    expect(PdfFilters.decodeResult(PdfFlate.compress([1]),
      _predictor(2, 1, 8)).unsupported, 'FlateDecode');
    expect(PdfFilters.decodeResult(PdfFlate.compress([5, 1, 2]),
      _predictor(2, 1, 8, predictor: 15)).unsupported, 'FlateDecode');
  });

  test('DCT remains encoded for existing JPEG host paths', () {
    final raw = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    final result = PdfFilters.decodeResult(raw, PdfCosDict(<String, PdfCos>{
      'Filter': const PdfCosName('DCTDecode'),
    }));
    expect(result.bytes, raw);
    expect(result.jpxImage, isNull);
  });
}

PdfDisplayList _inlineDisplayList(String parameters, List<int> payload) {
  final file = PdfFile.open(_imagePdf(Uint8List(0), '/Width 1 /Height 1'));
  file.pageDict(0)['Contents'] = PdfCosStream(
    PdfCosDict(),
    Uint8List.fromList([
      ...ascii.encode('0 0 5 5 re f q 10 0 0 10 0 0 cm BI $parameters ID '),
      ...payload,
      ...ascii.encode('\nEI Q 0 0 3 3 re f'),
    ]),
  );
  return file.displayList(0);
}

Uint8List _stream(Uint8List data, String entries) => Uint8List.fromList([
  ...ascii.encode('<< $entries /Length ${data.length} >>\nstream\n'),
  ...data,
  ...ascii.encode('\nendstream'),
]);

Uint8List _imagePdf(Uint8List data, String entries,
    {List<List<int>> extras = const []}) {
  final objects = <List<int>>[
    ascii.encode('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii.encode('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
        '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
    _stream(Uint8List.fromList(ascii.encode('q 40 0 0 40 10 10 cm /Im0 Do Q')), ''),
    _stream(data, '/Type /XObject /Subtype /Image $entries'),
    ...extras,
  ];
  final out = BytesBuilder()..add(ascii.encode('%PDF-1.7\n'));
  final offsets = <int>[];
  for (int i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(ascii.encode('${i + 1} 0 obj\n'));
    out.add(objects[i]);
    out.add(ascii.encode('\nendobj\n'));
  }
  final xref = out.length;
  out.add(ascii.encode('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n'));
  for (final offset in offsets) {
    out.add(ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.add(ascii.encode('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n'));
  return out.takeBytes();
}
