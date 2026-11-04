// WordprocessingML paragraph / run / table properties.
// Measurements are stored in points (1 twip = 1/20 pt, w:sz is half-points).

/// Enum WmlJustification.
enum WmlJustification { left, right, center, justify, distributed }

/// Enum WmlUnderline.
enum WmlUnderline { none, single, double, dotted, wavy }

/// Enum WmlLineSpacingRule.
enum WmlLineSpacingRule { auto, exact, atLeast }

/// Enum WmlVertAlign.
enum WmlVertAlign { baseline, superscript, subscript }

/// Word-like script metrics: about two-thirds size, raised or lowered.
extension WmlVertAlignMetrics on WmlVertAlign {
  /// fontScale API.
  double get fontScale => switch (this) {
    WmlVertAlign.baseline => 1,
    WmlVertAlign.superscript || WmlVertAlign.subscript => 0.65,
  };

  /// baselineShift API.
  double baselineShift(double baseFontSize) => switch (this) {
    WmlVertAlign.superscript => -baseFontSize * 0.35,
    WmlVertAlign.subscript => baseFontSize * 0.14,
    WmlVertAlign.baseline => 0,
  };

  /// paintTop API.
  double paintTop({
    required double lineY,
    required double lineHeight,
    required double fontSize,
  }) => switch (this) {
    WmlVertAlign.baseline => lineY,
    WmlVertAlign.superscript => lineY,
    WmlVertAlign.subscript =>
      lineY + (lineHeight - fontSize).clamp(0, lineHeight),
  };
}

/// Enum WmlTabAlignment.
enum WmlTabAlignment { left, center, right, decimal }

/// Enum WmlTabLeader.
enum WmlTabLeader { none, dot, hyphen, underscore }

/// Enum WmlVMerge.
enum WmlVMerge { none, restart, cont }

/// Enum WmlBreakType.
enum WmlBreakType { page, column, textWrapping }

/// Enum WmlFrameAnchor.
enum WmlFrameAnchor { page, margin }

/// Enum WmlFrameWrap.
enum WmlFrameWrap { none, square }

/// Class WmlPageSize.
class WmlPageSize {
  /// WmlPageSize API.
  const WmlPageSize({this.width = 595.28, this.height = 841.89});

  /// a4 API.
  factory WmlPageSize.a4() => const WmlPageSize();

  /// letter API.
  factory WmlPageSize.letter() => const WmlPageSize(width: 612, height: 792);

  /// legal API.
  factory WmlPageSize.legal() => const WmlPageSize(width: 612, height: 1008);

  /// a3 API.
  factory WmlPageSize.a3() => const WmlPageSize(width: 841.89, height: 1190.55);

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// isLandscape API.
  bool get isLandscape => width > height + 0.5;

  /// portrait API.
  WmlPageSize get portrait =>
      isLandscape ? WmlPageSize(width: height, height: width) : this;

  /// landscape API.
  WmlPageSize get landscape =>
      isLandscape ? this : WmlPageSize(width: height, height: width);

  /// matches API.
  bool matches(WmlPageSize other) =>
      (width - other.width).abs() < 1 && (height - other.height).abs() < 1;

  /// copyWith API.
  WmlPageSize copyWith({double? width, double? height}) =>
      WmlPageSize(width: width ?? this.width, height: height ?? this.height);
}

/// Class WmlPageMargins.
class WmlPageMargins {
  /// WmlPageMargins API.
  const WmlPageMargins({
    this.top = 72,
    this.bottom = 72,
    this.left = 72,
    this.right = 72,
    this.header = 36,
    this.footer = 36,
  });

  /// Word Normal: 1" on every side.
  static const WmlPageMargins normal = WmlPageMargins();

  /// Word Narrow: 0.5" on every side.
  static const WmlPageMargins narrow = WmlPageMargins(
    top: 36,
    bottom: 36,
    left: 36,
    right: 36,
  );

