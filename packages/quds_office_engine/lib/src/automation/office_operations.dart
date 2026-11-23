import 'dart:typed_data';

import '../opc/office_isolate_save.dart';
import '../opc/opc_archive.dart';
import '../opc/zip/zip_reader.dart';
import '../sheet/formula/formula_ast.dart';
import '../sheet/formula/formula_eval.dart';
import '../sheet/formula/formula_functions.dart';
import '../sheet/model/sml_analysis.dart';
import '../sheet/model/sml_workbook.dart';
import '../sheet/serial/sheet_serial.dart';
import '../slide/model/pml_presentation.dart';
import '../slide/serial/slide_serial.dart';
import '../word/model/wml_document.dart';
import '../word/model/word_table.dart';
import '../word/model/word_tree.dart';
import '../word/serial/word_deserializer.dart';
import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';
import 'operations/inspect_word.dart';
import 'operations/sheet_steps.dart';
import 'operations/slide_steps.dart';
import 'operations/step_input.dart';
import 'operations/word_steps.dart';
import 'operations/word_structure_steps.dart';
import 'operations/word_table_cell_text_steps.dart';

export 'operations/step_input.dart' show OfficeMacroAssetResolver;

/// The document family targeted by a macro. Macro-enabled packages retain
/// their native package type and opaque VBA parts within these families.
enum OfficeMacroFormat { docx, xlsx, pptx }

/// A host execution budget was exhausted before allocating more document work.
final class OfficeOperationLimitException implements Exception {
  const OfficeOperationLimitException(this.message);
  final String message;

  @override
  String toString() => 'OfficeOperationLimitException: $message';
}

/// An admitted, detached document owned only by a macro execution.
///
/// The model is never exposed. Initial and final admission checks cover native
/// metadata; intermediate calls use the same validators and handlers without
/// reparsing every unchanged XML part for every step. Hosts that already own a
/// mutable model must continue to use [OfficeOperationCatalog.apply].
final class OfficeOperationDocument {
  OfficeOperationDocument._(
    this._document,
    this.maxCellVisits,
    this._maxExpandedBytes,
    this._maxPackageParts,
  );

  /// Opens and admits an isolated model before any operation can run.
  factory OfficeOperationDocument.open(
    Uint8List bytes,
    OfficeMacroFormat format, {
    int maxCellVisits = 100000,
    int maxExpandedBytes = 128 * 1024 * 1024,
    int maxPackageParts = 4096,
  }) {
    if (maxCellVisits < 1) {
      throw ArgumentError.value(maxCellVisits, 'maxCellVisits');
    }
    final document = OfficeOperationCatalog.open(
      bytes,
      format,
      maxExpandedBytes: maxExpandedBytes,
      maxPackageParts: maxPackageParts,
    );
    OfficeOperationCatalog.assertEditable(document);
    return OfficeOperationDocument._(
      document,
      maxCellVisits,
      maxExpandedBytes,
      maxPackageParts,
    );
  }

  final Object _document;
  final int maxCellVisits;
  final int _maxExpandedBytes;
  final int _maxPackageParts;
  int _cellVisits = 0;
  bool _needsRecalculation = false;

  /// Applies one command to the privately owned model after charging its work.
  void apply(
    String tool,
    Map<String, Object?> arguments, {
    OfficeMacroAssetResolver? resolveAsset,
  }) {
    final values = _operationValues(_document, tool, arguments);
    _chargeWork(values);
    _dispatchOperation(_document, values, resolveAsset: resolveAsset);
    if (_document is SmlWorkbook &&
        const <String>{
          'cellValue',
          'cellFormula',
          'mergeCells',
          'renameSheet',
          'sheetOrder',
        }.contains(values['op'])) {
      _needsRecalculation = true;
    }
  }

  /// Rechecks the final document, optionally recalculates spreadsheet formulas,
  /// and serializes. No document state is published by this object itself.
  Future<Uint8List> save({bool recalculate = false}) async {
    OfficeOperationCatalog.assertEditable(_document);
    if (recalculate && _needsRecalculation && _document is SmlWorkbook) {
      _OfficeFormulaPreflight(_document, _chargeCells).run();
      FormulaEvaluator.recalculate(_document);
    }
    final output = await _saveDocument(_document);
    return _boundedPackage(output, _maxExpandedBytes, _maxPackageParts);
  }

