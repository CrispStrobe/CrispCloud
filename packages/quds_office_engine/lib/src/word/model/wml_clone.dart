import 'wml_document.dart';
import 'wml_run_edit.dart';
import 'word_bookmarks.dart';
import 'word_content_controls.dart';
import 'word_tree.dart';

/// Deep copies of Word blocks so cut / paste / undo never share mutable state.
abstract final class WmlClone {
  /// Copies the section's blocks, stories and page settings for undo or split.
  static WmlSection section(WmlSection source) => WmlSection(
    blocks: <WmlBlock>[for (final WmlBlock item in source.blocks) block(item)],
    pageSize: source.pageSize,
    margins: source.margins,
    columnCount: source.columnCount,
    columnSpace: source.columnSpace,
    columnSep: source.columnSep,
    breakKind: source.breakKind,
    differentFirstPage: source.differentFirstPage,
    differentOddEven: source.differentOddEven,
    linkToPrevious: source.linkToPrevious,
    lineNumbers: source.lineNumbers,
    sourceProperties: source.sourceProperties,
    header: <WmlParagraph>[for (final p in source.header) paragraph(p)],
    footer: <WmlParagraph>[for (final p in source.footer) paragraph(p)],
    firstHeader: <WmlParagraph>[
      for (final p in source.firstHeader) paragraph(p),
    ],
    firstFooter: <WmlParagraph>[
      for (final p in source.firstFooter) paragraph(p),
    ],
    evenHeader: <WmlParagraph>[for (final p in source.evenHeader) paragraph(p)],
    evenFooter: <WmlParagraph>[for (final p in source.evenFooter) paragraph(p)],
    headerVisuals: <WmlVisual>[for (final v in source.headerVisuals) visual(v)],
    footerVisuals: <WmlVisual>[for (final v in source.footerVisuals) visual(v)],
    firstHeaderVisuals: <WmlVisual>[
      for (final v in source.firstHeaderVisuals) visual(v),
    ],
    firstFooterVisuals: <WmlVisual>[
      for (final v in source.firstFooterVisuals) visual(v),
    ],
    evenHeaderVisuals: <WmlVisual>[
      for (final v in source.evenHeaderVisuals) visual(v),
    ],
    evenFooterVisuals: <WmlVisual>[
      for (final v in source.evenFooterVisuals) visual(v),
    ],
  );

  /// block API.
  static WmlBlock block(WmlBlock source) {
    switch (source) {
      case WmlParagraph():
        return paragraph(source);
      case WmlTable():
        return table(source);
      case WmlVisual():
        return visual(source);
      case WmlFrame():
        return frame(source);
      case WmlContentControlBlock():
        return WmlContentControlBlock(
          control: source.control,
          blocks: <WmlBlock>[for (final child in source.blocks) block(child)],
        );
      case WmlEquation():
        return equation(source);
      case WmlToc():
        return toc(source);
      case WmlOpaqueBlock():
        return WmlOpaqueBlock(
          xml: source.xml,
          sourcePartUri: source.sourcePartUri,
          relationships: source.relationships,
        );
    }
  }

  /// paragraph API.
  static WmlParagraph paragraph(WmlParagraph source) {
    return WmlParagraph(
      properties: source.properties.copy(),
      inlines: inlines(source.inlines),
      contentControlWrappers: List.of(source.contentControlWrappers),
    );
  }

  /// slicedParagraph API.
  static WmlParagraph slicedParagraph(WmlParagraph source, int from, int to) {
    final int length = source.text.length;
    final int start = from.clamp(0, length);
    final int end = to.clamp(0, length);
    if (start <= 0 && end >= length) {
      return paragraph(source);
    }
    return WmlParagraph(
      properties: source.properties.copy(),
      inlines: sliceInlines(source, start, end < start ? start : end),
    );
  }

  /// inlines API.
  static List<WmlInline> inlines(List<WmlInline> source) {
    return <WmlInline>[for (final WmlInline inline in source) _inline(inline)];
  }

  /// table API.
  static WmlTable table(WmlTable source) {
    return WmlTable(
      grid: List<double>.from(source.grid),
      properties: source.properties.copy(),
      rows: <WmlTableRow>[
        for (final WmlTableRow row in source.rows)
          WmlTableRow(
            cantSplit: row.cantSplit,
            height: row.height,
            cells: <WmlTableCell>[
              for (final WmlTableCell cell in row.cells) cellOf(cell),
            ],
          ),
      ],
    );
  }

