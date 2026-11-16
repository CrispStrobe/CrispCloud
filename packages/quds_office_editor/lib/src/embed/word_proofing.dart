part of 'office_controller.dart';

/// One finding attached to its actual paragraph and source snapshot. Story
/// labels distinguish body text, notes, comments and header/footer variants.
class WordProofingIssue {
  WordProofingIssue._(this.finding, this._input, this.language);

  final OfficeProofingFinding finding;
  final _WordProofingInput _input;
  final String language;
  WmlParagraph get paragraph => _input.paragraph;
  String get story => _input.story;
  String get sourceText => _input.text;
}

/// All operational outcomes are retained; no checker, an unsupported locale,
/// or unmodeled content can be reported as a successfully clean document.
class WordProofingSummary {
  WordProofingSummary({
    required this.running,
    required this.hasChecked,
    required this.enabled,
    required this.paragraphCount,
    required this.checkedSegments,
    required this.skippedContentCount,
    required this.excludedSpanCount,
    required Iterable<WordProofingIssue> issues,
    required Iterable<OfficeProofingResult> results,
  }) : issues = List.unmodifiable(issues),
       results = List.unmodifiable(results);

  final bool running;
  final bool hasChecked;
  final bool enabled;
  final int paragraphCount;
  final int checkedSegments;

  /// Opaque blocks/inlines and preserved stories that cannot be interpreted.
  final int skippedContentCount;

  /// Intentionally excluded noProof text, field caches and tracked deletions.
  final int excludedSpanCount;
  final List<WordProofingIssue> issues;
  final List<OfficeProofingResult> results;

  bool get complete =>
      enabled &&
      hasChecked &&
      !running &&
      skippedContentCount == 0 &&
      results.isNotEmpty &&
      results.any((r) => r.status == OfficeProofingStatus.success) &&
      results.every(
        (r) =>
            r.status == OfficeProofingStatus.success ||
            r.status == OfficeProofingStatus.unsupported,
      ) &&
      // A successful German paragraph must not hide an unchecked English one.
      _allRequestsCovered;

  bool get _allRequestsCovered {
    final requests = <OfficeProofingRequest>{};
    final covered = <OfficeProofingRequest>{};
    for (final result in results) {
      requests.add(result.request);
      if (result.status == OfficeProofingStatus.success) {
        covered.add(result.request);
      }
    }
    return covered.length == requests.length;
  }

  bool get isClean => complete && issues.isEmpty;
}

/// A document-scoped session, with host-owned vocabulary and an explicit
/// lifecycle. German spelling/rules are the default providers. Text never leaves
/// the process unless a host explicitly supplies a different service.
class WordProofingSession extends ChangeNotifier {
  WordProofingSession._(
    this.controller, {
    OfficeProofingVocabulary? vocabulary,
    OfficeProofingService? service,
  }) : vocabulary = vocabulary ?? OfficeProofingVocabulary() {
    _service =
        service ??
        OfficeProofingService(
          providers: [
            GermanSpellingProvider(vocabulary: this.vocabulary),
            GermanWritingRulesProvider(),
          ],
        );
    _observedDocument = controller.document;
    _observedRevision = controller.contentRevision;
    _observedConfiguration = _configurationKey;
    controller.addListener(_controllerChanged);
  }

