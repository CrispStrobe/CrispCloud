/// Unicode bidirectional classes (UAX #9).
enum BidiClass {
  l,
  r,
  al,
  en,
  es,
  et,
  an,
  cs,
  nsm,
  bn,
  b,
  s,
  ws,
  on,
  lre,
  rle,
  lro,
  rlo,
  pdf,
  lri,
  rli,
  fsi,
  pdi,
}

/// One directional run after UAX #9 reordering.
class BidiRun {
  /// BidiRun API.
  BidiRun({
    required this.text,
    required this.level,
    required this.logicalStart,
    required this.logicalEnd,
    required this.visualStart,
  });

  /// text API.
  final String text;

  /// level API.
  final int level;

  /// logicalStart API.
  final int logicalStart;

  /// logicalEnd API.
  final int logicalEnd;

  /// visualStart API.
  final int visualStart;

  /// isRtl API.
  bool get isRtl => level.isOdd;
}

/// Result of running the Unicode Bidirectional Algorithm on a paragraph.
class BidiParagraph {
  /// BidiParagraph API.
  BidiParagraph({
    required this.baseLevel,
    required this.levels,
    required this.visualToLogical,
    required this.logicalToVisual,
    required this.runs,
    required this.original,
  });

  /// baseLevel API.
  final int baseLevel;

  /// levels API.
  final List<int> levels;

  /// visualToLogical API.
  final List<int> visualToLogical;

  /// logicalToVisual API.
  final List<int> logicalToVisual;

  /// runs API.
  final List<BidiRun> runs;

  /// original API.
  final String original;

  /// isRtl API.
  bool get isRtl => baseLevel.isOdd;
}

/// Full UAX #9 implementation for a single paragraph.
abstract final class Uax9Bidi {
  /// classify API.
  static BidiClass classify(int codePoint) => _classify(codePoint);

  /// Directional marks and embeds that must not paint (no .notdef boxes).
  ///
  /// `intl` DateFormat / BidiFormatter wrap LTR dates with LRE/PDF or LRI/PDI.
  static bool isInvisibleFormat(int codePoint) {
    return codePoint == 0x061C ||
        codePoint == 0x200B ||
        codePoint == 0x200C ||
        codePoint == 0x200D ||
        codePoint == 0x200E ||
        codePoint == 0x200F ||
        (codePoint >= 0x202A && codePoint <= 0x202E) ||
        (codePoint >= 0x2060 && codePoint <= 0x2064) ||
        (codePoint >= 0x2066 && codePoint <= 0x206F) ||
        codePoint == 0xFEFF;
  }

  /// reorder API.
  static BidiParagraph reorder(String text, {int? baseLevel}) {
    if (text.isEmpty) {
      return BidiParagraph(
        baseLevel: baseLevel ?? 0,
        levels: const <int>[],
        visualToLogical: const <int>[],
        logicalToVisual: const <int>[],
        runs: const <BidiRun>[],
        original: text,
      );
    }
    final List<int> cps = text.runes.toList();
    final List<BidiClass> types = cps.map(_classify).toList();
    final int paragraphLevel = baseLevel ?? _paragraphLevel(types);
    final List<int> levels = List<int>.filled(cps.length, paragraphLevel);
    final List<BidiClass> working = List<BidiClass>.from(types);
    _resolveExplicit(working, levels, paragraphLevel);
    _resolveWeak(working);
    _resolveNeutrals(working, levels, paragraphLevel);
    _resolveImplicit(working, levels);
    _resetWhitespace(types, levels, paragraphLevel);
    final List<int> visual = visualOrder(levels);
    final List<int> logicalToVisual = List<int>.filled(cps.length, 0);
    for (int v = 0; v < visual.length; v++) {
      logicalToVisual[visual[v]] = v;
    }
    return BidiParagraph(
      baseLevel: paragraphLevel,
      levels: levels,
      visualToLogical: visual,
      logicalToVisual: logicalToVisual,
      runs: _runs(text, cps, levels, visual),
      original: text,
    );
  }

