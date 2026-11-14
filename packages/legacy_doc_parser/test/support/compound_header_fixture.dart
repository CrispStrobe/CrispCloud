// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import 'compound_size_fixture.dart';

final compoundInvalidGeometry = <(String, bool, int, int, int)>[
  for (final major in [0, 1, 2, 5, 0xffff])
    ('major-$major', false, 26, 2, major),
  for (final shift in [0, 6, 8, 10, 11, 12, 13, 31, 32, 63, 64, 0xffff])
    ('v3-sector-$shift', false, 30, 2, shift),
  ('v4-sector-9', true, 30, 2, 9),
  for (final shift in [0, 1, 5, 7, 9, 31, 32, 63, 64, 0xffff]) ...[
    ('v3-mini-$shift', false, 32, 2, shift),
    ('v4-mini-$shift', true, 32, 2, shift),
  ],
  for (final cutoff in [0, 1, 64, 4095, 4097, 0xffffffff]) ...[
    ('v3-cutoff-$cutoff', false, 56, 4, cutoff),
    ('v4-cutoff-$cutoff', true, 56, 4, cutoff),
  ],
];

Uint8List compoundGeometryFixture((String, bool, int, int, int) variant) {
  final (_, version4, offset, size, value) = variant;
  final bytes = version4
      ? compoundSizeFixture(version4: true)
      : (CfbfWriter()
              ..addStream('First', [11])
              ..addStream('Second', [99])
              ..addStream('Large', List<int>.filled(4096, 37)))
            .build();
  final data = ByteData.sublistView(bytes);
  if (size == 2) {
    data.setUint16(offset, value, Endian.little);
  } else {
    data.setUint32(offset, value, Endian.little);
  }
  return bytes;
}

/// A referenced FAT padding slot has a valid terminator, but its corresponding
/// physical sector does not exist. Table bounds alone cannot authorize a read.
Uint8List compoundPhantomMetadataFixture({
  required bool version4,
  required bool miniFat,
}) {
  final bytes = compoundSizeFixture(version4: version4);
  final data = ByteData.sublistView(bytes);
  final sectorSize = version4 ? 4096 : 512;
  final nonexistent = bytes.length ~/ sectorSize - 1;
  final fat = (data.getUint32(76, Endian.little) + 1) * sectorSize;
  data.setUint32(fat + nonexistent * 4, cfbfEndOfChain, Endian.little);
  data.setUint32(miniFat ? 60 : 48, nonexistent, Endian.little);
  if (miniFat) data.setUint32(64, 1, Endian.little);
  return bytes;
}
