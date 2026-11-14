// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'nested_field_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

const fieldVisibilityCases = [
  ...nestedFieldCases,
  'visible-result-child',
  'character-hidden-result',
];

const fieldVisibilityExpectedText = {
  'formula': 'A999Z',
  'nested-results': 'AVisibleZ',
  'private-result': 'AZ',
  'private-instruction-result': 'AVisibleZ',
  'unsupported-result': 'AVisibleZ',
  'instruction-whitespace': 'ACachedZ',
  'nested-instruction-whitespace': 'AVisibleZ',
  'cached-controls': 'Aco\u2011op\u00aderate\x0enextZ',
  'nested-cached-controls': 'AVisibleZ',
  'visible-result-child': 'Abefore7afterZ',
  'character-hidden-result': 'AZ',
};

const fieldVisibilityExpectedFields = {
  'formula': 1,
  'nested-results': 3,
  'private-result': 1,
  'private-instruction-result': 2,
  'unsupported-result': 2,
  'instruction-whitespace': 1,
  'nested-instruction-whitespace': 2,
  'cached-controls': 1,
  'nested-cached-controls': 2,
  'visible-result-child': 2,
  'character-hidden-result': 1,
};

Uint8List fieldVisibilityFixture(String name) {
  if (nestedFieldCases.contains(name)) return nestedFieldFixture(name);
  if (name == 'visible-result-child') {
    return storyWordFixture(
      main: 'A\x13 QUOTE "outer" \x14before\x13 PAGE \x147\x15after\x15Z\r',
    );
  }
  if (name == 'character-hidden-result') {
    // This uses ordinary character formatting, not fPrivateResult. The entire
    // source field is hidden; its visible surrounding text remains unchanged.
    // A missing REF also tests native importers that recalculate despite locks.
    const text = 'A\x13 REF Missing \x14Secret\x15Z\r';
    final start = text.indexOf('\x13'), end = text.indexOf('\x15') + 1;
    return StructuredWordFixture(
      pieces: const [WordFixturePiece(text)],
      characterRuns: [
        WordFixtureFkpRun(8192, 8192 + start),
        WordFixtureFkpRun(
          8192 + start,
          8192 + end,
          properties: wordSprm(0x083c, [1]),
        ),
        WordFixtureFkpRun(8192 + end, 8192 + text.length),
      ],
    ).build();
  }
  throw ArgumentError.value(name, 'name');
}