  /// Word Moderate: 1" top/bottom, 0.75" left/right.
  static const WmlPageMargins moderate = WmlPageMargins(
    top: 72,
    bottom: 72,
    left: 54,
    right: 54,
  );

  /// Word Wide: 1" top/bottom, 2" left/right.
  static const WmlPageMargins wide = WmlPageMargins(
    top: 72,
    bottom: 72,
    left: 144,
    right: 144,
  );

  /// top API.
  final double top;

  /// bottom API.
  final double bottom;

  /// left API.
  final double left;

  /// right API.
  final double right;

  /// Distance from page top to the header band (`w:pgMar/@w:header`).
  final double header;

  /// Distance from page bottom to the footer band (`w:pgMar/@w:footer`).
  final double footer;

  /// matches API.
  bool matches(WmlPageMargins other) =>
      (top - other.top).abs() < 0.5 &&
      (bottom - other.bottom).abs() < 0.5 &&
      (left - other.left).abs() < 0.5 &&
      (right - other.right).abs() < 0.5;

  /// copyWith API.
  WmlPageMargins copyWith({
    double? top,
    double? bottom,
    double? left,
    double? right,
    double? header,
    double? footer,
  }) => WmlPageMargins(
    top: top ?? this.top,
    bottom: bottom ?? this.bottom,
    left: left ?? this.left,
    right: right ?? this.right,
    header: header ?? this.header,
    footer: footer ?? this.footer,
  );
}

/// Class WmlIndent.
class WmlIndent {
  /// WmlIndent API.
  const WmlIndent({
    this.left = 0,
    this.right = 0,
    this.firstLine = 0,
    this.hanging = 0,
  });

  /// left API.
  final double left;

  /// right API.
  final double right;

  /// firstLine API.
  final double firstLine;

  /// hanging API.
  final double hanging;

  /// copyWith API.
  WmlIndent copyWith({
    double? left,
    double? right,
    double? firstLine,
    double? hanging,
  }) => WmlIndent(
    left: left ?? this.left,
    right: right ?? this.right,
    firstLine: firstLine ?? this.firstLine,
    hanging: hanging ?? this.hanging,
  );
}

/// Class WmlTabStop.
class WmlTabStop {
  /// WmlTabStop API.
  const WmlTabStop({
    required this.position,
    this.alignment = WmlTabAlignment.left,
    this.leader = WmlTabLeader.none,
  });

  /// position API.
  final double position;

  /// alignment API.
  final WmlTabAlignment alignment;

  /// leader API.
  final WmlTabLeader leader;
}

/// Class WmlBorder.
class WmlBorder {
  /// WmlBorder API.
  const WmlBorder({
    this.style = 'single',
    this.sizeEighths = 8,
    this.color = '000000',
  });

  /// style API.
  final String style;

  /// sizeEighths API.
  final int sizeEighths;

  /// color API.
  final String color;
}

/// Class WmlParagraphProps.
class WmlParagraphProps {
  /// WmlParagraphProps API.
  WmlParagraphProps({
    this.justification = WmlJustification.left,
    this.lineSpacing = 1.15,
    this.lineSpacingRule = WmlLineSpacingRule.auto,
    this.spacingBefore = 0,
    this.spacingAfter = 8,
    this.explicitLineSpacing = false,
    this.explicitSpacingBefore = false,
    this.explicitSpacingAfter = false,
    this.indent = const WmlIndent(),
    List<WmlTabStop>? tabs,
    this.keepTogether = false,
    this.pageBreakBefore = false,
    this.columnBreakBefore = false,
    this.numId,
    this.ilvl = 0,
    this.listLabel,
    this.listRestart,
    this.pageNumberField = false,
    this.headingLevel,
    this.styleId,
    this.fieldInstruction,
    this.fieldBegin = false,
    this.fieldEnd = false,
    this.bookmarkName,
    this.rightToLeft,
    this.dropCapLines = 0,
    this.shadingFill,
    this.borderColor,
    this.noteId,
    this.endnoteRef = false,
  }) : tabs = tabs ?? <WmlTabStop>[];

