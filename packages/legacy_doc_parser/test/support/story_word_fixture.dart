// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'structured_word_fixture.dart';

/// Logical subdocuments are deliberately stored out of physical FC order.
Uint8List storyWordFixture({
  required String main,
  String footnotes = '',
  String headers = '',
  String comments = '',
  String endnotes = '',
  String textboxes = '',
  String headerTextboxes = '',
  Map<int, List<int>> tablePairs = const {},
  List<WordFixtureFkpRun> characterRuns = const [],
  List<WordFixtureFkpRun> paragraphRuns = const [],
  List<WordFixtureSection> sections = const [],
  void Function(ByteData, Uint8List)? mutate,
}) {
  final values = [
    main,
    footnotes,
    headers,
    comments,
    endnotes,
    textboxes,
    headerTextboxes,
  ];
  const offsets = [16384, 8192, 20480, 10240, 22528, 12288, 24576];
  final pieces = [
    for (var i = 0; i < values.length; i++)
      if (values[i].isNotEmpty)
        WordFixturePiece(values[i], offset: offsets[i], compressed: false),
  ];
  return StructuredWordFixture(
    pieces: pieces,
    mainCharacterCount: main.length,
    storyCounts: {
      4: footnotes.length,
      5: headers.length,
      7: comments.length,
      8: endnotes.length,
      9: textboxes.length,
      10: headerTextboxes.length,
    },
    characterRuns: characterRuns,
    paragraphRuns: paragraphRuns.isEmpty
        ? [const WordFixtureFkpRun(8192, 28672)]
        : paragraphRuns,
    extraTablePairs: tablePairs,
    sections: sections,
  ).build(mutate: mutate);
}

List<int> storyPlc(List<int> cps, [List<int> records = const []]) => [
  for (final cp in cps) ...wordU32(cp),
  ...records,
];

List<int> storyXst(String value) => [
  ...wordU16(value.length),
  for (final unit in value.codeUnits) ...wordU16(unit),
];

List<int> storyBookmarkNames(List<String> values) => [
  ...wordU16(0xffff),
  ...wordU16(values.length),
  ...wordU16(0),
  for (final value in values) ...storyXst(value),
];

List<int> storyCommentRecord({
  String initials = 'AB',
  int author = 0,
  int tag = -1,
}) => [
  ...storyXst(initials),
  ...List.filled(18 - initials.length * 2, 0),
  ...wordU16(author),
  ...wordU16(0),
  ...wordU16(0),
  ...wordU32(tag & 0xffffffff),
];
