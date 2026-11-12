import 'dart:math' as math;

import 'arabic_shaping.dart';
import 'grapheme_clusters.dart';
import 'uax9_bidi.dart';

/// A laid-out line of shaped visual glyphs.
class BrokenLine {
  /// BrokenLine API.
  BrokenLine({
    required this.glyphs,
    required this.width,
    required this.logicalStart,
    required this.logicalEnd,
    required this.justificationRatio,
  });

  /// glyphs API.
  final List<ShapedGlyph> glyphs;

  /// width API.
  final double width;

  /// logicalStart API.
  final int logicalStart;

  /// logicalEnd API.
  final int logicalEnd;

  /// justificationRatio API.
  final double justificationRatio;
}

/// Shaped visual glyph with document metrics in points.
class ShapedGlyph {
  /// ShapedGlyph API.
  const ShapedGlyph({
    required this.codePoint,
    required this.glyphId,
    required this.advance,
    required this.logicalIndex,
    required this.level,
    this.isSpace = false,
    this.paintDx = 0,
    this.paintDy = 0,
  });

  /// codePoint API.
  final int codePoint;

  /// glyphId API.
  final int glyphId;

  /// advance API.
  final double advance;

  /// logicalIndex API.
  final int logicalIndex;

  /// level API.
  final int level;

  /// isSpace API.
  final bool isSpace;

  /// Added to the pen X before painting. Combining marks sit on their base.
  final double paintDx;

  /// Added to the baseline before painting (font space, positive is up).
  final double paintDy;
}

/// Offset applied after the base advance so a combining mark sits on it.
typedef MarkAttachFn =
    ({double dx, double dy}) Function(ShapedGlyph base, ShapedGlyph mark);

/// Width provider used by the breaker (typically [FontMetrics.characterWidth]).
typedef GlyphWidthFn = double Function(int codePoint);

/// Typedef GlyphIdFn.
typedef GlyphIdFn = int Function(int codePoint);

/// UAX #14 opportunities + Knuth–Plass least-demerits wrapping.
abstract final class LineBreaker {
  /// Shape once, then choose each line's width as its layout position changes.
  ///
  /// The prepared paragraph retains the original bidi levels, Arabic joining
  /// and UTF-16 offsets. Rebreaking a substring would lose that context.
  static PreparedLineBreaker prepare({
    required String text,
    required GlyphWidthFn widthOf,
    GlyphIdFn glyphIdOf = _identityGlyph,
    int? baseLevel,
    double spaceStretch = 3,
    double spaceShrink = 1,
    bool justify = true,
    MarkAttachFn? markAttachOf,
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? ligate,
  }) {
    final bidi = Uax9Bidi.reorder(text, baseLevel: baseLevel);
    final logical = _logicalGlyphs(text, bidi, widthOf, glyphIdOf);
    return PreparedLineBreaker._(
      text,
      ligate == null ? logical : ligate(logical),
      spaceStretch,
      spaceShrink,
      justify,
      markAttachOf,
    );
  }

