import 'dart:convert';
import 'dart:typed_data';

import '../opc/content_types.dart';
import '../opc/opc_archive.dart';
import '../opc/package_part.dart';
import '../opc/relationships.dart';
import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';
import 'office_document_theme.dart';
import 'office_markup.dart';

/// Class XlsxNamedSheet.
class XlsxNamedSheet {
  /// XlsxNamedSheet API.
  const XlsxNamedSheet({required this.name, required this.rows});

  /// name API.
  final String name;

  /// rows API.
  final List<List<String>> rows;
}

/// Display text plus optional raw number / Excel date serial.
///
/// Merged cells other than the top-left of the range are left empty.
class XlsxGridCell {
  /// XlsxGridCell API.
  const XlsxGridCell({required this.text, this.number});

  /// text API.
  final String text;

  /// number API.
  final double? number;

  /// asDate API.
  DateTime? get asDate =>
      number == null ? null : XlsxGridReader.excelSerialToDateTime(number!);
}

/// Reads worksheets as string grids and optional header→row maps.
///
/// [sheetIndex] is **0-based**. Use [listSheets] when the sheet name is known.
abstract final class XlsxGridReader {
  /// Converts an Excel date serial (1900 date system) to UTC [DateTime].
  static DateTime excelSerialToDateTime(num serial) {
    return DateTime.utc(
      1899,
      12,
      30,
    ).add(Duration(milliseconds: (serial * 86400000).round()));
  }

  /// Parses a displayed cell string into text + raw number when numeric.
  static XlsxGridCell parseCell(String text) {
    return XlsxGridCell(text: text, number: double.tryParse(text));
  }

  /// Sheet names in workbook order. [sheetIndex] for [readSheet] is 0-based.
  static List<String> listSheets(Uint8List bytes, {String? password}) {
    return <String>[
      for (final XlsxNamedSheet s in readAll(bytes, password: password)) s.name,
    ];
  }

  /// readAll API.
  static List<XlsxNamedSheet> readAll(Uint8List bytes, {String? password}) {
    final OpcPackage package = OpcPackage.openBytes(bytes, password: password);
    final PackagePart? sstPart = package.getPart('/xl/sharedStrings.xml');
    final List<String> shared = sstPart == null
        ? <String>[]
        : _sharedStrings(sstPart.readText());
    final List<XlsxNamedSheet> out = <XlsxNamedSheet>[];
    for (final ({String name, String uri}) info in _sheetList(package)) {
      final PackagePart? part = package.getPart(info.uri);
      if (part == null) {
        continue;
      }
      out.add(
        XlsxNamedSheet(
          name: info.name,
          rows: _sheetRows(part.readText(), shared),
        ),
      );
    }
    return out;
  }

  /// readSheet API.
  static List<List<String>> readSheet(
    Uint8List bytes, {
    int sheetIndex = 0,
    String? password,
  }) {
    final List<XlsxNamedSheet> all = readAll(bytes, password: password);
    if (all.isEmpty) {
      return <List<String>>[];
    }
    final int i = sheetIndex.clamp(0, all.length - 1);
    return all[i].rows;
  }

  /// First non-empty row is headers; remaining rows become maps.
  static List<Map<String, String>> headerMaps(
    List<List<String>> rows, {
    int headerRow = 0,
  }) {
    if (rows.isEmpty || headerRow >= rows.length) {
      return <Map<String, String>>[];
    }
    final List<String> headers = <String>[
      for (final String h in rows[headerRow]) h.trim(),
    ];
    final List<Map<String, String>> maps = <Map<String, String>>[];
    for (int r = headerRow + 1; r < rows.length; r++) {
      final List<String> row = rows[r];
      final Map<String, String> map = <String, String>{};
      var any = false;
      for (int c = 0; c < headers.length; c++) {
        if (headers[c].isEmpty) {
          continue;
        }
        final String value = c < row.length ? row[c].trim() : '';
        if (value.isEmpty) {
          continue;
        }
        map[headers[c]] = value;
        any = true;
      }
      if (any) {
        maps.add(map);
      }
    }
    return maps;
  }

  /// readHeaderMaps API.
  static List<Map<String, String>> readHeaderMaps(
    Uint8List bytes, {
    int sheetIndex = 0,
    int headerRow = 0,
    String? password,
  }) {
    return headerMaps(
      readSheet(bytes, sheetIndex: sheetIndex, password: password),
      headerRow: headerRow,
    );
  }

