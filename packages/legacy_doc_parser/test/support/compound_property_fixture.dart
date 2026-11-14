// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

class CompoundPropertyFixture {
  CompoundPropertyFixture(this.bytes, this.streams);
  final Uint8List bytes;
  final Map<String, List<int>> streams;
}

/// An integer generator whose multiplication stays below 2^53, including in
/// real JavaScript builds. Seed and operation index fully identify each case.
class CompoundPropertyRandom {
  CompoundPropertyRandom(this.state);
  int state;
  int next(int limit) {
    state = (state * 1664525 + 1013904223) % 0x100000000;
    return state % limit;
  }
}

const compoundPropertySizes = [
  0,
  1,
  2,
  63,
  64,
  65,
  127,
  128,
  129,
  511,
  512,
  513,
  1023,
  1024,
  1025,
  4094,
  4095,
  4096,
  4097,
  4607,
  4608,
  4609,
  8191,
  8192,
  8193,
];

CompoundPropertyFixture compoundGeneratedV3(int seed) {
  final random = CompoundPropertyRandom(seed);
  final writer = CfbfWriter()..addStorage('Empty-$seed');
  final streams = <String, List<int>>{};
  for (var index = 0; index < 8; index++) {
    final depth = random.next(5);
    final prefix = [
      for (var level = 0; level < depth; level++) 'D${random.next(4)}',
    ];
    final name =
        '${const ['Ascii', 'ß', 'SS', '\u1f80', '\u1f88', '\u{10400}', '\u{10428}', '\u0005Meta'][index]}-$seed-$index';
    final path = [...prefix, name].join('/');
    final length =
        compoundPropertySizes[(seed + index * 7) %
            compoundPropertySizes.length];
    final payload = List.generate(
      length,
      (i) => (seed * 11 + index * 37 + i * 13) % 251,
    );
    streams[path] = payload;
    writer.addStream(path, payload);
  }
  return CompoundPropertyFixture(writer.build(), streams);
}

/// Independently assembled version-4 CFB. Both FAT and mini-FAT payload chains
/// can be fragmented; payload padding contains a distinct value to expose
/// accidental extra reads. This does not invoke the version-3 writer.
CompoundPropertyFixture compoundGeneratedV4(int seed) {
  const sectorSize = 4096, miniSize = 64;
  final random = CompoundPropertyRandom(seed);
  final smallLength = const [
    1,
    2,
    63,
    64,
    65,
    511,
    512,
    513,
    1023,
    1024,
    2047,
    4095,
  ][seed % 12];
  final largeLength = const [
    4096,
    4097,
    4607,
    8191,
    8192,
    8193,
    12287,
  ][seed % 7];
  final largeCount = (largeLength + sectorSize - 1) ~/ sectorSize;
  final miniCount = (smallLength + miniSize - 1) ~/ miniSize;
  final rootSector = largeCount;
  final miniFatSector = largeCount + 1;
  final directorySector = largeCount + 2;
  final fatSector = largeCount + 3;
  final bytes = Uint8List((fatSector + 2) * sectorSize);
  final data = ByteData.sublistView(bytes);
  void u16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void u32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  bytes.setAll(0, cfbfSignature);
  u16(24, 0x3e);
  u16(26, 4);
  u16(28, 0xfffe);
  u16(30, 12);
  u16(32, 6);
  u32(40, 1);
  u32(44, 1);
  u32(48, directorySector);
  u32(56, 4096);
  u32(60, miniFatSector);
  u32(64, 1);
  u32(68, cfbfEndOfChain);
  for (var i = 0; i < 109; i++) {
    u32(76 + i * 4, i == 0 ? fatSector : cfbfFreeSect);
  }
  final fatOffset = (fatSector + 1) * sectorSize;
  final miniFatOffset = (miniFatSector + 1) * sectorSize;
  bytes.fillRange(fatOffset, fatOffset + sectorSize, 0xff);
  bytes.fillRange(miniFatOffset, miniFatOffset + sectorSize, 0xff);
  void fat(int sector, int next) => u32(fatOffset + sector * 4, next);
  void mini(int sector, int next) => u32(miniFatOffset + sector * 4, next);
  List<int> permutation(int count) {
    final result = List.generate(count, (i) => i);
    for (var i = count - 1; i > 0; i--) {
      final other = random.next(i + 1);
      final value = result[i];
      result[i] = result[other];
      result[other] = value;
    }
    return result;
  }

  final regularOrder = permutation(largeCount);
  final miniOrder = permutation(miniCount);
  final large = List.generate(largeLength, (i) => (seed * 17 + i * 29) % 251);
  final small = List.generate(smallLength, (i) => (seed * 19 + i * 31) % 251);
  for (var index = 0; index < regularOrder.length; index++) {
    final sector = regularOrder[index];
    final start = (sector + 1) * sectorSize;
    bytes.fillRange(start, start + sectorSize, 0xcc);
    final end = (index + 1) * sectorSize < large.length
        ? (index + 1) * sectorSize
        : large.length;
    bytes.setRange(
      start,
      start + end - index * sectorSize,
      large,
      index * sectorSize,
    );
    fat(
      sector,
      index + 1 == regularOrder.length
          ? cfbfEndOfChain
          : regularOrder[index + 1],
    );
  }
  final rootOffset = (rootSector + 1) * sectorSize;
  bytes.fillRange(rootOffset, rootOffset + sectorSize, 0xdd);
  for (var index = 0; index < miniOrder.length; index++) {
    final sector = miniOrder[index];
    final start = rootOffset + sector * miniSize;
    final end = (index + 1) * miniSize < small.length
        ? (index + 1) * miniSize
        : small.length;
    bytes.setRange(
      start,
      start + end - index * miniSize,
      small,
      index * miniSize,
    );
    mini(
      sector,
      index + 1 == miniOrder.length ? cfbfEndOfChain : miniOrder[index + 1],
    );
  }
  fat(rootSector, cfbfEndOfChain);
  fat(miniFatSector, cfbfEndOfChain);
  fat(directorySector, cfbfEndOfChain);
  fat(fatSector, cfbfFatSect);
  final directory = (directorySector + 1) * sectorSize;
  void entry(
    int index,
    String name,
    int type,
    int start,
    int size, {
    int left = cfbfNoStream,
    int right = cfbfNoStream,
    int child = cfbfNoStream,
  }) {
    final at = directory + index * 128;
    for (var i = 0; i < name.length; i++) {
      u16(at + i * 2, name.codeUnitAt(i));
    }
    u16(at + 64, (name.length + 1) * 2);
    bytes[at + 66] = type;
    bytes[at + 67] = 1;
    u32(at + 68, left);
    u32(at + 72, right);
    u32(at + 76, child);
    u32(at + 116, start);
    u32(at + 120, size);
  }

  entry(0, 'Root Entry', 5, rootSector, miniCount * miniSize, child: 1);
  entry(1, 'Large', 2, regularOrder.first, largeLength, right: 2);
  entry(2, 'Small', 2, miniOrder.first, smallLength);
  bytes[directory + 2 * 128 + 67] = 0; // Red leaf preserves black height.
  for (var index = 3; index < 32; index++) {
    for (final field in [68, 72, 76]) {
      u32(directory + index * 128 + field, cfbfNoStream);
    }
  }
  return CompoundPropertyFixture(bytes, {'Large': large, 'Small': small});
}

