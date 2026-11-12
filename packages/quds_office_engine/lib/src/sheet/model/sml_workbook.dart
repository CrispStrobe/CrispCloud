import 'dart:convert';

import '../../office/office_document_properties.dart';
import '../../opc/opc_archive.dart';
import '../../visual/office_visual.dart';
import '../styles/sml_styles.dart';
import 'sml_analysis.dart';
import 'sml_sparkline.dart';

/// Enum SmlCellType.
enum SmlCellType { number, string, boolean, error, formula }

/// Class SmlCellRef.
class SmlCellRef {
  /// SmlCellRef API.
  const SmlCellRef(this.col, this.row);

  /// col API.
  final int col;

  /// row API.
  final int row;

  /// parse API.
  factory SmlCellRef.parse(String a1) {
    final Match? match = RegExp(r'^\$?([A-Za-z]+)\$?(\d+)$').firstMatch(a1);
    if (match == null) {
      throw FormatException('Invalid A1 reference: $a1');
    }
    return SmlCellRef(
      _colToIndex(match.group(1)!),
      int.parse(match.group(2)!) - 1,
    );
  }

  /// a1 API.
  String get a1 => '${_indexToCol(col)}${row + 1}';

  static int _colToIndex(String letters) {
    var n = 0;
    for (int i = 0; i < letters.length; i++) {
      n = n * 26 + (letters[i].toUpperCase().codeUnitAt(0) - 64);
    }
    return n - 1;
  }

  static String _indexToCol(int index) {
    var n = index + 1;
    final StringBuffer buffer = StringBuffer();
    while (n > 0) {
      n--;
      buffer.writeCharCode(65 + (n % 26));
      n ~/= 26;
    }
    return buffer.toString().split('').reversed.join();
  }
}

/// Class SmlRange.
class SmlRange {
  /// SmlRange API.
  const SmlRange(this.start, this.end);

  /// start API.
  final SmlCellRef start;

  /// end API.
  final SmlCellRef end;

  /// parse API.
  factory SmlRange.parse(String a1) {
    final int colon = a1.indexOf(':');
    if (colon < 0) {
      final SmlCellRef one = SmlCellRef.parse(a1);
      return SmlRange(one, one);
    }
    return SmlRange(
      SmlCellRef.parse(a1.substring(0, colon)),
      SmlCellRef.parse(a1.substring(colon + 1)),
    );
  }

  /// cells API.
  Iterable<SmlCellRef> get cells sync* {
    for (int r = minRow; r <= maxRow; r++) {
      for (int c = minCol; c <= maxCol; c++) {
        yield SmlCellRef(c, r);
      }
    }
  }

  /// minCol API.
  int get minCol => start.col < end.col ? start.col : end.col;

  /// maxCol API.
  int get maxCol => start.col > end.col ? start.col : end.col;

  /// minRow API.
  int get minRow => start.row < end.row ? start.row : end.row;

  /// maxRow API.
  int get maxRow => start.row > end.row ? start.row : end.row;

  /// True when the range is a single cell.
  bool get isSingleCell => start.col == end.col && start.row == end.row;

  /// contains API.
  bool contains(int col, int row) =>
      col >= minCol && col <= maxCol && row >= minRow && row <= maxRow;

  /// containsRef API.
  bool containsRef(SmlCellRef ref) => contains(ref.col, ref.row);
}

/// A merged rectangle (`mergeCell/@ref`), inclusive on every edge.
class SmlMerge {
  /// SmlMerge API.
  SmlMerge({required int c0, required int r0, required int c1, required int r1})
    : c0 = c0 < c1 ? c0 : c1,
      r0 = r0 < r1 ? r0 : r1,
      c1 = c0 > c1 ? c0 : c1,
      r1 = r0 > r1 ? r0 : r1;

  /// parse API.
  factory SmlMerge.parse(String a1) {
    final SmlRange range = SmlRange.parse(a1);
    return SmlMerge(
      c0: range.minCol,
      r0: range.minRow,
      c1: range.maxCol,
      r1: range.maxRow,
    );
  }

  /// Left column (origin).
  final int c0;

  /// Top row (origin).
  final int r0;

  /// Right column.
  final int c1;

  /// Bottom row.
  final int r1;

  /// origin API.
  SmlCellRef get origin => SmlCellRef(c0, r0);

  /// a1 API.
  String get a1 => c0 == c1 && r0 == r1
      ? origin.a1
      : '${origin.a1}:${SmlCellRef(c1, r1).a1}';

  /// isSingle API.
  bool get isSingle => c0 == c1 && r0 == r1;

  /// contains API.
  bool contains(int col, int row) =>
      col >= c0 && col <= c1 && row >= r0 && row <= r1;

  /// containsRef API.
  bool containsRef(SmlCellRef ref) => contains(ref.col, ref.row);

  /// isOrigin API.
  bool isOrigin(int col, int row) => col == c0 && row == r0;

  /// Covered non-origin cell inside this merge.
  bool isCovered(int col, int row) => contains(col, row) && !isOrigin(col, row);

  /// overlaps API.
  bool overlaps(SmlMerge other) =>
      c0 <= other.c1 && c1 >= other.c0 && r0 <= other.r1 && r1 >= other.r0;

  /// equalsRange API.
  bool equalsRange(SmlRange range) =>
      c0 == range.minCol &&
      r0 == range.minRow &&
      c1 == range.maxCol &&
      r1 == range.maxRow;

  /// copy API.
  SmlMerge copy() => SmlMerge(c0: c0, r0: r0, c1: c1, r1: r1);
}

/// Class SmlCell.
class SmlCell {
  /// SmlCell API.
  SmlCell({
    required this.ref,
    this.type = SmlCellType.number,
    this.value,
    this.formula,
    this.styleIndex = 0,
    this.hasExplicitStyleIndex = false,
    this.horizontalAlign = SmlHAlign.general,
    this.fillRgb = '',
    this.fontRgb = '',
    this.fontBold = false,
    this.fontSize = 11,
    this.borderRgb = '',
    this.borderWidth = 0,
    this.locked = true,
  });

