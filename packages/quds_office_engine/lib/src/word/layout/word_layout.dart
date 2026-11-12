import 'dart:math' as math;

import '../../bidi/line_breaker.dart';
import '../../fonts/font_metrics.dart';
import '../../fonts/gpos_mark_to_base.dart';
import '../../fonts/office_font_set.dart';
import '../../fonts/office_typeface.dart';
import '../../fonts/sfnt_parser.dart';
import '../../visual/office_visual.dart';
import '../math/omml_document.dart';
import '../math/omml_layout.dart';
import '../model/wml_clone.dart';
import '../model/wml_document.dart';
import '../model/wml_run_edit.dart';
import '../model/word_comment.dart';
import '../model/word_fields.dart';
import '../model/word_link.dart';
import '../model/word_notes.dart';
import '../model/word_table.dart';
import '../model/word_toc.dart';
import '../properties/wml_properties.dart';

part 'word_note_layout.dart';
part 'word_table_row_layout.dart';

/// Class LaidOutGlyph.
class LaidOutGlyph {
  /// LaidOutGlyph API.
  LaidOutGlyph({
    required this.glyph,
    required this.x,
    required this.y,
    required this.color,
    required this.fontSize,
    required this.bold,
    required this.underline,
    this.italic = false,
    this.strike = false,
    this.highlight,
    this.fontFamily,
    this.vertAlign = WmlVertAlign.baseline,
    this.hyperlink,
    List<int>? commentIds,
    double? advance,
    double? paintDx,
    double? paintDy,
  }) : commentIds = commentIds ?? const <int>[],
       advance = advance ?? glyph.advance,
       paintDx = paintDx ?? glyph.paintDx,
       paintDy = paintDy ?? glyph.paintDy;

  /// glyph API.
  final ShapedGlyph glyph;

  /// x API.
  double x;

  /// y API.
  final double y;

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

  /// strike API.
  final bool strike;

  /// highlight API.
  final String? highlight;

  /// fontFamily API.
  final String? fontFamily;

  /// vertAlign API.
  final WmlVertAlign vertAlign;

  /// hyperlink API.
  final WmlHyperlink? hyperlink;

  /// commentIds API.
  final List<int> commentIds;

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
    required this.y,
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
    this.sourceText,
    this.tocTargetParagraph,
    this.tocLeader = false,
    this.hyperlink,
    this.justificationRatio = 0,
    this.boxX = 0,
    this.boxWidth = 0,
  });

  /// Inner left/right pad for table-cell text (`tblCellMar` 108 twips).
  static const double tableCellPad = 5.4;

  /// Inner pad for absolutely placed [WmlFrame] text.
  static const double framePad = 8;

  /// glyphs API.
  final List<LaidOutGlyph> glyphs;

  /// x API.
  double x;

  /// y API.
  final double y;

  /// width API.
  double width;

  /// height API.
  final double height;

  /// pageIndex API.
  final int pageIndex;

  /// justification API.
  final WmlJustification justification;

  /// paragraphIndex API.
  final int paragraphIndex;

  /// Logical source text covered by this line, including shaped note content.
  String get text {
    if (glyphs.isEmpty) return overlayText ?? '';
    final List<LaidOutGlyph> logical = List<LaidOutGlyph>.of(glyphs)
      ..sort(
        (LaidOutGlyph a, LaidOutGlyph b) =>
            a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex),
      );
    final String? source = sourceText;
    if (source != null) {
      final int start = logical.first.glyph.logicalIndex.clamp(
        0,
        source.length,
      );
      final LaidOutGlyph last = logical.last;
      final int end =
          (last.glyph.logicalIndex + (last.glyph.codePoint > 0xffff ? 2 : 1))
              .clamp(start, source.length);
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
}

