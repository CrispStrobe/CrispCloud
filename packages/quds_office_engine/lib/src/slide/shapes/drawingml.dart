import '../../visual/drawingml_visual_io.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_reader.dart';
import '../../xml/xml_writer.dart';
import '../anim/pml_motion_io.dart';
import '../model/pml_presentation.dart';

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
  int? currentGroupId;
  var nextGroupId = 1;
  var inXfrm = false;
  var inStyle = false;
  var explicitFill = false;
  var explicitLine = false;
  String? styleRef;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement) {
      if (reader.localName == 'xfrm') {
        inXfrm = false;
      } else if (reader.localName == 'style') {
        inStyle = false;
        styleRef = null;
      } else if (reader.localName == 'spPr') {
        inSpPr = false;
        inLn = false;
        fillPending = false;
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
      );
      positioned?.add(current);
    } else if (reader.localName == 'ext' && inXfrm && current != null) {
      current.transform = PmlTransform(
        x: current.transform.x,
        y: current.transform.y,
        cx: int.tryParse(reader.getAttribute('cx') ?? '') ?? 0,
        cy: int.tryParse(reader.getAttribute('cy') ?? '') ?? 0,
        rot: current.transform.rot,
      );
      positioned?.add(current);
    } else if (reader.localName == 'prstGeom' && current != null) {
      current.preset = switch (reader.getAttribute('prst')) {
        'ellipse' => PmlShapePreset.ellipse,
        'roundRect' => PmlShapePreset.roundRect,
        'triangle' => PmlShapePreset.triangle,
        'straightConnector1' => PmlShapePreset.connector,
        _ => PmlShapePreset.rect,
      };
    } else if (reader.localName == 'noFill' &&
        inSpPr &&
        !inLn &&
        current != null) {
      current.fillColor = '';
      explicitFill = true;
      fillPending = false;
    } else if ((reader.localName == 'solidFill' ||
            reader.localName == 'gradFill' ||
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
    } else if (_colorElements.contains(reader.localName) && current != null) {
      final String? val = _readColor(reader, colors);
      if (val != null && val.isNotEmpty) {
        if (inTcPr && currentCell != null) {
          currentCell.fillColor = val;
        } else if (strokePending) {
          current.strokeColor = val;
        } else if (fillPending) {
          current.fillColor = val;
        } else if (textFillPending) {
          current.textColor = val;
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
    } else if (reader.localName == 'p' && current != null) {
      if (currentCell != null &&
          currentCell.text.isNotEmpty &&
          !currentCell.text.endsWith('\n')) {
        currentCell.text += '\n';
      } else if (!inTbl &&
          current.text.isNotEmpty &&
          !current.text.endsWith('\n')) {
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
  return shapes;
}

const Set<String> _colorElements = <String>{
  'srgbClr',
  'schemeClr',
  'sysClr',
  'prstClr',
};

/// Reads a DrawingML color element (consuming it) as `RRGGBB`, applying the
/// `lumMod` / `lumOff` / `shade` / `tint` modifiers PowerPoint themes use.
String? _readColor(XmlPullReader reader, Map<String, String> colors) {
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
String slideToXml(PmlSlide slide, {Map<PmlShape, String>? embedIds}) {
  /// w API.
  final XmlWriter w = XmlWriter();

  /// writeStartDocument API.
  w.writeStartDocument();

  /// writeStartElement API.
  w.writeStartElement('sld', prefix: 'p');
  if (slide.hidden) {
    w.writeAttribute('show', '0');
  }

  /// writeNamespace API.
  w.writeNamespace('p', OfficeNamespaces.p);

  /// writeNamespace API.
  w.writeNamespace('a', OfficeNamespaces.a);

  /// writeNamespace API.
  w.writeNamespace('r', OfficeNamespaces.r);

  /// writeNamespace API.
  w.writeNamespace('c', OfficeNamespaces.c);

  /// writeStartElement API.
  w.writeStartElement('cSld', prefix: 'p');

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
        w.writeStartElement('grpSp', prefix: 'p');
        w.writeStartElement('nvGrpSpPr', prefix: 'p');
        w.writeEmptyElement(
          'cNvPr',
          prefix: 'p',
          attributes: <String, String>{
            'id': '${shape.groupId}',
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

  /// writeEmptyElement API.
  w.writeEmptyElement('nvPr', prefix: 'p');

  /// writeEndElement API.
  w.writeEndElement();

  /// writeStartElement API.
  w.writeStartElement('spPr', prefix: 'p');

  /// writeStartElement API.
  w.writeStartElement('xfrm', prefix: 'a');
  if (shape.transform.rot != 0) {
    w.writeAttribute('rot', '${shape.transform.rot}');
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
        PmlShapePreset.rect => 'rect',
      },
    },
  );
  if (shape.fillColor.isNotEmpty) {
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
  if (shape.text.isNotEmpty) {
    w.writeStartElement('txBody', prefix: 'p');
    w.writeEmptyElement('bodyPr', prefix: 'a');
    w.writeStartElement('p', prefix: 'a');
    if (shape.rightToLeft != null || shape.textAlign != PmlTextAlign.left) {
      final Map<String, String> pPr = <String, String>{};
      if (shape.textAlign != PmlTextAlign.left) {
        pPr['algn'] = switch (shape.textAlign) {
          PmlTextAlign.center => 'ctr',
          PmlTextAlign.right => 'r',
          PmlTextAlign.justify => 'just',
          PmlTextAlign.left => 'l',
        };
      }
      if (shape.rightToLeft != null) {
        pPr['rtl'] = shape.rightToLeft! ? '1' : '0';
      }
      w.writeEmptyElement('pPr', prefix: 'a', attributes: pPr);
    }
    w.writeStartElement('r', prefix: 'a');
    w.writeStartElement('t', prefix: 'a');
    w.writeText(shape.text);
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  /// writeEndElement API.
  w.writeEndElement();
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
