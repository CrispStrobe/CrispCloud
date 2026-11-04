import '../builders/office_markup.dart';
import '../xml/xml_reader.dart';
import '../xml/xml_writer.dart';
import 'office_visual.dart';

/// Shared DrawingML conversions used by Word, Excel, and PowerPoint writers.
abstract final class DrawingmlVisualIo {
  /// emuPerPoint API.
  static const int emuPerPoint = 12700;

  /// emuPerPixel API.
  static const int emuPerPixel = 9525;

  /// pointsToEmu API.
  static int pointsToEmu(double points) =>
      (points.clamp(4, 4000) * emuPerPoint).round();

  /// emuToPoints API.
  static double emuToPoints(int emu) => emu / emuPerPoint;

  /// pixelsToEmu API.
  static int pixelsToEmu(double pixels) =>
      (pixels.clamp(0, 20000) * emuPerPixel).round();

  /// emuToPixels API.
  static double emuToPixels(int emu) => emu / emuPerPixel;

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

  /// DrawingML `a:lum/@bright` is 1000ths of a percent; 0 is unchanged.
  static int brightnessToLum(double brightness) =>
      (brightness.clamp(-0.5, 0.5) * 100000).round();

  /// lumToBrightness API.
  static double lumToBrightness(String? raw) {
    final int? value = int.tryParse(raw ?? '');
    if (value == null) {
      return 0;
    }
    return (value / 100000).clamp(-0.5, 0.5);
  }

  /// DrawingML contrast 0 = unchanged; our model uses 1.0 as unchanged.
  static int contrastToLum(double contrast) =>
      ((contrast.clamp(0.5, 1.8) - 1) * 100000).round();

  /// lumToContrast API.
  static double lumToContrast(String? raw) {
    final int? value = int.tryParse(raw ?? '');
    if (value == null) {
      return 1;
    }
    return (1 + value / 100000).clamp(0.5, 1.8);
  }

  /// transparencyToAlpha API.
  static int transparencyToAlpha(double transparency) =>
      ((1 - transparency.clamp(0.0, 1.0)) * 100000).round();

  /// alphaToTransparency API.
  static double alphaToTransparency(String? raw) {
    final int? value = int.tryParse(raw ?? '');
    if (value == null) {
      return 0;
    }
    return (1 - value / 100000).clamp(0.0, 1.0);
  }

  /// borderToEmu API.
  static int borderToEmu(double points) =>
      (points.clamp(0, 24) * emuPerPoint).round();

  /// emuToBorder API.
  static double emuToBorder(int emu) => (emu / emuPerPoint).clamp(0, 24);

  /// legendPosXml API.
  static String legendPosXml(ChartLegendPos pos) => switch (pos) {
    ChartLegendPos.bottom => 'b',
    ChartLegendPos.top => 't',
    ChartLegendPos.left => 'l',
    ChartLegendPos.right => 'r',
    ChartLegendPos.topRight => 'tr',
  };

  /// legendPosFromXml API.
  static ChartLegendPos legendPosFromXml(String? raw) => switch (raw) {
    't' => ChartLegendPos.top,
    'l' => ChartLegendPos.left,
    'r' => ChartLegendPos.right,
    'tr' => ChartLegendPos.topRight,
    _ => ChartLegendPos.bottom,
  };

  /// writeBlip API.
  static void writeBlip(
    XmlWriter w, {
    required String relationshipId,
    required PictureAdjust adj,
  }) {
    w.writeStartElement('blip', prefix: 'a');
    w.writeAttribute('r:embed', relationshipId);
    if (adj.brightness.abs() > 0.001 || (adj.contrast - 1).abs() > 0.001) {
      w.writeEmptyElement(
        'lum',
        prefix: 'a',
        attributes: <String, String>{
          'bright': '${brightnessToLum(adj.brightness)}',
          'contrast': '${contrastToLum(adj.contrast)}',
        },
      );
    }
    if (adj.transparency > 0.001) {
      w.writeEmptyElement(
        'alphaModFix',
        prefix: 'a',
        attributes: <String, String>{
          'amt': '${transparencyToAlpha(adj.transparency)}',
        },
      );
    }
    w.writeEndElement();
  }

  /// writeSrcRect API.
  static void writeSrcRect(XmlWriter w, PictureAdjust adj) {
    if (adj.cropLeft <= 0 &&
        adj.cropTop <= 0 &&
        adj.cropRight <= 0 &&
        adj.cropBottom <= 0) {
      return;
    }
    w.writeEmptyElement(
      'srcRect',
      prefix: 'a',
      attributes: <String, String>{
        'l': '${cropToSrc(adj.cropLeft)}',
        't': '${cropToSrc(adj.cropTop)}',
        'r': '${cropToSrc(adj.cropRight)}',
        'b': '${cropToSrc(adj.cropBottom)}',
      },
    );
  }

