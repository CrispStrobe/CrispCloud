// SPDX-License-Identifier: MPL-2.0

part of 'legacy_word_structured_parser.dart';

// FKP/property decoding is adapted in part from the 0BSD JSDoc docToText.js,
// commit 821695a884e0c0bb8592a635d9524bb3e116cd67. The strict extents, property
// cascade, PRM handling, toggle semantics, revisions and TCGRF interpretation
// here are independently implemented against MS-DOC; no accepted-change view
// or image-carving code is used.

class _Budget {
  int properties = 0;
  int applications = 0;
  int expandedProperties = 0;

  void expand(int count) {
    if (count > 2000000 - expandedProperties) {
      throw const FormatException(
        'Word properties exceed the preview complexity limit.',
      );
    }
    expandedProperties += count;
  }

  void property() {
    if (++properties > 500000) {
      throw const FormatException(
        'Word formatting exceeds the preview complexity limit.',
      );
    }
  }

  void apply() {
    if (++applications > 2000000) {
      throw const FormatException(
        'Word formatting exceeds the preview complexity limit.',
      );
    }
  }
}

class _Sprm {
  _Sprm(this.code, Uint8List bytes) : data = _Bytes(bytes);
  final int code;
  final _Bytes data;
  int get group => (code >> 10) & 7;
}

int _wordTwipMeasurement(int value, {bool nonNegative = false}) {
  // MS-DOC XAS and LSPD are narrower than their signed 16-bit storage.
  // Paragraph before/after spacing has the same upper bound, but is unsigned.
  if (value < (nonNegative ? 0 : -31680) || value > 31680) {
    throw const FormatException('Invalid Word twip measurement.');
  }
  return value;
}

List<_Sprm> _decodeSprms(
  Uint8List bytes,
  _Budget budget, {
  void Function()? onPapxOrphanByte,
  bool stopAtReplacingProperties = false,
}) {
  final input = _Bytes(bytes);
  final output = <_Sprm>[];
  var position = 0;
  while (position < input.length) {
    final remaining = input.length - position;
    if (remaining <= 2 && bytes.skip(position).every((byte) => byte == 0)) {
      break;
    }
    // Narrow interoperability recovery requested only by cb=0 PapxInFkp.
    // This is not valid GrpPrlAndIstd padding: it requires whole Prl records.
    // A complete prior record and exactly one remaining byte are essential;
    // no operand, opcode pair, length prefix or indirect property is repaired.
    if (remaining == 1 && output.isNotEmpty && onPapxOrphanByte != null) {
      onPapxOrphanByte();
      break;
    }
    budget.property();
    final code = input.u16(position);
    position += 2;
    final spra = code >> 13;
    var prefix = 0;
    var size = switch (spra) {
      0 || 1 => 1,
      2 || 4 || 5 => 2,
      3 => 4,
      7 => 3,
      _ => 0,
    };
    if (spra == 6) {
      if (code == 0xd608 || code == 0xd606) {
        final declared = input.u16(position);
        if (declared < 1) {
          throw const FormatException('Invalid Word table property length.');
        }
        size = declared + 1;
        prefix = 2;
      } else {
        size = input.u8(position) + 1;
        prefix = 1;
        if (code == 0xc615 && input.u8(position) == 255) {
          final deleted = input.u8(position + 1);
          if (deleted > 64) {
            throw const FormatException('Invalid Word tab-stop count.');
          }
          final addedAt = position + 2 + deleted * 4;
          final added = input.u8(addedAt);
          if (added > 64) {
            throw const FormatException('Invalid Word tab-stop count.');
          }
          size = addedAt + 1 + added * 3 - position;
        }
      }
    }
    input.require(position, size);
    output.add(_Sprm(code, input.slice(position + prefix, size - prefix)));
    position += size;
    if (stopAtReplacingProperties &&
        (code == 0x646b || (code == 0x6646 && output.length == 1))) {
      break;
    }
  }
  return output;
}

