// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// SDK-only acceptance entry point. Run directly on Dart VM, then compile this
// exact file with `dart compile js -O2` and execute the emitted JavaScript.
// Relative imports keep this independent of Flutter package resolution; print
// provides the process-level acceptance receipt in VM and JavaScript runtimes.
// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../lib/services/binary_structure_service.dart';
import '../../lib/services/disk_partition_inspector.dart';
import 'disk_partition_fixture.dart';

var _checks = 0;
void _check(bool value, String message) {
  _checks++;
  if (!value) throw StateError(message);
}

Future<DiskPartitionAnalysis> _inspect(DiskPartitionFixture fixture) =>
    inspectDiskPartitions(totalBytes: fixture.totalBytes, read: fixture.read);

bool _has(DiskPartitionAnalysis result, DiskPartitionFindingCode code) =>
    result.findings.any((finding) => finding.code == code);

Iterable<BinaryStructureField> _flatten(
  List<BinaryStructureField> fields,
) sync* {
  for (final field in fields) {
    yield field;
    yield* _flatten(field.children);
  }
}

void _bounded(DiskPartitionFixture fixture, DiskPartitionAnalysis result) {
  _check(result.inspectedBytes <= diskPartitionReadLimit, 'Total read bound');
  for (final read in fixture.reads) {
    _check(
      read.$1 >= 0 && read.$1 + read.$2 <= fixture.totalBytes,
      'Positional read range',
    );
    _check(read.$2 <= diskPartitionReadChunkBytes, 'Per-read bound');
  }
  for (final field in _flatten(result.fields)) {
    _check(
      field.start >= 0 &&
          field.end > field.start &&
          field.end <= fixture.totalBytes,
      'Selectable field range',
    );
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--fixtures-json')) {
    print(
      jsonEncode([
        for (final fixture in [
          DiskPartitionFixture.gpt(),
          DiskPartitionFixture.gpt(sectorBytes: 4096),
          DiskPartitionFixture.gpt(totalBytes: 5 * 1024 * 1024 * 1024 * 1024),
        ])
          {
            'sector_bytes': fixture.sectorBytes,
            'total_bytes': fixture.totalBytes,
            'primary_header': base64Encode(fixture.primaryHeader),
            'backup_header': base64Encode(fixture.backupHeader),
            'primary_table': base64Encode(fixture.primaryTable),
            'backup_table': base64Encode(fixture.backupTable),
            'mbr': base64Encode(fixture.mbr),
          },
      ]),
    );
    return;
  }
  var groups = 0;
  _check(
    partitionFixtureCrc32('123456789'.codeUnits) == 0xcbf43926,
    'Independent CRC32 check value',
  );
  for (final sector in [512, 4096]) {
    final fixture = DiskPartitionFixture.gpt(sectorBytes: sector);
    final result = await _inspect(fixture);
    _check(result.scheme == DiskPartitionScheme.gpt, 'GPT recognition');
    _check(result.sectorBytes == sector, 'Logical sector detection');
    _check(result.findings.isEmpty, 'Valid GPT must have no findings');
    _check(result.headers.length == 2, 'Two independent header results');
    for (final header in result.headers) {
      _check(
        header.headerCrcStatus == DiskPartitionCheckStatus.valid,
        'Header CRC32',
      );
      _check(
        header.tableCrcStatus == DiskPartitionCheckStatus.valid,
        'Array CRC32',
      );
      _check(header.partitions.single.name == 'CrispCloud test', 'UTF-16 name');
    }
    for (final read in fixture.reads) {
      _check(
        read.$1 + read.$2 <= fixture.firstUsable * sector ||
            read.$1 >= (fixture.lastUsable + 1) * sector,
        'Valid GPT inspection must not read usable partition sectors',
      );
    }
    _bounded(fixture, result);
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt(
      totalBytes: 5 * 1024 * 1024 * 1024 * 1024,
    );
    final result = await _inspect(fixture);
    _check(result.findings.isEmpty, 'Sparse 5 TiB metadata');
    _check(
      result.headers.last.offset == fixture.totalBytes - 512,
      'Exact backup offset beyond 32 bits',
    );
    _check(result.inspectedBytes < 64 * 1024, 'Large disk remains lazy');
    _bounded(fixture, result);
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    final huge = (BigInt.one << 64) - BigInt.one;
    partitionFixtureSet64(fixture.primaryHeader, 72, huge);
    fixture.updateHeaderCrc();
    final result = await _inspect(fixture);
    _check(
      _has(result, DiskPartitionFindingCode.outOfRange),
      'Huge LBA rejected',
    );
    _check(
      result.headers.first.tableCrcStatus == DiskPartitionCheckStatus.unchecked,
      'Unaddressable table remains unchecked',
    );
    _check(
      _flatten(result.fields).any((field) => field.value == huge.toString()),
      'Exact unsigned 64-bit text',
    );
    _bounded(fixture, result);
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    partitionFixtureSet32(fixture.primaryHeader, 80, 0xffffffff);
    partitionFixtureSet32(fixture.backupHeader, 84, 0x80000000);
    fixture.updateHeaderCrc();
    fixture.updateHeaderCrc(backup: true);
    final result = await _inspect(fixture);
    _check(
      _has(result, DiskPartitionFindingCode.metadataLimit),
      'Entry/array caps',
    );
    _check(result.inspectedBytes < 16 * 1024, 'No oversized array read');
    _bounded(fixture, result);
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    fixture.primaryHeader[16] ^= 1;
    fixture.backupTable[56] ^= 1;
    final result = await _inspect(fixture);
    _check(
      result.headers.first.headerCrcStatus == DiskPartitionCheckStatus.invalid,
      'Broken header CRC',
    );
    _check(
      result.headers.first.tableCrcStatus == DiskPartitionCheckStatus.valid,
      'Independent valid array CRC',
    );
    _check(
      result.headers.last.headerCrcStatus == DiskPartitionCheckStatus.valid,
      'Independent valid backup header',
    );
    _check(
      result.headers.last.tableCrcStatus == DiskPartitionCheckStatus.invalid,
      'Broken array CRC',
    );
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    fixture.backupHeader[56] ^= 1;
    fixture.setPartition(
      0,
      fixture.firstUsable + 1,
      fixture.firstUsable + 10,
      backup: true,
      name: 'Mirror \u03a9 \u{1F30D}',
    );
    fixture.updateTableCrc(backup: true);
    final result = await _inspect(fixture);
    _check(
      _has(result, DiskPartitionFindingCode.headerMismatch),
      'Header disagreement',
    );
    _check(
      _has(result, DiskPartitionFindingCode.arrayMismatch),
      'Array disagreement',
    );
    _check(
      result.headers.last.partitions.single.name == 'Mirror \u03a9 \u{1F30D}',
      'UTF-16 surrogate pair decoding',
    );
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    fixture.setPartition(1, fixture.firstUsable + 10, fixture.firstUsable + 20);
    fixture.setPartition(2, fixture.lastUsable + 1, fixture.lastUsable + 10);
    fixture.updateTableCrc();
    final result = await _inspect(fixture);
    _check(
      _has(result, DiskPartitionFindingCode.overlap),
      'Nested interval overlap',
    );
    _check(
      _has(result, DiskPartitionFindingCode.outOfRange),
      'Partition bounds',
    );
    _bounded(fixture, result);
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    partitionFixtureSet64(
      fixture.primaryHeader,
      72,
      BigInt.from(fixture.firstUsable),
    );
    fixture.updateHeaderCrc();
    final result = await _inspect(fixture);
    _check(
      result.headers.first.tableCrcStatus == DiskPartitionCheckStatus.unchecked,
      'Unsafe metadata placement stays unchecked',
    );
    _check(
      !fixture.reads.any((read) => read.$1 == fixture.firstUsable * 512),
      'Unsafe pointer is never followed into partition data',
    );
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    var cancelled = false;
    final operation = inspectDiskPartitions(
      totalBytes: fixture.totalBytes,
      read: fixture.read,
      isCancelled: () => cancelled,
    );
    Timer.run(() => cancelled = true);
    try {
      await operation;
      throw StateError('Expected typed cancellation');
    } on DiskPartitionInspectionCancelled {
      _check(fixture.reads.isEmpty, 'Event-loop cancellation before sync read');
    }
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    fixture.primaryHeader[92] = 1;
    fixture.backupHeader[511] = 1;
    final result = await _inspect(fixture);
    _check(
      _has(result, DiskPartitionFindingCode.invalidHeader),
      'Reserved GPT header bytes are independently checked',
    );
    _check(
      result.headers.every(
        (header) => header.headerCrcStatus == DiskPartitionCheckStatus.valid,
      ),
      'Valid CRCs do not hide reserved-tail violations',
    );
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    partitionFixtureSet64(fixture.backupHeader, 48, BigInt.from(100));
    partitionFixtureSet64(fixture.backupHeader, 72, BigInt.from(110));
    fixture.updateHeaderCrc(backup: true);
    final result = await _inspect(fixture);
    _check(
      _has(result, DiskPartitionFindingCode.headerMismatch),
      'Cross-mirror usable-range disagreement',
    );
    _check(
      result.headers.last.tableCrcStatus == DiskPartitionCheckStatus.unchecked,
      'Array in peer-declared partition area remains unchecked',
    );
    _check(
      !fixture.reads.any((read) => read.$1 == 110 * 512),
      'Peer-declared payload is never followed as an array',
    );
    groups++;
  }
  {
    final fixture = DiskPartitionFixture.gpt();
    try {
      await inspectDiskPartitions(
        totalBytes: fixture.totalBytes,
        read: (offset, length) {
          final bytes = fixture.read(offset, length);
          if (offset == 512 && length == 512) {
            bytes[0] = 0;
            partitionFixtureSet32(bytes, 16, 0);
            partitionFixtureSet32(
              bytes,
              16,
              partitionFixtureCrc32(bytes.sublist(0, 92)),
            );
          }
          return bytes;
        },
      );
      throw ArgumentError('Expected inconsistent-header-read StateError');
    } on StateError {
      _check(
        !fixture.reads.any(
          (read) =>
              read.$1 == fixture.primaryTableOffset &&
              read.$2 == fixture.primaryTable.length,
        ),
        'Changed full header prevents table reads and result publication',
      );
    }
    groups++;
  }
  {
    try {
      await inspectDiskPartitions(
        totalBytes: 1024,
        read: (_, length) => Uint8List(length - 1),
      );
      throw ArgumentError('Expected short-read StateError');
    } on StateError {
      _check(true, 'Short read rejected');
    }
    groups++;
  }
  print('Disk partition acceptance: $groups groups passed ($_checks checks).');
}
