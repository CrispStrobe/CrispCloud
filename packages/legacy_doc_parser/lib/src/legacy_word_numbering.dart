// SPDX-License-Identifier: MPL-2.0

import 'legacy_word_structured_model.dart';

/// A label precedes the source character at its paragraph's start CP. At a
/// separator/end marker it still belongs to the preceding field phase. These
/// ranges therefore include the closing marker, unlike hidden text ranges.
/// Resolving counters remains independent of whether a label is displayed.
class LegacyWordNumberingVisibility {
  LegacyWordNumberingVisibility(List<LegacyWordField> fields) {
    if (fields.length > 20000) {
      throw const FormatException('Word numbering has too many field ranges.');
    }
    final ranges = <(int, int)>[];
    for (final field in fields) {
      final separator = field.separatorCp;
      if (field.startCp < 0 ||
          field.endCp <= field.startCp + 1 ||
          separator != null &&
              (separator <= field.startCp || separator >= field.endCp - 1)) {
        throw const FormatException('Invalid Word numbering field range.');
      }
      ranges.add((
        field.startCp + 1,
        field.privateResult || separator == null ? field.endCp : separator + 1,
      ));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    for (final range in ranges) {
      if (_hidden.isNotEmpty && _hidden.last.$2 >= range.$1) {
        final previous = _hidden.removeLast();
        _hidden.add((
          previous.$1,
          previous.$2 > range.$2 ? previous.$2 : range.$2,
        ));
      } else {
        _hidden.add(range);
      }
    }
  }

  final _hidden = <(int, int)>[];

  bool visibleAt(int cp) {
    var low = 0, high = _hidden.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final range = _hidden[middle];
      if (cp < range.$1) {
        high = middle;
      } else if (cp >= range.$2) {
        low = middle + 1;
      } else {
        return false;
      }
    }
    return true;
  }
}

