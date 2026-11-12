// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.5.14, 2.7.2/DopBase, 2.7.4/Dop97 and 2.6.4/section SPRMs.
// Old DOP numbering is active only through Word 2000. Newer files use section
// properties; unused old values must not silently override those defaults.
extension _WordNoteSettingsSource on _BinarySource {
  void _readDocumentNoteSettings(int offset, int length) {
    final dop = _Bytes(table.slice(offset, length));
    final extension = 154 + pairCount * 8;
    final cswNew = word.u16(extension);
    if (!const {0, 2, 5}.contains(cswNew)) {
      throw const FormatException('Invalid Word FIB extension size.');
    }
    word.require(extension + 2, cswNew * 2);
    final newVersion = cswNew == 0 ? null : word.u16(extension + 2);
    if (newVersion != null &&
        (!const {0xd9, 0x101, 0x10c, 0x112}.contains(newVersion) ||
            (newVersion == 0x112 ? cswNew != 5 : cswNew != 2))) {
      throw const FormatException('Invalid Word FIB extension version.');
    }
    final effectiveVersion = newVersion ?? version;
    // The pinned native corpus proves that this exact legacy exporter layout
    // still uses its DOP starts/placement. This is an interoperability
    // recovery, not a claim that modern MS-DOC activates obsolete fields.
    final recovered =
        cswNew == 0 && version == 0x101 && pairCount == 136 && length == 610;
    final legacyNumbering = effectiveVersion <= 0xd9 || recovered;
    final endPosition = switch (dop.u8(54) & 3) {
      0 => LegacyWordEndnotePosition.sectionEnd,
      3 => LegacyWordEndnotePosition.documentEnd,
      _ => throw const FormatException('Invalid Word endnote position.'),
    };
    if (!legacyNumbering) {
      endnotes = LegacyWordEndnoteSettings(position: endPosition);
      return;
    }
    if (recovered) {
      noteSettingsWarnings.add(LegacyWordWarning.recoveredLegacyNoteSettings);
    }
    final footPosition = switch ((dop.u8(0) >> 5) & 3) {
      0 => LegacyWordFootnotePosition.sectionEnd,
      1 => LegacyWordFootnotePosition.pageBottom,
      2 => LegacyWordFootnotePosition.beneathText,
      _ => throw const FormatException('Invalid Word footnote position.'),
    };
    final foot = dop.u16(2), end = dop.u16(52);
    final footFormat = length >= 496
        ? _noteNumberFormat(dop.u16(492), noteSettingsWarnings)
        : LegacyWordNoteNumberFormat.decimal;
    final endFormat = length >= 496
        ? _noteNumberFormat(dop.u16(494), noteSettingsWarnings)
        : LegacyWordNoteNumberFormat.lowerRoman;
    footnotes = LegacyWordFootnoteSettings(
      position: footPosition,
      numbering: LegacyWordNoteNumbering(
        format: footFormat,
        startAt: foot >> 2,
        restart: _noteRestart(foot & 3),
      ),
    );
    endnotes = LegacyWordEndnoteSettings(
      position: endPosition,
      numbering: LegacyWordNoteNumbering(
        format: endFormat,
        startAt: end >> 2,
        restart: _noteRestart(end & 3),
      ),
    );
  }
}

LegacyWordNoteRestart _noteRestart(int raw, {bool sectionEndnote = false}) {
  if (raw > 2 || (sectionEndnote && raw == 2)) {
    throw const FormatException('Invalid Word note numbering restart.');
  }
  return LegacyWordNoteRestart.values[raw];
}

LegacyWordNoteNumberFormat _noteNumberFormat(
  int raw,
  Set<LegacyWordWarning> warnings,
) {
  if (raw == 0xff) return LegacyWordNoteNumberFormat.none;
  if (raw >= _numberFormats.length) {
    throw const FormatException('Invalid Word note numbering format.');
  }
  // Word's documented note-format fallback for bullet; 40 is MSONFC's
  // application-defined format, for which the binary stores no definition.
  if (raw == 23 || raw == 40) {
    warnings.add(LegacyWordWarning.unsupportedFormatting);
    return LegacyWordNoteNumberFormat.decimal;
  }
  return LegacyWordNoteNumberFormat.values.byName(_numberFormats[raw]);
}

bool _applySectionNoteProperty(
  _Sprm operation,
  _Props output,
  Set<LegacyWordWarning> warnings,
) {
  final value = operation.data;
  switch (operation.code) {
    case 0x3012:
      output['suppressEndnotes'] = !_boolean(value);
    case 0x303b:
      output['footnotePosition'] = switch (value.u8(0)) {
        1 => LegacyWordFootnotePosition.pageBottom,
        2 => LegacyWordFootnotePosition.beneathText,
        _ => throw const FormatException('Invalid Word footnote position.'),
      };
    case 0x303c:
      output['footnoteRestart'] = _noteRestart(value.u8(0));
    case 0x303e:
      output['endnoteRestart'] = _noteRestart(
        value.u8(0),
        sectionEndnote: true,
      );
    case 0x503f:
    case 0x5041:
      final start = value.u16(0);
      if (start > 16383) {
        throw const FormatException('Invalid Word note numbering start.');
      }
      output[operation.code == 0x503f ? 'footnoteStart' : 'endnoteStart'] =
          start;
    case 0x5040:
    case 0x5042:
      output[operation.code == 0x5040 ? 'footnoteFormat' : 'endnoteFormat'] =
          _noteNumberFormat(value.u16(0), warnings);
    default:
      return false;
  }
  return true;
}

LegacyWordNoteNumbering _sectionNoteNumbering(
  _Props properties,
  String prefix,
  LegacyWordNoteNumbering defaults,
) {
  final restart =
      properties['${prefix}Restart'] as LegacyWordNoteRestart? ??
      defaults.restart;
  return LegacyWordNoteNumbering(
    format:
        properties['${prefix}Format'] as LegacyWordNoteNumberFormat? ??
        defaults.format,
    restart: restart,
    // SNFtn/SNEdn are offsets for continuous numbering only. A dormant
    // offset must not change the start of per-page/per-section numbering.
    startAt: restart == LegacyWordNoteRestart.continuous
        ? properties['${prefix}Start'] as int? ?? defaults.startAt
        : defaults.startAt,
  );
}

LegacyWordFootnoteSettings? _sectionFootnoteSettings(
  _Props properties,
  LegacyWordFootnoteSettings defaults,
) {
  if (!const [
    'footnotePosition',
    'footnoteRestart',
    'footnoteStart',
    'footnoteFormat',
  ].any(properties.containsKey)) {
    return null;
  }
  return LegacyWordFootnoteSettings(
    position:
        properties['footnotePosition'] as LegacyWordFootnotePosition? ??
        defaults.position,
    numbering: _sectionNoteNumbering(
      properties,
      'footnote',
      defaults.numbering,
    ),
  );
}

LegacyWordEndnoteSettings? _sectionEndnoteSettings(
  _Props properties,
  LegacyWordEndnoteSettings defaults,
) {
  if (!const [
    'endnoteRestart',
    'endnoteStart',
    'endnoteFormat',
  ].any(properties.containsKey)) {
    return null;
  }
  return LegacyWordEndnoteSettings(
    position: defaults.position,
    numbering: _sectionNoteNumbering(properties, 'endnote', defaults.numbering),
  );
}