  /// breakLines API.
  static List<BrokenLine> breakLines({
    required String text,
    required double maxWidth,
    required GlyphWidthFn widthOf,
    GlyphIdFn glyphIdOf = _identityGlyph,
    int? baseLevel,
    double spaceStretch = 3,
    double spaceShrink = 1,

    /// When false, do not stretch spaces to the line edge (pdf_widgets
    /// non-justify aligns). Word layout keeps the default [true].
    bool justify = true,

    /// Split otherwise overflowing lines at source grapheme boundaries. Fixed
    /// cells and textboxes cannot expand to accommodate a long word. Normal
    /// word breaks still take priority; a single wider grapheme stays intact.
    bool breakLongWords = false,
    MarkAttachFn? markAttachOf,
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? ligate,
  }) {
    if (text.isEmpty) {
      return <BrokenLine>[
        BrokenLine(
          glyphs: const <ShapedGlyph>[],
          width: 0,
          logicalStart: 0,
          logicalEnd: 0,
          justificationRatio: 0,
        ),
      ];
    }
    final BidiParagraph bidi = Uax9Bidi.reorder(text, baseLevel: baseLevel);
    // Wrap in logical order, then apply UAX #9 L2 per line. Reordering the
    // whole paragraph first inverts RTL wraps (logical start on a later line).
    final List<ShapedGlyph> logical = ligate == null
        ? _logicalGlyphs(text, bidi, widthOf, glyphIdOf)
        : ligate(_logicalGlyphs(text, bidi, widthOf, glyphIdOf));
    if (logical.isEmpty) {
      return <BrokenLine>[];
    }
    final Set<int>? clusterStarts = breakLongWords
        ? {for (final cluster in GraphemeClusters.segment(text)) cluster.start}
        : null;

    // Hard breaks on LF/CR (Flutter / package:pdf Text parity).
    final List<BrokenLine> lines = <BrokenLine>[];
    var start = 0;
    for (int i = 0; i <= logical.length; i++) {
      final bool atEnd = i == logical.length;
      final bool hard =
          !atEnd &&
          (logical[i].codePoint == 0x0A || logical[i].codePoint == 0x0D);
      if (!atEnd && !hard) {
        continue;
      }
      final List<ShapedGlyph> chunk = logical.sublist(start, i);
      if (chunk.isNotEmpty) {
        lines.addAll(
          _wrapChunk(
            chunk,
            sourceText: text,
            maxWidth: maxWidth,
            spaceStretch: spaceStretch,
            spaceShrink: spaceShrink,
            justify: justify,
            markAttachOf: markAttachOf,
            clusterStarts: clusterStarts,
          ),
        );
      } else if (hard || (atEnd && lines.isEmpty)) {
        lines.add(
          BrokenLine(
            glyphs: const <ShapedGlyph>[],
            width: 0,
            logicalStart: 0,
            logicalEnd: 0,
            justificationRatio: 0,
          ),
        );
      }
      start = i + (hard ? 1 : 0);
      if (hard &&
          i + 1 < logical.length &&
          logical[i].codePoint == 0x0D &&
          logical[i + 1].codePoint == 0x0A) {
        start = i + 2;
        i++;
      }
    }
    return lines;
  }

  static List<BrokenLine> _wrapChunk(
    List<ShapedGlyph> logical, {
    required String sourceText,
    required double maxWidth,
    required double spaceStretch,
    required double spaceShrink,
    required bool justify,
    MarkAttachFn? markAttachOf,
    Set<int>? clusterStarts,
  }) {
    final List<int> planned = _knuthPlass(
      logical,
      maxWidth,
      spaceStretch,
      spaceShrink,
    );
    final breaks = clusterStarts == null
        ? planned
        : _constrainBreaks(logical, planned, clusterStarts, maxWidth);
    final List<BrokenLine> lines = <BrokenLine>[];
    for (int i = 0; i < breaks.length - 1; i++) {
      final int from = breaks[i];
      var to = breaks[i + 1];
      while (to > from && _isSoftTrailingSpace(logical[to - 1])) {
        to--;
      }
      final List<ShapedGlyph> slice = _reorderLine(
        logical.sublist(from, to),
        markAttachOf,
        clusterStarts,
      );
      double width = 0;
      var spaces = 0;
      for (final ShapedGlyph g in slice) {
        width += g.advance;
        if (g.isSpace) {
          spaces++;
        }
      }
      var ratio = 0.0;
      if (justify && spaces > 0 && width < maxWidth && i != breaks.length - 2) {
        ratio = (maxWidth - width) / (spaces * spaceStretch);
        width = maxWidth;
      }
      int logStart = 0x7fffffff;
      int logEnd = 0;
      for (final ShapedGlyph g in slice) {
        if (g.logicalIndex < logStart) {
          logStart = g.logicalIndex;
        }
        final source = sourceText.codeUnitAt(g.logicalIndex);
        final units = source >= 0xD800 && source <= 0xDBFF ? 2 : 1;
        if (g.logicalIndex + units > logEnd) {
          logEnd = g.logicalIndex + units;
        }
      }
      if (slice.isEmpty) {
        logStart = 0;
        logEnd = 0;
      }
      lines.add(
        BrokenLine(
          glyphs: slice,
          width: width,
          logicalStart: logStart,
          logicalEnd: logEnd,
          justificationRatio: ratio,
        ),
      );
    }
    return lines;
  }

