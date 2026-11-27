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
import '../../xml/xml_node.dart';
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
    int drawingIndex, {
    SmlWorkbook? workbook,
  }) {
    if (sheet.drawings.isEmpty) {
      return;
    }
    final RelationshipCollection sheetRels = package.relationshipsFor(sheetUri);
    final imported = sheetRels.firstByType(RelationshipTypes.drawing);
    final owner = sheetUri.split('/').last.replaceAll('.xml', '');
    final String drawingUri = imported == null
        ? '/xl/drawings/${owner}_drawing.xml'
        : sheetRels.resolve(imported);
    final String target = OpcUris.relativize(sheetUri, drawingUri);
    // A worksheet owns exactly one drawing relationship. Imported producers
    // may use an absolute package URI while our writer uses a relative target;
    // keep the matching one so a save never adds a second relationship.
    final found =
        imported ??
        sheetRels.add(type: RelationshipTypes.drawing, target: target);
    for (final rel in sheetRels.byType(RelationshipTypes.drawing).toList()) {
      if (rel.id != found.id) sheetRels.removeById(rel.id);
    }
    final RelationshipCollection drawingRels = package.relationshipsFor(
      drawingUri,
    );
    final List<String> embedIds = <String>[];
    var mediaIndex = 1;
    var chartIndex = 1;
    for (final SmlDrawing drawing in sheet.drawings) {
      final OfficeVisual visual = drawing.visual;
      if (visual.isChart) {
        final preserve =
            drawing.sourceChartPartUri != null &&
            package.getPart(drawing.sourceChartPartUri!) != null &&
            drawing.sourceChartState == chartState(drawing, sheet);
        final String uri = preserve
            ? drawing.sourceChartPartUri!
            : '/xl/charts/${owner}_chart$chartIndex.xml';
        chartIndex++;
        if (!preserve) {
          _writePart(
            package,
            uri,
            OfficeContentTypes.drawingChart,
            utf8.encode(chartState(drawing, sheet, includeValues: true)),
          );
        } else if (drawing.sourceFromA1 != null &&
            (drawing.sourceSheetName == null ||
                drawing.sourceSheetName == sheet.name ||
                (workbook?.sheets.any(
                      (source) => source.name == drawing.sourceSheetName,
                    ) ??
                    false))) {
          // Keep native series/title formulas and metadata, while publishing
          // the evaluated values of the modeled first series in its cache.
          final part = package.getPart(uri)!;
          final native = XmlDocument.parse(part.readText());
          final generated = XmlDocument.parse(
            chartState(drawing, sheet, includeValues: true),
          );
          XmlElement? first(XmlElement node, String name) {
            if (node.localName == name) return node;
            for (final child in node.childElements) {
              final found = first(child, name);
              if (found != null) return found;
            }
            return null;
          }

          final target = first(
            native.root!,
            'ser',
          )?.firstChild('val')?.firstChild('numRef');
          final cache = first(
            generated.root!,
            'ser',
          )?.firstChild('val')?.firstChild('numRef')?.firstChild('numCache');
          if (target != null && cache != null) {
            final copy = cache.copy();
            void prefix(XmlElement node) {
              node.prefix = target.prefix;
              for (final child in node.childElements) {
                prefix(child);
              }
            }

            prefix(copy);
            final existing = target.firstChild('numCache');
            if (existing == null) {
              target.addChild(copy);
              part.writeText(native.toXmlString());
            } else {
              // A native cache can be sparse and carry a producer-specific
              // number format. Refresh only mapped values, retaining point
              // indices, missing points, formatting and extension metadata.
              final count = int.tryParse(
                copy.firstChild('ptCount')?.getAttribute('val') ?? '',
              );
              final oldCount = int.tryParse(
                existing.firstChild('ptCount')?.getAttribute('val') ?? '',
              );
              final values = <int, String>{};
              for (final point in copy.childrenNamed('pt')) {
                final index = int.tryParse(point.getAttribute('idx') ?? '');
                if (index != null && point.firstChild('v') != null) {
                  values[index] = point.firstChild('v')!.text;
                }
              }
              final points = existing.childrenNamed('pt');
              final indices = [
                for (final point in points)
                  int.tryParse(point.getAttribute('idx') ?? ''),
              ];
              if (count != null &&
                  count == oldCount &&
                  indices.toSet().length == indices.length &&
                  indices.every(
                    (index) => index != null && values.containsKey(index),
                  ) &&
                  points.every((point) => point.firstChild('v') != null)) {
                for (var index = 0; index < points.length; index++) {
                  points[index].firstChild('v')!.text = values[indices[index]]!;
                }
                part.writeText(native.toXmlString());
              }
            }
          }
        }
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
            '/xl/media/${owner}_image$mediaIndex${WordLikeMedia.extensionOf(mime)}';
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

  /// Native charts are reusable while their editable projection is unchanged.
  /// Optional names calculate a rename snapshot without mutating the drawing.
  static String chartState(
    SmlDrawing drawing,
    SmlWorksheet sheet, {
    String? ownerName,
    String? sourceName,
    bool includeValues = false,
  }) {
    // Cell-driven values are refreshed independently; changing source data
    // must not discard other native chart series or title formulas.
    final visual = !includeValues && drawing.sourceFromA1 != null
        ? drawing.visual.copy()
        : drawing.visual;
    if (!includeValues && drawing.sourceFromA1 != null) {
      for (var i = 0; i < visual.points.length; i++) {
        visual.points[i] = ChartPoint(
          label: '',
          value: 0,
          color: visual.points[i].color,
        );
      }
    }
    return _bindChartRefs(
      _chartXml(visual, sheetRtl: sheet.rightToLeft),
      SmlDrawing(
        visual: drawing.visual,
        sourceFromA1: drawing.sourceFromA1,
        sourceToA1: drawing.sourceToA1,
        sourceSheetName: sourceName ?? drawing.sourceSheetName,
        labelsFromA1: drawing.labelsFromA1,
        labelsToA1: drawing.labelsToA1,
      ),
      ownerName ?? sheet.name,
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
    String sheetUri, {
    List<String> themeColors = const [],
  }) {
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
      ..addAll(
        _parse(part.readText(), package, drawingUri, sheet, themeColors),
      );
  }

  static List<SmlDrawing> _parse(
    String xml,
    OpcPackage package,
    String drawingUri,
    SmlWorksheet sheet,
    List<String> themeColors,
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
    int? endCol;
    int? endRow;
    var endColOff = 0;
    var endRowOff = 0;
    String? marker;
    String? editAs;
    var twoCell = false;
    final PictureAdjust adj = PictureAdjust();
    String name = 'Picture';
    void flush() {
      OfficeVisual? visual;
      String? sourceChartUri;
      ({String? sheet, SmlRange range})? values;
      ({String? sheet, SmlRange range})? labels;
      SmlDrawingMarker? twoCellEnd;
      final lastCol = endCol;
      final lastRow = endRow;
      if (twoCell &&
          lastCol != null &&
          lastCol >= col &&
          lastCol < SmlWorksheet.excelColumnCount &&
          lastRow != null &&
          lastRow >= row &&
          lastRow < SmlWorksheet.excelRowCount &&
          col >= 0 &&
          row >= 0) {
        final width =
            sheet.columnLeft(lastCol) -
            sheet.columnLeft(col) +
            DrawingmlVisualIo.emuToPixels(endColOff - colOff);
        final height =
            sheet.rowTop(lastRow) -
            sheet.rowTop(row) +
            DrawingmlVisualIo.emuToPixels(endRowOff - rowOff);
        if (width > 0 && height > 0) {
          cx = DrawingmlVisualIo.pixelsToEmu(width);
          cy = DrawingmlVisualIo.pixelsToEmu(height);
          twoCellEnd = (
            col: lastCol,
            row: lastRow,
            colEmu: endColOff,
            rowEmu: endRowOff,
          );
        }
      }
      final String? chartRel = chartId;
      final String? embedRel = embed;
      if (chartRel != null) {
        final rels = package.relationshipsFor(drawingUri);
        final rel = rels.byId(chartRel);
        if (rel != null && rel.targetMode != RelationshipTargetMode.external) {
          sourceChartUri = rels.resolve(rel);
        }
        final String? chartXml = _readChartPart(package, drawingUri, chartRel);
        if (chartXml != null) {
          visual = DrawingmlVisualIo.parseChart(
            chartXml,
            name: name,
            width: cx > 0 ? DrawingmlVisualIo.emuToPoints(cx) : 360,
            height: cy > 0 ? DrawingmlVisualIo.emuToPoints(cy) : 180,
          );
          if (visual.kind == OfficeVisualKind.chartLine) {
            _projectLineChart(chartXml, visual, name);
          } else if (visual.kind == OfficeVisualKind.chartPie) {
            _projectPieChart(chartXml, visual, themeColors);
          }
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
            sourceChartPartUri: sourceChartUri,
            importedEndMarker: twoCellEnd,
            twoCellEditAs: editAs,
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
      endCol = endRow = null;
      endColOff = endRowOff = 0;
      marker = editAs = null;
      twoCell = false;
      adj.reset();
      name = 'Picture';
    }

    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 'from' || reader.localName == 'to') {
          marker = null;
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
        case 'twoCellAnchor':
          twoCell = true;
          editAs = reader.getAttribute('editAs');
        case 'from':
        case 'to':
          marker = reader.isEmptyElement ? null : reader.localName;
        case 'col':
          if (marker == 'from') col = int.tryParse(_text(reader)) ?? col;
          if (marker == 'to') endCol = int.tryParse(_text(reader));
        case 'row':
          if (marker == 'from') row = int.tryParse(_text(reader)) ?? row;
          if (marker == 'to') endRow = int.tryParse(_text(reader));
        case 'colOff':
          if (marker == 'from') colOff = int.tryParse(_text(reader)) ?? colOff;
          if (marker == 'to') endColOff = int.tryParse(_text(reader)) ?? 0;
        case 'rowOff':
          if (marker == 'from') rowOff = int.tryParse(_text(reader)) ?? rowOff;
          if (marker == 'to') endRowOff = int.tryParse(_text(reader)) ?? 0;
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

  static void _applyTitleStyle(XmlElement? node, ChartDisplay display) {
    final rich = node?.firstChild('tx')?.firstChild('rich');
    final paragraph = rich?.firstChild('p');
    final run = paragraph?.firstChild('r')?.firstChild('rPr');
    final defaults = paragraph?.firstChild('pPr')?.firstChild('defRPr');
    final size = int.tryParse(
      run?.getAttribute('sz') ?? defaults?.getAttribute('sz') ?? '',
    );
    if (size != null && size >= 600 && size <= 7200) {
      display.titleSize = size / 100;
    }
    final bold = run?.getAttribute('b') ?? defaults?.getAttribute('b');
    if (bold != null) display.titleBold = bold == '1' || bold == 'true';
    display.titleFamily =
        run?.firstChild('latin')?.getAttribute('typeface') ??
        defaults?.firstChild('latin')?.getAttribute('typeface');
  }

  static void _applyLegendStyle(XmlElement? chart, ChartDisplay display) {
    final properties = chart
        ?.firstChild('legend')
        ?.firstChild('txPr')
        ?.firstChild('p')
        ?.firstChild('pPr')
        ?.firstChild('defRPr');
    final size = int.tryParse(properties?.getAttribute('sz') ?? '');
    if (size != null && size >= 600 && size <= 3600) {
      display.legendSize = size / 100;
    }
    display.legendFamily = properties
        ?.firstChild('latin')
        ?.getAttribute('typeface');
  }

  static void _projectPieChart(
    String xml,
    OfficeVisual visual,
    List<String> themeColors,
  ) {
    final chart = XmlDocument.parse(xml).root?.firstChild('chart');
    final pie = chart?.firstChild('plotArea')?.firstChild('pieChart');
    final series = pie?.firstChild('ser');
    if (series == null) return;
    _applyTitleStyle(chart?.firstChild('title'), visual.chart);
    _applyLegendStyle(chart, visual.chart);
    final explicit = <int, String>{};
    for (final point in series.childrenNamed('dPt')) {
      final index = int.tryParse(
        point.firstChild('idx')?.getAttribute('val') ?? '',
      );
      final fill = point.firstChild('spPr')?.firstChild('solidFill');
      final rgb = fill?.firstChild('srgbClr')?.getAttribute('val');
      final scheme = fill?.firstChild('schemeClr')?.getAttribute('val');
      final accent = scheme != null && scheme.startsWith('accent')
          ? int.tryParse(scheme.substring(6))
          : null;
      if (index == null || index < 0) continue;
      if (rgb != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(rgb)) {
        explicit[index] = rgb.toUpperCase();
      } else if (accent != null &&
          accent >= 1 &&
          accent <= 6 &&
          accent + 3 < themeColors.length) {
        explicit[index] = themeColors[accent + 3];
      }
    }
    final colors = themeColors.length >= 10
        ? themeColors.sublist(4, 10)
        : VisualPalette.fills;
    for (var i = 0; i < visual.points.length; i++) {
      final color = explicit[i] ?? colors[i % colors.length];
      visual.points[i] = visual.points[i].copyWith(color: color);
    }
  }

  static void _projectLineChart(String xml, OfficeVisual visual, String name) {
    final chart = XmlDocument.parse(xml).root?.firstChild('chart');
    final plot = chart?.firstChild('plotArea');
    final line = plot?.firstChild('lineChart');
    if (chart == null || plot == null || line == null) return;
    final grouping = line.firstChild('grouping')?.getAttribute('val');
    if (grouping != null && grouping != 'standard') return;

    String titleText(XmlElement? title) {
      final text = title?.firstChild('tx');
      final cached = text?.firstChild('strRef')?.firstChild('strCache');
      return (text?.firstChild('rich')?.text ??
              cached?.firstChild('pt')?.firstChild('v')?.text ??
              '')
          .trim();
    }

    const maxCategories = 16384;
    Map<int, String> points(XmlElement? cache) {
      final result = <int, String>{};
      if (cache == null) return result;
      for (final point in cache.childrenNamed('pt')) {
        final index = int.tryParse(point.getAttribute('idx') ?? '');
        final value = point.firstChild('v')?.text;
        if (index != null &&
            index >= 0 &&
            index < maxCategories &&
            value != null) {
          result[index] = value;
        }
      }
      return result;
    }

    XmlElement? cacheFor(XmlElement? region) {
      final source = region?.childElements.firstOrNull;
      return switch (source?.localName) {
        'strRef' => source?.firstChild('strCache'),
        'numRef' => source?.firstChild('numCache'),
        'strLit' || 'numLit' => source,
        _ => null,
      };
    }

    final labels = <int, String>{};
    final series = <ChartSeries>[];
    final labelFormats = <String?>[];
    var categoryCount = 0;
    var sampleBudget = 65536;
    final blanks = chart.firstChild('dispBlanksAs')?.getAttribute('val');
    for (final item in line.childrenNamed('ser')) {
      final categoryCache = cacheFor(item.firstChild('cat'));
      final valueCache = cacheFor(item.firstChild('val'));
      final categories = points(categoryCache);
      final values = points(valueCache);
      for (final entry in categories.entries) {
        labels.putIfAbsent(entry.key, () => entry.value);
      }
      final declared =
          int.tryParse(
            valueCache?.firstChild('ptCount')?.getAttribute('val') ?? '',
          ) ??
          0;
      var size = declared.clamp(0, maxCategories);
      for (final index in [...categories.keys, ...values.keys]) {
        if (index >= size) size = index + 1;
      }
      sampleBudget -= blanks == 'zero' ? size : values.length;
      if (sampleBudget < 0) return;
      if (size > categoryCount) categoryCount = size;
      final title = item.firstChild('tx');
      final seriesName =
          title?.firstChild('v')?.text ?? points(cacheFor(title))[0] ?? '';
      final rgb = item
          .firstChild('spPr')
          ?.firstChild('ln')
          ?.firstChild('solidFill')
          ?.firstChild('srgbClr')
          ?.getAttribute('val');
      final color = rgb != null && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(rgb)
          ? rgb.toUpperCase()
          : VisualPalette.fills[series.length % VisualPalette.fills.length];
      final samples = <ChartPoint>[];
      final indices = blanks == 'zero'
          ? Iterable<int>.generate(size)
          : (values.keys.toList()..sort());
      for (final index in indices) {
        final value =
            double.tryParse(values[index] ?? '') ??
            (blanks == 'zero' ? 0.0 : null);
        if (value != null && value.isFinite) {
          samples.add(
            ChartPoint(
              label: categories[index] ?? '',
              value: value,
              x: index.toDouble(),
              color: color,
            ),
          );
        }
      }
      if (samples.isEmpty) continue;
      final labelSettings = item.firstChild('dLbls');
      final sharedSettings = line.firstChild('dLbls');
      final show =
          labelSettings?.firstChild('showVal')?.getAttribute('val') ??
          sharedSettings?.firstChild('showVal')?.getAttribute('val');
      labelFormats.add(
        show == '1' || show == 'true'
            ? labelSettings?.firstChild('numFmt')?.getAttribute('formatCode') ??
                  sharedSettings
                      ?.firstChild('numFmt')
                      ?.getAttribute('formatCode') ??
                  valueCache?.firstChild('formatCode')?.text ??
                  '#,##0'
            : null,
      );
      series.add(
        ChartSeries(
          name: seriesName.isEmpty ? 'Series ${series.length + 1}' : seriesName,
          points: List.unmodifiable(samples),
          color: color,
        ),
      );
    }

    _applyTitleStyle(chart.firstChild('title'), visual.chart);
    _applyLegendStyle(chart, visual.chart);
    final axis = plot.firstChild('valAx');
    final categoryAxis = plot.firstChild('catAx');
    final title = titleText(chart.firstChild('title'));
    visual.title = title.isEmpty ? name : title;
    visual.chart
      ..showTitle = chart.firstChild('title') != null
      ..categoryTitle = titleText(plot.firstChild('catAx')?.firstChild('title'))
      ..valueTitle = titleText(plot.firstChild('valAx')?.firstChild('title'));
    if (series.isNotEmpty) {
      visual.importedLineChart = OfficeLineChart(
        categories: [
          for (var i = 0; i < categoryCount; i++) labels[i] ?? '${i + 1}',
        ],
        series: series,
        labelFormats: labelFormats,
        locale:
            chart.parent?.firstChild('lang')?.getAttribute('val') ?? 'en_US',
        connectGaps: blanks == 'span',
        betweenCategories:
            axis?.firstChild('crossBetween')?.getAttribute('val') == 'between',
        labelsAtZero:
            axis?.firstChild('crosses')?.getAttribute('val') == 'autoZero' &&
            categoryAxis?.firstChild('tickLblPos')?.getAttribute('val') ==
                'nextTo',
      );
    }
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
    final end = drawing.twoCellEnd;
    w.writeStartElement(
      end == null ? 'oneCellAnchor' : 'twoCellAnchor',
      prefix: 'xdr',
    );
    if (end != null && drawing.twoCellEditAs != null) {
      w.writeAttribute('editAs', drawing.twoCellEditAs!);
    }
    _writeMarker(w, 'from', (
      col: drawing.col,
      row: drawing.row,
      colEmu: DrawingmlVisualIo.pixelsToEmu(drawing.offsetX),
      rowEmu: DrawingmlVisualIo.pixelsToEmu(drawing.offsetY),
    ));
    if (end != null) {
      _writeMarker(w, 'to', end);
    } else {
      w.writeEmptyElement(
        'ext',
        prefix: 'xdr',
        attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
      );
    }
    if (visual.isChart) {
      _writeChartFrame(w, visual, relationshipId, nvId, cx, cy);
    } else {
      _writePic(w, visual, relationshipId, nvId, cx, cy);
    }
    w.writeEmptyElement('clientData', prefix: 'xdr');
    w.writeEndElement();
  }

  static void _writeMarker(
    XmlWriter writer,
    String name,
    SmlDrawingMarker marker,
  ) {
    writer.writeStartElement(name, prefix: 'xdr');
    for (final (tag, value) in [
      ('col', marker.col),
      ('colOff', marker.colEmu),
      ('row', marker.row),
      ('rowOff', marker.rowEmu),
    ]) {
      writer.writeStartElement(tag, prefix: 'xdr');
      writer.writeText('$value');
      writer.writeEndElement();
    }
    writer.writeEndElement();
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
    DrawingmlVisualIo.writeXfrm(
      w,
      cx: cx,
      cy: cy,
      adj: visual.picture,
      prefix: 'xdr',
    );
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

  static String _bindChartRefs(
    String xml,
    SmlDrawing drawing,
    String sheetName,
  ) {
    if (drawing.sourceFromA1 == null || drawing.sourceToA1 == null) return xml;
    final document = XmlDocument.parse(xml);
    XmlElement? find(XmlElement node, String name) {
      if (node.localName == name) return node;
      for (final c in node.childElements) {
        final match = find(c, name);
        if (match != null) return match;
      }
      return null;
    }

    final series = find(document.root!, 'ser');
    if (series == null) return xml;
    final source = (drawing.sourceSheetName ?? sheetName).replaceAll("'", "''");
    for (final kind in ['cat', 'val']) {
      final from = kind == 'val' ? drawing.sourceFromA1 : drawing.labelsFromA1;
      final to = kind == 'val' ? drawing.sourceToA1 : drawing.labelsToA1;
      if (from == null || to == null) continue;
      final region = series.firstChild(kind);
      if (region == null) continue;
      final literal = region.childElements.firstOrNull;
      final numeric = kind == 'val';
      final reference = XmlElement(
        localName: numeric ? 'numRef' : 'strRef',
        prefix: 'c',
      );
      reference.addChild(
        XmlElement(localName: 'f', prefix: 'c')..addText("'$source'!$from:$to"),
      );
      if (literal != null) {
        final cache = literal.copy()
          ..localName = numeric ? 'numCache' : 'strCache';
        reference.addChild(cache);
      }
      region.children.clear();
      region.addChild(reference);
    }
    return document.toXmlString();
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
