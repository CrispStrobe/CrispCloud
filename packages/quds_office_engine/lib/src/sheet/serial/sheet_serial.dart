import 'dart:convert';
import 'dart:typed_data';

import '../../office/office_document_properties.dart';
import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../formula/dep_graph.dart';
import '../formula/formula_refs.dart';
import '../model/sml_analysis.dart';
import '../model/sml_sparkline.dart';
import '../model/sml_workbook.dart';
import '../shared_strings.dart';
import '../styles/sml_styles.dart';
import 'sheet_drawing_io.dart';

/// Class SheetDeserializer.
class SheetDeserializer {
  /// read API.
  SmlWorkbook read(OpcPackage package) {
    final SharedStringTable sst =
        package.getPart('/xl/sharedStrings.xml') == null
        ? SharedStringTable()
        : SharedStringTable.parse(
            package.getPart('/xl/sharedStrings.xml')!.readText(),
          );
    SmlStyleSheet? styles;
    if (package.getPart('/xl/styles.xml') != null) {
      List<String>? theme;
      final PackagePart? themePart = package.getPart('/xl/theme/theme1.xml');
      if (themePart != null) {
        theme = SmlStyleSheet.parseTheme(themePart.readText());
      }
      styles = SmlStyleSheet.parse(
        package.getPart('/xl/styles.xml')!.readText(),
        themeColors: theme,
      );
    }
    final SmlWorkbook book = SmlWorkbook(
      sheets: <SmlWorksheet>[],
      sharedStrings: sst.values,
      package: package,
      styles: styles,
      properties: OfficeDocumentProperties.fromPackage(package),
    );
    final PackagePart? wb = package.getPart('/xl/workbook.xml');
    if (wb == null) {
      return book;
    }
    final RelationshipCollection rels = package.relationshipsFor(
      '/xl/workbook.xml',
    );
    final XmlPullReader reader = XmlPullReader(wb.readText());
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != 'sheet') {
        continue;
      }
      final String name = reader.getAttribute('name') ?? 'Sheet';
      final int id = int.parse(reader.getAttribute('sheetId') ?? '1');
      final String? rid = reader.getAttribute(
        'id',
        namespaceUri: OfficeNamespaces.r,
      );
      final SmlWorksheet sheet = SmlWorksheet(name: name, sheetId: id);
      if (rid != null) {
        final PackageRelationship? rel = rels.byId(rid);
        if (rel != null) {
          final String uri = rels.resolve(rel);
          final PackagePart? part = package.getPart(uri);
          if (part != null) {
            _readSheet(part.readText(), sheet, sst, package, uri, styles);
          }
        }
      }
      book.sheets.add(sheet);
    }
    if (book.sheets.isEmpty) {
      book.sheets.add(SmlWorksheet(name: 'Sheet1', sheetId: 1));
    }
    _readDefinedNames(wb.readText(), book);
    return book;
  }

  /// readBytes API.
  SmlWorkbook readBytes(Uint8List bytes, {String? password}) =>
      read(OpcPackage.openBytes(bytes, password: password));

  static void _readDefinedNames(String xml, SmlWorkbook book) {
    final XmlPullReader reader = XmlPullReader(xml);
    String? name;
    String? localSheetId;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'definedName') {
        name = reader.getAttribute('name');
        localSheetId = reader.getAttribute('localSheetId');
      } else if (reader.eventType == XmlEventType.characters && name != null) {
        final String raw = reader.text.trim();
        if (name == '_xlnm.Print_Titles') {
          _applyPrintTitles(book, raw, localSheetId);
          name = null;
          localSheetId = null;
          continue;
        }
        final int bang = raw.lastIndexOf('!');
        if (bang > 0) {
          var sheetName = raw.substring(0, bang);
          if (sheetName.startsWith("'") && sheetName.endsWith("'")) {
            sheetName = sheetName.substring(1, sheetName.length - 1);
          }
          try {
            book.namedRanges.add(
              SmlNamedRange(
                name: name,
                sheetName: sheetName,
                range: SmlRange.parse(raw.substring(bang + 1)),
              ),
            );
          } on FormatException {
            // Ignore names that are not A1 ranges.
          }
        }
        name = null;
        localSheetId = null;
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'definedName') {
        name = null;
        localSheetId = null;
      }
    }
  }

  static void _applyPrintTitles(
    SmlWorkbook book,
    String raw,
    String? localSheetId,
  ) {
    SmlWorksheet? sheet;
    final int? idx = int.tryParse(localSheetId ?? '');
    if (idx != null && idx >= 0 && idx < book.sheets.length) {
      sheet = book.sheets[idx];
    }
    for (final String part in raw.split(',')) {
      final String token = part.trim();
      final int bang = token.lastIndexOf('!');
      if (bang <= 0) {
        continue;
      }
      var sheetName = token.substring(0, bang);
      if (sheetName.startsWith("'") && sheetName.endsWith("'")) {
        sheetName = sheetName.substring(1, sheetName.length - 1);
      }
      sheet ??= () {
        for (final SmlWorksheet s in book.sheets) {
          if (s.name == sheetName) {
            return s;
          }
        }
        return null;
      }();
      if (sheet == null) {
        continue;
      }
      final String ref = token.substring(bang + 1).replaceAll('\$', '');
      final Match? rows = RegExp(r'^(\d+):(\d+)$').firstMatch(ref);
      if (rows != null) {
        final int r0 = int.parse(rows.group(1)!) - 1;
        final int r1 = int.parse(rows.group(2)!) - 1;
        sheet.printTitleRows = SmlRange(SmlCellRef(0, r0), SmlCellRef(0, r1));
        continue;
      }
      final Match? cols = RegExp(r'^([A-Za-z]+):([A-Za-z]+)$').firstMatch(ref);
      if (cols != null) {
        final int c0 = SmlCellRef.parse('${cols.group(1)}1').col;
        final int c1 = SmlCellRef.parse('${cols.group(2)}1').col;
        sheet.printTitleCols = SmlRange(SmlCellRef(c0, 0), SmlCellRef(c1, 0));
      }
    }
  }

  static String _elementText(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final int depth = reader.depth;
    final StringBuffer buffer = StringBuffer();
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
  }

  static void _applyHeaderFooterSection(
    SmlHeaderFooter hf,
    String raw, {
    required bool header,
  }) {
    // Formatting codes (`&"Arial,Bold"`, `&12`, `&B`, `&&`) stay in the
    // section text; only `&L` / `&C` / `&R` switch sections.
    final Map<String, StringBuffer> sections = <String, StringBuffer>{
      'L': StringBuffer(),
      'C': StringBuffer(),
      'R': StringBuffer(),
    };
    StringBuffer current = sections['C']!;
    var i = 0;
    while (i < raw.length) {
      final String ch = raw[i];
      if (ch != '&' || i + 1 >= raw.length) {
        current.write(ch);
        i++;
        continue;
      }
      final String code = raw[i + 1];
      final StringBuffer? target = sections[code];
      if (target != null) {
        current = target;
        i += 2;
      } else if (code == '"') {
        final int close = raw.indexOf('"', i + 2);
        final int end = close < 0 ? raw.length : close + 1;
        current.write(raw.substring(i, end));
        i = end;
      } else {
        current.write(raw.substring(i, i + 2));
        i += 2;
      }
    }
    final String left = sections['L'].toString();
    final String center = sections['C'].toString();
    final String right = sections['R'].toString();
    if (header) {
      hf
        ..headerLeft = left
        ..headerCenter = center
        ..headerRight = right;
    } else {
      hf
        ..footerLeft = left
        ..footerCenter = center
        ..footerRight = right;
    }
  }

  void _readSheet(
    String xml,
    SmlWorksheet sheet,
    SharedStringTable sst,
    OpcPackage package,
    String sheetUri,
    SmlStyleSheet? styles,
  ) {
    final XmlPullReader reader = XmlPullReader(xml);
    SmlCell? current;
    // `t="shared"` masters by `si`: formula text and the cell it is written for.
    final Map<String, ({String formula, SmlCellRef anchor})> shared =
        <String, ({String formula, SmlCellRef anchor})>{};
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'sheetView') {
        final String? rtl = reader.getAttribute('rightToLeft');
        sheet.rightToLeft = rtl == '1' || rtl?.toLowerCase() == 'true';
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'autoFilter') {
        final String? ref = reader.getAttribute('ref');
        if (ref != null && ref.isNotEmpty) {
          sheet.autoFilter = SmlAutoFilter(range: SmlRange.parse(ref));
        }
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'sheetProtection') {
        sheet.protection = SmlSheetProtection(enabled: true);
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'oddHeader') {
        sheet.headerFooter ??= SmlHeaderFooter();
        final String text = _elementText(reader);
        _applyHeaderFooterSection(sheet.headerFooter!, text, header: true);
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'oddFooter') {
        sheet.headerFooter ??= SmlHeaderFooter();
        final String text = _elementText(reader);
        _applyHeaderFooterSection(sheet.headerFooter!, text, header: false);
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'dataValidation') {
        final String? sqref = reader.getAttribute('sqref');
        final String type = reader.getAttribute('type') ?? 'custom';
        if (sqref != null && sqref.isNotEmpty) {
          sheet.validations.add(
            SmlDataValidation(
              range: SmlRange.parse(sqref.split(' ').first),
              kind: switch (type) {
                'list' => SmlValidationKind.list,
                'whole' => SmlValidationKind.whole,
                'decimal' => SmlValidationKind.decimal,
                'date' => SmlValidationKind.date,
                'textLength' => SmlValidationKind.textLength,
                _ => SmlValidationKind.custom,
              },
              formula1: '',
              allowBlank: reader.getAttribute('allowBlank') != '0',
            ),
          );
        }
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'formula1' &&
          sheet.validations.isNotEmpty) {
        sheet.validations.last.formula1 = _readText(reader);
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'formula' &&
          sheet.conditionalFormats.isNotEmpty) {
        sheet.conditionalFormats.last.formula = _readText(reader);
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'conditionalFormatting') {
        final String? sqref = reader.getAttribute('sqref');
        if (sqref != null && sqref.isNotEmpty) {
          sheet.conditionalFormats.add(
            SmlConditionalRule(
              range: SmlRange.parse(sqref.split(' ').first),
              kind: SmlConditionalKind.greaterThan,
            ),
          );
        }
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'pane') {
        final int x = int.tryParse(reader.getAttribute('xSplit') ?? '0') ?? 0;
        final int y = int.tryParse(reader.getAttribute('ySplit') ?? '0') ?? 0;
        sheet.freezeCols = x.clamp(0, SmlWorksheet.excelColumnCount - 1);
        sheet.freezeRows = y.clamp(0, SmlWorksheet.excelRowCount - 1);
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'col') {
        final int min = int.tryParse(reader.getAttribute('min') ?? '1') ?? 1;
        final int max =
            int.tryParse(reader.getAttribute('max') ?? '$min') ?? min;
        final double? width = double.tryParse(
          reader.getAttribute('width') ?? '',
        );
        if (width != null) {
          final double px = SmlWorksheet.columnWidthFromExcel(width);
          final int from = (min - 1).clamp(
            0,
            SmlWorksheet.excelColumnCount - 1,
          );
          final int to = (max - 1).clamp(0, SmlWorksheet.excelColumnCount - 1);
          for (int c = from; c <= to; c++) {
            sheet.columnWidths[c] = px;
          }
        }
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'row') {
        final int r = (int.tryParse(reader.getAttribute('r') ?? '1') ?? 1) - 1;
        final double? ht = double.tryParse(reader.getAttribute('ht') ?? '');
        if (ht != null && r >= 0 && r < SmlWorksheet.excelRowCount) {
          sheet.rowHeights[r] = SmlWorksheet.rowHeightFromExcel(ht);
        }
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'c') {
        final String ref = reader.getAttribute('r') ?? 'A1';
        final String? t = reader.getAttribute('t');
        final int s = int.parse(reader.getAttribute('s') ?? '0');
        current = sheet.cellA1(ref);
        current.styleIndex = s;
        current.horizontalAlign = styles?.alignAt(s) ?? SmlHAlign.general;
        current.fillRgb = styles?.fillAt(s) ?? '';
        current.fontRgb = styles?.fontAt(s) ?? '';
        current.fontBold = styles?.boldAt(s) ?? false;
        current.fontSize = styles?.sizeAt(s) ?? 11;
        current.type = switch (t) {
          's' => SmlCellType.string,
          'b' => SmlCellType.boolean,
          'e' => SmlCellType.error,
          'str' || 'inlineStr' => SmlCellType.string,
          _ => SmlCellType.number,
        };
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'f' &&
          current != null) {
        // formula text follows
      } else if (reader.eventType == XmlEventType.characters &&
          current != null) {
        // assigned below via element-end tracking
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'c') {
        current = null;
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'is' &&
          current != null) {
        current.value = _readInlineString(reader);
      }
      if (reader.eventType == XmlEventType.startElement &&
          (reader.localName == 'v' || reader.localName == 'f') &&
          current != null) {
        final String name = reader.localName;
        final String? formulaKind = name == 'f'
            ? reader.getAttribute('t')
            : null;
        final String? sharedIndex = name == 'f'
            ? reader.getAttribute('si')
            : null;
        final String text = _readText(reader);
        if (name == 'f') {
          String? formula = text;
          if (formulaKind == 'shared' && sharedIndex != null) {
            final ({String formula, SmlCellRef anchor})? master =
                shared[sharedIndex];
            if (text.isNotEmpty) {
              shared[sharedIndex] = (formula: text, anchor: current.ref);
            } else if (master != null) {
              formula = FormulaRefShift.shift(
                master.formula,
                rows: current.ref.row - master.anchor.row,
                columns: current.ref.col - master.anchor.col,
              );
            } else {
              formula = null;
            }
          }
          if (formula != null && formula.isNotEmpty) {
            current.formula = formula;
            current.type = SmlCellType.formula;
          }
        } else if (current.type == SmlCellType.string &&
            int.tryParse(text) != null) {
          current.value = sst[int.parse(text)];
        } else if (current.type == SmlCellType.boolean) {
          current.value = text == '1' || text.toLowerCase() == 'true';
        } else {
          current.value = double.tryParse(text) ?? text;
        }
      }
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'mergeCell') {
        final String? ref = reader.getAttribute('ref');
        if (ref != null && ref.isNotEmpty) {
          sheet.merges.add(SmlMerge.parse(ref));
        }
      }
    }
    SheetDrawingIo.readSheet(sheet, package, sheetUri);
    _readSheetExtras(sheet, package, sheetUri);
  }

  static void _readSheetExtras(
    SmlWorksheet sheet,
    OpcPackage package,
    String sheetUri,
  ) {
    final PackagePart? comments = package.getPart(
      '/xl/comments${sheet.sheetId}.xml',
    );
    if (comments != null) {
      final XmlPullReader reader = XmlPullReader(comments.readText());
      String? ref;
      String author = '';
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'comment') {
          ref = reader.getAttribute('ref');
          author = reader.getAttribute('author') ?? '';
        } else if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'text' &&
            ref != null) {
          sheet.comments.add(
            SmlComment(
              ref: SmlCellRef.parse(ref),
              text: _readText(reader),
              author: author,
            ),
          );
          ref = null;
        }
      }
    }
    final PackagePart? tables = package.getPart(
      '/xl/tables${sheet.sheetId}.xml',
    );
    if (tables != null) {
      final XmlPullReader reader = XmlPullReader(tables.readText());
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'table') {
          final String name = reader.getAttribute('name') ?? 'Table';
          final String? ref = reader.getAttribute('ref');
          if (ref != null) {
            sheet.tables.add(SmlTable(name: name, range: SmlRange.parse(ref)));
          }
        }
      }
    }
    final PackagePart? sparks = package.getPart(
      '/xl/sparklines${sheet.sheetId}.xml',
    );
    if (sparks != null) {
      final XmlPullReader reader = XmlPullReader(sparks.readText());
      while (reader.next()) {
        if (reader.eventType != XmlEventType.startElement ||
            reader.localName != 'sparkline') {
          continue;
        }
        final String? ref = reader.getAttribute('ref');
        final String? sqref = reader.getAttribute('sqref');
        if (ref == null || sqref == null) {
          continue;
        }
        sheet.sparklines.add(
          SmlSparkline(
            anchor: SmlCellRef.parse(ref),
            source: SmlRange.parse(sqref),
            kind: reader.getAttribute('type') == 'column'
                ? SmlSparklineKind.column
                : SmlSparklineKind.line,
          ),
        );
      }
    }
    final PackagePart? pivot = package.getPart(
      '/xl/pivotCache/pivotCacheDefinition${sheet.sheetId}.xml',
    );
    if (pivot != null && sheet.pivots.isEmpty) {
      final XmlPullReader reader = XmlPullReader(pivot.readText());
      while (reader.next()) {
        if (reader.eventType == XmlEventType.startElement &&
            reader.localName == 'worksheetSource') {
          final String? ref = reader.getAttribute('ref');
          if (ref != null) {
            sheet.pivots.add(
              SmlPivotTable(
                source: SmlRange.parse(ref),
                rowField: 0,
                dataField: 1,
              ),
            );
          }
        }
      }
    }
  }

  /// Text of an inline string (`<is>`): plain `<t>` or rich-text runs,
  /// without phonetic (`<rPh>`) readings.
  static String _readInlineString(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = reader.depth;
    var inText = false;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.startElement) {
        if (reader.localName == 'rPh') {
          reader.skip();
        } else if (reader.localName == 't') {
          inText = !reader.isEmptyElement;
        }
      } else if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 't') {
          inText = false;
        }
      } else if (inText &&
          (reader.eventType == XmlEventType.characters ||
              reader.eventType == XmlEventType.cdata)) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
  }

  static String _readText(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
  }
}

