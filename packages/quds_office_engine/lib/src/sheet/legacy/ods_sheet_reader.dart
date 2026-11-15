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
import '../model/sml_workbook.dart';
import '../styles/sml_styles.dart';

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
  static const int _maxRows = 100000;
  static const int _maxColumns = 4096;
  static const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
  static const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
  static const _textNs = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
  static const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
  static const _number = 'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0';
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
      _readColumns(table, sheet, styles, budget);
      var rowIndex = 0;
      for (final row in _members(table, 'table-row', const {
        'table-row-group',
        'table-rows',
        'table-header-rows',
      })) {
        final rowRepeat = _repeat(row, 'number-rows-repeated');
        final rowStyle = _styleChain(
          styles,
          'table-row',
          _attribute(row, 'style-name', _table),
        );
        final rowHeight = _lengthToPoints(
          _property(rowStyle, 'table-row-properties', 'row-height', _style),
        );
        final rowMerges = <SmlMerge>[];
        final entries =
            <
              ({
                int column,
                int repeat,
                int colSpan,
                int rowSpan,
                SmlCell? cell,
              })
            >[];
        var column = 0;
        for (final element in row.childElements) {
          if (element.namespaceUri != _table ||
              (element.localName != 'table-cell' &&
                  element.localName != 'covered-table-cell')) {
            continue;
          }
          final repeat = _repeat(element, 'number-columns-repeated');
          if (element.localName == 'covered-table-cell') {
            // ODF emits a covered cell for each coordinate after the anchor.
            // The anchor itself also occupies exactly one serialized cell.
            if (_attribute(element, 'value-type', _office) != null ||
                _attribute(element, 'formula', _table) != null ||
                _text(element).isNotEmpty) {
              throw const OdsSheetFormatException('Covered cell contains data');
            }
            column += repeat;
            continue;
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
          final cell = _createCell(
            element,
            book.styles!,
            styles,
            numberStyles,
            budget,
          );
          if (cell != null || colSpan > 1 || rowSpan > 1) {
            if (column + repeat + colSpan - 1 > _maxColumns ||
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
            if (sheet.merges.isNotEmpty || rowMerges.isNotEmpty) {
              budget.mergeCoverage(sheet.merges.length + rowMerges.length);
              final occupied = SmlMerge(
                c0: column,
                r0: rowIndex,
                c1: column + repeat - 1,
                r1: rowIndex + rowRepeat - 1,
              );
              if (sheet.merges.any((merge) => merge.overlaps(occupied)) ||
                  rowMerges.any((merge) => merge.overlaps(occupied))) {
                throw const OdsSheetFormatException(
                  'Stored cell inside a merge requires a covered-cell token',
                );
              }
            }
            if (colSpan > 1 || rowSpan > 1) {
              rowMerges.add(
                SmlMerge(
                  c0: column,
                  r0: rowIndex,
                  c1: column + colSpan - 1,
                  r1: rowIndex + rowRepeat + rowSpan - 2,
                ),
              );
            }
            if (cell != null) {
              final count = repeat * rowRepeat;
              budget.cells(count);
              final value = cell.value;
              budget.cellText(
                ((value is String ? utf8.encode(value).length : 0) +
                        (cell.formula == null
                            ? 0
                            : utf8.encode(cell.formula!).length)) *
                    count,
              );
            }
            entries.add((
              column: column,
              repeat: repeat,
              colSpan: colSpan,
              rowSpan: rowSpan,
              cell: cell,
            ));
          }
          column += repeat;
        }
        // Empty runs do not allocate cells, but must retain their exact row
        // count: data after an internal gap must never move or disappear.
        if (rowHeight != null &&
            rowHeight > 0 &&
            rowIndex + rowRepeat <= _maxRows) {
          budget.dimensions(rowRepeat);
          for (var r = 0; r < rowRepeat; r++) {
            sheet.rowHeights[rowIndex + r] = SmlWorksheet.rowHeightFromExcel(
              rowHeight,
            );
          }
        }
        if (entries.isNotEmpty) {
          for (var r = 0; r < rowRepeat; r++) {
            for (final entry in entries) {
              for (var c = 0; c < entry.repeat; c++) {
                final ref = SmlCellRef(entry.column + c, rowIndex + r);
                if (entry.cell case final source?) {
                  _copyCell(source, sheet.cell(ref));
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
      return XmlDocument.parse(source).root!;
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

  static void _readColumns(
    XmlElement table,
    SmlWorksheet sheet,
    Map<String, XmlElement> styles,
    _OdsBudget budget,
  ) {
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
      if (width != null && width > 0) {
        // Column definitions commonly include a full-sheet default-width tail.
        // It has no cells to preserve outside the admitted grid.
        final end = (column + repeat).clamp(0, _maxColumns);
        final count = (end - column).clamp(0, _maxColumns);
        budget.dimensions(count);
        for (var i = 0; i < count; i++) {
          sheet.setColumnWidth(column + i, width * 96 / 72);
        }
      }
      column += repeat;
    }
  }

  static SmlCell? _createCell(
    XmlElement element,
    SmlStyleSheet engineStyles,
    Map<String, XmlElement> styles,
    Map<String, XmlElement> numberStyles,
    _OdsBudget budget,
  ) {
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
    final styleName = _attribute(element, 'style-name', _table);
    // The named Default style on empty spreadsheet padding is not cell data.
    if (value == null &&
        formula == null &&
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
    final styled =
        bold ||
        fontSize != null ||
        color != null ||
        fill != null ||
        align != SmlHAlign.general ||
        wrap ||
        family != null ||
        numFmt != null;

    if (value == null && formula == null && !styled) return null;

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
          (i == 0 || !_isFormulaWordCharacter(formula.codeUnitAt(i - 1))) &&
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

  // Match the ASCII word-boundary rule used by the original prefix regex;
  // embedded namespace text belongs to an unknown/custom identifier.
  static bool _isFormulaWordCharacter(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      codeUnit == 0x5f;

  static String _odfReference(String raw) {
    var reference = raw.trim();
    if (reference.startsWith('.')) reference = reference.substring(1);
    final dot = reference.lastIndexOf('.');
    if (dot <= 0) return reference;
    var sheet = reference.substring(0, dot).trim();
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
        return '#,##0.00';
      case 'date-style':
        return 'DD.MM.YYYY';
      case 'time-style':
        return 'h:mm:ss';
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
    final paragraphs = _descendants(element, 'p', _textNs).toList();
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
  int _dimensions = 0;
  int _merges = 0;
  int _xmlBytes = 0;
  int _xmlEvents = 0;
  int _cellText = 0;
  int _styleWork = 0;
  int _mergeCoverageWork = 0;

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
