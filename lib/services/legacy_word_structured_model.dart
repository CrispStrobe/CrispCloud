/// Bounded, resolved Word-binary content for preview and conversion to a new
/// document. CP positions refer to original UTF-16 character positions; an end
/// position is exclusive. Paragraph endCp includes its terminating mark.
library;

enum LegacyWordWarning {
  unsupportedFormatting,
  numberingNotReconstructed,
  nestedTablesFlattened,
  fieldsUseStoredResults,
  imagesOmitted,
  floatingObjectsOmitted,
  headersFootersOmitted,
  notesOmitted,
  commentsOmitted,
  textboxesOmitted,
  macrosOmitted,
  revisionMetadataIncomplete,
}

enum LegacyWordAlignment { left, center, right, justify, distribute }

enum LegacyWordVerticalAlignment { baseline, superscript, subscript }

enum LegacyWordSectionBreak {
  continuous,
  newColumn,
  newPage,
  evenPage,
  oddPage,
}

class LegacyWordDocument {
  const LegacyWordDocument({
    required this.blocks,
    required this.sections,
    required this.plainText,
    required this.safeHtml,
    this.warnings = const [],
  });
  final List<LegacyWordBlock> blocks;
  final List<LegacyWordSection> sections;
  final String plainText;

  /// Generated escaped markup with fixed tags/styles and no external assets.
  /// Hidden runs are omitted; insertions and deletions remain visibly marked.
  final String safeHtml;
  final List<LegacyWordWarning> warnings;
}

sealed class LegacyWordBlock {
  const LegacyWordBlock({required this.startCp, required this.endCp});
  final int startCp;
  final int endCp;
}

class LegacyWordParagraph extends LegacyWordBlock {
  const LegacyWordParagraph({
    required super.startCp,
    required super.endCp,
    required this.runs,
    this.style = const LegacyWordParagraphStyle(),
  });
  final List<LegacyWordRun> runs;
  final LegacyWordParagraphStyle style;
}

class LegacyWordTable extends LegacyWordBlock {
  const LegacyWordTable({
    required super.startCp,
    required super.endCp,
    required this.rows,
  });
  final List<LegacyWordTableRow> rows;
}

class LegacyWordTableRow {
  const LegacyWordTableRow({required this.cells, this.isHeader = false});
  final List<LegacyWordTableCell> cells;
  final bool isHeader;
}

class LegacyWordTableCell {
  const LegacyWordTableCell({
    required this.paragraphs,
    this.widthTwips,
    this.mergeStart = false,
    this.mergeContinue = false,
    this.verticalMergeStart = false,
    this.verticalMergeContinue = false,
  });
  final List<LegacyWordParagraph> paragraphs;
  final int? widthTwips;
  final bool mergeStart;
  final bool mergeContinue;
  final bool verticalMergeStart;
  final bool verticalMergeContinue;
}

class LegacyWordRun {
  const LegacyWordRun({
    required this.startCp,
    required this.endCp,
    required this.text,
    this.style = const LegacyWordCharacterStyle(),
    this.inserted = false,
    this.deleted = false,
    this.revisionAuthor,
    this.revisionTime,
  });
  final int startCp;
  final int endCp;

  /// Paragraph/cell/section terminators are removed. Tabs remain '\t', soft
  /// line breaks are '\n', and explicit non-section page breaks are '\f'.
  /// Text marked as inserted or deleted is retained, never silently accepted.
  final String text;
  final LegacyWordCharacterStyle style;
  final bool inserted;
  final bool deleted;
  final String? revisionAuthor;
  final DateTime? revisionTime;
}

