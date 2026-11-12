// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC UpxTapx/UpxPapx/UpxChpx forbid structural and indirect properties
// within style differences. Decode them without following Data references.
// Other unsupported visual properties retain the existing diagnostic path.
void _validateTableStyleOperation(
  _Sprm operation,
  int group, {
  int? styleId,
  bool conditional = false,
}) {
  final code = operation.code;
  if (operation.group != group ||
      (conditional && const {0xc666, 0xca85, 0xd66a}.contains(code))) {
    throw const FormatException('Invalid Word table-style property group.');
  }
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
    },
    2 => const {0x4a30, 0xca31, 0x6a03, 0x0806, 0x080a, 0x0855, 0x0856},
    _ => const {
      0x9601,
      0xd606,
      0xd608,
      0xd609,
      0xd60c,
      0xd612,
      0xd616,
      0xf618,
      0x3619,
      0xd61a,
      0xd61b,
      0xd61c,
      0xd61d,
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
      0xd642,
      0xd660,
      0xd662,
      0x560b,
      0x5664,
      0x3465,
      0x7469,
      0xd670,
      0xd671,
      0xd672,
      0x9407,
      0x9602,
      0xf614,
      0x3615,
      0x360d,
      0x940e,
      0x940f,
      0x9410,
      0x9411,
      0x941e,
      0x941f,
      0xd667,
      0x3668,
      0x7479,
    },
  };
  if (forbidden.contains(code)) {
    throw const FormatException('Structural property in Word table style.');
  }
  if (code == 0xf617 &&
      (conditional ||
          styleId != 11 ||
          operation.data.u8(0) != 3 ||
          operation.data.u16(1) != 0)) {
    throw const FormatException('Invalid Word default table-style indent.');
  }
}

// Bounded row operations from MS-DOC 2.6.3. Keep TC80 formats and indexed
// overrides attached to their cells while structural edits change positions.
void _resetTableStyleProperties(_Props output) {
  // Replace row/style defaults, not the cell definitions those defaults
  // decorate. UpxTapx cannot create/resize/delete cells. Independent Word
  // source (POI simple-table2.doc) has TInsert -> TDxaCol -> TIstd with no
  // later definition; clearing the definition would destroy a valid row.
  // Direct per-cell geometry/formatting and TIstd's explicit exemption list
  // (direction, positioning, gap, height, auto-fit, look, review) survive.
  // The style/cell resolver supplies the new style defaults after grouping.
  for (final key in const [
    'tableCantSplit',
    'tableCantSplit90',
    'rowHeader',
    'tableAlignment',
    'tablePhysicalAlignment',
    'tableMargins',
    'tableBorders',
  ]) {
    output.remove(key);
  }
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

LegacyWordTableWidth _tableCellPreferredWidth(
  int unit,
  int value, {
  bool tc80 = false,
}) {
  if (unit > 3 ||
      unit < 0 ||
      (tc80 && value < 0) ||
      (unit == 1 && !tc80 && value != 0) ||
      (unit == 2 && (value < 0 || value > 5000)) ||
      (unit == 3 && (value < 0 || value > 31680))) {
    throw const FormatException('Invalid Word preferred cell width.');
  }
  return LegacyWordTableWidth(
    unit: LegacyWordTableWidthUnit.values[unit],
    value: unit < 2 ? 0 : value,
  );
}

void _applyTableCellFormatRange(
  _Props output,
  int first,
  int limit,
  LegacyWordTableCellFormat format,
) {
  final definition = output['tableDefinition'] as _TableDefinition;
  output['tableDefinition'] =
      _TableDefinition(definition.edges, definition.flags, [
        for (var index = 0; index < definition.flags.length; index++)
          _mergeTableCellFormat(
            index < definition.formats.length
                ? definition.formats[index]
                : const LegacyWordTableCellFormat(),
            index >= first && index < limit
                ? format
                : const LegacyWordTableCellFormat(),
          ),
      ]);
}

void _changeTableCells(_Sprm operation, _Props output) {
  final previous =
      output['tableDefinition'] as _TableDefinition? ??
      _TableDefinition([output['tableOrigin'] as int? ?? 0], const []);
  final widths = [
    for (var i = 0; i < previous.flags.length; i++)
      previous.edges[i + 1] - previous.edges[i],
  ];
  final flags = [...previous.flags];
  final formats = [
    for (var i = 0; i < flags.length; i++)
      i < previous.formats.length
          ? previous.formats[i]
          : const LegacyWordTableCellFormat(),
  ];
  final value = operation.data;
  if (operation.code == 0x7621) {
    final first = value.u8(0), count = value.u8(1), width = value.i16(2);
    if (first > flags.length ||
        count == 0 ||
        count + flags.length > 63 ||
        width < 0) {
      throw const FormatException('Invalid Word table cell insertion.');
    }
    widths.insertAll(first, List.filled(count, width));
    flags.insertAll(first, List.filled(count, 0));
    formats.insertAll(
      first,
      List.filled(count, const LegacyWordTableCellFormat()),
    );
    _shiftTableCellOverrides(output, first, 0, count, previous.flags.length);
  } else {
    final (first, limit) = _tableCellRange(value, output);
    if (operation.code == 0x5622) {
      if (limit - first == flags.length) {
        throw const FormatException('Word table deletion removes every cell.');
      }
      widths.removeRange(first, limit);
      flags.removeRange(first, limit);
      formats.removeRange(first, limit);
      _shiftTableCellOverrides(
        output,
        first,
        limit - first,
        0,
        previous.flags.length,
      );
    } else if (operation.code == 0x7623) {
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
            (operation.code == 0x5625
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
      edges.any((value) => value < -31680 || value > 31680)) {
    throw const FormatException('Word table width exceeds the allowed range.');
  }
  output['tableDefinition'] = _TableDefinition(edges, flags, formats);
  output.putIfAbsent('tableOrigin', () => edges.first);
}

void _shiftTableCellOverrides(
  _Props output,
  int first,
  int removed,
  int inserted,
  int oldCount,
) {
  void shift<T>(String key) {
    final values = output[key] as Map<int, T>?;
    if (values == null) return;
    output[key] = Map<int, T>.unmodifiable({
      for (final entry in values.entries)
        if (entry.key < oldCount)
          if (entry.key < first)
            entry.key: entry.value
          else if (entry.key >= first + removed)
            entry.key + inserted - removed: entry.value,
    });
  }

  shift<LegacyWordShading>('cellShading');
  shift<LegacyWordShading>('cellShadingRaw');
  shift<int>('cellAlignment');
  shift<Map<LegacyWordBorderSide, int?>>('cellMargins');
}

bool _sameTableRows(_Props left, _Props right) {
  if (left['tableStyleId'] != right['tableStyleId'] ||
      left['tableGroup'] != right['tableGroup'] ||
      ((left['tableRtl'] == true || left['tableRtl90'] == true) !=
          (right['tableRtl'] == true || right['tableRtl90'] == true))) {
    return false;
  }
  for (final code in const [
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

LegacyWordAlignment _tableAlignment(_Props properties) {
  final logical = properties['tableAlignment'] as int?;
  if (logical != null) return LegacyWordAlignment.values[logical];
  final physical = properties['tablePhysicalAlignment'] as int?;
  if (physical == null) return LegacyWordAlignment.left;
  final rtl =
      properties['tableRtl'] == true || properties['tableRtl90'] == true;
  return LegacyWordAlignment.values[rtl ? 2 - physical : physical];
}
