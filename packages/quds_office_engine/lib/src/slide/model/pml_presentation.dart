import '../../office/office_document_properties.dart';
import '../../opc/opc_archive.dart';
import '../../visual/office_visual.dart';
import '../../xml/xml_node.dart';
import '../anim/pml_motion.dart';

/// Class PmlTransform.
class PmlTransform {
  /// PmlTransform API.
  const PmlTransform({
    this.x = 0,
    this.y = 0,
    this.cx = 914400,
    this.cy = 914400,
    this.rot = 0,
    this.flipH = false,
    this.flipV = false,
  });

  /// Offsets and extents in EMUs (1 pt = 12,700 EMUs).
  final int x;

  /// y API.
  final int y;

  /// cx API.
  final int cx;

  /// cy API.
  final int cy;

  /// rot API.
  final int rot;

  /// Horizontal flip from `a:xfrm/@flipH`.
  final bool flipH;

  /// Vertical flip from `a:xfrm/@flipV`.
  final bool flipV;

  /// Returns this geometry with only the supplied properties changed.
  PmlTransform copyWith({
    int? x,
    int? y,
    int? cx,
    int? cy,
    int? rot,
    bool? flipH,
    bool? flipV,
  }) => PmlTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    cx: cx ?? this.cx,
    cy: cy ?? this.cy,
    rot: rot ?? this.rot,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
  );

  /// xPoints API.
  double get xPoints => x / 12700;

  /// yPoints API.
  double get yPoints => y / 12700;

  /// widthPoints API.
  double get widthPoints => cx / 12700;

  /// heightPoints API.
  double get heightPoints => cy / 12700;

  /// rotationDegrees API.
  double get rotationDegrees => rot / 60000;
}

/// Enum PmlShapePreset.
enum PmlShapePreset {
  rect,
  roundRect,
  ellipse,
  triangle,
  connector,
  freeform,
  downArrow,
  upArrow,
  leftArrow,
  rightArrow,
  diamond,
  hexagon,
  pentagon,
  chevron,
  parallelogram,
  trapezoid,
  homePlate,
}

/// One colour stop in a DrawingML gradient fill.
class PmlGradientStop {
  PmlGradientStop({required this.position, required this.color});

  final double position;
  final String color;

  PmlGradientStop copy() => PmlGradientStop(position: position, color: color);
}

/// A linear or centered circular DrawingML gradient fill.
class PmlGradientFill {
  PmlGradientFill({
    List<PmlGradientStop>? stops,
    this.angleDegrees = 0,
    this.radial = false,
  }) : stops = stops ?? <PmlGradientStop>[];

  final List<PmlGradientStop> stops;
  double angleDegrees;

  /// Circular shading from the center to the circumscribed shape bounds.
  /// Other path types and noncentral focus rectangles are not modeled.
  bool radial;

  String get fallbackColor => stops.isEmpty ? '' : stops.first.color;

  PmlGradientFill copy() => PmlGradientFill(
    stops: <PmlGradientStop>[for (final stop in stops) stop.copy()],
    angleDegrees: angleDegrees,
    radial: radial,
  );
}

/// Enum PmlTextAlign.
enum PmlTextAlign { left, center, right, justify }

/// Vertical placement of a text frame inside its shape.
enum PmlTextAnchor { top, center, bottom }

/// One styled DrawingML text run.
class PmlTextRun {
  PmlTextRun({
    this.text = '',
    this.fontSizePt = 0,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color = '',
    this.baseline = 0,
    this.fontFamily = '',
  });

  String text;
  double fontSizePt;
  bool bold;
  bool italic;
  bool underline;
  bool strike;
  String color;
  double baseline;
  String fontFamily;

  PmlTextRun copy() => PmlTextRun(
    text: text,
    fontSizePt: fontSizePt,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    color: color,
    baseline: baseline,
    fontFamily: fontFamily,
  );
}

/// One DrawingML paragraph with its runs and layout settings.
class PmlTextParagraph {
  PmlTextParagraph({
    List<PmlTextRun>? runs,
    this.align = PmlTextAlign.left,
    this.level = 0,
    this.marginLeftPt = 0,
    this.indentPt = 0,
    this.lineSpacing = 1,
    this.lineSpacingPt,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 0,
    this.rightToLeft = false,
    this.defaultTabPt = 72,
    this.defaultFontSizePt = 0,
    this.defaultColor = '',
    this.defaultBold = false,
    this.defaultItalic = false,
    this.replacementRun,
  }) : runs = runs ?? <PmlTextRun>[];