  static int _paragraphLevel(List<BidiClass> types) {
    for (final BidiClass t in types) {
      if (t == BidiClass.l) {
        return 0;
      }
      if (t == BidiClass.r || t == BidiClass.al) {
        return 1;
      }
    }
    return 0;
  }

  static void _resolveExplicit(
    List<BidiClass> types,
    List<int> levels,
    int paragraphLevel,
  ) {
    final List<_Embed> stack = <_Embed>[_Embed(paragraphLevel, false, false)];
    var overflowIsolate = 0;
    var overflowEmbed = 0;
    var validIsolate = 0;
    for (int i = 0; i < types.length; i++) {
      final BidiClass t = types[i];
      switch (t) {
        case BidiClass.rle:
        case BidiClass.lre:
        case BidiClass.rlo:
        case BidiClass.lro:
        case BidiClass.lri:
        case BidiClass.rli:
        case BidiClass.fsi:
          final bool rtl =
              t == BidiClass.rle ||
              t == BidiClass.rlo ||
              t == BidiClass.rli ||
              (t == BidiClass.fsi && _fsiRtl(types, i));
          final int newLevel = rtl
              ? (stack.last.level + 1) | 1
              : (stack.last.level + 2) & ~1;
          final bool isolate =
              t == BidiClass.lri || t == BidiClass.rli || t == BidiClass.fsi;
          if (newLevel <= 125 && overflowIsolate == 0 && overflowEmbed == 0) {
            stack.add(
              _Embed(
                newLevel,
                t == BidiClass.rlo || t == BidiClass.lro,
                isolate,
              ),
            );
            if (isolate) {
              validIsolate++;
            }
            levels[i] = stack[stack.length - 2].level;
          } else if (isolate) {
            overflowIsolate++;
            levels[i] = stack.last.level;
          } else {
            if (overflowIsolate == 0) {
              overflowEmbed++;
            }
            levels[i] = stack.last.level;
          }
          types[i] = BidiClass.bn;
        case BidiClass.pdf:
          levels[i] = stack.last.level;
          types[i] = BidiClass.bn;
          if (overflowIsolate > 0) {
            break;
          }
          if (overflowEmbed > 0) {
            overflowEmbed--;
          } else if (!stack.last.isolate && stack.length >= 2) {
            stack.removeLast();
          }
        case BidiClass.pdi:
          if (overflowIsolate > 0) {
            overflowIsolate--;
          } else if (validIsolate > 0) {
            overflowEmbed = 0;
            while (stack.isNotEmpty && !stack.last.isolate) {
              stack.removeLast();
            }
            if (stack.isNotEmpty) {
              stack.removeLast();
            }
            validIsolate--;
          }
          levels[i] = stack.last.level;
          types[i] = BidiClass.bn;
        case BidiClass.b:
          levels[i] = paragraphLevel;
        default:
          levels[i] = stack.last.level;
          if (stack.last.override) {
            types[i] = stack.last.level.isOdd ? BidiClass.r : BidiClass.l;
          }
      }
    }
  }

  static bool _fsiRtl(List<BidiClass> types, int start) {
    var depth = 1;
    for (int i = start + 1; i < types.length; i++) {
      final BidiClass t = types[i];
      if (t == BidiClass.lri || t == BidiClass.rli || t == BidiClass.fsi) {
        depth++;
      } else if (t == BidiClass.pdi) {
        depth--;
        if (depth == 0) {
          break;
        }
      } else if (depth == 1) {
        if (t == BidiClass.l) {
          return false;
        }
        if (t == BidiClass.r || t == BidiClass.al) {
          return true;
        }
      }
    }
    return false;
  }

