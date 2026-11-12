// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordTableWriter on _StructuredWordWriter {
  void _table(LegacyWordTable table) {
    if (++_tableDepth > 63) {
      throw const FormatException('Word tables are nested too deeply.');
    }
    _count('tables');
    var origin = table.indentTwips ?? 0;
    for (final row in table.rows) {
      if (row.indentTwips != null && row.indentTwips! < origin) {
        origin = row.indentTwips!;
      }
    }
    if (origin < -31680 || origin > 31680) {
      throw const FormatException('Invalid Word table indentation.');
    }
    final grid = <int>{0};
    var canWriteGrid = table.rows.isNotEmpty;
    final starts = <int>[];
    final ends = <int>[];
    for (final row in table.rows) {
      var offset = (row.indentTwips ?? table.indentTwips ?? origin) - origin;
      starts.add(offset);
      grid.add(offset);
      for (final cell in row.cells) {
        final width = cell.widthTwips;
        if (width == null || width <= 0) {
          canWriteGrid = false;
          break;
        }
        offset += width;
        grid.add(offset);
      }
      ends.add(offset);
    }
    final edges = grid.toList()..sort();
    final edgeIndices = {for (var i = 0; i < edges.length; i++) edges[i]: i};
    // Binary TDefTable retains the outer edge. In the legacy Word table
    // convention used by DOCX importers, tblInd locates the leading text
    // margin; keep the original edge in the model and add that cell margin.
    // Emit zero explicitly: omitting tblInd takes a different fallback path
    // in readers that align the table's outer box instead of its text.
    final leadingMargin =
        table.rows.isNotEmpty && table.rows.first.cells.isNotEmpty
        ? table.rows.first.cells.first.marginsTwips[LegacyWordCellBorderSide
                  .left] ??
              0
        : 0;
    final textIndent = origin + leadingMargin;
    if (textIndent < -32768 || textIndent > 32767) {
      throw const FormatException('Invalid Word table text indentation.');
    }
    _xml.add('<w:tbl><w:tblPr>');
    if (table.rightToLeft) _xml.add('<w:bidiVisual w:val="on"/>');
    _xml.add(
      canWriteGrid
          ? '<w:tblW w:w="${edges.last}" w:type="dxa"/>'
          : '<w:tblW w:w="0" w:type="auto"/>',
    );
    if (table.alignment != LegacyWordAlignment.left) {
      _xml.add(
        '<w:jc w:val="${table.alignment == LegacyWordAlignment.center ? 'center' : 'right'}"/>',
      );
    }
    _xml.add('<w:tblInd w:w="$textIndent" w:type="dxa"/>');
    _xml.add('<w:tblLayout w:type="${table.autoFit ? 'autofit' : 'fixed'}"/>');
    final look = table.look;
    _xml.add(
      '<w:tblLook w:val="${(look.flags & 0x7e0).toRadixString(16).padLeft(4, '0')}" '
      'w:firstRow="${look.firstRow ? 1 : 0}" w:lastRow="${look.lastRow ? 1 : 0}" '
      'w:firstColumn="${look.firstColumn ? 1 : 0}" w:lastColumn="${look.lastColumn ? 1 : 0}" '
      'w:noHBand="${look.noRowBands ? 1 : 0}" w:noVBand="${look.noColumnBands ? 1 : 0}"/></w:tblPr>',
    );
    if (table.styleId != null) {
      _evidenceRecords.add({
        'kind': 'resolvedTableStyle',
        'story': _storyId,
        'cp': table.startCp,
        'sourceStyleId': table.styleId,
        'sourceStyleName': table.styleName,
        'lookFlags': look.flags,
        'reason':
            'conditional style resolved to current cell and text properties',
      });
    }
    if (canWriteGrid) {
      _xml.add('<w:tblGrid>');
      for (var i = 1; i < edges.length; i++) {
        _xml.add('<w:gridCol w:w="${edges[i] - edges[i - 1]}"/>');
      }
      _xml.add('</w:tblGrid>');
    } else {
      _xml.add('<w:tblGrid/>');
    }
    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      _countBreak();
      _xml.add('<w:tr><w:trPr>');
      if (canWriteGrid) {
        final before = edgeIndices[starts[r]]!;
        final after = edges.length - 1 - edgeIndices[ends[r]]!;
        if (before != 0) _xml.add('<w:gridBefore w:val="$before"/>');
        if (after != 0) _xml.add('<w:gridAfter w:val="$after"/>');
        if (before != 0) {
          _xml.add('<w:wBefore w:w="${starts[r]}" w:type="dxa"/>');
        }
        if (after != 0) {
          _xml.add('<w:wAfter w:w="${edges.last - ends[r]}" w:type="dxa"/>');
        }
      }
      if (row.cantSplit) _xml.add('<w:cantSplit/>');
      if (row.heightTwips case final height? when height > 0) {
        if (height > 32768) {
          throw const FormatException('Invalid Word row height.');
        }
        _xml.add(
          '<w:trHeight w:val="$height" w:hRule="${row.exactHeight ? 'exact' : 'atLeast'}"/>',
        );
      }
      if (row.isHeader) _xml.add('<w:tblHeader/>');
      _xml.add('</w:trPr>');
      var offset = starts[r];
      for (final cell in row.cells) {
        _countBreak();
        _count('cells');
        _xml.add('<w:tc><w:tcPr>');
        final width = cell.widthTwips;
        if (width != null && width > 0) {
          _xml.add('<w:tcW w:w="$width" w:type="dxa"/>');
          if (canWriteGrid) {
            final span = edgeIndices[offset + width]! - edgeIndices[offset]!;
            if (span > 1) _xml.add('<w:gridSpan w:val="$span"/>');
          }
          offset += width;
        }
        if (cell.mergeStart || cell.mergeContinue) {
          _xml.add(
            '<w:hMerge w:val="${cell.mergeStart ? 'restart' : 'continue'}"/>',
          );
        }
        if (cell.verticalMergeStart || cell.verticalMergeContinue) {
          _xml.add(
            '<w:vMerge w:val="${cell.verticalMergeStart ? 'restart' : 'continue'}"/>',
          );
        }
        _cellBorders(cell);
        if (cell.shading != null) {
          _shading(
            cell.shading!,
            _xml,
            'tableCell',
            cell.blocks.isEmpty ? null : cell.blocks.first.startCp,
          );
        }
        if (cell.marginsTwips.isNotEmpty) {
          _xml.add('<w:tcMar>');
          for (final side in LegacyWordCellBorderSide.values.take(4)) {
            final margin = cell.marginsTwips[side];
            if (margin == null) continue;
            if (margin < 0 || margin > 31680) {
              throw const FormatException('Invalid Word cell margin.');
            }
            _xml.add('<w:${side.name} w:w="$margin" w:type="dxa"/>');
          }
          _xml.add('</w:tcMar>');
        }
        _xml.add('<w:vAlign w:val="${cell.verticalAlignment.name}"/></w:tcPr>');
        for (final block in cell.blocks) {
          switch (block) {
            case LegacyWordParagraph():
              _paragraph(block);
            case LegacyWordTable():
              _table(block);
          }
        }
        if (cell.blocks.isEmpty || cell.blocks.last is LegacyWordTable) {
          _xml.add('<w:p/>');
        }
        _xml.add('</w:tc>');
      }
      _xml.add('</w:tr>');
    }
    _xml.add('</w:tbl>');
    _tableDepth--;
  }

  void _cellBorders(LegacyWordTableCell cell) {
    if (cell.borders.isEmpty) return;
    _xml.add('<w:tcBorders>');
    for (final side in LegacyWordCellBorderSide.values) {
      final border = cell.borders[side];
      if (border == null) continue;
      if ((!_wordBorderStyles.contains(border.style) &&
              border.style != 'nil') ||
          border.widthEighthPoints < 0 ||
          border.widthEighthPoints > 255) {
        throw const FormatException('Invalid Word cell border.');
      }
      final name = switch (side) {
        LegacyWordCellBorderSide.diagonalDown => 'tl2br',
        LegacyWordCellBorderSide.diagonalUp => 'tr2bl',
        _ => side.name,
      };
      // Word ignores border spacing for table cells. Shadow/frame flags are
      // retained only on applicable bottom/right sides, as for source Brc.
      final outer =
          side == LegacyWordCellBorderSide.bottom ||
          side == LegacyWordCellBorderSide.right;
      _xml.add(
        '<w:$name w:val="${border.style}" w:sz="${border.widthEighthPoints}" '
        'w:color="${border.colorHex == null ? 'auto' : _StructuredWordWriter._color(border.colorHex!)}" '
        'w:shadow="${outer && border.shadow ? 1 : 0}" w:frame="${outer && border.frame ? 1 : 0}"/>',
      );
    }
    _xml.add('</w:tcBorders>');
  }
}
