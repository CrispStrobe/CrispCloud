import 'dart:typed_data';

import '../bidi/arabic_shaping.dart';
import '../bidi/line_breaker.dart';
import '../io/byte_source.dart';
import 'sfnt_parser.dart';

/// OpenType `GPOS` LookupType 4 (MarkToBase). Other lookups are ignored.
class GposMarkToBase {
  GposMarkToBase._(this._tables);

  final List<_MarkToBaseTable> _tables;

  static final Expando<GposMarkToBase> _cache = Expando<GposMarkToBase>();

  /// Cached parse of [font]'s `GPOS` table. Empty when the table is absent.
  static GposMarkToBase of(SfntFont font) {
    return _cache[font] ??= parse(font);
  }

  /// parse API.
  static GposMarkToBase parse(SfntFont font) {
    if (!font.hasTable('GPOS')) {
      return GposMarkToBase._(const <_MarkToBaseTable>[]);
    }
    try {
      return GposMarkToBase._(_parseTables(font.tableBytes('GPOS')));
    } on Object {
      return GposMarkToBase._(const <_MarkToBaseTable>[]);
    }
  }

  /// Font-unit offset of [markGlyphId] relative to [baseGlyphId] origin.
  ({int x, int y})? offset(int baseGlyphId, int markGlyphId) {
    if (baseGlyphId == 0 || markGlyphId == 0) {
      return null;
    }
    for (final _MarkToBaseTable table in _tables) {
      final _MarkRec? mark = table.marks[markGlyphId];
      final List<({int x, int y})?>? base = table.bases[baseGlyphId];
      if (mark == null || base == null) {
        continue;
      }
      if (mark.markClass < 0 || mark.markClass >= base.length) {
        continue;
      }
      final ({int x, int y})? anchor = base[mark.markClass];
      if (anchor == null) {
        continue;
      }
      return (x: anchor.x - mark.x, y: anchor.y - mark.y);
    }
    return null;
  }

  /// Pen offset after the base advance, in points. Falls back to centering.
  static ({double dx, double dy}) attachOrCenter({
    required SfntFont font,
    required int baseGlyphId,
    required int markGlyphId,
    required double baseAdvance,
    required double fontSize,
  }) {
    final ({int x, int y})? units = of(font).offset(baseGlyphId, markGlyphId);
    if (units == null) {
      return (dx: -baseAdvance / 2, dy: 0);
    }
    return (
      dx: font.unitsToPoints(units.x, fontSize) - baseAdvance,
      dy: font.unitsToPoints(units.y, fontSize),
    );
  }

  /// Line-breaker callback using [font] (or [faceFor] per letter).
  static MarkAttachFn fnFor(
    SfntFont font,
    double fontSize, {
    SfntFont? Function(int codePoint)? faceFor,
  }) {
    return (ShapedGlyph base, ShapedGlyph mark) {
      final SfntFont face = faceFor?.call(base.codePoint) ?? font;
      final GposMarkToBase table = of(face);
      for (final int baseGid in _glyphIds(face, base)) {
        for (final int markGid in _glyphIds(face, mark)) {
          final ({int x, int y})? units = table.offset(baseGid, markGid);
          if (units == null) {
            continue;
          }
          return (
            dx: face.unitsToPoints(units.x, fontSize) - base.advance,
            dy: face.unitsToPoints(units.y, fontSize),
          );
        }
      }
      return (dx: -base.advance / 2, dy: 0);
    };
  }

  /// True when at least one MarkToBase subtable was parsed.
  bool get isEmpty => _tables.isEmpty;

  static List<int> _glyphIds(SfntFont face, ShapedGlyph glyph) {
    final List<int> ids = <int>[];
    void add(int gid) {
      if (gid != 0 && !ids.contains(gid)) {
        ids.add(gid);
      }
    }

    add(glyph.glyphId);
    add(face.glyphIdFor(glyph.codePoint));
    final int? nominal = ArabicShaper.nominalOf(glyph.codePoint);
    if (nominal != null) {
      add(face.glyphIdFor(nominal));
    }
    return ids;
  }

