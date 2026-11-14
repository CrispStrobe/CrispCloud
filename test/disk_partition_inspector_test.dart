import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/binary_structure_service.dart';
import 'package:crisp_cloud/services/disk_partition_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/disk_partition_fixture.dart';

Future<DiskPartitionAnalysis> _inspect(
  DiskPartitionFixture fixture, {
  int? sector,
}) => inspectDiskPartitions(
  totalBytes: fixture.totalBytes,
  read: fixture.read,
  logicalSectorBytes: sector,
);

Iterable<BinaryStructureField> _flatten(
  List<BinaryStructureField> fields,
) sync* {
  for (final field in fields) {
    yield field;
    yield* _flatten(field.children);
  }
}

Set<DiskPartitionFindingCode> _codes(DiskPartitionAnalysis result) =>
    result.findings.map((finding) => finding.code).toSet();

void _assertReadBounds(
  DiskPartitionFixture fixture,
  DiskPartitionAnalysis result,
) {
  expect(
    fixture.reads.fold<int>(0, (sum, read) => sum + read.$2),
    result.inspectedBytes,
  );
  expect(result.inspectedBytes, lessThanOrEqualTo(diskPartitionReadLimit));
  for (final read in fixture.reads) {
    expect(read.$1, greaterThanOrEqualTo(0));
    expect(read.$2, lessThanOrEqualTo(diskPartitionReadChunkBytes));
    expect(read.$1 + read.$2, lessThanOrEqualTo(fixture.totalBytes));
  }
  for (final field in _flatten(result.fields)) {
    expect(field.start, greaterThanOrEqualTo(0), reason: field.name);
    expect(field.end, greaterThan(field.start), reason: field.name);
    expect(
      field.end,
      lessThanOrEqualTo(fixture.totalBytes),
      reason: field.name,
    );
    // Every field interval must be covered by reads, not merely lie within the
    // source size. Array groups may span multiple adjacent bounded reads.
    var covered = field.start;
    final reads = [...fixture.reads]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final read in reads) {
      if (read.$1 <= covered && read.$1 + read.$2 > covered) {
        covered = read.$1 + read.$2;
      }
    }
    expect(covered, greaterThanOrEqualTo(field.end), reason: field.name);
  }
}

