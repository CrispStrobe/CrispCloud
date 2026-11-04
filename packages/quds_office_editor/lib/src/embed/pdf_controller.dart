import 'dart:ui' show Offset, Rect, Size, lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../core/command_pipeline.dart';
import '../core/virtual_viewport.dart';
import '../editor_pdf/pdf_find.dart';
import '../editor_pdf/pdf_page_layout.dart';
import '../editor_pdf/pdf_text_selection.dart';
import 'office_clipboard.dart';
import 'office_theme.dart';
import 'office_uri.dart';
import 'pdf_viewer_options.dart';

/// View / select controller for an opened PDF.
class PdfViewerController extends ChangeNotifier {
  /// PdfViewerController API.
  PdfViewerController({
    PdfFile? file,
    List<PdfDisplayList>? lists,
    this.config = const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.viewing,
    ),
  }) : _file = file,
       _lists = lists ?? file?.displayLists() ?? <PdfDisplayList>[];

  /// fromBytes API.
  factory PdfViewerController.fromBytes(
    Uint8List bytes, {
    String? password,
    OfficeSurfaceConfig config = const OfficeSurfaceConfig(
      mode: OfficeInteractionMode.viewing,
    ),
  }) {
    final PdfFile file = PdfFile.open(bytes, password: password);
    return PdfViewerController(
      file: file,
      lists: file.displayLists(),
      config: config,
    );
  }

  PdfFile? _file;
  List<PdfDisplayList> _lists;
  OfficeSurfaceConfig config;
  final VirtualViewport viewport = VirtualViewport();
  PdfTextSelection? selection;
  final List<PdfFindMark> findMarks = <PdfFindMark>[];
  var findIndex = -1;
  var pageIndex = 0;

  /// Host override for `http` / `https` / `mailto` link annots.
  /// When null, the platform opener is used.
  void Function(String uri)? onOpenUri;

  /// Optional load-failure sink (set by [QudsPdfViewer.onError]).
  void Function(Object error)? onError;

  /// Active viewer options. Updated by [QudsPdfViewer].
  PdfViewerOptions options = const PdfViewerOptions();

  /// Whether pages are stacked horizontally.
  bool get swipeHorizontal => options.swipeHorizontal;

  static const Duration _zoomAnimDuration = Duration(milliseconds: 200);
  var _zoomAnimating = false;
  var _zoomFrom = 1.0;
  var _zoomTo = 1.0;
  Offset _zoomOrigin0 = Offset.zero;
  Offset _zoomFocal = Offset.zero;
  Duration? _zoomStart;

  /// file API.
  PdfFile? get file => _file;

  /// lists API.
  List<PdfDisplayList> get lists => _lists;

  /// pageCount API.
  int get pageCount => _file?.pageCount ?? _lists.length;

  /// Apply [next] options: zoom clamps and optional default page.
  void applyOptions(PdfViewerOptions next, {bool jumpToDefaultPage = false}) {
    options = next;
    viewport.applyZoomLimits(min: next.minZoom, max: next.maxZoom);
    if (jumpToDefaultPage && pageCount > 0) {
      goToPage(next.defaultPage);
    }
    notifyListeners();
  }

  /// Fit the current page using [policy] against the live viewport extent.
  void applyFitPolicy(PdfFitPolicy policy) {
    final Size extent = viewport.extent;
    final double w = extent.width > 0 ? extent.width : 720;
    final double h = extent.height > 0 ? extent.height : 900;
    switch (policy) {
      case PdfFitPolicy.width:
        fitWidth(w);
      case PdfFitPolicy.page:
        fitPage(w, h);
      case PdfFitPolicy.height:
        fitHeight(h);
      case PdfFitPolicy.none:
        break;
    }
  }

  /// loadBytesAsync API.
  ///
  /// On failure the error is rethrown after [onLoadError] and [onError] run.
  Future<void> loadBytesAsync(
    Uint8List bytes, {
    String? password,
    void Function(OfficeOpenProgress progress)? onProgress,
    void Function(Object error)? onLoadError,
  }) async {
    try {
      final PdfOpenPayload payload = await OfficeIsolateOpen.pdf(
        bytes,
        password: password ?? options.password,
        onProgress: onProgress,
      );
      _file = payload.file;
      _lists = payload.lists;
      selection = null;
      _clearFind();
      pageIndex = options.defaultPage.clamp(0, mathMax(0, pageCount - 1));
      viewport.origin = Offset.zero;
      goToPage(pageIndex);
      notifyListeners();
    } catch (error) {
      onLoadError?.call(error);
      onError?.call(error);
      rethrow;
    }
  }

  /// goToPage API.
  ///
  /// [destY] / [destX] are top-left page offsets. The page start stays visible
  /// when they are omitted or already near the start edge.
  void goToPage(int index, {double? destY, double? destX}) {
    pageIndex = index.clamp(0, mathMax(0, pageCount - 1));
    if (swipeHorizontal) {
      var left = PdfPageLayout.stackStart(_lists, pageIndex, viewport.scale);
      if (destX != null && destX > 12) {
        left += destX * PdfPageLayout.viewScale(viewport.scale) - 36;
      }
      var top = viewport.origin.dy;
      if (destY != null && destY > 12) {
        top = destY * PdfPageLayout.viewScale(viewport.scale) - 36;
        if (top < 0) {
          top = 0;
        }
      }
      viewport.origin = Offset(left < 0 ? 0 : left, top);
    } else {
      var top = PdfPageLayout.stackTop(_lists, pageIndex, viewport.scale);
      if (destY != null && destY > 12) {
        top += destY * PdfPageLayout.viewScale(viewport.scale) - 36;
      }
      viewport.origin = Offset(viewport.origin.dx, top < 0 ? 0 : top);
    }
    if (viewport.extent.width > 0 && viewport.extent.height > 0) {
      viewport.clampTo(
        content: PdfPageLayout.contentSize(
          _lists,
          viewport.scale,
          horizontal: swipeHorizontal,
        ),
        view: viewport.extent,
      );
    }
    notifyListeners();
  }

  /// Keep [pageIndex] aligned with the visible stack (wheel / scrollbar).
  void adoptVisiblePage() {
    if (_lists.isEmpty) {
      return;
    }
    if (swipeHorizontal) {
      final double x =
          viewport.origin.dx +
          (viewport.extent.width > 0 ? viewport.extent.width * 0.35 : 0);
      pageIndex = PdfPageLayout.pageAtX(_lists, x, viewport.scale);
    } else {
      final double y =
          viewport.origin.dy +
          (viewport.extent.height > 0 ? viewport.extent.height * 0.35 : 0);
      pageIndex = PdfPageLayout.pageAtY(_lists, y, viewport.scale);
    }
  }

  /// Snap the viewport origin to the nearest page start edge.
  void snapToNearestPage() {
    if (_lists.isEmpty || !options.pageSnap) {
      return;
    }
    adoptVisiblePage();
    goToPage(pageIndex);
  }

  /// Canvas pan / wheel / pinch finished — keep chrome in sync.
  void viewportChanged() {
    adoptVisiblePage();
    notifyListeners();
  }

  /// setScale API. Zooms about [focal] (content space) or the view center.
  ///
  /// When [animate] is true (default), scale and origin ease over ~200ms so the
  /// last page raster stretches like an image instead of jumping.
  void setScale(double scale, {Offset? focal, bool animate = true}) {
    final Offset focus = focal ?? _viewCenter();
    final double old = viewport.scale;
    final double clamped = scale.clamp(viewport.clampMin, viewport.clampMax);
    final double pending = _zoomAnimating ? _zoomTo : old;
    if ((clamped - pending).abs() < 1e-9) {
      return;
    }
    if (!animate) {
      _stopZoomAnimation();
      _commitScale(clamped, focus: focus, from: old, origin0: viewport.origin);
      return;
    }
    _beginZoomAnimation(
      from: old,
      to: clamped,
      origin0: viewport.origin,
      focal: focus,
    );
  }

  /// Multiply the current scale (ribbon / shortcuts / ctrl+wheel).
  void zoomBy(double factor, {Offset? focal, bool animate = true}) {
    final double base = _zoomAnimating ? _zoomTo : viewport.scale;
    setScale(base * factor, focal: focal, animate: animate);
  }

  Offset _viewCenter() {
    final Size extent = viewport.extent;
    if (extent.width <= 0 || extent.height <= 0) {
      return viewport.origin;
    }
    return viewport.origin + Offset(extent.width / 2, extent.height / 2);
  }

  void _clampViewport() {
    final Size extent = viewport.extent;
    if (extent.width <= 0 || extent.height <= 0) {
      return;
    }
    viewport.clampTo(
      content: PdfPageLayout.contentSize(
        _lists,
        viewport.scale,
        horizontal: swipeHorizontal,
      ),
      view: extent,
    );
  }

  void _commitScale(
    double next, {
    required Offset focus,
    required double from,
    required Offset origin0,
  }) {
    viewport.setScale(next);
    viewport.origin = PdfPageLayout.originAfterScale(
      lists: _lists,
      origin: origin0,
      focal: focus,
      oldScale: from,
      nextScale: viewport.scale,
      horizontal: swipeHorizontal,
    );
    _clampViewport();
    notifyListeners();
  }

  void _beginZoomAnimation({
    required double from,
    required double to,
    required Offset origin0,
    required Offset focal,
  }) {
    if ((to - from).abs() < 1e-9) {
      return;
    }
    _zoomFrom = from;
    _zoomTo = to;
    _zoomOrigin0 = origin0;
    _zoomFocal = focal;
    _zoomStart = null;
    if (_zoomAnimating) {
      return;
    }
    _zoomAnimating = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onZoomFrame);
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _onZoomFrame(Duration timestamp) {
    if (!_zoomAnimating) {
      return;
    }
    final Duration start = _zoomStart ??= timestamp;
    final int elapsedMs = (timestamp - start).inMilliseconds.clamp(0, 1 << 30);
    final double t = (elapsedMs / _zoomAnimDuration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
    final double eased = Curves.easeOutCubic.transform(t);
    final double next = lerpDouble(_zoomFrom, _zoomTo, eased)!;
    viewport.scale = next;
    viewport.origin = PdfPageLayout.originAfterScale(
      lists: _lists,
      origin: _zoomOrigin0,
      focal: _zoomFocal,
      oldScale: _zoomFrom,
      nextScale: next,
      horizontal: swipeHorizontal,
    );
    _clampViewport();
    notifyListeners();
    if (t < 1) {
      SchedulerBinding.instance.scheduleFrameCallback(_onZoomFrame);
      return;
    }
    _zoomAnimating = false;
    viewport.setScale(_zoomTo);
    viewport.origin = PdfPageLayout.originAfterScale(
      lists: _lists,
      origin: _zoomOrigin0,
      focal: _zoomFocal,
      oldScale: _zoomFrom,
      nextScale: viewport.scale,
      horizontal: swipeHorizontal,
    );
    _clampViewport();
    notifyListeners();
  }

  void _stopZoomAnimation() {
    _zoomAnimating = false;
  }

  @override
  void dispose() {
    _stopZoomAnimation();
    super.dispose();
  }

  /// copySelection API.
  String copySelection() => selection?.plainText(_lists) ?? '';

  /// copyToClipboard API.
  Future<void> copyToClipboard() async {
    final String text = copySelection();
    if (text.isEmpty) {
      return;
    }
    await OfficeClipboard.instance.write(
      OfficeClipboardPayload.fromPlain(text),
    );
  }

  /// Search the opened display lists. Empty [query] clears the marks.
  List<PdfFindMark> find(String query) {
    if (query.trim().isEmpty) {
      _clearFind();
      notifyListeners();
      return const <PdfFindMark>[];
    }
    findMarks
      ..clear()
      ..addAll(PdfFind.search(_lists, query));
    findIndex = findMarks.isEmpty ? -1 : 0;
    _revealFind();
    notifyListeners();
    return findMarks;
  }

  /// Next match, wrapping. Reveals the hit.
  PdfFindMark? findNext() {
    if (findMarks.isEmpty) {
      return null;
    }
    findIndex = (findIndex + 1) % findMarks.length;
    _revealFind();
    notifyListeners();
    return findMarks[findIndex];
  }

  /// Previous match, wrapping. Reveals the hit.
  PdfFindMark? findPrevious() {
    if (findMarks.isEmpty) {
      return null;
    }
    findIndex = findIndex <= 0 ? findMarks.length - 1 : findIndex - 1;
    _revealFind();
    notifyListeners();
    return findMarks[findIndex];
  }

  void _clearFind() {
    findMarks.clear();
    findIndex = -1;
  }

  void _revealFind() {
    if (findIndex < 0 || findIndex >= findMarks.length) {
      return;
    }
    final PdfFindMark mark = findMarks[findIndex];
    final double? destY = mark.rects.isEmpty ? null : mark.rects.first.top;
    goToPage(mark.page, destY: destY);
  }

  /// Select every text run in the file.
  void selectAll() {
    if (_lists.isEmpty) {
      return;
    }
    var first = -1;
    var last = -1;
    for (int i = 0; i < _lists.length; i++) {
      if (_lists[i].runs.isNotEmpty) {
        first = i;
        break;
      }
    }
    for (int i = _lists.length - 1; i >= 0; i--) {
      if (_lists[i].runs.isNotEmpty) {
        last = i;
        break;
      }
    }
    if (first < 0 || last < 0) {
      selection = null;
      notifyListeners();
      return;
    }
    final List<PdfTextRun> end = _lists[last].runs;
    selection = PdfTextSelection(
      anchor: PdfTextHit(page: first, run: 0, offset: 0),
      extent: PdfTextHit(
        page: last,
        run: end.length - 1,
        offset: end.last.text.length,
      ),
    );
    notifyListeners();
  }

  /// Select every text run on [index].
  void selectPage(int index) {
    if (index < 0 || index >= _lists.length) {
      return;
    }
    final List<PdfTextRun> runs = _lists[index].runs;
    if (runs.isEmpty) {
      return;
    }
    selection = PdfTextSelection(
      anchor: PdfTextHit(page: index, run: 0, offset: 0),
      extent: PdfTextHit(
        page: index,
        run: runs.length - 1,
        offset: runs.last.text.length,
      ),
    );
    goToPage(index);
  }

  /// selectRun API.
  void selectRun(int page, PdfTextRun run) {
    final int index = page < 0 || page >= _lists.length
        ? 0
        : _runIndex(_lists[page], run);
    setSelection(PdfTextSelection.run(page, index, run));
  }

  /// setSelection API.
  void setSelection(PdfTextSelection? range) {
    selection = range;
    if (range != null) {
      pageIndex = range.normalized.extent.page.clamp(
        0,
        mathMax(0, pageCount - 1),
      );
    }
    notifyListeners();
  }

  static int _runIndex(PdfDisplayList list, PdfTextRun run) {
    for (int i = 0; i < list.runs.length; i++) {
      final PdfTextRun item = list.runs[i];
      if (identical(item, run) ||
          (item.x == run.x && item.y == run.y && item.text == run.text)) {
        return i;
      }
    }
    return 0;
  }

  /// followLink API.
  void followLink(PdfLinkAction action) {
    final int? page = action.pageIndex;
    if (page != null) {
      goToPage(page, destY: _topFromPdfY(action.destY, page));
    }
    final String? uri = action.uri;
    if (uri == null || !launchableUri(uri)) {
      return;
    }
    if (options.preventLinkNavigation) {
      return;
    }
    final void Function(String uri)? host = onOpenUri;
    if (host != null) {
      host(uri);
    } else {
      openExternalUri(uri);
    }
  }

  /// PDF `/XYZ` y is bottom-left. Null when the target is already the page top.
  double? _topFromPdfY(double? pdfY, int page) {
    if (pdfY == null || pdfY <= 0 || page < 0 || page >= _lists.length) {
      return null;
    }
    final double height = _lists[page].page.height;
    if (pdfY >= height - 1) {
      return 0;
    }
    return height - pdfY;
  }

  /// stats API.
  OfficeTextStats stats() {
    final PdfFile? file = _file;
    if (file == null) {
      return const OfficeTextStats();
    }
    return OfficeTextStats.ofPdf(file);
  }

  /// fitWidth API.
  void fitWidth(double viewportWidth) {
    final PdfFile? file = _file;
    if (file == null || file.pageCount == 0 || viewportWidth <= 0) {
      return;
    }
    final double usable =
        viewportWidth - PdfPageLayout.gutter * 2 - PdfPageLayout.scrollBar;
    if (usable <= 0) {
      return;
    }
    setScale(
      usable / file.pageAt(pageIndex).width / PdfPageLayout.pointsToPixels,
    );
  }

  /// Fit the current page to the live canvas width.
  void fitVisibleWidth() {
    final double width = viewport.extent.width;
    fitWidth(width > 0 ? width : 720);
  }

  /// fitPage API.
  void fitPage(double viewportWidth, double viewportHeight) {
    final PdfFile? file = _file;
    if (file == null || file.pageCount == 0) {
      return;
    }
    final PdfPageInfo page = file.pageAt(pageIndex);
    final double sx =
        (viewportWidth - PdfPageLayout.gutter * 2 - PdfPageLayout.scrollBar) /
        page.width;
    final double sy = (viewportHeight - PdfPageLayout.gap * 2) / page.height;
    setScale((sx < sy ? sx : sy) / PdfPageLayout.pointsToPixels);
  }

  /// Scale so the page height fills [viewportHeight].
  void fitHeight(double viewportHeight) {
    final PdfFile? file = _file;
    if (file == null || file.pageCount == 0 || viewportHeight <= 0) {
      return;
    }
    final double usable = viewportHeight - PdfPageLayout.gap * 2;
    if (usable <= 0) {
      return;
    }
    setScale(
      usable / file.pageAt(pageIndex).height / PdfPageLayout.pointsToPixels,
    );
  }

  /// isDirty API.
  bool get isDirty => _file?.isDirty ?? false;

  int mathMax(int a, int b) => a > b ? a : b;
}

