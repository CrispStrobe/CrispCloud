import 'package:flutter/material.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Paints a laid-out Office Math box onto a Flutter [Canvas].
abstract final class PaintEquation {
  /// ink API.
  static const Color ink = Color(0xFF1F4E79);

  /// slot API.
  static const Color slot = Color(0xFFB4C7E7);

  /// slotFill API.
  static const Color slotFill = Color(0xFFE8F1FB);

  /// focus API.
  static const Color focus = Color(0xFF2B579A);

  /// paint API.
  static void paint(
    Canvas canvas,
    Rect box,
    LaidOutOmml omml, {
    int? focusedSlot,
    bool selected = false,
    bool caretVisible = false,
    int caretIndex = 0,
    OmmlSeq? root,
  }) {
    canvas.save();
    canvas.clipRect(box.inflate(1));
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = const Color(0xFFF7FBFF),
    );
    canvas.translate(box.left, box.top);

    if (selected) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, box.width, box.height),
        Paint()..color = const Color(0x142B579A),
      );
    }

    final Set<int> cells = root == null
        ? const <int>{}
        : OmmlEdit.cellIndexes(root);
    final LaidOutOmmlSlot? focusSlot = focusedSlot == null
        ? null
        : _slotByIndex(omml, focusedSlot);
    final Rect? focusRect = focusSlot == null
        ? null
        : _cellRect(omml, focusSlot, cells).inflate(1.2);
    if (focusRect != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(focusRect, const Radius.circular(2)),
        Paint()
          ..color = slotFill
          ..style = PaintingStyle.fill,
      );
    }
    if (selected && cells.isNotEmpty) {
      for (final LaidOutOmmlSlot slot in omml.slots) {
        if (!cells.contains(slot.slotIndex)) {
          continue;
        }
        final Rect cell = _cellRect(omml, slot, cells);
        if (cell.width >= omml.width * 0.88 &&
            cell.height >= omml.height * 0.8) {
          continue;
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(cell, const Radius.circular(2)),
          Paint()
            ..color = PaintEquation.slot
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9,
        );
      }
    }

    for (final LaidOutOmmlItem item in omml.items) {
      switch (item) {
        case LaidOutOmmlText():
          _text(canvas, item);
        case LaidOutOmmlRule():
          canvas.drawLine(
            Offset(item.x, item.y),
            Offset(item.x + item.width, item.y),
            Paint()
              ..color = ink
              ..strokeWidth = item.height.clamp(1.0, 2.2)
              ..strokeCap = StrokeCap.round,
          );
        case LaidOutOmmlStroke():
          _stroke(canvas, item);
        case LaidOutOmmlSlot():
          if (item.empty &&
              (focusedSlot == null || item.slotIndex != focusedSlot)) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(item.x, item.y, item.width, item.height),
                const Radius.circular(2),
              ),
              Paint()
                ..color = PaintEquation.slot
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1,
            );
          }
      }
    }

    if (focusRect != null && focusSlot != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(focusRect, const Radius.circular(2)),
        Paint()
          ..color = focus
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      if (caretVisible) {
        final double caretX = caretPosition(
          omml,
          focusSlot,
          caretIndex,
          cells,
          fallback: focusRect,
        );
        canvas.drawLine(
          Offset(caretX, focusRect.top + 1),
          Offset(caretX, focusRect.bottom - 1),
          Paint()
            ..color = focus
            ..strokeWidth = 1.4,
        );
      }
    }

    canvas.restore();

    if (selected) {
      canvas.drawRect(
        box.inflate(2),
        Paint()
          ..color = focus
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  /// hitSlot API.
  static int? hitSlot(LaidOutOmml omml, Offset local, {OmmlSeq? root}) {
    final Set<int> cells = root == null
        ? const <int>{}
        : OmmlEdit.cellIndexes(root);
    LaidOutOmmlSlot? best;
    var bestArea = double.infinity;
    for (final LaidOutOmmlSlot slot in omml.slots) {
      if (cells.isNotEmpty && !cells.contains(slot.slotIndex)) {
        continue;
      }
      final Rect r = _cellRect(omml, slot, cells).inflate(3);
      if (r.contains(local)) {
        final double area = slot.width * slot.height;
        if (area < bestArea) {
          bestArea = area;
          best = slot;
        }
      }
    }
    if (best != null) {
      return best.slotIndex;
    }
    var bestDist = double.infinity;
    for (final LaidOutOmmlSlot slot in omml.slots) {
      if (cells.isNotEmpty && !cells.contains(slot.slotIndex)) {
        continue;
      }
      final Rect r = _cellRect(omml, slot, cells);
      final double dist = _distanceToRect(local, r);
      if (dist < bestDist) {
        bestDist = dist;
        best = slot;
      }
    }
    return best?.slotIndex;
  }

  /// hitCaret API.
  static int hitCaret(
    LaidOutOmml omml,
    Offset local, {
    required int slotIndex,
    OmmlSeq? root,
  }) {
    final Set<int> cells = root == null
        ? const <int>{}
        : OmmlEdit.cellIndexes(root);
    final LaidOutOmmlSlot? slot = _slotByIndex(omml, slotIndex);
    if (slot == null) {
      return 0;
    }
    final List<LaidOutOmmlText> texts = _ownedTexts(omml, slot, cells);
    var index = 0;
    for (final LaidOutOmmlText text in texts) {
      for (int i = 0; i < text.text.length; i++) {
        final double mid =
            text.x + text.width * ((i + 0.5) / text.text.length.clamp(1, 1000));
        if (local.dx < mid) {
          return index;
        }
        index++;
      }
    }
    return index;
  }

  /// caretPosition API.
  static double caretPosition(
    LaidOutOmml omml,
    LaidOutOmmlSlot slot,
    int caretIndex,
    Set<int> cells, {
    required Rect fallback,
  }) {
    if (slot.empty) {
      return fallback.center.dx;
    }
    final List<LaidOutOmmlText> texts = _ownedTexts(omml, slot, cells);
    var remaining = caretIndex;
    for (final LaidOutOmmlText text in texts) {
      if (remaining <= 0) {
        return text.x;
      }
      if (remaining >= text.text.length) {
        remaining -= text.text.length;
        if (remaining == 0) {
          return text.x + text.width;
        }
        continue;
      }
      return text.x +
          text.width * (remaining / text.text.length.clamp(1, 1000));
    }
    return fallback.right - 1;
  }

  static List<LaidOutOmmlText> _ownedTexts(
    LaidOutOmml omml,
    LaidOutOmmlSlot slot,
    Set<int> cells,
  ) {
    final Rect raw = Rect.fromLTWH(slot.x, slot.y, slot.width, slot.height);
    final List<LaidOutOmmlText> out = <LaidOutOmmlText>[];
    for (final LaidOutOmmlText text
        in omml.items.whereType<LaidOutOmmlText>()) {
      final Offset center = Offset(
        text.x + text.width / 2,
        text.y + text.height / 2,
      );
      if (!raw.inflate(2).contains(center)) {
        continue;
      }
      var insideSmaller = false;
      for (final LaidOutOmmlSlot other in omml.slots) {
        if (other.slotIndex == slot.slotIndex) {
          continue;
        }
        if (cells.isNotEmpty && !cells.contains(other.slotIndex)) {
          continue;
        }
        final Rect otherRect = Rect.fromLTWH(
          other.x,
          other.y,
          other.width,
          other.height,
        );
        if (otherRect.width * otherRect.height < slot.width * slot.height &&
            otherRect.contains(center)) {
          insideSmaller = true;
          break;
        }
      }
      if (!insideSmaller) {
        out.add(text);
      }
    }
    out.sort((LaidOutOmmlText a, LaidOutOmmlText b) => a.x.compareTo(b.x));
    return out;
  }

  static LaidOutOmmlSlot? _slotByIndex(LaidOutOmml omml, int index) {
    for (final LaidOutOmmlSlot slot in omml.slots) {
      if (slot.slotIndex == index) {
        return slot;
      }
    }
    return null;
  }

  static Rect _cellRect(
    LaidOutOmml omml,
    LaidOutOmmlSlot slot,
    Set<int> cells,
  ) {
    final Rect raw = Rect.fromLTWH(slot.x, slot.y, slot.width, slot.height);
    if (slot.empty) {
      return raw;
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var found = false;
    for (final LaidOutOmmlText text
        in omml.items.whereType<LaidOutOmmlText>()) {
      final Offset center = Offset(
        text.x + text.width / 2,
        text.y + text.height / 2,
      );
      if (!raw.inflate(2).contains(center)) {
        continue;
      }
      var insideSmaller = false;
      for (final LaidOutOmmlSlot other in omml.slots) {
        if (other.slotIndex == slot.slotIndex) {
          continue;
        }
        if (cells.isNotEmpty && !cells.contains(other.slotIndex)) {
          continue;
        }
        final Rect otherRect = Rect.fromLTWH(
          other.x,
          other.y,
          other.width,
          other.height,
        );
        if (otherRect.width * otherRect.height < slot.width * slot.height &&
            otherRect.contains(center)) {
          insideSmaller = true;
          break;
        }
      }
      if (insideSmaller) {
        continue;
      }
      found = true;
      minX = minX < text.x ? minX : text.x;
      minY = minY < text.y ? minY : text.y;
      maxX = maxX > text.x + text.width ? maxX : text.x + text.width;
      maxY = maxY > text.y + text.height ? maxY : text.y + text.height;
    }
    if (!found) {
      return raw;
    }
    return Rect.fromLTRB(minX - 2, minY - 2, maxX + 2, maxY + 2);
  }

  static double _distanceToRect(Offset point, Rect rect) {
    final double dx = point.dx < rect.left
        ? rect.left - point.dx
        : (point.dx > rect.right ? point.dx - rect.right : 0);
    final double dy = point.dy < rect.top
        ? rect.top - point.dy
        : (point.dy > rect.bottom ? point.dy - rect.bottom : 0);
    return dx * dx + dy * dy;
  }

  static void _text(Canvas canvas, LaidOutOmmlText item) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          fontSize: item.fontSize,
          color: ink,
          fontStyle: item.italic ? FontStyle.italic : FontStyle.normal,
          fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
          fontFamily: 'Cambria Math',
          fontFamilyFallback: const <String>[
            'Cambria',
            'Calibri',
            'Noto Naskh Arabic',
            'serif',
          ],
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(item.x, item.y + (item.height - painter.height) / 2),
    );
  }

  static void _stroke(Canvas canvas, LaidOutOmmlStroke item) {
    final Paint paint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path();
    switch (item.kind) {
      case OmmlStrokeKind.radical:
        final double check = (item.height * 0.42).clamp(8.0, item.width * 0.28);
        path
          ..moveTo(item.x, item.y + item.height * 0.55)
          ..lineTo(item.x + check * 0.38, item.y + item.height)
          ..lineTo(item.x + check, item.y + 1)
          ..lineTo(item.x + item.width, item.y + 1);
      case OmmlStrokeKind.parenLeft:
      case OmmlStrokeKind.braceLeft:
        path
          ..moveTo(item.x + item.width, item.y)
          ..cubicTo(
            item.x,
            item.y + item.height * 0.2,
            item.x,
            item.y + item.height * 0.8,
            item.x + item.width,
            item.y + item.height,
          );
      case OmmlStrokeKind.parenRight:
      case OmmlStrokeKind.braceRight:
        path
          ..moveTo(item.x, item.y)
          ..cubicTo(
            item.x + item.width,
            item.y + item.height * 0.2,
            item.x + item.width,
            item.y + item.height * 0.8,
            item.x,
            item.y + item.height,
          );
    }
    canvas.drawPath(path, paint);
  }
}
