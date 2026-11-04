/// Chart data model and vector rendering for report charts.
///
/// The renderer emits ordinary layout primitives (rectangles, lines, paths,
/// shaped text), so PDF export and the Flutter preview draw charts with no
/// chart-specific code, and Arabic labels shape like any other report text.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../builders/drawingml_charts.dart';
import '../builders/office_markup.dart';
import '../visual/office_visual.dart';
import 'report_expression_engine.dart';
import 'report_fonts.dart';
import 'report_format.dart';
import 'report_layout.dart';
import 'report_shape.dart';
import 'report_template.dart';
import 'report_units.dart';
import 'report_value.dart';

/// One resolved series: a value per category.
class ReportChartSeriesData {
  /// ReportChartSeriesData API.
  const ReportChartSeriesData({
    required this.name,
    required this.color,
    required this.values,
    this.xs,
    this.sizes,
    this.style = ReportSeriesStyle.column,
    this.secondary = false,
    this.totals,
  });

  /// Legend label (may be empty for single-series charts).
  final String name;

  /// color API.
  final ReportColor color;

  /// Same length as [ReportChartData.categories]. Y values of a point chart.
  final List<double> values;

  /// X values of a scatter or bubble series. Null uses the category index.
  final List<double>? xs;

  /// Bubble areas. Null draws a fixed marker.
  final List<double>? sizes;

  /// How a combo chart draws this series.
  final ReportSeriesStyle style;

  /// Use the secondary value axis.
  final bool secondary;

  /// Waterfall categories that are absolute totals.
  final List<bool>? totals;

  /// Copy with [values] (and the parallel lists) reordered by [order].
  ReportChartSeriesData pick(List<int> order) => ReportChartSeriesData(
    name: name,
    color: color,
    values: <double>[for (final int i in order) values[i]],
    xs: xs == null ? null : <double>[for (final int i in order) xs![i]],
    sizes: sizes == null
        ? null
        : <double>[for (final int i in order) sizes![i]],
    style: style,
    secondary: secondary,
    totals: totals == null
        ? null
        : <bool>[for (final int i in order) totals![i]],
  );
}

/// [style] over [base]. Empty fields keep [base].
ReportFontSpec reportStyleFont(ReportTextStyle style, ReportFontSpec base) {
  final String family = (style.fontFamily ?? '').trim();
  final double? size = style.fontSize;
  return ReportFontSpec(
    family: family.isEmpty ? base.family : family,
    size: size != null && size > 0 ? size : base.size,
    bold: style.bold ?? base.bold,
    italic: style.italic ?? base.italic,
  );
}

/// Aggregated chart content ready to draw or export.
class ReportChartData {
  /// ReportChartData API.
  const ReportChartData({
    required this.type,
    required this.title,
    required this.categories,
    required this.series,
    required this.pointColors,
    required this.rtl,
    this.varyColors = false,
    this.showLegend = true,
    this.showValues = false,
    this.showGrid = true,
    this.showAxes = true,
    this.valueFormat,
    this.depth = 14,
    this.skew = 32,
    this.hole = 0.58,
    this.startAngle = -90,
    this.smooth = false,
    this.showMarkers,
    this.markerSize = 2.6,
    this.lineWidth = 1.6,
    this.axisMin,
    this.axisMax,
    this.axisMin2,
    this.axisMax2,
    this.target,
    this.showPercent = false,
    this.lastIsTotal = false,
    this.bands = 3,
    this.increase = const ReportColor(0xFF2E7D32),
    this.decrease = const ReportColor(0xFFC62828),
    this.total = const ReportColor(0xFF37474F),
    this.shapes,
    this.showLabels = true,
    this.low = const ReportColor(0xFFDEEBF7),
    this.high = const ReportColor(0xFF08306B),
    this.empty = const ReportColor(0xFFE4E4E4),
    this.regionColors,
    this.labelField,
    this.regionLabels,
    this.featureLabels,
    this.titleFont,
    this.titleInk,
    this.labelFont,
    this.legendFont,
    this.legendInk,
  });

  /// type API.
  final ReportChartType type;

  /// Evaluated title.
  final String title;

  /// Category labels in plot order.
  final List<String> categories;

  /// series API.
  final List<ReportChartSeriesData> series;

  /// Per-category colors (pie slices; bars when [varyColors]).
  final List<ReportColor> pointColors;

  /// Mirror the plot (first category on the right, value axis on the right).
  final bool rtl;

  /// Color single-series bars per category.
  final bool varyColors;

  /// showLegend API.
  final bool showLegend;

  /// showValues API.
  final bool showValues;

  /// showGrid API.
  final bool showGrid;

  /// showAxes API.
  final bool showAxes;

  /// Format spec for value labels.
  final String? valueFormat;

  /// Extrusion depth in points.
  final double depth;

  /// Oblique angle in degrees.
  final double skew;

  /// Hole as a fraction of the radius.
  final double hole;

  /// Pie and gauge start, in degrees.
  final double startAngle;

  /// Curve polylines.
  final bool smooth;

  /// Point markers. Null follows the chart type.
  final bool? showMarkers;

  /// Marker diameter in points.
  final double markerSize;

  /// Line stroke width in points.
  final double lineWidth;

  /// Forced primary minimum.
  final double? axisMin;

  /// Forced primary maximum.
  final double? axisMax;

  /// Forced secondary minimum.
  final double? axisMin2;

  /// Forced secondary maximum.
  final double? axisMax2;

  /// Gauge or bullet target.
  final double? target;

  /// Labels are percentages.
  final bool showPercent;

  /// Last waterfall category is an absolute total.
  final bool lastIsTotal;

  /// Qualitative bands behind a gauge or bullet.
  final int bands;

  /// Waterfall increase.
  final ReportColor increase;

  /// Waterfall decrease.
  final ReportColor decrease;

  /// Waterfall total.
  final ReportColor total;

  /// Regions of a shape map. Null draws nothing for that chart type.
  final ReportShapeLayer? shapes;

  /// Region names on areas wide enough to hold them.
  final bool showLabels;

  /// Smallest shape-map value.
  final ReportColor low;

  /// Largest shape-map value.
  final ReportColor high;

  /// Shape-map region with no value.
  final ReportColor empty;

  /// Per-category fill when the map has a region-color column.
  /// Null keeps the value gradient. A null entry is an unmatched region.
  final List<ReportColor?>? regionColors;

  /// Attribute drawn on each region. Empty uses [ReportShapeFeature.label].
  /// A `{{ }}` template is evaluated per row; the results are [regionLabels].
  final String? labelField;

  /// Formula caption for each category, aligned with [categories].
  /// Null when the label is a shape attribute or the feature name.
  final List<String>? regionLabels;

  /// Caption of each region by [ReportShapeFeature.key], for a calculated
  /// or stored column that is not an attribute of the shape file.
  final Map<String, String>? featureLabels;

  /// Map title font. Null uses the chart font, enlarged on charts that are
  /// not maps.
  final ReportFontSpec? titleFont;

  /// Map title color. Null uses the chart text color.
  final ReportColor? titleInk;

  /// Region-label font. Null uses the chart font.
  final ReportFontSpec? labelFont;

  /// Legend font. Null uses the chart font.
  final ReportFontSpec? legendFont;

  /// Legend color. Null uses the chart text color.
  final ReportColor? legendInk;

  /// Pie, donut, or an extruded form of either.
  bool get isRadial => type.isPie;

  /// Markers follow [showMarkers], or the chart type when it is null.
  bool get drawMarkers {
    if (showMarkers != null) {
      return showMarkers!;
    }
    return switch (type) {
      ReportChartType.line ||
      ReportChartType.scatter ||
      ReportChartType.bubble ||
      ReportChartType.radar ||
      ReportChartType.combo => true,
      _ => false,
    };
  }

  /// True when there is nothing to plot.
  bool get isEmpty => categories.isEmpty || series.isEmpty;

  /// Legend entries exist (radial categories or named / multiple series).
  bool get hasLegendEntries =>
      isRadial || series.length > 1 || series.first.name.isNotEmpty;

  /// Native DrawingML `c:chartSpace` part with literal data (Word, Excel).
  ///
  /// Gauge, bullet, funnel, waterfall, heatmap, and sparkline become the
  /// closest native chart. The vector renderer is the page they print.
  String toDrawingml() {
    final int slice = startAngle.round() % 360;
    final ChartDisplay display = ChartDisplay(
      showLegend: showLegend && !isEmpty && hasLegendEntries,
      showDataLabels: showValues,
      showAxes: showAxes,
      showGridlines: showGrid,
      showTitle: title.isNotEmpty,
      showPercent: showPercent,
      firstSliceAng: slice < 0 ? slice + 360 : slice,
      holeSize: (hole * 100).round().clamp(10, 90),
      rtl: rtl,
      view3d: type.isExtruded,
    );
    String label(int i) =>
        categories[i].trim().isEmpty ? '${i + 1}' : categories[i];
    final bool horizontal =
        type == ReportChartType.horizontalBar ||
        type == ReportChartType.bullet ||
        type == ReportChartType.funnel;
    if (isEmpty) {
      return DrawingmlCharts.multiSeries(
        title: title,
        series: const <ChartSeries>[],
        rtl: rtl,
        kind: ChartKind.bar,
        display: display,
      );
    }
    if (type == ReportChartType.gauge) {
      final double v = series.first.values.first;
      final double lo = axisMin ?? 0;
      final double hi = math.max(axisMax ?? lo + 1, math.max(v, target ?? v));
      final double span = math.max(hi - lo, 1e-6);
      final double filled = (v - lo).clamp(0, span).toDouble();
      return DrawingmlCharts.singleSeries(
        title: title,
        points: <ChartPoint>[
          ChartPoint(
            label: title.isEmpty ? 'Value' : title,
            value: filled,
            color: series.first.color.hex,
          ),
          ChartPoint(label: '', value: span - filled, color: 'E5E7EB'),
        ],
        rtl: rtl,
        kind: ChartKind.donut,
        titleColor: '404040',
        display: display..showLegend = false,
      );
    }
    if (type == ReportChartType.scatter || type == ReportChartType.bubble) {
      return DrawingmlCharts.xy(
        title: title,
        series: <ChartSeries>[
          for (final ReportChartSeriesData s in series)
            ChartSeries(
              name: s.name,
              color: s.color.hex,
              points: <ChartPoint>[
                for (int i = 0; i < s.values.length; i++)
                  ChartPoint(
                    label: i < categories.length ? label(i) : '${i + 1}',
                    value: s.values[i],
                    x: s.xs != null && i < s.xs!.length ? s.xs![i] : null,
                    size: s.sizes != null && i < s.sizes!.length
                        ? s.sizes![i]
                        : null,
                    color: s.color.hex,
                  ),
              ],
            ),
        ],
        rtl: rtl,
        bubble: type == ReportChartType.bubble,
        display: display,
      );
    }
    final ChartKind kind = switch (type) {
      ReportChartType.pie || ReportChartType.extrudedPie => ChartKind.pie,
      ReportChartType.donut || ReportChartType.extrudedDonut => ChartKind.donut,
      ReportChartType.line || ReportChartType.sparkline => ChartKind.line,
      ReportChartType.area => ChartKind.area,
      ReportChartType.stackedArea => ChartKind.stackedArea,
      ReportChartType.stackedBar => ChartKind.stackedBar,
      ReportChartType.percentStackedBar => ChartKind.percentStackedBar,
      ReportChartType.combo => ChartKind.combo,
      ReportChartType.radar => ChartKind.radar,
      ReportChartType.scatter => ChartKind.scatter,
      ReportChartType.bubble => ChartKind.bubble,
      ReportChartType.gauge => ChartKind.donut,
      _ => ChartKind.bar,
    };
    if (isRadial || (varyColors && series.length == 1 && !type.plotsPoints)) {
      final ReportChartSeriesData s = series.first;
      return DrawingmlCharts.singleSeries(
        title: title,
        points: <ChartPoint>[
          for (int i = 0; i < categories.length; i++)
            ChartPoint(
              label: label(i),
              value: s.values[i],
              color: pointColors[i % pointColors.length].hex,
            ),
        ],
        rtl: rtl,
        kind: kind,
        horizontal: horizontal,
        titleColor: '404040',
        display: display,
      );
    }
    return DrawingmlCharts.multiSeries(
      title: title,
      series: <ChartSeries>[
        for (final ReportChartSeriesData s in series)
          ChartSeries(
            name: s.name,
            color: s.color.hex,
            points: <ChartPoint>[
              for (int i = 0; i < categories.length; i++)
                ChartPoint(label: label(i), value: s.values[i]),
            ],
          ),
      ],
      rtl: rtl,
      kind: kind,
      horizontal: horizontal,
      markers: drawMarkers,
      lines: <bool>[
        for (final ReportChartSeriesData s in series)
          s.style == ReportSeriesStyle.line ||
              s.style == ReportSeriesStyle.area,
      ],
      secondary: <bool>[
        for (final ReportChartSeriesData s in series) s.secondary,
      ],
      titleColor: '404040',
      display: display,
    );
  }
}

