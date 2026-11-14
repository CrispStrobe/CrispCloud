// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Synthetic Microsoft Basic Data wrappers around independently supplied bytes.

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_disk_image_fixture.dart';

DiskImageFixture ntfsGptFixture({
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
    // Microsoft Basic Data EBD0A0A2-B9E5-4433-87C0-68B6B72699C7.
    layout.primaryTable.setRange(
      index * layout.entrySize,
      index * layout.entrySize + 16,
      const [
        0xa2,
        0xa0,
        0xd0,
        0xeb,
        0xe5,
        0xb9,
        0x33,
        0x44,
        0x87,
        0xc0,
        0x68,
        0xb6,
        0xb7,
        0x26,
        0x99,
        0xc7,
      ],
    );
  }
  layout.backupTable.setAll(0, layout.primaryTable);
  layout.updateTableCrc();
  layout.updateTableCrc(backup: true);
  return fixture;
}
