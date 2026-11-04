/// OpenType `GSUB` LookupType 4 (ligature substitution).
library;

import 'dart:typed_data';

import '../bidi/line_breaker.dart';
import '../io/byte_source.dart';
import 'sfnt_parser.dart';

/// Ligature substitutions from a font's `GSUB` table.
class GsubLigatures {
  GsubLigatures._(this._sets);

  final Map<int, List<_Ligature>> _sets;

  static final Expando<GsubLigatures> _cache = Expando<GsubLigatures>();

  /// Cached parse. Empty when the font has no usable ligature lookup.
  static GsubLigatures of(SfntFont font) {
    return _cache[font] ??= parse(font);
  }

  /// parse API.
  static GsubLigatures parse(SfntFont font) {
    if (!font.hasTable('GSUB')) {
      return GsubLigatures._(const <int, List<_Ligature>>{});
    }
    try {
      return GsubLigatures._(_parse(font.tableBytes('GSUB')));
    } on Object {
      return GsubLigatures._(const <int, List<_Ligature>>{});
    }
  }

  /// Parses a raw `GSUB` table (tests and tools that already sliced it out).
  static GsubLigatures parseBytes(Uint8List gsub) {
    try {
      return GsubLigatures._(_parse(gsub));
    } on Object {
      return GsubLigatures._(const <int, List<_Ligature>>{});
    }
  }

  /// True when at least one ligature was read.
  bool get isEmpty => _sets.isEmpty;

  /// Replaces glyph-id sequences, longest match first.
  List<int> apply(List<int> glyphIds) {
    if (_sets.isEmpty || glyphIds.length < 2) {
      return glyphIds;
    }
    final List<int> out = <int>[];
    var i = 0;
    while (i < glyphIds.length) {
      final List<_Ligature>? options = _sets[glyphIds[i]];
      _Ligature? chosen;
      if (options != null) {
        for (final _Ligature lig in options) {
          if (i + lig.components.length >= glyphIds.length) {
            continue;
          }
          var match = true;
          for (int k = 0; k < lig.components.length; k++) {
            if (glyphIds[i + 1 + k] != lig.components[k]) {
              match = false;
              break;
            }
          }
          if (match &&
              (chosen == null ||
                  lig.components.length > chosen.components.length)) {
            chosen = lig;
          }
        }
      }
      if (chosen == null) {
        out.add(glyphIds[i]);
        i++;
      } else {
        out.add(chosen.glyph);
        i += 1 + chosen.components.length;
      }
    }
    return out;
  }

  /// Collapses [glyphs] when a ligature covers them. The first glyph keeps
  /// the ligature id and the summed advance.
  List<ShapedGlyph> rewrite(List<ShapedGlyph> glyphs) {
    if (_sets.isEmpty || glyphs.length < 2) {
      return glyphs;
    }
    final List<int> ids = apply(<int>[for (final ShapedGlyph g in glyphs) g.glyphId]);
    if (ids.length == glyphs.length) {
      return glyphs;
    }
    final List<ShapedGlyph> out = <ShapedGlyph>[];
    var src = 0;
    for (final int id in ids) {
      if (src >= glyphs.length) {
        break;
      }
      if (id == glyphs[src].glyphId) {
        out.add(glyphs[src]);
        src++;
        continue;
      }
      var advance = glyphs[src].advance;
      var end = src + 1;
      while (end < glyphs.length &&
          apply(<int>[
            for (int k = src; k <= end; k++) glyphs[k].glyphId,
          ]).length !=
              1) {
        advance += glyphs[end].advance;
        end++;
      }
      if (end < glyphs.length) {
        advance += glyphs[end].advance;
      }
      out.add(
        ShapedGlyph(
          codePoint: glyphs[src].codePoint,
          glyphId: id,
          advance: advance,
          logicalIndex: glyphs[src].logicalIndex,
          level: glyphs[src].level,
        ),
      );
      src = end + 1;
    }
    while (src < glyphs.length) {
      out.add(glyphs[src]);
      src++;
    }
    return out;
  }