/// Turns [ReportChartData] into page primitives inside a box.
class ReportChartRenderer {
  /// ReportChartRenderer API.
  ReportChartRenderer({required this.shaper, required this.formatter});

  /// shaper API.
  final ReportTextShaper shaper;

  /// Formats value labels and axis ticks (digits, separators).
  final ReportFormatter formatter;

  static String _featureLabel(ReportChartData d, ReportShapeFeature feature) {
    final Map<String, String>? labels = d.featureLabels;
    if (labels == null || labels.isEmpty) {
      return '';
    }
    final String? exact = labels[feature.key];
    if (exact != null) {
      return exact.trim();
    }
    final String lower = feature.key.toLowerCase();
    for (final MapEntry<String, String> e in labels.entries) {
      if (e.key.toLowerCase() == lower) {
        return e.value.trim();
      }
    }
    return '';
  }

  static const ReportColor _gridColor = ReportColor(0xFFE3E6EA);
  static const ReportColor _axisColor = ReportColor(0xFF9AA0A6);
  static const ReportColor _tickColor = ReportColor(0xFF6B7280);
  static const double _pad = 4;

  late List<ReportPrimitive> _out;
  late ReportFontSpec _font;
  late ReportColor _textColor;
  ReportColor? _labelColor;
  String? _elementId;
  ReportBandKind? _band;

  /// Primitives drawing [data] inside [box].
  List<ReportPrimitive> render(
    ReportChartData data,
    ReportRect box, {
    required ReportFontSpec font,
    required ReportColor textColor,
    ReportColor? labelColor,
    String? elementId,
    ReportBandKind? band,
  }) {
    _out = <ReportPrimitive>[];
    _font = font;
    _textColor = textColor;
    _labelColor = labelColor;
    _elementId = elementId;
    _band = band;
    var area = ReportRect(
      box.left + _pad,
      box.top + _pad,
      box.width - 2 * _pad,
      box.height - 2 * _pad,
    );
    if (area.width <= 4 || area.height <= 4) {
      return _out;
    }
    if (data.title.isNotEmpty) {
      final ReportFontSpec tf =
          data.titleFont ??
          (data.type.isShapeMap
              ? font
              : ReportFontSpec(
                  family: font.family,
                  size: font.size * 1.3,
                  bold: true,
                  italic: font.italic,
                ));
      final double h = shaper.lineHeight(tf);
      _label(
        data.title,
        tf,
        ReportRect(area.left, area.top, area.width, h),
        ReportTextAlign.center,
        data.titleInk ?? textColor,
      );
      area = ReportRect(
        area.left,
        area.top + h + 3,
        area.width,
        area.height - h - 3,
      );
    }
    final bool drawable = data.type.isShapeMap
        ? data.shapes != null && data.shapes!.features.isNotEmpty
        : !data.isEmpty;
    if (drawable && area.height > 8) {
      area = _legend(data, area);
      switch (data.type) {
        case ReportChartType.pie:
        case ReportChartType.donut:
        case ReportChartType.extrudedPie:
        case ReportChartType.extrudedDonut:
          _radial(data, area);
        case ReportChartType.gauge:
          _gauge(data, area);
        case ReportChartType.radar:
          _radar(data, area);
        case ReportChartType.scatter:
        case ReportChartType.bubble:
          _scatter(data, area);
        case ReportChartType.heatmap:
          _heatmap(data, area);
        case ReportChartType.sparkline:
          _spark(data, area);
        case ReportChartType.funnel:
          _funnel(data, area);
        case ReportChartType.bullet:
          _bullet(data, area);
        case ReportChartType.horizontalBar:
          _horizontal(data, area);
        case ReportChartType.shapeMap:
          _shapeMap(data, area);
        case ReportChartType.bar:
        case ReportChartType.stackedBar:
        case ReportChartType.percentStackedBar:
        case ReportChartType.line:
        case ReportChartType.area:
        case ReportChartType.stackedArea:
        case ReportChartType.combo:
        case ReportChartType.waterfall:
        case ReportChartType.extrudedBar:
          _vertical(data, area);
      }
    }
    if (!data.rtl || data.type.isShapeMap) {
      return _out;
    }
    final double axis = box.left + box.right;
    return <ReportPrimitive>[
      for (final ReportPrimitive p in _out) _mirror(p, axis),
    ];
  }

  // ------------------------------------------------------------ legend

  ReportRect _legend(ReportChartData d, ReportRect area) {
    if (d.type.isShapeMap) {
      return area;
    }
    final List<(String, ReportColor)> entries = <(String, ReportColor)>[
      if (d.isRadial || d.type == ReportChartType.funnel)
        for (int i = 0; i < d.categories.length; i++)
          (
            d.categories[i],
            d.pointColors.isEmpty
                ? d.series.first.color
                : d.pointColors[i % d.pointColors.length],
          )
      else if (d.type != ReportChartType.waterfall &&
          (d.series.length > 1 || d.series.first.name.isNotEmpty))
        for (final ReportChartSeriesData s in d.series) (s.name, s.color),
    ];
    if (!d.showLegend || entries.isEmpty) {
      return area;
    }
    final double lh = shaper.lineHeight(_font);
    final double sw = _font.size * 0.8;
    final List<double> widths = <double>[
      for (final (String, ReportColor) e in entries)
        sw + 3 + _width(e.$1, _font),
    ];
    if (d.isRadial) {
      var maxW = 0.0;
      for (final double w in widths) {
        maxW = math.max(maxW, w);
      }
      final double legendW = math.min(maxW, area.width * 0.42);
      final int fit = math.max(1, (area.height / (lh + 1)).floor());
      final int count = math.min(fit, entries.length);
      final double total = count * (lh + 1);
      var y = area.top + (area.height - total) / 2;
      final double x = area.right - legendW;
      for (int i = 0; i < count; i++) {
        _swatch(x, y + (lh - sw) / 2, sw, entries[i].$2);
        _label(
          entries[i].$1,
          _font,
          ReportRect(x + sw + 3, y, legendW - sw - 3, lh),
          ReportTextAlign.left,
          _textColor,
        );
        y += lh + 1;
      }
      return ReportRect(
        area.left,
        area.top,
        area.width - legendW - 6,
        area.height,
      );
    }
    final List<List<int>> rows = <List<int>>[<int>[]];
    var rowW = 0.0;
    for (int i = 0; i < entries.length; i++) {
      final double w = math.min(widths[i], area.width);
      if (rows.last.isNotEmpty && rowW + 10 + w > area.width) {
        rows.add(<int>[]);
        rowW = 0;
      }
      rowW += (rows.last.isEmpty ? 0 : 10) + w;
      rows.last.add(i);
    }
    final double legendH = rows.length * lh;
    if (legendH > area.height * 0.4) {
      return area;
    }
    var y = area.bottom - legendH;
    for (final List<int> row in rows) {
      var total = 0.0;
      for (final int i in row) {
        total += math.min(widths[i], area.width);
      }
      total += (row.length - 1) * 10;
      var x = area.left + (area.width - total) / 2;
      for (final int i in row) {
        final double w = math.min(widths[i], area.width);
        _swatch(x, y + (lh - sw) / 2, sw, entries[i].$2);
        _label(
          entries[i].$1,
          _font,
          ReportRect(x + sw + 3, y, w - sw - 3, lh),
          ReportTextAlign.left,
          _textColor,
        );
        x += w + 10;
      }
      y += lh;
    }
    return ReportRect(
      area.left,
      area.top,
      area.width,
      area.height - legendH - 3,
    );
  }

  void _swatch(double x, double y, double size, ReportColor color) {
    _out.add(
      ReportRectPrimitive(
        bounds: ReportRect(x, y, size, size),
        elementId: _elementId,
        band: _band,
        fill: color,
        radius: size * 0.2,
      ),
    );
  }

  // ------------------------------------------------------------ cartesian

  ({double lo, double hi}) _range(ReportChartData d) {
    var lo = 0.0;
    var hi = 0.0;
    if (d.type == ReportChartType.percentStackedBar) {
      return (lo: 0, hi: 100);
    }
    if (d.type == ReportChartType.stackedBar ||
        d.type == ReportChartType.stackedArea) {
      for (int i = 0; i < d.categories.length; i++) {
        var pos = 0.0;
        var neg = 0.0;
        for (final ReportChartSeriesData s in d.series) {
          if (s.secondary) {
            continue;
          }
          final double v = s.values[i];
          if (v >= 0) {
            pos += v;
          } else {
            neg += v;
          }
        }
        hi = math.max(hi, pos);
        lo = math.min(lo, neg);
      }
    } else if (d.type == ReportChartType.waterfall) {
      final ({double lo, double hi}) w = _waterfallExtent(d);
      lo = w.lo;
      hi = w.hi;
    } else {
      for (final ReportChartSeriesData s in d.series) {
        if (s.secondary && d.type == ReportChartType.combo) {
          continue;
        }
        final List<double> xs = s.xs ?? const <double>[];
        if (d.type.plotsPoints && xs.isNotEmpty) {
          continue;
        }
        for (final double v in s.values) {
          hi = math.max(hi, v);
          lo = math.min(lo, v);
        }
      }
    }
    if (hi - lo < 1e-9) {
      hi = lo + 1;
    }
    return (lo: lo, hi: hi);
  }

