import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../l10n/office_plural.dart';
import 'background_proofing.dart';

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
        '$checkedParagraphCount of ${officeParagraphs(paragraphCount)} checked';
    final excluded = skippedContentCount == 0
        ? ''
        : '; ${officeCount(skippedContentCount, 'excluded or unsupported content range')}';
    if (reports.isEmpty) return '$coverage$excluded. No checkable text.';
    if (supported.isEmpty) {
      final language = reports.first.request.language;
      return '$coverage$excluded. No configured checker supports $language.';
    }
    if (problems.isNotEmpty) return '$coverage$excluded. ${problems.join(' ')}';
    if (manualProvidersSkipped) {
      return '$coverage$excluded. ${officeFindings(issues.length)}; '
          'choose Check document to include the manual grammar check.';
    }
    if (!complete) {
      return '$coverage$excluded. ${officeFindings(issues.length)}; coverage is incomplete.';
    }
    return issues.isEmpty
        ? '$coverage. No issues found by the configured providers.'
        : '$coverage. ${officeCount(issues.length, 'finding')} to review.';
  }
}

/// Default intervals of as-you-type proofing. The rationale and the
/// comparison with other editors are in docs/proofing/scheduling.md; the
/// measurements in docs/performance/typing-proofing-20261120.md.
abstract final class WordProofingTiming {
  /// Pause since the last edit after which the edited text is checked
  /// completely (spelling and grammar). The default of
  /// [WordProofingSchedule.pause].
  static const Duration idle = Duration(milliseconds: 1500);

  /// Delay between completing a word (typing a space or punctuation) and the
  /// spelling check of its paragraph. Later completions within this window
  /// share the check: it is not postponed by further typing.
  static const Duration wordCompletion = Duration(milliseconds: 150);

  /// Input-free time after which the rest of the document is checked in the
  /// background. The default of [WordProofingSchedule.backgroundIdle].
  static const Duration backgroundIdle = Duration(seconds: 3);

  /// Status chrome shows "Checking…" for background, initial document-wide
  /// or explicit passes that run this long. Local typing checks never show it.
  static const Duration checkingIndicatorDelay = Duration(milliseconds: 1000);

  /// Main-isolate time a pass may use before yielding to input and frames.
  static const Duration sliceBudget = Duration(milliseconds: 4);
}

/// When automatic checking runs.
enum WordProofingMode {
  /// Spelling when a word is completed, grammar when a sentence is completed
  /// or typing pauses, the rest of the document in idle time.
  whileTyping,

  /// Everything waits for a pause in typing.
  onPause,

  /// No automatic checking; only explicit checks (Check document, F7).
  manual,
}

/// The user-adjustable as-you-type proofing schedule. Changing
/// [WordProofingSession.schedule] takes effect immediately.
@immutable
final class WordProofingSchedule {
  const WordProofingSchedule({
    this.mode = WordProofingMode.whileTyping,
    this.checkSpelling = true,
    this.checkGrammar = true,
    this.pause = WordProofingTiming.idle,
    this.backgroundCheck = true,
    this.backgroundIdle = WordProofingTiming.backgroundIdle,
    this.hideTypingErrors = true,
  });

  /// The supported range of [pause] in settings UIs.
  static const Duration minPause = Duration(milliseconds: 300);
  static const Duration maxPause = Duration(seconds: 5);

  final WordProofingMode mode;

  /// Spelling providers run automatically (otherwise only explicit checks).
  final bool checkSpelling;

  /// Grammar and style providers run automatically.
  final bool checkGrammar;

  /// Pause in typing after which the edited text is checked completely.
  final Duration pause;

  /// Unchecked parts of the document are checked in idle time and after
  /// a document is loaded.
  final bool backgroundCheck;

  /// Input-free time before the background check starts.
  final Duration backgroundIdle;

  /// Findings that touch the caret where the user is typing stay hidden
  /// until the caret leaves them or the word is completed.
  final bool hideTypingErrors;

  bool get automatic =>
      mode != WordProofingMode.manual && (checkSpelling || checkGrammar);

  WordProofingSchedule copyWith({
    WordProofingMode? mode,
    bool? checkSpelling,
    bool? checkGrammar,
    Duration? pause,
    bool? backgroundCheck,
    Duration? backgroundIdle,
    bool? hideTypingErrors,
  }) => WordProofingSchedule(
    mode: mode ?? this.mode,
    checkSpelling: checkSpelling ?? this.checkSpelling,
    checkGrammar: checkGrammar ?? this.checkGrammar,
    pause: pause ?? this.pause,
    backgroundCheck: backgroundCheck ?? this.backgroundCheck,
    backgroundIdle: backgroundIdle ?? this.backgroundIdle,
    hideTypingErrors: hideTypingErrors ?? this.hideTypingErrors,
  );

  @override
  bool operator ==(Object other) =>
      other is WordProofingSchedule &&
      other.mode == mode &&
      other.checkSpelling == checkSpelling &&
      other.checkGrammar == checkGrammar &&
      other.pause == pause &&
      other.backgroundCheck == backgroundCheck &&
      other.backgroundIdle == backgroundIdle &&
      other.hideTypingErrors == hideTypingErrors;

  @override
  int get hashCode => Object.hash(
    mode,
    checkSpelling,
    checkGrammar,
    pause,
    backgroundCheck,
    backgroundIdle,
    hideTypingErrors,
  );

  @override
  String toString() =>
      'WordProofingSchedule(${mode.name}, spelling: $checkSpelling, '
      'grammar: $checkGrammar, pause: ${pause.inMilliseconds} ms, '
      'background: $backgroundCheck, hide typing: $hideTypingErrors)';
}

/// What started a pass; decides its providers, scope and visibility.
enum _Trigger {
  /// A word was completed: spelling of the typing paragraph only.
  word,

  /// A sentence or paragraph was completed: the edited text, all providers.
  sentence,

  /// Typing paused: the edited text, all providers.
  pause,

  /// Idle time: every unchecked paragraph, visible text first.
  background,

  /// Check document / F7: everything, including manual providers.
  explicit,
}

/// Provider groups scheduled separately.
enum _Kind { spelling, grammar }

/// Coarse, coalesced proofing state for status chrome. It changes only on
/// real transitions: a settled result stays visible while the next background
/// pass waits for a typing pause, and a pass shows [checking] only once it
/// has run for [WordProofingTiming.checkingIndicatorDelay].
enum WordProofingPhase {
  paused,
  notChecked,
  waiting,
  checking,
  partial,
  complete,
}

final class WordProofingStatus {
  const WordProofingStatus({
    required this.phase,
    this.issueCount = 0,
    this.message = '',
  });

  final WordProofingPhase phase;
  final int issueCount;

  /// The [WordProofingSummary.statusMessage] of the state shown.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is WordProofingStatus &&
      other.phase == phase &&
      other.issueCount == issueCount &&
      other.message == message;

  @override
  int get hashCode => Object.hash(phase, issueCount, message);

  @override
  String toString() => 'WordProofingStatus($phase, $issueCount)';
}

