// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_fat_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/disk_partition_inspector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_disk_image_fixture.dart';
import 'support/archive_fat_fixture.dart';
import 'support/disk_partition_fixture.dart';

Matcher _archiveError(ArchiveMessageCode code) =>
    isA<ArchiveViewException>().having((error) => error.code, 'code', code);

ViewerArchiveMember _member(ViewerArchive archive, String path) =>
    archive.members.singleWhere((member) => member.name == path);

Future<DiskPartitionAnalysis> _inspect(DiskImageFixture source) =>
    inspectDiskPartitions(totalBytes: source.length, read: source.read);

List<String> _paths(ViewerArchive archive) =>
    archive.members.map((member) => member.name).toList();

bool _readTouchesVolume(DiskImageFixture source, (int, int) read) =>
    source.volumes.any(
      (volume) =>
          read.$1 < volume.$1 + volume.$2 && read.$1 + read.$2 > volume.$1,
    );

void _assertBoundedReads(DiskImageFixture source) {
  for (final read in source.reads) {
    expect(read.$1, greaterThanOrEqualTo(0));
    expect(read.$2, lessThanOrEqualTo(64 * 1024));
    expect(read.$2, lessThanOrEqualTo(source.physicalLength - read.$1));
  }
}

void _mirror(DiskPartitionFixture layout) {
  layout.backupTable.setAll(0, layout.primaryTable);
  layout.updateTableCrc();
  layout.updateTableCrc(backup: true);
}

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

