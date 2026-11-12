import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  Future<_Scenario> scenario({
    FileOperationKind kind = FileOperationKind.copy,
    int stageCount = 1,
    MemoryTransferJournalStorage? storage,
  }) async {
    final root = await Directory.systemTemp.createTemp('crisp-stage-cleanup-');
    addTearDown(() => root.delete(recursive: true));
    final content = Uint8List.fromList(
      List.generate(262161, (index) => (index * 31 + index ~/ 97) % 256),
    );
    final original = File(p.join(root.path, 'original.bin'));
    await original.writeAsBytes(content, flush: true);
    final out = await Directory(p.join(root.path, 'out')).create();
    final source = _InterruptedRangeSource();
    final target = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final plan = await const FileOperationService().prepare(
      source: source,
      destination: target,
      files: [(await source.stat(original.path))!],
      targetDirectory: out.path,
      options: FileOperationOptions(kind: kind),
    );
    expect(plan.errors, isEmpty);
    final stages = <File>[];
    for (var index = 0; index < stageCount; index++) {
      final private = await Directory(
        p.join(out.path, '.crisp-transfer-saved-$index'),
      ).create();
      final file = File(p.join(private.path, 'payload'));
      await file.writeAsBytes(
        content.sublist(0, 8193 + index * 16),
        flush: true,
      );
      stages.add(file);
    }
    plan.entries.single
      ..outcome = FileOperationOutcome.failed
      ..recovery = {
        'phase': 'writing',
        'stagedPath': stages.last.path,
        'sourceSha256': sha256.convert(content).toString(),
        if (stageCount > 1)
          'retainedStagePaths': stages.map((file) => file.path).toList(),
      };
    final store = storage ?? MemoryTransferJournalStorage();
    await TransferJournal(store).create('cleanup', plan);
    return _Scenario(
      root,
      original,
      File(p.join(out.path, 'original.bin')),
      content,
      source,
      target,
      store,
      stages,
    );
  }

  for (final kind in FileOperationKind.values) {
    test(
      'verified ${kind.name} removes consumed stages before source cleanup',
      () async {
        final fixture = await scenario(kind: kind, stageCount: 2);
        final recovery = await fixture.recover();
        expect(recovery.preview.issues, isEmpty);
        await JournaledTransferRunner(recovery.journal).execute(
          'cleanup',
          recovery.preview.plan,
          control: FileOperationControl(),
          onPhase: (_, phase) {
            if (phase == 'deletingSource') {
              expect(
                fixture.stages.every((stage) => !stage.existsSync()),
                isTrue,
              );
            }
          },
        );
        expect(
          recovery.journal.job('cleanup')!.status,
          TransferJobStatus.completed,
        );
        expect(await fixture.destination.readAsBytes(), fixture.content);
        expect(await fixture.original.exists(), kind != FileOperationKind.move);
        for (final stage in fixture.stages) {
          expect(await stage.exists(), isFalse);
          expect(await stage.parent.exists(), isFalse);
        }
        final state = recovery.journal.job('cleanup')!.entries.single.recovery;
        expect(state['retainedStagePaths'], isEmpty);
        expect(state.containsKey('resumeStagePath'), isFalse);
        expect(state.containsKey('stagedPath'), isFalse);
      },
    );
  }

  for (final mutation in [
    'stage bytes',
    'destination bytes',
    'unrelated entry',
    'directory symlink',
  ]) {
    test(
      '$mutation after publication preserves unconfirmed recovery data and the move source',
      () async {
        final fixture = await scenario(kind: FileOperationKind.move);
        final recovery = await fixture.recover();
        final stage = fixture.stages.single;
        final originalPrefix = await stage.readAsBytes();
        var mutated = false;
        String? heldDirectory;
        await JournaledTransferRunner(recovery.journal).execute(
          'cleanup',
          recovery.preview.plan,
          control: FileOperationControl(),
          onPhase: (_, phase) {
            if (phase != 'cleaningPartial' || mutated) return;
            mutated = true;
            switch (mutation) {
              case 'stage bytes':
                final modified = stage.lastModifiedSync();
                final bytes = stage.readAsBytesSync()..[0] ^= 1;
                stage.writeAsBytesSync(bytes, flush: true);
                stage.setLastModifiedSync(modified);
              case 'destination bytes':
                final modified = fixture.destination.lastModifiedSync();
                final bytes = fixture.destination.readAsBytesSync()
                  ..[fixture.content.length - 1] ^= 1;
                fixture.destination.writeAsBytesSync(bytes, flush: true);
                fixture.destination.setLastModifiedSync(modified);
              case 'unrelated entry':
                File(p.join(stage.parent.path, 'keep.txt'))
                    .writeAsStringSync('independent file', flush: true);
              case 'directory symlink':
                heldDirectory = p.join(
                  fixture.root.path,
                  'retained-original-directory',
                );
                stage.parent.renameSync(heldDirectory!);
                Link(stage.parent.path).createSync(heldDirectory!);
            }
          },
        );
        final job = recovery.journal.job('cleanup')!;
        expect(mutated, isTrue);
        expect(job.status, TransferJobStatus.failed);
        expect(job.entries.single.message, contains('copy was published'));
        expect(
          job.entries.single.recovery['retainedStagePaths'],
          contains(stage.path),
        );
        expect(job.entries.single.recovery['partialCleanupError'], isNotNull);
        expect(await fixture.original.readAsBytes(), fixture.content);
        if (mutation == 'stage bytes') {
          expect(await stage.readAsBytes(), isNot(originalPrefix));
        } else if (mutation == 'directory symlink') {
          expect(await Link(stage.parent.path).exists(), isTrue);
          expect(
            await File(p.join(heldDirectory!, 'payload')).readAsBytes(),
            originalPrefix,
          );
        } else {
          expect(await stage.readAsBytes(), originalPrefix);
        }
        if (mutation == 'unrelated entry') {
          expect(
            await File(p.join(stage.parent.path, 'keep.txt')).readAsString(),
            'independent file',
          );
          // Explicitly removing the unrelated entry makes a later confirmed-copy
          // recovery clean only the known payload and complete source deletion.
          await File(p.join(stage.parent.path, 'keep.txt')).delete();
          final retry = await fixture.recover();
          expect(retry.preview.issues, isEmpty);
          expect(
            retry.preview.plan.entries.single.recovery?['resumeAfterCommit'],
            isTrue,
          );
          await JournaledTransferRunner(retry.journal).execute(
            'cleanup',
            retry.preview.plan,
            control: FileOperationControl(),
          );
          expect(
            retry.journal.job('cleanup')!.status,
            TransferJobStatus.completed,
          );
          expect(await stage.parent.exists(), isFalse);
          expect(await fixture.original.exists(), isFalse);
        }
      },
      skip: Platform.isWindows && mutation == 'directory symlink',
    );
  }

  test(
    'a payload symlink is refused without following or deleting its target',
    () async {
      final fixture = await scenario();
      final recovery = await fixture.recover();
      final stage = fixture.stages.single;
      final unrelated = File(p.join(fixture.root.path, 'unrelated.bin'));
      await unrelated.writeAsBytes(
        fixture.content.sublist(0, 8193),
        flush: true,
      );
      var changed = false;
      await JournaledTransferRunner(recovery.journal).execute(
        'cleanup',
        recovery.preview.plan,
        control: FileOperationControl(),
        onPhase: (_, phase) {
          if (phase == 'cleaningPartial' && !changed) {
            changed = true;
            stage.deleteSync();
            Link(stage.path).createSync(unrelated.path);
          }
        },
      );
      expect(recovery.journal.job('cleanup')!.status, TransferJobStatus.failed);
      expect(await Link(stage.path).exists(), isTrue);
      expect(await unrelated.readAsBytes(), fixture.content.sublist(0, 8193));
    },
    skip: Platform.isWindows,
  );

  for (final interrupt in ['cancel', 'source failure']) {
    test(
      '$interrupt and a subsequent empty retry retain every prior stage until confirmed publication',
      () async {
        final fixture = await scenario();
        final first = await fixture.recover();
        final old = fixture.stages.single;
        final oldBytes = await old.readAsBytes();
        final control = FileOperationControl();
        if (interrupt == 'source failure') {
          fixture.source.failAfterRangeBytes = 4097;
        }
        await JournaledTransferRunner(first.journal).execute(
          'cleanup',
          first.preview.plan,
          control: control,
          onProgress: (_, count, _) {
            if (interrupt == 'cancel' && count > oldBytes.length) {
              scheduleMicrotask(control.cancel);
            }
          },
        );
        final firstEntry = first.journal.job('cleanup')!.entries.single;
        expect(
          firstEntry.outcome,
          interrupt == 'cancel'
              ? FileOperationOutcome.cancelled
              : FileOperationOutcome.failed,
        );
        final newer = File(firstEntry.recovery['stagedPath'] as String);
        final newerBytes = await newer.readAsBytes();
        expect(newerBytes.length, greaterThan(oldBytes.length));
        expect(newerBytes.length, lessThan(fixture.content.length));
        expect(newerBytes, fixture.content.sublist(0, newerBytes.length));
        expect(await old.readAsBytes(), oldBytes);
        expect(
          firstEntry.recovery['retainedStagePaths'],
          containsAll([old.path, newer.path]),
        );
        expect(await fixture.destination.exists(), isFalse);

        fixture.source.failAfterRangeBytes = null;
        final emptyRetry = await fixture.recover();
        expect(
          emptyRetry.preview.plan.entries.single.recovery?['resumeStagePath'],
          newer.path,
        );
        final emptyControl = FileOperationControl();
        await JournaledTransferRunner(emptyRetry.journal).execute(
          'cleanup',
          emptyRetry.preview.plan,
          control: emptyControl,
          onPhase: (_, phase) {
            if (phase == 'staging') emptyControl.cancel();
          },
        );
        final emptyEntry = emptyRetry.journal.job('cleanup')!.entries.single;
        final emptyPath = emptyEntry.recovery['stagedPath'] as String;
        expect(await File(emptyPath).exists(), isFalse);
        expect(
          emptyEntry.recovery['retainedStagePaths'],
          containsAll([old.path, newer.path, emptyPath]),
        );
        expect(await old.readAsBytes(), oldBytes);
        expect(await newer.readAsBytes(), newerBytes);

        final finalRetry = await fixture.recover();
        expect(finalRetry.preview.issues, isEmpty);
        expect(
          finalRetry.preview.plan.entries.single.recovery?['resumeStagePath'],
          newer.path,
        );
        await JournaledTransferRunner(finalRetry.journal).execute(
          'cleanup',
          finalRetry.preview.plan,
          control: FileOperationControl(),
        );
        expect(
          finalRetry.journal.job('cleanup')!.status,
          TransferJobStatus.completed,
        );
        expect(await fixture.destination.readAsBytes(), fixture.content);
        expect(await old.parent.exists(), isFalse);
        expect(await newer.parent.exists(), isFalse);
        expect(
          finalRetry.journal
              .job('cleanup')!
              .entries
              .single
              .recovery['retainedStagePaths'],
          isEmpty,
        );
      },
    );
  }

  test('an empty newest stage after a crash preserves and resumes the older prefix', () async {
    final fixture = await scenario(stageCount: 2);
    final old = fixture.stages.first;
    final empty = fixture.stages.last;
    final oldBytes = await old.readAsBytes();
    await empty.writeAsBytes([], flush: true);
    final recovery = await fixture.recover();
    expect(recovery.preview.issues, isEmpty);
    final entry = recovery.preview.plan.entries.single;
    expect(entry.recovery?['resumeStagePath'], old.path);
    expect(
      entry.recovery?['retainedStagePaths'],
      containsAll([old.path, empty.path]),
    );
    expect(await old.readAsBytes(), oldBytes);
    expect(await empty.exists(), isTrue);
    await JournaledTransferRunner(recovery.journal).execute(
      'cleanup',
      recovery.preview.plan,
      control: FileOperationControl(),
    );
    expect(
      recovery.journal.job('cleanup')!.status,
      TransferJobStatus.completed,
    );
    expect(await fixture.destination.readAsBytes(), fixture.content);
    for (final stage in fixture.stages) {
      expect(await stage.parent.exists(), isFalse);
    }
    expect(
      recovery.journal
          .job('cleanup')!
          .entries
          .single
          .recovery['retainedStagePaths'],
      isEmpty,
    );
  });

  for (final replacement in ['directory', 'symlink']) {
    test(
      'an empty $replacement candidate cannot hide behind an older verified prefix',
      () async {
        final fixture = await scenario(stageCount: 2);
        final newer = fixture.stages.last;
        await newer.delete();
        if (replacement == 'directory') {
          await Directory(newer.path).create();
        } else {
          final empty = File(p.join(fixture.root.path, 'empty.bin'));
          await empty.writeAsBytes([], flush: true);
          await Link(newer.path).create(empty.path);
        }
        final recovery = await fixture.recover();
        expect(recovery.preview.issues, isNotEmpty);
        expect(
          recovery.preview.plan.entries.single.recovery?['resumeStagePath'],
          isNull,
        );
        expect(
          recovery.preview.plan.entries.single.recovery?['retainedStagePaths'],
          containsAll(fixture.stages.map((stage) => stage.path)),
        );
        expect(await fixture.stages.first.exists(), isTrue);
        expect(await fixture.destination.exists(), isFalse);
      },
      skip: Platform.isWindows && replacement == 'symlink',
    );
  }

  for (final phase in ['cleaningPartial', 'partialCleaned']) {
    test(
      'journal failure at $phase retains cleanup references for another reviewed recovery',
      () async {
        final store = _FailCleanupCheckpoint(phase);
        final fixture = await scenario(storage: store);
        final stage = fixture.stages.single;
        final recovery = await fixture.recover();
        await JournaledTransferRunner(recovery.journal).execute(
          'cleanup',
          recovery.preview.plan,
          control: FileOperationControl(),
        );
        final job = recovery.journal.job('cleanup')!;
        expect(store.rejected, isTrue);
        expect(job.status, TransferJobStatus.failed);
        expect(
          job.entries.single.recovery['retainedStagePaths'],
          contains(stage.path),
        );
        expect(await fixture.destination.readAsBytes(), fixture.content);
        expect(await stage.exists(), phase == 'cleaningPartial');
        final retry = await fixture.recover();
        expect(retry.preview.issues, isEmpty);
        await JournaledTransferRunner(retry.journal).execute(
          'cleanup',
          retry.preview.plan,
          control: FileOperationControl(),
        );
        expect(
          retry.journal.job('cleanup')!.status,
          TransferJobStatus.completed,
        );
        expect(await stage.parent.exists(), isFalse);
      },
    );
  }

  test('retained stage count limit blocks new data without forgetting previous files', () async {
    final fixture = await scenario(stageCount: maxRetainedTransferStages);
    final recovery = await fixture.recover();
    expect(recovery.preview.issues, isEmpty);
    await JournaledTransferRunner(recovery.journal).execute(
      'cleanup',
      recovery.preview.plan,
      control: FileOperationControl(),
    );
    final job = recovery.journal.job('cleanup')!;
    expect(job.status, TransferJobStatus.failed);
    expect(
      job.entries.single.message,
      contains('Too many retained partial files'),
    );
    expect(
      job.entries.single.recovery['retainedStagePaths'],
      fixture.stages.map((file) => file.path).toList(),
    );
    for (final stage in fixture.stages) {
      expect(await stage.exists(), isTrue);
    }
    expect(await fixture.destination.exists(), isFalse);
  });

  test(
    'retained path budget counts UTF-8 bytes and rejects malformed lists',
    () {
      expect(
        () => retainedTransferStagePaths({
          'retainedStagePaths': ['é' * 33000],
        }),
        throwsStateError,
      );
      expect(
        () => retainedTransferStagePaths({'retainedStagePaths': 'not a list'}),
        throwsStateError,
      );
      expect(
        () => retainedTransferStagePaths({
          'retainedStagePaths': [null],
        }),
        throwsStateError,
      );
    },
  );

  test('an unsafe older stage path blocks recovery even when the newest prefix is valid', () async {
    final fixture = await scenario();
    final stored = TransferJournal(fixture.storage);
    await stored.initialize();
    final saved = stored.job('cleanup')!.entries.single;
    final entry = FileOperationEntry(saved.source, saved.destination)
      ..outcome = FileOperationOutcome.failed
      ..recovery = {
        ...saved.recovery,
        'retainedStagePaths': [
          fixture.original.path,
          fixture.stages.single.path,
        ],
      };
    await stored.checkpoint('cleanup', 0, entry, 'failed');
    final recovery = await fixture.recover();
    expect(recovery.preview.issues, isNotEmpty);
    expect(await fixture.original.readAsBytes(), fixture.content);
    expect(await fixture.stages.single.exists(), isTrue);
    expect(await fixture.destination.exists(), isFalse);
  });
}

