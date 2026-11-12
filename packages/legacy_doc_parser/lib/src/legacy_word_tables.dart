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
      _Props? tableProperties;
      var rowCursor = cursor, lastRowEnd = start;
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
            end = lastRowEnd;
            break;
          }
          tableProperties ??= properties;
          rows.add(
            LegacyWordTableRow(
              sourceHeaderRequest: properties['rowHeader'] as bool?,
              formattingRevision: _tableRowRevision(properties),
              alignment: _tableAlignment(properties),
              autoFit: properties['tableAutoFit'] == true,
              originTwips:
                  properties['tableOrigin'] as int? ?? definition.edges.first,
              tableStyleId: _resolvedTableStyleId(
                properties['tableStyleId'] as int?,
              ),
              styleOptions: properties['tableStyleOptions'] as int? ?? 0x600,
              halfGapTwips: properties['tableGapHalf'] as int? ?? 0,
              heightTwips: properties['tableRowHeight'] as int?,
              cantSplit:
                  properties['tableCantSplit'] as bool? ??
                  properties['tableCantSplit90'] as bool?,
              borders:
                  properties['tableBorders']
                      as Map<LegacyWordTableBorderSide, LegacyWordBorder>? ??
                  const {},
              defaultCellMargins:
                  properties['tableMargins']
                      as Map<LegacyWordBorderSide, int?>? ??
                  const {},
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
                        verticalAlignment:
                            (properties['cellAlignment']
                                    as Map<int, int>?)?[i] ==
                                null
                            ? null
                            : LegacyWordCellAlignment
                                  .values[(properties['cellAlignment']
                                  as Map<int, int>)[i]!],
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
          rowCursor = cursor;
          lastRowEnd = end;
        } else {
          _unplacedTableRowRevision(properties);
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
        rightToLeft:
            tableProperties?['tableRtl'] == true ||
            tableProperties?['tableRtl90'] == true,
        autoFit: tableProperties?['tableAutoFit'] == true,
        alignment: _tableAlignment(tableProperties ?? const {}),
        position: _tablePosition(tableProperties ?? const {}),
      );
    }

    final blocks = <LegacyWordBlock>[];
    while (cursor < paragraphs.length) {
      final item = paragraphs[cursor];
      if (depthOf(item) == 0) {
        _unplacedTableRowRevision(item.properties);
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

// MS-DOC 2.6.3, PositionCodeOperand and XAS/YAS_plusOne. Nondefault
// positioning/wrapping values activate tblpPr; an explicit "none" anchor
// makes the table inline. In particular, do not delete its anchor paragraph.
LegacyWordTablePosition? _tablePosition(_Props properties) {
  int value(int code) => properties['tablePosition$code'] as int? ?? 0;
  if (const [
    0x360d,
    0x940e,
    0x940f,
    0x9410,
    0x9411,
    0x941e,
    0x941f,
  ].every((code) => value(code) == 0)) {
    return null;
  }
  final pc = value(0x360d), x = value(0x940e), y = value(0x940f);
  final vertical = (pc >> 4) & 3, horizontal = (pc >> 6) & 3;
  if (vertical == 3 || horizontal == 3) return null;
  final xPlacement = switch (x) {
    0 => LegacyWordTableHorizontalPlacement.left,
    -4 => LegacyWordTableHorizontalPlacement.center,
    -8 => LegacyWordTableHorizontalPlacement.right,
    -12 => LegacyWordTableHorizontalPlacement.inside,
    -16 => LegacyWordTableHorizontalPlacement.outside,
    _ => null,
  };
  final yPlacement = switch (y) {
    0 => LegacyWordTableVerticalPlacement.inline,
    -4 => LegacyWordTableVerticalPlacement.top,
    -8 => LegacyWordTableVerticalPlacement.center,
    -12 => LegacyWordTableVerticalPlacement.bottom,
    -16 => LegacyWordTableVerticalPlacement.inside,
    -20 => LegacyWordTableVerticalPlacement.outside,
    _ => null,
  };
  return LegacyWordTablePosition(
    horizontalAnchor: const [
      LegacyWordTableAnchor.text,
      LegacyWordTableAnchor.margin,
      LegacyWordTableAnchor.page,
    ][horizontal],
    verticalAnchor: const [
      LegacyWordTableAnchor.margin,
      LegacyWordTableAnchor.page,
      LegacyWordTableAnchor.text,
    ][vertical],
    horizontalPlacement: xPlacement,
    verticalPlacement: yPlacement,
    horizontalOffsetTwips: xPlacement == null ? x - 1 : null,
    verticalOffsetTwips: yPlacement == null ? y - 1 : null,
    leftFromTextTwips: value(0x9410),
    topFromTextTwips: value(0x9411),
    rightFromTextTwips: value(0x941e),
    bottomFromTextTwips: value(0x941f),
    allowOverlap: value(0x3465) == 0,
  );
}