  static List<({String name, String uri})> _sheetList(OpcPackage package) {
    final PackagePart? wb = package.getPart('/xl/workbook.xml');
    if (wb == null) {
      return <({String name, String uri})>[
        (name: 'Sheet1', uri: '/xl/worksheets/sheet1.xml'),
      ];
    }
    final RelationshipCollection rels = package.relationshipsFor(
      '/xl/workbook.xml',
    );
    final List<({String name, String uri})> out =
        <({String name, String uri})>[];
    final XmlPullReader reader = XmlPullReader(wb.readText());
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.localName != 'sheet') {
        continue;
      }
      final String name = reader.getAttribute('name') ?? 'Sheet';
      final String? rid =
          reader.getAttribute('id', namespaceUri: OfficeNamespaces.r) ??
          reader.getAttribute('id');
      if (rid == null) {
        continue;
      }
      final PackageRelationship? rel = rels.byId(rid);
      if (rel == null) {
        continue;
      }
      out.add((name: name, uri: rels.resolve(rel)));
    }
    return out;
  }

  static List<String> _sharedStrings(String xml) {
    final List<String> values = <String>[];
    final XmlPullReader reader = XmlPullReader(xml);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'si') {
        values.add(_readSi(reader));
      }
    }
    return values;
  }

  static String _readSi(XmlPullReader reader) {
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

  static List<List<String>> _sheetRows(String xml, List<String> shared) {
    final Map<int, Map<int, String>> sparse = <int, Map<int, String>>{};
    var maxCol = -1;
    var maxRow = -1;
    final XmlPullReader reader = XmlPullReader(xml);
    String? ref;
    String? type;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'c') {
        ref = reader.getAttribute('r');
        type = reader.getAttribute('t');
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'is' &&
          ref != null &&
          type == 'inlineStr') {
        final String text = _readText(reader);
        final ({int col, int row}) parsed = _parseA1(ref);
        sparse.putIfAbsent(parsed.row, () => <int, String>{})[parsed.col] =
            text;
        if (parsed.col > maxCol) {
          maxCol = parsed.col;
        }
        if (parsed.row > maxRow) {
          maxRow = parsed.row;
        }
      } else if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'v' &&
          ref != null) {
        final String text = _readText(reader);
        final ({int col, int row}) parsed = _parseA1(ref);
        final String value = switch (type) {
          's' => () {
            final int? i = int.tryParse(text);
            return i != null && i >= 0 && i < shared.length ? shared[i] : text;
          }(),
          'inlineStr' => text,
          'str' => text,
          'b' => text == '1' || text.toLowerCase() == 'true' ? 'TRUE' : 'FALSE',
          _ => text,
        };
        sparse.putIfAbsent(parsed.row, () => <int, String>{})[parsed.col] =
            value;
        if (parsed.col > maxCol) {
          maxCol = parsed.col;
        }
        if (parsed.row > maxRow) {
          maxRow = parsed.row;
        }
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'c') {
        ref = null;
        type = null;
      }
    }
    final List<List<String>> rows = <List<String>>[];
    for (int r = 0; r <= maxRow; r++) {
      final Map<int, String> cols = sparse[r] ?? <int, String>{};
      rows.add(<String>[for (int c = 0; c <= maxCol; c++) cols[c] ?? '']);
    }
    return rows;
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

  static ({int col, int row}) _parseA1(String a1) {
    var i = 0;
    while (i < a1.length) {
      final int cu = a1.codeUnitAt(i);
      final bool letter = (cu >= 65 && cu <= 90) || (cu >= 97 && cu <= 122);
      if (!letter) {
        break;
      }
      i++;
    }
    final String letters = a1.substring(0, i);
    final int row = (int.tryParse(a1.substring(i)) ?? 1) - 1;
    var col = 0;
    for (int k = 0; k < letters.length; k++) {
      col = col * 26 + (letters[k].toUpperCase().codeUnitAt(0) - 64);
    }
    return (col: col - 1, row: row);
  }
}

/// Class XlsxCell.
class XlsxCell {
  /// XlsxCell API.
  const XlsxCell(this.value, {this.style = 0});

  /// value API.
  final Object? value;

  /// style API.
  final int style;
}

/// Class XlsxSheetBuilder.
class XlsxSheetBuilder {
  /// XlsxSheetBuilder API.
  XlsxSheetBuilder(this.name, {this.theme});

  /// theme API.
  final OfficeDocumentTheme? theme;

  /// name API.
  final String name;