class _Scenario {
  _Scenario(
    this.root,
    this.original,
    this.destination,
    this.content,
    this.source,
    this.target,
    this.storage,
    this.stages,
  );
  final Directory root;
  final File original;
  final File destination;
  final Uint8List content;
  final _InterruptedRangeSource source;
  final LocalOperationBackend target;
  final MemoryTransferJournalStorage storage;
  final List<File> stages;

  Future<({TransferJournal journal, TransferRecoveryPreview preview})>
  recover() async {
    final journal = TransferJournal(storage);
    await journal.initialize();
    final preview = await const TransferRecoveryService().prepare(
      journal.job('cleanup')!,
      source: source,
      destination: target,
      control: FileOperationControl(),
    );
    return (journal: journal, preview: preview);
  }
}

class _InterruptedRangeSource extends LocalOperationBackend {
  _InterruptedRangeSource() : super(LocalFileService(), isCurrent: () => true);
  int? failAfterRangeBytes;

  @override
  Stream<List<int>> readRange(FileItem file, int offset) async* {
    var remaining = failAfterRangeBytes;
    await for (final chunk in super.readRange(file, offset)) {
      if (remaining == null) {
        yield chunk;
      } else {
        final count = chunk.length < remaining ? chunk.length : remaining;
        yield chunk.sublist(0, count);
        remaining -= count;
        if (remaining == 0) throw StateError('Fixture range interrupted.');
      }
    }
  }
}

class _FailCleanupCheckpoint extends MemoryTransferJournalStorage {
  _FailCleanupCheckpoint(this.phase);
  final String phase;
  bool rejected = false;
  @override
  Future<void> append(String line) async {
    final event = decodeTransferEvent(line);
    if (!rejected &&
        event['kind'] == 'entries' &&
        (event['entries'] as List).any((entry) => entry['phase'] == phase)) {
      rejected = true;
      throw StateError('Fixture journal confirmation unavailable.');
    }
    await super.append(line);
  }
}
