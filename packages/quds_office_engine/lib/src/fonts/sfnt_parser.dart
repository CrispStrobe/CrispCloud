import 'dart:typed_data';

import '../io/byte_source.dart';

/// Parsed TrueType / OpenType SFNT font.
class SfntFont {
  /// SfntFont API.
  SfntFont({
    required this.bytes,
    required this.tables,
    required this.unitsPerEm,
    required this.indexToLocFormat,
    required this.numGlyphs,
    required this.numberOfHMetrics,
    required this.ascender,
    required this.descender,
    required this.lineGap,
    required this.capHeight,
    required this.winAscent,
    required this.winDescent,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.advanceWidths,
    required this.leftSideBearings,
    required this.glyphOffsets,
    required this.cmap,
    this.familyName = '',
  });

  /// bytes API.
  final Uint8List bytes;

  /// tables API.
  final Map<String, SfntTableRecord> tables;

  /// unitsPerEm API.
  final int unitsPerEm;

  /// indexToLocFormat API.
  final int indexToLocFormat;

  /// numGlyphs API.
  final int numGlyphs;

  /// numberOfHMetrics API.
  final int numberOfHMetrics;

  /// ascender API.
  final int ascender;

  /// descender API.
  final int descender;

  /// lineGap API.
  final int lineGap;

  /// capHeight API.
  final int capHeight;

  /// OS/2 `usWinAscent` (positive). Prefer for line boxes that must not clip.
  final int winAscent;

  /// OS/2 `usWinDescent` (positive extent below the baseline).
  final int winDescent;

  /// xMin API.
  final int xMin;

  /// yMin API.
  final int yMin;

  /// xMax API.
  final int xMax;

  /// yMax API.
  final int yMax;

  /// advanceWidths API.
  final List<int> advanceWidths;

  /// leftSideBearings API.
  final List<int> leftSideBearings;

  /// glyphOffsets API.
  final List<int> glyphOffsets;

  /// cmap API.
  final CmapTable cmap;

  /// familyName API.
  final String familyName;

  /// parse API.
  factory SfntFont.parse(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const SfntException('SFNT header is truncated');
    }
    final ByteCursor header = ByteCursor(bytes);
    header.u32be(); // sfntVersion
    final int numTables = header.u16be();
    header.skip(6);
    final Map<String, SfntTableRecord> tables = <String, SfntTableRecord>{};
    for (int i = 0; i < numTables; i++) {
      final String tag = String.fromCharCodes(header.bytes(4));
      final int checksum = header.u32be();
      final int offset = header.u32be();
      final int length = header.u32be();
      tables[tag] = SfntTableRecord(
        tag: tag,
        checksum: checksum,
        offset: offset,
        length: length,
      );
    }

    ByteCursor table(String tag) {
      final SfntTableRecord? rec = tables[tag];
      if (rec == null) {
        throw SfntException('Missing required SFNT table $tag');
      }
      return ByteCursor.view(MemoryByteSource(bytes), rec.offset, rec.length);
    }

    final ByteCursor head = table('head');
    head.skip(18);
    final int unitsPerEm = head.u16be();
    head.skip(16);
    final int xMin = head.i16be();
    final int yMin = head.i16be();
    final int xMax = head.i16be();
    final int yMax = head.i16be();
    head.skip(6);
    final int indexToLocFormat = head.i16be();

    final ByteCursor hhea = table('hhea');
    hhea.skip(4);
    final int ascender = hhea.i16be();
    final int descender = hhea.i16be();
    final int lineGap = hhea.i16be();
    hhea.skip(24);
    final int numberOfHMetrics = hhea.u16be();

    final ByteCursor maxp = table('maxp');
    maxp.skip(4);
    final int numGlyphs = maxp.u16be();

    int capHeight = ascender;
    var winAscent = ascender < 0 ? -ascender : ascender;
    var winDescent = descender < 0 ? -descender : descender;
    final SfntTableRecord? os2rec = tables['OS/2'];
    if (os2rec != null && os2rec.length >= 78) {
      final ByteCursor os2 = table('OS/2');
      os2.skip(68);
      final int typoAscender = os2.i16be();
      if (typoAscender != 0) {
        capHeight = typoAscender;
      }
      os2.seek(74);
      final int usWinAscent = os2.u16be();
      final int usWinDescent = os2.u16be();
      if (usWinAscent > 0) {
        winAscent = usWinAscent;
      }
      if (usWinDescent > 0) {
        winDescent = usWinDescent;
      }
      if (os2rec.length >= 90) {
        os2.seek(88);
        final int sCap = os2.i16be();
        if (sCap != 0) {
          capHeight = sCap;
        }
      }
    }