const _prm0Codes = <int, int>{
  0x04: 0x2602,
  0x05: 0x2403,
  0x07: 0x2405,
  0x08: 0x2406,
  0x09: 0x2407,
  0x0a: 0x2408,
  0x0c: 0x260a,
  0x0d: 0x2470,
  0x0e: 0x240c,
  0x0f: 0x2471,
  0x18: 0x2416,
  0x19: 0x2417,
  0x1d: 0x2423,
  0x25: 0x2423,
  0x2c: 0x242a,
  0x32: 0x2430,
  0x33: 0x2431,
  0x35: 0x2433,
  0x36: 0x2434,
  0x37: 0x2435,
  0x38: 0x2436,
  0x39: 0x2437,
  0x3a: 0x2438,
  0x41: 0x0800,
  0x42: 0x0801,
  0x43: 0x0802,
  0x47: 0x0806,
  0x4b: 0x080a,
  0x4d: 0x2a0c,
  0x4e: 0x0858,
  0x4f: 0x2859,
  0x50: 0x0811,
  0x51: 0x0818,
  0x53: 0x2a33,
  0x55: 0x0835,
  0x56: 0x0836,
  0x57: 0x0837,
  0x58: 0x0838,
  0x59: 0x0839,
  0x5a: 0x083a,
  0x5b: 0x083b,
  0x5c: 0x083c,
  0x5e: 0x2a3e,
  0x62: 0x2a42,
  0x68: 0x2a48,
  0x73: 0x2a53,
  0x74: 0x0854,
  0x75: 0x0855,
  0x76: 0x0856,
  0x78: 0x2640,
  0x7e: 0x2443,
};

const _toggleProperties = <int, String>{
  0x0800: 'deleted',
  0x0801: 'inserted',
  0x0835: 'bold',
  0x0836: 'italic',
  0x0837: 'strike',
  0x083a: 'smallCaps',
  0x083b: 'allCaps',
  0x083c: 'hidden',
  0x2a53: 'doubleStrike',
  0x0855: 'special',
};
const _palette = <String?>[
  null,
  '000000',
  '0000FF',
  '00FFFF',
  '00FF00',
  'FF00FF',
  'FF0000',
  'FFFF00',
  'FFFFFF',
  '000080',
  '008080',
  '008000',
  '800080',
  '800000',
  '808000',
  '808080',
  'C0C0C0',
];

bool _toggle(int value, Object? style) => switch (value) {
  0 => false,
  1 => true,
  0x80 => style == true,
  0x81 => style != true,
  _ => throw const FormatException('Invalid Word formatting toggle.'),
};
bool _boolean(_Bytes value) {
  final byte = value.u8(0);
  if (byte > 1) throw const FormatException('Invalid Word Boolean property.');
  return byte != 0;
}

String? _colorIndex(int index) {
  if (index >= _palette.length) {
    throw const FormatException('Invalid Word color index.');
  }
  return _palette[index];
}

