// Adapted from MadEdit2's lib/editor/hex_view.dart.
// Copyright (c) 2026 madedit. MIT License; see the package LICENSE.
// The byte-window layout, nibble hit testing and bounded painting are retained;
// app settings, text indexing, Rust and encoding-dependent editing are removed.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'hex_editor_controller.dart';

/// Geometry shared by painting and hit testing, in monospace character cells.
class HexViewportGeometry {
  const HexViewportGeometry({
    required this.bytesPerRow,
    required this.offsetDigits,
    required this.characterWidth,
    required this.rowHeight,
    required this.headerHeight,
    this.padding = 12,
  });

  final int bytesPerRow;
  final int offsetDigits;
  final double characterWidth;
  final double rowHeight;
  final double headerHeight;
  final double padding;

  int hexColumn(int byte) =>
      offsetDigits + 2 + byte * 3 + (byte >= bytesPerRow ~/ 2 ? 1 : 0);
  int get asciiStart => offsetDigits + 2 + bytesPerRow * 3 + 3;
  int asciiColumn(int byte) => asciiStart + byte;
  double x(int column) => padding + column * characterWidth;
  double get width => x(asciiStart + bytesPerRow + 1) + padding;

  static int digitsForLength(int length) =>
      math.max(8, length.toRadixString(16).length);

  HexViewportHit? hitTest(
    Offset position, {
    required int base,
    required int length,
    required int visibleRows,
    bool clampY = false,
  }) {
    final rowY = position.dy - headerHeight;
    if (!clampY && (rowY < 0 || rowY >= visibleRows * rowHeight)) return null;
    final row = (rowY / rowHeight).floor().clamp(0, visibleRows - 1);
    final column = (position.dx - padding) / characterWidth;
    int byte;
    int nibble = 0;
    HexEditorArea area;
    if (column >= asciiStart - 1) {
      area = HexEditorArea.ascii;
      byte = (column - asciiStart).floor().clamp(0, bytesPerRow - 1);
    } else {
      area = HexEditorArea.hex;
      byte = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < bytesPerRow; i++) {
        final high = hexColumn(i).toDouble();
        final distance = (column - high - 0.5).abs();
        final lowDistance = (column - high - 1.5).abs();
        if (distance < bestDistance) {
          byte = i;
          nibble = 0;
          bestDistance = distance;
        }
        if (lowDistance < bestDistance) {
          byte = i;
          nibble = 1;
          bestDistance = lowDistance;
        }
      }
    }
    final offset = (base + row * bytesPerRow + byte).clamp(0, length);
    return HexViewportHit(offset, area, offset == length ? 0 : nibble);
  }
}

class HexViewportHit {
  const HexViewportHit(this.offset, this.area, this.nibble);
  final int offset;
  final HexEditorArea area;
  final int nibble;
}

/// Paints and exposes semantics only for the supplied byte window, regardless
/// of the backing file's size. Scrolling is represented by an integer offset,
/// never by a billions-of-pixels render object.
class HexViewportPainter extends CustomPainter {
  HexViewportPainter({
    required this.bytes,
    required this.base,
    required this.documentLength,
    required this.geometry,
    required this.textStyle,
    required this.background,
    required this.foreground,
    required this.offsetColor,
    required this.selectionColor,
    required this.caretColor,
    required this.currentRowColor,
    required this.headerColor,
    required this.caretOffset,
    required this.caretNibble,
    required this.area,
    required this.selectionStart,
    required this.selectionEnd,
    required this.insertMode,
    required this.showCaret,
    required this.focused,
    required this.offsetLabel,
    required this.textLabel,
    required this.onSemanticSelect,
  });

  final Uint8List bytes;
  final int base;
  final int documentLength;
  final HexViewportGeometry geometry;
  final TextStyle textStyle;
  final Color background;
  final Color foreground;
  final Color offsetColor;
  final Color selectionColor;
  final Color caretColor;
  final Color currentRowColor;
  final Color headerColor;
  final int caretOffset;
  final int caretNibble;
  final HexEditorArea area;
  final int selectionStart;
  final int selectionEnd;
  final bool insertMode;
  final bool showCaret;
  final bool focused;
  final String offsetLabel;
  final String textLabel;
  final ValueChanged<int> onSemanticSelect;

  int get _rows => (bytes.length / geometry.bytesPerRow).ceil();

