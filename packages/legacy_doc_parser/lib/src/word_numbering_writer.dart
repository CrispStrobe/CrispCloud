// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

class _MaterializedNumberingLabel {
  const _MaterializedNumberingLabel(
    this.text,
    this.level,
    this.containingFields,
  );
  final String text;
  final LegacyWordNumberingLevel level;
  final List<LegacyWordField> containingFields;
}

extension _WordNumberingWriter on _StructuredWordWriter {
  void _prepareNumbering() {
    if (document.numbering.isEmpty) return;
    final resolver = LegacyWordNumberingResolver(document.numbering);
    final visibility = LegacyWordNumberingVisibility(document.fields);
    for (final definition in document.numbering) {
      for (final level in definition.levels) {
        final template = resolver.templates[level]!;
        _numberingTemplates[(definition.id, level.level)] = template;
        if (template.nativeRepresentable) continue;
        if (_evidenceRecords.length >= 20000) _tooComplex();
        _evidenceRecords.add({
          'kind': 'literalNumberingTemplate',
          'definition': definition.id,
          'sourceListId': definition.sourceListId,
          'level': level.level,
          'text': level.text,
          'placeholderOffsets': template.offsets,
          'offsetUnit': 'UTF-16 code units, zero-based in text',
          'binaryTemplate': template.binaryText(level.text),
          'format': level.format,
          'startAt': level.startAt,
          'startOverrides': {
            for (final entry in definition.startOverrides.entries)
              '${entry.key}': entry.value,
          },
          'suffix': level.suffix.name,
          'legal': level.legal,
          'restartAfterLevel': level.restartAfterLevel,
          'characterStyleOverrides': [
            for (final property in level.characterStyleOverrides) property.name,
          ],
          'characterStyleIsSparse': level.characterStyleIsSparse,
          'reason':
              'OOXML lvlText reserves percent-number sequences; using this '
              'template requires styled text labels without automatic renumbering',
        });
      }
    }
    var nextId = document.numbering.fold(
      0,
      (int value, definition) => definition.id > value ? definition.id : value,
    );
    var materializedUnits = 0;
    final seenParagraphs = <LegacyWordParagraph>{};
    final fieldsByStory = <String, List<(int, bool, LegacyWordField)>>{};
    for (final field in document.fields) {
      fieldsByStory.putIfAbsent(field.storyId, () => []).addAll([
        (field.startCp, true, field),
        (field.endCp, false, field),
      ]);
    }
    for (final events in fieldsByStory.values) {
      events.sort((a, b) {
        final cp = a.$1.compareTo(b.$1);
        return cp != 0 ? cp : (a.$2 ? 1 : 0).compareTo(b.$2 ? 1 : 0);
      });
    }
    void scope(List<LegacyWordBlock> blocks, String story) {
      final active = <int, _WordNumberingInstance>{};
      final fieldEvents = fieldsByStory[story] ?? const [];
      var fieldOffset = 0;
      final containingFields = <LegacyWordField>{};
      for (final entry in resolver.resolve(blocks).entries) {
        final resolved = entry.value;
        if (resolved == null) {
          limitations.add(LegacyWordConversionLimitation.fieldsLists);
          continue;
        }
        if (!seenParagraphs.add(entry.key)) {
          throw const FormatException(
            'A numbered Word paragraph belongs to more than one story.',
          );
        }
        if (resolved.approximate) {
          limitations.add(LegacyWordConversionLimitation.fieldsLists);
        }
        if (!visibility.visibleAt(entry.key.startCp)) {
          if (_evidenceRecords.length >= 20000) _tooComplex();
          _suppressedParagraphNumbering.add(entry.key);
          _evidenceRecords.add({
            'kind': 'suppressedFieldNumbering',
            'story': story,
            'cp': entry.key.startCp,
            'definition': resolved.definition.id,
            'level': resolved.level.level,
            'referenceNumbers': {
              for (final entry in resolved.referenceNumbers.entries)
                '${entry.key}': entry.value,
            },
            'reason':
                'The label precedes a source character inside field instructions '
                'or a private result; source counters advance without a visible label',
          });
          _count('suppressedNumberingLabels');
          // Hidden source items still advance the independent resolver. They
          // must not advance native counters, so later visible items receive
          // a fresh native instance when its start value needs to catch up.
          continue;
        }
        if (!resolved.template.nativeRepresentable) {
          final cp = entry.key.startCp;
          while (fieldOffset < fieldEvents.length) {
            final event = fieldEvents[fieldOffset];
            // The prefix precedes source events at this CP. A field beginning
            // here does not contain it; a field whose range has ended cannot.
            if (event.$1 > cp || event.$1 == cp && event.$2) break;
            if (event.$2) {
              containingFields.add(event.$3);
              if (containingFields.length > 65) _tooComplex();
            } else {
              containingFields.remove(event.$3);
            }
            fieldOffset++;
          }
          final text = resolved.labelText();
          if (text == null) {
            throw FormatException(
              'Cannot materialize a literal Word list label with an unsupported '
              'numeral format, value, or ancestor (list ${resolved.definition.id}, '
              'level ${resolved.level.level}, reference formats: '
              '${resolved.referenceFormats.values.toSet().join(', ')}).',
            );
          }
          materializedUnits += text.length;
          if (materializedUnits > 4 * 1024 * 1024 ||
              _evidenceRecords.length >= 20000) {
            _tooComplex();
          }
          _materializedParagraphNumbering[entry.key] =
              _MaterializedNumberingLabel(
                text,
                resolved.level,
                List.unmodifiable(containingFields),
              );
          limitations.add(LegacyWordConversionLimitation.fieldsLists);
          _evidenceRecords.add({
            'kind': 'materializedNumberingLabel',
            'story': story,
            'cp': entry.key.startCp,
            'definition': resolved.definition.id,
            'level': resolved.level.level,
            'label': text,
            'referenceNumbers': {
              for (final entry in resolved.referenceNumbers.entries)
                '${entry.key}': entry.value,
            },
            'referenceFormats': {
              for (final entry in resolved.referenceFormats.entries)
                '${entry.key}': entry.value,
            },
            'approximateContinuation': resolved.approximate,
            'automaticRenumbering': false,
            'reason':
                'Literal percent-number text cannot be escaped in OOXML lvlText; '
                'source CP positions and original runs are unchanged',
          });
          // This is ordinary label text, so native counters do not advance.
          // A later editable item starts a fresh instance if needed to match
          // the independently resolved source counter/ancestor state.
          continue;
        }
        final sourceDefinition = resolved.definition;
        final definition = sourceDefinition.continuationOf == null
            ? sourceDefinition
            : resolver.definitions[sourceDefinition.continuationOf]!;
        var instance = active[definition.id];
        if (instance == null || !instance.matches(resolved)) {
          final id = !_numberingInstances.containsKey(definition.id)
              ? definition.id
              : ++nextId;
          if (id > 0x7fffffff ||
              _numberingInstances.length >= kLegacyWordDocxBreakLimit) {
            _tooComplex();
          }
          instance = _WordNumberingInstance(id, definition, {
            ...definition.startOverrides,
            for (final value in resolved.referenceNumbers.entries)
              if (value.value != null) value.key: value.value!,
          });
          _numberingInstances[id] = instance;
          active[definition.id] = instance;
        }
        instance.advance(resolved.level);
        _resolvedParagraphNumbering[entry.key] = instance.id;
      }
    }

    scope(document.blocks, 'main');
    for (final story in document.stories) {
      scope(story.blocks, story.id);
    }
    for (final definition in document.numbering) {
      if (definition.continuationOf != null) continue;
      _numberingInstances.putIfAbsent(
        definition.id,
        () => _WordNumberingInstance(
          definition.id,
          definition,
          definition.startOverrides,
        ),
      );
    }
  }

