// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_ntfs_disk_fixture.dart';
import 'support/archive_ntfs_reference_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  for (final partitioned in [false, true]) {
    test(
      '${partitioned ? 'GPT' : 'ntfs'} native workspace streams an image above 64 MiB without write authority',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'ntfs-workspace-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File(
          '${directory.path}/volume.${partitioned ? 'img' : 'ntfs'}',
        );
        const imageBytes = kArchiveReadLimit + 64 * 1024;
        final volume = ntfsReferenceBytes('ntfs31');
        final blocks = <(int, Uint8List)>[];
        if (partitioned) {
          final fixture = ntfsGptFixture(
            volumes: [NtfsReferenceSource('ntfs31')],
            totalBytes: imageBytes,
          );
          final gpt = fixture.gpt!;
          blocks.addAll([
            (0, gpt.mbr),
            (gpt.sectorBytes, gpt.primaryHeader),
            (gpt.primaryTableOffset, gpt.primaryTable),
            (fixture.volumes.single.$1, volume),
            (gpt.backupTableOffset, gpt.backupTable),
            (imageBytes - gpt.sectorBytes, gpt.backupHeader),
          ]);
        } else {
          blocks.add((0, volume));
        }
        final handle = await file.open(mode: FileMode.write);
        try {
          for (final (offset, bytes) in blocks) {
            await handle.setPosition(offset);
            await handle.writeFrom(bytes);
          }
          await handle.truncate(imageBytes);
        } finally {
          await handle.close();
        }
        final before = await sha256.bind(file.openRead()).single;
        final local = LocalOperationBackend(
          LocalFileService(),
          isCurrent: () => true,
        );
        final workspace = await ArchiveWorkspace.open(
          local,
          (await local.stat(file.path))!,
          journal: ArchivePublicationJournal(
            storage: MemoryFileCollectionStorage(),
          ),
        );
        addTearDown(workspace.close);
        final initialRevision = workspace.revision;
        expect(workspace.format, partitioned ? 'disk-image' : 'ntfs');
        expect(workspace.supportsLargeFiles, isTrue);
        expect(workspace.maxMemberBytes, kArchiveStreamingLimit);
        expect(
          workspace.endpointCapabilities.format,
          ArchiveEndpointFormat.readOnly,
        );
        expect(workspace.canUpdate, isFalse);
        expect(workspace.canRemoveMembers, isFalse);
        expect(workspace.canMoveMembers, isFalse);
        expect(workspace.canSynchronizeDirectory, isFalse);
        final prefix = partitioned ? '/partition-001/files' : '';
        expect(
          workspace
              .list(prefix.isEmpty ? '/' : prefix)
              .map((entry) => entry.name),
          isNot(contains('hello.txt:notes-雪')),
        );
        await expectLater(
          workspace.read('$prefix/hello.txt:notes-雪'),
          throwsStateError,
        );
        await expectLater(
          workspace.openRead('$prefix/hello.txt:notes-雪:\$DATA').toList(),
          throwsStateError,
        );
        expect(
          sha256
              .convert(await workspace.read('$prefix/nested/café-雪.txt'))
              .toString(),
          ntfsReferencePayloads['nested/café-雪.txt'],
        );
        final destination = File('${directory.path}/extracted.bin');
        await workspace
            .openRead('$prefix/sparse.bin')
            .pipe(destination.openWrite());
        expect(
          (await sha256.bind(destination.openRead()).single).toString(),
          ntfsReferencePayloads['sparse.bin'],
        );
        expect(
          () => workspace.rename('$prefix/hello.txt', 'changed.txt'),
          throwsUnsupportedError,
        );
        expect(
          () => workspace.remove(['$prefix/hello.txt']),
          throwsUnsupportedError,
        );
        expect(
          () => workspace.replace('$prefix/new.txt', Uint8List.fromList([1])),
          throwsUnsupportedError,
        );
        expect(workspace.dirty, isFalse);
        expect(workspace.revision, initialRevision);
        await workspace.close();
        expect(await file.length(), imageBytes);
        expect(await sha256.bind(file.openRead()).single, before);
      },
    );
  }
}
