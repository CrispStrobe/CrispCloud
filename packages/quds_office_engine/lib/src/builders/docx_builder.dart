import 'dart:convert';
import 'dart:typed_data';

import '../opc/content_types.dart';
import '../opc/opc_archive.dart';
import '../opc/package_part.dart';
import '../opc/relationships.dart';
import '../xml/namespaces.dart';
import '../xml/xml_reader.dart';
import 'drawingml_charts.dart';
import 'image_fit.dart';
import 'office_document_theme.dart';
import 'office_markup.dart';

/// Class DocxHyperlink.
class DocxHyperlink {
  /// DocxHyperlink API.
  const DocxHyperlink({required this.text, required this.url});

  /// text API.
  final String text;

  /// url API.
  final String url;
}

/// Extracts plain paragraphs, tables, and hyperlinks from a `.docx` package.
abstract final class DocxPlainReader {
  /// paragraphs API.
  static String paragraphs(Uint8List bytes, {String? password}) {
    return read(bytes, password: password).paragraphs.join('\n');
  }

  static ({
    List<String> paragraphs,
    List<List<List<String>>> tables,
    List<DocxHyperlink> hyperlinks,
  })
  /// read API.
  read(Uint8List bytes, {String? password}) {
    final OpcPackage package = OpcPackage.openBytes(bytes, password: password);
    final PackagePart? part = package.getPart('/word/document.xml');
    if (part == null) {
      return (
        paragraphs: <String>[],
        tables: <List<List<String>>>[],
        hyperlinks: <DocxHyperlink>[],
      );
    }
    final Map<String, String> linkTargets = <String, String>{};
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    for (final PackageRelationship rel in rels.byType(
      RelationshipTypes.hyperlink,
    )) {
      linkTargets[rel.id] = rel.target;
    }
    final List<String> paragraphs = <String>[];
    final List<List<List<String>>> tables = <List<List<String>>>[];
    final List<DocxHyperlink> hyperlinks = <DocxHyperlink>[];
    final XmlPullReader reader = XmlPullReader(part.readText());
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'tbl') {
        tables.add(_readTable(reader));
      } else if (reader.localName == 'p') {
        final ({String text, List<DocxHyperlink> links}) para = _readParagraph(
          reader,
          linkTargets,
        );
        if (para.text.trim().isNotEmpty) {
          paragraphs.add(para.text);
        }
        hyperlinks.addAll(para.links);
      }
    }
    return (paragraphs: paragraphs, tables: tables, hyperlinks: hyperlinks);
  }

  static List<List<String>> _readTable(XmlPullReader reader) {
    final List<List<String>> rows = <List<String>>[];
    if (reader.isEmptyElement) {
      return rows;
    }
    final int depth = reader.depth;
    List<String>? currentRow;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if (reader.localName == 'tr') {
        currentRow = <String>[];
        rows.add(currentRow);
      } else if (reader.localName == 'tc' && currentRow != null) {
        currentRow.add(_readPlain(reader));
      }
    }
    return rows;
  }

  static ({String text, List<DocxHyperlink> links}) _readParagraph(
    XmlPullReader reader,
    Map<String, String> linkTargets,
  ) {
    if (reader.isEmptyElement) {
      return (text: '', links: <DocxHyperlink>[]);
    }
    final StringBuffer buffer = StringBuffer();
    final List<DocxHyperlink> links = <DocxHyperlink>[];
    final int depth = reader.depth;
    String? linkRid;
    final StringBuffer linkText = StringBuffer();
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.startElement &&
          reader.localName == 'hyperlink') {
        linkRid =
            reader.getAttribute('id', namespaceUri: OfficeNamespaces.r) ??
            reader.getAttribute('id');
        linkText.clear();
      } else if (reader.eventType == XmlEventType.characters) {
        buffer.write(reader.text);
        if (linkRid != null) {
          linkText.write(reader.text);
        }
      } else if (reader.eventType == XmlEventType.endElement &&
          reader.localName == 'hyperlink') {
        final String? url = linkRid == null ? null : linkTargets[linkRid];
        final String text = linkText.toString();
        if (text.trim().isNotEmpty && url != null && url.isNotEmpty) {
          links.add(DocxHyperlink(text: text, url: url));
        }
        linkRid = null;
      }
    }
    return (text: buffer.toString(), links: links);
  }

  static String _readPlain(XmlPullReader reader) {
    return _readParagraph(reader, const <String, String>{}).text;
  }
}

