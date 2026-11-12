// SPDX-License-Identifier: MPL-2.0

/// Bounded, resolved Word-binary content for preview and conversion to a new
/// document. CP positions refer to original UTF-16 character positions; an end
/// position is exclusive. Paragraph endCp includes its terminating mark.
library;

import 'dart:typed_data';
import 'legacy_word_note_settings.dart';

import 'legacy_word_compatibility.dart';
import 'legacy_word_media_model.dart';
import 'legacy_word_layout_model.dart';

export 'legacy_word_compatibility.dart';
export 'legacy_word_media_model.dart';
export 'legacy_word_layout_model.dart';
export 'legacy_word_note_settings.dart';

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
  recoveredTableStoryBoundary,
  recoveredEmptySection,

  /// A declared-one FTXBXS disagreed with a complete explicit OfficeArt chain.
  recoveredTextboxChainLength,

  /// A cb=0 PAPX had one uninterpreted final byte after complete properties.
  recoveredNonconformingProperties,

  /// Note defaults recovered from the identified 610-byte LibreOffice DOP.
  recoveredLegacyNoteSettings,

  /// The final main-story CR is present but absent from the last CHPX range.
  /// Its paragraph mark stays null; its formatting and revision state are
  /// unknown rather than inherited from a preceding character.
  terminalMarkFormattingUnavailable,
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
    this.compatibility = const LegacyWordCompatibility.unspecified(),
    this.footnotes = const LegacyWordFootnoteSettings(),
    this.endnotes = const LegacyWordEndnoteSettings(),
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
  final LegacyWordCompatibility compatibility;
  final LegacyWordFootnoteSettings footnotes;
  final LegacyWordEndnoteSettings endnotes;
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
    this.referenceStyle,
    this.markerStyle,
    this.presentation = const LegacyWordMediaPresentation(),
  });
  final int id;
  final int anchorCp;
  final String storyId;
  final bool endnote;
  final bool autoNumbered;
  final String? customMark;

  /// Independent source formatting at the body reference and note marker.
  final LegacyWordCharacterStyle? referenceStyle;
  final LegacyWordCharacterStyle? markerStyle;
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
    this.sourceRecord,
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

  /// Comment ID for a validated reply relationship. Binary AtrdExtra records
  /// use pre-order; the public writer also accepts a parent listed later.
  final int? parentId;
  final bool ink;
  final LegacyWordCommentSourceRecord? sourceRecord;
  final LegacyWordMediaPresentation presentation;
}

/// Original 18-byte ATRDPost10 record, retained as immutable source evidence.
/// The ink flag is metadata; this record does not itself contain pen strokes.
class LegacyWordCommentSourceRecord {
  LegacyWordCommentSourceRecord({
    required Uint8List bytes,
    required this.tableOffset,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView() {
    if (bytes.length != 18 || tableOffset < 0) {
      throw const FormatException('Invalid Word extended comment evidence.');
    }
  }
  final Uint8List bytes;
  final int tableOffset;
  int get rawDate => ByteData.sublistView(bytes).getUint32(0, Endian.little);
  int get depth => ByteData.sublistView(bytes).getUint32(6, Endian.little);
  int get relativeParent =>
      ByteData.sublistView(bytes).getInt32(10, Endian.little);
  bool get ink => (bytes[14] & 2) != 0;
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
    this.declaredChainLength,
    this.anchors = const [],
  });
  final int id;
  final String storyId;
  final bool inHeaderFooter;
  final int? anchorCp;
  final int? shapeId;
  final int? nextTextboxId;
  final int chainLength;

  /// Original FTXBXS count when available. This can differ from [chainLength]
  /// only after a reported, fully linked-chain interoperability recovery.
  final int? declaredChainLength;

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
    this.startOverrides = const {},
    this.continuationOf,
  });

  /// The absolute, one-based ilfo referenced by paragraph listId.
  final int id;

  /// Original lsid shared by list instances that can continue one sequence.
  final int? sourceListId;

  /// Another instance whose number sequence this instance continues. The
  /// parser sets this only for a shared lsid with no LFO level overrides.
  /// Both definitions retain their original ids and share the same levels.
  final int? continuationOf;
  final List<LegacyWordNumberingLevel> levels;

  /// Explicit LFOLVL start/restart values, distinct from a level's default.
  /// A formatting override with fStartAt uses its own LVL start value.
  final Map<int, int> startOverrides;
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
    this.formattingRevision,
    this.mark,
    this.revisionSaveId,
  });
  final List<LegacyWordRun> runs;
  final LegacyWordParagraphStyle style;
  final LegacyWordParagraphFormattingRevision? formattingRevision;

  /// Properties of the terminating paragraph mark, independently of text.
  /// Deleting this mark does not delete the paragraph contents.
  final LegacyWordParagraphMark? mark;
  final int? revisionSaveId;
}