  void _materializedNumberingLabel(LegacyWordParagraph paragraph) {
    final label = _materializedParagraphNumbering[paragraph];
    if (label == null) return;
    final activeFields = fieldMode == LegacyWordFieldMode.cachedResults
        ? const <LegacyWordField>[]
        : label.containingFields
              .where(
                (field) => _numberingActiveFields.putIfAbsent(
                  field,
                  () =>
                      !_fieldHandledByAncestor(field) && _safeFieldTree(field),
                ),
              )
              .toList();
    // _prepareNumbering has already suppressed prefixes inside instructions
    // and private results, including their closing marker CPs.
    if (label.containingFields.isNotEmpty) {
      if (_evidenceRecords.length >= 20000) _tooComplex();
      _evidenceRecords.add({
        'kind': 'materializedNumberingFieldContext',
        'story': _storyId,
        'cp': paragraph.startCp,
        'fieldMode': fieldMode.name,
        'containingFields': [
          for (final field in label.containingFields)
            {
              'id': field.id,
              'phase':
                  paragraph.startCp <= (field.separatorCp ?? field.endCp - 1)
                  ? 'instruction'
                  : 'result',
              'active': activeFields.contains(field),
            },
        ],
        'reason': activeFields.isEmpty
            ? 'Containing source fields are inert; the literal prefix remains visible text'
            : 'The literal prefix lies in an active field cached result; field '
                  'recalculation can replace it even though source CP positions are unchanged',
      });
    }
    final suffix = switch (label.level.suffix) {
      LegacyWordListSuffix.tab => '\t',
      LegacyWordListSuffix.space => ' ',
      LegacyWordListSuffix.nothing => '',
    };
    // Emit outside source CP event traversal: synthetic text must not consume
    // source characters, split a field, or move bookmark/note/revision anchors.
    _writeRun(
      LegacyWordRun(
        startCp: paragraph.startCp,
        endCp: paragraph.startCp,
        text: '${label.text}$suffix',
        style: resolveLegacyWordMarkerStyle(label.level, paragraph.mark?.style),
      ),
    );
    _count('materializedNumberingLabels');
  }

