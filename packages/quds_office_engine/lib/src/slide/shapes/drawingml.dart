import '../../visual/drawingml_visual_io.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../anim/pml_motion_io.dart';
import '../model/pml_arrange.dart';
import '../model/pml_presentation.dart';
import 'slide_rich_text.dart';

/// parseSlideShapes helper.
///
/// [colors] maps scheme color names (`accent1`, `tx1`, `bg1`, …) to hex so
/// `a:schemeClr` and `p:style` references resolve; [positioned] collects the
/// shapes that carry their own `xfrm` offset or extent.
List<PmlShape> parseSlideShapes(
  String xml, {
  Map<String, String> colors = const <String, String>{},
  Set<PmlShape>? positioned,
}) {
  /// shapes API.
  final List<PmlShape> shapes = <PmlShape>[];

  /// reader API.
  final XmlPullReader reader = XmlPullReader(xml);

  /// current API.
  PmlShape? current;

  /// fillPending API.
  var fillPending = false;
  var inGradFill = false;
  int? shapePropertiesDepth;
  int? gradientDepth;
  int? gradientStopDepth;
  int? gradientPathDepth;
  final List<PmlGradientStop> gradientStops = <PmlGradientStop>[];
  double? gradientStopPosition;
  double gradientAngle = 0;
  var gradientRadial = false;
  var gradientCentered = false;
  var gradientDefaultTile = true;
  var gradientIsLinear = true;

  /// textFillPending API.
  var textFillPending = false;

  /// strokePending API.
  var strokePending = false;

  /// inSpPr API.
  var inSpPr = false;

  /// inTxBody API.
  var inTxBody = false;

  /// inLn API.
  var inLn = false;

  /// inTbl API.
  var inTbl = false;

  /// inTcPr API.
  var inTcPr = false;

  /// currentRow API.
  List<PmlTableCell>? currentRow;

  /// currentCell API.
  PmlTableCell? currentCell;
  var paragraphCount = 0;
  var cellParagraphCount = 0;
  int? currentGroupId;
  var nextGroupId = 1;
  var inXfrm = false;
  var inStyle = false;
  var explicitFill = false;
  var explicitLine = false;
  String? styleRef;
  var hiddenDepth = 0;
  while (reader.next()) {
    // `a14:hiddenFill` / `hiddenLine` / `hiddenEffects` record the formatting
    // PowerPoint hides behind the current fallback. They must never win over
    // the visible `noFill` / `ln` / effect list.
    if (hiddenDepth > 0) {
      if (reader.eventType == XmlEventType.endElement &&
          reader.depth <= hiddenDepth) {
        hiddenDepth = 0;
      }
      continue;
    }
    if (reader.eventType == XmlEventType.startElement &&
        reader.localName.startsWith('hidden')) {
      hiddenDepth = reader.depth;
      continue;
    }
    if (reader.eventType == XmlEventType.endElement) {
      if (reader.localName == 'xfrm') {
        inXfrm = false;
      } else if (reader.localName == 'style') {
        inStyle = false;
        styleRef = null;
      } else if (reader.localName == 'path' &&
          gradientPathDepth != null &&
          reader.depth == gradientPathDepth - 1) {
        gradientPathDepth = null;
      } else if (reader.localName == 'gradFill' &&
          inGradFill &&
          gradientDepth != null &&
          reader.depth == gradientDepth - 1) {
        if (current != null && gradientStops.isNotEmpty) {
          final List<PmlGradientStop> stops = <PmlGradientStop>[
            ...gradientStops,
          ]..sort((a, b) => a.position.compareTo(b.position));
          current.gradient =
              gradientIsLinear ||
                  gradientRadial && gradientCentered && gradientDefaultTile
              ? PmlGradientFill(
                  stops: stops,
                  angleDegrees: gradientAngle,
                  radial: gradientRadial,
                )
              : null;
          current.fillColor = stops.first.color;
        }
        inGradFill = false;
        gradientDepth = null;
        gradientStopDepth = null;
        gradientPathDepth = null;
        gradientStops.clear();
        gradientStopPosition = null;
        fillPending = false;
      } else if (reader.localName == 'spPr') {
        inSpPr = false;
        shapePropertiesDepth = null;
        inLn = false;
        fillPending = false;
        inGradFill = false;
        gradientDepth = null;
        gradientStopDepth = null;
        gradientPathDepth = null;
        gradientStops.clear();
        gradientStopPosition = null;
      } else if (reader.localName == 'gs' &&
          gradientStopDepth != null &&
          reader.depth == gradientStopDepth - 1) {
        gradientStopDepth = null;
        gradientStopPosition = null;
      } else if (reader.localName == 'ln') {
        inLn = false;
        fillPending = false;
      } else if (reader.localName == 'txBody') {
        inTxBody = false;
        textFillPending = false;
      } else if (reader.localName == 'tcPr') {
        inTcPr = false;
      } else if (reader.localName == 'tc') {
        currentCell = null;
        inTcPr = false;
      } else if (reader.localName == 'tr') {
        currentRow = null;
      } else if (reader.localName == 'tbl') {
        inTbl = false;
        currentRow = null;
        currentCell = null;
        inTcPr = false;
      } else if (reader.localName == 'grpSp') {
        currentGroupId = null;
      } else if (reader.localName == 'sp' ||
          reader.localName == 'cxnSp' ||
          reader.localName == 'pic' ||
          reader.localName == 'graphicFrame') {
        current = null;
        inSpPr = false;
        shapePropertiesDepth = null;
        inGradFill = false;
        gradientDepth = null;
        gradientStopDepth = null;
        gradientPathDepth = null;
        gradientStops.clear();
        gradientStopPosition = null;
        inTxBody = false;
        inLn = false;
        inXfrm = false;
        inStyle = false;
        styleRef = null;
        fillPending = false;
        textFillPending = false;
        inTbl = false;
        inTcPr = false;
        currentRow = null;
        currentCell = null;
      }
      continue;
    }
    if (reader.eventType != XmlEventType.startElement) {
      continue;
    }
    if (reader.localName == 'grpSp') {
      currentGroupId = nextGroupId++;
    } else if (reader.localName == 'sp' ||
        reader.localName == 'cxnSp' ||
        reader.localName == 'pic' ||
        reader.localName == 'graphicFrame') {
      current = PmlShape(
        id: shapes.length + 2,
        name: 'Shape',
        fillColor: '',
        groupId: currentGroupId,
      );
      if (reader.localName == 'pic') {
        current.visual = OfficeVisual(kind: OfficeVisualKind.picture);
      }
      shapes.add(current);
      fillPending = false;
      textFillPending = false;
      strokePending = false;
      inSpPr = false;
      shapePropertiesDepth = null;
      inGradFill = false;
      gradientDepth = null;
      gradientStopDepth = null;
      gradientStops.clear();
      gradientStopPosition = null;
      inTxBody = false;
      inLn = false;
      inXfrm = false;
      inStyle = false;
      explicitFill = false;
      explicitLine = false;
      styleRef = null;
    } else if (reader.localName == 'ph' && current != null) {
      current.placeholder = true;
      current.placeholderType = reader.getAttribute('type') ?? '';
      current.placeholderIndex = int.tryParse(reader.getAttribute('idx') ?? '');
    } else if (reader.localName == 'style' && current != null) {
      inStyle = true;
    } else if (inStyle &&
        (reader.localName == 'fillRef' ||
            reader.localName == 'lnRef' ||
            reader.localName == 'fontRef')) {
      final bool none = reader.getAttribute('idx') == '0';
      styleRef = switch (reader.localName) {
        'fillRef' when !none && !explicitFill => 'fill',
        'lnRef' when !none && !explicitLine => 'line',
        'fontRef' => 'font',
        _ => null,
      };
    } else if (reader.localName == 'spPr') {
      inSpPr = current != null;
      shapePropertiesDepth = current != null ? reader.depth : null;
      inLn = false;
    } else if (reader.localName == 'ln' && inSpPr) {
      inLn = true;
      final String? w = reader.getAttribute('w');
      if (w != null && current != null) {
        final int? emu = int.tryParse(w);
        if (emu != null && emu > 0) {
          current.strokeWidth = emu / 12700.0;
        }
      }
    } else if (reader.localName == 'txBody') {
      inTxBody = current != null;
      if (currentCell == null) {
        paragraphCount = 0;
      } else {
        cellParagraphCount = 0;
      }
    } else if (reader.localName == 'rPr' && current != null) {
      final int? sz = int.tryParse(reader.getAttribute('sz') ?? '');
      if (sz != null && sz > 0 && current.fontSizePt <= 0) {
        current.fontSizePt = sz / 100.0;
      }
    } else if (reader.localName == 'cNvPr' && current != null) {
      current.id = int.parse(reader.getAttribute('id') ?? '${current.id}');
      current.name = reader.getAttribute('name') ?? current.name;
      final String? descr = reader.getAttribute('descr');
      if (descr != null &&
          (descr.startsWith('http://') ||
              descr.startsWith('https://') ||
              descr.startsWith('mailto:'))) {
        current.hyperlinkUrl = descr;
      }
    } else if (reader.localName == 'hlinkClick' && current != null) {
      final String? target = reader.getAttribute('target');
      if (target != null && target.isNotEmpty) {
        current.hyperlinkUrl = target;
      }
    } else if (reader.localName == 'solidFill' && inSpPr && inLn) {
      strokePending = current != null;
      explicitLine = true;
      fillPending = false;
    } else if (reader.localName == 'noFill' && inSpPr && inLn) {
      explicitLine = true;
      current?.strokeColor = '';
    } else if (reader.localName == 'srcRect' && current?.visual != null) {
      DrawingmlVisualIo.applySrcRect(current!.visual!.picture, reader);
    } else if (reader.localName == 'lum' && current?.visual != null) {
      DrawingmlVisualIo.applyLum(current!.visual!.picture, reader);
    } else if (reader.localName == 'alphaModFix' && current?.visual != null) {
      current!.visual!.picture.transparency =
          DrawingmlVisualIo.alphaToTransparency(reader.getAttribute('amt'));
    } else if (reader.localName == 'outerShdw' && current?.visual != null) {
      current!.visual!.picture.shadow = true;
    } else if (reader.localName == 'xfrm' && current != null && !inXfrm) {
      inXfrm = !reader.isEmptyElement;
      final int rot = int.tryParse(reader.getAttribute('rot') ?? '0') ?? 0;
      current.transform = PmlTransform(
        x: current.transform.x,
        y: current.transform.y,
        cx: current.transform.cx,
        cy: current.transform.cy,
        rot: rot,
        flipH: switch (reader.getAttribute('flipH')?.trim()) {
          '1' || 'true' => true,
          _ => false,
        },
        flipV: switch (reader.getAttribute('flipV')?.trim()) {
          '1' || 'true' => true,
          _ => false,
        },
      );
      final OfficeVisual? visual = current.visual;
      if (visual != null) {
        DrawingmlVisualIo.applyXfrm(visual.picture, reader);
      }
    } else if (reader.localName == 'off' && inXfrm && current != null) {
      current.transform = PmlTransform(
        x: int.tryParse(reader.getAttribute('x') ?? '') ?? 0,
        y: int.tryParse(reader.getAttribute('y') ?? '') ?? 0,
        cx: current.transform.cx,
        cy: current.transform.cy,
        rot: current.transform.rot,
        flipH: current.transform.flipH,
        flipV: current.transform.flipV,
      );
      positioned?.add(current);
    } else if (reader.localName == 'ext' && inXfrm && current != null) {
      current.transform = PmlTransform(
        x: current.transform.x,
        y: current.transform.y,
        cx: int.tryParse(reader.getAttribute('cx') ?? '') ?? 0,
        cy: int.tryParse(reader.getAttribute('cy') ?? '') ?? 0,
        rot: current.transform.rot,
        flipH: current.transform.flipH,
        flipV: current.transform.flipV,
      );
      positioned?.add(current);
    } else if (reader.localName == 'prstGeom' && current != null) {
      current.preset = switch (reader.getAttribute('prst')) {
        'ellipse' => PmlShapePreset.ellipse,
        'roundRect' => PmlShapePreset.roundRect,
        'triangle' => PmlShapePreset.triangle,
        'straightConnector1' || 'line' => PmlShapePreset.connector,
        'downArrow' => PmlShapePreset.downArrow,
        'upArrow' => PmlShapePreset.upArrow,
        'leftArrow' => PmlShapePreset.leftArrow,
        'rightArrow' => PmlShapePreset.rightArrow,
        'diamond' || 'flowChartDecision' => PmlShapePreset.diamond,
        'hexagon' => PmlShapePreset.hexagon,
        'pentagon' => PmlShapePreset.pentagon,
        'homePlate' => PmlShapePreset.homePlate,
        'chevron' => PmlShapePreset.chevron,
        'parallelogram' || 'flowChartData' => PmlShapePreset.parallelogram,
        'trapezoid' => PmlShapePreset.trapezoid,
        'round1Rect' ||
        'round2SameRect' ||
        'round2DiagRect' ||
        'plaque' ||
        'flowChartTerminator' => PmlShapePreset.roundRect,
        _ => PmlShapePreset.rect,
      };
    } else if (reader.localName == 'bodyPr' && current != null) {
      current.textAnchor = switch (reader.getAttribute(
        'anchor',
        namespaceUri: '',
      )) {
        'ctr' => PmlTextAnchor.center,
        'b' => PmlTextAnchor.bottom,
        _ => PmlTextAnchor.top,
      };
    } else if (reader.localName == 'noFill' &&
        inSpPr &&
        !inLn &&
        current != null) {
      current.fillColor = '';
      explicitFill = true;
      fillPending = false;
    } else if (reader.localName == 'gradFill' &&
        reader.namespaceUri == OfficeNamespaces.a &&
        inSpPr &&
        !inLn &&
        shapePropertiesDepth != null &&
        reader.depth == shapePropertiesDepth + 1) {
      inGradFill = true;
      gradientDepth = reader.depth;
      gradientStopDepth = null;
      gradientPathDepth = null;
      gradientStops.clear();
      gradientStopPosition = null;
      gradientAngle = 0;
      gradientRadial = false;
      gradientCentered = false;
      gradientDefaultTile = true;
      gradientIsLinear = true;
      fillPending = false;
      explicitFill = true;
    } else if ((reader.localName == 'solidFill' ||
            reader.localName == 'pattFill') &&
        inSpPr &&
        !inLn) {
      fillPending = current != null;
      explicitFill = true;
    } else if (reader.localName == 'blipFill' && inSpPr && !inLn) {
      explicitFill = true;
    } else if (reader.localName == 'solidFill' && inTxBody) {
      textFillPending = current != null;
    } else if (reader.localName == 'tbl' && current != null) {
      current.table ??= PmlTable();
      inTbl = true;
    } else if (reader.localName == 'tblPr' && current?.table != null) {
      final String? rtl = reader.getAttribute('rtl');
      if (rtl != null) {
        current!.table!.rightToLeft = rtl == '1' || rtl.toLowerCase() == 'true';
      }
    } else if (reader.localName == 'tr' && current?.table != null) {
      currentRow = <PmlTableCell>[];
      current!.table!.rows.add(currentRow);
    } else if (reader.localName == 'tc' && currentRow != null) {
      currentCell = PmlTableCell();
      currentRow.add(currentCell);
    } else if (reader.localName == 'tcPr' && currentCell != null) {
      inTcPr = true;
    } else if (reader.localName == 'gs' &&
        reader.namespaceUri == OfficeNamespaces.a &&
        inGradFill &&
        reader.depth == gradientDepth! + 2) {
      gradientStopDepth = reader.depth;
      gradientStopPosition =
          (int.tryParse(reader.getAttribute('pos') ?? '') ?? 0) / 100000;
    } else if (reader.localName == 'lin' &&
        reader.namespaceUri == OfficeNamespaces.a &&
        inGradFill &&
        reader.depth == gradientDepth! + 1) {
      gradientAngle =
          (int.tryParse(reader.getAttribute('ang') ?? '') ?? 0) / 60000;
    } else if (reader.localName == 'path' &&
        reader.namespaceUri == OfficeNamespaces.a &&
        inGradFill &&
        reader.depth == gradientDepth! + 1) {
      gradientPathDepth = reader.depth;
      gradientIsLinear = false;
      gradientRadial = reader.getAttribute('path') == 'circle';
      // Office's omitted focus rectangle is the center point. An explicit
      // noncentral focus still requires geometry outside the bounded model.
      gradientCentered = true;
    } else if (reader.localName == 'fillToRect' &&
        reader.namespaceUri == OfficeNamespaces.a &&
        inGradFill &&
        gradientPathDepth != null &&
        reader.depth == gradientPathDepth + 1) {
      gradientCentered = isCenteredRadialFillToRect(reader);
    } else if (reader.localName == 'tileRect' &&
        reader.namespaceUri == OfficeNamespaces.a &&
        inGradFill &&
        reader.depth == gradientDepth! + 1) {
      gradientDefaultTile = isDefaultGradientTileRect(reader);
    } else if (_colorElements.contains(reader.localName) && current != null) {
      // Color modifiers are consumed by the resolver, changing reader.depth.
      // Capture fill ownership while still positioned on the color start.
      final bool isGradientStopColor =
          inGradFill &&
          gradientStopPosition != null &&
          gradientStopDepth != null &&
          reader.depth == gradientStopDepth + 1 &&
          reader.namespaceUri == OfficeNamespaces.a;
      final String? val = resolveDrawingmlColor(reader, colors);
      if (val != null && val.isNotEmpty) {
        if (isGradientStopColor) {
          gradientStops.add(
            PmlGradientStop(
              position: gradientStopPosition.clamp(0.0, 1.0),
              color: val,
            ),
          );
        } else if (inTcPr && currentCell != null) {
          currentCell.fillColor = val;
        } else if (strokePending) {
          current.strokeColor = val;
        } else if (fillPending) {
          current.fillColor = val;
        } else if (textFillPending) {
          if (currentCell != null) {
            if (currentCell.textColor.isEmpty) currentCell.textColor = val;
          } else if (current.textColor.isEmpty) {
            current.textColor = val;
          }
        } else if (styleRef == 'fill') {
          current.fillColor = val;
        } else if (styleRef == 'line') {
          current.strokeColor = val;
        } else if (styleRef == 'font') {
          current.textColor = val;
        } else if (currentCell != null && currentCell.textColor.isEmpty) {
          currentCell.textColor = val;
        }
      }
      fillPending = false;
      textFillPending = false;
      strokePending = false;
      styleRef = null;
      gradientStopPosition = null;
    } else if ((reader.localName == 'blip' || reader.localName == 'chart') &&
        current != null &&
        !inTxBody) {
      current.embedRelId =
          reader.getAttribute('embed') ?? reader.getAttribute('id');
      if (reader.localName == 'blip') {
        current.visual ??= OfficeVisual(kind: OfficeVisualKind.picture);
      }
    } else if (reader.localName == 'pPr' && current != null && inTxBody) {
      final String? algn = reader.getAttribute('algn');
      current.textAlign = switch (algn) {
        'ctr' => PmlTextAlign.center,
        'r' => PmlTextAlign.right,
        'just' => PmlTextAlign.justify,
        'l' => PmlTextAlign.left,
        _ => current.textAlign,
      };
      final String? rtl = reader.getAttribute('rtl');
      if (rtl != null) {
        current.rightToLeft = rtl == '1' || rtl.toLowerCase() == 'true';
      }
    } else if (reader.localName == 'p' && current != null && inTxBody) {
      if (currentCell != null) {
        if (cellParagraphCount++ > 0) currentCell.text += '\n';
      } else if (!inTbl) {
        if (paragraphCount++ > 0) current.text += '\n';
      }
    } else if (reader.localName == 'br' && current != null && inTxBody) {
      if (currentCell != null) {
        currentCell.text += '\n';
      } else if (!inTbl) {
        current.text += '\n';
      }
    } else if (reader.localName == 't' &&
        current != null &&
        !reader.isEmptyElement) {
      final int depth = reader.depth;
      while (reader.next() && reader.depth >= depth) {
        if (reader.eventType == XmlEventType.characters) {
          if (currentCell != null) {
            currentCell.text += reader.text;
          } else if (!inTbl) {
            current.text += reader.text;
          }
        }
      }
    }
  }
  _captureTextSources(xml, shapes, colors);
  return shapes;
}

