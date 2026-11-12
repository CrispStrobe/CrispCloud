// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.4.6.6: table style, conditional regions, paragraph style, direct
// paragraph properties, list properties, then character properties. Table
// position is determined before parsing runs; a later TTP mark must not cause
// a second pass through fields, revision anchors or media occurrences.
class _ParagraphInput {
  const _ParagraphInput(
    this.start,
    this.contentEnd,
    this.end,
    this.terminator,
    this.papx,
    this.prm,
    this.styleIndex,
    this.resolved,
    this.properties,
  );
  final int start, contentEnd, end, terminator, styleIndex;
  final _FkpRun papx;
  final List<_Sprm> prm;
  final _ResolvedStyle resolved;
  final _Props properties;
  _Paragraph get structural => _Paragraph(
    LegacyWordParagraph(startCp: start, endCp: end, runs: const []),
    properties,
    terminator,
  );
}

class _TableStyleDefinition {
  const _TableStyleDefinition(
    this.paragraph,
    this.character,
    this.table,
    this.paragraphConditions,
    this.characterConditions,
    this.tableConditions,
  );
  final List<_Sprm> paragraph, character, table;
  final Map<int, List<_Sprm>> paragraphConditions,
      characterConditions,
      tableConditions;
  static const empty = _TableStyleDefinition([], [], [], {}, {}, {});
}

class _TableCellContext {
  const _TableCellContext(
    this.paragraph,
    this.character,
    this.table,
    this.flags,
  );
  final _Props paragraph, character, table;
  final int flags;
}

class _TableContexts {
  final paragraphs = <int, _TableCellContext>{};
  final rows = <int, List<_TableCellContext>>{};
}

const _tableConditions = <int>[
  0x40,
  0x80,
  0x10,
  0x20,
  4,
  8,
  1,
  2,
  0x100,
  0x200,
  0x400,
  0x800,
];

extension _WordTableStyles on _StructuredWordParser {
  _ParagraphInput _paragraphInput(
    int start,
    int contentEnd,
    int end,
    int term,
  ) {
    final cp = end > start ? end - 1 : start;
    final piece = source.pieceAt(cp);
    final papx = paragraphFormatting.at(piece.fc(cp));
    final prm = _pieceProperties(piece);
    final initial = _resolveStyle(papx.styleIndex);
    final properties = <String, Object?>{
      ...initial.paragraph,
      'styleIndex': papx.styleIndex,
    };
    // PIstd resets formatting at its actual position. Moving it before the
    // operation stream would destroy pre-wall formatting revision snapshots.
    _applyParagraph(
      [...papx.operations, ...prm],
      properties,
      budget,
      warnings,
      resolveParagraphStyle: (index) => _resolveStyle(index).paragraph,
    );
    final styleIndex = properties['styleIndex'] as int? ?? papx.styleIndex;
    final resolved = _resolveStyle(styleIndex);
    return _ParagraphInput(
      start,
      contentEnd,
      end,
      term,
      papx,
      prm,
      styleIndex,
      resolved,
      properties,
    );
  }

