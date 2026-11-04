/// Writes the logical report flow to a WordprocessingML (.docx) package.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../builders/office_markup.dart';
import '../opc/content_types.dart';
import '../opc/opc_archive.dart';
import '../opc/relationships.dart';
import '../xml/namespaces.dart';
import 'report_chart.dart';
import 'report_expression.dart';
import 'report_expression_engine.dart';
import 'report_fonts.dart';
import 'report_layout.dart';
import 'report_template.dart';
import 'report_units.dart';

/// Flow-based Word export.
///
/// The page header / footer bands become Word header and footer parts, with
/// `System.PageNumber` and `System.TotalPages` written as live `PAGE` and
/// `NUMPAGES` fields so Word repaginates correctly. Body bands become
/// paragraphs (side-by-side elements share a borderless row), horizontal
/// line shapes become paragraph rules, images are inline pictures, and data
/// tables are real Word tables whose header row repeats on every page.
class ReportDocxWriter {
  /// ReportDocxWriter API.
  const ReportDocxWriter({required this.engine, required this.scope});

  /// Evaluates header/footer placeholders.
  final QudsExpressionEngine engine;

  /// Root scope for header/footer text (page 1, final page count).
  final ReportScope scope;

  /// Serializes [layout].
  Uint8List write(ReportDocumentLayout layout) {
    final ReportTemplate t = layout.template;
    final _Ids ids = _Ids();
    final _Part body = _Part('/word/document.xml', ids);
    final _BlockWriter bodyWriter = _BlockWriter(t, body);
    final ReportBand? detail = t.detail;
    final bool pageEachRow =
        detail != null &&
        (detail.newPageBefore || detail.newPageAfter) &&
        !detail.elements.any((ReportElement e) => e is ReportTableElement);
    final bool breakBefore = detail?.newPageBefore ?? false;
    final bool breakAfter = detail?.newPageAfter ?? false;
    var broke = false;
    final List<ReportFlowEntry> flow = layout.flow;
    for (int i = 0; i < flow.length; i++) {
      final ReportFlowEntry e = flow[i];
      final bool row =
          pageEachRow && e is ReportFlowBand && e.band == ReportBandKind.detail;
      if (row && breakBefore && i > 0 && !broke) {
        bodyWriter.pageBreak();
      }
      switch (e) {
        case ReportFlowBand():
          bodyWriter.band(e.items, e.height);
        case ReportFlowTableRow():
          bodyWriter.tableRow(e);
      }
      broke = false;
      if (row && breakAfter && i + 1 < flow.length) {
        bodyWriter.pageBreak();
        broke = true;
      }
    }
    bodyWriter.flush();

    final ReportBand? headerBand = t.band(ReportBandKind.pageHeader);
    final ReportBand? footerBand = t.band(ReportBandKind.pageFooter);
    final _Part? header = headerBand == null
        ? null
        : _bandPart('/word/header1.xml', headerBand, layout, ids);
    final _Part? footer = footerBand == null
        ? null
        : _bandPart('/word/footer1.xml', footerBand, layout, ids);
    final bool titlePg =
        (headerBand != null && !headerBand.printOnFirstPage) ||
        (footerBand != null && !footerBand.printOnFirstPage);

    final OpcPackage package = OpcPackage.empty();
    package.packageRelationships.add(
      type: RelationshipTypes.officeDocument,
      target: 'word/document.xml',
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
      );
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      utf8.encode(_stylesXml(t)),
    );
    package.createPart(
      '/word/settings.xml',
      OfficeContentTypes.wordSettings,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:settings xmlns:w="${OfficeNamespaces.w}">'
        '<w:defaultTabStop w:val="720"/><w:compat/></w:settings>',
      ),
    );

    final StringBuffer refs = StringBuffer();
    void addHf(
      _Part part, {
      required bool isHeader,
      required String type,
      required String id,
    }) {
      final String file = part.uri.substring('/word/'.length);
      package.createPart(
        part.uri,
        isHeader
            ? OfficeContentTypes.wordHeader
            : OfficeContentTypes.wordFooter,
        utf8.encode(_hfXml(part, isHeader: isHeader)),
      );
      rels.add(
        type: isHeader ? RelationshipTypes.header : RelationshipTypes.footer,
        target: file,
        id: id,
      );
      refs.write(
        '<w:${isHeader ? 'header' : 'footer'}Reference w:type="$type" r:id="$id"/>',
      );
      _addMedia(package, part);
    }

    if (header != null) {
      addHf(header, isHeader: true, type: 'default', id: 'rIdHeader1');
      if (titlePg) {
        final _Part first = headerBand!.printOnFirstPage
            ? _bandPart('/word/header2.xml', headerBand, layout, ids)
            : (_Part('/word/header2.xml', ids)..xml.write(_emptyParagraph));
        addHf(first, isHeader: true, type: 'first', id: 'rIdHeader2');
      }
    }
    if (footer != null) {
      addHf(footer, isHeader: false, type: 'default', id: 'rIdFooter1');
      if (titlePg) {
        final _Part first = footerBand!.printOnFirstPage
            ? _bandPart('/word/footer2.xml', footerBand, layout, ids)
            : (_Part('/word/footer2.xml', ids)..xml.write(_emptyParagraph));
        addHf(first, isHeader: false, type: 'first', id: 'rIdFooter2');
      }
    }

    final double headerH = headerBand?.designHeight ?? 0;
    final double footerH = footerBand?.designHeight ?? 0;
    final bool landscape = t.pageWidth > t.pageHeight;
    final String sect =
        '<w:sectPr>$refs'
        '<w:pgSz w:w="${_tw(t.pageWidth)}" w:h="${_tw(t.pageHeight)}"'
        '${landscape ? ' w:orient="landscape"' : ''}/>'
        '<w:pgMar w:top="${_tw(t.margins.top + headerH)}" w:right="${_tw(t.margins.right)}" '
        'w:bottom="${_tw(t.margins.bottom + footerH)}" w:left="${_tw(t.margins.left)}" '
        'w:header="${_tw(t.margins.top)}" w:footer="${_tw(t.margins.bottom)}" w:gutter="0"/>'
        '${titlePg ? '<w:titlePg/>' : ''}'
        '${t.isRtl ? '<w:bidi/>' : ''}</w:sectPr>';
    package.createPart(
      '/word/document.xml',
      OfficeContentTypes.wordMain,
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document ${_namespaces()}><w:body>${body.xml}$_emptyParagraph$sect'
        '</w:body></w:document>',
      ),
    );
    _addMedia(package, body);
    return package.save();
  }

  static const String _emptyParagraph =
      '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr></w:p>';

  static String _namespaces() =>
      'xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}" '
      'xmlns:wp="${OfficeNamespaces.wp}" xmlns:a="${OfficeNamespaces.a}" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

  static String _hfXml(_Part part, {required bool isHeader}) {
    final String tag = isHeader ? 'w:hdr' : 'w:ftr';
    final String content = part.xml.isEmpty
        ? _emptyParagraph
        : part.xml.toString();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<$tag ${_namespaces()}>$content$_emptyParagraph</$tag>';
  }

  static void _addMedia(OpcPackage package, _Part part) {
    if (part.images.isEmpty && part.charts.isEmpty && part.links.isEmpty) {
      return;
    }
    final RelationshipCollection rels = package.relationshipsFor(part.uri);
    for (final _Image img in part.images) {
      package.createPart('/word/media/${img.file}', img.mime, img.bytes);
      rels.add(
        type: RelationshipTypes.image,
        target: 'media/${img.file}',
        id: img.rId,
      );
    }
    for (final _Chart chart in part.charts) {
      package.createPart(
        '/word/charts/${chart.file}',
        OfficeContentTypes.drawingChart,
        utf8.encode(chart.xml),
      );
      rels.add(
        type: RelationshipTypes.chart,
        target: 'charts/${chart.file}',
        id: chart.rId,
      );
    }
    for (final ({String id, String url}) link in part.links) {
      rels.add(
        type:
            'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',
        target: link.url,
        id: link.id,
        targetMode: RelationshipTargetMode.external,
      );
    }
  }

  _Part _bandPart(
    String uri,
    ReportBand band,
    ReportDocumentLayout layout,
    _Ids ids,
  ) {
    final _Part part = _Part(uri, ids);
    final ReportTemplate t = layout.template;
    final Map<String, Uint8List> images = <String, Uint8List>{};
    if (layout.pages.isNotEmpty) {
      for (final ReportPrimitive p in layout.pages.first.primitives) {
        final String? id = p.elementId;
        if (p is ReportImagePrimitive && id != null && p.band == band.kind) {
          images[id] = p.bytes;
        }
      }
    }
    final List<_Item> items = <_Item>[];
    for (final ReportElement e in band.elements) {
      if (!_visible(e.visibleWhen)) {
        continue;
      }
      final ReportRect rect = ReportRect(
        t.elementLeft(e.x, e.width),
        e.y,
        e.width,
        e.height,
      );
      switch (e) {
        case ReportTextElement():
          final bool rtl = switch (e.direction) {
            ReportTextDirection.rtl => true,
            ReportTextDirection.ltr => false,
            ReportTextDirection.auto => t.isRtl,
          };
          items.add(
            _Para(
              rect: rect,
              runs: _runs(e.text, e.format),
              font: ReportFontSpec(
                family: e.style.fontFamily ?? t.defaultFont,
                size: e.style.fontSize ?? t.defaultFontSize,
                bold: e.style.bold ?? false,
                italic: e.style.italic ?? false,
              ),
              color: t.resolveColor(e.style.color, t.textColor),
              align: _physical(e.align, rtl: rtl),
              rtl: rtl,
              underline: e.style.underline ?? false,
              background: e.background == null
                  ? null
                  : t.resolveColor(e.background, ReportColor.transparent),
            ),
          );
        case ReportShapeElement(:final ReportShapeKind kind)
            when kind == ReportShapeKind.line && e.height <= e.width * 0.05:
          items.add(
            _Rule(
              rect: rect,
              color: t.resolveColor(e.strokeColor, t.textColor),
              width: e.strokeWidth,
            ),
          );
        case ReportImageElement():
          final Uint8List? bytes = images[e.id];
          if (bytes != null) {
            items.add(_Picture(rect: rect, bytes: bytes));
          }
        case ReportShapeElement():
        case ReportBarcodeElement():
        case ReportTableElement():
        case ReportChartElement():
        case ReportCrosstabElement():
        case ReportSubreportElement():
          break;
      }
    }
    _BlockWriter(t, part)
      ..items(items, band.height)
      ..flush();
    return part;
  }

  bool _visible(String? expr) {
    if (expr == null || expr.trim().isEmpty) {
      return true;
    }
    try {
      return expr.contains('{{')
          ? engine.valueOf(ReportTemplateText.parse(expr), scope).truthy
          : engine.evaluateSource(expr, scope).truthy;
    } on ReportExpressionException {
      return true;
    }
  }

  /// Splits [template] into literal text and `PAGE` / `NUMPAGES` fields.
  List<_Run> _runs(String template, String? format) {
    if (!template.contains('{{')) {
      return <_Run>[_Run.text(template)];
    }
    final List<_Run> out = <_Run>[];
    try {
      final ReportTemplateText parsed = ReportTemplateText.parse(template);
      for (final ReportTextSegment s in parsed.segments) {
        switch (s) {
          case ReportLiteralSegment(:final String text):
            out.add(_Run.text(text));
          case ReportExpressionSegment(
            :final ReportExpression expression,
            format: final String? f,
          ):
            final String? path = ReportExpression.dottedPath(
              expression.root,
            )?.toLowerCase();
            if (path == 'system.pagenumber') {
              out.add(_Run.field('PAGE', '${scope.system.pageNumber}'));
            } else if (path == 'system.totalpages' ||
                path == 'system.pagecount') {
              out.add(_Run.field('NUMPAGES', '${scope.system.totalPages}'));
            } else {
              out.add(
                _Run.text(
                  engine.formatter.format(
                    engine.evaluate(expression, scope),
                    f ?? format,
                  ),
                ),
              );
            }
        }
      }
    } on ReportExpressionException {
      return <_Run>[const _Run.text('#ERR')];
    }
    return out;
  }

  static ReportTextAlign _physical(
    ReportTextAlign a, {
    required bool rtl,
  }) => switch (a) {
    ReportTextAlign.start => rtl ? ReportTextAlign.right : ReportTextAlign.left,
    ReportTextAlign.end => rtl ? ReportTextAlign.left : ReportTextAlign.right,
    _ => a,
  };

  static String _stylesXml(ReportTemplate t) {
    final String face = OfficeMarkup.escapeAttr(
      t.defaultFont.isEmpty ? 'Arial' : t.defaultFont,
    );
    final int sz = (t.defaultFontSize * 2).round();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="${OfficeNamespaces.w}">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="$face" w:hAnsi="$face" w:cs="$face" w:eastAsia="$face"/>'
        '<w:sz w:val="$sz"/><w:szCs w:val="$sz"/>'
        '<w:lang w:val="${t.isRtl ? 'ar-SA' : 'en-US'}" w:eastAsia="en-US" w:bidi="ar-SA"/>'
        '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>'
        '<w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>'
        '</w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/><w:qFormat/></w:style>'
        '<w:style w:type="table" w:default="1" w:styleId="TableNormal">'
        '<w:name w:val="Normal Table"/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/>'
        '<w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="60" w:type="dxa"/>'
        '<w:bottom w:w="0" w:type="dxa"/><w:right w:w="60" w:type="dxa"/></w:tblCellMar>'
        '</w:tblPr></w:style></w:styles>';
  }
}

