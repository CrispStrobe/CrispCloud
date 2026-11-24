import 'dart:typed_data';

import '../../../opc/zip/deflate_codec.dart';
import '../../pdf_stream.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';
import 'pdf_ccitt.dart';
import 'pdf_dct.dart';
import 'pdf_jbig2.dart';
import 'pdf_jpx.dart';

/// ISO 32000-1 §7.4 stream filters used by [PdfFile].
abstract final class PdfFilters {
  static const int maxDecodedBytes = PdfFlate.maxDecodedBytes;

  /// Decodes [raw] using `/Filter` and `/DecodeParms` on [dict].
  static Uint8List decode(Uint8List raw, PdfCosDict dict) {
    final PdfFilterResult result = decodeResult(raw, dict);
    final Uint8List? bytes = result.bytes;
    if (bytes != null) {
      return bytes;
    }
    if (result.limitExceeded) {
      throw const PdfOpenException(PdfOpenError.limit, 'Decoded stream too large');
    }
    throw PdfFilterUnsupported(result.unsupported ?? 'Unknown');
  }

  /// decodeResult API.
  static PdfFilterResult decodeResult(
    Uint8List raw,
    PdfCosDict dict, {
    PdfCos? Function(PdfCos?)? resolve,
    bool decodeDct = false,
    int maxOutputBytes = maxDecodedBytes,
  }) {
    if (maxOutputBytes < 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    final int limit = maxOutputBytes.clamp(0, maxDecodedBytes);
    PdfCos? resolved(PdfCos? value) => resolve?.call(value) ?? value;
    final List<String> filters = _filterNames(
      resolved(dict['Filter']),
      resolved,
    );
    final List<PdfCosDict> parms = _decodeParms(
      resolved(dict['DecodeParms']),
      filters.length,
      resolved,
    );
    var data = raw;
    for (int i = 0; i < filters.length; i++) {
      final String name = filters[i];
      final PdfCosDict parm = i < parms.length ? parms[i] : PdfCosDict();
      try {
        if (name == 'DCTDecode' || name == 'DCT') {
          if (i != filters.length - 1) {
            return const PdfFilterResult.unsupported('DCTDecode');
          }
          if (decodeDct) {
            final image = PdfDct.decode(data, dict, parm, resolve: resolved);
            if (image != null) {
              return PdfFilterResult.dct(image);
            }
          }
          return PdfFilterResult.encodedJpeg(data);
        }
        if (name == 'JPXDecode') {
          if (i != filters.length - 1) {
            return PdfFilterResult.unsupported(name);
          }
          return PdfFilterResult.jpx(
            PdfJpx.decode(data, dict, colorSpace: resolved(dict['ColorSpace'])),
          );
        }
        if (name == 'JBIG2Decode') {
          if (i != filters.length - 1) {
            return PdfFilterResult.unsupported(name);
          }
          data = PdfJbig2.decode(
            data,
            dict,
            globals: _jbig2Globals(parm, resolved),
          );
        } else {
          data = _one(data, name, parm, dict, limit);
        }
      } on PdfFilterUnsupported catch (error) {
        return PdfFilterResult.unsupported(error.filter);
      } on ZipDeflateLimitException {
        return PdfFilterResult.unsupported(name, limitExceeded: true);
      } on PdfOpenException catch (error) {
        if (error.error != PdfOpenError.limit) rethrow;
        return PdfFilterResult.unsupported(name, limitExceeded: true);
      } on _OutputLimit {
        return PdfFilterResult.unsupported(name, limitExceeded: true);
      } on ZipDeflateException {
        return PdfFilterResult.unsupported(name);
      } on FormatException {
        return PdfFilterResult.unsupported(name);
      }
    }
    if (data.length > limit) {
      return const PdfFilterResult.unsupported(
        'StreamTooLarge',
        limitExceeded: true,
      );
    }
    return PdfFilterResult.ok(data);
  }

  /// Decode one inline-image Flate stream and the filters following it.
  static ({PdfFilterResult result, int consumed})? decodeInlineFlatePrefix(
    Uint8List data,
    PdfCosDict dict, {
    required int maxOutputBytes,
    required PdfCos? Function(PdfCos?) resolve,
  }) {
    final ({Uint8List bytes, int consumed}) prefix;
    try {
      prefix = PdfFlate.decompressZlibPrefix(
        data,
        maxOutputBytes: maxOutputBytes,
      );
    } on ZipDeflateException {
      return null;
    } on PdfOpenException catch (error) {
      if (error.error != PdfOpenError.limit) rethrow;
      return null;
    } on FormatException {
      return null;
    }
    final filters = _filterNames(resolve(dict['Filter']), resolve);
    final parms = _decodeParms(
      resolve(dict['DecodeParms']), filters.length, resolve,
    );
    try {
      final samples = _pngPredict(prefix.bytes, parms.firstOrNull ?? PdfCosDict());
      if (filters.length <= 1) {
        return (result: PdfFilterResult.ok(samples), consumed: prefix.consumed);
      }
      final rest = PdfCosDict({...dict.values})
        ..['Filter'] = PdfCosArray([
          for (final name in filters.skip(1)) PdfCosName(name),
        ])
        ..['DecodeParms'] = PdfCosArray(parms.skip(1).toList());
      return (
        result: decodeResult(samples, rest, resolve: resolve, decodeDct: true),
        consumed: prefix.consumed,
      );
    } on FormatException {
      return (
        result: const PdfFilterResult.unsupported('FlateDecode'),
        consumed: prefix.consumed,
      );
    }
  }

  static Uint8List _one(
    Uint8List data,
    String name,
    PdfCosDict parm,
    PdfCosDict dict,
    int limit,
  ) {
    switch (name) {
      case 'FlateDecode':
      case 'Fl':
        return _pngPredict(
          PdfFlate.decompress(data, maxOutputBytes: limit),
          parm,
        );
      case 'ASCIIHexDecode':
      case 'AHx':
        return _asciiHex(data, limit);
      case 'ASCII85Decode':
      case 'A85':
        return _ascii85(data, limit);
      case 'RunLengthDecode':
      case 'RL':
        return _runLength(data, limit);
      case 'LZWDecode':
      case 'LZW':
        return _pngPredict(_lzw(data, parm, limit), parm);
      case 'Crypt':
        return data;
      case 'CCITTFaxDecode':
      case 'CCF':
        return PdfCcitt.decode(
          data,
          parm,
          imageWidth: pdfCosInt(dict['Width']),
          imageHeight: pdfCosInt(dict['Height']),
        );
      default:
        throw PdfFilterUnsupported(name);
    }
  }

  static List<String> _filterNames(
    PdfCos? value,
    PdfCos? Function(PdfCos?) resolve,
  ) {
    if (value is PdfCosName) {
      return <String>[value.value];
    }
    if (value is PdfCosArray) {
      return <String>[
        for (final PdfCos item in value.items)
          pdfCosName(resolve(item)) ?? 'InvalidFilter',
      ];
    }
    return value == null || value is PdfCosNull
        ? const <String>[]
        : const <String>['InvalidFilter'];
  }

  static List<PdfCosDict> _decodeParms(
    PdfCos? value,
    int count,
    PdfCos? Function(PdfCos?) resolve,
  ) {
    if (value is PdfCosDict) {
      return <PdfCosDict>[value];
    }
    if (value is PdfCosArray) {
      return <PdfCosDict>[
        for (final PdfCos item in value.items)
          switch (resolve(item)) {
            final PdfCosDict dict => dict,
            _ => PdfCosDict(),
          },
      ];
    }
    return <PdfCosDict>[for (int i = 0; i < count; i++) PdfCosDict()];
  }

  static Uint8List? _jbig2Globals(
    PdfCosDict parm,
    PdfCos? Function(PdfCos?) resolve,
  ) {
    final PdfCos? entry = parm['JBIG2Globals'];
    if (entry == null || entry is PdfCosNull) {
      return null;
    }
    final PdfCos? stream = resolve(entry);
    if (stream is! PdfCosStream || stream.raw.length > 16 * 1024 * 1024) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    // Global dictionaries are ordinary byte streams, not image streams.
    // Reject recursive image filters rather than silently ignoring globals.
    final List<String> names = _filterNames(
      resolve(stream.dict['Filter']),
      resolve,
    );
    const allowed = <String>{
      'FlateDecode',
      'Fl',
      'LZWDecode',
      'LZW',
      'ASCII85Decode',
      'A85',
      'ASCIIHexDecode',
      'AHx',
      'RunLengthDecode',
      'RL',
      'Crypt',
    };
    if (names.any((name) => !allowed.contains(name))) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    final Uint8List? bytes = decodeResult(
      stream.raw,
      stream.dict,
      resolve: resolve,
    ).bytes;
    if (bytes == null || bytes.length > 16 * 1024 * 1024) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    return bytes;
  }

  static Uint8List _asciiHex(Uint8List data, int limit) {
    final out = BytesBuilder();
    int? high;
    for (final int b in data) {
      if (b == 0x3E) {
        break;
      }
      final int v = _hex(b);
      if (v >= 0) {
        if (high == null) {
          high = v;
        } else {
          _checkOutput(out, 1, limit);
          out.addByte((high << 4) | v);
          high = null;
        }
      }
    }
    if (high != null) {
      _checkOutput(out, 1, limit);
      out.addByte(high << 4);
    }
    return out.takeBytes();
  }

  static int _hex(int b) {
    if (b >= 0x30 && b <= 0x39) {
      return b - 0x30;
    }
    if (b >= 0x41 && b <= 0x46) {
      return b - 0x41 + 10;
    }
    if (b >= 0x61 && b <= 0x66) {
      return b - 0x61 + 10;
    }
    return -1;
  }

  static Uint8List _ascii85(Uint8List data, int limit) {
    final BytesBuilder out = BytesBuilder();
    var acc = 0;
    var n = 0;
    for (int i = 0; i < data.length; i++) {
      final int b = data[i];
      if (b == 0x7E && i + 1 < data.length && data[i + 1] == 0x3E) {
        break;
      }
      if (b == 0x7A && n == 0) {
        _checkOutput(out, 4, limit);
        out.add(Uint8List(4));
        continue;
      }
      if (b <= 0x20) {
        continue;
      }
      if (b < 0x21 || b > 0x75) {
        continue;
      }
      acc = acc * 85 + (b - 0x21);
      n++;
      if (n == 5) {
        _checkOutput(out, 4, limit);
        out.addByte((acc >> 24) & 0xFF);
        out.addByte((acc >> 16) & 0xFF);
        out.addByte((acc >> 8) & 0xFF);
        out.addByte(acc & 0xFF);
        acc = 0;
        n = 0;
      }
    }
    if (n > 0) {
      _checkOutput(out, n - 1, limit);
      for (int i = n; i < 5; i++) {
        acc = acc * 85 + 84;
      }
      final Uint8List word = Uint8List(4)
        ..[0] = (acc >> 24) & 0xFF
        ..[1] = (acc >> 16) & 0xFF
        ..[2] = (acc >> 8) & 0xFF
        ..[3] = acc & 0xFF;
      out.add(word.sublist(0, n - 1));
    }
    return out.takeBytes();
  }

  static Uint8List _runLength(Uint8List data, int limit) {
    final BytesBuilder out = BytesBuilder();
    var i = 0;
    while (i < data.length) {
      final int len = data[i++];
      if (len == 128) {
        break;
      }
      if (len < 128) {
        final int n = len + 1;
        if (i + n > data.length) {
          break;
        }
        _checkOutput(out, n, limit);
        out.add(Uint8List.sublistView(data, i, i + n));
        i += n;
      } else {
        if (i >= data.length) {
          break;
        }
        final int b = data[i++];
        final int n = 257 - len;
        _checkOutput(out, n, limit);
        out.add(Uint8List(n)..fillRange(0, n, b));
      }
    }
    return out.takeBytes();
  }

  static Uint8List _lzw(Uint8List data, PdfCosDict parm, int limit) {
    final int early = pdfCosInt(parm['EarlyChange']) ?? 1;
    final _Lzw decoder = _Lzw(earlyChange: early != 0);
    return decoder.decode(data, limit);
  }

  static void _checkOutput(BytesBuilder out, int additional, int limit) {
    if (additional > limit - out.length) {
      throw const _OutputLimit();
    }
  }

  static Uint8List _pngPredict(Uint8List data, PdfCosDict parm) {
    final int predictor = pdfCosInt(parm['Predictor']) ?? 1;
    if (predictor <= 1) {
      return data;
    }
    final int columns = pdfCosInt(parm['Columns']) ?? 1;
    final int colors = pdfCosInt(parm['Colors']) ?? 1;
    final int bpc = pdfCosInt(parm['BitsPerComponent']) ?? 8;
    if (columns < 1 ||
        columns > 16 * 1024 * 1024 ||
        colors < 1 ||
        colors > 32 ||
        !const <int>{1, 2, 4, 8, 16}.contains(bpc)) {
      throw const FormatException('Invalid predictor dimensions');
    }
    final int rowBytes = ((columns * colors * bpc) + 7) ~/ 8;
    if (predictor == 2) {
      return _tiffPredict(data, rowBytes, columns, colors, bpc);
    }
    if (predictor < 10 || predictor > 15) {
      throw const FormatException('Invalid predictor');
    }
    final int stride = rowBytes + 1;
    if (data.length % stride != 0) {
      throw const FormatException('Truncated PNG predictor row');
    }
    if (data.isEmpty) {
      return data;
    }
    final int rows = data.length ~/ stride;
    final Uint8List out = Uint8List(rows * rowBytes);
    final Uint8List prev = Uint8List(rowBytes);
    for (int r = 0; r < rows; r++) {
      final int tag = data[r * stride];
      if (tag > 4) {
        throw const FormatException('Invalid PNG predictor tag');
      }
      final Uint8List row = data.sublist(r * stride + 1, r * stride + stride);
      final Uint8List dest = Uint8List(rowBytes);
      final int bpp = (colors * bpc + 7) ~/ 8;
      for (int i = 0; i < rowBytes; i++) {
        final int left = i >= bpp ? dest[i - bpp] : 0;
        final int up = prev[i];
        final int upLeft = i >= bpp ? prev[i - bpp] : 0;
        final int raw = row[i];
        dest[i] = switch (tag) {
          0 => raw,
          1 => (raw + left) & 0xFF,
          2 => (raw + up) & 0xFF,
          3 => (raw + ((left + up) ~/ 2)) & 0xFF,
          4 => (raw + _paeth(left, up, upLeft)) & 0xFF,
          _ => raw,
        };
      }
      out.setRange(r * rowBytes, (r + 1) * rowBytes, dest);
      prev.setAll(0, dest);
    }
    return out;
  }

  static Uint8List _tiffPredict(
    Uint8List data,
    int rowBytes,
    int columns,
    int colors,
    int bpc,
  ) {
    if (data.length % rowBytes != 0) {
      throw const FormatException('Truncated TIFF predictor row');
    }
    final Uint8List out = Uint8List.fromList(data);
    final int mask = (1 << bpc) - 1;
    final int samples = columns * colors;
    for (int base = 0; base < out.length; base += rowBytes) {
      for (int i = colors; i < samples; i++) {
        final int pos = i * bpc;
        final int previous = (i - colors) * bpc;
        final int value =
            (_readSample(out, base, pos, bpc) +
                _readSample(out, base, previous, bpc)) &
            mask;
        _writeSample(out, base, pos, bpc, value);
      }
    }
    return out;
  }

  static int _readSample(Uint8List data, int base, int bit, int bpc) {
    final int index = base + (bit >> 3);
    if (bpc == 16) {
      return (data[index] << 8) | data[index + 1];
    }
    return (data[index] >> (8 - bpc - (bit & 7))) & ((1 << bpc) - 1);
  }

  static void _writeSample(
    Uint8List data,
    int base,
    int bit,
    int bpc,
    int value,
  ) {
    final int index = base + (bit >> 3);
    if (bpc == 16) {
      data[index] = value >> 8;
      data[index + 1] = value & 255;
      return;
    }
    final int shift = 8 - bpc - (bit & 7);
    final int mask = ((1 << bpc) - 1) << shift;
    data[index] = (data[index] & ~mask) | (value << shift);
  }

  static int _paeth(int a, int b, int c) {
    final int p = a + b - c;
    final int pa = (p - a).abs();
    final int pb = (p - b).abs();
    final int pc = (p - c).abs();
    if (pa <= pb && pa <= pc) {
      return a;
    }
    if (pb <= pc) {
      return b;
    }
    return c;
  }
}

/// Decoded stream or a named unsupported filter.
class PdfFilterResult {
  /// ok API.
  const PdfFilterResult.ok(this.bytes)
    : unsupported = null, jpxImage = null, dctImage = null, jpegEncoded = false,
      limitExceeded = false;

