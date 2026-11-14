// SPDX-License-Identifier: MPL-2.0
part of 'legacy_word_structured_parser.dart';

// MS-DOC 2.4.6.6: table/conditional differences precede paragraph styles and
// direct formatting. Keep raw SPRMs until that cascade has been evaluated;
// already coalesced visual runs cannot reconstruct source toggle boundaries.
class _TableTextOperations {
  const _TableTextOperations(
    this.paragraph,
    this.character,
    this.paragraphConditions,
    this.characterConditions,
  );
  final List<_Sprm> paragraph;
  final List<_Sprm> character;
  final Map<LegacyWordTableCondition, List<_Sprm>> paragraphConditions;
  final Map<LegacyWordTableCondition, List<_Sprm>> characterConditions;
  bool get isNotEmpty =>
      paragraph.isNotEmpty ||
      character.isNotEmpty ||
      paragraphConditions.isNotEmpty ||
      characterConditions.isNotEmpty;
}

class _TableTextContext {
  _TableTextContext(this.base);
  final _ResolvedStyle base;
  final styles = <int, _ResolvedStyle>{};
}

class _PreparedParagraph {
  const _PreparedParagraph(this.styleIndex, this.operations, this.properties);
  final int styleIndex;
  final List<_Sprm> operations;
  final _Props properties;
}

extension _WordTableText on _StructuredWordParser {
  _TableTextOperations _readTableTextOperations(_Style style) {
    (List<_Sprm>, Map<LegacyWordTableCondition, List<_Sprm>>) read(
      List<_Sprm> operations,
      bool paragraph,
    ) {
      final plain = <_Sprm>[];
      final conditions = <LegacyWordTableCondition, List<_Sprm>>{};
      final code = paragraph ? 0xc666 : 0xca85;
      for (final operation in operations) {
        _validateTableStyleOperation(operation, paragraph ? 1 : 2);
        if (operation.code != code) {
          if (_tableTextPropertySupported(operation, paragraph)) {
            if (operation.code == 0x2a0c) {
              warnings.add(LegacyWordWarning.unsupportedFormatting);
            }
            plain.add(operation);
          } else {
            warnings.add(LegacyWordWarning.unsupportedFormatting);
          }
          continue;
        }
        final value = operation.data;
        if (value.length < 2) {
          throw const FormatException('Truncated Word text style condition.');
        }
        final mask = value.u16(0);
        if (mask == 0 || mask > 0x800 || (mask & (mask - 1)) != 0) {
          throw const FormatException('Invalid Word text style condition.');
        }
        final condition = LegacyWordTableCondition.values[mask.bitLength - 1];
        final nested = _decodeSprms(value.slice(2, value.length - 2), budget);
        final result = conditions.putIfAbsent(condition, () => []);
        for (final item in nested) {
          _validateTableStyleOperation(
            item,
            paragraph ? 1 : 2,
            conditional: true,
          );
          if (_tableTextPropertySupported(item, paragraph)) {
            if (item.code == 0x2a0c) {
              warnings.add(LegacyWordWarning.unsupportedFormatting);
            }
            result.add(item);
          } else {
            warnings.add(LegacyWordWarning.unsupportedFormatting);
          }
        }
      }
      return (plain, conditions);
    }

    final (paragraph, paragraphConditions) = read(style.paragraph, true);
    final (character, characterConditions) = read(style.character, false);
    return _TableTextOperations(
      paragraph,
      character,
      paragraphConditions,
      characterConditions,
    );
  }

  LegacyWordTableTextFormat _tableTextFormat(
    List<_Sprm> paragraph,
    List<_Sprm> character,
  ) {
    final p = <String, Object?>{}, c = <String, Object?>{};
    _applyParagraph(paragraph, p, budget, warnings);
    _applyCharacter(character, c, const {}, budget, warnings);
    final toggles = <LegacyWordTableCharacterProperty, int>{};
    for (final operation in character) {
      final key = _toggleProperties[operation.code];
      if (key == null) continue;
      final property = LegacyWordTableCharacterProperty.values.byName(key);
      final value = operation.data.u8(0);
      if (value >= 0x80) {
        toggles[property] = value;
      } else {
        toggles.remove(property);
      }
    }
    return LegacyWordTableTextFormat(
      paragraph: _paragraphStyle(p, 0),
      character: _characterStyle(c),
      paragraphProperties: Set.unmodifiable(
        LegacyWordTableParagraphProperty.values.where(
          (property) => p.containsKey(property.name),
        ),
      ),
      characterProperties: Set.unmodifiable(
        LegacyWordTableCharacterProperty.values.where(
          (property) => c.containsKey(property.name),
        ),
      ),
      relativeCharacterToggles: Map.unmodifiable(toggles),
    );
  }

