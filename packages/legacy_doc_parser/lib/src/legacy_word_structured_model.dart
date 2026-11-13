// SPDX-License-Identifier: MPL-2.0

/// Bounded, resolved Word-binary content for preview and conversion to a new
/// document. CP positions refer to original UTF-16 character positions; an end
/// position is exclusive. Paragraph endCp includes its terminating mark.
library;

import 'dart:typed_data';

import 'legacy_word_compatibility.dart';
import 'legacy_word_media_model.dart';
import 'legacy_word_layout_model.dart';

export 'legacy_word_compatibility.dart';
export 'legacy_word_media_model.dart';
export 'legacy_word_revision_model.dart';
export 'legacy_word_layout_model.dart';

part 'legacy_word_table_model.dart';

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

  /// The final main-story CR is missing from exact CHPX physical/bin bounds.
  terminalMarkFormattingUnavailable,

  /// A main-textbox spare range ended at the exact whole-document sentinel.
  /// Every real range remained bounded by the textbox story length.
  recoveredGlobalTextboxSentinel,

  /// A single-frame header text range is shared by separate normal/first
  /// header occurrences, corroborated by their stored shapes and CPs.
  recoveredHeaderTextboxAlias,

  /// Two separate normal/first-header SPA occurrences share one OfficeArt
  /// shape. Their actual shape ID and individual anchor CPs are retained.
  recoveredHeaderTextboxShapeAlias,

  /// A note format is unknown or requires a disclosed decimal fallback.
  /// The original MSONFC code remains available on the note numbering model.
  unsupportedNoteNumberFormat,

  /// One native singleton textbox story was reused by separate header/footer
  /// variants, each with its own index-zero shape and no continuation link.
  recoveredSharedHeaderTextbox,

  /// An invalid old nil diagonal border was immediately superseded by the
  /// exact matching valid modern operation; all cell extents stayed bounded.
  recoveredLegacyDiagonalBorder,

  /// A validated singleton textbox story has no matching main-story anchor.
  /// Its source shape identity and text are retained without inventing layout.
  recoveredUnpositionedTextbox,
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
    this.tableStyles = const [],
    this.media = const LegacyWordMediaCatalog(),
    this.evenAndOddHeaders = false,
    this.defaultTabStopTwips,
    this.compatibility = const LegacyWordCompatibility.unspecified(),
    this.lineNumberStyle,
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
  final List<LegacyWordTableStyle> tableStyles;
  final LegacyWordMediaCatalog media;

  /// DopBase.fFacingPages. Stored even-page stories alone do not enable them.
  final bool evenAndOddHeaders;
  final int? defaultTabStopTwips;
  final LegacyWordCompatibility compatibility;

  /// Resolved character formatting of an explicitly stored built-in Line
  /// Number style (MS-DOC StdfBase.sti 40). Null preserves its absence; an
  /// ordinary style with the same display name does not define this value.
  final LegacyWordCharacterStyle? lineNumberStyle;
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
    this.headerAliases = const [],
    this.replicaAnchors = const [],
    this.placementUnresolved = false,
  });
  final int id;
  final String storyId;
  final bool inHeaderFooter;
  final int? anchorCp;
  final int? shapeId;
  final int? nextTextboxId;
  final int chainLength;

  /// Independently valid text was recovered without a matching FSPA anchor.
  /// Consumers must not infer a placement from another shape's textbox ID.
  final bool placementUnresolved;

  /// Original FTXBXS count when a nonconforming declared-one chain was
  /// recovered from agreeing OfficeArt indices and next-shape references.
  final int? declaredChainLength;

  /// Actual OfficeArtClientTextbox chain indices, when available. A story is
  /// not duplicated for each shape and the library does not invent reflow.
  final List<LegacyWordTextboxAnchor> anchors;

  /// Corroborated, separate header occurrences of a single-frame text range.
  /// These retain their source chain index zero and are not text-flow links.
  /// A shared source shape is distinguished by its original anchor CP.
  /// The converter revalidates the bounded normal/first-header recovery.
  final List<LegacyWordTextboxAnchor> headerAliases;

  /// Independent singleton placements of the same source text in distinct
  /// header/footer stories. These are not continuations of [anchors].
  final List<LegacyWordTextboxAnchor> replicaAnchors;
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
    this.displayRevision,
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
  final LegacyWordDisplayFieldRevision? displayRevision;
}

