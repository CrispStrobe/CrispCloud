import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../editor_slide/snap_guidelines.dart';
import '../editor_slide/transform_handles.dart';
import '../embed/office_theme.dart';
import 'report_completion_popup.dart';
import 'report_design_layout.dart';
import 'report_designer_controller.dart';
import 'report_element_painter.dart';
import 'report_layout_painter.dart';
import 'report_pinch_zoom.dart';

/// Right-click target on the band canvas.
@immutable
class ReportCanvasContextHit {
  /// ReportCanvasContextHit API.
  const ReportCanvasContextHit({
    required this.globalPosition,
    this.elementId,
    this.band,
  });

  /// globalPosition API.
  final Offset globalPosition;

  /// Element under the pointer.
  final String? elementId;

  /// Band under the pointer.
  final ReportBandKind? band;
}

/// Band canvas of the report designer.
class ReportDesignerCanvas extends LeafRenderObjectWidget {
  /// ReportDesignerCanvas API.
  const ReportDesignerCanvas({
    super.key,
    required this.controller,
    this.theme = OfficeTheme.light,
    this.onContextMenu,
    this.onActivate,
  });

  /// controller API.
  final ReportDesignerController controller;

  /// theme API.
  final OfficeTheme theme;

  /// Right-click callback.
  final ValueChanged<ReportCanvasContextHit>? onContextMenu;

  /// Pointer down (hosts request keyboard focus).
  final VoidCallback? onActivate;

  @override
  RenderReportDesigner createRenderObject(BuildContext context) =>
      RenderReportDesigner(
        controller: controller,
        theme: theme,
        onContextMenu: onContextMenu,
        onActivate: onActivate,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportDesigner renderObject,
  ) {
    renderObject
      ..controller = controller
      ..theme = theme
      ..onContextMenu = onContextMenu
      ..onActivate = onActivate;
  }
}

enum _Drag { none, move, resize, band, marquee, create, pan, caret }

/// RenderBox behind [ReportDesignerCanvas].
class RenderReportDesigner extends RenderBox implements MouseTrackerAnnotation {
  /// RenderReportDesigner API.
  RenderReportDesigner({
    required this._controller,
    required this._theme,
    this.onContextMenu,
    this.onActivate,
  }) {
    _raster.onImageReady = markNeedsPaint;
  }

  ReportDesignerController _controller;
  OfficeTheme _theme;

  /// Right-click callback.
  ValueChanged<ReportCanvasContextHit>? onContextMenu;

  /// Pointer-down callback.
  VoidCallback? onActivate;

  final ReportLayoutPainter _raster = ReportLayoutPainter();
  late final ReportElementPainter _painter = ReportElementPainter(_raster);
  final ReportCompletionPopup _popup = ReportCompletionPopup();
  Rect? _popupRect;
  final Map<String, TextPainter> _labels = <String, TextPainter>{};

  /// Ruler thickness, logical pixels.
  static const double ruler = 20;

  /// Space around the page, logical pixels.
  static const double pad = 24;

  static const double _mm = 72 / 25.4;

  Offset _scroll = Offset.zero;
  Offset? _hover;
  late final ReportPinchZoom _pinch = ReportPinchZoom(
    zoom: () => _controller.zoom,
    onZoom: _zoomAround,
    onPinchStart: () => _onUp(const PointerCancelEvent()),
  );

  ReportDesignLayout? _layoutCache;
  int _layoutRevision = -1;
  ReportTemplate? _layoutTemplate;
  ReportDesignLayout? _frozen;

  _Drag _drag = _Drag.none;
  int _handle = 0;
  Offset _downDoc = Offset.zero;
  Offset _lastLocal = Offset.zero;
  Rect? _rubber;
  var _additive = false;
  ReportDesignSlot? _createSlot;
  ReportDesignSlot? _bandSlot;
  SnapGuidelines? _guides;
  final Map<String, Rect> _startRects = <String, Rect>{};
  final Map<String, double> _startBandTop = <String, double>{};
  final Map<String, Size> _startSizes = <String, Size>{};

  Duration _lastTapTime = Duration.zero;
  Offset _lastTapPos = Offset.zero;
  int _taps = 0;

  /// controller API.
  ReportDesignerController get controller => _controller;

  set controller(ReportDesignerController value) {
    if (identical(value, _controller)) {
      return;
    }
    if (attached) {
      _controller.removeListener(_onChanged);
      value.addListener(_onChanged);
    }
    _controller = value;
    _layoutCache = null;
    markNeedsPaint();
  }

  /// theme API.
  OfficeTheme get theme => _theme;

  set theme(OfficeTheme value) {
    if (identical(value, _theme)) {
      return;
    }
    _theme = value;
    markNeedsPaint();
  }

