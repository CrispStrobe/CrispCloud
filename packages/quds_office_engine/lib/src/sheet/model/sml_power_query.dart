import '../../reports/report_data.dart';
import 'sml_workbook.dart';

/// Loads a delimited table into a worksheet (CSV helper — not full Power Query).
abstract final class SmlPowerQuery {
  /// Parses [csv] and writes rows starting at [origin].
  static SmlRange fromCsv(
    SmlWorksheet sheet,
    String csv, {
    SmlCellRef origin = const SmlCellRef(0, 0),
    String delimiter = ',',
    bool detectNumbers = true,
  }) {
    final rows = ReportCsv.parse(
      csv,
      delimiter: delimiter,
      keepEmptyRows: true,
    );
    return fromRows(sheet, rows, origin: origin, detectNumbers: detectNumbers);
  }

  /// Writes parsed cells without treating formula-looking text as a formula.
  /// Disable [detectNumbers] to preserve identifiers and exact textual values.
  static SmlRange fromRows(
    SmlWorksheet sheet,
    List<List<String>> rows, {
    SmlCellRef origin = const SmlCellRef(0, 0),
    bool detectNumbers = true,
  }) {
    var maxCol = origin.col;
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        final SmlCell cell = sheet.cell(
          SmlCellRef(origin.col + c, origin.row + r),
        );
        final String raw = rows[r][c];
        final double? n = detectNumbers ? double.tryParse(raw) : null;
        if (n != null && raw.isNotEmpty) {
          cell
            ..type = SmlCellType.number
            ..formula = null
            ..value = n;
        } else {
          cell
            ..type = SmlCellType.string
            ..formula = null
            ..value = raw;
        }
        if (origin.col + c > maxCol) {
          maxCol = origin.col + c;
        }
      }
    }
    return SmlRange(
      origin,
      SmlCellRef(maxCol, origin.row + (rows.isEmpty ? 0 : rows.length - 1)),
    );
  }
}
