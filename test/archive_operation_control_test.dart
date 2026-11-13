import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codecs;
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/archive_writer_worker.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_creation_backend.dart';
import 'support/archive_endpoint_backend.dart';

const _settle = Duration(milliseconds: 20);

class _CreationBackend extends ArchiveCreationBackend {
  int sourceChunks = 0;
  void Function()? onSourceChunk;
  void Function()? afterCommit;
  bool stallSource = false;
  final sourceStarted = Completer<void>();
  final sourceCancelled = Completer<void>();

  @override
  Stream<List<int>> readFile(FileItem file) {
    if (file.path != '/input/source.bin') return super.readFile(file);
    if (!sourceStarted.isCompleted) sourceStarted.complete();
    if (stallSource) {
      return StreamController<List<int>>(
        onCancel: () {
          if (!sourceCancelled.isCompleted) sourceCancelled.complete();
        },
      ).stream;
    }
    return super.readFile(file).map((chunk) {
      sourceChunks++;
      onSourceChunk?.call();
      return chunk;
    });
  }

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    if (replace || await stat(path) != null) throw StateError('Occupied.');
    const stage = '/output/.stage';
    try {
      await checkpoint?.call({
        'phase': 'staging',
        'destination': path,
        'stagedPath': stage,
      });
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in data) {
        bytes.add(chunk);
      }
      expect(bytes.length, length);
      put(stage, bytes.takeBytes());
      await verifyStaged?.call((await stat(stage))!);
      await checkpoint?.call({
        'phase': 'committing',
        'destination': path,
        'stagedPath': stage,
      });
      if (await stat(path) != null) throw StateError('Occupied.');
      contents[path] = contents[stage]!;
      writes.add(path);
      afterCommit?.call();
      await checkpoint?.call({'phase': 'committed', 'destination': path});
    } finally {
      contents.remove(stage);
    }
  }
}

Future<ArchiveCreationResult> _create(
  _CreationBackend backend, {
  FileOperationControl? control,
  bool background = false,
  String name = 'created.zip',
  String? expectedManifest,
  Future<void> Function(Map<String, dynamic>)? checkpoint,
}) async => const ArchiveCreationService().create(
  source: backend,
  destination: backend,
  files: [(await backend.stat('/input/source.bin'))!],
  destinationDirectory: '/output',
  options: ArchiveCreationOptions(
    name: name,
    format: ArchiveCreationFormat.zip,
  ),
  control: control,
  background: background,
  expectedSourceManifestSha256: expectedManifest,
  onPublicationCheckpoint: checkpoint,
);

