/// In-memory model of a `.qrep` band report template.
///
/// The model is mutable so a designer can edit it in place; the generator
/// never mutates it. All geometry is in points (1/72 inch), y grows down.
library;

import 'report_data.dart';
import 'report_format.dart';
import 'report_units.dart';
import 'report_value.dart';

/// Band sections, in canonical document order.
enum ReportBandKind {
  /// Printed once at the top of the first page.
  reportHeader('ReportHeader'),

  /// Printed at the top of every page.
  pageHeader('PageHeader'),

  /// Printed before each group.
  groupHeader('GroupHeader'),

  /// Repeated per data row (or hosts a repeating table).
  detail('Detail'),

  /// Printed after each group (subtotals).
  groupFooter('GroupFooter'),

  /// Printed at the bottom of every page.
  pageFooter('PageFooter'),

  /// Printed once after the last row.
  reportSummary('ReportSummary');

  const ReportBandKind(this.xmlName);

  /// XML element name.
  final String xmlName;

  /// Kind for [name] (case-insensitive, accepts `reportHeader` too).
  static ReportBandKind? fromXml(String name) {
    final String n = name.toLowerCase();
    for (final ReportBandKind k in ReportBandKind.values) {
      if (k.xmlName.toLowerCase() == n) {
        return k;
      }
    }
    if (n == 'summary' || n == 'reportfooter') {
      return ReportBandKind.reportSummary;
    }
    return null;
  }
}

/// Horizontal text alignment. `start`/`end` follow the text direction.
enum ReportTextAlign { start, end, left, right, center, justify }

/// Vertical alignment inside an element box.
enum ReportVerticalAlign { top, middle, bottom }

/// Paragraph direction override.
enum ReportTextDirection { auto, rtl, ltr }

/// Image scaling.
enum ReportImageFit { contain, cover, fill, none }

/// Barcode symbology.
enum ReportBarcodeType { code128, qr, ean13 }

/// Shape kind.
enum ReportShapeKind { line, rectangle, roundedRectangle, ellipse }

/// Stroke pattern.
enum ReportLineStyle { solid, dashed, dotted }

/// Page orientation.
enum ReportOrientation { portrait, landscape }

/// Origin of element `x` coordinates.
enum ReportCoordinateOrigin {
  /// `x` is measured from the left page edge (default).
  page,

  /// `x` is measured from the left margin.
  margin,
}

/// Chart family drawn by a [ReportChartElement].
enum ReportChartType {
  /// Clustered columns.
  bar,

  /// Clustered bars.
  horizontalBar,

  /// Stacked columns.
  stackedBar,

  /// Stacked columns normalized to 100%.
  percentStackedBar,

  /// Lines through category values.
  line,

  /// Filled lines.
  area,

  /// Areas stacked per category.
  stackedArea,

  /// Pie.
  pie,

  /// Donut.
  donut,

  /// Columns plus lines, with an optional secondary axis.
  combo,

  /// Floating steps from a running total.
  waterfall,

  /// Dial for one value against a minimum, maximum, and target.
  gauge,

  /// Bar against qualitative bands and a target mark.
  bullet,

  /// Stages as centered trapezoids.
  funnel,

  /// One dot per row, X against Y.
  scatter,

  /// Scatter whose dot area encodes a third measure.
  bubble,

  /// Series as polygons around a center.
  radar,

  /// Category × series matrix colored by value.
  heatmap,

  /// Compact line, area, or columns with no chrome.
  sparkline,

  /// Columns with an oblique top and side.
  extrudedBar,

  /// Pie with a visible thickness.
  extrudedPie,

  /// Donut with a visible thickness.
  extrudedDonut,

  /// Regions of a shape layer colored by value.
  shapeMap;

  /// Pie, donut, and their extruded forms.
  bool get isPie =>
      this == pie ||
      this == donut ||
      this == extrudedPie ||
      this == extrudedDonut;

  /// Oblique 3D drawing.
  bool get isExtruded =>
      this == extrudedBar || this == extrudedPie || this == extrudedDonut;

  /// Each row is a point (no category aggregation).
  bool get plotsPoints => this == scatter || this == bubble;

  /// Closed regions colored by a measure.
  bool get isShapeMap => this == shapeMap;
}

/// How one combo series is drawn.
enum ReportSeriesStyle { column, line, area }

/// How rows sharing a category are combined into one chart value.
enum ReportChartAggregate { sum, avg, count, min, max, first, last }

/// Category order after aggregation.
enum ReportChartSort { none, category, value }

/// Element kind (mirrors `type="…"`).
enum ReportElementType { text, image, table, barcode, shape, chart, crosstab, subreport }

/// Enum value for [name] ignoring case, `-`, and `_`.
T? reportEnumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) {
    return null;
  }
  final String n = name.replaceAll(RegExp(r'[-_\s]'), '').toLowerCase();
  for (final T v in values) {
    if (v.name.toLowerCase() == n) {
      return v;
    }
  }
  return null;
}

/// Axis-aligned rectangle in points.
class ReportRect {
  /// ReportRect API.
  const ReportRect(this.left, this.top, this.width, this.height);

  /// left API.
  final double left;

  /// top API.
  final double top;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// right API.
  double get right => left + width;

  /// bottom API.
  double get bottom => top + height;

  /// Shifted copy.
  ReportRect translate(double dx, double dy) =>
      ReportRect(left + dx, top + dy, width, height);

  /// True when the point lies inside (edges inclusive).
  bool contains(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  /// True when the rectangles overlap.
  bool overlaps(ReportRect o) =>
      left < o.right && o.left < right && top < o.bottom && o.top < bottom;

  @override
  String toString() =>
      'ReportRect(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)})';
}

/// Named page size in points (portrait).
class ReportPageSize {
  /// ReportPageSize API.
  const ReportPageSize(this.name, this.width, this.height);

  /// name API.
  final String name;

  /// width API.
  final double width;

  /// height API.
  final double height;

  static const double _mm = 72 / 25.4;

  /// a3 API.
  static const ReportPageSize a3 = ReportPageSize('A3', 297 * _mm, 420 * _mm);

  /// a4 API.
  static const ReportPageSize a4 = ReportPageSize('A4', 210 * _mm, 297 * _mm);

  /// a5 API.
  static const ReportPageSize a5 = ReportPageSize('A5', 148 * _mm, 210 * _mm);

  /// b5 API.
  static const ReportPageSize b5 = ReportPageSize('B5', 176 * _mm, 250 * _mm);

  /// letter API.
  static const ReportPageSize letter = ReportPageSize('Letter', 612, 792);

  /// legal API.
  static const ReportPageSize legal = ReportPageSize('Legal', 612, 1008);

  /// Named sizes.
  static const List<ReportPageSize> named = <ReportPageSize>[
    a3,
    a4,
    a5,
    b5,
    letter,
    legal,
  ];

  /// Size for [name] (case-insensitive), or null.
  static ReportPageSize? byName(String name) {
    final String n = name.trim().toLowerCase();
    for (final ReportPageSize s in named) {
      if (s.name.toLowerCase() == n) {
        return s;
      }
    }
    return null;
  }
}

/// Page margins in points.
class ReportMargins {
  /// ReportMargins API.
  ReportMargins({
    this.top = 56.69,
    this.bottom = 56.69,
    this.left = 42.52,
    this.right = 42.52,
  });

