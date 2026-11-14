import 'dart:typed_data';

import 'package:crisp_cloud/services/disk_partition_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/disk_partition_fixture.dart';

// Independent review regressions based on UEFI 2.11 chapter 5:
// https://uefi.org/specs/UEFI/2.11/05_GUID_Partition_Table_Format.html
// The fixture's independent CRC routine deliberately keeps corrupted metadata
// checksummed in these cases, separating structural findings from CRC failures.

Set<DiskPartitionFindingCode> _codes(DiskPartitionAnalysis result) =>
    result.findings.map((finding) => finding.code).toSet();

Future<DiskPartitionAnalysis> _inspect(DiskPartitionFixture fixture) =>
    inspectDiskPartitions(totalBytes: fixture.totalBytes, read: fixture.read);

void _validChecksums(DiskPartitionAnalysis result) {
  expect(result.headers.length, 2);
  for (final header in result.headers) {
    expect(header.headerCrcStatus, DiskPartitionCheckStatus.valid);
    expect(header.tableCrcStatus, DiskPartitionCheckStatus.valid);
  }
}

void _boundedReads(DiskPartitionFixture fixture, DiskPartitionAnalysis result) {
  expect(result.inspectedBytes, lessThanOrEqualTo(diskPartitionReadLimit));
  expect(
    fixture.reads.fold<int>(0, (total, range) => total + range.$2),
    result.inspectedBytes,
  );
  for (final range in fixture.reads) {
    expect(range.$1, greaterThanOrEqualTo(0));
    expect(range.$2, lessThanOrEqualTo(diskPartitionReadChunkBytes));
    expect(range.$1 + range.$2, lessThanOrEqualTo(fixture.totalBytes));
  }
}