  static void _resolveWeak(List<BidiClass> types) {
    // W1 NSM
    BidiClass prev = BidiClass.on;
    for (int i = 0; i < types.length; i++) {
      if (types[i] == BidiClass.nsm) {
        types[i] = prev;
      } else if (types[i] != BidiClass.bn) {
        prev = types[i];
      }
    }
    // W2 EN → AN after AL
    BidiClass lastStrong = BidiClass.on;
    for (int i = 0; i < types.length; i++) {
      final BidiClass t = types[i];
      if (t == BidiClass.al || t == BidiClass.r || t == BidiClass.l) {
        lastStrong = t;
      } else if (t == BidiClass.en && lastStrong == BidiClass.al) {
        types[i] = BidiClass.an;
      }
    }
    // W3 AL → R
    for (int i = 0; i < types.length; i++) {
      if (types[i] == BidiClass.al) {
        types[i] = BidiClass.r;
      }
    }
    // W4 ES/CS between numbers
    for (int i = 1; i < types.length - 1; i++) {
      if (types[i] != BidiClass.es && types[i] != BidiClass.cs) {
        continue;
      }
      final BidiClass left = _nonBn(types, i, -1);
      final BidiClass right = _nonBn(types, i, 1);
      if (types[i] == BidiClass.es &&
          left == BidiClass.en &&
          right == BidiClass.en) {
        types[i] = BidiClass.en;
      } else if (types[i] == BidiClass.cs &&
          left == right &&
          (left == BidiClass.en || left == BidiClass.an)) {
        types[i] = left;
      }
    }
    // W5 ET adjacent to EN
    for (int i = 0; i < types.length; i++) {
      if (types[i] != BidiClass.et) {
        continue;
      }
      if (_nonBn(types, i, -1) == BidiClass.en ||
          _nonBn(types, i, 1) == BidiClass.en) {
        types[i] = BidiClass.en;
      }
    }
    // W6 remaining ES/ET/CS → ON
    for (int i = 0; i < types.length; i++) {
      if (types[i] == BidiClass.es ||
          types[i] == BidiClass.et ||
          types[i] == BidiClass.cs) {
        types[i] = BidiClass.on;
      }
    }
    // W7 EN → L after L
    lastStrong = BidiClass.on;
    for (int i = 0; i < types.length; i++) {
      if (types[i] == BidiClass.l || types[i] == BidiClass.r) {
        lastStrong = types[i];
      } else if (types[i] == BidiClass.en && lastStrong == BidiClass.l) {
        types[i] = BidiClass.l;
      }
    }
  }

  static BidiClass _nonBn(List<BidiClass> types, int i, int dir) {
    int j = i + dir;
    while (j >= 0 && j < types.length) {
      if (types[j] != BidiClass.bn) {
        return types[j];
      }
      j += dir;
    }
    return BidiClass.on;
  }

  static void _resolveNeutrals(
    List<BidiClass> types,
    List<int> levels,
    int paragraphLevel,
  ) {
    // N0 simplified: paired brackets inherit embedding direction if both sides match.
    for (int i = 0; i < types.length; i++) {
      if (!_isNeutral(types[i])) {
        continue;
      }
      final BidiClass left = _sosEos(types, levels, i, -1, paragraphLevel);
      final BidiClass right = _sosEos(types, levels, i, 1, paragraphLevel);
      if (left == right && (left == BidiClass.l || left == BidiClass.r)) {
        types[i] = left;
      } else {
        types[i] = levels[i].isOdd ? BidiClass.r : BidiClass.l;
      }
    }
  }

  static BidiClass _sosEos(
    List<BidiClass> types,
    List<int> levels,
    int i,
    int dir,
    int paragraphLevel,
  ) {
    int j = i + dir;
    final int runLevel = levels[i];
    while (j >= 0 && j < types.length) {
      if (levels[j] != runLevel) {
        break;
      }
      if (!_isNeutral(types[j]) && types[j] != BidiClass.bn) {
        if (types[j] == BidiClass.an || types[j] == BidiClass.en) {
          return BidiClass.r;
        }
        return types[j];
      }
      j += dir;
    }
    return runLevel.isOdd ? BidiClass.r : BidiClass.l;
  }

  static bool _isNeutral(BidiClass t) =>
      t == BidiClass.b ||
      t == BidiClass.s ||
      t == BidiClass.ws ||
      t == BidiClass.on ||
      t == BidiClass.bn;

