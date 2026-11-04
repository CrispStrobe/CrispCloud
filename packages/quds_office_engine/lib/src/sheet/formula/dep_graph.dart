import '../model/sml_analysis.dart';
import '../model/sml_workbook.dart';
import 'formula_ast.dart';
import 'formula_eval.dart';

/// Dependency graph with topological recalculation and cycle detection.
class FormulaDepGraph {
  /// FormulaDepGraph API.
  FormulaDepGraph(this.workbook);

  /// workbook API.
  final SmlWorkbook workbook;
  final Map<String, Set<String>> _deps = <String, Set<String>>{};

  /// circular API.
  final Set<String> circular = <String>{};

  /// rebuild API.
  void rebuild() {
    _deps.clear();
    circular.clear();
    for (final SmlWorksheet sheet in workbook.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        if (cell.formula == null || cell.formula!.isEmpty) {
          continue;
        }
        final String key = _key(sheet, cell.ref);
        _deps[key] = _collect(cell.formula!, sheet);
      }
    }
  }

  /// Recalculates in dependency order. Returns cells that were updated.
  ///
  /// When [keepCachedOnUnsupported] is true, a formula this engine cannot
  /// evaluate (`#NAME?` for an unknown function, `#ERROR!` for syntax it
  /// cannot parse) keeps the value saved in the file instead of replacing
  /// it with the error.
  List<String> recalculate({bool keepCachedOnUnsupported = true}) {
    rebuild();
    final List<String> order = <String>[];
    final Set<String> visiting = <String>{};
    final Set<String> visited = <String>{};

    void visit(String node) {
      if (visited.contains(node)) {
        return;
      }
      if (!visiting.add(node)) {
        circular.add(node);
        return;
      }
      for (final String d in _deps[node] ?? const <String>{}) {
        visit(d);
      }
      visiting.remove(node);
      visited.add(node);
      order.add(node);
    }

    for (final String node in _deps.keys) {
      visit(node);
    }

    for (final String key in order) {
      final (SmlWorksheet sheet, SmlCellRef ref) = _parse(key);
      final SmlCell cell = sheet.cell(ref);
      if (circular.contains(key)) {
        cell.value = '#CIRC!';
        cell.type = SmlCellType.error;
        continue;
      }
      if (cell.formula == null || cell.formula!.isEmpty) {
        continue;
      }
      final Object? cached = cell.value;
      final Object? result = evaluateFormula(
        cell.formula!,
        FormulaContext(workbook: workbook, sheet: sheet, origin: ref),
      );
      if (keepCachedOnUnsupported &&
          _unsupported(result) &&
          cached != null &&
          !_unsupported(cached)) {
        continue;
      }
      cell.value = result;
      if (cell.formula != null && cell.formula!.isNotEmpty) {
        if (cell.value is String &&
            (cell.value as String).startsWith('#') &&
            cell.value != cell.formula) {
          cell.type = SmlCellType.error;
        } else {
          cell.type = SmlCellType.formula;
        }
      } else if (cell.value is num) {
        cell.type = SmlCellType.number;
      } else if (cell.value is bool) {
        cell.type = SmlCellType.boolean;
      } else {
        cell.type = SmlCellType.string;
      }
    }
    return order;
  }

  Set<String> _collect(String formula, SmlWorksheet sheet) {
    final Set<String> out = <String>{};
    void walk(FormulaNode node) {
      switch (node) {
        case CellNode(:final SmlCellRef ref, :final String? sheetName):
          final SmlWorksheet target = sheetName == null
              ? sheet
              : (workbook.sheetByName(sheetName) ?? sheet);
          out.add(_key(target, ref));
        case RangeNode(:final SmlRange range, :final String? sheetName):
          final SmlWorksheet target = sheetName == null
              ? sheet
              : (workbook.sheetByName(sheetName) ?? sheet);
          for (final SmlCellRef ref in range.cells) {
            out.add(_key(target, ref));
          }
        case BinaryNode(:final FormulaNode left, :final FormulaNode right):
          walk(left);
          walk(right);
        case UnaryNode(:final FormulaNode expr):
          walk(expr);
        case CallNode(:final List<FormulaNode> args):
          for (final FormulaNode a in args) {
            walk(a);
          }
        case LiteralNode():
          break;
        case NamedRangeNode(:final String name):
          final SmlNamedRange? named = workbook.namedRange(name);
          if (named == null) {
            break;
          }
          final SmlWorksheet target =
              workbook.sheetByName(named.sheetName) ?? sheet;
          for (final SmlCellRef ref in named.range.cells) {
            out.add(_key(target, ref));
          }
      }
    }

    try {
      walk(parseFormula(formula));
    } on Object {
      // Broken formula — no deps.
    }
    return out;
  }

  static bool _unsupported(Object? value) =>
      value is String && (value == '#NAME?' || value.startsWith('#ERROR!'));

  static String _key(SmlWorksheet sheet, SmlCellRef ref) =>
      '${sheet.name}!${ref.a1}';

  (SmlWorksheet, SmlCellRef) _parse(String key) {
    final int bang = key.indexOf('!');
    final SmlWorksheet sheet =
        workbook.sheetByName(key.substring(0, bang)) ?? workbook.firstSheet;
    return (sheet, SmlCellRef.parse(key.substring(bang + 1)));
  }
}