void main() {
  group('fixed-position recognition', () {
    for (final sector in [512, 4096]) {
      test(
        'recognizes GPT with $sector-byte sectors without owning it',
        () async {
          final source = DiskImageFixture.gpt(
            volumes: [FatFixture(sectorBytes: sector).source()],
            sectorBytes: sector,
          );
          expect(await hasDiskImagePartitionRecognition(source), isTrue);
          expect(source.closeCount, 0);
          expect(
            source.reads.fold<int>(0, (sum, read) => sum + read.$2),
            lessThanOrEqualTo(1066),
          );
          expect(
            source.reads.any((read) => _readTouchesVolume(source, read)),
            isFalse,
          );
        },
      );
    }

    test('MBR needs plausible records, not only the 55AA trailer', () async {
      final empty = DiskImageFixture.mbr(volumes: []);
      expect(await hasDiskImagePartitionRecognition(empty), isFalse);
      final populated = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
      expect(await hasDiskImagePartitionRecognition(populated), isTrue);
      populated.mbr[446] = 0x01;
      expect(await hasDiskImagePartitionRecognition(populated), isFalse);
      expect(populated.closeCount, 0);
    });

    test(
      'standalone FAT boot code cannot masquerade as a partition table',
      () async {
        final fat = FatFixture();
        fat.boot[450] = 0x01;
        partitionFixtureSet32(fat.boot, 454, 128);
        partitionFixtureSet32(fat.boot, 458, 20);
        final source = fat.source();
        expect(await hasDiskImagePartitionRecognition(source), isFalse);
        expect(source.closeCount, 0);
        await expectLater(
          openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(_archiveError(ArchiveMessageCode.unsupported)),
        );
        expect(source.closeCount, 1);
      },
    );

    test(
      'short reads during recognition propagate instead of classifying',
      () async {
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()])
          ..shortNextRead = true;
        await expectLater(
          hasDiskImagePartitionRecognition(source),
          throwsA(_archiveError(ArchiveMessageCode.corrupt)),
        );
        expect(source.closeCount, 0);
      },
    );
  });

  group('composed browsing', () {
    for (final sector in [512, 4096]) {
      test(
        'GPT $sector deduplicates mirrors and streams exact FAT/raw bytes',
        () async {
          final fat = FatFixture(sectorBytes: sector);
          final source = DiskImageFixture.gpt(
            volumes: [fat.source()],
            sectorBytes: sector,
          );
          final analysis = await _inspect(source);
          // Inspection retains the protective MBR record and both GPT
          // evidence copies; only primary GPT records become archive rows.
          expect(analysis.partitions, hasLength(3));
          expect(
            analysis.headers.every((header) => header.partitions.length == 1),
            isTrue,
          );
          expect(diskImageAnalysisSupportsBrowsing(analysis), isTrue);
          final archive = await openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveStreamingLimit,
          );
          expect(archive.formatName, 'disk-image');
          expect(_paths(archive), [
            'partition-001',
            'partition-001/raw.img',
            'partition-001/files',
            'partition-001/files/HELLO.TXT',
          ]);
          final member = _member(archive, 'partition-001/files/HELLO.TXT');
          expect(await archive.readMember(member), fat.payload);
          expect(
            await _collect(archive.openMember(member, chunkSize: 3)),
            fat.payload,
          );
          final raw = _member(archive, 'partition-001/raw.img');
          expect(raw.size, fat.length);
          final rawPrefix = await archive
              .openMember(raw, maxBytes: kArchiveStreamingLimit, chunkSize: 512)
              .first;
          expect(rawPrefix, fat.boot.sublist(0, 512));
          expect(source.closed, isFalse);
          _assertBoundedReads(source);
          await archive.close();
          await archive.close();
          expect(source.closeCount, 1);
        },
      );
    }

    test(
      'MBR respects explicit 4096-byte units and discloses its default',
      () async {
        final ordinary = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        final assumed = await openDiskImageArchive(
          ordinary,
          maxMemberBytes: kArchiveReadLimit,
        );
        expect(assumed.notices.join(' '), contains('512'));
        expect(_paths(assumed), contains('partition-001/files/HELLO.TXT'));
        await assumed.close();

        final fat = FatFixture(sectorBytes: 4096);
        final source = DiskImageFixture.mbr(
          volumes: [fat.source()],
          sectorBytes: 4096,
        );
        final archive = await openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          logicalSectorBytes: 4096,
        );
        expect(
          await archive.readMember(
            _member(archive, 'partition-001/files/HELLO.TXT'),
          ),
          fat.payload,
        );
        expect(_member(archive, 'partition-001/raw.img').size, fat.length);
        await archive.close();
      },
    );

    test(
      'multiple volumes keep deterministic paths despite unsafe GPT labels',
      () async {
        final first = FatFixture(fileData: [1, 2, 3]);
        final second = FatFixture(fileData: [9, 8, 7, 6]);
        final source = DiskImageFixture.gpt(
          volumes: [first.source(), second.source()],
        );
        final layout = source.gpt!;
        final range = source.volumes.first;
        layout.setPartition(
          0,
          range.$1 ~/ 512,
          (range.$1 + range.$2) ~/ 512 - 1,
          name: '../bad\\label',
        );
        _mirror(layout);
        final archive = await openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
        );
        expect(archive.members, hasLength(8));
        expect(
          await archive.readMember(
            _member(archive, 'partition-001/files/HELLO.TXT'),
          ),
          first.payload,
        );
        expect(
          await archive.readMember(
            _member(archive, 'partition-002/files/HELLO.TXT'),
          ),
          second.payload,
        );
        expect(
          archive.members.every(
            (member) =>
                !member.name.contains('..') && !member.name.contains('\\'),
          ),
          isTrue,
        );
        await archive.close();
      },
    );

    test('sparse 5 TiB source retains exact 4 TiB partition offsets', () async {
      const tib = 1024 * 1024 * 1024 * 1024;
      final fat = FatFixture();
      final source = DiskImageFixture.gpt(
        volumes: [fat.source()],
        firstPartitionLba: 4 * tib ~/ 512,
        totalBytes: 5 * tib,
      );
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      final before = source.reads.length;
      expect(
        await archive.readMember(
          _member(archive, 'partition-001/files/HELLO.TXT'),
        ),
        fat.payload,
      );
      expect(source.reads.skip(before).single, (
        4 * tib + fat.fileOffset,
        fat.payload.length,
      ));
      expect(
        source.reads.fold<int>(0, (sum, read) => sum + read.$2),
        lessThan(128 * 1024),
      );
      _assertBoundedReads(source);
      await archive.close();
    });

    test('valid empty GPT is an empty read-only listing', () async {
      final source = DiskImageFixture.gpt(volumes: []);
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      expect(archive.members, isEmpty);
      expect(archive.notices, isNotEmpty);
      await archive.close();
      expect(source.closeCount, 1);
    });
  });

  group('raw-only filesystem boundaries', () {
    for (final type in [0x05, 0x0f, 0x42, 0xab]) {
      test(
        'MBR type 0x${type.toRadixString(16)} never probes a FAT-looking payload',
        () async {
          final source = DiskImageFixture.mbr(
            volumes: [FatFixture().source()],
            types: [type],
          );
          final archive = await openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveReadLimit,
          );
          expect(_paths(archive), ['partition-001', 'partition-001/raw.img']);
          expect(archive.notices.join(' '), contains('raw bytes only'));
          expect(
            source.reads.any((read) => _readTouchesVolume(source, read)),
            isFalse,
          );
          final raw = _member(archive, 'partition-001/raw.img');
          expect(
            (await archive.openMember(raw, chunkSize: 512).first).length,
            512,
          );
          await archive.close();
        },
      );
    }

    test(
      'GPT dynamic-disk type remains raw even when its bytes form FAT',
      () async {
        final source = DiskImageFixture.gpt(volumes: [FatFixture().source()]);
        // Microsoft's LDM data partition GUID in EFI_GUID byte order.
        source.gpt!.primaryTable.setRange(0, 16, [
          0xa0,
          0x60,
          0x9b,
          0xaf,
          0x31,
          0x14,
          0x62,
          0x4f,
          0xbc,
          0x68,
          0x33,
          0x11,
          0x71,
          0x4a,
          0x69,
          0xad,
        ]);
        _mirror(source.gpt!);
        final archive = await openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
        );
        expect(_paths(archive), ['partition-001', 'partition-001/raw.img']);
        expect(
          source.reads.any((read) => _readTouchesVolume(source, read)),
          isFalse,
        );
        expect(
          archive.notices.join(' '),
          contains('AF9B60A0-1431-4F62-BC68-3311714A69AD'),
        );
        await archive.close();
      },
    );

    test('eligible non-FAT partition remains available as raw bytes', () async {
      final source = DiskImageFixture.mbr(volumes: [_ZeroSource(1024 * 1024)]);
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      expect(_paths(archive), ['partition-001', 'partition-001/raw.img']);
      expect(archive.notices.join(' '), contains('no supported FAT volume'));
      await archive.close();
    });

    test('corrupt child never publishes a partial FAT listing', () async {
      final fat = FatFixture()..setFat(2, 0);
      final source = DiskImageFixture.mbr(volumes: [fat.source()]);
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      expect(_paths(archive), ['partition-001', 'partition-001/raw.img']);
      expect(archive.notices.join(' '), contains('FAT listing was refused'));
      expect(
        (await archive
            .openMember(
              _member(archive, 'partition-001/raw.img'),
              chunkSize: 512,
            )
            .first),
        fat.boot,
      );
      await archive.close();
      expect(source.closeCount, 1);
    });
  });

  group('partition authority', () {
    test(
      'conflicting GPT sector signatures never choose an implicit authority',
      () async {
        final source = DiskImageFixture.gpt(volumes: [FatFixture().source()]);
        source.gpt!.primaryTable.setRange(
          4096 - 1024,
          4096 - 1024 + 8,
          'EFI PART'.codeUnits,
        );
        final analysis = await _inspect(source);
        expect(analysis.sectorBytes, isNull);
        expect(
          analysis.findings.map((finding) => finding.code),
          contains(DiskPartitionFindingCode.sectorSizeAmbiguous),
        );
        expect(diskImageAnalysisSupportsBrowsing(analysis), isFalse);
        await expectLater(
          openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(_archiveError(ArchiveMessageCode.unsupported)),
        );
        expect(
          source.reads.any((read) => _readTouchesVolume(source, read)),
          isFalse,
        );
        expect(source.closeCount, 1);
      },
    );

    final damage = <String, void Function(DiskImageFixture)>{
      'primary header CRC': (source) => source.gpt!.primaryHeader[16] ^= 1,
      'backup header missing': (source) => source.gpt!.backupHeader[0] = 0,
      'backup array CRC': (source) => source.gpt!.backupTable[56] ^= 1,
      'different arrays with valid CRCs': (source) {
        source.gpt!.backupTable[56] ^= 1;
        source.gpt!.updateTableCrc(backup: true);
      },
      'protective MBR count': (source) =>
          partitionFixtureSet32(source.mbr, 458, 1),
      'hybrid MBR': (source) {
        source.mbr[466] = 0x01;
        partitionFixtureSet32(source.mbr, 470, 128);
        partitionFixtureSet32(source.mbr, 474, 20);
      },
      'unsigned 64-bit LBA': (source) {
        partitionFixtureSet64(
          source.gpt!.primaryTable,
          32,
          (BigInt.one << 64) - BigInt.one,
        );
        _mirror(source.gpt!);
      },
      'partition over metadata': (source) {
        partitionFixtureSet64(source.gpt!.primaryTable, 32, BigInt.from(2));
        _mirror(source.gpt!);
      },
      'overlapping GPT entries': (source) {
        final first = source.volumes.first.$1 ~/ 512;
        source.gpt!.setPartition(1, first + 2, first + 10);
        _mirror(source.gpt!);
      },
    };
    for (final entry in damage.entries) {
      test('refuses ${entry.key} before filesystem reads', () async {
        final source = DiskImageFixture.gpt(volumes: [FatFixture().source()]);
        entry.value(source);
        final analysis = await _inspect(source);
        final readsBeforeHelper = source.reads.length;
        expect(diskImageAnalysisSupportsBrowsing(analysis), isFalse);
        expect(source.reads.length, readsBeforeHelper);
        await expectLater(
          openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.closeCount, 1);
        expect(
          source.reads.any((read) => _readTouchesVolume(source, read)),
          isFalse,
        );
        _assertBoundedReads(source);
      });
    }

    test('MBR overlapping and out-of-range records are rejected', () async {
      for (final outOfRange in [false, true]) {
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        if (outOfRange) {
          partitionFixtureSet32(source.mbr, 458, 0xffffffff);
        } else {
          source.mbr[466] = 0x06;
          partitionFixtureSet32(source.mbr, 470, 128);
          partitionFixtureSet32(source.mbr, 474, 20);
        }
        await expectLater(
          openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(_archiveError(ArchiveMessageCode.corrupt)),
        );
        expect(source.closeCount, 1);
        expect(
          source.reads.any((read) => _readTouchesVolume(source, read)),
          isFalse,
        );
      }
    });
  });

  group('shared work and memory ceilings', () {
    test('partition cap rejects the whole table before child probes', () async {
      final source = DiskImageFixture.gpt(
        volumes: [FatFixture().source(), FatFixture().source()],
      );
      await expectLater(
        openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          maxPartitions: 1,
        ),
        throwsA(_archiveError(ArchiveMessageCode.archiveLimit)),
      );
      expect(
        source.reads.any((read) => _readTouchesVolume(source, read)),
        isFalse,
      );
      expect(source.closeCount, 1);
    });

    test(
      'combined entries preserve raw partition when no FAT rows fit',
      () async {
        final source = DiskImageFixture.mbr(
          volumes: [FatFixture().source(), FatFixture().source()],
        );
        final archive = await openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          maxEntries: 6,
        );
        expect(_paths(archive), [
          'partition-001',
          'partition-001/raw.img',
          'partition-001/files',
          'partition-001/files/HELLO.TXT',
          'partition-002',
          'partition-002/raw.img',
        ]);
        expect(
          archive.notices.join(' '),
          contains('No listing budget remains'),
        );
        await archive.close();
      },
    );

    test(
      'path ceiling counts relative and prefixed strings across children',
      () async {
        final source = DiskImageFixture.mbr(
          volumes: [FatFixture().source(), FatFixture().source()],
        );
        // One volume retains 164 bytes of composite paths plus 18 bytes of its
        // original child path. Both sets for two volumes total 364 bytes.
        await expectLater(
          openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveReadLimit,
            maxRetainedPathBytes: 350,
          ),
          throwsA(_archiveError(ArchiveMessageCode.archiveLimit)),
        );
        expect(source.closeCount, 1);
      },
    );

    test(
      'metadata ceiling is global and never becomes a raw fallback',
      () async {
        final source = DiskImageFixture.gpt(volumes: [FatFixture().source()]);
        await expectLater(
          openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveReadLimit,
            maxMetadataBytes: 1024,
          ),
          throwsA(_archiveError(ArchiveMessageCode.archiveLimit)),
        );
        expect(
          source.reads.fold<int>(0, (sum, read) => sum + read.$2),
          lessThanOrEqualTo(1024),
        );
        expect(source.closeCount, 1);
      },
    );

    for (final clusters in [true, false]) {
      test(
        'shared ${clusters ? 'cluster' : 'extent'} budget does not reset for each FAT volume',
        () async {
          final source = DiskImageFixture.mbr(
            volumes: [FatFixture().source(), FatFixture().source()],
          );
          final archive = await openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveReadLimit,
            maxClusters: clusters ? 1 : diskImageMaxClusters,
            maxExtents: clusters ? diskImageMaxExtents : 2,
          );
          expect(_paths(archive), contains('partition-001/files/HELLO.TXT'));
          expect(_paths(archive), isNot(contains('partition-002/files')));
          expect(_paths(archive), contains('partition-002/raw.img'));
          expect(
            archive.notices.join(' '),
            contains('FAT listing was refused'),
          );
          await archive.close();
        },
      );
    }

    test(
      'raw streams large members lazily without a large buffered allocation',
      () async {
        final source = DiskImageFixture.mbr(
          volumes: [_ZeroSource(65 * 1024 * 1024)],
          types: [0x83],
        );
        final archive = await openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveStreamingLimit,
        );
        final raw = _member(archive, 'partition-001/raw.img');
        source.reads.clear();
        await expectLater(
          archive.readMember(raw, maxBytes: kArchiveStreamingLimit),
          throwsA(_archiveError(ArchiveMessageCode.archiveLimit)),
        );
        expect(source.reads, isEmpty);
        expect(
          (await archive
                  .openMember(
                    raw,
                    maxBytes: kArchiveStreamingLimit,
                    chunkSize: 1024 * 1024,
                  )
                  .first)
              .length,
          64 * 1024,
        );
        expect(source.reads, hasLength(1));
        await Future<void>.delayed(Duration.zero);
        expect(source.reads, hasLength(1));
        expect(source.closed, isFalse);
        await archive.close();
      },
    );

    test('caller member allowance also applies to lazy raw reads', () async {
      final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
      final archive = await openDiskImageArchive(source, maxMemberBytes: 1024);
      final raw = _member(archive, 'partition-001/raw.img');
      source.reads.clear();
      await expectLater(
        archive.openMember(raw, maxBytes: kArchiveReadLimit).first,
        throwsA(_archiveError(ArchiveMessageCode.archiveLimit)),
      );
      expect(source.reads, isEmpty);
      await archive.close();
    });
  });

  group('source failures and ownership', () {
    test(
      'format-shaped provider exception is not swallowed as child rejection',
      () async {
        const error = ArchiveViewException(
          'Provider access was revoked.',
          code: ArchiveMessageCode.unsupported,
        );
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        source.readError = error;
        source.failWhen = (offset, count) => offset == source.volumes.first.$1;
        await expectLater(
          openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(same(error)),
        );
        expect(source.closeCount, 1);
      },
    );

    test(
      'short child probe is a source failure, not a raw-only success',
      () async {
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        source.onRead = (offset, count) {
          if (offset == source.volumes.first.$1) source.shortNextRead = true;
        };
        await expectLater(
          openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
          throwsA(
            isA<ArchiveViewException>().having(
              (error) => error.message,
              'message',
              contains('incomplete read'),
            ),
          ),
        );
        expect(source.closeCount, 1);
      },
    );

    test('cancellation before I/O closes exactly once', () async {
      final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
      await expectLater(
        openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          isCancelled: () => true,
        ),
        throwsA(isA<ArchiveDiskImageCancelledException>()),
      );
      expect(source.reads, isEmpty);
      expect(source.closeCount, 1);
    });

    test(
      'cancellation during a child read never publishes raw fallback',
      () async {
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        var cancelled = false;
        source.onRead = (offset, count) {
          if (_readTouchesVolume(source, (offset, count))) cancelled = true;
        };
        await expectLater(
          openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveReadLimit,
            isCancelled: () => cancelled,
          ),
          throwsA(
            anyOf(
              isA<ArchiveDiskImageCancelledException>(),
              isA<ArchiveFatCancelledException>(),
              isA<DiskPartitionInspectionCancelled>(),
            ),
          ),
        );
        expect(source.closeCount, 1);
      },
    );

    test(
      'revalidation exception retains identity and closes the root',
      () async {
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        final error = StateError('Source identity changed.');
        await expectLater(
          openDiskImageArchive(
            source,
            maxMemberBytes: kArchiveReadLimit,
            validateUnchanged: () {
              if (source.reads.any(
                (read) => _readTouchesVolume(source, read),
              )) {
                throw error;
              }
            },
          ),
          throwsA(same(error)),
        );
        expect(source.closeCount, 1);
      },
    );

    test('source-length changes during a pending read are rejected', () async {
      final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
      source.onRead = (offset, count) {
        if (offset == source.volumes.first.$1) {
          source.reportedLength = source.physicalLength - 512;
        }
      };
      await expectLater(
        openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
        throwsA(
          isA<ArchiveViewException>().having(
            (error) => error.message,
            'message',
            contains('length changed'),
          ),
        ),
      );
      expect(source.closeCount, 1);
    });

    test(
      'a closed archive and a foreign member cannot read the source',
      () async {
        final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
        final archive = await openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
        );
        final foreign = ViewerArchive.direct(
          formatName: 'other',
          name: 'file',
          data: Uint8List(0),
        );
        final reads = source.reads.length;
        await expectLater(
          archive.readMember(foreign.members.single),
          throwsA(isA<ArchiveViewException>()),
        );
        expect(source.reads.length, reads);
        final child = _member(archive, 'partition-001/files/HELLO.TXT');
        await archive.close();
        await expectLater(
          archive.readMember(child),
          throwsA(_archiveError(ArchiveMessageCode.closed)),
        );
        expect(source.reads.length, reads);
        expect(source.closeCount, 1);
        await foreign.close();
      },
    );

    test('invalid arguments close their source without reading', () async {
      final source = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
      await expectLater(
        openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          logicalSectorBytes: 1024,
        ),
        throwsArgumentError,
      );
      expect(source.reads, isEmpty);
      expect(source.closeCount, 1);
      final excessive = DiskImageFixture.mbr(volumes: [FatFixture().source()]);
      await expectLater(
        openDiskImageArchive(
          excessive,
          maxMemberBytes: kArchiveReadLimit,
          maxEntries: diskImageMaxEntries + 1,
        ),
        throwsArgumentError,
      );
      expect(excessive.reads, isEmpty);
      expect(excessive.closeCount, 1);
    });
  });
}

class _ZeroSource implements koni.ByteSource {
  _ZeroSource(this.length);
  @override
  final int length;
  @override
  String get name => 'zero-volume';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw RangeError('Zero source bounds.');
    }
    return Uint8List(count);
  }

  @override
  Future<void> close() async {}
}