  List<PmlTextRun> runs;
  PmlTextAlign align;
  int level;
  double marginLeftPt;
  double indentPt;
  double lineSpacing;

  /// Fixed line spacing in points; excludes percentage autofit reduction.
  double? lineSpacingPt;
  double spaceBeforePt;
  double spaceAfterPt;
  bool rightToLeft;
  double defaultTabPt;
  double defaultFontSizePt;
  String defaultColor;
  bool defaultBold;
  bool defaultItalic;

  /// Imported ordinary-run formatting used when text is explicitly replaced.
  /// It can differ from the first visible run when a field or break precedes it.
  PmlTextRun? replacementRun;

  PmlTextParagraph copy() => PmlTextParagraph(
    runs: <PmlTextRun>[for (final PmlTextRun run in runs) run.copy()],
    align: align,
    level: level,
    marginLeftPt: marginLeftPt,
    indentPt: indentPt,
    lineSpacing: lineSpacing,
    lineSpacingPt: lineSpacingPt,
    spaceBeforePt: spaceBeforePt,
    spaceAfterPt: spaceAfterPt,
    rightToLeft: rightToLeft,
    defaultTabPt: defaultTabPt,
    defaultFontSizePt: defaultFontSizePt,
    defaultColor: defaultColor,
    defaultBold: defaultBold,
    defaultItalic: defaultItalic,
    replacementRun: replacementRun?.copy(),
  );
}

/// Class PmlTableCell.
class PmlTableCell {
  /// PmlTableCell API.
  PmlTableCell({this.text = '', this.fillColor = '', this.textColor = ''});

  /// text API.
  String text;

  /// fillColor API.
  String fillColor;

  /// Optional gradient fill; takes precedence over [fillColor] when present.
  PmlGradientFill? gradient;

  /// textColor API.
  String textColor;

  /// copy API.
  PmlTableCell copy() =>
      PmlTableCell(text: text, fillColor: fillColor, textColor: textColor);
}

/// Class PmlTable.
class PmlTable {
  /// PmlTable API.
  PmlTable({
    List<List<PmlTableCell>>? rows,
    this.headerRow = true,
    this.rightToLeft = false,
  }) : rows = rows ?? <List<PmlTableCell>>[];

  /// rows API.
  List<List<PmlTableCell>> rows;

  /// headerRow API.
  bool headerRow;

  /// rightToLeft API.
  bool rightToLeft;

  /// rowCount API.
  int get rowCount => rows.length;

  /// colCount API.
  int get colCount {
    var max = 0;
    for (final List<PmlTableCell> row in rows) {
      if (row.length > max) {
        max = row.length;
      }
    }
    return max;
  }

  /// cellAt API.
  PmlTableCell cellAt(int row, int col) {
    while (rows.length <= row) {
      rows.add(<PmlTableCell>[]);
    }
    while (rows[row].length <= col) {
      rows[row].add(PmlTableCell());
    }
    return rows[row][col];
  }

  /// cellBounds API.
  ({double x, double y, double width, double height}) cellBounds({
    required double x,
    required double y,
    required double width,
    required double height,
    required int row,
    required int col,
  }) {
    final int rowsN = rowCount < 1 ? 1 : rowCount;
    final int colsN = colCount < 1 ? 1 : colCount;
    final double cw = width / colsN;
    final double rh = height / rowsN;
    final int visualCol = rightToLeft ? colsN - 1 - col : col;
    return (x: x + visualCol * cw, y: y + row * rh, width: cw, height: rh);
  }

  /// hitCell API.
  ({int row, int col})? hitCell({
    required double x,
    required double y,
    required double width,
    required double height,
    required double localX,
    required double localY,
  }) {
    if (rowCount <= 0 || colCount <= 0) {
      return null;
    }
    if (localX < x || localY < y || localX > x + width || localY > y + height) {
      return null;
    }
    final int row = ((localY - y) / (height / rowCount)).floor().clamp(
      0,
      rowCount - 1,
    );
    final int visualCol = ((localX - x) / (width / colCount)).floor().clamp(
      0,
      colCount - 1,
    );
    final int col = rightToLeft ? colCount - 1 - visualCol : visualCol;
    return (row: row, col: col);
  }

