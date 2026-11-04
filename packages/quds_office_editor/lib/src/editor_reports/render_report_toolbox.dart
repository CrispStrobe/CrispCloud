import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../embed/office_theme.dart';
import 'render_report_toolbar.dart';
import 'report_designer_controller.dart';

/// One insert tool in the side panel.
@immutable
class ReportToolboxEntry {
  /// ReportToolboxEntry API.
  const ReportToolboxEntry({
    required this.tool,
    required this.icon,
    required this.title,
    required this.description,
    this.gapBefore = false,
  });

  /// Tool the canvas uses after a click.
  final ReportDesignTool tool;

  /// Small glyph and the subject of the hover drawing.
  final ReportToolbarIcon icon;

  /// Short name, authored in English.
  final String title;

  /// One sentence on what the tool places, authored in English.
  final String description;

  /// Start a new group above this tool.
  final bool gapBefore;
}

/// The button currently under the pointer.
@immutable
class ReportToolboxHover {
  /// ReportToolboxHover API.
  const ReportToolboxHover({
    required this.title,
    required this.description,
    required this.icon,
    required this.button,
  });

  /// English title.
  final String title;

  /// English description.
  final String description;

  /// icon API.
  final ReportToolbarIcon icon;

  /// Button rect in the toolbox's local coordinates.
  final Rect button;

  @override
  bool operator ==(Object other) =>
      other is ReportToolboxHover &&
      other.title == title &&
      other.icon == icon &&
      other.button == button;

  @override
  int get hashCode => Object.hash(title, icon, button);
}

/// Vertical insert panel. Hover is reported so the designer can paint a
/// card beside the panel; the card is wider than this box.
class ReportToolbox extends LeafRenderObjectWidget {
  /// ReportToolbox API.
  const ReportToolbox({
    super.key,
    required this.entries,
    required this.heading,
    required this.active,
    this.enabled = true,
    this.theme = OfficeTheme.light,
    this.onPressed,
    this.onHover,
  });

  /// Tools, top to bottom, two per row.
  final List<ReportToolboxEntry> entries;

  /// Panel title, already translated.
  final String heading;

  /// Tool that is armed.
  final ReportDesignTool active;

  /// enabled API.
  final bool enabled;

  /// theme API.
  final OfficeTheme theme;

  /// onPressed API.
  final ValueChanged<ReportDesignTool>? onPressed;

  /// The entry under the pointer, or null when the pointer leaves.
  final ValueChanged<ReportToolboxHover?>? onHover;

  /// Panel width, logical pixels.
  static const double width = 92;

  @override
  RenderReportToolbox createRenderObject(BuildContext context) =>
      RenderReportToolbox(
        entries: entries,
        heading: heading,
        active: active,
        enabled: enabled,
        theme: theme,
        onPressed: onPressed,
        onHover: onHover,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportToolbox renderObject,
  ) {
    renderObject
      ..entries = entries
      ..heading = heading
      ..active = active
      ..enabled = enabled
      ..theme = theme
      ..onPressed = onPressed
      ..onHover = onHover;
  }
}

/// RenderBox behind [ReportToolbox].
class RenderReportToolbox extends RenderBox implements MouseTrackerAnnotation {
  /// RenderReportToolbox API.
  RenderReportToolbox({
    required this._entries,
    required this._heading,
    required this._active,
    required this._enabled,
    required this._theme,
    this.onPressed,
    this.onHover,
  });

  static const double _cell = 32;
  static const double _gap = 6;
  static const double _pad = 8;
  static const double _headingHeight = 26;

  List<ReportToolboxEntry> _entries;
  String _heading;
  ReportDesignTool _active;
  bool _enabled;
  OfficeTheme _theme;

  /// onPressed API.
  ValueChanged<ReportDesignTool>? onPressed;

  /// onHover API.
  ValueChanged<ReportToolboxHover?>? onHover;

  final Map<String, TextPainter> _labels = <String, TextPainter>{};
  List<Rect> _rects = const <Rect>[];
  int? _hover;
  int? _pressed;

  /// entries API.
  List<ReportToolboxEntry> get entries => _entries;

  set entries(List<ReportToolboxEntry> value) {
    _entries = value;
    markNeedsLayout();
  }

  /// heading API.
  String get heading => _heading;

  set heading(String value) {
    if (value == _heading) {
      return;
    }
    _heading = value;
    markNeedsPaint();
  }