  _TableStyleDefinition _tableStyle(int requested, [int depth = 0]) {
    final index = styles[requested]?.kind == 3 ? requested : 11;
    final cached = _tableStyles[index];
    if (cached != null) return cached;
    final style = styles[index];
    if (style == null || style.kind != 3) return _TableStyleDefinition.empty;
    if (depth > 64 || !_tableStyleActive.add(index)) {
      throw const FormatException('Cyclic or excessive Word table styles.');
    }
    final parent = style.parent == 0xfff
        ? _TableStyleDefinition.empty
        : _tableStyle(style.parent, depth + 1);
    (List<_Sprm>, Map<int, List<_Sprm>>) collect(
      List<_Sprm> inherited,
      Map<int, List<_Sprm>> conditions,
      List<_Sprm> own,
      int group,
      int conditionalCode,
    ) {
      final base = <_Sprm>[...inherited];
      final conditional = <int, List<_Sprm>>{
        for (final e in conditions.entries) e.key: [...e.value],
      };
      for (final op in own) {
        budget.apply();
        if (op.group != group) {
          throw const FormatException(
            'Invalid Word table-style property group.',
          );
        }
        if (op.code == conditionalCode) {
          final condition = op.data.u16(0);
          if (!_tableConditions.contains(condition)) {
            throw const FormatException('Invalid Word table-style condition.');
          }
          final values = _decodeSprms(
            op.data.slice(2, op.data.length - 2),
            budget,
          );
          for (final value in values) {
            _validateTableStyleOperation(value, group, conditional: true);
          }
          conditional.putIfAbsent(condition, () => []).addAll(values);
        } else {
          _validateTableStyleOperation(op, group);
          if (op.code != 0x563a) base.add(op); // TIstd in TAPX is ignored.
        }
      }
      return (
        List.unmodifiable(base),
        {
          for (final e in conditional.entries)
            e.key: List.unmodifiable(e.value),
        },
      );
    }

    final p = collect(
      parent.paragraph,
      parent.paragraphConditions,
      style.paragraph,
      1,
      0xc666,
    );
    final c = collect(
      parent.character,
      parent.characterConditions,
      style.character,
      2,
      0xca85,
    );
    final t = collect(
      parent.table,
      parent.tableConditions,
      style.table,
      5,
      0xd66a,
    );
    _tableStyleActive.remove(index);
    return _tableStyles[index] = _TableStyleDefinition(
      p.$1,
      c.$1,
      t.$1,
      p.$2,
      c.$2,
      t.$2,
    );
  }

  _TableContexts _tableContexts(List<_ParagraphInput> inputs) {
    final result = _TableContexts();
    final byEnd = {for (final input in inputs) input.end: input};
    final structural = _assembleTables([for (final p in inputs) p.structural]);
    void visit(List<LegacyWordBlock> blocks, int depth) {
      if (depth > 63) {
        throw const FormatException('Word tables are nested too deeply.');
      }
      for (final block in blocks) {
        if (block is! LegacyWordTable) continue;
        var headerRows = 0;
        while (headerRows < block.rows.length &&
            block.rows[headerRows].isHeader) {
          headerRows++;
        }
        for (var r = 0; r < block.rows.length; r++) {
          final row = block.rows[r];
          final input = byEnd[row.endCp]!;
          final direct = input.properties;
          final id = direct['tableStyle'] as int?;
          final style = id == null
              ? _TableStyleDefinition.empty
              : _tableStyle(id);
          final tableBase = <String, Object?>{};
          _applyParagraph(style.table, tableBase, budget, warnings);
          final look = LegacyWordTableLook(
            flags: direct['tableLook'] as int? ?? 0,
          );
          final rowBand = tableBase['rowBand'] as int? ?? 0;
          final columnBand = tableBase['columnBand'] as int? ?? 0;
          final contexts = <_TableCellContext>[];
          for (var c = 0; c < row.cells.length; c++) {
            final flags = _conditionalTableFlags(
              look,
              r,
              c,
              block.rows.length,
              row.cells.length,
              headerRows,
              rowBand,
              columnBand,
            );
            final paragraph = <String, Object?>{};
            final character = <String, Object?>{};
            final table = <String, Object?>{
              ...tableBase,
              'rowIndex': r,
              'rowCount': block.rows.length,
            };
            _applyParagraph(style.paragraph, paragraph, budget, warnings);
            _applyCharacter(
              style.character,
              character,
              const {},
              budget,
              warnings,
            );
            for (final flag in _tableConditions) {
              if (flags & flag == 0) continue;
              _applyParagraph(
                style.paragraphConditions[flag] ?? const [],
                paragraph,
                budget,
                warnings,
              );
              _applyCharacter(
                style.characterConditions[flag] ?? const [],
                character,
                Map.of(character),
                budget,
                warnings,
              );
              _applyParagraph(
                style.tableConditions[flag] ?? const [],
                table,
                budget,
                warnings,
              );
            }
            final context = _TableCellContext(
              paragraph,
              character,
              table,
              flags,
            );
            contexts.add(context);
            for (final child in row.cells[c].blocks) {
              if (child is LegacyWordParagraph) {
                result.paragraphs[child.startCp] = context;
              } else if (child is LegacyWordTable) {
                visit([child], depth + 1);
              }
            }
          }
          result.rows[input.end] = contexts;
        }
      }
    }

    visit(structural, 0);
    return result;
  }
}