/// Editing controller: annotations, forms, incremental save.
class PdfEditorController extends PdfViewerController {
  /// PdfEditorController API.
  PdfEditorController({
    super.file,
    super.lists,
    super.config = const OfficeSurfaceConfig(),
  });

  /// fromBytes API.
  factory PdfEditorController.fromBytes(
    Uint8List bytes, {
    String? password,
    OfficeSurfaceConfig config = const OfficeSurfaceConfig(),
  }) {
    final PdfFile file = PdfFile.open(bytes, password: password);
    return PdfEditorController(
      file: file,
      lists: file.displayLists(),
      config: config,
    );
  }

  final CommandPipeline commands = CommandPipeline();

  /// canUndo API.
  bool get canUndo => commands.canUndo;

  /// canRedo API.
  bool get canRedo => commands.canRedo;

  /// highlightSelection API.
  void highlightSelection({int color = 0x66FFE066}) {
    markSelection('Highlight', color: color);
  }

  /// Markup the current selection (`Highlight`, `StrikeOut`, `Underline`).
  void markSelection(String subtype, {int color = 0x66FFE066}) {
    final PdfFile? file = _file;
    final PdfTextSelection? range = selection;
    if (file == null ||
        range == null ||
        range.isCollapsed ||
        !config.allowsMutation) {
      return;
    }
    if (file.permissions != null && !file.permissions!.canAnnotate) {
      return;
    }
    final List<({int page, Rect rect})> boxes = range.boxes(_lists);
    if (boxes.isEmpty) {
      return;
    }
    for (final ({int page, Rect rect}) item in boxes) {
      final Rect box = item.rect;
      commands.commit(
        _PdfAnnotCommand(
          file,
          item.page,
          PdfAnnot(
            id: 0,
            subtype: subtype,
            rect: PdfRect(
              x: box.left,
              y: box.top,
              width: box.width,
              height: box.height,
            ),
            quads: <PdfQuad>[
              PdfQuad(
                x1: box.left,
                y1: box.top,
                x2: box.right,
                y2: box.top,
                x3: box.right,
                y3: box.bottom,
                x4: box.left,
                y4: box.bottom,
              ),
            ],
            color: color,
          ),
        ),
      );
    }
    notifyListeners();
  }