  /// grid API.
  static PmlTable grid({
    required int rows,
    required int cols,
    bool header = true,
    bool arabic = false,
  }) {
    final int safeRows = rows.clamp(1, 12);
    final int safeCols = cols.clamp(1, 12);
    final PmlTable table = PmlTable(headerRow: header, rightToLeft: arabic);
    for (int r = 0; r < safeRows; r++) {
      final bool isHeader = header && r == 0;
      table.rows.add(<PmlTableCell>[
        for (int c = 0; c < safeCols; c++)
          PmlTableCell(
            text: isHeader
                ? (arabic ? 'عمود ${c + 1}' : 'Column ${c + 1}')
                : (arabic
                      ? 'خلية ${r + 1}×${c + 1}'
                      : 'Cell ${r + 1}×${c + 1}'),
            fillColor: isHeader ? '2B579A' : (r.isOdd ? 'D6DCE4' : 'FFFFFF'),
            textColor: isHeader ? 'FFFFFF' : '1A1A1A',
          ),
      ]);
    }
    return table;
  }

  /// copy API.
  PmlTable copy() => PmlTable(
    headerRow: headerRow,
    rightToLeft: rightToLeft,
    rows: <List<PmlTableCell>>[
      for (final List<PmlTableCell> row in rows)
        <PmlTableCell>[for (final PmlTableCell cell in row) cell.copy()],
    ],
  );
}

/// Imported text body and the scalar values exposed by the shape editor.
///
/// The immutable source retains rich runs, fonts, bullets, hyperlinks, fields
/// and body settings when a shape is moved or otherwise edited without
/// replacing its text. Scalar text-format edits are applied during export.
class PmlTextSource {
  /// Creates an immutable source snapshot.
  const PmlTextSource({
    required this.xml,
    required this.text,
    required this.fontSizePt,
    required this.textColor,
    required this.textAlign,
    required this.rightToLeft,
    this.textScale = 1,
    this.lineSpacingReduction = 0,
  });

  /// Original DrawingML text body, including namespace declarations.
  final String xml;

  /// Text and formatting exposed on import.
  final String text;

  /// Imported representative font size.
  final double fontSizePt;

  /// Imported representative text color.
  final String textColor;

  /// Imported paragraph alignment.
  final PmlTextAlign textAlign;

  /// Imported paragraph direction.
  final bool? rightToLeft;

  final double textScale;
  final double lineSpacingReduction;
}

/// Class PmlShape.
class PmlShape {
  /// PmlShape API.
  PmlShape({
    required this.id,
    required this.name,
    this.preset = PmlShapePreset.rect,
    this.transform = const PmlTransform(),
    this.text = '',
    this.fillColor = '4472C4',
    this.gradient,
    this.textColor = '',
    this.fontSizePt = 0,
    this.textBold,
    this.textItalic,
    this.textUnderline,
    this.textFontFamily,
    this.textSizeOverride = false,
    this.textColorOverride = false,
    this.textAlignOverride = false,
    this.textDirectionOverride = false,
    this.textReplacementRequested = false,
    this.textSource,
    this.embedRelId,
    List<PmlPathPoint>? path,
    this.visual,
    this.isBackgroundPicture = false,
    this.isBackgroundGradient = false,
    this.table,
    this.rightToLeft,
    this.textAlign = PmlTextAlign.left,
    this.textAnchor = PmlTextAnchor.top,
    this.textAnchorOverride = false,
    double textScale = 1.0,
    double lineSpacingReduction = 0.0,
    List<PmlTextParagraph>? richText,
    this.groupId,
    this.placeholder = false,
    this.placeholderType = '',
    this.placeholderIndex,
    this.mediaName = '',
    List<int>? mediaBytes,
    this.strokeColor = '',
    this.strokeWidth = 1,
    this.hyperlinkUrl = '',
  }) : _textScale = _autofitRatio(textScale, 'textScale'),
       _lineSpacingReduction = _autofitRatio(
         lineSpacingReduction,
         'lineSpacingReduction',
       ),
       path = path ?? <PmlPathPoint>[],
       richText = richText ?? <PmlTextParagraph>[],
       mediaBytes = mediaBytes ?? <int>[];

  /// id API.
  int id;

  /// name API.
  String name;

  /// preset API.
  PmlShapePreset preset;

  /// transform API.
  PmlTransform transform;

  /// text API.
  String text;

  /// fillColor API.
  String fillColor;

  /// Optional gradient fill; takes precedence over [fillColor] when present.
  PmlGradientFill? gradient;

  /// textColor API.
  String textColor;

  /// fontSizePt API.
  double fontSizePt;