  /// ref API.
  SmlCellRef ref;

  /// type API.
  SmlCellType type;

  /// value API.
  Object? value;

  /// formula API.
  String? formula;

  /// styleIndex API.
  int styleIndex;

  /// Whether the imported cell explicitly selected its style, including zero.
  /// Retained through copies so native style presence survives serialization.
  bool hasExplicitStyleIndex;

  /// horizontalAlign API.
  SmlHAlign horizontalAlign;

  /// Solid fill as `RRGGBB`; empty means no fill.
  String fillRgb;

  /// Font color as `RRGGBB`; empty means the theme default.
  String fontRgb;

  /// fontBold API.
  bool fontBold;

  /// Point size from the cell xf font; `11` is Calibri default.
  double fontSize;

  /// Uniform cell border as `RRGGBB`; empty means no true border.
  String borderRgb;

  /// Border stroke width in points when [borderRgb] is set (`0` → 0.5 pt).
  double borderWidth;

  /// Excel default: locked when the sheet is protected.
  bool locked;

  /// asNumber API.
  double? get asNumber {
    final Object? v = value;
    if (v is num) {
      return v.toDouble();
    }
    if (v is String) {
      return double.tryParse(v);
    }
    if (v is bool) {
      return v ? 1 : 0;
    }
    return null;
  }

  /// asString API.
  String get asString => value?.toString() ?? '';

  /// hasContent API.
  bool get hasContent {
    if (formula != null && formula!.isNotEmpty) {
      return true;
    }
    if (value == null) {
      return false;
    }
    return asString.isNotEmpty;
  }
}

/// Class SmlRow.
class SmlRow {
  /// SmlRow API.
  SmlRow(this.index, {Map<int, SmlCell>? cells})
    : cells = cells ?? <int, SmlCell>{};

  /// index API.
  final int index;

  /// cells API.
  final Map<int, SmlCell> cells;

  /// cell API.
  SmlCell cell(int col) =>
      cells.putIfAbsent(col, () => SmlCell(ref: SmlCellRef(col, index)));
}

/// Class SmlHeaderFooter.
class SmlHeaderFooter {
  /// SmlHeaderFooter API.
  SmlHeaderFooter({
    this.headerLeft = '',
    this.headerCenter = '',
    this.headerRight = '',
    this.footerLeft = '',
    this.footerCenter = '',
    this.footerRight = '',
  });

  /// headerLeft API.
  String headerLeft;

  /// headerCenter API.
  String headerCenter;

  /// headerRight API.
  String headerRight;

  /// footerLeft API.
  String footerLeft;

  /// footerCenter API.
  String footerCenter;

  /// footerRight API.
  String footerRight;

  /// True when any section has text.
  bool get isEmpty =>
      headerLeft.isEmpty &&
      headerCenter.isEmpty &&
      headerRight.isEmpty &&
      footerLeft.isEmpty &&
      footerCenter.isEmpty &&
      footerRight.isEmpty;

  /// copy API.
  SmlHeaderFooter copy() => SmlHeaderFooter(
    headerLeft: headerLeft,
    headerCenter: headerCenter,
    headerRight: headerRight,
    footerLeft: footerLeft,
    footerCenter: footerCenter,
    footerRight: footerRight,
  );
}

/// Reversible column state, retaining imported width precision and the metric
/// under which its pixel projection was captured.
class SmlColumnSnapshot {
  SmlColumnSnapshot._({
    required this.pixelWidth,
    required this.nativeWidth,
    required this.maximumDigitWidthPx,
    required Map<String, String> properties,
  }) : properties = Map<String, String>.unmodifiable(properties);

  final double? pixelWidth;
  final double? nativeWidth;
  final int maximumDigitWidthPx;
  final Map<String, String> properties;
}

/// Class SmlWorksheet.
class SmlWorksheet {
  /// SmlWorksheet API.
  SmlWorksheet({
    required this.name,
    required this.sheetId,
    this.sourcePartUri,
    this.rightToLeft = false,
    this.freezeRows = 0,
    this.freezeCols = 0,
    Map<int, SmlRow>? rows,
    List<SmlDrawing>? drawings,
    Map<int, double>? columnWidths,
    Map<int, Map<String, String>>? columnProperties,
    Map<int, double>? rowHeights,
    List<SmlMerge>? merges,
    List<SmlDataValidation>? validations,
    List<SmlConditionalRule>? conditionalFormats,
    this.autoFilter,
    this.printArea,
    this.printTitleRows,
    this.printTitleCols,
    this.headerFooter,
    this.protection,
    List<SmlComment>? comments,
    List<SmlTable>? tables,
    List<SmlPivotTable>? pivots,
    List<SmlSparkline>? sparklines,
  }) : rows = rows ?? <int, SmlRow>{},
       drawings = drawings ?? <SmlDrawing>[],
       columnWidths = columnWidths ?? <int, double>{},
       columnProperties = columnProperties ?? <int, Map<String, String>>{},
       rowHeights = rowHeights ?? <int, double>{},
       merges = merges ?? <SmlMerge>[],
       validations = validations ?? <SmlDataValidation>[],
       conditionalFormats = conditionalFormats ?? <SmlConditionalRule>[],
       comments = comments ?? <SmlComment>[],
       tables = tables ?? <SmlTable>[],
       pivots = pivots ?? <SmlPivotTable>[],
       sparklines = sparklines ?? <SmlSparkline>[];

  /// Original owning part, retained when worksheets are reordered.
  String? sourcePartUri;

  /// Imported native rule groups remain intact while their editable projection
  /// is unchanged. A reference-only rename rebases these snapshots atomically.
  String? sourceValidationState;
  String? sourceConditionalFormatState;

  /// Snapshot of every editable validation property, optionally rewriting refs.
  String validationState([String Function(String)? rewrite]) => jsonEncode([
    for (final rule in validations)
      [
        rule.range.start.a1,
        rule.range.end.a1,
        rule.kind.name,
        rewrite?.call(rule.formula1) ?? rule.formula1,
        rewrite?.call(rule.formula2) ?? rule.formula2,
        rule.allowBlank,
        rule.errorTitle,
        rule.error,
      ],
  ]);