/// Tracked replacement of the cached result of a LISTNUM display field.
/// This is separate from a revision to the field's instruction or text runs.
class LegacyWordDisplayFieldRevision {
  LegacyWordDisplayFieldRevision({
    required this.original,
    this.revision = const LegacyWordRevisionInfo(),
    this.hidden = false,
    Uint8List? sourceRecord,
  }) : sourceRecord = sourceRecord == null
           ? null
           : Uint8List.fromList(sourceRecord).asUnmodifiableView() {
    if (original.length > 15 ||
        sourceRecord != null && sourceRecord.length != 39) {
      throw ArgumentError('Invalid Word display-field revision.');
    }
  }

  final String original;
  final LegacyWordRevisionInfo revision;

  /// Explicitly hidden source text or a field inside a private field result.
  /// Such history is retained as evidence and is not activated in native XML.
  final bool hidden;
  final Uint8List? sourceRecord;
}

enum LegacyWordListSuffix { tab, space, nothing }

class LegacyWordNumberingDefinition {
  const LegacyWordNumberingDefinition({
    required this.id,
    required this.levels,
    this.sourceListId,
    this.continuationOf,
    this.startOverrides = const {},
  });

  /// The absolute, one-based ilfo referenced by paragraph listId.
  final int id;

  /// Original lsid shared by list instances that can continue one sequence.
  final int? sourceListId;

  /// Another instance whose number sequence this instance continues. The
  /// parser sets this only for a shared lsid with no LFO level overrides.
  /// Both definitions retain their original ids and share the same levels.
  final int? continuationOf;

  /// Explicit LFOLVL start overrides, distinct from each resolved level's
  /// default. Formatting-only overrides can still share source LSID counters.
  final Map<int, int> startOverrides;
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
    this.formattingRevision,
    this.numberingRevision,
    this.mark,
    this.revisionSaveId,
  });
  final List<LegacyWordRun> runs;
  final LegacyWordParagraphStyle style;
  final LegacyWordParagraphFormattingRevision? formattingRevision;
  final LegacyWordNumberingRevision? numberingRevision;

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
    this.autoFit = false,
    this.rightToLeft = false,
    this.alignment = LegacyWordAlignment.left,
    this.position,
  });
  final List<LegacyWordTableRow> rows;
  final bool autoFit;
  final bool rightToLeft;

  /// Logical table alignment (left means its leading edge). Physical TJc90
  /// source values are resolved against the table direction during parsing.
  final LegacyWordAlignment alignment;

  /// Absolute positioning from the table's own MS-DOC properties. The next
  /// regular paragraph remains the anchor and remains editable content.
  final LegacyWordTablePosition? position;
}

class LegacyWordTableRow {
  const LegacyWordTableRow({
    required this.cells,
    this.isHeader = false,
    this.sourceHeaderRequest,
    this.formattingRevision,
    this.originTwips = 0,
    this.tableStyleId,
    this.styleOptions = 0x600,
    this.halfGapTwips = 0,
    this.heightTwips,
    this.cantSplit,
    this.borders = const {},
    this.defaultCellMargins = const {},
    this.alignment,
    this.autoFit,
  });
  final List<LegacyWordTableCell> cells;
  final bool isHeader;

  /// The source header instruction before applying the contiguous-prefix
  /// rule. A dormant request can become effective after a preceding row's
  /// header-property revision is rejected. Null uses [isHeader].
  final bool? sourceHeaderRequest;
  final LegacyWordTableRowFormattingRevision? formattingRevision;

  /// Logical left outer edge, including cell spacing, relative to the page's
  /// logical left margin. Negative values retain an outdent. Rows can differ.
  final int originTwips;
  final int? tableStyleId;

  /// Original Fatl options. Bits 5–8 enable edge rows/columns; bits 9–10
  /// disable horizontal/vertical banding. Unrelated auto-format bits survive.
  final int styleOptions;

  /// Source origin offset; it is not a cell margin.
  final int halfGapTwips;

  /// MS-DOC signed row height: positive is a minimum, negative is exact,
  /// and zero explicitly selects automatic height. Null means unspecified.
  final int? heightTwips;

  /// Null leaves the default ability to split a row across pages unchanged.
  final bool? cantSplit;

  /// Effective source row exceptions; null inherits the public table value.
  final LegacyWordAlignment? alignment;
  final bool? autoFit;

