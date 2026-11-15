// Bounded OpenDocument Spreadsheet (`.ods`) reader.
//
// ODF stores typed values in attributes (`office:value`, `office:date-value`,
// …), collapses runs of cells with `table:number-columns-repeated`, and keeps
// style names in a separate automatic-style table. Reading only `text:p`
// shifts columns and loses numbers, which is what the previous extraction did.
//
// This produces the same [SmlWorkbook] model as the OOXML and BIFF paths, so an
// imported ODS can be edited and saved as `.xlsx`.

import 'dart:convert';
import 'dart:typed_data';

import '../../opc/zip/zip_reader.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../model/sml_analysis.dart';
import '../model/sml_workbook.dart';
import '../styles/sml_styles.dart';

typedef _OdsAnnotation = ({String text, String author});
typedef _OdsCellContent = ({
  Object? value,
  String? formula,
  String? valueType,
  _OdsAnnotation? annotation,
});

/// Thrown when an ODS package cannot be read safely.
class OdsSheetFormatException implements Exception {
  /// OdsSheetFormatException API.
  const OdsSheetFormatException(this.message);

  /// message API.
  final String message;

  @override
  String toString() => 'OdsSheetFormatException: $message';
}

/// Reads an `.ods` package into [SmlWorkbook].
abstract final class OdsSheetReader {
  static const double _odfMaxDigitWidthPx = 7.4;
  static const double _odfDefaultColumnWidthIn = 0.8898;
  static const double _odfDefaultRowHeightPoints = 14.95;
  static const int _maxRows = 100000;
  static const int _maxColumns = 4096;
  static const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
  static const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
  static const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
  static const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
  static const _number = 'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0';
  static const _dc = 'http://purl.org/dc/elements/1.1/';
  static const _fo =
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';

