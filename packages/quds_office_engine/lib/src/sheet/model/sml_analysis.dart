import 'sml_workbook.dart';

/// A workbook-defined name (`definedName`).
class SmlNamedRange {
  /// SmlNamedRange API.
  SmlNamedRange({
    required this.name,
    required this.sheetName,
    required this.range,
  });

  /// name API.
  String name;

  /// sheetName API.
  String sheetName;

  /// range API.
  SmlRange range;

  /// a1 API.
  String get a1 => '${range.start.a1}:${range.end.a1}';
}

/// How a cell value is validated.
enum SmlValidationKind { list, whole, decimal, date, textLength, custom }

/// Data-validation rule on a range.
class SmlDataValidation {
  /// SmlDataValidation API.
  SmlDataValidation({
    required this.range,
    required this.kind,
    this.formula1 = '',
    this.formula2 = '',
    this.allowBlank = true,
    this.errorTitle = '',
    this.error = '',
  });

  /// range API.
  SmlRange range;

  /// kind API.
  SmlValidationKind kind;

  /// formula1 API.
  String formula1;

  /// formula2 API.
  String formula2;

  /// allowBlank API.
  bool allowBlank;

  /// errorTitle API.
  String errorTitle;

  /// error API.
  String error;

  /// listItems API.
  List<String> get listItems {
    if (kind != SmlValidationKind.list) {
      return const <String>[];
    }
    return formula1
        .split(RegExp(r'[,،]'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  /// accepts API.
  bool accepts(String raw) {
    if (raw.isEmpty) {
      return allowBlank;
    }
    switch (kind) {
      case SmlValidationKind.list:
        return listItems.any(
          (String item) => item.toLowerCase() == raw.toLowerCase(),
        );
      case SmlValidationKind.whole:
        return int.tryParse(raw) != null && _inNumericBounds(double.parse(raw));
      case SmlValidationKind.decimal:
        final double? n = double.tryParse(raw);
        return n != null && _inNumericBounds(n);
      case SmlValidationKind.date:
        return DateTime.tryParse(raw) != null;
      case SmlValidationKind.textLength:
        return _inNumericBounds(raw.length.toDouble());
      case SmlValidationKind.custom:
        return raw.isNotEmpty;
    }
  }

  bool _inNumericBounds(double value) {
    final double? min = double.tryParse(formula1);
    final double? max = double.tryParse(formula2);
    if (min != null && value < min) {
      return false;
    }
    if (max != null && value > max) {
      return false;
    }
    return true;
  }
}

/// Conditional format kinds hosts can paint.
enum SmlConditionalKind { greaterThan, lessThan, equal, duplicate, contains }

/// One conditional-format rule.
class SmlConditionalRule {
  /// SmlConditionalRule API.
  SmlConditionalRule({
    required this.range,
    required this.kind,
    this.formula = '',
    this.fillRgb = 'FFF2CC',
    this.fontRgb = '',
  });

  /// range API.
  SmlRange range;

  /// kind API.
  SmlConditionalKind kind;

  /// formula API.
  String formula;

  /// fillRgb API.
  String fillRgb;

  /// fontRgb API.
  String fontRgb;

  /// matches API.
  bool matches(SmlCell cell, SmlWorksheet sheet) {
    final String text = cell.asString;
    switch (kind) {
      case SmlConditionalKind.greaterThan:
        final double? n = cell.asNumber;
        final double? bound = double.tryParse(formula);
        return n != null && bound != null && n > bound;
      case SmlConditionalKind.lessThan:
        final double? n = cell.asNumber;
        final double? bound = double.tryParse(formula);
        return n != null && bound != null && n < bound;
      case SmlConditionalKind.equal:
        return text == formula;
      case SmlConditionalKind.contains:
        return text.toLowerCase().contains(formula.toLowerCase());
      case SmlConditionalKind.duplicate:
        if (text.isEmpty) {
          return false;
        }
        var seen = 0;
        for (final SmlCellRef ref in range.cells) {
          final SmlCell? other = sheet.cellOrNull(ref);
          if (other != null && other.asString == text) {
            seen++;
          }
        }
        return seen > 1;
    }
  }
}

/// AutoFilter + sort on a worksheet range.
class SmlAutoFilter {
  /// SmlAutoFilter API.
  SmlAutoFilter({required this.range, Map<int, Set<String>>? hiddenValues})
    : hiddenValues = hiddenValues ?? <int, Set<String>>{};

  /// range API.
  SmlRange range;

  /// Column index (relative to [range.minCol]) → values hidden by the filter.
  final Map<int, Set<String>> hiddenValues;

  /// enabled API.
  bool get enabled => hiddenValues.values.any((Set<String> v) => v.isNotEmpty);

  /// isRowHidden API.
  bool isRowHidden(SmlWorksheet sheet, int row) {
    if (row < range.minRow || row > range.maxRow) {
      return false;
    }
    if (row == range.minRow) {
      return false;
    }
    for (final MapEntry<int, Set<String>> entry in hiddenValues.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final int col = range.minCol + entry.key;
      final String text = sheet.cell(SmlCellRef(col, row)).asString;
      if (entry.value.contains(text)) {
        return true;
      }
    }
    return false;
  }

  /// uniqueValues API.
  List<String> uniqueValues(SmlWorksheet sheet, int relativeCol) {
    final int col = range.minCol + relativeCol;
    final Set<String> values = <String>{};
    for (int r = range.minRow + 1; r <= range.maxRow; r++) {
      final String text = sheet.cellOrNull(SmlCellRef(col, r))?.asString ?? '';
      if (text.isNotEmpty) {
        values.add(text);
      }
    }
    final List<String> list = values.toList()..sort();
    return list;
  }
}

/// Sort one column inside a range.
class SmlSortKey {
  /// SmlSortKey API.
  const SmlSortKey({required this.column, this.ascending = true});

  /// Absolute column index.
  final int column;

  /// ascending API.
  final bool ascending;
}

/// Sort / filter / validate / paint helpers.
abstract final class SmlAnalysis {
  /// sort API.
  static void sort(SmlWorksheet sheet, SmlRange range, List<SmlSortKey> keys) {
    if (keys.isEmpty) {
      return;
    }
    final int header = range.minRow;
    final List<int> body = <int>[
      for (int r = header + 1; r <= range.maxRow; r++) r,
    ];
    body.sort((int a, int b) {
      for (final SmlSortKey key in keys) {
        final String left = sheet.cell(SmlCellRef(key.column, a)).asString;
        final String right = sheet.cell(SmlCellRef(key.column, b)).asString;
        final double? ln = double.tryParse(left);
        final double? rn = double.tryParse(right);
        final int cmp;
        if (ln != null && rn != null) {
          cmp = ln.compareTo(rn);
        } else {
          cmp = left.toLowerCase().compareTo(right.toLowerCase());
        }
        if (cmp != 0) {
          return key.ascending ? cmp : -cmp;
        }
      }
      return 0;
    });
    final List<Map<int, SmlCell>> snapshot = <Map<int, SmlCell>>[
      for (final int r in body)
        <int, SmlCell>{
          for (int c = range.minCol; c <= range.maxCol; c++)
            c: _copyCell(sheet.cell(SmlCellRef(c, r))),
        },
    ];
    for (int i = 0; i < body.length; i++) {
      final int dest = header + 1 + i;
      for (int c = range.minCol; c <= range.maxCol; c++) {
        final SmlCell src = snapshot[i][c]!;
        final SmlCell cell = sheet.cell(SmlCellRef(c, dest));
        cell
          ..type = src.type
          ..value = src.value
          ..formula = src.formula
          ..styleIndex = src.styleIndex
          ..fillRgb = src.fillRgb
          ..fontRgb = src.fontRgb
          ..fontBold = src.fontBold
          ..fontSize = src.fontSize
          ..horizontalAlign = src.horizontalAlign;
      }
    }
  }

  /// applyConditional API.
  static void applyConditional(SmlWorksheet sheet) {
    for (final SmlConditionalRule rule in sheet.conditionalFormats) {
      for (final SmlCellRef ref in rule.range.cells) {
        final SmlCell cell = sheet.cell(ref);
        if (rule.matches(cell, sheet)) {
          if (rule.fillRgb.isNotEmpty) {
            cell.fillRgb = rule.fillRgb;
          }
          if (rule.fontRgb.isNotEmpty) {
            cell.fontRgb = rule.fontRgb;
          }
        }
      }
    }
  }

  /// removeDuplicates API.
  static int removeDuplicates(SmlWorksheet sheet, SmlRange range) {
    final Set<String> seen = <String>{};
    var removed = 0;
    for (int r = range.maxRow; r > range.minRow; r--) {
      final String key = <String>[
        for (int c = range.minCol; c <= range.maxCol; c++)
          sheet.cell(SmlCellRef(c, r)).asString,
      ].join('\u0001');
      if (!seen.add(key)) {
        for (int c = range.minCol; c <= range.maxCol; c++) {
          final SmlCell cell = sheet.cell(SmlCellRef(c, r));
          cell
            ..value = null
            ..formula = null;
        }
        removed++;
      }
    }
    return removed;
  }

  static SmlCell _copyCell(SmlCell src) {
    return SmlCell(
      ref: src.ref,
      type: src.type,
      value: src.value,
      formula: src.formula,
      styleIndex: src.styleIndex,
      horizontalAlign: src.horizontalAlign,
      fillRgb: src.fillRgb,
      fontRgb: src.fontRgb,
      fontBold: src.fontBold,
      fontSize: src.fontSize,
    );
  }

  /// Returns an error string when [text] violates a rule covering [ref].
  static String? validateInput(
    SmlWorksheet sheet,
    SmlCellRef ref,
    String text,
  ) {
    for (final SmlDataValidation rule in sheet.validations) {
      if (rule.range.containsRef(ref) && !rule.accepts(text)) {
        return rule.error.isEmpty ? 'This value does not match the data validation restrictions.' : rule.error;
      }
    }
    return null;
  }

  /// Fills empty cells in [range] from the first populated cell in each column.
  static void fillSeries(SmlWorksheet sheet, SmlRange range) {
    for (int c = range.minCol; c <= range.maxCol; c++) {
      SmlCell? seed;
      var seedRow = range.minRow;
      SmlCell? second;
      var secondRow = range.minRow;
      for (int r = range.minRow; r <= range.maxRow; r++) {
        final SmlCell cell = sheet.cell(SmlCellRef(c, r));
        if (!cell.hasContent) {
          continue;
        }
        if (seed == null) {
          seed = cell;
          seedRow = r;
        } else {
          second = cell;
          secondRow = r;
          break;
        }
      }
      if (seed == null) {
        continue;
      }
      final double? a = seed.asNumber;
      final double? b = second?.asNumber;
      final double step;
      if (a != null && b != null && secondRow != seedRow) {
        step = (b - a) / (secondRow - seedRow);
      } else if (a != null) {
        step = 1;
      } else {
        step = 0;
      }
      for (int r = seedRow + 1; r <= range.maxRow; r++) {
        final SmlCell cell = sheet.cell(SmlCellRef(c, r));
        if (cell.hasContent) {
          continue;
        }
        if (a != null) {
          cell
            ..type = SmlCellType.number
            ..formula = null
            ..value = a + step * (r - seedRow);
        } else {
          cell
            ..type = seed.type
            ..formula = null
            ..value = seed.value;
        }
      }
    }
  }
}

/// A cell comment (`comments.xml`).
class SmlComment {
  /// SmlComment API.
  SmlComment({
    required this.ref,
    required this.text,
    this.author = 'Quds Office',
  });

  /// ref API.
  SmlCellRef ref;

  /// text API.
  String text;

  /// author API.
  String author;
}

/// Worksheet protection flag.
class SmlSheetProtection {
  /// SmlSheetProtection API.
  SmlSheetProtection({
    this.enabled = true,
    this.allowSelectLocked = true,
    this.password = '',
  });

  /// enabled API.
  bool enabled;

  /// allowSelectLocked API.
  bool allowSelectLocked;

  /// Optional plaintext password checked by the host before unprotecting.
  String password;
}

/// An Excel Table (ListObject).
class SmlTable {
  /// SmlTable API.
  SmlTable({
    required this.name,
    required this.range,
    this.headerRow = true,
    this.bandedRows = true,
  });

  /// name API.
  String name;

  /// range API.
  SmlRange range;

  /// headerRow API.
  bool headerRow;

  /// bandedRows API.
  bool bandedRows;

  /// headerName API.
  String headerName(SmlWorksheet sheet, int col) {
    if (!range.contains(col, range.minRow)) {
      return '';
    }
    return sheet.cell(SmlCellRef(col, range.minRow)).asString;
  }

  /// dataRangeForColumn API.
  SmlRange? dataRangeForColumn(SmlWorksheet sheet, String header) {
    for (int c = range.minCol; c <= range.maxCol; c++) {
      if (headerName(sheet, c).toUpperCase() == header.toUpperCase()) {
        final int r0 = headerRow ? range.minRow + 1 : range.minRow;
        if (r0 > range.maxRow) {
          return SmlRange(SmlCellRef(c, range.minRow), SmlCellRef(c, range.minRow));
        }
        return SmlRange(SmlCellRef(c, r0), SmlCellRef(c, range.maxRow));
      }
    }
    return null;
  }

  /// dataRange API.
  SmlRange get dataRange {
    final int r0 = headerRow ? range.minRow + 1 : range.minRow;
    if (r0 > range.maxRow) {
      return range;
    }
    return SmlRange(
      SmlCellRef(range.minCol, r0),
      SmlCellRef(range.maxCol, range.maxRow),
    );
  }

  /// resolveRef API.
  static SmlRange? resolveRef(SmlWorksheet sheet, String token) {
    final int bracket = token.indexOf('[');
    final String tableName = (bracket < 0 ? token : token.substring(0, bracket))
        .trim();
    final String column = bracket < 0
        ? ''
        : token.substring(bracket + 1, token.endsWith(']') ? token.length - 1 : token.length)
            .trim();
    for (final SmlTable table in sheet.tables) {
      if (table.name.toUpperCase() != tableName.toUpperCase()) {
        continue;
      }
      if (column.isEmpty) {
        return table.dataRange;
      }
      return table.dataRangeForColumn(sheet, column);
    }
    return null;
  }
}

/// A compact pivot cache: one row field, one data field, SUM aggregation.
class SmlPivotTable {
  /// SmlPivotTable API.
  SmlPivotTable({
    required this.source,
    required this.rowField,
    required this.dataField,
    this.name = 'Pivot',
  });

  /// Source range including a header row.
  SmlRange source;

  /// 0-based column inside [source] used as the row label.
  int rowField;

  /// 0-based column inside [source] summed into values.
  int dataField;

  /// name API.
  String name;

  /// Evaluates grouped sums: header row + one result row per distinct label.
  List<List<Object?>> evaluate(SmlWorksheet sheet) {
    final int labelCol = source.minCol + rowField;
    final int valueCol = source.minCol + dataField;
    final String labelHeader = sheet
        .cell(SmlCellRef(labelCol, source.minRow))
        .asString;
    final String valueHeader = sheet
        .cell(SmlCellRef(valueCol, source.minRow))
        .asString;
    final Map<String, double> sums = <String, double>{};
    for (int r = source.minRow + 1; r <= source.maxRow; r++) {
      final String label = sheet.cell(SmlCellRef(labelCol, r)).asString;
      if (label.isEmpty) {
        continue;
      }
      final double n = sheet.cell(SmlCellRef(valueCol, r)).asNumber ?? 0;
      sums[label] = (sums[label] ?? 0) + n;
    }
    final List<String> keys = sums.keys.toList()..sort();
    return <List<Object?>>[
      <Object?>[
        labelHeader.isEmpty ? 'Row' : labelHeader,
        'Sum of $valueHeader',
      ],
      for (final String key in keys) <Object?>[key, sums[key]],
    ];
  }

  /// Writes the evaluated cache starting at [origin].
  void materialize(SmlWorksheet sheet, SmlCellRef origin) {
    final List<List<Object?>> rows = evaluate(sheet);
    for (int r = 0; r < rows.length; r++) {
      for (int c = 0; c < rows[r].length; c++) {
        final SmlCell cell = sheet.cell(
          SmlCellRef(origin.col + c, origin.row + r),
        );
        final Object? value = rows[r][c];
        cell.formula = null;
        if (value is num) {
          cell.type = SmlCellType.number;
          cell.value = value;
        } else {
          cell.type = SmlCellType.string;
          cell.value = value?.toString() ?? '';
        }
      }
    }
  }
}