  /// active API.
  ReportDesignTool get active => _active;

  set active(ReportDesignTool value) {
    if (value == _active) {
      return;
    }
    _active = value;
    markNeedsPaint();
  }

  /// enabled API.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (value == _enabled) {
      return;
    }
    _enabled = value;
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

  TextPainter _text(
    String text,
    double size,
    Color color, {
    bool bold = false,
  }) {
    final String key = '$text|$size|${color.toARGB32()}|$bold';
    final TextPainter? hit = _labels[key];
    if (hit != null) {
      return hit;
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _theme.fontFamily ?? 'Liberation Sans',
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: size,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: ReportToolbox.width - 12);
    _labels[key] = tp;
    return tp;
  }

  List<Rect> _place(double height) {
    var cell = _cell;
    List<Rect> placed = _layout(cell);
    if (placed.isNotEmpty && placed.last.bottom + 8 > height) {
      final double used = placed.last.bottom + 8 - _headingHeight;
      final double room = height - _headingHeight - 8;
      if (used > 0 && room > 0) {
        cell = (cell * room / used).clamp(22.0, _cell);
        placed = _layout(cell);
      }
    }
    return placed;
  }

  List<Rect> _layout(double cell) {
    final List<Rect> rects = <Rect>[];
    final double group = cell < 28 ? 6 : 10;
    var col = 0;
    var y = _headingHeight;
    var x = _pad;
    for (final ReportToolboxEntry entry in _entries) {
      if (entry.gapBefore && rects.isNotEmpty) {
        if (col != 0) {
          col = 0;
          x = _pad;
          y += cell;
        }
        y += group;
      }
      rects.add(Rect.fromLTWH(x, y, cell, cell));
      col++;
      if (col == 2) {
        col = 0;
        x = _pad;
        y += cell + _gap;
      } else {
        x += cell + _gap;
      }
    }
    return rects;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final double w = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : ReportToolbox.width;
    final double h = constraints.hasBoundedHeight ? constraints.maxHeight : 640;
    return constraints.constrain(Size(w, h));
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
    _rects = _place(size.height);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  /// Local rect of `tool.<name>` after layout, or null.
  Rect? rectOf(String id) {
    for (int i = 0; i < _entries.length && i < _rects.length; i++) {
      if ('tool.${_entries[i].tool.name}' == id) {
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

  void _setHover(int? i) {
    if (i == _hover) {
      return;
    }
    _hover = i;
    markNeedsPaint();
    if (i == null || i >= _entries.length || i >= _rects.length) {
      onHover?.call(null);
      return;
    }
    final ReportToolboxEntry entry = _entries[i];
    onHover?.call(
      ReportToolboxHover(
        title: entry.title,
        description: entry.description,
        icon: entry.icon,
        button: _rects[i],
      ),
    );
  }

  @override
  MouseCursor get cursor {
    final int? i = _hover;
    return _enabled && i != null
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit =>
      (_) => _setHover(null);

  @override
  bool get validForMouseTracker => attached;

  @override
  void handleEvent(PointerEvent event, covariant BoxHitTestEntry entry) {
    if (event is PointerHoverEvent) {
      _setHover(_indexAt(event.localPosition));
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
      if (_enabled && i != null && i == pressed && i < _entries.length) {
        onPressed?.call(_entries[i].tool);
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
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()..color = _theme.pageBorder,
    );
    final TextPainter title = _text(
      _heading,
      11,
      _theme.headerText,
      bold: true,
    );
    title.paint(canvas, Offset(_pad, (_headingHeight - title.height) / 2));
    for (int i = 0; i < _entries.length && i < _rects.length; i++) {
      final ReportToolboxEntry entry = _entries[i];
      final Rect r = _rects[i];
      if (entry.gapBefore && i > 0) {
        canvas.drawLine(
          Offset(_pad, r.top - 5),
          Offset(size.width - _pad, r.top - 5),
          Paint()..color = _theme.pageBorder.withValues(alpha: 0.7),
        );
      }
      final bool on = _enabled && entry.tool == _active;
      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      if (on) {
        canvas.drawRRect(
          rr,
          Paint()..color = _theme.selectionStroke.withValues(alpha: 0.16),
        );
      } else if (_hover == i || _pressed == i) {
        canvas.drawRRect(
          rr,
          Paint()
            ..color = _theme.chromeText.withValues(
              alpha: _pressed == i ? 0.14 : 0.07,
            ),
        );
      }
      final Color ink = !_enabled
          ? _theme.chromeText.withValues(alpha: 0.35)
          : (on ? _theme.selectionStroke : _theme.chromeText);
      RenderReportToolbar.paintIcon(
        canvas,
        entry.icon,
        Rect.fromCenter(center: r.center, width: 16, height: 16),
        ink,
      );
    }
    canvas.restore();
  }
}

/// Hover card: name, a drawing of what the tool inserts, and a sentence.
class ReportToolboxCard extends LeafRenderObjectWidget {
  /// ReportToolboxCard API.
  const ReportToolboxCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.theme = OfficeTheme.light,
    this.direction = TextDirection.ltr,
  });

  /// Translated name.
  final String title;

  /// Translated explanation.
  final String description;

  /// Which drawing to paint.
  final ReportToolbarIcon icon;

  /// theme API.
  final OfficeTheme theme;

  /// direction API.
  final TextDirection direction;

  @override
  RenderReportToolboxCard createRenderObject(BuildContext context) =>
      RenderReportToolboxCard(
        title: title,
        description: description,
        icon: icon,
        theme: theme,
        direction: direction,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReportToolboxCard renderObject,
  ) {
    renderObject
      ..title = title
      ..description = description
      ..icon = icon
      ..theme = theme
      ..direction = direction;
  }
}

/// RenderBox behind [ReportToolboxCard].
class RenderReportToolboxCard extends RenderBox {
  /// RenderReportToolboxCard API.
  RenderReportToolboxCard({
    required this._title,
    required this._description,
    required this._icon,
    required this._theme,
    required this._direction,
  });

  String _title;
  String _description;
  ReportToolbarIcon _icon;
  OfficeTheme _theme;
  TextDirection _direction;
  TextPainter? _titlePainter;
  TextPainter? _bodyPainter;

  /// title API.
  String get title => _title;

  set title(String value) {
    if (value == _title) {
      return;
    }
    _title = value;
    _dropText();
    markNeedsPaint();
  }

  /// description API.
  String get description => _description;

  set description(String value) {
    if (value == _description) {
      return;
    }
    _description = value;
    _dropText();
    markNeedsPaint();
  }

  /// icon API.
  ReportToolbarIcon get icon => _icon;

  set icon(ReportToolbarIcon value) {
    if (value == _icon) {
      return;
    }
    _icon = value;
    markNeedsPaint();
  }

  /// theme API.
  OfficeTheme get theme => _theme;

  set theme(OfficeTheme value) {
    if (identical(value, _theme)) {
      return;
    }
    _theme = value;
    _dropText();
    markNeedsPaint();
  }

  /// direction API.
  TextDirection get direction => _direction;

  set direction(TextDirection value) {
    if (value == _direction) {
      return;
    }
    _direction = value;
    _dropText();
    markNeedsPaint();
  }

  void _dropText() {
    _titlePainter?.dispose();
    _bodyPainter?.dispose();
    _titlePainter = null;
    _bodyPainter = null;
  }

  @override
  void dispose() {
    _dropText();
    super.dispose();
  }

  TextPainter _line(String text, double size, Color color, FontWeight weight) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _theme.fontFamily ?? 'Liberation Sans',
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.25,
        ),
      ),
      textDirection: _direction,
      textAlign: _direction == TextDirection.rtl
          ? TextAlign.right
          : TextAlign.left,
      maxLines: size > 12 ? 1 : 3,
      ellipsis: '…',
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(const Size(252, 172));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final RRect card = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.drawRRect(
      card.shift(const Offset(0, 2)),
      Paint()..color = const Color(0x33000000),
    );
    canvas.drawRRect(card, Paint()..color = _theme.chromeFill);
    canvas.drawRRect(
      card,
      Paint()
        ..color = _theme.pageBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final Rect well = Rect.fromLTWH(10, 10, size.width - 20, 78);
    canvas.drawRRect(
      RRect.fromRectAndRadius(well, const Radius.circular(6)),
      Paint()..color = _theme.pageBackground,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(well, const Radius.circular(6)),
      Paint()
        ..color = _theme.pageBorder
        ..style = PaintingStyle.stroke,
    );
    _paintScene(canvas, well.deflate(8));
    _titlePainter ??= _line(_title, 13, _theme.chromeText, FontWeight.w600)
      ..layout(maxWidth: size.width - 20);
    _bodyPainter ??= _line(
      _description,
      11,
      _theme.chromeText.withValues(alpha: 0.78),
      FontWeight.w400,
    )..layout(maxWidth: size.width - 20);
    final double tx = _direction == TextDirection.rtl
        ? size.width - 10 - _titlePainter!.width
        : 10;
    _titlePainter!.paint(canvas, Offset(tx, 96));
    final double bx = _direction == TextDirection.rtl
        ? size.width - 10 - _bodyPainter!.width
        : 10;
    _bodyPainter!.paint(canvas, Offset(bx, 116));
    canvas.restore();
  }

  void _paintScene(Canvas canvas, Rect r) {
    final Color ink = _theme.chromeText;
    final Color accent = _theme.selectionStroke;
    final Paint stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = ink;
    final Paint accentFill = Paint()..color = accent;
    final Paint soft = Paint()..color = accent.withValues(alpha: 0.16);
    switch (_icon) {
      case ReportToolbarIcon.select:
        final Rect box = Rect.fromLTWH(
          r.left + 8,
          r.top + 10,
          r.width * 0.55,
          r.height - 22,
        );
        canvas.drawRect(box, soft);
        canvas.drawRect(box, stroke);
        final Paint handle = Paint()..color = accent;
        for (final Offset o in <Offset>[
          box.topLeft,
          box.topRight,
          box.bottomLeft,
          box.bottomRight,
        ]) {
          canvas.drawRect(
            Rect.fromCenter(center: o, width: 5, height: 5),
            handle,
          );
        }
        final Path cursor = Path()
          ..moveTo(box.right - 6, box.top + 8)
          ..lineTo(box.right - 6, box.top + 26)
          ..lineTo(box.right - 1, box.top + 20)
          ..lineTo(box.right + 6, box.top + 28)
          ..lineTo(box.right + 9, box.top + 25)
          ..lineTo(box.right + 2, box.top + 17)
          ..close();
        canvas.drawPath(cursor, accentFill);
      case ReportToolbarIcon.text:
        _lines(canvas, r, accent, ink);
      case ReportToolbarIcon.pageNumber:
        _sheet(canvas, r, stroke, soft);
        _glyph(canvas, '1', r.center, 22, accent);
      case ReportToolbarIcon.pages:
        _sheet(canvas, r.shift(const Offset(-10, 4)), stroke, soft);
        _sheet(
          canvas,
          r.shift(const Offset(10, -2)),
          stroke,
          Paint()..color = _theme.pageBackground,
        );
        _glyph(canvas, '2 / 5', r.center, 13, accent);
      case ReportToolbarIcon.date:
        final Rect cal = Rect.fromCenter(
          center: r.center,
          width: 54,
          height: 46,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cal, const Radius.circular(3)),
          stroke,
        );
        canvas.drawRect(
          Rect.fromLTWH(cal.left, cal.top, cal.width, 12),
          accentFill,
        );
        for (int row = 0; row < 2; row++) {
          for (int col = 0; col < 3; col++) {
            canvas.drawCircle(
              Offset(cal.left + 12 + col * 15, cal.top + 22 + row * 12),
              2.2,
              fill,
            );
          }
        }
      case ReportToolbarIcon.reportName:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left, r.top + 8, r.width, 18),
            const Radius.circular(3),
          ),
          soft,
        );
        canvas.drawLine(
          Offset(r.left + 8, r.top + 17),
          Offset(r.right - 28, r.top + 17),
          stroke..strokeWidth = 2.4,
        );
        canvas.drawLine(
          Offset(r.left + 8, r.top + 40),
          Offset(r.right - 8, r.top + 40),
          stroke..strokeWidth = 1.2,
        );
        canvas.drawLine(
          Offset(r.left + 8, r.top + 50),
          Offset(r.right - 40, r.top + 50),
          stroke,
        );
      case ReportToolbarIcon.rowNumber:
        for (int i = 0; i < 3; i++) {
          final double y = r.top + 8 + i * 16;
          canvas.drawRect(Rect.fromLTWH(r.left, y, 18, 12), soft);
          _glyph(canvas, '${i + 1}', Offset(r.left + 9, y + 6), 10, accent);
          canvas.drawLine(
            Offset(r.left + 26, y + 6),
            Offset(r.right - 8, y + 6),
            stroke..strokeWidth = 1.2,
          );
        }
      case ReportToolbarIcon.total:
        for (int i = 0; i < 3; i++) {
          canvas.drawLine(
            Offset(r.left + 6, r.top + 10 + i * 12),
            Offset(r.right - 46, r.top + 10 + i * 12),
            stroke..strokeWidth = 1.2,
          );
        }
        final Rect pill = Rect.fromLTWH(r.right - 40, r.bottom - 22, 34, 16);
        canvas.drawRRect(
          RRect.fromRectAndRadius(pill, const Radius.circular(3)),
          soft,
        );
        _glyph(canvas, '128', pill.center, 11, accent);
      case ReportToolbarIcon.signature:
        final Path wave = Path()
          ..moveTo(r.left + 16, r.center.dy)
          ..cubicTo(
            r.left + 36,
            r.top + 6,
            r.left + 52,
            r.bottom - 8,
            r.center.dx,
            r.center.dy - 2,
          )
          ..cubicTo(
            r.center.dx + 24,
            r.top + 8,
            r.right - 36,
            r.bottom - 6,
            r.right - 14,
            r.center.dy,
          );
        canvas.drawPath(wave, stroke..strokeWidth = 1.4);
        canvas.drawLine(
          Offset(r.left + 10, r.bottom - 8),
          Offset(r.right - 10, r.bottom - 8),
          stroke..strokeWidth = 1.1,
        );
      case ReportToolbarIcon.image:
        final Rect frame = Rect.fromCenter(
          center: r.center,
          width: r.width * 0.7,
          height: r.height - 8,
        );
        canvas.drawRect(frame, stroke..strokeWidth = 1.2);
        canvas.drawCircle(frame.center + const Offset(16, -8), 5, accentFill);
        final Path hill = Path()
          ..moveTo(frame.left, frame.bottom)
          ..lineTo(frame.left + frame.width * 0.4, frame.top + 16)
          ..lineTo(frame.right, frame.bottom)
          ..close();
        canvas.drawPath(hill, soft);
      case ReportToolbarIcon.table:
        final Rect grid = Rect.fromLTWH(
          r.left + 4,
          r.top + 4,
          r.width - 8,
          r.height - 8,
        );
        canvas.drawRect(
          Rect.fromLTWH(grid.left, grid.top, grid.width, 14),
          accentFill,
        );
        canvas.drawRect(grid, stroke..strokeWidth = 1);
        for (int i = 1; i < 3; i++) {
          final double x = grid.left + grid.width * i / 3;
          canvas.drawLine(Offset(x, grid.top), Offset(x, grid.bottom), stroke);
        }
        for (int i = 1; i < 3; i++) {
          final double y = grid.top + 14 + (grid.height - 14) * i / 3;
          canvas.drawLine(Offset(grid.left, y), Offset(grid.right, y), stroke);
        }
      case ReportToolbarIcon.barcode:
        var x = r.left + 18;
        const List<double> bars = <double>[2, 1, 3, 1, 2, 4, 1, 2, 3, 1, 2];
        for (int i = 0; i < bars.length; i++) {
          if (i.isEven) {
            canvas.drawRect(
              Rect.fromLTWH(x, r.top + 8, bars[i], r.height - 16),
              fill,
            );
          }
          x += bars[i] + 2;
        }
      case ReportToolbarIcon.qr:
        final Rect code = Rect.fromCenter(
          center: r.center,
          width: 42,
          height: 42,
        );
        canvas.drawRect(code, stroke..strokeWidth = 1.2);
        for (final Offset o in <Offset>[
          code.topLeft,
          code.topRight + const Offset(-12, 0),
          code.bottomLeft + const Offset(0, -12),
        ]) {
          canvas.drawRect(o & const Size(12, 12), stroke);
          canvas.drawRect(o + const Offset(3, 3) & const Size(6, 6), fill);
        }
        canvas.drawRect(
          code.center - const Offset(3, 3) & const Size(6, 6),
          fill,
        );
      case ReportToolbarIcon.line:
        canvas.drawLine(
          Offset(r.left + 8, r.center.dy),
          Offset(r.right - 8, r.center.dy),
          stroke..strokeWidth = 1.6,
        );
      case ReportToolbarIcon.rectangle:
        canvas.drawRect(
          Rect.fromCenter(
            center: r.center,
            width: r.width * 0.62,
            height: r.height - 16,
          ),
          soft,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: r.center,
            width: r.width * 0.62,
            height: r.height - 16,
          ),
          stroke..strokeWidth = 1.3,
        );
      case ReportToolbarIcon.rounded:
        final RRect box = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: r.center,
            width: r.width * 0.62,
            height: r.height - 16,
          ),
          const Radius.circular(10),
        );
        canvas.drawRRect(box, soft);
        canvas.drawRRect(box, stroke..strokeWidth = 1.3);
      case ReportToolbarIcon.ellipse:
        canvas.drawOval(
          Rect.fromCenter(center: r.center, width: 58, height: r.height - 12),
          soft,
        );
        canvas.drawOval(
          Rect.fromCenter(center: r.center, width: 58, height: r.height - 12),
          stroke..strokeWidth = 1.3,
        );
      case ReportToolbarIcon.chart:
        final double base = r.bottom - 8;
        final double left = r.left + 16;
        const List<double> heights = <double>[18, 34, 24, 42];
        for (int i = 0; i < heights.length; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left + i * 22, base - heights[i], 14, heights[i]),
              const Radius.circular(2),
            ),
            i == 3 ? accentFill : soft,
          );
        }
        canvas.drawLine(Offset(left, base), Offset(r.right - 12, base), stroke);
      case ReportToolbarIcon.map:
        final Path land = Path()
          ..moveTo(r.center.dx - 28, r.center.dy)
          ..lineTo(r.center.dx - 8, r.top + 6)
          ..lineTo(r.center.dx + 30, r.top + 14)
          ..lineTo(r.center.dx + 18, r.bottom - 8)
          ..lineTo(r.center.dx - 16, r.bottom - 6)
          ..close();
        canvas.drawPath(land, soft);
        canvas.drawPath(land, stroke..strokeWidth = 1.3);
      case ReportToolbarIcon.templates:
      case ReportToolbarIcon.variables:
      case ReportToolbarIcon.undo:
      case ReportToolbarIcon.redo:
      case ReportToolbarIcon.delete:
      case ReportToolbarIcon.duplicate:
      case ReportToolbarIcon.alignLeft:
      case ReportToolbarIcon.alignCenter:
      case ReportToolbarIcon.alignRight:
      case ReportToolbarIcon.alignTop:
      case ReportToolbarIcon.alignMiddle:
      case ReportToolbarIcon.alignBottom:
      case ReportToolbarIcon.sameWidth:
      case ReportToolbarIcon.sameHeight:
      case ReportToolbarIcon.distributeX:
      case ReportToolbarIcon.distributeY:
      case ReportToolbarIcon.front:
      case ReportToolbarIcon.back:
      case ReportToolbarIcon.zoomIn:
      case ReportToolbarIcon.zoomOut:
      case ReportToolbarIcon.fitWidth:
      case ReportToolbarIcon.grid:
      case ReportToolbarIcon.preview:
      case ReportToolbarIcon.design:
      case ReportToolbarIcon.export:
      case ReportToolbarIcon.print:
      case ReportToolbarIcon.band:
      case ReportToolbarIcon.font:
      case ReportToolbarIcon.data:
        RenderReportToolbar.paintIcon(
          canvas,
          _icon,
          Rect.fromCenter(center: r.center, width: 28, height: 28),
          ink,
        );
    }
  }

  void _sheet(Canvas canvas, Rect r, Paint stroke, Paint fill) {
    final Rect page = Rect.fromCenter(
      center: r.center,
      width: 36,
      height: math.min(52, r.height - 4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const Radius.circular(2)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const Radius.circular(2)),
      stroke,
    );
  }

  void _lines(Canvas canvas, Rect r, Color accent, Color ink) {
    final Paint bar = Paint()..color = ink.withValues(alpha: 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + 6, r.top + 6, 46, 8),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + 6, r.top + 22, r.width - 20, 6),
        const Radius.circular(2),
      ),
      bar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + 6, r.top + 34, r.width * 0.55, 6),
        const Radius.circular(2),
      ),
      bar,
    );
  }

  void _glyph(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
  ) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _theme.fontFamily ?? 'Liberation Sans',
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}
