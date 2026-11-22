part of 'word_layout.dart';

// Incremental relayout for local edits.
//
// The body flow is a greedy, forward-only stream: the layout of a top-level
// block depends only on the flow state when it starts (page, column, y,
// whether the page already has content, the preceding paragraph's after
// spacing and the running paragraph index) and on the block itself. A full
// layout therefore records that state as a checkpoint before every visible
// top-level block. After a local edit the engine:
//
//  1. finds the dirty blocks: blocks the caller names (they contain an edited
//     paragraph), blocks whose text changed, and inserted/removed blocks
//     (identity sequence differs), widened by one block on each side;
//  2. resumes the flow at the checkpoint of the first dirty block, reusing
//     every finished page before it and the partial page's earlier lines;
//  3. lays out from there and, after the last dirty block, compares the
//     flow state at each block with that block's old checkpoint. Once they
//     are equal the rest of the old layout is exactly what a full layout
//     would produce: the old partial page's remaining lines and all later
//     pages are spliced in (paragraph indices shifted when paragraphs were
//     inserted or removed) and layout stops.
//
// Footnotes are part of the flow state: a checkpoint also records how many
// notes were placed and the note slices already reserved on pages not yet
// finished; the layout keeps the final slices of every page, the placement
// order and the shaped note stories. Resuming restores them, convergence
// requires them to be equal, and the splice takes the old layout's note
// slices for the reused pages. Note-overflow pages and endnotes (appended
// after the body) are made again by every layout. A change of note
// numbering or note content falls back.
//
// Anything the checkpoints cannot capture falls back to the ordinary path:
// field updates, wrapping frames on the page at the resume or convergence
// point, missing or foreign state, note numbering or note content changes,
// and section list changes. A layout rule
// that looks ahead across top-level blocks (keep-with-next, widow control)
// must extend the dirty range or disable reuse here; the equivalence suite
// (`incremental_layout_equivalence_test.dart`) and [verifyIncrementalLayout]
// compare against a fresh full layout.

/// How a page was made, so a spliced page can be made again with new lines.
class _PageOrigin {
  _PageOrigin(
    this.section,
    this.sectionIndex,
    this.firstInSection,
    this.bodyFrames,
  );

  final WmlSection section;
  final int sectionIndex;
  final bool firstInSection;

  /// Frames passed by the flow; chrome, notes and line numbers follow them.
  final int bodyFrames;
}

/// Flow state immediately before a visible top-level block.
class _Checkpoint {
  _Checkpoint({
    required this.pagesLength,
    required this.pageIndex,
    required this.columnIndex,
    required this.y,
    required this.columnTop,
    required this.lines,
    required this.frames,
    required this.adjacentAfter,
    required this.paragraphIndex,
    required this.wrapFrames,
    this.placedNotes = 0,
    this.pendingNotes,
  });

  final int pagesLength;
  final int pageIndex;
  final int columnIndex;
  final double y;
  final double columnTop;

  /// Lines and frames already on the page being filled.
  final int lines;
  final int frames;
  final double? adjacentAfter;
  final int paragraphIndex;

  /// A text-wrapping frame is on the page being filled.
  final bool wrapFrames;

  /// Footnotes placed so far (a prefix of the placement order).
  final int placedNotes;

  /// Note slices already reserved on unfinished pages (index >=
  /// [pagesLength]); null when there are none.
  final Map<int, List<_NoteSlice>>? pendingNotes;

  bool get hasContent => lines > 0 || frames > 0;

  /// The same checkpoint after a splice: paragraph indices move by [delta];
  /// on the spliced page ([page]) the new prefix can hold a different number
  /// of lines and frames than the old one (an empty paragraph has height but
  /// no line, and may gain one at the same height).
  _Checkpoint shifted(
    int delta, {
    required int page,
    required int lineDelta,
    required int frameDelta,
  }) {
    final bool onPage = pagesLength == page;
    if (delta == 0 && (!onPage || lineDelta == 0 && frameDelta == 0)) {
      return this;
    }
    return _Checkpoint(
      pagesLength: pagesLength,
      pageIndex: pageIndex,
      columnIndex: columnIndex,
      y: y,
      columnTop: columnTop,
      lines: onPage ? lines + lineDelta : lines,
      frames: onPage ? frames + frameDelta : frames,
      adjacentAfter: adjacentAfter,
      paragraphIndex: paragraphIndex + delta,
      wrapFrames: wrapFrames,
      placedNotes: placedNotes,
      pendingNotes: pendingNotes,
    );
  }
}

