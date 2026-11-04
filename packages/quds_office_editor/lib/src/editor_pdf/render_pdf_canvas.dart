import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/pdf_file.dart';

import '../core/virtual_viewport.dart';
import '../embed/office_context_menu.dart';
import '../embed/office_theme.dart';
import 'paint_pdf_display_list.dart';
import 'pdf_font_faces.dart';
import 'pdf_find.dart';
import 'pdf_page_layout.dart';
import 'pdf_page_rotation.dart';
import 'pdf_raster.dart';
import 'pdf_text_selection.dart';

/// Leaf canvas for PDF pages.
class PdfCanvasView extends LeafRenderObjectWidget {
  /// PdfCanvasView API.
  const PdfCanvasView({
    super.key,
    required this.lists,
    required this.viewport,
    required this.scale,
    required this.config,
    this.selection,
    this.findMarks = const <PdfFindMark>[],
    this.findIndex = -1,
    this.annots = const <List<PdfAnnot>>[],
    this.editing = false,
    this.enableSwipe = true,
    this.swipeHorizontal = false,
    this.pageFling = true,
    this.pageSnap = false,
    this.showScrollIndicators = true,
    this.nightMode = false,
    this.backgroundColor,
    this.onChanged,
    this.onZoomBy,
    this.onFollowLink,
    this.onSelectText,
    this.onAnnotTap,
    this.onContextMenu,
    this.onRender,
    this.onPageError,
    this.onDraw,
    this.onGestureSettled,
  });

  /// lists API.
  final List<PdfDisplayList> lists;

  /// viewport API.
  final VirtualViewport viewport;

  /// Logical zoom (1 = 100%). Passed explicitly so the RenderBox dirties.
  final double scale;

  /// config API.
  final OfficeSurfaceConfig config;

  /// selection API.
  final PdfTextSelection? selection;

  /// findMarks API.
  final List<PdfFindMark> findMarks;

  /// Active search hit, or -1.
  final int findIndex;

  /// annots API.
  final List<List<PdfAnnot>> annots;

  /// editing API.
  final bool editing;

  /// When false, pan and wheel scroll are ignored (Ctrl+zoom still works).
  final bool enableSwipe;

  /// Stack pages left-to-right.
  final bool swipeHorizontal;

  /// Keep scroll momentum after pointer-up.
  final bool pageFling;

  /// Align to nearest page when a gesture settles.
  final bool pageSnap;

  /// Show the overlay scrollbar.
  final bool showScrollIndicators;

  /// Invert page rasters for dark reading.
  final bool nightMode;

  /// Canvas chrome behind the paper.
  final Color? backgroundColor;

  /// onChanged API.
  final VoidCallback? onChanged;

  /// Ctrl/meta+wheel zoom — [factor] and content-space [focal].
  /// Pass [animate]: false for continuous pinch updates.
  final void Function(double factor, Offset focal, {bool animate})? onZoomBy;

  /// onFollowLink API.
  final void Function(PdfLinkAction action)? onFollowLink;

  /// onSelectText API.
  final void Function(PdfTextSelection? range)? onSelectText;

  /// onAnnotTap API.
  final void Function(int page, PdfAnnot annot)? onAnnotTap;

  /// Right-click on a page or the canvas gutter.
  final void Function(PdfContextHit hit)? onContextMenu;

  /// Fired when a page raster finishes.
  final void Function(int page)? onRender;

  /// Fired when a page raster fails.
  final void Function(int page, Object error)? onPageError;

  /// Optional host overlay after a page is painted.
  final void Function(Canvas canvas, Size size, int page)? onDraw;

  /// Fired after pan/fling settles (for page snap).
  final VoidCallback? onGestureSettled;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderPdfCanvas(
      lists: lists,
      viewport: viewport,
      scale: scale,
      config: config,
      selection: selection,
      findMarks: findMarks,
      findIndex: findIndex,
      annots: annots,
      editing: editing,
      enableSwipe: enableSwipe,
      swipeHorizontal: swipeHorizontal,
      pageFling: pageFling,
      pageSnap: pageSnap,
      showScrollIndicators: showScrollIndicators,
      nightMode: nightMode,
      backgroundColor: backgroundColor,
      onChanged: onChanged,
      onZoomBy: onZoomBy,
      onFollowLink: onFollowLink,
      onSelectText: onSelectText,
      onAnnotTap: onAnnotTap,
      onContextMenu: onContextMenu,
      onRender: onRender,
      onPageError: onPageError,
      onDraw: onDraw,
      onGestureSettled: onGestureSettled,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPdfCanvas renderObject) {
    renderObject
      ..lists = lists
      ..viewport = viewport
      ..scale = scale
      ..config = config
      ..selection = selection
      ..findMarks = findMarks
      ..findIndex = findIndex
      ..annots = annots
      ..editing = editing
      ..enableSwipe = enableSwipe
      ..swipeHorizontal = swipeHorizontal
      ..pageFling = pageFling
      ..pageSnap = pageSnap
      ..showScrollIndicators = showScrollIndicators
      ..nightMode = nightMode
      ..backgroundColor = backgroundColor
      ..onChanged = onChanged
      ..onZoomBy = onZoomBy
      ..onFollowLink = onFollowLink
      ..onSelectText = onSelectText
      ..onAnnotTap = onAnnotTap
      ..onContextMenu = onContextMenu
      ..onRender = onRender
      ..onPageError = onPageError
      ..onDraw = onDraw
      ..onGestureSettled = onGestureSettled;
    renderObject.markNeedsPaint();
  }
}

/// Class RenderPdfCanvas.
class RenderPdfCanvas extends RenderBox implements MouseTrackerAnnotation {
  /// RenderPdfCanvas API.
  RenderPdfCanvas({
    required this._lists,
    required this._viewport,
    required this._scale,
    required this._config,
    this._selection,
    this.findMarks = const <PdfFindMark>[],
    this.findIndex = -1,
    this.annots = const <List<PdfAnnot>>[],
    this.editing = false,
    this.enableSwipe = true,
    this.swipeHorizontal = false,
    this.pageFling = true,
    this.pageSnap = false,
    this.showScrollIndicators = true,
    this.nightMode = false,
    this.backgroundColor,
    this.onChanged,
    this.onZoomBy,
    this.onFollowLink,
    this.onSelectText,
    this.onAnnotTap,
    this.onContextMenu,
    this.onRender,
    this.onPageError,
    this.onDraw,
    this.onGestureSettled,
  });

  List<PdfDisplayList> _lists;
  VirtualViewport _viewport;
  double _scale;
  OfficeSurfaceConfig _config;

