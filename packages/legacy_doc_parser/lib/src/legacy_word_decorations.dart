// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// MS-DOC PChgTabsDel/DelClose/Add, TBD, Brc/Brc80/BrcType, Shd/Shd80/Ipat.
// All properties are resolved through the same paragraph/style cascade.
List<LegacyWordTabStop> _changeTabs(
  _Bytes value,
  List<LegacyWordTabStop> existing,
  bool close,
  _Budget budget,
) {
  final deleted = value.u8(0);
  if (deleted > 64 || existing.length > 64) {
    throw const FormatException('Word tab-stop count exceeds the limit.');
  }
  final deletePositions = <int>[], distances = <int>[];
  for (var i = 0; i < deleted; i++) {
    final position = value.i16(1 + i * 2);
    if (position > 31680 ||
        (!close && position < -31680) ||
        (i != 0 && position < deletePositions.last)) {
      throw const FormatException('Invalid Word tab deletion positions.');
    }
    final distance = close ? value.i16(1 + deleted * 2 + i * 2) : 25;
    if (distance > 31681) {
      throw const FormatException('Invalid Word tab deletion distance.');
    }
    deletePositions.add(position);
    distances.add(distance < 25 ? 25 : distance);
  }
  var cursor = 1 + deleted * (close ? 4 : 2);
  final added = value.u8(cursor++);
  if (added > 64 || value.length != cursor + added * 3) {
    throw const FormatException('Invalid Word tab-stop operand.');
  }
  final stops = <int, LegacyWordTabStop>{};
  for (final stop in existing) {
    var remove = false;
    for (var i = 0; i < deleted; i++) {
      budget.apply();
      if ((stop.positionTwips - deletePositions[i]).abs() <= distances[i]) {
        remove = true;
        break;
      }
    }
    if (!remove) stops[stop.positionTwips] = stop;
  }
  int? prior;
  for (var i = 0; i < added; i++) {
    budget.apply();
    final position = value.i16(cursor + i * 2);
    final descriptor = value.u8(cursor + added * 2 + i);
    final alignment = descriptor & 7, leader = (descriptor >> 3) & 7;
    if (position < -31680 ||
        position > 31680 ||
        (prior != null && position < prior) ||
        !const {0, 1, 2, 3, 4, 6}.contains(alignment) ||
        (alignment != 4 && leader == 6)) {
      throw const FormatException('Invalid Word custom tab stop.');
    }
    prior = position;
    stops[position] = LegacyWordTabStop(
      positionTwips: position,
      alignment: LegacyWordTabAlignment.values[alignment == 6 ? 5 : alignment],
      leader: alignment == 4 || leader == 7
          ? LegacyWordTabLeader.none
          : LegacyWordTabLeader.values[leader],
    );
  }
  if (stops.length > 64) {
    throw const FormatException('Resolved Word tabs exceed the limit.');
  }
  return List.unmodifiable(
    stops.values.toList()
      ..sort((a, b) => a.positionTwips.compareTo(b.positionTwips)),
  );
}

LegacyWordShading _readShading(
  _Bytes value,
  Set<LegacyWordWarning> warnings, {
  bool old = false,
}) {
  if (value.length != (old ? 2 : 10)) {
    throw const FormatException('Invalid Word shading operand.');
  }
  final packed = old ? value.u16(0) : 0;
  if (old && packed == 0xffff) {
    return const LegacyWordShading(pattern: 'nil', rawPattern: 63);
  }
  final pattern = old ? packed >> 10 : value.u16(8);
  if (pattern > 25 && !(pattern >= 35 && pattern <= 61) && pattern != 0xffff) {
    throw const FormatException('Invalid Word shading pattern.');
  }
  var name = _shadingPatterns[pattern];
  final foreground = old
      ? _colorIndex(packed & 31)
      : _color(_Bytes(value.slice(0, 4)));
  final background = old
      ? _colorIndex((packed >> 5) & 31)
      : _color(_Bytes(value.slice(4, 4)));
  if (!old &&
      pattern == 0 &&
      value.u32(0) == 0xffffffff &&
      value.u32(4) == 0xffffffff) {
    name = 'nil';
  }
  if (name == null) warnings.add(LegacyWordWarning.unsupportedFormatting);
  return LegacyWordShading(
    pattern: name,
    rawPattern: pattern,
    foregroundHex: foreground,
    backgroundHex: background,
  );
}