/// Ephemeral document proofing. The host owns vocabulary persistence; the
/// session owns and disposes its service. Unchanged paragraphs reuse checked
/// results while every published finding is rebound to the current revision.
///
/// Typing only marks the published results stale: the document is captured
/// and republished lazily, when a reader asks for the [summary] or a check
/// starts, never once per keystroke. Painting uses [paintFindingsLookup] to
/// remap findings for each visible paragraph without capturing the document.
final class WordProofingSession extends ChangeNotifier {
  WordProofingSession({
    required this._document,
    required this._revision,
    this._priorityParagraph,
    this._caretPosition,
    OfficeProofingService? service,
    OfficeProofingVocabulary? vocabulary,
    WordProofingSchedule schedule = const WordProofingSchedule(),
    Duration? debounce,
    this._visibleParagraphs,
    this.checkingIndicatorDelay = WordProofingTiming.checkingIndicatorDelay,
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary(),
       _schedule = debounce == null
           ? schedule
           : schedule.copyWith(pause: debounce) {
    _service = service ?? defaultWordProofingService(this.vocabulary);
  }

  final WmlDocument Function() _document;
  final int Function() _revision;
  final WmlParagraph? Function()? _priorityParagraph;

  /// The collapsed caret where the user types. It decides word and sentence
  /// completion and which findings stay hidden while typing.
  final ({WmlParagraph paragraph, int offset})? Function()? _caretPosition;

  /// Paragraphs on screen, checked first by background passes.
  final Iterable<WmlParagraph> Function()? _visibleParagraphs;
  final OfficeProofingVocabulary vocabulary;

  /// Live draft checks are bounded independently of the document's paragraphs.
  static const int maxDraftLength = 16384;

  /// Hosts may persist this owner-scoped snapshot in their own storage.
  void Function(Map<String, Object?> snapshot)? onVocabularyChanged;

  WordProofingSchedule _schedule;

  /// When and what automatic checking runs. Takes effect immediately:
  /// pending checks are rescheduled, results are kept.
  WordProofingSchedule get schedule => _schedule;

  set schedule(WordProofingSchedule value) {
    if (_disposed || value == _schedule) return;
    final previous = _schedule;
    _schedule = value;
    if (!value.hideTypingErrors && previous.hideTypingErrors) {
      _typing = null;
    }
    _cancelAutomaticTimers();
    if (_automatic) {
      // Pick up whatever the new schedule now covers once typing pauses.
      _timer = Timer(value.pause, () => _startAutomaticPass(_Trigger.pause));
    }
    if (_pendingPublish == null && !_published.checking) {
      _republish(scheduled: _automatic && _timer != null);
    }
    notifyListeners();
  }

  /// Pause since the last edit before the edited text is fully checked.
  Duration get debounce => _schedule.pause;

  /// Delay before [status] reports a running pass as checking.
  final Duration checkingIndicatorDelay;
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
  final Set<_ProofingOccurrence> _ignoredOnce = {};
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
  bool _compositionSuspended = false;
  int _draftEnabledRevision = 0;
  bool _draftCheckRunning = false;
  _DraftProofingRequest? _pendingDraftCheck;

  /// The pause timer.
  Timer? _timer;

  /// A pending word- or sentence-completion check and its trigger.
  Timer? _completionTimer;
  _Trigger? _completionTrigger;
  DateTime? _lastTypingAt;
  Duration _typingGap = const Duration(milliseconds: 1000);
  Timer? _backgroundTimer;
  Timer? _checkingIndicatorTimer;

  /// Whether the running pass may show "Checking…".
  bool _passShowsProgress = false;
  WmlDocument? _observedDocument;
  int? _observedRevision;
  String? _observedConfiguration;
  WordProofingSummary _published = WordProofingSummary();

  /// A republish requested by an edit, performed on first read.
  ({bool scheduled})? _pendingPublish;
  Map<WmlParagraph, List<OfficeProofingFinding>>? _provisionalFindings;
  final _provisionalParagraphs =
      HashMap<WmlParagraph, List<OfficeProofingFinding>?>.identity();
  final Map<WmlParagraph, String> _findingTexts = HashMap.identity();

  /// Where the latest edit left the collapsed caret, until the caret moves
  /// without an edit. Findings touching it stay hidden while typing.
  ({WmlParagraph paragraph, int offset})? _typing;

  /// Whether the latest publication hid a finding at [_typing].
  bool _hidAtCaret = false;

  /// Paragraphs edited at the caret since they were last checked.
  final Set<WmlParagraph> _touched = HashSet.identity();

  /// Paragraphs of the latest pass's capture, to recognize new paragraphs.
  Set<WmlParagraph> _known = HashSet.identity();
  WmlDocument? _knownDocument;

  /// Last detected languages per paragraph, routing text whose new version
  /// has not been detected yet (language detection waits for a completed
  /// sentence or a pause).
  final Expando<ParagraphLanguages> _lastDetection = Expando(
    'proofing paragraph detection',
  );
  final ValueNotifier<WordProofingStatus> _status = ValueNotifier(
    const WordProofingStatus(phase: WordProofingPhase.paused),
  );

  /// Instrumentation: passes started and paragraphs sent to providers since
  /// the session was created, and passes per trigger.
  int passCount = 0;
  int checkedParagraphCount = 0;
  final Map<String, int> passCountsByTrigger = {};

  /// Passes over the typed text whose results changed nothing on screen and
  /// therefore did not notify listeners.
  int silentPassCount = 0;

  WordProofingSummary get _summary {
    final pending = _pendingPublish;
    if (pending != null) {
      _pendingPublish = null;
      _clearProvisionalFindings();
      final document = _document();
      // Readers can be widgets in build: never notify listeners from here.
      _flushing = true;
      try {
        _publishCached(
          _capture(document),
          documentId: _documentIds[document] ??= 'document-${++_nextId}',
          revision: _revision(),
          useManual: false,
          scheduled: pending.scheduled,
        );
      } finally {
        _flushing = false;
      }
    }
    return _published;
  }

  bool _flushing = false;

  set _summary(WordProofingSummary value) {
    _pendingPublish = null;
    _clearProvisionalFindings();
    _published = value;
    if (_flushing) {
      scheduleMicrotask(_updateStatus);
    } else {
      _updateStatus();
    }
  }

  WordProofingSummary get summary => _summary;
  bool get checking => _pendingPublish == null && _published.checking;

  /// Coalesced state for status chrome; see [WordProofingStatus].
  ValueListenable<WordProofingStatus> get status => _status;

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

  /// Findings to paint. While an edit's republish is pending, unchanged
  /// paragraphs keep their underlines without capturing the document. In a
  /// paragraph whose text changed, marks in the unchanged text before the
  /// edit stay, marks in the unchanged text after it move with it, and marks
  /// touching the edited range (including a word extended at either end)
  /// are dropped until the next check, so typing
  /// does not make the paragraph's other underlines blink.
  Map<WmlParagraph, List<OfficeProofingFinding>> get findingsByParagraph {
    if (_pendingPublish == null) return UnmodifiableMapView(_findings);
    if (_provisionalFindings case final prepared?) return prepared;
    final all = HashMap<WmlParagraph, List<OfficeProofingFinding>>.identity();
    for (final paragraph in _findings.keys) {
      if (_paintFindingsFor(paragraph) case final kept?) all[paragraph] = kept;
    }
    _provisionalParagraphs.clear();
    return _provisionalFindings = UnmodifiableMapView(all);
  }

  /// The canvas asks for individual visible paragraphs. During typing this
  /// avoids reading and rebuilding the marks on every page before painting.
  List<OfficeProofingFinding>? Function(WmlParagraph)?
  get paintFindingsLookup => _findings.isEmpty ? null : _paintFindingsFor;

  List<OfficeProofingFinding>? _paintFindingsFor(WmlParagraph paragraph) {
    final findings = _findings[paragraph];
    if (findings == null || _pendingPublish == null) return findings;
    if (_provisionalFindings case final prepared?) return prepared[paragraph];
    return _provisionalParagraphs.putIfAbsent(paragraph, () {
      final kept = _provisionalMarks(
        findings,
        _findingTexts[paragraph],
        paragraph.text,
      );
      return kept == null || kept.isEmpty ? null : kept;
    });
  }

  void _clearProvisionalFindings() {
    _provisionalFindings = null;
    _provisionalParagraphs.clear();
  }

  static List<OfficeProofingFinding>? _provisionalMarks(
    List<OfficeProofingFinding> findings,
    String? before,
    String now,
  ) {
    if (before == null) return null;
    if (before == now) return findings;
    return List.unmodifiable(_remapFindings(findings, before, now));
  }

  /// [findings] of [before] that lie in text [now] left unchanged, moved to
  /// their offsets in [now]; findings touching the changed range are dropped.
  static List<OfficeProofingFinding> _remapFindings(
    Iterable<OfficeProofingFinding> findings,
    String before,
    String now,
  ) {
    final limit = before.length < now.length ? before.length : now.length;
    var prefix = 0;
    while (prefix < limit &&
        before.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < limit - prefix &&
        before.codeUnitAt(before.length - 1 - suffix) ==
            now.codeUnitAt(now.length - 1 - suffix)) {
      suffix++;
    }
    final shift = now.length - before.length;
    final changedEnd = before.length - suffix;
    return [
      for (final finding in findings)
        if (finding.end < prefix)
          finding
        else if (finding.start > changedEnd)
          OfficeProofingFinding(
            documentId: finding.documentId,
            blockId: finding.blockId,
            revision: finding.revision,
            providerId: finding.providerId,
            start: finding.start + shift,
            end: finding.end + shift,
            originalText: finding.originalText,
            ruleId: finding.ruleId,
            message: finding.message,
            category: finding.category,
            replacements: finding.replacements,
          ),
    ];
  }

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

  ParagraphLanguages? _detectionForCapture(
    WmlParagraph paragraph,
    String text,
  ) {
    if (!_detectionActive) return null;
    _capturedTexts.add(text);
    final hit = _detections[text] ?? _languageDetector!.cached(text);
    if (hit != null) {
      _detections[text] = hit;
      return _lastDetection[paragraph] = hit;
    }
    if (scriptSegments(text).isEmpty) return null;
    _missingDetections.add(text);
    return _provisionalDetection(_lastDetection[paragraph], text);
  }

  /// Routes edited text like its previous version until detection runs
  /// again, when that version was in one language and one script. Mixed
  /// paragraphs fall back to their Word language tags.
  static ParagraphLanguages? _provisionalDetection(
    ParagraphLanguages? previous,
    String text,
  ) {
    if (previous == null || previous.segments.isEmpty) return null;
    final first = previous.segments.first;
    if (first.language == null ||
        previous.segments.any(
          (segment) =>
              segment.language != first.language ||
              segment.script != first.script,
        )) {
      return null;
    }
    return ParagraphLanguages(text, [
      DetectedSegment(
        start: 0,
        end: text.length,
        script: first.script,
        language: first.language,
        confidence: first.confidence,
        byScript: first.byScript,
      ),
    ]);
  }

  /// Runs detection for the paragraphs the last capture could not resolve,
  /// limited to the texts in [only]. Returns whether anything was detected.
  Future<bool> _detectMissing({Set<String>? only}) async {
    final detector = _languageDetector;
    final texts = [
      for (final text in _missingDetections)
        if (only == null || only.contains(text)) text,
    ];
    _missingDetections.clear();
    if (!_detectionActive || detector == null || texts.isEmpty) {
      return false;
    }
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

  /// Cancels pending automatic work while the host previews unfinished IME
  /// text. Cached findings remain available. The next [observeDocument] call
  /// resumes scheduling after composition commits, even without a text change.
  void suspendForComposition() {
    if (_disposed || _compositionSuspended) return;
    _compositionSuspended = true;
    _invalidate();
  }

  /// Called for controller-observed content changes. Selection and scroll
  /// notifications do not repeatedly cancel work or schedule new checks.
  void observeDocument() {
    if (_disposed) return;
    final resumedComposition = _compositionSuspended;
    _compositionSuspended = false;
    final document = _document();
    final revision = _revision();
    final configuration = _configurationKey;
    if (!identical(document, _observedDocument)) {
      _cache.clear();
      _ignoredOnce.clear();
      _touched.clear();
      _typing = null;
    }
    if (!resumedComposition &&
        identical(document, _observedDocument) &&
        revision == _observedRevision &&
        configuration == _observedConfiguration) {
      _releaseTypingPosition();
      return;
    }
    final contentEdit =
        identical(document, _observedDocument) &&
        configuration == _observedConfiguration;
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = configuration;
    _invalidate();
    if (contentEdit) _queueTypingEvaluation();
  }

  bool _typingEvaluationQueued = false;

  /// Hosts may notify while an edit is still in progress (for example from
  /// a history batch, before the caret moves past the inserted text), so the
  /// caret is read once the edit's synchronous work is done.
  void _queueTypingEvaluation() {
    if (_typingEvaluationQueued) return;
    _typingEvaluationQueued = true;
    scheduleMicrotask(() {
      _typingEvaluationQueued = false;
      if (_disposed) return;
      final trigger = _typingTrigger();
      if (trigger != null) _scheduleCompletion(trigger);
    });
  }

  static final RegExp _wordCharacter = RegExp(
    r"[\p{L}\p{M}\p{N}'\u2019_\-]",
    unicode: true,
  );
  static const String _sentenceEnds = '.!?\u2026\u061F\u3002\uFF01\uFF1F';

  /// The caret and its paragraph's length at the latest observation.
  ({WmlParagraph paragraph, int offset, int length})? _caretSample;

  ({WmlParagraph paragraph, int offset, int length})? _sampleCaret() {
    final caret = _caretPosition?.call();
    return caret == null
        ? null
        : (
            paragraph: caret.paragraph,
            offset: caret.offset,
            length: caret.paragraph.text.length,
          );
  }

  /// Records where typing happens and whether the edit completed a word
  /// (space or punctuation typed) or a sentence (sentence-final punctuation,
  /// or Enter, which completes the previous paragraph).
  ///
  /// An edit is typing when the caret moved by exactly the length change of
  /// its paragraph (inserting or deleting at the caret). Undo, corrections,
  /// replacements and edits elsewhere are not, and show findings at once.
  _Trigger? _typingTrigger() {
    final before = _caretSample;
    final after = _caretSample = _sampleCaret();
    final wasTyping = _typing;
    _typing = null;
    if (after == null || before == null) return null;
    if (!identical(before.paragraph, after.paragraph)) {
      // Enter after typing: the paragraph typed before is complete.
      if (wasTyping != null &&
          identical(wasTyping.paragraph, before.paragraph) &&
          after.offset == 0) {
        _touched.add(before.paragraph);
        _touched.add(after.paragraph);
        _typing = (paragraph: after.paragraph, offset: 0);
        return _Trigger.sentence;
      }
      return null;
    }
    final delta = after.length - before.length;
    if (delta == 0 || after.offset - before.offset != delta) return null;
    _typing = (paragraph: after.paragraph, offset: after.offset);
    _noteTypingCadence();
    _touched.add(after.paragraph);
    // Deleting is not finishing anything.
    if (delta < 0) return null;
    final text = after.paragraph.text;
    final typed = text[after.offset - 1];
    if (_sentenceEnds.contains(typed)) return _Trigger.sentence;
    if (_wordCharacter.hasMatch(typed)) return null;
    return _Trigger.word;
  }

  void _noteTypingCadence() {
    final now = DateTime.now();
    final previous = _lastTypingAt;
    _lastTypingAt = now;
    if (previous == null) return;
    final gap = now.difference(previous);
    if (gap <= Duration.zero || gap > const Duration(seconds: 2)) return;
    // An exponential moving average tolerates a single hesitation without
    // making the next burst look slow.
    _typingGap = Duration(
      microseconds: (_typingGap.inMicroseconds * 3 + gap.inMicroseconds) ~/ 4,
    );
  }

  Duration get _wordCompletionDelay {
    if (_typingGap < const Duration(milliseconds: 180)) {
      return const Duration(milliseconds: 350);
    }
    if (_typingGap < const Duration(milliseconds: 300)) {
      return const Duration(milliseconds: 250);
    }
    return WordProofingTiming.wordCompletion;
  }

  void _scheduleCompletion(_Trigger trigger) {
    if (!_automatic || _schedule.mode != WordProofingMode.whileTyping) return;
    final kinds = _kindsFor(trigger);
    if (kinds.isEmpty) return;
    if (_completionTimer != null) {
      // A pending word check becomes a sentence check. A word check is a
      // trailing debounce: while the user keeps typing, postpone it instead
      // of running a provider pass in the middle of a burst.
      if (trigger == _Trigger.sentence) {
        _completionTrigger = trigger;
        return;
      }
      _completionTimer!.cancel();
    }
    _completionTrigger = trigger;
    final delay = trigger == _Trigger.word
        ? _wordCompletionDelay
        : WordProofingTiming.wordCompletion;
    _completionTimer = Timer(delay, () {
      final fired = _completionTrigger ?? _Trigger.word;
      _completionTimer = null;
      _completionTrigger = null;
      _startAutomaticPass(fired);
    });
  }

  /// A caret move away from where the user typed shows the findings hidden
  /// there, without a provider call. The host notifies its own listeners.
  void _releaseTypingPosition() {
    if (_typingEvaluationQueued) return;
    _caretSample = _sampleCaret();
    final typing = _typing;
    if (typing == null) return;
    final caret = _caretPosition?.call();
    if (caret != null &&
        identical(caret.paragraph, typing.paragraph) &&
        caret.offset == typing.offset) {
      return;
    }
    _typing = null;
    if (!_hidAtCaret || _pendingPublish != null) return;
    final summary = _published;
    if (summary.checking) return;
    _republish(scheduled: summary.scheduled, finished: summary.hasResults);
  }

  /// Republishes cached results for the current revision, no provider call.
  void _republish({bool scheduled = false, bool finished = false}) {
    final document = _document();
    final documentId = _documentIds[document];
    if (documentId == null) return;
    _publishCached(
      _capture(document),
      documentId: documentId,
      revision: _revision(),
      useManual: false,
      scheduled: scheduled,
      finished: finished,
    );
  }

  /// Hosts call this after direct model edits or changes to host-owned words.
  void refresh() {
    if (_disposed) return;
    if (!identical(_observedDocument, _document())) {
      _cache.clear();
      _ignoredOnce.clear();
      _touched.clear();
      _typing = null;
    }
    _observedDocument = _document();
    _observedRevision = _revision();
    _observedConfiguration = _configurationKey;
    _invalidate();
    notifyListeners();
  }

  bool get _automatic =>
      !_compositionSuspended && _enabled && _schedule.automatic;

  /// The provider groups an automatic pass of [trigger] runs.
  Set<_Kind> _kindsFor(_Trigger trigger) => switch (trigger) {
    _Trigger.explicit => _Kind.values.toSet(),
    _Trigger.word => {if (_schedule.checkSpelling) _Kind.spelling},
    _ => {
      if (_schedule.checkSpelling) _Kind.spelling,
      if (_schedule.checkGrammar) _Kind.grammar,
    },
  };

  void _cancelAutomaticTimers() {
    _timer?.cancel();
    _timer = null;
    _completionTimer?.cancel();
    _completionTimer = null;
    _completionTrigger = null;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  void _invalidate() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    // Input postpones idle-time work; the next pause pass re-arms it.
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    _checkingIndicatorTimer?.cancel();
    _checkingIndicatorTimer = null;
    _checkingVisible = false;
    final automatic = _automatic;
    if (_cache.isEmpty) {
      // No verified findings exist yet. Leave the first full capture behind
      // the typing debounce instead of scanning a document on every keystroke.
      _summary = WordProofingSummary(scheduled: automatic);
      _findings = HashMap.identity();
      _findingTexts.clear();
    } else {
      // Rebinding cached results to the new revision needs a full capture.
      // Defer it to the first reader or the next pass, so a keystroke costs
      // no document-wide work; consecutive edits coalesce into one capture.
      _pendingPublish = (scheduled: automatic);
      _clearProvisionalFindings();
      _updateStatus();
    }
    if (automatic) {
      _timer = Timer(
        _schedule.pause,
        () => _startAutomaticPass(_Trigger.pause),
      );
    } else {
      _cancelAutomaticTimers();
    }
  }

  void _startAutomaticPass(_Trigger trigger) {
    if (_disposed || !_automatic) return;
    unawaited(_runPass(trigger));
  }

  /// Arms the idle-time check of the rest of the document after an
  /// automatic pass, when unchecked text remains and no pause pass is due.
  void _armBackground(_DocumentSnapshot captured) {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    if (!_automatic ||
        !_schedule.backgroundCheck ||
        _timer != null ||
        _completionTimer != null) {
      return;
    }
    final kinds = _kindsFor(_Trigger.background);
    if (!captured.paragraphs.any(
      (snapshot) => _needsWork(snapshot, kinds, useManual: false),
    )) {
      return;
    }
    // The pause pass already waited for the pause since the last input.
    final remaining = _schedule.backgroundIdle - _schedule.pause;
    _backgroundTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        _backgroundTimer = null;
        _startAutomaticPass(_Trigger.background);
      },
    );
  }

  /// Derives the coalesced [status] from the published summary.
  void _updateStatus() {
    if (_disposed) return;
    final previous = _status.value;
    final pending = _pendingPublish;
    final summary = _published;
    final checking = pending == null && summary.checking;
    final scheduled = pending?.scheduled ?? summary.scheduled;
    final settled =
        previous.phase == WordProofingPhase.partial ||
        previous.phase == WordProofingPhase.complete;
    WordProofingStatus next;
    if (checking || scheduled) {
      if (checking && _checkingVisible) {
        next = WordProofingStatus(
          phase: WordProofingPhase.checking,
          issueCount: previous.issueCount,
          message: 'Checking document…',
        );
      } else if (settled && summary.hasResults) {
        // Settled results stay on screen while typing and short passes run.
        next = previous;
      } else if (scheduled) {
        next = const WordProofingStatus(
          phase: WordProofingPhase.waiting,
          message: 'Waiting for a pause in typing…',
        );
      } else {
        next = previous;
      }
      if (checking &&
          _passShowsProgress &&
          !_checkingVisible &&
          _checkingIndicatorTimer == null) {
        final generation = _generation;
        _checkingIndicatorTimer = Timer(checkingIndicatorDelay, () {
          _checkingIndicatorTimer = null;
          if (_disposed || generation != _generation || !this.checking) {
            return;
          }
          _checkingVisible = true;
          _updateStatus();
        });
      }
    } else {
      _checkingIndicatorTimer?.cancel();
      _checkingIndicatorTimer = null;
      _checkingVisible = false;
      final count = summary.issues.length;
      final message = summary.statusMessage;
      next = !_enabled
          ? WordProofingStatus(
              phase: WordProofingPhase.paused,
              message: message,
            )
          : !summary.hasResults
          ? WordProofingStatus(
              phase: WordProofingPhase.notChecked,
              message: message,
            )
          : WordProofingStatus(
              phase: summary.complete
                  ? WordProofingPhase.complete
                  : WordProofingPhase.partial,
              issueCount: count,
              message: message,
            );
    }
    _status.value = next;
  }

  bool _checkingVisible = false;

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

  _ProofingOccurrence _issueKey(
    OfficeProofingFinding finding,
    _ParagraphSnapshot snapshot,
  ) => (
    blockId: finding.blockId,
    snapshotKey: snapshot.key,
    providerId: finding.providerId,
    ruleId: finding.ruleId,
    start: finding.start,
    end: finding.end,
  );

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
        _timer != null ||
        _completionTimer != null) {
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
        !captured.sameAs(_capture(document))) {
      return;
    }
    // The settled capture had no timer. The single invalidation above is the
    // only owner of this redundant debounce; no new provider work is needed.
    _cancelAutomaticTimers();
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
          inline.properties.allCaps,
          inline.properties.color,
          inline.properties.highlight,
          inline.properties.fontSizeHalfPoints,
          inline.properties.asciiFont,
          inline.properties.csFont,
          inline.properties.vertAlign.name,
          inline.properties.positionHalfPoints,
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