  void _writeNumbering() {
    if (document.numbering.isEmpty) return;
    final xml = _wordPart('numbering');
    for (final definition in document.numbering) {
      if (definition.continuationOf != null) continue;
      xml.add(
        '<w:abstractNum w:abstractNumId="${definition.id}"><w:multiLevelType w:val="multilevel"/>',
      );
      final levels = [...definition.levels]
        ..sort((a, b) => a.level.compareTo(b.level));
      final seen = <int>{};
      for (final level in levels) {
        if (level.level < 0 ||
            level.level > 8 ||
            !seen.add(level.level) ||
            level.startAt < 0 ||
            !const {
              'decimal',
              'upperRoman',
              'lowerRoman',
              'upperLetter',
              'lowerLetter',
              'ordinal',
              'cardinalText',
              'ordinalText',
              'hex',
              'chicago',
              'ideographDigital',
              'japaneseCounting',
              'aiueo',
              'iroha',
              'decimalFullWidth',
              'decimalHalfWidth',
              'japaneseLegal',
              'japaneseDigitalTenThousand',
              'decimalEnclosedCircle',
              'decimalFullWidth2',
              'aiueoFullWidth',
              'irohaFullWidth',
              'decimalZero',
              'bullet',
              'none',
              'ganada',
              'chosung',
              'decimalEnclosedFullstop',
              'decimalEnclosedParen',
              'decimalEnclosedCircleChinese',
              'ideographEnclosedCircle',
              'ideographTraditional',
              'ideographZodiac',
              'ideographZodiacTraditional',
              'taiwaneseCounting',
              'ideographLegalTraditional',
              'taiwaneseCountingThousand',
              'taiwaneseDigital',
              'chineseCounting',
              'chineseLegalSimplified',
              'chineseCountingThousand',
              'koreanDigital',
              'koreanCounting',
              'koreanLegal',
              'koreanDigital2',
              'hebrew1',
              'hebrew2',
              'arabicAlpha',
              'arabicAbjad',
              'hindiVowels',
              'hindiConsonants',
              'hindiNumbers',
              'hindiCounting',
              'thaiLetters',
              'thaiNumbers',
              'thaiCounting',
              'vietnameseCounting',
              'numberInDash',
              'russianLower',
              'russianUpper',
            }.contains(level.format)) {
          throw const FormatException(
            'Invalid or unsupported Word numbering level.',
          );
        }
        xml.add(
          '<w:lvl w:ilvl="${level.level}"><w:start w:val="${level.startAt}"/><w:numFmt w:val="${level.format}"/>',
        );
        if (level.restartAfterLevel != null) {
          if (level.restartAfterLevel! < 0 ||
              level.restartAfterLevel! > level.level) {
            throw const FormatException('Invalid Word numbering restart.');
          }
          xml.add('<w:lvlRestart w:val="${level.restartAfterLevel}"/>');
        }
        if (level.legal) xml.add('<w:isLgl/>');
        xml.add('<w:suff w:val="${level.suffix.name}"/><w:lvlText w:val="');
        // Character references preserve source TABs through XML attribute
        // normalization; literal tabs must not reject the entire conversion.
        // A conflicting template is retained in evidence, never emitted as
        // an active native template that would silently replace its literals.
        // Keep its number format so a normal child can reference the counter.
        final template = _numberingTemplates[(definition.id, level.level)]!;
        xml.text(
          template.nativeRepresentable ? level.text : '',
          attribute: true,
          preserveWhitespace: true,
        );
        xml.add('"/>');
        xml.add(
          '<w:lvlJc w:val="${level.markerAlignment == LegacyWordAlignment.justify ? 'both' : level.markerAlignment.name}"/>',
        );
        final paragraph = level.paragraphStyle;
        xml.add('<w:pPr>');
        _paragraphDecorations(paragraph, xml, null);
        xml.add(
          '<w:ind w:left="${paragraph.leftIndentTwips}" w:right="${paragraph.rightIndentTwips}"',
        );
        xml.add(
          paragraph.firstLineIndentTwips < 0
              ? ' w:hanging="${-paragraph.firstLineIndentTwips}"'
              : ' w:firstLine="${paragraph.firstLineIndentTwips}"',
        );
        xml.add('/></w:pPr><w:rPr>');
        final character = level.characterStyle;
        _runFonts(character, xml);
        for (final property in [
          ('b', character.bold, LegacyWordNumberingCharacterProperty.bold),
          ('i', character.italic, LegacyWordNumberingCharacterProperty.italic),
        ]) {
          if (property.$2 ||
              !level.characterStyleIsSparse ||
              level.characterStyleOverrides.contains(property.$3)) {
            xml.add('<w:${property.$1} w:val="${property.$2 ? 1 : 0}"/>');
          }
        }
        // Sparse LVL defaults inherit the paragraph mark. Explicit resets
        // must remain present so an enabled mark cannot reactivate them.
        for (final property in [
          (
            'caps',
            character.allCaps,
            LegacyWordNumberingCharacterProperty.allCaps,
          ),
          (
            'smallCaps',
            character.smallCaps,
            LegacyWordNumberingCharacterProperty.smallCaps,
          ),
          (
            'strike',
            character.strike,
            LegacyWordNumberingCharacterProperty.strike,
          ),
          (
            'dstrike',
            character.doubleStrike,
            LegacyWordNumberingCharacterProperty.doubleStrike,
          ),
          (
            'vanish',
            character.hidden,
            LegacyWordNumberingCharacterProperty.hidden,
          ),
        ]) {
          if (property.$2) {
            xml.add(
              property.$1 == 'vanish'
                  ? '<w:vanish/>'
                  : '<w:${property.$1} w:val="1"/>',
            );
          } else if (level.characterStyleIsSparse &&
              level.characterStyleOverrides.contains(property.$3)) {
            xml.add('<w:${property.$1} w:val="0"/>');
          }
        }
        if (character.colorHex != null ||
            level.characterStyleOverrides.contains(
              LegacyWordNumberingCharacterProperty.color,
            )) {
          xml.add(
            '<w:color w:val="${character.colorHex == null ? 'auto' : _StructuredWordWriter._color(character.colorHex!)}"/>',
          );
        }
        if (character.spacingTwips != null) {
          xml.add('<w:spacing w:val="${character.spacingTwips}"/>');
        }
        if (character.kerningThresholdHalfPoints != 0 ||
            !level.characterStyleIsSparse ||
            level.characterStyleOverrides.contains(
              LegacyWordNumberingCharacterProperty.kerning,
            )) {
          xml.add(
            '<w:kern w:val="${_StructuredWordWriter._kerningThreshold(character)}"/>',
          );
        }
        if (character.positionHalfPoints != null) {
          xml.add('<w:position w:val="${character.positionHalfPoints}"/>');
        }
        if (character.fontSizeHalfPoints != null) {
          xml.add('<w:sz w:val="${character.fontSizeHalfPoints}"/>');
        }
        final highlight = character.highlightHex == null
            ? null
            : _StructuredWordWriter._color(character.highlightHex!);
        if (character.underline ||
            character.underlineStyle != null ||
            !level.characterStyleIsSparse ||
            level.characterStyleOverrides.contains(
              LegacyWordNumberingCharacterProperty.underline,
            )) {
          xml.add('<w:u w:val="${_underlineValue(character)}"/>');
        }
        // NumberingSymbolRunProperties permits shading but not highlight
        // (MS-OI29500 17.9.24). Retain the exact background RGB using shading.
        if (highlight != null) {
          xml.add('<w:shd w:val="clear" w:color="auto" w:fill="$highlight"/>');
        }
        if (character.verticalAlign != LegacyWordVerticalAlignment.baseline ||
            level.characterStyleIsSparse &&
                level.characterStyleOverrides.contains(
                  LegacyWordNumberingCharacterProperty.verticalAlign,
                )) {
          xml.add('<w:vertAlign w:val="${character.verticalAlign.name}"/>');
        }
        xml.add('</w:rPr></w:lvl>');
      }
      xml.add('</w:abstractNum>');
      _count('numberingDefinitions');
    }
    for (final instance in _numberingInstances.values) {
      xml.add(
        '<w:num w:numId="${instance.id}"><w:abstractNumId w:val="${instance.definition.id}"/>',
      );
      for (final level in instance.definition.levels) {
        final start = instance.starts[level.level];
        if (start != null && start != level.startAt) {
          xml.add(
            '<w:lvlOverride w:ilvl="${level.level}"><w:startOverride w:val="$start"/></w:lvlOverride>',
          );
        }
      }
      xml.add('</w:num>');
      _count('numberingInstances');
    }
    xml.add('</w:numbering>');
    _package.addXml(
      'word/numbering.xml',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml',
      xml,
    );
    _package.relate(
      'word/document.xml',
      '$_relationshipNamespace/numbering',
      'numbering.xml',
    );
  }
}