// Numbering inherits unspecified faces and nullable character properties from
// the paragraph mark. Ordinary text/HTML runs must spell those properties out.
// Explicit automatic-color/no-highlight resets remain distinct from absence;
// parsed sparse overrides also distinguish absent defaults from explicit resets.
LegacyWordCharacterStyle resolveLegacyWordMarkerStyle(
  LegacyWordNumberingLevel level,
  LegacyWordCharacterStyle? mark,
) {
  final marker = level.characterStyle;
  if (mark == null) return marker;
  T? inherited<T>(
    LegacyWordNumberingCharacterProperty property,
    T? value,
    T? parent,
  ) =>
      value ??
      (level.characterStyleOverrides.contains(property) ? null : parent);
  bool inheritedBoolean(
    LegacyWordNumberingCharacterProperty property,
    bool value,
    bool parent,
  ) =>
      value ||
      level.characterStyleIsSparse &&
          !level.characterStyleOverrides.contains(property) &&
          parent;
  bool inheritsDefault(LegacyWordNumberingCharacterProperty property) =>
      level.characterStyleIsSparse &&
      !level.characterStyleOverrides.contains(property);
  final inheritUnderline =
      !marker.underline &&
      marker.underlineStyle == null &&
      inheritsDefault(LegacyWordNumberingCharacterProperty.underline);
  String? nonAscii(LegacyWordCharacterStyle style) =>
      style.scriptFonts == null ? style.fontName : style.scriptFonts!.nonAscii;
  String? eastAsia(LegacyWordCharacterStyle style) =>
      style.scriptFonts == null ? style.fontName : style.scriptFonts!.eastAsia;
  return LegacyWordCharacterStyle(
    bold: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.bold,
      marker.bold,
      mark.bold,
    ),
    italic: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.italic,
      marker.italic,
      mark.italic,
    ),
    underline: inheritUnderline ? mark.underline : marker.underline,
    underlineStyle: inheritUnderline
        ? mark.underlineStyle
        : marker.underlineStyle,
    strike: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.strike,
      marker.strike,
      mark.strike,
    ),
    doubleStrike: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.doubleStrike,
      marker.doubleStrike,
      mark.doubleStrike,
    ),
    smallCaps: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.smallCaps,
      marker.smallCaps,
      mark.smallCaps,
    ),
    allCaps: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.allCaps,
      marker.allCaps,
      mark.allCaps,
    ),
    hidden: inheritedBoolean(
      LegacyWordNumberingCharacterProperty.hidden,
      marker.hidden,
      mark.hidden,
    ),
    fontName: marker.fontName ?? mark.fontName,
    scriptFonts: LegacyWordScriptFonts(
      nonAscii: nonAscii(marker) ?? nonAscii(mark),
      eastAsia: eastAsia(marker) ?? eastAsia(mark),
      complexScript:
          marker.scriptFonts?.complexScript ?? mark.scriptFonts?.complexScript,
    ),
    fontSizeHalfPoints: inherited(
      LegacyWordNumberingCharacterProperty.fontSize,
      marker.fontSizeHalfPoints,
      mark.fontSizeHalfPoints,
    ),
    kerningThresholdHalfPoints:
        marker.kerningThresholdHalfPoints == 0 &&
            inheritsDefault(LegacyWordNumberingCharacterProperty.kerning)
        ? mark.kerningThresholdHalfPoints
        : marker.kerningThresholdHalfPoints,
    colorHex: inherited(
      LegacyWordNumberingCharacterProperty.color,
      marker.colorHex,
      mark.colorHex,
    ),
    highlightHex: inherited(
      LegacyWordNumberingCharacterProperty.highlight,
      marker.highlightHex,
      mark.highlightHex,
    ),
    verticalAlign:
        marker.verticalAlign == LegacyWordVerticalAlignment.baseline &&
            inheritsDefault(LegacyWordNumberingCharacterProperty.verticalAlign)
        ? mark.verticalAlign
        : marker.verticalAlign,
    positionHalfPoints: inherited(
      LegacyWordNumberingCharacterProperty.position,
      marker.positionHalfPoints,
      mark.positionHalfPoints,
    ),
    spacingTwips: inherited(
      LegacyWordNumberingCharacterProperty.spacing,
      marker.spacingTwips,
      mark.spacingTwips,
    ),
  );
}