void _validateTableStyleOperation(
  _Sprm op,
  int group, {
  bool conditional = false,
}) {
  if (op.group != group || const {0xc666, 0xca85, 0xd66a}.contains(op.code)) {
    throw const FormatException('Invalid nested Word table-style condition.');
  }
  // Structural and indirect properties are forbidden in style UPX. Keeping
  // them out also prevents a style from changing table depth or resolving an
  // attacker-controlled Data-stream offset while applying each table cell.
  final forbidden = switch (group) {
    1 => const {
      0x4600,
      0xc601,
      0x2602,
      0x2416,
      0x2417,
      0x6649,
      0x664a,
      0x244b,
      0x244c,
      0x6645,
      0x6646,
      0x646b,
      0xc615,
    },
    2 => const {0x4a30, 0xca31, 0x6a03, 0x0806, 0x080a, 0x0855, 0x0856},
    _ => const {
      0x9601,
      0xd608,
      0xd609,
      0xd60c,
      0xd612,
      0xd616,
      0xf618,
      0x3619,
      0xd620,
      0x7621,
      0x5622,
      0x7623,
      0x5624,
      0x5625,
      0x7629,
      0xd62b,
      0xd62c,
      0xd62f,
      0xd632,
      0xd635,
      0xf636,
      0xd639,
      0x560b,
      0x5664,
      0x3465,
      0xd670,
      0xd671,
      0xd672,
      0x9407,
      0x360d,
      0x940e,
      0x940f,
      0x9410,
      0x9411,
      0x941e,
      0x941f,
    },
  };
  if (forbidden.contains(op.code) ||
      (!conditional &&
          (op.code == 0xd47f || (op.code >= 0xd680 && op.code <= 0xd684)))) {
    throw const FormatException('Forbidden Word table-style property.');
  }
}

int _conditionalTableFlags(
  LegacyWordTableLook look,
  int row,
  int column,
  int rows,
  int columns,
  int headers,
  int rowBand,
  int columnBand,
) {
  final firstRow = look.firstRow && (row == 0 || row < headers);
  final lastRow = look.lastRow && row == rows - 1 && !firstRow;
  final firstColumn = look.firstColumn && column == 0;
  final lastColumn = look.lastColumn && column == columns - 1 && !firstColumn;
  var result =
      (firstRow ? 1 : 0) |
      (lastRow ? 2 : 0) |
      (firstColumn ? 4 : 0) |
      (lastColumn ? 8 : 0);
  if (!firstRow && !lastRow && !look.noRowBands && rowBand != 0) {
    final offset = row - (look.firstRow ? (headers > 0 ? headers : 1) : 0);
    result |= (offset ~/ rowBand).isEven ? 0x40 : 0x80;
  }
  if (!firstColumn && !lastColumn && !look.noColumnBands && columnBand != 0) {
    final offset = column - (look.firstColumn ? 1 : 0);
    result |= (offset ~/ columnBand).isEven ? 0x10 : 0x20;
  }
  if (row == 0 && firstColumn && look.firstRow) {
    result |= 0x200;
  } else if (row == 0 && lastColumn && look.firstRow) {
    result |= 0x100;
  } else if (row == rows - 1 && firstColumn && look.lastRow) {
    result |= 0x800;
  } else if (row == rows - 1 && lastColumn && look.lastRow) {
    result |= 0x400;
  }
  return result;
}

