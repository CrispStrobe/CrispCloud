import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

import '../models/file_item.dart';
import 'file_integrity_service.dart';
import 'file_operation_service.dart';

const csvSpreadsheetInputLimit = 8 * 1024 * 1024;
const csvSpreadsheetCellLimit = 1000000;

bool supportsSpreadsheetTextImport(String name) =>
    RegExp(r'\.(csv|tsv)$', caseSensitive: false).hasMatch(name);

/// Use the shared Quds CSV parser to retain quoted multiline cells and blank rows.
List<List<String>> parseSpreadsheetText(String text, {String? delimiter}) {
  if (text.length > csvSpreadsheetInputLimit ||
      utf8.encode(text).length > csvSpreadsheetInputLimit) {
    throw const FormatException(
      'Spreadsheet import is limited to 8 MiB of text.',
    );
  }
  final rows = ReportCsv.parse(
    text,
    delimiter: delimiter ?? detectSpreadsheetDelimiter(text),
    keepEmptyRows: true,
  );
  var cells = 0;
  for (final row in rows) {
    cells += row.length;
    if (row.length > 16384 ||
        rows.length > 1048576 ||
        cells > csvSpreadsheetCellLimit) {
      throw const FormatException(
        'This table exceeds the spreadsheet import limit of 1,000,000 cells.',
      );
    }
  }
  return rows;
}

/// Count separators outside quotes in the first complete record. Embedded
/// separators and multiline quoted headings cannot select the wrong dialect.
String detectSpreadsheetDelimiter(String text) {
  final counts = <String, int>{',': 0, ';': 0, '\t': 0};
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted) {
      if (ch == '\r' || ch == '\n') break;
      if (counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
    }
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

Uint8List buildSpreadsheetCopy((List<List<String>>, bool) input) {
  final (rows, detectNumbers) = input;
  final workbook = SmlWorkbook();
  final sheet = workbook.sheets.single;
  SmlPowerQuery.fromRows(sheet, rows, detectNumbers: false);
  if (detectNumbers) {
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final number = _number(rows[r][c]);
        if (number != null) {
          sheet.cell(SmlCellRef(c, r))
            ..type = SmlCellType.number
            ..value = number;
        }
      }
    }
  }
  // CSV expressions remain literal text; importing never introduces formulas.
  return SheetSerializer().writeBytes(workbook, recalculate: false);
}

double? _number(String value) {
  if (!RegExp(r'^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$')
      .hasMatch(value)) {
    return null;
  }
  // Excel numbers have at most 15 significant decimal digits. Keep identifiers
  // and larger exact integers as text rather than rounding them on import.
  final mantissa = value.split(RegExp('[eE]')).first;
  if (mantissa.replaceAll(RegExp(r'[^0-9]'), '').length > 15) return null;
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite ? parsed : null;
}

/// Uses the same exclusive, read-back-verified publication boundary as other
/// conversion copies. Neither the original CSV nor an existing XLSX is replaced.
Future<FileItem> createSpreadsheetCopy({
  required FileOperationBackend backend,
  required String sourcePath,
  required String name,
  required Uint8List bytes,
}) async {
  final stem = name.split('.').first.toUpperCase();
  if (name.trim() != name ||
      !name.toLowerCase().endsWith('.xlsx') ||
      name.length <= 5 ||
      utf8.encode(name).length > 240 ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]').hasMatch(name) ||
      const {'CON', 'PRN', 'AUX', 'NUL'}.contains(stem) ||
      RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem)) {
    throw const FormatException('Choose a valid new XLSX filename.');
  }
  checkIntegrityCurrent(backend, null);
  if (!backend.paths.isAbsolute(sourcePath)) {
    throw StateError('The original file path could not be verified.');
  }
  final directory = backend.paths.dirname(sourcePath);
  final output = backend.paths.join(directory, name);
  if (backend.samePath(output, sourcePath) ||
      !backend.samePath(backend.paths.dirname(output), directory)) {
    throw StateError('Choose a new filename beside the original.');
  }
  final listed = await backend.list(directory);
  checkIntegrityCurrent(backend, null);
  if (listed.any(
    (file) => backend.samePath(
      file.path ?? backend.paths.join(directory, file.name),
      output,
    ),
  )) {
    throw StateError('A file already exists: $output');
  }
  await writeIntegrityBytes(backend, output, bytes, replace: false);
  final created = await backend.stat(output);
  checkIntegrityCurrent(backend, null);
  if (created == null || created.isFolder || created.isSymlink == true) {
    throw StateError('The new spreadsheet could not be verified after saving.');
  }
  return created.copyWith(path: output);
}
