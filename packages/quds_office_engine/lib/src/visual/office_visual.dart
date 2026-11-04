import 'dart:typed_data';

import '../builders/office_markup.dart';

/// In-document visual: picture, chart, or SmartArt-style diagram.
enum OfficeVisualKind {
  picture,
  chartColumn,
  chartBar,
  chartPie,
  chartLine,
  diagramProcess,
  diagramCycle,
  diagramHierarchy,
}

/// Text wrapping for a Word inline / floating picture (`wp:inline` / `wp:anchor`).
enum PictureWrap {
  inline,
  square,
  tight,
  through,
  topAndBottom,
  behind,
  inFront,
}

/// Legend placement (`c:legendPos`).
enum ChartLegendPos { bottom, top, left, right, topRight }

/// Crop, tone, rotation, stroke, wrap, and effects applied to a picture.
class PictureAdjust {
  /// PictureAdjust API.
  PictureAdjust({
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 0,
    this.cropBottom = 0,
    this.rotationDeg = 0,
    this.brightness = 0,
    this.contrast = 1,
    this.transparency = 0,
    this.borderColor = '',
    this.borderWidth = 0,
    this.flipH = false,
    this.flipV = false,
    this.lockAspect = true,
    this.wrap = PictureWrap.inline,
    this.wrapDistT = 0,
    this.wrapDistB = 0,
    this.wrapDistL = 9,
    this.wrapDistR = 9,
    this.altTitle = '',
    this.altDescription = '',
    this.shadow = false,
  });

  /// cropLeft API.
  double cropLeft;

  /// cropTop API.
  double cropTop;

  /// cropRight API.
  double cropRight;

  /// cropBottom API.
  double cropBottom;

  /// rotationDeg API.
  double rotationDeg;

  /// brightness API.
  double brightness;

  /// contrast API.
  double contrast;

  /// transparency API.
  double transparency;

  /// borderColor API.
  String borderColor;

  /// borderWidth API.
  double borderWidth;

  /// flipH API.
  bool flipH;

  /// flipV API.
  bool flipV;

  /// lockAspect API.
  bool lockAspect;

  /// wrap API.
  PictureWrap wrap;

  /// wrapDistT API.
  double wrapDistT;

  /// wrapDistB API.
  double wrapDistB;

  /// wrapDistL API.
  double wrapDistL;

  /// wrapDistR API.
  double wrapDistR;

  /// altTitle API.
  String altTitle;

  /// altDescription API.
  String altDescription;

  /// shadow API.
  bool shadow;

  /// copy API.
  PictureAdjust copy() => PictureAdjust(
    cropLeft: cropLeft,
    cropTop: cropTop,
    cropRight: cropRight,
    cropBottom: cropBottom,
    rotationDeg: rotationDeg,
    brightness: brightness,
    contrast: contrast,
    transparency: transparency,
    borderColor: borderColor,
    borderWidth: borderWidth,
    flipH: flipH,
    flipV: flipV,
    lockAspect: lockAspect,
    wrap: wrap,
    wrapDistT: wrapDistT,
    wrapDistB: wrapDistB,
    wrapDistL: wrapDistL,
    wrapDistR: wrapDistR,
    altTitle: altTitle,
    altDescription: altDescription,
    shadow: shadow,
  );

  /// reset API.
  void reset() {
    cropLeft = 0;
    cropTop = 0;
    cropRight = 0;
    cropBottom = 0;
    rotationDeg = 0;
    brightness = 0;
    contrast = 1;
    transparency = 0;
    borderColor = '';
    borderWidth = 0;
    flipH = false;
    flipV = false;
    lockAspect = true;
    wrap = PictureWrap.inline;
    wrapDistT = 0;
    wrapDistB = 0;
    wrapDistL = 9;
    wrapDistR = 9;
    altTitle = '';
    altDescription = '';
    shadow = false;
  }
}