/// Internal shared numbering interpreter for HTML and WordprocessingML.
/// Each resolve call is one story/valid-selection scope. Source LSID connects
/// compatible instances; an explicit LFOLVL start override keeps its own
/// restart sequence. Ancestor placeholders refer to the same source ILFO.
class LegacyWordNumberingResolver {
  LegacyWordNumberingResolver(List<LegacyWordNumberingDefinition> values) {
    if (values.length > 4096) {
      throw const FormatException('Word numbering is too complex.');
    }
    final policies = <((bool, int), int), (int, int, bool)>{};
    final incompatible = <((bool, int), int)>{};
    final sourceInstances =
        <(bool, int), List<LegacyWordNumberingDefinition>>{};
    for (final definition in values) {
      if (definition.id <= 0 ||
          definition.id > 0x7fffffff ||
          definitions.containsKey(definition.id) ||
          definition.levels.isEmpty ||
          definition.levels.length > 9) {
        throw const FormatException('Invalid Word numbering definition.');
      }
      final levels = <int, LegacyWordNumberingLevel>{};
      for (final level in definition.levels) {
        if (level.level < 0 ||
            level.level > 8 ||
            levels.containsKey(level.level) ||
            level.startAt < 0 ||
            level.startAt > 32767 ||
            level.text.length > 1033 ||
            (level.restartAfterLevel != null &&
                (level.restartAfterLevel! < 0 ||
                    level.restartAfterLevel! > level.level))) {
          throw const FormatException('Invalid Word numbering level.');
        }
        templates.putIfAbsent(level, () => LegacyWordNumberingTemplate(level));
        levels[level.level] = level;
        if (!definition.startOverrides.containsKey(level.level)) {
          final key = (_source(definition), level.level);
          final policy = (
            level.startAt,
            level.restartAfterLevel ?? level.level,
            level.format != 'bullet' && level.format != 'none',
          );
          final previous = policies.putIfAbsent(key, () => policy);
          if (previous != policy) incompatible.add(key);
        }
      }
      for (final override in definition.startOverrides.entries) {
        if (!levels.containsKey(override.key) ||
            override.value < 0 ||
            override.value > 32767) {
          throw const FormatException('Invalid Word numbering start override.');
        }
      }
      definitions[definition.id] = definition;
      levelsById[definition.id] = Map.unmodifiable(levels);
      sourceInstances
          .putIfAbsent(_source(definition), () => [])
          .add(definition);
    }
    for (final definition in values) {
      final targetId = definition.continuationOf;
      if (targetId == null) continue;
      final target = definitions[targetId];
      if (target == null ||
          target.id == definition.id ||
          target.continuationOf != null ||
          target.sourceListId == null ||
          target.sourceListId != definition.sourceListId ||
          definition.startOverrides.isNotEmpty ||
          target.startOverrides.isNotEmpty ||
          target.levels.length != definition.levels.length ||
          !List.generate(
            target.levels.length,
            (i) => identical(target.levels[i], definition.levels[i]),
          ).every((v) => v)) {
        throw const FormatException('Invalid Word numbering continuation.');
      }
    }
    // MS-DOC's published fStartAt iteration is ambiguous for interleaved
    // restart/resume cases. Preserve explicit starts and the separately
    // verified native sequences, but retain a limitation rather than claim
    // identical behavior across all Word versions and override combinations.
    for (final instances in sourceInstances.values) {
      if (instances.length > 1 &&
          instances.any((value) => value.startOverrides.isNotEmpty)) {
        approximateDefinitions.addAll(instances.map((value) => value.id));
      }
    }
    for (final definition in values) {
      for (final level in definition.levels) {
        if (incompatible.contains((_source(definition), level.level))) {
          approximateDefinitions.add(definition.id);
          _incompatibleLevels.add((definition.id, level.level));
        }
      }
    }
  }

  final definitions = <int, LegacyWordNumberingDefinition>{};
  final levelsById = <int, Map<int, LegacyWordNumberingLevel>>{};
  final templates =
      Map<LegacyWordNumberingLevel, LegacyWordNumberingTemplate>.identity();
  final approximateDefinitions = <int>{};
  final _incompatibleLevels = <(int, int)>{};
  var _visitedItems = 0;

  static (bool, int) _source(LegacyWordNumberingDefinition definition) =>
      definition.sourceListId == null
      ? (false, definition.id)
      : (true, definition.sourceListId!);

