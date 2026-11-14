// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/archive_ext_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'support/archive_ext_reference_data.dart';
import 'support/archive_ext_web_acceptance.dart';

void main() {
  test('external ext2/ext3/ext4 payloads and corruption controls pass portable acceptance', () async {
    final result = await runExtReferenceAcceptance();
    expect(result['independent_reference_images'], hasLength(5));
    expect(result['groups'], hasLength(16));
    expect(result['derived_partition_wrappers'], hasLength(3));
    expect(result['all_payload_and_complete_image_hashes_match'], isTrue);
  });

  test('file content stays lazy and configured member ceilings precede payload reads', () async {
    final source = ExtReferenceSource('ext3');
    final archive = await openExtArchive(source, maxMemberBytes: 1024);
    final member = archive.members.singleWhere((m) => m.name == 'indirect.bin');
    final reads = source.rangesRead.length;
    await expectLater(
      archive.readMember(member),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      archive.openMember(member).toList(),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.rangesRead, hasLength(reads));
    await archive.close();
    expect(source.closeCount, 1);
  });

  test('validated classic allocation decisions survive mutation of borrowed metadata buffers', () async {
    final source = ExtReviewSource(
      extReferenceBytes('ext2'),
      borrowedReads: true,
    );
    final archive = await openExtArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
    );
    final member = archive.members.singleWhere((m) => m.name == 'indirect.bin');
    final data = ByteData.sublistView(source.bytes);
    final inodeBytes = data.getUint16(1024 + 88, Endian.little);
    final perGroup = data.getUint32(1024 + 40, Endian.little);
    final groups =
        (data.getUint32(1024, Endian.little) + perGroup - 1) ~/ perGroup;
    // Only inode tables are damaged. Original payload blocks remain untouched;
    // extraction must keep using the extents validated during opening.
    for (var group = 0; group < groups; group++) {
      final block = data.getUint32(2048 + group * 32 + 8, Endian.little);
      source.bytes.fillRange(
        block * 1024,
        block * 1024 + perGroup * inodeBytes,
        0,
      );
    }
    expect(
      sha256.convert(await archive.readMember(member)).toString(),
      extReferencePayloads['indirect.bin'],
    );
    await archive.close();
  });

  final limits = <String, Future<ViewerArchive> Function(ExtReferenceSource)>{
    'entry count': (source) =>
        openExtArchive(source, maxMemberBytes: 2 * 1024 * 1024, maxEntries: 2),
    'metadata bytes': (source) => openExtArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
      maxMetadataBytes: 512,
    ),
    'directory bytes': (source) => openExtArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
      maxDirectoryBytes: 512,
    ),
    'retained paths': (source) => openExtArchive(
      source,
      maxMemberBytes: 2 * 1024 * 1024,
      maxRetainedPathBytes: 16,
    ),
    'traversed blocks': (source) =>
        openExtArchive(source, maxMemberBytes: 2 * 1024 * 1024, maxBlocks: 2),
    'extent count': (source) =>
        openExtArchive(source, maxMemberBytes: 2 * 1024 * 1024, maxExtents: 1),
  };
  for (final entry in limits.entries) {
    test('external images obey the configured ${entry.key} budget', () async {
      final source = ExtReferenceSource('ext4');
      await expectLater(
        entry.value(source),
        throwsA(isA<ArchiveViewException>()),
      );
      expect(source.closeCount, 1);
    });
  }
}
