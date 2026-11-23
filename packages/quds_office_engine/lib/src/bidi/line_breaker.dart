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
    this.isDiscretionaryHyphen = false,
    this.sourceLength,
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

  /// A visible hyphen selected at a discretionary line break.
  final bool isDiscretionaryHyphen;

  /// Authored UTF-16 units owned by this glyph. Automatic hyphens own zero;
  /// explicit U+00AD owns one. Null retains the normal source-character size.
  final int? sourceLength;

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

/// Per-run width provider. [logicalIndex] is the source UTF-16 offset, retained
/// through Arabic joining and bidi mirroring.
typedef GlyphWidthAtFn = double Function(int codePoint, int logicalIndex);

/// Per-run glyph lookup in the same face used by [GlyphWidthAtFn].
typedef GlyphIdAtFn = int Function(int codePoint, int logicalIndex);

/// UAX #14 opportunities with balanced or Word-style greedy wrapping.
abstract final class LineBreaker {
  /// Shape once, then choose each line's width as its layout position changes.
  ///
  /// The prepared paragraph retains the original bidi levels, Arabic joining
  /// and UTF-16 offsets. Rebreaking a substring would lose that context.
  static PreparedLineBreaker prepare({
    required String text,
    required GlyphWidthFn widthOf,
    GlyphIdFn glyphIdOf = _identityGlyph,
    GlyphWidthAtFn? widthAt,
    GlyphIdAtFn? glyphIdAt,
    int? baseLevel,
    double spaceStretch = 3,
    double spaceShrink = 1,
    bool justify = true,
    bool breakLongWords = false,
    // False uses the longest fitting legal prefix, as Word does. The default
    // retains balanced paragraph breaking for PDF/report consumers.
    bool balanceLines = true,
    MarkAttachFn? markAttachOf,
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? ligate,

    /// Remeasure an actual logical line after trimming spaces and selecting a
    /// discretionary hyphen. The callback may change advances only; source
    /// ownership and glyph order must remain intact. Invalid results fall back
    /// to the original metrics. Overflow is repaired before visual reordering.
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? measureLine,
    Iterable<int> hyphenationOffsets = const [],
  }) {
    final logical = _logicalGlyphs(
      text,
      baseLevel,
      widthAt ?? (cp, _) => widthOf(cp),
      glyphIdAt ?? (cp, _) => glyphIdOf(cp),
    );
    final shaped = ligate == null ? logical : ligate(logical);
    final clusterStarts = {
      for (final cluster in GraphemeClusters.segment(text)) cluster.start,
    };
    final hyphens = _hyphenGlyphs(
      text,
      shaped,
      hyphenationOffsets,
      clusterStarts,
      widthAt ?? (cp, _) => widthOf(cp),
      glyphIdAt ?? (cp, _) => glyphIdOf(cp),
    );
    return PreparedLineBreaker._(
      text,
      shaped,
      spaceStretch,
      spaceShrink,
      justify,
      markAttachOf,
      hyphens,
      _BreakControls.fromText(text, shaped),
      clusterStarts,
      measureLine,
      breakLongWords,
      balanceLines,
    );
  }