  // Keep the existing paragraph plan wherever it fits. Repair only overflow,
  // greedily preferring a normal word break before a grapheme boundary. This
  // avoids adding every character to Knuth-Plass's quadratic search, and keeps
  // original Arabic joining, bidi levels and UTF-16 ownership intact.
  static List<int> _constrainBreaks(
    List<ShapedGlyph> logical,
    List<int> planned,
    Set<int> clusterStarts,
    double maxWidth,
  ) {
    final boundaries = <int>[
      0,
      for (var i = 1; i < logical.length; i++)
        if (clusterStarts.contains(logical[i].logicalIndex) &&
            // A lam-alef ghost belongs to the preceding painted ligature.
            logical[i].codePoint != 0)
          i,
      logical.length,
    ];
    final boundaryIndex = <int, int>{
      for (var i = 0; i < boundaries.length; i++) boundaries[i]: i,
    };
    final widths = List<double>.filled(logical.length + 1, 0);
    final paintedEnd = List<int>.filled(logical.length + 1, 0);
    for (var i = 0; i < logical.length; i++) {
      widths[i + 1] = widths[i] + logical[i].advance;
      paintedEnd[i + 1] = _isSoftTrailingSpace(logical[i])
          ? paintedEnd[i]
          : i + 1;
    }
    final result = <int>[0];
    var start = 0;
    for (final plannedEnd in planned.skip(1)) {
      final end = boundaryIndex[plannedEnd];
      // A natural break inside a source grapheme must join the next interval.
      if (end == null) continue;
      while (start < end) {
        var fitting = start;
        var natural = start;
        for (var next = start + 1; next <= end; next++) {
          final from = boundaries[start];
          final to = boundaries[next];
          final width = widths[math.max(from, paintedEnd[to])] - widths[from];
          if (width > maxWidth + 0.000001) {
            // An indivisible glyph/cluster may itself be wider than the box.
            // Keep it whole and always make progress.
            if (fitting == start) fitting = next;
            break;
          }
          fitting = next;
          if (_canBreakAfter(logical, to - 1)) natural = next;
        }
        final cut = fitting == end
            ? end
            : (natural > start ? natural : fitting);
        result.add(boundaries[cut]);
        start = cut;
      }
    }
    return result;
  }

  static List<ShapedGlyph> _reorderLine(
    List<ShapedGlyph> logicalSlice,
    MarkAttachFn? markAttachOf, [
    Set<int>? clusterStarts,
  ]) {
    if (logicalSlice.isEmpty) {
      return logicalSlice;
    }
    final List<List<ShapedGlyph>> clusters = _graphemeClusters(
      logicalSlice,
      clusterStarts,
    );
    if (clusters.length < 2) {
      return _attachMarksToBases(logicalSlice, markAttachOf);
    }
    final List<int> levels = <int>[
      for (final List<ShapedGlyph> cluster in clusters) cluster.first.level,
    ];
    final List<int> order = Uax9Bidi.visualOrder(levels);
    return _attachMarksToBases(<ShapedGlyph>[
      for (final int i in order) ...clusters[i],
    ], markAttachOf);
  }

