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
import '../embed/office_host_fonts.dart';
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
    this.master,
    this.slideSize,
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

  /// Optional master context for resolving direct background edits at paint
  /// time. Without it, the slide's resolved background snapshot is used.
  final PmlMaster? master;

  /// Native presentation dimensions in points.
  final Size? slideSize;

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
      master: master,
      slideSize: slideSize,
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
      ..master = master
      ..slideSize = slideSize
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

class _SlideParagraph {
  const _SlideParagraph({
    required this.painter,
    required this.offset,
    required this.start,
    required this.length,
    required this.prefixLength,
    this.bullet,
    this.bulletOffset,
  });

  final TextPainter painter;
  final Offset offset;
  final int start;
  final int length;
  final int prefixLength;
  final TextPainter? bullet;
  final Offset? bulletOffset;

  int get end => start + length;

  void dispose() {
    painter.dispose();
    bullet?.dispose();
  }
}

enum _SlideDrag { none, pan, move, resize, rotate, select }

/// Class RenderSlideStage.
class RenderSlideStage extends RenderBox implements MouseTrackerAnnotation {
  /// RenderSlideStage API.
  RenderSlideStage({
    required this.slide,
    this.master,
    this.slideSize,
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

  /// Master context used to resolve inherited paper without model mutation.
  PmlMaster? master;

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

  @override
  void dispose() {
    _images.dispose();
    super.dispose();
  }

  /// theme API.
  OfficeTheme get _theme => config.theme;

  /// Size API.
  Size? slideSize;

  Size get _slideSize => slideSize ?? const Size(720, 405);

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
    shape.transform = start.copyWith(rot: (deg * 60000).round());
  }

  static bool _sameTransform(PmlTransform a, PmlTransform b) {
    return a.x == b.x &&
        a.y == b.y &&
        a.cx == b.cx &&
        a.cy == b.cy &&
        a.rot == b.rot &&
        a.flipH == b.flipH &&
        a.flipV == b.flipV;
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
    final color = _textColor(shape);
    final textRect = _shapeTextRect(shape, r);
    final paragraphs = shape.resolvedRichText;
    if (paragraphs.isNotEmpty) {
      final layout = _layoutRichText(shape, paragraphs, textRect, color);
      try {
        final blockOrigin = _shapeTextOrigin(
          shape,
          textRect,
          _richTextHeight(layout),
        );
        final hit = local - blockOrigin;
        final paragraph = layout.lastWhere(
          (entry) => entry.offset.dy <= hit.dy,
          orElse: () => layout.first,
        );
        final position = paragraph.painter
            .getPositionForOffset(hit - paragraph.offset)
            .offset;
        return (paragraph.start +
                (position - paragraph.prefixLength).clamp(0, paragraph.length))
            .clamp(0, shape.text.length);
      } finally {
        for (final paragraph in layout) {
          paragraph.dispose();
        }
      }
    }
    final painter = _shapePainter(shape, shape.text, textRect, color);
    try {
      return PaintRunText.hitIndex(
        painter,
        local - _plainTextOrigin(shape, textRect, painter),
        shape.text.length,
      );
    } finally {
      painter.dispose();
    }
  }

  Color _textColor(PmlShape shape, {Color? background}) {
    final int? own = int.tryParse(shape.textColor, radix: 16);
    if (own != null) {
      final Color authored = Color(0xFF000000 | own);
      return background == null
          ? authored
          : _theme.resolveDocumentColor(authored, background: background);
    }
    final int? fill = int.tryParse(shape.fillColor, radix: 16);
    final int rgb =
        fill ?? ((background ?? _slidePaper(slide)).toARGB32() & 0xFFFFFF);
    final int r = (rgb >> 16) & 0xFF;
    final int g = (rgb >> 8) & 0xFF;
    final int b = rgb & 0xFF;
    return (0.299 * r + 0.587 * g + 0.114 * b) < 140
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF1A1A1A);
  }

  Color? _solidTextBackground(
    PmlSlide target,
    PmlShape shape,
    Rect rect, {
    Map<int, PmlAnimSample>? samples,
    Set<int>? skipIds,
  }) {
    if (!_theme.adaptDocumentColors) return null;
    final sample = samples?[shape.id] ?? PmlAnimSample.identity;
    if (!_staticSample(sample)) return null;
    final int? own = int.tryParse(shape.fillColor, radix: 16);
    if (own != null &&
        !_growsWithText(rect) &&
        shape.preset == PmlShapePreset.rect) {
      return Color(0xFF000000 | own);
    }
    if (own != null) return null;
    if (shape.transform.rotationDegrees.abs() >= 0.01) return null;
    // Very short imported text boxes grow to fit their contents. Include that
    // possible extent before deciding that the dark slide lies beneath them.
    final Rect textBounds = _growsWithText(rect)
        ? Rect.fromLTWH(rect.left, rect.top, rect.width, 208)
        : rect;
    Color? background = _slidePaper(target);
    final int inheritedCount = target.backgroundShapes.length;
    var precedingIndex = 0;
    for (final previous in target.backgroundShapes.followedBy(target.shapes)) {
      final bool inherited = precedingIndex++ < inheritedCount;
      if (inherited && _hiddenBackgroundPicture(target, previous)) continue;
      if (!inherited && identical(previous, shape)) break;
      if (!inherited && (skipIds?.contains(previous.id) ?? false)) continue;
      final previousSample = inherited
          ? PmlAnimSample.identity
          : samples?[previous.id] ?? PmlAnimSample.identity;
      if (!previousSample.visible || previousSample.opacity <= 0.01) continue;
      // Animated transforms/clips can expose arbitrary mixed backing. The
      // authored colour is safer than treating it as untouched dark paper.
      if (!_staticSample(previousSample)) return null;
      final Rect previousRect = _shapeRect(previous);
      final double radians = previous.transform.rotationDegrees * math.pi / 180;
      final double cosine = math.cos(radians).abs();
      final double sine = math.sin(radians).abs();
      final Rect bounds = Rect.fromCenter(
        center: previousRect.center,
        width: previousRect.width * cosine + previousRect.height * sine,
        height: previousRect.width * sine + previousRect.height * cosine,
      );
      if (!bounds.overlaps(textBounds)) continue;
      if (previous.visual != null ||
          previous.table != null ||
          previous.hasMedia ||
          previous.text.isNotEmpty ||
          previous.preset != PmlShapePreset.rect ||
          previous.transform.rotationDegrees.abs() >= 0.01) {
        background = null;
        continue;
      }
      final int? fill = int.tryParse(previous.fillColor, radix: 16);
      if (fill == null) continue;
      final bool covers =
          previousRect.left <= textBounds.left &&
          previousRect.top <= textBounds.top &&
          previousRect.right >= textBounds.right &&
          previousRect.bottom >= textBounds.bottom;
      background = covers ? Color(0xFF000000 | fill) : null;
    }
    return background;
  }

