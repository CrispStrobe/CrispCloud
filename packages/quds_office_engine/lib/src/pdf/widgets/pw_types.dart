/// Constraint-layout primitives for the PDF widget tree (pure Dart).
library;

/// How text is aligned.
enum TextAlign { left, right, start, end, center, justify }

/// How [Text] treats a line that does not fit [Text.maxLines].
enum TextOverflow { clip, ellipsis, visible }

/// Reading direction.
enum TextDirection { ltr, rtl }

/// Page rotation hint.
enum PageOrientation { natural, landscape, portrait }

/// Main-axis direction.
enum Axis { horizontal, vertical }

/// How a flex child is sized.
enum FlexFit { tight, loose }

/// Image fit.
enum BoxFit { contain, cover, fill, fitWidth, fitHeight, none, scaleDown }

/// Decoration shape.
enum BoxShape { rectangle, circle }

/// How children sit on a [Row] / [Column].
enum MainAxisAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// Cross-axis alignment for [Row] / [Column].
enum CrossAxisAlignment { start, end, center, stretch }

/// Font weight.
enum FontWeight { normal, bold }

/// Font style.
enum FontStyle { normal, italic }

/// 2D size in typographic points.
class PwSize {
  /// PwSize API.
  const PwSize(this.width, this.height);

  /// zero API.
  static const PwSize zero = PwSize(0, 0);

  /// width API.
  final double width;

  /// height API.
  final double height;
}

/// Top-left offset in page space.
class PwOffset {
  /// PwOffset API.
  const PwOffset(this.dx, this.dy);

  /// zero API.
  static const PwOffset zero = PwOffset(0, 0);

  /// dx API.
  final double dx;

  /// dy API.
  final double dy;

  /// translate API.
  PwOffset translate(double x, double y) => PwOffset(dx + x, dy + y);
}

/// Flutter-style box constraints.
class BoxConstraints {
  /// BoxConstraints API.
  const BoxConstraints({
    this.minWidth = 0,
    this.maxWidth = double.infinity,
    this.minHeight = 0,
    this.maxHeight = double.infinity,
  });

  /// tight API.
  BoxConstraints.tight(PwSize size)
    : minWidth = size.width,
      maxWidth = size.width,
      minHeight = size.height,
      maxHeight = size.height;

  /// Tight on the axes that are specified (same idea as Flutter / package:pdf).
  factory BoxConstraints.tightFor({double? width, double? height}) {
    return BoxConstraints(
      minWidth: width ?? 0,
      maxWidth: width ?? double.infinity,
      minHeight: height ?? 0,
      maxHeight: height ?? double.infinity,
    );
  }

  /// expand API.
  factory BoxConstraints.expand({double? width, double? height}) {
    return BoxConstraints(
      minWidth: width ?? 0,
      maxWidth: width ?? double.infinity,
      minHeight: height ?? 0,
      maxHeight: height ?? double.infinity,
    );
  }

  /// True when min and max are equal on both axes.
  bool get isTight => minWidth >= maxWidth && minHeight >= maxHeight;

  /// loose API.
  BoxConstraints.loose(PwSize size)
    : minWidth = 0,
      maxWidth = size.width,
      minHeight = 0,
      maxHeight = size.height;

  /// minWidth API.
  final double minWidth;

  /// maxWidth API.
  final double maxWidth;

  /// minHeight API.
  final double minHeight;

  /// maxHeight API.
  final double maxHeight;

  /// hasBoundedWidth API.
  bool get hasBoundedWidth => maxWidth.isFinite;

  /// hasBoundedHeight API.
  bool get hasBoundedHeight => maxHeight.isFinite;

  /// constrain API.
  PwSize constrain(PwSize size) => PwSize(
    size.width.clamp(minWidth, maxWidth),
    size.height.clamp(minHeight, maxHeight),
  );

  /// constrainWidth API.
  double constrainWidth([double width = double.infinity]) =>
      width.clamp(minWidth, maxWidth);

  /// constrainHeight API.
  double constrainHeight([double height = double.infinity]) =>
      height.clamp(minHeight, maxHeight);

  /// deflate API.
  BoxConstraints deflate(EdgeInsets insets) {
    final double h = insets.horizontal;
    final double v = insets.vertical;
    return BoxConstraints(
      minWidth: (minWidth - h).clamp(0, double.infinity),
      maxWidth: (maxWidth - h).clamp(0, double.infinity),
      minHeight: (minHeight - v).clamp(0, double.infinity),
      maxHeight: (maxHeight - v).clamp(0, double.infinity),
    );
  }

  /// tighten API.
  BoxConstraints tighten({double? width, double? height}) {
    return BoxConstraints(
      minWidth: width == null ? minWidth : width.clamp(minWidth, maxWidth),
      maxWidth: width == null ? maxWidth : width.clamp(minWidth, maxWidth),
      minHeight: height == null ? minHeight : height.clamp(minHeight, maxHeight),
      maxHeight: height == null ? maxHeight : height.clamp(minHeight, maxHeight),
    );
  }

