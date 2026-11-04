import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../core/virtual_viewport.dart';
import '../embed/office_context_menu.dart';
import '../embed/office_theme.dart';
import '../ui_components/office_chrome.dart';
import '../visual/paint_office_visual.dart';
import '../editor_slide/transform_handles.dart';
import 'caret_engine.dart';
import 'office_ruler.dart';
import 'paint_equation.dart';
import 'paint_run_text.dart';

/// Class WordCanvas.
class WordCanvas extends LeafRenderObjectWidget {
  /// WordCanvas API.
  const WordCanvas({
    super.key,
    required this.document,
    required this.laidOut,
    required this.caret,
    this.viewport,
    this.config = const OfficeSurfaceConfig(),
    this.hasFocus = false,
    this.semanticsLabel = '',
    this.semanticsValue = '',
    this.selectedVisual,
    this.selectedFrame,
    this.editingFrame = false,
    this.selectedEquation,
    this.equationSlot = 0,
    this.equationCaret = 0,
    this.pictureCropMode = false,
    this.onChanged,
    this.onSelectVisual,
    this.onSelectFrame,
    this.onEditFrame,
    this.onSelectEquation,
    this.onBeginVisualTransform,
    this.onPreviewVisualMove,
    this.onPreviewVisualResize,
    this.onPreviewVisualCrop,
    this.onPreviewVisualRotate,
    this.onCommitVisualTransform,
    this.onBeginFrameTransform,
    this.onPreviewFrameMove,
    this.onPreviewFrameResize,
    this.onCommitFrameTransform,
    this.onActivateVisual,
    this.onExtendThroughVisual,
    this.isVisualInSelection,
    this.onJumpParagraph,
    this.onFollowLink,
    this.selectedCommentId,
    this.onSelectComment,
    this.onContextMenu,
    this.onInsertTableRowAt,
    this.onInsertTableColumnAt,
    this.onBeginTableResize,
    this.onPreviewTableColumnWidth,
    this.onPreviewTableRowHeight,
    this.onCommitTableResize,
    this.selectedTable,
    this.onSelectTable,
    this.selectedTableBand,
    this.onSelectTableBand,
    this.storyParagraphs,
    this.editingHeader = false,
    this.editingFooter = false,
    this.onBeginHeaderFooterEdit,
    this.onEndHeaderFooterEdit,
    this.onBeginRulerEdit,
    this.onPreviewRulerEdit,
    this.onCommitRulerEdit,
    this.compact = false,
    this.findHits = const <OfficeFindHit>[],
    this.activeFindIndex = -1,
  });

  /// document API.
  final WmlDocument document;

  /// laidOut API.
  final LaidOutDocument laidOut;

  /// caret API.
  final CaretEngine caret;

  /// viewport API.
  final VirtualViewport? viewport;

  /// config API.
  final OfficeSurfaceConfig config;

  /// hasFocus API.
  final bool hasFocus;

  /// semanticsLabel API.
  final String semanticsLabel;

  /// semanticsValue API.
  final String semanticsValue;

  /// selectedVisual API.
  final WmlVisual? selectedVisual;

  /// selectedFrame API.
  final WmlFrame? selectedFrame;

  /// Hide move/resize knobs and edit the frame text.
  final bool editingFrame;

  /// selectedEquation API.
  final WmlEquation? selectedEquation;

  /// equationSlot API.
  final int equationSlot;

  /// equationCaret API.
  final int equationCaret;

  /// pictureCropMode API.
  final bool pictureCropMode;

  /// onBeginVisualTransform API.
  final VoidCallback? onBeginVisualTransform;

  /// Function API.
  final void Function(double dx, double dy)? onPreviewVisualMove;

  /// Function API.
  final void Function({required double width, required double height})?
  /// onPreviewVisualResize API.
  onPreviewVisualResize;

  /// Function API.
  final void Function({
    required double left,
    required double top,
    required double right,
    required double bottom,
  })?
  /// onPreviewVisualCrop API.
  onPreviewVisualCrop;

  /// onPreviewVisualRotate API.
  final ValueChanged<double>? onPreviewVisualRotate;

  /// onCommitVisualTransform API.
  final VoidCallback? onCommitVisualTransform;

  /// onBeginFrameTransform API.
  final VoidCallback? onBeginFrameTransform;

  /// Function API.
  final void Function(double dx, double dy)? onPreviewFrameMove;

  /// Function API.
  final void Function({required double width, required double height})?
  onPreviewFrameResize;

  /// onCommitFrameTransform API.
  final VoidCallback? onCommitFrameTransform;

  /// onChanged API.
  final VoidCallback? onChanged;

  /// onSelectVisual API.
  final ValueChanged<OfficeVisual?>? onSelectVisual;

  /// onSelectFrame API.
  final ValueChanged<WmlFrame?>? onSelectFrame;

  /// Double-click enters text edit on a frame.
  final ValueChanged<WmlFrame>? onEditFrame;

  /// Function API.
  final void Function(WmlEquation? equation, int? slot, int? caret)?
  /// onSelectEquation API.
  onSelectEquation;

  /// onActivateVisual API.
  final ValueChanged<OfficeVisual>? onActivateVisual;

  /// onExtendThroughVisual API.
  final ValueChanged<OfficeVisual>? onExtendThroughVisual;

  /// Function API.
  final bool Function(OfficeVisual visual)? isVisualInSelection;

  /// onJumpParagraph API.
  final ValueChanged<int>? onJumpParagraph;

  /// onFollowLink API.
  final ValueChanged<WmlHyperlink>? onFollowLink;

  /// selectedCommentId API.
  final int? selectedCommentId;

  /// onSelectComment API.
  final ValueChanged<int?>? onSelectComment;

  /// onContextMenu API.
  final ValueChanged<OfficeContextHit>? onContextMenu;

  /// Function API.
  final void Function(WmlTable table, int index)? onInsertTableRowAt;

  /// Function API.
  final void Function(WmlTable table, int index)? onInsertTableColumnAt;

  /// onBeginTableResize API.
  final ValueChanged<WmlTable>? onBeginTableResize;

  /// Function API.
  final void Function(WmlTable table, int col, double width)?
  /// onPreviewTableColumnWidth API.
  onPreviewTableColumnWidth;

  /// Function API.
  final void Function(WmlTable table, int row, double height)?
  /// onPreviewTableRowHeight API.
  onPreviewTableRowHeight;

  /// onCommitTableResize API.
  final ValueChanged<WmlTable>? onCommitTableResize;

  /// selectedTable API.
  final WmlTable? selectedTable;

  /// onSelectTable API.
  final ValueChanged<WmlTable?>? onSelectTable;
  final ({WmlTable table, bool column, int from, int to})? selectedTableBand;

  /// Function API.
  final void Function(
    WmlTable table, {
    required bool column,
    required int from,
    required int to,
  })?
  /// onSelectTableBand API.
  onSelectTableBand;

  /// storyParagraphs API.
  final List<WmlParagraph>? storyParagraphs;

  /// editingHeader API.
  final bool editingHeader;

  /// editingFooter API.
  final bool editingFooter;

  /// Function API.
  final void Function(int pageIndex, {required bool footer})?
  /// onBeginHeaderFooterEdit API.
  onBeginHeaderFooterEdit;

  /// onEndHeaderFooterEdit API.
  final VoidCallback? onEndHeaderFooterEdit;

  /// onBeginRulerEdit API.
  final VoidCallback? onBeginRulerEdit;

  /// onPreviewRulerEdit API.
  final ValueChanged<WordRulerEdit>? onPreviewRulerEdit;

  /// onCommitRulerEdit API.
  final VoidCallback? onCommitRulerEdit;

  /// compact API.
  final bool compact;

  /// findHits API.
  final List<OfficeFindHit> findHits;

  /// activeFindIndex API.
  final int activeFindIndex;

  @override
  /// createRenderObject API.
  RenderWordCanvas createRenderObject(BuildContext context) {
    return RenderWordCanvas(
      document: document,
      laidOut: laidOut,
      caret: caret,
      viewport: viewport ?? VirtualViewport(),
      config: config,
      hasFocus: hasFocus,
      semanticsLabel: semanticsLabel,
      semanticsValue: semanticsValue,
      selectedVisual: selectedVisual,
      selectedFrame: selectedFrame,
      editingFrame: editingFrame,
      selectedEquation: selectedEquation,
      equationSlot: equationSlot,
      equationCaret: equationCaret,
      pictureCropMode: pictureCropMode,
      onChanged: onChanged,
      onSelectVisual: onSelectVisual,
      onSelectFrame: onSelectFrame,
      onEditFrame: onEditFrame,
      onSelectEquation: onSelectEquation,
      onBeginVisualTransform: onBeginVisualTransform,
      onPreviewVisualMove: onPreviewVisualMove,
      onPreviewVisualResize: onPreviewVisualResize,
      onPreviewVisualCrop: onPreviewVisualCrop,
      onPreviewVisualRotate: onPreviewVisualRotate,
      onCommitVisualTransform: onCommitVisualTransform,
      onBeginFrameTransform: onBeginFrameTransform,
      onPreviewFrameMove: onPreviewFrameMove,
      onPreviewFrameResize: onPreviewFrameResize,
      onCommitFrameTransform: onCommitFrameTransform,
      onActivateVisual: onActivateVisual,
      onExtendThroughVisual: onExtendThroughVisual,
      isVisualInSelection: isVisualInSelection,
      onJumpParagraph: onJumpParagraph,
      onFollowLink: onFollowLink,
      selectedCommentId: selectedCommentId,
      onSelectComment: onSelectComment,
      onContextMenu: onContextMenu,
      onInsertTableRowAt: onInsertTableRowAt,
      onInsertTableColumnAt: onInsertTableColumnAt,
      onBeginTableResize: onBeginTableResize,
      onPreviewTableColumnWidth: onPreviewTableColumnWidth,
      onPreviewTableRowHeight: onPreviewTableRowHeight,
      onCommitTableResize: onCommitTableResize,
      selectedTable: selectedTable,
      onSelectTable: onSelectTable,
      selectedTableBand: selectedTableBand,
      onSelectTableBand: onSelectTableBand,
      storyParagraphs: storyParagraphs,
      editingHeader: editingHeader,
      editingFooter: editingFooter,
      onBeginHeaderFooterEdit: onBeginHeaderFooterEdit,
      onEndHeaderFooterEdit: onEndHeaderFooterEdit,
      onBeginRulerEdit: onBeginRulerEdit,
      onPreviewRulerEdit: onPreviewRulerEdit,
      onCommitRulerEdit: onCommitRulerEdit,
      compact: compact,
      findHits: findHits,
      activeFindIndex: activeFindIndex,
    );
  }

  @override
  /// updateRenderObject API.
  void updateRenderObject(BuildContext context, RenderWordCanvas renderObject) {
    renderObject
      ..document = document
      ..laidOut = laidOut
      ..caret = caret
      ..config = config
      ..hasFocus = hasFocus
      ..semanticsLabel = semanticsLabel
      ..semanticsValue = semanticsValue
      ..selectedVisual = selectedVisual
      ..selectedFrame = selectedFrame
      ..editingFrame = editingFrame
      ..selectedEquation = selectedEquation
      ..equationSlot = equationSlot
      ..equationCaret = equationCaret
      ..pictureCropMode = pictureCropMode
      ..onChanged = onChanged
      ..onSelectVisual = onSelectVisual
      ..onSelectFrame = onSelectFrame
      ..onEditFrame = onEditFrame
      ..onSelectEquation = onSelectEquation
      ..onBeginVisualTransform = onBeginVisualTransform
      ..onPreviewVisualMove = onPreviewVisualMove
      ..onPreviewVisualResize = onPreviewVisualResize
      ..onPreviewVisualCrop = onPreviewVisualCrop
      ..onPreviewVisualRotate = onPreviewVisualRotate
      ..onCommitVisualTransform = onCommitVisualTransform
      ..onBeginFrameTransform = onBeginFrameTransform
      ..onPreviewFrameMove = onPreviewFrameMove
      ..onPreviewFrameResize = onPreviewFrameResize
      ..onCommitFrameTransform = onCommitFrameTransform
      ..onActivateVisual = onActivateVisual
      ..onExtendThroughVisual = onExtendThroughVisual
      ..isVisualInSelection = isVisualInSelection
      ..onJumpParagraph = onJumpParagraph
      ..onFollowLink = onFollowLink
      ..selectedCommentId = selectedCommentId
      ..onSelectComment = onSelectComment
      ..onContextMenu = onContextMenu
      ..onInsertTableRowAt = onInsertTableRowAt
      ..onInsertTableColumnAt = onInsertTableColumnAt
      ..onBeginTableResize = onBeginTableResize
      ..onPreviewTableColumnWidth = onPreviewTableColumnWidth
      ..onPreviewTableRowHeight = onPreviewTableRowHeight
      ..onCommitTableResize = onCommitTableResize
      ..selectedTable = selectedTable
      ..onSelectTable = onSelectTable
      ..selectedTableBand = selectedTableBand
      ..onSelectTableBand = onSelectTableBand
      ..storyParagraphs = storyParagraphs
      ..editingHeader = editingHeader
      ..editingFooter = editingFooter
      ..onBeginHeaderFooterEdit = onBeginHeaderFooterEdit
      ..onEndHeaderFooterEdit = onEndHeaderFooterEdit
      ..onBeginRulerEdit = onBeginRulerEdit
      ..onPreviewRulerEdit = onPreviewRulerEdit
      ..onCommitRulerEdit = onCommitRulerEdit
      ..compact = compact
      ..findHits = findHits
      ..activeFindIndex = activeFindIndex;
    if (viewport != null) {
      renderObject.viewport = viewport!;
    }
    renderObject.markNeedsPaint();
  }
}

/// Class RenderWordCanvas.
class RenderWordCanvas extends RenderBox implements MouseTrackerAnnotation {
  /// RenderWordCanvas API.
  RenderWordCanvas({
    required this.document,
    required this.laidOut,
    required this.caret,
    required this.viewport,
    required this.config,
    required this.hasFocus,
    required this.semanticsLabel,
    required this.semanticsValue,
    this.selectedVisual,
    this.selectedFrame,
    this.editingFrame = false,
    this.selectedEquation,
    this.equationSlot = 0,
    this.equationCaret = 0,
    this.pictureCropMode = false,
    this.onChanged,
    this.onSelectVisual,
    this.onSelectFrame,
    this.onEditFrame,
    this.onSelectEquation,
    this.onBeginVisualTransform,
    this.onPreviewVisualMove,
    this.onPreviewVisualResize,
    this.onPreviewVisualCrop,
    this.onPreviewVisualRotate,
    this.onCommitVisualTransform,
    this.onBeginFrameTransform,
    this.onPreviewFrameMove,
    this.onPreviewFrameResize,
    this.onCommitFrameTransform,
    this.onActivateVisual,
    this.onExtendThroughVisual,
    this.isVisualInSelection,
    this.onJumpParagraph,
    this.onFollowLink,
    this.selectedCommentId,
    this.onSelectComment,
    this.onContextMenu,
    this.onInsertTableRowAt,
    this.onInsertTableColumnAt,
    this.onBeginTableResize,
    this.onPreviewTableColumnWidth,
    this.onPreviewTableRowHeight,
    this.onCommitTableResize,
    this.selectedTable,
    this.onSelectTable,
    this.selectedTableBand,
    this.onSelectTableBand,
    this.storyParagraphs,
    this.editingHeader = false,
    this.editingFooter = false,
    this.onBeginHeaderFooterEdit,
    this.onEndHeaderFooterEdit,
    this.onBeginRulerEdit,
    this.onPreviewRulerEdit,
    this.onCommitRulerEdit,
    this.compact = false,
    this.findHits = const <OfficeFindHit>[],
    this.activeFindIndex = -1,
  });

  /// document API.
  WmlDocument document;

  /// laidOut API.
  LaidOutDocument laidOut;

  /// caret API.
  CaretEngine caret;

  /// viewport API.
  VirtualViewport viewport;

  /// config API.
  OfficeSurfaceConfig config;

  /// hasFocus API.
  bool hasFocus;

  /// semanticsLabel API.
  String semanticsLabel;

  /// semanticsValue API.
  String semanticsValue;

  /// selectedVisual API.
  WmlVisual? selectedVisual;

  /// selectedFrame API.
  WmlFrame? selectedFrame;

