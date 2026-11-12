// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.4.6.6, StkTableGRLPUPX, CNFOperand and Fatl. Conditional
// formatting order is horizontal bands, vertical bands, columns, rows, corner.
extension _WordTableStyles on _StructuredWordParser {
  int? _resolvedTableStyleId(int? id) {
    if (id == null) return null;
    if (_tableStyles.containsKey(id)) return id;
    // MS-DOC sprmTIstd falls back to the default table style for an invalid
    // reference. An absent default is left unspecified and diagnosed.
    if (_tableStyles.containsKey(11)) return 11;
    warnings.add(LegacyWordWarning.unsupportedFormatting);
    return null;
  }

  List<LegacyWordTableRow> _resolveTableStyleCells(
    List<LegacyWordTableRow> rows,
  ) => [
    for (var r = 0; r < rows.length; r++)
      LegacyWordTableRow(
        isHeader: rows[r].isHeader,
        originTwips: rows[r].originTwips,
        tableStyleId: rows[r].tableStyleId,
        styleOptions: rows[r].styleOptions,
        halfGapTwips: rows[r].halfGapTwips,
        cells: List.unmodifiable([
          for (var c = 0; c < rows[r].cells.length; c++)
            _resolvedTableCell(rows[r], r, rows, c),
        ]),
      ),
  ];

  LegacyWordTableCell _resolvedTableCell(
    LegacyWordTableRow row,
    int r,
    List<LegacyWordTableRow> rows,
    int c,
  ) {
    final cell = row.cells[c];
    var format = _mergeTableCellFormat(
      _mergeTableCellFormat(
        const LegacyWordTableCellFormat(
          margins: {
            LegacyWordBorderSide.top: 0,
            LegacyWordBorderSide.left: 108,
            LegacyWordBorderSide.bottom: 0,
            LegacyWordBorderSide.right: 108,
          },
        ),
        _tableStyleCell(row, r, rows, c),
      ),
      cell.formatting,
    );
    format = _mergeTableCellFormat(
      format,
      LegacyWordTableCellFormat(shading: cell.shading),
    );
    return LegacyWordTableCell(
      paragraphs: cell.paragraphs,
      blocks: cell.blocks,
      widthTwips: cell.widthTwips,
      mergeStart: cell.mergeStart,
      mergeContinue: cell.mergeContinue,
      verticalMergeStart: cell.verticalMergeStart,
      verticalMergeContinue: cell.verticalMergeContinue,
      shading: format.shading,
      formatting: format,
    );
  }

  void _readTableStyles() {
    for (final entry in styles.entries) {
      if (entry.value.kind != 3) continue;
      final raw = entry.value;
      final text = _readTableTextOperations(raw);
      _tableTextOperations[entry.key] = text;
      final conditional =
          <LegacyWordTableCondition, LegacyWordTableCellFormat>{};
      final plain = <_Sprm>[];
      int? rowBand, columnBand;
      for (final operation in raw.table) {
        final value = operation.data;
        if (operation.code == 0xd66a) {
          if (value.length < 2) {
            throw const FormatException(
              'Truncated Word conditional table style.',
            );
          }
          final condition = value.u16(0);
          if (condition == 0 ||
              condition > 0x800 ||
              (condition & (condition - 1)) != 0) {
            throw const FormatException('Invalid Word table style condition.');
          }
          final kind = LegacyWordTableCondition.values[condition.bitLength - 1];
          final nested = _readProperties(value.slice(2, value.length - 2));
          if (nested.any((p) => p.code == 0xd66a)) {
            throw const FormatException('Nested Word table style condition.');
          }
          conditional[kind] = _mergeTableCellFormat(
            conditional[kind] ?? const LegacyWordTableCellFormat(),
            _readTableCellFormat(nested, conditional: true),
          );
        } else if (operation.code == 0x3488 || operation.code == 0x3489) {
          final count = value.u8(0);
          if (count < 1 || count > 3) {
            throw const FormatException('Invalid Word table style band size.');
          }
          if (operation.code == 0x3488) {
            rowBand = count;
          } else {
            columnBand = count;
          }
        } else {
          plain.add(operation);
        }
      }
      _tableStyles[entry.key] = LegacyWordTableStyle(
        id: entry.key,
        name: raw.name,
        basedOn: raw.parent == 0xfff ? null : raw.parent,
        rowBandSize: rowBand,
        columnBandSize: columnBand,
        cell: _readTableCellFormat(plain),
        conditions: Map.unmodifiable(conditional),
        text: _tableTextFormat(text.paragraph, text.character),
        textConditions: Map.unmodifiable({
          for (final condition in {
            ...text.paragraphConditions.keys,
            ...text.characterConditions.keys,
          })
            condition: _tableTextFormat(
              text.paragraphConditions[condition] ?? const [],
              text.characterConditions[condition] ?? const [],
            ),
        }),
      );
    }
    for (final id in _tableStyles.keys) {
      _tableStyleChain(id);
    }
  }