  /// top API.
  double top;

  /// bottom API.
  double bottom;

  /// left API.
  double left;

  /// right API.
  double right;

  /// copy API.
  ReportMargins copy() =>
      ReportMargins(top: top, bottom: bottom, left: left, right: right);
}

/// Font and color overrides for text. Null fields inherit report defaults.
class ReportTextStyle {
  /// ReportTextStyle API.
  ReportTextStyle({
    this.fontFamily,
    this.fontSize,
    this.bold,
    this.italic,
    this.underline,
    this.color,
  });

  /// fontFamily API.
  String? fontFamily;

  /// Points.
  double? fontSize;

  /// bold API.
  bool? bold;

  /// italic API.
  bool? italic;

  /// underline API.
  bool? underline;

  /// Raw color: `#RRGGBB`, a CSS name, or a palette name (`primary`).
  String? color;

  /// copy API.
  ReportTextStyle copy() => ReportTextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    bold: bold,
    italic: italic,
    underline: underline,
    color: color,
  );
}

/// `<Var name="…" value="…"/>`. [value] may contain `{{ }}` placeholders.
/// Data type of a template variable.
enum ReportVariableType {
  /// Text; `{{ }}` placeholders are expanded.
  text,

  /// Number (`1250.5`).
  number,

  /// `true` / `false`.
  boolean,

  /// Date `yyyy-MM-dd` (optionally `THH:mm[:ss]`), or `today` / `now`.
  date,

  /// Items separated by `;` (numbers stay numeric).
  list,

  /// Expression without braces, evaluated against the data
  /// (`SUM(Data.items.total) * 0.15`).
  expression;

  /// Parses an XML `type` value (case-insensitive aliases accepted).
  static ReportVariableType? fromName(String raw) =>
      switch (raw.trim().toLowerCase()) {
        'text' || 'string' || '' => ReportVariableType.text,
        'number' ||
        'numeric' ||
        'decimal' ||
        'int' ||
        'integer' => ReportVariableType.number,
        'boolean' || 'bool' => ReportVariableType.boolean,
        'date' || 'datetime' => ReportVariableType.date,
        'list' || 'array' => ReportVariableType.list,
        'expression' || 'expr' || 'formula' => ReportVariableType.expression,
        _ => null,
      };
}

/// Value stored in the template itself (`<Variables>`), referenced as
/// `{{Variables.name}}`. Host values passed to the engine override it.
class ReportVariable {
  /// ReportVariable API.
  ReportVariable({
    required this.name,
    this.value = '',
    this.type = ReportVariableType.text,
    this.description = '',
    this.format,
    this.prompt = false,
    this.required = false,
  });

  /// Name; dots group variables into folders, so `stats.sum` is referenced
  /// as `{{Variables.stats.sum}}` and shown under `stats` by designers.
  String name;

  static final RegExp _segment = RegExp(
    r'^[A-Za-z_\u0600-\u06FF][A-Za-z0-9_\u0600-\u06FF]*$',
  );

  /// Whether [name] is one identifier or several joined by dots
  /// (`total`, `stats.sum`).
  static bool isValidName(String name) =>
      name.isNotEmpty && name.split('.').every(_segment.hasMatch);

  /// Parts of [name] split at dots (`['stats', 'sum']`).
  List<String> get segments => name.split('.');

  /// Folder part of [name] (`stats` for `stats.sum`); empty at the top level.
  String get folder {
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(0, dot);
  }

  /// Last part of [name] (`sum` for `stats.sum`).
  String get leaf => name.substring(name.lastIndexOf('.') + 1);

  /// Value as authored (see [type]).
  String value;

  /// type API.
  ReportVariableType type;

  /// Shown to designers.
  String description;

  /// Format used when the designer inserts the variable (`currency:LYD`).
  String? format;

  /// The studio asks for a value before preview, print, and export.
  /// [value] stays the saved default and the design-time sample.
  bool prompt;

  /// A prompted run cannot continue while the answer is empty.
  bool required;

  /// Placeholder the designer inserts for this variable.
  String get placeholder {
    final String? f = format;
    return f == null || f.trim().isEmpty
        ? '{{Variables.$name}}'
        : '{{Variables.$name | ${f.trim()}}}';
  }

  /// Typed value of a literal variable; null for [ReportVariableType.expression],
  /// text with placeholders, or an invalid literal (see [error]).
  ReportValue? literal({DateTime? now}) {
    final String v = value.trim();
    switch (type) {
      case ReportVariableType.text:
        return value.contains('{{') ? null : ReportText(value);
      case ReportVariableType.number:
        final num? n = _number(v);
        return n == null ? null : ReportNumber(n);
      case ReportVariableType.boolean:
        return switch (v.toLowerCase()) {
          'true' || 'yes' || '1' || 'on' => const ReportBool(true),
          'false' || 'no' || '0' || 'off' || '' => const ReportBool(false),
          _ => null,
        };
      case ReportVariableType.date:
        final DateTime t = now ?? DateTime.now();
        return switch (v.toLowerCase()) {
          'today' => ReportDate(DateTime(t.year, t.month, t.day)),
          'now' => ReportDate(t),
          '' => ReportNull.instance,
          _ => switch (DateTime.tryParse(v)) {
            final DateTime d => ReportDate(d),
            null => null,
          },
        };
      case ReportVariableType.list:
        return ReportList(<ReportValue>[
          for (final String item in listItems)
            switch (_number(item)) {
              final num n => ReportNumber(n),
              null => ReportText(item),
            },
        ]);
      case ReportVariableType.expression:
        return null;
    }
  }

  /// Items of a [ReportVariableType.list] value.
  List<String> get listItems => <String>[
    for (final String item in value.split(';'))
      if (item.trim().isNotEmpty) item.trim(),
  ];

  /// Why the literal is invalid, or null.
  String? get error {
    final String v = value.trim();
    switch (type) {
      case ReportVariableType.number:
        return _number(v) == null ? '"$v" is not a number' : null;
      case ReportVariableType.boolean:
      case ReportVariableType.date:
        return literal() == null ? '"$v" is not a valid ${type.name}' : null;
      case ReportVariableType.expression:
        return v.isEmpty ? 'Expression is empty' : null;
      case ReportVariableType.text:
      case ReportVariableType.list:
        return null;
    }
  }

  static num? _number(String v) {
    final String s = v.replaceAll(',', '').replaceAll(' ', '');
    if (s.isEmpty) {
      return null;
    }
    return int.tryParse(s) ?? double.tryParse(s);
  }

  /// copy API.
  ReportVariable copy() => ReportVariable(
    name: name,
    value: value,
    type: type,
    description: description,
    format: format,
    prompt: prompt,
    required: required,
  );
}

var _elementSeq = 0;

String _nextElementId() => 'e${++_elementSeq}';

/// Base of every positioned element.
sealed class ReportElement {
  ReportElement({
    String? id,
    this.name,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.visibleWhen,
    Map<String, String>? extraAttributes,
  }) : id = id ?? _nextElementId(),
       extraAttributes = extraAttributes ?? <String, String>{};

  /// Stable runtime identity (selection, layout back-references).
  final String id;

  /// Optional author-facing name (`name="…"`).
  String? name;

  /// Left, relative to the page (or margin) — see [ReportCoordinateOrigin].
  double x;

