import 'dart:typed_data';

import '../../../io/byte_source.dart';
import '../../pdf_stream.dart';
import '../cos/pdf_cos.dart';
import '../cos/pdf_open_error.dart';
import 'pdf_ccitt.dart';

/// Limited `/JBIG2Decode`: file/page headers and MMR generic regions.
///
/// Symbol dictionaries, text regions, and arithmetic generic coding stay
/// [PdfFilterUnsupported] so those XObjects remain placeholders.
abstract final class PdfJbig2 {
  /// Decodes to 8-bit DeviceGray (`0x00` black / `0xFF` white), like CCITT.
  static Uint8List decode(Uint8List data, PdfCosDict parm) {
    if (data.length > 16 * 1024 * 1024) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    final Uint8List globals = _globals(parm);
    final BytesBuilder joined = BytesBuilder(copy: false);
    if (globals.isNotEmpty) {
      joined.add(globals);
    }
    joined.add(data);
    final Uint8List stream = joined.takeBytes();
    final _Jbig2Reader reader = _Jbig2Reader(stream);
    reader.run();
    final Uint8List? page = reader.page;
    if (page == null || reader.width <= 0 || reader.height <= 0) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    return page;
  }

  static Uint8List _globals(PdfCosDict parm) {
    final PdfCos? raw = parm['JBIG2Globals'];
    if (raw is PdfCosStream) {
      try {
        return PdfFiltersProxy.decode(raw.raw, raw.dict);
      } on Object {
        return Uint8List(0);
      }
    }
    return Uint8List(0);
  }
}

/// Avoids a circular import with [PdfFilters] by decoding Flate/ASCII only.
abstract final class PdfFiltersProxy {
  /// decode API.
  static Uint8List decode(Uint8List raw, PdfCosDict dict) {
    final PdfCos? filter = dict['Filter'];
    if (filter == null) {
      return raw;
    }
    final String name = filter is PdfCosName
        ? filter.value
        : (filter is PdfCosArray &&
              filter.items.isNotEmpty &&
              filter.items.first is PdfCosName)
        ? (filter.items.first as PdfCosName).value
        : '';
    if (name == 'FlateDecode' || name == 'Fl') {
      return PdfFlate.decompress(raw);
    }
    return raw;
  }
}

class _Jbig2Reader {
  _Jbig2Reader(this.bytes) : cur = ByteCursor(bytes);

  final Uint8List bytes;
  final ByteCursor cur;
  var width = 0;
  var height = 0;
  Uint8List? page;
  var _sawUnsupported = false;

  static const int _maxSide = 8192;
  static const int _maxPixels = 16 * 1024 * 1024;

  void run() {
    _maybeHeader();
    while (!cur.isEof && cur.remaining >= 4) {
      final _Seg? seg = _segment();
      if (seg == null) {
        break;
      }
      _dispatch(seg);
      if (seg.type == 51) {
        break;
      }
    }
    if (_sawUnsupported && page == null) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
  }

  void _maybeHeader() {
    if (cur.remaining < 9) {
      return;
    }
    if (bytes[cur.offset] == 0x97 &&
        bytes[cur.offset + 1] == 0x4A &&
        bytes[cur.offset + 2] == 0x42 &&
        bytes[cur.offset + 3] == 0x32) {
      cur.skip(8);
      final int flags = cur.u8();
      if ((flags & 0x02) == 0) {
        if (cur.remaining < 4) {
          return;
        }
        cur.u32be();
      }
    }
  }

