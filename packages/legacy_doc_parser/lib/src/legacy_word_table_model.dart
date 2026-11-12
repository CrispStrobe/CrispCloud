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

/// A supported set of cell properties. Null and absent entries inherit.
class LegacyWordTableCellFormat {
  const LegacyWordTableCellFormat({
    this.shading,
    this.borders = const {},
    this.verticalAlignment,
    this.noWrap,
    this.margins = const {},
  });
  final LegacyWordShading? shading;
  final Map<LegacyWordTableBorderSide, LegacyWordBorder> borders;
  final LegacyWordCellAlignment? verticalAlignment;
  final bool? noWrap;

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
  fontSize,
  color,
  highlight,
  verticalAlign,
  position,
  spacing,
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
