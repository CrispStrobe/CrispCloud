import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../embed/office_theme.dart';

/// Vector icons drawn by [ReportToolbar].
enum ReportToolbarIcon {
  /// Arrow pointer.
  select,

  /// Text box.
  text,

  /// Picture.
  image,

  /// Table grid.
  table,

  /// Barcode bars.
  barcode,

  /// QR squares.
  qr,

  /// Diagonal line.
  line,

  /// Rectangle.
  rectangle,

  /// Ellipse.
  ellipse,

  /// Bar chart.
  chart,

  /// Shape map.
  map,

  /// A page marked with its number.
  pageNumber,

  /// Page number and page count.
  pages,

  /// Calendar.
  date,

  /// Report title lines.
  reportName,

  /// Numbered rows.
  rowNumber,

  /// A summed column.
  total,

  /// Rounded rectangle.
  rounded,

  /// A signing stroke.
  signature,

  /// Document gallery (templates).
  templates,

  /// Braces with an x (template variables).
  variables,

  /// Undo arrow.
  undo,

  /// Redo arrow.
  redo,

  /// Trash / delete.
  delete,

  /// Two stacked boxes.
  duplicate,

  /// Align left edges.
  alignLeft,

  /// Align horizontal centers.
  alignCenter,

  /// Align right edges.
  alignRight,

  /// Align top edges.
  alignTop,

  /// Align vertical centers.
  alignMiddle,

  /// Align bottom edges.
  alignBottom,

  /// Distribute horizontally.
  distributeX,

  /// Distribute vertically.
  distributeY,

  /// Same width.
  sameWidth,

  /// Same height.
  sameHeight,

  /// Bring to front.
  front,

  /// Send to back.
  back,

  /// Zoom in.
  zoomIn,

  /// Zoom out.
  zoomOut,

  /// Fit width.
  fitWidth,

  /// Grid.
  grid,

  /// Eye (preview).
  preview,

  /// Pencil (design).
  design,

  /// Download arrow (export).
  export,

  /// Printer.
  print,

  /// Band rows (add band).
  band,

  /// Letter pair (fonts).
  font,

  /// Database cylinder (data explorer).
  data,
}

/// One toolbar button.
@immutable
class ReportToolbarItem {
  /// ReportToolbarItem API.
  const ReportToolbarItem({
    required this.id,
    required this.icon,
    required this.tooltip,
    this.label,
    this.enabled = true,
    this.active = false,
    this.separatorBefore = false,
  });

  /// Passed to [ReportToolbar.onPressed].
  final String id;

  /// icon API.
  final ReportToolbarIcon icon;

  /// Shown in the status area while hovered.
  final String tooltip;

  /// Optional text after the icon.
  final String? label;

  /// enabled API.
  final bool enabled;

  /// Toggled-on state.
  final bool active;

  /// Draw a separator before this button.
  final bool separatorBefore;
}

/// Designer toolbar painted on a RenderBox; wraps onto more rows when narrow.
class ReportToolbar extends LeafRenderObjectWidget {
  /// ReportToolbar API.
  const ReportToolbar({
    super.key,
    required this.items,
    this.status = '',
    this.theme = OfficeTheme.light,
    this.onPressed,
    this.onPressedAt,
  });

  /// items API.
  final List<ReportToolbarItem> items;

  /// Right-aligned status text.
  final String status;

  /// theme API.
  final OfficeTheme theme;

  /// Button click.
  final ValueChanged<String>? onPressed;

  /// Button click with the button's bottom-left in global coordinates
  /// (for drop-down menus).
  final void Function(String id, Offset globalPosition)? onPressedAt;

  @override
  RenderReportToolbar createRenderObject(BuildContext context) =>
      RenderReportToolbar(
        items: items,
        status: status,
        theme: theme,
        onPressed: onPressed,
        onPressedAt: onPressedAt,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportToolbar renderObject,
  ) {
    renderObject
      ..items = items
      ..status = status
      ..theme = theme
      ..onPressed = onPressed
      ..onPressedAt = onPressedAt;
  }
}

/// RenderBox behind [ReportToolbar].
class RenderReportToolbar extends RenderBox implements MouseTrackerAnnotation {
  /// RenderReportToolbar API.
  RenderReportToolbar({
    required this._items,
    required this._status,
    required this._theme,
    this.onPressed,
    this.onPressedAt,
  });

  List<ReportToolbarItem> _items;
  String _status;
  OfficeTheme _theme;

