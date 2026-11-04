import '../properties/wml_properties.dart';
import 'wml_document.dart';

/// A paragraph + run style that hosts can show in a gallery.
class WmlStyle {
  /// WmlStyle API.
  const WmlStyle({
    required this.id,
    required this.name,
    required this.nameAr,
    this.headingLevel,
    this.justification = WmlJustification.left,
    this.bold = false,
    this.italic = false,
    this.fontSizePoints = 11,
    this.color = '000000',
    this.spacingBefore = 0,
    this.spacingAfter = 8,
    this.font,
    this.csFont,
    this.basedOn,
    this.numId,
    this.ilvl,
    this.indent,
  });

  /// id API.
  final String id;

  /// name API.
  final String name;

  /// nameAr API.
  final String nameAr;

  /// headingLevel API.
  final int? headingLevel;

  /// justification API.
  final WmlJustification justification;

  /// bold API.
  final bool bold;

  /// italic API.
  final bool italic;

  /// fontSizePoints API.
  final double fontSizePoints;

  /// color API.
  final String color;

  /// spacingBefore API.
  final double spacingBefore;

  /// spacingAfter API.
  final double spacingAfter;

  /// ascii / hAnsi font written to `styles.xml`.
  final String? font;

  /// Complex-script font written to `styles.xml`.
  final String? csFont;

  /// Parent style id (`w:basedOn`), if any.
  final String? basedOn;

  /// List numbering instance from the style's `w:numPr` (`0` turns a list
  /// off).
  final int? numId;

  /// List level from the style's `w:numPr`.
  final int? ilvl;

  /// Paragraph indents from the style's `w:ind`.
  final WmlIndent? indent;

  /// label API.
  String label({required bool arabic}) => arabic ? nameAr : name;
}

/// Built-in Word styles and apply / inspect helpers.
abstract final class WordStyles {
  /// catalog API.
  static const List<WmlStyle> catalog = <WmlStyle>[
    WmlStyle(
      id: 'Normal',
      name: 'Normal',
      nameAr: 'عادي',
      font: 'Arial',
      csFont: 'Arial',
    ),
    WmlStyle(
      id: 'Title',
      name: 'Title',
      nameAr: 'عنوان',
      fontSizePoints: 28,
      bold: true,
      spacingAfter: 12,
    ),
    WmlStyle(
      id: 'Subtitle',
      name: 'Subtitle',
      nameAr: 'عنوان فرعي',
      fontSizePoints: 14,
      italic: true,
      color: '5B5B5B',
    ),
    WmlStyle(
      id: 'Heading1',
      name: 'Heading 1',
      nameAr: 'عنوان 1',
      headingLevel: 1,
      fontSizePoints: 16,
      bold: true,
      spacingBefore: 12,
      spacingAfter: 6,
    ),
    WmlStyle(
      id: 'Heading2',
      name: 'Heading 2',
      nameAr: 'عنوان 2',
      headingLevel: 2,
      fontSizePoints: 13,
      bold: true,
      spacingBefore: 10,
      spacingAfter: 4,
    ),
    WmlStyle(
      id: 'Heading3',
      name: 'Heading 3',
      nameAr: 'عنوان 3',
      headingLevel: 3,
      fontSizePoints: 12,
      bold: true,
    ),
    WmlStyle(
      id: 'Quote',
      name: 'Quote',
      nameAr: 'اقتباس',
      italic: true,
      justification: WmlJustification.center,
      color: '2E75B6',
    ),
    WmlStyle(
      id: 'Caption',
      name: 'Caption',
      nameAr: 'تسمية توضيحية',
      italic: true,
      fontSizePoints: 10,
      color: '666666',
    ),
    WmlStyle(
      id: 'IntenseQuote',
      name: 'Intense Quote',
      nameAr: 'اقتباس مكثف',
      italic: true,
      bold: true,
      justification: WmlJustification.center,
    ),
  ];

  /// Styles loaded from `styles.xml` that are not in [catalog].
  static final List<WmlStyle> extras = <WmlStyle>[];

  /// all API.
  static Iterable<WmlStyle> get all sync* {
    yield* catalog;
    yield* extras;
  }

  /// byId API.
  static WmlStyle? byId(String id, {WmlDocument? document}) {
    if (document != null) {
      for (final WmlStyle style in document.styles) {
        if (style.id == id) {
          return style;
        }
      }
    }
    for (final WmlStyle style in all) {
      if (style.id == id) {
        return style;
      }
    }
    return null;
  }

