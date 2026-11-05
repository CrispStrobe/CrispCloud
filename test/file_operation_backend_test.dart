import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('operation listings bypass cached provider directory IDs', () async {
    final client = _FreshCloudClient()..put('/current.txt', 'fresh contents');
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final file = await backend.stat('/current.txt');
    expect(file?.size, 14);
    expect(client.freshReads, isNotEmpty);
    expect(client.cachedReads, isEmpty);
  });

  test(
    'a restored job reuses its exact opaque multipart staging target',
    () async {
      final original = _ResumableCloudClient('source')
        ..put('/source', 'complete original');
      final cloud = _ResumableCloudClient('destination')..interruptNext = true;
      final source = CloudOperationBackend(original, isCurrent: () => true);
      final target = CloudOperationBackend(cloud, isCurrent: () => true);
      final prepared = await const FileOperationService().prepare(
        source: source,
        destination: target,
        files: [(await source.stat('/source'))!],
        targetDirectory: '/target',
        options: const FileOperationOptions(),
      );
      final store = MemoryTransferJournalStorage();
      final journal = TransferJournal(store);
      await journal.create('multipart', prepared);
      await JournaledTransferRunner(journal)
          .execute('multipart', prepared, control: FileOperationControl());
      final initial = journal.job('multipart')!;
      final stage = initial.entries.single.recovery['stagedPath'] as String;
      expect(initial.entries.single.recovery['multipartUploadPending'], isTrue);
      expect(await target.stat(stage), isNull);
      expect(cloud.pending.keys, [stage]);
      final restored = TransferJournal(store);
    await restored.initialize();
      final preview = await const TransferRecoveryService().prepare(
        restored.job('multipart')!,
        source: source,
        destination: target,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      expect(preview.actions[0], contains('multipart'));
      expect(preview.plan.entries.single.recovery?['resumeUploadPath'], stage);
      await JournaledTransferRunner(restored)
          .execute('multipart', preview.plan, control: FileOperationControl());
      expect(cloud.uploads, [stage, stage]);
      expect(cloud.resumed, [stage]);
      expect(cloud.text('/target/source'), 'complete original');
      expect(restored.job('multipart')!.status, TransferJobStatus.completed);
      expect(cloud.pending, isEmpty);
    },
  );

  test(
    'restart does not silently reattach a previous multipart session',
    () async {
      final original = _ResumableCloudClient('source')
        ..put('/source', 'original');
      final cloud = _ResumableCloudClient('destination')..interruptNext = true;
      final source = CloudOperationBackend(original, isCurrent: () => true);
      final target = CloudOperationBackend(cloud, isCurrent: () => true);
      final prepared = await const FileOperationService().prepare(
        source: source,
        destination: target,
        files: [(await source.stat('/source'))!],
        targetDirectory: '/target',
        options: const FileOperationOptions(),
      );
      final journal = TransferJournal(MemoryTransferJournalStorage());
      await journal.create('multipart', prepared);
      await JournaledTransferRunner(journal)
          .execute('multipart', prepared, control: FileOperationControl());
      final preview = await const TransferRecoveryService().prepare(
        journal.job('multipart')!,
        source: source,
        destination: target,
        control: FileOperationControl(),
        mode: TransferRecoveryMode.restartIncomplete,
      );
      expect(preview.issues, isEmpty);
      expect(preview.plan.entries.single.recovery?['resumeUploadPath'], isNull);
      await JournaledTransferRunner(journal)
          .execute('multipart', preview.plan, control: FileOperationControl());
      expect(cloud.uploads.last, isNot(cloud.uploads.first));
      expect(cloud.resumed, isEmpty);
    },
  );

  test('expired, outside, occupied and malformed saved upload targets are rejected before reading source', () async {
    const name = '.crisp-transfer-01234567-89ab-4cde-8f01-23456789abcd.tmp';
    for (final path in [
      '/other/$name',
      '/target/../$name',
      '/target/plain.tmp',
      '/target/$name/child',
      '/target/$name',
    ]) {
      final cloud = _ResumableCloudClient('destination');
      final target = CloudOperationBackend(cloud, isCurrent: () => true);
      var read = false;
      Stream<List<int>> input() async* {
        read = true;
        yield [1];
      }

      if (path != '/target/$name') cloud.pending[path] = 1;
      await expectLater(
        target.writeConfiguredFile(
          '/target/final',
          input(),
          1,
          replace: false,
          resumeUploadPath: path,
        ),
        throwsStateError,
      );
      expect(read, isFalse);
      expect(cloud.uploads, isEmpty);
    }
    final cloud = _ResumableCloudClient('destination')
      ..pending['/target/$name'] = 1;
    cloud.put('/target/$name', 'external');
    final target = CloudOperationBackend(cloud, isCurrent: () => true);
    await expectLater(
      target.writeConfiguredFile(
        '/target/final',
        Stream.value([1]),
        1,
        replace: false,
        resumeUploadPath: '/target/$name',
      ),
      throwsStateError,
    );
    expect(cloud.text('/target/$name'), 'external');
    expect(cloud.uploads, isEmpty);
  });

  group(
    'native transfer storage',
    () {
      late Directory root;
      late LocalOperationBackend backend;
      late bool current;

      setUp(() async {
        root = await Directory.systemTemp.createTemp('crisp_transfer_test_');
        current = true;
        backend = LocalOperationBackend(
          LocalFileService(),
          isCurrent: () => current,
        );
      });

      tearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      Future<File> existingFile([String contents = 'original']) async {
        final file = File(p.join(root.path, 'a.txt'));
        await file.writeAsString(contents);
        return file;
      }

      Future<void> expectNoStages() async {
        final entries = await root.list().toList();
        expect(
          entries.where(
            (entry) => p.basename(entry.path).startsWith('.crisp-transfer-'),
          ),
          isEmpty,
        );
      }

      test('stat is unaffected by unrelated siblings disappearing during enumeration', () async {
        final requested = await existingFile();
        final outer = Zone.current;
        await IOOverrides.runZoned(
          () async {
            final result = await backend.stat(requested.path);
            expect(result?.size, 8);
            final files = await backend.list(root.path);
            expect(files.map((item) => item.name), ['a.txt']);
          },
          createDirectory: (path) => path == root.path
              ? _DirectoryWithDisappearedChild(root)
              : outer.run(() => Directory(path)),
        );
        expect(await backend.stat(p.join(root.path, 'missing.txt')), isNull);
      });

      test(
        'native stat propagates access errors suppressed by the type lookup',
        () async {
          final denied = p.join(root.path, 'denied.txt');
          final outer = Zone.current;
          await IOOverrides.runZoned(
            () async {
              await expectLater(
                backend.stat(denied),
                throwsA(
                  isA<FileSystemException>().having(
                    (error) => error.osError?.errorCode,
                    'permission error',
                    13,
                  ),
                ),
              );
            },
            createFile: (path) => path == denied
                ? _DeniedResolutionFile(path)
                : outer.run(() => File(path)),
          );
        },
      );

      test(
        'native stat retains dangling link identity without reading its target',
        () async {
          final link = Link(p.join(root.path, 'dangling'));
          await link.create(p.join(root.path, 'missing-target'));
          final item = await backend.stat(link.path);
          expect(item?.isSymlink, isTrue);
          expect(item?.symlinkTarget, p.join(root.path, 'missing-target'));
          expect(item?.size, isNull);
        },
      );

      test(
        'staged verification rejects corruption before replacing the original',
        () async {
          final file = await existingFile();
          final phases = <String>[];
          await expectLater(
            backend.writePreparedFile(
              file.path,
              Stream.value(utf8.encode('new')),
              3,
              replace: true,
              checkpoint: (state) async {
                phases.add(state['phase'] as String);
              },
              verifyStaged: (staged) async {
                expect(staged.path, isNot(file.path));
                expect(await File(staged.path!).readAsString(), 'new');
                expect(await file.readAsString(), 'original');
                throw StateError('Digest mismatch');
              },
            ),
            throwsStateError,
          );
          expect(await file.readAsString(), 'original');
          expect(phases, contains('staging'));
          expect(phases, isNot(contains('committed')));
          await expectNoStages();
        },
      );

      test(
        'allocation requires a size before consuming or staging the source',
        () async {
          final file = await existingFile();
          var consumed = false;
          Stream<List<int>> stream() async* {
            consumed = true;
            yield [1];
          }

          await expectLater(
            backend.writeConfiguredFile(
              file.path,
              stream(),
              null,
              replace: true,
              preallocate: true,
            ),
            throwsUnsupportedError,
          );
          expect(consumed, isFalse);
          expect(await file.readAsString(), 'original');
          await expectNoStages();
        },
      );

      test(
        'short allocated streams never commit their pre-sized zero tail',
        () async {
          final file = await existingFile();
          await expectLater(
            backend.writeConfiguredFile(
              file.path,
              Stream.value(utf8.encode('short')),
              1024,
              replace: true,
              preallocate: true,
            ),
            throwsA(anyOf(isA<StateError>(), isA<UnsupportedError>())),
          );
          expect(await file.readAsString(), 'original');
          await expectNoStages();
        },
      );

      test(
        'allocation happens before streaming and retains exact final bytes',
        () async {
          final file = await existingFile();
          String? stage;
          var read = false;
          Stream<List<int>> stream() async* {
            read = true;
            expect(await File(stage!).length(), 3);
            yield utf8.encode('new');
          }

          try {
            await backend.writeConfiguredFile(
              file.path,
              stream(),
              3,
              replace: true,
              preallocate: true,
              checkpoint: (state) async {
                if (state['phase'] == 'allocating') {
                  stage = state['stagedPath'] as String;
                }
              },
            );
          } on UnsupportedError {
            expect(read, isFalse);
            expect(await file.readAsString(), 'original');
            return;
          }
          expect(read, isTrue);
          expect(await file.readAsString(), 'new');
          await expectNoStages();
        },
      );

      test(
        'native ranges seek directly to the requested byte offset',
        () async {
          final file = await existingFile();
          final item = (await backend.stat(file.path))!;
          int? openedAt;
          final outer = Zone.current;
          await IOOverrides.runZoned(
            () async {
              final bytes = await backend
                  .readRange(item, 5)
                  .expand((chunk) => chunk)
                  .toList();
              expect(utf8.decode(bytes), 'nal');
            },
            createFile: (path) => path == file.path
                ? _ObservedRangeFile(file, (start) => openedAt = start)
                : outer.run(() => File(path)),
          );
          expect(openedAt, 5);
          await expectLater(
            backend.readRange(item, 100).toList(),
            throwsStateError,
          );
        },
      );

      test('native replacement preserves mode without copying old contents into the stage', () async {
        if (!supportsNativePermissions) return;
        final file = await existingFile();
        await setNativeFileMode(file.path, 0x1a0); // 0640
        await backend.writeFile(
          file.path,
          Stream.value(utf8.encode('new')),
          3,
          replace: true,
        );
        expect((await file.stat()).mode & 0x1ff, 0x1a0);
        final metadata = await backend.readMetadata(file.path);
        expect(metadata.mode, 0x1a0);
        await backend.writeMetadata(
          file.path,
          const TransferMetadata(mode: 0x1e0),
        ); // 0740
        expect((await file.stat()).mode & 0x1ff, 0x1e0);
      });

      test(
        'a rejected clone verifier retains the original destination',
        () async {
          final target = await existingFile();
          final source = await File(p.join(root.path, 'clone-source'))
              .writeAsString('replacement');
          var verified = false;
          try {
            final cloned = await backend.clonePreparedFile(
              (await backend.stat(source.path))!,
              target.path,
              replace: true,
              verifyStaged: (stage) async {
                verified = true;
                expect(await File(stage.path!).readAsString(), 'replacement');
                throw StateError('Verification refused');
              },
            );
            expect(cloned, isFalse);
            expect(verified, isFalse);
          } on StateError catch (error) {
            expect(error.message, 'Verification refused');
            expect(verified, isTrue);
          }
          expect(await target.readAsString(), 'original');
          expect(await source.readAsString(), 'replacement');
          await expectNoStages();
        },
      );

      test('a stream error never truncates an existing destination', () async {
        final file = await existingFile();
        Stream<List<int>> failingStream() async* {
          yield utf8.encode('part');
          throw StateError('source connection lost');
        }

        await expectLater(
          backend.writeFile(file.path, failingStream(), 20, replace: true),
          throwsStateError,
        );
        expect(await file.readAsString(), 'original');
        await expectNoStages();
      });

      test(
        'a length mismatch preserves the original and removes staging files',
        () async {
          final file = await existingFile();
          await expectLater(
            backend.writeFile(
              file.path,
              Stream.value(utf8.encode('short')),
              30,
              replace: true,
            ),
            throwsStateError,
          );
          expect(await file.readAsString(), 'original');
          await expectNoStages();
        },
      );

      test(
        'an account/source change during streaming prevents commit',
        () async {
          final file = await existingFile();
          Stream<List<int>> changedSource() async* {
            yield utf8.encode('replacement');
            current = false;
          }

          await expectLater(
            backend.writeFile(file.path, changedSource(), 11, replace: true),
            throwsStateError,
          );
          expect(await file.readAsString(), 'original');
          await expectNoStages();
        },
      );

      test('exclusive creation refuses existing files', () async {
        final file = await existingFile();
        await expectLater(
          backend.writeFile(
            file.path,
            Stream.value([1, 2, 3]),
            3,
            replace: false,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await file.readAsString(), 'original');
        await expectNoStages();
      });

      test(
        'complete staged replacement and new file creation write exact bytes',
        () async {
          final existing = await existingFile();
          final created = File(p.join(root.path, 'new.bin'));
          await backend.writeFile(
            existing.path,
            Stream.fromIterable([
              [0, 1],
              [2, 255],
            ]),
            4,
            replace: true,
          );
          await backend.writeFile(
            created.path,
            Stream.value([5, 6, 7]),
            3,
            replace: false,
          );
          expect(await existing.readAsBytes(), [0, 1, 2, 255]);
          expect(await created.readAsBytes(), [5, 6, 7]);
          await expectNoStages();
        },
      );

      test(
        'symbolic-link destinations and parents cannot redirect a write',
        () async {
          final outside = await Directory(p.join(root.path, 'outside'))
              .create();
          final protected = File(p.join(outside.path, 'keep.txt'));
          await protected.writeAsString('keep');
          final direct = Link(p.join(root.path, 'direct'));
          final parent = Link(p.join(root.path, 'via-link'));
          await direct.create(protected.path);
          await parent.create(outside.path);
          for (final path in [direct.path, p.join(parent.path, 'keep.txt')]) {
            await expectLater(
              backend.writeFile(
                path,
                Stream.value(utf8.encode('overwrite')),
                9,
                replace: true,
              ),
              throwsA(isA<FileSystemException>()),
            );
          }
          expect(await protected.readAsString(), 'keep');
          expect(
            await FileSystemEntity.type(direct.path, followLinks: false),
            FileSystemEntityType.link,
          );
        },
        skip: Platform.isWindows
            ? 'Creating native links requires Windows privileges.'
            : false,
      );

      test(
        'empty-directory cleanup never recursively deletes a populated folder',
        () async {
          final folder = await Directory(p.join(root.path, 'folder')).create();
          final child = File(p.join(folder.path, 'keep.txt'));
          await child.writeAsString('retain');
          await expectLater(
            backend.deleteEmptyDirectory(folder.path),
            throwsA(isA<FileSystemException>()),
          );
          expect(await child.readAsString(), 'retain');
        },
      );

      test(
        'verified native move retains bytes and modification time',
        () async {
          final from = await Directory(p.join(root.path, 'from')).create();
          final to = await Directory(p.join(root.path, 'to')).create();
          final original = File(p.join(from.path, 'a.txt'));
          await original.writeAsString('native transfer payload');
          final modified = DateTime.utc(2024, 3, 4, 5, 6, 7);
          await original.setLastModified(modified);
          final sourceItem = (await backend.stat(original.path))!;
          const service = FileOperationService();
          final plan = await service.prepare(
            files: [sourceItem],
            source: backend,
            destination: backend,
            targetDirectory: to.path,
            options: const FileOperationOptions(
              kind: FileOperationKind.move,
              verifyContents: true,
              preserveModified: true,
            ),
          );
          expect(plan.errors, isEmpty);
          await service.execute(plan, control: FileOperationControl());
          expect(plan.entries.single.outcome, FileOperationOutcome.moved);
          expect(await original.exists(), isFalse);
          final written = File(p.join(to.path, 'a.txt'));
          expect(await written.readAsString(), 'native transfer payload');
          expect(
            (await written.lastModified()).difference(modified).abs(),
            lessThan(const Duration(seconds: 1)),
          );
        },
      );
    },
    skip: !Platform.isLinux && !Platform.isWindows
        ? 'This suite targets the Linux and Windows local filesystem backend.'
        : false,
  );

  group('cloud staged transfers', () {
    late _CloudClient client;
    late CloudOperationBackend backend;
    setUp(() {
      client = _CloudClient();
      backend = CloudOperationBackend(client, isCurrent: () => true);
    });

    test(
      'cloud verification runs before the old destination is backed up',
      () async {
        client.put('/target/a.txt', 'original');
        await expectLater(
          backend.writePreparedFile(
            '/target/a.txt',
            Stream.value(utf8.encode('new')),
            3,
            replace: true,
            verifyStaged: (staged) async {
              expect(staged.path, contains('.crisp-transfer-'));
              expect(client.text('/target/a.txt'), 'original');
              throw StateError('Digest mismatch');
            },
          ),
          throwsStateError,
        );
        expect(client.text('/target/a.txt'), 'original');
        expect(client.renames, isEmpty);
      },
    );

    test('case aliases cannot bypass cloud no-overwrite checks', () async {
      client.put('/target/Photo.txt', 'original');
      expect(
        (await backend.stat('/TARGET/photo.txt'))!.path,
        '/target/Photo.txt',
      );
      await expectLater(
        backend.writeFile(
          '/TARGET/photo.txt',
          Stream.value(utf8.encode('new')),
          3,
          replace: false,
        ),
        throwsStateError,
      );
      expect(client.text('/target/Photo.txt'), 'original');
      expect(client.uploads, isEmpty);
    });

    test(
      'case-ambiguous cloud listings are rejected instead of choosing an item',
      () async {
        client.put('/target/Photo.txt', 'one');
        client.put('/target/photo.txt', 'two');
        await expectLater(
          backend.stat('/target/photo.txt'),
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              'message',
              contains('case-ambiguous'),
            ),
          ),
        );
        expect(client.text('/target/Photo.txt'), 'one');
        expect(client.text('/target/photo.txt'), 'two');
        expect(client.deleted, isEmpty);
      },
    );

    test('an actual cloud destination matching the source blocks move and permits Keep both copy', () async {
      client.put('/target/Photo.txt', 'original');
      final source = (await backend.stat('/target/Photo.txt'))!;
      const service = FileOperationService();
      final move = await service.prepare(
        files: [source],
        source: backend,
        destination: backend,
        targetDirectory: '/TARGET',
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          fileConflict: FileConflictPolicy.replace,
        ),
      );
      expect(move.canExecute, isFalse);
      expect(move.errors.join(), contains('into itself'));
      final copy = await service.prepare(
        files: [source],
        source: backend,
        destination: backend,
        targetDirectory: '/TARGET',
        options: const FileOperationOptions(
          fileConflict: FileConflictPolicy.keepBoth,
        ),
      );
      expect(copy.canExecute, isTrue);
      expect(copy.entries.single.destination, '/target/Photo (1).txt');
      await service.execute(copy, control: FileOperationControl());
      expect(copy.entries.single.outcome, FileOperationOutcome.copied);
      expect(client.text('/target/Photo.txt'), 'original');
      expect(client.text('/target/Photo (1).txt'), 'original');
      expect(client.deleted, isEmpty);
    });

    test(
      'cloud collision reservations keep both case-distinct source rows',
      () async {
        client.directories.addAll(['/one', '/two']);
        client.put('/one/Photo.txt', 'one');
        client.put('/two/photo.txt', 'two');
        final selected = [
          (await backend.stat('/one/Photo.txt'))!,
          (await backend.stat('/two/photo.txt'))!,
        ];
        const service = FileOperationService();
        final collision = await service.prepare(
          files: selected,
          source: backend,
          destination: backend,
          targetDirectory: '/target',
        );
        expect(collision.entries, hasLength(2));
        expect(collision.canExecute, isFalse);
        expect(collision.errors.join(), contains('Several source items'));
        final keepBoth = await service.prepare(
          files: selected,
          source: backend,
          destination: backend,
          targetDirectory: '/target',
          options: const FileOperationOptions(
            fileConflict: FileConflictPolicy.keepBoth,
          ),
        );
        expect(keepBoth.entries, hasLength(2));
        expect(keepBoth.entries.map((entry) => entry.destination), [
          '/target/Photo.txt',
          '/target/photo (1).txt',
        ]);
        await service.execute(keepBoth, control: FileOperationControl());
        expect(
          keepBoth.entries.map((entry) => entry.outcome),
          everyElement(FileOperationOutcome.copied),
        );
        expect(client.text('/target/Photo.txt'), 'one');
        expect(client.text('/target/photo (1).txt'), 'two');
      },
    );

    Future<void> write(String contents, {bool replace = true, int? length}) =>
        backend.writeFile(
          '/target/a.txt',
          Stream.value(utf8.encode(contents)),
          length ?? utf8.encode(contents).length,
          replace: replace,
        );

    test('a backup rename with a lost acknowledgement still reports the recovery file', () async {
      client.put('/target/a.txt', 'original');
      client.afterBackup = () {
        throw StateError('Rename acknowledgement lost');
      };
      client.failRestore = true;
      Object? failure;
      try {
        await write('replacement');
      } catch (error) {
        failure = error;
      }
      final backup = client.files.keys.singleWhere(
        (name) => name.contains('/.crisp-replaced-'),
      );
      expect(client.text(backup), 'original');
      expect(failure, isA<StateError>());
      expect(failure.toString(), contains('Rename acknowledgement lost'));
      expect(failure.toString(), contains(backup));
      expect(client.deleted, isNot(contains(backup)));
    });

    test(
      'unknown-length uploads supply the actual length to the provider',
      () async {
        await backend.writeFile(
          '/target/a.txt',
          Stream.fromIterable([
            [1, 2],
            [3, 4, 5],
          ]),
          null,
          replace: false,
        );
        expect(client.lastUploadLength, 5);
        expect(client.files['/target/a.txt'], [1, 2, 3, 4, 5]);
        expect(client.files.keys, ['/target/a.txt']);
      },
    );

    test(
      'replacement uploads under a temporary name before committing',
      () async {
        client.put('/target/a.txt', 'original');
        String? valueDuringUpload;
        client.afterUpload = () {
          valueDuringUpload = client.text('/target/a.txt');
        };
        await write('replacement');
        expect(valueDuringUpload, 'original');
        expect(client.uploads.single, contains('/.crisp-transfer-'));
        expect(client.text('/target/a.txt'), 'replacement');
        expect(client.files.keys, ['/target/a.txt']);
        expect(client.renames, hasLength(2));
        expect(client.renames.first.$1, '/target/a.txt');
        expect(client.renames.first.$2, startsWith('.crisp-replaced-'));
        expect(client.renames.last.$2, 'a.txt');
      },
    );

    test(
      'failed upload preserves existing data and removes the partial stage',
      () async {
        client.put('/target/a.txt', 'original');
        client.failUpload = true;
        await expectLater(write('replacement'), throwsStateError);
        expect(client.text('/target/a.txt'), 'original');
        expect(client.files.keys, ['/target/a.txt']);
        expect(client.renames, isEmpty);
        expect(client.deleted, everyElement(contains('/.crisp-transfer-')));
      },
    );

    test('source stream errors leave the destination unchanged', () async {
      client.put('/target/a.txt', 'original');
      Stream<List<int>> failedRead() async* {
        yield [1, 2, 3];
        throw StateError('read failed');
      }

      await expectLater(
        backend.writeFile('/target/a.txt', failedRead(), 50, replace: true),
        throwsStateError,
      );
      expect(client.text('/target/a.txt'), 'original');
      expect(client.files.keys, ['/target/a.txt']);
    });

    test(
      'length mismatch is rejected before moving the previous destination',
      () async {
        client.put('/target/a.txt', 'original');
        await expectLater(write('short', length: 100), throwsStateError);
        expect(client.text('/target/a.txt'), 'original');
        expect(client.renames, isEmpty);
        expect(client.files.keys, ['/target/a.txt']);
      },
    );

    test(
      'failed commit restores the previous destination from its backup',
      () async {
        client.put('/target/a.txt', 'original');
        client.failCommit = true;
        await expectLater(write('replacement'), throwsStateError);
        expect(client.text('/target/a.txt'), 'original');
        final stage = client.files.keys.singleWhere(
          (path) => path.contains('.crisp-transfer-'),
        );
        expect(client.text(stage), 'replacement');
        expect(client.files.keys, hasLength(2));
        expect(client.renames.last.$1, contains('/.crisp-replaced-'));
        expect(client.renames.last.$2, 'a.txt');
      },
    );

    test(
      'failed restore preserves and reports the original recovery path',
      () async {
        client.put('/target/a.txt', 'original');
        client.failCommit = true;
        client.failRestore = true;
        Object? failure;
        try {
          await write('replacement');
        } catch (error) {
          failure = error;
        }
        expect(failure, isA<StateError>());
        final backup = client.files.keys.singleWhere(
          (name) => name.contains('/.crisp-replaced-'),
        );
        expect(client.text(backup), 'original');
        expect(failure.toString(), contains(backup));
        expect(client.deleted, isNot(contains(backup)));
      },
    );

    test(
      'account changes after backup prevent commit and all cleanup writes',
      () async {
        client.put('/target/a.txt', 'original');
        client.afterBackup = () {
          client.authenticated = false;
        };
        await expectLater(write('replacement'), throwsStateError);
        final backup = client.files.keys.singleWhere(
          (name) => name.contains('/.crisp-replaced-'),
        );
        expect(client.text(backup), 'original');
        expect(client.renames, hasLength(1));
        expect(client.deleted, isEmpty);
        expect(
          client.files.keys.where((name) => name.contains('/.crisp-transfer-')),
          hasLength(1),
        );
      },
    );

    test('a competing destination created during upload is never replaced in no-overwrite mode', () async {
      client.afterUpload = () {
        client.put('/target/a.txt', 'concurrent writer');
      };
      await expectLater(write('new data', replace: false), throwsStateError);
      expect(client.text('/target/a.txt'), 'concurrent writer');
      expect(client.renames, isEmpty);
      expect(client.files.keys, ['/target/a.txt']);
    });

    test('failure to remove a recovery backup does not invalidate a completed copy', () async {
      client.put('/target/a.txt', 'original');
      client.failBackupDeletion = true;
      await write('replacement');
      expect(client.text('/target/a.txt'), 'replacement');
      final backup = client.files.keys.singleWhere(
        (name) => name.contains('/.crisp-replaced-'),
      );
      expect(client.text(backup), 'original');
    });

    test('cloud source directories are retained when conditional empty deletion is unavailable', () async {
      client.directories.add('/target/folder');
      client.put('/target/folder/keep.txt', 'keep');
      await expectLater(
        backend.deleteEmptyDirectory('/target/folder'),
        throwsUnsupportedError,
      );
      expect(client.text('/target/folder/keep.txt'), 'keep');
      expect(client.deleted, isEmpty);
    });
  });

  group('conditional object commit', () {
    late _ExactObjectClient client;
    late CloudOperationBackend backend;
    setUp(() {
      client = _ExactObjectClient();
      backend = CloudOperationBackend(client, isCurrent: () => true);
    });

    Future<void> write({
      bool replace = false,
      Future<void> Function(Map<String, dynamic>)? checkpoint,
    }) => backend.writePreparedFile(
      '/target/a.txt',
      Stream.value(utf8.encode('new')),
      3,
      replace: replace,
      checkpoint: checkpoint,
    );

    test('replacement uses conditional copy and version-specific cleanup throughout', () async {
      client.put('/target/a.txt', 'original');
      final checkpoints = <Map<String, dynamic>>[];
      await write(
        replace: true,
        checkpoint: (state) async {
          checkpoints.add(state);
        },
      );
      expect(client.renames, isEmpty);
      expect(client.text('/target/a.txt'), 'new');
      expect(client.files.keys, ['/target/a.txt']);
      expect(client.copies, hasLength(2));
      expect(client.conditionalDeletes, hasLength(3));
      expect(
        checkpoints.map((state) => state['phase']),
        containsAllInOrder([
          'backupCopied',
          'backedUp',
          'commitCopied',
          'committed',
        ]),
      );
      expect(
        checkpoints.firstWhere(
          (state) => state['phase'] == 'commitCopied',
        )['commitCopyVersion'],
        isNotNull,
      );
    });

    test(
      'a target created inside the exact commit is never overwritten',
      () async {
        client.beforeCopy = (source, target) {
          if (target == '/target/a.txt') client.put(target, 'concurrent');
        };
        await expectLater(write(), throwsStateError);
        expect(client.text('/target/a.txt'), 'concurrent');
        expect(client.conditionalDeletes, isEmpty);
        expect(
          client.files.keys.where((path) => path.contains('.crisp-transfer-')),
          hasLength(1),
        );
      },
    );

    test(
      'a changed original is retained after its backup copy completes',
      () async {
        client.put('/target/a.txt', 'original');
        client.beforeConditionalDelete = (path) {
          if (path == '/target/a.txt') client.put(path, 'changed original');
        };
        await expectLater(write(replace: true), throwsStateError);
        expect(client.text('/target/a.txt'), 'changed original');
        final backup = client.files.keys.singleWhere(
          (path) => path.contains('.crisp-replaced-'),
        );
        expect(client.text(backup), 'original');
        expect(client.renames, isEmpty);
      },
    );

    test('a failed copy checkpoint preserves both confirmed copy and original stage', () async {
      await expectLater(
        write(
          checkpoint: (state) async {
            if (state['phase'] == 'commitCopied') {
              throw StateError('Journal unavailable');
            }
          },
        ),
        throwsStateError,
      );
      expect(client.text('/target/a.txt'), 'new');
      expect(client.conditionalDeletes, isEmpty);
      final stage = client.files.keys.singleWhere(
        (path) => path.contains('.crisp-transfer-'),
      );
      expect(client.text(stage), 'new');
    });

    test(
      'a lost conditional delete reply reconciles exact destination version',
      () async {
        client.loseDeleteReply = true;
        await write();
        expect(client.text('/target/a.txt'), 'new');
        expect(client.files.keys, ['/target/a.txt']);
      },
    );

    test('a failed commit restores the original through exact conditional primitives', () async {
      client.put('/target/a.txt', 'original');
      client.beforeCopy = (source, target) {
        if (source.contains('.crisp-transfer-')) {
          throw StateError('Copy refused');
        }
      };
      await expectLater(write(replace: true), throwsStateError);
      expect(client.text('/target/a.txt'), 'original');
      expect(client.renames, isEmpty);
      expect(
        client.files.keys.where((path) => path.contains('.crisp-replaced-')),
        isEmpty,
      );
    });

    test(
      'unsupported object stores fail before upload or source consumption',
      () async {
        final unsupported = _UnsupportedObjectClient();
        var consumed = false;
        Stream<List<int>> content() async* {
          consumed = true;
          yield [1];
        }

        await expectLater(
          CloudOperationBackend(
            unsupported,
            isCurrent: () => true,
          ).writePreparedFile('/target/a.txt', content(), 1, replace: false),
          throwsUnsupportedError,
        );
        expect(consumed, isFalse);
        expect(unsupported.uploads, isEmpty);
      },
    );
  });
}

