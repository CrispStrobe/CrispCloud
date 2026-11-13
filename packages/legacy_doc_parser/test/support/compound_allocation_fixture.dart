// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/src/compound/cfbf_reader.dart';
import 'package:legacy_doc_parser/src/compound/cfbf_writer.dart';

import 'compound_size_fixture.dart';

/// Small independently mutated allocation tables. Both streams deliberately
/// end part-way through a sector so termination checks cannot assume alignment.
Uint8List compoundAllocationFixture(String mutation) {
  if (mutation == 'directory-count') {
    final bytes = compoundSizeFixture(version4: true);
    ByteData.sublistView(bytes).setUint32(40, 2, Endian.little);
    return bytes;
  }
  final bytes =
      (CfbfWriter()
            ..addStream('Small', List.generate(65, (index) => index))
            ..addStream('Large', List.generate(4097, (index) => index % 251)))
          .build();
  final data = ByteData.sublistView(bytes);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  void set32(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  final fatStart = (u32(76) + 1) * 512;
  final directory = (u32(48) + 1) * 512;
  final miniFatStart = (u32(60) + 1) * 512;
  switch (mutation.replaceFirst('-spare', '-tail')) {
    case 'valid':
      break;
    case 'duplicate-fat':
      set32(44, 2);
      set32(80, u32(76));
    case 'fat-count-zero':
      set32(44, 0);
    case 'fat-count-extra':
      set32(44, 2);
    case 'difat-count-extra':
      set32(72, 1);
    case 'minifat-count-extra':
      set32(64, 2);
    case 'minifat-free-terminal':
      set32(fatStart + u32(60) * 4, cfbfFreeSect);
    case 'directory-free-terminal':
      set32(fatStart + u32(48) * 4, cfbfFreeSect);
    case 'mini-cycle-tail':
      set32(miniFatStart + 4, 1);
    case 'mini-free-tail':
      set32(miniFatStart + 4, cfbfFreeSect);
    case 'regular-cycle-tail':
      // The writer allocates the only regular stream first, in sectors 0..8.
      set32(fatStart + 8 * 4, 8);
    case 'regular-free-tail':
      set32(fatStart + 8 * 4, cfbfFreeSect);
    case 'root-cycle-tail':
      final rootStart = u32(directory + 116);
      set32(fatStart + rootStart * 4, rootStart);
    case 'spare-capacity':
      break;
    default:
      throw ArgumentError.value(mutation, 'mutation');
  }
  if (mutation.endsWith('-spare') || mutation == 'spare-capacity') {
    // Sorted sibling entries are Large (1), Small (2). Keep their allocated
    // chains but reduce logical sizes so the final sector is entirely spare.
    set32(directory + 128 + 120, 4096);
    set32(directory + 256 + 120, 1);
  }
  return bytes;
}

/// Preserve prior reader compatibility with a root stream ending at its last
/// logical mini-container byte rather than requiring 64-byte padding.
Uint8List compoundPartialMiniFixture(int size) {
  final bytes =
      (CfbfWriter()
            ..addStream('Small', List.generate(size, (index) => index & 255)))
          .build();
  final data = ByteData.sublistView(bytes);
  final directory = (data.getUint32(48, Endian.little) + 1) * 512;
  data.setUint32(directory + 120, size, Endian.little);
  return bytes;
}

/// Deliberately shared allocation tails exercise resource bounds independently
/// of logical stream bytes. Ownership validation must reject every alias
/// without reading the shared payload or repeatedly walking its long tail.
Uint8List compoundSharedChainFixture() {
  final writer = CfbfWriter()
    ..addStream('Shared', List.generate(1024 * 1024, (index) => index % 251));
  for (var index = 0; index < 64; index++) {
    writer.addStream('Alias$index', Uint8List(4096));
  }
  final bytes = writer.build();
  final file = CfbfFile.fromBytes(bytes);
  final start = file.entryByName('Shared')!.startSector;
  final data = ByteData.sublistView(bytes);
  final directory = (data.getUint32(48, Endian.little) + 1) * 512;
  for (final entry in file.entries.where((entry) => entry.isStream)) {
    // This writer emits the directory sectors contiguously.
    final offset = directory + entry.index * 128;
    data.setUint32(offset + 116, start, Endian.little);
    data.setUint32(offset + 120, 4096, Endian.little);
  }
  return bytes;
}

/// One legitimately overallocated stream retains the suffix-cache performance
/// control without depending on malformed sharing between directory entries.
Uint8List compoundOverallocatedFixture() {
  final bytes =
      (CfbfWriter()..addStream(
            'Large',
            List.generate(1024 * 1024, (index) => index % 251),
          ))
          .build();
  final data = ByteData.sublistView(bytes);
  final directory = (data.getUint32(48, Endian.little) + 1) * 512;
  data.setUint32(directory + 128 + 120, 4096, Endian.little);
  return bytes;
}