  /// Top, relative to the band.
  double y;

  /// width API.
  double width;

  /// height API.
  double height;

  /// Expression; the element is skipped when it evaluates falsy.
  String? visibleWhen;

  /// Unrecognized attributes kept for round-trip.
  final Map<String, String> extraAttributes;

  /// type API.
  ReportElementType get type;

  /// Box in band coordinates.
  ReportRect get bounds => ReportRect(x, y, width, height);

  /// Deep copy. A fresh [id] unless [keepId].
  ReportElement clone({bool keepId = false});

  /// Short label for designers (`Text`, `Table`, …) plus [name].
  String get displayName {
    final String kind = switch (type) {
      ReportElementType.text => 'Text',
      ReportElementType.image => 'Image',
      ReportElementType.table => 'Table',
      ReportElementType.barcode => 'Barcode',
      ReportElementType.shape => 'Shape',
      ReportElementType.chart => 'Chart',
      ReportElementType.crosstab => 'Crosstab',
      ReportElementType.subreport => 'Subreport',
    };
    final String? n = name;
    return n == null || n.isEmpty ? kind : '$kind "$n"';
  }

  /// Base for generated names (`text1`, `table2`, …).
  String get namePrefix => switch (type) {
    ReportElementType.text => 'text',
    ReportElementType.image => 'image',
    ReportElementType.table => 'table',
    ReportElementType.barcode => 'barcode',
    ReportElementType.shape => 'shape',
    ReportElementType.chart => 'chart',
    ReportElementType.crosstab => 'crosstab',
    ReportElementType.subreport => 'subreport',
  };
}

/// One styled slice of a [ReportTextElement].
class ReportTextRun {
  /// ReportTextRun API.
  ReportTextRun({
    this.text = '',
    this.bold,
    this.italic,
    this.fontSize,
    this.color,
    this.underline,
    this.link,
  });

  /// Literal or `{{ }}` text.
  String text;

  /// bold API.
  bool? bold;

  /// italic API.
  bool? italic;

  /// Points. Null uses the element size.
  double? fontSize;

  /// color API.
  String? color;

  /// underline API.
  bool? underline;

  /// URI. Null is plain text.
  String? link;

  /// copy API.
  ReportTextRun copy() => ReportTextRun(
    text: text,
    bold: bold,
    italic: italic,
    fontSize: fontSize,
    color: color,
    underline: underline,
    link: link,
  );
}

/// Static or bound text.
class ReportTextElement extends ReportElement {
  /// ReportTextElement API.
  ReportTextElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.text = '',
    ReportTextStyle? style,
    this.align = ReportTextAlign.start,
    this.verticalAlign = ReportVerticalAlign.top,
    this.direction = ReportTextDirection.auto,
    this.canGrow = true,
    this.canShrink = false,
    this.wordWrap = true,
    this.format,
    this.padding = 0,
    this.borderColor,
    this.borderWidth = 0,
    this.background,
    this.lineSpacing = 1.0,
    List<ReportTextRun>? runs,
  }) : style = style ?? ReportTextStyle(),
       runs = runs ?? <ReportTextRun>[];

  /// Template text with `{{ }}` placeholders.
  String text;

  /// style API.
  final ReportTextStyle style;

  /// align API.
  ReportTextAlign align;

  /// verticalAlign API.
  ReportVerticalAlign verticalAlign;

  /// direction API.
  ReportTextDirection direction;

  /// Grow the band when wrapped text needs more height.
  bool canGrow;

  /// Shrink to content height (never below one line).
  bool canShrink;

  /// Wrap at the box width; when false lines are clipped.
  bool wordWrap;

  /// Format spec applied when [text] is a single placeholder.
  String? format;

  /// Inner padding, points.
  double padding;

  /// borderColor API.
  String? borderColor;

  /// borderWidth API.
  double borderWidth;

  /// background API.
  String? background;

  /// Line-height multiplier.
  double lineSpacing;

  /// Mixed slices. Empty means [text] uses [style] alone.
  final List<ReportTextRun> runs;

  /// [text], or the runs joined when they are present.
  String get plainText => runs.isEmpty
      ? text
      : runs.map((ReportTextRun r) => r.text).join();

  @override
  ReportElementType get type => ReportElementType.text;

  @override
  ReportTextElement clone({bool keepId = false}) => ReportTextElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    text: text,
    style: style.copy(),
    align: align,
    verticalAlign: verticalAlign,
    direction: direction,
    canGrow: canGrow,
    canShrink: canShrink,
    wordWrap: wordWrap,
    format: format,
    padding: padding,
    borderColor: borderColor,
    borderWidth: borderWidth,
    background: background,
    lineSpacing: lineSpacing,
    runs: <ReportTextRun>[for (final ReportTextRun r in runs) r.copy()],
  );
}

/// Picture from embedded bytes, a named resource, or a data binding.
class ReportImageElement extends ReportElement {
  /// ReportImageElement API.
  ReportImageElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.source = '',
    this.fit = ReportImageFit.contain,
    this.borderColor,
    this.borderWidth = 0,
    this.background,
  });

  /// `data:image/png;base64,…`, a resource name registered with the
  /// engine, raw base64, or a template such as `{{Data.logo}}`.
  String source;

  /// fit API.
  ReportImageFit fit;

  /// borderColor API.
  String? borderColor;

  /// borderWidth API.
  double borderWidth;

  /// background API.
  String? background;

  @override
  ReportElementType get type => ReportElementType.image;

  @override
  ReportImageElement clone({bool keepId = false}) => ReportImageElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    source: source,
    fit: fit,
    borderColor: borderColor,
    borderWidth: borderWidth,
    background: background,
  );
}

/// Code 128 or QR symbol.
class ReportBarcodeElement extends ReportElement {
  /// ReportBarcodeElement API.
  ReportBarcodeElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.data = '',
    this.symbology = ReportBarcodeType.code128,
    this.showText = true,
    this.color,
    this.background,
    this.fontSize = 8,
  });

  /// Template text encoded in the symbol.
  String data;

  /// symbology API.
  ReportBarcodeType symbology;

  /// Human-readable line under 1-D codes.
  bool showText;

  /// color API.
  String? color;

  /// background API.
  String? background;

  /// fontSize API.
  double fontSize;

  @override
  ReportElementType get type => ReportElementType.barcode;

  @override
  ReportBarcodeElement clone({bool keepId = false}) => ReportBarcodeElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    data: data,
    symbology: symbology,
    showText: showText,
    color: color,
    background: background,
    fontSize: fontSize,
  );
}

