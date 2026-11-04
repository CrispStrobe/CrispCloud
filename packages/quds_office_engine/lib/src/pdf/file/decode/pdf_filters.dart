import 'dart:typed_data';

import '../../../opc/zip/deflate_codec.dart';
import '../../pdf_stream.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';
import 'pdf_ccitt.dart';
import 'pdf_jbig2.dart';

/// ISO 32000-1 §7.4 stream filters used by [PdfFile].
abstract final class PdfFilters {
  /// Decodes [raw] using `/Filter` and `/DecodeParms` on [dict].
  static Uint8List decode(Uint8List raw, PdfCosDict dict) {
    final PdfFilterResult result = decodeResult(raw, dict);
    final Uint8List? bytes = result.bytes;
    if (bytes != null) {
      return bytes;
    }
    throw PdfFilterUnsupported(result.unsupported ?? 'Unknown');
  }

  /// decodeResult API.
  static PdfFilterResult decodeResult(Uint8List raw, PdfCosDict dict) {
    final List<String> filters = _filterNames(dict['Filter']);
    final List<PdfCosDict> parms = _decodeParms(dict['DecodeParms'], filters.length);
    var data = raw;
    for (int i = 0; i < filters.length; i++) {
      final String name = filters[i];
      final PdfCosDict parm = i < parms.length ? parms[i] : PdfCosDict();
      try {
        data = _one(data, name, parm);
      } on PdfFilterUnsupported catch (error) {
        return PdfFilterResult.unsupported(error.filter);
      } on ZipDeflateException {
        return PdfFilterResult.unsupported(name);
      } on FormatException {
        return PdfFilterResult.unsupported(name);
      }
    }
    return PdfFilterResult.ok(data);
  }

  static Uint8List _one(Uint8List data, String name, PdfCosDict parm) {
    switch (name) {
      case 'FlateDecode':
      case 'Fl':
        return _pngPredict(PdfFlate.decompress(data), parm);
      case 'ASCIIHexDecode':
      case 'AHx':
        return _asciiHex(data);
      case 'ASCII85Decode':
      case 'A85':
        return _ascii85(data);
      case 'RunLengthDecode':
      case 'RL':
        return _runLength(data);
      case 'LZWDecode':
      case 'LZW':
        return _pngPredict(_lzw(data, parm), parm);
      case 'DCTDecode':
      case 'DCT':
        return data;
      case 'Crypt':
        return data;
      case 'CCITTFaxDecode':
      case 'CCF':
        return PdfCcitt.decode(data, parm);
      case 'JBIG2Decode':
        return PdfJbig2.decode(data, parm);
      case 'JPXDecode':
        throw PdfFilterUnsupported(name);
      default:
        throw PdfFilterUnsupported(name);
    }
  }

  static List<String> _filterNames(PdfCos? value) {
    if (value is PdfCosName) {
      return <String>[value.value];
    }
    if (value is PdfCosArray) {
      return <String>[
        for (final PdfCos item in value.items)
          if (item is PdfCosName) item.value,
      ];
    }
    return const <String>[];
  }

  static List<PdfCosDict> _decodeParms(PdfCos? value, int count) {
    if (value is PdfCosDict) {
      return <PdfCosDict>[value];
    }
    if (value is PdfCosArray) {
      return <PdfCosDict>[
        for (final PdfCos item in value.items)
          item is PdfCosDict ? item : PdfCosDict(),
      ];
    }
    return <PdfCosDict>[for (int i = 0; i < count; i++) PdfCosDict()];
  }

  static Uint8List _asciiHex(Uint8List data) {
    final List<int> nibbles = <int>[];
    for (final int b in data) {
      if (b == 0x3E) {
        break;
      }
      final int v = _hex(b);
      if (v >= 0) {
        nibbles.add(v);
      }
    }
    if (nibbles.length.isOdd) {
      nibbles.add(0);
    }
    final Uint8List out = Uint8List(nibbles.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = (nibbles[i * 2] << 4) | nibbles[i * 2 + 1];
    }
    return out;
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

  static Uint8List _ascii85(Uint8List data) {
    final BytesBuilder out = BytesBuilder(copy: false);
    var acc = 0;
    var n = 0;
    for (int i = 0; i < data.length; i++) {
      final int b = data[i];
      if (b == 0x7E && i + 1 < data.length && data[i + 1] == 0x3E) {
        break;
      }
      if (b == 0x7A && n == 0) {
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
        out.addByte((acc >> 24) & 0xFF);
        out.addByte((acc >> 16) & 0xFF);
        out.addByte((acc >> 8) & 0xFF);
        out.addByte(acc & 0xFF);
        acc = 0;
        n = 0;
      }
    }
    if (n > 0) {
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

  static Uint8List _runLength(Uint8List data) {
    final BytesBuilder out = BytesBuilder(copy: false);
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
        out.add(data.sublist(i, i + n));
        i += n;
      } else {
        if (i >= data.length) {
          break;
        }
        final int b = data[i++];
        final int n = 257 - len;
        out.add(Uint8List(n)..fillRange(0, n, b));
      }
    }
    return out.takeBytes();
  }

  static Uint8List _lzw(Uint8List data, PdfCosDict parm) {
    final int early = pdfCosInt(parm['EarlyChange']) ?? 1;
    final _Lzw decoder = _Lzw(earlyChange: early != 0);
    return decoder.decode(data);
  }

  static Uint8List _pngPredict(Uint8List data, PdfCosDict parm) {
    final int predictor = pdfCosInt(parm['Predictor']) ?? 1;
    if (predictor <= 1) {
      return data;
    }
    final int columns = pdfCosInt(parm['Columns']) ?? 1;
    final int colors = pdfCosInt(parm['Colors']) ?? 1;
    final int bpc = pdfCosInt(parm['BitsPerComponent']) ?? 8;
    final int rowBytes = ((columns * colors * bpc) + 7) ~/ 8;
    if (predictor == 2) {
      return _tiffPredict(data, rowBytes, colors, bpc);
    }
    if (predictor < 10 || predictor > 15) {
      return data;
    }
    final int stride = rowBytes + 1;
    if (stride <= 1 || data.length < stride) {
      return data;
    }
    final int rows = data.length ~/ stride;
    final Uint8List out = Uint8List(rows * rowBytes);
    final Uint8List prev = Uint8List(rowBytes);
    for (int r = 0; r < rows; r++) {
      final int tag = data[r * stride];
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
    int colors,
    int bpc,
  ) {
    if (bpc != 8) {
      return data;
    }
    final Uint8List out = Uint8List.fromList(data);
    final int rows = out.length ~/ rowBytes;
    for (int r = 0; r < rows; r++) {
      final int base = r * rowBytes;
      for (int i = colors; i < rowBytes; i++) {
        out[base + i] = (out[base + i] + out[base + i - colors]) & 0xFF;
      }
    }
    return out;
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
  const PdfFilterResult.ok(this.bytes) : unsupported = null;

  /// unsupported API.
  const PdfFilterResult.unsupported(this.unsupported) : bytes = null;

  /// bytes API.
  final Uint8List? bytes;

  /// unsupported API.
  final String? unsupported;
}

class _Lzw {
  _Lzw({required this.earlyChange});

  final bool earlyChange;
  static const int _clear = 256;
  static const int _eod = 257;

  Uint8List decode(Uint8List data) {
    final BytesBuilder out = BytesBuilder(copy: false);
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