  /// cellOf API.
  static WmlTableCell cellOf(WmlTableCell cell) {
    return WmlTableCell(
      gridSpan: cell.gridSpan,
      vMerge: cell.vMerge,
      width: cell.width,
      fillColor: cell.fillColor,
      borderTop: cell.borderTop,
      borderBottom: cell.borderBottom,
      borderLeft: cell.borderLeft,
      borderRight: cell.borderRight,
      blocks: <WmlBlock>[
        for (final WmlBlock block in cell.blocks) WmlClone.block(block),
      ],
    );
  }

  /// visual API.
  static WmlVisual visual(WmlVisual source) =>
      WmlVisual(visual: source.visual.copy());

  /// frame API.
  static WmlFrame frame(WmlFrame source) {
    return WmlFrame(
      x: source.x,
      y: source.y,
      width: source.width,
      height: source.height,
      anchor: source.anchor,
      wrap: source.wrap,
      fillColor: source.fillColor,
      strokeColor: source.strokeColor,
      insetLeft: source.insetLeft,
      insetTop: source.insetTop,
      insetRight: source.insetRight,
      insetBottom: source.insetBottom,
      sourceBodyPropertiesXml: source.sourceBodyPropertiesXml,
      importedInsets: source.importedInsets == null
          ? null
          : Map.of(source.importedInsets!),
      sourceLinePropertiesXml: source.sourceLinePropertiesXml,
      importedStrokeColor: source.importedStrokeColor,
      anchorParagraphProperties: source.anchorParagraphProperties?.copy(),
      blocks: <WmlBlock>[
        for (final WmlBlock block in source.blocks) WmlClone.block(block),
      ],
    );
  }

  /// equation API.
  static WmlEquation equation(WmlEquation source) =>
      WmlEquation(math: source.math.copy());

  /// toc API.
  static WmlToc toc(WmlToc source) {
    return WmlToc(
      minLevel: source.minLevel,
      maxLevel: source.maxLevel,
      showPageNumbers: source.showPageNumbers,
      omitPageNumbersFromLevel: source.omitPageNumbersFromLevel,
      omitPageNumbersThroughLevel: source.omitPageNumbersThroughLevel,
      captionLabel: source.captionLabel,
      title: source.title,
      entries: <WmlTocEntry>[
        for (final WmlTocEntry entry in source.entries)
          WmlTocEntry(
            text: entry.text,
            level: entry.level,
            headingParagraphIndex: entry.headingParagraphIndex,
            pageNumber: entry.pageNumber,
          ),
      ],
      titleParagraph: paragraph(source.titleParagraph),
      itemParagraphs: <WmlParagraph>[
        for (final WmlParagraph item in source.itemParagraphs) paragraph(item),
      ],
      sourcePresentation: source.sourcePresentation == null
          ? null
          : WmlTocPresentation(
              configuration: source.sourcePresentation!.configuration,
              paragraphs: [
                for (final item in source.sourcePresentation!.paragraphs)
                  WmlTocSourceParagraph(
                    paragraph: paragraph(item.paragraph),
                    title: item.title,
                    entryIndex: item.entryIndex,
                    textStart: item.textStart,
                    textEnd: item.textEnd,
                    pageStart: item.pageStart,
                    pageEnd: item.pageEnd,
                  ),
              ],
            ),
    );
  }

  /// paragraphsOf API.
  static List<WmlParagraph> paragraphsOf(WmlBlock block) {
    return WordTree.paragraphs(<WmlBlock>[block]).toList();
  }

  /// plainTextOf API.
  static String plainTextOf(List<WmlBlock> blocks) {
    final StringBuffer buffer = StringBuffer();
    for (final WmlBlock block in blocks) {
      for (final WmlParagraph para in paragraphsOf(block)) {
        if (buffer.isNotEmpty) {
          buffer.write('\n');
        }
        buffer.write(para.text);
      }
    }
    return buffer.toString();
  }

  static WmlInline _inline(WmlInline inline) {
    if (inline is WmlBookmarkBoundary) {
      return WmlBookmarkBoundary(
        id: inline.id,
        isStart: inline.isStart,
        name: inline.name,
        sourceXml: inline.sourceXml,
      );
    }
    if (inline is WmlContentControlBoundary) {
      return WmlContentControlBoundary(
        control: inline.control,
        start: inline.start,
      );
    }
    if (inline is WmlNoteMarker) {
      return WmlNoteMarker(
        endnote: inline.endnote,
        properties: inline.properties.copy(),
      );
    }
    if (inline is WmlRun) {
      return WmlRun(
        text: inline.text,
        properties: inline.properties.copy(),
        hyperlink: inline.hyperlink?.copy(),
        commentIds: List<int>.from(inline.commentIds),
        noteRefId: inline.noteRefId,
        noteRefEndnote: inline.noteRefEndnote,
        fieldInstruction: inline.fieldInstruction,
        fieldLocked: inline.fieldLocked,
        fieldDirty: inline.fieldDirty,
      );
    }
    if (inline is WmlBreak) {
      return WmlBreak(inline.type);
    }
    if (inline is WmlObject) {
      return WmlObject(
        relationshipId: inline.relationshipId,
        embedded: inline.embedded,
        width: inline.width,
        height: inline.height,
      );
    }
    return inline;
  }

