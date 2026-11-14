// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_endpoint_policy.dart';
import 'package:crisp_cloud/services/archive_format_registry.dart';
import 'package:crisp_cloud/services/archive_fat_reader.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_viewer_streaming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_disk_image_fixture.dart';
import 'support/archive_fat_reference_data.dart';
import 'support/archive_udf_reference_data.dart';
import 'support/dmg_fixture.dart';

void main() {
  test(
    'FAT and raw-image names expose only browse and extraction capabilities',
    () {
      for (final suffix in [
        'fat',
        'fat12',
        'fat16',
        'fat32',
        'img',
        'ima',
        'dd',
        'raw',
      ]) {
        final name = 'volume.${suffix.toUpperCase()}';
        final capability = archiveFormatForName(name)!;
        expect(capability.canCreate, isFalse, reason: name);
        expect(capability.canModify, isFalse, reason: name);
        expect(ArchiveService.isArchive(name), isTrue, reason: name);
        expect(isStreamedArchiveViewerName(name), isTrue, reason: name);
        expect(matchesStreamedArchiveViewerSignature(name, const []), isTrue);
      }
    },
  );

  for (final name in [
    'volume.fat',
    'volume.img',
    'misleading.zip',
    'misleading.iso',
  ]) {
    test(
      'FAT recognition and read-only policy survive the name $name',
      () async {
        final bytes = fatReferenceBytes('fat12');
        final archive = await openViewerArchive(bytes, name: name);
        expect(archive.formatName, 'fat');
        for (final payload in fatReferencePayloads.entries) {
          final member = archive.members.singleWhere(
            (m) => m.name == payload.key,
          );
          expect(
            sha256.convert(await archive.readMember(member)).toString(),
            payload.value,
          );
        }
        final policy = await ArchiveEndpointPolicy.inspect(
          bytes,
          name,
          archive,
          null,
        );
        expect(policy.format, ArchiveEndpointFormat.readOnly);
        expect(policy.reason, contains('FAT'));
        await archive.close();
      },
    );
  }

  test('native FAT viewing retains positional reads and the larger stream allowance', () async {
    final source = FatReferenceSource('fat32');
    final opened = await openStreamedArchiveSource(source, name: 'volume.img');
    expect(opened.archive.formatName, 'fat');
    expect(opened.policy.format, ArchiveEndpointFormat.readOnly);
    expect(opened.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
    expect(source.requestedBytes, lessThan(128 * 1024));
    final member = opened.archive.members.singleWhere(
      (m) => m.name == 'fragmented.bin',
    );
    final data = BytesBuilder();
    await for (final bytes in opened.archive.openMember(
      member,
      chunkSize: 257,
    )) {
      data.add(bytes);
    }
    expect(
      sha256.convert(data.takeBytes()).toString(),
      fatReferencePayloads[member.name],
    );
    expect(source.largestRequest, lessThanOrEqualTo(64 * 1024));
    await opened.archive.close();
    await opened.archive.close();
    expect(source.closeCount, 1);
  });

  test(
    'explicit 4096-byte MBR geometry reaches the archive dispatcher',
    () async {
      final source = DiskImageFixture.mbr(
        volumes: [FatReferenceSource('fat16-sector4096')],
        sectorBytes: 4096,
        types: [0x06],
      );
      final opened = await openStreamedArchiveSource(
        source,
        name: 'disk.bin',
        diskImageSectorBytes: 4096,
      );
      expect(opened.archive.formatName, 'disk-image');
      expect(opened.policy.format, ArchiveEndpointFormat.readOnly);
      final member = opened.archive.members.singleWhere(
        (m) => m.name == 'partition-001/files/café-雪.txt',
      );
      expect(
        sha256.convert(await opened.archive.readMember(member)).toString(),
        fatReferencePayloads['café-雪.txt'],
      );
      expect(source.reads.every((r) => r.$2 <= 64 * 1024), isTrue);
      await opened.archive.close();
      expect(source.closeCount, 1);
    },
  );

  test('GPT image opening through the shared dispatcher preserves raw partition access', () async {
    final source = DiskImageFixture.gpt(volumes: [FatReferenceSource('fat12')]);
    final archive = await openViewerArchiveSource(source, name: 'disk.dd');
    expect(archive.formatName, 'disk-image');
    final raw = archive.members.singleWhere(
      (m) => m.name == 'partition-001/raw.img',
    );
    expect(
      sha256.convert(await archive.readMember(raw)).toString(),
      fatReferenceImages['fat12']!.sha256,
    );
    expect(
      archive.members.any((m) => m.name == 'partition-001/files/emoji-😀.txt'),
      isTrue,
    );
    await archive.close();
    expect(source.closeCount, 1);
  });

  test(
    'a ZIP named img keeps its codec limits and cannot gain rewrite authority',
    () async {
      final zip = Uint8List.fromList(
        ar.ZipEncoder().encode(
          ar.Archive()..addFile(ar.ArchiveFile.bytes('note.txt', [1, 2, 3])),
        ),
      );
      final opened = await openStreamedArchiveSource(
        koni.MemoryByteSource(zip),
        name: 'not.img',
      );
      expect(opened.archive.formatName, 'zip');
      expect(opened.archive.maxStreamingMemberBytes, kArchiveReadLimit);
      expect(opened.policy.format, ArchiveEndpointFormat.readOnly);
      expect(await opened.archive.readMember(opened.archive.members.single), [
        1,
        2,
        3,
      ]);
      await opened.archive.close();
    },
  );

  test(
    'a UDF image keeps its filesystem namespace with a raw-image suffix',
    () async {
      final archive = await openViewerArchive(
        udfReferenceBytes('mastered-bridge'),
        name: 'disc.img',
      );
      expect(archive.formatName, 'udf');
      expect(archive.members.any((m) => m.name == 'café-雪.txt'), isTrue);
      await archive.close();
    },
  );

  test('a FAT filesystem inside LZFSE UDIF exposes files and the original raw volume', () async {
    final image = fatReferenceBytes('fat12');
    final dmg = DmgFixture(image, method: 0x80000007, chunkBytes: 32768);
    final archive = await openViewerArchive(dmg.bytes, name: 'volume.dmg');
    expect(archive.formatName, 'dmg');
    final raw = archive.members.singleWhere(
      (m) => m.name.startsWith('partitions/'),
    );
    expect(raw.name, endsWith('.fat'));
    expect(await archive.readMember(raw), image);
    for (final payload in fatReferencePayloads.entries) {
      final member = archive.members.singleWhere(
        (m) =>
            m.name.startsWith('files/') && m.name.endsWith('/${payload.key}'),
      );
      expect(
        sha256.convert(await archive.readMember(member)).toString(),
        payload.value,
      );
    }
    expect(
      archive.notices.any((n) => n.contains('Read-only FAT filesystem')),
      isTrue,
    );
    final policy = await ArchiveEndpointPolicy.inspect(
      dmg.bytes,
      'volume.dmg',
      archive,
      null,
    );
    expect(policy.format, ArchiveEndpointFormat.readOnly);
    await archive.close();
  });

  test(
    'DMG retains dirty FAT notices while preserving exact raw partition bytes',
    () async {
      final image = fatReferenceBytes('fat16');
      final data = ByteData.sublistView(image);
      final sectorBytes = data.getUint16(11, Endian.little);
      final reserved = data.getUint16(14, Endian.little);
      final fatSectors = data.getUint16(22, Endian.little);
      for (var table = 0; table < image[16]; table++) {
        final state = (reserved + table * fatSectors) * sectorBytes + 2;
        data.setUint16(
          state,
          data.getUint16(state, Endian.little) & 0x7fff,
          Endian.little,
        );
      }
      final dmg = DmgFixture(image, method: 0x80000005, chunkBytes: 65536);
      final archive = await openViewerArchive(dmg.bytes, name: 'dirty.dmg');
      expect(
        archive.notices.where((n) => n.contains('marked dirty')),
        hasLength(1),
      );
      final raw = archive.members.singleWhere(
        (m) => m.name.startsWith('partitions/'),
      );
      expect(await archive.readMember(raw), image);
      expect(archive.members.any((m) => m.name.endsWith('/HELLO.TXT')), isTrue);
      await archive.close();
    },
  );

  test('corrupt FAT inside DMG remains raw and cannot expose partial filesystem entries', () async {
    final image = fatReferenceBytes('fat12');
    // An explicit FAT marker still routes the malformed BPB to the FAT reader.
    image[13] = 3;
    final dmg = DmgFixture(image, method: 0x80000005, chunkBytes: 32768);
    final archive = await openViewerArchive(dmg.bytes, name: 'corrupt.dmg');
    expect(archive.members, hasLength(1));
    expect(archive.members.single.name, endsWith('.fat'));
    expect(await archive.readMember(archive.members.single), image);
    expect(
      archive.notices.any((n) => n.contains('filesystem browsing unavailable')),
      isTrue,
    );
    await archive.close();
  });

  test(
    'failed FAT and partition opens close the transferred source exactly once',
    () async {
      final bytes = fatReferenceBytes('fat12')..[13] = 3;
      final source = _ObservedSource(bytes);
      await expectLater(
        openViewerArchiveSource(source, name: 'corrupt.fat'),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closeCount, 1);
      final disk = DiskImageFixture.gpt(volumes: [FatReferenceSource('fat12')]);
      disk.gpt!.backupHeader[16] ^= 1;
      await expectLater(
        openViewerArchiveSource(disk, name: 'corrupt.img'),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(disk.closeCount, 1);
    },
  );

  test(
    'source failure inside a DMG FAT child cannot become a raw-only success',
    () async {
      final image = fatReferenceBytes('fat12');
      final dmg = DmgFixture(image, method: 1, chunkBytes: 32768);
      const failure = ArchiveViewException('The selected source was revoked.');
      // FAT table reads follow the outer trailer and the boot-sector probe.
      final source = _ObservedSource(dmg.bytes)
        ..failure = failure
        ..failWhen = (offset, count) => offset == 512 && count > 512;
      await expectLater(
        openViewerArchiveSource(source, name: 'revoked.dmg'),
        throwsA(same(failure)),
      );
      expect(source.closeCount, 1);
    },
  );

  test('DMG FAT cancellation is propagated rather than reported as raw-only browsing', () async {
    final image = fatReferenceBytes('fat12');
    final dmg = DmgFixture(image, method: 1, chunkBytes: 32768);
    var cancelled = false;
    final source = _ObservedSource(dmg.bytes)
      ..onRead = (offset, count) {
        if (offset == 512 && count > 512) cancelled = true;
      };
    await expectLater(
      openViewerArchiveSource(
        source,
        name: 'cancelled.dmg',
        isCancelled: () => cancelled,
      ),
      throwsA(isA<ArchiveFatCancelledException>()),
    );
    expect(source.closeCount, 1);
  });
}

class _ObservedSource implements koni.ByteSource {
  _ObservedSource(this.bytes);
  final Uint8List bytes;
  int closeCount = 0;
  Object? failure;
  bool Function(int offset, int count)? failWhen;
  void Function(int offset, int count)? onRead;
  @override
  int get length => bytes.length;
  @override
  String get name => 'observed-image';
  @override
  Future<Uint8List> read(int offset, int count) async {
    onRead?.call(offset, count);
    if (failure != null && (failWhen?.call(offset, count) ?? true))
      throw failure!;
    return Uint8List.sublistView(bytes, offset, offset + count);
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}
