// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'list_word_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

const listVisibilityKinds = [
  'empty',
  'hidden-body',
  'hidden-marker',
  'empty-middle',
  'private-only',
  'private-blank-middle',
  'instruction-blank-middle',
  'instruction-body-second',
  'separator-at-start',
  'private-end-visible',
  'result-second',
];

final listVisibilityCases = List<String>.unmodifiable([
  for (final prefix in ['decimal', 'literal'])
    for (final kind in listVisibilityKinds) '$prefix-$kind',
]);

String listVisibilitySourceText(String name) =>
    switch (name.substring(name.indexOf('-') + 1)) {
      'empty' => '\r',
      'empty-middle' => 'A\r\rB\r',
      'private-only' => '\x13 PAGE \x14Secret\x15\r',
      'private-blank-middle' => '\x13 PAGE \x14\r\r\x15\r',
      'instruction-blank-middle' => '\x13 QUOTE "a\r\rb" \x14Result\x15\r',
      'instruction-body-second' => '\x13 QUOTE "a\r b" \x14Result\x15\r',
      'separator-at-start' => '\x13 QUOTE "a"\r\x14Result\x15\r',
      'private-end-visible' => '\x13 PAGE \x14\r\r\x15After\rOutside\r',
      'result-second' => '\x13 QUOTE "x" \x14First\rSecond\x15\r',
      _ => 'Body\r',
    };

/// Independent expected label visibility for every source paragraph. Hidden
/// field paragraphs still consume counters; source CP positions are retained.
List<String> listVisibilityExpectedLabels(String name) {
  final kind = name.substring(name.indexOf('-') + 1);
  final labels = switch (kind) {
    'hidden-marker' => [''],
    'empty-middle' => ['7.', '8.', '9.'],
    'private-blank-middle' || 'instruction-blank-middle' => ['7.', '', ''],
    'instruction-body-second' || 'separator-at-start' => ['7.', ''],
    'private-end-visible' => ['7.', '', '', '10.'],
    'result-second' => ['7.', '8.'],
    _ => ['7.'],
  };
  return name.startsWith('literal-')
      ? [for (final label in labels) label.isEmpty ? '' : '%1']
      : labels;
}

List<String> listVisibilityExpectedBodies(String name) =>
    switch (name.substring(name.indexOf('-') + 1)) {
      'hidden-marker' => ['Body'],
      'empty-middle' => ['A', '', 'B'],
      'private-blank-middle' => ['', '', ''],
      'instruction-blank-middle' => ['', '', 'Result'],
      'instruction-body-second' || 'separator-at-start' => ['', 'Result'],
      'private-end-visible' => ['', '', 'After', 'Outside'],
      'result-second' => ['First', 'Second'],
      _ => [''],
    };

int listVisibilitySuppressedLabels(String name) =>
    switch (name.substring(name.indexOf('-') + 1)) {
      'private-blank-middle' ||
      'instruction-blank-middle' ||
      'private-end-visible' => 2,
      'instruction-body-second' || 'separator-at-start' => 1,
      _ => 0,
    };

Uint8List listVisibilityFixture(String name) {
  if (!listVisibilityCases.contains(name)) throw ArgumentError.value(name);
  final literal = name.startsWith('literal-');
  final kind = name.substring(name.indexOf('-') + 1);
  final text = listVisibilitySourceText(name);
  final runs = <WordFixtureFkpRun>[];
  if (kind == 'hidden-body') {
    runs.add(WordFixtureFkpRun(8192, 8196, properties: wordSprm(0x083c, [1])));
    runs.add(WordFixtureFkpRun(8196, 8197, properties: wordSprm(0x083c, [0])));
  }
  if (text.startsWith('\x13')) {
    var start = 0;
    for (var cp = 0; cp < text.length; cp++) {
      if (![19, 20, 21].contains(text.codeUnitAt(cp))) continue;
      if (start < cp) runs.add(WordFixtureFkpRun(8192 + start, 8192 + cp));
      // MS-DOC Plcfld requires CFSpec on each source field character.
      runs.add(
        WordFixtureFkpRun(
          8192 + cp,
          8192 + cp + 1,
          properties: wordSprm(0x0855, [1]),
        ),
      );
      start = cp + 1;
    }
    if (start < text.length) {
      runs.add(WordFixtureFkpRun(8192 + start, 8192 + text.length));
    }
  }
  final paragraphs = <WordFixtureFkpRun>[];
  var start = 0;
  for (var cp = 0; cp < text.length; cp++) {
    if (text.codeUnitAt(cp) != 13) continue;
    paragraphs.add(
      WordFixtureFkpRun(
        8192 + start,
        8192 + cp + 1,
        properties: [
          ...wordSprm(0x460b, wordU16(1)),
          ...wordSprm(0x260a, [0]),
        ],
      ),
    );
    start = cp + 1;
  }
  return StructuredWordFixture(
    pieces: [WordFixturePiece(text)],
    characterRuns: runs,
    paragraphRuns: paragraphs,
    reuseFormattingRecords: true,
    extraTablePairs: {
      73: listFixtureDefinitions([
        listFixtureLevel(
          start: 7,
          text: literal ? '%1' : '\x00.',
          placeholders: literal ? [] : [1],
          character: kind == 'hidden-marker' ? wordSprm(0x083c, [1]) : [],
          paragraph: [
            ...wordSprm(0x845e, wordU16(720)),
            ...wordSprm(0x8460, wordU16(0xfe98)),
          ],
        ),
      ]),
      74: listFixtureInstances(),
      if (text.startsWith('\x13'))
        16: storyPlc(
          [0, text.indexOf('\x14'), text.indexOf('\x15'), 0xffffffff],
          [
            19,
            kind.startsWith('private-') ? 33 : 35,
            20,
            0,
            21,
            kind.startsWith('private-') ? 0xb0 : 0x90,
          ],
        ),
    },
  ).build(mutate: (word, _) => word.setUint32(158 + 73 * 8, 30, Endian.little));
}
