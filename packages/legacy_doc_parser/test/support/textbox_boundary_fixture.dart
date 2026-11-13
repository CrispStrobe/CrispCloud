// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'officeart_shape_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Literal FTXBXS ranges. Each real range includes its final separator CR;
/// any preceding CRs belong to the textbox content and are not synthesized.
Uint8List textboxBoundaryFixture(
  List<String> ranges, {
  bool header = false,
  Set<int> reusable = const {},
  int chainLength = 1,
  String? anchorText,
  List<WordFixtureFkpRun> characterRuns = const [],
  List<WordFixtureFkpRun> paragraphRuns = const [],
  Map<int, int> shapeProperties = const {},
  Map<int, Uint8List> shapeComplex = const {},
  List<(int, Uint8List)> globalBlips = const [],
}) {
  if (chainLength < 1 || (chainLength > 1 && ranges.length != 1)) {
    throw ArgumentError('A linked control has one shared FTXBXS range.');
  }
  final shapes = <(int, int, int)>[]; // shape ID, FTXBXS index, chain index
  for (var index = 0; index < ranges.length; index++) {
    if (reusable.contains(index)) continue;
    for (var chain = 0; chain < chainLength; chain++) {
      shapes.add((1025 + index * chainLength + chain, index, chain));
    }
  }
  final anchorStory =
      anchorText ?? 'M${List.filled(shapes.length, '\x08').join()}\r';
  final headerRange = '$anchorStory\r';
  final offsets = [0];
  for (final range in ranges) {
    offsets.add(offsets.last + range.length);
  }
  final text = '${ranges.join()}x'; // Final reusable range is ignored.
  List<int> shape((int, int, int) item) => officeArtRecord(0xf004, [
    ...officeArtRecord(
      0xf00a,
      [...wordU32(item.$1), ...wordU32(0xa00)],
      version: 2,
      instance: 202,
    ),
    ...shapePropertyRecord(
      values: {
        0x0080: ((item.$2 + 1) << 16) | item.$3,
        0x0081: 0,
        0x0082: 0,
        0x0083: 0,
        0x0084: 0,
        if (item.$3 + 1 < chainLength) 0x008a: item.$1 + 1,
        0x00bf: 0x00020002, // Explicit fit-shape-to-text.
        0x0181: 0x00ffffff,
        0x01bf: 0x00100010,
        0x01c0: 0x00000000,
        0x01ff: 0x00080008,
        0x038f: 0,
        0x0390: 1,
        0x0391: 0,
        0x0392: 1,
        ...shapeProperties,
      },
      complex: shapeComplex,
    ),
    ...officeArtRecord(0xf00d, wordU32(((item.$2 + 1) << 16) | item.$3)),
  ], version: 15);
  return storyWordFixture(
    main: header ? 'Body\r' : anchorStory,
    headers: header ? '$headerRange\r' : '',
    textboxes: header ? '' : text,
    headerTextboxes: header ? text : '',
    characterRuns: characterRuns.isNotEmpty
        ? characterRuns
        : [
            WordFixtureFkpRun(8192, 28672, properties: wordSprm(0x0855, [1])),
          ],
    paragraphRuns: paragraphRuns,
    tablePairs: {
      if (header)
        11: storyPlc([
          ...List.filled(8, 0),
          ...List.filled(5, headerRange.length),
          headerRange.length + 1,
        ]),
      header ? 41 : 40: storyPlc(
        [
          for (var index = 0; index < shapes.length; index++) index + 1,
          0xffffffff,
        ],
        [
          for (var index = 0; index < shapes.length; index++) ...[
            ...wordU32(shapes[index].$1),
            ...wordU32(1440 + index * 3600),
            ...wordU32(1440),
            ...wordU32(4320 + index * 3600),
            ...wordU32(1880),
            ...wordU16(0x6a),
            ...wordU32(0),
          ],
        ],
      ),
      50: [
        ...officeArtRecord(0xf000, [
          if (globalBlips.isNotEmpty)
            ...officeArtRecord(
              0xf001,
              [
                for (final (type, blip) in globalBlips)
                  ...blipStoreEntry(blip, type: type),
              ],
              version: 15,
              instance: globalBlips.length,
            ),
        ], version: 15),
        header ? 1 : 0,
        ...officeArtRecord(
          0xf002,
          officeArtRecord(0xf003, [
            for (final item in shapes) ...shape(item),
          ], version: 15),
          version: 15,
        ),
      ],
      header ? 58 : 56: storyPlc(
        [...offsets, text.length],
        [
          for (var index = 0; index < ranges.length; index++) ...[
            ...wordU32(chainLength),
            ...wordU32(0),
            ...wordU16(reusable.contains(index) ? 1 : 0),
            ...wordU32(0),
            ...wordU32(
              reusable.contains(index) ? 0 : 1025 + index * chainLength,
            ),
            ...wordU32(0),
          ],
          ...List.filled(22, 0),
        ],
      ),
    },
  );
}

const textboxBoundaryCases = <String, (String, List<String>)>{
  'content': ('ALPHA\r\r', ['ALPHA']),
  'empty': ('\r\r', ['']),
  'leading-blank': ('\rALPHA\r\r', ['', 'ALPHA']),
  'interior-blank': ('ALPHA\r\rBETA\r\r', ['ALPHA', '', 'BETA']),
  'trailing-blank': ('ALPHA\r\r\r', ['ALPHA', '']),
  'two-trailing-blanks': ('ALPHA\r\r\r\r', ['ALPHA', '', '']),
  'two-content-paragraphs': ('ALPHA\rBETA\r\r', ['ALPHA', 'BETA']),
};
