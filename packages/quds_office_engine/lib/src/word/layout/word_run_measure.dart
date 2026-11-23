part of 'word_layout.dart';

/// Advance of a shaped source cluster, in points, over UTF-16 [start]..[end].
///
/// A measurement covers its input consecutively with nonnegative, finite
/// advances, one extended source grapheme per range. A host that cannot assign
/// individual grapheme advances for a multi-grapheme ligature must decline the
/// run. The line breaker retains its existing source-grapheme break policy.
class WordMeasuredCluster {
  const WordMeasuredCluster({
    required this.start,
    required this.end,
    required this.advance,
  });

  final int start;
  final int end;
  final double advance;
}

/// Measures original logical text in one font/style and bidi embedding level.
///
/// Hosts implement this in their painting layer; the engine has no Flutter or
/// native dependency. [sizePoints] already includes superscript/small-cap scale.
/// Return null to retain the scalar fallback. Metrics describe the whole input
/// context: a line break inside a word may require separate shaping in a more
/// complete backend. This callback does not supply exportable glyph outlines.
typedef WordRunMeasure =
    List<WordMeasuredCluster>? Function(
      String text,
      double sizePoints,
      WmlRunProps props,
      int bidiLevel,
    );

int _sourceCodePoint(String text, int offset) {
  final first = text.codeUnitAt(offset);
  if (first >= 0xd800 && first <= 0xdbff && offset + 1 < text.length) {
    final second = text.codeUnitAt(offset + 1);
    if (second >= 0xdc00 && second <= 0xdfff) {
      return 0x10000 + ((first - 0xd800) << 10) + second - 0xdc00;
    }
  }
  return first;
}

// Validate the complete result before replacing any fallback advances. A host
// returning a partial range or NaN must not corrupt line widths/pagination.
List<double>? _clusterAdvances(
  String text,
  List<int> offsets,
  List<WordMeasuredCluster>? measured,
) {
  if (measured == null || measured.isEmpty || measured.length > text.length) {
    return null;
  }
  final graphemes = GraphemeClusters.segment(text);
  if (measured.length != graphemes.length) return null;
  var end = 0;
  var total = 0.0;
  for (var i = 0; i < measured.length; i++) {
    final cluster = measured[i];
    if (cluster.start != end ||
        cluster.end <= cluster.start ||
        cluster.end > text.length ||
        cluster.end != graphemes[i].end ||
        !cluster.advance.isFinite ||
        cluster.advance < 0 ||
        (text.substring(cluster.start, cluster.end) == '\u00ad' &&
            cluster.advance != 0)) {
      return null;
    }
    total += cluster.advance;
    end = cluster.end;
  }
  if (end != text.length || !total.isFinite) return null;
  final advances = List<double>.filled(offsets.length, 0);
  var index = 0;
  for (final cluster in measured) {
    while (index < offsets.length && offsets[index] < cluster.start) {
      index++;
    }
    if (index == offsets.length || offsets[index] >= cluster.end) {
      // Invisible formatting can have no glyph, but must not own an advance.
      if (cluster.advance != 0) return null;
      continue;
    }
    advances[index] = cluster.advance;
    while (index < offsets.length && offsets[index] < cluster.end) {
      index++;
    }
  }
  return advances;
}

ShapedGlyph _withMeasuredAdvance(ShapedGlyph glyph, double advance) =>
    ShapedGlyph(
      codePoint: glyph.codePoint,
      glyphId: glyph.glyphId,
      advance: advance,
      logicalIndex: glyph.logicalIndex,
      level: glyph.level,
      isSpace: glyph.isSpace,
      paintDx: glyph.paintDx,
      paintDy: glyph.paintDy,
      isDiscretionaryHyphen: glyph.isDiscretionaryHyphen,
      sourceLength: glyph.sourceLength,
    );

/// Source formatting ranges for one paragraph layout. Lookups use the same
/// UTF-16 offsets as editing, including the last run's formatting at the end.
class _LayoutRunIndex {
  _LayoutRunIndex(WmlParagraph paragraph) {
    var offset = 0;
    var breaks = 0;
    for (final inline in paragraph.inlines) {
      if (inline is WmlBreak) {
        breaks++;
      } else if (inline is WmlRun) {
        if (inline.noteRefId case final id? when !inline.noteRefEndnote) {
          _noteReferences.add((offset + breaks, id));
        }
        offset += inline.text.length;
        _ends.add(offset);
        _runs.add(inline);
        _lastLink = inline.hyperlink ?? _lastLink;
      }
    }
  }