  /// Snapshot of every editable conditional-format property.
  String conditionalFormatState([String Function(String)? rewrite]) =>
      jsonEncode([
        for (final rule in conditionalFormats)
          [
            rule.range.start.a1,
            rule.range.end.a1,
            rule.kind.name,
            rewrite?.call(rule.formula) ?? rule.formula,
            rule.fillRgb,
            rule.fontRgb,
          ],
      ]);

  /// Excel worksheet column count (A … XFD).
  static const int excelColumnCount = 16384;

  /// Excel worksheet row count (1 … 1048576).
  static const int excelRowCount = 1048576;

  /// Default rendered column width in CSS pixels (Excel default ≈ 8.43 chars).
  static const double defaultColumnWidthPx = 64;

  /// Default rendered row height in CSS pixels (Excel default 15 pt @ 96 dpi).
  static const double defaultRowHeightPx = 20;

  /// minColumnWidthPx API.
  static const double minColumnWidthPx = 8;

  /// maxColumnWidthPx API.
  static const double maxColumnWidthPx = 800;

  /// minRowHeightPx API.
  static const double minRowHeightPx = 8;

  /// maxRowHeightPx API.
  static const double maxRowHeightPx = 409;

  /// OOXML `col/@width` units matching [defaultColumnWidthPx]. The Excel UI
  /// displays about 8.43 characters, but the stored width includes padding.
  static const double excelDefaultColumnWidth = 9.140625;

  /// Calibri 11 maximum digit width at 96 dpi, used by the default sheet font.
  static const int defaultMaximumDigitWidthPx = 7;

  /// name API.
  String name;

  /// sheetId API.
  int sheetId;

  /// Excel `sheetView/@rightToLeft`: column A sits on the right.
  bool rightToLeft;

  /// Frozen row count (`pane/@ySplit`): rows `[0, freezeRows)` stay pinned.
  int freezeRows;

  /// Frozen column count (`pane/@xSplit`): cols `[0, freezeCols)` stay pinned.
  int freezeCols;

  /// rows API.
  final Map<int, SmlRow> rows;

  /// drawings API.
  final List<SmlDrawing> drawings;

  /// Custom column widths in CSS pixels, keyed by 0-based column index.
  final Map<int, double> columnWidths;

  /// Retained column formatting attributes, including hidden/grouping flags,
  /// default cell style, bestFit and phonetic. Width/min/max are modeled apart.
  final Map<int, Map<String, String>> columnProperties;

  // Preserve original character widths when an import is saved unchanged:
  // several stored widths can map to the same integral pixel width.
  final Map<int, double> _importedColumnWidths = <int, double>{};

  int _maximumDigitWidthPx = defaultMaximumDigitWidthPx;
  double? _nativeDefaultColumnWidth;
  int? _nativeBaseColumnWidth;

  /// Active 96-dpi Normal-font metric. Seven is an explicit unresolved fallback.
  int get maximumDigitWidthPx => _maximumDigitWidthPx;

  /// Native default widths use the same Normal-font metric as explicit columns.
  /// Files omitting both default/base width retain the historical 64px default.
  double get effectiveDefaultColumnWidthPx {
    final width = _nativeDefaultColumnWidth;
    if (width != null) {
      return columnWidthFromExcel(
        width,
        maximumDigitWidth: maximumDigitWidthPx,
      );
    }
    final base = _nativeBaseColumnWidth;
    return base == null
        ? defaultColumnWidthPx
        : base * maximumDigitWidthPx + 5.0;
  }

  /// Retains native sheetFormatPr values; the serializer keeps their source XML.
  void importDefaultColumnWidth({double? excelWidth, int? baseCharacters}) {
    if (excelWidth != null && (!excelWidth.isFinite || excelWidth < 0)) {
      throw ArgumentError.value(excelWidth, 'excelWidth');
    }
    if (baseCharacters != null && baseCharacters < 0) {
      throw ArgumentError.value(baseCharacters, 'baseCharacters');
    }
    _nativeDefaultColumnWidth = excelWidth;
    _nativeBaseColumnWidth = baseCharacters;
  }

  // Direct edits to the public pixel map bypass setColumnWidth. Once observed,
  // a mismatch permanently severs its old native association: a later metric
  // must not accidentally make the edited value look like an untouched import.
  double? _currentImportedColumnWidth(int col) {
    final native = _importedColumnWidths[col];
    if (native != null &&
        columnWidths[col] !=
            columnWidthFromExcel(
              native,
              maximumDigitWidth: maximumDigitWidthPx,
            )) {
      _importedColumnWidths.remove(col);
      return null;
    }
    return native;
  }

  bool _hasNativeColumnProjection(SmlColumnSnapshot state) =>
      state.nativeWidth != null &&
      state.pixelWidth ==
          columnWidthFromExcel(
            state.nativeWidth!,
            maximumDigitWidth: state.maximumDigitWidthPx,
          );

  /// Captures a column for editor history without flattening its native width.
  SmlColumnSnapshot captureColumn(int col) => SmlColumnSnapshot._(
    pixelWidth: columnWidths[col],
    nativeWidth: _currentImportedColumnWidth(col),
    maximumDigitWidthPx: maximumDigitWidthPx,
    properties: columnProperties[col] ?? const <String, String>{},
  );

  /// Projects a history state under the current font; authored pixel edits stay
  /// pixels, whereas untouched native widths follow the resolved Normal font.
  double projectedColumnWidth(SmlColumnSnapshot state) {
    final pixels = state.pixelWidth;
    if (pixels == null) return effectiveDefaultColumnWidthPx;
    if (_hasNativeColumnProjection(state)) {
      return columnWidthFromExcel(
        state.nativeWidth!,
        maximumDigitWidth: maximumDigitWidthPx,
      );
    }
    return pixels;
  }

