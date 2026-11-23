import 'dart:math' as math;

import '../../bidi/grapheme_clusters.dart';
import '../../bidi/line_breaker.dart';
import '../../bidi/office_hyphenator.dart';
import '../../fonts/font_metrics.dart';
import '../../fonts/gpos_mark_to_base.dart';
import '../../fonts/office_font_set.dart';
import '../../fonts/office_typeface.dart';
import '../../fonts/sfnt_parser.dart';
import '../../visual/office_visual.dart';
import '../../xml/namespaces.dart';
import '../../xml/xml_node.dart';
import '../math/omml_document.dart';
import '../math/omml_layout.dart';
import '../model/wml_clone.dart';
import '../model/wml_document.dart';
import '../model/wml_run_edit.dart';
import '../model/word_comment.dart';
import '../model/word_fields.dart';
import '../model/word_link.dart';
import '../model/word_notes.dart';
import '../model/word_small_caps.dart';
import '../model/word_table.dart';
import '../model/word_toc.dart';
import '../model/word_tree.dart';
import '../properties/wml_properties.dart';

part 'word_contained_layout.dart';
part 'word_chrome_frames.dart';
part 'word_incremental_layout.dart';
part 'word_note_layout.dart';
part 'word_run_measure.dart';
part 'word_table_row_layout.dart';
part 'word_wrap_layout.dart';

/// Class LaidOutGlyph.
class LaidOutGlyph {
  /// LaidOutGlyph API.
  LaidOutGlyph({
    required this.glyph,
    required this.x,
    required double y,
    required this.color,
    required this.fontSize,
    required this.bold,
    required this.underline,
    this.italic = false,
    this.kerning = true,
    this.strike = false,
    this.highlight,
    this.fontFamily,
    this.vertAlign = WmlVertAlign.baseline,
    this.positionHalfPoints = 0,
    this.hyperlink,
    List<int>? commentIds,
    this.displayText,
    this.displayOffset = 0,
    this.sourceEnd,
    this.actualText,
    double? advance,
    double? paintDx,
    double? paintDy,
  }) : // A named parameter cannot be private; y moves only in layout.
       // ignore: prefer_initializing_formals
       _y = y,
       commentIds = commentIds ?? const <int>[],
       advance = advance ?? glyph.advance,
       paintDx = paintDx ?? glyph.paintDx,
       paintDy = paintDy ?? glyph.paintDy;

  /// glyph API.
  final ShapedGlyph glyph;

  /// x API.
  double x;

  /// y API.
  double get y => _y;
  double _y;

  /// Vertical-alignment shift used for [y] by body paragraph layout, so an
  /// incremental layout can place the same line at another height with the
  /// same arithmetic (see `_translateParagraph`).
  double _baselineShift = 0;

  /// color API.
  final String color;

  /// fontSize API.
  final double fontSize;

  /// bold API.
  final bool bold;

  /// underline API.
  final WmlUnderline underline;

  /// italic API.
  final bool italic;

  /// Pair kerning selected by the effective native run threshold.
  final bool kerning;

  /// strike API.
  final bool strike;

  /// highlight API.
  final String? highlight;

  /// fontFamily API.
  final String? fontFamily;

  /// vertAlign API.
  final WmlVertAlign vertAlign;

  /// Independent native baseline position, positive upward, in half-points.
  final int positionHalfPoints;

  /// hyperlink API.
  final WmlHyperlink? hyperlink;

  /// commentIds API.
  final List<int> commentIds;

  /// Presentation text painted in place of a source range, including an
  /// automatic field label or a selected discretionary hyphen.
  /// All glyphs in one label share the source start/end; [displayOffset]
  /// identifies this glyph within [displayText] for shaping and hit testing.
  final String? displayText;
  final int displayOffset;
  final int? sourceEnd;

  /// Authored source for a synthetic character presentation. PDF exporters
  /// mark the complete display group with this text for copy and search.
  /// Automatic note labels intentionally leave this null.
  final String? actualText;

  int get logicalEnd =>
      sourceEnd ??
      glyph.logicalIndex +
          (glyph.sourceLength ?? (glyph.codePoint > 0xffff ? 2 : 1));

  /// advance API.
  double advance;

  /// Horizontal shift so tashkeel paints on its base letter.
  final double paintDx;

  /// Upward shift (font space) so tashkeel uses the GPOS mark anchor.
  final double paintDy;
}

/// Class LaidOutLine.
class LaidOutLine {
  /// LaidOutLine API.
  LaidOutLine({
    required this.glyphs,
    required this.x,
    required double y,
    required this.width,
    required this.height,
    required this.pageIndex,
    required this.justification,
    this.paragraphIndex = 0,
    this.listLabel,
    this.listMarkerX = 0,
    this.isParagraphStart = false,
    this.isFooter = false,
    this.overlayText,
    this.overlayColor,
    this.overlaySize = 11,
    this.overlayBold = false,
    this.overlayBaseline,
    this.sourceText,
    this.sourceParagraph,
    this.proofingOffsets,
    this.tocTargetParagraph,
    this.tocLeader = false,
    this.hyperlink,
    this.justificationRatio = 0,
    this.boxX = 0,
    this.boxWidth = 0,
    // A named parameter cannot be private; y moves only in layout.
    // ignore: prefer_initializing_formals
  }) : _y = y;

  /// Exact model paragraph for this layout story, independent of body indexes.
  final WmlParagraph? sourceParagraph;

  /// Note labels can add display-only UTF-16 units before/between source runs.
  /// A null entry denotes such a label; otherwise each entry is the original
  /// source offset. Null list means the identity mapping.
  final List<int?>? proofingOffsets;

  /// Baseline leading and ascent of a body paragraph line (null for other
  /// lines): with them `_translateParagraph` recomputes glyph heights exactly
  /// as paragraph layout does.
  ({double leading, double ascent})? _baseline;

  int? proofingOffsetAt(int layoutOffset) => proofingOffsets == null
      ? layoutOffset
      : layoutOffset < 0 || layoutOffset >= proofingOffsets!.length
      ? null
      : proofingOffsets![layoutOffset];

  /// Default table-cell inset, matching [WmlTableProps.cellMargin].
  ///
  /// Actual table layout uses each table's configured margin. This constant
  /// remains the fallback for callers without a table model.
  static const double tableCellPad = 4;

  /// Inner pad for absolutely placed [WmlFrame] text.
  static const double framePad = 8;

  /// glyphs API.
  final List<LaidOutGlyph> glyphs;

  /// x API.
  double x;

  /// y API.
  double get y => _y;
  double _y;

  /// width API.
  double width;

  /// height API.
  final double height;

  /// pageIndex API.
  final int pageIndex;

  /// justification API.
  final WmlJustification justification;

  /// paragraphIndex API.
  ///
  /// Mutable only so incremental layout can renumber reused lines after a
  /// paragraph was inserted or removed before them.
  int paragraphIndex;

  /// Logical source text covered by this line, including shaped note content.
  String get text {
    if (glyphs.isEmpty) return overlayText ?? '';
    final List<LaidOutGlyph> logical = List<LaidOutGlyph>.of(glyphs)
      ..sort(
        (LaidOutGlyph a, LaidOutGlyph b) =>
            a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex),
      );
    final String? source = sourceText ?? sourceParagraph?.text;
    if (logical.any((glyph) => glyph.displayText != null)) {
      logical.sort((a, b) {
        final bySource = a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex);
        return bySource != 0
            ? bySource
            : a.displayOffset.compareTo(b.displayOffset);
      });
      final out = StringBuffer();
      var lastDisplayStart = -1;
      var sourceOffset = logical.first.glyph.logicalIndex;
      for (final glyph in logical) {
        final at = glyph.glyph.logicalIndex;
        if (source != null && sourceOffset < at) {
          // Invisible authored controls can lie between painted glyphs.
          out.write(source.substring(sourceOffset, at.clamp(0, source.length)));
          sourceOffset = at;
        }
        if (glyph.glyph.isDiscretionaryHyphen) {
          out.write(glyph.actualText ?? '');
          sourceOffset = math.max(sourceOffset, glyph.logicalEnd);
          continue;
        }
        if (glyph.displayText case final String display) {
          if (glyph.glyph.logicalIndex != lastDisplayStart) out.write(display);
          lastDisplayStart = glyph.glyph.logicalIndex;
        } else if (source != null && glyph.glyph.logicalIndex < source.length) {
          out.write(
            source.substring(
              glyph.glyph.logicalIndex,
              glyph.logicalEnd.clamp(glyph.glyph.logicalIndex, source.length),
            ),
          );
        } else if (glyph.glyph.codePoint != 0) {
          out.writeCharCode(glyph.glyph.codePoint);
        }
        sourceOffset = math.max(sourceOffset, glyph.logicalEnd);
      }
      return out.toString();
    }
    if (source != null) {
      final int start = logical.first.glyph.logicalIndex.clamp(
        0,
        source.length,
      );
      final LaidOutGlyph last = logical.last;
      final int end = last.logicalEnd.clamp(start, source.length);
      return source.substring(start, end);
    }
    return String.fromCharCodes(
      logical.map((LaidOutGlyph g) => g.glyph.codePoint),
    );
  }

  /// listLabel API.
  final String? listLabel;

  /// Page X of the list marker (hanging indent / RTL-aware).
  final double listMarkerX;

  /// isParagraphStart API.
  final bool isParagraphStart;

  /// isFooter API.
  final bool isFooter;

  /// overlayText API.
  final String? overlayText;

  /// overlayColor API.
  final String? overlayColor;

  /// overlaySize API.
  final double overlaySize;

  /// overlayBold API.
  final bool overlayBold;

  /// Baseline measured from the top of the line box for an overlay.
  final double? overlayBaseline;

  /// sourceText API.
  final String? sourceText;

  /// tocTargetParagraph API.
  final int? tocTargetParagraph;

  /// tocLeader API.
  final bool tocLeader;

  /// hyperlink API.
  final WmlHyperlink? hyperlink;

  /// Non-zero on wrapped justified lines. Last lines stay packed.
  final double justificationRatio;

  /// Page X of the paragraph content box (column / cell / frame origin).
  final double boxX;

  /// Width of the paragraph content box, before first-line indent.
  final double boxWidth;

  /// Stretches word spaces so the line fills [targetWidth], capping extreme
  /// gaps so narrow columns stay readable (soft justify when stretch is huge).
  void applyJustification({double? targetWidth}) {
    if (glyphs.isEmpty) {
      return;
    }
    if (justification != WmlJustification.justify &&
        justification != WmlJustification.distributed) {
      return;
    }
    if (justificationRatio == 0) {
      return;
    }
    final double target = targetWidth ?? width;
    var used = 0.0;
    final List<int> spaceIndexes = <int>[];
    for (int i = 0; i < glyphs.length; i++) {
      final LaidOutGlyph glyph = glyphs[i];
      used += glyph.advance;
      // Tabs keep their stop width; only word spaces absorb justify stretch.
      if (glyph.glyph.isSpace && glyph.glyph.codePoint != 0x09) {
        spaceIndexes.add(i);
      }
    }
    final double slack = target - used;
    final int spaces = spaceIndexes.length;
    if (spaces <= 0 || slack <= 0.5) {
      return;
    }
    final double em = glyphs[spaceIndexes.first].fontSize;
    // ~0.45em per gap ≈ Word-like comfort; beyond that, leave a slight shortfall
    // instead of "rivers" of white space in narrow columns.
    final double maxExtra = math.max(em * 0.45, 1.0);
    final double extra = math.min(slack / spaces, maxExtra);
    final Set<int> stretch = spaceIndexes.toSet();
    var x = this.x;
    for (int i = 0; i < glyphs.length; i++) {
      final LaidOutGlyph glyph = glyphs[i];
      glyph.x = x + glyph.paintDx;
      if (stretch.contains(i)) {
        glyph.advance += extra;
      }
      x += glyph.advance;
    }
    width = used + extra * spaces;
  }
}

/// Enum LaidOutBoxKind.
enum LaidOutBoxKind {
  tableCell,
  picture,
  chart,
  diagram,
  equation,
  tocEntry,
  frame,
  columnSep,
  paragraphShade,
  footnote,
  lineNumber,
}

/// Decorative box in page coordinates (table cell, picture, chart).
class LaidOutBox {
  /// LaidOutBox API.
  LaidOutBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.fillColor,
    this.strokeColor = 'B0B0B0',
    this.paragraphIndex,
    this.paragraphEnd,
    this.kind = LaidOutBoxKind.tableCell,
    this.visual,
    this.equation,
    this.omml,
    this.table,
    this.tableRow,
    this.tableCol,
    this.tableGridCol,
    this.tableRowGeometry,
    this.frame,
    this.strokeTop = true,
    this.strokeRight = true,
    this.strokeBottom = true,
    this.strokeLeft = true,
    this.strokeWidth = 0.5,
    this.isNoteContent = false,
  });

  /// x API.
  double x;

  /// y API.
  double y;

  /// width API.
  double width;

  /// height API.
  double height;

  /// fillColor API.
  String? fillColor;

  /// strokeColor API.
  String strokeColor;

  /// paragraphIndex API.
  int? paragraphIndex;

  /// paragraphEnd API.
  int? paragraphEnd;

  /// kind API.
  LaidOutBoxKind kind;

  /// visual API.
  OfficeVisual? visual;

  /// equation API.
  WmlEquation? equation;

  /// omml API.
  LaidOutOmml? omml;

  /// table API.
  WmlTable? table;

  /// tableRow API.
  int? tableRow;

  /// tableCol API.
  int? tableCol;

  /// tableGridCol API.
  int? tableGridCol;

  /// Physical row bounds before vertically merged fragments are consolidated.
  ///
  /// Visible [tableRow] and paragraph ownership resolve to the merge origin;
  /// row selection and insertion still need the actual row on this page.
  ({int row, double y, double height})? tableRowGeometry;

  /// frame API.
  WmlFrame? frame;

  /// strokeTop API.
  bool strokeTop;

  /// strokeRight API.
  bool strokeRight;

  /// strokeBottom API.
  bool strokeBottom;

  /// strokeLeft API.
  bool strokeLeft;

  /// strokeWidth API.
  double strokeWidth;

  /// True for note borders, drawings and separators, outside the body flow.
  final bool isNoteContent;
}