  /// Explicit whole-text formatting. Null retains the imported run styles;
  /// false explicitly removes the corresponding decoration.
  bool? textBold;
  bool? textItalic;
  bool? textUnderline;
  String? textFontFamily;

  /// Retain the intent of a whole-text assignment even when its scalar value
  /// equals the representative imported value but individual runs differ.
  bool textSizeOverride;
  bool textColorOverride;
  bool textAlignOverride;
  bool textDirectionOverride;

  /// Explicit native text assignments replace imported runs even when the
  /// scalar text is unchanged, using the same template for display and export.
  bool textReplacementRequested;

  bool get hasExplicitTextFormatting =>
      textBold != null ||
      textItalic != null ||
      textUnderline != null ||
      textFontFamily != null ||
      textSizeOverride ||
      textColorOverride ||
      textAlignOverride ||
      textDirectionOverride;

  /// Source rich text used to preserve unchanged imported formatting.
  PmlTextSource? textSource;

  /// embedRelId API.
  String? embedRelId;

  /// path API.
  List<PmlPathPoint> path;

  /// visual API.
  OfficeVisual? visual;

  /// A full-slide picture resolved from the native `p:bg` fill.
  /// This role distinguishes the background from ordinary template pictures.
  /// It is rendered in [PmlSlide.backgroundShapes] and saved as `p:bg`.
  final bool isBackgroundPicture;

  /// A full-slide gradient resolved from the selected native `p:bg` fill.
  /// It shares fill ownership with a background picture, while ordinary
  /// gradient decorations remain independent of solid-background edits.
  final bool isBackgroundGradient;

  bool get isBackgroundFill => isBackgroundPicture || isBackgroundGradient;

  /// table API.
  PmlTable? table;

  /// DrawingML `a:pPr/@rtl`. `null` auto-detects from the text.
  bool? rightToLeft;

  /// textAlign API.
  PmlTextAlign textAlign;

  /// Vertical text-frame placement from `a:bodyPr/@anchor`.
  PmlTextAnchor textAnchor;

  /// An explicit assignment owns `a:bodyPr/@anchor` even when its projected
  /// value matches an imported baseline/unsupported anchor's fallback.
  bool textAnchorOverride;

  /// `a:normAutofit/@fontScale`, normalized to 0.0–1.0.
  double get textScale => _textScale;
  double _textScale;

  set textScale(double value) => _textScale = _autofitRatio(value, 'textScale');

  /// `a:normAutofit/@lnSpcReduction`, normalized to 0.0–1.0.
  double get lineSpacingReduction => _lineSpacingReduction;
  double _lineSpacingReduction;

  set lineSpacingReduction(double value) =>
      _lineSpacingReduction = _autofitRatio(value, 'lineSpacingReduction');

