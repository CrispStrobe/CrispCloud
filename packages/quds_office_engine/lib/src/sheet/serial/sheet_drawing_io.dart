import 'dart:convert';
import 'dart:typed_data';

import '../../builders/drawingml_charts.dart';
import '../../builders/office_markup.dart';
import '../../opc/content_types.dart';
import '../../opc/opc_archive.dart';
import '../../opc/package_part.dart';
import '../../opc/relationships.dart';
import '../../visual/drawingml_visual_io.dart';
import '../../visual/office_visual.dart';
import '../../visual/png_bytes.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../model/sml_workbook.dart';

/// SpreadsheetML drawings (`xdr:wsDr` / `xdr:oneCellAnchor`).
abstract final class SheetDrawingIo {
  /// pictureUri API.
  static const String pictureUri =
      'http://schemas.openxmlformats.org/drawingml/2006/picture';

  /// syncSheet API.
  static void syncSheet(
    SmlWorksheet sheet,
    OpcPackage package,
    String sheetUri,
    int drawingIndex,
  ) {
    if (sheet.drawings.isEmpty) {
      return;
    }
    final String drawingUri = '/xl/drawings/drawing$drawingIndex.xml';
    final RelationshipCollection sheetRels = package.relationshipsFor(sheetUri);
    final String target = OpcUris.relativize(sheetUri, drawingUri);
    PackageRelationship? found;
    for (final PackageRelationship rel in sheetRels.items) {
      if (rel.target == target && rel.type == RelationshipTypes.drawing) {
        found = rel;
        break;
      }
    }
    found ??= sheetRels.add(type: RelationshipTypes.drawing, target: target);
    final RelationshipCollection drawingRels = package.relationshipsFor(
      drawingUri,
    );
    final List<String> embedIds = <String>[];
    var mediaIndex = 1;
    var chartIndex = 1;
    for (final SmlDrawing drawing in sheet.drawings) {
      final OfficeVisual visual = drawing.visual;
      if (visual.isChart) {
        final String uri = '/xl/charts/chart$chartIndex.xml';
        chartIndex++;
        final String xml = _chartXml(visual, sheetRtl: sheet.rightToLeft);
        _writePart(
          package,
          uri,
          OfficeContentTypes.drawingChart,
          utf8.encode(xml),
        );
        embedIds.add(
          _ensureRel(
            drawingRels,
            RelationshipTypes.chart,
            OpcUris.relativize(drawingUri, uri),
          ),
        );
      } else {
        final Uint8List bytes = PngBytes.fromVisual(visual);
        final String mime = WordLikeMedia.mimeOf(bytes);
        final String uri =
            '/xl/media/image$mediaIndex${WordLikeMedia.extensionOf(mime)}';
        mediaIndex++;
        _writePart(package, uri, mime, bytes);
        embedIds.add(
          _ensureRel(
            drawingRels,
            RelationshipTypes.image,
            OpcUris.relativize(drawingUri, uri),
          ),
        );
      }
    }
    _writePart(
      package,
      drawingUri,
      OfficeContentTypes.spreadsheetDrawing,
      utf8.encode(_drawingXml(sheet, embedIds)),
    );
  }

  /// drawingRelationshipId API.
  static String? drawingRelationshipId(OpcPackage package, String sheetUri) {
    return package
        .relationshipsFor(sheetUri)
        .firstByType(RelationshipTypes.drawing)
        ?.id;
  }

  /// readSheet API.
  static void readSheet(
    SmlWorksheet sheet,
    OpcPackage package,
    String sheetUri,
  ) {
    final PackageRelationship? rel = package
        .relationshipsFor(sheetUri)
        .firstByType(RelationshipTypes.drawing);
    if (rel == null) {
      return;
    }
    final String drawingUri = package.relationshipsFor(sheetUri).resolve(rel);
    final PackagePart? part = package.getPart(drawingUri);
    if (part == null) {
      return;
    }
    sheet.drawings
      ..clear()
      ..addAll(_parse(part.readText(), package, drawingUri));
  }