  void _chargeWork(Map<String, Object?> values) {
    final step = StepInput(values);
    final operation = step.string('op');
    var rows = 1;
    var columns = 1;
    if (_document is SmlWorkbook && operation == 'mergeCells') {
      final range = _boundedRange(step.string('range'));
      rows = range.maxRow - range.minRow + 1;
      columns = range.maxCol - range.minCol + 1;
    } else if (_document is WmlDocument) {
      if (operation == 'tableAdd') {
        rows = step.integer('rows', min: 1, max: 1000);
        columns = step.integer('columns', min: 1, max: 63);
      } else if (const <String>{
        'tableRowInsert',
        'tableColumnInsert',
        'tableUnmerge',
      }.contains(operation)) {
        final table = step.item(
          'table',
          bodyBlocks(_document).whereType<WmlTable>(),
        );
        if (operation != 'tableRowInsert') rows = table.rows.length;
        if (operation != 'tableColumnInsert') {
          columns = WordTable.columnCount(table);
        }
      }
    }
    _chargeCells(rows, columns);
  }

  void _chargeCells(int rows, int columns) {
    // Divide before multiplication so malicious imported grid spans cannot
    // overflow an integer and turn a huge request into a small/negative cost.
    final remaining = maxCellVisits - _cellVisits;
    if (rows < 1 || columns < 1) {
      rows = 1;
      columns = 1;
    }
    if (columns > remaining || rows > remaining ~/ columns) {
      throw const OfficeOperationLimitException(
        'Macro exceeds its cumulative cell-work budget',
      );
    }
    _cellVisits += rows * columns;
  }
}

/// Bounds known expansion paths before entering the synchronous evaluator.
/// This is deliberately a macro admission policy, not a second evaluator or
/// a promise to sandbox every existing spreadsheet function.
final class _OfficeFormulaPreflight {
  _OfficeFormulaPreflight(this._workbook, this._charge);

  final SmlWorkbook _workbook;
  final void Function(int rows, int columns) _charge;
  static const _maxSource = 8192;
  static const _maxTokens = 512;
  static const _maxDepth = 64;
  static const _maxGeneratedText = 32767;

  void run() {
    // Resolving a structured reference may materialize an absent header cell.
    // Collect formulas first so that resolution cannot invalidate iteration.
    final formulas = <(SmlWorksheet, String)>[];
    for (final sheet in _workbook.sheets) {
      for (final cell in sheet.allCells) {
        final formula = cell.formula;
        if (formula != null && formula.isNotEmpty) {
          _charge(1, 1);
          formulas.add((sheet, formula));
        }
      }
    }
    for (final (sheet, formula) in formulas) {
      final node = _parse(formula);
      if (node != null) _visit(node, sheet, const <String>{}, 1);
    }
  }

  FormulaNode? _parse(String formula) {
    if (formula.length > _maxSource) {
      throw const OfficeOperationLimitException(
        'Macro recalculation formula exceeds 8192 source code units',
      );
    }
    _charge(1, (formula.length + 31) ~/ 32);
    try {
      final tokens = FormulaLexer(formula, strict: true).tokenize();
      if (tokens.length > _maxTokens) {
        throw const OfficeOperationLimitException(
          'Macro recalculation formula exceeds 512 lexer tokens',
        );
      }
      _charge(1, tokens.length);
      var depth = 0;
      for (final token in tokens) {
        if (token.kind == FormulaTokenKind.lparen) {
          if (++depth > _maxDepth) _tooDeep();
        } else if (token.kind == FormulaTokenKind.rparen) {
          depth--;
        } else if (token.kind == FormulaTokenKind.cell ||
            token.kind == FormulaTokenKind.range) {
          // Validate coordinates before the engine's integer parser sees an
          // arbitrarily long column/row spelling, including qualified refs.
          final ref = token.lexeme.substring(token.lexeme.lastIndexOf('!') + 1);
          try {
            _boundedRange(ref);
          } on ArgumentError {
            throw const OfficeOperationLimitException(
              'Macro recalculation references cells outside Excel bounds',
            );
          }
        }
      }
      return FormulaParser(tokens).parse();
    } on FormatException {
      // Ordinary unsupported/incomplete native formulas retain their caches
      // through the existing evaluator. Explicit resource limits propagate.
      return null;
    } on UnsupportedError {
      return null;
    }
  }