  /// breakLines API.
  static List<BrokenLine> breakLines({
    required String text,
    required double maxWidth,
    required GlyphWidthFn widthOf,
    GlyphIdFn glyphIdOf = _identityGlyph,
    GlyphWidthAtFn? widthAt,
    GlyphIdAtFn? glyphIdAt,
    int? baseLevel,
    double spaceStretch = 3,
    double spaceShrink = 1,

    /// When false, do not stretch spaces to the line edge (pdf_widgets
    /// non-justify aligns). Word enables this for justified paragraphs only.
    bool justify = true,

    /// Split otherwise overflowing lines at source grapheme boundaries. Fixed
    /// cells and textboxes cannot expand to accommodate a long word. Normal
    /// word breaks still take priority; a single wider grapheme stays intact.
    bool breakLongWords = false,
    // False uses the longest fitting legal prefix, as Word does. The default
    // retains balanced paragraph breaking for PDF/report consumers.
    bool balanceLines = true,
    MarkAttachFn? markAttachOf,
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? ligate,

    /// Remeasure an actual logical line after trimming spaces and selecting a
    /// discretionary hyphen. The callback may change advances only; source
    /// ownership and glyph order must remain intact. Invalid results fall back
    /// to the original metrics. Overflow is repaired before visual reordering.
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? measureLine,
    Iterable<int> hyphenationOffsets = const [],

    /// Optional width for the first line. When supplied, wrapping is greedy.
    double? firstLineWidth,
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
    // Wrap in logical order, then apply UAX #9 L2 per line. Reordering the
    // whole paragraph first inverts RTL wraps (logical start on a later line).
    final shaped = _logicalGlyphs(
      text,
      baseLevel,
      widthAt ?? (cp, _) => widthOf(cp),
      glyphIdAt ?? (cp, _) => glyphIdOf(cp),
    );
    final List<ShapedGlyph> logical = ligate == null ? shaped : ligate(shaped);
    if (logical.isEmpty) {
      return <BrokenLine>[];
    }
    final clusterStarts = {
      for (final cluster in GraphemeClusters.segment(text)) cluster.start,
    };
    final hyphens = _hyphenGlyphs(
      text,
      logical,
      hyphenationOffsets,
      clusterStarts,
      widthAt ?? (cp, _) => widthOf(cp),
      glyphIdAt ?? (cp, _) => glyphIdOf(cp),
    );
    final controls = _BreakControls.fromText(text, logical);

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
            firstLineWidth: lines.isEmpty ? firstLineWidth : null,
            spaceStretch: spaceStretch,
            spaceShrink: spaceShrink,
            justify: justify,
            markAttachOf: markAttachOf,
            clusterStarts: clusterStarts,
            hyphens: hyphens,
            controls: controls,
            breakLongWords: breakLongWords,
            balanceLines: balanceLines,
            measureLine: measureLine,
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
    double? firstLineWidth,
    required double spaceStretch,
    required double spaceShrink,
    required bool justify,
    MarkAttachFn? markAttachOf,
    required Set<int> clusterStarts,
    Map<int, ShapedGlyph> hyphens = const {},
    _BreakControls controls = _BreakControls.empty,
    bool breakLongWords = false,
    // False uses the longest fitting legal prefix, as Word does. The default
    // retains balanced paragraph breaking for PDF/report consumers.
    bool balanceLines = true,
    List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? measureLine,
  }) {
    final measurements = _LineMeasurements(
      logical,
      hyphens,
      clusterStarts,
      markAttachOf,
      measureLine,
    );
    final List<int> planned = balanceLines && firstLineWidth == null
        ? _knuthPlass(
            logical,
            maxWidth,
            spaceStretch,
            spaceShrink,
            hyphens,
            clusterStarts,
            controls,
          )
        : _greedyBreaks(
            logical,
            maxWidth,
            hyphens,
            clusterStarts,
            controls,
            measurements.at,
            firstLineWidth: firstLineWidth,
          );
    var breaks = !breakLongWords
        ? planned
        : _constrainBreaks(
            logical,
            planned,
            clusterStarts,
            maxWidth,
            hyphens,
            controls,
            firstLineWidth: firstLineWidth,
          );
    if (measureLine != null) {
      breaks = _refineBreaks(
        logical,
        breaks,
        clusterStarts,
        maxWidth,
        hyphens,
        controls,
        measurements.at,
        breakLongWords: breakLongWords,
        firstLineWidth: firstLineWidth,
      );
    }
    final List<BrokenLine> lines = <BrokenLine>[];
    for (int i = 0; i < breaks.length - 1; i++) {
      final int from = breaks[i];
      final measured = measurements.at(from, breaks[i + 1]);
      final to = measured.paintedTo;
      final slice = measured.glyphs;
      var width = measured.width;
      var spaces = 0;
      for (final ShapedGlyph g in slice) {
        if (g.isSpace) {
          spaces++;
        }
      }
      var ratio = 0.0;
      final limit = i == 0 ? firstLineWidth ?? maxWidth : maxWidth;
      if (justify && spaces > 0 && width < limit && i != breaks.length - 2) {
        ratio = (limit - width) / (spaces * spaceStretch);
        width = limit;
      }
      int logStart = 0x7fffffff;
      int logEnd = 0;
      for (final ShapedGlyph g in logical.sublist(from, to)) {
        if (g.logicalIndex < logStart) {
          logStart = g.logicalIndex;
        }
        final source = sourceText.codeUnitAt(g.logicalIndex);
        final units = source >= 0xD800 && source <= 0xDBFF ? 2 : 1;
        if (g.logicalIndex + units > logEnd) {
          logEnd = g.logicalIndex + units;
        }
      }
      if (to == from) {
        logStart = from < logical.length
            ? logical[from].logicalIndex
            : sourceText.length;
        logEnd = logStart;
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
    Map<int, ShapedGlyph> hyphens,
    _BreakControls controls, {
    double? firstLineWidth,
  }) {
    final boundaries = <int>[
      0,
      for (var i = 1; i < logical.length; i++)
        if (_isClusterBoundary(logical, i, clusterStarts, controls)) i,
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
        final limit = start == 0 ? firstLineWidth ?? maxWidth : maxWidth;
        var fitting = start;
        var natural = start;
        for (var next = start + 1; next <= end; next++) {
          final from = boundaries[start];
          final to = boundaries[next];
          final width =
              widths[math.max(from, paintedEnd[to])] -
              widths[from] +
              (_hyphenForBreak(logical, to, hyphens)?.advance ?? 0);
          if (width > limit + 0.000001) {
            // An indivisible glyph/cluster may itself be wider than the box.
            // Keep it whole and always make progress.
            if (fitting == start) fitting = next;
            break;
          }
          fitting = next;
          if (_canBreakAfter(
            logical,
            to - 1,
            hyphens,
            clusterStarts,
            controls,
          )) {
            natural = next;
          }
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

  static bool _isClusterBoundary(
    List<ShapedGlyph> logical,
    int at,
    Set<int> clusterStarts,
    _BreakControls controls,
  ) =>
      at == logical.length ||
      (at > 0 &&
          // All soft-break paths consume ordinary spaces with their preceding
          // line, including a host-measured oversized grapheme fallback.
          logical[at].codePoint != 0x0020 &&
          !controls.prohibits(logical[at].logicalIndex) &&
          clusterStarts.contains(logical[at].logicalIndex) &&
          logical[at].logicalIndex != logical[at - 1].logicalIndex &&
          // The continuation of a lam-alef ligature has no independent ink.
          logical[at].codePoint != 0);

  // Paragraph shaping is an estimate for a line: removing its neighbours can
  // change kerning or contextual forms. Verify the actual painted slice and
  // repair only overflowing planned intervals. Retaining the remaining plan
  // avoids making the paragraph optimiser quadratic in expensive host calls.
  static List<int> _refineBreaks(
    List<ShapedGlyph> logical,
    List<int> planned,
    Set<int> clusterStarts,
    double maxWidth,
    Map<int, ShapedGlyph> hyphens,
    _BreakControls controls,
    _MeasuredLine Function(int from, int to) measure, {
    required bool breakLongWords,
    double? firstLineWidth,
  }) {
    final boundaries = <int>[
      for (var at = 1; at <= logical.length; at++)
        if (_isClusterBoundary(logical, at, clusterStarts, controls)) at,
    ];
    final natural = <int>[
      for (final at in boundaries)
        if (_canBreakAfter(logical, at - 1, hyphens, clusterStarts, controls))
          at,
    ];
    int firstAfter(List<int> values, int value) {
      var low = 0;
      var high = values.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (values[mid] <= value) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return low;
    }

    final result = <int>[0];
    var plannedIndex = 1;
    var start = 0;
    while (start < logical.length) {
      final width = start == 0 ? firstLineWidth ?? maxWidth : maxWidth;
      while (planned[plannedIndex] <= start) {
        plannedIndex++;
      }
      final end = planned[plannedIndex];
      if (measure(start, end).width <= width + 0.000001) {
        result.add(end);
        start = end;
        continue;
      }

      // At most 32 candidate measurements per repair. Always include the
      // earliest candidate so a long paragraph still reaches a short prefix.
      int? fitting(List<int> candidates, int limit) {
        final first = firstAfter(candidates, start);
        final last = firstAfter(candidates, end - 1) - 1;
        var tested = 0;
        for (var at = last; at >= first; at--) {
          if (tested == limit - 1 && at > first) at = first;
          final cut = candidates[at];
          tested++;
          if (measure(start, cut).width <= width + 0.000001) return cut;
          if (tested >= limit) break;
        }
        return null;
      }

      var cut = fitting(natural, breakLongWords ? 16 : 32);
      if (cut == null && breakLongWords) {
        cut = fitting(boundaries, 16);
      }
      if (cut == null) {
        if (breakLongWords) {
          // A single oversized grapheme cannot fit, but must remain whole.
          cut = boundaries[firstAfter(boundaries, start)];
        } else {
          // Keep an indivisible word whole. A discretionary hyphen which no
          // longer fits is not a valid fallback; consume to the next ordinary
          // word boundary, even when it lies beyond the original plan.
          var next = firstAfter(natural, start);
          while (_hyphenForBreak(logical, natural[next], hyphens) != null) {
            next++;
          }
          cut = natural[next];
        }
      }
      result.add(cut);
      start = cut;
    }
    return result;
  }

  static List<ShapedGlyph> _reorderLine(
    List<ShapedGlyph> logicalSlice,
    MarkAttachFn? markAttachOf, [
    Set<int>? clusterStarts,
  ]) {
    var hasOddLevel = false;
    var hasMarks = false;
    for (final glyph in logicalSlice) {
      if (glyph.level.isOdd) {
        hasOddLevel = true;
        break;
      }
      hasMarks |= isCombiningMark(glyph.codePoint);
    }
    // UAX #9 L2 has no reversals when all embedding levels are even.
    if (!hasOddLevel) {
      return hasMarks
          ? _attachMarksToBases(logicalSlice, markAttachOf)
          : logicalSlice;
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
      final sameSource =
          clusters.isNotEmpty &&
          clusters.last.last.logicalIndex == glyph.logicalIndex;
      final continues =
          sameSource ||
          (clusterStarts == null
              ? isCombiningMark(glyph.codePoint)
              : !clusterStarts.contains(glyph.logicalIndex) ||
                    glyph.codePoint == 0);
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
    int? baseLevel,
    GlyphWidthAtFn widthOf,
    GlyphIdAtFn glyphIdOf,
  ) {
    final codePoints = text.runes.toList();
    final levels = Uax9Bidi.embeddingLevels(codePoints, baseLevel: baseLevel);
    final shaped = codePoints.any(ArabicShaper.mayNeedShaping)
        ? ArabicShaper.shapeCodePoints(codePoints)
        : null;
    final glyphs = <ShapedGlyph>[];
    var utf16 = 0;
    for (var i = 0; i < codePoints.length; i++) {
      final source = codePoints[i];
      final index = utf16;
      utf16 += source > 0xffff ? 2 : 1;
      if (Uax9Bidi.isInvisibleFormat(source)) continue;
      final level = levels[i];
      if (source == 0x00ad) {
        glyphs.add(
          ShapedGlyph(
            codePoint: source,
            glyphId: 0,
            advance: 0,
            logicalIndex: index,
            level: level,
          ),
        );
        continue;
      }

      final char = shaped?[i];
      var cp = char?.codePoint ?? source;
      final hasAdvance = char == null || char.advanceFactor != 0;
      // A consumed alef owns its source offset without painting a glyph.
      var gid = !hasAdvance && cp == 0 ? 0 : glyphIdOf(cp, index);
      if (shaped != null && gid == 0 && cp != 0) {
        final nominal = ArabicShaper.nominalOf(cp);
        if (nominal != null) {
          final nominalGlyph = glyphIdOf(nominal, index);
          if (nominalGlyph != 0) {
            cp = nominal;
            gid = nominalGlyph;
          }
        }
      }
      var advance = hasAdvance ? widthOf(cp, index) : 0.0;
      if (hasAdvance && advance <= 0 && gid != 0) {
        final space = widthOf(0x0020, index);
        advance = space > 0 ? space : 1;
      }
      glyphs.add(
        _l4Mirror(
          ShapedGlyph(
            codePoint: cp,
            glyphId: gid,
            advance: advance,
            logicalIndex: index,
            level: level,
            isSpace: _isBreakSpace(source),
          ),
          widthOf,
          glyphIdOf,
        ),
      );
    }
    return glyphs;
  }

  /// UAX #9 L4 after shaping: flip mirrored pairs on odd embedding levels.
  static ShapedGlyph _l4Mirror(
    ShapedGlyph g,
    GlyphWidthAtFn widthOf,
    GlyphIdAtFn glyphIdOf,
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
      glyphId: glyphIdOf(mirrored, g.logicalIndex),
      advance: widthOf(mirrored, g.logicalIndex),
      logicalIndex: g.logicalIndex,
      level: g.level,
      isSpace: g.isSpace,
      paintDx: g.paintDx,
    );
  }

  // Word consumes the longest fitting word prefix, rather than balancing the
  // raggedness of the whole paragraph. Prefix advances narrow the search;
  // actual line shaping and selected hyphens decide the final fit.
  static List<int> _greedyBreaks(
    List<ShapedGlyph> glyphs,
    double maxWidth,
    Map<int, ShapedGlyph> hyphens,
    Set<int> clusterStarts,
    _BreakControls controls,
    _MeasuredLine Function(int, int) measure, {
    double? firstLineWidth,
  }) {
    final n = glyphs.length;
    final widths = List<double>.filled(n + 1, 0);
    final legal = <int>[];
    for (var i = 0; i < n; i++) {
      widths[i + 1] = widths[i] + glyphs[i].advance;
      if (_canBreakAfter(glyphs, i, hyphens, clusterStarts, controls)) {
        legal.add(i + 1);
      }
    }
    if (legal.isEmpty || legal.last != n) legal.add(n);
    final points = <int>[0];
    var start = 0;
    var first = 0;
    while (start < n) {
      final limit = start == 0 ? firstLineWidth ?? maxWidth : maxWidth;
      while (legal[first] <= start) {
        first++;
      }
      double baseWidth(int to) {
        var end = to;
        while (end > start && _isSoftTrailingSpace(glyphs[end - 1])) {
          end--;
        }
        return widths[end] - widths[start];
      }

      var low = first;
      var high = legal.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (baseWidth(legal[mid]) <= limit + .000001) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      int? chosen;
      var chosenIndex = first - 1;
      for (
        var at = low - 1, tested = 0;
        at >= first && tested < 32;
        at--, tested++
      ) {
        if (measure(start, legal[at]).width <= limit + .000001) {
          chosen = legal[at];
          chosenIndex = at;
          break;
        }
      }
      // Contextual shaping can make the next prefix fit. A non-fitting
      // discretionary hyphen must not hide a fitting complete word.
      for (
        var at = math.max(first, chosenIndex + 1), tested = 0;
        at < legal.length && tested < 32;
        at++, tested++
      ) {
        if (measure(start, legal[at]).width <= limit + .000001) {
          chosen = legal[at];
          chosenIndex = at;
        } else if (_hyphenForBreak(glyphs, legal[at], hyphens) == null) {
          break;
        }
      }
      if (chosen == null) {
        var at = first;
        while (_hyphenForBreak(glyphs, legal[at], hyphens) != null) {
          at++;
        }
        chosen = legal[at]; // Retain a whole oversized word for the caller.
      }
      points.add(chosen);
      start = chosen;
    }
    return points;
  }

  static List<int> _knuthPlass(
    List<ShapedGlyph> glyphs,
    double maxWidth,
    double stretch,
    double shrink, [
    Map<int, ShapedGlyph> hyphens = const {},
    Set<int>? clusterStarts,
    _BreakControls controls = _BreakControls.empty,
  ]) {
    final int n = glyphs.length;
    final List<double> widths = List<double>.filled(n + 1, 0);
    for (int i = 0; i < n; i++) {
      widths[i + 1] = widths[i] + glyphs[i].advance;
    }
    final List<int> legal = <int>[0];
    for (int i = 0; i < n; i++) {
      if (_canBreakAfter(glyphs, i, hyphens, clusterStarts, controls)) {
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
        final hyphen = _hyphenForBreak(glyphs, to, hyphens);
        w += hyphen?.advance ?? 0;
        if (hyphen != null && w > maxWidth) continue;
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
        final double cost =
            demerits[i] +
            badness * badness * 100 +
            10 +
            (hyphen == null ? 0 : 50);
        if (cost < demerits[j]) {
          demerits[j] = cost;
          pred[j] = i;
        }
      }
      if (demerits[j].isInfinite &&
          _hyphenForBreak(glyphs, legal[j], hyphens) == null) {
        // An indivisible word may overflow; a discretionary hyphen that
        // does not fit is not a usable break. Keep its candidate unreachable.
        var previous = j - 1;
        while (previous > 0 && demerits[previous].isInfinite) {
          previous--;
        }
        demerits[j] = demerits[previous] + 10000;
        pred[j] = previous;
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

  static bool _canBreakAfter(
    List<ShapedGlyph> glyphs,
    int i, [
    Map<int, ShapedGlyph> hyphens = const {},
    Set<int>? clusterStarts,
    _BreakControls controls = _BreakControls.empty,
  ]) {
    final int cp = glyphs[i].codePoint;
    if (cp == 0x000A || cp == 0x000D) {
      return true;
    }
    if (i == glyphs.length - 1) {
      return true;
    }
    if (clusterStarts != null &&
        !_isClusterBoundary(glyphs, i + 1, clusterStarts, controls)) {
      return false;
    }
    if (controls.prohibits(glyphs[i + 1].logicalIndex)) return false;
    if (controls.opportunities.contains(glyphs[i + 1].logicalIndex)) {
      return true;
    }
    if (hyphens.containsKey(glyphs[i + 1].logicalIndex)) return true;
    final int next = glyphs[i + 1].codePoint;
    // A soft wrap owns the following ordinary spaces. In particular, a
    // hyphen followed by a space must not leave that space at the beginning
    // of the next line. Keep tabs and nonbreaking spaces distinct.
    if (next == 0x0020) return false;
    if (_isBreakSpace(cp)) {
      return true;
    }
    // UAX #14: BA, ZW, HY allow break after; GL/WJ forbid.
    if (cp == 0x200B || cp == 0x2010 || cp == 0x002D) {
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

  static Map<int, ShapedGlyph> _hyphenGlyphs(
    String text,
    List<ShapedGlyph> logical,
    Iterable<int> candidates,
    Set<int> clusterStarts,
    GlyphWidthAtFn widthAt,
    GlyphIdAtFn glyphIdAt,
  ) {
    if (candidates.isEmpty && !text.contains('\u00ad')) return const {};
    final offsets = candidates.toSet();
    for (final g in logical) {
      if (g.codePoint == 0x00ad) offsets.add(g.logicalIndex + 1);
    }
    final result = <int, ShapedGlyph>{};
    final bySource = {for (final g in logical) g.logicalIndex: g};
    for (final offset in offsets) {
      if (offset <= 0 ||
          offset >= text.length ||
          !clusterStarts.contains(offset) ||
          !bySource.containsKey(offset)) {
        continue;
      }
      final explicit = text.codeUnitAt(offset - 1) == 0x00ad;
      var owner = offset - 1;
      if (owner > 0 &&
          text.codeUnitAt(owner) >= 0xdc00 &&
          text.codeUnitAt(owner) <= 0xdfff) {
        owner--;
      }
      final prior = bySource[owner];
      final next = bySource[offset]!;
      if (prior == null ||
          prior.isSpace ||
          next.isSpace ||
          next.codePoint == 0x0a ||
          next.codePoint == 0x0d) {
        continue;
      }
      result[offset] = ShapedGlyph(
        codePoint: 0x2d,
        glyphId: glyphIdAt(0x2d, owner),
        advance: widthAt(0x2d, owner),
        logicalIndex: explicit ? offset - 1 : offset,
        level: prior.level,
        isDiscretionaryHyphen: true,
        sourceLength: explicit ? 1 : 0,
      );
    }
    return result;
  }

  static ShapedGlyph? _hyphenForBreak(
    List<ShapedGlyph> logical,
    int to,
    Map<int, ShapedGlyph> hyphens,
  ) => to < logical.length ? hyphens[logical[to].logicalIndex] : null;

  static List<ShapedGlyph> _paintSlice(
    List<ShapedGlyph> logical,
    int from,
    int paintedTo,
    int consumedTo,
    Map<int, ShapedGlyph> hyphens,
  ) => [
    for (var at = from; at < paintedTo; at++)
      if (logical[at].codePoint != 0x00ad) logical[at],
    ?_hyphenForBreak(logical, consumedTo, hyphens),
  ];

  static bool _isBreakSpace(int cp) =>
      cp == 0x0020 || cp == 0x0009 || cp == 0x2000 || cp == 0x3000;

  static bool _isSoftTrailingSpace(ShapedGlyph glyph) =>
      glyph.isSpace && glyph.codePoint != 0x09;

  /// cp API.
  static int _identityGlyph(int cp) => cp;
}

// Bidi formatting controls do not paint, but some carry line-break semantics.
// Preserve these constraints separately from the visible glyph list so host
// shaping, source offsets and caret ownership keep their existing contracts.
// UAX #14 LB8 permits a break after ZWSP and following ordinary spaces; LB11
// prohibits a break around WJ/ZWNBSP. An explicit ZWSP opportunity wins (LB8).
class _BreakControls {
  const _BreakControls._(this.opportunities, this._prohibited);

  static const empty = _BreakControls._({}, {});
  final Set<int> opportunities;
  final Set<int> _prohibited;

  bool prohibits(int offset) =>
      _prohibited.contains(offset) && !opportunities.contains(offset);

  static _BreakControls fromText(String text, List<ShapedGlyph> logical) {
    if (!text.contains('\u200b') &&
        !text.contains('\u2060') &&
        !text.contains('\ufeff')) {
      return empty;
    }
    final sources = {for (final glyph in logical) glyph.logicalIndex};
    final opportunities = <int>{};
    final prohibited = <int>{};
    int? nextGlyph;
    int? afterSpaces;
    for (var at = text.length - 1; at >= 0; at--) {
      final unit = text.codeUnitAt(at);
      if (sources.contains(at)) {
        nextGlyph = at;
        if (unit != 0x20) afterSpaces = at;
      } else if (unit == 0x200b) {
        // Omitted directional controls may share the same visible boundary.
        // Ordinary trailing spaces stay with the preceding line as elsewhere.
        if (afterSpaces != null) opportunities.add(afterSpaces);
      } else if (unit == 0x2060 || unit == 0xfeff) {
        if (nextGlyph != null) prohibited.add(nextGlyph);
      }
    }
    return _BreakControls._(opportunities, prohibited);
  }
}

class _MeasuredLine {
  const _MeasuredLine(this.paintedTo, this.glyphs, this.width);

  final int paintedTo;
  final List<ShapedGlyph> glyphs;
  final double width;
}

// Cache values only within this prepared paragraph/chunk. Candidate repairs
// and final emission share the exact same measurement; repeated frame retries
// do not retain an unbounded number of host-shaped slices.
class _LineMeasurements {
  _LineMeasurements(
    this.logical,
    this.hyphens,
    this.clusterStarts,
    this.markAttach,
    this.measureLine,
  );

  final List<ShapedGlyph> logical;
  final Map<int, ShapedGlyph> hyphens;
  final Set<int> clusterStarts;
  final MarkAttachFn? markAttach;
  final List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? measureLine;
  final Map<(int, int), _MeasuredLine> _cache = {};
  var _cachedGlyphs = 0;
  static const _maxEntries = 128;
  static const _maxGlyphs = 32768;

  _MeasuredLine at(int from, int to) {
    final key = (from, to);
    final cached = _cache[key];
    if (cached != null) return cached;
    var painted = to;
    while (painted > from &&
        LineBreaker._isSoftTrailingSpace(logical[painted - 1])) {
      painted--;
    }
    var slice = LineBreaker._paintSlice(logical, from, painted, to, hyphens);
    final callback = measureLine;
    if (callback != null && slice.isNotEmpty) {
      final measured = callback(List<ShapedGlyph>.unmodifiable(slice));
      if (_validMetrics(slice, measured)) {
        // Do not retain a mutable list owned by a host callback.
        slice = List<ShapedGlyph>.of(measured);
      }
    }
    final visual = LineBreaker._reorderLine(slice, markAttach, clusterStarts);
    final width = visual.fold<double>(0, (sum, glyph) => sum + glyph.advance);
    final value = _MeasuredLine(painted, visual, width);
    if (visual.length <= _maxGlyphs) {
      while (_cache.isNotEmpty &&
          (_cache.length >= _maxEntries ||
              _cachedGlyphs + visual.length > _maxGlyphs)) {
        final oldest = _cache.keys.first;
        _cachedGlyphs -= _cache.remove(oldest)!.glyphs.length;
      }
      _cache[key] = value;
      _cachedGlyphs += visual.length;
    }
    return value;
  }

  static bool _validMetrics(
    List<ShapedGlyph> original,
    List<ShapedGlyph> measured,
  ) {
    if (original.length != measured.length) return false;
    var total = 0.0;
    for (var at = 0; at < original.length; at++) {
      final before = original[at];
      final after = measured[at];
      if (!after.advance.isFinite ||
          after.advance < 0 ||
          before.codePoint != after.codePoint ||
          before.glyphId != after.glyphId ||
          before.logicalIndex != after.logicalIndex ||
          before.level != after.level ||
          before.isSpace != after.isSpace ||
          before.isDiscretionaryHyphen != after.isDiscretionaryHyphen ||
          before.sourceLength != after.sourceLength ||
          before.paintDx != after.paintDx ||
          before.paintDy != after.paintDy) {
        return false;
      }
      total += after.advance;
    }
    return total.isFinite;
  }
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
    this._hyphens,
    this._controls,
    this._clusterStarts,
    this._measureLine,
    this._breakLongWords,
    this._balanceLines,
  );

  final String _text;
  final List<ShapedGlyph> _logical;
  final double _stretch;
  final double _shrink;
  final bool _justify;
  final MarkAttachFn? _markAttach;
  final Map<int, ShapedGlyph> _hyphens;
  final _BreakControls _controls;
  final Set<int> _clusterStarts;
  final List<ShapedGlyph> Function(List<ShapedGlyph> glyphs)? _measureLine;
  final bool _breakLongWords;
  final bool _balanceLines;
  late final _measurements = _LineMeasurements(
    _logical,
    _hyphens,
    _clusterStarts,
    _markAttach,
    _measureLine,
  );
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
      var points = _balanceLines
          ? LineBreaker._knuthPlass(
              chunk,
              maxWidth,
              _stretch,
              _shrink,
              _hyphens,
              _clusterStarts,
              _controls,
            )
          : LineBreaker._greedyBreaks(
              chunk,
              maxWidth,
              _hyphens,
              _clusterStarts,
              _controls,
              (a, b) => _measurements.at(from + a, from + b),
            );
      if (_breakLongWords) {
        points = LineBreaker._constrainBreaks(
          chunk,
          points,
          _clusterStarts,
          maxWidth,
          _hyphens,
          _controls,
        );
      }
      if (_measureLine != null) {
        points = LineBreaker._refineBreaks(
          chunk,
          points,
          _clusterStarts,
          maxWidth,
          _hyphens,
          _controls,
          (a, b) => _measurements.at(from + a, from + b),
          breakLongWords: _breakLongWords,
        );
      }
      // The optimal suffix remains valid until the available width changes.
      // Reuse it instead of recomputing a whole paragraph for every line.
      for (var i = 0; i + 1 < points.length; i++) {
        _plannedBreaks[from + points[i]] = from + points[i + 1];
      }
    }
    final consumed = _plannedBreaks[from]! - from;
    final measured = _measurements.at(from, from + consumed);
    final painted = measured.paintedTo - from;
    final glyphs = measured.glyphs;
    var width = measured.width;
    var spaces = 0;
    var logicalStart = _text.length;
    var logicalEnd = start;
    for (final glyph in glyphs) {
      if (glyph.isSpace) spaces++;
    }
    for (final glyph in chunk.take(painted)) {
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
        logicalStart: painted == 0 ? start : logicalStart,
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
