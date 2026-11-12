// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'officeart_shape_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Literal independent ranges/ids model the retained native normal/first
/// header alias. They do not create a second FTXBXS or a text-flow link.
Uint8List headerTextboxAliasFixture({
  String rawText = 'ALPHA\r\r',
  int count = 1,
  int lid = 1025,
  int secondIndex = 0,
  int secondStory = 1,
  int? firstNext,
  int? secondNext,
  bool sameHeader = false,
  bool mainStory = false,
  bool firstFooter = false,
  bool extraOccurrence = false,
  int shapeFlags = 0xa00,
  int shapeType = 202,
  List<int> textProperties = const [],
  List<int> paragraphProperties = const [],
}) {
  final anchors = [2, sameHeader ? 3 : 5, if (extraOccurrence) 6];
  final headers = sameHeader
      ? '\r\r\x08\x08\r\r\r\r\r'
      : '\r\r\x08\r\r\x08\r\r\r';
  List<int> shape(int index) {
    final id = 1025 + index;
    final encoded = index == 0 ? 0x10000 : (secondStory << 16) | secondIndex;
    final next = index == 0 ? firstNext : secondNext;
    return officeArtRecord(0xf004, [
      ...officeArtRecord(
        0xf00a,
        [...wordU32(id), ...wordU32(shapeFlags)],
        version: 2,
        instance: shapeType,
      ),
      ...shapePropertyRecord(
        values: {0x0080: encoded, if (next != null) 0x008a: next},
      ),
      ...officeArtRecord(0xf00d, wordU32(encoded)),
    ], version: 15);
  }

  final textboxOffset = mainStory ? 12288 : 24576;
  return storyWordFixture(
    main: mainStory ? headers : 'Body\r',
    headers: mainStory ? '' : headers,
    textboxes: mainStory ? '${rawText}x' : '',
    headerTextboxes: mainStory ? '' : '${rawText}x',
    characterRuns: [
      WordFixtureFkpRun(8192, textboxOffset, properties: wordSprm(0x0855, [1])),
      WordFixtureFkpRun(
        textboxOffset,
        textboxOffset + 2 * rawText.length,
        properties: textProperties,
      ),
      WordFixtureFkpRun(
        textboxOffset + 2 * rawText.length,
        28672,
        properties: wordSprm(0x0855, [1]),
      ),
    ],
    paragraphRuns: paragraphProperties.isEmpty
        ? const []
        : [WordFixtureFkpRun(8192, 28672, properties: paragraphProperties)],
    tablePairs: {
      if (!mainStory)
        11: storyPlc([
          ...List.filled(7, 0),
          2,
          if (sameHeader) ...[
            6,
            6,
            6,
            8,
            8,
          ] else if (firstFooter) ...[
            5,
            5,
            5,
            5,
            8,
          ] else ...[
            5,
            5,
            5,
            8,
            8,
          ],
          10,
        ]),
      mainStory ? 40 : 41: storyPlc(
        [...anchors, 0xffffffff],
        [
          for (var i = 0; i < anchors.length; i++) ...[
            ...wordU32(1025 + i),
            ...wordU32(1440),
            ...wordU32(1440),
            ...wordU32(4320),
            ...wordU32(1880),
            ...wordU16(0x6a),
            ...wordU32(0),
          ],
        ],
      ),
      50: [
        ...officeArtRecord(0xf000, [], version: 15),
        mainStory ? 0 : 1,
        ...officeArtRecord(
          0xf002,
          officeArtRecord(0xf003, [
            for (var i = 0; i < anchors.length; i++) ...shape(i),
          ], version: 15),
          version: 15,
        ),
      ],
      mainStory ? 56 : 58: storyPlc(
        [0, rawText.length, rawText.length + 1],
        [
          ...wordU32(count),
          ...wordU32(0),
          ...wordU16(0),
          ...wordU32(0),
          ...wordU32(lid),
          ...wordU32(0),
          ...List.filled(22, 0),
        ],
      ),
    },
  );
}