  /// Reads a bounded spreadsheet, declining unsupported expansion instead of
  /// silently clipping cells. Empty padding advances coordinates arithmetically.
  static SmlWorkbook readBytes(Uint8List bytes) {
    final budget = _OdsBudget();
    final ZipReader zip;
    try {
      if (bytes.length > 64 * 1024 * 1024) {
        throw const OdsSheetFormatException('ODS input exceeds 64 MiB');
      }
      zip = ZipReader.fromBytes(bytes, maxEntries: 10000);
    } on Object catch (error) {
      throw OdsSheetFormatException('Not an ODF package: $error');
    }
    final root = _readXml(zip, 'content.xml', budget);
    if (!_is(root, 'document-content', _office)) {
      throw const OdsSheetFormatException('Expected an ODF content document');
    }
    final spreadsheet = root
        .firstChild('body', namespaceUri: _office)
        ?.firstChild('spreadsheet', namespaceUri: _office);
    if (spreadsheet == null) {
      throw const OdsSheetFormatException('Document is not an ODF spreadsheet');
    }

    final styles = <String, XmlElement>{};
    final numberStyles = <String, XmlElement>{};
    void collectStyles(XmlElement styleRoot) {
      for (final collection in ['styles', 'automatic-styles']) {
        final parent = styleRoot.firstChild(collection, namespaceUri: _office);
        if (parent == null) continue;
        for (final style in parent.childElements) {
          final name = _attribute(style, 'name', _style);
          if (name == null) continue;
          if (_is(style, 'style', _style)) {
            final family = _attribute(style, 'family', _style);
            if (family != null) styles['$family:$name'] = style;
          } else if (style.namespaceUri == _number) {
            numberStyles[name] = style;
          }
          if (styles.length + numberStyles.length > 4096) {
            throw const OdsSheetFormatException('ODS style definition limit');
          }
        }
      }
    }

    if (zip.contains('styles.xml')) {
      final named = _readXml(zip, 'styles.xml', budget);
      if (!_is(named, 'document-styles', _office)) {
        throw const OdsSheetFormatException('Invalid ODF named styles');
      }
      collectStyles(named);
    }
    collectStyles(root);

    final book = SmlWorkbook(sheets: <SmlWorksheet>[], styles: SmlStyleSheet());
    final tables = spreadsheet.childrenNamed('table', namespaceUri: _table);
    if (tables.isEmpty || tables.length > 128) {
      throw const OdsSheetFormatException('ODS requires 1 to 128 worksheets');
    }
    for (final table in tables) {
      final name = _attribute(table, 'name', _table)?.trim();
      final sheet = SmlWorksheet(
        name: name == null || name.isEmpty
            ? 'Sheet${book.sheets.length + 1}'
            : name,
        sheetId: book.sheets.length + 1,
      );
      sheet.importDefaultColumnWidth(
        excelWidth: _odfDefaultColumnWidthIn * 96 / _odfMaxDigitWidthPx,
      );
      final columnDefaults = _readColumns(table, sheet, styles, budget);
      var rowIndex = 0;
      final pendingRowHeights = <({int start, int count, double height})>[];
      for (final row in _members(table, 'table-row', const {
        'table-row-group',
        'table-rows',
        'table-header-rows',
      })) {
        final rowRepeat = _repeat(row, 'number-rows-repeated');
        final rowDefault = _attribute(row, 'default-cell-style-name', _table);
        final rowStyle = _styleChain(
          styles,
          'table-row',
          _attribute(row, 'style-name', _table),
        );
        final rowHeight = _lengthToPoints(
          _property(rowStyle, 'table-row-properties', 'row-height', _style),
        );
        final entries =
            <
              ({
                int column,
                int repeat,
                int colSpan,
                int rowSpan,
                SmlCell? cell,
                _OdsAnnotation? annotation,
              })
            >[];
        var column = 0;
        var pendingCovered = 0;
        for (final element in row.childElements) {
          if (element.namespaceUri != _table ||
              (element.localName != 'table-cell' &&
                  element.localName != 'covered-table-cell')) {
            continue;
          }
          final repeat = _repeat(element, 'number-columns-repeated');
          if (element.localName == 'covered-table-cell') {
            if (_attribute(element, 'value-type', _office) != null ||
                _attribute(element, 'formula', _table) != null ||
                _text(element).isNotEmpty ||
                _readAnnotation(element) != null) {
              throw const OdsSheetFormatException('Covered cell contains data');
            }
            // A spanning origin already reserves its covered columns. Consume
            // explicit placeholders once; additional covered positions still
            // advance normally, including cells covered by a vertical merge.
            final reserved = repeat < pendingCovered ? repeat : pendingCovered;
            pendingCovered -= reserved;
            column += repeat - reserved;
            continue;
          }
          if (pendingCovered > 0) {
            throw const OdsSheetFormatException(
              'Stored cell inside a merge requires a covered-cell token',
            );
          }
          final colSpan = _repeat(element, 'number-columns-spanned');
          final rowSpan = _repeat(element, 'number-rows-spanned');
          if (_repeat(element, 'number-matrix-columns-spanned') > 1 ||
              _repeat(element, 'number-matrix-rows-spanned') > 1) {
            throw const OdsSheetFormatException(
              'Matrix formulas are not supported',
            );
          }
          if (element.childrenNamed('table', namespaceUri: _table).isNotEmpty) {
            throw const OdsSheetFormatException(
              'Nested ODS tables are not supported',
            );
          }
          // Parse values and formulas once, then resolve each column's style.
          // Repetition can cross columns with different default cell styles.
          final content = _readCellContent(element);
          if (content.annotation != null) budget.comments(repeat * rowRepeat);
          final explicitStyle = _attribute(element, 'style-name', _table);
          final defaultStyle = explicitStyle ?? rowDefault;
          for (final run in _cellStyleRuns(
            column,
            repeat,
            defaultStyle,
            columnDefaults,
            budget,
          )) {
            final cell = _createCell(
              content,
              run.styleName,
              book.styles!,
              styles,
              numberStyles,
              budget,
              preserveEmptyStyle:
                  explicitStyle != null && explicitStyle != 'Default',
            );
            if (cell != null || colSpan > 1 || rowSpan > 1) {
              if (run.column + run.repeat + colSpan - 1 > _maxColumns ||
                  rowIndex + rowRepeat + rowSpan - 1 > _maxRows) {
                throw const OdsSheetFormatException(
                  'ODS data exceeds the supported grid',
                );
              }
              if ((colSpan > 1 || rowSpan > 1) &&
                  (repeat > 1 || (rowSpan > 1 && rowRepeat > 1))) {
                throw const OdsSheetFormatException(
                  'Repeated merged anchors are not supported',
                );
              }
              if (cell?.formula != null && (repeat > 1 || rowRepeat > 1)) {
                throw const OdsSheetFormatException(
                  'Repeated formulas are not supported',
                );
              }
              if (cell != null) {
                final count = run.repeat * rowRepeat;
                budget.cells(count);
                final value = cell.value;
                budget.cellText(
                  ((value is String ? utf8.encode(value).length : 0) +
                          (cell.formula == null
                              ? 0
                              : utf8.encode(cell.formula!).length) +
                          (content.annotation == null
                              ? 0
                              : utf8.encode(content.annotation!.text).length +
                                    utf8
                                        .encode(content.annotation!.author)
                                        .length)) *
                      count,
                );
              }
              entries.add((
                column: run.column,
                repeat: run.repeat,
                colSpan: colSpan,
                rowSpan: rowSpan,
                cell: cell,
                annotation: content.annotation,
              ));
            }
          }
          column += repeat + colSpan - 1;
          pendingCovered = colSpan - 1;
        }
        // Empty runs do not allocate cells, but must retain their exact row
        // count: data after an internal gap must never move or disappear.
        if (entries.isNotEmpty) {
          for (final pending in pendingRowHeights) {
            budget.dimensions(pending.count);
            for (var r = 0; r < pending.count; r++) {
              sheet.rowHeights[pending.start + r] = pending.height;
            }
          }
          pendingRowHeights.clear();
        }
        if (rowHeight != null &&
            rowHeight > 0 &&
            (entries.isNotEmpty ||
                (rowHeight - _odfDefaultRowHeightPoints).abs() > 0.1) &&
            rowIndex + rowRepeat <= _maxRows) {
          final height = SmlWorksheet.rowHeightFromExcel(rowHeight);
          if (entries.isEmpty && rowRepeat > 1) {
            // Defer empty height runs until data follows. Styled trailing
            // padding remains sparse; internal heights retain the same budget.
            pendingRowHeights.add((
              start: rowIndex,
              count: rowRepeat,
              height: height,
            ));
          } else {
            budget.dimensions(rowRepeat);
            for (var r = 0; r < rowRepeat; r++) {
              sheet.rowHeights[rowIndex + r] = height;
            }
          }
        }
        if (entries.isNotEmpty) {
          for (var r = 0; r < rowRepeat; r++) {
            for (final entry in entries) {
              for (var c = 0; c < entry.repeat; c++) {
                final ref = SmlCellRef(entry.column + c, rowIndex + r);
                if (sheet.merges.isNotEmpty) {
                  budget.mergeCoverage(sheet.merges.length);
                  if (sheet.merges.any((merge) => merge.containsRef(ref))) {
                    throw const OdsSheetFormatException(
                      'Stored cell inside a merge requires a covered-cell token',
                    );
                  }
                }
                if (entry.cell case final source?) {
                  _copyCell(source, sheet.cell(ref));
                }
                if (entry.annotation case final annotation?) {
                  // Every coordinate is materialized once, after the shared
                  // cell/text budgets and merge coverage have been checked.
                  sheet.comments.add(
                    SmlComment(
                      ref: ref,
                      text: annotation.text,
                      author: annotation.author,
                    ),
                  );
                }
                if (entry.colSpan > 1 || entry.rowSpan > 1) {
                  final merge = SmlMerge(
                    c0: ref.col,
                    r0: ref.row,
                    c1: ref.col + entry.colSpan - 1,
                    r1: ref.row + entry.rowSpan - 1,
                  );
                  budget.merge();
                  if (sheet.merges.any(
                    (existing) => existing.overlaps(merge),
                  )) {
                    throw const OdsSheetFormatException(
                      'Overlapping ODS merges',
                    );
                  }
                  sheet.merges.add(merge);
                }
              }
            }
          }
        }
        rowIndex += rowRepeat;
      }
      book.sheets.add(sheet);
    }
    return book;
  }

