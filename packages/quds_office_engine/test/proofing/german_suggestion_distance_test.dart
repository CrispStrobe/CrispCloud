import 'dart:math';

import 'package:quds_office_engine/src/proofing/german_suggestion_distance.dart';
import 'package:test/test.dart';

int _reference(String source, String target) {
  final costs = List.generate(
    source.length + 1,
    (row) => List.generate(target.length + 1, (column) => row + column),
  );
  for (var i = 1; i <= source.length; i++) {
    for (var j = 1; j <= target.length; j++) {
      final from = source.codeUnitAt(i - 1);
      final to = target.codeUnitAt(j - 1);
      var cost = min(
        costs[i - 1][j - 1] + (from == to ? 0 : 1),
        min(costs[i - 1][j] + 1, costs[i][j - 1] + 1),
      );
      if (i > 1 &&
          j > 1 &&
          from == target.codeUnitAt(j - 2) &&
          source.codeUnitAt(i - 2) == to) {
        cost = min(cost, costs[i - 2][j - 2] + 1);
      }
      costs[i][j] = cost;
    }
  }
  return costs.last.last;
}

void main() {
  test('reused rows agree with the reference across alternating bands', () {
    final distance = GermanSuggestionDistance();
    final random = Random(736);
    const alphabet = 'abcdäöèß';
    String word(int length) => List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();

    for (var iteration = 0; iteration < 12000; iteration++) {
      final source = word(1 + random.nextInt(80));
      var target = source;
      for (var edit = random.nextInt(5); edit > 0; edit--) {
        final offset = random.nextInt(target.length + 1);
        final end = min(target.length, offset + random.nextInt(3));
        target = target.replaceRange(offset, end, word(random.nextInt(3)));
      }
      if (target.isEmpty) continue;
      final limit = 1 + iteration % 2;
      final expected = _reference(source, target);
      final actual = distance.measure(source, target, limit: limit);
      expect(min(actual, limit + 1), min(expected, limit + 1));
    }
  });

  test('transpositions survive both early exits and row growth', () {
    final distance = GermanSuggestionDistance();
    final prefix = 'ö' * 90;
    for (var iteration = 0; iteration < 30; iteration++) {
      expect(distance.measure('Wort', 'xyz', limit: 1), greaterThan(1));
      expect(distance.measure('Wort', 'Wrot', limit: 1), 1);
      expect(distance.measure('${prefix}au', '${prefix}ua'), 1);
      expect(distance.measure('Cafè', 'Café', limit: 1), 1);
    }
  });
}