  /// Direct row-wide outer and interior border defaults. Cell borders whose
  /// type is none inherit; an explicit nil cell border suppresses the edge.
  final Map<LegacyWordTableBorderSide, LegacyWordBorder> borders;

  /// Row-wide source cell-padding defaults, including inherited table-style
  /// defaults, before per-cell or conditional overrides. Keeping these
  /// separate also preserves floating-table origins: a cell override does
  /// not replace the table's default padding in OOXML.
  final Map<LegacyWordBorderSide, int?> defaultCellMargins;
}

/// The bounded, native row properties represented by a table revision wall.
/// Header state is the instruction, before the contiguous-prefix rule.
class LegacyWordTableRowProperties {
  const LegacyWordTableRowProperties({
    this.heightTwips,
    this.cantSplit,
    this.isHeader = false,
  });
  final int? heightTwips;
  final bool? cantSplit;
  final bool isHeader;
}

class LegacyWordTableRowFormattingRevision {
  LegacyWordTableRowFormattingRevision({
    required this.previousProperties,
    this.revision = const LegacyWordRevisionInfo(),
    this.marked = true,
    this.previousPropertiesComplete = true,
    this.conditionalFormattingMayChange = false,
    List<int> unsupportedPropertyCodes = const [],
  }) : unsupportedPropertyCodes = List.unmodifiable(unsupportedPropertyCodes);

  final LegacyWordTableRowProperties? previousProperties;
  final LegacyWordRevisionInfo revision;
  final bool marked;

  /// False for an incomplete prior row or unknown pre-wall table properties.
  final bool previousPropertiesComplete;

  /// A header instruction changes in a table with conditional cell or text
  /// formatting. Rejecting it can also change later header-prefix/banding
  /// results; the current flattened child properties are not prior history.
  final bool conditionalFormattingMayChange;

  /// Post-wall table/cell operations outside the supported row-layout subset.
  /// These remain evidence; no partial native trPrChange is invented.
  final List<int> unsupportedPropertyCodes;
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
    this.formatting = const LegacyWordTableCellFormat(),
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
  final LegacyWordTableCellFormat formatting;
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

/// The legacy NumRM paragraph-numbering history and PFNumRMIns insertion flag.
/// A missing native original string is deliberately different from no previous
/// numbering; the immutable source record still retains all nine levels.
class LegacyWordNumberingRevision {
  LegacyWordNumberingRevision({
    this.previouslyNumbered,
    this.original,
    this.inserted = false,
    this.revision = const LegacyWordRevisionInfo(),
    Uint8List? sourceRecord,
  }) : sourceRecord = sourceRecord == null
           ? null
           : Uint8List.fromList(sourceRecord).asUnmodifiableView() {
    if (sourceRecord != null && sourceRecord.length != 128) {
      throw const FormatException('Invalid Word numbering revision record.');
    }
  }

  /// Null means no NumRM record supplied this previous state.
  final bool? previouslyNumbered;

  /// OOXML legacy numbering history, e.g. %1:3:0:. for old decimal "3.".
  /// Null means the original cannot be represented without interpretation.
  final String? original;
  final bool inserted;
  final LegacyWordRevisionInfo revision;
  final Uint8List? sourceRecord;
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

/// The separately selected MS-DOC non-ASCII, East Asian and complex-script
/// font faces. A null face remains unspecified; it is not the ASCII face.
class LegacyWordScriptFonts {
  const LegacyWordScriptFonts({
    this.nonAscii,
    this.eastAsia,
    this.complexScript,
  });

  final String? nonAscii;
  final String? eastAsia;
  final String? complexScript;

  @override
  bool operator ==(Object other) =>
      other is LegacyWordScriptFonts &&
      nonAscii == other.nonAscii &&
      eastAsia == other.eastAsia &&
      complexScript == other.complexScript;

  @override
  int get hashCode => Object.hash(nonAscii, eastAsia, complexScript);
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
    this.scriptFonts,
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

  /// When present, script-specific faces are independent of [fontName], which
  /// is the ASCII face. A null set preserves the original single-face API.
  final LegacyWordScriptFonts? scriptFonts;
  final int? fontSizeHalfPoints;

  /// MS-DOC sprmCHpsKern threshold in half-points. Zero disables kerning.
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
      scriptFonts == other.scriptFonts &&
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
    scriptFonts,
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
