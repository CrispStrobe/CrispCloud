// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// Independently implemented from MS-DOC §§2.4.6.3–4, 2.9.131–133,
// 2.9.147–150 and MS-OSHARED §2.2.1.3. The LVL array follows PlfLst but
// is deliberately excluded from FibRgFcLcb97.lcbPlfLst.
class _ListLevelData {
  const _ListLevelData(this.model, this.paragraph, this.styleIndex);
  final LegacyWordNumberingLevel model;
  final List<_Sprm> paragraph;
  final int? styleIndex;
}

extension _WordLists on _StructuredWordParser {
  void _readNumbering() {
    final (listStart, listSize) = source.pair(73);
    final (overrideStart, overrideSize) = source.pair(74);
    if (listSize == 0 && overrideSize == 0) return;
    if (listSize < 2 || overrideSize < 4) {
      throw const FormatException('Incomplete Word list definitions.');
    }
    final table = source.table;
    final count = table.i16(listStart);
    if (count < 0 || count > 4096 || listSize != 2 + count * 28) {
      throw const FormatException('Invalid Word list definition count.');
    }
    final definitions = <int, List<_ListLevelData>>{};
    var cursor = listStart + listSize;
    var totalLevels = 0;
    for (var list = 0; list < count; list++) {
      final record = listStart + 2 + list * 28;
      final id = table.i32(record);
      if (id == -1 || definitions.containsKey(id)) {
        throw const FormatException('Invalid or duplicate Word list identity.');
      }
      final levelCount = (table.u8(record + 26) & 1) != 0 ? 1 : 9;
      if ((totalLevels += levelCount) > 20000) {
        throw const FormatException(
          'Word list levels exceed the complexity limit.',
        );
      }
      final levels = <_ListLevelData>[];
      for (var level = 0; level < levelCount; level++) {
        final styleIndex = table.u16(record + 8 + level * 2);
        final (value, next) = _readListLevel(
          table,
          cursor,
          level,
          styleIndex == 0x0fff ? null : styleIndex,
        );
        levels.add(value);
        cursor = next;
      }
      definitions[id] = levels;
    }
    final overrides = _Bytes(table.slice(overrideStart, overrideSize));
    final overrideCount = overrides.u32(0);
    if (overrideCount > 2046) {
      throw const FormatException(
        'Word list instances exceed the complexity limit.',
      );
    }
    overrides.require(4, overrideCount * 16);
    var position = 4 + overrideCount * 16;
    final firstInstances = <int, int>{};
    final overriddenSources = <int>{};
    for (var instance = 0; instance < overrideCount; instance++) {
      final at = 4 + instance * 16;
      final sourceId = overrides.i32(at);
      firstInstances.putIfAbsent(sourceId, () => instance + 1);
      if (overrides.u8(at + 12) != 0) overriddenSources.add(sourceId);
    }
    for (var instance = 0; instance < overrideCount; instance++) {
      final at = 4 + instance * 16;
      final sourceId = overrides.i32(at);
      final original = definitions[sourceId];
      final overrideLevels = overrides.u8(at + 12);
      if (original == null || overrideLevels > 9) {
        throw const FormatException('Invalid Word list-instance reference.');
      }
      final firstCp = overrides.u32(position);
      if (firstCp != 0xffffffff && firstCp > source.bodyLength) {
        throw const FormatException(
          'Invalid Word list-instance character position.',
        );
      }
      position += 4;
      final levels = [...original];
      final startOverrides = <int, int>{};
      final modified = <int>{};
      for (var item = 0; item < overrideLevels; item++) {
        final startAt = overrides.i32(position);
        final flags = overrides.u32(position + 4);
        position += 8;
        final level = flags & 15;
        final replaceStart = (flags & 0x10) != 0;
        final replaceFormatting = (flags & 0x20) != 0;
        if (level >= levels.length || !modified.add(level)) {
          throw const FormatException(
            'Invalid or duplicate Word list-level override.',
          );
        }
        if (replaceFormatting) {
          final (value, next) = _readListLevel(
            overrides,
            position,
            level,
            levels[level].styleIndex,
          );
          levels[level] = value;
          if (replaceStart) startOverrides[level] = value.model.startAt;
          position = next;
        } else if (replaceStart) {
          if (startAt < 0 || startAt > 32767) {
            throw const FormatException('Invalid Word list start value.');
          }
          startOverrides[level] = startAt;
          final old = levels[level];
          final model = old.model;
          levels[level] = _ListLevelData(
            LegacyWordNumberingLevel(
              level: model.level,
              format: model.format,
              text: model.text,
              startAt: startAt,
              suffix: model.suffix,
              legal: model.legal,
              restartAfterLevel: model.restartAfterLevel,
              markerAlignment: model.markerAlignment,
              paragraphStyle: model.paragraphStyle,
              characterStyle: model.characterStyle,
            ),
            old.paragraph,
            old.styleIndex,
          );
        }
      }
      final id = instance + 1;
      final definition = LegacyWordNumberingDefinition(
        id: id,
        sourceListId: sourceId,
        startOverrides: Map.unmodifiable(startOverrides),
        continuationOf:
            !overriddenSources.contains(sourceId) &&
                firstInstances[sourceId] != id
            ? firstInstances[sourceId]
            : null,
        levels: List.unmodifiable(levels.map((value) => value.model)),
      );
      numbering.add(definition);
      _numberingById[id] = definition;
      for (final level in levels) {
        _listLevels[(id, level.model.level)] = level;
      }
    }
    if (position != overrides.length) {
      throw const FormatException('Trailing Word list-instance data.');
    }
    if (LegacyWordNumberingResolver(
      numbering,
    ).approximateDefinitions.isNotEmpty) {
      warnings.add(LegacyWordWarning.numberingNotReconstructed);
    }
  }