  /// writeXfrm API.
  static void writeXfrm(
    XmlWriter w, {
    required int cx,
    required int cy,
    required PictureAdjust adj,
    int offX = 0,
    int offY = 0,
  }) {
    w.writeStartElement('xfrm', prefix: 'a');
    final int rot = (adj.rotationDeg * 60000).round();
    if (rot != 0) {
      w.writeAttribute('rot', '$rot');
    }
    if (adj.flipH) {
      w.writeAttribute('flipH', '1');
    }
    if (adj.flipV) {
      w.writeAttribute('flipV', '1');
    }
    w.writeEmptyElement(
      'off',
      prefix: 'a',
      attributes: <String, String>{'x': '$offX', 'y': '$offY'},
    );
    w.writeEmptyElement(
      'ext',
      prefix: 'a',
      attributes: <String, String>{'cx': '$cx', 'cy': '$cy'},
    );
    w.writeEndElement();
  }

  /// writeLine API.
  static void writeLine(XmlWriter w, PictureAdjust adj) {
    if (adj.borderWidth <= 0 || adj.borderColor.isEmpty) {
      return;
    }
    w.writeStartElement('ln', prefix: 'a');
    w.writeAttribute('w', '${borderToEmu(adj.borderWidth)}');
    w.writeStartElement('solidFill', prefix: 'a');
    w.writeEmptyElement(
      'srgbClr',
      prefix: 'a',
      attributes: <String, String>{'val': OfficeMarkup.srgb(adj.borderColor)},
    );
    w.writeEndElement();
    w.writeEndElement();
  }

  /// writeShadow API.
  static void writeShadow(XmlWriter w, PictureAdjust adj) {
    if (!adj.shadow) {
      return;
    }
    w.writeStartElement('effectLst', prefix: 'a');
    w.writeStartElement('outerShdw', prefix: 'a');
    w.writeAttribute('blurRad', '50800');
    w.writeAttribute('dist', '38100');
    w.writeAttribute('dir', '2700000');
    w.writeStartElement('srgbClr', prefix: 'a');
    w.writeAttribute('val', '000000');
    w.writeEmptyElement(
      'alpha',
      prefix: 'a',
      attributes: <String, String>{'val': '40000'},
    );
    w.writeEndElement();
    w.writeEndElement();
    w.writeEndElement();
  }

  /// wrapFromDrawing API.
  static PictureWrap wrapFromDrawing({
    required String localName,
    required bool behindDoc,
  }) {
    return switch (localName) {
      'wrapSquare' => PictureWrap.square,
      'wrapTight' => PictureWrap.tight,
      'wrapThrough' => PictureWrap.through,
      'wrapTopAndBottom' => PictureWrap.topAndBottom,
      'wrapNone' => behindDoc ? PictureWrap.behind : PictureWrap.inFront,
      _ => PictureWrap.inline,
    };
  }

  /// applyXfrm API.
  static void applyXfrm(PictureAdjust adj, XmlPullReader reader) {
    final int? rot = int.tryParse(reader.getAttribute('rot') ?? '');
    if (rot != null) {
      adj.rotationDeg = rot / 60000;
    }
    final String? flipH = reader.getAttribute('flipH');
    adj.flipH = flipH == '1' || flipH?.toLowerCase() == 'true';
    final String? flipV = reader.getAttribute('flipV');
    adj.flipV = flipV == '1' || flipV?.toLowerCase() == 'true';
  }

  /// applySrcRect API.
  static void applySrcRect(PictureAdjust adj, XmlPullReader reader) {
    adj
      ..cropLeft = srcToCrop(reader.getAttribute('l'))
      ..cropTop = srcToCrop(reader.getAttribute('t'))
      ..cropRight = srcToCrop(reader.getAttribute('r'))
      ..cropBottom = srcToCrop(reader.getAttribute('b'));
  }

  /// applyLum API.
  static void applyLum(PictureAdjust adj, XmlPullReader reader) {
    adj.brightness = lumToBrightness(reader.getAttribute('bright'));
    adj.contrast = lumToContrast(reader.getAttribute('contrast'));
  }