  List<LegacyWordTableStyle> _tableStyleChain(int id) {
    final chain = <LegacyWordTableStyle>[];
    final seen = <int>{};
    int? current = id;
    while (current != null) {
      final style = _tableStyles[current];
      if (style == null || !seen.add(current) || chain.length >= 64) {
        throw const FormatException('Missing or cyclic Word table style.');
      }
      chain.add(style);
      current = style.basedOn;
    }
    return chain.reversed.toList();
  }

  LegacyWordTableCellFormat _readTableCellFormat(
    List<_Sprm> operations, {
    bool conditional = false,
  }) {
    LegacyWordShading? shading;
    LegacyWordCellAlignment? alignment;
    bool? noWrap;
    final margins = <LegacyWordBorderSide, int?>{};
    final borders = <LegacyWordTableBorderSide, LegacyWordBorder>{};
    for (final operation in operations) {
      budget.apply();
      final value = operation.data;
      switch (operation.code) {
        case 0x563a: // Ignored in UpxTapx by specification.
          break;
        case 0xd687:
          shading = _readShading(value, warnings);
        case 0x347c:
          final index = value.u8(0);
          if (index > 2) {
            throw const FormatException('Invalid Word cell alignment.');
          }
          alignment = LegacyWordCellAlignment.values[index];
        case 0x347d:
          noWrap = _boolean(value);
        case 0xd63e:
        case 0xd634:
          final (_, _, decoded) = _readTableMargins(
            value,
            wholeRow: true,
            style: operation.code == 0xd63e,
          );
          margins.addAll(decoded);
        case 0xd605:
        case 0xd613:
          final old = operation.code == 0xd605;
          final width = old ? 4 : 8;
          if (value.length != width * 6) {
            throw const FormatException('Invalid Word style table borders.');
          }
          for (var side = 0; side < 6; side++) {
            borders[LegacyWordTableBorderSide.values[side]] = _readTableBorder(
              _Bytes(value.slice(side * width, width)),
              old: old,
            );
          }
        case 0xd47f:
        case >= 0xd680 && <= 0xd686:
          if (!conditional) {
            throw const FormatException(
              'Conditional Word cell border outside condition.',
            );
          }
          final side = switch (operation.code) {
            0xd47f => LegacyWordTableBorderSide.top,
            0xd680 => LegacyWordTableBorderSide.bottom,
            0xd681 => LegacyWordTableBorderSide.left,
            0xd682 => LegacyWordTableBorderSide.right,
            0xd683 => LegacyWordTableBorderSide.insideH,
            0xd684 => LegacyWordTableBorderSide.insideV,
            0xd685 => LegacyWordTableBorderSide.tl2br,
            _ => LegacyWordTableBorderSide.tr2bl,
          };
          borders[side] = _readTableBorder(value);
        default:
          warnings.add(LegacyWordWarning.unsupportedFormatting);
      }
    }
    return LegacyWordTableCellFormat(
      shading: shading,
      borders: Map.unmodifiable(borders),
      verticalAlignment: alignment,
      noWrap: noWrap,
      margins: Map.unmodifiable(margins),
    );
  }

  LegacyWordTableCellFormat _tableStyleCell(
    LegacyWordTableRow row,
    int rowIndex,
    List<LegacyWordTableRow> rows,
    int column,
  ) {
    final id = row.tableStyleId;
    if (id == null) return const LegacyWordTableCellFormat();
    final chain = _tableStyleChain(id);
    var value = const LegacyWordTableCellFormat();
    for (final style in chain) {
      value = _mergeTableCellFormat(value, style.cell);
    }
    final conditions = _tableStyleConditions(row, rowIndex, rows, column);
    final baseBorders = value.borders;
    value = LegacyWordTableCellFormat(
      shading: value.shading,
      verticalAlignment: value.verticalAlignment,
      noWrap: value.noWrap,
      margins: value.margins,
      borders: Map.unmodifiable({
        if (baseBorders[rowIndex == 0
                ? LegacyWordTableBorderSide.top
                : LegacyWordTableBorderSide.insideH]
            case final border?)
          LegacyWordTableBorderSide.top: border,
        if (baseBorders[rowIndex == rows.length - 1
                ? LegacyWordTableBorderSide.bottom
                : LegacyWordTableBorderSide.insideH]
            case final border?)
          LegacyWordTableBorderSide.bottom: border,
        if (baseBorders[column == 0
                ? LegacyWordTableBorderSide.left
                : LegacyWordTableBorderSide.insideV]
            case final border?)
          LegacyWordTableBorderSide.left: border,
        if (baseBorders[column == row.cells.length - 1
                ? LegacyWordTableBorderSide.right
                : LegacyWordTableBorderSide.insideV]
            case final border?)
          LegacyWordTableBorderSide.right: border,
      }),
    );
    for (final condition in conditions) {
      for (final style in chain) {
        final rule = style.conditions[condition];
        if (rule != null) value = _mergeTableCellFormat(value, rule);
      }
    }
    return value;
  }