  Never _tooDeep() => throw const OfficeOperationLimitException(
    'Macro recalculation formula exceeds 64 syntax levels',
  );

  void _visit(
    FormulaNode node,
    SmlWorksheet sheet,
    Set<String> bindings,
    int depth,
  ) {
    if (depth > _maxDepth) _tooDeep();
    _charge(1, 1);
    switch (node) {
      case LiteralNode():
      case ExternalCellNode():
        break;
      case CellNode(:final ref):
        _range(SmlRange(ref, ref));
      case RangeNode(:final range):
        _range(range);
      case BinaryNode(:final left, :final right):
        _visit(left, sheet, bindings, depth + 1);
        _visit(right, sheet, bindings, depth + 1);
      case UnaryNode(:final expr):
        _visit(expr, sheet, bindings, depth + 1);
      case NamedRangeNode():
        if (node.sheetName == null &&
            bindings.contains(node.name.toUpperCase())) {
          break;
        }
        if (node.sheetName == null) {
          // SmlTable.resolveRef scans column headers. Charge and validate that
          // scan before invoking it, then charge the resolved data rectangle.
          final tableName = node.name.split('[').first.trim().toUpperCase();
          for (final table in sheet.tables) {
            _charge(1, 1);
            if (table.name.toUpperCase() != tableName) continue;
            _validateRange(table.range);
            if (node.name.contains('[')) {
              _charge(1, table.range.maxCol - table.range.minCol + 1);
            }
          }
          final structured = SmlTable.resolveRef(sheet, node.name);
          if (structured != null) {
            _range(structured);
            break;
          }
        }
        try {
          final named = node.resolve(_workbook, sheet);
          if (named is SmlNamedRange) _range(named.range);
        } on UnsupportedError {
          // Ambiguous and unmodeled names follow native cache preservation.
        }
      case CallNode(:final name, :final args):
        final function = FormulaFunctions.stripFutureFunctionPrefix(
          name,
        ).toUpperCase();
        _call(function, args, bindings);
        if (function == 'LET' && args.length >= 3 && args.length.isOdd) {
          final locals = Set<String>.of(bindings);
          for (var index = 0; index < args.length - 1; index += 2) {
            final binding = args[index];
            final String local;
            if (binding is NamedRangeNode) {
              local = binding.name.toUpperCase();
            } else if (binding is LiteralNode && binding.value is String) {
              local = (binding.value! as String).toUpperCase();
              if (locals.contains(local)) {
                throw const OfficeOperationLimitException(
                  'Macro recalculation requires static LET binding names',
                );
              }
            } else {
              throw const OfficeOperationLimitException(
                'Macro recalculation requires static LET binding names',
              );
            }
            _visit(args[index + 1], sheet, locals, depth + 1);
            locals.add(local);
          }
          _visit(args.last, sheet, locals, depth + 1);
        } else {
          for (final arg in args) {
            _visit(arg, sheet, bindings, depth + 1);
          }
        }
    }
  }

  void _validateRange(SmlRange range) {
    if (range.minRow < 0 ||
        range.minCol < 0 ||
        range.maxRow >= 1048576 ||
        range.maxCol >= 16384) {
      throw const OfficeOperationLimitException(
        'Macro recalculation references cells outside Excel bounds',
      );
    }
  }

  void _range(SmlRange range) {
    _validateRange(range);
    _charge(range.maxRow - range.minRow + 1, range.maxCol - range.minCol + 1);
  }

