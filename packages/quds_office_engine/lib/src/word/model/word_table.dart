import '../properties/wml_properties.dart';
import 'wml_clone.dart';
import 'wml_document.dart';

/// Enum WordTableAutoFit.
enum WordTableAutoFit { contents, window, fixed }

/// Locate and mutate Word tables (insert / delete rows and columns).
abstract final class WordTable {
  /// emptyCell API.
  static WmlTableCell emptyCell() {
    return WmlTableCell(
      blocks: <WmlBlock>[
        WmlParagraph(inlines: <WmlInline>[WmlRun()]),
      ],
    );
  }

  /// emptyCellLike API.
  static WmlTableCell emptyCellLike(WmlTableCell? source) {
    if (source == null) {
      return emptyCell();
    }
    final List<WmlBlock> blocks = <WmlBlock>[];
    for (final WmlBlock block in source.blocks) {
      if (block is WmlParagraph) {
        blocks.add(
          WmlParagraph(
            properties: block.properties.copy(),
            inlines: <WmlInline>[
              for (final WmlInline inline in block.inlines)
                if (inline is WmlRun)
                  WmlRun(properties: inline.properties.copy()),
            ],
          ),
        );
      }
    }
    if (blocks.isEmpty) {
      blocks.add(WmlParagraph(inlines: <WmlInline>[WmlRun()]));
    }
    return WmlTableCell(
      width: source.width,
      fillColor: source.fillColor,
      blocks: blocks,
    );
  }