  /// rows API.
  final List<List<XlsxCell?>> rows = <List<XlsxCell?>>[];

  /// columnWidths API.
  final List<({int min, int max, double width})> columnWidths =
      <({int min, int max, double width})>[];

  /// merges API.
  final List<({int r1, int c1, int r2, int c2})> merges =
      <({int r1, int c1, int r2, int c2})>[];

  /// rowHeights API.
  final Map<int, double> rowHeights = <int, double>{};

  /// freezeRows API.
  int freezeRows = 0;

  /// freezeCols API.
  int freezeCols = 0;

  /// rightToLeft API.
  bool rightToLeft = false;

  /// autoFilterRef API.
  String? autoFilterRef;

  /// Charts floating over the sheet.
  final List<XlsxSheetChart> charts = <XlsxSheetChart>[];

  /// Pictures floating over the sheet (PNG or JPEG).
  final List<XlsxSheetPicture> pictures = <XlsxSheetPicture>[];

  /// Left-aligned odd-page header text.
  String? oddHeader;

  /// Left-aligned odd-page footer text.
  String? oddFooter;

  /// Anchors a DrawingML `c:chartSpace` part with its top-left corner at
  /// cell ([row], [col]) and the given size in points.
  void addChart({
    required int row,
    required int col,
    required double widthPoints,
    required double heightPoints,
    required String chartXml,
  }) {
    charts.add(
      XlsxSheetChart(
        row: row,
        col: col,
        widthEmu: (widthPoints * 12700).round(),
        heightEmu: (heightPoints * 12700).round(),
        xml: chartXml,
      ),
    );
  }

  /// Anchors a PNG or JPEG with its top-left corner at cell ([row], [col]).
  void addPicture({
    required int row,
    required int col,
    required double widthPoints,
    required double heightPoints,
    required Uint8List bytes,
  }) {
    pictures.add(
      XlsxSheetPicture(
        row: row,
        col: col,
        widthEmu: (widthPoints * 12700).round(),
        heightEmu: (heightPoints * 12700).round(),
        bytes: bytes,
      ),
    );
  }

  /// addRow API.
  void addRow(List<Object?> values, {int style = 0}) {
    rows.add(<XlsxCell?>[
      for (final Object? v in values) XlsxCell(v, style: style),
    ]);
  }

  /// setCell API.
  void setCell(int row, int col, Object? value, {int style = 0}) {
    while (rows.length <= row) {
      rows.add(<XlsxCell?>[]);
    }
    final List<XlsxCell?> line = rows[row];
    while (line.length <= col) {
      line.add(null);
    }
    line[col] = XlsxCell(value, style: style);
  }

  /// merge API.
  void merge(int r1, int c1, int r2, int c2) {
    merges.add((r1: r1, c1: c1, r2: r2, c2: c2));
  }

  /// colWidth API.
  void colWidth(int colIndex, double width, {int span = 1}) {
    columnWidths.add((min: colIndex + 1, max: colIndex + span, width: width));
  }

  /// rowHeight API.
  void rowHeight(int rowIndex, double height) {
    rowHeights[rowIndex] = height;
  }

  /// fitColumnWidths API.
  void fitColumnWidths({
    required int fromRow,
    required int toRow,
    required int colCount,
    double min = 8,
    double max = 48,
    List<({double min, double max})>? columnLimits,
  }) {
    final List<int> lens = List<int>.filled(colCount, 0);
    for (int r = fromRow; r <= toRow && r < rows.length; r++) {
      if (_isMergedBanner(r, colCount)) {
        continue;
      }
      final List<XlsxCell?> row = rows[r];
      for (int c = 0; c < colCount && c < row.length; c++) {
        final Object? value = row[c]?.value;
        if (value == null) {
          continue;
        }
        final int len = value.toString().length;
        if (len > lens[c]) {
          lens[c] = len;
        }
      }
    }
    columnWidths.removeWhere(
      (({int min, int max, double width}) e) => e.min <= colCount && e.max >= 1,
    );
    for (int c = 0; c < colCount; c++) {
      final double lo = columnLimits != null && c < columnLimits.length
          ? columnLimits[c].min
          : min;
      final double hi = columnLimits != null && c < columnLimits.length
          ? columnLimits[c].max
          : max;
      colWidth(c, (lens[c] * 1.12 + 2.2).clamp(lo, hi).toDouble());
    }
  }

