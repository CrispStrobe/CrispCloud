import 'dart:convert';
import 'dart:typed_data';

import '../../odf/odf_text.dart';
import '../../opc/zip/zip_writer.dart';
import '../../xml/xml_writer.dart';
import '../model/sml_analysis.dart';
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
    final manifest = _manifestXml(layout.media.keys.toList());
    final meta = _metaXml();

    final zip = ZipWriter();
    zip.addFile('mimetype', utf8.encode(_mime), store: true);
    zip.addFile('META-INF/manifest.xml', utf8.encode(manifest));
    zip.addFile('content.xml', utf8.encode(content));
    zip.addFile('styles.xml', utf8.encode(styles));
    zip.addFile('meta.xml', utf8.encode(meta));
    for (final entry in layout.media.entries) {
      zip.addFile(entry.key, entry.value);
    }
    return zip.close();
  }

  static String _manifestXml(List<String> media) {
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
    for (final path in media) {
      entry(path, _mediaType(path));
    }
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
    w.writeEmptyElement(
      'style',
      prefix: 'style',
      attributes: {'style:name': 'Default', 'style:family': 'table-cell'},
    );
    layout.writeConditionalStyles(w);
    w.writeEndElement();
    w.writeStartElement('automatic-styles', prefix: 'office');
    layout.writeNumberStyles(w);
    layout.writeColumnStyles(w);
    layout.writeRowStyles(w);
    layout.writeCellStyles(w);
    layout.writePageLayouts(w);
    w.writeEndElement();

    w.writeStartElement('master-styles', prefix: 'office');
    layout.writeMasterPages(w);
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
    final allValidations = [
      for (final definitions in layout.validationXml) ...definitions,
    ];
    if (allValidations.isNotEmpty) {
      w.writeStartElement('content-validations', prefix: 'table');
      for (final definition in allValidations) {
        w.writeRaw(definition);
      }
      w.writeEndElement();
    }
    for (var index = 0; index < book.sheets.length; index++) {
      _writeSheet(w, book, book.sheets[index], index, layout);
    }
    final globals = <String>[];
    for (final name in book.namedRanges) {
      if (name.localSheetId == null) {
        globals.add(
          '<table:named-range table:name="${_escapeAttr(name.name)}" '
          'table:cell-range-address="${_rangeAddress(name.sheetName, name.range)}" '
          'table:base-cell-address="${_baseAddress(name.sheetName)}"/>',
        );
      }
    }
    for (final name in book.formulaNames) {
      if (name.localSheetId == null) {
        globals.add(
          '<table:named-expression table:name="${_escapeAttr(name.name)}" '
          'table:expression="${_escapeAttr(_dropOf(name.formula))}"/>',
        );
      }
    }
    if (globals.isNotEmpty) {
      w.writeStartElement('named-expressions', prefix: 'table');
      for (final name in globals) {
        w.writeRaw(name);
      }
      w.writeEndElement();
    }
    final filters = book.sheets.where((sheet) => sheet.autoFilter != null);
    if (filters.isNotEmpty) {
      w.writeStartElement('database-ranges', prefix: 'table');
      for (final sheet in filters) {
        final filter = sheet.autoFilter!;
        final range = filter.range;
        final conditions = <({int field, String value})>[];
        for (final entry in filter.hiddenValues.entries) {
          if (entry.value.isEmpty) continue;
          final visible = <String>{
            for (var row = range.minRow + 1; row <= range.maxRow; row++)
              if (sheet
                      .cellOrNull(SmlCellRef(range.minCol + entry.key, row))
                      ?.asString
                  case final text? when text.isNotEmpty)
                text,
          }..removeAll(entry.value);
          for (final value in visible) {
            conditions.add((field: entry.key, value: value));
          }
        }
        w.writeStartElement('database-range', prefix: 'table');
        w.writeAttribute(
          'table:target-range-address',
          '${_plainSheet(sheet.name)}.${range.start.a1}:'
              '${_plainSheet(sheet.name)}.${range.end.a1}',
        );
        w.writeAttribute('table:display-filter-buttons', 'true');
        if (conditions.isNotEmpty) {
          w.writeStartElement('filter', prefix: 'table');
          for (final condition in conditions) {
            w.writeEmptyElement(
              'filter-condition',
              prefix: 'table',
              attributes: {
                'table:field-number': '${condition.field}',
                'table:operator': '=',
                'table:value': condition.value,
              },
            );
          }
          w.writeEndElement();
        }
        w.writeEndElement();
      }
      w.writeEndElement();
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
    if (sheet.printArea case final area?) {
      w.writeAttribute(
        'table:print-ranges',
        '${_plainSheet(sheet.name)}.${area.start.a1}:'
            '${_plainSheet(sheet.name)}.${area.end.a1}',
      );
    }
    final extent = sheet.usedExtent();
    var maxCol = extent.col;
    var maxRow = extent.row;
    void includeColumn(int col) {
      if (col > maxCol) maxCol = col;
    }

    void includeRow(int row) {
      if (row > maxRow) maxRow = row;
    }

    for (final col in sheet.columnWidths.keys) {
      includeColumn(col);
    }
    for (final col in sheet.columnProperties.keys) {
      includeColumn(col);
    }
    for (final row in sheet.rows.keys) {
      includeRow(row);
    }
    for (final row in sheet.rowHeights.keys) {
      includeRow(row);
    }
    for (final row in sheet.hiddenRows) {
      includeRow(row);
    }
    for (final row in sheet.rowOutlineLevels.keys) {
      includeRow(row);
    }
    for (final validation in sheet.validations) {
      final count =
          (validation.range.maxRow - validation.range.minRow + 1) *
          (validation.range.maxCol - validation.range.minCol + 1);
      if (count <= 100000) {
        includeColumn(validation.range.maxCol);
        includeRow(validation.range.maxRow);
      }
    }
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
    var openGroups = 0;
    for (var row = 0; row <= maxRow; row++) {
      final level = sheet.rowOutlineLevels[row] ?? 0;
      while (openGroups > level) {
        w.writeEndElement();
        openGroups--;
      }
      while (openGroups < level) {
        w.writeStartElement('table-row-group', prefix: 'table');
        openGroups++;
      }
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
    while (openGroups > 0) {
      w.writeEndElement();
      openGroups--;
    }
    final conditional = StringBuffer();
    for (final rule in sheet.conditionalFormats) {
      if (rule.kind == SmlConditionalKind.colorScale) {
        final stops = rule.colorScaleStops;
        if (stops.length < 2) continue;
        final entries = StringBuffer();
        for (final stop in stops) {
          entries.write(
            '<calcext:color-scale-entry '
            'calcext:value="${stop.value}" '
            'calcext:type="${_escapeAttr(stop.type)}" '
            'calcext:color="#${stop.colorRgb.toLowerCase()}"/>',
          );
        }
        conditional.write(
          '<calcext:conditional-format calcext:target-range-address="'
          '${_plainSheet(sheet.name)}.${rule.range.start.a1}:'
          '${_plainSheet(sheet.name)}.${rule.range.end.a1}">'
          '<calcext:color-scale>$entries</calcext:color-scale>'
          '</calcext:conditional-format>',
        );
        continue;
      }
      final style = layout.conditionalStyle(rule);
      conditional.write(
        '<calcext:conditional-format calcext:target-range-address="'
        '${_plainSheet(sheet.name)}.${rule.range.start.a1}:'
        '${_plainSheet(sheet.name)}.${rule.range.end.a1}">'
        '<calcext:condition calcext:apply-style-name="$style" '
        'calcext:base-cell-address="${_plainSheet(sheet.name)}.'
        '${rule.range.start.a1}" calcext:value="${_condition(rule)}"/>'
        '</calcext:conditional-format>',
      );
    }
    if (conditional.isNotEmpty) {
      w.writeRaw(
        '<calcext:conditional-formats>${conditional.toString()}'
        '</calcext:conditional-formats>',
      );
    }
    final localNames = <String>[];
    if (sheet.printTitleRows != null || sheet.printTitleCols != null) {
      localNames.add(
        '<table:named-expression table:name="Excel_BuiltIn_Print_Titles" '
        'table:expression="${_printTitles(sheet)}"/>',
      );
    }
    for (final name in book.namedRanges) {
      if (name.localSheetId == index) {
        localNames.add(
          '<table:named-range table:name="${_escapeAttr(name.name)}" '
          'table:cell-range-address="${_rangeAddress(name.sheetName, name.range)}" '
          'table:base-cell-address="${_baseAddress(name.sheetName)}"/>',
        );
      }
    }
    for (final name in book.formulaNames) {
      if (name.localSheetId == index) {
        localNames.add(
          '<table:named-expression table:name="${_escapeAttr(name.name)}" '
          'table:expression="${_escapeAttr(_dropOf(name.formula))}"/>',
        );
      }
    }
    if (localNames.isNotEmpty) {
      w.writeStartElement('named-expressions', prefix: 'table');
      for (final name in localNames) {
        w.writeRaw(name);
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
    final validation = layout.validationName(sheet, col, row);
    if (validation != null) {
      w.writeAttribute('table:content-validation-name', validation);
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
      writeOdfText(w, value?.toString() ?? '');
      w.writeEndElement();
      w.writeEndElement();
    } else if (value is String && value.isNotEmpty) {
      w.writeStartElement('p', prefix: 'text');
      writeOdfText(w, value);
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
    for (final image in layout.imagesAt(sheet, col, row)) {
      w.writeStartElement('frame', prefix: 'draw');
      w.writeAttribute('draw:name', image.name);
      w.writeAttribute(
        'svg:width',
        '${(image.width / 72).toStringAsFixed(4)}in',
      );
      w.writeAttribute(
        'svg:height',
        '${(image.height / 72).toStringAsFixed(4)}in',
      );
      w.writeEmptyElement(
        'image',
        prefix: 'draw',
        attributes: {'xlink:href': image.path},
      );
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  static void _writeHeaderText(XmlWriter w, String text) {
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      w.writeText(buffer.toString());
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      if (text[i] != '&' || i + 1 >= text.length) {
        buffer.write(text[i]);
        continue;
      }
      final code = text[i + 1].toUpperCase();
      final element = switch (code) {
        'P' => 'page-number',
        'N' => 'page-count',
        'D' => 'date',
        'T' => 'time',
        'A' => 'sheet-name',
        'F' => 'title',
        _ => null,
      };
      if (element == null) {
        if (code == '&') {
          buffer.write('&');
          i++;
        } else {
          buffer
            ..write('&')
            ..write(text[i + 1]);
          i++;
        }
        continue;
      }
      flush();
      w.writeEmptyElement(element, prefix: 'text');
      i++;
    }
    flush();
  }

  static String _condition(SmlConditionalRule rule) {
    String quote(String value) => '"${value.replaceAll('"', '""')}"';
    return switch (rule.kind) {
      SmlConditionalKind.expression => _escapeAttr(
        'formula-is(${_dropOf(_toOpenFormula(rule.formula))})',
      ),
      SmlConditionalKind.greaterThan => _escapeAttr('>${rule.formula}'),
      SmlConditionalKind.greaterOrEqual => _escapeAttr('>=${rule.formula}'),
      SmlConditionalKind.lessThan => _escapeAttr('<${rule.formula}'),
      SmlConditionalKind.lessOrEqual => _escapeAttr('<=${rule.formula}'),
      SmlConditionalKind.equal => _escapeAttr('=${rule.formula}'),
      SmlConditionalKind.notEqual => _escapeAttr('<>${rule.formula}'),
      SmlConditionalKind.between => _escapeAttr(
        'between(${rule.formula},${rule.formula2})',
      ),
      SmlConditionalKind.notBetween => _escapeAttr(
        'not-between(${rule.formula},${rule.formula2})',
      ),
      SmlConditionalKind.contains => _escapeAttr(
        'contains-text(${quote(rule.formula)})',
      ),
      SmlConditionalKind.beginsWith => _escapeAttr(
        'begins-with(${quote(rule.formula)})',
      ),
      SmlConditionalKind.endsWith => _escapeAttr(
        'ends-with(${quote(rule.formula)})',
      ),
      SmlConditionalKind.duplicate => 'duplicate',
      SmlConditionalKind.top => 'top-elements(${rule.rank})',
      SmlConditionalKind.bottom => 'bottom-elements(${rule.rank})',
      SmlConditionalKind.topPercent => 'top-percent(${rule.rank})',
      SmlConditionalKind.bottomPercent => 'bottom-percent(${rule.rank})',
      SmlConditionalKind.aboveAverage => 'above-average',
      SmlConditionalKind.belowAverage => 'below-average',
      SmlConditionalKind.colorScale => '',
    };
  }

  static String _imageExt(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    return 'bin';
  }

  static String _mediaType(String path) => path.endsWith('.png')
      ? 'image/png'
      : path.endsWith('.jpg')
      ? 'image/jpeg'
      : 'application/octet-stream';

  static String _plainSheet(String name) =>
      RegExp(r'[^A-Za-z0-9_]').hasMatch(name) ? _escapeSheet(name) : name;

  static String _escapeSheet(String name) => "'${name.replaceAll("'", "''")}'";

  static String _escapeAttr(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _rangeAddress(String sheet, SmlRange range) =>
      '\$${OdsSheetWriter._escapeSheet(sheet)}.${range.start.a1}:.${range.end.a1}';

  static String _baseAddress(String sheet) =>
      '\$${OdsSheetWriter._escapeSheet(sheet)}.\$A\$1';

  static String _dropOf(String formula) =>
      formula.startsWith('of:=') ? formula.substring(4) : formula;

  static String _printTitles(SmlWorksheet sheet) {
    final parts = <String>[];
    if (sheet.printTitleRows case final rows?) {
      parts.add(
        '[\$${_escapeSheet(sheet.name)}.\$${rows.minRow + 1}:'
        '.\$${rows.maxRow + 1}]',
      );
    }
    if (sheet.printTitleCols case final cols?) {
      final start = SmlCellRef(
        cols.minCol,
        0,
      ).a1.replaceAll(RegExp(r'\d+'), '');
      final end = SmlCellRef(cols.maxCol, 0).a1.replaceAll(RegExp(r'\d+'), '');
      parts.add('[\$${_escapeSheet(sheet.name)}.\$$start:.\$$end]');
    }
    return parts.join(';');
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
    final numberStyleIds = <String, String>{};
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
      final validationXml = <String>[];
      for (final rule in sheet.validations) {
        final name = 'val${++_validationCount}';
        validationDefinitions.add(name);
        validationXml.add(
          _validationXml(
            rule,
            name,
            '${OdsSheetWriter._plainSheet(sheet.name)}.${rule.range.start.a1}',
          ),
        );
        for (final ref in rule.range.cells) {
          validationNames['${sheet.name}:${ref.a1}'] = name;
        }
      }
      this.validationXml.add(validationXml);
      tableStyle.add('ta$sheetIndex');
      tableBuffers.add(
        '<style:style style:name="ta$sheetIndex" style:family="table" '
        'style:master-page-name="mp$sheetIndex">'
        '<style:table-properties table:display="${sheet.hidden ? 'false' : 'true'}"'
        '${sheet.tabColorRgb == null ? '' : ' table:tab-color="#${sheet.tabColorRgb!.toLowerCase()}"'}/>'
        '</style:style>',
      );
      for (final drawing in sheet.drawings) {
        final bytes = drawing.visual.imageBytes;
        if (bytes == null || bytes.isEmpty) continue;
        final ext = OdsSheetWriter._imageExt(bytes);
        final path = 'Pictures/image${media.length + 1}.$ext';
        media[path] = bytes;
        images['${sheet.name}:${drawing.col}:${drawing.row}'] =
            (images['${sheet.name}:${drawing.col}:${drawing.row}'] ??
                  <_WriterImage>[])
              ..add(
                _WriterImage(
                  path: path,
                  name: drawing.visual.title.isEmpty
                      ? 'Picture'
                      : drawing.visual.title,
                  width: drawing.visual.width,
                  height: drawing.visual.height,
                ),
              );
      }
      for (final cell in sheet.allCells) {
        if (cell.type == SmlCellType.string &&
            cell.value == null &&
            cell.formula == null &&
            cell.styleIndex == 0) {
          continue;
        }
        String? numberCode;
        final styleSheet = book.styles;
        if (styleSheet != null &&
            cell.styleIndex >= 0 &&
            cell.styleIndex < styleSheet.cellXfsNumFmt.length) {
          final id = styleSheet.cellXfsNumFmt[cell.styleIndex];
          final code = styleSheet.numFmts[id];
          if (code != null && code.trim().isNotEmpty && code != 'General') {
            numberCode = code;
          }
        }
        final key = [
          cell.fontBold,
          cell.fontSize,
          cell.fontFamily,
          cell.fontRgb,
          cell.fillRgb,
          cell.horizontalAlign.name,
          cell.wrapText ?? false,
          numberCode ?? '',
        ].join('|');
        cellStyleIds.putIfAbsent(key, () {
          final name = 'ce${cellStyleIds.length + 1}';
          String? dataStyle;
          if (numberCode != null) {
            dataStyle = numberStyleIds.putIfAbsent(numberCode, () {
              final numberName = 'N${numberStyleIds.length + 1}';
              numberStyleBuffers.add(_numberStyleXml(numberCode!, numberName));
              return numberName;
            });
          }
          final buffer = StringBuffer(
            '<style:style style:name="$name" style:family="table-cell"'
            '${dataStyle == null ? '' : ' style:data-style-name="$dataStyle"'}>',
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
  final List<String> conditionalStyleBuffers = [];
  final List<String> numberStyleBuffers = [];
  final Map<String, String> conditionalStyles = {};
  final List<String> validationDefinitions = [];
  final List<List<String>> validationXml = [];
  final Map<String, String> validationNames = {};
  final Map<String, List<int>> media = {};
  final Map<String, List<_WriterImage>> images = {};
  var _validationCount = 0;

  final Map<String, String> cellStyles = {};

  String cellKey(int sheet, SmlCell cell) => '$sheet:${cell.ref.a1}';

  String? cellStyle(SmlWorksheet sheet, SmlCell cell) =>
      cellStyles[cellKey(book.sheets.indexOf(sheet), cell)];

  List<_WriterImage> imagesAt(SmlWorksheet sheet, int col, int row) =>
      images['${sheet.name}:$col:$row'] ?? const <_WriterImage>[];

  String? validationName(SmlWorksheet sheet, int col, int row) =>
      validationNames['${sheet.name}:${SmlCellRef(col, row).a1}'];

  static String _escapeAttr(String value) => OdsSheetWriter._escapeAttr(value);

  static String _validationXml(
    SmlDataValidation rule,
    String name,
    String baseCellAddress,
  ) {
    final condition = _validationCondition(rule);
    final buffer = StringBuffer(
      '<table:content-validation table:name="$name" '
      'table:condition="${_escapeAttr(condition)}" '
      'table:allow-empty-cell="${rule.allowBlank}" '
      'table:base-cell-address="$baseCellAddress">',
    );
    if (rule.promptTitle.isNotEmpty || rule.prompt.isNotEmpty) {
      buffer.write(
        '<table:help-message table:title="${_escapeAttr(rule.promptTitle)}" '
        'table:display="true"><text:p>${_escapeAttr(rule.prompt)}</text:p>'
        '</table:help-message>',
      );
    }
    if (rule.errorTitle.isNotEmpty || rule.error.isNotEmpty) {
      buffer.write(
        '<table:error-message table:message-type="${rule.errorStyle}" '
        'table:title="${_escapeAttr(rule.errorTitle)}" '
        'table:display="true"><text:p>${_escapeAttr(rule.error)}</text:p>'
        '</table:error-message>',
      );
    }
    buffer.write('</table:content-validation>');
    return buffer.toString();
  }

  static String _validationCondition(SmlDataValidation rule) {
    String op(SmlValidationOperator operator) => switch (operator) {
      SmlValidationOperator.between => 'between',
      SmlValidationOperator.notBetween => 'not-between',
      SmlValidationOperator.equal => '=',
      SmlValidationOperator.notEqual => '<>',
      SmlValidationOperator.greaterThan => '>',
      SmlValidationOperator.lessThan => '<',
      SmlValidationOperator.greaterThanOrEqual => '>=',
      SmlValidationOperator.lessThanOrEqual => '<=',
    };
    String value(String raw) {
      if (rule.kind == SmlValidationKind.date) {
        final serial = double.tryParse(raw);
        if (serial != null) {
          final date = excelSerialToDate(serial);
          return '${date.year}-${date.month}-${date.day}';
        }
      }
      return raw;
    }

    if (rule.kind == SmlValidationKind.list) {
      if (rule.listSourceRange case final range?) {
        final sheet = rule.listSourceSheet;
        final address = sheet == null || sheet.isEmpty
            ? '.${range.start.a1}:.${range.end.a1}'
            : OdsSheetWriter._rangeAddress(sheet, range);
        return 'of:cell-content-is-in-list([$address])';
      }
      final items = rule.listItems
          .map((item) => '"${item.replaceAll('"', '""')}"')
          .join(';');
      return 'of:cell-content-is-in-list($items)';
    }
    if (rule.kind == SmlValidationKind.custom) {
      return 'of:is-true-formula([.A1]>0)';
    }
    final prefix = switch (rule.kind) {
      SmlValidationKind.whole => 'of:cell-content-is-whole-number()',
      SmlValidationKind.decimal => 'of:cell-content-is-decimal-number()',
      SmlValidationKind.date => 'of:cell-content-is-date()',
      SmlValidationKind.textLength => 'of:cell-content-text-length()',
      _ => 'of:cell-content-is-whole-number()',
    };
    if (rule.operator == SmlValidationOperator.between ||
        rule.operator == SmlValidationOperator.notBetween) {
      final between = rule.operator == SmlValidationOperator.between
          ? 'between'
          : 'not-between';
      return '$prefix and cell-content-is-$between('
          '${value(rule.formula1)},${value(rule.formula2)})';
    }
    return '$prefix and cell-content()${op(rule.operator)}'
        '${value(rule.formula1)}';
  }

  String conditionalStyle(SmlConditionalRule rule) {
    final fill = rule.fillRgb;
    final font = rule.fontRgb;
    final key = '$fill|$font';
    return conditionalStyles.putIfAbsent(key, () {
      final name = 'cf${conditionalStyles.length + 1}';
      final buffer = StringBuffer(
        '<style:style style:name="$name" style:display-name="$name" style:family="table-cell" '
        'style:parent-style-name="Default">',
      );
      if (fill.isNotEmpty) {
        buffer.write(
          '<style:table-cell-properties fo:background-color="#${fill.toLowerCase()}"/>',
        );
      }
      if (font.isNotEmpty) {
        buffer.write(
          '<style:text-properties fo:color="#${font.toLowerCase()}"/>',
        );
      }
      buffer.write('</style:style>');
      conditionalStyleBuffers.add(buffer.toString());
      return name;
    });
  }

  void writeNumberStyles(XmlWriter w) {
    for (final buffer in numberStyleBuffers) {
      w.writeRaw(buffer);
    }
  }

  static String _numberStyleXml(String code, String name) {
    final clean = code.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    final percent = clean.contains('%');
    final date = RegExp(
      r'yyyy|yy|mmm|dd',
      caseSensitive: false,
    ).hasMatch(clean);
    final currency = RegExp(r'[$€£¥]').firstMatch(clean)?.group(0);
    final decimals = _decimals(clean);
    final grouping = clean.contains(',');
    final number =
        '<number:number number:decimal-places="$decimals" '
        'number:min-decimal-places="$decimals" number:min-integer-digits="1"'
        '${grouping ? ' number:grouping="true"' : ''}/>';
    if (percent) {
      return '<number:percentage-style style:name="$name">'
          '$number<number:text>%</number:text></number:percentage-style>';
    }
    if (date) {
      return '<number:date-style style:name="$name">'
          '<number:year number:style="long"/><number:text>-</number:text>'
          '<number:month number:style="long"/><number:text>-</number:text>'
          '<number:day number:style="long"/></number:date-style>';
    }
    if (currency != null) {
      return '<number:currency-style style:name="$name">'
          '<number:currency-symbol>$currency</number:currency-symbol>'
          '$number</number:currency-style>';
    }
    return '<number:number-style style:name="$name">$number</number:number-style>';
  }

  static int _decimals(String code) {
    final dot = code.indexOf('.');
    if (dot < 0) return 0;
    var count = 0;
    for (var i = dot + 1; i < code.length; i++) {
      if (code[i] == '0' || code[i] == '#') {
        count++;
      } else {
        break;
      }
    }
    return count.clamp(0, 10);
  }

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

  void writePageLayouts(XmlWriter w) {
    for (var index = 0; index < book.sheets.length; index++) {
      final setup = book.sheets[index].pageSetup ?? SmlPageSetup();
      var width = setup.paperWidthIn;
      var height = setup.paperHeightIn;
      if (setup.orientation == SmlPageOrientation.landscape && width < height) {
        final swap = width;
        width = height;
        height = swap;
      } else if (setup.orientation == SmlPageOrientation.portrait &&
          width > height) {
        final swap = width;
        width = height;
        height = swap;
      }
      w.writeStartElement('page-layout', prefix: 'style');
      w.writeAttribute('style:name', 'pm$index');
      w.writeStartElement('page-layout-properties', prefix: 'style');
      w.writeAttribute('fo:page-width', '${width.toStringAsFixed(4)}in');
      w.writeAttribute('fo:page-height', '${height.toStringAsFixed(4)}in');
      w.writeAttribute(
        'style:print-orientation',
        setup.orientation == SmlPageOrientation.landscape
            ? 'landscape'
            : 'portrait',
      );
      w.writeAttribute(
        'fo:margin-left',
        '${setup.marginLeftIn.toStringAsFixed(4)}in',
      );
      w.writeAttribute(
        'fo:margin-right',
        '${setup.marginRightIn.toStringAsFixed(4)}in',
      );
      w.writeAttribute(
        'fo:margin-top',
        '${setup.marginTopIn.toStringAsFixed(4)}in',
      );
      w.writeAttribute(
        'fo:margin-bottom',
        '${setup.marginBottomIn.toStringAsFixed(4)}in',
      );
      if (setup.scale != 100) {
        w.writeAttribute('style:scale-to', '${setup.scale}%');
      }
      if (setup.fitToWidth > 0) {
        w.writeAttribute('style:scale-to-X', '${setup.fitToWidth}');
      }
      if (setup.fitToHeight > 0) {
        w.writeAttribute('style:scale-to-Y', '${setup.fitToHeight}');
      }
      if (setup.useFirstPageNumber && setup.firstPageNumber != null) {
        w.writeAttribute('style:first-page-number', '${setup.firstPageNumber}');
      }
      final print = <String>[
        if (setup.printGridlines) 'grid',
        if (setup.printHeadings) 'headers',
      ];
      if (print.isNotEmpty) {
        w.writeAttribute('style:print', print.join(' '));
      }
      w.writeEndElement();
      w.writeStartElement('header-style', prefix: 'style');
      w.writeEmptyElement(
        'header-footer-properties',
        prefix: 'style',
        attributes: {
          'fo:min-height': '0.2953in',
          'fo:margin-left': '0in',
          'fo:margin-right': '0in',
          'fo:margin-bottom': '0.0984in',
        },
      );
      w.writeEndElement();
      w.writeStartElement('footer-style', prefix: 'style');
      w.writeEmptyElement(
        'header-footer-properties',
        prefix: 'style',
        attributes: {
          'fo:min-height': '0.2953in',
          'fo:margin-left': '0in',
          'fo:margin-right': '0in',
          'fo:margin-top': '0.0984in',
        },
      );
      w.writeEndElement();
      w.writeEndElement();
    }
  }

  void writeMasterPages(XmlWriter w) {
    for (var index = 0; index < book.sheets.length; index++) {
      w.writeStartElement('master-page', prefix: 'style');
      w.writeAttribute('style:name', 'mp$index');
      w.writeAttribute('style:page-layout-name', 'pm$index');
      _writeHeaderFooter(w, book.sheets[index].headerFooter, header: true);
      _writeHeaderFooter(w, book.sheets[index].headerFooter, header: false);
      w.writeEndElement();
    }
  }

  static void _writeHeaderFooter(
    XmlWriter w,
    SmlHeaderFooter? hf, {
    required bool header,
  }) {
    final tag = header ? 'header' : 'footer';
    if (hf == null || hf.isEmpty) {
      w.writeEmptyElement(tag, prefix: 'style');
      return;
    }
    final sections = <String, String>{
      'left': header ? hf.headerLeft : hf.footerLeft,
      'center': header ? hf.headerCenter : hf.footerCenter,
      'right': header ? hf.headerRight : hf.footerRight,
    }..removeWhere((_, value) => value.isEmpty);
    if (sections.isEmpty) {
      w.writeEmptyElement(tag, prefix: 'style');
      return;
    }
    w.writeStartElement(tag, prefix: 'style');
    for (final entry in sections.entries) {
      w.writeStartElement('region-${entry.key}', prefix: 'style');
      w.writeStartElement('p', prefix: 'text');
      OdsSheetWriter._writeHeaderText(w, entry.value);
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  void writeConditionalStyles(XmlWriter w) {
    for (final buffer in conditionalStyleBuffers) {
      w.writeRaw(buffer);
    }
  }
}

class _WriterImage {
  const _WriterImage({
    required this.path,
    required this.name,
    required this.width,
    required this.height,
  });

  final String path;
  final String name;
  final double width;
  final double height;
}