  /// addNote API.
  void addNote(PdfRect rect, String text) {
    final PdfFile? file = _file;
    if (file == null || !config.allowsMutation) {
      return;
    }
    commands.commit(
      _PdfAnnotCommand(
        file,
        pageIndex,
        PdfAnnot(id: 0, subtype: 'Text', rect: rect, contents: text),
      ),
    );
    notifyListeners();
  }

  /// addInk API.
  void addInk(List<PdfPoint> points) {
    final PdfFile? file = _file;
    if (file == null || points.length < 2 || !config.allowsMutation) {
      return;
    }
    var minX = points.first.x, minY = points.first.y, maxX = minX, maxY = minY;
    for (final PdfPoint p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    commands.commit(
      _PdfAnnotCommand(
        file,
        pageIndex,
        PdfAnnot(
          id: 0,
          subtype: 'Ink',
          rect: PdfRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY,
          ),
          ink: <List<PdfPoint>>[points],
        ),
      ),
    );
    notifyListeners();
  }

  /// Toggle an optional-content group and rebuild display lists.
  void setLayerVisible(int objectId, bool visible) {
    _file?.setLayerVisible(objectId, visible);
    _lists = _file?.displayLists() ?? _lists;
    notifyListeners();
  }

  /// setFieldValue API.
  void setFieldValue(String name, String value) {
    final PdfFormField? field = _file?.form.field(name);
    if (field == null || field.readOnly || !config.allowsMutation) {
      return;
    }
    field.value = value;
    _file?.form.needAppearances = true;
    _file?.markDirty(field.pageIndex);
    notifyListeners();
  }

