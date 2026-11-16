import 'office_proofing.dart';

/// Seven independently authored writing checks; not a general grammar parser.
/// Findings are advisory and never rewrite text. Unbalanced quotes can be valid
/// across paragraph boundaries and are explicitly described as review items.
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
    final List<RegExpMatch> protected = RegExp(
      r'(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}|`[^`]*`',
    ).allMatches(text).toList();
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
      if (request.ignoredRuleIds.contains(ruleId) ||
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
      'ich sind': 'bin',
      'ich seid': 'bin',
      'du bin': 'bist',
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
      final String? replacement =
          agreement['${m.group(1)!.toLowerCase()} ${m.group(2)!.toLowerCase()}'];
      if (replacement != null) {
        add(
          'de.grammar.pronoun-verb',
          m.end - m.group(2)!.length,
          m.end,
          'Diese Form von „sein“ passt normalerweise nicht zum unmittelbar vorangehenden Pronomen.',
          category: OfficeProofingCategory.grammar,
          replacements: <String>[replacement],
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
      if (quotes.isNotEmpty && quotes.last.$1 == char) {
        quotes.removeLast();
      } else if (quotePairs.containsKey(char)) {
        quotes.add((quotePairs[char]!, i));
      } else if (char == '”' || char == '’') {
        final bool apostrophe =
            char == '’' &&
            i > 0 &&
            RegExp(r'\p{L}', unicode: true).hasMatch(text[i - 1]);
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