int _tw(double points) => (points * 20).round();

/// Shared drawing-id counter.
class _Ids {
  int docPr = 0;
  int image = 0;
  int chart = 0;
}

class _Chart {
  _Chart(this.file, this.xml, this.rId);

  final String file;
  final String xml;
  final String rId;
}

class _Image {
  _Image(this.file, this.bytes, this.mime, this.rId);

  final String file;
  final Uint8List bytes;
  final String mime;
  final String rId;
}

/// XML body of one part plus the images it references.
class _Part {
  _Part(this.uri, this.ids);

  final String uri;
  final _Ids ids;
  final StringBuffer xml = StringBuffer();
  final List<_Image> images = <_Image>[];
  final List<_Chart> charts = <_Chart>[];
  final List<({String id, String url})> links = <({String id, String url})>[];

  /// Relationship id for an external [url].
  String hyperlink(String url) {
    for (final ({String id, String url}) link in links) {
      if (link.url == url) {
        return link.id;
      }
    }
    final String id = 'rIdLink${links.length + 1}';
    links.add((id: id, url: url));
    return id;
  }

  String addChart(String xml) {
    ids.chart++;
    final String rId = 'rIdChart${charts.length + 1}';
    charts.add(_Chart('chart${ids.chart}.xml', xml, rId));
    return rId;
  }

