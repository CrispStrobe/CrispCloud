// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_ext_reader.dart';
import 'package:crisp_cloud/services/archive_format_registry.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_viewer_streaming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_disk_image_fixture.dart';
import 'support/archive_ext_disk_fixture.dart';
import 'support/archive_ext_reference_data.dart';
import 'support/archive_fat_fixture.dart';

ViewerArchiveMember _member(ViewerArchive archive, String path) =>
    archive.members.singleWhere((entry) => entry.name == path);

void main() {
  test(
    'ext filename capabilities are read-only and retain native streaming',
    () {
      for (final suffix in ['ext', 'ext2', 'ext3', 'ext4']) {
        final name = 'linux.${suffix.toUpperCase()}';
        final capability = archiveFormatForName(name)!;
        expect(capability.id, 'ext');
        expect(capability.canCreate, isFalse);
        expect(capability.canModify, isFalse);
        expect(ArchiveService.isArchive(name), isTrue);
        expect(isStreamedArchiveViewerName(name), isTrue);
        expect(matchesStreamedArchiveViewerSignature(name, const []), isTrue);
      }
    },
  );

  for (final name in [
    'linux.ext2',
    'linux.img',
    'misnamed.zip',
    'misnamed.iso',
  ]) {
    test('ext content remains read-only when named $name', () async {
      final bytes = extReferenceBytes('ext2');
      final archive = await openViewerArchive(bytes, name: name);
      addTearDown(archive.close);
      expect(archive.formatName, 'ext');
      expect(
        utf8.decode(await archive.readMember(_member(archive, 'hello.txt'))),
        'Hello from ext filesystem\n',
      );
      expect(
        sha256
            .convert(await archive.readMember(_member(archive, 'sparse.bin')))
            .toString(),
        extReferencePayloads['sparse.bin'],
      );
      final policy = await ArchiveEndpointPolicy.inspect(
        bytes,
        name,
        archive,
        null,
      );
      expect(policy.format, ArchiveEndpointFormat.readOnly);
      expect(policy.reason, contains('ext'));
    });
  }

  test('native ext source retains streamed member allowance', () async {
    final source = _ObservedSource(ExtReferenceSource('ext2'));
    final result = await openStreamedArchiveSource(source, name: 'linux.ext2');
    expect(result.archive.formatName, 'ext');
    expect(result.policy.format, ArchiveEndpointFormat.readOnly);
    expect(result.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
    expect(source.requested, lessThan(source.length));
    final hash = await sha256
        .bind(
          result.archive.openMember(_member(result.archive, 'indirect.bin')),
        )
        .single;
    expect(hash.toString(), extReferencePayloads['indirect.bin']);
    await result.archive.close();
    expect(source.closeCount, 1);
  });

  for (final sector in [512, 4096]) {
    test('Linux GPT $sector preserves raw and ext file views', () async {
      final source = extGptFixture(
        volumes: [ExtReferenceSource('ext4')],
        sectorBytes: sector,
      );
      final archive = await openViewerArchiveSource(
        source,
        name: 'linux.img',
        diskImageSectorBytes: sector,
      );
      expect(archive.formatName, 'disk-image');
      final raw = _member(archive, 'partition-001/raw.img');
      expect(
        (await sha256.bind(archive.openMember(raw)).single).toString(),
        extReferenceImages['ext4']!.sha256,
      );
      for (final name in [
        'hello.txt',
        'nested/café-雪.txt',
        'sparse.bin',
        'hello-hardlink.txt',
      ]) {
        expect(
          sha256
              .convert(
                await archive.readMember(
                  _member(archive, 'partition-001/files/$name'),
                ),
              )
              .toString(),
          extReferencePayloads[name],
        );
      }
      expect(archive.notices.join(' '), contains('overlapping'));
      await archive.close();
      expect(source.closeCount, 1);
    });
  }

  test('MBR can expose FAT and Linux ext partitions together', () async {
    final fat = FatFixture();
    final source = DiskImageFixture.mbr(
      volumes: [fat.source(), ExtReferenceSource('ext2')],
      types: [0x01, 0x83],
    );
    final archive = await openDiskImageArchive(
      source,
      maxMemberBytes: kArchiveReadLimit,
    );
    expect(
      await archive.readMember(
        _member(archive, 'partition-001/files/HELLO.TXT'),
      ),
      fat.payload,
    );
    expect(
      utf8.decode(
        await archive.readMember(
          _member(archive, 'partition-002/files/hello.txt'),
        ),
      ),
      'Hello from ext filesystem\n',
    );
    await archive.close();
    expect(source.closeCount, 1);
  });

  test(
    'a Linux partition does not reinterpret FAT-looking bytes as FAT',
    () async {
      final source = DiskImageFixture.mbr(
        volumes: [FatFixture().source()],
        types: [0x83],
      );
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      expect(archive.members.map((entry) => entry.name), [
        'partition-001',
        'partition-001/raw.img',
      ]);
      expect(archive.notices.join(' '), contains('no supported ext volume'));
      final offset = source.volumes.single.$1;
      expect(
        source.reads.where(
          (read) =>
              read.$1 >= offset && read.$1 < offset + source.volumes.single.$2,
        ),
        [(offset + 1080, 2)],
      );
      await archive.close();
    },
  );

  test('an unknown partition type never probes an ext payload', () async {
    final source = DiskImageFixture.mbr(
      volumes: [ExtReferenceSource('ext2')],
      types: [0xab],
    );
    final archive = await openDiskImageArchive(
      source,
      maxMemberBytes: kArchiveReadLimit,
    );
    expect(archive.members.map((entry) => entry.name), [
      'partition-001',
      'partition-001/raw.img',
    ]);
    final offset = source.volumes.single.$1;
    expect(
      source.reads.any(
        (read) =>
            read.$1 >= offset && read.$1 < offset + source.volumes.single.$2,
      ),
      isFalse,
    );
    await archive.close();
  });

  test(
    'unsupported ext child retains raw access without a partial tree',
    () async {
      final bytes = extReferenceBytes('ext2');
      final data = ByteData.sublistView(bytes);
      data.setUint32(
        1024 + 0x60,
        data.getUint32(1024 + 0x60, Endian.little) | 0x80000000,
        Endian.little,
      );
      final source = DiskImageFixture.mbr(
        volumes: [koni.MemoryByteSource(bytes)],
        types: [0x83],
      );
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
      );
      expect(archive.members.map((entry) => entry.name), [
        'partition-001',
        'partition-001/raw.img',
      ]);
      expect(archive.notices.join(' '), contains('ext listing was refused'));
      expect(
        await archive.readMember(_member(archive, 'partition-001/raw.img')),
        bytes,
      );
      await archive.close();
    },
  );

  test(
    'recognized ext corruption never falls through to a filename reader',
    () async {
      final bytes = extReferenceBytes('ext2');
      ByteData.sublistView(bytes).setUint32(1024 + 0x18, 31, Endian.little);
      final source = _ObservedSource(koni.MemoryByteSource(bytes))
        ..failClose = true;
      await expectLater(
        openViewerArchiveSource(source, name: 'misnamed.zip'),
        throwsA(
          isA<ArchiveViewException>().having(
            (error) => error.message,
            'message',
            contains('ext'),
          ),
        ),
      );
      expect(source.closeCount, 1);
    },
  );

  for (final error in <Object>[
    StateError('source revoked'),
    const ArchiveViewException(
      'provider resembles unsupported format',
      code: ArchiveMessageCode.unsupported,
    ),
    const ArchiveViewException(
      'provider resembles corrupt format',
      code: ArchiveMessageCode.corrupt,
    ),
  ]) {
    test('ext partition retains source failure identity: $error', () async {
      final source = DiskImageFixture.mbr(
        volumes: [ExtReferenceSource('ext2')],
        types: [0x83],
      );
      final offset = source.volumes.single.$1;
      source.readError = error;
      source.failWhen = (at, count) => at >= offset;
      await expectLater(
        openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
        throwsA(same(error)),
      );
      expect(source.closeCount, 1);
    });
  }

  test('short ext partition probes fail the whole source', () async {
    final source = DiskImageFixture.mbr(
      volumes: [ExtReferenceSource('ext2')],
      types: [0x83],
    );
    final offset = source.volumes.single.$1;
    source.onRead = (at, count) {
      if (at >= offset) source.shortNextRead = true;
    };
    await expectLater(
      openDiskImageArchive(source, maxMemberBytes: kArchiveReadLimit),
      throwsA(
        isA<ArchiveViewException>().having(
          (error) => error.message,
          'message',
          contains('incomplete'),
        ),
      ),
    );
    expect(source.closeCount, 1);
  });

  test(
    'cancellation during an ext child does not return raw-only success',
    () async {
      var cancelled = false;
      final source = DiskImageFixture.mbr(
        volumes: [ExtReferenceSource('ext2')],
        types: [0x83],
      );
      final offset = source.volumes.single.$1;
      source.onRead = (at, count) {
        if (at >= offset) cancelled = true;
      };
      await expectLater(
        openDiskImageArchive(
          source,
          maxMemberBytes: kArchiveReadLimit,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ArchiveDiskImageCancelledException>()),
      );
      expect(source.closeCount, 1);
    },
  );

  test(
    'ext and FAT children cannot each spend a fresh disk allocation budget',
    () async {
      final extBudget = ArchiveExtTraversalBudget();
      final first = await openExtArchive(
        ExtReferenceSource('ext2'),
        maxMemberBytes: kArchiveReadLimit,
        traversalBudget: extBudget,
      );
      await first.close();
      final source = DiskImageFixture.mbr(
        volumes: [ExtReferenceSource('ext2'), FatFixture().source()],
        types: [0x83, 0x01],
      );
      final archive = await openDiskImageArchive(
        source,
        maxMemberBytes: kArchiveReadLimit,
        maxClusters: extBudget.blocksVisited,
      );
      expect(
        archive.members.any(
          (entry) => entry.name == 'partition-001/files/hello.txt',
        ),
        isTrue,
      );
      expect(
        archive.members.any(
          (entry) => entry.name.startsWith('partition-002/files'),
        ),
        isFalse,
      );
      expect(
        archive.members.any((entry) => entry.name == 'partition-002/raw.img'),
        isTrue,
      );
      expect(archive.notices.join(' '), contains('No listing budget remains'));
      await archive.close();
    },
  );
}

class _ObservedSource implements koni.ByteSource {
  _ObservedSource(this.inner);
  final koni.ByteSource inner;
  var closeCount = 0, requested = 0;
  var failClose = false;
  @override
  int get length => inner.length;
  @override
  String? get name => inner.name;
  @override
  Future<Uint8List> read(int offset, int count) {
    requested += count;
    return inner.read(offset, count);
  }

  @override
  Future<void> close() async {
    closeCount++;
    await inner.close();
    if (failClose) throw StateError('cleanup failed');
  }
}