/// Class DocxHeaderFooter.
class DocxHeaderFooter {
  /// DocxHeaderFooter API.
  const DocxHeaderFooter({
    this.left,
    this.center,
    this.right,
    this.pageNumber = false,
    this.date = false,
  });

  /// left API.
  final String? left;

  /// center API.
  final String? center;

  /// right API.
  final String? right;

  /// pageNumber API.
  final bool pageNumber;

  /// date API.
  final bool date;
}

/// Fluent Word builder: headings, lists, RTL tables, images, charts, comments.
class DocxDocumentBuilder {
  /// DocxDocumentBuilder API.
  DocxDocumentBuilder({bool? rtl, OfficeDocumentTheme? theme})
    : theme = theme ?? OfficeDocumentTheme.light(rtl: rtl ?? false),
      rtl = rtl ?? theme?.rtl ?? false;

  /// rtl API.
  final bool rtl;

  /// theme API.
  final OfficeDocumentTheme theme;
  final List<String> _body = <String>[];
  final List<({String name, Uint8List bytes, String mime})> _images =
      <({String name, Uint8List bytes, String mime})>[];
  final List<({int id, String xml})> _charts = <({int id, String xml})>[];
  final List<String> _comments = <String>[];
  final List<({String id, String url})> _hyperlinks =
      <({String id, String url})>[];
  DocxHeaderFooter? _header;
  DocxHeaderFooter? _footer;
  var _imageSeq = 0;
  var _chartSeq = 0;
  var _docPrSeq = 0;
  var _numInstance = 2;
  var _bookmarkSeq = 0;
  var _linkSeq = 0;

  /// palette API.
  OfficePalette get _colors => theme.palette;

  /// heading API.
  void heading(String text, {int level = 1}) {
    final int size = switch (level) {
      1 => 32,
      2 => 26,
      _ => 22,
    };
    _body.add(
      _paragraphXml(
        text,
        bold: true,
        fontSizeHalfPoints: size,
        spacingAfter: 120,
        spacingBefore: level == 1 ? 0 : 200,
        colorHex: level == 1 ? _colors.primary : null,
        styleId: 'Heading${level.clamp(1, 9)}',
        outlineLevel: level.clamp(1, 9),
      ),
    );
  }

  /// paragraph API.
  void paragraph(
    String text, {
    bool bold = false,
    bool italic = false,
    int fontSizeHalfPoints = 20,
    String? colorHex,
    List<String> comments = const <String>[],
  }) {
    _body.add(
      _paragraphXml(
        text,
        bold: bold,
        italic: italic,
        fontSizeHalfPoints: fontSizeHalfPoints,
        colorHex: colorHex,
        commentIds: _addComments(comments),
      ),
    );
  }

  /// note API.
  void note(String text) {
    _body.add(
      _paragraphXml(
        text,
        italic: true,
        fontSizeHalfPoints: 18,
        colorHex: _colors.muted,
        spacingAfter: 80,
      ),
    );
  }

  /// caption API.
  void caption(String text) {
    _body.add(
      _paragraphXml(
        text,
        italic: true,
        fontSizeHalfPoints: 16,
        colorHex: _colors.muted,
        spacingBefore: 40,
        spacingAfter: 160,
      ),
    );
  }

  /// spacer API.
  void spacer({int heightTwips = 240}) {
    _body.add(
      '<w:p><w:pPr><w:spacing w:before="0" w:after="$heightTwips"/>'
      '$_bidiEl<w:jc w:val="$_jc"/>$_markRpr</w:pPr></w:p>',
    );
  }

  /// hyperlink API.
  void hyperlink(String text, String url) {
    _linkSeq += 1;
    final String id = 'rIdLink$_linkSeq';
    _hyperlinks.add((id: id, url: url));
    _body.add(
      '<w:p>$_pPrOpen$_pPrClose<w:hyperlink r:id="$id" w:history="1">'
      '<w:r>${_runProperties(colorHex: '0563C1', underline: true)}'
      '<w:t xml:space="preserve">${OfficeMarkup.escape(text)}</w:t></w:r>'
      '</w:hyperlink></w:p>',
    );
  }

  /// bookmark API.
  void bookmark(String name) {
    _bookmarkSeq += 1;
    final String safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    _body.add(
      '<w:bookmarkStart w:id="$_bookmarkSeq" w:name="${OfficeMarkup.escapeAttr(safe)}"/>'
      '<w:bookmarkEnd w:id="$_bookmarkSeq"/>',
    );
  }