  static XmlElement _readXml(ZipReader zip, String part, _OdsBudget budget) {
    try {
      if (!zip.contains(part)) throw OdsSheetFormatException('Missing $part');
      final bytes = zip.read(part, maxBytes: 64 * 1024 * 1024);
      budget.xml(bytes.length);
      final source = utf8.decode(bytes);
      final reader = XmlPullReader(source);
      var roots = 0;
      var open = 0;
      while (reader.next()) {
        budget.xmlEvent();
        if (reader.eventType == XmlEventType.dtd) {
          throw const OdsSheetFormatException(
            'DTD declarations are not supported',
          );
        }
        if (reader.eventType == XmlEventType.startElement) {
          if (open++ == 0) roots++;
          if (open > 128) {
            throw const OdsSheetFormatException('XML nesting limit');
          }
        } else if (reader.eventType == XmlEventType.endElement) {
          open--;
          if (open < 0) throw const OdsSheetFormatException('Unbalanced XML');
        }
      }
      if (roots != 1 || open != 0) {
        throw const OdsSheetFormatException('Unbalanced XML document');
      }
      // ODF number:text whitespace is an authored separator. The generic
      // document parser drops leading whitespace-only nodes; the element
      // reader retains them after the same complete bounded validation.
      final materializer = XmlPullReader(source);
      while (materializer.next()) {
        if (materializer.eventType == XmlEventType.startElement) {
          return XmlDocument.readElement(materializer);
        }
      }
      throw const OdsSheetFormatException('Missing XML document root');
    } on OdsSheetFormatException {
      rethrow;
    } on Object catch (error) {
      throw OdsSheetFormatException('Cannot read $part: $error');
    }
  }

  static void _copyCell(SmlCell source, SmlCell target) {
    target
      ..type = source.type
      ..value = source.value
      ..formula = source.formula
      ..styleIndex = source.styleIndex
      ..hasExplicitStyleIndex = source.hasExplicitStyleIndex
      ..horizontalAlign = source.horizontalAlign
      ..wrapText = source.wrapText
      ..fillRgb = source.fillRgb
      ..hasExplicitFillColorEdit = source.hasExplicitFillColorEdit
      ..fontRgb = source.fontRgb
      ..hasExplicitFontColorEdit = source.hasExplicitFontColorEdit
      ..fontBold = source.fontBold
      ..fontSize = source.fontSize
      ..fontFamily = source.fontFamily;
  }