  /// loosen API.
  BoxConstraints loosen() => BoxConstraints(
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}

/// Page size in typographic points.
class PdfPageFormat {
  /// PdfPageFormat API.
  const PdfPageFormat(
    this.width,
    this.height, {
    double marginTop = 0,
    double marginBottom = 0,
    double marginLeft = 0,
    double marginRight = 0,
    double? marginAll,
  }) : marginTop = marginAll ?? marginTop,
       marginBottom = marginAll ?? marginBottom,
       marginLeft = marginAll ?? marginLeft,
       marginRight = marginAll ?? marginRight;

  /// a3 API.
  static const PdfPageFormat a3 = PdfPageFormat(
    29.7 * cm,
    42 * cm,
    marginAll: 2.0 * cm,
  );

  /// a4 API.
  static const PdfPageFormat a4 = PdfPageFormat(
    21.0 * cm,
    29.7 * cm,
    marginAll: 2.0 * cm,
  );

  /// standard API.
  static const PdfPageFormat standard = a4;

  /// a5 API.
  static const PdfPageFormat a5 = PdfPageFormat(
    14.8 * cm,
    21.0 * cm,
    marginAll: 1.5 * cm,
  );

  /// letter API.
  static const PdfPageFormat letter = PdfPageFormat(
    8.5 * inch,
    11.0 * inch,
    marginAll: inch,
  );

  /// legal API.
  static const PdfPageFormat legal = PdfPageFormat(
    8.5 * inch,
    14.0 * inch,
    marginAll: inch,
  );

  /// point API.
  static const double point = 1;

  /// inch API.
  static const double inch = 72;

  /// cm API.
  static const double cm = inch / 2.54;

  /// mm API.
  static const double mm = inch / 25.4;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// marginTop API.
  final double marginTop;

  /// marginBottom API.
  final double marginBottom;

  /// marginLeft API.
  final double marginLeft;

  /// marginRight API.
  final double marginRight;

  /// landscape API.
  PdfPageFormat get landscape => width >= height
      ? this
      : PdfPageFormat(
          height,
          width,
          marginTop: marginLeft,
          marginBottom: marginRight,
          marginLeft: marginBottom,
          marginRight: marginTop,
        );

  /// apply API.
  PdfPageFormat apply(PageOrientation orientation) {
    return switch (orientation) {
      PageOrientation.landscape => landscape,
      PageOrientation.portrait => width <= height
          ? this
          : PdfPageFormat(
              height,
              width,
              marginAll: marginLeft,
            ),
      PageOrientation.natural => this,
    };
  }

  /// contentWidth API.
  double get contentWidth =>
      (width - marginLeft - marginRight).clamp(1, width);

  /// contentHeight API.
  double get contentHeight =>
      (height - marginTop - marginBottom).clamp(1, height);
}

/// Alias used in some samples.
typedef PageFormat = PdfPageFormat;

/// Physical or start/end insets. Resolve with [resolve] before painting.
abstract class EdgeInsetsGeometry {
  /// EdgeInsetsGeometry API.
  const EdgeInsetsGeometry();

  /// Physical insets for [direction].
  EdgeInsets resolve(TextDirection direction);
}

/// Insets around a child.
class EdgeInsets extends EdgeInsetsGeometry {
  /// EdgeInsets API.
  const EdgeInsets.fromLTRB(this.left, this.top, this.right, this.bottom);

  /// all API.
  const EdgeInsets.all(double value)
    : left = value,
      top = value,
      right = value,
      bottom = value;

  /// only API.
  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// symmetric API.
  const EdgeInsets.symmetric({double vertical = 0, double horizontal = 0})
    : left = horizontal,
      right = horizontal,
      top = vertical,
      bottom = vertical;

  /// zero API.
  static const EdgeInsets zero = EdgeInsets.all(0);

  /// left API.
  final double left;

  /// top API.
  final double top;

  /// right API.
  final double right;

  /// bottom API.
  final double bottom;

  /// horizontal API.
  double get horizontal => left + right;

  /// vertical API.
  double get vertical => top + bottom;

  @override
  EdgeInsets resolve(TextDirection direction) => this;
}

/// Insets that flip with [TextDirection]. [start] is left in LTR, right in RTL.
class EdgeInsetsDirectional extends EdgeInsetsGeometry {
  /// EdgeInsetsDirectional API.
  const EdgeInsetsDirectional.fromSTEB(
    this.start,
    this.top,
    this.end,
    this.bottom,
  );

  /// all API.
  const EdgeInsetsDirectional.all(double value)
    : start = value,
      top = value,
      end = value,
      bottom = value;

  /// only API.
  const EdgeInsetsDirectional.only({
    this.start = 0,
    this.top = 0,
    this.end = 0,
    this.bottom = 0,
  });

  /// zero API.
  static const EdgeInsetsDirectional zero = EdgeInsetsDirectional.all(0);

  /// start API.
  final double start;

  /// top API.
  final double top;

  /// end API.
  final double end;

  /// bottom API.
  final double bottom;