  final WordEditorController controller;
  final OfficeProofingVocabulary vocabulary;
  late OfficeProofingService _service;
  bool _ownsService = true;
  bool _disposed = false;
  bool _enabled = true;
  bool _manualStarted = false;
  int _attachedViews = 0;
  bool get _started => _manualStarted || _attachedViews > 0;
  bool _running = false;
  bool _hasChecked = false;
  int _generation = 0;
  int _nextBlock = 0;
  int _nextRevision = 0;
  int _observedRevision = 0;
  late WmlDocument _observedDocument;
  late String _observedConfiguration;
  int _paragraphCount = 0;
  int _checkedSegments = 0;
  int _skippedContentCount = 0;
  int _excludedSpanCount = 0;
  Timer? _timer;
  final _ids = Expando<String>('proofing paragraph identity');
  final Map<WmlParagraph, _WordProofingCache> _cache = Map.identity();
  final Set<String> _ignoredRules = {};
  final Set<String> _ignoredOnce = {};
  List<WordProofingIssue> _issues = const [];
  List<OfficeProofingResult> _results = const [];
  Map<WmlParagraph, List<WordProofingIssue>> _issueIndex = Map.identity();
  Map<WmlParagraph, List<OfficeProofingFinding>> _findingsIndex =
      Map.identity();

  /// Hosts persist this snapshot in their own storage. The engine never writes
  /// personal words into a document, bundled dictionary, or shared account.
  void Function(Map<String, Object?> snapshot)? onVocabularyChanged;
  Duration debounce = const Duration(milliseconds: 350);
  bool get enabled => _enabled;
  bool get running => _running;
  List<WordProofingIssue> get issues => _issues;
  List<OfficeProofingResult> get results => _results;
  Set<String> get ignoredRuleIds => Set.unmodifiable(_ignoredRules);
  Map<WmlParagraph, List<OfficeProofingFinding>> get findingsByParagraph =>
      _findingsIndex;
  String get _configurationKey =>
      '${_service.configurationKey}|v${vocabulary.revision}|${_ignoredRules.join(',')}';
  String get _documentId => 'word-${identityHashCode(controller.document)}';

  WordProofingSummary get summary => WordProofingSummary(
    running: _running,
    hasChecked: _hasChecked,
    enabled: _enabled,
    paragraphCount: _paragraphCount,
    checkedSegments: _checkedSegments,
    skippedContentCount: _skippedContentCount,
    excludedSpanCount: _excludedSpanCount,
    issues: _issues,
    results: _results,
  );

  void start() {
    if (_disposed || _manualStarted) return;
    final wasStarted = _started;
    _manualStarted = true;
    if (_enabled && !wasStarted) _schedule();
  }

  /// Stops background work explicitly started by the host. Attached surfaces
  /// keep their own independent ownership until [detachView].
  void stop() {
    if (_disposed) return;
    _manualStarted = false;
    _pauseIfUnobserved();
  }

  /// A surface acquires background work while mounted. Multiple surfaces may
  /// share one controller without stopping each other's checking.
  void attachView() {
    if (_disposed) return;
    final wasStarted = _started;
    _attachedViews++;
    if (_enabled && !wasStarted) _schedule();
  }

  void detachView() {
    if (_disposed || _attachedViews == 0) return;
    _attachedViews--;
    _pauseIfUnobserved();
  }

  void _pauseIfUnobserved() {
    if (_started) return;
    _timer?.cancel();
    _timer = null;
    if (_running) {
      _generation++;
      _running = false;
      notifyListeners();
    }
  }

  void setEnabled(bool enabled) {
    if (_disposed || _enabled == enabled) return;
    _enabled = enabled;
    invalidate();
  }

  /// A custom service's availability remains visible in [results]. Callers may
  /// retain lifecycle ownership explicitly when sharing a service across views.
  void configureService(
    OfficeProofingService service, {
    bool ownsService = true,
  }) {
    if (_disposed) return;
    if (identical(_service, service)) return;
    final previous = _service;
    final disposePrevious = _ownsService;
    _service = service;
    _ownsService = ownsService;
    if (disposePrevious) unawaited(previous.dispose());
    _cache.clear();
    invalidate();
  }

  void _controllerChanged() {
    if (_disposed) return;
    if (!identical(_observedDocument, controller.document) ||
        _observedRevision != controller.contentRevision ||
        _observedConfiguration != _configurationKey) {
      if (!identical(_observedDocument, controller.document)) {
        _cache.clear();
        _ignoredOnce.clear();
      }
      invalidate();
    }
  }