  /// parseChart API.
  /// Range formulas (`c:f`) of the first series' categories and values, e.g.
  /// `'Sheet'!$B$1:$B$3`. Charts written without a value cache (openpyxl and
  /// other generators) can only be drawn from these.
  static ({String? categories, String? values}) chartSeriesRefs(String xml) {
    final XmlPullReader reader = XmlPullReader(xml);
    String? categories;
    String? values;
    String? region;
    while (reader.next()) {
      final String name = reader.localName;
      if (reader.eventType == XmlEventType.endElement) {
        if (name == region) {
          region = null;
        } else if (name == 'ser' && (categories != null || values != null)) {
          break;
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      if ((name == 'cat' || name == 'val') && !reader.isEmptyElement) {
        region = name;
      } else if (name == 'f' && region != null) {
        final String text = _elementText(reader).trim();
        if (region == 'cat') {
          categories ??= text;
        } else {
          values ??= text;
        }
      }
    }
    return (categories: categories, values: values);
  }

  static OfficeVisual parseChart(
    String xml, {
    required String name,
    required double width,
    required double height,
  }) {
    final XmlPullReader reader = XmlPullReader(xml);
    var kind = OfficeVisualKind.chartColumn;
    var inCat = false;
    var inVal = false;
    var inTitle = false;
    var inDpt = false;
    var dptColorTaken = false;
    var catsLocked = false;
    var valsLocked = false;
    var showLegend = false;
    var showDataLabels = false;
    var showPercent = false;
    var showAxes = true;
    var showGridlines = false;
    var showTitle = false;
    var legendPos = ChartLegendPos.bottom;
    var gapWidth = 120;
    var firstSliceAng = 0;
    var holeSize = 50;
    final List<String> labels = <String>[];
    final List<double> values = <double>[];
    final List<String> colors = <String>[];
    final StringBuffer title = StringBuffer();
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement) {
        if (reader.localName == 'cat') {
          inCat = false;
          if (labels.isNotEmpty) {
            catsLocked = true;
          }
        } else if (reader.localName == 'val') {
          inVal = false;
          if (values.isNotEmpty) {
            valsLocked = true;
          }
        } else if (reader.localName == 'title') {
          inTitle = false;
        } else if (reader.localName == 'dPt') {
          inDpt = false;
          dptColorTaken = false;
        }
        continue;
      }
      if (reader.eventType != XmlEventType.startElement) {
        continue;
      }
      switch (reader.localName) {
        case 'pieChart':
        case 'doughnutChart':
          kind = OfficeVisualKind.chartPie;
        case 'lineChart':
          kind = OfficeVisualKind.chartLine;
        case 'barChart':
          kind = OfficeVisualKind.chartColumn;
        case 'barDir':
          if ((reader.getAttribute('val') ?? '') == 'bar') {
            kind = OfficeVisualKind.chartBar;
          }
        case 'cat':
          if (!catsLocked) {
            inCat = true;
          }
        case 'val':
          if (!valsLocked) {
            inVal = true;
          }
        case 'title':
          inTitle = true;
          showTitle = true;
        case 'dPt':
          inDpt = true;
          dptColorTaken = false;
        case 'legend':
          showLegend = true;
        case 'legendPos':
          legendPos = legendPosFromXml(reader.getAttribute('val'));
        case 'showVal':
          if ((reader.getAttribute('val') ?? '1') != '0') {
            showDataLabels = true;
          }
        case 'showPercent':
          if ((reader.getAttribute('val') ?? '0') == '1') {
            showPercent = true;
            showDataLabels = true;
          }
        case 'majorGridlines':
          showGridlines = true;
        case 'delete':
          if ((reader.getAttribute('val') ?? '0') == '1') {
            showAxes = false;
          }
        case 'gapWidth':
          gapWidth = int.tryParse(reader.getAttribute('val') ?? '') ?? gapWidth;
        case 'firstSliceAng':
          firstSliceAng =
              int.tryParse(reader.getAttribute('val') ?? '') ?? firstSliceAng;
        case 'holeSize':
          holeSize = int.tryParse(reader.getAttribute('val') ?? '') ?? holeSize;
        case 'srgbClr':
          final String? hex = reader.getAttribute('val');
          if (hex != null &&
              hex.isNotEmpty &&
              inDpt &&
              !dptColorTaken &&
              hex.toUpperCase() != 'FFFFFF') {
            colors.add(hex);
            dptColorTaken = true;
          }
        case 'v':
          if (reader.isEmptyElement) {
            break;
          }
          final String text = _elementText(reader);
          if (inCat) {
            labels.add(text);
          } else if (inVal) {
            values.add(double.tryParse(text) ?? 0);
          }
        case 't':
          if (inTitle && !reader.isEmptyElement) {
            title.write(_elementText(reader));
          }
      }
    }
    final int n = labels.length > values.length ? labels.length : values.length;
    final String parsedTitle = title.toString().trim();
    return OfficeVisual(
      kind: kind,
      title: parsedTitle.isEmpty ? name : parsedTitle,
      width: width,
      height: height,
      points: <ChartPoint>[
        for (int i = 0; i < n; i++)
          ChartPoint(
            label: i < labels.length ? labels[i] : 'P${i + 1}',
            value: i < values.length ? values[i] : 0,
            color: i < colors.length ? colors[i] : _chartColor(i),
          ),
      ],
      chart: ChartDisplay(
        showLegend: showLegend,
        showDataLabels: showDataLabels,
        showAxes: showAxes,
        showGridlines: showGridlines,
        showTitle: showTitle || parsedTitle.isNotEmpty,
        showPercent: showPercent,
        legendPos: legendPos,
        gapWidth: gapWidth,
        firstSliceAng: firstSliceAng,
        holeSize: holeSize,
      ),
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

  static String _chartColor(int index) {
    const List<String> palette = <String>[
      '2B579A',
      '217346',
      'B7472A',
      'ED7D31',
      '7030A0',
      '00B0F0',
    ];
    return palette[index % palette.length];
  }
}
