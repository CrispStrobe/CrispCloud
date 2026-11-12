// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.4.3: each cell ends in a depth-specific cell mark, followed by a
// separate row mark. Nested tables are cell blocks, not ordinary paragraphs.
extension _WordTables on _StructuredWordParser {
  List<LegacyWordBlock> _assembleTables(List<_Paragraph> paragraphs) {
    var cursor = 0;
    int depthOf(_Paragraph value) =>
        value.properties['tableDepth'] as int? ??
        (value.properties['inTable'] == true ? 1 : 0);

    LegacyWordTable table(int depth) {
      if (depth > 63 || cursor >= paragraphs.length) {
        throw const FormatException('Word tables are nested too deeply.');
      }
      final start = paragraphs[cursor].paragraph.startCp;
      var end = start;
      final rows = <LegacyWordTableRow>[];
      final cells = <List<LegacyWordBlock>>[];
      var cell = <LegacyWordBlock>[];
      while (cursor < paragraphs.length) {
        final item = paragraphs[cursor];
        final currentDepth = depthOf(item);
        if (currentDepth < depth) break;
        if (currentDepth > depth) {
          cell.add(table(depth + 1));
          continue;
        }
        cursor++;
        final properties = item.properties;
        final paragraph = item.paragraph;
        end = paragraph.endCp;
        final rowEnd = depth == 1
            ? properties['rowEnd'] == true
            : properties['innerRowEnd'] == true;
        final cellEnd = depth == 1
            ? item.terminator == 7 && !rowEnd
            : properties['innerCellEnd'] == true && !rowEnd;
        if ((depth > 1 && item.terminator == 7) ||
            (depth == 1 &&
                (properties['innerCellEnd'] == true ||
                    properties['innerRowEnd'] == true)) ||
            ((rowEnd || cellEnd) && item.terminator != (depth == 1 ? 7 : 13))) {
          throw const FormatException('Invalid Word table terminator.');
        }
        if (rowEnd) {
          if (paragraph.runs.isNotEmpty || cell.isNotEmpty || cells.isEmpty) {
            throw const FormatException('Unterminated Word table cell.');
          }
          final definition = properties['tableDefinition'] as _TableDefinition?;
          if (definition == null || definition.flags.length != cells.length) {
            throw const FormatException(
              'Word table cell count does not match its row.',
            );
          }
          rows.add(
            LegacyWordTableRow(
              originTwips:
                  properties['tableOrigin'] as int? ?? definition.edges.first,
              tableStyleId: _resolvedTableStyleId(
                properties['tableStyleId'] as int?,
              ),
              styleOptions: properties['tableStyleOptions'] as int? ?? 0x600,
              halfGapTwips: properties['tableGapHalf'] as int? ?? 0,
              // Only leading, contiguous rows are repeating headers.
              isHeader:
                  properties['rowHeader'] == true &&
                  (rows.isEmpty || rows.last.isHeader),
              cells: List.unmodifiable([
                for (var i = 0; i < cells.length; i++)
                  LegacyWordTableCell(
                    blocks: List.unmodifiable(cells[i]),
                    paragraphs: List.unmodifiable(
                      cells[i].whereType<LegacyWordParagraph>(),
                    ),
                    widthTwips: definition.edges[i + 1] - definition.edges[i],
                    formatting: _mergeTableCellFormat(
                      i < definition.formats.length
                          ? definition.formats[i]
                          : const LegacyWordTableCellFormat(),
                      LegacyWordTableCellFormat(
                        margins: Map.unmodifiable({
                          ...?properties['tableMargins']
                              as Map<LegacyWordBorderSide, int?>?,
                          ...?(properties['cellMargins']
                              as Map<
                                int,
                                Map<LegacyWordBorderSide, int?>
                              >?)?[i],
                        }),
                      ),
                    ),
                    mergeStart: (definition.flags[i] & 3) >= 2,
                    mergeContinue: (definition.flags[i] & 3) == 1,
                    verticalMergeStart: ((definition.flags[i] >> 5) & 3) >= 2,
                    verticalMergeContinue:
                        ((definition.flags[i] >> 5) & 3) == 1,
                    shading:
                        (properties[source.version > 0xd9 &&
                                    _resolvedTableStyleId(
                                          properties['tableStyleId'] as int?,
                                        ) !=
                                        null
                                ? 'cellShadingRaw'
                                : 'cellShading']
                            as Map<int, LegacyWordShading>?)?[i],
                  ),
              ]),
            ),
          );
          cells.clear();
        } else {
          cell.add(paragraph);
          if (cellEnd) {
            cells.add(cell);
            cell = [];
            if (cells.length > 63) {
              throw const FormatException('Word table has too many cells.');
            }
          }
        }
        if (sectionEnds.contains(end)) break;
      }
      if (rows.isEmpty || cell.isNotEmpty || cells.isNotEmpty) {
        throw const FormatException('Unterminated Word table row.');
      }
      return LegacyWordTable(
        startCp: start,
        endCp: end,
        rows: List.unmodifiable(_resolveTableStyleCells(rows)),
      );
    }

    final blocks = <LegacyWordBlock>[];
    while (cursor < paragraphs.length) {
      final item = paragraphs[cursor];
      if (depthOf(item) == 0) {
        if (item.properties['rowEnd'] == true ||
            item.properties['innerRowEnd'] == true ||
            item.properties['innerCellEnd'] == true) {
          throw const FormatException(
            'Word table marker has no containing table.',
          );
        }
        blocks.add(item.paragraph);
        cursor++;
      } else {
        blocks.add(table(1));
      }
    }
    return blocks;
  }
}
