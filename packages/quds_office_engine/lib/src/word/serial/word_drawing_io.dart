import 'dart:convert';
import 'dart:typed_data';

import '../../builders/drawingml_charts.dart';
import '../../builders/image_fit.dart';
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
import '../model/wml_document.dart';
import '../properties/wml_properties.dart';

/// Word inline pictures (`w:drawing` / `wp:inline` / `pic:pic`).
abstract final class WordDrawingIo {
  /// emuPerPoint API.
  static const int emuPerPoint = 12700;

  /// pictureUri API.
  static const String pictureUri =
      'http://schemas.openxmlformats.org/drawingml/2006/picture';

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

  /// pointsToEmu API.
  static int pointsToEmu(double points) =>
      (points.clamp(8, 2000) * emuPerPoint).round();

  /// Position offsets may be 0 (page edge) and as tall as A4.
  static int offsetToEmu(double points) =>
      (points.clamp(-2000, 4000) * emuPerPoint).round();

  /// Shape / picture extent — allows a full A4 edge.
  static int sizeToEmu(double points) =>
      (points.clamp(1, 4000) * emuPerPoint).round();

  /// emuToPoints API.
  static double emuToPoints(int emu) => emu / emuPerPoint;

  /// cropToSrc API.
  static int cropToSrc(double fraction) =>
      (fraction.clamp(0.0, 0.49) * 100000).round();

  /// srcToCrop API.
  static double srcToCrop(String? raw) {
    final int? value = int.tryParse(raw ?? '');
    if (value == null || value <= 0) {
      return 0;
    }
    return (value / 100000).clamp(0.0, 0.49);
  }

  /// syncVisuals API.
  static Map<OfficeVisual, String> syncVisuals(
    Iterable<OfficeVisual> visuals,
    OpcPackage package, {
    String partUri = '/word/document.xml',
    String mediaPrefix = 'image',
  }) {
    final List<WmlVisualImage> images = <WmlVisualImage>[];
    final RelationshipCollection rels = package.relationshipsFor(partUri);
    var chartIndex = 1;
    final Map<OfficeVisual, String> ids = <OfficeVisual, String>{};
    for (final OfficeVisual visual in visuals) {
      if (visual.isChart) {
        final String uri = '/word/charts/chart$chartIndex.xml';
        final String xml = _chartXml(visual);
        chartIndex++;
        if (package.getPart(uri) == null) {
          package.createPart(
            uri,
            OfficeContentTypes.drawingChart,
            utf8.encode(xml),
          );
        } else {
          package.getPart(uri)!.writeText(xml);
        }
        final String target = OpcUris.relativize(partUri, uri);
        PackageRelationship? found;
        for (final PackageRelationship rel in rels.items) {
          if (rel.target == target && rel.type == RelationshipTypes.chart) {
            found = rel;
            break;
          }
        }
        found ??= rels.add(type: RelationshipTypes.chart, target: target);
        ids[visual] = found.id;
        continue;
      }
      images.add(
        WmlVisualImage(bytes: PngBytes.fromVisual(visual), visual: visual),
      );
    }
    final Map<WmlVisualImage, String> raw = syncMedia(
      images,
      package,
      partUri: partUri,
      mediaPrefix: mediaPrefix,
    );
    for (final MapEntry<WmlVisualImage, String> e in raw.entries) {
      ids[e.key.visual] = e.value;
    }
    return ids;
  }