  /// Hide move/resize knobs and edit the frame text.
  bool editingFrame;

  /// selectedEquation API.
  WmlEquation? selectedEquation;

  /// equationSlot API.
  int equationSlot;

  /// equationCaret API.
  int equationCaret;

  /// pictureCropMode API.
  bool pictureCropMode;

  /// onBeginVisualTransform API.
  VoidCallback? onBeginVisualTransform;

  /// Function API.
  void Function(double dx, double dy)? onPreviewVisualMove;

  /// Function API.
  void Function({required double width, required double height})?
  /// onPreviewVisualResize API.
  onPreviewVisualResize;

  /// Function API.
  void Function({
    required double left,
    required double top,
    required double right,
    required double bottom,
  })?
  /// onPreviewVisualCrop API.
  onPreviewVisualCrop;

  /// onPreviewVisualRotate API.
  ValueChanged<double>? onPreviewVisualRotate;

  /// onCommitVisualTransform API.
  VoidCallback? onCommitVisualTransform;

  /// onBeginFrameTransform API.
  VoidCallback? onBeginFrameTransform;

  /// Function API.
  void Function(double dx, double dy)? onPreviewFrameMove;

  /// Function API.
  void Function({required double width, required double height})?
  onPreviewFrameResize;

  /// onCommitFrameTransform API.
  VoidCallback? onCommitFrameTransform;

  /// onChanged API.
  VoidCallback? onChanged;

  /// onSelectVisual API.
  ValueChanged<OfficeVisual?>? onSelectVisual;

  /// onSelectFrame API.
  ValueChanged<WmlFrame?>? onSelectFrame;

  /// Double-click enters text edit on a frame.
  ValueChanged<WmlFrame>? onEditFrame;

  /// Function API.
  void Function(WmlEquation? equation, int? slot, int? caret)? onSelectEquation;

  /// onActivateVisual API.
  ValueChanged<OfficeVisual>? onActivateVisual;

  /// onExtendThroughVisual API.
  ValueChanged<OfficeVisual>? onExtendThroughVisual;

  /// Function API.
  bool Function(OfficeVisual visual)? isVisualInSelection;

  /// onJumpParagraph API.
  ValueChanged<int>? onJumpParagraph;

  /// onFollowLink API.
  ValueChanged<WmlHyperlink>? onFollowLink;

  /// selectedCommentId API.
  int? selectedCommentId;

  /// onSelectComment API.
  ValueChanged<int?>? onSelectComment;

  /// onContextMenu API.
  ValueChanged<OfficeContextHit>? onContextMenu;

  /// Function API.
  void Function(WmlTable table, int index)? onInsertTableRowAt;

  /// Function API.
  void Function(WmlTable table, int index)? onInsertTableColumnAt;

  /// onBeginTableResize API.
  ValueChanged<WmlTable>? onBeginTableResize;

  /// Function API.
  void Function(WmlTable table, int col, double width)?
  /// onPreviewTableColumnWidth API.
  onPreviewTableColumnWidth;

  /// Function API.
  void Function(WmlTable table, int row, double height)?
  /// onPreviewTableRowHeight API.
  onPreviewTableRowHeight;

  /// onCommitTableResize API.
  ValueChanged<WmlTable>? onCommitTableResize;

  /// selectedTable API.
  WmlTable? selectedTable;

  /// onSelectTable API.
  ValueChanged<WmlTable?>? onSelectTable;

  /// selectedTableBand API.
  ({WmlTable table, bool column, int from, int to})? selectedTableBand;

  /// Function API.
  void Function(
    WmlTable table, {
    required bool column,
    required int from,
    required int to,
  })?
  /// onSelectTableBand API.
  onSelectTableBand;

  /// storyParagraphs API.
  List<WmlParagraph>? storyParagraphs;

  /// editingHeader API.
  bool editingHeader;

  /// editingFooter API.
  bool editingFooter;

  /// Function API.
  void Function(int pageIndex, {required bool footer})? onBeginHeaderFooterEdit;

  /// onEndHeaderFooterEdit API.
  VoidCallback? onEndHeaderFooterEdit;

  /// onBeginRulerEdit API.
  VoidCallback? onBeginRulerEdit;

  /// onPreviewRulerEdit API.
  ValueChanged<WordRulerEdit>? onPreviewRulerEdit;

  /// onCommitRulerEdit API.
  VoidCallback? onCommitRulerEdit;

  /// compact API.
  bool compact;

  /// findHits API.
  List<OfficeFindHit> findHits;

  /// activeFindIndex API.
  int activeFindIndex;

  /// editingFooter API.
  bool get _editingHeaderFooter => editingHeader || editingFooter;

  TapGestureRecognizer? _tap;
  PanGestureRecognizer? _pan;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;
  var _tapCount = 0;

  /// VisualImageCache API.
  final VisualImageCache _images = VisualImageCache();
  LaidOutDocument? _fittedLayout;
  final Set<LaidOutPage> _fittedPages = <LaidOutPage>{};
  int? _visualHandle;
  var _draggingVisual = false;
  int? _frameHandle;
  var _draggingFrame = false;
  ({WmlTable table, bool column, int index, double start})? _tableResize;
  ({WmlTable table, bool column, int anchor, int current})? _tableBand;
  Offset? _hoverLocal;
  var _scrollDrag = false;
  int? _scrollPageTip;
  var _panZoomScale = 1.0;
  RulerHit? _rulerHover;
  RulerHit? _rulerDrag;
  Offset? _rulerDown;
  WmlIndent? _rulerIndent;
  List<WmlTabStop>? _rulerTabs;
  WmlPageMargins? _rulerMargins;
  String? _rulerReadout;
  var _rulerCreatedTab = false;

  static const double _pointsToPixels = 96 / 72;
  static const double _scrollBar = 14;

  /// theme API.
  OfficeTheme get _theme => config.theme;

  double get _viewScale => viewport.scale * _pointsToPixels;

  @override
  /// cursor API.
  MouseCursor get cursor => cursorFor(_hoverLocal);

  @override
  /// onEnter API.
  PointerEnterEventListener? get onEnter => null;

  @override
  /// onExit API.
  PointerExitEventListener? get onExit => (_) {
    _hoverLocal = null;
  };

  @override
  /// validForMouseTracker API.
  bool get validForMouseTracker => attached;

  @override
  /// hitTestSelf API.
  bool hitTestSelf(Offset position) {
    _hoverLocal = position;
    return true;
  }

