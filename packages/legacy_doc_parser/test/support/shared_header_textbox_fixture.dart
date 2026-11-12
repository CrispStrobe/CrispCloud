// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'media_word_fixture.dart';
import 'officeart_shape_fixture.dart';
import 'story_word_fixture.dart';
import 'structured_word_fixture.dart';

/// Independent PlcfHdd/FTXBXS/ClientTextbox records. Several header/footer
/// variants reference one singleton text story, without continuation links.
Uint8List sharedHeaderTextboxFixture({
  List<int> slots = const [1, 4],
  bool sameOwner = false,
  bool field = false,
  int declared = 1,
  int firstShape = 1025,
  List<int>? indices,
  List<int?>? nextShapes,
}) {
  if (slots.isEmpty || slots.any((slot) => slot < 0 || slot > 5)) {
    throw ArgumentError('Expected one or more header/footer variant slots.');
  }
  final anchorCps = <int>[];
  final ranges = <String>[];
  var cp = 0;
  for (var slot = 0; slot < 6; slot++) {
    final count = sameOwner
        ? (slot == slots.first ? slots.length : 0)
        : slots.where((value) => value == slot).length;
    final content = count == 0 ? '' : '${'\x08' * count}\r\r';
    for (var index = 0; index < count; index++) {
      anchorCps.add(cp + index);
    }
    ranges.add(content);
    cp += content.length;
  }
  final cps = List.filled(7, 0, growable: true);
  for (final range in ranges) {
    cps.add(cps.last + range.length);
  }
  const main = 'BODY\r';
  final headers = '${ranges.join()}\r';
  final text = field ? '\x13 PAGE \x14SHARED\x15\r\r' : 'SHARED\r\r';
  List<int> shape(int index) => officeArtRecord(0xf004, [
    ...officeArtRecord(
      0xf00a,
      [...wordU32(1025 + index), ...wordU32(0xa00)],
      version: 2,
      instance: 202,
    ),
    ...shapePropertyRecord(
      values: {
        0x0080: 0x10000 | (indices?[index] ?? 0),
        0x0081: 0,
        0x0082: 0,
        0x0083: 0,
        0x0084: 0,
        if (nextShapes?[index] case final next?) 0x008a: next,
        0x0181: 0x00ffffff,
        0x01bf: 0x00100010,
        0x01c0: 0,
        0x01ff: 0x00080008,
        0x038f: 0,
        0x0390: 1,
        0x0391: 0,
        0x0392: 1,
      },
    ),
    ...officeArtRecord(0xf00d, wordU32(0x10000 | (indices?[index] ?? 0))),
  ], version: 15);
  return storyWordFixture(
    main: main,
    headers: headers,
    headerTextboxes: '${text}x',
    characterRuns: [
      WordFixtureFkpRun(8192, 28672, properties: wordSprm(0x0855, [1])),
    ],
    tablePairs: {
      11: storyPlc([...cps, 0xffffffff]),
      41: storyPlc(
        [...anchorCps, 0xffffffff],
        [
          for (var index = 0; index < anchorCps.length; index++) ...[
            ...wordU32(1025 + index),
            ...wordU32(1440),
            ...wordU32(1440),
            ...wordU32(4320),
            ...wordU32(2160),
            ...wordU16(0x6a),
            ...wordU32(0),
          ],
        ],
      ),
      50: [
        ...officeArtRecord(0xf000, [], version: 15),
        1,
        ...officeArtRecord(
          0xf002,
          officeArtRecord(0xf003, [
            for (var index = 0; index < anchorCps.length; index++)
              ...shape(index),
          ], version: 15),
          version: 15,
        ),
      ],
      58: storyPlc(
        [0, text.length, text.length + 1],
        [
          ...wordU32(declared),
          ...wordU32(0),
          ...wordU16(0),
          ...wordU32(0),
          ...wordU32(firstShape),
          ...wordU32(0),
          ...List.filled(22, 0),
        ],
      ),
      if (field)
        59: storyPlc(
          [0, text.indexOf('\x14'), text.indexOf('\x15'), 0xffffffff],
          [0x13, 33, 0x14, 0, 0x15, 0x80],
        ),
    },
  );
}
