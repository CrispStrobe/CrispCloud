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
    r'(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}|'
    r'(?<!`)(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)',
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

  // Independently authored present-indicative forms. Do not infer forms for
  // unlisted verbs, subjunctives, or separated subject/verb constructions.
  static const List<_GermanPresentParadigm> _presentParadigms =
      <_GermanPresentParadigm>[
        _GermanPresentParadigm('sein', 'bin', 'bist', 'ist', 'sind', 'seid'),
        _GermanPresentParadigm('haben', 'habe', 'hast', 'hat', 'haben', 'habt'),
        _GermanPresentParadigm(
          'werden',
          'werde',
          'wirst',
          'wird',
          'werden',
          'werdet',
        ),
        _GermanPresentParadigm(
          'können',
          'kann',
          'kannst',
          'kann',
          'können',
          'könnt',
        ),
        _GermanPresentParadigm(
          'müssen',
          'muss',
          'musst',
          'muss',
          'müssen',
          'müsst',
        ),
        _GermanPresentParadigm(
          'dürfen',
          'darf',
          'darfst',
          'darf',
          'dürfen',
          'dürft',
        ),
        _GermanPresentParadigm(
          'sollen',
          'soll',
          'sollst',
          'soll',
          'sollen',
          'sollt',
        ),
        _GermanPresentParadigm(
          'wollen',
          'will',
          'willst',
          'will',
          'wollen',
          'wollt',
        ),
        _GermanPresentParadigm('mögen', 'mag', 'magst', 'mag', 'mögen', 'mögt'),
      ];
  static final Map<String, _GermanPresentParadigm> _presentByForm =
      <String, _GermanPresentParadigm>{
        for (final _GermanPresentParadigm paradigm in _presentParadigms)
          for (final String form in paradigm.forms) form: paradigm,
      };
  static final RegExp _pronounVerb = RegExp(
    r"(?<![\p{L}\p{M}\p{N}_'’-])(ich|du|wir|ihr)[ \t\u00a0\u202f]+(" +
        _presentByForm.keys.map(RegExp.escape).join('|') +
        r")(?![\p{L}\p{M}\p{N}_'’-])",
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _comparisonPrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:wie|als)[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _coordinationPrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:(und|oder|noch|sowie)(?:[ \t\u00a0\u202f]+auch)?|(?:sondern|als|wie)[ \t\u00a0\u202f]+auch)[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _nominalPronounPrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:das|ein|mein|dein|sein|unser|euer|ihr|dieses|jenes|jedes|welches|kein)(?:[ \t\u00a0\u202f]+[\p{L}\p{M}]+){0,3}[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _dativePrefix = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:aus|bei|mit|nach|seit|von|zu|außer|gegenüber|dank|wegen|trotz|vor|hinter|unter|über|neben|zwischen|an|auf|in)(?:[ \t\u00a0\u202f]+(?:nur|gerade|auch|selbst|allein))*[ \t\u00a0\u202f]+$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _followingSubject = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])(?:ich|du|er|sie|es|wir|man|jemand|niemand|der|die|das|ein|eine|alle|beide|jeder|jede|jedes|viele|wenige)(?![\p{L}\p{M}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _followingNoun = RegExp(
    r'(?<![\p{L}\p{M}\p{N}_])\p{Lu}[\p{L}\p{M}]*(?![\p{L}\p{M}\p{N}_])',
    unicode: true,
  );
  static final RegExp _clauseEnd = RegExp(r'[.!?;:\r\n]');

  static bool _ambiguousAgreementContext(
    String text,
    RegExpMatch match,
    String subject,
    String verb,
  ) {
    final String prefix = text.substring(
      match.start > 96 ? match.start - 96 : 0,
      match.start,
    );
    // "wie du haben wir" and "du und ich sind" do not assign the verb
    // exclusively to the last pronoun. A preceding comma can also close a
    // relative clause: "Mein Bruder, den du kennst, und ich haben Zeit".
    // Keep plausible plural forms untouched even after that comma.
    if (_comparisonPrefix.hasMatch(prefix)) return true;
    final RegExpMatch? coordination = _coordinationPrefix.firstMatch(prefix);
    final _GermanPresentParadigm? paradigm = _presentByForm[verb];
    if (coordination != null &&
        (coordination.group(1) == null ||
            !prefix
                .substring(0, coordination.start)
                .trimRight()
                .endsWith(',') ||
            paradigm != null &&
                (verb == paradigm.wir || verb == paradigm.ihr))) {
      return true;
    }
    final String originalSubject = match.group(1)!;
    if (originalSubject != subject &&
        (_nominalPronounPrefix.hasMatch(prefix) ||
            verb == 'ist' && const <String>{'ich', 'du'}.contains(subject))) {
      return true;
    }
    if (subject != 'ihr') return false;
    // "ihr" also denotes a dative object. "Ihr ist kalt" is valid without an
    // explicit subject; "Ihr bin ich dankbar" and "Mit ihr sind wir ..." are
    // also valid. Preserve narrow existing sein checks only outside those
    // ambiguous contexts; do not expand ihr to the additional verb families.
    if (verb == 'ist' || _dativePrefix.hasMatch(prefix)) return true;
    final int end = match.end + 160 < text.length
        ? match.end + 160
        : text.length;
    final String following = text.substring(match.end, end);
    final RegExpMatch? stop = _clauseEnd.firstMatch(following);
    final String clause = stop == null
        ? following
        : following.substring(0, stop.start);
    return _followingSubject.hasMatch(clause) ||
        _followingNoun.hasMatch(clause);
  }

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
    for (final RegExpMatch match in _pronounVerb.allMatches(text)) {
      // Both the subject and verb must belong to prose, including their source
      // graphemes. Protected text cannot govern an unrelated following verb.
      if (isProtected(match.start, match.end) ||
          !boundaries.contains(match.start)) {
        continue;
      }
      final String subject = match.group(1)!.toLowerCase();
      final String verb = match.group(2)!;
      final String lowerVerb = verb.toLowerCase();
      final _GermanPresentParadigm? paradigm = _presentByForm[lowerVerb];
      // Unicode case folding can match a form whose lowercase text is not
      // a listed spelling (for example long-s). Leave it to spelling checks.
      if (paradigm == null ||
          subject == 'ihr' && paradigm.infinitive != 'sein') {
        continue;
      }
      final String replacement = paradigm.forSubject(subject);
      if (replacement == lowerVerb ||
          _ambiguousAgreementContext(text, match, subject, lowerVerb)) {
        continue;
      }
      add(
        'de.grammar.pronoun-verb',
        match.end - verb.length,
        match.end,
        'Diese Form von „${paradigm.infinitive}“ passt normalerweise nicht zum unmittelbar vorangehenden Pronomen.',
        category: OfficeProofingCategory.grammar,
        replacements: <String>[
          verb == verb.toUpperCase() ? replacement.toUpperCase() : replacement,
        ],
      );
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

/// A finite, reviewed indicative paradigm; this is not a morphology engine.
class _GermanPresentParadigm {
  const _GermanPresentParadigm(
    this.infinitive,
    this.ich,
    this.du,
    this.thirdPerson,
    this.wir,
    this.ihr,
  );

  final String infinitive;
  final String ich;
  final String du;
  final String thirdPerson;
  final String wir;
  final String ihr;

  Set<String> get forms => <String>{ich, du, thirdPerson, wir, ihr};

  String forSubject(String subject) => switch (subject) {
    'ich' => ich,
    'du' => du,
    'wir' => wir,
    'ihr' => ihr,
    _ => throw ArgumentError.value(subject, 'subject'),
  };
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
