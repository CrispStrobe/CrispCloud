import 'dart:convert';
import 'dart:typed_data';

import '../../opc/zip/zip_writer.dart';
import '../../xml/xml_writer.dart';
import '../model/sml_workbook.dart';
import '../styles/sml_styles.dart';

/// Bounded ODS writer for the shared spreadsheet model.
///
/// This is an export path, not an in-place ODF editor. It writes supported
/// values, formulas, styles, merges, geometry, comments, hyperlinks and
/// worksheet state; unmodeled extension content is not invented.
abstract final class OdsSheetWriter {
  static const String _mime = 'application/vnd.oasis.opendocument.spreadsheet';

  /// Serializes [book] as a new ODS package.
  static Uint8List writeBytes(SmlWorkbook book) {
    final layout = _OdsLayout(book);
    final content = _contentXml(book, layout);
    final styles = _stylesXml(book, layout);
    final manifest = _manifestXml();
    final meta = _metaXml();

    final zip = ZipWriter();
    zip.addFile('mimetype', utf8.encode(_mime), store: true);
    zip.addFile('META-INF/manifest.xml', utf8.encode(manifest));
    zip.addFile('content.xml', utf8.encode(content));
    zip.addFile('styles.xml', utf8.encode(styles));
    zip.addFile('meta.xml', utf8.encode(meta));
    return zip.close();
  }

  static String _manifestXml() {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement(
      'manifest',
      prefix: 'manifest',
      namespaceUri: 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0',
    );
    w.writeAttribute('manifest:version', '1.3');
    void entry(String path, String type) {
      w.writeEmptyElement(
        'file-entry',
        prefix: 'manifest',
        attributes: {'manifest:full-path': path, 'manifest:media-type': type},
      );
    }

    entry('/', _mime);
    entry('content.xml', 'text/xml');
    entry('styles.xml', 'text/xml');
    entry('meta.xml', 'text/xml');
    w.writeEndElement();
    return w.toXml();
  }