void main() {
  for (final sector in [512, 4096]) {
    for (final backup in [false, true]) {
      test('review: $sector-byte ${backup ? 'backup' : 'primary'} header '
          'reserved tail cannot produce a clean report', () async {
        final fixture = DiskPartitionFixture.gpt(sectorBytes: sector);
        final header = backup ? fixture.backupHeader : fixture.primaryHeader;
        final byte = backup ? sector - 1 : 92;
        header[byte] = 1; // Outside the 92-byte header CRC coverage.
        final result = await _inspect(fixture);
        _validChecksums(result);
        expect(
          _codes(result),
          contains(DiskPartitionFindingCode.invalidHeader),
        );
        final absolute = (backup ? fixture.totalBytes - sector : sector) + byte;
        expect(
          result.findings.any((finding) {
            final field = finding.field;
            return finding.code == DiskPartitionFindingCode.invalidHeader &&
                field != null &&
                field.start <= absolute &&
                field.end > absolute;
          }),
          isTrue,
          reason:
              'The finding identifies the metadata that contains the bad byte.',
        );
        _boundedReads(fixture, result);
      });
    }
  }

  final protectiveMutations = <String, void Function(Uint8List)>{
    'boot indicator': (mbr) => mbr[446] = 0x80,
    'disk signature': (mbr) => mbr[440] = 1,
    'unknown reserved word': (mbr) => mbr[444] = 1,
    'starting CHS': (mbr) => mbr[448] = 1,
    'otherwise unused partition record': (mbr) => mbr[462] = 1,
  };
  for (final mutation in protectiveMutations.entries) {
    test('review: protective MBR ${mutation.key} is checked', () async {
      final fixture = DiskPartitionFixture.gpt();
      mutation.value(fixture.mbr);
      final result = await _inspect(fixture);
      _validChecksums(result);
      expect(
        _codes(result),
        contains(DiskPartitionFindingCode.protectiveMbrMismatch),
      );
      _boundedReads(fixture, result);
    });
  }

  test('review: 4 KiB protective MBR reserved tail is inspected', () async {
    final fixture = DiskPartitionFixture.gpt(sectorBytes: 4096);
    const badOffset = 4095;
    final result = await inspectDiskPartitions(
      totalBytes: fixture.totalBytes,
      read: (offset, length) {
        final bytes = fixture.read(offset, length);
        if (offset <= badOffset && offset + length > badOffset) {
          bytes[badOffset - offset] = 1;
        }
        return bytes;
      },
    );
    _validChecksums(result);
    expect(
      _codes(result),
      contains(DiskPartitionFindingCode.protectiveMbrMismatch),
    );
    expect(
      fixture.reads.any(
        (range) => range.$1 <= badOffset && range.$1 + range.$2 > badOffset,
      ),
      isTrue,
    );
    _boundedReads(fixture, result);
  });

  test(
    'review: protective-only restrictions are not applied to legacy MBR',
    () async {
      final fixture = DiskPartitionFixture.gpt();
      fixture.primaryHeader[0] = 0;
      fixture.backupHeader[0] = 0;
      fixture.mbr[450] = 0x83;
      fixture.mbr[446] = 0x7f;
      fixture.mbr[440] = 1;
      fixture.mbr[444] = 1;
      fixture.mbr[462] =
          1; // Type/count zero: this legacy record may be ignored.
      partitionFixtureSet32(fixture.mbr, 454, 10);
      partitionFixtureSet32(fixture.mbr, 458, 20);
      final result = await _inspect(fixture);
      expect(result.scheme, DiskPartitionScheme.mbr);
      expect(
        _codes(result),
        isNot(contains(DiskPartitionFindingCode.protectiveMbrMismatch)),
      );
      expect(
        result.findings.where(
          (finding) => finding.severity == DiskPartitionFindingSeverity.error,
        ),
        isEmpty,
      );
      _boundedReads(fixture, result);
    },
  );

  for (final backup in [false, true]) {
    test('review: ${backup ? 'backup' : 'primary'} signature disagreement '
        'between probe and full read is an IO consistency failure', () async {
      final fixture = DiskPartitionFixture.gpt();
      final target = backup ? fixture.totalBytes - 512 : 512;
      await expectLater(
        inspectDiskPartitions(
          totalBytes: fixture.totalBytes,
          read: (offset, length) {
            final bytes = fixture.read(offset, length);
            if (offset == target && length == 512) {
              bytes[0] ^= 1;
              partitionFixtureSet32(bytes, 16, 0);
              partitionFixtureSet32(
                bytes,
                16,
                partitionFixtureCrc32(bytes.sublist(0, 92)),
              );
            }
            return bytes;
          },
        ),
        throwsStateError,
        reason: 'An earlier eight-byte signature cannot authenticate different full-header bytes.',
      );
    });
  }

  for (final backup in [false, true]) {
    test('review: ${backup ? 'backup' : 'primary'} array is not followed '
        'inside the peer header usable range', () async {
      final fixture = DiskPartitionFixture.gpt();
      final header = backup ? fixture.backupHeader : fixture.primaryHeader;
      if (backup) {
        partitionFixtureSet64(header, 48, BigInt.from(39));
      } else {
        partitionFixtureSet64(header, 40, BigInt.from(1000));
      }
      const conflictingLba = 40;
      partitionFixtureSet64(header, 72, BigInt.from(conflictingLba));
      fixture.updateHeaderCrc(backup: backup);
      final result = await _inspect(fixture);
      expect(
        result.headers[backup ? 1 : 0].headerCrcStatus,
        DiskPartitionCheckStatus.valid,
      );
      expect(
        result.headers[backup ? 1 : 0].tableCrcStatus,
        DiskPartitionCheckStatus.unchecked,
      );
      expect(
        _codes(result),
        containsAll([
          DiskPartitionFindingCode.overlap,
          DiskPartitionFindingCode.tableNotInspected,
          DiskPartitionFindingCode.headerMismatch,
        ]),
      );
      expect(
        fixture.reads.any((range) => range.$1 == conflictingLba * 512),
        isFalse,
        reason: 'Both headers are checksummed; their conflict must be resolved before following this pointer.',
      );
      _boundedReads(fixture, result);
    });
  }

  for (final excess in [-1, 1]) {
    test(
      'review: ${excess < 0 ? 'short' : 'oversized'} late metadata read never publishes an analysis',
      () async {
        final fixture = DiskPartitionFixture.gpt();
        await expectLater(
          inspectDiskPartitions(
            totalBytes: fixture.totalBytes,
            read: (offset, length) {
              final bytes = fixture.read(offset, length);
              if (offset == fixture.backupTableOffset) {
                return Uint8List(length + excess);
              }
              return bytes;
            },
          ),
          throwsStateError,
        );
        expect(
          fixture.reads.any((range) => range.$1 == fixture.primaryTableOffset),
          isTrue,
        );
        expect(fixture.reads.last.$1, fixture.backupTableOffset);
      },
    );
  }

  test('review: cancellation during final snapshot validation prevents publication', () async {
    final fixture = DiskPartitionFixture.gpt();
    var validations = 0;
    var cancelled = false;
    await expectLater(
      inspectDiskPartitions(
        totalBytes: fixture.totalBytes,
        read: fixture.read,
        isCancelled: () => cancelled,
        validateUnchanged: () async {
          if (++validations == 2) {
            await Future<void>.value();
            cancelled = true;
          }
        },
      ),
      throwsA(isA<DiskPartitionInspectionCancelled>()),
    );
    expect(validations, 2);
    expect(fixture.reads, isNotEmpty);
  });

  test(
    'review: two maximum-sized arrays stay inside the declared global budget',
    () async {
      final fixture = DiskPartitionFixture.gpt(
        totalBytes: 8 * 1024 * 1024,
        entryCount: diskPartitionMaxEntries,
        entrySize: 256,
      );
      expect(fixture.primaryTable.length, diskPartitionMaxTableBytes);
      final result = await _inspect(fixture);
      _validChecksums(result);
      expect(result.findings, isEmpty);
      expect(
        result.inspectedBytes,
        greaterThanOrEqualTo(2 * diskPartitionMaxTableBytes),
      );
      _boundedReads(fixture, result);
    },
  );

  test('review: the last complete sector below the JS exact-integer ceiling remains exact', () async {
    const total = 9007199254740480; // 2^53 - 512, exactly sector aligned.
    final fixture = DiskPartitionFixture.gpt(totalBytes: total);
    final result = await _inspect(fixture);
    _validChecksums(result);
    expect(result.findings, isEmpty);
    expect(result.headers.last.offset, total - 512);
    expect(fixture.reads, contains((total - 512, 512)));
    _boundedReads(fixture, result);
  });
}
