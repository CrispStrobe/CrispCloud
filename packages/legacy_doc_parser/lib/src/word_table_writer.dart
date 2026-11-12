// SPDX-License-Identifier: MPL-2.0
part of 'conversion.dart';

extension _WordTableWriter on _StructuredWordWriter {
  void _table(LegacyWordTable table) {
    if (++_tableDepth > 63) {
      throw const FormatException('Word tables are nested too deeply.');
    }
    _count('tables');
    final origin = table.rows.isEmpty
        ? 0
        : table.rows
              .map((row) => row.originTwips)
              .reduce((a, b) => a < b ? a : b);
    // Every row retains its logical origin. Include all absolute row edges in
    // the shared grid, including omitted leading/trailing cells.
    final grid = <int>{origin};
    var canWriteGrid = table.rows.isNotEmpty;
    for (final row in table.rows) {
      var offset = row.originTwips;
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
    }
    final edges = grid.toList()..sort();
    final edgeIndices = {for (var i = 0; i < edges.length; i++) edges[i]: i};
    _xml.add('<w:tbl><w:tblPr>');
    final firstRow = table.rows.firstOrNull;
    final tableMargins = firstRow?.defaultCellMargins ?? const {};
    final firstMargins = firstRow?.cells.firstOrNull?.formatting.margins;
    final leadingMargin =
        firstMargins?.containsKey(LegacyWordBorderSide.left) == true
        ? firstMargins![LegacyWordBorderSide.left] ?? 0
        : 108;
    // Legacy Word/OOXML top-level indentation aligns the first cell's text,
    // whereas TDefTable retains the outer boundary. Native DOC->DOCX oracles
    // confirm this conversion for zero, signed, per-cell and default margins.
    // Nested tables already use their boundary origin and need no adjustment.
    final nativeIndent = origin + (_tableDepth == 1 ? leadingMargin : 0);
    if (origin < -31680 ||
        origin > 31680 ||
        nativeIndent < -32768 ||
        nativeIndent > 32767) {
      throw const FormatException('Invalid Word table indentation.');
    }
    if (firstRow?.tableStyleId case final id?) {
      if (!_tableStyleDefinitions.containsKey(id)) {
        throw const FormatException('Unknown Word table style.');
      }
      _xml.add('<w:tblStyle w:val="LegacyTable$id"/>');
    }
    if (table.position case final position?) {
      var horizontalOrigin = 0;
      if (position.horizontalOffsetTwips != null) {
        // MS-DOC's physical table origin precedes its row boundary, default
        // padding and border. OOXML floats the resulting table edge. Keep
        // the table default distinct from a first-cell padding override.
        final margin = tableMargins.containsKey(LegacyWordBorderSide.left)
            ? tableMargins[LegacyWordBorderSide.left] ?? 0
            : 108;
        horizontalOrigin = origin + margin;
        // The source first cell's left border defines this physical origin
        // even when bidiVisual reverses the displayed cells. Single borders
        // straddle the edge; truncate fractional twips as in source geometry.
        final border = firstRow
            ?.cells
            .firstOrNull
            ?.formatting
            .borders[LegacyWordTableBorderSide.left];
        if (border != null &&
            border.style != 'none' &&
            border.style != 'nil' &&
            border.widthEighthPoints != 0) {
          if (border.style == 'single' &&
              border.spacingPoints == 0 &&
              !border.shadow &&
              !border.frame) {
            horizontalOrigin += border.widthEighthPoints * 5 ~/ 4;
          } else {
            limitations.add(LegacyWordConversionLimitation.partialFormatting);
            _evidenceRecords.add({
              'kind': 'floatingTableBorderOrigin',
              'tableStartCp': table.startCp,
              'borderStyle': border.style,
              'widthEighthPoints': border.widthEighthPoints,
              'spacingPoints': border.spacingPoints,
              'shadow': border.shadow,
              'frame': border.frame,
              'reason':
                  'Source border is preserved; its contribution to the floating origin is not mapped outside an unadorned single line.',
            });
          }
        }
      }
      _tablePosition(position, horizontalOriginTwips: horizontalOrigin);
    }
    if (table.rightToLeft) _xml.add('<w:bidiVisual w:val="on"/>');
    _xml.add(
      canWriteGrid
          ? '<w:tblW w:w="${edges.last - origin}" w:type="dxa"/>'
          : '<w:tblW w:w="0" w:type="auto"/>',
    );
    _xml.add('<w:jc w:val="${_tableJustification(table.alignment)}"/>');
    _xml.add('<w:tblInd w:w="$nativeIndent" w:type="dxa"/>');
    _xml.add('<w:tblLayout w:type="${table.autoFit ? 'autofit' : 'fixed'}"/>');
    _tableCellMargins(tableMargins, _xml, 'tblCellMar');
    _tableLook(firstRow?.styleOptions ?? 0x600, _xml);
    _xml.add('</w:tblPr>');
    if (canWriteGrid) {
      _xml.add('<w:tblGrid>');
      for (var i = 1; i < edges.length; i++) {
        _xml.add('<w:gridCol w:w="${edges[i] - edges[i - 1]}"/>');
      }
      _xml.add('</w:tblGrid>');
    } else {
      _xml.add('<w:tblGrid/>');
    }
    final conditionalFormatting = _tableHeaderHistoryHasConditionalFormatting(
      table,
    );
    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      _countBreak();
      _xml.add('<w:tr>');
      final rowAlignment = row.alignment ?? table.alignment;
      final rowAutoFit = row.autoFit ?? table.autoFit;
      // MS-DOC sprmTCellPaddingDefault is row-wide. The first row supplies
      // tblPr; later defaults belong to tblPrEx, including resets to 108/0.
      final marginExceptions = <LegacyWordBorderSide, int?>{};
      for (final side in const [
        LegacyWordBorderSide.top,
        LegacyWordBorderSide.left,
        LegacyWordBorderSide.bottom,
        LegacyWordBorderSide.right,
      ]) {
        final fallback =
            side == LegacyWordBorderSide.left ||
                side == LegacyWordBorderSide.right
            ? 108
            : 0;
        final before = tableMargins.containsKey(side)
            ? tableMargins[side]
            : fallback;
        final after = row.defaultCellMargins.containsKey(side)
            ? row.defaultCellMargins[side]
            : fallback;
        if (before != after) marginExceptions[side] = after;
      }
      if (row.borders.isNotEmpty ||
          rowAlignment != table.alignment ||
          rowAutoFit != table.autoFit ||
          marginExceptions.isNotEmpty) {
        _xml.add('<w:tblPrEx>');
        if (rowAlignment != table.alignment) {
          _xml.add('<w:jc w:val="${_tableJustification(rowAlignment)}"/>');
        }
        _tableBorders(row.borders, _xml, 'tblBorders');
        if (rowAutoFit != table.autoFit) {
          _xml.add(
            '<w:tblLayout w:type="${rowAutoFit ? 'autofit' : 'fixed'}"/>',
          );
        }
        _tableCellMargins(marginExceptions, _xml, 'tblCellMar');
        _xml.add('</w:tblPrEx>');
      }
      final before = canWriteGrid ? edgeIndices[row.originTwips]! : 0;
      final rowEnd =
          row.originTwips +
          row.cells.fold<int>(0, (sum, cell) => sum + (cell.widthTwips ?? 0));
      final after = canWriteGrid ? edges.length - 1 - edgeIndices[rowEnd]! : 0;
      final headerRequest = row.sourceHeaderRequest ?? row.isHeader;
      if (headerRequest ||
          before != 0 ||
          after != 0 ||
          row.heightTwips != null ||
          row.cantSplit != null ||
          row.formattingRevision != null) {
        _xml.add('<w:trPr>');
        _tableRowProperties(
          LegacyWordTableRowProperties(
            heightTwips: row.heightTwips,
            cantSplit: row.cantSplit,
            isHeader: headerRequest,
          ),
          before: before,
          after: after,
          widthBefore: row.originTwips - origin,
          widthAfter: edges.last - rowEnd,
        );
        _tableRowFormattingRevision(
          row,
          tableStartCp: table.startCp,
          rowIndex: rowIndex,
          gridKnown: canWriteGrid,
          tableHasConditionalFormatting: conditionalFormatting,
          before: before,
          after: after,
          widthBefore: row.originTwips - origin,
          widthAfter: edges.last - rowEnd,
        );
        _xml.add('</w:trPr>');
      }
      var offset = row.originTwips;
      for (final cell in row.cells) {
        _countBreak();
        _count('cells');
        _xml.add('<w:tc><w:tcPr>');
        final width = cell.widthTwips;
        final preference = cell.formatting.preferredWidth;
        if (preference != null) {
          _preferredCellWidth(preference);
        } else if (width != null && width > 0) {
          _xml.add('<w:tcW w:w="$width" w:type="dxa"/>');
        }
        if (width != null && width > 0) {
          if (canWriteGrid) {
            final start = edgeIndices[offset]!;
            final end = edgeIndices[offset + width]!;
            if (end - start > 1) {
              _xml.add('<w:gridSpan w:val="${end - start}"/>');
            }
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
        _tableBorders(cell.formatting.borders, _xml, 'tcBorders');
        if (cell.shading != null) {
          _shading(
            cell.shading!,
            _xml,
            'tableCell',
            cell.blocks.isEmpty ? null : cell.blocks.first.startCp,
          );
        }
        _tableCellFormat(
          cell.formatting,
          _xml,
          includeShading: false,
          includeBorders: false,
        );
        if (cell.formatting.noWrapPreference == true &&
            cell.formatting.noWrap == false) {
          _evidenceRecords.add({
            'kind': 'cellNoWrapWidthContext',
            'tableStartCp': table.startCp,
            'cellStartCp': cell.blocks.firstOrNull?.startCp,
            'sourceNoWrap': true,
            'effectiveNoWrap': false,
            'preferredWidthUnit': preference?.unit.name,
            'preferredWidth': preference?.value,
            'reason':
                'MS-DOC suppresses no-wrap for a dxa preferred width; the source preference remains evidence.',
          });
        }
        _xml.add('</w:tcPr>');
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

  void _tablePosition(
    LegacyWordTablePosition position, {
    required int horizontalOriginTwips,
  }) {
    final x = position.horizontalOffsetTwips, y = position.verticalOffsetTwips;
    final storedX = x == null ? null : x + horizontalOriginTwips + 1;
    if ((x == null) == (position.horizontalPlacement == null) ||
        (y == null) == (position.verticalPlacement == null) ||
        (x != null && (x < -31680 || x > 31680)) ||
        (y != null && (y < -31680 || y > 31680)) ||
        (storedX != null && (storedX < -32768 || storedX > 32767)) ||
        [
          position.leftFromTextTwips,
          position.rightFromTextTwips,
          position.topFromTextTwips,
          position.bottomFromTextTwips,
        ].any((distance) => distance < 0 || distance > 31680)) {
      throw const FormatException('Invalid Word floating-table position.');
    }
    _xml.add(
      '<w:tblpPr w:horzAnchor="${position.horizontalAnchor.name}" '
      'w:vertAnchor="${position.verticalAnchor.name}" '
      'w:leftFromText="${position.leftFromTextTwips}" '
      'w:rightFromText="${position.rightFromTextTwips}" '
      'w:topFromText="${position.topFromTextTwips}" '
      'w:bottomFromText="${position.bottomFromTextTwips}"',
    );
    // MS-OI29500 2.1.162(e): Word stores each absolute OOXML distance plus
    // one twip, just like the MS-DOC XAS/YAS_plusOne source operands. The
    // public model retains the actual signed distance; sentinels stay named.
    _xml.add(
      x == null
          ? ' w:tblpXSpec="${position.horizontalPlacement!.name}"'
          : ' w:tblpX="$storedX"',
    );
    _xml.add(
      y == null
          ? ' w:tblpYSpec="${position.verticalPlacement!.name}"'
          : ' w:tblpY="${y + 1}"',
    );
    _xml.add(
      '/><w:tblOverlap w:val="${position.allowOverlap ? 'overlap' : 'never'}"/>',
    );
  }

  String _tableJustification(LegacyWordAlignment value) => switch (value) {
    LegacyWordAlignment.left => 'left',
    LegacyWordAlignment.center => 'center',
    LegacyWordAlignment.right => 'right',
    _ => throw const FormatException('Invalid Word table alignment.'),
  };

  void _preferredCellWidth(LegacyWordTableWidth value) {
    final unit = value.unit;
    if (value.value < 0 ||
        ((unit == LegacyWordTableWidthUnit.nil ||
                unit == LegacyWordTableWidthUnit.auto) &&
            value.value != 0) ||
        (unit == LegacyWordTableWidthUnit.percent && value.value > 5000) ||
        (unit == LegacyWordTableWidthUnit.twips && value.value > 31680)) {
      throw const FormatException('Invalid Word preferred cell width.');
    }
    final type = switch (unit) {
      LegacyWordTableWidthUnit.nil => 'nil',
      LegacyWordTableWidthUnit.auto => 'auto',
      LegacyWordTableWidthUnit.percent => 'pct',
      LegacyWordTableWidthUnit.twips => 'dxa',
    };
    _xml.add('<w:tcW w:w="${value.value}" w:type="$type"/>');
  }
}
