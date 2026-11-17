/// Source ranges that language checks and automatic hyphenation leave alone.
///
/// HTTP(S) links, email addresses and closed backtick spans are protected.
/// Coordinates are original UTF-16 offsets; the source is never rewritten.
/// This is a conservative prose convention, not a Markdown or URI parser.
final class OfficeProofingTextRanges {
  OfficeProofingTextRanges(String text) : sourceLength = text.length {
    final spans = <({int start, int end})>[];
    for (final match in _links.allMatches(text)) {
      final end = _urlStart.hasMatch(match.group(0)!)
          ? _urlEnd(text, match.start, match.end)
          : match.end;
      spans.add((start: match.start, end: end));
    }

    // Pair runs of equal delimiter length. Precomputed next matches avoid
    // repeatedly searching the remaining paragraph after unmatched openers.
    // A matched outer span owns any differently sized delimiters inside it.
    final ticks = _backticks.allMatches(text).toList(growable: false);
    final next = List<int>.filled(ticks.length, -1);
    final lastByLength = <int, int>{};
    for (var i = ticks.length - 1; i >= 0; i--) {
      final length = ticks[i].end - ticks[i].start;
      next[i] = lastByLength[length] ?? -1;
      lastByLength[length] = i;
    }
    for (var i = 0; i < ticks.length; i++) {
      final close = next[i];
      if (close < 0) continue;
      spans.add((start: ticks[i].start, end: ticks[close].end));
      i = close;
    }
    spans.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[];
    for (final span in spans) {
      if (merged.isNotEmpty && span.start <= merged.last.end) {
        final previous = merged.removeLast();
        merged.add((
          start: previous.start,
          end: span.end > previous.end ? span.end : previous.end,
        ));
      } else {
        merged.add(span);
      }
    }
    ranges = List.unmodifiable(merged);
  }

  final int sourceLength;

  /// Sorted, disjoint, immutable half-open ranges in the original source.
  late final List<({int start, int end})> ranges;

  static final RegExp _links = RegExp(
    r'(?:https?://|www\.)[^\s<>\u0022\u0060]+|'
    r"(?<![\p{L}\p{M}\p{N}._%+'-])[\p{L}\p{M}\p{N}._%+'-]+@[\p{L}\p{M}\p{N}.-]+\.[\p{L}\p{M}]{2,}",
    unicode: true,
    caseSensitive: false,
  );
  static final RegExp _urlStart = RegExp(
    r'^(?:https?://|www\.)',
    caseSensitive: false,
  );
  static final RegExp _backticks = RegExp(r'`+');

  static int _urlEnd(String text, int start, int end) {
    const pairs = <String, String>{')': '(', ']': '[', '}': '{'};
    final counts = <String, int>{};
    for (var i = start; i < end; i++) {
      final char = text[i];
      if ('()[]{}'.contains(char)) {
        counts[char] = (counts[char] ?? 0) + 1;
      }
    }
    while (end > start) {
      final char = text[end - 1];
      if (".,;:!?'“”‘’«»".contains(char)) {
        end--;
        continue;
      }
      final opening = pairs[char];
      if (opening != null && (counts[char] ?? 0) > (counts[opening] ?? 0)) {
        counts[char] = counts[char]! - 1;
        end--;
        continue;
      }
      break;
    }
    return end;
  }

  /// Whether a finding or word intersects protected text, in O(log n).
  /// An insertion is protected at a range's start or interior, not its end.
  bool overlaps(int start, int end) {
    if (start < 0 || end < start || end > sourceLength) {
      throw RangeError('Invalid source range: $start..$end');
    }
    var lower = 0;
    var upper = ranges.length;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      if (ranges[middle].end <= start) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    return lower < ranges.length &&
        (start == end
            ? ranges[lower].start <= start
            : ranges[lower].start < end);
  }
}