/// A real OOXML numbering instance. A fresh instance is required if resuming
/// a source ILFO cannot reproduce its resolved counter/ancestor state using
/// its existing OOXML counters. Labels remain editable numbering, not text.
class _WordNumberingInstance {
  _WordNumberingInstance(this.id, this.definition, Map<int, int> starts)
    : starts = Map.unmodifiable(starts),
      levels = {for (final level in definition.levels) level.level: level};
  final int id;
  final LegacyWordNumberingDefinition definition;
  final Map<int, int> starts;
  final Map<int, LegacyWordNumberingLevel> levels;
  final _values = List<int?>.filled(9, null);

  int _next(LegacyWordNumberingLevel level) => _values[level.level] == null
      ? starts[level.level] ?? level.startAt
      : _values[level.level]! + 1;

  bool matches(LegacyWordResolvedNumbering value) {
    if (value.number != null && value.number != _next(value.level)) {
      return false;
    }
    for (final offset in value.template.offsets) {
      final index = value.level.text.codeUnitAt(offset + 1) - 49;
      if (index == value.level.level) continue;
      final expected = value.referenceNumbers[index];
      if (expected == null) continue;
      final level = levels[index];
      if (level == null ||
          expected != (_values[index] ?? starts[index] ?? level.startAt)) {
        return false;
      }
    }
    return true;
  }

  void advance(LegacyWordNumberingLevel level) {
    if (level.format != 'bullet' && level.format != 'none') {
      _values[level.level] = _next(level);
    }
    for (final lower in definition.levels) {
      final restart = lower.restartAfterLevel ?? lower.level;
      if (lower.level > level.level && restart > 0 && level.level < restart) {
        _values[lower.level] = null;
      }
    }
  }
}