  static bool _staticSample(PmlAnimSample sample) =>
      sample.opacity >= 0.999 &&
      !sample.usesClip &&
      sample.dx == 0 &&
      sample.dy == 0 &&
      (sample.scale - 1).abs() <= 0.001 &&
      sample.rotationDeg.abs() <= 0.05;

  /// Boxes too short for a line (e.g. `cy="0"` text boxes) grow with their
  /// text, as PowerPoint does, instead of clipping it away.
  static bool _growsWithText(Rect r) => r.height < 24;

  /// Fill of a shape, or nothing when [PmlShape.fillColor] is empty (no fill).
  void _paintShapeFill(
    Canvas canvas,
    PmlShape shape,
    Rect r,
    String hex, {
    PmlTransform? transform,
  }) {
    if (shape.preset == PmlShapePreset.connector) {
      final bool hasStroke = shape.strokeColor.isNotEmpty;
      final int? stroke = int.tryParse(
        hasStroke ? shape.strokeColor : hex,
        radix: 16,
      );
      if (stroke != null) {
        final PmlTransform geometry = transform ?? shape.transform;
        final bool flipH = geometry.flipH;
        final bool flipV = geometry.flipV;
        canvas.drawLine(
          Offset(flipH ? r.right : r.left, flipV ? r.bottom : r.top),
          Offset(flipH ? r.left : r.right, flipV ? r.top : r.bottom),
          Paint()
            ..color = Color(0xFF000000 | stroke)
            ..strokeWidth = hasStroke
                ? (shape.strokeWidth <= 0 ? 1 : shape.strokeWidth)
                : 1.6,
        );
      }
      return;
    }
    final int? fill = int.tryParse(hex, radix: 16);
    if (fill != null) {
      final Paint paint = Paint()
        ..color = Color(0xFF000000 | fill).withValues(alpha: shape.fillOpacity);
      final PmlGradientFill? gradient = shape.gradient;
      if (gradient != null && gradient.stops.length >= 2) {
        final List<Color> colors = <Color>[
          for (final stop in gradient.stops)
            Color(0xFF000000 | (int.tryParse(stop.color, radix: 16) ?? 0)),
        ];
        final List<double> stops = <double>[
          for (final stop in gradient.stops) stop.position,
        ];
        if (gradient.radial) {
          paint.shader = ui.Gradient.radial(
            r.center,
            math.sqrt(r.width * r.width + r.height * r.height) / 2,
            colors,
            stops,
          );
        } else {
          final double radians = gradient.angleDegrees * math.pi / 180;
          final Offset direction = Offset(math.cos(radians), math.sin(radians));
          final double radius =
              (r.width * direction.dx.abs() + r.height * direction.dy.abs()) /
              2;
          paint.shader = ui.Gradient.linear(
            r.center - direction * radius,
            r.center + direction * radius,
            colors,
            stops,
          );
        }
      }
      _paintShapeGeometry(canvas, shape, r, paint, transform: transform);
    }
    final int? stroke = int.tryParse(shape.strokeColor, radix: 16);
    if (stroke != null) {
      _paintShapeGeometry(
        canvas,
        shape,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = shape.strokeWidth
          ..color = Color(0xFF000000 | stroke),
        transform: transform,
      );
    } else if (fill == null &&
        shape.placeholder &&
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

  void _paintShapeGeometry(
    Canvas canvas,
    PmlShape shape,
    Rect r,
    Paint paint, {
    PmlTransform? transform,
  }) {
    switch (shape.preset) {
      case PmlShapePreset.rect:
        canvas.drawRect(r, paint);
      case PmlShapePreset.roundRect:
        final callout = shape.roundedCallout;
        if (callout != null) {
          final geometry = transform ?? shape.transform;
          canvas.save();
          if (geometry.flipH || geometry.flipV) {
            canvas.translate(r.center.dx, r.center.dy);
            canvas.scale(geometry.flipH ? -1 : 1, geometry.flipV ? -1 : 1);
            canvas.translate(-r.center.dx, -r.center.dy);
          }
          canvas.drawPath(_roundedCalloutPath(r, callout), paint);
          canvas.restore();
          return;
        }
        final double radius = math.min(8, r.shortestSide / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(radius)),
          paint,
        );
      case PmlShapePreset.ellipse:
        canvas.drawOval(r, paint);
      case PmlShapePreset.triangle:
        canvas.drawPath(
          Path()
            ..moveTo(r.center.dx, r.top)
            ..lineTo(r.right, r.bottom)
            ..lineTo(r.left, r.bottom)
            ..close(),
          paint,
        );
      case PmlShapePreset.connector:
        break;
      case PmlShapePreset.freeform:
        final Path path = Path();
        if (shape.path.isNotEmpty) {
          final w = shape.pathWidth;
          final h = shape.pathHeight;
          final sx = w != null && w > 0 ? r.width / w : 1 / 12700;
          final sy = h != null && h > 0 ? r.height / h : 1 / 12700;
          for (final (index, point) in shape.path.indexed) {
            if (point.close) {
              path.close();
            } else if (index == 0 || point.move) {
              path.moveTo(r.left + point.x * sx, r.top + point.y * sy);
            } else {
              path.lineTo(r.left + point.x * sx, r.top + point.y * sy);
            }
          }
          if (w == null) path.close();
        } else {
          path.addRect(r);
        }
        canvas.drawPath(path, paint);
      case PmlShapePreset.downArrow:
      case PmlShapePreset.upArrow:
      case PmlShapePreset.leftArrow:
      case PmlShapePreset.rightArrow:
        canvas.drawPath(_arrowPath(r, shape.preset), paint);
      case PmlShapePreset.diamond:
      case PmlShapePreset.hexagon:
      case PmlShapePreset.pentagon:
      case PmlShapePreset.homePlate:
      case PmlShapePreset.chevron:
      case PmlShapePreset.parallelogram:
      case PmlShapePreset.trapezoid:
        canvas.drawPath(_shapePath(r, shape.preset), paint);
    }
  }

  Path _roundedCalloutPath(Rect r, PmlRoundedCallout callout) {
    // DrawingML wedgeRoundRectCallout. The two tail base points sit on the
    // chosen side, on one of two quarter-width / quarter-height segments.
    final dx = callout.tipX.clamp(-2147483647, 2147483647) / 100000;
    final dy = callout.tipY.clamp(-2147483647, 2147483647) / 100000;
    final vertical = dy.abs() > dx.abs();
    final x1 = r.left + r.width * (dx > 0 ? 7 : 2) / 12;
    final x2 = x1 + r.width / 4;
    final y1 = r.top + r.height * (dy > 0 ? 7 : 2) / 12;
    final y2 = y1 + r.height / 4;
    final tip = Offset(r.center.dx + r.width * dx, r.center.dy + r.height * dy);
    final corner = _roundedCalloutRadius(r, callout);
    final path = Path()..moveTo(r.left, r.top + corner);
    void round(Offset center, double angle) {
      if (corner == 0) {
        path.lineTo(center.dx, center.dy);
      } else {
        path.arcTo(
          Rect.fromCircle(center: center, radius: corner),
          angle,
          math.pi / 2,
          false,
        );
      }
    }

    void tail(Offset from, Offset to) {
      path
        ..lineTo(from.dx, from.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(to.dx, to.dy);
    }

    round(Offset(r.left + corner, r.top + corner), math.pi);
    if (vertical && dy <= 0) tail(Offset(x1, r.top), Offset(x2, r.top));
    round(Offset(r.right - corner, r.top + corner), -math.pi / 2);
    if (!vertical && dx > 0) tail(Offset(r.right, y1), Offset(r.right, y2));
    round(Offset(r.right - corner, r.bottom - corner), 0);
    if (vertical && dy > 0) tail(Offset(x2, r.bottom), Offset(x1, r.bottom));
    round(Offset(r.left + corner, r.bottom - corner), math.pi / 2);
    if (!vertical && dx <= 0) tail(Offset(r.left, y2), Offset(r.left, y1));
    return path..close();
  }

  Path _arrowPath(Rect r, PmlShapePreset preset) {
    final bool vertical =
        preset == PmlShapePreset.downArrow || preset == PmlShapePreset.upArrow;
    final double shaft = (vertical ? r.width : r.height) * 0.48;
    final double head = (vertical ? r.height : r.width) * 0.48;
    final Path path = Path();
    switch (preset) {
      case PmlShapePreset.downArrow:
        final double left = r.left + (r.width - shaft) / 2;
        final double bottom = r.bottom - head;
        path
          ..moveTo(left, r.top)
          ..lineTo(left + shaft, r.top)
          ..lineTo(left + shaft, bottom)
          ..lineTo(r.right, bottom)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, bottom)
          ..lineTo(left, bottom)
          ..close();
      case PmlShapePreset.upArrow:
        final double left = r.left + (r.width - shaft) / 2;
        final double top = r.top + head;
        path
          ..moveTo(left, r.bottom)
          ..lineTo(left + shaft, r.bottom)
          ..lineTo(left + shaft, top)
          ..lineTo(r.right, top)
          ..lineTo(r.center.dx, r.top)
          ..lineTo(r.left, top)
          ..lineTo(left, top)
          ..close();
      case PmlShapePreset.leftArrow:
        final double top = r.top + (r.height - shaft) / 2;
        final double right = r.right - head;
        path
          ..moveTo(r.right, top)
          ..lineTo(r.right, top + shaft)
          ..lineTo(right, top + shaft)
          ..lineTo(right, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..lineTo(right, r.top)
          ..lineTo(right, top)
          ..close();
      case PmlShapePreset.rightArrow:
        final double top = r.top + (r.height - shaft) / 2;
        final double left = r.left + head;
        path
          ..moveTo(r.left, top)
          ..lineTo(r.left, top + shaft)
          ..lineTo(left, top + shaft)
          ..lineTo(left, r.bottom)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(left, r.top)
          ..lineTo(left, top)
          ..close();
      case PmlShapePreset.diamond:
      case PmlShapePreset.hexagon:
      case PmlShapePreset.pentagon:
      case PmlShapePreset.homePlate:
      case PmlShapePreset.chevron:
      case PmlShapePreset.parallelogram:
      case PmlShapePreset.trapezoid:
        return _shapePath(r, preset);
      case PmlShapePreset.rect:
      case PmlShapePreset.roundRect:
      case PmlShapePreset.ellipse:
      case PmlShapePreset.triangle:
      case PmlShapePreset.connector:
      case PmlShapePreset.freeform:
        path.addRect(r);
    }
    return path;
  }

  Path _shapePath(Rect r, PmlShapePreset preset) {
    final Path path = Path();
    switch (preset) {
      case PmlShapePreset.diamond:
        path
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy);
      case PmlShapePreset.hexagon:
        path
          ..moveTo(r.left + r.width * 0.25, r.top)
          ..lineTo(r.left + r.width * 0.75, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.left + r.width * 0.75, r.bottom)
          ..lineTo(r.left + r.width * 0.25, r.bottom)
          ..lineTo(r.left, r.center.dy);
      case PmlShapePreset.pentagon:
        // A regular pentagon normalized to its bounding rectangle.
        final double inset = (3 - math.sqrt(5)) / 4;
        path
          ..moveTo(r.left, r.top + r.height * inset * 2)
          ..lineTo(r.center.dx, r.top)
          ..lineTo(r.right, r.top + r.height * inset * 2)
          ..lineTo(r.right - r.width * inset, r.bottom)
          ..lineTo(r.left + r.width * inset, r.bottom);
      case PmlShapePreset.homePlate:
        final double head = r.shortestSide / 2;
        path
          ..moveTo(r.left, r.top)
          ..lineTo(r.right - head, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.right - head, r.bottom)
          ..lineTo(r.left, r.bottom);
      case PmlShapePreset.chevron:
        path
          ..moveTo(r.left, r.top)
          ..lineTo(r.left + r.width * 0.75, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.left + r.width * 0.75, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..lineTo(r.left + r.width * 0.25, r.center.dy);
      case PmlShapePreset.parallelogram:
        path
          ..moveTo(r.left + r.width * 0.25, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.left + r.width * 0.75, r.bottom)
          ..lineTo(r.left, r.bottom);
      case PmlShapePreset.trapezoid:
        path
          ..moveTo(r.left + r.width * 0.2, r.top)
          ..lineTo(r.left + r.width * 0.8, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom);
      case PmlShapePreset.rect:
      case PmlShapePreset.roundRect:
      case PmlShapePreset.ellipse:
      case PmlShapePreset.triangle:
      case PmlShapePreset.connector:
      case PmlShapePreset.freeform:
      case PmlShapePreset.downArrow:
      case PmlShapePreset.upArrow:
      case PmlShapePreset.leftArrow:
      case PmlShapePreset.rightArrow:
        path.addRect(r);
    }
    path.close();
    return path;
  }

  static double _displayFontSize(PmlShape shape, double authoredSize) {
    final fitted = authoredSize * shape.textScale;
    // PowerPoint paints imported normal autofit at whole point sizes.
    if (shape.textSource != null && shape.textScale < 1 && fitted >= 1) {
      return fitted.roundToDouble();
    }
    return fitted;
  }

  TextPainter _shapePainter(PmlShape shape, String text, Rect r, Color color) {
    final double baseSize = shape.fontSizePt > 0 ? shape.fontSizePt : 16;
    final double fontSize = _displayFontSize(shape, baseSize);
    final double lineHeight =
        _normalLineHeight(shape, baseSize) * (1 - shape.lineSpacingReduction);
    final int lines =
        !shape.shouldClipTextVertically ||
            shape.growsToFitText ||
            _growsWithText(r) ||
            lineHeight == 0
        ? 32
        : (r.height / lineHeight).ceil().clamp(1, 32);
    final bool rtl = shape.rightToLeft ?? PaintRunText.looksRtl(text);
    final TextAlign align = switch (shape.textAlign) {
      PmlTextAlign.center => TextAlign.center,
      PmlTextAlign.right => TextAlign.right,
      PmlTextAlign.justify => TextAlign.justify,
      PmlTextAlign.left =>
        shape.rightToLeft == null && rtl ? TextAlign.right : TextAlign.left,
    };
    final width = math.max(8.0, shape.textInsets.contentWidth(r.width));
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: _flutterLineHeight(fontSize > 0 ? lineHeight / fontSize : 0),
          color: color,
          fontWeight: FontWeight.normal,
          fontFamily: PaintRunText.familyFor(
            text: text,
            themeFamily: _theme.fontFamily,
          ),
          fontFamilyFallback: PaintRunText.fallbacksFor(text),
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: align,
      maxLines: lines,
      textHeightBehavior: shape.lineSpacingReduction > 0
          ? const ui.TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            )
          : null,
    )..layout(
      minWidth: shape.wrapsText ? 0 : width,
      maxWidth: shape.wrapsText ? width : double.infinity,
    );
  }

