import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
import '../editor_word/table_history.dart';
import 'office_clipboard.dart';
import 'office_theme.dart';

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
    findSession
      ..active = true
      ..options = options
      ..hits = collectFindHits(options)
      ..index = findSession.hits.isEmpty ? -1 : 0;
    final OfficeFindHit? hit = findSession.current;
    if (hit != null) {
      revealFindHit(hit);
    }
    onFindResult?.call(hit);
    notifyListeners();
    return findSession.hits;
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
    if (findSession.index + 1 < findSession.hits.length) {
      findSession.index++;
    } else if (wrap && findSession.hits.isNotEmpty) {
      findSession.index = 0;
    } else {
      return findSession.current;
    }
    final OfficeFindHit? hit = findSession.current;
    if (hit != null) {
      revealFindHit(hit);
    }
    onFindResult?.call(hit);
    notifyListeners();
    return hit;
  }

  /// findPrevious API.
  OfficeFindHit? findPrevious({bool wrap = true}) {
    if (findSession.hits.isEmpty) {
      return findNext(wrap: wrap);
    }
    if (findSession.index > 0) {
      findSession.index--;
    } else if (wrap && findSession.hits.isNotEmpty) {
      findSession.index = findSession.hits.length - 1;
    }
    final OfficeFindHit? hit = findSession.current;
    if (hit != null) {
      revealFindHit(hit);
    }
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
    notifyListeners();
  }

  @override
  /// notifyListeners API.
  void notifyListeners() {
    if (_disposed) {
      return;
    }
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
  /// WordEditorController API.
  WordEditorController({WmlDocument? document, super.config, this.layoutEngine})
    : document = document ?? WmlDocument.empty() {
    _requestedMode = _config.mode;
    _config = _effectiveConfig(_config);
    relayout();
    input = OfficeInputBridge(
      onValue: _onIme,
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
  }) {
    final WordEditorController controller = WordEditorController(
      config: config,
      layoutEngine: layoutEngine,
    );
    controller.loadBytes(bytes, password: password);
    return controller;
  }

  /// document API.
  WmlDocument document;

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
  late LaidOutDocument documentLaidOut;

  /// commentLaidOut API.
  LaidOutDocument? commentLaidOut;

  /// Custom layout engine. When null, lines break with the same Flutter
  /// metrics the canvas paints with ([PaintRunText.advanceOf]).
  final WordLayoutEngine? layoutEngine;

  WordLayoutEngine? _paintMetricsEngine;

  WordLayoutEngine get _engine =>
      layoutEngine ??
      (_paintMetricsEngine ??= WordLayoutEngine(
        font: null,
        measure: (int codePoint, double sizePoints, WmlRunProps props) =>
            PaintRunText.advanceOf(
              codePoint,
              sizePoints,
              props,
              themeFamily: config.theme.fontFamily,
            ),
      ));

  /// Lays the document out again with fresh paint metrics, for example
  /// after fonts finish loading.
  void refreshMetrics() {
    fitPaintMetrics(themeFamily: config.theme.fontFamily);
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
  var _editingSectionIndex = 0;

  /// commentSurfaceWidth API.
  double commentSurfaceWidth = 288;

  /// input API.
  late final OfficeInputBridge input;
  var _applyingIme = false;

  /// fromMillisecondsSinceEpoch API.
  var _localEditAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _textBeforeLocalEdit;
  double? _stickyCaretX;

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
      comment.paragraphs.add(
        WmlParagraph(
          inlines: <WmlInline>[
            WmlRun(properties: WmlRunProps(fontSizeHalfPoints: 20)),
          ],
        ),
      );
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

  List<WmlParagraph> _ensureHeaderFooterParagraphs() {
    final WmlSection section = document.sections.isEmpty
        ? WmlSection()
        : document.sections[_editingSectionIndex.clamp(
            0,
            document.sections.length - 1,
          )];
    final List<WmlParagraph> story = _editingFooter
        ? section.footer
        : section.header;
    if (story.isEmpty) {
      story.add(WmlParagraph(inlines: <WmlInline>[WmlRun(text: '')]));
    }
    return story;
  }

  /// beginHeaderFooterEdit API.
  void beginHeaderFooterEdit(int pageIndex, {required bool footer}) {
    if (!config.allowsMutation && !config.allowsSelection) {
      return;
    }
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
    selectedCommentId = id;
    if (selectedComment == null) {
      return;
    }
    endHeaderFooterEdit();
    _editingComment = true;
    selectedVisual = null;
    selectedEquation = null;
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
    _acceptOpenedWord(
      WordDeserializer().read(OfficeRepair.open(bytes, password: password)),
    );
  }

  /// loadBytesAsync API.
  Future<void> loadBytesAsync(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
  }) async {
    final WordOpenPayload opened = await OfficeIsolateOpen.word(
      bytes,
      password: password,
      onProgress: onProgress,
    );
    _acceptOpenedWord(opened.document);
  }

  void _acceptOpenedWord(WmlDocument opened) {
    document = opened;
    commands.clear();
    _noteEditStart.clear();
    _syncProtectionMode();
    _editingComment = false;
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
    relayout();
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

  /// relayout API.
  void relayout({bool localEdit = false}) {
    _syncEmptyParagraphDirection();
    // Header/footer text is chrome, not section body content. The incremental
    // layout path reuses page chrome, so edits there would never reach the
    // header band. Force a full layout while editing a header or footer.
    final bool incremental = localEdit && !isEditingHeaderFooter;
    if (!incremental) {
      WordLink.ensureHeadingBookmarks(document);
      WordToc.refreshEmpty(document);
      WordToc.rebindHeadings(document);
    }
    final WordLayoutEngine engine = _engine;
    final int fromSection = incremental ? sectionIndexAtCaret : 0;
    documentLaidOut = engine.layout(
      document,
      updateFields: !incremental,
      fromSectionIndex: fromSection,
      reuse: incremental ? documentLaidOut : null,
    );
    if (!incremental && WordToc.syncPageNumbers(document, documentLaidOut)) {
      documentLaidOut = engine.layout(document);
    }
    if (!incremental || isEditingComment) {
      _layoutComment();
    }
  }

  @override
  void onSurfaceDirectionChanged() {
    _syncEmptyParagraphDirection();
    if (config.allowsMutation) {
      attachInput();
    }
  }

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
            WordToc.applyHeading(paras[p], level);
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
    String author = 'Quds Office',
    String initials = 'QO',
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
    String author = 'Quds Office',
    String initials = 'QO',
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
    input.attach(multiline: true);
    _writeImeValue();
  }

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
        } else if (caret.paragraphIndex >= paras.length - 1) {
          caret.logicalIndex = text.length;
          remaining = 0;
        } else {
          remaining -= room + 1;
          caret.paragraphIndex++;
          caret.logicalIndex = 0;
        }
      } else if (caret.logicalIndex + remaining >= 0) {
        caret.logicalIndex += remaining;
        remaining = 0;
      } else if (caret.paragraphIndex <= 0) {
        caret.logicalIndex = 0;
        remaining = 0;
      } else {
        remaining += caret.logicalIndex + 1;
        caret.paragraphIndex--;
        caret.logicalIndex = paras[caret.paragraphIndex].text.length;
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
    caret.paragraphIndex = (caret.paragraphIndex + delta).clamp(
      0,
      paras.length - 1,
    );
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
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          host.remove(target);
          selectedTable = null;
          selectedTableBand = null;
          _ensureBodyHasParagraph();
        },
        undoFn: () {
          if (!host.contains(target)) {
            host.insert(at.clamp(0, host.length), target);
            WordTable.restore(target, snap);
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
  Future<void> cutToClipboard() async {
    if (!canCut) {
      return;
    }
    await copyToClipboard();
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
    relayout();
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

  /// insertText API.
  void insertText(String text) {
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
  void deleteSelectionOr({required bool backward}) {
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
          first.inlines.addAll(
            _cloneInlinesFrom(
              last.inlines,
            ).where((inline) => inline is! WmlRun || inline.text.isNotEmpty),
          );
          WmlRunEdit.coalesce(first);
          parent.removeRange(range.startPara + 1, range.endPara + 1);
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
  void insertParagraphBreak() => _insertParagraphBreak();

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
    _textBeforeLocalEdit = _activeParagraph.text;
  }

  @override
  /// afterHistoryChange API.
  void afterHistoryChange() {
    final List<WmlParagraph> paragraphs = _paragraphs;
    caret.paragraphIndex = paragraphs.isEmpty
        ? 0
        : caret.paragraphIndex.clamp(0, paragraphs.length - 1);
    relayout();
    caret.logicalIndex = caret.logicalIndex.clamp(
      0,
      _activeParagraph.text.length,
    );
    caret.collapseSelection();
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
      return;
    }
    final WmlParagraph para = _activeParagraph;
    final String old = para.text;
    if (value.text != old) {
      _setParagraphText(WmlClone.paragraph(para), value.text);
      _applyingIme = true;
      _syncParagraphDirection(para, incoming: value.text);
      _commitParagraphInlines(para, () => _setParagraphText(para, value.text));
      _applyingIme = false;
      relayout(localEdit: true);
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
    notifyListeners();
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

  /// applyParagraphFormat API.
  void applyParagraphFormat(void Function(WmlParagraphProps props) update) {
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
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          for (int i = start; i <= end; i++) {
            paras[i].properties = before[i]!.copy();
            update(paras[i].properties);
          }
        },
        undoFn: () {
          for (final MapEntry<int, WmlParagraphProps> entry in before.entries) {
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
    // Empty paragraphs track studio language / incoming script and may flip.
    if (existing.isEmpty) {
      final bool preferRtl =
          OfficeTypeface.isRtlText(incoming) ||
          config.textDirection == TextDirection.rtl;
      if (preferRtl) {
        para.properties
          ..rightToLeft = true
          ..justification = WmlJustification.right;
      } else {
        // Drop auto-RTL latch so BiDi / later Arabic input can take over.
        para.properties.rightToLeft = null;
        if (para.properties.justification == WmlJustification.right) {
          para.properties.justification = WmlJustification.left;
        }
      }
      return;
    }
    if (para.properties.rightToLeft != null) {
      return;
    }
    if (OfficeTypeface.isRtlText(existing) ||
        OfficeTypeface.isRtlText(incoming)) {
      if (para.properties.justification == WmlJustification.left) {
        para.properties
          ..rightToLeft = true
          ..justification = WmlJustification.right;
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

  List<WmlBlock>? _parentBlocksOfVisual(WmlVisual visual) =>
      _parentBlocksOfBlock(visual);

  List<WmlBlock>? _parentBlocksOfBlock(WmlBlock target) =>
      WordTree.locate(document, target)?.parent;

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

    commands.commit(
      _CallbackCommand(
        executeFn: () {
          restore();
          for (final paragraph in before.keys) {
            WordStyles.apply(paragraph, styleId, document: document);
          }
        },
        undoFn: restore,
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

  void _resolveRevisions(List<WmlRevision> revisions, {required bool accept}) {
    if (!config.allowsMutation) {
      return;
    }
    // Story-local paragraph indices cannot order targets across stories or
    // after paragraph insertion. Rightmost spans first is sufficient for all
    // independent paragraph targets, and keeps their offsets valid.
    final List<WmlRevision> targets =
        revisions.where(document.revisions.contains).toList()
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
    final WmlRevisionSnapshot before = WordRevisions.capture(document);
    final int? selected = selectedRevisionIndex;
    void restore() {
      for (final entry in inlines.entries) {
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
          for (final revision in targets) {
            if (accept) {
              WordRevisions.accept(document, revision);
            } else {
              WordRevisions.reject(document, revision);
            }
          }
          selectedRevisionIndex = null;
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

  /// compareWith API.
  void compareWith(WmlDocument other) {
    WordCompare.compare(other, document);
    relayout();
    notifyListeners();
  }

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
    relayout(localEdit: edit.margins == null);
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
    _resolveRevisions(List<WmlRevision>.of(document.revisions), accept: true);
  }

  /// rejectAllRevisions API.
  void rejectAllRevisions() {
    _resolveRevisions(List<WmlRevision>.of(document.revisions), accept: false);
  }

  /// selectedRevision API.
  WmlRevision? get selectedRevision {
    final int? index = selectedRevisionIndex;
    if (index == null || index < 0 || index >= document.revisions.length) {
      return document.revisions.isEmpty ? null : document.revisions.first;
    }
    return document.revisions[index];
  }

  /// selectRevision API.
  void selectRevision(WmlRevision revision) {
    final int index = document.revisions.indexOf(revision);
    selectedRevisionIndex = index < 0 ? null : index;
    notifyListeners();
  }

  /// stepRevision API.
  void stepRevision(int delta) {
    if (document.revisions.isEmpty) {
      selectedRevisionIndex = null;
      notifyListeners();
      return;
    }
    final int current = selectedRevisionIndex ?? 0;
    selectedRevisionIndex = (current + delta) % document.revisions.length;
    if (selectedRevisionIndex! < 0) {
      selectedRevisionIndex = document.revisions.length - 1;
    }
    notifyListeners();
  }

  /// The text a notes editor shows for [note]: one line per paragraph.
  String noteEditText(WmlNote note) => WordNotes.editableText(note);

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

    commands.commit(
      _CallbackCommand(
        executeFn: () => after.restore(note, document),
        undoFn: () => before.restore(note, document),
      ),
    );
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

  /// checkSpelling API.
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
    super.config,
    this._activeSheet = 0,
    this.columnMetricsResolver = SheetFontMetrics.measure,
  }) : workbook = workbook ?? SmlWorkbook() {
    cellEditor = InlineCellEditor(
      onCommit: _commitFormula,
      onChanged: _onCellEditorChanged,
      commitOnNewline: true,
    );
    this.workbook.resolveColumnMetrics(columnMetricsResolver);
    recalculateWorkbook();
  }

  /// fromBytes API.
  factory SheetEditorController.fromBytes(
    Uint8List bytes, {
    String? password,
    OfficeSurfaceConfig? config,
    SmlColumnMetricsResolver columnMetricsResolver = SheetFontMetrics.measure,
  }) {
    final SheetEditorController controller = SheetEditorController(
      config: config,
      columnMetricsResolver: columnMetricsResolver,
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
      onProgress: onProgress,
    );
    _acceptOpenedWorkbook(opened, recalculate: false);
  }

  void _acceptOpenedWorkbook(SmlWorkbook opened, {required bool recalculate}) {
    _cancelResize();
    cancelCellEdit();
    workbook = opened;
    workbook.resolveColumnMetrics(columnMetricsResolver);
    _activeSheet = 0;
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
      lastValidationError = _cellInputError(
        target,
        cell,
        cellEditor.formulaBar,
      );
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

  /// setActiveSheet API.
  void setActiveSheet(int index) {
    commitCellEdit();
    _activeSheet = index.clamp(0, workbook.sheets.length - 1);
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
    if (sheet.rightToLeft == value) {
      return;
    }
    sheet.rightToLeft = value;
    notifyListeners();
  }

  /// toggleSheetRightToLeft API.
  void toggleSheetRightToLeft() {
    setSheetRightToLeft(!sheet.rightToLeft);
  }

  /// hasFrozenPanes API.
  bool get hasFrozenPanes => sheet.freezeRows > 0 || sheet.freezeCols > 0;

  /// unfreezePanes API.
  void unfreezePanes() {
    if (!hasFrozenPanes) {
      return;
    }
    sheet.freezeRows = 0;
    sheet.freezeCols = 0;
    clampSheetViewport();
    notifyListeners();
  }

  /// Excel Freeze Panes: lock rows above and columns left of the selection.
  ///
  /// A full row freezes from that row (no columns). A full column freezes
  /// from that column (no rows). A cell freezes from its row and column.
  void freezePanesFromSelection() {
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
    sheet.freezeRows = rows.clamp(0, SmlWorksheet.excelRowCount - 1);
    sheet.freezeCols = cols.clamp(0, SmlWorksheet.excelColumnCount - 1);
    clampSheetViewport();
    notifyListeners();
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
    sheet.freezeRows = 1;
    sheet.freezeCols = 0;
    clampSheetViewport();
    notifyListeners();
  }

  /// freezeFirstColumn API.
  void freezeFirstColumn() {
    sheet.freezeRows = 0;
    sheet.freezeCols = 1;
    clampSheetViewport();
    notifyListeners();
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
    _mutateSheetGrid(() {
      if (range.isSingleCell) {
        sheet.toggleMergeAndCenter(range);
      } else {
        sheet.mergeAndCenter(range);
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
    _mutateSheetGrid(() => sheet.unmerge(selection.range));
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

  /// setSelectionFillRgb API.
  void setSelectionFillRgb(String rgb) {
    if (!config.allowsMutation) {
      return;
    }
    final String next = SmlStyleSheet.normalizeRgb(rgb);
    _mutateSheetGrid(() {
      for (final SmlCellRef ref in selection.range.cells) {
        if (sheet.isCovered(ref.col, ref.row)) {
          continue;
        }
        sheet.cell(ref).fillRgb = next;
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
    _mutateSheetGrid(() {
      for (final SmlCellRef ref in selection.range.cells) {
        if (sheet.isCovered(ref.col, ref.row)) {
          continue;
        }
        sheet.cell(ref).fontRgb = next;
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
    _mutateSheetGrid(() => sheet.insertRows(at, count));
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
    _mutateSheetGrid(() => sheet.insertCols(at, count));
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
    _mutateSheetGrid(() => sheet.deleteRows(at, count));
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
    _mutateSheetGrid(() => sheet.deleteCols(at, count));
    selection.selectCell(SmlCellRef(at.clamp(0, 16383), selection.focus.row));
    notifyListeners();
  }

  /// Function API.
  void _mutateSheetGrid(void Function() mutate) {
    final _SheetGridSnap snap = _SheetGridSnap.capture(sheet);
    commands.commit(
      _CallbackCommand(
        executeFn: () {
          mutate();
          recalculateWorkbook();
        },
        undoFn: () {
          snap.restore(sheet);
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
    final String? sheetName = hit.sheetName;
    if (sheetName != null) {
      for (int i = 0; i < workbook.sheets.length; i++) {
        if (workbook.sheets[i].name == sheetName) {
          setActiveSheet(i);
          break;
        }
      }
    }
    final String? a1 = hit.a1;
    if (a1 != null) {
      selection.selectCell(SmlCellRef.parse(a1));
      ensureCellVisible(SmlCellRef.parse(a1));
    }
    notifyListeners();
  }

  /// sortSelection API.
  void sortSelection({int? column, bool ascending = true}) {
    if (!config.allowsMutation) {
      return;
    }
    final SmlRange range = selection.range;
    SmlAnalysis.sort(sheet, range, <SmlSortKey>[
      SmlSortKey(column: column ?? range.minCol, ascending: ascending),
    ]);
    recalculateWorkbook();
    notifyListeners();
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
    String author = 'Quds Office',
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
        shape: PmlTransform(
          x: shape.transform.x + dxEmu,
          y: shape.transform.y + dyEmu,
          cx: shape.transform.cx,
          cy: shape.transform.cy,
          rot: shape.transform.rot,
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
            : PmlTransform(
                x: mate.transform.x + dx,
                y: mate.transform.y + dy,
                cx: mate.transform.cx,
                cy: mate.transform.cy,
                rot: mate.transform.rot,
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
    slide.notes = value;
    notifyListeners();
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
          before.rot != after.rot) {
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
      headingLevel: paragraph.properties.headingLevel,
      styleId: paragraph.properties.styleId,
      spacingBefore: paragraph.properties.spacingBefore,
      spacingAfter: paragraph.properties.spacingAfter,
      keepTogether: paragraph.properties.keepTogether,
      inlines: WordEditorController._cloneInlines(paragraph),
    );
  }

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
    required this.cells,
    required this.widths,
    required this.heights,
    required this.merges,
  });

  /// capture API.
  factory _SheetGridSnap.capture(SmlWorksheet sheet) {
    return _SheetGridSnap._(
      cells: <SmlCell>[
        for (final SmlCell cell in sheet.allCells)
          SmlCell(
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
          ),
      ],
      widths: sheet.captureColumns(),
      heights: Map<int, double>.from(sheet.rowHeights),
      merges: <SmlMerge>[
        for (final SmlMerge merge in sheet.merges) merge.copy(),
      ],
    );
  }

  /// cells API.
  final List<SmlCell> cells;

  /// widths API.
  final Map<int, SmlColumnSnapshot> widths;

  /// heights API.
  final Map<int, double> heights;

  /// merges API.
  final List<SmlMerge> merges;

  /// restore API.
  void restore(SmlWorksheet sheet) {
    sheet.rows.clear();
    for (final SmlCell cell in cells) {
      final SmlCell target = sheet.cell(cell.ref);
      target
        ..type = cell.type
        ..value = cell.value
        ..formula = cell.formula
        ..styleIndex = cell.styleIndex
        ..hasExplicitStyleIndex = cell.hasExplicitStyleIndex
        ..horizontalAlign = cell.horizontalAlign
        ..fillRgb = cell.fillRgb
        ..hasExplicitFillColorEdit = cell.hasExplicitFillColorEdit
        ..fontRgb = cell.fontRgb
        ..hasExplicitFontColorEdit = cell.hasExplicitFontColorEdit
        ..fontBold = cell.fontBold
        ..fontSize = cell.fontSize;
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