  /// Resolves [basedOn] chain into an effective style (catalog + extras + doc).
  static WmlStyle resolve(
    String styleId, {
    WmlDocument? document,
    Set<String>? seen,
  }) {
    final Set<String> visited = seen ?? <String>{};
    if (!visited.add(styleId)) {
      return byId(styleId, document: document) ?? catalog.first;
    }
    final WmlStyle? style = byId(styleId, document: document);
    if (style == null) {
      return catalog.first;
    }
    final String? parentId = style.basedOn;
    if (parentId == null || parentId.isEmpty || parentId == styleId) {
      return style;
    }
    final WmlStyle parent = resolve(
      parentId,
      document: document,
      seen: visited,
    );
    return WmlStyle(
      id: style.id,
      name: style.name,
      nameAr: style.nameAr,
      headingLevel: style.headingLevel ?? parent.headingLevel,
      justification: style.justification,
      bold: style.bold || parent.bold,
      italic: style.italic || parent.italic,
      fontSizePoints: style.fontSizePoints,
      color: style.color != '000000' ? style.color : parent.color,
      spacingBefore: style.spacingBefore != 0
          ? style.spacingBefore
          : parent.spacingBefore,
      spacingAfter: style.spacingAfter != 8
          ? style.spacingAfter
          : parent.spacingAfter,
      font: style.font ?? parent.font,
      csFont: style.csFont ?? parent.csFont,
      basedOn: style.basedOn,
      numId: style.numId ?? parent.numId,
      ilvl: style.ilvl ?? parent.ilvl,
      indent: style.indent ?? parent.indent,
    );
  }

  /// apply API.
  static void apply(
    WmlParagraph paragraph,
    String styleId, {
    WmlDocument? document,
  }) {
    final WmlStyle style = resolve(styleId, document: document);
    paragraph.properties
      ..styleId = style.id
      ..headingLevel = style.headingLevel
      ..justification = style.justification
      ..spacingBefore = style.spacingBefore
      ..spacingAfter = style.spacingAfter;
    if (paragraph.inlines.whereType<WmlRun>().isEmpty) {
      paragraph.inlines.add(WmlRun());
    }
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      inline.properties
        ..bold = style.bold
        ..italic = style.italic
        ..fontSizeHalfPoints = (style.fontSizePoints * 2).round()
        ..color = style.color;
      if (style.font != null && style.font!.isNotEmpty) {
        inline.properties.asciiFont = style.font!;
      }
      if (style.csFont != null && style.csFont!.isNotEmpty) {
        inline.properties.csFont = style.csFont!;
      }
    }
  }

  /// Fills missing paragraph/run props from the paragraph's styleId.
  ///
  /// Runs in [notBold] / [notItalic] turned that toggle off themselves
  /// (`w:b w:val="0"`), so the style does not turn it back on.
  static void resolveOntoParagraph(
    WmlParagraph paragraph, {
    WmlDocument? document,
    Set<WmlRunProps> notBold = const <WmlRunProps>{},
    Set<WmlRunProps> notItalic = const <WmlRunProps>{},
  }) {
    final String? id = paragraph.properties.styleId;
    if (id == null || id.isEmpty) {
      return;
    }
    final WmlStyle style = resolve(id, document: document);
    paragraph.properties.headingLevel ??= style.headingLevel;
    if (paragraph.properties.numId == null && style.numId != null) {
      paragraph.properties
        ..numId = style.numId
        ..ilvl = style.ilvl ?? paragraph.properties.ilvl;
    }
    final WmlIndent own = paragraph.properties.indent;
    final WmlIndent? styled = style.indent;
    if (styled != null &&
        own.left == 0 &&
        own.right == 0 &&
        own.firstLine == 0 &&
        own.hanging == 0) {
      paragraph.properties.indent = styled;
    }
    if (paragraph.properties.spacingBefore == 0 && style.spacingBefore != 0) {
      paragraph.properties.spacingBefore = style.spacingBefore;
    }
    if (paragraph.properties.spacingAfter == 8 && style.spacingAfter != 8) {
      paragraph.properties.spacingAfter = style.spacingAfter;
    }
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is! WmlRun) {
        continue;
      }
      if (inline.properties.fontSizeHalfPoints == 22 &&
          style.fontSizePoints != 11) {
        inline.properties.fontSizeHalfPoints = (style.fontSizePoints * 2)
            .round();
      }
      if ((inline.properties.asciiFont == 'Calibri' ||
              inline.properties.asciiFont == 'Arial') &&
          style.font != null &&
          style.font!.isNotEmpty) {
        inline.properties.asciiFont = style.font!;
      }
      if (inline.properties.csFont == 'Arial' &&
          style.csFont != null &&
          style.csFont!.isNotEmpty) {
        inline.properties.csFont = style.csFont!;
      }
      if (style.bold && !notBold.contains(inline.properties)) {
        inline.properties.bold = true;
      }
      if (style.italic && !notItalic.contains(inline.properties)) {
        inline.properties.italic = true;
      }
      if (inline.properties.color == '000000' && style.color != '000000') {
        inline.properties.color = style.color;
      }
    }
  }

  /// ofParagraph API.
  static WmlStyle ofParagraph(WmlParagraph paragraph, {WmlDocument? document}) {
    final String? id = paragraph.properties.styleId;
    if (id != null && id.isNotEmpty) {
      return resolve(id, document: document);
    }
    final int? level = paragraph.properties.headingLevel;
    if (level != null && level > 0) {
      return byId('Heading$level', document: document) ?? catalog.first;
    }
    return catalog.first;
  }
}