class LegacyWordTable extends LegacyWordBlock {
  const LegacyWordTable({
    required super.startCp,
    required super.endCp,
    required this.rows,
    this.styleId,
    this.styleName,
    this.look = const LegacyWordTableLook(),
    this.rightToLeft = false,
    this.alignment = LegacyWordAlignment.left,
    this.indentTwips,
    this.autoFit = false,
  });
  final List<LegacyWordTableRow> rows;
  final int? styleId;
  final String? styleName;
  final LegacyWordTableLook look;
  final bool rightToLeft;
  final LegacyWordAlignment alignment;
  final int? indentTwips;
  final bool autoFit;
}

class LegacyWordTableRow {
  const LegacyWordTableRow({
    required this.cells,
    this.isHeader = false,
    this.endCp,
    this.cantSplit = false,
    this.heightTwips,
    this.exactHeight = false,
    int? indentTwips,
    int? originTwips,
  }) : indentTwips = indentTwips ?? originTwips;
  final List<LegacyWordTableCell> cells;
  final bool isHeader;
  final int? endCp;
  final bool cantSplit;
  final int? heightTwips;
  final bool exactHeight;
  final int? indentTwips;

  /// Logical outer edge retained independently of the leading cell margin.
  /// This is the compatibility name for [indentTwips], defaulting to zero.
  int get originTwips => indentTwips ?? 0;
}

/// Active TLP conditional regions; historical autoformat flags are not
/// confused with the current style. Logical first/last columns follow RTL.
class LegacyWordTableLook {
  const LegacyWordTableLook({this.flags = 0});
  final int flags;
  bool get firstRow => flags & 0x20 != 0;
  bool get lastRow => flags & 0x40 != 0;
  bool get firstColumn => flags & 0x80 != 0;
  bool get lastColumn => flags & 0x100 != 0;
  bool get noRowBands => flags & 0x200 != 0;
  bool get noColumnBands => flags & 0x400 != 0;
}

enum LegacyWordCellVerticalAlignment { top, center, bottom }

enum LegacyWordCellBorderSide {
  top,
  left,
  bottom,
  right,
  diagonalDown,
  diagonalUp,
}

class LegacyWordTableCell {
  const LegacyWordTableCell({
    required this.paragraphs,
    List<LegacyWordBlock>? blocks,
    this.widthTwips,
    this.mergeStart = false,
    this.mergeContinue = false,
    this.verticalMergeStart = false,
    this.verticalMergeContinue = false,
    this.shading,
    this.borders = const {},
    this.verticalAlignment = LegacyWordCellVerticalAlignment.top,
    this.conditionalFlags = 0,
    this.marginsTwips = const {},
  }) : _blocks = blocks;

  /// Direct paragraphs in this cell. [blocks] retains their order relative to
  /// nested tables; consumers rendering complete content should use [blocks].
  final List<LegacyWordParagraph> paragraphs;
  final List<LegacyWordBlock>? _blocks;
  List<LegacyWordBlock> get blocks => _blocks ?? paragraphs;
  final int? widthTwips;
  final bool mergeStart;
  final bool mergeContinue;
  final bool verticalMergeStart;
  final bool verticalMergeContinue;
  final LegacyWordShading? shading;
  final Map<LegacyWordCellBorderSide, LegacyWordBorder> borders;
  final LegacyWordCellVerticalAlignment verticalAlignment;

  /// Matched CNFC regions before direct paragraph/character/cell overrides.
  final int conditionalFlags;

  /// Logical cell margins; only top/left/bottom/right are valid keys.
  final Map<LegacyWordCellBorderSide, int> marginsTwips;
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
    this.insertionRevision,
    this.deletionRevision,
    this.formattingRevision,
    this.formattingSaveId,
  });
  final int startCp;
  final int endCp;

  /// Paragraph/cell/section terminators are removed. Tabs remain '\t', soft
  /// line breaks are '\n', page breaks are '\f', and column breaks '\u000e'.
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

  /// Separate provenance for overlapping insertion and deletion revisions.
  /// The older revisionAuthor/revisionTime pair remains a compatibility view.
  final LegacyWordRevisionInfo? insertionRevision;
  final LegacyWordRevisionInfo? deletionRevision;
  final LegacyWordCharacterFormattingRevision? formattingRevision;
  final int? formattingSaveId;
}

/// Source revision metadata. A missing name/date remains missing; the parser
/// never invents an author or converts the source wall-clock timestamp to UTC.
class LegacyWordRevisionInfo {
  const LegacyWordRevisionInfo({
    this.author,
    this.time,
    this.authorIndex,
    this.rawDate,
    this.saveId,
    this.reason,
  });
  final String? author;
  final DateTime? time;
  final int? authorIndex;
  final int? rawDate;
  final int? saveId;