  static Map<int, String> _readColumns(
    XmlElement table,
    SmlWorksheet sheet,
    Map<String, XmlElement> styles,
    _OdsBudget budget,
  ) {
    final defaults = <int, String>{};
    var column = 0;
    for (final element in _members(table, 'table-column', const {
      'table-column-group',
      'table-columns',
      'table-header-columns',
    })) {
      final repeat = _repeat(element, 'number-columns-repeated');
      final style = _styleChain(
        styles,
        'table-column',
        _attribute(element, 'style-name', _table),
      );
      final width = _lengthToPoints(
        _property(style, 'table-column-properties', 'column-width', _style),
      );
      final cellStyle = _attribute(element, 'default-cell-style-name', _table);
      // Column definitions commonly include a full-sheet metadata tail. It
      // has no cells to preserve outside the admitted grid.
      final end = (column + repeat).clamp(0, _maxColumns);
      final count = (end - column).clamp(0, _maxColumns);
      if (width != null && width > 0) {
        // Retain the native Excel character units used by ODF producers so
        // an XLSX round trip does not apply a second pixel conversion.
        final chars = width * 96 / 72 / _odfMaxDigitWidthPx;
        final defaultChars =
            _odfDefaultColumnWidthIn * 96 / _odfMaxDigitWidthPx;
        if ((chars - defaultChars).abs() > 0.05) {
          budget.dimensions(count);
          for (var i = 0; i < count; i++) {
            sheet.importColumnWidth(column + i, chars);
          }
        }
      }
      if (cellStyle != null) {
        budget.dimensions(count);
        for (var i = 0; i < count; i++) {
          defaults[column + i] = cellStyle;
        }
      }
      column += repeat;
    }
    return defaults;
  }

  static Iterable<({int column, int repeat, String? styleName})> _cellStyleRuns(
    int column,
    int repeat,
    String? defaultStyle,
    Map<int, String> columnDefaults,
    _OdsBudget budget,
  ) sync* {
    if (defaultStyle != null ||
        columnDefaults.isEmpty ||
        column >= _maxColumns) {
      yield (column: column, repeat: repeat, styleName: defaultStyle);
      return;
    }
    final end = column + repeat;
    final admittedEnd = end.clamp(0, _maxColumns);
    budget.styleWork(admittedEnd - column);
    var start = column;
    var styleName = columnDefaults[column];
    for (var next = column + 1; next < admittedEnd; next++) {
      final nextStyle = columnDefaults[next];
      if (nextStyle == styleName) continue;
      yield (column: start, repeat: next - start, styleName: styleName);
      start = next;
      styleName = nextStyle;
    }
    yield (column: start, repeat: admittedEnd - start, styleName: styleName);
    if (end > admittedEnd) {
      // Meaningful values in this tail still reach the grid refusal. Empty
      // padding does not allocate or iterate beyond the admitted columns.
      yield (column: admittedEnd, repeat: end - admittedEnd, styleName: null);
    }
  }

  static _OdsCellContent _readCellContent(XmlElement element) {
    Object? value;
    final valueType = _attribute(element, 'value-type', _office);
    switch (valueType) {
      case 'float':
      case 'currency':
      case 'percentage':
        final number = double.tryParse(
          _attribute(element, 'value', _office) ?? '',
        );
        if (number == null || !number.isFinite) {
          throw const OdsSheetFormatException('Invalid ODS numeric value');
        }
        value = number;
      case 'date':
        final parsed = DateTime.tryParse(
          _attribute(element, 'date-value', _office) ?? '',
        );
        if (parsed == null) {
          throw const OdsSheetFormatException('Invalid ODS date');
        }
        value = _excelSerial(parsed);
      case 'time':
        value = _odfDurationDays(_attribute(element, 'time-value', _office));
        if (value == null) {
          throw const OdsSheetFormatException('Invalid ODS time');
        }
      case 'boolean':
        value = switch (_attribute(element, 'boolean-value', _office)) {
          'true' || '1' => true,
          'false' || '0' => false,
          _ => throw const OdsSheetFormatException('Invalid ODS boolean'),
        };
      case 'string':
        value = _attribute(element, 'string-value', _office) ?? _text(element);
      case null:
        value = _text(element);
      default:
        throw OdsSheetFormatException('Unsupported ODS value type: $valueType');
    }
    if (value is String && value.length > 1024 * 1024) {
      throw const OdsSheetFormatException('ODS cell text limit');
    }
    if (value is String && value.isEmpty) value = null;
    final formula = _translateFormula(_attribute(element, 'formula', _table));
    return (
      value: value,
      formula: formula,
      valueType: valueType,
      annotation: _readAnnotation(element),
    );
  }

