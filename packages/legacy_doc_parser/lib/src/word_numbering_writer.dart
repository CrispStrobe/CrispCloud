// SPDX-License-Identifier: MPL-2.0

part of 'conversion.dart';

extension _WordNumberingWriter on _StructuredWordWriter {
  void _prepareNumbering() {
    if (document.numbering.isEmpty) return;
    final resolver = LegacyWordNumberingResolver(document.numbering);
    var nextId = document.numbering.fold(
      0,
      (int value, definition) => definition.id > value ? definition.id : value,
    );
    void scope(List<LegacyWordBlock> blocks) {
      final active = <int, _WordNumberingInstance>{};
      for (final entry in resolver.resolve(blocks).entries) {
        final resolved = entry.value;
        if (resolved == null) {
          limitations.add(LegacyWordConversionLimitation.fieldsLists);
          continue;
        }
        if (resolved.approximate) {
          limitations.add(LegacyWordConversionLimitation.fieldsLists);
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
        if (_resolvedParagraphNumbering.containsKey(entry.key)) {
          throw const FormatException(
            'A numbered Word paragraph belongs to more than one story.',
          );
        }
        _resolvedParagraphNumbering[entry.key] = instance.id;
      }
    }

    scope(document.blocks);
    for (final story in document.stories) {
      scope(story.blocks);
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
        xml.text(level.text, attribute: true);
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
        xml.add(
          '<w:b w:val="${character.bold ? 1 : 0}"/><w:i w:val="${character.italic ? 1 : 0}"/>',
        );
        if (character.hidden) xml.add('<w:vanish/>');
        if (character.colorHex != null) {
          xml.add(
            '<w:color w:val="${_StructuredWordWriter._color(character.colorHex!)}"/>',
          );
        }
        xml.add(
          '<w:kern w:val="${_StructuredWordWriter._kerningThreshold(character)}"/>',
        );
        if (character.fontSizeHalfPoints != null) {
          xml.add('<w:sz w:val="${character.fontSizeHalfPoints}"/>');
        }
        xml.add('<w:u w:val="${_underlineValue(character)}"/></w:rPr></w:lvl>');
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
  static final _placeholder = RegExp(r'%([1-9])');

  int _next(LegacyWordNumberingLevel level) => _values[level.level] == null
      ? starts[level.level] ?? level.startAt
      : _values[level.level]! + 1;

  bool matches(LegacyWordResolvedNumbering value) {
    if (value.number != null && value.number != _next(value.level)) {
      return false;
    }
    for (final match in _placeholder.allMatches(value.level.text)) {
      final index = int.parse(match.group(1)!) - 1;
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