  final _noteReferences = <(int, int)>[];
  final _ends = <int>[];
  final _runs = <WmlRun>[];
  final _commentKeys = <WmlRun, String>{};
  WmlHyperlink? _lastLink;
  late final _fallback = WmlRunProps();
  var _lastIndex = 0;

  WmlRun? at(int offset) {
    if (_runs.isEmpty) return null;
    if (offset >= _ends.last) return _runs.last;
    final current = _lastIndex;
    if (offset < _ends[current] &&
        (current == 0 || offset >= _ends[current - 1])) {
      return _runs[current];
    }
    var low = 0;
    var high = _ends.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (offset < _ends[mid]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    _lastIndex = low;
    return _runs[low];
  }

  WmlRunProps propsAt(int offset) => at(offset)?.properties ?? _fallback;

  WmlHyperlink? linkAt(int offset, WmlRun? run) =>
      _ends.isNotEmpty && offset >= _ends.last ? _lastLink : run?.hyperlink;

  List<int> footnoteIds(Iterable<int> offsets) {
    if (_noteReferences.isEmpty) return const [];
    final positions = offsets.toSet();
    return [
      for (final (offset, id) in _noteReferences)
        if (positions.contains(offset)) id,
    ];
  }

  String commentKey(WmlRun? run) => run == null || run.commentIds.isEmpty
      ? ''
      : _commentKeys.putIfAbsent(run, () => run.commentIds.join(','));
}

List<ShapedGlyph> _measureWordRuns({
  required List<ShapedGlyph> glyphs,
  required String text,
  required _LayoutRunIndex runIndex,
  required Map<int, ({String text, int end, double scale, bool note})> labels,
  required Set<int> pictures,
  required WordRunMeasure measure,
}) {
  final result = List<ShapedGlyph>.of(glyphs);
  bool separator(ShapedGlyph glyph) =>
      glyph.isDiscretionaryHyphen ||
      glyph.codePoint == 0x09 ||
      glyph.codePoint == 0x0a ||
      glyph.codePoint == 0x0d ||
      pictures.contains(glyph.logicalIndex);
  Object styleKey(ShapedGlyph glyph) {
    final run = runIndex.at(glyph.logicalIndex);
    final props = run?.properties ?? runIndex._fallback;
    return (
      OfficeTypeface.familyForRun(
        props,
        glyph.codePoint == 0 && !labels.containsKey(glyph.logicalIndex)
            ? _sourceCodePoint(text, glyph.logicalIndex)
            : glyph.codePoint,
      ),
      props.fontSizeHalfPoints,
      props.kerningHalfPoints,
      props.bold,
      props.italic,
      props.color,
      props.underline,
      props.strike,
      WmlHighlight.toRgb(props.highlight) ?? props.highlight,
      props.vertAlign,
      props.positionHalfPoints,
      runIndex.commentKey(run),
      glyph.level,
    );
  }

  var start = 0;
  while (start < glyphs.length) {
    final first = glyphs[start];
    if (separator(first)) {
      start++;
      continue;
    }
    final label = labels[first.logicalIndex];
    final key = styleKey(first);
    var end = start + 1;
    while (end < glyphs.length && !separator(glyphs[end])) {
      final next = glyphs[end];
      if (label != null) {
        if (next.logicalIndex != first.logicalIndex) break;
      } else if (labels.containsKey(next.logicalIndex) ||
          styleKey(next) != key) {
        break;
      }
      end++;
    }
    final props = runIndex.propsAt(first.logicalIndex);
    final String runText;
    final offsets = <int>[];
    if (label != null) {
      runText = label.text;
      var offset = 0;
      for (var i = start; i < end; i++) {
        offsets.add(offset);
        offset += glyphs[i].codePoint > 0xffff ? 2 : 1;
      }
    } else {
      final last = glyphs[end - 1];
      final sourceEnd =
          last.logicalIndex +
          (_sourceCodePoint(text, last.logicalIndex) > 0xffff ? 2 : 1);
      runText = text.substring(first.logicalIndex, sourceEnd);
      for (var i = start; i < end; i++) {
        offsets.add(glyphs[i].logicalIndex - first.logicalIndex);
      }
    }
    if (runText.isNotEmpty) {
      final measured = measure(
        runText,
        props.fontSizePoints * props.vertAlign.fontScale * (label?.scale ?? 1),
        props,
        first.level,
      );
      final advances = _clusterAdvances(runText, offsets, measured);
      if (advances != null) {
        for (var i = start; i < end; i++) {
          result[i] = _withMeasuredAdvance(glyphs[i], advances[i - start]);
        }
      }
    }
    start = end;
  }
  return result;
}
