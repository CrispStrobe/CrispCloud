import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:quds_office_engine/quds_reports.dart';

import '../embed/office_theme.dart';
import 'report_designer_controller.dart';
import 'report_designer_strings.dart';

/// Part of the data explorer under a context click.
enum ReportDataArea {
  /// A table in the sidebar.
  table,

  /// A column header.
  header,

  /// A row number.
  rowHeader,

  /// A data cell.
  cell,

  /// Empty grid space.
  empty,
}

/// A right-click in the data explorer (the hit is selected first).
class ReportDataContextHit {
  /// ReportDataContextHit API.
  const ReportDataContextHit({
    required this.globalPosition,
    required this.area,
    this.table = '',
    this.row = -1,
    this.column = -1,
  });

  /// globalPosition API.
  final Offset globalPosition;

  /// area API.
  final ReportDataArea area;

  /// Table name ('' for the fields table).
  final String table;

  /// Row index, or -1.
  final int row;

  /// Column index, or -1.
  final int column;
}

/// Data explorer of the report designer: the tables and fields the report
/// is generated from, shown as an editable grid (like a BI data view).
class ReportDataExplorer extends LeafRenderObjectWidget {
  /// ReportDataExplorer API.
  const ReportDataExplorer({
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

  /// Right-click on a table, header, row, or cell.
  final ValueChanged<ReportDataContextHit>? onContextMenu;

  /// Pointer down anywhere (focus the designer).
  final VoidCallback? onActivate;

  @override
  RenderReportDataExplorer createRenderObject(BuildContext context) =>
      RenderReportDataExplorer(
        controller: controller,
        theme: theme,
        onContextMenu: onContextMenu,
        onActivate: onActivate,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportDataExplorer renderObject,
  ) {
    renderObject
      ..controller = controller
      ..theme = theme
      ..onContextMenu = onContextMenu
      ..onActivate = onActivate;
  }
}

/// RenderBox behind [ReportDataExplorer].
class RenderReportDataExplorer extends RenderBox {
  /// RenderReportDataExplorer API.
  RenderReportDataExplorer({
    required this._controller,
    required this._theme,
    this.onContextMenu,
    this.onActivate,
  });

  ReportDesignerController _controller;
  OfficeTheme _theme;

  /// onContextMenu API.
  ValueChanged<ReportDataContextHit>? onContextMenu;

  /// onActivate API.
  VoidCallback? onActivate;

  /// Header strip height.
  static const double headerHeight = 44;

  /// Column header height.
  static const double columnHeaderHeight = 30;

  /// Body row height.
  static const double rowHeight = 26;

  /// Row number gutter width.
  static const double gutterWidth = 48;

  /// Sidebar row height.
  static const double sideRowHeight = 30;

  static const double _bar = 10;

  final Map<String, TextPainter> _cache = <String, TextPainter>{};
  final Map<String, Rect> _buttons = <String, Rect>{};
  final List<_SideHit> _sideHits = <_SideHit>[];
  final Set<String> _collapsed = <String>{};

  Offset _scroll = Offset.zero;
  double _sideScroll = 0;
  Offset? _hover;
  Duration _lastTap = Duration.zero;
  Offset _lastTapPos = Offset.zero;
  String _scrollDrag = '';
  double _dragStart = 0;
  double _dragScroll = 0;
  double _editScrollX = 0;

  ReportDataTableView? _widthsFor;
  List<double> _widths = const <double>[];
  String _shown = '';

  /// controller API.
  ReportDesignerController get controller => _controller;

  set controller(ReportDesignerController value) {
    if (identical(value, _controller)) {
      markNeedsPaint();
      return;
    }
    if (attached) {
      _controller.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _controller = value;
    _widthsFor = null;
    markNeedsPaint();
  }

  /// theme API.
  OfficeTheme get theme => _theme;

  set theme(OfficeTheme value) {
    if (identical(value, _theme)) {
      return;
    }
    _theme = value;
    _clearText();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clearText();
    super.dispose();
  }

  void _clearText() {
    for (final TextPainter tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size s = constraints.biggest;
    return s.isFinite ? s : constraints.constrain(const Size(900, 600));
  }

  @override
  bool hitTestSelf(Offset position) => true;

  // ------------------------------------------------------------ colors

  Color get _ink => _theme.chromeText;

  Color get _muted => _theme.chromeText.withValues(alpha: 0.55);

  Color get _accent => _theme.selectionStroke;

  Color get _line => _theme.gridLine;

  /// Grid and button face: the paper color on light chrome, a lifted chrome
  /// tone on dark chrome (the paper stays white for the report canvas).
  Color get _cellFill => _theme.chromeFill.computeLuminance() < 0.35
      ? Color.alphaBlend(const Color(0x0FFFFFFF), _theme.chromeFill)
      : _theme.pageBackground;

  // ------------------------------------------------------------ geometry

  double get _sideWidth => size.width < 520
      ? math.max(156, size.width * 0.36)
      : math.min(268, math.max(210, size.width * 0.22));

  Rect get _sidebar => Rect.fromLTWH(0, 0, _sideWidth, size.height);

  /// Field tree under the "Field Explorer" title.
  Rect get _sideView => Rect.fromLTRB(0, 36, _sideWidth, size.height);

  double _sideExtent(int count) => 38 + count * sideRowHeight;

  double _sideMaxScroll(int count) =>
      math.max(0.0, _sideExtent(count) - size.height);

  Rect get _main => Rect.fromLTRB(_sideWidth, 0, size.width, size.height);

  Rect get _grid =>
      Rect.fromLTRB(_main.left, headerHeight, _main.right, size.height);

  List<double> _columnWidths(ReportDataTableView t) {
    if (identical(t, _widthsFor)) {
      return _widths;
    }
    final List<double> out = <double>[];
    for (int c = 0; c < t.columns.length; c++) {
      final ReportDataColumnView col = t.columns[c];
      var w = _text(col.name, 12, _ink, 1000, bold: true).width + 44;
      final int n = math.min(t.rows.length, 120);
      for (int r = 0; r < n; r++) {
        final String s = _controller.dataCellDisplay(col, t.rows[r][c]);
        if (s.isNotEmpty) {
          w = math.max(w, _measure(s) + 18);
        }
      }
      out.add(w.clamp(72, t.isFields && c == 1 ? 360 : 280).toDouble());
    }
    _widthsFor = t;
    _widths = out;
    return out;
  }

  double _measure(String s) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: _style(12, _ink)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double w = tp.width;
    tp.dispose();
    return w;
  }

  Size _content(ReportDataTableView t) {
    var w = 0.0;
    for (final double c in _columnWidths(t)) {
      w += c;
    }
    return Size(w, t.rows.length * rowHeight);
  }

  /// Body viewport (cells only, excluding headers and scrollbars).
  Rect _body(ReportDataTableView t) {
    final Rect g = _grid;
    final Size c = _content(t);
    var right = g.right;
    var bottom = g.bottom;
    final double vw = g.width - gutterWidth;
    final double vh = g.height - columnHeaderHeight;
    final bool needV = c.height > vh;
    final bool needH = c.width > vw - (needV ? _bar : 0);
    if (needV) {
      right -= _bar;
    }
    if (needH) {
      bottom -= _bar;
    }
    return Rect.fromLTRB(
      g.left + gutterWidth,
      g.top + columnHeaderHeight,
      math.max(g.left + gutterWidth, right),
      math.max(g.top + columnHeaderHeight, bottom),
    );
  }

  void _clamp(ReportDataTableView t) {
    final Rect b = _body(t);
    final Size c = _content(t);
    _scroll = Offset(
      _scroll.dx.clamp(0, math.max(0, c.width - b.width)).toDouble(),
      _scroll.dy.clamp(0, math.max(0, c.height - b.height)).toDouble(),
    );
  }

  double _columnLeft(int column) {
    var x = 0.0;
    for (int i = 0; i < column && i < _widths.length; i++) {
      x += _widths[i];
    }
    return x;
  }

  int _columnAt(ReportDataTableView t, double contentX) {
    var x = 0.0;
    final List<double> widths = _columnWidths(t);
    for (int i = 0; i < widths.length; i++) {
      if (contentX >= x && contentX < x + widths[i]) {
        return i;
      }
      x += widths[i];
    }
    return -1;
  }

  void _ensureVisible(ReportDataTableView t, int row, int column) {
    final Rect b = _body(t);
    var dx = _scroll.dx;
    var dy = _scroll.dy;
    if (row >= 0) {
      final double top = row * rowHeight;
      if (top < dy) {
        dy = top;
      } else if (top + rowHeight > dy + b.height) {
        dy = top + rowHeight - b.height;
      }
    }
    if (column >= 0 && column < _widths.length) {
      final double left = _columnLeft(column);
      final double w = _widths[column];
      if (left < dx) {
        dx = left;
      } else if (left + w > dx + b.width) {
        dx = math.min(left, left + w - b.width);
      }
    }
    _scroll = Offset(dx, dy);
    _clamp(t);
  }

  // ------------------------------------------------------------ events

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerSignalEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, _onSignal);
      return;
    }
    final ReportDataTableView t = _controller.dataTable;
    if (event is PointerPanZoomUpdateEvent) {
      if (_sidebar.contains(event.localPosition)) {
        _scrollSide(event.localPanDelta.dy);
      } else {
        _scroll -= event.localPanDelta;
        _clamp(t);
        markNeedsPaint();
      }
      return;
    }
    if (event is PointerHoverEvent) {
      _hover = event.localPosition;
      markNeedsPaint();
      return;
    }
    if (event is PointerDownEvent) {
      onActivate?.call();
      _onDown(event, t);
      return;
    }
    if (event is PointerMoveEvent && _scrollDrag.isNotEmpty) {
      if (_scrollDrag == 'sv') {
        _dragSideScrollbar(event.localPosition);
      } else {
        _dragScrollbar(event.localPosition, t);
      }
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _scrollDrag = '';
    }
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    if (_sidebar.contains(event.localPosition)) {
      _scrollSide(event.scrollDelta.dy);
      return;
    }
    _scroll += HardwareKeyboard.instance.isShiftPressed
        ? Offset(event.scrollDelta.dy, 0)
        : event.scrollDelta;
    _clamp(_controller.dataTable);
    markNeedsPaint();
  }