  static _OdsAnnotation? _readAnnotation(XmlElement element) {
    Iterable<XmlElement> annotationNodes(XmlElement parent) sync* {
      for (final child in parent.childElements) {
        if (child.localName == 'annotation') yield child;
        yield* annotationNodes(child);
      }
    }

    final annotations = annotationNodes(element).toList();
    if (annotations.isEmpty) return null;
    if (annotations.length != 1 ||
        annotations.single.namespaceUri != _office ||
        annotations.single.parent != element) {
      throw const OdsSheetFormatException(
        'Multiple or foreign-namespace ODS annotations are not supported',
      );
    }
    final annotation = annotations.single;
    final creators = annotation.childElements
        .where((child) => child.localName == 'creator')
        .toList();
    if (creators.length > 1 ||
        creators.any((creator) => creator.namespaceUri != _dc)) {
      throw const OdsSheetFormatException(
        'Ambiguous or foreign-namespace ODS annotation author',
      );
    }
    final author = creators.firstOrNull?.text.trim();
    if (author != null && author.length > 1024 * 1024) {
      throw const OdsSheetFormatException('ODS annotation author limit');
    }
    return (
      text: _text(annotation),
      author: author == null || author.isEmpty ? 'Quds Office' : author,
    );
  }

  static SmlCell? _createCell(
    _OdsCellContent content,
    String? styleName,
    SmlStyleSheet engineStyles,
    Map<String, XmlElement> styles,
    Map<String, XmlElement> numberStyles,
    _OdsBudget budget, {
    required bool preserveEmptyStyle,
  }) {
    final (:value, :formula, :valueType, :annotation) = content;
    // The named Default style on empty spreadsheet padding is not cell data.
    if (value == null &&
        formula == null &&
        annotation == null &&
        (styleName == null || styleName == 'Default')) {
      return null;
    }
    final style = _styleChain(styles, 'table-cell', styleName);
    final bold = _isBold(
      _property(style, 'text-properties', 'font-weight', _fo),
    );
    final fontSize = _lengthToPoints(
      _property(style, 'text-properties', 'font-size', _fo),
    );
    final color = _hex(_property(style, 'text-properties', 'color', _fo));
    final fill = _hex(
      _property(style, 'table-cell-properties', 'background-color', _fo),
    );
    final align = _align(
      _property(style, 'paragraph-properties', 'text-align', _fo),
    );
    final wrap =
        _property(style, 'table-cell-properties', 'wrap-option', _fo) == 'wrap';
    final family = _family(
      _property(style, 'text-properties', 'font-family', _fo),
    );
    final numFmt = _numberFormat(
      _styleAttribute(style, 'data-style-name'),
      numberStyles,
      valueType,
    );
    // Inherited column/row defaults apply to real cells, but materializing
    // every cell of a 16k-column padding run would create millions of empty
    // cells. Only an explicit, non-default cell style can stand alone.
    final styled =
        preserveEmptyStyle &&
        (bold ||
            fontSize != null ||
            color != null ||
            fill != null ||
            align != SmlHAlign.general ||
            wrap ||
            family != null ||
            numFmt != null);

    if (value == null && formula == null && !styled && annotation == null) {
      return null;
    }

    final cell = SmlCell(ref: const SmlCellRef(0, 0));
    if (value != null) {
      cell.value = value;
      cell.type = value is bool
          ? SmlCellType.boolean
          : value is num
          ? SmlCellType.number
          : SmlCellType.string;
    }
    if (formula != null) {
      cell.formula = formula;
      cell.type = SmlCellType.formula;
    }
    cell
      ..fontBold = bold
      ..horizontalAlign = align
      ..wrapText = wrap;
    if (fontSize != null) cell.fontSize = fontSize;
    if (color != null) cell.fontRgb = color;
    if (fill != null) cell.fillRgb = fill;
    if (family != null) cell.fontFamily = family;
    // xfFor searches existing style tables. Count that work before calling it,
    // as a large set of distinct imported styles otherwise makes this quadratic.
    budget.styleWork(
      engineStyles.cellXfsAlign.length +
          engineStyles.fillRgbs.length +
          engineStyles.fontFamilies.length +
          1,
    );
    cell.styleIndex = engineStyles.xfFor(
      align: align,
      fillRgb: fill ?? '',
      fillColorExplicit: fill != null,
      fontRgb: color ?? '',
      fontColorExplicit: color != null,
      bold: bold,
      size: fontSize ?? 11,
      fontFamily: family ?? '',
      numFmtCode: numFmt,
      wrapText: wrap,
    );
    cell.hasExplicitStyleIndex = true;
    return cell;
  }