  static double _autofitRatio(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw RangeError.value(
        value,
        name,
        'Expected a finite value from 0 to 1',
      );
    }
    return value;
  }

  /// Rich paragraph/run model when the source text has not been replaced.
  List<PmlTextParagraph> richText;

  /// Rich text with the same scalar formatting overrides used by PPTX export.
  ///
  /// Moving a shape preserves its imported runs. Font, color, alignment and
  /// direction edits apply to those runs without mutating the import snapshot.
  /// Replacing imported text invalidates the old runs altogether.
  List<PmlTextParagraph> get resolvedRichText {
    final PmlTextSource? source = textSource;
    final bool explicit = hasExplicitTextFormatting || textReplacementRequested;
    if (!explicit && (source == null || richText.isEmpty)) return richText;
    if (!explicit && source!.text != text) return const <PmlTextParagraph>[];
    final bool replace =
        textReplacementRequested ||
        source == null ||
        richText.isEmpty ||
        source.text != text;
    final bool fontChanged =
        textSizeOverride ||
        (source == null
            ? replace && fontSizePt > 0
            : source.fontSizePt != fontSizePt);
    final bool colorChanged =
        textColorOverride ||
        (source == null
            ? replace && textColor.isNotEmpty
            : source.textColor != textColor);
    final bool alignChanged =
        textAlignOverride ||
        (source == null ? replace : source.textAlign != textAlign);
    final bool directionChanged =
        textDirectionOverride ||
        (source == null ? replace : source.rightToLeft != rightToLeft);
    if (!explicit &&
        !fontChanged &&
        !colorChanged &&
        !alignChanged &&
        !directionChanged) {
      return richText;
    }
    final List<PmlTextParagraph> originals;
    if (replace) {
      final lines = text.split('\n');
      originals = <PmlTextParagraph>[];
      for (var i = 0; i < lines.length; i++) {
        // Without an imported XML source, export starts from the authored
        // scalar text/style. Unsaved display runs are not its replacement
        // template and must not leave stale text or styling in live output.
        final template = source == null || richText.isEmpty
            ? PmlTextParagraph()
            : richText[i < richText.length ? i : richText.length - 1].copy();
        final run =
            template.replacementRun?.copy() ??
            (template.runs.isEmpty
                ? PmlTextRun(
                    text: lines[i],
                    fontSizePt: template.defaultFontSizePt,
                    color: template.defaultColor,
                    bold: template.defaultBold,
                    italic: template.defaultItalic,
                  )
                : template.runs.first.copy());
        run.text = lines[i];
        template.runs = <PmlTextRun>[run];
        originals.add(template);
      }
    } else {
      originals = richText;
    }
    final List<PmlTextParagraph> resolved = <PmlTextParagraph>[];
    for (final PmlTextParagraph original in originals) {
      final PmlTextParagraph paragraph = original.copy();
      if (alignChanged) paragraph.align = textAlign;
      if (directionChanged) paragraph.rightToLeft = rightToLeft ?? false;
      if (fontChanged) paragraph.defaultFontSizePt = fontSizePt;
      if (colorChanged) paragraph.defaultColor = textColor;
      if (textBold != null) paragraph.defaultBold = textBold!;
      if (textItalic != null) paragraph.defaultItalic = textItalic!;
      for (final PmlTextRun run in paragraph.runs) {
        if (fontChanged) run.fontSizePt = fontSizePt;
        if (colorChanged) run.color = textColor;
        if (textBold != null) run.bold = textBold!;
        if (textItalic != null) run.italic = textItalic!;
        if (textUnderline != null) run.underline = textUnderline!;
        if (textFontFamily != null) run.fontFamily = textFontFamily!;
      }
      resolved.add(paragraph);
    }
    return resolved;
  }

  /// Whether the unmodified imported runs still match scalar text formatting.
  /// Renderers use [resolvedRichText] to apply edits while retaining run styles.
  bool get hasCurrentRichText {
    if (richText.isEmpty ||
        hasExplicitTextFormatting ||
        textReplacementRequested) {
      return false;
    }
    final PmlTextSource? source = textSource;
    return source == null ||
        (source.text == text &&
            source.fontSizePt == fontSizePt &&
            source.textColor == textColor &&
            source.textAlign == textAlign &&
            source.rightToLeft == rightToLeft);
  }

  /// Shapes that share a [groupId] move together.
  int? groupId;

  /// True when this shape is a layout / master placeholder.
  bool placeholder;

  /// `p:ph/@type` (`title`, `ctrTitle`, `body`, `subTitle`, `dt`, …); empty
  /// when the attribute is absent, which PowerPoint reads as `obj`.
  String placeholderType;

  /// `p:ph/@idx`, the key slides use to inherit from layout placeholders.
  int? placeholderIndex;

  /// Optional media file name (video/audio).
  String mediaName;

  /// Optional media payload for playback hosts.
  List<int> mediaBytes;

  /// Outline stroke as `RRGGBB`; empty means no stroke (fill-only).
  String strokeColor;

  /// Outline width in points when [strokeColor] is set.
  double strokeWidth;

  /// External hyperlink URL for the shape (`a:hlinkClick` target).
  String hyperlinkUrl;

  /// True when this shape has playable media.
  bool get hasMedia => mediaBytes.isNotEmpty || mediaName.isNotEmpty;

  /// copy API.
  PmlShape copy({int? id}) {
    return PmlShape(
      id: id ?? this.id,
      name: name,
      preset: preset,
      transform: transform,
      text: text,
      fillColor: fillColor,
      gradient: gradient?.copy(),
      textColor: textColor,
      fontSizePt: fontSizePt,
      textBold: textBold,
      textItalic: textItalic,
      textUnderline: textUnderline,
      textFontFamily: textFontFamily,
      textSizeOverride: textSizeOverride,
      textColorOverride: textColorOverride,
      textAlignOverride: textAlignOverride,
      textDirectionOverride: textDirectionOverride,
      textReplacementRequested: textReplacementRequested,
      textSource: textSource,
      embedRelId: embedRelId,
      path: <PmlPathPoint>[...path],
      visual: visual?.copy(),
      isBackgroundPicture: isBackgroundPicture,
      isBackgroundGradient: isBackgroundGradient,
      table: table?.copy(),
      rightToLeft: rightToLeft,
      textAlign: textAlign,
      textAnchor: textAnchor,
      textAnchorOverride: textAnchorOverride,
      textScale: textScale,
      lineSpacingReduction: lineSpacingReduction,
      richText: <PmlTextParagraph>[
        for (final PmlTextParagraph paragraph in richText) paragraph.copy(),
      ],
      groupId: groupId,
      placeholder: placeholder,
      placeholderType: placeholderType,
      placeholderIndex: placeholderIndex,
      mediaName: mediaName,
      mediaBytes: <int>[...mediaBytes],
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      hyperlinkUrl: hyperlinkUrl,
    );
  }
}

