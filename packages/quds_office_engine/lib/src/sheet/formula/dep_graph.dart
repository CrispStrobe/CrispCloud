import '../model/sml_analysis.dart';
import '../model/sml_workbook.dart';
import 'formula_ast.dart';
import 'formula_eval.dart';
import 'formula_functions.dart';

/// Dependency graph with topological recalculation and cycle detection.
class FormulaDepGraph {
  /// FormulaDepGraph API.
  FormulaDepGraph(this.workbook);

  /// workbook API.
  final SmlWorkbook workbook;
  final Map<String, Set<String>> _deps = <String, Set<String>>{};
  final Set<String> _unmodeledDependencies = <String>{};

  /// circular API.
  final Set<String> circular = <String>{};

  /// rebuild API.
  void rebuild() {
    _deps.clear();
    _unmodeledDependencies.clear();
    circular.clear();
    for (final SmlWorksheet sheet in workbook.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        if (cell.formula == null || cell.formula!.isEmpty) {
          continue;
        }
        final String key = _key(sheet, cell.ref);
        final dependencies = _collect(cell.formula!, sheet);
        _deps[key] = dependencies ?? <String>{};
        if (dependencies == null) _unmodeledDependencies.add(key);
      }
    }
  }

  /// Recalculates in evaluation order. Returns the formula cells visited.
  ///
  /// When [keepCachedOnUnsupported] is true, a formula this engine cannot
  /// evaluate (`#NAME?` for an unknown function, `#ERROR!` for unsupported
  /// reference syntax or incomplete parsing) keeps its imported value and type.
  /// A dependent formula receives the unsupported marker, never the retained
  /// stale cache. Dynamic references use this same resolver and cycle detector.
  List<String> recalculate({bool keepCachedOnUnsupported = true}) {
    rebuild();
    final List<String> order = <String>[];
    final List<String> path = <String>[];
    final Map<String, int> visiting = <String, int>{};
    final Map<String, Object?> results = <String, Object?>{};

    Object? evaluateCell(SmlWorksheet sheet, SmlCellRef ref) {
      final key = _key(sheet, ref);
      if (results.containsKey(key)) return results[key];
      final SmlCell cell = sheet.cell(ref);
      if (cell.formula == null || cell.formula!.isEmpty) {
        final value = cell.value;
        return cell.type == SmlCellType.error && value is String
            ? FormulaErrorValue(value)
            : value;
      }
      final cycleStart = visiting[key];
      if (cycleStart != null) {
        circular.addAll(path.skip(cycleStart));
        return const FormulaErrorValue('#CIRC!');
      }
      visiting[key] = path.length;
      path.add(key);
      Object? result;
      try {
        result = _unmodeledDependencies.contains(key)
            ? const FormulaErrorValue(
                '#ERROR! Unmodeled formula dependencies',
                isUnsupported: true,
              )
            : evaluateFormulaForCache(
                cell.formula!,
                FormulaContext(
                  workbook: workbook,
                  sheet: sheet,
                  origin: ref,
                  resolveCell: evaluateCell,
                ),
              );
        result = FormulaErrorValue.unsupportedIn(result) ?? result;
        // An IFERROR inside a cycle cannot turn a participant's recursion
        // error into a plausible value. A non-cyclic dependent may handle it.
        if (circular.contains(key)) {
          result = const FormulaErrorValue('#CIRC!');
        }
      } finally {
        visiting.remove(key);
        path.removeLast();
      }
      results[key] = result;
      order.add(key);
      return result;
    }

    for (final key in _deps.keys) {
      final (sheet, ref) = _parse(key);
      evaluateCell(sheet, ref);
    }

    // Keep original caches intact during evaluation. Traversal order can never
    // turn a retained unsupported result into fresh input for another formula.
    for (final key in order) {
      final (sheet, ref) = _parse(key);
      final cell = sheet.cell(ref);
      final result = results[key];
      if (keepCachedOnUnsupported &&
          result is FormulaErrorValue &&
          result.isUnsupported &&
          cell.value != null) {
        continue;
      }
      cell.value = FormulaErrorValue.unwrap(result);
      cell.type = result is FormulaErrorValue
          ? SmlCellType.error
          : result is String
          ? SmlCellType.string
          : SmlCellType.formula;
    }
    return order;
  }

  Set<String>? _collect(String formula, SmlWorksheet sheet) {
    final Set<String> out = <String>{};
    void walk(FormulaNode node, [Set<String> bindings = const {}]) {
      switch (node) {
        case CellNode(:final SmlCellRef ref, :final String? sheetName):
          final SmlWorksheet? target = sheetName == null
              ? sheet
              : workbook.sheetByName(sheetName);
          if (target != null) out.add(_key(target, ref));
        case RangeNode(:final SmlRange range, :final String? sheetName):
          final SmlWorksheet? target = sheetName == null
              ? sheet
              : workbook.sheetByName(sheetName);
          if (target != null) {
            for (final SmlCellRef ref in range.cells) {
              out.add(_key(target, ref));
            }
          }
        case BinaryNode(:final FormulaNode left, :final FormulaNode right):
          walk(left, bindings);
          walk(right, bindings);
        case UnaryNode(:final FormulaNode expr):
          walk(expr, bindings);
        case CallNode(:final String name, :final List<FormulaNode> args):
          final function = FormulaFunctions.stripFutureFunctionPrefix(name);
          if (function == 'IF' && args.isNotEmpty) {
            if (args.first case LiteralNode(value: final bool condition)) {
              // A constant predicate has one reachable branch. Opaque names in
              // the unused branch cannot discard the selected branch's deps.
              final selected = condition ? 1 : 2;
              if (args.length > selected) walk(args[selected], bindings);
              break;
            }
          }
          if ((function == 'IFERROR' || function == 'IFNA') &&
              args.isNotEmpty &&
              args.first is LiteralNode) {
            // Parsed scalar literals cannot be native errors; quoted error
            // spellings are ordinary text and do not select the fallback.
            break;
          }
          if (function == 'LET' && args.length >= 3 && args.length.isOdd) {
            final local = {...bindings};
            for (var i = 0; i < args.length - 1; i += 2) {
              walk(args[i + 1], local);
              final binding = args[i];
              if (binding is NamedRangeNode && binding.sheetName == null) {
                local.add(binding.name.toUpperCase());
              }
            }
            walk(args.last, local);
            break;
          }
          for (final FormulaNode a in args) {
            walk(a, bindings);
          }
        case LiteralNode():
          break;
        case NamedRangeNode():
          if (node.sheetName == null &&
              bindings.contains(node.name.toUpperCase())) {
            break;
          }
          final named = node.resolve(workbook, sheet);
          if (named is! SmlNamedRange) {
            if (named is SmlFormulaName || node.sheetName != null) {
              // Validate only scalar/opaque definitions. An unsupported name
              // means the whole expression must keep its authored cache, not
              // acquire partial dependencies that could manufacture a cycle.
              node.eval(
                FormulaContext(
                  workbook: workbook,
                  sheet: sheet,
                  origin: const SmlCellRef(0, 0),
                ),
              );
            }
            break;
          }
          final target = workbook.sheetByName(named.sheetName);
          if (target != null) {
            for (final SmlCellRef ref in named.range.cells) {
              out.add(_key(target, ref));
            }
          }
      }
    }

    try {
      walk(parseFormula(formula));
    } on Object {
      // Never calculate against an incomplete dependency set. In particular,
      // a dynamic conditional containing an opaque name remains a cache
      // fallback even if direct scalar evaluation can choose another branch.
      return null;
    }
    return out;
  }

  static String _key(SmlWorksheet sheet, SmlCellRef ref) =>
      '${sheet.name}!${ref.a1}';

  (SmlWorksheet, SmlCellRef) _parse(String key) {
    final int bang = key.lastIndexOf('!');
    final SmlWorksheet sheet =
        workbook.sheetByName(key.substring(0, bang)) ?? workbook.firstSheet;
    return (sheet, SmlCellRef.parse(key.substring(bang + 1)));
  }
}
