import 'package:characters/characters.dart';

import 'office_proofing.dart';

Set<int> _sourceGraphemeBoundaries(String text) {
  final Set<int> boundaries = <int>{0};
  int end = 0;
  for (final String cluster in text.characters) {
    end += cluster.length;
    boundaries.add(end);
  }
  return boundaries;
}

/// Seven independently authored writing checks; not a general grammar parser.
/// Findings are advisory and never rewrite text. Unbalanced quotes can be valid
/// across paragraph boundaries and are explicitly described as review items.
/// A pattern with an endpoint inside a source grapheme is omitted rather than
/// offering a partial range or widening a replacement over adjacent marks.
class GermanWritingRulesProvider extends OfficeProofingProvider {
  bool _disposed = false;
  @override
  String get id => 'german-writing';
  @override
  bool supportsLanguage(String language) => const <String>{
    'de-DE',
    'de-AT',
    'de-CH',
  }.contains(normalizeProofingLanguage(language));
  static const Set<String> ruleIds = <String>{
    'de.spacing.repeated',
    'de.spacing.before-punctuation',
    'de.spacing.after-punctuation',
    'de.repetition.conjunction',
    'de.grammar.pronoun-verb',
    'de.delimiter.balance',
    'de.quote.balance',
  };
  static final RegExp _letterBefore = RegExp(r'[\p{L}\p{M}]$', unicode: true);
  static final RegExp _letterAfter = RegExp(r'^\p{L}', unicode: true);
  static final RegExp _protectedTokens = RegExp(
    r'(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}|`[^`]*`',
    caseSensitive: false,
  );
  static final RegExp _urlStart = RegExp(
    r'^(?:https?://|www\.)',
    caseSensitive: false,
  );

  static List<({int start, int end})> _protectedRanges(String text) {
    final List<({int start, int end})> ranges = <({int start, int end})>[];
    for (final RegExpMatch match in _protectedTokens.allMatches(text)) {
      int end = match.end;
      if (_urlStart.hasMatch(match.group(0)!)) {
        // A URL may contain balanced parentheses (or an IPv6 host). Keep those
        // protected, but leave surrounding prose punctuation to the balance
        // checks: (https://example.invalid/path) and „https://example.invalid“.
        const Map<String, String> closingBrackets = <String, String>{
          ')': '(',
          ']': '[',
          '}': '{',
        };
        final Map<String, int> counts = <String, int>{};
        for (int i = match.start; i < end; i++) {
          final String char = text[i];
          if ('()[]{}'.contains(char)) {
            counts[char] = (counts[char] ?? 0) + 1;
          }
        }
        while (end > match.start) {
          final String char = text[end - 1];
          if ('.,;:!?“”‘’«»'.contains(char)) {
            end--;
            continue;
          }
          final String? opening = closingBrackets[char];
          if (opening != null && (counts[char] ?? 0) > (counts[opening] ?? 0)) {
            counts[char] = counts[char]! - 1;
            end--;
            continue;
          }
          break;
        }
      }
      ranges.add((start: match.start, end: end));
    }
    return ranges;
  }

  static final RegExp _comparisonPrefix = RegExp(
    r'(?<![\p{L}\p{M}])(?:wie|als)[ \t\u00a0]+$',
    caseSensitive: false,
    unicode: true,
  );

  static bool _hasLetterBefore(String text, int offset) =>
      offset > 0 &&
      _letterBefore.hasMatch(
        text.substring(offset > 1 ? offset - 2 : 0, offset),
      );