  /// Restores a native-aware history state. Width-only actions preserve later
  /// unrelated formatting, including column style, grouping and visibility.
  void restoreColumn(
    int col,
    SmlColumnSnapshot state, {
    bool widthOnly = false,
  }) {
    if (state.pixelWidth == null) {
      columnWidths.remove(col);
    } else {
      columnWidths[col] = projectedColumnWidth(state);
    }
    if (!_hasNativeColumnProjection(state)) {
      _importedColumnWidths.remove(col);
    } else {
      _importedColumnWidths[col] = state.nativeWidth!;
    }
    if (widthOnly) {
      final custom = state.properties['customWidth'];
      if (custom == null) {
        columnProperties[col]?.remove('customWidth');
      } else {
        (columnProperties[col] ??= <String, String>{})['customWidth'] = custom;
      }
    } else if (state.properties.isEmpty) {
      columnProperties.remove(col);
    } else {
      columnProperties[col] = Map<String, String>.of(state.properties);
    }
  }

  /// Captures all modeled and native column dimensions for grid history.
  Map<int, SmlColumnSnapshot> captureColumns() => {
    for (final col in {
      ...columnWidths.keys,
      ..._importedColumnWidths.keys,
      ...columnProperties.keys,
    })
      col: captureColumn(col),
  };

  /// Restores grid dimensions after a structural history action.
  void restoreColumns(Map<int, SmlColumnSnapshot> columns) {
    columnWidths.clear();
    _importedColumnWidths.clear();
    columnProperties.clear();
    for (final entry in columns.entries) {
      restoreColumn(entry.key, entry.value);
    }
  }

  /// Reprojects untouched imported widths, retaining native precision and later
  /// explicit pixel edits. It changes view geometry, not document content.
  void applyColumnMetrics(int maximumDigitWidth) {
    if (maximumDigitWidth <= 0) {
      throw ArgumentError.value(maximumDigitWidth, 'maximumDigitWidth');
    }
    if (maximumDigitWidth == _maximumDigitWidthPx) return;
    for (final col in _importedColumnWidths.keys.toList()) {
      final native = _currentImportedColumnWidth(col);
      if (native != null) {
        columnWidths[col] = columnWidthFromExcel(
          native,
          maximumDigitWidth: maximumDigitWidth,
        );
      }
    }
    _maximumDigitWidthPx = maximumDigitWidth;
  }

  /// Custom row heights in CSS pixels, keyed by 0-based row index.
  final Map<int, double> rowHeights;

  /// Merged cell rectangles (`mergeCells`).
  final List<SmlMerge> merges;

  /// validations API.
  final List<SmlDataValidation> validations;

  /// conditionalFormats API.
  final List<SmlConditionalRule> conditionalFormats;

  /// autoFilter API.
  SmlAutoFilter? autoFilter;

  /// printArea API.
  SmlRange? printArea;

  /// Rows repeated at the top of each printed page (`printTitles`).
  SmlRange? printTitleRows;

  /// Columns repeated at the leading edge of each printed page.
  SmlRange? printTitleCols;

  /// Optional sheet header/footer texts (`headerFooter`).
  SmlHeaderFooter? headerFooter;

  /// protection API.
  SmlSheetProtection? protection;

  /// comments API.
  final List<SmlComment> comments;

  /// tables API.
  final List<SmlTable> tables;

  /// pivots API.
  final List<SmlPivotTable> pivots;

  /// sparklines API.
  final List<SmlSparkline> sparklines;

  /// row API.
  SmlRow row(int index) => rows.putIfAbsent(index, () => SmlRow(index));

  /// cell API.
  SmlCell cell(SmlCellRef ref) => row(ref.row).cell(ref.col);

  /// cellA1 API.
  SmlCell cellA1(String a1) => cell(SmlCellRef.parse(a1));

  /// Existing cell, or null when the address has never been materialized.
  SmlCell? cellOrNull(SmlCellRef ref) => rows[ref.row]?.cells[ref.col];

  /// allCells API.
  Iterable<SmlCell> get allCells sync* {
    for (final SmlRow row in rows.values) {
      yield* row.cells.values;
    }
  }

  /// mergeAt API.
  SmlMerge? mergeAt(int col, int row) {
    for (final SmlMerge merge in merges) {
      if (merge.contains(col, row)) {
        return merge;
      }
    }
    return null;
  }

  /// mergeAtRef API.
  SmlMerge? mergeAtRef(SmlCellRef ref) => mergeAt(ref.col, ref.row);

  /// True when [col]/[row] sits inside a merge but is not the origin.
  bool isCovered(int col, int row) {
    final SmlMerge? merge = mergeAt(col, row);
    return merge != null && merge.isCovered(col, row);
  }

  /// A rectangle of at least two cells can be merged.
  bool canMerge(SmlRange range) => !range.isSingleCell;

  /// True when [range] overlaps any merge (Excel Unmerge).
  bool canUnmerge(SmlRange range) {
    final SmlMerge probe = SmlMerge(
      c0: range.minCol,
      r0: range.minRow,
      c1: range.maxCol,
      r1: range.maxRow,
    );
    for (final SmlMerge merge in merges) {
      if (merge.overlaps(probe)) {
        return true;
      }
    }
    return false;
  }

  /// Excel Merge & Center: join [range] and center the origin.
  ///
  /// Keeps the top-left value. Other cells in the rectangle are cleared.
  /// Overlapping merges are removed first.
  void mergeAndCenter(SmlRange range) {
    if (!canMerge(range)) {
      return;
    }
    unmerge(range);
    final SmlMerge merge = SmlMerge(
      c0: range.minCol,
      r0: range.minRow,
      c1: range.maxCol,
      r1: range.maxRow,
    );
    final SmlCell origin = cell(merge.origin);
    if (!origin.hasContent) {
      for (final SmlCellRef ref in range.cells) {
        if (ref.col == merge.c0 && ref.row == merge.r0) {
          continue;
        }
        final SmlCell other = cell(ref);
        if (!other.hasContent) {
          continue;
        }
        origin
          ..type = other.type
          ..value = other.value
          ..formula = other.formula;
        break;
      }
    }
    for (final SmlCellRef ref in range.cells) {
      if (ref.col == merge.c0 && ref.row == merge.r0) {
        continue;
      }
      final SmlCell other = cell(ref);
      other
        ..value = null
        ..formula = null
        ..type = SmlCellType.string
        ..horizontalAlign = SmlHAlign.general;
    }
    origin.horizontalAlign = SmlHAlign.center;
    merges.add(merge);
  }