  String addImage(Uint8List bytes) {
    final bool jpeg = bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    ids.image++;
    final String rId = 'rIdImg${images.length + 1}';
    images.add(
      _Image(
        'report${ids.image}.${jpeg ? 'jpeg' : 'png'}',
        bytes,
        jpeg ? 'image/jpeg' : 'image/png',
        rId,
      ),
    );
    return rId;
  }
}

class _Run {
  const _Run.text(
    this.text, {
    this.bold,
    this.italic,
    this.size,
    this.underline,
    this.link,
  }) : field = null;

  const _Run.field(String instruction, this.text)
    : field = instruction,
      bold = null,
      italic = null,
      size = null,
      underline = null,
      link = null;

  /// Literal text, or the cached field result.
  final String text;

  /// Field instruction (`PAGE`), or null for literal text.
  final String? field;

  /// Overrides the paragraph bold.
  final bool? bold;

  /// Overrides the paragraph italic.
  final bool? italic;

  /// Overrides the paragraph size, points.
  final double? size;

  /// Overrides the paragraph underline.
  final bool? underline;

  /// External URI.
  final String? link;
}

sealed class _Item {
  const _Item(this.rect);

  final ReportRect rect;
}

final class _Para extends _Item {
  const _Para({
    required ReportRect rect,
    required this.runs,
    required this.font,
    required this.color,
    required this.align,
    required this.rtl,
    this.underline = false,
    this.background,
  }) : super(rect);