  static bool _hasLetterAfter(String text, int offset) =>
      offset + 1 < text.length &&
      _letterAfter.hasMatch(
        text.substring(
          offset + 1,
          offset + 3 < text.length ? offset + 3 : text.length,
        ),
      );

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || !supportsLanguage(request.language)) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: _disposed
            ? OfficeProofingStatus.unavailable
            : OfficeProofingStatus.unsupported,
        message: _disposed
            ? 'German writing provider is disposed.'
            : 'German writing checks support de-DE, de-AT and de-CH.',
      );
    }
    final String text = request.text;
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];
    final Set<int> boundaries = _sourceGraphemeBoundaries(request.text);
    final List<({int start, int end})> protected = _protectedRanges(text);
    bool isProtected(int start, int end) {
      int lower = 0;
      int upper = protected.length;
      while (lower < upper) {
        final int middle = (lower + upper) ~/ 2;
        if (protected[middle].end <= start) {
          lower = middle + 1;
        } else {
          upper = middle;
        }
      }
      return lower < protected.length && protected[lower].start < end;
    }

    void add(
      String ruleId,
      int start,
      int end,
      String message, {
      OfficeProofingCategory category = OfficeProofingCategory.style,
      List<String> replacements = const <String>[],
    }) {
      if (!boundaries.contains(start) ||
          !boundaries.contains(end) ||
          request.ignoredRuleIds.contains(ruleId) ||
          isProtected(start, end == start ? end + 1 : end)) {
        return;
      }
      findings.add(
        OfficeProofingFinding.forRequest(
          request,
          providerId: id,
          start: start,
          end: end,
          ruleId: ruleId,
          message: message,
          category: category,
          replacements: replacements,
        ),
      );
    }

    for (final RegExpMatch m in RegExp(
      r'(?<=\S) {2,}(?=\S)',
    ).allMatches(text)) {
      if (RegExp(r'\d').hasMatch(text[m.start - 1]) &&
          RegExp(r'\d').hasMatch(text[m.end])) {
        continue;
      }
      add(
        'de.spacing.repeated',
        m.start,
        m.end,
        'Mehrere Leerzeichen zwischen Wörtern prüfen.',
        replacements: <String>[' '],
      );
    }
    for (final RegExpMatch m in RegExp(r' +(?=[,;:!?])').allMatches(text)) {
      add(
        'de.spacing.before-punctuation',
        m.start,
        m.end,
        'Vor diesem Satzzeichen steht normalerweise kein Leerzeichen.',
        replacements: <String>[''],
      );
    }
    for (final RegExpMatch m in RegExp(
      r'[,;](?=\p{L})',
      unicode: true,
    ).allMatches(text)) {
      add(
        'de.spacing.after-punctuation',
        m.end,
        m.end,
        'Nach diesem Satzzeichen ein Leerzeichen prüfen.',
        replacements: <String>[' '],
      );
    }
    for (final RegExpMatch m in RegExp(
      r'(?<![\p{L}\p{M}])(und|oder|aber) +(\1)(?![\p{L}\p{M}])',
      caseSensitive: false,
      unicode: true,
    ).allMatches(text)) {
      add(
        'de.repetition.conjunction',
        m.start,
        m.end,
        'Die unmittelbare Wiederholung dieser Konjunktion prüfen.',
        replacements: <String>[m.group(1)!],
      );
    }
    const Map<String, String> agreement = <String, String>{
      'ich bist': 'bin',
      'ich ist': 'bin',
      'ich sind': 'bin',
      'ich seid': 'bin',
      'du bin': 'bist',
      'du ist': 'bist',
      'du sind': 'bist',
      'du seid': 'bist',
      'wir bin': 'sind',
      'wir bist': 'sind',
      'wir ist': 'sind',
      'wir seid': 'sind',
      'ihr bin': 'seid',
      'ihr bist': 'seid',
      'ihr ist': 'seid',
      'ihr sind': 'seid',
    };
    for (final RegExpMatch m in RegExp(
      r'(?<![\p{L}\p{M}])(ich|du|wir|ihr) +(bin|bist|ist|sind|seid)(?![\p{L}\p{M}])',
      caseSensitive: false,
      unicode: true,
    ).allMatches(text)) {
      // The whole subject/verb context must be prose. Checking only the verb
      // would let a URL ending in /ich govern an unrelated following "bist".
      if (isProtected(m.start, m.end)) continue;
      final String? replacement =
          agreement['${m.group(1)!.toLowerCase()} ${m.group(2)!.toLowerCase()}'];
      // In "wie du ist er" or "als ich sind sie", the verb belongs to the
      // following subject. These comparisons are not adjacent-subject errors.
      if (_comparisonPrefix.hasMatch(
        text.substring(m.start > 32 ? m.start - 32 : 0, m.start),
      )) {
        continue;
      }
      // "das Ich ist" / "das Du ist" are valid nominal uses. Without a
      // parser, only add the unambiguous lowercase forms of these two pairs.
      if (m.group(2)!.toLowerCase() == 'ist' &&
          const <String>{'ich', 'du'}.contains(m.group(1)!.toLowerCase()) &&
          m.group(1) != m.group(1)!.toLowerCase()) {
        continue;
      }
      if (replacement != null) {
        final String verb = m.group(2)!;
        add(
          'de.grammar.pronoun-verb',
          m.end - m.group(2)!.length,
          m.end,
          'Diese Form von „sein“ passt normalerweise nicht zum unmittelbar vorangehenden Pronomen.',
          category: OfficeProofingCategory.grammar,
          replacements: <String>[
            verb == verb.toUpperCase()
                ? replacement.toUpperCase()
                : replacement,
          ],
        );
      }
    }
    final List<(String, int)> delimiters = <(String, int)>[];
    final List<(String, int)> quotes = <(String, int)>[];
    const Map<String, String> bracketPairs = <String, String>{
      '(': ')',
      '[': ']',
      '{': '}',
    };
    const Map<String, String> quotePairs = <String, String>{
      '„': '“',
      '‚': '‘',
      '“': '”',
      '‘': '’',
      '«': '»',
      '»': '«',
    };
    for (int i = 0; i < text.length; i++) {
      if (i % 2048 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (_disposed) {
          return OfficeProofingResult(
            request: request,
            providerId: id,
            status: OfficeProofingStatus.unavailable,
            message: 'German writing provider is disposed.',
          );
        }
      }
      if (isProtected(i, i + 1)) continue;
      final String char = text[i];
      if (bracketPairs.containsKey(char)) {
        delimiters.add((bracketPairs[char]!, i));
      } else if (bracketPairs.containsValue(char)) {
        if (delimiters.isNotEmpty && delimiters.last.$1 == char) {
          delimiters.removeLast();
        } else {
          add(
            'de.delimiter.balance',
            i,
            i + 1,
            'Zu dieser schließenden Klammer fehlt im Absatz eine passende öffnende Klammer.',
          );
        }
      }
      // An apostrophe inside a name or contraction must not consume the
      // enclosing English single quote: ‘O’Connor’ and ‘geht’s’ are balanced.
      // Inspect whole neighboring scalars, including supplementary letters
      // and decomposed accents, while leaving all source offsets unchanged.
      if (char == '’' &&
          _hasLetterBefore(text, i) &&
          _hasLetterAfter(text, i)) {
        continue;
      }
      if (quotes.isNotEmpty && quotes.last.$1 == char) {
        quotes.removeLast();
      } else if (quotePairs.containsKey(char)) {
        quotes.add((quotePairs[char]!, i));
      } else if (char == '”' || char == '’') {
        final bool apostrophe = char == '’' && _hasLetterBefore(text, i);
        if (!apostrophe) {
          add(
            'de.quote.balance',
            i,
            i + 1,
            'Zu diesem Anführungszeichen fehlt im Absatz ein passendes öffnendes Zeichen.',
          );
        }
      }
    }
    for (final (String, int) entry in delimiters) {
      add(
        'de.delimiter.balance',
        entry.$2,
        entry.$2 + 1,
        'Zu dieser Klammer fehlt im Absatz „${entry.$1}“. Absatzübergreifende Inhalte bitte manuell prüfen.',
      );
    }
    for (final (String, int) entry in quotes) {
      add(
        'de.quote.balance',
        entry.$2,
        entry.$2 + 1,
        'Zu diesem Anführungszeichen fehlt im Absatz „${entry.$1}“. Mehrabsätzige Zitate bitte manuell prüfen.',
      );
    }
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: findings,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