Matcher _cancelledCreation() => throwsA(
  isA<ArchiveCreationException>().having(
    (error) => error.code,
    'code',
    ArchiveCreationError.cancelled,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'creation pauses at an input boundary and resumes the exact payload',
    () async {
      final payload = Uint8List.fromList(List.generate(150000, (i) => i % 251));
      final backend = _CreationBackend()..put('/input/source.bin', payload);
      final control = FileOperationControl();
      final paused = Completer<void>();
      backend.onSourceChunk = () {
        if (paused.isCompleted) return;
        control.pause();
        paused.complete();
      };
      var finished = false;
      final run = _create(backend, control: control).whenComplete(() {
        finished = true;
      });
      await paused.future;
      final chunks = backend.sourceChunks;
      await Future<void>.delayed(_settle);
      expect(backend.sourceChunks, chunks);
      expect(backend.writes, isEmpty);
      expect(finished, isFalse);
      control.resume();
      final result = await run;
      expect(result.publicationWarning, isNull);
      final archive = await openViewerArchive(
        backend.contents[result.path]!,
        name: result.path,
      );
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), payload);
    },
  );

  test(
    'stopping a paused creation releases its checkpoint without publishing',
    () async {
      final backend = _CreationBackend()..put('/input/source.bin', [1, 2, 3]);
      final control = FileOperationControl()..pause();
      final run = _create(backend, control: control);
      final rejection = expectLater(run, _cancelledCreation());
      await Future<void>.delayed(_settle);
      expect(backend.sourceChunks, 0);
      control.cancel();
      await rejection;
      expect(backend.writes, isEmpty);
      expect(backend.contents.keys, ['/input/source.bin']);
    },
  );

  test(
    'stopping interrupts a source stalled before its first data chunk',
    () async {
      final backend = _CreationBackend()
        ..put('/input/source.bin', [1, 2, 3])
        ..stallSource = true;
      final control = FileOperationControl();
      final run = _create(backend, control: control);
      final rejection = expectLater(run, _cancelledCreation());
      await backend.sourceStarted.future;
      control.cancel();
      await rejection.timeout(const Duration(seconds: 2));
      await backend.sourceCancelled.future.timeout(const Duration(seconds: 2));
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'creation pauses before commit with an acknowledged source manifest',
    () async {
      final backend = _CreationBackend()..put('/input/source.bin', [3, 1, 4]);
      final control = FileOperationControl();
      final paused = Completer<void>();
      final phases = <String>[];
      final run = _create(
        backend,
        control: control,
        checkpoint: (state) async {
          phases.add(state['phase'] as String);
          expect(state['destination'], '/output/created.zip');
          expect(state['packedBytes'], greaterThan(0));
          expect(state['packedSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
          expect(
            state['sourceManifestSha256'],
            matches(RegExp(r'^[a-f0-9]{64}$')),
          );
          expect(state['entryCount'], 1);
          expect(state['sourceEntryCount'], 1);
          if (state['phase'] == 'committing') {
            expect(state['stagedPath'], '/output/.stage');
            control.pause();
            paused.complete();
          }
        },
      );
      await paused.future;
      await Future<void>.delayed(_settle);
      expect(backend.contents.containsKey('/output/.stage'), isTrue);
      expect(backend.writes, isEmpty);
      control.resume();
      await run;
      expect(phases, ['prepared', 'staging', 'committing', 'committed']);
    },
  );

  for (final changeStage in [false, true]) {
    test(
      'a precommit pause rechecks ${changeStage ? 'staged bytes' : 'source bytes'}',
      () async {
        final backend = _CreationBackend()
          ..put('/input/source.bin', [1, 2, 3, 4]);
        final control = FileOperationControl();
        final paused = Completer<void>();
        final run = _create(
          backend,
          control: control,
          checkpoint: (state) async {
            if (state['phase'] == 'committing') {
              control.pause();
              paused.complete();
            }
          },
        );
        final rejection = expectLater(
          run,
          throwsA(
            isA<ArchiveCreationException>().having(
              (error) => error.code,
              'code',
              changeStage
                  ? ArchiveCreationError.verificationFailed
                  : ArchiveCreationError.sourceChanged,
            ),
          ),
        );
        await paused.future;
        final path = changeStage ? '/output/.stage' : '/input/source.bin';
        final changed = Uint8List.fromList(backend.contents[path]!);
        changed[changed.length ~/ 2] ^= 0x5a;
        backend.put(path, changed);
        control.resume();
        await rejection;
        expect(backend.writes, isEmpty);
        expect(backend.contents.containsKey('/output/.stage'), isFalse);
      },
    );
  }

  test(
    'late stop and failed completion observer preserve committed creation',
    () async {
      final backend = _CreationBackend()
        ..put('/input/source.bin', [2, 7, 1, 8]);
      final control = FileOperationControl();
      final observerError = StateError('Completion journal unavailable.');
      backend.afterCommit = control.cancel;
      final result = await _create(
        backend,
        control: control,
        checkpoint: (state) async {
          if (state['phase'] == 'committed') throw observerError;
        },
      );
      expect(result.path, '/output/created.zip');
      expect(result.publicationWarning, same(observerError));
      expect(backend.writes, [result.path]);
      expect(backend.contents[result.path]!.length, result.bytes);
      expect(backend.contents.containsKey('/output/.stage'), isFalse);
    },
  );

  test('failed precommit observer prevents publication', () async {
    final backend = _CreationBackend()..put('/input/source.bin', [1, 4, 1, 4]);
    final failure = StateError('Intent was not acknowledged.');
    await expectLater(
      _create(
        backend,
        checkpoint: (state) async {
          if (state['phase'] == 'committing') throw failure;
        },
      ),
      throwsA(same(failure)),
    );
    expect(backend.writes, isEmpty);
    expect(backend.contents.keys, ['/input/source.bin']);
  });

  test(
    'restart manifest rejects different bytes with identical size and time',
    () async {
      final backend = _CreationBackend()
        ..put('/input/source.bin', [1, 2, 3, 4]);
      String? manifest;
      await _create(
        backend,
        checkpoint: (state) async {
          manifest = state['sourceManifestSha256'] as String;
        },
      );
      final before = (await backend.stat('/input/source.bin'))!;
      backend.put('/input/source.bin', [4, 3, 2, 1]);
      final after = (await backend.stat('/input/source.bin'))!;
      expect(after.size, before.size);
      expect(after.updatedAt, before.updatedAt);
      await expectLater(
        _create(backend, name: 'restarted.zip', expectedManifest: manifest),
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.sourceChanged,
          ),
        ),
      );
      expect(backend.contents.containsKey('/output/restarted.zip'), isFalse);
      expect(backend.writes, ['/output/created.zip']);
    },
  );

  test(
    'background creation uses controlled source and publishes verified content',
    () async {
      final payload = Uint8List.fromList(List.generate(70001, (i) => i % 239));
      final backend = _CreationBackend()..put('/input/source.bin', payload);
      final result = await _create(backend, background: true);
      final archive = await openViewerArchive(
        backend.contents[result.path]!,
        name: result.path,
      );
      addTearDown(archive.close);
      expect(await archive.readMember(archive.members.single), payload);
    },
    skip: !supportsArchiveWriterWorker,
  );

  test(
    'workspace exposes its diff before paused background review and save',
    () async {
      final input = codecs.Archive()
        ..addFile(codecs.ArchiveFile.bytes('original.txt', [6, 2, 6]));
      final backend = ArchiveEndpointTestBackend()
        ..put('/out/work.zip', codecs.ZipEncoder().encode(input));
      final workspace = await ArchiveWorkspace.open(
        backend,
        (await backend.stat('/out/work.zip'))!,
        journal: ArchivePublicationJournal(
          storage: MemoryFileCollectionStorage(),
        ),
      );
      addTearDown(workspace.close);
      workspace.rename('/original.txt', 'renamed.txt');
      final changes = workspace.draftChanges;
      expect(changes.single.kind, ArchiveWorkspaceChangeKind.rename);
      final control = FileOperationControl()..pause();
      var finished = false;
      final future = workspace
          .review(control: control, background: true)
          .whenComplete(() => finished = true);
      expect(
        () => workspace.moveMembers(['/renamed.txt'], '/'),
        throwsStateError,
      );
      await Future<void>.delayed(_settle);
      expect(finished, isFalse);
      expect(backend.mutations, isEmpty);
      control.resume();
      final review = await future;
      expect(review.changes.single.path, changes.single.path);
      final warning = StateError('The saved workspace observer failed.');
      control.pause();
      final saving = workspace.save(
        reviewed: review,
        control: control,
        background: true,
        onPhase: (phase) {
          if (phase == ArchivePublicationPhase.published) throw warning;
        },
      );
      expect(
        () => workspace.moveMembers(['/renamed.txt'], '/'),
        throwsStateError,
      );
      await Future<void>.delayed(_settle);
      expect(backend.mutations, isEmpty);
      control.resume();
      final receipt = await saving;
      expect(workspace.lastPublicationWarning, same(warning));
      expect(receipt, isNotNull);
      expect(workspace.dirty, isFalse);
      expect(await workspace.read('/renamed.txt'), [6, 2, 6]);
    },
    skip: !supportsArchiveWriterWorker,
  );

  for (final cancel in [false, true]) {
    test(
      'publisher ${cancel ? 'stops and restores' : 'finishes a requested pause'} after backup',
      () async {
        final original = Uint8List.fromList([1, 2, 3]);
        final candidate = Uint8List.fromList([7, 8, 9, 10]);
        final backend = ArchiveEndpointTestBackend()
          ..put('/out/work.zip', original);
        final publisher = ArchiveContainerPublisher(
          backend,
          ArchivePublicationJournal(storage: MemoryFileCollectionStorage()),
        );
        final control = FileOperationControl();
        addTearDown(control.resume);
        final future = publisher.publish(
          original: (await backend.stat('/out/work.zip'))!,
          originalSha256: sha256.convert(original).toString(),
          bytes: candidate,
          control: control,
          onPhase: (phase) {
            if (phase == ArchivePublicationPhase.backedUp) {
              cancel ? control.cancel() : control.pause();
            }
          },
        );
        if (cancel) {
          await expectLater(
            future,
            throwsA(isA<ArchivePublicationException>()),
          );
          expect(backend.files['/out/work.zip'], original);
        } else {
          final receipt = await future.timeout(const Duration(seconds: 2));
          expect(receipt.record.phase, ArchivePublicationPhase.complete);
          expect(backend.files['/out/work.zip'], candidate);
          expect(control.isPaused, isTrue);
        }
      },
    );
  }

  test(
    'publication source guard may pause while original remains available',
    () async {
      final original = Uint8List.fromList([1, 6, 1, 8]);
      final backend = ArchiveEndpointTestBackend()
        ..put('/out/work.zip', original);
      final publisher = ArchiveContainerPublisher(
        backend,
        ArchivePublicationJournal(storage: MemoryFileCollectionStorage()),
      );
      final control = FileOperationControl();
      final guarded = Completer<void>();
      final future = publisher.publish(
        original: (await backend.stat('/out/work.zip'))!,
        originalSha256: sha256.convert(original).toString(),
        bytes: Uint8List.fromList([2, 7, 1, 8]),
        control: control,
        beforePublication: () async {
          control.pause();
          guarded.complete();
          await control.checkpoint();
        },
      );
      await guarded.future;
      expect(backend.files['/out/work.zip'], original);
      expect(backend.mutations.where((m) => m.startsWith('move:')), isEmpty);
      control.resume();
      await future;
    },
  );

  test(
    'post-publication observer failure retains a successful receipt',
    () async {
      final original = Uint8List.fromList([3, 3, 8]);
      final backend = ArchiveEndpointTestBackend()
        ..put('/out/work.zip', original);
      final publisher = ArchiveContainerPublisher(
        backend,
        ArchivePublicationJournal(storage: MemoryFileCollectionStorage()),
      );
      final warning = StateError('A completed-job observer failed.');
      final control = FileOperationControl();
      final receipt = await publisher.publish(
        original: (await backend.stat('/out/work.zip'))!,
        originalSha256: sha256.convert(original).toString(),
        bytes: Uint8List.fromList([1, 0, 0]),
        control: control,
        onPhase: (phase) {
          if (phase == ArchivePublicationPhase.published) {
            control.cancel();
            throw warning;
          }
        },
      );
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
      expect(publisher.observerWarning, same(warning));
      expect(backend.files['/out/work.zip'], [1, 0, 0]);
    },
  );

  test(
    'intentional pause is excluded from publisher verification deadlines',
    () async {
      final original = Uint8List.fromList([1, 2, 3]);
      final backend = ArchiveEndpointTestBackend()
        ..put('/out/work.zip', original);
      final control = FileOperationControl();
      var paused = false;
      backend.before = (action, path, _) {
        if (action == 'read' && !paused) {
          paused = true;
          control.pause();
          Timer(const Duration(milliseconds: 1200), control.resume);
        }
      };
      final publisher = ArchiveContainerPublisher(
        backend,
        ArchivePublicationJournal(storage: MemoryFileCollectionStorage()),
        verificationDeadline: (_) => const Duration(seconds: 1),
      );
      final receipt = await publisher.publish(
        original: (await backend.stat('/out/work.zip'))!,
        originalSha256: sha256.convert(original).toString(),
        bytes: Uint8List.fromList([4, 5, 6]),
        control: control,
      );
      expect(paused, isTrue);
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
    },
  );
}