/// Line, rectangle, rounded rectangle, or ellipse.
///
/// A line runs from the top-left to the bottom-right of its box, or from the
/// bottom-left to the top-right when [rising] is set.
class ReportShapeElement extends ReportElement {
  /// ReportShapeElement API.
  ReportShapeElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.kind = ReportShapeKind.rectangle,
    this.strokeColor,
    this.strokeWidth = 0.75,
    this.fill,
    this.cornerRadius = 0,
    this.lineStyle = ReportLineStyle.solid,
    this.rising = false,
  });

  /// From explicit end points (`x1 y1 x2 y2`).
  factory ReportShapeElement.line({
    String? id,
    String? name,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    String? strokeColor,
    double strokeWidth = 0.75,
    ReportLineStyle lineStyle = ReportLineStyle.solid,
    String? visibleWhen,
    Map<String, String>? extraAttributes,
  }) {
    final double left = x1 < x2 ? x1 : x2;
    final double top = y1 < y2 ? y1 : y2;
    final bool rising = (x2 - x1) * (y2 - y1) < 0;
    return ReportShapeElement(
      id: id,
      name: name,
      x: left,
      y: top,
      width: (x2 - x1).abs(),
      height: (y2 - y1).abs(),
      kind: ReportShapeKind.line,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      lineStyle: lineStyle,
      rising: rising,
      visibleWhen: visibleWhen,
      extraAttributes: extraAttributes,
    );
  }

  /// kind API.
  ReportShapeKind kind;

  /// Stroke color (`color` attribute).
  String? strokeColor;

  /// Points.
  double strokeWidth;

  /// Fill color; null means no fill.
  String? fill;

  /// cornerRadius API.
  double cornerRadius;

  /// lineStyle API.
  ReportLineStyle lineStyle;

  /// Line direction flag (see class docs).
  bool rising;

  /// Line start point.
  ({double x, double y}) get start => (x: x, y: rising ? y + height : y);

  /// Line end point.
  ({double x, double y}) get end => (x: x + width, y: rising ? y : y + height);

  @override
  ReportElementType get type => ReportElementType.shape;

  @override
  ReportShapeElement clone({bool keepId = false}) => ReportShapeElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    kind: kind,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    fill: fill,
    cornerRadius: cornerRadius,
    lineStyle: lineStyle,
    rising: rising,
  );
}

/// `<Series name="…" value="…" color="…"/>` — one plotted measure.
class ReportChartSeries {
  /// ReportChartSeries API.
  ReportChartSeries({
    this.name = '',
    this.value = '',
    this.color,
    this.x,
    this.size,
    this.style = ReportSeriesStyle.column,
    this.secondary = false,
  });

  /// Legend label (template text, `{{ }}` allowed).
  String name;

  /// Expression evaluated per row (`Row.total`). The Y value of a point chart.
  String value;

  /// Hex color; null picks from the chart palette.
  String? color;

  /// X expression for [ReportChartType.scatter] and [ReportChartType.bubble].
  String? x;

  /// Size expression for [ReportChartType.bubble].
  String? size;

  /// Column, line, or area when the chart is a [ReportChartType.combo].
  ReportSeriesStyle style;

  /// Plot this series on the secondary value axis.
  bool secondary;

  /// Deep copy.
  ReportChartSeries copy() => ReportChartSeries(
    name: name,
    value: value,
    color: color,
    x: x,
    size: size,
    style: style,
    secondary: secondary,
  );
}

/// `<Point label="…" value="…" color="…"/>` — a static data point.
class ReportChartPoint {
  /// ReportChartPoint API.
  ReportChartPoint({
    this.label = '',
    this.value = '',
    this.color,
    this.x,
    this.size,
    this.total = false,
  });

  /// Category label (template text).
  String label;

  /// Expression or number literal. The Y value of a point chart.
  String value;

  /// Hex color (pie slices); null picks from the palette.
  String? color;

  /// X expression for a scatter or bubble point.
  String? x;

  /// Size expression for a bubble point.
  String? size;

  /// Waterfall bar drawn from zero (an absolute total) instead of a step.
  bool total;

  /// Deep copy.
  ReportChartPoint copy() => ReportChartPoint(
    label: label,
    value: value,
    color: color,
    x: x,
    size: size,
    total: total,
  );
}

