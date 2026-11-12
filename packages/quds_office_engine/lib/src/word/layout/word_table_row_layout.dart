part of 'word_layout.dart';

// A row taller than a page cannot be kept as an indivisible paragraph. Shape
// its cells once, then slice at complete line boundaries. Note references are
// collected from each actual slice, so a late reference cannot place its note
// on an earlier page of the same row.
({double y, int pageIndex}) _layoutTallTableRow(
  WordLayoutEngine owner,
  WmlTable table,
  int rowIndex,
  List<double> columns,
  WmlSection section,
  List<LaidOutPage> pages,
  List<LaidOutLine> current,
  List<LaidOutBox> currentFrames,
  int pageIndex,
  double y,
  int paragraphIndex,
  double x,
  double width,
  int sectionIndex,
) {
  final rowTable = WmlTable(
    grid: columns,
    rows: [table.rows[rowIndex]],
    properties: table.properties,
  );
  final storyDocument = WmlDocument(
    sections: [
      WmlSection(
        blocks: [rowTable],
        pageSize: WmlPageSize(width: width, height: 10000000),
        margins: const WmlPageMargins(
          top: 0,
          bottom: 0,
          left: 0,
          right: 0,
          header: 0,
          footer: 0,
        ),
      ),
    ],
  );
  final deferredFrames = <WmlFrame, ({double y, int paragraphIndex})>{};
  final deferredVisuals = <WmlVisual, double>{};
  final rowEngine =
      WordLayoutEngine(
          font: owner.font,
          fonts: owner.fonts,
          measure: owner.measure,
          fallbackWidthFactor: owner.fallbackWidthFactor,
        )
        .._deferredContainedFrames = deferredFrames
        .._deferredContainedVisuals = deferredVisuals
        .._containedPhysicalSection = owner._containedPhysicalSection ?? section
        .._containedTableDepth = math.max(0, owner._containedTableDepth - 1);
  final laid = rowEngine.layout(storyDocument, updateFields: false);
  final paragraphs = storyDocument.paragraphs.toList();
  final lines = laid.pages.single.lines;
  final frames = laid.pages.single.frames;
  final top = frames.map((f) => f.y).reduce(math.min);
  final bottom = frames.map((f) => f.y + f.height).reduce(math.max);
  final story = _NoteStory(lines, frames, bottom);
  var start = top;
  var cursor = y;
  var page = pageIndex;
  final emittedFrames = <WmlFrame>{};
  final emittedVisuals = <WmlVisual>{};

  bool anchorInSlice(double anchor, double end) =>
      anchor >= start - 0.01 &&
      (anchor < end - 0.01 || (end >= bottom - 0.01 && anchor <= end + 0.01));

  Iterable<MapEntry<WmlFrame, ({double y, int paragraphIndex})>> framesThrough(
    double end,
  ) => deferredFrames.entries.where((entry) {
    final anchor = entry.value.y;
    // A boundary anchor belongs to the following slice. The final boundary
    // stays on the last page, including a frame after the last text block.
    return !emittedFrames.contains(entry.key) && anchorInSlice(anchor, end);
  });

  Iterable<MapEntry<WmlVisual, double>> visualsThrough(double end) =>
      deferredVisuals.entries.where(
        (entry) =>
            !emittedVisuals.contains(entry.key) &&
            anchorInSlice(entry.value, end),
      );

  Set<int> notesThrough(double end) => {
    for (final line in lines)
      if (line.y >= start - 0.01 && line.y + line.height <= end + 0.01)
        ...owner._noteIds(
          paragraphs[line.paragraphIndex],
          line.glyphs.map((g) => g.glyph.logicalIndex),
        ),
    for (final entry in framesThrough(end))
      for (final paragraph in WordTree.paragraphs(entry.key.blocks))
        for (final run in paragraph.inlines.whereType<WmlRun>())
          if (run.noteRefId != null && !run.noteRefEndnote) run.noteRefId!,
  };

  void nextPage() {
    pages.add(
      owner._makePage(
        section,
        page,
        current,
        currentFrames,
        sectionIndex: sectionIndex,
        firstInSection: false,
      ),
    );
    current.clear();
    currentFrames.clear();
    page++;
    cursor = owner._tablePageTop(section);
  }

  while (start < bottom - 0.01) {
    final available = owner._bodyBottom(section, page) - cursor;
    var end = story.cut(start, available);
    var ids = notesThrough(end);
    while (end > start + 0.01) {
      final minimum = owner._minimumNotes(ids, section, page);
      if (end - start + minimum <= available + 0.01) break;
      end = story.cut(start, available - minimum);
      ids = notesThrough(end);
    }
    if (end <= start + 0.01) {
      if (current.isEmpty &&
          currentFrames.isEmpty &&
          owner._noteReserve(page) == 0 &&
          cursor <= owner._tablePageTop(section) + 0.01) {
        throw StateError('A table line and its note cannot fit the page');
      }
      nextPage();
      continue;
    }
    owner._reserveNotes(ids, section, page, cursor + end - start);
    for (final line in lines) {
      if (line.y < start - 0.01 || line.y + line.height > end + 0.01) continue;
      current.add(
        _noteLine(
          line,
          x,
          cursor - start,
          page,
          paragraphs[line.paragraphIndex].text,
          paragraphIndex: paragraphIndex + line.paragraphIndex,
        ),
      );
    }
    for (final frame in frames) {
      if (frame.y + frame.height <= start || frame.y >= end) continue;
      final copy = _noteBox(
        frame,
        x,
        cursor - start,
        start,
        end,
        isNoteContent: false,
      );
      // TOC hit boxes point at the global heading, not a paragraph owned by
      // the temporary row document. Only source-paragraph indices need the
      // row's offset when its shaped content returns to the body flow.
      if (copy.paragraphIndex != null && copy.kind != LaidOutBoxKind.tocEntry) {
        copy.paragraphIndex = copy.paragraphIndex! + paragraphIndex;
      }
      if (copy.paragraphEnd != null) {
        copy.paragraphEnd = copy.paragraphEnd! + paragraphIndex;
      }
      if (copy.table == rowTable) {
        copy.table = table;
        copy.tableRow = rowIndex;
      }
      currentFrames.add(copy);
    }
    // Anchored frames retain page/margin coordinates. Paint them as complete
    // objects on their source anchor's page, never as clipped row fragments.
    for (final entry in framesThrough(end)) {
      owner._layoutFrameContents(
        entry.key,
        section,
        pages,
        current,
        currentFrames,
        page,
        paragraphIndex + entry.value.paragraphIndex,
      );
      emittedFrames.add(entry.key);
    }
    for (final entry in visualsThrough(end)) {
      owner._layoutVisual(
        entry.key.visual,
        section,
        pages,
        current,
        currentFrames,
        page,
        cursor,
        allowBreak: false,
      );
      emittedVisuals.add(entry.key);
    }
    cursor += end - start;
    start = end;
    if (start < bottom - 0.01) nextPage();
  }
  return (y: cursor, pageIndex: page);
}
