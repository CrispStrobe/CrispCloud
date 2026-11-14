// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_ext_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_disk_image_fixture.dart';
import 'support/archive_ext_disk_fixture.dart';
import 'support/archive_ext_reference_data.dart';
import 'support/archive_ext_web_acceptance.dart';

DiskImageFixture _collisionGpt() {
  final source = extGptFixture(volumes: [ExtReferenceSource('ext2')]);
  final gpt = source.gpt!;
  // In a 512-byte GPT, first-entry name unit zero lives at disk byte1080,
  // exactly the offset used by ext's two-byte superblock magic.
  gpt.primaryTable.setRange(56, 58, [0x53, 0xef]);
  gpt.backupTable.setAll(0, gpt.primaryTable);
  gpt.updateTableCrc();
  gpt.updateTableCrc(backup: true);
  return source;
}

Uint8List _extWithBootRecords() {
  final bytes = extReferenceBytes('ext2');
  bytes.setRange(510, 512, [0x55, 0xaa]);
  bytes[450] = 0x83;
  final data = ByteData.sublistView(bytes);
  data.setUint32(454, 128, Endian.little);
  data.setUint32(458, 512, Endian.little);
  return bytes;
}

void main() {
  test('a valid GPT partition name containing ext magic still browses its Linux filesystem', () async {
    final source = _collisionGpt();
    expect(await hasExtVolumeRecognition(source), isTrue);
    expect(await hasDiskImagePartitionRecognition(source), isTrue);
    final archive = await openDiskImageArchive(
      source,
      maxMemberBytes: 64 * 1024 * 1024,
    );
    expect(archive.formatName, 'disk-image');
    final member = archive.members.singleWhere(
      (m) => m.name == 'partition-001/files/hello.txt',
    );
    expect(
      utf8.decode(await archive.readMember(member)),
      'Hello from ext filesystem\n',
    );
    await archive.close();
    expect(source.closeCount, 1);
  });

  test('shared viewer gives explicit GPT headers priority over a coincidental ext marker and suffix', () async {
    final source = _collisionGpt();
    final archive = await openViewerArchiveSource(
      source,
      name: 'coincidence.ext4',
    );
    expect(archive.formatName, 'disk-image');
    expect(
      archive.members.any((m) => m.name == 'partition-001/files/hello.txt'),
      isTrue,
    );
    await archive.close();
    expect(source.closeCount, 1);
  });

  test('corrupt recognized GPT with an ext-like name cannot fall through to a filesystem', () async {
    final source = _collisionGpt();
    source.gpt!.primaryHeader[16] ^= 1;
    await expectLater(
      openViewerArchiveSource(source, name: 'coincidence.ext4'),
      throwsA(
        isA<ArchiveViewException>()
            .having((e) => e.code, 'code', ArchiveMessageCode.corrupt)
            .having((e) => e.message, 'message', contains('disk image')),
      ),
    );
    expect(source.closeCount, 1);
  });

  test('standalone ext retains precedence over incidental MBR records in its boot area', () async {
    final source = ExtReviewSource(_extWithBootRecords());
    expect(await hasDiskImagePartitionRecognition(source), isFalse);
    final archive = await openViewerArchiveSource(source, name: 'linux.img');
    expect(archive.formatName, 'ext');
    final member = archive.members.singleWhere((m) => m.name == 'hello.txt');
    expect(
      utf8.decode(await archive.readMember(member)),
      'Hello from ext filesystem\n',
    );
    await archive.close();
    expect(source.closeCount, 1);
    final forced = ExtReviewSource(_extWithBootRecords());
    await expectLater(
      openDiskImageArchive(forced, maxMemberBytes: 64 * 1024 * 1024),
      throwsA(
        isA<ArchiveViewException>().having(
          (e) => e.code,
          'code',
          ArchiveMessageCode.unsupported,
        ),
      ),
    );
    expect(forced.closeCount, 1);
  });
}