  void _call(String function, List<FormulaNode> args, Set<String> bindings) {
    switch (function) {
      case 'OFFSET':
      case 'INDIRECT':
        throw OfficeOperationLimitException(
          'Macro recalculation cannot bound dynamic $function references',
        );
      case 'SEQUENCE':
        // The evaluator clamps rows to 100 and columns to 50, including when
        // dimensions are calculated. Charge that ceiling without evaluating.
        _charge(100, 50);
      case 'REPT':
        if (args.length < 2) break;
        final text = _literal(args[0], function, bindings);
        final count =
            asFormulaNumber(_literal(args[1], function, bindings)) ?? 0;
        if (!count.isFinite || count < 0 || count > _maxGeneratedText) {
          _textLimit(function);
        }
        final length = formulaString(text).length;
        final repeats = count.toInt();
        if (length > 0 && repeats > _maxGeneratedText ~/ length) {
          _textLimit(function);
        }
        _charge(1, repeats);
        _charge(1, length * repeats);
      case 'SUBSTITUTE':
        if (args.isEmpty) break;
        final base = formulaString(_literal(args[0], function, bindings));
        final replacement = args.length > 2
            ? formulaString(_literal(args[2], function, bindings))
            : '';
        if (args.length > 1) _literal(args[1], function, bindings);
        // Replacing an empty match can insert at every boundary. This upper
        // bound also covers ordinary literal matches without constructing the
        // resulting string just to inspect its size.
        if (base.length > _maxGeneratedText ||
            (replacement.isNotEmpty &&
                base.length + 1 >
                    (_maxGeneratedText - base.length) ~/ replacement.length)) {
          _textLimit(function);
        }
        _charge(1, base.length + (base.length + 1) * replacement.length);
      case 'NETWORKDAYS':
        if (args.length < 2) break;
        final start = asFormulaNumber(_literal(args[0], function, bindings));
        final end = asFormulaNumber(_literal(args[1], function, bindings));
        if (start == null || end == null) {
          throw const OfficeOperationLimitException(
            'Macro recalculation NETWORKDAYS requires numeric literal dates',
          );
        }
        if (!start.isFinite ||
            !end.isFinite ||
            start.abs() > 100000000 ||
            end.abs() > 100000000) {
          throw const OfficeOperationLimitException(
            'Macro recalculation date is outside supported bounds',
          );
        }
        _charge(1, (end - start).abs().ceil() + 2);
    }
  }

  Object? _literal(FormulaNode node, String function, Set<String> bindings) {
    if (node is LiteralNode) {
      final value = node.value;
      if (value is! String || !bindings.contains(value.toUpperCase())) {
        return value;
      }
      // LiteralNode.eval resolves quoted strings against active LET bindings.
      // A quoted local is therefore just as dynamic as a NamedRangeNode.
    }
    if (node case UnaryNode(:final op, expr: final LiteralNode literal)) {
      final number = asFormulaNumber(_literal(literal, function, bindings));
      if (number != null) return op == '-' ? -number : number;
    }
    throw OfficeOperationLimitException(
      'Macro recalculation requires literal $function operands to bound work',
    );
  }

  Never _textLimit(String function) => throw OfficeOperationLimitException(
    'Macro recalculation $function output exceeds 32767 code units',
  );
}

/// One portable operation catalog shared by macros, MCP hosts, and the
/// existing fidelity tooling. It has no filesystem or network authority.
///
/// [apply] edits the supplied model. Hosts requiring whole-macro atomicity
/// should open a detached copy and publish its saved bytes only on success.
/// The low-level legacy handlers remain available to the fidelity tools;
/// application hosts should use this catalog's admission checks.
abstract final class OfficeOperationCatalog {
  /// Accepted argument keys by operation name, without the family prefix.
  /// Both the map and its lists are immutable compile-time constants.
  static Map<String, List<String>> fields(OfficeMacroFormat format) =>
      switch (format) {
        OfficeMacroFormat.docx => wordOperations,
        OfficeMacroFormat.xlsx => sheetOperations,
        OfficeMacroFormat.pptx => slideOperations,
      };

  /// Resolves the family of a supported in-memory document.
  static OfficeMacroFormat formatOf(Object document) => switch (document) {
    WmlDocument() => OfficeMacroFormat.docx,
    SmlWorkbook() => OfficeMacroFormat.xlsx,
    PmlPresentation() => OfficeMacroFormat.pptx,
    _ => throw ArgumentError('Unsupported Office document model'),
  };

