// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'compound_size_fixture.dart';

const compoundInvalidRoots = [
  'missing-root',
  'storage-root',
  'stream-root',
  'second-root',
  'displaced-root',
  'left-root-sibling',
  'right-root-sibling',
  'empty-directory',
];

Uint8List compoundRootFixture(String mutation, {required bool version4}) {
  final bytes = compoundSizeFixture(version4: version4);
  final data = ByteData.sublistView(bytes);
  final sectorSize = version4 ? 4096 : 512;
  final directory = (data.getUint32(48, Endian.little) + 1) * sectorSize;
  switch (mutation) {
    case 'missing-root':
      bytes[directory + 66] = 0;
    case 'storage-root':
      bytes[directory + 66] = 1;
    case 'stream-root':
      bytes[directory + 66] = 2;
    case 'second-root':
      bytes[directory + 128 + 66] = 5;
    case 'displaced-root':
      bytes[directory + 66] = 1;
      bytes[directory + 128 + 66] = 5;
    case 'left-root-sibling':
      data.setUint32(directory + 68, 1, Endian.little);
    case 'right-root-sibling':
      data.setUint32(directory + 72, 1, Endian.little);
    case 'empty-directory':
      data.setUint32(48, 0xfffffffe, Endian.little);
      if (version4) data.setUint32(40, 0, Endian.little);
    default:
      throw ArgumentError.value(mutation, 'mutation');
  }
  return bytes;
}