void main() {
  test('independent fixture CRC has the IEEE check value', () {
    expect(partitionFixtureCrc32('123456789'.codeUnits), 0xcbf43926);
  });

  for (final size in [512, 4096]) {
    test(
      'auto-detects $size-byte GPT and checks both independent mirrors',
      () async {
        final fixture = DiskPartitionFixture.gpt(sectorBytes: size);
        final result = await _inspect(fixture);
        expect(result.scheme, DiskPartitionScheme.gpt);
        expect(result.sectorBytes, size);
        expect(result.findings, isEmpty);
        expect(result.headers.length, 2);
        for (final header in result.headers) {
          expect(header.present, isTrue);
          expect(header.headerCrcStatus, DiskPartitionCheckStatus.valid);
          expect(header.tableCrcStatus, DiskPartitionCheckStatus.valid);
          expect(header.partitions.single.name, 'CrispCloud test');
          expect(
            header.partitions.single.type,
            'C12A7328-F81F-11D2-BA4B-00A0C93EC93B',
          );
        }
        _assertReadBounds(fixture, result);
        final firstPayload = fixture.firstUsable * size;
        final lastPayload = (fixture.lastUsable + 1) * size;
        for (final read in fixture.reads) {
          expect(
            read.$1 + read.$2 <= firstPayload || read.$1 >= lastPayload,
            isTrue,
            reason: 'No reads from the usable partition area.',
          );
        }
      },
    );
  }

  test(
    '5 TiB sparse image reads only bounded metadata including physical tail',
    () async {
      final fixture = DiskPartitionFixture.gpt(
        totalBytes: 5 * 1024 * 1024 * 1024 * 1024,
      );
      final result = await _inspect(fixture);
      expect(result.findings, isEmpty);
      expect(result.headers.last.offset, fixture.totalBytes - 512);
      expect(fixture.reads, contains((fixture.totalBytes - 512, 512)));
      expect(result.inspectedBytes, lessThan(64 * 1024));
      _assertReadBounds(fixture, result);
    },
  );

  test('header and array CRC failures are reported independently', () async {
    final fixture = DiskPartitionFixture.gpt();
    fixture.primaryHeader[16] ^= 0x80;
    fixture.backupTable[56] ^= 1;
    final result = await _inspect(fixture);
    expect(
      result.headers.first.headerCrcStatus,
      DiskPartitionCheckStatus.invalid,
    );
    expect(result.headers.first.tableCrcStatus, DiskPartitionCheckStatus.valid);
    expect(result.headers.last.headerCrcStatus, DiskPartitionCheckStatus.valid);
    expect(
      result.headers.last.tableCrcStatus,
      DiskPartitionCheckStatus.invalid,
    );
    expect(
      _codes(result),
      containsAll([
        DiskPartitionFindingCode.headerCrcMismatch,
        DiskPartitionFindingCode.tableCrcMismatch,
        DiskPartitionFindingCode.arrayMismatch,
      ]),
    );
  });

  test(
    'missing primary still inspects backup; missing checks stay unchecked',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      fixture.primaryHeader[0] = 0;
      final result = await _inspect(fixture);
      expect(result.headers.first.present, isFalse);
      expect(
        result.headers.first.headerCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(
        result.headers.first.tableCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(
        result.headers.last.tableCrcStatus,
        DiskPartitionCheckStatus.valid,
      );
      expect(
        _codes(result),
        contains(DiskPartitionFindingCode.missingGptHeader),
      );
    },
  );

  test('missing backup is not presented as verified', () async {
    final fixture = DiskPartitionFixture.gpt();
    fixture.backupHeader[0] = 0;
    final result = await _inspect(fixture);
    expect(result.headers.first.tableCrcStatus, DiskPartitionCheckStatus.valid);
    expect(result.headers.last.present, isFalse);
    expect(
      result.headers.last.tableCrcStatus,
      DiskPartitionCheckStatus.unchecked,
    );
  });

  test(
    'valid CRCs do not hide contradictory headers or different arrays',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      fixture.backupHeader[56] ^= 1;
      fixture.setPartition(
        0,
        fixture.firstUsable + 10,
        fixture.firstUsable + 32,
        backup: true,
        name: 'Different mirror',
      );
      fixture.updateTableCrc(backup: true);
      final result = await _inspect(fixture);
      expect(
        result.headers.every(
          (header) =>
              header.headerCrcStatus == DiskPartitionCheckStatus.valid &&
              header.tableCrcStatus == DiskPartitionCheckStatus.valid,
        ),
        isTrue,
      );
      expect(
        _codes(result),
        containsAll([
          DiskPartitionFindingCode.headerMismatch,
          DiskPartitionFindingCode.arrayMismatch,
        ]),
      );
    },
  );

  test(
    'overlapping, reversed and out-of-range GPT records are disclosed',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      fixture.setPartition(
        1,
        fixture.firstUsable + 20,
        fixture.firstUsable + 40,
      );
      fixture.setPartition(2, 10, 5);
      fixture.setPartition(3, fixture.lastUsable - 1, fixture.lastUsable + 1);
      fixture.updateTableCrc();
      final result = await _inspect(fixture);
      expect(
        _codes(result),
        containsAll([
          DiskPartitionFindingCode.overlap,
          DiskPartitionFindingCode.outOfRange,
        ]),
      );
      _assertReadBounds(fixture, result);
    },
  );

  test(
    'unsigned 64-bit malicious LBAs remain exact and never become read offsets',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      final huge = (BigInt.one << 64) - BigInt.one;
      partitionFixtureSet64(fixture.primaryHeader, 72, huge);
      fixture.updateHeaderCrc();
      final result = await _inspect(fixture);
      expect(
        result.headers.first.tableCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(_codes(result), contains(DiskPartitionFindingCode.outOfRange));
      expect(
        _flatten(result.fields).any((field) => field.value == '$huge'),
        isTrue,
      );
      expect(
        fixture.reads.any(
          (read) =>
              read.$1 == fixture.primaryTableOffset &&
              read.$2 == fixture.primaryTable.length,
        ),
        isFalse,
      );
      _assertReadBounds(fixture, result);
    },
  );

  test('metadata pointing into usable sectors is not followed', () async {
    final fixture = DiskPartitionFixture.gpt();
    partitionFixtureSet64(
      fixture.primaryHeader,
      72,
      BigInt.from(fixture.firstUsable + 10),
    );
    fixture.updateHeaderCrc();
    final result = await _inspect(fixture);
    expect(
      result.headers.first.tableCrcStatus,
      DiskPartitionCheckStatus.unchecked,
    );
    expect(
      _codes(result),
      containsAll([
        DiskPartitionFindingCode.overlap,
        DiskPartitionFindingCode.tableNotInspected,
      ]),
    );
    expect(
      fixture.reads.any((read) => read.$1 == (fixture.firstUsable + 10) * 512),
      isFalse,
    );
    _assertReadBounds(fixture, result);
  });

  test('huge entry count and size stop before array reads', () async {
    final fixture = DiskPartitionFixture.gpt();
    partitionFixtureSet32(fixture.primaryHeader, 80, 0xffffffff);
    partitionFixtureSet32(fixture.backupHeader, 84, 0x80000000);
    fixture.updateHeaderCrc();
    fixture.updateHeaderCrc(backup: true);
    final result = await _inspect(fixture);
    expect(
      result.headers.every(
        (header) => header.tableCrcStatus == DiskPartitionCheckStatus.unchecked,
      ),
      isTrue,
    );
    expect(_codes(result), contains(DiskPartitionFindingCode.metadataLimit));
    expect(result.inspectedBytes, lessThan(16 * 1024));
    _assertReadBounds(fixture, result);
  });

  test(
    'invalid header sizes and unsupported revisions retain unchecked tables',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      partitionFixtureSet32(fixture.primaryHeader, 12, 91);
      partitionFixtureSet32(fixture.backupHeader, 8, 0x00020000);
      fixture.updateHeaderCrc(backup: true);
      final result = await _inspect(fixture);
      expect(
        result.headers.first.headerCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(
        result.headers.first.tableCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(
        result.headers.last.headerCrcStatus,
        DiskPartitionCheckStatus.valid,
      );
      expect(
        result.headers.last.tableCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(
        _codes(result),
        containsAll([
          DiskPartitionFindingCode.invalidHeader,
          DiskPartitionFindingCode.unsupportedRevision,
        ]),
      );
    },
  );

  test(
    'finding count is capped with explicit omitted-findings notice',
    () async {
      final fixture = DiskPartitionFixture.gpt(entryCount: 1024);
      for (var i = 0; i < 1024; i++) {
        fixture.setPartition(
          i,
          fixture.firstUsable + 8,
          fixture.firstUsable + 31,
          uniqueId: 1,
        );
      }
      fixture.updateTableCrc();
      final result = await _inspect(fixture);
      expect(result.findings.length, diskPartitionMaxFindings);
      expect(
        result.findings.last.code,
        DiskPartitionFindingCode.findingsTruncated,
      );
      _assertReadBounds(fixture, result);
    },
  );

  test('ambiguous sector signatures require explicit selection', () async {
    final fixture = DiskPartitionFixture.gpt();
    fixture.primaryTable.setAll(
      4096 - fixture.primaryTableOffset,
      'EFI PART'.codeUnits,
    );
    final result = await _inspect(fixture);
    expect(result.sectorBytes, isNull);
    expect(result.headers, isEmpty);
    expect(
      _codes(result),
      contains(DiskPartitionFindingCode.sectorSizeAmbiguous),
    );
    final selected = await _inspect(fixture, sector: 512);
    expect(selected.sectorBytes, 512);
    expect(selected.headers.length, 2);
  });

  test(
    'MBR alone discloses assumed sector size and extended-chain limit',
    () async {
      final bytes = Uint8List(1024 * 1024)
        ..[510] = 0x55
        ..[511] = 0xaa;
      bytes[450] = 0x05;
      partitionFixtureSet32(bytes, 454, 10);
      partitionFixtureSet32(bytes, 458, 20);
      Future<DiskPartitionAnalysis> inspect([int? sector]) =>
          inspectDiskPartitions(
            totalBytes: bytes.length,
            read: (offset, length) =>
                Uint8List.sublistView(bytes, offset, offset + length),
            logicalSectorBytes: sector,
          );
      final result = await inspect();
      expect(result.scheme, DiskPartitionScheme.mbr);
      expect(
        _codes(result),
        containsAll([
          DiskPartitionFindingCode.sectorSizeAssumed,
          DiskPartitionFindingCode.extendedPartitionsNotInspected,
        ]),
      );
      final explicit = await inspect(4096);
      expect(explicit.sectorBytes, 4096);
      expect(
        _codes(explicit),
        isNot(contains(DiskPartitionFindingCode.sectorSizeAssumed)),
      );
    },
  );

  test(
    'boot-sector signature alone does not identify a partitioned disk',
    () async {
      final bytes = Uint8List(1024)
        ..[510] = 0x55
        ..[511] = 0xaa;
      final result = await inspectDiskPartitions(
        totalBytes: bytes.length,
        read: (offset, length) =>
            Uint8List.sublistView(bytes, offset, offset + length),
      );
      expect(result.scheme, DiskPartitionScheme.none);
      expect(
        _codes(result),
        contains(DiskPartitionFindingCode.noPartitionTable),
      );
    },
  );

  test(
    'truncated inputs produce diagnostics without speculative reads',
    () async {
      for (final length in [0, 1, 510, 511]) {
        final calls = <(int, int)>[];
        final result = await inspectDiskPartitions(
          totalBytes: length,
          read: (offset, count) {
            calls.add((offset, count));
            return Uint8List(count);
          },
        );
        expect(result.scheme, DiskPartitionScheme.none);
        expect(calls, [(0, length)]);
        expect(_codes(result), contains(DiskPartitionFindingCode.truncated));
      }
    },
  );

  test(
    'snapshot validation brackets reads and rejects replaced sources',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      var calls = 0;
      await expectLater(
        inspectDiskPartitions(
          totalBytes: fixture.totalBytes,
          read: fixture.read,
          validateUnchanged: () {
            if (++calls == 2) throw StateError('changed source');
          },
        ),
        throwsStateError,
      );
      expect(calls, 2);
      expect(fixture.reads, isNotEmpty);
    },
  );

  test('initial snapshot rejection performs no reads', () async {
    final fixture = DiskPartitionFixture.gpt();
    await expectLater(
      inspectDiskPartitions(
        totalBytes: fixture.totalBytes,
        read: fixture.read,
        validateUnchanged: () => throw StateError('changed source'),
      ),
      throwsStateError,
    );
    expect(fixture.reads, isEmpty);
  });

  test(
    'short read is an IO failure, not a partially published analysis',
    () async {
      await expectLater(
        inspectDiskPartitions(
          totalBytes: 1024,
          read: (offset, count) => Uint8List(count - 1),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'cancellation is typed and yields the event loop before a sync read',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      var cancelled = false;
      final future = inspectDiskPartitions(
        totalBytes: fixture.totalBytes,
        read: fixture.read,
        isCancelled: () => cancelled,
      );
      Timer.run(() => cancelled = true);
      await expectLater(
        future,
        throwsA(isA<DiskPartitionInspectionCancelled>()),
      );
      expect(fixture.reads, isEmpty);
    },
  );

  test('cancellation after a bounded read prevents any later reads', () async {
    final fixture = DiskPartitionFixture.gpt();
    var cancelled = false;
    await expectLater(
      inspectDiskPartitions(
        totalBytes: fixture.totalBytes,
        read: (offset, length) {
          final value = fixture.read(offset, length);
          cancelled = true;
          return value;
        },
        isCancelled: () => cancelled,
      ),
      throwsA(isA<DiskPartitionInspectionCancelled>()),
    );
    expect(fixture.reads.length, 1);
  });

  test('invalid caller geometry is rejected before reads', () async {
    await expectLater(
      inspectDiskPartitions(
        totalBytes: -1,
        read: (_, count) => Uint8List(count),
      ),
      throwsArgumentError,
    );
    await expectLater(
      inspectDiskPartitions(
        totalBytes: 1024,
        logicalSectorBytes: 1024,
        read: (_, count) => Uint8List(count),
      ),
      throwsArgumentError,
    );
  });
}
