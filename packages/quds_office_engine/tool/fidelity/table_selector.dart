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
  _validateMerges(table);
  if (row < 0 || row >= table.rows.length || gridColumn < 0) {
    throw ArgumentError('Logical table coordinate is outside the table');
  }
  final selected = WordTable.cellIndexAtGrid(table.rows[row], gridColumn);
  if (selected == null) {
    throw ArgumentError('No cell covers gridColumn $gridColumn in row $row');
  }
  var originRow = row;
  var originColumn = selected;
  while (table.rows[originRow].cells[originColumn].vMerge == WmlVMerge.cont) {
    final start = WordTable.gridStart(table.rows[originRow], originColumn);
    originRow--;
    originColumn = WordTable.cellIndexAtGrid(table.rows[originRow], start)!;
  }
  return (
    row: originRow,
    column: originColumn,
    cell: table.rows[originRow].cells[originColumn],
  );
}

void _validateMerges(WmlTable table) {
  for (var row = 0; row < table.rows.length; row++) {
    for (var column = 0; column < table.rows[row].cells.length; column++) {
      final cell = table.rows[row].cells[column];
      if (cell.gridSpan < 1) {
        throw ArgumentError('Cell at $row/$column has a nonpositive gridSpan');
      }
      if (cell.vMerge != WmlVMerge.cont) continue;
      final start = WordTable.gridStart(table.rows[row], column);
      final preceding = row == 0
          ? null
          : WordTable.cellIndexAtGrid(table.rows[row - 1], start);
      if (preceding == null ||
          WordTable.gridStart(table.rows[row - 1], preceding) != start ||
          table.rows[row - 1].cells[preceding].gridSpan != cell.gridSpan ||
          table.rows[row - 1].cells[preceding].vMerge == WmlVMerge.none) {
        throw ArgumentError(
          'Vertical continuation at $row/$column has no aligned merge origin',
        );
      }
    }
  }
}

/// Add the two coordinate systems to `inspect` without making malformed input
/// impossible to inspect. The diagnostic marks why logical edits are guarded.
List<List<Map<String, Object?>>> tableGridCoordinates(WmlTable table) {
  String? error;
  try {
    _validateMerges(table);
  } on ArgumentError catch (caught) {
    error = caught.message.toString();
  }
  final rows = <List<Map<String, Object?>>>[];
  for (var row = 0; row < table.rows.length; row++) {
    final cells = <Map<String, Object?>>[];
    var gridColumn = 0;
    for (final (column, cell) in table.rows[row].cells.indexed) {
      final span = WordTable.spanOf(cell);
      final origin = error != null
          ? null
          : cell.vMerge == WmlVMerge.cont
          ? rows[row - 1][WordTable.cellIndexAtGrid(
              table.rows[row - 1],
              gridColumn,
            )!]['mergeOrigin']
          : <String, Object?>{
              'row': row,
              'column': column,
              'gridColumn': gridColumn,
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
