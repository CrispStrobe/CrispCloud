import 'sml_workbook.dart';

/// Loads a delimited table into a worksheet (CSV helper — not full Power Query).
abstract final class SmlPowerQuery {
  /// Parses [csv] and writes rows starting at [origin].
  static SmlRange fromCsv(
    SmlWorksheet sheet,
    String csv, {
    SmlCellRef origin = const SmlCellRef(0, 0),
    String delimiter = ',',
  }) {
    final List<List<String>> rows = <List<String>>[];
    for (final String line in csv.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty && rows.isEmpty) {
        continue;
      }
      rows.add(_split(line, delimiter));
    }
    var maxCol = origin.col;
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        final SmlCell cell = sheet.cell(
          SmlCellRef(origin.col + c, origin.row + r),
        );
        final String raw = rows[r][c];
        final double? n = double.tryParse(raw);
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

  static List<String> _split(String line, String delimiter) {
    final List<String> out = <String>[];
    final StringBuffer cur = StringBuffer();
    var quoted = false;
    for (int i = 0; i < line.length; i++) {
      final String ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == delimiter && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }
}
