/// Ranking shared by command surfaces. Every query word must match; exact and
/// prefix matches win over abbreviations. An empty query preserves menu order.
int? commandSearchScore(String query, String label, {String keywords = ''}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return 0;
  final title = label.toLowerCase();
  final haystack = '$title ${keywords.toLowerCase()}';
  if (title == needle) return 10000;
  if (title.startsWith(needle)) return 9000 - title.length;
  if (title.contains(needle)) return 8000 - title.indexOf(needle);
  final words = haystack
      .split(RegExp(r'[\s+_\-/]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  var score = 0;
  for (final token in needle.split(RegExp(r'\s+'))) {
    if (words.any((word) => word == token)) {
      score += 400;
      continue;
    }
    if (words.any((word) => word.startsWith(token))) {
      score += 300;
      continue;
    }
    if (haystack.contains(token)) {
      score += 200;
      continue;
    }
    // Keep one-character searches precise; longer abbreviations can skip
    // characters within a word, but may not hop across unrelated commands.
    if (token.length < 2) return null;
    int? best;
    for (final word in words) {
      var position = 0;
      var skipped = 0;
      var matched = true;
      for (final rune in token.runes) {
        final next = word.indexOf(String.fromCharCode(rune), position);
        if (next < 0) {
          matched = false;
          break;
        }
        skipped += next - position;
        position = next + 1;
      }
      if (matched && (best == null || skipped < best)) best = skipped;
    }
    if (best == null) return null;
    score += 100 - best.clamp(0, 90);
  }
  return score;
}
