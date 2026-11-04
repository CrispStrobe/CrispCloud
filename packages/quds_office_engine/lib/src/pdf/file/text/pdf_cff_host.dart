import 'dart:typed_data';

import 'pdf_tounicode.dart';

/// Wraps raw CFF `/FontFile3` (Type 1C / CID CFF) in a minimal OTTO so a
/// host `FontLoader` can paint it. The engine does **not** rasterize CFF.
abstract final class PdfCffHost {
  /// True when [bytes] are already an OpenType / TrueType / TTC face.
  static bool isSfnt(Uint8List bytes) {
    if (bytes.length < 4) {
      return false;
    }
    return (bytes[0] == 0x4F &&
            bytes[1] == 0x54 &&
            bytes[2] == 0x54 &&
            bytes[3] == 0x4F) ||
        (bytes[0] == 0x00 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x00 &&
            bytes[3] == 0x00) ||
        (bytes[0] == 0x74 &&
            bytes[1] == 0x72 &&
            bytes[2] == 0x75 &&
            bytes[3] == 0x65) ||
        (bytes[0] == 0x74 &&
            bytes[1] == 0x74 &&
            bytes[2] == 0x63 &&
            bytes[3] == 0x66);
  }

  /// True when [bytes] start with a CFF1 header.
  static bool isRawCff(Uint8List bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 1 &&
        bytes[1] == 0 &&
        bytes[2] >= 4 &&
        bytes[2] <= 16;
  }

  /// Host-loadable face: SFNT passthrough (with cmap repair), or CFF wrapped as OTTO.
  static Uint8List forFlutter(
    Uint8List bytes, {
    PdfToUnicode? toUnicode,
    bool cid = false,
    String family = 'CFF',
  }) {
    if (isSfnt(bytes)) {
      return _ensureSfntCmap(bytes, toUnicode, cid);
    }
    if (!isRawCff(bytes)) {
      return bytes;
    }
    try {
      return _wrap(bytes, toUnicode, cid, family);
    } catch (_) {
      return bytes;
    }
  }

  /// TrueType / OTTO subsets often ship a sparse or Identity-wrong `cmap`.
  /// Rebuild from CFF glyph names and ToUnicode so Flutter does not fall back
  /// mid-word (e.g. Myriad missing `f` → Liberation metrics → broken columns).
  static Uint8List _ensureSfntCmap(
    Uint8List bytes,
    PdfToUnicode? toUnicode,
    bool cid,
  ) {
    final Map<int, int> built = <int, int>{};
    final Uint8List? cff = _sfntTableBytes(bytes, 'CFF ');
    if (cff != null) {
      try {
        final _CffFace face = _CffFace.parse(cff);
        face.gidToName.forEach((int gid, String name) {
          final int uni = _glyphNameUnicode(name);
          if (uni > 0) {
            built[uni] = gid;
          }
        });
        face.codeToGid.forEach((int code, int gid) {
          final String mapped = toUnicode?.mapCid(code) ?? '';
          if (mapped.isNotEmpty) {
            built.putIfAbsent(mapped.codeUnitAt(0), () => gid);
          } else if (!cid && code > 0 && code < 0xFFFF) {
            built.putIfAbsent(code, () => gid);
          }
        });
      } catch (_) {}
    }
    if (toUnicode != null) {
      toUnicode.invertCodeUnits().forEach((int uni, int code) {
        if (uni <= 0 || uni >= 0xFFFF) {
          return;
        }
        // Only Identity-fill when we have no name-based entry yet.
        built.putIfAbsent(uni, () => code & 0xFFFF);
      });
    }
    if (built.isEmpty) {
      return bytes;
    }
    // Prefer CFF/name-derived cmap over a sparse embedded one (common for
    // InDesign subsets that omit `f`/`Q` while the CFF still has those glyphs).
    final bool hasCmap = _sfntHasNamedTable(bytes, 'cmap');
    final bool fromCff = cff != null && built.length >= 40;
    if (hasCmap && !fromCff) {
      return bytes;
    }
    try {
      return _sfntReplaceOrAdd(bytes, 'cmap', _cmapTable(built));
    } catch (_) {
      return bytes;
    }
  }