  /// cursorFor API.
  MouseCursor cursorFor(Offset? window) {
    if (window == null || !config.allowsSelection) {
      return SystemMouseCursors.basic;
    }
    if (_rulerDrag != null || _inRuler(window)) {
      return WordRuler.cursorFor(_rulerDrag ?? _rulerHit(window));
    }
    if (_draggingVisual) {
      return _cursorForHandle(_visualHandle ?? 9);
    }
    if (_draggingFrame) {
      return _cursorForHandle(_frameHandle ?? 9);
    }
    if (_tableResize != null) {
      return _tableResize!.column
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow;
    }
    if (_tableBand != null) {
      return _tableBand!.column
          ? SystemMouseCursors.resizeDown
          : SystemMouseCursors.resizeRight;
    }
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return SystemMouseCursors.basic;
    }
    final LaidOutPage laidPage = laidOut.pages[page];
    final LaidOutBox? selectedBox = _selectedVisualBoxOn(page);
    if (selectedBox != null && config.allowsMutation) {
      final int? handle = TransformHandles(
        Rect.fromLTWH(
          selectedBox.x,
          selectedBox.y,
          selectedBox.width,
          selectedBox.height,
        ),
      ).hit(local, radius: 12, showRotate: !pictureCropMode);
      if (handle != null) {
        return _cursorForHandle(handle);
      }
      if (_boxContains(selectedBox, local, pad: 2)) {
        return SystemMouseCursors.move;
      }
    }
    final LaidOutBox? selectedFrameBox = _selectedFrameBoxOn(page);
    if (selectedFrameBox != null && config.allowsMutation) {
      if (editingFrame) {
        if (_boxContains(selectedFrameBox, local, pad: 2)) {
          return SystemMouseCursors.text;
        }
      } else {
        final int? handle = TransformHandles(
          Rect.fromLTWH(
            selectedFrameBox.x,
            selectedFrameBox.y,
            selectedFrameBox.width,
            selectedFrameBox.height,
          ),
        ).hit(local, radius: 12, showRotate: false);
        if (handle != null) {
          return _cursorForHandle(handle);
        }
        if (_boxContains(selectedFrameBox, local, pad: 2)) {
          return SystemMouseCursors.move;
        }
      }
    }
    final WmlHyperlink? link = _linkAt(laidPage, local);
    if (link != null) {
      return _ctrlFollow ? SystemMouseCursors.click : SystemMouseCursors.text;
    }
    if (_equationAt(laidPage, local) != null) {
      return SystemMouseCursors.text;
    }
    final LaidOutBox? visualBox = _visualAt(laidPage, local);
    if (visualBox != null) {
      return config.allowsMutation
          ? SystemMouseCursors.grab
          : SystemMouseCursors.click;
    }
    if (_frameAt(laidPage, local) != null) {
      return config.allowsMutation
          ? SystemMouseCursors.grab
          : SystemMouseCursors.click;
    }
    if (_tableHandleAt(laidPage, local) != null ||
        _insertHoverAt(laidPage, local) != null) {
      return SystemMouseCursors.click;
    }
    final MouseCursor? table = _tableEdgeCursor(laidPage, local);
    if (table != null) {
      return table;
    }
    final _TableBandHit? band = _tableBandAt(laidPage, local);
    if (band != null) {
      return band.column
          ? SystemMouseCursors.resizeDown
          : SystemMouseCursors.resizeRight;
    }
    if (local.dx >= 0 &&
        local.dx <= laidPage.width &&
        local.dy >= 0 &&
        local.dy <= laidPage.height) {
      return SystemMouseCursors.text;
    }
    return SystemMouseCursors.basic;
  }

  static MouseCursor _cursorForHandle(int handle) {
    return switch (handle) {
      0 || 4 => SystemMouseCursors.resizeUpLeftDownRight,
      2 || 6 => SystemMouseCursors.resizeUpRightDownLeft,
      1 || 5 => SystemMouseCursors.resizeUpDown,
      3 || 7 => SystemMouseCursors.resizeLeftRight,
      8 => SystemMouseCursors.grab,
      9 => SystemMouseCursors.move,
      _ => SystemMouseCursors.basic,
    };
  }

  /// pad API.
  static bool _boxContains(LaidOutBox box, Offset local, {double pad = 0}) {
    return local.dx >= box.x - pad &&
        local.dx <= box.x + box.width + pad &&
        local.dy >= box.y - pad &&
        local.dy <= box.y + box.height + pad;
  }

  LaidOutBox? _selectedVisualBoxOn(int page) {
    final WmlVisual? selected = selectedVisual;
    if (selected == null || page < 0 || page >= laidOut.pages.length) {
      return null;
    }
    for (final LaidOutBox box in laidOut.pages[page].frames) {
      if (box.visual != null && identical(box.visual, selected.visual)) {
        return box;
      }
    }
    return null;
  }

  MouseCursor? _tableEdgeCursor(LaidOutPage page, Offset local) {
    final ({WmlTable table, bool column, int index, double start})? edge =
        _tableEdgeAt(page, local);
    if (edge == null) {
      return null;
    }
    return edge.column
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;
  }

  ({WmlTable table, bool column, int index, double start})? _tableEdgeAt(
    LaidOutPage page,
    Offset local,
  ) {
    if (!config.allowsMutation) {
      return null;
    }
    const double slop = 5;
    for (final _TableGeom table in _tablesOn(page)) {
      if (!table.bounds.inflate(slop).contains(local)) {
        continue;
      }
      for (int i = 1; i <= table.colCount; i++) {
        final double x = table.colBoundary(i);
        if ((local.dx - x).abs() <= slop) {
          final int col = i - 1;
          final double width = col < table.table.grid.length
              ? table.table.grid[col]
              : (table.colBoundary(i) - table.colBoundary(col)).clamp(24, 900);
          return (table: table.table, column: true, index: col, start: width);
        }
      }
      for (int i = 1; i <= table.rowCount; i++) {
        final double y = table.rowBoundary(i);
        if ((local.dy - y).abs() <= slop) {
          final int row = i - 1;
          final double height = row < table.table.rows.length
              ? (table.table.rows[row].height ??
                    (table.rowBoundary(i) - table.rowBoundary(row)))
              : 24;
          return (table: table.table, column: false, index: row, start: height);
        }
      }
    }
    return null;
  }

  bool _tryTableResize(Offset window) {
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return false;
    }
    final ({WmlTable table, bool column, int index, double start})? edge =
        _tableEdgeAt(laidOut.pages[page], local);
    if (edge == null) {
      return false;
    }
    _tableResize = edge;
    onBeginTableResize?.call(edge.table);
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  void _dragTableEdge(Offset delta) {
    final ({WmlTable table, bool column, int index, double start})? drag =
        _tableResize;
    if (drag == null) {
      return;
    }
    final Offset page = Offset(delta.dx / _viewScale, delta.dy / _viewScale);
    if (drag.column) {
      final double next = (drag.start + page.dx).clamp(24, 900);
      _tableResize = (
        table: drag.table,
        column: true,
        index: drag.index,
        start: next,
      );
      onPreviewTableColumnWidth?.call(drag.table, drag.index, next);
    } else {
      final double next = (drag.start + page.dy).clamp(16, 480);
      _tableResize = (
        table: drag.table,
        column: false,
        index: drag.index,
        start: next,
      );
      onPreviewTableRowHeight?.call(drag.table, drag.index, next);
    }
  }

  @override
  /// performLayout API.
  void performLayout() {
    final double scale = compact ? 1 : _viewScale;
    final Size content;
    if (compact) {
      var bottom = 24.0;
      if (laidOut.pages.isNotEmpty) {
        for (final LaidOutLine line in laidOut.pages.first.lines) {
          final double edge = line.y + line.height;
          if (edge > bottom) {
            bottom = edge;
          }
        }
      }
      content = Size(
        constraints.hasBoundedWidth
            ? constraints.maxWidth
            : laidOut.pageSize.width,
        bottom + 8,
      );
    } else {
      var maxW = laidOut.pageSize.width;
      var stackH = 24.0;
      for (final LaidOutPage page in laidOut.pages) {
        if (page.width > maxW) {
          maxW = page.width;
        }
        stackH += page.height * scale + 24;
      }
      if (laidOut.pages.isEmpty) {
        stackH += laidOut.pageSize.height * scale + 24;
      }
      content = Size(maxW * scale + 64, stackH);
    }
    size = compact
        ? constraints.constrain(content)
        : (constraints.hasBoundedWidth && constraints.hasBoundedHeight
              ? constraints.constrain(constraints.biggest)
              : constraints.constrain(content));
    viewport.extent = size;
    if (!compact) {
      _clampViewport();
    }
    _resetPaintFit();
  }

  static const double _pageSideGutter = 64;

  double get _maxPageWidthPt {
    var maxW = laidOut.pageSize.width;
    for (final LaidOutPage page in laidOut.pages) {
      if (page.width > maxW) {
        maxW = page.width;
      }
    }
    return maxW;
  }

  Size get _contentSize {
    final double scale = _viewScale;
    var stackH = 24.0;
    for (final LaidOutPage page in laidOut.pages) {
      stackH += page.height * scale + 24;
    }
    if (laidOut.pages.isEmpty) {
      stackH += laidOut.pageSize.height * scale + 24;
    }
    return Size(
      _maxPageWidthPt * scale + _pageSideGutter * 2 + _scrollBar,
      stackH,
    );
  }

  void _clampViewport() {
    viewport.clampTo(content: _contentSize, view: size);
  }

  double get _rulerInset => config.showRulers ? OfficeChrome.rulerSize : 0;

  Rect get _vTrack {
    final double top = _rulerInset;
    return Rect.fromLTWH(
      size.width - _scrollBar,
      top,
      _scrollBar,
      math.max(0, size.height - top),
    );
  }

  /// max API.
  double get _maxScrollY => math.max(0, _contentSize.height - size.height);

  Rect get _vThumb {
    final double maxY = _maxScrollY;
    final double trackH = _vTrack.height;
    final double thumbH =
        (_contentSize.height <= 0
                ? 22.0
                : trackH * (size.height / _contentSize.height))
            .clamp(22.0, trackH);
    final double y = maxY <= 0
        ? _vTrack.top
        : _vTrack.top + (trackH - thumbH) * (viewport.origin.dy / maxY);
    return Rect.fromLTWH(_vTrack.left + 2, y, _vTrack.width - 4, thumbH);
  }

  int _pageAtViewport() {
    return laidOut.pageIndexAtContentY(
      viewport.origin.dy + size.height * 0.35,
      _viewScale,
    );
  }

  void _jumpScroll(Offset local) {
    final double maxY = _maxScrollY;
    if (maxY <= 0 || _vTrack.height <= 0) {
      return;
    }
    final double t = ((local.dy - _vTrack.top) / _vTrack.height).clamp(0, 1);
    viewport.origin = Offset(viewport.origin.dx, maxY * t);
    _clampViewport();
    _scrollPageTip = _pageAtViewport();
  }

  void _dragScroll(Offset delta) {
    final double maxY = _maxScrollY;
    if (maxY <= 0 || _vTrack.height <= 0) {
      return;
    }
    viewport.origin = Offset(
      viewport.origin.dx,
      viewport.origin.dy + delta.dy * (maxY / _vTrack.height),
    );
    _clampViewport();
    _scrollPageTip = _pageAtViewport();
    markNeedsPaint();
    onChanged?.call();
  }

  void _paintScrollBar(Canvas canvas) {
    if (compact) {
      return;
    }
    canvas.drawRect(_vTrack, Paint()..color = const Color(0xFFE8E8E8));
    canvas.drawRRect(
      RRect.fromRectAndRadius(_vThumb, const Radius.circular(4)),
      Paint()..color = const Color(0xFF7A7A7A),
    );
    final int? tip = _scrollPageTip;
    if (tip == null) {
      return;
    }
    final String label = '${tip + 1} / ${laidOut.pages.length}';
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
    final double tipX = (_vTrack.left - tipW - 8).clamp(
      8,
      size.width - tipW - 8,
    );
    final double tipY = (_vThumb.center.dy - tipH / 2).clamp(
      8,
      size.height - tipH - 8,
    );
    final RRect bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(tipX, tipY, tipW, tipH),
      const Radius.circular(4),
    );
    canvas.drawRRect(bubble, Paint()..color = const Color(0xE62B2B2B));
    painter.paint(canvas, Offset(tipX + 8, tipY + 5));
  }

  @override
  /// detach API.
  void detach() {
    _tap?.dispose();
    _pan?.dispose();
    _tap = null;
    _pan = null;
    super.detach();
  }

  void _ensureRecognizers() {
    _tap ??= TapGestureRecognizer(debugOwner: this);
    _pan ??= PanGestureRecognizer(debugOwner: this)
      ..onUpdate = (DragUpdateDetails details) {
        if (_scrollDrag) {
          _dragScroll(details.delta);
          return;
        }
        if (_draggingVisual) {
          _dragVisual(details.delta);
          return;
        }
        if (_draggingFrame) {
          _dragFrame(details.delta);
          return;
        }
        if (_tableResize != null) {
          _dragTableEdge(details.delta);
          return;
        }
        if (_tableBand != null) {
          _extendTableBand(details.localPosition);
          return;
        }
        if (_rulerDrag != null) {
          _dragRuler(details.localPosition);
          return;
        }
        if (_selectEquationAt(details.localPosition)) {
          return;
        }
        _placeCaret(details.localPosition, extend: true);
      }
      ..onEnd = (DragEndDetails details) {
        if (_scrollDrag) {
          _scrollDrag = false;
          _scrollPageTip = null;
          markNeedsPaint();
          onChanged?.call();
          return;
        }
        if (_draggingVisual) {
          onCommitVisualTransform?.call();
          _draggingVisual = false;
          _visualHandle = null;
        }
        if (_draggingFrame) {
          onCommitFrameTransform?.call();
          _draggingFrame = false;
          _frameHandle = null;
        }
        if (_tableResize != null) {
          onCommitTableResize?.call(_tableResize!.table);
          _tableResize = null;
        }
        if (_rulerDrag != null) {
          _finishRuler();
        }
        _tableBand = null;
      };
  }

  bool get _zoomKeys =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  void _finishPointerScroll() {
    _clampViewport();
    _scrollPageTip = _pageAtViewport();
    markNeedsPaint();
    onChanged?.call();
  }

  void _applyWheelScroll(PointerScrollEvent event) {
    if (_zoomKeys) {
      viewport.setScale(
        viewport.scale * (event.scrollDelta.dy > 0 ? 0.9 : 1.1),
      );
    } else {
      Offset delta = event.scrollDelta;
      if (HardwareKeyboard.instance.isShiftPressed &&
          delta.dx.abs() < delta.dy.abs()) {
        delta = Offset(delta.dy, 0);
      }
      viewport.pan(delta);
    }
    _finishPointerScroll();
  }

  void _applyPanZoom(PointerPanZoomUpdateEvent event) {
    if (_zoomKeys || (event.scale - _panZoomScale).abs() > 0.02) {
      final double current = _panZoomScale == 0 ? 1 : _panZoomScale;
      viewport.setScale(viewport.scale * (event.scale / current));
      _panZoomScale = event.scale == 0 ? current : event.scale;
    } else {
      viewport.pan(-event.localPanDelta);
    }
    _finishPointerScroll();
  }

  @override
  /// handleEvent API.
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (compact &&
        (event is PointerScrollEvent ||
            event is PointerPanZoomStartEvent ||
            event is PointerPanZoomUpdateEvent ||
            event is PointerPanZoomEndEvent)) {
      return;
    }
    if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (
        PointerSignalEvent signal,
      ) {
        if (signal is PointerScrollEvent) {
          _applyWheelScroll(signal);
        }
      });
      return;
    }
    if (event is PointerPanZoomStartEvent) {
      _panZoomScale = 1;
      return;
    }
    if (event is PointerPanZoomUpdateEvent) {
      _applyPanZoom(event);
      return;
    }
    if (event is PointerPanZoomEndEvent) {
      _panZoomScale = 1;
      _scrollPageTip = null;
      markNeedsPaint();
      return;
    }
    if (event is PointerHoverEvent || event is PointerMoveEvent) {
      _hoverLocal = event.localPosition;
      _rulerHover = _inRuler(event.localPosition)
          ? _rulerHit(event.localPosition)
          : null;
      if (!compact && _vTrack.contains(event.localPosition)) {
        _scrollPageTip = _pageAtViewport();
      } else if (!_scrollDrag) {
        _scrollPageTip = null;
      }
      markNeedsPaint();
    }
    if (event is PointerDownEvent &&
        !compact &&
        _vTrack.contains(event.localPosition)) {
      _scrollDrag = true;
      _jumpScroll(event.localPosition);
      _ensureRecognizers();
      _pan!.addPointer(event);
      markNeedsPaint();
      onChanged?.call();
      return;
    }
    if (!config.allowsSelection) {
      return;
    }
    if (event is PointerDownEvent) {
      if (event.buttons == kSecondaryMouseButton) {
        _handleContext(event);
        return;
      }
      if (_tryRuler(event.localPosition)) {
        _ensureRecognizers();
        _pan!.addPointer(event);
        return;
      }
      if (_tryTableHandle(event.localPosition)) {
        return;
      }
      if (_tryTableResize(event.localPosition)) {
        _ensureRecognizers();
        _pan!.addPointer(event);
        return;
      }
      if (_tryInsertHandle(event.localPosition)) {
        return;
      }
      if (_tryTableBand(event.localPosition)) {
        _ensureRecognizers();
        _pan!.addPointer(event);
        return;
      }
      _ensureRecognizers();
      _tap!.addPointer(event);
      _pan!.addPointer(event);
      _handleClick(event.localPosition);
    }
  }

  bool _inRuler(Offset local) {
    return config.showRulers &&
        !compact &&
        (local.dy <= WordRuler.size || local.dx <= WordRuler.size);
  }

  List<WmlParagraph> _rulerStory() {
    return storyParagraphs ?? document.paragraphs.toList();
  }

  /// Page the sticky rulers follow: the caret's page (active), not merely
  /// whichever sheet sits under the top of the viewport.
  int _activeRulerPageIndex() {
    if (laidOut.pages.isEmpty) {
      return 0;
    }
    final LaidOutLine? caretLine = _lineForParagraph(_caretParagraph());
    if (caretLine != null &&
        caretLine.pageIndex >= 0 &&
        caretLine.pageIndex < laidOut.pages.length) {
      return caretLine.pageIndex;
    }
    return laidOut
        .pageIndexAtContentY(
          viewport.origin.dy + WordRuler.size + 8,
          _viewScale,
        )
        .clamp(0, laidOut.pages.length - 1);
  }

  WmlParagraph? _rulerParagraph() {
    final List<WmlParagraph> paras = _rulerStory();
    if (paras.isEmpty) {
      return null;
    }
    final LaidOutLine? focus = _rulerFocusLine();
    if (focus != null) {
      return paras[focus.paragraphIndex.clamp(0, paras.length - 1)];
    }
    return paras[caret.paragraphIndex.clamp(0, paras.length - 1)];
  }

  WmlSection _rulerSection() {
    if (laidOut.pages.isEmpty || document.sections.isEmpty) {
      return document.sections.isEmpty ? WmlSection() : document.sections.first;
    }
    final int sectionIndex = laidOut.pages[_activeRulerPageIndex()].sectionIndex
        .clamp(0, document.sections.length - 1);
    return document.sections[sectionIndex];
  }

  LaidOutLine? _rulerFocusLine() {
    if (laidOut.pages.isEmpty) {
      return null;
    }
    final int pageIndex = _activeRulerPageIndex();
    final LaidOutPage page = laidOut.pages[pageIndex];
    return WordRuler.pickFocusLine(
      activePageIndex: pageIndex,
      caretLine: _lineForParagraph(_caretParagraph()),
      pageLines: _editingHeaderFooter
          ? (editingFooter ? page.footer : page.header)
          : page.lines,
    );
  }

  WmlParagraph? _caretParagraph() {
    final List<WmlParagraph> paras = _rulerStory();
    if (paras.isEmpty) {
      return null;
    }
    return paras[caret.paragraphIndex.clamp(0, paras.length - 1)];
  }

  _RulerView _rulerView() {
    final int pageIndex = laidOut.pages.isEmpty ? 0 : _activeRulerPageIndex();
    final WmlSection section = _rulerSection();
    final LaidOutLine? focus = _rulerFocusLine();
    final WmlParagraph? para = _rulerParagraph();
    final WmlIndent indent =
        _rulerIndent ?? para?.properties.indent ?? const WmlIndent();
    final List<WmlTabStop> tabs =
        _rulerTabs ?? para?.properties.tabs ?? const <WmlTabStop>[];
    final WmlPageMargins margins = _rulerMargins ?? section.margins;
    final bool rtl =
        para?.properties.rightToLeft == true ||
        para?.properties.bidiBaseLevel == 1;
    final ({double left, double right}) box = _rulerContentBox(
      section,
      para,
      focus: focus,
      pageIndex: pageIndex,
    );
    return _RulerView(
      pageLeft: _pageLeftPx() - viewport.origin.dx,
      pageTop: laidOut.pageStackTop(pageIndex, _viewScale) - viewport.origin.dy,
      scale: _viewScale,
      pageWidth: section.pageSize.width,
      pageHeight: section.pageSize.height,
      margins: margins,
      indent: indent,
      tabs: tabs,
      rtl: rtl,
      contentLeft: box.left,
      contentRight: box.right,
    );
  }

  ({double left, double right}) _rulerContentBox(
    WmlSection section,
    WmlParagraph? para, {
    LaidOutLine? focus,
    required int pageIndex,
  }) {
    final LaidOutLine? line = focus ?? _lineForParagraph(para);
    final int paraIndex = line?.paragraphIndex ?? caret.paragraphIndex;
    final LaidOutBox? cell = _cellBoxForParagraph(paraIndex);
    final WmlFrame? selectedOnPage = _frameOnPage(selectedFrame, pageIndex);
    final WmlFrame? frame = selectedOnPage ?? _frameContaining(para);
    var columnIndex = 0;
    if (section.resolvedColumnCount > 1) {
      final double probe = line != null && line.boxWidth > 0
          ? line.boxX
          : line?.x ?? section.margins.left;
      columnIndex = _columnIndexForX(section, probe);
    }
    return WordRuler.paragraphContentBox(
      margins: section.margins,
      pageWidth: section.pageSize.width,
      lineBoxX: line != null && line.boxWidth > 0 ? line.boxX : null,
      lineBoxWidth: line != null && line.boxWidth > 0 ? line.boxWidth : null,
      cellX: cell?.x,
      cellWidth: cell?.width,
      frameX: frame?.pageX(section),
      frameWidth: frame?.width,
      columnCount: section.resolvedColumnCount,
      columnIndex: columnIndex,
      columnWidth: section.columnWidth,
      columnSpace: section.columnSpace,
      preferFrame: selectedOnPage != null,
    );
  }

  WmlFrame? _frameOnPage(WmlFrame? frame, int pageIndex) {
    if (frame == null || pageIndex < 0 || pageIndex >= laidOut.pages.length) {
      return null;
    }
    for (final LaidOutBox box in laidOut.pages[pageIndex].frames) {
      if (identical(box.frame, frame)) {
        return frame;
      }
    }
    return null;
  }

  LaidOutLine? _lineForParagraph(WmlParagraph? para) {
    if (para == null) {
      return null;
    }
    final int index = caret.paragraphIndex;
    LaidOutLine? first;
    for (final LaidOutPage page in laidOut.pages) {
      final List<LaidOutLine> pool = _editingHeaderFooter
          ? <LaidOutLine>[
              if (editingHeader) ...page.header,
              if (editingFooter) ...page.footer,
            ]
          : page.lines;
      for (final LaidOutLine line in pool) {
        if (line.paragraphIndex != index) {
          continue;
        }
        first ??= line;
        final bool last = _isLastParagraphLine(page, line);
        if (caret.isOnLine(line, lastOfParagraph: last)) {
          return line;
        }
      }
    }
    return first;
  }

  LaidOutBox? _cellBoxForParagraph(int paraIndex) {
    for (final LaidOutPage page in laidOut.pages) {
      for (final LaidOutBox box in page.frames) {
        if (box.table == null) {
          continue;
        }
        final int? start = box.paragraphIndex;
        if (start == null) {
          continue;
        }
        final int end = box.paragraphEnd ?? start;
        if (paraIndex >= start && paraIndex <= end) {
          return box;
        }
      }
    }
    return null;
  }

  int _columnIndexForX(WmlSection section, double pageX) {
    var best = 0;
    for (int i = 0; i < section.resolvedColumnCount; i++) {
      if (pageX >= section.columnOriginX(i) - 1) {
        best = i;
      }
    }
    return best;
  }

  WmlFrame? _frameContaining(WmlParagraph? target) {
    if (target == null) {
      return null;
    }
    WmlFrame? walk(List<WmlBlock> blocks) {
      for (final WmlBlock block in blocks) {
        if (block is WmlFrame) {
          if (_paragraphIn(block.blocks, target)) {
            return block;
          }
          final WmlFrame? nested = walk(block.blocks);
          if (nested != null) {
            return nested;
          }
        } else if (block is WmlTable) {
          for (final WmlTableRow row in block.rows) {
            for (final WmlTableCell cell in row.cells) {
              final WmlFrame? found = walk(cell.blocks);
              if (found != null) {
                return found;
              }
            }
          }
        }
      }
      return null;
    }

    for (final WmlSection section in document.sections) {
      final WmlFrame? found = walk(section.blocks);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  bool _paragraphIn(List<WmlBlock> blocks, WmlParagraph target) {
    for (final WmlBlock block in blocks) {
      if (identical(block, target)) {
        return true;
      }
      if (block is WmlFrame && _paragraphIn(block.blocks, target)) {
        return true;
      }
      if (block is WmlTable) {
        for (final WmlTableRow row in block.rows) {
          for (final WmlTableCell cell in row.cells) {
            if (_paragraphIn(cell.blocks, target)) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  RulerHit? _rulerHit(Offset local) {
    final _RulerView view = _rulerView();
    return WordRuler.hit(
      local: local,
      view: size,
      pageLeft: view.pageLeft,
      pageTop: view.pageTop,
      scale: view.scale,
      pageWidth: view.pageWidth,
      pageHeight: view.pageHeight,
      margins: view.margins,
      indent: view.indent,
      tabs: view.tabs,
      rtl: view.rtl,
      contentLeft: view.contentLeft,
      contentRight: view.contentRight,
    );
  }

  bool _tryRuler(Offset local) {
    if (!_inRuler(local) || !config.allowsMutation) {
      return false;
    }
    final RulerHit? hit = _rulerHit(local);
    if (hit == null) {
      return false;
    }
    final _RulerView view = _rulerView();
    _rulerDown = local;
    _rulerIndent = view.indent;
    _rulerTabs = List<WmlTabStop>.from(view.tabs);
    _rulerMargins = view.margins;
    onBeginRulerEdit?.call();
    if (hit.kind == RulerHitKind.track && local.dy <= WordRuler.size) {
      final bool snapOff = HardwareKeyboard.instance.isAltPressed;
      final double px = WordRuler.snap(
        WordRuler.pageX(local.dx, pageLeft: view.pageLeft, scale: view.scale),
        disable: snapOff,
      );
      final double pos = WordRuler.tabPosition(
        pageX: px,
        margins: view.margins,
        pageWidth: view.pageWidth,
        rtl: view.rtl,
        contentLeft: view.contentLeft,
        contentRight: view.contentRight,
      );
      _rulerTabs = <WmlTabStop>[..._rulerTabs!, WmlTabStop(position: pos)];
      _rulerCreatedTab = true;
      _rulerDrag = RulerHit(RulerHitKind.tab, tabIndex: _rulerTabs!.length - 1);
      onPreviewRulerEdit?.call(WordRulerEdit(tabs: _rulerTabs));
    } else {
      _rulerCreatedTab = false;
      _rulerDrag = hit;
    }
    markNeedsPaint();
    return true;
  }

  void _dragRuler(Offset local) {
    final RulerHit? drag = _rulerDrag;
    if (drag == null) {
      return;
    }
    final _RulerView view = _rulerView();
    final bool snapOff = HardwareKeyboard.instance.isAltPressed;
    if (drag.kind == RulerHitKind.tab) {
      if ((local.dy - WordRuler.size).abs() > 28 && local.dy > WordRuler.size) {
        final int? i = drag.tabIndex;
        if (i != null &&
            _rulerTabs != null &&
            i >= 0 &&
            i < _rulerTabs!.length) {
          _rulerTabs = <WmlTabStop>[
            for (int t = 0; t < _rulerTabs!.length; t++)
              if (t != i) _rulerTabs![t],
          ];
          _rulerDrag = const RulerHit(RulerHitKind.track);
          _rulerReadout = null;
          onPreviewRulerEdit?.call(WordRulerEdit(tabs: _rulerTabs));
        }
        markNeedsPaint();
        return;
      }
      final double px = WordRuler.snap(
        WordRuler.pageX(local.dx, pageLeft: view.pageLeft, scale: view.scale),
        disable: snapOff,
      );
      final double pos = WordRuler.tabPosition(
        pageX: px,
        margins: view.margins,
        pageWidth: view.pageWidth,
        rtl: view.rtl,
        contentLeft: view.contentLeft,
        contentRight: view.contentRight,
      );
      final int i = drag.tabIndex ?? 0;
      if (_rulerTabs != null && i >= 0 && i < _rulerTabs!.length) {
        final WmlTabStop old = _rulerTabs![i];
        _rulerTabs = <WmlTabStop>[
          for (int t = 0; t < _rulerTabs!.length; t++)
            if (t == i)
              WmlTabStop(
                position: pos,
                alignment: old.alignment,
                leader: old.leader,
              )
            else
              _rulerTabs![t],
        ];
        _rulerReadout = WordRuler.inchLabel(pos);
        onPreviewRulerEdit?.call(WordRulerEdit(tabs: _rulerTabs));
      }
      markNeedsPaint();
      return;
    }
    if (drag.kind == RulerHitKind.marginLeft ||
        drag.kind == RulerHitKind.marginRight ||
        drag.kind == RulerHitKind.marginTop ||
        drag.kind == RulerHitKind.marginBottom) {
      final double pos =
          drag.kind == RulerHitKind.marginTop ||
              drag.kind == RulerHitKind.marginBottom
          ? WordRuler.snap(
              WordRuler.pageY(
                local.dy,
                pageTop: view.pageTop,
                scale: view.scale,
              ),
              disable: snapOff,
            )
          : WordRuler.snap(
              WordRuler.pageX(
                local.dx,
                pageLeft: view.pageLeft,
                scale: view.scale,
              ),
              disable: snapOff,
            );
      _rulerMargins = WordRuler.applyMarginDrag(
        margins: _rulerMargins ?? view.margins,
        kind: drag.kind,
        pagePos: pos,
        pageWidth: view.pageWidth,
        pageHeight: view.pageHeight,
      );
      _rulerReadout = WordRuler.inchLabel(pos);
      onPreviewRulerEdit?.call(WordRulerEdit(margins: _rulerMargins));
      markNeedsPaint();
      return;
    }
    final double px = WordRuler.snap(
      WordRuler.pageX(local.dx, pageLeft: view.pageLeft, scale: view.scale),
      disable: snapOff,
    );
    _rulerIndent = WordRuler.applyIndentDrag(
      indent: _rulerIndent ?? view.indent,
      kind: drag.kind,
      pageX: px,
      margins: view.margins,
      pageWidth: view.pageWidth,
      rtl: view.rtl,
      contentLeft: view.contentLeft,
      contentRight: view.contentRight,
    );
    _rulerReadout = WordRuler.inchLabel(
      view.rtl ? view.contentRight - px : px - view.contentLeft,
    );
    onPreviewRulerEdit?.call(WordRulerEdit(indent: _rulerIndent));
    markNeedsPaint();
  }

  void _finishRuler() {
    final RulerHit? drag = _rulerDrag;
    final Offset? down = _rulerDown;
    if (!_rulerCreatedTab &&
        drag?.kind == RulerHitKind.tab &&
        down != null &&
        _hoverLocal != null &&
        (_hoverLocal! - down).distance < 3 &&
        _rulerTabs != null &&
        drag!.tabIndex != null &&
        drag.tabIndex! < _rulerTabs!.length) {
      final WmlTabStop old = _rulerTabs![drag.tabIndex!];
      _rulerTabs = <WmlTabStop>[
        for (int t = 0; t < _rulerTabs!.length; t++)
          if (t == drag.tabIndex)
            WmlTabStop(
              position: old.position,
              alignment: WordRuler.cycleAlignment(old.alignment),
              leader: old.leader,
            )
          else
            _rulerTabs![t],
      ];
      onPreviewRulerEdit?.call(WordRulerEdit(tabs: _rulerTabs));
    }
    onCommitRulerEdit?.call();
    _rulerDrag = null;
    _rulerDown = null;
    _rulerIndent = null;
    _rulerTabs = null;
    _rulerMargins = null;
    _rulerReadout = null;
    _rulerCreatedTab = false;
    markNeedsPaint();
    onChanged?.call();
  }

  double _pageLeftPx() {
    if (compact) {
      return 0;
    }
    final double pageW = _maxPageWidthPt * _viewScale;
    final double viewW = math.max(0, size.width - _scrollBar);
    if (viewW > pageW + _pageSideGutter * 2) {
      return (viewW - pageW) / 2;
    }
    return _pageSideGutter;
  }

  /// Local position of [point] (page points) on page [page]: the inverse
  /// of pointer hit testing, for anchoring host overlays and tests.
  Offset windowForPagePoint(int page, Offset point) {
    if (compact) {
      return point;
    }
    final double scale = _viewScale;
    var top = 24.0;
    for (int i = 0; i < page && i < laidOut.pages.length; i++) {
      top += laidOut.pages[i].height * scale + 24;
    }
    return Offset(
      point.dx * scale + _pageLeftPx() - viewport.origin.dx,
      point.dy * scale + top - viewport.origin.dy,
    );
  }

  (int, Offset) _hitPage(Offset window) {
    if (compact) {
      return (0, window);
    }
    final double scale = _viewScale;
    final double x = (window.dx + viewport.origin.dx - _pageLeftPx()) / scale;
    var top = 24.0;
    for (int i = 0; i < laidOut.pages.length; i++) {
      final LaidOutPage page = laidOut.pages[i];
      final double y = (window.dy + viewport.origin.dy - top) / scale;
      if (y >= -8 && y <= page.height + 8) {
        return (i, Offset(x, y));
      }
      top += page.height * scale + 24;
    }
    return (0, Offset(x, (window.dy + viewport.origin.dy - 24) / scale));
  }

  void _handleClick(Offset window) {
    final bool extend = HardwareKeyboard.instance.isShiftPressed;
    final int taps = extend ? 1 : _countTap(window);
    final (int page, Offset local) = _hitPage(window);
    _fitPageAt(page);
    if (page >= 0 && page < laidOut.pages.length) {
      final bool? chromeFooter = _chromeHit(laidOut.pages[page], local);
      if (taps >= 2 && chromeFooter != null && config.allowsMutation) {
        onBeginHeaderFooterEdit?.call(page, footer: chromeFooter);
        markNeedsPaint();
        onChanged?.call();
        return;
      }
      if (_editingHeaderFooter) {
        if (chromeFooter != null &&
            ((chromeFooter && editingFooter) ||
                (!chromeFooter && editingHeader))) {
          _placeChromeCaret(laidOut.pages[page], local, extend: extend);
          markNeedsPaint();
          onChanged?.call();
          return;
        }
        onEndHeaderFooterEdit?.call();
      }
      if (_tryTableHandle(window)) {
        return;
      }
      if (_selectEquationAt(window)) {
        return;
      }
      final WmlHyperlink? link = _linkAt(laidOut.pages[page], local);
      if (link != null && _ctrlFollow) {
        onFollowLink?.call(link);
        markNeedsPaint();
        onChanged?.call();
        return;
      }
      final int? commentId = _commentIdAt(laidOut.pages[page], local);
      onSelectComment?.call(commentId);
      if (_trySelectedVisualHandle(page, local)) {
        return;
      }
      if (_trySelectedFrameHandle(page, local)) {
        return;
      }
      final LaidOutBox? visualBox = _visualAt(laidOut.pages[page], local);
      final OfficeVisual? visual = visualBox?.visual;
      if (visual != null) {
        if (extend) {
          onExtendThroughVisual?.call(visual);
        } else {
          onSelectVisual?.call(visual);
        }
        if (config.allowsMutation && !extend) {
          final int? handle = visualBox == null
              ? null
              : TransformHandles(
                  Rect.fromLTWH(
                    visualBox.x,
                    visualBox.y,
                    visualBox.width,
                    visualBox.height,
                  ),
                ).hit(local, radius: 14);
          _visualHandle = handle ?? 9;
          _draggingVisual = true;
          onBeginVisualTransform?.call();
        }
        markNeedsPaint();
        onChanged?.call();
        return;
      }
      final LaidOutBox? frameBox = _frameAt(laidOut.pages[page], local);
      final WmlFrame? frame = frameBox?.frame;
      if (frame != null) {
        if (taps >= 2) {
          onEditFrame?.call(frame);
          _placeCaret(window, extend: extend, notify: false);
        } else if (editingFrame && identical(frame, selectedFrame)) {
          _placeCaret(window, extend: extend, notify: false);
        } else {
          onSelectFrame?.call(frame);
          if (config.allowsMutation && !extend) {
            final int? handle = TransformHandles(
              Rect.fromLTWH(
                frameBox!.x,
                frameBox.y,
                frameBox.width,
                frameBox.height,
              ),
            ).hit(local, radius: 14, showRotate: false);
            _frameHandle = handle ?? 9;
            _draggingFrame = true;
            onBeginFrameTransform?.call();
          }
        }
        markNeedsPaint();
        onChanged?.call();
        return;
      }
    }
    onSelectVisual?.call(null);
    onSelectFrame?.call(null);
    onSelectEquation?.call(null, null, null);
    onSelectTable?.call(null);
    _placeCaret(window, extend: extend, notify: false);
    if (!extend) {
      final String text = _paragraphText();
      if (taps >= 3) {
        caret.selectParagraph(text);
      } else if (taps == 2) {
        caret.selectWord(text, caret.logicalIndex);
      }
    }
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

  String _paragraphText() {
    final List<WmlParagraph> paras =
        storyParagraphs ?? document.paragraphs.toList();
    if (paras.isEmpty) {
      return '';
    }
    return paras[caret.paragraphIndex.clamp(0, paras.length - 1)].text;
  }

  bool? _chromeHit(LaidOutPage page, Offset local) {
    if (page.footerBand.contains(local.dx, local.dy)) {
      return true;
    }
    if (page.headerBand.contains(local.dx, local.dy)) {
      return false;
    }
    return null;
  }

  void _placeChromeCaret(
    LaidOutPage page,
    Offset local, {
    required bool extend,
  }) {
    final List<LaidOutLine> story = editingFooter ? page.footer : page.header;
    LaidOutLine? line = _nearestChromeLine(story, local);
    if (line == null && story.isNotEmpty) {
      line = story.last;
    }
    if (line != null) {
      caret.paragraphIndex = line.paragraphIndex;
      caret.logicalIndex = _hitOffsetOnLine(line, local);
    } else {
      caret.paragraphIndex = 0;
      caret.logicalIndex = 0;
    }
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
  }

  LaidOutLine? _nearestChromeLine(List<LaidOutLine> lines, Offset local) {
    LaidOutLine? best;
    var bestScore = double.infinity;
    for (final LaidOutLine line in lines) {
      final bool inY = local.dy >= line.y && local.dy <= line.y + line.height;
      final double lineW = line.width < 8 ? 8 : line.width;
      if (inY && local.dx >= line.x && local.dx <= line.x + lineW) {
        return line;
      }
      final double xDist = local.dx < line.x
          ? line.x - local.dx
          : (local.dx > line.x + lineW ? local.dx - (line.x + lineW) : 0);
      final double yDist = inY
          ? 0
          : (local.dy < line.y
                ? line.y - local.dy
                : local.dy - (line.y + line.height));
      final double score = yDist * 10000 + xDist;
      if (score < bestScore) {
        bestScore = score;
        best = line;
      }
    }
    return best;
  }

  /// notify API.
  void _placeCaret(Offset window, {required bool extend, bool notify = true}) {
    final (int page, Offset local) = _hitPage(window);
    _fitPageAt(page);
    if (page < 0 || page >= laidOut.pages.length) {
      return;
    }
    final LaidOutPage laidPage = laidOut.pages[page];
    if (extend) {
      final OfficeVisual? visual = _visualAt(laidPage, local)?.visual;
      if (visual != null) {
        onExtendThroughVisual?.call(visual);
        if (notify) {
          markNeedsPaint();
          onChanged?.call();
        }
        return;
      }
    }
    if (_editingHeaderFooter) {
      _placeChromeCaret(laidPage, local, extend: extend);
      if (notify) {
        markNeedsPaint();
        onChanged?.call();
      }
      return;
    }
    final LaidOutBox? cell = _cellAt(laidPage, local);
    final LaidOutLine? line = _lineAt(laidPage, local);
    if (line != null && line.paragraphIndex < 0) {
      return;
    }
    if (line != null) {
      caret.paragraphIndex = line.paragraphIndex;
      caret.logicalIndex = _hitOffsetOnLine(line, local);
    } else if (cell?.paragraphIndex != null) {
      caret.paragraphIndex = cell!.paragraphIndex!;
      caret.logicalIndex = 0;
    } else {
      caret.logicalIndex = 0;
    }
    if (!extend) {
      caret.collapseSelection();
    }
    caret.resetBlink();
    if (notify) {
      markNeedsPaint();
      onChanged?.call();
    }
  }

  LaidOutLine? _lineAt(LaidOutPage page, Offset local) {
    final LaidOutBox? cell = _cellAt(page, local);
    LaidOutLine? best;
    var bestScore = double.infinity;
    for (final LaidOutLine line in page.lines) {
      if (cell != null && !_lineInCell(line, cell)) {
        continue;
      }
      final bool inY = local.dy >= line.y && local.dy <= line.y + line.height;
      if (!inY && cell == null) {
        continue;
      }
      final double lineW = line.width < 8 ? 8 : line.width;
      if (inY && local.dx >= line.x && local.dx <= line.x + lineW) {
        return line;
      }
      final double xDist = local.dx < line.x
          ? line.x - local.dx
          : (local.dx > line.x + lineW ? local.dx - (line.x + lineW) : 0);
      final double yDist = inY
          ? 0
          : (local.dy < line.y
                ? line.y - local.dy
                : local.dy - (line.y + line.height));
      final double score = yDist * 10000 + xDist;
      if (score < bestScore) {
        bestScore = score;
        best = line;
      }
    }
    if (best != null) {
      return best;
    }
    if (cell != null) {
      return null;
    }
    return page.lines.isEmpty ? null : page.lines.last;
  }

  void _dragVisual(Offset delta) {
    final int? handle = _visualHandle;
    final OfficeVisual? visual = selectedVisual?.visual;
    if (handle == null || visual == null) {
      return;
    }
    final Offset pageDelta = Offset(
      delta.dx / _viewScale,
      delta.dy / _viewScale,
    );
    if (pictureCropMode && handle < 8) {
      _cropFromHandle(handle, pageDelta, visual);
      return;
    }
    if (handle == 9) {
      onPreviewVisualMove?.call(pageDelta.dx, pageDelta.dy);
      return;
    }
    if (handle == 8) {
      _rotateFromPointer(visual);
      return;
    }
    _resizeFromHandle(handle, pageDelta, visual);
  }

  void _rotateFromPointer(OfficeVisual visual) {
    final LaidOutBox? box = _selectedVisualBox();
    if (box == null) {
      return;
    }
    final Offset window = _hoverLocal ?? Offset.zero;
    final (int page, Offset local) = _hitPage(window);
    if (page < 0) {
      return;
    }
    final Offset center = Offset(box.x + box.width / 2, box.y + box.height / 2);
    final double deg =
        math.atan2(local.dx - center.dx, center.dy - local.dy) * 180 / math.pi;
    onPreviewVisualRotate?.call(deg);
  }

  bool _trySelectedVisualHandle(int page, Offset local) {
    if (!config.allowsMutation) {
      return false;
    }
    final LaidOutBox? selectedBox = _selectedVisualBoxOn(page);
    if (selectedBox == null) {
      return false;
    }
    final int? handle = TransformHandles(
      Rect.fromLTWH(
        selectedBox.x,
        selectedBox.y,
        selectedBox.width,
        selectedBox.height,
      ),
    ).hit(local, radius: 14, showRotate: !pictureCropMode);
    if (handle == null) {
      return false;
    }
    _visualHandle = handle;
    _draggingVisual = true;
    onBeginVisualTransform?.call();
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  void _resizeFromHandle(int handle, Offset d, OfficeVisual visual) {
    var width = visual.width;
    var height = visual.height;
    var shift = 0.0;
    switch (handle) {
      case 0:
        shift = d.dx;
        width -= d.dx;
        height -= d.dy;
      case 1:
        height -= d.dy;
      case 2:
        width += d.dx;
        height -= d.dy;
      case 3:
        width += d.dx;
      case 4:
        width += d.dx;
        height += d.dy;
      case 5:
        height += d.dy;
      case 6:
        shift = d.dx;
        width -= d.dx;
        height += d.dy;
      case 7:
        shift = d.dx;
        width -= d.dx;
    }
    onPreviewVisualResize?.call(width: width, height: height);
    if (shift != 0) {
      onPreviewVisualMove?.call(shift, 0);
    }
  }

  void _cropFromHandle(int handle, Offset d, OfficeVisual visual) {
    final LaidOutBox? box = _selectedVisualBox();
    if (box == null || box.width <= 1 || box.height <= 1) {
      return;
    }
    final double dl = d.dx / box.width;
    final double dt = d.dy / box.height;
    var left = visual.picture.cropLeft;
    var top = visual.picture.cropTop;
    var right = visual.picture.cropRight;
    var bottom = visual.picture.cropBottom;
    switch (handle) {
      case 0:
        left += dl;
        top += dt;
      case 1:
        top += dt;
      case 2:
        right -= dl;
        top += dt;
      case 3:
        right -= dl;
      case 4:
        right -= dl;
        bottom -= dt;
      case 5:
        bottom -= dt;
      case 6:
        left += dl;
        bottom -= dt;
      case 7:
        left += dl;
    }
    onPreviewVisualCrop?.call(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  LaidOutBox? _selectedVisualBox() {
    final WmlVisual? selected = selectedVisual;
    if (selected == null) {
      return null;
    }
    for (final LaidOutPage page in laidOut.pages) {
      for (final LaidOutBox box in page.frames) {
        if (box.visual != null && identical(box.visual, selected.visual)) {
          return box;
        }
      }
    }
    return null;
  }

  bool _selectEquationAt(Offset window) {
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return false;
    }
    final LaidOutBox? equationBox = _equationAt(laidOut.pages[page], local);
    final WmlEquation? equation = equationBox?.equation;
    if (equation == null) {
      return false;
    }
    final LaidOutOmml? omml = equationBox!.omml;
    final Offset inside = Offset(
      local.dx - equationBox.x,
      local.dy - equationBox.y,
    );
    final int? slot = omml == null
        ? null
        : PaintEquation.hitSlot(omml, inside, root: equation.math.root);
    final int? caret = omml == null || slot == null
        ? null
        : PaintEquation.hitCaret(
            omml,
            inside,
            slotIndex: slot,
            root: equation.math.root,
          );
    onSelectEquation?.call(equation, slot, caret);
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  LaidOutBox? _equationAt(LaidOutPage page, Offset local) {
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.equation || box.equation == null) {
        continue;
      }
      if (local.dx >= box.x - 4 &&
          local.dx <= box.x + box.width + 4 &&
          local.dy >= box.y - 4 &&
          local.dy <= box.y + box.height + 4) {
        return box;
      }
    }
    return null;
  }

  LaidOutBox? _frameAt(LaidOutPage page, Offset local) {
    LaidOutBox? best;
    var bestArea = double.infinity;
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.frame || box.frame == null) {
        continue;
      }
      if (_boxContains(box, local)) {
        final double area = box.width * box.height;
        if (area < bestArea) {
          bestArea = area;
          best = box;
        }
      }
    }
    return best;
  }

  LaidOutBox? _selectedFrameBoxOn(int page) {
    final WmlFrame? selected = selectedFrame;
    if (selected == null || page < 0 || page >= laidOut.pages.length) {
      return null;
    }
    for (final LaidOutBox box in laidOut.pages[page].frames) {
      if (box.frame != null && identical(box.frame, selected)) {
        return box;
      }
    }
    return null;
  }

  bool _trySelectedFrameHandle(int page, Offset local) {
    if (!config.allowsMutation || editingFrame) {
      return false;
    }
    final LaidOutBox? selectedBox = _selectedFrameBoxOn(page);
    if (selectedBox == null) {
      return false;
    }
    final int? handle = TransformHandles(
      Rect.fromLTWH(
        selectedBox.x,
        selectedBox.y,
        selectedBox.width,
        selectedBox.height,
      ),
    ).hit(local, radius: 14, showRotate: false);
    if (handle == null) {
      return false;
    }
    _frameHandle = handle;
    _draggingFrame = true;
    onBeginFrameTransform?.call();
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  void _dragFrame(Offset delta) {
    final int? handle = _frameHandle;
    final WmlFrame? frame = selectedFrame;
    if (handle == null || frame == null) {
      return;
    }
    final Offset pageDelta = Offset(
      delta.dx / _viewScale,
      delta.dy / _viewScale,
    );
    if (handle == 9 || handle == 8) {
      onPreviewFrameMove?.call(pageDelta.dx, pageDelta.dy);
      return;
    }
    var width = frame.width;
    var height = frame.height;
    var shiftX = 0.0;
    var shiftY = 0.0;
    switch (handle) {
      case 0:
        shiftX = pageDelta.dx;
        shiftY = pageDelta.dy;
        width -= pageDelta.dx;
        height -= pageDelta.dy;
      case 1:
        shiftY = pageDelta.dy;
        height -= pageDelta.dy;
      case 2:
        shiftY = pageDelta.dy;
        width += pageDelta.dx;
        height -= pageDelta.dy;
      case 3:
        width += pageDelta.dx;
      case 4:
        width += pageDelta.dx;
        height += pageDelta.dy;
      case 5:
        height += pageDelta.dy;
      case 6:
        shiftX = pageDelta.dx;
        width -= pageDelta.dx;
        height += pageDelta.dy;
      case 7:
        shiftX = pageDelta.dx;
        width -= pageDelta.dx;
    }
    onPreviewFrameResize?.call(width: width, height: height);
    if (shiftX != 0 || shiftY != 0) {
      onPreviewFrameMove?.call(shiftX, shiftY);
    }
  }

  LaidOutBox? _visualAt(LaidOutPage page, Offset local) {
    LaidOutBox? best;
    var bestArea = double.infinity;
    for (final LaidOutBox box in page.frames) {
      if (box.kind == LaidOutBoxKind.tableCell || box.visual == null) {
        continue;
      }
      if (local.dx >= box.x &&
          local.dx <= box.x + box.width &&
          local.dy >= box.y &&
          local.dy <= box.y + box.height) {
        final double area = box.width * box.height;
        if (area < bestArea) {
          bestArea = area;
          best = box;
        }
      }
    }
    return best;
  }

  void _handleContext(PointerDownEvent event) {
    final (int pageHint, Offset localHint) = _hitPage(event.localPosition);
    final _TableGeom? handle = pageHint >= 0 && pageHint < laidOut.pages.length
        ? _tableHandleAt(laidOut.pages[pageHint], localHint)
        : null;
    final ValueChanged<OfficeContextHit>? callback = onContextMenu;
    if (callback == null) {
      return;
    }
    final (int page, Offset local) = _hitPage(event.localPosition);
    if (page < 0 || page >= laidOut.pages.length) {
      callback(
        OfficeContextHit(
          kind: compact
              ? OfficeContextKind.comment
              : OfficeContextKind.document,
          globalPosition: event.position,
          commentId: selectedCommentId,
        ),
      );
      return;
    }
    final LaidOutPage laidPage = laidOut.pages[page];
    final LaidOutBox? visual = _visualAt(laidPage, local);
    final LaidOutBox? equation = _equationAt(laidPage, local);
    final LaidOutBox? cell = _cellAt(laidPage, local);
    final int? commentId = _commentIdAt(laidPage, local) ?? selectedCommentId;
    final WmlHyperlink? link = _linkAt(laidPage, local);
    final OfficeContextKind kind;
    if (handle != null) {
      kind = OfficeContextKind.tableHandle;
    } else if (visual != null) {
      kind = OfficeContextKind.picture;
    } else if (equation != null) {
      kind = OfficeContextKind.equation;
    } else if (cell != null) {
      kind = OfficeContextKind.table;
    } else if (commentId != null) {
      kind = OfficeContextKind.comment;
    } else if (link != null) {
      kind = OfficeContextKind.hyperlink;
    } else {
      kind = OfficeContextKind.document;
    }
    callback(
      OfficeContextHit(
        kind: kind,
        globalPosition: event.position,
        table: handle?.table ?? cell?.table,
        tableRow: cell?.tableRow,
        tableCol: cell?.tableCol,
        visual: visual?.visual,
        commentId: commentId,
        link: link,
        equation: equation?.equation,
      ),
    );
  }

  bool _tryInsertHandle(Offset window) {
    if (compact || !config.allowsMutation) {
      return false;
    }
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return false;
    }
    final _TableInsertHit? hit = _insertHitAt(laidOut.pages[page], local);
    if (hit == null) {
      return false;
    }
    if (hit.column) {
      onInsertTableColumnAt?.call(hit.table, hit.index);
    } else {
      onInsertTableRowAt?.call(hit.table, hit.index);
    }
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  _TableInsertHit? _insertHitAt(LaidOutPage page, Offset local) {
    if (compact || !config.allowsMutation) {
      return null;
    }
    for (final _TableGeom table in _tablesOn(page)) {
      final _TableInsertHit? hit = _nearestInsertHit(table, local);
      if (hit != null && hit.button.inflate(6).contains(local)) {
        return hit;
      }
    }
    return null;
  }

  _TableInsertHit? _insertHoverAt(LaidOutPage page, Offset local) {
    if (compact || !config.allowsMutation) {
      return null;
    }
    for (final _TableGeom table in _tablesOn(page)) {
      final _TableInsertHit? hit = _nearestInsertHit(table, local);
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  bool _tryTableBand(Offset window) {
    if (compact || !config.allowsSelection) {
      return false;
    }
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return false;
    }
    final _TableBandHit? hit = _tableBandAt(laidOut.pages[page], local);
    if (hit == null) {
      return false;
    }
    _tableBand = (
      table: hit.table,
      column: hit.column,
      anchor: hit.index,
      current: hit.index,
    );
    onSelectTableBand?.call(
      hit.table,
      column: hit.column,
      from: hit.index,
      to: hit.index,
    );
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  void _extendTableBand(Offset window) {
    final ({WmlTable table, bool column, int anchor, int current})? drag =
        _tableBand;
    if (drag == null) {
      return;
    }
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return;
    }
    for (final _TableGeom table in _tablesOn(laidOut.pages[page])) {
      if (!identical(table.table, drag.table)) {
        continue;
      }
      final int index = drag.column
          ? table.colIndexAt(local.dx, clamp: true)
          : table.rowIndexAt(local.dy, clamp: true);
      if (index < 0 || index == drag.current) {
        return;
      }
      _tableBand = (
        table: drag.table,
        column: drag.column,
        anchor: drag.anchor,
        current: index,
      );
      onSelectTableBand?.call(
        drag.table,
        column: drag.column,
        from: drag.anchor,
        to: index,
      );
      markNeedsPaint();
      onChanged?.call();
      return;
    }
  }

  _TableBandHit? _tableBandAt(LaidOutPage page, Offset local) {
    if (compact) {
      return null;
    }
    const double gutter = 22;
    const double insertSlop = 5;
    for (final _TableGeom table in _tablesOn(page)) {
      if (table.handleRect.inflate(4).contains(local)) {
        continue;
      }
      for (final _TableInsertHit hit in _tableInsertHitsFor(table)) {
        if (hit.button.inflate(3).contains(local)) {
          return null;
        }
      }
      if (local.dx >= table.bounds.left - gutter &&
          local.dx < table.bounds.left - 1 &&
          local.dy >= table.bounds.top &&
          local.dy <= table.bounds.bottom) {
        if (!_nearAxisBoundary(
          table,
          local.dy,
          column: false,
          slop: insertSlop,
        )) {
          final int row = table.rowIndexAt(local.dy);
          if (row >= 0) {
            return _TableBandHit(
              table: table.table,
              column: false,
              index: row,
              highlight: table.rowBand(row, row),
            );
          }
        }
      }
      if (local.dy >= table.bounds.top - gutter &&
          local.dy < table.bounds.top - 1 &&
          local.dx >= table.bounds.left &&
          local.dx <= table.bounds.right) {
        if (!_nearAxisBoundary(
          table,
          local.dx,
          column: true,
          slop: insertSlop,
        )) {
          final int col = table.colIndexAt(local.dx);
          if (col >= 0) {
            return _TableBandHit(
              table: table.table,
              column: true,
              index: col,
              highlight: table.colBand(col, col),
            );
          }
        }
      }
    }
    return null;
  }

  bool _nearAxisBoundary(
    _TableGeom table,
    double value, {
    required bool column,
    required double slop,
  }) {
    final int count = column ? table.colCount : table.rowCount;
    for (int i = 0; i <= count; i++) {
      final double edge = column ? table.colBoundary(i) : table.rowBoundary(i);
      if ((value - edge).abs() <= slop) {
        return true;
      }
    }
    return false;
  }

  _TableGeom? _tableHandleAt(LaidOutPage page, Offset local) {
    if (compact) {
      return null;
    }
    for (final _TableGeom table in _tablesOn(page)) {
      if (table.handleRect.inflate(8).contains(local)) {
        return table;
      }
    }
    return null;
  }

  bool _tryTableHandle(Offset window) {
    final (int page, Offset local) = _hitPage(window);
    if (page < 0 || page >= laidOut.pages.length) {
      return false;
    }
    final _TableGeom? handle = _tableHandleAt(laidOut.pages[page], local);
    if (handle == null) {
      return false;
    }
    onSelectTable?.call(handle.table);
    markNeedsPaint();
    onChanged?.call();
    return true;
  }

  _TableInsertHit? _nearestInsertHit(_TableGeom table, Offset local) {
    if (!table.bounds.inflate(28).contains(local)) {
      return null;
    }
    if (table.handleRect.inflate(2).contains(local)) {
      return null;
    }
    _TableInsertHit? best;
    var bestDist = 8.0;
    for (final _TableInsertHit hit in _tableInsertHitsFor(table)) {
      if (hit.button.inflate(4).contains(local)) {
        return hit;
      }
      final bool onAxis;
      final double dist;
      if (hit.column) {
        final bool inTopGutter =
            local.dy >= table.bounds.top - 26 &&
            local.dy <= table.bounds.top + 4;
        onAxis = inTopGutter && (local.dx - hit.axis).abs() <= 6;
        dist = (local.dx - hit.axis).abs();
      } else {
        final bool inLeftGutter =
            local.dx >= table.bounds.left - 26 &&
            local.dx <= table.bounds.left + 4;
        onAxis = inLeftGutter && (local.dy - hit.axis).abs() <= 6;
        dist = (local.dy - hit.axis).abs();
      }
      if (!onAxis) {
        continue;
      }
      if (dist < bestDist) {
        bestDist = dist;
        best = hit;
      }
    }
    return best;
  }

  List<_TableGeom> _tablesOn(LaidOutPage page) {
    final Map<WmlTable, _TableGeom> groups = <WmlTable, _TableGeom>{};
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.tableCell || box.table == null) {
        continue;
      }
      final WmlTable table = box.table!;
      final _TableGeom geom = groups.putIfAbsent(
        table,
        () => _TableGeom(table),
      );
      geom.add(box);
    }
    return groups.values.toList();
  }

  void _paintSelectedTables(Canvas canvas, LaidOutPage page) {
    if (selectedTable == null) {
      return;
    }
    for (final _TableGeom table in _tablesOn(page)) {
      if (!identical(selectedTable, table.table)) {
        continue;
      }
      canvas.drawRect(
        table.bounds,
        Paint()
          ..color = _theme.selectionStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      _paintTableHandle(canvas, table);
    }
  }

  void _paintTableBandChrome(Canvas canvas, LaidOutPage page) {
    final ({WmlTable table, bool column, int anchor, int current})? drag =
        _tableBand;
    if (drag != null) {
      for (final _TableGeom table in _tablesOn(page)) {
        if (!identical(table.table, drag.table)) {
          continue;
        }
        _paintTableBand(
          canvas,
          drag.column
              ? table.colBand(drag.anchor, drag.current)
              : table.rowBand(drag.anchor, drag.current),
          active: true,
        );
      }
      return;
    }
    if (!config.allowsSelection || compact) {
      return;
    }
    final Offset? hover = _hoverLocal;
    if (hover == null) {
      return;
    }
    final (int hoverPage, Offset local) = _hitPage(hover);
    if (hoverPage < 0 ||
        hoverPage >= laidOut.pages.length ||
        !identical(laidOut.pages[hoverPage], page)) {
      return;
    }
    final _TableBandHit? band = _tableBandAt(page, local);
    if (band != null) {
      _paintTableBand(canvas, band.highlight, active: false);
    }
  }

  void _paintTableInsertHandles(Canvas canvas, LaidOutPage page) {
    if (compact || !config.allowsMutation) {
      return;
    }
    final Offset? hover = _hoverLocal;
    Offset? local;
    if (hover != null) {
      final (int hoverPage, Offset pageLocal) = _hitPage(hover);
      if (hoverPage >= 0 &&
          hoverPage < laidOut.pages.length &&
          identical(laidOut.pages[hoverPage], page)) {
        local = pageLocal;
      }
    }
    if (local == null) {
      return;
    }
    for (final _TableGeom table in _tablesOn(page)) {
      if (!table.bounds.inflate(32).contains(local)) {
        continue;
      }
      if (selectedTable == null || !identical(selectedTable, table.table)) {
        _paintTableHandle(canvas, table);
      }
      final _TableInsertHit? hot = _nearestInsertHit(table, local);
      if (hot == null) {
        continue;
      }
      _paintInsertGuide(canvas, hot);
      _paintPlusButton(canvas, hot.button, active: true);
    }
  }

  void _paintInsertGuide(Canvas canvas, _TableInsertHit hot) {
    canvas.drawLine(
      hot.lineStart,
      hot.lineEnd,
      Paint()
        ..color = const Color(0x662E75B6)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      hot.lineStart,
      hot.lineEnd,
      Paint()
        ..color = const Color(0xFF2E75B6)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintTableBand(Canvas canvas, Rect highlight, {required bool active}) {
    canvas.drawRect(
      highlight,
      Paint()
        ..color = active ? const Color(0x552E75B6) : const Color(0x332E75B6),
    );
  }

  void _paintTableHandle(Canvas canvas, _TableGeom table) {
    final Rect handle = table.handleRect;
    final bool selected =
        selectedTable != null && identical(selectedTable, table.table);
    canvas.drawRRect(
      RRect.fromRectAndRadius(handle, const Radius.circular(2)),
      Paint()
        ..color = selected ? const Color(0xFF2E75B6) : const Color(0xFFFFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handle, const Radius.circular(2)),
      Paint()
        ..color = const Color(0xFF2E75B6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final Paint dots = Paint()
      ..color = selected ? const Color(0xFFFFFFFF) : const Color(0xFF2E75B6);
    for (int r = 0; r < 2; r++) {
      for (int c = 0; c < 2; c++) {
        canvas.drawCircle(
          Offset(handle.left + 3.5 + c * 5, handle.top + 3.5 + r * 5),
          1.05,
          dots,
        );
      }
    }
  }

  List<_TableInsertHit> _tableInsertHitsFor(_TableGeom table) {
    final List<_TableInsertHit> hits = <_TableInsertHit>[];
    for (int i = 0; i <= table.rowCount; i++) {
      final double y = table.rowBoundary(i);
      hits.add(
        _TableInsertHit(
          table: table.table,
          column: false,
          index: i,
          button: Rect.fromCircle(
            center: Offset(table.bounds.left - 12, y),
            radius: 7,
          ),
          lineStart: Offset(table.bounds.left - 12, y),
          lineEnd: Offset(table.bounds.right, y),
        ),
      );
    }
    for (int i = 0; i <= table.colCount; i++) {
      final double x = table.colBoundary(i);
      hits.add(
        _TableInsertHit(
          table: table.table,
          column: true,
          index: i,
          button: Rect.fromCircle(
            center: Offset(x, table.bounds.top - 12),
            radius: 7,
          ),
          lineStart: Offset(x, table.bounds.top - 12),
          lineEnd: Offset(x, table.bounds.bottom),
        ),
      );
    }
    return hits;
  }

  void _paintPlusButton(Canvas canvas, Rect button, {required bool active}) {
    canvas.drawCircle(
      button.center,
      button.width / 2,
      Paint()
        ..color = active ? const Color(0xFF2E75B6) : const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      button.center,
      button.width / 2,
      Paint()
        ..color = const Color(0xFF2E75B6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final Paint plus = Paint()
      ..color = active ? const Color(0xFFFFFFFF) : const Color(0xFF2E75B6)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(button.center.dx - 3.2, button.center.dy),
      Offset(button.center.dx + 3.2, button.center.dy),
      plus,
    );
    canvas.drawLine(
      Offset(button.center.dx, button.center.dy - 3.2),
      Offset(button.center.dx, button.center.dy + 3.2),
      plus,
    );
  }

  LaidOutBox? _cellAt(LaidOutPage page, Offset local) {
    LaidOutBox? best;
    var bestArea = double.infinity;
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.tableCell) {
        continue;
      }
      if (local.dx >= box.x &&
          local.dx <= box.x + box.width &&
          local.dy >= box.y &&
          local.dy <= box.y + box.height) {
        final double area = box.width * box.height;
        if (area < bestArea) {
          bestArea = area;
          best = box;
        }
      }
    }
    return best;
  }

  bool _lineInCell(LaidOutLine line, LaidOutBox cell) {
    if (cell.paragraphIndex != null) {
      final int start = cell.paragraphIndex!;
      final int end = cell.paragraphEnd ?? start;
      return line.paragraphIndex >= start && line.paragraphIndex <= end;
    }
    return line.x >= cell.x - 1 && line.x <= cell.x + cell.width;
  }

  LaidOutBox? _cellForLine(LaidOutPage page, LaidOutLine line) {
    LaidOutBox? best;
    var bestArea = double.infinity;
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.tableCell || !_lineInCell(line, box)) {
        continue;
      }
      final double area = box.width * box.height;
      if (area < bestArea) {
        bestArea = area;
        best = box;
      }
    }
    return best;
  }

  int _hitOffsetOnLine(LaidOutLine line, Offset local) {
    if (line.glyphs.isEmpty) {
      final String text = line.overlayText ?? '';
      if (text.isEmpty || line.width <= 0) {
        return 0;
      }
      final bool rtl = CaretEngine.resolveRtl(
        paragraphRtl: _paragraphRtl(line.paragraphIndex),
        nearbyText: text,
      );
      final double t = ((local.dx - line.x) / line.width).clamp(0.0, 1.0);
      final double visual = rtl ? 1 - t : t;
      return (visual * text.length).round();
    }
    return PaintRunText.hitLogicalIndexOnLine(
      line,
      local.dx,
      paragraph: line.sourceText ?? _paragraphTextAt(line.paragraphIndex),
      themeFamily: _theme.fontFamily,
    );
  }

  void _resetPaintFit() {
    if (identical(_fittedLayout, laidOut)) {
      return;
    }
    _fittedLayout = laidOut;
    _fittedPages.clear();
  }

  void _fitPageAt(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= laidOut.pages.length) {
      return;
    }
    _fitPage(laidOut.pages[pageIndex]);
  }

  void _fitPage(LaidOutPage page) {
    _resetPaintFit();
    if (!_fittedPages.add(page)) {
      return;
    }
    void fit(LaidOutLine line) {
      PaintRunText.fitLine(
        line,
        _paragraphTextAt(line.paragraphIndex),
        themeFamily: _theme.fontFamily,
      );
    }

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

  @override
  /// describeSemanticsConfiguration API.
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = semanticsLabel
      ..value = semanticsValue
      ..isReadOnly = !this.config.allowsMutation
      ..isTextField = this.config.allowsMutation && selectedVisual == null
      ..textDirection = this.config.textDirection;
  }

  @override
  /// paint API.
  void paint(PaintingContext context, Offset offset) {
    _resetPaintFit();
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = compact ? _theme.pageBackground : _theme.canvasBackground,
    );
    if (compact) {
      if (laidOut.pages.isNotEmpty) {
        _fitPage(laidOut.pages.first);
        _paintFrames(canvas, laidOut.pages.first);
        for (final LaidOutLine line in laidOut.pages.first.lines) {
          if (_paintsLineSelection(line, laidOut.pages.first)) {
            _paintLineSelection(canvas, line);
          }
          _drawLine(
            canvas,
            line,
            pageWidth: laidOut.pages.first.width,
            marginRight: _marginRightOf(laidOut.pages.first),
          );
          if (config.showsCaret &&
              hasFocus &&
              caret.visible &&
              line.paragraphIndex >= 0 &&
              caret.isOnLine(
                line,
                lastOfParagraph: _isLastParagraphLine(
                  laidOut.pages.first,
                  line,
                ),
              )) {
            _paintCaret(canvas, line);
          }
        }
      }
      if (hasFocus) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..color = _theme.focusRing
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
      return;
    }

    final double scale = _viewScale;
    final double pageLeft = _pageLeftPx();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-viewport.origin.dx, -viewport.origin.dy);

    var stackTop = 24.0;
    for (int i = 0; i < laidOut.pages.length; i++) {
      final LaidOutPage page = laidOut.pages[i];
      final double top = stackTop;
      stackTop += page.height * scale + 24;
      final Rect pageRect = Rect.fromLTWH(
        pageLeft,
        top,
        page.width * scale,
        page.height * scale,
      );
      if (!viewport.intersects(pageRect)) {
        continue;
      }
      _fitPage(page);
      canvas.drawShadow(
        Path()..addRect(pageRect.inflate(1)),
        const Color(0x66000000),
        8,
        false,
      );
      canvas.drawRect(pageRect, Paint()..color = _theme.pageBackground);
      canvas.drawRect(
        pageRect,
        Paint()
          ..color = _theme.pageBorder
          ..style = PaintingStyle.stroke,
      );

      canvas.save();
      canvas.translate(pageLeft, top);
      canvas.scale(scale);
      canvas.clipRect(Rect.fromLTWH(0, 0, page.width, page.height));
      _paintWatermark(canvas, page);
      _paintFrames(canvas, page, paintHandles: false);
      _paintSelectedTables(canvas, page);
      _paintTableBandChrome(canvas, page);
      for (final LaidOutLine line in page.header) {
        _drawOverlay(
          canvas,
          line,
          pageWidth: page.width,
          marginRight: _marginRightOf(page),
        );
      }
      if (_editingHeaderFooter) {
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            page.headerBand.height,
            page.width,
            page.height - page.headerBand.height - page.footerBand.height,
          ),
          Paint()..color = const Color(0x55F3F3F3),
        );
      }
      for (final LaidOutLine line in page.lines) {
        final LaidOutBox? cell = _cellForLine(page, line);
        if (cell != null) {
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(cell.x, cell.y, cell.width, cell.height),
          );
        }
        if (!_editingHeaderFooter && _paintsLineSelection(line, page)) {
          _paintLineSelection(canvas, line);
        }
        _paintRevisionMarkup(canvas, line);
        _drawLine(
          canvas,
          line,
          pageWidth: page.width,
          marginRight: _marginRightOf(page),
        );
        if (!_editingHeaderFooter &&
            config.showsCaret &&
            hasFocus &&
            caret.visible &&
            line.paragraphIndex >= 0 &&
            caret.isOnLine(
              line,
              lastOfParagraph: _isLastParagraphLine(page, line),
            )) {
          _paintCaret(canvas, line);
        }
        if (cell != null) {
          canvas.restore();
        }
      }
      for (final LaidOutLine line in page.footer) {
        _drawOverlay(
          canvas,
          line,
          pageWidth: page.width,
          marginRight: _marginRightOf(page),
        );
      }
      for (final LaidOutLine line in page.notes) {
        _drawOverlay(
          canvas,
          line,
          pageWidth: page.width,
          marginRight: _marginRightOf(page),
        );
      }
      if (_editingHeaderFooter) {
        _paintHeaderFooterChrome(canvas, page);
      }
      canvas.restore();
      canvas.save();
      canvas.translate(pageLeft, top);
      canvas.scale(scale);
      _paintTableInsertHandles(canvas, page);
      _paintVisualHandles(canvas, page);
      canvas.restore();
    }
    canvas.restore();

    _paintScrollBar(canvas);
    _paintLinkHint(canvas);
    if (config.showRulers) {
      final _RulerView ruler = _rulerView();
      WordRuler.paint(
        canvas,
        size,
        pageLeft: ruler.pageLeft,
        pageTop: ruler.pageTop,
        scale: ruler.scale,
        pageWidth: ruler.pageWidth,
        pageHeight: ruler.pageHeight,
        margins: ruler.margins,
        indent: ruler.indent,
        tabs: ruler.tabs,
        rtl: ruler.rtl,
        theme: _theme,
        hover: _rulerHover,
        active: _rulerDrag,
        readout: _rulerReadout,
        contentLeft: ruler.contentLeft,
        contentRight: ruler.contentRight,
      );
    }
    if (hasFocus) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = _theme.focusRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.restore();
  }

  bool _cellSelected(LaidOutBox box) {
    if (selectedTable != null &&
        box.table != null &&
        identical(selectedTable, box.table)) {
      return true;
    }
    final ({WmlTable table, bool column, int from, int to})? band =
        selectedTableBand;
    if (band != null && box.table != null && identical(band.table, box.table)) {
      return _boxInTableBand(box, band);
    }
    final int? start = box.paragraphIndex;
    if (start == null) {
      return false;
    }
    final int end = box.paragraphEnd ?? start;
    for (int p = start; p <= end; p++) {
      if (caret.coversParagraph(p)) {
        return true;
      }
    }
    return false;
  }

  bool _boxInTableBand(
    LaidOutBox box,
    ({WmlTable table, bool column, int from, int to}) band,
  ) {
    final int a = band.from < band.to ? band.from : band.to;
    final int b = band.from > band.to ? band.from : band.to;
    if (band.column) {
      final int col = box.tableGridCol ?? box.tableCol ?? 0;
      final int span = _cellGridSpan(box);
      return col <= b && col + span - 1 >= a;
    }
    final int row = box.tableRow ?? 0;
    return row >= a && row <= b;
  }

  int _cellGridSpan(LaidOutBox box) {
    final WmlTable? table = box.table;
    final int? rowIndex = box.tableRow;
    if (table == null || rowIndex == null || rowIndex >= table.rows.length) {
      return 1;
    }
    final int start = box.tableGridCol ?? box.tableCol ?? 0;
    var grid = 0;
    for (final WmlTableCell cell in table.rows[rowIndex].cells) {
      final int span = WordTable.spanOf(cell);
      if (grid == start) {
        return span;
      }
      grid += span;
    }
    return 1;
  }

  void _paintFindHits(Canvas canvas, LaidOutLine line) {
    if (findHits.isEmpty) {
      return;
    }
    for (int i = 0; i < findHits.length; i++) {
      final OfficeFindHit hit = findHits[i];
      if (hit.paragraphIndex != line.paragraphIndex) {
        continue;
      }
      final Color fill = i == activeFindIndex
          ? const Color(0x99F4B183)
          : const Color(0x66FFE699);
      for (final Rect r in CaretEngine.rangeRectsOnLine(
        line,
        line.y,
        line.height,
        hit.start,
        hit.end,
      )) {
        canvas.drawRect(r, Paint()..color = fill);
      }
    }
  }

  void _paintLineSelection(Canvas canvas, LaidOutLine line) {
    _paintFindHits(canvas, line);
    for (final Rect r in caret.selectionRectsOnLine(
      line,
      line.y,
      line.height,
      paragraph: line.paragraphIndex,
    )) {
      final Rect box = r.inflate(0.6);
      // Selection must be visible regardless of the text colour. The old
      // code inverted the ink colour, which made black-on-white selections
      // pure white and therefore invisible.
      canvas.drawRect(box, Paint()..color = _theme.selectionFill);
      canvas.drawRect(
        box,
        Paint()
          ..color = _theme.selectionStroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
  }

  bool _paintsLineSelection(LaidOutLine line, LaidOutPage page) {
    if (!config.allowsSelection || line.paragraphIndex < 0) {
      return false;
    }
    if (!caret.coversParagraph(line.paragraphIndex)) {
      return false;
    }
    final ({WmlTable table, bool column, int from, int to})? band =
        selectedTableBand;
    if (band == null) {
      return true;
    }
    for (final LaidOutBox box in page.frames) {
      if (box.kind != LaidOutBoxKind.tableCell || box.table == null) {
        continue;
      }
      if (!identical(box.table, band.table)) {
        continue;
      }
      final int start = box.paragraphIndex ?? -1;
      final int end = box.paragraphEnd ?? start;
      if (line.paragraphIndex >= start && line.paragraphIndex <= end) {
        return false;
      }
    }
    return true;
  }

  bool get _ctrlFollow =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  String _commentHint(WmlComment comment) {
    final String body = comment.text.trim();
    final String preview = body.isEmpty
        ? comment.author
        : '${comment.author}: ${body.split('\n').first}';
    if (comment.resolved) {
      return '$preview  ✓';
    }
    return preview;
  }

  int? _commentIdAt(LaidOutPage page, Offset local) {
    for (final LaidOutLine line in <LaidOutLine>[
      ...page.header,
      ...page.lines,
      ...page.footer,
    ]) {
      if (local.dy < line.y - 2 || local.dy > line.y + line.height + 2) {
        continue;
      }
      for (final LaidOutGlyph glyph in line.glyphs) {
        if (glyph.commentIds.isEmpty) {
          continue;
        }
        if (local.dx >= glyph.x - 2 &&
            local.dx <= glyph.x + glyph.advance + 2) {
          return glyph.commentIds.last;
        }
      }
    }
    return null;
  }

  WmlHyperlink? _linkAt(LaidOutPage page, Offset local) {
    final int? toc = _tocTargetAt(page, local);
    if (toc != null) {
      final List<WmlParagraph> paras = document.paragraphs.toList();
      if (toc >= 0 && toc < paras.length) {
        final WmlParagraph para = paras[toc];
        return WmlHyperlink(
          anchor: para.properties.bookmarkName ?? para.text.trim(),
        );
      }
    }
    for (final LaidOutLine line in <LaidOutLine>[
      ...page.header,
      ...page.lines,
      ...page.footer,
    ]) {
      if (line.hyperlink != null &&
          local.dy >= line.y - 2 &&
          local.dy <= line.y + line.height + 2 &&
          local.dx >= line.x - 4 &&
          local.dx <= line.x + line.width + 4) {
        return line.hyperlink;
      }
      if (local.dy < line.y - 2 || local.dy > line.y + line.height + 2) {
        continue;
      }
      for (final LaidOutGlyph glyph in line.glyphs) {
        if (glyph.hyperlink == null) {
          continue;
        }
        if (local.dx >= glyph.x && local.dx <= glyph.x + glyph.advance) {
          return glyph.hyperlink;
        }
      }
    }
    return null;
  }

  void _paintLinkHint(Canvas canvas) {
    final Offset? hover = _hoverLocal;
    if (hover == null) {
      return;
    }
    final (int page, Offset local) = _hitPage(hover);
    if (page < 0 || page >= laidOut.pages.length) {
      return;
    }
    final int? commentId = _commentIdAt(laidOut.pages[page], local);
    final WmlComment? comment = commentId == null
        ? null
        : WordComment.byId(document, commentId);
    final WmlHyperlink? link = _linkAt(laidOut.pages[page], local);
    if (comment == null && link == null) {
      return;
    }
    final String hint = comment != null
        ? _commentHint(comment)
        : (_ctrlFollow
              ? link!.displayTarget
              : '${config.strings.followLinkHint}\n${link!.displayTarget}');
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: hint,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF222222),
          height: 1.25,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);
    final double x = (hover.dx + 16).clamp(8, size.width - painter.width - 8);
    final double y = (hover.dy + 18).clamp(8, size.height - painter.height - 8);
    final Rect box = Rect.fromLTWH(
      x - 6,
      y - 4,
      painter.width + 12,
      painter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()..color = const Color(0xFFF7F7F7),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFFB0B0B0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    painter.paint(canvas, Offset(x, y));
  }

  int? _tocTargetAt(LaidOutPage page, Offset local) {
    for (final LaidOutBox box in page.frames.reversed) {
      if (box.kind != LaidOutBoxKind.tocEntry || box.paragraphIndex == null) {
        continue;
      }
      if (_boxContains(box, local, pad: 3)) {
        return box.paragraphIndex;
      }
    }
    return null;
  }

  void _paintVisualHandles(Canvas canvas, LaidOutPage page) {
    for (final LaidOutBox box in page.frames) {
      if (box.kind == LaidOutBoxKind.frame &&
          box.frame != null &&
          identical(box.frame, selectedFrame)) {
        TransformHandles(
          Rect.fromLTWH(box.x, box.y, box.width, box.height),
        ).paint(
          canvas,
          strokeColor: _theme.focusRing,
          fillColor: _theme.pageBackground,
          showKnobs: !editingFrame,
          showRotate: false,
          knobSize: 9,
        );
        continue;
      }
      final OfficeVisual? visual = box.visual;
      if (visual == null || box.kind == LaidOutBoxKind.tableCell) {
        continue;
      }
      final bool selected =
          selectedVisual != null && identical(visual, selectedVisual!.visual);
      final bool inRange =
          selected || (isVisualInSelection?.call(visual) ?? false);
      if (!inRange) {
        continue;
      }
      TransformHandles(
        Rect.fromLTWH(box.x, box.y, box.width, box.height),
      ).paint(
        canvas,
        strokeColor: pictureCropMode
            ? const Color(0xFFFF8C1A)
            : _theme.focusRing,
        fillColor: _theme.pageBackground,
        showKnobs: true,
        showRotate: !pictureCropMode,
        cropMode: pictureCropMode && visual.isPicture,
        knobSize: 9,
      );
    }
  }

  void _paintRevisionMarkup(Canvas canvas, LaidOutLine line) {
    if (document.revisions.isEmpty || line.glyphs.isEmpty) {
      return;
    }
    for (final WmlRevision revision in document.revisions) {
      if (revision.paragraphIndex != line.paragraphIndex) {
        continue;
      }
      for (final LaidOutGlyph glyph in line.glyphs) {
        final int at = glyph.glyph.logicalIndex;
        if (at < revision.start || at >= revision.end) {
          continue;
        }
        final double x = glyph.x;
        final double w = glyph.advance;
        canvas.drawRect(
          Rect.fromLTWH(x, line.y, w, line.height),
          Paint()
            ..color = revision.kind == WmlRevisionKind.insert
                ? const Color(0x3327AE60)
                : const Color(0x33C0392B),
        );
        if (revision.kind == WmlRevisionKind.insert) {
          canvas.drawLine(
            Offset(x, line.y + line.height - 1),
            Offset(x + w, line.y + line.height - 1),
            Paint()
              ..color = const Color(0xFF1B7A3A)
              ..strokeWidth = 1.6,
          );
        } else {
          canvas.drawLine(
            Offset(x, line.y + line.height * 0.55),
            Offset(x + w, line.y + line.height * 0.55),
            Paint()
              ..color = const Color(0xFFC0392B)
              ..strokeWidth = 1.6,
          );
        }
      }
    }
  }

  void _paintWatermark(Canvas canvas, LaidOutPage page) {
    final String text = document.watermark.trim();
    if (text.isEmpty) {
      return;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0x33888888),
          fontSize: (page.width * 0.12).clamp(22.0, 64.0),
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: PaintRunText.looksRtl(text)
          ? TextDirection.rtl
          : TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(page.width / 2, page.height / 2);
    canvas.rotate(-0.6);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  void _paintFrames(
    Canvas canvas,
    LaidOutPage page, {
    bool paintHandles = true,
  }) {
    for (final LaidOutBox box in page.frames) {
      if (box.kind == LaidOutBoxKind.tocEntry) {
        continue;
      }
      if (box.kind == LaidOutBoxKind.paragraphShade) {
        final Rect shade = Rect.fromLTWH(box.x, box.y, box.width, box.height);
        if (box.fillColor != null && box.fillColor!.isNotEmpty) {
          canvas.drawRect(
            shade,
            Paint()..color = _colorFromHex(box.fillColor!),
          );
        }
        if (box.strokeColor.isNotEmpty) {
          canvas.drawRect(
            shade,
            Paint()
              ..color = _colorFromHex(box.strokeColor)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
        }
        continue;
      }
      if (box.kind == LaidOutBoxKind.lineNumber) {
        final TextPainter painter = TextPainter(
          text: TextSpan(
            text: '${box.paragraphIndex ?? ''}',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 8),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(box.x, box.y));
        continue;
      }
      if (box.kind == LaidOutBoxKind.footnote) {
        canvas.drawRect(
          Rect.fromLTWH(box.x, box.y, box.width, 0.7),
          Paint()..color = const Color(0xFF888888),
        );
        continue;
      }
      final Rect rect = Rect.fromLTWH(box.x, box.y, box.width, box.height);
      if (box.kind == LaidOutBoxKind.frame ||
          box.kind == LaidOutBoxKind.columnSep) {
        if (box.fillColor != null && box.fillColor!.isNotEmpty) {
          canvas.drawRect(rect, Paint()..color = _colorFromHex(box.fillColor!));
        }
        final bool frameSelected =
            box.frame != null && identical(box.frame, selectedFrame);
        if (box.strokeColor.isNotEmpty && box.strokeColor != '00000000') {
          canvas.drawRect(
            rect,
            Paint()
              ..color = frameSelected
                  ? _theme.focusRing
                  : _colorFromHex(box.strokeColor)
              ..style = PaintingStyle.stroke
              ..strokeWidth = frameSelected
                  ? 1.8
                  : (box.kind == LaidOutBoxKind.columnSep ? 0.7 : 0.8),
          );
        }
        if (frameSelected && paintHandles && !editingFrame) {
          TransformHandles(rect).paint(
            canvas,
            strokeColor: _theme.focusRing,
            fillColor: _theme.pageBackground,
            showKnobs: true,
            showRotate: false,
            knobSize: 9,
          );
        }
        continue;
      }
      if (box.kind == LaidOutBoxKind.equation && box.omml != null) {
        final bool selected =
            selectedEquation != null &&
            identical(box.equation, selectedEquation);
        PaintEquation.paint(
          canvas,
          rect,
          box.omml!,
          focusedSlot: selected ? equationSlot : null,
          selected: selected,
          caretVisible: selected && hasFocus && caret.visible,
          caretIndex: equationCaret,
          root: box.equation?.math.root,
        );
        continue;
      }
      final OfficeVisual? visual = box.visual;
      if (visual != null && box.kind != LaidOutBoxKind.tableCell) {
        PaintOfficeVisual.paint(
          canvas,
          rect,
          visual,
          fontFamily: _theme.fontFamily ?? PaintRunText.fontFallbacks.first,
          images: _images,
          onImageReady: markNeedsPaint,
          cropPreview:
              pictureCropMode &&
              visual.isPicture &&
              selectedVisual != null &&
              identical(visual, selectedVisual!.visual),
        );
        if (paintHandles) {
          final bool selected =
              selectedVisual != null &&
              identical(visual, selectedVisual!.visual);
          final bool inRange =
              selected || (isVisualInSelection?.call(visual) ?? false);
          if (inRange) {
            TransformHandles(rect).paint(
              canvas,
              strokeColor: pictureCropMode
                  ? const Color(0xFFFF8C1A)
                  : _theme.focusRing,
              fillColor: _theme.pageBackground,
              showKnobs: true,
              showRotate: !pictureCropMode,
              cropMode: pictureCropMode && visual.isPicture,
              knobSize: 9,
            );
          }
        }
        continue;
      }
      if (box.height <= 0.5) {
        continue;
      }
      if (box.fillColor != null) {
        canvas.drawRect(rect, Paint()..color = _colorFromHex(box.fillColor!));
      }
      if (config.allowsSelection && _cellSelected(box)) {
        canvas.drawRect(rect, Paint()..color = _theme.selectionFill);
      }
      canvas.drawRect(
        rect,
        Paint()
          ..color = _colorFromHex(box.strokeColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }
  }

  void _paintHeaderFooterChrome(Canvas canvas, LaidOutPage page) {
    final LaidOutBand band = editingFooter ? page.footerBand : page.headerBand;
    final Rect rect = Rect.fromLTWH(
      band.left,
      band.top,
      band.width,
      math.max(band.height, 28),
    );
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF7F9FC));
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF2E75B6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final Path dash = Path();
    const double step = 5;
    for (double x = rect.left; x < rect.right; x += step * 2) {
      dash
        ..moveTo(x, rect.top)
        ..lineTo(math.min(x + step, rect.right), rect.top)
        ..moveTo(x, rect.bottom)
        ..lineTo(math.min(x + step, rect.right), rect.bottom);
    }
    canvas.drawPath(
      dash,
      Paint()
        ..color = const Color(0xFF2E75B6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final List<LaidOutLine> story = editingFooter ? page.footer : page.header;
    for (final LaidOutLine line in story) {
      if (config.showsCaret &&
          hasFocus &&
          caret.visible &&
          caret.isOnLine(line, lastOfParagraph: identical(line, story.last))) {
        _paintCaret(canvas, line);
      }
    }
    final TextPainter label = TextPainter(
      text: TextSpan(
        text: editingFooter ? 'Footer' : 'Header',
        style: const TextStyle(
          fontSize: 9,
          color: Color(0xFF2E75B6),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(band.left + 8, band.top + 4));
  }

  double _marginRightOf(LaidOutPage page) {
    if (page.sectionIndex < 0 ||
        page.sectionIndex >= document.sections.length) {
      return 72;
    }
    return document.sections[page.sectionIndex].margins.right;
  }

  void _drawOverlay(
    Canvas canvas,
    LaidOutLine line, {
    double? pageWidth,
    double? marginRight,
  }) {
    final String? text = line.overlayText;
    if (text == null || text.isEmpty) {
      return;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: line.overlaySize,
          fontWeight: line.overlayBold ? FontWeight.w700 : FontWeight.w400,
          fontFamily: PaintRunText.familyFor(
            text: text,
            themeFamily: _theme.fontFamily,
          ),
          fontFamilyFallback: PaintRunText.fallbacksFor(text),
          color: line.hyperlink != null
              ? const Color(0xFF0563C1)
              : _colorFromHex(
                  line.overlayColor == null || line.overlayColor!.isEmpty
                      ? '444444'
                      : line.overlayColor!,
                ),
          decoration: line.hyperlink != null
              ? TextDecoration.underline
              : TextDecoration.none,
          height: 1.0,
        ),
      ),
      textDirection: PaintRunText.directionFor(bidiLevel: 0, text: text),
      maxLines: 1,
    )..layout();
    var x = line.x;
    if (line.tocLeader) {
      x = WordToc.pageNumberX(
        pageWidth: pageWidth ?? laidOut.pageSize.width,
        marginRight: marginRight ?? 72,
        numberWidth: painter.width,
      );
    } else if (line.justification == WmlJustification.right) {
      final double rightEdge = line.width > 1
          ? line.x + line.width
          : (pageWidth ?? laidOut.pageSize.width);
      x = rightEdge - painter.width;
    } else if (line.justification == WmlJustification.center) {
      x = line.x + (line.width - painter.width) / 2;
    }
    painter.paint(canvas, Offset(x, line.y));
  }

  void _drawLine(
    Canvas canvas,
    LaidOutLine line, {
    double? pageWidth,
    double? marginRight,
  }) {
    if (line.isParagraphStart &&
        line.listLabel != null &&
        line.listLabel!.isNotEmpty) {
      final TextPainter marker = TextPainter(
        text: TextSpan(
          text: line.listLabel,
          style: TextStyle(
            fontSize: line.glyphs.isEmpty ? 11 : line.glyphs.first.fontSize,
            fontFamily: PaintRunText.latinFallbacks.first,
            fontFamilyFallback: PaintRunText.latinFallbacks,
            color: const Color(0xFF222222),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      marker.paint(canvas, Offset(line.x - marker.width - 4, line.y));
    }
    if (line.glyphs.isEmpty) {
      _drawOverlay(
        canvas,
        line,
        pageWidth: pageWidth,
        marginRight: marginRight,
      );
      return;
    }
    final String paragraph =
        line.sourceText ?? _paragraphTextAt(line.paragraphIndex);
    var start = 0;
    while (start < line.glyphs.length) {
      final LaidOutGlyph first = line.glyphs[start];
      var end = start + 1;
      while (end < line.glyphs.length &&
          PaintRunText.samePaintRun(first, line.glyphs[end])) {
        end++;
      }
      final List<LaidOutGlyph> run = line.glyphs.sublist(start, end);
      if (first.commentIds.isNotEmpty) {
        final double x0 = first.x;
        final double x1 = run.last.x + run.last.advance;
        final bool active =
            selectedCommentId != null &&
            first.commentIds.contains(selectedCommentId);
        canvas.drawRect(
          Rect.fromLTWH(x0, line.y, x1 - x0, line.height),
          Paint()
            ..color = Color(
              active ? 0xFFF4B183 : 0xFFFFF2CC,
            ).withValues(alpha: 0.88),
        );
      }
      if (first.highlight != null) {
        final double x0 = first.x;
        final double x1 = run.last.x + run.last.advance;
        canvas.drawRect(
          Rect.fromLTWH(x0, line.y, x1 - x0, line.height),
          Paint()
            ..color = _colorFromHex(first.highlight!).withValues(alpha: 0.45),
        );
      }
      final bool splitWords =
          (line.justification == WmlJustification.justify ||
              line.justification == WmlJustification.distributed) &&
          line.justificationRatio != 0;
      if (splitWords) {
        var i = start;
        while (i < end) {
          if (line.glyphs[i].glyph.isSpace) {
            i++;
            continue;
          }
          var j = i + 1;
          while (j < end && !line.glyphs[j].glyph.isSpace) {
            j++;
          }
          _paintTextRun(canvas, line, paragraph, line.glyphs.sublist(i, j));
          i = j;
        }
      } else {
        _paintTextRun(canvas, line, paragraph, run);
      }
      start = end;
    }
    if (line.overlayText != null && line.overlayText!.isNotEmpty) {
      _drawTocLeader(
        canvas,
        line,
        pageWidth: pageWidth,
        marginRight: marginRight,
      );
      _drawOverlay(
        canvas,
        line,
        pageWidth: pageWidth,
        marginRight: marginRight,
      );
    }
  }

  void _paintTextRun(
    Canvas canvas,
    LaidOutLine line,
    String paragraph,
    List<LaidOutGlyph> run,
  ) {
    if (run.isEmpty) {
      return;
    }
    final LaidOutGlyph first = run.first;
    final String text = PaintRunText.runText(paragraph, run);
    if (text.isEmpty) {
      return;
    }
    final TextPainter painter = PaintRunText.painterFor(
      text: text,
      first: first,
      themeFamily: _theme.fontFamily,
      color: _colorFromHex(first.color),
      decoration: first.underline == WmlUnderline.none
          ? TextDecoration.none
          : TextDecoration.underline,
    )..layout();
    final double paintX = PaintRunText.runPaintOrigin(
      run,
      painter,
      text,
      paragraph,
    );
    painter.paint(
      canvas,
      Offset(
        paintX,
        first.vertAlign.paintTop(
          lineY: line.y,
          lineHeight: line.height,
          fontSize: first.fontSize,
        ),
      ),
    );
  }

  void _drawTocLeader(
    Canvas canvas,
    LaidOutLine line, {
    double? pageWidth,
    double? marginRight,
  }) {
    if (!line.tocLeader || line.glyphs.isEmpty) {
      return;
    }
    final LaidOutGlyph last = line.glyphs.last;
    final double from = last.x + last.advance + 6;
    final double numberWidth =
        (line.overlayText?.length ?? 1) * (line.overlaySize * 0.56);
    final double to = WordToc.leaderEndX(
      pageWidth: pageWidth ?? laidOut.pageSize.width,
      marginRight: marginRight ?? 72,
      numberWidth: numberWidth,
    );
    if (to <= from + 8) {
      return;
    }
    final Paint dots = Paint()
      ..color = const Color(0xFF8A8A8A)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    final double y = line.y + line.height * 0.72;
    for (double x = from; x < to; x += 4) {
      canvas.drawCircle(Offset(x, y), 0.55, dots);
    }
  }

  String _paragraphTextAt(int index, {LaidOutLine? line}) {
    final List<WmlParagraph> paras = _storyForLine(line);
    if (paras.isEmpty) {
      return '';
    }
    return paras[index.clamp(0, paras.length - 1)].text;
  }

  List<WmlParagraph> _storyForLine(LaidOutLine? line) {
    if (storyParagraphs != null &&
        _editingHeaderFooter &&
        (line == null ||
            (editingFooter && line.isFooter) ||
            (editingHeader && !line.isFooter))) {
      return storyParagraphs!;
    }
    if (line != null &&
        (line.isFooter || (line.overlayText != null && line.glyphs.isEmpty))) {
      final WmlSection? section = _pageSectionForLine(line);
      if (section != null) {
        return line.isFooter ? section.footer : section.header;
      }
    }
    return document.paragraphs.toList();
  }

  WmlSection? _pageSectionForLine(LaidOutLine line) {
    if (line.pageIndex < 0 || line.pageIndex >= laidOut.pages.length) {
      return document.sections.isEmpty ? null : document.sections.first;
    }
    final int sectionIndex = laidOut.pages[line.pageIndex].sectionIndex;
    if (sectionIndex < 0 || sectionIndex >= document.sections.length) {
      return null;
    }
    return document.sections[sectionIndex];
  }

  Color _colorFromHex(String hex) {
    final String resolved =
        WmlHighlight.toRgb(hex) ?? hex.replaceFirst('#', '');
    final String clean = resolved.replaceFirst('#', '');
    if (clean.length != 6) {
      return const Color(0xFF000000);
    }
    final int rgb = int.tryParse(clean, radix: 16) ?? 0;
    return Color(0xFF000000 | rgb);
  }

  bool _isLastParagraphLine(LaidOutPage page, LaidOutLine line) {
    for (final LaidOutLine other in page.lines) {
      if (other.paragraphIndex == line.paragraphIndex &&
          other.y > line.y + 0.01) {
        return false;
      }
    }
    for (final LaidOutPage later in laidOut.pages) {
      if (later.index <= page.index) {
        continue;
      }
      for (final LaidOutLine other in later.lines) {
        if (other.paragraphIndex == line.paragraphIndex) {
          return false;
        }
      }
    }
    return true;
  }

  void _paintCaret(Canvas canvas, LaidOutLine line) {
    final bool paragraphRtl = _paragraphRtl(line.paragraphIndex);
    final String paragraph =
        line.sourceText ?? _paragraphTextAt(line.paragraphIndex);
    CaretEngine.paintFlagged(
      canvas,
      stem: _caretPaintRect(line, paragraphRtl: paragraphRtl),
      color: _theme.caret,
      rtl: caret.rtlAtLaidOut(
        line,
        paragraphRtl: paragraphRtl,
        nearbyText: paragraph,
      ),
    );
  }

  bool _paragraphRtl(int paragraphIndex, {LaidOutLine? line}) {
    final List<WmlParagraph> paras = _storyForLine(line);
    if (paras.isEmpty) {
      return config.textDirection == TextDirection.rtl ||
          CaretEngine.deviceRtl();
    }
    final WmlParagraph para = paras[paragraphIndex.clamp(0, paras.length - 1)];
    if (para.properties.rightToLeft == true) {
      return true;
    }
    if (para.properties.rightToLeft == false) {
      return false;
    }
    return para.properties.justification == WmlJustification.right ||
        OfficeTypeface.isRtlText(para.text) ||
        config.textDirection == TextDirection.rtl ||
        CaretEngine.deviceRtl();
  }

  Rect _caretPaintRect(LaidOutLine line, {required bool paragraphRtl}) {
    final String paragraph =
        line.sourceText ?? _paragraphTextAt(line.paragraphIndex);
    final double x = PaintRunText.caretXOnLine(
      line,
      caret.logicalIndex,
      paragraph: paragraph,
      themeFamily: _theme.fontFamily,
      paragraphRtl: paragraphRtl,
      contentRight: laidOut.pageSize.width - 72,
    );
    if (line.glyphs.isNotEmpty) {
      final LaidOutGlyph marker = line.glyphs.first;
      final double size = marker.fontSize <= 0 ? 12 : marker.fontSize;
      final double ascent = size * 0.80;
      final double descent = size * 0.22;
      return Rect.fromLTWH(x, marker.y - ascent, 1.0, ascent + descent);
    }
    final double height = math.min(
      line.height,
      math.max(11.0, line.height * 0.78),
    );
    return Rect.fromLTWH(
      x,
      line.y + (line.height - height) * 0.08,
      1.0,
      height,
    );
  }
}

class _TableInsertHit {
  const _TableInsertHit({
    required this.table,
    required this.column,
    required this.index,
    required this.button,
    required this.lineStart,
    required this.lineEnd,
  });

  /// table API.
  final WmlTable table;

  /// column API.
  final bool column;

  /// index API.
  final int index;

  /// button API.
  final Rect button;

  /// lineStart API.
  final Offset lineStart;

  /// lineEnd API.
  final Offset lineEnd;

  /// axis API.
  double get axis => column ? lineStart.dx : lineStart.dy;
}

class _TableBandHit {
  const _TableBandHit({
    required this.table,
    required this.column,
    required this.index,
    required this.highlight,
  });

  /// table API.
  final WmlTable table;

  /// column API.
  final bool column;

  /// index API.
  final int index;

  /// highlight API.
  final Rect highlight;
}

class _TableGeom {
  _TableGeom(this.table);

  /// table API.
  final WmlTable table;

  /// bounds API.
  Rect bounds = Rect.zero;
  final Map<int, double> _rowTop = <int, double>{};
  final Map<int, double> _rowBottom = <int, double>{};
  final Map<int, double> _colLeft = <int, double>{};
  final Map<int, double> _colRight = <int, double>{};

  /// handleRect API.
  Rect get handleRect =>
      Rect.fromLTWH(bounds.left - 15, bounds.top - 15, 12, 12);

  /// add API.
  void add(LaidOutBox box) {
    final Rect rect = Rect.fromLTWH(box.x, box.y, box.width, box.height);
    bounds = bounds == Rect.zero ? rect : bounds.expandToInclude(rect);
    final int row = box.tableRow ?? 0;
    final int col = box.tableGridCol ?? box.tableCol ?? 0;
    _rowTop[row] = _minOr(_rowTop[row], rect.top);
    _rowBottom[row] = _maxOr(_rowBottom[row], rect.bottom);
    _colLeft[col] = _minOr(_colLeft[col], rect.left);
    _colRight[col] = _maxOr(_colRight[col], rect.right);
  }

  /// rowCount API.
  int get rowCount {
    var max = table.rows.length;
    for (final int key in _rowTop.keys) {
      if (key + 1 > max) {
        max = key + 1;
      }
    }
    return max;
  }

  /// colCount API.
  int get colCount {
    var max = WordTable.columnCount(table);
    for (final int key in _colLeft.keys) {
      if (key + 1 > max) {
        max = key + 1;
      }
    }
    return max;
  }

  /// rowBoundary API.
  double rowBoundary(int index) {
    if (index <= 0) {
      return bounds.top;
    }
    if (index >= rowCount) {
      return bounds.bottom;
    }
    return _rowTop[index] ?? _rowBottom[index - 1] ?? bounds.top;
  }

  /// colBoundary API.
  double colBoundary(int index) {
    if (index <= 0) {
      return bounds.left;
    }
    if (index >= colCount) {
      return bounds.right;
    }
    return _colLeft[index] ?? _colRight[index - 1] ?? bounds.left;
  }

  /// rowIndexAt API.
  int rowIndexAt(double y, {bool clamp = false}) {
    if (rowCount <= 0) {
      return -1;
    }
    if (y < rowBoundary(0)) {
      return clamp ? 0 : -1;
    }
    for (int i = 0; i < rowCount; i++) {
      if (y < rowBoundary(i + 1)) {
        return i;
      }
    }
    return clamp
        ? rowCount - 1
        : (y <= rowBoundary(rowCount) ? rowCount - 1 : -1);
  }

  /// colIndexAt API.
  int colIndexAt(double x, {bool clamp = false}) {
    if (colCount <= 0) {
      return -1;
    }
    if (x < colBoundary(0)) {
      return clamp ? 0 : -1;
    }
    for (int i = 0; i < colCount; i++) {
      if (x < colBoundary(i + 1)) {
        return i;
      }
    }
    return clamp
        ? colCount - 1
        : (x <= colBoundary(colCount) ? colCount - 1 : -1);
  }

  /// rowBand API.
  Rect rowBand(int from, int to) {
    final int a = from < to ? from : to;
    final int b = from > to ? from : to;
    return Rect.fromLTRB(
      bounds.left,
      rowBoundary(a),
      bounds.right,
      rowBoundary(b + 1),
    );
  }

  /// colBand API.
  Rect colBand(int from, int to) {
    final int a = from < to ? from : to;
    final int b = from > to ? from : to;
    return Rect.fromLTRB(
      colBoundary(a),
      bounds.top,
      colBoundary(b + 1),
      bounds.bottom,
    );
  }

  static double _minOr(double? current, double next) {
    return current == null || next < current ? next : current;
  }

  static double _maxOr(double? current, double next) {
    return current == null || next > current ? next : current;
  }
}

class _RulerView {
  const _RulerView({
    required this.pageLeft,
    required this.pageTop,
    required this.scale,
    required this.pageWidth,
    required this.pageHeight,
    required this.margins,
    required this.indent,
    required this.tabs,
    required this.rtl,
    required this.contentLeft,
    required this.contentRight,
  });

  final double pageLeft;
  final double pageTop;
  final double scale;
  final double pageWidth;
  final double pageHeight;
  final WmlPageMargins margins;
  final WmlIndent indent;
  final List<WmlTabStop> tabs;
  final bool rtl;
  final double contentLeft;
  final double contentRight;
}