/// Class PmlPathPoint.
class PmlPathPoint {
  /// PmlPathPoint API.
  const PmlPathPoint(this.x, this.y);

  /// x API.
  final int x;

  /// y API.
  final int y;
}

/// Class PmlSlide.
class PmlSlide {
  /// PmlSlide API.
  PmlSlide({
    required this.id,
    List<PmlShape>? shapes,
    this.layoutName = 'Blank',
    this.masterName = 'Office Theme',
    String background = '',
    bool? inheritsMasterBackground,
    List<PmlShape>? backgroundShapes,
    bool? backgroundShapesResolved,
    this.showMasterShapes = true,
    this.notes = '',
    this.sourcePartUri,
    this.sourceLayoutPartUri,
    this.transition = const PmlSlideTransition(),
    List<PmlShapeAnimation>? animations,
    this.hidden = false,
  }) : _background = background,
       _primaryMasterBackground = background.isEmpty
           ? null
           : background.toUpperCase(),
       inheritsMasterBackground =
           inheritsMasterBackground ?? background.isEmpty,
       shapes = shapes ?? <PmlShape>[],
       backgroundShapes = backgroundShapes ?? <PmlShape>[],
       backgroundShapesResolved =
           backgroundShapesResolved ?? (backgroundShapes != null),
       animations = animations ?? <PmlShapeAnimation>[];

  /// id API.
  int id;

  /// shapes API.
  List<PmlShape> shapes;

  /// The selected background picture and non-editable master/layout decorations
  /// painted behind [shapes]. Import resolves master-shape visibility while
  /// retaining the selected background fill and layout shapes.
  final List<PmlShape> backgroundShapes;

  /// Whether this slide has its own resolved master/layout decorations.
  /// A resolved empty list must not fall back to the presentation master.
  final bool backgroundShapesResolved;

  /// The slide's authored `showMasterSp` flag, retained when saving/copying.
  bool showMasterShapes;

  /// layoutName API.
  String layoutName;

  /// masterName API.
  String masterName;

  String _background;
  String? _primaryMasterBackground;
  XmlElement? _sourceBackground;
  PmlShape? _backgroundFill;
  bool _backgroundFromSource = false;

  /// Authored slide fill retained with its namespace bindings for serialization.
  /// Layout/master fills remain in their owning package parts.
  XmlElement? get sourceBackground => _sourceBackground;

  /// The selected imported picture, also present first in [backgroundShapes].
  PmlShape? get backgroundPicture =>
      (_backgroundFill?.isBackgroundPicture ?? false) ? _backgroundFill : null;

  /// The selected imported gradient, also present first in [backgroundShapes].
  PmlShape? get backgroundGradient =>
      (_backgroundFill?.isBackgroundGradient ?? false) ? _backgroundFill : null;

  /// A direct solid-color assignment must be serialized as an authored fill.
  bool get writesSolidBackground =>
      !_backgroundFromSource &&
      !inheritsMasterBackground &&
      _background.isNotEmpty;

  /// Retains an imported fill after its displayed color and image are resolved.
  void retainSourceBackground(
    XmlElement? source, {
    PmlShape? picture,
    PmlShape? gradient,
  }) {
    if (picture != null && gradient != null) {
      throw ArgumentError('A background selects one picture or gradient fill.');
    }
    _clearSourceBackground();
    _sourceBackground = source?.copy();
    _backgroundFromSource = true;
    _backgroundFill = picture ?? gradient;
    if (_backgroundFill != null) backgroundShapes.insert(0, _backgroundFill!);
  }

  void _clearSourceBackground() {
    if (_backgroundFill != null) backgroundShapes.remove(_backgroundFill);
    _sourceBackground = null;
    _backgroundFill = null;
    _backgroundFromSource = false;
  }