    final List<int> advances = List<int>.filled(numGlyphs, 0);
    final List<int> lsbs = List<int>.filled(numGlyphs, 0);
    final ByteCursor hmtx = table('hmtx');
    int lastAdvance = 0;
    for (int i = 0; i < numberOfHMetrics && i < numGlyphs; i++) {
      lastAdvance = hmtx.u16be();
      advances[i] = lastAdvance;
      lsbs[i] = hmtx.i16be();
    }
    for (int i = numberOfHMetrics; i < numGlyphs; i++) {
      advances[i] = lastAdvance;
      lsbs[i] = hmtx.i16be();
    }

    final List<int> loca = <int>[];
    if (tables.containsKey('loca') && tables.containsKey('glyf')) {
      final ByteCursor locaCur = table('loca');
      final int count = numGlyphs + 1;
      if (indexToLocFormat == 0) {
        for (int i = 0; i < count; i++) {
          loca.add(locaCur.u16be() * 2);
        }
      } else {
        for (int i = 0; i < count; i++) {
          loca.add(locaCur.u32be());
        }
      }
    } else {
      for (int i = 0; i <= numGlyphs; i++) {
        loca.add(0);
      }
    }

    String family = '';
    if (tables.containsKey('name')) {
      family = _readFamilyName(table('name'));
    }

    return SfntFont(
      bytes: bytes,
      tables: tables,
      unitsPerEm: unitsPerEm,
      indexToLocFormat: indexToLocFormat,
      numGlyphs: numGlyphs,
      numberOfHMetrics: numberOfHMetrics,
      ascender: ascender,
      descender: descender,
      lineGap: lineGap,
      capHeight: capHeight,
      winAscent: winAscent,
      winDescent: winDescent,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      advanceWidths: advances,
      leftSideBearings: lsbs,
      glyphOffsets: loca,
      cmap: CmapTable.parse(table('cmap')),
      familyName: family,
    );
  }

  /// tableBytes API.
  Uint8List tableBytes(String tag) {
    final SfntTableRecord? rec = tables[tag];
    if (rec == null) {
      throw SfntException('Missing SFNT table $tag');
    }
    return Uint8List.sublistView(bytes, rec.offset, rec.offset + rec.length);
  }

  /// hasTable API.
  bool hasTable(String tag) => tables.containsKey(tag);

  /// glyphIdFor API.
  int glyphIdFor(int codePoint) => cmap.glyphId(codePoint);

  /// advanceWidth API.
  int advanceWidth(int glyphId) {
    if (glyphId < 0 || glyphId >= advanceWidths.length) {
      return 0;
    }
    return advanceWidths[glyphId];
  }

  /// Converts font units to points at [fontSizePoints].
  double unitsToPoints(int units, double fontSizePoints) {
    if (unitsPerEm == 0) {
      return 0;
    }
    return units * fontSizePoints / unitsPerEm;
  }

  static String _readFamilyName(ByteCursor name) {
    name.u16be(); // format
    final int count = name.u16be();
    final int stringOffset = name.u16be();
    String? unicode;
    String? mac;
    for (int i = 0; i < count; i++) {
      final int platform = name.u16be();
      final int encoding = name.u16be();
      name.u16be(); // language
      final int nameId = name.u16be();
      final int length = name.u16be();
      final int offset = name.u16be();
      if (nameId != 1 && nameId != 16) {
        continue;
      }
      final int abs = name.offset;
      name.seek(stringOffset + offset);
      final Uint8List raw = name.bytes(length);
      name.seek(abs);
      if (platform == 3 && (encoding == 1 || encoding == 10)) {
        unicode = _utf16be(raw);
      } else if (platform == 1) {
        mac = String.fromCharCodes(raw);
      }
    }
    return unicode ?? mac ?? '';
  }

  static String _utf16be(Uint8List raw) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i + 1 < raw.length; i += 2) {
      buffer.writeCharCode((raw[i] << 8) | raw[i + 1]);
    }
    return buffer.toString();
  }
}

/// Table directory entry.
class SfntTableRecord {
  /// SfntTableRecord API.
  const SfntTableRecord({
    required this.tag,
    required this.checksum,
    required this.offset,
    required this.length,
  });

  /// tag API.
  final String tag;

  /// checksum API.
  final int checksum;

  /// offset API.
  final int offset;

  /// length API.
  final int length;
}

/// Character-to-glyph map supporting cmap format 4 and 12.
class CmapTable {
  /// CmapTable API.
  CmapTable(this._map);

  final Map<int, int> _map;