  /// UAX #9 L2 at grapheme-cluster granularity: tashkeel stays on its letter.
  static List<List<ShapedGlyph>> _graphemeClusters(
    List<ShapedGlyph> glyphs,
    Set<int>? clusterStarts,
  ) {
    final List<List<ShapedGlyph>> clusters = <List<ShapedGlyph>>[];
    for (final ShapedGlyph glyph in glyphs) {
      final continues = clusterStarts == null
          ? isCombiningMark(glyph.codePoint)
          : !clusterStarts.contains(glyph.logicalIndex) || glyph.codePoint == 0;
      if (clusters.isNotEmpty && continues) {
        clusters.last.add(glyph);
      } else {
        clusters.add(<ShapedGlyph>[glyph]);
      }
    }
    return clusters;
  }

  /// Paint marks at the center of the preceding base (zero-width overlay).
  static List<ShapedGlyph> _attachMarksToBases(
    List<ShapedGlyph> visual,
    MarkAttachFn? markAttachOf,
  ) {
    final List<ShapedGlyph> out = <ShapedGlyph>[];
    var i = 0;
    while (i < visual.length) {
      final ShapedGlyph glyph = visual[i];
      if (isCombiningMark(glyph.codePoint)) {
        out.add(glyph);
        i++;
        continue;
      }
      var j = i + 1;
      while (j < visual.length && isCombiningMark(visual[j].codePoint)) {
        j++;
      }
      out.add(glyph);
      if (j > i + 1) {
        for (int k = i + 1; k < j; k++) {
          final ShapedGlyph mark = visual[k];
          final ({double dx, double dy}) attach = markAttachOf == null
              ? (dx: -glyph.advance / 2, dy: 0)
              : markAttachOf(glyph, mark);
          out.add(
            ShapedGlyph(
              codePoint: mark.codePoint,
              glyphId: mark.glyphId,
              advance: 0,
              logicalIndex: mark.logicalIndex,
              level: mark.level,
              paintDx: attach.dx,
              paintDy: attach.dy,
            ),
          );
        }
      }
      i = j;
    }
    return out;
  }

  /// Arabic / Syriac combining marks (tashkeel) that must stay on the base.
  static bool isCombiningMark(int cp) =>
      (cp >= 0x0610 && cp <= 0x061A) ||
      (cp >= 0x064B && cp <= 0x065F) ||
      cp == 0x0670 ||
      (cp >= 0x06D6 && cp <= 0x06DC) ||
      (cp >= 0x06DF && cp <= 0x06E4) ||
      (cp >= 0x06E7 && cp <= 0x06E8) ||
      (cp >= 0x06EA && cp <= 0x06ED) ||
      (cp >= 0x08D3 && cp <= 0x08E1) ||
      (cp >= 0x08E3 && cp <= 0x0902);