  static void _resolveImplicit(List<BidiClass> types, List<int> levels) {
    for (int i = 0; i < types.length; i++) {
      final BidiClass t = types[i];
      if (levels[i].isEven) {
        if (t == BidiClass.r) {
          levels[i] += 1;
        } else if (t == BidiClass.an || t == BidiClass.en) {
          levels[i] += 2;
        }
      } else {
        if (t == BidiClass.l || t == BidiClass.an || t == BidiClass.en) {
          levels[i] += 1;
        }
      }
    }
  }

  static void _resetWhitespace(
    List<BidiClass> original,
    List<int> levels,
    int paragraphLevel,
  ) {
    for (int i = levels.length - 1; i >= 0; i--) {
      final BidiClass t = original[i];
      if (t == BidiClass.b || t == BidiClass.s) {
        levels[i] = paragraphLevel;
        for (int j = i - 1; j >= 0; j--) {
          if (original[j] == BidiClass.ws || original[j] == BidiClass.bn) {
            levels[j] = paragraphLevel;
          } else {
            break;
          }
        }
      }
    }
  }

  /// UAX #9 L4: mirrored glyph for [codePoint] when resolved level is odd.
  ///
  /// Parentheses and similar pairs must flip after RTL reordering; otherwise
  /// Arabic like `الإيراد (شيكل)` paints as `الإيراد )شيكل(`.
  static int mirrored(int codePoint) => _mirrors[codePoint] ?? codePoint;

  static const Map<int, int> _mirrors = <int, int>{
    0x0028: 0x0029, // ( )
    0x0029: 0x0028,
    0x003C: 0x003E, // < >
    0x003E: 0x003C,
    0x005B: 0x005D, // [ ]
    0x005D: 0x005B,
    0x007B: 0x007D, // { }
    0x007D: 0x007B,
    0x00AB: 0x00BB, // « »
    0x00BB: 0x00AB,
    0x2039: 0x203A, // ‹ ›
    0x203A: 0x2039,
    0x2264: 0x2265, // ≤ ≥
    0x2265: 0x2264,
  };

  /// UAX #9 L2: visual-to-logical indices for one line's resolved levels.
  static List<int> visualOrder(List<int> levels) {
    final List<int> order = <int>[for (int i = 0; i < levels.length; i++) i];
    var maxLevel = 0;
    var minOdd = 125;
    for (final int level in levels) {
      if (level > maxLevel) {
        maxLevel = level;
      }
      if (level.isOdd && level < minOdd) {
        minOdd = level;
      }
    }
    for (int level = maxLevel; level >= minOdd; level--) {
      int i = 0;
      while (i < order.length) {
        if (levels[order[i]] >= level) {
          int j = i;
          while (j < order.length && levels[order[j]] >= level) {
            j++;
          }
          _reverseRange(order, i, j - 1);
          i = j;
        } else {
          i++;
        }
      }
    }
    return order;
  }

  static void _reverseRange(List<int> list, int from, int to) {
    while (from < to) {
      final int tmp = list[from];
      list[from] = list[to];
      list[to] = tmp;
      from++;
      to--;
    }
  }

  static List<BidiRun> _runs(
    String text,
    List<int> cps,
    List<int> levels,
    List<int> visual,
  ) {
    if (visual.isEmpty) {
      return const <BidiRun>[];
    }
    // Map code-point index → UTF-16 offset.
    final List<int> offsets = <int>[0];
    var utf16 = 0;
    for (final int cp in cps) {
      utf16 += cp > 0xFFFF ? 2 : 1;
      offsets.add(utf16);
    }
    final List<BidiRun> runs = <BidiRun>[];
    int runStart = 0;
    for (int v = 1; v <= visual.length; v++) {
      final bool boundary =
          v == visual.length ||
          levels[visual[v]] != levels[visual[runStart]] ||
          visual[v] !=
              visual[v - 1] + (levels[visual[runStart]].isOdd ? -1 : 1);
      if (!boundary) {
        continue;
      }
      final List<int> slice = visual.sublist(runStart, v);
      final int minLog = slice.reduce((int a, int b) => a < b ? a : b);
      final int maxLog = slice.reduce((int a, int b) => a > b ? a : b);
      runs.add(
        BidiRun(
          text: text.substring(offsets[minLog], offsets[maxLog + 1]),
          level: levels[visual[runStart]],
          logicalStart: offsets[minLog],
          logicalEnd: offsets[maxLog + 1],
          visualStart: runStart,
        ),
      );
      runStart = v;
    }
    return runs;
  }