  /// deletePage API.
  void deletePageAt(int index) {
    _file?.deletePage(index);
    _lists = _file?.displayLists() ?? _lists;
    notifyListeners();
  }

  /// insertBlankPage API.
  void insertBlankPage(int index) {
    _file?.insertBlankPage(index);
    _lists = _file?.displayLists() ?? _lists;
    notifyListeners();
  }

  /// rotatePage API.
  void rotateCurrentPage(int degrees) => rotatePageAt(pageIndex, degrees);

  /// Rotate [index] by [degrees] and rebuild the display lists.
  void rotatePageAt(int index, int degrees) {
    _file?.rotatePage(index, degrees);
    _lists = _file?.displayLists() ?? _lists;
    notifyListeners();
  }

  /// Remove a markup annotation, undoable.
  void deleteAnnot(int page, PdfAnnot annot) {
    final PdfFile? file = _file;
    if (file == null || !config.allowsMutation) {
      return;
    }
    if (file.permissions != null && !file.permissions!.canAnnotate) {
      return;
    }
    commands.commit(_PdfRemoveAnnotCommand(file, page, annot));
    notifyListeners();
  }

  /// mergeFrom API.
  void mergeFrom(PdfFile other) {
    _file?.appendPages(other);
    _lists = _file?.displayLists() ?? _lists;
    notifyListeners();
  }