  /// Opens a detached model, verifies the requested family, and retains the
  /// existing refusal to rewrite a digitally signed package.
  static Object open(
    Uint8List bytes,
    OfficeMacroFormat format, {
    int maxExpandedBytes = 128 * 1024 * 1024,
    int maxPackageParts = 4096,
  }) {
    final source = _boundedPackage(bytes, maxExpandedBytes, maxPackageParts);
    final package = OpcPackage.openBytes(source);
    final expected = switch (format) {
      OfficeMacroFormat.docx => OpcPackageKind.word,
      OfficeMacroFormat.xlsx => OpcPackageKind.sheet,
      OfficeMacroFormat.pptx => OpcPackageKind.slide,
    };
    if (package.kind != expected) {
      throw FormatException('Input is not a ${format.name} document family');
    }
    package.assertUnsignedForEditing();
    return switch (format) {
      OfficeMacroFormat.docx => WordDeserializer().read(package),
      OfficeMacroFormat.xlsx => SheetDeserializer().read(package),
      OfficeMacroFormat.pptx => SlideDeserializer().read(package),
    };
  }

  /// Executes one canonical tool name, such as `xlsx.cellValue`.
  ///
  /// `op` is reserved for the legacy step format and is never accepted in
  /// [arguments]. Image operations require an explicit [resolveAsset]; an
  /// argument named `file` is only a host lookup key in this portable API.
  static void apply(
    Object document,
    String tool,
    Map<String, Object?> arguments, {
    OfficeMacroAssetResolver? resolveAsset,
  }) {
    final values = _operationValues(document, tool, arguments);
    // Cell operations accept public in-memory models as well as detached
    // package sessions. Reject shared/cyclic ownership before the ordinary
    // document admission walks the tree. Other tools keep their contracts.
    if (document is WmlDocument &&
        (values['op'] == 'tableCellRangeText' ||
            values['op'] == 'tableCellRangeInsertBefore' ||
            values['op'] == 'tableCellRangeInsertAfter' ||
            values['story'] == 'tableCell')) {
      checkWordTableCellRangeOwnership(document);
    }
    assertEditable(document);
    _dispatchOperation(document, values, resolveAsset: resolveAsset);
  }

  /// Returns the same deterministic inspection projection as the CLI.
  static Map<String, Object?> inspect(Object document) => switch (document) {
    WmlDocument() => inspectWord(document),
    SmlWorkbook() => inspectSheet(document),
    PmlPresentation() => inspectSlides(document),
    _ => throw ArgumentError('Unsupported Office document model'),
  };

  /// Serializes an admitted model. Workbook formula caches are preserved;
  /// callers may explicitly recalculate after completing their edits.
  static Future<Uint8List> save(Object document) {
    assertEditable(document);
    return _saveDocument(document);
  }

  /// Refuses editing that the operation layer cannot faithfully authorize or
  /// record: document/worksheet protection, locked Word controls, tracked
  /// changes, password-to-modify metadata, and package signatures.
  ///
  /// This is deliberately conservative: one protected worksheet/control
  /// makes the complete macro target unavailable. Hosts must also enforce
  /// their own readonly mode before allowing a macro to run.
  static void assertEditable(Object document) {
    final format = formatOf(document);
    final OpcPackage? package;
    switch (document) {
      case WmlDocument():
        if (document.restrictEditing ||
            document.protectionFormattingRestricted ||
            document.trackRevisions) {
          throw UnsupportedError(
            'Macros cannot edit restricted or change-tracked Word documents',
          );
        }
        _assertWordControls(document);
        package = document.package;
      case SmlWorkbook():
        if (document.sheets.any(
          (sheet) => sheet.protection?.enabled ?? false,
        )) {
          throw UnsupportedError('Macros cannot edit protected worksheets');
        }
        package = document.package;
      case PmlPresentation():
        package = document.package;
      default:
        throw ArgumentError('Unsupported Office document model');
    }
    if (package == null) return;
    package.assertUnsignedForEditing();
    for (final part in package.parts) {
      final contentType = part.contentType.toLowerCase();
      final xmlContentType =
          contentType == 'application/xml' ||
          contentType == 'text/xml' ||
          contentType.endsWith('+xml');
      if (!xmlContentType && !part.uri.toLowerCase().endsWith('.xml')) {
        continue;
      }
      // Package parts are lazy; materialize only XML, never opaque VBA/media.
      _assertNativeXml(package.getPart(part.uri)!.readText(), format);
    }
  }
}

