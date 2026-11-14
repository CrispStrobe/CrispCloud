// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/archive_fat_reader.dart';
import 'package:crisp_cloud/services/archive_types.dart';

import 'support/archive_fat_reference_data.dart';
import 'support/archive_fat_web_acceptance.dart';

void main() {
  test(
    'external FAT references and derived partition wrappers pass acceptance',
    () async {
      final result = await runFatReferenceAcceptance();
      expect(result['groups'], hasLength(15));
      expect(result['independent_reference_images'], hasLength(4));
      expect(result['derived_partition_wrappers'], hasLength(4));
      expect(result['derived_udif_wrappers'], hasLength(3));
    },
  );

  test('external file contents stay lazy and provider failures keep their identity', () async {
    final bytes = fatReferenceBytes('fat12');
    // Locate an independently written SFN and compute its payload offset from
    // the externally recorded FAT12 geometry; no implementation helper is used.
    final entry = List<int>.generate(16, (index) => 9728 + index * 32)
        .singleWhere(
          (at) =>
              ascii.decode(bytes.sublist(at, at + 11), allowInvalid: true) ==
              'HELLO   TXT',
        );
    final first = ByteData.sublistView(bytes)
        .getUint16(entry + 26, Endian.little);
    final payloadAt = 26112 + (first - 2) * 512;
    final failure = StateError('Payload range unavailable.');
    final source = FatReviewSource(bytes)
      ..failure = failure
      ..failWhen = (at, count) => at < payloadAt + 38 && at + count > payloadAt;
    final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
    final hello = archive.members.singleWhere(
      (member) => member.name == 'HELLO.TXT',
    );
    expect(archive.members, hasLength(11));
    await expectLater(archive.readMember(hello), throwsA(same(failure)));
    expect(source.closeCount, 0);
    await archive.close();
    expect(source.closeCount, 1);
  });

  test('metadata decisions do not change when a borrowed allocation page changes later', () async {
    final source = FatReviewSource(
      fatReferenceBytes('fat12'),
      borrowedReads: true,
    );
    final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
    final member = archive.members.singleWhere(
      (row) => row.name == 'fragmented.bin',
    );
    // This is a derived mutation after open, not an external reference image.
    // Both FATs become unusable; the already validated immutable extents remain.
    source.bytes.fillRange(512, 9728, 0);
    expect(
      sha256.convert(await archive.readMember(member)).toString(),
      fatReferencePayloads[member.name],
    );
    await archive.close();
  });

  test('configured member ceiling rejects buffered and streamed reads before payload I/O', () async {
    final source = FatReferenceSource('fat16');
    final archive = await openFatArchive(source, maxMemberBytes: 1024);
    final member = archive.members.singleWhere(
      (row) => row.name == 'nested/payload.bin',
    );
    final before = source.rangesRead.length;
    await expectLater(
      archive.readMember(member),
      throwsA(
        isA<ArchiveViewException>().having(
          (e) => e.code,
          'code',
          ArchiveMessageCode.archiveLimit,
        ),
      ),
    );
    await expectLater(
      archive.openMember(member).toList(),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(source.rangesRead.length, before);
    await archive.close();
  });

  test(
    'FAT type derives from data clusters instead of the informational label',
    () async {
      final bytes = fatReferenceBytes('fat12');
      bytes.setRange(54, 62, ascii.encode('FAT32   '));
      final source = FatReviewSource(bytes);
      final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
      expect(archive.notices.any((text) => text.startsWith('FAT12;')), isTrue);
      expect(
        sha256
            .convert(
              await archive.readMember(
                archive.members.singleWhere((m) => m.name == 'HELLO.TXT'),
              ),
            )
            .toString(),
        fatReferencePayloads['HELLO.TXT'],
      );
      await archive.close();
    },
  );

  test('bytes after the declared volume are reported and never used', () async {
    final image = fatReferenceBytes('fat12');
    final bytes = Uint8List(image.length + 4096)..setAll(0, image);
    bytes.fillRange(image.length, bytes.length, 0xa5);
    final source = FatReviewSource(bytes)
      ..failure = StateError('Reader crossed the BPB volume boundary.')
      ..failWhen = (at, count) => at + count > image.length;
    final archive = await openFatArchive(source, maxMemberBytes: 1024 * 1024);
    expect(archive.members, hasLength(11));
    expect(
      archive.notices.any((text) => text.contains('after the BPB-declared')),
      isTrue,
    );
    await archive.close();
  });

  final openings = <String, Future<ViewerArchive> Function(FatReviewSource)>{
    'entry count': (source) =>
        openFatArchive(source, maxMemberBytes: 1024 * 1024, maxEntries: 2),
    'metadata bytes': (source) => openFatArchive(
      source,
      maxMemberBytes: 1024 * 1024,
      maxMetadataBytes: 512,
    ),
    'directory bytes': (source) => openFatArchive(
      source,
      maxMemberBytes: 1024 * 1024,
      maxDirectoryBytes: 512,
    ),
    'cluster traversal': (source) =>
        openFatArchive(source, maxMemberBytes: 1024 * 1024, maxClusters: 3),
    'decoded names': (source) =>
        openFatArchive(source, maxMemberBytes: 1024 * 1024, maxNameBytes: 5),
    'retained paths': (source) => openFatArchive(
      source,
      maxMemberBytes: 1024 * 1024,
      maxRetainedPathBytes: 5,
    ),
  };
  for (final entry in openings.entries) {
    final label = entry.key;
    test(
      'external reference respects reduced $label budget and closes once',
      () async {
        final source = FatReviewSource(fatReferenceBytes('fat12'));
        await expectLater(
          entry.value(source),
          throwsA(
            isA<ArchiveViewException>().having(
              (error) => error.code,
              'resource code',
              isIn([
                ArchiveMessageCode.archiveLimit,
                ArchiveMessageCode.entryLimit,
              ]),
            ),
          ),
        );
        expect(source.closeCount, 1);
      },
    );
  }

  test(
    'short provider reads reject the reference and release ownership',
    () async {
      final source = FatReviewSource(fatReferenceBytes('fat12'))
        ..shortNextRead = true;
      await expectLater(
        openFatArchive(source, maxMemberBytes: 1024 * 1024),
        throwsA(
          isA<ArchiveViewException>().having(
            (e) => e.code,
            'code',
            ArchiveMessageCode.corrupt,
          ),
        ),
      );
      expect(source.closeCount, 1);
    },
  );

  test('invalid API limits close the transferred source', () async {
    final source = FatReviewSource(fatReferenceBytes('fat12'));
    await expectLater(
      openFatArchive(source, maxMemberBytes: 0),
      throwsArgumentError,
    );
    expect(source.ranges, isEmpty);
    expect(source.closeCount, 1);
  });
}
