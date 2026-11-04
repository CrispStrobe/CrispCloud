/// One misspelled span the host can underline or offer replacements for.
class OfficeSpellIssue {
  /// OfficeSpellIssue API.
  const OfficeSpellIssue({
    required this.start,
    required this.end,
    required this.word,
    this.suggestions = const <String>[],
  });

  /// start API.
  final int start;

  /// end API.
  final int end;

  /// word API.
  final String word;

  /// suggestions API.
  final List<String> suggestions;
}

/// Host-supplied dictionary / service. The engine never ships a full lexicon.
typedef OfficeSpellChecker = List<OfficeSpellIssue> Function(String text);

/// Walks words and asks [checker] — or a tiny built-in Latin/Arabic split.
abstract final class OfficeSpell {
  /// check API.
  static List<OfficeSpellIssue> check(
    String text, {
    OfficeSpellChecker? checker,
    Set<String> known = const <String>{},
  }) {
    if (checker != null) {
      return checker(text);
    }
    if (known.isEmpty) {
      return const <OfficeSpellIssue>[];
    }
    final List<OfficeSpellIssue> issues = <OfficeSpellIssue>[];
    final RegExp word = RegExp(r'[\p{L}\p{N}]+', unicode: true);
    for (final Match match in word.allMatches(text)) {
      final String token = match.group(0)!;
      if (!known.contains(token.toLowerCase()) &&
          !known.contains(token)) {
        issues.add(
          OfficeSpellIssue(start: match.start, end: match.end, word: token),
        );
      }
    }
    return issues;
  }
}