  Map<LegacyWordParagraph, LegacyWordResolvedNumbering?> resolve(
    List<LegacyWordBlock> blocks,
  ) {
    final ordered = <(int, LegacyWordParagraph)>[];
    void item() {
      if (++_visitedItems > 200000) {
        throw const FormatException('Word numbering is too complex.');
      }
    }

    void scan(List<LegacyWordBlock> values, int depth) {
      if (depth > 63) {
        throw const FormatException('Word tables are nested too deeply.');
      }
      for (final block in values) {
        item();
        switch (block) {
          case LegacyWordParagraph():
            if (block.style.listId != null && block.style.listId != 0) {
              ordered.add((ordered.length, block));
            }
          case LegacyWordTable():
            for (final row in block.rows) {
              item();
              for (final cell in row.cells) {
                item();
                scan(cell.blocks, depth + 1);
              }
            }
        }
      }
    }

    scan(blocks, 0);
    ordered.sort((a, b) {
      final cp = a.$2.startCp.compareTo(b.$2.startCp);
      return cp == 0 ? a.$1.compareTo(b.$1) : cp;
    });
    final counters = <((bool, int), int, int), _Counter>{};
    final lastPositions = <(bool, int), List<int>>{};
    final ancestorValues = <int, Map<int, (int?, String)>>{};
    final output = <LegacyWordParagraph, LegacyWordResolvedNumbering?>{};
    for (var position = 0; position < ordered.length; position++) {
      final paragraph = ordered[position].$2;
      final id = paragraph.style.listId!.abs();
      final index = paragraph.style.listLevel ?? 0;
      final definition = definitions[id];
      final levels = levelsById[id];
      final level = levels?[index];
      if (definition == null || level == null) {
        output[paragraph] = null;
        continue;
      }
      final source = _source(definition);
      final positions = lastPositions.putIfAbsent(
        source,
        () => List.filled(9, -1),
      );
      final explicitStart = definition.startOverrides[index];
      final branch =
          explicitStart != null || _incompatibleLevels.contains((id, index))
          ? id
          : 0;
      final key = (source, index, branch);
      final old = counters[key];
      final restart = level.restartAfterLevel ?? index;
      var reset = old == null;
      if (old != null) {
        for (var upper = 0; upper < restart; upper++) {
          if (positions[upper] > old.position) reset = true;
        }
      }
      final hasSequence = level.format != 'bullet' && level.format != 'none';
      final value = !hasSequence
          ? null
          : reset
          ? explicitStart ?? level.startAt
          : old!.value + 1;
      if (value != null) counters[key] = _Counter(value, position);
      positions[index] = position;
      final ancestors = ancestorValues.putIfAbsent(id, () => {});
      final numbers = <int, int?>{}, formats = <int, String>{};
      for (var upper = 0; upper <= index; upper++) {
        final ancestor = levels![upper];
        if (ancestor == null) continue;
        final previous = ancestors[upper];
        numbers[upper] = upper == index
            ? value
            : previous?.$1 ??
                  (ancestor.format == 'none' || ancestor.format == 'bullet'
                      ? null
                      : definition.startOverrides[upper] ?? ancestor.startAt);
        formats[upper] = upper == index
            ? level.format
            : previous?.$2 ?? ancestor.format;
      }
      ancestors[index] = (value, level.format);
      output[paragraph] = LegacyWordResolvedNumbering(
        definition: definition,
        level: level,
        template: templates[level]!,
        number: value,
        referenceNumbers: Map.unmodifiable(numbers),
        referenceFormats: Map.unmodifiable(formats),
        approximate: approximateDefinitions.contains(id),
      );
    }
    return output;
  }
}

class LegacyWordResolvedNumbering {
  const LegacyWordResolvedNumbering({
    required this.definition,
    required this.level,
    required this.template,
    required this.number,
    required this.referenceNumbers,
    required this.referenceFormats,
    this.approximate = false,
  });
  final LegacyWordNumberingDefinition definition;
  final LegacyWordNumberingLevel level;
  final LegacyWordNumberingTemplate template;
  final int? number;
  final Map<int, int?> referenceNumbers;
  final Map<int, String> referenceFormats;
  final bool approximate;

  /// Resolves only the source's real placeholders. Null means that a required
  /// number format or missing ancestor cannot be reproduced exactly here.
  String? labelText() {
    final output = StringBuffer();
    var position = 0;
    void append(String text) {
      if (text.length > 4096 - output.length) {
        throw const FormatException(
          'Word numbering label exceeds the size limit.',
        );
      }
      output.write(text);
    }

    for (final offset in template.offsets) {
      append(level.text.substring(position, offset));
      final index = level.text.codeUnitAt(offset + 1) - 49;
      final sourceFormat = referenceFormats[index];
      if (sourceFormat == null || index > level.level) return null;
      final value = referenceNumbers[index];
      final number = sourceFormat == 'none' || sourceFormat == 'bullet'
          ? ''
          : value == null
          ? null
          : _listNumber(
              value,
              level.legal && sourceFormat != 'decimalZero'
                  ? 'decimal'
                  : sourceFormat,
            );
      if (number == null) return null;
      append(number);
      position = offset + 2;
    }
    append(level.text.substring(position));
    return output.toString();
  }
}