/// Vector chart fed by a data set (one category per distinct
/// [category] value, one series per [series] entry) or by static [points].
///
/// Without [dataSet] the chart reads the rows of its band scope: all rows in
/// the report header / summary, the group's rows in group bands.
class ReportChartElement extends ReportElement {
  /// ReportChartElement API.
  ReportChartElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.chartType = ReportChartType.bar,
    this.title = '',
    this.dataSet,
    this.category,
    List<ReportChartSeries>? series,
    List<ReportChartPoint>? points,
    this.aggregate = ReportChartAggregate.sum,
    this.sortBy = ReportChartSort.none,
    this.descending = false,
    this.limit = 0,
    this.showLegend = true,
    this.showValues = false,
    this.showGrid = true,
    this.showAxes = true,
    this.valueFormat,
    this.fontSize = 7.5,
    this.fontFamily,
    this.bold = false,
    this.italic = false,
    this.textColor,
    this.background,
    this.borderColor,
    this.borderWidth = 0,
    List<String>? palette,
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
    this.increaseColor,
    this.decreaseColor,
    this.totalColor,
    this.shape = 'world',
    this.shapeKey,
    this.lowColor,
    this.highColor,
    this.emptyColor,
    this.showLabels = true,
    this.regionColor,
    this.labelField,
    ReportTextStyle? titleStyle,
    ReportTextStyle? labelStyle,
    ReportTextStyle? legendStyle,
  }) : series = series ?? <ReportChartSeries>[],
       points = points ?? <ReportChartPoint>[],
       palette = palette ?? <String>[],
       titleStyle = titleStyle ?? ReportTextStyle(),
       labelStyle = labelStyle ?? ReportTextStyle(),
       legendStyle = legendStyle ?? ReportTextStyle();

  /// Default slice / series colors (Office-like, print safe).
  static const List<String> defaultPalette = <String>[
    '#4472C4',
    '#ED7D31',
    '#70AD47',
    '#FFC000',
    '#5B9BD5',
    '#A5A5A5',
    '#264478',
    '#9E480E',
    '#43682B',
    '#997300',
  ];

  /// chartType API.
  ReportChartType chartType;

  /// Template text drawn above the plot.
  String title;

  /// Data set path (`Data.sales`); null uses the band scope rows.
  String? dataSet;

  /// Expression giving each row's category label (`Row.month`).
  String? category;

  /// Plotted measures (data-bound charts).
  final List<ReportChartSeries> series;

  /// Static points; used when [series] is empty.
  final List<ReportChartPoint> points;

  /// How rows of one category combine.
  ReportChartAggregate aggregate;

  /// Category order.
  ReportChartSort sortBy;

  /// Reverse [sortBy].
  bool descending;

  /// Keep only the first N categories after sorting (0 = all).
  int limit;

  /// showLegend API.
  bool showLegend;

  /// Value labels on bars, points, and slices.
  bool showValues;

  /// Horizontal value grid lines.
  bool showGrid;

  /// Axis lines and tick labels.
  bool showAxes;

  /// Format spec for value labels (`currency:LYD`, `n0`, `percent`).
  String? valueFormat;

  /// Label size, points. A chart title is drawn at 1.3×; a map uses this size
  /// for the title, the legend, and the region labels.
  double fontSize;

  /// Font family; null uses the template default.
  String? fontFamily;

  /// Bold title, legend, and region labels.
  bool bold;

  /// Italic title, legend, and region labels.
  bool italic;

  /// Label color; null uses the template text color.
  /// On a map, null keeps region labels in a color that contrasts with the fill.
  String? textColor;

  /// background API.
  String? background;

  /// borderColor API.
  String? borderColor;

  /// borderWidth API.
  double borderWidth;

  /// Custom colors; empty uses [defaultPalette].
  final List<String> palette;

  /// Extrusion depth in points for [ReportChartType.isExtruded] charts.
  double depth;

  /// Oblique angle in degrees (0 = flat side, 90 = straight up).
  double skew;

  /// Donut and gauge hole, as a fraction of the radius (0–0.9).
  double hole;

  /// Pie start in degrees. 0 is the right side; -90 is the top.
  double startAngle;

  /// Curve line, area, radar, and sparkline series.
  bool smooth;

  /// Point markers. Null follows the chart type.
  bool? showMarkers;

  /// Marker diameter in points.
  double markerSize;

  /// Stroke width of lines, in points.
  double lineWidth;

  /// Primary value-axis minimum. Null lets the scale choose.
  double? axisMin;

  /// Primary value-axis maximum. Null lets the scale choose.
  double? axisMax;

  /// Secondary value-axis minimum.
  double? axisMin2;

  /// Secondary value-axis maximum.
  double? axisMax2;

  /// Expression for the gauge or bullet target.
  String? target;

  /// Value labels are shares of the category (or of the pie).
  bool showPercent;

  /// The last waterfall category is an absolute total.
  bool lastIsTotal;

  /// Qualitative bands behind a gauge or bullet (0 hides them).
  int bands;

  /// Waterfall increase color. Null uses green.
  String? increaseColor;

  /// Waterfall decrease color. Null uses red.
  String? decreaseColor;

  /// Waterfall total color. Null uses slate.
  String? totalColor;

  /// Shape layer: `world` is the bundled country atlas; any other name is
  /// a layer embedded in the `.qrep` (`shapes/<name>.qmap`).
  String shape;

  /// Attribute used as the region key when a shapefile or GeoJSON is
  /// imported. Empty lets the importer choose a code or name column.
  String? shapeKey;

  /// Color of the smallest value. Null uses a light blue.
  String? lowColor;

  /// Color of the largest value. Null uses a deep blue.
  String? highColor;

  /// Color of a region with no value. Null uses gray.
  String? emptyColor;

  /// Draw the region name on areas wide enough to hold it.
  bool showLabels;

  /// Expression that paints each region, such as `Row.color`.
  /// A `#hex` value, a CSS name, or a palette name. Empty keeps the
  /// value gradient.
  String? regionColor;

  /// Attribute drawn as the region name. Empty uses the name stored
  /// with the shape, or the key when the file has no name column.
  String? labelField;

  /// Title font. Empty fields use the chart font.
  final ReportTextStyle titleStyle;

  /// Region-label font. An empty color keeps a color that contrasts with the fill.
  final ReportTextStyle labelStyle;

  /// Legend font (the low and high values under the scale).
  final ReportTextStyle legendStyle;

  /// Pie, donut, or an extruded form of either.
  bool get isRadial => chartType.isPie;

  /// Grid and axis toggles apply.
  bool get showsCartesianAxes =>
      !isRadial &&
      chartType != ReportChartType.gauge &&
      chartType != ReportChartType.sparkline &&
      chartType != ReportChartType.funnel &&
      !chartType.isShapeMap;

  /// Palette color [index] (wraps).
  String paletteColor(int index) {
    final List<String> p = palette.isEmpty ? defaultPalette : palette;
    return p[index % p.length];
  }

  @override
  ReportElementType get type => ReportElementType.chart;

  @override
  ReportChartElement clone({bool keepId = false}) => ReportChartElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    chartType: chartType,
    title: title,
    dataSet: dataSet,
    category: category,
    series: <ReportChartSeries>[
      for (final ReportChartSeries s in series) s.copy(),
    ],
    points: <ReportChartPoint>[
      for (final ReportChartPoint p in points) p.copy(),
    ],
    aggregate: aggregate,
    sortBy: sortBy,
    descending: descending,
    limit: limit,
    showLegend: showLegend,
    showValues: showValues,
    showGrid: showGrid,
    showAxes: showAxes,
    valueFormat: valueFormat,
    fontSize: fontSize,
    fontFamily: fontFamily,
    bold: bold,
    italic: italic,
    textColor: textColor,
    background: background,
    borderColor: borderColor,
    borderWidth: borderWidth,
    palette: List<String>.of(palette),
    depth: depth,
    skew: skew,
    hole: hole,
    startAngle: startAngle,
    smooth: smooth,
    showMarkers: showMarkers,
    markerSize: markerSize,
    lineWidth: lineWidth,
    axisMin: axisMin,
    axisMax: axisMax,
    axisMin2: axisMin2,
    axisMax2: axisMax2,
    target: target,
    showPercent: showPercent,
    lastIsTotal: lastIsTotal,
    bands: bands,
    increaseColor: increaseColor,
    decreaseColor: decreaseColor,
    totalColor: totalColor,
    shape: shape,
    shapeKey: shapeKey,
    lowColor: lowColor,
    highColor: highColor,
    emptyColor: emptyColor,
    showLabels: showLabels,
    regionColor: regionColor,
    labelField: labelField,
    titleStyle: titleStyle.copy(),
    labelStyle: labelStyle.copy(),
    legendStyle: legendStyle.copy(),
  );
}

/// `<Column width="…" header="…" align="…"/>`.
class ReportTableColumn {
  /// ReportTableColumn API.
  ReportTableColumn({
    this.width,
    this.header = '',
    this.align = ReportTextAlign.start,
    this.headerAlign,
  });

  /// Points; null shares the remaining table width.
  double? width;

  /// Header template text.
  String header;

  /// Body cell alignment.
  ReportTextAlign align;

  /// Header alignment (defaults to [align]).
  ReportTextAlign? headerAlign;

  /// copy API.
  ReportTableColumn copy() => ReportTableColumn(
    width: width,
    header: header,
    align: align,
    headerAlign: headerAlign,
  );
}

/// `<Cell field="item.code" format="…"/>` or `<Cell text="{{…}}"/>`.
class ReportTableCell {
  /// ReportTableCell API.
  ReportTableCell({
    this.field,
    this.text,
    this.format,
    this.bold,
    this.italic,
    this.color,
    this.background,
    this.align,
  });

  /// Expression evaluated per row (`item.total`, `item.qty * item.price`).
  String? field;

  /// Template text alternative to [field].
  String? text;

  /// format API.
  String? format;

  /// bold API.
  bool? bold;

  /// italic API.
  bool? italic;

  /// color API.
  String? color;

  /// background API.
  String? background;

  /// Overrides the column alignment.
  ReportTextAlign? align;

  /// Template text used for evaluation (`{{field}}` when [field] is set).
  String get template {
    final String? f = field;
    if (f != null && f.trim().isNotEmpty) {
      return '{{$f}}';
    }
    return text ?? '';
  }

  /// copy API.
  ReportTableCell copy() => ReportTableCell(
    field: field,
    text: text,
    format: format,
    bold: bold,
    italic: italic,
    color: color,
    background: background,
    align: align,
  );
}