  /// Original JPEG codestream for legacy byte consumers and host fallback.
  const PdfFilterResult.encodedJpeg(this.bytes)
    : unsupported = null, jpxImage = null, dctImage = null, jpegEncoded = true,
      limitExceeded = false;

  /// Engine-decoded JPEG with normalized RGB samples.
  PdfFilterResult.dct(PdfDctImage image)
    : bytes = image.pixels, unsupported = null, jpxImage = null,
      dctImage = image, jpegEncoded = false, limitExceeded = false;

  /// A decoded JPEG 2000 image; bytes are normalized RGB/RGBA samples.
  PdfFilterResult.jpx(PdfJpxImage image)
    : bytes = image.pixels, unsupported = null, jpxImage = image,
      dctImage = null, jpegEncoded = false, limitExceeded = false;

  /// unsupported API.
  const PdfFilterResult.unsupported(this.unsupported, {this.limitExceeded = false})
    : bytes = null, jpxImage = null, dctImage = null, jpegEncoded = false;

  /// Image layout for JPX, independent of PDF dictionary color defaults.
  final PdfJpxImage? jpxImage;

  /// Normalized JPEG layout when image decoding is requested.
  final PdfDctImage? dctImage;

  /// Whether bytes still contain a JPEG codestream.
  final bool jpegEncoded;