bool _applyTableProperty(
  _Sprm op,
  _Props output,
  _Budget budget,
  Set<LegacyWordWarning> warnings,
) {
  final value = op.data;
  switch (op.code) {
    case 0x563a:
      // TIstd replaces table properties with the selected style. Paragraph
      // properties and the explicitly exempt row/direction/position values
      // survive. Conditional style values are resolved after row grouping.
      for (final key in const [
        'rowLeft',
        'rowLeftOperand',
        'rowCantSplit',
        'rowHeader',
        'tableDefinition',
        'tableGroup',
        'tableAlignment',
        'tablePhysicalAlignment',
        'styleCellAlignment',
        'rowBand',
        'columnBand',
        'styleCellShading',
        'tableShading',
        'defaultCellMargins',
        'styleCellMargins',
        'cellMargins',
        'cellBorders',
        'cellAlignment',
        'tableBorders',
        'conditionalBorders',
        'cellShading',
        'rawShadingInheritance',
      ]) {
        output.remove(key);
      }
      output['tableStyle'] = value.u16(0);
    case 0x7469:
      output['tableGroup'] = value.u32(0);
    case 0x740a:
      output['tableLook'] = value.u16(2) & 0x7ff;
    case 0x560b:
    case 0x5664:
      final flag = value.u16(0);
      if (flag > 1) {
        throw const FormatException('Invalid Word table direction.');
      }
      output[op.code == 0x560b ? 'tableRtl' : 'tableRtl90'] = flag != 0;
    case 0x5400:
    case 0x548a:
      final alignment = value.u16(0);
      if (alignment > 2) {
        throw const FormatException('Invalid Word table alignment.');
      }
      output[op.code == 0x5400 ? 'tablePhysicalAlignment' : 'tableAlignment'] =
          alignment;
    case 0x3466:
      output['rowCantSplit'] = _boolean(value);
    case 0x3615:
      output['tableAutoFit'] = _boolean(value);
    case 0x3403:
      break; // Obsolete TFCantSplit90 is ignored in favour of 3466.
    case 0x9407:
      output['rowHeight'] = value.i16(0);
    case 0x9601:
      output['rowLeftOperand'] = value.i16(0);
      output['rowLeft'] = value.i16(0) - (output['halfGap'] as int? ?? 0);
    case 0x9602:
      final gap = value.i16(0);
      if (gap < 0) throw const FormatException('Invalid Word table half gap.');
      output['halfGap'] = gap;
      if (output['rowLeftOperand'] case final int origin) {
        output['rowLeft'] = origin - gap;
      }
    case 0x360d:
    case 0x3465:
    case 0x940e:
    case 0x940f:
    case 0x9410:
    case 0x9411:
    case 0x941e:
    case 0x941f:
      output['tablePosition${op.code}'] = value.bytes.fold<int>(
        0,
        (a, b) => a * 256 + b,
      );
      warnings.add(LegacyWordWarning.unsupportedFormatting);
    case 0x7621:
    case 0x5622:
    case 0x7623:
    case 0x5624:
    case 0x5625:
      _changeTableCells(op, output);
    case 0x347c:
      final align = value.u8(0);
      if (align > 2) {
        throw const FormatException('Invalid Word cell alignment.');
      }
      output['styleCellAlignment'] = align;
    case 0x3488:
    case 0x3489:
      final count = value.u8(0);
      if (count < 1 || count > 3) {
        throw const FormatException('Invalid Word table band size.');
      }
      output[op.code == 0x3488 ? 'rowBand' : 'columnBand'] = count;
    case 0xd687:
      output['styleCellShading'] = _readShading(value, warnings);
    case 0xd660:
      output['tableShading'] = _readShading(value, warnings);
      // Retained separately from cell shading: it is the table backdrop,
      // which cannot be substituted for a transparent or patterned cell.
      warnings.add(LegacyWordWarning.unsupportedFormatting);
    case 0xd632:
    case 0xd634:
    case 0xd63e:
      _applyCellMargins(op, output);
    case 0xd620:
    case 0xd62f:
      final old = op.code == 0xd620;
      if (value.length != (old ? 7 : 11)) {
        throw const FormatException('Invalid Word cell-border range.');
      }
      final (first, limit) = _tableCellRange(value, output);
      final mask = value.u8(2);
      if (mask & ~0x3f != 0) {
        throw const FormatException('Invalid Word cell-border sides.');
      }
      final border = _tableBorder(
        _Bytes(value.slice(3, old ? 4 : 8)),
        old: old,
      );
      final cells = <int, Map<LegacyWordCellBorderSide, LegacyWordBorder>>{
        ...?output['cellBorders']
            as Map<int, Map<LegacyWordCellBorderSide, LegacyWordBorder>>?,
      };
      for (var cell = first; cell < limit; cell++) {
        budget.apply();
        cells[cell] = {
          ...?cells[cell],
          for (var side = 0; side < 4; side++)
            if (mask & (1 << side) != 0)
              LegacyWordCellBorderSide.values[side]: border,
        };
      }
      if (mask & 0x30 != 0) {
        warnings.add(LegacyWordWarning.unsupportedFormatting);
      }
      output['cellBorders'] = cells;
    case 0xd62c:
      if (value.length != 3 ||
          value.u8(0) >= value.u8(1) ||
          value.u8(1) > 63 ||
          value.u8(2) > 2) {
        throw const FormatException('Invalid Word cell-alignment range.');
      }
      _tableCellRange(value, output);
      output['cellAlignment'] = <int, int>{
        ...?output['cellAlignment'] as Map<int, int>?,
        for (var i = value.u8(0); i < value.u8(1); i++) i: value.u8(2),
      };
    case 0xd605:
    case 0xd613:
      final old = op.code == 0xd605;
      final width = old ? 4 : 8;
      if (value.length != width * 6) {
        throw const FormatException('Invalid Word table borders.');
      }
      output['tableBorders'] = <int, LegacyWordBorder>{
        for (var i = 0; i < 6; i++)
          if (!_nilTableBorder(value.slice(i * width, width)))
            i: _readParagraphBorder(
              _Bytes(value.slice(i * width, width)),
              old: old,
            ),
      };
    case 0xd47f:
    case >= 0xd680 && <= 0xd686:
      if (value.length != 8) {
        throw const FormatException('Invalid Word conditional border operand.');
      }
      final side = op.code == 0xd47f ? 0 : op.code - 0xd680 + 1;
      // Style order: top, bottom, left, right, insideH, insideV, diagonals.
      output['conditionalBorders'] = <int, LegacyWordBorder>{
        ...?output['conditionalBorders'] as Map<int, LegacyWordBorder>?,
        if (!_nilTableBorder(value.bytes)) side: _readParagraphBorder(value),
      };
    default:
      return false;
  }
  return true;
}