class _SectionRecord {
  _SectionRecord(this.section);

  final WmlSection section;
  final List<WmlBlock> blocks = <WmlBlock>[];

  /// Text of each block's paragraphs when it was laid out.
  final List<String> texts = <String>[];
  final List<_Checkpoint> checkpoints = <_Checkpoint>[];
}

class _IncrementalState {
  _IncrementalState(this.owner, this.document, this.sections)
    : noSpaceRaiseLower = document.sourceNoSpaceRaiseLower;

  /// Opaque identity of the engine that shaped these pages and checkpoints.
  final Object owner;
  final WmlDocument document;
  final List<_SectionRecord?> sections;
  final bool noSpaceRaiseLower;

  /// Pages made by the body flow; later pages hold only note overflow and
  /// endnotes and are made again by every layout.
  int flowPages = 0;

  /// Footnote and endnote state at the end of the layout (null without
  /// notes).
  _NoteState? notes;
}

/// Document-wide note state of one layout (see the file comment).
class _NoteState {
  _NoteState({
    required this.slices,
    required this.placedOrder,
    required this.stories,
    required this.numbering,
    required this.content,
    required this.endnotePage,
    required this.endnoteLines,
    required this.endnoteFrames,
  });

  /// Final note slices per page.
  final Map<int, List<_NoteSlice>> slices;

  /// Footnote ids in placement order.
  final List<int> placedOrder;

  /// Shaped note stories, reused while numbering and content are unchanged.
  final Map<WmlNote, _NoteStory> stories;

  /// Note order and labels ([WordNoteNumbering]) and note content.
  final List<Object> numbering;
  final List<Object> content;

  /// The page endnotes were appended to, and its note lines and frames
  /// before them (-1: no endnotes).
  final int endnotePage;
  final int endnoteLines;
  final int endnoteFrames;
}

bool _sameObjects(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    final Object x = a[i];
    final Object y = b[i];
    if (x is String ? x != y : !identical(x, y)) return false;
  }
  return true;
}

bool _sameSlices(List<_NoteSlice>? a, List<_NoteSlice>? b) {
  if ((a?.length ?? 0) != (b?.length ?? 0)) return false;
  if (a == null || b == null) return true;
  for (int i = 0; i < a.length; i++) {
    if (!identical(a[i].story, b[i].story) ||
        a[i].start != b[i].start ||
        a[i].end != b[i].end ||
        !identical(a[i].section, b[i].section) ||
        a[i].sectionIndex != b[i].sectionIndex) {
      return false;
    }
  }
  return true;
}

/// Where the new flow met the old one.
class _Splice {
  _Splice({
    required this.sectionIndex,
    required this.newBlock,
    required this.oldBlock,
    required this.checkpoint,
    required this.delta,
    required this.lines,
    required this.frames,
  });

  final int sectionIndex;
  final int newBlock;
  final int oldBlock;
  final _Checkpoint checkpoint;
  final int delta;
  final List<LaidOutLine> lines;
  final List<LaidOutBox> frames;
}

/// Convergence targets for one incremental layout.
class _Convergence {
  _Convergence({
    required this.old,
    required this.oldPages,
    required this.lastDirtySection,
    required this.firstCandidateBlock,
    required this.blockOffset,
  });

  final _IncrementalState old;
  final List<LaidOutPage> oldPages;
  final int lastDirtySection;

  /// In [lastDirtySection]: first new block index after the dirty range and
  /// the difference between new and old block indices from there on.
  final int firstCandidateBlock;
  final int blockOffset;
}

