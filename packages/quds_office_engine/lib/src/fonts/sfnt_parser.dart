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
    try {
      return _parse(bytes);
    } on RangeError {
      throw const SfntException(
        'SFNT table data is truncated or out of bounds',
      );
    }
  }

  static SfntFont _parse(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const SfntException('SFNT header is truncated');
    }
    final ByteCursor header = ByteCursor(bytes);
    header.u32be(); // sfntVersion
    final int numTables = header.u16be();
    header.skip(6);
    if (numTables > header.remaining ~/ 16) {
      throw const SfntException('SFNT table directory is truncated');
    }
    final Map<String, SfntTableRecord> tables = <String, SfntTableRecord>{};
    for (int i = 0; i < numTables; i++) {
      final String tag = String.fromCharCodes(header.bytes(4));
      final int checksum = header.u32be();
      final int offset = header.u32be();
      final int length = header.u32be();
      if (offset > bytes.length || length > bytes.length - offset) {
        throw SfntException('SFNT table $tag is outside the font');
      }
      if (tables.containsKey(tag)) {
        throw SfntException('Duplicate SFNT table $tag');
      }
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
      cmap: CmapTable.parse(table('cmap'), numGlyphs: numGlyphs),
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

typedef _CmapGroup = ({int start, int end, int glyph});

/// Character-to-glyph map supporting cmap formats 0, 4 and 12.
class CmapTable {
  /// CmapTable API.
  CmapTable(this._map) : _groups = const <_CmapGroup>[];

  CmapTable._format12(this._groups) : _map = const <int, int>{};

  final Map<int, int> _map;
  final List<_CmapGroup> _groups;

  /// Selects one supported encoding and validates every mapping it contains.
  ///
  /// [numGlyphs] is the font's `maxp.numGlyphs`. Without a font directory,
  /// glyph IDs are still restricted to the unsigned 16-bit SFNT range.
  /// Unicode encodings take precedence over legacy encoded character codes;
  /// full Unicode coverage takes precedence over BMP coverage. Subtables are
  /// exclusive, so their mappings are never combined or ranked by population.
  factory CmapTable.parse(ByteCursor cmap, {int numGlyphs = 0x10000}) {
    if (numGlyphs < 1 || numGlyphs > 0x10000) {
      throw const SfntException('Invalid cmap glyph count');
    }
    if (cmap.offset < 0 || cmap.remaining < 4) {
      throw const SfntException('cmap header is truncated');
    }
    final data = ByteData.sublistView(cmap.buffer, cmap.offset);
    if (data.getUint16(0) != 0) {
      throw const SfntException('Unsupported cmap table version');
    }
    final numTables = data.getUint16(2);
    final directoryEnd = 4 + numTables * 8;
    if (directoryEnd > data.lengthInBytes) {
      throw const SfntException('cmap encoding directory is truncated');
    }
    final tables = <({int score, int offset, int format, bool unicode})>[];
    for (int i = 0; i < numTables; i++) {
      final record = 4 + i * 8;
      final platform = data.getUint16(record);
      final encoding = data.getUint16(record + 2);
      final offset = data.getUint32(record + 4);
      if (offset < directoryEnd || offset > data.lengthInBytes - 2) {
        throw const SfntException('cmap subtable offset is outside its data');
      }
      final format = data.getUint16(offset);
      if (format != 0 && format != 4 && format != 12) {
        continue;
      }
      // Unicode variation sequences and last-resort coverage have different
      // formats and cannot serve as the ordinary character-to-glyph map.
      if (platform == 0 && encoding > 4) {
        continue;
      }
      tables.add((
        score: _score(platform, encoding, format),
        offset: offset,
        format: format,
        unicode: _isUnicode(platform, encoding),
      ));
    }
    tables.sort(
      (a, b) => b.score != a.score ? b.score - a.score : a.offset - b.offset,
    );
    if (tables.isEmpty) {
      return CmapTable(<int, int>{0: 0});
    }
    final selected = tables.first;
    final offset = selected.offset;
    final format = selected.format;
    final headerLength = format == 12 ? 16 : 6;
    if (headerLength > data.lengthInBytes - offset) {
      throw SfntException('cmap format $format header is truncated');
    }
    final length = format == 12
        ? data.getUint32(offset + 4)
        : data.getUint16(offset + 2);
    if (length < headerLength || length > data.lengthInBytes - offset) {
      throw SfntException('Invalid cmap format $format length');
    }
    final subtable = ByteData.sublistView(
      cmap.buffer,
      cmap.offset + offset,
      cmap.offset + offset + length,
    );
    if (format == 12) {
      return _parseFormat12(subtable, numGlyphs);
    }
    if (format == 4) {
      return _parseFormat4(subtable, numGlyphs, unicode: selected.unicode);
    }
    final map = <int, int>{};
    if (format == 0) {
      if (length != 262) {
        throw const SfntException('Invalid cmap format 0 glyph-array length');
      }
      for (int i = 0; i < 256; i++) {
        final glyph = subtable.getUint8(6 + i);
        _checkGlyph(glyph, numGlyphs);
        map[i] = glyph;
      }
    }
    return CmapTable(map);
  }

  /// glyphId API.
  int glyphId(int codePoint) {
    if (_groups.isEmpty) {
      return _map[codePoint] ?? 0;
    }
    var lo = 0;
    var hi = _groups.length - 1;
    while (lo <= hi) {
      final middle = lo + ((hi - lo) ~/ 2);
      final group = _groups[middle];
      if (codePoint < group.start) {
        hi = middle - 1;
      } else if (codePoint > group.end) {
        lo = middle + 1;
      } else {
        return group.glyph + codePoint - group.start;
      }
    }
    return 0;
  }

  /// mappings API.
  Iterable<MapEntry<int, int>> get mappings sync* {
    if (_groups.isEmpty) {
      yield* _map.entries;
      return;
    }
    if (_groups.first.start != 0) {
      yield const MapEntry(0, 0);
    }
    for (final group in _groups) {
      for (var code = group.start; code <= group.end; code++) {
        yield MapEntry(code, group.glyph + code - group.start);
      }
    }
  }

  static int _score(int platform, int encoding, int format) {
    if (_isUnicode(platform, encoding)) {
      final coverage = format == 12 ? 200 : (format == 4 ? 100 : 0);
      return 1000 + coverage + (platform == 3 ? 10 : 0) + encoding;
    }
    if (platform == 3 && encoding == 0) {
      return 20;
    }
    if (platform == 1) {
      return 10;
    }
    return 0;
  }

  static bool _isUnicode(int platform, int encoding) =>
      platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));

  static CmapTable _parseFormat4(
    ByteData data,
    int numGlyphs, {
    required bool unicode,
  }) {
    final length = data.lengthInBytes;
    if (length < 24 || length.isOdd) {
      throw const SfntException('Invalid cmap format 4 segment-array length');
    }
    final segCountX2 = data.getUint16(6);
    if (segCountX2 == 0 || segCountX2.isOdd) {
      throw const SfntException('Invalid cmap format 4 segment count');
    }
    final segCount = segCountX2 ~/ 2;
    final glyphArrayStart = 16 + segCount * 8;
    if (glyphArrayStart > length) {
      throw const SfntException('cmap format 4 segment arrays are truncated');
    }
    if (data.getUint16(14 + segCount * 2) != 0) {
      throw const SfntException('Invalid cmap format 4 reserved padding');
    }
    final startBase = 16 + segCount * 2;
    final deltaBase = 16 + segCount * 4;
    final rangeBase = 16 + segCount * 6;
    final map = <int, int>{0: 0};
    var previousEnd = -1;
    for (int i = 0; i < segCount; i++) {
      final startCode = data.getUint16(startBase + i * 2);
      final endCode = data.getUint16(14 + i * 2);
      final delta = data.getInt16(deltaBase + i * 2);
      final rangeOffset = data.getUint16(rangeBase + i * 2);
      if (startCode > endCode || startCode <= previousEnd) {
        throw const SfntException(
          'cmap format 4 segments overlap or are unsorted',
        );
      }
      if (i == segCount - 1 && (startCode != 0xffff || endCode != 0xffff)) {
        throw const SfntException('cmap format 4 terminal segment is missing');
      }
      previousEnd = endCode;
      final glyphStart = rangeBase + i * 2 + rangeOffset;
      if (rangeOffset != 0 &&
          (rangeOffset.isOdd ||
              glyphStart < glyphArrayStart ||
              glyphStart + (endCode - startCode + 1) * 2 > length)) {
        throw const SfntException(
          'cmap format 4 glyph pointer is out of bounds',
        );
      }
      for (int c = startCode; c <= endCode; c++) {
        int glyph;
        if (rangeOffset == 0) {
          glyph = (c + delta) & 0xFFFF;
        } else {
          final glyphIndex = data.getUint16(glyphStart + (c - startCode) * 2);
          glyph = glyphIndex == 0 ? 0 : (glyphIndex + delta) & 0xFFFF;
        }
        _checkGlyph(glyph, numGlyphs);
        if (unicode && c >= 0xd800 && c <= 0xdfff) {
          if (glyph != 0) {
            throw const SfntException('cmap format 4 maps a Unicode surrogate');
          }
          continue;
        }
        if (c != 0xFFFF) {
          map[c] = glyph;
        }
      }
    }
    return CmapTable(map);
  }

  static CmapTable _parseFormat12(ByteData data, int numGlyphs) {
    if (data.getUint16(2) != 0) {
      throw const SfntException('Invalid cmap format 12 reserved field');
    }
    final nGroups = data.getUint32(12);
    if (nGroups != (data.lengthInBytes - 16) ~/ 12 ||
        (data.lengthInBytes - 16) % 12 != 0) {
      throw const SfntException(
        'cmap format 12 group array has invalid length',
      );
    }
    final groups = <_CmapGroup>[];
    var previousEnd = -1;
    for (int i = 0; i < nGroups; i++) {
      final offset = 16 + i * 12;
      final start = data.getUint32(offset);
      final end = data.getUint32(offset + 4);
      final glyph = data.getUint32(offset + 8);
      if (start > end || start <= previousEnd || end > 0x10ffff) {
        throw const SfntException('Invalid or unordered cmap format 12 range');
      }
      if (start <= 0xdfff && end >= 0xd800) {
        throw const SfntException('cmap format 12 range includes surrogates');
      }
      _checkGlyph(glyph, numGlyphs);
      if (end - start > numGlyphs - 1 - glyph) {
        throw const SfntException('cmap format 12 glyph range is outside maxp');
      }
      groups.add((start: start, end: end, glyph: glyph));
      previousEnd = end;
    }
    // Keep validated ranges compact. A small table must not allocate one map
    // entry per encoded character, even when many scalars alias glyph ranges.
    return groups.isEmpty
        ? CmapTable(<int, int>{0: 0})
        : CmapTable._format12(groups);
  }

  static void _checkGlyph(int glyph, int numGlyphs) {
    if (glyph >= numGlyphs) {
      throw const SfntException('cmap glyph ID is outside maxp');
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
