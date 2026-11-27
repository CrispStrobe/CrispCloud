import 'dart:math' as math;
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../builders/office_markup.dart';
import '../sheet/styles/sml_styles.dart' show applyNumberFormat;

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

/// Sides on which Word stores an optional distance between a picture and text.
enum PictureWrapDistanceEdge { top, bottom, left, right }

/// Legend placement (`c:legendPos`).
enum ChartLegendPos { bottom, top, left, right, topRight }

/// Native DrawingML outer shadow settings for a picture.
class PictureOuterShadow {
  const PictureOuterShadow({
    this.blurRadius = 0,
    this.distance = 0,
    this.directionDegrees = 0,
    this.color = '000000',
    this.opacity = 1,
    this.rotatesWithShape = true,
  });

  final double blurRadius;
  final double distance;
  final double directionDegrees;
  final String color;
  final double opacity;
  final bool rotatesWithShape;
}

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
    this._wrapDistT = 0,
    this._wrapDistB = 0,
    this._wrapDistL = 9,
    this._wrapDistR = 9,
    this.altTitle = '',
    this.altDescription = '',
    this.shadow = false,
    this.outerShadow,
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

  double _wrapDistT;
  double _wrapDistB;
  double _wrapDistL;
  double _wrapDistR;
  Set<PictureWrapDistanceEdge>? _sourceWrapDistances;
  final Set<PictureWrapDistanceEdge> _editedWrapDistances = {};

  /// Distance above the picture, in points. Assignments are explicit edits,
  /// including setting an imported, omitted distance to zero.
  double get wrapDistT => _wrapDistT;
  set wrapDistT(double value) {
    _wrapDistT = value;
    _editedWrapDistances.add(PictureWrapDistanceEdge.top);
  }

  /// Distance below the picture, in points.
  double get wrapDistB => _wrapDistB;
  set wrapDistB(double value) {
    _wrapDistB = value;
    _editedWrapDistances.add(PictureWrapDistanceEdge.bottom);
  }

  /// Distance to the left of the picture, in points.
  double get wrapDistL => _wrapDistL;
  set wrapDistL(double value) {
    _wrapDistL = value;
    _editedWrapDistances.add(PictureWrapDistanceEdge.left);
  }

  /// Distance to the right of the picture, in points.
  double get wrapDistR => _wrapDistR;
  set wrapDistR(double value) {
    _wrapDistR = value;
    _editedWrapDistances.add(PictureWrapDistanceEdge.right);
  }

  /// Capture source attribute presence after reading the four distance values.
  /// Office consumers can distinguish omission from an explicit zero.
  void retainWrapDistanceAttributes(Iterable<PictureWrapDistanceEdge> edges) {
    _sourceWrapDistances = Set<PictureWrapDistanceEdge>.unmodifiable(edges);
    _editedWrapDistances.clear();
  }

  /// New pictures emit model defaults. Imported pictures emit only source
  /// attributes and deliberate edits, preserving untouched omissions.
  bool writesWrapDistance(PictureWrapDistanceEdge edge) =>
      _sourceWrapDistances == null ||
      _sourceWrapDistances!.contains(edge) ||
      _editedWrapDistances.contains(edge);

  /// altTitle API.
  String altTitle;

  /// altDescription API.
  String altDescription;

  /// shadow API.
  bool shadow;
  PictureOuterShadow? outerShadow;

  /// copy API.
  PictureAdjust copy() =>
      PictureAdjust(
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
          outerShadow: outerShadow,
        )
        .._sourceWrapDistances = _sourceWrapDistances
        .._editedWrapDistances.addAll(_editedWrapDistances);

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
    outerShadow = null;
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
    this.titleSize,
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

  /// Point size of the authored chart title, when available.
  double? titleSize;

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
    titleSize: titleSize,
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