  static List<ShapedGlyph> _logicalGlyphs(
    String text,
    BidiParagraph bidi,
    GlyphWidthFn widthOf,
    GlyphIdFn glyphIdOf,
  ) {
    final List<int> cps = text.runes.toList();
    final List<int> offsets = <int>[0];
    var utf16 = 0;
    for (final int cp in cps) {
      utf16 += cp > 0xFFFF ? 2 : 1;
      offsets.add(utf16);
    }
    final List<ShapedGlyph> logical = <ShapedGlyph>[];
    for (
      int logicalCpIndex = 0;
      logicalCpIndex < cps.length;
      logicalCpIndex++
    ) {
      final int cp = cps[logicalCpIndex];
      final int logicalIndex = offsets[logicalCpIndex];
      if (Uax9Bidi.isInvisibleFormat(cp)) {
        continue;
      }
      if (isCombiningMark(cp)) {
        logical.add(
          ShapedGlyph(
            codePoint: cp,
            glyphId: glyphIdOf(cp),
            advance: 0,
            logicalIndex: logicalIndex,
            level: bidi.levels[logicalCpIndex],
          ),
        );
        continue;
      }
      logical.add(
        ShapedGlyph(
          codePoint: cp,
          glyphId: glyphIdOf(cp),
          advance: widthOf(cp),
          logicalIndex: logicalIndex,
          level: bidi.levels[logicalCpIndex],
          isSpace: _isBreakSpace(cp),
        ),
      );
    }
    // Presentation forms use logical-neighbour joining on the original string.
    final List<ShapedChar> shaped = ArabicShaper.shape(text);
    final Map<int, ShapedChar> byLogical = <int, ShapedChar>{
      for (final ShapedChar s in shaped) s.logicalIndex: s,
    };
    return logical.map((ShapedGlyph g) {
      final ShapedChar? s = byLogical[g.logicalIndex];
      if (s == null) {
        return _l4Mirror(g, widthOf, glyphIdOf);
      }
      // Prefer the joining presentation form. Fonts that only encode the
      // nominal letter (GSUB shaping, no FE7x cmap) still get a non-zero
      // advance so the glyph is not painted on top of the previous letter.
      var cp = s.codePoint;
      if (cp == 0 && s.advanceFactor == 0) {
        return ShapedGlyph(
          codePoint: 0,
          glyphId: 0,
          advance: 0,
          logicalIndex: g.logicalIndex,
          level: g.level,
        );
      }
      if (glyphIdOf(cp) == 0) {
        final int? nominal = ArabicShaper.nominalOf(cp);
        if (nominal != null && glyphIdOf(nominal) != 0) {
          cp = nominal;
        }
      }
      final int gid = glyphIdOf(cp);
      var advance = s.advanceFactor == 0 ? 0.0 : widthOf(cp);
      if (s.advanceFactor != 0 && advance <= 0 && gid != 0) {
        final double space = widthOf(0x0020);
        advance = space > 0 ? space : 1;
      }
      return _l4Mirror(
        ShapedGlyph(
          codePoint: cp,
          glyphId: gid,
          advance: advance,
          logicalIndex: g.logicalIndex,
          level: g.level,
          isSpace: g.isSpace,
        ),
        widthOf,
        glyphIdOf,
      );
    }).toList();
  }

  /// UAX #9 L4 after shaping: flip mirrored pairs on odd embedding levels.
  static ShapedGlyph _l4Mirror(
    ShapedGlyph g,
    GlyphWidthFn widthOf,
    GlyphIdFn glyphIdOf,
  ) {
    if (!g.level.isOdd || g.codePoint == 0) {
      return g;
    }
    final int mirrored = Uax9Bidi.mirrored(g.codePoint);
    if (mirrored == g.codePoint) {
      return g;
    }
    return ShapedGlyph(
      codePoint: mirrored,
      glyphId: glyphIdOf(mirrored),
      advance: widthOf(mirrored),
      logicalIndex: g.logicalIndex,
      level: g.level,
      isSpace: g.isSpace,
      paintDx: g.paintDx,
    );
  }

  static List<int> _knuthPlass(
    List<ShapedGlyph> glyphs,
    double maxWidth,
    double stretch,
    double shrink,
  ) {
    final int n = glyphs.length;
    final List<double> widths = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      widths[i + 1] = widths[i] + glyphs[i].advance;
    }
    final List<int> legal = <int>[0];
    for (int i = 0; i < n; i++) {
      if (_canBreakAfter(glyphs, i)) {
        legal.add(i + 1);
      }
    }
    if (legal.last != n) {
      legal.add(n);
    }