  final List<_Run> runs;
  final ReportFontSpec font;
  final ReportColor color;
  final ReportTextAlign align;
  final bool rtl;
  final bool underline;
  final ReportColor? background;
}

final class _Rule extends _Item {
  const _Rule({
    required ReportRect rect,
    required this.color,
    required this.width,
  }) : super(rect);

  final ReportColor color;
  final double width;
}

final class _Picture extends _Item {
  const _Picture({required ReportRect rect, required this.bytes}) : super(rect);

  final Uint8List bytes;
}

final class _ChartBox extends _Item {
  const _ChartBox({required ReportRect rect, required this.data}) : super(rect);

  final ReportChartData data;
}

final class _Grid extends _Item {
  const _Grid({required ReportRect rect, required this.rows}) : super(rect);

  final List<ReportFlowTableRow> rows;
}

/// Emits paragraphs and tables for bands and table rows.
class _BlockWriter {
  _BlockWriter(this.t, this.part);

  final ReportTemplate t;
  final _Part part;
  final List<ReportFlowTableRow> _pendingRows = <ReportFlowTableRow>[];
  double _pendingSpace = 0;
  bool _lastWasTable = false;

  StringBuffer get _out => part.xml;

  void band(List<ReportFlowItem> flow, double height) {
    final List<_Item> list = <_Item>[];
    for (final ReportFlowItem f in flow) {
      switch (f) {
        case ReportFlowText():
          list.add(
            _Para(
              rect: f.rect,
              runs: f.spans.isEmpty
                  ? <_Run>[_Run.text(f.text)]
                  : <_Run>[
                      for (final ReportFlowSpan s in f.spans)
                        _Run.text(
                          s.text,
                          bold: s.font.bold,
                          italic: s.font.italic,
                          size: s.font.size,
                          underline: s.underline,
                          link: s.link,
                        ),
                    ],
              font: f.font,
              color: f.color,
              align: f.align,
              rtl: f.rtl,
              underline: f.underline,
              background: f.background,
            ),
          );
        case ReportFlowImage():
          list.add(_Picture(rect: f.rect, bytes: f.bytes));
        case ReportFlowRule():
          list.add(_Rule(rect: f.rect, color: f.color, width: f.width));
        case ReportFlowTableBlock():
          list.add(_Grid(rect: f.rect, rows: f.rows));
        case ReportFlowChart():
          if (!f.data.isEmpty) {
            list.add(_ChartBox(rect: f.rect, data: f.data));
          }
      }
    }
    items(list, height);
  }