  bool _isMergedBanner(int row, int colCount) {
    for (final ({int r1, int c1, int r2, int c2}) m in merges) {
      if (m.r1 <= row && m.r2 >= row && m.c1 <= 0 && m.c2 >= colCount - 1) {
        return true;
      }
    }
    return false;
  }
}

/// Chart anchored on a worksheet (see [XlsxSheetBuilder.addChart]).
class XlsxSheetChart {
  /// XlsxSheetChart API.
  const XlsxSheetChart({
    required this.row,
    required this.col,
    required this.widthEmu,
    required this.heightEmu,
    required this.xml,
  });

  /// Zero-based anchor row.
  final int row;

  /// Zero-based anchor column.
  final int col;

  /// widthEmu API.
  final int widthEmu;

  /// heightEmu API.
  final int heightEmu;

  /// `c:chartSpace` part XML.
  final String xml;
}

/// PNG or JPEG anchored on a worksheet.
class XlsxSheetPicture {
  /// XlsxSheetPicture API.
  const XlsxSheetPicture({
    required this.row,
    required this.col,
    required this.widthEmu,
    required this.heightEmu,
    required this.bytes,
  });

  /// Zero-based anchor row.
  final int row;

  /// Zero-based anchor column.
  final int col;

  /// widthEmu API.
  final int widthEmu;

  /// heightEmu API.
  final int heightEmu;

  /// PNG or JPEG bytes.
  final Uint8List bytes;
}

/// Multi-sheet workbook writer with styles, freeze, merges, RTL, and filters.
class XlsxWorkbookBuilder {
  /// XlsxWorkbookBuilder API.
  XlsxWorkbookBuilder({OfficeDocumentTheme? theme})
    : theme = theme ?? const OfficeDocumentTheme();

  /// theme API.
  final OfficeDocumentTheme theme;

  /// sheets API.
  final List<XlsxSheetBuilder> sheets = <XlsxSheetBuilder>[];
  final List<({int id, String code})> _numFmts = <({int id, String code})>[];
  final List<_Xf> _xfs = <_Xf>[_Xf()];
  final List<_Font> _fonts = <_Font>[const _Font()];

  /// none API.
  final List<_Fill> _fills = <_Fill>[const _Fill.none(), const _Fill.gray125()];
  final List<_Border> _borders = <_Border>[
    const _Border.none(),
    const _Border.thin('FFD0D0D8'),
  ];

  /// addSheet API.
  XlsxSheetBuilder addSheet(String name) {
    final XlsxSheetBuilder sheet = XlsxSheetBuilder(
      OfficeMarkup.sheetName(name, sheets.length + 1),
      theme: theme,
    );
    sheets.add(sheet);
    return sheet;
  }

  /// style API.
  int style({
    bool bold = false,
    double size = 11,
    String color = 'FF000000',
    String? fillRgb,
    bool border = false,
    String horizontal = 'left',
    String vertical = 'center',
    bool wrap = false,
    String? numFmt,
    bool rightToLeft = false,
  }) {
    final int fontId = _fontId(
      bold: bold,
      size: size,
      color: OfficeMarkup.rgb(color),
    );
    final int fillId = fillRgb == null ? 0 : _fillId(OfficeMarkup.rgb(fillRgb));
    final int numFmtId = numFmt == null ? 0 : _numFmtId(numFmt);
    final _Xf xf = _Xf(
      fontId: fontId,
      fillId: fillId,
      borderId: border ? 1 : 0,
      numFmtId: numFmtId,
      applyFont: true,
      applyFill: fillRgb != null,
      applyBorder: border,
      applyAlignment: true,
      applyNumFmt: numFmt != null,
      horizontal: horizontal,
      vertical: vertical,
      wrap: wrap,
      rightToLeft: rightToLeft,
    );
    for (int i = 0; i < _xfs.length; i++) {
      if (_xfs[i] == xf) {
        return i;
      }
    }
    _xfs.add(xf);
    return _xfs.length - 1;
  }

