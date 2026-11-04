import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../core/virtual_viewport.dart';
import '../editor_word/caret_engine.dart';
import '../editor_word/paint_run_text.dart';
import '../embed/office_context_menu.dart';
import '../embed/office_theme.dart';
import '../visual/paint_office_visual.dart';
import 'paint_slide_motion.dart';
import 'snap_guidelines.dart';
import 'transform_handles.dart';

/// Class SlideStage.
class SlideStage extends LeafRenderObjectWidget {
  /// SlideStage API.
  const SlideStage({
    super.key,
    required this.slide,
    this.selected,
    this.selectedShapes = const <PmlShape>[],
    this.config = const OfficeSurfaceConfig(),
    this.hasFocus = false,
    this.semanticsLabel = '',
    this.semanticsValue = '',
    this.viewport,
    this.editing = false,
    this.editCaret = 0,
    this.editBase = 0,
    this.onChanged,
    this.onSelect,
    this.onSelectTableCell,
    this.onTransform,
    this.onTransforms,
    this.onActivate,
    this.onPlaceCaret,
    this.onSelectWord,
    this.onSelectParagraph,
    this.onCommitEdit,
    this.outgoingSlide,
    this.transitionProgress = 1,
    this.playingTransition,
    this.animSamples,
    this.presenting = false,
    this.preview = false,
    this.selectedTableRow = 0,
    this.selectedTableCol = 0,
    this.onShowAdvance,
    this.onContextMenu,
  });

  /// slide API.
  final PmlSlide slide;

  /// selected API.
  final PmlShape? selected;

  /// selectedShapes API.
  final List<PmlShape> selectedShapes;

  /// config API.
  final OfficeSurfaceConfig config;

  /// hasFocus API.
  final bool hasFocus;

  /// semanticsLabel API.
  final String semanticsLabel;

  /// semanticsValue API.
  final String semanticsValue;

  /// viewport API.
  final VirtualViewport? viewport;

  /// editing API.
  final bool editing;

  /// editCaret API.
  final int editCaret;

  /// editBase API.
  final int editBase;

  /// onChanged API.
  final VoidCallback? onChanged;

  /// onSelect API.
  final void Function(PmlShape? shape, {bool additive})? onSelect;

  /// onTransforms API.
  final void Function(Map<PmlShape, PmlTransform> next)? onTransforms;

  /// Function API.
  final void Function(PmlShape shape, int row, int col)? onSelectTableCell;

  /// Function API.
  final void Function(PmlShape shape, PmlTransform next)? onTransform;

  /// selectedTableRow API.
  final int selectedTableRow;

  /// selectedTableCol API.
  final int selectedTableCol;

  /// onActivate API.
  final VoidCallback? onActivate;

  /// Function API.
  final void Function(int index, {bool extend})? onPlaceCaret;

  /// onSelectWord API.
  final ValueChanged<int>? onSelectWord;

  /// onSelectParagraph API.
  final ValueChanged<int>? onSelectParagraph;

  /// onCommitEdit API.
  final VoidCallback? onCommitEdit;

  /// outgoingSlide API.
  final PmlSlide? outgoingSlide;

  /// transitionProgress API.
  final double transitionProgress;

  /// playingTransition API.
  final PmlSlideTransition? playingTransition;

  /// animSamples API.
  final Map<int, PmlAnimSample>? animSamples;

  /// presenting API.
  final bool presenting;

  /// preview API.
  final bool preview;

  /// onShowAdvance API.
  final VoidCallback? onShowAdvance;

  /// onContextMenu API.
  final ValueChanged<OfficeContextHit>? onContextMenu;

  @override
  /// createRenderObject API.
  RenderSlideStage createRenderObject(BuildContext context) {
    return RenderSlideStage(
      slide: slide,
      selected: selected,
      selectedShapes: selectedShapes,
      config: config,
      hasFocus: hasFocus,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
      viewport: viewport ?? VirtualViewport(),
      editing: editing,
      editCaret: editCaret,
      editBase: editBase,
      onChanged: onChanged,
      onSelect: onSelect,
      onSelectTableCell: onSelectTableCell,
      onTransform: onTransform,
      onTransforms: onTransforms,
      onActivate: onActivate,
      selectedTableRow: selectedTableRow,
      selectedTableCol: selectedTableCol,
      onPlaceCaret: onPlaceCaret,
      onSelectWord: onSelectWord,
      onSelectParagraph: onSelectParagraph,
      onCommitEdit: onCommitEdit,
      outgoingSlide: outgoingSlide,
      transitionProgress: transitionProgress,
      playingTransition: playingTransition,
      animSamples: animSamples,
      presenting: presenting,
      preview: preview,
      onShowAdvance: onShowAdvance,
      onContextMenu: onContextMenu,
    );
  }

  @override
  /// updateRenderObject API.
  void updateRenderObject(BuildContext context, RenderSlideStage renderObject) {
    renderObject
      ..slide = slide
      ..selected = selected
      ..selectedShapes = selectedShapes
      ..config = config
      ..hasFocus = hasFocus
      ..semanticsLabel = semanticsLabel
      ..semanticsValue = semanticsValue
      ..editing = editing
      ..editCaret = editCaret
      ..editBase = editBase
      ..onChanged = onChanged
      ..onSelect = onSelect
      ..onSelectTableCell = onSelectTableCell
      ..onTransform = onTransform
      ..onTransforms = onTransforms
      ..onActivate = onActivate
      ..selectedTableRow = selectedTableRow
      ..selectedTableCol = selectedTableCol
      ..onPlaceCaret = onPlaceCaret
      ..onSelectWord = onSelectWord
      ..onSelectParagraph = onSelectParagraph
      ..onCommitEdit = onCommitEdit
      ..outgoingSlide = outgoingSlide
      ..transitionProgress = transitionProgress
      ..playingTransition = playingTransition
      ..animSamples = animSamples
      ..presenting = presenting
      ..preview = preview
      ..onShowAdvance = onShowAdvance
      ..onContextMenu = onContextMenu;
    if (viewport != null) {
      renderObject.viewport = viewport!;
    }
    renderObject.markNeedsPaint();
  }
}