  /// justification API.
  WmlJustification justification;

  /// lineSpacing API.
  double lineSpacing;

  /// lineSpacingRule API.
  WmlLineSpacingRule lineSpacingRule;

  /// spacingBefore API.
  double spacingBefore;

  /// spacingAfter API.
  double spacingAfter;

  /// True when `w:spacing/@w:line` was set on this paragraph.
  bool explicitLineSpacing;

  /// True when `w:spacing/@w:before` was set on this paragraph.
  bool explicitSpacingBefore;

  /// True when `w:spacing/@w:after` was set on this paragraph.
  bool explicitSpacingAfter;

  /// indent API.
  WmlIndent indent;

  /// tabs API.
  List<WmlTabStop> tabs;

  /// keepTogether API.
  bool keepTogether;

  /// pageBreakBefore API.
  bool pageBreakBefore;

  /// columnBreakBefore API.
  bool columnBreakBefore;

  /// numId API.
  int? numId;

  /// ilvl API.
  int ilvl;

  /// listLabel API.
  String? listLabel;

  /// Restart value for multilevel numbering (`null` = continue).
  int? listRestart;

  /// pageNumberField API.
  bool pageNumberField;

  /// Word heading 1–9. `null` is body text (Normal).
  int? headingLevel;

  /// styleId API.
  String? styleId;

  /// fieldInstruction API.
  String? fieldInstruction;

  /// fieldBegin API.
  bool fieldBegin;

  /// fieldEnd API.
  bool fieldEnd;

  /// bookmarkName API.
  String? bookmarkName;

  /// Word `w:bidi`. `null` lets UAX #9 pick the paragraph level.
  bool? rightToLeft;

  /// Drop-cap line count; 0 is none.
  int dropCapLines;

  /// Paragraph shading RRGGBB.
  String? shadingFill;

  /// Paragraph border RRGGBB.
  String? borderColor;

  /// Footnote / endnote id referenced by this paragraph mark.
  int? noteId;

  /// endnoteRef API.
  bool endnoteRef;

  /// Embedding level for [LineBreaker]: 1 RTL, 0 LTR, `null` auto.
  int? get bidiBaseLevel {
    if (rightToLeft == true) {
      return 1;
    }
    if (rightToLeft == false) {
      return 0;
    }
    return justification == WmlJustification.right ? 1 : null;
  }

  /// copy API.
  WmlParagraphProps copy() => WmlParagraphProps(
    justification: justification,
    lineSpacing: lineSpacing,
    lineSpacingRule: lineSpacingRule,
    spacingBefore: spacingBefore,
    spacingAfter: spacingAfter,
    explicitLineSpacing: explicitLineSpacing,
    explicitSpacingBefore: explicitSpacingBefore,
    explicitSpacingAfter: explicitSpacingAfter,
    indent: indent,
    tabs: List<WmlTabStop>.from(tabs),
    keepTogether: keepTogether,
    pageBreakBefore: pageBreakBefore,
    columnBreakBefore: columnBreakBefore,
    numId: numId,
    ilvl: ilvl,
    listLabel: listLabel,
    listRestart: listRestart,
    pageNumberField: pageNumberField,
    headingLevel: headingLevel,
    styleId: styleId,
    fieldInstruction: fieldInstruction,
    fieldBegin: fieldBegin,
    fieldEnd: fieldEnd,
    bookmarkName: bookmarkName,
    rightToLeft: rightToLeft,
    dropCapLines: dropCapLines,
    shadingFill: shadingFill,
    borderColor: borderColor,
    noteId: noteId,
    endnoteRef: endnoteRef,
  );
}