  static Uint8List? _sfntTableBytes(Uint8List bytes, String tag) {
    if (bytes.length < 12) {
      return null;
    }
    final int n = (bytes[4] << 8) | bytes[5];
    var o = 12;
    for (int i = 0; i < n && o + 16 <= bytes.length; i++, o += 16) {
      if (String.fromCharCodes(bytes.sublist(o, o + 4)) != tag) {
        continue;
      }
      final int off =
          (bytes[o + 8] << 24) |
          (bytes[o + 9] << 16) |
          (bytes[o + 10] << 8) |
          bytes[o + 11];
      final int len =
          (bytes[o + 12] << 24) |
          (bytes[o + 13] << 16) |
          (bytes[o + 14] << 8) |
          bytes[o + 15];
      if (off < 0 || len < 1 || off + len > bytes.length) {
        return null;
      }
      return bytes.sublist(off, off + len);
    }
    return null;
  }

  static bool _sfntHasNamedTable(Uint8List bytes, String tag) {
    if (bytes.length < 12) {
      return false;
    }
    final int n = (bytes[4] << 8) | bytes[5];
    var o = 12;
    for (int i = 0; i < n && o + 16 <= bytes.length; i++, o += 16) {
      if (String.fromCharCodes(bytes.sublist(o, o + 4)) == tag) {
        return true;
      }
    }
    return false;
  }

  static Uint8List _sfntReplaceOrAdd(
    Uint8List bytes,
    String tag,
    Uint8List data,
  ) {
    final String scaler = String.fromCharCodes(bytes.sublist(0, 4));
    final int n = (bytes[4] << 8) | bytes[5];
    final List<_Tbl> tables = <_Tbl>[];
    var o = 12;
    for (int i = 0; i < n && o + 16 <= bytes.length; i++, o += 16) {
      final String t = String.fromCharCodes(bytes.sublist(o, o + 4));
      if (t == tag) {
        continue;
      }
      final int off =
          (bytes[o + 8] << 24) |
          (bytes[o + 9] << 16) |
          (bytes[o + 10] << 8) |
          bytes[o + 11];
      final int len =
          (bytes[o + 12] << 24) |
          (bytes[o + 13] << 16) |
          (bytes[o + 14] << 8) |
          bytes[o + 15];
      if (off < 0 || len < 0 || off + len > bytes.length) {
        continue;
      }
      tables.add(_Tbl(t, bytes.sublist(off, off + len)));
    }
    tables.add(_Tbl(tag, data));
    // Keep the original scaler bytes (`\0\1\0\0` or OTTO), not Apple `true`.
    final String head = scaler.length >= 4 ? scaler.substring(0, 4) : 'OTTO';
    return _sfnt(head, tables);
  }

  static Uint8List _wrap(
    Uint8List cff,
    PdfToUnicode? toUnicode,
    bool cid,
    String family,
  ) {
    final _CffFace face = _CffFace.parse(cff);
    final int nGlyphs = face.nGlyphs < 1 ? 1 : face.nGlyphs;
    final Map<int, int> cmap = _cmap(face, toUnicode, cid);
    if (cmap.isEmpty) {
      for (int c = 32; c <= 126 && c - 31 < nGlyphs; c++) {
        cmap[c] = c - 31;
      }
    }
    final String name = face.family.isNotEmpty ? face.family : family;
    final int advance = face.defaultWidth < 1 ? 500 : face.defaultWidth;
    final List<_Tbl> tables = <_Tbl>[
      _Tbl('CFF ', cff),
      _Tbl('OS/2', _os2(face)),
      _Tbl('cmap', _cmapTable(cmap)),
      _Tbl('head', _head(face)),
      _Tbl('hhea', _hhea(nGlyphs, face)),
      _Tbl('hmtx', _hmtx(nGlyphs, advance)),
      _Tbl('maxp', _maxp(nGlyphs)),
      _Tbl('name', _name(name)),
      _Tbl('post', _post()),
    ];
    return _sfnt('OTTO', tables);
  }