  /// onPressed API.
  ValueChanged<String>? onPressed;

  /// onPressedAt API.
  void Function(String id, Offset globalPosition)? onPressedAt;

  /// Button size, logical pixels.
  static const double button = 28;

  /// Row height, logical pixels.
  static const double rowHeight = 34;

  static const double _gap = 2;
  static const double _sep = 10;

  final Map<String, TextPainter> _labels = <String, TextPainter>{};
  List<Rect> _rects = <Rect>[];
  int? _hover;
  int? _pressed;

  /// items API.
  List<ReportToolbarItem> get items => _items;

  set items(List<ReportToolbarItem> value) {
    _items = value;
    markNeedsLayout();
  }

  /// status API.
  String get status => _status;

  set status(String value) {
    if (value == _status) {
      return;
    }
    _status = value;
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

  @override
  void dispose() {
    for (final TextPainter tp in _labels.values) {
      tp.dispose();
    }
    _labels.clear();
    super.dispose();
  }

  TextPainter _text(String text, double fontSize, Color color) {
    final String key = '$text|$fontSize|${color.toARGB32()}';
    final TextPainter? hit = _labels[key];
    if (hit != null) {
      return hit;
    }
    if (_labels.length > 200) {
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
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: fontSize,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout();
    _labels[key] = tp;
    return tp;
  }

  double _buttonWidth(ReportToolbarItem item) {
    final String? label = item.label;
    if (label == null) {
      return button;
    }
    return button + _text(label, 11.5, _theme.chromeText).width + 4;
  }

  List<Rect> _place(double width) {
    final List<Rect> rects = <Rect>[];
    var x = 6.0;
    var y = (rowHeight - button) / 2;
    for (final ReportToolbarItem item in _items) {
      final double w = _buttonWidth(item);
      if (item.separatorBefore && x > 6) {
        x += _sep;
      }
      if (x + w > width - 6 && x > 6) {
        x = 6;
        y += rowHeight;
      }
      rects.add(Rect.fromLTWH(x, y, w, button));
      x += w + _gap;
    }
    return rects;
  }

  double _heightFor(double width) {
    if (!width.isFinite) {
      return rowHeight;
    }
    final List<Rect> rects = _place(width);
    final double bottom = rects.isEmpty
        ? rowHeight
        : rects.last.bottom + (rowHeight - button) / 2;
    return math.max(rowHeight, bottom);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final double w = constraints.hasBoundedWidth ? constraints.maxWidth : 1200;
    return constraints.constrain(Size(w, _heightFor(w)));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    _rects = _place(size.width);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  /// Local rect of the button with [id] after layout, or null.
  Rect? rectOf(String id) {
    for (int i = 0; i < _items.length && i < _rects.length; i++) {
      if (_items[i].id == id) {
        return _rects[i];
      }
    }
    return null;
  }

  int? _indexAt(Offset p) {
    for (int i = 0; i < _rects.length; i++) {
      if (_rects[i].contains(p)) {
        return i;
      }
    }
    return null;
  }

  @override
  MouseCursor get cursor {
    final int? i = _hover;
    return i != null && i < _items.length && _items[i].enabled
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => (_) {
    _hover = null;
    markNeedsPaint();
  };

  @override
  bool get validForMouseTracker => attached;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerHoverEvent) {
      final int? i = _indexAt(event.localPosition);
      if (i != _hover) {
        _hover = i;
        markNeedsPaint();
      }
      return;
    }
    if (event is PointerDownEvent && event.buttons == kPrimaryButton) {
      _pressed = _indexAt(event.localPosition);
      markNeedsPaint();
      return;
    }
    if (event is PointerUpEvent) {
      final int? i = _indexAt(event.localPosition);
      final int? pressed = _pressed;
      _pressed = null;
      markNeedsPaint();
      if (i != null && i == pressed && i < _items.length && _items[i].enabled) {
        final ReportToolbarItem item = _items[i];
        onPressed?.call(item.id);
        onPressedAt?.call(item.id, localToGlobal(_rects[i].bottomLeft));
      }
      return;
    }
    if (event is PointerCancelEvent) {
      _pressed = null;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _theme.chromeFill);
    for (int i = 0; i < _items.length && i < _rects.length; i++) {
      final ReportToolbarItem item = _items[i];
      final Rect r = _rects[i];
      if (item.separatorBefore && r.left > 6) {
        final double x = r.left - _sep / 2 - _gap / 2;
        canvas.drawLine(
          Offset(x, r.top + 5),
          Offset(x, r.bottom - 5),
          Paint()..color = _theme.pageBorder,
        );
      }
      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
      if (item.active) {
        canvas.drawRRect(
          rr,
          Paint()..color = _theme.selectionStroke.withValues(alpha: 0.18),
        );
      }
      if (item.enabled && (_hover == i || _pressed == i)) {
        canvas.drawRRect(
          rr,
          Paint()
            ..color = _theme.chromeText.withValues(
              alpha: _pressed == i ? 0.16 : 0.08,
            ),
        );
      }
      final Color ink = item.enabled
          ? (item.active ? _theme.selectionStroke : _theme.chromeText)
          : _theme.chromeText.withValues(alpha: 0.3);
      final Rect iconBox = Rect.fromCenter(
        center: Offset(r.left + button / 2, r.center.dy),
        width: 16,
        height: 16,
      );
      paintIcon(canvas, item.icon, iconBox, ink);
      final String? label = item.label;
      if (label != null) {
        final TextPainter tp = _text(label, 11.5, ink);
        tp.paint(
          canvas,
          Offset(r.left + button - 2, r.center.dy - tp.height / 2),
        );
      }
    }
    final int? hover = _hover;
    final String text = hover != null && hover < _items.length
        ? _items[hover].tooltip
        : _status;
    if (text.isNotEmpty && _rects.isNotEmpty) {
      final Rect last = _rects.last;
      final double free = size.width - last.right - 16;
      final TextPainter tp = _text(
        text,
        11,
        _theme.chromeText.withValues(alpha: 0.7),
      );
      if (tp.width <= free) {
        tp.paint(
          canvas,
          Offset(size.width - tp.width - 10, last.center.dy - tp.height / 2),
        );
      }
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = _theme.pageBorder,
    );
    canvas.restore();
  }

  /// Draws [icon] inside the 16×16 [box].
  static void paintIcon(
    Canvas canvas,
    ReportToolbarIcon icon,
    Rect box,
    Color color,
  ) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = color;
    final double l = box.left;
    final double t = box.top;
    Offset p(double x, double y) => Offset(l + x, t + y);
    void bar(double x, double y, double w, double h) =>
        canvas.drawRect(Rect.fromLTWH(l + x, t + y, w, h), fill);
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(p(x1, y1), p(x2, y2), stroke);
    switch (icon) {
      case ReportToolbarIcon.select:
        canvas.drawPath(
          Path()
            ..moveTo(l + 3, t + 1)
            ..lineTo(l + 3, t + 14)
            ..lineTo(l + 6.5, t + 10.5)
            ..lineTo(l + 9, t + 15)
            ..lineTo(l + 11, t + 14)
            ..lineTo(l + 8.5, t + 9.5)
            ..lineTo(l + 13, t + 9.5)
            ..close(),
          fill,
        );
      case ReportToolbarIcon.text:
        line(3, 3, 13, 3);
        line(8, 3, 8, 14);
        line(5.5, 14, 10.5, 14);
      case ReportToolbarIcon.image:
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 2.5, 13, 11), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(l + 2, t + 13)
            ..lineTo(l + 6, t + 8)
            ..lineTo(l + 9, t + 11)
            ..lineTo(l + 11, t + 9)
            ..lineTo(l + 14, t + 13)
            ..close(),
          fill,
        );
        canvas.drawCircle(p(11, 5.5), 1.3, fill);
      case ReportToolbarIcon.table:
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 2.5, 13, 11), stroke);
        bar(1.5, 2.5, 13, 3);
        line(1.5, 9, 14.5, 9);
        line(6, 5.5, 6, 13.5);
        line(10.5, 5.5, 10.5, 13.5);
      case ReportToolbarIcon.barcode:
        for (final (double x, double w) in <(double, double)>[
          (1.5, 1),
          (3.5, 2),
          (6.5, 1),
          (8.5, 1),
          (10.5, 2),
          (13.5, 1),
        ]) {
          bar(x, 2, w, 12);
        }
      case ReportToolbarIcon.qr:
        for (final Offset o in <Offset>[p(1, 1), p(9, 1), p(1, 9)]) {
          canvas.drawRect(
            Rect.fromLTWH(o.dx + 0.7, o.dy + 0.7, 4.6, 4.6),
            stroke,
          );
          canvas.drawRect(Rect.fromLTWH(o.dx + 2, o.dy + 2, 2, 2), fill);
        }
        bar(10, 10, 2, 2);
        bar(13, 13, 2, 2);
        bar(13, 9, 2, 2);
        bar(9, 13, 2, 2);
      case ReportToolbarIcon.line:
        line(2, 14, 14, 2);
      case ReportToolbarIcon.rectangle:
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 3.5, 13, 9), stroke);
      case ReportToolbarIcon.ellipse:
        canvas.drawOval(Rect.fromLTWH(l + 1.5, t + 3, 13, 10), stroke);
      case ReportToolbarIcon.chart:
        line(1.5, 14.5, 14.5, 14.5);
        bar(2.5, 8, 3, 6);
        bar(6.5, 3, 3, 11);
        bar(10.5, 6, 3, 8);
      case ReportToolbarIcon.map:
        final Path land = Path()
          ..moveTo(l + 2.5, t + 6)
          ..lineTo(l + 7, t + 2.5)
          ..lineTo(l + 13.5, t + 5.5)
          ..lineTo(l + 12, t + 13)
          ..lineTo(l + 4.5, t + 14)
          ..close();
        canvas.drawPath(land, stroke);
      case ReportToolbarIcon.pageNumber:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 3.5, t + 1.5, 9, 13),
            const Radius.circular(1),
          ),
          stroke,
        );
        line(5.5, 5, 10.5, 5);
        line(5.5, 8, 10.5, 8);
        line(5.5, 11, 8.5, 11);
      case ReportToolbarIcon.pages:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 2, t + 3.5, 8, 10),
            const Radius.circular(1),
          ),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 6, t + 2, 8, 10),
            const Radius.circular(1),
          ),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 6, t + 2, 8, 10),
            const Radius.circular(1),
          ),
          stroke,
        );
      case ReportToolbarIcon.date:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 2, t + 2.5, 12, 11),
            const Radius.circular(1.5),
          ),
          stroke,
        );
        canvas.drawRect(Rect.fromLTWH(l + 2, t + 2.5, 12, 3.5), fill);
        bar(4.5, 8, 2, 2);
        bar(8, 8, 2, 2);
        bar(4.5, 11, 2, 2);
      case ReportToolbarIcon.reportName:
        line(2, 4, 14, 4);
        line(2, 8, 11, 8);
        line(2, 11.5, 13, 11.5);
      case ReportToolbarIcon.rowNumber:
        line(2, 4, 5, 4);
        line(7, 4, 14, 4);
        line(2, 8, 5, 8);
        line(7, 8, 14, 8);
        line(2, 12, 5, 12);
        line(7, 12, 14, 12);
      case ReportToolbarIcon.total:
        line(12, 3, 3.5, 3);
        line(3.5, 3, 8.5, 8);
        line(3.5, 13, 8.5, 8);
        line(12, 13, 3.5, 13);
      case ReportToolbarIcon.rounded:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 1.5, t + 3.5, 13, 9),
            const Radius.circular(3),
          ),
          stroke,
        );
      case ReportToolbarIcon.signature:
        canvas.drawPath(
          Path()
            ..moveTo(l + 1, t + 9)
            ..cubicTo(l + 4, t + 3, l + 7, t + 13, l + 10, t + 7)
            ..cubicTo(l + 12, t + 4, l + 13, t + 8, l + 15, t + 8),
          stroke,
        );
        line(1, 13, 15, 13);
      case ReportToolbarIcon.templates:
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 1.5, 9, 11), stroke);
        canvas.drawRect(
          Rect.fromLTWH(l + 5, t + 4, 9.5, 11),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.drawRect(Rect.fromLTWH(l + 5, t + 4, 9.5, 11), stroke);
        line(7, 7, 12.5, 7);
        line(7, 9.5, 12.5, 9.5);
        line(7, 12, 10.5, 12);
      case ReportToolbarIcon.variables:
        canvas.drawPath(
          Path()
            ..moveTo(l + 4.5, t + 2)
            ..quadraticBezierTo(l + 2.5, t + 2, l + 2.5, t + 4.5)
            ..lineTo(l + 2.5, t + 6.5)
            ..quadraticBezierTo(l + 2.5, t + 8, l + 1, t + 8)
            ..quadraticBezierTo(l + 2.5, t + 8, l + 2.5, t + 9.5)
            ..lineTo(l + 2.5, t + 11.5)
            ..quadraticBezierTo(l + 2.5, t + 14, l + 4.5, t + 14)
            ..moveTo(l + 11.5, t + 2)
            ..quadraticBezierTo(l + 13.5, t + 2, l + 13.5, t + 4.5)
            ..lineTo(l + 13.5, t + 6.5)
            ..quadraticBezierTo(l + 13.5, t + 8, l + 15, t + 8)
            ..quadraticBezierTo(l + 13.5, t + 8, l + 13.5, t + 9.5)
            ..lineTo(l + 13.5, t + 11.5)
            ..quadraticBezierTo(l + 13.5, t + 14, l + 11.5, t + 14),
          stroke,
        );
        line(6, 5.5, 10, 10.5);
        line(10, 5.5, 6, 10.5);
      case ReportToolbarIcon.undo:
      case ReportToolbarIcon.redo:
        final bool undo = icon == ReportToolbarIcon.undo;
        canvas.save();
        if (!undo) {
          canvas.translate(l * 2 + 16, 0);
          canvas.scale(-1, 1);
        }
        canvas.drawPath(
          Path()
            ..moveTo(l + 3, t + 7)
            ..lineTo(l + 10, t + 7)
            ..quadraticBezierTo(l + 14, t + 7, l + 14, t + 10.5)
            ..quadraticBezierTo(l + 14, t + 14, l + 10, t + 14)
            ..lineTo(l + 7, t + 14),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(l + 6, t + 3.5)
            ..lineTo(l + 2.5, t + 7)
            ..lineTo(l + 6, t + 10.5),
          stroke,
        );
        canvas.restore();
      case ReportToolbarIcon.delete:
        line(2.5, 4, 13.5, 4);
        line(6, 4, 6.5, 2);
        line(10, 4, 9.5, 2);
        line(6.5, 2, 9.5, 2);
        canvas.drawPath(
          Path()
            ..moveTo(l + 4, t + 4)
            ..lineTo(l + 5, t + 14.5)
            ..lineTo(l + 11, t + 14.5)
            ..lineTo(l + 12, t + 4),
          stroke,
        );
        line(8, 6.5, 8, 12.5);
      case ReportToolbarIcon.duplicate:
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 1.5, 9, 9), stroke);
        canvas.drawRect(Rect.fromLTWH(l + 5.5, t + 5.5, 9, 9), stroke);
      case ReportToolbarIcon.alignLeft:
        line(1.5, 1, 1.5, 15);
        bar(3, 3, 10, 3.5);
        bar(3, 9.5, 6, 3.5);
      case ReportToolbarIcon.alignCenter:
        line(8, 1, 8, 15);
        bar(2, 3, 12, 3.5);
        bar(4.5, 9.5, 7, 3.5);
      case ReportToolbarIcon.alignRight:
        line(14.5, 1, 14.5, 15);
        bar(3, 3, 10, 3.5);
        bar(7, 9.5, 6, 3.5);
      case ReportToolbarIcon.alignTop:
        line(1, 1.5, 15, 1.5);
        bar(3, 3, 3.5, 10);
        bar(9.5, 3, 3.5, 6);
      case ReportToolbarIcon.alignMiddle:
        line(1, 8, 15, 8);
        bar(3, 2, 3.5, 12);
        bar(9.5, 4.5, 3.5, 7);
      case ReportToolbarIcon.alignBottom:
        line(1, 14.5, 15, 14.5);
        bar(3, 3, 3.5, 10);
        bar(9.5, 7, 3.5, 6);
      case ReportToolbarIcon.distributeX:
        line(1.5, 2, 1.5, 14);
        line(14.5, 2, 14.5, 14);
        bar(6, 4, 4, 8);
      case ReportToolbarIcon.distributeY:
        line(2, 1.5, 14, 1.5);
        line(2, 14.5, 14, 14.5);
        bar(4, 6, 8, 4);
      case ReportToolbarIcon.sameWidth:
        bar(2, 2.5, 12, 3);
        bar(2, 10.5, 12, 3);
        line(2, 8, 14, 8);
      case ReportToolbarIcon.sameHeight:
        bar(2.5, 2, 3, 12);
        bar(10.5, 2, 3, 12);
        line(8, 2, 8, 14);
      case ReportToolbarIcon.front:
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 1.5, 8, 8), stroke);
        bar(6, 6, 8.5, 8.5);
      case ReportToolbarIcon.back:
        bar(1.5, 1.5, 8, 8);
        canvas.drawRect(
          Rect.fromLTWH(l + 6, t + 6, 8.5, 8.5),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        canvas.drawRect(Rect.fromLTWH(l + 6, t + 6, 8.5, 8.5), stroke);
      case ReportToolbarIcon.zoomIn:
      case ReportToolbarIcon.zoomOut:
        canvas.drawCircle(p(6.5, 6.5), 5, stroke);
        line(10.2, 10.2, 14.5, 14.5);
        line(4, 6.5, 9, 6.5);
        if (icon == ReportToolbarIcon.zoomIn) {
          line(6.5, 4, 6.5, 9);
        }
      case ReportToolbarIcon.fitWidth:
        line(1.5, 8, 14.5, 8);
        canvas.drawPath(
          Path()
            ..moveTo(l + 4.5, t + 5)
            ..lineTo(l + 1.5, t + 8)
            ..lineTo(l + 4.5, t + 11)
            ..moveTo(l + 11.5, t + 5)
            ..lineTo(l + 14.5, t + 8)
            ..lineTo(l + 11.5, t + 11),
          stroke,
        );
        line(1, 2, 1, 14);
        line(15, 2, 15, 14);
      case ReportToolbarIcon.grid:
        for (final double v in <double>[2, 6, 10, 14]) {
          line(v, 2, v, 14);
          line(2, v, 14, v);
        }
      case ReportToolbarIcon.preview:
        canvas.drawPath(
          Path()
            ..moveTo(l + 1, t + 8)
            ..quadraticBezierTo(l + 8, t + 0, l + 15, t + 8)
            ..quadraticBezierTo(l + 8, t + 16, l + 1, t + 8)
            ..close(),
          stroke,
        );
        canvas.drawCircle(p(8, 8), 2.4, fill);
      case ReportToolbarIcon.design:
        canvas.drawPath(
          Path()
            ..moveTo(l + 2, t + 14)
            ..lineTo(l + 3, t + 10.5)
            ..lineTo(l + 11, t + 2.5)
            ..lineTo(l + 13.5, t + 5)
            ..lineTo(l + 5.5, t + 13)
            ..close(),
          stroke,
        );
        line(9.5, 4, 12, 6.5);
      case ReportToolbarIcon.export:
        line(8, 2, 8, 11);
        canvas.drawPath(
          Path()
            ..moveTo(l + 4.5, t + 7.5)
            ..lineTo(l + 8, t + 11)
            ..lineTo(l + 11.5, t + 7.5),
          stroke,
        );
        line(2.5, 14, 13.5, 14);
      case ReportToolbarIcon.print:
        canvas.drawPath(
          Path()
            ..moveTo(l + 4.5, t + 5.5)
            ..lineTo(l + 4.5, t + 1.5)
            ..lineTo(l + 11.5, t + 1.5)
            ..lineTo(l + 11.5, t + 5.5),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(l + 1.5, t + 5.5, 13, 6),
            const Radius.circular(1.5),
          ),
          stroke,
        );
        canvas.drawRect(Rect.fromLTWH(l + 4.5, t + 9.5, 7, 5), stroke);
        canvas.drawCircle(p(12, 7.8), 0.9, fill);
      case ReportToolbarIcon.band:
        bar(1.5, 2, 13, 2.5);
        canvas.drawRect(Rect.fromLTWH(l + 1.5, t + 5.5, 13, 3.5), stroke);
        bar(1.5, 10.5, 13, 2.5);
        line(11.5, 12.5, 11.5, 15.5);
        line(10, 14, 13, 14);
      case ReportToolbarIcon.font:
        canvas.drawPath(
          Path()
            ..moveTo(l + 1, t + 14)
            ..lineTo(l + 5.5, t + 2)
            ..lineTo(l + 10, t + 14),
          stroke,
        );
        line(2.8, 10, 8.2, 10);
        canvas.drawCircle(p(12.5, 11.5), 2.3, stroke);
        line(14.8, 9, 14.8, 14);
      case ReportToolbarIcon.data:
        canvas.drawOval(Rect.fromLTWH(l + 2.5, t + 1.5, 11, 4), stroke);
        line(2.5, 3.5, 2.5, 12.5);
        line(13.5, 3.5, 13.5, 12.5);
        for (final double y in <double>[8, 12.5]) {
          canvas.drawArc(
            Rect.fromLTWH(l + 2.5, t + y - 2, 11, 4),
            0,
            math.pi,
            false,
            stroke,
          );
        }
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..textDirection = TextDirection.ltr
      ..label = 'Report designer toolbar';
  }
}