String? _color(_Bytes data) {
  final auto = data.u8(3);
  if (auto == 0xff) return null;
  if (auto != 0) throw const FormatException('Invalid Word color value.');
  return [
    data.u8(0),
    data.u8(1),
    data.u8(2),
  ].map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

void _applyCharacter(
  List<_Sprm> operations,
  _Props output,
  _Props style,
  _Budget budget,
  Set<LegacyWordWarning> warnings, {
  _Props? paragraphStyle,
  _Props Function(int)? resolveCharacterStyle,
}) {
  final paragraph = paragraphStyle ?? style;
  var activeStyle = style;
  void resetVisualProperties(_Props properties) {
    for (final key in [
      'bold',
      'italic',
      'underline',
      'underlineStyle',
      'strike',
      'doubleStrike',
      'smallCaps',
      'allCaps',
      'hidden',
      'fontSize',
      'fontIndex',
      'eastAsianFontIndex',
      'nonAsciiFontIndex',
      'complexScriptFontIndex',
      'color',
      'verticalAlign',
      'position',
      'spacing',
      'kerning',
    ]) {
      output[key] = properties[key];
    }
  }

  for (final operation in operations) {
    if (operation.group != 2) continue;
    budget.apply();
    final data = operation.data;
    final toggle = _toggleProperties[operation.code];
    if (toggle != null) {
      output[toggle] = _toggle(data.u8(0), activeStyle[toggle]);
      continue;
    }
    switch (operation.code) {
      case 0x6a09:
        // CSymbol designates the character as a symbol and sets fSpec.
        // A subsequent CFSpec operation can explicitly override that flag.
        output['symbolFontIndex'] = data.u16(0);
        output['symbolCharacterCode'] = data.u16(2);
        output['special'] = true;
      case 0x2a3e:
        final kind = data.u8(0);
        final name = _underlineStyles[kind];
        if (name == null) {
          throw const FormatException('Invalid Word underline style.');
        }
        output['underline'] = kind != 0;
        output['underlineStyle'] = name;
      case 0x4a43:
        final size = data.u16(0);
        if (size < 2 || size > 3276) {
          throw const FormatException('Invalid Word font size.');
        }
        output['fontSize'] = size;
      case 0x4a4f:
        output['fontIndex'] = data.i16(0);
      case 0x4a50:
        output['eastAsianFontIndex'] = data.i16(0);
      case 0x4a51:
        output['nonAsciiFontIndex'] = data.i16(0);
      case 0x4a5e:
        output['complexScriptFontIndex'] = data.i16(0);
      case 0x4a30:
        final index = data.u16(0);
        if (resolveCharacterStyle == null) {
          warnings.add(LegacyWordWarning.unsupportedFormatting);
        } else {
          activeStyle = {...paragraph, ...resolveCharacterStyle(index)};
          resetVisualProperties(activeStyle);
        }
        output['characterStyle'] = index;
      case 0x2a42:
        output['color'] = _colorIndex(data.u8(0));
      case 0x6870:
        output['color'] = _color(data);
      case 0x2a0c:
        output['highlight'] = _colorIndex(data.u8(0));
      case 0x2a48:
        final value = data.u8(0);
        if (value > 2) {
          throw const FormatException('Invalid Word vertical text position.');
        }
        output['verticalAlign'] = value;
      case 0x4845:
        final position = data.i16(0);
        if (position < -3168 || position > 3168) {
          throw const FormatException('Invalid Word text position.');
        }
        output['position'] = position;
      case 0x484b:
        final threshold = data.i16(0);
        if (threshold < 0 || threshold > 3276) {
          throw const FormatException('Invalid Word kerning threshold.');
        }
        output['kerning'] = threshold;
      case 0x8840:
        output['spacing'] = _wordTwipMeasurement(data.i16(0));
      case 0x2a83:
        output['_oldCharacter'] = _boolean(data)
            ? _revisionSnapshot(output)
            : null;
      case 0xca57:
      case 0xca89:
        _applyPropertyRevision(data, output, 'character');
      case 0xca62:
        output['displayFieldRevision'] = _displayFieldRevisionRecord(data);
      case 0x6815:
        output['formattingSaveId'] = data.u32(0);
      case 0x6816:
        output['insertionSaveId'] = data.u32(0);
      case 0x6817:
        output['deletionSaveId'] = data.u32(0);
      case 0x4807:
        output['insertionReason'] = data.u16(0);
      case 0x4867:
        output['deletionReason'] = data.u16(0);
      case 0x4804:
        output['insertionAuthor'] = data.u16(0);
      case 0x4863:
        output['deletionAuthor'] = data.u16(0);
      case 0x6805:
        output['insertionDate'] = data.u32(0);
      case 0x6864:
        output['deletionDate'] = data.u32(0);
      case 0x2a33:
        activeStyle = paragraph;
        resetVisualProperties(paragraph);
        output['characterStyle'] = 10;
      case 0x6a03:
        output['pictureLocation'] = data.i32(0);
      case 0x0806:
        output['data'] = _boolean(data);
      case 0x080a:
        output['ole2'] = _boolean(data);
      case 0x0856:
        // CFObj is Bool8; CFSpec and the visual flags use ToggleOperand.
        output['object'] = _boolean(data);
      // Language, proofing and revision-save identifiers do not change the
      // supported visual properties. Script language selection remains a limit.
      case 0x486d:
      case 0x4873:
      case 0x4874:
      case 0x4a41:
      case 0x680e:
      case 0x0802:
        break;
      default:
        output['_unsupportedCharacter'] = true;
        warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
  }
}

// MS-DOC Kul and the corresponding WordprocessingML ST_Underline values.
// In particular 0x14 is heavy dotted, not the wavy style used by some readers.
const _underlineStyles = <int, String>{
  0x00: 'none',
  0x01: 'single',
  0x02: 'words',
  0x03: 'double',
  0x04: 'dotted',
  0x06: 'thick',
  0x07: 'dash',
  0x09: 'dotDash',
  0x0a: 'dotDotDash',
  0x0b: 'wave',
  0x14: 'dottedHeavy',
  0x17: 'dashedHeavy',
  0x19: 'dashDotHeavy',
  0x1a: 'dashDotDotHeavy',
  0x1b: 'wavyHeavy',
  0x27: 'dashLong',
  0x2b: 'wavyDouble',
  0x37: 'dashLongHeavy',
};

class _TableDefinition {
  const _TableDefinition(this.edges, this.flags, [this.formats = const []]);
  final List<int> edges;
  final List<int> flags;
  final List<LegacyWordTableCellFormat> formats;
}

void _applyParagraph(
  List<_Sprm> operations,
  _Props output,
  _Budget budget,
  Set<LegacyWordWarning> warnings, {
  _Props Function(int)? resolveParagraphStyle,
}) {
  for (
    var operationIndex = 0;
    operationIndex < operations.length;
    operationIndex++
  ) {
    final operation = operations[operationIndex];
    if (operation.group != 1 && operation.group != 5) continue;
    budget.apply();
    _trackTableRevisionOperation(operation, output);
    if (_applyParagraphLayout(operation, output)) continue;
    final value = operation.data;
    switch (operation.code) {
      case 0x4600:
        final index = value.u16(0);
        if (resolveParagraphStyle != null) {
          final preserved = <String, Object?>{
            for (final entry in output.entries)
              if (_paragraphStylePreserved.contains(entry.key) ||
                  entry.key.startsWith('table') ||
                  entry.key.startsWith('cell') ||
                  entry.key.startsWith('paragraphRevision'))
                entry.key: entry.value,
          };
          output
            ..clear()
            ..addAll(resolveParagraphStyle(index))
            ..addAll(preserved);
        }
        output['styleIndex'] = index;
      case 0x2664:
        output['_oldParagraph'] = _boolean(value)
            ? _revisionSnapshot(output)
            : null;
      case 0xc63f:
      case 0xc66f:
        _applyPropertyRevision(value, output, 'paragraph');
      case 0x6467:
        output['paragraphSaveId'] = value.u32(0);
      case 0x2443:
        output['numberingInserted'] = _boolean(value);
      case 0xc645:
        output['numberingRevisionRecord'] = _numberingRevisionRecord(value);
      case 0x2403:
      case 0x2461:
        final alignment = value.u8(0);
        if (alignment > 9) {
          throw const FormatException('Invalid Word paragraph alignment.');
        }
        output['alignment'] = alignment;
        if (alignment > 4) {
          warnings.add(LegacyWordWarning.unsupportedFormatting);
        }
      case 0x2405:
        output['keepTogether'] = _boolean(value);
      case 0x2406:
        output['keepNext'] = _boolean(value);
      case 0x2407:
        output['pageBreakBefore'] = _boolean(value);
      case 0x2416:
        final inTable = _boolean(value);
        output['inTable'] = inTable;
        // PFInTable is the Word 97 representation. Later PItap/PDtap values
        // replace its implied depth; a false value clears it in sequence.
        if (!inTable) {
          output['tableDepth'] = 0;
        } else if ((output['tableDepth'] as int? ?? 0) == 0) {
          output['tableDepth'] = 1;
        }
      case 0x2417:
        output['rowEnd'] = _boolean(value);
      case 0x244b:
        output['innerCellEnd'] = _boolean(value);
      case 0x244c:
        output['innerRowEnd'] = _boolean(value);
      case 0x6649:
        final depth = value.u32(0);
        if (depth > 63) {
          throw const FormatException('Invalid Word table nesting.');
        }
        output['tableDepth'] = depth;
        output['inTable'] = depth != 0;
      case 0x664a:
        final depth = (output['tableDepth'] as int? ?? 0) + value.i32(0);
        if (depth < 0 || depth > 63) {
          throw const FormatException('Invalid Word table nesting adjustment.');
        }
        output['tableDepth'] = depth;
        output['inTable'] = depth != 0;
      case 0x3404:
        output['rowHeader'] = _boolean(value);
      case 0x3668:
        output['tableRevisionSnapshot'] = _boolean(value)
            ? _TableRowRevisionSnapshot(output)
            : null;
        output.remove('tableRevisionUnsupportedOperations');
      case 0xd667:
        _applyPropertyRevision(value, output, 'table');
      case 0x3403:
        output['tableCantSplit90'] = _boolean(value);
      case 0x3466:
        output['tableCantSplit'] = _boolean(value);
      case 0x9407:
        final height = value.i16(0);
        if (height < -31680 || height > 31680) {
          throw const FormatException('Invalid Word table row height.');
        }
        output['tableRowHeight'] = height;
      case 0x563a:
        _resetTableStyleProperties(output);
        output['tableStyleId'] = value.u16(0);
      case 0x7469:
        output['tableGroup'] = value.u32(0);
        // Identity prevents merging unrelated adjacent tables, but this
        // bounded path does not interpret the referenced PGP hierarchy.
        warnings.add(LegacyWordWarning.unsupportedFormatting);
      case 0x560b:
      case 0x5664:
        final direction = value.u16(0);
        if (direction > 1) {
          throw const FormatException('Invalid Word table direction.');
        }
        output[operation.code == 0x560b ? 'tableRtl' : 'tableRtl90'] =
            direction != 0;
      case 0x5400:
      case 0x548a:
        final alignment = value.u16(0);
        if (alignment > 2) {
          throw const FormatException('Invalid Word table alignment.');
        }
        output[operation.code == 0x5400
                ? 'tablePhysicalAlignment'
                : 'tableAlignment'] =
            alignment;
      case 0x3615:
        output['tableAutoFit'] = _boolean(value);
      case 0x360d:
        // PositionCodeOperand's low four padding bits MUST be ignored.
        output['tablePosition${operation.code}'] = value.u8(0) & 0xf0;
      case 0x3465:
        output['tablePosition${operation.code}'] = _boolean(value) ? 1 : 0;
      case 0x940e:
      case 0x940f:
        final position = value.i16(0);
        if (position < -31679 || position > 31681) {
          throw const FormatException('Invalid Word table absolute position.');
        }
        output['tablePosition${operation.code}'] = position;
      case 0x9410:
      case 0x9411:
      case 0x941e:
      case 0x941f:
        final distance = value.u16(0);
        if (distance > 31680) {
          throw const FormatException('Invalid Word table wrapping distance.');
        }
        output['tablePosition${operation.code}'] = distance;
      case 0x740a:
        output['tableStyleOptions'] = value.u16(2);
      case 0xd605:
      case 0xd613:
        output['tableBorders'] =
            Map<LegacyWordTableBorderSide, LegacyWordBorder>.unmodifiable({
              ...?output['tableBorders']
                  as Map<LegacyWordTableBorderSide, LegacyWordBorder>?,
              ..._readTableBorders(value, old: operation.code == 0xd605),
            });
      case 0xd632:
      case 0xd634:
        final wholeRow = operation.code == 0xd634;
        final (first, limit, margins) = _readTableMargins(
          value,
          wholeRow: wholeRow,
        );
        if (wholeRow) {
          output['tableMargins'] =
              Map<LegacyWordBorderSide, int?>.unmodifiable({
                ...?output['tableMargins'] as Map<LegacyWordBorderSide, int?>?,
                ...margins,
              });
        } else {
          _tableCellRange(value, output);
          final all = <int, Map<LegacyWordBorderSide, int?>>{
            ...?output['cellMargins']
                as Map<int, Map<LegacyWordBorderSide, int?>>?,
          };
          for (var i = first; i < limit; i++) {
            all[i] = Map.unmodifiable({...?all[i], ...margins});
          }
          output['cellMargins'] =
              Map<int, Map<LegacyWordBorderSide, int?>>.unmodifiable(all);
        }
      case 0x7621:
      case 0x5622:
      case 0x7623:
      case 0x5624:
      case 0x5625:
        _changeTableCells(operation, output);
      case 0xd62c:
        if (value.length != 3 || value.u8(2) > 2) {
          throw const FormatException('Invalid Word cell-alignment range.');
        }
        final (first, limit) = _tableCellRange(value, output);
        output['cellAlignment'] = Map<int, int>.unmodifiable({
          ...?output['cellAlignment'] as Map<int, int>?,
          for (var i = first; i < limit; i++) i: value.u8(2),
        });
      case 0xd635:
        if (value.length != 5) {
          throw const FormatException(
            'Invalid Word preferred cell-width operand.',
          );
        }
        final (first, limit) = _tableCellRange(value, output);
        final width = _tableCellPreferredWidth(value.u8(2), value.i16(3));
        _applyTableCellFormatRange(
          output,
          first,
          limit,
          LegacyWordTableCellFormat(preferredWidth: width),
        );
      case 0xd639:
        if (value.length != 3 || value.u8(2) > 1) {
          throw const FormatException('Invalid Word cell no-wrap operand.');
        }
        final (first, limit) = _tableCellRange(value, output);
        _applyTableCellFormatRange(
          output,
          first,
          limit,
          LegacyWordTableCellFormat(noWrap: value.u8(2) != 0),
        );
      case 0xd620:
      case 0xd62f:
        final old = operation.code == 0xd620;
        final definition = output['tableDefinition'] as _TableDefinition?;
        final width = old ? 4 : 8;
        if (value.length != 3 + width || definition == null) {
          throw const FormatException('Invalid Word cell border range.');
        }
        final first = value.u8(0), limit = value.u8(1), sides = value.u8(2);
        if (first >= definition.flags.length ||
            limit < first ||
            limit > definition.flags.length) {
          throw const FormatException('Invalid Word cell border range.');
        }
        if (sides > (old ? 15 : 63)) {
          // WPS writes a redundant old nil diagonal border immediately before
          // the equivalent modern operation. The old operand cannot express
          // diagonal sides. Ignore only this exact corroborated pair, retaining
          // the normal cell bounds and the next operation's validated value.
          final next = operationIndex + 1 < operations.length
              ? operations[operationIndex + 1]
              : null;
          if (!old ||
              (sides != 0x10 && sides != 0x20) ||
              value.u32(3) != 0xffffffff ||
              next?.code != 0xd62f ||
              next!.data.length != 11 ||
              next.data.u8(0) != first ||
              next.data.u8(1) != limit ||
              next.data.u8(2) != sides ||
              next.data.u32(3) != 0xffffffff ||
              next.data.u32(7) != 0xffffffff) {
            throw const FormatException('Invalid Word cell border range.');
          }
          warnings.add(LegacyWordWarning.recoveredLegacyDiagonalBorder);
          continue;
        }
        final border = _readTableBorder(
          _Bytes(value.slice(3, width)),
          old: old,
        );
        if (border == null) continue;
        final borders = <LegacyWordTableBorderSide, LegacyWordBorder>{
          for (var side = 0; side < (old ? 4 : 6); side++)
            if ((sides & (1 << side)) != 0)
              LegacyWordTableBorderSide.values[side < 4 ? side : side + 2]:
                  border,
        };
        output['tableDefinition'] =
            _TableDefinition(definition.edges, definition.flags, [
              for (var i = 0; i < definition.flags.length; i++)
                _mergeTableCellFormat(
                  i < definition.formats.length
                      ? definition.formats[i]
                      : const LegacyWordTableCellFormat(),
                  i >= first && i < limit
                      ? LegacyWordTableCellFormat(borders: borders)
                      : const LegacyWordTableCellFormat(),
                ),
            ]);
      case 0x9601:
        final left = value.i16(0);
        output['tableDxaLeft'] = left;
        output['tableOrigin'] = left - (output['tableGapHalf'] as int? ?? 0);
      case 0x9602:
        final gap = value.i16(0);
        if (gap < 0) {
          throw const FormatException('Invalid Word table origin offset.');
        }
        final left =
            output['tableDxaLeft'] as int? ??
            (output['tableOrigin'] as int? ?? 0) +
                (output['tableGapHalf'] as int? ?? 0);
        output['tableGapHalf'] = gap;
        output['tableDxaLeft'] = left;
        output['tableOrigin'] = left - gap;
      case 0x840f:
      case 0x845e:
        output['leftIndent'] = _wordTwipMeasurement(value.i16(0));
      case 0x840e:
      case 0x845d:
        output['rightIndent'] = _wordTwipMeasurement(value.i16(0));
      case 0x8411:
      case 0x8460:
        output['firstIndent'] = _wordTwipMeasurement(value.i16(0));
      case 0xa413:
        output['before'] = _wordTwipMeasurement(
          value.u16(0),
          nonNegative: true,
        );
      case 0xa414:
        output['after'] = _wordTwipMeasurement(value.u16(0), nonNegative: true);
      case 0x6412:
        output['lineSpacing'] = _wordTwipMeasurement(value.i16(0));
        final multiple = value.u16(2);
        if (multiple > 1) {
          throw const FormatException('Invalid Word line-spacing value.');
        }
        output['lineMultiple'] = multiple == 1;
      case 0x2640:
        final level = value.u8(0);
        if (level > 9) {
          throw const FormatException('Invalid Word outline level.');
        }
        output['outline'] = level;
      case 0x460b:
        final id = value.i16(0);
        // 2047 is the pre-Word 97 ANLD marker, not an LFO index. Preserve it
        // while composing styles; the final list context rejects it unless
        // a descendant has replaced the old numbering with supported data.
        if (id < -2047 || id > 2047) {
          throw const FormatException('Invalid Word list-instance index.');
        }
        output['listId'] = id;
      case 0x260a:
        // The operand is ignored for non-list paragraphs. Resolve ilfo first,
        // including later properties and each retained revision snapshot.
        output['listLevel'] = value.u8(0);
      case 0xc60d:
      case 0xc615:
        output['tabs'] = _changeTabs(
          value,
          output['tabs'] as List<LegacyWordTabStop>? ?? const [],
          operation.code == 0xc615,
          budget,
        );
      case 0x442d:
      case 0xc64d:
        output['shading'] = _readShading(
          value,
          warnings,
          old: operation.code == 0x442d,
        );
      case >= 0x6424 && <= 0x6428:
      case 0x6629:
      case >= 0xc64e && <= 0xc653:
        final old = operation.code < 0x8000;
        final side = operation.code == 0x6629
            ? 5
            : operation.code - (old ? 0x6424 : 0xc64e);
        final border = _readParagraphBorder(value, old: old);
        if (border == null) continue;
        output['borders'] =
            Map<LegacyWordBorderSide, LegacyWordBorder>.unmodifiable({
              ...?output['borders']
                  as Map<LegacyWordBorderSide, LegacyWordBorder>?,
              LegacyWordBorderSide.values[side]: border,
            });
      case 0xd609:
        _applyCellShading(value, output, budget, warnings, old: true);
      case 0xd612:
      case 0xd616:
      case 0xd60c:
      case 0xd670:
      case 0xd671:
      case 0xd672:
        final first = switch (operation.code) {
          0xd616 || 0xd671 => 22,
          0xd60c || 0xd672 => 44,
          _ => 0,
        };
        _applyCellShading(
          value,
          output,
          budget,
          warnings,
          first: first,
          raw: operation.code >= 0xd670,
        );
      case 0xd608:
        final previousDefinition =
            output['tableDefinition'] as _TableDefinition?;
        final count = value.u8(0);
        if (count > 63) {
          throw const FormatException('Invalid Word table column count.');
        }
        value.require(1, (count + 1) * 2);
        final edges = [for (var i = 0; i <= count; i++) value.i16(1 + i * 2)];
        for (var i = 1; i < edges.length; i++) {
          if (edges[i] < edges[i - 1]) {
            throw const FormatException(
              'Word table boundaries are not ordered.',
            );
          }
        }
        final cellStart = 1 + (count + 1) * 2;
        final available = value.length - cellStart;
        if (available % 20 != 0) {
          throw const FormatException('Invalid Word table cell descriptors.');
        }
        final flags = [
          for (var i = 0; i < count; i++)
            i * 20 < available ? value.u16(cellStart + i * 20) : 0,
        ];
        if (flags.any((flag) => ((flag >> 5) & 3) == 2)) {
          throw const FormatException('Invalid Word vertical cell merge.');
        }
        final formats = <LegacyWordTableCellFormat>[];
        for (var i = 0; i < count; i++) {
          final flag = flags[i];
          final alignment = (flag >> 7) & 3;
          if (alignment > 2) {
            throw const FormatException('Invalid Word cell alignment.');
          }
          final direction = switch ((flag >> 2) & 7) {
            0 => LegacyWordCellTextDirection.lrTb,
            1 => LegacyWordCellTextDirection.tbRl,
            3 => LegacyWordCellTextDirection.btLr,
            4 => LegacyWordCellTextDirection.lrTbV,
            5 => LegacyWordCellTextDirection.tbRlV,
            _ => throw const FormatException('Invalid Word cell text flow.'),
          };
          final borders = <LegacyWordTableBorderSide, LegacyWordBorder>{};
          for (var side = 0; side < 4; side++) {
            final borderSide = LegacyWordTableBorderSide.values[side];
            final parsed = i * 20 < available
                ? _readTableBorder(
                    _Bytes(value.slice(cellStart + i * 20 + 4 + side * 4, 4)),
                    old: true,
                  )
                : const LegacyWordBorder(style: 'none', widthEighthPoints: 0);
            final border =
                parsed ??
                (i < (previousDefinition?.formats.length ?? 0)
                    ? previousDefinition!.formats[i].borders[borderSide]
                    : null);
            if (border != null) borders[borderSide] = border;
          }
          formats.add(
            LegacyWordTableCellFormat(
              borders: Map.unmodifiable(borders),
              verticalAlignment: LegacyWordCellAlignment.values[alignment],
              noWrap: (flag & 0x2000) != 0,
              preferredWidth: _tableCellPreferredWidth(
                (flag >> 9) & 7,
                i * 20 < available ? value.i16(cellStart + i * 20 + 2) : 0,
                tc80: true,
              ),
              textDirection: direction,
              fitText: (flag & 0x1000) != 0,
              hideMark: (flag & 0x4000) != 0,
            ),
          );
        }
        output['tableDefinition'] = _TableDefinition(edges, flags, formats);
        output['tableOrigin'] = edges.first;
        output['tableDxaLeft'] =
            edges.first + (output['tableGapHalf'] as int? ?? 0);
      // Section/table style properties beyond the represented subset are
      // reported rather than being represented as a different formatting.
      default:
        if (operation.group == 1) output['_unsupportedParagraph'] = true;
        if (operation.group == 5) {
          output['tableRevisionUnknownProperties'] = true;
        }
        warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
  }
}

Map<String, Object?> _sectionProperties(
  List<_Sprm> operations,
  _Budget budget,
  Set<LegacyWordWarning> warnings, {
  _Props initial = const {},
}) {
  final output = <String, Object?>{...initial};
  for (final operation in operations) {
    if (operation.group != 4) continue;
    budget.apply();
    if (_applySectionLayout(operation, output, warnings)) continue;
    final value = operation.data;
    switch (operation.code) {
      case 0x3009:
        final kind = value.u8(0);
        if (kind > 4) {
          throw const FormatException('Invalid Word section break.');
        }
        output['breakKind'] = kind;
      case 0x301d:
        final orientation = value.u8(0);
        if (orientation != 1 && orientation != 2) {
          throw const FormatException('Invalid Word page orientation.');
        }
        output['landscape'] = orientation == 2;
      case 0x300a:
        output['titlePage'] = _boolean(value);
      case 0xb01f:
        output['width'] = value.u16(0);
      case 0xb020:
        output['height'] = value.u16(0);
      case 0xb021:
        output['left'] = value.u16(0);
      case 0xb022:
        output['right'] = value.u16(0);
      case 0x9023:
        output['top'] = value.i16(0);
      case 0x9024:
        output['bottom'] = value.i16(0);
      case 0xb025:
        output['gutter'] = value.u16(0);
      case 0xb017:
        output['header'] = value.u16(0);
      case 0xb018:
        output['footer'] = value.u16(0);
      case 0x900c:
        output['columnsSpace'] = value.u16(0);
      case 0x500b:
        final columns = value.u16(0) + 1;
        if (columns > 44) {
          throw const FormatException('Invalid Word column count.');
        }
        output['columns'] = columns;
      case 0x703a:
        output['sectionSaveId'] = value.u32(0);
      case 0x3239:
        output['_oldSection'] = _boolean(value)
            ? _revisionSnapshot(output)
            : null;
      case 0xd243:
        _applyPropertyRevision(value, output, 'section');
      default:
        output['_unsupportedSection'] = true;
        warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
  }
  for (final key in ['width', 'height']) {
    if (output[key] case final int dimension) {
      if (dimension < 144 || dimension > 31680) {
        throw const FormatException('Invalid Word page dimension.');
      }
    }
  }
  return output;
}