    final List<double> demerits = List<double>.filled(
      legal.length,
      double.infinity,
    );
    final List<int> pred = List<int>.filled(legal.length, 0);
    demerits[0] = 0;
    for (int j = 1; j < legal.length; j++) {
      for (int i = 0; i < j; i++) {
        final int from = legal[i];
        final int to = legal[j];
        double w = widths[to] - widths[from];
        // trailing spaces do not count
        var t = to - 1;
        while (t >= from && _isSoftTrailingSpace(glyphs[t])) {
          w -= glyphs[t].advance;
          t--;
        }
        if (w > maxWidth + shrink && j != legal.length - 1) {
          continue;
        }
        var badness = 0.0;
        if (w > maxWidth) {
          badness = ((w - maxWidth) / (shrink <= 0 ? 1 : shrink)) * 4 + 20;
        } else if (j != legal.length - 1) {
          final double slack = maxWidth - w;
          var spaces = 0;
          for (int k = from; k <= t; k++) {
            if (glyphs[k].isSpace && glyphs[k].codePoint != 0x09) {
              spaces++;
            }
          }
          // TeX-like: stretchability grows with the number of word gaps.
          final double stretchability =
              math.max(spaces, 1) * (stretch <= 0 ? 1 : stretch);
          badness = slack / stretchability;
          // Extra penalty for sparse lines (few spaces, large gaps).
          if (spaces > 0 && slack / spaces > stretch * 2) {
            badness += (slack / spaces) / stretch;
          }
        }
        final double cost = demerits[i] + badness * badness * 100 + 10;
        if (cost < demerits[j]) {
          demerits[j] = cost;
          pred[j] = i;
        }
      }
      if (demerits[j].isInfinite) {
        // Forced overflow: take the previous legal break.
        demerits[j] = demerits[j - 1] + 10000;
        pred[j] = j - 1;
      }
    }
    final List<int> points = <int>[];
    var k = legal.length - 1;
    while (k > 0) {
      points.add(legal[k]);
      k = pred[k];
    }
    points.add(0);
    return points.reversed.toList();
  }

  static bool _canBreakAfter(List<ShapedGlyph> glyphs, int i) {
    final int cp = glyphs[i].codePoint;
    if (cp == 0x000A || cp == 0x000D) {
      return true;
    }
    if (i == glyphs.length - 1) {
      return true;
    }
    final int next = glyphs[i + 1].codePoint;
    if (_isBreakSpace(cp)) {
      return true;
    }
    // UAX #14: BA, ZW, HY allow break after; GL/WJ forbid.
    if (cp == 0x200B || cp == 0x00AD || cp == 0x2010 || cp == 0x002D) {
      return true;
    }
    if (cp == 0x00A0 || cp == 0x2060 || cp == 0x200D) {
      return false;
    }
    // Do not break inside a grapheme (tashkeel already zero-width).
    if (isCombiningMark(next)) {
      return false;
    }
    return false;
  }

  static bool _isBreakSpace(int cp) =>
      cp == 0x0020 || cp == 0x0009 || cp == 0x2000 || cp == 0x3000;

  static bool _isSoftTrailingSpace(ShapedGlyph glyph) =>
      glyph.isSpace && glyph.codePoint != 0x09;

  /// cp API.
  static int _identityGlyph(int cp) => cp;
}

/// A paragraph whose shaping is stable while available line widths vary.
///
/// [breakNext] is side-effect free: pagination can retry the same source offset
/// at a different width without consuming characters or changing bidi context.
class PreparedLineBreaker {
  PreparedLineBreaker._(
    this._text,
    this._logical,
    this._stretch,
    this._shrink,
    this._justify,
    this._markAttach,
  );

  final String _text;
  final List<ShapedGlyph> _logical;
  final double _stretch;
  final double _shrink;
  final bool _justify;
  final MarkAttachFn? _markAttach;
  double? _plannedWidth;
  final Map<int, int> _plannedBreaks = {};