  /// build API.
  Uint8List build({String? password}) {
    if (sheets.isEmpty) {
      addSheet('Sheet1');
    }
    final List<String> shared = <String>[];
    final Map<String, int> sharedIndex = <String, int>{};
    int share(String value) {
      final int? existing = sharedIndex[value];
      if (existing != null) {
        return existing;
      }
      final int i = shared.length;
      shared.add(value);
      sharedIndex[value] = i;
      return i;
    }

    final OpcPackage package = OpcPackage.empty();
    package.packageRelationships.add(
      type: RelationshipTypes.officeDocument,
      target: 'xl/workbook.xml',
    );
    final RelationshipCollection wbRels = package.relationshipsFor(
      '/xl/workbook.xml',
    );
    final StringBuffer sheetEls = StringBuffer();
    var drawingCount = 0;
    var chartCount = 0;
    for (int i = 0; i < sheets.length; i++) {
      final int id = i + 1;
      final String uri = '/xl/worksheets/sheet$id.xml';
      String? drawingRid;
      final List<XlsxSheetChart> charts = sheets[i].charts;
      final List<XlsxSheetPicture> pictures = sheets[i].pictures;
      if (charts.isNotEmpty || pictures.isNotEmpty) {
        drawingCount++;
        drawingRid = 'rIdDrawing1';
        final String drawingUri = '/xl/drawings/drawing$drawingCount.xml';
        package
            .relationshipsFor(uri)
            .add(
              type: RelationshipTypes.drawing,
              target: '../drawings/drawing$drawingCount.xml',
              id: drawingRid,
            );
        final RelationshipCollection drawingRels = package.relationshipsFor(
          drawingUri,
        );
        final StringBuffer anchors = StringBuffer();
        for (int k = 0; k < charts.length; k++) {
          chartCount++;
          final XlsxSheetChart chart = charts[k];
          package.createPart(
            '/xl/charts/chart$chartCount.xml',
            OfficeContentTypes.drawingChart,
            utf8.encode(chart.xml),
          );
          drawingRels.add(
            type: RelationshipTypes.chart,
            target: '../charts/chart$chartCount.xml',
            id: 'rIdChart${k + 1}',
          );
          anchors.write(
            '<xdr:oneCellAnchor><xdr:from><xdr:col>${chart.col}</xdr:col>'
            '<xdr:colOff>0</xdr:colOff><xdr:row>${chart.row}</xdr:row>'
            '<xdr:rowOff>0</xdr:rowOff></xdr:from>'
            '<xdr:ext cx="${chart.widthEmu}" cy="${chart.heightEmu}"/>'
            '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
            '<xdr:cNvPr id="${k + 2}" name="Chart ${k + 1}"/>'
            '<xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
            '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
            '<a:graphic><a:graphicData uri="${OfficeNamespaces.c}">'
            '<c:chart xmlns:c="${OfficeNamespaces.c}" r:id="rIdChart${k + 1}"/>'
            '</a:graphicData></a:graphic></xdr:graphicFrame>'
            '<xdr:clientData/></xdr:oneCellAnchor>',
          );
        }
        var imageCount = 0;
        for (int k = 0; k < pictures.length; k++) {
          imageCount++;
          final XlsxSheetPicture picture = pictures[k];
          final bool jpeg =
              picture.bytes.length > 2 &&
              picture.bytes[0] == 0xFF &&
              picture.bytes[1] == 0xD8;
          final String ext = jpeg ? 'jpeg' : 'png';
          final String media = '/xl/media/image$drawingCount$imageCount.$ext';
          package.createPart(
            media,
            jpeg ? 'image/jpeg' : 'image/png',
            picture.bytes,
          );
          final String rel = 'rIdPic$imageCount';
          drawingRels.add(
            type: RelationshipTypes.image,
            target: '../media/image$drawingCount$imageCount.$ext',
            id: rel,
          );
          anchors.write(
            '<xdr:oneCellAnchor><xdr:from><xdr:col>${picture.col}</xdr:col>'
            '<xdr:colOff>0</xdr:colOff><xdr:row>${picture.row}</xdr:row>'
            '<xdr:rowOff>0</xdr:rowOff></xdr:from>'
            '<xdr:ext cx="${picture.widthEmu}" cy="${picture.heightEmu}"/>'
            '<xdr:pic><xdr:nvPicPr>'
            '<xdr:cNvPr id="${charts.length + k + 2}" name="Picture $imageCount"/>'
            '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>'
            '</xdr:nvPicPr><xdr:blipFill><a:blip r:embed="$rel"/>'
            '<a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
            '<xdr:spPr><a:xfrm><a:off x="0" y="0"/>'
            '<a:ext cx="${picture.widthEmu}" cy="${picture.heightEmu}"/>'
            '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
            '</xdr:pic><xdr:clientData/></xdr:oneCellAnchor>',
          );
        }
        package.createPart(
          drawingUri,
          OfficeContentTypes.spreadsheetDrawing,
          utf8.encode(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<xdr:wsDr xmlns:xdr="${OfficeNamespaces.xdr}" '
            'xmlns:a="${OfficeNamespaces.a}" xmlns:r="${OfficeNamespaces.r}">'
            '$anchors</xdr:wsDr>',
          ),
        );
      }
      package.createPart(
        uri,
        OfficeContentTypes.sheetWorksheet,
        utf8.encode(_sheetXml(sheets[i], share, drawingRid: drawingRid)),
      );
      wbRels.add(
        type: RelationshipTypes.worksheet,
        target: 'worksheets/sheet$id.xml',
        id: 'rId$id',
      );
      sheetEls.write(
        '<sheet name="${OfficeMarkup.escapeAttr(sheets[i].name)}" '
        'sheetId="$id" r:id="rId$id"/>',
      );
    }
    final int stylesRid = sheets.length + 1;
    final int sharedRid = sheets.length + 2;
    wbRels
      ..add(
        type: RelationshipTypes.styles,
        target: 'styles.xml',
        id: 'rId$stylesRid',
      )
      ..add(
        type: RelationshipTypes.sharedStrings,
        target: 'sharedStrings.xml',
        id: 'rId$sharedRid',
      );

    package.createPart(
      '/xl/workbook.xml',
      OfficeContentTypes.sheetMain,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="${OfficeNamespaces.x}" '
        'xmlns:r="${OfficeNamespaces.r}">'
        '<sheets>$sheetEls</sheets></workbook>',
      ),
    );
    final StringBuffer sst = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<sst xmlns="${OfficeNamespaces.x}" count="${shared.length}" '
      'uniqueCount="${shared.length}">',
    );
    for (final String s in shared) {
      sst.write(
        '<si><t xml:space="preserve">${OfficeMarkup.escape(s)}</t></si>',
      );
    }
    sst.write('</sst>');
    package.createPart(
      '/xl/sharedStrings.xml',
      OfficeContentTypes.sheetSharedStrings,
      utf8.encode(sst.toString()),
    );
    package.createPart(
      '/xl/styles.xml',
      OfficeContentTypes.sheetStyles,
      utf8.encode(_stylesXml()),
    );
    return package.save(password: password);
  }

  int _fontId({
    required bool bold,
    required double size,
    required String color,
  }) {
    final _Font font = _Font(bold: bold, size: size, color: color);
    for (int i = 0; i < _fonts.length; i++) {
      if (_fonts[i] == font) {
        return i;
      }
    }
    _fonts.add(font);
    return _fonts.length - 1;
  }

  int _fillId(String rgb) {
    final _Fill fill = _Fill.solid(rgb);
    for (int i = 0; i < _fills.length; i++) {
      if (_fills[i] == fill) {
        return i;
      }
    }
    _fills.add(fill);
    return _fills.length - 1;
  }

  int _numFmtId(String code) {
    for (final ({int id, String code}) f in _numFmts) {
      if (f.code == code) {
        return f.id;
      }
    }
    final int id = 164 + _numFmts.length;
    _numFmts.add((id: id, code: code));
    return id;
  }

  /// Function API.
  String _sheetXml(
    XlsxSheetBuilder sheet,
    int Function(String) share, {
    String? drawingRid,
  }) {
    final StringBuffer buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="${OfficeNamespaces.x}"'
      '${drawingRid == null ? '' : ' xmlns:r="${OfficeNamespaces.r}"'}>',
    );
    buf.write('<sheetViews><sheetView workbookViewId="0"');
    if (sheet.rightToLeft) {
      buf.write(' rightToLeft="1"');
    }
    buf.write('>');
    if (sheet.freezeRows > 0 || sheet.freezeCols > 0) {
      final String topLeft =
          '${OfficeMarkup.colName(sheet.freezeCols)}${sheet.freezeRows + 1}';
      buf.write(
        '<pane xSplit="${sheet.freezeCols}" ySplit="${sheet.freezeRows}" '
        'topLeftCell="$topLeft" activePane="bottomRight" state="frozen"/>',
      );
    }
    buf.write('</sheetView></sheetViews>');
    if (sheet.columnWidths.isNotEmpty) {
      buf.write('<cols>');
      for (final ({int min, int max, double width}) c in sheet.columnWidths) {
        buf.write(
          '<col min="${c.min}" max="${c.max}" width="${c.width}" customWidth="1"/>',
        );
      }
      buf.write('</cols>');
    }
    buf.write('<sheetData>');
    for (int r = 0; r < sheet.rows.length; r++) {
      final List<XlsxCell?> row = sheet.rows[r];
      final double? ht = sheet.rowHeights[r];
      buf.write('<row r="${r + 1}"');
      if (ht != null) {
        buf.write(' ht="$ht" customHeight="1"');
      }
      buf.write('>');
      for (int c = 0; c < row.length; c++) {
        final XlsxCell? cell = row[c];
        if (cell == null || cell.value == null) {
          continue;
        }
        final String ref = '${OfficeMarkup.colName(c)}${r + 1}';
        final String styleAttr = cell.style > 0 ? ' s="${cell.style}"' : '';
        final Object value = cell.value!;
        if (value is num) {
          buf.write('<c r="$ref"$styleAttr><v>$value</v></c>');
        } else if (value is bool) {
          buf.write('<c r="$ref"$styleAttr t="b"><v>${value ? 1 : 0}</v></c>');
        } else {
          buf.write(
            '<c r="$ref"$styleAttr t="s"><v>${share(value.toString())}</v></c>',
          );
        }
      }
      buf.write('</row>');
    }
    buf.write('</sheetData>');
    if (sheet.autoFilterRef != null) {
      buf.write('<autoFilter ref="${sheet.autoFilterRef}"/>');
    }
    if (sheet.merges.isNotEmpty) {
      buf.write('<mergeCells count="${sheet.merges.length}">');
      for (final ({int r1, int c1, int r2, int c2}) m in sheet.merges) {
        buf.write(
          '<mergeCell ref="${OfficeMarkup.colName(m.c1)}${m.r1 + 1}:'
          '${OfficeMarkup.colName(m.c2)}${m.r2 + 1}"/>',
        );
      }
      buf.write('</mergeCells>');
    }
    if (sheet.oddHeader != null || sheet.oddFooter != null) {
      buf.write('<headerFooter>');
      final String? header = sheet.oddHeader;
      final String? footer = sheet.oddFooter;
      if (header != null) {
        buf.write(
          '<oddHeader>&amp;L${OfficeMarkup.escape(header)}</oddHeader>',
        );
      }
      if (footer != null) {
        buf.write(
          '<oddFooter>&amp;L${OfficeMarkup.escape(footer)}</oddFooter>',
        );
      }
      buf.write('</headerFooter>');
    }
    if (drawingRid != null) {
      buf.write('<drawing r:id="$drawingRid"/>');
    }
    buf.write('</worksheet>');
    return buf.toString();
  }

  String _stylesXml() {
    final StringBuffer buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="${OfficeNamespaces.x}">',
    );
    if (_numFmts.isNotEmpty) {
      buf.write('<numFmts count="${_numFmts.length}">');
      for (final ({int id, String code}) f in _numFmts) {
        buf.write(
          '<numFmt numFmtId="${f.id}" formatCode="${OfficeMarkup.escapeAttr(f.code)}"/>',
        );
      }
      buf.write('</numFmts>');
    }
    buf.write('<fonts count="${_fonts.length}">');
    for (final _Font f in _fonts) {
      buf.write(
        '<font>${f.bold ? '<b/>' : ''}<sz val="${f.size}"/>'
        '<color rgb="${f.color}"/><name val="${OfficeMarkup.escapeAttr(theme.fontFamily)}"/></font>',
      );
    }
    buf.write('</fonts><fills count="${_fills.length}">');
    for (final _Fill f in _fills) {
      if (f.pattern == 'none') {
        buf.write('<fill><patternFill patternType="none"/></fill>');
      } else if (f.pattern == 'gray125') {
        buf.write('<fill><patternFill patternType="gray125"/></fill>');
      } else {
        buf.write(
          '<fill><patternFill patternType="solid">'
          '<fgColor rgb="${f.rgb}"/></patternFill></fill>',
        );
      }
    }
    buf.write('</fills><borders count="${_borders.length}">');
    for (final _Border b in _borders) {
      if (b.thin) {
        buf.write(
          '<border><left style="thin"><color rgb="${b.color}"/></left>'
          '<right style="thin"><color rgb="${b.color}"/></right>'
          '<top style="thin"><color rgb="${b.color}"/></top>'
          '<bottom style="thin"><color rgb="${b.color}"/></bottom>'
          '<diagonal/></border>',
        );
      } else {
        buf.write('<border><left/><right/><top/><bottom/><diagonal/></border>');
      }
    }
    buf.write(
      '</borders><cellStyleXfs count="1">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="${_xfs.length}">',
    );
    for (final _Xf xf in _xfs) {
      buf.write(
        '<xf numFmtId="${xf.numFmtId}" fontId="${xf.fontId}" fillId="${xf.fillId}" '
        'borderId="${xf.borderId}" xfId="0"'
        '${xf.applyFont ? ' applyFont="1"' : ''}'
        '${xf.applyFill ? ' applyFill="1"' : ''}'
        '${xf.applyBorder ? ' applyBorder="1"' : ''}'
        '${xf.applyAlignment ? ' applyAlignment="1"' : ''}'
        '${xf.applyNumFmt ? ' applyNumberFormat="1"' : ''}>',
      );
      if (xf.applyAlignment) {
        buf.write(
          '<alignment horizontal="${xf.horizontal}" vertical="${xf.vertical}"'
          '${xf.wrap ? ' wrapText="1"' : ''}'
          '${xf.rightToLeft ? ' readingOrder="2"' : ''}/>',
        );
      }
      buf.write('</xf>');
    }
    buf.write('</cellXfs></styleSheet>');
    return buf.toString();
  }
}

