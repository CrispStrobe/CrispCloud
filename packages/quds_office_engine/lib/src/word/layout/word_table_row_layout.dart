part of 'word_layout.dart';

class _TallCellContent {
  _TallCellContent(
    this.lines,
    this.frames,
    this.frameAnchors,
    this.visualAnchors,
    this.bottom,
  );
  final List<LaidOutLine> lines;
  final List<LaidOutBox> frames;
  final List<MapEntry<WmlFrame, ({double y, int paragraphIndex})>> frameAnchors;
  final List<MapEntry<WmlVisual, double>> visualAnchors;
  final double bottom;

  // Walk backward through indivisible content to find the greatest safe
  // boundary. Space between paragraphs is a legal boundary, too.
  late final _unsplittable = <(double, double)>[
    for (final line in lines) (line.y, line.y + line.height),
    for (final frame in frames)
      if (frame.visual != null || frame.equation != null)
        (frame.y, frame.y + frame.height),
  ]..sort((a, b) => b.$1.compareTo(a.$1));

  double cut(double start, double available) {
    var end = math.min(bottom, start + available);
    for (final (top, bottom) in _unsplittable) {
      if (top < end - 0.01 && bottom > end + 0.01) {
        end = top;
        if (end <= start + 0.01) return start;
      }
    }
    return math.max(start, end);
  }
}