/// Repeating grid bound to the detail data set.
class ReportTableElement extends ReportElement {
  /// ReportTableElement API.
  ReportTableElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    List<ReportTableColumn>? columns,
    List<ReportTableCell>? cells,
    List<ReportTableCell>? footerCells,
    this.showGrid = true,
    this.borderColor,
    this.borderWidth = 0.5,
    this.headerBackground,
    this.headerColor,
    this.headerBold = true,
    this.fontSize,
    this.headerFontSize,
    this.fontFamily,
    this.color,
    this.rowHeight,
    this.headerHeight,
    this.stripeColor,
    this.repeatHeader = true,
    this.showHeader = true,
    this.padding = 3,
    this.dataSet,
  }) : columns = columns ?? <ReportTableColumn>[],
       cells = cells ?? <ReportTableCell>[],
       footerCells = footerCells ?? <ReportTableCell>[];

  /// columns API.
  final List<ReportTableColumn> columns;

  /// Row template, one cell per column.
  final List<ReportTableCell> cells;

  /// Optional totals row printed after the last row.
  final List<ReportTableCell> footerCells;

  /// showGrid API.
  bool showGrid;

  /// borderColor API.
  String? borderColor;

  /// borderWidth API.
  double borderWidth;

  /// Header fill (defaults to the `primary` palette color).
  String? headerBackground;

  /// Header text color (defaults to white).
  String? headerColor;

  /// headerBold API.
  bool headerBold;

  /// Body font size.
  double? fontSize;

  /// headerFontSize API.
  double? headerFontSize;

  /// fontFamily API.
  String? fontFamily;

  /// Body text color.
  String? color;

  /// Minimum body row height; falls back to the band `rowHeight`.
  double? rowHeight;

  /// Header row height; falls back to [rowHeight].
  double? headerHeight;

  /// Fill for every second body row.
  String? stripeColor;

  /// Repeat the header at the top of continuation pages.
  bool repeatHeader;

  /// showHeader API.
  bool showHeader;

  /// Cell padding, points.
  double padding;

  /// Overrides the band data set.
  String? dataSet;

  @override
  ReportElementType get type => ReportElementType.table;

  /// Column widths fitted to [width] (explicit widths scaled when they do
  /// not add up; auto columns share what is left).
  List<double> resolvedColumnWidths() {
    if (columns.isEmpty) {
      return const <double>[];
    }
    var fixed = 0.0;
    var autos = 0;
    for (final ReportTableColumn c in columns) {
      final double? w = c.width;
      if (w == null || w <= 0) {
        autos++;
      } else {
        fixed += w;
      }
    }
    final double total = width > 0
        ? width
        : (fixed > 0 ? fixed : 100.0 * columns.length);
    if (autos == 0) {
      final double scale = fixed <= 0 ? 1 : total / fixed;
      return <double>[
        for (final ReportTableColumn c in columns) c.width! * scale,
      ];
    }
    final double rest = total - fixed;
    final double share = rest > 0 ? rest / autos : 30;
    return <double>[
      for (final ReportTableColumn c in columns)
        (c.width == null || c.width! <= 0) ? share : c.width!,
    ];
  }

  @override
  ReportTableElement clone({bool keepId = false}) => ReportTableElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    columns: <ReportTableColumn>[
      for (final ReportTableColumn c in columns) c.copy(),
    ],
    cells: <ReportTableCell>[for (final ReportTableCell c in cells) c.copy()],
    footerCells: <ReportTableCell>[
      for (final ReportTableCell c in footerCells) c.copy(),
    ],
    showGrid: showGrid,
    borderColor: borderColor,
    borderWidth: borderWidth,
    headerBackground: headerBackground,
    headerColor: headerColor,
    headerBold: headerBold,
    fontSize: fontSize,
    headerFontSize: headerFontSize,
    fontFamily: fontFamily,
    color: color,
    rowHeight: rowHeight,
    headerHeight: headerHeight,
    stripeColor: stripeColor,
    repeatHeader: repeatHeader,
    showHeader: showHeader,
    padding: padding,
    dataSet: dataSet,
  );
}

/// Pivot of one data set: one row per [rowField], one column per [columnField].
class ReportCrosstabElement extends ReportElement {
  /// ReportCrosstabElement API.
  ReportCrosstabElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.dataSet,
    this.rowField = '',
    this.columnField = '',
    this.valueField = '',
    this.aggregate = ReportChartAggregate.sum,
    this.maxColumns = 12,
    this.fontSize = 9,
    this.headerBold = true,
  });

  /// Data set path. Null uses the band's rows.
  String? dataSet;

  /// Expression for the row header (`item.branch`).
  String rowField;

  /// Expression for the column header (`item.month`).
  String columnField;

  /// Expression for the aggregated number (`item.amount`).
  String valueField;

  /// How values that share a row and column combine.
  ReportChartAggregate aggregate;

  /// Columns after this count are dropped and reported as a warning.
  int maxColumns;

  /// Body font size, points.
  double fontSize;

  /// headerBold API.
  bool headerBold;

  @override
  ReportElementType get type => ReportElementType.crosstab;

  @override
  ReportCrosstabElement clone({bool keepId = false}) => ReportCrosstabElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    dataSet: dataSet,
    rowField: rowField,
    columnField: columnField,
    valueField: valueField,
    aggregate: aggregate,
    maxColumns: maxColumns,
    fontSize: fontSize,
    headerBold: headerBold,
  );
}

/// Renders another template stored at `subreports/<name>.xml` in the package.
class ReportSubreportElement extends ReportElement {
  /// ReportSubreportElement API.
  ReportSubreportElement({
    super.id,
    super.name,
    super.x,
    super.y,
    super.width,
    super.height,
    super.visibleWhen,
    super.extraAttributes,
    this.templateName = '',
    this.dataSet,
  });

  /// Key under `subreports/` without the extension.
  String templateName;

  /// Expression for the child data. A list becomes `{items: …}`.
  /// Null passes the current row, or the parent data when there is no row.
  String? dataSet;

  @override
  ReportElementType get type => ReportElementType.subreport;

  @override
  ReportSubreportElement clone({bool keepId = false}) => ReportSubreportElement(
    id: keepId ? id : null,
    name: name,
    x: x,
    y: y,
    width: width,
    height: height,
    visibleWhen: visibleWhen,
    extraAttributes: Map<String, String>.of(extraAttributes),
    templateName: templateName,
    dataSet: dataSet,
  );
}

/// One data region: optional group header, a detail band, optional group footer.
class ReportSection {
  /// ReportSection API.
  const ReportSection({
    required this.index,
    this.groupHeader,
    this.detail,
    this.groupFooter,
  });

  /// Zero-based section, matching [ReportBand.section].
  final int index;

  /// groupHeader API.
  final ReportBand? groupHeader;

  /// detail API.
  final ReportBand? detail;

  /// groupFooter API.
  final ReportBand? groupFooter;
}

/// One band section with its elements.
class ReportBand {
  /// ReportBand API.
  ReportBand({
    required this.kind,
    this.height = 0,
    this.dataSet,
    this.rowHeight,
    this.groupBy,
    this.sortBy,
    this.sortDescending = false,
    this.filter,
    this.printOnFirstPage = true,
    this.printOnLastPage = true,
    this.newPageBefore = false,
    this.newPageAfter = false,
    this.keepTogether = false,
    this.repeatOnEveryPage = false,
    this.background,
    this.visibleWhen,
    this.section = 0,
    List<ReportElement>? elements,
    Map<String, String>? extraAttributes,
  }) : elements = elements ?? <ReportElement>[],
       extraAttributes = extraAttributes ?? <String, String>{};

  /// kind API.
  final ReportBandKind kind;

  /// Design height, points.
  double height;

  /// Detail: data set path (`items`, `Data.invoice.items`).
  String? dataSet;

