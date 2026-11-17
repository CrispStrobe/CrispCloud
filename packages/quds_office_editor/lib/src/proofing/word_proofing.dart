import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// A finding together with its exact paragraph, story and input snapshot.
final class WordProofingIssue {
  WordProofingIssue._(this.finding, this._snapshot, this.language);

  final OfficeProofingFinding finding;
  final _ParagraphSnapshot _snapshot;
  final String language;
  WmlParagraph get paragraph => _snapshot.paragraph;
  String get story => _snapshot.story;
  String get sourceText => _snapshot.text;
}

/// Coverage and operational outcomes of one document-wide proofing pass.
final class WordProofingSummary {
  WordProofingSummary({
    this.paragraphCount = 0,
    this.checkedParagraphCount = 0,
    this.skippedContentCount = 0,
    this.hasResults = false,
    List<WordProofingIssue> issues = const [],
    List<OfficeProofingReport> reports = const [],
    this.checking = false,
    this.manualProvidersSkipped = false,
  }) : issues = List.unmodifiable(issues),
       reports = List.unmodifiable(reports);

  final int paragraphCount;
  final int checkedParagraphCount;
  final int skippedContentCount;
  final bool hasResults;
  final bool checking;
  final bool manualProvidersSkipped;
  final List<WordProofingIssue> issues;
  final List<OfficeProofingReport> reports;

  bool get complete =>
      hasResults &&
      !checking &&
      !manualProvidersSkipped &&
      skippedContentCount == 0 &&
      reports.isNotEmpty &&
      reports.every((report) => report.complete);

  String get statusMessage {
    if (checking) return 'Checking document…';
    if (!hasResults) return 'Document has not been checked.';
    final problems = <String>{};
    for (final report in reports) {
      if (!report.complete) {
        for (final result in report.results) {
          if (result.status != OfficeProofingStatus.success) {
            problems.add(
              result.message ?? '${result.providerId}: ${result.status.name}',
            );
          }
        }
      }
    }
    final coverage =
        '$checkedParagraphCount of $paragraphCount paragraphs checked';
    final excluded = skippedContentCount == 0
        ? ''
        : '; $skippedContentCount excluded or unsupported content ranges';
    if (problems.isNotEmpty) return '$coverage$excluded. ${problems.join(' ')}';
    if (manualProvidersSkipped) {
      return '$coverage$excluded. ${issues.length} findings; '
          'choose Check document to include the manual grammar check.';
    }
    if (reports.isEmpty) return '$coverage$excluded. No checkable text.';
    if (!complete) {
      return '$coverage$excluded. ${issues.length} findings; coverage is incomplete.';
    }
    return issues.isEmpty
        ? '$coverage. No issues found by the configured providers.'
        : '$coverage. ${issues.length} findings to review.';
  }
}