  /// Resolved solid background (`RRGGBB`); empty uses the current master.
  /// Assigning a nonempty color records an explicit slide override.
  String get background => _background;

  set background(String value) {
    _clearSourceBackground();
    _background = value;
    inheritsMasterBackground = value.isEmpty;
    _primaryMasterBackground = null;
    backgroundShapes.removeWhere((shape) => shape.isBackgroundFill);
  }

  /// Whether a master-background edit should update this slide's paper.
  /// Explicit slide/layout fills remain independent of master edits.
  bool inheritsMasterBackground;

  /// Retains an inherited color and the primary master at resolution time.
  /// The resolved color can come from a secondary imported slide master.
  void setInheritedBackground(
    String value, {
    required String masterBackground,
  }) {
    _clearSourceBackground();
    _background = value;
    inheritsMasterBackground = true;
    _primaryMasterBackground = masterBackground.isEmpty
        ? 'FFFFFF'
        : masterBackground.toUpperCase();
  }

  /// Resolves direct master edits without losing imported secondary colors.
  String resolveBackground(String masterBackground) {
    final String current = masterBackground.isEmpty
        ? 'FFFFFF'
        : masterBackground;
    if (inheritsMasterBackground &&
        (_background.isEmpty ||
            (_primaryMasterBackground != null &&
                _primaryMasterBackground != current.toUpperCase()))) {
      return current;
    }
    return _background.isEmpty ? current : _background;
  }

  /// Refreshes inherited paper without detaching it from future master edits.
  void updateMasterBackground(String value) {
    if (inheritsMasterBackground) {
      setInheritedBackground(value, masterBackground: value);
      backgroundShapes.removeWhere((shape) => shape.isBackgroundFill);
    }
  }

  /// Original owning part, retained when slides are reordered.
  String? sourcePartUri;

  /// Imported layout provenance, retained by copies within the same package.
  /// It preserves native master-background inheritance when a copy gets a new
  /// slide part rather than flattening an inherited picture into a local fill.
  String? sourceLayoutPartUri;

  /// notes API.
  String notes;

  /// transition API.
  PmlSlideTransition transition;

  /// animations API.
  final List<PmlShapeAnimation> animations;

  /// PowerPoint `p:sld/@show="0"` — skipped during a slide show.
  bool hidden;

  /// copy API.
  PmlSlide copy({int? id}) {
    final PmlSlide result = PmlSlide(
      id: id ?? this.id,
      layoutName: layoutName,
      masterName: masterName,
      background: background,
      inheritsMasterBackground: inheritsMasterBackground,
      notes: notes,
      backgroundShapesResolved: backgroundShapesResolved,
      backgroundShapes: <PmlShape>[
        for (final PmlShape shape in backgroundShapes) shape.copy(),
      ],
      showMasterShapes: showMasterShapes,
      sourcePartUri: id == null || id == this.id ? sourcePartUri : null,
      sourceLayoutPartUri: sourceLayoutPartUri,
      transition: transition,
      hidden: hidden,
      animations: <PmlShapeAnimation>[
        for (final PmlShapeAnimation anim in animations) anim.copyWith(),
      ],
      shapes: <PmlShape>[for (final PmlShape shape in shapes) shape.copy()],
    ).._primaryMasterBackground = _primaryMasterBackground;
    result._sourceBackground = _sourceBackground?.copy();
    result._backgroundFromSource = _backgroundFromSource;
    if (_backgroundFill != null) {
      final int index = backgroundShapes.indexOf(_backgroundFill!);
      if (index >= 0) {
        result._backgroundFill = result.backgroundShapes[index];
      }
    }
    return result;
  }
}

/// Class PmlLayout.
class PmlLayout {
  /// PmlLayout API.
  PmlLayout({
    required this.name,
    this.placeholderText = '',
    List<PmlShape>? placeholders,
  }) : placeholders = placeholders ?? <PmlShape>[];

  /// name API.
  String name;

  /// placeholderText API.
  String placeholderText;

  /// Real layout placeholders hosts can edit.
  final List<PmlShape> placeholders;
}

/// Class PmlMaster.
class PmlMaster {
  /// PmlMaster API.
  PmlMaster({required this.name, String? background, List<PmlShape>? shapes})
    : _background = background ?? 'FFFFFF',
      _hasAuthoredBackground = background != null,
      shapes = shapes ?? <PmlShape>[];

  /// name API.
  String name;