  /// Detail: row height for repeated rows / table body rows.
  double? rowHeight;

  /// Detail or group header: grouping key expression (`item.category`).
  String? groupBy;

  /// Detail: sort key expression.
  String? sortBy;

  /// sortDescending API.
  bool sortDescending;

  /// Detail: row filter expression.
  String? filter;

  /// Page header/footer: print on page 1.
  bool printOnFirstPage;

  /// Page footer: print on the last page.
  bool printOnLastPage;

  /// Start a new page before this band when the current page already has
  /// content: a group header, the report summary, and each free-form detail
  /// row. A detail band that contains a table keeps flowing its rows.
  bool newPageBefore;

  /// Start a new page after this band: the report header, a group footer
  /// while another group follows, and each free-form detail row while
  /// another row follows.
  bool newPageAfter;

  /// Do not split this band (or a group header from its first row).
  bool keepTogether;

  /// Group header: repeat at the top of continuation pages.
  bool repeatOnEveryPage;

  /// background API.
  String? background;

  /// visibleWhen API.
  String? visibleWhen;

  /// Which data section this band belongs to. Page and report bands stay 0.
  /// A second `<Section>` is 1, so a report can print two detail tables.
  int section;

  /// elements API.
  final List<ReportElement> elements;

  /// extraAttributes API.
  final Map<String, String> extraAttributes;

  /// Design height of the band: the larger of [height] and its contents.
  double get designHeight {
    var h = height;
    for (final ReportElement e in elements) {
      final double bottom = e.y + e.height;
      if (bottom > h) {
        h = bottom;
      }
    }
    return h;
  }

  /// copy API.
  ReportBand copy({bool keepIds = true}) => ReportBand(
    kind: kind,
    height: height,
    dataSet: dataSet,
    rowHeight: rowHeight,
    groupBy: groupBy,
    sortBy: sortBy,
    sortDescending: sortDescending,
    filter: filter,
    printOnFirstPage: printOnFirstPage,
    printOnLastPage: printOnLastPage,
    newPageBefore: newPageBefore,
    newPageAfter: newPageAfter,
    keepTogether: keepTogether,
    repeatOnEveryPage: repeatOnEveryPage,
    background: background,
    visibleWhen: visibleWhen,
    section: section,
    elements: <ReportElement>[
      for (final ReportElement e in elements) e.clone(keepId: keepIds),
    ],
    extraAttributes: Map<String, String>.of(extraAttributes),
  );
}

/// A complete report template (`<QudsReport>`).
class ReportTemplate {
  /// ReportTemplate API.
  ReportTemplate({
    this.name = 'Report',
    this.isRtl = false,
    this.pageSize = ReportPageSize.a4,
    this.orientation = ReportOrientation.portrait,
    this.defaultFont = '',
    this.defaultFontSize = 10,
    this.unit = ReportUnit.mm,
    this.coordinateOrigin = ReportCoordinateOrigin.page,
    this.mirrorRtl = true,
    ReportMargins? margins,
    Map<String, String>? colors,
    this.formats = const ReportFormatDefaults(),
    List<ReportVariable>? variables,
    List<ReportBand>? bands,
    ReportDataSchema? dataSchema,
    Map<String, String>? extraAttributes,
    Map<String, String>? subreports,
  }) : margins = margins ?? ReportMargins(),
       colors = colors ?? <String, String>{},
       variables = variables ?? <ReportVariable>[],
       bands = bands ?? <ReportBand>[],
       dataSchema = dataSchema ?? ReportDataSchema(),
       extraAttributes = extraAttributes ?? <String, String>{},
       subreports = subreports ?? <String, String>{};

  /// name API.
  String name;

  /// Right-to-left layout default (text direction, `start` alignment,
  /// table column order).
  bool isRtl;

  /// pageSize API.
  ReportPageSize pageSize;

  /// orientation API.
  ReportOrientation orientation;

  /// Default font family (resolved through the engine font registry).
  String defaultFont;

  /// Points.
  double defaultFontSize;

  /// Unit used for bare numbers and when writing XML.
  ReportUnit unit;

  /// coordinateOrigin API.
  ReportCoordinateOrigin coordinateOrigin;

  /// Mirror element positions in RTL reports: `x` is measured from the right
  /// page edge (or right margin), so a template authored left-to-right reads
  /// correctly right-to-left. Explicit `left` / `right` alignments are kept;
  /// `start` / `end` follow the text direction.
  bool mirrorRtl;

  /// margins API.
  final ReportMargins margins;

  /// Palette (`primary` → `#1F4E78`).
  final Map<String, String> colors;

  /// Date / number display defaults.
  ReportFormatDefaults formats;

  /// variables API.
  final List<ReportVariable> variables;

  /// Bands in canonical order.
  final List<ReportBand> bands;

  /// Data tables, columns, and fields the report expects (`<DataSchema>`).
  ReportDataSchema dataSchema;

  /// extraAttributes API.
  final Map<String, String> extraAttributes;

  /// Child templates keyed by name (`subreports/<name>.xml` in the package).
  final Map<String, String> subreports;

  /// Oriented page width, points.
  double get pageWidth => orientation == ReportOrientation.landscape
      ? (pageSize.width > pageSize.height ? pageSize.width : pageSize.height)
      : (pageSize.width < pageSize.height ? pageSize.width : pageSize.height);

  /// Oriented page height, points.
  double get pageHeight => orientation == ReportOrientation.landscape
      ? (pageSize.width > pageSize.height ? pageSize.height : pageSize.width)
      : (pageSize.width < pageSize.height ? pageSize.height : pageSize.width);

  /// True when element `x` is measured from the right edge ([isRtl] and
  /// [mirrorRtl]).
  bool get mirrored => isRtl && mirrorRtl;

  /// Physical left edge on the page of an element at [x] with [width].
  double elementLeft(double x, double width) {
    final bool margin = coordinateOrigin == ReportCoordinateOrigin.margin;
    if (mirrored) {
      return pageWidth - (margin ? margins.right : 0) - x - width;
    }
    return (margin ? margins.left : 0) + x;
  }

  /// Template `x` for an element whose physical left edge is [left].
  double elementX(double left, double width) {
    final bool margin = coordinateOrigin == ReportCoordinateOrigin.margin;
    if (mirrored) {
      return pageWidth - (margin ? margins.right : 0) - left - width;
    }
    return left - (margin ? margins.left : 0);
  }

  /// Width from [x] to the far page margin.
  double remainingWidth(double x) {
    final bool margin = coordinateOrigin == ReportCoordinateOrigin.margin;
    if (margin) {
      return contentWidth - x;
    }
    return pageWidth - (mirrored ? margins.left : margins.right) - x;
  }

  /// Printable width between the side margins.
  double get contentWidth => pageWidth - margins.left - margins.right;

  /// Band of [kind], or null.
  ReportBand? band(ReportBandKind kind) {
    for (final ReportBand b in bands) {
      if (b.kind == kind) {
        return b;
      }
    }
    return null;
  }

  /// Existing band of [kind] or a new one inserted in canonical order.
  ReportBand ensureBand(ReportBandKind kind, {double height = 20}) {
    final ReportBand? existing = band(kind);
    if (existing != null) {
      return existing;
    }
    final ReportBand created = ReportBand(kind: kind, height: height);
    var at = bands.length;
    for (int i = 0; i < bands.length; i++) {
      if (bands[i].kind.index > kind.index) {
        at = i;
        break;
      }
    }
    bands.insert(at, created);
    return created;
  }

