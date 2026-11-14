// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

const compoundInvalidTrees = [
  'self-child',
  'ancestor-child',
  'shared-subtree',
  'sibling-cycle',
  'repeated-sibling',
  'outside-child',
  'outside-sibling',
  'stream-child',
  'empty-linked-slot',
  'unknown-linked-type',
  'duplicate-name',
  'duplicate-case-name',
  'root-in-sibling-tree',
];

Uint8List compoundTreeFixture(String mutation) {
  final bytes =
      (CfbfWriter()
            ..addStream('First/Alpha', [11])
            ..addStream('First/Bravo', [22])
            ..addStream('Second/Charlie', [33])
            ..addStream('Top', [44]))
          .build();
  final original = CfbfFile.fromBytes(bytes);
  final data = ByteData.sublistView(bytes);
  final directory = (data.getUint32(48, Endian.little) + 1) * 512;
  final first = original.entryByName('First')!;
  final second = original.entryByName('Second')!;
  final alpha = original.entryByName('Alpha')!;
  final bravo = original.entryByName('Bravo')!;
  final charlie = original.entryByName('Charlie')!;
  void set(CfbfDirectoryEntry entry, int field, int value) => data.setUint32(
    directory + entry.index * 128 + field,
    value,
    Endian.little,
  );
  switch (mutation) {
    case 'valid':
      break;
    case 'self-child':
      set(first, 76, first.index);
    case 'ancestor-child':
      set(first, 76, 0);
    case 'shared-subtree':
      set(second, 76, first.child);
    case 'sibling-cycle':
      set(alpha, 68, alpha.index);
    case 'repeated-sibling':
      set(first, 76, bravo.index);
      set(bravo, 68, alpha.index);
      set(bravo, 72, alpha.index);
    case 'outside-child':
      set(first, 76, original.entries.length);
    case 'outside-sibling':
      set(alpha, 68, original.entries.length);
    case 'stream-child':
      set(alpha, 76, charlie.index);
    case 'empty-linked-slot':
      bytes[directory + alpha.index * 128 + 66] = 0;
    case 'unknown-linked-type':
      bytes[directory + alpha.index * 128 + 66] = 3;
    case 'duplicate-name':
    case 'duplicate-case-name':
      final name = mutation == 'duplicate-name' ? 'Alpha' : 'ALPHA';
      for (var index = 0; index < name.length; index++) {
        data.setUint16(
          directory + bravo.index * 128 + index * 2,
          name.codeUnitAt(index),
          Endian.little,
        );
      }
    case 'root-in-sibling-tree':
      set(alpha, 72, 0);
    default:
      throw ArgumentError.value(mutation, 'mutation');
  }
  return bytes;
}

CfbfDirectoryEntry compoundEntryCopy(
  CfbfDirectoryEntry entry, {
  int? index,
  CfbfObjectType? type,
  int? child,
  int? startSector,
  int? streamSize,
}) => CfbfDirectoryEntry(
  index: index ?? entry.index,
  name: entry.name,
  type: type ?? entry.type,
  colorBlack: entry.colorBlack,
  leftSibling: entry.leftSibling,
  rightSibling: entry.rightSibling,
  child: child ?? entry.child,
  clsid: entry.clsid,
  stateBits: entry.stateBits,
  created: entry.created,
  modified: entry.modified,
  createdFiletime: entry.createdFiletime,
  modifiedFiletime: entry.modifiedFiletime,
  startSector: startSector ?? entry.startSector,
  streamSize: streamSize ?? entry.streamSize,
);

List<(String, CfbfDirectoryEntry)> compoundInvalidParents(
  CfbfDirectoryEntry parent,
  int count,
) => [
  ('negative-index', compoundEntryCopy(parent, index: -1)),
  ('outside-index', compoundEntryCopy(parent, index: count)),
  ('stream-parent', compoundEntryCopy(parent, type: CfbfObjectType.stream)),
  ('empty-parent', compoundEntryCopy(parent, type: CfbfObjectType.empty)),
  ('negative-child', compoundEntryCopy(parent, child: -1)),
  ('outside-child', compoundEntryCopy(parent, child: count)),
  ('substituted-child', compoundEntryCopy(parent, child: parent.index)),
];