enum _SlideDrag { none, pan, move, resize, rotate, select }

/// Class RenderSlideStage.
class RenderSlideStage extends RenderBox implements MouseTrackerAnnotation {
  /// RenderSlideStage API.
  RenderSlideStage({
    required this.slide,
    this.selected,
    this.selectedShapes = const <PmlShape>[],
    required this.config,
    required this.hasFocus,
    required this.semanticsLabel,
    required this.semanticsValue,
    required this.viewport,
    this.editing = false,
    this.editCaret = 0,
    this.editBase = 0,
    this.onChanged,
    this.onSelect,
    this.onSelectTableCell,
    this.onTransform,
    this.onTransforms,
    this.onActivate,
    this.onPlaceCaret,
    this.onSelectWord,
    this.onSelectParagraph,
    this.onCommitEdit,
    this.outgoingSlide,
    this.transitionProgress = 1,
    this.playingTransition,
    this.animSamples,
    this.presenting = false,
    this.preview = false,
    this.selectedTableRow = 0,
    this.selectedTableCol = 0,
    this.onShowAdvance,
    this.onContextMenu,
  });

  /// slide API.
  PmlSlide slide;

  /// selected API.
  PmlShape? selected;

  /// selectedShapes API.
  List<PmlShape> selectedShapes;

  /// config API.
  OfficeSurfaceConfig config;

  /// hasFocus API.
  bool hasFocus;

  /// semanticsLabel API.
  String semanticsLabel;

  /// semanticsValue API.
  String semanticsValue;

  /// viewport API.
  VirtualViewport viewport;

  /// editing API.
  bool editing;

  /// editCaret API.
  int editCaret;

  /// editBase API.
  int editBase;

  /// selectedTableRow API.
  int selectedTableRow;

  /// selectedTableCol API.
  int selectedTableCol;

  /// onChanged API.
  VoidCallback? onChanged;

  /// onSelect API.
  void Function(PmlShape? shape, {bool additive})? onSelect;

  /// Function API.
  void Function(PmlShape shape, int row, int col)? onSelectTableCell;

  /// Function API.
  void Function(PmlShape shape, PmlTransform next)? onTransform;

  /// onTransforms API.
  void Function(Map<PmlShape, PmlTransform> next)? onTransforms;

  /// onActivate API.
  VoidCallback? onActivate;

  /// Function API.
  void Function(int index, {bool extend})? onPlaceCaret;

  /// onSelectWord API.
  ValueChanged<int>? onSelectWord;

  /// onSelectParagraph API.
  ValueChanged<int>? onSelectParagraph;

  /// onCommitEdit API.
  VoidCallback? onCommitEdit;

  /// outgoingSlide API.
  PmlSlide? outgoingSlide;

  /// transitionProgress API.
  double transitionProgress;

  /// playingTransition API.
  PmlSlideTransition? playingTransition;

  /// animSamples API.
  Map<int, PmlAnimSample>? animSamples;

  /// presenting API.
  bool presenting;

  /// preview API.
  bool preview;

  /// onShowAdvance API.
  VoidCallback? onShowAdvance;

  /// onContextMenu API.
  ValueChanged<OfficeContextHit>? onContextMenu;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;
  var _tapCount = 0;
  Offset? _hoverLocal;

  /// pan API.
  Offset pan = Offset.zero;

  /// snaps API.
  final SnapGuidelines snaps = SnapGuidelines();

  /// none API.
  _SlideDrag _drag = _SlideDrag.none;
  int? _handle;

  /// zero API.
  Offset _lastSlide = Offset.zero;
  PmlTransform? _startTx;
  final Map<PmlShape, PmlTransform> _startTxs = <PmlShape, PmlTransform>{};
  List<PmlShape> _dragShapes = <PmlShape>[];
  Rect _startUnion = Rect.zero;
  Offset _dragOrigin = Offset.zero;
  var _startRotateDeg = 0.0;
  var _paintRotateCursor = false;

  /// VisualImageCache API.
  final VisualImageCache _images = VisualImageCache();

  /// theme API.
  OfficeTheme get _theme => config.theme;

  /// Size API.
  static const Size _slideSize = Size(720, 405);

  double get _fitScale {
    final double pad = preview || presenting ? 0 : 48;
    final double sx = (size.width - pad) / _slideSize.width;
    final double sy = (size.height - pad) / _slideSize.height;
    final double fit = sx < sy ? sx : sy;
    final double safe = fit.isFinite && fit > 0 ? fit : 1;
    if (preview || presenting) {
      return safe;
    }
    return safe * viewport.scale;
  }

  Offset get _slideOrigin {
    final double s = _fitScale;
    if (presenting) {
      return Offset(
        (size.width - _slideSize.width * s) / 2,
        (size.height - _slideSize.height * s) / 2,
      );
    }
    return Offset(
      (size.width - _slideSize.width * s) / 2 + pan.dx,
      (size.height - _slideSize.height * s) / 2 + pan.dy,
    );
  }

  @override
  /// cursor API.
  MouseCursor get cursor => _cursorFor(_hoverLocal);

  @override
  /// onEnter API.
  PointerEnterEventListener? get onEnter => null;

  @override
  /// onExit API.
  PointerExitEventListener? get onExit => (_) {
    _hoverLocal = null;
    if (_paintRotateCursor) {
      _paintRotateCursor = false;
      markNeedsPaint();
    }
  };

  @override
  /// validForMouseTracker API.
  bool get validForMouseTracker => attached;

  @override
  /// hitTestSelf API.
  bool hitTestSelf(Offset position) {
    if (preview) {
      return false;
    }
    _hoverLocal = position;
    return true;
  }

  @override
  /// performLayout API.
  void performLayout() {
    size = constraints.biggest;
    if (size.isInfinite) {
      size = const Size(960, 540);
    }
    viewport.extent = size;
  }

  Offset _toSlide(Offset local) => (local - _slideOrigin) / _fitScale;

  Rect _shapeRect(PmlShape shape) {
    return Rect.fromLTWH(
      shape.transform.xPoints,
      shape.transform.yPoints,
      shape.transform.widthPoints,
      shape.transform.heightPoints,
    );
  }