  /// header API.
  void header({
    String? left,
    String? center,
    String? right,
    bool pageNumber = false,
    bool date = false,
  }) {
    _header = DocxHeaderFooter(
      left: left,
      center: center,
      right: right,
      pageNumber: pageNumber,
      date: date,
    );
  }

  /// footer API.
  void footer({
    String? left,
    String? center,
    String? right,
    bool pageNumber = true,
    bool date = false,
  }) {
    _footer = DocxHeaderFooter(
      left: left,
      center: center,
      right: right,
      pageNumber: pageNumber,
      date: date,
    );
  }

  /// bulletList API.
  void bulletList(List<String> items) {
    _list(items, numId: 1);
  }

  /// numberedList API.
  void numberedList(List<String> items, {int start = 1}) {
    _numInstance += 1;
    _list(items, numId: _numInstance, start: start);
  }

  /// table API.
  void table(
    List<List<String>> rows, {
    bool hasHeader = true,
    String? headerFillHex,
    bool headerWhiteText = true,
    List<int>? colWidths,
    String cellAlign = 'left',
  }) {
    if (rows.isEmpty) {
      return;
    }
    final int colCount = rows.fold<int>(
      0,
      (int a, List<String> r) => a > r.length ? a : r.length,
    );
    if (colCount == 0) {
      return;
    }
    final List<int> widths = <int>[
      for (int i = 0; i < colCount; i++)
        colWidths != null && i < colWidths.length
            ? colWidths[i]
            : (9000 / colCount).round(),
    ];
    final int tableW = widths.fold<int>(0, (int a, int b) => a + b);
    final String headerFill = headerFillHex ?? _colors.tableHeader;
    final StringBuffer buf = StringBuffer()
      ..write('<w:tbl><w:tblPr><w:tblW w:w="$tableW" w:type="dxa"/>')
      ..write(rtl ? '<w:bidiVisual/>' : '')
      ..write(
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>'
        '</w:tblBorders></w:tblPr><w:tblGrid>',
      );
    for (int i = 0; i < colCount; i++) {
      buf.write('<w:gridCol w:w="${widths[i]}"/>');
    }
    buf.write('</w:tblGrid>');
    final String align = rtl && cellAlign == 'left' ? 'right' : cellAlign;
    for (int r = 0; r < rows.length; r++) {
      final bool header = hasHeader && r == 0;
      buf.write('<w:tr>');
      for (int c = 0; c < colCount; c++) {
        final String text = c < rows[r].length ? rows[r][c] : '';
        final String fill = header
            ? headerFill
            : (r.isOdd ? _colors.tableBand : _colors.surface);
        buf.write(
          '<w:tc><w:tcPr><w:tcW w:w="${widths[c]}" w:type="dxa"/>'
          '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/></w:tcPr>'
          '${_paragraphXml(text, bold: header, fontSizeHalfPoints: header ? 20 : 18, colorHex: header && headerWhiteText ? _colors.onPrimary : null, align: align)}'
          '</w:tc>',
        );
      }
      buf.write('</w:tr>');
    }
    buf.write('</w:tbl>');
    _body.add(buf.toString());
  }