  void items(List<_Item> list, double height) {
    _flushTable();
    list.sort((_Item a, _Item b) => a.rect.top.compareTo(b.rect.top));
    var cursor = 0.0;
    var i = 0;
    while (i < list.length) {
      final double top = list[i].rect.top;
      final List<_Item> cluster = <_Item>[];
      while (i < list.length && (list[i].rect.top - top).abs() <= 3) {
        cluster.add(list[i]);
        i++;
      }
      final double gap = top - cursor;
      _pendingSpace += gap > 0 ? gap : 0;
      var bottom = cursor;
      for (final _Item it in cluster) {
        if (it.rect.bottom > bottom) {
          bottom = it.rect.bottom;
        }
      }
      _cluster(cluster);
      cursor = bottom;
    }
    final double tail = height - cursor;
    _pendingSpace += tail > 0 ? tail : 0;
  }

  void tableRow(ReportFlowTableRow row) {
    if (_pendingRows.isNotEmpty &&
        !identical(_pendingRows.first.table, row.table)) {
      _flushTable();
    }
    _pendingRows.add(row);
  }

  void flush() => _flushTable();

  /// A Word page break, after any open table is closed.
  void pageBreak() {
    _flushTable();
    _pendingSpace = 0;
    _lastWasTable = false;
    _out.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
  }

  void _flushTable() {
    if (_pendingRows.isEmpty) {
      return;
    }
    _table(List<ReportFlowTableRow>.of(_pendingRows));
    _pendingRows.clear();
  }

  void _cluster(List<_Item> cluster) {
    final List<_Item> grids = <_Item>[
      for (final _Item c in cluster)
        if (c is _Grid) c,
    ];
    final List<_Item> rest = <_Item>[
      for (final _Item c in cluster)
        if (c is! _Grid) c,
    ];
    if (rest.length == 1) {
      _block(rest.first);
    } else if (rest.length > 1) {
      _row(rest);
    }
    for (final _Item g in grids) {
      _table((g as _Grid).rows);
    }
  }

  void _block(_Item item) {
    switch (item) {
      case _Para():
        _out.write(_paragraph(item, spaceBefore: _takeSpace()));
        _lastWasTable = false;
      case _Rule():
        _out.write(
          '<w:p><w:pPr>${t.isRtl ? '<w:bidi/>' : ''}'
          '<w:pBdr><w:bottom w:val="single" w:sz="${_eighths(item.width)}" '
          'w:space="1" w:color="${item.color.hex}"/></w:pBdr>'
          '<w:spacing w:before="${_tw(_takeSpace())}" w:after="0" w:line="40" w:lineRule="exact"/>'
          '${_indent(item.rect)}</w:pPr></w:p>',
        );
        _lastWasTable = false;
      case _Picture():
        _out.write(
          '<w:p><w:pPr>${t.isRtl ? '<w:bidi/>' : ''}'
          '<w:spacing w:before="${_tw(_takeSpace())}" w:after="0"/>'
          '<w:jc w:val="${_jcForRect(item.rect)}"/></w:pPr>'
          '${_drawing(item)}</w:p>',
        );
        _lastWasTable = false;
      case _ChartBox():
        _out.write(
          '<w:p><w:pPr>${t.isRtl ? '<w:bidi/>' : ''}'
          '<w:spacing w:before="${_tw(_takeSpace())}" w:after="0"/>'
          '<w:jc w:val="${_jcForRect(item.rect)}"/></w:pPr>'
          '${_chartDrawing(item)}</w:p>',
        );
        _lastWasTable = false;
      case _Grid():
        _table(item.rows);
    }
  }