/// Host-authored literal terminology policy, with language and boundary controls.
class OfficeTerminologyRule {
  OfficeTerminologyRule({
    required this.id,
    required this.term,
    required this.message,
    required List<String> replacements,
    this.caseSensitive = false,
    this.wholeWord = true,
    Set<String> languages = const <String>{},
  }) : replacements = List<String>.unmodifiable(replacements),
       languages = Set<String>.unmodifiable(
         languages.map(normalizeProofingLanguage),
       ) {
    if (id.trim().isEmpty || term.isEmpty) {
      throw ArgumentError(
        'A terminology rule needs an id and a nonempty literal term.',
      );
    }
  }
  final String id;
  final String term;
  final String message;
  final List<String> replacements;
  final bool caseSensitive;
  final bool wholeWord;

  /// Empty means every explicitly selected document language.
  final Set<String> languages;
}

class OfficeTerminologyProvider extends OfficeProofingProvider {
  OfficeTerminologyProvider({required List<OfficeTerminologyRule> rules})
    : rules = List<OfficeTerminologyRule>.unmodifiable(rules) {
    final Set<String> ids = <String>{};
    for (final OfficeTerminologyRule rule in rules) {
      if (!ids.add(rule.id)) {
        throw ArgumentError('Duplicate terminology rule id: ${rule.id}');
      }
    }
  }
  final List<OfficeTerminologyRule> rules;
  bool _disposed = false;
  @override
  String get id => 'terminology';
  @override
  bool supportsLanguage(String language) => rules.any(
    (OfficeTerminologyRule rule) =>
        rule.languages.isEmpty ||
        rule.languages.contains(normalizeProofingLanguage(language)),
  );
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (_disposed || rules.isEmpty || !supportsLanguage(request.language)) {
      return OfficeProofingResult(
        request: request,
        providerId: id,
        status: _disposed || rules.isEmpty
            ? OfficeProofingStatus.unavailable
            : OfficeProofingStatus.unsupported,
        message: _disposed
            ? 'Terminology provider is disposed.'
            : 'No terminology rules apply.',
      );
    }
    final List<OfficeProofingFinding> findings = <OfficeProofingFinding>[];
    final Set<int> boundaries = _sourceGraphemeBoundaries(request.text);
    for (final OfficeTerminologyRule rule in rules) {
      await Future<void>.delayed(Duration.zero);
      if (_disposed) {
        return OfficeProofingResult(
          request: request,
          providerId: id,
          status: OfficeProofingStatus.unavailable,
          message: 'Terminology provider is disposed.',
        );
      }
      if (request.ignoredRuleIds.contains(rule.id) ||
          rule.languages.isNotEmpty &&
              !rule.languages.contains(request.language)) {
        continue;
      }
      final String term = RegExp.escape(rule.term);
      final RegExp expression = RegExp(
        rule.wholeWord
            ? '(?<![\\p{L}\\p{M}\\p{N}_])$term(?![\\p{L}\\p{M}\\p{N}_])'
            : term,
        caseSensitive: rule.caseSensitive,
        unicode: true,
      );
      for (final RegExpMatch m in expression.allMatches(request.text)) {
        // Literal substring rules still may not replace part of a visible
        // character (for example Cafe within decomposed Café).
        if (!boundaries.contains(m.start) || !boundaries.contains(m.end)) {
          continue;
        }
        findings.add(
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            start: m.start,
            end: m.end,
            ruleId: rule.id,
            message: rule.message,
            category: OfficeProofingCategory.style,
            replacements: rule.replacements,
          ),
        );
      }
    }
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: findings,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