  /// Removes every merge that overlaps [range].
  void unmerge(SmlRange range) {
    final SmlMerge probe = SmlMerge(
      c0: range.minCol,
      r0: range.minRow,
      c1: range.maxCol,
      r1: range.maxRow,
    );
    merges.removeWhere((SmlMerge merge) => merge.overlaps(probe));
  }

  /// Merge & Center when the selection is not already that merge; otherwise unmerge.
  void toggleMergeAndCenter(SmlRange range) {
    if (range.isSingleCell) {
      final SmlMerge? one = mergeAt(range.minCol, range.minRow);
      if (one != null) {
        unmerge(SmlRange(one.origin, SmlCellRef(one.c1, one.r1)));
      }
      return;
    }
    if (merges.length == 1 && merges.first.equalsRange(range)) {
      unmerge(range);
      return;
    }
    mergeAndCenter(range);
  }

  /// Converts stored `col/@width` to integral pixels using ISO 29500-1
  /// 18.3.1.13. The stored width already includes the five padding pixels;
  /// adding padding again, or scaling the UI's 8.43 character default, is wrong.
  static double columnWidthFromExcel(
    double excelWidth, {
    int maximumDigitWidth = defaultMaximumDigitWidthPx,
  }) {
    if (maximumDigitWidth <= 0) {
      throw ArgumentError.value(maximumDigitWidth, 'maximumDigitWidth');
    }
    return (((256 * excelWidth + (128 / maximumDigitWidth).floor()) / 256) *
            maximumDigitWidth)
        .floorToDouble();
  }

  /// Quantizes a requested pixel width to the stored 1/256-character units.
  /// The result maps back to the nearest integral pixel under the ISO formula.
  static double columnWidthToExcel(
    double px, {
    int maximumDigitWidth = defaultMaximumDigitWidthPx,
  }) {
    if (maximumDigitWidth <= 0) {
      throw ArgumentError.value(maximumDigitWidth, 'maximumDigitWidth');
    }
    final pixelWidth = px.round();
    final scaled = pixelWidth * 256 / maximumDigitWidth;
    final lower = (scaled - (128 / maximumDigitWidth).floor()).ceil();
    final preferred = scaled.floor();
    return (preferred < lower ? lower : preferred) / 256;
  }

  /// Records both the imported character width and its rendered pixel width.
  void importColumnWidth(int col, double excelWidth) {
    columnWidths[col] = columnWidthFromExcel(
      excelWidth,
      maximumDigitWidth: maximumDigitWidthPx,
    );
    _importedColumnWidths[col] = excelWidth;
  }

  /// Retains untouched import precision and converts edited pixel widths.
  double exportColumnWidth(int col) {
    final px = columnWidths[col] ?? effectiveDefaultColumnWidthPx;
    final imported = _currentImportedColumnWidth(col);
    if (imported != null) return imported;
    return columnWidthToExcel(px, maximumDigitWidth: maximumDigitWidthPx);
  }

  /// Column formatting to export, marking explicit width edits as custom.
  Map<String, String> exportColumnProperties(int col) {
    final properties = Map<String, String>.from(
      columnProperties[col] ?? const <String, String>{},
    );
    final width = columnWidths[col];
    final original = _currentImportedColumnWidth(col);
    if (width != null && original == null) {
      properties['customWidth'] = '1';
    }
    return properties;
  }

  /// rowHeightFromExcel API.
  static double rowHeightFromExcel(double points) => points * 96 / 72;

  /// rowHeightToExcel API.
  static double rowHeightToExcel(double px) => px * 72 / 96;

  /// columnWidth API.
  double columnWidth(int col) =>
      columnWidths[col] ?? effectiveDefaultColumnWidthPx;

  /// rowHeightAt API.
  double rowHeightAt(int row) {
    if (autoFilter != null && autoFilter!.isRowHidden(this, row)) {
      return 0;
    }
    return rowHeights[row] ?? defaultRowHeightPx;
  }

  /// setColumnWidth API.
  void setColumnWidth(int col, double px) {
    if (col < 0 || col >= excelColumnCount) {
      return;
    }
    final double v = px.clamp(minColumnWidthPx, maxColumnWidthPx);
    _importedColumnWidths.remove(col);
    if ((v - effectiveDefaultColumnWidthPx).abs() < 0.5) {
      columnWidths.remove(col);
      columnProperties[col]?.remove('customWidth');
    } else {
      columnWidths[col] = v;
    }
  }

  /// setRowHeight API.
  void setRowHeight(int row, double px) {
    if (row < 0 || row >= excelRowCount) {
      return;
    }
    final double v = px.clamp(minRowHeightPx, maxRowHeightPx);
    if ((v - defaultRowHeightPx).abs() < 0.5) {
      rowHeights.remove(row);
    } else {
      rowHeights[row] = v;
    }
  }

  /// Content X of the left edge of [col] (or the right edge when
  /// [col] == [excelColumnCount]), in unscaled pixels.
  double columnLeft(int col) {
    final int c = col < 0
        ? 0
        : (col > excelColumnCount ? excelColumnCount : col);
    final defaultWidth = effectiveDefaultColumnWidthPx;
    var x = c * defaultWidth;
    if (columnWidths.isEmpty) {
      return x;
    }
    for (final MapEntry<int, double> e in columnWidths.entries) {
      if (e.key >= 0 && e.key < c) {
        x += e.value - defaultWidth;
      }
    }
    return x;
  }

