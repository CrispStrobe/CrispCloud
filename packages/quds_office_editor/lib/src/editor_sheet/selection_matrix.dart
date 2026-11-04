import 'package:quds_office_engine/quds_office_engine.dart';

/// Enum SheetSelectionKind.
enum SheetSelectionKind { cells, rows, columns }

/// Class SelectionMatrix.
class SelectionMatrix {
  /// SelectionMatrix API.
  SelectionMatrix({this.anchor = const SmlCellRef(0, 0), SmlCellRef? focus})
    : focus = focus ?? const SmlCellRef(0, 0);

  /// anchor API.
  SmlCellRef anchor;

  /// focus API.
  SmlCellRef focus;

  /// kind API.
  SheetSelectionKind kind = SheetSelectionKind.cells;

  /// range API.
  SmlRange get range {
    if (kind == SheetSelectionKind.rows) {
      final int r0 = anchor.row < focus.row ? anchor.row : focus.row;
      final int r1 = anchor.row > focus.row ? anchor.row : focus.row;
      return SmlRange(
        SmlCellRef(0, r0),
        SmlCellRef(SmlWorksheet.excelColumnCount - 1, r1),
      );
    }
    if (kind == SheetSelectionKind.columns) {
      final int c0 = anchor.col < focus.col ? anchor.col : focus.col;
      final int c1 = anchor.col > focus.col ? anchor.col : focus.col;
      return SmlRange(
        SmlCellRef(c0, 0),
        SmlCellRef(c1, SmlWorksheet.excelRowCount - 1),
      );
    }
    return SmlRange(anchor, focus);
  }

  /// contains API.
  bool contains(SmlCellRef ref) {
    if (kind == SheetSelectionKind.rows) {
      final int r0 = anchor.row < focus.row ? anchor.row : focus.row;
      final int r1 = anchor.row > focus.row ? anchor.row : focus.row;
      return ref.row >= r0 && ref.row <= r1;
    }
    if (kind == SheetSelectionKind.columns) {
      final int c0 = anchor.col < focus.col ? anchor.col : focus.col;
      final int c1 = anchor.col > focus.col ? anchor.col : focus.col;
      return ref.col >= c0 && ref.col <= c1;
    }
    final int r0 = anchor.row < focus.row ? anchor.row : focus.row;
    final int r1 = anchor.row > focus.row ? anchor.row : focus.row;
    final int c0 = anchor.col < focus.col ? anchor.col : focus.col;
    final int c1 = anchor.col > focus.col ? anchor.col : focus.col;
    return ref.row >= r0 && ref.row <= r1 && ref.col >= c0 && ref.col <= c1;
  }

  /// selectCell API.
  void selectCell(SmlCellRef ref) {
    kind = SheetSelectionKind.cells;
    anchor = focus = ref;
  }

  /// extendTo API.
  void extendTo(SmlCellRef ref) {
    if (kind == SheetSelectionKind.rows) {
      extendRowsTo(ref.row);
      return;
    }
    if (kind == SheetSelectionKind.columns) {
      extendColumnsTo(ref.col);
      return;
    }
    focus = ref;
  }

  /// selectRow API.
  void selectRow(int row) {
    kind = SheetSelectionKind.rows;
    final int r = row.clamp(0, SmlWorksheet.excelRowCount - 1);
    anchor = SmlCellRef(0, r);
    focus = SmlCellRef(0, r);
  }

  /// selectColumn API.
  void selectColumn(int col) {
    kind = SheetSelectionKind.columns;
    final int c = col.clamp(0, SmlWorksheet.excelColumnCount - 1);
    anchor = SmlCellRef(c, 0);
    focus = SmlCellRef(c, 0);
  }

  /// Grow a header selection across whole columns, not a cell block.
  void extendColumnsTo(int col) {
    kind = SheetSelectionKind.columns;
    final int c = col.clamp(0, SmlWorksheet.excelColumnCount - 1);
    anchor = SmlCellRef(anchor.col, 0);
    focus = SmlCellRef(c, 0);
  }

  /// Grow a header selection across whole rows, not a cell block.
  void extendRowsTo(int row) {
    kind = SheetSelectionKind.rows;
    final int r = row.clamp(0, SmlWorksheet.excelRowCount - 1);
    anchor = SmlCellRef(0, anchor.row);
    focus = SmlCellRef(0, r);
  }

  /// isFullRowSelection API.
  bool get isFullRowSelection => kind == SheetSelectionKind.rows;

  /// isFullColumnSelection API.
  bool get isFullColumnSelection => kind == SheetSelectionKind.columns;
}