  static Map<int, int> _cmap(
    _CffFace face,
    PdfToUnicode? toUnicode,
    bool cid,
  ) {
    final Map<int, int> out = <int, int>{};
    // Glyph-name → Unicode for standard / single-char names (fixes sparse
    // Encoding + ToUnicode mismatches such as Myriad omitting `f` in cmap).
    face.gidToName.forEach((int gid, String name) {
      final int uni = _glyphNameUnicode(name);
      if (uni > 0) {
        out[uni] = gid;
      }
    });
    if (cid || face.cid) {
      for (int gid = 0; gid < face.nGlyphs; gid++) {
        final int cidVal = face.gidToSid[gid] ?? gid;
        final String mapped = toUnicode?.mapCid(cidVal) ?? '';
        if (mapped.isNotEmpty) {
          out.putIfAbsent(mapped.codeUnitAt(0), () => gid);
        }
      }
      return out;
    }
    for (final MapEntry<int, int> e in face.codeToGid.entries) {
      final String mapped = toUnicode?.mapCid(e.key) ?? '';
      if (mapped.isNotEmpty) {
        out.putIfAbsent(mapped.codeUnitAt(0), () => e.value);
        continue;
      }
      final int sid = face.gidToSid[e.value] ?? 0;
      final int uni = _sidUnicode(sid);
      if (uni > 0) {
        out.putIfAbsent(uni, () => e.value);
      }
    }
    if (toUnicode != null) {
      toUnicode.invertCodeUnits().forEach((int uni, int code) {
        final int? gid = face.codeToGid[code];
        if (gid != null) {
          out.putIfAbsent(uni, () => gid);
        }
      });
    }
    return out;
  }
}