  /// Content Y of the top edge of [row] (or the bottom edge when
  /// [row] == [excelRowCount]), in unscaled pixels.
  double rowTop(int row) {
    final int r = row < 0 ? 0 : (row > excelRowCount ? excelRowCount : row);
    var y = r * defaultRowHeightPx;
    if (rowHeights.isEmpty) {
      return y;
    }
    for (final MapEntry<int, double> e in rowHeights.entries) {
      if (e.key >= 0 && e.key < r) {
        y += e.value - defaultRowHeightPx;
      }
    }
    return y;
  }

  /// columnAt API.
  int columnAt(double x) {
    if (x <= 0) {
      return 0;
    }
    final defaultWidth = effectiveDefaultColumnWidthPx;
    if (columnWidths.isEmpty) {
      return defaultWidth > 0
          ? (x / defaultWidth).floor().clamp(0, excelColumnCount - 1)
          : excelColumnCount - 1;
    }
    var col = defaultWidth > 0
        ? (x / defaultWidth).floor().clamp(0, excelColumnCount - 1)
        : 0;
    var left = columnLeft(col);
    var width = columnWidth(col);
    var guard = 0;
    while (left > x && col > 0 && guard++ < excelColumnCount) {
      col--;
      width = columnWidth(col);
      left -= width;
    }
    while (left + width <= x &&
        col < excelColumnCount - 1 &&
        guard++ < excelColumnCount) {
      left += width;
      col++;
      width = columnWidth(col);
    }
    return col;
  }

  /// hasContentAt API.
  bool hasContentAt(SmlCellRef ref) {
    final SmlRow? row = rows[ref.row];
    if (row == null) {
      return false;
    }
    final SmlCell? cell = row.cells[ref.col];
    return cell != null && cell.hasContent;
  }

  /// Bottom-right content cell, or A1 when the sheet is empty.
  SmlCellRef usedExtent() {
    var maxC = 0;
    var maxR = 0;
    var any = false;
    for (final SmlCell cell in allCells) {
      if (!cell.hasContent) {
        continue;
      }
      any = true;
      if (cell.ref.col > maxC) {
        maxC = cell.ref.col;
      }
      if (cell.ref.row > maxR) {
        maxR = cell.ref.row;
      }
    }
    for (final SmlMerge merge in merges) {
      any = true;
      if (merge.c1 > maxC) {
        maxC = merge.c1;
      }
      if (merge.r1 > maxR) {
        maxR = merge.r1;
      }
    }
    return any ? SmlCellRef(maxC, maxR) : const SmlCellRef(0, 0);
  }

  /// firstContentColOnRow API.
  int? firstContentColOnRow(int row) {
    final SmlRow? data = rows[row];
    if (data == null) {
      return null;
    }
    int? minC;
    for (final SmlCell cell in data.cells.values) {
      if (!cell.hasContent) {
        continue;
      }
      if (minC == null || cell.ref.col < minC) {
        minC = cell.ref.col;
      }
    }
    return minC;
  }

  /// lastContentColOnRow API.
  int? lastContentColOnRow(int row) {
    final SmlRow? data = rows[row];
    if (data == null) {
      return null;
    }
    int? maxC;
    for (final SmlCell cell in data.cells.values) {
      if (!cell.hasContent) {
        continue;
      }
      if (maxC == null || cell.ref.col > maxC) {
        maxC = cell.ref.col;
      }
    }
    return maxC;
  }

  /// firstContentRowOnCol API.
  int? firstContentRowOnCol(int col) {
    int? minR;
    for (final SmlRow row in rows.values) {
      final SmlCell? cell = row.cells[col];
      if (cell == null || !cell.hasContent) {
        continue;
      }
      if (minR == null || row.index < minR) {
        minR = row.index;
      }
    }
    return minR;
  }

  /// lastContentRowOnCol API.
  int? lastContentRowOnCol(int col) {
    int? maxR;
    for (final SmlRow row in rows.values) {
      final SmlCell? cell = row.cells[col];
      if (cell == null || !cell.hasContent) {
        continue;
      }
      if (maxR == null || row.index > maxR) {
        maxR = row.index;
      }
    }
    return maxR;
  }

  /// Last cell in [dc]/[dr] that has the same filled or empty state as [from].
  ///
  /// Horizontal moves look only at [from]'s row; vertical moves look only at
  /// [from]'s column. Filled cells on other rows or columns are ignored.
  /// Already at the edge of a run, the opposite run is skipped so the caret
  /// lands on the last cell of the next same-occupancy block, or stays put.
  SmlCellRef sameOccupancy(SmlCellRef from, int dc, int dr) {
    final int stepC = dc == 0 ? 0 : (dc > 0 ? 1 : -1);
    final int stepR = dr == 0 ? 0 : (dr > 0 ? 1 : -1);
    if (stepC == 0 && stepR == 0) {
      return from;
    }
    if (stepC != 0) {
      return _sameOnLine(
        start: from.col,
        step: stepC,
        maxIndex: excelColumnCount - 1,
        firstContent: firstContentColOnRow(from.row),
        lastContent: lastContentColOnRow(from.row),
        filledAt: (int col) => hasContentAt(SmlCellRef(col, from.row)),
        makeRef: (int col) => SmlCellRef(col, from.row),
      );
    }
    return _sameOnLine(
      start: from.row,
      step: stepR,
      maxIndex: excelRowCount - 1,
      firstContent: firstContentRowOnCol(from.col),
      lastContent: lastContentRowOnCol(from.col),
      filledAt: (int row) => hasContentAt(SmlCellRef(from.col, row)),
      makeRef: (int row) => SmlCellRef(from.col, row),
    );
  }