class _Recorder {
  _Recorder(int sectionCount)
    : sections = List<_SectionRecord?>.filled(sectionCount, null);

  final List<_SectionRecord?> sections;
  _Convergence? convergence;
  _Splice? splice;

  /// Top-level blocks an incremental layout must lay out from scratch.
  Set<WmlBlock> dirtyBlocks = const <WmlBlock>{};

  /// Resumed sections keep the old records before the resume block.
  void begin(WmlSection section, int sectionIndex, {_SectionRecord? prefix}) {
    final _SectionRecord record = _SectionRecord(section);
    if (prefix != null) {
      record.blocks.addAll(prefix.blocks);
      record.texts.addAll(prefix.texts);
      record.checkpoints.addAll(prefix.checkpoints);
    }
    sections[sectionIndex] = record;
  }

  void record(
    int sectionIndex,
    WmlBlock block,
    _Flow flow,
    int paragraphIndex,
    double? adjacentAfter, {
    int placedNotes = 0,
    Map<int, List<_NoteSlice>>? pendingNotes,
  }) {
    final _SectionRecord record = sections[sectionIndex]!;
    record.blocks.add(block);
    record.texts.add(_blockText(block));
    record.checkpoints.add(
      _Checkpoint(
        pagesLength: flow.pages.length,
        pageIndex: flow.pageIndex,
        columnIndex: flow.columnIndex,
        y: flow.y,
        columnTop: flow.columnTop,
        lines: flow.current.length,
        frames: flow.currentFrames.length,
        adjacentAfter: adjacentAfter,
        paragraphIndex: paragraphIndex,
        wrapFrames: _hasWrapFrames(flow.currentFrames),
        placedNotes: placedNotes,
        pendingNotes: pendingNotes,
      ),
    );
  }

  /// True when the flow before new block [block] of [sectionIndex] is in the
  /// same state as the old layout before the matching old block; records the
  /// splice.
  bool converge(
    int sectionIndex,
    int block,
    _Flow flow,
    int paragraphIndex,
    double? adjacentAfter,
    bool Function(_Checkpoint checkpoint, List<int> oldOrder) notesMatch,
  ) {
    final _Convergence? target = convergence;
    if (target == null || sectionIndex < target.lastDirtySection) {
      return false;
    }
    int oldBlock = block;
    if (sectionIndex == target.lastDirtySection) {
      if (block < target.firstCandidateBlock) return false;
      oldBlock = block - target.blockOffset;
    }
    final _SectionRecord? old = sectionIndex < target.old.sections.length
        ? target.old.sections[sectionIndex]
        : null;
    if (old == null || oldBlock < 0 || oldBlock >= old.checkpoints.length) {
      return false;
    }
    final _Checkpoint cp = old.checkpoints[oldBlock];
    if (flow.pages.length != cp.pagesLength ||
        flow.pageIndex != cp.pageIndex ||
        flow.columnIndex != cp.columnIndex ||
        flow.y != cp.y ||
        flow.columnTop != cp.columnTop ||
        adjacentAfter != cp.adjacentAfter ||
        flow.hasContent != cp.hasContent ||
        // Retained checkpoints address prefix slices on the partial page.
        // Equal vertical flow alone does not preserve those slice lengths
        // (for example, extra lines inside a fixed-height table row).
        flow.current.length != cp.lines ||
        flow.currentFrames.length != cp.frames ||
        cp.wrapFrames ||
        _hasWrapFrames(flow.currentFrames) ||
        !notesMatch(cp, target.old.notes?.placedOrder ?? const <int>[])) {
      return false;
    }
    final List<LaidOutPage> oldPages = target.oldPages;
    final int at = cp.pagesLength;
    if (at < oldPages.length) {
      final LaidOutPage page = oldPages[at];
      final _PageOrigin? origin = page._origin;
      if (origin == null ||
          page.lines.length < cp.lines ||
          origin.bodyFrames < cp.frames ||
          origin.bodyFrames > page.frames.length) {
        return false;
      }
    } else if (flow.hasContent || at != oldPages.length) {
      return false;
    }
    // "First page of its section" (chrome variants) is decided from the
    // section indices of earlier pages; they must agree for reused pages.
    final Set<int> before = <int>{
      for (final LaidOutPage p in flow.pages) p.sectionIndex,
    };
    final Set<int> oldBefore = <int>{
      for (int i = 0; i < at && i < oldPages.length; i++)
        oldPages[i].sectionIndex,
    };
    if (before.length != oldBefore.length || !before.containsAll(oldBefore)) {
      return false;
    }
    splice = _Splice(
      sectionIndex: sectionIndex,
      newBlock: block,
      oldBlock: oldBlock,
      checkpoint: cp,
      delta: paragraphIndex - cp.paragraphIndex,
      lines: List<LaidOutLine>.of(flow.current),
      frames: List<LaidOutBox>.of(flow.currentFrames),
    );
    return true;
  }

