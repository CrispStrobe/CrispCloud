// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Original sparse test wrappers around separately supplied volume bytes.

import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'disk_partition_fixture.dart';

class DiskImageFixture implements koni.ByteSource {
  factory DiskImageFixture.gpt({
    required List<koni.ByteSource> volumes,
    int sectorBytes = 512,
    int firstPartitionLba = 128,
    int? totalBytes,
  }) {
    final ranges = <(int, int, koni.ByteSource)>[];
    var next = firstPartitionLba;
    for (final volume in volumes) {
      final sectors = (volume.length + sectorBytes - 1) ~/ sectorBytes;
      ranges.add((next * sectorBytes, sectors * sectorBytes, volume));
      next += sectors + 16;
    }
    final length = totalBytes ?? (next + 128) * sectorBytes;
    final layout = DiskPartitionFixture.gpt(
      sectorBytes: sectorBytes,
      totalBytes: length,
    );
    layout.primaryTable.fillRange(0, layout.primaryTable.length, 0);
    for (var index = 0; index < ranges.length; index++) {
      final range = ranges[index];
      layout.setPartition(
        index,
        range.$1 ~/ sectorBytes,
        (range.$1 + range.$2) ~/ sectorBytes - 1,
      );
    }
    layout.backupTable.setAll(0, layout.primaryTable);
    layout.updateTableCrc();
    layout.updateTableCrc(backup: true);
    return DiskImageFixture._(length, sectorBytes, layout.mbr, ranges, layout);
  }

  factory DiskImageFixture.mbr({
    required List<koni.ByteSource> volumes,
    int sectorBytes = 512,
    int firstPartitionLba = 128,
    List<int>? types,
  }) {
    if (volumes.length > 4) throw ArgumentError('At most four MBR volumes.');
    final mbr = Uint8List(512)..setAll(510, [0x55, 0xaa]);
    final ranges = <(int, int, koni.ByteSource)>[];
    var next = firstPartitionLba;
    for (var index = 0; index < volumes.length; index++) {
      final volume = volumes[index];
      final sectors = (volume.length + sectorBytes - 1) ~/ sectorBytes;
      ranges.add((next * sectorBytes, sectors * sectorBytes, volume));
      final at = 446 + 16 * index;
      mbr[at + 4] = types?[index] ?? 0x01;
      partitionFixtureSet32(mbr, at + 8, next);
      partitionFixtureSet32(mbr, at + 12, sectors);
      next += sectors + 16;
    }
    return DiskImageFixture._(
      (next + 128) * sectorBytes,
      sectorBytes,
      mbr,
      ranges,
      null,
    );
  }

  DiskImageFixture._(
    this.physicalLength,
    this.sectorBytes,
    this.mbr,
    this.volumes,
    this.gpt,
  );

  final int physicalLength;
  final int sectorBytes;
  final Uint8List mbr;
  final List<(int, int, koni.ByteSource)> volumes;
  final DiskPartitionFixture? gpt;
  final reads = <(int, int)>[];
  bool closed = false;
  int closeCount = 0;
  int? reportedLength;
  Object? readError;
  bool Function(int offset, int count)? failWhen;
  void Function(int offset, int count)? onRead;
  bool shortNextRead = false;

  @override
  int get length => reportedLength ?? physicalLength;
  @override
  String get name => 'partitioned-reference.img';

  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closed) throw StateError('Fixture is closed.');
    if (offset < 0 ||
        count < 0 ||
        offset > physicalLength ||
        count > physicalLength - offset) {
      throw RangeError('Fixture read out of range.');
    }
    reads.add((offset, count));
    onRead?.call(offset, count);
    if (readError != null && (failWhen?.call(offset, count) ?? true)) {
      throw readError!;
    }
    final bytes = gpt?.read(offset, count) ?? Uint8List(count);
    if (gpt == null && offset < mbr.length) {
      final end = offset + count < mbr.length ? offset + count : mbr.length;
      bytes.setRange(0, end - offset, mbr, offset);
    }
    for (final volume in volumes) {
      final first = offset > volume.$1 ? offset : volume.$1;
      final sourceEnd = volume.$1 + volume.$3.length;
      final end = offset + count < sourceEnd ? offset + count : sourceEnd;
      if (end > first) {
        bytes.setRange(
          first - offset,
          end - offset,
          await volume.$3.read(first - volume.$1, end - first),
        );
      }
    }
    if (shortNextRead && bytes.isNotEmpty) {
      shortNextRead = false;
      return bytes.sublist(0, bytes.length - 1);
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    closeCount++;
    closed = true;
  }
}