class _CffFace {
  _CffFace({
    required this.nGlyphs,
    required this.codeToGid,
    required this.gidToSid,
    required this.gidToName,
    required this.cid,
    required this.family,
    required this.defaultWidth,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  final int nGlyphs;
  final Map<int, int> codeToGid;
  final Map<int, int> gidToSid;
  final Map<int, String> gidToName;
  final bool cid;
  final String family;
  final int defaultWidth;
  final int xMin, yMin, xMax, yMax;

  static _CffFace parse(Uint8List data) {
    final _CffIn p = _CffIn(data);
    final int major = p.card8();
    final int minor = p.card8();
    final int hdrSize = p.card8();
    p.card8();
    if (major != 1 || minor != 0 || hdrSize < 4) {
      throw const FormatException('CFF1 only');
    }
    p.i = hdrSize;
    final _CffIndex nameIndex = p.index();
    final _CffIndex top = p.index();
    final _CffIndex stringIndex = p.index();
    p.index(); // global subrs
    var charsetOff = 0;
    var encodingOff = 0;
    var charStringsOff = 0;
    var privateOff = 0;
    var privateSize = 0;
    var cid = false;
    var xMin = 0, yMin = 0, xMax = 1000, yMax = 1000;
    if (top.count > 0) {
      final _CffIn d = _CffIn(data)..i = top.startOf(0);
      final int end = top.startOf(1);
      final List<num> ops = <num>[];
      while (d.i < end && d.i < data.length) {
        final int b = data[d.i];
        if (b <= 21) {
          var op = d.card8();
          if (op == 12) {
            op = 1200 + d.card8();
          }
          if (op == 15 && ops.isNotEmpty) {
            charsetOff = ops.last.toInt();
          } else if (op == 16 && ops.isNotEmpty) {
            encodingOff = ops.last.toInt();
          } else if (op == 17 && ops.isNotEmpty) {
            charStringsOff = ops.last.toInt();
          } else if (op == 18 && ops.length >= 2) {
            privateSize = ops[ops.length - 2].toInt();
            privateOff = ops.last.toInt();
          } else if (op == 5 && ops.length >= 4) {
            xMin = ops[ops.length - 4].round();
            yMin = ops[ops.length - 3].round();
            xMax = ops[ops.length - 2].round();
            yMax = ops.last.round();
          } else if (op == 1230) {
            cid = true;
          }
          ops.clear();
        } else {
          ops.add(d.number());
        }
      }
    }
    var nGlyphs = 1;
    if (charStringsOff > 0 && charStringsOff < data.length) {
      final _CffIn c = _CffIn(data)..i = charStringsOff;
      nGlyphs = c.peekCount();
    }
    if (nGlyphs < 1) {
      nGlyphs = 1;
    }
    final Map<int, int> gidToSid = _charset(data, charsetOff, nGlyphs);
    final Map<int, int> codeToGid = cid
        ? <int, int>{}
        : _encoding(data, encodingOff, nGlyphs, gidToSid);
    final Map<int, String> gidToName = <int, String>{};
    for (final MapEntry<int, int> e in gidToSid.entries) {
      final String name = _sidName(e.value, data, stringIndex);
      if (name.isNotEmpty) {
        gidToName[e.key] = name;
      }
    }
    var defaultWidth = 500;
    if (privateOff > 0 && privateSize > 0) {
      final _CffIn priv = _CffIn(data)..i = privateOff;
      final int end = privateOff + privateSize;
      final List<num> ops = <num>[];
      while (priv.i < end && priv.i < data.length) {
        final int b = data[priv.i];
        if (b <= 21) {
          final int op = priv.card8();
          if (op == 20 && ops.isNotEmpty) {
            defaultWidth = ops.last.round();
          }
          if (op == 12) {
            priv.card8();
          }
          ops.clear();
        } else {
          ops.add(priv.number());
        }
      }
    }
    var family = 'CFF';
    if (nameIndex.count > 0) {
      final int a = nameIndex.startOf(0);
      final int b = nameIndex.startOf(1);
      if (b > a && b <= data.length) {
        family = String.fromCharCodes(data.sublist(a, b));
      }
    }
    return _CffFace(
      nGlyphs: nGlyphs,
      codeToGid: codeToGid,
      gidToSid: gidToSid,
      gidToName: gidToName,
      cid: cid,
      family: family,
      defaultWidth: defaultWidth,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
    );
  }
}

class _CffIn {
  _CffIn(this.d);
  final Uint8List d;
  var i = 0;

  int card8() => d[i++];

  int card16() => (d[i++] << 8) | d[i++];

  int off(int size) {
    var v = 0;
    for (int k = 0; k < size; k++) {
      v = (v << 8) | d[i++];
    }
    return v;
  }

  int peekCount() {
    if (i + 1 >= d.length) {
      return 0;
    }
    return (d[i] << 8) | d[i + 1];
  }

  _CffIndex index() {
    if (i + 1 >= d.length) {
      return const _CffIndex(0, 0, <int>[]);
    }
    final int count = card16();
    if (count == 0) {
      return _CffIndex(0, i, const <int>[]);
    }
    final int offSize = card8();
    final List<int> offs = <int>[
      for (int k = 0; k <= count; k++) off(offSize),
    ];
    final int base = i - 1;
    i = base + offs.last;
    return _CffIndex(count, base, offs);
  }

  num number() {
    final int b = card8();
    if (b >= 32 && b <= 246) {
      return b - 139;
    }
    if (b >= 247 && b <= 250) {
      return (b - 247) * 256 + card8() + 108;
    }
    if (b >= 251 && b <= 254) {
      return -(b - 251) * 256 - card8() - 108;
    }
    if (b == 28) {
      final int v = (card8() << 8) | card8();
      return v >= 0x8000 ? v - 0x10000 : v;
    }
    if (b == 29) {
      final int v =
          (card8() << 24) | (card8() << 16) | (card8() << 8) | card8();
      return v;
    }
    if (b == 30) {
      while (i < d.length) {
        final int n = card8();
        if ((n & 0x0F) == 0x0F || (n >> 4) == 0x0F) {
          break;
        }
      }
      return 0;
    }
    return 0;
  }
}

class _CffIndex {
  const _CffIndex(this.count, this.base, this.offs);
  final int count;
  final int base;
  final List<int> offs;

  int startOf(int i) => i < offs.length ? base + offs[i] : base;
}

Map<int, int> _charset(Uint8List data, int offset, int nGlyphs) {
  final Map<int, int> gidToSid = <int, int>{0: 0};
  if (offset <= 2) {
    for (int g = 1; g < nGlyphs; g++) {
      gidToSid[g] = g;
    }
    return gidToSid;
  }
  if (offset >= data.length) {
    return gidToSid;
  }
  final _CffIn p = _CffIn(data)..i = offset;
  final int format = p.card8();
  var gid = 1;
  if (format == 0) {
    while (gid < nGlyphs && p.i + 1 < data.length) {
      gidToSid[gid++] = p.card16();
    }
  } else if (format == 1 || format == 2) {
    while (gid < nGlyphs && p.i + 1 < data.length) {
      final int first = p.card16();
      final int nLeft = format == 1 ? p.card8() : p.card16();
      for (int k = 0; k <= nLeft && gid < nGlyphs; k++) {
        gidToSid[gid++] = first + k;
      }
    }
  }
  return gidToSid;
}

Map<int, int> _encoding(
  Uint8List data,
  int offset,
  int nGlyphs,
  Map<int, int> gidToSid,
) {
  final Map<int, int> sidToGid = <int, int>{
    for (final MapEntry<int, int> e in gidToSid.entries) e.value: e.key,
  };
  final Map<int, int> codeToGid = <int, int>{};
  void fromSids(List<int> sids) {
    for (int code = 0; code < sids.length; code++) {
      final int sid = sids[code];
      final int? gid = sidToGid[sid];
      if (gid != null && gid < nGlyphs) {
        codeToGid[code] = gid;
      }
    }
  }

  if (offset <= 0) {
    fromSids(_kStandardEncoding);
    return codeToGid;
  }
  if (offset == 1) {
    fromSids(_kStandardEncoding);
    return codeToGid;
  }
  if (offset >= data.length) {
    return codeToGid;
  }
  final _CffIn p = _CffIn(data)..i = offset;
  final int format = p.card8() & 0x7F;
  var gid = 1;
  if (format == 0) {
    final int nCodes = p.card8();
    for (int k = 0; k < nCodes && gid < nGlyphs && p.i < data.length; k++) {
      codeToGid[p.card8()] = gid++;
    }
  } else if (format == 1) {
    final int nRanges = p.card8();
    for (int r = 0; r < nRanges && gid < nGlyphs; r++) {
      final int first = p.card8();
      final int nLeft = p.card8();
      for (int k = 0; k <= nLeft && gid < nGlyphs; k++) {
        codeToGid[first + k] = gid++;
      }
    }
  }
  return codeToGid;
}

int _sidUnicode(int sid) {
  if (sid <= 0) {
    return 0;
  }
  if (sid <= 95) {
    return 0x20 + (sid - 1);
  }
  final int i = sid - 96;
  if (i < _kSidExtra.length) {
    return _kSidExtra[i];
  }
  return 0;
}

String _sidName(int sid, Uint8List data, _CffIndex strings) {
  if (sid <= 0) {
    return '.notdef';
  }
  if (sid <= 95) {
    return String.fromCharCode(0x20 + (sid - 1));
  }
  if (sid >= 391) {
    final int i = sid - 391;
    if (i >= 0 && i < strings.count) {
      final int a = strings.startOf(i);
      final int b = strings.startOf(i + 1);
      if (b > a && b <= data.length) {
        return String.fromCharCodes(data.sublist(a, b));
      }
    }
    return '';
  }
  // SID 96–390: Adobe standard strings not needed when charset uses customs.
  return '';
}

int _glyphNameUnicode(String name) {
  if (name.isEmpty || name == '.notdef') {
    return 0;
  }
  if (name.length == 1) {
    return name.codeUnitAt(0);
  }
  switch (name) {
    case 'space':
      return 0x20;
    case 'exclam':
      return 0x21;
    case 'quotedbl':
      return 0x22;
    case 'numbersign':
      return 0x23;
    case 'dollar':
      return 0x24;
    case 'percent':
      return 0x25;
    case 'ampersand':
      return 0x26;
    case 'quotesingle':
    case 'quoteright':
      return 0x27;
    case 'parenleft':
      return 0x28;
    case 'parenright':
      return 0x29;
    case 'asterisk':
      return 0x2A;
    case 'plus':
      return 0x2B;
    case 'comma':
      return 0x2C;
    case 'hyphen':
    case 'minus':
      return 0x2D;
    case 'period':
      return 0x2E;
    case 'slash':
      return 0x2F;
    case 'colon':
      return 0x3A;
    case 'semicolon':
      return 0x3B;
    case 'less':
      return 0x3C;
    case 'equal':
      return 0x3D;
    case 'greater':
      return 0x3E;
    case 'question':
      return 0x3F;
    case 'at':
      return 0x40;
    case 'bracketleft':
      return 0x5B;
    case 'backslash':
      return 0x5C;
    case 'bracketright':
      return 0x5D;
    case 'asciicircum':
      return 0x5E;
    case 'underscore':
      return 0x5F;
    case 'grave':
    case 'quoteleft':
      return 0x60;
    case 'braceleft':
      return 0x7B;
    case 'bar':
      return 0x7C;
    case 'braceright':
      return 0x7D;
    case 'asciitilde':
      return 0x7E;
  }
  if (name.startsWith('uni') && name.length >= 7) {
    final int? v = int.tryParse(name.substring(3, 7), radix: 16);
    if (v != null && v > 0) {
      return v;
    }
  }
  return 0;
}

class _Tbl {
  _Tbl(this.tag, this.data);
  final String tag;
  final Uint8List data;
}

class _Buf {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u8(int v) => _b.addByte(v & 0xFF);

  void u16(int v) {
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void u32(int v) {
    _b.addByte((v >> 24) & 0xFF);
    _b.addByte((v >> 16) & 0xFF);
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void i16(int v) => u16(v & 0xFFFF);

  void add(Uint8List d) => _b.add(d);

  Uint8List take() => _b.takeBytes();
}

Uint8List _sfnt(String scaler, List<_Tbl> tables) {
  tables.sort((a, b) => a.tag.compareTo(b.tag));
  final int n = tables.length;
  var search = 1, entry = 0;
  while (search * 2 <= n) {
    search *= 2;
    entry++;
  }
  final List<Uint8List> padded = <Uint8List>[];
  var offset = 12 + n * 16;
  final List<int> offs = <int>[];
  for (final _Tbl t in tables) {
    offs.add(offset);
    final int pad = (4 - (t.data.length & 3)) & 3;
    final Uint8List block = Uint8List(t.data.length + pad);
    block.setAll(0, t.data);
    padded.add(block);
    offset += block.length;
  }
  final _Buf out = _Buf();
  for (int i = 0; i < 4; i++) {
    out.u8(scaler.codeUnitAt(i));
  }
  out
    ..u16(n)
    ..u16(search * 16)
    ..u16(entry)
    ..u16((n - search) * 16);
  for (int i = 0; i < n; i++) {
    final String tag = tables[i].tag;
    for (int k = 0; k < 4; k++) {
      out.u8(tag.codeUnitAt(k));
    }
    out
      ..u32(_checksum(padded[i]))
      ..u32(offs[i])
      ..u32(tables[i].data.length);
  }
  for (final Uint8List block in padded) {
    out.add(block);
  }
  final Uint8List font = out.take();
  var headAt = -1;
  for (int i = 0; i < n; i++) {
    if (tables[i].tag == 'head') {
      headAt = offs[i];
    }
  }
  if (headAt >= 0) {
    final int adj = (0xB1B0AFBA - _checksum(font)) & 0xFFFFFFFF;
    font[headAt + 8] = (adj >> 24) & 0xFF;
    font[headAt + 9] = (adj >> 16) & 0xFF;
    font[headAt + 10] = (adj >> 8) & 0xFF;
    font[headAt + 11] = adj & 0xFF;
  }
  return font;
}

int _checksum(Uint8List data) {
  var sum = 0;
  for (int i = 0; i < data.length; i += 4) {
    var v = 0;
    for (int k = 0; k < 4; k++) {
      v = (v << 8) | (i + k < data.length ? data[i + k] : 0);
    }
    sum = (sum + v) & 0xFFFFFFFF;
  }
  return sum;
}

Uint8List _head(_CffFace face) {
  final _Buf b = _Buf()
    ..u16(1)
    ..u16(0)
    ..u32(0)
    ..u32(0)
    ..u32(0x5F0F3CF5)
    ..u16(0)
    ..u16(1000)
    ..u32(0)
    ..u32(0)
    ..u32(0)
    ..u32(0)
    ..i16(face.xMin)
    ..i16(face.yMin)
    ..i16(face.xMax)
    ..i16(face.yMax)
    ..u16(0)
    ..u16(0)
    ..i16(2)
    ..i16(0)
    ..i16(0);
  return b.take();
}

Uint8List _hhea(int nGlyphs, _CffFace face) {
  // OpenType `hhea` is 36 bytes; omitting `metricDataFormat` truncates the
  // table so host parsers (and Flutter FontLoader) reject the OTTO wrap.
  final _Buf b = _Buf()
    ..u16(1)
    ..u16(0)
    ..i16(face.yMax <= 0 ? 800 : face.yMax)
    ..i16(face.yMin)
    ..i16(0)
    ..u16(face.defaultWidth < 1 ? 500 : face.defaultWidth)
    ..i16(0) // minLeftSideBearing
    ..i16(0) // minRightSideBearing
    ..i16(0) // xMaxExtent
    ..i16(1) // caretSlopeRise
    ..i16(0) // caretSlopeRun
    ..i16(0) // caretOffset
    ..i16(0) // reserved
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0) // metricDataFormat
    ..u16(nGlyphs); // numberOfHMetrics
  return b.take();
}

Uint8List _hmtx(int nGlyphs, int advance) {
  final _Buf b = _Buf();
  for (int i = 0; i < nGlyphs; i++) {
    b
      ..u16(advance)
      ..i16(0);
  }
  return b.take();
}

Uint8List _maxp(int nGlyphs) {
  final _Buf b = _Buf()
    ..u32(0x00005000)
    ..u16(nGlyphs);
  return b.take();
}

Uint8List _os2(_CffFace face) {
  final _Buf b = _Buf()
    ..u16(3)
    ..i16(500)
    ..u16(400)
    ..u16(5)
    ..i16(0)
    ..i16(250)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0)
    ..i16(0);
  for (int i = 0; i < 10; i++) {
    b.u8(0);
  }
  b
    ..u32(0)
    ..u32(0)
    ..u32(0)
    ..u32(0);
  for (final int c in 'CFF '.codeUnits) {
    b.u8(c);
  }
  b
    ..u16(0x0040)
    ..u16(0x20)
    ..u16(0x7E)
    ..i16(face.yMax <= 0 ? 800 : face.yMax)
    ..i16(face.yMin)
    ..i16(0)
    ..i16(face.yMax <= 0 ? 800 : face.yMax)
    ..i16(face.yMin)
    ..i16(0)
    ..u32(1)
    ..u32(0)
    ..u32(0)
    ..u32(0)
    ..u16(0x20)
    ..u16(0x7E);
  return b.take();
}

Uint8List _name(String family) {
  final Uint8List raw = Uint8List.fromList(family.codeUnits);
  final _Buf b = _Buf()
    ..u16(0)
    ..u16(1)
    ..u16(18)
    ..u16(1)
    ..u16(0)
    ..u16(0)
    ..u16(1)
    ..u16(raw.length)
    ..u16(0);
  b.add(raw);
  return b.take();
}

Uint8List _post() {
  final _Buf b = _Buf()
    ..u32(0x00030000)
    ..u32(0)
    ..i16(0)
    ..i16(0)
    ..u32(0)
    ..u32(0)
    ..u32(0)
    ..u32(0);
  return b.take();
}

Uint8List _cmapTable(Map<int, int> cmap) {
  final List<MapEntry<int, int>> pairs = cmap.entries
      .where((MapEntry<int, int> e) => e.key > 0 && e.key < 0xFFFF)
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final List<({int start, int end, int delta})> segs =
      <({int start, int end, int delta})>[];
  for (final MapEntry<int, int> e in pairs) {
    final int delta = (e.value - e.key) & 0xFFFF;
    if (segs.isNotEmpty &&
        segs.last.end + 1 == e.key &&
        segs.last.delta == delta) {
      segs[segs.length - 1] = (
        start: segs.last.start,
        end: e.key,
        delta: delta,
      );
    } else {
      segs.add((start: e.key, end: e.key, delta: delta));
    }
  }
  segs.add((start: 0xFFFF, end: 0xFFFF, delta: 1));
  final int segCount = segs.length;
  var search = 2, entry = 0;
  while (search * 2 <= segCount * 2) {
    search *= 2;
    entry++;
  }
  final int length = 16 + segCount * 8;
  final _Buf fmt = _Buf()
    ..u16(4)
    ..u16(length)
    ..u16(0)
    ..u16(segCount * 2)
    ..u16(search)
    ..u16(entry)
    ..u16(segCount * 2 - search);
  for (final s in segs) {
    fmt.u16(s.end);
  }
  fmt.u16(0);
  for (final s in segs) {
    fmt.u16(s.start);
  }
  for (final s in segs) {
    fmt.u16(s.delta);
  }
  for (int i = 0; i < segCount; i++) {
    fmt.u16(0);
  }
  final Uint8List body = fmt.take();
  final _Buf out = _Buf()
    ..u16(0)
    ..u16(1)
    ..u16(3)
    ..u16(1)
    ..u32(12);
  out.add(body);
  return out.take();
}

/// CFF StandardEncoding (ISO 32000 / Adobe TN #5176).
const List<int> _kStandardEncoding = <int>[
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
  17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
  33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
  49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64,
  65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
  81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110,
  0, 111, 112, 113, 114, 0, 115, 116, 117, 118, 119, 120, 121, 122, 0, 123,
  0, 124, 125, 126, 127, 128, 129, 130, 131, 0, 132, 133, 0, 134, 135, 136,
  137, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 138, 0, 139, 0, 0, 0, 0, 140, 141, 142, 143, 0, 0, 0, 0,
  0, 144, 0, 0, 0, 145, 0, 0, 146, 147, 148, 149, 0, 0, 0, 0,
];

/// Unicode for Adobe standard strings SID 96–228.
const List<int> _kSidExtra = <int>[
  0x00A1, 0x00A2, 0x00A3, 0x2044, 0x00A5, 0x0192, 0x00A7, 0x00A4,
  0x0027, 0x201C, 0x00AB, 0x2039, 0x203A, 0xFB01, 0xFB02, 0x2013,
  0x2020, 0x2021, 0x00B7, 0x00B6, 0x2022, 0x201A, 0x201E, 0x201D,
  0x00BB, 0x2026, 0x2030, 0x00BF, 0x0060, 0x00B4, 0x02C6, 0x02DC,
  0x00AF, 0x02D8, 0x02D9, 0x00A8, 0x02DA, 0x00B8, 0x02DD, 0x02DB,
  0x02C7, 0x2014, 0x00C6, 0x00AA, 0x0141, 0x00D8, 0x0152, 0x00BA,
  0x00E6, 0x0131, 0x0142, 0x00F8, 0x0153, 0x00DF, 0x00B9, 0x00AC,
  0x00B5, 0x2122, 0x00D0, 0x00BD, 0x00B1, 0x00DE, 0x00BC, 0x00F7,
  0x00A6, 0x00B0, 0x00FE, 0x00BE, 0x00B2, 0x00AE, 0x2212, 0x00F0,
  0x00D7, 0x00B3, 0x00A9, 0x00C1, 0x00C2, 0x00C4, 0x00C0, 0x00C5,
  0x00C3, 0x00E1, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E3, 0x00C9,
  0x00CA, 0x00CB, 0x00C8, 0x00E9, 0x00EA, 0x00EB, 0x00E8, 0x00CD,
  0x00CE, 0x00CF, 0x00CC, 0x00ED, 0x00EE, 0x00EF, 0x00EC, 0x00D3,
  0x00D4, 0x00D6, 0x00D2, 0x00D5, 0x00F3, 0x00F4, 0x00F6, 0x00F2,
  0x00F5, 0x00DA, 0x00DB, 0x00DC, 0x00D9, 0x00FA, 0x00FB, 0x00FC,
  0x00F9, 0x00DD, 0x00FD, 0x00FF, 0x0178, 0x00C7, 0x00E7, 0x00D1,
  0x00F1, 0x0132, 0x0133, 0x0160, 0x0161,
];