/// Class SheetSerializer.
class SheetSerializer {
  /// writeBytes API.
  Uint8List writeBytes(
    SmlWorkbook book, {
    bool recalculate = true,
    String? password,
  }) {
    return write(book, recalculate: recalculate).save(password: password);
  }

  /// write API.
  OpcPackage write(SmlWorkbook book, {bool recalculate = true}) {
    if (recalculate) {
      FormulaDepGraph(book).recalculate();
    }
    final OpcPackage package =
        book.package ?? OpcPackage.create(OpcPackageKind.sheet);
    final SharedStringTable sst = SharedStringTable();
    for (final SmlWorksheet sheet in book.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        if (cell.type == SmlCellType.string || cell.value is String) {
          sst.intern(cell.asString);
        }
      }
    }
    if (package.getPart('/xl/sharedStrings.xml') == null) {
      package.createPart(
        '/xl/sharedStrings.xml',
        OfficeContentTypes.sheetSharedStrings,
        utf8.encode(sst.toXml()),
      );
    } else {
      package.getPart('/xl/sharedStrings.xml')!.writeText(sst.toXml());
    }
    _syncStyles(book, package);
    book.properties.writeToPackage(package);
    package.getPart('/xl/workbook.xml')!.writeText(_workbookXml(book));
    final RelationshipCollection rels = package.relationshipsFor(
      '/xl/workbook.xml',
    );
    for (int i = 0; i < book.sheets.length; i++) {
      final String uri = '/xl/worksheets/sheet${i + 1}.xml';
      if (package.getPart(uri) == null) {
        package.createPart(
          uri,
          OfficeContentTypes.sheetWorksheet,
          utf8.encode(''),
        );
        rels.add(
          type: RelationshipTypes.worksheet,
          target: 'worksheets/sheet${i + 1}.xml',
        );
      }
      SheetDrawingIo.syncSheet(book.sheets[i], package, uri, i + 1);
      package
          .getPart(uri)!
          .writeText(_sheetXml(book.sheets[i], sst, package, uri));
      _writeSheetExtras(book.sheets[i], package);
    }
    if (package
            .relationshipsFor('/xl/workbook.xml')
            .firstByType(RelationshipTypes.sharedStrings) ==
        null) {
      package
          .relationshipsFor('/xl/workbook.xml')
          .add(
            type: RelationshipTypes.sharedStrings,
            target: 'sharedStrings.xml',
          );
    }
    book.package = package;
    book.sharedStrings = sst.values;
    return package;
  }

  static void _writeSheetExtras(SmlWorksheet sheet, OpcPackage package) {
    if (sheet.comments.isNotEmpty) {
      final XmlWriter w = XmlWriter();
      w.writeStartDocument();
      w.writeStartElement('comments');
      for (final SmlComment comment in sheet.comments) {
        w.writeStartElement('comment');
        w.writeAttribute('ref', comment.ref.a1);
        w.writeAttribute('author', comment.author);
        w.writeStartElement('text');
        w.writeText(comment.text);
        w.writeEndElement();
        w.writeEndElement();
      }
      w.writeEndElement();
      final String uri = '/xl/comments${sheet.sheetId}.xml';
      final PackagePart? existing = package.getPart(uri);
      if (existing == null) {
        package.createPart(
          uri,
          OfficeContentTypes.sheetSharedStrings,
          utf8.encode(w.toXml()),
        );
      } else {
        existing.writeText(w.toXml());
      }
    }
    if (sheet.tables.isNotEmpty) {
      final XmlWriter w = XmlWriter();
      w.writeStartDocument();
      w.writeStartElement('tables');
      for (final SmlTable table in sheet.tables) {
        w.writeEmptyElement(
          'table',
          attributes: <String, String>{
            'name': table.name,
            'ref': '${table.range.start.a1}:${table.range.end.a1}',
            'headerRow': table.headerRow ? '1' : '0',
            'bandedRows': table.bandedRows ? '1' : '0',
          },
        );
      }
      w.writeEndElement();
      final String uri = '/xl/tables${sheet.sheetId}.xml';
      final PackagePart? existing = package.getPart(uri);
      if (existing == null) {
        package.createPart(
          uri,
          OfficeContentTypes.sheetWorksheet,
          utf8.encode(w.toXml()),
        );
      } else {
        existing.writeText(w.toXml());
      }
    }
    if (sheet.pivots.isNotEmpty) {
      final XmlWriter w = XmlWriter();
      w.writeStartDocument();
      w.writeStartElement(
        'pivotCacheDefinition',
        namespaceUri: OfficeNamespaces.x,
      );
      w.writeAttribute('refreshedBy', 'Quds Office');
      w.writeAttribute(
        'recordCount',
        '${sheet.pivots.first.source.cells.length}',
      );
      w.writeStartElement('cacheSource');
      w.writeAttribute('type', 'worksheet');
      w.writeEmptyElement(
        'worksheetSource',
        attributes: <String, String>{
          'ref':
              '${sheet.pivots.first.source.start.a1}:${sheet.pivots.first.source.end.a1}',
          'sheet': sheet.name,
        },
      );
      w.writeEndElement();
      w.writeEndElement();
      final String cacheUri =
          '/xl/pivotCache/pivotCacheDefinition${sheet.sheetId}.xml';
      final PackagePart? cache = package.getPart(cacheUri);
      if (cache == null) {
        package.createPart(
          cacheUri,
          OfficeContentTypes.sheetWorksheet,
          utf8.encode(w.toXml()),
        );
      } else {
        cache.writeText(w.toXml());
      }
      final XmlWriter table = XmlWriter();
      table.writeStartDocument();
      table.writeStartElement(
        'pivotTableDefinition',
        namespaceUri: OfficeNamespaces.x,
      );
      table.writeAttribute('name', sheet.pivots.first.name);
      table.writeEmptyElement(
        'location',
        attributes: <String, String>{'ref': sheet.pivots.first.source.start.a1},
      );
      table.writeEndElement();
      final String tableUri = '/xl/pivotTables/pivotTable${sheet.sheetId}.xml';
      final PackagePart? tablePart = package.getPart(tableUri);
      if (tablePart == null) {
        package.createPart(
          tableUri,
          OfficeContentTypes.sheetWorksheet,
          utf8.encode(table.toXml()),
        );
      } else {
        tablePart.writeText(table.toXml());
      }
    }
    if (sheet.sparklines.isNotEmpty) {
      final XmlWriter w = XmlWriter();
      w.writeStartDocument();
      w.writeStartElement('sparklines');
      for (final SmlSparkline spark in sheet.sparklines) {
        w.writeEmptyElement(
          'sparkline',
          attributes: <String, String>{
            'ref': spark.anchor.a1,
            'sqref': '${spark.source.start.a1}:${spark.source.end.a1}',
            'type': spark.kind.name,
          },
        );
      }
      w.writeEndElement();
      final String uri = '/xl/sparklines${sheet.sheetId}.xml';
      final PackagePart? existing = package.getPart(uri);
      if (existing == null) {
        package.createPart(
          uri,
          OfficeContentTypes.sheetWorksheet,
          utf8.encode(w.toXml()),
        );
      } else {
        existing.writeText(w.toXml());
      }
    }
  }

  static void _syncStyles(SmlWorkbook book, OpcPackage package) {
    var needsStyles = book.styles != null;
    for (final SmlWorksheet sheet in book.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        if (cell.horizontalAlign != SmlHAlign.general ||
            cell.fillRgb.isNotEmpty ||
            cell.fontRgb.isNotEmpty ||
            cell.fontBold ||
            cell.fontSize != 11) {
          needsStyles = true;
          break;
        }
      }
      if (needsStyles) {
        break;
      }
    }
    if (!needsStyles) {
      return;
    }
    final SmlStyleSheet styles = book.styles ?? SmlStyleSheet();
    for (final SmlWorksheet sheet in book.sheets) {
      for (final SmlCell cell in sheet.allCells) {
        if (cell.horizontalAlign == SmlHAlign.general &&
            cell.fillRgb.isEmpty &&
            cell.fontRgb.isEmpty &&
            !cell.fontBold &&
            cell.fontSize == 11) {
          continue;
        }
        cell.styleIndex = styles.xfFor(
          align: cell.horizontalAlign,
          fillRgb: cell.fillRgb,
          fontRgb: cell.fontRgb,
          bold: cell.fontBold,
          size: cell.fontSize,
        );
      }
    }
    book.styles = styles;
    if (package.getPart('/xl/styles.xml') == null) {
      package.createPart(
        '/xl/styles.xml',
        OfficeContentTypes.sheetStyles,
        utf8.encode(styles.toXml()),
      );
    } else {
      package.getPart('/xl/styles.xml')!.writeText(styles.toXml());
    }
    final RelationshipCollection rels = package.relationshipsFor(
      '/xl/workbook.xml',
    );
    if (rels.firstByType(RelationshipTypes.styles) == null) {
      rels.add(type: RelationshipTypes.styles, target: 'styles.xml');
    }
  }

  String _workbookXml(SmlWorkbook book) {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('workbook');
    w.writeAttribute('xmlns', OfficeNamespaces.x);
    w.writeNamespace('r', OfficeNamespaces.r);
    w.writeStartElement('sheets');
    for (int i = 0; i < book.sheets.length; i++) {
      final SmlWorksheet s = book.sheets[i];
      w.writeStartElement('sheet');
      w.writeAttribute('name', s.name);
      w.writeAttribute('sheetId', '${s.sheetId}');
      w.writeAttribute('r:id', 'rId${i + 1}');
      w.writeEndElement();
    }
    w.writeEndElement();
    if (book.namedRanges.isNotEmpty ||
        book.sheets.any(
          (SmlWorksheet s) =>
              s.printTitleRows != null || s.printTitleCols != null,
        )) {
      w.writeStartElement('definedNames');
      for (final SmlNamedRange name in book.namedRanges) {
        w.writeStartElement('definedName');
        w.writeAttribute('name', name.name);
        w.writeText("'${name.sheetName}'!${name.a1}");
        w.writeEndElement();
      }
      for (int i = 0; i < book.sheets.length; i++) {
        final SmlWorksheet sheet = book.sheets[i];
        final List<String> parts = <String>[];
        if (sheet.printTitleRows != null) {
          final SmlRange r = sheet.printTitleRows!;
          parts.add("'${sheet.name}'!\$${r.minRow + 1}:\$${r.maxRow + 1}");
        }
        if (sheet.printTitleCols != null) {
          final SmlRange c = sheet.printTitleCols!;
          final String a = SmlCellRef(
            c.minCol,
            0,
          ).a1.replaceAll(RegExp(r'\d+'), '');
          final String b = SmlCellRef(
            c.maxCol,
            0,
          ).a1.replaceAll(RegExp(r'\d+'), '');
          parts.add("'${sheet.name}'!\$$a:\$$b");
        }
        if (parts.isEmpty) {
          continue;
        }
        w.writeStartElement('definedName');
        w.writeAttribute('name', '_xlnm.Print_Titles');
        w.writeAttribute('localSheetId', '$i');
        w.writeText(parts.join(','));
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    return w.toXml();
  }

  String _sheetXml(
    SmlWorksheet sheet,
    SharedStringTable sst,
    OpcPackage package,
    String sheetUri,
  ) {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('worksheet');
    w.writeAttribute('xmlns', OfficeNamespaces.x);
    if (sheet.drawings.isNotEmpty) {
      w.writeNamespace('r', OfficeNamespaces.r);
    }
    _writeSheetViews(w, sheet);
    _writeCols(w, sheet);
    w.writeStartElement('sheetData');
    final Set<int> rowKeys = <int>{
      ...sheet.rows.keys,
      ...sheet.rowHeights.keys,
    };
    final List<int> rowIdx = rowKeys.toList()..sort();
    for (final int r in rowIdx) {
      final SmlRow row = sheet.rows[r] ?? SmlRow(r);
      w.writeStartElement('row');
      w.writeAttribute('r', '${r + 1}');
      final double? ht = sheet.rowHeights[r];
      if (ht != null) {
        w.writeAttribute('ht', '${SmlWorksheet.rowHeightToExcel(ht)}');
        w.writeAttribute('customHeight', '1');
      }
      final List<int> cols = row.cells.keys.toList()..sort();
      for (final int c in cols) {
        final SmlCell cell = row.cells[c]!;
        w.writeStartElement('c');
        w.writeAttribute('r', cell.ref.a1);
        if (cell.styleIndex != 0) {
          w.writeAttribute('s', '${cell.styleIndex}');
        }
        if (cell.formula != null) {
          w.writeStartElement('f');
          w.writeText(
            cell.formula!.startsWith('=')
                ? cell.formula!.substring(1)
                : cell.formula!,
          );
          w.writeEndElement();
          w.writeStartElement('v');
          w.writeText(cell.asString);
          w.writeEndElement();
        } else if (cell.type == SmlCellType.string || cell.value is String) {
          w.writeAttribute('t', 's');
          w.writeStartElement('v');
          w.writeText('${sst.intern(cell.asString)}');
          w.writeEndElement();
        } else if (cell.type == SmlCellType.boolean) {
          w.writeAttribute('t', 'b');
          w.writeStartElement('v');
          w.writeText(cell.value == true ? '1' : '0');
          w.writeEndElement();
        } else if (cell.value != null) {
          w.writeStartElement('v');
          w.writeText(cell.asString);
          w.writeEndElement();
        }
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    w.writeEndElement();
    if (sheet.autoFilter != null) {
      w.writeEmptyElement(
        'autoFilter',
        attributes: <String, String>{
          'ref':
              '${sheet.autoFilter!.range.start.a1}:${sheet.autoFilter!.range.end.a1}',
        },
      );
    }
    if (sheet.protection != null && sheet.protection!.enabled) {
      w.writeEmptyElement(
        'sheetProtection',
        attributes: <String, String>{'sheet': '1'},
      );
    }
    if (sheet.validations.isNotEmpty) {
      w.writeStartElement('dataValidations');
      w.writeAttribute('count', '${sheet.validations.length}');
      for (final SmlDataValidation rule in sheet.validations) {
        w.writeStartElement('dataValidation');
        w.writeAttribute('type', switch (rule.kind) {
          SmlValidationKind.list => 'list',
          SmlValidationKind.whole => 'whole',
          SmlValidationKind.decimal => 'decimal',
          SmlValidationKind.date => 'date',
          SmlValidationKind.textLength => 'textLength',
          SmlValidationKind.custom => 'custom',
        });
        w.writeAttribute(
          'sqref',
          '${rule.range.start.a1}:${rule.range.end.a1}',
        );
        w.writeAttribute('allowBlank', rule.allowBlank ? '1' : '0');
        if (rule.formula1.isNotEmpty) {
          w.writeStartElement('formula1');
          w.writeText(rule.formula1);
          w.writeEndElement();
        }
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    if (sheet.conditionalFormats.isNotEmpty) {
      for (final SmlConditionalRule rule in sheet.conditionalFormats) {
        w.writeStartElement('conditionalFormatting');
        w.writeAttribute(
          'sqref',
          '${rule.range.start.a1}:${rule.range.end.a1}',
        );
        w.writeStartElement('cfRule');
        w.writeAttribute('type', 'cellIs');
        w.writeAttribute('operator', switch (rule.kind) {
          SmlConditionalKind.greaterThan => 'greaterThan',
          SmlConditionalKind.lessThan => 'lessThan',
          SmlConditionalKind.equal => 'equal',
          SmlConditionalKind.contains => 'containsText',
          SmlConditionalKind.duplicate => 'duplicateValues',
        });
        if (rule.formula.isNotEmpty) {
          w.writeStartElement('formula');
          w.writeText(rule.formula);
          w.writeEndElement();
        }
        w.writeEndElement();
        w.writeEndElement();
      }
    }
    if (sheet.merges.isNotEmpty) {
      w.writeStartElement('mergeCells');
      w.writeAttribute('count', '${sheet.merges.length}');
      for (final SmlMerge merge in sheet.merges) {
        w.writeEmptyElement(
          'mergeCell',
          attributes: <String, String>{'ref': merge.a1},
        );
      }
      w.writeEndElement();
    }
    final SmlHeaderFooter? hf = sheet.headerFooter;
    if (hf != null && !hf.isEmpty) {
      w.writeStartElement('headerFooter');
      final String oddHeader = <String>[
        if (hf.headerLeft.isNotEmpty) '&L${hf.headerLeft}',
        if (hf.headerCenter.isNotEmpty) '&C${hf.headerCenter}',
        if (hf.headerRight.isNotEmpty) '&R${hf.headerRight}',
      ].join();
      final String oddFooter = <String>[
        if (hf.footerLeft.isNotEmpty) '&L${hf.footerLeft}',
        if (hf.footerCenter.isNotEmpty) '&C${hf.footerCenter}',
        if (hf.footerRight.isNotEmpty) '&R${hf.footerRight}',
      ].join();
      if (oddHeader.isNotEmpty) {
        w.writeStartElement('oddHeader');
        w.writeText(oddHeader);
        w.writeEndElement();
      }
      if (oddFooter.isNotEmpty) {
        w.writeStartElement('oddFooter');
        w.writeText(oddFooter);
        w.writeEndElement();
      }
      w.writeEndElement();
    }
    if (sheet.drawings.isNotEmpty) {
      final String? rid = SheetDrawingIo.drawingRelationshipId(
        package,
        sheetUri,
      );
      if (rid != null) {
        w.writeEmptyElement(
          'drawing',
          attributes: <String, String>{'r:id': rid},
        );
      }
    }
    w.writeEndElement();
    return w.toXml();
  }

  static void _writeSheetViews(XmlWriter w, SmlWorksheet sheet) {
    if (!sheet.rightToLeft && sheet.freezeRows <= 0 && sheet.freezeCols <= 0) {
      return;
    }
    w.writeStartElement('sheetViews');
    w.writeStartElement('sheetView');
    w.writeAttribute('workbookViewId', '0');
    if (sheet.rightToLeft) {
      w.writeAttribute('rightToLeft', '1');
    }
    if (sheet.freezeRows > 0 || sheet.freezeCols > 0) {
      w.writeStartElement('pane');
      w.writeAttribute('xSplit', '${sheet.freezeCols}');
      w.writeAttribute('ySplit', '${sheet.freezeRows}');
      w.writeAttribute(
        'topLeftCell',
        SmlCellRef(sheet.freezeCols, sheet.freezeRows).a1,
      );
      w.writeAttribute('activePane', 'bottomRight');
      w.writeAttribute('state', 'frozen');
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeCols(XmlWriter w, SmlWorksheet sheet) {
    if (sheet.columnWidths.isEmpty) {
      return;
    }
    final List<int> keys = sheet.columnWidths.keys.toList()..sort();
    w.writeStartElement('cols');
    var i = 0;
    while (i < keys.length) {
      final int start = keys[i];
      final double px = sheet.columnWidths[start]!;
      var end = start;
      while (i + 1 < keys.length &&
          keys[i + 1] == end + 1 &&
          (sheet.columnWidths[keys[i + 1]]! - px).abs() < 0.01) {
        i++;
        end = keys[i];
      }
      w.writeStartElement('col');
      w.writeAttribute('min', '${start + 1}');
      w.writeAttribute('max', '${end + 1}');
      w.writeAttribute('width', '${SmlWorksheet.columnWidthToExcel(px)}');
      w.writeAttribute('customWidth', '1');
      w.writeEndElement();
      i++;
    }
    w.writeEndElement();
  }
}
