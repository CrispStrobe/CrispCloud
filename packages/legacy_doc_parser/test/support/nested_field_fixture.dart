// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'story_word_fixture.dart';

const _sources = {
  // Deliberately stale cached value: conversion must never evaluate 1 + 1.
  'formula': 'A\x13 = 1 + 1 \x14999\x15Z\r',
  'nested-results':
      'A\x13 IF \x13 REF Name \x14pre\x13 PAGE \x142\x15post\x15 '
      '= "pre2post" "yes" "no" \x14Visible\x15Z\r',
  'private-result':
      'A\x13 REF Hidden \x14before\x13 QUOTE "PrivateInstruction" '
      '\x14PrivateResult\x15after\x15Z\r',
  'private-instruction-result':
      'A\x13 IF \x13 REF Hidden \x14before\x13 QUOTE "PrivateInstruction" '
      '\x14PrivateResult\x15after\x15 = "" "yes" "no" '
      '\x14Visible\x15Z\r',
  'unsupported-result':
      'A\x13 IF \x13 REF Name \x14pre\x13 INCLUDETEXT "https://invalid.test/" '
      '\x14cached\x15post\x15 = "precachedpost" "yes" "no" '
      '\x14Visible\x15Z\r',
  'instruction-whitespace':
      'A\x13 QUOTE "one\ttwo\rthree\nfour\r\nfive & <six> 😀" '
      '\x14Cached\x15Z\r',
  'nested-instruction-whitespace':
      'A\x13 IF "before\tafter" = "before\tafter" '
      '\x13 QUOTE "one\ttwo" \x14Child\x15 "no\r\nyes" '
      '\x14Visible\x15Z\r',
  'cached-controls':
      'A\x13 QUOTE "cached" \x14co\x1eop\x1ferate\x0enext\x15Z\r',
  'nested-cached-controls':
      'A\x13 IF \x13 QUOTE "cached" '
      '\x14co\x1eop\x1ferate\x0enext\x0cpage\x0bline\rcarriage\nnewline\ttab\x07cell\x15 '
      '= "comparison" "yes" "no" \x14Visible\x15Z\r',
};

const nestedFieldCases = [
  'formula',
  'nested-results',
  'private-result',
  'private-instruction-result',
  'unsupported-result',
  'instruction-whitespace',
  'nested-instruction-whitespace',
  'cached-controls',
  'nested-cached-controls',
];

/// Independently assembled binary controls shared by VM, JS and schema gates.
Uint8List nestedFieldFixture(String name) {
  final source = _sources[name];
  if (source == null) throw ArgumentError.value(name, 'name');
  return storyWordFixture(
    main: source,
    tablePairs: {
      if (name == 'private-result')
        16: _fieldPlc(source, {source.lastIndexOf('\x15')}),
      if (name == 'private-instruction-result')
        16: _fieldPlc(source, {source.indexOf(' =') - 1}),
    },
  );
}

List<int> _fieldPlc(String text, Set<int> privateEnds) {
  final positions = <int>[], records = <int>[];
  var depth = 0;
  for (var cp = 0; cp < text.length; cp++) {
    final unit = text.codeUnitAt(cp);
    if (!const [19, 20, 21].contains(unit)) continue;
    positions.add(cp);
    var flags = 0;
    if (unit == 19) depth++;
    if (unit == 21) {
      flags =
          0x80 | (depth > 1 ? 0x40 : 0) | (privateEnds.contains(cp) ? 0x20 : 0);
      depth--;
    }
    records.addAll([unit, flags]);
  }
  return storyPlc([...positions, 0xffffffff], records);
}
