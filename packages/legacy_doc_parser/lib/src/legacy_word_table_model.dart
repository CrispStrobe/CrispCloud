// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_model.dart';

enum LegacyWordTableCondition {
  firstRow,
  lastRow,
  firstCol,
  lastCol,
  band1Vert,
  band2Vert,
  band1Horz,
  band2Horz,
  neCell,
  nwCell,
  seCell,
  swCell,
}

enum LegacyWordTableBorderSide {
  top,
  left,
  bottom,
  right,
  insideH,
  insideV,
  tl2br,
  tr2bl,
}

enum LegacyWordCellAlignment { top, center, bottom }

enum LegacyWordTableAnchor { text, margin, page }

enum LegacyWordTableHorizontalPlacement { left, center, right, inside, outside }

enum LegacyWordTableVerticalPlacement {
  inline,
  top,
  center,
  bottom,
  inside,
  outside,
}

/// Floating-table geometry. Each axis has either a relative placement or an
/// absolute offset in twips. These are physical positions, independent of RTL.
class LegacyWordTablePosition {
  const LegacyWordTablePosition({
    this.horizontalAnchor = LegacyWordTableAnchor.text,
    this.verticalAnchor = LegacyWordTableAnchor.margin,
    this.horizontalPlacement,
    this.verticalPlacement,
    this.horizontalOffsetTwips,
    this.verticalOffsetTwips,
    this.leftFromTextTwips = 0,
    this.rightFromTextTwips = 0,
    this.topFromTextTwips = 0,
    this.bottomFromTextTwips = 0,
    this.allowOverlap = true,
  });
  final LegacyWordTableAnchor horizontalAnchor, verticalAnchor;
  final LegacyWordTableHorizontalPlacement? horizontalPlacement;
  final LegacyWordTableVerticalPlacement? verticalPlacement;
  final int? horizontalOffsetTwips, verticalOffsetTwips;
  final int leftFromTextTwips, rightFromTextTwips;
  final int topFromTextTwips, bottomFromTextTwips;
  final bool allowOverlap;
}

/// The five text flow modes defined by MS-DOC TextFlow, using native XML names.
enum LegacyWordCellTextDirection { lrTb, tbRl, btLr, lrTbV, tbRlV }

/// MS-DOC Fts units for a preferred table/cell width. Percentages use 1/50th
/// of a percent; twips are 1/20th of a point. Nil and auto remain distinct.
enum LegacyWordTableWidthUnit { nil, auto, percent, twips }

class LegacyWordTableWidth {
  const LegacyWordTableWidth({required this.unit, this.value = 0});
  final LegacyWordTableWidthUnit unit;
  final int value;
}

/// A supported set of cell properties. Null and absent entries inherit.
class LegacyWordTableCellFormat {
  const LegacyWordTableCellFormat({
    this.shading,
    this.borders = const {},
    this.verticalAlignment,
    bool? noWrap,
    this.preferredWidth,
    this.margins = const {},
    this.textDirection,
    this.fitText,
    this.hideMark,
  }) : noWrapPreference = noWrap;
  final LegacyWordShading? shading;
  final Map<LegacyWordTableBorderSide, LegacyWordBorder> borders;
  final LegacyWordCellAlignment? verticalAlignment;

  /// The source preference before preferred-width context is evaluated.
  /// Keeping this separate permits a later TCellWidth to reactivate it.
  final bool? noWrapPreference;

  /// A dxa preferred width suppresses the binary single-line preference.
  /// It does not change the source preference retained above.
  bool? get noWrap => noWrapPreference == null
      ? null
      : preferredWidth?.unit == LegacyWordTableWidthUnit.twips
      ? false
      : noWrapPreference;

  /// Preferred width is independent of the physical grid interval retained
  /// by LegacyWordTableCell.widthTwips.
  final LegacyWordTableWidth? preferredWidth;
  final LegacyWordCellTextDirection? textDirection;
  final bool? fitText;
  final bool? hideMark;

  /// Missing sides inherit; a present null retains an explicit nil width.
  final Map<LegacyWordBorderSide, int?> margins;
}

/// Properties explicitly specified by a table-style paragraph difference.
/// The mask distinguishes an absent property from an explicit default value.
enum LegacyWordTableParagraphProperty {
  alignment,
  leftIndent,
  rightIndent,
  firstIndent,
  before,
  after,
  lineSpacing,
  keepNext,
  keepTogether,
  pageBreakBefore,
  tabs,
  borders,
  shading,
  outline,
  widowControl,
  suppressAutoHyphens,
  suppressLineNumbers,
  contextualSpacing,
  mirrorIndents,
  rightToLeft,
  spaceBeforeAuto,
  spaceAfterAuto,
  kinsoku,
  wordWrap,
  overflowPunctuation,
  autoSpaceEastAsianLatin,
  autoSpaceEastAsianNumbers,
}

enum LegacyWordTableCharacterProperty {
  bold,
  italic,
  underline,
  strike,
  doubleStrike,
  smallCaps,
  allCaps,
  hidden,
  fontIndex,
  eastAsianFontIndex,
  nonAsciiFontIndex,
  complexScriptFontIndex,
  fontSize,
  color,
  highlight,
  verticalAlign,
  position,
  spacing,
  kerning,
}

/// Supported native text differences, with explicit source-property masks.
/// The style objects contain resolved values only for properties in the masks.
class LegacyWordTableTextFormat {
  const LegacyWordTableTextFormat({
    this.paragraph = const LegacyWordParagraphStyle(),
    this.character = const LegacyWordCharacterStyle(),
    this.paragraphProperties = const {},
    this.characterProperties = const {},
    this.relativeCharacterToggles = const {},
  });
  final LegacyWordParagraphStyle paragraph;
  final LegacyWordCharacterStyle character;
  final Set<LegacyWordTableParagraphProperty> paragraphProperties;
  final Set<LegacyWordTableCharacterProperty> characterProperties;

  /// Original 0x80/0x81 toggle operands, retained for conversion evidence.
  /// Resolved cell text is authoritative when different conditions overlap.
  final Map<LegacyWordTableCharacterProperty, int> relativeCharacterToggles;
}

/// Native table-style identity and supported cell and text conditional rules.
class LegacyWordTableStyle {
  const LegacyWordTableStyle({
    required this.id,
    required this.name,
    this.basedOn,
    this.rowBandSize,
    this.columnBandSize,
    this.cell = const LegacyWordTableCellFormat(),
    this.conditions = const {},
    this.text = const LegacyWordTableTextFormat(),
    this.textConditions = const {},
  });
  final int id;
  final String name;
  final int? basedOn;
  final int? rowBandSize;
  final int? columnBandSize;
  final LegacyWordTableCellFormat cell;
  final Map<LegacyWordTableCondition, LegacyWordTableCellFormat> conditions;
  final LegacyWordTableTextFormat text;
  final Map<LegacyWordTableCondition, LegacyWordTableTextFormat> textConditions;
}