  void _scrollSide(double dy) {
    final int count = _sideSpecs(_controller.strings).length;
    _sideScroll = (_sideScroll + dy).clamp(0, _sideMaxScroll(count)).toDouble();
    markNeedsPaint();
  }

  /// Thumb of the field-tree scrollbar, or null when every row fits.
  Rect? get sidebarScrollbar => _sideBar()?.thumb;

  ({Rect track, Rect thumb})? _sideBar() {
    final int count = _sideSpecs(_controller.strings).length;
    final double max = _sideMaxScroll(count);
    final Rect view = _sideView;
    if (max <= 0 || view.height <= 0) {
      return null;
    }
    final double content = view.height + max;
    final Rect track = Rect.fromLTWH(
      view.right - _bar,
      view.top,
      _bar,
      view.height,
    );
    final double h = math.max(24, view.height * view.height / content);
    final double y = view.top + (view.height - h) * _sideScroll / max;
    return (track: track, thumb: Rect.fromLTWH(track.left + 2, y, _bar - 4, h));
  }

  bool _startSideScrollbar(Offset p) {
    final ({Rect track, Rect thumb})? bar = _sideBar();
    if (bar == null || !bar.track.contains(p)) {
      return false;
    }
    _scrollDrag = 'sv';
    _dragStart = p.dy;
    _dragScroll = _sideScroll;
    if (!bar.thumb.contains(p)) {
      final double page = _sideView.height;
      _scrollSide(p.dy < bar.thumb.top ? -page : page);
      _dragScroll = _sideScroll;
    }
    return true;
  }

  void _dragSideScrollbar(Offset p) {
    final ({Rect track, Rect thumb})? bar = _sideBar();
    if (bar == null) {
      return;
    }
    final int count = _sideSpecs(_controller.strings).length;
    final double max = _sideMaxScroll(count);
    final double free = _sideView.height - bar.thumb.height;
    final double ratio = free <= 0 ? 0 : max / free;
    _sideScroll = (_dragScroll + (p.dy - _dragStart) * ratio)
        .clamp(0, max)
        .toDouble();
    markNeedsPaint();
  }

