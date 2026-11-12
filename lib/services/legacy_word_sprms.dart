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

List<_Sprm> _decodeSprms(Uint8List bytes, _Budget budget) {
  final input = _Bytes(bytes);
  final output = <_Sprm>[];
  var position = 0;
  while (position < input.length) {
    final remaining = input.length - position;
    if (remaining <= 2 && bytes.skip(position).every((byte) => byte == 0)) {
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
  }
  return output;
}

const _prm0Codes = <int, int>{
  0x04: 0x2602,
  0x05: 0x2403,
  0x06: 0x2404,
  0x07: 0x2405,
  0x08: 0x2406,
  0x09: 0x2407,
  0x0a: 0x2408,
  0x0c: 0x260a,
  0x0d: 0x240c,
  0x0e: 0x240d,
  0x18: 0x2416,
  0x19: 0x2417,
  0x1d: 0x2423,
  0x25: 0x242a,
  0x2c: 0x2430,
  0x2d: 0x2431,
  0x2e: 0x2433,
  0x2f: 0x2434,
  0x30: 0x2435,
  0x31: 0x2436,
  0x32: 0x2437,
  0x33: 0x2438,
  0x35: 0x243a,
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
      'strike',
      'doubleStrike',
      'smallCaps',
      'allCaps',
      'hidden',
      'fontSize',
      'fontIndex',
      'color',
      'verticalAlign',
      'position',
      'spacing',
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
      case 0x2a3e:
        final kind = data.u8(0);
        output['underline'] = kind != 0;
        if (kind > 1) warnings.add(LegacyWordWarning.unsupportedFormatting);
      case 0x4a43:
        final size = data.u16(0);
        if (size < 2 || size > 3276) {
          throw const FormatException('Invalid Word font size.');
        }
        output['fontSize'] = size;
      case 0x4a4f:
        output['fontIndex'] = data.u16(0);
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
      case 0x8840:
        output['spacing'] = data.i16(0);
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
        output['pictureLocation'] = data.u32(0);
      // Language, proofing and revision-save identifiers do not change the
      // supported visual properties. Alternate script fonts remain a limit.
      case 0x486d:
      case 0x4873:
      case 0x4874:
      case 0x4a41:
      case 0x680e:
      case 0x6815:
      case 0x6816:
      case 0x6817:
      case 0x0802:
      case 0x0806:
      case 0x080a:
        break;
      default:
        warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
  }
}

class _TableDefinition {
  const _TableDefinition(this.edges, this.flags);
  final List<int> edges;
  final List<int> flags;
}

void _applyParagraph(
  List<_Sprm> operations,
  _Props output,
  _Budget budget,
  Set<LegacyWordWarning> warnings,
) {
  for (final operation in operations) {
    if (operation.group != 1 && operation.group != 5) continue;
    budget.apply();
    final value = operation.data;
    switch (operation.code) {
      case 0x4600:
        output['styleIndex'] = value.u16(0);
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
        output['inTable'] = _boolean(value);
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
      case 0x3404:
        output['rowHeader'] = _boolean(value);
      case 0x840f:
      case 0x845e:
        output['leftIndent'] = value.i16(0);
      case 0x840e:
      case 0x845d:
        output['rightIndent'] = value.i16(0);
      case 0x8411:
      case 0x8460:
        output['firstIndent'] = value.i16(0);
      case 0xa413:
        output['before'] = value.u16(0);
      case 0xa414:
        output['after'] = value.u16(0);
      case 0x6412:
        output['lineSpacing'] = value.i16(0);
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
        output['listId'] = value.i16(0);
      case 0x260a:
        final level = value.u8(0);
        if (level > 8) throw const FormatException('Invalid Word list level.');
        output['listLevel'] = level;
      case 0xd608:
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
        output['tableDefinition'] = _TableDefinition(edges, flags);
      // Section/table style properties beyond the represented subset are
      // reported rather than being represented as a different formatting.
      default:
        warnings.add(LegacyWordWarning.unsupportedFormatting);
    }
  }
}

Map<String, Object?> _sectionProperties(
  List<_Sprm> operations,
  _Budget budget,
  Set<LegacyWordWarning> warnings,
) {
  final output = <String, Object?>{};
  for (final operation in operations) {
    if (operation.group != 4) continue;
    budget.apply();
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
        break; // revision save ID
      default:
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