  Offset _plainTextOrigin(PmlShape shape, Rect rect, TextPainter painter) =>
      _shapeTextOrigin(shape, rect, painter.height) +
      Offset(
        shape.wrapsText
            ? 0
            : _overflowAlignment(
                painter,
                math.max(8.0, shape.textInsets.contentWidth(rect.width)),
              ),
        0,
      );

  static double _overflowAlignment(TextPainter painter, double width) {
    final offset = math.min(0.0, width - painter.width);
    final rtl = painter.textDirection == TextDirection.rtl;
    return switch (painter.textAlign) {
      TextAlign.center => offset / 2,
      TextAlign.right => offset,
      TextAlign.end => rtl ? 0 : offset,
      TextAlign.start || TextAlign.justify => rtl ? offset : 0,
      TextAlign.left => 0,
    };
  }

  List<_SlideParagraph> _layoutRichText(
    PmlShape shape,
    List<PmlTextParagraph> paragraphs,
    Rect rect,
    Color color, {
    Color? background,
  }) {
    final layouts = <_SlideParagraph>[];
    final fullWidth = shape.textInsets.contentWidth(rect.width);
    var top = 0.0;
    var start = 0;
    for (final paragraph in paragraphs) {
      final rtl =
          paragraph.definedProperties.contains(PmlParagraphProperty.direction)
          ? paragraph.rightToLeft
          : shape.rightToLeft ??
                PaintRunText.looksRtl(
                  paragraph.runs.map((run) => run.text).join(),
                );
      final direction = rtl ? TextDirection.rtl : TextDirection.ltr;
      final alignment = switch (paragraph.align) {
        PmlTextAlign.center => TextAlign.center,
        PmlTextAlign.right => TextAlign.right,
        PmlTextAlign.justify => TextAlign.justify,
        PmlTextAlign.left => rtl ? TextAlign.right : TextAlign.left,
      };
      var naturalLineHeight = 0.0;
      final usesLineSpacingRatio =
          paragraph.spaceBeforeLineRatio != 0 ||
          paragraph.spaceAfterLineRatio != 0;
      final fixed = paragraph.lineSpacingPt;
      final percentage = math.max(
        0,
        paragraph.lineSpacing - shape.lineSpacingReduction,
      );
      TextSpan span(PmlTextRun run, String text) {
        final base = run.fontSizePt > 0
            ? run.fontSizePt
            : paragraph.defaultFontSizePt > 0
            ? paragraph.defaultFontSizePt
            : shape.fontSizePt > 0
            ? shape.fontSizePt
            : 16.0;
        final size = _displayFontSize(shape, base);
        final lineHeight = _normalLineHeight(shape, base);
        final authoredColor = run.color.isEmpty
            ? color
            : _hexColor(run.color, color);
        final runColor = background == null
            ? authoredColor
            : _theme.resolveDocumentColor(
                authoredColor,
                background: background,
              );
        final family = run.fontFamily.isNotEmpty
            ? run.fontFamily
            : paragraph.defaultFontFamily.isNotEmpty
            ? paragraph.defaultFontFamily
            : _theme.fontFamily;
        final style = TextStyle(
          fontSize: size,
          // PowerPoint applies authored tracking after scaling the font.
          letterSpacing:
              run.letterSpacingPt ?? paragraph.defaultLetterSpacingPt,
          color: runColor,
          fontWeight:
              run.bold &&
                  !run.fontFamily.toLowerCase().contains('microsoft sans serif')
              ? FontWeight.bold
              : FontWeight.normal,
          fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
          decoration: run.underline || run.strike
              ? TextDecoration.combine([
                  if (run.underline) TextDecoration.underline,
                  if (run.strike) TextDecoration.lineThrough,
                ])
              : null,
          fontFamily: PaintRunText.familyFor(
            text: text,
            runFamily: family,
            themeFamily: _theme.fontFamily,
          ),
          fontFamilyFallback: PaintRunText.fallbacksFor(
            text,
            runFamily: family,
          ),
        );
        if (usesLineSpacingRatio) {
          naturalLineHeight = math.max(naturalLineHeight, lineHeight);
        }
        if (fixed != null && fixed.isFinite) {
          return TextSpan(
            text: text,
            style: style.copyWith(
              height: _flutterLineHeight(
                size > 0 ? math.max(0, fixed) / size : 0,
              ),
            ),
          );
        }
        if (size <= 0) {
          return TextSpan(text: text, style: style);
        }
        return TextSpan(
          text: text,
          style: style.copyWith(
            height: _flutterLineHeight(lineHeight * percentage / size),
          ),
        );
      }

      final runs = paragraph.runs;
      final marker = paragraph.bullet;
      final margin = rtl ? paragraph.marginRightPt : paragraph.marginLeftPt;
      final firstIndent = paragraph.indentPt;
      final inlineBullet =
          marker != null && runs.isNotEmpty && firstIndent == 0;
      final bulletSpan = marker == null || runs.isEmpty
          ? null
          : span(
              PmlTextRun(
                fontSizePt: runs.first.fontSizePt,
                color: paragraph.bulletColor ?? runs.first.color,
                fontFamily: paragraph.bulletFont ?? runs.first.fontFamily,
                letterSpacingPt: 0,
              ),
              _slideBulletText(marker, paragraph.bulletFont),
            );
      final paragraphSpans = <TextSpan>[
        if (inlineBullet) bulletSpan!,
        for (final run in runs) span(run, _slideRunText(run)),
        if (runs.isEmpty)
          span(
            PmlTextRun(
              bold: paragraph.defaultBold,
              italic: paragraph.defaultItalic,
            ),
            '\u200b',
          ),
      ];
      final spans =
          alignment == TextAlign.justify &&
              !rtl &&
              marker == null &&
              shape.wrapsText
          ? paragraphSpans.expand(_quantizedSlideAdvances).toList()
          : paragraphSpans;
      final leadStyle = spans[inlineBullet ? 1 : 0].style!;
      final uniformAdvance =
          fixed == null &&
              percentage > 0 &&
              leadStyle.height != null &&
              spans.every(
                (item) =>
                    item.style!.fontSize == leadStyle.fontSize &&
                    item.style!.height == leadStyle.height,
              )
          ? leadStyle.fontSize! * leadStyle.height!
          : null;
      // A uniform point size defines one line box, even when runs mix font
      // families or weights with different ascent and descent proportions.
      final strut =
          uniformAdvance != null &&
              spans.any((item) {
                final style = item.style!;
                return style.fontFamily != leadStyle.fontFamily ||
                    style.fontWeight != leadStyle.fontWeight ||
                    style.fontStyle != leadStyle.fontStyle;
              })
          ? StrutStyle.fromTextStyle(leadStyle, forceStrutHeight: true)
          : null;
      if (layouts.isNotEmpty) {
        top +=
            paragraph.spaceBeforePt +
            naturalLineHeight * paragraph.spaceBeforeLineRatio;
      }
      final layoutWidth = math.max(
        8.0,
        fullWidth - paragraph.marginLeftPt - paragraph.marginRightPt,
      );
      final left = paragraph.marginLeftPt;
      TextPainter layout(List<TextSpan> content, double width, int maxLines) =>
          TextPainter(
            text: TextSpan(children: content),
            textDirection: direction,
            textAlign: alignment,
            maxLines: maxLines,
            strutStyle: strut,
            textHeightBehavior: fixed != null || percentage == 0
                ? const ui.TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  )
                : null,
          )..layout(
            minWidth: width,
            maxWidth: shape.wrapsText ? width : double.infinity,
          );

      double advance(TextPainter painter) {
        final lines = painter.computeLineMetrics();
        if (lines.length == 1) {
          if (fixed != null) return fixed;
          if (percentage == 0) return 0;
        }
        if (fixed != null) return painter.height;
        if (uniformAdvance != null) return uniformAdvance * lines.length;
        // TextPainter.height is rounded separately for every paragraph.
        return lines.fold(
          0.0,
          (height, line) => height + line.ascent + line.descent,
        );
      }

      var remaining = runs.fold(0, (length, run) => length + run.text.length);
      var lineStart = start;
      var painterLeft = left;
      var painterWidth = layoutWidth;
      var lineCount = 32;
      var bodySpans = spans;
      TextPainter? firstLine;
      if (marker == null &&
          firstIndent != 0 &&
          remaining > 0 &&
          alignment != TextAlign.justify) {
        final firstWidth = math.max(8.0, layoutWidth - firstIndent);
        final firstLeft = rtl ? left : left + firstIndent;
        final probe = layout(spans, firstWidth, 32);
        final split = probe.getLineBoundary(const TextPosition(offset: 0)).end;
        if (split == remaining) {
          firstLine = probe;
          painterLeft = firstLeft;
          painterWidth = firstWidth;
        } else {
          probe.dispose();
          if (split > 0 && split < remaining) {
            final (head, tail) = _splitSlideSpans(spans, split);
            final headPainter = layout(head, firstWidth, 1);
            layouts.add(
              _SlideParagraph(
                painter: headPainter,
                offset: Offset(
                  firstLeft +
                      (shape.wrapsText
                          ? 0
                          : _overflowAlignment(headPainter, firstWidth)),
                  top,
                ),
                start: start,
                length: split,
                prefixLength: 0,
              ),
            );
            top += advance(headPainter);
            bodySpans = tail;
            lineStart += split;
            remaining -= split;
            lineCount--;
            // Flutter's line boundary excludes an explicit line break.
            // Consume it so the continuation begins on the intended line.
            if (bodySpans.first.text!.startsWith('\n')) {
              bodySpans = _splitSlideSpans(bodySpans, 1).$2;
              lineStart++;
              remaining--;
            }
          }
        }
      }
      if (remaining == 0 && lineStart != start) {
        bodySpans = [span(PmlTextRun(), '\u200b')];
      }
      final painter = firstLine ?? layout(bodySpans, layoutWidth, lineCount);
      final alignmentOffset = shape.wrapsText
          ? 0.0
          : _overflowAlignment(painter, painterWidth);
      final offset = Offset(painterLeft + alignmentOffset, top);
      final hangingBullet = bulletSpan != null && !inlineBullet
          ? (TextPainter(text: bulletSpan, textDirection: direction)..layout())
          : null;
      final bulletOffset = hangingBullet == null
          ? null
          : Offset(
              alignmentOffset +
                  (rtl
                      ? fullWidth - margin - firstIndent - hangingBullet.width
                      : left + firstIndent),
              top +
                  painter.computeDistanceToActualBaseline(
                    TextBaseline.alphabetic,
                  ) -
                  hangingBullet.computeDistanceToActualBaseline(
                    TextBaseline.alphabetic,
                  ),
            );
      layouts.add(
        _SlideParagraph(
          painter: painter,
          offset: offset,
          start: lineStart,
          length: remaining,
          prefixLength: inlineBullet ? marker.length : 0,
          bullet: hangingBullet,
          bulletOffset: bulletOffset,
        ),
      );
      start = lineStart + remaining + 1;
      top +=
          advance(painter) +
          paragraph.spaceAfterPt +
          naturalLineHeight * paragraph.spaceAfterLineRatio;
    }
    return layouts;
  }

  static (List<TextSpan>, List<TextSpan>) _splitSlideSpans(
    List<TextSpan> spans,
    int length,
  ) {
    final head = <TextSpan>[];
    final tail = <TextSpan>[];
    for (final span in spans) {
      final text = span.text!;
      if (length <= 0) {
        tail.add(span);
      } else if (length >= text.length) {
        head.add(span);
      } else {
        head.add(TextSpan(text: text.substring(0, length), style: span.style));
        tail.add(TextSpan(text: text.substring(length), style: span.style));
      }
      length -= text.length;
    }
    return (head, tail);
  }

  static final _simpleLatin = RegExp(
    r'^[\u0020-\u007e\u00a0-\u00ff\u2010-\u201f]+$',
  );
  static final _wordSpacingRuns = RegExp(r'[^ ]+| +');

  static Iterable<TextSpan> _quantizedSlideAdvances(TextSpan span) {
    final text = span.text!;
    final style = span.style!;
    final family = style.fontFamily;
    final size = style.fontSize!;
    if (family == null ||
        !size.isFinite ||
        size <= 0 ||
        (style.letterSpacing ?? 0) != 0 ||
        !_simpleLatin.hasMatch(text)) {
      return [span];
    }
    final metrics = OfficeHostFonts.paintMetrics(
      family,
      size,
      codePoint: 0x20,
      weight: style.fontWeight == FontWeight.bold ? 700 : 400,
      italic: style.fontStyle == FontStyle.italic,
    );
    if (metrics == null) return [span];

    // PowerPoint quantizes glyph advances to eighths of a point. Apply the
    // resulting width per word while retaining Flutter's glyph shaping.
    return _wordSpacingRuns.allMatches(text).map((match) {
      final word = match[0]!;
      var adjustment = 0.0;
      for (final codePoint in word.codeUnits) {
        if (metrics.font.glyphIdFor(codePoint) == 0) {
          return TextSpan(text: word, style: style);
        }
        final advance = metrics.characterWidth(codePoint);
        adjustment += (advance * 8).round() / 8 - advance;
      }
      return TextSpan(
        text: word,
        style: style.copyWith(letterSpacing: adjustment / word.length),
      );
    });
  }

  static String _slideBulletText(String text, String? family) {
    final lower = family?.toLowerCase() ?? '';
    if (!(lower.startsWith('wingdings') || lower == 'webdings') ||
        text.length != 1 ||
        text.codeUnitAt(0) > 0xff) {
      return text;
    }
    return _slideSymbolText(
      String.fromCharCode(text.codeUnitAt(0) + 0xf000),
      family!,
    );
  }

  static String _slideRunText(PmlTextRun run) =>
      _slideSymbolText(run.text.replaceAll('\t', '\u2003'), run.fontFamily);

  static String _slideSymbolText(String text, String family) {
    if (family.toLowerCase() != 'wingdings' ||
        OfficeHostFonts.registeredFamily(family) != null) {
      return text;
    }
    return text.replaceAll('\uF0E8', '\u2794').replaceAll('\uF0F3', '\u21D4');
  }

  static double _richTextHeight(List<_SlideParagraph> layouts) =>
      layouts.last.offset.dy + layouts.last.painter.height;

  // Native normal autofit rounds the fitted em before calculating leading.
  static double _normalLineHeight(PmlShape shape, double points) =>
      _displayFontSize(shape, points) * 1.2;

  // Flutter reserves a zero height multiplier for natural font metrics.
  // Keep a zero authored advance collapsed without changing its stored value.
  double _flutterLineHeight(double value) => value == 0 ? 0.001 : value;

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
        final Color ink = _theme.resolveDocumentColor(
          _hexColor(cell.textColor, const Color(0xFF1A1A1A)),
          background: _hexColor(cell.fillColor, const Color(0xFFFFFFFF)),
        );
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

  void _paintShapeText(
    Canvas canvas,
    PmlShape shape,
    Rect r, {
    String? text,
    Color? background,
  }) {
    final bool isEdit = editing && identical(shape, selected);
    final String body = text ?? shape.text;
    if (body.isEmpty && !isEdit) {
      return;
    }
    canvas.save();
    if (shape.shouldClipTextVertically &&
        !shape.growsToFitText &&
        !_growsWithText(r)) {
      final bounds = shape.wrapsText ? r : canvas.getLocalClipBounds();
      canvas.clipRect(
        Rect.fromLTRB(bounds.left, r.top, bounds.right, r.bottom),
      );
    }
    final Color color = _textColor(shape, background: background);
    final textRect = _shapeTextRect(shape, r);
    final paragraphs = body == shape.text
        ? shape.resolvedRichText
        : const <PmlTextParagraph>[];
    if (paragraphs.isNotEmpty) {
      final layout = _layoutRichText(
        shape,
        paragraphs,
        textRect,
        color,
        background: background,
      );
      try {
        final origin = _shapeTextOrigin(
          shape,
          textRect,
          _richTextHeight(layout),
        );
        final caretParagraph = isEdit && config.showsCaret && hasFocus
            ? layout.lastWhere(
                (paragraph) => paragraph.start <= editCaret,
                orElse: () => layout.first,
              )
            : null;
        for (final paragraph in layout) {
          if (paragraph.bullet case final bullet?) {
            bullet.paint(canvas, origin + paragraph.bulletOffset!);
          }
          _paintTextPainter(
            canvas,
            paragraph.painter,
            origin + paragraph.offset,
            color,
            shape.rightToLeft ?? PaintRunText.looksRtl(body),
            selectionStart: isEdit
                ? math.min(editBase, editCaret) - paragraph.start
                : null,
            selectionEnd: isEdit
                ? math.max(editBase, editCaret) - paragraph.start
                : null,
            caret: identical(caretParagraph, paragraph)
                ? editCaret - paragraph.start
                : null,
            length: paragraph.length,
            prefix: paragraph.prefixLength,
          );
        }
      } finally {
        for (final paragraph in layout) {
          paragraph.dispose();
        }
      }
    } else {
      final painter = _shapePainter(shape, body, textRect, color);
      try {
        _paintTextPainter(
          canvas,
          painter,
          _plainTextOrigin(shape, textRect, painter),
          color,
          shape.rightToLeft ??
              (PaintRunText.looksRtl(body) ||
                  config.textDirection == TextDirection.rtl),
          selectionStart: isEdit ? math.min(editBase, editCaret) : null,
          selectionEnd: isEdit ? math.max(editBase, editCaret) : null,
          caret: isEdit && config.showsCaret && hasFocus ? editCaret : null,
          length: body.length,
        );
      } finally {
        painter.dispose();
      }
    }
    canvas.restore();
  }

  void _paintTextPainter(
    Canvas canvas,
    TextPainter painter,
    Offset origin,
    Color color,
    bool rtl, {
    required int length,
    int? selectionStart,
    int? selectionEnd,
    int? caret,
    int prefix = 0,
  }) {
    if (selectionStart != null && selectionEnd != null) {
      final begin = selectionStart.clamp(0, length);
      final end = selectionEnd.clamp(0, length);
      if (end > begin) {
        for (final box in painter.getBoxesForSelection(
          TextSelection(baseOffset: begin + prefix, extentOffset: end + prefix),
        )) {
          canvas.drawRect(
            Rect.fromLTRB(
              box.left,
              box.top,
              box.right,
              box.bottom,
            ).shift(origin),
            Paint()..color = _theme.selectionFill,
          );
        }
      }
    }
    painter.paint(canvas, origin);
    if (caret != null) {
      final offset = painter.getOffsetForCaret(
        TextPosition(offset: caret.clamp(0, length) + prefix),
        const Rect.fromLTWH(0, 0, 0, 16),
      );
      CaretEngine.paintFlagged(
        canvas,
        stem: Rect.fromLTWH(
          origin.dx + offset.dx,
          origin.dy + offset.dy,
          1,
          18,
        ),
        color: color,
        rtl: rtl,
      );
    }
  }

  Offset _shapeTextOrigin(PmlShape shape, Rect r, double textHeight) => Offset(
    r.left + shape.textInsets.left,
    r.top +
        shape.textInsets.textTop(r.height, textHeight, shape.displayTextAnchor),
  );

  static double _roundedCalloutRadius(Rect rect, PmlRoundedCallout callout) =>
      rect.shortestSide * callout.corner.clamp(0, 50000) / 100000;

  static Rect _shapeTextRect(PmlShape shape, Rect rect) {
    final callout = shape.roundedCallout;
    // DrawingML's wedgeRoundRectCallout text rectangle is inset at the
    // 45-degree point of each rounded corner, before the text body margins.
    return callout == null
        ? rect
        : rect.deflate(_roundedCalloutRadius(rect, callout) * 0.29289);
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
      transform: frame.transform,
    );
    canvas.restore();
  }

  void _paintShapeInRect(
    Canvas canvas,
    PmlShape shape,
    Rect r, {
    String? text,
    String? fillColor,
    PmlTransform? transform,
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
        shapeRotationDegrees: (transform ?? shape.transform).rotationDegrees,
      );
    } else {
      final String paintedFill = fillColor ?? shape.fillColor;
      final int? fill = int.tryParse(paintedFill, radix: 16);
      _paintShapeFill(canvas, shape, r, paintedFill, transform: transform);
      // Morph can change the fill independently of the model shape. Resolve
      // against that painted fill; unfilled morph backing remains unknown.
      _paintShapeText(
        canvas,
        shape,
        r,
        text: text,
        background: fill == null || _growsWithText(r)
            ? null
            : Color(0xFF000000 | fill),
      );
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

  Color _slidePaper(PmlSlide target) {
    final int? rgb = int.tryParse(
      master == null
          ? target.background
          : target.resolveBackground(master!.background),
      radix: 16,
    );
    // Inherited neutral paper follows the display theme when adaptation is
    // enabled. Explicit slide/layout fills retain their authored appearance.
    return rgb == null ||
            (_theme.adaptDocumentColors &&
                target.inheritsMasterBackground &&
                (rgb & 0xFFFFFF) == 0xFFFFFF)
        ? _theme.slideBackground
        : Color(0xFF000000 | (rgb & 0xFFFFFF));
  }

  bool _hiddenBackgroundPicture(PmlSlide target, PmlShape shape) =>
      shape.isBackgroundFill &&
      target.inheritsMasterBackground &&
      (master?.hasAuthoredBackground ?? false);

  void _paintSlideBody(
    Canvas canvas,
    PmlSlide target, {
    Map<int, PmlAnimSample>? samples,
    Set<int>? skipIds,
  }) {
    canvas.drawRect(
      Offset.zero & _slideSize,
      Paint()..color = _slidePaper(target),
    );
    for (final PmlShape shape in target.backgroundShapes) {
      if (_hiddenBackgroundPicture(target, shape)) continue;
      // Master/layout shape ids belong to their own parts. Slide animations
      // and morph matching must never apply to a coincident decoration id.
      final Rect r = _shapeRect(shape);
      canvas.save();
      _rotateCanvas(canvas, shape, r);
      _paintShapeInRect(canvas, shape, r);
      canvas.restore();
    }
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
          shapeRotationDegrees: shape.transform.rotationDegrees,
        );
      } else {
        _paintShapeFill(canvas, shape, r, shape.fillColor);
        _paintShapeText(
          canvas,
          shape,
          r,
          background: _solidTextBackground(
            target,
            shape,
            r,
            samples: samples,
            skipIds: skipIds,
          ),
        );
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
    shape.transform = shape.transform.copyWith(
      x: (rect.left * 12700).round(),
      y: (rect.top * 12700).round(),
      cx: (rect.width * 12700).round().clamp(12700, 100000000),
      cy: (rect.height * 12700).round().clamp(12700, 100000000),
      rot: shape.transform.rot,
      flipH: shape.transform.flipH,
      flipV: shape.transform.flipV,
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
      shape.transform = start.copyWith(
        x: ((np.dx - start.widthPoints / 2) * 12700).round(),
        y: ((np.dy - start.heightPoints / 2) * 12700).round(),
        cx: start.cx,
        cy: start.cy,
        rot: start.rot + (delta * 60000).round(),
        flipH: start.flipH,
        flipV: start.flipV,
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