  PdfTextSelection? _selection;

  /// selection API.
  PdfTextSelection? get selection => _selection;

  set selection(PdfTextSelection? value) {
    _selection = value;
    if (!_selecting) {
      _live = null;
      _anchor = null;
    }
    markNeedsPaint();
  }

  /// findMarks API.
  List<PdfFindMark> findMarks;

  /// Active search hit, or -1.
  int findIndex;

  /// annots API.
  List<List<PdfAnnot>> annots;

  /// editing API.
  bool editing;

  /// When false, pan and wheel scroll are ignored (Ctrl+zoom still works).
  bool enableSwipe;

  /// Stack pages left-to-right.
  bool swipeHorizontal;

  /// Keep scroll momentum after pointer-up.
  bool pageFling;

  /// Align to nearest page when a gesture settles.
  bool pageSnap;

  /// Show the overlay scrollbar.
  bool showScrollIndicators;

  /// Invert page rasters for dark reading.
  bool nightMode;

  /// Canvas chrome behind the paper.
  Color? backgroundColor;

  /// onChanged API.
  VoidCallback? onChanged;

  /// Ctrl/meta+wheel zoom — [factor] and content-space [focal].
  /// Pass [animate]: false for continuous pinch updates.
  void Function(double factor, Offset focal, {bool animate})? onZoomBy;

  /// onFollowLink API.
  void Function(PdfLinkAction action)? onFollowLink;

  /// onSelectText API.
  void Function(PdfTextSelection? range)? onSelectText;

  /// onAnnotTap API.
  void Function(int page, PdfAnnot annot)? onAnnotTap;

  /// onContextMenu API.
  void Function(PdfContextHit hit)? onContextMenu;

  /// Fired when a page raster finishes.
  void Function(int page)? onRender;

  /// Fired when a page raster fails.
  void Function(int page, Object error)? onPageError;

  /// Optional host overlay after a page is painted.
  void Function(Canvas canvas, Size size, int page)? onDraw;

  /// Fired after pan/fling settles (for page snap).
  VoidCallback? onGestureSettled;

  final Map<int, ui.Image> _images = <int, ui.Image>{};
  final Set<int> _decoding = <int>{};
  final Map<int, _PageTile> _tiles = <int, _PageTile>{};
  final Set<int> _rasterizing = <int>{};
  Timer? _zoomSettle;
  var _previewZoom = false;
  var _tileEpoch = 0;
  PanGestureRecognizer? _pan;
  var _scrollDrag = false;
  int? _scrollPageTip;
  Offset? _hoverLocal;
  var _selecting = false;
  PdfTextSelection? _live;
  PdfTextHit? _anchor;
  Offset? _downLocal;
  DateTime? _downAt;
  var _clickCount = 0;
  PdfLinkAction? _pendingLink;

  /// Destination page shown in the desktop hover card, or null.
  int? _previewPage;
  var _panZoomScale = 1.0;
  Offset _flingVelocity = Offset.zero;
  var _flinging = false;

  double get _viewScale => PdfPageLayout.viewScale(_viewport.scale);

  Size get _contentSize => PdfPageLayout.contentSize(
    _lists,
    _viewport.scale,
    horizontal: swipeHorizontal,
  );

  double get _maxScrollY => math.max(0, _contentSize.height - size.height);

  double get _maxScrollX => math.max(0, _contentSize.width - size.width);

  bool get _scrollBarVisible =>
      showScrollIndicators &&
      (swipeHorizontal ? _maxScrollX > 0 : _maxScrollY > 0);

  Rect get _vTrack {
    if (swipeHorizontal) {
      return Rect.fromLTWH(
        0,
        size.height - PdfPageLayout.scrollBar,
        size.width,
        PdfPageLayout.scrollBar,
      );
    }
    return Rect.fromLTWH(
      size.width - PdfPageLayout.scrollBar,
      0,
      PdfPageLayout.scrollBar,
      size.height,
    );
  }

  /// lists API.
  set lists(List<PdfDisplayList> value) {
    if (identical(_lists, value)) {
      return;
    }
    _lists = value;
    _images.clear();
    _decoding.clear();
    _clearTiles();
    _live = null;
    _anchor = null;
    _selecting = false;
    markNeedsLayout();
    markNeedsPaint();
  }

  /// viewport API.
  set viewport(VirtualViewport value) {
    final bool scaleChanged =
        !identical(_viewport, value) ||
        _scale != value.scale ||
        _viewport.scale != value.scale;
    _viewport = value;
    _scale = value.scale;
    if (scaleChanged) {
      _noteZoomInteraction();
      markNeedsLayout();
    }
    markNeedsPaint();
  }

  /// scale API.
  set scale(double value) {
    if (_scale == value && _viewport.scale == value) {
      return;
    }
    final bool zoomed = (_scale - value).abs() > 1e-9;
    _scale = value;
    if (_viewport.scale != value) {
      _viewport.setScale(value);
    }
    if (zoomed) {
      _noteZoomInteraction();
    }
    markNeedsLayout();
    markNeedsPaint();
  }

  /// config API.
  set config(OfficeSurfaceConfig value) {
    _config = value;
    markNeedsPaint();
  }

  @override
  bool hitTestSelf(Offset position) {
    _hoverLocal = position;
    _syncLinkPreview();
    return true;
  }

  @override
  MouseCursor get cursor => _cursorFor(_hoverLocal);

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => (_) {
    _hoverLocal = null;
    if (_previewPage != null) {
      _previewPage = null;
      markNeedsPaint();
    }
  };

  @override
  bool get validForMouseTracker => attached;

  bool get _canSelect =>
      _config.allowsSelection || _config.mode == OfficeInteractionMode.viewing;

  MouseCursor _cursorFor(Offset? local) {
    if (local == null) {
      return SystemMouseCursors.basic;
    }
    if (_scrollBarVisible && _vTrack.contains(local)) {
      return SystemMouseCursors.grab;
    }
    if (_selecting) {
      return SystemMouseCursors.text;
    }
    final _PageHit? page = _pageHit(local);
    if (page == null) {
      return SystemMouseCursors.basic;
    }
    if (_hotspotAt(page) != null) {
      return SystemMouseCursors.click;
    }
    if (_canSelect && _textHit(page) != null) {
      return SystemMouseCursors.text;
    }
    return SystemMouseCursors.basic;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ensureRecognizers();
  }