/// Legend, labels, axes, and titles for a chart or diagram.
class ChartDisplay {
  /// ChartDisplay API.
  ChartDisplay({
    this.showLegend = true,
    this.showDataLabels = false,
    this.showAxes = true,
    this.showGridlines = true,
    this.showTitle = true,
    this.showPercent = false,
    this.legendPos = ChartLegendPos.bottom,
    this.categoryTitle = '',
    this.valueTitle = '',
    this.gapWidth = 120,
    this.firstSliceAng = 0,
    this.holeSize = 50,
    this.rtl = false,
    this.view3d = false,
  });

  /// showLegend API.
  bool showLegend;

  /// showDataLabels API.
  bool showDataLabels;

  /// showAxes API.
  bool showAxes;

  /// showGridlines API.
  bool showGridlines;

  /// showTitle API.
  bool showTitle;

  /// showPercent API.
  bool showPercent;

  /// legendPos API.
  ChartLegendPos legendPos;

  /// categoryTitle API.
  String categoryTitle;

  /// valueTitle API.
  String valueTitle;

  /// gapWidth API.
  int gapWidth;

  /// firstSliceAng API.
  int firstSliceAng;

  /// holeSize API.
  int holeSize;

  /// When true, chart XML is written with `c:chart/@rtl`.
  bool rtl;

  /// Oblique 3D chart (`bar3DChart` / `pie3DChart` plus `c:view3D`).
  bool view3d;

  /// copy API.
  ChartDisplay copy() => ChartDisplay(
    showLegend: showLegend,
    showDataLabels: showDataLabels,
    showAxes: showAxes,
    showGridlines: showGridlines,
    showTitle: showTitle,
    showPercent: showPercent,
    legendPos: legendPos,
    categoryTitle: categoryTitle,
    valueTitle: valueTitle,
    gapWidth: gapWidth,
    firstSliceAng: firstSliceAng,
    holeSize: holeSize,
    rtl: rtl,
    view3d: view3d,
  );
}

/// Class VisualPalette.
abstract final class VisualPalette {
  /// fills API.
  static const List<String> fills = <String>[
    '2B579A',
    '217346',
    'B7472A',
    'ED7D31',
    '7030A0',
    '5B9BD5',
    '00B0F0',
    'C00000',
    '548235',
    '833C0C',
  ];

  /// borders API.
  static const List<String> borders = <String>[
    '',
    '2B579A',
    '217346',
    'B7472A',
    '000000',
    'C9A227',
  ];

  /// nextFill API.
  static String nextFill(String current) {
    final int i = fills.indexOf(current.toUpperCase());
    return fills[(i + 1) % fills.length];
  }

  /// nextBorder API.
  static String nextBorder(String current) {
    final int i = borders.indexOf(current.toUpperCase());
    return borders[(i + 1) % borders.length];
  }
}

/// Class OfficeVisual.
class OfficeVisual {
  /// OfficeVisual API.
  OfficeVisual({
    required this.kind,
    this.title = '',
    List<ChartPoint>? points,
    this.imageBytes,
    this.width = 360,
    this.height = 180,
    this.offsetX = 0,
    this.offsetY = 0,
    PictureAdjust? picture,
    ChartDisplay? chart,
  }) : points = points ?? <ChartPoint>[],
       picture = picture ?? PictureAdjust(),
       chart = chart ?? ChartDisplay();

  /// kind API.
  OfficeVisualKind kind;

  /// title API.
  String title;

  /// points API.
  List<ChartPoint> points;

  /// imageBytes API.
  Uint8List? imageBytes;

  /// width API.
  double width;

  /// height API.
  double height;

  /// offsetX API.
  double offsetX;

  /// offsetY API.
  double offsetY;

  /// picture API.
  PictureAdjust picture;

  /// chart API.
  ChartDisplay chart;