  Map<int, _TableTextContext> _tableTextContexts(List<LegacyWordBlock> blocks) {
    final contexts = <int, _TableTextContext>{};
    final cache = <(int, int), _TableTextContext>{};
    void visit(List<LegacyWordBlock> values) {
      for (final table in values.whereType<LegacyWordTable>()) {
        for (var r = 0; r < table.rows.length; r++) {
          final row = table.rows[r];
          for (var c = 0; c < row.cells.length; c++) {
            final cell = row.cells[c];
            if (row.tableStyleId case final id?) {
              final conditions = _tableStyleConditions(row, r, table.rows, c);
              final mask = conditions.fold(0, (v, p) => v | (1 << p.index));
              final context = cache.putIfAbsent((id, mask), () {
                final chain = _tableStyleChain(id);
                final paragraph = <String, Object?>{};
                final character = <String, Object?>{};
                void apply(List<_Sprm> p, List<_Sprm> ch) {
                  _applyParagraph(p, paragraph, budget, warnings);
                  _applyCharacter(
                    ch,
                    character,
                    Map.of(character),
                    budget,
                    warnings,
                  );
                }

                for (final style in chain) {
                  final raw = _tableTextOperations[style.id]!;
                  apply(raw.paragraph, raw.character);
                }
                for (final condition in conditions) {
                  for (final style in chain) {
                    final raw = _tableTextOperations[style.id]!;
                    apply(
                      raw.paragraphConditions[condition] ?? const [],
                      raw.characterConditions[condition] ?? const [],
                    );
                  }
                }
                return _TableTextContext(_ResolvedStyle(paragraph, character));
              });
              for (final paragraph
                  in cell.blocks.whereType<LegacyWordParagraph>()) {
                contexts[paragraph.startCp] = context;
              }
            }
            // Only the innermost table supplies a paragraph's text style.
            visit(cell.blocks);
          }
        }
      }
    }

    visit(blocks);
    return contexts;
  }

  _ResolvedStyle _resolveStyleOverTable(int id, _TableTextContext context) {
    final active = <int>{};
    _ResolvedStyle resolve(int index) {
      if (index == 0xfff) return context.base;
      if (context.styles[index] case final cached?) return cached;
      if (!active.add(index) || active.length > 64) {
        throw const FormatException('Cyclic Word contextual text style.');
      }
      final style = styles[index];
      if (style == null) {
        if (index == 0 || index == 10) return context.base;
        throw const FormatException('Missing Word contextual text style.');
      }
      if (style.kind != 1 && style.kind != 2) {
        throw const FormatException('Invalid Word contextual text style.');
      }
      final parent = resolve(style.parent);
      final paragraph = <String, Object?>{...parent.paragraph};
      final character = <String, Object?>{...parent.character};
      if (style.builtinId >= 1 && style.builtinId <= 9) {
        paragraph['outline'] = style.builtinId - 1;
      }
      _applyParagraph(style.paragraph, paragraph, budget, warnings);
      _applyCharacter(
        style.character,
        character,
        parent.character,
        budget,
        warnings,
      );
      active.remove(index);
      return context.styles[index] = _ResolvedStyle(paragraph, character);
    }

    return resolve(id);
  }

  _PreparedParagraph _prepareParagraph(int start, int end) {
    final terminalCp = end > start ? end - 1 : start;
    final piece = source.pieceAt(terminalCp);
    final papx = paragraphFormatting.at(piece.fc(terminalCp));
    final operations = [...papx.operations, ..._pieceProperties(piece)];
    final properties = <String, Object?>{
      ..._resolveStyle(papx.styleIndex).paragraph,
      'styleIndex': papx.styleIndex,
    };
    _applyParagraph(
      operations,
      properties,
      budget,
      warnings,
      resolveParagraphStyle: _paragraphStyleForSelection,
    );
    return _PreparedParagraph(papx.styleIndex, operations, properties);
  }
}

bool _tableTextPropertySupported(_Sprm operation, bool paragraph) {
  final code = operation.code;
  if (paragraph) {
    return _paragraphLayoutBooleans.containsKey(code) ||
        const {
          0x2403,
          0x2461,
          0x2405,
          0x2406,
          0x2407,
          0x840f,
          0x845e,
          0x840e,
          0x845d,
          0x8411,
          0x8460,
          0xa413,
          0xa414,
          0x6412,
          0x2640,
          0x442d,
          0xc64d,
          0x6424,
          0x6425,
          0x6426,
          0x6427,
          0x6428,
          0x6629,
          0xc64e,
          0xc64f,
          0xc650,
          0xc651,
          0xc652,
          0xc653,
        }.contains(code);
  }
  return const {
    0x0835,
    0x0836,
    0x0837,
    0x083a,
    0x083b,
    0x083c,
    0x2a53,
    0x2a3e,
    0x4a43,
    0x4a4f,
    0x4a50,
    0x4a51,
    0x4a5e,
    0x2a42,
    0x6870,
    0x2a0c,
    0x2a48,
    0x4845,
    0x484b,
    0x8840,
  }.contains(code);
}