  /// The previous layout's lines of unchanged paragraph [block] (new index
  /// [blockIndex] of [sectionIndex]) when they can be translated to the
  /// flow's current height: the block was laid out entirely on one page
  /// without frames, and the flow is on that same page, column and column
  /// top with the same adjacent spacing. Null otherwise.
  List<LaidOutLine>? translationSource(
    int sectionIndex,
    int blockIndex,
    WmlParagraph block,
    _Flow flow,
    double? adjacentAfter,
  ) {
    final _Convergence? target = convergence;
    if (target == null ||
        sectionIndex < target.lastDirtySection ||
        dirtyBlocks.contains(block) ||
        block.properties.pageBreakBefore ||
        block.properties.columnBreakBefore ||
        // Inline breaks are applied after this candidate is selected. A page
        // break that was a no-op on an empty page can now move the paragraph,
        // invalidating the old lines' page indexes and column positions.
        WordLayoutEngine._hasBreak(block, WmlBreakType.page) ||
        WordLayoutEngine._hasBreak(block, WmlBreakType.column)) {
      return null;
    }
    int oldBlock = blockIndex;
    if (sectionIndex == target.lastDirtySection) {
      if (blockIndex < target.firstCandidateBlock) return null;
      oldBlock = blockIndex - target.blockOffset;
    }
    final _SectionRecord? old = sectionIndex < target.old.sections.length
        ? target.old.sections[sectionIndex]
        : null;
    if (old == null ||
        oldBlock < 0 ||
        oldBlock + 1 >= old.checkpoints.length ||
        !identical(old.blocks[oldBlock], block)) {
      return null;
    }
    final _Checkpoint cp = old.checkpoints[oldBlock];
    final _Checkpoint next = old.checkpoints[oldBlock + 1];
    if (next.pagesLength != cp.pagesLength ||
        next.pageIndex != cp.pageIndex ||
        next.columnIndex != cp.columnIndex ||
        next.columnTop != cp.columnTop ||
        next.frames != cp.frames ||
        next.lines <= cp.lines ||
        cp.wrapFrames ||
        next.wrapFrames ||
        flow.pages.length != cp.pagesLength ||
        flow.pageIndex != cp.pageIndex ||
        flow.columnIndex != cp.columnIndex ||
        flow.columnTop != cp.columnTop ||
        adjacentAfter != cp.adjacentAfter ||
        _hasWrapFrames(flow.currentFrames) ||
        cp.pagesLength >= target.oldPages.length) {
      return null;
    }
    final List<LaidOutLine> lines = target.oldPages[cp.pagesLength].lines;
    if (next.lines > lines.length) return null;
    return lines.sublist(cp.lines, next.lines);
  }

  static bool _hasWrapFrames(List<LaidOutBox> frames) => frames.any(
    (LaidOutBox box) =>
        box.frame != null && box.frame!.wrap != WmlFrameWrap.none,
  );
}