  void _clampPan() {
    pan = Offset(
      pan.dx.clamp(
        -_maxPan(_slideSize.width * _fitScale, size.width),
        _maxPan(_slideSize.width * _fitScale, size.width),
      ),
      pan.dy.clamp(
        -_maxPan(_slideSize.height * _fitScale, size.height),
        _maxPan(_slideSize.height * _fitScale, size.height),
      ),
    );
  }

  /// Keeps the slide inside the design surface, or covering it when zoomed in.
  static double _maxPan(double slideLen, double viewLen) {
    return ((slideLen - viewLen) / 2).abs();
  }

  Offset _unrotate(PmlShape shape, Offset slide) {
    final double deg = shape.transform.rotationDegrees;
    if (deg.abs() < 0.01) {
      return slide;
    }
    final Offset c = _shapeRect(shape).center;
    final double rad = -deg * math.pi / 180;
    final Offset p = slide - c;
    return Offset(
      c.dx + p.dx * math.cos(rad) - p.dy * math.sin(rad),
      c.dy + p.dx * math.sin(rad) + p.dy * math.cos(rad),
    );
  }

  bool _shapeContains(PmlShape shape, Offset slide) {
    return _shapeRect(shape).contains(_unrotate(shape, slide));
  }

  static bool _listHas(List<PmlShape> list, PmlShape shape) {
    for (final PmlShape item in list) {
      if (identical(item, shape)) {
        return true;
      }
    }
    return false;
  }

  List<PmlShape> get _effectiveSelection {
    if (selectedShapes.isNotEmpty) {
      return selectedShapes;
    }
    if (selected != null) {
      return <PmlShape>[selected!];
    }
    return const <PmlShape>[];
  }

  bool _isSelected(PmlShape shape) => _listHas(_effectiveSelection, shape);

  bool get _usesUnionHandles => _effectiveSelection.length > 1;

  List<PmlShape> _matesOf(PmlShape shape) {
    return PmlArrange.mates(slide.shapes, shape);
  }

  Rect _unionRect(List<PmlShape> shapes) {
    if (shapes.isEmpty) {
      return Rect.zero;
    }
    Rect union = _shapeRect(shapes.first);
    for (int i = 1; i < shapes.length; i++) {
      union = union.expandToInclude(_shapeRect(shapes[i]));
    }
    return union;
  }

  static bool get _additivePressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  int? _hitHandle(PmlShape shape, Offset slide) {
    return TransformHandles(_shapeRect(shape)).hit(_unrotate(shape, slide));
  }

  int? _hitSelectionHandle(Offset slide) {
    final List<PmlShape> items = _effectiveSelection;
    if (items.isEmpty) {
      return null;
    }
    if (items.length == 1) {
      return _hitHandle(items.first, slide);
    }
    return TransformHandles(_unionRect(items)).hit(slide);
  }

  List<PmlShape> _selectionAfterClick(PmlShape shape, bool additive) {
    final List<PmlShape> current = List<PmlShape>.from(_effectiveSelection);
    final List<PmlShape> mates = _matesOf(shape);
    if (additive) {
      final bool allIn = mates.every(
        (PmlShape mate) => _listHas(current, mate),
      );
      if (allIn) {
        current.removeWhere((PmlShape item) => _listHas(mates, item));
      } else {
        for (final PmlShape mate in mates) {
          if (!_listHas(current, mate)) {
            current.add(mate);
          }
        }
      }
      return current;
    }
    if (_listHas(current, shape) && current.length > 1) {
      return current;
    }
    return mates;
  }

  void _beginDragTransforms(List<PmlShape> shapes) {
    _dragShapes = List<PmlShape>.from(shapes);
    _startTxs
      ..clear()
      ..addEntries(
        _dragShapes.map(
          (PmlShape shape) =>
              MapEntry<PmlShape, PmlTransform>(shape, shape.transform),
        ),
      );
    _startUnion = _unionRect(_dragShapes);
    _startTx =
        selected?.transform ??
        (_dragShapes.isEmpty ? null : _dragShapes.first.transform);
  }

  void _rotateTo(PmlShape shape, Offset slide) {
    final PmlTransform start = _startTx ?? shape.transform;
    final Offset c = Offset(
      start.xPoints + start.widthPoints / 2,
      start.yPoints + start.heightPoints / 2,
    );
    final double deg =
        math.atan2(slide.dx - c.dx, c.dy - slide.dy) * 180 / math.pi;
    shape.transform = PmlTransform(
      x: start.x,
      y: start.y,
      cx: start.cx,
      cy: start.cy,
      rot: (deg * 60000).round(),
    );
  }

  static bool _sameTransform(PmlTransform a, PmlTransform b) {
    return a.x == b.x &&
        a.y == b.y &&
        a.cx == b.cx &&
        a.cy == b.cy &&
        a.rot == b.rot;
  }

  MouseCursor _cursorFor(Offset? local) {
    if (local == null || !config.allowsSelection) {
      return SystemMouseCursors.basic;
    }
    if (_drag == _SlideDrag.move || _drag == _SlideDrag.resize) {
      return _drag == _SlideDrag.move
          ? SystemMouseCursors.grabbing
          : _cursorForHandle(_handle ?? 4);
    }
    if (_drag == _SlideDrag.rotate) {
      return SystemMouseCursors.none;
    }
    final Offset at = _toSlide(local);
    if (_effectiveSelection.isNotEmpty &&
        !editing &&
        config.showSlideHandles &&
        config.allowsMutation) {
      final int? handle = _hitSelectionHandle(at);
      if (handle != null) {
        return _cursorForHandle(handle);
      }
    }
    for (final PmlShape shape in slide.shapes.reversed) {
      if (_shapeContains(shape, at)) {
        if (editing && identical(shape, selected) && shape.visual == null) {
          return SystemMouseCursors.text;
        }
        return config.allowsMutation
            ? SystemMouseCursors.grab
            : SystemMouseCursors.basic;
      }
    }
    return SystemMouseCursors.basic;
  }

