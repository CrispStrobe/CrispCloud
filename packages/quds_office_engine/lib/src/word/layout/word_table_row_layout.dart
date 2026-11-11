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
  final laid = WordLayoutEngine(
    font: owner.font,
    fonts: owner.fonts,
    measure: owner.measure,
    fallbackWidthFactor: owner.fallbackWidthFactor,
  ).layout(storyDocument, updateFields: false);
  final paragraphs = storyDocument.paragraphs.toList();
  final lines = laid.pages.single.lines;
  final frames = laid.pages.single.frames;
  final top = frames.map((f) => f.y).reduce(math.min);
  final bottom = frames.map((f) => f.y + f.height).reduce(math.max);
  final story = _NoteStory(lines, frames, bottom);
  var start = top;
  var cursor = y;
  var page = pageIndex;

  Set<int> notesThrough(double end) => {
    for (final line in lines)
      if (line.y >= start - 0.01 && line.y + line.height <= end + 0.01)
        ...owner._noteIds(
          paragraphs[line.paragraphIndex],
          line.glyphs.map((g) => g.glyph.logicalIndex),
        ),
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
      if (copy.paragraphIndex != null) {
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
    cursor += end - start;
    start = end;
    if (start < bottom - 0.01) nextPage();
  }
  return (y: cursor, pageIndex: page);
}
