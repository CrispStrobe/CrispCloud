/// Banded optimal-string-alignment distance for spelling suggestions.
/// Distances within the limit are exact. The ordinary two-edit search
/// evaluates at most five cells per source code unit.
final class GermanSuggestionDistance {
  // Normal dictionary candidates are at most 66 UTF-16 code units.
  static const _dictionaryRowSize = 67;
  var _initialRow = List<int>.filled(_dictionaryRowSize, 0);
  var _nextRow = List<int>.filled(_dictionaryRowSize, 0);
  var _scratchRow = List<int>.filled(_dictionaryRowSize, 0);

  void _resize(int size) {
    _initialRow = List<int>.filled(size, 0);
    _nextRow = List<int>.filled(size, 0);
    _scratchRow = List<int>.filled(size, 0);
  }

  int measure(String source, String target, {int limit = 2}) {
    if ((source.length - target.length).abs() > limit) return limit + 1;
    if (source == target) return 0;
    final int beyond = limit + 1;
    if (target.length >= _initialRow.length) {
      _resize(target.length + 1);
    }
    var previousPrevious = _scratchRow;
    var previous = _initialRow;
    var current = _nextRow;
    // The first source row reads at most one cell past the active band.
    // Reset that sentinel as well because the previous search may have
    // used a different limit or returned before rotating all three rows.
    for (
      var column = 0;
      column <= target.length && column <= limit + 1;
      column++
    ) {
      previous[column] = column <= limit ? column : beyond;
    }
    for (int i = 1; i <= source.length; i++) {
      final int start = i > limit ? i - limit : 1;
      final int end = i + limit < target.length ? i + limit : target.length;
      // Only the neighboring cells can be read from outside the band.
      current[start - 1] = i <= limit ? i : beyond;
      if (end < target.length) current[end + 1] = beyond;
      int best = beyond;
      final int sourceUnit = source.codeUnitAt(i - 1);
      for (int j = start; j <= end; j++) {
        final int targetUnit = target.codeUnitAt(j - 1);
        final int substitution =
            previous[j - 1] + (sourceUnit == targetUnit ? 0 : 1);
        final int insertion = current[j - 1] + 1;
        final int deletion = previous[j] + 1;
        int cost = substitution < insertion ? substitution : insertion;
        if (deletion < cost) cost = deletion;
        if (i > 1 &&
            j > 1 &&
            sourceUnit == target.codeUnitAt(j - 2) &&
            source.codeUnitAt(i - 2) == targetUnit) {
          final int transposition = previousPrevious[j - 2] + 1;
          if (transposition < cost) cost = transposition;
        }
        current[j] = cost;
        if (cost < best) best = cost;
      }
      if (best > limit) return beyond;
      final List<int> reusable = previousPrevious;
      previousPrevious = previous;
      previous = current;
      current = reusable;
    }
    return previous[target.length];
  }
}