class _Font {
  /// bold API.
  const _Font({this.bold = false, this.size = 11, this.color = 'FF000000'});

  /// bold API.
  final bool bold;

  /// size API.
  final double size;

  /// color API.
  final String color;

  @override
  bool operator ==(Object other) =>
      other is _Font &&
      other.bold == bold &&
      other.size == size &&
      other.color == color;

  @override
  /// hashCode API.
  int get hashCode => Object.hash(bold, size, color);
}

class _Fill {
  const _Fill._(this.pattern, this.rgb);

  /// none API.
  const _Fill.none() : this._('none', '');

  /// gray125 API.
  const _Fill.gray125() : this._('gray125', '');

  /// solid API.
  const _Fill.solid(String rgb) : this._('solid', rgb);

  /// pattern API.
  final String pattern;

  /// rgb API.
  final String rgb;

  @override
  bool operator ==(Object other) =>
      other is _Fill && other.pattern == pattern && other.rgb == rgb;

  @override
  /// hashCode API.
  int get hashCode => Object.hash(pattern, rgb);
}

class _Border {
  const _Border._(this.thin, this.color);

  /// none API.
  const _Border.none() : this._(false, '');

  /// thin API.
  const _Border.thin(String color) : this._(true, color);

  /// thin API.
  final bool thin;

