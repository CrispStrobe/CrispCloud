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

  /// Recalculates in dependency order. Returns cells that were updated.
  ///
  /// When [keepCachedOnUnsupported] is true, a formula this engine cannot
  /// evaluate (`#NAME?` for an unknown function, `#ERROR!` for unsupported
  /// reference syntax or incomplete parsing) keeps the value saved in the file instead of replacing
  /// it with the error.
  List<String> recalculate({bool keepCachedOnUnsupported = true}) {
    rebuild();
    final List<String> order = <String>[];
    final Set<String> visiting = <String>{};
    final List<String> path = <String>[];
    final Set<String> visited = <String>{};

    void visit(String node) {
      if (visited.contains(node)) {
        return;
      }
      if (!visiting.add(node)) {
        // Every participant must be marked before any old numeric cache is
        // consulted; marking only the first would leave stale values in peers.
        circular.addAll(path.skip(path.indexOf(node)));
        return;
      }
      path.add(node);
      for (final String d in _deps[node] ?? const <String>{}) {
        visit(d);
      }
      visiting.remove(node);
      path.removeLast();
      visited.add(node);
      order.add(node);
    }

    for (final String node in _deps.keys) {
      visit(node);
    }

    for (final String key in order) {
      final (SmlWorksheet sheet, SmlCellRef ref) = _parse(key);
      final SmlCell cell = sheet.cell(ref);
      if (_unmodeledDependencies.contains(key)) {
        if (keepCachedOnUnsupported && cell.value != null) continue;
        cell.value = '#ERROR! Unmodeled formula dependencies';
        cell.type = SmlCellType.error;
        continue;
      }
      if (circular.contains(key)) {
        cell.value = '#CIRC!';
        cell.type = SmlCellType.error;
        continue;
      }
      if (cell.formula == null || cell.formula!.isEmpty) {
        continue;
      }
      final Object? cached = cell.value;
      final Object? result = evaluateFormulaForCache(
        cell.formula!,
        FormulaContext(workbook: workbook, sheet: sheet, origin: ref),
      );
      if (keepCachedOnUnsupported &&
          result is FormulaErrorValue &&
          result.isUnsupported &&
          cached != null) {
        continue;
      }
      cell.value = FormulaErrorValue.unwrap(result);
      if (cell.formula != null && cell.formula!.isNotEmpty) {
        cell.type = result is FormulaErrorValue
            ? SmlCellType.error
            : result is String
            ? SmlCellType.string
            : SmlCellType.formula;
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