class LegacyWordCharacterStyle {
  const LegacyWordCharacterStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.doubleStrike = false,
    this.smallCaps = false,
    this.allCaps = false,
    this.hidden = false,
    this.fontName,
    this.fontSizeHalfPoints,
    this.colorHex,
    this.highlightHex,
    this.verticalAlign = LegacyWordVerticalAlignment.baseline,
    this.positionHalfPoints,
    this.spacingTwips,
  });
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool doubleStrike;
  final bool smallCaps;
  final bool allCaps;
  final bool hidden;
  final String? fontName;
  final int? fontSizeHalfPoints;

  /// Six hexadecimal RGB digits, without '#'; null means automatic/unspecified.
  final String? colorHex;
  final String? highlightHex;
  final LegacyWordVerticalAlignment verticalAlign;
  final int? positionHalfPoints;
  final int? spacingTwips;

  @override
  bool operator ==(Object other) =>
      other is LegacyWordCharacterStyle &&
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      strike == other.strike &&
      doubleStrike == other.doubleStrike &&
      smallCaps == other.smallCaps &&
      allCaps == other.allCaps &&
      hidden == other.hidden &&
      fontName == other.fontName &&
      fontSizeHalfPoints == other.fontSizeHalfPoints &&
      colorHex == other.colorHex &&
      highlightHex == other.highlightHex &&
      verticalAlign == other.verticalAlign &&
      positionHalfPoints == other.positionHalfPoints &&
      spacingTwips == other.spacingTwips;
  @override
  int get hashCode => Object.hash(
    bold,
    italic,
    underline,
    strike,
    doubleStrike,
    smallCaps,
    allCaps,
    hidden,
    fontName,
    fontSizeHalfPoints,
    colorHex,
    highlightHex,
    verticalAlign,
    positionHalfPoints,
    spacingTwips,
  );
}

class LegacyWordParagraphStyle {
  const LegacyWordParagraphStyle({
    this.styleIndex = 0,
    this.styleName,
    this.headingLevel,
    this.alignment = LegacyWordAlignment.left,
    this.leftIndentTwips = 0,
    this.rightIndentTwips = 0,
    this.firstLineIndentTwips = 0,
    this.spaceBeforeTwips = 0,
    this.spaceAfterTwips = 0,
    this.lineSpacingValue,
    this.lineSpacingMultiple = false,
    this.keepNext = false,
    this.keepTogether = false,
    this.pageBreakBefore = false,
    this.listId,
    this.listLevel,
  });
  final int styleIndex;
  final String? styleName;

  /// Heading levels 1–9; null denotes body text.
  final int? headingLevel;
  final LegacyWordAlignment alignment;
  final int leftIndentTwips;
  final int rightIndentTwips;
  final int firstLineIndentTwips;
  final int spaceBeforeTwips;
  final int spaceAfterTwips;

  /// For multiple=true, 240 denotes one line. Otherwise the absolute value is
  /// twips, negative means exact spacing and positive means at least.
  final int? lineSpacingValue;
  final bool lineSpacingMultiple;
  final bool keepNext;
  final bool keepTogether;
  final bool pageBreakBefore;

  /// Original list identifiers are retained for diagnostics, not synthesized
  /// as a different numbering scheme when definitions are unsupported.
  final int? listId;
  final int? listLevel;
}

class LegacyWordSection {
  const LegacyWordSection({
    required this.startCp,
    required this.endCp,
    this.pageWidthTwips,
    this.pageHeightTwips,
    this.marginTopTwips,
    this.marginBottomTwips,
    this.marginLeftTwips,
    this.marginRightTwips,
    this.gutterTwips,
    this.headerDistanceTwips,
    this.footerDistanceTwips,
    this.columnsSpaceTwips,
    this.landscape = false,
    this.columns = 1,
    this.breakKind = LegacyWordSectionBreak.newPage,
  });
  final int startCp;
  final int endCp;
  final int? pageWidthTwips;
  final int? pageHeightTwips;
  final int? marginTopTwips;
  final int? marginBottomTwips;
  final int? marginLeftTwips;
  final int? marginRightTwips;
  final int? gutterTwips;
  final int? headerDistanceTwips;
  final int? footerDistanceTwips;
  final int? columnsSpaceTwips;
  final bool landscape;
  final int columns;
  final LegacyWordSectionBreak breakKind;
}