  /// pageBreak API.
  void pageBreak() {
    _body.add('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
  }

  /// horizontalRule API.
  void horizontalRule({String? colorHex}) {
    final String color = colorHex ?? _colors.rule;
    _body.add(
      '<w:p><w:pPr><w:spacing w:before="80" w:after="120"/>$_bidiEl'
      '<w:jc w:val="$_jc"/>$_markRpr'
      '<w:pBdr><w:bottom w:val="single" w:sz="12" w:space="1" '
      'w:color="${OfficeMarkup.srgb(color)}"/></w:pBdr></w:pPr></w:p>',
    );
  }

  /// image API.
  void image(
    Uint8List bytes, {
    String name = 'image.png',
    int? widthPx,
    int? heightPx,
    int? maxWidthPx,
    String mime = 'image/png',
    String? caption,
  }) {
    if (bytes.isEmpty) {
      return;
    }
    final ImageSize? intrinsic = ImageFit.readSize(bytes);
    final ({int widthPx, int heightPx}) fitted = ImageFit.fitPixels(
      srcWidthPx: intrinsic?.widthPx ?? widthPx ?? 480,
      srcHeightPx: intrinsic?.heightPx ?? heightPx ?? 320,
      maxWidthPx: maxWidthPx ?? widthPx,
      maxHeightPx: heightPx,
      fallbackWidthPx: widthPx ?? 480,
      fallbackHeightPx: heightPx ?? 320,
    );
    _imageSeq += 1;
    final String file = 'image$_imageSeq${_ext(mime, name)}';
    _images.add((name: file, bytes: bytes, mime: mime));
    final int cx = fitted.widthPx * ImageFit.emuPerPx;
    final int cy = fitted.heightPx * ImageFit.emuPerPx;
    final int docPrId = ++_docPrSeq;
    _body.add(
      '<w:p>$_pPrOpen$_pPrClose<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$docPrId" name="${OfficeMarkup.escapeAttr(name)}"/>'
      '<a:graphic xmlns:a="${OfficeNamespaces.a}">'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:nvPicPr><pic:cNvPr id="0" name="${OfficeMarkup.escapeAttr(name)}"/>'
      '<pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rIdImg$_imageSeq"/>'
      '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
    if (caption != null && caption.isNotEmpty) {
      this.caption(caption);
    }
  }

  /// pieChart API.
  void pieChart({
    required String title,
    required List<ChartPoint> series,
    int widthPx = 480,
    int heightPx = 300,
  }) {
    _addChart(
      DrawingmlCharts.pie(
        title: title,
        series: series,
        rtl: rtl,
        titleColor: _colors.primary,
        theme: theme,
      ),
      title: title,
      widthPx: widthPx,
      heightPx: heightPx,
    );
  }

  /// barChart API.
  void barChart({
    required String title,
    required List<ChartPoint> series,
    bool horizontal = true,
    int widthPx = 480,
    int heightPx = 300,
  }) {
    _addChart(
      DrawingmlCharts.bar(
        title: title,
        series: series,
        rtl: rtl,
        horizontal: horizontal,
        titleColor: _colors.primary,
        theme: theme,
      ),
      title: title,
      widthPx: widthPx,
      heightPx: heightPx,
    );
  }

  /// lineChart API.
  void lineChart({
    required String title,
    required List<ChartSeries> series,
    bool markers = true,
    int widthPx = 480,
    int heightPx = 300,
  }) {
    _addChart(
      DrawingmlCharts.line(
        title: title,
        series: series,
        rtl: rtl,
        markers: markers,
        titleColor: _colors.primary,
        theme: theme,
      ),
      title: title,
      widthPx: widthPx,
      heightPx: heightPx,
    );
  }

  /// stackedBarChart API.
  void stackedBarChart({
    required String title,
    required List<ChartSeries> series,
    bool horizontal = false,
    int widthPx = 480,
    int heightPx = 300,
  }) {
    _addChart(
      DrawingmlCharts.stackedBar(
        title: title,
        series: series,
        rtl: rtl,
        horizontal: horizontal,
        titleColor: _colors.primary,
        theme: theme,
      ),
      title: title,
      widthPx: widthPx,
      heightPx: heightPx,
    );
  }

  /// build API.
  Uint8List build({String? password}) {
    final OpcPackage package = OpcPackage.empty();
    package.packageRelationships.add(
      type: RelationshipTypes.officeDocument,
      target: 'word/document.xml',
    );
    package.createPart(
      '/word/document.xml',
      OfficeContentTypes.wordMain,
      utf8.encode(_documentXml()),
    );
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      utf8.encode(_stylesXml()),
    );
    package.createPart(
      '/word/settings.xml',
      OfficeContentTypes.wordSettings,
      utf8.encode(_settingsXml()),
    );
    package.createPart(
      '/word/numbering.xml',
      OfficeContentTypes.wordNumbering,
      utf8.encode(_numberingXml()),
    );
    final RelationshipCollection rels = package.relationshipsFor(
      '/word/document.xml',
    );
    rels
      ..add(
        type: RelationshipTypes.styles,
        target: 'styles.xml',
        id: 'rIdStyles',
      )
      ..add(
        type: RelationshipTypes.settings,
        target: 'settings.xml',
        id: 'rIdSettings',
      )
      ..add(
        type: RelationshipTypes.numbering,
        target: 'numbering.xml',
        id: 'rIdNumbering',
      );
    if (_header != null) {
      package.createPart(
        '/word/header1.xml',
        OfficeContentTypes.wordHeader,
        utf8.encode(_hfXml(_header!, isHeader: true)),
      );
      rels.add(
        type: RelationshipTypes.header,
        target: 'header1.xml',
        id: 'rIdHeader',
      );
    }
    if (_footer != null) {
      package.createPart(
        '/word/footer1.xml',
        OfficeContentTypes.wordFooter,
        utf8.encode(_hfXml(_footer!, isHeader: false)),
      );
      rels.add(
        type: RelationshipTypes.footer,
        target: 'footer1.xml',
        id: 'rIdFooter',
      );
    }
    if (_comments.isNotEmpty) {
      package.createPart(
        '/word/comments.xml',
        OfficeContentTypes.wordComments,
        utf8.encode(_commentsXml()),
      );
      rels.add(
        type: RelationshipTypes.comments,
        target: 'comments.xml',
        id: 'rIdComments',
      );
    }
    for (final ({String id, String url}) link in _hyperlinks) {
      rels.add(
        type: RelationshipTypes.hyperlink,
        target: link.url,
        id: link.id,
        targetMode: RelationshipTargetMode.external,
      );
    }
    for (int i = 0; i < _images.length; i++) {
      final ({String name, Uint8List bytes, String mime}) img = _images[i];
      package.createPart('/word/media/${img.name}', img.mime, img.bytes);
      rels.add(
        type: RelationshipTypes.image,
        target: 'media/${img.name}',
        id: 'rIdImg${i + 1}',
      );
    }
    for (final ({int id, String xml}) chart in _charts) {
      package.createPart(
        '/word/charts/chart${chart.id}.xml',
        OfficeContentTypes.drawingChart,
        utf8.encode(chart.xml),
      );
      rels.add(
        type: RelationshipTypes.chart,
        target: 'charts/chart${chart.id}.xml',
        id: 'rIdChart${chart.id}',
      );
    }
    return package.save(password: password);
  }

  final Map<int, int> _listStarts = <int, int>{};

  /// start API.
  void _list(List<String> items, {required int numId, int start = 1}) {
    if (start != 1) {
      _listStarts[numId] = start;
    }
    for (final String item in items) {
      if (item.trim().isEmpty) {
        continue;
      }
      _body.add(
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="$numId"/>'
        '</w:numPr>$_bidiEl<w:jc w:val="$_jc"/>$_markRpr</w:pPr>'
        '<w:r>${_runProperties()}<w:t xml:space="preserve">${OfficeMarkup.escape(item)}</w:t></w:r></w:p>',
      );
    }
  }

  List<int> _addComments(List<String> texts) {
    final List<int> ids = <int>[];
    for (final String t in texts) {
      if (t.trim().isEmpty) {
        continue;
      }
      ids.add(_comments.length);
      _comments.add(t);
    }
    return ids;
  }

  void _addChart(
    String xml, {
    required String title,
    required int widthPx,
    required int heightPx,
  }) {
    if (!xml.contains('<c:pt ')) {
      return;
    }
    _chartSeq += 1;
    _charts.add((id: _chartSeq, xml: xml));
    final int cx = widthPx * 9525;
    final int cy = heightPx * 9525;
    final int docPrId = ++_docPrSeq;
    _body.add(
      '<w:p>$_pPrOpen$_pPrClose<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$docPrId" name="${OfficeMarkup.escapeAttr(title)}"/>'
      '<a:graphic xmlns:a="${OfficeNamespaces.a}">'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
      '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
      'xmlns:r="${OfficeNamespaces.r}" r:id="rIdChart$_chartSeq"/>'
      '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
  }

  String get _jc => rtl ? 'right' : 'left';
  String get _bidiEl => rtl ? '<w:bidi/>' : '';
  String get _rtlEl => rtl ? '<w:rtl/>' : '';
  String get _langEl => rtl
      ? '<w:lang w:val="ar-SA" w:eastAsia="en-US" w:bidi="ar-SA"/>'
      : '<w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>';
  String get _rFonts {
    final String face = theme.fontFamily;
    return '<w:rFonts w:ascii="$face" w:hAnsi="$face" w:cs="$face" w:eastAsia="$face"'
        '${rtl ? ' w:hint="cs"' : ''}/>';
  }

  String get _markRpr => '<w:rPr>$_rtlEl$_langEl$_rFonts</w:rPr>';
  String get _pPrOpen =>
      '<w:pPr><w:spacing w:before="0" w:after="80"/>$_bidiEl<w:jc w:val="$_jc"/>$_markRpr';
  String get _pPrClose => '</w:pPr>';

  String _runProperties({
    bool bold = false,
    bool italic = false,
    bool underline = false,
    int fontSizeHalfPoints = 20,
    String? colorHex,
  }) {
    return '<w:rPr>$_rtlEl$_langEl'
        '${bold ? '<w:b/><w:bCs/>' : ''}'
        '${italic ? '<w:i/><w:iCs/>' : ''}'
        '${underline ? '<w:u w:val="single"/>' : ''}'
        '${colorHex == null ? '' : '<w:color w:val="${OfficeMarkup.srgb(colorHex)}"/>'}'
        '<w:sz w:val="$fontSizeHalfPoints"/><w:szCs w:val="$fontSizeHalfPoints"/>'
        '$_rFonts</w:rPr>';
  }

  String _paragraphXml(
    String text, {
    bool bold = false,
    bool italic = false,
    int fontSizeHalfPoints = 20,
    int spacingAfter = 80,
    int spacingBefore = 0,
    String? colorHex,
    String? align,
    List<int> commentIds = const <int>[],
    String? styleId,
    int? outlineLevel,
  }) {
    final StringBuffer comments = StringBuffer();
    for (final int id in commentIds) {
      comments.write('<w:commentRangeStart w:id="$id"/>');
    }
    final StringBuffer ends = StringBuffer();
    for (final int id in commentIds) {
      ends.write(
        '<w:commentRangeEnd w:id="$id"/><w:r><w:rPr><w:rStyle w:val="CommentReference"/>'
        '</w:rPr><w:commentReference w:id="$id"/></w:r>',
      );
    }
    final String jc = align ?? _jc;
    final String style = styleId == null
        ? ''
        : '<w:pStyle w:val="${OfficeMarkup.escape(styleId)}"/>';
    final String outline = outlineLevel == null
        ? ''
        : '<w:outlineLvl w:val="${outlineLevel - 1}"/>';
    return '<w:p><w:pPr>$style$outline<w:spacing w:before="$spacingBefore" w:after="$spacingAfter"/>'
        '$_bidiEl<w:jc w:val="$jc"/>$_markRpr</w:pPr>$comments'
        '<w:r>${_runProperties(bold: bold, italic: italic, fontSizeHalfPoints: fontSizeHalfPoints, colorHex: colorHex)}'
        '<w:t xml:space="preserve">${OfficeMarkup.escape(text)}</w:t></w:r>$ends</w:p>';
  }

  String _documentXml() {
    final StringBuffer sect = StringBuffer(
      '<w:sectPr><w:pgSz w:w="${theme.page.widthTwips}" w:h="${theme.page.heightTwips}"/>'
      '<w:pgMar w:top="${theme.margins.topTwips}" w:right="${theme.margins.rightTwips}" '
      'w:bottom="${theme.margins.bottomTwips}" w:left="${theme.margins.leftTwips}" '
      'w:header="${theme.margins.headerTwips}" w:footer="${theme.margins.footerTwips}" '
      'w:gutter="0"/>',
    );
    if (_header != null) {
      sect.write('<w:headerReference w:type="default" r:id="rIdHeader"/>');
    }
    if (_footer != null) {
      sect.write('<w:footerReference w:type="default" r:id="rIdFooter"/>');
    }
    sect.write('${rtl ? '<w:bidi/><w:rtlGutter/>' : ''}</w:sectPr>');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}" '
        'xmlns:wp="${OfficeNamespaces.wp}" xmlns:a="${OfficeNamespaces.a}" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
        'xmlns:c="${OfficeNamespaces.c}">'
        '<w:body>${_body.join()}$sect</w:body></w:document>';
  }

  String _hfXml(DocxHeaderFooter spec, {required bool isHeader}) {
    final String tag = isHeader ? 'hdr' : 'ftr';
    String slot(
      String? text,
      String align, {
      bool page = false,
      bool date = false,
    }) {
      final StringBuffer runs = StringBuffer();
      if (text != null && text.isNotEmpty) {
        runs.write(
          '<w:r>${_runProperties(fontSizeHalfPoints: 16, colorHex: _colors.muted)}'
          '<w:t xml:space="preserve">${OfficeMarkup.escape(text)}</w:t></w:r>',
        );
      }
      if (date) {
        runs.write(
          '<w:r>${_runProperties(fontSizeHalfPoints: 16)}'
          '<w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r>${_runProperties(fontSizeHalfPoints: 16)}'
          '<w:instrText xml:space="preserve"> DATE \\@ "yyyy-MM-dd" </w:instrText></w:r>'
          '<w:r>${_runProperties(fontSizeHalfPoints: 16)}'
          '<w:fldChar w:fldCharType="end"/></w:r>',
        );
      }
      if (page) {
        runs.write(
          '<w:r>${_runProperties(fontSizeHalfPoints: 16)}'
          '<w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r>${_runProperties(fontSizeHalfPoints: 16)}'
          '<w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
          '<w:r>${_runProperties(fontSizeHalfPoints: 16)}'
          '<w:fldChar w:fldCharType="end"/></w:r>',
        );
      }
      if (runs.isEmpty) {
        return '';
      }
      return '<w:p><w:pPr><w:jc w:val="$align"/>$_markRpr</w:pPr>$runs</w:p>';
    }

    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:$tag xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}">'
        '${slot(spec.left, rtl ? 'right' : 'left')}'
        '${slot(spec.center, 'center', date: spec.date)}'
        '${slot(spec.right, rtl ? 'left' : 'right', page: spec.pageNumber)}'
        '</w:$tag>';
  }

