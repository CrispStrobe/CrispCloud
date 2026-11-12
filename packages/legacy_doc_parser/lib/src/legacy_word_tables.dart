// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.4.3: each cell ends in a depth-specific cell mark, followed by a
// separate row mark. Nested tables are cell blocks, not ordinary paragraphs.
extension _WordTables on _StructuredWordParser {
  List<LegacyWordBlock> _assembleTables(
    List<_Paragraph> paragraphs, {
    _TableContexts? contexts,
  }) {
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
      _Props? tableProperties;
      var rowCursor = cursor;
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
          if (tableProperties != null &&
              !_sameTableRows(tableProperties, properties)) {
            cursor = rowCursor;
            cells.clear();
            cell = [];
            end = rows.last.endCp!;
            break;
          }
          final rowContexts = contexts?.rows[paragraph.endCp];
          tableProperties ??= {...?rowContexts?.first.table, ...properties};
          final height = properties['rowHeight'] as int? ?? 0;
          rows.add(
            LegacyWordTableRow(
              endCp: paragraph.endCp,
              cantSplit:
                  (properties['rowCantSplit'] ??
                      rowContexts?.first.table['rowCantSplit']) ==
                  true,
              heightTwips: height == 0 ? null : height.abs(),
              exactHeight: height < 0,
              indentTwips:
                  properties['rowLeft'] as int? ?? definition.edges.first,
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
                    mergeStart: (definition.flags[i] & 3) >= 2,
                    mergeContinue: (definition.flags[i] & 3) == 1,
                    verticalMergeStart: ((definition.flags[i] >> 5) & 3) >= 2,
                    verticalMergeContinue:
                        ((definition.flags[i] >> 5) & 3) == 1,
                    shading: _resolvedCellShading(
                      properties,
                      rowContexts?[i],
                      i,
                    ),
                    verticalAlignment:
                        LegacyWordCellVerticalAlignment
                            .values[(properties['cellAlignment']
                                as Map<int, int>?)?[i] ??
                            (i < definition.styleDefaults.length &&
                                    !definition.styleDefaults[i]
                                ? ((definition.flags[i] >> 7) & 3)
                                : null) ??
                            rowContexts?[i].table['styleCellAlignment']
                                as int? ??
                            0],
                    conditionalFlags: rowContexts?[i].flags ?? 0,
                    marginsTwips: _resolvedCellMargins(
                      properties,
                      rowContexts?[i],
                      i,
                    ),
                    borders: _resolvedCellBorders(
                      properties,
                      rowContexts?[i],
                      i,
                      cells.length,
                      rows.isEmpty,
                    ),
                  ),
              ]),
            ),
          );
          cells.clear();
          rowCursor = cursor;
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
        rows: List.unmodifiable(rows),
        indentTwips: tableProperties?['rowLeft'] as int?,
        autoFit: tableProperties?['tableAutoFit'] == true,
        styleId: tableProperties?['tableStyle'] as int?,
        styleName: styles[tableProperties?['tableStyle']]?.name,
        look: LegacyWordTableLook(
          flags: tableProperties?['tableLook'] as int? ?? 0,
        ),
        rightToLeft:
            tableProperties?['tableRtl'] == true ||
            tableProperties?['tableRtl90'] == true,
        alignment:
            LegacyWordAlignment.values[tableProperties?['tableAlignment']
                    as int? ??
                tableProperties?['tablePhysicalAlignment'] as int? ??
                0],
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