  /// color API.
  final String color;
}

class _Xf {
  const _Xf({
    this.fontId = 0,
    this.fillId = 0,
    this.borderId = 0,
    this.numFmtId = 0,
    this.applyFont = false,
    this.applyFill = false,
    this.applyBorder = false,
    this.applyAlignment = false,
    this.applyNumFmt = false,
    this.horizontal = 'left',
    this.vertical = 'center',
    this.wrap = false,
    this.rightToLeft = false,
  });

  /// fontId API.
  final int fontId;

  /// fillId API.
  final int fillId;

  /// borderId API.
  final int borderId;

  /// numFmtId API.
  final int numFmtId;

  /// applyFont API.
  final bool applyFont;

  /// applyFill API.
  final bool applyFill;

  /// applyBorder API.
  final bool applyBorder;

  /// applyAlignment API.
  final bool applyAlignment;

  /// applyNumFmt API.
  final bool applyNumFmt;

  /// horizontal API.
  final String horizontal;

  /// vertical API.
  final String vertical;

  /// wrap API.
  final bool wrap;

  /// rightToLeft API (alignment `readingOrder="2"`).
  final bool rightToLeft;

  @override
  bool operator ==(Object other) =>
      other is _Xf &&
      other.fontId == fontId &&
      other.fillId == fillId &&
      other.borderId == borderId &&
      other.numFmtId == numFmtId &&
      other.applyFont == applyFont &&
      other.applyFill == applyFill &&
      other.applyBorder == applyBorder &&
      other.applyAlignment == applyAlignment &&
      other.applyNumFmt == applyNumFmt &&
      other.horizontal == horizontal &&
      other.vertical == vertical &&
      other.wrap == wrap &&
      other.rightToLeft == rightToLeft;

  @override
  /// hashCode API.
  int get hashCode => Object.hash(
    fontId,
    fillId,
    borderId,
    numFmtId,
    applyFont,
    applyFill,
    applyBorder,
    applyAlignment,
    applyNumFmt,
    horizontal,
    vertical,
    wrap,
    rightToLeft,
  );
}
