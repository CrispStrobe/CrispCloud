// SPDX-License-Identifier: MPL-2.0

/// Bounded, resolved Word-binary content for preview and conversion to a new
/// document. CP positions refer to original UTF-16 character positions; an end
/// position is exclusive. Paragraph endCp includes its terminating mark.
library;

import 'legacy_word_media_model.dart';

export 'legacy_word_media_model.dart';

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
    this.stories = const [],
    this.noteReferences = const [],
    this.commentReferences = const [],
    this.textboxReferences = const [],
    this.bookmarks = const [],
    this.fields = const [],
    this.numbering = const [],
    this.media = const LegacyWordMediaCatalog(),
    this.evenAndOddHeaders = false,
    this.defaultTabStopTwips,
  });
  final List<LegacyWordBlock> blocks;
  final List<LegacyWordSection> sections;
  final String plainText;

  /// Generated escaped markup with fixed tags/styles and no external assets.
  /// Hidden runs are omitted; insertions and deletions remain visibly marked.
  final String safeHtml;
  final List<LegacyWordWarning> warnings;

  /// Referenced auxiliary stories. Main content remains in [blocks], and the
  /// main-only [plainText]/[safeHtml] behavior is unchanged. All CPs below are
  /// global document UTF-16 positions, never offsets within a story.
  final List<LegacyWordStory> stories;
  final List<LegacyWordNoteReference> noteReferences;
  final List<LegacyWordCommentReference> commentReferences;
  final List<LegacyWordTextboxReference> textboxReferences;
  final List<LegacyWordBookmark> bookmarks;
  final List<LegacyWordField> fields;
  final List<LegacyWordNumberingDefinition> numbering;
  final LegacyWordMediaCatalog media;

  /// DopBase.fFacingPages. Stored even-page stories alone do not enable them.
  final bool evenAndOddHeaders;
  final int? defaultTabStopTwips;
}

enum LegacyWordStoryKind {
  header,
  footer,
  footnote,
  endnote,
  comment,
  textbox,
  headerTextbox,
  footnoteSeparator,
  footnoteContinuationSeparator,
  footnoteContinuationNotice,
  endnoteSeparator,
  endnoteContinuationSeparator,
  endnoteContinuationNotice,
}

enum LegacyWordHeaderFooterType { even, normal, first }

class LegacyWordStory {
  const LegacyWordStory({
    required this.id,
    required this.kind,
    required this.startCp,
    required this.endCp,
    required this.blocks,
    required this.plainText,
    required this.safeHtml,
    this.sectionIndex,
    this.headerFooterType,
  });
  final String id;
  final LegacyWordStoryKind kind;
  final int startCp;
  final int endCp;
  final List<LegacyWordBlock> blocks;
  final String plainText;
  final String safeHtml;
  final int? sectionIndex;
  final LegacyWordHeaderFooterType? headerFooterType;
}

class LegacyWordNoteReference {
  const LegacyWordNoteReference({
    required this.id,
    required this.anchorCp,
    required this.storyId,
    required this.endnote,
    this.autoNumbered = true,
    this.customMark,
    this.presentation = const LegacyWordMediaPresentation(),
  });
  final int id;
  final int anchorCp;
  final String storyId;
  final bool endnote;
  final bool autoNumbered;
  final String? customMark;
  final LegacyWordMediaPresentation presentation;
}

class LegacyWordCommentReference {
  const LegacyWordCommentReference({
    required this.id,
    required this.anchorCp,
    required this.storyId,
    this.rangeStartCp,
    this.rangeEndCp,
    this.author,
    this.initials,
    this.time,
    this.parentId,
    this.ink = false,
    this.presentation = const LegacyWordMediaPresentation(),
  });
  final int id;
  final int anchorCp;
  final String storyId;
  final int? rangeStartCp;
  final int? rangeEndCp;
  final String? author;
  final String? initials;

  /// Source wall-clock fields without a time-zone claim, as for run revisions.
  final DateTime? time;

  /// Earlier comment ID for a validated ATRDPost10 reply relationship.
  final int? parentId;
  final bool ink;
  final LegacyWordMediaPresentation presentation;
}

class LegacyWordTextboxReference {
  const LegacyWordTextboxReference({
    required this.id,
    required this.storyId,
    required this.inHeaderFooter,
    this.anchorCp,
    this.shapeId,
    this.nextTextboxId,
    this.chainLength = 1,
    this.anchors = const [],
  });
  final int id;
  final String storyId;
  final bool inHeaderFooter;
  final int? anchorCp;
  final int? shapeId;
  final int? nextTextboxId;
  final int chainLength;

  /// Actual OfficeArtClientTextbox chain indices, when available. A story is
  /// not duplicated for each shape and the library does not invent reflow.
  final List<LegacyWordTextboxAnchor> anchors;
}

class LegacyWordTextboxAnchor {
  const LegacyWordTextboxAnchor({
    required this.shapeId,
    required this.anchorCp,
    required this.chainIndex,
    this.nextShapeId,
  });
  final int shapeId;
  final int anchorCp;
  final int chainIndex;
  final int? nextShapeId;
}

class LegacyWordBookmark {
  const LegacyWordBookmark({
    required this.name,
    required this.startCp,
    required this.endCp,
    this.firstCell,
    this.lastCell,
  });
  final String name;
  final int startCp;
  final int endCp;
  final int? firstCell;
  final int? lastCell;
}

