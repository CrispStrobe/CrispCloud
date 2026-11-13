import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_service.dart';
import 'package:crisp_cloud/services/archive_types.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

final _modified = DateTime.utc(2026, 11, 13, 1, 2, 3);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  for (final format in const [
    ArchiveCreationFormat.iso,
    ArchiveCreationFormat.rar,
    ArchiveCreationFormat.dmg,
  ]) {
    for (final large in [false, true]) {
      test(
        '${format.label} creates, edits and publishes ${large ? 'beyond 2 GiB' : 'a native data container'}',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'crisp-native-container-',
          );
          addTearDown(() => temp.delete(recursive: true));
          final root = await temp.resolveSymbolicLinks();
          final input = File(p.join(root, 'payload.bin'));
          final size = large ? 2 * 1024 * 1024 * 1024 + 4097 : 1024 * 1024 + 17;
          final handle = await input.open(mode: FileMode.writeOnly);
          try {
            if (large && format == ArchiveCreationFormat.dmg) {
              // UDIF represents all-zero blocks without payload even in Store
              // mode. Nonzero blocks prove the outer DMG also exceeds 2 GiB.
              final block = Uint8List(256 * 1024)
                ..fillRange(0, 256 * 1024, 0x51);
              for (
                var position = 0;
                position < size;
                position += block.length
              ) {
                final remaining = size - position;
                await handle.writeFrom(
                  block,
                  0,
                  remaining < block.length ? remaining : block.length,
                );
              }
              await handle.setPosition(0);
            } else {
              await handle.truncate(size);
            }
            await handle.writeFrom([0x11, 0x22, 0x33, 0x44]);
            await handle.setPosition(size - 4);
            await handle.writeFrom([0x55, 0x66, 0x77, 0x88]);
            await handle.flush();
          } finally {
            await handle.close();
          }
          await input.setLastModified(_modified);
          final expected = await sha256.bind(input.openRead()).single;
          final local = LocalOperationBackend(
            LocalFileService(),
            isCurrent: () => true,
          );
          expect(local.supportsStagedVerification, isTrue);
          final lastProgress =
              <ArchiveCreationPhase, ArchiveCreationProgress>{};
          final phaseUpdates = <ArchiveCreationPhase, int>{};
          ArchiveCreationPhase? bytePhase;
          void checkProgress(ArchiveCreationProgress value) {
            if (value.phase == ArchiveCreationPhase.scanning) return;
            final previous = lastProgress[value.phase];
            if (bytePhase != value.phase) {
              if (bytePhase != null) {
                final completed = lastProgress[bytePhase]!;
                expect(completed.completed, completed.total);
                expect(value.phase.index, greaterThan(bytePhase!.index));
              }
              expect(value.completed, 0);
              bytePhase = value.phase;
            }
            expect(value.total, greaterThan(0));
            expect(value.completed, inInclusiveRange(0, value.total));
            if (previous != null) {
              expect(value.total, previous.total);
              expect(value.completed, greaterThanOrEqualTo(previous.completed));
            }
            lastProgress[value.phase] = value;
            phaseUpdates.update(
              value.phase,
              (count) => count + 1,
              ifAbsent: () => 1,
            );
          }

          final created = await const ArchiveCreationService().create(
            source: local,
            destination: local,
            files: [(await local.stat(input.path))!],
            destinationDirectory: root,
            options: ArchiveCreationOptions(
              name: 'data${format.extension}',
              format: format,
              compression: ArchiveCreationCompression.none,
            ),
            onProgress: checkProgress,
          );
          expect(lastProgress.keys.toList(), [
            ArchiveCreationPhase.packing,
            ArchiveCreationPhase.verifying,
            ArchiveCreationPhase.saving,
          ]);
          for (final progress in lastProgress.values) {
            expect(progress.completed, progress.total);
            expect(phaseUpdates[progress.phase], greaterThan(2));
          }
          expect(
            lastProgress[ArchiveCreationPhase.packing]!.total,
            format == ArchiveCreationFormat.rar ? 2 * size : size,
          );
          final verificationBytes =
              lastProgress[ArchiveCreationPhase.verifying]!.total;
          if (format == ArchiveCreationFormat.dmg) {
            expect(verificationBytes, greaterThan(3 * size + created.bytes));
          } else {
            expect(
              verificationBytes,
              (format == ArchiveCreationFormat.iso ? 3 : 2) * size +
                  created.bytes,
            );
          }
          expect(
            lastProgress[ArchiveCreationPhase.saving]!.total,
            2 * created.bytes + size,
          );
          final container = File(created.path);
          expect(await container.length(), created.bytes);
          if (large) expect(created.bytes, greaterThan(2 * 1024 * 1024 * 1024));
          final original = await sha256.bind(container.openRead()).single;
          final journal = ArchivePublicationJournal(
            storage: MemoryFileCollectionStorage(),
          );
          final workspace = await ArchiveWorkspace.open(
            local,
            (await local.stat(created.path))!,
            journal: journal,
          );
          addTearDown(workspace.close);
          expect(workspace.supportsLargeFiles, isTrue);
          expect(workspace.canUpdate, isTrue, reason: workspace.updateSupport);
          expect(workspace.list().single.size, size);
          expect(workspace.list().single.updatedAt, _modified);
          if (large) {
            await expectLater(
              workspace.read('/payload.bin'),
              throwsA(isA<ArchiveViewException>()),
            );
          }

          workspace.createDirectory(
            '/folder',
            modified: _modified,
            mode: 0x1ed,
          );
          workspace.rename('/payload.bin', 'folder/renamed.bin');
          workspace.createDirectory('/empty', modified: _modified);
          workspace.replace('/removed.txt', Uint8List.fromList([7]));
          workspace.remove(['/removed.txt']);
          workspace.replace('/added.txt', Uint8List.fromList([9, 8, 7]));
          final review = await workspace.review();
          expect(review.spool?.isSealed, isTrue);
          expect(() => review.bytes, throwsStateError);
          await expectLater(
            workspace.save(reviewed: review, isCancelled: () => true),
            throwsA(isA<FileOperationCancelled>()),
          );
          expect(await sha256.bind(container.openRead()).single, original);
          final receipt = await workspace.save(reviewed: review);
          expect(receipt, isNotNull);
          expect(workspace.dirty, isFalse);
          await workspace.close();

          final reopened = await ArchiveWorkspace.open(
            local,
            (await local.stat(created.path))!,
            journal: journal,
          );
          addTearDown(reopened.close);
          expect(reopened.canUpdate, isTrue, reason: reopened.updateSupport);
          expect(reopened.list().map((item) => item.name).toSet(), {
            'folder',
            'empty',
            'added.txt',
          });
          expect(reopened.list('/folder').single.updatedAt, _modified);
          var decoded = 0;
          final actual = await sha256
              .bind(
                reopened.openRead('/folder/renamed.bin').map((chunk) {
                  expect(chunk.length, lessThanOrEqualTo(256 * 1024));
                  decoded += chunk.length;
                  return chunk;
                }),
              )
              .single;
          expect(decoded, size);
          expect(actual, expected);
          expect(await reopened.read('/added.txt'), [9, 8, 7]);
          expect(await sha256.bind(input.openRead()).single, expected);

          // Normal cases also exercise the shared extraction entry point.
          // Large cases already stream-check every byte after publication.
          if (!large) {
            final target = p.join(root, 'extracted');
            final extracted = await ArchiveService.extractArchive(
              created.path,
              target,
              selectedPaths: {'folder/'},
            );
            expect(extracted, [p.join(target, 'folder', 'renamed.bin')]);
            expect(
              await sha256.bind(File(extracted.single).openRead()).single,
              expected,
            );
          }
          expect(
            await Directory(root)
                .list()
                .map((item) => p.basename(item.path))
                .toList(),
            unorderedEquals([
              'payload.bin',
              'data${format.extension}',
              if (!large) 'extracted',
            ]),
          );
        },
        skip:
            !supportsNativeExclusiveRename ||
            large &&
                Platform.environment['CRISP_RUN_LARGE_ARCHIVE_TESTS'] != '1',
        timeout: Timeout(Duration(minutes: large ? 35 : 5)),
      );
    }
  }
}