  @override
  EdgeInsets resolve(TextDirection direction) {
    if (direction == TextDirection.rtl) {
      return EdgeInsets.fromLTRB(end, top, start, bottom);
    }
    return EdgeInsets.fromLTRB(start, top, end, bottom);
  }
}

/// Physical or start/end alignment. Resolve before [Alignment.alongOffset].
abstract class AlignmentGeometry {
  /// AlignmentGeometry API.
  const AlignmentGeometry();

  /// Physical alignment for [direction].
  Alignment resolve(TextDirection direction);
}

/// Flutter alignment: x/y in `-1..1` (top-left is `-1,-1`).
class Alignment extends AlignmentGeometry {
  /// Alignment API.
  const Alignment(this.x, this.y);

  /// x API.
  final double x;

  /// y API.
  final double y;

  /// topLeft API.
  static const Alignment topLeft = Alignment(-1, -1);

  /// topCenter API.
  static const Alignment topCenter = Alignment(0, -1);

  /// topRight API.
  static const Alignment topRight = Alignment(1, -1);

  /// centerLeft API.
  static const Alignment centerLeft = Alignment(-1, 0);

  /// center API.
  static const Alignment center = Alignment(0, 0);

  /// centerRight API.
  static const Alignment centerRight = Alignment(1, 0);

  /// bottomLeft API.
  static const Alignment bottomLeft = Alignment(-1, 1);

  /// bottomCenter API.
  static const Alignment bottomCenter = Alignment(0, 1);

  /// bottomRight API.
  static const Alignment bottomRight = Alignment(1, 1);

  /// alongOffset API.
  PwOffset alongOffset(PwSize parent, PwSize child) {
    final double dx = (parent.width - child.width) * ((x + 1) / 2);
    final double dy = (parent.height - child.height) * ((y + 1) / 2);
    return PwOffset(dx, dy);
  }

  @override
  Alignment resolve(TextDirection direction) => this;
}

/// Alignment that flips with [TextDirection]. [start] is `-1` at the start edge.
class AlignmentDirectional extends AlignmentGeometry {
  /// AlignmentDirectional API.
  const AlignmentDirectional(this.start, this.y);

  /// start API. `-1` is the start edge, `1` the end edge.
  final double start;

  /// y API.
  final double y;

  /// topStart API.
  static const AlignmentDirectional topStart = AlignmentDirectional(-1, -1);

  /// topCenter API.
  static const AlignmentDirectional topCenter = AlignmentDirectional(0, -1);

  /// topEnd API.
  static const AlignmentDirectional topEnd = AlignmentDirectional(1, -1);

  /// centerStart API.
  static const AlignmentDirectional centerStart = AlignmentDirectional(-1, 0);

  /// center API.
  static const AlignmentDirectional center = AlignmentDirectional(0, 0);

  /// centerEnd API.
  static const AlignmentDirectional centerEnd = AlignmentDirectional(1, 0);

  /// bottomStart API.
  static const AlignmentDirectional bottomStart = AlignmentDirectional(-1, 1);

  /// bottomCenter API.
  static const AlignmentDirectional bottomCenter = AlignmentDirectional(0, 1);

  /// bottomEnd API.
  static const AlignmentDirectional bottomEnd = AlignmentDirectional(1, 1);

  @override
  Alignment resolve(TextDirection direction) {
    final double x = direction == TextDirection.rtl ? -start : start;
    return Alignment(x, y);
  }
}

/// One side of a border.
class BorderSide {
  /// BorderSide API.
  const BorderSide({this.color = '000000', this.width = 1});

  /// none API.
  static const BorderSide none = BorderSide(width: 0);

  /// color API.
  final String color;

  /// width API.
  final double width;
}

/// Box border.
class Border {
  /// Border API.
  const Border({
    this.top = BorderSide.none,
    this.right = BorderSide.none,
    this.bottom = BorderSide.none,
    this.left = BorderSide.none,
  });

  /// all API.
  factory Border.all({String color = '000000', double width = 1}) {
    final BorderSide side = BorderSide(color: color, width: width);
    return Border(top: side, right: side, bottom: side, left: side);
  }

  /// top API.
  final BorderSide top;

  /// right API.
  final BorderSide right;

  /// bottom API.
  final BorderSide bottom;

  /// left API.
  final BorderSide left;
}

/// Axis-aligned color blend (painted as strips — no PDF shading object).
class LinearGradient {
  /// LinearGradient API.
  const LinearGradient({
    required this.colors,
    this.vertical = true,
  });

  /// Two or more RRGGBB stops, evenly spaced.
  final List<String> colors;

  /// Top→bottom when true, left→right when false.
  final bool vertical;
}

/// Box decoration (fill + stroke).
class BoxDecoration {
  /// BoxDecoration API.
  const BoxDecoration({
    this.color,
    this.gradient,
    this.border,
    this.borderRadius = 0,
    this.shape = BoxShape.rectangle,
  });

  /// color API.
  final String? color;

  /// gradient API. Painted instead of [color] when set.
  final LinearGradient? gradient;

  /// border API.
  final Border? border;

  /// borderRadius API.
  final double borderRadius;

  /// shape API.
  final BoxShape shape;
}