  static String _chartXml(OfficeVisual visual) {
    final String title = visual.title.isEmpty ? 'Chart' : visual.title;
    final List<ChartPoint> points = visual.points.isEmpty
        ? OfficeVisual.sampleSeries()
        : visual.points;
    return switch (visual.kind) {
      OfficeVisualKind.chartPie => DrawingmlCharts.pie(
        title: title,
        series: points,
        rtl: false,
        display: visual.chart,
      ),
      OfficeVisualKind.chartLine => DrawingmlCharts.line(
        title: title,
        series: <ChartSeries>[ChartSeries(name: title, points: points)],
        rtl: false,
        display: visual.chart,
      ),
      OfficeVisualKind.chartBar => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: false,
        display: visual.chart,
      ),
      _ => DrawingmlCharts.bar(
        title: title,
        series: points,
        rtl: false,
        horizontal: false,
        display: visual.chart,
      ),
    };
  }

  /// syncMedia API.
  static Map<WmlVisualImage, String> syncMedia(
    Iterable<WmlVisualImage> images,
    OpcPackage package, {
    String partUri = '/word/document.xml',
    String mediaPrefix = 'image',
  }) {
    final Map<WmlVisualImage, String> ids = <WmlVisualImage, String>{};
    var index = 1;
    for (final WmlVisualImage image in images) {
      final Uint8List bytes = image.bytes;
      final String mime = mimeOf(bytes);
      final String uri = '/word/media/$mediaPrefix$index${extensionOf(mime)}';
      index++;
      final PackagePart? existing = package.getPart(uri);
      if (existing == null) {
        package.createPart(uri, mime, bytes);
      } else {
        existing.writeBytes(bytes);
      }
      final String target = OpcUris.relativize(partUri, uri);
      final RelationshipCollection rels = package.relationshipsFor(partUri);
      PackageRelationship? found;
      for (final PackageRelationship rel in rels.items) {
        if (rel.target == target && rel.type == RelationshipTypes.image) {
          found = rel;
          break;
        }
      }
      found ??= rels.add(type: RelationshipTypes.image, target: target);
      ids[image] = found.id;
    }
    return ids;
  }

  /// writeInline API.
  static void writeInline(
    XmlWriter w, {
    required String relationshipId,
    required OfficeVisual visual,
    required int docPrId,
  }) {
    final int cx = sizeToEmu(visual.width);
    final int cy = sizeToEmu(visual.height);
    final PictureAdjust adj = visual.picture;
    final String name = adj.altTitle.isNotEmpty
        ? adj.altTitle
        : (visual.title.isEmpty ? 'Picture' : visual.title);
    final String descr = adj.altDescription.isNotEmpty
        ? adj.altDescription
        : name;
    w.writeStartElement('p', prefix: 'w');
    w.writeStartElement('r', prefix: 'w');
    w.writeStartElement('drawing', prefix: 'w');
    _writeAnchorOrInline(w, visual: visual, cx: cx, cy: cy);
    w.writeEmptyElement(
      'extent',
      prefix: 'wp',
      attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
    );
    w.writeEmptyElement(
      'effectExtent',
      prefix: 'wp',
      attributes: <String, String>{
        'l': '0',
        't': '0',
        'r': adj.shadow ? '50800' : '0',
        'b': adj.shadow ? '38100' : '0',
      },
    );
    _writeWrap(w, adj);
    w.writeStartElement('docPr', prefix: 'wp');
    w.writeAttribute('id', '$docPrId');
    w.writeAttribute('name', name);
    w.writeAttribute('descr', descr);
    w.writeEndElement();
    w.writeStartElement('cNvGraphicFramePr', prefix: 'wp');
    w.writeEmptyElement(
      'graphicFrameLocks',
      prefix: 'a',
      attributes: <String, String>{
        'noChangeAspect': adj.lockAspect ? '1' : '0',
      },
    );
    w.writeEndElement();
    w.writeStartElement('graphic', prefix: 'a');
    w.writeStartElement('graphicData', prefix: 'a');
    w.writeAttribute('uri', pictureUri);
    w.writeStartElement('pic', prefix: 'pic');
    w.writeStartElement('nvPicPr', prefix: 'pic');
    w.writeStartElement('cNvPr', prefix: 'pic');
    w.writeAttribute('id', '0');
    w.writeAttribute('name', name);
    w.writeAttribute('descr', descr);
    w.writeEndElement();
    w.writeStartElement('cNvPicPr', prefix: 'pic');
    w.writeEmptyElement(
      'picLocks',
      prefix: 'a',
      attributes: <String, String>{
        'noChangeAspect': adj.lockAspect ? '1' : '0',
      },
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('blipFill', prefix: 'pic');
    DrawingmlVisualIo.writeBlip(w, relationshipId: relationshipId, adj: adj);
    DrawingmlVisualIo.writeSrcRect(w, adj);
    w.writeStartElement('stretch', prefix: 'a');
    w.writeEmptyElement('fillRect', prefix: 'a');
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('spPr', prefix: 'pic');
    DrawingmlVisualIo.writeXfrm(w, cx: cx, cy: cy, adj: adj);
    w.writeStartElement('prstGeom', prefix: 'a');
    w.writeAttribute('prst', 'rect');
    w.writeEmptyElement('avLst', prefix: 'a');
    w.writeEndElement();
    DrawingmlVisualIo.writeLine(w, adj);
    DrawingmlVisualIo.writeShadow(w, adj);
    w.writeEndElement(); // pic:spPr
    w.writeEndElement(); // pic:pic
    w.writeEndElement(); // a:graphicData
    w.writeEndElement(); // a:graphic
    w.writeEndElement(); // wp:inline or wp:anchor
    w.writeEndElement(); // w:drawing
    w.writeEndElement(); // w:r
    w.writeEndElement(); // w:p
  }

  static void _writeAnchorOrInline(
    XmlWriter w, {
    required OfficeVisual visual,
    required int cx,
    required int cy,
  }) {
    final PictureAdjust adj = visual.picture;
    final bool floating = adj.wrap != PictureWrap.inline;
    if (!floating) {
      w.writeStartElement('inline', prefix: 'wp');
      w.writeAttribute('distT', '${pointsToEmu(adj.wrapDistT)}');
      w.writeAttribute('distB', '${pointsToEmu(adj.wrapDistB)}');
      w.writeAttribute('distL', '${pointsToEmu(adj.wrapDistL)}');
      w.writeAttribute('distR', '${pointsToEmu(adj.wrapDistR)}');
      return;
    }
    w.writeStartElement('anchor', prefix: 'wp');
    w.writeAttribute('distT', '${pointsToEmu(adj.wrapDistT)}');
    w.writeAttribute('distB', '${pointsToEmu(adj.wrapDistB)}');
    w.writeAttribute('distL', '${pointsToEmu(adj.wrapDistL)}');
    w.writeAttribute('distR', '${pointsToEmu(adj.wrapDistR)}');
    w.writeAttribute('simplePos', '0');
    w.writeAttribute('relativeHeight', '251658240');
    w.writeAttribute('behindDoc', adj.wrap == PictureWrap.behind ? '1' : '0');
    w.writeAttribute('locked', '0');
    w.writeAttribute('layoutInCell', '1');
    w.writeAttribute('allowOverlap', '1');
    w.writeEmptyElement(
      'simplePos',
      prefix: 'wp',
      attributes: <String, String>{'x': '0', 'y': '0'},
    );
    w.writeStartElement('positionH', prefix: 'wp');
    w.writeAttribute(
      'relativeFrom',
      adj.wrap == PictureWrap.behind || adj.wrap == PictureWrap.inFront
          ? 'page'
          : 'column',
    );
    w.writeStartElement('posOffset', prefix: 'wp');
    w.writeText('${offsetToEmu(visual.offsetX)}');
    w.writeEndElement();
    w.writeEndElement();
    w.writeStartElement('positionV', prefix: 'wp');
    w.writeAttribute(
      'relativeFrom',
      visual.picture.wrap == PictureWrap.behind ||
              visual.picture.wrap == PictureWrap.inFront
          ? 'page'
          : 'paragraph',
    );
    w.writeStartElement('posOffset', prefix: 'wp');
    w.writeText('${offsetToEmu(visual.offsetY)}');
    w.writeEndElement();
    w.writeEndElement();
  }

  static void _writeWrap(XmlWriter w, PictureAdjust adj) {
    if (adj.wrap == PictureWrap.inline) {
      return;
    }
    switch (adj.wrap) {
      case PictureWrap.square:
        w.writeEmptyElement(
          'wrapSquare',
          prefix: 'wp',
          attributes: <String, String>{'wrapText': 'bothSides'},
        );
      case PictureWrap.tight:
        w.writeEmptyElement(
          'wrapTight',
          prefix: 'wp',
          attributes: <String, String>{'wrapText': 'bothSides'},
        );
      case PictureWrap.through:
        w.writeEmptyElement(
          'wrapThrough',
          prefix: 'wp',
          attributes: <String, String>{'wrapText': 'bothSides'},
        );
      case PictureWrap.topAndBottom:
        w.writeEmptyElement('wrapTopAndBottom', prefix: 'wp');
      case PictureWrap.behind:
      case PictureWrap.inFront:
        w.writeEmptyElement('wrapNone', prefix: 'wp');
      case PictureWrap.inline:
        break;
    }
  }

  /// writeChart API.
  static void writeChart(
    XmlWriter w, {
    required String relationshipId,
    required OfficeVisual visual,
    required int docPrId,
  }) {
    final int cx = sizeToEmu(visual.width);
    final int cy = sizeToEmu(visual.height);
    final String name = visual.title.isEmpty ? 'Chart' : visual.title;
    w.writeStartElement('p', prefix: 'w');
    w.writeStartElement('r', prefix: 'w');
    w.writeStartElement('drawing', prefix: 'w');
    _writeAnchorOrInline(w, visual: visual, cx: cx, cy: cy);
    w.writeEmptyElement(
      'extent',
      prefix: 'wp',
      attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
    );
    _writeWrap(w, visual.picture);
    w.writeStartElement('docPr', prefix: 'wp');
    w.writeAttribute('id', '$docPrId');
    w.writeAttribute('name', name);
    w.writeAttribute('descr', name);
    w.writeEndElement();
    w.writeStartElement('graphic', prefix: 'a');
    w.writeStartElement('graphicData', prefix: 'a');
    w.writeAttribute('uri', OfficeNamespaces.c);
    w.writeEmptyElement(
      'chart',
      prefix: 'c',
      attributes: <String, String>{'r:id': relationshipId},
    );
    w.writeEndElement(); // a:graphicData
    w.writeEndElement(); // a:graphic
    w.writeEndElement(); // wp:inline or wp:anchor
    w.writeEndElement(); // w:drawing
    w.writeEndElement(); // w:r
    w.writeEndElement(); // w:p
  }

  /// read API.
  static OfficeVisual? read(
    XmlPullReader reader,
    OpcPackage package,
    String docUri,
  ) {
    final WmlBlock? block = readBlock(reader, package, docUri);
    return block is WmlVisual ? block.visual : null;
  }

  /// Reads a picture, chart, or absolutely positioned frame.
  static WmlBlock? readBlock(
    XmlPullReader reader,
    OpcPackage package,
    String docUri, {
    WmlParagraph Function(XmlPullReader reader)? readParagraph,
  }) {
    if (reader.localName != 'drawing') {
      return null;
    }
    String? embed;
    String? chartId;
    String name = 'Picture';
    String descr = '';
    var cx = 0;
    var cy = 0;
    var offsetX = 0.0;
    var offsetY = 0.0;
    var verticalPos = false;
    var behindDoc = false;
    var wrap = PictureWrap.inline;
    var sawShape = false;
    var inSolidFill = false;
    var inLine = false;
    var frameAnchor = WmlFrameAnchor.page;
    var frameWrap = WmlFrameWrap.none;
    String? fill;
    String? stroke;
    final List<WmlBlock> frameBlocks = <WmlBlock>[];
    final PictureAdjust adj = PictureAdjust();
    if (!reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType == XmlEventType.endElement) {
          if (reader.localName == 'solidFill') {
            inSolidFill = false;
          } else if (reader.localName == 'ln') {
            inLine = false;
          }
          continue;
        }
        if (reader.eventType != XmlEventType.startElement) {
          continue;
        }
        if (reader.localName == 'wsp' ||
            reader.localName == 'txbx' ||
            reader.localName == 'txbxContent') {
          sawShape = true;
        }
        if (reader.localName == 'inline') {
          wrap = PictureWrap.inline;
          _readWrapDist(adj, reader);
        } else if (reader.localName == 'anchor') {
          behindDoc = reader.getAttribute('behindDoc') == '1';
          wrap = behindDoc ? PictureWrap.behind : PictureWrap.inFront;
          _readWrapDist(adj, reader);
        } else if (reader.localName.startsWith('wrap')) {
          wrap = DrawingmlVisualIo.wrapFromDrawing(
            localName: reader.localName,
            behindDoc: behindDoc,
          );
          if (reader.localName == 'wrapSquare' ||
              reader.localName == 'wrapTight' ||
              reader.localName == 'wrapTopAndBottom') {
            frameWrap = WmlFrameWrap.square;
          }
        } else if (reader.localName == 'positionH') {
          verticalPos = false;
          if (reader.getAttribute('relativeFrom') == 'margin') {
            frameAnchor = WmlFrameAnchor.margin;
          }
        } else if (reader.localName == 'positionV') {
          verticalPos = true;
        } else if (reader.localName == 'posOffset') {
          final String text = _elementText(reader);
          final int? emu = int.tryParse(text);
          if (emu != null) {
            final double points = emuToPoints(emu);
            if (verticalPos) {
              offsetY = points;
            } else {
              offsetX = points;
            }
          }
        } else if (reader.localName == 'blip') {
          embed =
              reader.getAttribute('embed', namespaceUri: OfficeNamespaces.r) ??
              reader.getAttribute('embed') ??
              embed;
        } else if (reader.localName == 'lum') {
          DrawingmlVisualIo.applyLum(adj, reader);
        } else if (reader.localName == 'alphaModFix') {
          adj.transparency = DrawingmlVisualIo.alphaToTransparency(
            reader.getAttribute('amt'),
          );
        } else if (reader.localName == 'outerShdw') {
          adj.shadow = true;
        } else if (reader.localName == 'solidFill') {
          inSolidFill = true;
        } else if (reader.localName == 'ln') {
          inLine = true;
          final int? wEmu = int.tryParse(reader.getAttribute('w') ?? '');
          if (wEmu != null) {
            adj.borderWidth = DrawingmlVisualIo.emuToBorder(wEmu);
          }
        } else if (reader.localName == 'srgbClr') {
          final String? val = reader.getAttribute('val');
          if (val != null && val.isNotEmpty) {
            if (inLine) {
              stroke = val.toUpperCase();
              if (adj.borderWidth > 0) {
                adj.borderColor = val;
              }
            } else if (inSolidFill) {
              fill = val.toUpperCase();
            }
          }
        } else if (reader.localName == 'p' &&
            reader.namespaceUri == OfficeNamespaces.w &&
            readParagraph != null) {
          frameBlocks.add(readParagraph(reader));
        } else if (reader.localName == 'graphicFrameLocks' ||
            reader.localName == 'picLocks') {
          final String? lock = reader.getAttribute('noChangeAspect');
          adj.lockAspect = lock != '0' && lock?.toLowerCase() != 'false';
        } else if (reader.localName == 'chart' &&
            (reader.prefix == 'c' ||
                reader.namespaceUri == OfficeNamespaces.c)) {
          chartId =
              reader.getAttribute('id', namespaceUri: OfficeNamespaces.r) ??
              reader.getAttribute('id') ??
              chartId;
        } else if (reader.localName == 'extent' || reader.localName == 'ext') {
          cx = int.tryParse(reader.getAttribute('cx') ?? '') ?? cx;
          cy = int.tryParse(reader.getAttribute('cy') ?? '') ?? cy;
        } else if (reader.localName == 'docPr' || reader.localName == 'cNvPr') {
          name = reader.getAttribute('name') ?? name;
          descr = reader.getAttribute('descr') ?? descr;
        } else if (reader.localName == 'srcRect') {
          DrawingmlVisualIo.applySrcRect(adj, reader);
        } else if (reader.localName == 'xfrm') {
          DrawingmlVisualIo.applyXfrm(adj, reader);
        }
      }
    }
    adj
      ..wrap = wrap
      ..altTitle = name
      ..altDescription = descr;
    if (chartId != null) {
      final OfficeVisual? chart = _readChart(
        package,
        docUri,
        chartId,
        name: name,
        cx: cx,
        cy: cy,
      );
      return chart == null ? null : WmlVisual(visual: chart);
    }
    if (embed != null) {
      final PackageRelationship? rel = package
          .relationshipsFor(docUri)
          .byId(embed);
      if (rel != null && rel.targetMode == RelationshipTargetMode.internal) {
        final String target = package.relationshipsFor(docUri).resolve(rel);
        final PackagePart? part = package.getPart(target);
        if (part != null) {
          final Uint8List bytes = part.readBytes();
          if (bytes.isNotEmpty) {
            final ImageSize? size = ImageFit.readSize(bytes);
            return WmlVisual(
              visual: OfficeVisual(
                kind: OfficeVisualKind.picture,
                title: name,
                imageBytes: bytes,
                width: cx > 0
                    ? emuToPoints(cx)
                    : (size?.widthPx.toDouble() ?? 240),
                height: cy > 0
                    ? emuToPoints(cy)
                    : (size?.heightPx.toDouble() ?? 140),
                offsetX: offsetX,
                offsetY: offsetY,
                picture: adj,
              ),
            );
          }
        }
      }
    }
    if (sawShape) {
      return WmlFrame(
        x: offsetX,
        y: offsetY,
        width: cx > 0 ? emuToPoints(cx) : 200,
        height: cy > 0 ? emuToPoints(cy) : 120,
        anchor: frameAnchor,
        wrap: frameWrap,
        fillColor: fill,
        strokeColor: stroke,
        blocks: frameBlocks,
      );
    }
    return null;
  }

  static void _readWrapDist(PictureAdjust adj, XmlPullReader reader) {
    adj.wrapDistT = emuToPoints(
      int.tryParse(reader.getAttribute('distT') ?? '') ?? 0,
    );
    adj.wrapDistB = emuToPoints(
      int.tryParse(reader.getAttribute('distB') ?? '') ?? 0,
    );
    adj.wrapDistL = emuToPoints(
      int.tryParse(reader.getAttribute('distL') ?? '') ?? 0,
    );
    adj.wrapDistR = emuToPoints(
      int.tryParse(reader.getAttribute('distR') ?? '') ?? 0,
    );
  }

  static OfficeVisual? _readChart(
    OpcPackage package,
    String docUri,
    String relationshipId, {
    required String name,
    required int cx,
    required int cy,
  }) {
    final PackageRelationship? rel = package
        .relationshipsFor(docUri)
        .byId(relationshipId);
    if (rel == null || rel.targetMode != RelationshipTargetMode.internal) {
      return null;
    }
    final String target = package.relationshipsFor(docUri).resolve(rel);
    final PackagePart? part = package.getPart(target);
    if (part == null) {
      return null;
    }
    return DrawingmlVisualIo.parseChart(
      part.readText(),
      name: name,
      width: cx > 0 ? emuToPoints(cx) : 360,
      height: cy > 0 ? emuToPoints(cy) : 180,
    );
  }

  static String _elementText(XmlPullReader reader) {
    if (reader.isEmptyElement) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = reader.depth;
    while (reader.next() && reader.depth >= depth) {
      if (reader.eventType == XmlEventType.characters ||
          reader.eventType == XmlEventType.cdata) {
        buffer.write(reader.text);
      }
    }
    return buffer.toString();
  }
}

/// Class WmlVisualImage.
class WmlVisualImage {
  /// WmlVisualImage API.
  WmlVisualImage({required this.bytes, required this.visual});

  /// bytes API.
  final Uint8List bytes;

  /// visual API.
  final OfficeVisual visual;
}