  (_ListLevelData, int) _readListLevel(
    _Bytes input,
    int at,
    int level,
    int? styleIndex,
  ) {
    input.require(at, 28);
    final start = input.i32(at);
    final nfc = input.u8(at + 4);
    final flags = input.u8(at + 5);
    final suffix = input.u8(at + 15);
    final restart = input.u8(at + 26);
    final format = nfc == 255
        ? 'none'
        : nfc < _numberFormats.length
        ? _numberFormats[nfc]
        : null;
    if (format == null ||
        const {8, 9, 15, 19}.contains(nfc) ||
        (nfc != 23 && nfc != 255 && (start < 0 || start > 32767)) ||
        (flags & 3) == 3 ||
        suffix > 2 ||
        ((flags & 8) != 0 && restart > level)) {
      throw const FormatException('Invalid Word list-level format.');
    }
    final papxLength = input.u8(at + 25);
    final chpxLength = input.u8(at + 24);
    final paragraph = _readProperties(input.slice(at + 28, papxLength));
    final character = _readProperties(
      input.slice(at + 28 + papxLength, chpxLength),
    );
    var position = at + 28 + papxLength + chpxLength;
    final length = input.u16(position);
    position += 2;
    if (length > 1024) {
      throw const FormatException('Word list label exceeds the size limit.');
    }
    final template = _unicodeString(input, position, length);
    position += length * 2;
    final placeholders = <int, int>{};
    var prior = 0;
    for (var i = 0; i < 9; i++) {
      final index = input.u8(at + 6 + i);
      if (index == 0) break;
      if (i > level || index <= prior || index > length) {
        throw const FormatException('Invalid Word list label placeholder.');
      }
      final numberLevel = template.codeUnitAt(index - 1);
      if (numberLevel > level) {
        throw const FormatException('Invalid Word list label level reference.');
      }
      placeholders[index - 1] = numberLevel;
      prior = index;
    }
    if (nfc == 23 && (length != 1 || placeholders.isNotEmpty)) {
      throw const FormatException('Invalid Word bullet label.');
    }
    final text = StringBuffer();
    for (var i = 0; i < template.length; i++) {
      final numberLevel = placeholders[i];
      if (numberLevel != null) {
        text.write('%${numberLevel + 1}');
      } else {
        final unit = template.codeUnitAt(i);
        if (unit < 32 && unit != 9) {
          throw const FormatException(
            'Invalid control character in Word list label.',
          );
        }
        text.writeCharCode(unit);
      }
    }
    final paragraphProperties = <String, Object?>{};
    final characterProperties = <String, Object?>{};
    if (styleIndex != null) {
      if (styles[styleIndex]?.kind != 1) {
        throw const FormatException('Invalid Word list paragraph style.');
      }
      final style = _resolveStyle(styleIndex);
      paragraphProperties.addAll(style.paragraph);
      characterProperties.addAll(style.character);
    }
    _applyParagraph(paragraph, paragraphProperties, budget, warnings);
    _applyCharacter(
      character,
      characterProperties,
      {...characterProperties},
      budget,
      warnings,
    );
    return (
      _ListLevelData(
        LegacyWordNumberingLevel(
          level: level,
          format: format,
          text: text.toString(),
          startAt: nfc == 23 || nfc == 255 ? 1 : start,
          suffix: LegacyWordListSuffix.values[suffix],
          legal: (flags & 4) != 0,
          restartAfterLevel: (flags & 8) != 0 ? restart : null,
          markerAlignment:
              LegacyWordAlignment.values[(flags & 3) == 1
                  ? 1
                  : (flags & 3) == 2
                  ? 2
                  : 0],
          paragraphStyle: _paragraphStyle(paragraphProperties, styleIndex ?? 0),
          // An absent marker font inherits the paragraph mark, not STSH.
          characterStyle: _characterStyle(
            characterProperties,
            useDocumentDefaultFont: styleIndex != null,
          ),
        ),
        List.unmodifiable(paragraph),
        styleIndex,
      ),
      position,
    );
  }

  _Props _applyListFormatting(_Props properties, _Props characterBase) {
    final rawId = properties['listId'] as int? ?? 0;
    final level = properties['listLevel'] as int? ?? 0;
    if (rawId == 0 || rawId == -2047 || level == 12) {
      if (rawId == -2047 || level == 12) properties['listId'] = 0;
      return characterBase;
    }
    final definition = _listLevels[(rawId.abs(), level)];
    if (definition == null) {
      warnings.add(LegacyWordWarning.numberingNotReconstructed);
      return characterBase;
    }
    final left = properties['leftIndent'];
    final first = properties['firstIndent'];
    final styleIndex = definition.styleIndex;
    if (styleIndex != null) {
      final style = _resolveStyle(styleIndex);
      properties.addAll(style.paragraph);
      characterBase = {...characterBase, ...style.character};
    }
    _applyParagraph(definition.paragraph, properties, budget, warnings);
    // A negative ilfo preserves the paragraph's own logical indentation.
    if (rawId < 0) {
      properties['leftIndent'] = left;
      properties['firstIndent'] = first;
    }
    properties['listId'] = rawId;
    properties['listLevel'] = level;
    return characterBase;
  }
}

const _numberFormats = legacyWordMsonfcFormats;
