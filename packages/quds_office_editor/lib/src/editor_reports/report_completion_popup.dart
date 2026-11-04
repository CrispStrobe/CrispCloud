import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:quds_office_engine/quds_reports.dart';

import '../embed/office_theme.dart';

/// Painted suggestion list for `{{ }}` completions, shared by the design
/// canvas and the inspector. Coordinates are the host's local pixels.
class ReportCompletionPopup {
  /// Row height, logical pixels.
  static const double rowHeight = 22;

  /// Rows visible before the list scrolls.
  static const int maxRows = 8;

  /// Preferred width, logical pixels.
  static const double width = 340;

  static const double _hint = 18;

  final Map<String, TextPainter> _cache = <String, TextPainter>{};

  /// Popup rect below [caretBottom] (above [caretTop] when it does not fit),
  /// kept inside [bounds].
  static Rect place(
    Offset caretTop,
    Offset caretBottom,
    Size bounds,
    int count,
  ) {
    final double w = math.min(width, bounds.width - 8);
    final double h = math.min(count, maxRows) * rowHeight + _hint + 4;
    final double left = caretBottom.dx.clamp(
      4,
      math.max(4, bounds.width - w - 4),
    );
    var top = caretBottom.dy + 4;
    if (top + h > bounds.height - 4 && caretTop.dy - h - 4 >= 4) {
      top = caretTop.dy - h - 4;
    }
    return Rect.fromLTWH(left.toDouble(), top, w, h);
  }

  static int _first(int count, int selected) =>
      count <= maxRows ? 0 : (selected - maxRows + 1).clamp(0, count - maxRows);

  /// Index of the row under [p], or null.
  static int? hitIndex(Rect rect, Offset p, int count, int selected) {
    if (!rect.contains(p)) {
      return null;
    }
    final int row = ((p.dy - rect.top - 2) / rowHeight).floor();
    final int visible = math.min(count, maxRows);
    if (row < 0 || row >= visible) {
      return null;
    }
    return _first(count, selected) + row;
  }

  static const Map<ReportCompletionKind, (String, Color)> _badges =
      <ReportCompletionKind, (String, Color)>{
        ReportCompletionKind.function: ('ƒ', Color(0xFF7B1FA2)),
        ReportCompletionKind.root: ('◆', Color(0xFF00838F)),
        ReportCompletionKind.field: ('▪', Color(0xFF1565C0)),
        ReportCompletionKind.dataset: ('≡', Color(0xFF2E7D32)),
        ReportCompletionKind.variable: ('V', Color(0xFFEF6C00)),
        ReportCompletionKind.keyword: ('K', Color(0xFF6D4C41)),
        ReportCompletionKind.format: ('#', Color(0xFFC62828)),
        ReportCompletionKind.currency: ('¤', Color(0xFF558B2F)),
      };

  /// Paints [result] in [rect] with row [selected] highlighted.
  void paint(
    Canvas canvas,
    Rect rect,
    ReportCompletionResult result,
    int selected,
    OfficeTheme theme,
  ) {
    final List<ReportCompletionItem> items = result.items;
    final bool dark = theme.chromeFill.computeLuminance() < 0.4;
    final Color fill = dark ? const Color(0xFF2B2D31) : const Color(0xFFFFFFFF);
    final Color ink = dark ? const Color(0xFFECEFF4) : const Color(0xFF1F2937);
    final Color muted = dark
        ? const Color(0xFFA0A7B4)
        : const Color(0xFF6B7280);
    final RRect rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(
      rr.shift(const Offset(0, 2)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(rr, Paint()..color = fill);
    canvas.save();
    canvas.clipRRect(rr);
    final int first = _first(items.length, selected);
    final int visible = math.min(items.length, maxRows);
    for (int r = 0; r < visible; r++) {
      final int i = first + r;
      final ReportCompletionItem it = items[i];
      final Rect row = Rect.fromLTWH(
        rect.left,
        rect.top + 2 + r * rowHeight,
        rect.width,
        rowHeight,
      );
      final bool on = i == selected;
      if (on) {
        canvas.drawRect(
          row.deflate(1),
          Paint()..color = theme.selectionStroke.withValues(alpha: 0.18),
        );
      }
      final (String glyph, Color badge) = _badges[it.kind]!;
      final Rect b = Rect.fromLTWH(row.left + 6, row.center.dy - 7, 14, 14);
      canvas.drawRRect(
        RRect.fromRectAndRadius(b, const Radius.circular(3)),
        Paint()..color = badge.withValues(alpha: dark ? 0.35 : 0.14),
      );
      final TextPainter g = _label(glyph, 9.5, badge, 14, bold: true);
      g.paint(
        canvas,
        Offset(b.center.dx - g.width / 2, b.center.dy - g.height / 2),
      );
      final double textLeft = b.right + 6;
      final double avail = row.right - 8 - textLeft;
      final TextPainter detail = _label(it.detail, 10.5, muted, avail * 0.45);
      final TextPainter label = _label(
        it.label,
        12,
        ink,
        avail - (it.detail.isEmpty ? 0 : detail.width + 10),
        bold: on,
      );
      label.paint(canvas, Offset(textLeft, row.center.dy - label.height / 2));
      if (it.detail.isNotEmpty) {
        detail.paint(
          canvas,
          Offset(
            row.right - 8 - detail.width,
            row.center.dy - detail.height / 2,
          ),
        );
      }
    }
    final double hintTop = rect.top + 2 + visible * rowHeight;
    canvas.drawLine(
      Offset(rect.left, hintTop),
      Offset(rect.right, hintTop),
      Paint()..color = muted.withValues(alpha: 0.3),
    );
    final String count = items.length > maxRows
        ? '${selected + 1}/${items.length}  ·  '
        : '';
    final TextPainter hint = _label(
      '$count↑↓ choose  ·  Enter/Tab insert  ·  Esc close  ·  Ctrl+Space',
      9.5,
      muted,
      rect.width - 12,
    );
    hint.paint(
      canvas,
      Offset(rect.left + 8, hintTop + (_hint + 2 - hint.height) / 2),
    );
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..color = muted.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke,
    );
  }

  TextPainter _label(
    String text,
    double size,
    Color color,
    double maxWidth, {
    bool bold = false,
  }) {
    final double w = maxWidth < 8 ? 8 : maxWidth;
    final String key = '$text|$size|${color.toARGB32()}|$w|$bold';
    final TextPainter? hit = _cache[key];
    if (hit != null) {
      return hit;
    }
    if (_cache.length > 400) {
      dispose();
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Liberation Sans',
          fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: w);
    _cache[key] = tp;
    return tp;
  }

  /// Releases cached painters.
  void dispose() {
    for (final TextPainter tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }
}