  /// Side-by-side items as one borderless row, cells in visual order.
  void _row(List<_Item> items) {
    final bool rtl = t.isRtl;
    items.sort(
      (_Item a, _Item b) => rtl
          ? b.rect.right.compareTo(a.rect.right)
          : a.rect.left.compareTo(b.rect.left),
    );
    final double left = t.margins.left;
    final double right = t.pageWidth - t.margins.right;
    final List<double> widths = <double>[];
    final List<_Item?> cells = <_Item?>[];
    var edge = rtl ? right : left;
    for (int i = 0; i < items.length; i++) {
      final _Item it = items[i];
      final double start = rtl ? it.rect.right : it.rect.left;
      final double lead = rtl ? edge - start : start - edge;
      if (lead > 2) {
        widths.add(lead);
        cells.add(null);
        edge = start;
      }
      final double nextStart = i + 1 < items.length
          ? (rtl ? items[i + 1].rect.right : items[i + 1].rect.left)
          : (rtl ? left : right);
      var w = rtl ? edge - nextStart : nextStart - edge;
      if (w < it.rect.width) {
        w = it.rect.width;
      }
      widths.add(w);
      cells.add(it);
      edge = rtl ? edge - w : edge + w;
    }
    final double space = _takeSpace();
    if (space > 0 || _lastWasTable) {
      _spacer(space);
    }
    final StringBuffer grid = StringBuffer();
    final StringBuffer tr = StringBuffer(
      '<w:tr><w:trPr><w:cantSplit/></w:trPr>',
    );
    for (int i = 0; i < widths.length; i++) {
      grid.write('<w:gridCol w:w="${_tw(widths[i])}"/>');
      final _Item? it = cells[i];
      final String content = switch (it) {
        null => _emptyCellParagraph,
        _Para() => _paragraph(it, spaceBefore: 0, indent: false),
        _Picture() =>
          '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>${_drawing(it)}</w:p>',
        _Rule() =>
          '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="${_eighths(it.width)}" '
              'w:space="1" w:color="${it.color.hex}"/></w:pBdr></w:pPr></w:p>',
        _ChartBox() =>
          '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>${_chartDrawing(it)}</w:p>',
        _Grid() => _emptyCellParagraph,
      };
      tr.write(
        '<w:tc><w:tcPr><w:tcW w:w="${_tw(widths[i])}" w:type="dxa"/>'
        '<w:tcMar><w:left w:w="0" w:type="dxa"/><w:right w:w="0" w:type="dxa"/></w:tcMar>'
        '</w:tcPr>$content</w:tc>',
      );
    }
    tr.write('</w:tr>');
    _out.write(
      '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}'
      '<w:tblW w:w="0" w:type="auto"/><w:tblLayout w:type="fixed"/>'
      '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/>'
      '<w:right w:val="nil"/><w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders>'
      '</w:tblPr><w:tblGrid>$grid</w:tblGrid>$tr</w:tbl>',
    );
    _lastWasTable = true;
  }

  static const String _emptyCellParagraph =
      '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr></w:p>';