  static List<SmlDrawing> _parse(
    String xml,
    OpcPackage package,
    String drawingUri,
  ) {
    final List<SmlDrawing> out = <SmlDrawing>[];
    final XmlPullReader reader = XmlPullReader(xml);
    String? embed;
    String? chartId;
    var cx = 0;
    var cy = 0;
    var col = 0;
    var row = 0;
    var colOff = 0;
    var rowOff = 0;
    var inFrom = false;
    final PictureAdjust adj = PictureAdjust();
    String name = 'Picture';
    void flush() {
      if (embed == null && chartId == null) {
        return;
      }
      OfficeVisual? visual;
      ({String? sheet, SmlRange range})? values;
      ({String? sheet, SmlRange range})? labels;
      final String? chartRel = chartId;
      final String? embedRel = embed;
      if (chartRel != null) {
        final String? chartXml = _readChartPart(package, drawingUri, chartRel);
        if (chartXml != null) {
          visual = DrawingmlVisualIo.parseChart(
            chartXml,
            name: name,
            width: cx > 0 ? DrawingmlVisualIo.emuToPoints(cx) : 360,
            height: cy > 0 ? DrawingmlVisualIo.emuToPoints(cy) : 180,
          );
          final ({String? categories, String? values}) refs =
              DrawingmlVisualIo.chartSeriesRefs(chartXml);
          values = _seriesRange(refs.values);
          labels = _seriesRange(refs.categories);
          if (labels != null && labels.sheet != values?.sheet) {
            labels = null;
          }
        }
      } else if (embedRel != null) {
        visual = _loadPicture(
          package,
          drawingUri,
          embedRel,
          name,
          cx,
          cy,
          adj.copy(),
        );
      }
      if (visual != null) {
        out.add(
          SmlDrawing(
            visual: visual,
            col: col,
            row: row,
            offsetX: DrawingmlVisualIo.emuToPixels(colOff),
            offsetY: DrawingmlVisualIo.emuToPixels(rowOff),
            sourceFromA1: values?.range.start.a1,
            sourceToA1: values?.range.end.a1,
            sourceSheetName: values?.sheet,
            labelsFromA1: labels?.range.start.a1,
            labelsToA1: labels?.range.end.a1,
          ),
        );
      }
      embed = null;
      chartId = null;
      cx = 0;
      cy = 0;
      col = 0;
      row = 0;
      colOff = 0;
      rowOff = 0;
      adj.reset();
      name = 'Picture';
    }

    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 'from') {
          inFrom = false;
        } else if (reader.localName == 'oneCellAnchor' ||
            reader.localName == 'twoCellAnchor' ||
            reader.localName == 'absoluteAnchor') {
          flush();
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      switch (reader.localName) {
        case 'from':
          inFrom = true;
        case 'col':
          if (inFrom) {
            col = int.tryParse(_text(reader)) ?? col;
          }
        case 'row':
          if (inFrom) {
            row = int.tryParse(_text(reader)) ?? row;
          }
        case 'colOff':
          if (inFrom) {
            colOff = int.tryParse(_text(reader)) ?? colOff;
          }
        case 'rowOff':
          if (inFrom) {
            rowOff = int.tryParse(_text(reader)) ?? rowOff;
          }
        case 'ext':
        case 'extent':
          cx = int.tryParse(reader.getAttribute('cx') ?? '') ?? cx;
          cy = int.tryParse(reader.getAttribute('cy') ?? '') ?? cy;
        case 'cNvPr':
        case 'docPr':
          name =
              reader.getAttribute('name') ??
              reader.getAttribute('descr') ??
              name;
          adj.altTitle = name;
          adj.altDescription = reader.getAttribute('descr') ?? '';
        case 'blip':
          embed =
              reader.getAttribute('embed', namespaceUri: OfficeNamespaces.r) ??
              reader.getAttribute('embed') ??
              embed;
        case 'chart':
          chartId =
              reader.getAttribute('id', namespaceUri: OfficeNamespaces.r) ??
              reader.getAttribute('id') ??
              chartId;
        case 'srcRect':
          DrawingmlVisualIo.applySrcRect(adj, reader);
        case 'xfrm':
          DrawingmlVisualIo.applyXfrm(adj, reader);
        case 'lum':
          DrawingmlVisualIo.applyLum(adj, reader);
        case 'alphaModFix':
          adj.transparency = DrawingmlVisualIo.alphaToTransparency(
            reader.getAttribute('amt'),
          );
        case 'outerShdw':
          adj.shadow = true;
        case 'ln':
          final int? wEmu = int.tryParse(reader.getAttribute('w') ?? '');
          if (wEmu != null) {
            adj.borderWidth = DrawingmlVisualIo.emuToBorder(wEmu);
          }
        case 'srgbClr':
          if (adj.borderWidth > 0) {
            adj.borderColor = reader.getAttribute('val') ?? adj.borderColor;
          }
        case 'graphicFrameLocks':
        case 'picLocks':
          final String? lock = reader.getAttribute('noChangeAspect');
          adj.lockAspect = lock != '0' && lock?.toLowerCase() != 'false';
      }
    }
    return out;
  }

  static String _drawingXml(SmlWorksheet sheet, List<String> embedIds) {
    final XmlWriter w = XmlWriter();
    w.writeStartDocument();
    w.writeStartElement('wsDr', prefix: 'xdr');
    w.writeNamespace('xdr', OfficeNamespaces.xdr);
    w.writeNamespace('a', OfficeNamespaces.a);
    w.writeNamespace('r', OfficeNamespaces.r);
    w.writeNamespace('c', OfficeNamespaces.c);
    for (int i = 0; i < sheet.drawings.length; i++) {
      final SmlDrawing drawing = sheet.drawings[i];
      final String rId = i < embedIds.length ? embedIds[i] : 'rId${i + 1}';
      _writeAnchor(w, drawing, rId, i + 2);
    }
    w.writeEndElement();
    return w.toXml();
  }

  static void _writeAnchor(
    XmlWriter w,
    SmlDrawing drawing,
    String relationshipId,
    int nvId,
  ) {
    final OfficeVisual visual = drawing.visual;
    final int cx = DrawingmlVisualIo.pointsToEmu(visual.width);
    final int cy = DrawingmlVisualIo.pointsToEmu(visual.height);
    w.writeStartElement('oneCellAnchor', prefix: 'xdr');
    w.writeStartElement('from', prefix: 'xdr');
    w.writeStartElement('col', prefix: 'xdr');
    w.writeText('${drawing.col}');
    w.writeEndElement();
    w.writeStartElement('colOff', prefix: 'xdr');
    w.writeText('${DrawingmlVisualIo.pixelsToEmu(drawing.offsetX)}');
    w.writeEndElement();
    w.writeStartElement('row', prefix: 'xdr');
    w.writeText('${drawing.row}');
    w.writeEndElement();
    w.writeStartElement('rowOff', prefix: 'xdr');
    w.writeText('${DrawingmlVisualIo.pixelsToEmu(drawing.offsetY)}');
    w.writeEndElement();
    w.writeEndElement();
    w.writeEmptyElement(
      'ext',
      prefix: 'xdr',
      attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
    );
    if (visual.isChart) {
      _writeChartFrame(w, visual, relationshipId, nvId, cx, cy);
    } else {
      _writePic(w, visual, relationshipId, nvId, cx, cy);
    }
    w.writeEmptyElement('clientData', prefix: 'xdr');
    w.writeEndElement();
  }

  static void _writePic(
    XmlWriter w,
    OfficeVisual visual,
    String relationshipId,
    int nvId,
    int cx,
    int cy,
  ) {
    final PictureAdjust adj = visual.picture;
    final String name = adj.altTitle.isNotEmpty
        ? adj.altTitle
        : (visual.title.isEmpty ? 'Picture' : visual.title);
    final String descr = adj.altDescription.isNotEmpty
        ? adj.altDescription
        : name;
    w.writeStartElement('pic', prefix: 'xdr');
    w.writeStartElement('nvPicPr', prefix: 'xdr');
    w.writeStartElement('cNvPr', prefix: 'xdr');
    w.writeAttribute('id', '$nvId');
    w.writeAttribute('name', name);
    w.writeAttribute('descr', descr);
    w.writeEndElement();
    w.writeStartElement('cNvPicPr', prefix: 'xdr');
    w.writeEmptyElement(
      'picLocks',
      prefix: 'a',
      attributes: <String, String>{
        'noChangeAspect': adj.lockAspect ? '1' : '0',
      },
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('blipFill', prefix: 'xdr');
    DrawingmlVisualIo.writeBlip(w, relationshipId: relationshipId, adj: adj);
    DrawingmlVisualIo.writeSrcRect(w, adj);
    w.writeStartElement('stretch', prefix: 'a');
    w.writeEmptyElement('fillRect', prefix: 'a');
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('spPr', prefix: 'xdr');
    DrawingmlVisualIo.writeXfrm(w, cx: cx, cy: cy, adj: adj);
    w.writeStartElement('prstGeom', prefix: 'a');
    w.writeAttribute('prst', 'rect');
    w.writeEmptyElement('avLst', prefix: 'a');
    w.writeEndElement();
    DrawingmlVisualIo.writeLine(w, adj);
    DrawingmlVisualIo.writeShadow(w, adj);
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeChartFrame(
    XmlWriter w,
    OfficeVisual visual,
    String relationshipId,
    int nvId,
    int cx,
    int cy,
  ) {
    final String name = visual.title.isEmpty ? 'Chart' : visual.title;
    w.writeStartElement('graphicFrame', prefix: 'xdr');
    w.writeStartElement('nvGraphicFramePr', prefix: 'xdr');
    w.writeStartElement('cNvPr', prefix: 'xdr');
    w.writeAttribute('id', '$nvId');
    w.writeAttribute('name', name);
    w.writeEndElement();
    w.writeEmptyElement('cNvGraphicFramePr', prefix: 'xdr');
    w.writeEndElement();
    DrawingmlVisualIo.writeXfrm(w, cx: cx, cy: cy, adj: visual.picture);
    w.writeStartElement('graphic', prefix: 'a');
    w.writeStartElement('graphicData', prefix: 'a');
    w.writeAttribute('uri', OfficeNamespaces.c);
    w.writeEmptyElement(
      'chart',
      prefix: 'c',
      attributes: <String, String>{'r:id': relationshipId},
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  static String _chartXml(OfficeVisual visual, {bool sheetRtl = false}) {
    final String title = visual.title.isEmpty ? 'Chart' : visual.title;
    final List<ChartPoint> points = visual.points.isEmpty
        ? OfficeVisual.sampleSeries()
        : visual.points;
    final bool rtl = visual.chart.rtl || sheetRtl;
    return switch (visual.kind) {
      OfficeVisualKind.chartPie => DrawingmlCharts.pie(
        title: title,
        series: points,
        rtl: rtl,
        display: visual.chart,
      ),
      OfficeVisualKind.chartLine => DrawingmlCharts.line(
        title: title,
        series: <ChartSeries>[ChartSeries(name: title, points: points)],
        rtl: rtl,
        display: visual.chart,
      ),
      OfficeVisualKind.chartBar => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: rtl,
        display: visual.chart,
      ),
      _ => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: rtl,
        horizontal: false,
        display: visual.chart,
      ),
    };
  }

  static OfficeVisual? _loadPicture(
    OpcPackage package,
    String drawingUri,
    String relationshipId,
    String name,
    int cx,
    int cy,
    PictureAdjust adj,
  ) {
    final PackageRelationship? rel = package
        .relationshipsFor(drawingUri)
        .byId(relationshipId);
    if (rel == null) {
      return null;
    }
    final PackagePart? part = package.getPart(
      package.relationshipsFor(drawingUri).resolve(rel),
    );
    if (part == null) {
      return null;
    }
    return OfficeVisual(
      kind: OfficeVisualKind.picture,
      title: name,
      imageBytes: part.readBytes(),
      width: cx > 0 ? DrawingmlVisualIo.emuToPoints(cx) : 240,
      height: cy > 0 ? DrawingmlVisualIo.emuToPoints(cy) : 140,
      picture: adj,
    );
  }

  static String? _readChartPart(
    OpcPackage package,
    String drawingUri,
    String relationshipId,
  ) {
    final PackageRelationship? rel = package
        .relationshipsFor(drawingUri)
        .byId(relationshipId);
    if (rel == null) {
      return null;
    }
    return package
        .getPart(package.relationshipsFor(drawingUri).resolve(rel))
        ?.readText();
  }

  /// `'Sheet 1'!$B$1:$B$3` → sheet name and range. Null for multi-area or
  /// unparseable references.
  static ({String? sheet, SmlRange range})? _seriesRange(String? formula) {
    if (formula == null || formula.isEmpty || formula.contains(',')) {
      return null;
    }
    final int bang = formula.lastIndexOf('!');
    String? sheet = bang < 0 ? null : formula.substring(0, bang);
    if (sheet != null &&
        sheet.length >= 2 &&
        sheet.startsWith("'") &&
        sheet.endsWith("'")) {
      sheet = sheet.substring(1, sheet.length - 1).replaceAll("''", "'");
    }
    final String a1 = formula.substring(bang + 1).replaceAll(r'$', '');
    try {
      return (sheet: sheet, range: SmlRange.parse(a1));
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static void _writePart(
    OpcPackage package,
    String uri,
    String contentType,
    List<int> bytes,
  ) {
    final PackagePart? existing = package.getPart(uri);
    if (existing == null) {
      package.createPart(uri, contentType, bytes);
    } else {
      existing.writeBytes(Uint8List.fromList(bytes));
    }
  }

  static String _ensureRel(
    RelationshipCollection rels,
    String type,
    String target,
  ) {
    for (final PackageRelationship rel in rels.items) {
      if (rel.target == target && rel.type == type) {
        return rel.id;
      }
    }
    return rels.add(type: type, target: target).id;
  }

  static String _text(XmlPullReader reader) {
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

/// Class WordLikeMedia.
abstract final class WordLikeMedia {
  /// mimeOf API.
  static String mimeOf(Uint8List bytes) {
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  /// extensionOf API.
  static String extensionOf(String mime) {
    if (mime == 'image/jpeg') {
      return '.jpeg';
    }
    if (mime == 'image/gif') {
      return '.gif';
    }
    return '.png';
  }
}