void _captureTextSources(
  String xml,
  List<PmlShape> shapes,
  Map<String, String> colors,
) {
  final Map<int, PmlShape> byId = <int, PmlShape>{
    for (final PmlShape shape in shapes) shape.id: shape,
  };
  final XmlPullReader reader = XmlPullReader(xml);
  PmlShape? current;
  while (reader.next()) {
    if (reader.eventType != XmlEventType.startElement) continue;
    if (reader.localName == 'cNvPr' &&
        reader.namespaceUri == OfficeNamespaces.p) {
      current = byId[int.tryParse(reader.getAttribute('id') ?? '')];
    } else if (reader.localName == 'txBody' &&
        reader.namespaceUri == OfficeNamespaces.p &&
        current != null) {
      final XmlElement body = XmlDocument.readElement(reader);
      final properties = body.firstChild(
        'bodyPr',
        namespaceUri: OfficeNamespaces.a,
      );
      current.textInsets = _readTextInsets(properties);
      current.textAnchor = switch (properties?.getAttribute(
        'anchor',
        namespaceUri: '',
      )) {
        'ctr' => PmlTextAnchor.center,
        'b' => PmlTextAnchor.bottom,
        _ => PmlTextAnchor.top,
      };
      final XmlElement? autofit = properties?.firstChild(
        'normAutofit',
        namespaceUri: OfficeNamespaces.a,
      );
      current.textScale = _readAutofitRatio(
        autofit?.getAttribute('fontScale'),
        1,
      );
      current.lineSpacingReduction = _readAutofitRatio(
        autofit?.getAttribute('lnSpcReduction'),
        0,
      );
      final String snapshot = XmlDocument(
        root: body,
      ).toXmlString(declaration: false);
      current.textSource = PmlTextSource(
        xml: snapshot,
        text: current.text,
        fontSizePt: current.fontSizePt,
        textColor: current.textColor,
        textAlign: current.textAlign,
        rightToLeft: current.rightToLeft,
        textInsets: current.textInsets,
        textScale: current.textScale,
        lineSpacingReduction: current.lineSpacingReduction,
      );
      current.richText = parsePmlRichText(snapshot, colors);
      final paragraphs = body.childrenNamed(
        'p',
        namespaceUri: OfficeNamespaces.a,
      );
      for (var index = 0; index < paragraphs.length; index++) {
        // The parser intentionally skips empty visible runs. Capture the same
        // replacement template as export, so fields, breaks or empty runs
        // before the first ordinary run cannot change live formatting.
        final replacementBody =
            XmlElement(
                localName: 'txBody',
                prefix: 'p',
                namespaceUri: OfficeNamespaces.p,
                attributes: <XmlAttribute>[
                  for (final attribute in body.attributes) attribute.copy(),
                ],
              )
              ..setAttribute('p', OfficeNamespaces.p, prefix: 'xmlns')
              ..setAttribute('a', OfficeNamespaces.a, prefix: 'xmlns')
              ..addChild(_replacementTextParagraph(paragraphs[index], 'x'));
        final replacement = parsePmlRichText(
          XmlDocument(root: replacementBody).toXmlString(declaration: false),
          colors,
        ).single.runs.single..text = '';
        current.richText[index].replacementRun = replacement;
      }
    }
  }
}