  /// parse API.
  factory CmapTable.parse(ByteCursor cmap) {
    cmap.u16be(); // version
    final int numTables = cmap.u16be();
    final List<({int score, int offset})> tables =
        <({int score, int offset})>[];
    for (int i = 0; i < numTables; i++) {
      final int platform = cmap.u16be();
      final int encoding = cmap.u16be();
      final int offset = cmap.u32be();
      tables.add((score: _score(platform, encoding), offset: offset));
    }
    tables.sort(
      (a, b) => b.score != a.score ? b.score - a.score : a.offset - b.offset,
    );
    Map<int, int> best = <int, int>{0: 0};
    var bestHits = -1;
    for (final ({int score, int offset}) table in tables) {
      cmap.seek(table.offset);
      final Map<int, int> map = <int, int>{};
      if (!_parseEncoding(cmap, map)) {
        continue;
      }
      map.putIfAbsent(0, () => 0);
      final int hits = map.values.where((int gid) => gid != 0).length;
      if (hits > bestHits) {
        best = map;
        bestHits = hits;
      }
    }
    return CmapTable(best);
  }

  static bool _parseEncoding(ByteCursor cmap, Map<int, int> map) {
    final int format = cmap.u16be();
    if (format == 4) {
      _parseFormat4(cmap, map);
      return true;
    }
    if (format == 12) {
      cmap.skip(2);
      cmap.u32be();
      cmap.u32be();
      _parseFormat12(cmap, map);
      return true;
    }
    if (format == 0) {
      cmap.u16be();
      cmap.u16be();
      for (int i = 0; i < 256; i++) {
        map[i] = cmap.u8();
      }
      return true;
    }
    return false;
  }

  /// glyphId API.
  int glyphId(int codePoint) => _map[codePoint] ?? 0;

  /// mappings API.
  Iterable<MapEntry<int, int>> get mappings => _map.entries;

  static int _score(int platform, int encoding) {
    if (platform == 3 && encoding == 10) {
      return 40;
    }
    if (platform == 0 && encoding == 4) {
      return 35;
    }
    if (platform == 3 && encoding == 1) {
      return 30;
    }
    if (platform == 0) {
      return 20;
    }
    if (platform == 1) {
      return 10;
    }
    return 0;
  }

  static void _parseFormat4(ByteCursor cmap, Map<int, int> map) {
    final int length = cmap.u16be();
    final int start = cmap.offset - 4;
    cmap.u16be(); // language
    final int segCountX2 = cmap.u16be();
    final int segCount = segCountX2 ~/ 2;
    cmap.skip(6);
    final List<int> endCodes = <int>[
      for (int i = 0; i < segCount; i++) cmap.u16be(),
    ];
    cmap.u16be(); // reserved
    final List<int> startCodes = <int>[
      for (int i = 0; i < segCount; i++) cmap.u16be(),
    ];
    final List<int> idDeltas = <int>[
      for (int i = 0; i < segCount; i++) cmap.i16be(),
    ];
    final int rangeOffsetBase = cmap.offset;
    final List<int> idRangeOffsets = <int>[
      for (int i = 0; i < segCount; i++) cmap.u16be(),
    ];
    for (int i = 0; i < segCount; i++) {
      final int startCode = startCodes[i];
      final int endCode = endCodes[i];
      final int delta = idDeltas[i];
      final int rangeOffset = idRangeOffsets[i];
      for (int c = startCode; c <= endCode; c++) {
        int glyph;
        if (rangeOffset == 0) {
          glyph = (c + delta) & 0xFFFF;
        } else {
          final int offset =
              rangeOffsetBase + i * 2 + rangeOffset + (c - startCode) * 2;
          if (offset + 2 > start + length) {
            glyph = 0;
          } else {
            final int saved = cmap.offset;
            cmap.seek(offset);
            final int glyphIndex = cmap.u16be();
            cmap.seek(saved);
            glyph = glyphIndex == 0 ? 0 : (glyphIndex + delta) & 0xFFFF;
          }
        }
        if (c != 0xFFFF) {
          map[c] = glyph;
        }
      }
    }
  }

  static void _parseFormat12(ByteCursor cmap, Map<int, int> map) {
    final int nGroups = cmap.u32be();
    for (int i = 0; i < nGroups; i++) {
      final int startChar = cmap.u32be();
      final int endChar = cmap.u32be();
      int glyph = cmap.u32be();
      for (int c = startChar; c <= endChar; c++) {
        map[c] = glyph++;
      }
    }
  }
}

/// Thrown when an SFNT font is corrupt or missing required tables.
class SfntException implements Exception {
  /// SfntException API.
  const SfntException(this.message);

  /// message API.
  final String message;

  @override
  /// toString API.
  String toString() => 'SfntException: $message';
}