  static String? _translateFormula(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.length > 1024 * 1024) {
      throw const OdsSheetFormatException('ODS formula length limit');
    }
    final equals = raw.indexOf('=');
    if (equals < 0) throw const OdsSheetFormatException('Invalid ODS formula');
    final formula = raw.substring(equals + 1);
    final result = StringBuffer();
    var quoted = false;
    for (var i = 0; i < formula.length; i++) {
      final char = formula[i];
      if (char == '"') {
        result.write(char);
        if (quoted && i + 1 < formula.length && formula[i + 1] == '"') {
          result.write(formula[++i]);
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && char == '[') {
        final end = formula.indexOf(']', i + 1);
        if (end < 0) {
          throw const OdsSheetFormatException('Invalid ODS reference');
        }
        result.write(
          formula.substring(i + 1, end).split(':').map(_odfReference).join(':'),
        );
        i = end;
      } else if (!quoted && char == ';') {
        result.write(',');
      } else if (!quoted &&
          (i == 0 || !_formulaNameCharacter(formula.codeUnitAt(i - 1))) &&
          (formula.startsWith('COM.MICROSOFT.', i) ||
              formula.startsWith('ORG.OPENOFFICE.', i))) {
        i += formula.startsWith('COM.MICROSOFT.', i)
            ? 'COM.MICROSOFT.'.length - 1
            : 'ORG.OPENOFFICE.'.length - 1;
      } else {
        result.write(char);
      }
    }
    if (quoted) {
      throw const OdsSheetFormatException('Unterminated formula string');
    }
    final translated = result.toString();
    return translated.trim().isEmpty ? null : translated;
  }

  static bool _formulaNameCharacter(int value) =>
      value == 0x5f ||
      (value >= 0x30 && value <= 0x39) ||
      (value >= 0x41 && value <= 0x5a) ||
      (value >= 0x61 && value <= 0x7a);

  static String _odfReference(String raw) {
    var reference = raw.trim();
    if (reference.startsWith('.')) reference = reference.substring(1);
    final dot = reference.lastIndexOf('.');
    if (dot <= 0) return reference;
    var sheet = reference.substring(0, dot).trim();
    // ODF's absolute sheet marker is separate from the cell's absolute row
    // and column markers, which remain unchanged in the XLSX reference.
    if (sheet.startsWith(r'$')) sheet = sheet.substring(1);
    final cell = reference.substring(dot + 1);
    final quoted = sheet.startsWith("'") && sheet.endsWith("'");
    if (quoted) {
      sheet = sheet.substring(1, sheet.length - 1);
    }
    if (sheet.isEmpty) return cell;
    return quoted || sheet.contains(' ') ? "'$sheet'!$cell" : '$sheet!$cell';
  }

  static String? _numberFormat(
    String? name,
    Map<String, XmlElement> numberStyles,
    String? valueType,
  ) {
    final style = name == null ? null : numberStyles[name];
    if (style == null) return valueType == 'percentage' ? '0.00%' : null;
    switch (style.localName) {
      case 'percentage-style':
        return '${_zeros(style)}%';
      case 'currency-style':
        final symbol = _descendants(
          style,
          'currency-symbol',
          _number,
        ).map((element) => element.text).firstOrNull;
        final decimals = _decimals(style);
        final base = '#,##0${decimals == 0 ? '' : '.${'0' * decimals}'}';
        if (symbol == r'$') {
          return r'[$$-409]'
              '$base'
              r';[red]-[$$-409]'
              '$base';
        }
        if (symbol == null || symbol.isEmpty) return base;
        return '"$symbol"$base';
      case 'date-style':
        return _dateFormat(style);
      case 'time-style':
        return _timeFormat(style);
      case 'number-style':
        final decimals = _decimals(style);
        final grouping = _descendants(
          style,
          'number',
          _number,
        ).any((element) => _attribute(element, 'grouping', _number) == 'true');
        final integer = grouping ? '#,##0' : '0';
        return decimals == 0 ? integer : '$integer.${'0' * decimals}';
    }
    return null;
  }

  /// Keeps the authored component order and literal text of an ODF date style.
  static String _dateFormat(XmlElement style) {
    final buffer = StringBuffer();
    for (final child in style.childElements) {
      if (child.namespaceUri != _number) continue;
      final short = _attribute(child, 'style', _number) == 'short';
      switch (child.localName) {
        case 'year':
          buffer.write(short ? 'YY' : 'YYYY');
        case 'month':
          final textual = _attribute(child, 'textual', _number);
          buffer.write(
            textual == 'true' || textual == '1'
                ? (short ? 'MMM' : 'MMMM')
                : (short ? 'M' : 'MM'),
          );
        case 'day':
          buffer.write(short ? 'D' : 'DD');
        case 'day-of-week':
          buffer.write(
            _attribute(child, 'style', _number) == 'long' ? 'DDDD' : 'DDD',
          );
        case 'hours':
          buffer.write(short ? 'H' : 'HH');
        case 'minutes':
          buffer.write(short ? 'M' : 'MM');
        case 'seconds':
          buffer.write(short ? 'S' : 'SS');
        case 'am-pm':
          buffer.write('AM/PM');
        case 'text':
          // Each literal character is escaped, including format letters,
          // quotes, slashes and semicolons; it cannot become an Excel token.
          // Retain an empty component and any authored spaces exactly.
          for (final code in child.text.runes) {
            buffer.write('\\${String.fromCharCode(code)}');
          }
      }
    }
    return buffer.isEmpty ? 'DD.MM.YYYY' : buffer.toString();
  }