bool _nilTableBorder(Uint8List bytes) => bytes.every((value) => value == 255);

LegacyWordBorder _tableBorder(_Bytes bytes, {bool old = false}) {
  if (bytes.length != (old ? 4 : 8)) {
    throw const FormatException('Invalid Word table border operand.');
  }
  if (_nilTableBorder(bytes.bytes)) {
    return const LegacyWordBorder(
      style: 'nil',
      rawType: 255,
      widthEighthPoints: 2,
    );
  }
  return _readParagraphBorder(bytes, old: old);
}

(int, int) _tableCellRange(_Bytes value, _Props output) {
  final first = value.u8(0), limit = value.u8(1);
  final count =
      (output['tableDefinition'] as _TableDefinition?)?.flags.length ?? 0;
  if (first >= limit || limit > count) {
    throw const FormatException('Invalid Word table cell range.');
  }
  return (first, limit);
}

void _changeTableCells(_Sprm op, _Props output) {
  final previous =
      output['tableDefinition'] as _TableDefinition? ??
      const _TableDefinition([0], []);
  final widths = [
    for (var i = 0; i < previous.flags.length; i++)
      previous.edges[i + 1] - previous.edges[i],
  ];
  final flags = [...previous.flags];
  final borders = [
    for (var i = 0; i < flags.length; i++)
      i < previous.borders.length
          ? previous.borders[i]
          : <LegacyWordCellBorderSide, LegacyWordBorder>{},
  ];
  final inherited = [
    for (var i = 0; i < flags.length; i++)
      i < previous.styleDefaults.length && previous.styleDefaults[i],
  ];
  final value = op.data;
  if (op.code == 0x7621) {
    final first = value.u8(0), count = value.u8(1), width = value.i16(2);
    if (first > flags.length ||
        count == 0 ||
        count + flags.length > 63 ||
        width < 0) {
      throw const FormatException('Invalid Word table insertion.');
    }
    widths.insertAll(first, List.filled(count, width));
    flags.insertAll(first, List.filled(count, 0));
    inherited.insertAll(first, List.filled(count, true));
    borders.insertAll(
      first,
      List.generate(
        count,
        (_) => <LegacyWordCellBorderSide, LegacyWordBorder>{},
      ),
    );
    _shiftTableCellOverrides(output, first, 0, count);
  } else {
    final (first, limit) = _tableCellRange(value, output);
    if (op.code == 0x5622) {
      if (limit - first == flags.length) {
        throw const FormatException('Word table deletion removes every cell.');
      }
      widths.removeRange(first, limit);
      flags.removeRange(first, limit);
      borders.removeRange(first, limit);
      inherited.removeRange(first, limit);
      _shiftTableCellOverrides(output, first, limit - first, 0);
    } else if (op.code == 0x7623) {
      final width = value.i16(2);
      if (width < 0) {
        throw const FormatException('Invalid Word table column width.');
      }
      for (var i = first; i < limit; i++) {
        widths[i] = width;
      }
    } else {
      for (var i = first; i < limit; i++) {
        flags[i] =
            (flags[i] & ~3) |
            (op.code == 0x5625
                ? 0
                : i == first
                ? 2
                : 1);
      }
    }
  }
  final edges = <int>[previous.edges.first];
  for (final width in widths) {
    edges.add(edges.last + width);
  }
  if (edges.last - edges.first > 31680 ||
      edges.any((x) => x < -31680 || x > 31680)) {
    throw const FormatException('Word table width exceeds the allowed range.');
  }
  output['tableDefinition'] = _TableDefinition(
    edges,
    flags,
    borders: borders,
    styleDefaults: inherited,
  );
  output.putIfAbsent('rowLeft', () => edges.first);
}