/// A validated snapshot of explicit binary placeholders or legacy public-model
/// percent placeholders. UTF-16 offsets preserve supplementary characters and
/// literal percent-number text without inventing invisible escape characters.
class LegacyWordNumberingTemplate {
  LegacyWordNumberingTemplate(LegacyWordNumberingLevel level) {
    final explicit = level.placeholderOffsets;
    final inferred = <int>[];
    for (var at = 0; at + 1 < level.text.length; at++) {
      if (_placeholderAt(level.text, at)) inferred.add(at);
    }
    if (explicit == null) {
      if (level.text.length > 1024) {
        throw const FormatException('Word list label exceeds the size limit.');
      }
      offsets = List.unmodifiable(
        level.format == 'bullet' ? <int>[] : inferred,
      );
      nativeRepresentable = true;
      return;
    }
    if (explicit.length > level.level + 1 ||
        explicit.length > 9 ||
        level.text.length - explicit.length > 1024 ||
        (level.format == 'bullet' && explicit.isNotEmpty)) {
      throw const FormatException('Invalid Word list label placeholders.');
    }
    var previous = -2;
    for (final at in explicit) {
      if (at < previous + 2 ||
          at < 0 ||
          at + 1 >= level.text.length ||
          !_placeholderAt(level.text, at) ||
          level.text.codeUnitAt(at + 1) - 49 > level.level) {
        throw const FormatException(
          'Invalid Word list label placeholder offset.',
        );
      }
      previous = at;
    }
    offsets = List.unmodifiable(explicit);
    nativeRepresentable = inferred.length == offsets.length;
  }

  late final List<int> offsets;
  late final bool nativeRepresentable;

  /// Reconstructs the source LVL label (before percent encoding). For a public
  /// model this is an equivalent binary template, not claimed original bytes.
  String binaryText(String text) {
    final output = StringBuffer();
    var position = 0;
    for (final offset in offsets) {
      output.write(text.substring(position, offset));
      output.writeCharCode(text.codeUnitAt(offset + 1) - 49);
      position = offset + 2;
    }
    output.write(text.substring(position));
    return output.toString();
  }

  static bool _placeholderAt(String text, int at) =>
      text.codeUnitAt(at) == 37 &&
      text.codeUnitAt(at + 1) >= 49 &&
      text.codeUnitAt(at + 1) <= 57;
}

String? _listNumber(int value, String format) {
  if (format == 'decimal') return '$value';
  if (format == 'decimalZero') return value.toString().padLeft(2, '0');
  if (format == 'upperLetter' || format == 'lowerLetter') {
    if (value < 1) return null;
    // Word repeats letters after Z: AA, BB, ... ZZ, AAA, unlike spreadsheet
    // column names. The bound prevents expansion before the label budget.
    final repeats = (value - 1) ~/ 26 + 1;
    if (repeats > 1024) return null;
    final first = format == 'lowerLetter' ? 97 : 65;
    return String.fromCharCode(first + (value - 1) % 26) * repeats;
  }
  if (format != 'upperRoman' && format != 'lowerRoman') return null;
  if (value < 1 || value > 3999) return null;
  const symbols = [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  final result = StringBuffer();
  var remaining = value;
  for (final (number, symbol) in symbols) {
    while (remaining >= number) {
      result.write(symbol);
      remaining -= number;
    }
  }
  final text = result.toString();
  return format == 'lowerRoman' ? text.toLowerCase() : text;
}

class _Counter {
  const _Counter(this.value, this.position);
  final int value, position;
}
