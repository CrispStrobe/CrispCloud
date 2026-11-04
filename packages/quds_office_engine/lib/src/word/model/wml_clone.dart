import 'wml_document.dart';

/// Deep copies of Word blocks so cut / paste / undo never share mutable state.
abstract final class WmlClone {
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
      case WmlEquation():
        return equation(source);
      case WmlToc():
        return toc(source);
    }
  }

  /// paragraph API.
  static WmlParagraph paragraph(WmlParagraph source) {
    return WmlParagraph(
      properties: source.properties.copy(),
      inlines: inlines(source.inlines),
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
      inlines: inlines(_extractRuns(source, start, end < start ? start : end)),
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
    );
  }

  /// paragraphsOf API.
  static List<WmlParagraph> paragraphsOf(WmlBlock block) {
    final List<WmlParagraph> out = <WmlParagraph>[];
    _collectParagraphs(<WmlBlock>[block], out);
    return out;
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

  static void _collectParagraphs(
    List<WmlBlock> blocks,
    List<WmlParagraph> out,
  ) {
    for (final WmlBlock block in blocks) {
      switch (block) {
        case WmlParagraph():
          out.add(block);
        case WmlTable(:final List<WmlTableRow> rows):
          for (final WmlTableRow row in rows) {
            for (final WmlTableCell cell in row.cells) {
              _collectParagraphs(cell.blocks, out);
            }
          }
        case WmlToc():
          out.add(block.titleParagraph);
          out.addAll(block.itemParagraphs);
        case WmlFrame():
          _collectParagraphs(block.blocks, out);
        case WmlVisual():
        case WmlEquation():
          break;
      }
    }
  }

  static WmlInline _inline(WmlInline inline) {
    if (inline is WmlRun) {
      return WmlRun(
        text: inline.text,
        properties: inline.properties.copy(),
        hyperlink: inline.hyperlink?.copy(),
        commentIds: List<int>.from(inline.commentIds),
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

  static List<WmlInline> _extractRuns(WmlParagraph source, int from, int to) {
    if (to <= from) {
      return <WmlInline>[WmlRun()];
    }
    final List<WmlInline> out = <WmlInline>[];
    var offset = 0;
    for (final WmlInline inline in source.inlines) {
      if (inline is! WmlRun) {
        if (offset >= from && offset < to) {
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
          text: inline.text.substring(localStart, localEnd),
          properties: inline.properties.copy(),
          hyperlink: inline.hyperlink?.copy(),
          commentIds: List<int>.from(inline.commentIds),
        ),
      );
      offset = end;
    }
    return out.isEmpty ? <WmlInline>[WmlRun()] : out;
  }
}