/// Geometry shared by the editor and PDF pie-chart renderers.
class OfficePieLayout {
  /// Builds the pie, its slice labels and its legend in chart coordinates.
  OfficePieLayout(OfficeVisual visual, double width, double height) {
    final chart = visual.chart;
    final points = visual.points
        .where((point) => point.value.isFinite && point.value >= 0)
        .toList();
    titleSize = chart.titleSize ?? 11;
    titleLines = visual.chartTitleLines(width, titleSize);
    var left = 8.0;
    var right = width - 8;
    var top = titleLines.isEmpty ? 6.0 : titleSize * titleLines.length + 10;
    var bottom = height - 6;
    if (chart.showLegend && points.isNotEmpty && right > left) {
      final side =
          chart.legendPos == ChartLegendPos.left ||
          chart.legendPos == ChartLegendPos.right ||
          chart.legendPos == ChartLegendPos.topRight;
      if (side) {
        final legendWidth = (right - left) * .35;
        final x = chart.legendPos == ChartLegendPos.left
            ? left
            : right - legendWidth;
        for (final (index, point) in points.indexed) {
          final y = top + index * 12;
          if (y + 12 > bottom) break;
          legend.add((point: point, x: x, y: y, width: legendWidth));
        }
        if (chart.legendPos == ChartLegendPos.left) {
          left += legendWidth + 6;
        } else {
          right -= legendWidth + 6;
        }
      } else {
        final rows = <List<({ChartPoint point, double width})>>[[]];
        final rowWidths = <double>[0];
        final available = right - left;
        for (final point in points) {
          final slot = math.min(available, 16 + point.label.runes.length * 4.1);
          if (rows.last.isNotEmpty && rowWidths.last + slot > available) {
            rows.add([]);
            rowWidths.add(0);
          }
          rows.last.add((point: point, width: slot));
          rowWidths[rowWidths.length - 1] += slot;
        }
        final maxRows = math.max(0, ((bottom - top) * .35 / 12).floor());
        final count = math.min(rows.length, maxRows);
        final above = chart.legendPos == ChartLegendPos.top;
        final startY = above ? top : bottom - count * 12;
        for (var row = 0; row < count; row++) {
          var x = left + (available - rowWidths[row]) / 2;
          for (final slot in rows[row]) {
            legend.add((
              point: slot.point,
              x: x,
              y: startY + row * 12,
              width: slot.width,
            ));
            x += slot.width;
          }
        }
        if (above) {
          top += count * 12;
        } else {
          bottom -= count * 12;
        }
      }
    }
    cx = (left + right) / 2;
    cy = (top + bottom) / 2;
    radius = math.max(0, math.min(right - left, bottom - top) * .4 - 3);
    if (points.isEmpty || radius == 0) return;
    final largest = points.fold(
      0.0,
      (maximum, point) => math.max(maximum, point.value),
    );
    if (largest == 0) return;
    final total = points.fold(0.0, (sum, point) => sum + point.value / largest);
    final shares = [
      for (final point in points) (point.value / largest) / total,
    ];
    final percentages = chart.showPercent
        ? _wholePercentages(shares)
        : const <int>[];
    var start = (chart.firstSliceAng - 90) * math.pi / 180;
    for (final (index, point) in points.indexed) {
      final sweep = 2 * math.pi * shares[index];
      final label = chart.showPercent
          ? '${percentages[index]}%'
          : chart.showDataLabels
          ? OfficeLineChart.formatTick(point.value)
          : '';
      if (sweep > 0 || label.isNotEmpty) {
        slices.add((point: point, start: start, sweep: sweep, label: label));
      }
      start += sweep;
    }
  }

  static List<int> _wholePercentages(List<double> shares) {
    final exact = shares.map((share) => share * 100).toList();
    final result = exact.map((value) => value.floor()).toList();
    final remaining =
        100 - result.fold<int>(0, (total, value) => total + value);
    // Distribute the rounding remainder so visible labels sum to 100%.
    final order = List<int>.generate(exact.length, (index) => index)
      ..sort((a, b) {
        final byRemainder = (exact[b] - result[b]).compareTo(
          exact[a] - result[a],
        );
        return byRemainder == 0 ? a.compareTo(b) : byRemainder;
      });
    for (final index in order.take(math.max(0, remaining))) {
      result[index]++;
    }
    return result;
  }

  /// Drawn slices and labels, in source order.
  final slices =
      <({ChartPoint point, double start, double sweep, String label})>[];

  /// Legend entries with local bounds.
  final legend = <({ChartPoint point, double x, double y, double width})>[];

  /// Chart title size in points.
  late final double titleSize;

  /// Chart title broken at word boundaries.
  late final List<String> titleLines;

  /// Horizontal position of the pie center within the chart.
  late final double cx;

  /// Vertical position of the pie center within the chart.
  late final double cy;

  /// Radius of the chart's pie.
  late final double radius;
}

/// Read-only line-chart data projected from an imported DrawingML cache.
class OfficeLineChart {
  /// Creates a chart whose point X values are zero-based category indices.
  OfficeLineChart({
    required List<String> categories,
    required List<ChartSeries> series,
    required this.connectGaps,
    List<String?> labelFormats = const [],
    this.locale = 'en_US',
  }) : categories = List.unmodifiable(categories),
       series = List.unmodifiable(series),
       labelFormats = List.unmodifiable(labelFormats);

  /// Shared category axis, including slots with missing values.
  final List<String> categories;

  /// Each series keeps its own name, color, and indexed values.
  final List<ChartSeries> series;

  /// Whether a line spans empty cells.
  final bool connectGaps;

  /// Source format for each enabled series' point labels.
  final List<String?> labelFormats;

  /// Language used by the native chart's labels.
  final String locale;

  /// A formatted label, or an empty string when its series has labels disabled.
  String pointLabel(int seriesIndex, double value) {
    if (seriesIndex >= labelFormats.length) return '';
    final format = labelFormats[seriesIndex];
    return format == null ? '' : _format(value, format);
  }

  /// Numeric axis labels follow the chart locale.
  String axisLabel(double value) =>
      _format(value, value.abs() >= 1 || value == 0 ? '#,##0' : '0.###');