LegacyWordBorder? _readParagraphBorder(_Bytes value, {bool old = false}) {
  if (value.length != (old ? 4 : 8)) {
    throw const FormatException('Invalid Word border operand.');
  }
  final width = value.u8(old ? 0 : 4);
  final type = value.u8(old ? 1 : 5);
  // BrcType 0xFF is ignored. It is not an explicit none/nil reset, and its
  // unused color/width fields do not describe a replacement border.
  if (type == 0xff) return null;
  final style = _borderStyles[type];
  // Art borders are valid only on a page, never on a paragraph. Brc80 does
  // not represent inset/outset. Unused bitfields are intentionally ignored.
  if (style == null || (old && (type == 26 || type == 27))) {
    throw const FormatException('Invalid Word paragraph border type.');
  }
  final flags = value.u8(old ? 3 : 6);
  return LegacyWordBorder(
    style: style,
    rawType: type,
    widthEighthPoints: width < 2 ? 2 : width,
    colorHex: old ? _colorIndex(value.u8(2)) : _color(value),
    spacingPoints: flags & 31,
    shadow: (flags & 32) != 0,
    frame: (flags & 64) != 0,
  );
}

void _applyCellShading(
  _Bytes value,
  _Props output,
  _Budget budget,
  Set<LegacyWordWarning> warnings, {
  int first = 0,
  bool old = false,
  bool raw = false,
}) {
  final width = old ? 2 : 10;
  final limit = old
      ? 63
      : first == 44
      ? 19
      : 22;
  if (value.length % width != 0 || value.length ~/ width > limit) {
    throw const FormatException('Invalid Word table-cell shading array.');
  }
  final values = <int, LegacyWordShading>{
    ...?output['cellShading'] as Map<int, LegacyWordShading>?,
  };
  final rawValues = <int, LegacyWordShading>{
    ...?output['cellShadingRaw'] as Map<int, LegacyWordShading>?,
  };
  for (var i = 0; i < value.length ~/ width; i++) {
    budget.apply();
    final shading = _readShading(
      _Bytes(value.slice(i * width, width)),
      warnings,
      old: old,
    );
    // Raw Nil can only be resolved when assembly identifies a table style.
    // Keep the diagnostic for now because this property may also occur on
    // rows with no usable style reference; do not turn it into automatic fill.
    if (raw && shading.pattern == 'nil') {
      warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
    values[first + i] = shading;
    if (raw) rawValues[first + i] = shading;
  }
  // A later operand replaces this whole range, including omitted trailing
  // cells whose shading is default, rather than inheriting stale entries.
  for (var i = value.length ~/ width; i < limit; i++) {
    values.remove(first + i);
    if (raw) rawValues.remove(first + i);
  }
  output['cellShading'] = Map<int, LegacyWordShading>.unmodifiable(values);
  if (raw) {
    output['cellShadingRaw'] = Map<int, LegacyWordShading>.unmodifiable(
      rawValues,
    );
  }
}

const _borderStyles = <int, String>{
  0: 'none',
  1: 'single',
  3: 'double',
  5: 'single',
  6: 'dotted',
  7: 'dashed',
  8: 'dotDash',
  9: 'dotDotDash',
  10: 'triple',
  11: 'thinThickSmallGap',
  12: 'thickThinSmallGap',
  13: 'thinThickThinSmallGap',
  14: 'thinThickMediumGap',
  15: 'thickThinMediumGap',
  16: 'thinThickThinMediumGap',
  17: 'thinThickLargeGap',
  18: 'thickThinLargeGap',
  19: 'thinThickThinLargeGap',
  20: 'wave',
  21: 'doubleWave',
  22: 'dashSmallGap',
  23: 'dashDotStroked',
  24: 'threeDEmboss',
  25: 'threeDEngrave',
  26: 'outset',
  27: 'inset',
};

const _shadingPatterns = <int, String>{
  0: 'clear',
  1: 'solid',
  2: 'pct5',
  3: 'pct10',
  4: 'pct20',
  5: 'pct25',
  6: 'pct30',
  7: 'pct40',
  8: 'pct50',
  9: 'pct60',
  10: 'pct70',
  11: 'pct75',
  12: 'pct80',
  13: 'pct90',
  14: 'horzStripe',
  15: 'vertStripe',
  16: 'reverseDiagStripe',
  17: 'diagStripe',
  18: 'horzCross',
  19: 'diagCross',
  20: 'thinHorzStripe',
  21: 'thinVertStripe',
  22: 'thinReverseDiagStripe',
  23: 'thinDiagStripe',
  24: 'thinHorzCross',
  25: 'thinDiagCross',
  37: 'pct12',
  38: 'pct15',
  43: 'pct35',
  44: 'pct37',
  46: 'pct45',
  49: 'pct55',
  51: 'pct62',
  52: 'pct65',
  57: 'pct85',
  58: 'pct87',
  60: 'pct95',
  0xffff: 'nil',
};