  SmlCellRef _sameOnLine({
    required int start,
    required int step,
    required int maxIndex,
    required int? firstContent,
    required int? lastContent,
    required bool Function(int index) filledAt,
    required SmlCellRef Function(int index) makeRef,
  }) {
    if (firstContent == null || lastContent == null) {
      return makeRef(start);
    }
    final bool startFilled = filledAt(start);
    bool inScan(int index) {
      if (index < 0 || index > maxIndex) {
        return false;
      }
      if (startFilled) {
        return index >= firstContent && index <= lastContent;
      }
      return index <= lastContent;
    }

    var index = start + step;
    if (!inScan(index)) {
      return makeRef(start);
    }
    if (filledAt(index) == startFilled) {
      while (inScan(index + step) && filledAt(index + step) == startFilled) {
        index += step;
      }
      return makeRef(index);
    }
    while (inScan(index + step) && filledAt(index) != startFilled) {
      index += step;
    }
    if (filledAt(index) != startFilled) {
      return makeRef(start);
    }
    while (inScan(index + step) && filledAt(index + step) == startFilled) {
      index += step;
    }
    return makeRef(index);
  }

  /// rowAt API.
  int rowAt(double y) {
    if (y <= 0) {
      return 0;
    }
    if (rowHeights.isEmpty) {
      return (y / defaultRowHeightPx).floor().clamp(0, excelRowCount - 1);
    }
    var row = (y / defaultRowHeightPx).floor().clamp(0, excelRowCount - 1);
    var top = rowTop(row);
    var height = rowHeightAt(row);
    var guard = 0;
    while (top > y && row > 0 && guard++ < excelRowCount) {
      row--;
      height = rowHeightAt(row);
      top -= height;
    }
    while (top + height <= y &&
        row < excelRowCount - 1 &&
        guard++ < excelRowCount) {
      top += height;
      row++;
      height = rowHeightAt(row);
    }
    return row;
  }

  /// Inserts [count] empty rows starting at [index], shifting existing cells down.
  void insertRows(int index, [int count = 1]) {
    if (count <= 0 || index < 0) {
      return;
    }
    final Map<int, SmlRow> next = <int, SmlRow>{};
    for (final MapEntry<int, SmlRow> e in rows.entries) {
      if (e.key >= index) {
        next[e.key + count] = _moveRow(e.value, e.key + count);
      } else {
        next[e.key] = e.value;
      }
    }
    rows
      ..clear()
      ..addAll(next);
    _shiftKeyedMap(rowHeights, index, count, remove: false);
    _shiftMerges(row: true, index: index, count: count, remove: false);
  }

  /// Inserts [count] empty columns starting at [index], shifting existing cells right.
  void insertCols(int index, [int count = 1]) {
    if (count <= 0 || index < 0) {
      return;
    }
    for (final SmlRow row in rows.values) {
      _shiftRowCells(row, index, count, remove: false);
    }
    _shiftKeyedMap(columnWidths, index, count, remove: false);
    _shiftKeyedMap(_importedColumnWidths, index, count, remove: false);
    _shiftKeyedMap(columnProperties, index, count, remove: false);
    _shiftMerges(row: false, index: index, count: count, remove: false);
  }

  /// Deletes [count] rows starting at [index], shifting remaining cells up.
  void deleteRows(int index, [int count = 1]) {
    if (count <= 0 || index < 0) {
      return;
    }
    final int last = index + count;
    final Map<int, SmlRow> next = <int, SmlRow>{};
    for (final MapEntry<int, SmlRow> e in rows.entries) {
      if (e.key >= index && e.key < last) {
        continue;
      }
      if (e.key >= last) {
        next[e.key - count] = _moveRow(e.value, e.key - count);
      } else {
        next[e.key] = e.value;
      }
    }
    rows
      ..clear()
      ..addAll(next);
    _shiftKeyedMap(rowHeights, index, count, remove: true);
    _shiftMerges(row: true, index: index, count: count, remove: true);
  }

  /// Deletes [count] columns starting at [index], shifting remaining cells left.
  void deleteCols(int index, [int count = 1]) {
    if (count <= 0 || index < 0) {
      return;
    }
    for (final SmlRow row in rows.values) {
      _shiftRowCells(row, index, -count, remove: true);
    }
    _shiftKeyedMap(columnWidths, index, count, remove: true);
    _shiftKeyedMap(_importedColumnWidths, index, count, remove: true);
    _shiftKeyedMap(columnProperties, index, count, remove: true);
    _shiftMerges(row: false, index: index, count: count, remove: true);
  }

  static SmlRow _moveRow(SmlRow source, int newIndex) {
    final SmlRow moved = SmlRow(newIndex);
    for (final MapEntry<int, SmlCell> e in source.cells.entries) {
      e.value.ref = SmlCellRef(e.key, newIndex);
      moved.cells[e.key] = e.value;
    }
    return moved;
  }

  static void _shiftRowCells(
    SmlRow row,
    int index,
    int delta, {
    required bool remove,
  }) {
    final int removedLast = remove ? index - delta : -1;
    final Map<int, SmlCell> next = <int, SmlCell>{};
    for (final MapEntry<int, SmlCell> e in row.cells.entries) {
      if (remove && e.key >= index && e.key < removedLast) {
        continue;
      }
      if (e.key >= index) {
        final int col = e.key + delta;
        e.value.ref = SmlCellRef(col, row.index);
        next[col] = e.value;
      } else {
        next[e.key] = e.value;
      }
    }
    row.cells
      ..clear()
      ..addAll(next);
  }

  static void _shiftKeyedMap<T>(
    Map<int, T> map,
    int index,
    int count, {
    required bool remove,
  }) {
    final int last = index + count;
    final Map<int, T> next = <int, T>{};
    for (final MapEntry<int, T> e in map.entries) {
      if (remove && e.key >= index && e.key < last) {
        continue;
      }
      if (e.key >= (remove ? last : index)) {
        next[e.key + (remove ? -count : count)] = e.value;
      } else {
        next[e.key] = e.value;
      }
    }
    map
      ..clear()
      ..addAll(next);
  }