/// Original field syntax and cached display content. The library never
/// evaluates a field, resolves a URL, or updates a TOC/REF from external data.
class LegacyWordField {
  const LegacyWordField({
    required this.id,
    required this.storyId,
    required this.startCp,
    required this.endCp,
    required this.instruction,
    required this.storedResult,
    required this.type,
    this.separatorCp,
    this.parentId,
    this.locked = false,
    this.dirty = false,
    this.privateResult = false,
  });
  final int id;

  /// 'main' for the main story; otherwise an ID in LegacyWordDocument.stories.
  final String storyId;
  final int startCp;

  /// Exclusive position immediately after the field-end marker.
  final int endCp;
  final int? separatorCp;
  final int? parentId;
  final String instruction;
  final String storedResult;

  /// Uppercase leading field keyword, such as TOC, REF, PAGE or HYPERLINK.
  final String type;
  final bool locked;
  final bool dirty;
  final bool privateResult;
}

enum LegacyWordListSuffix { tab, space, nothing }

class LegacyWordNumberingDefinition {
  const LegacyWordNumberingDefinition({
    required this.id,
    required this.levels,
    this.sourceListId,
  });

  /// The absolute, one-based ilfo referenced by paragraph listId.
  final int id;

  /// Original lsid shared by list instances that can continue one sequence.
  final int? sourceListId;
  final List<LegacyWordNumberingLevel> levels;
}

class LegacyWordNumberingLevel {
  const LegacyWordNumberingLevel({
    required this.level,
    required this.format,
    required this.text,
    this.startAt = 1,
    this.suffix = LegacyWordListSuffix.tab,
    this.legal = false,
    this.restartAfterLevel,
    this.paragraphStyle = const LegacyWordParagraphStyle(),
    this.characterStyle = const LegacyWordCharacterStyle(),
    this.markerAlignment = LegacyWordAlignment.left,
  });
  final int level;

  /// A supported OOXML number-format identifier, never an invented fallback.
  final String format;

  /// %1..%9 placeholders; literal characters (including bullets) are retained.
  final String text;
  final int startAt;
  final LegacyWordListSuffix suffix;
  final bool legal;

  /// OOXML-compatible one-based restart threshold: zero never restarts;
  /// null uses the preceding level. This affects only the number sequence.
  final int? restartAfterLevel;
  final LegacyWordAlignment markerAlignment;
  final LegacyWordParagraphStyle paragraphStyle;
  final LegacyWordCharacterStyle characterStyle;
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
    this.shading,
  });
  final List<LegacyWordParagraph> paragraphs;
  final int? widthTwips;
  final bool mergeStart;
  final bool mergeContinue;
  final bool verticalMergeStart;
  final bool verticalMergeContinue;
  final LegacyWordShading? shading;
}

enum LegacyWordTabAlignment { left, center, right, decimal, bar, list }

enum LegacyWordTabLeader { none, dot, hyphen, underscore, heavy, middleDot }

class LegacyWordTabStop {
  const LegacyWordTabStop({
    required this.positionTwips,
    this.alignment = LegacyWordTabAlignment.left,
    this.leader = LegacyWordTabLeader.none,
  });
  final int positionTwips;
  final LegacyWordTabAlignment alignment;
  final LegacyWordTabLeader leader;
}

enum LegacyWordBorderSide { top, left, bottom, right, between, bar }

class LegacyWordBorder {
  const LegacyWordBorder({
    required this.style,
    required this.widthEighthPoints,
    this.rawType = 0,
    this.colorHex,
    this.spacingPoints = 0,
    this.shadow = false,
    this.frame = false,
  });

  /// A fixed OOXML ST_Border identifier, including none/nil resets.
  final String style;
  final int rawType;
  final int widthEighthPoints;
  final String? colorHex;
  final int spacingPoints;
  final bool shadow;
  final bool frame;
}

class LegacyWordShading {
  const LegacyWordShading({
    required this.pattern,
    this.rawPattern = 0,
    this.foregroundHex,
    this.backgroundHex,
  });

  /// A fixed OOXML ST_Shd identifier, or null for a valid legacy pattern
  /// without an OOXML equivalent. clear uses background, solid uses
  /// foreground; patterned shading retains both colors independently.
  final String? pattern;
  final int rawPattern;
  final String? foregroundHex;
  final String? backgroundHex;
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

  /// Original DTTM wall-clock fields: the binary format carries no time zone.
  /// A UTC DateTime is only a stable carrier; consumers must not add a claimed
  /// UTC offset or convert these source fields to another time zone.
  final DateTime? revisionTime;
}

class LegacyWordCharacterStyle {
  const LegacyWordCharacterStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.underlineStyle,
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

  /// A fixed OOXML ST_Underline name resolved from MS-DOC Kul. Null retains
  /// the bool-only API's single underline; explicit none clears a style.
  final String? underlineStyle;
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
      underlineStyle == other.underlineStyle &&
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
    underlineStyle,
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
    this.tabs = const [],
    this.borders = const {},
    this.shading,
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

  /// Resolved, ordered custom stops after applying inherited additions and
  /// deletions. Source tab characters remain unchanged in each run's text.
  final List<LegacyWordTabStop> tabs;
  final Map<LegacyWordBorderSide, LegacyWordBorder> borders;
  final LegacyWordShading? shading;
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
    this.titlePage = false,
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

  /// sprmSFTitlePage, independently of stored first-page header/footer text.
  final bool titlePage;
}