  String _format(double value, String code) {
    final verified = Intl.verifiedLocale(
      locale,
      NumberFormat.localeExists,
      onFailure: (_) => 'en_US',
    );
    final symbols = NumberFormat.decimalPattern(verified).symbols;
    return applyNumberFormat(
      value,
      code,
      displayDecimalSeparator: symbols.DECIMAL_SEP,
      displayGroupSeparator: symbols.GROUP_SEP,
    );
  }

  /// Regular grid ticks that enclose the data range.
  List<double> get axisTicks {
    final range = limits;
    final span = range.max - range.min;
    if (span.isFinite && span > 1e-300 && span < 1e300) {
      final target = span / 8;
      final power = math
          .pow(10, (math.log(target) / math.ln10).floor())
          .toDouble();
      final scale = target / power;
      const steps = [1.0, 2.0, 2.5, 5.0, 10.0];
      final nearest = steps.reduce(
        (a, b) => (a - scale).abs() <= (b - scale).abs() ? a : b,
      );
      final step = nearest * power;
      final first = (range.min / step).floor();
      final last = (range.max / step).ceil();
      return [for (var i = first; i <= last; i++) i * step];
    }
    return [
      for (var i = 0; i <= 4; i++) range.min * (1 - i / 4) + range.max * i / 4,
    ];
  }

  /// Shared signed limits for all series.
  ({double min, double max}) get limits {
    var min = 0.0;
    var max = 0.0;
    for (final series in this.series) {
      for (final point in series.points) {
        min = math.min(min, point.value);
        max = math.max(max, point.value);
      }
    }
    return (min: min, max: min == max ? 1 : max);
  }

  /// Fraction of the shared category axis occupied by a point.
  double categoryFraction(int index) =>
      categories.length < 2 ? 0.5 : index / (categories.length - 1);

  /// Interpolates a finite value on a shared axis, including signed values.
  static double valueFraction(double value, ({double min, double max}) limits) {
    final span = limits.max - limits.min;
    if (span.isFinite) return (value - limits.min) / span;
    return (value / 2 - limits.min / 2) / (limits.max / 2 - limits.min / 2);
  }

  /// Category labels to paint without crowding the axis.
  Iterable<int> get labelIndices sync* {
    final last = categories.length - 1;
    final step = math.max(1, (last / 7).ceil());
    for (var index = 0; index < last; index += step) {
      yield index;
    }
    if (last >= 0) yield last;
  }

  /// Compact labels for the display axis.
  static String formatTick(double value) {
    final (divisor, suffix) = switch (value.abs()) {
      >= 1e12 => (1e12, 'T'),
      >= 1e9 => (1e9, 'B'),
      >= 1e6 => (1e6, 'M'),
      >= 1e3 => (1e3, 'k'),
      _ => (1.0, ''),
    };
    if (value == 0) return '0';
    var text = (value / divisor).toStringAsPrecision(3);
    if (text.contains('.') && !text.contains('e')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return '$text$suffix';
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
    this.importedLineChart,
  }) : points = points ?? <ChartPoint>[],
       picture = picture ?? PictureAdjust(),
       chart = chart ?? ChartDisplay();

  /// kind API.
  OfficeVisualKind kind;

  /// title API.
  String title;

  /// points API.
  List<ChartPoint> points;

  /// Native line-chart display data, independent of the editable point list.
  OfficeLineChart? importedLineChart;

  /// Wraps an authored chart title within its frame.
  List<String> chartTitleLines(double width, double size) {
    if (!chart.showTitle || title.isEmpty) return const [];
    final available = width - 16;
    if (available <= 0) return const [];
    final lines = <String>[];
    for (final paragraph in title.split('\n')) {
      var line = '';
      for (final word in paragraph.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final next = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && next.runes.length * size * .53 > available) {
          lines.add(line);
          line = word;
        } else {
          line = next;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }
    return lines;
  }

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
    importedLineChart: importedLineChart,
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
    importedLineChart = source.importedLineChart;
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

/// Native worksheet drawing marker. Insets are stored in OOXML units.
typedef SmlDrawingMarker = ({int col, int row, int colEmu, int rowEmu});

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
    this.sourceChartPartUri,
    this.sourceChartState,
    this.importedEndMarker,
    this.twoCellEditAs,
  }) : _importedGeometry = importedEndMarker == null
           ? null
           : (col, row, offsetX, offsetY, visual.width, visual.height);

  /// Original end marker from the worksheet drawing part.
  final SmlDrawingMarker? importedEndMarker;
  final (int, int, double, double, double, double)? _importedGeometry;

  /// Native end marker, available until the drawing is moved or resized.
  SmlDrawingMarker? get twoCellEnd =>
      _importedGeometry ==
          (col, row, offsetX, offsetY, visual.width, visual.height)
      ? importedEndMarker
      : null;

  /// How Excel moves or sizes the drawing when the underlying grid changes.
  final String? twoCellEditAs;

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

  /// Original native chart owner and editable projection. Unchanged imported
  /// charts retain all series/title references and native chart metadata.
  String? sourceChartPartUri;
  String? sourceChartState;
}