  /// extractPages API.
  Uint8List? extractPages(List<int> indices) => _file?.extractPages(indices);

  /// exportXfdf API.
  String exportXfdf() {
    final PdfFile? file = _file;
    if (file == null) {
      return '';
    }
    return PdfXfdf.exportXml(file);
  }

  /// importXfdf API.
  void importXfdf(String xml) {
    final PdfFile? file = _file;
    if (file == null || !config.allowsMutation) {
      return;
    }
    PdfXfdf.importXml(file, xml);
    _lists = file.displayLists();
    notifyListeners();
  }

  /// redactSelection API.
  void redactSelection({PdfRedactMode mode = PdfRedactMode.visual}) {
    final PdfFile? file = _file;
    final PdfTextSelection? range = selection;
    if (file == null ||
        range == null ||
        range.isCollapsed ||
        !config.allowsMutation) {
      return;
    }
    for (final ({int page, Rect rect}) item in range.boxes(_lists)) {
      file.redactRect(
        item.page,
        PdfRect(
          x: item.rect.left,
          y: item.rect.top,
          width: item.rect.width,
          height: item.rect.height,
        ),
        mode: mode,
      );
    }
    notifyListeners();
  }

  /// saveBytes API.
  Uint8List saveBytes() {
    final PdfFile? file = _file;
    if (file == null) {
      return Uint8List(0);
    }
    return PdfIncrementalSave.write(
      originalBytes: file.originalBytes,
      file: file,
    );
  }

  /// undo API.
  void undo() {
    if (commands.canUndo) {
      commands.undo();
      notifyListeners();
    }
  }

  /// redo API.
  void redo() {
    if (commands.canRedo) {
      commands.redo();
      notifyListeners();
    }
  }
}

class _PdfRemoveAnnotCommand implements OfficeCommand {
  _PdfRemoveAnnotCommand(this.file, this.page, this.annot);

  final PdfFile file;
  final int page;
  final PdfAnnot annot;

  @override
  void execute() {
    file.removeAnnot(page, annot.id);
  }

  @override
  void undo() {
    file.addAnnot(page, annot);
  }

  @override
  OfficeCommand invert() => this;
}

class _PdfAnnotCommand implements OfficeCommand {
  _PdfAnnotCommand(this.file, this.page, this.annot);

  final PdfFile file;
  final int page;
  final PdfAnnot annot;
  int? _id;

  @override
  void execute() {
    final PdfAnnot created = file.addAnnot(page, annot);
    _id = created.id;
  }

  @override
  void undo() {
    final int? id = _id;
    if (id != null) {
      file.removeAnnot(page, id);
    }
  }

  @override
  OfficeCommand invert() => this;
}