  void _onChanged() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void _onSystemFonts() {
    _painter.clearText();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_onChanged);
    PaintingBinding.instance.systemFonts.addListener(_onSystemFonts);
  }

  @override
  void detach() {
    _controller.removeListener(_onChanged);
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFonts);
    super.detach();
  }

  @override
  void dispose() {
    _popup.dispose();
    _painter.dispose();
    _raster.dispose();
    for (final TextPainter tp in _labels.values) {
      tp.dispose();
    }
    _labels.clear();
    super.dispose();
  }

  // ------------------------------------------------------------ geometry

  double get _scale => _controller.zoom;

  ReportDesignLayout get _layout {
    final ReportDesignLayout? frozen = _frozen;
    if (frozen != null) {
      return frozen;
    }
    if (_layoutCache == null ||
        _layoutRevision != _controller.revision ||
        !identical(_layoutTemplate, _controller.template)) {
      _layoutCache = ReportDesignLayout.of(_controller.template);
      _layoutRevision = _controller.revision;
      _layoutTemplate = _controller.template;
    }
    return _layoutCache!;
  }

  Offset _originFor(ReportDesignLayout layout) {
    final double docW = layout.width * _scale;
    final double avail = size.width - ruler;
    final double x = docW + 2 * pad < avail
        ? ruler + (avail - docW) / 2
        : ruler + pad - _scroll.dx;
    return Offset(x, ruler + pad - _scroll.dy);
  }

  Offset get _origin => _originFor(_layout);

  Offset _toDoc(Offset local) => (local - _origin) / _scale;

  Rect _toLocalRect(Rect r) {
    final Offset o = _origin;
    final double s = _scale;
    return Rect.fromLTRB(
      o.dx + r.left * s,
      o.dy + r.top * s,
      o.dx + r.right * s,
      o.dy + r.bottom * s,
    );
  }

  int _revealSeen = 0;

  /// Scrolls the element or band picked by
  /// [ReportDesignerController.revealDiagnostic] into view.
  void _revealTarget() {
    if (_revealSeen == _controller.revealSerial) {
      return;
    }
    _revealSeen = _controller.revealSerial;
    final ReportDesignLayout layout = _layout;
    final String? id = _controller.revealElement;
    final (ReportDesignSlot, ReportElement)? hit = id == null
        ? null
        : layout.find(id);
    Rect? target = hit == null ? null : layout.elementRect(hit.$1, hit.$2);
    if (target == null) {
      for (final ReportDesignSlot slot in layout.slots) {
        if (slot.band.kind == _controller.revealBand) {
          target = slot.caption.expandToInclude(slot.body);
          break;
        }
      }
    }
    if (target == null) {
      return;
    }
    final Rect local = _toLocalRect(target);
    final Rect view = Rect.fromLTRB(ruler, ruler, size.width, size.height);
    if (view.deflate(16).contains(local.topLeft) &&
        view.deflate(16).contains(local.bottomRight)) {
      return;
    }
    _scroll += local.center - view.center;
    _clampScroll();
  }

  void _clampScroll() {
    final ReportDesignLayout layout = _layout;
    final double contentW = layout.width * _scale + 2 * pad;
    final double contentH = layout.height * _scale + 2 * pad + 120;
    final double maxX = math.max(0, contentW - (size.width - ruler));
    final double maxY = math.max(0, contentH - (size.height - ruler));
    _scroll = Offset(
      _scroll.dx.clamp(0, maxX).toDouble(),
      _scroll.dy.clamp(0, maxY).toDouble(),
    );
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size s = constraints.biggest;
    return s.isFinite ? s : constraints.constrain(const Size(900, 700));
  }

  @override
  void performResize() {
    super.performResize();
    _controller.viewportWidth = size.width - ruler;
  }

  @override
  bool hitTestSelf(Offset position) {
    _hover = position;
    return true;
  }

  // ------------------------------------------------------------ mouse

  @override
  MouseCursor get cursor {
    final Offset? local = _hover;
    if (local == null) {
      return SystemMouseCursors.basic;
    }
    switch (_drag) {
      case _Drag.move:
        return SystemMouseCursors.move;
      case _Drag.resize:
        return _cursorForHandle(_handle);
      case _Drag.band:
        return SystemMouseCursors.resizeUpDown;
      case _Drag.pan:
        return SystemMouseCursors.grabbing;
      case _Drag.create:
      case _Drag.marquee:
        return SystemMouseCursors.precise;
      case _Drag.caret:
        return SystemMouseCursors.text;
      case _Drag.none:
        break;
    }
    if (local.dx < ruler || local.dy < ruler) {
      return SystemMouseCursors.basic;
    }
    if (_controller.tool != ReportDesignTool.select) {
      return SystemMouseCursors.precise;
    }
    final ReportDesignLayout layout = _layout;
    final Offset doc = _toDoc(local);
    final String? editing = _controller.editingId;
    if (editing != null) {
      final (ReportDesignSlot, ReportElement)? f = layout.find(editing);
      if (f != null && layout.elementRect(f.$1, f.$2).contains(doc)) {
        return SystemMouseCursors.text;
      }
    }
    final int? handle = _selectionHandleAt(layout, local);
    if (handle != null) {
      return _cursorForHandle(handle);
    }
    if (_bandEdgeAt(layout, doc) != null) {
      return SystemMouseCursors.resizeUpDown;
    }
    if (layout.hit(doc, slop: 4 / _scale) != null) {
      return SystemMouseCursors.move;
    }
    return SystemMouseCursors.basic;
  }

  static MouseCursor _cursorForHandle(int handle) => switch (handle) {
    0 || 4 => SystemMouseCursors.resizeUpLeftDownRight,
    2 || 6 => SystemMouseCursors.resizeUpRightDownLeft,
    1 || 5 => SystemMouseCursors.resizeUpDown,
    _ => SystemMouseCursors.resizeLeftRight,
  };

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => (_) {
    _hover = null;
  };

  @override
  bool get validForMouseTracker => attached;

  int? _selectionHandleAt(ReportDesignLayout layout, Offset local) {
    final List<String> sel = _controller.selection;
    if (sel.length != 1 || _controller.editingId != null) {
      return null;
    }
    final (ReportDesignSlot, ReportElement)? f = layout.find(sel.first);
    if (f == null) {
      return null;
    }
    return TransformHandles(
      _toLocalRect(layout.elementRect(f.$1, f.$2)),
    ).hit(local, radius: 6, showRotate: false);
  }

  ReportDesignSlot? _bandEdgeAt(ReportDesignLayout layout, Offset doc) {
    if (doc.dx < 0 || doc.dx > layout.width) {
      return null;
    }
    for (final ReportDesignSlot s in layout.slots) {
      if ((doc.dy - s.body.bottom).abs() * _scale <= 4) {
        return s;
      }
    }
    return null;
  }

  // ------------------------------------------------------------ events

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerHoverEvent) {
      _hover = event.localPosition;
      return;
    }
    if (event is PointerSignalEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, _onSignal);
      return;
    }
    if (_pinch.handle(event)) {
      return;
    }
    if (event is PointerDownEvent) {
      _onDown(event);
    } else if (event is PointerMoveEvent) {
      _onMove(event);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _onUp(event);
    }
  }

  /// Sets [zoom] keeping the document point under [focal] in place, then
  /// pans by [pan].
  void _zoomAround(double zoom, Offset focal, Offset pan) {
    final Offset before = _toDoc(focal);
    _controller.zoom = zoom;
    final Offset after = _origin + before * _scale;
    _scroll += after - focal - pan;
    _clampScroll();
    markNeedsPaint();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final bool ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl) {
      final Offset focal = event.localPosition;
      final Offset before = _toDoc(focal);
      _controller.zoom =
          _controller.zoom * (event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1);
      final Offset o = _origin;
      final Offset after = o + before * _scale;
      _scroll += after - focal;
    } else if (HardwareKeyboard.instance.isShiftPressed) {
      _scroll += Offset(event.scrollDelta.dy, 0);
    } else {
      _scroll += event.scrollDelta;
    }
    _clampScroll();
    markNeedsPaint();
  }

  int _countTap(PointerDownEvent e) {
    final bool near = (e.localPosition - _lastTapPos).distance < 6;
    final bool quick =
        e.timeStamp - _lastTapTime < const Duration(milliseconds: 400);
    _taps = near && quick ? _taps + 1 : 1;
    _lastTapTime = e.timeStamp;
    _lastTapPos = e.localPosition;
    return _taps;
  }

  static bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  static bool get _additiveKey =>
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _onDown(PointerDownEvent e) {
    onActivate?.call();
    final Offset local = e.localPosition;
    final Rect? popup = _popupRect;
    final ReportCompletionResult? suggestions = _controller.completion;
    if (popup != null && suggestions != null && popup.contains(local)) {
      final int? i = ReportCompletionPopup.hitIndex(
        popup,
        local,
        suggestions.items.length,
        _controller.completionIndex,
      );
      if (i != null) {
        _controller.acceptCompletion(i);
      }
      return;
    }
    _lastLocal = local;
    final ReportDesignLayout layout = _layout;
    final Offset doc = _toDoc(local);
    if (e.buttons == kSecondaryMouseButton) {
      final (ReportDesignSlot, ReportElement)? hit = layout.hit(
        doc,
        slop: 4 / _scale,
      );
      if (hit != null && !_controller.isSelected(hit.$2.id)) {
        _controller.select(hit.$2.id);
      }
      onContextMenu?.call(
        ReportCanvasContextHit(
          globalPosition: e.position,
          elementId: hit?.$2.id,
          band: hit?.$1.band.kind ?? layout.slotAtY(doc.dy)?.band.kind,
        ),
      );
      return;
    }
    if (e.buttons == kMiddleMouseButton) {
      _drag = _Drag.pan;
      return;
    }
    if (local.dx < ruler || local.dy < ruler) {
      return;
    }
    final int taps = _countTap(e);
    final String? editing = _controller.editingId;
    if (editing != null) {
      final (ReportDesignSlot, ReportElement)? f = layout.find(editing);
      if (f != null &&
          f.$2 is ReportTextElement &&
          layout.elementRect(f.$1, f.$2).contains(doc)) {
        _placeCaret(layout, f.$1, f.$2 as ReportTextElement, doc, _shift);
        _drag = _Drag.caret;
        return;
      }
      _controller.commitTextEdit();
    }
    if (_controller.tool != ReportDesignTool.select) {
      final ReportDesignSlot? slot = layout.bodyNear(doc.dy);
      if (slot == null) {
        return;
      }
      _drag = _Drag.create;
      _createSlot = slot;
      _downDoc = doc;
      _rubber = Rect.fromPoints(doc, doc);
      markNeedsPaint();
      return;
    }
    final int? handle = _selectionHandleAt(layout, local);
    if (handle != null) {
      final (ReportDesignSlot, ReportElement) f = layout.find(
        _controller.selection.first,
      )!;
      _beginElementGesture(layout, <(ReportDesignSlot, ReportElement)>[f]);
      _drag = _Drag.resize;
      _handle = handle;
      return;
    }
    final ReportDesignSlot? edge = _bandEdgeAt(layout, doc);
    if (edge != null) {
      _controller.beginGesture();
      _drag = _Drag.band;
      _bandSlot = edge;
      _controller.selectBand(edge.band.kind);
      return;
    }
    final (ReportDesignSlot, ReportElement)? hit = layout.hit(
      doc,
      slop: 4 / _scale,
    );
    if (hit != null) {
      final String id = hit.$2.id;
      final bool additive = _additiveKey;
      if (taps >= 2 && !additive && hit.$2 is ReportTextElement) {
        _controller.beginTextEdit(id);
        _placeCaret(layout, hit.$1, hit.$2 as ReportTextElement, doc, false);
        return;
      }
      if (additive) {
        _controller.select(id, additive: true);
        if (!_controller.isSelected(id)) {
          return;
        }
      } else {
        _controller.select(id);
      }
      _beginElementGesture(layout, <(ReportDesignSlot, ReportElement)>[
        for (final String sid in _controller.selection)
          if (layout.find(sid) case final (ReportDesignSlot, ReportElement) f)
            f,
      ]);
      _drag = _Drag.move;
      _downDoc = doc;
      return;
    }
    final ReportDesignSlot? slot = layout.slotAtY(doc.dy);
    _additive = _additiveKey;
    if (!_additive) {
      _controller.selectBand(slot?.band.kind);
    }
    if (slot != null && slot.caption.contains(doc)) {
      return;
    }
    _drag = _Drag.marquee;
    _downDoc = doc;
    _rubber = Rect.fromPoints(doc, doc);
  }

  void _beginElementGesture(
    ReportDesignLayout layout,
    List<(ReportDesignSlot, ReportElement)> items,
  ) {
    _controller.beginGesture();
    _frozen = layout;
    _startRects.clear();
    _startBandTop.clear();
    _startSizes.clear();
    final Set<String> ids = <String>{};
    for (final (ReportDesignSlot s, ReportElement e) in items) {
      ids.add(e.id);
      _startRects[e.id] = layout.elementRect(s, e);
      _startBandTop[e.id] = s.body.top;
      _startSizes[e.id] = Size(e.width, e.height);
    }
    _guides = _controller.snapToGuides ? _buildGuides(layout, ids) : null;
  }

  SnapGuidelines _buildGuides(ReportDesignLayout layout, Set<String> exclude) {
    final SnapGuidelines g = SnapGuidelines(threshold: 5 / _scale);
    final ReportTemplate t = layout.template;
    g.addTarget(Rect.fromLTWH(0, 0, layout.width, layout.height));
    g.addTarget(
      Rect.fromLTRB(
        t.margins.left,
        0,
        layout.width - t.margins.right,
        layout.height,
      ),
    );
    for (final ReportDesignSlot s in layout.slots) {
      g.addTarget(s.body);
      for (final ReportElement e in s.band.elements) {
        if (!exclude.contains(e.id)) {
          g.addTarget(layout.elementRect(s, e));
        }
      }
    }
    return g;
  }

  double _grid(double v) {
    final double g = _controller.gridSize;
    return g <= 0 ? v : (v / g).roundToDouble() * g;
  }

  void _onMove(PointerMoveEvent e) {
    final Offset local = e.localPosition;
    final Offset doc = _toDoc(local);
    switch (_drag) {
      case _Drag.none:
        return;
      case _Drag.pan:
        _scroll -= local - _lastLocal;
        _clampScroll();
        markNeedsPaint();
      case _Drag.caret:
        final String? id = _controller.editingId;
        final ReportDesignLayout layout = _layout;
        final (ReportDesignSlot, ReportElement)? f = id == null
            ? null
            : layout.find(id);
        if (f != null && f.$2 is ReportTextElement) {
          _placeCaret(layout, f.$1, f.$2 as ReportTextElement, doc, true);
        }
      case _Drag.create:
      case _Drag.marquee:
        _rubber = Rect.fromPoints(_downDoc, doc);
        markNeedsPaint();
      case _Drag.move:
        _applyMove(doc);
      case _Drag.resize:
        _applyResize(doc);
      case _Drag.band:
        _applyBand(doc);
    }
    _lastLocal = local;
  }

  void _applyMove(Offset doc) {
    if (_startRects.isEmpty) {
      return;
    }
    var delta = doc - _downDoc;
    Rect union = _startRects.values.first;
    for (final Rect r in _startRects.values) {
      union = union.expandToInclude(r);
    }
    final Rect moved = union.shift(delta);
    var snap = _guides?.snap(moved) ?? Offset.zero;
    if (_controller.snapToGrid) {
      final String lead = _startRects.keys.first;
      final double bandTop = _startBandTop[lead]!;
      final Rect leadRect = _startRects[lead]!.shift(delta);
      final double dx = snap.dx != 0
          ? snap.dx
          : _grid(leadRect.left) - leadRect.left;
      final double rel = leadRect.top - bandTop;
      final double dy = snap.dy != 0 ? snap.dy : _grid(rel) - rel;
      snap = Offset(dx, dy);
    }
    delta += snap;
    _controller.gestureSetRects(<String, ReportRect>{
      for (final MapEntry<String, Rect> entry in _startRects.entries)
        entry.key: ReportRect(
          entry.value.left + delta.dx,
          entry.value.top + delta.dy - _startBandTop[entry.key]!,
          _startSizes[entry.key]!.width,
          _startSizes[entry.key]!.height,
        ),
    });
  }

  void _applyResize(Offset doc) {
    if (_startRects.length != 1) {
      return;
    }
    final String id = _startRects.keys.first;
    final Rect r0 = _startRects[id]!;
    final double bandTop = _startBandTop[id]!;
    var p = doc;
    final Offset snap =
        _guides?.snap(Rect.fromLTWH(p.dx, p.dy, 0, 0)) ?? Offset.zero;
    p += snap;
    if (_controller.snapToGrid) {
      p = Offset(
        snap.dx != 0 ? p.dx : _grid(p.dx),
        snap.dy != 0 ? p.dy : bandTop + _grid(p.dy - bandTop),
      );
    }
    var l = r0.left;
    var t = r0.top;
    var r = r0.right;
    var b = r0.bottom;
    if (_handle == 0 || _handle == 6 || _handle == 7) {
      l = p.dx;
    }
    if (_handle == 2 || _handle == 3 || _handle == 4) {
      r = p.dx;
    }
    if (_handle == 0 || _handle == 1 || _handle == 2) {
      t = p.dy;
    }
    if (_handle == 4 || _handle == 5 || _handle == 6) {
      b = p.dy;
    }
    final bool corner = _handle.isEven;
    if (corner && _shift && r0.width > 0 && r0.height > 0) {
      final double ratio = r0.width / r0.height;
      final double w = (r - l).abs();
      final double h = w / ratio;
      if (_handle == 0 || _handle == 2) {
        t = b - h;
      } else {
        b = t + h;
      }
    }
    final ReportElement? e = _controller.template.findElement(id)?.$2;
    final bool line = e is ReportShapeElement && e.kind == ReportShapeKind.line;
    final double minSize = line ? 0 : 2;
    final double left = math.min(l, r);
    final double top = math.min(t, b);
    final double w = math.max((r - l).abs(), minSize);
    final double h = math.max((b - t).abs(), minSize);
    _controller.gestureSetRects(<String, ReportRect>{
      id: ReportRect(left, top - bandTop, w, h),
    });
  }

  void _applyBand(Offset doc) {
    final ReportDesignSlot? slot = _bandSlot;
    if (slot == null) {
      return;
    }
    var h = doc.dy - slot.body.top;
    if (_controller.snapToGrid) {
      h = _grid(h);
    }
    _controller.gestureSetBandHeight(slot.band.kind, h < 0 ? 0 : h);
  }

  void _onUp(PointerEvent e) {
    switch (_drag) {
      case _Drag.move:
        _finishMove();
        _controller.endGesture();
      case _Drag.resize:
      case _Drag.band:
        _controller.endGesture();
      case _Drag.create:
        final Rect? rect = _rubber;
        final ReportDesignSlot? slot = _createSlot;
        if (rect != null && slot != null && e is PointerUpEvent) {
          _controller.addElement(
            _controller.tool,
            slot.band.kind,
            ReportRect(
              rect.left,
              rect.top - slot.body.top,
              rect.width,
              rect.height,
            ),
          );
          if (!_shift) {
            _controller.tool = ReportDesignTool.select;
          }
        }
      case _Drag.marquee:
        final Rect? rect = _rubber;
        if (rect != null &&
            rect.width * _scale > 3 &&
            rect.height * _scale > 3) {
          final ReportDesignLayout layout = _layout;
          final List<String> ids = <String>[
            for (final ReportDesignSlot s in layout.slots)
              for (final ReportElement el in s.band.elements)
                if (layout.elementRect(s, el).inflate(0.5).overlaps(rect))
                  el.id,
          ];
          _controller.selectIds(ids, additive: _additive);
        }
      case _Drag.none:
      case _Drag.pan:
      case _Drag.caret:
        break;
    }
    _drag = _Drag.none;
    _frozen = null;
    _rubber = null;
    _createSlot = null;
    _bandSlot = null;
    _guides = null;
    _startRects.clear();
    markNeedsPaint();
  }

  void _finishMove() {
    final ReportDesignLayout? frozen = _frozen;
    if (frozen == null || _startRects.length != 1) {
      return;
    }
    final String id = _startRects.keys.first;
    final (ReportDesignSlot, ReportElement)? f = frozen.find(id);
    if (f == null) {
      return;
    }
    final Rect r = frozen.elementRect(f.$1, f.$2);
    final ReportDesignSlot? target = frozen.bodyNear(r.center.dy);
    if (target == null || identical(target.band, f.$1.band)) {
      return;
    }
    _controller.gestureMoveToBand(
      id,
      target.band.kind,
      r.top - target.body.top,
    );
  }

  void _placeCaret(
    ReportDesignLayout layout,
    ReportDesignSlot slot,
    ReportTextElement e,
    Offset doc,
    bool extend,
  ) {
    final (TextPainter tp, Offset origin) = _editPainter(layout, slot, e);
    final int index = tp.getPositionForOffset(doc - origin).offset;
    _controller.textEditor.setCaret(index, extend: extend);
  }

  (TextPainter, Offset) _editPainter(
    ReportDesignLayout layout,
    ReportDesignSlot slot,
    ReportTextElement e,
  ) {
    final Rect r = layout.elementRect(slot, e);
    final Rect content = r.deflate(e.padding);
    final TextPainter tp = _painter.textPainter(
      layout.template,
      e,
      _controller.textEditor.formulaBar,
      content.width,
      plain: true,
      color: _editColors(layout, slot, e).$2,
    );
    final double slack = content.height - tp.height;
    final double dy = switch (e.verticalAlign) {
      ReportVerticalAlign.top => 0,
      ReportVerticalAlign.middle => slack > 0 ? slack / 2 : 0,
      ReportVerticalAlign.bottom => slack > 0 ? slack : 0,
    };
    return (tp, Offset(content.left, content.top + dy));
  }

  // ------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _theme.canvasBackground,
    );
    _revealTarget();
    final ReportDesignLayout layout = _layout;
    final double s = _scale;
    final Offset o = _originFor(layout);
    final Rect page = Rect.fromLTWH(
      o.dx,
      o.dy,
      layout.width * s,
      math.max(layout.height, 40) * s,
    );
    canvas.drawRect(
      page.shift(const Offset(2, 3)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRect(page, Paint()..color = _theme.pageBackground);
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.scale(s);
    _paintDocument(canvas, layout);
    canvas.restore();
    _paintSelection(canvas, layout);
    _paintRulers(canvas, layout, o);
    _paintCompletion(canvas, layout);
    if (layout.slots.isEmpty) {
      _paintLabel(
        canvas,
        'No bands yet. Right-click the page to add a band.',
        Offset(page.left + 12, page.top + 12),
        const Color(0xFF6B7280),
        12,
      );
    }
    canvas.restore();
  }

  void _paintDocument(Canvas canvas, ReportDesignLayout layout) {
    final ReportTemplate t = layout.template;
    final double s = _scale;
    final double w = layout.width;
    final double h = math.max(layout.height, 40);
    if (_controller.showGrid && 5 * _mm * s >= 8) {
      final Paint grid = Paint()
        ..color =
            (_theme.pageBackground.computeLuminance() > 0.5 &&
                        _theme.gridLine.computeLuminance() < 0.3
                    ? const Color(0xFFC4C8CE)
                    : _theme.gridLine)
                .withValues(alpha: 0.45)
        ..strokeWidth = 0.5 / s;
      for (double x = 5 * _mm; x < w; x += 5 * _mm) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
      }
      for (final ReportDesignSlot slot in layout.slots) {
        for (
          double y = slot.body.top + 5 * _mm;
          y < slot.body.bottom;
          y += 5 * _mm
        ) {
          canvas.drawLine(Offset(0, y), Offset(w, y), grid);
        }
      }
    }
    final Paint margin = Paint()
      ..color = const Color(0x664472C4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / s;
    for (final double x in <double>[t.margins.left, w - t.margins.right]) {
      canvas.drawPath(
        ReportLayoutPainter.dashPath(
          Path()
            ..moveTo(x, 0)
            ..lineTo(x, h),
          ReportLineStyle.dashed,
          1.5 / s,
        ),
        margin,
      );
    }
    final String? editing = _controller.editingId;
    for (final ReportDesignSlot slot in layout.slots) {
      _paintCaption(canvas, slot, layout);
      final ReportColor bg = t.resolveColor(
        slot.band.background,
        ReportColor.transparent,
      );
      if (bg.alpha > 0) {
        canvas.drawRect(slot.body, Paint()..color = Color(bg.argb));
      }
      canvas.drawLine(
        slot.body.bottomLeft,
        slot.body.bottomRight,
        Paint()
          ..color = const Color(0xFFB8C0CC)
          ..strokeWidth = 1 / s,
      );
    }
    for (final ReportDesignSlot slot in layout.slots) {
      for (final ReportElement e in slot.band.elements) {
        _painter.paint(
          canvas,
          layout,
          slot,
          e,
          layout.elementRect(slot, e),
          _controller.images,
          shapes: _controller.shapes,
          hideText: e.id == editing,
          fonts: _controller.effectiveFonts,
          data: _controller.mockData,
        );
      }
    }
    if (editing != null) {
      _paintEditor(canvas, layout, editing);
    }
    _guides?.paint(canvas, Size(w, h), color: _theme.snapGuide);
    final Rect? rubber = _rubber;
    if (rubber != null) {
      final bool create = _drag == _Drag.create;
      canvas.drawRect(
        rubber,
        Paint()
          ..color = create
              ? const Color(0x1A2E75B6)
              : _theme.selectionFill.withValues(alpha: 0.12),
      );
      canvas.drawRect(
        rubber,
        Paint()
          ..color = _theme.selectionStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / s,
      );
    }
  }

  static const Map<ReportBandKind, Color> _captionFill =
      <ReportBandKind, Color>{
        ReportBandKind.reportHeader: Color(0xFFE6EDF7),
        ReportBandKind.pageHeader: Color(0xFFE8F3E6),
        ReportBandKind.groupHeader: Color(0xFFFFF2DC),
        ReportBandKind.detail: Color(0xFFF1E6F7),
        ReportBandKind.groupFooter: Color(0xFFFFF2DC),
        ReportBandKind.pageFooter: Color(0xFFE8F3E6),
        ReportBandKind.reportSummary: Color(0xFFE6EDF7),
      };

  /// English name of a band of [kind] (`Page Header`).
  static String bandName(ReportBandKind kind) => switch (kind) {
    ReportBandKind.reportHeader => 'Report Header',
    ReportBandKind.pageHeader => 'Page Header',
    ReportBandKind.groupHeader => 'Group Header',
    ReportBandKind.detail => 'Detail',
    ReportBandKind.groupFooter => 'Group Footer',
    ReportBandKind.pageFooter => 'Page Footer',
    ReportBandKind.reportSummary => 'Report Summary',
  };

  /// Caption text for [band].
  static String captionOf(ReportBand band) {
    final String name = bandName(band.kind);
    final List<String> notes = <String>[
      if (band.dataSet != null) 'data: ${band.dataSet}',
      if (band.groupBy != null) 'group: ${band.groupBy}',
      if (band.sortBy != null) 'sort: ${band.sortBy}',
      if (band.filter != null) 'filter: ${band.filter}',
    ];
    return notes.isEmpty ? name : '$name  ·  ${notes.join('  ·  ')}';
  }

  void _paintCaption(
    Canvas canvas,
    ReportDesignSlot slot,
    ReportDesignLayout layout,
  ) {
    final bool selected =
        _controller.selection.isEmpty &&
        _controller.selectedBand == slot.band.kind;
    canvas.drawRect(
      slot.caption,
      Paint()
        ..color = selected
            ? _theme.selectionStroke.withValues(alpha: 0.22)
            : (_captionFill[slot.band.kind] ?? const Color(0xFFEDEDED)),
    );
    final String label = captionOf(slot.band);
    final TextPainter tp = _label(label, 7.5, const Color(0xFF374151), true);
    final double x = layout.template.mirrored
        ? slot.caption.right - 6 - tp.width
        : slot.caption.left + 6;
    tp.paint(
      canvas,
      Offset(x, slot.caption.top + (slot.caption.height - tp.height) / 2),
    );
  }

  /// WCAG contrast ratio of two opaque colors.
  static double contrast(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Editor background (element fill, else band fill, else page) and a text
  /// color that stays readable on it.
  (Color, Color) _editColors(
    ReportDesignLayout layout,
    ReportDesignSlot slot,
    ReportTextElement e,
  ) {
    final ReportTemplate t = layout.template;
    ReportColor bg = t.resolveColor(e.background, ReportColor.transparent);
    if (bg.alpha < 255) {
      bg = t.resolveColor(slot.band.background, ReportColor.transparent);
    }
    final Color back = bg.alpha < 255 ? _theme.pageBackground : Color(bg.argb);
    final Color ink = Color(t.resolveColor(e.style.color, t.textColor).argb);
    if (contrast(back, ink.withValues(alpha: 1)) >= 4.5) {
      return (back, ink.withValues(alpha: 1));
    }
    const Color black = Color(0xFF111827);
    const Color white = Color(0xFFFFFFFF);
    return (
      back,
      contrast(back, black) >= contrast(back, white) ? black : white,
    );
  }

  void _paintEditor(Canvas canvas, ReportDesignLayout layout, String id) {
    final (ReportDesignSlot, ReportElement)? f = layout.find(id);
    if (f == null || f.$2 is! ReportTextElement) {
      return;
    }
    final ReportTextElement e = f.$2 as ReportTextElement;
    final Rect r = layout.elementRect(f.$1, e);
    final double s = _scale;
    final (Color back, Color ink) = _editColors(layout, f.$1, e);
    final (TextPainter tp, Offset origin) = _editPainter(layout, f.$1, e);
    final Rect box = Rect.fromLTRB(
      r.left,
      r.top,
      r.right,
      math.max(r.bottom, origin.dy + tp.height + e.padding),
    );
    canvas.drawRect(box, Paint()..color = back);
    final int start = _controller.textEditor.selectionStart;
    final int end = _controller.textEditor.selectionEnd;
    if (end > start) {
      final bool darkBack = back.computeLuminance() < 0.35;
      final Paint sel = Paint()
        ..color = darkBack
            ? const Color(0x66FFFFFF)
            : _theme.selectionStroke.withValues(alpha: 0.28);
      for (final TextBox b in tp.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        canvas.drawRect(b.toRect().shift(origin), sel);
      }
    }
    tp.paint(canvas, origin);
    final Offset caret = tp.getOffsetForCaret(
      TextPosition(offset: _controller.textEditor.caretIndex),
      Rect.zero,
    );
    final double lineH = tp.getFullHeightForCaret(
      TextPosition(offset: _controller.textEditor.caretIndex),
      Rect.zero,
    );
    canvas.drawRect(
      Rect.fromLTWH(origin.dx + caret.dx, origin.dy + caret.dy, 1.2 / s, lineH),
      Paint()..color = ink,
    );
    canvas.drawRect(
      box,
      Paint()
        ..color = _theme.focusRing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / s,
    );
  }

  void _paintCompletion(Canvas canvas, ReportDesignLayout layout) {
    _popupRect = null;
    final String? id = _controller.editingId;
    final ReportCompletionResult? r = id == null
        ? null
        : _controller.completion;
    if (id == null || r == null) {
      return;
    }
    final (ReportDesignSlot, ReportElement)? f = layout.find(id);
    if (f == null || f.$2 is! ReportTextElement) {
      return;
    }
    final (TextPainter tp, Offset origin) = _editPainter(
      layout,
      f.$1,
      f.$2 as ReportTextElement,
    );
    final TextPosition pos = TextPosition(
      offset: _controller.textEditor.caretIndex,
    );
    final Offset caret = origin + tp.getOffsetForCaret(pos, Rect.zero);
    final double lineH = tp.getFullHeightForCaret(pos, Rect.zero);
    final Offset o = _origin;
    final double s = _scale;
    final Rect rect = ReportCompletionPopup.place(
      o + caret * s,
      o + Offset(caret.dx, caret.dy + lineH) * s,
      size,
      r.items.length,
    );
    _popupRect = rect;
    _popup.paint(canvas, rect, r, _controller.completionIndex, _theme);
  }

  void _paintSelection(Canvas canvas, ReportDesignLayout layout) {
    final List<String> sel = _controller.selection;
    if (sel.isEmpty || _controller.editingId != null) {
      return;
    }
    for (int i = 0; i < sel.length; i++) {
      final (ReportDesignSlot, ReportElement)? f = layout.find(sel[i]);
      if (f == null) {
        continue;
      }
      final Rect r = _toLocalRect(layout.elementRect(f.$1, f.$2));
      TransformHandles(r).paint(
        canvas,
        strokeColor: _theme.handleStroke,
        fillColor: _theme.handleFill,
        showKnobs: sel.length == 1,
        showRotate: false,
        knobSize: 7,
      );
      if (i == 0 && sel.length > 1) {
        canvas.drawRect(
          r,
          Paint()
            ..color = _theme.handleStroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  void _paintRulers(Canvas canvas, ReportDesignLayout layout, Offset o) {
    final double s = _scale;
    final Paint bg = Paint()..color = _theme.chromeFill;
    final Paint edge = Paint()
      ..color = _theme.pageBorder
      ..strokeWidth = 1;
    final Paint tick = Paint()
      ..color = _theme.chromeText.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, ruler), bg);
    canvas.drawRect(Rect.fromLTWH(0, 0, ruler, size.height), bg);
    final ReportElement? lead = _controller.primary;
    if (lead != null) {
      final (ReportDesignSlot, ReportElement)? f = layout.find(lead.id);
      if (f != null) {
        final Rect r = _toLocalRect(layout.elementRect(f.$1, f.$2));
        final Paint mark = Paint()..color = _theme.selectionFill;
        canvas.drawRect(Rect.fromLTRB(r.left, 0, r.right, ruler), mark);
        canvas.drawRect(Rect.fromLTRB(0, r.top, ruler, r.bottom), mark);
      }
    }
    final double stepPx = _mm * s;
    final int every = stepPx >= 3 ? 1 : (stepPx * 5 >= 3 ? 5 : 10);
    final int maxMm = (layout.width / _mm).ceil();
    for (int k = 0; k <= maxMm; k += every) {
      final double x = o.dx + k * _mm * s;
      if (x < ruler || x > size.width) {
        continue;
      }
      final double len = k % 10 == 0 ? 10 : (k % 5 == 0 ? 6 : 3);
      canvas.drawLine(Offset(x, ruler), Offset(x, ruler - len), tick);
      if (k % 10 == 0 && stepPx * 10 >= 24) {
        _paintLabel(canvas, '$k', Offset(x + 2, 1), _theme.chromeText, 8);
      }
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, ruler, ruler, size.height - ruler));
    for (final ReportDesignSlot slot in layout.slots) {
      final double capTop = o.dy + slot.caption.top * s;
      final double bodyTop = o.dy + slot.body.top * s;
      final double bodyBottom = o.dy + slot.body.bottom * s;
      canvas.drawRect(
        Rect.fromLTRB(0, capTop, ruler, bodyTop),
        Paint()..color = _theme.frozenFill,
      );
      final int maxV = (slot.body.height / _mm).floor();
      for (int k = 0; k <= maxV; k += every) {
        final double y = bodyTop + k * _mm * s;
        if (y > bodyBottom) {
          break;
        }
        final double len = k % 10 == 0 ? 10 : (k % 5 == 0 ? 6 : 3);
        canvas.drawLine(Offset(ruler, y), Offset(ruler - len, y), tick);
      }
    }
    canvas.restore();
    canvas.drawLine(Offset(ruler, ruler), Offset(size.width, ruler), edge);
    canvas.drawLine(Offset(ruler, ruler), Offset(ruler, size.height), edge);
    canvas.drawRect(Rect.fromLTWH(0, 0, ruler, ruler), bg);
  }

  TextPainter _label(String text, double size, Color color, bool bold) {
    final String key = '$text|$size|${color.toARGB32()}|$bold';
    final TextPainter? hit = _labels[key];
    if (hit != null) {
      return hit;
    }
    if (_labels.length > 400) {
      for (final TextPainter tp in _labels.values) {
        tp.dispose();
      }
      _labels.clear();
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _theme.fontFamily ?? 'Liberation Sans',
          fontFamilyFallback: ReportElementPainter.fallbackFamilies,
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    _labels[key] = tp;
    return tp;
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double size,
  ) {
    _label(text, size, color, false).paint(canvas, at);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..textDirection = TextDirection.ltr
      ..label = 'Report designer canvas'
      ..value = _controller.inspectorTitle;
  }
}