const Set<String> _colorElements = <String>{
  'srgbClr',
  'schemeClr',
  'sysClr',
  'prstClr',
};

/// Reads a DrawingML color element (consuming it) as `RRGGBB`, applying the
/// `lumMod` / `lumOff` / `shade` / `tint` modifiers PowerPoint themes use.
String? resolveDrawingmlColor(
  XmlPullReader reader,
  Map<String, String> colors,
) {
  final String name = reader.localName;
  final String val = reader.getAttribute('val') ?? '';
  String? hex = switch (name) {
    'srgbClr' => val,
    'schemeClr' => colors[val],
    'sysClr' => reader.getAttribute('lastClr') ?? _systemColors[val],
    'prstClr' => _presetColors[val],
    _ => null,
  };
  if (reader.isEmptyElement) {
    return _normalHex(hex);
  }
  double lumMod = 1;
  double lumOff = 0;
  final int depth = reader.depth;
  while (reader.next() && reader.depth >= depth) {
    if (reader.eventType != XmlEventType.startElement) {
      continue;
    }
    final double amount =
        (int.tryParse(reader.getAttribute('val') ?? '') ?? 100000) / 100000;
    hex = _normalHex(hex);
    switch (reader.localName) {
      case 'lumMod':
        lumMod = amount;
      case 'lumOff':
        lumOff = amount;
      case 'shade' when hex != null:
        hex = _mapChannels(hex, (int c) => c * amount);
      case 'tint' when hex != null:
        hex = _mapChannels(hex, (int c) => c + (255 - c) * (1 - amount));
    }
  }
  hex = _normalHex(hex);
  if (hex == null || (lumMod == 1 && lumOff == 0)) {
    return hex;
  }
  return _applyLuminance(hex, lumMod, lumOff);
}

