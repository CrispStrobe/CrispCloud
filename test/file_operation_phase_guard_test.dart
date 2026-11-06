import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/workflow_fake_client.dart';

const _sourcePath = '/input/report.txt';
const _targetPath = '/target/report.txt';
const _payload = 'complete source contents';
const _original = 'original destination';

/// Models an adapter that consumes all plaintext into private storage before
/// its actual upload finishes. The input subscription cannot observe later
/// cancellation, so the operation must gate the subsequent commit phases.
class _SpooledCloud extends WorkflowFakeClient {
  _SpooledCloud(this.account);
  final String account;
  Future<void> Function()? afterInput;
  Future<void> Function()? afterBackup;
  final renames = <(String, String)>[];
  int inputLength = 0;

  @override
  String? get userId => account;

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await for (final part in dataStream) {
      bytes.add(part);
    }
    inputLength = bytes.length;
    expect(inputLength, length);
    await afterInput?.call();
    await super.uploadFile(bytes.takeBytes(), fileName, targetPath);
  }

  @override
  Future<void> renamePath(String path, String name) async {
    final destination = p.posix.join(p.posix.dirname(path), name);
    if (files.containsKey(destination)) {
      throw StateError('The fixture does not overwrite during rename.');
    }
    renames.add((path, destination));
    await super.renamePath(path, name);
    if (name.startsWith('.crisp-replaced-')) await afterBackup?.call();
  }
}