typedef _TallCellSlice = ({_TallCellContent content, double start, double end});

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
    proofingLanguage: owner._layoutDoc?.proofingLanguage,
    autoHyphenation: owner._layoutDoc?.autoHyphenation ?? false,
    sourceNoSpaceRaiseLower: owner._layoutDoc?.sourceNoSpaceRaiseLower ?? false,
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
  final cells = <_TallCellContent>[];
  final rowEngine =
      WordLayoutEngine(
          font: owner.font,
          fonts: owner.fonts,
          measure: owner.measure,
          measureRun: owner.measureRun,
          measureFont: owner.measureFont,
          fallbackWidthFactor: owner.fallbackWidthFactor,
        )
        .._deferredContainedFrames = deferredFrames
        .._deferredContainedVisuals = deferredVisuals
        .._captureTallCells = (table: rowTable, cells: cells)
        .._inheritedNoteNumbering = owner._noteNumbering
        .._containedPhysicalSection = owner._containedPhysicalSection ?? section
        .._containedTableDepth = math.max(0, owner._containedTableDepth - 1)
        // The temporary table adds its own margin while shaping. Retain only
        // its ancestors here, just as for the inherited nesting depth.
        .._containedVerticalInsets =
            owner._containedVerticalInsets -
            table.properties.cellInsets.vertical;
  final laid = rowEngine.layout(storyDocument, updateFields: false);
  final paragraphs = storyDocument.paragraphs.toList();
  final lines = laid.pages.single.lines;
  final frames = laid.pages.single.frames;
  final top = frames.map((f) => f.y).reduce(math.min);
  final bottom = frames.map((f) => f.y + f.height).reduce(math.max);
  final story = _NoteStory(lines, frames, bottom);
  final wholeRow = _TallCellContent(
    lines,
    frames,
    deferredFrames.entries.toList(),
    deferredVisuals.entries.toList(),
    bottom,
  );
  final outerFrames = frames.where((frame) => frame.table == rowTable).toList();
  // Keep aligned line positions when all cells share a legal cut. When
  // staggered baselines make that impossible, each cell keeps its own offset.
  var independent = false;
  var sources = [wholeRow];
  var starts = [top];
  var cursor = y;
  var page = pageIndex;
  final emittedFrames = <WmlFrame>{};
  final emittedVisuals = <WmlVisual>{};

  List<_TallCellSlice> slicesFor(double available) => [
    for (var c = 0; c < sources.length; c++)
      (
        content: sources[c],
        start: starts[c],
        end: independent
            ? sources[c].cut(starts[c], available)
            : story.cut(starts[c], available),
      ),
  ];

  double sliceHeight(List<_TallCellSlice> slices) => slices.fold<double>(
    0,
    (height, slice) => math.max(height, slice.end - slice.start),
  );

  bool containsAnchor(double anchor, _TallCellSlice slice) =>
      anchor >= slice.start - 0.01 &&
      (anchor < slice.end - 0.01 ||
          (slice.end >= slice.content.bottom - 0.01 &&
              anchor <= slice.end + 0.01));

  Iterable<LaidOutLine> linesThrough(_TallCellSlice slice) =>
      slice.content.lines.where(
        (line) =>
            line.y >= slice.start - 0.01 &&
            line.y + line.height <= slice.end + 0.01,
      );

  Iterable<MapEntry<WmlFrame, ({double y, int paragraphIndex})>> framesThrough(
    _TallCellSlice slice,
  ) => slice.content.frameAnchors.where(
    (entry) =>
        !emittedFrames.contains(entry.key) &&
        containsAnchor(entry.value.y, slice),
  );

  Iterable<MapEntry<WmlVisual, double>> visualsThrough(_TallCellSlice slice) =>
      slice.content.visualAnchors.where(
        (entry) =>
            !emittedVisuals.contains(entry.key) &&
            containsAnchor(entry.value, slice),
      );

  Set<int> notesThrough(List<_TallCellSlice> slices) => {
    for (final slice in slices) ...{
      for (final line in linesThrough(slice))
        ...owner._noteIds(
          paragraphs[line.paragraphIndex],
          line.glyphs.map((g) => g.glyph.logicalIndex),
        ),
      for (final entry in framesThrough(slice))
        for (final paragraph in WordTree.paragraphs(entry.key.blocks))
          for (final run in paragraph.inlines.whereType<WmlRun>())
            if (run.noteRefId != null && !run.noteRefEndnote) run.noteRefId!,
    },
  };

  void addBox(LaidOutBox copy) {
    // TOC hit boxes point at the global heading. Only source-paragraph
    // indices need the row offset when its shaped content returns to the body.
    if (copy.paragraphIndex != null && copy.kind != LaidOutBoxKind.tocEntry) {
      copy.paragraphIndex = copy.paragraphIndex! + paragraphIndex;
    }
    if (copy.paragraphEnd != null) {
      copy.paragraphEnd = copy.paragraphEnd! + paragraphIndex;
    }
    if (copy.table == rowTable) {
      copy.table = table;
      copy.tableRow = rowIndex;
      final geometry = copy.tableRowGeometry;
      if (geometry != null) {
        copy.tableRowGeometry = (
          row: rowIndex,
          y: geometry.y,
          height: geometry.height,
        );
      }
    }
    currentFrames.add(copy);
  }

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

  bool hasRemaining() => Iterable<int>.generate(
    sources.length,
  ).any((i) => starts[i] < sources[i].bottom - 0.01);

  while (hasRemaining()) {
    final available = owner._bodyBottom(section, page) - cursor;
    var slices = slicesFor(available);
    var ids = notesThrough(slices);
    var height = sliceHeight(slices);
    while (height > 0.01) {
      final minimum = owner._minimumNotes(ids, section, page);
      if (height + minimum <= available + 0.01) break;
      slices = slicesFor(available - minimum);
      ids = notesThrough(slices);
      height = sliceHeight(slices);
    }

    if (height <= 0.01) {
      if (current.isEmpty &&
          currentFrames.isEmpty &&
          owner._noteReserve(page) == 0 &&
          cursor <= owner._tablePageTop(section) + 0.01) {
        if (independent || cells.isEmpty) {
          throw StateError('A table line and its note cannot fit the page');
        }
        final start = starts.single;
        // The source table's explicit minimum row height can extend below
        // its cell content. Retain that space in one continuation lane.
        var tallest = 0;
        for (var c = 1; c < cells.length; c++) {
          if (cells[c].bottom > cells[tallest].bottom) tallest = c;
        }
        final cell = cells[tallest];
        cells[tallest] = _TallCellContent(
          cell.lines,
          cell.frames,
          cell.frameAnchors,
          cell.visualAnchors,
          bottom,
        );
        sources = cells;
        starts = [for (final cell in cells) math.min(start, cell.bottom)];
        independent = true;
        continue;
      }
      nextPage();
      continue;
    }

    owner._reserveNotes(ids, section, page, cursor + height);
    if (independent) {
      // Outer cell fills and borders share one physical row height even when
      // their text and nested table content use different offsets.
      final first = starts.every((start) => start <= top + 0.01);
      final last = slices.every(
        (slice) => slice.end >= slice.content.bottom - 0.01,
      );
      for (final frame in outerFrames) {
        final copy = _noteBox(
          frame,
          x,
          cursor - top,
          top,
          bottom,
          isNoteContent: false,
        );
        copy.height = height;
        copy.strokeTop = copy.strokeTop && first;
        copy.strokeBottom = copy.strokeBottom && last;
        if (copy.tableRowGeometry case final geometry?) {
          copy.tableRowGeometry = (
            row: geometry.row,
            y: cursor,
            height: height,
          );
        }
        addBox(copy);
      }
    }

    for (final slice in slices) {
      if (slice.end > slice.start + 0.01) {
        final dy = cursor - slice.start;
        for (final line in linesThrough(slice)) {
          current.add(
            _noteLine(
              line,
              x,
              dy,
              page,
              paragraphs[line.paragraphIndex].text,
              paragraphIndex: paragraphIndex + line.paragraphIndex,
            ),
          );
        }
        for (final frame in slice.content.frames) {
          if (!_noteBoxOverlaps(frame, slice.start, slice.end)) continue;
          addBox(
            _noteBox(
              frame,
              x,
              dy,
              slice.start,
              slice.end,
              isNoteContent: false,
            ),
          );
        }
      }
      // Anchored frames retain their page or margin placement and paint
      // only on the page carrying their original anchor.
      for (final entry in framesThrough(slice)) {
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
      for (final entry in visualsThrough(slice)) {
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
    }
    cursor += height;
    starts = [for (final slice in slices) slice.end];
    if (hasRemaining()) nextPage();
  }
  return (y: cursor, pageIndex: page);
}