  void _onDown(PointerDownEvent event, ReportDataTableView t) {
    final Offset p = event.localPosition;
    final bool secondary = event.buttons & kSecondaryMouseButton != 0;
    if (!secondary && _startSideScrollbar(p)) {
      return;
    }
    final bool quick =
        event.timeStamp - _lastTap < const Duration(milliseconds: 400) &&
        (p - _lastTapPos).distance < 6;
    _lastTap = event.timeStamp;
    _lastTapPos = p;

    for (final _SideHit h in _sideHits) {
      if (!_sideView.contains(p) || !h.rect.contains(p)) {
        continue;
      }
      final bool chevron = h.twist > 0 && p.dx < h.twist;
      if (h.action != null) {
        if (!secondary && !chevron) {
          if (h.table != null && h.table != t.name) {
            _controller.selectDataTable(h.table!);
          }
          _press(h.action!);
        }
        return;
      }
      if (h.table == null) {
        if (h.toggle != null) {
          _toggle(h.toggle!);
        }
        return;
      }
      if (chevron) {
        _toggle(h.toggle!);
        return;
      }
      if (_collapsed.contains(h.toggle)) {
        _collapsed.remove(h.toggle);
      }
      if (h.table != t.name) {
        _controller.selectDataTable(h.table!);
      }
      if (h.fieldRow >= 0) {
        _controller.selectDataCell(h.fieldRow, -1);
      } else if (h.column >= 0) {
        _controller.selectDataCell(-1, h.column);
        if (quick && h.formula) {
          _controller.beginPropertyEdit('data.col.expression');
        }
      }
      if (secondary) {
        _context(
          event,
          h.column >= 0
              ? ReportDataArea.header
              : h.fieldRow >= 0
              ? ReportDataArea.rowHeader
              : ReportDataArea.table,
          table: h.table!,
          row: h.fieldRow,
          column: h.column,
        );
      }
      return;
    }
    if (_sidebar.contains(p)) {
      return;
    }
    for (final MapEntry<String, Rect> b in _buttons.entries) {
      if (b.value.contains(p) && !secondary) {
        _press(b.key);
        return;
      }
    }
    final Rect body = _body(t);
    final Rect g = _grid;
    if (!secondary && _startScrollbar(p, t, body)) {
      return;
    }
    if (!g.contains(p)) {
      return;
    }
    final double cy = p.dy - body.top + _scroll.dy;
    final int row = p.dy >= body.top && p.dy < body.bottom
        ? (cy / rowHeight).floor()
        : -1;
    final int validRow = row >= 0 && row < t.rows.length ? row : -1;
    final int column = p.dx >= body.left && p.dx < body.right
        ? _columnAt(t, p.dx - body.left + _scroll.dx)
        : -1;
    if (p.dy < body.top) {
      if (column >= 0) {
        _controller.selectDataCell(-1, column);
        if (secondary) {
          _context(event, ReportDataArea.header, table: t.name, column: column);
        }
      }
      return;
    }
    if (p.dx < body.left) {
      if (validRow >= 0) {
        _controller.selectDataCell(validRow, -1);
        if (secondary) {
          _context(
            event,
            ReportDataArea.rowHeader,
            table: t.name,
            row: validRow,
          );
        }
      }
      return;
    }
    if (validRow < 0 || column < 0) {
      if (secondary) {
        _context(event, ReportDataArea.empty, table: t.name);
      }
      return;
    }
    final ({int row, int column})? editing = _controller.editingDataCell;
    if (editing != null &&
        editing.row == validRow &&
        editing.column == column &&
        !secondary) {
      _placeCaret(p, t, validRow, column, body);
      return;
    }
    if (quick && !secondary) {
      _controller.beginCellEdit(validRow, column);
      return;
    }
    _controller.selectDataCell(validRow, column);
    if (secondary) {
      _context(
        event,
        ReportDataArea.cell,
        table: t.name,
        row: validRow,
        column: column,
      );
    }
  }

  void _context(
    PointerDownEvent event,
    ReportDataArea area, {
    String table = '',
    int row = -1,
    int column = -1,
  }) {
    onContextMenu?.call(
      ReportDataContextHit(
        globalPosition: event.position,
        area: area,
        table: table,
        row: row,
        column: column,
      ),
    );
  }

  void _press(String id) {
    _controller.inspectorPage = ReportInspectorPage.properties;
    switch (id) {
      case 'field+':
        _controller.beginPropertyEdit('data.field+');
      case 'table+':
        _controller.beginPropertyEdit('data.table+');
      default:
        _controller.setProperty('data.$id', '');
    }
  }

  void _placeCaret(
    Offset p,
    ReportDataTableView t,
    int row,
    int column,
    Rect body,
  ) {
    final Rect cell = _cellRect(t, row, column, body);
    final TextPainter tp = _editPainter();
    final TextPosition pos = tp.getPositionForOffset(
      Offset(p.dx - cell.left - 6 + _editScrollX, tp.height / 2),
    );
    tp.dispose();
    _controller.propertyEditor.setCaret(pos.offset);
    markNeedsPaint();
  }

  ({Rect track, Rect thumb})? _vBar(ReportDataTableView t, Rect body) {
    final Size c = _content(t);
    if (c.height <= body.height || body.height <= 0) {
      return null;
    }
    final Rect track = Rect.fromLTWH(body.right, body.top, _bar, body.height);
    final double h = math.max(24, body.height * body.height / c.height);
    final double y =
        body.top + (body.height - h) * _scroll.dy / (c.height - body.height);
    return (track: track, thumb: Rect.fromLTWH(body.right + 2, y, _bar - 4, h));
  }

  ({Rect track, Rect thumb})? _hBar(ReportDataTableView t, Rect body) {
    final Size c = _content(t);
    if (c.width <= body.width || body.width <= 0) {
      return null;
    }
    final Rect track = Rect.fromLTWH(body.left, body.bottom, body.width, _bar);
    final double w = math.max(24, body.width * body.width / c.width);
    final double x =
        body.left + (body.width - w) * _scroll.dx / (c.width - body.width);
    return (
      track: track,
      thumb: Rect.fromLTWH(x, body.bottom + 2, w, _bar - 4),
    );
  }

  bool _startScrollbar(Offset p, ReportDataTableView t, Rect body) {
    final ({Rect track, Rect thumb})? v = _vBar(t, body);
    if (v != null && v.track.contains(p)) {
      _scrollDrag = 'v';
      _dragStart = p.dy;
      _dragScroll = _scroll.dy;
      if (!v.thumb.contains(p)) {
        _scroll = Offset(
          _scroll.dx,
          _scroll.dy + (p.dy < v.thumb.top ? -body.height : body.height),
        );
        _dragScroll = _scroll.dy;
        _clamp(t);
        markNeedsPaint();
      }
      return true;
    }
    final ({Rect track, Rect thumb})? h = _hBar(t, body);
    if (h != null && h.track.contains(p)) {
      _scrollDrag = 'h';
      _dragStart = p.dx;
      _dragScroll = _scroll.dx;
      if (!h.thumb.contains(p)) {
        _scroll = Offset(
          _scroll.dx + (p.dx < h.thumb.left ? -body.width : body.width),
          _scroll.dy,
        );
        _dragScroll = _scroll.dx;
        _clamp(t);
        markNeedsPaint();
      }
      return true;
    }
    return false;
  }