  @override
  void detach() {
    _zoomSettle?.cancel();
    _zoomSettle = null;
    _flinging = false;
    _pan?.dispose();
    _pan = null;
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.hasBoundedWidth && constraints.hasBoundedHeight
        ? constraints.biggest
        : constraints.constrain(_contentSize);
    if (!size.width.isFinite || !size.height.isFinite) {
      size = constraints.constrain(const Size(800, 600));
    }
    _viewport.extent = size;
    _viewport.clampTo(content: _contentSize, view: size);
  }

  double _pageLeft(PdfDisplayList list) {
    if (swipeHorizontal) {
      return 0;
    }
    final double pageW = list.page.width * _viewScale;
    final double viewW = math.max(
      0,
      size.width - (showScrollIndicators ? PdfPageLayout.scrollBar : 0),
    );
    if (viewW > pageW + PdfPageLayout.gutter * 2) {
      return (viewW - pageW) / 2;
    }
    return PdfPageLayout.gutter;
  }

  double _pageTop(PdfDisplayList list) {
    if (!swipeHorizontal) {
      return 0;
    }
    final double pageH = list.page.height * _viewScale;
    final double viewH = math.max(
      0,
      size.height - (showScrollIndicators ? PdfPageLayout.scrollBar : 0),
    );
    if (viewH > pageH + PdfPageLayout.gap * 2) {
      return (viewH - pageH) / 2;
    }
    return PdfPageLayout.gap;
  }

  Rect get _vThumb {
    if (swipeHorizontal) {
      final double maxX = _maxScrollX;
      final double trackW = _vTrack.width;
      final double thumbW =
          (_contentSize.width <= 0
                  ? 22.0
                  : trackW *
                        (size.width / math.max(size.width, _contentSize.width)))
              .clamp(22.0, trackW);
      final double x = maxX <= 0
          ? 0
          : (trackW - thumbW) * (_viewport.origin.dx / maxX);
      return Rect.fromLTWH(x, _vTrack.top + 2, thumbW, _vTrack.height - 4);
    }
    final double maxY = _maxScrollY;
    final double trackH = _vTrack.height;
    final double thumbH =
        (_contentSize.height <= 0
                ? 22.0
                : trackH *
                      (size.height /
                          math.max(size.height, _contentSize.height)))
            .clamp(22.0, trackH);
    final double y = maxY <= 0
        ? 0
        : (trackH - thumbH) * (_viewport.origin.dy / maxY);
    return Rect.fromLTWH(_vTrack.left + 2, y, _vTrack.width - 4, thumbH);
  }

  void _ensureRecognizers() {
    _pan ??= PanGestureRecognizer(debugOwner: this)
      ..onUpdate = (DragUpdateDetails details) {
        _stopFling();
        if (_scrollDrag) {
          _dragScroll(details.delta);
          return;
        }
        if (_selecting) {
          _extendSelection(details.localPosition);
          return;
        }
        if (!enableSwipe) {
          return;
        }
        _viewport.pan(-details.delta);
        _finishScroll(settle: false);
      }
      ..onEnd = (DragEndDetails details) {
        if (_selecting) {
          _finishSelect();
        }
        _scrollDrag = false;
        _scrollPageTip = null;
        markNeedsPaint();
        if (!enableSwipe) {
          onChanged?.call();
          return;
        }
        final Offset velocity = details.velocity.pixelsPerSecond;
        if (pageFling && velocity.distance > 80) {
          _startFling(-velocity);
        } else {
          _settleGesture();
        }
      };
  }