/// Ephemeral document proofing. The host owns vocabulary persistence; the
/// session owns and disposes its service. Unchanged paragraphs reuse checked
/// results while every published finding is rebound to the current revision.
final class WordProofingSession extends ChangeNotifier {
  WordProofingSession({
    required this._document,
    required this._revision,
    OfficeProofingService? service,
    OfficeProofingVocabulary? vocabulary,
    this.debounce = const Duration(milliseconds: 400),
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary() {
    _service =
        service ??
        OfficeProofingService(
          providers: [
            GermanWritingRulesProvider(),
            GermanSpellingProvider(vocabulary: this.vocabulary),
          ],
        );
  }

  final WmlDocument Function() _document;
  final int Function() _revision;
  final OfficeProofingVocabulary vocabulary;

  /// Hosts may persist this owner-scoped snapshot in their own storage.
  void Function(Map<String, Object?> snapshot)? onVocabularyChanged;
  final Duration debounce;
  late OfficeProofingService _service;
  OfficeProofingService? _manualService;
  final Set<String> _ignoredRules = {};
  final Set<String> _ignoredOnce = {};
  final Expando<String> _ids = Expando<String>('proofing paragraph id');
  final Expando<String> _documentIds = Expando<String>('proofing document id');
  final Map<WmlParagraph, _CachedParagraph> _cache = HashMap.identity();
  Map<WmlParagraph, List<OfficeProofingFinding>> _findings = HashMap.identity();
  int _nextId = 0;
  int _generation = 0;
  int _configuration = 0;
  bool _disposed = false;
  bool _enabled = false;
  Timer? _timer;
  WmlDocument? _observedDocument;
  int? _observedRevision;
  String? _observedConfiguration;
  WordProofingSummary _summary = WordProofingSummary();

  WordProofingSummary get summary => _summary;
  bool get checking => _summary.checking;
  bool get enabled => _enabled;
  bool get hasManualProviders => _manualService?.providers.isNotEmpty ?? false;
  String get language =>
      normalizeProofingLanguage(_document().proofingLanguage ?? 'de-DE');
  Set<String> get ignoredRuleIds => Set.unmodifiable(_ignoredRules);
  bool get hasIgnoredOccurrences => _ignoredOnce.isNotEmpty;
  Map<WmlParagraph, List<OfficeProofingFinding>> get findingsByParagraph =>
      UnmodifiableMapView(_findings);

  set enabled(bool value) {
    if (_enabled == value || _disposed) return;
    _enabled = value;
    refresh();
  }

  String get _configurationKey =>
      '$_configuration|${_service.configurationKey}|'
      '${_manualService?.configurationKey ?? ''}|${vocabulary.revision}|'
      '$language|${_ignoredRules.join(',')}';

  /// Replacing a provider configuration invalidates pending checks immediately.
  void configure(OfficeProofingService service) {
    if (_disposed) throw StateError('The proofing session is disposed.');
    if (identical(_service, service)) return;
    _validateDistinctProviders(service, _manualService);
    _validateReplacement(_service, service);
    final previous = _service;
    _service = service;
    _configuration++;
    _cache.clear();
    unawaited(previous.dispose());
    refresh();
  }

  /// Installs already-loaded providers for explicit checking, including F7.
  /// They never run from the typing debounce timer. The session owns this
  /// separate service and disposes it on replacement or session disposal.
  /// Providers must not be shared with the ordinary service or repeat its IDs.
  void configureManual(OfficeProofingService? service) {
    if (_disposed) throw StateError('The proofing session is disposed.');
    if (identical(_manualService, service)) return;
    _validateDistinctProviders(_service, service);
    _validateReplacement(_manualService, service);
    final previous = _manualService;
    _manualService = service;
    _configuration++;
    _cache.clear();
    if (previous != null) unawaited(previous.dispose());
    refresh();
  }

  static void _validateDistinctProviders(
    OfficeProofingService ordinary,
    OfficeProofingService? manual,
  ) {
    if (manual == null) return;
    final ordinaryIds = ordinary.providers
        .map((provider) => provider.id)
        .toSet();
    if (identical(ordinary, manual) ||
        manual.providers.any((provider) => ordinaryIds.contains(provider.id))) {
      throw ArgumentError(
        'Manual and ordinary proofing providers must have distinct IDs and ownership.',
      );
    }
  }

  static void _validateReplacement(
    OfficeProofingService? previous,
    OfficeProofingService? replacement,
  ) {
    if (previous == null || replacement == null) return;
    if (replacement.providers.any(
      (next) => previous.providers.any((old) => identical(old, next)),
    )) {
      throw ArgumentError(
        'A replacement service must own new provider instances.',
      );
    }
  }

  /// Called for controller-observed content changes. Selection and scroll
  /// notifications do not repeatedly cancel work or schedule new checks.
  void observeDocument() {
    if (_disposed) return;
    final document = _document();
    final revision = _revision();
    final configuration = _configurationKey;
    if (!identical(document, _observedDocument)) {
      _cache.clear();
      _ignoredOnce.clear();
    }
    if (identical(document, _observedDocument) &&
        revision == _observedRevision &&
        configuration == _observedConfiguration) {
      return;
    }
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = configuration;
    _invalidate();
  }

  /// Hosts call this after direct model edits or changes to host-owned words.
  void refresh() {
    if (_disposed) return;
    if (!identical(_observedDocument, _document())) {
      _cache.clear();
      _ignoredOnce.clear();
    }
    _observedDocument = _document();
    _observedRevision = _revision();
    _observedConfiguration = _configurationKey;
    _invalidate();
    notifyListeners();
  }

  void _invalidate() {
    _generation++;
    _timer?.cancel();
    _summary = WordProofingSummary();
    _findings = HashMap.identity();
    if (_enabled) {
      _timer = Timer(
        debounce,
        () => unawaited(checkNow(includeManualProviders: false)),
      );
    }
  }

  void ignoreWord(WordProofingIssue issue) {
    if (!isCurrent(issue) ||
        issue.finding.category != OfficeProofingCategory.spelling) {
      return;
    }
    vocabulary.ignoreWord(issue.finding.originalText, language: issue.language);
    onVocabularyChanged?.call(vocabulary.toJson());
    refresh();
  }

  List<WordProofingIssue> issuesAt(WmlParagraph paragraph, int offset) =>
      _summary.issues
          .where(
            (issue) =>
                identical(issue.paragraph, paragraph) &&
                offset >= issue.finding.start &&
                (issue.finding.start == issue.finding.end
                    ? offset == issue.finding.end
                    : offset < issue.finding.end),
          )
          .toList();

  String _issueKey(
    OfficeProofingFinding finding,
    _ParagraphSnapshot snapshot,
  ) => jsonEncode([
    finding.blockId,
    snapshot.key,
    finding.providerId,
    finding.ruleId,
    finding.start,
    finding.end,
  ]);

  void ignoreOnce(WordProofingIssue issue) {
    if (!isCurrent(issue)) return;
    _ignoredOnce.add(_issueKey(issue.finding, issue._snapshot));
    refresh();
  }

  /// Reviews previously ignored occurrences without resetting personal words,
  /// language-scoped ignored words or rule preferences.
  void clearIgnoredOnce() {
    if (_disposed || _ignoredOnce.isEmpty) return;
    _ignoredOnce.clear();
    refresh();
  }

  /// Restores a word in its original language, including run-level languages
  /// that differ from the document default.
  void unignoreWord(String word, {required String language}) {
    if (_disposed) return;
    final previous = vocabulary.revision;
    vocabulary.unignoreWord(word, language: language);
    if (vocabulary.revision == previous) return;
    refresh();
    onVocabularyChanged?.call(vocabulary.toJson());
  }

  /// Restores only this owner's vocabulary, preserving provider references.
  void restoreVocabulary(Map<String, Object?> snapshot) {
    final restored = OfficeProofingVocabulary.fromJson(snapshot);
    if (restored.ownerId != vocabulary.ownerId) {
      throw ArgumentError('Vocabulary owner does not match.');
    }
    final previous = vocabulary.toJson()['words']! as Map<String, Object?>;
    for (final language in previous.keys) {
      for (final word in vocabulary.wordsFor(language)) {
        vocabulary.removeWord(word, language: language);
      }
    }
    vocabulary.clearIgnoredWords();
    for (final language in (snapshot['words']! as Map<String, Object?>).keys) {
      for (final word in restored.wordsFor(language)) {
        vocabulary.addWord(word, language: language);
      }
    }
    for (final language
        in (snapshot['ignoredWords']! as Map<String, Object?>).keys) {
      for (final word in restored.ignoredWordsFor(language)) {
        vocabulary.ignoreWord(word, language: language);
      }
    }
    refresh();
  }

  void addWord(WordProofingIssue issue) {
    if (!isCurrent(issue) ||
        issue.finding.category != OfficeProofingCategory.spelling) {
      return;
    }
    vocabulary.addWord(issue.finding.originalText, language: issue.language);
    onVocabularyChanged?.call(vocabulary.toJson());
    refresh();
  }

  void ignoreRule(String ruleId) {
    if (_ignoredRules.add(ruleId)) refresh();
  }

  void restoreRule(String ruleId) {
    if (_ignoredRules.remove(ruleId)) refresh();
  }

  /// Results are accepted only for the current document, revision, language,
  /// provider configuration, story membership and complete paragraph snapshot.
  bool isCurrent(WordProofingIssue issue) {
    if (_disposed ||
        !_summary.issues.contains(issue) ||
        issue.finding.revision != _revision() ||
        issue.finding.documentId != _documentIds[_document()] ||
        issue._snapshot.configuration != _configurationKey) {
      return false;
    }
    final current = _capture(_document()).paragraphs
        .where((snapshot) => identical(snapshot.paragraph, issue.paragraph))
        .firstOrNull;
    return current != null &&
        current.key == issue._snapshot.key &&
        issue.finding.end <= current.text.length &&
        current.text.substring(issue.finding.start, issue.finding.end) ==
            issue.finding.originalText;
  }

  bool canCorrect(WordProofingIssue issue) {
    if (!isCurrent(issue)) return false;
    final snapshot = issue._snapshot;
    final finding = issue.finding;
    final boundaries = <int>{
      0,
      for (final cluster in GraphemeClusters.segment(snapshot.text))
        cluster.end,
    };
    if (!boundaries.contains(finding.start) ||
        !boundaries.contains(finding.end)) {
      return false;
    }
    if (_document().trackRevisions &&
        (snapshot.insertionBarriers.contains(finding.end) ||
            snapshot.guards.any(
              (range) =>
                  _touches(finding.end, finding.end, range.start, range.end),
            ))) {
      return false;
    }
    if (snapshot.locked ||
        snapshot.guards.any(
          (range) =>
              _touches(finding.start, finding.end, range.start, range.end),
        )) {
      return false;
    }
    try {
      WordContentControls.assertCanEdit(
        issue.paragraph,
        finding.start,
        finding.end,
      );
      final normalized = WmlRunEdit.normalizeRange(
        issue.paragraph,
        finding.start,
        finding.end,
      );
      return normalized.start == finding.start && normalized.end == finding.end;
    } on Object {
      return false;
    }
  }

  /// Explicit checks include manually configured providers. Background callers
  /// omit them and report that coverage separately; cached results never cross
  /// these two scopes. F7 and the review dialog call the inclusive default.
  Future<WordProofingSummary> checkNow({
    bool includeManualProviders = true,
  }) async {
    if (_disposed) return _summary;
    _timer?.cancel();
    final generation = ++_generation;
    final document = _document();
    final revision = _revision();
    final configuration = _configurationKey;
    final manual = includeManualProviders ? _manualService : null;
    final useManual = manual?.providers.isNotEmpty ?? false;
    if (!identical(document, _observedDocument)) {
      _cache.clear();
      _ignoredOnce.clear();
    }
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = configuration;
    final documentId = _documentIds[document] ??= 'document-${++_nextId}';
    final captured = _capture(document);
    final manualSkipped =
        !includeManualProviders && _manualProvidersApplyTo(captured);
    _summary = WordProofingSummary(
      paragraphCount: captured.paragraphs.length,
      checking: true,
      manualProvidersSkipped: manualSkipped,
    );
    _findings = HashMap.identity();
    notifyListeners();
    final reports = <OfficeProofingReport>[];
    final issues = <WordProofingIssue>[];
    var checked = 0;
    bool current() =>
        !_disposed &&
        generation == _generation &&
        identical(document, _document()) &&
        revision == _revision() &&
        configuration == _configurationKey;
    for (final snapshot in captured.paragraphs) {
      // Yield between paragraphs even when a cached/provider Future completes
      // synchronously. Web typing and painting get an event-loop turn.
      await Future<void>.delayed(Duration.zero);
      if (!current()) return _summary;
      final cached = _cache[snapshot.paragraph];
      final paragraphReports = <OfficeProofingReport>[];
      for (var index = 0; index < snapshot.segments.length; index++) {
        final segment = snapshot.segments[index];
        final request = OfficeProofingRequest(
          documentId: documentId,
          blockId: _ids[snapshot.paragraph] ??= 'paragraph-${++_nextId}',
          revision: revision,
          text: segment.text,
          startOffset: segment.start,
          language: segment.language,
          ignoredRuleIds: _ignoredRules,
        );
        final OfficeProofingReport report;
        if (cached?.key == snapshot.key &&
            cached!.includesManual == useManual &&
            cached.reports.length == snapshot.segments.length &&
            cached.reports.every((report) => report.complete)) {
          report = _retarget(cached.reports[index], request);
        } else {
          final ordinary = await _service.check(request);
          if (!current()) return _summary;
          report = useManual
              ? mergeOfficeProofingReports(
                  primary: ordinary,
                  secondary: await manual!.check(request),
                )
              : ordinary;
        }
        if (!current()) return _summary;
        paragraphReports.add(report);
        for (final finding in report.findings) {
          if (_ignoredOnce.contains(_issueKey(finding, snapshot))) continue;
          if (finding.category == OfficeProofingCategory.spelling &&
              vocabulary.contains(
                finding.originalText,
                language: segment.language,
              )) {
            continue;
          }
          issues.add(WordProofingIssue._(finding, snapshot, segment.language));
        }
      }
      if (paragraphReports.isNotEmpty &&
          paragraphReports.every((report) => report.complete)) {
        checked++;
      }
      reports.addAll(paragraphReports);
      _cache[snapshot.paragraph] = _CachedParagraph(
        snapshot.key,
        paragraphReports,
        useManual,
      );
    }
    if (!current()) return _summary;
    final after = _capture(document);
    if (captured.key != after.key) {
      refresh();
      return _summary;
    }
    final attached = captured.paragraphs
        .map((snapshot) => snapshot.paragraph)
        .toSet();
    _cache.removeWhere((paragraph, _) => !attached.contains(paragraph));
    final findings =
        HashMap<WmlParagraph, List<OfficeProofingFinding>>.identity();
    for (final issue in issues) {
      findings.putIfAbsent(issue.paragraph, () => []).add(issue.finding);
    }
    _findings = {
      for (final entry in findings.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    _summary = WordProofingSummary(
      paragraphCount: captured.paragraphs.length,
      checkedParagraphCount: checked,
      skippedContentCount: captured.skipped,
      hasResults: true,
      reports: reports,
      issues: issues,
      manualProvidersSkipped: manualSkipped,
    );
    notifyListeners();
    return _summary;
  }

  bool _manualProvidersApplyTo(_DocumentSnapshot captured) {
    final manual = _manualService;
    if (manual == null || manual.providers.isEmpty) return false;
    final languages = <String>{
      for (final paragraph in captured.paragraphs)
        for (final segment in paragraph.segments)
          normalizeProofingLanguage(segment.language),
    };
    for (final provider in manual.providers) {
      for (final language in languages) {
        try {
          if (provider.supportsLanguage(language)) return true;
        } on Object {
          // An invalid capability declaration is not evidence of coverage.
          // An explicit check will preserve its operational failure.
          return true;
        }
      }
    }
    return false;
  }

  _DocumentSnapshot _capture(WmlDocument document) {
    final snapshots = <_ParagraphSnapshot>[];
    final seen = HashSet<WmlParagraph>.identity();
    var skipped = 0;
    final configuration = _configurationKey;
    final deletions =
        HashMap<WmlParagraph, List<({int start, int end})>>.identity();
    final pending =
        HashMap<WmlParagraph, List<({int start, int end})>>.identity();
    for (final revision in document.revisions) {
      if (revision.accepted != null) continue;
      final paragraph = WordRevisions.resolveParagraph(document, revision);
      if (paragraph != null &&
          revision.start >= 0 &&
          revision.end <= paragraph.text.length) {
        pending.putIfAbsent(paragraph, () => []).add((
          start: revision.start,
          end: revision.end,
        ));
        if (revision.kind == WmlRevisionKind.delete) {
          deletions.putIfAbsent(paragraph, () => []).add((
            start: revision.start,
            end: revision.end,
          ));
        }
      }
    }
    void story(
      Iterable<({WmlParagraph paragraph, bool locked, bool generated})> entries,
      String name,
    ) {
      var fieldDepth = 0;
      for (final entry in entries) {
        final paragraph = entry.paragraph;
        if (!seen.add(paragraph)) continue;
        final text = paragraph.text;
        final exclusions = <({int start, int end})>[...?deletions[paragraph]];
        final guards = <({int start, int end})>[];
        final barriers = <int>{};
        final insertionBarriers = <int>{};
        final structure = <Object?>[];
        final languageRuns = <({int start, int end, String language})>[];
        var hasField = fieldDepth > 0;
        var offset = 0;
        var locked =
            entry.locked ||
            paragraph.contentControlWrappers.any(_lockedControl);
        var generated =
            entry.generated ||
            paragraph.properties.fieldInstruction != null ||
            paragraph.properties.pageNumberField;
        if (generated && text.isNotEmpty) {
          exclusions.add((start: 0, end: text.length));
        }
        try {
          for (final span in WordContentControls.spans(paragraph)) {
            if (_lockedControl(span.control)) {
              guards.add((start: span.start, end: span.end));
            }
          }
        } on Object {
          locked = true;
        }
        for (final inline in paragraph.inlines) {
          if (inline is WmlFieldBoundary) {
            hasField = true;
            barriers.add(offset);
            insertionBarriers.add(offset);
            structure.add(['field', inline.kind.name, inline.text]);
            switch (inline.kind) {
              case WmlFieldBoundaryKind.begin:
                fieldDepth++;
              case WmlFieldBoundaryKind.end:
                if (fieldDepth > 0) fieldDepth--;
              case WmlFieldBoundaryKind.instruction:
              case WmlFieldBoundaryKind.separate:
                break;
            }
          } else if (inline is WmlRun) {
            final end = offset + inline.text.length;
            if (inline.isAtomic ||
                inline.properties.noProof == true ||
                fieldDepth > 0) {
              exclusions.add((start: offset, end: end));
            }
            languageRuns.add((
              start: offset,
              end: end,
              language: normalizeProofingLanguage(
                inline.properties.proofingLanguage ??
                    paragraph.properties.proofingLanguage ??
                    language,
              ),
            ));
            offset = end;
          } else {
            barriers.add(offset);
            if (inline is WmlContentControlBoundary ||
                inline is WmlOpaqueInline) {
              insertionBarriers.add(offset);
            }
            structure.add(
              inline is WmlContentControlBoundary
                  ? ['control', inline.start, inline.control.xml]
                  : inline.runtimeType.toString(),
            );
            if (inline is WmlOpaqueInline || inline is WmlObject) skipped++;
          }
        }
        // A closed empty field has depth zero again, but its insertion point
        // still belongs to generated content. Also retain field coverage for
        // empty paragraphs inside or ending a field from the previous paragraph.
        final emptyField = text.isEmpty && hasField;
        if (emptyField) {
          exclusions.add((start: 0, end: 0));
          insertionBarriers.add(0);
        }
        guards.addAll(exclusions);
        // Existing insert revisions are not rewritten by a second command.
        guards.addAll(pending[paragraph] ?? const []);
        final ranges = <({int start, int end, String language})>[];
        var paragraphSkipped = generated || emptyField;
        var languageIndex = 0;
        // A language or noProof boundary inside a Unicode grapheme must never
        // give a provider half a surrogate pair, accent, or joined emoji.
        for (final cluster in GraphemeClusters.segment(text)) {
          final start = cluster.start;
          final end = cluster.end;
          if (exclusions.any(
            (range) => start < range.end && end > range.start,
          )) {
            paragraphSkipped = true;
            continue;
          }
          while (languageIndex < languageRuns.length &&
              languageRuns[languageIndex].end <= start) {
            languageIndex++;
          }
          final tag = languageIndex < languageRuns.length
              ? languageRuns[languageIndex].language
              : language;
          if (!barriers.contains(start) &&
              ranges.isNotEmpty &&
              ranges.last.end == start &&
              ranges.last.language == tag) {
            final last = ranges.removeLast();
            ranges.add((start: last.start, end: end, language: tag));
          } else {
            ranges.add((start: start, end: end, language: tag));
          }
        }
        final segments = [
          for (final range in ranges)
            _Segment(
              range.start,
              range.end,
              text.substring(range.start, range.end),
              range.language,
            ),
        ];
        if (paragraphSkipped) skipped++;
        if (text.isEmpty && !paragraphSkipped) {
          segments.add(
            _Segment(
              0,
              0,
              '',
              paragraph.properties.proofingLanguage ?? language,
            ),
          );
        }
        final key = jsonEncode([
          configuration,
          name,
          text,
          locked,
          paragraph.properties.fieldInstruction,
          paragraph.properties.pageNumberField,
          structure,
          for (final range in guards) [range.start, range.end],
          for (final segment in segments)
            [segment.start, segment.end, segment.language],
        ]);
        snapshots.add(
          _ParagraphSnapshot(
            paragraph,
            name,
            text,
            key,
            configuration,
            locked,
            guards,
            segments,
            insertionBarriers,
          ),
        );
      }
    }

    Iterable<({WmlParagraph paragraph, bool locked, bool generated})> blocks(
      Iterable<WmlBlock> children, {
      bool locked = false,
    }) sync* {
      for (final block in children) {
        if (block is WmlParagraph) {
          yield (paragraph: block, locked: locked, generated: false);
        } else if (block is WmlContentControlBlock) {
          yield* blocks(
            block.blocks,
            locked: locked || _lockedControl(block.control),
          );
        } else if (block is WmlToc) {
          for (final paragraph in [
            block.titleParagraph,
            ...block.itemParagraphs,
          ]) {
            yield (paragraph: paragraph, locked: true, generated: true);
          }
        } else if (block is WmlOpaqueBlock ||
            block is WmlVisual ||
            block is WmlEquation) {
          skipped++;
        } else {
          for (final childList in WordTree.childLists(block)) {
            yield* blocks(childList, locked: locked);
          }
        }
      }
    }

    // A complex field can span sections in the main document story.
    story(
      blocks(document.sections.expand((section) => section.blocks)),
      'Body',
    );
    for (var i = 0; i < document.sections.length; i++) {
      final section = document.sections[i];
      skipped += section.preservedStories.length;
      final stories = {
        'Header': section.header,
        'Footer': section.footer,
        'First-page header': section.firstHeader,
        'First-page footer': section.firstFooter,
        'Even-page header': section.evenHeader,
        'Even-page footer': section.evenFooter,
      };
      for (final entry in stories.entries) {
        story(
          entry.value.map(
            (p) => (paragraph: p, locked: false, generated: false),
          ),
          '${entry.key} · section ${i + 1}',
        );
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      story(
        blocks(note.blocks),
        '${note.endnote ? 'Endnote' : 'Footnote'} ${note.id}',
      );
    }
    for (final comment in document.comments) {
      story(
        comment.paragraphs.map(
          (p) => (paragraph: p, locked: false, generated: false),
        ),
        'Comment ${comment.id}',
      );
    }
    return _DocumentSnapshot(snapshots, skipped);
  }

  static bool _lockedControl(WmlContentControlData control) {
    try {
      final properties = WordContentControls.template(
        control,
      ).firstChild('sdtPr', namespaceUri: OfficeNamespaces.w);
      final lock = properties?.firstChild(
        'lock',
        namespaceUri: OfficeNamespaces.w,
      );
      final value = lock?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
      return (lock != null && value != 'unlocked' && value != 'sdtLocked') ||
          properties?.firstChild(
                'dataBinding',
                namespaceUri: OfficeNamespaces.w,
              ) !=
              null;
    } on Object {
      return true;
    }
  }

  static bool _touches(int start, int end, int from, int to) =>
      start == end ? start >= from && start <= to : start < to && end > from;

  static OfficeProofingReport _retarget(
    OfficeProofingReport report,
    OfficeProofingRequest request,
  ) => OfficeProofingReport(
    request: request,
    results: [
      for (final result in report.results)
        OfficeProofingResult(
          request: request,
          providerId: result.providerId,
          status: result.status,
          message: result.message,
          findings: [
            for (final finding in result.findings)
              OfficeProofingFinding(
                documentId: request.documentId,
                blockId: request.blockId,
                revision: request.revision,
                providerId: finding.providerId,
                start: finding.start,
                end: finding.end,
                originalText: finding.originalText,
                ruleId: finding.ruleId,
                message: finding.message,
                category: finding.category,
                replacements: finding.replacements,
              ),
          ],
        ),
    ],
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _cache.clear();
    _findings.clear();
    unawaited(_service.dispose());
    final manual = _manualService;
    if (manual != null) unawaited(manual.dispose());
    super.dispose();
  }
}

final class _Segment {
  const _Segment(this.start, this.end, this.text, this.language);
  final int start;
  final int end;
  final String text;
  final String language;
}

final class _ParagraphSnapshot {
  const _ParagraphSnapshot(
    this.paragraph,
    this.story,
    this.text,
    this.key,
    this.configuration,
    this.locked,
    this.guards,
    this.segments,
    this.insertionBarriers,
  );
  final WmlParagraph paragraph;
  final String story;
  final String text;
  final String key;
  final String configuration;
  final bool locked;
  final List<({int start, int end})> guards;
  final List<_Segment> segments;
  final Set<int> insertionBarriers;
}

final class _DocumentSnapshot {
  const _DocumentSnapshot(this.paragraphs, this.skipped);
  final List<_ParagraphSnapshot> paragraphs;
  final int skipped;
  String get key => jsonEncode([
    skipped,
    for (final p in paragraphs) [identityHashCode(p.paragraph), p.key],
  ]);
}

final class _CachedParagraph {
  const _CachedParagraph(this.key, this.reports, this.includesManual);
  final String key;
  final List<OfficeProofingReport> reports;
  final bool includesManual;
}
