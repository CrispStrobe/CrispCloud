part of 'word_layout.dart';

/// A shaped note story in local coordinates. Cut points never split a text
/// line or picture; table borders are clipped at a continuation boundary.
class _NoteStory {
  _NoteStory(this.lines, this.frames, this.height);
  final List<LaidOutLine> lines;
  final List<LaidOutBox> frames;
  final double height;

  factory _NoteStory.shape(
    WmlNote note,
    WmlSection section,
    WordLayoutEngine owner,
  ) {
    final List<WmlBlock> blocks = note.blocks.map(WmlClone.block).toList();
    final originals = WordTree.paragraphs(note.blocks).toList();
    final copies = WordTree.paragraphs(blocks).toList();
    final originalOf = <WmlParagraph, WmlParagraph>{
      for (var i = 0; i < copies.length; i++) copies[i]: originals[i],
    };
    final offsetsOf = <WmlParagraph, List<int?>>{};
    final label = owner._noteNumbering?.labelFor(note) ?? '${note.id}';
    var hasMarker = false;
    for (final paragraph in blocks.expand(WmlClone.paragraphsOf)) {
      final offsets = <int?>[];
      var sourceOffset = 0;
      for (final inline in paragraph.inlines) {
        if (inline is WmlNoteMarker) {
          offsets.addAll(List<int?>.filled(label.length, null));
        } else if (inline is WmlRun) {
          for (var j = 0; j < inline.text.length; j++) {
            offsets.add(sourceOffset++);
          }
        }
      }
      offsets.add(sourceOffset);
      offsetsOf[paragraph] = offsets;
      for (var i = 0; i < paragraph.inlines.length; i++) {
        final inline = paragraph.inlines[i];
        if (inline is WmlNoteMarker) {
          hasMarker = true;
          paragraph.inlines[i] = WmlRun(
            text: label,
            properties: inline.properties.copy(),
          );
        }
      }
    }
    if (note.addReference && !hasMarker) {
      if (blocks.isEmpty || blocks.first is! WmlParagraph) {
        blocks.insert(0, WmlParagraph());
      }
      final WmlParagraph first = blocks.first as WmlParagraph;
      final bool separator =
          label.isNotEmpty &&
          note.addReferenceSpace &&
          (first.text.isEmpty || !RegExp(r'^\s').hasMatch(first.text));
      final map = offsetsOf.putIfAbsent(first, () => <int?>[0]);
      map.insertAll(
        0,
        List<int?>.filled(label.length + (separator ? 1 : 0), null),
      );
      first.inlines.insertAll(0, [
        WmlRun(
          text: label,
          properties: WmlRunProps(
            styleId: note.endnote ? 'EndnoteReference' : 'FootnoteReference',
            vertAlign: WmlVertAlign.superscript,
          ),
        ),
        if (separator) WmlRun(text: ' '),
      ]);
    }
    // Make oversized drawings fit a continuation page without clipping.
    final WmlDocument story = WmlDocument(
      proofingLanguage: owner._layoutDoc?.proofingLanguage,
      autoHyphenation: owner._layoutDoc?.autoHyphenation ?? false,
      sections: <WmlSection>[
        WmlSection(
          blocks: blocks,
          pageSize: WmlPageSize(width: section.contentWidth, height: 10000000),
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
    for (final WmlVisual visual in story.visuals) {
      final double scale = math.min(
        1,
        math.min(
          section.contentWidth / math.max(1, visual.visual.width),
          (section.contentHeight - 48) / math.max(1, visual.visual.height),
        ),
      );
      visual.visual.width *= scale;
      visual.visual.height *= scale;
    }
    final storyEngine = WordLayoutEngine(
      font: owner.font,
      fonts: owner.fonts,
      measure: owner.measure,
      measureRun: owner.measureRun,
      measureFont: owner.measureFont,
      fallbackWidthFactor: owner.fallbackWidthFactor,
    ).._containedPhysicalSection = section;
    final LaidOutDocument laid = storyEngine.layout(story, updateFields: false);
    final List<WmlParagraph> paragraphs = story.paragraphs.toList();
    final List<LaidOutLine> lines = <LaidOutLine>[];
    final List<LaidOutBox> frames = <LaidOutBox>[];
    var height = 0.0;
    // Explicit page breaks in a note are just continuation boundaries.
    for (final LaidOutPage page in laid.pages) {
      var bottom = 0.0;
      for (final LaidOutLine line in page.lines) {
        final String source =
            line.sourceText ?? paragraphs[line.paragraphIndex].text;
        final cloned = line.sourceParagraph ?? paragraphs[line.paragraphIndex];
        lines.add(
          _noteLine(
            line,
            0,
            height,
            0,
            source,
            sourceParagraph: originalOf[cloned],
            proofingOffsets: offsetsOf[cloned],
          ),
        );
        bottom = math.max(bottom, line.y + line.height);
      }
      for (final LaidOutBox box in page.frames) {
        frames.add(_noteBox(box, 0, height, 0, double.infinity));
        bottom = math.max(bottom, box.y + box.height);
      }
      height += bottom;
    }
    return _NoteStory(lines, frames, math.max(height, 14));
  }

  double cut(double start, double available) {
    final double limit = math.min(height, start + available);
    final List<double> candidates = <double>[
      height,
      for (final LaidOutLine line in lines) line.y + line.height,
      for (final LaidOutBox box in frames) box.y + box.height,
    ]..sort();
    var best = start;
    for (final double end in candidates) {
      if (end <= start + 0.01 || end > limit + 0.01) continue;
      if (lines.any(
        (LaidOutLine l) => l.y < end - 0.01 && l.y + l.height > end + 0.01,
      )) {
        continue;
      }
      if (frames.any(
        (LaidOutBox b) =>
            b.visual != null && b.y < end - 0.01 && b.y + b.height > end + 0.01,
      )) {
        continue;
      }
      best = end;
    }
    return best;
  }

  double get firstHeight {
    final List<double> ends = <double>[
      height,
      for (final LaidOutLine l in lines) l.y + l.height,
      for (final LaidOutBox b in frames) b.y + b.height,
    ]..sort();
    for (final double end in ends) {
      if (cut(0, end) > 0) return end;
    }
    return height;
  }
}

class _NoteSlice {
  _NoteSlice(this.story, this.start, this.end, this.section, this.sectionIndex);
  final _NoteStory story;
  final double start, end;
  final WmlSection section;
  final int sectionIndex;
  double get height => end - start;

  void paintInto(LaidOutPage page, double y) {
    final double dx = section.margins.left;
    final double dy = y - start;
    for (final LaidOutLine line in story.lines) {
      if (line.y < start - 0.01 || line.y + line.height > end + 0.01) continue;
      page.notes.add(_noteLine(line, dx, dy, page.index, line.sourceText!));
    }
    for (final LaidOutBox frame in story.frames) {
      if (!_noteBoxOverlaps(frame, start, end)) continue;
      page.frames.add(_noteBox(frame, dx, dy, start, end));
    }
  }
}

LaidOutLine _noteLine(
  LaidOutLine line,
  double dx,
  double dy,
  int page,
  String source, {
  int paragraphIndex = -1,
  WmlParagraph? sourceParagraph,
  List<int?>? proofingOffsets,
}) => LaidOutLine(
  glyphs: <LaidOutGlyph>[
    for (final LaidOutGlyph g in line.glyphs)
      LaidOutGlyph(
        glyph: g.glyph,
        displayText: g.displayText,
        displayOffset: g.displayOffset,
        sourceEnd: g.sourceEnd,
        actualText: g.actualText,
        x: g.x + dx,
        y: g.y + dy,
        color: g.color,
        fontSize: g.fontSize,
        bold: g.bold,
        underline: g.underline,
        italic: g.italic,
        kerning: g.kerning,
        strike: g.strike,
        highlight: g.highlight,
        fontFamily: g.fontFamily,
        vertAlign: g.vertAlign,
        hyperlink: g.hyperlink,
        commentIds: g.commentIds,
        advance: g.advance,
        paintDx: g.paintDx,
        paintDy: g.paintDy,
      ),
  ],
  x: line.x + dx,
  y: line.y + dy,
  width: line.width,
  height: line.height,
  pageIndex: page,
  paragraphIndex: paragraphIndex,
  justification: line.justification,
  listLabel: line.listLabel,
  listMarkerX: line.listMarkerX + dx,
  isParagraphStart: line.isParagraphStart,
  isFooter: line.isFooter,
  overlayText: line.overlayText,
  overlayColor: line.overlayColor,
  overlaySize: line.overlaySize,
  overlayBold: line.overlayBold,
  tocTargetParagraph: line.tocTargetParagraph,
  tocLeader: line.tocLeader,
  hyperlink: line.hyperlink,
  sourceText: source,
  sourceParagraph: sourceParagraph ?? line.sourceParagraph,
  proofingOffsets: proofingOffsets ?? line.proofingOffsets,
  boxX: line.boxX + dx,
  boxWidth: line.boxWidth,
  justificationRatio: line.justificationRatio,
);

bool _noteBoxOverlaps(LaidOutBox box, double start, double end) {
  if (box.height > 0 && box.y + box.height > start && box.y < end) return true;
  final row = box.tableRowGeometry;
  // Hidden merge continuations retain physical rows for selection handles.
  return row != null &&
      row.height > 0 &&
      row.y + row.height > start &&
      row.y < end;
}

LaidOutBox _noteBox(
  LaidOutBox b,
  double dx,
  double dy,
  double start,
  double end, {
  bool isNoteContent = true,
}) {
  final double top = math.max(start, b.y);
  final double bottom = math.min(end, b.y + b.height);
  final row = b.tableRowGeometry;
  final rowTop = row == null ? 0.0 : math.max(start, row.y);
  final rowBottom = row == null ? 0.0 : math.min(end, row.y + row.height);
  return LaidOutBox(
    x: b.x + dx,
    y: top + dy,
    width: b.width,
    height: math.max(0, bottom - top),
    fillColor: b.fillColor,
    strokeColor: b.strokeColor,
    strokeWidth: b.strokeWidth,
    kind: b.kind,
    visual: b.visual,
    equation: b.equation,
    omml: b.omml,
    table: b.table,
    tableRow: b.tableRow,
    tableCol: b.tableCol,
    tableGridCol: b.tableGridCol,
    // Keep a zero-height record when this visible merge fragment has no
    // physical origin row in the slice. Falling back to its master tableRow
    // would invent that earlier row on a later note or tall-row page.
    tableRowGeometry: row == null
        ? null
        : (
            row: row.row,
            y: rowTop + dy,
            height: math.max(0, rowBottom - rowTop),
          ),
    frame: b.frame,
    strokeTop: b.strokeTop && b.y >= start,
    strokeBottom: b.strokeBottom && b.y + b.height <= end,
    strokeLeft: b.strokeLeft,
    strokeRight: b.strokeRight,
    paragraphIndex: b.paragraphIndex,
    paragraphEnd: b.paragraphEnd,
    isNoteContent: isNoteContent,
  );
}