  static ({WmlTable table, int row, int col})? locationOfParagraph(
    WmlDocument document,
    WmlParagraph paragraph,
  ) {
    for (final WmlSection section in document.sections) {
      final ({WmlTable table, int row, int col})? found = _locateInBlocks(
        section.blocks,
        paragraph,
      );
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static ({WmlTable table, int row, int col})? locationOfIndex(
    WmlDocument document,
    int paragraphIndex,
  ) {
    final List<WmlParagraph> paras = document.paragraphs.toList();
    if (paragraphIndex < 0 || paragraphIndex >= paras.length) {
      return null;
    }
    return locationOfParagraph(document, paras[paragraphIndex]);
  }

  static ({WmlTable table, int row, int col})? _locateInBlocks(
    List<WmlBlock> blocks,
    WmlParagraph paragraph,
  ) {
    for (final WmlBlock block in blocks) {
      if (block is WmlFrame) {
        final ({WmlTable table, int row, int col})? nested = _locateInBlocks(
          block.blocks,
          paragraph,
        );
        if (nested != null) {
          return nested;
        }
      }
      if (block is WmlTable) {
        for (int r = 0; r < block.rows.length; r++) {
          for (int c = 0; c < block.rows[r].cells.length; c++) {
            final ({WmlTable table, int row, int col})? nested =
                _locateInBlocks(block.rows[r].cells[c].blocks, paragraph);
            if (nested != null) {
              return nested;
            }
            if (_containsDirect(block.rows[r].cells[c].blocks, paragraph)) {
              return (table: block, row: r, col: c);
            }
          }
        }
      }
    }
    return null;
  }

  static bool _containsDirect(List<WmlBlock> blocks, WmlParagraph paragraph) {
    for (final WmlBlock block in blocks) {
      if (identical(block, paragraph)) {
        return true;
      }
    }
    return false;
  }

  /// spanOf API.
  static int spanOf(WmlTableCell cell) => cell.gridSpan < 1 ? 1 : cell.gridSpan;

  /// gridStart API.
  static int gridStart(WmlTableRow row, int cellIndex) {
    var col = 0;
    for (int i = 0; i < cellIndex && i < row.cells.length; i++) {
      col += spanOf(row.cells[i]);
    }
    return col;
  }

  /// cellIndexAtGrid API.
  static int? cellIndexAtGrid(WmlTableRow row, int gridCol) {
    var col = 0;
    for (int i = 0; i < row.cells.length; i++) {
      final int span = spanOf(row.cells[i]);
      if (gridCol >= col && gridCol < col + span) {
        return i;
      }
      col += span;
    }
    return null;
  }

  /// columnCount API.
  static int columnCount(WmlTable table) {
    var max = table.grid.length;
    for (final WmlTableRow row in table.rows) {
      var cols = 0;
      for (final WmlTableCell cell in row.cells) {
        cols += spanOf(cell);
      }
      if (cols > max) {
        max = cols;
      }
    }
    return max;
  }

  static ({int r0, int g0, int r1, int g1})? gridRect(
    WmlTable table,
    int rowA,
    int colA,
    int rowB,
    int colB,
  ) {
    if (rowA < 0 ||
        rowB < 0 ||
        rowA >= table.rows.length ||
        rowB >= table.rows.length) {
      return null;
    }
    final WmlTableRow row0 = table.rows[rowA];
    final WmlTableRow row1 = table.rows[rowB];
    if (colA < 0 ||
        colB < 0 ||
        colA >= row0.cells.length ||
        colB >= row1.cells.length) {
      return null;
    }
    final int r0 = rowA < rowB ? rowA : rowB;
    final int r1 = rowA > rowB ? rowA : rowB;
    final int a0 = gridStart(row0, colA);
    final int a1 = a0 + spanOf(row0.cells[colA]) - 1;
    final int b0 = gridStart(row1, colB);
    final int b1 = b0 + spanOf(row1.cells[colB]) - 1;
    return (r0: r0, g0: a0 < b0 ? a0 : b0, r1: r1, g1: a1 > b1 ? a1 : b1);
  }

  static bool _coversExactly(WmlTableRow row, int g0, int g1) {
    var col = 0;
    var covered = 0;
    for (final WmlTableCell cell in row.cells) {
      final int span = spanOf(cell);
      final int start = col;
      final int end = col + span - 1;
      if (end >= g0 && start <= g1) {
        if (start < g0 || end > g1) {
          return false;
        }
        covered += span;
      }
      col += span;
    }
    return covered == g1 - g0 + 1;
  }

  static int _cellsInRect(WmlTable table, int r0, int g0, int r1, int g1) {
    var count = 0;
    for (int r = r0; r <= r1; r++) {
      var col = 0;
      for (final WmlTableCell cell in table.rows[r].cells) {
        final int span = spanOf(cell);
        if (col >= g0 && col + span - 1 <= g1) {
          count++;
        }
        col += span;
      }
    }
    return count;
  }

  /// canMerge API.
  static bool canMerge(WmlTable table, int r0, int g0, int r1, int g1) {
    if (r1 < r0 || g1 < g0) {
      return false;
    }
    if (r0 < 0 || r1 >= table.rows.length) {
      return false;
    }
    if (_cellsInRect(table, r0, g0, r1, g1) < 2) {
      return false;
    }
    for (int r = r0; r <= r1; r++) {
      if (!_coversExactly(table.rows[r], g0, g1)) {
        return false;
      }
    }
    return true;
  }

  static void _appendCellContent(WmlTableCell dest, WmlTableCell source) {
    for (final WmlBlock block in source.blocks) {
      if (block is WmlParagraph && block.text.trim().isNotEmpty) {
        dest.blocks.add(WmlClone.block(block));
      }
    }
  }

  /// merge API.
  static void merge(WmlTable table, int r0, int g0, int r1, int g1) {
    if (!canMerge(table, r0, g0, r1, g1)) {
      return;
    }
    final int span = g1 - g0 + 1;
    WmlTableCell? master;
    for (int r = r0; r <= r1; r++) {
      final WmlTableRow row = table.rows[r];
      WmlTableCell? first;
      final List<int> drop = <int>[];
      var col = 0;
      for (int i = 0; i < row.cells.length; i++) {
        final WmlTableCell cell = row.cells[i];
        final int cellSpan = spanOf(cell);
        if (col >= g0 && col + cellSpan - 1 <= g1) {
          if (first == null) {
            first = cell;
          } else {
            _appendCellContent(first, cell);
            drop.add(i);
          }
        }
        col += cellSpan;
      }
      if (first == null) {
        continue;
      }
      first.gridSpan = span;
      if (r1 > r0) {
        first.vMerge = r == r0 ? WmlVMerge.restart : WmlVMerge.cont;
      }
      if (r == r0) {
        master = first;
      } else if (master != null) {
        _appendCellContent(master, first);
        first.blocks
          ..clear()
          ..add(WmlParagraph(inlines: <WmlInline>[WmlRun()]));
      }
      for (int i = drop.length - 1; i >= 0; i--) {
        row.cells.removeAt(drop[i]);
      }
    }
  }

  /// canUnmerge API.
  static bool canUnmerge(WmlTable table, int row, int col) {
    if (row < 0 || row >= table.rows.length) {
      return false;
    }
    if (col < 0 || col >= table.rows[row].cells.length) {
      return false;
    }
    final WmlTableCell cell = table.rows[row].cells[col];
    return spanOf(cell) > 1 || cell.vMerge != WmlVMerge.none;
  }

  static ({int row, int col}) _mergeOrigin(WmlTable table, int row, int col) {
    var r0 = row;
    var c0 = col;
    WmlTableCell cell = table.rows[row].cells[col];
    if (cell.vMerge == WmlVMerge.cont) {
      final int g = gridStart(table.rows[row], col);
      for (int r = row - 1; r >= 0; r--) {
        final int? i = cellIndexAtGrid(table.rows[r], g);
        if (i == null) {
          break;
        }
        r0 = r;
        c0 = i;
        cell = table.rows[r].cells[i];
        if (cell.vMerge != WmlVMerge.cont) {
          break;
        }
      }
    }
    return (row: r0, col: c0);
  }

  /// unmerge API.
  static void unmerge(WmlTable table, int row, int col) {
    if (!canUnmerge(table, row, col)) {
      return;
    }
    final ({int row, int col}) origin = _mergeOrigin(table, row, col);
    final WmlTableCell head = table.rows[origin.row].cells[origin.col];
    final int g0 = gridStart(table.rows[origin.row], origin.col);
    final int span = spanOf(head);
    var r1 = origin.row;
    if (head.vMerge == WmlVMerge.restart) {
      for (int r = origin.row + 1; r < table.rows.length; r++) {
        final int? i = cellIndexAtGrid(table.rows[r], g0);
        if (i == null || table.rows[r].cells[i].vMerge != WmlVMerge.cont) {
          break;
        }
        r1 = r;
      }
    }
    for (int r = origin.row; r <= r1; r++) {
      final int? i = cellIndexAtGrid(table.rows[r], g0);
      if (i == null) {
        continue;
      }
      final WmlTableCell cell = table.rows[r].cells[i];
      cell
        ..vMerge = WmlVMerge.none
        ..gridSpan = 1;
      for (int k = 1; k < span; k++) {
        table.rows[r].cells.insert(i + k, emptyCellLike(cell));
        table.rows[r].cells[i + k]
          ..gridSpan = 1
          ..vMerge = WmlVMerge.none;
      }
    }
  }

  /// gridWidth API.
  static double gridWidth(WmlTable table) {
    var total = 0.0;
    for (final double width in table.grid) {
      total += width;
    }
    return total;
  }

  /// insertRow API.
  static void insertRow(WmlTable table, int index) {
    final int cols = columnCount(table);
    if (cols <= 0) {
      table.grid.add(120);
    }
    final int width = cols <= 0 ? 1 : cols;
    final int at = index.clamp(0, table.rows.length);
    final int source = at > 0 ? at - 1 : 0;
    final WmlTableRow? like = table.rows.isEmpty
        ? null
        : table.rows[source.clamp(0, table.rows.length - 1)];
    table.rows.insert(
      at,
      WmlTableRow(
        cantSplit: like?.cantSplit ?? false,
        cells: <WmlTableCell>[
          for (int c = 0; c < width; c++)
            emptyCellLike(
              like != null && c < like.cells.length ? like.cells[c] : null,
            ),
        ],
      ),
    );
  }

  /// insertColumn API.
  static void insertColumn(WmlTable table, int index) {
    final int cols = columnCount(table);
    final int at = index.clamp(0, cols);
    final int source = at > 0 ? at - 1 : 0;
    final double width = table.grid.isEmpty
        ? 120
        : table.grid[source.clamp(0, table.grid.length - 1)];
    if (table.grid.length < cols) {
      while (table.grid.length < cols) {
        table.grid.add(width);
      }
    }
    table.grid.insert(at.clamp(0, table.grid.length), width);
    for (final WmlTableRow row in table.rows) {
      while (row.cells.length < cols) {
        row.cells.add(emptyCell());
      }
      final WmlTableCell? like = row.cells.isEmpty
          ? null
          : row.cells[source.clamp(0, row.cells.length - 1)];
      row.cells.insert(at.clamp(0, row.cells.length), emptyCellLike(like));
    }
  }

  /// autoFit API.
  static void autoFit(
    WmlTable table,
    WordTableAutoFit mode, {
    double contentWidth = 451,
  }) {
    switch (mode) {
      case WordTableAutoFit.contents:
        autoFitContents(table);
      case WordTableAutoFit.window:
        autoFitWindow(table, contentWidth);
      case WordTableAutoFit.fixed:
        autoFitFixed(table);
    }
  }

  /// autoFitContents API.
  static void autoFitContents(WmlTable table) {
    final int cols = columnCount(table);
    if (cols <= 0) {
      return;
    }
    while (table.grid.length < cols) {
      table.grid.add(120);
    }
    if (table.grid.length > cols) {
      table.grid.removeRange(cols, table.grid.length);
    }
    for (int c = 0; c < cols; c++) {
      var widest = 36.0;
      for (final WmlTableRow row in table.rows) {
        if (c >= row.cells.length) {
          continue;
        }
        for (final WmlBlock block in row.cells[c].blocks) {
          if (block is WmlParagraph) {
            final double estimate = block.text.length * 6.2 + 14;
            if (estimate > widest) {
              widest = estimate;
            }
          }
        }
      }
      table.grid[c] = widest.clamp(36, 360);
      for (final WmlTableRow row in table.rows) {
        if (c < row.cells.length) {
          row.cells[c].width = table.grid[c];
        }
      }
    }
  }

  /// autoFitWindow API.
  static void autoFitWindow(WmlTable table, double contentWidth) {
    final int cols = columnCount(table);
    if (cols <= 0 || contentWidth <= 0) {
      return;
    }
    while (table.grid.length < cols) {
      table.grid.add(contentWidth / cols);
    }
    if (table.grid.length > cols) {
      table.grid.removeRange(cols, table.grid.length);
    }
    final double total = gridWidth(table);
    final double scale = total <= 0 ? 1 : contentWidth / total;
    for (int i = 0; i < table.grid.length; i++) {
      table.grid[i] = (table.grid[i] * scale).clamp(24, contentWidth);
    }
    autoFitFixed(table);
  }

  /// autoFitFixed API.
  static void autoFitFixed(WmlTable table) {
    final int cols = columnCount(table);
    while (table.grid.length < cols) {
      table.grid.add(120);
    }
    for (final WmlTableRow row in table.rows) {
      for (int c = 0; c < row.cells.length && c < table.grid.length; c++) {
        row.cells[c].width = table.grid[c];
      }
    }
  }

  /// constrainToWidth API.
  static void constrainToWidth(WmlTable table, double maxWidth) {
    if (gridWidth(table) > maxWidth + 0.5) {
      autoFitWindow(table, maxWidth);
    }
  }

  /// deleteRow API.
  static void deleteRow(WmlTable table, int index) {
    if (table.rows.length <= 1 || index < 0 || index >= table.rows.length) {
      return;
    }
    table.rows.removeAt(index);
  }

  /// deleteColumn API.
  static void deleteColumn(WmlTable table, int index) {
    final int cols = columnCount(table);
    if (cols <= 1 || index < 0 || index >= cols) {
      return;
    }
    if (index < table.grid.length) {
      table.grid.removeAt(index);
    }
    for (final WmlTableRow row in table.rows) {
      if (index < row.cells.length) {
        row.cells.removeAt(index);
      }
    }
  }

  /// snapshot API.
  static WmlTable snapshot(WmlTable table) => WmlClone.table(table);

  /// restore API.
  static void restore(WmlTable table, WmlTable snap) {
    table.grid
      ..clear()
      ..addAll(snap.grid);
    table.properties
      ..alignment = snap.properties.alignment
      ..floating = snap.properties.floating
      ..cellMargin = snap.properties.cellMargin
      ..rightToLeft = snap.properties.rightToLeft;
    table.rows
      ..clear()
      ..addAll(snap.rows);
  }
}