  /// Hosts mutating model objects directly call this after their mutation.
  /// Normal controller commands invalidate the session automatically.
  void invalidate() {
    if (_disposed) return;
    _generation++;
    _observedDocument = controller.document;
    _observedRevision = controller.contentRevision;
    _observedConfiguration = _configurationKey;
    _timer?.cancel();
    _running = false;
    _hasChecked = false;
    _issues = const [];
    _results = const [];
    _issueIndex = Map.identity();
    _findingsIndex = Map.identity();
    notifyListeners();
    if (_enabled && _started) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(checkDocument()));
  }

  Future<WordProofingSummary> checkDocument() async {
    if (_disposed || !_enabled) return summary;
    _timer?.cancel();
    final generation = ++_generation;
    final document = controller.document;
    final config = _configurationKey;
    final revision = controller.contentRevision;
    final collection = _collect();
    _running = true;
    _hasChecked = false;
    _issues = const [];
    _results = const [];
    _issueIndex = Map.identity();
    _findingsIndex = Map.identity();
    _paragraphCount = collection.inputs.length;
    _skippedContentCount = collection.skipped;
    _excludedSpanCount = collection.excluded;
    _checkedSegments = 0;
    notifyListeners();
    final nextIssues = <WordProofingIssue>[];
    final nextResults = <OfficeProofingResult>[];
    final nextCache = Map<WmlParagraph, _WordProofingCache>.identity();
    bool current() =>
        !_disposed &&
        generation == _generation &&
        identical(document, controller.document) &&
        config == _configurationKey &&
        revision == controller.contentRevision;

    for (final input in collection.inputs) {
      if (!current()) break;
      final previous = _cache[input.paragraph];
      final List<OfficeProofingReport> reports;
      if (previous != null &&
          previous.input.key == input.key &&
          previous.configuration == config) {
        reports = previous.reports;
      } else {
        reports = [];
        final blockId = _ids[input.paragraph] ??= 'paragraph-${_nextBlock++}';
        final blockRevision = ++_nextRevision;
        for (final segment in input.segments) {
          reports.add(
            await _service.check(
              OfficeProofingRequest(
                documentId: _documentId,
                blockId: blockId,
                revision: blockRevision,
                text: segment.text,
                startOffset: segment.start,
                language: segment.language,
                ignoredRuleIds: _ignoredRules,
              ),
            ),
          );
          if (!current()) break;
          // Cooperatively yield even for a synchronous/custom provider.
          await Future<void>.delayed(Duration.zero);
        }
      }
      if (!current()) break;
      nextCache[input.paragraph] = _WordProofingCache(input, config, reports);
      for (final report in reports) {
        _checkedSegments++;
        nextResults.addAll(report.results);
        for (final finding in report.findings) {
          final issue = WordProofingIssue._(
            finding,
            input,
            report.request.language,
          );
          if (!_ignoredOnce.contains(_issueKey(issue))) nextIssues.add(issue);
        }
      }
    }
    if (!current()) {
      if (!_disposed && generation == _generation) invalidate();
      return summary;
    }
    // Direct host mutations need not have advanced contentRevision. Compare
    // complete source signatures before publishing any asynchronous result.
    final latest = _collect();
    if (!_sameInputs(collection.inputs, latest.inputs) ||
        collection.skipped != latest.skipped ||
        collection.excluded != latest.excluded) {
      invalidate();
      return summary;
    }
    _cache
      ..clear()
      ..addAll(nextCache);
    _issues = List.unmodifiable(nextIssues);
    _results = List.unmodifiable(nextResults);
    _issueIndex = Map.identity();
    _findingsIndex = Map.identity();
    for (final issue in _issues) {
      _issueIndex.putIfAbsent(issue.paragraph, () => []).add(issue);
      _findingsIndex.putIfAbsent(issue.paragraph, () => []).add(issue.finding);
    }
    for (final p in _issueIndex.keys) {
      _issueIndex[p] = List.unmodifiable(_issueIndex[p]!);
      _findingsIndex[p] = List.unmodifiable(_findingsIndex[p]!);
    }
    _findingsIndex = Map.unmodifiable(_findingsIndex);
    _running = false;
    _hasChecked = true;
    _observedDocument = document;
    _observedRevision = revision;
    _observedConfiguration = config;
    notifyListeners();
    return summary;
  }

  static bool _sameInputs(
    List<_WordProofingInput> a,
    List<_WordProofingInput> b,
  ) =>
      a.length == b.length &&
      a.indexed.every(
        (e) =>
            identical(e.$2.paragraph, b[e.$1].paragraph) &&
            e.$2.key == b[e.$1].key,
      );

  List<WordProofingIssue> issuesForParagraph(WmlParagraph paragraph) =>
      _issueIndex[paragraph] ?? const [];

  List<WordProofingIssue> issuesAt(WmlParagraph paragraph, int offset) =>
      issuesForParagraph(paragraph)
          .where(
            (issue) => issue.finding.start == issue.finding.end
                ? offset == issue.finding.start
                : issue.finding.start <= offset && offset < issue.finding.end,
          )
          .toList(growable: false);

  bool _publishedCurrent(WordProofingIssue issue) =>
      !_disposed &&
      _enabled &&
      (_issueIndex[issue.paragraph]?.contains(issue) ?? false) &&
      _observedConfiguration == _configurationKey &&
      _observedRevision == controller.contentRevision &&
      identical(_observedDocument, controller.document) &&
      issue.paragraph.text == issue.sourceText;

  /// Display-only snapshot check; actions use [isCurrent] to also re-read story
  /// ownership, language spans, complex fields and inherited content locks.
  bool isCurrentForDisplay(WordProofingIssue issue) => _publishedCurrent(issue);

  bool isCurrent(WordProofingIssue issue) {
    if (!_publishedCurrent(issue)) return false;
    final input = _collect().inputs
        .where((p) => identical(p.paragraph, issue.paragraph))
        .firstOrNull;
    return input != null && input.key == issue._input.key;
  }

  bool canApply(WordProofingIssue issue) =>
      _canApply(issue, validateSource: true);

  /// Cheap eligibility for a visible result row. Direct host model mutations
  /// must call [invalidate]. [applySuggestion] always verifies the complete live
  /// document again, so an obsolete enabled button cannot authorize an edit.
  bool canApplyForDisplay(WordProofingIssue issue) =>
      _canApply(issue, validateSource: false);

  bool _canApply(WordProofingIssue issue, {required bool validateSource}) {
    if (!controller.config.allowsMutation ||
        (controller.document.restrictEditing &&
            (controller.document.restrictMode != WmlRestrictMode.none ||
                controller.document.protectionFormattingRestricted)) ||
        !(validateSource ? isCurrent(issue) : _publishedCurrent(issue)) ||
        (controller.input.composing.isValid &&
            !controller.input.composing.isCollapsed)) {
      return false;
    }
    final f = issue.finding;
    if (issue._input.locked ||
        f.start < 0 ||
        f.end > issue.paragraph.text.length) {
      return false;
    }
    try {
      final range = WmlRunEdit.normalizeRange(issue.paragraph, f.start, f.end);
      if (range.start != f.start || range.end != f.end) return false;
      WordContentControls.assertCanEdit(issue.paragraph, f.start, f.end);
      for (final span in WordContentControls.spans(issue.paragraph)) {
        final touchesControl = f.start == f.end
            ? f.start >= span.start &&
                  (f.start < span.end || span.start == span.end)
            : _touches(f.start, f.end, span.start, span.end);
        if (touchesControl && _contentLocked(span.control)) {
          return false;
        }
      }
      for (final revision in controller.document.revisions) {
        if (revision.accepted == null &&
            identical(
              WordRevisions.resolveParagraph(controller.document, revision),
              issue.paragraph,
            ) &&
            _touches(f.start, f.end, revision.start, revision.end)) {
          return false;
        }
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// Applies one offered correction to its exact source paragraph, in one undo
  /// step. Tracking records deletion before insertion without losing old text.
  bool applySuggestion(WordProofingIssue issue, String replacement) {
    if (!issue.finding.replacements.contains(replacement) ||
        replacement.contains('\n') ||
        replacement.contains('\r') ||
        !canApply(issue)) {
      return false;
    }
    controller.commitPendingEdits();
    if (!canApply(issue)) return false;
    final paragraph = issue.paragraph;
    final f = issue.finding;
    final document = controller.document;
    final activeParagraphs = controller._paragraphs;
    final activeCaret = controller.caret;
    final activeAffected =
        activeCaret.paragraphIndex >= 0 &&
        activeCaret.paragraphIndex < activeParagraphs.length &&
        identical(activeParagraphs[activeCaret.paragraphIndex], paragraph);
    final beforeCaret = (
      paragraph: activeCaret.paragraphIndex,
      offset: activeCaret.logicalIndex,
      anchorParagraph: activeCaret.selectionAnchorParagraph,
      anchor: activeCaret.selectionAnchor,
    );
    final previousActiveText = activeAffected ? paragraph.text : null;
    final correctionEnd =
        (document.trackRevisions ? f.end : f.start) + replacement.length;
    void correctedCaret() {
      if (!activeAffected) return;
      activeCaret
        ..paragraphIndex = beforeCaret.paragraph
        ..logicalIndex = correctionEnd
        ..collapseSelection();
    }

    void originalCaret() {
      if (!activeAffected) return;
      activeCaret
        ..paragraphIndex = beforeCaret.paragraph
        ..logicalIndex = beforeCaret.offset
        ..selectionAnchorParagraph = beforeCaret.anchorParagraph
        ..selectionAnchor = beforeCaret.anchor;
      if (identical(controller.caret, activeCaret)) {
        controller._historyRestoredSelection = true;
      }
    }

    final before = WordEditorController._cloneInlines(paragraph);
    final revisionsBefore = WordRevisions.capture(document);
    List<WmlInline>? after;
    WmlRevisionSnapshot? revisionsAfter;
    void restore(List<WmlInline> inlines, WmlRevisionSnapshot revisions) {
      paragraph.inlines
        ..clear()
        ..addAll(WordEditorController._cloneInlinesFrom(inlines));
      revisions.restore(document);
    }

    // Preflight protects command history against an unsupported atomic edit.
    final preview = WmlClone.paragraph(paragraph);
    WmlRunEdit.replaceRange(preview, f.start, f.end, replacement);
    controller.commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (after != null) {
            restore(after!, revisionsAfter!);
            correctedCaret();
            return;
          }
          if (document.trackRevisions) {
            final index = document.paragraphs.toList().indexOf(paragraph);
            if (f.end > f.start) {
              WordRevisions.record(
                document,
                kind: WmlRevisionKind.delete,
                paragraph: paragraph,
                paragraphIndex: index < 0 ? 0 : index,
                start: f.start,
                end: f.end,
                text: f.originalText,
              );
            }
            if (replacement.isNotEmpty) {
              WordRevisions.rebaseEdit(
                document,
                paragraph,
                start: f.end,
                end: f.end,
                insertedLength: replacement.length,
              );
              WmlRunEdit.replaceRange(paragraph, f.end, f.end, replacement);
              WordRevisions.record(
                document,
                kind: WmlRevisionKind.insert,
                paragraph: paragraph,
                paragraphIndex: index < 0 ? 0 : index,
                start: f.end,
                end: f.end + replacement.length,
                text: replacement,
              );
            }
          } else {
            WordRevisions.rebaseEdit(
              document,
              paragraph,
              start: f.start,
              end: f.end,
              insertedLength: replacement.length,
            );
            WmlRunEdit.replaceRange(paragraph, f.start, f.end, replacement);
          }
          after = WordEditorController._cloneInlines(paragraph);
          revisionsAfter = WordRevisions.capture(document);
          correctedCaret();
        },
        undoFn: () {
          restore(before, revisionsBefore);
          originalCaret();
        },
      ),
    );
    controller.relayout();
    if (previousActiveText != null) {
      controller._markLocalEdit(previousText: previousActiveText);
    }
    controller._syncImeSelection();
    controller.notifyListeners();
    return true;
  }

  /// Reveals paragraphs supported by the current canvas. Notes and first/even
  /// header variants remain reviewable/correctable in the results dialog.
  bool canSelectIssue(WordProofingIssue issue) =>
      _publishedCurrent(issue) &&
      (issue.story == 'Body' || issue.story.startsWith('Comment '));

  bool selectIssue(WordProofingIssue issue) {
    if (!canSelectIssue(issue) ||
        !isCurrent(issue) ||
        !controller.config.allowsSelection) {
      return false;
    }
    final body = controller.document.paragraphs.toList();
    final index = body.indexOf(issue.paragraph);
    CaretEngine caret;
    int paragraphIndex;
    if (index >= 0) {
      controller.endCommentEdit();
      controller.endHeaderFooterEdit();
      controller.jumpToParagraph(index);
      caret = controller.documentCaret;
      paragraphIndex = index;
    } else {
      final comment = controller.document.comments
          .where((c) => c.paragraphs.contains(issue.paragraph))
          .firstOrNull;
      if (comment == null) return false;
      controller.beginCommentEdit(comment.id);
      caret = controller.commentCaret;
      paragraphIndex = comment.paragraphs.indexOf(issue.paragraph);
    }
    caret
      ..paragraphIndex = paragraphIndex
      ..selectionAnchorParagraph = paragraphIndex
      ..selectionAnchor = issue.finding.start
      ..logicalIndex = issue.finding.end;
    controller.notifyListeners();
    return true;
  }

  String _issueKey(WordProofingIssue issue) => jsonEncode([
    _ids[issue.paragraph],
    issue._input.key,
    issue.finding.providerId,
    issue.finding.ruleId,
    issue.finding.start,
    issue.finding.end,
  ]);

  void ignoreOnce(WordProofingIssue issue) {
    if (!isCurrent(issue)) return;
    _ignoredOnce.add(_issueKey(issue));
    invalidate();
    unawaited(checkDocument());
  }

  void ignoreWord(WordProofingIssue issue) {
    if (!isCurrent(issue) ||
        issue.finding.category != OfficeProofingCategory.spelling) {
      return;
    }
    vocabulary.ignoreWord(issue.finding.originalText, language: issue.language);
    _vocabularyChanged();
  }

  void addWord(WordProofingIssue issue) {
    if (!isCurrent(issue) ||
        issue.finding.category != OfficeProofingCategory.spelling) {
      return;
    }
    vocabulary.addWord(issue.finding.originalText, language: issue.language);
    _vocabularyChanged();
  }

  void _vocabularyChanged() {
    invalidate();
    onVocabularyChanged?.call(vocabulary.toJson());
    unawaited(checkDocument());
  }

  void ignoreRule(String ruleId) {
    if (_ignoredRules.add(ruleId)) {
      invalidate();
      unawaited(checkDocument());
    }
  }

  /// Restores the current owner's vocabulary without changing provider object
  /// references. Other owners' snapshots must be supplied at construction.
  void restoreVocabulary(Map<String, Object?> snapshot) {
    final restored = OfficeProofingVocabulary.fromJson(snapshot);
    if (restored.ownerId != vocabulary.ownerId) {
      throw ArgumentError('The vocabulary belongs to a different owner.');
    }
    final old = vocabulary.toJson();
    for (final language in (old['words']! as Map<String, Object?>).keys) {
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
    _vocabularyChanged();
  }

  static bool _touches(int from, int to, int start, int end) =>
      from == to ? from > start && from < end : from < end && to > start;

  static bool _contentLocked(WmlContentControlData control) {
    try {
      final properties = WordContentControls.template(
        control,
      ).firstChild('sdtPr', namespaceUri: OfficeNamespaces.w);
      final lock = properties
          ?.firstChild('lock', namespaceUri: OfficeNamespaces.w)
          ?.getAttribute('val', namespaceUri: OfficeNamespaces.w);
      return lock == 'contentLocked' ||
          lock == 'sdtContentLocked' ||
          properties?.firstChild(
                'dataBinding',
                namespaceUri: OfficeNamespaces.w,
              ) !=
              null;
    } on Object {
      return true;
    }
  }

  _WordProofingCollection _collect() {
    final document = controller.document;
    final result = _WordProofingCollection();
    final deleted = Map<WmlParagraph, List<({int start, int end})>>.identity();
    for (final revision in document.revisions) {
      if (revision.accepted != null ||
          revision.kind != WmlRevisionKind.delete) {
        continue;
      }
      final p = WordRevisions.resolveParagraph(document, revision);
      if (p != null) {
        deleted.putIfAbsent(p, () => []).add((
          start: revision.start,
          end: revision.end,
        ));
      }
    }
    final seen = Set<WmlParagraph>.identity();
    void story(Iterable<WmlBlock> blocks, String label) {
      var fieldDepth = 0;
      void walk(Iterable<WmlBlock> items, bool locked) {
        for (final block in items) {
          if (block is WmlOpaqueBlock) {
            result.skipped++;
            continue;
          }
          if (block is WmlToc) {
            result.excluded++;
            continue;
          }
          if (block is WmlParagraph) {
            if (!seen.add(block)) continue;
            final text = block.text;
            final segments = <_WordProofingSegment>[];
            final shape = <Object?>[
              label,
              text,
              locked,
              block.properties.proofingLanguage,
              document.proofingLanguage,
              block.properties.fieldInstruction,
              for (final control in block.contentControlWrappers) control.xml,
            ];
            final lockedParagraph =
                locked || block.contentControlWrappers.any(_contentLocked);
            var offset = 0;
            var canJoin = false;
            for (final inline in block.inlines) {
              if (inline is WmlFieldBoundary) {
                shape.addAll(['field', inline.kind.name, inline.text]);
                if (inline.kind == WmlFieldBoundaryKind.begin) fieldDepth++;
                if (inline.kind == WmlFieldBoundaryKind.end && fieldDepth > 0) {
                  fieldDepth--;
                }
                canJoin = false;
              } else if (inline is WmlRun) {
                final language = normalizeProofingLanguage(
                  inline.properties.proofingLanguage ??
                      block.properties.proofingLanguage ??
                      controller.proofingLanguage,
                );
                final skip =
                    fieldDepth > 0 ||
                    block.properties.fieldInstruction != null ||
                    inline.isAtomic ||
                    inline.properties.noProof == true;
                shape.addAll([
                  'run',
                  inline.text,
                  language,
                  inline.properties.noProof,
                  inline.fieldInstruction,
                  inline.noteRefId,
                  inline.inlineVisual != null,
                  fieldDepth,
                ]);
                final end = offset + inline.text.length;
                if (skip) {
                  result.excluded++;
                  canJoin = false;
                } else {
                  final cuts = <int>{offset, end};
                  for (final span
                      in deleted[block] ?? <({int start, int end})>[]) {
                    if (span.start < end && span.end > offset) {
                      cuts.add(span.start.clamp(offset, end));
                      cuts.add(span.end.clamp(offset, end));
                    }
                  }
                  final points = cuts.toList()..sort();
                  for (var i = 0; i + 1 < points.length; i++) {
                    final start = points[i];
                    final stop = points[i + 1];
                    final removed =
                        (deleted[block] ?? <({int start, int end})>[]).any(
                          (span) => start < span.end && stop > span.start,
                        );
                    if (removed) {
                      result.excluded++;
                      canJoin = false;
                      continue;
                    }
                    final part = text.substring(start, stop);
                    if (canJoin &&
                        segments.isNotEmpty &&
                        segments.last.language == language &&
                        segments.last.start + segments.last.text.length ==
                            start) {
                      final last = segments.removeLast();
                      segments.add(
                        _WordProofingSegment(
                          last.start,
                          last.text + part,
                          language,
                        ),
                      );
                    } else {
                      segments.add(_WordProofingSegment(start, part, language));
                    }
                    canJoin = true;
                  }
                }
                offset = end;
              } else {
                canJoin = false;
                if (inline is WmlOpaqueInline) result.skipped++;
                if (inline is WmlContentControlBoundary) {
                  shape.addAll(['control', inline.start, inline.control.xml]);
                } else {
                  shape.add(inline.runtimeType.toString());
                }
              }
            }
            if (text.isEmpty &&
                block.properties.fieldInstruction == null &&
                fieldDepth == 0) {
              segments.add(
                _WordProofingSegment(
                  0,
                  '',
                  normalizeProofingLanguage(
                    block.properties.proofingLanguage ??
                        controller.proofingLanguage,
                  ),
                ),
              );
            }
            shape.add([
              for (final span in deleted[block] ?? <({int start, int end})>[])
                [span.start, span.end],
            ]);
            result.inputs.add(
              _WordProofingInput(
                block,
                label,
                text,
                jsonEncode(shape),
                segments,
                lockedParagraph,
              ),
            );
          } else {
            final nextLocked =
                locked ||
                block is WmlContentControlBlock &&
                    _contentLocked(block.control);
            for (final children in WordTree.childLists(block)) {
              walk(children, nextLocked);
            }
          }
        }
      }

      walk(blocks, false);
    }

    story(document.sections.expand((s) => s.blocks), 'Body');
    for (final (index, section) in document.sections.indexed) {
      for (final entry in <String, List<WmlParagraph>>{
        'Header': section.header,
        'Footer': section.footer,
        'First-page header': section.firstHeader,
        'First-page footer': section.firstFooter,
        'Even-page header': section.evenHeader,
        'Even-page footer': section.evenFooter,
      }.entries) {
        story(entry.value, '${entry.key} · section ${index + 1}');
      }
      result.skipped += section.preservedStories.length;
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      story(note.blocks, '${note.endnote ? 'Endnote' : 'Footnote'} ${note.id}');
    }
    for (final comment in document.comments) {
      story(comment.paragraphs, 'Comment ${comment.id}');
    }
    return result;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    controller.removeListener(_controllerChanged);
    if (_ownsService) unawaited(_service.dispose());
    _cache.clear();
    super.dispose();
  }
}

class _WordProofingInput {
  const _WordProofingInput(
    this.paragraph,
    this.story,
    this.text,
    this.key,
    this.segments,
    this.locked,
  );
  final WmlParagraph paragraph;
  final String story;
  final String text;
  final String key;
  final List<_WordProofingSegment> segments;
  final bool locked;
}

class _WordProofingSegment {
  const _WordProofingSegment(this.start, this.text, this.language);
  final int start;
  final String text;
  final String language;
}

class _WordProofingCollection {
  final List<_WordProofingInput> inputs = [];
  int skipped = 0;
  int excluded = 0;
}

class _WordProofingCache {
  const _WordProofingCache(this.input, this.configuration, this.reports);
  final _WordProofingInput input;
  final String configuration;
  final List<OfficeProofingReport> reports;
}