const Map<String, String> _systemColors = <String, String>{
  'windowText': '000000',
  'window': 'FFFFFF',
};

const Map<String, String> _presetColors = <String, String>{
  'black': '000000',
  'white': 'FFFFFF',
  'red': 'FF0000',
  'green': '008000',
  'blue': '0000FF',
  'yellow': 'FFFF00',
  'gray': '808080',
};

String? _normalHex(String? hex) {
  if (hex == null || hex.length != 6 || int.tryParse(hex, radix: 16) == null) {
    return null;
  }
  return hex.toUpperCase();
}

String _mapChannels(String hex, double Function(int channel) map) {
  final int rgb = int.parse(hex, radix: 16);
  final StringBuffer out = StringBuffer();
  for (final int shift in <int>[16, 8, 0]) {
    final int c = map((rgb >> shift) & 0xFF).round().clamp(0, 255);
    out.write(c.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString().toUpperCase();
}

String _applyLuminance(String hex, double lumMod, double lumOff) {
  final int rgb = int.parse(hex, radix: 16);
  final double r = ((rgb >> 16) & 0xFF) / 255;
  final double g = ((rgb >> 8) & 0xFF) / 255;
  final double b = (rgb & 0xFF) / 255;
  final double max = <double>[
    r,
    g,
    b,
  ].reduce((double a, double v) => a > v ? a : v);
  final double min = <double>[
    r,
    g,
    b,
  ].reduce((double a, double v) => a < v ? a : v);
  double h = 0;
  double s = 0;
  double l = (max + min) / 2;
  final double d = max - min;
  if (d > 0) {
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    if (max == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    } else if (max == g) {
      h = ((b - r) / d + 2) / 6;
    } else {
      h = ((r - g) / d + 4) / 6;
    }
  }
  l = (l * lumMod + lumOff).clamp(0.0, 1.0);
  double channel(double t) {
    final double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final double p = 2 * l - q;
    double k = t;
    if (k < 0) {
      k += 1;
    }
    if (k > 1) {
      k -= 1;
    }
    if (k < 1 / 6) {
      return p + (q - p) * 6 * k;
    }
    if (k < 1 / 2) {
      return q;
    }
    if (k < 2 / 3) {
      return p + (q - p) * (2 / 3 - k) * 6;
    }
    return p;
  }

  final List<double> out = s == 0
      ? <double>[l, l, l]
      : <double>[channel(h + 1 / 3), channel(h), channel(h - 1 / 3)];
  return out
      .map(
        (double c) =>
            (c * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0'),
      )
      .join()
      .toUpperCase();
}

/// parseChartVisual helper.
OfficeVisual parseChartVisual(
  String xml, {

  /// width API.
  double width = 360,

  /// height API.
  double height = 180,
}) {
  return DrawingmlVisualIo.parseChart(
    xml,
    name: 'Chart',
    width: width,
    height: height,
  );
}

/// slideToXml helper.
String slideToXml(
  PmlSlide slide, {
  Map<PmlShape, String>? embedIds,
  bool preserveBackgroundInheritance = false,
}) {
  PmlArrange.validateGrouping(slide.shapes);
  // Group keys identify model membership. They need not be valid native
  // drawing IDs: the importer intentionally assigns compact local keys.
  final Set<int> reservedDrawingIds = {
    1,
    for (final shape in slide.shapes) shape.id,
  };
  var nextGroupDrawingId = 2;

  /// w API.
  final XmlWriter w = XmlWriter();

  /// writeStartDocument API.
  w.writeStartDocument();

  /// writeStartElement API.
  w.writeStartElement('sld', prefix: 'p');
  if (slide.hidden) {
    w.writeAttribute('show', '0');
  }
  if (!slide.showMasterShapes) {
    w.writeAttribute('showMasterSp', '0');
  }

  /// writeNamespace API.
  w.writeNamespace('p', OfficeNamespaces.p);

  /// writeNamespace API.
  w.writeNamespace('a', OfficeNamespaces.a);

  /// writeNamespace API.
  w.writeNamespace('r', OfficeNamespaces.r);

  /// writeNamespace API.
  w.writeNamespace('c', OfficeNamespaces.c);
  w.writeNamespace(
    'p14',
    'http://schemas.microsoft.com/office/powerpoint/2010/main',
  );
  w.writeNamespace('mc', OfficeNamespaces.mc);
  w.writeAttribute('mc:Ignorable', 'p14');

  /// writeStartElement API.
  w.writeStartElement('cSld', prefix: 'p');

  // Keep native fill inheritance when its source layout is retained. Other
  // resolved pictures become one native fill, never editable slide shapes.
  PmlShape? backgroundPicture;
  PmlGradientFill? backgroundGradient;
  if (!preserveBackgroundInheritance) {
    for (final shape in slide.backgroundShapes) {
      if (shape.isBackgroundPicture && (shape.visual?.isPicture ?? false)) {
        backgroundPicture = shape;
        break;
      } else if (shape.isBackgroundGradient &&
          (shape.gradient?.stops.length ?? 0) >= 2) {
        backgroundGradient = shape.gradient;
        break;
      }
    }
  }
  final String? backgroundEmbed = backgroundPicture == null
      ? null
      : embedIds?[backgroundPicture] ?? backgroundPicture.embedRelId;
  final XmlElement? sourceBackground = slide.sourceBackground?.copy();
  if (sourceBackground != null) {
    if (backgroundEmbed != null) {
      sourceBackground
          .firstChild('bgPr', namespaceUri: OfficeNamespaces.p)
          ?.firstChild('blipFill', namespaceUri: OfficeNamespaces.a)
          ?.firstChild('blip', namespaceUri: OfficeNamespaces.a)
          ?.setAttribute(
            'embed',
            backgroundEmbed,
            prefix: 'r',
            namespaceUri: OfficeNamespaces.r,
          );
    }
    sourceBackground.writeTo(w);
  } else if (backgroundEmbed != null ||
      backgroundGradient != null ||
      slide.writesSolidBackground) {
    w.writeStartElement('bg', prefix: 'p');
    w.writeStartElement('bgPr', prefix: 'p');
    if (backgroundEmbed != null) {
      final PictureAdjust picture = backgroundPicture!.visual!.picture;
      w.writeStartElement('blipFill', prefix: 'a');
      DrawingmlVisualIo.writeBlip(
        w,
        relationshipId: backgroundEmbed,
        adj: picture,
      );
      // Imported backgrounds support deep crops and edge expansion. The shared
      // editable-picture writer deliberately applies narrower UI limits.
      final crop = <String, int>{
        'l': (picture.cropLeft.clamp(-.99, .99) * 100000).round(),
        't': (picture.cropTop.clamp(-.99, .99) * 100000).round(),
        'r': (picture.cropRight.clamp(-.99, .99) * 100000).round(),
        'b': (picture.cropBottom.clamp(-.99, .99) * 100000).round(),
      };
      if (crop.values.any((value) => value != 0)) {
        w.writeEmptyElement(
          'srcRect',
          prefix: 'a',
          attributes: <String, String>{
            for (final entry in crop.entries) entry.key: '${entry.value}',
          },
        );
      }
      w.writeStartElement('stretch', prefix: 'a');
      w.writeEmptyElement('fillRect', prefix: 'a');
      w.writeEndElement();
      w.writeEndElement();
    } else if (backgroundGradient != null) {
      _writeGradientFill(w, backgroundGradient);
    } else {
      w.writeStartElement('solidFill', prefix: 'a');
      w.writeEmptyElement(
        'srgbClr',
        prefix: 'a',
        attributes: <String, String>{'val': slide.background},
      );
      w.writeEndElement();
    }
    w.writeEndElement();
    w.writeEndElement();
  }

  /// writeStartElement API.
  w.writeStartElement('spTree', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('nvGrpSpPr', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'cNvPr',
    prefix: 'p',
    attributes: <String, String>{'id': '1', 'name': ''},
  );

  /// writeEmptyElement API.
  w.writeEmptyElement('cNvGrpSpPr', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement('nvPr', prefix: 'p');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEmptyElement API.
  w.writeEmptyElement('grpSpPr', prefix: 'p');
  int? openGroup;
  for (final PmlShape shape in slide.shapes) {
    if (shape.groupId != openGroup) {
      if (openGroup != null) {
        w.writeEndElement();
      }
      if (shape.groupId != null) {
        while (reservedDrawingIds.contains(nextGroupDrawingId)) {
          nextGroupDrawingId++;
        }
        w.writeStartElement('grpSp', prefix: 'p');
        w.writeStartElement('nvGrpSpPr', prefix: 'p');
        w.writeEmptyElement(
          'cNvPr',
          prefix: 'p',
          attributes: <String, String>{
            'id': '${nextGroupDrawingId++}',
            'name': 'Group ${shape.groupId}',
          },
        );
        w.writeEmptyElement('cNvGrpSpPr', prefix: 'p');
        w.writeEmptyElement('nvPr', prefix: 'p');
        w.writeEndElement();
        w.writeEmptyElement('grpSpPr', prefix: 'p');
      }
      openGroup = shape.groupId;
    }
    final OfficeVisual? visual = shape.visual;
    final String? embed = embedIds?[shape] ?? shape.embedRelId;
    if (shape.table != null) {
      _writeSlideTable(w, shape);
    } else if (visual != null && visual.isChart && embed != null) {
      _writeSlideChart(w, shape, visual, embed);
    } else if (visual != null &&
        (visual.isPicture || visual.isDiagram) &&
        embed != null) {
      _writeSlidePicture(w, shape, visual, embed);
    } else {
      _writeSlideShape(w, shape);
    }
  }
  if (openGroup != null) {
    w.writeEndElement();
  }

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeSlideMotion API.
  writeSlideMotion(w, slide);

  /// writeEndElement API.
  w.writeEndElement();
  return w.toXml();
}

void _writeGradientFill(XmlWriter w, PmlGradientFill gradient) {
  w.writeStartElement('gradFill', prefix: 'a');
  w.writeStartElement('gsLst', prefix: 'a');
  for (final stop in gradient.stops) {
    w.writeStartElement('gs', prefix: 'a');
    w.writeAttribute(
      'pos',
      '${(stop.position.clamp(0.0, 1.0) * 100000).round()}',
    );
    w.writeEmptyElement(
      'srgbClr',
      prefix: 'a',
      attributes: <String, String>{'val': stop.color},
    );
    w.writeEndElement();
  }
  w.writeEndElement();
  if (gradient.radial) {
    w.writeStartElement('path', prefix: 'a');
    w.writeAttribute('path', 'circle');
    w.writeEmptyElement(
      'fillToRect',
      prefix: 'a',
      attributes: const <String, String>{
        'l': '50000',
        't': '50000',
        'r': '50000',
        'b': '50000',
      },
    );
    w.writeEndElement();
  } else {
    w.writeEmptyElement(
      'lin',
      prefix: 'a',
      attributes: <String, String>{
        'ang': '${(gradient.angleDegrees * 60000).round()}',
        'scaled': '0',
      },
    );
  }
  w.writeEndElement();
}

void _writeSlideShape(XmlWriter w, PmlShape shape) {
  /// writeStartElement API.
  w.writeStartElement('sp', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('nvSpPr', prefix: 'p');

  final Map<String, String> cNvPrAttrs = <String, String>{
    'id': '${shape.id}',
    'name': shape.name,
  };
  if (shape.hyperlinkUrl.isNotEmpty) {
    cNvPrAttrs['descr'] = shape.hyperlinkUrl;
  }
  w.writeEmptyElement('cNvPr', prefix: 'p', attributes: cNvPrAttrs);

  /// writeEmptyElement API.
  w.writeEmptyElement('cNvSpPr', prefix: 'p');

  // Keep the native layout/master binding. Empty type and null index retain
  // omitted attributes, whose defaults Office resolves through that binding.
  if (shape.placeholder) {
    w.writeStartElement('nvPr', prefix: 'p');
    w.writeEmptyElement(
      'ph',
      prefix: 'p',
      attributes: {
        if (shape.placeholderType.isNotEmpty) 'type': shape.placeholderType,
        if (shape.placeholderIndex != null) 'idx': '${shape.placeholderIndex}',
      },
    );
    w.writeEndElement();
  } else {
    w.writeEmptyElement('nvPr', prefix: 'p');
  }

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('spPr', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('xfrm', prefix: 'a');
  if (shape.transform.rot != 0) {
    w.writeAttribute('rot', '${shape.transform.rot}');
  }
  if (shape.transform.flipH) {
    w.writeAttribute('flipH', '1');
  }
  if (shape.transform.flipV) {
    w.writeAttribute('flipV', '1');
  }

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'off',
    prefix: 'a',
    attributes: <String, String>{
      'x': '${shape.transform.x}',
      'y': '${shape.transform.y}',
    },
  );

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'ext',
    prefix: 'a',
    attributes: <String, String>{
      'cx': '${shape.transform.cx}',
      'cy': '${shape.transform.cy}',
    },
  );

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'prstGeom',
    prefix: 'a',
    attributes: <String, String>{
      'prst': switch (shape.preset) {
        PmlShapePreset.roundRect => 'roundRect',
        PmlShapePreset.ellipse => 'ellipse',
        PmlShapePreset.triangle => 'triangle',
        PmlShapePreset.connector => 'straightConnector1',
        PmlShapePreset.freeform => 'rect',
        PmlShapePreset.downArrow => 'downArrow',
        PmlShapePreset.upArrow => 'upArrow',
        PmlShapePreset.leftArrow => 'leftArrow',
        PmlShapePreset.rightArrow => 'rightArrow',
        PmlShapePreset.diamond => 'diamond',
        PmlShapePreset.hexagon => 'hexagon',
        PmlShapePreset.pentagon => 'pentagon',
        PmlShapePreset.homePlate => 'homePlate',
        PmlShapePreset.chevron => 'chevron',
        PmlShapePreset.parallelogram => 'parallelogram',
        PmlShapePreset.trapezoid => 'trapezoid',
        PmlShapePreset.rect => 'rect',
      },
    },
  );
  final PmlGradientFill? gradient = shape.gradient;
  if (gradient != null && gradient.stops.length >= 2) {
    _writeGradientFill(w, gradient);
  } else if (shape.fillColor.isNotEmpty) {
    w.writeStartElement('solidFill', prefix: 'a');
    w.writeEmptyElement(
      'srgbClr',
      prefix: 'a',
      attributes: <String, String>{'val': shape.fillColor},
    );
    w.writeEndElement();
  }
  if (shape.strokeColor.isNotEmpty) {
    w.writeStartElement('ln', prefix: 'a');
    w.writeAttribute('w', '${(shape.strokeWidth * 12700).round()}');
    w.writeStartElement('solidFill', prefix: 'a');
    w.writeEmptyElement(
      'srgbClr',
      prefix: 'a',
      attributes: <String, String>{'val': shape.strokeColor},
    );
    w.writeEndElement();
    w.writeEndElement();
  }

  /// writeEndElement API.
  w.writeEndElement();
  if (shape.text.isNotEmpty ||
      shape.textSource != null ||
      shape.hasExplicitTextFormatting ||
      shape.textAnchorOverride ||
      shape.hasTextInsetChanges ||
      shape.textAnchor != PmlTextAnchor.top ||
      shape.textReplacementRequested) {
    _writeShapeText(w, shape);
  }

  /// writeEndElement API.
  w.writeEndElement();
}

XmlElement _textElement(String name) =>
    XmlElement(localName: name, prefix: 'a', namespaceUri: OfficeNamespaces.a);

String _insetAttribute(PmlTextInsetSide side) => switch (side) {
  PmlTextInsetSide.left => 'lIns',
  PmlTextInsetSide.top => 'tIns',
  PmlTextInsetSide.right => 'rIns',
  PmlTextInsetSide.bottom => 'bIns',
};

PmlTextInsets _readTextInsets(XmlElement? properties) {
  var result = const PmlTextInsets();
  for (final side in PmlTextInsetSide.values) {
    final emu = int.tryParse(
      properties?.getAttribute(_insetAttribute(side), namespaceUri: '') ?? '',
    );
    if (emu != null && emu >= -2147483648 && emu <= 2147483647) {
      result = result.withSide(side, emu / 12700);
    }
  }
  return result;
}

void _writeTextInsets(XmlElement body, PmlShape shape) {
  var properties = body.firstChild('bodyPr', namespaceUri: OfficeNamespaces.a);
  final imported = _readTextInsets(properties);
  for (final side in PmlTextInsetSide.values) {
    final points = shape.textInsets[side];
    if (!shape.textInsetOverrides.contains(side) && imported[side] == points) {
      continue;
    }
    final emu = points * 12700;
    if (!emu.isFinite ||
        emu < -2147483648 ||
        emu > 2147483647 ||
        emu.round() / 12700 != points) {
      throw ArgumentError('Text-frame insets must be exact signed Long EMUs');
    }
    if (properties == null) {
      properties = _textElement('bodyPr')..parent = body;
      body.children.insert(0, properties);
    }
    final name = _insetAttribute(side);
    properties.removeAttribute(name, namespaceUri: '');
    properties.attributes.add(
      XmlAttribute(localName: name, value: '${emu.round()}'),
    );
  }
}

/// Whether a DrawingML radial focus is the supported central point.
bool isCenteredRadialFillToRect(XmlPullReader reader) => const <String>[
  'l',
  't',
  'r',
  'b',
].every((name) => _fitPercent(reader.getAttribute(name), fallback: 0) == 0.5);

/// Whether a gradient uses the unshifted shape bounds as its fill tile.
bool isDefaultGradientTileRect(XmlPullReader reader) =>
    const <String>['l', 't', 'r', 'b'].every((name) {
      final String? value = reader.getAttribute(name);
      return value == null || _fitPercent(value, fallback: double.nan) == 0;
    });

double _fitPercent(String? value, {required double fallback}) {
  if (value == null) return fallback;
  final String raw = value.trim();
  final bool percent = raw.endsWith('%');
  final double? number = double.tryParse(
    percent ? raw.substring(0, raw.length - 1) : raw,
  );
  if (number == null || !number.isFinite) return fallback;
  return number / (percent ? 100 : 100000);
}

// CT_TextCharacterProperties orders script fonts before hyperlinks and rtl.
// Preserve every unrelated child while inserting only the requested font.
int _textCharacterOrder(String name) => switch (name) {
  'ln' => 0,
  'noFill' ||
  'solidFill' ||
  'gradFill' ||
  'blipFill' ||
  'pattFill' ||
  'grpFill' => 10,
  'effectLst' || 'effectDag' => 20,
  'highlight' => 30,
  'uLnTx' || 'uLn' => 40,
  'uFillTx' || 'uFill' => 50,
  'latin' => 60,
  'ea' => 61,
  'cs' => 62,
  'sym' => 63,
  'hlinkClick' => 70,
  'hlinkMouseOver' => 71,
  'rtl' => 80,
  'extLst' => 90,
  _ => 100,
};

void _setTextTypeface(XmlElement properties, String script, String family) {
  final font =
      properties.firstChild(script, namespaceUri: OfficeNamespaces.a)?.copy() ??
      _textElement(script);
  font.setAttribute('typeface', family);
  properties.children.removeWhere(
    (node) =>
        node is XmlElement &&
        node.namespaceUri == OfficeNamespaces.a &&
        node.localName == script,
  );
  final rank = _textCharacterOrder(script);
  final next = properties.children.indexWhere(
    (node) =>
        node is XmlElement &&
        node.namespaceUri == OfficeNamespaces.a &&
        _textCharacterOrder(node.localName) > rank,
  );
  properties.children.insert(
    next < 0 ? properties.children.length : next,
    font..parent = properties,
  );
}

double _readAutofitRatio(String? text, double fallback) {
  if (text == null) return fallback;
  final String value = text.trim();
  final bool percent = value.endsWith('%');
  final double? number = percent
      ? double.tryParse(value.substring(0, value.length - 1))
      : int.tryParse(value)?.toDouble();
  if (number == null || !number.isFinite) return fallback;
  return (number / (percent ? 100 : 100000)).clamp(0.0, 1.0);
}

void _writeAutofit(XmlElement body, PmlShape shape) {
  XmlElement? properties = body.firstChild(
    'bodyPr',
    namespaceUri: OfficeNamespaces.a,
  );
  XmlElement? autofit = properties?.firstChild(
    'normAutofit',
    namespaceUri: OfficeNamespaces.a,
  );
  if (autofit == null &&
      shape.textScale == 1 &&
      shape.lineSpacingReduction == 0) {
    // An ordinary text box must not acquire normal autofit merely by saving.
    return;
  }
  if (properties == null) {
    properties = _textElement('bodyPr')..parent = body;
    body.children.insert(0, properties);
  }
  final bool created = autofit == null;
  if (created) {
    properties.children.removeWhere(
      (XmlNode node) =>
          node is XmlElement &&
          node.namespaceUri == OfficeNamespaces.a &&
          (node.localName == 'noAutofit' || node.localName == 'spAutoFit'),
    );
    autofit = _textElement('normAutofit');
    final int laterProperty = properties.children.indexWhere(
      (XmlNode node) =>
          node is XmlElement &&
          node.namespaceUri == OfficeNamespaces.a &&
          const <String>{
            'scene3d',
            'sp3d',
            'flatTx',
            'extLst',
          }.contains(node.localName),
    );
    autofit.parent = properties;
    properties.children.insert(
      laterProperty < 0 ? properties.children.length : laterProperty,
      autofit,
    );
  }
  if (created ||
      _readAutofitRatio(autofit.getAttribute('fontScale'), 1) !=
          shape.textScale) {
    autofit.setAttribute('fontScale', '${(shape.textScale * 100000).round()}');
  }
  if (created ||
      _readAutofitRatio(autofit.getAttribute('lnSpcReduction'), 0) !=
          shape.lineSpacingReduction) {
    autofit.setAttribute(
      'lnSpcReduction',
      '${(shape.lineSpacingReduction * 100000).round()}',
    );
  }
}

Iterable<XmlElement> _textDescendants(XmlElement root, String name) sync* {
  for (final XmlElement child in root.childElements) {
    if (child.localName == name && child.namespaceUri == OfficeNamespaces.a) {
      yield child;
    }
    yield* _textDescendants(child, name);
  }
}

XmlElement _readTextSourceRoot(String xml) {
  final XmlPullReader reader = XmlPullReader(xml);
  while (reader.next()) {
    if (reader.eventType == XmlEventType.startElement) {
      // The generic DOM parser omits leading whitespace-only text. A drawing
      // text run containing only spaces is content and must stay intact.
      return XmlDocument.readElement(reader);
    }
  }
  throw const FormatException('Imported slide text body is empty');
}

XmlElement _replacementTextParagraph(XmlElement? template, String text) {
  final paragraph = _textElement('p');
  final pPr = template?.firstChild('pPr', namespaceUri: OfficeNamespaces.a);
  if (pPr != null) paragraph.addChild(pPr.copy());
  final templateRun = template?.firstChild(
    'r',
    namespaceUri: OfficeNamespaces.a,
  );
  final end = template?.firstChild(
    'endParaRPr',
    namespaceUri: OfficeNamespaces.a,
  );
  final rPr =
      templateRun?.firstChild('rPr', namespaceUri: OfficeNamespaces.a) ??
      end ??
      pPr?.firstChild('defRPr', namespaceUri: OfficeNamespaces.a);
  final run = _textElement('r');
  if (rPr != null) {
    run.addChild(rPr.copy()..localName = 'rPr');
  }
  run.addChild(_textElement('t')..addText(text));
  paragraph.addChild(run);
  if (end != null) paragraph.addChild(end.copy());
  return paragraph;
}

void _writeShapeText(XmlWriter writer, PmlShape shape) {
  final PmlTextSource? source = shape.textSource;
  final XmlElement body = source == null
      ? XmlElement(
          localName: 'txBody',
          prefix: 'p',
          namespaceUri: OfficeNamespaces.p,
        )
      : _readTextSourceRoot(source.xml);
  if (source == null) {
    body.addChild(_textElement('bodyPr'));
    body.addChild(_textElement('lstStyle'));
  }
  final properties = body.firstChild(
    'bodyPr',
    namespaceUri: OfficeNamespaces.a,
  );
  final importedAnchor = switch (properties?.getAttribute(
    'anchor',
    namespaceUri: '',
  )) {
    'ctr' => PmlTextAnchor.center,
    'b' => PmlTextAnchor.bottom,
    _ => PmlTextAnchor.top,
  };
  if (shape.textAnchorOverride || importedAnchor != shape.textAnchor) {
    final anchorProperties = properties ?? _textElement('bodyPr');
    if (properties == null) {
      anchorProperties.parent = body;
      body.children.insert(0, anchorProperties);
    }
    anchorProperties.removeAttribute('anchor', namespaceUri: '');
    anchorProperties.attributes.add(
      XmlAttribute(
        localName: 'anchor',
        value: switch (shape.textAnchor) {
          PmlTextAnchor.top => 't',
          PmlTextAnchor.center => 'ctr',
          PmlTextAnchor.bottom => 'b',
        },
      ),
    );
  }
  _writeTextInsets(body, shape);
  _writeAutofit(body, shape);
  final bool replace =
      shape.textReplacementRequested ||
      source == null ||
      source.text != shape.text;
  if (replace) {
    final List<XmlElement> original = body.childrenNamed(
      'p',
      namespaceUri: OfficeNamespaces.a,
    );
    body.children.removeWhere(
      (XmlNode n) =>
          n is XmlElement &&
          n.localName == 'p' &&
          n.namespaceUri == OfficeNamespaces.a,
    );
    final List<String> lines = shape.text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final XmlElement? template = original.isEmpty
          ? null
          : original[i < original.length ? i : original.length - 1];
      body.addChild(_replacementTextParagraph(template, lines[i]));
    }
  }
  final bool fontChanged =
      shape.textSizeOverride ||
      source == null ||
      source.fontSizePt != shape.fontSizePt;
  final bool colorChanged =
      shape.textColorOverride ||
      source == null ||
      source.textColor != shape.textColor;
  final bool alignChanged =
      shape.textAlignOverride ||
      source == null ||
      source.textAlign != shape.textAlign;
  final bool directionChanged =
      shape.textDirectionOverride ||
      source == null ||
      source.rightToLeft != shape.rightToLeft;
  final bool characterChanged =
      fontChanged ||
      colorChanged ||
      shape.textBold != null ||
      shape.textItalic != null ||
      shape.textUnderline != null ||
      shape.textFontFamily != null;
  for (final XmlElement paragraph in body.childrenNamed(
    'p',
    namespaceUri: OfficeNamespaces.a,
  )) {
    if (alignChanged || directionChanged || characterChanged) {
      XmlElement? props = paragraph.firstChild(
        'pPr',
        namespaceUri: OfficeNamespaces.a,
      );
      if (props == null) {
        props = _textElement('pPr')..parent = paragraph;
        paragraph.children.insert(0, props);
      }
      if (alignChanged) {
        props.setAttribute('algn', switch (shape.textAlign) {
          PmlTextAlign.left => 'l',
          PmlTextAlign.center => 'ctr',
          PmlTextAlign.right => 'r',
          PmlTextAlign.justify => 'just',
        });
      }
      if (directionChanged) {
        if (shape.rightToLeft == null) {
          props.removeAttribute('rtl');
        } else {
          props.setAttribute('rtl', shape.rightToLeft! ? '1' : '0');
        }
      }
      if (characterChanged &&
          props.firstChild('defRPr', namespaceUri: OfficeNamespaces.a) ==
              null) {
        final end = props.children.indexWhere(
          (node) =>
              node is XmlElement &&
              node.namespaceUri == OfficeNamespaces.a &&
              node.localName == 'extLst',
        );
        props.children.insert(
          end < 0 ? props.children.length : end,
          _textElement('defRPr')..parent = props,
        );
      }
    }
    if (characterChanged &&
        paragraph.firstChild('endParaRPr', namespaceUri: OfficeNamespaces.a) ==
            null) {
      paragraph.addChild(_textElement('endParaRPr'));
    }
  }
  if (characterChanged) {
    for (final XmlElement run in <XmlElement>[
      ..._textDescendants(body, 'r'),
      ..._textDescendants(body, 'fld'),
      ..._textDescendants(body, 'br'),
    ]) {
      if (run.firstChild('rPr', namespaceUri: OfficeNamespaces.a) == null) {
        final XmlElement props = _textElement('rPr')..parent = run;
        run.children.insert(0, props);
      }
    }
    for (final XmlElement props in <XmlElement>[
      ..._textDescendants(body, 'rPr'),
      ..._textDescendants(body, 'defRPr'),
      ..._textDescendants(body, 'endParaRPr'),
    ]) {
      if (fontChanged) {
        if (shape.fontSizePt > 0) {
          props.setAttribute('sz', '${(shape.fontSizePt * 100).round()}');
        } else {
          props.removeAttribute('sz');
        }
      }
      if (shape.textBold != null) {
        props.setAttribute('b', shape.textBold! ? '1' : '0');
      }
      if (shape.textItalic != null) {
        props.setAttribute('i', shape.textItalic! ? '1' : '0');
      }
      if (shape.textUnderline != null) {
        props.setAttribute('u', shape.textUnderline! ? 'sng' : 'none');
      }
      if (shape.textFontFamily != null) {
        for (final script in const ['latin', 'ea', 'cs']) {
          _setTextTypeface(props, script, shape.textFontFamily!);
        }
      }
      if (colorChanged) {
        const Set<String> fills = <String>{
          'noFill',
          'solidFill',
          'gradFill',
          'blipFill',
          'pattFill',
          'grpFill',
        };
        props.children.removeWhere(
          (XmlNode n) =>
              n is XmlElement &&
              n.namespaceUri == OfficeNamespaces.a &&
              fills.contains(n.localName),
        );
        if (shape.textColor.isNotEmpty) {
          final XmlElement fill = _textElement('solidFill');
          fill.addChild(
            _textElement('srgbClr')..setAttribute('val', shape.textColor),
          );
          final int lineAt = props.children.indexWhere(
            (XmlNode n) =>
                n is XmlElement &&
                n.localName == 'ln' &&
                n.namespaceUri == OfficeNamespaces.a,
          );
          props.children.insert(lineAt + 1, fill..parent = props);
        }
      }
    }
  }
  body.writeTo(writer);
}

void _writeSlidePicture(
  XmlWriter w,
  PmlShape shape,
  OfficeVisual visual,
  String relationshipId,
) {
  /// adj API.
  final PictureAdjust adj = visual.picture;

  /// name API.
  final String name = adj.altTitle.isNotEmpty ? adj.altTitle : shape.name;

  /// descr API.
  final String descr = adj.altDescription.isNotEmpty
      ? adj.altDescription
      : name;

  /// writeStartElement API.
  w.writeStartElement('pic', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('nvPicPr', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('cNvPr', prefix: 'p');

  /// writeAttribute API.
  w.writeAttribute('id', '${shape.id}');

  /// writeAttribute API.
  w.writeAttribute('name', name);

  /// writeAttribute API.
  w.writeAttribute('descr', descr);

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('cNvPicPr', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'picLocks',
    prefix: 'a',
    attributes: <String, String>{'noChangeAspect': adj.lockAspect ? '1' : '0'},
  );

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEmptyElement API.
  w.writeEmptyElement('nvPr', prefix: 'p');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('blipFill', prefix: 'p');

  /// writeBlip API.
  DrawingmlVisualIo.writeBlip(w, relationshipId: relationshipId, adj: adj);

  /// writeSrcRect API.
  DrawingmlVisualIo.writeSrcRect(w, adj);

  /// writeStartElement API.
  w.writeStartElement('stretch', prefix: 'a');

  /// writeEmptyElement API.
  w.writeEmptyElement('fillRect', prefix: 'a');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('spPr', prefix: 'p');

  /// writeXfrm API.
  DrawingmlVisualIo.writeXfrm(
    w,
    cx: shape.transform.cx,
    cy: shape.transform.cy,
    adj: adj,
    offX: shape.transform.x,
    offY: shape.transform.y,
  );

  /// writeStartElement API.
  w.writeStartElement('prstGeom', prefix: 'a');

  /// writeAttribute API.
  w.writeAttribute('prst', 'rect');

  /// writeEmptyElement API.
  w.writeEmptyElement('avLst', prefix: 'a');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeLine API.
  DrawingmlVisualIo.writeLine(w, adj);

  /// writeShadow API.
  DrawingmlVisualIo.writeShadow(w, adj);

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();
}

void _writeSlideTable(XmlWriter w, PmlShape shape) {
  /// table API.
  final PmlTable table = shape.table!;

  /// writeStartElement API.
  w.writeStartElement('graphicFrame', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('nvGraphicFramePr', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'cNvPr',
    prefix: 'p',
    attributes: <String, String>{'id': '${shape.id}', 'name': shape.name},
  );

  /// writeEmptyElement API.
  w.writeEmptyElement('cNvGraphicFramePr', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement('nvPr', prefix: 'p');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('xfrm', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'off',
    prefix: 'a',
    attributes: <String, String>{
      'x': '${shape.transform.x}',
      'y': '${shape.transform.y}',
    },
  );

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'ext',
    prefix: 'a',
    attributes: <String, String>{
      'cx': '${shape.transform.cx}',
      'cy': '${shape.transform.cy}',
    },
  );

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('graphic', prefix: 'a');

  /// writeStartElement API.
  w.writeStartElement('graphicData', prefix: 'a');

  /// writeAttribute API.
  w.writeAttribute('uri', OfficeNamespaces.drawingmlTable);

  /// writeStartElement API.
  w.writeStartElement('tbl', prefix: 'a');
  if (table.rightToLeft) {
    w.writeEmptyElement(
      'tblPr',
      prefix: 'a',
      attributes: <String, String>{'rtl': '1'},
    );
  } else {
    w.writeEmptyElement('tblPr', prefix: 'a');
  }

  /// cols API.
  final int cols = table.colCount;

  /// colW API.
  final int colW = cols <= 0 ? shape.transform.cx : shape.transform.cx ~/ cols;

  /// writeStartElement API.
  w.writeStartElement('tblGrid', prefix: 'a');
  for (int i = 0; i < cols; i++) {
    w.writeEmptyElement(
      'gridCol',
      prefix: 'a',
      attributes: <String, String>{'w': '$colW'},
    );
  }

  /// writeEndElement API.
  w.writeEndElement();

  /// rowH API.
  final int rowH = table.rowCount <= 0
      ? shape.transform.cy
      : shape.transform.cy ~/ table.rowCount;
  for (final List<PmlTableCell> row in table.rows) {
    w.writeStartElement('tr', prefix: 'a');
    w.writeAttribute('h', '$rowH');
    for (int c = 0; c < cols; c++) {
      final PmlTableCell cell = c < row.length ? row[c] : PmlTableCell();
      w.writeStartElement('tc', prefix: 'a');
      w.writeStartElement('tcPr', prefix: 'a');
      if (cell.fillColor.isNotEmpty) {
        w.writeStartElement('solidFill', prefix: 'a');
        w.writeEmptyElement(
          'srgbClr',
          prefix: 'a',
          attributes: <String, String>{'val': cell.fillColor},
        );
        w.writeEndElement();
      }
      w.writeEndElement();
      w.writeStartElement('txBody', prefix: 'a');
      w.writeEmptyElement('bodyPr', prefix: 'a');
      w.writeStartElement('p', prefix: 'a');
      if (cell.text.isNotEmpty) {
        w.writeStartElement('r', prefix: 'a');
        if (cell.textColor.isNotEmpty) {
          w.writeStartElement('rPr', prefix: 'a');
          w.writeStartElement('solidFill', prefix: 'a');
          w.writeEmptyElement(
            'srgbClr',
            prefix: 'a',
            attributes: <String, String>{'val': cell.textColor},
          );
          w.writeEndElement();
          w.writeEndElement();
        }
        w.writeStartElement('t', prefix: 'a');
        w.writeText(cell.text);
        w.writeEndElement();
        w.writeEndElement();
      }
      w.writeEndElement();
      w.writeEndElement();
      w.writeEndElement();
    }
    w.writeEndElement();
  }

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();
}

void _writeSlideChart(
  XmlWriter w,
  PmlShape shape,
  OfficeVisual visual,
  String relationshipId,
) {
  /// name API.
  final String name = visual.title.isEmpty ? shape.name : visual.title;

  /// writeStartElement API.
  w.writeStartElement('graphicFrame', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('nvGraphicFramePr', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('cNvPr', prefix: 'p');

  /// writeAttribute API.
  w.writeAttribute('id', '${shape.id}');

  /// writeAttribute API.
  w.writeAttribute('name', name);

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEmptyElement API.
  w.writeEmptyElement('cNvGraphicFramePr', prefix: 'p');

  /// writeEmptyElement API.
  w.writeEmptyElement('nvPr', prefix: 'p');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeXfrm API.
  DrawingmlVisualIo.writeXfrm(
    w,
    cx: shape.transform.cx,
    cy: shape.transform.cy,
    adj: visual.picture,
    offX: shape.transform.x,
    offY: shape.transform.y,
    prefix: 'p',
  );

  /// writeStartElement API.
  w.writeStartElement('graphic', prefix: 'a');

  /// writeStartElement API.
  w.writeStartElement('graphicData', prefix: 'a');

  /// writeAttribute API.
  w.writeAttribute('uri', OfficeNamespaces.c);

  /// writeEmptyElement API.
  w.writeEmptyElement(
    'chart',
    prefix: 'c',
    attributes: <String, String>{'r:id': relationshipId},
  );

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();

  /// writeEndElement API.
  w.writeEndElement();
}
