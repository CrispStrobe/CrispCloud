import '../formula/formula_eval.dart';
import 'sml_workbook.dart';

/// Goal Seek / one-variable solver.
abstract final class SmlSolver {
  /// Adjusts [changing] until [target] evaluates to [goal].
  static bool goalSeek({
    required SmlWorkbook workbook,
    required SmlWorksheet sheet,
    required SmlCellRef target,
    required SmlCellRef changing,
    required double goal,
    double tolerance = 1e-6,
    int iterations = 40,
  }) {
    final SmlCell change = sheet.cell(changing);
    var low = -1e6;
    var high = 1e6;
    var value = change.asNumber ?? 0;
    for (int i = 0; i < iterations; i++) {
      change
        ..formula = null
        ..type = SmlCellType.number
        ..value = value;
      FormulaEvaluator.recalculate(workbook);
      final double got = sheet.cell(target).asNumber ?? 0;
      if ((got - goal).abs() <= tolerance) {
        return true;
      }
      if (got < goal) {
        low = value;
      } else {
        high = value;
      }
      value = (low + high) / 2;
    }
    change
      ..type = SmlCellType.number
      ..value = value;
    FormulaEvaluator.recalculate(workbook);
    return ((sheet.cell(target).asNumber ?? 0) - goal).abs() <= tolerance * 10;
  }
}