  void _shiftMerges({
    required bool row,
    required int index,
    required int count,
    required bool remove,
  }) {
    final int last = index + count;
    final List<SmlMerge> next = <SmlMerge>[];
    for (final SmlMerge merge in merges) {
      var a = row ? merge.r0 : merge.c0;
      var b = row ? merge.r1 : merge.c1;
      if (remove && b >= index && a < last) {
        if (a >= index && b < last) {
          continue;
        }
        if (a < index) {
          b = index - 1;
        } else {
          a = last;
        }
      }
      if (a >= (remove ? last : index)) {
        final int delta = remove ? -count : count;
        a += delta;
        b += delta;
      } else if (!remove && a < index && b >= index) {
        b += count;
      } else if (remove && a < index && b >= last) {
        b -= count;
      }
      if (a > b) {
        continue;
      }
      if (row) {
        next.add(SmlMerge(c0: merge.c0, r0: a, c1: merge.c1, r1: b));
      } else {
        next.add(SmlMerge(c0: a, r0: merge.r0, c1: b, r1: merge.r1));
      }
    }
    merges
      ..clear()
      ..addAll(next);
  }
}

/// Class SmlWorkbook.
class SmlWorkbook {
  /// SmlWorkbook API.
  SmlWorkbook({
    List<SmlWorksheet>? sheets,
    List<String>? sharedStrings,
    List<SmlNamedRange>? namedRanges,
    List<SmlFormulaName>? formulaNames,
    OfficeDocumentProperties? properties,
    this.package,
    this.styles,
  }) : sheets =
           sheets ?? <SmlWorksheet>[SmlWorksheet(name: 'Sheet1', sheetId: 1)],
       sharedStrings = sharedStrings ?? <String>[],
       namedRanges = namedRanges ?? <SmlNamedRange>[],
       formulaNames = formulaNames ?? <SmlFormulaName>[],
       properties = properties ?? OfficeDocumentProperties();

  /// sheets API.
  List<SmlWorksheet> sheets;

  /// sharedStrings API.
  List<String> sharedStrings;

  /// namedRanges API.
  final List<SmlNamedRange> namedRanges;

  /// Native scalar and unsupported definitions, including worksheet scopes.
  final List<SmlFormulaName> formulaNames;

  Iterable<SmlDefinedName> get definedNames sync* {
    yield* namedRanges;
    yield* formulaNames;
  }

  /// properties API.
  OfficeDocumentProperties properties;

  /// package API.
  OpcPackage? package;

  /// Native names may contain expressions, scopes and print references that
  /// the compact named-range projection cannot represent independently.
  String? sourceDefinedNameState;

  /// Snapshot used to retain the native name collection without losing names
  /// outside the editable A1-range projection.
  String definedNameState({
    String? from,
    String? to,
    String Function(String)? rewriteFormula,
  }) {
    String sheetName(String value) =>
        from != null && value.toLowerCase() == from.toLowerCase() ? to! : value;
    String? range(SmlRange? value) =>
        value == null ? null : '${value.start.a1}:${value.end.a1}';
    return jsonEncode([
      [
        for (final name in namedRanges)
          [
            name.name,
            name.localSheetId,
            sheetName(name.sheetName),
            range(name.range),
            name.attributes,
          ],
      ],
      [
        for (final name in formulaNames)
          [
            name.name,
            name.localSheetId,
            rewriteFormula?.call(name.formula) ?? name.formula,
            name.attributes,
          ],
      ],
      [
        for (final sheet in sheets)
          [
            sheetName(sheet.name),
            range(sheet.printTitleRows),
            range(sheet.printTitleCols),
          ],
      ],
    ]);
  }

  /// styles API.
  SmlStyleSheet? styles;

  /// Last successfully measured font, or null while using fallback metrics.
  SmlColumnMetrics? get columnMetrics => _columnMetrics;
  SmlColumnMetrics? _columnMetrics;

  /// Gives newly added sheets the already resolved workbook font before export.
  void applyResolvedColumnMetrics() {
    final metrics = _columnMetrics;
    if (metrics == null) return;
    for (final sheet in sheets) {
      sheet.applyColumnMetrics(metrics.maximumDigitWidthPx);
    }
  }

  /// Resolves the native Normal style without asking the pure engine to locate
  /// platform fonts. Null results leave the current metric and geometry intact.
  bool resolveColumnMetrics(SmlColumnMetricsResolver resolver) {
    final font = styles?.normalFont;
    if (font == null) return false;
    final measured = resolver(font);
    if (measured == null) return false;
    if (measured.maximumDigitWidthPx <= 0 ||
        measured.resolvedFontFamily.trim().isEmpty) {
      throw ArgumentError.value(measured, 'columnMetrics');
    }
    _columnMetrics = measured;
    applyResolvedColumnMetrics();
    return true;
  }

  /// firstSheet API.
  SmlWorksheet get firstSheet => sheets.first;

  /// namedRange API.
  SmlNamedRange? namedRange(String name, {SmlWorksheet? onSheet}) =>
      switch (definedName(name, onSheet: onSheet)) {
        final SmlNamedRange range => range,
        _ => null,
      };

  /// Locals shadow globals, even when the local definition cannot be evaluated.
  /// Explicit worksheet qualification uses [localOnly] and never guesses a
  /// global fallback. Ambiguous native names are retained but not calculated.
  SmlDefinedName? definedName(
    String name, {
    SmlWorksheet? onSheet,
    bool localOnly = false,
  }) {
    final key = name.toUpperCase();
    SmlDefinedName? find(int? scope) {
      SmlDefinedName? result;
      for (final candidate in definedNames) {
        if (candidate.name.toUpperCase() == key &&
            candidate.localSheetId == scope) {
          if (result != null) {
            throw UnsupportedError('Ambiguous defined name $name');
          }
          result = candidate;
        }
      }
      return result;
    }

    if (onSheet != null) {
      final index = sheets.indexOf(onSheet);
      if (index < 0) throw ArgumentError.value(onSheet, 'onSheet');
      final local = find(index);
      if (local != null) return local;
    }
    return localOnly ? null : find(null);
  }

  /// sheetByName API.
  SmlWorksheet? sheetByName(String name) {
    final key = name.toLowerCase();
    for (final SmlWorksheet s in sheets) {
      if (s.name.toLowerCase() == key) {
        return s;
      }
    }
    return null;
  }
}