  static BidiClass _classify(int cp) {
    if (cp == 0x000A ||
        cp == 0x000D ||
        cp == 0x001C ||
        cp == 0x001D ||
        cp == 0x001E ||
        cp == 0x0085 ||
        cp == 0x2029) {
      return BidiClass.b;
    }
    if (cp == 0x0009 || cp == 0x000B || cp == 0x001F) {
      return BidiClass.s;
    }
    if (cp == 0x0020 ||
        cp == 0x00A0 ||
        cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) ||
        cp == 0x2028 ||
        cp == 0x202F ||
        cp == 0x205F ||
        cp == 0x3000) {
      return BidiClass.ws;
    }
    if (cp == 0x202A) return BidiClass.lre;
    if (cp == 0x202B) return BidiClass.rle;
    if (cp == 0x202C) return BidiClass.pdf;
    if (cp == 0x202D) return BidiClass.lro;
    if (cp == 0x202E) return BidiClass.rlo;
    if (cp == 0x2066) return BidiClass.lri;
    if (cp == 0x2067) return BidiClass.rli;
    if (cp == 0x2068) return BidiClass.fsi;
    if (cp == 0x2069) return BidiClass.pdi;
    if ((cp >= 0x0300 && cp <= 0x036F) ||
        (cp >= 0x064B && cp <= 0x065F) ||
        cp == 0x0670 ||
        (cp >= 0x06D6 && cp <= 0x06ED) ||
        (cp >= 0x08D3 && cp <= 0x08FF) ||
        (cp >= 0x1AB0 && cp <= 0x1AFF) ||
        (cp >= 0x20D0 && cp <= 0x20FF) ||
        (cp >= 0xFE20 && cp <= 0xFE2F)) {
      return BidiClass.nsm;
    }
    if (cp >= 0x0600 && cp <= 0x06FF) {
      if (cp >= 0x0660 && cp <= 0x0669) {
        return BidiClass.an;
      }
      if (cp >= 0x06F0 && cp <= 0x06F9) {
        return BidiClass.en;
      }
      if (cp == 0x060C || cp == 0x066B || cp == 0x066C) {
        return BidiClass.cs;
      }
      return BidiClass.al;
    }
    if (cp >= 0x0750 && cp <= 0x077F) return BidiClass.al;
    if (cp >= 0x08A0 && cp <= 0x08FF) return BidiClass.al;
    if (cp >= 0xFB50 && cp <= 0xFDFF) return BidiClass.al;
    if (cp >= 0xFE70 && cp <= 0xFEFF) return BidiClass.al;
    if (cp >= 0x0590 && cp <= 0x05FF) return BidiClass.r;
    if (cp >= 0x07C0 && cp <= 0x07FF) return BidiClass.r;
    if (cp >= 0x0030 && cp <= 0x0039) return BidiClass.en;
    if (cp == 0x002B || cp == 0x002D) return BidiClass.es;
    if (cp == 0x0023 ||
        cp == 0x0024 ||
        cp == 0x0025 ||
        (cp >= 0x00A2 && cp <= 0x00A5) ||
        cp == 0x20AC) {
      return BidiClass.et;
    }
    if (cp == 0x002C || cp == 0x002E || cp == 0x003A || cp == 0x002F) {
      return BidiClass.cs;
    }
    if ((cp >= 0x0041 && cp <= 0x005A) ||
        (cp >= 0x0061 && cp <= 0x007A) ||
        (cp >= 0x00C0 && cp <= 0x00D6) ||
        (cp >= 0x00D8 && cp <= 0x00F6) ||
        (cp >= 0x00F8 && cp <= 0x02B8)) {
      return BidiClass.l;
    }
    return BidiClass.on;
  }
}

class _Embed {
  const _Embed(this.level, this.override, this.isolate);

  /// level API.
  final int level;
  final bool override;

  /// isolate API.
  final bool isolate;
}