  /// Original AutoFormat reason code, when recorded in the binary source.
  final int? reason;

  @override
  bool operator ==(Object other) =>
      other is LegacyWordRevisionInfo &&
      author == other.author &&
      time == other.time &&
      authorIndex == other.authorIndex &&
      rawDate == other.rawDate &&
      saveId == other.saveId &&
      reason == other.reason;
  @override
  int get hashCode =>
      Object.hash(author, time, authorIndex, rawDate, saveId, reason);
}

class LegacyWordCharacterFormattingRevision {
  const LegacyWordCharacterFormattingRevision({
    required this.previousStyle,
    this.revision = const LegacyWordRevisionInfo(),
    this.marked = true,
    this.previousPropertiesComplete = true,
  });

  /// Resolved properties immediately before sprmCWall. Null means the file
  /// supplied a revision mark without its previous-formatting snapshot.
  final LegacyWordCharacterStyle? previousStyle;
  final LegacyWordRevisionInfo revision;
  final bool marked;
  final bool previousPropertiesComplete;

  @override
  bool operator ==(Object other) =>
      other is LegacyWordCharacterFormattingRevision &&
      previousStyle == other.previousStyle &&
      revision == other.revision &&
      marked == other.marked &&
      previousPropertiesComplete == other.previousPropertiesComplete;
  @override
  int get hashCode =>
      Object.hash(previousStyle, revision, marked, previousPropertiesComplete);
}

class LegacyWordParagraphFormattingRevision {
  const LegacyWordParagraphFormattingRevision({
    required this.previousStyle,
    this.revision = const LegacyWordRevisionInfo(),
    this.marked = true,
    this.previousPropertiesComplete = true,
  });
  final LegacyWordParagraphStyle? previousStyle;
  final LegacyWordRevisionInfo revision;
  final bool marked;
  final bool previousPropertiesComplete;
}

class LegacyWordParagraphMark {
  const LegacyWordParagraphMark({
    this.style = const LegacyWordCharacterStyle(),
    this.inserted = false,
    this.deleted = false,
    this.insertionRevision,
    this.deletionRevision,
    this.formattingRevision,
    this.formattingSaveId,
  });
  final LegacyWordCharacterStyle style;
  final bool inserted;
  final bool deleted;
  final LegacyWordRevisionInfo? insertionRevision;
  final LegacyWordRevisionInfo? deletionRevision;
  final LegacyWordCharacterFormattingRevision? formattingRevision;
  final int? formattingSaveId;
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
    this.kerningThresholdHalfPoints = 0,
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

  /// Resolved font-size threshold for pair kerning in half-points. Zero
  /// disables kerning, including the MS-DOC default. Positive source values
  /// range from 1 to 3276; kerning applies when the font size reaches that
  /// threshold.
  final int kerningThresholdHalfPoints;

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
      kerningThresholdHalfPoints == other.kerningThresholdHalfPoints &&
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
    kerningThresholdHalfPoints,
    colorHex,
    highlightHex,
    verticalAlign,
    positionHalfPoints,
    spacingTwips,
  );
}

class LegacyWordParagraphStyle {
  const LegacyWordParagraphStyle({
    this.layout = const LegacyWordParagraphLayout(),
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
  final LegacyWordParagraphLayout layout;
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
    this.layout = const LegacyWordSectionLayout(),
    this.formattingRevision,
    this.revisionSaveId,
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
    this.footnotes,
    this.endnotes,
    this.suppressEndnotes = false,
  });
  final LegacyWordSectionLayout layout;

  /// One previous section-property state captured by sprmSWall.
  final LegacyWordSectionFormattingRevision? formattingRevision;
  final int? revisionSaveId;
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

  /// Resolved section overrides. Null inherits the document note settings.
  final LegacyWordFootnoteSettings? footnotes;
  final LegacyWordEndnoteSettings? endnotes;

  /// sprmSFEndnote=0. Only applies when endnotes use end-of-section placement.
  final bool suppressEndnotes;
}

class LegacyWordSectionFormattingRevision {
  const LegacyWordSectionFormattingRevision({
    this.previousSection,
    this.revision = const LegacyWordRevisionInfo(),
    this.marked = true,
    this.previousPropertiesComplete = true,
  });

  /// Supported section properties immediately before sprmSWall, with the
  /// original source range. It has no recursively reconstructed history.
  final LegacyWordSection? previousSection;
  final LegacyWordRevisionInfo revision;
  final bool marked;
  final bool previousPropertiesComplete;
}