  /// isChart API.
  bool get isChart =>
      kind == OfficeVisualKind.chartColumn ||
      kind == OfficeVisualKind.chartBar ||
      kind == OfficeVisualKind.chartPie ||
      kind == OfficeVisualKind.chartLine;

  /// isDiagram API.
  bool get isDiagram =>
      kind == OfficeVisualKind.diagramProcess ||
      kind == OfficeVisualKind.diagramCycle ||
      kind == OfficeVisualKind.diagramHierarchy;

  /// isPicture API.
  bool get isPicture => kind == OfficeVisualKind.picture;

  /// copy API.
  OfficeVisual copy() => OfficeVisual(
    kind: kind,
    title: title,
    points: <ChartPoint>[
      for (final ChartPoint point in points)
        ChartPoint(label: point.label, value: point.value, color: point.color),
    ],
    imageBytes: imageBytes == null ? null : Uint8List.fromList(imageBytes!),
    width: width,
    height: height,
    offsetX: offsetX,
    offsetY: offsetY,
    picture: picture.copy(),
    chart: chart.copy(),
  );

  /// restoreFrom API.
  void restoreFrom(OfficeVisual source) {
    kind = source.kind;
    title = source.title;
    points
      ..clear()
      ..addAll(source.points);
    imageBytes = source.imageBytes == null
        ? null
        : Uint8List.fromList(source.imageBytes!);
    width = source.width;
    height = source.height;
    offsetX = source.offsetX;
    offsetY = source.offsetY;
    picture = source.picture.copy();
    chart = source.chart.copy();
  }

  /// addSamplePoint API.
  void addSamplePoint({required bool arabic}) {
    final int n = points.length + 1;
    points.add(
      ChartPoint(
        label: arabic ? 'ن$n' : 'P$n',
        value: 40 + (n * 7) % 35,
        color: VisualPalette.fills[points.length % VisualPalette.fills.length],
      ),
    );
  }

  /// removeLastPoint API.
  void removeLastPoint() {
    if (points.length > 1) {
      points.removeLast();
    }
  }

  /// bumpPointValue API.
  void bumpPointValue(int index, double delta) {
    if (index < 0 || index >= points.length) {
      return;
    }
    final ChartPoint p = points[index];
    points[index] = p.copyWith(value: (p.value + delta).clamp(1, 200));
  }

  /// cyclePointColor API.
  void cyclePointColor(int index) {
    if (index < 0 || index >= points.length) {
      return;
    }
    final ChartPoint p = points[index];
    points[index] = p.copyWith(color: VisualPalette.nextFill(p.color));
  }

  /// cyclePointLabel API.
  void cyclePointLabel(int index, {required bool arabic}) {
    if (index < 0 || index >= points.length) {
      return;
    }
    const List<String> en = <String>['Q1', 'Q2', 'Q3', 'Q4', 'East', 'West'];
    const List<String> ar = <String>['ر١', 'ر٢', 'ر٣', 'ر٤', 'شرق', 'غرب'];
    final List<String> labels = arabic ? ar : en;
    final ChartPoint p = points[index];
    final int i = labels.indexOf(p.label);
    points[index] = p.copyWith(label: labels[(i + 1) % labels.length]);
  }

  /// cycleTitle API.
  void cycleTitle({required bool arabic}) {
    const List<String> en = <String>[
      'Sales',
      'Revenue',
      'Share',
      'Trend',
      'Mix',
    ];
    const List<String> ar = <String>['مبيعات', 'إيراد', 'حصة', 'اتجاه', 'مزيج'];
    final List<String> titles = arabic ? ar : en;
    final int i = titles.indexOf(title);
    title = titles[(i + 1) % titles.length];
  }

  /// cropBy API.
  void cropBy(double delta) {
    final double next = (picture.cropLeft + delta).clamp(0.0, 0.4);
    picture
      ..cropLeft = next
      ..cropTop = next
      ..cropRight = next
      ..cropBottom = next;
  }