  void _startFling(Offset velocity) {
    _flingVelocity = velocity;
    if (_flinging) {
      return;
    }
    _flinging = true;
    SchedulerBinding.instance.scheduleFrameCallback(_onFlingFrame);
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _stopFling() {
    _flinging = false;
    _flingVelocity = Offset.zero;
  }

  void _onFlingFrame(Duration _) {
    if (!_flinging || !attached) {
      return;
    }
    final Offset step = _flingVelocity * (1 / 60);
    _viewport.pan(step);
    _flingVelocity *= 0.92;
    _finishScroll(settle: false);
    if (_flingVelocity.distance < 24) {
      _stopFling();
      _settleGesture();
      return;
    }
    SchedulerBinding.instance.scheduleFrameCallback(_onFlingFrame);
  }

  void _settleGesture() {
    _finishScroll(settle: true);
    if (pageSnap) {
      onGestureSettled?.call();
    }
  }

  void _zoomBy(double factor, Offset local) {
    final double old = _viewport.scale;
    if (old <= 0 || factor <= 0) {
      return;
    }
    _viewport.setScale(old * factor);
    final double next = _viewport.scale;
    if ((next - old).abs() < 1e-9) {
      return;
    }
    _scale = next;
    _viewport.origin = PdfPageLayout.originAfterScale(
      lists: _lists,
      origin: _viewport.origin,
      focal: _viewport.origin + local,
      oldScale: old,
      nextScale: next,
      horizontal: swipeHorizontal,
    );
    _noteZoomInteraction();
  }

  /// Stretch the last page rasters while zooming; rebuild after the gesture settles.
  void _noteZoomInteraction() {
    _previewZoom = true;
    _zoomSettle?.cancel();
    _zoomSettle = Timer(const Duration(milliseconds: 220), () {
      if (!attached) {
        return;
      }
      _previewZoom = false;
      _tileEpoch++;
      markNeedsPaint();
    });
  }

  void _clearTiles() {
    _zoomSettle?.cancel();
    _zoomSettle = null;
    _previewZoom = false;
    _tileEpoch++;
    for (final _PageTile tile in _tiles.values) {
      tile.image?.dispose();
    }
    _tiles.clear();
    _rasterizing.clear();
  }

  bool _tileMatchesScale(_PageTile tile, double scale) {
    if (tile.image == null || tile.scale <= 0 || scale <= 0) {
      return false;
    }
    return (tile.scale - scale).abs() / scale < 0.03;
  }

  void _scheduleRaster(int pageIndex, double targetScale) {
    if (_previewZoom || pageIndex < 0 || pageIndex >= _lists.length) {
      return;
    }
    final _PageTile tile = _tiles.putIfAbsent(pageIndex, _PageTile.new);
    if (_tileMatchesScale(tile, targetScale) ||
        _rasterizing.contains(pageIndex)) {
      return;
    }
    _rasterizing.add(pageIndex);
    final int epoch = _tileEpoch;
    final PdfDisplayList list = _lists[pageIndex];
    _warmImages(list);
    _warmFonts(list);
    if (!PdfFontFaces.readyFor(
      list.ops,
      (Object op) => op is PdfDrawText ? op.fontBytes : null,
    )) {
      _rasterizing.remove(pageIndex);
      return;
    }
    final double dpr = _devicePixelRatio;
    () async {
      try {
        final ui.Image? image = await _rasterPage(list, targetScale, dpr);
        if (!attached || epoch != _tileEpoch || _previewZoom) {
          image?.dispose();
          _rasterizing.remove(pageIndex);
          return;
        }
        if ((_viewScale - targetScale).abs() / math.max(targetScale, 1e-6) >
            0.05) {
          image?.dispose();
          _rasterizing.remove(pageIndex);
          return;
        }
        final _PageTile next = _tiles.putIfAbsent(pageIndex, _PageTile.new);
        next.image?.dispose();
        next.image = image;
        next.scale = targetScale;
        _rasterizing.remove(pageIndex);
        markNeedsPaint();
        if (image != null) {
          onRender?.call(pageIndex);
        }
      } catch (error) {
        _rasterizing.remove(pageIndex);
        onPageError?.call(pageIndex, error);
      }
    }();
  }

  double get _devicePixelRatio {
    final ui.FlutterView? view = ui.PlatformDispatcher.instance.implicitView;
    if (view != null && view.devicePixelRatio > 0) {
      return view.devicePixelRatio.clamp(1.0, 3.0);
    }
    return 1.0;
  }

  Future<ui.Image?> _rasterPage(
    PdfDisplayList list,
    double viewScale,
    double dpr,
  ) async {
    if (viewScale <= 0 || list.page.width <= 0 || list.page.height <= 0) {
      return null;
    }
    var pixelScale = viewScale * dpr;
    var w = (list.page.width * pixelScale).ceil();
    var h = (list.page.height * pixelScale).ceil();
    const int maxEdge = 4096;
    if (w > maxEdge || h > maxEdge) {
      final double fit = maxEdge / math.max(w, h);
      pixelScale *= fit;
      w = (list.page.width * pixelScale).ceil();
      h = (list.page.height * pixelScale).ceil();
    }
    w = w.clamp(1, maxEdge);
    h = h.clamp(1, maxEdge);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.scale(pixelScale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, list.page.width, list.page.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.clipRect(Rect.fromLTWH(0, 0, list.page.width, list.page.height));
    canvas.save();
    applyPdfPageRotation(canvas, list.page);
    PaintPdfDisplayList.paint(
      canvas,
      list,
      decodeImage: (Uint8List bytes, bool _) =>
          _images[identityHashCode(bytes)],
    );
    canvas.restore();
    final ui.Picture picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
  }

  void _finishScroll({bool settle = true}) {
    _viewport.clampTo(content: _contentSize, view: size);
    if (swipeHorizontal) {
      _scrollPageTip = PdfPageLayout.pageAtX(
        _lists,
        _viewport.origin.dx + size.width * 0.35,
        _viewport.scale,
      );
    } else {
      _scrollPageTip = PdfPageLayout.pageAtY(
        _lists,
        _viewport.origin.dy + size.height * 0.35,
        _viewport.scale,
      );
    }
    markNeedsPaint();
    if (settle) {
      onChanged?.call();
    }
  }

  void _dragScroll(Offset delta) {
    if (!_scrollBarVisible) {
      return;
    }
    if (swipeHorizontal) {
      final double maxX = _maxScrollX;
      if (maxX <= 0 || _vTrack.width <= 0) {
        return;
      }
      _viewport.origin = Offset(
        _viewport.origin.dx + delta.dx * (maxX / _vTrack.width),
        _viewport.origin.dy,
      );
    } else {
      final double maxY = _maxScrollY;
      if (maxY <= 0 || _vTrack.height <= 0) {
        return;
      }
      _viewport.origin = Offset(
        _viewport.origin.dx,
        _viewport.origin.dy + delta.dy * (maxY / _vTrack.height),
      );
    }
    _finishScroll();
  }

  void _jumpScroll(Offset local) {
    if (!_scrollBarVisible) {
      return;
    }
    if (swipeHorizontal) {
      final double maxX = _maxScrollX;
      if (maxX <= 0 || _vTrack.width <= 0) {
        return;
      }
      final double t = (local.dx / _vTrack.width).clamp(0, 1);
      _viewport.origin = Offset(maxX * t, _viewport.origin.dy);
    } else {
      final double maxY = _maxScrollY;
      if (maxY <= 0 || _vTrack.height <= 0) {
        return;
      }
      final double t = (local.dy / _vTrack.height).clamp(0, 1);
      _viewport.origin = Offset(_viewport.origin.dx, maxY * t);
    }
    _finishScroll();
  }

  void _paintScrollBar(Canvas canvas, Offset offset) {
    if (!_scrollBarVisible) {
      return;
    }
    final Rect track = _vTrack.shift(offset);
    canvas.drawRect(track, Paint()..color = _config.theme.headerFill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(_vThumb.shift(offset), const Radius.circular(4)),
      Paint()..color = _config.theme.headerText.withValues(alpha: 0.45),
    );
    final int? tip = _scrollPageTip;
    if (tip == null || _lists.isEmpty) {
      return;
    }
    final String label = '${tip + 1} / ${_lists.length}';
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double tipW = painter.width + 16;
    final double tipH = painter.height + 10;
    final double tipX;
    final double tipY;
    if (swipeHorizontal) {
      tipX = (_vThumb.shift(offset).center.dx - tipW / 2).clamp(
        8,
        size.width - tipW - 8,
      );
      tipY = (track.top - tipH - 8).clamp(8, size.height - tipH - 8);
    } else {
      tipX = (track.left - tipW - 8).clamp(8, size.width - tipW - 8);
      tipY = (_vThumb.shift(offset).center.dy - tipH / 2).clamp(
        8,
        size.height - tipH - 8,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx + tipX, offset.dy + tipY, tipW, tipH),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xE62B2B2B),
    );
    painter.paint(canvas, Offset(offset.dx + tipX + 8, offset.dy + tipY + 5));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final Color chrome =
        backgroundColor ??
        (nightMode ? const Color(0xFF121212) : _config.theme.canvasBackground);
    canvas.drawRect(offset & size, Paint()..color = chrome);
    canvas.save();
    canvas.clipRect(offset & size);
    canvas.translate(
      offset.dx - _viewport.origin.dx,
      offset.dy - _viewport.origin.dy,
    );
    final Rect view = Rect.fromLTWH(
      _viewport.origin.dx,
      _viewport.origin.dy,
      size.width,
      size.height,
    ).inflate(96);
    final double scale = _viewScale;
    var cursor = swipeHorizontal ? PdfPageLayout.gutter : PdfPageLayout.gap;
    for (int i = 0; i < _lists.length; i++) {
      final PdfDisplayList list = _lists[i];
      final double w = list.page.width * scale;
      final double h = list.page.height * scale;
      final double left = swipeHorizontal ? cursor : _pageLeft(list);
      final double top = swipeHorizontal ? _pageTop(list) : cursor;
      final Rect paper = Rect.fromLTWH(left, top, w, h);
      if (!view.overlaps(paper)) {
        cursor += (swipeHorizontal ? w : h) + PdfPageLayout.gap;
        continue;
      }
      _warmImages(list);
      _warmFonts(list);
      canvas.drawShadow(
        Path()..addRect(paper.inflate(1)),
        const Color(0x44000000),
        8,
        false,
      );
      canvas.drawRect(
        paper,
        Paint()
          ..color = nightMode
              ? const Color(0xFF1E1E1E)
              : _config.theme.pageBackground,
      );
      canvas.drawRect(
        paper,
        Paint()
          ..color = _config.theme.pageBorder
          ..style = PaintingStyle.stroke,
      );
      canvas.save();
      canvas.translate(left, top);
      canvas.scale(scale);
      canvas.clipRect(Rect.fromLTWH(0, 0, list.page.width, list.page.height));
      final _PageTile? tile = _tiles[i];
      final ui.Image? cached = tile?.image;
      final bool scaleMatch = tile != null && _tileMatchesScale(tile, scale);
      if (cached != null) {
        if (nightMode && !editing) {
          canvas.saveLayer(
            Rect.fromLTWH(0, 0, list.page.width, list.page.height),
            Paint()
              ..colorFilter = const ColorFilter.matrix(<double>[
                -1, 0, 0, 0, 255, //
                0, -1, 0, 0, 255, //
                0, 0, -1, 0, 255, //
                0, 0, 0, 1, 0,
              ]),
          );
        }
        paintImage(
          canvas: canvas,
          rect: Rect.fromLTWH(0, 0, list.page.width, list.page.height),
          image: cached,
          fit: BoxFit.fill,
          filterQuality: _previewZoom
              ? FilterQuality.medium
              : FilterQuality.high,
        );
        if (nightMode && !editing) {
          canvas.restore();
        }
      } else {
        if (nightMode && !editing) {
          canvas.saveLayer(
            Rect.fromLTWH(0, 0, list.page.width, list.page.height),
            Paint()
              ..colorFilter = const ColorFilter.matrix(<double>[
                -1, 0, 0, 0, 255, //
                0, -1, 0, 0, 255, //
                0, 0, -1, 0, 255, //
                0, 0, 0, 1, 0,
              ]),
          );
        }
        canvas.save();
        applyPdfPageRotation(canvas, list.page);
        PaintPdfDisplayList.paint(
          canvas,
          list,
          decodeImage: (Uint8List bytes, bool _) =>
              _images[identityHashCode(bytes)],
        );
        canvas.restore();
        if (nightMode && !editing) {
          canvas.restore();
        }
      }
      if (!_previewZoom && !scaleMatch) {
        _scheduleRaster(i, scale);
      }
      canvas.save();
      applyPdfPageRotation(canvas, list.page);
      final PdfTextSelection? sel = _selecting ? _live : selection;
      if (sel != null && !sel.isCollapsed && _selectionOwns(sel, i)) {
        final Paint fill = Paint()..color = _config.theme.selectionFill;
        for (final ({int page, Rect rect}) box in sel.boxes(_lists)) {
          if (box.page == i) {
            canvas.drawRect(box.rect, fill);
          }
        }
      }
      for (int h = 0; h < findMarks.length; h++) {
        final PdfFindMark mark = findMarks[h];
        if (mark.page != i) {
          continue;
        }
        final bool current = h == findIndex;
        final Paint fill = Paint()
          ..color = current ? const Color(0x99F59E0B) : const Color(0x55C9A227);
        for (final Rect rect in mark.rects) {
          canvas.drawRect(rect, fill);
        }
      }
      if (i < annots.length) {
        for (final PdfAnnot annot in annots[i]) {
          // Link annots carry a default yellow `/C` in many PDFs; Evince and
          // Acrobat do not fill them permanently — only markup types do.
          if (!_paintAnnotFill(annot.subtype)) {
            continue;
          }
          final double ah = annot.rect.height;
          final double at = ah < 0 ? annot.rect.y + ah : annot.rect.y;
          canvas.drawRect(
            Rect.fromLTWH(annot.rect.x, at, annot.rect.width.abs(), ah.abs()),
            Paint()..color = Color(annot.color).withValues(alpha: 0.28),
          );
        }
      }
      canvas.restore();
      onDraw?.call(canvas, Size(list.page.width, list.page.height), i);
      canvas.restore();
      cursor += (swipeHorizontal ? w : h) + PdfPageLayout.gap;
    }
    canvas.restore();
    _paintScrollBar(canvas, offset);
    _paintLinkPreview(canvas, offset);
  }

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (
        PointerSignalEvent signal,
      ) {
        if (signal is PointerScrollEvent) {
          if (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed) {
            final double factor = signal.scrollDelta.dy > 0 ? 0.9 : 1.1;
            final Offset focal = _viewport.origin + signal.localPosition;
            if (onZoomBy != null) {
              onZoomBy!(factor, focal);
            } else {
              _zoomBy(factor, signal.localPosition);
            }
          } else if (enableSwipe) {
            Offset delta = signal.scrollDelta;
            if (HardwareKeyboard.instance.isShiftPressed &&
                delta.dx.abs() < delta.dy.abs()) {
              delta = Offset(delta.dy, 0);
            } else if (swipeHorizontal &&
                delta.dx.abs() < delta.dy.abs() &&
                !HardwareKeyboard.instance.isShiftPressed) {
              delta = Offset(delta.dy, 0);
            }
            _viewport.pan(delta);
          }
          _finishScroll();
        }
      });
      return;
    }
    if (event is PointerPanZoomStartEvent) {
      _panZoomScale = 1;
      _stopFling();
      return;
    }
    if (event is PointerPanZoomUpdateEvent) {
      final bool zooming =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          (event.scale - _panZoomScale).abs() > 0.02;
      if (zooming && _panZoomScale != 0) {
        final double factor = event.scale / _panZoomScale;
        final Offset focal = _viewport.origin + event.localPosition;
        if (onZoomBy != null) {
          onZoomBy!(factor, focal, animate: false);
        } else {
          _zoomBy(factor, event.localPosition);
        }
        _panZoomScale = event.scale == 0 ? _panZoomScale : event.scale;
      } else if (enableSwipe) {
        _viewport.pan(-event.localPanDelta);
      }
      _finishScroll();
      return;
    }
    if (event is PointerHoverEvent || event is PointerMoveEvent) {
      _hoverLocal = event.localPosition;
      _syncLinkPreview();
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (_selecting || _pendingLink != null) {
        _finishSelect();
      }
      return;
    }
    if (event is PointerDownEvent) {
      _stopFling();
      _ensureRecognizers();
      if (_scrollBarVisible && _vTrack.contains(event.localPosition)) {
        _scrollDrag = true;
        if (!_vThumb.contains(event.localPosition)) {
          _jumpScroll(event.localPosition);
        }
        _pan?.addPointer(event);
        return;
      }
      if (event.buttons == kSecondaryMouseButton) {
        _showContextMenu(event);
        return;
      }
      final _PageHit? page = _pageHit(event.localPosition);
      if (page != null) {
        for (final PdfAnnot annot
            in page.index < annots.length
                ? annots[page.index]
                : const <PdfAnnot>[]) {
          if (!annot.rect.contains(page.x, page.y)) {
            continue;
          }
          // Link annots are followed as hotspots; markup taps stay here.
          if (annot.subtype == 'Link' ||
              annot.uri != null ||
              annot.goToPage != null) {
            continue;
          }
          onAnnotTap?.call(page.index, annot);
          _pan?.addPointer(event);
          return;
        }
        _pendingLink = _hotspotAt(page);
        if (_canSelect) {
          final PdfTextHit? text = _textHit(page);
          if (text != null) {
            _beginSelect(event, page, text);
            _pan?.addPointer(event);
            return;
          }
        }
        if (_pendingLink != null) {
          onFollowLink?.call(_pendingLink!);
          _pendingLink = null;
          return;
        }
      }
      _clearLive();
      if (enableSwipe) {
        _pan?.addPointer(event);
      }
    }
  }

  void _beginSelect(PointerDownEvent event, _PageHit page, PdfTextHit text) {
    final DateTime now = DateTime.now();
    final bool again =
        _downAt != null &&
        _downLocal != null &&
        now.difference(_downAt!) < const Duration(milliseconds: 400) &&
        (event.localPosition - _downLocal!).distance < 6;
    _clickCount = again ? _clickCount + 1 : 1;
    _downAt = now;
    _downLocal = event.localPosition;
    _selecting = true;
    _anchor = text;
    final PdfTextRun run = _lists[page.index].runs[text.run];
    if (_clickCount >= 3) {
      _live = PdfTextSelection.run(page.index, text.run, run);
    } else if (_clickCount == 2) {
      _live = PdfTextSelection.word(text, run);
    } else {
      _live = PdfTextSelection.collapsed(text);
    }
    _anchor = _live!.anchor;
    markNeedsPaint();
    onSelectText?.call(_live);
  }

  void _extendSelection(Offset local) {
    final PdfTextHit? hit = _hitOrNearest(local);
    if (hit == null || _anchor == null) {
      return;
    }
    _live = PdfTextSelection(anchor: _anchor!, extent: hit);
    markNeedsPaint();
    onSelectText?.call(_live);
  }

  void _finishSelect() {
    _selecting = false;
    if (_live != null && _live!.isCollapsed && _pendingLink != null) {
      onFollowLink?.call(_pendingLink!);
    }
    _pendingLink = null;
    onSelectText?.call(_live);
  }

  bool _selectionOwns(PdfTextSelection sel, int page) {
    final PdfTextSelection n = sel.normalized;
    return page >= n.anchor.page && page <= n.extent.page;
  }

  void _clearLive() {
    _selecting = false;
    _live = null;
    _anchor = null;
    _pendingLink = null;
    onSelectText?.call(null);
    markNeedsPaint();
  }

  void _showContextMenu(PointerDownEvent event) {
    final void Function(PdfContextHit hit)? callback = onContextMenu;
    if (callback == null) {
      return;
    }
    final _PageHit? page =
        _pageHit(event.localPosition) ?? _pageBand(event.localPosition);
    if (page == null) {
      return;
    }
    PdfAnnot? markup;
    if (page.index < annots.length) {
      for (final PdfAnnot annot in annots[page.index]) {
        if (!annot.rect.contains(page.x, page.y) || _isLinkAnnot(annot)) {
          continue;
        }
        markup = annot;
        break;
      }
    }
    callback(
      PdfContextHit(
        globalPosition: event.position,
        pageIndex: page.index,
        link: _hotspotAt(page),
        annot: markup,
      ),
    );
  }

  bool _isLinkAnnot(PdfAnnot annot) {
    return annot.subtype == 'Link' ||
        annot.uri != null ||
        annot.goToPage != null;
  }

  /// Page under [window] even when the pointer is in the side gutter.
  _PageHit? _pageBand(Offset window) {
    final double scale = _viewScale;
    if (swipeHorizontal) {
      var left = PdfPageLayout.gutter;
      final double contentX = window.dx + _viewport.origin.dx;
      for (int i = 0; i < _lists.length; i++) {
        final PdfDisplayList list = _lists[i];
        final double w = list.page.width * scale;
        if (contentX <= left + w || i == _lists.length - 1) {
          final double top = _pageTop(list);
          final ({double x, double y}) content = PdfPageView.fromView(
            list.page,
            ((contentX - left) / scale).clamp(0, list.page.width),
            ((window.dy + _viewport.origin.dy - top) / scale).clamp(
              0,
              list.page.height,
            ),
          );
          return _PageHit(i, content.x, content.y);
        }
        left += w + PdfPageLayout.gap;
      }
      return null;
    }
    var top = PdfPageLayout.gap;
    final double contentY = window.dy + _viewport.origin.dy;
    for (int i = 0; i < _lists.length; i++) {
      final PdfDisplayList list = _lists[i];
      final double h = list.page.height * scale;
      if (contentY <= top + h || i == _lists.length - 1) {
        final ({double x, double y}) content = PdfPageView.fromView(
          list.page,
          0,
          ((contentY - top) / scale).clamp(0, list.page.height),
        );
        return _PageHit(i, content.x, content.y);
      }
      top += h + PdfPageLayout.gap;
    }
    return null;
  }

  _PageHit? _pageHit(Offset window) {
    final double scale = _viewScale;
    if (swipeHorizontal) {
      var left = PdfPageLayout.gutter;
      for (int i = 0; i < _lists.length; i++) {
        final PdfDisplayList list = _lists[i];
        final double top = _pageTop(list);
        final double x = (window.dx + _viewport.origin.dx - left) / scale;
        final double y = (window.dy + _viewport.origin.dy - top) / scale;
        if (x >= -8 &&
            x <= list.page.width + 8 &&
            y >= 0 &&
            y <= list.page.height) {
          final ({double x, double y}) content = PdfPageView.fromView(
            list.page,
            x,
            y,
          );
          return _PageHit(i, content.x, content.y);
        }
        left += list.page.width * scale + PdfPageLayout.gap;
      }
      return null;
    }
    var top = PdfPageLayout.gap;
    for (int i = 0; i < _lists.length; i++) {
      final PdfDisplayList list = _lists[i];
      final double left = _pageLeft(list);
      final double x = (window.dx + _viewport.origin.dx - left) / scale;
      final double y = (window.dy + _viewport.origin.dy - top) / scale;
      if (x >= -8 &&
          x <= list.page.width + 8 &&
          y >= 0 &&
          y <= list.page.height) {
        final ({double x, double y}) content = PdfPageView.fromView(
          list.page,
          x,
          y,
        );
        return _PageHit(i, content.x, content.y);
      }
      top += list.page.height * scale + PdfPageLayout.gap;
    }
    return null;
  }

  PdfTextHit? _textHit(_PageHit page) {
    final List<PdfTextRun> runs = _lists[page.index].runs;
    for (int r = runs.length - 1; r >= 0; r--) {
      if (PdfTextSelection.containsPadded(runs[r], page.x, page.y)) {
        return PdfTextHit(
          page: page.index,
          run: r,
          offset: PdfTextSelection.offsetAt(runs[r], page.x),
        );
      }
    }
    return null;
  }

  PdfTextHit? _hitOrNearest(Offset window) {
    final _PageHit? page = _pageHit(window) ?? _nearestPage(window);
    if (page == null) {
      return null;
    }
    final PdfTextHit? exact = _textHit(page);
    if (exact != null && !_keptOnAnchorLine(page, exact)) {
      return exact;
    }
    final PdfTextHit? sticky = _hitOnAnchorLine(page);
    if (sticky != null) {
      return sticky;
    }
    if (exact != null) {
      return exact;
    }
    final List<PdfTextRun> runs = _lists[page.index].runs;
    if (runs.isEmpty) {
      return PdfTextHit(page: page.index, run: 0, offset: 0);
    }
    var best = 0;
    var bestDist = double.infinity;
    for (int r = 0; r < runs.length; r++) {
      final PdfTextRun run = runs[r];
      final double cx = run.x + run.width / 2;
      final double cy = run.y + run.height / 2;
      final double d =
          (page.x - cx) * (page.x - cx) + (page.y - cy) * (page.y - cy);
      if (d < bestDist) {
        bestDist = d;
        best = r;
      }
    }
    return PdfTextHit(
      page: page.index,
      run: best,
      offset: PdfTextSelection.offsetAt(runs[best], page.x),
    );
  }

  /// A horizontal drag stays on the anchor line until the pointer clearly
  /// enters another line. A small downward wobble used to grab the heading.
  bool _keptOnAnchorLine(_PageHit page, PdfTextHit exact) {
    final PdfTextHit? anchor = _anchor;
    if (anchor == null ||
        anchor.page != page.index ||
        exact.page != page.index) {
      return false;
    }
    final List<PdfTextRun> runs = _lists[page.index].runs;
    if (anchor.run < 0 ||
        anchor.run >= runs.length ||
        exact.run < 0 ||
        exact.run >= runs.length) {
      return false;
    }
    final PdfTextRun line = runs[anchor.run];
    if (PdfTextSelection.sameLine(line, runs[exact.run])) {
      return false;
    }
    final double pad = math.max(line.height, 8) * 0.35;
    return page.y >= line.y - 2 && page.y <= line.y + line.height + pad;
  }

  PdfTextHit? _hitOnAnchorLine(_PageHit page) {
    final PdfTextHit? anchor = _anchor;
    if (anchor == null || anchor.page != page.index) {
      return null;
    }
    final List<PdfTextRun> runs = _lists[page.index].runs;
    if (anchor.run < 0 || anchor.run >= runs.length) {
      return null;
    }
    final PdfTextRun line = runs[anchor.run];
    final double pad = math.max(line.height, 8) * 0.35;
    if (page.y < line.y - 2 || page.y > line.y + line.height + pad) {
      return null;
    }
    var best = -1;
    var bestDist = double.infinity;
    for (int r = 0; r < runs.length; r++) {
      if (!PdfTextSelection.sameLine(line, runs[r])) {
        continue;
      }
      final PdfTextRun run = runs[r];
      final double cx = run.x + run.width / 2;
      final double d = (page.x - cx).abs();
      if (d < bestDist) {
        bestDist = d;
        best = r;
      }
    }
    if (best < 0) {
      return null;
    }
    return PdfTextHit(
      page: page.index,
      run: best,
      offset: PdfTextSelection.offsetAt(runs[best], page.x),
    );
  }

  _PageHit? _nearestPage(Offset window) {
    if (_lists.isEmpty) {
      return null;
    }
    final double scale = _viewScale;
    if (swipeHorizontal) {
      var left = PdfPageLayout.gutter;
      final double contentX = window.dx + _viewport.origin.dx;
      if (contentX < left) {
        return _PageHit(0, 0, 0);
      }
      for (int i = 0; i < _lists.length; i++) {
        final PdfDisplayList list = _lists[i];
        final double top = _pageTop(list);
        final double w = list.page.width * scale;
        if (contentX <= left + w || i == _lists.length - 1) {
          return _PageHit(
            i,
            (contentX - left) / scale,
            (window.dy + _viewport.origin.dy - top) / scale,
          );
        }
        left += w + PdfPageLayout.gap;
      }
      return _PageHit(_lists.length - 1, _lists.last.page.width, 0);
    }
    var top = PdfPageLayout.gap;
    final double contentY = window.dy + _viewport.origin.dy;
    if (contentY < top) {
      return _PageHit(0, 0, 0);
    }
    for (int i = 0; i < _lists.length; i++) {
      final PdfDisplayList list = _lists[i];
      final double left = _pageLeft(list);
      final double h = list.page.height * scale;
      if (contentY <= top + h || i == _lists.length - 1) {
        return _PageHit(
          i,
          (window.dx + _viewport.origin.dx - left) / scale,
          (contentY - top) / scale,
        );
      }
      top += h + PdfPageLayout.gap;
    }
    return _PageHit(_lists.length - 1, 0, _lists.last.page.height);
  }

  PdfLinkAction? _hotspotAt(_PageHit page) {
    for (final PdfHotspot spot in _lists[page.index].hotspots) {
      if (spot.rect.contains(page.x, page.y)) {
        return spot.action;
      }
    }
    return null;
  }

  bool get _hoverPreviewEnabled {
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };
  }

  int? _internalDest(PdfLinkAction? action) {
    if (action == null) {
      return null;
    }
    final String? uri = action.uri;
    if (uri != null && uri.isNotEmpty) {
      return null;
    }
    final int? page = action.pageIndex;
    if (page == null || page < 0 || page >= _lists.length) {
      return null;
    }
    return page;
  }

  void _syncLinkPreview() {
    if (!_hoverPreviewEnabled || _selecting) {
      if (_previewPage != null) {
        _previewPage = null;
        markNeedsPaint();
      }
      return;
    }
    final Offset? local = _hoverLocal;
    final _PageHit? page = local == null ? null : _pageHit(local);
    final int? dest = _internalDest(page == null ? null : _hotspotAt(page));
    if (dest != _previewPage) {
      _previewPage = dest;
      if (dest != null) {
        _warmFonts(_lists[dest]);
        _warmImages(_lists[dest]);
      }
      markNeedsPaint();
    } else if (dest != null) {
      markNeedsPaint();
    }
  }

  void _paintLinkPreview(Canvas canvas, Offset offset) {
    final int? dest = _previewPage;
    final Offset? local = _hoverLocal;
    if (dest == null || local == null || dest >= _lists.length) {
      return;
    }
    final _PageHit? hit = _pageHit(local);
    final PdfLinkAction? action = hit == null ? null : _hotspotAt(hit);
    if (_internalDest(action) != dest) {
      return;
    }
    const double pad = 8;
    const double cardW = 236;
    const double cardH = 176;
    const double captionH = 22;
    const double radius = 8;
    final double innerW = cardW - pad * 2;
    final double innerH = cardH - captionH - pad * 2;
    double left = local.dx + 18;
    double top = local.dy + 16;
    if (left + cardW > size.width - 8) {
      left = local.dx - cardW - 18;
    }
    if (top + cardH > size.height - 8) {
      top = local.dy - cardH - 12;
    }
    left = left.clamp(8, math.max(8.0, size.width - cardW - 8));
    top = top.clamp(8, math.max(8.0, size.height - cardH - 8));
    final Rect card = Rect.fromLTWH(
      offset.dx + left,
      offset.dy + top,
      cardW,
      cardH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        card.shift(const Offset(0, 2)),
        const Radius.circular(radius),
      ),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(radius)),
      Paint()..color = const Color(0xFFF8FAFC),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(radius)),
      Paint()
        ..color = const Color(0xFF94A3B8)
        ..style = PaintingStyle.stroke,
    );
    final PdfDisplayList list = _lists[dest];
    final double pageW = list.page.width <= 0 ? 1 : list.page.width;
    final double pageH = list.page.height;
    final double scale = innerW / pageW;
    final double viewPts = innerH / scale;
    final double destTop = _destTop(action, pageH);
    final double originY = (destTop - 10).clamp(
      0.0,
      math.max(0.0, pageH - viewPts),
    );
    final Rect viewport = Rect.fromLTWH(
      card.left + pad,
      card.top + captionH,
      innerW,
      innerH,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(viewport, const Radius.circular(4)),
    );
    canvas.drawRect(viewport, Paint()..color = const Color(0xFFFFFFFF));
    canvas.translate(viewport.left, viewport.top - originY * scale);
    canvas.scale(scale);
    canvas.save();
    applyPdfPageRotation(canvas, list.page);
    PaintPdfDisplayList.paint(
      canvas,
      list,
      decodeImage: (Uint8List bytes, bool _) =>
          _images[identityHashCode(bytes)],
    );
    canvas.restore();
    if (destTop > 12) {
      canvas.drawRect(
        Rect.fromLTWH(8, destTop - 2, pageW - 16, 1.5),
        Paint()..color = const Color(0xCCF59E0B),
      );
    }
    canvas.restore();
    final TextPainter label = TextPainter(
      text: TextSpan(
        text: 'Page ${dest + 1}',
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: cardW - 16);
    label.paint(canvas, Offset(card.left + 10, card.top + 4));
  }

  double _destTop(PdfLinkAction? action, double pageH) {
    final double? pdfY = action?.destY;
    if (pdfY == null || pageH <= 0) {
      return 0;
    }
    return (pageH - pdfY).clamp(0.0, pageH);
  }

  void _warmFonts(PdfDisplayList list) {
    for (final PdfPaintOp op in list.ops) {
      if (op is PdfDrawText && op.fontBytes != null) {
        PdfFontFaces.ensure(op.fontBytes!, () {
          _clearTiles();
          markNeedsPaint();
        });
      }
    }
  }

  void _warmImages(PdfDisplayList list) {
    for (final PdfPaintOp op in list.ops) {
      if (op is! PdfDrawImage || op.placeholder || op.bytes.isEmpty) {
        continue;
      }
      final int key = identityHashCode(op.bytes);
      if (_images.containsKey(key) || !_decoding.add(key)) {
        continue;
      }
      PdfRaster.decode(op, (ui.Image image) {
        _images[key] = image;
        _decoding.remove(key);
        markNeedsPaint();
      });
    }
  }

  @override
  void dispose() {
    _zoomSettle?.cancel();
    _zoomSettle = null;
    for (final _PageTile tile in _tiles.values) {
      tile.image?.dispose();
    }
    _tiles.clear();
    _rasterizing.clear();
    for (final ui.Image image in _images.values) {
      image.dispose();
    }
    _images.clear();
    super.dispose();
  }
}

class _PageTile {
  ui.Image? image;
  double scale = 0;
}

/// Markup that Adobe/Evince paint as a tint; not navigation `/Link`.
bool _paintAnnotFill(String subtype) {
  switch (subtype) {
    case 'Highlight':
    case 'Underline':
    case 'Squiggly':
    case 'StrikeOut':
    case 'Caret':
    case 'Stamp':
    case 'Ink':
    case 'FreeText':
    case 'Text':
    case 'Square':
    case 'Circle':
    case 'Polygon':
    case 'PolyLine':
    case 'Redact':
      return true;
    default:
      return false;
  }
}

class _PageHit {
  _PageHit(this.index, this.x, this.y);
  final int index;
  final double x;
  final double y;
}