  void _dragScrollbar(Offset p, ReportDataTableView t) {
    final Rect body = _body(t);
    final Size c = _content(t);
    if (_scrollDrag == 'v') {
      final ({Rect track, Rect thumb})? v = _vBar(t, body);
      if (v == null) {
        return;
      }
      final double free = body.height - v.thumb.height;
      final double ratio = free <= 0 ? 0 : (c.height - body.height) / free;
      _scroll = Offset(_scroll.dx, _dragScroll + (p.dy - _dragStart) * ratio);
    } else {
      final ({Rect track, Rect thumb})? h = _hBar(t, body);
      if (h == null) {
        return;
      }
      final double free = body.width - h.thumb.width;
      final double ratio = free <= 0 ? 0 : (c.width - body.width) / free;
      _scroll = Offset(_dragScroll + (p.dx - _dragStart) * ratio, _scroll.dy);
    }
    _clamp(t);
    markNeedsPaint();
  }

  /// Local rectangle of cell ([row], [column]) of the shown table.
  Rect cellRect(int row, int column) {
    final ReportDataTableView t = _controller.dataTable;
    return _cellRect(t, row, column, _body(t));
  }

  /// Local rectangle of table [name] ('' for the fields) in the sidebar,
  /// once painted.
  Rect? sidebarRect(String name) {
    for (final _SideHit h in _sideHits) {
      if (h.table == name && h.column < 0 && h.fieldRow < 0 && !h.formula) {
        return h.rect;
      }
    }
    return null;
  }

  void _toggle(String key) {
    final bool opening = _collapsed.contains(key);
    if (opening) {
      _collapsed.remove(key);
    } else {
      _collapsed.add(key);
    }
    if (opening) {
      final List<_SideSpec> specs = _sideSpecs(_controller.strings);
      final int index = specs.indexWhere((_SideSpec s) => s.toggle == key);
      if (index >= 0) {
        final double top = 38 + index * sideRowHeight;
        if (top - _sideScroll > size.height - sideRowHeight * 4) {
          _sideScroll = (top - 42)
              .clamp(0, _sideMaxScroll(specs.length))
              .toDouble();
        }
      }
    }
    markNeedsPaint();
  }

  void _ensureSideRow(ReportDataTableView current) {
    final List<_SideSpec> specs = _sideSpecs(_controller.strings);
    var index = -1;
    for (int i = 0; i < specs.length; i++) {
      if (_sideSelected(specs[i], current)) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      return;
    }
    final double top = 38 + index * sideRowHeight;
    final double bottom = top + sideRowHeight;
    if (top - _sideScroll < 36) {
      _sideScroll = top - 38;
    } else if (bottom - _sideScroll > size.height) {
      _sideScroll = bottom - size.height;
    }
    _sideScroll = _sideScroll.clamp(0, _sideMaxScroll(specs.length)).toDouble();
  }

  Rect _cellRect(ReportDataTableView t, int row, int column, Rect body) {
    _columnWidths(t);
    return Rect.fromLTWH(
      body.left + _columnLeft(column) - _scroll.dx,
      body.top + row * rowHeight - _scroll.dy,
      column < _widths.length ? _widths[column] : 0,
      rowHeight,
    );
  }

