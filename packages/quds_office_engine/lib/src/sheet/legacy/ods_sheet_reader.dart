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

  /// Reads the package. Throws [OdsSheetFormatException] for malformed input.
  static SmlWorkbook readBytes(Uint8List bytes) {
    final ZipReader zip;
    try {
      zip = ZipReader.fromBytes(bytes, maxEntries: 10000);
    } on Object catch (error) {
      throw OdsSheetFormatException('Not an ODF package: $error');
    }
    if (!zip.contains('content.xml')) {
      throw const OdsSheetFormatException('Missing content.xml');
    }
    final Uint8List content;
    try {
      content = zip.read('content.xml', maxBytes: 64 * 1024 * 1024);
    } on Object catch (error) {
      throw OdsSheetFormatException('Cannot read content.xml: $error');
    }
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(content, allowMalformed: true));
    } on Object catch (error) {
      throw OdsSheetFormatException('Malformed content.xml: $error');
    }
    final root = document.root;
    if (root == null) {
      throw const OdsSheetFormatException('Empty content.xml');
    }

    final styles = <String, XmlElement>{};
    for (final collection in <String>['automatic-styles', 'styles']) {
      for (final element in _elements(root, collection)) {
        for (final style in element.childElements) {
          final name = style.getAttribute('name');
          if (name != null && style.localName == 'style') styles[name] = style;
        }
      }
    }
    final numberStyles = <String, XmlElement>{};
    for (final collection in <String>['automatic-styles', 'styles']) {
      for (final element in _elements(root, collection)) {
        for (final style in element.childElements) {
          final name = style.getAttribute('name');
          if (name != null &&
              (style.localName == 'number-style' ||
                  style.localName == 'currency-style' ||
                  style.localName == 'percentage-style' ||
                  style.localName == 'date-style' ||
                  style.localName == 'time-style')) {
            numberStyles[name] = style;
          }
        }
      }
    }

    final book = SmlWorkbook(sheets: <SmlWorksheet>[], styles: SmlStyleSheet());
    final engineStyles = book.styles!;
    final tables = _elements(root, 'table').toList();
    if (tables.isEmpty) {
      throw const OdsSheetFormatException('Workbook has no tables');
    }
    var sheetId = 0;
    for (final table in tables) {
      sheetId++;
      final sheet = SmlWorksheet(
        name: table.getAttribute('name')?.trim().isNotEmpty == true
            ? table.getAttribute('name')!.trim()
            : 'Sheet$sheetId',
        sheetId: sheetId,
      );
      _readColumns(table, sheet, styles);
      var rowIndex = 0;
      final rows = table.childElements
          .where((element) => element.localName == 'table-row')
          .toList();
      for (var rowNumber = 0; rowNumber < rows.length; rowNumber++) {
        final row = rows[rowNumber];
        final rowRepeat = _repeat(row, 'number-rows-repeated', _maxRows);
        final rowStyle = styles[row.getAttribute('style-name')];
        final rowHeight = _lengthToPoints(
          _property(rowStyle, 'table-row-properties', 'row-height'),
        );

        final parsed = <({int column, int span, SmlCell cell})>[];
        var column = 0;
        var hasContent = false;
        for (final element in row.childElements) {
          if (element.localName != 'table-cell' &&
              element.localName != 'covered-table-cell') {
            continue;
          }
          // Covered cells are placeholders for columns the spanning anchor
          // has already advanced past; advancing again shifts every later
          // cell to the right.
          if (element.localName == 'covered-table-cell') continue;
          final span = _repeat(element, 'number-columns-spanned', _maxColumns);
          final repeat = _repeat(
            element,
            'number-columns-repeated',
            _maxColumns,
          );
          for (var i = 0; i < repeat && column < _maxColumns; i++) {
            final cell = _createCell(
              sheet,
              SmlCellRef(column, rowIndex),
              element,
              engineStyles,
              styles,
              numberStyles,
            );
            if (cell != null) {
              hasContent = true;
              parsed.add((column: column, span: span, cell: cell));
            }
            column += span;
          }
        }
        if (rowHeight != null && rowHeight > 0) {
          for (var r = 0; r < rowRepeat && rowIndex + r < _maxRows; r++) {
            sheet.rowHeights[rowIndex + r] = SmlWorksheet.rowHeightFromExcel(
              rowHeight,
            );
          }
        }
        // Internal repeated empty rows are spacing and must keep later rows
        // at their authored positions. Only trailing padding is discarded.
        if (!hasContent && rowRepeat > 1) {
          if (rowNumber == rows.length - 1) break;
          rowIndex += rowRepeat.clamp(1, _maxRows);
          if (rowIndex >= _maxRows) break;
          continue;
        }
        for (final entry in parsed) {
          if (entry.span > 1) {
            sheet.merges.add(
              SmlMerge(
                c0: entry.column,
                r0: rowIndex,
                c1: entry.column + entry.span - 1,
                r1: rowIndex,
              ),
            );
          }
        }
        for (var r = 1; r < rowRepeat && rowIndex + r < _maxRows; r++) {
          for (final entry in parsed) {
            final source = entry.cell;
            final target = sheet.cell(SmlCellRef(entry.column, rowIndex + r));
            target
              ..type = source.type
              ..value = source.value
              ..formula = source.formula
              ..styleIndex = source.styleIndex
              ..hasExplicitStyleIndex = source.hasExplicitStyleIndex
              ..horizontalAlign = source.horizontalAlign
              ..wrapText = source.wrapText
              ..fillRgb = source.fillRgb
              ..fontRgb = source.fontRgb
              ..fontBold = source.fontBold
              ..fontSize = source.fontSize
              ..fontFamily = source.fontFamily;
          }
        }
        rowIndex += rowRepeat.clamp(1, _maxRows);
        if (rowIndex >= _maxRows) break;
      }
      book.sheets.add(sheet);
    }
    return book;
  }

  static void _readColumns(
    XmlElement table,
    SmlWorksheet sheet,
    Map<String, XmlElement> styles,
  ) {
    var column = 0;
    for (final element in table.childElements.where(
      (child) => child.localName == 'table-column',
    )) {
      final repeat = _repeat(element, 'number-columns-repeated', _maxColumns);
      final style = styles[element.getAttribute('style-name')];
      final width = _lengthToPoints(
        _property(style, 'table-column-properties', 'column-width'),
      );
      if (width != null && width > 0) {
        final px = width * 96 / 72;
        for (var i = 0; i < repeat && column < _maxColumns; i++) {
          sheet.setColumnWidth(column, px);
          column++;
        }
      } else {
        column += repeat;
      }
    }
  }

  static SmlCell? _createCell(
    SmlWorksheet sheet,
    SmlCellRef ref,
    XmlElement element,
    SmlStyleSheet engineStyles,
    Map<String, XmlElement> styles,
    Map<String, XmlElement> numberStyles,
  ) {
    Object? value;
    switch (element.getAttribute('value-type')) {
      case 'float':
      case 'currency':
      case 'percentage':
        value = double.tryParse(element.getAttribute('value') ?? '');
      case 'date':
        final parsed = DateTime.tryParse(
          element.getAttribute('date-value') ?? '',
        );
        value = parsed == null ? null : _excelSerial(parsed);
      case 'time':
        value = _odfDurationDays(element.getAttribute('time-value'));
      case 'boolean':
        value = element.getAttribute('boolean-value') == 'true';
      case 'string':
        value = element.getAttribute('string-value') ?? _text(element);
      default:
        value = _text(element);
    }
    if (value is String && value.isEmpty) value = null;
    final formula = _translateFormula(element.getAttribute('formula'));

    final style = styles[element.getAttribute('style-name')];
    final text = style == null ? null : _child(style, 'text-properties');
    final cellProperties = style == null
        ? null
        : _child(style, 'table-cell-properties');
    final paragraph = style == null
        ? null
        : _child(style, 'paragraph-properties');

    final bold = _isBold(text?.getAttribute('font-weight'));
    final fontSize = _lengthToPoints(text?.getAttribute('font-size'));
    final color = _hex(text?.getAttribute('color'));
    final fill = _hex(cellProperties?.getAttribute('background-color'));
    final align = _align(paragraph?.getAttribute('text-align'));
    final wrap = paragraph?.getAttribute('wrap-option') == 'wrap';
    final family = _family(text?.getAttribute('font-family'));
    final numFmt = _numberFormat(
      style?.getAttribute('data-style-name'),
      numberStyles,
      element.getAttribute('value-type'),
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

    final cell = sheet.cell(ref);
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
    var formula = raw;
    final equals = formula.indexOf('=');
    if (equals >= 0) formula = formula.substring(equals + 1);
    formula = formula.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]'),
      (match) => match.group(1)!.split(':').map(_odfReference).join(':'),
    );
    formula = formula
        .replaceAll(';', ',')
        .replaceAll(RegExp(r'\b(?:COM\.MICROSOFT|ORG\.OPENOFFICE)\.'), '');
    if (formula.trim().isEmpty) return null;
    return formula;
  }

  static String _odfReference(String raw) {
    var reference = raw.trim();
    if (reference.startsWith('.')) reference = reference.substring(1);
    final dot = reference.lastIndexOf('.');
    if (dot <= 0) return reference;
    var sheet = reference.substring(0, dot).trim();
    final cell = reference.substring(dot + 1);
    if (sheet.startsWith("'") && sheet.endsWith("'")) {
      sheet = sheet.substring(1, sheet.length - 1);
    }
    if (sheet.isEmpty) return cell;
    return sheet.contains(' ') ? "'$sheet'!$cell" : '$sheet!$cell';
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
        ).any((element) => element.getAttribute('grouping') == 'true');
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
    final number = _descendants(style, 'number').firstOrNull;
    final value = int.tryParse(number?.getAttribute('decimal-places') ?? '');
    return (value ?? 0).clamp(0, 10);
  }

  static double _excelSerial(DateTime value) {
    final epoch = DateTime.utc(1899, 12, 30);
    return value.toUtc().difference(epoch).inMilliseconds / 86400000;
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
    final paragraphs = _descendants(element, 'p').toList();
    if (paragraphs.isEmpty) return element.text.trim();
    final buffer = StringBuffer();
    for (final paragraph in paragraphs) {
      final text = paragraph.text.trim();
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  static int _repeat(XmlElement element, String name, int max) {
    final value = int.tryParse(element.getAttribute(name) ?? '') ?? 1;
    return value.clamp(1, max);
  }

  static XmlElement? _child(XmlElement element, String name) =>
      element.firstChild(name);

  static String? _property(
    XmlElement? style,
    String childName,
    String attribute,
  ) => style?.firstChild(childName)?.getAttribute(attribute);

  static Iterable<XmlElement> _elements(XmlElement root, String name) sync* {
    for (final child in root.childElements) {
      if (child.localName == name) yield child;
      yield* _elements(child, name);
    }
  }

  static Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
    for (final child in root.childElements) {
      if (child.localName == name) yield child;
      yield* _descendants(child, name);
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