class CompoundPropertyMutation {
  CompoundPropertyMutation(this.name, this.bytes, this.paths);
  final String name;
  final Uint8List bytes;
  final Iterable<String> paths;
}

Iterable<CompoundPropertyMutation> compoundSeededMutations({
  required int seed,
  required bool version4,
  int cases = 2048,
}) sync* {
  final fixture = version4
      ? compoundGeneratedV4(seed)
      : compoundGeneratedV3(seed);
  final original = fixture.bytes;
  final source = ByteData.sublistView(original);
  final sectorSize = version4 ? 4096 : 512;
  final fat = (source.getUint32(76, Endian.little) + 1) * sectorSize;
  final miniFat = (source.getUint32(60, Endian.little) + 1) * sectorSize;
  final physical = original.length ~/ sectorSize - 1;
  final entryOffsets = <int>[];
  var directorySector = source.getUint32(48, Endian.little);
  while (directorySector != cfbfEndOfChain) {
    final start = (directorySector + 1) * sectorSize;
    for (var within = 0; within < sectorSize; within += 128) {
      entryOffsets.add(start + within);
    }
    // Generated fixtures fit one FAT sector; this walk is independent of the
    // reader under test and includes every directory sector, not just root.
    directorySector = source.getUint32(
      fat + directorySector * 4,
      Endian.little,
    );
  }
  final random = CompoundPropertyRandom(seed);
  const boundaryValues = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    9,
    12,
    31,
    32,
    63,
    64,
    127,
    128,
    255,
    256,
    511,
    512,
    4095,
    4096,
    0xffff,
    0x1fffff,
    0x7fffffff,
    0xfffffffa,
    0xfffffffb,
    0xfffffffc,
    0xfffffffd,
    0xfffffffe,
    0xffffffff,
  ];
  for (var caseIndex = 0; caseIndex < cases; caseIndex++) {
    var bytes = Uint8List.fromList(original);
    final data = ByteData.sublistView(bytes);
    final mode = caseIndex % 8;
    var value = boundaryValues[random.next(boundaryValues.length)];
    var offset = 0, width = 4;
    switch (mode) {
      case 0:
        offset = const [26, 28, 30, 32][random.next(4)];
        width = 2;
      case 1:
        offset = const [
          40,
          44,
          48,
          56,
          60,
          64,
          68,
          72,
          76,
          80,
          508,
        ][random.next(11)];
      case 2:
        final entry = entryOffsets[random.next(entryOffsets.length)];
        offset =
            entry +
            const [68, 72, 76, 96, 100, 104, 108, 112, 116, 120, 124][random
                .next(11)];
      case 3:
        final entry = entryOffsets[random.next(entryOffsets.length)];
        final field = const [64, 66, 67][random.next(3)];
        offset = entry + field;
        width = field == 64 ? 2 : 1;
      case 4:
        offset = fat + random.next(physical + 4) * 4;
      case 5:
        offset = miniFat + random.next(128) * 4;
      case 6:
        final length = random.next(original.length + 1);
        bytes = Uint8List.fromList(original.sublist(0, length));
        yield CompoundPropertyMutation(
          'v${version4 ? 4 : 3}/$seed/$caseIndex/truncate/$length',
          bytes,
          fixture.streams.keys,
        );
        continue;
      case 7:
        offset =
            entryOffsets[random.next(entryOffsets.length)] +
            random.next(32) * 2;
        width = 2;
        value = const [
          0,
          0x21,
          0x2f,
          0x3a,
          0x5c,
          0xd800,
          0xdc00,
          0xffff,
        ][random.next(8)];
    }
    if (width == 1) {
      bytes[offset] = value & 255;
    } else if (width == 2) {
      data.setUint16(offset, value & 0xffff, Endian.little);
    } else {
      data.setUint32(offset, value, Endian.little);
    }
    yield CompoundPropertyMutation(
      'v${version4 ? 4 : 3}/$seed/$caseIndex/$offset:$width:$value',
      bytes,
      fixture.streams.keys,
    );
  }
}