  /// Return one line and the exact UTF-16 offset consumed, including a hard
  /// break or soft trailing spaces. A CRLF is one hard break; blank lines remain.
  ({BrokenLine line, int nextOffset}) breakNext({
    required int start,
    required double maxWidth,
  }) {
    RangeError.checkValueInInterval(start, 0, _text.length, 'start');
    if (!maxWidth.isFinite || maxWidth <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', 'Must be positive');
    }
    var low = 0;
    var high = _logical.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_logical[mid].logicalIndex < start) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final from = low;
    var hard = from;
    while (hard < _logical.length &&
        _logical[hard].codePoint != 0x0A &&
        _logical[hard].codePoint != 0x0D) {
      hard++;
    }
    var chunkEnd = _text.length;
    if (hard < _logical.length) {
      chunkEnd = _logical[hard].logicalIndex + 1;
      if (_logical[hard].codePoint == 0x0D &&
          chunkEnd < _text.length &&
          _text.codeUnitAt(chunkEnd) == 0x0A) {
        chunkEnd++;
      }
    }
    if (from == hard) {
      return (
        line: BrokenLine(
          glyphs: const [],
          width: 0,
          logicalStart: start,
          logicalEnd: start,
          justificationRatio: 0,
        ),
        nextOffset: chunkEnd,
      );
    }
    final chunk = _logical.sublist(from, hard);
    if (_plannedWidth != maxWidth) {
      _plannedWidth = maxWidth;
      _plannedBreaks.clear();
    }
    if (!_plannedBreaks.containsKey(from)) {
      final points = LineBreaker._knuthPlass(
        chunk,
        maxWidth,
        _stretch,
        _shrink,
      );
      // The optimal suffix remains valid until the available width changes.
      // Reuse it instead of recomputing a whole paragraph for every line.
      for (var i = 0; i + 1 < points.length; i++) {
        _plannedBreaks[from + points[i]] = from + points[i + 1];
      }
    }
    final consumed = _plannedBreaks[from]! - from;
    var painted = consumed;
    while (painted > 0 &&
        LineBreaker._isSoftTrailingSpace(chunk[painted - 1])) {
      painted--;
    }
    final glyphs = LineBreaker._reorderLine(
      chunk.sublist(0, painted),
      _markAttach,
    );
    var width = 0.0;
    var spaces = 0;
    var logicalStart = _text.length;
    var logicalEnd = start;
    for (final glyph in glyphs) {
      width += glyph.advance;
      if (glyph.isSpace) spaces++;
      logicalStart = math.min(logicalStart, glyph.logicalIndex);
      final source = _text.codeUnitAt(glyph.logicalIndex);
      final units = source >= 0xD800 && source <= 0xDBFF ? 2 : 1;
      logicalEnd = math.max(logicalEnd, glyph.logicalIndex + units);
    }
    var ratio = 0.0;
    if (_justify && spaces > 0 && width < maxWidth && consumed < chunk.length) {
      ratio = (maxWidth - width) / (spaces * _stretch);
      width = maxWidth;
    }
    return (
      line: BrokenLine(
        glyphs: glyphs,
        width: width,
        logicalStart: glyphs.isEmpty ? start : logicalStart,
        logicalEnd: logicalEnd,
        justificationRatio: ratio,
      ),
      nextOffset: consumed < chunk.length
          ? chunk[consumed].logicalIndex
          : chunkEnd,
    );
  }
}

/// Hit-test a visual X offset on [line] and return the logical UTF-16 index.
int visualXToLogical(BrokenLine line, double x) {
  /// cursor API.
  var cursor = 0.0;
  for (final ShapedGlyph g in line.glyphs) {
    final double mid = cursor + g.advance / 2;
    if (x <= mid) {
      return g.logicalIndex;
    }
    cursor += g.advance;
  }
  return line.logicalEnd;
}

/// Maps a logical index to a visual caret X on [line].
double logicalToVisualX(BrokenLine line, int logicalIndex) {
  /// cursor API.
  var cursor = 0.0;
  for (final ShapedGlyph g in line.glyphs) {
    if (g.logicalIndex == logicalIndex) {
      return cursor;
    }
    cursor += g.advance;
  }
  return line.width;
}

/// Expose cluster bounds for caret engines.
List<GraphemeCluster> caretClusters(String text) =>
    GraphemeClusters.segment(text);
