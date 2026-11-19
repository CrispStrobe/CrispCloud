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

/// A checked, detached reply draft. Its findings never enter document coverage
/// or the document's Undo history. The host still owns the draft and must verify
/// its thread, source and composition state before using a suggestion.
final class WordDraftProofingResult {
  WordDraftProofingResult._(this._owner, this._configuration, this.report);

  final WordProofingSession _owner;
  final Object _configuration;
  final OfficeProofingReport report;
  String get sourceText => report.request.text;
  String get language => report.request.language;
}

final class _DraftProofingRequest {
  _DraftProofingRequest(this.text, this.configuration);

  final String text;
  final Object configuration;
  final completer = Completer<WordDraftProofingResult?>();
}

/// A source capability independent of a spelling or grammar finding. Only the
/// capturing session can issue one, and its range remains in original UTF-16.
final class WordTextRangeTarget {
  WordTextRangeTarget._(
    this._owner,
    this._document,
    this._revision,
    this._snapshot,
    this.start,
    this.end,
    this.language,
    this._richTextKey,
  );

  final WordProofingSession _owner;
  final WmlDocument _document;
  final int _revision;
  final _ParagraphSnapshot _snapshot;
  final int start;
  final int end;
  final String language;
  final String _richTextKey;
  WmlParagraph get paragraph => _snapshot.paragraph;
  String get story => _snapshot.story;
  String get sourceText => _snapshot.text;
  String get text => sourceText.substring(start, end);
}

enum WordTextRangeStatus {
  ready,
  invalidRange,
  unsupportedTarget,
  protectedContent,
  mixedLanguage,
}

final class WordTextRangeCapture {
  const WordTextRangeCapture._(this.status, [this.target]);