  /// Rounded axis bounds and tick step for about [ticks] intervals.
  static ({double lo, double hi, double step}) niceScale(
    double min,
    double max,
    int ticks,
  ) {
    final double rough = (max - min) / ticks;
    final double mag = math
        .pow(10, (math.log(rough) / math.ln10).floor())
        .toDouble();
    final double norm = rough / mag;
    final double unit = norm <= 1
        ? 1
        : norm <= 2
        ? 2
        : norm <= 2.5
        ? 2.5
        : norm <= 5
        ? 5
        : 10;
    final double step = unit * mag;
    final double lo = (min / step).floor() * step;
    final double hi = (max / step).ceil() * step;
    return (lo: lo, hi: hi <= lo ? lo + step : hi, step: step);
  }

  String _tick(double v, double step) {
    final double a = step.abs();
    if (a >= 1e6) {
      return '${_number(v / 1e6, _decimals(step / 1e6))}M';
    }
    if (a >= 1e3) {
      return '${_number(v / 1e3, _decimals(step / 1e3))}K';
    }
    return _number(v, _decimals(step));
  }

  static int _decimals(double step) {
    for (int d = 0; d < 4; d++) {
      final double scaled = step * math.pow(10, d);
      if ((scaled - scaled.roundToDouble()).abs() < 1e-6) {
        return d;
      }
    }
    return 4;
  }

  String _number(double v, int decimals) =>
      formatter.format(ReportNumber(v), 'n$decimals');

  /// Value label text.
  String formatValue(double v, String? spec) {
    if (spec != null && spec.trim().isNotEmpty) {
      return formatter.format(ReportNumber(v), spec);
    }
    return _number(v, v == v.roundToDouble() ? 0 : 2);
  }

  void _vertical(ReportChartData d, ReportRect area) {
    final ({double lo, double hi}) r = _range(d);
    final ({double lo, double hi, double step}) s = _fit(
      r.lo,
      r.hi,
      min: d.axisMin,
      max: d.axisMax,
      ticks: 5,
    );
    final double lh = shaper.lineHeight(_font);
    final ReportFontSpec small = _smaller(_font);
    final double slh = shaper.lineHeight(small);
    final List<double> ticks = <double>[
      for (double v = s.lo; v <= s.hi + s.step * 1e-6; v += s.step) v,
    ];
    var axisW = 0.0;
    if (d.showAxes) {
      for (final double v in ticks) {
        axisW = math.max(axisW, _width(_tick(v, s.step), small));
      }
      axisW += 4;
    }
    final double top = area.top + (d.showValues ? slh : slh / 2);
    final double bottom = area.bottom - (d.showAxes ? lh + 2 : 0);
    final ReportRect plot = ReportRect(
      area.left + axisW,
      top,
      area.width - axisW,
      bottom - top,
    );
    if (plot.width <= 4 || plot.height <= 4) {
      return;
    }
    double y(double v) =>
        plot.bottom - (v - s.lo) / (s.hi - s.lo) * plot.height;
    for (final double v in ticks) {
      final double ty = y(v);
      if (d.showGrid) {
        _line(plot.left, ty, plot.right, ty, _gridColor, 0.4);
      }
      if (d.showAxes) {
        _label(
          _tick(v, s.step),
          small,
          ReportRect(area.left, ty - slh / 2, axisW - 3, slh),
          ReportTextAlign.right,
          _tickColor,
        );
      }
    }
    final int n = d.categories.length;
    final double slot = plot.width / n;
    final double zero = y(s.lo > 0 ? s.lo : (s.hi < 0 ? s.hi : 0));
    switch (d.type) {
      case ReportChartType.line:
      case ReportChartType.area:
      case ReportChartType.sparkline:
        _lines(d, plot, slot, y, zero, small, slh);
      case ReportChartType.stackedArea:
        _stackedArea(d, plot, slot, y, small, slh);
      case ReportChartType.stackedBar:
      case ReportChartType.percentStackedBar:
        _stacked(
          d,
          plot,
          slot,
          y,
          small,
          slh,
          percent: d.type == ReportChartType.percentStackedBar,
        );
      case ReportChartType.combo:
        _combo(d, plot, slot, y, small, slh);
      case ReportChartType.waterfall:
        _waterfall(d, plot, slot, y, small, slh);
      case ReportChartType.extrudedBar:
        _bars(d, plot, slot, y, zero, small, slh, extruded: true);
      case ReportChartType.bar:
      case ReportChartType.horizontalBar:
      case ReportChartType.pie:
      case ReportChartType.donut:
      case ReportChartType.extrudedPie:
      case ReportChartType.extrudedDonut:
      case ReportChartType.gauge:
      case ReportChartType.bullet:
      case ReportChartType.funnel:
      case ReportChartType.scatter:
      case ReportChartType.bubble:
      case ReportChartType.radar:
      case ReportChartType.heatmap:
      case ReportChartType.shapeMap:
        _bars(d, plot, slot, y, zero, small, slh);
    }
    if (d.showAxes) {
      _line(plot.left, plot.top, plot.left, plot.bottom, _axisColor, 0.6);
      _line(plot.left, zero, plot.right, zero, _axisColor, 0.6);
      var widest = 0.0;
      for (final String c in d.categories) {
        widest = math.max(widest, _width(c, _font));
      }
      final int every = math.max(1, (widest / (slot * 0.95)).ceil());
      for (int i = 0; i < n; i += every) {
        _label(
          d.categories[i],
          _font,
          ReportRect(
            plot.left + i * slot - (every - 1) * slot / 2,
            plot.bottom + 2,
            slot * every,
            lh,
          ),
          ReportTextAlign.center,
          _textColor,
        );
      }
    }
  }

  void _bars(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(double) y,
    double zero,
    ReportFontSpec small,
    double slh, {
    bool extruded = false,
  }) {
    final int m = d.series.length;
    final double group = slot * (m == 1 ? 0.6 : 0.78);
    final double bw = group / m;
    for (int si = 0; si < m; si++) {
      final ReportChartSeriesData s = d.series[si];
      for (int i = 0; i < d.categories.length; i++) {
        final double v = s.values[i];
        final double x = plot.left + i * slot + (slot - group) / 2 + si * bw;
        final double vy = y(v);
        final double top = math.min(vy, zero);
        final double h = (vy - zero).abs();
        final ReportColor color = d.varyColors && m == 1
            ? d.pointColors[i % d.pointColors.length]
            : s.color;
        if (h > 0.01) {
          final ReportRect bar = ReportRect(x + bw * 0.06, top, bw * 0.88, h);
          if (extruded) {
            _extrude(bar, color, d);
          } else {
            _out.add(
              ReportRectPrimitive(
                bounds: bar,
                elementId: _elementId,
                band: _band,
                fill: color,
              ),
            );
          }
        }
        if (d.showValues) {
          final double lw = m == 1 ? slot : bw * 1.8;
          _label(
            formatValue(v, d.valueFormat),
            small,
            ReportRect(x + bw / 2 - lw / 2, v >= 0 ? vy - slh : vy, lw, slh),
            ReportTextAlign.center,
            _textColor,
          );
        }
      }
    }
  }

  void _stacked(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(double) y,
    ReportFontSpec small,
    double slh, {
    bool percent = false,
  }) {
    final double bw = slot * 0.6;
    for (int i = 0; i < d.categories.length; i++) {
      final double x = plot.left + i * slot + (slot - bw) / 2;
      var pos = 0.0;
      var neg = 0.0;
      var posSum = 0.0;
      var negSum = 0.0;
      if (percent) {
        for (final ReportChartSeriesData s in d.series) {
          final double v = s.values[i];
          if (v >= 0) {
            posSum += v;
          } else {
            negSum += v;
          }
        }
      }
      for (final ReportChartSeriesData s in d.series) {
        final double raw = s.values[i];
        final double v = !percent
            ? raw
            : raw >= 0
            ? (posSum == 0 ? 0 : raw / posSum * 100)
            : (negSum == 0 ? 0 : raw / negSum * 100);
        final double from = v >= 0 ? pos : neg;
        final double to = from + v;
        if (v >= 0) {
          pos = to;
        } else {
          neg = to;
        }
        final double y1 = y(from);
        final double y2 = y(to);
        final double top = math.min(y1, y2);
        final double h = (y1 - y2).abs();
        if (h <= 0.01) {
          continue;
        }
        _out.add(
          ReportRectPrimitive(
            bounds: ReportRect(x, top, bw, h),
            elementId: _elementId,
            band: _band,
            fill: s.color,
            stroke: ReportColor.white,
            strokeWidth: 0.4,
          ),
        );
        if (d.showValues && h >= slh) {
          _label(
            percent && (d.showPercent || d.valueFormat == null)
                ? '${formatValue(v, d.showPercent ? d.valueFormat : null)}%'
                : formatValue(raw, d.valueFormat),
            small,
            ReportRect(x, top + (h - slh) / 2, bw, slh),
            ReportTextAlign.center,
            _contrast(s.color),
          );
        }
      }
    }
  }

  void _lines(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(double) y,
    double zero,
    ReportFontSpec small,
    double slh,
  ) {
    final int n = d.categories.length;
    final bool area = d.type == ReportChartType.area;
    for (final ReportChartSeriesData s in d.series) {
      final Float64List line = Float64List(n * 2);
      for (int i = 0; i < n; i++) {
        line[i * 2] = plot.left + (i + 0.5) * slot;
        line[i * 2 + 1] = y(s.values[i]);
      }
      final Float64List stroke = d.smooth && n > 2 ? _curve(line) : line;
      if (area && n > 1) {
        final Float64List poly = Float64List(stroke.length + 4)
          ..setRange(0, stroke.length, stroke);
        poly[stroke.length] = stroke[stroke.length - 2];
        poly[stroke.length + 1] = zero;
        poly[stroke.length + 2] = stroke[0];
        poly[stroke.length + 3] = zero;
        _out.add(
          ReportPathPrimitive.through(
            poly,
            elementId: _elementId,
            band: _band,
            closed: true,
            fill: _tint(s.color, 0.55),
          ),
        );
      }
      if (n > 1) {
        _out.add(
          ReportPathPrimitive.through(
            stroke,
            elementId: _elementId,
            band: _band,
            stroke: s.color,
            strokeWidth: d.lineWidth,
          ),
        );
      }
      if (d.showMarkers ?? (d.drawMarkers || (area && n == 1))) {
        final double r = math.min(d.markerSize, slot / 4);
        for (int i = 0; i < n; i++) {
          _out.add(
            ReportRectPrimitive(
              bounds: ReportRect(
                line[i * 2] - r,
                line[i * 2 + 1] - r,
                r * 2,
                r * 2,
              ),
              elementId: _elementId,
              band: _band,
              fill: s.color,
              stroke: ReportColor.white,
              strokeWidth: 0.6,
              ellipse: true,
            ),
          );
        }
      }
      if (d.showValues) {
        for (int i = 0; i < n; i++) {
          _label(
            formatValue(s.values[i], d.valueFormat),
            small,
            ReportRect(
              line[i * 2] - slot / 2,
              line[i * 2 + 1] - slh - 2,
              slot,
              slh,
            ),
            ReportTextAlign.center,
            _textColor,
          );
        }
      }
    }
  }

