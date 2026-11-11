import 'package:quds_office_engine/quds_office_engine.dart';
import 'step_input.dart';

const sheetOperations = <String, List<String>>{
  'cellValue': ['sheet', 'cell', 'value'],
  'cellFormula': ['sheet', 'cell', 'formula'],
  'cellFormat': ['sheet', 'cell', 'bold', 'color', 'fill', 'size', 'alignment'],
  'mergeCells': ['sheet', 'range'],
  'unmergeCells': ['sheet', 'range'],
  'freeze': ['sheet', 'rows', 'columns'],
  'renameSheet': ['sheet', 'name'],
  'sheetOrder': ['sheet', 'to'],
  'rowHeight': ['sheet', 'row', 'height'],
  'columnWidth': ['sheet', 'column', 'width'],
};

SmlCellRef _cell(String value) {
  final ref = SmlCellRef.parse(value);
  if (ref.row < 0 ||
      ref.row >= SmlWorksheet.excelRowCount ||
      ref.col < 0 ||
      ref.col >= SmlWorksheet.excelColumnCount) {
    throw ArgumentError('Cell outside Excel bounds: $value');
  }
  return ref;
}

SmlRange _range(String value) {
  final parts = value.split(':');
  if (parts.length > 2) throw ArgumentError('Invalid cell range');
  return SmlRange(_cell(parts.first), _cell(parts.last));
}

void applySheetStep(SmlWorkbook book, Map<String, Object?> values) {
  final s = StepInput(values);
  final op = s.string('op');
  final fields = sheetOperations[op];
  if (fields == null) throw ArgumentError('Unknown XLSX operation: $op');
  s.fields(fields);
  final sheet = s.item('sheet', book.sheets, fallback: 0);
  SmlCell cell() => sheet.cell(_cell(s.string('cell')));
  switch (op) {
    case 'cellValue':
      if (!s.has('value')) throw ArgumentError('cellValue requires value');
      final value = values['value'];
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool) {
        throw ArgumentError('Cell value must be scalar or null');
      }
      if (value is num && !value.isFinite) {
        throw ArgumentError('Cell value must be finite');
      }
      final target = cell();
      target.formula = null;
      target.value = value;
      target.type = value is String
          ? SmlCellType.string
          : value is bool
          ? SmlCellType.boolean
          : SmlCellType.number;
    case 'cellFormula':
      var formula = s.string('formula').trim();
      if (formula.startsWith('=')) formula = formula.substring(1);
      if (formula.isEmpty) throw ArgumentError('Formula must not be empty');
      cell()
        ..type = SmlCellType.formula
        ..formula = formula
        ..value = null;
    case 'cellFormat':
      final target = cell();
      if (s.has('bold')) target.fontBold = s.boolean('bold');
      if (s.has('color')) target.fontRgb = s.color('color');
      if (s.has('fill')) target.fillRgb = s.color('fill');
      if (s.has('size')) target.fontSize = s.number('size', min: 1, max: 409);
      if (s.has('alignment')) {
        target.horizontalAlign = SmlHAlign.values.byName(s.string('alignment'));
      }
    case 'mergeCells':
      final range = _range(s.string('range'));
      if (range.isSingleCell) {
        throw ArgumentError('Merge needs at least two cells');
      }
      sheet.mergeAndCenter(range);
    case 'unmergeCells':
      sheet.unmerge(_range(s.string('range')));
    case 'freeze':
      if (s.has('rows')) {
        sheet.freezeRows = s.integer(
          'rows',
          max: SmlWorksheet.excelRowCount - 1,
        );
      }
      if (s.has('columns')) {
        sheet.freezeCols = s.integer(
          'columns',
          max: SmlWorksheet.excelColumnCount - 1,
        );
      }
    case 'renameSheet':
      final name = s.string('name');
      if (name.isEmpty ||
          name.length > 31 ||
          RegExp(r'[\[\]:*?/\\]').hasMatch(name) ||
          name.startsWith("'") ||
          name.endsWith("'") ||
          book.sheets.any(
            (other) =>
                !identical(other, sheet) &&
                other.name.toLowerCase() == name.toLowerCase(),
          )) {
        throw ArgumentError('Invalid or duplicate worksheet name');
      }
      if (name != sheet.name && _referencesSheet(book, sheet.name)) {
        throw ArgumentError(
          'Cannot rename a sheet referenced by formulas, names, charts, or pivots',
        );
      }
      sheet.name = name;
    case 'sheetOrder':
      final at = s.integer('to', max: book.sheets.length - 1);
      book.sheets.remove(sheet);
      book.sheets.insert(at, sheet);
    case 'rowHeight':
      sheet.rowHeights[s.integer('row', max: SmlWorksheet.excelRowCount - 1)] =
          s.number('height', min: 8, max: 409);
    case 'columnWidth':
      sheet.columnWidths[s.integer(
        'column',
        max: SmlWorksheet.excelColumnCount - 1,
      )] = s.number(
        'width',
        min: 8,
        max: 800,
      );
  }
}

Map<String, Object?> inspectSheet(SmlWorkbook book) => <String, Object?>{
  'format': 'xlsx',
  'sheets': <Object?>[
    for (final sheet in book.sheets)
      <String, Object?>{
        'name': sheet.name,
        'freezeRows': sheet.freezeRows,
        'freezeColumns': sheet.freezeCols,
        'merges': <String>[for (final merge in sheet.merges) merge.a1],
        'cells': <Object?>[
          for (final cell
              in (sheet.allCells.toList()..sort(
                (a, b) => a.ref.row == b.ref.row
                    ? a.ref.col.compareTo(b.ref.col)
                    : a.ref.row.compareTo(b.ref.row),
              )))
            <String, Object?>{
              'cell': cell.ref.a1,
              'type': cell.type.name,
              'value': cell.value,
              'formula': cell.formula,
              'style': cell.styleIndex,
            },
        ],
      },
  ],
};

// Retained package XML can contain live references absent from the editable model.
// Refuse renaming those sheets until the entire reference graph can be rewritten.
bool _referencesSheet(SmlWorkbook book, String name) {
  bool formula(String text) =>
      text.toLowerCase().contains(
        "'${name.replaceAll("'", "''")}'!".toLowerCase(),
      ) ||
      RegExp(
        '(^|[^A-Za-z0-9_.])${RegExp.escape(name)}!',
        caseSensitive: false,
      ).hasMatch(text);
  if (book.namedRanges.any(
    (n) => n.sheetName.toLowerCase() == name.toLowerCase(),
  )) {
    return true;
  }
  for (final sheet in book.sheets) {
    if (sheet.allCells.any((c) => formula(c.formula ?? ''))) return true;
    if (sheet.pivots.any(
      (p) => p.sourceSheetName?.toLowerCase() == name.toLowerCase(),
    )) {
      return true;
    }
  }
  for (final part in book.package?.parts ?? <PackagePart>[]) {
    if (!part.uri.endsWith('.xml')) continue;
    final root = XmlDocument.parse(part.readText()).root;
    if (root == null) continue;
    bool visit(XmlElement e) {
      if (e.getAttribute('sheet')?.toLowerCase() == name.toLowerCase()) {
        return true;
      }
      if (<String>{
            'f',
            'definedName',
            'formula1',
            'formula2',
          }.contains(e.localName) &&
          formula(e.text)) {
        return true;
      }
      return e.childElements.any(visit);
    }

    if (visit(root)) return true;
  }
  return false;
}