  static List<_MarkToBaseTable> _parseTables(Uint8List bytes) {
    final ByteCursor gpos = ByteCursor(bytes);
    if (gpos.remaining < 10) {
      return const <_MarkToBaseTable>[];
    }
    final int major = gpos.u16be();
    final int minor = gpos.u16be();
    if (major != 1) {
      return const <_MarkToBaseTable>[];
    }
    gpos.u16be(); // scriptList
    gpos.u16be(); // featureList
    final int lookupListOff = gpos.u16be();
    if (minor >= 1 && gpos.remaining >= 4) {
      gpos.u32be(); // featureVariations
    }
    if (lookupListOff <= 0 || lookupListOff + 2 > bytes.length) {
      return const <_MarkToBaseTable>[];
    }
    gpos.seek(lookupListOff);
    final int lookupCount = gpos.u16be();
    final List<int> lookupOffs = <int>[
      for (int i = 0; i < lookupCount && gpos.remaining >= 2; i++)
        lookupListOff + gpos.u16be(),
    ];
    final List<_MarkToBaseTable> out = <_MarkToBaseTable>[];
    for (final int lookupAbs in lookupOffs) {
      _collectLookup(bytes, lookupAbs, out);
    }
    return out;
  }

  static void _collectLookup(
    Uint8List bytes,
    int lookupAbs,
    List<_MarkToBaseTable> out,
  ) {
    if (lookupAbs < 0 || lookupAbs + 6 > bytes.length) {
      return;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: lookupAbs);
    final int lookupType = cur.u16be();
    final int lookupFlag = cur.u16be();
    final int subCount = cur.u16be();
    final List<int> subOffs = <int>[
      for (int i = 0; i < subCount && cur.remaining >= 2; i++)
        lookupAbs + cur.u16be(),
    ];
    if ((lookupFlag & 0x0010) != 0 && cur.remaining >= 2) {
      cur.u16be(); // markFilteringSet
    }
    for (final int subAbs in subOffs) {
      if (lookupType == 4) {
        final _MarkToBaseTable? table = _parseMarkToBase(bytes, subAbs);
        if (table != null) {
          out.add(table);
        }
      } else if (lookupType == 9) {
        _collectExtension(bytes, subAbs, out);
      }
    }
  }

  static void _collectExtension(
    Uint8List bytes,
    int subAbs,
    List<_MarkToBaseTable> out,
  ) {
    if (subAbs + 8 > bytes.length) {
      return;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: subAbs);
    final int format = cur.u16be();
    if (format != 1) {
      return;
    }
    final int extType = cur.u16be();
    final int extOff = cur.u32be();
    if (extType != 4) {
      return;
    }
    final _MarkToBaseTable? table = _parseMarkToBase(bytes, subAbs + extOff);
    if (table != null) {
      out.add(table);
    }
  }

  static _MarkToBaseTable? _parseMarkToBase(Uint8List bytes, int subAbs) {
    if (subAbs < 0 || subAbs + 12 > bytes.length) {
      return null;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: subAbs);
    final int format = cur.u16be();
    if (format != 1) {
      return null;
    }
    final int markCovOff = cur.u16be();
    final int baseCovOff = cur.u16be();
    final int markClassCount = cur.u16be();
    final int markArrayOff = cur.u16be();
    final int baseArrayOff = cur.u16be();
    if (markClassCount <= 0 || markClassCount > 64) {
      return null;
    }
    final Map<int, int> markCoverage = _coverage(bytes, subAbs + markCovOff);
    final Map<int, int> baseCoverage = _coverage(bytes, subAbs + baseCovOff);
    if (markCoverage.isEmpty || baseCoverage.isEmpty) {
      return null;
    }
    final Map<int, _MarkRec> marks = _markArray(
      bytes,
      subAbs + markArrayOff,
      markCoverage,
    );
    final Map<int, List<({int x, int y})?>> bases = _baseArray(
      bytes,
      subAbs + baseArrayOff,
      baseCoverage,
      markClassCount,
    );
    if (marks.isEmpty || bases.isEmpty) {
      return null;
    }
    return _MarkToBaseTable(marks: marks, bases: bases);
  }

