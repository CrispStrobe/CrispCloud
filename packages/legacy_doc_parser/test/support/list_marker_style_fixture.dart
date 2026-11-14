// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'list_boolean_style_fixture.dart';
import 'list_sparse_style_fixture.dart';
import 'list_word_fixture.dart';
import 'structured_word_fixture.dart';

final listMarkerStyleCases = List<String>.unmodifiable([
  'inherited-nullable',
  'explicit-overrides',
  'explicit-resets',
  'native-all-properties',
  'native-named-highlight',
  'native-hidden',
  'native-font-slots',
  'native-color-reset',
  ...listBooleanStyleCases,
  ...listSparseStyleCases,
]);

Uint8List listMarkerStyleFixture(String name) {
  if (!listMarkerStyleCases.contains(name)) throw ArgumentError.value(name);
  if (listBooleanStyleCases.contains(name)) {
    return listBooleanStyleFixture(name);
  }
  if (listSparseStyleCases.contains(name)) {
    return listSparseStyleFixture(name);
  }
  final literal = !name.startsWith('native-');
  final parent = [
    ...wordSprm(0x4a43, wordU16(48)),
    ...wordSprm(0x6870, [0xaa, 0x11, 0x22, 0]),
    ...wordSprm(0x2a0c, [7]),
    ...wordSprm(0x4845, wordU16(6)),
    ...wordSprm(0x8840, wordU16(30)),
  ];
  final marker = switch (name) {
    'inherited-nullable' => <int>[],
    'explicit-overrides' => [
      ...wordSprm(0x4a43, wordU16(20)),
      ...wordSprm(0x6870, [0x11, 0x22, 0x33, 0]),
      ...wordSprm(0x2a0c, [4]),
      ...wordSprm(0x4845, wordU16(2)),
      ...wordSprm(0x8840, wordU16(10)),
    ],
    'explicit-resets' => [
      ...wordSprm(0x2a42, [0]),
      ...wordSprm(0x2a0c, [0]),
      ...wordSprm(0x4845, wordU16(0)),
      ...wordSprm(0x8840, wordU16(0)),
    ],
    'native-all-properties' => [
      for (final code in [0x0835, 0x0836, 0x0837, 0x083a, 0x083b, 0x2a53])
        ...wordSprm(code, [1]),
      ...wordSprm(0x2a3e, [3]),
      ...wordSprm(0x4a43, wordU16(30)),
      ...wordSprm(0x484b, wordU16(8)),
      ...wordSprm(0x6870, [0x12, 0x34, 0x56, 0]),
      ...wordSprm(0x2a0c, [7]),
      ...wordSprm(0x2a48, [2]),
      ...wordSprm(0x4845, wordU16(2)),
      ...wordSprm(0x8840, wordU16(0xfff1)),
    ],
    'native-named-highlight' => wordSprm(0x2a0c, [7]),
    'native-hidden' => wordSprm(0x083c, [1]),
    'native-font-slots' => [
      ...wordSprm(0x4a4f, wordU16(1)),
      ...wordSprm(0x4a51, wordU16(2)),
      ...wordSprm(0x4a50, wordU16(3)),
      ...wordSprm(0x4a5e, wordU16(4)),
    ],
    'native-color-reset' => wordSprm(0x2a42, [0]),
    _ => throw ArgumentError.value(name),
  };
  return listWordFixture(
    levels: [
      listFixtureLevel(
        start: 7,
        text: literal ? '%1' : '\x00.',
        placeholders: literal ? [] : [1],
        character: marker,
      ),
    ],
    styles: {
      0: WordFixtureStyle(
        name: 'Normal',
        builtinId: 0,
        characterProperties: literal || name == 'native-color-reset'
            ? parent
            : const [],
      ),
    },
    extraTablePairs: {
      15: [
        ...wordU16(5),
        ...wordU16(0),
        for (final name in [
          'Default Font',
          'Marker ASCII',
          'Marker NonASCII',
          'Marker EastAsia',
          'Marker Complex',
        ]) ...[
          41 + name.length * 2,
          ...List.filled(39, 0),
          for (final unit in name.codeUnits) ...wordU16(unit),
          ...wordU16(0),
        ],
      ],
    },
  );
}