  static MouseCursor _cursorForHandle(int handle) {
    return switch (handle) {
      0 || 4 => SystemMouseCursors.resizeUpLeftDownRight,
      2 || 6 => SystemMouseCursors.resizeUpRightDownLeft,
      1 || 5 => SystemMouseCursors.resizeUpDown,
      3 || 7 => SystemMouseCursors.resizeLeftRight,
      8 => SystemMouseCursors.none,
      _ => SystemMouseCursors.basic,
    };
  }

  @override
  /// handleEvent API.
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (preview) {
      return;
    }
    if (event is PointerHoverEvent) {
      _hoverLocal = event.localPosition;
      final bool showRotate = _wantsRotateCursor(event.localPosition);
      if (showRotate != _paintRotateCursor) {
        _paintRotateCursor = showRotate;
        markNeedsPaint();
      } else if (_paintRotateCursor) {
        markNeedsPaint();
      }
      return;
    }
    if (event is PointerScrollEvent) {
      if (presenting) {
        return;
      }
      viewport.setScale(
        viewport.scale * (event.scrollDelta.dy > 0 ? 0.95 : 1.05),
      );
      _clampPan();
      markNeedsPaint();
      onChanged?.call();
      return;
    }
    if (event is PointerDownEvent) {
      if (event.buttons == kSecondaryMouseButton && !presenting) {
        final Offset local = _toSlide(event.localPosition);
        PmlShape? hit;
        for (final PmlShape shape in slide.shapes.reversed) {
          if (_shapeContains(shape, local)) {
            hit = shape;
            break;
          }
        }
        onContextMenu?.call(
          OfficeContextHit(
            kind: hit == null
                ? OfficeContextKind.slideCanvas
                : OfficeContextKind.slideShape,
            globalPosition: event.position,
            shape: hit,
          ),
        );
        return;
      }
      if (presenting) {
        onShowAdvance?.call();
        markNeedsPaint();
        onChanged?.call();
        return;
      }
      _hoverLocal = event.localPosition;
      final Offset local = _toSlide(event.localPosition);
      if (editing) {
        _handleTextEditPointerDown(event.localPosition, local);
        return;
      }
      if (config.allowsMutation &&
          config.showSlideHandles &&
          _effectiveSelection.isNotEmpty) {
        final int? handle = _hitSelectionHandle(local);
        if (handle != null) {
          _drag = handle == 8 ? _SlideDrag.rotate : _SlideDrag.resize;
          _handle = handle;
          _lastSlide = local;
          _dragOrigin = local;
          _beginDragTransforms(_effectiveSelection);
          if (_startUnion.width > 0 || _startUnion.height > 0) {
            _startRotateDeg =
                math.atan2(
                  local.dx - _startUnion.center.dx,
                  _startUnion.center.dy - local.dy,
                ) *
                180 /
                math.pi;
          }
          _paintRotateCursor = handle == 8;
          return;
        }
      }
      if (config.allowsSelection) {
        final bool additive = _additivePressed;
        for (final PmlShape shape in slide.shapes.reversed) {
          if (_shapeContains(shape, local)) {
            final int taps = _countTap(event.localPosition);
            final List<PmlShape> next = _selectionAfterClick(shape, additive);
            selected = next.isEmpty ? null : shape;
            selectedShapes = next;
            final PmlTable? table = shape.table;
            if (table != null && !additive) {
              final Rect bounds = _shapeRect(shape);
              final ({int row, int col})? cell = table.hitCell(
                x: bounds.left,
                y: bounds.top,
                width: bounds.width,
                height: bounds.height,
                localX: local.dx,
                localY: local.dy,
              );
              if (cell != null) {
                onSelectTableCell?.call(shape, cell.row, cell.col);
              } else {
                onSelect?.call(shape, additive: additive);
              }
            } else {
              onSelect?.call(shape, additive: additive);
            }
            if (!additive &&
                taps >= 2 &&
                config.allowsMutation &&
                shape.visual == null) {
              final int index = _hitTextIndex(shape, local);
              onActivate?.call();
              onPlaceCaret?.call(index);
              if (taps >= 3) {
                onSelectParagraph?.call(index);
              } else {
                onSelectWord?.call(index);
              }
              _drag = _SlideDrag.select;
              _lastSlide = local;
              _startTx = null;
              _dragShapes = <PmlShape>[];
              _startTxs.clear();
            } else if (config.allowsMutation && next.isNotEmpty) {
              _drag = _SlideDrag.move;
              _lastSlide = local;
              _dragOrigin = local;
              _beginDragTransforms(next);
            }
            markNeedsPaint();
            onChanged?.call();
            return;
          }
        }
        selected = null;
        selectedShapes = <PmlShape>[];
        onSelect?.call(null, additive: false);
      }
      _drag = _SlideDrag.pan;
      _lastSlide = event.localPosition;
      markNeedsPaint();
      onChanged?.call();
    } else if (event is PointerMoveEvent) {
      _hoverLocal = event.localPosition;
      if (_drag == _SlideDrag.select && selected != null) {
        final Offset local = _toSlide(event.localPosition);
        if (_shapeContains(selected!, local) || editing) {
          onPlaceCaret?.call(_hitTextIndex(selected!, local), extend: true);
          markNeedsPaint();
          onChanged?.call();
        }
        return;
      }
      if (_drag == _SlideDrag.pan) {
        pan += event.localPosition - _lastSlide;
        _lastSlide = event.localPosition;
        _clampPan();
        markNeedsPaint();
        return;
      }
      if (!config.allowsMutation || _dragShapes.isEmpty || _startTxs.isEmpty) {
        return;
      }
      final Offset local = _toSlide(event.localPosition);
      final Offset delta = local - _lastSlide;
      _lastSlide = local;
      if (_drag == _SlideDrag.move) {
        Rect moving = _unionRect(_dragShapes).shift(delta);
        _loadSnapTargets();
        moving = moving.shift(snaps.snap(moving));
        final Offset applied = moving.topLeft - _unionRect(_dragShapes).topLeft;
        for (final PmlShape shape in _dragShapes) {
          _applyRect(shape, _shapeRect(shape).shift(applied));
        }
      } else if (_drag == _SlideDrag.resize && _handle != null) {
        _resizeSelection(delta, local, _handle!);
      } else if (_drag == _SlideDrag.rotate) {
        _rotateSelectionTo(local);
      }
      markNeedsPaint();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if ((_drag == _SlideDrag.move ||
              _drag == _SlideDrag.resize ||
              _drag == _SlideDrag.rotate) &&
          _startTxs.isNotEmpty) {
        final Map<PmlShape, PmlTransform> next = <PmlShape, PmlTransform>{
          for (final PmlShape shape in _dragShapes) shape: shape.transform,
        };
        var changed = false;
        for (final MapEntry<PmlShape, PmlTransform> entry
            in _startTxs.entries) {
          if (!_sameTransform(entry.value, next[entry.key] ?? entry.value)) {
            changed = true;
          }
          entry.key.transform = entry.value;
        }
        if (changed) {
          if (onTransforms != null) {
            onTransforms!(next);
          } else if (onTransform != null && selected != null) {
            final PmlTransform? after = next[selected!];
            if (after != null) {
              onTransform!(selected!, after);
            }
          }
        }
        onChanged?.call();
      }
      _drag = _SlideDrag.none;
      _handle = null;
      _startTx = null;
      _startTxs.clear();
      _dragShapes = <PmlShape>[];
      snaps.clear();
      _paintRotateCursor = _wantsRotateCursor(event.localPosition);
      markNeedsPaint();
    }
  }

  void _handleTextEditPointerDown(Offset window, Offset local) {
    if (selected != null && _shapeContains(selected!, local)) {
      final bool extend = HardwareKeyboard.instance.isShiftPressed;
      final int taps = extend ? 1 : _countTap(window);
      final int index = _hitTextIndex(selected!, local);
      onPlaceCaret?.call(index, extend: extend);
      if (!extend && taps >= 3) {
        onSelectParagraph?.call(index);
      } else if (!extend && taps == 2) {
        onSelectWord?.call(index);
      }
      _drag = _SlideDrag.select;
      _lastSlide = local;
      markNeedsPaint();
      onChanged?.call();
      return;
    }
    onCommitEdit?.call();
    if (config.allowsSelection) {
      for (final PmlShape shape in slide.shapes.reversed) {
        if (_shapeContains(shape, local)) {
          selected = shape;
          selectedShapes = _matesOf(shape);
          onSelect?.call(shape, additive: false);
          _drag = _SlideDrag.none;
          _startTx = null;
          markNeedsPaint();
          onChanged?.call();
          return;
        }
      }
      selected = null;
      selectedShapes = <PmlShape>[];
      onSelect?.call(null, additive: false);
    }
    _drag = _SlideDrag.none;
    _startTx = null;
    markNeedsPaint();
    onChanged?.call();
  }

  int _countTap(Offset window) {
    final DateTime now = DateTime.now();
    final bool chained =
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= kDoubleTapTimeout &&
        _lastTapPos != null &&
        (window - _lastTapPos!).distance <= kDoubleTapSlop;
    _tapCount = chained ? _tapCount + 1 : 1;
    if (_tapCount > 3) {
      _tapCount = 1;
    }
    _lastTapAt = now;
    _lastTapPos = window;
    return _tapCount;
  }

  bool _wantsRotateCursor(Offset local) {
    if (editing || !config.allowsMutation || !config.showSlideHandles) {
      return false;
    }
    if (_drag == _SlideDrag.rotate) {
      return true;
    }
    if (_effectiveSelection.isEmpty) {
      return false;
    }
    return _hitSelectionHandle(_toSlide(local)) == 8;
  }

  void _loadSnapTargets() {
    snaps.clear();
    snaps.addSlide(_slideSize);
    for (final PmlShape shape in slide.shapes) {
      if (!_listHas(_dragShapes, shape) && !_isSelected(shape)) {
        snaps.addTarget(_shapeRect(shape));
      }
    }
  }

  int _hitTextIndex(PmlShape shape, Offset slidePoint) {
    final Rect r = _shapeRect(shape);
    final Offset local = _unrotate(shape, slidePoint);
    if (shape.table != null) {
      final ({int row, int col})? cell = shape.table!.hitCell(
        x: r.left,
        y: r.top,
        width: r.width,
        height: r.height,
        localX: local.dx,
        localY: local.dy,
      );
      final PmlTableCell target = shape.table!.cellAt(
        cell?.row ?? selectedTableRow,
        cell?.col ?? selectedTableCol,
      );
      final ({double x, double y, double width, double height}) box = shape
          .table!
          .cellBounds(
            x: r.left,
            y: r.top,
            width: r.width,
            height: r.height,
            row: cell?.row ?? selectedTableRow,
            col: cell?.col ?? selectedTableCol,
          );
      final TextPainter painter = PaintRunText.plain(
        text: target.text,
        fontSize: 13,
        color: _hexColor(target.textColor, const Color(0xFF1A1A1A)),
        themeFamily: _theme.fontFamily,
        maxLines: 4,
        rtl: shape.table!.rightToLeft,
      )..layout(maxWidth: (box.width - 8).clamp(8, box.width));
      return PaintRunText.hitIndex(
        painter,
        Offset(local.dx - box.x - 4, local.dy - box.y - 3),
        target.text.length,
      );
    }
    final TextPainter painter = _shapePainter(
      shape,
      shape.text,
      r,
      _textColor(shape),
    )..layout(maxWidth: r.width - 16);
    return PaintRunText.hitIndex(
      painter,
      Offset(local.dx - r.left - 8, local.dy - r.top - 8),
      shape.text.length,
    );
  }

  Color _textColor(PmlShape shape) {
    final int? own = int.tryParse(shape.textColor, radix: 16);
    if (own != null) {
      return Color(0xFF000000 | own);
    }
    final int? fill = int.tryParse(shape.fillColor, radix: 16);
    final int rgb = fill ?? (_theme.slideBackground.toARGB32() & 0xFFFFFF);
    final int r = (rgb >> 16) & 0xFF;
    final int g = (rgb >> 8) & 0xFF;
    final int b = rgb & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) < 140
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1A1A1A);
  }

  /// Boxes too short for a line (e.g. `cy="0"` text boxes) grow with their
  /// text, as PowerPoint does, instead of clipping it away.
  static bool _growsWithText(Rect r) => r.height < 24;

  /// Fill of a shape, or nothing when [PmlShape.fillColor] is empty (no fill).
  void _paintShapeFill(Canvas canvas, PmlShape shape, Rect r, String hex) {
    final int? fill = int.tryParse(hex, radix: 16);
    if (fill != null) {
      canvas.drawRect(r, Paint()..color = Color(0xFF000000 | fill));
    } else if (shape.placeholder &&
        shape.text.isEmpty &&
        !presenting &&
        config.allowsMutation) {
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x66808080),
      );
    }
  }

  TextPainter _shapePainter(PmlShape shape, String text, Rect r, Color color) {
    final int lines = _growsWithText(r)
        ? 12
        : ((r.height - 12) / 18).floor().clamp(1, 12);
    final bool rtl = shape.rightToLeft ?? PaintRunText.looksRtl(text);
    final TextAlign align = switch (shape.textAlign) {
      PmlTextAlign.center => TextAlign.center,
      PmlTextAlign.right => TextAlign.right,
      PmlTextAlign.justify => TextAlign.justify,
      PmlTextAlign.left =>
        shape.rightToLeft == null && rtl ? TextAlign.right : TextAlign.left,
    };
    return PaintRunText.plain(
      text: text,
      fontSize: 16,
      color: color,
      themeFamily: _theme.fontFamily,
      maxLines: lines,
      align: align,
      rtl: rtl,
    );
  }

  Color _hexColor(String hex, Color fallback) {
    if (hex.isEmpty) {
      return fallback;
    }
    final int? rgb = int.tryParse(hex, radix: 16);
    if (rgb == null) {
      return fallback;
    }
    return Color(0xFF000000 | rgb);
  }

  void _paintTable(Canvas canvas, PmlShape shape, Rect r) {
    final PmlTable table = shape.table!;
    canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      r,
      Paint()
        ..color = const Color(0xFF1F1F1F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final bool isSelected = identical(shape, selected);
    for (int row = 0; row < table.rowCount; row++) {
      for (int col = 0; col < table.colCount; col++) {
        final PmlTableCell cell = table.cellAt(row, col);
        final ({double x, double y, double width, double height}) box = table
            .cellBounds(
              x: r.left,
              y: r.top,
              width: r.width,
              height: r.height,
              row: row,
              col: col,
            );
        final Rect cellRect = Rect.fromLTWH(
          box.x,
          box.y,
          box.width,
          box.height,
        );
        canvas.drawRect(
          cellRect,
          Paint()..color = _hexColor(cell.fillColor, const Color(0xFFFFFFFF)),
        );
        canvas.drawRect(
          cellRect,
          Paint()
            ..color = const Color(0xFF6B6B6B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        final bool active =
            isSelected && row == selectedTableRow && col == selectedTableCol;
        if (active) {
          canvas.drawRect(
            cellRect.deflate(1),
            Paint()
              ..color = _theme.selectionFill
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        final bool editingCell = editing && active;
        final String body = cell.text;
        if (body.isEmpty && !editingCell) {
          continue;
        }
        final Color ink = _hexColor(cell.textColor, const Color(0xFF1A1A1A));
        final TextPainter painter = PaintRunText.plain(
          text: body.isEmpty ? ' ' : body,
          fontSize: 13,
          color: ink,
          themeFamily: _theme.fontFamily,
          maxLines: 4,
          rtl: table.rightToLeft,
        )..layout(maxWidth: (box.width - 8).clamp(8, box.width));
        final Offset origin = Offset(box.x + 4, box.y + 3);
        if (editingCell && editBase != editCaret) {
          final int start = editBase < editCaret ? editBase : editCaret;
          final int end = editBase > editCaret ? editBase : editCaret;
          for (final ui.TextBox boxSel in painter.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
          )) {
            canvas.drawRect(
              Rect.fromLTRB(
                boxSel.left,
                boxSel.top,
                boxSel.right,
                boxSel.bottom,
              ).shift(origin),
              Paint()..color = _theme.selectionFill,
            );
          }
        }
        painter.paint(canvas, origin);
        if (editingCell && config.showsCaret && hasFocus) {
          final Offset caret = painter.getOffsetForCaret(
            TextPosition(offset: editCaret.clamp(0, body.length)),
            const Rect.fromLTWH(0, 0, 0, 14),
          );
          CaretEngine.paintFlagged(
            canvas,
            stem: Rect.fromLTWH(
              origin.dx + caret.dx,
              origin.dy + caret.dy,
              1.0,
              16,
            ),
            color: ink,
            rtl:
                table.rightToLeft ||
                config.textDirection == TextDirection.rtl ||
                PaintRunText.looksRtl(body),
          );
        }
      }
    }
  }

  void _paintShapeText(Canvas canvas, PmlShape shape, Rect r, {String? text}) {
    final bool isEdit = editing && identical(shape, selected);
    final String body = text ?? shape.text;
    if (body.isEmpty && !isEdit) {
      return;
    }
    canvas.save();
    if (!_growsWithText(r)) {
      canvas.clipRect(r);
    }
    final Color color = _textColor(shape);
    final TextPainter painter = _shapePainter(shape, body, r, color)
      ..layout(maxWidth: r.width - 16);
    final Offset origin = Offset(r.left + 8, r.top + 8);
    if (isEdit && editBase != editCaret) {
      final int start = editBase < editCaret ? editBase : editCaret;
      final int end = editBase > editCaret ? editBase : editCaret;
      for (final ui.TextBox box in painter.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        canvas.drawRect(
          Rect.fromLTRB(box.left, box.top, box.right, box.bottom).shift(origin),
          Paint()..color = _theme.selectionFill,
        );
      }
    }
    painter.paint(canvas, origin);
    if (isEdit && config.showsCaret && hasFocus) {
      final Offset caret = painter.getOffsetForCaret(
        TextPosition(offset: editCaret.clamp(0, shape.text.length)),
        const Rect.fromLTWH(0, 0, 0, 16),
      );
      CaretEngine.paintFlagged(
        canvas,
        stem: Rect.fromLTWH(
          origin.dx + caret.dx,
          origin.dy + caret.dy,
          1.0,
          18,
        ),
        color: color,
        rtl:
            shape.rightToLeft ??
            (PaintRunText.looksRtl(body) ||
                config.textDirection == TextDirection.rtl),
      );
    }
    canvas.restore();
  }

  void _paintMorph(
    Canvas canvas,
    PmlSlide outgoing,
    PmlSlide incoming,
    double progress,
  ) {
    final double p = progress.clamp(0.0, 1.0);
    final List<PmlMorphPair> pairs = PmlMorph.pair(outgoing, incoming);
    _paintSlideBody(
      canvas,
      outgoing,
      skipIds: PmlMorph.keepIds(pairs, outgoing: true),
    );
    canvas.saveLayer(
      Offset.zero & _slideSize,
      Paint()..color = Color.fromRGBO(255, 255, 255, p),
    );
    _paintSlideBody(
      canvas,
      incoming,
      skipIds: PmlMorph.keepIds(pairs, outgoing: false),
    );
    canvas.restore();
    for (final PmlMorphFrame frame in PmlMorph.frames(outgoing, incoming, p)) {
      if (frame.role != PmlMorphRole.keep) {
        continue;
      }
      _paintMorphFrame(canvas, frame);
    }
  }

  void _paintMorphFrame(Canvas canvas, PmlMorphFrame frame) {
    final Rect r = Rect.fromLTWH(
      frame.transform.xPoints,
      frame.transform.yPoints,
      frame.transform.widthPoints,
      frame.transform.heightPoints,
    );
    if (r.width <= 0 || r.height <= 0) {
      return;
    }
    canvas.save();
    final double deg = frame.transform.rotationDegrees;
    if (deg.abs() >= 0.01) {
      canvas.translate(r.center.dx, r.center.dy);
      canvas.rotate(deg * math.pi / 180);
      canvas.translate(-r.center.dx, -r.center.dy);
    }
    _paintShapeInRect(
      canvas,
      frame.shape,
      r,
      text: frame.text,
      fillColor: frame.fillColor,
    );
    canvas.restore();
  }

  void _paintShapeInRect(
    Canvas canvas,
    PmlShape shape,
    Rect r, {
    String? text,
    String? fillColor,
  }) {
    canvas.save();
    if (shape.table != null) {
      _paintTable(canvas, shape, r);
    } else if (shape.visual != null) {
      PaintOfficeVisual.paint(
        canvas,
        r,
        shape.visual!,
        fontFamily: _theme.fontFamily ?? PaintRunText.fontFallbacks.first,
        images: _images,
        onImageReady: markNeedsPaint,
      );
    } else {
      _paintShapeFill(canvas, shape, r, fillColor ?? shape.fillColor);
      _paintShapeText(canvas, shape, r, text: text);
    }
    canvas.restore();
  }

  void _paintMediaBadge(Canvas canvas, Rect r) {
    final Rect badge = Rect.fromLTWH(r.left + 6, r.bottom - 28, 22, 22);
    canvas.drawCircle(
      badge.center,
      11,
      Paint()..color = const Color(0xCC111111),
    );
    canvas.drawPath(
      Path()
        ..moveTo(badge.left + 7, badge.top + 5)
        ..lineTo(badge.right - 5, badge.center.dy)
        ..lineTo(badge.left + 7, badge.bottom - 5)
        ..close(),
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  void _paintSlideBody(
    Canvas canvas,
    PmlSlide target, {
    Map<int, PmlAnimSample>? samples,
    Set<int>? skipIds,
  }) {
    canvas.drawRect(
      Offset.zero & _slideSize,
      Paint()..color = _theme.slideBackground,
    );
    for (final PmlShape shape in target.shapes) {
      if (skipIds != null && skipIds.contains(shape.id)) {
        continue;
      }
      final PmlAnimSample sample = samples?[shape.id] ?? PmlAnimSample.identity;
      if (!sample.visible || sample.opacity <= 0.01) {
        continue;
      }
      final Rect r = _shapeRect(shape);
      canvas.save();
      PaintSlideMotion.applyShapeSample(canvas, r, sample);
      _rotateCanvas(canvas, shape, r);
      if (shape.table != null) {
        _paintTable(canvas, shape, r);
      } else if (shape.visual != null) {
        PaintOfficeVisual.paint(
          canvas,
          r,
          shape.visual!,
          fontFamily: _theme.fontFamily ?? PaintRunText.fontFallbacks.first,
          images: _images,
          onImageReady: markNeedsPaint,
        );
      } else {
        _paintShapeFill(canvas, shape, r, shape.fillColor);
        _paintShapeText(canvas, shape, r);
      }
      if (shape.hasMedia) {
        _paintMediaBadge(canvas, r);
      }
      if (!presenting &&
          _isSelected(shape) &&
          config.allowsSelection &&
          config.showSlideHandles) {
        if (_usesUnionHandles) {
          canvas.drawRect(
            r,
            Paint()
              ..color = _theme.handleStroke
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        } else {
          TransformHandles(r).paint(
            canvas,
            strokeColor: _theme.handleStroke,
            fillColor: _theme.handleFill,
            showKnobs: !editing,
          );
        }
      }
      PaintSlideMotion.restoreShapeSample(canvas, sample);
      canvas.restore();
    }
    if (!presenting &&
        _usesUnionHandles &&
        config.allowsSelection &&
        config.showSlideHandles &&
        identical(target, slide)) {
      TransformHandles(_unionRect(_effectiveSelection)).paint(
        canvas,
        strokeColor: _theme.handleStroke,
        fillColor: _theme.handleFill,
        showKnobs: !editing,
      );
    }
  }

  void _rotateCanvas(Canvas canvas, PmlShape shape, Rect r) {
    final double deg = shape.transform.rotationDegrees;
    if (deg.abs() < 0.01) {
      return;
    }
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-r.center.dx, -r.center.dy);
  }

  void _applyRect(PmlShape shape, Rect rect) {
    shape.transform = PmlTransform(
      x: (rect.left * 12700).round(),
      y: (rect.top * 12700).round(),
      cx: (rect.width * 12700).round().clamp(12700, 100000000),
      cy: (rect.height * 12700).round().clamp(12700, 100000000),
      rot: shape.transform.rot,
    );
  }

  Rect _applyHandleDelta(Rect r, Offset delta, int handle) {
    switch (handle) {
      case 0:
        r = Rect.fromLTRB(
          r.left + delta.dx,
          r.top + delta.dy,
          r.right,
          r.bottom,
        );
      case 1:
        r = Rect.fromLTRB(r.left, r.top + delta.dy, r.right, r.bottom);
      case 2:
        r = Rect.fromLTRB(
          r.left,
          r.top + delta.dy,
          r.right + delta.dx,
          r.bottom,
        );
      case 3:
        r = Rect.fromLTRB(r.left, r.top, r.right + delta.dx, r.bottom);
      case 4:
        r = Rect.fromLTRB(
          r.left,
          r.top,
          r.right + delta.dx,
          r.bottom + delta.dy,
        );
      case 5:
        r = Rect.fromLTRB(r.left, r.top, r.right, r.bottom + delta.dy);
      case 6:
        r = Rect.fromLTRB(
          r.left + delta.dx,
          r.top,
          r.right,
          r.bottom + delta.dy,
        );
      case 7:
        r = Rect.fromLTRB(r.left + delta.dx, r.top, r.right, r.bottom);
      default:
        break;
    }
    return r;
  }

  void _resize(PmlShape shape, Offset delta, int handle) {
    final Rect r = _applyHandleDelta(_shapeRect(shape), delta, handle);
    if (r.width > 8 && r.height > 8) {
      _applyRect(shape, r);
    }
  }

  void _resizeSelection(Offset delta, Offset local, int handle) {
    if (_dragShapes.length <= 1) {
      final PmlShape? shape = _dragShapes.isEmpty
          ? selected
          : _dragShapes.first;
      if (shape != null) {
        _resize(shape, delta, handle);
      }
      return;
    }
    final Rect from = _startUnion;
    if (from.width <= 0 || from.height <= 0) {
      return;
    }
    final Rect to = _applyHandleDelta(from, local - _dragOrigin, handle);
    if (to.width <= 8 || to.height <= 8) {
      return;
    }
    final double sx = to.width / from.width;
    final double sy = to.height / from.height;
    for (final PmlShape shape in _dragShapes) {
      final PmlTransform start = _startTxs[shape] ?? shape.transform;
      final double nx = to.left + (start.xPoints - from.left) * sx;
      final double ny = to.top + (start.yPoints - from.top) * sy;
      _applyRect(
        shape,
        Rect.fromLTWH(nx, ny, start.widthPoints * sx, start.heightPoints * sy),
      );
    }
  }

  void _rotateSelectionTo(Offset slide) {
    if (_dragShapes.length <= 1) {
      final PmlShape? shape =
          selected ?? (_dragShapes.isEmpty ? null : _dragShapes.first);
      if (shape != null) {
        _rotateTo(shape, slide);
      }
      return;
    }
    final Offset c = _startUnion.center;
    final double deg =
        math.atan2(slide.dx - c.dx, c.dy - slide.dy) * 180 / math.pi;
    final double delta = deg - _startRotateDeg;
    final double rad = delta * math.pi / 180;
    final double cos = math.cos(rad);
    final double sin = math.sin(rad);
    for (final PmlShape shape in _dragShapes) {
      final PmlTransform start = _startTxs[shape] ?? shape.transform;
      final Offset sc = Offset(
        start.xPoints + start.widthPoints / 2,
        start.yPoints + start.heightPoints / 2,
      );
      final Offset p = sc - c;
      final Offset np = Offset(
        c.dx + p.dx * cos - p.dy * sin,
        c.dy + p.dx * sin + p.dy * cos,
      );
      shape.transform = PmlTransform(
        x: ((np.dx - start.widthPoints / 2) * 12700).round(),
        y: ((np.dy - start.heightPoints / 2) * 12700).round(),
        cx: start.cx,
        cy: start.cy,
        rot: start.rot + (delta * 60000).round(),
      );
    }
  }

  @override
  /// describeSemanticsConfiguration API.
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = semanticsLabel
      ..value = semanticsValue
      ..isReadOnly = !this.config.allowsMutation
      ..textDirection = this.config.textDirection;
  }

  @override
  /// paint API.
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = preview
            ? _theme.slideBackground
            : (presenting ? const Color(0xFF000000) : _theme.canvasBackground),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(_slideOrigin.dx, _slideOrigin.dy);
    canvas.scale(_fitScale);
    canvas.clipRect(Offset.zero & _slideSize);
    final PmlSlide? outgoing = outgoingSlide;
    final PmlSlideTransition? trans = playingTransition;
    if (presenting && outgoing != null && trans != null) {
      if (trans.kind == PmlTransitionKind.morph) {
        _paintMorph(canvas, outgoing, slide, transitionProgress);
      } else {
        PaintSlideMotion.paintTransition(
          canvas: canvas,
          size: _slideSize,
          transition: trans,
          progress: transitionProgress,
          background: _theme.slideBackground,
          paintOutgoing: (Canvas c) =>
              _paintSlideBody(c, outgoing, samples: null),
          paintIncoming: (Canvas c) =>
              _paintSlideBody(c, slide, samples: animSamples),
        );
      }
    } else {
      _paintSlideBody(canvas, slide, samples: presenting ? animSamples : null);
    }
    if (_drag == _SlideDrag.move && !presenting) {
      snaps.paint(canvas, _slideSize, color: _theme.snapGuide);
    }
    canvas.restore();
    if (hasFocus && !presenting && !preview) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = _theme.focusRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if ((_paintRotateCursor || _drag == _SlideDrag.rotate) &&
        _hoverLocal != null) {
      TransformHandles.paintRotateCursor(
        canvas,
        _hoverLocal!,
        color: _theme.chromeText,
      );
    }
    canvas.restore();
  }
}