  void _horizontal(ReportChartData d, ReportRect area) {
    final ({double lo, double hi}) r = _range(d);
    final ({double lo, double hi, double step}) s = niceScale(r.lo, r.hi, 4);
    final double lh = shaper.lineHeight(_font);
    final ReportFontSpec small = _smaller(_font);
    final double slh = shaper.lineHeight(small);
    var catW = 0.0;
    if (d.showAxes) {
      for (final String c in d.categories) {
        catW = math.max(catW, _width(c, _font));
      }
      catW = math.min(catW + 4, area.width * 0.35);
    }
    var valueW = 0.0;
    if (d.showValues) {
      for (final ReportChartSeriesData sd in d.series) {
        for (final double v in sd.values) {
          valueW = math.max(
            valueW,
            _width(formatValue(v, d.valueFormat), small),
          );
        }
      }
      valueW += 3;
    }
    final double bottom = area.bottom - (d.showAxes ? slh + 2 : 0);
    final ReportRect plot = ReportRect(
      area.left + catW,
      area.top + 2,
      area.width - catW - valueW - 4,
      bottom - area.top - 2,
    );
    if (plot.width <= 4 || plot.height <= 4) {
      return;
    }
    double x(double v) => plot.left + (v - s.lo) / (s.hi - s.lo) * plot.width;
    for (double v = s.lo; v <= s.hi + s.step * 1e-6; v += s.step) {
      final double tx = x(v);
      if (d.showGrid) {
        _line(tx, plot.top, tx, plot.bottom, _gridColor, 0.4);
      }
      if (d.showAxes) {
        final double tw = plot.width / 4;
        _label(
          _tick(v, s.step),
          small,
          ReportRect(tx - tw / 2, plot.bottom + 2, tw, slh),
          ReportTextAlign.center,
          _tickColor,
        );
      }
    }
    final int n = d.categories.length;
    final int m = d.series.length;
    final double slot = plot.height / n;
    final double group = slot * (m == 1 ? 0.62 : 0.8);
    final double bh = group / m;
    final double zero = x(s.lo > 0 ? s.lo : (s.hi < 0 ? s.hi : 0));
    for (int i = 0; i < n; i++) {
      final double rowTop = plot.top + i * slot;
      if (d.showAxes) {
        _label(
          d.categories[i],
          _font,
          ReportRect(area.left, rowTop + (slot - lh) / 2, catW - 4, lh),
          ReportTextAlign.right,
          _textColor,
        );
      }
      for (int si = 0; si < m; si++) {
        final double v = d.series[si].values[i];
        final double vx = x(v);
        final double top = rowTop + (slot - group) / 2 + si * bh;
        final ReportColor color = d.varyColors && m == 1
            ? d.pointColors[i % d.pointColors.length]
            : d.series[si].color;
        final double left = math.min(vx, zero);
        final double w = (vx - zero).abs();
        if (w > 0.01) {
          _out.add(
            ReportRectPrimitive(
              bounds: ReportRect(left, top + bh * 0.06, w, bh * 0.88),
              elementId: _elementId,
              band: _band,
              fill: color,
            ),
          );
        }
        if (d.showValues) {
          _label(
            formatValue(v, d.valueFormat),
            small,
            ReportRect(
              v >= 0 ? vx + 2 : vx - valueW - 2,
              top + (bh - slh) / 2,
              valueW,
              slh,
            ),
            v >= 0 ? ReportTextAlign.left : ReportTextAlign.right,
            _textColor,
          );
        }
      }
    }
    if (d.showAxes) {
      _line(zero, plot.top, zero, plot.bottom, _axisColor, 0.6);
      _line(plot.left, plot.bottom, plot.right, plot.bottom, _axisColor, 0.6);
    }
  }

  // ------------------------------------------------------------ radial

  void _radial(ReportChartData d, ReportRect area) {
    final List<double> values = d.series.first.values;
    var total = 0.0;
    for (final double v in values) {
      if (v > 0) {
        total += v;
      }
    }
    final double radius = math.min(area.width, area.height) / 2 - 1;
    if (total <= 0 || radius <= 4) {
      return;
    }
    final double cx = area.left + area.width / 2;
    final double cy = area.top + area.height / 2;
    final bool donut =
        d.type == ReportChartType.donut ||
        d.type == ReportChartType.extrudedDonut;
    final bool extruded = d.type.isExtruded;
    final double inner = donut ? radius * d.hole.clamp(0.05, 0.9) : 0;
    final double drop = extruded ? math.min(d.depth, radius * 0.45) : 0;
    final ReportFontSpec bold = ReportFontSpec(
      family: _font.family,
      size: _font.size,
      bold: true,
    );
    final double lh = shaper.lineHeight(bold);
    var start = d.startAngle * math.pi / 180;
    final int positive = values.where((double v) => v > 0).length;
    for (int i = 0; i < values.length; i++) {
      final double v = values[i];
      if (v <= 0) {
        continue;
      }
      final double sweep = v / total * 2 * math.pi;
      final ReportColor color = d.pointColors[i % d.pointColors.length];
      if (extruded && drop > 0.4) {
        _out.add(
          ReportPathPrimitive.through(
            wedge(cx, cy + drop, radius, inner, start, sweep),
            elementId: _elementId,
            band: _band,
            closed: true,
            fill: _shade(color, 0.42),
          ),
        );
      }
      _out.add(
        ReportPathPrimitive.through(
          wedge(cx, cy, radius, inner, start, sweep),
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: color,
          stroke: positive > 1 ? ReportColor.white : null,
          strokeWidth: positive > 1 ? 0.8 : 0,
        ),
      );
      if (d.showValues && sweep >= 0.32) {
        final double mid = start + sweep / 2;
        final double lr = donut ? (radius + inner) / 2 : radius * 0.64;
        final double lx = cx + math.cos(mid) * lr;
        final double ly = cy + math.sin(mid) * lr;
        final String text = d.valueFormat == null
            ? formatter.format(ReportNumber(v / total), 'percent')
            : formatValue(v, d.valueFormat);
        final double w = radius * 0.9;
        _label(
          text,
          bold,
          ReportRect(lx - w / 2, ly - lh / 2, w, lh),
          ReportTextAlign.center,
          _contrast(color),
        );
      }
      start += sweep;
    }
    if (donut) {
      final ReportFontSpec big = ReportFontSpec(
        family: _font.family,
        size: _font.size * 1.35,
        bold: true,
      );
      final String text = formatValue(total, d.valueFormat);
      if (_width(text, big) < inner * 1.7) {
        final double h = shaper.lineHeight(big);
        _label(
          text,
          big,
          ReportRect(cx - inner, cy - h / 2, inner * 2, h),
          ReportTextAlign.center,
          _textColor,
        );
      }
    }
  }

  void _extrude(ReportRect bar, ReportColor color, ReportChartData d) {
    final (double dx, double dy) = _depthVector(d);
    final double x = bar.left;
    final double y = bar.top;
    final double w = bar.width;
    final double h = bar.height;
    _poly(<double>[
      x + w,
      y,
      x + w + dx,
      y + dy,
      x + w + dx,
      y + h + dy,
      x + w,
      y + h,
    ], fill: _shade(color, 0.32));
    _poly(<double>[
      x,
      y,
      x + w,
      y,
      x + w + dx,
      y + dy,
      x + dx,
      y + dy,
    ], fill: _tint(color, 0.35));
    _out.add(
      ReportRectPrimitive(
        bounds: bar,
        elementId: _elementId,
        band: _band,
        fill: color,
      ),
    );
  }

  (double, double) _depthVector(ReportChartData d) {
    final double rad = d.skew.clamp(8, 80) * math.pi / 180;
    final double depth = math.max(0, d.depth);
    return (depth * math.cos(rad), -depth * math.sin(rad));
  }