  static Map<int, List<_Ligature>> _parse(Uint8List bytes) {
    final ByteCursor c = ByteCursor(bytes);
    if (c.remaining < 10) {
      return const <int, List<_Ligature>>{};
    }
    c.u16be();
    c.u16be();
    c.u16be();
    c.u16be();
    final int lookupList = c.u16be();
    if (lookupList + 2 > bytes.length) {
      return const <int, List<_Ligature>>{};
    }
    final ByteCursor list = ByteCursor(bytes, offset: lookupList);
    final int count = list.u16be();
    final Map<int, List<_Ligature>> sets = <int, List<_Ligature>>{};
    for (int i = 0; i < count; i++) {
      if (list.remaining < 2) {
        break;
      }
      final int lookupOff = lookupList + list.u16be();
      _readLookup(bytes, lookupOff, sets);
    }
    return sets;
  }

  static void _readLookup(
    Uint8List bytes,
    int offset,
    Map<int, List<_Ligature>> sets,
  ) {
    if (offset + 6 > bytes.length) {
      return;
    }
    final ByteCursor c = ByteCursor(bytes, offset: offset);
    final int type = c.u16be();
    c.u16be();
    final int subCount = c.u16be();
    if (type != 4) {
      return;
    }
    for (int i = 0; i < subCount; i++) {
      if (c.remaining < 2) {
        return;
      }
      _readLigatureSubtable(bytes, offset + c.u16be(), sets);
    }
  }

  static void _readLigatureSubtable(
    Uint8List bytes,
    int offset,
    Map<int, List<_Ligature>> sets,
  ) {
    if (offset + 4 > bytes.length) {
      return;
    }
    final ByteCursor c = ByteCursor(bytes, offset: offset);
    final int format = c.u16be();
    if (format != 1) {
      return;
    }
    final int coverageOff = c.u16be();
    final int setCount = c.u16be();
    final List<int> coverage = _coverage(bytes, offset + coverageOff);
    final List<int> setOffsets = <int>[];
    for (int i = 0; i < setCount && c.remaining >= 2; i++) {
      setOffsets.add(offset + c.u16be());
    }
    final int n = coverage.length < setOffsets.length
        ? coverage.length
        : setOffsets.length;
    for (int i = 0; i < n; i++) {
      sets.putIfAbsent(coverage[i], () => <_Ligature>[]).addAll(
        _ligatureSet(bytes, setOffsets[i]),
      );
    }
  }

  static List<_Ligature> _ligatureSet(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) {
      return const <_Ligature>[];
    }
    final ByteCursor c = ByteCursor(bytes, offset: offset);
    final int count = c.u16be();
    final List<int> offsets = <int>[];
    for (int i = 0; i < count && c.remaining >= 2; i++) {
      offsets.add(offset + c.u16be());
    }
    final List<_Ligature> out = <_Ligature>[];
    for (final int at in offsets) {
      if (at + 4 > bytes.length) {
        continue;
      }
      final ByteCursor lig = ByteCursor(bytes, offset: at);
      final int glyph = lig.u16be();
      final int comp = lig.u16be();
      final List<int> components = <int>[];
      for (int i = 1; i < comp && lig.remaining >= 2; i++) {
        components.add(lig.u16be());
      }
      if (components.length == comp - 1 && comp >= 2) {
        out.add(_Ligature(glyph, components));
      }
    }
    return out;
  }

  static List<int> _coverage(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) {
      return const <int>[];
    }
    final ByteCursor c = ByteCursor(bytes, offset: offset);
    final int format = c.u16be();
    final int count = c.u16be();
    if (format == 1) {
      return <int>[for (int i = 0; i < count && c.remaining >= 2; i++) c.u16be()];
    }
    if (format == 2) {
      final List<int> glyphs = <int>[];
      for (int i = 0; i < count && c.remaining >= 6; i++) {
        final int start = c.u16be();
        final int end = c.u16be();
        c.u16be();
        for (int g = start; g <= end && glyphs.length < 4096; g++) {
          glyphs.add(g);
        }
      }
      return glyphs;
    }
    return const <int>[];
  }
}

class _Ligature {
  const _Ligature(this.glyph, this.components);

  final int glyph;
  final List<int> components;
}