  static Map<int, int> _coverage(Uint8List bytes, int abs) {
    final Map<int, int> map = <int, int>{};
    if (abs < 0 || abs + 4 > bytes.length) {
      return map;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: abs);
    final int format = cur.u16be();
    if (format == 1) {
      final int count = cur.u16be();
      for (int i = 0; i < count && cur.remaining >= 2; i++) {
        map[cur.u16be()] = i;
      }
      return map;
    }
    if (format == 2) {
      final int rangeCount = cur.u16be();
      for (int r = 0; r < rangeCount && cur.remaining >= 6; r++) {
        final int start = cur.u16be();
        final int end = cur.u16be();
        var index = cur.u16be();
        if (end < start) {
          continue;
        }
        for (int g = start; g <= end; g++) {
          map[g] = index++;
        }
      }
    }
    return map;
  }

  static Map<int, _MarkRec> _markArray(
    Uint8List bytes,
    int abs,
    Map<int, int> coverage,
  ) {
    final Map<int, _MarkRec> out = <int, _MarkRec>{};
    if (abs < 0 || abs + 2 > bytes.length) {
      return out;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: abs);
    final int count = cur.u16be();
    final List<_MarkRec?> byIndex = List<_MarkRec?>.filled(count, null);
    for (int i = 0; i < count && cur.remaining >= 4; i++) {
      final int markClass = cur.u16be();
      final int anchorOff = cur.u16be();
      final ({int x, int y})? anchor = anchorOff == 0
          ? null
          : _anchor(bytes, abs + anchorOff);
      if (anchor != null) {
        byIndex[i] = _MarkRec(
          markClass: markClass,
          x: anchor.x,
          y: anchor.y,
        );
      }
    }
    for (final MapEntry<int, int> e in coverage.entries) {
      if (e.value >= 0 && e.value < byIndex.length) {
        final _MarkRec? rec = byIndex[e.value];
        if (rec != null) {
          out[e.key] = rec;
        }
      }
    }
    return out;
  }

  static Map<int, List<({int x, int y})?>> _baseArray(
    Uint8List bytes,
    int abs,
    Map<int, int> coverage,
    int markClassCount,
  ) {
    final Map<int, List<({int x, int y})?>> out =
        <int, List<({int x, int y})?>>{};
    if (abs < 0 || abs + 2 > bytes.length) {
      return out;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: abs);
    final int count = cur.u16be();
    final List<List<({int x, int y})?>?> byIndex =
        List<List<({int x, int y})?>?>.filled(count, null);
    for (int i = 0; i < count; i++) {
      if (cur.remaining < markClassCount * 2) {
        break;
      }
      final List<({int x, int y})?> anchors = <({int x, int y})?>[];
      for (int c = 0; c < markClassCount; c++) {
        final int off = cur.u16be();
        anchors.add(off == 0 ? null : _anchor(bytes, abs + off));
      }
      byIndex[i] = anchors;
    }
    for (final MapEntry<int, int> e in coverage.entries) {
      if (e.value >= 0 && e.value < byIndex.length) {
        final List<({int x, int y})?>? rec = byIndex[e.value];
        if (rec != null) {
          out[e.key] = rec;
        }
      }
    }
    return out;
  }

  static ({int x, int y})? _anchor(Uint8List bytes, int abs) {
    if (abs < 0 || abs + 6 > bytes.length) {
      return null;
    }
    final ByteCursor cur = ByteCursor(bytes, offset: abs);
    final int format = cur.u16be();
    if (format < 1 || format > 3) {
      return null;
    }
    final int x = cur.i16be();
    final int y = cur.i16be();
    return (x: x, y: y);
  }
}

class _MarkToBaseTable {
  _MarkToBaseTable({required this.marks, required this.bases});

  final Map<int, _MarkRec> marks;
  final Map<int, List<({int x, int y})?>> bases;
}

class _MarkRec {
  const _MarkRec({required this.markClass, required this.x, required this.y});

  final int markClass;
  final int x;
  final int y;
}