  /// Explicit checks include manually configured providers and check every
  /// paragraph without a reusable result at once, the edited one first.
  /// Verified ordinary findings remain available while other paragraphs or
  /// manual providers are checked.
  ///
  /// The pass yields to input and frames after each
  /// [WordProofingTiming.sliceBudget] of main-isolate work and publishes
  /// partial results about twenty times per pass over the changed paragraphs.
  Future<WordProofingSummary> checkNow({bool includeManualProviders = true}) =>
      _runPass(_Trigger.explicit, includeManual: includeManualProviders);

  /// The providers of [kinds], or null for all of them.
  bool Function(OfficeProofingProvider)? _filter(Set<_Kind> kinds) =>
      kinds.length == _Kind.values.length
      ? null
      : (provider) => kinds.contains(_kindOf(provider));

  static _Kind _kindOf(OfficeProofingProvider provider) {
    try {
      final categories = provider.categories;
      return categories.length == 1 &&
              categories.contains(OfficeProofingCategory.spelling)
          ? _Kind.spelling
          : _Kind.grammar;
    } on Object {
      return _Kind.grammar;
    }
  }

  /// [kinds] restricted to groups the ordinary service actually has.
  Set<_Kind> _available(Set<_Kind> kinds) {
    final present = {for (final p in _service.providers) _kindOf(p)};
    // Without providers the service reports its own unavailability once.
    if (present.isEmpty) return kinds;
    return kinds.intersection(present);
  }

