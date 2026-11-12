import 'package:quds_office_engine/quds_office_engine.dart';

/// A table's structure and geometry, retaining the objects edited by commands.
///
/// Deep clones are appropriate for independent documents. History must restore
/// the original rows, cells and child blocks: later text, frame and drawing
/// commands keep references to those objects. Each state copies scalar values
/// and list membership while leaving child content to its own history commands.
class WordTableHistoryState {
  WordTableHistoryState.capture(this.table)
    : _grid = List<double>.of(table.grid),
      _properties = table.properties.copy(),
      _rows = [for (final row in table.rows) _RowState(row)];

  final WmlTable table;
  final List<double> _grid;
  final WmlTableProps _properties;
  final List<_RowState> _rows;

  void restore() {
    table.grid
      ..clear()
      ..addAll(_grid);
    table.properties = _properties.copy();
    table.rows
      ..clear()
      ..addAll(_rows.map((state) => state.row));
    for (final state in _rows) {
      state.restore();
    }
  }
}

class _RowState {
  _RowState(this.row)
    : _height = row.height,
      _cantSplit = row.cantSplit,
      _cells = [for (final cell in row.cells) _CellState(cell)];

  final WmlTableRow row;
  final double? _height;
  final bool _cantSplit;
  final List<_CellState> _cells;

  void restore() {
    row
      ..height = _height
      ..cantSplit = _cantSplit;
    row.cells
      ..clear()
      ..addAll(_cells.map((state) => state.cell));
    for (final state in _cells) {
      state.restore();
    }
  }
}

class _CellState {
  _CellState(this.cell)
    : _blocks = List<WmlBlock>.of(cell.blocks),
      _span = cell.gridSpan,
      _merge = cell.vMerge,
      _width = cell.width,
      _fill = cell.fillColor,
      _top = cell.borderTop,
      _bottom = cell.borderBottom,
      _left = cell.borderLeft,
      _right = cell.borderRight;

  final WmlTableCell cell;
  final List<WmlBlock> _blocks;
  final int _span;
  final WmlVMerge _merge;
  final double? _width;
  final String? _fill;
  final bool? _top;
  final bool? _bottom;
  final bool? _left;
  final bool? _right;

  void restore() {
    cell
      ..gridSpan = _span
      ..vMerge = _merge
      ..width = _width
      ..fillColor = _fill
      ..borderTop = _top
      ..borderBottom = _bottom
      ..borderLeft = _left
      ..borderRight = _right;
    cell.blocks
      ..clear()
      ..addAll(_blocks);
  }
}