Map<String, Object?> _operationValues(
  Object document,
  String tool,
  Map<String, Object?> arguments,
) {
  final format = OfficeOperationCatalog.formatOf(document);
  final prefix = '${format.name}.';
  if (!tool.startsWith(prefix)) {
    throw ArgumentError('Tool $tool does not target ${format.name}');
  }
  final operation = tool.substring(prefix.length);
  final accepted = OfficeOperationCatalog.fields(format)[operation];
  if (accepted == null) throw ArgumentError('Unknown Office tool: $tool');
  if (arguments.containsKey('op')) {
    throw ArgumentError('Tool arguments must not contain the reserved op key');
  }
  final values = <String, Object?>{'op': operation, ...arguments};
  StepInput(values).fields(accepted);
  return values;
}

void _dispatchOperation(
  Object document,
  Map<String, Object?> values, {
  OfficeMacroAssetResolver? resolveAsset,
}) {
  switch (document) {
    case WmlDocument():
      applyStep(document, values, resolveAsset: resolveAsset);
    case SmlWorkbook():
      applySheetStep(document, values);
    case PmlPresentation():
      applySlideStep(document, values, resolveAsset: resolveAsset);
    default:
      throw ArgumentError('Unsupported Office document model');
  }
}

Future<Uint8List> _saveDocument(Object document) => switch (document) {
  WmlDocument() => OfficeIsolateSave.word(document),
  SmlWorkbook() => OfficeIsolateSave.workbook(document, recalculate: false),
  PmlPresentation() => OfficeIsolateSave.presentation(document),
  _ => throw ArgumentError('Unsupported Office document model'),
};

SmlRange _boundedRange(String value) {
  final parts = value.split(':');
  if (parts.length > 2) throw ArgumentError('Invalid cell range');
  SmlCellRef cell(String text) {
    if (!RegExp(r'^\$?[A-Za-z]{1,3}\$?[0-9]{1,7}$').hasMatch(text)) {
      throw ArgumentError('Cell outside Excel bounds: $text');
    }
    final reference = SmlCellRef.parse(text);
    if (reference.row < 0 ||
        reference.row >= SmlWorksheet.excelRowCount ||
        reference.col < 0 ||
        reference.col >= SmlWorksheet.excelColumnCount) {
      throw ArgumentError('Cell outside Excel bounds: $text');
    }
    return reference;
  }

  return SmlRange(cell(parts.first), cell(parts.last));
}

Uint8List _boundedPackage(
  Uint8List bytes,
  int maxExpandedBytes,
  int maxPackageParts,
) {
  if (maxExpandedBytes < 1 || maxPackageParts < 1) {
    throw ArgumentError('Package limits must be positive');
  }
  // Retain our own source: the successful preflight and subsequent model
  // opening must observe identical compressed bytes.
  final source = Uint8List.fromList(bytes);
  try {
    final zip = ZipReader.fromBytes(
      source,
      maxEntries: maxPackageParts,
      rejectDuplicateNames: true,
    );
    var declared = 0;
    for (final entry in zip.entries) {
      if (entry.isDirectory) continue;
      if (entry.uncompressedSize > maxExpandedBytes - declared) {
        throw const OfficeOperationLimitException(
          'Office package exceeds its expanded byte limit',
        );
      }
      declared += entry.uncompressedSize;
    }
    var expanded = 0;
    for (final entry in zip.entries) {
      if (entry.isDirectory) continue;
      // Check actual inflation too: a forged central-directory size must not
      // bypass the budget. Discard each verified payload before the next one.
      expanded += zip
          .read(entry.fileName, maxBytes: maxExpandedBytes - expanded)
          .length;
    }
  } on ZipLimitException catch (error) {
    throw OfficeOperationLimitException(error.toString());
  }
  return source;
}

bool _enabled(String? value, {bool whenAbsent = false}) =>
    value == null ? whenAbsent : !const {'0', 'false', 'off'}.contains(value);