  /// Copies typed inlines, retaining complete control boundaries in the slice.
  static List<WmlInline> sliceInlines(WmlParagraph source, int from, int to) {
    from = from.clamp(0, source.text.length);
    to = to.clamp(from, source.text.length);
    if (to <= from) {
      return <WmlInline>[];
    }
    final controls = WordContentControls.controlsInSlice(source, from, to);
    final emptyBookmarks = _emptyBookmarks(source);
    final List<WmlInline> out = <WmlInline>[];
    var offset = 0;
    for (final WmlInline inline in source.inlines) {
      if (inline is! WmlRun) {
        if (inline is WmlContentControlBoundary
            ? controls.contains(inline.control)
            : inline is WmlBookmarkBoundary &&
                  !inline.isStart &&
                  !emptyBookmarks.contains(WordBookmarks.canonicalId(inline.id))
            ? offset > from && offset <= to
            : offset >= from && offset < to) {
          out.add(_inline(inline));
        }
        continue;
      }
      final int end = offset + inline.text.length;
      if (end <= from || offset >= to) {
        offset = end;
        continue;
      }
      final int localStart = from > offset ? from - offset : 0;
      final int localEnd = to < end ? to - offset : inline.text.length;
      out.add(
        WmlRun(
          // Note marks and field results are atomic regardless of label length.
          text: inline.isAtomic
              ? inline.text
              : inline.text.substring(localStart, localEnd),
          properties: inline.properties.copy(),
          hyperlink: inline.hyperlink?.copy(),
          commentIds: List<int>.from(inline.commentIds),
          noteRefId: inline.noteRefId,
          noteRefEndnote: inline.noteRefEndnote,
          fieldInstruction: inline.fieldInstruction,
          fieldLocked: inline.fieldLocked,
          fieldDirty: inline.fieldDirty,
        ),
      );
      offset = end;
    }
    return out;
  }

  /// Partitions all typed inlines exactly once at a paragraph break.
  ///
  /// Empty control pairs move together to the right. Nonempty controls cannot
  /// be split internally; controls ending at the break stay on the left.
  static ({List<WmlInline> head, List<WmlInline> tail}) splitInlines(
    WmlParagraph source,
    int offset,
  ) {
    final at = WmlRunEdit.normalizeRange(source, offset, offset).start;
    WordContentControls.assertCanSplit(source, at);
    final leftControls = <WmlContentControlData>{
      for (final span in WordContentControls.spans(source))
        if (span.end < at || (span.end == at && span.start < span.end))
          span.control,
    };
    final emptyBookmarks = _emptyBookmarks(source);
    final head = <WmlInline>[];
    final tail = <WmlInline>[];
    var position = 0;
    for (final inline in source.inlines) {
      if (inline is WmlRun) {
        final end = position + inline.text.length;
        if (end <= at) {
          head.add(_inline(inline));
        } else if (position >= at) {
          tail.add(_inline(inline));
        } else {
          head.add(
            (_inline(inline) as WmlRun)
              ..text = inline.text.substring(0, at - position),
          );
          tail.add(
            (_inline(inline) as WmlRun)
              ..text = inline.text.substring(at - position),
          );
        }
        position = end;
      } else {
        final onLeft = inline is WmlContentControlBoundary
            ? leftControls.contains(inline.control)
            : inline is WmlBookmarkBoundary &&
                  !inline.isStart &&
                  !emptyBookmarks.contains(WordBookmarks.canonicalId(inline.id))
            ? position <= at
            : position < at;
        (onLeft ? head : tail).add(_inline(inline));
      }
    }
    return (head: head, tail: tail);
  }

  static Set<String> _emptyBookmarks(WmlParagraph source) {
    final starts = <String, int>{};
    final empty = <String>{};
    var offset = 0;
    for (final inline in source.inlines) {
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is WmlBookmarkBoundary) {
        final id = WordBookmarks.canonicalId(inline.id);
        if (inline.isStart) {
          starts[id] = offset;
        } else if (starts[id] == offset) {
          empty.add(id);
        }
      }
    }
    return empty;
  }
}