/// An object-store backup restore needs two mutations and a `restoreCopied`
/// checkpoint between them; cancellation must not block verified rollback.
class _ObjectCloud extends _SpooledCloud
    with CloudTransferOperations
    implements ObjectStorageNamespace {
  _ObjectCloud() : super('object-destination');
  final versions = <String, String>{};
  final copies = <(String, String)>[];
  int _version = 0;
  Future<void> Function(String)? afterDelete;

  @override
  StorageTransferCapabilities get transferCapabilities =>
      const StorageTransferCapabilities(
        nativeCopy: true,
        noReplaceCopy: true,
        conditionalCopy: true,
        conditionalDelete: true,
      );

  @override
  void put(String path, List<int> bytes, {DateTime? date}) {
    super.put(path, bytes, date: date);
    versions[path] = '${++_version}';
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final result = await super.listPath(path);
    for (final file in result['files'] as List) {
      file['eTag'] = versions[file['path']];
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
    await checkpoint?.call();
    if (replace ||
        expectedSourceVersion == null ||
        versions[sourcePath] != expectedSourceVersion ||
        files.containsKey(destinationPath)) {
      throw StateError('Conditional fixture copy refused.');
    }
    copies.add((sourcePath, destinationPath));
    put(destinationPath, files[sourcePath]!);
    return CloudTransferResult(
      path: destinationPath,
      version: versions[destinationPath],
      size: files[destinationPath]!.length,
    );
  }

  @override
  Future<void> deleteTransferFile(
    String path, {
    String? expectedVersion,
  }) async {
    if (expectedVersion == null || versions[path] != expectedVersion) {
      throw StateError('Conditional fixture deletion refused.');
    }
    await super.deletePath(path);
    versions.remove(path);
    await afterDelete?.call(path);
  }

  @override
  Future<void> renamePath(String path, String name) async =>
      throw StateError('Object storage cannot use a legacy rename.');
}

class _Fixture {
  _Fixture({_SpooledCloud? target, bool existing = true})
    : target = target ?? _SpooledCloud('destination') {
    source.put(_sourcePath, utf8.encode(_payload));
    this.target.directories.add('/target');
    if (existing) this.target.put(_targetPath, utf8.encode(_original));
  }
  final source = _SpooledCloud('source');
  final _SpooledCloud target;
  bool sourceCurrent = true;
  final storage = MemoryTransferJournalStorage();
  late final journal = TransferJournal(storage);
  final phases = <String>[];

  Future<FileOperationPlan> prepare({
    FileOperationKind kind = FileOperationKind.copy,
  }) async {
    final from = CloudOperationBackend(source, isCurrent: () => sourceCurrent);
    final plan = await const FileOperationService().prepare(
      source: from,
      destination: CloudOperationBackend(target, isCurrent: () => true),
      files: [(await from.stat(_sourcePath))!],
      targetDirectory: '/target',
      options: FileOperationOptions(
        kind: kind,
        fileConflict: FileConflictPolicy.replace,
        preferNative: false,
        copyMethod: FileCopyMethod.stream,
      ),
    );
    expect(plan.errors, isEmpty);
    await journal.create('guard', plan);
    return plan;
  }

  Future<void> run(
    FileOperationPlan plan,
    FileOperationControl control, {
    void Function(String)? afterCheckpoint,
  }) => const FileOperationService().execute(
    plan,
    control: control,
    checkpoint: (entry, phase) async {
      phases.add(phase);
      await journal.checkpoint('guard', 0, entry, phase);
      afterCheckpoint?.call(phase);
    },
  );

  Future<void> expectRecordedStage() async {
    final restored = TransferJournal(storage);
    await restored.initialize();
    final recovery = restored.job('guard')!.entries.single.recovery;
    expect(recovery['stagedPath'], contains('/.crisp-transfer-'));
    expect(
      recovery['contentSha256'],
      sha256.convert(utf8.encode(_payload)).toString(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in FileOperationKind.values) {
    for (final existing in [false, true]) {
      test(
        '${kind.name} cancellation after input EOF prevents destination commit (existing: $existing)',
        () async {
          final fixture = _Fixture(existing: existing);
          final consumed = Completer<void>();
          final acknowledge = Completer<void>();
          fixture.target.afterInput = () async {
            consumed.complete();
            await acknowledge.future;
          };
          final control = FileOperationControl();
          final plan = await fixture.prepare(kind: kind);
          final running = fixture.run(plan, control);
          await consumed.future;
          expect(fixture.target.inputLength, utf8.encode(_payload).length);
          control.cancel();
          acknowledge.complete();
          await running;
          expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
          expect(fixture.source.files[_sourcePath], utf8.encode(_payload));
          expect(
            fixture.target.files[_targetPath],
            existing ? utf8.encode(_original) : isNull,
          );
          expect(fixture.target.renames, isEmpty);
          expect(
            fixture.target.files.keys.any((path) => path.contains('.crisp-')),
            isFalse,
          );
          expect(fixture.phases, containsAllInOrder(['staged', 'cancelled']));
          await fixture.expectRecordedStage();
        },
      );
    }
  }

  test(
    'a disconnected source after input EOF blocks commit and retains evidence',
    () async {
      final fixture = _Fixture();
      fixture.target.afterInput = () async => fixture.sourceCurrent = false;
      final plan = await fixture.prepare();
      await fixture.run(plan, FileOperationControl());
      expect(plan.entries.single.outcome, FileOperationOutcome.failed);
      expect(fixture.target.files[_targetPath], utf8.encode(_original));
      expect(fixture.source.files[_sourcePath], utf8.encode(_payload));
      expect(fixture.target.renames, isEmpty);
      expect(fixture.phases, containsAllInOrder(['staged', 'failed']));
      await fixture.expectRecordedStage();
    },
  );

  test(
    'pause after input EOF waits before backup or commit, then resumes',
    () async {
      final fixture = _Fixture();
      final control = FileOperationControl();
      final staged = Completer<void>();
      fixture.target.afterInput = () async => control.pause();
      final plan = await fixture.prepare();
      var finished = false;
      final running = fixture
          .run(
            plan,
            control,
            afterCheckpoint: (phase) {
              if (phase == 'staged') staged.complete();
            },
          )
          .then((_) => finished = true);
      await staged.future;
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(fixture.target.files[_targetPath], utf8.encode(_original));
      expect(fixture.target.renames, isEmpty);
      control.resume();
      await running;
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
      expect(fixture.target.files[_targetPath], utf8.encode(_payload));
    },
  );

  for (final sourceDisconnected in [false, true]) {
    test(
      'verified cloud backup restores after ${sourceDisconnected ? 'source disconnect' : 'cancellation'}',
      () async {
        final fixture = _Fixture();
        final control = FileOperationControl();
        fixture.target.afterBackup = () async {
          if (sourceDisconnected) {
            fixture.sourceCurrent = false;
          } else {
            control.cancel();
          }
        };
        final plan = await fixture.prepare();
        await fixture.run(plan, control);
        expect(
          plan.entries.single.outcome,
          sourceDisconnected
              ? FileOperationOutcome.failed
              : FileOperationOutcome.cancelled,
        );
        expect(fixture.target.files[_targetPath], utf8.encode(_original));
        expect(fixture.source.files[_sourcePath], utf8.encode(_payload));
        expect(fixture.target.files.keys, [_targetPath]);
        expect(
          fixture.phases,
          containsAllInOrder(['backedUp', 'restoringBackup']),
        );
        expect(fixture.phases, isNot(contains('committing')));
        await fixture.expectRecordedStage();
      },
    );

    test(
      'conditional object rollback completes after ${sourceDisconnected ? 'source disconnect' : 'cancellation'}',
      () async {
        final target = _ObjectCloud();
        final fixture = _Fixture(target: target);
        final control = FileOperationControl();
        target.afterDelete = (path) async {
          if (path != _targetPath) return;
          if (sourceDisconnected) {
            fixture.sourceCurrent = false;
          } else {
            control.cancel();
          }
        };
        final plan = await fixture.prepare();
        await fixture.run(plan, control);
        expect(
          plan.entries.single.outcome,
          sourceDisconnected
              ? FileOperationOutcome.failed
              : FileOperationOutcome.cancelled,
        );
        expect(target.files[_targetPath], utf8.encode(_original));
        expect(target.files.keys, [_targetPath]);
        expect(target.copies, hasLength(2));
        expect(
          fixture.phases,
          containsAllInOrder([
            'backupCopied',
            'backedUp',
            'restoringBackup',
            'restoreCopied',
          ]),
        );
        expect(fixture.phases, isNot(contains('commitCopied')));
        await fixture.expectRecordedStage();
      },
    );
  }

  test(
    'cancellation at completed commit preserves its durable record and source',
    () async {
      final fixture = _Fixture();
      final control = FileOperationControl();
      final plan = await fixture.prepare(kind: FileOperationKind.move);
      await fixture.run(
        plan,
        control,
        afterCheckpoint: (phase) {
          if (phase == 'committed') control.cancel();
        },
      );
      expect(plan.entries.single.outcome, FileOperationOutcome.cancelled);
      expect(fixture.target.files[_targetPath], utf8.encode(_payload));
      expect(fixture.source.files[_sourcePath], utf8.encode(_payload));
      expect(fixture.phases, containsAllInOrder(['committed', 'cancelled']));
      expect(plan.entries.single.recovery!['phase'], 'committed');
      await fixture.expectRecordedStage();
    },
  );

  for (final cancel in [false, true]) {
    test(
      'native staging ${cancel ? 'cancellation' : 'journal failure'} removes its owned temporary directory',
      () async {
        final directory = await Directory.current.createTemp('phase_guard_');
        try {
          final target = File(p.join(directory.path, 'report.txt'));
          await target.writeAsString(_original);
          final backend = LocalOperationBackend(
            LocalFileService(),
            isCurrent: () => true,
          );
          final control = FileOperationControl();
          await expectLater(
            backend.writePreparedFile(
              target.path,
              Stream.value(utf8.encode(_payload)),
              utf8.encode(_payload).length,
              replace: true,
              checkpoint: (state) async {
                if (state['phase'] != 'staging') return;
                if (cancel) {
                  control.cancel();
                  await control.checkpoint();
                } else {
                  throw StateError('Journal unavailable');
                }
              },
            ),
            cancel ? throwsA(isA<FileOperationCancelled>()) : throwsStateError,
          );
          expect(await target.readAsString(), _original);
          expect((await directory.list().toList()).map((file) => file.path), [
            target.path,
          ]);
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isLinux && !Platform.isWindows,
    );
  }
}