  /// Whether [snapshot] lacks a reusable, settled result for [kinds].
  bool _needsWork(
    _ParagraphSnapshot snapshot,
    Set<_Kind> kinds, {
    required bool useManual,
  }) {
    final cached = _cachedReports(snapshot, useManual: useManual);
    if (cached == null || !cached.every(_settled)) return true;
    return !_cache[snapshot.paragraph]!.kinds.containsAll(_available(kinds));
  }

  /// The paragraphs a pass of [trigger] checks, in checking order.
  List<_ParagraphSnapshot> _scope(
    _Trigger trigger,
    _DocumentSnapshot captured,
    Set<_Kind> kinds, {
    required bool useManual,
    required bool whole,
    required WmlDocument document,
  }) {
    final typing = _typing?.paragraph;
    final priorityParagraph = typing ?? _priorityParagraph?.call();
    final knownDocument = identical(_knownDocument, document);
    _ParagraphSnapshot? priority;
    final rest = <_ParagraphSnapshot>[];
    var priorityIndex = 0;
    for (var index = 0; index < captured.paragraphs.length; index++) {
      final snapshot = captured.paragraphs[index];
      final paragraph = snapshot.paragraph;
      if (identical(paragraph, priorityParagraph)) priorityIndex = index;
      if (trigger == _Trigger.word && !identical(paragraph, typing)) continue;
      if (!_needsWork(snapshot, kinds, useManual: useManual)) {
        final cached = _cache[paragraph];
        // A background pass never carries manual results forward: the next
        // explicit check runs the manual providers again.
        if (cached != null && !useManual && cached.includesManual) {
          _cache[paragraph] = _CachedParagraph(
            snapshot.key,
            _cachedReports(snapshot, useManual: false)!,
            false,
            cached.kinds,
          );
        }
        continue;
      }
      if (!whole &&
          trigger != _Trigger.word &&
          !_touched.contains(paragraph) &&
          // Edited elsewhere (replace, paste, undo) or checked in part.
          !_cache.containsKey(paragraph) &&
          // Inserted since the last pass.
          (!knownDocument || _known.contains(paragraph))) {
        continue;
      }
      if (identical(paragraph, priorityParagraph)) {
        priority = snapshot;
      } else {
        rest.add(snapshot);
      }
    }
    if (trigger == _Trigger.background && rest.length > 1) {
      // Visible text first, then outward from the caret.
      final visible = HashSet<WmlParagraph>.identity();
      try {
        visible.addAll(_visibleParagraphs?.call() ?? const <WmlParagraph>[]);
      } on Object {
        // Layout may be unavailable; the caret distance still orders.
      }
      final position = HashMap<WmlParagraph, int>.identity();
      for (var index = 0; index < captured.paragraphs.length; index++) {
        position[captured.paragraphs[index].paragraph] = index;
      }
      int rank(_ParagraphSnapshot snapshot) {
        final distance = (position[snapshot.paragraph]! - priorityIndex).abs();
        return visible.contains(snapshot.paragraph)
            ? distance
            : distance + captured.paragraphs.length;
      }

      // Ties keep document order (List.sort is not stable).
      rest.sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0
            ? byRank
            : position[a.paragraph]!.compareTo(position[b.paragraph]!);
      });
    }
    return [?priority, ...rest];
  }

  /// Runs one pass. Each trigger has its own providers ([_kindsFor]),
  /// scope ([_scope]) and visibility: background, initial document-wide and
  /// explicit passes publish progress and may show "Checking…"; local typing
  /// checks publish their results once, when they finish.
  Future<WordProofingSummary> _runPass(
    _Trigger trigger, {
    bool includeManual = false,
  }) async {
    if (_disposed) return _summary;
    final explicit = trigger == _Trigger.explicit;
    switch (trigger) {
      case _Trigger.explicit:
        _cancelAutomaticTimers();
        // The user asked for every finding, including the one being typed.
        _typing = null;
      case _Trigger.pause:
        _timer?.cancel();
        _timer = null;
        _completionTimer?.cancel();
        _completionTimer = null;
        _completionTrigger = null;
      case _Trigger.sentence:
      case _Trigger.word:
        break;
      case _Trigger.background:
        _backgroundTimer?.cancel();
        _backgroundTimer = null;
    }
    final kinds = _kindsFor(trigger);
    // No configured provider belongs to the requested groups (for example
    // no spelling-only provider for a word check): nothing to run.
    if (kinds.isEmpty || (!explicit && _available(kinds).isEmpty)) {
      return _summary;
    }
    // Nothing checked yet (a document was loaded or the configuration
    // changed): the first pause checks the whole document, like idle time.
    final loading =
        (trigger == _Trigger.pause || trigger == _Trigger.sentence) &&
        _schedule.backgroundCheck &&
        _cache.isEmpty;
    final whole = explicit || trigger == _Trigger.background || loading;
    final showProgress = whole;
    final generation = ++_generation;
    final document = _document();
    final revision = _revision();
    final configuration = _configurationKey;
    final manual = includeManual ? _manualService : null;
    final useManual = manual?.providers.isNotEmpty ?? false;
    if (!identical(document, _observedDocument)) {
      _cache.clear();
      _ignoredOnce.clear();
      _touched.clear();
    }
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = configuration;
    final documentId = _documentIds[document] ??= 'document-${++_nextId}';
    bool current() =>
        !_disposed &&
        generation == _generation &&
        identical(document, _document()) &&
        revision == _revision() &&
        configuration == _configurationKey;

    _capturedTexts.clear();
    var captured = _capture(document);
    var checkOrder = _scope(
      trigger,
      captured,
      kinds,
      useManual: useManual,
      whole: whole,
      document: document,
    );
    // Language detection runs for the text about to be checked, when a
    // sentence or paragraph is complete or typing pauses; never per word.
    if (trigger != _Trigger.word && _missingDetections.isNotEmpty) {
      final wanted = {for (final snapshot in checkOrder) snapshot.text};
      final detected = await _detectMissing(only: wanted);
      // Even a discarded detection yielded control: the session, document
      // or provider configuration may have changed while it was pending.
      if (!current()) return _summary;
      if (detected) {
        _capturedTexts.clear();
        captured = _capture(document);
        checkOrder = _scope(
          trigger,
          captured,
          kinds,
          useManual: useManual,
          whole: whole,
          document: document,
        );
      }
    }
    _missingDetections.clear();
    _detections.removeWhere((text, _) => !_capturedTexts.contains(text));
    if (checkOrder.isEmpty && !explicit) {
      // Nothing to check: settle a stale publication quietly.
      if (_pendingPublish != null || _published.scheduled) {
        _publishCached(
          captured,
          documentId: documentId,
          revision: revision,
          useManual: false,
          finished: _published.hasResults || _cache.isNotEmpty,
        );
        notifyListeners();
      }
      _finishAutomatic(trigger, captured, document);
      return _summary;
    }
    passCount++;
    passCountsByTrigger.update(trigger.name, (n) => n + 1, ifAbsent: () => 1);
    final hasWork = checkOrder.isNotEmpty;
    _passShowsProgress = showProgress && hasWork;
    if (_passShowsProgress) {
      _publishCached(
        captured,
        documentId: documentId,
        revision: revision,
        useManual: useManual,
        checking: true,
      );
      notifyListeners();
    }

    final wanted = _available(kinds);
    final allKinds = _available(_Kind.values.toSet());
    Future<_CachedParagraph?> evaluate(_ParagraphSnapshot snapshot) async {
      // Reuse results for the same text and add the missing provider groups.
      final previous = _cache[snapshot.paragraph];
      final reusable =
          !useManual &&
          previous != null &&
          !previous.includesManual &&
          previous.key == snapshot.key &&
          previous.reports.length == snapshot.segments.length &&
          previous.reports.every(_settled);
      final missing = reusable ? wanted.difference(previous.kinds) : wanted;
      final paragraphReports = <OfficeProofingReport>[];
      // Every available group already has settled results (an empty
      // provider selection must never be sent or cached).
      if (!useManual && missing.isEmpty) return null;
      for (var index = 0; index < snapshot.segments.length; index++) {
        final request = _request(
          snapshot,
          snapshot.segments[index],
          documentId: documentId,
          revision: revision,
        );
        final ordinary = await _service.check(
          request,
          only: useManual ? null : _filter(missing),
        );
        if (!current()) return null;
        final report = useManual
            ? mergeOfficeProofingReports(
                primary: ordinary,
                secondary: await manual!.check(request),
              )
            : reusable
            ? _mergeKinds(previous.reports[index], ordinary)
            : _carryOver(previous, snapshot, missing, ordinary) ?? ordinary;
        if (!current()) return null;
        paragraphReports.add(report);
      }
      final checkedKinds = useManual
          ? _Kind.values.toSet()
          : {...missing, if (reusable) ...previous.kinds};
      return _CachedParagraph(
        snapshot.key,
        paragraphReports,
        useManual,
        checkedKinds,
      );
    }

    // Keep both local workers busy when their checks have different costs.
    // Start with the priority paragraph and keep typing and custom providers
    // on their existing serial path.
    final batchSize =
        whole && !useManual && usesBackgroundWordProofing(_service) ? 4 : 1;
    var batch = const <_CachedParagraph?>[];
    var batchStart = 0;
    // About twenty progress publications per pass, plus early feedback for
    // the edited paragraph; each one republishes the whole document.
    final progressStride = (checkOrder.length + 19) ~/ 20;
    final slice = Stopwatch()..start();
    for (var position = 0; position < checkOrder.length; position++) {
      final snapshot = checkOrder[position];
      // Yield even when a provider Future completes synchronously, but only
      // once the slice budget is spent, so short work does not cost frames.
      if (position == 0 || slice.elapsed >= WordProofingTiming.sliceBudget) {
        await Future<void>.delayed(Duration.zero);
        slice
          ..reset()
          ..start();
      }
      if (!current()) return _summary;
      if (position - batchStart >= batch.length) {
        batchStart = position;
        final end = position + (position == 0 ? 1 : batchSize);
        batch = end == position + 1
            ? [await evaluate(snapshot)]
            : await Future.wait([
                for (
                  var next = position;
                  next < end && next < checkOrder.length;
                  next++
                )
                  evaluate(checkOrder[next]),
              ]);
      }
      if (!current()) return _summary;
      final checked = batch[position - batchStart];
      if (checked == null) continue;
      checkedParagraphCount++;
      _cache[snapshot.paragraph] = checked;
      if (checked.kinds.containsAll(allKinds)) {
        _touched.remove(snapshot.paragraph);
      }
      final remaining = position + 1 < checkOrder.length;
      if (showProgress &&
          remaining &&
          (position == 0 || (position + 1) % progressStride == 0)) {
        // Direct host edits can bypass the revision counter. Validate the
        // complete story/field/guard snapshot before exposing partial results.
        if (!captured.sameAs(_capture(document))) {
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
    // With no work there was no progress callback or async gap after the
    // current capture, so the settled summary can be published directly.
    if (hasWork && !captured.sameAs(_capture(document))) {
      refresh();
      return _summary;
    }
    // What the canvas paints for the checked text right now.
    final painted = showProgress
        ? null
        : [
            for (final snapshot in checkOrder)
              _paintFindingsFor(snapshot.paragraph),
          ];
    final hadResults = _pendingPublish != null || _published.hasResults;
    _publishCached(
      captured,
      documentId: documentId,
      revision: revision,
      useManual: useManual,
      finished: true,
    );
    // A check of the text being typed that changes no mark on screen does
    // not notify: listeners (and the host's whole chrome) would rebuild for
    // nothing. Readers still get the new summary; status has its own notifier.
    if (painted == null ||
        !hadResults ||
        !_sameMarks(painted, [
          for (final snapshot in checkOrder) _findings[snapshot.paragraph],
        ])) {
      notifyListeners();
    } else {
      silentPassCount++;
    }
    _finishAutomatic(trigger, captured, document);
    return _summary;
  }

  static bool _sameMarks(
    List<List<OfficeProofingFinding>?> before,
    List<List<OfficeProofingFinding>?> after,
  ) {
    for (var index = 0; index < before.length; index++) {
      final left = before[index] ?? const <OfficeProofingFinding>[];
      final right = after[index] ?? const <OfficeProofingFinding>[];
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        final a = left[i];
        final b = right[i];
        if (a.start != b.start ||
            a.end != b.end ||
            a.category != b.category ||
            a.ruleId != b.ruleId ||
            a.providerId != b.providerId ||
            a.originalText != b.originalText) {
          return false;
        }
      }
    }
    return true;
  }

  void _finishAutomatic(
    _Trigger trigger,
    _DocumentSnapshot captured,
    WmlDocument document,
  ) {
    _known = HashSet<WmlParagraph>.identity()
      ..addAll(captured.paragraphs.map((snapshot) => snapshot.paragraph));
    _knownDocument = document;
    if (trigger != _Trigger.explicit && trigger != _Trigger.background) {
      _armBackground(captured);
    }
  }

  /// While only some provider groups recheck an edited paragraph (spelling at
  /// word completion), the other groups' results for its previous text stay
  /// visible where that text is unchanged, so grammar marks do not vanish
  /// until the pause. They do not count as checked: the cache entry keeps
  /// only the groups that ran, and the pause pass replaces them.
  OfficeProofingReport? _carryOver(
    _CachedParagraph? previous,
    _ParagraphSnapshot snapshot,
    Set<_Kind> ran,
    OfficeProofingReport fresh,
  ) {
    if (previous == null ||
        previous.includesManual ||
        ran.containsAll(_available(_Kind.values.toSet())) ||
        previous.reports.length != 1 ||
        snapshot.segments.length != 1) {
      return null;
    }
    final old = previous.reports.single;
    final segment = snapshot.segments.single;
    if (old.request.startOffset != 0 ||
        segment.start != 0 ||
        old.request.language != segment.language) {
      return null;
    }
    final ranIds = {for (final result in fresh.results) result.providerId};
    final carried = [
      for (final result in old.results)
        if (!ranIds.contains(result.providerId) &&
            result.status == OfficeProofingStatus.success &&
            _service.providers.any(
              (provider) =>
                  provider.id == result.providerId &&
                  !ran.contains(_kindOf(provider)),
            ))
          OfficeProofingResult(
            request: fresh.request,
            providerId: result.providerId,
            status: result.status,
            message: result.message,
            findings: _remapFindings(
              result.findings,
              old.request.text,
              segment.text,
            ),
          ),
    ];
    if (carried.isEmpty) return null;
    return _mergeKinds(
      OfficeProofingReport(request: fresh.request, results: carried),
      fresh,
    );
  }

  /// [addition]'s provider results added to [base] for the same text, in
  /// the service's provider order (which decides merged-finding precedence).
  OfficeProofingReport _mergeKinds(
    OfficeProofingReport base,
    OfficeProofingReport addition,
  ) {
    final byId = <String, OfficeProofingResult>{
      for (final result in base.results) result.providerId: result,
      for (final result in addition.results) result.providerId: result,
    };
    final ordered = <OfficeProofingResult>[
      for (final provider in _service.providers) ?byId.remove(provider.id),
      ...byId.values,
    ];
    final request = addition.request;
    return OfficeProofingReport(
      request: request,
      results: [
        for (final result in ordered)
          identical(result.request, request)
              ? result
              : _retarget(
                  OfficeProofingReport(
                    request: result.request,
                    results: [result],
                  ),
                  request,
                ).results.single,
      ],
    );
  }

  /// A cached report that another pass cannot improve: every provider
  /// succeeded or declares that it does not support the text's language.
  /// Unavailable, failed or timed-out providers are retried, and so is an
  /// `unsupported` reply from a provider that claims the language. An
  /// unsupported-only paragraph (for example English text without an English
  /// checker) is then not rechecked on every pass; coverage still reports it
  /// as incomplete.
  bool _settled(OfficeProofingReport report) => report.results.every((result) {
    if (result.status == OfficeProofingStatus.success) return true;
    if (result.status != OfficeProofingStatus.unsupported) return false;
    for (final service in [_service, ?_manualService]) {
      for (final provider in service.providers) {
        if (provider.id != result.providerId) continue;
        try {
          return !provider.supportsLanguage(report.request.language);
        } on Object {
          return false;
        }
      }
    }
    return false;
  });

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
    _pendingPublish = null;
    _clearProvisionalFindings();
    final previous = HashMap<WmlParagraph, List<WordProofingIssue>>.identity();
    final previousByFinding =
        HashMap<OfficeProofingFinding, WordProofingIssue>.identity();
    for (final issue in _published.issues) {
      previous.putIfAbsent(issue.paragraph, () => []).add(issue);
      previousByFinding[issue.finding] = issue;
    }
    final findings =
        HashMap<WmlParagraph, List<OfficeProofingFinding>>.identity();
    final previousReports = HashSet<OfficeProofingReport>.identity()
      ..addAll(_published.reports);
    final reports = <OfficeProofingReport>[];
    final issues = <WordProofingIssue>[];
    var checked = 0;
    // Where the user is typing, a finding touching the caret is most likely
    // an unfinished word or sentence: keep it in the cache but do not flag
    // it until the word is completed or the caret moves away.
    final caret = _schedule.hideTypingErrors ? _typing : null;
    final allKinds = _available(_Kind.values.toSet());
    final hasIgnoredOccurrences = _ignoredOnce.isNotEmpty;
    _hidAtCaret = false;
    _findingTexts.clear();
    for (final snapshot in captured.paragraphs) {
      final cached = _cachedReports(
        snapshot,
        useManual: useManual,
        allowOrdinaryPreview: true,
      );
      if (cached == null) continue;
      final entry = _cache[snapshot.paragraph]!;
      if ((!useManual || entry.includesManual) &&
          cached.isNotEmpty &&
          cached.every((report) => report.complete) &&
          entry.kinds.containsAll(allKinds)) {
        checked++;
      }
      final paragraphFindings = <OfficeProofingFinding>[];
      for (var index = 0; index < snapshot.segments.length; index++) {
        final segment = snapshot.segments[index];
        final cachedReport = cached[index];
        final request = cachedReport.request;
        // Progress repeatedly publishes the same requests. A later document
        // revision still needs fresh request and finding coordinates.
        final report =
            request.documentId == documentId &&
                request.blockId == _ids[snapshot.paragraph] &&
                request.revision == revision &&
                request.text == segment.text &&
                request.startOffset == segment.start &&
                request.language ==
                    normalizeProofingLanguage(segment.language) &&
                setEquals(request.ignoredRuleIds, _ignoredRules)
            ? cachedReport
            : _retarget(
                cachedReport,
                _request(
                  snapshot,
                  segment,
                  documentId: documentId,
                  revision: revision,
                ),
              );
        reports.add(report);
        final previouslyPublished = previousReports.contains(report);
        for (final finding in report.findings) {
          // Inside or at the end of the finding (the word being typed);
          // a finding that starts at the caret is the next word.
          if (caret != null &&
              identical(caret.paragraph, snapshot.paragraph) &&
              finding.end >= caret.offset &&
              (finding.start < caret.offset || finding.start == finding.end)) {
            _hidAtCaret = true;
            continue;
          }
          if (hasIgnoredOccurrences &&
              _ignoredOnce.contains(_issueKey(finding, snapshot))) {
            continue;
          }
          if (finding.category == OfficeProofingCategory.spelling &&
              vocabulary.contains(
                finding.originalText,
                language: segment.language,
              )) {
            continue;
          }
          // Keep a current finding's identity when only progress changes, so
          // an open suggestion menu remains usable while other text is checked.
          var existing = previousByFinding[finding];
          if (existing?._snapshot.key != snapshot.key ||
              existing?.language != segment.language) {
            existing = null;
          }
          if (existing == null && !previouslyPublished) {
            final candidates = previous[snapshot.paragraph];
            if (candidates != null &&
                candidates.first.finding.revision == revision &&
                candidates.first._snapshot.key == snapshot.key) {
              existing = candidates
                  .where(
                    (issue) =>
                        issue.language == segment.language &&
                        _sameFinding(issue.finding, finding),
                  )
                  .firstOrNull;
            }
          }
          final issue =
              existing ??
              WordProofingIssue._(finding, snapshot, segment.language);
          issues.add(issue);
          paragraphFindings.add(issue.finding);
        }
      }
      if (paragraphFindings.isNotEmpty) {
        findings[snapshot.paragraph] = List.unmodifiable(paragraphFindings);
        _findingTexts[snapshot.paragraph] = snapshot.text;
      }
    }
    _findings = findings;
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
    final documentLanguage = normalizeProofingLanguage(
      document.proofingLanguage ?? 'de-DE',
    );
    final revisionsByParagraph =
        HashMap<WmlParagraph, List<WmlRevision>>.identity();
    final pendingRevisions = [
      for (final revision in document.revisions)
        if (revision.accepted == null && !revision.kind.isFormatting) revision,
    ];
    final targets = WordRevisions.resolveParagraphs(document, pendingRevisions);
    for (final revision in pendingRevisions) {
      if (targets[revision] case final paragraph?) {
        revisionsByParagraph.putIfAbsent(paragraph, () => []).add(revision);
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
        List<({int start, int end})>? pending;
        final exclusions = <({int start, int end})>[];
        for (final revision
            in revisionsByParagraph[paragraph] ?? const <WmlRevision>[]) {
          if (revision.start < 0 || revision.end > text.length) continue;
          final range = (start: revision.start, end: revision.end);
          (pending ??= []).add(range);
          if (revision.kind.isDeletion) exclusions.add(range);
        }
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
        final detection = _detectionForCapture(paragraph, text);
        var hasField = fieldDepth > 0;
        var hasInlineControl = false;
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
                    documentLanguage,
              ),
              run: inline,
              latin: detection == null
                  ? (language: null, isDefault: true)
                  : wordRunLanguageSlot(
                      inline,
                      paragraph,
                      complexScript: false,
                      documentLanguage: document.proofingLanguage,
                    ),
              complex: detection == null
                  ? (language: null, isDefault: true)
                  : wordRunLanguageSlot(
                      inline,
                      paragraph,
                      complexScript: true,
                      documentComplexScriptLanguage:
                          document.complexScriptLanguage,
                    ),
            ));
            offset = end;
          } else {
            if (inline is WmlContentControlBoundary) hasInlineControl = true;
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
        if (hasInlineControl) {
          try {
            for (final span in WordContentControls.spans(paragraph)) {
              if (_lockedControl(span.control)) {
                guards.add((start: span.start, end: span.end));
              }
            }
          } on Object {
            locked = true;
          }
        }
        guards.addAll(exclusions);
        // Existing insert revisions are not rewritten by a second command.
        if (pending != null) guards.addAll(pending);
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
        final uniformLanguage =
            languageRuns.firstOrNull?.language ?? documentLanguage;
        if (text.isNotEmpty &&
            detection == null &&
            exclusions.isEmpty &&
            !barriers.any((offset) => offset > 0 && offset < text.length) &&
            languageRuns.every((run) => run.language == uniformLanguage)) {
          ranges.add((start: 0, end: text.length, language: uniformLanguage));
        } else {
          // A language or noProof boundary inside a Unicode grapheme must never
          // give a provider half a surrogate pair, accent, or joined emoji.
          var nextStart = 0;
          for (final end in GraphemeClusters.endOffsets(text)) {
            final start = nextStart;
            nextStart = end;
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
                : documentLanguage;
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
              paragraph.properties.proofingLanguage ?? documentLanguage,
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
    _cancelAutomaticTimers();
    _checkingIndicatorTimer?.cancel();
    _pendingPublish = null;
    _touched.clear();
    _known = HashSet.identity();
    _pendingDraftCheck?.completer.complete();
    _pendingDraftCheck = null;
    _cache.clear();
    _findings.clear();
    _findingTexts.clear();
    _clearProvisionalFindings();
    _languageDetector = null;
    _detections.clear();
    _missingDetections.clear();
    _capturedTexts.clear();
    unawaited(_service.dispose());
    final manual = _manualService;
    if (manual != null) unawaited(manual.dispose());
    super.dispose();
    _status.dispose();
  }
}

typedef _ProofingOccurrence = ({
  String blockId,
  String snapshotKey,
  String providerId,
  String ruleId,
  int start,
  int end,
});

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

  /// [key] equality without encoding the whole document.
  bool sameAs(_DocumentSnapshot other) {
    if (skipped != other.skipped ||
        paragraphs.length != other.paragraphs.length) {
      return false;
    }
    for (var index = 0; index < paragraphs.length; index++) {
      final left = paragraphs[index];
      final right = other.paragraphs[index];
      if (!identical(left.paragraph, right.paragraph) ||
          left.key != right.key) {
        return false;
      }
    }
    return true;
  }
}

final class _CachedParagraph {
  const _CachedParagraph(
    this.key,
    this.reports,
    this.includesManual, [
    this.kinds = const {_Kind.spelling, _Kind.grammar},
  ]);
  final String key;
  final List<OfficeProofingReport> reports;
  final bool includesManual;

  /// The provider groups whose results [reports] contain.
  final Set<_Kind> kinds;
}
