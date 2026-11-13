// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

const compoundOverlappingStreams = [
  ('regular-shared-start', 'Alpha', 'Bravo'),
  ('regular-shared-tail', 'Alpha', 'Bravo'),
  ('regular-spare-shared-tail', 'Alpha', 'Bravo'),
  ('mini-shared-start', 'SmallA', 'SmallB'),
  ('mini-shared-tail', 'SmallA', 'SmallB'),
  ('mini-spare-shared-tail', 'SmallA', 'SmallB'),
  ('regular-root', 'Alpha', 'SmallA'),
];

const compoundMetadataOverlaps = [
  ('regular-directory', 'Alpha'),
  ('regular-directory-spare', 'Alpha'),
  ('regular-minifat', 'Alpha'),
  ('regular-fat', 'Alpha'),
  ('regular-difat', 'Alpha'),
  ('root-directory', 'SmallA'),
  ('root-minifat', 'SmallA'),
];

/// Each mutation changes an independent allocation link or directory start.
/// Stream names, sizes, metadata counts, and terminating links remain parseable
/// so ownership validation cannot be replaced by a generic topology guard.
Uint8List compoundOwnershipFixture(String mutation) {
  var bytes =
      (CfbfWriter()
            ..addStream('Alpha', List.generate(4097, (index) => index % 251))
            ..addStream(
              'Bravo',
              List.generate(4097, (index) => 255 - index % 251),
            )
            ..addStream('SmallA', List.generate(65, (index) => index + 10))
            ..addStream('SmallB', List.generate(65, (index) => index + 100)))
          .build();
  final original = CfbfFile.fromBytes(bytes);
  if (mutation == 'regular-difat') {
    // Move the one FAT reference into a separately allocated DIFAT sector.
    final extended = Uint8List(bytes.length + 512)..setAll(0, bytes);
    extended.fillRange(bytes.length, extended.length, 0xff);
    bytes = extended;
  }
  final data = ByteData.sublistView(bytes);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  void set32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  final fatSector = u32(76);
  final fatStart = (fatSector + 1) * 512;
  final directorySector = u32(48);
  final directory = (directorySector + 1) * 512;
  final miniFatSector = u32(60);
  final miniFatStart = (miniFatSector + 1) * 512;
  final alpha = original.entryByName('Alpha')!;
  final bravo = original.entryByName('Bravo')!;
  final smallA = original.entryByName('SmallA')!;
  final smallB = original.entryByName('SmallB')!;
  void start(CfbfDirectoryEntry entry, int value) =>
      set32(directory + entry.index * 128 + 116, value);
  void size(CfbfDirectoryEntry entry, int value) =>
      set32(directory + entry.index * 128 + 120, value);
  void next(int sector, int value) => set32(fatStart + sector * 4, value);
  void miniNext(int sector, int value) =>
      set32(miniFatStart + sector * 4, value);
  switch (mutation) {
    case 'valid':
      break;
    case 'regular-shared-start':
      start(bravo, alpha.startSector);
    case 'regular-shared-tail':
      next(bravo.startSector, alpha.startSector + 1);
    case 'regular-spare-shared-tail':
      size(alpha, 4096);
      size(bravo, 4096);
      next(bravo.startSector + 7, alpha.startSector + 8);
    case 'mini-shared-start':
      start(smallB, smallA.startSector);
    case 'mini-shared-tail':
      miniNext(smallB.startSector, smallA.startSector + 1);
    case 'mini-spare-shared-tail':
      size(smallA, 1);
      size(smallB, 1);
      miniNext(smallB.startSector, smallA.startSector + 1);
    case 'regular-root':
      start(original.root, alpha.startSector);
    case 'regular-directory':
      next(alpha.startSector + 7, directorySector);
    case 'regular-directory-spare':
      next(alpha.startSector + 8, directorySector);
    case 'regular-minifat':
      next(alpha.startSector + 7, miniFatSector);
    case 'regular-fat':
      next(alpha.startSector + 7, fatSector);
      next(fatSector, cfbfEndOfChain);
    case 'regular-difat':
      final difatSector = bytes.length ~/ 512 - 2;
      set32(76, cfbfFreeSect);
      set32(68, difatSector);
      set32(72, 1);
      set32((difatSector + 1) * 512, fatSector);
      set32(bytes.length - 4, cfbfEndOfChain);
      next(difatSector, cfbfEndOfChain);
      next(alpha.startSector + 7, difatSector);
    case 'root-directory':
      start(original.root, directorySector);
    case 'root-minifat':
      start(original.root, miniFatSector);
    case 'directory-minifat':
      set32(60, directorySector);
      set32(64, 2);
    case 'unrelated-regular-cycle':
      next(bravo.startSector + 8, bravo.startSector);
    case 'unrelated-mini-cycle':
      miniNext(smallB.startSector + 1, smallB.startSector);
    default:
      throw ArgumentError.value(mutation, 'mutation');
  }
  return bytes;
}

/// Public caller-built metadata can contain a negative size even though the
/// on-disk size field is unsigned. Keep all other fields of the real entry.
CfbfDirectoryEntry compoundNegativeSizeEntry(CfbfDirectoryEntry entry) =>
    CfbfDirectoryEntry(
      index: entry.index,
      name: entry.name,
      type: entry.type,
      colorBlack: entry.colorBlack,
      leftSibling: entry.leftSibling,
      rightSibling: entry.rightSibling,
      child: entry.child,
      clsid: entry.clsid,
      stateBits: entry.stateBits,
      created: entry.created,
      modified: entry.modified,
      createdFiletime: entry.createdFiletime,
      modifiedFiletime: entry.modifiedFiletime,
      startSector: entry.startSector,
      streamSize: -1000,
    );