  /// bytes API.
  final Uint8List? bytes;

  /// unsupported API.
  final String? unsupported;

  /// Whether decoding would exceed the stream's byte budget.
  final bool limitExceeded;
}

class _OutputLimit implements Exception {
  const _OutputLimit();
}

class _Lzw {
  _Lzw({required this.earlyChange});

  final bool earlyChange;
  static const int _clear = 256;
  static const int _eod = 257;

  Uint8List decode(Uint8List data, int limit) {
    final BytesBuilder out = BytesBuilder();
    var bits = 9;
    var next = 258;
    final List<List<int>> table = <List<int>>[
      for (int i = 0; i < 258; i++) <int>[i],
    ];
    final _BitIn input = _BitIn(data);
    List<int>? prev;
    while (true) {
      final int? code = input.read(bits);
      if (code == null || code == _eod) {
        break;
      }
      if (code == _clear) {
        bits = 9;
        next = 258;
        table
          ..clear()
          ..addAll(<List<int>>[
            for (int i = 0; i < 258; i++) <int>[i],
          ]);
        prev = null;
        continue;
      }
      List<int> entry;
      if (code < table.length) {
        entry = table[code];
      } else if (prev != null && code == next) {
        entry = <int>[...prev, prev.first];
      } else {
        break;
      }
      PdfFilters._checkOutput(out, entry.length, limit);
      out.add(entry);
      if (prev != null && next < 4096) {
        table.add(<int>[...prev, entry.first]);
        next++;
        final int threshold = earlyChange ? (1 << bits) - 1 : 1 << bits;
        if (next == threshold && bits < 12) {
          bits++;
        }
      }
      prev = entry;
    }
    return out.takeBytes();
  }
}

class _BitIn {
  _BitIn(this.data);
  final Uint8List data;
  var _i = 0;
  var _bit = 0;

  int? read(int width) {
    var v = 0;
    for (int n = 0; n < width; n++) {
      if (_i >= data.length) {
        return null;
      }
      final int bit = (data[_i] >> (7 - _bit)) & 1;
      v = (v << 1) | bit;
      _bit++;
      if (_bit == 8) {
        _bit = 0;
        _i++;
      }
    }
    return v;
  }
}