  _Seg? _segment() {
    if (cur.remaining < 8) {
      return null;
    }
    final int number = cur.u32be();
    final int flags = cur.u8();
    final int type = flags & 0x3F;
    final bool page4 = (flags & 0x40) != 0;
    if (cur.remaining < 1) {
      return null;
    }
    final int rts = cur.u8();
    var refCount = (rts >> 5) & 0x7;
    if (refCount == 7) {
      if (cur.remaining < 4) {
        return null;
      }
      refCount = cur.u32be();
      final int retainBytes = (refCount + 8) ~/ 8;
      if (cur.remaining < retainBytes) {
        return null;
      }
      cur.skip(retainBytes);
    }
    final int refSize = number <= 256
        ? 1
        : number <= 65536
        ? 2
        : 4;
    final int refsLen = refCount * refSize;
    if (cur.remaining < refsLen) {
      return null;
    }
    cur.skip(refsLen);
    final int pageBytes = page4 ? 4 : 1;
    if (cur.remaining < pageBytes + 4) {
      return null;
    }
    if (page4) {
      cur.u32be();
    } else {
      cur.u8();
    }
    final int dataLength = cur.u32be();
    if (dataLength == 0xFFFFFFFF || dataLength < 0 || dataLength > cur.remaining) {
      return null;
    }
    final int start = cur.offset;
    cur.skip(dataLength);
    return _Seg(
      type: type,
      data: Uint8List.sublistView(bytes, start, start + dataLength),
    );
  }

  void _dispatch(_Seg seg) {
    switch (seg.type) {
      case 48:
        _pageInfo(seg.data);
      case 36:
      case 38:
        _generic(seg.data);
      case 49:
      case 50:
      case 51:
      case 52:
      case 53:
      case 62:
        break;
      default:
        if (seg.type == 0 ||
            seg.type == 4 ||
            seg.type == 6 ||
            seg.type == 7 ||
            seg.type == 20 ||
            seg.type == 39 ||
            seg.type == 43) {
          _sawUnsupported = true;
        }
    }
  }

  void _pageInfo(Uint8List data) {
    if (data.length < 19) {
      return;
    }
    final ByteCursor c = ByteCursor(data);
    final int w = c.u32be();
    final int h = c.u32be();
    if (w <= 0 || h <= 0 || w > _maxSide || h > _maxSide || w * h > _maxPixels) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    width = w;
    height = h;
    page = Uint8List(w * h)..fillRange(0, w * h, 0xFF);
  }

  void _generic(Uint8List data) {
    if (data.length < 18) {
      _sawUnsupported = true;
      return;
    }
    final ByteCursor c = ByteCursor(data);
    final int rw = c.u32be();
    final int rh = c.u32be();
    final int x = c.u32be();
    final int y = c.u32be();
    final int comb = c.u8() & 0x7;
    final int flags = c.u8();
    final bool mmr = (flags & 0x01) != 0;
    if (!mmr) {
      _sawUnsupported = true;
      return;
    }
    if (rw <= 0 ||
        rh <= 0 ||
        rw > _maxSide ||
        rh > _maxSide ||
        rw * rh > _maxPixels) {
      throw const PdfFilterUnsupported('JBIG2Decode');
    }
    if (page == null) {
      width = rw;
      height = rh;
      page = Uint8List(rw * rh)..fillRange(0, rw * rh, 0xFF);
    }
    final Uint8List coded = Uint8List.sublistView(data, 18);
    final Uint8List gray = PdfCcitt.decode(
      coded,
      PdfCosDict(<String, PdfCos>{
        'Columns': PdfCosInt(rw),
        'Rows': PdfCosInt(rh),
        'K': const PdfCosInt(-1),
      }),
    );
    _blit(gray, rw, rh, x, y, comb);
  }

  void _blit(Uint8List src, int rw, int rh, int x0, int y0, int comb) {
    final Uint8List dest = page!;
    for (int y = 0; y < rh; y++) {
      final int dy = y0 + y;
      if (dy < 0 || dy >= height) {
        continue;
      }
      for (int x = 0; x < rw; x++) {
        final int dx = x0 + x;
        if (dx < 0 || dx >= width) {
          continue;
        }
        final int si = y * rw + x;
        final int di = dy * width + dx;
        if (si >= src.length) {
          return;
        }
        final int a = src[si];
        final int b = dest[di];
        switch (comb) {
          case 1:
            dest[di] = a & b;
          case 2:
            dest[di] = a ^ b;
          case 3:
            dest[di] = ~(a ^ b) & 0xFF;
          case 4:
            dest[di] = a;
          default:
            dest[di] = a < b ? a : b;
        }
      }
    }
  }
}

class _Seg {
  const _Seg({required this.type, required this.data});

  final int type;
  final Uint8List data;
}