/// Class LaidOutBand.
class LaidOutBand {
  /// LaidOutBand API.
  const LaidOutBand({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// left API.
  final double left;

  /// top API.
  final double top;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// contains API.
  bool contains(double x, double y) {
    return x >= left && x <= left + width && y >= top && y <= top + height;
  }
}

/// Class LaidOutPage.
class LaidOutPage {
  /// LaidOutPage API.
  LaidOutPage({
    required this.index,
    required this.width,
    required this.height,
    required this.lines,
    this.sectionIndex = 0,
    List<LaidOutBox>? frames,
    List<LaidOutLine>? header,
    List<LaidOutLine>? footer,
    List<LaidOutLine>? notes,
    LaidOutBand? headerBand,
    LaidOutBand? footerBand,
  }) : frames = frames ?? <LaidOutBox>[],
       header = header ?? <LaidOutLine>[],
       footer = footer ?? <LaidOutLine>[],
       notes = notes ?? <LaidOutLine>[],
       headerBand =
           headerBand ?? LaidOutBand(left: 0, top: 0, width: width, height: 72),
       footerBand =
           footerBand ??
           LaidOutBand(left: 0, top: height - 72, width: width, height: 72);

  /// index API.
  final int index;

  /// sectionIndex API.
  final int sectionIndex;

  /// width API.
  final double width;

  /// height API.
  final double height;

  /// lines API.
  final List<LaidOutLine> lines;

  /// frames API.
  final List<LaidOutBox> frames;

  /// header API.
  final List<LaidOutLine> header;

  /// footer API.
  final List<LaidOutLine> footer;

  /// Footnote lines stacked above the footer band.
  final List<LaidOutLine> notes;

  /// headerBand API.
  final LaidOutBand headerBand;

  /// footerBand API.
  final LaidOutBand footerBand;

  /// How the engine made this page, so incremental layout can remake it.
  _PageOrigin? _origin;
}

/// Class LaidOutDocument.
class LaidOutDocument {
  /// LaidOutDocument API.
  LaidOutDocument({required this.pages, required this.pageSize});

  /// Flow checkpoints recorded by the engine for incremental relayout.
  _IncrementalState? _incremental;

  /// True when [WordLayoutEngine.layout] can reuse this result for a local
  /// edit (see `reuse` and `dirtyParagraphs`).
  bool get supportsIncrementalReuse => _incremental != null;

  /// Call after mutating any laid-out line, glyph or box in place (for
  /// example paint-metric fitting): reusing such objects would no longer
  /// reproduce a fresh layout, so the next local edit falls back to the
  /// section-level path.
  void discardIncrementalState() => _incremental = null;

  /// pages API.
  final List<LaidOutPage> pages;

  /// pageSize API.
  final WmlPageSize pageSize;

  /// Vertical offset of page [index] in the stacked Word canvas (points ? scale).
  double pageStackTop(int index, double scale) {
    var top = 24.0;
    final int last = index < pages.length ? index : pages.length;
    for (int i = 0; i < last; i++) {
      top += pages[i].height * scale + 24;
    }
    if (index >= pages.length) {
      top += (index - pages.length) * (pageSize.height * scale + 24);
    }
    return top;
  }

  /// pageIndexAtContentY API.
  int pageIndexAtContentY(double contentY, double scale) {
    if (pages.isEmpty) {
      return 0;
    }
    var top = 24.0;
    for (int i = 0; i < pages.length; i++) {
      final double bottom = top + pages[i].height * scale;
      if (contentY < bottom + 12) {
        return i;
      }
      top = bottom + 24;
    }
    return pages.length - 1;
  }
}

class _Flow {
  _Flow(
    this.section,
    this.pages,
    this.makePage,
    this.sectionIndex,
    this.noteReserve,
    this.headerBodyTop,
  ) : pageIndex = pages.length,
      y = section.margins.top,
      columnTop = section.margins.top;

  /// section API.
  final WmlSection section;

  /// sectionIndex API.
  final int sectionIndex;

  /// pages API.
  final List<LaidOutPage> pages;

  /// Function API.
  final LaidOutPage Function(
    WmlSection section,
    int index,
    List<LaidOutLine> lines,
    List<LaidOutBox> frames, {
    required int sectionIndex,
    required bool firstInSection,
  })
  /// makePage API.
  makePage;

  final double Function(int) noteReserve;
  final double Function(int pageIndex, {required bool firstInSection})
  headerBodyTop;

  /// current API.
  final List<LaidOutLine> current = <LaidOutLine>[];

  /// currentFrames API.
  final List<LaidOutBox> currentFrames = <LaidOutBox>[];

  /// pageIndex API.
  int pageIndex;

  /// columnIndex API.
  int columnIndex = 0;

  /// y API.
  double y;

  /// Top of every column on the current page (below prior continuous content).
  double columnTop;

  /// originX API.
  double get originX => section.columnOriginX(columnIndex);

  /// colWidth API.
  double get colWidth => section.columnWidth;

  /// bottom API.
  double get bottom =>
      section.pageSize.height - section.margins.bottom - noteReserve(pageIndex);

  /// hasContent API.
  bool get hasContent => current.isNotEmpty || currentFrames.isNotEmpty;

  /// flushPage API.
  void flushPage() {
    pages.add(_make());
    current.clear();
    currentFrames.clear();
    pageIndex++;
    columnIndex = 0;
    y = headerBodyTop(pageIndex, firstInSection: false);
    columnTop = y;
  }

  /// nextColumn API.
  void nextColumn() {
    if (columnIndex + 1 < section.resolvedColumnCount) {
      columnIndex++;
      y = columnTop;
    } else {
      flushPage();
    }
  }

  /// breakPage API.
  void breakPage() {
    if (hasContent || columnIndex > 0) {
      flushPage();
    }
  }

  /// ensure API.
  void ensure(double height) {
    if (y + height > bottom && (hasContent || columnIndex > 0)) {
      nextColumn();
    }
  }

  /// addSeparators API.
  void addSeparators() {
    if (!section.columnSep || section.resolvedColumnCount < 2) {
      return;
    }
    for (int i = 1; i < section.resolvedColumnCount; i++) {
      final double x = section.columnOriginX(i) - section.columnSpace / 2;
      currentFrames.add(
        LaidOutBox(
          x: x,
          y: section.margins.top,
          width: 0.7,
          height: section.contentHeight,
          fillColor: 'B0B0B0',
          strokeColor: 'B0B0B0',
          kind: LaidOutBoxKind.columnSep,
        ),
      );
    }
  }

  LaidOutPage _make() {
    addSeparators();
    final bool first = pages.every(
      (LaidOutPage page) => page.sectionIndex != sectionIndex,
    );
    return makePage(
      section,
      pageIndex,
      current,
      currentFrames,
      sectionIndex: sectionIndex,
      firstInSection: first,
    );
  }

  /// finish API.
  void finish() {
    if (hasContent || pages.isEmpty) {
      pages.add(_make());
      current.clear();
      currentFrames.clear();
    }
  }
}

/// Word's default tab-stop interval (0.5 inch).
const double kDefaultTabWidth = 36;

/// Advance width in points of [codePoint] set in [props] at [sizePoints].
///
/// Hosts that paint with their own text stack (for example Flutter's
/// `TextPainter`) can supply scalar fallback metrics. Contextual shaping needs
/// [WordLayoutEngine.measureRun], which measures complete logical runs.
typedef WordGlyphMeasure =
    double Function(int codePoint, double sizePoints, WmlRunProps props);

/// Actual face metrics from a host that owns fonts outside the engine pack.
/// Width shaping and vertical line metrics must use the same resolved face.
typedef WordFontMeasure =
    FontMetrics? Function(int codePoint, double sizePoints, WmlRunProps props);

/// Word-style greedy wrapping with shaped line measurements and pagination.
class WordLayoutEngine {
  /// WordLayoutEngine API.
  WordLayoutEngine({
    required this.font,
    this.fonts,
    this.fallbackWidthFactor = 0.5,
    this.measure,
    this.measureRun,
    this.measureFont,
  });

  /// Primary face used when [fonts] does not cover a code point.
  final SfntFont? font;

  /// Multi-face pack for mixed-script documents (Latin + Arabic, …).
  final OfficeFontSet? fonts;

  /// Em fraction per character when neither [fonts], [font] nor [measure]
  /// can size a code point. Table cells and frames use at least 0.72 so
  /// their text stays inside the border.
  final double fallbackWidthFactor;

  /// Host measurement used when [fonts] and [font] do not cover a code point.
  final WordGlyphMeasure? measure;

  /// Optional host shaping metrics, applied before wrapping. Valid run metrics
  /// take precedence over scalar/font metrics; null or invalid measurements
  /// retain the pure-Dart fallback. This does not change glyph IDs for PDF.
  final WordRunMeasure? measureRun;

  final WordFontMeasure? measureFont;

  final Map<(SfntFont, double), FontMetrics> _metricsCache = {};

  WmlDocument? _layoutDoc;
  WordNoteNumbering? _noteNumbering;
  // Tall-row layout shares its owner's body sequence, not a temporary subset.
  WordNoteNumbering? _inheritedNoteNumbering;
  // Temporary tall-row shaping records absolute frame anchors without moving
  // their page coordinates into the row's local coordinate system.
  Map<WmlFrame, ({double y, int paragraphIndex})>? _deferredContainedFrames;
  int _containedMeasureDepth = 0;
  Map<WmlVisual, double>? _deferredContainedVisuals;
  ({WmlTable table, List<_TallCellContent> cells})? _captureTallCells;
  WmlSection? _containedPhysicalSection;
  int _containedTableDepth = 0;
  // Sum of one-sided margins of all enclosing table cells. Nested tables may
  // have different margins; depth alone cannot describe their usable height.
  double _containedVerticalInsets = 0;
  final Map<WmlNote, _NoteStory> _noteStories = <WmlNote, _NoteStory>{};
  final Map<int, List<_NoteSlice>> _noteSlices = <int, List<_NoteSlice>>{};
  final Set<int> _placedNotes = <int>{};

  /// [_placedNotes] in placement order (incremental layout restores
  /// prefixes of it).
  final List<int> _placedOrder = <int>[];

  /// Note slices reserved on pages from [fromPage] on, copied; null if none.
  Map<int, List<_NoteSlice>>? _pendingNotes(int fromPage) {
    if (_noteSlices.isEmpty) return null;
    Map<int, List<_NoteSlice>>? result;
    _noteSlices.forEach((int page, List<_NoteSlice> slices) {
      if (page >= fromPage && slices.isNotEmpty) {
        (result ??= <int, List<_NoteSlice>>{})[page] = List<_NoteSlice>.of(
          slices,
        );
      }
    });
    return result;
  }

  /// The note state of the flow equals the one recorded in [cp] (whose
  /// layout placed notes in [oldOrder]).
  bool _notesMatch(_Checkpoint cp, List<int> oldOrder) {
    if (_placedOrder.length != cp.placedNotes ||
        oldOrder.length < cp.placedNotes) {
      return false;
    }
    for (int i = 0; i < cp.placedNotes; i++) {
      if (!_placedNotes.contains(oldOrder[i])) return false;
    }
    final Map<int, List<_NoteSlice>>? pending = cp.pendingNotes;
    for (final MapEntry<int, List<_NoteSlice>> entry in _noteSlices.entries) {
      if (entry.key >= cp.pagesLength &&
          !_sameSlices(entry.value, pending?[entry.key])) {
        return false;
      }
    }
    if (pending != null) {
      for (final MapEntry<int, List<_NoteSlice>> entry in pending.entries) {
        if (!_sameSlices(entry.value, _noteSlices[entry.key])) return false;
      }
    }
    return true;
  }

  /// Note order, labels and the section of each reference: shaped note
  /// stories (sized for the section that first places them) and reference
  /// labels in the body are valid while this is unchanged.
  List<Object> _noteNumberingSignature(WmlDocument document) {
    final WordNoteNumbering numbering = _noteNumbering!;
    final List<Object> result = <Object>[];
    for (final WmlNote note in numbering.notes) {
      result
        ..add(note)
        ..add(numbering.labelFor(note));
    }
    for (int s = 0; s < document.sections.length; s++) {
      for (final WmlParagraph p in WordTree.paragraphs(
        document.sections[s].blocks,
      )) {
        for (final WmlInline inline in p.inlines) {
          if (inline is WmlRun && inline.noteRefId != null) {
            result.add(
              '$s:${inline.noteRefEndnote ? 'e' : 'f'}${inline.noteRefId}',
            );
          }
        }
      }
    }
    return result;
  }

  /// Note definitions, their paragraphs and text.
  static List<Object> _noteContentSignature(WmlDocument document) => <Object>[
    // Separator geometry affects every page's body reservation and must not be
    // reused after a document preference change, even when no note text changed.
    document.footnoteSeparator ??
        'legacy-footnote-separator:${document.sourceFootnoteSeparatorsPresent}',
    if (document.sourceBlankFootnoteSeparators) 'blank-footnote-separators',
    for (final WmlNote note in <WmlNote>[
      ...document.footnotes,
      ...document.endnotes,
    ]) ...<Object>[
      note,
      '${note.blocks.length}',
      for (final WmlParagraph p in WordTree.paragraphs(note.blocks)) ...[
        p,
        p.text,
      ],
    ],
  ];

  double get _footnoteSeparatorHeight {
    final separator = _layoutDoc?.footnoteSeparator;
    separator?.validate();
    return separator?.reservedHeight ?? 8;
  }

  double _noteReserve(int page) {
    final List<_NoteSlice> slices = _noteSlices[page] ?? <_NoteSlice>[];
    return slices.isEmpty
        ? 0
        : _footnoteSeparatorHeight +
              slices.fold<double>(0, (double n, _NoteSlice s) => n + s.height);
  }

  double _bodyBottom(WmlSection section, int page) =>
      section.pageSize.height - section.margins.bottom - _noteReserve(page);

  _NoteStory _story(WmlNote note, WmlSection section) => _noteStories
      .putIfAbsent(note, () => _NoteStory.shape(note, section, this));

  List<WmlNote> _newNotes(Iterable<int> ids) => <WmlNote>[
    for (final int id in ids.toSet())
      if (!_placedNotes.contains(id))
        if (WordNotes.byId(_layoutDoc!, id, endnote: false)
            case final WmlNote note)
          note,
  ];

  double _minimumNotes(Iterable<int> ids, WmlSection section, int page) {
    final List<WmlNote> notes = _newNotes(ids);
    if (notes.isEmpty) return 0;
    return (_noteReserve(page) == 0 ? _footnoteSeparatorHeight : 0) +
        notes.fold<double>(
          0,
          (double h, WmlNote note) => h + _story(note, section).firstHeight,
        );
  }

  void _reserveNotes(
    Iterable<int> ids,
    WmlSection section,
    int page,
    double bodyBottom,
  ) {
    final List<WmlNote> notes = _newNotes(ids);
    for (var ni = 0; ni < notes.length; ni++) {
      final WmlNote note = notes[ni];
      _placedNotes.add(note.id);
      _placedOrder.add(note.id);
      final _NoteStory story = _story(note, section);
      var start = 0.0;
      var target = page;
      while (start < story.height - 0.01) {
        final double minimumRemaining = target == page
            ? notes
                  .skip(ni + 1)
                  .fold<double>(
                    0,
                    (double h, WmlNote n) => h + _story(n, section).firstHeight,
                  )
            : 0;
        final double top = target == page ? bodyBottom : section.margins.top;
        final double available =
            section.pageSize.height -
            section.margins.bottom -
            top -
            _noteReserve(target) -
            (_noteReserve(target) == 0 ? _footnoteSeparatorHeight : 0) -
            minimumRemaining;
        final double end = story.cut(start, available);
        if (end <= start + 0.01) {
          if (target > page && _noteReserve(target) == 0) {
            throw StateError(
              'Note ${note.id} contains content taller than a page',
            );
          }
          target++;
          continue;
        }
        _noteSlices
            .putIfAbsent(target, () => <_NoteSlice>[])
            .add(
              _NoteSlice(
                story,
                start,
                end,
                section,
                _layoutDoc!.sections.indexOf(section),
              ),
            );
        start = end;
        target++;
      }
    }
  }

  Iterable<int> _noteIds(WmlParagraph paragraph, Iterable<int> offsets) sync* {
    final Set<int> positions = offsets.toSet();
    var offset = 0;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlRun) {
        if (inline.noteRefId != null &&
            !inline.noteRefEndnote &&
            positions.contains(offset)) {
          yield inline.noteRefId!;
        }
        offset += inline.text.length;
      } else if (inline is WmlBreak) {
        offset++;
      }
    }
  }

  SfntFont? _faceFor(int cp, WmlRunProps props) =>
      fonts?.faceFor(
        cp,
        family: OfficeTypeface.familyForRun(props, cp),
        weight: props.bold ? 700 : 400,
        italic: props.italic,
      ) ??
      (font != null && font!.glyphIdFor(cp) != 0 ? font : null);

  double _advanceOf(
    int cp,
    double sizePoints,
    double emFallback,
    WmlRunProps props,
  ) {
    if (cp == 0x09) {
      return kDefaultTabWidth;
    }
    final SfntFont? face = _faceFor(cp, props);
    if (face == null) {
      final WordGlyphMeasure? hostMeasure = measure;
      return hostMeasure != null
          ? hostMeasure(cp, sizePoints, props)
          : sizePoints * emFallback;
    }
    final FontMetrics metrics = _metricsCache.putIfAbsent((
      face,
      sizePoints,
    ), () => FontMetrics(font: face, fontSizePoints: sizePoints));
    return metrics.characterWidth(cp);
  }

  /// Tallest header logo height for [section] (0 if none).
  static double _headerLogoHeight(WmlSection section) {
    var maxH = 0.0;
    void consider(Iterable<WmlVisual> visuals) {
      for (final WmlVisual item in visuals) {
        maxH = math.max(maxH, item.visual.height);
      }
    }

    consider(section.headerVisuals);
    consider(section.firstHeaderVisuals);
    consider(section.evenHeaderVisuals);
    for (final story in [
      section.header,
      section.firstHeader,
      section.evenHeader,
    ]) {
      consider([
        for (final paragraph in story)
          for (final run in paragraph.inlines.whereType<WmlRun>())
            if (run.inlineVisual != null) run.inlineVisual!,
      ]);
    }
    return maxH;
  }

  /// Body Y that clears a header logo when content would sit underneath it.
  static double _bodyTopClearingLogo(WmlSection section) {
    final double logoH = _headerLogoHeight(section);
    if (logoH <= 0) {
      return section.margins.top;
    }
    return math.max(section.margins.top, section.margins.header + logoH + 2);
  }

  /// Top Y for a new table page slice — always below the header logo band.
  ///
  /// Word keeps floating header art outside the table; starting a continuation
  /// row at [WmlPageMargins.top] draws cell borders through the logo.
  double _tablePageTop(WmlSection section) => _bodyTopClearingLogo(section);

  double _headerBodyTop(
    WmlSection section,
    int pageIndex, {
    required bool firstInSection,
  }) {
    final preserved = section.preservedStories;
    final (story, key) =
        section.differentFirstPage &&
            firstInSection &&
            (section.firstHeader.isNotEmpty ||
                preserved.containsKey('firstHeader'))
        ? (section.firstHeader, 'firstHeader')
        : section.differentOddEven &&
              (pageIndex + 1).isEven &&
              (section.evenHeader.isNotEmpty ||
                  preserved.containsKey('evenHeader'))
        ? (section.evenHeader, 'evenHeader')
        : (section.header, 'header');
    final anchor = preserved[key]?.headerAnchor;
    final paragraphs = story.isEmpty && anchor != null ? [anchor] : story;
    if (paragraphs.isEmpty) return section.margins.top;

    var bottom = section.margins.header;
    _AdjacentWordParagraph? previous;
    for (final paragraph in paragraphs) {
      final props = paragraph.properties;
      final source = props.sourcePropertiesXml;
      if (props.dropCapLines == 0 &&
          source != null &&
          source.contains('framePr') &&
          XmlDocument.parse(
                source,
              ).root?.firstChild('framePr', namespaceUri: OfficeNamespaces.w) !=
              null) {
        continue;
      }
      final point = paragraph.text.runes.firstOrNull ?? 0x20;
      final run = paragraph.text.isEmpty
          ? props.importedParagraphMark ?? WmlRunEdit.propsAt(paragraph, 0)
          : WmlRunEdit.propsAt(paragraph, 0);
      final size = run.fontSizePoints;
      final face = _faceFor(point, run);
      final metrics =
          measureFont?.call(point, size, run) ??
          (face == null ? null : FontMetrics(font: face, fontSizePoints: size));
      var height = _lineHeight(props, metrics, size);
      for (final inline in paragraph.inlines.whereType<WmlRun>()) {
        final picture = inline.inlineVisual?.visual;
        if (picture != null && picture.picture.wrap == PictureWrap.inline) {
          height = math.max(height, picture.height.clamp(12.0, 120.0));
        }
      }
      bottom += props.spacingBefore + height + props.spacingAfter;
      if (previous != null) bottom -= _paragraphGapOverlap(previous, props);
      previous = _afterParagraph(props);
    }
    return math.max(section.margins.top, bottom);
  }

  /// Global switch for paragraph-level incremental relayout of local edits.
  /// When false, [layout] ignores `dirtyParagraphs` and uses the
  /// section-level path (lay out from `fromSectionIndex`). Build with
  /// `--dart-define=QUDS_FULL_RELAYOUT=true` to start with it off.
  static bool incrementalLayout = !const bool.fromEnvironment(
    'QUDS_FULL_RELAYOUT',
  );

  /// Debug aid: after every incremental layout, also run a full layout and
  /// throw a [StateError] when the two differ ([wordLayoutFingerprint]).
  /// `--dart-define=QUDS_VERIFY_INCREMENTAL_LAYOUT=true` turns it on.
  static bool verifyIncrementalLayout = const bool.fromEnvironment(
    'QUDS_VERIFY_INCREMENTAL_LAYOUT',
  );

  _Recorder? _recorder;
  final Object _incrementalOwner = Object();

  /// Incremental layout places an unchanged paragraph that only moved
  /// vertically on the same page by copying its previous lines at the new
  /// height (`_translateParagraph`) instead of laying it out again. Build
  /// with `--dart-define=QUDS_TRANSLATE_PARAGRAPHS=false` to turn it off.
  static bool translateParagraphs = const bool.fromEnvironment(
    'QUDS_TRANSLATE_PARAGRAPHS',
    defaultValue: true,
  );

