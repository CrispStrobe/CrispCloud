// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_disk_image_reader.dart';
import 'package:crisp_cloud/services/archive_iso_reader.dart';
import 'package:crisp_cloud/services/archive_ntfs_reader.dart';
import 'package:crisp_cloud/services/archive_streamed_reader.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_viewer_streaming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_iso_fixtures.dart';
import 'support/archive_ntfs_disk_fixture.dart';
import 'support/archive_ntfs_reference_data.dart';

class _Source implements koni.ByteSource {
  _Source(this.bytes);
  final Uint8List bytes;
  var closes = 0;
  @override
  int get length => bytes.length;
  @override
  String get name => 'recognition-source';
  @override
  Future<Uint8List> read(int offset, int count) async {
    if (closes != 0) throw StateError('Read after disposal.');
    return Uint8List.sublistView(bytes, offset, offset + count);
  }

  @override
  Future<void> close() async => closes++;
}

Matcher get _ntfsError => isA<ArchiveViewException>().having(
  (error) => error.message,
  'format-specific refusal',
  contains('NTFS'),
);

void main() {
  test('the native signature hint reads the complete OEM field', () {
    final prefix = Uint8List(11)..setRange(3, 11, ascii.encode('NTFS    '));
    expect(streamedArchiveViewerSignatureBytes, greaterThanOrEqualTo(11));
    expect(
      matchesStreamedArchiveViewerSignature('renamed.zip', prefix),
      isTrue,
    );
    expect(matchesStreamedArchiveViewerSignature('renamed.7z', prefix), isTrue);
    expect(
      matchesStreamedArchiveViewerSignature(
        'renamed.zip',
        prefix.sublist(0, 8),
      ),
      isFalse,
    );
    prefix[10] = 0;
    expect(
      matchesStreamedArchiveViewerSignature('renamed.zip', prefix),
      isFalse,
    );
  });

  test('NTFS recognition is non-owning and beats incidental MBR entries', () async {
    final bytes = ntfsReferenceBytes('ntfs31');
    bytes.fillRange(446, 510, 0);
    bytes[450] = 0x07;
    ByteData.sublistView(bytes)
      ..setUint32(454, 128, Endian.little)
      ..setUint32(458, 512, Endian.little);
    // Keep the independent fixture's backup boot copy consistent with the
    // synthetic boot-code-only mutation. Its filesystem structures are intact.
    bytes.setRange(bytes.length - 512, bytes.length, bytes, 0);
    final source = _Source(bytes);
    expect(await hasNtfsVolumeRecognition(source), isTrue);
    expect(await hasDiskImagePartitionRecognition(source), isFalse);
    expect(source.closes, 0);
    final archive = await openViewerArchiveSource(source, name: 'volume.img');
    expect(archive.formatName, 'ntfs');
    final hello = archive.members.singleWhere(
      (entry) => entry.name == 'hello.txt',
    );
    expect(
      utf8.decode(await archive.readMember(hello)),
      'Hello from NTFS filesystem\n',
    );
    await archive.close();
    expect(source.closes, 1);
    final forced = _Source(bytes);
    await expectLater(
      openDiskImageArchive(forced, maxMemberBytes: kArchiveReadLimit),
      throwsA(
        isA<ArchiveViewException>().having(
          (e) => e.code,
          'code',
          ArchiveMessageCode.unsupported,
        ),
      ),
    );
    expect(forced.closes, 1);
  });

  for (final name in [
    'renamed.zip',
    'renamed.7z',
    'renamed.iso',
    'renamed.udf',
    'renamed.dmg',
  ]) {
    test(
      'native NTFS content retains streaming and read-only policy as $name',
      () async {
        final source = _Source(ntfsReferenceBytes('ntfs31'));
        final opened = await openStreamedArchiveSource(source, name: name);
        expect(opened.archive.formatName, 'ntfs');
        expect(opened.policy.format, ArchiveEndpointFormat.readOnly);
        expect(opened.archive.maxStreamingMemberBytes, kArchiveStreamingLimit);
        final hello = opened.archive.members.singleWhere(
          (entry) => entry.name == 'hello.txt',
        );
        expect(
          utf8.decode(await opened.archive.readMember(hello)),
          'Hello from NTFS filesystem\n',
        );
        await opened.archive.close();
        expect(source.closes, 1);
      },
    );
  }

  for (final name in ['collision.iso', 'collision.udf']) {
    test(
      'recognized invalid NTFS cannot fall through to an intact ISO tree as $name',
      () async {
        final bytes = IsoFixture().bytes;
        bytes.setRange(3, 11, ascii.encode('NTFS    '));
        // An independent explicit ISO open confirms the optical namespace still
        // exists; content dispatch must nevertheless preserve the NTFS refusal.
        final iso = await openIsoArchive(
          koni.MemoryByteSource(bytes),
          maxMemberBytes: kArchiveReadLimit,
        );
        expect(iso.members.any((entry) => entry.name == 'HELLO.TXT'), isTrue);
        await iso.close();
        final buffered = _Source(bytes);
        await expectLater(
          openViewerArchiveSource(buffered, name: name),
          throwsA(_ntfsError),
        );
        expect(buffered.closes, 1);
        final streamed = _Source(bytes);
        await expectLater(
          openStreamedArchiveSource(streamed, name: name),
          throwsA(_ntfsError),
        );
        expect(streamed.closes, 1);
      },
    );
  }

  test(
    'GPT with an ext-like partition name still browses its NTFS child',
    () async {
      final source = ntfsGptFixture(volumes: [NtfsReferenceSource('ntfs31')]);
      final gpt = source.gpt!;
      gpt.primaryTable.setRange(56, 58, [0x53, 0xef]);
      gpt.backupTable.setAll(0, gpt.primaryTable);
      gpt.updateTableCrc();
      gpt.updateTableCrc(backup: true);
      final archive = await openViewerArchiveSource(
        source,
        name: 'renamed.ntfs',
      );
      expect(archive.formatName, 'disk-image');
      expect(
        archive.members.any(
          (entry) => entry.name == 'partition-001/files/hello.txt',
        ),
        isTrue,
      );
      await archive.close();
      expect(source.closeCount, 1);
    },
  );
}