/// Maps Word `w:highlight` names (and raw hex) to RRGGBB.
abstract final class WmlHighlight {
  /// toRgb API.
  static String? toRgb(String? value) {
    if (value == null || value.isEmpty || value == 'none') {
      return null;
    }
    switch (value) {
      case 'yellow':
        return 'FFFF00';
      case 'green':
        return '00FF00';
      case 'cyan':
        return '00FFFF';
      case 'magenta':
        return 'FF00FF';
      case 'blue':
        return '0000FF';
      case 'red':
        return 'FF0000';
      case 'darkBlue':
        return '000080';
      case 'darkCyan':
        return '008080';
      case 'darkGreen':
        return '008000';
      case 'darkMagenta':
        return '800080';
      case 'darkRed':
        return '800000';
      case 'darkYellow':
        return '808000';
      case 'darkGray':
        return '808080';
      case 'lightGray':
        return 'C0C0C0';
      case 'black':
        return '000000';
      case 'white':
        return 'FFFFFF';
      default:
        final String hex = value.replaceFirst('#', '');
        if (hex.length == 6) {
          return hex.toUpperCase();
        }
        return null;
    }
  }
}

/// Class WmlRunProps.
class WmlRunProps {
  /// WmlRunProps API.
  WmlRunProps({
    this.bold = false,
    this.italic = false,
    this.underline = WmlUnderline.none,
    this.strike = false,
    this.color = '000000',
    this.highlight,
    this.fontSizeHalfPoints = 22,
    this.asciiFont = 'Arial',
    this.csFont = 'Arial',
    this.vertAlign = WmlVertAlign.baseline,
  });

  /// bold API.
  bool bold;

  /// italic API.
  bool italic;

  /// underline API.
  WmlUnderline underline;

  /// strike API.
  bool strike;

  /// color API.
  String color;

  /// highlight API.
  String? highlight;

  /// fontSizeHalfPoints API.
  int fontSizeHalfPoints;

  /// asciiFont API.
  String asciiFont;

  /// csFont API.
  String csFont;

  /// vertAlign API.
  WmlVertAlign vertAlign;

  /// fontSizePoints API.
  double get fontSizePoints => fontSizeHalfPoints / 2.0;

  /// copy API.
  WmlRunProps copy() => WmlRunProps(
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    color: color,
    highlight: highlight,
    fontSizeHalfPoints: fontSizeHalfPoints,
    asciiFont: asciiFont,
    csFont: csFont,
    vertAlign: vertAlign,
  );
}

/// Class WmlTableProps.
class WmlTableProps {
  /// WmlTableProps API.
  WmlTableProps({
    this.alignment = WmlJustification.left,
    this.floating = false,
    this.cellMargin = 4,
    this.rightToLeft = false,
    this.borders = true,
    this.borderColor,
    this.borderWidth = 0.5,
    this.styleId,
  });

  /// alignment API.
  WmlJustification alignment;

  /// floating API.
  bool floating;

  /// cellMargin API.
  double cellMargin;

  /// Word `w:bidiVisual` — first column is drawn on the right.
  bool rightToLeft;

  /// When false, no `tblBorders` are written (borderless layout rows).
  bool borders;

  /// RRGGBB stroke for table borders.
  String? borderColor;

  /// Stroke width in points (Word `w:sz` is eighths of a point).
  double borderWidth;

  /// `w:tblStyle` id (e.g. TableGrid).
  String? styleId;

  /// copy API.
  WmlTableProps copy() => WmlTableProps(
    alignment: alignment,
    floating: floating,
    cellMargin: cellMargin,
    rightToLeft: rightToLeft,
    borders: borders,
    borderColor: borderColor,
    borderWidth: borderWidth,
    styleId: styleId,
  );
}

/// pointsToTwips helper.
int pointsToTwips(double points) => (points * 20).round();

/// twipsToPoints helper.
double twipsToPoints(int twips) => twips / 20.0;

/// parseHexInt helper.
int? parseHexInt(String? raw) {
  if (raw == null || raw.isEmpty || raw == 'auto') {
    return null;
  }
  return int.tryParse(raw.replaceFirst('#', ''), radix: 16);
}