  static String _metaXml() {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-meta', prefix: 'office');
    w.writeNamespace(
      'office',
      'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    );
    w.writeNamespace('meta', 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0');
    w.writeNamespace('dc', 'http://purl.org/dc/elements/1.1/');
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('meta', prefix: 'office');
    w.writeStartElement('generator', prefix: 'meta');
    w.writeText('Quds Office');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static String _stylesXml(SmlWorkbook book, _OdsLayout layout) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-styles', prefix: 'office');
    w.writeNamespace(
      'office',
      'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    );
    w.writeNamespace(
      'style',
      'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    );
    w.writeNamespace('text', 'urn:oasis:names:tc:opendocument:xmlns:text:1.0');
    w.writeNamespace(
      'table',
      'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    );
    w.writeNamespace(
      'fo',
      'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    );
    w.writeNamespace(
      'number',
      'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0',
    );
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('styles', prefix: 'office');
    w.writeStartElement('default-style', prefix: 'style');
    w.writeAttribute('style:family', 'table-cell');
    w.writeStartElement('text-properties', prefix: 'style');
    w.writeAttribute('fo:font-family', 'Calibri');
    w.writeAttribute('fo:font-size', '11pt');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEmptyElement(
      'style',
      prefix: 'style',
      attributes: {'style:name': 'Default', 'style:family': 'table-cell'},
    );
    w.writeStartElement('automatic-styles', prefix: 'office');
    layout.writeNumberStyles(w);
    layout.writeColumnStyles(w);
    layout.writeRowStyles(w);
    layout.writeCellStyles(w);
    w.writeEndElement();

    w.writeStartElement('master-styles', prefix: 'office');
    w.writeEmptyElement(
      'master-page',
      prefix: 'style',
      attributes: {'style:name': 'Standard', 'style:page-layout-name': 'pm1'},
    );
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static String _contentXml(SmlWorkbook book, _OdsLayout layout) {
    final w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('document-content', prefix: 'office');
    const namespaces = {
      'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
      'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
      'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
      'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
      'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
      'number': 'urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0',
      'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
      'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
      'xlink': 'http://www.w3.org/1999/xlink',
      'of': 'urn:oasis:names:tc:opendocument:xmlns:of:1.2',
      'dc': 'http://purl.org/dc/elements/1.1/',
      'calcext':
          'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0',
    };
    for (final entry in namespaces.entries) {
      w.writeNamespace(entry.key, entry.value);
    }
    w.writeAttribute('office:version', '1.3');
    w.writeStartElement('automatic-styles', prefix: 'office');
    layout.writeNumberStyles(w);
    layout.writeColumnStyles(w);
    layout.writeRowStyles(w);
    layout.writeCellStyles(w);
    w.writeEndElement();
    w.writeStartElement('body', prefix: 'office');
    w.writeStartElement('spreadsheet', prefix: 'office');
    for (var index = 0; index < book.sheets.length; index++) {
      _writeSheet(w, book, book.sheets[index], index, layout);
    }
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    return w.toXml();
  }

  static void _writeSheet(
    XmlWriter w,
    SmlWorkbook book,
    SmlWorksheet sheet,
    int index,
    _OdsLayout layout,
  ) {
    w.writeStartElement('table', prefix: 'table');
    w.writeAttribute('table:name', sheet.name);
    w.writeAttribute('table:style-name', layout.tableStyle[index]);
    final extent = sheet.usedExtent();
    final maxCol = extent.col;
    final maxRow = extent.row;
    for (var col = 0; col <= maxCol; col++) {
      w.writeStartElement('table-column', prefix: 'table');
      w.writeAttribute('table:default-cell-style-name', 'Default');
      if (layout.columnStyles[index].containsKey(col)) {
        w.writeAttribute('table:style-name', layout.columnStyles[index][col]!);
      }
      final properties = sheet.columnProperties[col];
      if (properties?['hidden'] == '1' || properties?['hidden'] == 'true') {
        w.writeAttribute('table:visibility', 'collapse');
      }
      w.writeEndElement();
    }
    for (var row = 0; row <= maxRow; row++) {
      w.writeStartElement('table-row', prefix: 'table');
      if (layout.rowStyles[index].containsKey(row)) {
        w.writeAttribute('table:style-name', layout.rowStyles[index][row]!);
      }
      if (sheet.hiddenRows.contains(row)) {
        w.writeAttribute('table:visibility', 'collapse');
      }
      for (var col = 0; col <= maxCol; col++) {
        final merge = sheet.mergeAt(col, row);
        if (merge != null && (merge.c0 != col || merge.r0 != row)) {
          w.writeEmptyElement('covered-table-cell', prefix: 'table');
          continue;
        }
        _writeCell(w, sheet, col, row, merge, layout);
      }
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeCell(
    XmlWriter w,
    SmlWorksheet sheet,
    int col,
    int row,
    SmlMerge? merge,
    _OdsLayout layout,
  ) {
    final cell = sheet.cellOrNull(SmlCellRef(col, row));
    w.writeStartElement('table-cell', prefix: 'table');
    final style = cell == null ? null : layout.cellStyle(sheet, cell);
    if (style != null) {
      w.writeAttribute('table:style-name', style);
    }
    if (merge != null) {
      final columns = merge.c1 - merge.c0 + 1;
      final rows = merge.r1 - merge.r0 + 1;
      if (columns > 1) {
        w.writeAttribute('table:number-columns-spanned', '$columns');
      }
      if (rows > 1) {
        w.writeAttribute('table:number-rows-spanned', '$rows');
      }
    }
    final value = cell?.value;
    final formula = cell?.formula;
    if (formula != null && formula.isNotEmpty) {
      w.writeAttribute('table:formula', _toOpenFormula(formula));
    }
    if (value is bool) {
      w.writeAttribute('office:value-type', 'boolean');
      w.writeAttribute('office:boolean-value', '$value');
    } else if (value is num) {
      w.writeAttribute('office:value-type', 'float');
      w.writeAttribute('office:value', '$value');
      if (formula != null) {
        w.writeAttribute('calcext:value-type', 'float');
      }
    } else if (value is String) {
      w.writeAttribute('office:value-type', 'string');
    }
    if (cell?.hyperlink case final link? when link.isNotEmpty) {
      w.writeStartElement('p', prefix: 'text');
      w.writeStartElement('a', prefix: 'text');
      w.writeAttribute('xlink:href', link);
      w.writeText(value?.toString() ?? '');
      w.writeEndElement();
      w.writeEndElement();
    } else if (value is String && value.isNotEmpty) {
      w.writeStartElement('p', prefix: 'text');
      w.writeText(value);
      w.writeEndElement();
    } else if (formula != null || value is num || value is bool) {
      w.writeStartElement('p', prefix: 'text');
      w.writeText(value?.toString() ?? '');
      w.writeEndElement();
    }
    final comments = sheet.comments.where(
      (comment) => comment.ref.col == col && comment.ref.row == row,
    );
    for (final comment in comments) {
      w.writeStartElement('annotation', prefix: 'office');
      w.writeStartElement('creator', prefix: 'dc');
      w.writeText(comment.author);
      w.writeEndElement();
      w.writeStartElement('p', prefix: 'text');
      w.writeText(comment.text);
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static String _toOpenFormula(String formula) {
    var input = formula.trim();
    if (input.startsWith('of:')) return input;
    if (input.startsWith('=')) input = input.substring(1);
    final out = StringBuffer('of:=');
    var i = 0;
    while (i < input.length) {
      final char = input[i];
      if (char == '"') {
        final end = _stringEnd(input, i);
        out.write(input.substring(i, end));
        i = end;
        continue;
      }
      if (char == ',') {
        out.write(';');
        i++;
        continue;
      }
      final reference = _referenceAt(input, i);
      if (reference != null) {
        out.write(reference.$2);
        i = reference.$1;
        continue;
      }
      out.write(char);
      i++;
    }
    return out.toString();
  }

  static (int, String)? _referenceAt(String input, int index) {
    final match = RegExp(
      r"^(?:(?:'([^']|'')+'|[A-Za-z_][\w.]*)!)?"
      r"(\$?[A-Za-z]{1,3}\$?\d+)"
      r"(?::(\$?[A-Za-z]{1,3}\$?\d+))?",
    ).firstMatch(input.substring(index));
    if (match == null) return null;
    final whole = match.group(0)!;
    if (index > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(input[index - 1])) {
      return null;
    }
    final prefix = match.group(0)!.split('!');
    String? sheet;
    var cellPart = whole;
    if (prefix.length > 1) {
      sheet = prefix.first;
      cellPart = prefix.skip(1).join('!');
      if (sheet.startsWith("'") && sheet.endsWith("'")) {
        sheet = sheet.substring(1, sheet.length - 1).replaceAll("''", "'");
      }
      sheet = "'${sheet.replaceAll("'", "''")}'";
    }
    final pieces = cellPart.split(':');
    String ref(String cell) => sheet == null ? '.$cell' : '\$$sheet.$cell';
    final encoded = pieces.length == 2
        ? '[${ref(pieces[0])}:.${pieces[1]}]'
        : '[${ref(pieces[0])}]';
    final end = index + whole.length;
    if (end < input.length && RegExp(r'[A-Za-z0-9_]').hasMatch(input[end])) {
      return null;
    }
    return (end, encoded);
  }

  static int _stringEnd(String value, int start) {
    var index = start + 1;
    while (index < value.length) {
      if (value[index] == '"') {
        if (index + 1 < value.length && value[index + 1] == '"') {
          index += 2;
          continue;
        }
        return index + 1;
      }
      index++;
    }
    return value.length;
  }
}

class _OdsLayout {
  _OdsLayout(this.book) {
    final cellStyleIds = <String, String>{};
    for (var sheetIndex = 0; sheetIndex < book.sheets.length; sheetIndex++) {
      final sheet = book.sheets[sheetIndex];
      final columnStyles = <int, String>{};
      final rowStyles = <int, String>{};
      for (var col = 0; col < SmlWorksheet.excelColumnCount; col++) {
        if (!sheet.columnWidths.containsKey(col) &&
            !sheet.columnProperties.containsKey(col)) {
          continue;
        }
        final name = 'co${columnStyles.length + 1}_$sheetIndex';
        final width = sheet.columnWidth(col);
        final widthIn = width * 72 / 96 / 72;
        columnStyles[col] = name;
        columnStyleBuffers.add(
          '<style:style style:name="$name" style:family="table-column">'
          '<style:table-column-properties style:column-width="${widthIn.toStringAsFixed(4)}in"/>'
          '</style:style>',
        );
      }
      for (var row = 0; row < SmlWorksheet.excelRowCount; row++) {
        if (!sheet.rowHeights.containsKey(row)) continue;
        final name = 'ro${rowStyles.length + 1}_$sheetIndex';
        final heightIn = sheet.rowHeightAt(row) * 72 / 96 / 72;
        rowStyles[row] = name;
        rowStyleBuffers.add(
          '<style:style style:name="$name" style:family="table-row">'
          '<style:table-row-properties style:row-height="${heightIn.toStringAsFixed(4)}in"/>'
          '</style:style>',
        );
      }
      this.columnStyles.add(columnStyles);
      this.rowStyles.add(rowStyles);
      tableStyle.add('ta$sheetIndex');
      tableBuffers.add(
        '<style:style style:name="ta$sheetIndex" style:family="table">'
        '<style:table-properties table:display="${sheet.hidden ? 'false' : 'true'}"'
        '${sheet.tabColorRgb == null ? '' : ' table:tab-color="#${sheet.tabColorRgb!.toLowerCase()}"'}/>'
        '</style:style>',
      );
      for (final cell in sheet.allCells) {
        if (cell.type == SmlCellType.string &&
            cell.value == null &&
            cell.formula == null &&
            cell.styleIndex == 0) {
          continue;
        }
        final key = [
          cell.fontBold,
          cell.fontSize,
          cell.fontFamily,
          cell.fontRgb,
          cell.fillRgb,
          cell.horizontalAlign.name,
          cell.wrapText ?? false,
        ].join('|');
        cellStyleIds.putIfAbsent(key, () {
          final name = 'ce${cellStyleIds.length + 1}';
          final buffer = StringBuffer(
            '<style:style style:name="$name" style:family="table-cell">',
          );
          buffer.write('<style:table-cell-properties');
          if (cell.fillRgb.isNotEmpty) {
            buffer.write(
              ' fo:background-color="#${cell.fillRgb.toLowerCase()}"',
            );
          }
          if (cell.wrapText == true) buffer.write(' fo:wrap-option="wrap"');
          buffer.write('/>');
          buffer.write(
            '<style:paragraph-properties fo:text-align="${switch (cell.horizontalAlign) {
              SmlHAlign.left => 'start',
              SmlHAlign.center => 'center',
              SmlHAlign.right => 'end',
              SmlHAlign.general => 'start',
            }}"/>',
          );
          buffer.write(
            '<style:text-properties fo:font-weight="${cell.fontBold ? 'bold' : 'normal'}" '
            'fo:font-size="${cell.fontSize}pt"',
          );
          if (cell.fontRgb.isNotEmpty) {
            buffer.write(' fo:color="#${cell.fontRgb.toLowerCase()}"');
          }
          if (cell.fontFamily.isNotEmpty) {
            buffer.write(' fo:font-family="${cell.fontFamily}"');
          }
          buffer.write('/></style:style>');
          cellStyleBuffers.add(buffer.toString());
          return name;
        });
        cellStyles[cellKey(sheetIndex, cell)] = cellStyleIds[key]!;
      }
    }
  }

  final SmlWorkbook book;
  final List<Map<int, String>> columnStyles = [];
  final List<Map<int, String>> rowStyles = [];
  final List<String> tableStyle = [];
  final List<String> tableBuffers = [];
  final List<String> columnStyleBuffers = [];
  final List<String> rowStyleBuffers = [];
  final List<String> cellStyleBuffers = [];

  final Map<String, String> cellStyles = {};

  String cellKey(int sheet, SmlCell cell) => '$sheet:${cell.ref.a1}';

  String? cellStyle(SmlWorksheet sheet, SmlCell cell) =>
      cellStyles[cellKey(book.sheets.indexOf(sheet), cell)];

  void writeNumberStyles(XmlWriter w) {}

  void writeColumnStyles(XmlWriter w) {
    for (final buffer in columnStyleBuffers) {
      w.writeRaw(buffer);
    }
  }

  void writeRowStyles(XmlWriter w) {
    for (final buffer in rowStyleBuffers) {
      w.writeRaw(buffer);
    }
  }

  void writeCellStyles(XmlWriter w) {
    for (final buffer in tableBuffers) {
      w.writeRaw(buffer);
    }
    for (final buffer in cellStyleBuffers) {
      w.writeRaw(buffer);
    }
  }
}
