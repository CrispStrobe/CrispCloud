import 'dart:math' as math;
import 'dart:ui';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'selection_matrix.dart';

/// Scrollable sheet size follows the last filled cell or the selection.
abstract final class SheetScrollExtent {
  /// minCols API.
  static const int minCols = 10;

  /// minRows API.
  static const int minRows = 22;

  /// padCols API.
  static const int padCols = 4;

  /// padRows API.
  static const int padRows = 8;

  /// lastCol API.
  static int lastCol(SmlWorksheet sheet, SelectionMatrix selection) {
    var last = 0;
    var any = false;
    for (final SmlCell cell in sheet.allCells) {
      if (!_filled(cell)) {
        continue;
      }
      any = true;
      if (cell.ref.col > last) {
        last = cell.ref.col;
      }
    }
    if (!selection.isFullRowSelection) {
      last = math.max(last, selection.anchor.col);
      last = math.max(last, selection.focus.col);
    }
    for (final SmlDrawing drawing in sheet.drawings) {
      final double right =
          sheet.columnLeft(drawing.col) +
          drawing.offsetX +
          drawing.visual.width;
      last = math.max(last, sheet.columnAt(right));
    }
    last = math.max(last, sheet.freezeCols);
    final int padded = any || last > 0 ? last + padCols : minCols - 1;
    return padded.clamp(minCols - 1, SmlWorksheet.excelColumnCount - 1);
  }

  /// lastRow API.
  static int lastRow(SmlWorksheet sheet, SelectionMatrix selection) {
    var last = 0;
    var any = false;
    for (final SmlCell cell in sheet.allCells) {
      if (!_filled(cell)) {
        continue;
      }
      any = true;
      if (cell.ref.row > last) {
        last = cell.ref.row;
      }
    }
    if (!selection.isFullColumnSelection) {
      last = math.max(last, selection.anchor.row);
      last = math.max(last, selection.focus.row);
    }
    for (final SmlDrawing drawing in sheet.drawings) {
      final double bottom =
          sheet.rowTop(drawing.row) + drawing.offsetY + drawing.visual.height;
      last = math.max(last, sheet.rowAt(bottom));
    }
    last = math.max(last, sheet.freezeRows);
    final int padded = any || last > 0 ? last + padRows : minRows - 1;
    return padded.clamp(minRows - 1, SmlWorksheet.excelRowCount - 1);
  }

  /// contentSize API.
  static Size contentSize({
    required SmlWorksheet sheet,
    required SelectionMatrix selection,
    required double scale,
    required double headW,
    required double headH,
    required double barH,
    double scrollBar = 12,
  }) {
    final int cols = lastCol(sheet, selection) + 1;
    final int rows = lastRow(sheet, selection) + 1;
    return Size(
      headW + sheet.columnLeft(cols) * scale + scrollBar,
      barH + headH + sheet.rowTop(rows) * scale + scrollBar,
    );
  }

  static bool _filled(SmlCell cell) {
    return (cell.value != null && cell.asString.isNotEmpty) ||
        (cell.formula != null && cell.formula!.isNotEmpty);
  }
}