class _UnsupportedObjectClient extends _CloudClient
    implements ObjectStorageNamespace {}

class _ExactObjectClient extends _CloudClient
    with CloudTransferOperations
    implements ObjectStorageNamespace {
  final versions = <String, String>{};
  final copies = <(String, String)>[];
  final conditionalDeletes = <(String, String?)>[];
  int nextVersion = 0;
  bool loseDeleteReply = false;
  void Function(String, String)? beforeCopy;
  void Function(String)? beforeConditionalDelete;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        caseSensitivity: StorageCaseSensitivity.sensitive,
        nativeCopy: true,
        noReplaceCopy: true,
        conditionalCopy: true,
        conditionalDelete: true,
      );
  @override
  void put(String path, String text) {
    super.put(path, text);
    versions[path] = '${++nextVersion}';
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    await super.uploadStream(
      dataStream,
      length,
      fileName,
      targetPath,
      onProgress: onProgress,
    );
    versions[p.posix.join(targetPath, fileName)] = '${++nextVersion}';
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final result = await super.listPath(path);
    for (final file in result['files'] as List) {
      file['eTag'] = versions[p.posix.join(path, file['name'] as String)];
    }
    return result;
  }

  @override
  Future<CloudTransferResult> copyToExact(
    String sourcePath,
    String destinationPath, {
    bool replace = false,
    String? expectedSourceVersion,
    String? expectedDestinationVersion,
    TransferCheckpoint? checkpoint,
    void Function(int, int)? onProgress,
  }) async {
    expect(replace, isFalse);
    beforeCopy?.call(sourcePath, destinationPath);
    if (expectedSourceVersion == null ||
        versions[sourcePath] != expectedSourceVersion ||
        files.containsKey(destinationPath)) {
      throw StateError('Conditional copy refused');
    }
    copies.add((sourcePath, destinationPath));
    files[destinationPath] = Uint8List.fromList(files[sourcePath]!);
    final version = versions[destinationPath] = '${++nextVersion}';
    return CloudTransferResult(
      path: destinationPath,
      version: version,
      size: files[destinationPath]!.length,
    );
  }

  @override
  Future<void> deleteTransferFile(
    String path, {
    String? expectedVersion,
  }) async {
    beforeConditionalDelete?.call(path);
    if (expectedVersion == null || versions[path] != expectedVersion) {
      throw StateError('Conditional delete refused');
    }
    conditionalDeletes.add((path, expectedVersion));
    files.remove(path);
    versions.remove(path);
    if (loseDeleteReply) throw StateError('Delete reply lost');
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    throw StateError('Legacy rename must not be used for object commits');
  }
}