void _shiftTableCellOverrides(
  _Props output,
  int first,
  int removed,
  int inserted,
) {
  if (output['rawShadingInheritance'] case final Set<int> values) {
    output['rawShadingInheritance'] = <int>{
      for (final index in values)
        if (index < first)
          index
        else if (index >= first + removed)
          index + inserted - removed,
    };
  }
  for (final key in [
    'cellShading',
    'cellAlignment',
    'cellBorders',
    'cellMargins',
  ]) {
    final values = output[key];
    if (values is! Map) continue;
    // Preserve the concrete map value types used by the property application.
    final moved = <int, Object?>{};
    for (final entry in values.entries) {
      final index = entry.key as int;
      if (index < first) {
        moved[index] = entry.value;
      } else if (index >= first + removed) {
        moved[index + inserted - removed] = entry.value;
      }
    }
    output[key] = switch (key) {
      'cellShading' => moved.cast<int, LegacyWordShading>(),
      'cellAlignment' => moved.cast<int, int>(),
      'cellBorders' =>
        moved.cast<int, Map<LegacyWordCellBorderSide, LegacyWordBorder>>(),
      _ => moved.cast<int, Map<LegacyWordCellBorderSide, int>>(),
    };
  }
}

void _applyCellMargins(_Sprm op, _Props output) {
  final value = op.data;
  if (value.length != 6) {
    throw const FormatException('Invalid Word cell-margin operand.');
  }
  final first = value.u8(0),
      limit = value.u8(1),
      mask = value.u8(2),
      unit = value.u8(3);
  final width = value.i16(4);
  final all = op.code != 0xd632;
  if (mask & ~15 != 0 ||
      (unit != 0 && unit != 3) ||
      (unit == 3 && (width < 0 || width > 31680)) ||
      (all && (first != 0 || limit != 1)) ||
      (op.code == 0xd63e && unit != 3)) {
    throw const FormatException('Invalid Word cell margins.');
  }
  final updates = <LegacyWordCellBorderSide, int>{
    if (unit == 3)
      for (var side = 0; side < 4; side++)
        if (mask & (1 << side) != 0)
          LegacyWordCellBorderSide.values[side]: width,
  };
  if (all) {
    final key = op.code == 0xd63e ? 'styleCellMargins' : 'defaultCellMargins';
    final values = <LegacyWordCellBorderSide, int>{
      ...?output[key] as Map<LegacyWordCellBorderSide, int>?,
      ...updates,
    };
    if (unit == 0) {
      values.removeWhere((side, _) => mask & (1 << side.index) != 0);
    }
    output[key] = values;
  } else {
    _tableCellRange(value, output);
    final values = <int, Map<LegacyWordCellBorderSide, int>>{
      ...?output['cellMargins']
          as Map<int, Map<LegacyWordCellBorderSide, int>>?,
    };
    for (var i = first; i < limit; i++) {
      final margins = <LegacyWordCellBorderSide, int>{
        ...?values[i],
        ...updates,
      };
      if (unit == 0) {
        margins.removeWhere((side, _) => mask & (1 << side.index) != 0);
      }
      values[i] = margins;
    }
    output['cellMargins'] = values;
  }
}