  void _combo(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(double) y,
    ReportFontSpec small,
    double slh,
  ) {
    final ReportChartData columns = _seriesWhere(
      d,
      (ReportChartSeriesData s) => s.style == ReportSeriesStyle.column,
    );
    if (columns.series.isNotEmpty) {
      _bars(columns, plot, slot, y, y(0), small, slh);
    }
    final List<ReportChartSeriesData> lines = <ReportChartSeriesData>[
      for (final ReportChartSeriesData s in d.series)
        if (s.style != ReportSeriesStyle.column) s,
    ];
    if (lines.isEmpty) {
      return;
    }
    final bool secondary = lines.any((ReportChartSeriesData s) => s.secondary);
    var lo = 0.0;
    var hi = 0.0;
    for (final ReportChartSeriesData s in lines) {
      for (final double v in s.values) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    final ({double lo, double hi, double step}) scale = secondary
        ? _fit(lo, hi, min: d.axisMin2, max: d.axisMax2)
        : _fit(lo, hi, min: d.axisMin, max: d.axisMax);
    double yOf(ReportChartSeriesData s, double v) {
      if (!s.secondary) {
        return y(v);
      }
      return plot.bottom - (v - scale.lo) / (scale.hi - scale.lo) * plot.height;
    }

    if (secondary && d.showAxes) {
      final ReportFontSpec tick = _smaller(_font);
      final double th = shaper.lineHeight(tick);
      for (
        double v = scale.lo;
        v <= scale.hi + scale.step * 1e-6;
        v += scale.step
      ) {
        final double ty =
            plot.bottom - (v - scale.lo) / (scale.hi - scale.lo) * plot.height;
        _label(
          _tick(v, scale.step),
          tick,
          ReportRect(plot.right + 2, ty - th / 2, 36, th),
          ReportTextAlign.left,
          _tickColor,
        );
      }
      _line(plot.right, plot.top, plot.right, plot.bottom, _axisColor, 0.6);
    }
    final ReportChartData lined = _seriesWhere(
      d,
      (ReportChartSeriesData s) => s.style != ReportSeriesStyle.column,
    );
    _linesMapped(lined, plot, slot, yOf, y(0), small, slh);
  }

  ReportChartData _seriesWhere(
    ReportChartData d,
    bool Function(ReportChartSeriesData) test,
  ) => ReportChartData(
    type: d.type,
    title: d.title,
    categories: d.categories,
    series: <ReportChartSeriesData>[
      for (final ReportChartSeriesData s in d.series)
        if (test(s)) s,
    ],
    pointColors: d.pointColors,
    rtl: d.rtl,
    varyColors: d.varyColors,
    showLegend: d.showLegend,
    showValues: d.showValues,
    showGrid: d.showGrid,
    showAxes: d.showAxes,
    valueFormat: d.valueFormat,
    depth: d.depth,
    skew: d.skew,
    hole: d.hole,
    startAngle: d.startAngle,
    smooth: d.smooth,
    showMarkers: d.showMarkers,
    markerSize: d.markerSize,
    lineWidth: d.lineWidth,
    showPercent: d.showPercent,
  );

  void _linesMapped(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(ReportChartSeriesData, double) yOf,
    double zero,
    ReportFontSpec small,
    double slh,
  ) {
    final int n = d.categories.length;
    for (final ReportChartSeriesData s in d.series) {
      final Float64List line = Float64List(n * 2);
      for (int i = 0; i < n; i++) {
        line[i * 2] = plot.left + (i + 0.5) * slot;
        line[i * 2 + 1] = yOf(s, s.values[i]);
      }
      final bool area = s.style == ReportSeriesStyle.area;
      final Float64List stroke = d.smooth && n > 2 ? _curve(line) : line;
      if (area && n > 1) {
        final Float64List poly = Float64List(stroke.length + 4)
          ..setRange(0, stroke.length, stroke);
        poly[stroke.length] = stroke[stroke.length - 2];
        poly[stroke.length + 1] = zero;
        poly[stroke.length + 2] = stroke[0];
        poly[stroke.length + 3] = zero;
        _out.add(
          ReportPathPrimitive.through(
            poly,
            elementId: _elementId,
            band: _band,
            closed: true,
            fill: _tint(s.color, 0.55),
          ),
        );
      }
      if (n > 1) {
        _out.add(
          ReportPathPrimitive.through(
            stroke,
            elementId: _elementId,
            band: _band,
            stroke: s.color,
            strokeWidth: d.lineWidth,
          ),
        );
      }
      if (d.drawMarkers) {
        _dots(line, s.color, math.min(d.markerSize, slot / 4));
      }
    }
  }

  void _stackedArea(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(double) y,
    ReportFontSpec small,
    double slh,
  ) {
    final int n = d.categories.length;
    final List<double> floor = List<double>.filled(n, 0);
    for (final ReportChartSeriesData s in d.series) {
      final Float64List top = Float64List(n * 2);
      final Float64List edge = Float64List(n * 2);
      for (int i = 0; i < n; i++) {
        final double v = floor[i] + s.values[i];
        top[i * 2] = plot.left + (i + 0.5) * slot;
        top[i * 2 + 1] = y(v);
        edge[i * 2] = top[i * 2];
        edge[i * 2 + 1] = y(floor[i]);
        floor[i] = v;
      }
      final Float64List poly = Float64List(n * 4);
      poly.setRange(0, n * 2, top);
      for (int i = 0; i < n; i++) {
        poly[(n + i) * 2] = edge[(n - 1 - i) * 2];
        poly[(n + i) * 2 + 1] = edge[(n - 1 - i) * 2 + 1];
      }
      _out.add(
        ReportPathPrimitive.through(
          poly,
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: _tint(s.color, 0.35),
          stroke: s.color,
          strokeWidth: d.lineWidth,
        ),
      );
      if (d.showValues) {
        for (int i = 0; i < n; i++) {
          _label(
            formatValue(s.values[i], d.valueFormat),
            small,
            ReportRect(top[i * 2] - slot / 2, top[i * 2 + 1] - slh, slot, slh),
            ReportTextAlign.center,
            _textColor,
          );
        }
      }
    }
  }

  void _waterfall(
    ReportChartData d,
    ReportRect plot,
    double slot,
    double Function(double) y,
    ReportFontSpec small,
    double slh,
  ) {
    final List<({double from, double to, bool total})> steps = _steps(d);
    final double bw = slot * 0.62;
    double? link;
    for (int i = 0; i < steps.length; i++) {
      final ({double from, double to, bool total}) step = steps[i];
      final double x = plot.left + i * slot + (slot - bw) / 2;
      final double y1 = y(step.from);
      final double y2 = y(step.to);
      final ReportColor color = step.total
          ? d.total
          : (step.to >= step.from ? d.increase : d.decrease);
      final double top = math.min(y1, y2);
      final double h = math.max((y1 - y2).abs(), 0.8);
      _out.add(
        ReportRectPrimitive(
          bounds: ReportRect(x, top, bw, h),
          elementId: _elementId,
          band: _band,
          fill: color,
        ),
      );
      final double end = step.to >= step.from ? top : top + h;
      if (link != null) {
        _line(x - (slot - bw) / 2, link, x, link, _axisColor, 0.5);
      }
      link = end;
      if (d.showValues) {
        _label(
          formatValue(d.series.first.values[i], d.valueFormat),
          small,
          ReportRect(x - 4, math.min(y1, y2) - slh, bw + 8, slh),
          ReportTextAlign.center,
          _textColor,
        );
      }
    }
  }

  List<({double from, double to, bool total})> _steps(ReportChartData d) {
    final ReportChartSeriesData s = d.series.first;
    final List<({double from, double to, bool total})> out =
        <({double from, double to, bool total})>[];
    var run = 0.0;
    for (int i = 0; i < s.values.length; i++) {
      final bool total =
          (s.totals != null && i < s.totals!.length && s.totals![i]) ||
          (d.lastIsTotal && i == s.values.length - 1);
      if (total) {
        out.add((from: 0, to: s.values[i], total: true));
        run = s.values[i];
      } else {
        final double to = run + s.values[i];
        out.add((from: run, to: to, total: false));
        run = to;
      }
    }
    return out;
  }

  ({double lo, double hi}) _waterfallExtent(ReportChartData d) {
    if (d.series.isEmpty || d.series.first.values.isEmpty) {
      return (lo: 0, hi: 1);
    }
    var lo = 0.0;
    var hi = 0.0;
    for (final ({double from, double to, bool total}) step in _steps(d)) {
      lo = math.min(lo, math.min(step.from, step.to));
      hi = math.max(hi, math.max(step.from, step.to));
    }
    if (hi - lo < 1e-9) {
      hi = lo + 1;
    }
    return (lo: lo, hi: hi);
  }

  void _gauge(ReportChartData d, ReportRect area) {
    final double v = d.series.first.values.first;
    final double lo = d.axisMin ?? 0;
    var hi = d.axisMax ?? math.max(v, d.target ?? v);
    if (hi <= lo) {
      hi = lo + 1;
    }
    final double radius = math.min(area.width, area.height * 1.15) / 2 - 2;
    if (radius <= 6) {
      return;
    }
    final double cx = area.left + area.width / 2;
    final double cy = area.top + area.height * 0.58;
    const double start = math.pi * 0.75;
    const double full = math.pi * 1.5;
    final double inner = radius * d.hole.clamp(0.45, 0.9);
    final int bands = d.bands.clamp(0, 8);
    if (bands > 0) {
      for (int i = 0; i < bands; i++) {
        _out.add(
          ReportPathPrimitive.through(
            wedge(
              cx,
              cy,
              radius,
              inner,
              start + full * i / bands,
              full / bands,
            ),
            elementId: _elementId,
            band: _band,
            closed: true,
            fill: _tint(d.pointColors[i % d.pointColors.length], 0.45),
          ),
        );
      }
    } else {
      _out.add(
        ReportPathPrimitive.through(
          wedge(cx, cy, radius, inner, start, full),
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: _gridColor,
        ),
      );
    }
    final double t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    if (t > 0) {
      _out.add(
        ReportPathPrimitive.through(
          wedge(cx, cy, radius, inner, start, full * t),
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: d.series.first.color,
        ),
      );
    }
    final double ang = start + full * t;
    final double nx = cx + math.cos(ang) * (radius * 0.92);
    final double ny = cy + math.sin(ang) * (radius * 0.92);
    _line(cx, cy, nx, ny, const ReportColor(0xFF202124), 1.4);
    _dot(cx, cy, 3.2, const ReportColor(0xFF202124));
    if (d.target != null) {
      final double ta =
          start + full * ((d.target! - lo) / (hi - lo)).clamp(0.0, 1.0);
      _line(
        cx + math.cos(ta) * inner,
        cy + math.sin(ta) * inner,
        cx + math.cos(ta) * radius,
        cy + math.sin(ta) * radius,
        const ReportColor(0xFF111827),
        1.6,
      );
    }
    final String text = formatValue(v, d.valueFormat);
    final ReportFontSpec big = ReportFontSpec(
      family: _font.family,
      size: _font.size * 1.4,
      bold: true,
    );
    final double lh = shaper.lineHeight(big);
    _label(
      text,
      big,
      ReportRect(cx - radius, cy + inner * 0.15, radius * 2, lh),
      ReportTextAlign.center,
      _textColor,
    );
  }

  void _bullet(ReportChartData d, ReportRect area) {
    final double v = d.series.first.values.first;
    final double lo = d.axisMin ?? 0;
    var hi = d.axisMax ?? math.max(v, d.target ?? v);
    if (hi <= lo) {
      hi = lo + 1;
    }
    final double labelW = d.showAxes
        ? math.min(_width(d.categories.first, _font) + 6, area.width * 0.34)
        : 0;
    final ReportRect plot = ReportRect(
      area.left + labelW,
      area.top + area.height * 0.28,
      area.width - labelW - 4,
      area.height * 0.44,
    );
    if (plot.width <= 4 || plot.height <= 4) {
      return;
    }
    if (d.showAxes) {
      _label(
        d.categories.first,
        _font,
        ReportRect(area.left, plot.top, labelW - 4, plot.height),
        ReportTextAlign.right,
        _textColor,
      );
    }
    final int bands = d.bands.clamp(0, 8);
    if (bands == 0) {
      _out.add(
        ReportRectPrimitive(
          bounds: plot,
          elementId: _elementId,
          band: _band,
          fill: _gridColor,
        ),
      );
    } else {
      final double bw = plot.width / bands;
      for (int i = 0; i < bands; i++) {
        _out.add(
          ReportRectPrimitive(
            bounds: ReportRect(plot.left + i * bw, plot.top, bw, plot.height),
            elementId: _elementId,
            band: _band,
            fill: _tint(d.pointColors[i % d.pointColors.length], 0.55),
          ),
        );
      }
    }
    final double t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    final double barH = plot.height * 0.42;
    _out.add(
      ReportRectPrimitive(
        bounds: ReportRect(
          plot.left,
          plot.top + (plot.height - barH) / 2,
          plot.width * t,
          barH,
        ),
        elementId: _elementId,
        band: _band,
        fill: d.series.first.color,
      ),
    );
    if (d.target != null) {
      final double tx =
          plot.left +
          plot.width * ((d.target! - lo) / (hi - lo)).clamp(0.0, 1.0);
      _line(
        tx,
        plot.top - 1,
        tx,
        plot.bottom + 1,
        const ReportColor(0xFF111827),
        1.8,
      );
    }
    if (d.showValues) {
      final ReportFontSpec small = _smaller(_font);
      _label(
        formatValue(v, d.valueFormat),
        small,
        ReportRect(
          plot.left,
          plot.bottom + 2,
          plot.width,
          shaper.lineHeight(small),
        ),
        ReportTextAlign.left,
        _textColor,
      );
    }
  }

  void _funnel(ReportChartData d, ReportRect area) {
    final List<double> values = d.series.first.values;
    var maxV = 0.0;
    for (final double v in values) {
      maxV = math.max(maxV, v.abs());
    }
    if (maxV <= 0) {
      return;
    }
    final int n = values.length;
    final double slot = area.height / n;
    final ReportFontSpec small = _smaller(_font);
    final double slh = shaper.lineHeight(small);
    for (int i = 0; i < n; i++) {
      final double w0 = area.width * (values[i].abs() / maxV);
      final double next = i + 1 < n
          ? values[i + 1].abs()
          : values[i].abs() * 0.72;
      final double w1 = area.width * (next / maxV);
      final double top = area.top + i * slot + slot * 0.08;
      final double h = slot * 0.84;
      final double x0 = area.left + (area.width - w0) / 2;
      final double x1 = area.left + (area.width - w1) / 2;
      final ReportColor color = d.pointColors[i % d.pointColors.length];
      _poly(<double>[
        x0,
        top,
        x0 + w0,
        top,
        x1 + w1,
        top + h,
        x1,
        top + h,
      ], fill: color);
      if (d.showValues && h >= slh) {
        _label(
          formatValue(values[i], d.valueFormat),
          small,
          ReportRect(area.left, top + (h - slh) / 2, area.width, slh),
          ReportTextAlign.center,
          _contrast(color),
        );
      }
    }
  }

  void _scatter(ReportChartData d, ReportRect area) {
    var xLo = double.infinity;
    var xHi = -double.infinity;
    var yLo = 0.0;
    var yHi = 0.0;
    var zHi = 1.0;
    for (final ReportChartSeriesData s in d.series) {
      for (int i = 0; i < s.values.length; i++) {
        final double x = s.xs != null && i < s.xs!.length
            ? s.xs![i]
            : (i + 1).toDouble();
        xLo = math.min(xLo, x);
        xHi = math.max(xHi, x);
        yLo = math.min(yLo, s.values[i]);
        yHi = math.max(yHi, s.values[i]);
        if (s.sizes != null && i < s.sizes!.length) {
          zHi = math.max(zHi, s.sizes![i].abs());
        }
      }
    }
    if (xLo == double.infinity) {
      return;
    }
    final ({double lo, double hi, double step}) xs = _fit(
      xLo,
      xHi,
      min: d.axisMin,
      max: d.axisMax,
    );
    final ({double lo, double hi, double step}) ys = _fit(
      yLo,
      yHi,
      min: d.axisMin2,
      max: d.axisMax2,
    );
    final double lh = shaper.lineHeight(_smaller(_font));
    final ReportRect plot = ReportRect(
      area.left + (d.showAxes ? 28 : 4),
      area.top + 4,
      area.width - (d.showAxes ? 36 : 8),
      area.height - (d.showAxes ? lh + 8 : 8),
    );
    if (plot.width <= 4 || plot.height <= 4) {
      return;
    }
    double px(double v) =>
        plot.left + (v - xs.lo) / (xs.hi - xs.lo) * plot.width;
    double py(double v) =>
        plot.bottom - (v - ys.lo) / (ys.hi - ys.lo) * plot.height;
    if (d.showGrid) {
      for (double v = ys.lo; v <= ys.hi + ys.step * 1e-6; v += ys.step) {
        _line(plot.left, py(v), plot.right, py(v), _gridColor, 0.4);
      }
    }
    if (d.showAxes) {
      _line(plot.left, plot.top, plot.left, plot.bottom, _axisColor, 0.6);
      _line(plot.left, plot.bottom, plot.right, plot.bottom, _axisColor, 0.6);
    }
    final bool bubble = d.type == ReportChartType.bubble;
    for (final ReportChartSeriesData s in d.series) {
      for (int i = 0; i < s.values.length; i++) {
        final double x = s.xs != null && i < s.xs!.length
            ? s.xs![i]
            : (i + 1).toDouble();
        final double z = s.sizes != null && i < s.sizes!.length
            ? s.sizes![i].abs()
            : 1;
        final double r = bubble ? 2.2 + 9 * math.sqrt(z / zHi) : d.markerSize;
        _dot(px(x), py(s.values[i]), r, s.color);
        if (d.showValues && i < d.categories.length) {
          _label(
            d.categories[i],
            _smaller(_font),
            ReportRect(px(x) + r, py(s.values[i]) - lh, 48, lh),
            ReportTextAlign.left,
            _textColor,
          );
        }
      }
    }
  }

  void _heatmap(ReportChartData d, ReportRect area) {
    final int cols = d.categories.length;
    final int rows = d.series.length;
    if (cols == 0 || rows == 0) {
      return;
    }
    final double lh = shaper.lineHeight(_font);
    final double topLab = d.showAxes ? lh + 2 : 0;
    var rowLab = 0.0;
    if (d.showAxes) {
      for (final ReportChartSeriesData s in d.series) {
        rowLab = math.max(rowLab, _width(s.name, _font));
      }
      rowLab = math.min(rowLab + 4, area.width * 0.32);
    }
    final ReportRect plot = ReportRect(
      area.left + rowLab,
      area.top + topLab,
      area.width - rowLab,
      area.height - topLab,
    );
    if (plot.width <= 4 || plot.height <= 4) {
      return;
    }
    var lo = d.series.first.values.first;
    var hi = lo;
    for (final ReportChartSeriesData s in d.series) {
      for (final double v in s.values) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if ((hi - lo).abs() < 1e-9) {
      hi = lo + 1;
    }
    final double cw = plot.width / cols;
    final double ch = plot.height / rows;
    final ReportFontSpec small = _smaller(_font);
    final double slh = shaper.lineHeight(small);
    for (int r = 0; r < rows; r++) {
      if (d.showAxes) {
        _label(
          d.series[r].name,
          _font,
          ReportRect(area.left, plot.top + r * ch, rowLab - 3, ch),
          ReportTextAlign.right,
          _textColor,
        );
      }
      for (int c = 0; c < cols; c++) {
        final double v = c < d.series[r].values.length
            ? d.series[r].values[c]
            : 0;
        final double t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
        final ReportColor color = _mix(
          const ReportColor(0xFFF8FAFC),
          d.pointColors[math.min(
            d.pointColors.length - 1,
            (t * (d.pointColors.length - 1)).round(),
          )],
          0.25 + 0.75 * t,
        );
        final ReportRect cell = ReportRect(
          plot.left + c * cw + 0.6,
          plot.top + r * ch + 0.6,
          cw - 1.2,
          ch - 1.2,
        );
        _out.add(
          ReportRectPrimitive(
            bounds: cell,
            elementId: _elementId,
            band: _band,
            fill: color,
          ),
        );
        if (d.showValues && ch >= slh && cw >= 12) {
          _label(
            formatValue(v, d.valueFormat),
            small,
            ReportRect(
              cell.left,
              cell.top + (cell.height - slh) / 2,
              cell.width,
              slh,
            ),
            ReportTextAlign.center,
            _contrast(color),
          );
        }
      }
    }
    if (d.showAxes) {
      for (int c = 0; c < cols; c++) {
        _label(
          d.categories[c],
          small,
          ReportRect(plot.left + c * cw, area.top, cw, lh),
          ReportTextAlign.center,
          _textColor,
        );
      }
    }
  }

  void _radar(ReportChartData d, ReportRect area) {
    final int n = d.categories.length;
    if (n < 3) {
      return;
    }
    final double radius = math.min(area.width, area.height) / 2 - 8;
    if (radius <= 8) {
      return;
    }
    final double cx = area.left + area.width / 2;
    final double cy = area.top + area.height / 2;
    final ({double lo, double hi}) range = _range(d);
    final ({double lo, double hi, double step}) scale = _fit(
      range.lo,
      range.hi,
      min: d.axisMin,
      max: d.axisMax,
    );
    double at(int i, double t) => -math.pi / 2 + 2 * math.pi * i / n;
    for (final double frac in <double>[0.25, 0.5, 0.75, 1]) {
      final Float64List ring = Float64List(n * 2);
      for (int i = 0; i < n; i++) {
        final double a = at(i, frac);
        ring[i * 2] = cx + math.cos(a) * radius * frac;
        ring[i * 2 + 1] = cy + math.sin(a) * radius * frac;
      }
      _out.add(
        ReportPathPrimitive.through(
          ring,
          elementId: _elementId,
          band: _band,
          closed: true,
          stroke: _gridColor,
          strokeWidth: 0.5,
        ),
      );
    }
    for (int i = 0; i < n; i++) {
      final double a = at(i, 1);
      _line(
        cx,
        cy,
        cx + math.cos(a) * radius,
        cy + math.sin(a) * radius,
        _gridColor,
        0.5,
      );
      if (d.showAxes) {
        final double lx = cx + math.cos(a) * (radius + 2);
        final double ly = cy + math.sin(a) * (radius + 2);
        _label(
          d.categories[i],
          _smaller(_font),
          ReportRect(lx - 28, ly - 6, 56, 12),
          ReportTextAlign.center,
          _textColor,
        );
      }
    }
    for (final ReportChartSeriesData s in d.series) {
      final Float64List poly = Float64List(n * 2);
      for (int i = 0; i < n; i++) {
        final double v = i < s.values.length ? s.values[i] : 0;
        final double t = ((v - scale.lo) / (scale.hi - scale.lo)).clamp(
          0.0,
          1.0,
        );
        final double a = at(i, t);
        poly[i * 2] = cx + math.cos(a) * radius * t;
        poly[i * 2 + 1] = cy + math.sin(a) * radius * t;
      }
      final Float64List drawn = d.smooth ? _curve(_closedCurve(poly)) : poly;
      _out.add(
        ReportPathPrimitive.through(
          drawn,
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: _tint(s.color, 0.62),
          stroke: s.color,
          strokeWidth: d.lineWidth,
        ),
      );
      if (d.drawMarkers) {
        _dots(poly, s.color, d.markerSize);
      }
    }
  }

  void _spark(ReportChartData d, ReportRect area) {
    final ReportChartSeriesData s = d.series.first;
    final int n = s.values.length;
    if (n == 0 || area.width <= 2) {
      return;
    }
    var lo = s.values.first;
    var hi = lo;
    for (final double v in s.values) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final ({double lo, double hi, double step}) scale = _fit(
      lo,
      hi,
      min: d.axisMin,
      max: d.axisMax,
      ticks: 2,
    );
    double y(double v) =>
        area.bottom - (v - scale.lo) / (scale.hi - scale.lo) * area.height;
    if (s.style == ReportSeriesStyle.column) {
      final double bw = area.width / n;
      final double zero = y(
        scale.lo > 0 ? scale.lo : (scale.hi < 0 ? scale.hi : 0),
      );
      for (int i = 0; i < n; i++) {
        final double vy = y(s.values[i]);
        _out.add(
          ReportRectPrimitive(
            bounds: ReportRect(
              area.left + i * bw + bw * 0.15,
              math.min(vy, zero),
              bw * 0.7,
              math.max((vy - zero).abs(), 0.6),
            ),
            elementId: _elementId,
            band: _band,
            fill: s.color,
          ),
        );
      }
      return;
    }
    final Float64List line = Float64List(n * 2);
    for (int i = 0; i < n; i++) {
      line[i * 2] =
          area.left + (n == 1 ? area.width / 2 : area.width * i / (n - 1));
      line[i * 2 + 1] = y(s.values[i]);
    }
    final Float64List stroke = d.smooth && n > 2 ? _curve(line) : line;
    if (s.style == ReportSeriesStyle.area && n > 1) {
      final Float64List poly = Float64List(stroke.length + 4)
        ..setRange(0, stroke.length, stroke);
      poly[stroke.length] = stroke[stroke.length - 2];
      poly[stroke.length + 1] = area.bottom;
      poly[stroke.length + 2] = stroke[0];
      poly[stroke.length + 3] = area.bottom;
      _out.add(
        ReportPathPrimitive.through(
          poly,
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: _tint(s.color, 0.5),
        ),
      );
    }
    if (n > 1) {
      _out.add(
        ReportPathPrimitive.through(
          stroke,
          elementId: _elementId,
          band: _band,
          stroke: s.color,
          strokeWidth: d.lineWidth,
        ),
      );
    }
    if (d.drawMarkers) {
      _dots(line, s.color, math.min(d.markerSize, 3));
    }
  }

  Float64List _curve(Float64List line) {
    final int n = line.length ~/ 2;
    if (n < 3) {
      return line;
    }
    const int steps = 8;
    final Float64List out = Float64List((n - 1) * steps * 2);
    var k = 0;
    for (int i = 0; i < n - 1; i++) {
      double at(int index, int axis) {
        final int j = index.clamp(0, n - 1);
        return line[j * 2 + axis];
      }

      for (int s = 0; s < steps; s++) {
        final double t = s / steps;
        final double t2 = t * t;
        final double t3 = t2 * t;
        for (int axis = 0; axis < 2; axis++) {
          final double p0 = at(i - 1, axis);
          final double p1 = at(i, axis);
          final double p2 = at(i + 1, axis);
          final double p3 = at(i + 2, axis);
          out[k++] =
              0.5 *
              ((2 * p1) +
                  (-p0 + p2) * t +
                  (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                  (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
        }
      }
    }
    return out;
  }

  Float64List _closedCurve(Float64List poly) {
    final int n = poly.length ~/ 2;
    final Float64List loop = Float64List((n + 1) * 2);
    loop.setRange(0, poly.length, poly);
    loop[poly.length] = poly[0];
    loop[poly.length + 1] = poly[1];
    return _curve(loop);
  }

  ({double lo, double hi, double step}) _fit(
    double lo,
    double hi, {
    double? min,
    double? max,
    int ticks = 4,
  }) {
    var a = lo;
    var b = hi;
    if (min != null) {
      a = min;
    }
    if (max != null) {
      b = max;
    }
    if (b - a < 1e-9) {
      b = a + 1;
    }
    final ({double lo, double hi, double step}) s = niceScale(a, b, ticks);
    if (min == null && max == null) {
      return s;
    }
    final double step = s.step == 0 ? 1 : s.step;
    return (lo: min ?? s.lo, hi: max ?? s.hi, step: step);
  }

  void _poly(List<double> xy, {ReportColor? fill, ReportColor? stroke}) {
    _out.add(
      ReportPathPrimitive.through(
        Float64List.fromList(xy),
        elementId: _elementId,
        band: _band,
        closed: true,
        fill: fill,
        stroke: stroke,
        strokeWidth: stroke == null ? 0 : 0.6,
      ),
    );
  }

  void _dot(double x, double y, double r, ReportColor color) {
    _out.add(
      ReportRectPrimitive(
        bounds: ReportRect(x - r, y - r, r * 2, r * 2),
        elementId: _elementId,
        band: _band,
        fill: color,
        stroke: ReportColor.white,
        strokeWidth: 0.5,
        ellipse: true,
      ),
    );
  }

  void _dots(Float64List line, ReportColor color, double r) {
    for (int i = 0; i < line.length; i += 2) {
      _dot(line[i], line[i + 1], r, color);
    }
  }

  static ReportColor _shade(ReportColor c, double amount) {
    int mix(int v) => (v * (1 - amount)).round().clamp(0, 255);
    return ReportColor.rgb(mix(c.red), mix(c.green), mix(c.blue));
  }

  static ReportColor _mix(ReportColor a, ReportColor b, double t) {
    int mix(int p, int q) => (p + (q - p) * t).round().clamp(0, 255);
    return ReportColor.rgb(
      mix(a.red, b.red),
      mix(a.green, b.green),
      mix(a.blue, b.blue),
    );
  }

  /// Polygon of a pie wedge (or a ring segment when [inner] > 0), with
  /// arcs flattened to segments of at most 3°.
  static Float64List wedge(
    double cx,
    double cy,
    double radius,
    double inner,
    double start,
    double sweep,
  ) {
    final int steps = math.max(2, (sweep / (math.pi / 60)).ceil());
    final bool ring = inner > 0;
    final int count = steps + 1 + (ring ? steps + 1 : 1);
    final Float64List pts = Float64List(count * 2);
    var k = 0;
    for (int i = 0; i <= steps; i++) {
      final double a = start + sweep * i / steps;
      pts[k++] = cx + math.cos(a) * radius;
      pts[k++] = cy + math.sin(a) * radius;
    }
    if (ring) {
      for (int i = steps; i >= 0; i--) {
        final double a = start + sweep * i / steps;
        pts[k++] = cx + math.cos(a) * inner;
        pts[k++] = cy + math.sin(a) * inner;
      }
    } else {
      pts[k++] = cx;
      pts[k++] = cy;
    }
    return pts;
  }

  // ------------------------------------------------------------ helpers

  static ReportFontSpec _smaller(ReportFontSpec f) => ReportFontSpec(
    family: f.family,
    size: f.size * 0.88,
    bold: f.bold,
    italic: f.italic,
  );

  /// Opaque mix of [c] toward white by [amount] (PDF paints alpha opaque).
  static ReportColor _tint(ReportColor c, double amount) {
    int mix(int v) => (v + (255 - v) * amount).round().clamp(0, 255);
    return ReportColor.rgb(mix(c.red), mix(c.green), mix(c.blue));
  }

  static ReportColor _contrast(ReportColor c) {
    final double lum = 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue;
    return lum > 160 ? const ReportColor(0xFF202124) : ReportColor.white;
  }

  /// True when [text] holds right-to-left letters.
  static bool hasRtl(String text) {
    for (final int cp in text.runes) {
      if ((cp >= 0x0590 && cp <= 0x08FF) || (cp >= 0xFB1D && cp <= 0xFEFC)) {
        return true;
      }
    }
    return false;
  }

  double _width(String text, ReportFontSpec f) => text.isEmpty
      ? 0
      : shaper
            .shape(text, f, maxWidth: 1e6, rtl: hasRtl(text), wrap: false)
            .maxLineWidth;

  void _line(
    double x1,
    double y1,
    double x2,
    double y2,
    ReportColor color,
    double width,
  ) {
    _out.add(
      ReportLinePrimitive(
        bounds: ReportRect(
          math.min(x1, x2),
          math.min(y1, y2),
          (x2 - x1).abs(),
          (y2 - y1).abs(),
        ),
        elementId: _elementId,
        band: _band,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: color,
        width: width,
      ),
    );
  }

  void _shapeMap(ReportChartData d, ReportRect area) {
    final ReportShapeLayer layer = d.shapes!;
    const ReportColor ocean = ReportColor(0xFFE7F1F8);
    final Map<int, double> values = <int, double>{};
    final Map<int, ReportColor> paints = <int, ReportColor>{};
    final bool colored = d.regionColors != null;
    if (colored) {
      final List<ReportColor?> colors = d.regionColors!;
      final int n = math.min(d.categories.length, colors.length);
      for (int i = 0; i < n; i++) {
        final ReportColor? color = colors[i];
        if (color == null) {
          continue;
        }
        final int? at = layer.indexOf(d.categories[i]);
        if (at != null) {
          paints.putIfAbsent(at, () => color);
        }
      }
    }
    final Map<int, String> formulaText = <int, String>{};
    if (d.regionLabels != null) {
      final int n = math.min(d.categories.length, d.regionLabels!.length);
      for (int i = 0; i < n; i++) {
        final int? at = layer.indexOf(d.categories[i]);
        if (at != null) {
          formulaText.putIfAbsent(at, () => d.regionLabels![i]);
        }
      }
    }
    final bool formula = d.regionLabels != null;
    final bool namedField = (d.labelField ?? '').trim().isNotEmpty;
    if (d.series.isNotEmpty) {
      final ReportChartSeriesData series = d.series.first;
      final int n = math.min(d.categories.length, series.values.length);
      for (int i = 0; i < n; i++) {
        final int? at = layer.indexOf(d.categories[i]);
        if (at != null && !values.containsKey(at)) {
          values[at] = series.values[i];
        }
      }
    }
    double? lo;
    double? hi;
    for (final double v in values.values) {
      lo = lo == null || v < lo ? v : lo;
      hi = hi == null || v > hi ? v : hi;
    }
    final bool legend = !colored && d.showLegend && lo != null && hi != null;
    final ReportFontSpec legendFont = d.legendFont ?? _font;
    final double legendBand = shaper.lineHeight(legendFont) + 16;
    final ReportRect plot = ReportRect(
      area.left,
      area.top,
      area.width,
      math.max(8, area.height - (legend ? legendBand : 0)),
    );
    _out.add(
      ReportRectPrimitive(
        bounds: plot,
        elementId: _elementId,
        band: _band,
        fill: ocean,
      ),
    );
    var minLon = double.infinity;
    var maxLon = -double.infinity;
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    for (final ReportShapeFeature f in layer.features) {
      for (final ReportShapeRing ring in f.rings) {
        for (int i = 0; i < ring.length; i++) {
          final double x = ring.lonLat[i * 2];
          final double y = ring.lonLat[i * 2 + 1];
          if (x < minLon) {
            minLon = x;
          }
          if (x > maxLon) {
            maxLon = x;
          }
          if (y < minLat) {
            minLat = y;
          }
          if (y > maxLat) {
            maxLat = y;
          }
        }
      }
    }
    // A world-sized layer. Antarctica otherwise eats the frame. A
    // governorate, or a layer that is itself polar, keeps every ring.
    final bool dropSouth = maxLat - minLat > 70 && maxLat > 20;
    const double southCut = -56;
    bool kept(ReportShapeRing ring) {
      if (!dropSouth) {
        return true;
      }
      for (int i = 0; i < ring.length; i++) {
        if (ring.lonLat[i * 2 + 1] >= southCut) {
          return true;
        }
      }
      return false;
    }

    double px(double lon) => lon * math.pi / 180;
    double py(double lat) {
      final double c = lat.clamp(-80, 80);
      final double r = c * math.pi / 180;
      return math.log(math.tan(math.pi / 4 + r / 2));
    }

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final ReportShapeFeature f in layer.features) {
      for (final ReportShapeRing ring in f.rings) {
        if (!kept(ring)) {
          continue;
        }
        for (int i = 0; i < ring.length; i++) {
          final double x = px(ring.lonLat[i * 2]);
          final double y = py(ring.lonLat[i * 2 + 1]);
          if (x < minX) {
            minX = x;
          }
          if (x > maxX) {
            maxX = x;
          }
          if (y < minY) {
            minY = y;
          }
          if (y > maxY) {
            maxY = y;
          }
        }
      }
    }
    if (minX == double.infinity) {
      return;
    }
    final double spanX = math.max(maxX - minX, 1e-6);
    final double spanY = math.max(maxY - minY, 1e-6);
    const double pad = 3;
    final double scale = math.min(
      (plot.width - pad * 2) / spanX,
      (plot.height - pad * 2) / spanY,
    );
    final double ox =
        plot.left + (plot.width - spanX * scale) / 2 - minX * scale;
    final double oy =
        plot.top + (plot.height - spanY * scale) / 2 + maxY * scale;
    double sx(double lon) => ox + px(lon) * scale;
    double sy(double lat) => oy - py(lat) * scale;
    final List<({int feature, ReportShapeRing ring})> rings =
        <({int feature, ReportShapeRing ring})>[
          for (int f = 0; f < layer.features.length; f++)
            for (final ReportShapeRing ring in layer.features[f].rings)
              if (kept(ring)) (feature: f, ring: ring),
        ]..sort(
          (
            ({int feature, ReportShapeRing ring}) a,
            ({int feature, ReportShapeRing ring}) b,
          ) => b.ring.signedArea.abs().compareTo(a.ring.signedArea.abs()),
        );
    final double span = hi == null || lo == null ? 1 : math.max(hi - lo, 1e-9);
    for (final ({int feature, ReportShapeRing ring}) item in rings) {
      final Float64List xy = Float64List(item.ring.length * 2);
      for (int i = 0; i < item.ring.length; i++) {
        xy[i * 2] = sx(item.ring.lonLat[i * 2]);
        xy[i * 2 + 1] = sy(item.ring.lonLat[i * 2 + 1]);
      }
      final ReportColor fill;
      if (item.ring.hole) {
        fill = ocean;
      } else {
        final ReportColor? named = paints[item.feature];
        final double? v = values[item.feature];
        if (named != null) {
          fill = named;
        } else if (colored || v == null) {
          fill = d.empty;
        } else {
          fill = _mix(d.low, d.high, (v - lo!) / span);
        }
      }
      final bool darkFill = _dark(fill);
      _out.add(
        ReportPathPrimitive.through(
          xy,
          elementId: _elementId,
          band: _band,
          closed: true,
          fill: fill,
          stroke: item.ring.hole
              ? null
              : (darkFill ? ReportColor.white : const ReportColor(0xFF7C93A8)),
          strokeWidth: item.ring.hole ? 0 : (darkFill ? 0.55 : 0.4),
        ),
      );
    }
    if (d.showLabels) {
      final String labelSource = (d.labelField ?? '').trim();
      QudsExpressionEngine? labelEngine;
      final ReportFontSpec labelFont = d.labelFont ?? _font;
      final double line = shaper.lineHeight(labelFont);
      int mainRing(ReportShapeFeature feature) {
        var best = -1;
        var area = -1.0;
        for (int i = 0; i < feature.rings.length; i++) {
          final ReportShapeRing ring = feature.rings[i];
          if (ring.hole || !kept(ring)) {
            continue;
          }
          final double a = ring.signedArea.abs();
          if (a > area) {
            area = a;
            best = i;
          }
        }
        return best;
      }

      final List<int> order =
          <int>[for (int i = 0; i < layer.features.length; i++) i]
            ..sort((int a, int b) {
              double areaOf(int i) {
                final int ring = mainRing(layer.features[i]);
                return ring < 0
                    ? 0
                    : layer.features[i].rings[ring].signedArea.abs();
              }

              return areaOf(b).compareTo(areaOf(a));
            });
      final List<({double l, double t, double r, double b})> taken =
          <({double l, double t, double r, double b})>[];
      bool crowded(double l, double t, double r, double b) {
        for (final ({double l, double t, double r, double b}) box in taken) {
          if (l < box.r && box.l < r && t < box.b && box.t < b) {
            return true;
          }
        }
        return false;
      }

      for (final int f in order) {
        final ReportShapeFeature feature = layer.features[f];
        final int ringAt = mainRing(feature);
        if (ringAt < 0) {
          continue;
        }
        final ReportShapeRing ring = feature.rings[ringAt];
        double? left, right, top, bottom;
        for (int i = 0; i < ring.length; i++) {
          final double x = sx(ring.lonLat[i * 2]);
          final double y = sy(ring.lonLat[i * 2 + 1]);
          left = left == null || x < left ? x : left;
          right = right == null || x > right ? x : right;
          top = top == null || y < top ? y : top;
          bottom = bottom == null || y > bottom ? y : bottom;
        }
        if (left == null || right == null || top == null || bottom == null) {
          continue;
        }
        final double w = right - left;
        final double h = bottom - top;
        if (w < 20 || h < 11) {
          continue;
        }
        final double? v = values[f];
        final String valueText = v == null
            ? ''
            : formatter.format(ReportNumber(v), d.valueFormat);
        final bool own = formula || namedField;
        String resolved;
        if (formula && formulaText.containsKey(f)) {
          resolved = formulaText[f]!.trim();
        } else if (formula && labelSource.isNotEmpty) {
          labelEngine ??= QudsExpressionEngine(formatter: formatter);
          resolved = labelEngine
              .shapeCaption(labelSource, feature, layer)
              .trim();
        } else if (namedField) {
          resolved = feature.valueOf(d.labelField).trim();
          if (resolved.isEmpty) {
            resolved = _featureLabel(d, feature);
          }
        } else {
          resolved = feature.label.trim().isEmpty
              ? feature.key
              : feature.label.trim();
        }
        if (resolved.isEmpty) {
          continue;
        }
        List<String> lines = resolved.split('\n');
        double widest = 0;
        for (final String lineText in lines) {
          final double lw = shaper.measure(lineText, labelFont);
          if (lw > widest) {
            widest = lw;
          }
        }
        final double valueW = shaper.measure(valueText, labelFont);
        final bool withValue =
            d.showValues && valueText.isNotEmpty && valueW <= w - 2;
        if (widest > w - 2 || lines.length * line > h - 2) {
          if (own) {
            continue;
          }
          final String key = feature.key.trim();
          final double keyW = shaper.measure(key, labelFont);
          if (key.isEmpty || keyW > w - 2) {
            continue;
          }
          lines = <String>[key];
          widest = keyW;
        }
        final double block = (lines.length + (withValue ? 1 : 0)) * line;
        if (block > h - 2) {
          continue;
        }
        final double lx = left + (w - widest) / 2;
        final double ly = top + (h - block) / 2;
        if (ly < plot.top || ly + block > plot.bottom) {
          continue;
        }
        if (crowded(lx - 1.5, ly - 0.8, lx + widest + 1.5, ly + block + 0.8)) {
          continue;
        }
        final ReportColor ink =
            _labelColor ??
            (_dark(
                  v == null
                      ? d.empty
                      : _mix(d.low, d.high, lo == null ? 0 : (v - lo) / span),
                )
                ? ReportColor.white
                : const ReportColor(0xFF1A1A1A));
        for (int i = 0; i < lines.length; i++) {
          final double lw = shaper.measure(lines[i], labelFont);
          _label(
            lines[i],
            labelFont,
            ReportRect(left + (w - lw) / 2, ly + i * line, lw, line),
            ReportTextAlign.center,
            ink,
          );
        }
        if (withValue) {
          _label(
            valueText,
            labelFont,
            ReportRect(
              left + (w - valueW) / 2,
              ly + lines.length * line,
              valueW,
              line,
            ),
            ReportTextAlign.center,
            ink,
          );
        }
        taken.add((
          l: lx - 1.5,
          t: ly - 0.8,
          r: lx + widest + 1.5,
          b: ly + block + 0.8,
        ));
      }
    }
    if (!legend) {
      return;
    }
    final double barW = math.min(110, area.width * 0.42);
    final double y = area.bottom - 10;
    const int steps = 14;
    for (int i = 0; i < steps; i++) {
      _out.add(
        ReportRectPrimitive(
          bounds: ReportRect(
            area.left + barW * i / steps,
            y,
            barW / steps + 0.2,
            8,
          ),
          elementId: _elementId,
          band: _band,
          fill: _mix(d.low, d.high, i / (steps - 1)),
        ),
      );
    }
    final String loText = formatter.format(ReportNumber(lo), d.valueFormat);
    final String hiText = formatter.format(ReportNumber(hi), d.valueFormat);
    final double line = shaper.lineHeight(legendFont);
    final double loW = shaper.measure(loText, legendFont);
    final double hiW = shaper.measure(hiText, legendFont);
    final ReportColor legendInk = d.legendInk ?? _textColor;
    final double yText = y - line - 1;
    _label(
      loText,
      legendFont,
      ReportRect(area.left, yText, loW + 1, line),
      ReportTextAlign.start,
      legendInk,
    );
    _label(
      hiText,
      legendFont,
      ReportRect(
        area.left + math.max(loW + 6, barW - hiW),
        yText,
        hiW + 1,
        line,
      ),
      ReportTextAlign.start,
      legendInk,
    );
    if (values.length < layer.features.length) {
      final double x = area.left + barW + 10;
      _out.add(
        ReportRectPrimitive(
          bounds: ReportRect(x, y, 8, 8),
          elementId: _elementId,
          band: _band,
          fill: d.empty,
          stroke: const ReportColor(0xFFB0B0B0),
          strokeWidth: 0.4,
        ),
      );
    }
  }

  static bool _dark(ReportColor c) =>
      0.3 * c.red + 0.59 * c.green + 0.11 * c.blue < 150;

  void _label(
    String text,
    ReportFontSpec font,
    ReportRect r,
    ReportTextAlign align,
    ReportColor color,
  ) {
    if (text.isEmpty || r.width <= 0) {
      return;
    }
    final bool rtl = hasRtl(text);
    _out.add(
      ReportTextPrimitive(
        bounds: r,
        elementId: _elementId,
        band: _band,
        text: text,
        shaped: shaper.shape(
          text,
          font,
          maxWidth: r.width,
          rtl: rtl,
          wrap: false,
        ),
        contentRect: r,
        font: font,
        color: color,
        align: align,
        verticalAlign: ReportVerticalAlign.middle,
        rtl: rtl,
      ),
    );
  }

  static ReportRect _flip(ReportRect r, double axis) =>
      ReportRect(axis - r.right, r.top, r.width, r.height);

  static ReportPrimitive _mirror(ReportPrimitive p, double axis) {
    return switch (p) {
      ReportTextPrimitive() => ReportTextPrimitive(
        bounds: _flip(p.bounds, axis),
        elementId: p.elementId,
        band: p.band,
        text: p.text,
        shaped: p.shaped,
        contentRect: _flip(p.contentRect, axis),
        font: p.font,
        color: p.color,
        align: switch (p.align) {
          ReportTextAlign.left => ReportTextAlign.right,
          ReportTextAlign.right => ReportTextAlign.left,
          _ => p.align,
        },
        verticalAlign: p.verticalAlign,
        rtl: p.rtl,
        underline: p.underline,
      ),
      ReportRectPrimitive() => ReportRectPrimitive(
        bounds: _flip(p.bounds, axis),
        elementId: p.elementId,
        band: p.band,
        fill: p.fill,
        stroke: p.stroke,
        strokeWidth: p.strokeWidth,
        radius: p.radius,
        ellipse: p.ellipse,
        lineStyle: p.lineStyle,
      ),
      ReportLinePrimitive() => ReportLinePrimitive(
        bounds: _flip(p.bounds, axis),
        elementId: p.elementId,
        band: p.band,
        x1: axis - p.x1,
        y1: p.y1,
        x2: axis - p.x2,
        y2: p.y2,
        color: p.color,
        width: p.width,
        lineStyle: p.lineStyle,
      ),
      ReportPathPrimitive() => ReportPathPrimitive(
        bounds: _flip(p.bounds, axis),
        elementId: p.elementId,
        band: p.band,
        points: Float64List.fromList(<double>[
          for (int i = 0; i < p.points.length; i++)
            i.isEven ? axis - p.points[i] : p.points[i],
        ]),
        closed: p.closed,
        fill: p.fill,
        stroke: p.stroke,
        strokeWidth: p.strokeWidth,
        lineStyle: p.lineStyle,
      ),
      ReportImagePrimitive() || ReportBarcodePrimitive() => p,
    };
  }
}