  /// [lines] (the previous layout of unchanged [paragraph], all on the page
  /// the flow is filling) moved to the flow's current height, with the
  /// arithmetic of [_layoutParagraph]; null when that layout could differ
  /// (a line would cross the page bottom, notes, no recorded baseline). The
  /// line objects move from the previous layout, which this one replaces.
  ({double y, int pageIndex})? _translateParagraph(
    WmlParagraph paragraph,
    WmlSection section,
    _Flow flow,
    List<LaidOutLine> lines,
    int paragraphIndex,
  ) {
    if (lines.isEmpty) return null;
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlRun && inline.noteRefId != null) return null;
    }
    final int idx = flow.pageIndex;
    final double bottom = _bodyBottom(section, idx);
    final double top = flow.y + paragraph.properties.spacingBefore;
    var cursorY = top;
    for (final LaidOutLine line in lines) {
      if (line._baseline == null || cursorY + line.height > bottom) {
        return null;
      }
      cursorY += line.height;
    }
    // The previous layout is replaced by this one: its lines move.
    cursorY = top;
    for (final LaidOutLine line in lines) {
      final ({double leading, double ascent}) baseline = line._baseline!;
      final double lineTop = cursorY;
      if (line._y != lineTop) {
        line._y = lineTop;
        for (final LaidOutGlyph g in line.glyphs) {
          g._y =
              lineTop +
              baseline.leading +
              baseline.ascent +
              g._baselineShift -
              g.glyph.paintDy;
        }
      }
      line.paragraphIndex = paragraphIndex;
      flow.current.add(line);
      cursorY += line.height;
    }
    WordIncrementalLayoutStats.blocksTranslated++;
    return (y: cursorY + paragraph.properties.spacingAfter, pageIndex: idx);
  }

  /// Last line breaks per paragraph (see [_BreakCache]).
  final Expando<_BreakCache> _breakCache = Expando<_BreakCache>();

  /// True while laying out a block an incremental layout proved unchanged.
  bool _breakCacheReadable = false;

  /// layout API.
  ///
  /// With [reuse] and [dirtyParagraphs] (and no field update), lays out only
  /// what a local edit can have changed: the result equals a full layout of
  /// [document] provided that, since [reuse] was laid out from it, the model
  /// changed only inside [dirtyParagraphs], by inserting or removing
  /// top-level blocks, or in paragraph text. Falls back to the section-level
  /// path from [fromSectionIndex] otherwise.
  LaidOutDocument layout(
    WmlDocument document, {
    bool updateFields = true,
    int fromSectionIndex = 0,
    LaidOutDocument? reuse,
    Set<WmlParagraph>? dirtyParagraphs,
  }) {
    if (reuse != null &&
        dirtyParagraphs != null &&
        !updateFields &&
        incrementalLayout) {
      final LaidOutDocument? incremental = _layoutIncremental(
        document,
        reuse,
        dirtyParagraphs,
      );
      if (incremental != null) {
        WordIncrementalLayoutStats.incremental++;
        if (verifyIncrementalLayout) {
          _verifyIncremental(document, incremental);
        }
        return incremental;
      }
      WordIncrementalLayoutStats.fallbacks++;
    }
    _prepareLayout(document, updateFields: updateFields);
    final _IncrementalState? previousState = reuse?._incremental;
    if (previousState != null &&
        (!identical(previousState.owner, _incrementalOwner) ||
            !identical(previousState.document, document) ||
            previousState.noSpaceRaiseLower !=
                document.sourceNoSpaceRaiseLower)) {
      // Pages of another engine or another document cannot be reused.
      // A rejected incremental attempt must not keep earlier sections from a
      // different engine's font or measurement environment in its fallback.
      reuse = null;
      fromSectionIndex = 0;
    }
    if (document.footnotes.isNotEmpty || document.endnotes.isNotEmpty) {
      fromSectionIndex = 0;
    }
    final _Recorder recorder = _recorder = _Recorder(document.sections.length);
    try {
      return _layoutFrom(
        document,
        updateFields: updateFields,
        fromSectionIndex: fromSectionIndex,
        reuse: reuse,
        recorder: recorder,
      );
    } finally {
      _recorder = null;
    }
  }

  void _prepareLayout(WmlDocument document, {required bool updateFields}) {
    _layoutDoc = document;
    _noteNumbering = _inheritedNoteNumbering ?? WordNoteNumbering(document);
    _noteStories.clear();
    _noteSlices.clear();
    _placedNotes.clear();
    _placedOrder.clear();
    // Materialize every nested TOC before paragraph indices are counted. A
    // normal engine layout also binds imported cached entries to live headings;
    // temporary row shaping keeps their original document-wide targets.
    for (final toc in WordToc.tocs(document)) {
      WordToc.ensureBody(toc);
    }
    if (updateFields) {
      WordToc.rebindHeadings(document);
      WordFields.update(document);
    }
  }

  LaidOutDocument _layoutFrom(
    WmlDocument document, {
    required bool updateFields,
    required int fromSectionIndex,
    required LaidOutDocument? reuse,
    required _Recorder recorder,
  }) {
    final List<LaidOutPage> pages = <LaidOutPage>[];
    var paragraphIndex = 0;
    var recorded = true;
    var start = fromSectionIndex.clamp(0, document.sections.length);
    if (start > 0 && reuse != null && start < document.sections.length) {
      while (start > 0 &&
          document.sections[start].breakKind ==
              WmlSectionBreakKind.continuous) {
        start--;
      }
      for (final LaidOutPage page in reuse.pages) {
        if (page.sectionIndex >= start) {
          break;
        }
        pages.add(page);
      }
      if (start > 0 && pages.isEmpty) {
        start = 0;
      } else {
        for (int i = 0; i < start; i++) {
          paragraphIndex += _layoutParagraphCount(document.sections[i]);
        }
        // Reused sections keep their checkpoints when the old layout has
        // them for the same sections; otherwise this result cannot seed an
        // incremental layout.
        final _IncrementalState? old = reuse._incremental;
        for (int i = 0; i < start; i++) {
          final _SectionRecord? record =
              old != null &&
                  identical(old.document, document) &&
                  i < old.sections.length
              ? old.sections[i]
              : null;
          if (record == null ||
              !identical(record.section, document.sections[i])) {
            recorded = false;
            break;
          }
          recorder.sections[i] = record;
        }
      }
    } else {
      start = 0;
    }
    for (int i = start; i < document.sections.length; i++) {
      paragraphIndex = _layoutSection(
        document.sections[i],
        pages,
        sectionIndex: i,
        paragraphIndex: paragraphIndex,
      );
    }
    return _finishLayout(
      document,
      pages,
      updateFields: updateFields,
      state: recorded
          ? _IncrementalState(_incrementalOwner, document, recorder.sections)
          : null,
    );
  }

  LaidOutDocument _finishLayout(
    WmlDocument document,
    List<LaidOutPage> pages, {
    required bool updateFields,
    required _IncrementalState? state,
  }) {
    if (pages.isEmpty) {
      pages.add(
        _makePage(
          document.sections.first,
          0,
          <LaidOutLine>[],
          <LaidOutBox>[],
          sectionIndex: 0,
          firstInSection: true,
        ),
      );
    }
    final int flowPages = pages.length;
    while (_noteSlices.keys.any((int index) => index >= pages.length)) {
      final _NoteSlice? slice = _noteSlices[pages.length]?.firstOrNull;
      final WmlSection section = slice?.section ?? document.sections.last;
      pages.add(
        _makePage(
          section,
          pages.length,
          <LaidOutLine>[],
          <LaidOutBox>[],
          sectionIndex: slice?.sectionIndex ?? document.sections.length - 1,
          firstInSection: false,
        ),
      );
    }
    final bool hasNotes =
        document.footnotes.isNotEmpty || document.endnotes.isNotEmpty;
    final int endnotePage = document.endnotes.isNotEmpty
        ? pages.length - 1
        : -1;
    final int endnoteLines = endnotePage < 0 ? 0 : pages.last.notes.length;
    final int endnoteFrames = endnotePage < 0 ? 0 : pages.last.frames.length;
    _appendEndnotes(document, pages);
    if (updateFields) {
      WordFields.update(document, pageCount: pages.length);
    }
    if (state != null) {
      state.flowPages = flowPages;
      if (hasNotes) {
        state.notes = _NoteState(
          slices: <int, List<_NoteSlice>>{
            for (final MapEntry<int, List<_NoteSlice>> entry
                in _noteSlices.entries)
              entry.key: List<_NoteSlice>.of(entry.value),
          },
          placedOrder: List<int>.of(_placedOrder),
          stories: Map<WmlNote, _NoteStory>.of(_noteStories),
          numbering: _noteNumberingSignature(document),
          content: _noteContentSignature(document),
          endnotePage: endnotePage,
          endnoteLines: endnoteLines,
          endnoteFrames: endnoteFrames,
        );
      }
    }
    return LaidOutDocument(
      pages: pages,
      pageSize: document.sections.first.pageSize,
    ).._incremental = state;
  }

  /// Incremental layout after a local edit, or null when it cannot be proven
  /// equal to a full layout (see word_incremental_layout.dart).
  LaidOutDocument? _layoutIncremental(
    WmlDocument document,
    LaidOutDocument reuse,
    Set<WmlParagraph> dirtyParagraphs,
  ) {
    final _IncrementalState? old = reuse._incremental;
    if (old == null ||
        !identical(old.owner, _incrementalOwner) ||
        !identical(old.document, document) ||
        old.noSpaceRaiseLower != document.sourceNoSpaceRaiseLower ||
        old.sections.length != document.sections.length ||
        (document.footnotes.isNotEmpty || document.endnotes.isNotEmpty) !=
            (old.notes != null)) {
      return null;
    }
    final int sectionCount = document.sections.length;
    final List<List<WmlBlock>> blocks = <List<WmlBlock>>[];
    final List<List<String>> texts = <List<String>>[];
    var firstSection = -1;
    var firstBlock = 0;
    var lastSection = -1;
    var lastCandidate = 0;
    var lastOffset = 0;
    final Set<WmlBlock> dirtyBlocks = Set<WmlBlock>.identity();
    for (int s = 0; s < sectionCount; s++) {
      final WmlSection section = document.sections[s];
      final _SectionRecord? record = old.sections[s];
      if (record == null || !identical(record.section, section)) return null;
      final List<WmlBlock> now = WordTree.visibleBlocks(
        section.blocks,
      ).toList();
      final List<String> nowTexts = <String>[
        for (final b in now) _blockText(b),
      ];
      blocks.add(now);
      texts.add(nowTexts);
      final int n = now.length;
      final int m = record.blocks.length;
      bool clean(int i, int j) =>
          identical(now[i], record.blocks[j]) &&
          nowTexts[i] == record.texts[j] &&
          !_blockContainsAny(now[i], dirtyParagraphs);
      var p = 0;
      while (p < n && p < m && clean(p, p)) {
        p++;
      }
      if (p == n && p == m) continue;
      var q = 0;
      while (q < n - p && q < m - p && clean(n - 1 - q, m - 1 - q)) {
        q++;
      }
      // One block of margin on each side: an edit can adjust a neighbour
      // (split/join, list or direction sync) without changing its text.
      var start = p > 0 ? p - 1 : 0;
      // Reflow the beginning of any keep-with-next chain the edit touches.
      while (start > 0) {
        final prior = now[start - 1];
        if (prior is! WmlParagraph || !prior.properties.keepWithNext) break;
        start--;
      }
      final int suffix = q > 0 ? q - 1 : 0;
      dirtyBlocks.addAll(now.sublist(start, n - suffix));
      if (firstSection < 0) {
        if (m == 0 || start >= m) return null;
        firstSection = s;
        firstBlock = start;
      }
      lastSection = s;
      lastCandidate = n - suffix;
      lastOffset = n - m;
    }
    _prepareLayout(document, updateFields: false);
    final _NoteState? oldNotes = old.notes;
    if (oldNotes != null) {
      // Labels in the body, note stories and their placement are valid only
      // while note order, labels, reference sections and content are equal.
      // Declared dirty note paragraphs may have changed mutable formatting
      // without changing text or identity, including inside nested tables.
      if (<WmlNote>[...document.footnotes, ...document.endnotes].any(
            (note) => note.blocks.any(
              (block) => _blockContainsAny(block, dirtyParagraphs),
            ),
          ) ||
          !_sameObjects(
            oldNotes.numbering,
            _noteNumberingSignature(document),
          ) ||
          !_sameObjects(oldNotes.content, _noteContentSignature(document))) {
        return null;
      }
      _noteStories.addAll(oldNotes.stories);
    }
    final _Recorder recorder = _recorder = _Recorder(sectionCount)
      ..dirtyBlocks = dirtyBlocks;
    try {
      if (firstSection < 0) {
        // Nothing changed in the body (for example a comment edit).
        for (int s = 0; s < sectionCount; s++) {
          recorder.sections[s] = old.sections[s];
        }
        return LaidOutDocument(
            pages: List<LaidOutPage>.of(reuse.pages),
            pageSize: document.sections.first.pageSize,
          )
          .._incremental =
              (_IncrementalState(_incrementalOwner, document, recorder.sections)
                ..flowPages = old.flowPages
                ..notes = oldNotes);
      }
      final _SectionRecord resumeRecord = old.sections[firstSection]!;
      final _Checkpoint cp = resumeRecord.checkpoints[firstBlock];
      // Note-overflow and endnote pages are made again after the flow.
      if (old.flowPages > reuse.pages.length) return null;
      final List<LaidOutPage> oldPages = reuse.pages.sublist(0, old.flowPages);
      if (cp.pagesLength > oldPages.length) return null;
      final List<LaidOutLine> lines = <LaidOutLine>[];
      final List<LaidOutBox> frames = <LaidOutBox>[];
      if (cp.hasContent) {
        if (cp.pagesLength >= oldPages.length) return null;
        final LaidOutPage partial = oldPages[cp.pagesLength];
        final _PageOrigin? origin = partial._origin;
        if (origin == null ||
            partial.lines.length < cp.lines ||
            origin.bodyFrames < cp.frames) {
          return null;
        }
        lines.addAll(partial.lines.take(cp.lines));
        frames.addAll(partial.frames.take(cp.frames));
      }
      for (int s = 0; s < firstSection; s++) {
        recorder.sections[s] = old.sections[s];
      }
      if (oldNotes != null) {
        // Finished pages keep their final slices; unfinished pages get the
        // slices reserved before the resume block.
        oldNotes.slices.forEach((int page, List<_NoteSlice> slices) {
          if (page < cp.pagesLength) {
            _noteSlices[page] = List<_NoteSlice>.of(slices);
          }
        });
        cp.pendingNotes?.forEach((int page, List<_NoteSlice> slices) {
          _noteSlices[page] = List<_NoteSlice>.of(slices);
        });
        for (final int id in oldNotes.placedOrder.take(cp.placedNotes)) {
          _placedNotes.add(id);
          _placedOrder.add(id);
        }
      } else if (cp.placedNotes != 0 || cp.pendingNotes != null) {
        return null;
      }
      final _SectionRecord prefix = _SectionRecord(resumeRecord.section)
        ..blocks.addAll(resumeRecord.blocks.take(firstBlock))
        ..texts.addAll(resumeRecord.texts.take(firstBlock))
        ..checkpoints.addAll(resumeRecord.checkpoints.take(firstBlock));
      recorder.convergence = _Convergence(
        old: old,
        oldPages: oldPages,
        lastDirtySection: lastSection,
        firstCandidateBlock: lastCandidate,
        blockOffset: lastOffset,
      );
      final List<LaidOutPage> pages = oldPages.sublist(0, cp.pagesLength);
      var paragraphIndex = _layoutSection(
        document.sections[firstSection],
        pages,
        sectionIndex: firstSection,
        paragraphIndex: cp.paragraphIndex,
        resume: (
          block: firstBlock,
          checkpoint: cp,
          lines: lines,
          frames: frames,
          prefix: prefix,
        ),
      );
      for (
        int s = firstSection + 1;
        s < sectionCount && recorder.splice == null;
        s++
      ) {
        paragraphIndex = _layoutSection(
          document.sections[s],
          pages,
          sectionIndex: s,
          paragraphIndex: paragraphIndex,
        );
      }
      final _Splice? splice = recorder.splice;
      if (splice != null) {
        WordIncrementalLayoutStats.converged++;
        _applySplice(splice, pages, oldPages, old, recorder);
      }
      return _finishLayout(
        document,
        pages,
        updateFields: false,
        state: _IncrementalState(
          _incrementalOwner,
          document,
          recorder.sections,
        ),
      );
    } finally {
      _recorder = null;
      _breakCacheReadable = false;
    }
  }

  void _applySplice(
    _Splice splice,
    List<LaidOutPage> pages,
    List<LaidOutPage> oldPages,
    _IncrementalState old,
    _Recorder recorder,
  ) {
    final _Checkpoint cp = splice.checkpoint;
    final int at = cp.pagesLength;
    final int delta = splice.delta;
    final _NoteState? oldNotes = old.notes;
    if (oldNotes != null) {
      // From here on the old flow repeats: its reserved slices for the
      // remaining pages and its later placements are the full layout's.
      _noteSlices.removeWhere((int page, _) => page >= at);
      oldNotes.slices.forEach((int page, List<_NoteSlice> slices) {
        if (page >= at) _noteSlices[page] = List<_NoteSlice>.of(slices);
      });
      for (final int id in oldNotes.placedOrder.skip(cp.placedNotes)) {
        if (_placedNotes.add(id)) _placedOrder.add(id);
      }
    }
    if (at < oldPages.length) {
      final LaidOutPage partial = oldPages[at];
      final _PageOrigin origin = partial._origin!;
      final List<LaidOutLine> tailLines = partial.lines.sublist(cp.lines);
      final List<LaidOutBox> tailFrames = partial.frames.sublist(
        cp.frames,
        origin.bodyFrames,
      );
      _shiftParagraphIndices(tailLines, tailFrames, delta);
      pages.add(
        _makePage(
          origin.section,
          partial.index,
          <LaidOutLine>[...splice.lines, ...tailLines],
          <LaidOutBox>[...splice.frames, ...tailFrames],
          sectionIndex: origin.sectionIndex,
          firstInSection: origin.firstInSection,
        ),
      );
      for (int i = at + 1; i < oldPages.length; i++) {
        LaidOutPage page = oldPages[i];
        final int body = page._origin?.bodyFrames ?? page.frames.length;
        _shiftParagraphIndices(page.lines, page.frames.take(body), delta);
        if (oldNotes != null && i == oldNotes.endnotePage) {
          // Endnotes are appended again after the flow.
          page = _withoutEndnotes(page, oldNotes);
        }
        pages.add(page);
      }
    }
    // The converged section: new checkpoints up to the splice block, then
    // the old ones; later sections keep their old records.
    final int s = splice.sectionIndex;
    final _SectionRecord oldRecord = old.sections[s]!;
    final _SectionRecord record = recorder.sections[s]!;
    _Checkpoint carry(_Checkpoint c) => c.shifted(
      delta,
      page: at,
      lineDelta: splice.lines.length - cp.lines,
      frameDelta: splice.frames.length - cp.frames,
    );
    for (int j = splice.oldBlock; j < oldRecord.blocks.length; j++) {
      record.blocks.add(oldRecord.blocks[j]);
      record.texts.add(oldRecord.texts[j]);
      record.checkpoints.add(carry(oldRecord.checkpoints[j]));
    }
    for (int t = s + 1; t < old.sections.length; t++) {
      final _SectionRecord? later = old.sections[t];
      if (later == null) {
        recorder.sections[t] = null;
        continue;
      }
      final _SectionRecord copy = _SectionRecord(later.section)
        ..blocks.addAll(later.blocks)
        ..texts.addAll(later.texts);
      for (final _Checkpoint c in later.checkpoints) {
        copy.checkpoints.add(carry(c));
      }
      recorder.sections[t] = copy;
    }
  }

  /// [page] as it was before endnotes were appended to it.
  static LaidOutPage _withoutEndnotes(LaidOutPage page, _NoteState notes) =>
      LaidOutPage(
        index: page.index,
        width: page.width,
        height: page.height,
        lines: page.lines,
        sectionIndex: page.sectionIndex,
        frames: page.frames.sublist(0, notes.endnoteFrames),
        header: page.header,
        footer: page.footer,
        notes: page.notes.sublist(0, notes.endnoteLines),
        headerBand: page.headerBand,
        footerBand: page.footerBand,
      ).._origin = page._origin;

  void _verifyIncremental(WmlDocument document, LaidOutDocument incremental) {
    final bool saved = incrementalLayout;
    incrementalLayout = false;
    final LaidOutDocument full;
    try {
      full = layout(document, updateFields: false);
    } finally {
      incrementalLayout = saved;
    }
    final String a = wordLayoutFingerprint(incremental);
    final String b = wordLayoutFingerprint(full);
    if (a == b) return;
    final List<String> la = a.split('\n');
    final List<String> lb = b.split('\n');
    var i = 0;
    while (i < la.length && i < lb.length && la[i] == lb[i]) {
      i++;
    }
    throw StateError(
      'Incremental layout differs from a full layout at fingerprint line '
      '$i:\n  incremental: ${i < la.length ? la[i] : '<end>'}\n'
      '  full:        ${i < lb.length ? lb[i] : '<end>'}',
    );
  }

  static Iterable<LaidOutBox> _bodyFrames(LaidOutPage page) => page.frames
      .take(page._origin?.bodyFrames ?? page.frames.length)
      .where((frame) => !frame.isNoteContent);

  static double _contentBottom(LaidOutPage page, {required double fallback}) {
    var bottom = fallback;
    for (final LaidOutLine line in page.lines) {
      bottom = math.max(bottom, line.y + line.height);
    }
    for (final LaidOutBox box in _bodyFrames(page)) {
      bottom = math.max(bottom, box.y + box.height);
    }
    return bottom;
  }

  int _layoutSection(
    WmlSection section,
    List<LaidOutPage> pages, {
    required int sectionIndex,
    required int paragraphIndex,
    ({
      int block,
      _Checkpoint checkpoint,
      List<LaidOutLine> lines,
      List<LaidOutBox> frames,
      _SectionRecord prefix,
    })?
    resume,
  }) {
    final _Flow flow;
    double headerBodyTop(int index, {required bool firstInSection}) =>
        _headerBodyTop(section, index, firstInSection: firstInSection);
    _AdjacentWordParagraph? adjacentParagraph;
    if (resume == null) {
      _padSectionBreak(section, pages, sectionIndex);
      final bool continuous =
          sectionIndex > 0 &&
          section.breakKind == WmlSectionBreakKind.continuous;
      flow = _Flow(
        section,
        pages,
        _makePage,
        sectionIndex,
        _noteReserve,
        headerBodyTop,
      );
      // Leave room under a floating header logo for title/body on page 1.
      flow.y = math.max(
        _bodyTopClearingLogo(section),
        headerBodyTop(flow.pageIndex, firstInSection: true),
      );
      flow.columnTop = flow.y;
      if (continuous && pages.isNotEmpty) {
        final LaidOutPage last = pages.removeLast();
        flow.current.addAll(last.lines);
        // Chrome is recreated for this section when the page is made again;
        // carrying it here would duplicate it and count it as body content.
        flow.currentFrames.addAll(_bodyFrames(last));
        flow.pageIndex = last.index;
        flow.y = _contentBottom(last, fallback: _bodyTopClearingLogo(section));
        flow.columnTop = flow.y;
      }
      _recorder?.begin(section, sectionIndex);
    } else {
      final _Checkpoint cp = resume.checkpoint;
      flow =
          _Flow(
              section,
              pages,
              _makePage,
              sectionIndex,
              _noteReserve,
              headerBodyTop,
            )
            ..pageIndex = cp.pageIndex
            ..columnIndex = cp.columnIndex
            ..y = cp.y
            ..columnTop = cp.columnTop;
      flow.current.addAll(resume.lines);
      flow.currentFrames.addAll(resume.frames);
      adjacentParagraph = cp.adjacentParagraph;
      _recorder?.begin(section, sectionIndex, prefix: resume.prefix);
    }
    final List<WmlBlock> blocks = WordTree.visibleBlocks(
      section.blocks,
    ).toList();
    var keepGroupEnd = -1;
    for (int bi = resume?.block ?? 0; bi < blocks.length; bi++) {
      final WmlBlock block = blocks[bi];
      List<LaidOutLine>? translation;
      final _Recorder? recorder = _recorder;
      if (recorder != null) {
        if (recorder.converge(
          sectionIndex,
          bi,
          flow,
          paragraphIndex,
          adjacentParagraph,
          _notesMatch,
        )) {
          return paragraphIndex;
        }
        translation = translateParagraphs && block is WmlParagraph
            ? recorder.translationSource(
                sectionIndex,
                bi,
                block,
                flow,
                adjacentParagraph,
              )
            : null;
        recorder.record(
          sectionIndex,
          block,
          flow,
          paragraphIndex,
          adjacentParagraph,
          placedNotes: _placedOrder.length,
          pendingNotes: _pendingNotes(flow.pages.length),
        );
        if (recorder.convergence != null) {
          WordIncrementalLayoutStats.blocksLaidOut++;
        }
        _breakCacheReadable =
            recorder.convergence != null &&
            !recorder.dirtyBlocks.contains(block);
      }
      switch (block) {
        case WmlContentControlBlock():
        case WmlOpaqueBlock():
          break;
        case WmlParagraph():
          if (block.properties.pageBreakBefore) {
            flow.breakPage();
            adjacentParagraph = null;
          } else if (block.properties.columnBreakBefore ||
              _hasBreak(block, WmlBreakType.column)) {
            flow.nextColumn();
            adjacentParagraph = null;
          } else if (_hasBreak(block, WmlBreakType.page)) {
            adjacentParagraph = null;
            // An authored break ends even a blank page. Word preserves the
            // blank pages between consecutive hard breaks.
            if (block.inlines
                    .where((inline) => inline is! WmlBookmarkBoundary)
                    .singleOrNull
                is WmlBreak) {
              flow.flushPage();
              paragraphIndex++;
              break;
            }
            flow.breakPage();
          }
          if (block.properties.keepWithNext && bi > keepGroupEnd) {
            keepGroupEnd = bi;
            while (keepGroupEnd + 1 < blocks.length &&
                (blocks[keepGroupEnd] as WmlParagraph)
                    .properties
                    .keepWithNext &&
                _canMeasureKeepParagraph(blocks[keepGroupEnd + 1])) {
              keepGroupEnd++;
            }
            if (keepGroupEnd > bi &&
                flow.y > flow.columnTop &&
                !flow.currentFrames.any(
                  (box) =>
                      box.frame != null && box.frame!.wrap != WmlFrameWrap.none,
                )) {
              final height = _measureKeepGroup(blocks, bi, keepGroupEnd, flow);
              final overlap = adjacentParagraph == null
                  ? 0.0
                  : _paragraphGapOverlap(adjacentParagraph, block.properties);
              final nextCapacity =
                  flow.columnIndex + 1 < section.resolvedColumnCount
                  ? flow.bottom - flow.columnTop
                  : section.contentHeight;
              if (flow.y - overlap + height > flow.bottom &&
                  height <= nextCapacity) {
                flow.nextColumn();
                adjacentParagraph = null;
              }
            }
          }
          if (adjacentParagraph != null) {
            flow.y -= _paragraphGapOverlap(adjacentParagraph, block.properties);
          }
          final ({double y, int pageIndex}) para =
              (translation == null
                  ? null
                  : _translateParagraph(
                      block,
                      section,
                      flow,
                      translation,
                      paragraphIndex,
                    )) ??
              _layoutParagraph(
                block,
                section,
                pages,
                flow.current,
                flow.currentFrames,
                flow.pageIndex,
                flow.y,
                paragraphIndex,
                originX: flow.originX,
                maxWidthOverride: flow.colWidth,
                flow: flow,
              );
          flow.y = para.y;
          flow.pageIndex = para.pageIndex;
          paragraphIndex++;
          adjacentParagraph = _afterParagraph(block.properties);
          if (flow.y > flow.bottom) {
            flow.nextColumn();
            adjacentParagraph = null;
          }
        case WmlTable():
          adjacentParagraph = null;
          final ({double y, int pageIndex}) table = _layoutTable(
            block,
            section,
            pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            flow.y,
            paragraphIndex,
            originX: flow.originX,
            maxWidthOverride: flow.colWidth,
            flow: flow,
          );
          flow.y = table.y;
          flow.pageIndex = table.pageIndex;
          paragraphIndex += _tableParagraphCount(block);
        case WmlVisual():
          adjacentParagraph = null;
          final ({double y, int pageIndex}) visual = _layoutVisual(
            block.visual,
            section,
            pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            flow.y,
            originX: flow.originX,
            maxWidthOverride: flow.colWidth,
            flow: flow,
          );
          flow.y = visual.y;
          flow.pageIndex = visual.pageIndex;
        case WmlFrame():
          adjacentParagraph = null;
          paragraphIndex = _layoutFrame(block, section, flow, paragraphIndex);
        case WmlEquation():
          adjacentParagraph = null;
          final ({double y, int pageIndex}) equation = _layoutEquation(
            block,
            section,
            pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            flow.y,
          );
          flow.y = equation.y;
          flow.pageIndex = equation.pageIndex;
        case WmlToc():
          adjacentParagraph = null;
          WordToc.ensureBody(block);
          final ({double y, int pageIndex}) toc = _layoutToc(
            block,
            section,
            pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            flow.y,
            paragraphIndex,
            flow: flow,
          );
          flow.y = toc.y;
          flow.pageIndex = toc.pageIndex;
          paragraphIndex += 1 + block.itemParagraphs.length;
      }
    }
    flow.finish();
    return paragraphIndex;
  }

  static bool _canMeasureKeepParagraph(WmlBlock block) =>
      block is WmlParagraph &&
      !block.properties.pageBreakBefore &&
      !block.properties.columnBreakBefore &&
      block.properties.dropCapLines == 0 &&
      !_hasBreak(block, WmlBreakType.page) &&
      !_hasBreak(block, WmlBreakType.column) &&
      !block.inlines.whereType<WmlRun>().any(
        (run) => run.noteRefId != null || run.inlineVisual != null,
      );

  double _measureKeepGroup(
    List<WmlBlock> blocks,
    int first,
    int last,
    _Flow flow,
  ) {
    if (!_canMeasureKeepParagraph(blocks[first])) return double.infinity;
    var height = 0.0;
    _AdjacentWordParagraph? previous;
    for (var i = first; i <= last; i++) {
      final para = blocks[i] as WmlParagraph;
      final props = para.properties;
      if (previous != null) height -= _paragraphGapOverlap(previous, props);
      final lines = <LaidOutLine>[];
      final layout = _layoutParagraph(
        para,
        flow.section,
        [],
        lines,
        [],
        flow.pageIndex,
        0,
        0,
        maxWidthOverride: flow.colWidth,
        allowBreak: false,
        measureBody: true,
      );
      if (i == last) {
        if (props.keepTogether || lines.isEmpty) {
          height += layout.y - props.spacingAfter;
        } else {
          final count = props.widowControl == false
              ? 1
              : math.min(lines.length, lines.length == 3 ? 3 : 2);
          final line = lines[count - 1];
          height += line.y + line.height;
        }
      } else {
        height += layout.y;
        previous = _afterParagraph(props);
      }
    }
    return height;
  }

  static bool _hasBreak(WmlParagraph paragraph, WmlBreakType type) {
    for (final WmlInline inline in paragraph.inlines) {
      if (inline is WmlBreak && inline.type == type) {
        return true;
      }
    }
    return false;
  }

  int _layoutParagraphCount(WmlSection section) {
    return _layoutParagraphCountIn(section.blocks);
  }

  int _layoutParagraphCountIn(List<WmlBlock> blocks) =>
      WordTree.paragraphs(blocks).length;

  static int _tableParagraphCount(WmlTable table) => table.rows
      .expand((row) => row.cells)
      .map((cell) => WordTree.paragraphs(cell.blocks).length)
      .fold(0, (count, length) => count + length);

  List<double> _columnWidths(
    WmlTable table,
    WmlSection section, [
    double? maxWidth,
  ]) {
    final int columns = WordTable.columnCount(table).clamp(1, 64);
    final double available = maxWidth ?? section.contentWidth;
    if (table.grid.isNotEmpty) {
      final List<double> grid = table.grid.length >= columns
          ? table.grid.sublist(0, columns)
          : table.grid;
      if (table.grid.length >= columns) {
        final double used = grid.fold<double>(0, (double a, double b) => a + b);
        if (used > available && used > 0) {
          final double scale = available / used;
          return <double>[for (final double w in grid) w * scale];
        }
        return grid;
      }
      final double used = table.grid.fold<double>(
        0,
        (double a, double b) => a + b,
      );
      final int missing = columns - table.grid.length;
      final double rest = ((available - used) / missing).clamp(36, available);
      return <double>[...table.grid, ...List<double>.filled(missing, rest)];
    }
    return List<double>.filled(columns, available / columns);
  }

  ({double y, int pageIndex}) _layoutParagraph(
    WmlParagraph paragraph,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> current,
    List<LaidOutBox> currentFrames,
    int pageIndex,
    double y,
    int paragraphIndex, {
    double? originX,
    double? maxWidthOverride,
    String? sourceText,
    int? tocTargetParagraph,
    String? overlayText,
    bool tocLeader = false,
    _Flow? flow,
    bool allowBreak = true,
    bool measureBody = false,
  }) {
    if (!measureBody && !_breakCacheReadable) {
      // Dirty blocks and full layouts cannot retain breaks from an earlier
      // version of this paragraph. Clear before any empty or frame-wrapping
      // path, which may produce no replacement cache entry; otherwise a later
      // clean layout could resurrect those stale glyphs after the flow moves.
      _breakCache[paragraph] = null;
    }
    final WmlRunProps runProps = paragraph.inlines.isEmpty
        ? paragraph.properties.importedParagraphMark ??
              WmlRunEdit.propsAt(paragraph, 0)
        : WmlRunEdit.propsAt(paragraph, 0);
    final double fontSize = runProps.fontSizePoints;
    final firstRune = paragraph.text.runes.firstOrNull;
    final int firstCodePoint = firstRune == null || firstRune == 0x09
        ? 0x20
        : firstRune;
    final SfntFont? firstFace = _faceFor(firstCodePoint, runProps);
    final FontMetrics? metrics =
        measureFont?.call(firstCodePoint, fontSize, runProps) ??
        (firstFace == null
            ? null
            : FontMetrics(font: firstFace, fontSizePoints: fontSize));
    final double lineHeight = _lineHeight(
      paragraph.properties,
      metrics,
      fontSize,
    );
    final String? listLabel = paragraph.properties.listLabel;
    final double hanging = paragraph.properties.indent.hanging;
    final double indentLeft = paragraph.properties.indent.left;
    final double firstLineShift = hanging > 0
        ? (listLabel == null && paragraph.properties.bidiBaseLevel != 1
              ? -hanging
              : 0)
        : paragraph.properties.indent.firstLine;
    // Hanging indent: marker sits in [left-hanging, left); text wraps at left.
    final double markerSlot = listLabel == null
        ? 0
        : (hanging > 0
              ? hanging
              : math.min(18, indentLeft > 0 ? indentLeft : 16));
    final double textLeft = indentLeft > 0
        ? indentLeft
        : (listLabel == null ? 0 : markerSlot);
    // [maxWidthOverride] is the content box (e.g. cell inner width). Indents
    // still consume that box ? otherwise wrapped text overflows the right edge.
    final double contentBox = maxWidthOverride ?? section.contentWidth;
    final double maxWidth =
        (contentBox - textLeft - paragraph.properties.indent.right).clamp(
          12.0,
          section.pageSize.width,
        );
    final double firstLineWidth = (maxWidth - firstLineShift).clamp(
      12.0,
      section.pageSize.width,
    );
    // Empty paragraphs are a full blank line in Word. A tab is content.
    if (!paragraph.text.contains('\t') &&
        paragraph.text.trim().isEmpty &&
        listLabel == null &&
        !paragraph.properties.pageNumberField &&
        paragraph.properties.noteId == null) {
      if (!measureBody) _breakCache[paragraph] = null;
      final lineExtent = paragraph.properties.spacingBefore + lineHeight;
      final gap = lineExtent + paragraph.properties.spacingAfter;
      // Move the blank line itself when it will not fit. Advancing after
      // consuming its height would lose it at a page or column boundary.
      if (allowBreak &&
          flow != null &&
          y + lineExtent > flow.bottom &&
          (y > flow.columnTop || flow.hasContent)) {
        flow.nextColumn();
        return (y: flow.y + gap, pageIndex: flow.pageIndex);
      }
      return (y: y + gap, pageIndex: pageIndex);
    }
    final String text = paragraph.text;
    // Table cells and frames (laid out without page breaks) use a wider em
    // so the painted text stays inside their border.
    final double em = allowBreak || measureBody
        ? fallbackWidthFactor
        : math.max(fallbackWidthFactor, 0.72);
    final propsByOffset = <int, WmlRunProps>{};
    WmlRunProps propsAt(int offset) => propsByOffset.putIfAbsent(
      offset,
      () => WmlRunEdit.propsAt(paragraph, offset),
    );
    // Inline pictures: one U+FFFC per picture (WmlRun.inlineVisual). It
    // advances by the picture's width and is shaped as a space glyph, so no
    // painter draws a character there; the picture itself becomes a box on
    // the baseline once the line is placed.
    final inlinePictures = <int, OfficeVisual>{};
    final displayLabels =
        <int, ({String text, int end, double scale, bool note})>{};
    {
      var offset = 0;
      for (final WmlInline inline in paragraph.inlines) {
        if (inline is WmlBreak) {
          offset++;
          continue;
        }
        if (inline is! WmlRun) continue;
        final WmlVisual? picture = inline.inlineVisual;
        if (picture != null) inlinePictures[offset] = picture.visual;
        final label = _noteNumbering?.referenceLabel(inline);
        if (label != null) {
          displayLabels[offset] = (
            text: label,
            end: offset + inline.text.length,
            scale: 1,
            note: true,
          );
        }
        offset += inline.text.length;
      }
    }
    if (paragraph.inlines.whereType<WmlRun>().any(
      (run) => run.properties.smallCaps || run.properties.allCaps,
    )) {
      for (final segment in WordSmallCaps.segments(text)) {
        if (segment.text == text.substring(segment.start, segment.end) ||
            !(propsAt(segment.start).smallCaps ||
                propsAt(segment.start).allCaps) ||
            inlinePictures.containsKey(segment.start) ||
            displayLabels.containsKey(segment.start)) {
          continue;
        }
        // A grapheme that crosses a run with different formatting must stay
        // intact. Do not claim that differently styled marks share one run.
        final props = propsAt(segment.start);
        if (!List.generate(
          segment.end - segment.start,
          (i) => segment.start + i,
        ).every((offset) => identical(propsAt(offset), props))) {
          continue;
        }
        displayLabels[segment.start] = (
          text: segment.text,
          end: segment.end,
          // Prefer full-size capitals for malformed input with both flags on.
          // This is a display fallback; retain the authored text and flags.
          scale: props.allCaps ? 1 : segment.scale,
          note: false,
        );
      }
    }
    double widthAt(int cp, int offset) {
      final OfficeVisual? picture = inlinePictures[offset];
      if (picture != null) return math.min(picture.width, maxWidth);
      final props = propsAt(offset);
      return _advanceOf(
        cp,
        props.fontSizePoints *
            props.vertAlign.fontScale *
            (displayLabels[offset]?.scale ?? 1),
        em,
        props,
      );
    }

    int glyphIdAt(int cp, int offset) => inlinePictures.containsKey(offset)
        ? _faceFor(0x20, propsAt(offset))?.glyphIdFor(0x20) ?? 0
        : _faceFor(cp, propsAt(offset))?.glyphIdFor(cp) ?? 0;

    List<ShapedGlyph> displayReplacements(List<ShapedGlyph> source) {
      final result = <ShapedGlyph>[];
      var skipUntil = -1;
      for (final glyph in source) {
        if (glyph.logicalIndex < skipUntil) continue;
        final label = displayLabels[glyph.logicalIndex];
        if (label == null) {
          result.add(glyph);
          continue;
        }
        skipUntil = label.end;
        for (final cp in label.text.isEmpty ? const [0] : label.text.runes) {
          final replacement = ShapedGlyph(
            codePoint: cp,
            glyphId: glyphIdAt(cp, glyph.logicalIndex),
            advance: cp == 0 ? 0 : widthAt(cp, glyph.logicalIndex),
            logicalIndex: glyph.logicalIndex,
            // Numeric and Roman note labels form one left-to-right unit.
            level: label.note && glyph.level.isOdd
                ? glyph.level + 1
                : glyph.level,
          );
          result.add(replacement);
        }
      }
      return result;
    }

    // An actual line can be unsupported even when the full paragraph was
    // measurable. Preserve the original font/scalar advances before applying
    // host metrics so a declined fragment does not reuse a different context.
    // Repeated display-label scalars share this source/style and scalar width.
    final fallbackAdvances = <(int, int, int), double>{};
    final hasMeasuredTabs =
        text.contains('\t') && paragraph.properties.bidiBaseLevel != 1;
    final tabStops = [...paragraph.properties.tabs]
      ..sort((a, b) => a.position.compareTo(b.position));
    List<ShapedGlyph> measureTabs(List<ShapedGlyph> glyphs) {
      if (!hasMeasuredTabs) return glyphs;
      final result = [...glyphs];
      var pen =
          textLeft +
          (glyphs.firstOrNull?.logicalIndex == 0 ? firstLineShift : 0);
      for (var i = 0; i < glyphs.length; i++) {
        final glyph = glyphs[i];
        if (glyph.codePoint == 0x0a || glyph.codePoint == 0x0d) {
          pen = textLeft;
          continue;
        }
        if (glyph.codePoint != 0x09) {
          pen += glyph.advance;
          continue;
        }
        var fieldWidth = 0.0;
        var decimalWidth = 0.0;
        var foundDecimal = false;
        for (var j = i + 1; j < glyphs.length; j++) {
          final next = glyphs[j];
          if (next.codePoint == 0x09 ||
              next.codePoint == 0x0a ||
              next.codePoint == 0x0d) {
            break;
          }
          if (next.codePoint == 0x2e) foundDecimal = true;
          if (!foundDecimal) decimalWidth += next.advance;
          fieldWidth += next.advance;
        }
        final stop = tabStops
            .where((stop) => stop.position > pen + .001)
            .firstOrNull;
        final target =
            stop?.position ??
            ((pen / kDefaultTabWidth).floor() + 1) * kDefaultTabWidth;
        final inset = switch (stop?.alignment ?? WmlTabAlignment.left) {
          WmlTabAlignment.left => 0.0,
          WmlTabAlignment.center => fieldWidth / 2,
          WmlTabAlignment.right => fieldWidth,
          WmlTabAlignment.decimal => decimalWidth,
        };
        final advance = math.max(0.0, target - inset - pen);
        result[i] = _withMeasuredAdvance(glyph, advance);
        pen += advance;
      }
      return result;
    }

    List<ShapedGlyph> measuredLine(List<ShapedGlyph> presented) {
      final host = measureRun;
      if (host == null) return measureTabs(presented);
      final fallback = <ShapedGlyph>[
        for (final glyph in presented)
          if (fallbackAdvances[(
                glyph.logicalIndex,
                glyph.codePoint,
                glyph.glyphId,
              )]
              case final advance?)
            advance == glyph.advance
                ? glyph
                : _withMeasuredAdvance(glyph, advance)
          else
            // Selected hyphens are created after paragraph measurement and
            // retain their independent scalar metrics and source ownership.
            glyph,
      ];
      return measureTabs(
        _measureWordRuns(
          glyphs: fallback,
          text: text,
          paragraph: paragraph,
          propsAt: propsAt,
          labels: displayLabels,
          pictures: inlinePictures.keys.toSet(),
          measure: host,
        ),
      );
    }

    List<ShapedGlyph> measuredRuns(List<ShapedGlyph> source) {
      final presented = displayLabels.isEmpty
          ? source
          : displayReplacements(source);
      if (measureRun == null) return measureTabs(presented);
      for (final glyph in presented) {
        fallbackAdvances[(glyph.logicalIndex, glyph.codePoint, glyph.glyphId)] =
            glyph.advance;
      }
      return measuredLine(presented);
    }

    // Widths and glyph IDs are resolved before wrapping, using each run's
    // actual family, style and size. Scaling only after wrapping lets bold or
    // large runs overflow the line and produces incorrect PDF positioning.
    ({double dx, double dy}) markAttach(ShapedGlyph base, ShapedGlyph mark) {
      final baseProps = propsAt(base.logicalIndex);
      final markProps = propsAt(mark.logicalIndex);
      final baseFace = _faceFor(base.codePoint, baseProps);
      final markFace = _faceFor(mark.codePoint, markProps);
      final baseSize =
          baseProps.fontSizePoints *
          baseProps.vertAlign.fontScale *
          (displayLabels[base.logicalIndex]?.scale ?? 1);
      final markSize =
          markProps.fontSizePoints *
          markProps.vertAlign.fontScale *
          (displayLabels[mark.logicalIndex]?.scale ?? 1);
      if (baseFace == null ||
          !identical(baseFace, markFace) ||
          baseSize != markSize) {
        return (dx: -base.advance / 2, dy: 0);
      }
      return GposMarkToBase.fnFor(baseFace, baseSize)(base, mark);
    }

    final bool wrapsFrames =
        allowBreak &&
        flow != null &&
        currentFrames.any(
          (box) => box.frame != null && box.frame!.wrap != WmlFrameWrap.none,
        );
    // Wrapping uses a separate breaker and does not replace the ordinary
    // paragraph cache. Discard an older entry: a dirty paragraph may change
    // its font or text while wrapping, then later move off the frame's page.
    if (wrapsFrames) {
      _breakCache[paragraph] = null;
    }
    // Line breaks of a paragraph the caller proved unchanged since the last
    // layout (incremental layout, clean block) are reused when the width
    // environment is the same; shaping dominates layout cost.
    final _BreakCache? cachedBreaks =
        measureBody || wrapsFrames || !_breakCacheReadable
        ? null
        : _breakCache[paragraph];
    final List<BrokenLine>? reusedBreaks =
        cachedBreaks != null &&
            cachedBreaks.matches(
              maxWidth: maxWidth,
              allowBreak: allowBreak,
              document: _layoutDoc,
            )
        ? cachedBreaks.lines
        : null;
    if (reusedBreaks != null) WordIncrementalLayoutStats.breaksReused++;
    final hyphenationOffsets = reusedBreaks != null
        ? const <int>[]
        : _layoutDoc?.autoHyphenation == true &&
              paragraph.properties.suppressAutoHyphens != true
        ? OfficeHyphenator.breakOffsets(
            text,
            // Native Word can use a later German syllable boundary even
            // when the source word already has an optional hyphen.
            allowGermanSoftHyphenAlternatives: true,
            language:
                paragraph.properties.proofingLanguage ??
                _layoutDoc?.proofingLanguage,
            languageAt: (offset) =>
                propsAt(offset).proofingLanguage ??
                paragraph.properties.proofingLanguage ??
                _layoutDoc?.proofingLanguage,
          )
        : const <int>[];
    int sourceStyleOffset(ShapedGlyph glyph) =>
        glyph.isDiscretionaryHyphen && glyph.sourceLength == 0
        ? (glyph.logicalIndex - 1).clamp(0, text.length)
        : glyph.logicalIndex;

    final justify =
        paragraph.properties.justification == WmlJustification.justify ||
        paragraph.properties.justification == WmlJustification.distributed;
    final PreparedLineBreaker? wrapBreaker = wrapsFrames
        ? LineBreaker.prepare(
            text: text,
            balanceLines: false,
            hyphenationOffsets: hyphenationOffsets,
            widthOf: (cp) => widthAt(cp, 0),
            widthAt: widthAt,
            glyphIdAt: glyphIdAt,
            markAttachOf: markAttach,
            baseLevel: paragraph.properties.bidiBaseLevel,
            justify: justify,
            measureLine: measureRun == null && !hasMeasuredTabs
                ? null
                : measuredLine,
            ligate:
                displayLabels.isEmpty && measureRun == null && !hasMeasuredTabs
                ? null
                : measuredRuns,
          )
        : null;
    final List<BrokenLine> broken = wrapsFrames
        ? const []
        : reusedBreaks ??
              LineBreaker.breakLines(
                text: text,
                balanceLines: false,
                hyphenationOffsets: hyphenationOffsets,
                maxWidth: maxWidth,
                firstLineWidth: firstLineWidth == maxWidth
                    ? null
                    : firstLineWidth,
                widthOf: (cp) => widthAt(cp, 0),
                widthAt: widthAt,
                glyphIdAt: glyphIdAt,
                markAttachOf: markAttach,
                baseLevel: paragraph.properties.bidiBaseLevel,
                justify: justify,
                measureLine: measureRun == null && !hasMeasuredTabs
                    ? null
                    : measuredLine,
                breakLongWords: !allowBreak && !measureBody,
                ligate:
                    displayLabels.isEmpty &&
                        measureRun == null &&
                        !hasMeasuredTabs
                    ? null
                    : measuredRuns,
              );
    if (!measureBody && !wrapsFrames && reusedBreaks == null) {
      _breakCache[paragraph] = _BreakCache(
        broken,
        maxWidth: maxWidth,
        allowBreak: allowBreak,
        document: _layoutDoc,
      );
    }
    var cursorY = y + paragraph.properties.spacingBefore;
    var idx = pageIndex;
    var lineOrigin = originX ?? section.margins.left;
    final int dropLines = paragraph.properties.dropCapLines;
    final double dropWidth = dropLines > 0 ? fontSize * 2.4 : 0;
    // Each line owns its strut. A large opening run must not enlarge all
    // subsequent lines, nor may one family's metrics stand in for another.
    final faceMetrics = <(WmlRunProps, int), FontMetrics?>{};
    final lineMetrics = <BrokenLine, ({double ascent, double height})>{};
    final lastTextOffset = text.trimRight().length;
    ({double ascent, double height}) metricsOn(BrokenLine line) =>
        lineMetrics.putIfAbsent(line, () {
          var ascent = 0.0;
          var descent = 0.0;
          var count = 0;
          void include(WmlRunProps props, int cp, {double displayScale = 1}) {
            final size = props.fontSizePoints;
            // A tab participates in the line's strut with its run's font,
            // whose cmap need not contain an actual tab glyph.
            final metricPoint = cp == 0x09 ? 0x20 : cp;
            final metric = faceMetrics.putIfAbsent((props, metricPoint), () {
              final host = measureFont?.call(metricPoint, size, props);
              if (host != null) return host;
              final face = _faceFor(metricPoint, props);
              return face == null
                  ? null
                  : _metricsCache.putIfAbsent((
                      face,
                      size,
                    ), () => FontMetrics(font: face, fontSizePoints: size));
            });
            final runAscent = metric?.typographicAscender ?? size * 0.8;
            final height = metric?.typographicLineHeight ?? size * 1.32;
            ascent = math.max(ascent, runAscent);
            descent = math.max(descent, height - runAscent);
            if (props.positionHalfPoints != 0 &&
                paragraph.properties.lineSpacingRule !=
                    WmlLineSpacingRule.exact &&
                _layoutDoc?.sourceNoSpaceRaiseLower != true) {
              // Position moves a run without scaling it. Keep the ordinary
              // unshifted strut, then include the painted run's shifted
              // ascent/descent so auto/atLeast lines reserve enough space.
              // Superscript/subscript and small-cap display scaling stay
              // independent; exact spacing and noSpaceRaiseLower opt out.
              final scale = props.vertAlign.fontScale * displayScale;
              final shift = props.baselineShift;
              ascent = math.max(ascent, runAscent * scale - shift);
              descent = math.max(descent, (height - runAscent) * scale + shift);
            }
            count++;
          }

          for (final glyph in line.glyphs) {
            if (inlinePictures.containsKey(glyph.logicalIndex)) continue;
            include(
              propsAt(sourceStyleOffset(glyph)),
              glyph.codePoint,
              displayScale: displayLabels[glyph.logicalIndex]?.scale ?? 1,
            );
          }
          // The paragraph mark is an unpainted final-line participant. Its
          // effective font comes from defaults/styles/direct mark properties.
          final marker = paragraph.properties.importedParagraphMark;
          if (marker != null && line.logicalEnd >= lastTextOffset) {
            include(marker, firstCodePoint);
          }
          if (count == 0) include(runProps, 0x20);
          return (ascent: ascent, height: ascent + descent);
        });

    double textHeightOfLine(BrokenLine line) {
      final height = metricsOn(line).height;
      return switch (paragraph.properties.lineSpacingRule) {
        WmlLineSpacingRule.exact => paragraph.properties.lineSpacing,
        WmlLineSpacingRule.atLeast => math.max(
          height,
          paragraph.properties.lineSpacing,
        ),
        WmlLineSpacingRule.auto => height * paragraph.properties.lineSpacing,
      };
    }

    double pictureHeightOn(BrokenLine line) {
      var tallest = 0.0;
      for (final ShapedGlyph g in line.glyphs) {
        final OfficeVisual? picture = inlinePictures[g.logicalIndex];
        if (picture != null) tallest = math.max(tallest, picture.height);
      }
      return tallest;
    }

    double textAscentOn(BrokenLine line) => metricsOn(line).ascent;

    // An inline picture sits on the baseline: a picture taller than the
    // text ascent raises the baseline and the line (exact spacing clips).
    double heightOfLine(BrokenLine line) {
      final double text = textHeightOfLine(line);
      if (paragraph.properties.lineSpacingRule == WmlLineSpacingRule.exact) {
        return text;
      }
      final double picture = pictureHeightOn(line);
      final double ascent = textAscentOn(line);
      if (picture <= ascent) return text;
      return text + (picture - ascent);
    }

    final canPlanBreaks =
        allowBreak &&
        wrapBreaker == null &&
        broken.length > 1 &&
        !paragraph.inlines.whereType<WmlRun>().any(
          (run) => run.noteRefId != null && !run.noteRefEndnote,
        );
    double nextCapacity(_Flow currentFlow) =>
        currentFlow.columnIndex + 1 < section.resolvedColumnCount
        ? _bodyBottom(section, idx) - currentFlow.columnTop
        : section.contentHeight;
    if (flow != null &&
        canPlanBreaks &&
        paragraph.properties.keepTogether &&
        y > flow.columnTop) {
      final height = broken.fold(
        0.0,
        (total, line) => total + heightOfLine(line),
      );
      // An oversized paragraph can still flow across page boundaries.
      if (cursorY + height > _bodyBottom(section, idx) &&
          height <= nextCapacity(flow)) {
        flow.nextColumn();
        cursorY = flow.y;
        idx = flow.pageIndex;
        lineOrigin = flow.originX;
      }
    }
    final int lineStart = current.length;
    final double paraTop = cursorY;
    var lineNumber = 0;
    var segmentStartLine = 0;
    var wrappedOffset = 0;
    while (wrapBreaker == null
        ? lineNumber < broken.length
        : wrappedOffset < text.length || lineNumber == 0) {
      var line = wrapBreaker == null
          ? broken[lineNumber]
          : BrokenLine(
              glyphs: const [],
              width: 0,
              logicalStart: 0,
              logicalEnd: 0,
              justificationRatio: 0,
            );
      var nextOffset = wrappedOffset;
      var lineLeft = lineOrigin + textLeft;
      var lineWidth = lineNumber == 0 ? firstLineWidth : maxWidth;
      void rebreakForFrame() {
        if (wrapBreaker == null) return;
        final shift = lineNumber == 0 ? firstLineShift : 0.0;
        final available = lineNumber == 0 ? firstLineWidth : maxWidth;
        final rtl = paragraph.properties.bidiBaseLevel == 1;
        var band = _frameWrapBand(
          currentFrames,
          left: lineOrigin + textLeft + shift,
          width: available,
          y: cursorY,
          height: lineHeight,
          rightToLeft: rtl,
        );
        var candidate = wrapBreaker.breakNext(
          start: wrappedOffset,
          maxWidth: band.width,
        );
        // An unbreakable word must clear the frame before using the ordinary
        // oversized-word behavior; it must not paint through a narrow band.
        if (candidate.line.width > band.width + 0.001 &&
            band.width < available) {
          band = _frameWrapBand(
            currentFrames,
            left: lineOrigin + textLeft + shift,
            width: available,
            y: cursorY,
            height: lineHeight,
            rightToLeft: rtl,
            minimumWidth: candidate.line.width.clamp(12.0, available),
          );
          candidate = wrapBreaker.breakNext(
            start: wrappedOffset,
            maxWidth: band.width,
          );
        }
        cursorY = band.y;
        lineLeft = band.left;
        lineWidth = band.width;
        line = candidate.line;
        nextOffset = candidate.nextOffset;
      }

      rebreakForFrame();
      var lineH = heightOfLine(line);
      if (flow != null &&
          canPlanBreaks &&
          paragraph.properties.widowControl != false &&
          dropLines == 0 &&
          (lineNumber > 0 || y > flow.columnTop) &&
          cursorY > flow.columnTop) {
        final remaining = broken.length - lineNumber;
        final placedOnColumn = lineNumber - segmentStartLine;
        if (remaining >= 2 &&
            (placedOnColumn == 0 || remaining == 2 && placedOnColumn >= 2)) {
          final capacity = nextCapacity(flow);
          var groupHeight = lineH + heightOfLine(broken[lineNumber + 1]);
          // Three lines cannot be split into two groups of at least two.
          if (placedOnColumn == 0 && remaining == 3) {
            final thirdHeight = heightOfLine(broken[lineNumber + 2]);
            if (groupHeight + thirdHeight <= capacity) {
              groupHeight += thirdHeight;
            }
          }
          if (cursorY + groupHeight > _bodyBottom(section, idx) &&
              groupHeight <= capacity) {
            flow.nextColumn();
            cursorY = flow.y;
            idx = flow.pageIndex;
            lineOrigin = flow.originX;
            segmentStartLine = lineNumber;
          }
        }
      }
      var noteIds = _noteIds(
        paragraph,
        line.glyphs.map((ShapedGlyph g) => g.logicalIndex),
      ).toList();
      double occupiedBottom() {
        var bottom = cursorY + lineH;
        for (final LaidOutLine l in current) {
          bottom = math.max(bottom, l.y + l.height);
        }
        for (final LaidOutBox b in currentFrames) {
          if (!b.isNoteContent && b.kind != LaidOutBoxKind.columnSep) {
            bottom = math.max(bottom, b.y + b.height);
          }
        }
        return bottom;
      }

      while (allowBreak &&
          (cursorY + lineH > _bodyBottom(section, idx) ||
              (_minimumNotes(noteIds, section, idx) > 0 &&
                  occupiedBottom() + _minimumNotes(noteIds, section, idx) >
                      _bodyBottom(section, idx)))) {
        if (current.isEmpty &&
            currentFrames.isEmpty &&
            _noteReserve(idx) == 0 &&
            cursorY <= (flow?.columnTop ?? section.margins.top) + 0.01) {
          if (_minimumNotes(noteIds, section, idx) > 0) {
            throw StateError(
              'A note reference and its first line cannot fit the page',
            );
          }
          break; // Retain the existing oversized-body-line behavior.
        }
        // A new note affects every column: move its marker to a new page when
        // reserving its first line would overlap earlier column content.
        final bool noteBreak = _minimumNotes(noteIds, section, idx) > 0;
        if (flow != null) {
          flow.y = cursorY;
          if (noteBreak) {
            flow.flushPage();
          } else {
            flow.nextColumn();
          }
          cursorY = flow.y;
          idx = flow.pageIndex;
          lineOrigin = flow.originX;
        } else {
          pages.add(
            _makePage(
              section,
              idx,
              current,
              currentFrames,
              sectionIndex: pages.isEmpty ? 0 : pages.last.sectionIndex,
              firstInSection: false,
            ),
          );
          current.clear();
          currentFrames.clear();
          idx++;
          cursorY = section.margins.top;
        }
        segmentStartLine = lineNumber;
        rebreakForFrame();
        lineH = heightOfLine(line);
        noteIds = _noteIds(
          paragraph,
          line.glyphs.map((g) => g.logicalIndex),
        ).toList();
      }
      if (allowBreak) _reserveNotes(noteIds, section, idx, occupiedBottom());
      final double x0 = wrapBreaker == null
          ? lineOrigin + textLeft + (lineNumber == 0 ? firstLineShift : 0)
          : lineLeft;
      double x = x0;
      if (paragraph.properties.justification == WmlJustification.center) {
        x += (lineWidth - line.width) / 2;
      } else if (paragraph.properties.justification == WmlJustification.right) {
        x += lineWidth - line.width;
      }
      var gx = x;
      final double pictureAscent =
          paragraph.properties.lineSpacingRule == WmlLineSpacingRule.exact
          ? 0.0
          : pictureHeightOn(line);
      final double baselineAscent = math.max(textAscentOn(line), pictureAscent);
      final naturalHeight = metricsOn(line).height;
      // With default paragraph text alignment Word positions fixed-spacing
      // text at 80% of the line box, independent of run font/size. Native Word
      // probes cover 8–24pt text in four families and 10–120pt fixed spacing.
      // Do not derive this baseline by subtracting one face's descender.
      final baselineLeading = switch (paragraph.properties.lineSpacingRule) {
        WmlLineSpacingRule.exact => lineHeight * 0.8 - baselineAscent,
        WmlLineSpacingRule.atLeast => heightOfLine(line) - naturalHeight,
        WmlLineSpacingRule.auto => 0.0,
      };
      final List<LaidOutGlyph> glyphs = <LaidOutGlyph>[];
      // Mark attachment can replace a shaped glyph object. Track display
      // offsets by source ownership rather than that transient identity.
      final displayOffsets = <int, int>{};
      for (final ShapedGlyph g in line.glyphs) {
        final WmlRunProps props = propsAt(sourceStyleOffset(g));
        final double baseSize = props.fontSizePoints;
        final display = g.isDiscretionaryHyphen
            ? null
            : displayLabels[g.logicalIndex];
        final double size =
            baseSize * props.vertAlign.fontScale * (display?.scale ?? 1);
        glyphs.add(
          LaidOutGlyph(
            glyph: g,
            // The visible break has separate source ownership.
            displayText: g.isDiscretionaryHyphen ? '-' : display?.text,
            displayOffset: displayOffsets[g.logicalIndex] ?? 0,
            sourceEnd: g.isDiscretionaryHyphen
                ? g.logicalIndex + (g.sourceLength ?? 0)
                : display?.end,
            actualText: g.isDiscretionaryHyphen
                ? (g.sourceLength == 0 ? '' : '\u00ad')
                : display != null && !display.note
                ? text.substring(g.logicalIndex, display.end)
                : null,
            x: gx + g.paintDx,
            y:
                cursorY +
                baselineLeading +
                baselineAscent +
                props.baselineShift -
                g.paintDy,
            color: props.color,
            fontSize: size,
            bold: props.bold,
            underline: props.underline,
            italic: props.italic,
            kerning:
                (props.kerningHalfPoints ?? 0) > 0 &&
                size * 2 >= props.kerningHalfPoints!,
            strike: props.strike,
            highlight: WmlHighlight.toRgb(props.highlight) ?? props.highlight,
            fontFamily: OfficeTypeface.familyForRun(
              props,
              g.codePoint == 0 && display == null
                  ? _sourceCodePoint(text, g.logicalIndex)
                  : g.codePoint,
            ),
            vertAlign: props.vertAlign,
            positionHalfPoints: props.positionHalfPoints,
            hyperlink: WordLink.at(paragraph, g.logicalIndex),
            commentIds: WordComment.idsAt(paragraph, g.logicalIndex),
            advance: g.advance,
            paintDx: g.paintDx,
            paintDy: g.paintDy,
          ).._baselineShift = props.baselineShift,
        );
        if (display != null) {
          displayOffsets[g.logicalIndex] =
              (displayOffsets[g.logicalIndex] ?? 0) +
              (g.codePoint > 0xffff ? 2 : 1);
        }
        gx += g.advance;
      }
      final bool paraRtl =
          paragraph.properties.rightToLeft == true ||
          paragraph.properties.bidiBaseLevel == 1;
      final double markerX = listLabel == null
          ? 0
          : (paraRtl ? lineLeft + lineWidth + 2 : lineLeft - markerSlot);
      final LaidOutLine laid = LaidOutLine(
        glyphs: glyphs,
        x: x,
        y: cursorY,
        width: line.width,
        height: lineH,
        pageIndex: idx,
        justification: paragraph.properties.justification,
        paragraphIndex: paragraphIndex,
        listLabel: listLabel,
        listMarkerX: markerX,
        isParagraphStart: lineNumber == 0,
        sourceText: sourceText ?? text,
        sourceParagraph: paragraph,
        tocTargetParagraph: tocTargetParagraph,
        overlayText:
            (wrapBreaker == null
                ? lineNumber == broken.length - 1
                : nextOffset >= text.length)
            ? overlayText
            : null,
        tocLeader:
            tocLeader &&
            (wrapBreaker == null
                ? lineNumber == broken.length - 1
                : nextOffset >= text.length),
        justificationRatio: line.justificationRatio,
        boxX: wrapBreaker == null ? lineOrigin : lineLeft,
        boxWidth: wrapBreaker == null ? contentBox : lineWidth,
      );
      laid.applyJustification(targetWidth: lineWidth);
      if (wrapBreaker == null) {
        laid._baseline = (leading: baselineLeading, ascent: baselineAscent);
      }
      current.add(laid);
      if (inlinePictures.isNotEmpty) {
        for (final LaidOutGlyph placed in laid.glyphs) {
          final OfficeVisual? picture =
              inlinePictures[placed.glyph.logicalIndex];
          if (picture == null) continue;
          final double width = math.min(picture.width, lineWidth);
          final double height = picture.height;
          currentFrames.add(
            _visualBox(
              picture,
              placed.x,
              cursorY + baselineAscent - height,
              width,
              height,
            ),
          );
        }
      }
      cursorY += lineH;
      lineNumber++;
      wrappedOffset = nextOffset;
    }
    if (dropWidth > 0 && current.length > lineStart) {
      final LaidOutLine first = current[lineStart];
      first.x += dropWidth;
      for (
        int i = lineStart + 1;
        i < current.length && i < lineStart + dropLines;
        i++
      ) {
        current[i].x += dropWidth * 0.35;
      }
      currentFrames.add(
        LaidOutBox(
          x: lineOrigin,
          y: first.y,
          width: dropWidth,
          height: lineHeight * dropLines,
          fillColor: '',
          strokeColor: '',
          kind: LaidOutBoxKind.frame,
          paragraphIndex: paragraphIndex,
        ),
      );
    }
    final String? shade = paragraph.properties.shadingFill;
    final String? border = paragraph.properties.borderColor;
    if ((shade != null && shade.isNotEmpty) ||
        (border != null && border.isNotEmpty)) {
      currentFrames.add(
        LaidOutBox(
          x: lineOrigin,
          y: paraTop,
          width: maxWidth,
          height: math.max(lineHeight, cursorY - paraTop),
          fillColor: shade,
          strokeColor: border ?? '',
          kind: LaidOutBoxKind.paragraphShade,
          paragraphIndex: paragraphIndex,
        ),
      );
    }
    return (y: cursorY + paragraph.properties.spacingAfter, pageIndex: idx);
  }

  ({double y, int pageIndex}) _layoutToc(
    WmlToc toc,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> current,
    List<LaidOutBox> currentFrames,
    int pageIndex,
    double y,
    int paragraphIndex, {
    _Flow? flow,
    double? originX,
    double? maxWidthOverride,
    bool allowBreak = true,
  }) {
    var cursorY = y;
    var idx = pageIndex;
    var para = paragraphIndex;
    final source = toc.sourcePresentation;
    if (source == null || source.paragraphs.any((p) => p.title)) {
      final title = _layoutParagraph(
        toc.titleParagraph,
        section,
        pages,
        current,
        currentFrames,
        idx,
        cursorY,
        para,
        sourceText: toc.titleParagraph.text,
        originX: originX ?? flow?.originX,
        maxWidthOverride: maxWidthOverride ?? flow?.colWidth,
        flow: flow,
        allowBreak: allowBreak,
      );
      cursorY = title.y;
      idx = title.pageIndex;
    }
    para++;
    final int itemCount = toc.itemParagraphs.length;
    for (int i = 0; i < itemCount; i++) {
      final WmlParagraph item = toc.itemParagraphs[i];
      final WmlTocEntry? entry = i < toc.entries.length ? toc.entries[i] : null;
      final target = entry?.headingParagraphIndex ?? -1;
      final int lineStart = current.length;
      final ({double y, int pageIndex}) laid = _layoutParagraph(
        item,
        section,
        pages,
        current,
        currentFrames,
        idx,
        cursorY,
        para,
        sourceText: item.text,
        originX: originX ?? flow?.originX,
        maxWidthOverride: maxWidthOverride ?? flow?.colWidth,
        flow: flow,
        allowBreak: allowBreak,
        tocTargetParagraph: target >= 0 ? target : null,
        overlayText: entry != null && toc.showsPageNumberForLevel(entry.level)
            ? '${entry.pageNumber}'
            : null,
        tocLeader: entry != null && toc.showsPageNumberForLevel(entry.level),
      );
      cursorY = laid.y;
      idx = laid.pageIndex;
      para++;
      final List<LaidOutLine> entryLines = lineStart <= current.length
          ? current.sublist(lineStart)
          : List<LaidOutLine>.from(current);
      if (entryLines.isNotEmpty && target >= 0) {
        final LaidOutLine first = entryLines.first;
        final LaidOutLine last = entryLines.last;
        currentFrames.add(
          LaidOutBox(
            x: first.boxX,
            y: first.y,
            width: first.boxWidth,
            height: (last.y + last.height) - first.y,
            strokeColor: '00000000',
            kind: LaidOutBoxKind.tocEntry,
            paragraphIndex: target,
          ),
        );
      }
    }
    return (y: cursorY + 8, pageIndex: idx);
  }

  ({double y, int pageIndex}) _layoutTable(
    WmlTable table,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> current,
    List<LaidOutBox> currentFrames,
    int pageIndex,
    double y,
    int paragraphIndex, {
    double? originX,
    double? maxWidthOverride,
    _Flow? flow,
    bool allowBreak = true,
  }) {
    final cellMargin = table.properties.cellMargin;
    if (!cellMargin.isFinite || cellMargin < 0) {
      throw ArgumentError.value(
        cellMargin,
        'cellMargin',
        'Table cell margins must be finite and nonnegative.',
      );
    }
    final insets = table.properties.cellInsets;
    final previousInsets = _containedVerticalInsets;
    final nestedInsets = previousInsets + insets.vertical;
    if (!nestedInsets.isFinite) {
      throw ArgumentError.value(
        cellMargin,
        'cellMargin',
        'The combined table cell margins are not representable.',
      );
    }
    _containedVerticalInsets = nestedInsets;
    _containedTableDepth++;
    try {
      return _layoutTableContents(
        table,
        section,
        pages,
        current,
        currentFrames,
        pageIndex,
        y,
        paragraphIndex,
        originX: originX,
        maxWidthOverride: maxWidthOverride,
        insets: insets,
        flow: flow,
        allowBreak: allowBreak,
      );
    } finally {
      _containedTableDepth--;
      _containedVerticalInsets = previousInsets;
    }
  }

  ({double y, int pageIndex}) _layoutTableContents(
    WmlTable table,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> current,
    List<LaidOutBox> currentFrames,
    int pageIndex,
    double y,
    int paragraphIndex, {
    double? originX,
    double? maxWidthOverride,
    required WmlTableCellInsets insets,
    _Flow? flow,
    bool allowBreak = true,
  }) {
    final firstPage = pages.length;
    final firstFrame = currentFrames.length;
    final List<double> cols = _columnWidths(table, section, maxWidthOverride);
    // Word tables occupy their row boxes in the surrounding story flow.
    // Keep the editor's spacing for tables authored without a DOCX source.
    final imported = table.properties.sourcePropertiesXml != null;
    var cursorY = y + (imported ? 0 : 6);
    var idx = pageIndex;
    var para = paragraphIndex;
    final double tableX = originX ?? section.margins.left;
    final double tableWidth = cols.fold<double>(
      0,
      (double sum, double width) => sum + width,
    );
    if (!tableWidth.isFinite ||
        tableWidth <= 0 ||
        cols.any((width) => !width.isFinite || width <= 0)) {
      throw ArgumentError.value(
        cols,
        'table.grid',
        'Laid-out table columns must have finite positive widths.',
      );
    }
    final bool rtl = table.properties.rightToLeft;

    for (final WmlTableRow row in table.rows) {
      final int rowIndex = table.rows.indexOf(row);
      final rowBlocks = [
        for (final cell in row.cells)
          WordTree.visibleBlocks(cell.blocks).toList(),
      ];
      final cellParagraphStarts = <int>[];
      final blockParagraphOffsets = <List<int>>[];
      var rowParagraphEnd = para;
      for (final blocks in rowBlocks) {
        cellParagraphStarts.add(rowParagraphEnd);
        final offsets = <int>[0];
        for (final block in blocks) {
          final count = WordTree.paragraphs([block]).length;
          rowParagraphEnd += count;
          offsets.add(offsets.last + count);
        }
        blockParagraphOffsets.add(offsets);
      }
      final double fullRowHeight = _measureTableRowHeightFrom(
        row,
        cols,
        section,
        nextBlock: List<int>.filled(row.cells.length, 0),
        insets: insets,
      );
      final exactHeight = row.exactHeight;
      final canSplitRow = !row.cantSplit && exactHeight == null;
      if (allowBreak &&
          exactHeight == null &&
          fullRowHeight > section.contentHeight - insets.vertical) {
        final laid = _layoutTallTableRow(
          this,
          table,
          rowIndex,
          cols,
          section,
          pages,
          current,
          currentFrames,
          idx,
          cursorY,
          para,
          tableX,
          tableWidth,
          flow?.sectionIndex ?? 0,
        );
        cursorY = laid.y;
        idx = laid.pageIndex;
        para = rowParagraphEnd;
        continue;
      }
      final List<int> nextBlock = List<int>.filled(row.cells.length, 0);
      var sliceStart = true;
      while (true) {
        var remaining = false;
        for (int c = 0; c < row.cells.length; c++) {
          if (nextBlock[c] < rowBlocks[c].length) {
            remaining = true;
            break;
          }
        }
        if (!remaining && !sliceStart) {
          break;
        }

        final Set<int> rowNotes = <int>{
          for (final WmlTableCell cell in row.cells)
            for (final WmlBlock block in cell.blocks)
              for (final WmlParagraph p in WmlClone.paragraphsOf(block))
                for (final WmlRun run in p.inlines.whereType<WmlRun>())
                  if (run.noteRefId != null && !run.noteRefEndnote)
                    run.noteRefId!,
        };
        if (allowBreak && _minimumNotes(rowNotes, section, idx) > 0) {
          final double rowHeight = _measureTableRowHeightFrom(
            row,
            cols,
            section,
            nextBlock: nextBlock,
            insets: insets,
          );
          while (cursorY + rowHeight + _minimumNotes(rowNotes, section, idx) >
                  _bodyBottom(section, idx) &&
              (current.isNotEmpty ||
                  currentFrames.isNotEmpty ||
                  _noteReserve(idx) > 0)) {
            pages.add(
              _makePage(
                section,
                idx,
                current,
                currentFrames,
                sectionIndex: flow?.sectionIndex ?? 0,
                firstInSection: false,
              ),
            );
            current.clear();
            currentFrames.clear();
            idx++;
            cursorY = _tablePageTop(section);
          }
          final double minimum = _minimumNotes(rowNotes, section, idx);
          _reserveNotes(
            rowNotes,
            section,
            idx,
            math.min(
              cursorY + rowHeight,
              section.pageSize.height - section.margins.bottom - minimum,
            ),
          );
        }
        var pageBottom = _bodyBottom(section, idx);

        // If the cursor is already past the usable area, advance the page
        // before opening a new row slice.
        while (allowBreak &&
            (current.isNotEmpty ||
                currentFrames.isNotEmpty ||
                _noteReserve(idx) > 0) &&
            cursorY + (exactHeight ?? insets.top + 12) > pageBottom) {
          pages.add(
            _makePage(
              section,
              idx,
              current,
              currentFrames,
              sectionIndex: pages.isEmpty ? 0 : pages.last.sectionIndex,
              firstInSection: false,
            ),
          );
          current.clear();
          currentFrames.clear();
          idx++;
          cursorY = _tablePageTop(section);
          pageBottom = _bodyBottom(section, idx);
        }

        // When cantSplit is set, move the whole remaining row to the next
        // page if it will not fit. Otherwise start placing cells and allow
        // mid-row continuation (Word default for Table Grid).
        if (allowBreak &&
            sliceStart &&
            !canSplitRow &&
            (current.isNotEmpty || currentFrames.isNotEmpty)) {
          final double estimated = _measureTableRowHeightFrom(
            row,
            cols,
            section,
            nextBlock: nextBlock,
            insets: insets,
          );
          if (cursorY + estimated > pageBottom) {
            pages.add(
              _makePage(
                section,
                idx,
                current,
                currentFrames,
                sectionIndex: pages.isEmpty ? 0 : pages.last.sectionIndex,
                firstInSection: false,
              ),
            );
            current.clear();
            currentFrames.clear();
            idx++;
            cursorY = _tablePageTop(section);
            pageBottom = _bodyBottom(section, idx);
          }
        }

        final double rowStartY = cursorY;
        var rowBottom = rowStartY;
        var x = rtl ? tableX + tableWidth : tableX;
        var gridCol = 0;
        final int rowFrameStart = currentFrames.length;
        final List<LaidOutBox> rowFrames = <LaidOutBox>[];
        var needsContinue = false;
        final capture = identical(table, _captureTallCells?.table)
            ? _captureTallCells
            : null;

        for (int c = 0; c < row.cells.length; c++) {
          final lineStart = capture == null ? 0 : current.length;
          final frameStart = capture == null ? 0 : currentFrames.length;
          final anchorStart = capture == null
              ? 0
              : _deferredContainedFrames!.length;
          final visualStart = capture == null
              ? 0
              : _deferredContainedVisuals!.length;
          final WmlTableCell cell = row.cells[c];
          final int span = WordTable.spanOf(cell);
          var colW = 0.0;
          for (int k = 0; k < span; k++) {
            colW += cols[(gridCol + k).clamp(0, cols.length - 1)];
          }
          final contentWidth = _tableCellContentWidth(colW, insets.horizontal);
          if (rtl) {
            x -= colW;
          }
          final int cellParaStart = cellParagraphStarts[c];
          final int cellParagraphCount = blockParagraphOffsets[c].last;
          var cellPara = cellParaStart + blockParagraphOffsets[c][nextBlock[c]];
          var cellY = rowStartY + insets.top;
          final firstBlock = nextBlock[c];
          final blocks = rowBlocks[c];
          var bi = firstBlock;
          while (bi < blocks.length) {
            final WmlBlock block = blocks[bi];
            final blockY = bi == firstBlock
                ? cellY
                : cellY - _cellParagraphOverlap(blocks[bi - 1], block);
            final double blockH = _estimateCellBlockHeight(
              block,
              section,
              maxWidth: contentWidth,
            );
            if (allowBreak &&
                canSplitRow &&
                blockY + blockH > pageBottom &&
                cellY > rowStartY + insets.top + 0.5) {
              needsContinue = true;
              break;
            }
            // Word-like orphan control for consecutive list items: if this
            // block fits but the next list sibling does not, break before
            // this block so the pair moves together (e.g. UN OCHA + CEPs).
            if (allowBreak &&
                canSplitRow &&
                bi + 1 < blocks.length &&
                cellY > rowStartY + insets.top + 0.5 &&
                blockY + blockH <= pageBottom) {
              final WmlBlock nextBlock = blocks[bi + 1];
              if (_listOrphanPair(block, nextBlock)) {
                final double nextH = _estimateCellBlockHeight(
                  nextBlock,
                  section,
                  maxWidth: contentWidth,
                );
                if (blockY +
                        blockH +
                        nextH -
                        _cellParagraphOverlap(block, nextBlock) >
                    pageBottom) {
                  needsContinue = true;
                  break;
                }
              }
            }
            final laid = _layoutContainedBlock(
              this,
              block,
              section,
              pages,
              current,
              currentFrames,
              idx,
              blockY,
              cellPara,
              originX: x + insets.left,
              maxWidth: contentWidth,
            );
            cellY = laid.y;
            cellPara = laid.nextParagraphIndex;
            bi++;
          }
          nextBlock[c] = bi;
          rowBottom = math.max(rowBottom, cellY + insets.bottom);
          if (capture != null) {
            capture.cells.add(
              _TallCellContent(
                current.sublist(lineStart),
                currentFrames.sublist(frameStart),
                _deferredContainedFrames!.entries.skip(anchorStart).toList(),
                _deferredContainedVisuals!.entries.skip(visualStart).toList(),
                cellY + insets.bottom,
              ),
            );
          }
          final bool firstSlice = sliceStart;
          final bool lastSlice = bi >= rowBlocks[c].length;
          // Empty cells still have visible borders. Their absent paragraph
          // span must not claim the next sibling's text identity.
          {
            rowFrames.add(
              LaidOutBox(
                x: x,
                y: rowStartY,
                width: colW,
                height: 0,
                fillColor: cell.vMerge == WmlVMerge.cont
                    ? null
                    : cell.fillColor,
                strokeColor: cell.vMerge == WmlVMerge.cont
                    ? '00000000'
                    : (table.properties.borderColor ?? '000000'),
                strokeWidth: table.properties.borderWidth,
                strokeTop: _cellEdge(
                  cell.borderTop,
                  inherit: table.properties.borders && firstSlice,
                ),
                strokeBottom: _cellEdge(
                  cell.borderBottom,
                  inherit: table.properties.borders && lastSlice,
                ),
                strokeLeft: _cellEdge(
                  cell.borderLeft,
                  inherit: table.properties.borders,
                ),
                strokeRight: _cellEdge(
                  cell.borderRight,
                  inherit: table.properties.borders,
                ),
                paragraphIndex: cellParagraphCount == 0 ? null : cellParaStart,
                paragraphEnd: cellParagraphCount == 0
                    ? null
                    : cellParaStart + cellParagraphCount - 1,
                table: table,
                tableRow: rowIndex,
                tableCol: c,
                tableGridCol: gridCol,
              ),
            );
          }
          if (!rtl) {
            x += colW;
          }
          gridCol += span;
        }

        final double minH = sliceStart ? (row.height ?? 0) : 0;
        final double height =
            exactHeight ?? math.max(minH, rowBottom - rowStartY);
        for (final LaidOutBox frame in rowFrames) {
          frame.height = height;
          // Close the bottom edge of a mid-row split on both columns so the
          // page break matches Word's continuous table grid.
          if (needsContinue && frame.strokeBottom == false) {
            final WmlTableCell? cell =
                frame.tableCol != null && frame.tableCol! < row.cells.length
                ? row.cells[frame.tableCol!]
                : null;
            if (cell?.borderBottom != false) {
              frame.strokeBottom = table.properties.borders;
            }
          }
        }
        // Parent backgrounds precede rich descendants in painter order.
        currentFrames.insertAll(rowFrameStart, rowFrames);
        cursorY = rowStartY + height;
        sliceStart = false;

        if (allowBreak && needsContinue) {
          pages.add(
            _makePage(
              section,
              idx,
              current,
              currentFrames,
              sectionIndex: pages.isEmpty ? 0 : pages.last.sectionIndex,
              firstInSection: false,
            ),
          );
          current.clear();
          currentFrames.clear();
          idx++;
          cursorY = _tablePageTop(section);
          pageBottom = _bodyBottom(section, idx);
        }
      }
      para = rowParagraphEnd;
    }
    // Pages copy the frame list, retaining the boxes. Normalize each physical
    // page separately after all rows (including tall-row slices) have their
    // original table identity. A later page may contain only continuations.
    _applyVerticalMerges(table, [
      for (var page = firstPage; page < pages.length; page++)
        pages[page].frames.skip(page == firstPage ? firstFrame : 0),
      currentFrames.skip(pages.length == firstPage ? firstFrame : 0),
    ]);
    return (y: cursorY + (imported ? 0 : 4), pageIndex: idx);
  }

  static bool _cellEdge(bool? explicit, {required bool inherit}) {
    if (explicit != null) {
      return explicit;
    }
    return inherit;
  }

  /// True when [a] and [b] are consecutive list paragraphs that should not
  /// be separated by a page break at the bottom of a cell.
  static bool _listOrphanPair(WmlBlock a, WmlBlock b) {
    if (a is! WmlParagraph || b is! WmlParagraph) {
      return false;
    }
    final String? la = a.properties.listLabel;
    final String? lb = b.properties.listLabel;
    if (la == null || lb == null) {
      return false;
    }
    if (a.properties.numId == null ||
        b.properties.numId == null ||
        a.properties.numId != b.properties.numId) {
      return false;
    }
    return a.properties.ilvl == b.properties.ilvl;
  }

  static _AdjacentWordParagraph _afterParagraph(WmlParagraphProps properties) =>
      (
        after: properties.spacingAfter,
        styleId: properties.layoutStyleId,
        contextualSpacing: properties.contextualSpacing,
      );

  static double _paragraphGapOverlap(
    _AdjacentWordParagraph previous,
    WmlParagraphProps next,
  ) {
    final after = math.max(0.0, previous.after);
    final before = math.max(0.0, next.spacingBefore);
    if (previous.styleId != next.layoutStyleId ||
        (!previous.contextualSpacing && !next.contextualSpacing)) {
      return math.min(after, before);
    }
    // Word ignores an opted-in before-space when combining the gaps, then
    // subtracts an opted-in after-space from the result.
    final combined = math.max(after, next.contextualSpacing ? 0.0 : before);
    final gap = combined - (previous.contextualSpacing ? after : 0.0);
    return after + before - gap;
  }

  static double _cellParagraphOverlap(WmlBlock previous, WmlBlock next) =>
      previous is WmlParagraph && next is WmlParagraph
      ? _paragraphGapOverlap(
          _afterParagraph(previous.properties),
          next.properties,
        )
      : 0;

  double _estimateCellBlockHeight(
    WmlBlock block,
    WmlSection section, {
    required double maxWidth,
  }) {
    _containedMeasureDepth++;
    try {
      return _layoutContainedBlock(
        this,
        block,
        section,
        <LaidOutPage>[],
        <LaidOutLine>[],
        <LaidOutBox>[],
        0,
        0,
        0,
        originX: 0,
        maxWidth: maxWidth,
      ).y;
    } finally {
      _containedMeasureDepth--;
    }
  }

  double _measureTableRowHeightFrom(
    WmlTableRow row,
    List<double> cols,
    WmlSection section, {
    required List<int> nextBlock,
    required WmlTableCellInsets insets,
  }) {
    if (row.exactHeight case final height?) return height;
    var rowBottom = 0.0;
    var gridCol = 0;
    for (int c = 0; c < row.cells.length; c++) {
      final WmlTableCell cell = row.cells[c];
      final int span = WordTable.spanOf(cell);
      var colW = 0.0;
      for (int k = 0; k < span; k++) {
        colW += cols[(gridCol + k).clamp(0, cols.length - 1)];
      }
      final contentWidth = _tableCellContentWidth(colW, insets.horizontal);
      var cellY = insets.top;
      final blocks = WordTree.visibleBlocks(cell.blocks).toList();
      for (int bi = nextBlock[c]; bi < blocks.length; bi++) {
        final block = blocks[bi];
        if (bi > nextBlock[c]) {
          cellY -= _cellParagraphOverlap(blocks[bi - 1], block);
        }
        cellY += _estimateCellBlockHeight(
          block,
          section,
          maxWidth: contentWidth,
        );
      }
      rowBottom = math.max(rowBottom, cellY + insets.bottom);
      gridCol += span;
    }
    return math.max(row.height ?? 0, rowBottom);
  }

  static double _tableCellContentWidth(double width, double margin) {
    final innerWidth = width - margin;
    if (!innerWidth.isFinite || innerWidth <= 0) {
      throw ArgumentError.value(
        margin,
        'cellMargin',
        'Table cell margins must leave a finite positive content width.',
      );
    }
    return innerWidth;
  }

  List<LaidOutBox> _chromeVisualFrames(
    WmlSection section,
    int pageNumber, {
    required bool firstInSection,
    required bool isFooter,
  }) {
    final List<WmlVisual> visuals = isFooter
        ? section.footerVisualsForPage(
            pageNumber,
            firstInSection: firstInSection,
          )
        : section.headerVisualsForPage(
            pageNumber,
            firstInSection: firstInSection,
          );
    final List<WmlParagraph> story = isFooter
        ? section.footerForPage(pageNumber, firstInSection: firstInSection)
        : section.headerForPage(pageNumber, firstInSection: firstInSection);
    final List<WmlVisual> inlineVisuals = <WmlVisual>[
      for (final WmlParagraph paragraph in story)
        for (final WmlRun run in paragraph.inlines.whereType<WmlRun>())
          if (run.inlineVisual != null) run.inlineVisual!,
    ];
    if (visuals.isEmpty && inlineVisuals.isEmpty) {
      return const <LaidOutBox>[];
    }
    final double bandTop = isFooter
        ? section.pageSize.height -
              math.max(section.margins.footer, section.margins.bottom * 0.55)
        : section.margins.header;
    final List<LaidOutBox> frames = <LaidOutBox>[];
    final listed = Set<WmlVisual>.identity()..addAll(visuals);
    final placed = Set<WmlVisual>.identity();
    var x = section.margins.left;
    // Header/footer tables are flattened to their paragraphs by the source
    // model. Keep their inline pictures (typically the organisation logo)
    // instead of painting U+FFFC as a row of missing-glyph boxes.
    var inlineX = section.margins.left;
    for (final WmlVisual item in inlineVisuals) {
      final OfficeVisual visual = item.visual;
      if (listed.contains(item) || !placed.add(item)) {
        // One node may be exposed through both representations; its list
        // placement owns that occurrence. Distinct nodes can share an asset.
        continue;
      }
      final double width = visual.width.clamp(16, section.contentWidth);
      final double height = visual.height.clamp(12, 120);
      frames.add(
        LaidOutBox(
          x: inlineX,
          y: bandTop,
          width: width,
          height: height,
          fillColor: null,
          strokeColor: '00000000',
          kind: LaidOutBoxKind.picture,
          visual: visual,
          strokeTop: false,
          strokeRight: false,
          strokeBottom: false,
          strokeLeft: false,
        ),
      );
      inlineX += width + 8;
    }
    for (final WmlVisual item in visuals) {
      // Repeated references to one node are one occurrence. Equal content or
      // coordinates do not identify distinct authored nodes, even with alpha.
      if (!placed.add(item)) continue;
      final OfficeVisual visual = item.visual;
      final double width = visual.width.clamp(16, section.pageSize.width);
      final double height = visual.height.clamp(12, 120);
      final double vx = visual.offsetX != 0
          ? visual.offsetX.clamp(0, section.pageSize.width - width)
          : x;
      final double vy = visual.offsetY != 0
          ? (isFooter
                ? section.pageSize.height -
                      section.margins.bottom +
                      visual.offsetY
                : visual.offsetY)
          : bandTop;
      frames.add(
        LaidOutBox(
          x: vx,
          y: vy,
          width: width,
          height: height,
          fillColor: null,
          strokeColor: '00000000',
          kind: LaidOutBoxKind.picture,
          visual: visual,
          strokeTop: false,
          strokeRight: false,
          strokeBottom: false,
          strokeLeft: false,
        ),
      );
      x = vx + width + 8;
    }
    return frames;
  }

  void _applyVerticalMerges(
    WmlTable table,
    List<Iterable<LaidOutBox>> pageFrames,
  ) {
    // Resolve chains once by exact logical start and span. An orphan, shifted
    // continuation or mismatched native span cannot consume a neighboring cell.
    final origins =
        <(int, int), ({int row, int col, int grid, WmlTableCell cell})>{};
    var above = <int, ({int row, int col, int grid, WmlTableCell cell})>{};
    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      // Omitted grid positions are not yet placed by the table renderer.
      // Do not infer a merge owner at a different physical x coordinate.
      if (row.gridBefore != 0 ||
          row.gridAfter != 0 ||
          row.cells.any((cell) => cell.gridSpan < 1)) {
        above = {};
        continue;
      }
      final current =
          <int, ({int row, int col, int grid, WmlTableCell cell})>{};
      var grid = 0;
      for (var c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        ({int row, int col, int grid, WmlTableCell cell})? origin;
        if (cell.gridSpan > 0 && cell.vMerge == WmlVMerge.restart) {
          origin = (row: r, col: c, grid: grid, cell: cell);
        } else if (cell.gridSpan > 0 && cell.vMerge == WmlVMerge.cont) {
          final previous = above[grid];
          if (previous != null && previous.cell.gridSpan == cell.gridSpan) {
            origin = previous;
          }
        }
        if (origin != null) {
          origins[(r, c)] = origin;
          current[grid] = origin;
        }
        grid += WordTable.spanOf(cell);
      }
      above = current;
    }
    if (origins.isEmpty) return;

    final pages = [
      for (final frames in pageFrames)
        [
          for (final box in frames)
            if (identical(box.table, table) &&
                box.kind == LaidOutBoxKind.tableCell &&
                box.height > 0)
              box,
        ],
    ];
    final masters = <WmlTableCell, LaidOutBox>{};
    final firstSlices = <(int, int), LaidOutBox>{};
    final lastSlices = <(int, int), LaidOutBox>{};
    for (final frames in pages) {
      for (final box in frames) {
        final origin = origins[(box.tableRow, box.tableCol)];
        if (origin != null) {
          final position = (box.tableRow!, box.tableCol!);
          firstSlices.putIfAbsent(position, () => box);
          lastSlices[position] = box;
        }
        if (origin != null &&
            box.tableRow == origin.row &&
            box.tableCol == origin.col) {
          masters.putIfAbsent(origin.cell, () => box);
        }
      }
    }
    for (final frames in pages) {
      final groups = <WmlTableCell, List<LaidOutBox>>{};
      for (final box in frames) {
        final origin = origins[(box.tableRow, box.tableCol)];
        if (origin != null && masters.containsKey(origin.cell)) {
          groups.putIfAbsent(origin.cell, () => []).add(box);
        }
      }
      for (final entry in groups.entries) {
        final fragments = entry.value;
        for (final fragment in fragments) {
          fragment.tableRowGeometry ??= (
            row: fragment.tableRow!,
            y: fragment.y,
            height: fragment.height,
          );
        }
        final first = fragments.first;
        final last = fragments.last;
        final origin = origins[(first.tableRow, first.tableCol)]!;
        final master = masters[entry.key]!;
        final bottom = fragments
            .map((box) => box.y + box.height)
            .reduce(math.max);
        // Border style and physical slicing are separate. A continuation may
        // inherit a different style from its master, while a tall cell's
        // interior page cuts must remain open even with explicit true borders.
        final firstSlice = identical(
          firstSlices[(first.tableRow, first.tableCol)],
          first,
        );
        final lastSlice = identical(
          lastSlices[(last.tableRow, last.tableCol)],
          last,
        );
        first
          ..height = bottom - first.y
          ..fillColor = origin.cell.fillColor
          ..strokeColor = table.properties.borderColor ?? '000000'
          ..strokeWidth = table.properties.borderWidth
          ..strokeTop =
              firstSlice &&
              _cellEdge(
                origin.cell.borderTop,
                inherit: table.properties.borders,
              )
          ..strokeBottom =
              lastSlice &&
              _cellEdge(
                origin.cell.borderBottom,
                inherit: table.properties.borders,
              )
          ..strokeLeft = _cellEdge(
            origin.cell.borderLeft,
            inherit: table.properties.borders,
          )
          ..strokeRight = _cellEdge(
            origin.cell.borderRight,
            inherit: table.properties.borders,
          )
          ..tableRow = origin.row
          ..tableCol = origin.col
          ..tableGridCol = origin.grid
          ..paragraphIndex = master.paragraphIndex
          ..paragraphEnd = master.paragraphEnd;
        for (final continuation in fragments.skip(1)) {
          // Retain physical row geometry metadata for table handles, but a
          // hidden continuation must never claim editable paragraph ownership.
          continuation
            ..height = 0
            ..fillColor = null
            ..strokeColor = '00000000'
            ..paragraphIndex = null
            ..paragraphEnd = null;
        }
      }
    }
  }

  int _layoutFrame(
    WmlFrame frame,
    WmlSection section,
    _Flow flow,
    int paragraphIndex,
  ) => _layoutFrameContents(
    frame,
    section,
    flow.pages,
    flow.current,
    flow.currentFrames,
    flow.pageIndex,
    paragraphIndex,
  );

  int _layoutFrameContents(
    WmlFrame frame,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> lines,
    List<LaidOutBox> frames,
    int pageIndex,
    int paragraphIndex,
  ) {
    final double x = frame.pageX(section);
    final double y = frame.pageY(section);
    frames.add(
      LaidOutBox(
        x: x,
        y: y,
        width: frame.width,
        height: frame.height,
        fillColor: frame.fillColor,
        strokeColor: frame.strokeColor ?? '00000000',
        kind: LaidOutBoxKind.frame,
        frame: frame,
      ),
    );
    var cursorY = y + frame.insetTop;
    var para = paragraphIndex;
    final double innerX = x + frame.insetLeft;
    final double innerW = math.max(
      1,
      frame.width - frame.insetLeft - frame.insetRight,
    );
    for (final block in WordTree.visibleBlocks(frame.blocks)) {
      final laid = _layoutContainedBlock(
        this,
        block,
        section,
        pages,
        lines,
        frames,
        pageIndex,
        cursorY,
        para,
        originX: innerX,
        maxWidth: innerW,
      );
      cursorY = laid.y;
      para = laid.nextParagraphIndex;
    }
    return para;
  }

  ({double y, int pageIndex}) _layoutVisual(
    OfficeVisual visual,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> current,
    List<LaidOutBox> currentFrames,
    int pageIndex,
    double y, {
    double? originX,
    double? maxWidthOverride,
    double? maxHeightOverride,
    _Flow? flow,
    bool allowBreak = true,
  }) {
    final double maxW = maxWidthOverride ?? section.contentWidth;
    final bool absolute =
        visual.picture.wrap == PictureWrap.behind ||
        visual.picture.wrap == PictureWrap.inFront;
    final double widthLimit = absolute ? section.pageSize.width : maxW;
    final double width = visual.width.clamp(
      math.min(24, widthLimit),
      widthLimit,
    );
    final double heightLimit = absolute
        ? section.pageSize.height
        : maxHeightOverride ?? section.contentHeight;
    final double height = visual.height.clamp(
      math.min(24, heightLimit),
      heightLimit,
    );
    if (absolute) {
      currentFrames.add(
        _visualBox(visual, visual.offsetX, visual.offsetY, width, height),
      );
      return (y: y, pageIndex: pageIndex);
    }
    final bool atTop = allowBreak && (y - section.margins.top).abs() < 0.5;
    var cursorY = atTop ? y : y + 8 + visual.offsetY;
    var idx = pageIndex;
    var x0 = (originX ?? section.margins.left) + visual.offsetX;
    while (allowBreak &&
        cursorY + height > _bodyBottom(section, idx) &&
        (current.isNotEmpty ||
            currentFrames.isNotEmpty ||
            _noteReserve(idx) > 0)) {
      if (flow != null) {
        flow.y = cursorY;
        flow.nextColumn();
        cursorY = flow.y;
        idx = flow.pageIndex;
        x0 = flow.originX + visual.offsetX;
      } else {
        pages.add(
          _makePage(
            section,
            idx,
            current,
            currentFrames,
            sectionIndex: pages.isEmpty ? 0 : pages.last.sectionIndex,
            firstInSection: false,
          ),
        );
        current.clear();
        currentFrames.clear();
        idx++;
        cursorY = section.margins.top;
      }
    }
    currentFrames.add(_visualBox(visual, x0, cursorY, width, height));
    return (y: cursorY + height + 10, pageIndex: idx);
  }

  LaidOutBox _visualBox(
    OfficeVisual visual,
    double x,
    double y,
    double width,
    double height,
  ) {
    return LaidOutBox(
      x: x,
      y: y,
      width: width,
      height: height,
      fillColor: 'FFFFFF',
      strokeColor: '8FAADC',
      kind: visual.isDiagram
          ? LaidOutBoxKind.diagram
          : visual.kind == OfficeVisualKind.picture
          ? LaidOutBoxKind.picture
          : LaidOutBoxKind.chart,
      visual: visual,
    );
  }

  ({double y, int pageIndex}) _layoutEquation(
    WmlEquation equation,
    WmlSection section,
    List<LaidOutPage> pages,
    List<LaidOutLine> current,
    List<LaidOutBox> currentFrames,
    int pageIndex,
    double y,
  ) {
    final LaidOutOmml omml = OmmlLayout.layout(equation.math, fontSize: 16);
    final double width = math.min(
      section.contentWidth,
      math.max(72, omml.width),
    );
    final double height = math.max(28, omml.height);
    var cursorY = y + 8;
    var idx = pageIndex;
    while (cursorY + height > _bodyBottom(section, idx) &&
        (current.isNotEmpty ||
            currentFrames.isNotEmpty ||
            _noteReserve(idx) > 0)) {
      pages.add(
        _makePage(
          section,
          idx,
          current,
          currentFrames,
          sectionIndex: pages.isEmpty ? 0 : pages.last.sectionIndex,
          firstInSection: false,
        ),
      );
      current.clear();
      currentFrames.clear();
      idx++;
      cursorY = section.margins.top;
    }
    final double x = equation.math.display == OmmlDisplay.display
        ? section.margins.left + (section.contentWidth - width) / 2
        : section.margins.left;
    currentFrames.add(
      LaidOutBox(
        x: x,
        y: cursorY,
        width: width,
        height: height,
        fillColor: 'F7FBFF',
        strokeColor: '8FAADC',
        kind: LaidOutBoxKind.equation,
        equation: equation,
        omml: omml,
      ),
    );
    return (y: cursorY + height + 10, pageIndex: idx);
  }

  static double _lineHeight(
    WmlParagraphProps props,
    FontMetrics? metrics,
    double fontSize,
  ) {
    // Use the face's typographic line spacing, not its clipping extents plus
    // a global multiplier. WinAscent/Descent can include rare glyphs well
    // outside a normal line (notably Aptos), and a 10% margin accumulates
    // enough drift to change page breaks. Preserve the historical estimate
    // only when no real face is available; it is not native-qualified.
    final double single = metrics == null
        ? fontSize * 1.32
        : metrics.typographicLineHeight;
    switch (props.lineSpacingRule) {
      case WmlLineSpacingRule.exact:
        return props.lineSpacing;
      case WmlLineSpacingRule.atLeast:
        return single > props.lineSpacing ? single : props.lineSpacing;
      case WmlLineSpacingRule.auto:
        return single * props.lineSpacing;
    }
  }

  LaidOutPage _makePage(
    WmlSection section,
    int index,
    List<LaidOutLine> lines,
    List<LaidOutBox> frames, {
    required int sectionIndex,
    required bool firstInSection,
  }) {
    final List<LaidOutLine> headerLines = _chromeLines(
      section,
      index + 1,
      section.headerForPage(index + 1, firstInSection: firstInSection),
      isFooter: false,
    );
    final List<LaidOutLine> footerLines = _chromeLines(
      section,
      index + 1,
      section.footerForPage(index + 1, firstInSection: firstInSection),
      isFooter: true,
    );
    final double headerH = _chromeBandHeight(
      lines: headerLines,
      fallback: math.max(section.margins.header, section.margins.top),
      pageHeight: section.pageSize.height,
      footer: false,
    );
    final double footerH = _chromeBandHeight(
      lines: footerLines,
      fallback: math.max(section.margins.footer, section.margins.bottom),
      pageHeight: section.pageSize.height,
      footer: true,
    );
    final LaidOutPage page = LaidOutPage(
      index: index,
      sectionIndex: sectionIndex,
      width: section.pageSize.width,
      height: section.pageSize.height,
      lines: List<LaidOutLine>.from(lines),
      frames: <LaidOutBox>[
        ...frames,
        ..._chromeVisualFrames(
          section,
          index + 1,
          firstInSection: firstInSection,
          isFooter: false,
        ),
        ..._chromeVisualFrames(
          section,
          index + 1,
          firstInSection: firstInSection,
          isFooter: true,
        ),
      ],
      header: headerLines,
      footer: footerLines,
      headerBand: LaidOutBand(
        left: 0,
        top: 0,
        width: section.pageSize.width,
        height: headerH,
      ),
      footerBand: LaidOutBand(
        left: 0,
        top: section.pageSize.height - footerH,
        width: section.pageSize.width,
        height: footerH,
      ),
    );
    page._origin = _PageOrigin(
      section,
      sectionIndex,
      firstInSection,
      frames.length,
    );
    _attachNotes(page, section);
    _attachLineNumbers(page, section);
    return page;
  }

  void _padSectionBreak(
    WmlSection section,
    List<LaidOutPage> pages,
    int sectionIndex,
  ) {
    if (sectionIndex == 0) {
      return;
    }
    switch (section.breakKind) {
      case WmlSectionBreakKind.continuous:
        return;
      case WmlSectionBreakKind.oddPage:
        while ((pages.length + 1).isEven) {
          pages.add(
            _makePage(
              section,
              pages.length,
              <LaidOutLine>[],
              <LaidOutBox>[],
              sectionIndex: sectionIndex,
              firstInSection: pages.every(
                (LaidOutPage p) => p.sectionIndex != sectionIndex,
              ),
            ),
          );
        }
      case WmlSectionBreakKind.evenPage:
        while ((pages.length + 1).isOdd) {
          pages.add(
            _makePage(
              section,
              pages.length,
              <LaidOutLine>[],
              <LaidOutBox>[],
              sectionIndex: sectionIndex,
              firstInSection: pages.every(
                (LaidOutPage p) => p.sectionIndex != sectionIndex,
              ),
            ),
          );
        }
      case WmlSectionBreakKind.nextPage:
        return;
    }
  }

  void _attachNotes(LaidOutPage page, WmlSection section) {
    final List<_NoteSlice> slices = _noteSlices[page.index] ?? <_NoteSlice>[];
    if (slices.isEmpty) return;
    final separator = _layoutDoc?.footnoteSeparator;
    final reservationTop = _bodyBottom(section, page.index);
    var y = reservationTop + _footnoteSeparatorHeight;
    if (separator != null) {
      if (separator.visible) {
        final width = section.contentWidth * separator.relativeWidth;
        final remaining = section.contentWidth - width;
        final x =
            section.margins.left +
            switch (separator.alignment) {
              WmlFootnoteSeparatorAlignment.left => 0.0,
              WmlFootnoteSeparatorAlignment.center => remaining / 2,
              WmlFootnoteSeparatorAlignment.right => remaining,
            };
        page.frames.add(
          LaidOutBox(
            x: x,
            y: reservationTop + separator.beforeSpacing,
            width: width,
            height: separator.thickness,
            fillColor: separator.color.toRadixString(16).padLeft(6, '0'),
            // A filled rectangle is the separator itself. Stroking its
            // outline would paint outside the reserved thickness in PDF.
            strokeColor: '',
            kind: LaidOutBoxKind.footnote,
            isNoteContent: true,
          ),
        );
      }
    } else if (_layoutDoc?.sourceFootnoteSeparatorsPresent != false &&
        _layoutDoc?.sourceBlankFootnoteSeparators != true) {
      page.frames.add(
        LaidOutBox(
          x: section.margins.left,
          y: y - 4,
          width: section.contentWidth,
          height: 0.6,
          fillColor: '888888',
          strokeColor: '888888',
          kind: LaidOutBoxKind.footnote,
          isNoteContent: true,
        ),
      );
    }
    for (final _NoteSlice slice in slices) {
      slice.paintInto(page, y);
      y += slice.height;
    }
  }

  void _attachLineNumbers(LaidOutPage page, WmlSection section) {
    if (!section.lineNumbers) {
      return;
    }
    var n = 1;
    for (final LaidOutLine line in page.lines) {
      page.frames.add(
        LaidOutBox(
          x: math.max(4, section.margins.left - 18),
          y: line.y,
          width: 16,
          height: line.height,
          fillColor: '',
          strokeColor: '',
          kind: LaidOutBoxKind.lineNumber,
          paragraphIndex: n,
        ),
      );
      n++;
    }
  }

  void _appendEndnotes(WmlDocument document, List<LaidOutPage> pages) {
    // Temporary table-row documents inherit labels, but never own the outer
    // document's note stories. Only append definitions belonging to this story.
    final owned = document.endnotes.toSet();
    if (owned.isEmpty) return;
    // Numbering retains orphan definitions for repair. The visual-only path
    // must not turn those (or ambiguous duplicate IDs) into visible notes.
    final definitions = <int, WmlNote?>{};
    for (final note in document.endnotes) {
      definitions[note.id] = definitions.containsKey(note.id) ? null : note;
    }
    final referenced = <WmlNote>{};
    void collectReferences(Iterable<WmlBlock> blocks) {
      // Match WordNoteNumbering's body sequence. Frames and generated TOC
      // paragraphs are separate stories, even though document.paragraphs
      // exposes them to ordinary editing operations.
      for (final block in WordTree.visibleBlocks(blocks)) {
        if (block is WmlParagraph) {
          for (final run in block.inlines.whereType<WmlRun>()) {
            if (run.noteRefEndnote) {
              if (definitions[run.noteRefId] case final WmlNote note) {
                referenced.add(note);
              }
            }
          }
        } else if (block is WmlTable) {
          for (final row in block.rows) {
            for (final cell in row.cells) {
              collectReferences(cell.blocks);
            }
          }
        }
      }
    }

    for (final section in document.sections) {
      collectReferences(section.blocks);
    }
    final List<WmlNote> notes = <WmlNote>[
      for (final WmlNote note in _noteNumbering!.notes)
        if (owned.contains(note) &&
            (note.text.trim().isNotEmpty ||
                (referenced.contains(note) && note.visuals.isNotEmpty) ||
                note.addReference ||
                note.hasReferenceMarkers))
          note,
    ];
    if (notes.isEmpty || pages.isEmpty) {
      return;
    }
    final WmlSection section = document.sections.last;
    final LaidOutPage last = pages.last;
    var y = last.lines.isEmpty
        ? section.margins.top
        : last.lines.last.y + last.lines.last.height + 16;
    for (final LaidOutBox frame in last.frames) {
      if (!frame.isNoteContent) {
        y = math.max(y, frame.y + frame.height + 12);
      }
    }
    LaidOutPage target = pages.last;
    var bottom = section.pageSize.height - section.margins.bottom;
    for (final LaidOutBox frame in target.frames) {
      if (frame.kind == LaidOutBoxKind.footnote) {
        bottom = math.min(bottom, frame.y - 4);
      }
    }
    void ensureRoom(double height) {
      if (y + height <= bottom) {
        return;
      }
      target = _makePage(
        section,
        pages.length,
        <LaidOutLine>[],
        <LaidOutBox>[],
        sectionIndex: document.sections.length - 1,
        firstInSection: false,
      );
      pages.add(target);
      y = section.margins.top;
      bottom = section.pageSize.height - section.margins.bottom;
    }

    ensureRoom(32);
    target.notes.add(
      LaidOutLine(
        glyphs: const <LaidOutGlyph>[],
        x: section.margins.left,
        y: y,
        width: section.contentWidth,
        height: 16,
        pageIndex: target.index,
        justification: WmlJustification.left,
        overlayText: 'Endnotes',
        overlayBold: true,
        overlaySize: 12,
      ),
    );
    y += 18;
    for (final WmlNote note in notes) {
      final _NoteStory story = _story(note, section);
      var start = 0.0;
      while (start < story.height - 0.01) {
        double end = story.cut(start, bottom - y);
        if (end <= start + 0.01) {
          ensureRoom(bottom - y + 1);
          end = story.cut(start, bottom - y);
          if (end <= start + 0.01) {
            throw StateError('Endnote content taller than a page');
          }
        }
        final _NoteSlice slice = _NoteSlice(
          story,
          start,
          end,
          section,
          document.sections.length - 1,
        );
        slice.paintInto(target, y);
        y += slice.height;
        start = end;
      }
    }
  }

  List<LaidOutLine> _chromeLines(
    WmlSection section,
    int pageNumber,
    List<WmlParagraph> story, {
    required bool isFooter,
  }) {
    if (story.isEmpty) {
      return <LaidOutLine>[];
    }
    final double y = isFooter ? 0 : math.max(8, section.margins.header);
    final List<LaidOutLine> lines = <LaidOutLine>[];
    final ordinary = _WordChromeFlow();
    final frames = <_WordChromeFlow>[];
    final fieldResults = <bool>[];
    _WordChromeFlow? activeFrame;
    var unanchored = 0;
    for (int i = 0; i < story.length; i++) {
      final WmlParagraph paragraph = story[i];
      final props = paragraph.properties;
      final frame = _WordChromeFrame.read(props.sourcePropertiesXml);
      if (frame == null) {
        activeFrame = null;
      } else if (activeFrame?.frame?.key != frame.key) {
        activeFrame = _WordChromeFlow(frame: frame);
        frames.add(activeFrame);
      }
      final flow = activeFrame ?? ordinary;
      final box =
          frame?.horizontalBox(section, pageNumber) ??
          (left: section.margins.left, width: section.contentWidth);
      final WmlDocument? doc = _layoutDoc;
      final String source = paragraph.text.replaceAll('\uFFFC', ' ');
      final String raw = source.trim();
      if (isFooter || frame != null) {
        for (final boundary
            in paragraph.inlines.whereType<WmlFieldBoundary>()) {
          switch (boundary.kind) {
            case WmlFieldBoundaryKind.begin:
              fieldResults.add(false);
            case WmlFieldBoundaryKind.separate:
              if (fieldResults.isNotEmpty) fieldResults.last = true;
            case WmlFieldBoundaryKind.end:
              if (fieldResults.isNotEmpty) fieldResults.removeLast();
            case WmlFieldBoundaryKind.instruction:
              break;
          }
        }
        // A field instruction can span native paragraphs. Its code-only
        // prefix does not create an empty line in the positioned result.
        if (frame != null && raw.isEmpty && fieldResults.contains(false)) {
          continue;
        }
      }
      final WmlRunProps run =
          (frame != null && raw.isEmpty ? props.importedParagraphMark : null) ??
          WmlRunEdit.propsAt(paragraph, 0);
      final int rawStart = source.length - source.trimLeft().length;
      final String text;
      var generated = false;
      if (doc != null &&
          (paragraph.properties.pageNumberField ||
              paragraph.properties.fieldInstruction != null)) {
        final String resolved = WordFields.chromeText(
          paragraph,
          document: doc,
          pageNumber: pageNumber,
          pageCount: math.max(pageNumber, 1),
        );
        text = resolved.isEmpty ? raw : resolved;
        generated = true;
      } else if (_isStandaloneChromePageField(paragraph)) {
        text = '$pageNumber';
        generated = true;
      } else {
        text = raw;
      }
      // These overlay lines have no glyphs. Their character positions must
      // map to the untrimmed source, not to a body paragraph or a repeated
      // label elsewhere in the same header/footer. Generated labels expose
      // no authored offsets, even when their cache happens to match the text.
      final offsets = List<int?>.generate(
        text.length + 1,
        (index) => generated ? null : rawStart + index,
      );
      final size = run.fontSizePoints > 0 ? run.fontSizePoints : 11.0;
      final point = text.isEmpty ? 0x20 : text.runes.first;
      final font = _faceFor(point, run);
      final metrics =
          measureFont?.call(point, size, run) ??
          (font == null ? null : FontMetrics(font: font, fontSizePoints: size));
      final height = _lineHeight(props, metrics, size);
      final ascent = metrics?.typographicAscender ?? size * 0.8;
      final naturalHeight = metrics?.typographicLineHeight ?? size * 1.32;
      final baseline = switch (props.lineSpacingRule) {
        WmlLineSpacingRule.exact => height * 0.8,
        WmlLineSpacingRule.atLeast => ascent + height - naturalHeight,
        WmlLineSpacingRule.auto => ascent,
      };
      flow.height += props.spacingBefore;
      if (flow.previousParagraph case final previous?) {
        flow.height -= _paragraphGapOverlap(_afterParagraph(previous), props);
      }
      flow.previousParagraph = props;
      if (frame == null) {
        while (unanchored < frames.length) {
          frames[unanchored++].textAnchor = flow.height;
        }
      }
      final String overlayColor = run.color.isEmpty ? '222222' : run.color;
      void addLine(String label, List<int?> mapping, WmlJustification align) {
        final double width = label.isEmpty
            ? box.width
            : label.runes.fold(
                0.0,
                (sum, rune) => sum + _advanceOf(rune, size, 0.52, run),
              );
        final double x = switch (align) {
          WmlJustification.center =>
            frame == null
                ? (section.pageSize.width - width) / 2
                : box.left + (box.width - width) / 2,
          WmlJustification.right => box.left + box.width - width,
          _ => box.left,
        };
        final line = LaidOutLine(
          glyphs: <LaidOutGlyph>[],
          x: x,
          y: (frame == null ? y : 0) + flow.height,
          width: width,
          height: height,
          pageIndex: pageNumber - 1,
          paragraphIndex: i,
          sourceParagraph: paragraph,
          sourceText: source,
          proofingOffsets: mapping,
          justification: align,
          isFooter: isFooter,
          overlayText: label,
          overlayColor: overlayColor,
          overlaySize: size,
          overlayBold: run.bold,
          overlayBaseline: baseline,
          hyperlink: WordLink.firstIn(paragraph),
          boxX: box.left,
          boxWidth: box.width,
        );
        flow.lines.add(line);
        lines.add(line);
      }

      final List<String> tabParts = text.split('\t');
      if (tabParts.length >= 2) {
        final parts = <({String text, List<int?> offsets})>[];
        var partStart = 0;
        for (final part in tabParts) {
          final trimmed = part.trim();
          final leading = part.length - part.trimLeft().length;
          parts.add((
            text: trimmed,
            offsets: offsets.sublist(
              partStart + leading,
              partStart + leading + trimmed.length + 1,
            ),
          ));
          partStart += part.length + 1;
        }
        final left = parts.first;
        final mid = parts.length >= 3
            ? parts[1]
            : (text: '', offsets: <int?>[null]);
        final ({String text, List<int?> offsets}) right;
        if (parts.length >= 3) {
          final rightParts = parts.sublist(2);
          final rightOffsets = <int?>[];
          for (var j = 0; j < rightParts.length; j++) {
            if (j > 0) rightOffsets.add(null); // Presentation-only join space.
            rightOffsets.addAll(
              rightParts[j].offsets.take(rightParts[j].text.length),
            );
          }
          rightOffsets.add(rightParts.last.offsets.last);
          right = (
            text: rightParts.map((part) => part.text).join(' '),
            offsets: rightOffsets,
          );
        } else {
          right = parts.last;
        }
        void addPart(
          ({String text, List<int?> offsets}) part,
          WmlJustification align,
        ) {
          if (part.text.isNotEmpty) {
            addLine(part.text, part.offsets, align);
          }
        }

        addPart(left, WmlJustification.left);
        addPart(mid, WmlJustification.center);
        addPart(right, WmlJustification.right);
      } else {
        addLine(
          text,
          offsets,
          frame?.width == null
              ? frame?.alignmentForPage(pageNumber) ?? props.justification
              : props.justification,
        );
      }
      flow.height += height + props.spacingAfter;
    }
    final top = isFooter
        ? section.pageSize.height - section.margins.footer - ordinary.height
        : y;
    if (isFooter) {
      for (final line in ordinary.lines) {
        line._y += top;
      }
    }
    for (final flow in frames) {
      final frame = flow.frame!;
      final origin = switch (frame.vertical) {
        'page' => 0.0,
        'margin' => section.margins.top,
        _ => top + (flow.textAnchor ?? (isFooter ? -flow.height : 0)),
      };
      for (final line in flow.lines) {
        line._y += origin + frame.y;
      }
    }
    return lines;
  }

  static double _chromeBandHeight({
    required List<LaidOutLine> lines,
    required double fallback,
    required double pageHeight,
    required bool footer,
  }) {
    var height = math.max(fallback, 28);
    for (final LaidOutLine line in lines) {
      height = math.max(
        height,
        footer ? pageHeight - line.y + 6 : line.y + line.height + 6,
      );
    }
    return height.clamp(28, pageHeight * 0.35).toDouble();
  }
}