  /// rotateBy API.
  void rotateBy(double degrees) {
    picture.rotationDeg = (picture.rotationDeg + degrees) % 360;
  }

  /// bumpBrightness API.
  void bumpBrightness(double delta) {
    picture.brightness = (picture.brightness + delta).clamp(-0.5, 0.5);
  }

  /// bumpContrast API.
  void bumpContrast(double delta) {
    picture.contrast = (picture.contrast + delta).clamp(0.5, 1.8);
  }

  /// cycleBorder API.
  void cycleBorder() {
    picture.borderColor = VisualPalette.nextBorder(picture.borderColor);
    picture.borderWidth = picture.borderColor.isEmpty ? 0 : 3;
  }

  /// bumpTransparency API.
  void bumpTransparency(double delta) {
    picture.transparency = (picture.transparency + delta).clamp(0.0, 0.85);
  }

  /// toggleFlipH API.
  void toggleFlipH() {
    picture.flipH = !picture.flipH;
  }

  /// toggleFlipV API.
  void toggleFlipV() {
    picture.flipV = !picture.flipV;
  }

  /// cycleWrap API.
  void cycleWrap() {
    const List<PictureWrap> order = PictureWrap.values;
    picture.wrap = order[(order.indexOf(picture.wrap) + 1) % order.length];
  }

  /// cycleLegendPos API.
  void cycleLegendPos() {
    const List<ChartLegendPos> order = ChartLegendPos.values;
    chart.legendPos =
        order[(order.indexOf(chart.legendPos) + 1) % order.length];
  }

  /// resetPicture API.
  void resetPicture() {
    picture.reset();
  }

  /// nextKind API.
  static OfficeVisualKind nextKind(OfficeVisualKind kind) {
    const List<OfficeVisualKind> order = OfficeVisualKind.values;
    return order[(order.indexOf(kind) + 1) % order.length];
  }

  /// sampleSeries API.
  static List<ChartPoint> sampleSeries({bool arabic = false}) {
    return <ChartPoint>[
      ChartPoint(label: arabic ? 'ر١' : 'Q1', value: 42, color: '2B579A'),
      ChartPoint(label: arabic ? 'ر٢' : 'Q2', value: 55, color: '217346'),
      ChartPoint(label: arabic ? 'ر٣' : 'Q3', value: 38, color: 'B7472A'),
      ChartPoint(label: arabic ? 'ر٤' : 'Q4', value: 61, color: 'ED7D31'),
    ];
  }

  /// sampleSteps API.
  static List<ChartPoint> sampleSteps({bool arabic = false}) {
    return <ChartPoint>[
      ChartPoint(label: arabic ? 'خطّط' : 'Plan', value: 1, color: '2B579A'),
      ChartPoint(label: arabic ? 'ابنِ' : 'Build', value: 1, color: '217346'),
      ChartPoint(label: arabic ? 'راجع' : 'Review', value: 1, color: 'B7472A'),
    ];
  }
}

/// Floating drawing anchored to a worksheet cell.
class SmlDrawing {
  /// SmlDrawing API.
  SmlDrawing({
    required this.visual,
    this.col = 6,
    this.row = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.sourceFromA1,
    this.sourceToA1,
    this.sourceSheetName,
    this.labelsFromA1,
    this.labelsToA1,
  });

  /// visual API.
  OfficeVisual visual;

  /// col API.
  int col;

  /// row API.
  int row;

  /// offsetX API.
  double offsetX;

  /// offsetY API.
  double offsetY;

  /// sourceFromA1 API.
  String? sourceFromA1;

  /// sourceToA1 API.
  String? sourceToA1;

  /// Sheet holding the source and label ranges; null for the drawing's own
  /// sheet.
  String? sourceSheetName;

  /// First cell of the category (label) range, e.g. a chart's `c:cat` ref.
  String? labelsFromA1;

  /// Last cell of the category (label) range.
  String? labelsToA1;
}