/// Deliberately models destructive streaming uploads. The adapter must stage
/// away from the destination to make this provider behavior safe.
class _CloudClient extends CloudStorageClient {
  final files = <String, Uint8List>{};
  final directories = <String>{'/', '/target'};
  final uploads = <String>[];
  final renames = <(String, String)>[];
  final deleted = <String>[];
  int? lastUploadLength;
  bool authenticated = true;
  bool failUpload = false;
  bool failCommit = false;
  bool failRestore = false;
  bool failBackupDeletion = false;
  FutureOr<void> Function()? afterUpload;
  FutureOr<void> Function()? afterBackup;

  void put(String path, String text) =>
      files[path] = Uint8List.fromList(utf8.encode(text));
  String text(String path) => utf8.decode(files[path]!);

  @override
  String get providerName => 'Fake staged cloud';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => authenticated;
  @override
  String? get userId => 'test-user';
  @override
  String? get bucketId => null;
  @override
  Future<void> login(
    String email,
    String password, {
    String? twoFactorCode,
  }) async {
    authenticated = true;
  }

  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<void> logout() async {
    authenticated = false;
  }

  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async =>
      files.containsKey(path) || directories.contains(path)
      ? {'path': path}
      : null;

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    if (!directories.contains(path)) {
      throw StateError('Directory missing: $path');
    }
    return {
      'folders': directories
          .where((entry) => entry != path && p.posix.dirname(entry) == path)
          .map((entry) => {'name': p.posix.basename(entry), 'uuid': entry})
          .toList(),
      'files': files.entries
          .where((entry) => p.posix.dirname(entry.key) == path)
          .map(
            (entry) => {
              'name': p.posix.basename(entry.key),
              'uuid': entry.key,
              'size': entry.value.length,
            },
          )
          .toList(),
    };
  }

  @override
  Future<void> createFolderPath(String path) async {
    directories.add(path);
  }

  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    files[p.posix.join(targetPath, fileName)] = Uint8List.fromList(fileData);
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    lastUploadLength = length;
    final path = p.posix.join(targetPath, fileName);
    uploads.add(path);
    files[path] = Uint8List(0);
    final received = <int>[];
    await for (final chunk in dataStream) {
      received.addAll(chunk);
      files[path] = Uint8List.fromList(received);
      if (failUpload) throw StateError('Upload connection failed');
    }
    await afterUpload?.call();
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async => Uint8List.fromList(files[remotePath]!);

  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async* {
    yield Uint8List.fromList(files[remotePath]!);
  }

  @override
  Future<void> downloadFileByPath(
    String remotePath,
    String localPath, {
    Function(int, int)? onProgress,
  }) async {
    await File(localPath).writeAsBytes(files[remotePath]!);
  }

  @override
  Future<void> renamePath(String path, String newName) async {
    renames.add((path, newName));
    if (failCommit && path.contains('/.crisp-transfer-')) {
      throw StateError('Commit rename failed');
    }
    if (failRestore && path.contains('/.crisp-replaced-')) {
      throw StateError('Recovery rename failed');
    }
    final destination = p.posix.join(p.posix.dirname(path), newName);
    if (files.containsKey(destination) || directories.contains(destination)) {
      throw StateError('Rename would overwrite another item');
    }
    final bytes = files.remove(path);
    if (bytes == null) throw StateError('Missing rename source');
    files[destination] = bytes;
    if (newName.startsWith('.crisp-replaced-')) await afterBackup?.call();
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async =>
      throw UnimplementedError();

  @override
  Future<void> deletePath(String path) async {
    deleted.add(path);
    if (failBackupDeletion && path.contains('/.crisp-replaced-')) {
      throw StateError('Recovery backup retained');
    }
    files.remove(path);
    directories.remove(path);
  }
}