  void _table(List<ReportFlowTableRow> rows) {
    if (rows.isEmpty) {
      return;
    }
    final ReportTableElement table = rows.first.table;
    final List<double> widths = rows.first.columnWidths;
    final bool rtl = t.isRtl;
    final double space = _takeSpace();
    if (space > 0 || _lastWasTable) {
      _spacer(space);
    }
    var total = 0.0;
    for (final double w in widths) {
      total += w;
    }
    final double x0 = t.elementLeft(table.x, total);
    final double indent = rtl
        ? (t.pageWidth - t.margins.right) - (x0 + total)
        : x0 - t.margins.left;
    final ReportColor grid = t.resolveColor(
      table.borderColor,
      const ReportColor(0xFFBFBFBF),
    );
    final String border = table.showGrid && table.borderWidth > 0
        ? 'w:val="single" w:sz="${_eighths(table.borderWidth)}" w:space="0" w:color="${grid.hex}"'
        : 'w:val="nil"';
    final StringBuffer out = StringBuffer(
      '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}'
      '<w:tblW w:w="${_tw(total)}" w:type="dxa"/>'
      '<w:tblInd w:w="${_tw(indent > 0 ? indent : 0)}" w:type="dxa"/>'
      '<w:tblBorders><w:top $border/><w:left $border/><w:bottom $border/><w:right $border/>'
      '<w:insideH $border/><w:insideV $border/></w:tblBorders>'
      '<w:tblLayout w:type="fixed"/>'
      '<w:tblCellMar><w:left w:w="${_tw(table.padding)}" w:type="dxa"/>'
      '<w:right w:w="${_tw(table.padding)}" w:type="dxa"/></w:tblCellMar>'
      '</w:tblPr><w:tblGrid>',
    );
    for (final double w in widths) {
      out.write('<w:gridCol w:w="${_tw(w)}"/>');
    }
    out.write('</w:tblGrid>');
    for (final ReportFlowTableRow row in rows) {
      out.write('<w:tr><w:trPr><w:cantSplit/>');
      if (row.header && table.repeatHeader) {
        out.write('<w:tblHeader/>');
      }
      out.write(
        '<w:trHeight w:val="${_tw(row.height)}" w:hRule="atLeast"/></w:trPr>',
      );
      for (int c = 0; c < widths.length; c++) {
        final ReportFlowCell? cell = c < row.cells.length ? row.cells[c] : null;
        final ReportColor? fill = cell?.background ?? row.fill;
        out.write(
          '<w:tc><w:tcPr><w:tcW w:w="${_tw(widths[c])}" w:type="dxa"/>'
          '${fill != null && fill.alpha > 0 ? '<w:shd w:val="clear" w:color="auto" w:fill="${fill.hex}"/>' : ''}'
          '<w:vAlign w:val="center"/></w:tcPr>',
        );
        if (cell == null) {
          out.write(_emptyCellParagraph);
        } else {
          out.write(
            _paragraph(
              _Para(
                rect: const ReportRect(0, 0, 0, 0),
                runs: <_Run>[_Run.text(cell.text)],
                font: ReportFontSpec(
                  family: table.fontFamily ?? t.defaultFont,
                  size: cell.fontSize,
                  bold: cell.bold,
                  italic: cell.italic,
                ),
                color: cell.color,
                align: cell.align,
                rtl: rtl,
              ),
              spaceBefore: 0,
              indent: false,
            ),
          );
        }
        out.write('</w:tc>');
      }
      out.write('</w:tr>');
    }
    out.write('</w:tbl>');
    _out.write(out);
    _lastWasTable = true;
  }

  void _spacer(double space) {
    _out.write(
      '<w:p><w:pPr><w:spacing w:before="${_tw(space)}" w:after="0" '
      'w:line="20" w:lineRule="exact"/></w:pPr></w:p>',
    );
  }

  double _takeSpace() {
    final double s = _pendingSpace;
    _pendingSpace = 0;
    return s;
  }

  static int _eighths(double points) {
    final int v = (points * 8).round();
    return v < 2 ? 2 : (v > 96 ? 96 : v);
  }

  String _jcForRect(ReportRect r) {
    final double left = r.left - t.margins.left;
    final double right = (t.pageWidth - t.margins.right) - r.right;
    if ((left - right).abs() < 6) {
      return 'center';
    }
    return left < right
        ? (t.isRtl ? 'end' : 'start')
        : (t.isRtl ? 'start' : 'end');
  }

  /// Start/end indentation reproducing the element's horizontal position.
  String _indent(ReportRect r) {
    final double left = r.left - t.margins.left;
    final double right = (t.pageWidth - t.margins.right) - r.right;
    final int l = _tw(left > 0 ? left : 0);
    final int rr = _tw(right > 0 ? right : 0);
    return t.isRtl
        ? '<w:ind w:start="$rr" w:end="$l"/>'
        : '<w:ind w:start="$l" w:end="$rr"/>';
  }