void _assertNativeXml(String xml, OfficeMacroFormat format) {
  final reader = XmlPullReader(xml);
  while (reader.next()) {
    if (reader.eventType != XmlEventType.startElement) continue;
    final namespace = reader.namespaceUri;
    final local = reader.localName;
    switch (format) {
      case OfficeMacroFormat.docx:
        if (namespace != OfficeNamespaces.w &&
            namespace != 'http://purl.oclc.org/ooxml/wordprocessingml/main') {
          continue;
        }
        if ((local == 'lock' && reader.getAttribute('val') != 'unlocked') ||
            (local == 'trackRevisions' &&
                _enabled(reader.getAttribute('val'), whenAbsent: true)) ||
            (local == 'documentProtection' &&
                (_enabled(reader.getAttribute('enforcement')) ||
                    _enabled(reader.getAttribute('formatting')))) ||
            local == 'writeProtection') {
          throw UnsupportedError('Macros cannot edit protected Word content');
        }
      case OfficeMacroFormat.xlsx:
        if (namespace != OfficeNamespaces.x &&
            namespace != 'http://purl.oclc.org/ooxml/spreadsheetml/main') {
          continue;
        }
        if ((local == 'workbookProtection' && _workbookProtected(reader)) ||
            (local == 'sheetProtection' &&
                _enabled(reader.getAttribute('sheet'), whenAbsent: true)) ||
            (local == 'fileSharing' &&
                (reader.getAttribute('reservationPassword') != null ||
                    reader.getAttribute('hashValue') != null))) {
          throw UnsupportedError('Macros cannot edit protected workbooks');
        }
      case OfficeMacroFormat.pptx:
        if (namespace != OfficeNamespaces.p &&
            namespace != 'http://purl.oclc.org/ooxml/presentationml/main') {
          continue;
        }
        if (local == 'modifyVerifier') {
          throw UnsupportedError('Macros cannot edit protected presentations');
        }
    }
  }
}

bool _workbookProtected(XmlPullReader reader) {
  // Independent producers commonly emit <workbookProtection/> even when
  // no restriction is enabled. Empty/default-false metadata is not a lock.
  for (final name in ['lockStructure', 'lockWindows', 'lockRevision']) {
    if (_enabled(reader.getAttribute(name))) return true;
  }
  for (var index = 0; index < reader.attributeCount; index++) {
    final name = reader.attributeLocalName(index).toLowerCase();
    if ((name.contains('password') || name.contains('hash')) &&
        reader.attributeValue(index).isNotEmpty) {
      return true;
    }
  }
  return false;
}

void _assertWordControls(WmlDocument document) {
  final seen = <WmlContentControlData>{};
  void control(WmlContentControlData value) {
    if (seen.add(value)) _assertNativeXml(value.xml, OfficeMacroFormat.docx);
  }

  void paragraphs(Iterable<WmlParagraph> values) {
    for (final paragraph in values) {
      for (final wrapper in paragraph.contentControlWrappers) {
        control(wrapper);
      }
      for (final inline in paragraph.inlines) {
        if (inline is WmlContentControlBoundary) {
          control(inline.control);
        } else if (inline is WmlOpaqueInline) {
          _assertNativeXml(inline.content.xml, OfficeMacroFormat.docx);
        }
      }
    }
  }

  void blocks(Iterable<WmlBlock> values) {
    for (final block in WordTree.descendants(values)) {
      if (block is WmlContentControlBlock) {
        control(block.control);
      } else if (block is WmlOpaqueBlock) {
        _assertNativeXml(block.xml, OfficeMacroFormat.docx);
      }
    }
    paragraphs(WordTree.paragraphs(values));
  }

  for (final section in document.sections) {
    blocks(section.blocks);
    paragraphs([
      ...section.header,
      ...section.footer,
      ...section.firstHeader,
      ...section.firstFooter,
      ...section.evenHeader,
      ...section.evenFooter,
    ]);
    for (final story in section.preservedStories.values) {
      _assertNativeXml(story.xml, OfficeMacroFormat.docx);
    }
  }
  for (final note in [...document.footnotes, ...document.endnotes]) {
    blocks(note.blocks);
  }
  for (final comment in document.comments) {
    paragraphs(comment.paragraphs);
  }
}