  String _background;
  bool _hasAuthoredBackground;
  String? _nativeBackground;

  /// Resolved paper color. Assigning it authors a solid master fill, including
  /// when the color equals an imported picture's solid fallback.
  String get background => _background;

  set background(String value) {
    _background = value;
    _hasAuthoredBackground = true;
  }

  /// Whether native master fills should be replaced by the authored color.
  bool get hasAuthoredBackground => _hasAuthoredBackground;

  /// A changed primary color also changes inherited secondary-master colors.
  /// An explicit assignment of the same color can still replace picture fills.
  bool get changesNativeBackgroundColor =>
      _nativeBackground == null ||
      _nativeBackground !=
          (_background.isEmpty ? 'FFFFFF' : _background.toUpperCase());

  /// Records a resolved imported or published color without authoring a fill.
  void setImportedBackground(String value) {
    _background = value;
    _hasAuthoredBackground = false;
    _nativeBackground = value.isEmpty ? 'FFFFFF' : value.toUpperCase();
  }

  /// Master shapes / placeholders.
  final List<PmlShape> shapes;
}

/// A named group of consecutive slides in the sorter.
class PmlSection {
  /// PmlSection API.
  PmlSection({
    required this.name,
    required this.startIndex,
    this.id,
    this.nativeXml,
  });

  /// name API.
  String name;

  /// First slide index in this section (inclusive).
  int startIndex;

  /// Native section GUID. Imported identities are retained across moves/saves.
  String? id;

  /// Original section properties, including opaque extension payloads.
  /// Serialization copies this node and replaces only modeled properties.
  final XmlElement? nativeXml;
}

/// Import provenance for native section membership that cannot be modeled.
class PmlSectionSource {
  /// Creates a read-only record of the imported slide order and any guard.
  PmlSectionSource({required Iterable<int> slideIds, this.issue})
    : slideIds = List<int>.unmodifiable(slideIds);

  /// Native slide order before any edit.
  final List<int> slideIds;

  /// A non-null reason prevents section-aware mutation of ambiguous input.
  final String? issue;
}

/// Class PmlPresentation.
class PmlPresentation {
  /// PmlPresentation API.
  PmlPresentation({
    List<PmlSlide>? slides,
    PmlMaster? master,
    List<PmlLayout>? layouts,
    List<PmlSection>? sections,
    OfficeDocumentProperties? properties,
    this.package,
    this.sectionSource,
    this.slideWidth = 9144000,
    this.slideHeight = 5143500,
  }) : slides = slides ?? <PmlSlide>[PmlSlide(id: 256)],
       master = master ?? PmlMaster(name: 'Office Theme'),
       layouts = layouts ?? <PmlLayout>[PmlLayout(name: 'Blank')],
       sections = sections ?? <PmlSection>[],
       properties = properties ?? OfficeDocumentProperties();

  /// slides API.
  List<PmlSlide> slides;

  /// master API.
  PmlMaster master;

  /// layouts API.
  List<PmlLayout> layouts;

  /// sections API.
  final List<PmlSection> sections;

  /// Native section import provenance and an optional pre-mutation guard.
  PmlSectionSource? sectionSource;

  /// properties API.
  OfficeDocumentProperties properties;

  /// package API.
  OpcPackage? package;

  /// slideWidth API.
  int slideWidth;

  /// slideHeight API.
  int slideHeight;

  /// Cascade: slide shape → layout placeholder → master defaults.
  String resolveText(PmlShape shape, PmlSlide slide) {
    if (shape.text.isNotEmpty) {
      return shape.text;
    }
    for (final PmlLayout layout in layouts) {
      if (layout.name != slide.layoutName) {
        continue;
      }
      if (layout.placeholderText.isNotEmpty) {
        return layout.placeholderText;
      }
      for (final PmlShape ph in layout.placeholders) {
        if (ph.name == shape.name && ph.text.isNotEmpty) {
          return ph.text;
        }
      }
    }
    for (final PmlShape ph in master.shapes) {
      if (ph.name == shape.name && ph.text.isNotEmpty) {
        return ph.text;
      }
    }
    return '';
  }

  /// Next or previous slide that is not [PmlSlide.hidden], or `null`.
  int? visibleIndexAfter(int from, {int direction = 1}) {
    if (direction == 0) {
      return null;
    }
    var index = from + direction;
    while (index >= 0 && index < slides.length) {
      if (!slides[index].hidden) {
        return index;
      }
      index += direction;
    }
    return null;
  }
}
