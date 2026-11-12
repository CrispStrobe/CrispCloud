import 'package:quds_office_engine/quds_office_engine.dart';

import 'step_input.dart';

typedef TableCellSelection = ({int row, int column, WmlTableCell cell});

/// Select either a physical row cell (legacy `column`) or a visible logical
/// cell (`gridColumn`). Logical selection follows horizontal spans and vertical
/// continuations to the content-owning merge origin.
TableCellSelection selectTableCell(WmlTable table, StepInput step) {
  if (step.has('column') == step.has('gridColumn')) {
    throw ArgumentError('Supply exactly one of column or gridColumn');
  }
  final row = step.integer('row', max: table.rows.length - 1);
  if (step.has('column')) {
    final column = step.integer(
      'column',
      max: table.rows[row].cells.length - 1,
    );
    return (row: row, column: column, cell: table.rows[row].cells[column]);
  }
  final gridColumn = step.integer(
    'gridColumn',
    max: WordTable.columnCount(table) - 1,
  );
  return logicalTableCell(table, row, gridColumn);
}

/// Resolve a logical grid coordinate without guessing through malformed merge
/// chains. OOXML vertical continuations must cover the same logical columns as
/// the preceding member. Reject these cases before any edit or unmerge.
TableCellSelection logicalTableCell(WmlTable table, int row, int gridColumn) {
  final selected = WordTable.cellAtGrid(table, row, gridColumn);
  if (selected == null) {
    throw ArgumentError('No cell covers gridColumn $gridColumn in row $row');
  }
  return (row: selected.row, column: selected.col, cell: selected.cell);
}

/// Add the two coordinate systems to `inspect` without making malformed input
/// impossible to inspect. The diagnostic marks why logical edits are guarded.
List<List<Map<String, Object?>>> tableGridCoordinates(WmlTable table) {
  final error = WordTable.supportsGridAddressing(table)
      ? null
      : 'Table does not have a supported rectangular grid';
  final rows = <List<Map<String, Object?>>>[];
  for (var row = 0; row < table.rows.length; row++) {
    final cells = <Map<String, Object?>>[];
    var gridColumn = table.rows[row].gridBefore;
    for (final (column, cell) in table.rows[row].cells.indexed) {
      final span = WordTable.spanOf(cell);
      final selected = error != null
          ? null
          : WordTable.cellAtGrid(table, row, gridColumn);
      final origin = selected == null
          ? null
          : <String, Object?>{
              'row': selected.row,
              'column': selected.col,
              'gridColumn': WordTable.gridStart(
                table.rows[selected.row],
                selected.col,
              ),
            };
      cells.add(<String, Object?>{
        'column': column,
        'gridColumn': gridColumn,
        'endGridColumn': gridColumn + span - 1,
        'mergeOrigin': origin,
        'gridError': ?error,
      });
      gridColumn += span;
    }
    rows.add(cells);
  }
  return rows;
}