  List<LegacyWordTableCondition> _tableStyleConditions(
    LegacyWordTableRow row,
    int rowIndex,
    List<LegacyWordTableRow> rows,
    int column,
  ) {
    final options = row.styleOptions;
    var rowBand = 1, colBand = 1;
    for (final style in _tableStyleChain(row.tableStyleId!)) {
      rowBand = style.rowBandSize ?? rowBand;
      colBand = style.columnBandSize ?? colBand;
    }
    final firstRow = (options & 0x20) != 0 && (rowIndex == 0 || row.isHeader);
    final lastRow =
        (options & 0x40) != 0 && rowIndex == rows.length - 1 && !firstRow;
    final firstCol = (options & 0x80) != 0 && column == 0;
    final lastCol =
        (options & 0x100) != 0 && column == row.cells.length - 1 && !firstCol;
    final excludedRows = (options & 0x20) == 0
        ? 0
        : rows
              .take(rowIndex)
              .indexed
              .where((p) => p.$1 == 0 || p.$2.isHeader)
              .length;
    return <LegacyWordTableCondition>[
      if (!firstRow && !lastRow && (options & 0x200) == 0)
        ((rowIndex - excludedRows) ~/ rowBand).isEven
            ? LegacyWordTableCondition.band1Horz
            : LegacyWordTableCondition.band2Horz,
      if (!firstCol && !lastCol && (options & 0x400) == 0)
        ((column - ((options & 0x80) != 0 ? 1 : 0)) ~/ colBand).isEven
            ? LegacyWordTableCondition.band1Vert
            : LegacyWordTableCondition.band2Vert,
      if (firstCol) LegacyWordTableCondition.firstCol,
      if (lastCol) LegacyWordTableCondition.lastCol,
      if (firstRow) LegacyWordTableCondition.firstRow,
      if (lastRow) LegacyWordTableCondition.lastRow,
      if (rowIndex == 0 && firstRow && firstCol)
        LegacyWordTableCondition.nwCell,
      if (rowIndex == 0 && firstRow && lastCol) LegacyWordTableCondition.neCell,
      if (rowIndex == rows.length - 1 && lastRow && firstCol)
        LegacyWordTableCondition.swCell,
      if (rowIndex == rows.length - 1 && lastRow && lastCol)
        LegacyWordTableCondition.seCell,
    ];
  }
}

LegacyWordBorder _readTableBorder(_Bytes value, {bool old = false}) {
  if ((old && value.u32(0) == 0xffffffff) ||
      (!old && value.u32(4) == 0xffffffff)) {
    return const LegacyWordBorder(style: 'nil', widthEighthPoints: 0);
  }
  return _readParagraphBorder(value, old: old);
}

LegacyWordTableCellFormat _mergeTableCellFormat(
  LegacyWordTableCellFormat base,
  LegacyWordTableCellFormat overlay,
) => LegacyWordTableCellFormat(
  shading: overlay.shading?.pattern == 'nil'
      ? base.shading ?? overlay.shading
      : overlay.shading ?? base.shading,
  borders: Map.unmodifiable({...base.borders, ...overlay.borders}),
  verticalAlignment: overlay.verticalAlignment ?? base.verticalAlignment,
  noWrap: overlay.noWrap ?? base.noWrap,
  margins: Map.unmodifiable({...base.margins, ...overlay.margins}),
);

(int, int, Map<LegacyWordBorderSide, int?>) _readTableMargins(
  _Bytes value, {
  bool wholeRow = false,
  bool style = false,
}) {
  if (value.length != 6) {
    throw const FormatException('Invalid Word cell margin size.');
  }
  final first = value.u8(0),
      limit = value.u8(1),
      sides = value.u8(2),
      unit = value.u8(3),
      width = value.u16(4);
  if (first >= 63 ||
      limit > 63 ||
      limit < first ||
      sides > 15 ||
      (wholeRow && (first != 0 || limit != 1)) ||
      (unit != 3 && (style || unit != 0)) ||
      width > 31680 ||
      (unit == 0 && width != 0)) {
    throw const FormatException('Invalid Word cell margins.');
  }
  return (
    first,
    limit,
    Map.unmodifiable({
      for (var side = 0; side < 4; side++)
        if ((sides & (1 << side)) != 0)
          LegacyWordBorderSide.values[side]: unit == 0 ? null : width,
    }),
  );
}