  static String _timeFormat(XmlElement style) {
    final hours = _descendants(style, 'hours', _number).firstOrNull;
    final minutes = _descendants(style, 'minutes', _number).firstOrNull;
    final seconds = _descendants(style, 'seconds', _number).firstOrNull;
    final elapsed = switch (_attribute(
      style,
      'truncate-on-overflow',
      _number,
    )) {
      'false' || '0' => true,
      _ => false,
    };
    String leading(XmlElement component, String symbol) {
      final token = _attribute(component, 'style', _number) == 'long'
          ? symbol * 2
          : symbol;
      return elapsed ? '[$token]' : token;
    }

    if (hours != null) {
      return '${leading(hours, 'h')}${minutes == null ? '' : ':mm'}'
          '${seconds == null ? '' : ':ss'}';
    }
    if (minutes != null && (seconds != null || elapsed)) {
      final token = elapsed ? leading(minutes, 'm') : 'mm';
      return '$token${seconds == null ? '' : ':ss'}';
    }
    if (seconds != null) return elapsed ? leading(seconds, 's') : 'ss';
    return 'h:mm:ss';
  }

  static String _zeros(XmlElement style) {
    final decimals = _decimals(style);
    return decimals == 0 ? '0' : '0.${'0' * decimals}';
  }

  static int _decimals(XmlElement style) {
    final number = _descendants(style, 'number', _number).firstOrNull;
    final value = int.tryParse(
      number?.getAttribute('decimal-places', namespaceUri: _number) ?? '',
    );
    return (value ?? 0).clamp(0, 10);
  }

  static double _excelSerial(DateTime value) {
    final epoch = DateTime.utc(1899, 12, 30);
    final civil = value.isUtc
        ? value
        : DateTime.utc(
            value.year,
            value.month,
            value.day,
            value.hour,
            value.minute,
            value.second,
            value.millisecond,
            value.microsecond,
          );
    return civil.difference(epoch).inMilliseconds / 86400000;
  }

  static double? _odfDurationDays(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final hours = double.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = double.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = double.tryParse(match.group(3) ?? '') ?? 0;
    return (hours * 3600 + minutes * 60 + seconds) / 86400;
  }

  static String _text(XmlElement element) {
    Iterable<XmlElement> bodyParagraphs(XmlElement parent) sync* {
      for (final child in parent.childElements) {
        // An annotation is a separate story, never part of its cell value.
        // Its own text is read by calling _text on the annotation root.
        if (child.localName == 'annotation') continue;
        if (_is(child, 'p', _textNs)) yield child;
        yield* bodyParagraphs(child);
      }
    }

    final paragraphs = bodyParagraphs(element).toList();
    final buffer = StringBuffer();
    void write(String value) {
      if (buffer.length + value.length > 1024 * 1024) {
        throw const OdsSheetFormatException('ODS cell text limit');
      }
      buffer.write(value);
    }

    void inline(XmlNode node) {
      if (node is XmlText) {
        write(node.text);
      } else if (node is XmlCdata) {
        write(node.text);
      } else if (node is XmlElement) {
        if (node.localName == 'annotation') return;
        if (_is(node, 's', _textNs)) {
          final count = _repeat(node, 'c', namespace: _textNs);
          if (count > 1024 * 1024) {
            throw const OdsSheetFormatException('ODS cell text limit');
          }
          write(' ' * count);
        } else if (_is(node, 'tab', _textNs)) {
          write('\t');
        } else if (_is(node, 'line-break', _textNs)) {
          write('\n');
        } else {
          for (final child in node.children) {
            inline(child);
          }
        }
      }
    }

    for (var i = 0; i < paragraphs.length; i++) {
      if (i > 0) write('\n');
      inline(paragraphs[i]);
    }
    return buffer.toString();
  }

