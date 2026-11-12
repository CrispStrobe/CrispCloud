// SPDX-License-Identifier: MPL-2.0

import 'legacy_word_structured_model.dart';

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
            level.text.length > 1024 ||
            (level.restartAfterLevel != null &&
                (level.restartAfterLevel! < 0 ||
                    level.restartAfterLevel! > level.level))) {
          throw const FormatException('Invalid Word numbering level.');
        }
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
    required this.number,
    required this.referenceNumbers,
    required this.referenceFormats,
    this.approximate = false,
  });
  final LegacyWordNumberingDefinition definition;
  final LegacyWordNumberingLevel level;
  final int? number;
  final Map<int, int?> referenceNumbers;
  final Map<int, String> referenceFormats;
  final bool approximate;
}

class _Counter {
  const _Counter(this.value, this.position);
  final int value, position;
}