  /// Sorts bands into canonical order. Data bands stay grouped by [ReportBand.section].
  void sortBands() => bands.sort((ReportBand a, ReportBand b) {
    final int ao = _bandOrder(a);
    final int bo = _bandOrder(b);
    return ao == bo ? a.section - b.section : ao - bo;
  });

  static int _bandOrder(ReportBand b) => switch (b.kind) {
    ReportBandKind.reportHeader => 0,
    ReportBandKind.pageHeader => 1,
    ReportBandKind.groupHeader => 100 + b.section * 10,
    ReportBandKind.detail => 101 + b.section * 10,
    ReportBandKind.groupFooter => 102 + b.section * 10,
    ReportBandKind.pageFooter => 100000,
    ReportBandKind.reportSummary => 100001,
  };

  /// The first detail band, if any.
  ReportBand? get detail => band(ReportBandKind.detail);

  /// Detail regions in section order. A template with one detail is one section.
  List<ReportSection> get sections {
    final Set<int> ids = <int>{};
    for (final ReportBand b in bands) {
      switch (b.kind) {
        case ReportBandKind.groupHeader:
        case ReportBandKind.detail:
        case ReportBandKind.groupFooter:
          ids.add(b.section);
        case ReportBandKind.reportHeader:
        case ReportBandKind.pageHeader:
        case ReportBandKind.pageFooter:
        case ReportBandKind.reportSummary:
          break;
      }
    }
    if (ids.isEmpty) {
      return <ReportSection>[];
    }
    final List<int> sorted = ids.toList()..sort();
    return <ReportSection>[
      for (final int i in sorted)
        ReportSection(
          index: i,
          groupHeader: bandIn(ReportBandKind.groupHeader, i),
          detail: bandIn(ReportBandKind.detail, i),
          groupFooter: bandIn(ReportBandKind.groupFooter, i),
        ),
    ];
  }

  /// Band of [kind] inside [section], or null.
  ReportBand? bandIn(ReportBandKind kind, int section) {
    for (final ReportBand b in bands) {
      if (b.kind == kind && b.section == section) {
        return b;
      }
    }
    return null;
  }

  /// Every element with its band.
  Iterable<(ReportBand, ReportElement)> get allElements sync* {
    for (final ReportBand b in bands) {
      for (final ReportElement e in b.elements) {
        yield (b, e);
      }
    }
  }

  /// Element by [ReportElement.id], with its band.
  (ReportBand, ReportElement)? findElement(String id) {
    for (final (ReportBand, ReportElement) pair in allElements) {
      if (pair.$2.id == id) {
        return pair;
      }
    }
    return null;
  }

  /// Whether [name] can address an element from code: a letter (Latin,
  /// Arabic, …) or `_` followed by letters, digits, or `_`.
  static bool isValidElementName(String name) => ReportData.isValidName(name);

  /// Element whose [ReportElement.name] is [name] (case-insensitive), with
  /// its band.
  (ReportBand, ReportElement)? elementNamed(String name) {
    final String lower = name.trim().toLowerCase();
    if (lower.isEmpty) {
      return null;
    }
    for (final (ReportBand, ReportElement) pair in allElements) {
      if (pair.$2.name?.toLowerCase() == lower) {
        return pair;
      }
    }
    return null;
  }

  /// Names used by more than one element (case-insensitive), lower-cased.
  Set<String> get duplicateElementNames {
    final Set<String> seen = <String>{};
    final Set<String> dupes = <String>{};
    for (final (ReportBand _, ReportElement e) in allElements) {
      final String? n = e.name?.trim().toLowerCase();
      if (n != null && n.isNotEmpty && !seen.add(n)) {
        dupes.add(n);
      }
    }
    return dupes;
  }

  /// [base] followed by the first number no other element uses (`text3`).
  /// [except] is ignored when checking (the element being renamed).
  String uniqueElementName(String base, {ReportElement? except}) {
    final Set<String> taken = <String>{
      for (final (ReportBand _, ReportElement e) in allElements)
        if (!identical(e, except) && e.name != null) e.name!.toLowerCase(),
    };
    var stem = base.replaceAll(RegExp(r'[^A-Za-z0-9_\u00C0-\uFFFF]'), '');
    if (stem.isEmpty || RegExp('^[0-9]').hasMatch(stem)) {
      stem = 'element$stem';
    }
    stem = stem.replaceFirst(RegExp(r'\d+$'), '');
    for (int i = 1; ; i++) {
      final candidate = '$stem$i';
      if (!taken.contains(candidate.toLowerCase())) {
        return candidate;
      }
    }
  }

  /// Names every unnamed element and renames later duplicates so each
  /// element can be addressed from code. Returns the renamed elements.
  List<ReportElement> assignElementNames() {
    final List<ReportElement> changed = <ReportElement>[];
    final Set<String> seen = <String>{};
    final List<ReportElement> pending = <ReportElement>[];
    for (final (ReportBand _, ReportElement e) in allElements) {
      final String? n = e.name?.trim();
      if (n == null || n.isEmpty || !seen.add(n.toLowerCase())) {
        pending.add(e);
      }
    }
    for (final ReportElement e in pending) {
      e.name = null;
    }
    for (final ReportElement e in pending) {
      e.name = uniqueElementName(e.namePrefix, except: e);
      changed.add(e);
    }
    return changed;
  }

  /// Resolves a raw color (palette name, hex, CSS name) or [fallback].
  ReportColor resolveColor(String? raw, ReportColor fallback) {
    if (raw == null || raw.trim().isEmpty) {
      return fallback;
    }
    final String key = raw.trim();
    String? mapped = colors[key];
    if (mapped == null) {
      final String lower = key.toLowerCase();
      for (final MapEntry<String, String> e in colors.entries) {
        if (e.key.toLowerCase() == lower) {
          mapped = e.value;
          break;
        }
      }
    }
    return ReportColor.tryParse(mapped ?? key) ?? fallback;
  }

  /// Palette `text` color or black.
  ReportColor get textColor => resolveColor(colors['text'], ReportColor.black);

  /// Palette `primary` color or a dark blue.
  ReportColor get primaryColor =>
      resolveColor(colors['primary'], const ReportColor(0xFF1F4E78));

  /// Deep copy (element ids preserved unless [keepIds] is false).
  ReportTemplate copy({bool keepIds = true}) => ReportTemplate(
    name: name,
    isRtl: isRtl,
    pageSize: pageSize,
    orientation: orientation,
    defaultFont: defaultFont,
    defaultFontSize: defaultFontSize,
    unit: unit,
    coordinateOrigin: coordinateOrigin,
    mirrorRtl: mirrorRtl,
    margins: margins.copy(),
    colors: Map<String, String>.of(colors),
    formats: formats,
    variables: <ReportVariable>[
      for (final ReportVariable v in variables) v.copy(),
    ],
    bands: <ReportBand>[
      for (final ReportBand b in bands) b.copy(keepIds: keepIds),
    ],
    dataSchema: dataSchema.copy(),
    extraAttributes: Map<String, String>.of(extraAttributes),
    subreports: Map<String, String>.of(subreports),
  );
}