  static int _repeat(
    XmlElement element,
    String name, {
    String namespace = _table,
  }) {
    final raw = _attribute(element, name, namespace);
    if (raw == null) return 1;
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 1 << 30) {
      throw OdsSheetFormatException('Invalid ODS $name');
    }
    return value;
  }

  static bool _is(XmlElement element, String name, String namespace) =>
      element.localName == name && element.namespaceUri == namespace;

  static String? _attribute(
    XmlElement element,
    String name,
    String namespace,
  ) => element.getAttribute(name, namespaceUri: namespace);

  static List<XmlElement> _styleChain(
    Map<String, XmlElement> styles,
    String family,
    String? name,
  ) {
    final result = <XmlElement>[];
    final seen = <String>{};
    while (name != null) {
      if (!seen.add(name) || seen.length > 32) {
        throw const OdsSheetFormatException(
          'Cyclic or excessive ODS style inheritance',
        );
      }
      final style = styles['$family:$name'];
      if (style == null) break;
      result.add(style);
      name = _attribute(style, 'parent-style-name', _style);
    }
    return result;
  }

  static String? _styleAttribute(List<XmlElement> styles, String name) {
    for (final style in styles) {
      final value = _attribute(style, name, _style);
      if (value != null) return value;
    }
    return null;
  }

  static String? _property(
    List<XmlElement> styles,
    String childName,
    String name,
    String namespace,
  ) {
    for (final style in styles) {
      final properties = style.firstChild(childName, namespaceUri: _style);
      final value = properties?.getAttribute(name, namespaceUri: namespace);
      if (value != null) return value;
    }
    return null;
  }

  static Iterable<XmlElement> _members(
    XmlElement root,
    String name,
    Set<String> wrappers,
  ) sync* {
    for (final child in root.childElements) {
      if (child.namespaceUri != _table) continue;
      if (child.localName == name) {
        yield child;
      } else if (wrappers.contains(child.localName)) {
        yield* _members(child, name, wrappers);
      }
    }
  }

  static Iterable<XmlElement> _descendants(
    XmlElement root,
    String name,
    String namespace,
  ) sync* {
    for (final child in root.childElements) {
      if (_is(child, name, namespace)) yield child;
      yield* _descendants(child, name, namespace);
    }
  }

  static bool _isBold(String? weight) {
    if (weight == null) return false;
    if (weight.toLowerCase() == 'bold') return true;
    final numeric = int.tryParse(weight);
    return numeric != null && numeric >= 600;
  }

  static String? _hex(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty ||
        value.toLowerCase() == 'none' ||
        value.toLowerCase() == 'transparent') {
      return null;
    }
    final hex = value.startsWith('#') ? value.substring(1) : value;
    return RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex) ? hex.toUpperCase() : null;
  }

  static String? _family(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final first = value.split(',').first.trim();
    return first.replaceAll(RegExp(r'''^["']|["']$'''), '');
  }

  static SmlHAlign _align(String? raw) => switch (raw) {
    'center' => SmlHAlign.center,
    'right' || 'end' => SmlHAlign.right,
    'left' || 'start' => SmlHAlign.left,
    _ => SmlHAlign.general,
  };

  static double? _lengthToPoints(String? raw) {
    final match = RegExp(
      r'^\s*([0-9]+(?:\.[0-9]+)?)\s*(cm|mm|in|pt|pc|px)?\s*$',
      caseSensitive: false,
    ).firstMatch(raw ?? '');
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null) return null;
    return switch ((match.group(2) ?? 'pt').toLowerCase()) {
      'cm' => value * 72 / 2.54,
      'mm' => value * 72 / 25.4,
      'in' => value * 72,
      'pc' => value * 12,
      'px' => value * 72 / 96,
      _ => value,
    };
  }
}

/// Bounds are shared across sheets, so short repeated markup cannot expand to
/// hundreds of millions of cells or unbounded merge/dimension bookkeeping.
class _OdsBudget {
  int _cells = 0;
  int _comments = 0;
  int _dimensions = 0;
  int _merges = 0;
  int _xmlBytes = 0;
  int _xmlEvents = 0;
  int _cellText = 0;
  int _styleWork = 0;
  int _mergeCoverageWork = 0;

  void comments(int count) {
    if (count > 10000 - _comments) {
      throw const OdsSheetFormatException('ODS comment limit (10000)');
    }
    _comments += count;
  }

  void cells(int count) {
    if (count > 200000 - _cells) {
      throw const OdsSheetFormatException(
        'ODS materialized cell limit (200000)',
      );
    }
    _cells += count;
  }

  void dimensions(int count) {
    if (count > 200000 - _dimensions) {
      throw const OdsSheetFormatException('ODS dimension limit (200000)');
    }
    _dimensions += count;
  }

  void cellText(int count) {
    if (count > 8 * 1024 * 1024 - _cellText) {
      throw const OdsSheetFormatException(
        'ODS expanded cell text limit (8 MiB)',
      );
    }
    _cellText += count;
  }

  void styleWork(int count) {
    if (count > 4000000 - _styleWork) {
      throw const OdsSheetFormatException('ODS style work limit');
    }
    _styleWork += count;
  }

  void mergeCoverage(int count) {
    if (count > 4000000 - _mergeCoverageWork) {
      throw const OdsSheetFormatException('ODS merge coverage work limit');
    }
    _mergeCoverageWork += count;
  }

  void merge() {
    if (++_merges > 1000) {
      throw const OdsSheetFormatException('ODS merge limit (1000)');
    }
  }

  void xml(int count) {
    if (count > 64 * 1024 * 1024 - _xmlBytes) {
      throw const OdsSheetFormatException('ODS XML byte limit (64 MiB)');
    }
    _xmlBytes += count;
  }

  void xmlEvent() {
    if (++_xmlEvents > 500000) {
      throw const OdsSheetFormatException('ODS XML event limit (500000)');
    }
  }
}