/// A paragraph's line breaks with the environment they were made for. The
/// paragraph's own content (text, run and paragraph properties) is not part
/// of the key: entries are read only for blocks an incremental layout proved
/// unchanged since the previous layout. Dirty blocks and full layouts discard
/// old entries before shaping, including empty and frame-wrapping paths that
/// do not produce replacement cache entries.
class _BreakCache {
  _BreakCache(
    this.lines, {
    required this.maxWidth,
    required this.allowBreak,
    required WmlDocument? document,
  }) : autoHyphenation = document?.autoHyphenation,
       proofingLanguage = document?.proofingLanguage;

  final List<BrokenLine> lines;
  final double maxWidth;
  final bool allowBreak;
  final bool? autoHyphenation;
  final String? proofingLanguage;

  bool matches({
    required double maxWidth,
    required bool allowBreak,
    required WmlDocument? document,
  }) =>
      this.maxWidth == maxWidth &&
      this.allowBreak == allowBreak &&
      autoHyphenation == document?.autoHyphenation &&
      proofingLanguage == document?.proofingLanguage;
}

/// Paragraph text of a block, as compared between layouts.
String _blockText(WmlBlock block) {
  if (block is WmlParagraph) return block.text;
  final List<WmlParagraph> paragraphs = WordTree.paragraphs(<WmlBlock>[
    block,
  ]).toList();
  if (paragraphs.isEmpty) return '';
  if (paragraphs.length == 1) return paragraphs.first.text;
  return paragraphs.map((WmlParagraph p) => p.text).join('\u0000');
}

bool _blockContainsAny(WmlBlock block, Set<WmlParagraph> paragraphs) {
  if (paragraphs.isEmpty) return false;
  if (block is WmlParagraph) return paragraphs.contains(block);
  for (final WmlParagraph p in WordTree.paragraphs(<WmlBlock>[block])) {
    if (paragraphs.contains(p)) return true;
  }
  return false;
}

/// Shifts body paragraph indices of reused lines and flow boxes.
void _shiftParagraphIndices(
  Iterable<LaidOutLine> lines,
  Iterable<LaidOutBox> frames,
  int delta,
) {
  if (delta == 0) return;
  for (final LaidOutLine line in lines) {
    line.paragraphIndex += delta;
  }
  for (final LaidOutBox box in frames) {
    // TOC entry boxes carry their heading's model index and line-number
    // boxes their line number; neither follows the body counter.
    if (box.kind == LaidOutBoxKind.tocEntry ||
        box.kind == LaidOutBoxKind.lineNumber) {
      continue;
    }
    final int? start = box.paragraphIndex;
    final int? end = box.paragraphEnd;
    if (start != null) box.paragraphIndex = start + delta;
    if (end != null) box.paragraphEnd = end + delta;
  }
}

/// Counters for tests and benchmarks.
class WordIncrementalLayoutStats {
  WordIncrementalLayoutStats._();

  /// Local edits laid out incrementally.
  static int incremental = 0;

  /// Of those, layouts that met the old flow and reused its tail.
  static int converged = 0;

  /// Local edits that fell back to the ordinary path.
  static int fallbacks = 0;

  /// Top-level blocks laid out by incremental layouts.
  static int blocksLaidOut = 0;

  /// Paragraph line breaks reused from the previous layout.
  static int breaksReused = 0;

  /// Unchanged paragraphs placed by translating their previous lines.
  static int blocksTranslated = 0;

  static void reset() {
    incremental = 0;
    converged = 0;
    fallbacks = 0;
    blocksLaidOut = 0;
    breaksReused = 0;
    blocksTranslated = 0;
  }
}

String _link(WmlHyperlink? link) =>
    link == null ? '-' : '${link.anchor}|${link.url}|${link.file}';