/// Class LaidOutDocument.
class LaidOutDocument {
  /// LaidOutDocument API.
  LaidOutDocument({required this.pages, required this.pageSize});

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
    y = section.margins.top;
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
/// `TextPainter`) pass this to [WordLayoutEngine.measure] so line breaks use
/// the same widths the painter will use.
typedef WordGlyphMeasure =
    double Function(int codePoint, double sizePoints, WmlRunProps props);

/// Flowable pagination: Knuth-Plass lines accumulated into physical pages.
class WordLayoutEngine {
  /// WordLayoutEngine API.
  WordLayoutEngine({
    required this.font,
    this.fonts,
    this.fallbackWidthFactor = 0.5,
    this.measure,
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

  final Map<int, FontMetrics> _metricsCache = <int, FontMetrics>{};

  WmlDocument? _layoutDoc;
  final Map<WmlNote, _NoteStory> _noteStories = <WmlNote, _NoteStory>{};
  final Map<int, List<_NoteSlice>> _noteSlices = <int, List<_NoteSlice>>{};
  final Set<int> _placedNotes = <int>{};

  double _noteReserve(int page) {
    final List<_NoteSlice> slices = _noteSlices[page] ?? <_NoteSlice>[];
    return slices.isEmpty
        ? 0
        : 8 + slices.fold<double>(0, (double n, _NoteSlice s) => n + s.height);
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
    return (_noteReserve(page) == 0 ? 8 : 0) +
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
            (_noteReserve(target) == 0 ? 8 : 0) -
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

  double _advanceOf(
    int cp,
    double sizePoints,
    double emFallback,
    WmlRunProps props,
  ) {
    if (cp == 0x09) {
      return kDefaultTabWidth;
    }
    final SfntFont? face =
        fonts?.faceFor(cp) ??
        (font != null && font!.glyphIdFor(cp) != 0 ? font : null);
    if (face == null) {
      final WordGlyphMeasure? hostMeasure = measure;
      return hostMeasure != null
          ? hostMeasure(cp, sizePoints, props)
          : sizePoints * emFallback;
    }
    final int key = identityHashCode(face) ^ (sizePoints * 100).round();
    final FontMetrics metrics = _metricsCache.putIfAbsent(
      key,
      () => FontMetrics(font: face, fontSizePoints: sizePoints),
    );
    return metrics.characterWidth(cp);
  }

  /// Tallest header logo height for [section] (0 if none).
  static double _headerLogoHeight(WmlSection section) {
    var maxH = 0.0;
    void consider(List<WmlVisual> visuals) {
      for (final WmlVisual item in visuals) {
        maxH = math.max(maxH, item.visual.height);
      }
    }

    consider(section.headerVisuals);
    consider(section.firstHeaderVisuals);
    consider(section.evenHeaderVisuals);
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

  /// layout API.
  LaidOutDocument layout(
    WmlDocument document, {
    bool updateFields = true,
    int fromSectionIndex = 0,
    LaidOutDocument? reuse,
  }) {
    _layoutDoc = document;
    _noteStories.clear();
    _noteSlices.clear();
    _placedNotes.clear();
    if (document.footnotes.isNotEmpty) fromSectionIndex = 0;
    if (updateFields) {
      WordFields.update(document);
    }
    final List<LaidOutPage> pages = <LaidOutPage>[];
    var paragraphIndex = 0;
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
    _appendEndnotes(document, pages);
    if (updateFields) {
      WordFields.update(document, pageCount: pages.length);
    }
    return LaidOutDocument(
      pages: pages,
      pageSize: document.sections.first.pageSize,
    );
  }

  static double _contentBottom(LaidOutPage page, {required double fallback}) {
    var bottom = fallback;
    for (final LaidOutLine line in page.lines) {
      bottom = math.max(bottom, line.y + line.height);
    }
    for (final LaidOutBox box in page.frames) {
      if (!box.isNoteContent) bottom = math.max(bottom, box.y + box.height);
    }
    return bottom;
  }

  int _layoutSection(
    WmlSection section,
    List<LaidOutPage> pages, {
    required int sectionIndex,
    required int paragraphIndex,
  }) {
    _padSectionBreak(section, pages, sectionIndex);
    final bool continuous =
        sectionIndex > 0 && section.breakKind == WmlSectionBreakKind.continuous;
    final _Flow flow = _Flow(
      section,
      pages,
      _makePage,
      sectionIndex,
      _noteReserve,
    );
    // Leave room under a floating header logo for title/body on page 1.
    flow.y = _bodyTopClearingLogo(section);
    flow.columnTop = flow.y;
    if (continuous && pages.isNotEmpty) {
      final LaidOutPage last = pages.removeLast();
      flow.current.addAll(last.lines);
      flow.currentFrames.addAll(
        last.frames.where((LaidOutBox b) => !b.isNoteContent),
      );
      flow.pageIndex = last.index;
      flow.y = _contentBottom(last, fallback: _bodyTopClearingLogo(section));
      flow.columnTop = flow.y;
    }
    for (final WmlBlock block in section.blocks) {
      switch (block) {
        case WmlOpaqueBlock():
          break;
        case WmlParagraph():
          if (block.properties.pageBreakBefore) {
            flow.breakPage();
          } else if (block.properties.columnBreakBefore ||
              _hasBreak(block, WmlBreakType.column)) {
            flow.nextColumn();
          } else if (_hasBreak(block, WmlBreakType.page)) {
            flow.breakPage();
          }
          final ({double y, int pageIndex}) para = _layoutParagraph(
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
          if (flow.y > flow.bottom) {
            flow.nextColumn();
          }
        case WmlTable():
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
          paragraphIndex = _layoutFrame(block, section, flow, paragraphIndex);
        case WmlEquation():
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
          );
          flow.y = toc.y;
          flow.pageIndex = toc.pageIndex;
          paragraphIndex += 1 + block.itemParagraphs.length;
      }
    }
    flow.finish();
    return paragraphIndex;
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

  int _layoutParagraphCountIn(List<WmlBlock> blocks) {
    var n = 0;
    for (final WmlBlock block in blocks) {
      switch (block) {
        case WmlOpaqueBlock():
          break;
        case WmlParagraph():
          n++;
        case WmlTable():
          n += _tableParagraphCount(block);
        case WmlFrame():
          n += _layoutParagraphCountIn(block.blocks);
        case WmlToc():
          n += 1 + block.itemParagraphs.length;
        case WmlVisual():
        case WmlEquation():
          break;
      }
    }
    return n;
  }

  static int _tableParagraphCount(WmlTable table) {
    var n = 0;
    for (final WmlTableRow row in table.rows) {
      for (final WmlTableCell cell in row.cells) {
        for (final WmlBlock block in cell.blocks) {
          if (block is WmlParagraph) {
            n++;
          }
        }
      }
    }
    return n;
  }

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
  }) {
    final WmlRunProps runProps = WmlRunEdit.propsAt(paragraph, 0);
    final double fontSize = runProps.fontSizePoints;
    final FontMetrics? metrics = font == null
        ? null
        : FontMetrics(font: font!, fontSizePoints: fontSize);
    final double lineHeight = _lineHeight(
      paragraph.properties,
      metrics,
      fontSize,
    );
    final String? listLabel = paragraph.properties.listLabel;
    final double hanging = paragraph.properties.indent.hanging;
    final double indentLeft = paragraph.properties.indent.left;
    final double firstLineShift = hanging > 0
        ? 0
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
    // Empty paragraphs are a full blank line in Word. A tab is content.
    if (!paragraph.text.contains('\t') &&
        paragraph.text.trim().isEmpty &&
        listLabel == null &&
        !paragraph.properties.pageNumberField &&
        paragraph.properties.noteId == null) {
      final double gap =
          paragraph.properties.spacingBefore +
          lineHeight +
          paragraph.properties.spacingAfter;
      return (y: y + gap, pageIndex: pageIndex);
    }
    final String text = paragraph.text;
    // Table cells and frames (laid out without page breaks) use a wider em
    // so the painted text stays inside their border.
    final double em = allowBreak
        ? fallbackWidthFactor
        : math.max(fallbackWidthFactor, 0.72);
    final List<BrokenLine> broken = LineBreaker.breakLines(
      text: text,
      maxWidth: maxWidth,
      widthOf: (int cp) => _advanceOf(cp, fontSize, em, runProps),
      glyphIdOf: (int cp) {
        final SfntFont? face = fonts?.faceFor(cp) ?? font;
        return face?.glyphIdFor(cp) ?? cp;
      },
      markAttachOf: font == null
          ? null
          : GposMarkToBase.fnFor(
              font!,
              fontSize,
              faceFor: (int cp) => fonts?.faceFor(cp) ?? font,
            ),
      baseLevel: paragraph.properties.bidiBaseLevel,
    );
    var cursorY = y + paragraph.properties.spacingBefore;
    var idx = pageIndex;
    var lineOrigin = originX ?? section.margins.left;
    final int dropLines = paragraph.properties.dropCapLines;
    final double dropWidth = dropLines > 0 ? fontSize * 2.4 : 0;
    final int lineStart = current.length;
    final double paraTop = cursorY;
    for (final BrokenLine line in broken) {
      final List<int> noteIds = _noteIds(
        paragraph,
        line.glyphs.map((ShapedGlyph g) => g.logicalIndex),
      ).toList();
      double occupiedBottom() {
        var bottom = cursorY + lineHeight;
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
          (cursorY + lineHeight > _bodyBottom(section, idx) ||
              (_minimumNotes(noteIds, section, idx) > 0 &&
                  occupiedBottom() + _minimumNotes(noteIds, section, idx) >
                      _bodyBottom(section, idx)))) {
        if (current.isEmpty &&
            currentFrames.isEmpty &&
            _noteReserve(idx) == 0 &&
            cursorY <= section.margins.top + 0.01) {
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
      }
      if (allowBreak) _reserveNotes(noteIds, section, idx, occupiedBottom());
      final double x0 =
          lineOrigin +
          textLeft +
          (identical(line, broken.first) ? firstLineShift : 0);
      double x = x0;
      if (paragraph.properties.justification == WmlJustification.center) {
        x += (maxWidth - line.width) / 2;
      } else if (paragraph.properties.justification == WmlJustification.right) {
        x += maxWidth - line.width;
      }
      var gx = x;
      final List<LaidOutGlyph> glyphs = <LaidOutGlyph>[];
      for (final ShapedGlyph g in line.glyphs) {
        final WmlRunProps props = WmlRunEdit.propsAt(paragraph, g.logicalIndex);
        final double baseSize = props.fontSizePoints;
        final double size = baseSize * props.vertAlign.fontScale;
        final double scale = fontSize <= 0
            ? props.vertAlign.fontScale
            : size / fontSize;
        glyphs.add(
          LaidOutGlyph(
            glyph: g,
            x: gx + g.paintDx * scale,
            y:
                cursorY +
                (metrics?.ascender ?? baseSize * 0.8) +
                props.vertAlign.baselineShift(baseSize) -
                g.paintDy * scale,
            color: props.color,
            fontSize: size,
            bold: props.bold,
            underline: props.underline,
            italic: props.italic,
            strike: props.strike,
            highlight: WmlHighlight.toRgb(props.highlight) ?? props.highlight,
            fontFamily: OfficeTypeface.familyForRun(props, g.codePoint),
            vertAlign: props.vertAlign,
            hyperlink: WordLink.at(paragraph, g.logicalIndex),
            commentIds: WordComment.idsAt(paragraph, g.logicalIndex),
            advance: g.advance * scale,
            paintDx: g.paintDx * scale,
            paintDy: g.paintDy * scale,
          ),
        );
        gx += g.advance * scale;
      }
      final bool paraRtl =
          paragraph.properties.rightToLeft == true ||
          paragraph.properties.bidiBaseLevel == 1;
      final double markerX = listLabel == null
          ? 0
          : (paraRtl
                ? lineOrigin + textLeft + maxWidth + 2
                : lineOrigin + textLeft - markerSlot);
      final LaidOutLine laid = LaidOutLine(
        glyphs: glyphs,
        x: x,
        y: cursorY,
        width: line.width,
        height: lineHeight,
        pageIndex: idx,
        justification: paragraph.properties.justification,
        paragraphIndex: paragraphIndex,
        listLabel: listLabel,
        listMarkerX: markerX,
        isParagraphStart: identical(line, broken.first),
        sourceText: sourceText,
        tocTargetParagraph: tocTargetParagraph,
        overlayText: identical(line, broken.last) ? overlayText : null,
        tocLeader: tocLeader && identical(line, broken.last),
        justificationRatio: line.justificationRatio,
        boxX: lineOrigin,
        boxWidth: contentBox,
      );
      laid.applyJustification(targetWidth: maxWidth);
      current.add(laid);
      cursorY += lineHeight;
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
    int paragraphIndex,
  ) {
    var cursorY = y;
    var idx = pageIndex;
    var para = paragraphIndex;
    final ({double y, int pageIndex}) title = _layoutParagraph(
      toc.titleParagraph,
      section,
      pages,
      current,
      currentFrames,
      idx,
      cursorY,
      para,
      sourceText: toc.titleParagraph.text,
    );
    cursorY = title.y;
    idx = title.pageIndex;
    para++;
    final int itemCount = toc.itemParagraphs.length;
    for (int i = 0; i < itemCount; i++) {
      final WmlParagraph item = toc.itemParagraphs[i];
      final WmlTocEntry? entry = i < toc.entries.length ? toc.entries[i] : null;
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
        tocTargetParagraph: entry?.headingParagraphIndex,
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
      if (entryLines.isNotEmpty && entry != null) {
        final LaidOutLine first = entryLines.first;
        final LaidOutLine last = entryLines.last;
        currentFrames.add(
          LaidOutBox(
            x: section.margins.left,
            y: first.y,
            width: section.contentWidth,
            height: (last.y + last.height) - first.y,
            strokeColor: '00000000',
            kind: LaidOutBoxKind.tocEntry,
            paragraphIndex: entry.headingParagraphIndex,
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
  }) {
    final List<double> cols = _columnWidths(table, section, maxWidthOverride);
    var cursorY = y + 6;
    var idx = pageIndex;
    var para = paragraphIndex;
    const double cellPad = LaidOutLine.tableCellPad;
    final double tableX = originX ?? section.margins.left;
    final double tableWidth = cols.fold<double>(
      0,
      (double sum, double width) => sum + width,
    );
    final bool rtl = table.properties.rightToLeft;

    for (final WmlTableRow row in table.rows) {
      final int rowIndex = table.rows.indexOf(row);
      final double fullRowHeight = _measureTableRowHeightFrom(
        row,
        cols,
        section,
        nextBlock: List<int>.filled(row.cells.length, 0),
        tableX: tableX,
        tableWidth: tableWidth,
        rtl: rtl,
        cellPad: cellPad,
      );
      if (fullRowHeight > section.contentHeight - cellPad * 2) {
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
        para += row.cells
            .expand((cell) => cell.blocks)
            .expand(WmlClone.paragraphsOf)
            .length;
        continue;
      }
      final List<int> nextBlock = List<int>.filled(row.cells.length, 0);
      var sliceStart = true;
      while (true) {
        var remaining = false;
        for (int c = 0; c < row.cells.length; c++) {
          if (nextBlock[c] < row.cells[c].blocks.length) {
            remaining = true;
            break;
          }
        }
        if (!remaining) {
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
        if (_minimumNotes(rowNotes, section, idx) > 0) {
          final double rowHeight = _measureTableRowHeightFrom(
            row,
            cols,
            section,
            nextBlock: nextBlock,
            tableX: tableX,
            tableWidth: tableWidth,
            rtl: rtl,
            cellPad: cellPad,
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
        while ((current.isNotEmpty ||
                currentFrames.isNotEmpty ||
                _noteReserve(idx) > 0) &&
            cursorY + cellPad + 12 > pageBottom) {
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
        if (sliceStart &&
            row.cantSplit &&
            (current.isNotEmpty || currentFrames.isNotEmpty)) {
          final double estimated = _measureTableRowHeightFrom(
            row,
            cols,
            section,
            nextBlock: nextBlock,
            tableX: tableX,
            tableWidth: tableWidth,
            rtl: rtl,
            cellPad: cellPad,
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
        final List<LaidOutBox> rowFrames = <LaidOutBox>[];
        final List<int> placed = List<int>.filled(row.cells.length, 0);
        var needsContinue = false;

        for (int c = 0; c < row.cells.length; c++) {
          final WmlTableCell cell = row.cells[c];
          final int span = WordTable.spanOf(cell);
          var colW = 0.0;
          for (int k = 0; k < span; k++) {
            colW += cols[(gridCol + k).clamp(0, cols.length - 1)];
          }
          if (rtl) {
            x -= colW;
          }
          final int cellParaStart = para;
          var cellY = rowStartY + cellPad;
          var bi = nextBlock[c];
          while (bi < cell.blocks.length) {
            final WmlBlock block = cell.blocks[bi];
            final double blockH = _estimateCellBlockHeight(
              block,
              section,
              maxWidth: math.max(12, colW - cellPad * 2),
            );
            if (!row.cantSplit &&
                cellY + blockH > pageBottom &&
                cellY > rowStartY + cellPad + 0.5) {
              needsContinue = true;
              break;
            }
            // Word-like orphan control for consecutive list items: if this
            // block fits but the next list sibling does not, break before
            // this block so the pair moves together (e.g. UN OCHA + CEPs).
            if (!row.cantSplit &&
                bi + 1 < cell.blocks.length &&
                cellY > rowStartY + cellPad + 0.5 &&
                cellY + blockH <= pageBottom) {
              final WmlBlock nextBlock = cell.blocks[bi + 1];
              if (_listOrphanPair(block, nextBlock)) {
                final double nextH = _estimateCellBlockHeight(
                  nextBlock,
                  section,
                  maxWidth: math.max(12, colW - cellPad * 2),
                );
                if (cellY + blockH + nextH > pageBottom) {
                  needsContinue = true;
                  break;
                }
              }
            }
            if (block is WmlParagraph) {
              final ({double y, int pageIndex}) laid = _layoutParagraph(
                block,
                section,
                pages,
                current,
                currentFrames,
                idx,
                cellY,
                para,
                originX: x + cellPad,
                maxWidthOverride: math.max(12, colW - cellPad * 2),
                allowBreak: false,
              );
              cellY = laid.y;
              idx = laid.pageIndex;
              para++;
            } else if (block is WmlEquation) {
              final LaidOutOmml omml = OmmlLayout.layout(
                block.math,
                fontSize: 14,
              );
              currentFrames.add(
                LaidOutBox(
                  x: x + cellPad,
                  y: cellY,
                  width: math.min(colW - cellPad * 2, omml.width),
                  height: omml.height,
                  fillColor: 'F7FBFF',
                  strokeColor: '8FAADC',
                  kind: LaidOutBoxKind.equation,
                  equation: block,
                  omml: omml,
                ),
              );
              cellY += omml.height + 4;
            }
            bi++;
          }
          placed[c] = bi - nextBlock[c];
          final int previous = nextBlock[c];
          nextBlock[c] = bi;
          rowBottom = math.max(rowBottom, cellY + cellPad);
          final bool firstSlice = sliceStart;
          final bool lastSlice = bi >= cell.blocks.length;
          // Skip cells that were empty from the start of the row. On
          // continuation slices, still emit frames for exhausted cells so the
          // grid (e.g. empty CHAIN cell beside WORKING RELATIONS) remains.
          if (!(placed[c] == 0 &&
              previous >= cell.blocks.length &&
              sliceStart)) {
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
                paragraphIndex: cellParaStart,
                paragraphEnd: para > cellParaStart ? para - 1 : cellParaStart,
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
        final double height = math.max(minH, rowBottom - rowStartY);
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
          currentFrames.add(frame);
        }
        cursorY = rowStartY + height;
        sliceStart = false;

        if (needsContinue) {
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
    }
    _applyVerticalMerges(table, currentFrames);
    return (y: cursorY + 4, pageIndex: idx);
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

  double _estimateCellBlockHeight(
    WmlBlock block,
    WmlSection section, {
    required double maxWidth,
  }) {
    if (block is WmlParagraph) {
      final List<LaidOutPage> pages = <LaidOutPage>[];
      final List<LaidOutLine> lines = <LaidOutLine>[];
      final List<LaidOutBox> frames = <LaidOutBox>[];
      final ({double y, int pageIndex}) laid = _layoutParagraph(
        block,
        section,
        pages,
        lines,
        frames,
        0,
        0,
        0,
        originX: 0,
        maxWidthOverride: maxWidth,
        allowBreak: false,
      );
      return laid.y;
    }
    if (block is WmlEquation) {
      return OmmlLayout.layout(block.math, fontSize: 14).height + 4;
    }
    if (block is WmlOpaqueBlock) return 0;
    return 18;
  }

  double _measureTableRowHeightFrom(
    WmlTableRow row,
    List<double> cols,
    WmlSection section, {
    required List<int> nextBlock,
    required double tableX,
    required double tableWidth,
    required bool rtl,
    required double cellPad,
  }) {
    var rowBottom = 0.0;
    var gridCol = 0;
    for (int c = 0; c < row.cells.length; c++) {
      final WmlTableCell cell = row.cells[c];
      final int span = WordTable.spanOf(cell);
      var colW = 0.0;
      for (int k = 0; k < span; k++) {
        colW += cols[(gridCol + k).clamp(0, cols.length - 1)];
      }
      var cellY = cellPad;
      for (int bi = nextBlock[c]; bi < cell.blocks.length; bi++) {
        cellY += _estimateCellBlockHeight(
          cell.blocks[bi],
          section,
          maxWidth: math.max(12, colW - cellPad * 2),
        );
      }
      rowBottom = math.max(rowBottom, cellY + cellPad);
      gridCol += span;
    }
    return math.max(row.height ?? 0, rowBottom);
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
    if (visuals.isEmpty) {
      return const <LaidOutBox>[];
    }
    final double bandTop = isFooter
        ? section.pageSize.height -
              math.max(section.margins.footer, section.margins.bottom * 0.55)
        : section.margins.header;
    final List<LaidOutBox> frames = <LaidOutBox>[];
    var x = section.margins.left;
    for (final WmlVisual item in visuals) {
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

  void _applyVerticalMerges(WmlTable table, List<LaidOutBox> frames) {
    final List<LaidOutBox> mine = <LaidOutBox>[
      for (final LaidOutBox box in frames)
        if (identical(box.table, table) && box.kind == LaidOutBoxKind.tableCell)
          box,
    ];
    for (final LaidOutBox box in mine) {
      final int r = box.tableRow ?? 0;
      final int c = box.tableCol ?? 0;
      if (r >= table.rows.length || c >= table.rows[r].cells.length) {
        continue;
      }
      final WmlTableCell cell = table.rows[r].cells[c];
      if (cell.vMerge != WmlVMerge.restart) {
        continue;
      }
      final int g0 = WordTable.gridStart(table.rows[r], c);
      var bottom = box.y + box.height;
      for (int rr = r + 1; rr < table.rows.length; rr++) {
        final int? i = WordTable.cellIndexAtGrid(table.rows[rr], g0);
        if (i == null || table.rows[rr].cells[i].vMerge != WmlVMerge.cont) {
          break;
        }
        LaidOutBox? cont;
        for (final LaidOutBox other in mine) {
          if (other.tableRow == rr && other.tableCol == i) {
            cont = other;
            break;
          }
        }
        if (cont == null) {
          break;
        }
        bottom = math.max(bottom, cont.y + cont.height);
        cont
          ..height = 0
          ..fillColor = null
          ..strokeColor = '00000000';
      }
      box.height = bottom - box.y;
    }
  }

  int _layoutFrame(
    WmlFrame frame,
    WmlSection section,
    _Flow flow,
    int paragraphIndex,
  ) {
    final double x = frame.pageX(section);
    final double y = frame.pageY(section);
    const double pad = LaidOutLine.framePad;
    flow.currentFrames.add(
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
    var cursorY = y + pad;
    var para = paragraphIndex;
    final double innerX = x + pad;
    final double innerW = math.max(12, frame.width - pad * 2);
    for (final WmlBlock block in frame.blocks) {
      switch (block) {
        case WmlOpaqueBlock():
          break;
        case WmlParagraph():
          final ({double y, int pageIndex}) laid = _layoutParagraph(
            block,
            section,
            flow.pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            cursorY,
            para,
            originX: innerX,
            maxWidthOverride: innerW,
            allowBreak: false,
          );
          cursorY = laid.y;
          para++;
        case WmlVisual():
          final ({double y, int pageIndex}) laid = _layoutVisual(
            block.visual,
            section,
            flow.pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            cursorY,
            originX: innerX,
            maxWidthOverride: innerW,
            allowBreak: false,
          );
          cursorY = laid.y;
        case WmlTable():
          final ({double y, int pageIndex}) laid = _layoutTable(
            block,
            section,
            flow.pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            cursorY,
            para,
            originX: innerX,
            maxWidthOverride: innerW,
          );
          cursorY = laid.y;
          para += _tableParagraphCount(block);
        case WmlEquation():
          final ({double y, int pageIndex}) laid = _layoutEquation(
            block,
            section,
            flow.pages,
            flow.current,
            flow.currentFrames,
            flow.pageIndex,
            cursorY,
          );
          cursorY = laid.y;
        case WmlFrame():
          para = _layoutFrame(block, section, flow, para);
        case WmlToc():
          break;
      }
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
    _Flow? flow,
    bool allowBreak = true,
  }) {
    final double maxW = maxWidthOverride ?? section.contentWidth;
    final bool absolute =
        visual.picture.wrap == PictureWrap.behind ||
        visual.picture.wrap == PictureWrap.inFront;
    final double width = visual.width.clamp(
      24,
      absolute ? section.pageSize.width : maxW,
    );
    final double height = visual.height.clamp(
      24,
      absolute ? section.pageSize.height : section.contentHeight,
    );
    if (absolute) {
      currentFrames.add(
        _visualBox(visual, visual.offsetX, visual.offsetY, width, height),
      );
      return (y: y, pageIndex: pageIndex);
    }
    final bool atTop = (y - section.margins.top).abs() < 0.5;
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
    // Word's painted single-line box for Calibri/Western text tracks ~115% of
    // (ascender-descender+lineGap), then multiplies by w:line/240.
    final double fontLine = metrics == null
        ? fontSize * 1.2
        : math.max(fontSize * 1.2, metrics.lineHeight);
    // Empirically matches Word Calibri line boxes on Table Grid docs.
    final double single = fontLine * 1.10;
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
    var y = _bodyBottom(section, page.index) + 8;
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
    final List<WmlNote> notes = <WmlNote>[
      for (final WmlNote note in document.endnotes)
        if (note.id > 0 &&
            (note.text.trim().isNotEmpty ||
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
    final double y = isFooter
        ? section.pageSize.height -
              math.max(
                22,
                math.max(section.margins.footer, section.margins.bottom * 0.45),
              )
        : math.max(8, section.margins.header);
    final List<LaidOutLine> lines = <LaidOutLine>[];
    var offsetY = 0.0;
    for (int i = 0; i < story.length; i++) {
      final WmlParagraph paragraph = story[i];
      final WmlRunProps run = WmlRunEdit.propsAt(paragraph, 0);
      final WmlDocument? doc = _layoutDoc;
      final String raw = paragraph.text.trim();
      final String text;
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
      } else if (_looksLikePageCache(raw)) {
        text = '$pageNumber';
      } else {
        text = raw;
      }
      final double size = run.fontSizePoints.clamp(8, 16);
      final String overlayColor = run.color.isEmpty
          ? (isFooter ? '222222' : '6B7280')
          : run.color;
      final List<String> tabParts = text.split('\t');
      if (tabParts.length >= 2) {
        final List<String> parts = <String>[
          for (final String part in tabParts)
            _looksLikePageCache(part.trim()) ? '$pageNumber' : part.trim(),
        ];
        final String left = parts.first;
        final String mid = parts.length >= 3 ? parts[1] : '';
        final String right = parts.length >= 3
            ? parts.sublist(2).join(' ')
            : parts.last;
        void addPart(String part, WmlJustification align) {
          if (part.isEmpty) {
            return;
          }
          final double width = part.length * size * 0.52;
          var x = section.margins.left;
          if (align == WmlJustification.center) {
            x = (section.pageSize.width - width) / 2;
          } else if (align == WmlJustification.right) {
            x = section.pageSize.width - section.margins.right - width;
          }
          lines.add(
            LaidOutLine(
              glyphs: <LaidOutGlyph>[],
              x: x,
              y: y + offsetY,
              width: width,
              height: size + 3,
              pageIndex: pageNumber - 1,
              paragraphIndex: i,
              justification: align,
              isFooter: isFooter,
              overlayText: part,
              overlayColor: overlayColor,
              overlaySize: size,
              overlayBold: run.bold,
              hyperlink: WordLink.firstIn(paragraph),
              boxX: section.margins.left,
              boxWidth: section.contentWidth,
            ),
          );
        }

        addPart(left, WmlJustification.left);
        addPart(mid, WmlJustification.center);
        addPart(right, WmlJustification.right);
        offsetY += size + 4;
        continue;
      }
      final double width = text.isEmpty
          ? section.contentWidth
          : text.length * size * 0.52;
      var x = section.margins.left;
      if (paragraph.properties.justification == WmlJustification.center) {
        x = (section.pageSize.width - width) / 2;
      } else if (paragraph.properties.justification == WmlJustification.right) {
        x = section.pageSize.width - section.margins.right - width;
      }
      lines.add(
        LaidOutLine(
          glyphs: <LaidOutGlyph>[],
          x: x,
          y: y + offsetY,
          width: width,
          height: size + 3,
          pageIndex: pageNumber - 1,
          paragraphIndex: i,
          justification: paragraph.properties.justification,
          isFooter: isFooter,
          overlayText: text,
          overlayColor: overlayColor,
          overlaySize: size,
          overlayBold: run.bold,
          hyperlink: WordLink.firstIn(paragraph),
          boxX: section.margins.left,
          boxWidth: section.contentWidth,
        ),
      );
      offsetY += size + 4;
    }
    return lines;
  }

  static bool _looksLikePageCache(String text) =>
      RegExp(r'^\d+$').hasMatch(text);

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