  void _text(Canvas canvas, String text, double x, double y, Color color) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    p.paint(canvas, Offset(x, y + (geometry.rowHeight - p.height) / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final g = geometry;
    if (g.headerHeight > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, g.headerHeight),
        Paint()..color = headerColor,
      );
      final y = (g.headerHeight - g.rowHeight) / 2;
      _text(canvas, offsetLabel, g.padding, y, offsetColor);
      for (var i = 0; i < g.bytesPerRow; i++) {
        _text(
          canvas,
          i.toRadixString(16).padLeft(2, '0').toUpperCase(),
          g.x(g.hexColumn(i)),
          y,
          offsetColor,
        );
      }
      _text(canvas, textLabel, g.x(g.asciiStart), y, offsetColor);
    }
    final caretRow = (caretOffset - base) ~/ g.bytesPerRow;
    if (caretOffset >= base && caretRow >= 0) {
      final y = g.headerHeight + caretRow * g.rowHeight;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, g.rowHeight),
        Paint()..color = currentRowColor,
      );
    }
    for (var row = 0; row < _rows; row++) {
      final from = row * g.bytesPerRow;
      final count = math.min(g.bytesPerRow, bytes.length - from);
      final rowOffset = base + from;
      final y = g.headerHeight + row * g.rowHeight;
      if (y >= size.height) break;
      final selectedFrom = (selectionStart - rowOffset).clamp(0, count);
      final selectedTo = (selectionEnd - rowOffset).clamp(0, count);
      if (selectedFrom < selectedTo) {
        final color = focused ? selectionColor : selectionColor.withAlpha(95);
        canvas.drawRect(
          Rect.fromLTRB(
            g.x(g.hexColumn(selectedFrom)),
            y,
            g.x(g.hexColumn(selectedTo - 1) + 2),
            y + g.rowHeight,
          ),
          Paint()..color = color,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            g.x(g.asciiColumn(selectedFrom)),
            y,
            (selectedTo - selectedFrom) * g.characterWidth,
            g.rowHeight,
          ),
          Paint()..color = color,
        );
      }
      _text(
        canvas,
        rowOffset.toRadixString(16).padLeft(g.offsetDigits, '0').toUpperCase(),
        g.padding,
        y,
        offsetColor,
      );
      // A single paragraph for the byte column retains MadEdit2's fixed-cell
      // layout without building one widget per byte or per row.
      final hex = StringBuffer();
      final ascii = StringBuffer();
      for (var i = 0; i < count; i++) {
        if (i == g.bytesPerRow ~/ 2) hex.write(' ');
        final value = bytes[from + i];
        hex.write('${value.toRadixString(16).padLeft(2, '0').toUpperCase()} ');
        ascii.write(
          value >= 32 && value <= 126 ? String.fromCharCode(value) : '.',
        );
      }
      _text(canvas, hex.toString(), g.x(g.hexColumn(0)), y, foreground);
      _text(canvas, ascii.toString(), g.x(g.asciiStart), y, foreground);
    }
    // The EOF insertion row also exists for an empty document or exact row
    // boundary. It is painted without requiring an artificial backing byte.
    if (documentLength >= base && documentLength % g.bytesPerRow == 0) {
      final row = (documentLength - base) ~/ g.bytesPerRow;
      final y = g.headerHeight + row * g.rowHeight;
      if (y < size.height) {
        _text(
          canvas,
          documentLength
              .toRadixString(16)
              .padLeft(g.offsetDigits, '0')
              .toUpperCase(),
          g.padding,
          y,
          offsetColor,
        );
      }
    }
    if (showCaret && caretOffset >= base && caretOffset <= documentLength) {
      final row = (caretOffset - base) ~/ g.bytesPerRow;
      final byte = (caretOffset - base) % g.bytesPerRow;
      final y = g.headerHeight + row * g.rowHeight;
      final column = area == HexEditorArea.hex
          ? g.hexColumn(byte) + caretNibble
          : g.asciiColumn(byte);
      final x = g.x(column);
      if (y < size.height) {
        final paint = Paint()..color = focused ? caretColor : offsetColor;
        if (insertMode || caretOffset == documentLength) {
          canvas.drawRect(Rect.fromLTWH(x, y + 2, 2, g.rowHeight - 4), paint);
        } else {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRect(
            Rect.fromLTWH(x, y + 1, g.characterWidth, g.rowHeight - 2),
            paint,
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (Size size) {
    final result = <CustomPainterSemantics>[];
    for (var row = 0; row < _rows; row++) {
      final start = row * geometry.bytesPerRow;
      final end = math.min(start + geometry.bytesPerRow, bytes.length);
      final offset = base + start;
      final y = geometry.headerHeight + row * geometry.rowHeight;
      if (y >= size.height) break;
      final values = bytes.sublist(start, end);
      result.add(
        CustomPainterSemantics(
          key: ValueKey('hex-row-$offset'),
          rect: Rect.fromLTWH(
            0,
            y,
            math.min(size.width, geometry.width),
            math.min(geometry.rowHeight, size.height - y),
          ),
          properties: SemanticsProperties(
            textDirection: TextDirection.ltr,
            label:
                '$offsetLabel 0x${offset.toRadixString(16).toUpperCase()}: '
                '${HexEditorController.formatHex(values)}',
            selected:
                selectionStart < offset + values.length &&
                selectionEnd > offset,
            onTap: () => onSemanticSelect(offset),
          ),
        ),
      );
    }
    return result;
  };

  @override
  bool shouldRebuildSemantics(covariant HexViewportPainter oldDelegate) =>
      oldDelegate.bytes != bytes ||
      oldDelegate.base != base ||
      oldDelegate.selectionStart != selectionStart ||
      oldDelegate.selectionEnd != selectionEnd ||
      oldDelegate.geometry != geometry;

  @override
  bool shouldRepaint(covariant HexViewportPainter oldDelegate) => true;
}
