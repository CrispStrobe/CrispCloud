// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original synthetic test data; no disk images or third-party parser code.

import 'dart:typed_data';

/// Sparse, independently checksummed synthetic GPT image for native/web tests.
class DiskPartitionFixture {
  DiskPartitionFixture.gpt({
    this.sectorBytes = 512,
    this.totalBytes = 1024 * 1024,
    this.entryCount = 128,
    this.entrySize = 128,
  }) {
    final sectors = totalBytes ~/ sectorBytes;
    final tableBytes = entryCount * entrySize;
    final tableSectors = (tableBytes + sectorBytes - 1) ~/ sectorBytes;
    final reserve = (16384 + sectorBytes - 1) ~/ sectorBytes;
    final reservedSectors = tableSectors > reserve ? tableSectors : reserve;
    primaryTableOffset = 2 * sectorBytes;
    backupTableOffset = (sectors - 1 - tableSectors) * sectorBytes;
    firstUsable = 2 + reservedSectors;
    lastUsable = sectors - 2 - reservedSectors;
    mbr = Uint8List(512)
      ..[510] = 0x55
      ..[511] = 0xaa;
    mbr[450] = 0xee;
    mbr.setAll(447, [0, 2, 0]);
    mbr.setAll(451, [255, 255, 255]);
    partitionFixtureSet32(mbr, 454, 1);
    partitionFixtureSet32(
      mbr,
      458,
      sectors - 1 < 0xffffffff ? sectors - 1 : 0xffffffff,
    );
    primaryTable = Uint8List(tableBytes);
    if (entrySize >= 128 && entryCount > 0) {
      setPartition(0, firstUsable + 8, firstUsable + 31);
    }
    backupTable = Uint8List.fromList(primaryTable);
    primaryHeader = _header(1, sectors - 1, 2);
    backupHeader = _header(sectors - 1, 1, backupTableOffset ~/ sectorBytes);
    updateTableCrc();
    updateTableCrc(backup: true);
  }

  final int sectorBytes;
  final int totalBytes;
  final int entryCount;
  final int entrySize;
  late final int firstUsable;
  late final int lastUsable;
  late final int primaryTableOffset;
  late final int backupTableOffset;
  late final Uint8List mbr;
  late final Uint8List primaryHeader;
  late final Uint8List backupHeader;
  late final Uint8List primaryTable;
  late final Uint8List backupTable;
  final reads = <(int, int)>[];

  Uint8List _header(int self, int alternate, int arrayLba) {
    final bytes = Uint8List(sectorBytes)..setAll(0, 'EFI PART'.codeUnits);
    partitionFixtureSet32(bytes, 8, 0x00010000);
    partitionFixtureSet32(bytes, 12, 92);
    partitionFixtureSet64(bytes, 24, BigInt.from(self));
    partitionFixtureSet64(bytes, 32, BigInt.from(alternate));
    partitionFixtureSet64(bytes, 40, BigInt.from(firstUsable));
    partitionFixtureSet64(bytes, 48, BigInt.from(lastUsable));
    bytes.setAll(56, List.generate(16, (i) => i + 1));
    partitionFixtureSet64(bytes, 72, BigInt.from(arrayLba));
    partitionFixtureSet32(bytes, 80, entryCount);
    partitionFixtureSet32(bytes, 84, entrySize);
    return bytes;
  }

  void setPartition(
    int index,
    int first,
    int last, {
    bool backup = false,
    String name = 'CrispCloud test',
    int? uniqueId,
  }) {
    final table = backup ? backupTable : primaryTable;
    final at = index * entrySize;
    table.fillRange(at, at + entrySize, 0);
    // EFI system partition GUID, stored using EFI_GUID's mixed byte order.
    table.setAll(at, [
      0x28,
      0x73,
      0x2a,
      0xc1,
      0x1f,
      0xf8,
      0xd2,
      0x11,
      0xba,
      0x4b,
      0x00,
      0xa0,
      0xc9,
      0x3e,
      0xc9,
      0x3b,
    ]);
    partitionFixtureSet32(table, at + 16, uniqueId ?? index + 1);
    table[at + 31] = 0xa5;
    partitionFixtureSet64(table, at + 32, BigInt.from(first));
    partitionFixtureSet64(table, at + 40, BigInt.from(last));
    final units = name.codeUnits;
    for (var i = 0; i < units.length && i < 36; i++) {
      table[at + 56 + i * 2] = units[i] & 255;
      table[at + 57 + i * 2] = units[i] >> 8;
    }
  }

  void updateHeaderCrc({bool backup = false}) {
    final header = backup ? backupHeader : primaryHeader;
    partitionFixtureSet32(header, 16, 0);
    final size = ByteData.sublistView(header).getUint32(12, Endian.little);
    if (size >= 20 && size <= header.length) {
      partitionFixtureSet32(
        header,
        16,
        partitionFixtureCrc32(header.sublist(0, size)),
      );
    }
  }

  void updateTableCrc({bool backup = false}) {
    partitionFixtureSet32(
      backup ? backupHeader : primaryHeader,
      88,
      partitionFixtureCrc32(backup ? backupTable : primaryTable),
    );
    updateHeaderCrc(backup: backup);
  }

  Uint8List read(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > totalBytes) {
      throw RangeError('Out-of-bounds fixture read');
    }
    reads.add((offset, length));
    final output = Uint8List(length);
    for (final segment in <(int, Uint8List)>[
      (0, mbr),
      (sectorBytes, primaryHeader),
      (primaryTableOffset, primaryTable),
      (backupTableOffset, backupTable),
      (totalBytes - sectorBytes, backupHeader),
    ]) {
      final first = offset > segment.$1 ? offset : segment.$1;
      final endA = offset + length;
      final endB = segment.$1 + segment.$2.length;
      final end = endA < endB ? endA : endB;
      if (end > first) {
        output.setRange(
          first - offset,
          end - offset,
          segment.$2,
          first - segment.$1,
        );
      }
    }
    return output;
  }

  Uint8List materialize() {
    if (totalBytes > 8 * 1024 * 1024) {
      throw StateError('Large fixtures must remain sparse.');
    }
    return read(0, totalBytes);
  }
}

void partitionFixtureSet32(Uint8List bytes, int at, int value) =>
    ByteData.sublistView(bytes).setUint32(at, value, Endian.little);
void partitionFixtureSet64(Uint8List bytes, int at, BigInt value) {
  partitionFixtureSet32(bytes, at, (value & BigInt.from(0xffffffff)).toInt());
  partitionFixtureSet32(bytes, at + 4, (value >> 32).toInt());
}

/// Deliberately bit-at-a-time oracle, independent of the production lookup
/// table implementation; also checked against Python zlib in the acceptance
/// driver and the standard CRC32 check value for "123456789".
int partitionFixtureCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 == 0 ? crc >>> 1 : (crc >>> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff).toUnsigned(32);
}
