import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show Intl;
import 'package:quds_office_engine/quds_office_engine.dart';

import '../core/command_pipeline.dart';
import '../core/input_bridge.dart';
import '../core/virtual_viewport.dart';
import '../editor_sheet/inline_cell_editor.dart';
import '../editor_sheet/selection_matrix.dart';
import '../editor_sheet/sheet_font_metrics.dart';
import '../editor_sheet/sheet_scroll_extent.dart';
import '../editor_word/caret_engine.dart';
import '../editor_word/office_ruler.dart';
import '../editor_word/paint_run_text.dart';
import '../editor_word/proofing_geometry.dart';
import '../editor_word/table_history.dart';
import '../editor_word/word_run_metrics.dart';
import '../proofing/word_proofing.dart';
import 'office_clipboard.dart';
import 'office_host_fonts.dart';
import 'office_theme.dart';
import 'word_autocorrect.dart';
import 'word_page_layout.dart';

/// The persistent review workspace shown beside (or below) a Word document.
enum WordReviewPaneTab { proofing, changes }

/// The page variant of the header or footer currently being edited.
enum WordHeaderFooterVariant { standard, firstPage, evenPage }

/// Selection in a Notes pane, measured in [WordNotes.editableText] offsets.
/// The automatic note marker and its hidden separator are not editable text.
typedef WordNoteEditingTarget = ({
  WmlNote note,
  TextSelection selection,
  TextRange composing,
});

/// An immutable view of the selected text, or the whole current paragraph.
///
/// Keep this handle with a displayed control and supply it when applying an
/// option. The controller refuses a handle whose document, caret, source or
/// proofing settings have changed, including model edits made by a host.
@immutable
final class WordTextProofingTarget {
  const WordTextProofingTarget._(
    this._context,
    this._ranges, {
    required this.isSelection,
    required this.language,
    required this.checkingEnabled,
    required this.unavailableReason,
    this.scriptLanguages = const {},
    this.detectedLanguages = const {},
    this.detectionPending = false,
  });

  final bool isSelection;

  /// Effective language, or null when the target contains several languages.
  final String? language;

  /// The Word language of the target's text per script, in text order:
  /// `w:lang/@w:val` for Latin (and other non-complex) scripts,
  /// `w:lang/@w:bidi` for Arabic and Hebrew. A null value means the text of
  /// that script has several languages.
  final Map<TextScript, String?> scriptLanguages;

  /// Languages automatic detection found per script (null: several). Empty
  /// when detection is off, has not run yet ([detectionPending]) or found
  /// nothing certain.
  final Map<TextScript, String?> detectedLanguages;

  /// Detection is configured but has not run for this text yet; hosts may
  /// call [WordEditorController.detectTextProofingLanguages].
  final bool detectionPending;

  /// Whether "Apply detected language" would change a script's language.
  bool get canApplyDetectedLanguages =>
      canEdit &&
      detectedLanguages.entries.any((entry) {
        final detected = entry.value;
        if (detected == null) return true;
        final current = scriptLanguages[entry.key];
        return current == null ||
            primaryLanguageSubtag(current) != primaryLanguageSubtag(detected);
      });

  /// Whether this text permits proofing; null denotes a mixed selection.
  /// This is independent of the session's Check as you type preference.
  final bool? checkingEnabled;
  final String? unavailableReason;
  bool get canEdit => unavailableReason == null;

  final Object _context;
  final List<_WordTextProofingRange> _ranges;

  bool _matches(WordTextProofingTarget other) =>
      _context == other._context &&
      _ranges.length == other._ranges.length &&
      _ranges.indexed.every((entry) {
        final before = entry.$2;
        final after = other._ranges[entry.$1];
        return identical(before.paragraph, after.paragraph) &&
            before.start == after.start &&
            before.end == after.end &&
            before.source == after.source &&
            listEquals(before.inlines, after.inlines);
      });
}

final class _WordTextProofingRange {
  _WordTextProofingRange({
    required this.paragraph,
    required this.start,
    required this.end,
    required this.source,
  }) : inlines = List.unmodifiable(paragraph.inlines);

  final WmlParagraph paragraph;
  final int start;
  final int end;
  final String source;
  final List<WmlInline> inlines;
}

typedef _WordTextProofingParagraph = ({
  WmlParagraph paragraph,
  List<WmlContentControlData> controls,
  List<Object?> styleContext,
  bool generated,
});

/// Why the explicit thesaurus action could not capture an editable source.
enum WordThesaurusTargetStatus {
  ready,
  noText,
  multipleParagraphs,
  mixedLanguage,
  protectedContent,
  composing,
  unsupportedTarget,
  invalidRange,
}

final class WordThesaurusCapture {
  const WordThesaurusCapture._(this.status, {this.target, this.message});

  final WordThesaurusTargetStatus status;
  final WordThesaurusTarget? target;
  final String? message;
  bool get isReady => target != null;
}

/// Immutable source selection. Only [WordEditorController] can capture one;
/// it is independent of the spelling/grammar finding membership contract.
final class WordThesaurusTarget {
  WordThesaurusTarget._(
    this._owner,
    this._source,
    this._caret,
    this._selection,
    this._trackRevisions,
  );

  final WordEditorController _owner;
  final WordTextRangeTarget _source;
  final CaretEngine _caret;
  final ({
    WmlParagraph? paragraph,
    int offset,
    int? anchor,
    int? anchorParagraph,
  })
  _selection;
  final bool _trackRevisions;
  String get text => _source.text;
  String get language => _source.language;
  String get story => _source.story;
  int get start => _source.start;
  int get end => _source.end;
}

/// A returned provider result bound to one captured source and pack revision.
/// A literal candidate from this exact result is required for replacement.
final class WordThesaurusLookup {
  WordThesaurusLookup._(
    this.target,
    this.result,
    this.language,
    this._service,
    this._serviceRevision,
    this._generation,
  );

  final WordThesaurusTarget target;
  final OfficeThesaurusResult result;
  final String language;
  final OfficeThesaurusService _service;
  final int _serviceRevision;
  final int _generation;
}

/// Live find/replace cursor shared by every host.
class OfficeFindSession {
  /// OfficeFindSession API.
  OfficeFindSession();

  /// hits API.
  List<OfficeFindHit> hits = <OfficeFindHit>[];

  /// index API.
  var index = -1;

  /// options API.
  OfficeFindOptions? options;

  /// active API.
  var active = false;

  /// current API.
  OfficeFindHit? get current =>
      index >= 0 && index < hits.length ? hits[index] : null;

  /// clear API.
  void clear() {
    hits = <OfficeFindHit>[];
    index = -1;
    options = null;
    active = false;
  }
}

/// Shared undo, dirty-state, and interaction mode for every embedded editor.
abstract class OfficeController extends ChangeNotifier {
  /// OfficeController API.
  OfficeController({OfficeSurfaceConfig? config})
    : _config = config ?? const OfficeSurfaceConfig() {
    commands.addListener(_onCommands);
  }

  /// commands API.
  final CommandPipeline commands = CommandPipeline();

  /// viewport API.
  final VirtualViewport viewport = VirtualViewport();

  /// findSession API.
  final OfficeFindSession findSession = OfficeFindSession();

  /// Host chrome: Ctrl+F.
  VoidCallback? onFindRequested;

  /// Host chrome: Ctrl+H.
  VoidCallback? onReplaceRequested;

  /// Host chrome: Ctrl+P.
  VoidCallback? onPrintRequested;

  /// Host chrome: F7.
  VoidCallback? onSpellCheckRequested;

  /// Gives a host's configured shortcuts priority over the surface defaults.
  /// Return true after dispatching a command or retiring a default binding.
  /// Only focused document surfaces call this hook; native text fields keep
  /// their own editing actions. Null preserves standalone editor shortcuts.
  bool Function(KeyEvent event)? onShortcutKeyEvent;

  /// Fired after [find] / [findNext] updates [findSession].
  void Function(OfficeFindHit? hit)? onFindResult;

  OfficeSurfaceConfig _config;
  var _dirty = false;
  var _disposed = false;
  var _contentRevision = 0;

  /// config API.
  OfficeSurfaceConfig get config => _config;

  /// mode API.
  OfficeInteractionMode get mode => _config.mode;

  /// theme API.
  OfficeTheme get theme => _config.theme;

  /// isDirty API.
  bool get isDirty => _dirty || _hasPendingEdits;

  /// Allows asynchronous host workflows to reject a closed editor safely.
  bool get isDisposed => _disposed;

  // Drafts contribute to dirty state without replacing the state of unrelated
  // committed commands. Discarding a draft therefore cannot clear those edits.
  bool get _hasPendingEdits => false;

  /// Monotonic revision for controller-observed document changes. Hosts can
  /// capture this after committing pending edits and compare it after an
  /// asynchronous save. Caret, viewport and layout notifications do not advance
  /// it; changed note, cell and slide text drafts do, before their undo command
  /// is committed. Discarding a changed draft advances it as well.
  int get contentRevision => _contentRevision;

  /// canUndo API.
  bool get canUndo => commands.canUndo;

  /// canRedo API.
  bool get canRedo => commands.canRedo;

  /// kind API.
  OpcPackageKind get kind;

  /// config API.
  set config(OfficeSurfaceConfig value) {
    if (identical(_config, value)) {
      return;
    }
    _config = value;
    notifyListeners();
  }

  /// Assigns [value] without notifying listeners (safe during widget build).
  void syncConfig(OfficeSurfaceConfig value) {
    final bool directionChanged = _config.textDirection != value.textDirection;
    _config = value;
    if (directionChanged) {
      onSurfaceDirectionChanged();
    }
  }

  /// Hook when [OfficeSurfaceConfig.textDirection] changes (e.g. studio language).
  void onSurfaceDirectionChanged() {}

  /// setMode API.
  void setMode(OfficeInteractionMode mode) {
    _config = _config.copyWith(mode: mode);
    if (!config.allowsMutation) {
      detachInput();
    }
    notifyListeners();
  }

  /// markClean API.
  void markClean() {
    _dirty = false;
    notifyListeners();
  }

  /// Hosts and surfaces call this after pointer-driven state changes.
  void refresh() {
    notifyListeners();
  }

  /// undo API.
  void undo() {
    if (!config.enableUndo || !config.allowsMutation || !commands.canUndo) {
      return;
    }
    beforeHistoryChange();
    commands.undo();
    afterHistoryChange();
  }

  /// redo API.
  void redo() {
    if (!config.enableUndo || !config.allowsMutation || !commands.canRedo) {
      return;
    }
    beforeHistoryChange();
    commands.redo();
    afterHistoryChange();
  }

  /// Snapshot state that IME must not echo back after undo/redo.
  void beforeHistoryChange() {}

  /// Relayout / refresh after undo/redo.
  void afterHistoryChange() {}

  /// Applies active editor drafts and records their undo commands.
  ///
  /// Hosts should call this before capturing [contentRevision] for a save.
  /// [isDirty] already includes changed drafts, so a close prompt can inspect it
  /// without committing. Both byte-saving APIs also commit drafts.
  void commitPendingEdits() {}

  /// saveBytes API.
  Uint8List saveBytes({String? password});

  /// Encodes the package, using a worker isolate when the file is large.
  ///
  /// Unlike [saveBytes], this does not mark the controller clean — the host
  /// should call [markClean] after the bytes are written to disk.
  Future<Uint8List> saveBytesAsync({String? password}) async {
    commitPendingEdits();
    return saveBytes(password: password);
  }

  /// detachInput API.
  void detachInput();

  /// canCopy API.
  bool get canCopy => false;

  /// canCut API.
  bool get canCut => canCopy && config.allowsMutation;

  /// canPaste API.
  bool get canPaste => config.allowsMutation;

  /// selectAll API.
  void selectAll() {}

  /// copyToClipboard API.
  Future<void> copyToClipboard() async {}

  /// cutToClipboard API.
  Future<void> cutToClipboard() async {
    await copyToClipboard();
  }

  /// pasteFromClipboard API.
  Future<void> pasteFromClipboard({
    OfficePasteMode mode = OfficePasteMode.keepSource,
  }) async {}

  /// semanticsLabel API.
  String get semanticsLabel;

  /// semanticsValue API.
  String get semanticsValue;

  /// canFind API.
  bool get canFind => true;

  /// canPrint API.
  bool get canPrint => true;

  /// hasTrackedChanges API.
  bool get hasTrackedChanges => false;

  /// documentProperties API.
  OfficeDocumentProperties get documentProperties;

  /// documentProperties API.
  set documentProperties(OfficeDocumentProperties value);

  /// documentStats API.
  OfficeTextStats get documentStats;

  /// selectionStats API.
  OfficeTextStats get selectionStats => documentStats;

  /// collectFindHits API.
  List<OfficeFindHit> collectFindHits(OfficeFindOptions options);

  /// applyReplace API.
  int applyReplace(OfficeFindOptions options, {OfficeFindHit? only});

  /// exportPdf API.
  Uint8List exportPdf({
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
  });

  /// revealFindHit API.
  void revealFindHit(OfficeFindHit hit) {}

  /// find API.
  List<OfficeFindHit> find(OfficeFindOptions options) {
    final List<OfficeFindHit> hits = collectFindHits(options);
    final OfficeFindHit? hit = hits.isEmpty ? null : hits.first;
    if (hit != null) {
      revealFindHit(hit);
    }
    // A rejected reveal (for example, an invalid worksheet draft) must not
    // replace the previous query, result list or selected result.
    findSession
      ..active = true
      ..options = options
      ..hits = hits
      ..index = hits.isEmpty ? -1 : 0;
    onFindResult?.call(hit);
    notifyListeners();
    return hits;
  }

  /// findNext API.
  OfficeFindHit? findNext({bool wrap = true}) {
    if (findSession.hits.isEmpty) {
      final OfficeFindOptions? options = findSession.options;
      if (options != null) {
        find(options);
      }
      return findSession.current;
    }
    final int nextIndex;
    if (findSession.index + 1 < findSession.hits.length) {
      nextIndex = findSession.index + 1;
    } else if (wrap && findSession.hits.isNotEmpty) {
      nextIndex = 0;
    } else {
      return findSession.current;
    }
    final OfficeFindHit? hit =
        nextIndex >= 0 && nextIndex < findSession.hits.length
        ? findSession.hits[nextIndex]
        : null;
    if (hit != null) {
      revealFindHit(hit);
    }
    findSession.index = nextIndex;
    onFindResult?.call(hit);
    notifyListeners();
    return hit;
  }

  /// findPrevious API.
  OfficeFindHit? findPrevious({bool wrap = true}) {
    if (findSession.hits.isEmpty) {
      return findNext(wrap: wrap);
    }
    final int previousIndex;
    if (findSession.index > 0) {
      previousIndex = findSession.index - 1;
    } else if (wrap && findSession.hits.isNotEmpty) {
      previousIndex = findSession.hits.length - 1;
    } else {
      previousIndex = findSession.index;
    }
    final OfficeFindHit? hit =
        previousIndex >= 0 && previousIndex < findSession.hits.length
        ? findSession.hits[previousIndex]
        : null;
    if (hit != null) {
      revealFindHit(hit);
    }
    findSession.index = previousIndex;
    onFindResult?.call(hit);
    notifyListeners();
    return hit;
  }

  /// replace API.
  int replace(OfficeFindOptions options, {OfficeFindHit? only}) {
    if (!config.allowsMutation) {
      return 0;
    }
    final int count = applyReplace(options, only: only);
    if (count > 0) {
      find(options);
    }
    return count;
  }

  /// replaceAll API.
  int replaceAll(OfficeFindOptions options) {
    if (!config.allowsMutation) {
      return 0;
    }
    final int count = applyReplace(options);
    findSession
      ..options = options
      ..hits = const <OfficeFindHit>[]
      ..index = -1;
    notifyListeners();
    return count;
  }

  /// requestFind API.
  void requestFind() {
    findSession.active = true;
    onFindRequested?.call();
    notifyListeners();
  }

  /// requestReplace API.
  void requestReplace() {
    findSession.active = true;
    onReplaceRequested?.call();
    notifyListeners();
  }

  /// requestPrint API.
  void requestPrint() {
    onPrintRequested?.call();
  }

  /// requestSpellCheck API.
  void requestSpellCheck() {
    onSpellCheckRequested?.call();
  }

  /// closeFind API.
  void closeFind() {
    findSession.clear();
    notifyListeners();
  }

  /// replaceCurrent API.
  int replaceCurrent() {
    final OfficeFindHit? hit = findSession.current;
    final OfficeFindOptions? options = findSession.options;
    if (hit == null || options == null) {
      return 0;
    }
    return replace(options, only: hit);
  }

  void _onCommands() {
    _contentRevision++;
    _dirty = true;
    if (_editNotifyDepth > 0 && coalesceEditNotifications) {
      // The edit in progress notifies once when it is done.
      _commandNotifyPending = true;
      return;
    }
    notifyListeners();
  }

  /// Typing edits commit undo commands before they lay out and notify.
  /// While one runs, the command stack's notification is folded into the
  /// edit's own, so listeners (chrome, proofing, the editor widget) run once
  /// per keystroke instead of twice, and never see the model before the
  /// relayout. `--dart-define=QUDS_COALESCE_EDIT_NOTIFY=false` turns it off.
  static bool coalesceEditNotifications = const bool.fromEnvironment(
    'QUDS_COALESCE_EDIT_NOTIFY',
    defaultValue: true,
  );

  int _editNotifyDepth = 0;
  bool _commandNotifyPending = false;

  /// Runs [edit] with command notifications folded into one notification
  /// (the edit's own, or one at the end when it did not notify).
  T _coalescingNotifications<T>(T Function() edit) {
    _editNotifyDepth++;
    try {
      return edit();
    } finally {
      _editNotifyDepth--;
      if (_editNotifyDepth == 0 && _commandNotifyPending) {
        _commandNotifyPending = false;
        notifyListeners();
      }
    }
  }

  @override
  /// notifyListeners API.
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    _commandNotifyPending = false;
    super.notifyListeners();
  }

  @override
  /// dispose API.
  void dispose() {
    _disposed = true;
    commands.removeListener(_onCommands);
    detachInput();
    super.dispose();
  }
}

/// Word document controller: IME, caret, layout, load/save.
class WordEditorController extends OfficeController {
  /// Benchmark hook (null in normal use): receives the duration of each
  /// phase of a typed keystroke (`model`, `undo`, `layout`, `notify`) and,
  /// while [debugTimeListeners] was on when a listener was added, of each
  /// listener (`listener <description>`).
  static void Function(String phase, int microseconds)? debugEditPhase;

  /// Benchmark switch: listeners added while it is true are timed through
  /// [debugEditPhase].
  static bool debugTimeListeners = false;

  final Map<VoidCallback, List<VoidCallback>> _timedListeners =
      <VoidCallback, List<VoidCallback>>{};

  @override
  void addListener(VoidCallback listener) {
    if (!debugTimeListeners) {
      super.addListener(listener);
      return;
    }
    final String label = 'listener $listener';
    void timed() {
      final void Function(String, int)? sink = debugEditPhase;
      if (sink == null) {
        listener();
        return;
      }
      final Stopwatch watch = Stopwatch()..start();
      listener();
      sink(label, watch.elapsedMicroseconds);
    }

    _timedListeners.putIfAbsent(listener, () => <VoidCallback>[]).add(timed);
    super.addListener(timed);
  }

  @override
  void removeListener(VoidCallback listener) {
    final List<VoidCallback>? wrappers = _timedListeners[listener];
    if (wrappers != null && wrappers.isNotEmpty) {
      super.removeListener(wrappers.removeLast());
      if (wrappers.isEmpty) _timedListeners.remove(listener);
      return;
    }
    super.removeListener(listener);
  }

  WordProofingSession? _proofing;
  final OfficeProofingVocabulary? _initialProofingVocabulary;
  final OfficeProofingService? _initialProofingService;
  String _revisionAuthor;
  bool _reviewPaneVisible = false;
  bool _reviewTextProofingOptionsVisible = false;
  int _textProofingOptionsRequest = 0;
  WordReviewPaneTab _reviewPaneTab = WordReviewPaneTab.proofing;
  WordProofingIssue? _selectedProofingIssue;
  final Map<WordProofingIssue, WordProofingIssue> _noteProofingCommitAliases =
      Map.identity();
  Future<WordProofingSummary>? _explicitProofingCheck;
  int? _explicitProofingGeneration;
  ({WmlParagraph? paragraph, int offset, int? anchor, int? anchorParagraph})?
  _proofingSelectionCaret;
  WordThesaurusTarget? _thesaurusTarget;
  WordThesaurusLookup? _thesaurusLookup;
  int _thesaurusGeneration = 0;

  /// Host chrome: Shift+F7. Capture the target before changing input focus.
  VoidCallback? onThesaurusRequested;

  void requestThesaurus() {
    if (!isDisposed) onThesaurusRequested?.call();
  }

  /// Review chrome is session state and never marks the document dirty.
  bool get reviewPaneVisible => _reviewPaneVisible;
  WordReviewPaneTab get reviewPaneTab => _reviewPaneTab;

  bool get reviewTextProofingOptionsVisible =>
      _reviewTextProofingOptionsVisible;

  /// Advances even when already open, so hosts can reveal the controls again.
  int get textProofingOptionsRequest => _textProofingOptionsRequest;

  /// Expanding or collapsing text options is session state only.
  void setTextProofingOptionsVisible(bool visible) {
    if (isDisposed || _reviewTextProofingOptionsVisible == visible) return;
    _reviewTextProofingOptionsVisible = visible;
    notifyListeners();
  }

  /// Opens the current text's language and proofing controls in Writing.
  void showTextProofingOptions() {
    if (isDisposed) return;
    _reviewTextProofingOptionsVisible = true;
    _textProofingOptionsRequest++;
    openReviewPane();
  }

  void openReviewPane({WordReviewPaneTab tab = WordReviewPaneTab.proofing}) {
    if (isDisposed) return;
    _reviewPaneVisible = true;
    _reviewPaneTab = tab;
    notifyListeners();
  }

  void closeReviewPane() {
    if (!_reviewPaneVisible || isDisposed) return;
    _reviewPaneVisible = false;
    notifyListeners();
    requestEditingFocus();
  }

  void setReviewPaneTab(WordReviewPaneTab tab) {
    if (_reviewPaneTab == tab || isDisposed) return;
    _reviewPaneTab = tab;
    notifyListeners();
  }

  /// Attribution for changes recorded from now on. Existing changes retain
  /// their original authors, including across undo and redo.
  String get revisionAuthor => _revisionAuthor;

  set revisionAuthor(String value) {
    final author = _normalizeRevisionAuthor(value);
    if (author == _revisionAuthor) return;
    _revisionAuthor = author;
    notifyListeners();
  }

  static String _normalizeRevisionAuthor(String value) {
    final author = value.trim();
    if (author.isEmpty) {
      throw ArgumentError.value(value, 'revisionAuthor', 'Must not be empty');
    }
    return author;
  }

  /// Offline German checkers are available immediately. The shared editor
  /// enables background checking unless the host/user has set a preference;
  /// standalone controllers remain idle until a host requests a check.
  WordProofingSession get proofing {
    _proofing ??= WordProofingSession(
      document: () => document,
      revision: () => contentRevision,
      priorityParagraph: () => _proofingPriorityParagraph,
      // Canvas typing only; never materializes a story paragraph.
      caretPosition: () {
        if (noteEditingTarget != null || !caret.isCollapsed) return null;
        final paragraph = _proofingPriorityParagraph;
        return paragraph == null
            ? null
            : (paragraph: paragraph, offset: caret.logicalIndex);
      },
      vocabulary: _initialProofingVocabulary,
      service: _initialProofingService,
      visibleParagraphs: _proofingVisibleParagraphs,
    )..addListener(_onProofingChanged);
    return _proofing!;
  }

  /// Body paragraphs on the visible page and its neighbours, from the
  /// current layout; background proofing checks them first.
  Iterable<WmlParagraph> _proofingVisibleParagraphs() sync* {
    final pages = documentLaidOut.pages;
    if (pages.isEmpty) return;
    final visible = visiblePageIndex.clamp(0, pages.length - 1);
    final last = visible + 1 < pages.length ? visible + 1 : pages.length - 1;
    for (var index = visible > 0 ? visible - 1 : 0; index <= last; index++) {
      for (final line in pages[index].lines) {
        final paragraph = line.sourceParagraph;
        if (paragraph != null) yield paragraph;
      }
    }
  }

  // Inspect existing text only: checking must not materialize empty comment,
  // header or body paragraphs merely to choose the first item in a pass.
  WmlParagraph? get _proofingPriorityParagraph {
    final note = noteEditingTarget;
    if (note != null) {
      return _noteSelectionRange((
        note: note.note,
        selection: TextSelection.collapsed(offset: note.selection.extentOffset),
        composing: note.composing,
      ))?.paragraph;
    }
    final Iterable<WmlParagraph> paragraphs;
    if (_editingComment) {
      paragraphs = selectedComment?.paragraphs ?? const <WmlParagraph>[];
    } else if (_editingHeaderFooter) {
      if (_editingSectionIndex < 0 ||
          _editingSectionIndex >= document.sections.length) {
        return null;
      }
      final section = document.sections[_editingSectionIndex];
      paragraphs = _headerFooterStory(section);
    } else {
      paragraphs = document.paragraphs;
    }
    final index = caret.paragraphIndex;
    return index < 0 ? null : paragraphs.skip(index).firstOrNull;
  }

  void _onProofingChanged() => super.notifyListeners();

  @override
  void notifyListeners() {
    final target = _thesaurusTarget;
    if (target != null && !_matchesThesaurusSelection(target)) {
      _thesaurusGeneration++;
      _thesaurusTarget = null;
      _thesaurusLookup = null;
    }
    // An active composition is not committed text. Do not schedule proofing
    // against the intermediate IME value; the commit notification observes
    // the final text and schedules the normal check.
    if (input.composing.isValid && !input.composing.isCollapsed) {
      _proofing?.suspendForComposition();
      super.notifyListeners();
      return;
    }
    _proofing?.observeDocument();
    super.notifyListeners();
  }

  @override
  void refresh() {
    _proofing?.refresh();
    super.refresh();
  }

  /// Updates selection/scroll chrome without invalidating checked text. Use
  /// [refresh] after a direct model edit that bypasses controller commands.
  void refreshView() => notifyListeners();

  @override
  void dispose() {
    _proofing?.removeListener(_onProofingChanged);
    _proofing?.dispose();
    _timedListeners.clear();
    super.dispose();
  }

  /// WordEditorController API.
  WordEditorController({
    WmlDocument? document,
    super.config,
    this.layoutEngine,
    LaidOutDocument? initialLayout,
    OfficeProofingVocabulary? proofingVocabulary,
    OfficeProofingService? proofingService,
    String revisionAuthor = 'CrispOffice',
  }) : _document = document ?? WmlDocument.empty(),
       _initialProofingVocabulary = proofingVocabulary,
       _initialProofingService = proofingService,
       _revisionAuthor = _normalizeRevisionAuthor(revisionAuthor) {
    _requestedMode = _config.mode;
    _config = _effectiveConfig(_config);
    if (initialLayout == null) {
      relayout();
    } else {
      documentLaidOut = initialLayout;
    }
    input = OfficeInputBridge(
      onValue: (value) => _coalescingNotifications(() => _onIme(value)),
      onAction: _onImeAction,
      onSelector: _onImeSelector,
    );
  }

  /// fromBytes API.
  factory WordEditorController.fromBytes(
    Uint8List bytes, {
    String? password,
    OfficeSurfaceConfig? config,
    WordLayoutEngine? layoutEngine,
    OfficeProofingVocabulary? proofingVocabulary,
    OfficeProofingService? proofingService,
    String revisionAuthor = 'CrispOffice',
  }) {
    final WordEditorController controller = WordEditorController(
      config: config,
      layoutEngine: layoutEngine,
      proofingVocabulary: proofingVocabulary,
      proofingService: proofingService,
      revisionAuthor: revisionAuthor,
    );
    controller.loadBytes(bytes, password: password);
    return controller;
  }

  /// document API.
  ///
  /// Assigning a different document marks the current layout as belonging to
  /// the old one: the next read of [documentLaidOut] (the canvas's next
  /// paint, or an explicit [relayout]) lays the new document out in full.
  /// Without this, the layout stayed the old document's until the first
  /// keystroke, which then paid a full layout (and an incremental attempt
  /// could reuse pages of the old document). Switch:
  /// [layoutReplacedDocumentOnRead].
  WmlDocument get document => _document;
  set document(WmlDocument value) {
    if (identical(value, _document)) return;
    _openGeneration++;
    _document = value;
    _documentReplaced = true;
  }

  WmlDocument _document;
  int _openGeneration = 0;

  /// True while [documentLaidOut] still shows a previously assigned
  /// [document].
  bool _documentReplaced = false;

  /// When false (`--dart-define=QUDS_LAZY_DOCUMENT_LAYOUT=false`), assigning
  /// [document] leaves the old layout in place until the next [relayout],
  /// as before.
  static bool layoutReplacedDocumentOnRead = const bool.fromEnvironment(
    'QUDS_LAZY_DOCUMENT_LAYOUT',
    defaultValue: true,
  );

  // Keep the host's requested interaction mode separate from document
  // restrictions so a rebuild cannot bypass protection or undo enable edits
  // in an intentionally read-only host.
  late OfficeInteractionMode _requestedMode;

  OfficeSurfaceConfig _effectiveConfig(OfficeSurfaceConfig value) =>
      document.restrictEditing &&
          (document.restrictMode != WmlRestrictMode.none ||
              document.protectionFormattingRestricted) &&
          value.allowsMutation
      ? value.copyWith(mode: OfficeInteractionMode.viewing)
      : value;

  /// Whether the host can change Word protection without password verification.
  bool get canChangeProtection =>
      !_disposed &&
      _requestedMode == OfficeInteractionMode.editing &&
      !document.protectionHasPassword;

  @override
  set config(OfficeSurfaceConfig value) {
    _requestedMode = value.mode;
    super.config = _effectiveConfig(value);
    if (!config.allowsMutation) detachInput();
  }

  @override
  void syncConfig(OfficeSurfaceConfig value) {
    _requestedMode = value.mode;
    super.syncConfig(_effectiveConfig(value));
    if (!config.allowsMutation) detachInput();
  }

  @override
  void setMode(OfficeInteractionMode mode) {
    _requestedMode = mode;
    super.setMode(_effectiveConfig(_config.copyWith(mode: mode)).mode);
  }

  void _syncProtectionMode() {
    _config = _effectiveConfig(_config.copyWith(mode: _requestedMode));
    if (!config.allowsMutation) detachInput();
  }

  @override
  bool get canUndo => config.allowsMutation
      ? super.canUndo
      : canChangeProtection &&
            commands.nextUndoCommand is _WordProtectionCommand;

  @override
  bool get canRedo => config.allowsMutation
      ? super.canRedo
      : canChangeProtection &&
            commands.nextRedoCommand is _WordProtectionCommand;

  /// documentLaidOut API.
  ///
  /// Lays out a newly assigned [document] first (see [document]).
  LaidOutDocument get documentLaidOut {
    if (_documentReplaced && layoutReplacedDocumentOnRead) relayout();
    return _documentLaidOut;
  }

  set documentLaidOut(LaidOutDocument value) => _documentLaidOut = value;

  late LaidOutDocument _documentLaidOut;

  /// commentLaidOut API.
  LaidOutDocument? commentLaidOut;

  /// Custom layout engine. When null, complete logical runs are measured by
  /// Flutter before wrapping, with scalar metrics as an explicit fallback.
  final WordLayoutEngine? layoutEngine;

  WordLayoutEngine? _paintMetricsEngine;

  WordLayoutEngine get _engine =>
      layoutEngine ?? (_paintMetricsEngine ??= _newPaintMetricsEngine());

  WordLayoutEngine _newPaintMetricsEngine({
    void Function(WordLayoutProgress progress)? onProgress,
  }) => WordLayoutEngine(
    font: null,
    onProgress: onProgress,
    measureFont: (codePoint, sizePoints, props) => OfficeHostFonts.wordMetrics(
      codePoint,
      sizePoints,
      props,
      themeFamily: config.theme.fontFamily,
    ),
    measureRun: (text, sizePoints, props, bidiLevel) => WordRunMetrics.measure(
      text,
      sizePoints,
      props,
      bidiLevel,
      respectKerningThreshold: true,
      themeFamily: config.theme.fontFamily,
    ),
    measure: (int codePoint, double sizePoints, WmlRunProps props) =>
        PaintRunText.advanceOf(
          codePoint,
          sizePoints,
          props,
          themeFamily: config.theme.fontFamily,
        ),
  );

  /// Reflow after fonts load. The editor fits paint metrics when a page enters
  /// view; explicit export and print callers can still fit the full layout.
  void refreshMetrics() {
    if (documentLaidOut.isPreview) return;
    relayout();
    notifyListeners();
  }

  /// documentCaret API.
  final CaretEngine documentCaret = CaretEngine();

  /// commentCaret API.
  final CaretEngine commentCaret = CaretEngine();

  /// headerFooterCaret API.
  final CaretEngine headerFooterCaret = CaretEngine();
  var _editingComment = false;
  var _editingHeaderFooter = false;
  var _editingFooter = false;
  var _editingHeaderFooterVariant = WordHeaderFooterVariant.standard;
  var _editingSectionIndex = 0;

  /// commentSurfaceWidth API.
  double commentSurfaceWidth = 288;

  /// input API.
  late final OfficeInputBridge input;
  var _applyingIme = false;
  Object? _imeValueTarget;

  /// fromMillisecondsSinceEpoch API.
  var _localEditAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _textBeforeLocalEdit;
  bool _historyRestoredSelection = false;
  double? _stickyCaretX;
  // Only this controller's inferred values may follow later UI-language
  // changes. Imported/authored directions and replacement property objects
  // remain authoritative, including explicit LTR on an empty paragraph.
  final Expando<({WmlParagraphProps properties, bool? rightToLeft})>
  _automaticParagraphDirections = Expando('automatic paragraph directions');

  @override
  /// kind API.
  OpcPackageKind get kind => OpcPackageKind.word;

  /// Index into [WmlDocument.revisions], or null.
  int? selectedRevisionIndex;

  /// selectedVisual API.
  WmlVisual? selectedVisual;

  /// selectedFrame API.
  WmlFrame? selectedFrame;

  /// True after a double-click: text caret only, no move/resize knobs.
  var editingFrame = false;

  /// selectedEquation API.
  WmlEquation? selectedEquation;

  /// selectedCommentId API.
  int? selectedCommentId;

  /// equationSlot API.
  var equationSlot = 0;

  /// equationCaret API.
  var equationCaret = 0;

  /// onRequestFocus API.
  VoidCallback? onRequestFocus;

  /// pictureCropMode API.
  var pictureCropMode = false;
  ({double x, double y, double width, double height})? _frameSnap;
  ({
    double width,
    double height,
    double offsetX,
    double offsetY,
    double rotationDeg,
    double cropLeft,
    double cropTop,
    double cropRight,
    double cropBottom,
  })?
  _visualSnap;

  /// caret API.
  CaretEngine get caret {
    if (isEditingComment) {
      return commentCaret;
    }
    if (isEditingHeaderFooter) {
      return headerFooterCaret;
    }
    return documentCaret;
  }

  /// laidOut API.
  LaidOutDocument get laidOut => isEditingComment && commentLaidOut != null
      ? commentLaidOut!
      : documentLaidOut;

  /// isEditingComment API.
  bool get isEditingComment => _editingComment && selectedComment != null;

  /// isEditingHeaderFooter API.
  bool get isEditingHeaderFooter => _editingHeaderFooter;

  /// isEditingFooter API.
  bool get isEditingFooter => _editingHeaderFooter && _editingFooter;

  /// isEditingHeader API.
  bool get isEditingHeader => _editingHeaderFooter && !_editingFooter;

  /// editingSectionIndex API.
  int get editingSectionIndex => _editingSectionIndex;

  /// The exact header/footer variant selected on the rendered page.
  WordHeaderFooterVariant get editingHeaderFooterVariant =>
      _editingHeaderFooterVariant;

  /// headerFooterParagraphs API.
  List<WmlParagraph> get headerFooterParagraphs =>
      _ensureHeaderFooterParagraphs();

  /// Modern comments: Home character format only — no font/size/styles/paragraph.
  bool get commentFormatLimited => isEditingComment;

  List<WmlParagraph> get _paragraphs {
    if (isEditingComment) {
      return _ensureCommentParagraphs(selectedComment!);
    }
    if (isEditingHeaderFooter) {
      return _ensureHeaderFooterParagraphs();
    }
    return document.paragraphs.toList();
  }

  /// visuals API.
  List<WmlVisual> get visuals => document.visuals.toList();

  WmlParagraph get _activeParagraph {
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      final WmlParagraph created = WmlParagraph();
      if (isEditingComment) {
        selectedComment!.paragraphs.add(created);
        return created;
      }
      if (isEditingHeaderFooter) {
        _ensureHeaderFooterParagraphs().add(created);
        return created;
      }
      sectionAtCaret.blocks.add(created);
      return created;
    }
    return paras[caret.paragraphIndex.clamp(0, paras.length - 1)];
  }

  List<WmlParagraph> _ensureCommentParagraphs(WmlComment comment) {
    if (comment.paragraphs.isEmpty) {
      final placeholder = WmlParagraph(
        inlines: <WmlInline>[
          WmlRun(properties: WmlRunProps(fontSizeHalfPoints: 20)),
        ],
      );
      // Viewing an empty comment needs a layout/caret target, without adding
      // a paragraph to the stored document merely to select or copy its text.
      if (!config.allowsMutation) return <WmlParagraph>[placeholder];
      comment.paragraphs.add(placeholder);
    }
    return comment.paragraphs;
  }

  /// commentDocument API.
  WmlDocument get commentDocument {
    final WmlComment comment = selectedComment!;
    return WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          pageSize: WmlPageSize(width: commentSurfaceWidth, height: 2000),
          margins: const WmlPageMargins(top: 4, bottom: 4, left: 4, right: 4),
          blocks: <WmlBlock>[
            ..._ensureCommentParagraphs(comment),
            ...comment.visuals,
          ],
        ),
      ],
    );
  }

  /// commentSurfaceHeight API.
  double get commentSurfaceHeight {
    final LaidOutDocument? laid = commentLaidOut;
    if (laid == null || laid.pages.isEmpty) {
      return 72;
    }
    var bottom = 20.0;
    for (final LaidOutLine line in laid.pages.first.lines) {
      final double edge = line.y + line.height;
      if (edge > bottom) {
        bottom = edge;
      }
    }
    for (final LaidOutBox box in laid.pages.first.frames) {
      final double edge = box.y + box.height;
      if (edge > bottom) {
        bottom = edge;
      }
    }
    return (bottom + 10).clamp(56.0, 320.0);
  }

  List<WmlParagraph> _headerFooterStory(WmlSection section) =>
      switch (_editingHeaderFooterVariant) {
        WordHeaderFooterVariant.standard =>
          _editingFooter ? section.footer : section.header,
        WordHeaderFooterVariant.firstPage =>
          _editingFooter ? section.firstFooter : section.firstHeader,
        WordHeaderFooterVariant.evenPage =>
          _editingFooter ? section.evenFooter : section.evenHeader,
      };

  List<WmlParagraph> _ensureHeaderFooterParagraphs() {
    final WmlSection section = document.sections.isEmpty
        ? WmlSection()
        : document.sections[_editingSectionIndex.clamp(
            0,
            document.sections.length - 1,
          )];
    final List<WmlParagraph> story = _headerFooterStory(section);
    if (story.isEmpty) {
      final placeholder = WmlParagraph(inlines: <WmlInline>[WmlRun(text: '')]);
      // Selecting or inspecting an empty protected story must not add content.
      if (!config.allowsMutation ||
          (document.restrictEditing &&
              document.restrictMode != WmlRestrictMode.none)) {
        return <WmlParagraph>[placeholder];
      }
      story.add(placeholder);
    }
    return story;
  }

  /// beginHeaderFooterEdit API.
  void beginHeaderFooterEdit(int pageIndex, {required bool footer}) {
    if (!config.allowsMutation && !config.allowsSelection) {
      return;
    }
    clearNoteEditingTarget();
    endCommentEdit();
    final int sectionIndex =
        pageIndex >= 0 && pageIndex < documentLaidOut.pages.length
        ? documentLaidOut.pages[pageIndex].sectionIndex
        : sectionIndexAtCaret;
    _editingSectionIndex = sectionIndex.clamp(
      0,
      document.sections.isEmpty ? 0 : document.sections.length - 1,
    );
    _editingFooter = footer;
    final section = document.sections.isEmpty
        ? WmlSection()
        : document.sections[_editingSectionIndex];
    final firstPage = documentLaidOut.pages.indexWhere(
      (page) => page.sectionIndex == _editingSectionIndex,
    );
    final story = footer
        ? section.footerForPage(
            pageIndex + 1,
            firstInSection: pageIndex == firstPage,
          )
        : section.headerForPage(
            pageIndex + 1,
            firstInSection: pageIndex == firstPage,
          );
    _editingHeaderFooterVariant =
        identical(story, footer ? section.firstFooter : section.firstHeader)
        ? WordHeaderFooterVariant.firstPage
        : identical(story, footer ? section.evenFooter : section.evenHeader)
        ? WordHeaderFooterVariant.evenPage
        : WordHeaderFooterVariant.standard;
    _editingHeaderFooter = true;
    selectedVisual = null;
    selectedFrame = null;
    editingFrame = false;
    selectedEquation = null;
    selectedTable = null;
    selectedTableBand = null;
    final List<WmlParagraph> paras = _ensureHeaderFooterParagraphs();
    headerFooterCaret
      ..paragraphIndex = 0
      ..logicalIndex = 0
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 0;
    headerFooterCaret.paragraphIndex = headerFooterCaret.paragraphIndex.clamp(
      0,
      paras.length - 1,
    );
    relayout();
    _revealPage(pageIndex);
    onRequestFocus?.call();
    attachInput();
    notifyListeners();
  }

  /// Zooms while keeping the currently visible page and in-page offset fixed.
  ///
  /// The canvas stacks pages with unscaled gaps, so simply scaling
  /// [viewport.origin] drifts across page boundaries when the user zooms.
  void setZoomPreservingPage(double value) {
    const double pointsToPixels = 96 / 72;
    final double oldScale = viewport.scale * pointsToPixels;
    if (oldScale <= 0) {
      viewport.setScale(value);
      notifyListeners();
      return;
    }
    final double viewH = viewport.extent.height > 0
        ? viewport.extent.height
        : 1;
    final double anchorY = viewport.origin.dy + viewH * 0.35;
    final int page = documentLaidOut.pageIndexAtContentY(anchorY, oldScale);
    final double pageTop = documentLaidOut.pageStackTop(page, oldScale);
    final double offset = anchorY - pageTop;
    viewport.setScale(value);
    final double nextScale = viewport.scale * pointsToPixels;
    final double nextPageTop = documentLaidOut.pageStackTop(page, nextScale);
    final double nextY =
        nextPageTop + offset * (nextScale / oldScale) - viewH * 0.35;
    viewport.origin = Offset(viewport.origin.dx, nextY < 0 ? 0 : nextY);
    notifyListeners();
  }

  void _revealPage(int pageIndex) {
    if (documentLaidOut.pages.isEmpty) {
      return;
    }
    final int index = pageIndex.clamp(0, documentLaidOut.pages.length - 1);
    const double pointsToPixels = 96 / 72;
    final double scale = viewport.scale * pointsToPixels;
    final double top = documentLaidOut.pageStackTop(index, scale);
    viewport.origin = Offset(viewport.origin.dx, top < 0 ? 0 : top);
  }

  /// endHeaderFooterEdit API.
  void endHeaderFooterEdit() {
    if (!_editingHeaderFooter) {
      return;
    }
    _editingHeaderFooter = false;
    notifyListeners();
  }

  /// beginCommentEdit API.
  void beginCommentEdit(int id) {
    if (!config.allowsMutation && !config.allowsSelection) {
      return;
    }
    selectedCommentId = id;
    if (selectedComment == null) {
      return;
    }
    clearNoteEditingTarget();
    endHeaderFooterEdit();
    _editingComment = true;
    selectedVisual = null;
    selectedFrame = null;
    editingFrame = false;
    selectedEquation = null;
    selectedTable = null;
    selectedTableBand = null;
    final List<WmlParagraph> paras = _ensureCommentParagraphs(selectedComment!);
    commentCaret.paragraphIndex = commentCaret.paragraphIndex.clamp(
      0,
      paras.length - 1,
    );
    final int max = paras[commentCaret.paragraphIndex].text.length;
    commentCaret.logicalIndex = commentCaret.logicalIndex.clamp(0, max);
    commentCaret.selectionAnchorParagraph = commentCaret
        .selectionAnchorParagraph
        .clamp(0, paras.length - 1);
    commentCaret.selectionAnchor = commentCaret.selectionAnchor.clamp(
      0,
      paras[commentCaret.selectionAnchorParagraph].text.length,
    );
    _layoutComment();
    onRequestFocus?.call();
    attachInput();
    notifyListeners();
  }

  /// endCommentEdit API.
  void endCommentEdit() {
    if (!_editingComment) {
      return;
    }
    _editingComment = false;
    notifyListeners();
  }

  /// setCommentSurfaceWidth API.
  void setCommentSurfaceWidth(double width) {
    final double next = width.clamp(160.0, 480.0);
    if ((commentSurfaceWidth - next).abs() < 0.5) {
      return;
    }
    commentSurfaceWidth = next;
    if (selectedComment != null) {
      _layoutComment();
      notifyListeners();
    }
  }

  void _layoutComment() {
    if (selectedComment == null) {
      commentLaidOut = null;
      return;
    }
    commentLaidOut = _engine.layout(commentDocument);
  }

  /// loadBytes API.
  void loadBytes(Uint8List bytes, {String? password}) {
    if (isDisposed) {
      throw StateError('Cannot open a file in a disposed editor.');
    }
    _openGeneration++;
    if (OdtDocumentReader.isOdt(bytes)) {
      throw UnsupportedError(
        'Use loadBytesAsync to import a native ODT document.',
      );
    }
    _acceptOpenedWord(
      WordDeserializer().read(OfficeRepair.open(bytes, password: password)),
    );
  }

  /// Opens DOCX or a supported native ODT without replacing newer work.
  ///
  /// Failed imports and results made stale by an edit, document replacement,
  /// another open request or disposal leave the active document untouched.
  Future<void> loadBytesAsync(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
    void Function(WmlDocument document, LaidOutDocument firstPage)? onFirstPage,
  }) async {
    if (isDisposed) {
      throw StateError('Cannot open a file in a disposed editor.');
    }
    final int generation = ++_openGeneration;
    final WmlDocument original = document;
    final int revision = contentRevision;
    bool isCurrent() =>
        !isDisposed &&
        generation == _openGeneration &&
        identical(document, original) &&
        contentRevision == revision;
    final WmlDocument opened = await OfficeIsolateOpen.wordDocument(
      bytes,
      password: password,
      onProgress: onProgress,
    );
    if (!isCurrent()) {
      throw StateError('The document changed while the file was opening.');
    }
    if (onFirstPage == null || layoutEngine != null) {
      // Opening shows the authored cached TOC page numbers, as Word does.
      // Rebuilding them would require a second full layout of a large file.
      _acceptOpenedWord(opened, syncToc: false);
      return;
    }
    _prepareOpenedWord(opened);
    WordLink.ensureHeadingBookmarks(opened);
    WordToc.refreshEmpty(opened);
    // Only a generated TOC without page numbers needs the extra full pass.
    final bool needsTocSync = _needsTocPageSync(opened);
    // Keep a separate engine until the result is accepted. Edits or a new
    // document can use the active editor's engine while this one is yielding.
    var progressBase = 0.45;
    var progressSpan = needsTocSync ? 0.30 : 0.52;
    final engine = _newPaintMetricsEngine(
      onProgress: onProgress == null
          ? null
          : (progress) => onProgress(
              OfficeOpenProgress(
                value: progressBase + progressSpan * progress.fraction,
                stage: 'layout',
                detail:
                    'Layout: ${progress.pages} pages · '
                    '${progress.blocksDone}/${progress.blocksTotal} blocks · '
                    '${progress.notesDone}/${progress.notesTotal} notes',
              ),
            ),
    );
    var layout = await engine.layoutProgressively(
      opened,
      onFirstPage: (page) => onFirstPage(opened, page),
      isCurrent: isCurrent,
    );
    if (needsTocSync && WordToc.syncPageNumbers(opened, layout)) {
      progressBase = 0.75;
      progressSpan = 0.22;
      layout = await engine.layoutProgressively(
        opened,
        onFirstPage: (_) {},
        isCurrent: isCurrent,
      );
    }
    if (!isCurrent()) {
      throw StateError('The document changed while the file was opening.');
    }
    _paintMetricsEngine = engine;
    _acceptOpenedWord(opened, layout: layout);
  }

  void _prepareOpenedWord(WmlDocument opened) {
    final first = opened.paragraphs.firstOrNull;
    if (first != null && first.text.trim().isEmpty) {
      _syncParagraphDirection(first);
    }
  }

  void _acceptOpenedWord(
    WmlDocument opened, {
    LaidOutDocument? layout,
    bool syncToc = true,
  }) {
    if (layout == null) {
      _prepareOpenedWord(opened);
      layout = _layoutWordDocument(opened, syncToc: syncToc);
    }
    document = opened;
    commands.clear();
    _noteEditStart.clear();
    _noteProofingCommitAliases.clear();
    _noteEditingTarget = null;
    _noteBodyTarget = null;
    _syncProtectionMode();
    _editingComment = false;
    _editingHeaderFooter = false;
    _editingHeaderFooterVariant = WordHeaderFooterVariant.standard;
    documentCaret.paragraphIndex = 0;
    documentCaret.logicalIndex = 0;
    documentCaret.collapseSelection();
    commentCaret.paragraphIndex = 0;
    commentCaret.logicalIndex = 0;
    commentCaret.collapseSelection();
    selectedVisual = null;
    selectedEquation = null;
    equationSlot = 0;
    equationCaret = 0;
    pictureCropMode = false;
    documentLaidOut = layout;
    _documentReplaced = false;
    _layoutComment();
    _dirty = false;
    notifyListeners();
  }

  @override
  void commitPendingEdits() => commitNoteEdits();

  @override
  /// saveBytes API.
  Uint8List saveBytes({String? password}) {
    commitPendingEdits();
    final Uint8List bytes = WordSerializer().writeBytes(
      document,
      password: password,
    );
    markClean();
    return bytes;
  }

  @override
  /// saveBytesAsync API.
  Future<Uint8List> saveBytesAsync({String? password}) {
    commitPendingEdits();
    return OfficeIsolateSave.word(document, password: password);
  }

  /// Host opens web / file targets. Internal anchors stay in the editor.
  void Function(WmlHyperlink link)? onFollowExternalLink;

  /// Host-owned language support/download UI. These callbacks never download
  /// anything themselves and run only after a successful language edit.
  void Function(String language)? onProofingLanguageChanged;
  VoidCallback? onManageProofingDownloads;

  /// relayout API.
  ///
  /// [localEdit] declares that only the paragraphs in [dirty] (default: the
  /// paragraphs of the caret selection after the edit) changed, plus
  /// inserted or removed blocks and paragraph text. The engine then lays out
  /// only from the first changed block until the flow meets the previous
  /// layout again ([WordLayoutEngine.incrementalLayout]); the result equals a
  /// full layout without field updates.
  void relayout({bool localEdit = false, Iterable<WmlParagraph>? dirty}) {
    final bool replaced = _documentReplaced;
    if (replaced) {
      // The previous layout belongs to another document: nothing in it can
      // be reused, so lay the new one out in full.
      _documentReplaced = false;
      localEdit = false;
    }
    try {
      _relayoutCurrentDocument(localEdit: localEdit, dirty: dirty);
    } catch (_) {
      // A failed replacement must never make the old document's layout
      // appear current. Keep both lazy reads and explicit relayouts retryable.
      if (replaced) _documentReplaced = true;
      rethrow;
    }
  }

  LaidOutDocument _layoutWordDocument(
    WmlDocument model, {
    bool syncToc = true,
  }) {
    WordLink.ensureHeadingBookmarks(model);
    WordToc.refreshEmpty(model);
    WordToc.rebindHeadings(model);
    final engine = _engine;
    final layout = engine.layout(model);
    if (!syncToc && !_needsTocPageSync(model)) return layout;
    return WordToc.syncPageNumbers(model, layout)
        ? engine.layout(model)
        : layout;
  }

  /// True when a TOC has entries but no cached page numbers yet.
  bool _needsTocPageSync(WmlDocument model) => WordToc.tocs(
    model,
  ).any((toc) => toc.entries.any((entry) => entry.pageNumber <= 0));

  void _relayoutCurrentDocument({
    required bool localEdit,
    Iterable<WmlParagraph>? dirty,
  }) {
    _syncEmptyParagraphDirection();
    // Header/footer text is chrome, not section body content. The incremental
    // layout path reuses page chrome, so edits there would never reach the
    // header band. Force a full layout while editing a header or footer.
    final bool incremental = localEdit && !isEditingHeaderFooter;
    if (!incremental) {
      documentLaidOut = _layoutWordDocument(document);
      _layoutComment();
      return;
    }
    final WordLayoutEngine engine = _engine;
    final int fromSection = sectionIndexAtCaret;
    if (WordLayoutEngine.incrementalLayout) {
      final LaidOutDocument previous = documentLaidOut;
      // Paint-fitted lines get their engine values back first, so they can
      // be reused line by line (the new layout is unfitted, as a full
      // relayout after an edit is).
      _FittedLines.restore(previous);
      documentLaidOut = previous.supportsIncrementalReuse
          ? engine.layout(
              document,
              updateFields: false,
              fromSectionIndex: fromSection,
              reuse: previous,
              dirtyParagraphs: Set<WmlParagraph>.identity()
                ..addAll(dirty ?? _localEditParagraphs()),
            )
          : engine.layout(document, updateFields: false);
    } else {
      // The section-level path reuses earlier pages as they are (fitted),
      // without recording incremental state from them.
      if (_FittedLines.of(documentLaidOut) != null) {
        documentLaidOut.discardIncrementalState();
      }
      documentLaidOut = engine.layout(
        document,
        updateFields: false,
        fromSectionIndex: fromSection,
        reuse: documentLaidOut,
      );
    }
    if (isEditingComment) {
      _layoutComment();
    }
  }

  /// Paragraphs a local edit may have changed: the caret selection after it.
  List<WmlParagraph> _localEditParagraphs() {
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) return const <WmlParagraph>[];
    final range = caret.normalizedRange;
    final int start = range.startPara < range.endPara
        ? range.startPara
        : range.endPara;
    final int end = range.startPara < range.endPara
        ? range.endPara
        : range.startPara;
    if (end < 0 || start >= paras.length) return const <WmlParagraph>[];
    return paras.sublist(
      start.clamp(0, paras.length - 1),
      end.clamp(0, paras.length - 1) + 1,
    );
  }

  @override
  void onSurfaceDirectionChanged() {
    _syncEmptyParagraphDirection();
    if (config.allowsMutation) {
      attachInput();
    }
  }

  /// Effective formatting at the active paragraph.
  WmlParagraphProps get activeParagraphProperties =>
      _activeParagraph.properties;

  /// activeHeadingLevel API.
  int get activeHeadingLevel => WordToc.headingLevelOf(_activeParagraph) ?? 0;

  /// applyHeading API.
  void applyHeading(int level) {
    if (!config.allowsMutation || isEditingComment) {
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    final int startPara;
    final int endPara;
    if (caret.isCollapsed) {
      startPara = caret.paragraphIndex.clamp(0, paras.length - 1);
      endPara = startPara;
    } else {
      final ({int startPara, int startIdx, int endPara, int endIdx}) range =
          caret.normalizedRange;
      startPara = range.startPara;
      endPara = range.endPara;
    }
    final List<int> targets = <int>[
      for (int p = startPara; p <= endPara; p++)
        if (!WordToc.isFieldParagraph(paras[p])) p,
    ];
    if (targets.isEmpty) {
      return;
    }
    final Map<int, _HeadingSnap> before = <int, _HeadingSnap>{
      for (final int p in targets) p: _HeadingSnap.capture(paras[p]),
    };
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final int p in targets) {
            before[p]!.restore(paras[p]);
            WordHeadingIo.apply(document, paras[p], level);
          }
        },
        undoFn: () {
          for (final int p in targets) {
            before[p]!.restore(paras[p]);
          }
        },
      ),
    );
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _syncImeSelection();
    notifyListeners();
  }

  /// insertHeading API.
  void insertHeading({int level = 1, String text = ''}) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlParagraph created = WmlParagraph(
      inlines: <WmlInline>[WmlRun(text: text)],
    );
    WordToc.applyHeading(created, level);
    final ({List<WmlBlock> parent, int index})? slot = _hostSlotOf(
      _activeParagraph,
    );
    final List<WmlBlock> parent =
        slot?.parent ?? document.sections.first.blocks;
    final int at = slot == null
        ? parent.length
        : (slot.index + 1).clamp(0, parent.length);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (!parent.contains(created)) {
            parent.insert(at.clamp(0, parent.length), created);
          }
        },
        undoFn: () => parent.remove(created),
      ),
    );
    final List<WmlParagraph> paras = _paragraphs;
    caret.paragraphIndex = paras.indexOf(created).clamp(0, paras.length - 1);
    caret.logicalIndex = created.text.length;
    caret.collapseSelection();
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _syncImeSelection();
    notifyListeners();
  }

  /// insertTableOfContents API.
  void insertTableOfContents({
    int minLevel = 1,
    int maxLevel = 3,
    String title = 'Table of Contents',
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlToc toc = WmlToc(
      minLevel: minLevel,
      maxLevel: maxLevel,
      title: title,
    );
    final ({List<WmlBlock> parent, int index})? slot = _topLevelInsertSlot();
    final List<WmlBlock> parent =
        slot?.parent ?? document.sections.first.blocks;
    final int index = slot == null
        ? 0
        : (slot.index + 1).clamp(0, parent.length);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (!parent.contains(toc)) {
            parent.insert(index.clamp(0, parent.length), toc);
          }
        },
        undoFn: () => parent.remove(toc),
      ),
    );
    WordLink.ensureHeadingBookmarks(document);
    WordToc.refresh(toc, document);
    _relayoutTocPages();
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    notifyListeners();
  }

  /// Rebuilds TOC entries from headings, or only refreshes printed page numbers.
  void updateTableOfContents({bool pageNumbersOnly = false}) {
    if (!pageNumbersOnly) {
      WordToc.refreshAll(document);
    }
    _relayoutTocPages();
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    notifyListeners();
  }

  void _relayoutTocPages() {
    documentLaidOut = _engine.layout(document);
    if (WordToc.syncPageNumbers(document, documentLaidOut)) {
      documentLaidOut = _engine.layout(document);
    }
    _layoutComment();
  }

  /// followLink API.
  void followLink(WmlHyperlink link) {
    if (link.isInternal) {
      final int? index = WordLink.paragraphIndexForAnchor(
        document,
        link.anchor!,
      );
      if (index != null) {
        jumpToParagraph(index);
      }
      return;
    }
    onFollowExternalLink?.call(link);
  }

  /// insertHyperlink API.
  void insertHyperlink({
    required String text,
    WmlHyperlink? link,
    String? target,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlHyperlink? resolved =
        link ?? WmlHyperlink.fromTarget(target ?? '');
    if (resolved == null || (caret.isCollapsed && text.isEmpty)) {
      return;
    }
    final List<WmlParagraph> paragraphs = _paragraphs;
    final range = caret.normalizedRange;
    if (range.startPara < 0 || range.endPara >= paragraphs.length) {
      return;
    }
    final bool collapsed = caret.isCollapsed;
    final String previous = _activeParagraph.text;
    commands.beginBatch();
    if (collapsed) {
      final WmlParagraph paragraph = paragraphs[range.startPara];
      final int at = WmlRunEdit.normalizeRange(
        paragraph,
        range.startIdx,
        range.startIdx,
      ).start;
      final WmlRun run = WmlRun(
        text: text,
        properties: WmlRunEdit.propsAt(paragraph, at).copy(),
        hyperlink: resolved,
      );
      WordLink.applyLook(run);
      _commitParagraphInlines(
        paragraph,
        () => WmlRunEdit.insertRuns(paragraph, at, <WmlRun>[run]),
        textEdit: (start: at, end: at, insertedLength: text.length),
      );
      if (document.trackRevisions) {
        _recordRevision(
          kind: WmlRevisionKind.insert,
          paragraph: paragraph,
          paragraphIndex: range.startPara,
          start: at,
          end: at + text.length,
          text: text,
        );
      }
      caret.logicalIndex = at + text.length;
      caret.collapseSelection();
    } else {
      // A selection can cover several paragraphs. Preserve its text and apply
      // the link to each selected span, matching single-paragraph behavior.
      for (var index = range.startPara; index <= range.endPara; index++) {
        final WmlParagraph paragraph = paragraphs[index];
        final span = WmlRunEdit.normalizeRange(
          paragraph,
          index == range.startPara ? range.startIdx : 0,
          index == range.endPara ? range.endIdx : paragraph.text.length,
        );
        if (span.start == span.end) {
          continue;
        }
        _commitParagraphInlines(
          paragraph,
          () => WordLink.applyRange(paragraph, span.start, span.end, resolved),
        );
      }
    }
    commands.endBatch();
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _markLocalEdit(previousText: previous);
    _syncImeSelection();
    notifyListeners();
  }

  /// selectedComment API.
  WmlComment? get selectedComment => selectedCommentId == null
      ? null
      : WordComment.byId(document, selectedCommentId!);

  /// commentsAtCaret API.
  List<WmlComment> commentsAtCaret() {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty) {
      return const <WmlComment>[];
    }
    final WmlParagraph para =
        paras[documentCaret.paragraphIndex.clamp(0, paras.length - 1)];
    final List<int> ids = WordComment.idsAt(para, documentCaret.logicalIndex);
    return <WmlComment>[
      for (final int id in ids)
        if (WordComment.byId(document, id) != null)
          WordComment.byId(document, id)!,
    ];
  }

  /// selectComment API.
  void selectComment(int? id, {bool jump = false}) {
    if (id == null || (isEditingComment && selectedCommentId != id)) {
      _editingComment = false;
    }
    selectedCommentId = id;
    _layoutComment();
    if (jump && id != null) {
      jumpToComment(id);
      return;
    }
    notifyListeners();
  }

  /// jumpToComment API.
  void jumpToComment(int id) {
    _editingComment = false;
    selectedCommentId = id;
    final ({int paragraphIndex, int start, int end})? range =
        WordComment.rangeOf(document, WordComment.threadRootId(document, id));
    if (range != null) {
      documentCaret.paragraphIndex = range.paragraphIndex;
      documentCaret.logicalIndex = range.end;
      documentCaret.selectionAnchorParagraph = range.paragraphIndex;
      documentCaret.selectionAnchor = range.start;
      _revealParagraph(range.paragraphIndex);
    }
    _layoutComment();
    notifyListeners();
  }

  /// insertComment API.
  void insertComment({
    String text = '',
    String author = 'CrispOffice',
    String initials = 'CO',
    int? parentId,
    List<WmlParagraph>? paragraphs,
    List<WmlVisual>? visuals,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    _editingComment = false;
    final String body = text.trim();
    if (body.isEmpty &&
        (paragraphs == null || paragraphs.isEmpty) &&
        parentId == null) {
      // Anchor still needs a body so the pane can edit it.
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty) {
      return;
    }
    int startPara;
    int startIdx;
    int endPara;
    int endIdx;
    if (parentId != null) {
      startPara = caret.paragraphIndex.clamp(0, paras.length - 1);
      startIdx = 0;
      endPara = startPara;
      endIdx = 0;
    } else if (caret.isCollapsed) {
      startPara = caret.paragraphIndex.clamp(0, paras.length - 1);
      startIdx = 0;
      endPara = startPara;
      endIdx = paras[startPara].text.length;
    } else {
      final ({int startPara, int startIdx, int endPara, int endIdx}) range =
          caret.normalizedRange;
      startPara = range.startPara;
      startIdx = range.startIdx;
      endPara = range.endPara;
      endIdx = range.endIdx;
    }
    final Map<int, List<WmlInline>> snapshots = <int, List<WmlInline>>{
      for (int p = startPara; p <= endPara; p++) p: _cloneInlines(paras[p]),
    };
    final List<WmlComment> previous = List<WmlComment>.of(document.comments);
    final int id = WordComment.nextId(document);
    final WmlComment created = WmlComment(
      id: id,
      author: author,
      initials: initials,
      dateIso: DateTime.now().toUtc().toIso8601String(),
      text: body.isEmpty ? (parentId == null ? '' : '') : body,
      paragraphs: paragraphs,
      visuals: visuals,
      parentId: parentId,
    );
    if (created.text.isEmpty && created.visuals.isEmpty) {
      created.text = parentId == null ? ' ' : ' ';
      created.paragraphs.first.inlines.whereType<WmlRun>().first.text = '';
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          document.comments
            ..clear()
            ..addAll(<WmlComment>[...previous, created]);
          for (final MapEntry<int, List<WmlInline>> entry
              in snapshots.entries) {
            paras[entry.key].inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(entry.value));
          }
          if (parentId == null) {
            WordComment.applyDocumentRange(
              document,
              startPara: startPara,
              startIdx: startIdx,
              endPara: endPara,
              endIdx: endIdx,
              id: id,
            );
          }
          selectedCommentId = id;
        },
        undoFn: () {
          document.comments
            ..clear()
            ..addAll(previous);
          for (final MapEntry<int, List<WmlInline>> entry
              in snapshots.entries) {
            paras[entry.key].inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(entry.value));
          }
          if (selectedCommentId == id) {
            selectedCommentId = parentId;
          }
        },
      ),
    );
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    if (parentId == null) {
      beginCommentEdit(id);
      commentCaret
        ..paragraphIndex = 0
        ..logicalIndex = selectedComment!.paragraphs.first.text.length
        ..collapseSelection();
      notifyListeners();
      return;
    }
    notifyListeners();
  }

  /// replyToComment API.
  void replyToComment(
    int parentId, {
    required String text,
    String author = 'CrispOffice',
    String initials = 'CO',
  }) {
    final String body = text.trim();
    if (body.isEmpty) {
      return;
    }
    insertComment(
      text: body,
      author: author,
      initials: initials,
      parentId: WordComment.threadRootId(document, parentId),
    );
  }

  /// setCommentResolved API.
  void setCommentResolved(int id, bool resolved) {
    final int root = WordComment.threadRootId(document, id);
    final WmlComment? comment = WordComment.byId(document, root);
    if (comment == null || !config.allowsMutation) {
      return;
    }
    final bool before = comment.resolved;
    commands.commit(
      _CallbackCommand(
        executeFn: () => comment.resolved = resolved,
        undoFn: () => comment.resolved = before,
      ),
    );
    selectedCommentId = root;
    notifyListeners();
  }

  /// applyCommentRunFormat API.
  void applyCommentRunFormat(int id, void Function(WmlRunProps props) update) {
    if (WordComment.byId(document, id) == null || !config.allowsMutation) {
      return;
    }
    beginCommentEdit(id);
    applyRunFormat(update);
  }

  /// insertCommentVisual API.
  void insertCommentVisual(int id, OfficeVisual visual) {
    final WmlComment? comment = WordComment.byId(document, id);
    if (comment == null || !config.allowsMutation) {
      return;
    }
    final WmlVisual block = WmlVisual(visual: visual.copy());
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (!comment.visuals.contains(block)) {
            comment.visuals.add(block);
          }
        },
        undoFn: () => comment.visuals.remove(block),
      ),
    );
    selectedCommentId = id;
    _layoutComment();
    notifyListeners();
  }

  /// removeCommentVisual API.
  void removeCommentVisual(int id, WmlVisual visual) {
    final WmlComment? comment = WordComment.byId(document, id);
    if (comment == null || !config.allowsMutation) {
      return;
    }
    final int index = comment.visuals.indexOf(visual);
    if (index < 0) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => comment.visuals.remove(visual),
        undoFn: () {
          if (!comment.visuals.contains(visual)) {
            comment.visuals.insert(
              index.clamp(0, comment.visuals.length),
              visual,
            );
          }
        },
      ),
    );
    _layoutComment();
    notifyListeners();
  }

  /// updateComment API.
  void updateComment(
    int id, {
    String? text,
    String? author,
    String? initials,
    List<WmlParagraph>? paragraphs,
  }) {
    final WmlComment? comment = WordComment.byId(document, id);
    if (comment == null || !config.allowsMutation) {
      return;
    }
    // Keep paragraph identities in both states so earlier text/format commands
    // still target the right objects when a replacement is undone.
    final List<WmlParagraph> before = List<WmlParagraph>.of(comment.paragraphs);
    final List<WmlParagraph>? after = paragraphs != null
        ? <WmlParagraph>[for (final p in paragraphs) WmlClone.paragraph(p)]
        : text != null
        ? (comment.copy()..text = text).paragraphs
        : null;
    final String beforeAuthor = comment.author;
    final String beforeInitials = comment.initials;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (after != null) {
            comment.paragraphs
              ..clear()
              ..addAll(after);
          }
          comment.author = author ?? beforeAuthor;
          comment.initials = initials ?? beforeInitials;
        },
        undoFn: () {
          comment.paragraphs
            ..clear()
            ..addAll(before);
          comment.author = beforeAuthor;
          comment.initials = beforeInitials;
        },
      ),
    );
    selectedCommentId = id;
    _layoutComment();
    notifyListeners();
  }

  /// deleteComment API.
  void deleteComment(int id) {
    if (!config.allowsMutation) {
      return;
    }
    final List<WmlParagraph> body = document.paragraphs.toList();
    final Map<WmlParagraph, List<WmlInline>> snapshots =
        <WmlParagraph, List<WmlInline>>{
          for (final WmlParagraph paragraph in body)
            paragraph: _cloneInlines(paragraph),
        };
    final List<WmlComment> previous = List<WmlComment>.of(document.comments);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          WordComment.removeId(document, id);
          if (selectedCommentId == id) {
            selectedCommentId = null;
          }
        },
        undoFn: () {
          document.comments
            ..clear()
            ..addAll(previous);
          for (final MapEntry<WmlParagraph, List<WmlInline>> entry
              in snapshots.entries) {
            entry.key.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(entry.value));
          }
          selectedCommentId = id;
        },
      ),
    );
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    notifyListeners();
  }

  /// stepComment API.
  void stepComment(int delta) {
    if (document.comments.isEmpty) {
      return;
    }
    final List<WmlComment> comments = WordComment.roots(document);
    if (comments.isEmpty) {
      return;
    }
    final int selectedRoot = selectedCommentId == null
        ? comments.first.id
        : WordComment.threadRootId(document, selectedCommentId!);
    if (selectedCommentId == null) {
      jumpToComment(delta >= 0 ? comments.first.id : comments.last.id);
      return;
    }
    var index = 0;
    for (int i = 0; i < comments.length; i++) {
      if (comments[i].id == selectedRoot) {
        index = i;
        break;
      }
    }
    final int next = (index + delta) % comments.length;
    jumpToComment(comments[next < 0 ? next + comments.length : next].id);
  }

  /// jumpToParagraph API.
  void jumpToParagraph(int index) {
    clearNoteEditingTarget();
    _editingComment = false;
    selectedVisual = null;
    selectedEquation = null;
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty) {
      return;
    }
    documentCaret.paragraphIndex = index.clamp(0, paras.length - 1);
    documentCaret.logicalIndex = 0;
    documentCaret.collapseSelection();
    _revealParagraph(documentCaret.paragraphIndex);
    notifyListeners();
  }

  ({List<WmlBlock> parent, int index})? _hostSlotOf(WmlParagraph para) {
    final List<WmlParagraph>? story = isEditingComment
        ? selectedComment?.paragraphs
        : isEditingHeaderFooter
        ? _ensureHeaderFooterParagraphs()
        : null;
    if (story != null) {
      final index = story.indexOf(para);
      if (index >= 0) return (parent: story, index: index);
    }
    final exact = WordTree.locate(document, para);
    if (exact != null) return exact;
    // Generated TOC paragraphs are owned by the TOC, not an editable child
    // list. Inserting adjacent blocks uses that actual TOC position.
    for (final blocks in <List<WmlBlock>>[
      for (final section in document.sections) section.blocks,
      for (final note in [...document.footnotes, ...document.endnotes])
        note.blocks,
    ]) {
      for (final block in WordTree.descendants(blocks)) {
        if (block is WmlToc && WordToc.ownsParagraph(block, para)) {
          return WordTree.locate(document, block);
        }
      }
    }
    return null;
  }

  ({List<WmlBlock> parent, int index})? _topLevelInsertSlot() =>
      WordTree.flowHost(document, _activeParagraph);

  void _revealParagraph(int index) {
    const double pointsToPixels = 96 / 72;
    final double scale = viewport.scale * pointsToPixels;
    for (final LaidOutPage page in laidOut.pages) {
      for (final LaidOutLine line in page.lines) {
        if (line.paragraphIndex != index) {
          continue;
        }
        final double top =
            laidOut.pageStackTop(page.index, scale) + line.y * scale;
        final double nextY = top - 48;
        viewport.origin = Offset(viewport.origin.dx, nextY < 0 ? 0 : nextY);
        return;
      }
    }
  }

  /// Re-lays out then applies the same Flutter metrics used on screen.
  void fitPaintMetrics({String? themeFamily}) {
    relayout();
    _fitLaidOut(documentLaidOut, document.paragraphs.toList(), themeFamily);
    if (commentLaidOut != null && selectedComment != null) {
      _fitLaidOut(commentLaidOut!, selectedComment!.paragraphs, themeFamily);
    }
  }

  void _fitLaidOut(
    LaidOutDocument laid,
    List<WmlParagraph> paras,
    String? themeFamily,
  ) {
    // Fitting moves glyphs in place; such lines are no longer engine output.
    // Keep the engine values so the next local edit can put them back and
    // relayout incrementally instead of discarding the layout state.
    if (laid.supportsIncrementalReuse && _FittedLines.of(laid) == null) {
      _FittedLines.capture(laid);
    } else if (_FittedLines.of(laid) == null) {
      laid.discardIncrementalState();
    }
    void fit(LaidOutLine line) {
      final String text =
          line.sourceText ??
          (paras.isEmpty
              ? ''
              : paras[line.paragraphIndex.clamp(0, paras.length - 1)].text);
      PaintRunText.fitLine(line, text, themeFamily: themeFamily);
    }

    for (final LaidOutPage page in laid.pages) {
      for (final LaidOutLine line in page.lines) {
        fit(line);
      }
      for (final LaidOutLine line in page.header) {
        fit(line);
      }
      for (final LaidOutLine line in page.footer) {
        fit(line);
      }
    }
  }

  /// attachInput API.
  void attachInput() {
    if (!config.allowsMutation) {
      return;
    }
    // Restoring focus after host chrome must reconnect the current IME
    // draft. Rebuilding it would silently finish an active composition.
    final preserveComposition = _canResumeImeComposition;
    input.attach(multiline: true);
    if (!preserveComposition) _writeImeValue();
  }

  bool get _canResumeImeComposition {
    final value = input.value;
    if (!input.composing.isValid ||
        input.composing.isCollapsed ||
        input.composing != value.composing ||
        value.composing.end > value.text.length ||
        !value.selection.isValid ||
        value.selection.end > value.text.length ||
        _imeValueTarget != _imeEditingTarget) {
      return false;
    }
    final text = selectedEquation == null
        ? _activeParagraph.text
        : equationEditingText();
    return value.text == text;
  }

  Object get _imeEditingTarget => (
    document: document,
    paragraph: _activeParagraph,
    caret: caret,
    paragraphIndex: caret.paragraphIndex,
    offset: caret.logicalIndex,
    anchorParagraph: caret.selectionAnchorParagraph,
    anchorOffset: caret.selectionAnchor,
    equation: selectedEquation,
    equationSlot: selectedEquation == null ? null : equationSlot,
    equationOffset: selectedEquation == null ? null : equationCaret,
  );

  @override
  /// detachInput API.
  void detachInput() {
    input.detach();
  }

  /// moveCaret API.
  void moveCaret(int delta, {bool extend = false}) {
    if (!config.allowsSelection) {
      return;
    }
    if (selectedVisual != null && !extend) {
      _leaveSelectedVisual(forward: delta > 0);
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    if (!extend && _selectNeighborVisual(delta, requireEdge: true)) {
      return;
    }
    var remaining = delta;
    while (remaining != 0) {
      caret.paragraphIndex = caret.paragraphIndex.clamp(0, paras.length - 1);
      final String text = paras[caret.paragraphIndex].text;
      if (remaining > 0) {
        final int room = text.length - caret.logicalIndex;
        if (remaining <= room) {
          caret.logicalIndex += remaining;
          remaining = 0;
        } else {
          final next = _nextNavigationParagraph(paras, caret.paragraphIndex, 1);
          if (next == null) {
            caret.logicalIndex = text.length;
            remaining = 0;
          } else {
            remaining -= room + 1;
            caret.paragraphIndex = next;
            caret.logicalIndex = 0;
          }
        }
      } else if (caret.logicalIndex + remaining >= 0) {
        caret.logicalIndex += remaining;
        remaining = 0;
      } else {
        final previous = _nextNavigationParagraph(
          paras,
          caret.paragraphIndex,
          -1,
        );
        if (previous == null) {
          caret.logicalIndex = 0;
          remaining = 0;
        } else {
          remaining += caret.logicalIndex + 1;
          caret.paragraphIndex = previous;
          caret.logicalIndex = paras[previous].text.length;
        }
      }
    }
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
    selectedVisual = null;
    _stickyCaretX = null;
    _syncImeSelection();
    notifyListeners();
  }

  /// Moves the caret one visual step (physical left/right), not logical UTF-16.
  void moveCaretVisual({required bool toRight, bool extend = false}) {
    if (!config.allowsSelection) {
      return;
    }
    if (selectedEquation != null) {
      moveEquationArrow(dx: toRight ? 1 : -1, dy: 0);
      return;
    }
    _stickyCaretX = null;
    if (selectedVisual != null && !extend) {
      _leaveSelectedVisual(forward: toRight);
      return;
    }
    final List<LaidOutLine> lines = _contentLines();
    final int index = _lineIndexOfCaret(lines);
    if (index < 0) {
      moveCaret(toRight ? 1 : -1, extend: extend);
      return;
    }
    if (!extend && _selectNeighborVisual(toRight ? 1 : -1, requireEdge: true)) {
      return;
    }
    final LaidOutLine line = lines[index];
    if (line.glyphs.isEmpty) {
      _crossLaidOutLine(lines, index, toRight: toRight, extend: extend);
      return;
    }
    final int? next = CaretEngine.visualNeighbor(
      line,
      caret.logicalIndex,
      toRight: toRight,
    );
    if (next != null) {
      caret.paragraphIndex = line.paragraphIndex;
      caret.logicalIndex = next;
    } else {
      _crossLaidOutLine(lines, index, toRight: toRight, extend: extend);
      return;
    }
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
    selectedVisual = null;
    _syncImeSelection();
    notifyListeners();
  }

  /// Moves the caret to the previous or next laid-out line.
  void moveCaretLine(int delta, {bool extend = false}) {
    if (!config.allowsSelection || delta == 0) {
      return;
    }
    if (selectedEquation != null) {
      moveEquationArrow(dx: 0, dy: delta);
      return;
    }
    if (selectedVisual != null && !extend) {
      _leaveSelectedVisual(forward: delta > 0);
      return;
    }
    final List<LaidOutLine> lines = _contentLines();
    final int index = _lineIndexOfCaret(lines);
    if (index < 0) {
      moveParagraph(delta, extend: extend);
      return;
    }
    final int nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= lines.length) {
      return;
    }
    final LaidOutLine current = lines[index];
    final LaidOutLine next = lines[nextIndex];
    if (!extend) {
      final WmlVisual? between = _visualBetweenLines(current, next);
      if (between != null) {
        selectedVisual = between;
        notifyListeners();
        return;
      }
    }
    final double x = _stickyCaretX ?? _caretXOnLine(current);
    _stickyCaretX = x;
    caret.paragraphIndex = next.paragraphIndex;
    caret.logicalIndex = _logicalAtX(next, x);
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
    selectedVisual = null;
    _syncImeSelection();
    notifyListeners();
  }

  /// moveParagraph API.
  void moveParagraph(int delta, {bool extend = false}) {
    if (!config.allowsSelection) {
      return;
    }
    if (selectedVisual != null && !extend) {
      _leaveSelectedVisual(forward: delta > 0);
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    if (!extend && _selectNeighborVisual(delta, requireEdge: false)) {
      return;
    }
    selectedVisual = null;
    caret.paragraphIndex = caret.paragraphIndex.clamp(0, paras.length - 1);
    for (var remaining = delta.abs(); remaining > 0; remaining--) {
      final next = _nextNavigationParagraph(
        paras,
        caret.paragraphIndex,
        delta.sign,
      );
      if (next == null) break;
      caret.paragraphIndex = next;
    }
    caret.logicalIndex = caret.logicalIndex.clamp(
      0,
      paras[caret.paragraphIndex].text.length,
    );
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
    _stickyCaretX = null;
    attachInput();
    notifyListeners();
  }

  /// selectAll API.
  @override
  void selectAll() {
    if (!config.allowsSelection) {
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    selectedVisual = null;
    caret
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 0
      ..paragraphIndex = paras.length - 1
      ..logicalIndex = paras.last.text.length;
    caret.resetBlink();
    _syncImeSelection();
    notifyListeners();
  }

  /// selectWordAtCaret API.
  void selectWordAtCaret() {
    if (!config.allowsSelection) {
      return;
    }
    caret.selectWord(_activeParagraph.text, caret.logicalIndex);
    _syncImeSelection();
    notifyListeners();
  }

  /// selectParagraphAtCaret API.
  void selectParagraphAtCaret() {
    if (!config.allowsSelection) {
      return;
    }
    caret.selectParagraph(_activeParagraph.text);
    _syncImeSelection();
    notifyListeners();
  }

  /// tableAtCaret API.
  ({WmlTable table, int row, int col})? get tableAtCaret {
    if (isEditingComment || isEditingHeaderFooter) {
      return null;
    }
    return WordTable.locationOfIndex(document, caret.paragraphIndex);
  }

  /// isInTable API.
  bool get isInTable => tableAtCaret != null;

  /// tableCellRange API.
  ({WmlTable table, int r0, int g0, int r1, int g1})? get tableCellRange {
    if (isEditingComment) {
      return null;
    }
    if (caret.isCollapsed) {
      final ({WmlTable table, int row, int col})? loc = tableAtCaret;
      if (loc == null) {
        return null;
      }
      final ({int r0, int g0, int r1, int g1})? rect = WordTable.gridRect(
        loc.table,
        loc.row,
        loc.col,
        loc.row,
        loc.col,
      );
      if (rect == null) {
        return null;
      }
      return (
        table: loc.table,
        r0: rect.r0,
        g0: rect.g0,
        r1: rect.r1,
        g1: rect.g1,
      );
    }
    final ({int startPara, int startIdx, int endPara, int endIdx}) range =
        caret.normalizedRange;
    final ({WmlTable table, int row, int col})? a = WordTable.locationOfIndex(
      document,
      range.startPara,
    );
    final ({WmlTable table, int row, int col})? b = WordTable.locationOfIndex(
      document,
      range.endPara,
    );
    if (a == null || b == null || !identical(a.table, b.table)) {
      return null;
    }
    final ({int r0, int g0, int r1, int g1})? rect = WordTable.gridRect(
      a.table,
      a.row,
      a.col,
      b.row,
      b.col,
    );
    if (rect == null) {
      return null;
    }
    return (table: a.table, r0: rect.r0, g0: rect.g0, r1: rect.r1, g1: rect.g1);
  }

  /// canMergeTableCells API.
  bool get canMergeTableCells {
    final ({WmlTable table, int r0, int g0, int r1, int g1})? range =
        tableCellRange;
    return range != null &&
        WordTable.canMerge(range.table, range.r0, range.g0, range.r1, range.g1);
  }

  /// canUnmergeTableCells API.
  bool get canUnmergeTableCells {
    final ({WmlTable table, int row, int col})? loc = tableAtCaret;
    return loc != null && WordTable.canUnmerge(loc.table, loc.row, loc.col);
  }

  /// mergeTableCells API.
  void mergeTableCells() {
    final ({WmlTable table, int r0, int g0, int r1, int g1})? range =
        tableCellRange;
    if (range == null ||
        !config.allowsMutation ||
        !WordTable.canMerge(
          range.table,
          range.r0,
          range.g0,
          range.r1,
          range.g1,
        )) {
      return;
    }
    _mutateWordTable(
      range.table,
      () =>
          WordTable.merge(range.table, range.r0, range.g0, range.r1, range.g1),
      (WmlTable table) {
        final int col =
            WordTable.cellIndexAtGrid(table.rows[range.r0], range.g0) ?? 0;
        _placeCaretInTable(table, range.r0, col);
        selectedTable = null;
      },
    );
  }

  /// unmergeTableCells API.
  void unmergeTableCells() {
    final ({WmlTable table, int row, int col})? loc = tableAtCaret;
    if (loc == null ||
        !config.allowsMutation ||
        !WordTable.canUnmerge(loc.table, loc.row, loc.col)) {
      return;
    }
    _mutateWordTable(
      loc.table,
      () => WordTable.unmerge(loc.table, loc.row, loc.col),
      (WmlTable table) {
        _placeCaretInTable(table, loc.row, loc.col);
        selectedTable = null;
      },
    );
  }

  WordTableHistoryState? _tableResizeSnap;

  /// beginTableResize API.
  void beginTableResize(WmlTable table) {
    if (!config.allowsMutation || WordTable.hasRowOmissions(table)) {
      _tableResizeSnap = null;
      return;
    }
    _tableResizeSnap = WordTableHistoryState.capture(table);
  }

  /// previewTableColumnWidth API.
  void previewTableColumnWidth(WmlTable table, int col, double width) {
    if (!config.allowsMutation || WordTable.hasRowOmissions(table)) {
      return;
    }
    while (table.grid.length <= col) {
      table.grid.add(120);
    }
    table.grid[col] = width.clamp(24, 900);
    for (final WmlTableRow row in table.rows) {
      final int? i = WordTable.cellIndexAtGrid(row, col);
      if (i != null && WordTable.spanOf(row.cells[i]) == 1) {
        row.cells[i].width = table.grid[col];
      }
    }
    relayout();
    notifyListeners();
  }

  /// previewTableRowHeight API.
  void previewTableRowHeight(WmlTable table, int row, double height) {
    if (!config.allowsMutation ||
        WordTable.hasRowOmissions(table) ||
        row < 0 ||
        row >= table.rows.length) {
      return;
    }
    table.rows[row].height = height.clamp(16, 480);
    relayout();
    notifyListeners();
  }

  /// commitTableResize API.
  void commitTableResize(WmlTable table) {
    final WordTableHistoryState? snap = _tableResizeSnap;
    _tableResizeSnap = null;
    if (snap == null ||
        !identical(snap.table, table) ||
        !config.allowsMutation ||
        WordTable.hasRowOmissions(table)) {
      return;
    }
    final WordTableHistoryState now = WordTableHistoryState.capture(table);
    commands.commit(
      _CallbackCommand(executeFn: now.restore, undoFn: snap.restore),
    );
    relayout();
    notifyListeners();
  }

  /// insertTableRow API.
  void insertTableRow({required bool after, WmlTable? table, int? row}) {
    final ({WmlTable table, int row, int col})? loc =
        table != null && row != null
        ? (table: table, row: row, col: 0)
        : tableAtCaret;
    if (loc == null) {
      return;
    }
    insertTableRowAt(loc.table, after ? loc.row + 1 : loc.row);
  }

  /// insertTableRowAt API.
  void insertTableRowAt(WmlTable table, int index) {
    _mutateWordTable(table, () => WordTable.insertRow(table, index), (
      WmlTable t,
    ) {
      _placeCaretInTable(t, index.clamp(0, t.rows.length - 1), 0);
    });
  }

  /// insertTableColumn API.
  void insertTableColumn({required bool after, WmlTable? table, int? col}) {
    final ({WmlTable table, int row, int col})? loc =
        table != null && col != null
        ? (table: table, row: 0, col: col)
        : tableAtCaret;
    if (loc == null) {
      return;
    }
    insertTableColumnAt(loc.table, after ? loc.col + 1 : loc.col);
  }

  /// insertTableColumnAt API.
  void insertTableColumnAt(WmlTable table, int index) {
    _mutateWordTable(
      table,
      () {
        WordTable.insertColumn(table, index);
        WordTable.constrainToWidth(table, _tableContentWidth);
      },
      (WmlTable t) {
        final ({WmlTable table, int row, int col})? loc = tableAtCaret;
        _placeCaretInTable(
          t,
          loc?.row ?? 0,
          index.clamp(0, WordTable.columnCount(t) - 1),
        );
      },
    );
  }

  double get _tableContentWidth {
    if (document.sections.isEmpty) {
      return 451;
    }
    return document.sections.first.contentWidth;
  }

  /// selectedTable API.
  WmlTable? selectedTable;

  /// selectedTableBand API.
  ({WmlTable table, bool column, int from, int to})? selectedTableBand;

  /// selectTable API.
  void selectTable(WmlTable? table) {
    selectedTable = table;
    selectedTableBand = null;
    if (table != null) {
      selectedVisual = null;
      selectedEquation = null;
      _selectTableRange(table);
    }
    notifyListeners();
  }

  /// autoFitTable API.
  void autoFitTable(WordTableAutoFit mode, {WmlTable? table}) {
    final WmlTable? target = table ?? selectedTable ?? tableAtCaret?.table;
    if (target == null) {
      return;
    }
    _mutateWordTable(
      target,
      () => WordTable.autoFit(target, mode, contentWidth: _tableContentWidth),
      (_) {},
    );
  }

  /// deleteTable API.
  void deleteTable({WmlTable? table}) {
    final WmlTable? target = table ?? selectedTable ?? tableAtCaret?.table;
    if (target == null || !config.allowsMutation) {
      return;
    }
    final List<WmlBlock>? parent = _parentBlocksOfBlock(target);
    if (parent == null) {
      return;
    }
    final int at = parent.indexOf(target);
    if (at < 0) {
      return;
    }
    final List<WmlBlock> host = parent;
    final WmlTable snap = WordTable.snapshot(target);
    // A bookmark cut by the table keeps its outside endpoint and is clamped
    // to where the table was; ranges wholly inside the table go with it.
    final List<WmlBookmarkBoundary> removedMarkers =
        WordBookmarks.boundariesInBlocks(<WmlBlock>[target]);
    WmlParagraph? markerAnchor;
    var anchorAtStart = false;
    List<WmlInline>? anchorSnap;
    if (removedMarkers.isNotEmpty) {
      final List<WmlParagraph> paras = document.paragraphs.toList();
      final List<WmlParagraph> owned = WmlClone.paragraphsOf(target);
      final int first = owned.isEmpty ? -1 : paras.indexOf(owned.first);
      final int last = owned.isEmpty ? -1 : paras.indexOf(owned.last);
      if (first >= 0 && last + 1 < paras.length) {
        markerAnchor = paras[last + 1];
        anchorAtStart = true;
      } else if (first > 0) {
        markerAnchor = paras[first - 1];
      }
      if (markerAnchor != null) anchorSnap = _cloneInlines(markerAnchor);
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          host.remove(target);
          WordBookmarks.clampRemoved(
            document,
            removedMarkers,
            anchor: markerAnchor,
            atStart: anchorAtStart,
          );
          selectedTable = null;
          selectedTableBand = null;
          _ensureBodyHasParagraph();
        },
        undoFn: () {
          if (!host.contains(target)) {
            host.insert(at.clamp(0, host.length), target);
            WordTable.restore(target, snap);
          }
          final List<WmlInline>? inlines = anchorSnap;
          final WmlParagraph? anchor = markerAnchor;
          if (anchor != null && inlines != null) {
            anchor.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(inlines));
          }
        },
      ),
    );
    _placeCaretAfterBlockRemoval(host, at);
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _syncImeSelection();
    notifyListeners();
  }

  void _placeCaretAfterBlockRemoval(List<WmlBlock> host, int wasAt) {
    WmlParagraph? findPara(WmlBlock block) {
      final List<WmlParagraph> owned = WmlClone.paragraphsOf(block);
      return owned.isEmpty ? null : owned.first;
    }

    WmlParagraph? para;
    var atStart = true;
    if (wasAt < host.length) {
      para = findPara(host[wasAt]);
    }
    if (para == null && wasAt > 0) {
      final List<WmlParagraph> owned = WmlClone.paragraphsOf(host[wasAt - 1]);
      if (owned.isNotEmpty) {
        para = owned.last;
        atStart = false;
      }
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (para == null) {
      if (paras.isEmpty) {
        caret.paragraphIndex = 0;
        caret.logicalIndex = 0;
        caret.collapseSelection();
        return;
      }
      para = paras.first;
    }
    final int index = paras.indexOf(para);
    caret.paragraphIndex = index < 0 ? 0 : index;
    caret.logicalIndex = atStart ? 0 : para.text.length;
    caret.collapseSelection();
  }

  void _selectTableRange(WmlTable table) {
    WmlParagraph? first;
    WmlParagraph? last;
    void walk(List<WmlBlock> blocks) {
      for (final WmlBlock block in blocks) {
        if (block is WmlParagraph) {
          first ??= block;
          last = block;
        } else if (block is WmlTable) {
          for (final WmlTableRow row in block.rows) {
            for (final WmlTableCell cell in row.cells) {
              walk(cell.blocks);
            }
          }
        }
      }
    }

    for (final WmlTableRow row in table.rows) {
      for (final WmlTableCell cell in row.cells) {
        walk(cell.blocks);
      }
    }
    if (first == null || last == null) {
      return;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final int start = paras.indexOf(first!);
    final int end = paras.indexOf(last!);
    if (start < 0 || end < 0) {
      return;
    }
    caret
      ..selectionAnchorParagraph = start
      ..selectionAnchor = 0
      ..paragraphIndex = end
      ..logicalIndex = last!.text.length;
  }

  /// selectTableBand API.
  void selectTableBand(
    WmlTable table, {
    required bool column,
    required int from,
    required int to,
  }) {
    if (!config.allowsSelection) {
      return;
    }
    final int a = from < to ? from : to;
    final int b = from > to ? from : to;
    WmlParagraph? first;
    WmlParagraph? last;
    void take(WmlTableCell cell) {
      void walk(List<WmlBlock> blocks) {
        for (final WmlBlock block in blocks) {
          if (block is WmlParagraph) {
            first ??= block;
            last = block;
          } else if (block is WmlTable) {
            for (final WmlTableRow nestedRow in block.rows) {
              for (final WmlTableCell nested in nestedRow.cells) {
                walk(nested.blocks);
              }
            }
          }
        }
      }

      walk(cell.blocks);
    }

    if (column) {
      for (final WmlTableRow row in table.rows) {
        var grid = 0;
        for (final WmlTableCell cell in row.cells) {
          final int span = WordTable.spanOf(cell);
          if (grid <= b && grid + span - 1 >= a) {
            take(cell);
          }
          grid += span;
        }
      }
    } else {
      for (int r = a; r <= b && r < table.rows.length; r++) {
        for (final WmlTableCell cell in table.rows[r].cells) {
          take(cell);
        }
      }
    }
    if (first == null || last == null) {
      return;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final int start = paras.indexOf(first!);
    final int end = paras.indexOf(last!);
    if (start < 0 || end < 0) {
      return;
    }
    selectedTable = null;
    selectedTableBand = (table: table, column: column, from: a, to: b);
    selectedVisual = null;
    selectedEquation = null;
    caret
      ..selectionAnchorParagraph = start
      ..selectionAnchor = 0
      ..paragraphIndex = end
      ..logicalIndex = last!.text.length;
    notifyListeners();
  }

  /// deleteTableRow API.
  void deleteTableRow({WmlTable? table, int? row}) {
    if (table == null &&
        row == null &&
        selectedTableBand != null &&
        !selectedTableBand!.column) {
      deleteSelectedTableBand();
      return;
    }
    final ({WmlTable table, int row, int col})? loc =
        table != null && row != null
        ? (table: table, row: row, col: 0)
        : tableAtCaret;
    if (loc == null || loc.table.rows.length <= 1) {
      return;
    }
    _mutateWordTable(loc.table, () => WordTable.deleteRow(loc.table, loc.row), (
      WmlTable t,
    ) {
      _placeCaretInTable(t, loc.row.clamp(0, t.rows.length - 1), loc.col);
    });
  }

  /// deleteTableColumn API.
  void deleteTableColumn({WmlTable? table, int? col}) {
    if (table == null &&
        col == null &&
        selectedTableBand != null &&
        selectedTableBand!.column) {
      deleteSelectedTableBand();
      return;
    }
    final ({WmlTable table, int row, int col})? loc =
        table != null && col != null
        ? (table: table, row: 0, col: col)
        : tableAtCaret;
    if (loc == null || WordTable.columnCount(loc.table) <= 1) {
      return;
    }
    _mutateWordTable(
      loc.table,
      () => WordTable.deleteColumn(loc.table, loc.col),
      (WmlTable t) {
        _placeCaretInTable(
          t,
          loc.row,
          loc.col.clamp(0, WordTable.columnCount(t) - 1),
        );
      },
    );
  }

  /// Deletes the selected full table row(s) or column(s).
  void deleteSelectedTableBand() {
    final ({WmlTable table, bool column, int from, int to})? band =
        selectedTableBand;
    if (band == null || !config.allowsMutation) {
      return;
    }
    final WmlTable table = band.table;
    if (WordTable.hasRowOmissions(table)) return;
    final int a = band.from < band.to ? band.from : band.to;
    final int b = band.from > band.to ? band.from : band.to;
    if (band.column) {
      final int cols = WordTable.columnCount(table);
      if (cols <= 0 || (a <= 0 && b >= cols - 1)) {
        deleteTable(table: table);
        return;
      }
      _mutateWordTable(
        table,
        () {
          for (int i = b; i >= a; i--) {
            WordTable.deleteColumn(table, i);
          }
          selectedTableBand = null;
        },
        (WmlTable t) {
          _placeCaretInTable(t, 0, a.clamp(0, WordTable.columnCount(t) - 1));
        },
      );
      return;
    }
    if (table.rows.isEmpty || (a <= 0 && b >= table.rows.length - 1)) {
      deleteTable(table: table);
      return;
    }
    _mutateWordTable(
      table,
      () {
        for (int i = b; i >= a && table.rows.length > 1; i--) {
          WordTable.deleteRow(table, i);
        }
        selectedTableBand = null;
      },
      (WmlTable t) {
        _placeCaretInTable(t, a.clamp(0, t.rows.length - 1), 0);
      },
    );
  }

  void _mutateWordTable(
    WmlTable table,
    void Function() mutate,
    void Function(WmlTable table) place,
  ) {
    if (!config.allowsMutation || WordTable.hasRowOmissions(table)) {
      return;
    }
    final WordTableHistoryState before = WordTableHistoryState.capture(table);
    WordTableHistoryState? after;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (after == null) {
            mutate();
            after = WordTableHistoryState.capture(table);
          } else {
            after!.restore();
          }
          place(table);
        },
        undoFn: before.restore,
      ),
    );
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _syncImeSelection();
    notifyListeners();
  }

  /// Moves the caret to the next (`forward`) or previous table cell.
  ///
  /// Traverses left-to-right within a row, then the next row. At the last
  /// cell, inserts a new row when mutation is allowed. Returns `false` when
  /// the caret is not inside a table.
  bool moveTableCell({required bool forward}) {
    final ({WmlTable table, int row, int col})? loc = tableAtCaret;
    if (loc == null) {
      return false;
    }
    final ({int row, int col})? next = _stepTableCell(
      loc.table,
      loc.row,
      loc.col,
      forward ? 1 : -1,
    );
    if (next == null) {
      if (forward && config.allowsMutation) {
        insertTableRowAt(loc.table, loc.table.rows.length);
        return true;
      }
      return true;
    }
    _placeCaretInTable(loc.table, next.row, next.col);
    selectedTable = null;
    selectedTableBand = null;
    notifyListeners();
    return true;
  }

  static ({int row, int col})? _stepTableCell(
    WmlTable table,
    int row,
    int col,
    int direction,
  ) {
    var r = row;
    var c = col;
    while (true) {
      c += direction;
      if (r < 0 || r >= table.rows.length) {
        return null;
      }
      if (c >= table.rows[r].cells.length) {
        r++;
        c = 0;
        if (r >= table.rows.length) {
          return null;
        }
      } else if (c < 0) {
        r--;
        if (r < 0) {
          return null;
        }
        c = table.rows[r].cells.length - 1;
      }
      if (table.rows[r].cells[c].vMerge != WmlVMerge.cont) {
        return (row: r, col: c);
      }
    }
  }

  void _placeCaretInTable(WmlTable table, int row, int col) {
    if (table.rows.isEmpty) {
      return;
    }
    final int r = row.clamp(0, table.rows.length - 1);
    final List<WmlTableCell> cells = table.rows[r].cells;
    if (cells.isEmpty) {
      return;
    }
    final int c = col.clamp(0, cells.length - 1);
    WmlParagraph? paragraph;
    for (final WmlBlock block in cells[c].blocks) {
      if (block is WmlParagraph) {
        paragraph = block;
        break;
      }
    }
    if (paragraph == null) {
      return;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final int index = paras.indexOf(paragraph);
    if (index < 0) {
      return;
    }
    caret.paragraphIndex = index;
    caret.logicalIndex = 0;
    caret.collapseSelection();
  }

  @override
  /// canCopy API.
  bool get canCopy =>
      selectedVisual != null ||
      (selectedFrame != null && !editingFrame) ||
      selectedTable != null ||
      !caret.isCollapsed;

  @override
  /// copyToClipboard API.
  Future<void> copyToClipboard() async {
    final OfficeClipboardPayload payload = _captureWordClipboard();
    if (payload.isEmpty) {
      return;
    }
    await OfficeClipboard.instance.write(payload);
  }

  @override
  /// cutToClipboard API.
  /// [isCurrent] can bind a contextual action to its original edit target while
  /// the system clipboard write is pending.
  Future<void> cutToClipboard({bool Function()? isCurrent}) async {
    if (!canCut || !(isCurrent?.call() ?? true)) {
      return;
    }
    await copyToClipboard();
    if (!(isCurrent?.call() ?? true)) {
      return;
    }
    if (selectedVisual != null) {
      deleteSelectedVisual();
      return;
    }
    if (selectedFrame != null && !editingFrame) {
      deleteSelectedFrame();
      return;
    }
    deleteSelectionOr(backward: true);
  }

  @override
  /// pasteFromClipboard API.
  /// [isCurrent] can bind a contextual action to its original edit target while
  /// the system clipboard read is pending.
  Future<void> pasteFromClipboard({
    OfficePasteMode mode = OfficePasteMode.keepSource,
    bool Function()? isCurrent,
  }) async {
    if (!canPaste || !(isCurrent?.call() ?? true)) {
      return;
    }
    final OfficeClipboardPayload payload = await OfficeClipboard.instance
        .read();
    if (!(isCurrent?.call() ?? true) || payload.isEmpty) {
      return;
    }
    if (payload.visual != null && selectedVisual == null && caret.isCollapsed) {
      _pasteWordVisual(payload.visual!);
      return;
    }
    if (mode == OfficePasteMode.keepSource && payload.hasWordBlocks) {
      _pasteWordBlocks(payload.wordBlocks);
      return;
    }
    if (mode == OfficePasteMode.keepSource && payload.hasRichText) {
      _pasteWordRich(payload.paragraphs);
      return;
    }
    _pasteWordPlain(payload.plain);
  }

  OfficeClipboardPayload _captureWordClipboard() {
    final WmlVisual? visual = selectedVisual;
    if (visual != null) {
      return OfficeClipboardPayload(
        kind: OfficeClipboardKind.visual,
        plain: visual.visual.title,
        visual: visual.visual.copy(),
      );
    }
    if (selectedTable != null) {
      final WmlTable clone = WmlClone.table(selectedTable!);
      return OfficeClipboardPayload(
        kind: OfficeClipboardKind.richText,
        plain: WmlClone.plainTextOf(<WmlBlock>[clone]),
        wordBlocks: <WmlBlock>[clone],
        paragraphs: _spansFromBlocks(<WmlBlock>[clone]),
      );
    }
    if (caret.isCollapsed) {
      return OfficeClipboardPayload.empty();
    }
    final List<WmlBlock> fragment = _captureWordFragment();
    if (fragment.isEmpty) {
      return OfficeClipboardPayload.empty();
    }
    return OfficeClipboardPayload(
      kind: OfficeClipboardKind.richText,
      plain: WmlClone.plainTextOf(fragment),
      wordBlocks: fragment,
      paragraphs: _spansFromBlocks(fragment),
    );
  }

  List<List<OfficeClipboardSpan>> _spansFromBlocks(List<WmlBlock> blocks) {
    return <List<OfficeClipboardSpan>>[
      for (final WmlBlock block in blocks)
        for (final WmlParagraph para in WmlClone.paragraphsOf(block))
          <OfficeClipboardSpan>[
            for (final WmlInline inline in para.inlines)
              if (inline is WmlRun)
                OfficeClipboardSpan(
                  text: inline.text,
                  props: inline.properties.copy(),
                ),
          ],
    ];
  }

  List<WmlBlock> _captureWordFragment() {
    if (isEditingComment || isEditingHeaderFooter) {
      return _captureSlicedCommentParagraphs();
    }
    if (_isEntireDocumentSelected()) {
      return <WmlBlock>[
        for (final WmlSection section in document.sections)
          for (final WmlBlock block in section.blocks) WmlClone.block(block),
      ];
    }
    return _captureStructuredFragment();
  }

  List<WmlBlock> _captureSlicedCommentParagraphs() {
    final List<WmlParagraph> paras = _paragraphs;
    final (:int startPara, :int startIdx, :int endPara, :int endIdx) =
        caret.normalizedRange;
    if (startPara < 0 || endPara >= paras.length) {
      return <WmlBlock>[];
    }
    return <WmlBlock>[
      for (int p = startPara; p <= endPara; p++)
        WmlClone.slicedParagraph(
          paras[p],
          p == startPara ? startIdx : 0,
          p == endPara ? endIdx : paras[p].text.length,
        ),
    ];
  }

  List<WmlBlock> _captureStructuredFragment() {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final (:int startPara, :int startIdx, :int endPara, :int endIdx) =
        caret.normalizedRange;
    if (startPara < 0 || endPara >= paras.length) {
      return <WmlBlock>[];
    }
    final List<WmlBlock> out = <WmlBlock>[];
    for (final WmlSection section in document.sections) {
      for (final WmlBlock block in section.blocks) {
        switch (_coverageOf(
          block,
          paras,
          startPara,
          startIdx,
          endPara,
          endIdx,
        )) {
          case _WordBlockCover.none:
            break;
          case _WordBlockCover.full:
            out.add(WmlClone.block(block));
          case _WordBlockCover.partial:
            if (block is WmlParagraph) {
              final int index = paras.indexOf(block);
              out.add(
                WmlClone.slicedParagraph(
                  block,
                  index == startPara ? startIdx : 0,
                  index == endPara ? endIdx : block.text.length,
                ),
              );
            } else if (block is WmlTable) {
              if (_selectionInsideTableOnly(block, startPara, endPara, paras)) {
                out.addAll(
                  _slicedParagraphsInRange(
                    paras,
                    startPara,
                    startIdx,
                    endPara,
                    endIdx,
                  ),
                );
              } else {
                out.add(WmlClone.table(block));
              }
            } else if (block is WmlToc) {
              out.add(WmlClone.toc(block));
            }
        }
      }
    }
    return out;
  }

  List<WmlBlock> _slicedParagraphsInRange(
    List<WmlParagraph> paras,
    int startPara,
    int startIdx,
    int endPara,
    int endIdx,
  ) {
    return <WmlBlock>[
      for (int p = startPara; p <= endPara; p++)
        WmlClone.slicedParagraph(
          paras[p],
          p == startPara ? startIdx : 0,
          p == endPara ? endIdx : paras[p].text.length,
        ),
    ];
  }

  bool _selectionInsideTableOnly(
    WmlTable table,
    int startPara,
    int endPara,
    List<WmlParagraph> paras,
  ) {
    for (int p = startPara; p <= endPara; p++) {
      final ({WmlTable table, int row, int col})? loc =
          WordTable.locationOfParagraph(document, paras[p]);
      if (loc == null || !identical(loc.table, table)) {
        return false;
      }
    }
    return true;
  }

  _WordBlockCover _coverageOf(
    WmlBlock block,
    List<WmlParagraph> paras,
    int startPara,
    int startIdx,
    int endPara,
    int endIdx,
  ) {
    if (block is WmlVisual || block is WmlEquation) {
      return _isObjectBetweenParagraphs(block, startPara, endPara)
          ? _WordBlockCover.full
          : _WordBlockCover.none;
    }
    final List<WmlParagraph> owned = WmlClone.paragraphsOf(block);
    if (owned.isEmpty) {
      return _WordBlockCover.none;
    }
    final int first = paras.indexOf(owned.first);
    final int last = paras.indexOf(owned.last);
    if (first < 0 || last < 0 || last < startPara || first > endPara) {
      return _WordBlockCover.none;
    }
    final bool fromStart =
        startPara < first || (startPara == first && startIdx <= 0);
    final bool toEnd =
        endPara > last || (endPara == last && endIdx >= owned.last.text.length);
    if (fromStart && toEnd) {
      return _WordBlockCover.full;
    }
    return _WordBlockCover.partial;
  }

  bool _isEntireDocumentSelected() {
    if (isEditingComment) {
      return false;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty || caret.isCollapsed) {
      return false;
    }
    final (:int startPara, :int startIdx, :int endPara, :int endIdx) =
        caret.normalizedRange;
    return startPara == 0 &&
        startIdx <= 0 &&
        endPara == paras.length - 1 &&
        endIdx >= paras.last.text.length;
  }

  bool _isObjectBetweenParagraphs(WmlBlock block, int startPara, int endPara) {
    if (endPara <= startPara) {
      return false;
    }
    final int? after = _paragraphIndexBeforeBlock(block);
    if (after == null) {
      return false;
    }
    return after >= startPara && after < endPara;
  }

  int? _paragraphIndexBeforeBlock(WmlBlock block) {
    final List<WmlBlock>? parent = _parentBlocksOfBlock(block);
    if (parent == null) {
      return null;
    }
    final int index = parent.indexOf(block);
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = index - 1; i >= 0; i--) {
      final List<WmlParagraph> owned = WmlClone.paragraphsOf(parent[i]);
      if (owned.isEmpty) {
        continue;
      }
      final int at = paras.indexOf(owned.last);
      return at >= 0 ? at : null;
    }
    return -1;
  }

  void _pasteWordPlain(String text) {
    final List<String> lines = OfficeClipboardPayload.splitPlainLines(text);
    if (lines.isEmpty) {
      return;
    }
    _preflightMultilineInsert(lines);
    commands.beginBatch();
    if (!caret.isCollapsed) {
      _deleteNormalizedSelection();
    }
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) {
        _splitActiveParagraph();
      }
      if (lines[i].isNotEmpty) {
        final WmlParagraph para = _activeParagraph;
        final int start = WmlRunEdit.normalizeRange(
          para,
          caret.logicalIndex,
          caret.logicalIndex,
        ).start;
        final String line = lines[i];
        _commitParagraphInlines(
          para,
          () => WmlRunEdit.replaceRange(para, start, start, line),
          textEdit: (start: start, end: start, insertedLength: line.length),
        );
        caret.logicalIndex = start + lines[i].length;
        caret.collapseSelection();
      }
    }
    commands.endBatch();
    // Like typing and Enter: the split paragraphs are new blocks and the
    // first one's text changed, so the incremental path sees all of them.
    relayout(localEdit: true);
    _markLocalEdit();
    _syncImeSelection();
    notifyListeners();
  }

  void _pasteWordRich(List<List<OfficeClipboardSpan>> paragraphs) {
    if (paragraphs.isEmpty) {
      return;
    }
    _preflightMultilineInsert(<String>[
      for (final spans in paragraphs) spans.map((span) => span.text).join(),
    ]);
    commands.beginBatch();
    if (!caret.isCollapsed) {
      _deleteNormalizedSelection();
    }
    for (int i = 0; i < paragraphs.length; i++) {
      if (i > 0) {
        _splitActiveParagraph();
      }
      _insertSpansAtCaret(paragraphs[i]);
    }
    commands.endBatch();
    relayout();
    _markLocalEdit();
    _syncImeSelection();
    notifyListeners();
  }

  void _pasteWordBlocks(List<WmlBlock> blocks) {
    if (blocks.isEmpty) {
      return;
    }
    _assertSelectionCanChange();
    WordContentControls.assertCanInsert(document, blocks);
    final List<WmlBlock> clones = WordBookmarks.copyForInsertion(
      document,
      blocks,
    );
    final paragraphStory = isEditingComment || isEditingHeaderFooter;
    if (paragraphStory) {
      if (blocks.any((block) => block is! WmlParagraph)) {
        throw UnsupportedError(
          'This story accepts paragraph content; pasting other block objects '
          'here is not supported.',
        );
      }
      _preflightMultilineInsert(<String>[
        for (final block in blocks) block is WmlParagraph ? block.text : '',
      ]);
    }
    final mergedParagraphs = paragraphStory
        ? blocks.whereType<WmlParagraph>()
        : blocks.take(1).whereType<WmlParagraph>();
    if ((paragraphStory ||
            (!_wordBodyIsBlank() &&
                (!caret.isCollapsed || _activeParagraph.text.isNotEmpty))) &&
        mergedParagraphs.any(
          (paragraph) => WordBookmarks.generatedName(paragraph) != null,
        )) {
      throw UnsupportedError(
        'Pasting a generated paragraph bookmark into this text would discard '
        'its range. Retain it as a complete paragraph in an empty body target.',
      );
    }
    if ((paragraphStory || !_wordBodyIsBlank()) &&
        mergedParagraphs.any(
          (paragraph) =>
              paragraph.contentControlWrappers.isNotEmpty ||
              paragraph.inlines.any(
                (inline) => inline is WmlContentControlBoundary,
              ),
        )) {
      throw UnsupportedError(
        'Pasting native paragraph wrappers or inline content controls into an '
        'existing paragraph is not supported. Retain them as complete objects.',
      );
    }
    commands.beginBatch();
    if (!caret.isCollapsed) {
      _deleteNormalizedSelection();
    }
    if (paragraphStory) {
      for (int i = 0; i < clones.length; i++) {
        if (i > 0) {
          _splitActiveParagraph();
        }
        final WmlBlock block = clones[i];
        if (block is WmlParagraph) {
          _insertInlinesAtCaret(block.inlines);
        }
      }
    } else if (_wordBodyIsBlank()) {
      _replaceBodyWith(clones);
    } else {
      _insertWordBlocksAtCaret(clones);
    }
    commands.endBatch();
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _markLocalEdit();
    _syncImeSelection();
    notifyListeners();
  }

  bool _wordBodyIsBlank() {
    for (final WmlSection section in document.sections) {
      for (final WmlBlock block in section.blocks) {
        if (block is WmlParagraph) {
          if (block.text.isNotEmpty ||
              block.inlines.any(
                (inline) => inline is! WmlRun || inline.isAtomic,
              )) {
            return false;
          }
        } else {
          return false;
        }
      }
    }
    return true;
  }

  void _replaceBodyWith(List<WmlBlock> blocks) {
    final List<({WmlSection section, List<WmlBlock> blocks})> before =
        <({WmlSection section, List<WmlBlock> blocks})>[
          for (final WmlSection section in document.sections)
            (section: section, blocks: List<WmlBlock>.from(section.blocks)),
        ];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final WmlSection section in document.sections) {
            section.blocks.clear();
          }
          final List<WmlBlock> host = document.sections.first.blocks;
          if (blocks.isEmpty) {
            host.add(WmlParagraph(inlines: <WmlInline>[WmlRun()]));
          } else {
            host.addAll(blocks);
          }
          selectedTable = null;
          selectedVisual = null;
          selectedEquation = null;
        },
        undoFn: () {
          for (final ({WmlSection section, List<WmlBlock> blocks}) snap
              in before) {
            snap.section.blocks
              ..clear()
              ..addAll(snap.blocks);
          }
        },
      ),
    );
    _placeCaretAtEndOf(blocks);
  }

  void _insertWordBlocksAtCaret(List<WmlBlock> blocks) {
    if (blocks.isEmpty) {
      return;
    }
    final WmlParagraph dest = _activeParagraph;
    final bool destEmpty = dest.text.isEmpty;
    final WmlParagraphProps destProps = dest.properties.copy();
    final WmlBlock first = blocks.first;
    if (first is WmlParagraph) {
      _insertInlinesAtCaret(first.inlines);
      if (destEmpty) {
        commands.commit(
          _CallbackCommand(
            executeFn: () {
              dest.properties = first.properties.copy();
            },
            undoFn: () {
              dest.properties = destProps;
            },
          ),
        );
      }
      if (blocks.length == 1) {
        return;
      }
      _insertBlocksAfterCurrent(blocks.sublist(1));
      return;
    }
    _insertBlocksAfterCurrent(blocks);
  }

  void _insertBlocksAfterCurrent(List<WmlBlock> blocks) {
    final ({List<WmlBlock> parent, int index})? slot = _topLevelInsertSlot();
    final List<WmlBlock> parent =
        slot?.parent ?? document.sections.first.blocks;
    final int at = slot == null ? parent.length : slot.index + 1;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (int i = 0; i < blocks.length; i++) {
            parent.insert((at + i).clamp(0, parent.length), blocks[i]);
          }
        },
        undoFn: () {
          for (final WmlBlock block in blocks) {
            parent.remove(block);
          }
        },
      ),
    );
    _placeCaretAtEndOf(blocks);
    relayout();
    notifyListeners();
  }

  void _placeCaretAtEndOf(List<WmlBlock> blocks) {
    WmlParagraph? last;
    for (final WmlBlock block in blocks) {
      final List<WmlParagraph> owned = WmlClone.paragraphsOf(block);
      if (owned.isNotEmpty) {
        last = owned.last;
      }
    }
    if (last == null) {
      caret.collapseSelection();
      return;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final int index = paras.indexOf(last);
    if (index < 0) {
      return;
    }
    caret.paragraphIndex = index;
    caret.logicalIndex = last.text.length;
    caret.collapseSelection();
  }

  void _insertSpansAtCaret(List<OfficeClipboardSpan> spans) {
    _insertInlinesAtCaret(<WmlInline>[
      for (final OfficeClipboardSpan span in spans) span.toRun(),
    ]);
  }

  void _insertInlinesAtCaret(List<WmlInline> inlines) {
    if (inlines.isEmpty) {
      return;
    }
    final WmlParagraph para = _activeParagraph;
    final int start = WmlRunEdit.normalizeRange(
      para,
      caret.logicalIndex,
      caret.logicalIndex,
    ).start;
    final int added = inlines.whereType<WmlRun>().fold<int>(
      0,
      (int n, WmlRun run) => n + run.text.length,
    );
    _commitParagraphInlines(
      para,
      () => WmlRunEdit.insertInlines(para, start, inlines),
      textEdit: (start: start, end: start, insertedLength: added),
    );
    caret.logicalIndex = start + added;
    caret.collapseSelection();
  }

  void _splitActiveParagraph({
    bool pageBreakBefore = false,
    bool columnBreakBefore = false,
  }) {
    final WmlParagraph para = _activeParagraph;
    final int index = WmlRunEdit.normalizeRange(
      para,
      caret.logicalIndex,
      caret.logicalIndex,
    ).start;
    WordContentControls.assertCanSplit(para, index);
    final slot = _hostSlotOf(para);
    if (slot == null || !identical(slot.parent[slot.index], para)) {
      throw UnsupportedError('This paragraph has no editable block owner.');
    }
    final List<WmlBlock> parent = slot.parent;
    final int at = slot.index + 1;
    final List<WmlInline> before = _cloneInlines(para);
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    final split = WmlClone.splitInlines(para, index);
    // Keep both the inserted paragraph and its story stable across history.
    // Later commands hold this paragraph, even after focus moves to the body.
    final WmlParagraph next = WmlParagraph(
      properties: para.properties.copy()
        ..bookmarkName = null
        ..listRestart = null
        ..pageBreakBefore = pageBreakBefore
        ..columnBreakBefore = columnBreakBefore,
      inlines: split.tail.isEmpty
          ? <WmlInline>[WmlRun()]
          : _cloneInlinesFrom(split.tail),
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          revisions.restore(document);
          para.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(before));
          WordRevisions.splitParagraph(document, para, next, index);
          para.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(split.head));
          next.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(split.tail));
          parent.insert(at.clamp(0, parent.length), next);
        },
        undoFn: () {
          parent.remove(next);
          para.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(before));
          revisions.restore(document);
        },
      ),
    );
    caret.paragraphIndex++;
    caret.logicalIndex = 0;
    caret.collapseSelection();
  }

  void _pasteWordVisual(OfficeVisual visual) {
    final WmlParagraph para = _activeParagraph;
    final ({List<WmlBlock> parent, int index})? slot = _hostSlotOf(para);
    if (slot == null) {
      return;
    }
    final List<WmlBlock> parent = slot.parent;
    final int index = slot.index;
    final WmlVisual block = WmlVisual(visual: visual.copy());
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          parent.insert((index + 1).clamp(0, parent.length), block);
          selectedVisual = block;
        },
        undoFn: () {
          parent.remove(block);
          if (identical(selectedVisual, block)) {
            selectedVisual = null;
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// Applies character formatting to the current selection only.
  void applyRunFormat(void Function(WmlRunProps props) update) {
    if (!config.allowsMutation) {
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    final int startPara;
    final int startIdx;
    final int endPara;
    final int endIdx;
    if (caret.isCollapsed) {
      final WmlParagraph para = _activeParagraph;
      final ({int start, int end}) span = _runSpanAt(para, caret.logicalIndex);
      startPara = caret.paragraphIndex.clamp(0, paras.length - 1);
      endPara = startPara;
      startIdx = span.start;
      endIdx = span.end;
    } else {
      final ({int startPara, int startIdx, int endPara, int endIdx}) range =
          caret.normalizedRange;
      startPara = range.startPara;
      startIdx = range.startIdx;
      endPara = range.endPara;
      endIdx = range.endIdx;
    }
    if (startPara < 0 || endPara >= paras.length) {
      return;
    }
    final Map<int, List<WmlInline>> before = <int, List<WmlInline>>{
      for (int p = startPara; p <= endPara; p++) p: _cloneInlines(paras[p]),
    };
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (int p = startPara; p <= endPara; p++) {
            final WmlParagraph para = paras[p];
            para.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(before[p]!));
            final int from = p == startPara ? startIdx : 0;
            final int to = p == endPara ? endIdx : para.text.length;
            WmlRunEdit.applyRange(para, from, to, update);
          }
        },
        undoFn: () {
          for (int p = startPara; p <= endPara; p++) {
            paras[p].inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(before[p]!));
          }
        },
      ),
    );
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
    _syncImeSelection();
    notifyListeners();
  }

  static ({int start, int end}) _runSpanAt(WmlParagraph para, int index) {
    final int length = para.text.length;
    if (length == 0) {
      return (start: 0, end: 0);
    }
    final int caret = index.clamp(0, length);
    var offset = 0;
    var lastStart = 0;
    var lastEnd = 0;
    for (final WmlInline inline in para.inlines) {
      if (inline is! WmlRun || inline.text.isEmpty) {
        continue;
      }
      final int end = offset + inline.text.length;
      if (caret < end) {
        return (start: offset, end: end);
      }
      lastStart = offset;
      lastEnd = end;
      offset = end;
    }
    return (start: lastStart, end: lastEnd == 0 ? length : lastEnd);
  }

  /// activeRunProps API.
  WmlRunProps get activeRunProps =>
      WmlRunEdit.propsAt(_activeParagraph, caret.logicalIndex);

  static List<WmlInline> _cloneInlines(WmlParagraph para) =>
      _cloneInlinesFrom(para.inlines);

  static List<WmlInline> _cloneInlinesFrom(List<WmlInline> source) =>
      WmlClone.inlines(source);

  void _assertSelectionCanChange() {
    if (caret.isCollapsed) return;
    final paragraphs = _paragraphs;
    final range = caret.normalizedRange;
    if (range.startPara < 0 || range.endPara >= paragraphs.length) return;
    if (range.startPara != range.endPara) {
      for (var index = range.startPara; index <= range.endPara; index++) {
        if (WordContentControls.hasStructuralControls(paragraphs[index])) {
          throw UnsupportedError(
            'Changing several paragraphs containing a structural content '
            'control is not supported. Edit each paragraph separately.',
          );
        }
      }
    }
    for (var index = range.startPara; index <= range.endPara; index++) {
      final paragraph = paragraphs[index];
      final span = WmlRunEdit.normalizeRange(
        paragraph,
        index == range.startPara ? range.startIdx : 0,
        index == range.endPara ? range.endIdx : paragraph.text.length,
      );
      WordContentControls.assertCanEdit(paragraph, span.start, span.end);
    }
  }

  // Simulate the text portion of a paste/Enter before opening a command batch.
  // A later unsupported split must not leave an earlier replacement committed.
  void _preflightMultilineInsert(List<String> lines) {
    _assertSelectionCanChange();
    if (lines.isEmpty) return;
    final range = caret.normalizedRange;
    final paragraphs = _paragraphs;
    if (range.startPara < 0 || range.startPara >= paragraphs.length) return;
    final original = paragraphs[range.startPara];
    if (lines.length > 1) {
      final slot = _hostSlotOf(original);
      if (slot == null || !identical(slot.parent[slot.index], original)) {
        throw UnsupportedError('This paragraph has no editable block owner.');
      }
    }
    // Multi-paragraph inline-control changes were rejected above. No wrapper
    // can be split in that branch; existing structural selection rules apply.
    if (range.startPara != range.endPara) return;
    var preview = WmlClone.paragraph(original);
    final span = WmlRunEdit.normalizeRange(
      preview,
      range.startIdx,
      range.endIdx,
    );
    var offset = span.start;
    if (!caret.isCollapsed && !document.trackRevisions) {
      WmlRunEdit.replaceRange(preview, span.start, span.end, '');
    }
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].isNotEmpty) {
        WmlRunEdit.replaceRange(preview, offset, offset, lines[index]);
        offset += lines[index].length;
      }
      if (index + 1 < lines.length) {
        WordContentControls.assertCanSplit(preview, offset);
        final split = WmlClone.splitInlines(preview, offset);
        preview = WmlParagraph(inlines: split.tail);
        offset = 0;
      }
    }
  }

  void _commitParagraphInlines(
    WmlParagraph paragraph,
    void Function() update, {
    ({int start, int end, int insertedLength})? textEdit,
  }) {
    if (textEdit != null) {
      WordContentControls.assertCanEdit(
        paragraph,
        textEdit.start,
        textEdit.end,
      );
    }
    final List<WmlInline> before = _cloneInlines(paragraph);
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    final String oldText = paragraph.text;
    void restore() {
      paragraph.inlines
        ..clear()
        ..addAll(_cloneInlinesFrom(before));
      revisions.restore(document);
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          if (textEdit != null) {
            WordRevisions.rebaseEdit(
              document,
              paragraph,
              start: textEdit.start,
              end: textEdit.end,
              insertedLength: textEdit.insertedLength,
            );
          }
          update();
          if (textEdit == null) {
            WordRevisions.rebaseTextChange(document, paragraph, oldText);
          }
        },
        undoFn: restore,
      ),
    );
  }

  void _recordRevision({
    required WmlRevisionKind kind,
    required WmlParagraph paragraph,
    required int paragraphIndex,
    required int start,
    required int end,
    required String text,
  }) {
    final WmlRevisionSnapshot before = WordRevisions.capture(document);
    WmlRevisionSnapshot? after;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (after == null) {
            WordRevisions.record(
              document,
              kind: kind,
              paragraph: paragraph,
              paragraphIndex: paragraphIndex,
              start: start,
              end: end,
              text: text,
              author: revisionAuthor,
            );
            after = WordRevisions.capture(document);
          } else {
            after!.restore(document);
          }
        },
        undoFn: () => before.restore(document),
      ),
    );
  }

  /// Inserts literal plain text at the text caret as one undoable operation.
  ///
  /// Replaces a same-paragraph text selection or the complete document using
  /// plain-paste preflight and story ownership. CRLF, CR and LF become paragraph
  /// boundaries, including empty and trailing lines. Destination formatting is
  /// retained; HTML is not interpreted and the clipboard is not accessed.
  ///
  /// Returns false without changes for empty input, read-only surfaces,
  /// active Notes-pane targets, non-text object selections or partial selections
  /// spanning paragraphs. Notes retain a separate selection, so this operation
  /// must not fall through to the inactive body caret.
  /// Returns true after insertion. Unsupported content-control edits throw
  /// before any text is changed.
  bool insertPlainText(String text) {
    if (!config.allowsMutation ||
        text.isEmpty ||
        noteEditingTarget != null ||
        selectedVisual != null ||
        selectedEquation != null ||
        (selectedFrame != null && !editingFrame) ||
        selectedTable != null ||
        selectedTableBand != null) {
      return false;
    }
    final range = caret.normalizedRange;
    // Structural paste can retain boundary blocks or relocate the caret when
    // a partial selection crosses paragraphs. Do not expose that behavior as
    // text replacement at the selected target.
    if (range.startPara != range.endPara &&
        (isEditingHeaderFooter || !_isEntireDocumentSelected())) {
      return false;
    }
    _coalescingNotifications(() => _pasteWordPlain(text));
    return true;
  }

  /// insertText API.
  void insertText(String text) =>
      _coalescingNotifications(() => _insertText(text));

  void _insertText(String text) {
    if (!config.allowsMutation || text.isEmpty) {
      return;
    }
    if (selectedEquation != null) {
      insertEquationText(text);
      return;
    }
    if (selectedVisual != null) {
      return;
    }
    _assertSelectionCanChange();
    final String previous = _activeParagraph.text;
    commands.beginBatch();
    if (!caret.isCollapsed) {
      _deleteNormalizedSelection();
    }
    final WmlParagraph para = _activeParagraph;
    _syncParagraphDirection(para, incoming: text);
    final int start = WmlRunEdit.normalizeRange(
      para,
      caret.logicalIndex,
      caret.logicalIndex,
    ).start;
    _commitParagraphInlines(
      para,
      () => WmlRunEdit.replaceRange(para, start, start, text),
      textEdit: (start: start, end: start, insertedLength: text.length),
    );
    if (document.trackRevisions) {
      _recordRevision(
        kind: WmlRevisionKind.insert,
        paragraph: para,
        paragraphIndex: caret.paragraphIndex,
        start: start,
        end: start + text.length,
        text: text,
      );
    }
    commands.endBatch();
    caret.logicalIndex = start + text.length;
    caret.collapseSelection();
    relayout(localEdit: true);
    _markLocalEdit(previousText: previous);
    _syncImeSelection();
    notifyListeners();
  }

  /// deleteSelectionOr API.
  void deleteSelectionOr({required bool backward}) =>
      _coalescingNotifications(() => _deleteSelectionOr(backward: backward));

  void _deleteSelectionOr({required bool backward}) {
    if (!config.allowsMutation) {
      return;
    }
    if (selectedVisual != null) {
      deleteSelectedVisual();
      return;
    }
    if (selectedFrame != null && !editingFrame) {
      deleteSelectedFrame();
      return;
    }
    if (selectedTableBand != null) {
      deleteSelectedTableBand();
      return;
    }
    if (selectedTable != null) {
      deleteTable(table: selectedTable);
      return;
    }
    if (selectedEquation != null) {
      deleteEquationContent(backward: backward);
      return;
    }
    final String previous = _activeParagraph.text;
    if (!caret.isCollapsed) {
      _assertSelectionCanChange();
      commands.beginBatch();
      _deleteNormalizedSelection();
      commands.endBatch();
      caret.collapseSelection();
      relayout(localEdit: true);
      _markLocalEdit(previousText: previous);
      _syncImeSelection();
      notifyListeners();
      return;
    }
    final String text = _activeParagraph.text;
    final int index = caret.logicalIndex.clamp(0, text.length);
    final int start;
    final int end;
    if (backward) {
      if (index <= 0) {
        if (_joinAdjacentParagraph(backward: true)) {
          _markLocalEdit(previousText: previous);
          _syncImeSelection();
          notifyListeners();
        }
        return;
      }
      start = _clusterStartBefore(text, index);
      end = index;
    } else {
      if (index >= text.length) {
        if (_joinAdjacentParagraph(backward: false)) {
          _markLocalEdit(previousText: previous);
          _syncImeSelection();
          notifyListeners();
        }
        return;
      }
      start = index;
      end = _clusterEndAfter(text, index);
    }
    if (end <= start) {
      return;
    }
    final WmlParagraph paragraph = _activeParagraph;
    final range = WmlRunEdit.normalizeRange(paragraph, start, end);
    if (document.trackRevisions) {
      _recordRevision(
        kind: WmlRevisionKind.delete,
        paragraph: paragraph,
        paragraphIndex: caret.paragraphIndex,
        start: range.start,
        end: range.end,
        text: text.substring(range.start, range.end),
      );
      relayout(localEdit: true);
      _markLocalEdit(previousText: previous);
      _syncImeSelection();
      notifyListeners();
      return;
    }
    _commitParagraphInlines(
      paragraph,
      () => WmlRunEdit.replaceRange(paragraph, range.start, range.end, ''),
      textEdit: (start: range.start, end: range.end, insertedLength: 0),
    );
    caret.logicalIndex = range.start;
    caret.collapseSelection();
    relayout(localEdit: true);
    _markLocalEdit(previousText: previous);
    _syncImeSelection();
    notifyListeners();
  }

  void _deleteNormalizedSelection() {
    _assertSelectionCanChange();
    if (document.trackRevisions) {
      _deleteNormalizedTextOnly();
      return;
    }
    if (isEditingComment || isEditingHeaderFooter) {
      if (caret.normalizedRange.startPara != caret.normalizedRange.endPara) {
        _deleteStorySelection();
      } else {
        _deleteNormalizedTextOnly();
      }
      return;
    }
    if (_isEntireDocumentSelected()) {
      _replaceDocumentWithEmptyParagraph();
      return;
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    final (:int startPara, :int startIdx, :int endPara, :int endIdx) =
        caret.normalizedRange;
    if (startPara < 0 || endPara >= paras.length) {
      return;
    }
    if (startPara == endPara) {
      _deleteNormalizedTextOnly();
      return;
    }
    _deleteStructuredSelection(paras, startPara, startIdx, endPara, endIdx);
  }

  void _deleteStorySelection() {
    final List<WmlParagraph> parent = isEditingComment
        ? selectedComment!.paragraphs
        : _ensureHeaderFooterParagraphs();
    final range = caret.normalizedRange;
    if (range.startPara < 0 || range.endPara >= parent.length) {
      return;
    }
    final List<WmlParagraph> before = List<WmlParagraph>.of(parent);
    final WmlParagraph first = parent[range.startPara];
    final WmlParagraph last = parent[range.endPara];
    final List<WmlInline> inlines = _cloneInlines(first);
    final List<WmlInline> lastInlines = _cloneInlines(last);
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    final int from = WmlRunEdit.normalizeRange(
      first,
      range.startIdx,
      first.text.length,
    ).start;
    final int to = WmlRunEdit.normalizeRange(last, 0, range.endIdx).end;
    final List<WmlBookmarkBoundary> removedMarkers = WordBookmarks.boundariesIn(
      parent.sublist(range.startPara + 1, range.endPara),
    );
    void restore() {
      parent
        ..clear()
        ..addAll(before);
      first.inlines
        ..clear()
        ..addAll(_cloneInlinesFrom(inlines));
      last.inlines
        ..clear()
        ..addAll(_cloneInlinesFrom(lastInlines));
      revisions.restore(document);
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          WordRevisions.rebaseEdit(
            document,
            first,
            start: from,
            end: first.text.length,
            insertedLength: 0,
          );
          WmlRunEdit.replaceRange(first, from, first.text.length, '');
          WordRevisions.rebaseEdit(
            document,
            last,
            start: 0,
            end: to,
            insertedLength: 0,
          );
          WmlRunEdit.replaceRange(last, 0, to, '');
          WordRevisions.joinParagraphs(document, first, last);
          // The deletion point: where the tail of `last` joins `first`.
          final int join = first.inlines.length;
          first.inlines.addAll(
            _cloneInlinesFrom(
              last.inlines,
            ).where((inline) => inline is! WmlRun || inline.text.isNotEmpty),
          );
          parent.removeRange(range.startPara + 1, range.endPara + 1);
          WordBookmarks.clampRemoved(
            document,
            removedMarkers,
            anchor: first,
            atStart: false,
            index: join,
          );
          WmlRunEdit.coalesce(first);
          WordRevisions.markDetached(document);
        },
        undoFn: restore,
      ),
    );
    caret.paragraphIndex = range.startPara;
    caret.logicalIndex = from;
    caret.collapseSelection();
  }

  void _deleteNormalizedTextOnly() {
    final List<WmlParagraph> paras = _paragraphs;
    final (:int startPara, :int startIdx, :int endPara, :int endIdx) =
        caret.normalizedRange;
    if (startPara < 0 || endPara >= paras.length) {
      return;
    }
    var caretAt = startIdx;
    for (int p = endPara; p >= startPara; p--) {
      final WmlParagraph para = paras[p];
      final range = WmlRunEdit.normalizeRange(
        para,
        p == startPara ? startIdx : 0,
        p == endPara ? endIdx : para.text.length,
      );
      final int from = range.start;
      final int to = range.end;
      if (p == startPara) {
        caretAt = from;
      }
      if (to > from) {
        if (document.trackRevisions) {
          _recordRevision(
            kind: WmlRevisionKind.delete,
            paragraph: para,
            paragraphIndex: p,
            start: from,
            end: to,
            text: para.text.substring(from, to),
          );
          continue;
        }
        _commitParagraphInlines(
          para,
          () => WmlRunEdit.replaceRange(para, from, to, ''),
          textEdit: (start: from, end: to, insertedLength: 0),
        );
      }
    }
    _deleteVisualsInSelection(startPara, endPara);
    caret.paragraphIndex = startPara;
    caret.logicalIndex = caretAt.clamp(0, paras[startPara].text.length);
  }

  void _replaceDocumentWithEmptyParagraph() {
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    final List<({WmlSection section, List<WmlBlock> blocks})> before =
        <({WmlSection section, List<WmlBlock> blocks})>[
          for (final WmlSection section in document.sections)
            (section: section, blocks: List<WmlBlock>.from(section.blocks)),
        ];
    final WmlParagraph empty = WmlParagraph(inlines: <WmlInline>[WmlRun()]);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          revisions.restore(document);
          for (final WmlSection section in document.sections) {
            section.blocks.clear();
          }
          document.sections.first.blocks.add(empty);
          WordRevisions.markDetached(document);
          selectedTable = null;
          selectedVisual = null;
          selectedEquation = null;
          caret.paragraphIndex = 0;
          caret.logicalIndex = 0;
        },
        undoFn: () {
          for (final ({WmlSection section, List<WmlBlock> blocks}) snap
              in before) {
            snap.section.blocks
              ..clear()
              ..addAll(snap.blocks);
          }
          revisions.restore(document);
        },
      ),
    );
    caret.paragraphIndex = 0;
    caret.logicalIndex = 0;
  }

  void _deleteStructuredSelection(
    List<WmlParagraph> paras,
    int startPara,
    int startIdx,
    int endPara,
    int endIdx,
  ) {
    final WmlParagraph startIdentity = paras[startPara];
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    final List<({WmlSection section, List<WmlBlock> blocks})> sectionSnaps =
        <({WmlSection section, List<WmlBlock> blocks})>[
          for (final WmlSection section in document.sections)
            (section: section, blocks: List<WmlBlock>.from(section.blocks)),
        ];
    final Map<WmlParagraph, List<WmlInline>> inlineSnaps =
        <WmlParagraph, List<WmlInline>>{
          for (int p = startPara; p <= endPara; p++)
            paras[p]: _cloneInlines(paras[p]),
        };
    final List<WmlBlock> remove = <WmlBlock>[];
    for (final WmlSection section in document.sections) {
      for (final WmlBlock block in section.blocks) {
        if (_coverageOf(block, paras, startPara, startIdx, endPara, endIdx) ==
            _WordBlockCover.full) {
          remove.add(block);
        }
      }
    }
    // Bookmark endpoints in removed paragraphs: a range wholly inside the
    // deletion goes, one cut by it is clamped to the deletion point (Word).
    final List<WmlBookmarkBoundary> removedMarkers =
        WordBookmarks.boundariesInBlocks(remove);
    final Set<WmlParagraph> removedParas = Set<WmlParagraph>.identity()
      ..addAll(remove.expand(WmlClone.paragraphsOf));
    WmlParagraph? markerAnchor;
    var anchorAtStart = false;
    if (removedMarkers.isNotEmpty) {
      if (!removedParas.contains(paras[startPara])) {
        markerAnchor = paras[startPara];
      } else {
        for (int p = startPara + 1; p < paras.length; p++) {
          if (!removedParas.contains(paras[p])) {
            markerAnchor = paras[p];
            anchorAtStart = true;
            break;
          }
        }
        for (int p = startPara - 1; markerAnchor == null && p >= 0; p--) {
          if (!removedParas.contains(paras[p])) markerAnchor = paras[p];
        }
      }
      final WmlParagraph? anchor = markerAnchor;
      if (anchor != null && !inlineSnaps.containsKey(anchor)) {
        inlineSnaps[anchor] = _cloneInlines(anchor);
      }
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          revisions.restore(document);
          for (final WmlBlock block in remove) {
            final List<WmlBlock>? parent = _parentBlocksOfBlock(block);
            parent?.remove(block);
          }
          final List<WmlParagraph> live = document.paragraphs.toList();
          for (int p = startPara; p <= endPara; p++) {
            final WmlParagraph para = paras[p];
            if (!live.contains(para)) {
              continue;
            }
            final int from = p == startPara ? startIdx : 0;
            final int to = p == endPara ? endIdx : para.text.length;
            if (to > from) {
              final range = WmlRunEdit.normalizeRange(para, from, to);
              WordRevisions.rebaseEdit(
                document,
                para,
                start: range.start,
                end: range.end,
                insertedLength: 0,
              );
              WmlRunEdit.replaceRange(para, from, to, '');
            }
          }
          WordBookmarks.clampRemoved(
            document,
            removedMarkers,
            anchor: markerAnchor,
            atStart: anchorAtStart,
          );
          _ensureBodyHasParagraph();
          WordRevisions.markDetached(document);
          selectedTable = null;
          selectedVisual = null;
          selectedEquation = null;
        },
        undoFn: () {
          for (final ({WmlSection section, List<WmlBlock> blocks}) snap
              in sectionSnaps) {
            snap.section.blocks
              ..clear()
              ..addAll(snap.blocks);
          }
          inlineSnaps.forEach((WmlParagraph para, List<WmlInline> inlines) {
            para.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(inlines));
          });
          revisions.restore(document);
        },
      ),
    );
    final List<WmlParagraph> after = document.paragraphs.toList();
    final int stay = after.indexOf(startIdentity);
    if (stay >= 0) {
      caret.paragraphIndex = stay;
      caret.logicalIndex = startIdx.clamp(0, startIdentity.text.length);
    } else if (after.isNotEmpty) {
      caret.paragraphIndex = 0;
      caret.logicalIndex = 0;
    }
  }

  void _ensureBodyHasParagraph() {
    for (final WmlSection section in document.sections) {
      if (section.blocks.isNotEmpty) {
        return;
      }
    }
    document.sections.first.blocks.add(
      WmlParagraph(inlines: <WmlInline>[WmlRun()]),
    );
  }

  void _deleteVisualsInSelection(int startPara, int endPara) {
    if (isEditingComment || isEditingHeaderFooter || endPara <= startPara) {
      return;
    }
    final List<WmlVisual> remove = <WmlVisual>[
      for (final WmlVisual visual in visuals)
        if (_isVisualBetweenParagraphs(visual, startPara, endPara)) visual,
    ];
    for (final WmlVisual visual in remove) {
      final List<WmlBlock>? parent = _parentBlocksOfVisual(visual);
      if (parent == null) {
        continue;
      }
      final int index = parent.indexOf(visual);
      commands.commit(
        _CallbackCommand(
          executeFn: () => parent.remove(visual),
          undoFn: () {
            if (!parent.contains(visual)) {
              parent.insert(index.clamp(0, parent.length), visual);
            }
          },
        ),
      );
    }
  }

  /// insertParagraphBreak API.
  void insertParagraphBreak() =>
      _coalescingNotifications(() => _insertParagraphBreak());

  void _insertParagraphBreak({
    bool pageBreakBefore = false,
    bool columnBreakBefore = false,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    if (selectedVisual != null) {
      cycleSelectedVisualKind();
      return;
    }
    if (selectedEquation != null) {
      moveEquationSlot(1);
      return;
    }
    final String text = _activeParagraph.text;
    _preflightMultilineInsert(const <String>['', '']);
    commands.beginBatch();
    if (!caret.isCollapsed) {
      _deleteNormalizedSelection();
    }
    _splitActiveParagraph(
      pageBreakBefore: pageBreakBefore,
      columnBreakBefore: columnBreakBefore,
    );
    commands.endBatch();
    relayout(localEdit: !pageBreakBefore && !columnBreakBefore);
    _markLocalEdit(previousText: text);
    attachInput();
    notifyListeners();
  }

  void _onImeSelector(String selector) {
    if (!config.allowsSelection) {
      return;
    }
    final String name = selector.endsWith(':')
        ? selector.substring(0, selector.length - 1)
        : selector;
    final bool extend = HardwareKeyboard.instance.isShiftPressed;
    switch (name) {
      case 'moveLeft':
        moveCaretVisual(toRight: false, extend: extend);
      case 'moveRight':
        moveCaretVisual(toRight: true, extend: extend);
      case 'moveUp':
        moveCaretLine(-1, extend: extend);
      case 'moveDown':
        moveCaretLine(1, extend: extend);
      case 'moveBackward':
        moveCaret(-1, extend: extend);
      case 'moveForward':
        moveCaret(1, extend: extend);
      case 'moveLeftAndModifySelection':
        moveCaretVisual(toRight: false, extend: true);
      case 'moveRightAndModifySelection':
        moveCaretVisual(toRight: true, extend: true);
      case 'moveUpAndModifySelection':
        moveCaretLine(-1, extend: true);
      case 'moveDownAndModifySelection':
        moveCaretLine(1, extend: true);
      case 'moveWordLeft':
      case 'moveWordBackward':
        moveCaret(-1);
      case 'moveWordRight':
      case 'moveWordForward':
        moveCaret(1);
      case 'moveToLeftEndOfLine':
      case 'moveToBeginningOfLine':
        moveCaretVisual(toRight: false);
      case 'moveToRightEndOfLine':
      case 'moveToEndOfLine':
        moveCaretVisual(toRight: true);
      case 'selectAll':
        selectAll();
      default:
        break;
    }
    if (!config.allowsMutation) {
      return;
    }
    switch (name) {
      case 'deleteBackward':
        deleteSelectionOr(backward: true);
      case 'deleteForward':
        deleteSelectionOr(backward: false);
      case 'insertNewline':
        insertParagraphBreak();
      case 'undo':
        undo();
      case 'redo':
        redo();
      case 'copy':
        copyToClipboard();
      case 'cut':
        cutToClipboard();
      case 'paste':
        pasteFromClipboard();
      default:
        break;
    }
  }

  @override
  /// beforeHistoryChange API.
  void beforeHistoryChange() {
    _historyRestoredSelection = false;
    _textBeforeLocalEdit = _activeParagraph.text;
  }

  @override
  /// afterHistoryChange API.
  void afterHistoryChange() {
    final noteTarget = noteEditingTarget;
    final List<WmlParagraph> paragraphs = _paragraphs;
    caret.paragraphIndex = paragraphs.isEmpty
        ? 0
        : caret.paragraphIndex.clamp(0, paragraphs.length - 1);
    relayout();
    caret.logicalIndex = caret.logicalIndex.clamp(
      0,
      _activeParagraph.text.length,
    );
    if (!_historyRestoredSelection) caret.collapseSelection();
    if (noteTarget != null) {
      // Ordinary Notes typing has its own history commands. Keep the visible
      // note caret current when undo shortens that text, and when collapsing
      // the unrelated body selection would otherwise discard the note target.
      _restoreNoteEditingTarget(_clampNoteEditingTarget(noteTarget));
    }
    _historyRestoredSelection = false;
    _markLocalEdit(previousText: _textBeforeLocalEdit);
    _syncImeSelection();
    notifyListeners();
  }

  void _markLocalEdit({String? previousText}) {
    _localEditAt = DateTime.now();
    _textBeforeLocalEdit = previousText ?? _textBeforeLocalEdit;
  }

  bool _isImeEcho(String incoming) {
    return DateTime.now().difference(_localEditAt) <
            const Duration(milliseconds: 200) &&
        incoming == _textBeforeLocalEdit;
  }

  static int _clusterStartBefore(String text, int index) {
    final List<GraphemeCluster> clusters = GraphemeClusters.segment(text);
    for (int i = clusters.length - 1; i >= 0; i--) {
      if (clusters[i].start < index) {
        return clusters[i].start;
      }
    }
    return 0;
  }

  static int _clusterEndAfter(String text, int index) {
    for (final GraphemeCluster cluster in GraphemeClusters.segment(text)) {
      if (cluster.end > index) {
        return cluster.end;
      }
    }
    return text.length;
  }

  TextEditingValue _autocorrectImeValue(TextEditingValue value, String old) {
    if (!value.selection.isCollapsed ||
        value.composing.isValid && !value.composing.isCollapsed ||
        value.text == old) {
      return value;
    }
    final insertion = _singleInsertion(old, value.text);
    if (insertion == null) return value;
    final corrected = wordAutocorrectInsertion(
      text: value.text,
      offset: insertion.offset,
      inserted: insertion.text,
      language: _autocorrectLanguage,
    );
    if (corrected.text == value.text) return value;
    final extent = (value.selection.extentOffset + corrected.caretDelta).clamp(
      0,
      corrected.text.length,
    );
    return value.copyWith(
      text: corrected.text,
      selection: TextSelection.collapsed(offset: extent),
      composing: TextRange.empty,
    );
  }

  ({int offset, String text})? _singleInsertion(String old, String next) {
    if (next.length != old.length + 1) return null;
    var prefix = 0;
    while (prefix < old.length &&
        old.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    if (prefix == old.length) return (offset: prefix, text: next[prefix]);
    if (old.substring(prefix) != next.substring(prefix + 1)) return null;
    return (offset: prefix, text: next[prefix]);
  }

  String get _autocorrectLanguage =>
      _activeParagraph.properties.proofingLanguage ??
      document.proofingLanguage ??
      'de-DE';

  void _onIme(TextEditingValue value) {
    if (_applyingIme ||
        !config.allowsMutation ||
        selectedVisual != null ||
        selectedTable != null ||
        _isImeEcho(value.text)) {
      return;
    }
    if (selectedEquation != null) {
      _onEquationIme(value);
      _imeValueTarget = _imeEditingTarget;
      return;
    }
    final WmlParagraph para = _activeParagraph;
    final String old = para.text;
    final corrected = _autocorrectImeValue(value, old);
    final autocorrected = corrected.text != value.text;
    value = corrected;
    final void Function(String, int)? phase = debugEditPhase;
    final Stopwatch? watch = phase == null ? null : (Stopwatch()..start());
    void lap(String name) {
      if (watch == null) return;
      phase!(name, watch.elapsedMicroseconds);
      watch.reset();
    }

    if (value.text != old) {
      _setParagraphText(WmlClone.paragraph(para), value.text);
      _applyingIme = true;
      _syncParagraphDirection(para, incoming: value.text);
      lap('model');
      _commitParagraphInlines(para, () => _setParagraphText(para, value.text));
      _applyingIme = false;
      lap('undo');
      relayout(localEdit: true);
      lap('layout');
      caret.logicalIndex = value.selection.extentOffset.clamp(
        0,
        value.text.length,
      );
      caret.selectionAnchor = value.selection.baseOffset.clamp(
        0,
        value.text.length,
      );
      caret.selectionAnchorParagraph = caret.paragraphIndex;
    } else if (caret.selectionAnchorParagraph == caret.paragraphIndex) {
      caret.logicalIndex = value.selection.extentOffset.clamp(
        0,
        value.text.length,
      );
      caret.selectionAnchor = value.selection.baseOffset.clamp(
        0,
        value.text.length,
      );
      caret.selectionAnchorParagraph = caret.paragraphIndex;
    }
    caret.resetBlink();
    _imeValueTarget = _imeEditingTarget;
    lap('caret');
    if (autocorrected) input.setValue(value);
    notifyListeners();
    lap('notify');
  }

  void _onImeAction(TextInputAction action) {
    if (action == TextInputAction.newline || action == TextInputAction.done) {
      insertParagraphBreak();
    }
  }

  void _syncImeSelection() {
    if (!input.isAttached) {
      return;
    }
    _writeImeValue();
  }

  /// equationEditingText API.
  String equationEditingText() {
    final WmlEquation? equation = selectedEquation;
    if (equation == null) {
      return '';
    }
    if (equation.math.view == OmmlView.linear) {
      return equation.math.linearText.isEmpty
          ? OmmlLinear.write(equation.math.root)
          : equation.math.linearText;
    }
    return OmmlEdit.cellPlain(
      equation.math.root,
      OmmlEdit.slotAt(equation.math.root, equationSlot),
    );
  }

  int _equationCellLength() {
    return equationEditingText().length;
  }

  void _clampEquationCaret() {
    equationCaret = equationCaret.clamp(0, _equationCellLength());
  }

  void _onEquationIme(TextEditingValue value) {
    final String old = equationEditingText();
    if (value.text == old) {
      return;
    }
    final String paragraph = _activeParagraph.text;
    if (value.text == paragraph ||
        (paragraph.isNotEmpty &&
            value.text.startsWith(paragraph) &&
            !old.startsWith(paragraph))) {
      _writeImeValue();
      return;
    }
    final int oldCaret = equationCaret.clamp(0, old.length);
    if (value.text.length > old.length &&
        oldCaret <= old.length &&
        value.text.startsWith(old.substring(0, oldCaret)) &&
        value.text.endsWith(old.substring(oldCaret))) {
      final String inserted = value.text.substring(
        oldCaret,
        value.text.length - (old.length - oldCaret),
      );
      insertEquationText(inserted);
      return;
    }
    if (value.text.length == old.length - 1 &&
        oldCaret > 0 &&
        value.text ==
            old.substring(0, oldCaret - 1) + old.substring(oldCaret)) {
      deleteEquationContent(backward: true);
      return;
    }
    if (value.text.startsWith(old)) {
      insertEquationText(value.text.substring(old.length));
      return;
    }
    if (old.startsWith(value.text) && value.text.length == old.length - 1) {
      deleteEquationContent(backward: true);
      return;
    }
    _setEquationSlotText(value.text);
  }

  void _setEquationSlotText(String text) {
    _mutateEquation((OmmlEquation math) {
      if (math.view == OmmlView.linear) {
        math.linearText = text;
        return;
      }
      final OmmlSeq slot = OmmlEdit.slotAt(math.root, equationSlot);
      slot.children
        ..clear()
        ..addAll(OmmlLinear.parse(text).children);
    });
    equationCaret = text.length;
    _clampEquationCaret();
  }

  @visibleForTesting
  /// applyImeText API.
  void applyImeText(String text) {
    _onIme(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  void _writeImeValue() {
    _imeValueTarget = _imeEditingTarget;
    if (selectedEquation != null) {
      final String text = equationEditingText();
      _applyingIme = true;
      input.setValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(
            offset: equationCaret.clamp(0, text.length),
          ),
        ),
      );
      _applyingIme = false;
      return;
    }
    final String text = _activeParagraph.text;
    final bool samePara =
        caret.selectionAnchorParagraph == caret.paragraphIndex;
    _applyingIme = true;
    input.setValue(
      TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: (samePara ? caret.selectionAnchor : caret.logicalIndex)
              .clamp(0, text.length),
          extentOffset: caret.logicalIndex.clamp(0, text.length),
        ),
      ),
    );
    _applyingIme = false;
  }

  void _setParagraphText(WmlParagraph para, String text) {
    final String old = para.text;
    if (old == text) {
      return;
    }
    var prefix = 0;
    while (prefix < old.length &&
        prefix < text.length &&
        old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    var oldEnd = old.length;
    var newEnd = text.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        old.codeUnitAt(oldEnd - 1) == text.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    WmlRunEdit.replaceRange(
      para,
      prefix,
      oldEnd,
      text.substring(prefix, newEnd),
    );
  }

  bool _joinStoryParagraph({
    required List<WmlParagraph> parent,
    required WmlParagraph keep,
    required WmlParagraph drop,
    required int dropAt,
    required int caretAfter,
    required int caretPara,
  }) {
    if (dropAt < 0) {
      return false;
    }
    final List<WmlInline> keepInlines = _cloneInlines(keep);
    final List<WmlInline> dropInlines = _cloneInlines(drop);
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          revisions.restore(document);
          keep.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(keepInlines));
          WordRevisions.joinParagraphs(document, keep, drop);
          keep.inlines.addAll(
            _cloneInlinesFrom(
              dropInlines,
            ).where((inline) => inline is! WmlRun || inline.text.isNotEmpty),
          );
          WmlRunEdit.coalesce(keep);
          parent.remove(drop);
        },
        undoFn: () {
          keep.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(keepInlines));
          drop.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(dropInlines));
          if (!parent.contains(drop)) {
            parent.insert(dropAt.clamp(0, parent.length), drop);
          }
          revisions.restore(document);
        },
      ),
    );
    caret.paragraphIndex = caretPara.clamp(0, parent.length - 1);
    caret.logicalIndex = caretAfter.clamp(0, keep.text.length);
    caret.collapseSelection();
    relayout();
    return true;
  }

  /// Joins the caret paragraph with the previous (Backspace) or next (Delete).
  ///
  /// Returns `true` when the document or caret changed.
  bool _joinAdjacentParagraph({required bool backward}) {
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.length < 2) {
      return false;
    }
    final int currentIndex = caret.paragraphIndex.clamp(0, paras.length - 1);
    final int otherIndex = backward ? currentIndex - 1 : currentIndex + 1;
    if (otherIndex < 0 || otherIndex >= paras.length) {
      return false;
    }
    final WmlParagraph keep = backward
        ? paras[otherIndex]
        : paras[currentIndex];
    final WmlParagraph drop = backward
        ? paras[currentIndex]
        : paras[otherIndex];
    if (WordContentControls.hasStructuralControls(keep) ||
        WordContentControls.hasStructuralControls(drop)) {
      throw UnsupportedError(
        'Joining paragraphs containing a structural content control is not '
        'supported. Preserve each existing wrapper and paragraph.',
      );
    }
    if (isEditingComment || isEditingHeaderFooter) {
      final List<WmlParagraph> parent = isEditingComment
          ? selectedComment!.paragraphs
          : _ensureHeaderFooterParagraphs();
      return _joinStoryParagraph(
        parent: parent,
        keep: keep,
        drop: drop,
        dropAt: parent.indexOf(drop),
        caretAfter: backward ? keep.text.length : caret.logicalIndex,
        caretPara: backward ? otherIndex : currentIndex,
      );
    }
    final List<WmlBlock>? parent = _parentBlocksOf(drop);
    if (parent == null) {
      return false;
    }
    final int dropAt = parent.indexOf(drop);
    final bool canMerge = dropAt > 0 && identical(parent[dropAt - 1], keep);
    if (!canMerge) {
      if (_deleteObjectBetweenParagraphs(keep, drop, backward: backward)) {
        return true;
      }
      if (drop.text.isEmpty && parent.length > 1 && dropAt >= 0) {
        commands.commit(
          _CallbackCommand(
            executeFn: () => parent.remove(drop),
            undoFn: () {
              if (!parent.contains(drop)) {
                parent.insert(dropAt.clamp(0, parent.length), drop);
              }
            },
          ),
        );
      }
      caret.paragraphIndex = backward ? otherIndex : currentIndex;
      caret.logicalIndex = backward ? keep.text.length : caret.logicalIndex;
      caret.collapseSelection();
      relayout(localEdit: true);
      return true;
    }
    final int join = keep.text.length;
    final List<WmlInline> keepInlines = _cloneInlines(keep);
    final List<WmlInline> dropInlines = _cloneInlines(drop);
    final WmlRevisionSnapshot revisions = WordRevisions.capture(document);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          revisions.restore(document);
          keep.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(keepInlines));
          WordRevisions.joinParagraphs(document, keep, drop);
          keep.inlines.addAll(
            _cloneInlinesFrom(
              dropInlines,
            ).where((inline) => inline is! WmlRun || inline.text.isNotEmpty),
          );
          WmlRunEdit.coalesce(keep);
          parent.remove(drop);
        },
        undoFn: () {
          keep.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(keepInlines));
          drop.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(dropInlines));
          if (!parent.contains(drop)) {
            parent.insert(dropAt.clamp(0, parent.length), drop);
          }
          revisions.restore(document);
        },
      ),
    );
    caret.paragraphIndex = backward ? otherIndex : currentIndex;
    caret.logicalIndex = join;
    caret.collapseSelection();
    relayout(localEdit: true);
    return true;
  }

  bool _deleteObjectBetweenParagraphs(
    WmlParagraph keep,
    WmlParagraph drop, {
    required bool backward,
  }) {
    final List<WmlBlock>? keepParent = _parentBlocksOfBlock(keep);
    final List<WmlBlock>? dropParent = _parentBlocksOfBlock(drop);
    if (keepParent != null &&
        dropParent != null &&
        identical(keepParent, dropParent)) {
      final int keepAt = keepParent.indexOf(keep);
      final int dropAt = dropParent.indexOf(drop);
      if (keepAt >= 0 && dropAt >= 0) {
        final int lo = keepAt < dropAt ? keepAt : dropAt;
        final int hi = keepAt < dropAt ? dropAt : keepAt;
        for (int i = lo + 1; i < hi; i++) {
          final WmlBlock block = keepParent[i];
          if (block is WmlTable ||
              block is WmlVisual ||
              block is WmlEquation ||
              block is WmlToc) {
            _deleteDocumentBlock(block);
            return true;
          }
        }
      }
    }
    final ({WmlTable table, int row, int col})? keepLoc =
        WordTable.locationOfParagraph(document, keep);
    final ({WmlTable table, int row, int col})? dropLoc =
        WordTable.locationOfParagraph(document, drop);
    if (keepLoc != null && dropLoc == null && backward) {
      deleteTable(table: keepLoc.table);
      return true;
    }
    if (keepLoc == null && dropLoc != null && !backward) {
      deleteTable(table: dropLoc.table);
      return true;
    }
    return false;
  }

  void _deleteDocumentBlock(WmlBlock block) {
    if (block is WmlTable) {
      deleteTable(table: block);
      return;
    }
    if (block is WmlVisual) {
      selectedVisual = block;
      deleteSelectedVisual();
      return;
    }
    if (block is WmlEquation) {
      selectedEquation = block;
      deleteSelectedEquation();
      return;
    }
    final List<WmlBlock>? parent = _parentBlocksOfBlock(block);
    if (parent == null) {
      return;
    }
    final int at = parent.indexOf(block);
    if (at < 0) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => parent.remove(block),
        undoFn: () {
          if (!parent.contains(block)) {
            parent.insert(at.clamp(0, parent.length), block);
          }
        },
      ),
    );
    _placeCaretAfterBlockRemoval(parent, at);
    relayout();
  }

  /// selectVisual API.
  void selectVisual(WmlVisual? visual) {
    if (!config.allowsSelection) {
      selectedVisual = null;
      selectedFrame = null;
      selectedEquation = null;
      notifyListeners();
      return;
    }
    selectedVisual = visual;
    if (visual != null) {
      selectedFrame = null;
      editingFrame = false;
      selectedEquation = null;
      caret.collapseSelection();
    } else {
      pictureCropMode = false;
    }
    notifyListeners();
  }

  /// selectFrame API.
  void selectFrame(WmlFrame? frame, {bool editing = false}) {
    if (!config.allowsSelection) {
      selectedFrame = null;
      editingFrame = false;
      notifyListeners();
      return;
    }
    selectedFrame = frame;
    editingFrame = frame != null && editing;
    if (frame != null) {
      selectedVisual = null;
      selectedEquation = null;
      pictureCropMode = false;
      if (!editing) {
        caret.collapseSelection();
      }
    } else {
      editingFrame = false;
    }
    notifyListeners();
  }

  /// togglePictureCropMode API.
  void togglePictureCropMode() {
    if (selectedVisual == null || !selectedVisual!.visual.isPicture) {
      pictureCropMode = false;
      notifyListeners();
      return;
    }
    pictureCropMode = !pictureCropMode;
    notifyListeners();
  }

  /// beginVisualTransform API.
  void beginVisualTransform() {
    final OfficeVisual? visual = selectedVisual?.visual;
    if (visual == null) {
      return;
    }
    _visualSnap = (
      width: visual.width,
      height: visual.height,
      offsetX: visual.offsetX,
      offsetY: visual.offsetY,
      rotationDeg: visual.picture.rotationDeg,
      cropLeft: visual.picture.cropLeft,
      cropTop: visual.picture.cropTop,
      cropRight: visual.picture.cropRight,
      cropBottom: visual.picture.cropBottom,
    );
  }

  /// previewVisualMove API.
  void previewVisualMove(double dx, [double dy = 0]) {
    final OfficeVisual? visual = selectedVisual?.visual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    visual.offsetX = (visual.offsetX + dx).clamp(-40, 720);
    visual.offsetY = (visual.offsetY + dy).clamp(-40, 900);
    relayout();
    notifyListeners();
  }

  /// sectionAtCaret API.
  WmlSection get sectionAtCaret {
    if (document.sections.isEmpty) {
      document.sections.add(WmlSection());
    }
    if (isEditingHeaderFooter) {
      return document.sections[_editingSectionIndex.clamp(
        0,
        document.sections.length - 1,
      )];
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty) {
      return document.sections.first;
    }
    final int index = documentCaret.paragraphIndex.clamp(0, paras.length - 1);
    return document.sections[document.sectionIndexOf(paras[index])];
  }

  /// sectionIndexAtCaret API.
  int get sectionIndexAtCaret {
    if (document.sections.isEmpty) {
      return 0;
    }
    if (isEditingHeaderFooter) {
      return _editingSectionIndex.clamp(0, document.sections.length - 1);
    }
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paras.isEmpty) {
      return 0;
    }
    final int index = documentCaret.paragraphIndex.clamp(0, paras.length - 1);
    return document.sectionIndexOf(paras[index]);
  }

  /// sectionCount API.
  int get sectionCount => document.sections.length;

  /// sectionForPage API.
  WmlSection sectionForPage(int pageIndex) {
    if (pageIndex >= 0 && pageIndex < documentLaidOut.pages.length) {
      final int index = documentLaidOut.pages[pageIndex].sectionIndex;
      if (index >= 0 && index < document.sections.length) {
        return document.sections[index];
      }
    }
    return sectionAtCaret;
  }

  /// sectionAtCaret API.
  WmlSection get _pageSection => sectionAtCaret;

  /// insertSectionBreak API.
  void insertSectionBreak({
    WmlSectionBreakKind kind = WmlSectionBreakKind.nextPage,
  }) {
    if (!config.allowsMutation || isEditingComment || isEditingHeaderFooter) {
      return;
    }
    final WmlSection current = sectionAtCaret;
    final ({List<WmlBlock> parent, int index})? slot = _topLevelInsertSlot();
    final int splitAt = slot != null && identical(slot.parent, current.blocks)
        ? slot.index + 1
        : current.blocks.length;
    final List<WmlBlock> moved = splitAt < current.blocks.length
        ? current.blocks.sublist(splitAt)
        : <WmlBlock>[];
    final WmlSection next = WmlClone.section(current)
      ..blocks = moved.isEmpty
          ? <WmlBlock>[
              WmlParagraph(inlines: <WmlInline>[WmlRun(text: '')]),
            ]
          : moved
      ..breakKind = kind;
    final int at = document.sections.indexOf(current) + 1;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (moved.isNotEmpty) {
            current.blocks.removeRange(splitAt, current.blocks.length);
          }
          if (!document.sections.contains(next)) {
            document.sections.insert(
              at.clamp(0, document.sections.length),
              next,
            );
          }
        },
        undoFn: () {
          document.sections.remove(next);
          if (moved.isNotEmpty) {
            current.blocks.addAll(moved);
          }
        },
      ),
    );
    if (next.blocks.isNotEmpty && next.blocks.first is WmlParagraph) {
      final List<WmlParagraph> paras = document.paragraphs.toList();
      final int paraIndex = paras.indexOf(next.blocks.first as WmlParagraph);
      if (paraIndex >= 0) {
        documentCaret
          ..paragraphIndex = paraIndex
          ..logicalIndex = 0
          ..collapseSelection();
      }
    }
    relayout();
    notifyListeners();
  }

  /// pageMargins API.
  WmlPageMargins get pageMargins => _pageSection.margins;

  /// pageSize API.
  WmlPageSize get pageSize => _pageSection.pageSize;

  /// isPageLandscape API.
  bool get isPageLandscape => pageSize.isLandscape;

  /// pageCount API.
  int get pageCount => documentLaidOut.pages.length;

  /// visiblePageIndex API.
  int get visiblePageIndex {
    final double scale = viewport.scale * (96 / 72);
    final double viewH = viewport.extent.height > 0
        ? viewport.extent.height
        : 1;
    return documentLaidOut.pageIndexAtContentY(
      viewport.origin.dy + viewH * 0.35,
      scale,
    );
  }

  /// Continuous siblings share one visual section (heading + body columns).
  List<WmlSection> _pageGeometryGroup() {
    final List<WmlSection> sections = document.sections;
    if (sections.isEmpty) {
      return <WmlSection>[_pageSection];
    }
    int start = sections.indexOf(_pageSection);
    if (start < 0) {
      return <WmlSection>[_pageSection];
    }
    while (start > 0 &&
        sections[start].breakKind == WmlSectionBreakKind.continuous) {
      start--;
    }
    int end = start;
    while (end + 1 < sections.length &&
        sections[end + 1].breakKind == WmlSectionBreakKind.continuous) {
      end++;
    }
    return sections.sublist(start, end + 1);
  }

  /// Capture a Page Layout draft without changing section content or history.
  WordPageLayoutTarget capturePageLayout() {
    final WmlSection section = sectionAtCaret;
    return WordPageLayoutTarget(
      document: document,
      section: section,
      contentRevision: contentRevision,
      settings: WordPageLayoutSettings.fromSection(section).copyWith(
        differentOddEven: document.sections.any(
          (WmlSection item) => item.differentOddEven,
        ),
      ),
      sections: document.sections,
      sectionSettings: <WordPageLayoutSettings>[
        for (final WmlSection item in document.sections)
          WordPageLayoutSettings.fromSection(item),
      ],
    );
  }

  /// Whether a detached dialog still describes the same document and layout.
  bool isPageLayoutTargetCurrent(WordPageLayoutTarget target) {
    if (isDisposed ||
        !identical(target.document, document) ||
        target.contentRevision != contentRevision ||
        target.sections.length != document.sections.length ||
        target.sectionSettings.length != document.sections.length ||
        !document.sections.contains(target.section)) {
      return false;
    }
    for (var index = 0; index < document.sections.length; index++) {
      if (!identical(target.sections[index], document.sections[index]) ||
          !target.sectionSettings[index].matches(
            WordPageLayoutSettings.fromSection(document.sections[index]),
          )) {
        return false;
      }
    }
    return true;
  }

  /// Apply supported page settings as one validated, undoable command.
  ///
  /// For the current section, changed paper/margins propagate to continuous
  /// siblings sharing its page, matching the ribbon's existing geometry edits.
  /// Columns and first-page/line-number options belong to the chosen section.
  /// Whole-document scope sets the chosen values on every section while
  /// preserving section starts. Odd/even headers are document-wide in DOCX.
  /// A successful no-op returns true without creating a history entry.
  bool applyPageLayout(
    WordPageLayoutSettings settings, {
    WordPageLayoutScope scope = WordPageLayoutScope.currentSection,
    WordPageLayoutTarget? target,
  }) {
    if (isDisposed ||
        !config.allowsMutation ||
        settings.validationIssue != null) {
      return false;
    }
    final WordPageLayoutTarget captured = target ?? capturePageLayout();
    if (!isPageLayoutTargetCurrent(captured)) return false;
    final List<WmlSection> sections = captured.sections;
    final int selected = sections.indexOf(captured.section);
    var groupStart = selected;
    while (groupStart > 0 &&
        sections[groupStart].breakKind == WmlSectionBreakKind.continuous) {
      groupStart--;
    }
    var groupEnd = selected;
    while (groupEnd + 1 < sections.length &&
        sections[groupEnd + 1].breakKind == WmlSectionBreakKind.continuous) {
      groupEnd++;
    }
    final bool wholeDocument = scope == WordPageLayoutScope.wholeDocument;
    final bool paperChanged = !settings.samePaper(captured.settings);
    final bool marginsChanged = !settings.sameMargins(captured.settings);
    final bool oddEvenChanged =
        settings.differentOddEven != captured.settings.differentOddEven;
    final List<WordPageLayoutSettings> before = captured.sectionSettings;
    final List<WordPageLayoutSettings> after = <WordPageLayoutSettings>[];
    for (var index = 0; index < sections.length; index++) {
      final bool selectedSection = wholeDocument || index == selected;
      final bool sharedPage = index >= groupStart && index <= groupEnd;
      final WordPageLayoutSettings next = before[index].copyWith(
        pageSize: wholeDocument || (sharedPage && paperChanged)
            ? settings.pageSize
            : null,
        margins: wholeDocument || (sharedPage && marginsChanged)
            ? settings.margins
            : null,
        columnCount: selectedSection ? settings.columnCount : null,
        columnSpace: selectedSection ? settings.columnSpace : null,
        columnSeparator: selectedSection ? settings.columnSeparator : null,
        sectionStart: !wholeDocument && index == selected
            ? settings.sectionStart
            : null,
        differentFirstPage: selectedSection
            ? settings.differentFirstPage
            : null,
        differentOddEven: wholeDocument || oddEvenChanged
            ? settings.differentOddEven
            : null,
        lineNumbers: selectedSection ? settings.lineNumbers : null,
      );
      // Shared page geometry must also leave any sibling columns usable.
      if (!next.matches(before[index]) && next.validationIssue != null) {
        return false;
      }
      after.add(next);
    }
    final List<int> changed = <int>[
      for (var index = 0; index < sections.length; index++)
        if (!before[index].matches(after[index])) index,
    ];
    if (changed.isEmpty) return true;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final int index in changed) {
            after[index].applyTo(sections[index]);
          }
        },
        undoFn: () {
          for (final int index in changed) {
            before[index].applyTo(sections[index]);
          }
        },
      ),
    );
    relayout();
    notifyListeners();
    return true;
  }

  /// setPageMargins API.
  void setPageMargins(WmlPageMargins margins) {
    if (!config.allowsMutation) {
      return;
    }
    final List<WmlSection> group = _pageGeometryGroup();
    final List<WmlPageMargins> before = <WmlPageMargins>[
      for (final WmlSection section in group) section.margins,
    ];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final WmlSection section in group) {
            section.margins = margins;
          }
        },
        undoFn: () {
          for (int i = 0; i < group.length; i++) {
            group[i].margins = before[i];
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// setPageSize API.
  void setPageSize(WmlPageSize size) {
    if (!config.allowsMutation) {
      return;
    }
    final List<WmlSection> group = _pageGeometryGroup();
    final List<WmlPageSize> before = <WmlPageSize>[
      for (final WmlSection section in group) section.pageSize,
    ];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final WmlSection section in group) {
            section.pageSize = size;
          }
        },
        undoFn: () {
          for (int i = 0; i < group.length; i++) {
            group[i].pageSize = before[i];
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// setPageLandscape API.
  void setPageLandscape(bool landscape) {
    setPageSize(landscape ? pageSize.landscape : pageSize.portrait);
  }

  /// Modify the document's default tab interval and reflow its paragraphs.
  void setDefaultTabStop(double points) {
    if (!config.allowsMutation ||
        !points.isFinite ||
        points < 0.05 ||
        points > 1584) {
      return;
    }
    final next = (points * 20).round() / 20;
    final model = document;
    final before = model.defaultTabStop;
    if (next == (before ?? kDefaultTabWidth)) return;
    commands.commit(
      _CallbackCommand(
        executeFn: () => model.defaultTabStop = next,
        undoFn: () => model.defaultTabStop = before,
      ),
    );
    relayout();
    notifyListeners();
  }

  /// Edit the native paragraph style without changing direct paragraph indents.
  void setParagraphStyleGeometry(
    String id, {
    required WmlIndent indent,
    required List<WmlTabStop> tabs,
  }) {
    if (!config.allowsMutation || document.trackRevisions) return;
    final model = document;
    final update = WordHeadingIo.prepareStyleGeometry(
      model,
      id,
      indent: indent,
      tabs: tabs,
    );
    if (update == null || update.before == update.after) return;
    void apply(String xml) {
      update.part.writeText(xml);
      WordDeserializer().refreshStyles(model);
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () => apply(update.after),
        undoFn: () => apply(update.before),
      ),
    );
    relayout();
    notifyListeners();
  }

  /// applyParagraphFormat API.
  void applyParagraphFormat(
    void Function(WmlParagraphProps props) update, {
    List<WmlTabStop>? tabStops,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    final int start;
    final int end;
    if (caret.isCollapsed) {
      start = caret.paragraphIndex.clamp(0, paras.length - 1);
      end = start;
    } else {
      final ({int startPara, int startIdx, int endPara, int endIdx}) range =
          caret.normalizedRange;
      start = range.startPara.clamp(0, paras.length - 1);
      end = range.endPara.clamp(0, paras.length - 1);
    }
    final Map<int, WmlParagraphProps> before = <int, WmlParagraphProps>{
      for (int i = start; i <= end; i++) i: paras[i].properties.copy(),
    };
    final after = <int, WmlParagraphProps>{};
    if (tabStops != null) {
      final reader = WordDeserializer();
      for (var i = start; i <= end; i++) {
        final paragraph = paras[i];
        final candidate = before[i]!.copy();
        update(candidate);
        final original = paragraph.properties;
        try {
          reader.editParagraphTabStops(
            document,
            paragraph,
            replacement: tabStops,
            paragraphProperties: candidate,
          );
          after[i] = paragraph.properties;
        } finally {
          paragraph.properties = original;
        }
      }
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (var i = start; i <= end; i++) {
            paras[i].properties = (after[i] ?? before[i]!).copy();
            if (tabStops == null) update(paras[i].properties);
          }
        },
        undoFn: () {
          for (final entry in before.entries) {
            paras[entry.key].properties = entry.value.copy();
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  void _syncEmptyParagraphDirection() {
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    final WmlParagraph para =
        paras[caret.paragraphIndex.clamp(0, paras.length - 1)];
    if (para.text.trim().isEmpty) {
      _syncParagraphDirection(para);
    }
  }

  void _syncParagraphDirection(WmlParagraph para, {String incoming = ''}) {
    final String existing = para.text.trim();
    final properties = para.properties;
    final automatic = _automaticParagraphDirections[para];
    final retainsAutomaticDirection =
        identical(automatic?.properties, properties) &&
        automatic?.rightToLeft == properties.rightToLeft;
    if (properties.rightToLeft != null && !retainsAutomaticDirection) {
      return;
    }
    // Fresh empty paragraphs track studio language / incoming script. Values
    // authored by the user or an importer must survive layout and typing.
    if (existing.isEmpty) {
      final bool preferRtl =
          OfficeTypeface.isRtlText(incoming) ||
          config.textDirection == TextDirection.rtl;
      if (preferRtl) {
        properties.rightToLeft = true;
        if (!properties.explicitJustification) {
          properties.justification = WmlJustification.right;
        }
      } else {
        // Drop auto-RTL latch so BiDi / later Arabic input can take over.
        properties.rightToLeft = null;
        if (!properties.explicitJustification &&
            properties.justification == WmlJustification.right) {
          properties.justification = WmlJustification.left;
        }
      }
      _automaticParagraphDirections[para] = (
        properties: properties,
        rightToLeft: properties.rightToLeft,
      );
      return;
    }
    if (properties.rightToLeft != null) {
      return;
    }
    if (OfficeTypeface.isRtlText(existing) ||
        OfficeTypeface.isRtlText(incoming)) {
      if (properties.justification == WmlJustification.left) {
        properties.rightToLeft = true;
        if (!properties.explicitJustification) {
          properties.justification = WmlJustification.right;
        }
        _automaticParagraphDirections[para] = (
          properties: properties,
          rightToLeft: properties.rightToLeft,
        );
      }
    }
  }

  /// setParagraphDirection API.
  void setParagraphDirection({required bool rtl}) {
    applyParagraphFormat((WmlParagraphProps props) {
      props.rightToLeft = rtl;
      if (rtl) {
        if (props.justification == WmlJustification.left) {
          props.justification = WmlJustification.right;
        }
      } else if (props.justification == WmlJustification.right) {
        props.justification = WmlJustification.left;
      }
    });
  }

  /// toggleList API.
  void toggleList({required bool numbered}) {
    applyParagraphFormat((WmlParagraphProps props) {
      if (props.numId != null) {
        WordLists.clear(WmlParagraph(properties: props));
        return;
      }
      props
        ..numId = WordLists.numberingId(document, numbered: numbered)
        ..numberingSuppressed = false
        ..ilvl = 0
        ..listLabel = numbered ? '1. ' : '• ';
    });
  }

  /// setSectionColumns API.
  void setSectionColumns(int count, {double space = 36, bool sep = false}) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlSection section = sectionAtCaret;
    final int before = section.columnCount;
    final double beforeSpace = section.columnSpace;
    final bool beforeSep = section.columnSep;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          section.columnCount = count.clamp(1, 4);
          section.columnSpace = space;
          section.columnSep = sep;
        },
        undoFn: () {
          section.columnCount = before;
          section.columnSpace = beforeSpace;
          section.columnSep = beforeSep;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// insertTextFrame API.
  void insertTextFrame({
    double x = 72,
    double y = 96,
    double width = 220,
    double height = 120,
    String? fillColor,
    String text = '',
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final ({List<WmlBlock> parent, int index})? slot = _topLevelInsertSlot();
    final List<WmlBlock> parent =
        slot?.parent ?? document.sections.first.blocks;
    final int index = slot == null ? parent.length : slot.index + 1;
    final WmlFrame frame = WmlFrame(
      x: x,
      y: y,
      width: width,
      height: height,
      fillColor: fillColor ?? 'FFFFFF',
      strokeColor: '2E75B6',
      blocks: <WmlBlock>[
        WmlParagraph(
          inlines: <WmlInline>[WmlRun(text: text.isEmpty ? 'Text box' : text)],
        ),
      ],
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          parent.insert(index, frame);
          selectedFrame = frame;
          editingFrame = false;
          selectedVisual = null;
        },
        undoFn: () {
          parent.remove(frame);
          if (identical(selectedFrame, frame)) {
            selectedFrame = null;
            editingFrame = false;
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// beginFrameTransform API.
  void beginFrameTransform() {
    final WmlFrame? frame = selectedFrame;
    if (frame == null) {
      return;
    }
    _frameSnap = (
      x: frame.x,
      y: frame.y,
      width: frame.width,
      height: frame.height,
    );
  }

  /// previewFrameMove API.
  void previewFrameMove(double dx, [double dy = 0]) {
    final WmlFrame? frame = selectedFrame;
    if (frame == null || !config.allowsMutation) {
      return;
    }
    frame.x = (frame.x + dx).clamp(-80, 2000);
    frame.y = (frame.y + dy).clamp(-80, 2400);
    relayout();
    notifyListeners();
  }

  /// previewFrameResize API.
  void previewFrameResize({required double width, required double height}) {
    final WmlFrame? frame = selectedFrame;
    if (frame == null || !config.allowsMutation) {
      return;
    }
    frame.width = width.clamp(36, 2400);
    frame.height = height.clamp(28, 1800);
    relayout();
    notifyListeners();
  }

  /// commitFrameTransform API.
  void commitFrameTransform() {
    final WmlFrame? frame = selectedFrame;
    final ({double x, double y, double width, double height})? snap =
        _frameSnap;
    _frameSnap = null;
    if (frame == null || snap == null || !config.allowsMutation) {
      return;
    }
    final double x = frame.x;
    final double y = frame.y;
    final double width = frame.width;
    final double height = frame.height;
    if (x == snap.x &&
        y == snap.y &&
        width == snap.width &&
        height == snap.height) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          frame
            ..x = x
            ..y = y
            ..width = width
            ..height = height;
        },
        undoFn: () {
          frame
            ..x = snap.x
            ..y = snap.y
            ..width = snap.width
            ..height = snap.height;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// nudgeSelectedFrame API.
  void nudgeSelectedFrame({double dx = 0, double dy = 0, bool resize = false}) {
    if (selectedFrame == null || !config.allowsMutation) {
      return;
    }
    beginFrameTransform();
    if (resize) {
      previewFrameResize(
        width: selectedFrame!.width + dx,
        height: selectedFrame!.height + dy,
      );
    } else {
      previewFrameMove(dx, dy);
    }
    commitFrameTransform();
  }

  /// deleteSelectedFrame API.
  void deleteSelectedFrame() {
    final WmlFrame? frame = selectedFrame;
    if (frame == null || !config.allowsMutation) {
      return;
    }
    final List<WmlBlock>? parent = _parentBlocksOfBlock(frame);
    if (parent == null) {
      return;
    }
    final int index = parent.indexOf(frame);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          parent.remove(frame);
          selectedFrame = null;
          editingFrame = false;
        },
        undoFn: () {
          if (!parent.contains(frame)) {
            parent.insert(index.clamp(0, parent.length), frame);
          }
          selectedFrame = frame;
          editingFrame = false;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// insertColumnBreak API.
  void insertColumnBreak() {
    if (!config.allowsMutation) {
      return;
    }
    _insertParagraphBreak(columnBreakBefore: true);
  }

  /// previewVisualResize API.
  void previewVisualResize({required double width, required double height}) {
    final OfficeVisual? visual = selectedVisual?.visual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    visual.width = width.clamp(16, 2400);
    visual.height = height.clamp(16, 2400);
    relayout();
    notifyListeners();
  }

  /// previewVisualRotate API.
  void previewVisualRotate(double degrees) {
    final OfficeVisual? visual = selectedVisual?.visual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    visual.picture.rotationDeg = degrees % 360;
    notifyListeners();
  }

  /// previewVisualCrop API.
  void previewVisualCrop({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    final OfficeVisual? visual = selectedVisual?.visual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    visual.picture
      ..cropLeft = left.clamp(0.0, 0.45)
      ..cropTop = top.clamp(0.0, 0.45)
      ..cropRight = right.clamp(0.0, 0.45)
      ..cropBottom = bottom.clamp(0.0, 0.45);
    notifyListeners();
  }

  /// commitVisualTransform API.
  void commitVisualTransform() {
    final OfficeVisual? visual = selectedVisual?.visual;
    final snap = _visualSnap;
    _visualSnap = null;
    if (visual == null || snap == null || !config.allowsMutation) {
      return;
    }
    final double width = visual.width;
    final double height = visual.height;
    final double offsetX = visual.offsetX;
    final double offsetY = visual.offsetY;
    final PictureAdjust crop = visual.picture.copy();
    if (width == snap.width &&
        height == snap.height &&
        offsetX == snap.offsetX &&
        offsetY == snap.offsetY &&
        crop.rotationDeg == snap.rotationDeg &&
        crop.cropLeft == snap.cropLeft &&
        crop.cropTop == snap.cropTop &&
        crop.cropRight == snap.cropRight &&
        crop.cropBottom == snap.cropBottom) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          visual
            ..width = width
            ..height = height
            ..offsetX = offsetX
            ..offsetY = offsetY;
          visual.picture
            ..rotationDeg = crop.rotationDeg
            ..cropLeft = crop.cropLeft
            ..cropTop = crop.cropTop
            ..cropRight = crop.cropRight
            ..cropBottom = crop.cropBottom;
        },
        undoFn: () {
          visual
            ..width = snap.width
            ..height = snap.height
            ..offsetX = snap.offsetX
            ..offsetY = snap.offsetY;
          visual.picture
            ..rotationDeg = snap.rotationDeg
            ..cropLeft = snap.cropLeft
            ..cropTop = snap.cropTop
            ..cropRight = snap.cropRight
            ..cropBottom = snap.cropBottom;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// nudgeSelectedVisual API.
  void nudgeSelectedVisual({
    double dx = 0,
    double dy = 0,
    bool resize = false,
    bool crop = false,
  }) {
    final OfficeVisual? visual = selectedVisual?.visual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    beginVisualTransform();
    if (crop) {
      previewVisualCrop(
        left: visual.picture.cropLeft + (dx < 0 ? 0.02 : (dx > 0 ? -0.02 : 0)),
        top: visual.picture.cropTop + (dy < 0 ? 0.02 : (dy > 0 ? -0.02 : 0)),
        right: visual.picture.cropRight + (dx > 0 ? 0.02 : 0),
        bottom: visual.picture.cropBottom + (dy > 0 ? 0.02 : 0),
      );
    } else if (resize) {
      previewVisualResize(width: visual.width + dx, height: visual.height + dy);
    } else {
      previewVisualMove(dx, dy);
    }
    commitVisualTransform();
  }

  /// equations API.
  List<WmlEquation> get equations => document.equations.toList();

  /// selectEquation API.
  void selectEquation(WmlEquation? equation, {int? slot, int? caret}) {
    if (!config.allowsSelection) {
      selectedEquation = null;
      notifyListeners();
      return;
    }
    selectedEquation = equation;
    if (equation != null) {
      selectedVisual = null;
      final int raw = slot ?? equationSlot;
      equationSlot = OmmlEdit.snapToCell(equation.math.root, raw);
      equationCaret = caret ?? equationCaret;
      _clampEquationCaret();
      _markLocalEdit(previousText: equationEditingText());
      attachInput();
      onRequestFocus?.call();
    } else {
      equationSlot = 0;
      equationCaret = 0;
    }
    notifyListeners();
  }

  /// insertEquation API.
  void insertEquation(OmmlEquation math) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlParagraph para = _activeParagraph;
    final ({List<WmlBlock> parent, int index})? slot = _hostSlotOf(para);
    if (slot == null) {
      return;
    }
    final List<WmlBlock> parent = slot.parent;
    final int index = slot.index;
    final WmlEquation block = WmlEquation(math: math.copy());
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          parent.insert((index + 1).clamp(0, parent.length), block);
          selectedVisual = null;
          selectedEquation = block;
          equationSlot = OmmlEdit.snapToCell(block.math.root, 0);
        },
        undoFn: () {
          parent.remove(block);
          if (identical(selectedEquation, block)) {
            selectedEquation = null;
          }
        },
      ),
    );
    relayout();
    attachInput();
    notifyListeners();
    onRequestFocus?.call();
  }

  /// deleteSelectedEquation API.
  void deleteSelectedEquation() {
    final WmlEquation? equation = selectedEquation;
    if (equation == null || !config.allowsMutation) {
      return;
    }
    final List<WmlBlock>? parent = _parentBlocksOfBlock(equation);
    if (parent == null) {
      return;
    }
    final int index = parent.indexOf(equation);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          parent.remove(equation);
          selectedEquation = null;
        },
        undoFn: () {
          if (!parent.contains(equation)) {
            parent.insert(index.clamp(0, parent.length), equation);
          }
          selectedEquation = equation;
        },
      ),
    );
    _placeCaretAfterBlockRemoval(parent, index);
    relayout();
    _syncImeSelection();
    notifyListeners();
  }

  /// insertEquationText API.
  void insertEquationText(String text) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null || !config.allowsMutation || text.isEmpty) {
      return;
    }
    _mutateEquation((OmmlEquation math) {
      if (math.view == OmmlView.linear) {
        final String current = math.linearText.isEmpty
            ? OmmlLinear.write(math.root)
            : math.linearText;
        final int i = equationCaret.clamp(0, current.length);
        math.linearText = current.substring(0, i) + text + current.substring(i);
        return;
      }
      OmmlEdit.insertAt(
        math.root,
        OmmlEdit.slotAt(math.root, equationSlot),
        equationCaret,
        text,
      );
    });
    equationCaret += text.length;
    _clampEquationCaret();
  }

  /// insertEquationSymbol API.
  void insertEquationSymbol(String symbol) => insertEquationText(symbol);

  /// applyEquationStructure API.
  void applyEquationStructure(OmmlStructure kind) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null || !config.allowsMutation) {
      return;
    }
    _mutateEquation((OmmlEquation math) {
      if (math.view == OmmlView.linear) {
        math.root = OmmlLinear.parse(math.linearText);
        math.view = OmmlView.professional;
        math.linearText = '';
      }
      OmmlEdit.applyStructure(OmmlEdit.slotAt(math.root, equationSlot), kind);
    });
    final WmlEquation? after = selectedEquation;
    if (after == null) {
      return;
    }
    for (final OmmlSeq cell in OmmlEdit.cells(after.math.root)) {
      if (cell.isEmpty) {
        equationSlot = OmmlEdit.slotIndexOf(after.math.root, cell);
        equationCaret = 0;
        notifyListeners();
        return;
      }
    }
  }

  /// setEquationView API.
  void setEquationView(OmmlView view) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null || !config.allowsMutation) {
      return;
    }
    _mutateEquation((OmmlEquation math) {
      if (view == OmmlView.linear) {
        math.linearText = OmmlLinear.write(math.root);
        math.view = OmmlView.linear;
      } else {
        if (math.linearText.isNotEmpty) {
          math.root = OmmlLinear.parse(math.linearText);
        }
        math.linearText = '';
        math.view = OmmlView.professional;
      }
    });
  }

  /// deleteEquationContent API.
  void deleteEquationContent({required bool backward}) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null || !config.allowsMutation) {
      return;
    }
    if (equation.math.view == OmmlView.linear) {
      final String text = equationEditingText();
      if (text.isEmpty) {
        deleteSelectedEquation();
        return;
      }
      if (backward && equationCaret <= 0) {
        return;
      }
      if (!backward && equationCaret >= text.length) {
        return;
      }
      final int from = backward ? equationCaret - 1 : equationCaret;
      _mutateEquation((OmmlEquation math) {
        final String current = math.linearText.isEmpty
            ? OmmlLinear.write(math.root)
            : math.linearText;
        math.linearText =
            current.substring(0, from) + current.substring(from + 1);
      });
      if (backward) {
        equationCaret = from;
      }
      _clampEquationCaret();
      return;
    }
    final OmmlSeq root = equation.math.root;
    final bool atStart = equationCaret <= 0;
    if (backward &&
        atStart &&
        OmmlEdit.isFirstReadingCell(root, equationSlot) &&
        !OmmlEdit.hasUserText(root)) {
      deleteSelectedEquation();
      return;
    }
    final int len = _equationCellLength();
    if (backward && atStart) {
      final int prev = OmmlEdit.stepReading(root, equationSlot, -1);
      if (prev == equationSlot) {
        return;
      }
      equationSlot = prev;
      equationCaret = _equationCellLength();
      if (equationCaret > 0) {
        deleteEquationContent(backward: true);
      } else {
        notifyListeners();
      }
      return;
    }
    if (!backward && equationCaret >= len) {
      final int next = OmmlEdit.stepReading(
        equation.math.root,
        equationSlot,
        1,
      );
      if (next == equationSlot) {
        return;
      }
      equationSlot = next;
      equationCaret = 0;
      if (_equationCellLength() > 0) {
        deleteEquationContent(backward: false);
      } else {
        notifyListeners();
      }
      return;
    }
    final int offset = equationCaret;
    _mutateEquation((OmmlEquation math) {
      OmmlEdit.deleteAt(
        math.root,
        OmmlEdit.slotAt(math.root, equationSlot),
        offset,
        backward: backward,
      );
    });
    equationCaret = backward ? offset - 1 : offset;
    _clampEquationCaret();
  }

  /// moveEquationSlot API.
  void moveEquationSlot(int delta) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null) {
      return;
    }
    equationSlot = delta >= 0
        ? OmmlEdit.nextSlot(equation.math.root, equationSlot)
        : OmmlEdit.prevSlot(equation.math.root, equationSlot);
    equationCaret = delta >= 0 ? 0 : _equationCellLength();
    _clampEquationCaret();
    notifyListeners();
    if (input.isAttached) {
      _writeImeValue();
    }
  }

  /// moveEquationArrow API.
  void moveEquationArrow({required int dx, required int dy}) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null) {
      return;
    }
    if (dx != 0 && dy == 0) {
      _moveEquationChar(dx);
      return;
    }
    final LaidOutOmml? omml = _laidOmmlOf(equation);
    if (omml != null) {
      final int? next = _neighborEquationCell(
        omml,
        equation.math.root,
        dx: dx,
        dy: dy,
      );
      if (next != null) {
        equationSlot = next;
        equationCaret = dy < 0 ? _equationCellLength() : 0;
        _clampEquationCaret();
        notifyListeners();
        if (input.isAttached) {
          _writeImeValue();
        }
        return;
      }
    }
    moveEquationSlot(dy);
  }

  void _moveEquationChar(int dx) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null || dx == 0) {
      return;
    }
    final int len = _equationCellLength();
    if (dx > 0) {
      if (equationCaret < len) {
        equationCaret++;
      } else {
        final int next = OmmlEdit.stepReading(
          equation.math.root,
          equationSlot,
          1,
        );
        if (next != equationSlot) {
          equationSlot = next;
          equationCaret = 0;
        }
      }
    } else if (equationCaret > 0) {
      equationCaret--;
    } else {
      final int prev = OmmlEdit.stepReading(
        equation.math.root,
        equationSlot,
        -1,
      );
      if (prev != equationSlot) {
        equationSlot = prev;
        equationCaret = _equationCellLength();
      }
    }
    _clampEquationCaret();
    caret.resetBlink();
    notifyListeners();
    if (input.isAttached) {
      _writeImeValue();
    }
  }

  LaidOutOmml? _laidOmmlOf(WmlEquation equation) {
    for (final LaidOutPage page in laidOut.pages) {
      for (final LaidOutBox box in page.frames) {
        if (identical(box.equation, equation)) {
          return box.omml;
        }
      }
    }
    return null;
  }

  int? _neighborEquationCell(
    LaidOutOmml omml,
    OmmlSeq root, {
    required int dx,
    required int dy,
  }) {
    final List<OmmlSeq> all = OmmlEdit.slots(root);
    final Set<int> cellIdx = <int>{
      for (final OmmlSeq cell in OmmlEdit.cells(root))
        OmmlEdit.slotIndexOf(root, cell),
    };
    LaidOutOmmlSlot? current;
    for (final LaidOutOmmlSlot slot in omml.slots) {
      if (slot.slotIndex == equationSlot) {
        current = slot;
        break;
      }
    }
    current ??= omml.slots.cast<LaidOutOmmlSlot?>().firstWhere(
      (LaidOutOmmlSlot? slot) =>
          slot != null && cellIdx.contains(slot.slotIndex),
      orElse: () => null,
    );
    if (current == null) {
      return null;
    }
    final double cx = current.x + current.width / 2;
    final double cy = current.y + current.height / 2;
    LaidOutOmmlSlot? best;
    var bestScore = double.infinity;
    for (final LaidOutOmmlSlot slot in omml.slots) {
      if (slot.slotIndex == current.slotIndex ||
          !cellIdx.contains(slot.slotIndex) ||
          slot.slotIndex >= all.length) {
        continue;
      }
      final double sx = slot.x + slot.width / 2;
      final double sy = slot.y + slot.height / 2;
      final double ddx = sx - cx;
      final double ddy = sy - cy;
      if (dy != 0) {
        if (ddy.abs() < 2 || ddy.sign != dy) {
          continue;
        }
        final double score = ddy.abs() + ddx.abs() * 2.4;
        if (score < bestScore) {
          bestScore = score;
          best = slot;
        }
      } else if (dx != 0) {
        if (ddx.abs() < 2 || ddx.sign != dx) {
          continue;
        }
        final double score = ddx.abs() + ddy.abs() * 2.4;
        if (score < bestScore) {
          bestScore = score;
          best = slot;
        }
      }
    }
    return best?.slotIndex;
  }

  /// Function API.
  void _mutateEquation(void Function(OmmlEquation math) edit) {
    final WmlEquation? equation = selectedEquation;
    if (equation == null) {
      return;
    }
    final OmmlEquation before = equation.math.copy();
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          equation.math = before.copy();
          edit(equation.math);
        },
        undoFn: () {
          equation.math = before.copy();
        },
      ),
    );
    equationSlot = OmmlEdit.snapToCell(equation.math.root, equationSlot);
    _clampEquationCaret();
    relayout();
    attachInput();
    notifyListeners();
    onRequestFocus?.call();
  }

  /// visualsInSelection API.
  List<WmlVisual> get visualsInSelection {
    if (selectedVisual != null && caret.isCollapsed) {
      return <WmlVisual>[selectedVisual!];
    }
    if (caret.isCollapsed) {
      return const <WmlVisual>[];
    }
    final range = caret.normalizedRange;
    return <WmlVisual>[
      for (final WmlVisual visual in visuals)
        if (_isVisualBetweenParagraphs(visual, range.startPara, range.endPara))
          visual,
    ];
  }

  /// isVisualInSelection API.
  bool isVisualInSelection(OfficeVisual visual) {
    for (final WmlVisual candidate in visualsInSelection) {
      if (identical(candidate.visual, visual)) {
        return true;
      }
    }
    return false;
  }

  /// extendSelectionThroughVisual API.
  void extendSelectionThroughVisual(OfficeVisual office) {
    if (!config.allowsSelection) {
      return;
    }
    WmlVisual? visual;
    for (final WmlVisual candidate in visuals) {
      if (identical(candidate.visual, office)) {
        visual = candidate;
        break;
      }
    }
    if (visual == null) {
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    final int before = _paragraphIndexBefore(visual) ?? -1;
    final int after = before + 1;
    final int anchor = caret.selectionAnchorParagraph;
    if (anchor <= before) {
      if (after >= 0 && after < paras.length) {
        caret.paragraphIndex = after;
        caret.logicalIndex = 0;
      } else if (before >= 0 && before < paras.length) {
        caret.paragraphIndex = before;
        caret.logicalIndex = paras[before].text.length;
      }
    } else if (before >= 0 && before < paras.length) {
      caret.paragraphIndex = before;
      caret.logicalIndex = paras[before].text.length;
    }
    caret.resetBlink();
    notifyListeners();
  }

  /// selectVisualFromOffice API.
  void selectVisualFromOffice(OfficeVisual? visual) {
    if (visual == null) {
      selectVisual(null);
      return;
    }
    for (final WmlVisual candidate in visuals) {
      if (identical(candidate.visual, visual)) {
        selectVisual(candidate);
        return;
      }
    }
    selectVisual(null);
  }

  /// deleteSelectedVisual API.
  void deleteSelectedVisual() {
    final WmlVisual? visual = selectedVisual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    final List<WmlBlock>? parent = _parentBlocksOfVisual(visual);
    if (parent == null) {
      _deleteInlineVisual(visual);
      return;
    }
    final int index = parent.indexOf(visual);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          parent.remove(visual);
          selectedVisual = null;
        },
        undoFn: () {
          if (!parent.contains(visual)) {
            parent.insert(index.clamp(0, parent.length), visual);
          }
          selectedVisual = visual;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// updateSelectedVisual API.
  void updateSelectedVisual({
    String? title,
    OfficeVisualKind? kind,
    List<ChartPoint>? points,
    double? width,
    double? height,
  }) {
    final WmlVisual? visual = selectedVisual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    final OfficeVisual before = visual.visual;
    final OfficeVisualKind prevKind = before.kind;
    final String prevTitle = before.title;
    final List<ChartPoint> prevPoints = List<ChartPoint>.from(before.points);
    final double prevW = before.width;
    final double prevH = before.height;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (title != null) {
            before.title = title;
          }
          if (kind != null) {
            before.kind = kind;
          }
          if (points != null) {
            before.points
              ..clear()
              ..addAll(points);
          }
          if (width != null) {
            before.width = width;
          }
          if (height != null) {
            before.height = height;
          }
        },
        undoFn: () {
          before
            ..kind = prevKind
            ..title = prevTitle
            ..width = prevW
            ..height = prevH;
          before.points
            ..clear()
            ..addAll(prevPoints);
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// mutateSelectedVisual API.
  void mutateSelectedVisual(void Function(OfficeVisual visual) edit) {
    final WmlVisual? wrap = selectedVisual;
    if (wrap == null || !config.allowsMutation) {
      return;
    }
    final OfficeVisual visual = wrap.visual;
    final OfficeVisual before = visual.copy();
    edit(visual);
    final OfficeVisual after = visual.copy();
    commands.commit(
      _CallbackCommand(
        executeFn: () => visual.restoreFrom(after),
        undoFn: () => visual.restoreFrom(before),
      ),
    );
    relayout();
    notifyListeners();
  }

  /// cycleSelectedVisualKind API.
  void cycleSelectedVisualKind() {
    final WmlVisual? visual = selectedVisual;
    if (visual == null) {
      return;
    }
    updateSelectedVisual(kind: _nextVisualKind(visual.visual.kind));
  }

  bool _selectNeighborVisual(int delta, {required bool requireEdge}) {
    final WmlParagraph para = _activeParagraph;
    if (delta > 0 && (!requireEdge || caret.logicalIndex >= para.text.length)) {
      final WmlBlock? next = _siblingBlock(para, after: true);
      if (next is WmlVisual) {
        selectedVisual = next;
        notifyListeners();
        return true;
      }
      if (next is WmlEquation) {
        selectEquation(next);
        return true;
      }
    }
    if (delta < 0 && (!requireEdge || caret.logicalIndex <= 0)) {
      final WmlBlock? prev = _siblingBlock(para, after: false);
      if (prev is WmlVisual) {
        selectedVisual = prev;
        notifyListeners();
        return true;
      }
      if (prev is WmlEquation) {
        selectEquation(prev);
        return true;
      }
    }
    return false;
  }

  void _leaveSelectedVisual({required bool forward}) {
    final WmlVisual? visual = selectedVisual;
    selectedVisual = null;
    if (visual == null) {
      notifyListeners();
      return;
    }
    final WmlBlock? neighbor = _siblingBlock(visual, after: forward);
    if (neighbor is WmlVisual) {
      selectedVisual = neighbor;
      notifyListeners();
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (neighbor is WmlParagraph) {
      final int index = paras.indexOf(neighbor);
      if (index >= 0) {
        caret.paragraphIndex = index;
        caret.logicalIndex = forward ? 0 : neighbor.text.length;
        caret.collapseSelection();
      }
    }
    caret.resetBlink();
    notifyListeners();
  }

  WmlBlock? _siblingBlock(WmlBlock block, {required bool after}) {
    final List<WmlBlock>? parent = block is WmlParagraph
        ? _parentBlocksOf(block)
        : block is WmlVisual
        ? _parentBlocksOfVisual(block)
        : null;
    if (parent == null) {
      return null;
    }
    final int index = parent.indexOf(block);
    if (index < 0) {
      return null;
    }
    final int next = after ? index + 1 : index - 1;
    if (next < 0 || next >= parent.length) {
      return null;
    }
    return parent[next];
  }

  /// An inline picture lives in a run of its paragraph (one U+FFFC
  /// character); deleting it removes that run, undoably.
  void _deleteInlineVisual(WmlVisual visual) {
    for (final WmlParagraph paragraph in document.paragraphs) {
      final int index = paragraph.inlines.indexWhere(
        (inline) => inline is WmlRun && identical(inline.inlineVisual, visual),
      );
      if (index < 0) continue;
      final WmlInline run = paragraph.inlines[index];
      commands.commit(
        _CallbackCommand(
          executeFn: () {
            paragraph.inlines.remove(run);
            selectedVisual = null;
          },
          undoFn: () {
            if (!paragraph.inlines.contains(run)) {
              paragraph.inlines.insert(
                index.clamp(0, paragraph.inlines.length),
                run,
              );
            }
            selectedVisual = visual;
          },
        ),
      );
      relayout();
      notifyListeners();
      return;
    }
  }

  List<WmlBlock>? _parentBlocksOfVisual(WmlVisual visual) =>
      _parentBlocksOfBlock(visual);

  List<WmlBlock>? _parentBlocksOfBlock(WmlBlock target) =>
      WordTree.locate(document, target)?.parent;

  // Native vMerge continuations own structural empty paragraphs, but no
  // independent editable text. Keep model indexes stable while bypassing only
  // those placeholders during navigation. Imported content and zero-width
  // fields/bookmarks remain reachable, even in malformed native cells.
  bool _isEmptyVerticalContinuation(WmlParagraph paragraph) {
    if (isEditingComment ||
        isEditingHeaderFooter ||
        paragraph.text.isNotEmpty ||
        paragraph.contentControlWrappers.isNotEmpty ||
        paragraph.properties.fieldInstruction != null ||
        paragraph.properties.fieldBegin ||
        paragraph.properties.fieldSeparate ||
        paragraph.properties.fieldEnd ||
        paragraph.properties.pageNumberField ||
        paragraph.properties.bookmarkName != null ||
        paragraph.properties.sourceBookmarkName != null ||
        paragraph.properties.noteId != null ||
        paragraph.properties.numId != null ||
        paragraph.properties.listLabel != null ||
        paragraph.inlines.any(
          (inline) =>
              inline is! WmlRun ||
              inline.isAtomic ||
              inline.hyperlink != null ||
              inline.commentIds.isNotEmpty,
        )) {
      return false;
    }
    final location = WordTable.locationOfParagraph(document, paragraph);
    if (location == null) return false;
    final cell = location.table.rows[location.row].cells[location.col];
    if (cell.vMerge != WmlVMerge.cont ||
        cell.blocks.length != 1 ||
        !identical(cell.blocks.single, paragraph) ||
        !WordTable.supportsGridAddressing(location.table)) {
      return false;
    }
    return true;
  }

  int? _nextNavigationParagraph(
    List<WmlParagraph> paragraphs,
    int index,
    int direction,
  ) {
    for (
      var next = index + direction;
      next >= 0 && next < paragraphs.length;
      next += direction
    ) {
      if (!_isEmptyVerticalContinuation(paragraphs[next])) return next;
    }
    return null;
  }

  List<LaidOutLine> _contentLines() {
    return <LaidOutLine>[
      for (final LaidOutPage page in laidOut.pages)
        for (final LaidOutLine line in page.lines) line,
    ];
  }

  int _lineIndexOfCaret(List<LaidOutLine> lines) {
    for (int i = 0; i < lines.length; i++) {
      if (caret.isOnLine(
        lines[i],
        lastOfParagraph: _isLastContentLine(lines, i),
      )) {
        return i;
      }
    }
    var found = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].paragraphIndex == caret.paragraphIndex) {
        found = i;
      }
    }
    return found;
  }

  static bool _isLastContentLine(List<LaidOutLine> lines, int index) {
    final int paragraph = lines[index].paragraphIndex;
    for (int i = index + 1; i < lines.length; i++) {
      if (lines[i].paragraphIndex == paragraph) {
        return false;
      }
    }
    return true;
  }

  double _caretXOnLine(LaidOutLine line) {
    final List<WmlParagraph> paras = _paragraphs;
    final WmlParagraph? para = paras.isEmpty
        ? null
        : paras[line.paragraphIndex.clamp(0, paras.length - 1)];
    final String paragraph = line.sourceText ?? para?.text ?? '';
    return PaintRunText.caretXOnLine(
      line,
      caret.logicalIndex,
      paragraph: paragraph,
      themeFamily: config.theme.fontFamily,
      paragraphRtl:
          para?.properties.rightToLeft == true ||
          para?.properties.justification == WmlJustification.right ||
          config.textDirection == TextDirection.rtl,
      contentRight: documentLaidOut.pageSize.width - 72,
    );
  }

  static int _logicalAtX(LaidOutLine line, double x) {
    return CaretEngine.hitLogicalIndex(line, x);
  }

  void _crossLaidOutLine(
    List<LaidOutLine> lines,
    int index, {
    required bool toRight,
    required bool extend,
  }) {
    final int nextIndex = toRight ? index + 1 : index - 1;
    if (nextIndex < 0 || nextIndex >= lines.length) {
      if (!extend) {
        _selectNeighborVisual(toRight ? 1 : -1, requireEdge: true);
      }
      return;
    }
    final LaidOutLine current = lines[index];
    final LaidOutLine next = lines[nextIndex];
    if (!extend) {
      final WmlVisual? between = _visualBetweenLines(current, next);
      if (between != null) {
        selectedVisual = between;
        notifyListeners();
        return;
      }
    }
    caret.paragraphIndex = next.paragraphIndex;
    caret.logicalIndex = _logicalAtX(
      next,
      toRight ? next.x : next.x + next.width,
    );
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
    selectedVisual = null;
    _syncImeSelection();
    notifyListeners();
  }

  WmlVisual? _visualBetweenLines(LaidOutLine a, LaidOutLine b) {
    final int lo = a.paragraphIndex < b.paragraphIndex
        ? a.paragraphIndex
        : b.paragraphIndex;
    final int hi = a.paragraphIndex > b.paragraphIndex
        ? a.paragraphIndex
        : b.paragraphIndex;
    if (lo == hi) {
      return null;
    }
    for (final WmlVisual visual in visuals) {
      if (_isVisualBetweenParagraphs(visual, lo, hi)) {
        return visual;
      }
    }
    return null;
  }

  bool _isVisualBetweenParagraphs(
    WmlVisual visual,
    int startPara,
    int endPara,
  ) {
    if (endPara <= startPara) {
      return false;
    }
    final int? after = _paragraphIndexBefore(visual);
    if (after == null) {
      return false;
    }
    return after >= startPara && after < endPara;
  }

  int? _paragraphIndexBefore(WmlVisual visual) {
    final List<WmlBlock>? parent = _parentBlocksOfVisual(visual);
    if (parent == null) {
      return null;
    }
    final int index = parent.indexOf(visual);
    final List<WmlParagraph> paras = _paragraphs;
    for (int i = index - 1; i >= 0; i--) {
      final WmlBlock block = parent[i];
      if (block is WmlParagraph) {
        final int at = paras.indexOf(block);
        return at >= 0 ? at : null;
      }
      if (block is WmlTable) {
        WmlParagraph? last;
        for (final WmlTableRow row in block.rows) {
          for (final WmlTableCell cell in row.cells) {
            for (final WmlBlock inner in cell.blocks) {
              if (inner is WmlParagraph) {
                last = inner;
              }
            }
          }
        }
        if (last != null) {
          final int at = paras.indexOf(last);
          return at >= 0 ? at : null;
        }
      }
    }
    return -1;
  }

  static OfficeVisualKind _nextVisualKind(OfficeVisualKind kind) {
    return OfficeVisual.nextKind(kind);
  }

  List<WmlBlock>? _parentBlocksOf(WmlParagraph para) =>
      WordTree.locate(document, para)?.parent;

  @override
  /// semanticsLabel API.
  String get semanticsLabel {
    final WmlVisual? visual = selectedVisual;
    if (visual != null) {
      final String title = visual.visual.title.isEmpty
          ? config.strings.pictureLabel
          : visual.visual.title;
      final String mode = pictureCropMode ? ', ${config.strings.cropMode}' : '';
      return '${config.strings.wordEditor}, $title$mode';
    }
    return config.strings.wordEditor;
  }

  @override
  /// semanticsValue API.
  String get semanticsValue {
    final WmlVisual? visual = selectedVisual;
    if (visual != null) {
      final OfficeVisual v = visual.visual;
      return '${config.strings.pictureLabel} ${v.width.round()}×${v.height.round()}. ${config.strings.pictureHint}';
    }
    final String text = _activeParagraph.text;
    final int i = caret.logicalIndex.clamp(0, text.length);
    return text.isEmpty ? '' : text.substring(0, i);
  }

  @override
  /// hasTrackedChanges API.
  bool get hasTrackedChanges => document.revisions.isNotEmpty;

  @override
  /// documentProperties API.
  OfficeDocumentProperties get documentProperties => document.properties;

  @override
  set documentProperties(OfficeDocumentProperties value) {
    document.properties = value;
    notifyListeners();
  }

  @override
  /// documentStats API.
  OfficeTextStats get documentStats =>
      OfficeTextStats.ofWord(document, laidOut: documentLaidOut);

  @override
  /// collectFindHits API.
  List<OfficeFindHit> collectFindHits(OfficeFindOptions options) =>
      OfficeFind.inWord(document, options);

  @override
  /// applyReplace API.
  int applyReplace(OfficeFindOptions options, {OfficeFindHit? only}) {
    if (!config.allowsMutation) return 0;
    final plan = OfficeFind.prepareWordReplace(document, options, only: only);
    if (plan.count == 0) return 0;
    commitNoteEdits();
    final before = <WmlParagraph, List<WmlInline>>{
      for (final paragraph in plan.paragraphs)
        paragraph: _cloneInlines(paragraph),
    };
    final revisions = WordRevisions.capture(document);
    final previous = _activeParagraph.text;
    void restore() {
      for (final entry in before.entries) {
        entry.key.inlines
          ..clear()
          ..addAll(_cloneInlinesFrom(entry.value));
      }
      revisions.restore(document);
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          plan.apply();
        },
        undoFn: restore,
      ),
    );
    relayout();
    _markLocalEdit(previousText: previous);
    _syncImeSelection();
    notifyListeners();
    return plan.count;
  }

  @override
  /// exportPdf API.
  Uint8List exportPdf({
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
  }) {
    return OfficePrint.word(
      document,
      settings: settings,
      font: font,
      fonts: fonts,
    );
  }

  @override
  /// revealFindHit API.
  void revealFindHit(OfficeFindHit hit) {
    final int para = hit.paragraphIndex ?? 0;
    caret
      ..paragraphIndex = para
      ..logicalIndex = hit.end
      ..selectionAnchorParagraph = para
      ..selectionAnchor = hit.start
      ..resetBlink();
    _revealParagraph(para);
    notifyListeners();
  }

  /// applyStyle API.
  void applyStyle(String styleId) {
    if (!config.allowsMutation || isEditingComment) {
      return;
    }
    final List<WmlParagraph> paragraphs = _paragraphs;
    if (paragraphs.isEmpty) {
      return;
    }
    final range = caret.normalizedRange;
    final int start = range.startPara.clamp(0, paragraphs.length - 1);
    final int end = range.endPara.clamp(0, paragraphs.length - 1);
    final Map<WmlParagraph, WmlParagraph> before = <WmlParagraph, WmlParagraph>{
      for (var index = start; index <= end; index++)
        paragraphs[index]: WmlClone.paragraph(paragraphs[index]),
    };
    void restore() {
      for (final entry in before.entries) {
        entry.key.properties = entry.value.properties.copy();
        entry.key.inlines
          ..clear()
          ..addAll(_cloneInlines(entry.value));
      }
    }

    final imported = document.importedStyles.containsKey(styleId);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          if (WordHeadingIo.applyImportedStyles(
            document,
            before.keys,
            styleId,
          )) {
            return;
          }
          for (final paragraph in before.keys) {
            WordStyles.apply(paragraph, styleId, document: document);
          }
        },
        undoFn: () {
          restore();
          if (imported) WordDeserializer().refreshNumbering(document);
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// insertFootnote API.
  void insertFootnote({String text = '', bool endnote = false}) {
    if (!config.allowsMutation) {
      return;
    }
    commitNoteEdits();
    final WmlParagraph paragraph = _activeParagraph;
    final int at = WmlRunEdit.normalizeRange(
      paragraph,
      caret.logicalIndex,
      caret.logicalIndex,
    ).start;
    final WmlParagraphProps beforeProps = paragraph.properties.copy();
    final List<WmlInline> before = _cloneInlines(paragraph);
    final List<WmlNote> bucket = endnote
        ? document.endnotes
        : document.footnotes;
    final int noteIndex = bucket.length;
    WmlNote? note;
    WmlParagraphProps? insertedProps;
    List<WmlInline>? insertedInlines;
    var referenceLength = 0;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (note == null) {
            note = WordNotes.insert(
              document,
              paragraph,
              endnote: endnote,
              text: text,
            );
            final WmlRun reference = paragraph.inlines.removeLast() as WmlRun;
            WmlRunEdit.insertRuns(paragraph, at, <WmlRun>[reference]);
            referenceLength = reference.text.length;
            insertedProps = paragraph.properties.copy();
            insertedInlines = _cloneInlines(paragraph);
          } else {
            // Subsequent note edits reference this exact note instance.
            bucket.insert(noteIndex.clamp(0, bucket.length), note!);
            paragraph.properties = insertedProps!.copy();
            paragraph.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(insertedInlines!));
          }
          caret.logicalIndex = at + referenceLength;
          caret.collapseSelection();
        },
        undoFn: () {
          bucket.remove(note);
          paragraph.properties = beforeProps.copy();
          paragraph.inlines
            ..clear()
            ..addAll(_cloneInlinesFrom(before));
          caret.logicalIndex = at;
          caret.collapseSelection();
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// insertCaption API.
  void insertCaption({String label = 'Figure', String text = ''}) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlParagraph caption = WordCaptions.create(
      document,
      label: label,
      text: text,
    );
    final ({List<WmlBlock> parent, int index})? slot = _hostSlotOf(
      _activeParagraph,
    );
    final List<WmlBlock> parent =
        slot?.parent ?? document.sections.first.blocks;
    final int at = slot == null
        ? parent.length
        : (slot.index + 1).clamp(0, parent.length);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (!parent.contains(caption)) {
            parent.insert(at.clamp(0, parent.length), caption);
          }
        },
        undoFn: () => parent.remove(caption),
      ),
    );
    relayout();
    notifyListeners();
  }

  /// insertField API.
  void insertField(WmlFieldKind kind, {String argument = ''}) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlParagraph field = WmlParagraph();
    WordFields.stamp(
      field,
      kind,
      argument: argument,
      result: WordFields.evaluate(
        kind,
        document: document,
        pageCount: pageCount.clamp(1, 9999),
        instruction: WordFields.instructionOf(kind, argument: argument),
      ),
    );
    _insertBlocksAfterCurrent(<WmlBlock>[field]);
  }

  /// updateFields API.
  void updateFields() {
    WordFields.update(document, pageCount: pageCount.clamp(1, 9999));
    relayout();
    notifyListeners();
  }

  /// insertCrossReference API.
  void insertCrossReference(String bookmark) {
    insertField(WmlFieldKind.ref, argument: bookmark);
  }

  /// insertPageBreak API.
  void insertPageBreak() {
    if (!config.allowsMutation) {
      return;
    }
    _insertParagraphBreak(pageBreakBefore: true);
  }

  /// insertTable API.
  void insertTable({int rows = 3, int columns = 3}) {
    if (!config.allowsMutation) {
      return;
    }
    final int cols = columns.clamp(1, 20);
    final WmlTable table = WmlTable(
      grid: List<double>.filled(cols, 96, growable: true),
      rows: <WmlTableRow>[
        for (int r = 0; r < rows.clamp(1, 50); r++)
          WmlTableRow(
            cells: <WmlTableCell>[
              for (int c = 0; c < cols; c++)
                WmlTableCell(
                  blocks: <WmlBlock>[
                    WmlParagraph(inlines: <WmlInline>[WmlRun()]),
                  ],
                ),
            ],
          ),
      ],
    );
    _insertBlocksAfterCurrent(<WmlBlock>[table]);
  }

  /// insertPicture API.
  void insertPicture(OfficeVisual visual) {
    if (!config.allowsMutation) {
      return;
    }
    _insertBlocksAfterCurrent(<WmlBlock>[WmlVisual(visual: visual)]);
  }

  /// acceptRevision API.
  void acceptRevision(WmlRevision revision) {
    _resolveRevisions(<WmlRevision>[revision], accept: true);
  }

  /// rejectRevision API.
  void rejectRevision(WmlRevision revision) {
    _resolveRevisions(<WmlRevision>[revision], accept: false);
  }

  /// Accepts the supplied pending changes as one undoable operation. A stale,
  /// conflicted, or protected target rejects the entire batch before editing.
  /// Foreign or already resolved changes and duplicate references are ignored.
  void acceptRevisions(Iterable<WmlRevision> revisions) {
    _resolveRevisions(revisions, accept: true);
  }

  /// Rejects the supplied pending changes as one undoable operation, with the
  /// same complete-batch validation as [acceptRevisions].
  void rejectRevisions(Iterable<WmlRevision> revisions) {
    _resolveRevisions(revisions, accept: false);
  }

  void _resolveRevisions(
    Iterable<WmlRevision> revisions, {
    required bool accept,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    // Story-local paragraph indices cannot order targets across stories or
    // after paragraph insertion. Rightmost spans first is sufficient for all
    // independent paragraph targets, and keeps their offsets valid.
    final targets =
        (Set<WmlRevision>.identity()..addAll(
              revisions
                  .where(
                    (revision) =>
                        revision.accepted == null &&
                        document.revisions.contains(revision),
                  )
                  .expand(
                    (revision) => WordRevisions.related(document, revision),
                  ),
            ))
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start));
    if (targets.isEmpty) {
      return;
    }
    // Validate the whole request before a command can mutate any paragraph.
    for (final revision in targets) {
      WordRevisions.validateRevision(document, revision);
    }
    final Map<WmlParagraph, List<WmlInline>> inlines =
        <WmlParagraph, List<WmlInline>>{};
    for (final revision in targets) {
      final WmlParagraph? paragraph = WordRevisions.resolveParagraph(
        document,
        revision,
      );
      if (paragraph != null) {
        inlines.putIfAbsent(paragraph, () => _cloneInlines(paragraph));
      }
    }
    final properties = {
      for (final paragraph in inlines.keys)
        paragraph: paragraph.properties.copy(),
    };
    final WmlRevisionSnapshot before = WordRevisions.capture(document);
    final int? selected = selectedRevisionIndex;
    final pending = document.revisions
        .where((revision) => revision.accepted == null)
        .toList();
    final current = selectedRevision;
    final currentIndex = current == null ? -1 : pending.indexOf(current);
    WmlRevision? successor;
    if (current != null && !targets.contains(current)) {
      successor = current;
    } else {
      // Keep review moving forward from the decision. At the end, stay with
      // the nearest earlier change instead of jumping to the document start.
      for (var index = currentIndex + 1; index < pending.length; index++) {
        if (!targets.contains(pending[index])) {
          successor = pending[index];
          break;
        }
      }
      if (successor == null) {
        for (var index = currentIndex - 1; index >= 0; index--) {
          if (!targets.contains(pending[index])) {
            successor = pending[index];
            break;
          }
        }
      }
    }
    void restore() {
      for (final entry in inlines.entries) {
        entry.key.properties = properties[entry.key]!.copy();
        entry.key.inlines
          ..clear()
          ..addAll(_cloneInlinesFrom(entry.value));
      }
      before.restore(document);
      selectedRevisionIndex = selected;
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          try {
            for (final revision in targets) {
              if (!document.revisions.contains(revision)) continue;
              if (accept) {
                WordRevisions.accept(document, revision);
              } else {
                WordRevisions.reject(document, revision);
              }
            }
            final next = successor == null
                ? -1
                : document.revisions.indexOf(successor);
            selectedRevisionIndex = next < 0 ? null : next;
          } on Object {
            restore();
            rethrow;
          }
        },
        undoFn: restore,
      ),
    );
    relayout();
    notifyListeners();
  }

  /// setDropCap API.
  void setDropCap(int lines) {
    applyParagraphFormat((props) => props.dropCapLines = lines.clamp(0, 10));
  }

  /// setParagraphShading API.
  void setParagraphShading(String? fillRgb) {
    applyParagraphFormat((props) => props.shadingFill = fillRgb);
  }

  /// setParagraphBorder API.
  void setParagraphBorder(String? color) {
    applyParagraphFormat((props) => props.borderColor = color);
  }

  void _setSectionFlag(
    bool value,
    bool Function(WmlSection section) read,
    void Function(WmlSection section, bool value) write,
  ) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlSection section = sectionAtCaret;
    final bool before = read(section);
    if (before == value) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => write(section, value),
        undoFn: () => write(section, before),
      ),
    );
    relayout();
    notifyListeners();
  }

  /// setLineNumbers API.
  void setLineNumbers(bool value) {
    _setSectionFlag(
      value,
      (section) => section.lineNumbers,
      (section, next) => section.lineNumbers = next,
    );
  }

  /// insertTableOfFigures API.
  void insertTableOfFigures({String label = 'Figure'}) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlToc toc = WordCaptions.tableOfFigures(document, label: label);
    _insertBlocksAfterCurrent(<WmlBlock>[toc]);
  }

  /// insertCitation API.
  void insertCitation(WmlCitation citation) {
    if (!config.allowsMutation) {
      return;
    }
    final WmlParagraph paragraph = _activeParagraph;
    final List<WmlInline> before = _cloneInlines(paragraph);
    final List<WmlCitation> citations = List<WmlCitation>.of(
      document.citations,
    );
    final int at = WmlRunEdit.normalizeRange(
      paragraph,
      caret.logicalIndex,
      caret.logicalIndex,
    ).start;
    final int beforeLength = paragraph.text.length;
    void restore() {
      document.citations
        ..clear()
        ..addAll(citations);
      paragraph.inlines
        ..clear()
        ..addAll(_cloneInlinesFrom(before));
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          WordCitations.insert(document, paragraph, citation, index: at);
        },
        undoFn: restore,
      ),
    );
    caret.logicalIndex = at + paragraph.text.length - beforeLength;
    caret.collapseSelection();
    relayout();
    notifyListeners();
  }

  /// insertBibliography API.
  void insertBibliography() {
    if (!config.allowsMutation) {
      return;
    }
    _insertBlocksAfterCurrent(<WmlBlock>[WordCitations.bibliography(document)]);
  }

  /// Zotero fields in every modeled story, including imported citations.
  /// Reinspect after mutations or undo/redo: field handles are short-lived.
  List<WmlZoteroField> get zoteroFields => WordZotero.fields(document);

  /// Whether a field has a complete result packet the native Zotero processor
  /// can replace, even when its stored citation metadata is damaged. This is
  /// an availability hint; the transaction rechecks document ownership,
  /// protection and the complete field inventory before any change applies.
  bool canEditZoteroFieldNatively(WmlZoteroField field) =>
      field.canEditNativeResult ||
      WordZotero.canRecoverNativeBibliography(document, field);

  WordZoteroTransaction? _zoteroContextOwner;

  /// Temporary context requested by Zotero while a detached operation runs.
  /// This never replaces the writing selection or the active Notes target.
  /// A changed document/selection or a finished operation has no live context.
  WordZoteroFieldSelectionContext? get zoteroFieldContext {
    final owner = _zoteroContextOwner;
    if (owner == null || _disposed || !config.allowsSelection) return null;
    try {
      return owner.selectedFieldContext;
    } on StateError {
      return null;
    }
  }

  void _presentZoteroFieldContext(WordZoteroTransaction owner) {
    final context = owner.selectedFieldContext;
    if (context == null) {
      _clearZoteroFieldContext(owner);
      return;
    }
    final previous = _zoteroContextOwner;
    if (previous != null && !identical(previous, owner)) {
      previous.clearFieldContext();
    }
    _zoteroContextOwner = owner;
    owner._revealFieldContext(context);
    notifyListeners();
  }

  void _clearZoteroFieldContext(
    WordZoteroTransaction owner, {
    bool notify = true,
  }) {
    if (!identical(_zoteroContextOwner, owner)) return;
    _zoteroContextOwner = null;
    owner._restoreContextViewport();
    if (notify && !_disposed) notifyListeners();
  }

  /// A fresh field handle at the body or Notes caret, enclosing a selection
  /// in one paragraph, or exactly matching a selected multi-paragraph
  /// bibliography. A collapsed caret at a field's end belongs to the following
  /// text. Other stories retain their explicit field-list actions.
  WmlZoteroField? get zoteroFieldAtCaret => findZoteroFieldAtCaret();

  /// Resolves the current editing caret using a fresh field inventory when the
  /// caller already inspected this document during the same synchronous build.
  /// Omit [fields] to inspect the document here. Do not retain supplied handles
  /// across document changes or undo/redo.
  WmlZoteroField? findZoteroFieldAtCaret({Iterable<WmlZoteroField>? fields}) {
    if (_disposed ||
        isEditingHeaderFooter ||
        isEditingComment ||
        editingFrame ||
        selectedFrame != null) {
      return null;
    }
    final noteTarget = noteEditingTarget;
    final WmlParagraph paragraph;
    final int rangeStart;
    final int rangeEnd;
    final bool collapsed;
    if (noteTarget != null) {
      final range = _noteSelectionRange(noteTarget);
      if (range == null) {
        return (fields ?? zoteroFields).where((field) {
          if (field.kind != ZoteroFieldKind.bibliography ||
              field.paragraphs.length < 2) {
            return false;
          }
          final visible = _zoteroRevealRange(field);
          return visible != null &&
              identical(visible.note, noteTarget.note) &&
              visible.start == noteTarget.selection.start &&
              visible.end == noteTarget.selection.end;
        }).firstOrNull;
      }
      paragraph = range.paragraph;
      rangeStart = range.start;
      rangeEnd = range.end;
      collapsed = noteTarget.selection.isCollapsed;
    } else {
      final paragraphs = document.paragraphs.toList();
      final range = caret.normalizedRange;
      if (range.startPara < 0 || range.endPara >= paragraphs.length) {
        return null;
      }
      if (range.startPara != range.endPara) {
        final selected = paragraphs.sublist(range.startPara, range.endPara + 1);
        return (fields ?? zoteroFields).where((field) {
          if (field.kind != ZoteroFieldKind.bibliography ||
              field.paragraphs.length < 2 ||
              !listEquals(field.paragraphs, selected) ||
              range.startIdx != field.start ||
              range.endIdx != field.end) {
            return false;
          }
          final visible = _zoteroRevealRange(field);
          return visible != null && visible.note == null;
        }).firstOrNull;
      }
      paragraph = paragraphs[range.startPara];
      rangeStart = range.startIdx;
      rangeEnd = range.endIdx;
      collapsed = caret.isCollapsed;
    }
    if (rangeStart < 0 || rangeEnd > paragraph.text.length) return null;
    return (fields ?? zoteroFields).where((field) {
      final index = field.paragraphs.indexOf(paragraph);
      if (index < 0) return false;
      final start = index == 0 ? field.start : 0;
      final end = index == field.paragraphs.length - 1
          ? field.end
          : paragraph.text.length;
      return rangeStart >= start &&
          (collapsed ? rangeStart < end : rangeEnd <= end);
    }).firstOrNull;
  }

  /// Whether the field has a selectable range in the body or the Notes pane.
  /// This is an availability hint and does not scan the Zotero inventory.
  /// [revealZoteroField] reinspects ownership before moving the selection.
  bool canRevealZoteroField(WmlZoteroField field) =>
      _zoteroRevealRange(field) != null;

  /// Selects a current citation or bibliography without changing document
  /// content, dirty state or undo history. Read-only selecting mode is allowed.
  /// Unsupported stories, stale handles and incomplete ranges return false.
  bool revealZoteroField(WmlZoteroField field) {
    if (!canRevealZoteroField(field)) return false;
    final current = zoteroFields
        .where(
          (candidate) =>
              identical(candidate.paragraph, field.paragraph) &&
              listEquals(candidate.paragraphs, field.paragraphs) &&
              identical(candidate.run, field.run) &&
              candidate.kind == field.kind &&
              candidate.start == field.start &&
              candidate.end == field.end &&
              candidate.instruction == field.instruction &&
              candidate.cachedText == field.cachedText &&
              candidate.wholeParagraph == field.wholeParagraph &&
              candidate.locked == field.locked &&
              candidate.nested == field.nested &&
              candidate.opaqueMetadata == field.opaqueMetadata,
        )
        .firstOrNull;
    if (current == null) return false;
    final range = _zoteroRevealRange(current);
    if (range == null) return false;
    final note = range.note;
    if (note != null) {
      detachInput();
      setNoteEditingTarget(
        note,
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
    } else {
      final paragraphs = document.paragraphs.toList();
      final first = paragraphs.indexOf(current.paragraphs.first);
      final last = paragraphs.indexOf(current.paragraphs.last);
      if (first < 0 || last < first) return false;
      clearNoteEditingTarget(notify: false);
      _editingComment = false;
      _editingHeaderFooter = false;
      selectedVisual = null;
      selectedFrame = null;
      editingFrame = false;
      selectedEquation = null;
      selectedTable = null;
      selectedTableBand = null;
      documentCaret
        ..paragraphIndex = last
        ..logicalIndex = range.end
        ..selectionAnchorParagraph = first
        ..selectionAnchor = range.start
        ..resetBlink();
      _stickyCaretX = null;
      _revealParagraph(first);
      _syncImeSelection();
      notifyListeners();
    }
    requestEditingFocus();
    return true;
  }

  ({WmlNote? note, int start, int end})? _zoteroRevealRange(
    WmlZoteroField field,
  ) {
    if (_disposed ||
        !config.allowsSelection ||
        !field.isValid ||
        field.nested ||
        field.opaqueMetadata ||
        field.paragraphs.isEmpty ||
        !identical(field.paragraphs.first, field.paragraph) ||
        field.start < 0 ||
        field.start > field.paragraph.text.length ||
        field.end < 0 ||
        field.end > field.paragraphs.last.text.length ||
        (field.paragraphs.length == 1 && field.start >= field.end) ||
        (field.paragraphs.length > 1 &&
            field.kind != ZoteroFieldKind.bibliography) ||
        (input.composing.isValid && !input.composing.isCollapsed)) {
      return null;
    }
    final activeNote = noteEditingTarget;
    if (activeNote != null &&
        activeNote.composing.isValid &&
        !activeNote.composing.isCollapsed) {
      return null;
    }
    bool contiguous(List<WmlBlock> parent, int index) =>
        index + field.paragraphs.length <= parent.length &&
        field.paragraphs.indexed.every(
          (entry) => identical(parent[index + entry.$1], entry.$2),
        );
    for (final section in document.sections) {
      final slot = _zoteroBodyParagraphSlot(section.blocks, field.paragraph);
      if (slot != null) {
        return contiguous(slot.parent, slot.index)
            ? (note: null, start: field.start, end: field.end)
            : null;
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      final segments = _noteTextSegments(note).toList();
      final first = segments.indexWhere(
        (segment) => identical(segment.paragraph, field.paragraph),
      );
      if (first < 0) continue;
      final last = first + field.paragraphs.length - 1;
      if (last >= segments.length ||
          !field.paragraphs.indexed.every(
            (entry) =>
                identical(segments[first + entry.$1].paragraph, entry.$2),
          ) ||
          field.start < segments[first].hidden ||
          field.end < segments[last].hidden) {
        return null;
      }
      final slot = WordTree.locateIn(note.blocks, field.paragraph);
      if (slot == null || !contiguous(slot.parent, slot.index)) return null;
      return (
        note: note,
        start: segments[first].start + field.start - segments[first].hidden,
        end: segments[last].start + field.end - segments[last].hidden,
      );
    }
    return null;
  }

  static ({List<WmlBlock> parent, int index})? _zoteroBodyParagraphSlot(
    List<WmlBlock> blocks,
    WmlParagraph paragraph,
  ) {
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (identical(block, paragraph)) return (parent: blocks, index: index);
      final Iterable<List<WmlBlock>> children;
      if (block is WmlContentControlBlock) {
        children = [block.blocks];
      } else if (block is WmlTable) {
        children = [
          for (final row in block.rows)
            for (final cell in row.cells) cell.blocks,
        ];
      } else {
        // Text frames and generated TOCs do not share the body input surface.
        continue;
      }
      for (final child in children) {
        final found = _zoteroBodyParagraphSlot(child, paragraph);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Starts a detached Zotero desktop transaction tied to this exact editing
  /// target. The host drives its protocol and calls [WordZoteroTransaction.apply]
  /// only after completion and any formatting review.
  WordZoteroTransaction beginZoteroTransaction({
    required String documentId,
    ZoteroCitingCommand? command,
    WmlZoteroField? selectedField,
    ZoteroCitation? seedCitation,
    bool Function()? isCurrent,
  }) {
    if (_disposed || !config.allowsMutation) {
      throw StateError('This document is not editable.');
    }
    if (input.composing.isValid && !input.composing.isCollapsed) {
      throw UnsupportedError(
        'Finish the current text composition before using Zotero.',
      );
    }
    if (WordZoteroTransfer.isTransferDocument(document) &&
        command != null &&
        command != ZoteroCitingCommand.refresh) {
      throw UnsupportedError(
        'Use Refresh citations to import this Zotero transfer document before editing its references.',
      );
    }
    final noteTarget = noteEditingTarget;
    _assertNoteTargetReady(noteTarget);
    final insertsNoteText = command?.insertsNoteText == true;
    if (insertsNoteText &&
        (selectedVisual != null ||
            selectedEquation != null ||
            selectedTableBand != null)) {
      throw UnsupportedError(
        'Place the caret or select ordinary text before inserting a Zotero note or annotation.',
      );
    }
    commitNoteEdits();
    _assertZoteroTrackingMode();
    if (isEditingHeaderFooter ||
        isEditingComment ||
        editingFrame ||
        selectedFrame != null) {
      throw UnsupportedError(
        'Open Zotero from the document body or an anchored note to use its desktop citation tools.',
      );
    }
    if (selectedField != null) _assertZoteroFieldOwner(selectedField);
    final noteRange = noteTarget == null
        ? null
        : _noteSelectionRange(noteTarget);
    final researchNoteRange = noteTarget == null || !insertsNoteText
        ? null
        : _noteResearchSelectionRange(noteTarget);
    final bodyRange = caret.normalizedRange;
    final bodyParagraphs = document.paragraphs.toList();
    final validBodyRange =
        bodyRange.startPara >= 0 &&
        bodyRange.endPara >= bodyRange.startPara &&
        bodyRange.endPara < bodyParagraphs.length;
    if (insertsNoteText &&
        (noteTarget != null ? researchNoteRange == null : !validBodyRange)) {
      throw UnsupportedError(
        'Select ordinary text in the document body or an authored note to replace it with a Zotero note or annotation.',
      );
    }
    final resolvedField =
        selectedField ?? (noteTarget != null ? findZoteroFieldAtCaret() : null);
    final session = WordZoteroCitingSession(
      document: document,
      documentId: documentId,
      insertionParagraph: noteTarget != null
          ? (insertsNoteText
                ? researchNoteRange!.paragraph
                : (noteTarget.selection.isCollapsed
                      ? noteRange?.paragraph
                      : null))
          : (insertsNoteText
                ? bodyParagraphs[bodyRange.startPara]
                : (caret.isCollapsed ? _activeParagraph : null)),
      insertionEndParagraph: insertsNoteText
          ? (noteTarget != null
                ? researchNoteRange!.endParagraph
                : bodyParagraphs[bodyRange.endPara])
          : null,
      insertionOffset: noteTarget != null
          ? (insertsNoteText
                ? researchNoteRange!.start
                : (noteRange?.start ?? 0))
          : (insertsNoteText ? bodyRange.startIdx : caret.logicalIndex),
      insertionEndOffset: insertsNoteText
          ? (noteTarget != null ? researchNoteRange!.end : bodyRange.endIdx)
          : null,
      selectedField: resolvedField,
      seedCitation: seedCitation,
    );
    if (insertsNoteText) {
      session.assertCanInsertNoteText();
    }
    return WordZoteroTransaction._(this, session, isCurrent: isCurrent);
  }

  void _applyZoteroTransaction(WordZoteroCitingSession session) {
    _assertZoteroTrackingMode();
    if (!identical(session.document, document)) {
      throw StateError('The document changed while Zotero was open.');
    }
    if (!session.isComplete) {
      throw StateError('Zotero has not completed the operation.');
    }
    if (!session.hasChanges) return;
    // Reject stale host state before capturing endpoints from its live
    // paragraphs, preserving the transaction's StateError contract.
    session.assertUnchanged();
    final beforeCaret = caret.logicalIndex;
    final beforeParagraph = caret.paragraphIndex;
    final beforeAnchor = caret.selectionAnchor;
    final beforeAnchorParagraph = caret.selectionAnchorParagraph;
    final beforeNoteTarget = noteEditingTarget;
    final sourceParagraphs = _paragraphs;
    WordZoteroCitingPosition? captureBody(int paragraph, int offset) =>
        paragraph >= 0 && paragraph < sourceParagraphs.length
        ? session.capturePosition(
            sourceParagraphs[paragraph],
            offset.clamp(0, sourceParagraphs[paragraph].text.length),
          )
        : null;
    WordZoteroCitingPosition? captureNote(int offset) {
      if (beforeNoteTarget == null) return null;
      final range = _noteSelectionRange((
        note: beforeNoteTarget.note,
        selection: TextSelection.collapsed(offset: offset),
        composing: TextRange.empty,
      ));
      return range == null
          ? null
          : session.capturePosition(range.paragraph, range.start);
    }

    // Body and Notes selections have independent endpoints. Retain their
    // native paragraph identities before bibliography reflow changes indexes.
    final bodyExtent = captureBody(beforeParagraph, beforeCaret);
    final bodyAnchor = captureBody(beforeAnchorParagraph, beforeAnchor);
    final noteExtent = beforeNoteTarget == null
        ? null
        : captureNote(beforeNoteTarget.selection.extentOffset);
    final noteAnchor = beforeNoteTarget == null
        ? null
        : captureNote(beforeNoteTarget.selection.baseOffset);
    final before = _ZoteroDocumentSnapshot.capture(document);
    before.assertRestorable(document);
    late final _ZoteroDocumentSnapshot after;
    late ({int paragraph, int offset}) afterExtent;
    late ({int paragraph, int offset}) afterAnchor;
    WordNoteEditingTarget? afterNoteTarget;
    try {
      session.apply();
      final paragraphs = _paragraphs;
      ({WmlParagraph paragraph, int offset})? resolve(
        WordZoteroCitingPosition? position,
      ) => position == null ? null : session.resolvePosition(position);
      ({int paragraph, int offset}) bodyPosition(
        ({WmlParagraph paragraph, int offset})? position, {
        required int fallbackParagraph,
        required int fallbackOffset,
      }) {
        final index = position == null
            ? -1
            : paragraphs.indexOf(position.paragraph);
        final paragraph = (index < 0 ? fallbackParagraph : index).clamp(
          0,
          paragraphs.length - 1,
        );
        return (
          paragraph: paragraph,
          offset: (index < 0 ? fallbackOffset : position!.offset).clamp(
            0,
            paragraphs[paragraph].text.length,
          ),
        );
      }

      final mappedExtent = resolve(bodyExtent);
      final mappedAnchor = resolve(bodyAnchor);
      afterExtent = bodyPosition(
        mappedExtent,
        fallbackParagraph: beforeParagraph,
        fallbackOffset: beforeCaret,
      );
      afterAnchor = mappedExtent == null || mappedAnchor == null
          ? afterExtent
          : bodyPosition(
              mappedAnchor,
              fallbackParagraph: beforeAnchorParagraph,
              fallbackOffset: beforeAnchor,
            );
      final destination = session.caretAfter;
      if (destination != null) {
        // New citations and research content retain their explicit insertion
        // destination; Refresh and style changes use the transformed source.
        afterExtent = bodyPosition(
          destination,
          fallbackParagraph: afterExtent.paragraph,
          fallbackOffset: afterExtent.offset,
        );
        afterAnchor = afterExtent;
        afterNoteTarget = _noteTargetAt(
          destination.paragraph,
          destination.offset,
        );
      } else if (beforeNoteTarget != null) {
        final extent = resolve(noteExtent);
        final anchor = resolve(noteAnchor);
        final extentTarget = extent == null
            ? null
            : _noteTargetAt(extent.paragraph, extent.offset);
        final anchorTarget = anchor == null
            ? null
            : _noteTargetAt(anchor.paragraph, anchor.offset);
        if (extentTarget != null) {
          final sameNote =
              anchorTarget != null &&
              identical(anchorTarget.note, extentTarget.note);
          afterNoteTarget = (
            note: extentTarget.note,
            selection: beforeNoteTarget.selection.copyWith(
              baseOffset: sameNote
                  ? anchorTarget.selection.extentOffset
                  : extentTarget.selection.extentOffset,
              extentOffset: extentTarget.selection.extentOffset,
            ),
            composing: TextRange.empty,
          );
        } else if (extent != null && paragraphs.contains(extent.paragraph)) {
          // A removed or converted sole citation note returns to its body
          // anchor. Never retain a Notes selection into a detached note.
          afterExtent = bodyPosition(
            extent,
            fallbackParagraph: afterExtent.paragraph,
            fallbackOffset: afterExtent.offset,
          );
          afterAnchor = anchor != null && paragraphs.contains(anchor.paragraph)
              ? bodyPosition(
                  anchor,
                  fallbackParagraph: afterExtent.paragraph,
                  fallbackOffset: afterExtent.offset,
                )
              : afterExtent;
        } else {
          afterNoteTarget = _clampNoteEditingTarget(beforeNoteTarget);
        }
      }
      after = _ZoteroDocumentSnapshot.capture(document);
    } finally {
      before.restore(document);
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          after.restore(document);
          caret
            ..paragraphIndex = afterExtent.paragraph
            ..logicalIndex = afterExtent.offset
            ..selectionAnchorParagraph = afterAnchor.paragraph
            ..selectionAnchor = afterAnchor.offset
            ..resetBlink();
          _restoreNoteEditingTarget(afterNoteTarget);
          // Redo must retain the transformed selection, including direction.
          _historyRestoredSelection = true;
        },
        undoFn: () {
          before.restore(document);
          caret.paragraphIndex = beforeParagraph;
          caret.logicalIndex = beforeCaret;
          caret.selectionAnchor = beforeAnchor;
          caret.selectionAnchorParagraph = beforeAnchorParagraph;
          _restoreNoteEditingTarget(beforeNoteTarget);
          _historyRestoredSelection = true;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// Inserts a Zotero citation and its embedded CSL data as one undo step.
  /// Display text is supplied explicitly; this does not run a CSL processor.
  void insertZoteroCitation(ZoteroCitation citation) {
    if (_disposed || !config.allowsMutation) return;
    final noteTarget = noteEditingTarget;
    _assertNoteTargetReady(noteTarget);
    if (!(noteTarget?.selection.isCollapsed ?? caret.isCollapsed)) {
      throw UnsupportedError('Place the caret where the citation should go.');
    }
    if (zoteroFields.any(
      (field) => field.citation?.citationId == citation.citationId,
    )) {
      throw ArgumentError('A citation with this identity already exists.');
    }
    final noteRange = noteTarget == null
        ? null
        : _noteSelectionRange(noteTarget);
    if (noteTarget != null && noteRange == null) {
      throw UnsupportedError('Place the caret in an editable note paragraph.');
    }
    final paragraph = noteRange?.paragraph ?? _activeParagraph;
    if (zoteroFields.any(
      (field) =>
          field.paragraphs.length > 1 && field.paragraphs.contains(paragraph),
    )) {
      throw UnsupportedError(
        'Move the caret outside the multi-paragraph Zotero field.',
      );
    }
    final at = WmlRunEdit.normalizeRange(
      paragraph,
      noteRange?.start ?? caret.logicalIndex,
      noteRange?.start ?? caret.logicalIndex,
    ).start;
    final beforeLength = paragraph.text.length;
    _commitZoteroChange(
      <WmlParagraph>[paragraph],
      () => WordZotero.insertCitation(paragraph, citation, index: at),
      commitNoteDrafts: noteTarget != null,
      noteTargetAfter: noteTarget == null
          ? null
          : () => _noteTargetAt(
              paragraph,
              at + paragraph.text.length - beforeLength,
            ),
    );
    if (noteTarget == null) {
      caret.logicalIndex = at + paragraph.text.length - beforeLength;
      caret.collapseSelection();
    }
    relayout();
    notifyListeners();
  }

  /// Replaces one managed citation while retaining ordinary document text.
  void updateZoteroCitation(WmlZoteroField field, ZoteroCitation citation) {
    if (_disposed || !config.allowsMutation) return;
    _assertZoteroFieldOwner(field);
    if (field.citation?.citationId != citation.citationId) {
      throw ArgumentError('An edited citation must retain its identity.');
    }
    _commitZoteroChange(field.paragraphs, () {
      WordZotero.updateCitation(field, citation);
    });
  }

  /// Refreshes a prepared set of citation caches atomically. All network work
  /// must finish before this call; any unsupported field leaves every cache
  /// and the undo history unchanged.
  void refreshZoteroCitations(Map<String, ZoteroCitation> citations) {
    if (_disposed || !config.allowsMutation || citations.isEmpty) return;
    final fields = zoteroFields
        .where((field) => citations.containsKey(field.citation?.citationId))
        .toList();
    if (fields.length != citations.length ||
        fields.any((field) => !field.canEdit)) {
      throw UnsupportedError(
        'Some citations changed or cannot be refreshed safely.',
      );
    }
    for (final field in fields) {
      final id = field.citation!.citationId;
      if (citations[id]!.citationId != id) {
        throw ArgumentError('A refreshed citation must retain its identity.');
      }
    }
    _commitZoteroChange(
      fields.expand((field) => field.paragraphs).toSet().toList(),
      () {
        // Replace later fields first so earlier offsets remain valid.
        for (final field in fields.reversed) {
          WordZotero.updateCitation(
            field,
            citations[field.citation!.citationId]!,
          );
        }
      },
    );
  }

  /// Creates an editable Zotero bibliography field from a complete result.
  void insertZoteroBibliography({
    required String text,
    Map<String, dynamic>? metadata,
    ZoteroFormattedText? formattedText,
  }) {
    if (_disposed || !config.allowsMutation) return;
    _assertZoteroTrackingMode();
    if (noteEditingTarget != null ||
        !caret.isCollapsed ||
        isEditingHeaderFooter ||
        isEditingComment ||
        editingFrame ||
        selectedFrame != null) {
      throw UnsupportedError(
        'Place the caret in the document body for a bibliography.',
      );
    }
    _insertBlocksAfterCurrent(<WmlBlock>[
      WordZotero.bibliography(
        text: text,
        metadata: metadata,
        formattedText: formattedText,
      ),
    ]);
  }

  /// Updates a bibliography only after its complete replacement is available.
  void updateZoteroBibliography(
    WmlZoteroField field, {
    required String text,
    Map<String, dynamic>? metadata,
    ZoteroFormattedText? formattedText,
  }) {
    if (_disposed || !config.allowsMutation) return;
    _assertZoteroFieldOwner(field);
    _commitZoteroChange(field.paragraphs, () {
      WordZotero.updateBibliography(
        field,
        text: text,
        metadata: metadata,
        formattedText: formattedText,
      );
    });
  }

  /// Explicitly converts a citation/bibliography to ordinary text, with undo.
  /// Damaged metadata is allowed only when its complete native result packet
  /// has an unambiguous structural owner; its cached text stays unchanged.
  void unlinkZoteroField(WmlZoteroField field) {
    if (_disposed || !config.allowsMutation) return;
    _assertZoteroFieldOwner(field);
    if (!field.isValid) {
      if (document.restrictEditing || !canEditZoteroFieldNatively(field)) {
        throw UnsupportedError(
          'This damaged Zotero reference does not have an editable, complete field result. Its text and metadata were kept unchanged.',
        );
      }
      WordZotero.assertCompleteNativeFields(document);
      WordZotero.nativeFieldOwners(document, [field]);
      _commitZoteroChange(
        field.paragraphs,
        () => WordZotero.unlinkNative(field, document: document),
      );
    } else {
      _commitZoteroChange(field.paragraphs, () => WordZotero.unlink(field));
    }
  }

  /// Converts all modeled Zotero citations and bibliographies to ordinary
  /// text in one undo step. Cached character/paragraph formatting, notes,
  /// other fields and document style preferences stay intact. A single unsafe
  /// field prevents the entire operation; no partial conversion is committed.
  /// Damaged metadata is allowed only for complete, exclusively owned native
  /// results, using the same structural checks as individual conversion.
  /// Returns the number of converted fields, or zero for an uneditable or
  /// citation-free document.
  int unlinkZoteroFields() {
    if (_disposed || !config.allowsMutation) return 0;
    _assertNoUnmodeledZoteroFields();
    final fields = zoteroFields;
    if (fields.isEmpty) return 0;
    _assertZoteroTrackingMode();
    if (document.restrictEditing) {
      throw UnsupportedError(
        'Use an editable document before unlinking citations.',
      );
    }
    if (fields.any(
      (field) => field.locked || field.nested || field.opaqueMetadata,
    )) {
      throw UnsupportedError(
        'Resolve locked, nested or unsupported Zotero fields before unlinking citations. No fields were changed.',
      );
    }
    final damaged = fields.where((field) => !field.isValid).toList();
    if (damaged.isNotEmpty) {
      if (damaged.any((field) => !canEditZoteroFieldNatively(field))) {
        throw UnsupportedError(
          'A damaged Zotero reference does not have a complete, safely owned field result. No fields were changed.',
        );
      }
      WordZotero.assertCompleteNativeFields(document);
      WordZotero.nativeFieldOwners(document, damaged);
    }
    final paragraphs = Set<WmlParagraph>.identity()
      ..addAll(fields.expand((field) => field.paragraphs));
    for (final paragraph in paragraphs) {
      WordContentControls.assertCanEdit(paragraph, 0, paragraph.text.length);
    }
    _commitZoteroChange(paragraphs.toList(), () {
      for (final field in fields.reversed) {
        if (field.isValid) {
          WordZotero.unlink(field);
        } else {
          WordZotero.unlinkNative(field, document: document);
        }
      }
    }, commitNoteDrafts: true);
    return fields.length;
  }

  void _assertNoUnmodeledZoteroFields() {
    final opaque = <WmlOpaqueBlock>[];
    _assertCompleteZoteroFieldPackets(document.paragraphs);
    void inspectParagraph(WmlParagraph paragraph) {
      opaque.addAll(
        paragraph.inlines.whereType<WmlOpaqueInline>().map(
          (inline) => inline.content,
        ),
      );
    }

    void inspectBlocks(Iterable<WmlBlock> blocks) {
      for (final block in WordTree.descendants(blocks)) {
        if (block is WmlOpaqueBlock) opaque.add(block);
        if (block is WmlParagraph) inspectParagraph(block);
      }
    }

    for (final section in document.sections) {
      inspectBlocks(section.blocks);
      final stories = <String, List<WmlParagraph>>{
        'header': section.header,
        'footer': section.footer,
        'firstHeader': section.firstHeader,
        'firstFooter': section.firstFooter,
        'evenHeader': section.evenHeader,
        'evenFooter': section.evenFooter,
      };
      for (final entry in stories.entries) {
        _assertCompleteZoteroFieldPackets(entry.value);
        for (final paragraph in entry.value) {
          inspectParagraph(paragraph);
        }
        // A modeled replacement supersedes the preserved original story.
        final preserved = section.preservedStories[entry.key];
        if (entry.value.isEmpty && preserved != null) opaque.add(preserved);
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      _assertCompleteZoteroFieldPackets(note.allParagraphs);
      inspectBlocks(note.blocks);
    }
    for (final comment in document.comments) {
      _assertCompleteZoteroFieldPackets(comment.paragraphs);
      for (final paragraph in comment.paragraphs) {
        inspectParagraph(paragraph);
      }
    }
    if (opaque.any(_opaqueContainsZoteroField)) {
      throw UnsupportedError(
        'This document contains Zotero fields in preserved content that cannot be unlinked here. Resolve those fields in the original word processor first. No fields were changed.',
      );
    }
  }

  static void _assertCompleteZoteroFieldPackets(
    Iterable<WmlParagraph> paragraphs,
  ) {
    final open = <({StringBuffer code, bool separated})>[];
    final detached = StringBuffer();
    void rejectZotero(StringBuffer code) {
      if (WordZotero.kindOfInstruction(code.toString()) != null) {
        throw UnsupportedError(
          'Resolve incomplete Zotero field boundaries before unlinking citations. No fields were changed.',
        );
      }
    }

    void flushDetached() {
      rejectZotero(detached);
      detached.clear();
    }

    // Field enumeration intentionally exposes only complete complex packets.
    // Check incomplete or detached instructions separately, otherwise a batch
    // could unlink the valid fields while leaving an unreported citation.
    for (final paragraph in paragraphs) {
      for (final inline in paragraph.inlines) {
        if (inline is! WmlFieldBoundary) {
          flushDetached();
          continue;
        }
        if (inline.kind != WmlFieldBoundaryKind.instruction) flushDetached();
        switch (inline.kind) {
          case WmlFieldBoundaryKind.begin:
            open.add((code: StringBuffer(), separated: false));
          case WmlFieldBoundaryKind.instruction:
            (open.isEmpty ? detached : open.last.code).write(inline.text);
          case WmlFieldBoundaryKind.separate:
            if (open.isNotEmpty) {
              final field = open.removeLast();
              open.add((code: field.code, separated: true));
            }
          case WmlFieldBoundaryKind.end:
            if (open.isNotEmpty) {
              final field = open.removeLast();
              if (!field.separated) rejectZotero(field.code);
            }
        }
      }
    }
    flushDetached();
    for (final field in open) {
      rejectZotero(field.code);
    }
  }

  static bool _opaqueContainsZoteroField(WmlOpaqueBlock content) {
    // Inspect native field instructions, never visible prose or unrelated
    // fields that merely quote the word Zotero. Complex instructions can be
    // split across several runs and may contain nested field packets.
    final root = XmlDocument.parse(content.xml).root;
    if (root == null) return false;
    final instructions = <StringBuffer>[];
    final detached = StringBuffer();
    var found = false;
    bool isWord(XmlElement element) =>
        element.namespaceUri == OfficeNamespaces.w ||
        (element.namespaceUri.isEmpty && element.prefix == 'w');
    String? attribute(XmlElement element, String name) => element.attributes
        .where(
          (value) =>
              value.localName == name &&
              (value.namespaceUri == OfficeNamespaces.w ||
                  (value.namespaceUri.isEmpty && value.prefix == 'w')),
        )
        .firstOrNull
        ?.value;
    void finish(StringBuffer instruction) {
      if (WordZotero.kindOfInstruction(instruction.toString()) != null) {
        found = true;
      }
    }

    void visit(XmlElement element) {
      if (isWord(element)) {
        if (element.localName == 'fldSimple' &&
            WordZotero.kindOfInstruction(attribute(element, 'instr')) != null) {
          found = true;
        } else if (element.localName == 'fldChar') {
          switch (attribute(element, 'fldCharType')) {
            case 'begin':
              instructions.add(StringBuffer());
            case 'separate':
              if (instructions.isNotEmpty) finish(instructions.last);
            case 'end':
              if (instructions.isNotEmpty) finish(instructions.removeLast());
          }
        } else if (element.localName == 'instrText') {
          (instructions.isEmpty ? detached : instructions.last).write(
            element.text,
          );
        }
      }
      for (final child in element.childElements) {
        visit(child);
      }
    }

    visit(root);
    finish(detached);
    for (final instruction in instructions) {
      finish(instruction);
    }
    return found;
  }

  void _assertZoteroFieldOwner(WmlZoteroField field) {
    final owners = zoteroFields.where(
      (current) =>
          identical(current.paragraph, field.paragraph) &&
          current.start == field.start &&
          current.end == field.end &&
          current.instruction == field.instruction &&
          current.cachedText == field.cachedText,
    );
    if (owners.take(2).length != 1) {
      throw StateError(
        'This Zotero field no longer has one owner in the current document.',
      );
    }
  }

  void _commitZoteroChange(
    List<WmlParagraph> paragraphs,
    VoidCallback mutate, {
    bool commitNoteDrafts = false,
    WordNoteEditingTarget? Function()? noteTargetAfter,
  }) {
    _assertZoteroTrackingMode();
    final beforeNoteTarget = noteEditingTarget;
    _assertNoteTargetReady(beforeNoteTarget);
    final touched = Set<WmlParagraph>.identity()..addAll(paragraphs);
    if (document.revisions.any(
      (revision) =>
          revision.accepted == null &&
          touched.contains(
            revision.targetParagraph ??
                WordRevisions.resolveParagraph(document, revision),
          ),
    )) {
      throw UnsupportedError(
        'Accept or reject tracked changes in this paragraph before editing Zotero fields.',
      );
    }
    final before =
        <
          WmlParagraph,
          ({List<WmlInline> inlines, WmlParagraphProps properties})
        >{
          for (final paragraph in paragraphs)
            paragraph: (
              inlines: _cloneInlines(paragraph),
              properties: paragraph.properties.copy(),
            ),
        };
    void restore(
      Map<
        WmlParagraph,
        ({List<WmlInline> inlines, WmlParagraphProps properties})
      >
      snapshot,
    ) {
      for (final entry in snapshot.entries) {
        entry.key.properties = entry.value.properties.copy();
        entry.key.inlines
          ..clear()
          ..addAll(_cloneInlinesFrom(entry.value.inlines));
      }
    }

    late final Map<
      WmlParagraph,
      ({List<WmlInline> inlines, WmlParagraphProps properties})
    >
    after;
    WordNoteEditingTarget? afterNoteTarget;
    try {
      mutate();
      afterNoteTarget = noteTargetAfter != null
          ? noteTargetAfter()
          : _clampNoteEditingTarget(beforeNoteTarget);
      after = {
        for (final paragraph in paragraphs)
          paragraph: (
            inlines: _cloneInlines(paragraph),
            properties: paragraph.properties.copy(),
          ),
      };
    } finally {
      restore(before);
    }
    // Finish existing note drafts only after the complete operation has been
    // staged successfully. A failed preflight must preserve pending history,
    // while undo of a successful bulk conversion must restore its field links
    // before undoing an older note edit.
    if (commitNoteDrafts || beforeNoteTarget != null) commitNoteEdits();
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore(after);
          if (beforeNoteTarget != null) {
            _restoreNoteEditingTarget(afterNoteTarget);
            _historyRestoredSelection = true;
          }
        },
        undoFn: () {
          restore(before);
          if (beforeNoteTarget != null) {
            _restoreNoteEditingTarget(beforeNoteTarget);
            _historyRestoredSelection = true;
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  void _assertZoteroTrackingMode() {
    if (document.trackRevisions) {
      throw UnsupportedError(
        'Turn off Track changes before changing Zotero fields.',
      );
    }
  }

  /// markIndexTerm API.
  void markIndexTerm(String term) {
    if (!config.allowsMutation || term.trim().isEmpty) {
      return;
    }
    final int index = document.paragraphs.toList().indexOf(_activeParagraph);
    final WmlIndexMark mark = WmlIndexMark(
      term: term,
      paragraphIndex: index < 0 ? 0 : index,
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () => document.indexMarks.add(mark),
        undoFn: () => document.indexMarks.remove(mark),
      ),
    );
    relayout();
    notifyListeners();
  }

  /// insertIndex API.
  void insertIndex() {
    if (!config.allowsMutation) {
      return;
    }
    _insertBlocksAfterCurrent(<WmlBlock>[WordCitations.index(document)]);
  }

  /// mergeMail API.
  void mergeMail(Map<String, String> record) {
    if (!config.allowsMutation) {
      return;
    }
    WordMailMerge.merge(document, record);
    relayout();
    notifyListeners();
  }

  /// Compares [original] with this document without changing either input,
  /// pending revisions, history, or selection. Available in read-only modes.
  WordComparisonResult compareWith(
    WmlDocument original, {
    WordComparisonOptions options = const WordComparisonOptions(),
  }) => WordDocumentComparison.compare(original, document, options: options);

  /// setRestrictEditing API.
  void setRestrictEditing(bool value, {WmlRestrictMode? mode}) {
    if (!canChangeProtection) return;
    final target = document;
    final before = target.restrictEditing;
    final beforeMode = target.restrictMode;
    final nextMode =
        mode ??
        (value && beforeMode == WmlRestrictMode.none
            ? WmlRestrictMode.readOnly
            : beforeMode);
    if (before == value && beforeMode == nextMode) return;
    commitPendingEdits();
    void apply(bool enabled, WmlRestrictMode restriction) {
      target.restrictEditing = enabled;
      target.restrictMode = restriction;
      _syncProtectionMode();
    }

    commands.commit(
      _WordProtectionCommand(
        executeFn: () => apply(value, nextMode),
        undoFn: () => apply(before, beforeMode),
      ),
    );
  }

  /// previewMailMerge API.
  void previewMailMerge(List<Map<String, String>> records, {int index = 0}) {
    if (!config.allowsMutation) {
      return;
    }
    WordMailMerge.preview(document, records, index);
    relayout();
    notifyListeners();
  }

  /// printPreviewPages API.
  List<LaidOutPage> printPreviewPages({
    OfficePrintSettings settings = const OfficePrintSettings(),
  }) {
    return OfficePrint.wordPreview(document, settings: settings);
  }

  /// setWatermark API.
  void setWatermark(String text) {
    if (!config.allowsMutation) {
      return;
    }
    final String before = document.watermark;
    commands.commit(
      _CallbackCommand(
        executeFn: () => document.watermark = text,
        undoFn: () => document.watermark = before,
      ),
    );
    notifyListeners();
  }

  /// applyList API.
  void applyList({required bool numbered, int level = 0}) {
    if (!config.allowsMutation) {
      return;
    }
    applyParagraphFormat((WmlParagraphProps props) {
      final WmlParagraph paragraph = WmlParagraph(properties: props);
      WordLists.applyLevel(
        paragraph,
        numbered: numbered,
        level: level,
        document: document,
      );
    });
  }

  /// setParagraphIndent API.
  void setParagraphIndent({
    double? left,
    double? right,
    double? firstLine,
    double? hanging,
  }) {
    applyParagraphFormat((WmlParagraphProps props) {
      final WmlIndent current = props.indent;
      props.indent = WmlIndent(
        left: left ?? current.left,
        right: right ?? current.right,
        firstLine: firstLine ?? current.firstLine,
        hanging: hanging ?? current.hanging,
      );
    });
  }

  /// addTabStop API.
  void addTabStop(
    double position, {
    WmlTabAlignment alignment = WmlTabAlignment.left,
  }) {
    applyParagraphFormat((WmlParagraphProps props) {
      props.tabs.add(WmlTabStop(position: position, alignment: alignment));
    });
  }

  List<WmlParagraph> _rulerTargets = <WmlParagraph>[];
  final Map<WmlParagraph, WmlParagraphProps> _rulerParaSnap =
      <WmlParagraph, WmlParagraphProps>{};
  WmlSection? _rulerSection;
  WmlPageMargins? _rulerMarginSnap;
  var _rulerLive = false;

  /// beginRulerEdit API.
  void beginRulerEdit() {
    if (!config.allowsMutation) {
      return;
    }
    final List<WmlParagraph> paras = _paragraphs;
    if (paras.isEmpty) {
      return;
    }
    final int start;
    final int end;
    if (caret.isCollapsed) {
      start = caret.paragraphIndex.clamp(0, paras.length - 1);
      end = start;
    } else {
      final ({int startPara, int startIdx, int endPara, int endIdx}) range =
          caret.normalizedRange;
      start = range.startPara.clamp(0, paras.length - 1);
      end = range.endPara.clamp(0, paras.length - 1);
    }
    _rulerTargets = <WmlParagraph>[for (int i = start; i <= end; i++) paras[i]];
    _rulerParaSnap
      ..clear()
      ..addEntries(
        _rulerTargets.map(
          (WmlParagraph p) =>
              MapEntry<WmlParagraph, WmlParagraphProps>(p, p.properties.copy()),
        ),
      );
    _rulerSection = sectionAtCaret;
    _rulerMarginSnap = _rulerSection!.margins;
    _rulerLive = true;
  }

  /// previewRulerEdit API.
  void previewRulerEdit(WordRulerEdit edit) {
    if (!_rulerLive || !config.allowsMutation) {
      return;
    }
    if (edit.indent != null) {
      for (final WmlParagraph para in _rulerTargets) {
        para.properties.indent = edit.indent!;
      }
    }
    if (edit.tabs != null) {
      for (final WmlParagraph para in _rulerTargets) {
        para.properties.tabs
          ..clear()
          ..addAll(edit.tabs!);
      }
    }
    if (edit.margins != null && _rulerSection != null) {
      _rulerSection!.margins = edit.margins!;
    }
    relayout(localEdit: edit.margins == null, dirty: _rulerTargets);
    notifyListeners();
  }

  /// commitRulerEdit API.
  void commitRulerEdit() {
    if (!_rulerLive) {
      return;
    }
    final List<WmlParagraph> targets = List<WmlParagraph>.from(_rulerTargets);
    final Map<WmlParagraph, WmlParagraphProps> before =
        Map<WmlParagraph, WmlParagraphProps>.from(_rulerParaSnap);
    final Map<WmlParagraph, WmlParagraphProps> after =
        <WmlParagraph, WmlParagraphProps>{
          for (final WmlParagraph p in targets) p: p.properties.copy(),
        };
    final WmlSection? section = _rulerSection;
    final WmlPageMargins? marginBefore = _rulerMarginSnap;
    final WmlPageMargins? marginAfter = section?.margins;
    _rulerLive = false;
    _rulerTargets = <WmlParagraph>[];
    _rulerParaSnap.clear();
    _rulerSection = null;
    _rulerMarginSnap = null;
    var changed = false;
    for (final WmlParagraph p in targets) {
      final WmlParagraphProps? snap = before[p];
      if (snap == null) {
        continue;
      }
      if (snap.indent.left != p.properties.indent.left ||
          snap.indent.right != p.properties.indent.right ||
          snap.indent.firstLine != p.properties.indent.firstLine ||
          snap.indent.hanging != p.properties.indent.hanging ||
          snap.tabs.length != p.properties.tabs.length ||
          List<int>.generate(snap.tabs.length, (index) => index).any(
            (index) =>
                snap.tabs[index].position !=
                    p.properties.tabs[index].position ||
                snap.tabs[index].alignment !=
                    p.properties.tabs[index].alignment ||
                snap.tabs[index].leader != p.properties.tabs[index].leader,
          )) {
        changed = true;
        break;
      }
    }
    if (marginBefore != null &&
        marginAfter != null &&
        !marginBefore.matches(marginAfter)) {
      changed = true;
    }
    if (!changed) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final WmlParagraph p in targets) {
            final WmlParagraphProps? props = after[p];
            if (props != null) {
              p.properties = props.copy();
            }
          }
          if (section != null && marginAfter != null) {
            section.margins = marginAfter;
          }
        },
        undoFn: () {
          for (final MapEntry<WmlParagraph, WmlParagraphProps> e
              in before.entries) {
            e.key.properties = e.value.copy();
          }
          if (section != null && marginBefore != null) {
            section.margins = marginBefore;
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// setTrackRevisions API.
  void setTrackRevisions(bool value) {
    if (!config.allowsMutation || document.trackRevisions == value) {
      return;
    }
    final bool before = document.trackRevisions;
    commands.commit(
      _CallbackCommand(
        executeFn: () => document.trackRevisions = value,
        undoFn: () => document.trackRevisions = before,
      ),
    );
    notifyListeners();
  }

  /// acceptAllRevisions API.
  void acceptAllRevisions() {
    acceptRevisions(document.revisions);
  }

  /// rejectAllRevisions API.
  void rejectAllRevisions() {
    rejectRevisions(document.revisions);
  }

  /// The selected pending change, or the first pending change for legacy
  /// accept/reject toolbar actions when no explicit selection exists.
  WmlRevision? get selectedRevision {
    final int? index = selectedRevisionIndex;
    if (index != null && index >= 0 && index < document.revisions.length) {
      final revision = document.revisions[index];
      if (revision.accepted == null) return revision;
    }
    for (final revision in document.revisions) {
      if (revision.accepted == null) return revision;
    }
    return null;
  }

  /// Selects a pending change and reveals its exact range when its story has
  /// an editable canvas. Unsupported stories remain selected for review.
  void selectRevision(WmlRevision revision) {
    final int index = document.revisions.indexOf(revision);
    if (index < 0 || revision.accepted != null) {
      selectedRevisionIndex = null;
      notifyListeners();
      return;
    }
    revealRevision(revision);
  }

  /// Moves through pending changes, wrapping at either end. With no explicit
  /// selection, Next starts at the first change and Previous at the last.
  void stepRevision(int delta) {
    if (delta == 0) return;
    final pending = document.revisions
        .where((revision) => revision.accepted == null)
        .toList();
    if (pending.isEmpty) {
      selectedRevisionIndex = null;
      notifyListeners();
      return;
    }
    final selected = selectedRevisionIndex;
    final current =
        selected != null &&
            selected >= 0 &&
            selected < document.revisions.length
        ? pending.indexOf(document.revisions[selected])
        : -1;
    final next = current < 0
        ? (delta > 0 ? delta - 1 : delta) % pending.length
        : (current + delta) % pending.length;
    selectRevision(pending[next]);
  }

  /// Selects and reveals the actual tracked span in its editing surface.
  /// Stale or conflicted ranges, active composition, disabled selection and
  /// unsupported/unrendered stories remain available in the review list;
  /// they never redirect to a matching body paragraph.
  bool revealRevision(WmlRevision revision) {
    final index = document.revisions.indexOf(revision);
    if (index < 0 || revision.accepted != null) return false;
    selectedRevisionIndex = index;
    if (!config.allowsSelection || _hasProofingComposition) {
      notifyListeners();
      return false;
    }
    commitPendingEdits();
    final paragraph = WordRevisions.resolveParagraph(document, revision);
    if (!document.revisions.contains(revision) ||
        revision.accepted != null ||
        revision.conflict != null ||
        paragraph == null ||
        revision.start < 0 ||
        revision.end < revision.start ||
        revision.end > paragraph.text.length ||
        paragraph.text.substring(revision.start, revision.end) !=
            revision.text) {
      notifyListeners();
      return false;
    }
    final revealed = _revealParagraphRange(
      paragraph,
      revision.start,
      revision.end,
    );
    if (!revealed) notifyListeners();
    return revealed;
  }

  /// The text a notes editor shows for [note]: one line per paragraph.
  String noteEditText(WmlNote note) => WordNotes.editableText(note);

  /// Current findings in exactly the UTF-16 text displayed by the Notes pane.
  /// Hidden reference spacing, inter-paragraph newlines and note ownership are
  /// accounted for; findings in tables or other non-editable note blocks are
  /// deliberately absent from this simple text surface.
  List<({WordProofingIssue issue, TextRange range})> proofingIssuesForNote(
    WmlNote note,
  ) {
    if (_disposed || !_ownsNote(note)) return const [];
    final session = _proofing;
    if (session == null) return const [];
    final result = <({WordProofingIssue issue, TextRange range})>[];
    for (final segment in _noteTextSegments(note)) {
      for (final issue in session.summary.issues) {
        final finding = issue.finding;
        if (!identical(issue.paragraph, segment.paragraph) ||
            finding.start < segment.hidden ||
            finding.end < finding.start ||
            finding.end > segment.paragraph.text.length ||
            !session.isCurrent(issue)) {
          continue;
        }
        result.add((
          issue: issue,
          range: TextRange(
            start: segment.start + finding.start - segment.hidden,
            end: segment.start + finding.end - segment.hidden,
          ),
        ));
      }
    }
    return List.unmodifiable(result);
  }

  /// Resolves a captured Notes finding across an unchanged note-history
  /// commit. Real edits, undo/redo, detached notes and provider changes retire
  /// the handle. The finding must still map to this note's editable text.
  WordProofingIssue? currentNoteProofingIssue(
    WmlNote note,
    WordProofingIssue issue,
  ) {
    if (_disposed || !_ownsNote(note)) return null;
    final current = _currentProofingIssue(issue);
    if (current == null) return null;
    return proofingIssuesForNote(
          note,
        ).any((entry) => identical(entry.issue, current))
        ? current
        : null;
  }

  WordProofingIssue? _currentProofingIssue(WordProofingIssue issue) {
    final session = _proofing;
    if (_disposed || session == null) return null;
    if (session.isCurrent(issue)) return issue;
    final alias = _noteProofingCommitAliases[issue];
    return alias != null && session.isCurrent(alias) ? alias : null;
  }

  WordNoteEditingTarget? _noteEditingTarget;
  Object? _noteBodyTarget;

  int _noteFocusRequest = 0;

  /// Monotonic focus request for hosts displaying the retained Notes target.
  /// The default Notes pane consumes this after its next layout.
  int get noteFocusRequest => _noteFocusRequest;

  /// Returns keyboard focus to the active body or Notes insertion point after
  /// closing host chrome. The focused surface retains ownership of its IME.
  void requestEditingFocus() {
    if (_disposed ||
        !config.allowsSelection ||
        (input.composing.isValid && !input.composing.isCollapsed)) {
      return;
    }
    final target = noteEditingTarget;
    if (target != null) {
      if ((target.composing.isValid && !target.composing.isCollapsed) ||
          !_ownsNote(target.note) ||
          !target.selection.isValid ||
          target.selection.end > noteEditText(target.note).length) {
        return;
      }
      if (!config.showNotesPane) {
        syncConfig(config.copyWith(showNotesPane: true));
      }
      _noteFocusRequest++;
      notifyListeners();
    } else {
      onRequestFocus?.call();
      _syncImeSelection();
    }
  }

  Object get _bodyEditingPosition => (
    document: document,
    caret: documentCaret,
    paragraph: documentCaret.paragraphIndex,
    offset: documentCaret.logicalIndex,
    anchorParagraph: documentCaret.selectionAnchorParagraph,
    anchorOffset: documentCaret.selectionAnchor,
  );

  /// The last active Notes selection, retained when focus moves to chrome or
  /// a citation dialog. Moving the body caret invalidates this target as well
  /// as calling [clearNoteEditingTarget] when the canvas receives input.
  WordNoteEditingTarget? get noteEditingTarget =>
      _noteBodyTarget == _bodyEditingPosition ? _noteEditingTarget : null;

  bool _ownsNote(WmlNote note) =>
      (note.endnote ? document.endnotes : document.footnotes).any(
        (candidate) => identical(candidate, note),
      );

  /// Publishes the Notes pane's actual selection without moving the body caret
  /// or changing document history. Hosts should update this on focus, selection
  /// and composition changes, and retain it while a ribbon command is running.
  void setNoteEditingTarget(
    WmlNote note,
    TextSelection selection, {
    TextRange composing = TextRange.empty,
  }) {
    if (_disposed) return;
    if (!_ownsNote(note)) {
      throw StateError('This note no longer belongs to the document.');
    }
    final length = noteEditText(note).length;
    if (!selection.isValid ||
        selection.end > length ||
        (composing.isValid && composing.end > length)) {
      throw ArgumentError('The note selection is outside its editable text.');
    }
    final next = (note: note, selection: selection, composing: composing);
    if (next == noteEditingTarget) return;
    _editingComment = false;
    _editingHeaderFooter = false;
    selectedVisual = null;
    selectedFrame = null;
    editingFrame = false;
    selectedEquation = null;
    selectedTable = null;
    selectedTableBand = null;
    _restoreNoteEditingTarget(next);
    notifyListeners();
  }

  /// Returns citation commands to the document canvas. Losing note focus to a
  /// toolbar or modal is deliberately not a reason to clear its selection.
  void clearNoteEditingTarget({bool notify = true}) {
    if (_noteEditingTarget == null) return;
    _noteEditingTarget = null;
    _noteBodyTarget = null;
    if (notify && !_disposed) notifyListeners();
  }

  void _restoreNoteEditingTarget(WordNoteEditingTarget? target) {
    _noteEditingTarget = target;
    _noteBodyTarget = target == null ? null : _bodyEditingPosition;
  }

  WordNoteEditingTarget? _clampNoteEditingTarget(
    WordNoteEditingTarget? target,
  ) {
    if (target == null || !_ownsNote(target.note)) return null;
    final length = noteEditText(target.note).length;
    return (
      note: target.note,
      selection: target.selection.copyWith(
        baseOffset: target.selection.baseOffset.clamp(0, length),
        extentOffset: target.selection.extentOffset.clamp(0, length),
      ),
      composing: TextRange.empty,
    );
  }

  /// Paragraph positions in exactly the text exposed by the Notes pane.
  /// WordNotes may omit one leading reference-space from the first paragraph.
  Iterable<({WmlParagraph paragraph, int start, int hidden})> _noteTextSegments(
    WmlNote note,
  ) sync* {
    final paragraphs = WordNotes.editableParagraphs(note);
    if (paragraphs.isEmpty) return;
    final hidden =
        paragraphs.map((p) => p.text).join('\n').length -
        noteEditText(note).length;
    var start = 0;
    for (var index = 0; index < paragraphs.length; index++) {
      final paragraph = paragraphs[index];
      final prefix = index == 0 ? hidden : 0;
      yield (paragraph: paragraph, start: start, hidden: prefix);
      start += paragraph.text.length - prefix + 1;
    }
  }

  ({WmlParagraph paragraph, int start, int end})? _noteSelectionRange(
    WordNoteEditingTarget target,
  ) {
    if (!_ownsNote(target.note) ||
        !target.selection.isValid ||
        target.selection.end > noteEditText(target.note).length) {
      return null;
    }
    for (final segment in _noteTextSegments(target.note)) {
      final end =
          segment.start + segment.paragraph.text.length - segment.hidden;
      if (target.selection.start >= segment.start &&
          target.selection.end <= end) {
        return (
          paragraph: segment.paragraph,
          start: target.selection.start - segment.start + segment.hidden,
          end: target.selection.end - segment.start + segment.hidden,
        );
      }
    }
    return null;
  }

  /// Research-content replacement may cross paragraph separators exposed by
  /// the Notes pane. Resolve each endpoint independently, including the hidden
  /// automatic-reference separator. The engine qualifies the actual block
  /// range; adjacent visible paragraphs can still be separated by a table or
  /// belong to different content controls in the native note story.
  ({WmlParagraph paragraph, WmlParagraph endParagraph, int start, int end})?
  _noteResearchSelectionRange(WordNoteEditingTarget target) {
    if (!_ownsNote(target.note) ||
        !target.selection.isValid ||
        target.selection.end > noteEditText(target.note).length) {
      return null;
    }
    ({WmlParagraph paragraph, int offset})? start;
    for (final segment in _noteTextSegments(target.note)) {
      final end =
          segment.start + segment.paragraph.text.length - segment.hidden;
      if (start == null &&
          target.selection.start >= segment.start &&
          target.selection.start <= end) {
        start = (
          paragraph: segment.paragraph,
          offset: target.selection.start - segment.start + segment.hidden,
        );
      }
      if (start != null &&
          target.selection.end >= segment.start &&
          target.selection.end <= end) {
        return (
          paragraph: start.paragraph,
          endParagraph: segment.paragraph,
          start: start.offset,
          end: target.selection.end - segment.start + segment.hidden,
        );
      }
    }
    return null;
  }

  WordNoteEditingTarget? _noteTargetAt(WmlParagraph paragraph, int offset) {
    for (final note in [...document.footnotes, ...document.endnotes]) {
      for (final segment in _noteTextSegments(note)) {
        if (!identical(segment.paragraph, paragraph)) continue;
        final position =
            segment.start +
            offset.clamp(segment.hidden, paragraph.text.length) -
            segment.hidden;
        return (
          note: note,
          selection: TextSelection.collapsed(offset: position),
          composing: TextRange.empty,
        );
      }
    }
    return null;
  }

  void _assertNoteTargetReady(WordNoteEditingTarget? target) {
    if (target == null) return;
    if (!_ownsNote(target.note) ||
        !target.selection.isValid ||
        target.selection.end > noteEditText(target.note).length) {
      throw StateError('The note or its selection changed. Select it again.');
    }
    if (target.composing.isValid && !target.composing.isCollapsed) {
      throw StateError('Finish composing the note text before citing.');
    }
  }

  final Map<WmlNote, _WordNoteEditSnapshot> _noteEditStart =
      <WmlNote, _WordNoteEditSnapshot>{};

  /// Replaces the editable text of [note], keeping its formatting, tables,
  /// pictures and links (see [WordNotes.editText]).
  ///
  /// Successive calls for the same note form one edit; [commitNoteEdit]
  /// records it as a single undo step. A pending edit is also committed by an
  /// edit of another note, [undo], and saving. The text and content revision
  /// change immediately, before the undo command is committed.
  void setNoteText(WmlNote note, String text) {
    if (!config.allowsMutation || WordNotes.editableText(note) == text) {
      return;
    }
    final beforeText = WordNotes.editableParagraphs(
      note,
    ).map((paragraph) => paragraph.text).toList();
    final paragraphs = note.allParagraphs.toList();
    final hasInlineControls = paragraphs.any(
      WordContentControls.hasInlineControls,
    );
    if (hasInlineControls &&
        text.split('\n').length != WordNotes.editableParagraphs(note).length) {
      throw UnsupportedError(
        'Changing paragraph boundaries in a note containing an inline '
        'content control is not supported.',
      );
    }
    if (hasInlineControls ||
        paragraphs.any(
          (paragraph) =>
              paragraph.inlines.whereType<WmlBookmarkBoundary>().isNotEmpty,
        )) {
      // Validate replacements and native range deletion before committing
      // another pending note or creating this note's history snapshot.
      WordNotes.editText(
        WmlNote(
          id: note.id,
          endnote: note.endnote,
          addReference: note.addReference,
          addReferenceSpace: note.addReferenceSpace,
          referencePropertiesXml: note.referencePropertiesXml,
          blocks: <WmlBlock>[
            for (final block in note.blocks) WmlClone.block(block),
          ],
        ),
        text,
      );
    }
    for (final WmlNote other in _noteEditStart.keys.toList()) {
      if (!identical(other, note)) {
        commitNoteEdit(other);
      }
    }
    _noteEditStart.putIfAbsent(
      note,
      () => _WordNoteEditSnapshot(note, document),
    );
    final Map<WmlParagraph, String> previousText = <WmlParagraph, String>{
      for (final paragraph in WordNotes.editableParagraphs(note))
        paragraph: paragraph.text,
    };
    WordNotes.editText(note, text);
    if (listEquals(
      beforeText,
      WordNotes.editableParagraphs(
        note,
      ).map((paragraph) => paragraph.text).toList(),
    )) {
      return;
    }
    for (final entry in previousText.entries) {
      WordRevisions.rebaseTextChange(document, entry.key, entry.value);
    }
    WordRevisions.markDetached(document);
    _contentRevision++;
    _dirty = true;
    relayout();
    notifyListeners();
  }

  /// Records every pending notes-pane edit as an undo step.
  void commitNoteEdits() {
    for (final WmlNote note in _noteEditStart.keys.toList()) {
      commitNoteEdit(note);
    }
  }

  @override
  /// Commits a pending notes-pane edit first, so it is the step undone.
  void undo() {
    if (config.allowsMutation) {
      commitNoteEdits();
      super.undo();
    } else if (config.enableUndo && canUndo) {
      beforeHistoryChange();
      commands.undo();
      afterHistoryChange();
    }
  }

  @override
  void redo() {
    if (config.allowsMutation) {
      // A new Notes draft is already document content. Record it first so
      // committing that new edit retires an older, incompatible redo branch.
      commitNoteEdits();
      super.redo();
    } else if (config.enableUndo && canRedo) {
      beforeHistoryChange();
      commands.redo();
      afterHistoryChange();
    }
  }

  /// Records the edit started by [setNoteText] as one undoable command.
  void commitNoteEdit(WmlNote note) {
    final _WordNoteEditSnapshot? before = _noteEditStart.remove(note);
    if (before == null) {
      return;
    }
    final _WordNoteEditSnapshot after = _WordNoteEditSnapshot(note, document);
    if (before.text == after.text &&
        listEquals(before.blocks, after.blocks) &&
        before.revisions.matches(document)) {
      return;
    }
    final session = _proofing;
    final checked = session == null
        ? const <WordProofingIssue>[]
        : session.summary.issues.where(session.isCurrent).toList();
    final previousAliases = Map<WordProofingIssue, WordProofingIssue>.of(
      _noteProofingCommitAliases,
    );
    final previousDocument = document;
    final previousRevision = contentRevision;
    void recordHistory() => commands.commit(
      _CallbackCommand(
        executeFn: () => after.restore(note, document),
        undoFn: () => before.restore(note, document),
      ),
    );
    if (session == null) {
      recordHistory();
    } else {
      session.preserveUnchangedHistory(recordHistory);
    }
    // A focus-loss history commit records text that was already applied and
    // checked while typing. Keep only capabilities validated immediately
    // before this exact boundary, never handles from an earlier source edit.
    _noteProofingCommitAliases.clear();
    if (session != null &&
        identical(session, _proofing) &&
        identical(previousDocument, document) &&
        contentRevision == previousRevision + 1) {
      final rebound = <WordProofingIssue, WordProofingIssue>{};
      for (final issue in checked) {
        final current = session.rebindUnchangedIssue(issue);
        if (current != null) rebound[issue] = current;
      }
      for (final entry in previousAliases.entries) {
        final current = rebound[entry.value];
        if (current != null) _noteProofingCommitAliases[entry.key] = current;
      }
      _noteProofingCommitAliases.addAll(rebound);
    }
  }

  /// Deletes [note] and its reference mark in the body, as one undo step.
  void deleteNote(WmlNote note) {
    if (!config.allowsMutation) {
      return;
    }
    commitNoteEdit(note);
    final List<WmlNote> bucket = note.endnote
        ? document.endnotes
        : document.footnotes;
    final int index = bucket.indexOf(note);
    if (index < 0) {
      return;
    }
    final WmlParagraph? anchor = WordNotes.paragraphOf(document, note);
    final WmlParagraphProps? anchorProps = anchor?.properties.copy();
    final List<WmlInline>? anchorInlines = anchor == null
        ? null
        : _cloneInlines(anchor);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          WordNotes.delete(document, note.id, endnote: note.endnote);
        },
        undoFn: () {
          bucket.insert(index.clamp(0, bucket.length), note);
          if (anchor != null) {
            anchor.properties = anchorProps!.copy();
            anchor.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(anchorInlines!));
          }
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  /// jumpToNote API.
  void jumpToNote(WmlNote note) {
    clearNoteEditingTarget();
    final List<WmlParagraph> paras = document.paragraphs.toList();
    for (int i = 0; i < paras.length; i++) {
      final WmlParagraph paragraph = paras[i];
      if (WordNotes.paragraphOf(document, note) == paragraph) {
        caret
          ..paragraphIndex = i
          ..logicalIndex = paragraph.text.length
          ..collapseSelection();
        break;
      }
    }
    notifyListeners();
  }

  /// setDifferentFirstPage API.
  void setDifferentFirstPage(bool value) {
    _setSectionFlag(
      value,
      (section) => section.differentFirstPage,
      (section, next) => section.differentFirstPage = next,
    );
  }

  /// setDifferentOddEven API.
  void setDifferentOddEven(bool value) {
    _setSectionFlag(
      value,
      (section) => section.differentOddEven,
      (section, next) => section.differentOddEven = next,
    );
  }

  /// setLinkToPrevious API.
  void setLinkToPrevious(bool value) {
    _setSectionFlag(
      value,
      (section) => section.linkToPrevious,
      (section, next) => section.linkToPrevious = next,
    );
  }

  /// Checks all modeled document stories, preserving provider availability and
  /// coverage. Findings never become document edits without an explicit choice.
  Future<WordProofingSummary> checkDocumentProofing() {
    final current = _explicitProofingCheck;
    if (current != null &&
        _explicitProofingGeneration == proofing.checkGeneration) {
      return current;
    }
    late final Future<WordProofingSummary> check;
    check = proofing.checkNow().whenComplete(() {
      if (identical(_explicitProofingCheck, check)) {
        _explicitProofingCheck = null;
        _explicitProofingGeneration = null;
      }
    });
    _explicitProofingCheck = check;
    _explicitProofingGeneration = proofing.checkGeneration;
    return check;
  }

  /// Current review selection, rebound after a check of unchanged text. A
  /// finding under the caret takes precedence, so the pane follows navigation
  /// without moving focus or interrupting typing.
  /// The issue last chosen with [selectProofingIssue], without validating it
  /// against the caret; cheap to read (no proofing capture), for change
  /// detection by host chrome.
  WordProofingIssue? get chosenProofingIssue => _selectedProofingIssue;

  WordProofingIssue? get selectedProofingIssue {
    final selected = _selectedProofingIssue;
    final atCaret = proofingIssuesAtCaret;
    WordProofingIssue? matching(Iterable<WordProofingIssue> issues) {
      if (selected == null) return null;
      for (final issue in issues) {
        if (identical(issue.paragraph, selected.paragraph) &&
            issue.sourceText == selected.sourceText &&
            issue.language == selected.language &&
            issue.finding.providerId == selected.finding.providerId &&
            issue.finding.ruleId == selected.finding.ruleId &&
            issue.finding.start == selected.finding.start &&
            issue.finding.end == selected.finding.end) {
          return issue;
        }
      }
      return null;
    }

    final explicit = matching(proofing.summary.issues);
    if (explicit != null && _proofingSelectionCaret == _proofingCaretPosition) {
      return explicit;
    }
    return matching(atCaret) ?? atCaret.firstOrNull ?? explicit;
  }

  ({WmlParagraph? paragraph, int offset, int? anchor, int? anchorParagraph})
  get _proofingCaretPosition {
    final note = noteEditingTarget;
    if (note != null) {
      final extent = _noteSelectionRange((
        note: note.note,
        selection: TextSelection.collapsed(offset: note.selection.extentOffset),
        composing: note.composing,
      ));
      final anchor = _noteSelectionRange((
        note: note.note,
        selection: TextSelection.collapsed(offset: note.selection.baseOffset),
        composing: note.composing,
      ));
      return (
        paragraph: extent?.paragraph,
        offset: extent?.start ?? 0,
        anchor: anchor?.start,
        anchorParagraph: anchor == null
            ? null
            : WordNotes.editableParagraphs(note.note).indexOf(anchor.paragraph),
      );
    }
    return _canvasCaretPosition;
  }

  // Thesaurus and other canvas commands still use their canvas caret; a Notes
  // proofing selection must never combine note text with body caret offsets.
  ({WmlParagraph? paragraph, int offset, int? anchor, int? anchorParagraph})
  get _canvasCaretPosition {
    final paragraphs = _paragraphs;
    final current = caret;
    final index = current.paragraphIndex;
    return (
      paragraph: index >= 0 && index < paragraphs.length
          ? paragraphs[index]
          : null,
      offset: current.logicalIndex,
      anchor: current.selectionAnchor,
      anchorParagraph: current.selectionAnchorParagraph,
    );
  }

  /// Selects a current finding. Unsupported canvas stories stay selected in
  /// the pane; false means that no source range could be revealed.
  bool selectProofingIssue(WordProofingIssue issue, {bool reveal = true}) {
    final current = _currentProofingIssue(issue);
    if (current == null) return false;
    _selectedProofingIssue = current;
    final shown = reveal && revealProofingIssue(current);
    _proofingSelectionCaret = _proofingCaretPosition;
    if (!shown) notifyListeners();
    return shown;
  }

  /// Advances through the current findings, wrapping at either end.
  void stepProofingIssue(int delta) {
    if (delta == 0 || isDisposed) return;
    final issues = proofing.summary.issues;
    if (issues.isEmpty) return;
    final selected = selectedProofingIssue;
    final current = selected == null ? -1 : issues.indexOf(selected);
    final next = current < 0
        ? (delta > 0 ? delta - 1 : delta) % issues.length
        : (current + delta) % issues.length;
    selectProofingIssue(issues[next]);
  }

  /// The selected text, or the whole paragraph when the caret is collapsed.
  ///
  /// This inspection never creates a paragraph or changes selection/history.
  /// Object selections, empty text and unsupported stories return null.
  WordTextProofingTarget? get textProofingTarget {
    if (isDisposed ||
        selectedVisual != null ||
        selectedEquation != null ||
        (selectedFrame != null && !editingFrame) ||
        selectedTable != null ||
        selectedTableBand != null ||
        _noteEditStart.isNotEmpty) {
      return null;
    }
    final current = caret;
    final note = noteEditingTarget;
    final noteSegments = note == null
        ? null
        : _noteTextSegments(note.note).toList();
    var selection = current.normalizedRange;
    final collapsed = note?.selection.isCollapsed ?? current.isCollapsed;
    if (note != null) {
      // Notes owns a separate, flattened UTF-16 selection. Never pair it with
      // the retained canvas caret, even after the note's typing is committed.
      final start = _noteSelectionRange((
        note: note.note,
        selection: TextSelection.collapsed(offset: note.selection.start),
        composing: note.composing,
      ));
      final end = _noteSelectionRange((
        note: note.note,
        selection: TextSelection.collapsed(offset: note.selection.end),
        composing: note.composing,
      ));
      if (start == null || end == null) return null;
      selection = (
        startPara: noteSegments!.indexWhere(
          (segment) => identical(segment.paragraph, start.paragraph),
        ),
        startIdx: start.start,
        endPara: noteSegments.indexWhere(
          (segment) => identical(segment.paragraph, end.paragraph),
        ),
        endIdx: end.end,
      );
    }
    final startParagraph = selection.startPara;
    final endParagraph = selection.endPara;
    if (startParagraph < 0 || endParagraph < startParagraph) return null;
    final entries = _textProofingStory.take(endParagraph + 1).toList();
    if (endParagraph >= entries.length) return null;
    if (collapsed &&
        (selection.startIdx < 0 ||
            selection.startIdx >
                entries[startParagraph].paragraph.text.length)) {
      return null;
    }
    final ranges = <_WordTextProofingRange>[];
    final languages = <String>{};
    final scriptLanguages = <TextScript, Set<String>>{};
    final detectedLanguages = <TextScript, Set<String>>{};
    var detectionPending = false;
    final enabledValues = <bool>{};
    String? unavailable;
    if (!config.allowsMutation ||
        (document.restrictEditing &&
            (document.restrictMode != WmlRestrictMode.none ||
                document.protectionFormattingRestricted))) {
      unavailable = 'This document is read-only or protected.';
    } else if (_hasProofingComposition) {
      unavailable = 'Finish composing text before changing its options.';
    }
    var fieldDepth = 0;
    for (var index = 0; index <= endParagraph; index++) {
      final entry = entries[index];
      final paragraph = entry.paragraph;
      if (index < startParagraph) {
        // Earlier text is irrelevant except for complex fields that remain
        // open. Do not allocate its strings, properties or grapheme lists.
        for (final boundary
            in paragraph.inlines.whereType<WmlFieldBoundary>()) {
          if (boundary.kind == WmlFieldBoundaryKind.begin) fieldDepth++;
          if (boundary.kind == WmlFieldBoundaryKind.end && fieldDepth > 0) {
            fieldDepth--;
          }
        }
        continue;
      }
      final text = paragraph.text;
      final selected = index >= startParagraph;
      var from = collapsed || index != startParagraph
          ? (noteSegments?[index].hidden ?? 0)
          : selection.startIdx;
      var to = collapsed || index != endParagraph
          ? text.length
          : selection.endIdx;
      if (selected && (from < 0 || to > text.length || from > to)) return null;
      if (selected && from < to) {
        // An external host can supply a selection inside a UTF-16 grapheme.
        // Include the complete visible character instead of splitting it.
        for (final cluster in GraphemeClusters.segment(text)) {
          if (from > cluster.start && from < cluster.end) from = cluster.start;
          if (to > cluster.start && to < cluster.end) to = cluster.end;
        }
        if (entry.generated ||
            paragraph.properties.fieldInstruction != null ||
            paragraph.properties.pageNumberField) {
          unavailable ??=
              'Generated text does not have editable proofing options.';
        }
        if ([
          ...entry.controls,
          ...paragraph.contentControlWrappers,
        ].any(_textProofingControlLocked)) {
          unavailable ??= 'This text belongs to a protected content control.';
        }
        try {
          for (final span in WordContentControls.spans(paragraph)) {
            if (_textProofingControlLocked(span.control) &&
                from < span.end &&
                to > span.start) {
              unavailable ??=
                  'This text belongs to a protected content control.';
            }
          }
          final normalized = WmlRunEdit.normalizeRange(paragraph, from, to);
          if (normalized.start != from || normalized.end != to) {
            unavailable ??=
                'Select ordinary text outside fields and note marks.';
          }
        } on Object {
          unavailable ??= 'This text contains unsupported native content.';
        }
        ranges.add(
          _WordTextProofingRange(
            paragraph: paragraph,
            start: from,
            end: to,
            source: _textProofingSource(
              paragraph,
              entry.controls,
              entry.styleContext,
            ),
          ),
        );
        if (proofing.automaticLanguageDetection &&
            proofing.languageDetector != null) {
          final detection = proofing.detectedLanguages(text);
          if (detection == null) {
            detectionPending |= scriptSegments(
              text.substring(from, to),
            ).isNotEmpty;
          } else {
            for (final segment in detection.segments) {
              final language = segment.language;
              if (language == null ||
                  segment.end <= from ||
                  segment.start >= to) {
                continue;
              }
              detectedLanguages
                  .putIfAbsent(segment.script, () => <String>{})
                  .add(language);
            }
          }
        }
      }
      var offset = 0;
      for (final inline in paragraph.inlines) {
        if (inline is WmlFieldBoundary) {
          if (selected && from < to && offset > from && offset < to) {
            unavailable ??=
                'Select ordinary text outside fields and note marks.';
          }
          if (inline.kind == WmlFieldBoundaryKind.begin) fieldDepth++;
          if (inline.kind == WmlFieldBoundaryKind.end && fieldDepth > 0) {
            fieldDepth--;
          }
        } else if (inline is WmlRun) {
          final end = offset + inline.text.length;
          if (selected && from < end && to > offset) {
            final fragment = from <= offset && to >= end
                ? inline
                : WmlRun(
                    text: inline.text.substring(
                      (from - offset).clamp(0, inline.text.length),
                      (to - offset).clamp(0, inline.text.length),
                    ),
                    properties: inline.properties,
                  );
            final latinLanguage = normalizeProofingLanguage(
              inline.properties.proofingLanguage ??
                  paragraph.properties.proofingLanguage ??
                  document.proofingLanguage ??
                  'de-DE',
            );
            for (final segment in scriptSegments(fragment.text)) {
              final complex =
                  inline.properties.complexScript == true ||
                  segment.script.isComplex;
              scriptLanguages
                  .putIfAbsent(segment.script, () => <String>{})
                  .add(
                    complex
                        ? normalizeProofingLanguage(
                            inline.properties.complexScriptLanguage ??
                                document.complexScriptLanguage ??
                                latinLanguage,
                          )
                        : latinLanguage,
                  );
            }
            if (wordRunUsesLatinScriptLanguage(fragment)) {
              languages.add(
                normalizeProofingLanguage(
                  inline.properties.proofingLanguage ??
                      paragraph.properties.proofingLanguage ??
                      document.proofingLanguage ??
                      'de-DE',
                ),
              );
            }
            if (wordRunUsesComplexScriptLanguage(fragment)) {
              languages.add(
                normalizeProofingLanguage(
                  wordRunProofingLanguage(
                        fragment,
                        paragraph,
                        documentLanguage: document.proofingLanguage,
                        documentComplexScriptLanguage:
                            document.complexScriptLanguage,
                      ) ??
                      'de-DE',
                ),
              );
            }
            enabledValues.add(inline.properties.noProof != true);
            if (inline.isAtomic || fieldDepth > 0) {
              unavailable ??=
                  'Select ordinary text outside fields and note marks.';
            }
          }
          offset = end;
        } else if (selected &&
            from < to &&
            offset > from &&
            offset < to &&
            (inline is WmlOpaqueInline || inline is WmlObject)) {
          unavailable ??= 'This text contains unsupported native content.';
        }
      }
    }
    if (ranges.isEmpty) return null;
    return WordTextProofingTarget._(
      (
        controller: this,
        document: document,
        revision: contentRevision,
        caret: current,
        paragraph: current.paragraphIndex,
        offset: current.logicalIndex,
        anchorParagraph: current.selectionAnchorParagraph,
        anchor: current.selectionAnchor,
        comment: _editingComment ? selectedComment : null,
        section:
            _editingHeaderFooter &&
                _editingSectionIndex >= 0 &&
                _editingSectionIndex < document.sections.length
            ? document.sections[_editingSectionIndex]
            : null,
        footer: _editingFooter,
        headerFooterVariant: _editingHeaderFooterVariant,
        note: note,
        documentLanguage: document.proofingLanguage,
        documentComplexScriptLanguage: document.complexScriptLanguage,
        styles: _textProofingStylesToken,
        tracking: document.trackRevisions,
        restricted: document.restrictEditing,
        restriction: document.restrictMode,
        formattingRestricted: document.protectionFormattingRestricted,
      ),
      List.unmodifiable(ranges),
      isSelection: !collapsed,
      language: languages.length == 1 ? languages.single : null,
      checkingEnabled: enabledValues.length == 1 ? enabledValues.single : null,
      unavailableReason: unavailable,
      scriptLanguages: Map.unmodifiable({
        for (final entry in scriptLanguages.entries)
          entry.key: entry.value.length == 1 ? entry.value.single : null,
      }),
      detectedLanguages: Map.unmodifiable({
        for (final entry in detectedLanguages.entries)
          entry.key: entry.value.length == 1 ? entry.value.single : null,
      }),
      detectionPending: detectionPending,
    );
  }

  Iterable<_WordTextProofingParagraph> get _textProofingStory sync* {
    Iterable<_WordTextProofingParagraph> plain(
      Iterable<WmlParagraph> paragraphs,
    ) sync* {
      for (final paragraph in paragraphs) {
        yield (
          paragraph: paragraph,
          controls: const [],
          styleContext: const [],
          generated: false,
        );
      }
    }

    if (_editingComment) {
      final comment = selectedComment;
      if (comment != null) yield* plain(comment.paragraphs);
      return;
    }
    if (_editingHeaderFooter) {
      if (_editingSectionIndex < 0 ||
          _editingSectionIndex >= document.sections.length) {
        return;
      }
      final section = document.sections[_editingSectionIndex];
      yield* plain(_headerFooterStory(section));
      return;
    }
    Iterable<_WordTextProofingParagraph> visit(
      Iterable<WmlBlock> blocks,
      List<WmlContentControlData> controls,
      List<Object?> styleContext,
    ) sync* {
      for (final block in blocks) {
        if (block is WmlParagraph) {
          yield (
            paragraph: block,
            controls: controls,
            styleContext: styleContext,
            generated: false,
          );
        } else if (block is WmlContentControlBlock) {
          yield* visit(block.blocks, [
            ...controls,
            block.control,
          ], styleContext);
        } else if (block is WmlTable) {
          for (final row in block.rows.indexed) {
            for (final cell in row.$2.cells.indexed) {
              yield* visit(cell.$2.blocks, controls, [
                ...styleContext,
                [
                  block.properties.styleId,
                  block.properties.sourcePropertiesXml,
                  block.properties.importedValues,
                  row.$1,
                  cell.$1,
                ],
              ]);
            }
          }
        } else if (block is WmlToc) {
          for (final paragraph in [
            block.titleParagraph,
            ...block.itemParagraphs,
          ]) {
            yield (
              paragraph: paragraph,
              controls: controls,
              styleContext: styleContext,
              generated: true,
            );
          }
        } else {
          for (final children in WordTree.childLists(block)) {
            yield* visit(children, controls, styleContext);
          }
        }
      }
    }

    final note = noteEditingTarget;
    if (note != null) {
      if (!_ownsNote(note.note)) return;
      final editable = WordNotes.editableParagraphs(note.note).toSet();
      // Retain native block-control protection and style context, but expose
      // only the paragraphs actually present in the flat Notes field.
      yield* visit(
        note.note.blocks,
        const [],
        const [],
      ).where((entry) => editable.contains(entry.paragraph));
      return;
    }
    yield* visit(
      document.sections.expand((section) => section.blocks),
      const [],
      const [],
    );
  }

  // PackagePart replaces its payload on writes. Retaining its read-only view
  // identity detects style edits without copying/decoding an entire styles XML
  // on every caret or progress notification.
  Object? get _textProofingStylesToken {
    final package = document.package;
    if (package == null) return null;
    final office = package.packageRelationships.firstByType(
      RelationshipTypes.officeDocument,
    );
    final uri = office == null
        ? '/word/document.xml'
        : package.packageRelationships.resolve(office);
    final relationships = package.relationshipsFor(uri);
    final style = relationships.firstByType(RelationshipTypes.styles);
    final part = package.getPart(
      style == null ? '/word/styles.xml' : relationships.resolve(style),
    );
    return (package, part, part?.bytesView);
  }

  static bool _textProofingControlLocked(WmlContentControlData control) {
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

  static String _textProofingSource(
    WmlParagraph paragraph,
    List<WmlContentControlData> controls,
    List<Object?> styleContext,
  ) => jsonEncode([
    styleContext,
    paragraph.properties.styleId,
    paragraph.properties.sourcePropertiesXml,
    paragraph.properties.importedValues,
    paragraph.properties.proofingLanguage,
    paragraph.properties.fieldInstruction,
    paragraph.properties.pageNumberField,
    for (final control in [...controls, ...paragraph.contentControlWrappers])
      control.xml,
    for (final run in paragraph.inlines.whereType<WmlRun>())
      [
        run.text,
        run.properties.proofingLanguage,
        run.properties.complexScriptLanguage,
        run.properties.complexScript,
        run.properties.noProof,
        run.properties.styleId,
        run.properties.bold,
        run.properties.italic,
        run.properties.underline.name,
        run.properties.strike,
        run.properties.smallCaps,
        run.properties.allCaps,
        run.properties.color,
        run.properties.highlight,
        run.properties.fontSizeHalfPoints,
        run.properties.asciiFont,
        run.properties.csFont,
        run.properties.vertAlign.name,
        run.properties.positionHalfPoints,
        run.properties.sourcePropertiesXml,
        run.properties.importedValues,
        run.properties.explicitProperties.toList(),
        run.hyperlink?.anchor,
        run.hyperlink?.url,
        run.hyperlink?.file,
        run.commentIds,
        run.noteRefId,
        run.noteRefEndnote,
        run.noteRefCustomMark,
        run.fieldInstruction,
        run.fieldLocked,
        run.fieldDirty,
        run.inlineVisual != null,
      ],
  ]);

  /// Changes the active language slots of exactly [target], preserving inactive
  /// language metadata and other formatting. Unmarked mixed-script fragments
  /// use both slots. Null removes those overrides so the text inherits its
  /// character/paragraph styles and paragraph/document defaults. Set
  /// [activeLanguageOnly] to false to explicitly change or clear both slots.
  /// Returns false if the displayed target became stale or cannot be changed
  /// safely.
  bool setTextProofingLanguage(
    String? language, {
    required WordTextProofingTarget target,
    bool activeLanguageOnly = true,
  }) {
    final normalized = language == null
        ? null
        : normalizeProofingLanguage(language);
    if (normalized != null && normalized.isEmpty) return false;
    if (normalized == null) {
      final reader = WordDeserializer();
      final before = contentRevision;
      final applied = _setTextProofingOption(
        target,
        prepare: (source, preview, start, end) =>
            reader.clearRunProofingLanguage(
              document,
              source,
              preview,
              start,
              end,
              includeComplexScript: true,
              activeLanguageOnly: activeLanguageOnly,
            ),
      );
      if (applied && contentRevision != before) {
        final inherited = textProofingTarget;
        for (final tag in <String>{
          ...?inherited?.scriptLanguages.values.whereType<String>(),
          if (inherited?.language case final String tag) tag,
        }) {
          onProofingLanguageChanged?.call(tag);
        }
      }
      return applied;
    }
    final before = contentRevision;
    final applied = _setTextProofingOption(
      target,
      prepare: (source, preview, start, end) => activeLanguageOnly
          ? _prepareTextProofingLanguage(preview, start, end, normalized)
          : _prepareTextProofingRuns(
              preview,
              start,
              end,
              needsChange: (properties) =>
                  properties.proofingLanguage != normalized ||
                  properties.complexScriptLanguage != normalized,
              update: (properties) => properties
                ..proofingLanguage = normalized
                ..complexScriptLanguage = normalized,
            ),
    );
    if (applied && contentRevision != before) {
      onProofingLanguageChanged?.call(normalized);
    }
    return applied;
  }

  /// Runs automatic language detection for the paragraphs of [target] (when
  /// a detector is configured), so a fresh [textProofingTarget] shows the
  /// detected languages. Never changes the document.
  Future<void> detectTextProofingLanguages(
    WordTextProofingTarget target,
  ) async {
    final texts = {for (final range in target._ranges) range.paragraph.text};
    if (texts.isEmpty || proofing.languageDetector == null) return;
    await proofing.detectLanguages(texts.toList());
    if (!isDisposed) notifyListeners();
  }

  /// "Apply detected language": writes the detected language of each script
  /// segment of [target] into the document, `w:lang/@w:val` for Latin (and
  /// other non-complex) text and `w:lang/@w:bidi` for Arabic- and
  /// Hebrew-script text (or any run marked complex script). A slot whose
  /// language already has the detected primary subtag keeps its tag (so
  /// de-CH stays de-CH). One undoable history command covers the selection.
  /// Returns false when the target is stale, not editable or has no
  /// detection; true (possibly without changes) otherwise.
  bool applyDetectedTextProofingLanguages({
    required WordTextProofingTarget target,
  }) {
    if (target.detectedLanguages.isEmpty) return false;
    final documentLanguage = document.proofingLanguage;
    final documentComplex = document.complexScriptLanguage;
    final before = contentRevision;
    final applied = _setTextProofingOption(
      target,
      prepare: (source, preview, start, end) {
        final detection = proofing.detectedLanguages(source.text);
        if (detection == null) return false;
        var changed = false;
        for (final segment in detection.segments) {
          final detected = segment.language;
          if (detected == null) continue;
          final from = segment.start < start ? start : segment.start;
          final to = segment.end > end ? end : segment.end;
          if (from >= to) continue;
          final tag = normalizeProofingLanguage(
            wordLanguageTagForDetected(detected),
          );
          final range = WmlRunEdit.normalizeRange(preview, from, to);
          if (range.start == range.end) continue;
          WmlRunEdit.splitProofingRange(preview, range.start, range.end);
          final latin = <WmlRunProps>{};
          final complex = <WmlRunProps>{};
          var offset = 0;
          for (final run in preview.inlines.whereType<WmlRun>()) {
            final runEnd = offset + run.text.length;
            if (offset >= range.start &&
                runEnd <= range.end &&
                runEnd > offset) {
              final useComplex =
                  run.properties.complexScript == true ||
                  segment.script.isComplex;
              final uses = useComplex
                  ? wordRunUsesComplexScriptLanguage(run)
                  : wordRunUsesLatinScriptLanguage(run);
              final current = useComplex
                  ? run.properties.complexScriptLanguage ?? documentComplex
                  : run.properties.proofingLanguage ??
                        preview.properties.proofingLanguage ??
                        documentLanguage;
              if (uses &&
                  (current == null ||
                      primaryLanguageSubtag(current) !=
                          primaryLanguageSubtag(tag))) {
                (useComplex ? complex : latin).add(run.properties);
              }
            }
            offset = runEnd;
          }
          if (latin.isEmpty && complex.isEmpty) continue;
          changed |= _prepareTextProofingRuns(
            preview,
            range.start,
            range.end,
            needsChange: (properties) =>
                latin.contains(properties) || complex.contains(properties),
            update: (properties) {
              if (complex.contains(properties)) {
                properties.complexScriptLanguage = tag;
              } else {
                properties.proofingLanguage = tag;
              }
            },
          );
        }
        return changed;
      },
    );
    if (applied && contentRevision != before) {
      for (final language
          in target.detectedLanguages.values.whereType<String>().toSet()) {
        onProofingLanguageChanged?.call(language);
      }
    }
    return applied;
  }

  /// Includes or excludes exactly [target] in document proofing. One history
  /// command covers the complete selection, without changing its text.
  bool setTextProofingEnabled(
    bool enabled, {
    required WordTextProofingTarget target,
  }) => _setTextProofingOption(
    target,
    prepare: (source, preview, start, end) => _prepareTextProofingRuns(
      preview,
      start,
      end,
      needsChange: (properties) => (properties.noProof != true) != enabled,
      update: (properties) => properties.noProof = !enabled,
    ),
  );

  static bool _prepareTextProofingLanguage(
    WmlParagraph preview,
    int start,
    int end,
    String language,
  ) {
    final range = WmlRunEdit.normalizeRange(preview, start, end);
    final routingChanged = WmlRunEdit.splitProofingRange(
      preview,
      range.start,
      range.end,
    );
    // Choose the slots from each selected fragment after splitting. Unselected
    // letters must not choose its slots, and a mixed fragment can use both.
    final latinProperties = {
      for (final run in preview.inlines.whereType<WmlRun>())
        if (wordRunUsesLatinScriptLanguage(run)) run.properties,
    };
    final complexProperties = {
      for (final run in preview.inlines.whereType<WmlRun>())
        if (wordRunUsesComplexScriptLanguage(run)) run.properties,
    };
    final propertiesChanged = _prepareTextProofingRuns(
      preview,
      range.start,
      range.end,
      needsChange: (properties) =>
          latinProperties.contains(properties) &&
              properties.proofingLanguage != language ||
          complexProperties.contains(properties) &&
              properties.complexScriptLanguage != language,
      update: (properties) {
        if (latinProperties.contains(properties)) {
          properties.proofingLanguage = language;
        }
        if (complexProperties.contains(properties)) {
          properties.complexScriptLanguage = language;
        }
      },
    );
    return propertiesChanged || routingChanged;
  }

  static bool _prepareTextProofingRuns(
    WmlParagraph preview,
    int start,
    int end, {
    required bool Function(WmlRunProps) needsChange,
    required void Function(WmlRunProps) update,
  }) {
    var offset = 0;
    var changed = false;
    for (final run in preview.inlines.whereType<WmlRun>()) {
      final runEnd = offset + run.text.length;
      if (offset < end && runEnd > start && needsChange(run.properties)) {
        changed = true;
      }
      offset = runEnd;
    }
    if (!changed) return false;
    WmlRunEdit.applyRange(preview, start, end, (properties) {
      if (needsChange(properties)) update(properties);
    });
    return true;
  }

  bool _setTextProofingOption(
    WordTextProofingTarget target, {
    required bool Function(WmlParagraph, WmlParagraph, int, int) prepare,
  }) {
    if (!target.canEdit) return false;
    final current = textProofingTarget;
    if (current == null || !current.canEdit || !target._matches(current)) {
      return false;
    }
    final owners = <WmlParagraph, int>{
      for (final range in current._ranges) range.paragraph: 0,
    };
    void countOwners(Iterable<WmlParagraph> paragraphs) {
      for (final paragraph in paragraphs) {
        if (owners.containsKey(paragraph)) {
          owners[paragraph] = owners[paragraph]! + 1;
        }
      }
    }

    // Full ownership validation is needed only for an explicit mutation. An
    // aliased paragraph could otherwise also change a protected/hidden story.
    for (final section in document.sections) {
      countOwners(WordTree.paragraphs(section.blocks));
      for (final story in [
        section.header,
        section.footer,
        section.firstHeader,
        section.firstFooter,
        section.evenHeader,
        section.evenFooter,
      ]) {
        countOwners(story);
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      countOwners(note.allParagraphs);
    }
    for (final comment in document.comments) {
      countOwners(comment.paragraphs);
    }
    if (owners.values.any((count) => count != 1)) return false;
    final changes =
        <
          ({
            WmlParagraph paragraph,
            List<WmlInline> before,
            List<WmlInline> after,
          })
        >[];
    try {
      // Complete every preflight and detached edit before changing any source.
      for (final range in current._ranges) {
        final preview = WmlClone.paragraph(range.paragraph);
        if (!prepare(range.paragraph, preview, range.start, range.end)) {
          continue;
        }
        if (preview.text != range.paragraph.text) return false;
        changes.add((
          paragraph: range.paragraph,
          before: _cloneInlines(range.paragraph),
          after: _cloneInlines(preview),
        ));
      }
    } on Object {
      return false;
    }
    if (changes.isEmpty) return true;
    void restore({required bool after}) {
      for (final change in changes) {
        change.paragraph.inlines
          ..clear()
          ..addAll(_cloneInlinesFrom(after ? change.after : change.before));
      }
      // Formatting does not move text; history must not collapse a selection,
      // including a selection made in another story since this command.
      _historyRestoredSelection = true;
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () => restore(after: true),
        undoFn: () => restore(after: false),
      ),
    );
    relayout();
    _syncImeSelection();
    notifyListeners();
    return true;
  }

  /// Changes the default language; explicit span languages remain authoritative.
  void setProofingLanguage(String value) {
    if (!canApplyProofingSuggestions) return;
    final language = normalizeProofingLanguage(value);
    if (language.isEmpty || document.proofingLanguage == language) return;
    final before = document.proofingLanguage;
    commands.commit(
      _CallbackCommand(
        executeFn: () => document.proofingLanguage = language,
        undoFn: () => document.proofingLanguage = before,
      ),
    );
    relayout();
    notifyListeners();
    onProofingLanguageChanged?.call(language);
  }

  /// Saves the displayed language together with the hyphenation toggle so an
  /// untagged document actually receives linguistic line breaking. One undo
  /// restores both source settings.
  void setAutomaticHyphenation(bool enabled) {
    if (!config.allowsMutation ||
        (document.autoHyphenation == enabled &&
            (!enabled || document.proofingLanguage != null))) {
      return;
    }
    final before = document.autoHyphenation;
    final previousLanguage = document.proofingLanguage;
    final language = proofing.language;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          document.autoHyphenation = enabled;
          if (enabled && document.proofingLanguage == null) {
            document.proofingLanguage = language;
          }
        },
        undoFn: () {
          document.autoHyphenation = before;
          document.proofingLanguage = previousLanguage;
        },
      ),
    );
    relayout();
    notifyListeners();
  }

  bool get _hasProofingComposition {
    final composing = noteEditingTarget?.composing;
    return (input.composing.isValid && !input.composing.isCollapsed) ||
        (composing != null && composing.isValid && !composing.isCollapsed);
  }

  bool get canApplyProofingSuggestions =>
      !isDisposed &&
      config.allowsMutation &&
      !(document.restrictEditing &&
          (document.restrictMode != WmlRestrictMode.none ||
              document.protectionFormattingRestricted)) &&
      !_hasProofingComposition;

  bool canApplyProofingIssue(WordProofingIssue issue) {
    final current = _currentProofingIssue(issue);
    return current != null &&
        canApplyProofingSuggestions &&
        proofing.canCorrect(current);
  }

  /// Captures the selected word/phrase, or the complete word at a caret. The
  /// operation neither changes selection nor commits an active IME composition.
  WordThesaurusCapture captureThesaurusTarget() {
    _thesaurusGeneration++;
    _thesaurusTarget = null;
    _thesaurusLookup = null;
    if (isDisposed ||
        !config.allowsSelection ||
        noteEditingTarget != null ||
        selectedVisual != null ||
        selectedFrame != null ||
        selectedEquation != null) {
      return const WordThesaurusCapture._(
        WordThesaurusTargetStatus.unsupportedTarget,
        message: 'Select text in a supported Word paragraph.',
      );
    }
    if (input.composing.isValid && !input.composing.isCollapsed) {
      return const WordThesaurusCapture._(
        WordThesaurusTargetStatus.composing,
        message: 'Finish the current text composition before using Thesaurus.',
      );
    }
    final currentCaret = caret;
    final selection = _canvasCaretPosition;
    final paragraph = selection.paragraph;
    if (paragraph == null) {
      return const WordThesaurusCapture._(
        WordThesaurusTargetStatus.unsupportedTarget,
        message: 'Select text in a supported Word paragraph.',
      );
    }
    final range = currentCaret.normalizedRange;
    if (range.startPara != range.endPara) {
      return const WordThesaurusCapture._(
        WordThesaurusTargetStatus.multipleParagraphs,
        message: 'Select a word or phrase within one paragraph.',
      );
    }
    final sourceText = paragraph.text;
    var start = range.startIdx;
    var end = range.endIdx;
    if (start < 0 || end > sourceText.length) {
      return const WordThesaurusCapture._(
        WordThesaurusTargetStatus.invalidRange,
        message: 'The text selection is no longer valid. Select it again.',
      );
    }
    if (start == end) {
      final word = _thesaurusWordAt(sourceText, start);
      if (word == null) {
        return const WordThesaurusCapture._(
          WordThesaurusTargetStatus.noText,
          message: 'Select a word or phrase, or place the caret inside a word.',
        );
      }
      start = word.start;
      end = word.end;
    }
    if (sourceText.substring(start, end).trim().isEmpty) {
      return const WordThesaurusCapture._(
        WordThesaurusTargetStatus.noText,
        message: 'Select a word or phrase containing text.',
      );
    }
    final capture = proofing.captureTextRange(paragraph, start, end);
    final source = capture.target;
    if (source == null) {
      return switch (capture.status) {
        WordTextRangeStatus.mixedLanguage => const WordThesaurusCapture._(
          WordThesaurusTargetStatus.mixedLanguage,
          message:
              'The selection contains more than one language. Select a single-language word or phrase.',
        ),
        WordTextRangeStatus.protectedContent => const WordThesaurusCapture._(
          WordThesaurusTargetStatus.protectedContent,
          message:
              'This range contains protected, generated, or pending tracked content. Select ordinary text.',
        ),
        WordTextRangeStatus.invalidRange => const WordThesaurusCapture._(
          WordThesaurusTargetStatus.invalidRange,
          message: 'Select complete characters within a single paragraph.',
        ),
        _ => const WordThesaurusCapture._(
          WordThesaurusTargetStatus.unsupportedTarget,
          message: 'This text is outside the supported Word editing surface.',
        ),
      };
    }
    final target = WordThesaurusTarget._(
      this,
      source,
      currentCaret,
      selection,
      document.trackRevisions,
    );
    _thesaurusTarget = target;
    return WordThesaurusCapture._(
      WordThesaurusTargetStatus.ready,
      target: target,
    );
  }

  static final _thesaurusWordCharacter = RegExp(
    r'[\p{L}\p{N}\p{M}]',
    unicode: true,
  );
  static final _thesaurusWordJoiner = RegExp(r"^['’\-‐‑_\u00ad]+$");

  static ({int start, int end})? _thesaurusWordAt(String text, int offset) {
    final clusters = GraphemeClusters.segment(text);
    if (clusters.isEmpty ||
        offset < 0 ||
        offset > text.length ||
        (offset != 0 && !clusters.any((cluster) => cluster.end == offset))) {
      return null;
    }
    final lexical = <bool>[
      for (final cluster in clusters)
        _thesaurusWordCharacter.hasMatch(cluster.text),
    ];
    final included = List<bool>.of(lexical);
    for (var i = 1; i < clusters.length - 1; i++) {
      if (_thesaurusWordJoiner.hasMatch(clusters[i].text) &&
          lexical[i - 1] &&
          lexical[i + 1]) {
        included[i] = true;
      }
    }
    var at = clusters.indexWhere((cluster) => cluster.end > offset);
    if (at < 0) at = clusters.length - 1;
    if (!included[at] &&
        at > 0 &&
        clusters[at].start == offset &&
        included[at - 1]) {
      at--;
    }
    if (!included[at]) return null;
    var from = at;
    var to = at;
    while (from > 0 && included[from - 1]) {
      from--;
    }
    while (to + 1 < included.length && included[to + 1]) {
      to++;
    }
    return (start: clusters[from].start, end: clusters[to].end);
  }

  bool _matchesThesaurusSelection(WordThesaurusTarget target) =>
      !isDisposed &&
      config.allowsSelection &&
      noteEditingTarget == null &&
      selectedVisual == null &&
      selectedFrame == null &&
      selectedEquation == null &&
      identical(target._owner, this) &&
      identical(caret, target._caret) &&
      _canvasCaretPosition == target._selection &&
      document.trackRevisions == target._trackRevisions &&
      !(input.composing.isValid && !input.composing.isCollapsed);

  bool isThesaurusTargetCurrent(WordThesaurusTarget target) {
    if (!identical(_thesaurusTarget, target)) return false;
    if (_matchesThesaurusSelection(target) &&
        proofing.canEditTextRange(target._source)) {
      return true;
    }
    _thesaurusGeneration++;
    _thesaurusTarget = null;
    _thesaurusLookup = null;
    return false;
  }

  /// Looks up a captured source without changing its language or the document.
  /// Repeating the lookup (including changing the override) retires old choices.
  Future<WordThesaurusLookup> lookupThesaurus(
    WordThesaurusTarget target,
    OfficeThesaurusService service, {
    String? languageOverride,
  }) async {
    final generation = ++_thesaurusGeneration;
    _thesaurusLookup = null;
    final revision = service.revision;
    final language = normalizeProofingLanguage(
      languageOverride ?? target.language,
    );
    final result = await service.lookup(
      OfficeThesaurusQuery(text: target.text, language: language),
    );
    final lookup = WordThesaurusLookup._(
      target,
      result,
      language,
      service,
      revision,
      generation,
    );
    if (generation == _thesaurusGeneration &&
        isThesaurusTargetCurrent(target) &&
        service.revision == revision) {
      _thesaurusLookup = lookup;
    }
    return lookup;
  }

  bool isThesaurusLookupCurrent(WordThesaurusLookup lookup) =>
      identical(_thesaurusLookup, lookup) &&
      lookup._generation == _thesaurusGeneration &&
      lookup._service.revision == lookup._serviceRevision &&
      isThesaurusTargetCurrent(lookup.target);

  bool canApplyThesaurusTerm(
    WordThesaurusLookup lookup,
    OfficeThesaurusTerm term,
  ) =>
      canApplyProofingSuggestions &&
      isThesaurusLookupCurrent(lookup) &&
      lookup.result.status == OfficeThesaurusStatus.ready &&
      lookup.result.packIdentity != null &&
      lookup.result.containsTerm(term) &&
      term.text != lookup.target.text &&
      term.text.trim().isNotEmpty &&
      !RegExp(r'[\x00-\x1f\x7f-\x9f\u2028\u2029]').hasMatch(term.text);

  /// Applies one literal alternative using the same rich-text transaction and
  /// history snapshots as proofing, after validating its own source/candidate.
  bool applyThesaurusTerm(
    WordThesaurusLookup lookup,
    OfficeThesaurusTerm term,
  ) {
    if (!canApplyThesaurusTerm(lookup, term)) return false;
    commitNoteEdits();
    if (!canApplyThesaurusTerm(lookup, term)) return false;
    final source = lookup.target._source;
    final applied = _applyValidatedTextReplacement(
      paragraph: source.paragraph,
      start: source.start,
      end: source.end,
      replacement: term.text,
      edits: [(start: source.start, end: source.end, replacement: term.text)],
      preserveReplacementStyle: true,
      preserveReplacementLinks: true,
    );
    if (applied) {
      _thesaurusGeneration++;
      _thesaurusLookup = null;
      _thesaurusTarget = null;
    }
    return applied;
  }

  // Complete phrase alternatives preserve their original word separators.
  // Apply only changed words so article formatting cannot replace the styles
  // of an unchanged noun or adjective. A malformed provider choice is refused.
  static List<({int start, int end, String replacement})>? _proofingPhraseEdits(
    String source,
    String replacement,
    int offset,
  ) {
    final words = RegExp(r'\S+');
    final before = words.allMatches(source).toList();
    final after = words.allMatches(replacement).toList();
    if (before.length < 2 ||
        before.length > 4 ||
        before.length != after.length) {
      return null;
    }
    final edits = <({int start, int end, String replacement})>[];
    var oldEnd = 0, newEnd = 0;
    for (var i = 0; i < before.length; i++) {
      final oldWord = before[i], newWord = after[i];
      if (source.substring(oldEnd, oldWord.start) !=
          replacement.substring(newEnd, newWord.start)) {
        return null;
      }
      if (oldWord.group(0) != newWord.group(0)) {
        edits.add((
          start: offset + oldWord.start,
          end: offset + oldWord.end,
          replacement: newWord.group(0)!,
        ));
      }
      oldEnd = oldWord.end;
      newEnd = newWord.end;
    }
    if (source.substring(oldEnd) != replacement.substring(newEnd) ||
        edits.isEmpty) {
      return null;
    }
    return edits;
  }

  /// Replaces one current, editable source span through normal undo history.
  /// Tracked corrections retain deleted text and a separate inserted revision.
  bool applyProofingSuggestion(WordProofingIssue issue, String replacement) {
    var current = _currentProofingIssue(issue);
    if (current == null ||
        !canApplyProofingIssue(current) ||
        !issue.finding.replacements.contains(replacement) ||
        replacement == issue.finding.originalText ||
        RegExp(r'[\r\n\u2028\u2029]').hasMatch(replacement)) {
      return false;
    }
    commitNoteEdits();
    current = _currentProofingIssue(current);
    if (current == null || !canApplyProofingIssue(current)) return false;
    final paragraph = current.paragraph;
    final finding = current.finding;
    final start = finding.start;
    final end = finding.end;
    final edits = finding.ruleId == 'de.grammar.phrase-agreement'
        ? _proofingPhraseEdits(finding.originalText, replacement, start)
        : [(start: start, end: end, replacement: replacement)];
    if (edits == null) return false;
    return _applyValidatedTextReplacement(
      paragraph: paragraph,
      start: start,
      end: end,
      replacement: replacement,
      edits: edits,
      preserveReplacementStyle: finding.ruleId == 'de.grammar.phrase-agreement',
    );
  }

  bool _applyValidatedTextReplacement({
    required WmlParagraph paragraph,
    required int start,
    required int end,
    required String replacement,
    required List<({int start, int end, String replacement})> edits,
    required bool preserveReplacementStyle,
    bool preserveReplacementLinks = false,
  }) {
    final insertedLength = edits.fold<int>(
      0,
      (length, edit) => length + edit.replacement.length,
    );
    final before = _cloneInlines(paragraph);
    final revisions = WordRevisions.capture(document);
    List<WmlInline>? after;
    WmlRevisionSnapshot? afterRevisions;
    final tracked = document.trackRevisions;
    final previousText = paragraph.text;
    final activeCaret = caret;
    final activeParagraphs = _paragraphs;
    final activeNote = noteEditingTarget;
    final activeNoteAffected =
        activeNote != null &&
        _noteTextSegments(
          activeNote.note,
        ).any((segment) => identical(segment.paragraph, paragraph));
    final activeComment = isEditingComment ? selectedComment : null;
    final activeHeaderFooter = isEditingHeaderFooter ? activeParagraphs : null;
    bool sameCaretStory() =>
        noteEditingTarget == null &&
        identical(caret, activeCaret) &&
        (activeComment != null
            ? isEditingComment && identical(selectedComment, activeComment)
            : activeHeaderFooter != null
            ? isEditingHeaderFooter &&
                  identical(_paragraphs, activeHeaderFooter)
            : !isEditingComment && !isEditingHeaderFooter);
    final activeAffected =
        activeNote == null &&
        activeCaret.paragraphIndex >= 0 &&
        activeCaret.paragraphIndex < activeParagraphs.length &&
        identical(activeParagraphs[activeCaret.paragraphIndex], paragraph);
    final beforeCaret = (
      paragraph: activeCaret.paragraphIndex,
      offset: activeCaret.logicalIndex,
      anchorParagraph: activeCaret.selectionAnchorParagraph,
      anchor: activeCaret.selectionAnchor,
    );
    void correctedCaret() {
      if (activeNoteAffected) {
        if (identical(noteEditingTarget?.note, activeNote.note)) {
          _restoreNoteEditingTarget(
            _noteTargetAt(
              paragraph,
              tracked ? end + insertedLength : start + replacement.length,
            ),
          );
        }
        _historyRestoredSelection = true;
        return;
      }
      // Comments and headers/footers share a caret across distinct stories.
      // Undo/redo must not apply one story's offsets to another story.
      if (!activeAffected || !sameCaretStory()) {
        _historyRestoredSelection = true;
        return;
      }
      activeCaret
        ..paragraphIndex = beforeCaret.paragraph
        ..logicalIndex = tracked
            ? end + insertedLength
            : start + replacement.length
        ..collapseSelection();
    }

    void originalCaret() {
      if (activeNoteAffected) {
        if (identical(noteEditingTarget?.note, activeNote.note)) {
          _restoreNoteEditingTarget(_clampNoteEditingTarget(activeNote));
        }
        _historyRestoredSelection = true;
        return;
      }
      if (!activeAffected || !sameCaretStory()) {
        _historyRestoredSelection = true;
        return;
      }
      activeCaret
        ..paragraphIndex = beforeCaret.paragraph
        ..logicalIndex = beforeCaret.offset
        ..selectionAnchorParagraph = beforeCaret.anchorParagraph
        ..selectionAnchor = beforeCaret.anchor;
      if (identical(caret, activeCaret)) {
        _historyRestoredSelection = true;
      }
    }

    void restoreBefore() {
      paragraph.inlines
        ..clear()
        ..addAll(_cloneInlinesFrom(before));
      revisions.restore(document);
    }

    // Validate the exact operation on a clone before opening a transaction.
    final preview = WmlClone.paragraph(paragraph);
    for (final edit in edits.reversed) {
      _replaceValidatedRange(
        preview,
        edit.start,
        edit.end,
        edit.replacement,
        tracked: tracked,
        preserveStyle: preserveReplacementStyle,
        preserveLink: preserveReplacementLinks,
      );
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (after != null) {
            paragraph.inlines
              ..clear()
              ..addAll(_cloneInlinesFrom(after!));
            afterRevisions!.restore(document);
            correctedCaret();
            return;
          }
          restoreBefore();
          try {
            for (final edit in edits.reversed) {
              final start = edit.start;
              final end = edit.end;
              final replacement = edit.replacement;
              if (tracked) {
                // Recording deletion first keeps replacement insertion at the
                // original end outside the deleted span during range rebasing.
                if (start != end) {
                  WordRevisions.record(
                    document,
                    kind: WmlRevisionKind.delete,
                    paragraph: paragraph,
                    paragraphIndex: document.paragraphs.toList().indexOf(
                      paragraph,
                    ),
                    start: start,
                    end: end,
                    text: previousText.substring(start, end),
                    author: revisionAuthor,
                  );
                }
                WordRevisions.rebaseEdit(
                  document,
                  paragraph,
                  start: end,
                  end: end,
                  insertedLength: replacement.length,
                );
                _replaceValidatedRange(
                  paragraph,
                  start,
                  end,
                  replacement,
                  tracked: true,
                  preserveStyle: preserveReplacementStyle,
                  preserveLink: preserveReplacementLinks,
                );
                if (replacement.isNotEmpty) {
                  WordRevisions.record(
                    document,
                    kind: WmlRevisionKind.insert,
                    paragraph: paragraph,
                    paragraphIndex: document.paragraphs.toList().indexOf(
                      paragraph,
                    ),
                    start: end,
                    end: end + replacement.length,
                    text: replacement,
                    author: revisionAuthor,
                  );
                }
              } else {
                WordRevisions.rebaseEdit(
                  document,
                  paragraph,
                  start: start,
                  end: end,
                  insertedLength: replacement.length,
                );
                _replaceValidatedRange(
                  paragraph,
                  start,
                  end,
                  replacement,
                  tracked: false,
                  preserveStyle: preserveReplacementStyle,
                  preserveLink: preserveReplacementLinks,
                );
              }
            }
            after = _cloneInlines(paragraph);
            afterRevisions = WordRevisions.capture(document);
            correctedCaret();
          } on Object {
            restoreBefore();
            originalCaret();
            rethrow;
          }
        },
        undoFn: () {
          restoreBefore();
          originalCaret();
        },
      ),
    );
    if (activeAffected) {
      _markLocalEdit(previousText: previousText);
    }
    relayout();
    _syncImeSelection();
    notifyListeners();
    return true;
  }

  // A literal replacement inside one hyperlink keeps that link. A selection
  // across differently linked/unlinked text does not acquire a misleading link.
  // Work on exact inserted boundaries after coalescing ordinary text runs.
  static void _replaceValidatedRange(
    WmlParagraph paragraph,
    int start,
    int end,
    String replacement, {
    required bool tracked,
    required bool preserveStyle,
    required bool preserveLink,
  }) {
    WmlHyperlink? link;
    var sawRun = false;
    var uniform = true;
    var offset = 0;
    if (preserveLink) {
      for (final run in paragraph.inlines.whereType<WmlRun>()) {
        final runEnd = offset + run.text.length;
        if (offset < end && runEnd > start) {
          if (!sawRun) {
            link = run.hyperlink;
            sawRun = true;
          } else if (link?.url != run.hyperlink?.url ||
              link?.anchor != run.hyperlink?.anchor ||
              link?.file != run.hyperlink?.file) {
            uniform = false;
          }
        }
        offset = runEnd;
      }
    }
    final insertStart = tracked ? end : start;
    WmlRunEdit.replaceRange(
      paragraph,
      insertStart,
      end,
      replacement,
      styleSource: tracked && preserveStyle ? start : null,
    );
    if (!uniform || link == null || replacement.isEmpty) return;
    final insertEnd = insertStart + replacement.length;
    WmlRunEdit.splitAt(paragraph, insertEnd);
    WmlRunEdit.splitAt(paragraph, insertStart);
    offset = 0;
    for (final run in paragraph.inlines.whereType<WmlRun>()) {
      final runEnd = offset + run.text.length;
      if (offset >= insertStart && runEnd <= insertEnd && runEnd > offset) {
        run.hyperlink = link.copy();
      }
      offset = runEnd;
    }
    WmlRunEdit.coalesce(paragraph);
  }

  /// Selects a finding in its actual rendered story. Header/footer variants
  /// that do not occur on a laid-out page remain available in the review pane.
  bool revealProofingIssue(WordProofingIssue issue) {
    var current = _currentProofingIssue(issue);
    if (!config.allowsSelection || current == null || _hasProofingComposition) {
      return false;
    }
    commitPendingEdits();
    current = _currentProofingIssue(current);
    if (current == null) return false;
    _selectedProofingIssue = current;
    final revealed = _revealParagraphRange(
      current.paragraph,
      current.finding.start,
      current.finding.end,
    );
    _proofingSelectionCaret = _proofingCaretPosition;
    return revealed;
  }

  bool _revealParagraphRange(WmlParagraph paragraph, int start, int end) {
    if (_disposed ||
        !config.allowsSelection ||
        _hasProofingComposition ||
        start < 0 ||
        end < start ||
        end > paragraph.text.length) {
      return false;
    }
    for (final comment in document.comments) {
      if (comment.paragraphs.contains(paragraph)) {
        beginCommentEdit(comment.id);
        commentCaret
          ..paragraphIndex = comment.paragraphs.indexOf(paragraph)
          ..logicalIndex = end
          ..selectionAnchorParagraph = comment.paragraphs.indexOf(paragraph)
          ..selectionAnchor = start;
        _syncImeSelection();
        notifyListeners();
        return true;
      }
    }
    for (
      var sectionIndex = 0;
      sectionIndex < document.sections.length;
      sectionIndex++
    ) {
      final section = document.sections[sectionIndex];
      for (final footer in [false, true]) {
        for (final paragraphs
            in footer
                ? [section.footer, section.firstFooter, section.evenFooter]
                : [section.header, section.firstHeader, section.evenHeader]) {
          final index = paragraphs.indexOf(paragraph);
          if (index < 0) continue;
          // Navigate only to a page that renders this exact source story.
          // Do not silently edit the default variant or change page settings.
          final page = documentLaidOut.pages.indexWhere((page) {
            final lines = footer ? page.footer : page.header;
            return page.sectionIndex == sectionIndex &&
                lines.any((line) => identical(line.sourceParagraph, paragraph));
          });
          if (page < 0) return false;
          beginHeaderFooterEdit(page, footer: footer);
          headerFooterCaret
            ..paragraphIndex = index
            ..logicalIndex = end
            ..selectionAnchorParagraph = index
            ..selectionAnchor = start;
          _syncImeSelection();
          notifyListeners();
          return true;
        }
      }
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      for (final segment in _noteTextSegments(note)) {
        if (!identical(segment.paragraph, paragraph)) continue;
        if (start < segment.hidden) return false;
        detachInput();
        setNoteEditingTarget(
          note,
          TextSelection(
            baseOffset: segment.start + start - segment.hidden,
            extentOffset: segment.start + end - segment.hidden,
          ),
        );
        requestEditingFocus();
        return true;
      }
    }
    final index = document.paragraphs.toList().indexOf(paragraph);
    if (index < 0) return false;
    clearNoteEditingTarget(notify: false);
    endCommentEdit();
    endHeaderFooterEdit();
    // Showing a text finding leaves object editing. Otherwise the equation
    // IME or visual/frame key handlers can retain ownership of later input.
    selectEquation(null);
    selectVisual(null);
    selectFrame(null);
    selectTable(null);
    documentCaret
      ..paragraphIndex = index
      ..logicalIndex = end
      ..selectionAnchorParagraph = index
      ..selectionAnchor = start;
    final page = documentLaidOut.pages.indexWhere(
      (page) =>
          page.lines.any((line) => identical(line.sourceParagraph, paragraph)),
    );
    if (page >= 0) _revealPage(page);
    onRequestFocus?.call();
    attachInput();
    _syncImeSelection();
    notifyListeners();
    return true;
  }

  /// Reading findings must not create a paragraph in an empty document.
  /// Use the session's half-open hit ranges, including exact insertion points.
  List<WordProofingIssue> get proofingIssuesAtCaret {
    final position = _proofingCaretPosition;
    final paragraph = position.paragraph;
    if (paragraph == null) {
      return const <WordProofingIssue>[];
    }
    return proofing
        .issuesAt(paragraph, position.offset)
        .where(proofing.isCurrent)
        .toList();
  }

  /// Legacy caller-supplied spelling callback. New hosts should use
  /// [checkDocumentProofing] to distinguish unavailable and clean results.
  List<OfficeSpellIssue> checkSpelling({OfficeSpellChecker? checker}) {
    return OfficeSpell.check(_activeParagraph.text, checker: checker);
  }
}

enum _WordBlockCover { none, partial, full }

/// Spreadsheet controller: selection, formula bar, cell IME.
class SheetEditorController extends OfficeController {
  /// SheetEditorController API.
  SheetEditorController({
    SmlWorkbook? workbook,
    String? formulaLocale,
    super.config,
    this._activeSheet = 0,
    this.columnMetricsResolver = SheetFontMetrics.measure,
  }) : workbook = workbook ?? SmlWorkbook() {
    this.workbook.formulaLocale =
        formulaLocale ?? this.workbook.formulaLocale ?? Intl.getCurrentLocale();
    cellEditor = InlineCellEditor(
      onCommit: _commitFormula,
      onChanged: _onCellEditorChanged,
      commitOnNewline: true,
    );
    this.workbook.resolveColumnMetrics(columnMetricsResolver);
    if (this.workbook.sheets.isNotEmpty) {
      final active = this
          .workbook
          .sheets[_activeSheet.clamp(0, this.workbook.sheets.length - 1)];
      if (active.hidden) {
        final firstVisible = this.workbook.sheets.indexWhere(
          (sheet) => !sheet.hidden,
        );
        if (firstVisible >= 0) _activeSheet = firstVisible;
      }
    }
    recalculateWorkbook();
  }

  /// fromBytes API.
  factory SheetEditorController.fromBytes(
    Uint8List bytes, {
    String? password,
    String? formulaLocale,
    OfficeSurfaceConfig? config,
    SmlColumnMetricsResolver columnMetricsResolver = SheetFontMetrics.measure,
  }) {
    final SheetEditorController controller = SheetEditorController(
      config: config,
      columnMetricsResolver: columnMetricsResolver,
      formulaLocale: formulaLocale,
    );
    controller.loadBytes(bytes, password: password);
    return controller;
  }

  /// workbook API.
  SmlWorkbook workbook;

  /// Resolves actual font availability; null measurements preserve fallback.
  final SmlColumnMetricsResolver columnMetricsResolver;

  /// Reprojects dimensions after a host registers fonts. This view-only change
  /// preserves source width precision, explicit edits, dirty state and history.
  bool refreshColumnMetrics() {
    final resolved = workbook.resolveColumnMetrics(columnMetricsResolver);
    if (resolved) notifyListeners();
    return resolved;
  }

  int _activeSheet;

  @override
  set config(OfficeSurfaceConfig value) {
    if (!value.allowsMutation) _cancelResize();
    super.config = value;
  }

  @override
  void syncConfig(OfficeSurfaceConfig value) {
    if (!value.allowsMutation) _cancelResize();
    super.syncConfig(value);
  }

  @override
  void setMode(OfficeInteractionMode mode) {
    if (mode != OfficeInteractionMode.editing) _cancelResize();
    super.setMode(mode);
  }

  /// selection API.
  final SelectionMatrix selection = SelectionMatrix();

  /// cellEditor API.
  late final InlineCellEditor cellEditor;

  SmlWorksheet? _cellEditSheet;
  SmlCell? _cellEditCell;
  String? _cellTextBeforeEdit;
  String? _cellTextLastObserved;

  @override
  bool get _hasPendingEdits =>
      cellEditor.editing &&
      _cellTextBeforeEdit != null &&
      cellEditor.formulaBar != _cellTextBeforeEdit;

  @override
  bool get canUndo => super.canUndo || _hasPendingEdits;

  /// selectedDrawingIndex API.
  int? selectedDrawingIndex;
  var _applyingPoint = false;
  int? _pointStart;
  int? _pointEnd;
  SmlCellRef? _pointAnchor;

  /// functionSuggestions API.
  List<FormulaFnDoc> functionSuggestions = const <FormulaFnDoc>[];

  /// Last data-validation failure, or null.
  String? lastValidationError;

  /// functionSuggestionIndex API.
  var functionSuggestionIndex = 0;
  var _suppressFunctionSuggestions = false;
  String? _suppressedFunctionPrefix;

  /// activeSheetIndex API.
  int get activeSheetIndex => _activeSheet;

  /// sheet API.
  SmlWorksheet get sheet {
    if (workbook.sheets.isEmpty) {
      workbook.sheets.add(SmlWorksheet(name: 'Sheet1', sheetId: 1));
    }
    final active =
        workbook.sheets[_activeSheet.clamp(0, workbook.sheets.length - 1)];
    final metrics = workbook.columnMetrics;
    if (metrics != null) active.applyColumnMetrics(metrics.maximumDigitWidthPx);
    return active;
  }

  @override
  /// kind API.
  OpcPackageKind get kind => OpcPackageKind.sheet;

  /// Top-left cell of the selection, or the merge origin when the focus is merged.
  SmlCellRef get activeCell {
    final SmlMerge? merge = sheet.mergeAtRef(selection.focus);
    if (merge != null) {
      return merge.origin;
    }
    final SmlRange range = selection.range;
    return SmlCellRef(range.minCol, range.minRow);
  }

  /// Name-box address: a merged block uses its origin cell only.
  String get selectionAddress {
    final SmlMerge? merge = sheet.mergeAtRef(activeCell);
    if (merge != null) {
      final SmlRange range = selection.range;
      final bool onlyThisMerge =
          range.minCol >= merge.c0 &&
          range.maxCol <= merge.c1 &&
          range.minRow >= merge.r0 &&
          range.maxRow <= merge.r1;
      if (onlyThisMerge) {
        return merge.origin.a1;
      }
    }
    final SmlRange range = selection.range;
    if (range.minCol == range.maxCol && range.minRow == range.maxRow) {
      return SmlCellRef(range.minCol, range.minRow).a1;
    }
    return '${SmlCellRef(range.minCol, range.minRow).a1}:${SmlCellRef(range.maxCol, range.maxRow).a1}';
  }

  /// Name-box label: a defined name when the selection is that range.
  String get nameBoxText {
    final SmlRange range = selection.range;
    for (final SmlNamedRange named in workbook.namedRanges) {
      if (named.sheetName.isNotEmpty && named.sheetName != sheet.name) {
        continue;
      }
      final SmlRange namedRange = named.range;
      if (namedRange.minCol == range.minCol &&
          namedRange.maxCol == range.maxCol &&
          namedRange.minRow == range.minRow &&
          namedRange.maxRow == range.maxRow) {
        return named.name;
      }
    }
    return selectionAddress;
  }

  /// Selects the workbook name [name], switching sheets when it names one.
  bool selectNamedRange(String name) {
    final SmlNamedRange? named = workbook.namedRange(name);
    if (named == null) {
      return false;
    }
    final int index = workbook.sheets.indexWhere(
      (SmlWorksheet candidate) => candidate.name == named.sheetName,
    );
    if (index >= 0) {
      _activeSheet = index;
    }
    selection
      ..kind = SheetSelectionKind.cells
      ..anchor = named.range.start
      ..focus = named.range.end;
    notifyListeners();
    return true;
  }

  /// formulaBarText API.
  String get formulaBarText {
    if (cellEditor.editing) {
      return cellEditor.formulaBar;
    }
    final SmlCell cell = sheet.cell(activeCell);
    return cell.formula ?? cell.asString;
  }

  /// cellDisplayText API.
  String cellDisplayText(SmlCell cell) {
    if (cellEditor.editing &&
        cell.ref.col == activeCell.col &&
        cell.ref.row == activeCell.row) {
      return cellEditor.formulaBar;
    }
    if (cell.formula != null && cell.formula!.isNotEmpty) {
      return _formatDisplayedValue(
        FormulaEvaluator.evaluateCell(workbook, sheet, cell),
        cell.styleIndex,
      );
    }
    return _formatDisplayedValue(cell.value, cell.styleIndex);
  }

  String _formatDisplayedValue(Object? value, int styleIndex) {
    final SmlStyleSheet? styles = workbook.styles;
    if (styles != null) {
      return styles.format(value, styleIndex);
    }
    return _formatCellValue(value);
  }

  /// recalculateWorkbook API.
  void recalculateWorkbook() {
    FormulaEvaluator.recalculate(workbook);
    SheetChartData.refreshWorkbook(workbook);
  }

  static String _formatCellValue(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is num) {
      if (value == value.roundToDouble()) {
        return value.round().toString();
      }
      return value.toString();
    }
    return value.toString();
  }

  /// loadBytes API.
  void loadBytes(Uint8List bytes, {String? password}) {
    _acceptOpenedWorkbook(
      SheetDeserializer().read(OfficeRepair.open(bytes, password: password)),
      recalculate: true,
    );
  }

  /// loadBytesAsync API.
  Future<void> loadBytesAsync(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final SmlWorkbook opened = await OfficeIsolateOpen.workbook(
      bytes,
      password: password,
      formulaLocale: workbook.formulaLocale,
      onProgress: onProgress,
    );
    _acceptOpenedWorkbook(opened, recalculate: false);
  }

  void _acceptOpenedWorkbook(SmlWorkbook opened, {required bool recalculate}) {
    _cancelResize();
    cancelCellEdit();
    opened.formulaLocale ??= workbook.formulaLocale;
    workbook = opened;
    workbook.resolveColumnMetrics(columnMetricsResolver);
    _activeSheet = workbook.sheets.indexWhere((sheet) => !sheet.hidden);
    if (_activeSheet < 0) _activeSheet = 0;
    selectedDrawingIndex = null;
    selection.selectCell(const SmlCellRef(0, 0));
    viewport.origin = Offset.zero;
    if (recalculate) {
      recalculateWorkbook();
    }
    _dirty = false;
    notifyListeners();
  }

  @override
  /// afterHistoryChange API.
  void afterHistoryChange() {
    recalculateWorkbook();
  }

  @override
  void undo() {
    if (!config.enableUndo || !config.allowsMutation) {
      return;
    }
    commitCellEdit();
    super.undo();
  }

  @override
  void redo() {
    if (!config.enableUndo || !config.allowsMutation) {
      return;
    }
    commitCellEdit();
    super.redo();
  }

  @override
  void commitPendingEdits() {
    if (_hasPendingEdits) {
      final SmlWorksheet target = _cellEditSheet ?? sheet;
      final SmlCell cell = _cellEditCell ?? target.cell(activeCell);
      lastValidationError = config.allowsMutation
          ? _cellInputError(target, cell, cellEditor.formulaBar)
          : 'The editor is read-only.';
      if (lastValidationError != null) {
        // Retain the visible draft if a save cannot apply it to the workbook.
        notifyListeners();
        throw StateError(lastValidationError!);
      }
    }
    commitCellEdit();
  }

  @override
  /// saveBytes API.
  Uint8List saveBytes({String? password}) {
    commitPendingEdits();
    final Uint8List bytes = SheetSerializer().writeBytes(
      workbook,
      password: password,
    );
    markClean();
    return bytes;
  }

  @override
  /// saveBytesAsync API.
  Future<Uint8List> saveBytesAsync({String? password}) {
    commitPendingEdits();
    return OfficeIsolateSave.workbook(workbook, password: password);
  }

  /// Selects the clamped worksheet index after committing any changed draft.
  /// Rejected drafts remain on their original worksheet. Selecting the current
  /// worksheet is a no-op, including its selection, viewport and editor state.
  void setActiveSheet(int index) {
    final int next = index.clamp(0, workbook.sheets.length - 1);
    if (next == _activeSheet) {
      return;
    }
    commitPendingEdits();
    _activeSheet = next;
    selectedDrawingIndex = null;
    selection.selectCell(const SmlCellRef(0, 0));
    viewport.origin = Offset.zero;
    notifyListeners();
  }

  /// Renames a worksheet and all supported local references as one history
  /// entry. Invalid/unsupported renames leave pending cell input untouched.
  /// A valid pending formula is committed before its references are rewritten.
  bool renameSheet(String name, {int? sheetIndex}) {
    if (!config.allowsMutation) return false;
    final index = sheetIndex ?? _activeSheet;
    if (index < 0 || index >= workbook.sheets.length) {
      throw RangeError.index(index, workbook.sheets, 'sheetIndex');
    }
    final target = workbook.sheets[index];
    final checked = SheetRename.prepare(workbook, target, name);
    if (checked.isEmpty) return false;
    // Validate the buffered formula before committing it, so a malformed
    // qualifier cannot create a cell command ahead of a rejected rename.
    if (cellEditor.editing &&
        cellEditor.formulaBar.trimLeft().startsWith('=')) {
      SheetRename.rewriteFormula(cellEditor.formulaBar, target.name, name);
    }
    commitPendingEdits();
    final edit = SheetRename.prepare(workbook, target, name);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          edit.apply();
          recalculateWorkbook();
        },
        undoFn: () {
          edit.undo();
          recalculateWorkbook();
        },
      ),
    );
    notifyListeners();
    return true;
  }

  /// setSheetRightToLeft API.
  void setSheetRightToLeft(bool value) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlWorksheet target = sheet;
    final bool before = target.rightToLeft;
    if (before == value) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => target.rightToLeft = value,
        undoFn: () => target.rightToLeft = before,
      ),
    );
  }

  /// toggleSheetRightToLeft API.
  void toggleSheetRightToLeft() {
    setSheetRightToLeft(!sheet.rightToLeft);
  }

  /// hasFrozenPanes API.
  bool get hasFrozenPanes => sheet.freezeRows > 0 || sheet.freezeCols > 0;

  /// unfreezePanes API.
  void unfreezePanes() {
    _setFrozenPanes(0, 0);
  }

  /// Excel Freeze Panes: lock rows above and columns left of the selection.
  ///
  /// A full row freezes from that row (no columns). A full column freezes
  /// from that column (no rows). A cell freezes from its row and column.
  void freezePanesFromSelection() {
    if (!config.allowsMutation) {
      return;
    }
    var rows = 0;
    var cols = 0;
    if (selection.isFullRowSelection && selection.isFullColumnSelection) {
      unfreezePanes();
      return;
    }
    if (selection.isFullRowSelection) {
      rows = selection.anchor.row < selection.focus.row
          ? selection.anchor.row
          : selection.focus.row;
    } else if (selection.isFullColumnSelection) {
      cols = selection.anchor.col < selection.focus.col
          ? selection.anchor.col
          : selection.focus.col;
    } else {
      rows = selection.focus.row;
      cols = selection.focus.col;
    }
    if (rows <= 0 && cols <= 0) {
      unfreezePanes();
      return;
    }
    _setFrozenPanes(rows, cols);
  }

  /// toggleFreezePanes API.
  void toggleFreezePanes() {
    if (hasFrozenPanes) {
      unfreezePanes();
    } else {
      freezePanesFromSelection();
    }
  }

  /// freezeTopRow API.
  void freezeTopRow() {
    _setFrozenPanes(1, 0);
  }

  /// freezeFirstColumn API.
  void freezeFirstColumn() {
    _setFrozenPanes(0, 1);
  }

  void _setFrozenPanes(int rows, int cols) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlWorksheet target = sheet;
    final int beforeRows = target.freezeRows;
    final int beforeCols = target.freezeCols;
    final int afterRows = rows.clamp(0, SmlWorksheet.excelRowCount - 1);
    final int afterCols = cols.clamp(0, SmlWorksheet.excelColumnCount - 1);
    if (beforeRows == afterRows && beforeCols == afterCols) {
      return;
    }
    void apply(int rowCount, int colCount) {
      target
        ..freezeRows = rowCount
        ..freezeCols = colCount;
      if (identical(sheet, target)) {
        clampSheetViewport();
      }
    }

    commands.commit(
      _CallbackCommand(
        executeFn: () => apply(afterRows, afterCols),
        undoFn: () => apply(beforeRows, beforeCols),
      ),
    );
  }

  /// canMergeAndCenter API.
  bool get canMergeAndCenter {
    if (!config.allowsMutation ||
        selection.isFullRowSelection ||
        selection.isFullColumnSelection) {
      return false;
    }
    return sheet.canMerge(selection.range) || sheet.canUnmerge(selection.range);
  }

  /// canUnmergeCells API.
  bool get canUnmergeCells =>
      config.allowsMutation && sheet.canUnmerge(selection.range);

  /// True when the selection is (or sits inside) a merged rectangle.
  bool get hasMergedSelection => sheet.canUnmerge(selection.range);

  /// Excel Merge & Center.
  void mergeAndCenter() {
    if (!canMergeAndCenter) {
      return;
    }
    final SmlRange range = selection.range;
    _mutateSheetGrid((SmlWorksheet target) {
      if (range.isSingleCell) {
        target.toggleMergeAndCenter(range);
      } else {
        target.mergeAndCenter(range);
      }
    });
    final SmlMerge? merge = sheet.mergeAt(range.minCol, range.minRow);
    if (merge != null) {
      selection.selectCell(merge.origin);
    }
    notifyListeners();
  }

  /// unmergeCells API.
  void unmergeCells() {
    if (!canUnmergeCells) {
      return;
    }
    final SmlRange range = selection.range;
    _mutateSheetGrid((SmlWorksheet target) => target.unmerge(range));
    notifyListeners();
  }

  /// toggleMergeAndCenter API.
  void toggleMergeAndCenter() {
    if (!canMergeAndCenter) {
      return;
    }
    if (hasMergedSelection &&
        (selection.range.isSingleCell ||
            (sheet.merges.length == 1 &&
                sheet.merges.first.equalsRange(selection.range)))) {
      unmergeCells();
      return;
    }
    mergeAndCenter();
  }

  static const List<String> sheetFillPalette = <String>[
    '000000',
    'FFFFFF',
    'FF0000',
    '00B050',
    '0070C0',
    'FFC000',
    '7030A0',
    'F4B183',
    'BDD7EE',
    'C6EFCE',
    '',
  ];

  /// fillRgb of the active cell.
  String get selectionFillRgb => sheet.cell(activeCell).fillRgb;

  /// fontRgb of the active cell.
  String get selectionFontRgb => sheet.cell(activeCell).fontRgb;

  /// Bold state of the active cell.
  bool get selectionFontBold => sheet.cell(activeCell).fontBold;

  /// Font size of the active cell.
  double get selectionFontSize => sheet.cell(activeCell).fontSize;

  /// Font family of the active cell.
  String get selectionFontFamily {
    final String family = sheet.cell(activeCell).fontFamily.trim();
    return family.isEmpty ? 'Calibri' : family;
  }

  /// Sets a finite font family on the selected cells.
  void setSelectionFontFamily(String family) {
    final String next = family.trim();
    if (next.isEmpty || next.length > 256) return;
    _applySelectionStyle(
      (SmlCell cell) => cell.fontFamily = next,
      needsChange: (SmlCell? cell) =>
          (cell?.fontFamily.trim().isEmpty ?? true) ||
          cell!.fontFamily.trim() != next,
    );
  }

  /// Sets bold on the selected cells as one reversible formatting command.
  void setSelectionFontBold(bool bold) {
    _applySelectionStyle(
      (SmlCell cell) => cell.fontBold = bold,
      needsChange: (SmlCell? cell) => (cell?.fontBold ?? false) != bold,
    );
  }

  /// Sets a finite, positive font size in points on the selected cells.
  void setSelectionFontSize(double size) {
    if (!size.isFinite || size <= 0) {
      return;
    }
    _applySelectionStyle(
      (SmlCell cell) => cell.fontSize = size,
      needsChange: (SmlCell? cell) => (cell?.fontSize ?? 11) != size,
    );
  }

  /// Sets horizontal alignment on the selected cells.
  void setSelectionHorizontalAlign(SmlHAlign align) {
    _applySelectionStyle(
      (SmlCell cell) => cell.horizontalAlign = align,
      needsChange: (SmlCell? cell) =>
          (cell?.horizontalAlign ?? SmlHAlign.general) != align,
    );
  }

  /// Resets the host ribbon's six formatting fields: bold, size, horizontal
  /// alignment, fill color, font color, and style index. Other modeled cell
  /// properties are outside this command's scope. Clearing colors is explicit,
  /// even when an imported native fill or font has an empty modeled RGB.
  void clearSelectionFormatting() {
    _applySelectionStyle((SmlCell cell) {
      cell
        ..fontBold = false
        ..fontSize = 11
        ..fontFamily = ''
        ..horizontalAlign = SmlHAlign.general
        ..fillRgb = ''
        ..fontRgb = ''
        ..styleIndex = 0;
    });
  }

  void _applySelectionStyle(
    void Function(SmlCell) update, {
    bool Function(SmlCell?)? needsChange,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlWorksheet target = sheet;
    final SmlRange range = selection.range;
    final bool hasChange = range.cells.any(
      (SmlCellRef ref) =>
          !target.isCovered(ref.col, ref.row) &&
          (needsChange?.call(target.cellOrNull(ref)) ?? true),
    );
    if (!hasChange) {
      return;
    }
    _mutateSheetGrid((SmlWorksheet owner) {
      for (final SmlCellRef ref in range.cells) {
        if (!owner.isCovered(ref.col, ref.row)) {
          update(owner.cell(ref));
        }
      }
    });
    notifyListeners();
  }

  /// setSelectionFillRgb API.
  void setSelectionFillRgb(String rgb) {
    if (!config.allowsMutation) {
      return;
    }
    final String next = SmlStyleSheet.normalizeRgb(rgb);
    final SmlRange range = selection.range;
    _mutateSheetGrid((SmlWorksheet target) {
      for (final SmlCellRef ref in range.cells) {
        if (target.isCovered(ref.col, ref.row)) {
          continue;
        }
        target.cell(ref).fillRgb = next;
      }
    });
    notifyListeners();
  }

  /// setSelectionFontRgb API.
  void setSelectionFontRgb(String rgb) {
    if (!config.allowsMutation) {
      return;
    }
    final String next = SmlStyleSheet.normalizeRgb(rgb);
    final SmlRange range = selection.range;
    _mutateSheetGrid((SmlWorksheet target) {
      for (final SmlCellRef ref in range.cells) {
        if (target.isCovered(ref.col, ref.row)) {
          continue;
        }
        target.cell(ref).fontRgb = next;
      }
    });
    notifyListeners();
  }

  /// cycleSelectionFillRgb API.
  void cycleSelectionFillRgb() {
    final int i = sheetFillPalette.indexOf(selectionFillRgb.toUpperCase());
    setSelectionFillRgb(sheetFillPalette[(i + 1) % sheetFillPalette.length]);
  }

  /// cycleSelectionFontRgb API.
  void cycleSelectionFontRgb() {
    final int i = sheetFillPalette.indexOf(selectionFontRgb.toUpperCase());
    setSelectionFontRgb(sheetFillPalette[(i + 1) % sheetFillPalette.length]);
  }

  /// selectedDrawing API.
  SmlDrawing? get selectedDrawing {
    final int? index = selectedDrawingIndex;
    if (index == null || index < 0 || index >= sheet.drawings.length) {
      return null;
    }
    return sheet.drawings[index];
  }

  /// selectDrawing API.
  void selectDrawing(int? index) {
    if (!config.allowsSelection) {
      selectedDrawingIndex = null;
      notifyListeners();
      return;
    }
    selectedDrawingIndex = index;
    notifyListeners();
  }

  /// deleteSelectedDrawing API.
  void deleteSelectedDrawing() {
    final int? index = selectedDrawingIndex;
    if (index == null || !config.allowsMutation) {
      return;
    }
    if (index < 0 || index >= sheet.drawings.length) {
      return;
    }
    final SmlDrawing drawing = sheet.drawings[index];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          sheet.drawings.remove(drawing);
          selectedDrawingIndex = null;
        },
        undoFn: () {
          if (!sheet.drawings.contains(drawing)) {
            sheet.drawings.insert(
              index.clamp(0, sheet.drawings.length),
              drawing,
            );
          }
          selectedDrawingIndex = sheet.drawings.indexOf(drawing);
        },
      ),
    );
    notifyListeners();
  }

  /// nudgeSelectedDrawing API.
  void nudgeSelectedDrawing(int dc, int dr) {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null || !config.allowsMutation) {
      return;
    }
    if (dc == 0 && dr == 0) {
      return;
    }
    final int prevCol = drawing.col;
    final int prevRow = drawing.row;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          drawing.col = (drawing.col + dc).clamp(0, 16383);
          drawing.row = (drawing.row + dr).clamp(0, 1048575);
        },
        undoFn: () {
          drawing.col = prevCol;
          drawing.row = prevRow;
        },
      ),
    );
    notifyListeners();
  }

  ({int col, int row, double ox, double oy, double w, double h})? _drawingSnap;

  /// beginDrawingTransform API.
  void beginDrawingTransform() {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null) {
      return;
    }
    _drawingSnap = (
      col: drawing.col,
      row: drawing.row,
      ox: drawing.offsetX,
      oy: drawing.offsetY,
      w: drawing.visual.width,
      h: drawing.visual.height,
    );
  }

  /// previewDrawingMove API.
  void previewDrawingMove(double dx, double dy) {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null || !config.allowsMutation) {
      return;
    }
    _placeDrawing(
      drawing,
      sheet.columnLeft(drawing.col) + drawing.offsetX + dx,
      sheet.rowTop(drawing.row) + drawing.offsetY + dy,
    );
    notifyListeners();
  }

  /// previewDrawingResize API.
  void previewDrawingResize({
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null || !config.allowsMutation) {
      return;
    }
    drawing.visual.width = width.clamp(40, 1200);
    drawing.visual.height = height.clamp(40, 800);
    _placeDrawing(drawing, left, top);
    notifyListeners();
  }

  /// commitDrawingTransform API.
  void commitDrawingTransform() {
    final SmlDrawing? drawing = selectedDrawing;
    final snap = _drawingSnap;
    _drawingSnap = null;
    if (drawing == null || snap == null || !config.allowsMutation) {
      return;
    }
    final int col = drawing.col;
    final int row = drawing.row;
    final double ox = drawing.offsetX;
    final double oy = drawing.offsetY;
    final double w = drawing.visual.width;
    final double h = drawing.visual.height;
    if (col == snap.col &&
        row == snap.row &&
        ox == snap.ox &&
        oy == snap.oy &&
        w == snap.w &&
        h == snap.h) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          drawing
            ..col = col
            ..row = row
            ..offsetX = ox
            ..offsetY = oy;
          drawing.visual
            ..width = w
            ..height = h;
        },
        undoFn: () {
          drawing
            ..col = snap.col
            ..row = snap.row
            ..offsetX = snap.ox
            ..offsetY = snap.oy;
          drawing.visual
            ..width = snap.w
            ..height = snap.h;
        },
      ),
    );
    notifyListeners();
  }

  void _placeDrawing(SmlDrawing drawing, double x, double y) {
    final double px = x.clamp(
      0,
      sheet.columnLeft(SmlWorksheet.excelColumnCount - 1),
    );
    final double py = y.clamp(0, sheet.rowTop(SmlWorksheet.excelRowCount - 1));
    drawing.col = sheet.columnAt(px);
    drawing.row = sheet.rowAt(py);
    drawing.offsetX = px - sheet.columnLeft(drawing.col);
    drawing.offsetY = py - sheet.rowTop(drawing.row);
  }

  /// updateSelectedDrawing API.
  void updateSelectedDrawing({
    String? title,
    OfficeVisualKind? kind,
    List<ChartPoint>? points,
    double? width,
    double? height,
  }) {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null || !config.allowsMutation) {
      return;
    }
    final OfficeVisual visual = drawing.visual;
    final OfficeVisualKind prevKind = visual.kind;
    final String prevTitle = visual.title;
    final List<ChartPoint> prevPoints = List<ChartPoint>.from(visual.points);
    final double prevW = visual.width;
    final double prevH = visual.height;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (title != null) {
            visual.title = title;
          }
          if (kind != null) {
            visual.kind = kind;
          }
          if (points != null) {
            visual.points
              ..clear()
              ..addAll(points);
          }
          if (width != null) {
            visual.width = width;
          }
          if (height != null) {
            visual.height = height;
          }
        },
        undoFn: () {
          visual
            ..kind = prevKind
            ..title = prevTitle
            ..width = prevW
            ..height = prevH;
          visual.points
            ..clear()
            ..addAll(prevPoints);
        },
      ),
    );
    notifyListeners();
  }

  /// mutateSelectedDrawing API.
  void mutateSelectedDrawing(void Function(OfficeVisual visual) edit) {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null || !config.allowsMutation) {
      return;
    }
    final OfficeVisual visual = drawing.visual;
    final OfficeVisual before = visual.copy();
    edit(visual);
    final OfficeVisual after = visual.copy();
    commands.commit(
      _CallbackCommand(
        executeFn: () => visual.restoreFrom(after),
        undoFn: () => visual.restoreFrom(before),
      ),
    );
    notifyListeners();
  }

  /// cycleSelectedDrawingKind API.
  void cycleSelectedDrawingKind() {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing == null) {
      return;
    }
    updateSelectedDrawing(
      kind: WordEditorController._nextVisualKind(drawing.visual.kind),
    );
  }

  @override
  /// selectAll API.
  void selectAll() {
    if (!config.allowsSelection) {
      return;
    }
    if (cellEditor.editing) {
      cellEditor.selectAll();
      notifyListeners();
      return;
    }
    selectedDrawingIndex = null;
    var maxCol = 0;
    var maxRow = 0;
    var any = false;
    for (final SmlCell cell in sheet.allCells) {
      if ((cell.value == null || cell.asString.isEmpty) &&
          (cell.formula == null || cell.formula!.isEmpty)) {
        continue;
      }
      any = true;
      if (cell.ref.col > maxCol) {
        maxCol = cell.ref.col;
      }
      if (cell.ref.row > maxRow) {
        maxRow = cell.ref.row;
      }
    }
    for (final SmlDrawing drawing in sheet.drawings) {
      any = true;
      if (drawing.col > maxCol) {
        maxCol = drawing.col;
      }
      if (drawing.row > maxRow) {
        maxRow = drawing.row;
      }
    }
    if (!any) {
      selection.selectCell(const SmlCellRef(0, 0));
    } else {
      selection.anchor = const SmlCellRef(0, 0);
      selection.focus = SmlCellRef(maxCol, maxRow);
    }
    notifyListeners();
  }

  /// moveSelection API.
  void moveSelection(int dc, int dr, {bool extend = false}) {
    if (!config.allowsSelection) {
      return;
    }
    if (selectedDrawingIndex != null && !extend) {
      nudgeSelectedDrawing(dc, dr);
      return;
    }
    selectedDrawingIndex = null;
    var col = selection.focus.col + dc;
    var row = selection.focus.row + dr;
    final SmlMerge? current = sheet.mergeAtRef(selection.focus);
    if (current != null && !extend) {
      if (dc > 0) {
        col = current.c1 + 1;
      } else if (dc < 0) {
        col = current.c0 - 1;
      }
      if (dr > 0) {
        row = current.r1 + 1;
      } else if (dr < 0) {
        row = current.r0 - 1;
      }
    }
    moveSelectionTo(SmlCellRef(col, row), extend: extend);
  }

  /// jumpSelectionByOccupancy API.
  void jumpSelectionByOccupancy(int dc, int dr, {bool extend = false}) {
    if (!config.allowsSelection) {
      return;
    }
    selectedDrawingIndex = null;
    moveSelectionTo(
      sheet.sameOccupancy(selection.focus, dc, dr),
      extend: extend,
    );
  }

  /// moveSelectionTo API.
  void moveSelectionTo(SmlCellRef ref, {bool extend = false}) {
    if (!config.allowsSelection) {
      return;
    }
    selectedDrawingIndex = null;
    final SmlCellRef next = SmlCellRef(
      ref.col.clamp(0, SmlWorksheet.excelColumnCount - 1),
      ref.row.clamp(0, SmlWorksheet.excelRowCount - 1),
    );
    if (extend) {
      final SmlMerge? merge = sheet.mergeAtRef(next);
      if (merge == null) {
        selection.extendTo(next);
      } else {
        final bool preferMax =
            next.col >= selection.anchor.col &&
            next.row >= selection.anchor.row;
        selection.extendTo(
          preferMax ? SmlCellRef(merge.c1, merge.r1) : merge.origin,
        );
      }
    } else {
      final SmlMerge? merge = sheet.mergeAtRef(next);
      if (merge == null) {
        selection.selectCell(next);
      } else {
        selection.selectCell(merge.origin);
      }
    }
    ensureCellVisible();
    notifyListeners();
  }

  /// panSheet API.
  void panSheet(Offset delta, {bool zoom = false}) {
    if (zoom) {
      viewport.setScale(viewport.scale * (delta.dy > 0 ? 0.9 : 1.1));
    } else {
      viewport.pan(delta);
    }
    clampSheetViewport();
    notifyListeners();
  }

  /// visibleRowPage API.
  int get visibleRowPage {
    final double inner = viewport.extent.height - 48;
    final double h = sheet.rowHeightAt(selection.focus.row) * viewport.scale;
    if (inner <= 0 || h <= 0) {
      return 10;
    }
    return (inner / h).floor().clamp(1, 200);
  }

  /// visibleColPage API.
  int get visibleColPage {
    final double inner = viewport.extent.width - 28;
    final double w = sheet.columnWidth(selection.focus.col) * viewport.scale;
    if (inner <= 0 || w <= 0) {
      return 8;
    }
    return (inner / w).floor().clamp(1, 64);
  }

  /// scrollTarget API.
  SmlCellRef scrollTarget([SmlCellRef? ref]) {
    final SmlCellRef cell = ref ?? selection.focus;
    if (selection.isFullRowSelection) {
      return SmlCellRef(lastUsedCell().col, cell.row);
    }
    if (selection.isFullColumnSelection) {
      return SmlCellRef(cell.col, lastUsedCell().row);
    }
    return cell;
  }

  /// lastUsedCell API.
  SmlCellRef lastUsedCell() {
    var maxC = 0;
    var maxR = 0;
    var any = false;
    for (final SmlCell cell in sheet.allCells) {
      if ((cell.value == null || cell.asString.isEmpty) &&
          (cell.formula == null || cell.formula!.isEmpty)) {
        continue;
      }
      any = true;
      if (cell.ref.col > maxC) {
        maxC = cell.ref.col;
      }
      if (cell.ref.row > maxR) {
        maxR = cell.ref.row;
      }
    }
    return any ? SmlCellRef(maxC, maxR) : const SmlCellRef(0, 0);
  }

  /// lastUsedColOnRow API.
  int lastUsedColOnRow(int row) {
    final SmlRow? data = sheet.rows[row];
    if (data == null || data.cells.isEmpty) {
      return 0;
    }
    var maxC = 0;
    for (final SmlCell cell in data.cells.values) {
      if ((cell.value == null || cell.asString.isEmpty) &&
          (cell.formula == null || cell.formula!.isEmpty)) {
        continue;
      }
      if (cell.ref.col > maxC) {
        maxC = cell.ref.col;
      }
    }
    return maxC;
  }

  /// ensureCellVisible API.
  void ensureCellVisible([SmlCellRef? ref]) {
    final SmlCellRef cell = ref ?? scrollTarget();
    final double scale = viewport.scale <= 0 ? 1 : viewport.scale;
    final double headW = config.showGridHeaders ? 28 : 0;
    final double headH = config.showGridHeaders ? 20 : 0;
    final double barH = config.showFormulaBar ? 28 : 0;
    final Size view = viewport.extent;
    final double frozenW = sheet.columnLeft(sheet.freezeCols) * scale;
    final double frozenH = sheet.rowTop(sheet.freezeRows) * scale;
    final double viewW = view.width > headW + 1 ? view.width - headW : 1;
    final double viewH = view.height > barH + headH + 1
        ? view.height - barH - headH
        : 1;
    final double left = sheet.columnLeft(cell.col) * scale;
    final double right = left + sheet.columnWidth(cell.col) * scale;
    final double top = sheet.rowTop(cell.row) * scale;
    final double bottom = top + sheet.rowHeightAt(cell.row) * scale;
    var ox = viewport.origin.dx;
    var oy = viewport.origin.dy;
    if (cell.col >= sheet.freezeCols) {
      if (left - ox < frozenW) {
        ox = left - frozenW;
      } else if (right > ox + viewW) {
        ox = right - viewW;
      }
    }
    if (cell.row >= sheet.freezeRows) {
      if (top - oy < frozenH) {
        oy = top - frozenH;
      } else if (bottom > oy + viewH) {
        oy = bottom - viewH;
      }
    }
    viewport.origin = Offset(ox, oy);
    clampSheetViewport();
  }

  /// clampSheetViewport API.
  void clampSheetViewport() {
    final double scale = viewport.scale <= 0 ? 1 : viewport.scale;
    final double headW = config.showGridHeaders ? 28 : 0;
    final double headH = config.showGridHeaders ? 20 : 0;
    final double barH = config.showFormulaBar ? 28 : 0;
    final Size view = viewport.extent.width <= 0 || viewport.extent.height <= 0
        ? const Size(800, 600)
        : viewport.extent;
    viewport.clampTo(
      content: SheetScrollExtent.contentSize(
        sheet: sheet,
        selection: selection,
        scale: scale,
        headW: headW,
        headH: headH,
        barH: barH,
      ),
      view: view,
    );
  }

  List<int> _columnsForResize(int col) {
    if (selection.isFullColumnSelection &&
        selection.contains(SmlCellRef(col, 0))) {
      final int c0 = selection.anchor.col < selection.focus.col
          ? selection.anchor.col
          : selection.focus.col;
      final int c1 = selection.anchor.col > selection.focus.col
          ? selection.anchor.col
          : selection.focus.col;
      return <int>[for (int c = c0; c <= c1; c++) c];
    }
    return <int>[col];
  }

  List<int> _rowsForResize(int row) {
    if (selection.isFullRowSelection &&
        selection.contains(SmlCellRef(0, row))) {
      final int r0 = selection.anchor.row < selection.focus.row
          ? selection.anchor.row
          : selection.focus.row;
      final int r1 = selection.anchor.row > selection.focus.row
          ? selection.anchor.row
          : selection.focus.row;
      return <int>[for (int r = r0; r <= r1; r++) r];
    }
    return <int>[row];
  }

  Map<int, SmlColumnSnapshot>? _resizeFromCols;
  Map<int, double?>? _resizeFromRows;
  SmlWorksheet? _columnResizeSheet;
  SmlWorksheet? _rowResizeSheet;

  void _restoreRowResize(SmlWorksheet target, Map<int, double?> values) {
    for (final entry in values.entries) {
      if (entry.value == null) {
        target.rowHeights.remove(entry.key);
      } else {
        target.rowHeights[entry.key] = entry.value!;
      }
    }
  }

  void _cancelResize() {
    final columns = _resizeFromCols;
    final columnTarget = _columnResizeSheet;
    if (columns != null && columnTarget != null) {
      for (final entry in columns.entries) {
        columnTarget.restoreColumn(entry.key, entry.value, widthOnly: true);
      }
    }
    final rows = _resizeFromRows;
    final rowTarget = _rowResizeSheet;
    if (rows != null && rowTarget != null) _restoreRowResize(rowTarget, rows);
    _resizeFromCols = null;
    _resizeFromRows = null;
    _columnResizeSheet = null;
    _rowResizeSheet = null;
  }

  /// previewColumnWidth API.
  void previewColumnWidth(int col, double px) {
    if (!config.allowsMutation) return;
    final target = sheet;
    if (_resizeFromRows != null ||
        (_columnResizeSheet != null &&
            !identical(_columnResizeSheet, target))) {
      commitResize();
    }
    final List<int> cols = _columnsForResize(col);
    final original = _resizeFromCols ??= <int, SmlColumnSnapshot>{};
    _columnResizeSheet = target;
    for (final int c in cols) {
      original.putIfAbsent(c, () => target.captureColumn(c));
      target.setColumnWidth(c, px);
    }
    notifyListeners();
  }

  /// previewRowHeight API.
  void previewRowHeight(int row, double px) {
    if (!config.allowsMutation) return;
    final target = sheet;
    if (_resizeFromCols != null ||
        (_rowResizeSheet != null && !identical(_rowResizeSheet, target))) {
      commitResize();
    }
    final List<int> rows = _rowsForResize(row);
    final original = _resizeFromRows ??= <int, double?>{};
    _rowResizeSheet = target;
    for (final int r in rows) {
      original.putIfAbsent(r, () => target.rowHeights[r]);
      target.setRowHeight(r, px);
    }
    notifyListeners();
  }

  /// Commits to the worksheet captured at preview, even after tab navigation.
  /// Losing mutation permission restores previews without history or dirtiness.
  void commitResize() {
    if (!config.allowsMutation) {
      _cancelResize();
      return;
    }
    if (_resizeFromCols != null) {
      final target = _columnResizeSheet!;
      if (!workbook.sheets.any((candidate) => identical(candidate, target))) {
        _cancelResize();
        return;
      }
      final from = _resizeFromCols!;
      final to = <int, SmlColumnSnapshot>{
        for (final int c in from.keys) c: target.captureColumn(c),
      };
      _resizeFromCols = null;
      _columnResizeSheet = null;
      var changed = false;
      for (final int c in from.keys) {
        if ((target.projectedColumnWidth(to[c]!) -
                    target.projectedColumnWidth(from[c]!))
                .abs() >=
            0.5) {
          changed = true;
          break;
        }
      }
      for (final entry in from.entries) {
        target.restoreColumn(entry.key, entry.value, widthOnly: true);
      }
      if (!changed) return;
      commands.commit(
        _CallbackCommand(
          executeFn: () {
            for (final entry in to.entries) {
              target.restoreColumn(entry.key, entry.value, widthOnly: true);
            }
          },
          undoFn: () {
            for (final entry in from.entries) {
              target.restoreColumn(entry.key, entry.value, widthOnly: true);
            }
          },
        ),
      );
      return;
    }
    if (_resizeFromRows != null) {
      final target = _rowResizeSheet!;
      if (!workbook.sheets.any((candidate) => identical(candidate, target))) {
        _cancelResize();
        return;
      }
      final from = _resizeFromRows!;
      final to = <int, double?>{
        for (final int r in from.keys) r: target.rowHeights[r],
      };
      _resizeFromRows = null;
      _rowResizeSheet = null;
      final changed = from.keys.any(
        (r) =>
            ((to[r] ?? SmlWorksheet.defaultRowHeightPx) -
                    (from[r] ?? SmlWorksheet.defaultRowHeightPx))
                .abs() >=
            0.5,
      );
      _restoreRowResize(target, from);
      if (!changed) return;
      commands.commit(
        _CallbackCommand(
          executeFn: () => _restoreRowResize(target, to),
          undoFn: () => _restoreRowResize(target, from),
        ),
      );
    }
  }

  /// nudgeColumnWidth API.
  void nudgeColumnWidth(double delta) {
    if (!config.allowsMutation) {
      return;
    }
    final int col = selection.focus.col;
    previewColumnWidth(col, sheet.columnWidth(col) + delta);
    commitResize();
  }

  /// nudgeRowHeight API.
  void nudgeRowHeight(double delta) {
    if (!config.allowsMutation) {
      return;
    }
    final int row = selection.focus.row;
    previewRowHeight(row, sheet.rowHeightAt(row) + delta);
    commitResize();
  }

  @override
  /// canCopy API.
  bool get canCopy => true;

  @override
  /// copyToClipboard API.
  Future<void> copyToClipboard() async {
    await OfficeClipboard.instance.write(_captureSheetClipboard());
  }

  @override
  /// cutToClipboard API.
  Future<void> cutToClipboard() async {
    if (!canCut) {
      return;
    }
    await copyToClipboard();
    if (cellEditor.editing) {
      _replaceCellEditorSelection('');
      return;
    }
    clearSelectedCells();
  }

  @override
  /// pasteFromClipboard API.
  Future<void> pasteFromClipboard({
    OfficePasteMode mode = OfficePasteMode.keepSource,
  }) async {
    if (!canPaste) {
      return;
    }
    final OfficeClipboardPayload payload = await OfficeClipboard.instance
        .read();
    if (payload.isEmpty) {
      return;
    }
    if (cellEditor.editing) {
      _replaceCellEditorSelection(payload.plain);
      return;
    }
    if (mode != OfficePasteMode.keepTextOnly && payload.hasCells) {
      _pasteSheetCells(
        payload.cells,
        formulas: mode == OfficePasteMode.keepSource,
      );
      return;
    }
    _pasteSheetTsv(payload.plain, formulas: mode == OfficePasteMode.keepSource);
  }

  OfficeClipboardPayload _captureSheetClipboard() {
    if (cellEditor.editing) {
      final String text = cellEditor.hasSelection
          ? cellEditor.formulaBar.substring(
              cellEditor.selectionStart,
              cellEditor.selectionEnd,
            )
          : cellEditor.formulaBar;
      return OfficeClipboardPayload.fromPlain(text);
    }
    final SmlRange range = selection.range;
    var r0 = range.start.row < range.end.row ? range.start.row : range.end.row;
    var r1 = range.start.row > range.end.row ? range.start.row : range.end.row;
    var c0 = range.start.col < range.end.col ? range.start.col : range.end.col;
    var c1 = range.start.col > range.end.col ? range.start.col : range.end.col;
    if (r1 - r0 > 1000 || c1 - c0 > 256) {
      var usedR = selection.focus.row;
      var usedC = selection.focus.col;
      for (final int row in sheet.rows.keys) {
        if (row > usedR) {
          usedR = row;
        }
        for (final int col in sheet.rows[row]!.cells.keys) {
          if (col > usedC) {
            usedC = col;
          }
        }
      }
      if (r1 > usedR) {
        r1 = usedR;
      }
      if (c1 > usedC) {
        c1 = usedC;
      }
    }
    final List<List<OfficeClipboardCell>> rows = <List<OfficeClipboardCell>>[];
    final StringBuffer tsv = StringBuffer();
    for (int r = r0; r <= r1; r++) {
      final List<OfficeClipboardCell> row = <OfficeClipboardCell>[];
      for (int c = c0; c <= c1; c++) {
        final SmlCell cell = sheet.cell(SmlCellRef(c, r));
        final String text = cell.formula ?? cell.asString;
        row.add(
          OfficeClipboardCell(
            value: cell.value,
            formula: cell.formula,
            type: cell.type,
            text: text,
          ),
        );
      }
      rows.add(row);
      if (r > r0) {
        tsv.write('\n');
      }
      tsv.write(row.map((OfficeClipboardCell cell) => cell.text).join('\t'));
    }
    return OfficeClipboardPayload(
      kind: OfficeClipboardKind.cells,
      plain: tsv.toString(),
      cells: rows,
    );
  }

  void _replaceCellEditorSelection(String insert) {
    cellEditor.replaceRange(
      cellEditor.selectionStart,
      cellEditor.selectionEnd,
      insert,
    );
  }

  void _pasteSheetCells(
    List<List<OfficeClipboardCell>> rows, {
    required bool formulas,
  }) {
    if (rows.isEmpty) {
      return;
    }
    final int originC = selection.range.start.col < selection.range.end.col
        ? selection.range.start.col
        : selection.range.end.col;
    final int originR = selection.range.start.row < selection.range.end.row
        ? selection.range.start.row
        : selection.range.end.row;
    commands.beginBatch();
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        final OfficeClipboardCell snap = rows[r][c];
        final SmlCell cell = sheet.cell(SmlCellRef(originC + c, originR + r));
        final Object? prevValue = cell.value;
        final String? prevFormula = cell.formula;
        final SmlCellType prevType = cell.type;
        commands.commit(
          _CallbackCommand(
            executeFn: () {
              if (formulas && snap.formula != null) {
                cell.formula = snap.formula;
                cell.type = snap.type;
                cell.value = snap.value;
              } else {
                _applyCellText(cell, snap.text);
              }
            },
            undoFn: () {
              cell.value = prevValue;
              cell.formula = prevFormula;
              cell.type = prevType;
            },
          ),
        );
      }
    }
    commands.endBatch();
    recalculateWorkbook();
    notifyListeners();
  }

  void _pasteSheetTsv(String text, {required bool formulas}) {
    final List<List<String>> rows = OfficeClipboardPayload.parseTsv(text);
    if (rows.isEmpty) {
      return;
    }
    _pasteSheetCells(<List<OfficeClipboardCell>>[
      for (final List<String> row in rows)
        <OfficeClipboardCell>[
          for (final String cell in row)
            OfficeClipboardCell(
              text: cell,
              value: cell,
              type: SmlCellType.string,
            ),
        ],
    ], formulas: formulas);
  }

  /// clearSelectedCells API.
  void clearSelectedCells() {
    if (!config.allowsMutation || cellEditor.editing) {
      return;
    }
    if (selectedDrawingIndex != null) {
      deleteSelectedDrawing();
      return;
    }
    commands.beginBatch();
    for (final SmlRow row in sheet.rows.values) {
      for (final SmlCell cell in row.cells.values) {
        if (selection.contains(cell.ref) &&
            (cell.value != null || cell.formula != null)) {
          _clearCell(cell);
        }
      }
    }
    final SmlCell focus = sheet.cell(selection.focus);
    if (focus.value != null || focus.formula != null) {
      _clearCell(focus);
    }
    commands.endBatch();
    recalculateWorkbook();
    notifyListeners();
  }

  /// insertSheetRows API.
  void insertSheetRows({required bool after, int? index, int count = 1}) {
    if (!config.allowsMutation || count <= 0) {
      return;
    }
    final SmlRange range = selection.range;
    final int minRow = range.start.row < range.end.row
        ? range.start.row
        : range.end.row;
    final int maxRow = range.start.row > range.end.row
        ? range.start.row
        : range.end.row;
    final int at = index ?? (after ? maxRow + 1 : minRow);
    _mutateSheetGrid((SmlWorksheet target) => target.insertRows(at, count));
    selection.selectCell(SmlCellRef(selection.focus.col, at.clamp(0, 1048575)));
    notifyListeners();
  }

  /// insertSheetCols API.
  void insertSheetCols({required bool after, int? index, int count = 1}) {
    if (!config.allowsMutation || count <= 0) {
      return;
    }
    final SmlRange range = selection.range;
    final int minCol = range.start.col < range.end.col
        ? range.start.col
        : range.end.col;
    final int maxCol = range.start.col > range.end.col
        ? range.start.col
        : range.end.col;
    final int at = index ?? (after ? maxCol + 1 : minCol);
    _mutateSheetGrid((SmlWorksheet target) => target.insertCols(at, count));
    selection.selectCell(SmlCellRef(at.clamp(0, 16383), selection.focus.row));
    notifyListeners();
  }

  /// deleteSheetRows API.
  void deleteSheetRows({int? index, int count = 1}) {
    if (!config.allowsMutation || count <= 0) {
      return;
    }
    final SmlRange range = selection.range;
    final int minRow = range.start.row < range.end.row
        ? range.start.row
        : range.end.row;
    final int at = index ?? minRow;
    _mutateSheetGrid((SmlWorksheet target) => target.deleteRows(at, count));
    selection.selectCell(SmlCellRef(selection.focus.col, at.clamp(0, 1048575)));
    notifyListeners();
  }

  /// deleteSheetCols API.
  void deleteSheetCols({int? index, int count = 1}) {
    if (!config.allowsMutation || count <= 0) {
      return;
    }
    final SmlRange range = selection.range;
    final int minCol = range.start.col < range.end.col
        ? range.start.col
        : range.end.col;
    final int at = index ?? minCol;
    _mutateSheetGrid((SmlWorksheet target) => target.deleteCols(at, count));
    selection.selectCell(SmlCellRef(at.clamp(0, 16383), selection.focus.row));
    notifyListeners();
  }

  /// Function API.
  void _mutateSheetGrid(void Function(SmlWorksheet) mutate) {
    final SmlWorksheet target = sheet;
    final _SheetGridSnap before = _SheetGridSnap.capture(target);
    _SheetGridSnap? after;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          final _SheetGridSnap? capturedAfter = after;
          if (capturedAfter == null) {
            mutate(target);
            recalculateWorkbook();
            after = _SheetGridSnap.capture(target);
            return;
          }
          capturedAfter.restore(target);
          recalculateWorkbook();
        },
        undoFn: () {
          before.restore(target);
          recalculateWorkbook();
        },
      ),
    );
  }

  void _clearCell(SmlCell cell) {
    final Object? prevValue = cell.value;
    final String? prevFormula = cell.formula;
    final SmlCellType prevType = cell.type;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          cell.value = null;
          cell.formula = null;
          cell.type = SmlCellType.string;
        },
        undoFn: () {
          cell.value = prevValue;
          cell.formula = prevFormula;
          cell.type = prevType;
        },
      ),
    );
  }

  /// beginCellEdit API.
  void beginCellEdit({String? initial, bool replace = false, int? caret}) {
    if (!config.allowsMutation) {
      return;
    }
    commitCellEdit();
    final SmlCell lockedCell = sheet.cell(activeCell);
    if (sheet.protection?.enabled == true && lockedCell.locked) {
      lastValidationError = 'The sheet is protected.';
      notifyListeners();
      return;
    }
    if (selectedDrawingIndex != null && initial == null) {
      cycleSelectedDrawingKind();
      return;
    }
    selectedDrawingIndex = null;
    _clearPoint();
    final SmlCell cell = sheet.cell(activeCell);
    _cellEditSheet = sheet;
    _cellEditCell = cell;
    _cellTextBeforeEdit = cell.formula ?? cell.asString;
    _cellTextLastObserved = _cellTextBeforeEdit;
    final String seed = initial ?? (replace ? '' : _cellTextBeforeEdit!);
    cellEditor.begin(seed, caret: caret);
    _refreshFunctionSuggestions();
    notifyListeners();
  }

  /// canPointEditRefs API.
  bool get canPointEditRefs {
    if (!cellEditor.editing) {
      return false;
    }
    final String text = cellEditor.formulaBar.trimLeft();
    return text.isEmpty || text.startsWith('=');
  }

  /// Inserts or replaces a cell/range reference while the formula is open.
  void pointEditRef(SmlCellRef ref, {bool extend = false}) {
    if (!canPointEditRefs) {
      return;
    }
    final String lexeme = extend && _pointAnchor != null
        ? _refLexeme(_pointAnchor!, ref)
        : ref.a1;
    if (!extend) {
      _pointAnchor = ref;
    }
    final bool prefixEquals = cellEditor.formulaBar.isEmpty;
    final (int start, int end) = _pointReplaceRange();
    final String insert = prefixEquals ? '=$lexeme' : lexeme;
    _applyingPoint = true;
    cellEditor.replaceRange(start, end, insert);
    _applyingPoint = false;
    _pointStart = prefixEquals ? 1 : start;
    _pointEnd = _pointStart! + lexeme.length;
    notifyListeners();
  }

  void _onCellEditorChanged() {
    if (cellEditor.editing && _cellTextLastObserved != cellEditor.formulaBar) {
      _cellTextLastObserved = cellEditor.formulaBar;
      _contentRevision++;
    }
    if (!_applyingPoint) {
      _clearPoint();
      _suppressFunctionSuggestions = false;
    }
    _refreshFunctionSuggestions();
    notifyListeners();
  }

  /// highlightedFunction API.
  FormulaFnDoc? get highlightedFunction {
    if (functionSuggestions.isEmpty) {
      return null;
    }
    return functionSuggestions[functionSuggestionIndex.clamp(
      0,
      functionSuggestions.length - 1,
    )];
  }

  /// highlightFunctionSuggestion API.
  void highlightFunctionSuggestion(int index) {
    if (functionSuggestions.isEmpty) {
      return;
    }
    functionSuggestionIndex = index.clamp(0, functionSuggestions.length - 1);
    notifyListeners();
  }

  /// moveFunctionSuggestion API.
  void moveFunctionSuggestion(int delta) {
    if (functionSuggestions.isEmpty) {
      return;
    }
    highlightFunctionSuggestion(functionSuggestionIndex + delta);
  }

  /// dismissFunctionSuggestions API.
  void dismissFunctionSuggestions() {
    _suppressedFunctionPrefix = FormulaFunctionGuide.queryAt(
      cellEditor.formulaBar,
      cellEditor.caretIndex,
    )?.prefix;
    _suppressFunctionSuggestions = true;
    functionSuggestions = const <FormulaFnDoc>[];
    functionSuggestionIndex = 0;
    notifyListeners();
  }

  /// applyFunctionSuggestion API.
  bool applyFunctionSuggestion([int? index]) {
    if (functionSuggestions.isEmpty) {
      return false;
    }
    final FormulaNameQuery? query = FormulaFunctionGuide.queryAt(
      cellEditor.formulaBar,
      cellEditor.caretIndex,
    );
    if (query == null) {
      return false;
    }
    final FormulaFnDoc doc =
        functionSuggestions[(index ?? functionSuggestionIndex).clamp(
          0,
          functionSuggestions.length - 1,
        )];
    cellEditor.replaceRange(query.start, query.end, '${doc.name}(');
    return true;
  }

  /// deleteEditBackward API.
  void deleteEditBackward() {
    if (cellEditor.editing) {
      cellEditor.deleteBackward();
    }
  }

  /// deleteEditForward API.
  void deleteEditForward() {
    if (cellEditor.editing) {
      cellEditor.deleteForward();
    }
  }

  void _refreshFunctionSuggestions() {
    if (!cellEditor.editing) {
      functionSuggestions = const <FormulaFnDoc>[];
      functionSuggestionIndex = 0;
      return;
    }
    final FormulaNameQuery? query = FormulaFunctionGuide.queryAt(
      cellEditor.formulaBar,
      cellEditor.caretIndex,
    );
    if (query == null) {
      functionSuggestions = const <FormulaFnDoc>[];
      functionSuggestionIndex = 0;
      _suppressFunctionSuggestions = false;
      return;
    }
    if (_suppressFunctionSuggestions &&
        query.prefix == _suppressedFunctionPrefix) {
      functionSuggestions = const <FormulaFnDoc>[];
      return;
    }
    if (!_suppressFunctionSuggestions &&
        query.prefix != _suppressedFunctionPrefix) {
      functionSuggestionIndex = 0;
    }
    _suppressFunctionSuggestions = false;
    functionSuggestions = FormulaFunctionGuide.search(query.prefix);
    functionSuggestionIndex = functionSuggestionIndex.clamp(
      0,
      functionSuggestions.isEmpty ? 0 : functionSuggestions.length - 1,
    );
  }

  void _clearPoint() {
    _pointStart = null;
    _pointEnd = null;
    _pointAnchor = null;
  }

  (int, int) _pointReplaceRange() {
    if (cellEditor.hasSelection) {
      return (cellEditor.selectionStart, cellEditor.selectionEnd);
    }
    if (_pointStart != null && _pointEnd != null) {
      return (_pointStart!, _pointEnd!);
    }
    final String text = cellEditor.formulaBar;
    final int caret = cellEditor.caretIndex;
    for (final FormulaRefSpan span in FormulaRefScanner.scan(text)) {
      if (caret >= span.start && caret <= span.end) {
        return (span.start, span.end);
      }
    }
    return (caret, caret);
  }

  static String _refLexeme(SmlCellRef a, SmlCellRef b) {
    if (a.col == b.col && a.row == b.row) {
      return a.a1;
    }
    return '${a.a1}:${b.a1}';
  }

  /// placeEditCaret API.
  void placeEditCaret(int index, {bool extend = false}) {
    if (!cellEditor.editing) {
      return;
    }
    cellEditor.setCaret(index, extend: extend);
  }

  /// moveEditCaret API.
  void moveEditCaret(int delta, {bool extend = false}) {
    if (!cellEditor.editing) {
      return;
    }
    cellEditor.moveCaret(delta, extend: extend);
  }

  /// commitCellEdit API.
  void commitCellEdit() {
    _clearPoint();
    functionSuggestions = const <FormulaFnDoc>[];
    cellEditor.end();
  }

  /// cancelCellEdit API.
  void cancelCellEdit() {
    if (!cellEditor.editing) {
      return;
    }
    if (_hasPendingEdits) {
      _contentRevision++;
    }
    _clearPoint();
    functionSuggestions = const <FormulaFnDoc>[];
    cellEditor.editing = false;
    cellEditor.bridge.detach();
    _clearCellEditTracking();
    notifyListeners();
  }

  @override
  /// detachInput API.
  void detachInput() {
    if (cellEditor.editing) {
      cancelCellEdit();
    }
  }

  void _commitFormula(String text) {
    final SmlWorksheet target = _cellEditSheet ?? sheet;
    final SmlCell cell = _cellEditCell ?? target.cell(activeCell);
    final bool discardedDraft =
        _cellTextBeforeEdit != null && text != _cellTextBeforeEdit;
    _clearCellEditTracking();
    if (text == (cell.formula ?? cell.asString)) {
      lastValidationError = null;
      notifyListeners();
      return;
    }
    lastValidationError = _cellInputError(target, cell, text);
    if (lastValidationError != null) {
      if (discardedDraft) {
        _contentRevision++;
      }
      notifyListeners();
      return;
    }
    final Object? prevValue = cell.value;
    final String? prevFormula = cell.formula;
    final SmlCellType prevType = cell.type;
    commands.commit(
      _CallbackCommand(
        executeFn: () =>
            FormulaEvaluator.applyInput(workbook, target, cell, text),
        undoFn: () {
          cell.value = prevValue;
          cell.formula = prevFormula;
          cell.type = prevType;
        },
      ),
    );
    recalculateWorkbook();
    notifyListeners();
  }

  void _clearCellEditTracking() {
    _cellEditSheet = null;
    _cellEditCell = null;
    _cellTextBeforeEdit = null;
    _cellTextLastObserved = null;
  }

  String? _cellInputError(SmlWorksheet target, SmlCell cell, String text) {
    if (target.protection?.enabled == true && cell.locked) {
      return 'The sheet is protected.';
    }
    return SmlAnalysis.validateInput(target, cell.ref, text);
  }

  void _applyCellText(SmlCell cell, String text) {
    lastValidationError = _cellInputError(sheet, cell, text);
    if (lastValidationError != null) {
      return;
    }
    FormulaEvaluator.applyInput(workbook, sheet, cell, text);
  }

  @override
  /// semanticsLabel API.
  String get semanticsLabel {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing != null) {
      final String title = drawing.visual.title.isEmpty
          ? config.strings.pictureLabel
          : drawing.visual.title;
      return '${config.strings.sheetEditor}, $title';
    }
    return config.strings.sheetEditor;
  }

  @override
  /// semanticsValue API.
  String get semanticsValue {
    final SmlDrawing? drawing = selectedDrawing;
    if (drawing != null) {
      final OfficeVisual v = drawing.visual;
      return '${v.kind.name} ${v.width.round()}×${v.height.round()}. ${config.strings.pictureHint}';
    }
    return '${config.strings.cellLabel} $selectionAddress $formulaBarText';
  }

  @override
  /// documentProperties API.
  OfficeDocumentProperties get documentProperties => workbook.properties;

  @override
  set documentProperties(OfficeDocumentProperties value) {
    workbook.properties = value;
    notifyListeners();
  }

  @override
  /// documentStats API.
  OfficeTextStats get documentStats => OfficeTextStats.ofWorkbook(workbook);

  @override
  /// collectFindHits API.
  List<OfficeFindHit> collectFindHits(OfficeFindOptions options) =>
      OfficeFind.inWorkbook(workbook, options);

  @override
  /// applyReplace API.
  int applyReplace(OfficeFindOptions options, {OfficeFindHit? only}) {
    final int count = OfficeFind.replaceWorkbook(workbook, options, only: only);
    if (count > 0) {
      recalculateWorkbook();
      notifyListeners();
    }
    return count;
  }

  @override
  /// exportPdf API.
  Uint8List exportPdf({
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
  }) {
    return OfficePrint.workbook(
      workbook,
      settings: settings,
      font: font,
      fonts: fonts,
    );
  }

  @override
  /// revealFindHit API.
  void revealFindHit(OfficeFindHit hit) {
    final String? a1 = hit.a1;
    final SmlCellRef? target = a1 == null ? null : SmlCellRef.parse(a1);
    // A find result can move the selected cell without changing worksheets.
    // Finish the draft before either move; setActiveSheet intentionally does
    // nothing when its effective target is already the active worksheet.
    commitPendingEdits();
    final String? sheetName = hit.sheetName;
    if (sheetName != null) {
      for (int i = 0; i < workbook.sheets.length; i++) {
        if (workbook.sheets[i].name == sheetName) {
          setActiveSheet(i);
          break;
        }
      }
    }
    if (target != null) {
      selectedDrawingIndex = null;
      selection.selectCell(target);
      ensureCellVisible(target);
    }
    notifyListeners();
  }

  /// sortSelection API.
  void sortSelection({int? column, bool ascending = true}) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlRange range = selection.range;
    // The first selected row is the header; one body row cannot move.
    if (range.maxRow - range.minRow < 2) {
      return;
    }
    commitPendingEdits();
    final SmlWorksheet target = sheet;
    final before = _SheetGridSnap.capture(target);
    _SheetGridSnap? after;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          final saved = after;
          if (saved == null) {
            SmlAnalysis.sort(target, range, <SmlSortKey>[
              SmlSortKey(column: column ?? range.minCol, ascending: ascending),
            ]);
            recalculateWorkbook();
            after = _SheetGridSnap.capture(target);
          } else {
            saved.restore(target);
            recalculateWorkbook();
          }
        },
        undoFn: () {
          before.restore(target);
          recalculateWorkbook();
        },
      ),
    );
  }

  /// filterSelection API.
  void filterSelection({int relativeCol = 0, Set<String>? hide}) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlAutoFilter filter =
        sheet.autoFilter ?? SmlAutoFilter(range: selection.range);
    sheet.autoFilter = filter;
    if (hide != null) {
      filter.hiddenValues[relativeCol] = hide;
    }
    notifyListeners();
  }

  /// clearFilter API.
  void clearFilter() {
    sheet.autoFilter = null;
    notifyListeners();
  }

  /// addValidation API.
  void addValidation(SmlDataValidation rule) {
    if (!config.allowsMutation) {
      return;
    }
    sheet.validations.add(rule);
    notifyListeners();
  }

  /// addConditionalFormat API.
  void addConditionalFormat(SmlConditionalRule rule) {
    if (!config.allowsMutation) {
      return;
    }
    sheet.conditionalFormats.add(rule);
    SmlAnalysis.applyConditional(sheet);
    notifyListeners();
  }

  /// defineName API.
  void defineName(String name, {SmlRange? range, String? sheetName}) {
    if (!config.allowsMutation) {
      return;
    }
    final String sheetTitle = sheetName ?? sheet.name;
    final SmlRange chosen = range ?? selection.range;
    workbook.namedRanges.removeWhere(
      (SmlNamedRange existing) =>
          existing.name.toLowerCase() == name.toLowerCase(),
    );
    workbook.namedRanges.add(
      SmlNamedRange(name: name, sheetName: sheetTitle, range: chosen),
    );
    notifyListeners();
  }

  /// setPrintArea API.
  void setPrintArea(SmlRange? range) {
    if (!config.allowsMutation) {
      return;
    }
    sheet.printArea = range ?? selection.range;
    notifyListeners();
  }

  /// removeDuplicatesInSelection API.
  int removeDuplicatesInSelection() {
    if (!config.allowsMutation) {
      return 0;
    }
    final int removed = SmlAnalysis.removeDuplicates(sheet, selection.range);
    if (removed > 0) {
      recalculateWorkbook();
      notifyListeners();
    }
    return removed;
  }

  /// setCellComment API.
  void setCellComment(
    String text, {
    SmlCellRef? ref,
    String author = 'CrispOffice',
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlCellRef at = ref ?? activeCell;
    sheet.comments.removeWhere((SmlComment c) => c.ref.a1 == at.a1);
    if (text.isNotEmpty) {
      sheet.comments.add(SmlComment(ref: at, text: text, author: author));
    }
    notifyListeners();
  }

  /// protectSheet API.
  void protectSheet({bool enabled = true, String password = ''}) {
    if (!config.allowsMutation) {
      return;
    }
    if (!enabled) {
      final String current = sheet.protection?.password ?? '';
      if (current.isNotEmpty && current != password) {
        lastValidationError = 'Incorrect password.';
        notifyListeners();
        return;
      }
      sheet.protection = SmlSheetProtection(enabled: false, password: '');
      notifyListeners();
      return;
    }
    sheet.protection = SmlSheetProtection(enabled: true, password: password);
    notifyListeners();
  }

  /// setCellLocked API.
  void setCellLocked(bool locked, {SmlRange? range}) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlRange target = range ?? selection.range;
    for (final SmlCellRef ref in target.cells) {
      sheet.cell(ref).locked = locked;
    }
    notifyListeners();
  }

  /// fillSeries API.
  void fillSeries({SmlRange? range}) {
    if (!config.allowsMutation) {
      return;
    }
    SmlAnalysis.fillSeries(sheet, range ?? selection.range);
    recalculateWorkbook();
    notifyListeners();
  }

  /// applyValidationChoice API.
  void applyValidationChoice(String value) {
    if (!config.allowsMutation) {
      return;
    }
    _commitFormula(value);
  }

  /// toggleFilterValue API.
  void toggleFilterValue(int relativeCol, String value) {
    if (!config.allowsMutation || sheet.autoFilter == null) {
      return;
    }
    final Set<String> hidden = sheet.autoFilter!.hiddenValues.putIfAbsent(
      relativeCol,
      () => <String>{},
    );
    if (hidden.contains(value)) {
      hidden.remove(value);
    } else {
      hidden.add(value);
    }
    notifyListeners();
  }

  /// addTable API.
  void addTable({String name = 'Table1', SmlRange? range}) {
    if (!config.allowsMutation) {
      return;
    }
    sheet.tables.add(SmlTable(name: name, range: range ?? selection.range));
    notifyListeners();
  }

  /// addSparkline API.
  void addSparkline({SmlRange? source, SmlCellRef? anchor}) {
    if (!config.allowsMutation) {
      return;
    }
    sheet.sparklines.add(
      SmlSparkline(
        source: source ?? selection.range,
        anchor: anchor ?? activeCell,
      ),
    );
    notifyListeners();
  }

  /// goalSeek API.
  bool goalSeek({
    required SmlCellRef target,
    required SmlCellRef changing,
    required double goal,
  }) {
    if (!config.allowsMutation) {
      return false;
    }
    final bool ok = SmlSolver.goalSeek(
      workbook: workbook,
      sheet: sheet,
      target: target,
      changing: changing,
      goal: goal,
    );
    notifyListeners();
    return ok;
  }

  /// importCsv API.
  SmlRange importCsv(String csv, {SmlCellRef? origin}) {
    final SmlRange range = SmlPowerQuery.fromCsv(
      sheet,
      csv,
      origin: origin ?? activeCell,
    );
    recalculateWorkbook();
    notifyListeners();
    return range;
  }

  /// insertPivot API.
  void insertPivot({
    required SmlRange source,
    required int rowField,
    required int dataField,
    SmlCellRef? origin,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlPivotTable pivot = SmlPivotTable(
      source: source,
      rowField: rowField,
      dataField: dataField,
    );
    sheet.pivots.add(pivot);
    pivot.materialize(sheet, origin ?? activeCell);
    notifyListeners();
  }
}

/// Which surface the slide editor paints.
enum SlideStageKind { slide, layout, master }

/// Presentation controller: slide index, shape selection, transforms.
class SlideEditorController extends OfficeController {
  /// SlideEditorController API.
  SlideEditorController({
    PmlPresentation? presentation,
    super.config,
    this._activeSlide = 0,
  }) : presentation = presentation ?? PmlPresentation();

  /// fromBytes API.
  factory SlideEditorController.fromBytes(
    Uint8List bytes, {
    String? password,
    OfficeSurfaceConfig? config,
  }) {
    final SlideEditorController controller = SlideEditorController(
      config: config,
    );
    controller.loadBytes(bytes, password: password);
    return controller;
  }

  /// presentation API.
  PmlPresentation presentation;
  int _activeSlide;
  var stageKind = SlideStageKind.slide;

  PmlShape? _selected;

  /// Primary selected shape (last clicked). Use [selectedShapes] for the full set.
  PmlShape? get selected => _selected;

  set selected(PmlShape? value) {
    _selected = value;
    if (value == null) {
      selectedShapes.clear();
    } else if (!_containsShape(selectedShapes, value)) {
      selectedShapes
        ..clear()
        ..add(value);
    }
  }

  /// All selected shapes, including group mates treated as one unit.
  final List<PmlShape> selectedShapes = <PmlShape>[];

  /// selectedTableRow API.
  int selectedTableRow = 0;

  /// selectedTableCol API.
  int selectedTableCol = 0;
  int? _selectedAnimationIndex;
  PmlSlideShow? _show;
  String? _textBeforeEdit;
  PmlShape? _textEditShape;
  PmlTableCell? _textEditCell;

  @override
  bool get _hasPendingEdits =>
      textEditor.editing &&
      _textBeforeEdit != null &&
      textEditor.formulaBar != _textBeforeEdit;

  @override
  bool get canUndo => super.canUndo || _hasPendingEdits;

  /// textEditor API.
  late final InlineCellEditor textEditor = InlineCellEditor(
    onCommit: _commitShapeText,
    onChanged: _onShapeTextChanged,
    commitOnNewline: false,
  );

  /// activeSlideIndex API.
  int get activeSlideIndex => _activeSlide;

  /// speakerNotes API.
  String get speakerNotes => slide.notes;

  /// slide API.
  PmlSlide get slide {
    if (presentation.slides.isEmpty) {
      presentation.slides.add(PmlSlide(id: 256));
    }
    return presentation.slides[_activeSlide.clamp(
      0,
      presentation.slides.length - 1,
    )];
  }

  @override
  /// kind API.
  OpcPackageKind get kind => OpcPackageKind.slide;

  /// loadBytes API.
  void loadBytes(Uint8List bytes, {String? password}) {
    _acceptOpenedPresentation(
      SlideDeserializer().read(OfficeRepair.open(bytes, password: password)),
    );
  }

  /// loadBytesAsync API.
  Future<void> loadBytesAsync(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final PmlPresentation opened = await OfficeIsolateOpen.presentation(
      bytes,
      password: password,
      onProgress: onProgress,
    );
    _acceptOpenedPresentation(opened);
  }

  void _acceptOpenedPresentation(PmlPresentation opened) {
    presentation = opened;
    _activeSlide = 0;
    selected = null;
    selectedTableRow = 0;
    selectedTableCol = 0;
    _selectedAnimationIndex = null;
    endShow();
    _cancelTextEditSilent();
    _dirty = false;
    notifyListeners();
  }

  @override
  void commitPendingEdits() => commitTextEdit();

  @override
  void undo() {
    if (!config.enableUndo || !config.allowsMutation) {
      return;
    }
    commitTextEdit();
    super.undo();
  }

  @override
  void redo() {
    if (!config.enableUndo || !config.allowsMutation) {
      return;
    }
    commitTextEdit();
    super.redo();
  }

  @override
  /// saveBytes API.
  Uint8List saveBytes({String? password}) {
    commitPendingEdits();
    final Uint8List bytes = SlideSerializer().writeBytes(
      presentation,
      password: password,
    );
    markClean();
    return bytes;
  }

  @override
  /// saveBytesAsync API.
  Future<Uint8List> saveBytesAsync({String? password}) {
    commitPendingEdits();
    return OfficeIsolateSave.presentation(presentation, password: password);
  }

  /// setActiveSlide API.
  void setActiveSlide(int index) {
    if (textEditor.editing) {
      commitTextEdit();
    }
    _activeSlide = index.clamp(0, presentation.slides.length - 1);
    selected = null;
    _selectedAnimationIndex = null;
    notifyListeners();
  }

  /// reorderSlide API.
  void reorderSlide(int from, int to) {
    if (!config.allowsMutation) {
      return;
    }
    final List<PmlSlide> slides = presentation.slides;
    if (from < 0 ||
        to < 0 ||
        from >= slides.length ||
        to >= slides.length ||
        from == to) {
      return;
    }
    final int active = _activeSlide;
    final PmlSlideReorder move = PmlSections.planReorder(
      presentation,
      from,
      to,
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          move.apply();
          _activeSlide = _indexAfterReorder(active, from, to);
        },
        undoFn: () {
          move.undo();
          _activeSlide = active.clamp(0, slides.length - 1);
        },
      ),
    );
    selected = null;
    _selectedAnimationIndex = null;
    notifyListeners();
  }

  /// Copies [index] so it can be pasted after any other thumbnail.
  void copySlide(int index) {
    if (index < 0 || index >= presentation.slides.length) {
      return;
    }
    final PmlSlide slide = presentation.slides[index];
    OfficeClipboard.instance.writeLocal(
      OfficeClipboardPayload(
        kind: OfficeClipboardKind.slide,
        plain: slide.notes.trim().isEmpty ? 'Slide ${index + 1}' : slide.notes,
        slide: slide.copy(),
      ),
    );
  }

  /// True when the in-app clipboard holds a whole slide.
  bool get canPasteSlide {
    final PmlSlide? slide = OfficeClipboard.instance.local?.slide;
    return config.allowsMutation && slide != null;
  }

  /// Pastes the copied slide after [afterIndex] (or after the active slide).
  void pasteSlide({int? afterIndex}) {
    if (!canPasteSlide) {
      return;
    }
    final PmlSlide? source = OfficeClipboard.instance.local?.slide;
    if (source == null) {
      return;
    }
    insertClonedSlide(source, afterIndex: afterIndex ?? activeSlideIndex);
  }

  /// Duplicates [index] immediately after itself.
  void duplicateSlide(int index) {
    if (!config.allowsMutation) {
      return;
    }
    if (index < 0 || index >= presentation.slides.length) {
      return;
    }
    insertClonedSlide(presentation.slides[index], afterIndex: index);
  }

  /// insertClonedSlide API.
  void insertClonedSlide(PmlSlide source, {required int afterIndex}) {
    if (!config.allowsMutation) {
      return;
    }
    final List<PmlSlide> slides = presentation.slides;
    final int dest = (afterIndex + 1).clamp(0, slides.length);
    final int previousActive = _activeSlide;
    final PmlSlide clone = source.copy(id: _allocateSlideId());
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (!slides.contains(clone)) {
            slides.insert(dest.clamp(0, slides.length), clone);
          }
          _activeSlide = dest.clamp(0, slides.length - 1);
        },
        undoFn: () {
          slides.remove(clone);
          _activeSlide = previousActive.clamp(0, slides.length - 1);
        },
      ),
    );
    selected = null;
    _selectedAnimationIndex = null;
    notifyListeners();
  }

  int _allocateSlideId() {
    var maxId = 255;
    for (final PmlSlide slide in presentation.slides) {
      if (slide.id > maxId) {
        maxId = slide.id;
      }
    }
    return maxId + 1;
  }

  /// setSlideHidden API.
  void setSlideHidden(int index, bool hidden) {
    if (!config.allowsMutation) {
      return;
    }
    if (index < 0 || index >= presentation.slides.length) {
      return;
    }
    final PmlSlide target = presentation.slides[index];
    if (target.hidden == hidden) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => target.hidden = hidden,
        undoFn: () => target.hidden = !hidden,
      ),
    );
    notifyListeners();
  }

  /// toggleSlideHidden API.
  void toggleSlideHidden(int index) {
    if (index < 0 || index >= presentation.slides.length) {
      return;
    }
    setSlideHidden(index, !presentation.slides[index].hidden);
  }

  static int _indexAfterReorder(int active, int from, int to) {
    if (active == from) {
      return to;
    }
    if (from < to && active > from && active <= to) {
      return active - 1;
    }
    if (from > to && active >= to && active < from) {
      return active + 1;
    }
    return active;
  }

  /// isPlayingMotion API.
  bool get isPlayingMotion => _show?.presenting == true;

  /// isPreviewing API.
  bool get isPreviewing =>
      _show?.presenting == true && (_show?.isPreview ?? false);

  /// isPresenting API.
  bool get isPresenting =>
      _show?.presenting == true && !(_show?.isPreview ?? false);

  /// slideShow API.
  PmlSlideShow? get slideShow => _show;

  PmlShape? _restoreSelected;
  int? _restoreAnimationIndex;

  /// motionFrame API.
  final ValueNotifier<int> motionFrame = ValueNotifier<int>(0);

  /// showSamples API.
  Map<int, PmlAnimSample> get showSamples {
    final PmlSlideShow? show = _show;
    if (show == null || !show.presenting) {
      return const <int, PmlAnimSample>{};
    }
    return <int, PmlAnimSample>{
      for (final PmlShape shape in show.currentSlide.shapes)
        shape.id: show.sample(shape.id),
    };
  }

  /// selectedAnimationIndex API.
  int? get selectedAnimationIndex {
    final int? index = _selectedAnimationIndex;
    if (index == null || index < 0 || index >= slide.animations.length) {
      return null;
    }
    return index;
  }

  /// selectedAnimation API.
  PmlShapeAnimation? get selectedAnimation {
    final int? index = selectedAnimationIndex;
    if (index == null) {
      return null;
    }
    return slide.animations[index];
  }

  /// startShow API.
  void startShow({int? from, bool withTransition = false}) {
    _beginShow(from: from, withTransition: withTransition);
  }

  /// previewTransition API.
  void previewTransition() {
    if (slide.transition.isNone) {
      return;
    }
    _beginShow(
      from: _activeSlide,
      withTransition: true,
      previewOnly: true,
      endAfterTransition: true,
    );
  }

  /// previewAnimations API.
  void previewAnimations() {
    if (slide.animations.isEmpty) {
      return;
    }
    _beginShow(
      from: _activeSlide,
      withTransition: false,
      previewOnly: true,
      autoPlayClicks: true,
    );
  }

  /// previewAnimationAt API.
  void previewAnimationAt(int index) {
    if (index < 0 || index >= slide.animations.length) {
      return;
    }
    _beginShow(
      from: _activeSlide,
      withTransition: false,
      previewOnly: true,
      autoPlayClicks: true,
      onlyAnimationIndex: index,
    );
  }

  void _beginShow({
    int? from,
    bool withTransition = false,
    bool previewOnly = false,
    bool endAfterTransition = false,
    bool autoPlayClicks = false,
    int? onlyAnimationIndex,
  }) {
    if (textEditor.editing) {
      commitTextEdit();
    }
    _show?.stop();
    _show = null;
    if (previewOnly) {
      _restoreSelected = selected;
      _restoreAnimationIndex = _selectedAnimationIndex;
    } else {
      _restoreSelected = null;
      _restoreAnimationIndex = null;
    }
    final int last = presentation.slides.isEmpty
        ? 0
        : presentation.slides.length - 1;
    final int index = (from ?? _activeSlide).clamp(0, last);
    _show = PmlSlideShow(presentation)
      ..start(
        from: index,
        withTransition: withTransition,
        previewOnly: previewOnly,
        endAfterTransition: endAfterTransition,
        autoPlayClicks: autoPlayClicks,
        onlyAnimationIndex: onlyAnimationIndex,
      );
    _activeSlide = _show!.slideIndex;
    if (!previewOnly) {
      selected = null;
      startPresenter();
    }
    notifyListeners();
  }

  /// endShow API.
  void endShow() {
    stopPresenter();
    if (_show == null) {
      return;
    }
    if (_show!.presenting || _show!.finished) {
      _activeSlide = _show!.slideIndex;
    }
    _show!.stop();
    _show = null;
    if (_restoreSelected != null) {
      selected = _restoreSelected;
      _selectedAnimationIndex = _restoreAnimationIndex;
    }
    _restoreSelected = null;
    _restoreAnimationIndex = null;
    notifyListeners();
  }

  /// showNext API.
  void showNext() {
    final PmlSlideShow? show = _show;
    if (show == null) {
      return;
    }
    show.next();
    _activeSlide = show.slideIndex;
    if (show.finished) {
      endShow();
      return;
    }
    notifyListeners();
  }

  /// showPrevious API.
  void showPrevious() {
    final PmlSlideShow? show = _show;
    if (show == null) {
      return;
    }
    show.previous();
    _activeSlide = show.slideIndex;
    notifyListeners();
  }

  /// tickShow API.
  void tickShow(int milliseconds) {
    final PmlSlideShow? show = _show;
    if (show == null || !show.presenting) {
      return;
    }
    final int slideBefore = show.slideIndex;
    show.elapse(milliseconds);
    _activeSlide = show.slideIndex;
    if (show.finished) {
      endShow();
      return;
    }
    if (show.slideIndex != slideBefore) {
      notifyListeners();
      return;
    }
    motionFrame.value++;
  }

  /// setSlideTransition API.
  void setSlideTransition(
    PmlSlideTransition transition, {
    bool applyToAll = false,
    bool preview = true,
  }) {
    if (applyToAll) {
      for (final PmlSlide s in presentation.slides) {
        s.transition = transition;
      }
    } else {
      slide.transition = transition;
    }
    if (preview && !transition.isNone) {
      previewTransition();
      return;
    }
    notifyListeners();
  }

  /// addShapeAnimation API.
  void addShapeAnimation(
    PmlAnimPreset preset, {
    PmlAnimTrigger trigger = PmlAnimTrigger.onClick,
    PmlTransitionDir direction = PmlTransitionDir.left,
    int durationMs = 500,
  }) {
    final PmlShape? shape = selected;
    if (shape == null) {
      return;
    }
    slide.animations.add(
      PmlShapeAnimation(
        shapeId: shape.id,
        preset: preset,
        trigger: trigger,
        direction: direction,
        durationMs: durationMs,
        order: slide.animations.length,
      ),
    );
    _selectedAnimationIndex = slide.animations.length - 1;
    previewAnimationAt(_selectedAnimationIndex!);
  }

  /// selectAnimation API.
  void selectAnimation(int? index) {
    if (index == null || index < 0 || index >= slide.animations.length) {
      _selectedAnimationIndex = null;
      notifyListeners();
      return;
    }
    _selectedAnimationIndex = index;
    final int shapeId = slide.animations[index].shapeId;
    for (final PmlShape shape in slide.shapes) {
      if (shape.id == shapeId) {
        selected = shape;
        break;
      }
    }
    notifyListeners();
    previewAnimationAt(index);
  }

  /// updateShapeAnimation API.
  void updateShapeAnimation(
    int index, {
    PmlAnimTrigger? trigger,
    PmlTransitionDir? direction,
    int? durationMs,
    int? delayMs,
  }) {
    if (index < 0 || index >= slide.animations.length) {
      return;
    }
    final PmlShapeAnimation anim = slide.animations[index];
    if (trigger != null) {
      anim.trigger = trigger;
    }
    if (direction != null) {
      anim.direction = direction;
    }
    if (durationMs != null) {
      anim.durationMs = durationMs;
    }
    if (delayMs != null) {
      anim.delayMs = delayMs;
    }
    notifyListeners();
  }

  /// removeShapeAnimation API.
  void removeShapeAnimation(int index) {
    if (index < 0 || index >= slide.animations.length) {
      return;
    }
    slide.animations.removeAt(index);
    for (int i = 0; i < slide.animations.length; i++) {
      slide.animations[i].order = i;
    }
    if (_selectedAnimationIndex != null) {
      if (_selectedAnimationIndex == index) {
        _selectedAnimationIndex = slide.animations.isEmpty
            ? null
            : index.clamp(0, slide.animations.length - 1);
      } else if (_selectedAnimationIndex! > index) {
        _selectedAnimationIndex = _selectedAnimationIndex! - 1;
      }
    }
    notifyListeners();
  }

  /// moveShapeAnimation API.
  void moveShapeAnimation(int index, int delta) {
    final int next = (index + delta).clamp(0, slide.animations.length - 1);
    if (next == index) {
      return;
    }
    final PmlShapeAnimation item = slide.animations.removeAt(index);
    slide.animations.insert(next, item);
    for (int i = 0; i < slide.animations.length; i++) {
      slide.animations[i].order = i;
    }
    notifyListeners();
  }

  /// setAnimationTrigger API.
  void setAnimationTrigger(int index, PmlAnimTrigger trigger) {
    if (index < 0 || index >= slide.animations.length) {
      return;
    }
    slide.animations[index].trigger = trigger;
    notifyListeners();
  }

  static bool _containsShape(List<PmlShape> list, PmlShape shape) {
    for (final PmlShape item in list) {
      if (identical(item, shape)) {
        return true;
      }
    }
    return false;
  }

  void _addUniqueShape(List<PmlShape> list, PmlShape shape) {
    if (!_containsShape(list, shape)) {
      list.add(shape);
    }
  }

  List<PmlShape> _matesOf(PmlShape shape) {
    return PmlArrange.mates(slide.shapes, shape);
  }

  List<PmlShape> _selectionWithMates({PmlShape? extra}) {
    final List<PmlShape> out = <PmlShape>[];
    final List<PmlShape> seeds = selectedShapes.isNotEmpty
        ? selectedShapes
        : (selected == null ? <PmlShape>[] : <PmlShape>[selected!]);
    for (final PmlShape seed in seeds) {
      for (final PmlShape mate in _matesOf(seed)) {
        _addUniqueShape(out, mate);
      }
    }
    if (extra != null) {
      for (final PmlShape mate in _matesOf(extra)) {
        _addUniqueShape(out, mate);
      }
    }
    return out;
  }

  void _adoptSelection(List<PmlShape> shapes, {PmlShape? primary}) {
    selectedShapes
      ..clear()
      ..addAll(shapes);
    _selected =
        primary ?? (selectedShapes.isEmpty ? null : selectedShapes.last);
  }

  /// selectShape API.
  void selectShape(PmlShape? shape, {bool additive = false}) {
    if (!config.allowsSelection) {
      selected = null;
      notifyListeners();
      return;
    }
    if (textEditor.editing && !identical(selected, shape)) {
      commitTextEdit();
    }
    if (!identical(selected, shape)) {
      selectedTableRow = 0;
      selectedTableCol = 0;
    }
    if (shape == null) {
      selected = null;
      notifyListeners();
      return;
    }
    final List<PmlShape> mates = _matesOf(shape);
    if (additive) {
      final bool allIn = mates.every(
        (PmlShape mate) => _containsShape(selectedShapes, mate),
      );
      if (allIn) {
        selectedShapes.removeWhere(
          (PmlShape item) => _containsShape(mates, item),
        );
        _selected = selectedShapes.isEmpty ? null : selectedShapes.last;
      } else {
        for (final PmlShape mate in mates) {
          _addUniqueShape(selectedShapes, mate);
        }
        _selected = shape;
      }
    } else if (_containsShape(selectedShapes, shape) &&
        selectedShapes.length > 1) {
      _selected = shape;
    } else {
      _adoptSelection(mates, primary: shape);
    }
    notifyListeners();
  }

  /// selectTableCell API.
  void selectTableCell(PmlShape shape, int row, int col) {
    if (!config.allowsSelection) {
      return;
    }
    if (textEditor.editing &&
        (!identical(selected, shape) ||
            selectedTableRow != row ||
            selectedTableCol != col)) {
      commitTextEdit();
    }
    selectShape(shape);
    final PmlTable? table = shape.table;
    if (table != null && table.rowCount > 0 && table.colCount > 0) {
      selectedTableRow = row.clamp(0, table.rowCount - 1);
      selectedTableCol = col.clamp(0, table.colCount - 1);
    }
    notifyListeners();
  }

  /// selectedTable API.
  PmlTable? get selectedTable => selected?.table;

  int _nextSlideShapeId() {
    return slide.shapes.fold<int>(
          2,
          (int max, PmlShape s) => s.id > max ? s.id : max,
        ) +
        1;
  }

  /// insertTable API.
  void insertTable({int rows = 3, int cols = 3, bool arabic = false}) {
    if (!config.allowsMutation) {
      return;
    }
    final PmlShape shape = PmlShape(
      id: _nextSlideShapeId(),
      name: 'Table',
      fillColor: '',
      table: PmlTable.grid(
        rows: rows,
        cols: cols,
        header: true,
        arabic: arabic,
      ),
      transform: const PmlTransform(
        x: 600000,
        y: 1100000,
        cx: 7900000,
        cy: 2800000,
      ),
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          slide.shapes.add(shape);
          selected = shape;
          selectedTableRow = 0;
          selectedTableCol = 0;
        },
        undoFn: () {
          slide.shapes.remove(shape);
          if (identical(selected, shape)) {
            selected = null;
          }
        },
      ),
    );
    notifyListeners();
  }

  /// insertSelectedTableRow API.
  void insertSelectedTableRow({required bool after}) {
    final PmlTable? table = selectedTable;
    if (table == null || !config.allowsMutation) {
      return;
    }
    final int index = (after ? selectedTableRow + 1 : selectedTableRow).clamp(
      0,
      table.rowCount,
    );
    final int cols = table.colCount < 1 ? 1 : table.colCount;
    final List<PmlTableCell> row = <PmlTableCell>[
      for (int c = 0; c < cols; c++)
        PmlTableCell(fillColor: 'FFFFFF', textColor: '1A1A1A'),
    ];
    final int prevRow = selectedTableRow;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          table.rows.insert(index, row);
          selectedTableRow = index.clamp(0, table.rowCount - 1);
        },
        undoFn: () {
          table.rows.remove(row);
          selectedTableRow = prevRow.clamp(0, table.rowCount - 1);
        },
      ),
    );
    notifyListeners();
  }

  /// insertSelectedTableColumn API.
  void insertSelectedTableColumn({required bool after}) {
    final PmlTable? table = selectedTable;
    if (table == null || !config.allowsMutation) {
      return;
    }
    final int index = (after ? selectedTableCol + 1 : selectedTableCol).clamp(
      0,
      table.colCount,
    );
    final int prevCol = selectedTableCol;
    final List<PmlTableCell> added = <PmlTableCell>[];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          added.clear();
          for (final List<PmlTableCell> row in table.rows) {
            final PmlTableCell cell = PmlTableCell(
              fillColor: 'FFFFFF',
              textColor: '1A1A1A',
            );
            final int at = index.clamp(0, row.length);
            row.insert(at, cell);
            added.add(cell);
          }
          selectedTableCol = index;
        },
        undoFn: () {
          for (int i = 0; i < table.rows.length && i < added.length; i++) {
            table.rows[i].remove(added[i]);
          }
          selectedTableCol = prevCol.clamp(0, table.colCount - 1);
        },
      ),
    );
    notifyListeners();
  }

  /// deleteSelectedTableRow API.
  void deleteSelectedTableRow() {
    final PmlTable? table = selectedTable;
    if (table == null || table.rowCount <= 1 || !config.allowsMutation) {
      return;
    }
    final int index = selectedTableRow.clamp(0, table.rowCount - 1);
    final List<PmlTableCell> row = table.rows[index];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          table.rows.remove(row);
          selectedTableRow = index.clamp(0, table.rowCount - 1);
        },
        undoFn: () {
          table.rows.insert(index.clamp(0, table.rows.length), row);
          selectedTableRow = index;
        },
      ),
    );
    notifyListeners();
  }

  /// deleteSelectedTableColumn API.
  void deleteSelectedTableColumn() {
    final PmlTable? table = selectedTable;
    if (table == null || table.colCount <= 1 || !config.allowsMutation) {
      return;
    }
    final int index = selectedTableCol.clamp(0, table.colCount - 1);
    final List<PmlTableCell?> removed = <PmlTableCell?>[
      for (final List<PmlTableCell> row in table.rows)
        index < row.length ? row[index] : null,
    ];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (final List<PmlTableCell> row in table.rows) {
            if (index < row.length) {
              row.removeAt(index);
            }
          }
          selectedTableCol = index.clamp(0, table.colCount - 1);
        },
        undoFn: () {
          for (int i = 0; i < table.rows.length; i++) {
            final PmlTableCell? cell = i < removed.length ? removed[i] : null;
            if (cell != null) {
              table.rows[i].insert(index.clamp(0, table.rows[i].length), cell);
            }
          }
          selectedTableCol = index;
        },
      ),
    );
    notifyListeners();
  }

  /// moveSelectedTableCell API.
  void moveSelectedTableCell({required bool forward}) {
    final PmlTable? table = selectedTable;
    if (table == null || table.rowCount == 0 || table.colCount == 0) {
      return;
    }
    if (textEditor.editing) {
      commitTextEdit();
    }
    var row = selectedTableRow;
    var col = selectedTableCol;
    if (forward) {
      col++;
      if (col >= table.colCount) {
        col = 0;
        row++;
        if (row >= table.rowCount) {
          insertSelectedTableRow(after: true);
          row = table.rowCount - 1;
        }
      }
    } else {
      col--;
      if (col < 0) {
        col = table.colCount - 1;
        row--;
        if (row < 0) {
          row = 0;
          col = 0;
        }
      }
    }
    selectedTableRow = row.clamp(0, table.rowCount - 1);
    selectedTableCol = col.clamp(0, table.colCount - 1);
    beginTextEdit();
  }

  /// editingText API.
  bool get editingText => textEditor.editing;

  /// beginTextEdit API.
  void beginTextEdit({String? initial, bool replace = false, int? caret}) {
    final PmlShape? shape = selected;
    if (shape == null || shape.visual != null || !config.allowsMutation) {
      return;
    }
    commitTextEdit();
    _textEditShape = shape;
    if (shape.table != null) {
      final PmlTableCell cell = shape.table!.cellAt(
        selectedTableRow,
        selectedTableCol,
      );
      _textEditCell = cell;
      _textBeforeEdit = cell.text;
      final String seed = initial ?? (replace ? '' : cell.text);
      textEditor.begin(seed, caret: caret, multiline: true);
      notifyListeners();
      return;
    }
    _textBeforeEdit = shape.text;
    final String seed = initial ?? (replace ? '' : shape.text);
    textEditor.begin(seed, caret: caret, multiline: true);
    notifyListeners();
  }

  @override
  /// selectAll API.
  void selectAll() {
    if (!config.allowsSelection) {
      return;
    }
    if (textEditor.editing) {
      textEditor.selectAll();
      notifyListeners();
      return;
    }
    if (slide.shapes.isEmpty) {
      selected = null;
    } else {
      _adoptSelection(List<PmlShape>.from(slide.shapes));
    }
    notifyListeners();
  }

  @override
  /// canCopy API.
  bool get canCopy => selected != null || textEditor.editing;

  @override
  /// copyToClipboard API.
  Future<void> copyToClipboard() async {
    final OfficeClipboardPayload payload = _captureSlideClipboard();
    if (payload.isEmpty) {
      return;
    }
    await OfficeClipboard.instance.write(payload);
  }

  @override
  /// cutToClipboard API.
  Future<void> cutToClipboard() async {
    if (!canCut) {
      return;
    }
    await copyToClipboard();
    if (textEditor.editing) {
      _replaceSlideEditorSelection('');
      return;
    }
    deleteSelectedShape();
  }

  @override
  /// pasteFromClipboard API.
  Future<void> pasteFromClipboard({
    OfficePasteMode mode = OfficePasteMode.keepSource,
  }) async {
    if (!canPaste) {
      return;
    }
    final OfficeClipboardPayload payload = await OfficeClipboard.instance
        .read();
    if (payload.isEmpty) {
      return;
    }
    if (payload.slide != null && mode != OfficePasteMode.keepTextOnly) {
      pasteSlide(afterIndex: activeSlideIndex);
      return;
    }
    if (textEditor.editing) {
      _replaceSlideEditorSelection(payload.plain);
      return;
    }
    if (mode != OfficePasteMode.keepTextOnly && payload.shape != null) {
      _pasteSlideShape(payload.shape!);
      return;
    }
    if (mode != OfficePasteMode.keepTextOnly && payload.visual != null) {
      _pasteSlideVisual(payload.visual!);
      return;
    }
    if (selected != null && selected!.visual == null) {
      final PmlShape shape = selected!;
      if (mode == OfficePasteMode.keepTextOnly ||
          !payload.plain.contains('\n')) {
        updateSelected(text: payload.plain);
        return;
      }
      shape.text = payload.plain;
      notifyListeners();
      return;
    }
    if (payload.plain.isEmpty) {
      return;
    }
    _pasteSlideTextBox(payload.plain);
  }

  OfficeClipboardPayload _captureSlideClipboard() {
    if (textEditor.editing) {
      final String text = textEditor.hasSelection
          ? textEditor.formulaBar.substring(
              textEditor.selectionStart,
              textEditor.selectionEnd,
            )
          : textEditor.formulaBar;
      return OfficeClipboardPayload.fromPlain(text);
    }
    final PmlShape? shape = selected;
    if (shape == null) {
      return OfficeClipboardPayload.empty();
    }
    return OfficeClipboardPayload(
      kind: OfficeClipboardKind.shape,
      plain: shape.text,
      shape: cloneClipboardShape(shape, nudgeEmu: 0),
      visual: shape.visual?.copy(),
    );
  }

  void _replaceSlideEditorSelection(String insert) {
    textEditor.replaceRange(
      textEditor.selectionStart,
      textEditor.selectionEnd,
      insert,
    );
  }

  void _pasteSlideShape(PmlShape source) {
    final int nextId =
        slide.shapes.fold<int>(
          2,
          (int max, PmlShape s) => s.id > max ? s.id : max,
        ) +
        1;
    final PmlShape clone = cloneClipboardShape(source, id: nextId);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          slide.shapes.add(clone);
          selected = clone;
        },
        undoFn: () {
          slide.shapes.remove(clone);
          if (identical(selected, clone)) {
            selected = source;
          }
        },
      ),
    );
    notifyListeners();
  }

  void _pasteSlideVisual(OfficeVisual visual) {
    final int nextId =
        slide.shapes.fold<int>(
          2,
          (int max, PmlShape s) => s.id > max ? s.id : max,
        ) +
        1;
    final PmlShape shape = PmlShape(
      id: nextId,
      name: visual.title,
      transform: const PmlTransform(
        x: 1270000,
        y: 762000,
        cx: 4572000,
        cy: 2286000,
      ),
      visual: visual.copy(),
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          slide.shapes.add(shape);
          selected = shape;
        },
        undoFn: () {
          slide.shapes.remove(shape);
          if (identical(selected, shape)) {
            selected = null;
          }
        },
      ),
    );
    notifyListeners();
  }

  void _pasteSlideTextBox(String text) {
    final int nextId =
        slide.shapes.fold<int>(
          2,
          (int max, PmlShape s) => s.id > max ? s.id : max,
        ) +
        1;
    final PmlShape shape = PmlShape(
      id: nextId,
      name: 'Text',
      transform: const PmlTransform(
        x: 1270000,
        y: 1270000,
        cx: 4572000,
        cy: 1270000,
      ),
      text: text,
      fillColor: '4472C4',
    );
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          slide.shapes.add(shape);
          selected = shape;
        },
        undoFn: () {
          slide.shapes.remove(shape);
          if (identical(selected, shape)) {
            selected = null;
          }
        },
      ),
    );
    notifyListeners();
  }

  /// commitTextEdit API.
  void commitTextEdit() {
    if (!textEditor.editing) {
      return;
    }
    textEditor.end();
  }

  /// cancelTextEdit API.
  void cancelTextEdit() {
    if (!textEditor.editing) {
      return;
    }
    final PmlShape? shape = _textEditShape;
    final PmlTableCell? cell = _textEditCell;
    final String? before = _textBeforeEdit;
    if (shape != null && before != null) {
      if (_hasPendingEdits || (cell?.text ?? shape.text) != before) {
        _contentRevision++;
      }
      if (cell != null) {
        cell.text = before;
      } else {
        shape.text = before;
      }
    }
    _cancelTextEditSilent();
    notifyListeners();
  }

  /// placeTextCaret API.
  void placeTextCaret(int index, {bool extend = false}) {
    if (!textEditor.editing) {
      return;
    }
    textEditor.setCaret(index, extend: extend);
    notifyListeners();
  }

  /// selectTextWordAt API.
  void selectTextWordAt(int index) {
    if (!textEditor.editing) {
      return;
    }
    textEditor.selectWord(index);
    notifyListeners();
  }

  /// selectTextParagraphAt API.
  void selectTextParagraphAt(int index) {
    if (!textEditor.editing) {
      return;
    }
    textEditor.selectParagraph(index);
    notifyListeners();
  }

  /// moveTextCaret API.
  void moveTextCaret(int delta, {bool extend = false}) {
    if (!textEditor.editing) {
      return;
    }
    textEditor.moveCaret(delta, extend: extend);
  }

  /// deleteSelectedShape API.
  void deleteSelectedShape() {
    if (textEditor.editing) {
      return;
    }
    if (!config.allowsMutation) {
      return;
    }
    final List<PmlShape> targets = _selectionWithMates();
    if (targets.isEmpty) {
      return;
    }
    final List<PmlShape> shapes = slide.shapes;
    final List<({int index, PmlShape shape})> removed =
        <({int index, PmlShape shape})>[
          for (final PmlShape shape in targets)
            if (shapes.contains(shape))
              (index: shapes.indexOf(shape), shape: shape),
        ]..sort(
          (({int index, PmlShape shape}) a, ({int index, PmlShape shape}) b) =>
              a.index.compareTo(b.index),
        );
    if (removed.isEmpty) {
      return;
    }
    final List<PmlShapeAnimation> anims = <PmlShapeAnimation>[
      for (final PmlShapeAnimation animation in slide.animations)
        if (targets.any((PmlShape s) => s.id == animation.shapeId)) animation,
    ];
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (int i = removed.length - 1; i >= 0; i--) {
            shapes.remove(removed[i].shape);
          }
          slide.animations.removeWhere(
            (PmlShapeAnimation a) =>
                targets.any((PmlShape s) => s.id == a.shapeId),
          );
          selected = null;
          _selectedAnimationIndex = null;
        },
        undoFn: () {
          for (final ({int index, PmlShape shape}) item in removed) {
            if (!shapes.contains(item.shape)) {
              shapes.insert(item.index.clamp(0, shapes.length), item.shape);
            }
          }
          for (final PmlShapeAnimation animation in anims) {
            if (!slide.animations.contains(animation)) {
              slide.animations.add(animation);
            }
          }
          _adoptSelection(targets);
        },
      ),
    );
    notifyListeners();
  }

  void _onShapeTextChanged() {
    final PmlShape? shape = _textEditShape;
    if (shape != null && textEditor.editing) {
      final PmlTableCell? cell = _textEditCell;
      final String text = textEditor.formulaBar;
      if ((cell?.text ?? shape.text) != text) {
        if (cell != null) {
          cell.text = text;
        } else {
          shape.text = text;
        }
        _contentRevision++;
      }
    }
    notifyListeners();
  }

  void _commitShapeText(String text) {
    final PmlShape? shape = _textEditShape;
    final PmlTableCell? cell = _textEditCell;
    final String prev = _textBeforeEdit ?? text;
    _clearShapeTextTracking();
    textEditor.editing = false;
    if (shape == null) {
      return;
    }
    if (cell != null) {
      cell.text = text;
      if (prev == text) {
        notifyListeners();
        return;
      }
      commands.commit(
        _CallbackCommand(
          executeFn: () => cell.text = text,
          undoFn: () => cell.text = prev,
        ),
      );
      notifyListeners();
      return;
    }
    shape.text = text;
    if (prev == text) {
      notifyListeners();
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => shape.text = text,
        undoFn: () => shape.text = prev,
      ),
    );
    notifyListeners();
  }

  void _cancelTextEditSilent() {
    if (textEditor.editing) {
      textEditor.editing = false;
      textEditor.bridge.detach();
    }
    _clearShapeTextTracking();
  }

  void _clearShapeTextTracking() {
    _textBeforeEdit = null;
    _textEditShape = null;
    _textEditCell = null;
  }

  /// nudgeSelected API.
  void nudgeSelected(int dxEmu, int dyEmu) {
    if (!config.allowsMutation) {
      return;
    }
    final List<PmlShape> targets = _selectionWithMates();
    if (targets.isEmpty) {
      return;
    }
    final Map<PmlShape, PmlTransform> next = <PmlShape, PmlTransform>{
      for (final PmlShape shape in targets)
        shape: shape.transform.copyWith(
          x: shape.transform.x + dxEmu,
          y: shape.transform.y + dyEmu,
          cx: shape.transform.cx,
          cy: shape.transform.cy,
          rot: shape.transform.rot,
          flipH: shape.transform.flipH,
          flipV: shape.transform.flipV,
        ),
    };
    applyTransforms(next);
  }

  /// updateSelected API.
  void updateSelected({String? text, String? fillColor, double? fontSizePt}) {
    final PmlShape? shape = selected;
    if (shape == null || !config.allowsMutation) {
      return;
    }
    final String prevText = shape.text;
    final String prevFill = shape.fillColor;
    final double prevSize = shape.fontSizePt;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          if (text != null) {
            shape.text = text;
          }
          if (fillColor != null) {
            shape.fillColor = fillColor;
          }
          if (fontSizePt != null) {
            shape.fontSizePt = fontSizePt;
          }
        },
        undoFn: () {
          shape.text = prevText;
          shape.fillColor = prevFill;
          shape.fontSizePt = prevSize;
        },
      ),
    );
    notifyListeners();
  }

  /// setSelectedTextDirection API.
  void setSelectedTextDirection({required bool rtl}) {
    final PmlShape? shape = selected;
    if (shape == null || shape.visual != null || !config.allowsMutation) {
      return;
    }
    final bool? prevRtl = shape.rightToLeft;
    final PmlTextAlign prevAlign = shape.textAlign;
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          shape.rightToLeft = rtl;
          shape.textAlign = rtl ? PmlTextAlign.right : PmlTextAlign.left;
        },
        undoFn: () {
          shape.rightToLeft = prevRtl;
          shape.textAlign = prevAlign;
        },
      ),
    );
    notifyListeners();
  }

  /// setSelectedTextAlign API.
  void setSelectedTextAlign(PmlTextAlign align) {
    final PmlShape? shape = selected;
    if (shape == null || shape.visual != null || !config.allowsMutation) {
      return;
    }
    final PmlTextAlign prev = shape.textAlign;
    commands.commit(
      _CallbackCommand(
        executeFn: () => shape.textAlign = align,
        undoFn: () => shape.textAlign = prev,
      ),
    );
    notifyListeners();
  }

  /// mutateSelectedShapeVisual API.
  void mutateSelectedShapeVisual(void Function(OfficeVisual visual) edit) {
    final OfficeVisual? visual = selected?.visual;
    if (visual == null || !config.allowsMutation) {
      return;
    }
    final OfficeVisual before = visual.copy();
    edit(visual);
    final OfficeVisual after = visual.copy();
    commands.commit(
      _CallbackCommand(
        executeFn: () => visual.restoreFrom(after),
        undoFn: () => visual.restoreFrom(before),
      ),
    );
    notifyListeners();
  }

  /// reorderSelected API.
  void reorderSelected({required bool forward}) {
    final PmlShape? shape = selected;
    if (shape == null || !config.allowsMutation) {
      return;
    }
    final List<PmlShape> shapes = slide.shapes;
    final int index = shapes.indexOf(shape);
    if (index < 0) {
      return;
    }
    final int next = forward ? index + 1 : index - 1;
    if (next < 0 || next >= shapes.length) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          shapes.removeAt(index);
          shapes.insert(next, shape);
        },
        undoFn: () {
          final int now = shapes.indexOf(shape);
          if (now >= 0) {
            shapes.removeAt(now);
            shapes.insert(index, shape);
          }
        },
      ),
    );
    notifyListeners();
  }

  /// applyTransform API.
  void applyTransform(PmlShape shape, PmlTransform next) {
    if (!config.allowsMutation) {
      return;
    }
    final int dx = next.x - shape.transform.x;
    final int dy = next.y - shape.transform.y;
    final List<PmlShape> mates = _containsShape(selectedShapes, shape)
        ? _selectionWithMates(extra: shape)
        : _matesOf(shape);
    final Map<PmlShape, PmlTransform> nextByShape = <PmlShape, PmlTransform>{
      for (final PmlShape mate in mates)
        mate: identical(mate, shape)
            ? next
            : mate.transform.copyWith(
                x: mate.transform.x + dx,
                y: mate.transform.y + dy,
                cx: mate.transform.cx,
                cy: mate.transform.cy,
                rot: mate.transform.rot,
                flipH: mate.transform.flipH,
                flipV: mate.transform.flipV,
              ),
    };
    applyTransforms(nextByShape);
  }

  /// Commits a batch of shape transforms as one undo step.
  void applyTransforms(Map<PmlShape, PmlTransform> nextByShape) {
    if (!config.allowsMutation || nextByShape.isEmpty) {
      return;
    }
    final Map<PmlShape, PmlTransform> prev = <PmlShape, PmlTransform>{
      for (final MapEntry<PmlShape, PmlTransform> entry in nextByShape.entries)
        entry.key: entry.key.transform,
    };
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          nextByShape.forEach((PmlShape shape, PmlTransform t) {
            shape.transform = t;
          });
        },
        undoFn: () {
          prev.forEach((PmlShape shape, PmlTransform t) {
            shape.transform = t;
          });
        },
      ),
    );
    notifyListeners();
  }

  /// groupShapes API.
  int? groupShapes({List<PmlShape>? shapes}) {
    if (!config.allowsMutation) {
      return null;
    }
    final List<PmlShape> candidates;
    if (shapes != null) {
      candidates = shapes;
    } else if (selectedShapes.length >= 2) {
      candidates = selectedShapes;
    } else if (selectedShapes.isEmpty) {
      candidates = slide.shapes;
    } else {
      return null;
    }
    final List<PmlShape> items = _arrangementMembers(candidates);
    if (items.length < 2) {
      return null;
    }
    final Map<PmlShape, PmlShape> planned = _groupPlan();
    final int id = PmlArrange.group([
      for (final shape in items) planned[shape]!,
    ], allShapes: planned.values.toList());
    _applyGroupMembership({for (final shape in items) shape: id});
    _adoptSelection(
      items,
      primary: items.contains(selected) ? selected : items.first,
    );
    notifyListeners();
    return id;
  }

  /// ungroupShapes API.
  void ungroupShapes({List<PmlShape>? shapes}) {
    if (!config.allowsMutation) {
      return;
    }
    final List<PmlShape> items = _arrangementMembers(
      shapes ?? (selectedShapes.isNotEmpty ? selectedShapes : slide.shapes),
    );
    final Map<PmlShape, PmlShape> planned = _groupPlan();
    PmlArrange.ungroup([
      for (final shape in items) planned[shape]!,
    ], allShapes: planned.values.toList());
    _applyGroupMembership({for (final shape in items) shape: null});
  }

  List<PmlShape> _arrangementMembers(List<PmlShape> shapes) {
    final Set<PmlShape> seen = Set<PmlShape>.identity();
    for (final shape in shapes) {
      if (!seen.add(shape) || !_containsShape(slide.shapes, shape)) {
        throw ArgumentError(
          'Arrangement requires unique shapes from the active slide.',
        );
      }
    }
    return List<PmlShape>.of(shapes);
  }

  Map<PmlShape, PmlShape> _groupPlan() => {
    for (final shape in slide.shapes)
      shape: PmlShape(id: shape.id, name: shape.name, groupId: shape.groupId),
  };

  void _applyGroupMembership(Map<PmlShape, int?> proposed) {
    final Map<PmlShape, int?> next = {
      for (final entry in proposed.entries)
        if (entry.key.groupId != entry.value) entry.key: entry.value,
    };
    if (next.isEmpty) {
      return;
    }
    final Map<PmlShape, int?> previous = {
      for (final shape in next.keys) shape: shape.groupId,
    };
    commands.commit(
      _CallbackCommand(
        executeFn: () => next.forEach((shape, id) => shape.groupId = id),
        undoFn: () => previous.forEach((shape, id) => shape.groupId = id),
      ),
    );
    notifyListeners();
  }

  /// setLayoutPlaceholder API.
  void setLayoutPlaceholder({
    required String layoutName,
    required String text,
    String shapeName = 'Title',
  }) {
    if (!config.allowsMutation) {
      return;
    }
    PmlLayout? layout;
    for (final PmlLayout item in presentation.layouts) {
      if (item.name == layoutName) {
        layout = item;
        break;
      }
    }
    layout ??= PmlLayout(name: layoutName);
    if (!presentation.layouts.contains(layout)) {
      presentation.layouts.add(layout);
    }
    layout.placeholderText = text;
    PmlShape? ph;
    for (final PmlShape shape in layout.placeholders) {
      if (shape.name == shapeName) {
        ph = shape;
        break;
      }
    }
    if (ph == null) {
      ph = PmlShape(
        id: layout.placeholders.length + 1,
        name: shapeName,
        placeholder: true,
      );
      layout.placeholders.add(ph);
    }
    ph.text = text;
    notifyListeners();
  }

  DateTime? _presenterStarted;
  var presenterPaused = false;
  Duration _pausedElapsed = Duration.zero;

  /// presenterElapsed API.
  Duration get presenterElapsed {
    if (presenterPaused) {
      return _pausedElapsed;
    }
    return _presenterStarted == null
        ? Duration.zero
        : DateTime.now().difference(_presenterStarted!);
  }

  /// startPresenter API.
  void startPresenter() {
    _presenterStarted = DateTime.now();
    presenterPaused = false;
    _pausedElapsed = Duration.zero;
    notifyListeners();
  }

  /// pausePresenter API.
  void pausePresenter() {
    if (_presenterStarted == null) {
      startPresenter();
      return;
    }
    if (presenterPaused) {
      _presenterStarted = DateTime.now().subtract(_pausedElapsed);
      presenterPaused = false;
    } else {
      _pausedElapsed = presenterElapsed;
      presenterPaused = true;
    }
    notifyListeners();
  }

  /// stopPresenter API.
  void stopPresenter() {
    _presenterStarted = null;
    presenterPaused = false;
    _pausedElapsed = Duration.zero;
    notifyListeners();
  }

  /// canvasSlide API.
  PmlSlide get canvasSlide {
    if (stageKind == SlideStageKind.master) {
      return PmlSlide(id: 1, shapes: presentation.master.shapes);
    }
    if (stageKind == SlideStageKind.layout) {
      final PmlLayout layout = _activeLayout;
      return PmlSlide(id: 1, shapes: layout.placeholders);
    }
    return slide;
  }

  PmlLayout get _activeLayout {
    for (final PmlLayout layout in presentation.layouts) {
      if (layout.name == slide.layoutName) {
        return layout;
      }
    }
    if (presentation.layouts.isEmpty) {
      presentation.layouts.add(PmlLayout(name: 'Blank'));
    }
    return presentation.layouts.first;
  }

  /// setStageKind API.
  void setStageKind(SlideStageKind kind) {
    stageKind = kind;
    if (kind == SlideStageKind.layout && _activeLayout.placeholders.isEmpty) {
      _activeLayout.placeholders.add(
        PmlShape(
          id: 2,
          name: 'Title',
          text: _activeLayout.placeholderText.isEmpty
              ? 'Click to add title'
              : _activeLayout.placeholderText,
          placeholder: true,
        ),
      );
    }
    if (kind == SlideStageKind.master && presentation.master.shapes.isEmpty) {
      presentation.master.shapes.add(
        PmlShape(id: 2, name: 'Master title', text: presentation.master.name),
      );
    }
    selected = canvasSlide.shapes.isEmpty ? null : canvasSlide.shapes.first;
    notifyListeners();
  }

  /// nextVisibleSlide API.
  int? get nextVisibleSlide =>
      presentation.visibleIndexAfter(_activeSlide, direction: 1);

  @override
  /// dispose API.
  void dispose() {
    motionFrame.dispose();
    super.dispose();
  }

  @override
  /// detachInput API.
  void detachInput() {
    if (textEditor.editing) {
      cancelTextEdit();
    }
  }

  @override
  /// semanticsLabel API.
  String get semanticsLabel => config.strings.slideEditor;

  @override
  /// semanticsValue API.
  String get semanticsValue {
    final PmlShape? shape = selected;
    if (shape == null) {
      return '${config.strings.pageLabel} ${_activeSlide + 1}';
    }
    return '${config.strings.shapeLabel} ${shape.name} ${shape.text}';
  }

  @override
  /// documentProperties API.
  OfficeDocumentProperties get documentProperties => presentation.properties;

  @override
  set documentProperties(OfficeDocumentProperties value) {
    presentation.properties = value;
    notifyListeners();
  }

  @override
  /// documentStats API.
  OfficeTextStats get documentStats =>
      OfficeTextStats.ofPresentation(presentation);

  @override
  /// collectFindHits API.
  List<OfficeFindHit> collectFindHits(OfficeFindOptions options) =>
      OfficeFind.inPresentation(presentation, options);

  @override
  /// applyReplace API.
  int applyReplace(OfficeFindOptions options, {OfficeFindHit? only}) {
    final int count = OfficeFind.replacePresentation(
      presentation,
      options,
      only: only,
    );
    if (count > 0) {
      notifyListeners();
    }
    return count;
  }

  @override
  /// exportPdf API.
  Uint8List exportPdf({
    OfficePrintSettings settings = const OfficePrintSettings(),
    SfntFont? font,
    OfficeFontSet? fonts,
    PdfSlideExportMode mode = PdfSlideExportMode.slides,
  }) {
    return OfficePrint.presentation(
      presentation,
      settings: settings,
      font: font,
      fonts: fonts,
      mode: mode,
    );
  }

  @override
  /// revealFindHit API.
  void revealFindHit(OfficeFindHit hit) {
    final int index = hit.slideIndex ?? _activeSlide;
    setActiveSlide(index);
    final int? id = hit.shapeId;
    if (id != null) {
      for (final PmlShape shape in slide.shapes) {
        if (shape.id == id) {
          selectShape(shape);
          break;
        }
      }
    }
  }

  /// setShapeMedia API.
  void setShapeMedia(
    PmlShape shape, {
    String name = 'clip.mp4',
    List<int>? bytes,
  }) {
    if (!config.allowsMutation) {
      return;
    }
    shape.mediaName = name;
    if (bytes != null) {
      shape.mediaBytes
        ..clear()
        ..addAll(bytes);
    }
    notifyListeners();
  }

  /// playShapeMedia API.
  void playShapeMedia(PmlShape shape) {
    onPlayMedia?.call(shape);
    notifyListeners();
  }

  /// Host hook for video/audio playback.
  void Function(PmlShape shape)? onPlayMedia;

  /// setSpeakerNotes API.
  void setSpeakerNotes(String value) {
    if (!config.allowsMutation) {
      return;
    }
    final PmlSlide target = slide;
    final String before = target.notes;
    if (before == value) {
      return;
    }
    commands.commit(
      _CallbackCommand(
        executeFn: () => target.notes = value,
        undoFn: () => target.notes = before,
      ),
    );
  }

  /// addSlideSection API.
  PmlSection addSlideSection(String name, {int? startIndex}) {
    final PmlSection section = PmlSections.add(
      presentation,
      name: name,
      startIndex: startIndex ?? _activeSlide,
    );
    notifyListeners();
    return section;
  }

  /// alignShapes API.
  void alignShapes(PmlAlignAxis axis, {List<PmlShape>? shapes}) {
    if (!config.allowsMutation) {
      return;
    }
    _arrangeTransforms(
      shapes ?? slide.shapes,
      (planned) => PmlArrange.align(planned, axis),
    );
  }

  /// distributeShapes API.
  void distributeShapes({required bool horizontal, List<PmlShape>? shapes}) {
    if (!config.allowsMutation) {
      return;
    }
    _arrangeTransforms(
      shapes ?? slide.shapes,
      (planned) => PmlArrange.distribute(planned, horizontal: horizontal),
    );
  }

  void _arrangeTransforms(
    List<PmlShape> shapes,
    void Function(List<PmlShape>) arrange,
  ) {
    final List<PmlShape> items = _arrangementMembers(shapes);
    final List<PmlShape> planned = [
      for (final shape in items)
        PmlShape(id: shape.id, name: shape.name, transform: shape.transform),
    ];
    arrange(planned);
    final Map<PmlShape, PmlTransform> changes = {};
    for (int index = 0; index < items.length; index++) {
      final PmlTransform before = items[index].transform;
      final PmlTransform after = planned[index].transform;
      if (before.x != after.x ||
          before.y != after.y ||
          before.cx != after.cx ||
          before.cy != after.cy ||
          before.rot != after.rot ||
          before.flipH != after.flipH ||
          before.flipV != after.flipV) {
        changes[items[index]] = after;
      }
    }
    applyTransforms(changes);
  }

  /// applyMasterBackground API.
  void applyMasterBackground(String rgb) {
    if (!config.allowsMutation) {
      return;
    }
    presentation.master.background = rgb;
    for (final PmlSlide slide in presentation.slides) {
      slide.updateMasterBackground(rgb);
    }
    notifyListeners();
  }
}

// Notes-pane edits change existing paragraph runs and their ordering. Keeping
// those paragraph objects is essential: revisions and later commands hold them.
class _WordNoteEditSnapshot {
  _WordNoteEditSnapshot(WmlNote note, WmlDocument document)
    : blocks = List<WmlBlock>.of(note.blocks),
      text = WmlClone.plainTextOf(note.blocks),
      parents = <List<WmlBlock>, List<WmlBlock>>{
        for (final block in WordTree.descendants(note.blocks))
          for (final children in WordTree.childLists(block))
            children: List<WmlBlock>.of(children),
      },
      inlines = <WmlParagraph, List<WmlInline>>{
        for (final paragraph in note.allParagraphs)
          paragraph: WmlClone.inlines(paragraph.inlines),
      },
      revisions = WordRevisions.capture(document);

  final List<WmlBlock> blocks;
  final String text;
  final Map<List<WmlBlock>, List<WmlBlock>> parents;
  final Map<WmlParagraph, List<WmlInline>> inlines;
  final WmlRevisionSnapshot revisions;

  void restore(WmlNote note, WmlDocument document) {
    note.blocks
      ..clear()
      ..addAll(blocks);
    for (final entry in parents.entries) {
      entry.key
        ..clear()
        ..addAll(entry.value);
    }
    for (final entry in inlines.entries) {
      entry.key.inlines
        ..clear()
        ..addAll(WmlClone.inlines(entry.value));
    }
    revisions.restore(document);
  }
}

class _HeadingSnap {
  _HeadingSnap({
    required this.properties,
    required this.headingLevel,
    required this.styleId,
    required this.spacingBefore,
    required this.spacingAfter,
    required this.keepTogether,
    required this.inlines,
  });

  /// capture API.
  factory _HeadingSnap.capture(WmlParagraph paragraph) {
    return _HeadingSnap(
      properties: paragraph.properties.copy(),
      headingLevel: paragraph.properties.headingLevel,
      styleId: paragraph.properties.styleId,
      spacingBefore: paragraph.properties.spacingBefore,
      spacingAfter: paragraph.properties.spacingAfter,
      keepTogether: paragraph.properties.keepTogether,
      inlines: WordEditorController._cloneInlines(paragraph),
    );
  }

  /// Full paragraph properties: a style apply also changes alignment,
  /// indents and numbering, which undo must restore.
  final WmlParagraphProps properties;

  /// headingLevel API.
  final int? headingLevel;

  /// styleId API.
  final String? styleId;

  /// spacingBefore API.
  final double spacingBefore;

  /// spacingAfter API.
  final double spacingAfter;

  /// keepTogether API.
  final bool keepTogether;

  /// inlines API.
  final List<WmlInline> inlines;

  /// restore API.
  void restore(WmlParagraph paragraph) {
    paragraph.properties = properties.copy();
    paragraph.properties
      ..headingLevel = headingLevel
      ..styleId = styleId
      ..spacingBefore = spacingBefore
      ..spacingAfter = spacingAfter
      ..keepTogether = keepTogether;
    paragraph.inlines
      ..clear()
      ..addAll(WordEditorController._cloneInlinesFrom(inlines));
  }
}

class _SheetGridSnap {
  _SheetGridSnap._({
    required this.rowIndices,
    required this.cells,
    required this.widths,
    required this.heights,
    required this.merges,
  });

  /// capture API.
  factory _SheetGridSnap.capture(SmlWorksheet sheet) {
    return _SheetGridSnap._(
      rowIndices: List<int>.of(sheet.rows.keys),
      cells: <({SmlCell target, SmlCell state})>[
        for (final SmlCell cell in sheet.allCells)
          (
            target: cell,
            state: SmlCell(
              ref: cell.ref,
              type: cell.type,
              value: cell.value,
              formula: cell.formula,
              styleIndex: cell.styleIndex,
              hasExplicitStyleIndex: cell.hasExplicitStyleIndex,
              horizontalAlign: cell.horizontalAlign,
              fillRgb: cell.fillRgb,
              hasExplicitFillColorEdit: cell.hasExplicitFillColorEdit,
              fontRgb: cell.fontRgb,
              hasExplicitFontColorEdit: cell.hasExplicitFontColorEdit,
              fontBold: cell.fontBold,
              fontSize: cell.fontSize,
              borderRgb: cell.borderRgb,
              borderWidth: cell.borderWidth,
              locked: cell.locked,
            ),
          ),
      ],
      widths: sheet.captureColumns(),
      heights: Map<int, double>.from(sheet.rowHeights),
      merges: <SmlMerge>[
        for (final SmlMerge merge in sheet.merges) merge.copy(),
      ],
    );
  }

  // Empty rows are part of the grid even when they contain no cells.
  final List<int> rowIndices;

  // Other history commands retain these cell objects. Copy their data without
  // replacing their identities when a grid edit is undone or redone.
  final List<({SmlCell target, SmlCell state})> cells;

  /// widths API.
  final Map<int, SmlColumnSnapshot> widths;

  /// heights API.
  final Map<int, double> heights;

  /// merges API.
  final List<SmlMerge> merges;

  /// restore API.
  void restore(SmlWorksheet sheet) {
    sheet.rows.clear();
    for (final int index in rowIndices) {
      sheet.rows[index] = SmlRow(index);
    }
    for (final ({SmlCell target, SmlCell state}) entry in cells) {
      final SmlCell cell = entry.state;
      final SmlCell target = entry.target;
      target
        ..ref = cell.ref
        ..type = cell.type
        ..value = cell.value
        ..formula = cell.formula
        ..styleIndex = cell.styleIndex
        ..hasExplicitStyleIndex = cell.hasExplicitStyleIndex
        ..horizontalAlign = cell.horizontalAlign
        ..wrapText = cell.wrapText
        ..fillRgb = cell.fillRgb
        ..hasExplicitFillColorEdit = cell.hasExplicitFillColorEdit
        ..fontRgb = cell.fontRgb
        ..hasExplicitFontColorEdit = cell.hasExplicitFontColorEdit
        ..fontBold = cell.fontBold
        ..fontSize = cell.fontSize
        ..fontFamily = cell.fontFamily
        ..borderRgb = cell.borderRgb
        ..borderWidth = cell.borderWidth
        ..locked = cell.locked;
      sheet.row(cell.ref.row).cells[cell.ref.col] = target;
    }
    sheet.restoreColumns(widths);
    sheet.rowHeights
      ..clear()
      ..addAll(heights);
    sheet.merges
      ..clear()
      ..addAll(merges.map((SmlMerge merge) => merge.copy()));
  }
}

// Only this command may cross an otherwise read-only protection boundary.
// Ordinary document commands remain blocked until protection is undone.
/// A native Zotero operation pinned to one editor document and selection.
/// Commands operate on [session] until [apply] commits the complete result.
final class WordZoteroTransaction {
  WordZoteroTransaction._(
    this._controller,
    this.session, {
    bool Function()? isCurrent,
  }) : _hostIsCurrent = isCurrent,
       _target = _capture(_controller);

  final WordEditorController _controller;
  final WordZoteroCitingSession session;
  final bool Function()? _hostIsCurrent;
  final Object _target;
  bool _applied = false;
  Offset? _contextOrigin;
  Offset? _revealedOrigin;
  double? _contextScale;

  /// Context for an explicit Field.select callback, checked against the
  /// original document and host target. No staged content is published.
  WordZoteroFieldSelectionContext? get selectedFieldContext {
    assertCurrent();
    return session.selectedFieldContext;
  }

  /// Only this operation's currently presented context. An older prompt must
  /// not adopt the selected field of a newer operation in the same editor.
  WordZoteroFieldSelectionContext? get presentedFieldContext =>
      identical(_controller._zoteroContextOwner, this)
      ? _controller.zoteroFieldContext
      : null;

  /// Drives a native callback and presents its selected source field without
  /// moving the user's caret, selection, Notes target, focus or undo history.
  /// Hosts still handle Document.displayAlert themselves. Always call
  /// [clearFieldContext] in the host's finally/disposal path as well.
  Object? handle(String command, List<Object?> arguments) {
    try {
      assertCurrent();
      final response = session.handle(command, arguments);
      if (command == 'Field.select') {
        _controller._presentZoteroFieldContext(this);
      } else if (identical(_controller._zoteroContextOwner, this) &&
          (command == 'Field.delete' ||
              command == 'Field.removeCode' ||
              command == 'Document.insertField' ||
              command == 'Document.insertText' ||
              command == 'Document.importDocument' ||
              command == 'Document.exportDocument' ||
              command == 'Document.complete')) {
        if (session.selectedFieldContext == null) clearFieldContext();
      }
      return response;
    } on Object {
      clearFieldContext();
      rethrow;
    }
  }

  /// Discards only this operation's presentation. A newer operation's context
  /// and a viewport subsequently moved by the user are left alone.
  void clearFieldContext({bool notify = true}) =>
      _controller._clearZoteroFieldContext(this, notify: notify);

  void _revealFieldContext(WordZoteroFieldSelectionContext context) {
    final ranges = context.sourceRanges;
    if (ranges.isEmpty) return;
    final viewport = _controller.viewport;
    final extent = viewport.extent;
    final scale = viewport.scale * 96 / 72;
    if (extent.isEmpty ||
        !extent.width.isFinite ||
        !extent.height.isFinite ||
        !scale.isFinite ||
        scale <= 0) {
      return;
    }
    final layout = _controller.documentLaidOut;
    if (layout.pages.isEmpty) return;
    // Match RenderWordCanvas's paged content and page-left geometry. A reveal
    // changes only the viewport; no layout pass is guaranteed to clamp it.
    const sideGutter = 64.0;
    const scrollBar = 14.0;
    const pageGap = 24.0;
    final pageWidth =
        layout.pages.fold<double>(
          layout.pageSize.width,
          (width, page) => math.max(width, page.width),
        ) *
        scale;
    final viewWidth = math.max(0.0, extent.width - scrollBar);
    if (viewWidth <= 0) return;
    final pageLeft = viewWidth > pageWidth + sideGutter * 2
        ? (viewWidth - pageWidth) / 2
        : sideGutter;
    final content = Size(
      pageWidth + sideGutter * 2 + scrollBar,
      layout.pages.fold<double>(
        pageGap,
        (height, page) => height + page.height * scale + pageGap,
      ),
    );
    // A later select may follow deliberate scrolling or zooming while the
    // prompt was open. Return to that newer view, not the first reveal's view.
    if (_contextOrigin != null &&
        (viewport.origin != _revealedOrigin ||
            viewport.scale != _contextScale)) {
      _contextOrigin = viewport.origin;
      _contextScale = viewport.scale;
    }
    for (final range in ranges) {
      for (final page in layout.pages) {
        for (final line in [...page.lines, ...page.notes]) {
          if (!identical(line.sourceParagraph, range.paragraph)) continue;
          final bounds = _fieldContextBounds(page, line, range);
          if (bounds == null) continue;
          final left = pageLeft + bounds.left * scale;
          final right = pageLeft + bounds.right * scale;
          final top =
              layout.pageStackTop(page.index, scale) + bounds.top * scale;
          final padding = math.min(24.0, viewWidth / 4);
          var nextX = viewport.origin.dx;
          if (right - left > viewWidth) {
            // An oversized result cannot fit at this zoom. Show its leading
            // edge, respecting the original paragraph's writing direction.
            nextX = range.paragraph.properties.bidiBaseLevel == 1
                ? right - viewWidth + padding
                : left - padding;
          } else if (left < nextX) {
            nextX = left - padding;
          } else if (right > nextX + viewWidth) {
            nextX = right - viewWidth + padding;
          }
          _contextOrigin ??= viewport.origin;
          _contextScale ??= viewport.scale;
          viewport.origin = Offset(nextX, top - 48);
          viewport.clampTo(content: content, view: extent);
          // Remember the actual legal origin so a later layout clamp cannot
          // be mistaken for deliberate user scrolling during cleanup.
          _revealedOrigin = viewport.origin;
          return;
        }
      }
    }
  }

  Rect? _fieldContextBounds(
    LaidOutPage page,
    LaidOutLine line,
    WordZoteroFieldSelectionRange range,
  ) {
    final displayRanges = WordProofingGeometry.displayRanges(
      line,
      range.start,
      range.end,
    );
    if (displayRanges.isEmpty) return null;
    final boxes = <Rect>[];
    if (line.glyphs.isNotEmpty) {
      // Offscreen pages may not have their Flutter metrics yet. Measure as
      // the canvas will paint, then restore every fitted value so the reveal
      // cannot alter incremental layout or an existing renderer fit cache.
      final originalX = line.x;
      final originalWidth = line.width;
      final positions = [
        for (final glyph in line.glyphs) (x: glyph.x, advance: glyph.advance),
      ];
      try {
        PaintRunText.fitLine(
          line,
          line.sourceText ?? range.paragraph.text,
          themeFamily: _controller.config.theme.fontFamily,
        );
        for (final display in displayRanges) {
          if (display.isCollapsed) {
            final span = CaretEngine.logicalSpan(line);
            if (display.start < span.min || display.start > span.max) continue;
            final x = PaintRunText.caretXOnLine(
              line,
              display.start,
              paragraph: line.sourceText ?? range.paragraph.text,
              themeFamily: _controller.config.theme.fontFamily,
              paragraphRtl: range.paragraph.properties.bidiBaseLevel == 1,
            );
            boxes.add(Rect.fromLTWH(x, line.y, 1, line.height));
          } else {
            boxes.addAll(
              CaretEngine.rangeRectsOnLine(
                line,
                line.y,
                line.height,
                display.start,
                display.end,
              ),
            );
          }
        }
      } finally {
        line
          ..x = originalX
          ..width = originalWidth;
        for (var i = 0; i < line.glyphs.length; i++) {
          line.glyphs[i]
            ..x = positions[i].x
            ..advance = positions[i].advance;
        }
      }
    } else if (line.overlayText?.isNotEmpty == true) {
      final text = line.overlayText!;
      final painter = PaintRunText.plain(
        text: text,
        fontSize: line.overlaySize,
        color: _controller.config.theme.documentText,
        themeFamily: _controller.config.theme.fontFamily,
        bold: line.overlayBold,
      )..layout();
      try {
        var x = line.x;
        if (line.tocLeader) {
          final sections = _controller.document.sections;
          final marginRight =
              page.sectionIndex >= 0 && page.sectionIndex < sections.length
              ? sections[page.sectionIndex].margins.right
              : 72.0;
          x = line.boxWidth > 0
              ? line.boxX + line.boxWidth - painter.width
              : WordToc.pageNumberX(
                  pageWidth: page.width,
                  marginRight: marginRight,
                  numberWidth: painter.width,
                );
        } else if (line.justification == WmlJustification.right) {
          x =
              (line.width > 1 ? line.x + line.width : page.width) -
              painter.width;
        } else if (line.justification == WmlJustification.center) {
          x += (line.width - painter.width) / 2;
        }
        for (final display in displayRanges) {
          if (display.start > text.length) continue;
          if (display.isCollapsed) {
            final caret = painter.getOffsetForCaret(
              TextPosition(offset: display.start),
              Rect.zero,
            );
            boxes.add(Rect.fromLTWH(x + caret.dx, line.y, 1, painter.height));
          } else {
            boxes.addAll(
              painter
                  .getBoxesForSelection(
                    TextSelection(
                      baseOffset: display.start,
                      extentOffset: display.end.clamp(0, text.length),
                    ),
                  )
                  .map((box) => box.toRect().shift(Offset(x, line.y))),
            );
          }
        }
      } finally {
        painter.dispose();
      }
    } else if (range.start == range.end && range.paragraph.text.isEmpty) {
      boxes.add(Rect.fromLTWH(line.x, line.y, 1, line.height));
    }
    if (boxes.isEmpty) return null;
    var bounds = boxes.first;
    for (final box in boxes.skip(1)) {
      bounds = bounds.expandToInclude(box);
    }
    if (line.paragraphIndex < 0 && line.boxWidth > 0) {
      bounds = bounds.intersect(
        Rect.fromLTWH(line.boxX, line.y, line.boxWidth, line.height),
      );
    }
    return bounds.isEmpty ? null : bounds;
  }

  void _restoreContextViewport() {
    if (!_controller.isDisposed &&
        !_applied &&
        (_hostIsCurrent?.call() ?? true) &&
        _target == _capture(_controller) &&
        identical(_controller.document, session.document) &&
        _contextOrigin != null &&
        _controller.viewport.origin == _revealedOrigin &&
        _controller.viewport.scale == _contextScale) {
      try {
        session.assertUnchanged();
        _controller.viewport.origin = _contextOrigin!;
      } on StateError {
        // A direct host model edit can bypass the editor's revision counter.
        // It must not cause this stale operation to move the new document view.
      }
    }
    _contextOrigin = null;
    _revealedOrigin = null;
    _contextScale = null;
  }

  static Object _capture(WordEditorController controller) => (
    document: controller.document,
    revision: controller.contentRevision,
    caret: controller.caret,
    paragraph: controller.caret.paragraphIndex,
    offset: controller.caret.logicalIndex,
    anchorParagraph: controller.caret.selectionAnchorParagraph,
    anchorOffset: controller.caret.selectionAnchor,
    composing: controller.input.composing,
    note: controller.noteEditingTarget,
    headerFooter: controller.isEditingHeaderFooter,
    footer: controller.isEditingFooter,
    headerFooterVariant: controller.editingHeaderFooterVariant,
    section: controller.isEditingHeaderFooter
        ? controller.editingSectionIndex
        : null,
    comment: controller.isEditingComment ? controller.selectedComment : null,
    frame: controller.selectedFrame,
    editingFrame: controller.editingFrame,
    table: controller.selectedTable,
    tableBand: controller.selectedTableBand,
    visual: controller.selectedVisual,
    equation: controller.selectedEquation,
  );

  /// Run before every protocol command, after host prompts, and before apply.
  void assertCurrent() {
    if (_applied ||
        _controller.isDisposed ||
        !(_hostIsCurrent?.call() ?? true) ||
        !_controller.config.allowsMutation ||
        _controller.document.trackRevisions ||
        _controller.document.restrictEditing ||
        _target != _capture(_controller)) {
      throw StateError(
        'The document or insertion point changed while Zotero was open. Close the Zotero dialog and try again.',
      );
    }
  }

  void apply() {
    assertCurrent();
    clearFieldContext();
    _controller._applyZoteroTransaction(session);
    _applied = true;
  }
}

/// Keeps original object identities so older and newer undo commands continue
/// to address the same paragraphs, note objects and block containers.
final class _ZoteroDocumentSnapshot {
  _ZoteroDocumentSnapshot._({
    required this.paragraphs,
    required this.blocks,
    required this.footnotes,
    required this.endnotes,
    required this.data,
    required this.numbering,
  });

  factory _ZoteroDocumentSnapshot.capture(WmlDocument document) {
    final blocks = <List<WmlBlock>, List<WmlBlock>>{};
    final paragraphs =
        <
          WmlParagraph,
          ({List<WmlInline> inlines, WmlParagraphProps properties})
        >{};
    void visit(List<WmlBlock> list) {
      blocks[list] = List<WmlBlock>.of(list);
      for (final block in list) {
        if (block is WmlParagraph) {
          paragraphs[block] = (
            inlines: WmlClone.inlines(block.inlines),
            properties: block.properties.copy(),
          );
        }
        for (final children in WordTree.childLists(block)) {
          visit(children);
        }
      }
    }

    for (final section in document.sections) {
      visit(section.blocks);
    }
    for (final note in [...document.footnotes, ...document.endnotes]) {
      visit(note.blocks);
    }
    return _ZoteroDocumentSnapshot._(
      paragraphs: paragraphs,
      blocks: blocks,
      footnotes: List<WmlNote>.of(document.footnotes),
      endnotes: List<WmlNote>.of(document.endnotes),
      data: WordZoteroTransfer.isTransferDocument(document)
          ? document.zoteroDocumentData
          : WordZoteroDocumentData.read(document),
      numbering: WordListNumberingSnapshot.capture(document),
    );
  }

  final Map<
    WmlParagraph,
    ({List<WmlInline> inlines, WmlParagraphProps properties})
  >
  paragraphs;
  final Map<List<WmlBlock>, List<WmlBlock>> blocks;
  final List<WmlNote> footnotes;
  final List<WmlNote> endnotes;
  final String? data;
  final WordListNumberingSnapshot numbering;

  void assertRestorable(WmlDocument document) {
    for (final entry in blocks.entries) {
      _assertRestorableList(entry.key, entry.value);
    }
    for (final entry in paragraphs.entries) {
      _assertRestorableList(entry.key.inlines, entry.value.inlines);
    }
    _assertRestorableList(document.footnotes, footnotes);
    _assertRestorableList(document.endnotes, endnotes);
  }

  static void _assertRestorableList<T>(List<T> target, Iterable<T> values) {
    try {
      // No content changes: reject fixed/unmodifiable containers and retain
      // the runtime element type when checking covariant owners.
      target.length = target.length;
      final probe = target.sublist(0, 0);
      for (final value in values) {
        probe.add(value);
      }
    } on UnsupportedError {
      throw UnsupportedError(
        'Zotero edits require mutable document containers.',
      );
    } on TypeError {
      throw UnsupportedError(
        'Zotero edits require compatible document containers.',
      );
    }
  }

  void restore(WmlDocument document) {
    for (final entry in blocks.entries) {
      entry.key.clear();
      // Owners may retain a covariant List<WmlParagraph>. Adding each saved
      // value preserves that valid element type without an Iterable cast.
      for (final block in entry.value) {
        entry.key.add(block);
      }
    }
    for (final entry in paragraphs.entries) {
      entry.key.properties = entry.value.properties.copy();
      entry.key.inlines.clear();
      for (final inline in WmlClone.inlines(entry.value.inlines)) {
        entry.key.inlines.add(inline);
      }
    }
    document.footnotes.clear();
    for (final note in footnotes) {
      document.footnotes.add(note);
    }
    document.endnotes.clear();
    for (final note in endnotes) {
      document.endnotes.add(note);
    }
    document.zoteroDocumentData = data;
    numbering.restore(document);
  }
}

class _WordProtectionCommand extends _CallbackCommand {
  _WordProtectionCommand({required super.executeFn, required super.undoFn});
}

class _CallbackCommand implements OfficeCommand {
  _CallbackCommand({required this.executeFn, required this.undoFn});

  /// Function API.
  final void Function() executeFn;

  /// Function API.
  final void Function() undoFn;

  @override
  /// execute API.
  void execute() => executeFn();

  @override
  /// undo API.
  void undo() => undoFn();

  @override
  /// invert API.
  OfficeCommand invert() =>
      _CallbackCommand(executeFn: undoFn, undoFn: executeFn);
}

/// Engine values of lines paint-fitted in place ([LaidOutLine.x], width and
/// each glyph's x and advance — everything fitting changes), so a fitted
/// layout can still seed an incremental relayout.
final class _FittedLines {
  _FittedLines._(this.lines, this.values);

  static final Expando<_FittedLines> _byLayout = Expando<_FittedLines>(
    'fitted lines',
  );

  final List<LaidOutLine> lines;
  final Float64List values;

  static _FittedLines? of(LaidOutDocument laid) => _byLayout[laid];

  static void capture(LaidOutDocument laid) {
    final List<LaidOutLine> lines = <LaidOutLine>[
      for (final LaidOutPage page in laid.pages) ...<LaidOutLine>[
        ...page.lines,
        ...page.header,
        ...page.footer,
      ],
    ];
    var n = 0;
    for (final LaidOutLine line in lines) {
      n += 2 + 2 * line.glyphs.length;
    }
    final Float64List values = Float64List(n);
    var i = 0;
    for (final LaidOutLine line in lines) {
      values[i++] = line.x;
      values[i++] = line.width;
      for (final LaidOutGlyph glyph in line.glyphs) {
        values[i++] = glyph.x;
        values[i++] = glyph.advance;
      }
    }
    _byLayout[laid] = _FittedLines._(lines, values);
  }

  /// Puts the engine values back; [laid] is then engine output again.
  static void restore(LaidOutDocument laid) {
    final _FittedLines? fitted = _byLayout[laid];
    if (fitted == null) return;
    _byLayout[laid] = null;
    var i = 0;
    final Float64List values = fitted.values;
    for (final LaidOutLine line in fitted.lines) {
      line.x = values[i++];
      line.width = values[i++];
      for (final LaidOutGlyph glyph in line.glyphs) {
        glyph.x = values[i++];
        glyph.advance = values[i++];
      }
    }
  }
}