  final WordTextRangeStatus status;
  final WordTextRangeTarget? target;
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
    this.scheduled = false,
    this.manualProvidersSkipped = false,
  }) : issues = List.unmodifiable(issues),
       reports = List.unmodifiable(reports);

  final int paragraphCount;
  final int checkedParagraphCount;
  final int skippedContentCount;
  final bool hasResults;
  final bool checking;

  /// A background pass is waiting for the typing debounce, not checking yet.
  final bool scheduled;
  final bool manualProvidersSkipped;
  final List<WordProofingIssue> issues;
  final List<OfficeProofingReport> reports;

  Iterable<OfficeProofingResult> get _supportedResults sync* {
    for (final report in reports) {
      for (final result in report.results) {
        if (result.status != OfficeProofingStatus.unsupported) yield result;
      }
    }
  }

  bool get complete =>
      hasResults &&
      !checking &&
      !scheduled &&
      !manualProvidersSkipped &&
      checkedParagraphCount == paragraphCount &&
      skippedContentCount == 0 &&
      reports.isNotEmpty &&
      // Each text snapshot needs a successful checker. An unsupported
      // snapshot cannot borrow coverage from another paragraph's success.
      reports.every((report) => report.complete);

  String get statusMessage {
    if (checking) return 'Checking document…';
    if (scheduled) return 'Waiting for a pause in typing…';
    if (!hasResults) return 'Document has not been checked.';
    final supported = _supportedResults.toList();
    final problems = <String>{
      for (final result in supported)
        if (result.status != OfficeProofingStatus.success)
          result.message ?? '${result.providerId}: ${result.status.name}',
    };
    final coverage =
        '$checkedParagraphCount of $paragraphCount paragraphs checked';
    final excluded = skippedContentCount == 0
        ? ''
        : '; $skippedContentCount excluded or unsupported content ranges';
    if (reports.isEmpty) return '$coverage$excluded. No checkable text.';
    if (supported.isEmpty) {
      final language = reports.first.request.language;
      return '$coverage$excluded. No configured checker supports $language.';
    }
    if (problems.isNotEmpty) return '$coverage$excluded. ${problems.join(' ')}';
    if (manualProvidersSkipped) {
      return '$coverage$excluded. ${issues.length} findings; '
          'choose Check document to include the manual grammar check.';
    }
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
    this._priorityParagraph,
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
            // Active only for Arabic-language paragraphs.
            ArabicWritingRulesProvider(),
          ],
        );
  }

  final WmlDocument Function() _document;
  final int Function() _revision;
  final WmlParagraph? Function()? _priorityParagraph;
  final OfficeProofingVocabulary vocabulary;

  /// Live draft checks are bounded independently of the document's paragraphs.
  static const int maxDraftLength = 16384;

  /// Hosts may persist this owner-scoped snapshot in their own storage.
  void Function(Map<String, Object?> snapshot)? onVocabularyChanged;
  final Duration debounce;
  late OfficeProofingService _service;
  OfficeProofingService? _manualService;
  ParagraphLanguageDetector? _languageDetector;
  bool _automaticLanguageDetection = true;

  /// Detected languages of the paragraph texts seen by the latest captures.
  /// Pruned to the current document's texts at the start of each check, so
  /// a long pass never loses results halfway through.
  final Map<String, ParagraphLanguages> _detections = {};
  final Set<String> _missingDetections = {};
  final Set<String> _capturedTexts = {};
  final Set<String> _ignoredRules = {};
  final Set<String> _ignoredOnce = {};
  final Expando<String> _ids = Expando<String>('proofing paragraph id');
  final Expando<String> _documentIds = Expando<String>('proofing document id');
  final Expando<_CachedParagraphSnapshot> _snapshotCache =
      Expando<_CachedParagraphSnapshot>('proofing paragraph snapshot');
  final Map<WmlParagraph, _CachedParagraph> _cache = HashMap.identity();
  Map<WmlParagraph, List<OfficeProofingFinding>> _findings = HashMap.identity();
  int _nextId = 0;
  int _generation = 0;
  int _configuration = 0;
  bool _disposed = false;
  bool _enabled = false;
  bool _enabledPreferenceSet = false;
  int _draftEnabledRevision = 0;
  bool _draftCheckRunning = false;
  _DraftProofingRequest? _pendingDraftCheck;
  Timer? _timer;
  WmlDocument? _observedDocument;
  int? _observedRevision;
  String? _observedConfiguration;
  WordProofingSummary _summary = WordProofingSummary();

  WordProofingSummary get summary => _summary;
  bool get checking => _summary.checking;

  /// Changes when a check starts or its input is invalidated, never for progress.
  /// Hosts can use this token to share requests for the same active check.
  int get checkGeneration => _generation;
  bool get enabled => _enabled;
  bool get hasManualProviders => _manualService?.providers.isNotEmpty ?? false;

  /// Stable across document edits and proofing progress, but changes whenever
  /// the document identity or draft checking configuration becomes obsolete.
  Object get draftConfigurationKey => (
    _document(),
    _disposed,
    _enabled,
    _draftEnabledRevision,
    _configurationKey,
  );

  String get language =>
      normalizeProofingLanguage(_document().proofingLanguage ?? 'de-DE');
  Set<String> get ignoredRuleIds => Set.unmodifiable(_ignoredRules);
  bool get hasIgnoredOccurrences => _ignoredOnce.isNotEmpty;
  Map<WmlParagraph, List<OfficeProofingFinding>> get findingsByParagraph =>
      UnmodifiableMapView(_findings);

  set enabled(bool value) {
    if (_disposed) return;
    _enabledPreferenceSet = true;
    if (_enabled == value) return;
    _enabled = value;
    _draftEnabledRevision++;
    refresh();
  }

  /// Enables the editor's default background checking until a host or user
  /// explicitly chooses [enabled]. Reattaching a view preserves that choice,
  /// including an explicit `false` set before the first attachment.
  /// Standalone sessions remain disabled until this method is called.
  void enableBackgroundByDefault() {
    if (_disposed || _enabledPreferenceSet || _enabled) return;
    _enabled = true;
    _draftEnabledRevision++;
    refresh();
  }

  /// Checks detached reply text with the existing ordinary providers. Manual
  /// providers are never invoked here, and the service remains session-owned.
  /// Hosts debounce requests and discard obsolete draft identities. Across all
  /// composers the session runs at most one draft check and queues only the
  /// latest request, resolving superseded pending requests with null.
  /// No document summary, finding cache or document check generation changes.
  Future<WordDraftProofingResult?> checkDraft(String text) {
    if (_disposed || !_enabled) return Future.value();
    final request = _DraftProofingRequest(text, draftConfigurationKey);
    if (_draftCheckRunning) {
      _pendingDraftCheck?.completer.complete();
      _pendingDraftCheck = request;
    } else {
      unawaited(_runDraftCheck(request));
    }
    return request.completer.future;
  }

  Future<void> _runDraftCheck(_DraftProofingRequest request) async {
    _draftCheckRunning = true;
    try {
      final result = request.configuration == draftConfigurationKey
          ? await _checkDraftSnapshot(request.text, request.configuration)
          : null;
      request.completer.complete(result);
    } catch (error, stack) {
      request.completer.completeError(error, stack);
    } finally {
      _draftCheckRunning = false;
      final next = _pendingDraftCheck;
      _pendingDraftCheck = null;
      if (next != null) unawaited(_runDraftCheck(next));
    }
  }

  Future<WordDraftProofingResult?> _checkDraftSnapshot(
    String text,
    Object configuration,
  ) async {
    if (_disposed || !_enabled) return null;
    final document = _document();
    final request = OfficeProofingRequest(
      documentId: _documentIds[document] ??= 'document-${++_nextId}',
      blockId: 'draft-${++_nextId}',
      revision: 0,
      text: text,
      language: language,
      ignoredRuleIds: _ignoredRules,
    );
    final OfficeProofingReport checked;
    if (text.length > maxDraftLength || text.trim().isEmpty) {
      checked = OfficeProofingReport(
        request: request,
        results: [
          OfficeProofingResult(
            request: request,
            providerId: 'draft-checking',
            status: OfficeProofingStatus.unavailable,
            message: text.length > maxDraftLength
                ? 'This reply is too long for live checking. Check it after posting.'
                : 'Write a reply to check it.',
          ),
        ],
      );
    } else {
      checked = await _service.check(request);
    }
    if (_disposed || configuration != draftConfigurationKey) return null;
    // Some host providers do not consult the shared vocabulary themselves.
    // Apply exactly the document session's language-scoped spelling filter.
    final report = OfficeProofingReport(
      request: request,
      results: [
        for (final result in checked.results)
          OfficeProofingResult(
            request: request,
            providerId: result.providerId,
            status: result.status,
            message: result.message,
            findings: [
              for (final finding in result.findings)
                if (finding.category != OfficeProofingCategory.spelling ||
                    !vocabulary.contains(
                      finding.originalText,
                      language: request.language,
                    ))
                  finding,
            ],
          ),
      ],
    );
    return WordDraftProofingResult._(this, configuration, report);
  }

  /// A draft result remains valid through unrelated body edits and progress.
  /// The host must additionally retain the exact draft/thread identity.
  bool isDraftResultCurrent(
    WordDraftProofingResult result, {
    required String text,
  }) =>
      !_disposed &&
      _enabled &&
      identical(result._owner, this) &&
      result._configuration == draftConfigurationKey &&
      result.sourceText == text;

  String get _configurationKey =>
      '$_configuration|${_service.configurationKey}|'
      '${_manualService?.configurationKey ?? ''}|${vocabulary.revision}|'
      '$language|${_ignoredRules.join(',')}|'
      '${_detectionActive ? 'lid' : ''}';

  bool get _detectionActive =>
      !_disposed && _automaticLanguageDetection && _languageDetector != null;

  /// The paragraph language detector used for proofing routing, if any.
  ParagraphLanguageDetector? get languageDetector => _languageDetector;

  /// Installs (or removes) automatic language detection. Detection only
  /// steers which providers check a range: a confidently detected language
  /// replaces a *default* language (none set, or the document default), an
  /// explicit language always wins, and the document is never changed
  /// (see [resolveDetectedLanguage]). The session does not own [detector].
  void configureLanguageDetection(ParagraphLanguageDetector? detector) {
    if (_disposed) throw StateError('The proofing session is disposed.');
    if (identical(_languageDetector, detector)) return;
    _languageDetector = detector;
    _detections.clear();
    _configuration++;
    _cache.clear();
    refresh();
  }

  /// Whether automatic language detection steers proofing (on by default;
  /// it has no effect until a detector is configured).
  bool get automaticLanguageDetection => _automaticLanguageDetection;

  set automaticLanguageDetection(bool value) {
    if (_disposed || _automaticLanguageDetection == value) return;
    _automaticLanguageDetection = value;
    _configuration++;
    _cache.clear();
    refresh();
  }

  /// The detection already available for [text] (no classifier call), or
  /// null when detection is off or has not run for it yet.
  ParagraphLanguages? detectedLanguages(String text) {
    if (!_detectionActive) return null;
    return _detections[text] ?? _languageDetector!.cached(text);
  }

  /// Detects [texts] now (cached), regardless of whether automatic
  /// detection steers proofing. Returns null without a detector.
  Future<List<ParagraphLanguages>?> detectLanguages(List<String> texts) async {
    final detector = _languageDetector;
    if (_disposed || detector == null) return null;
    final results = await detector.detectAll(texts);
    if (_disposed || !identical(detector, _languageDetector)) return null;
    for (final result in results) {
      if (_detectionActive) _detections[result.text] = result;
    }
    return results;
  }

  ParagraphLanguages? _detectionForCapture(String text) {
    if (!_detectionActive) return null;
    _capturedTexts.add(text);
    final hit = _detections[text];
    if (hit != null) return hit;
    final cached = _languageDetector!.cached(text);
    if (cached != null) return _detections[text] = cached;
    if (scriptSegments(text).isNotEmpty) _missingDetections.add(text);
    return null;
  }

  /// Runs detection for the paragraphs the last capture could not resolve.
  /// Returns whether anything new was detected.
  Future<bool> _detectMissing() async {
    final detector = _languageDetector;
    if (!_detectionActive || detector == null || _missingDetections.isEmpty) {
      _missingDetections.clear();
      return false;
    }
    final texts = _missingDetections.toList();
    _missingDetections.clear();
    final results = await detector.detectAll(texts);
    if (!_detectionActive || !identical(detector, _languageDetector)) {
      return false;
    }
    for (final result in results) {
      _detections[result.text] = result;
    }
    return true;
  }

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
    _timer = null;
    if (_cache.isEmpty) {
      // No verified findings exist yet. Leave the first full capture behind
      // the typing debounce instead of scanning a document on every keystroke.
      _summary = WordProofingSummary(scheduled: _enabled);
      _findings = HashMap.identity();
    } else {
      final document = _document();
      final captured = _capture(document);
      _publishCached(
        captured,
        documentId: _documentIds[document] ??= 'document-${++_nextId}',
        revision: _revision(),
        useManual: false,
        scheduled: _enabled,
      );
    }
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

  /// Keeps settled reports when [recordHistory] synchronously records text
  /// that the host already applied and checked. Clean manual results need the
  /// same protection as findings: an unchanged history boundary must not turn
  /// their completed coverage into an unchecked or ordinary-only result.
  ///
  /// The callback always runs once. Results survive only one revision and one
  /// invalidation with the same document, configuration and complete source.
  /// Real edits and unfinished checks retain the normal invalidation path.
  void preserveUnchangedHistory(VoidCallback recordHistory) {
    final previous = _summary;
    if (_disposed ||
        !previous.hasResults ||
        previous.checking ||
        previous.scheduled ||
        previous.manualProvidersSkipped ||
        _timer != null) {
      recordHistory();
      return;
    }
    final document = _document();
    final documentId = _documentIds[document];
    final revision = _revision();
    final generation = _generation;
    final configuration = _configurationKey;
    final useManual = hasManualProviders;
    final captured = _capture(document);
    // A host can change model text without notifying the session. Do not
    // cancel its pending recheck or revive reports for that changed source.
    if (documentId == null ||
        previous.reports.any(
          (report) =>
              report.request.documentId != documentId ||
              report.request.revision != revision,
        ) ||
        captured.paragraphs.any(
          (snapshot) => _cachedReports(snapshot, useManual: useManual) == null,
        )) {
      recordHistory();
      return;
    }
    recordHistory();
    if (_disposed ||
        !identical(document, _document()) ||
        revision + 1 != _revision() ||
        generation + 1 != _generation ||
        configuration != _configurationKey ||
        captured.key != _capture(document).key) {
      return;
    }
    // The settled capture had no timer. The single invalidation above is the
    // only owner of this redundant debounce; no new provider work is needed.
    _timer?.cancel();
    _timer = null;
    _publishCached(
      captured,
      documentId: documentId,
      revision: _revision(),
      useManual: useManual,
      finished: previous.hasResults,
    );
    notifyListeners();
  }

  /// Finds the equivalent current result after a host records already-applied
  /// text in history. This is not permission to reuse an arbitrary stale UI
  /// handle: the host must first validate the old handle before that boundary.
  /// Configuration, story, complete source snapshot and finding contents must
  /// remain identical; only one document revision may have advanced.
  WordProofingIssue? rebindUnchangedIssue(WordProofingIssue issue) {
    final old = issue.finding;
    if (_disposed ||
        old.revision + 1 != _revision() ||
        old.documentId != _documentIds[_document()] ||
        issue._snapshot.configuration != _configurationKey) {
      return null;
    }
    WordProofingIssue? currentEquivalent() {
      for (final candidate in _summary.issues) {
        final finding = candidate.finding;
        if (identical(candidate.paragraph, issue.paragraph) &&
            candidate._snapshot.key == issue._snapshot.key &&
            candidate.language == issue.language &&
            finding.documentId == old.documentId &&
            finding.blockId == old.blockId &&
            finding.providerId == old.providerId &&
            finding.ruleId == old.ruleId &&
            finding.start == old.start &&
            finding.end == old.end &&
            finding.originalText == old.originalText &&
            finding.message == old.message &&
            finding.category == old.category &&
            listEquals(finding.replacements, old.replacements) &&
            isCurrent(candidate)) {
          return candidate;
        }
      }
      return null;
    }

    final current = currentEquivalent();
    if (current != null) return current;
    // The history notification publishes ordinary cached results and hides
    // manual findings. A commit of already-checked text may retain those exact
    // manual reports too, without running the provider again.
    if (!(_manualService?.providers.any(
          (provider) => provider.id == old.providerId,
        ) ??
        false)) {
      return null;
    }
    final captured = _capture(_document());
    final snapshot = captured.paragraphs
        .where((entry) => identical(entry.paragraph, issue.paragraph))
        .firstOrNull;
    final cached = _cache[issue.paragraph];
    if (snapshot == null ||
        snapshot.key != issue._snapshot.key ||
        cached == null ||
        cached.key != snapshot.key ||
        !cached.includesManual ||
        cached.reports.length != snapshot.segments.length) {
      return null;
    }
    final status = _summary;
    _publishCached(
      captured,
      documentId: old.documentId,
      revision: _revision(),
      useManual: true,
      checking: status.checking,
      scheduled: status.scheduled,
      finished: status.hasResults,
    );
    final rebound = currentEquivalent();
    notifyListeners();
    return rebound;
  }

  bool canCorrect(WordProofingIssue issue) {
    if (!isCurrent(issue)) return false;
    return _canEditSnapshotRange(
      issue._snapshot,
      issue.finding.start,
      issue.finding.end,
    );
  }

  /// Captures modeled text with the same story, field, control, revision and
  /// language boundaries used by proofing, without manufacturing a finding.
  WordTextRangeCapture captureTextRange(
    WmlParagraph paragraph,
    int start,
    int end,
  ) {
    if (_disposed) {
      return const WordTextRangeCapture._(
        WordTextRangeStatus.unsupportedTarget,
      );
    }
    final document = _document();
    final snapshot = _capture(document).paragraphs
        .where((entry) => identical(entry.paragraph, paragraph))
        .firstOrNull;
    if (snapshot == null) {
      return const WordTextRangeCapture._(
        WordTextRangeStatus.unsupportedTarget,
      );
    }
    if (start < 0 ||
        end <= start ||
        end > snapshot.text.length ||
        !_hasRangeBoundaries(snapshot, start, end)) {
      return const WordTextRangeCapture._(WordTextRangeStatus.invalidRange);
    }
    if (!_canEditSnapshotRange(snapshot, start, end) ||
        snapshot.insertionBarriers.any(
          (offset) => start < offset && offset < end,
        )) {
      return const WordTextRangeCapture._(WordTextRangeStatus.protectedContent);
    }
    final languages = <String>{};
    // A grapheme can span differently tagged formatting runs. It must remain
    // whole, but that does not make its source language unambiguous.
    var runStart = 0;
    for (final run in paragraph.inlines.whereType<WmlRun>()) {
      final runEnd = runStart + run.text.length;
      if (runStart < end && runEnd > start) {
        languages.add(
          normalizeProofingLanguage(
            wordRunProofingLanguage(
                  run,
                  paragraph,
                  documentComplexScriptLanguage: document.complexScriptLanguage,
                ) ??
                language,
          ),
        );
      }
      runStart = runEnd;
    }
    var covered = start;
    for (final segment in snapshot.segments) {
      if (segment.end <= start || segment.start >= end) continue;
      if (segment.start > covered) {
        return const WordTextRangeCapture._(
          WordTextRangeStatus.protectedContent,
        );
      }
      languages.add(segment.language);
      if (segment.end > covered) covered = segment.end;
    }
    if (covered < end || languages.isEmpty) {
      return const WordTextRangeCapture._(WordTextRangeStatus.protectedContent);
    }
    if (languages.length != 1) {
      return const WordTextRangeCapture._(WordTextRangeStatus.mixedLanguage);
    }
    return WordTextRangeCapture._(
      WordTextRangeStatus.ready,
      WordTextRangeTarget._(
        this,
        document,
        _revision(),
        snapshot,
        start,
        end,
        languages.single,
        _richTextKey(paragraph),
      ),
    );
  }

  bool isTextRangeCurrent(WordTextRangeTarget target) {
    if (_disposed ||
        !identical(target._owner, this) ||
        !identical(target._document, _document()) ||
        target._revision != _revision() ||
        target._snapshot.configuration != _configurationKey) {
      return false;
    }
    final current = _capture(_document()).paragraphs
        .where((entry) => identical(entry.paragraph, target.paragraph))
        .firstOrNull;
    return current != null &&
        current.key == target._snapshot.key &&
        _richTextKey(target.paragraph) == target._richTextKey;
  }

  // The source guard key already binds fields, controls, languages, tracked
  // ranges and story membership. Also bind direct rich-text mutations that do
  // not advance a controller's revision (for example, a host-edited hyperlink).
  static String _richTextKey(WmlParagraph paragraph) => jsonEncode([
    for (final inline in paragraph.inlines)
      if (inline is WmlRun)
        [
          'run',
          inline.text,
          inline.hyperlink?.url,
          inline.hyperlink?.file,
          inline.hyperlink?.anchor,
          inline.commentIds,
          inline.fieldInstruction,
          inline.fieldLocked,
          inline.fieldDirty,
          inline.noteRefId,
          inline.noteRefEndnote,
          inline.noteRefCustomMark,
          inline.properties.styleId,
          inline.properties.bold,
          inline.properties.italic,
          inline.properties.underline.name,
          inline.properties.strike,
          inline.properties.smallCaps,
          inline.properties.color,
          inline.properties.highlight,
          inline.properties.fontSizeHalfPoints,
          inline.properties.asciiFont,
          inline.properties.csFont,
          inline.properties.vertAlign.name,
          inline.properties.proofingLanguage,
          inline.properties.complexScriptLanguage,
          inline.properties.complexScript,
          inline.properties.noProof,
          inline.properties.sourcePropertiesXml,
          inline.properties.importedValues,
          inline.properties.explicitProperties.toList(),
        ]
      else if (inline is WmlBookmarkBoundary)
        ['bookmark', inline.id, inline.name, inline.isStart, inline.sourceXml]
      else if (inline is WmlFieldBoundary)
        [
          'field',
          inline.kind.name,
          inline.text,
          inline.sourceXml,
          inline.runPropertiesXml,
        ]
      else if (inline is WmlContentControlBoundary)
        ['control', inline.start, inline.control.xml]
      else
        [inline.runtimeType.toString(), identityHashCode(inline)],
  ]);

  bool canEditTextRange(WordTextRangeTarget target) =>
      isTextRangeCurrent(target) &&
      _canEditSnapshotRange(target._snapshot, target.start, target.end);

  static bool _hasRangeBoundaries(
    _ParagraphSnapshot snapshot,
    int start,
    int end,
  ) {
    final boundaries = <int>{
      0,
      for (final cluster in GraphemeClusters.segment(snapshot.text))
        cluster.end,
    };
    return boundaries.contains(start) && boundaries.contains(end);
  }

  bool _canEditSnapshotRange(_ParagraphSnapshot snapshot, int start, int end) {
    if (!_hasRangeBoundaries(snapshot, start, end)) {
      return false;
    }
    if (_document().trackRevisions &&
        (snapshot.insertionBarriers.contains(end) ||
            snapshot.guards.any(
              (range) => _touches(end, end, range.start, range.end),
            ))) {
      return false;
    }
    if (snapshot.locked ||
        snapshot.guards.any(
          (range) => _touches(start, end, range.start, range.end),
        )) {
      return false;
    }
    try {
      WordContentControls.assertCanEdit(snapshot.paragraph, start, end);
      final normalized = WmlRunEdit.normalizeRange(
        snapshot.paragraph,
        start,
        end,
      );
      return normalized.start == start && normalized.end == end;
    } on Object {
      return false;
    }
  }

  /// Explicit checks include manually configured providers. Background callers
  /// omit them and report that coverage separately. Verified ordinary findings
  /// remain available while other paragraphs or manual providers are checked.
  Future<WordProofingSummary> checkNow({
    bool includeManualProviders = true,
  }) async {
    if (_disposed) return _summary;
    _timer?.cancel();
    _timer = null;
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
    _capturedTexts.clear();
    var captured = _capture(document);
    if (_missingDetections.isNotEmpty) {
      // Paragraph detection is fast (well under a millisecond each); route
      // the whole pass with it rather than checking twice.
      final detected = await _detectMissing();
      // Even a discarded detection yielded control: the session, document
      // or provider configuration may have changed while it was pending.
      if (_disposed ||
          generation != _generation ||
          !identical(document, _document()) ||
          revision != _revision() ||
          configuration != _configurationKey) {
        return _summary;
      }
      if (detected) {
        captured = _capture(document);
      }
    }
    _detections.removeWhere((text, _) => !_capturedTexts.contains(text));
    _publishCached(
      captured,
      documentId: documentId,
      revision: revision,
      useManual: useManual,
      checking: true,
    );
    notifyListeners();
    bool current() =>
        !_disposed &&
        generation == _generation &&
        identical(document, _document()) &&
        revision == _revision() &&
        configuration == _configurationKey;

    // About twenty progress publications, plus early active-paragraph feedback,
    // avoid rebuilding every paragraph for each short result in long documents.
    final progressStride = (captured.paragraphs.length + 19) ~/ 20;
    // Visit the text being edited first without changing navigation/report
    // order. A caret move affects the next pass, never cancels the current one.
    final priorityParagraph = _priorityParagraph?.call();
    final priority = captured.paragraphs
        .where((snapshot) => identical(snapshot.paragraph, priorityParagraph))
        .firstOrNull;
    final checkOrder = [
      ?priority,
      for (final snapshot in captured.paragraphs)
        if (!identical(snapshot, priority)) snapshot,
    ];
    var processed = 0;
    for (final snapshot in checkOrder) {
      // Yield even when a cached/provider Future completes synchronously.
      await Future<void>.delayed(Duration.zero);
      if (!current()) return _summary;
      final cached = _cachedReports(snapshot, useManual: useManual);
      final reusable =
          cached != null && cached.every((report) => report.complete);
      final paragraphReports = <OfficeProofingReport>[];
      for (var index = 0; index < snapshot.segments.length; index++) {
        final request = _request(
          snapshot,
          snapshot.segments[index],
          documentId: documentId,
          revision: revision,
        );
        final OfficeProofingReport report;
        if (reusable) {
          report = _retarget(cached[index], request);
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
      }
      _cache[snapshot.paragraph] = _CachedParagraph(
        snapshot.key,
        paragraphReports,
        useManual,
      );
      processed++;
      if (processed < captured.paragraphs.length &&
          (identical(snapshot, priority) || processed % progressStride == 0)) {
        // Direct host edits can bypass the revision counter. Validate the
        // complete story/field/guard snapshot before exposing partial results.
        if (captured.key != _capture(document).key) {
          refresh();
          return _summary;
        }
        _publishCached(
          captured,
          documentId: documentId,
          revision: revision,
          useManual: useManual,
          checking: true,
        );
        notifyListeners();
      }
    }
    if (!current()) return _summary;
    if (captured.key != _capture(document).key) {
      refresh();
      return _summary;
    }
    _publishCached(
      captured,
      documentId: documentId,
      revision: revision,
      useManual: useManual,
      finished: true,
    );
    notifyListeners();
    return _summary;
  }

  OfficeProofingRequest _request(
    _ParagraphSnapshot snapshot,
    _Segment segment, {
    required String documentId,
    required int revision,
  }) => OfficeProofingRequest(
    documentId: documentId,
    blockId: _ids[snapshot.paragraph] ??= 'paragraph-${++_nextId}',
    revision: revision,
    text: segment.text,
    startOffset: segment.start,
    language: segment.language,
    ignoredRuleIds: _ignoredRules,
  );

  List<OfficeProofingReport>? _cachedReports(
    _ParagraphSnapshot snapshot, {
    required bool useManual,
    bool allowOrdinaryPreview = false,
  }) {
    final cached = _cache[snapshot.paragraph];
    if (cached == null ||
        cached.key != snapshot.key ||
        cached.reports.length != snapshot.segments.length) {
      return null;
    }
    if (cached.includesManual == useManual ||
        (useManual && allowOrdinaryPreview)) {
      return cached.reports;
    }
    if (useManual) return null;
    // A full check contains the ordinary results unchanged. Keep those marks
    // during typing, but never carry manual findings or coverage into a
    // background pass, and never start the manual service here.
    final manualIds = {
      for (final provider
          in _manualService?.providers ?? const <OfficeProofingProvider>[])
        provider.id,
    };
    return [
      for (final report in cached.reports)
        OfficeProofingReport(
          request: report.request,
          results: [
            for (final result in report.results)
              if (!manualIds.contains(result.providerId)) result,
          ],
        ),
    ];
  }

  void _publishCached(
    _DocumentSnapshot captured, {
    required String documentId,
    required int revision,
    required bool useManual,
    bool checking = false,
    bool scheduled = false,
    bool finished = false,
  }) {
    final attached = HashSet<WmlParagraph>.identity()
      ..addAll(captured.paragraphs.map((snapshot) => snapshot.paragraph));
    _cache.removeWhere((paragraph, _) => !attached.contains(paragraph));
    final previous = HashMap<WmlParagraph, List<WordProofingIssue>>.identity();
    for (final issue in _summary.issues) {
      previous.putIfAbsent(issue.paragraph, () => []).add(issue);
    }
    final reports = <OfficeProofingReport>[];
    final issues = <WordProofingIssue>[];
    var checked = 0;
    for (final snapshot in captured.paragraphs) {
      final cached = _cachedReports(
        snapshot,
        useManual: useManual,
        allowOrdinaryPreview: true,
      );
      if (cached == null) continue;
      if ((!useManual || _cache[snapshot.paragraph]!.includesManual) &&
          cached.isNotEmpty &&
          cached.every((report) => report.complete)) {
        checked++;
      }
      for (var index = 0; index < snapshot.segments.length; index++) {
        final segment = snapshot.segments[index];
        final report = _retarget(
          cached[index],
          _request(
            snapshot,
            segment,
            documentId: documentId,
            revision: revision,
          ),
        );
        reports.add(report);
        for (final finding in report.findings) {
          if (_ignoredOnce.contains(_issueKey(finding, snapshot))) continue;
          if (finding.category == OfficeProofingCategory.spelling &&
              vocabulary.contains(
                finding.originalText,
                language: segment.language,
              )) {
            continue;
          }
          // Keep a current finding's identity when only progress changes, so
          // an open suggestion menu remains usable while other text is checked.
          final existing = previous[snapshot.paragraph]
              ?.where(
                (issue) =>
                    issue._snapshot.key == snapshot.key &&
                    issue.language == segment.language &&
                    _sameFinding(issue.finding, finding),
              )
              .firstOrNull;
          issues.add(
            existing ??
                WordProofingIssue._(finding, snapshot, segment.language),
          );
        }
      }
    }
    final findings =
        HashMap<WmlParagraph, List<OfficeProofingFinding>>.identity();
    for (final issue in issues) {
      findings.putIfAbsent(issue.paragraph, () => []).add(issue.finding);
    }
    _findings = HashMap<WmlParagraph, List<OfficeProofingFinding>>.identity();
    for (final entry in findings.entries) {
      _findings[entry.key] = List.unmodifiable(entry.value);
    }
    _summary = WordProofingSummary(
      paragraphCount: captured.paragraphs.length,
      checkedParagraphCount: checked,
      skippedContentCount: captured.skipped,
      hasResults: finished || reports.isNotEmpty,
      reports: reports,
      issues: issues,
      checking: checking,
      scheduled: scheduled,
      manualProvidersSkipped: !useManual && _manualProvidersApplyTo(captured),
    );
  }

  static bool _sameFinding(
    OfficeProofingFinding left,
    OfficeProofingFinding right,
  ) =>
      left.documentId == right.documentId &&
      left.blockId == right.blockId &&
      left.revision == right.revision &&
      left.providerId == right.providerId &&
      left.ruleId == right.ruleId &&
      left.start == right.start &&
      left.end == right.end &&
      left.originalText == right.originalText &&
      left.message == right.message &&
      left.category == right.category &&
      listEquals(left.replacements, right.replacements);

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
        final languageRuns =
            <
              ({
                int start,
                int end,
                String language,
                WmlRun run,
                ({String? language, bool isDefault}) latin,
                ({String? language, bool isDefault}) complex,
              })
            >[];
        final detection = _detectionForCapture(text);
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
                wordRunProofingLanguage(
                      inline,
                      paragraph,
                      documentComplexScriptLanguage:
                          document.complexScriptLanguage,
                    ) ??
                    language,
              ),
              run: inline,
              latin: wordRunLanguageSlot(
                inline,
                paragraph,
                complexScript: false,
                documentLanguage: document.proofingLanguage,
              ),
              complex: wordRunLanguageSlot(
                inline,
                paragraph,
                complexScript: true,
                documentComplexScriptLanguage: document.complexScriptLanguage,
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
        // Scan current structure first: fields can start in a previous
        // paragraph, and a parent or inline control can change protection
        // without changing text. Only grapheme segmentation is memoized.
        final inputKey = jsonEncode([
          configuration,
          name,
          locked,
          paragraph.properties.fieldInstruction,
          paragraph.properties.pageNumberField,
          paragraph.properties.proofingLanguage,
          document.complexScriptLanguage,
          generated,
          emptyField,
          structure,
          [
            for (final range in exclusions) [range.start, range.end],
          ],
          [
            for (final range in guards) [range.start, range.end],
          ],
          barriers.toList(growable: false),
          insertionBarriers.toList(growable: false),
          [
            for (final run in languageRuns) [run.start, run.end, run.language],
          ],
          detection?.key,
        ]);
        final previous = _snapshotCache[paragraph];
        if (previous != null &&
            previous.inputKey == inputKey &&
            previous.snapshot.text == text) {
          if (previous.paragraphSkipped) skipped++;
          snapshots.add(previous.snapshot);
          continue;
        }
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
              ? _routedLanguage(
                  languageRuns[languageIndex],
                  detection?.segmentAt(start),
                  document,
                )
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
        final snapshot = _ParagraphSnapshot(
          paragraph,
          name,
          text,
          key,
          configuration,
          locked,
          guards,
          segments,
          insertionBarriers,
        );
        _snapshotCache[paragraph] = _CachedParagraphSnapshot(
          inputKey,
          snapshot,
          paragraphSkipped,
        );
        snapshots.add(snapshot);
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

  /// The proofing language of text at one position: the run's own Word
  /// language, unless detection found a language for the script segment
  /// and the run's slot for that script only holds a default.
  String _routedLanguage(
    ({
      int start,
      int end,
      String language,
      WmlRun run,
      ({String? language, bool isDefault}) latin,
      ({String? language, bool isDefault}) complex,
    })
    run,
    DetectedSegment? segment,
    WmlDocument document,
  ) {
    if (segment == null || segment.language == null) return run.language;
    final complex =
        run.run.properties.complexScript == true || segment.script.isComplex;
    final latinLanguage =
        run.latin.language ?? document.proofingLanguage ?? language;
    final slot = complex ? run.complex : run.latin;
    final current = complex
        ? run.complex.language ??
              document.complexScriptLanguage ??
              latinLanguage
        : latinLanguage;
    final routed = resolveDetectedLanguage(
      current: current,
      currentIsDefault: slot.isDefault,
      detection: segment,
      keepDefaultConfidence:
          _languageDetector?.policy.keepDefaultConfidence ?? 0.01,
    );
    return routed == null ? run.language : normalizeProofingLanguage(routed);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _pendingDraftCheck?.completer.complete();
    _pendingDraftCheck = null;
    _cache.clear();
    _findings.clear();
    _languageDetector = null;
    _detections.clear();
    _missingDetections.clear();
    _capturedTexts.clear();
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

final class _CachedParagraphSnapshot {
  const _CachedParagraphSnapshot(
    this.inputKey,
    this.snapshot,
    this.paragraphSkipped,
  );

  final String inputKey;
  final _ParagraphSnapshot snapshot;
  final bool paragraphSkipped;
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