Map<LegacyWordCellBorderSide, int> _resolvedCellMargins(
  _Props direct,
  _TableCellContext? style,
  int cell,
) => Map.unmodifiable({
  LegacyWordCellBorderSide.top: 0,
  LegacyWordCellBorderSide.left: 108,
  LegacyWordCellBorderSide.bottom: 0,
  LegacyWordCellBorderSide.right: 108,
  ...?direct['defaultCellMargins'] as Map<LegacyWordCellBorderSide, int>?,
  ...?style?.table['styleCellMargins'] as Map<LegacyWordCellBorderSide, int>?,
  ...?(direct['cellMargins']
      as Map<int, Map<LegacyWordCellBorderSide, int>>?)?[cell],
});

LegacyWordShading? _resolvedCellShading(
  _Props direct,
  _TableCellContext? style,
  int cell,
) {
  final value = (direct['cellShading'] as Map<int, LegacyWordShading>?)?[cell];
  if (value != null &&
      !(direct['rawShadingInheritance'] as Set<int>? ?? const {}).contains(
        cell,
      )) {
    return value;
  }
  return style?.table['styleCellShading'] as LegacyWordShading?;
}

Map<LegacyWordCellBorderSide, LegacyWordBorder> _resolvedCellBorders(
  _Props direct,
  _TableCellContext? style,
  int cell,
  int cells,
  bool firstRow,
) {
  final result = <LegacyWordCellBorderSide, LegacyWordBorder>{};
  final table = <int, LegacyWordBorder>{
    ...?style?.table['tableBorders'] as Map<int, LegacyWordBorder>?,
    ...?direct['tableBorders'] as Map<int, LegacyWordBorder>?,
  };
  void put(LegacyWordCellBorderSide side, LegacyWordBorder? value) {
    if (value != null) result[side] = value;
  }

  put(LegacyWordCellBorderSide.top, table[firstRow ? 0 : 4]);
  final lastRow =
      style?.table['rowIndex'] == (style?.table['rowCount'] as int? ?? 0) - 1;
  put(LegacyWordCellBorderSide.bottom, table[lastRow ? 2 : 4]);
  put(LegacyWordCellBorderSide.left, table[cell == 0 ? 1 : 5]);
  put(LegacyWordCellBorderSide.right, table[cell == cells - 1 ? 3 : 5]);
  final conditional =
      style?.table['conditionalBorders'] as Map<int, LegacyWordBorder>?;
  if (conditional != null) {
    put(LegacyWordCellBorderSide.top, conditional[0]);
    put(LegacyWordCellBorderSide.bottom, conditional[1]);
    put(LegacyWordCellBorderSide.left, conditional[2]);
    put(LegacyWordCellBorderSide.right, conditional[3]);
    if (!lastRow) put(LegacyWordCellBorderSide.bottom, conditional[4]);
    if (cell != cells - 1) put(LegacyWordCellBorderSide.right, conditional[5]);
    put(LegacyWordCellBorderSide.diagonalDown, conditional[6]);
    put(LegacyWordCellBorderSide.diagonalUp, conditional[7]);
  }
  final definition = direct['tableDefinition'] as _TableDefinition?;
  if (definition != null && cell < definition.borders.length) {
    result.addAll(definition.borders[cell]);
  }
  result.addAll(
    (direct['cellBorders']
            as Map<
              int,
              Map<LegacyWordCellBorderSide, LegacyWordBorder>
            >?)?[cell] ??
        const {},
  );
  return Map.unmodifiable(result);
}

bool _sameTableRows(_Props left, _Props right) {
  if (left['tableStyle'] != right['tableStyle'] ||
      left['tableGroup'] != right['tableGroup'] ||
      ((left['tableRtl'] == true || left['tableRtl90'] == true) !=
          (right['tableRtl'] == true || right['tableRtl90'] == true))) {
    return false;
  }
  for (final code in [
    0x360d,
    0x3465,
    0x940e,
    0x940f,
    0x9410,
    0x9411,
    0x941e,
    0x941f,
  ]) {
    if ((left['tablePosition$code'] ?? 0) !=
        (right['tablePosition$code'] ?? 0)) {
      return false;
    }
  }
  return true;
}