class _FreshCloudClient extends _CloudClient
    implements FreshCloudDirectoryReader {
  final List<String> freshReads = [];
  final List<String> cachedReads = [];
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    cachedReads.add(path);
    throw StateError('Stale listing path was used');
  }

  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) {
    freshReads.add(path);
    return super.listPath(path);
  }
}

class _DirectoryWithDisappearedChild extends Fake implements Directory {
  _DirectoryWithDisappearedChild(this.directory);
  final Directory directory;
  @override
  String get path => directory.path;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    yield File(p.join(path, 'disappeared-sibling'));
    yield* directory.list(recursive: recursive, followLinks: followLinks);
  }
}

class _DeniedResolutionFile extends Fake implements File {
  _DeniedResolutionFile(this.path);
  @override
  final String path;
  @override
  Future<String> resolveSymbolicLinks() async => throw FileSystemException(
    'Permission denied',
    path,
    const OSError('Permission denied', 13),
  );
}

class _ObservedRangeFile extends Fake implements File {
  _ObservedRangeFile(this.file, this.opened);
  final File file;
  final void Function(int?) opened;
  @override
  String get path => file.path;
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    opened(start);
    return file.openRead(start, end);
  }
}

class _ResumableCloudClient extends _CloudClient with CloudTransferOperations {
  _ResumableCloudClient(this.account);
  final String account;
  final pending = <String, int>{};
  final resumed = <String>[];
  bool interruptNext = false;
  @override
  String get userId => account;
  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        resumableUpload: true,
        boundedUpload: true,
        boundedDownload: true,
      );
  @override
  Future<bool> hasPendingUpload(String path, {int? length}) async =>
      pending.containsKey(path) && (length == null || pending[path] == length);
  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final path = p.posix.join(targetPath, fileName);
    if (interruptNext) {
      interruptNext = false;
      uploads.add(path);
      pending[path] = length;
      await dataStream.first;
      throw StateError(
        'Multipart upload was interrupted before becoming an object.',
      );
    }
    if (pending.remove(path) != null) resumed.add(path);
    await super.uploadStream(
      dataStream,
      length,
      fileName,
      targetPath,
      onProgress: onProgress,
    );
  }
}