  String _stylesXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="${OfficeNamespaces.w}">'
        '<w:docDefaults><w:rPrDefault><w:rPr>$_rtlEl$_langEl$_rFonts'
        '<w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr>$_bidiEl<w:jc w:val="$_jc"/>$_markRpr</w:pPr></w:pPrDefault>'
        '</w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/><w:qFormat/>'
        '<w:pPr>$_bidiEl<w:jc w:val="$_jc"/>$_markRpr</w:pPr>'
        '<w:rPr>$_rtlEl$_langEl</w:rPr></w:style></w:styles>';
  }

  String _settingsXml() {
    final String lang = rtl ? 'ar-SA' : 'en-US';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:settings xmlns:w="${OfficeNamespaces.w}">'
        '<w:view w:val="print"/><w:zoom w:percent="100"/>'
        '<w:defaultTabStop w:val="720"/>'
        '<w:themeFontLang w:val="$lang" w:eastAsia="en-US" w:bidi="ar-SA"/>'
        '<w:compat><w:compatSetting w:name="compatibilityMode" '
        'w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
        '</w:settings>';
  }

  String _numberingXml() {
    final StringBuffer abstracts = StringBuffer();
    final StringBuffer nums = StringBuffer();
    for (int id = 3; id <= _numInstance; id++) {
      final int start = _listStarts[id] ?? 1;
      final int absId = id;
      abstracts.write(
        '<w:abstractNum w:abstractNumId="$absId"><w:multiLevelType w:val="hybridMultilevel"/>'
        '<w:lvl w:ilvl="0"><w:start w:val="$start"/><w:numFmt w:val="decimal"/>'
        '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/></w:lvl></w:abstractNum>',
      );
      nums.write(
        '<w:num w:numId="$id"><w:abstractNumId w:val="$absId"/></w:num>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:numbering xmlns:w="${OfficeNamespaces.w}">'
        '<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>'
        '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
        '<w:lvlText w:val="•"/><w:lvlJc w:val="left"/></w:lvl></w:abstractNum>'
        '<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>'
        '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
        '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/></w:lvl></w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
        '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
        '$abstracts$nums</w:numbering>';
  }

  String _commentsXml() {
    final StringBuffer buf = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:comments xmlns:w="${OfficeNamespaces.w}">',
    );
    for (int i = 0; i < _comments.length; i++) {
      buf.write(
        '<w:comment w:id="$i" w:author="Quds Office" w:date="2026-01-01T00:00:00Z" w:initials="QO">'
        '<w:p><w:r><w:t xml:space="preserve">${OfficeMarkup.escape(_comments[i])}</w:t></w:r></w:p>'
        '</w:comment>',
      );
    }
    buf.write('</w:comments>');
    return buf.toString();
  }

  static String _ext(String mime, String name) {
    if (mime.contains('jpeg') || name.toLowerCase().endsWith('.jpg')) {
      return '.jpg';
    }
    if (name.toLowerCase().endsWith('.gif')) {
      return '.gif';
    }
    return '.png';
  }
}
