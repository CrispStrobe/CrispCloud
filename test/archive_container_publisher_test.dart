import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/archive_publication_lease_io.dart';
import 'package:crisp_cloud/services/archive_publication_cleanup_io.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_endpoint_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });
  final original = Uint8List.fromList(List.generate(32811, (i) => i % 251));
  final candidate = Uint8List.fromList(
    List.generate(49199, (i) => (i * 17) % 253),
  );
  late ArchiveEndpointTestBackend backend;
  late MemoryFileCollectionStorage storage;
  late ArchivePublicationJournal journal;
  late ArchiveContainerPublisher publisher;
  setUp(() {
    backend = ArchiveEndpointTestBackend()..put('/out/work.zip', original);
    storage = MemoryFileCollectionStorage();
    journal = ArchivePublicationJournal(storage: storage);
    publisher = ArchiveContainerPublisher(backend, journal);
  });
  Future<ArchivePublicationReceipt> publish({
    bool Function()? cancelled,
    void Function(ArchivePublicationPhase)? phase,
    ArchivePublicationRecord? retry,
  }) async => publisher.publish(
    original: (await backend.stat('/out/work.zip'))!,
    originalSha256: sha256.convert(original).toString(),
    bytes: candidate,
    isCancelled: cancelled,
    onPhase: phase,
    retry: retry,
  );

  test('publication checkpoints precede exact moves and preserve mode until verified cleanup', () async {
    backend.before = (action, path, destination) async {
      if (action != 'move' && action != 'delete') return;
      final durable = ArchivePublicationJournal(storage: storage);
      await durable.initialize();
      final record = durable.records.single;
      expect(record.originalSha256, sha256.convert(original).toString());
      if (action == 'delete') {
        expect(record.phase, ArchivePublicationPhase.cleaningBackup);
        expect(backend.files['/out/work.zip'], candidate);
      } else {
        expect(
          record.phase,
          path.endsWith('.candidate')
              ? ArchivePublicationPhase.installing
              : ArchivePublicationPhase.backingUp,
        );
      }
    };
    final result = await publish();
    expect(result.cleanupPending, isFalse);
    expect(result.record.phase, ArchivePublicationPhase.complete);
    expect(backend.files.keys, ['/out/work.zip']);
    expect(backend.files['/out/work.zip'], candidate);
    expect(backend.modes['/out/work.zip'], 0x180);
    await publisher.verifyReceipt(result);
  });

  test('unsupported publication has no staging or original mutation', () async {
    backend.publicationSupported = false;
    await expectLater(publish(), throwsUnsupportedError);
    expect(backend.files['/out/work.zip'], original);
    expect(backend.mutations, isEmpty);
  });

  test(
    'an unacknowledged durable intent stops before moving the original',
    () async {
      final failing = _FailIntentStorage(ArchivePublicationPhase.backingUp);
      journal = ArchivePublicationJournal(storage: failing);
      publisher = ArchiveContainerPublisher(backend, journal);
      await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
      expect(failing.rejected, isTrue);
      expect(backend.files['/out/work.zip'], original);
      expect(
        backend.mutations.where((value) => value.startsWith('move:')),
        isEmpty,
      );
      final recovered = ArchivePublicationJournal(storage: failing);
      await recovered.initialize();
      expect(
        recovered.records.single.phase,
        ArchivePublicationPhase.candidateWritten,
      );
    },
  );

  test(
    'a lost journal acknowledgement is accepted only after exact readback',
    () async {
      final lost = _FailIntentStorage(
        ArchivePublicationPhase.backingUp,
        afterCommit: true,
      );
      journal = ArchivePublicationJournal(storage: lost);
      publisher = ArchiveContainerPublisher(backend, journal);
      final receipt = await publish();
      expect(lost.rejected, isTrue);
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
      expect(backend.files['/out/work.zip'], candidate);
    },
  );

  test('failure installing restores original and a retained candidate can be retried', () async {
    var reject = true;
    backend.before = (action, path, destination) {
      if (reject && action == 'move' && path.endsWith('.candidate')) {
        reject = false;
        throw StateError('Fixture install failed.');
      }
    };
    await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
    expect(backend.files['/out/work.zip'], original);
    final failed = publisher.activeRecord!;
    expect(failed.phase, ArchivePublicationPhase.restored);
    expect(backend.files[failed.candidatePath(backend.paths)], candidate);
    final receipt = await publish(retry: failed);
    expect(receipt.cleanupPending, isFalse);
    expect(backend.files.keys, ['/out/work.zip']);
    expect(backend.files['/out/work.zip'], candidate);
  });

  test('cancellation after original backup restores original and retains draft evidence', () async {
    var cancelled = false;
    await expectLater(
      publish(
        cancelled: () => cancelled,
        phase: (phase) {
          if (phase == ArchivePublicationPhase.backedUp) cancelled = true;
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.files['/out/work.zip'], original);
    final record = publisher.activeRecord!;
    expect(backend.files[record.candidatePath(backend.paths)], candidate);
    expect(record.phase, ArchivePublicationPhase.restored);
  });

  test('lost install reply is unconfirmed until restart reconciliation verifies publication', () async {
    var lose = true;
    backend.after = (action, path, destination) {
      if (lose && action == 'move' && path.endsWith('.candidate')) {
        lose = false;
        throw StateError('Fixture install acknowledgement lost.');
      }
    };
    await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
    final reopened = ArchivePublicationJournal(storage: storage);
    await reopened.initialize();
    final record = reopened.records.single;
    expect(record.phase, ArchivePublicationPhase.installing);
    expect(backend.files[record.backupPath(backend.paths)], original);
    final recovery = ArchiveContainerPublisher(backend, reopened);
    final inspection = await recovery.inspect(record);
    expect(inspection.canFinish, isTrue);
    expect(inspection.canRestore, isFalse);
    final receipt = await recovery.recover(
      record,
      ArchiveRecoveryAction.finishPublication,
    );
    expect(receipt, isNotNull);
    expect(receipt!.cleanupPending, isFalse);
    expect(backend.files.keys, ['/out/work.zip']);
  });

  test(
    'concurrent original mutation is not overwritten by a staged candidate',
    () async {
      final replacement = Uint8List.fromList([9, 8, 7]);
      backend.before = (action, path, destination) {
        if (action == 'write') backend.put('/out/work.zip', replacement);
      };
      await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
      expect(backend.files['/out/work.zip'], replacement);
      expect(
        backend.mutations.where((value) => value.startsWith('move:')),
        isEmpty,
      );
    },
  );

  test('a concurrent original name during install is preserved alongside the original backup', () async {
    final external = Uint8List.fromList([4, 3, 2]);
    backend.before = (action, path, destination) {
      if (action == 'move' && path.endsWith('.candidate')) {
        backend.put('/out/work.zip', external);
      }
    };
    await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
    final record = publisher.activeRecord!;
    expect(backend.files['/out/work.zip'], external);
    expect(backend.files[record.backupPath(backend.paths)], original);
    expect(backend.files[record.candidatePath(backend.paths)], candidate);
    final inspection = await publisher.inspect(record);
    expect(inspection.canFinish, isFalse);
    expect(inspection.canRestore, isFalse);
  });

  test('changed backup after publication is retained with a truthful cleanup warning', () async {
    final changed = Uint8List.fromList([44, 55]);
    final receipt = await publish(
      phase: (phase) {
        if (phase == ArchivePublicationPhase.published) {
          backend.put(
            publisher.activeRecord!.backupPath(backend.paths),
            changed,
          );
        }
      },
    );
    expect(receipt.cleanupPending, isTrue);
    expect(backend.files['/out/work.zip'], candidate);
    expect(backend.files[receipt.record.backupPath(backend.paths)], changed);
    expect(receipt.record.phase, ArchivePublicationPhase.published);
  });

  test('recovery refuses another account and symbolic recovery files without mutation', () async {
    var cancelled = false;
    await expectLater(
      publish(
        cancelled: () => cancelled,
        phase: (phase) {
          if (phase == ArchivePublicationPhase.candidateWritten) {
            cancelled = true;
          }
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    final record = publisher.activeRecord!;
    final before = List<String>.of(backend.mutations);
    backend.account = 'replacement-account';
    await expectLater(publisher.inspect(record), throwsStateError);
    backend.account = 'archive-fixture';
    backend.links.add(record.candidatePath(backend.paths));
    await expectLater(publisher.inspect(record), throwsStateError);
    expect(backend.mutations, before);
  });

  test('explicit restore after restart retains original and cleans only the verified candidate', () async {
    var cancelled = false;
    await expectLater(
      publish(
        cancelled: () => cancelled,
        phase: (phase) {
          if (phase == ArchivePublicationPhase.candidateWritten) {
            cancelled = true;
          }
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    final journal2 = ArchivePublicationJournal(storage: storage);
    await journal2.initialize();
    final recovery = ArchiveContainerPublisher(backend, journal2);
    final result = await recovery.recover(
      journal2.records.single,
      ArchiveRecoveryAction.restoreOriginal,
    );
    expect(result, isNull);
    expect(journal2.records.single.phase, ArchivePublicationPhase.discarded);
    expect(backend.files.keys, ['/out/work.zip']);
    expect(backend.files['/out/work.zip'], original);
  });
  test('a failed install intent revokes restoration authority until explicit recovery', () async {
    final failing = _FailIntentStorage(ArchivePublicationPhase.installing);
    journal = ArchivePublicationJournal(storage: failing);
    publisher = ArchiveContainerPublisher(backend, journal);
    await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
    expect(backend.files.containsKey('/out/work.zip'), isFalse);
    final saved = ArchivePublicationJournal(storage: failing);
    await saved.initialize();
    final record = saved.records.single;
    expect(record.phase, ArchivePublicationPhase.backedUp);
    expect(backend.files[record.backupPath(backend.paths)], original);
    expect(
      backend.mutations.where((item) => item.startsWith('move:')).length,
      1,
    );
    final recovered = await ArchiveContainerPublisher(
      backend,
      saved,
    ).recover(record, ArchiveRecoveryAction.restoreOriginal);
    expect(recovered, isNull);
    expect(backend.files['/out/work.zip'], original);
  });

  test('the publication lease excludes concurrent recovery even with a shared journal instance', () async {
    final paused = Completer<void>(), release = Completer<void>();
    backend.before = (action, path, destination) async {
      if (action == 'move' && path == '/out/work.zip') {
        paused.complete();
        await release.future;
      }
    };
    final active = publish();
    await paused.future;
    final before = List<String>.of(backend.mutations);
    final second = ArchiveContainerPublisher(backend, journal);
    await expectLater(
      second.recover(
        publisher.activeRecord!,
        ArchiveRecoveryAction.finishPublication,
      ),
      throwsStateError,
    );
    expect(backend.mutations, before);
    release.complete();
    expect((await active).cleanupPending, isFalse);
  });

  test(
    'journal updates require the exact expected record as well as catalog CAS',
    () async {
      final result = await publish();
      final saved = result.record;
      await expectLater(
        journal.write(
          saved.copyWith(phase: ArchivePublicationPhase.published),
          expected: saved.copyWith(phase: ArchivePublicationPhase.backedUp),
        ),
        throwsStateError,
      );
      expect(journal.records.single.phase, ArchivePublicationPhase.complete);
    },
  );

  test('providers without conditional deletion retain backup evidence after verified publication', () async {
    backend.conditionalCleanup = false;
    final receipt = await publish();
    expect(receipt.cleanupPending, isTrue);
    expect(backend.files['/out/work.zip'], candidate);
    expect(backend.files[receipt.record.backupPath(backend.paths)], original);
    expect(
      backend.mutations.where((item) => item.startsWith('delete:')),
      isEmpty,
    );
    final saved = ArchivePublicationJournal(storage: storage);
    await saved.initialize();
    expect(saved.records.single.backup, isNotNull);
    backend.files.remove(receipt.record.backupPath(backend.paths));
    final complete = await ArchiveContainerPublisher(
      backend,
      saved,
    ).recover(saved.records.single, ArchiveRecoveryAction.finishPublication);
    expect(complete!.cleanupPending, isFalse);
  });

  test(
    'a changed recovery revision at conditional deletion is preserved',
    () async {
      final changed = Uint8List.fromList([3, 8, 3]);
      backend.before = (action, path, destination) {
        if (action == 'delete') backend.put(path, changed);
      };
      final receipt = await publish();
      expect(receipt.cleanupPending, isTrue);
      expect(backend.files[receipt.record.backupPath(backend.paths)], changed);
      expect(backend.files['/out/work.zip'], candidate);
    },
  );

  test('native publication retains outer permissions and cleans only exact recovery files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-archive-publication-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'work.zip'));
    await file.writeAsBytes(original, flush: true);
    final local = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    if (!local.capabilities.noReplaceMove) return;
    if (local.capabilities.permissions) {
      await local.writeMetadata(file.path, const TransferMetadata(mode: 0x1a0));
    }
    final current = (await local.stat(file.path))!;
    final native = ArchiveContainerPublisher(
      local,
      ArchivePublicationJournal(storage: MemoryFileCollectionStorage()),
    );
    final receipt = await native.publish(
      original: current,
      originalSha256: sha256.convert(original).toString(),
      bytes: candidate,
    );
    expect(receipt.cleanupPending, isFalse);
    expect(await file.readAsBytes(), candidate);
    if (local.capabilities.permissions) {
      expect((await file.stat()).mode & 0xfff, 0x1a0);
    }
    expect(
      await directory.list().map((entry) => p.basename(entry.path)).toList(),
      ['work.zip'],
    );
  });

  test(
    'native publication leases exclude a second owner and release on close',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-archive-lease-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'transaction.lock');
      final first = await acquireNativeArchivePublicationLease(path);
      expect(first, isNotNull);
      expect(await acquireNativeArchivePublicationLease(path), isNull);
      first!.close();
      final next = await acquireNativeArchivePublicationLease(path);
      expect(next, isNotNull);
      next!.close();
    },
  );
  test(
    'a provider without proven access policy cannot stage any archive bytes',
    () async {
      backend.accessPolicySupported = false;
      await expectLater(publish(), throwsUnsupportedError);
      expect(backend.mutations, isEmpty);
      expect(backend.files['/out/work.zip'], original);
    },
  );

  test(
    'candidate siblings have the original mode before becoming visible',
    () async {
      backend.modes['/out/work.zip'] = 0x100;
      backend.after = (action, path, destination) {
        if (action == 'write') expect(backend.modes[path], 0x100);
      };
      final receipt = await publish();
      expect(
        receipt.record.accessPolicySha256,
        matches(RegExp(r'^[a-f0-9]{64}$')),
      );
      expect(backend.modes['/out/work.zip'], 0x100);
    },
  );

  test('an original access-policy change refuses backup even when bytes and revision agree', () async {
    await expectLater(
      publish(
        phase: (phase) {
          if (phase == ArchivePublicationPhase.candidateWritten) {
            backend.modes['/out/work.zip'] = 0x1a4;
          }
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.files['/out/work.zip'], original);
    expect(backend.modes['/out/work.zip'], 0x1a4);
    expect(
      backend.mutations.where((entry) => entry.startsWith('move:')),
      isEmpty,
    );
  });

  test('candidate access-policy remutation before install restores original and retains candidate', () async {
    await expectLater(
      publish(
        phase: (phase) {
          if (phase == ArchivePublicationPhase.installing) {
            backend.modes[publisher.activeRecord!.candidatePath(
                  backend.paths,
                )] =
                0x1ff;
          }
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.files['/out/work.zip'], original);
    expect(backend.modes['/out/work.zip'], 0x180);
    expect(
      backend.files[publisher.activeRecord!.candidatePath(backend.paths)],
      candidate,
    );
  });
  test('native cleanup refuses a growing recovery file without deleting either copy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-archive-growing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final backup = File(p.join(directory.path, 'recovery.original'));
    final published = File(p.join(directory.path, 'work.zip'));
    await backup.writeAsBytes(original, flush: true);
    await published.writeAsBytes(candidate, flush: true);
    final local = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final recoveryFile = (await local.stat(backup.path))!;
    final publishedFile = (await local.stat(published.path))!;
    var checkpoints = 0;
    await expectLater(
      deleteNativeArchiveRecoveryFile(
        local,
        recoveryFile,
        publishedFile,
        recoverySha256: sha256.convert(original).toString(),
        publishedSha256: sha256.convert(candidate).toString(),
        checkpoint: () async {
          if (++checkpoints == 2) {
            await backup.writeAsBytes(
              Uint8List(2 * 1024 * 1024),
              mode: FileMode.append,
              flush: true,
            );
          }
        },
      ),
      throwsStateError,
    );
    expect(await backup.exists(), isTrue);
    expect(await published.readAsBytes(), candidate);
    expect(checkpoints, lessThan(20));
  });
}

class _FailIntentStorage extends MemoryFileCollectionStorage {
  _FailIntentStorage(this.phase, {this.afterCommit = false});
  final ArchivePublicationPhase phase;
  final bool afterCommit;
  bool rejected = false;
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final data = jsonDecode(value) as Map;
    if (!rejected &&
        (data['records'] as List).any(
          (entry) => entry['phase'] == phase.name,
        )) {
      rejected = true;
      if (afterCommit) await super.compareAndSwap(key, expected, value);
      throw StateError('Fixture journal acknowledgement failure.');
    }
    return super.compareAndSwap(key, expected, value);
  }
}