  // ------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final ReportDataTableView t = _controller.dataTable;
    _columnWidths(t);
    final String shown =
        '${t.name}|${_controller.dataRow}|${_controller.dataColumn}';
    if (shown != _shown) {
      if (_shown.split('|').first != t.name) {
        _scroll = Offset.zero;
      }
      _shown = shown;
      _ensureVisible(t, _controller.dataRow, _controller.dataColumn);
      _ensureSideRow(t);
    }
    _clamp(t);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _theme.chromeFill);
    _paintSidebar(canvas, t);
    _paintHeader(canvas, t);
    _paintGrid(canvas, t);
    canvas.restore();
  }

  void _paintSidebar(Canvas canvas, ReportDataTableView current) {
    final Rect side = _sidebar;
    canvas.drawRect(side, Paint()..color = _theme.headerFill);
    canvas.drawLine(side.topRight, side.bottomRight, Paint()..color = _line);
    final ReportDesignerStrings s = _controller.strings;
    _text(
      s.t('Field Explorer'),
      10.5,
      _muted,
      side.width - 24,
      bold: true,
    ).paint(canvas, const Offset(12, 14));
    _buttons.remove('table+');
    _buttons.remove('formula+');
    final List<_SideSpec> specs = _sideSpecs(s);
    final double maxScroll = _sideMaxScroll(specs.length);
    _sideScroll = _sideScroll.clamp(0, maxScroll).toDouble();
    final ({Rect track, Rect thumb})? bar = _sideBar();
    _sideHits.clear();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 36, side.right - 1, side.bottom));
    var y = 38 - _sideScroll;
    final double rowRight = side.width - 6 - (bar == null ? 0 : _bar);
    for (final _SideSpec spec in specs) {
      final Rect r = Rect.fromLTWH(2, y, rowRight - 2, sideRowHeight - 2);
      final double indent = 6 + spec.depth * 13;
      final double twist = spec.toggle == null ? 0 : indent + 14;
      _sideHits.add(
        _SideHit(
          rect: r,
          table: spec.table,
          column: spec.column,
          fieldRow: spec.fieldRow,
          toggle: spec.toggle,
          twist: twist,
          formula: spec.formula,
          action: spec.action,
        ),
      );
      if (spec.action != null) {
        final Rect add = Rect.fromLTWH(
          indent,
          r.top + 1,
          r.right - indent - 4,
          r.height - 2,
        );
        _buttons[spec.action!] = add;
        _buttonFace(
          canvas,
          add,
          spec.label,
          _hover != null && r.contains(_hover!),
        );
        y += sideRowHeight;
        continue;
      }
      final bool selected = _sideSelected(spec, current);
      final bool hot = _hover != null && r.contains(_hover!);
      if (selected || hot) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..color = _accent.withValues(alpha: selected ? 0.16 : 0.07),
        );
      }
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left, r.top + 5, 3, r.height - 10),
            const Radius.circular(2),
          ),
          Paint()..color = spec.formula ? const Color(0xFF7B5CC4) : _accent,
        );
      }
      var x = indent;
      if (spec.toggle != null) {
        _chevron(
          canvas,
          Offset(x + 5, r.center.dy),
          !_collapsed.contains(spec.toggle),
        );
        x += 14;
      }
      _fieldGlyph(canvas, Offset(x + 8, r.center.dy), spec.glyph);
      x += 18;
      final String? badge = spec.badge;
      final TextPainter count = badge == null
          ? _text('', 11, _muted, 10)
          : _text(badge, 11, _muted, 48);
      final double countW = badge == null ? 0 : count.width + 10;
      final TextPainter name = _text(
        spec.label,
        12,
        _ink,
        math.max(16, r.right - x - countW - 6),
        bold: selected || spec.depth == 0,
      );
      name.paint(canvas, Offset(x, r.center.dy - name.height / 2));
      if (badge != null) {
        count.paint(
          canvas,
          Offset(r.right - count.width - 6, r.center.dy - count.height / 2),
        );
      }
      y += sideRowHeight;
    }
    canvas.restore();
    if (bar != null) {
      canvas.drawRect(bar.track, Paint()..color = _theme.headerFill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar.thumb, const Radius.circular(3)),
        Paint()..color = _ink.withValues(alpha: 0.45),
      );
    }
  }

  bool _sideSelected(_SideSpec spec, ReportDataTableView current) {
    if (spec.action != null ||
        spec.table == null ||
        spec.table != current.name) {
      return false;
    }
    if (spec.fieldRow >= 0) {
      return _controller.dataRow == spec.fieldRow;
    }
    if (spec.column >= 0) {
      return _controller.dataColumn == spec.column;
    }
    return _controller.dataColumn < 0 &&
        (!current.isFields || _controller.dataRow < 0);
  }

  List<_SideSpec> _sideSpecs(ReportDesignerStrings s) {
    final List<ReportDataTableView> tables = _controller.dataTables;
    final List<_SideSpec> out = <_SideSpec>[
      _SideSpec(
        label: s.t('Database Fields'),
        depth: 0,
        glyph: _FieldGlyph.folder,
        toggle: 'db',
      ),
    ];
    if (_collapsed.contains('db')) {
      return out;
    }
    for (final ReportDataTableView t in tables) {
      final bool expandable = t.isFields ? t.rows.isNotEmpty : true;
      out.add(
        _SideSpec(
          label: t.isFields ? s.t('Fields') : t.title,
          depth: 1,
          glyph: t.isFields ? _FieldGlyph.fields : _FieldGlyph.table,
          toggle: expandable ? 't:${t.name}' : null,
          table: t.name,
          badge: '${t.isFields ? t.rows.length : t.columns.length}',
        ),
      );
      if (!expandable || _collapsed.contains('t:${t.name}')) {
        continue;
      }
      if (t.isFields) {
        for (int i = 0; i < t.rows.length; i++) {
          final ReportDataType type =
              ReportDataType.fromName(t.rows[i][2].displayText) ??
              ReportDataType.text;
          out.add(
            _SideSpec(
              label: t.rows[i][0].displayText,
              depth: 2,
              glyph: _glyphFor(type, calculated: false),
              table: t.name,
              fieldRow: i,
            ),
          );
        }
        continue;
      }
      for (int c = 0; c < t.columns.length; c++) {
        final ReportDataColumnView col = t.columns[c];
        out.add(
          _SideSpec(
            label: col.name,
            depth: 2,
            glyph: _glyphFor(col.type, calculated: col.isCalculated),
            table: t.name,
            column: c,
            formula: col.isCalculated,
          ),
        );
      }
      out.add(
        _SideSpec(
          label: s.t('+ Column'),
          depth: 2,
          glyph: _FieldGlyph.text,
          table: t.name,
          action: 'col+',
        ),
      );
      out.add(
        _SideSpec(
          label: s.t('+ Formula'),
          depth: 2,
          glyph: _FieldGlyph.formula,
          table: t.name,
          action: 'formula+',
        ),
      );
    }
    out.add(
      _SideSpec(
        label: s.t('+ New table'),
        depth: 1,
        glyph: _FieldGlyph.folder,
        action: 'table+',
      ),
    );
    return out;
  }

  _FieldGlyph _glyphFor(ReportDataType type, {required bool calculated}) {
    if (calculated) {
      return _FieldGlyph.formula;
    }
    return switch (type) {
      ReportDataType.text => _FieldGlyph.text,
      ReportDataType.number => _FieldGlyph.number,
      ReportDataType.boolean => _FieldGlyph.boolean,
      ReportDataType.date => _FieldGlyph.date,
    };
  }

  void _chevron(Canvas canvas, Offset c, bool open) {
    final Path path = Path();
    if (open) {
      path
        ..moveTo(c.dx - 3.5, c.dy - 1.2)
        ..lineTo(c.dx + 3.5, c.dy - 1.2)
        ..lineTo(c.dx, c.dy + 3);
    } else {
      path
        ..moveTo(c.dx - 1.5, c.dy - 3.5)
        ..lineTo(c.dx + 2.2, c.dy)
        ..lineTo(c.dx - 1.5, c.dy + 3.5);
    }
    canvas.drawPath(path..close(), Paint()..color = _muted);
  }

  void _fieldGlyph(Canvas canvas, Offset c, _FieldGlyph glyph) {
    final Color tone = switch (glyph) {
      _FieldGlyph.folder => const Color(0xFFE6A817),
      _FieldGlyph.formula => const Color(0xFF7B5CC4),
      _FieldGlyph.table || _FieldGlyph.fields => const Color(0xFF8D6E63),
      _FieldGlyph.text => const Color(0xFF1565C0),
      _FieldGlyph.number => const Color(0xFF2E7D32),
      _FieldGlyph.boolean => const Color(0xFF00897B),
      _FieldGlyph.date => const Color(0xFFEF6C00),
    };
    if (glyph == _FieldGlyph.folder) {
      _folderIcon(canvas, c, tone);
      return;
    }
    if (glyph == _FieldGlyph.table || glyph == _FieldGlyph.fields) {
      _tableGlyph(canvas, c, glyph == _FieldGlyph.fields);
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 14, height: 14),
        const Radius.circular(3),
      ),
      Paint()..color = tone.withValues(alpha: 0.16),
    );
    if (glyph == _FieldGlyph.formula) {
      final TextPainter tp = _text('fx', 9, tone, 16, bold: true, italic: true);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      return;
    }
    if (glyph == _FieldGlyph.boolean) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - 4, c.dy)
          ..lineTo(c.dx - 1.2, c.dy + 3)
          ..lineTo(c.dx + 4.5, c.dy - 3.2),
        Paint()
          ..color = tone
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    if (glyph == _FieldGlyph.date) {
      final Rect r = Rect.fromCenter(center: c, width: 10, height: 9);
      final Paint stroke = Paint()
        ..color = tone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(1.5)),
        stroke,
      );
      canvas.drawLine(
        Offset(r.left, r.top + 3),
        Offset(r.right, r.top + 3),
        stroke,
      );
      return;
    }
    final TextPainter tp = _text(
      glyph == _FieldGlyph.number ? '#' : 'Ab',
      9,
      tone,
      16,
      bold: true,
    );
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _folderIcon(Canvas canvas, Offset c, Color color) {
    final Path path = Path()
      ..moveTo(c.dx - 7, c.dy - 2)
      ..lineTo(c.dx - 7, c.dy + 5)
      ..lineTo(c.dx + 7, c.dy + 5)
      ..lineTo(c.dx + 7, c.dy - 1)
      ..lineTo(c.dx + 0.5, c.dy - 1)
      ..lineTo(c.dx - 1.5, c.dy - 4)
      ..lineTo(c.dx - 7, c.dy - 4)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _tableGlyph(Canvas canvas, Offset c, bool fields) {
    final Paint stroke = Paint()
      ..color = _muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    if (fields) {
      final TextPainter tp = _text('{ }', 11, _muted, 30, bold: true);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      return;
    }
    final Rect r = Rect.fromCenter(center: c, width: 13, height: 11);
    canvas.drawRect(r, stroke);
    canvas.drawLine(
      Offset(r.left, r.top + 3.5),
      Offset(r.right, r.top + 3.5),
      stroke,
    );
    canvas.drawLine(
      Offset(r.left, r.top + 7.2),
      Offset(r.right, r.top + 7.2),
      stroke,
    );
    canvas.drawLine(
      Offset(r.left + 4.5, r.top),
      Offset(r.left + 4.5, r.bottom),
      stroke,
    );
  }

  void _buttonFace(Canvas canvas, Rect r, String label, bool hot) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(5)),
      Paint()..color = hot ? _accent.withValues(alpha: 0.12) : _cellFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(0.5), const Radius.circular(5)),
      Paint()
        ..color = hot ? _accent : _line
        ..style = PaintingStyle.stroke,
    );
    final TextPainter tp = _text(label, 12, _accent, r.width - 8, bold: true);
    tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintHeader(Canvas canvas, ReportDataTableView t) {
    final Rect m = _main;
    final Rect h = Rect.fromLTWH(m.left, 0, m.width, headerHeight);
    canvas.drawLine(h.bottomLeft, h.bottomRight, Paint()..color = _line);
    for (final String k in _buttons.keys.toList()) {
      if (k != 'table+' && k != 'formula+') {
        _buttons.remove(k);
      }
    }
    final bool host = _controller.hasHostData;
    final ReportDesignerStrings s = _controller.strings;
    final List<(String, String)> actions = <(String, String)>[
      if (t.isFields)
        ('field+', s.t('+ Field'))
      else ...<(String, String)>[
        if (!host) ('row+', s.t('+ Row')),
        ('col+', s.t('+ Column')),
        ('calc+', s.t('ƒx Column')),
      ],
      if (_controller.dataPicker != null && !host) ('import', s.t('Import…')),
    ];
    var right = h.right - 10;
    for (final (String id, String label) in actions.reversed) {
      final double w = _text(label, 12, _accent, 200, bold: true).width + 20;
      if (right - w < h.left + 160) {
        break;
      }
      final Rect r = Rect.fromLTWH(right - w, h.center.dy - 13, w, 26);
      _buttons[id] = r;
      _buttonFace(canvas, r, label, _hover != null && r.contains(_hover!));
      right -= w + 6;
    }
    var x = h.left + 14;
    final TextPainter title = _text(
      t.title,
      14,
      _ink,
      math.max(40, right - x - 140),
      bold: true,
    );
    title.paint(canvas, Offset(x, h.center.dy - title.height / 2));
    x += title.width + 10;
    final String info = t.isFields
        ? s.count(t.rows.length, 'value')
        : '${s.count(t.rows.length, 'row')} · '
              '${s.count(t.columns.length, 'column')}';
    final String source = s.t(
      host
          ? 'host data · read-only'
          : _controller.hasSampleData
          ? 'sample data'
          : 'generated',
    );
    final TextPainter sub = _text(
      '$info  ·  $source',
      11.5,
      _muted,
      math.max(20, right - x - 8),
    );
    sub.paint(canvas, Offset(x, h.center.dy - sub.height / 2));
  }

  void _paintGrid(Canvas canvas, ReportDataTableView t) {
    final Rect g = _grid;
    final Rect body = _body(t);
    canvas.drawRect(g, Paint()..color = _cellFill);
    if (t.columns.isEmpty) {
      final TextPainter tp = _text(
        _controller.strings.t(
          t.isFields
              ? 'No single-value fields. Add one with "+ Field".'
              : 'This table has no columns yet. Add a column or import a CSV '
                    'or JSON file.',
        ),
        12.5,
        _muted,
        g.width - 40,
      );
      tp.paint(canvas, Offset(g.left + 20, g.top + 24));
      return;
    }
    final List<double> widths = _columnWidths(t);
    final int first = math.max(0, (_scroll.dy / rowHeight).floor());
    final int last = math.min(
      t.rows.length - 1,
      ((_scroll.dy + body.height) / rowHeight).ceil(),
    );
    final int selRow = _controller.dataRow;
    final int selCol = _controller.dataColumn;
    final ({int row, int column})? editing = _controller.editingDataCell;
    final Paint gridPaint = Paint()..color = _line.withValues(alpha: 0.7);

    canvas.save();
    canvas.clipRect(body);
    var x = body.left - _scroll.dx;
    for (int c = 0; c < widths.length; c++) {
      final double w = widths[c];
      if (x + w >= body.left && x <= body.right) {
        final ReportDataColumnView col = t.columns[c];
        final bool calc = col.isCalculated;
        final bool readOnly = t.isFields && c != 1;
        if (calc || readOnly || (selCol == c && selRow < 0)) {
          canvas.drawRect(
            Rect.fromLTWH(x, body.top, w, body.height),
            Paint()
              ..color = selCol == c && selRow < 0
                  ? _accent.withValues(alpha: 0.10)
                  : calc
                  ? const Color(0xFF7B5CC4).withValues(alpha: 0.06)
                  : _theme.headerFill.withValues(alpha: 0.6),
          );
        }
        for (int r = first; r <= last; r++) {
          final double y = body.top + r * rowHeight - _scroll.dy;
          final Rect cell = Rect.fromLTWH(x, y, w, rowHeight);
          if (selRow == r && selCol < 0) {
            canvas.drawRect(
              cell,
              Paint()..color = _accent.withValues(alpha: 0.10),
            );
          }
          if (editing != null && editing.row == r && editing.column == c) {
            continue;
          }
          _paintCell(canvas, cell, col, t.rows[r][c], italic: calc);
        }
        canvas.drawLine(
          Offset(x + w - 0.5, body.top),
          Offset(x + w - 0.5, body.bottom),
          gridPaint,
        );
      }
      x += w;
    }
    for (int r = first; r <= last + 1; r++) {
      final double y = body.top + r * rowHeight - _scroll.dy - 0.5;
      canvas.drawLine(
        Offset(body.left, y),
        Offset(math.min(body.right, x), y),
        gridPaint,
      );
    }
    if (selRow >= 0 && selCol >= 0 && selRow < t.rows.length) {
      final Rect cell = _cellRect(t, selRow, selCol, body);
      canvas.drawRect(
        cell.deflate(1),
        Paint()
          ..color = _accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (editing != null &&
        editing.row < t.rows.length &&
        editing.column < t.columns.length) {
      _paintEditor(canvas, _cellRect(t, editing.row, editing.column, body));
    }
    canvas.restore();

    _paintColumnHeaders(canvas, t, body, selRow, selCol);
    _paintGutter(canvas, t, body, first, last, selRow, selCol);

    final Rect corner = Rect.fromLTWH(
      g.left,
      g.top,
      gutterWidth,
      columnHeaderHeight,
    );
    canvas.drawRect(corner, Paint()..color = _theme.headerFill);
    canvas.drawLine(
      corner.bottomLeft,
      corner.bottomRight,
      Paint()..color = _line,
    );
    canvas.drawLine(
      corner.topRight,
      corner.bottomRight,
      Paint()..color = _line,
    );

    if (t.rows.isEmpty) {
      final TextPainter tp = _text(
        _controller.strings.t(
          _controller.hasHostData
              ? 'The host data has no rows for this table.'
              : 'No rows yet. Add a row with "+ Row" or import a CSV / JSON '
                    'file.',
        ),
        12.5,
        _muted,
        body.width - 32,
      );
      tp.paint(canvas, Offset(body.left + 16, body.top + 16));
    }
    final Paint thumb = Paint()..color = _ink.withValues(alpha: 0.28);
    for (final ({Rect track, Rect thumb})? bar in <({Rect track, Rect thumb})?>[
      _vBar(t, body),
      _hBar(t, body),
    ]) {
      if (bar != null) {
        canvas.drawRect(bar.track, Paint()..color = _theme.headerFill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(bar.thumb, const Radius.circular(3)),
          thumb,
        );
      }
    }
  }

  void _paintCell(
    Canvas canvas,
    Rect cell,
    ReportDataColumnView col,
    ReportValue v, {
    required bool italic,
  }) {
    if (v is ReportNull) {
      return;
    }
    final String s = _controller.dataCellDisplay(col, v);
    final bool numeric = v is ReportNumber || v is ReportDate;
    final bool complex = v is ReportList || v is ReportRecord;
    final TextPainter tp = _text(
      s,
      12,
      complex ? _muted : _ink,
      cell.width - 12,
      italic: italic || complex,
    );
    final double dx = numeric
        ? cell.right - 6 - tp.width
        : v is ReportBool
        ? cell.center.dx - tp.width / 2
        : cell.left + 6;
    tp.paint(canvas, Offset(dx, cell.center.dy - tp.height / 2));
  }

  void _paintColumnHeaders(
    Canvas canvas,
    ReportDataTableView t,
    Rect body,
    int selRow,
    int selCol,
  ) {
    final Rect strip = Rect.fromLTRB(
      body.left,
      body.top - columnHeaderHeight,
      _grid.right,
      body.top,
    );
    canvas.drawRect(strip, Paint()..color = _theme.headerFill);
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(body.left, strip.top, body.right, strip.bottom),
    );
    var x = body.left - _scroll.dx;
    for (int c = 0; c < t.columns.length; c++) {
      final double w = _widths[c];
      final Rect r = Rect.fromLTWH(x, strip.top, w, columnHeaderHeight);
      if (r.right >= body.left && r.left <= body.right) {
        final ReportDataColumnView col = t.columns[c];
        final bool selected = selCol == c;
        if (selected) {
          canvas.drawRect(
            r,
            Paint()
              ..color = _accent.withValues(alpha: selRow < 0 ? 0.22 : 0.10),
          );
        }
        _typeGlyph(canvas, Offset(r.left + 14, r.center.dy), col, t.isFields);
        final TextPainter tp = _text(
          col.name,
          12,
          _theme.headerText,
          w - 34,
          bold: true,
        );
        tp.paint(canvas, Offset(r.left + 26, r.center.dy - tp.height / 2));
        canvas.drawLine(
          Offset(r.right - 0.5, r.top + 5),
          Offset(r.right - 0.5, r.bottom - 5),
          Paint()..color = _line,
        );
      }
      x += w;
    }
    canvas.restore();
    canvas.drawLine(
      strip.bottomLeft,
      strip.bottomRight,
      Paint()..color = _line,
    );
  }

  void _typeGlyph(
    Canvas canvas,
    Offset c,
    ReportDataColumnView col,
    bool fields,
  ) {
    if (fields) {
      return;
    }
    final Color tone = col.isCalculated
        ? const Color(0xFF7B5CC4)
        : _theme.headerText.withValues(alpha: 0.7);
    if (col.isCalculated) {
      final TextPainter tp = _text(
        'ƒx',
        11,
        tone,
        30,
        bold: true,
        italic: true,
      );
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      return;
    }
    final Paint stroke = Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    switch (col.type) {
      case ReportDataType.text:
        final TextPainter tp = _text('Aa', 10.5, tone, 30, bold: true);
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      case ReportDataType.number:
        final TextPainter tp = _text('12', 10.5, tone, 30, bold: true);
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      case ReportDataType.boolean:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 5, c.dy)
            ..lineTo(c.dx - 1.5, c.dy + 3.5)
            ..lineTo(c.dx + 5, c.dy - 4),
          stroke,
        );
      case ReportDataType.date:
        final Rect r = Rect.fromCenter(center: c, width: 12, height: 11);
        canvas.drawRect(r, stroke);
        canvas.drawLine(
          Offset(r.left, r.top + 3.5),
          Offset(r.right, r.top + 3.5),
          stroke,
        );
        canvas.drawLine(
          Offset(r.left + 3.5, r.top - 1.5),
          Offset(r.left + 3.5, r.top + 1.5),
          stroke,
        );
        canvas.drawLine(
          Offset(r.right - 3.5, r.top - 1.5),
          Offset(r.right - 3.5, r.top + 1.5),
          stroke,
        );
    }
  }

  void _paintGutter(
    Canvas canvas,
    ReportDataTableView t,
    Rect body,
    int first,
    int last,
    int selRow,
    int selCol,
  ) {
    final Rect strip = Rect.fromLTRB(
      _grid.left,
      body.top,
      body.left,
      _grid.bottom,
    );
    canvas.drawRect(strip, Paint()..color = _theme.headerFill);
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(strip.left, body.top, strip.right, body.bottom),
    );
    for (int r = first; r <= last; r++) {
      final double y = body.top + r * rowHeight - _scroll.dy;
      final Rect cell = Rect.fromLTWH(strip.left, y, gutterWidth, rowHeight);
      if (selRow == r) {
        canvas.drawRect(
          cell,
          Paint()..color = _accent.withValues(alpha: selCol < 0 ? 0.22 : 0.10),
        );
      }
      final TextPainter tp = _text('${r + 1}', 11, _muted, gutterWidth - 8);
      tp.paint(
        canvas,
        Offset(cell.right - 8 - tp.width, cell.center.dy - tp.height / 2),
      );
    }
    canvas.restore();
    canvas.drawLine(strip.topRight, strip.bottomRight, Paint()..color = _line);
  }

  void _paintEditor(Canvas canvas, Rect cell) {
    canvas.drawRect(cell, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      cell.deflate(1),
      Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final TextPainter tp = _editPainter();
    final int caret = _controller.propertyEditor.caretIndex;
    final Offset at = tp.getOffsetForCaret(
      TextPosition(offset: caret),
      Rect.zero,
    );
    final double inner = cell.width - 12;
    if (at.dx - _editScrollX > inner) {
      _editScrollX = at.dx - inner + 2;
    } else if (at.dx < _editScrollX) {
      _editScrollX = at.dx;
    }
    final Offset origin = Offset(
      cell.left + 6 - _editScrollX,
      cell.center.dy - tp.height / 2,
    );
    canvas.save();
    canvas.clipRect(cell.deflate(2));
    final int start = _controller.propertyEditor.selectionStart;
    final int end = _controller.propertyEditor.selectionEnd;
    if (end > start) {
      for (final TextBox b in tp.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      )) {
        canvas.drawRect(
          b.toRect().shift(origin),
          Paint()..color = _accent.withValues(alpha: 0.28),
        );
      }
    }
    tp.paint(canvas, origin);
    canvas.drawRect(
      Rect.fromLTWH(origin.dx + at.dx, origin.dy, 1.2, tp.preferredLineHeight),
      Paint()..color = const Color(0xFF111111),
    );
    canvas.restore();
    tp.dispose();
  }

  TextPainter _editPainter() => TextPainter(
    text: TextSpan(
      text: _controller.propertyEditor.formulaBar,
      style: _style(12, const Color(0xFF111111)),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  TextStyle _style(
    double size,
    Color color, {
    bool bold = false,
    bool italic = false,
  }) => TextStyle(
    fontFamily: _theme.fontFamily ?? 'Liberation Sans',
    fontFamilyFallback: const <String>['Noto Naskh Arabic'],
    fontSize: size,
    color: color,
    fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  );

  TextPainter _text(
    String text,
    double fontSize,
    Color color,
    double maxWidth, {
    bool bold = false,
    bool italic = false,
  }) {
    final double w = maxWidth < 10 ? 10 : maxWidth;
    final String key = '$text|$fontSize|${color.toARGB32()}|$w|$bold|$italic';
    final TextPainter? hit = _cache[key];
    if (hit != null) {
      return hit;
    }
    if (_cache.length > 600) {
      _clearText();
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text.replaceAll('\n', ' '),
        style: _style(fontSize, color, bold: bold, italic: italic),
      ),
      textDirection: _controller.strings.direction,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: w);
    _cache[key] = tp;
    return tp;
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    final ReportDataTableView t = _controller.dataTable;
    config
      ..isSemanticBoundary = true
      ..textDirection = TextDirection.ltr
      ..label = 'Report data explorer'
      ..value =
          '${t.title}: ${t.rows.length} rows, ${t.columns.length} columns';
  }
}

/// Icon drawn beside a field in the explorer.
enum _FieldGlyph { folder, table, fields, text, number, boolean, date, formula }

/// One row of the field tree, before it is laid out.
class _SideSpec {
  const _SideSpec({
    required this.label,
    required this.depth,
    required this.glyph,
    this.toggle,
    this.table,
    this.column = -1,
    this.fieldRow = -1,
    this.formula = false,
    this.action,
    this.badge,
  });

  final String label;
  final int depth;
  final _FieldGlyph glyph;
  final String? toggle;
  final String? table;
  final int column;
  final int fieldRow;
  final bool formula;
  final String? action;
  final String? badge;
}

/// A painted row of the field tree.
class _SideHit {
  const _SideHit({
    required this.rect,
    this.table,
    this.column = -1,
    this.fieldRow = -1,
    this.toggle,
    this.twist = 0,
    this.formula = false,
    this.action,
  });

  final Rect rect;
  final String? table;
  final int column;
  final int fieldRow;
  final String? toggle;
  final double twist;
  final bool formula;
  final String? action;
}