  String _paragraph(
    _Para p, {
    required double spaceBefore,
    bool indent = true,
  }) {
    final String jc = switch (p.align) {
      ReportTextAlign.center => 'center',
      ReportTextAlign.justify => 'both',
      ReportTextAlign.right => p.rtl ? 'start' : 'end',
      _ => p.rtl ? 'end' : 'start',
    };
    final ReportColor? bg = p.background;
    final StringBuffer out = StringBuffer(
      '<w:p><w:pPr>${p.rtl ? '<w:bidi/>' : ''}'
      '<w:spacing w:before="${_tw(spaceBefore)}" w:after="0"/>'
      '${bg != null && bg.alpha > 0 ? '<w:shd w:val="clear" w:color="auto" w:fill="${bg.hex}"/>' : ''}'
      '${indent && p.rect.width > 0 ? _indent(p.rect) : ''}'
      '<w:jc w:val="$jc"/></w:pPr>',
    );
    for (final _Run run in p.runs) {
      final String rPr = _rPr(p, run);
      final String? field = run.field;
      if (field != null) {
        out
          ..write('<w:r>$rPr<w:fldChar w:fldCharType="begin"/></w:r>')
          ..write(
            '<w:r>$rPr<w:instrText xml:space="preserve"> $field </w:instrText></w:r>',
          )
          ..write('<w:r>$rPr<w:fldChar w:fldCharType="separate"/></w:r>')
          ..write('<w:r>$rPr<w:t>${OfficeMarkup.escape(run.text)}</w:t></w:r>')
          ..write('<w:r>$rPr<w:fldChar w:fldCharType="end"/></w:r>');
        continue;
      }
      final List<String> lines = run.text.split('\n');
      final String? link = run.link;
      if (link != null && link.isNotEmpty) {
        out.write('<w:hyperlink r:id="${part.hyperlink(link)}">');
      }
      out.write('<w:r>$rPr');
      for (int i = 0; i < lines.length; i++) {
        if (i > 0) {
          out.write('<w:br/>');
        }
        out.write(
          '<w:t xml:space="preserve">${OfficeMarkup.escape(lines[i])}</w:t>',
        );
      }
      out.write('</w:r>');
      if (link != null && link.isNotEmpty) {
        out.write('</w:hyperlink>');
      }
    }
    out.write('</w:p>');
    return out.toString();
  }

  String _rPr(_Para p, _Run run) {
    final String face = OfficeMarkup.escapeAttr(
      p.font.family.isEmpty
          ? (t.defaultFont.isEmpty ? 'Arial' : t.defaultFont)
          : p.font.family,
    );
    final bool bold = run.bold ?? p.font.bold;
    final bool italic = run.italic ?? p.font.italic;
    final bool underline = run.underline ?? p.underline;
    final int sz = ((run.size ?? p.font.size) * 2).round();
    return '<w:rPr><w:rFonts w:ascii="$face" w:hAnsi="$face" w:cs="$face" w:eastAsia="$face"/>'
        '${bold ? '<w:b/><w:bCs/>' : ''}'
        '${italic ? '<w:i/><w:iCs/>' : ''}'
        '${underline ? '<w:u w:val="single"/>' : ''}'
        '<w:color w:val="${p.color.hex}"/>'
        '<w:sz w:val="$sz"/><w:szCs w:val="$sz"/>'
        '${_hasRtl(run.text) ? '<w:rtl/>' : ''}</w:rPr>';
  }

  static bool _hasRtl(String s) {
    for (final int cp in s.runes) {
      if ((cp >= 0x0590 && cp <= 0x08FF) ||
          (cp >= 0xFB1D && cp <= 0xFDFF) ||
          (cp >= 0xFE70 && cp <= 0xFEFF)) {
        return true;
      }
    }
    return false;
  }

  String _chartDrawing(_ChartBox c) {
    final String rId = part.addChart(c.data.toDrawingml());
    final int docPr = ++part.ids.docPr;
    final int cx = (c.rect.width * 12700).round();
    final int cy = (c.rect.height * 12700).round();
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$docPr" name="Chart $docPr"/>'
        '<a:graphic><a:graphicData uri="${OfficeNamespaces.c}">'
        '<c:chart xmlns:c="${OfficeNamespaces.c}" r:id="$rId"/>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }

  String _drawing(_Picture p) {
    final String rId = part.addImage(p.bytes);
    final int docPr = ++part.ids.docPr;
    final int cx = (p.rect.width * 12700).round();
    final int cy = (p.rect.height * 12700).round();
    return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$docPr" name="Picture $docPr"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="0" name="Picture $docPr"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$rId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
  }
}
