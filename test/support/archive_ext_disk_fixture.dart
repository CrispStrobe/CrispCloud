// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Synthetic Linux partition wrappers around independently supplied volume bytes.

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_disk_image_fixture.dart';

DiskImageFixture extGptFixture({
  required List<koni.ByteSource> volumes,
  int sectorBytes = 512,
  int firstPartitionLba = 128,
  int? totalBytes,
}) {
  final fixture = DiskImageFixture.gpt(
    volumes: volumes,
    sectorBytes: sectorBytes,
    firstPartitionLba: firstPartitionLba,
    totalBytes: totalBytes,
  );
  final layout = fixture.gpt!;
  for (var index = 0; index < volumes.length; index++) {
    // Linux filesystem-data GUID 0FC63DAF-8483-4772-8E79-3D69D8477DE4.
    layout.primaryTable.setRange(
      index * layout.entrySize,
      index * layout.entrySize + 16,
      const [
        0xaf,
        0x3d,
        0xc6,
        0x0f,
        0x83,
        0x84,
        0x72,
        0x47,
        0x8e,
        0x79,
        0x3d,
        0x69,
        0xd8,
        0x47,
        0x7d,
        0xe4,
      ],
    );
  }
  layout.backupTable.setAll(0, layout.primaryTable);
  layout.updateTableCrc();
  layout.updateTableCrc(backup: true);
  return fixture;
}