/// A canonical text form of a layout, for comparing two layouts of the same
/// document (line boxes, glyph positions, page assignment, boxes, chrome).
/// Model objects are named by identity where layout refers to the document's
/// own objects (source paragraphs, tables, frames) and by value where layout
/// may create them afresh (links, note-story content, visuals).
String wordLayoutFingerprint(LaidOutDocument document) {
  final StringBuffer out = StringBuffer()
    ..writeln('pageSize ${document.pageSize.width} ${document.pageSize.height}')
    ..writeln('pages ${document.pages.length}');
  void line(String tag, LaidOutLine l) {
    out
      ..write(tag)
      ..write(' x=${l.x} y=${l.y} w=${l.width} h=${l.height}')
      ..write(' page=${l.pageIndex} para=${l.paragraphIndex}')
      ..write(' just=${l.justification.name} ratio=${l.justificationRatio}')
      ..write(' start=${l.isParagraphStart} footer=${l.isFooter}')
      ..write(' list=${l.listLabel} marker=${l.listMarkerX}')
      ..write(' box=${l.boxX}/${l.boxWidth}')
      ..write(' overlay=${l.overlayText}/${l.overlayColor}')
      ..write('/${l.overlaySize}/${l.overlayBold}')
      ..write(' toc=${l.tocTargetParagraph}/${l.tocLeader}')
      ..write(' src=${l.sourceText}')
      ..write(' srcPara=${identityHashCode(l.sourceParagraph)}')
      ..write(' link=${_link(l.hyperlink)}')
      ..writeln(' proof=${l.proofingOffsets}');
    for (final LaidOutGlyph g in l.glyphs) {
      out
        ..write('  g cp=${g.glyph.codePoint} id=${g.glyph.glyphId}')
        ..write(' li=${g.glyph.logicalIndex} lv=${g.glyph.level}')
        ..write(' x=${g.x} y=${g.y} adv=${g.advance}')
        ..write(' pd=${g.paintDx}/${g.paintDy} size=${g.fontSize}')
        ..write(' b=${g.bold} i=${g.italic} u=${g.underline.name}')
        ..write(' s=${g.strike} k=${g.kerning} c=${g.color}')
        ..write(' hl=${g.highlight} f=${g.fontFamily}')
        ..write(' va=${g.vertAlign.name} pos=${g.positionHalfPoints}')
        ..write(' disp=${g.displayText}')
        ..write('/${g.displayOffset}/${g.sourceEnd}/${g.actualText}')
        ..write(' link=${_link(g.hyperlink)}')
        ..writeln(' cm=${g.commentIds}');
    }
  }

  for (final LaidOutPage page in document.pages) {
    out
      ..write('page ${page.index} section=${page.sectionIndex}')
      ..write(' ${page.width}x${page.height}')
      ..write(' hb=${page.headerBand.top}/${page.headerBand.height}')
      ..writeln(' fb=${page.footerBand.top}/${page.footerBand.height}');
    for (final LaidOutLine l in page.lines) {
      line('line', l);
    }
    for (final LaidOutLine l in page.header) {
      line('header', l);
    }
    for (final LaidOutLine l in page.footer) {
      line('footer', l);
    }
    for (final LaidOutLine l in page.notes) {
      line('note', l);
    }
    for (final LaidOutBox b in page.frames) {
      out
        ..write('box ${b.kind.name} x=${b.x} y=${b.y}')
        ..write(' w=${b.width} h=${b.height}')
        ..write(' para=${b.paragraphIndex}/${b.paragraphEnd}')
        ..write(' fill=${b.fillColor} stroke=${b.strokeColor}')
        ..write(' sw=${b.strokeWidth}')
        ..write(' edges=${b.strokeTop}${b.strokeRight}')
        ..write('${b.strokeBottom}${b.strokeLeft}')
        ..write(' cell=${b.tableRow}/${b.tableCol}/${b.tableGridCol}')
        ..write(
          ' table=${b.isNoteContent ? b.table != null : identityHashCode(b.table)}',
        )
        ..write(' visual=${b.visual?.kind.name}/${b.visual?.title}')
        ..write('/${b.visual?.width}/${b.visual?.height}')
        ..write(
          ' eq=${b.isNoteContent ? b.equation != null : identityHashCode(b.equation)}',
        )
        ..write(
          ' frame=${b.isNoteContent ? b.frame != null : identityHashCode(b.frame)}',
        )
        ..writeln(' note=${b.isNoteContent}');
    }
  }
  return out.toString();
}
