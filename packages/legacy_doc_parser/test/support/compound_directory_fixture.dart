// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

const compoundMalformedNames = [
  'zero-length',
  'odd-length',
  'oversized-length',
  'length-excludes-terminator',
  'non-null-terminator',
  'embedded-null',
  'slash',
  'backslash',
  'colon',
  'exclamation',
  'storage-embedded-null',
  'root-odd-length',
];

/// Mutate the on-disk name separately from the writer's validated path API.
/// The small layout has root (0), Folder (1), Payload (2), and one unused slot.
Uint8List compoundDirectoryNameFixture(String mutation) {
  final bytes = (CfbfWriter()..addStream('Folder/Payload', [11, 12, 13]))
      .build();
  final data = ByteData.sublistView(bytes);
  final directory = (data.getUint32(48, Endian.little) + 1) * 512;
  final entry = directory + 256;
  void set16(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  switch (mutation) {
    case 'valid':
      break;
    case 'zero-length':
      set16(entry + 64, 0);
    case 'odd-length':
      set16(entry + 64, 15);
    case 'oversized-length':
      set16(entry + 64, 66);
    case 'length-excludes-terminator':
      set16(entry + 64, 14);
    case 'non-null-terminator':
      set16(entry + 14, 0x58);
    case 'embedded-null':
      set16(entry + 6, 0);
    case 'slash':
      set16(entry + 6, 0x2f);
    case 'backslash':
      set16(entry + 6, 0x5c);
    case 'colon':
      set16(entry + 6, 0x3a);
    case 'exclamation':
      set16(entry + 6, 0x21);
    case 'storage-embedded-null':
      set16(directory + 128 + 6, 0);
    case 'root-odd-length':
      set16(directory + 64, 21);
    case 'unused-padding':
      // Ignore the bytes beyond the declared terminator, even if an earlier
      // writer left nonzero data there. They are not part of the name.
      bytes.fillRange(entry + 16, entry + 64, 0x7f);
    case 'stale-unused-slot':
      // An unallocated record is not a name-bearing object. Do not narrow
      // legacy compatibility by validating stale name bytes in deleted slots.
      bytes.fillRange(directory + 384, directory + 450, 0xff);
    default:
      throw ArgumentError.value(mutation, 'mutation');
  }
  return bytes;
}
