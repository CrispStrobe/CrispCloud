import 'dart:ui';

import '../embed/office_theme.dart';

/// Vector chrome painted by the host RenderBoxes (not Material widgets).
class OfficeChrome {
  /// Thickness of the horizontal and vertical page rulers.
  static const double rulerSize = 24;

  /// paintRuler API.
  static void paintRuler(
    Canvas canvas,
    Size size, {
    required bool vertical,
    OfficeTheme theme = OfficeTheme.light,
  }) {
    final Paint paint = Paint()..color = theme.headerFill;
    final Rect bar = vertical
        ? Rect.fromLTWH(0, 0, rulerSize, size.height)
        : Rect.fromLTWH(0, 0, size.width, rulerSize);
    canvas.drawRect(bar, paint);
    final Paint tick = Paint()
      ..color = theme.headerText
      ..strokeWidth = 1;
    if (vertical) {
      for (double y = 0; y < size.height; y += 10) {
        canvas.drawLine(
          Offset(y % 50 == 0 ? 4 : 12, y),
          Offset(rulerSize, y),
          tick,
        );
      }
    } else {
      for (double x = 0; x < size.width; x += 10) {
        canvas.drawLine(
          Offset(x, x % 50 == 0 ? 4 : 12),
          Offset(x, rulerSize),
          tick,
        );
      }
    }
  }

  /// paintFormulaBar API.
  static void paintFormulaBar(
    Canvas canvas,
    Size size,
    String text, {
    OfficeTheme theme = OfficeTheme.light,
    String? fontFamily,
    bool rtl = false,
    String nameBox = '',
    List<(int start, int end, Color color)> highlights =
        const <(int, int, Color)>[],
  }) {
    const double nameW = 96;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 28),
      Paint()..color = theme.chromeFill,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 27, size.width, 1),
      Paint()..color = theme.gridLine,
    );
    canvas.drawRect(
      const Rect.fromLTWH(4, 4, nameW - 8, 20),
      Paint()..color = theme.pageBackground,
    );
    canvas.drawRect(
      const Rect.fromLTWH(4, 4, nameW - 8, 20),
      Paint()
        ..color = theme.gridLine
        ..style = PaintingStyle.stroke,
    );
    final ParagraphBuilder name = ParagraphBuilder(
      ParagraphStyle(fontSize: 12, fontFamily: fontFamily),
    )..addText(nameBox);
    final Paragraph nameParagraph = name.build()
      ..layout(const ParagraphConstraints(width: nameW - 16));
    canvas.drawParagraph(nameParagraph, const Offset(8, 6));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(nameW, 0, size.width - nameW, 28));
    canvas.translate(nameW, 0);
    final ParagraphBuilder b = ParagraphBuilder(
      ParagraphStyle(
        fontSize: 12,
        fontFamily: fontFamily,
        textAlign: rtl ? TextAlign.right : TextAlign.left,
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      ),
    );
    if (highlights.isEmpty) {
      b.pushStyle(TextStyle(color: theme.chromeText, fontSize: 12));
      b.addText(text);
    } else {
      var cursor = 0;
      for (final (int start, int end, Color color) in highlights) {
        final int from = start.clamp(0, text.length);
        final int to = end.clamp(from, text.length);
        if (from > cursor) {
          b.pushStyle(TextStyle(color: theme.chromeText, fontSize: 12));
          b.addText(text.substring(cursor, from));
          b.pop();
        }
        if (to > from) {
          b.pushStyle(TextStyle(color: color, fontSize: 12));
          b.addText(text.substring(from, to));
          b.pop();
        }
        cursor = to > cursor ? to : cursor;
      }
      if (cursor < text.length) {
        b.pushStyle(TextStyle(color: theme.chromeText, fontSize: 12));
        b.addText(text.substring(cursor));
        b.pop();
      }
    }
    final Paragraph p = b.build()
      ..layout(ParagraphConstraints(width: size.width - nameW - 16));
    canvas.drawParagraph(p, const Offset(8, 6));
    canvas.restore();
  }

  /// paintSheetHeader API.
  static void paintSheetHeader(
    Canvas canvas, {
    required Rect rect,
    required String label,
    required OfficeTheme theme,
    String? fontFamily,
    bool selected = false,
  }) {
    canvas.drawRect(
      rect,
      Paint()..color = selected ? theme.selectionFill : theme.headerFill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = theme.gridLine
        ..style = PaintingStyle.stroke,
    );
    final ParagraphBuilder b = ParagraphBuilder(
      ParagraphStyle(
        fontSize: 10,
        fontFamily: fontFamily,
        textAlign: TextAlign.center,
      ),
    );
    b.pushStyle(TextStyle(color: theme.headerText, fontSize: 10));
    b.addText(label);
    final Paragraph p = b.build()
      ..layout(ParagraphConstraints(width: rect.width));
    canvas.drawParagraph(p, Offset(rect.left, rect.top + 3));
  }
}
