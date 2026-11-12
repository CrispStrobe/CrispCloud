import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/archive_endpoint_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
  final candidate = Uint8List.fromList([5, 6]);
  final destinationBytes = Uint8List.fromList([9, 8, 1, 2, 3, 4]);
  late ArchiveEndpointTestBackend backend;
  late MemoryFileCollectionStorage storage;
  late ArchivePublicationJournal journal;
  late ArchiveContainerPublisher publisher;
  late ArchivePublicationReceipt destinationReceipt;
  late ArchivePublicationDependency dependency;

  setUp(() async {
    backend = ArchiveEndpointTestBackend()
      ..put('/input/source.zip', original)
      ..put('/out/destination.zip', [9, 8]);
    storage = MemoryFileCollectionStorage();
    journal = ArchivePublicationJournal(storage: storage);
    destinationReceipt = await ArchiveContainerPublisher(backend, journal)
        .publish(
          original: (await backend.stat('/out/destination.zip'))!,
          originalSha256: sha256.convert([9, 8]).toString(),
          bytes: destinationBytes,
        );
    dependency = ArchivePublicationDependency.fromReceipt(destinationReceipt);
    publisher = ArchiveContainerPublisher(backend, journal);
    backend.mutations.clear();
  });

  Future<ArchivePublicationReceipt> publish({
    ArchivePublicationRecord? retry,
    void Function(ArchivePublicationPhase)? onPhase,
    bool Function()? isCancelled,
  }) async => publisher.publish(
    original: (await backend.stat('/input/source.zip'))!,
    originalSha256: sha256.convert(original).toString(),
    bytes: candidate,
    dependency: retry == null ? dependency : null,
    retry: retry,
    onPhase: onPhase,
    isCancelled: isCancelled,
  );

  Future<ArchivePublicationRecord> reopenRecord() async {
    final reopened = ArchivePublicationJournal(storage: storage);
    await reopened.initialize();
    journal = reopened;
    publisher = ArchiveContainerPublisher(backend, journal);
    return journal.records.singleWhere(
      (record) => record.original.path == '/input/source.zip',
    );
  }

  Future<ArchivePublicationRecord> interruptAfterStage() async {
    await expectLater(
      publish(
        onPhase: (phase) {
          if (phase == ArchivePublicationPhase.candidateWritten) {
            throw StateError('Stop after a durably verified candidate.');
          }
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    return reopenRecord();
  }

  Future<ArchivePublicationRecord> loseInstallationReply() async {
    var fired = false;
    backend.after = (action, path, destination) {
      if (!fired &&
          action == 'move' &&
          path.endsWith('.candidate') &&
          destination == '/input/source.zip') {
        fired = true;
        throw StateError('Lost installation acknowledgement.');
      }
    };
    await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
    backend.after = null;
    final record = await reopenRecord();
    expect(backend.files['/input/source.zip'], candidate);
    expect(backend.files[record.backupPath(backend.paths)], original);
    return record;
  }

  test(
    'source intent retains a v2 destination dependency after receipt pruning',
    () async {
      backend.before = (action, path, destination) async {
        if (action != 'move' && action != 'delete') return;
        final durable = ArchivePublicationJournal(storage: storage);
        await durable.initialize();
        final record = durable.records.single;
        expect(record.original.path, '/input/source.zip');
        expect(record.toJson()['version'], 2);
        expect(record.dependency!.receiptId, destinationReceipt.record.id);
        expect(
          record.dependency!.sha256,
          sha256.convert(destinationBytes).toString(),
        );
      };
      final receipt = await publish();
      expect(receipt.cleanupPending, isFalse);
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
      expect(receipt.record.dependency!.toJson(), dependency.toJson());
      expect(backend.files['/input/source.zip'], candidate);
      expect(backend.files['/out/destination.zip'], destinationBytes);
      await publisher.verifyReceipt(receipt);
    },
  );

  test('dependency and guarded record round-trip without passwords', () async {
    final record = await interruptAfterStage();
    final json =
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;
    final decoded = ArchivePublicationRecord.fromJson(json);
    expect(decoded.toJson(), record.toJson());
    expect(
      decoded
          .copyWith(phase: ArchivePublicationPhase.needsReview)
          .dependency!
          .toJson(),
      dependency.toJson(),
    );
    expect(jsonEncode(json).toLowerCase(), isNot(contains('password')));
    expect(jsonEncode(json).toLowerCase(), isNot(contains('token')));
  });

  for (final malformed in [
    'v1 with dependency',
    'v2 without dependency',
    'future version',
  ]) {
    test('guarded recovery refuses $malformed', () async {
      final record = await interruptAfterStage();
      final json = Map<String, dynamic>.of(record.toJson());
      if (malformed == 'v1 with dependency') json['version'] = 1;
      if (malformed == 'v2 without dependency') json.remove('dependency');
      if (malformed == 'future version') json['version'] = 3;
      expect(
        () => ArchivePublicationRecord.fromJson(json),
        throwsFormatException,
      );
    });
  }

  test('ordinary v1 records remain readable', () {
    final json = destinationReceipt.record.toJson();
    expect(json['version'], 1);
    expect(ArchivePublicationRecord.fromJson(json).dependency, isNull);
  });

  test('an unverified destination cannot authorize a source removal', () {
    final unverified = destinationReceipt.record.copyWith(
      phase: ArchivePublicationPhase.installing,
      clearPublished: true,
    );
    expect(
      () => ArchivePublicationDependency.fromReceipt(
        ArchivePublicationReceipt(
          record: unverified,
          file: destinationReceipt.file,
        ),
      ),
      throwsStateError,
    );
  });

  for (final change in [
    'contents',
    'missing',
    'identity',
    'revision',
    'permissions',
    'symlink',
    'parent symlink',
  ]) {
    test('changed destination $change blocks before source staging', () async {
      switch (change) {
        case 'contents':
          backend.put('/out/destination.zip', [
            9,
            8,
            0,
            0,
            0,
            0,
          ], preserveVersion: true);
        case 'missing':
          backend.files.remove('/out/destination.zip');
        case 'identity':
          backend.ids['/out/destination.zip'] = 'replacement-object';
        case 'revision':
          backend.put('/out/destination.zip', destinationBytes);
        case 'permissions':
          backend.modes['/out/destination.zip'] = 0x1ff;
        case 'symlink':
          backend.links.add('/out/destination.zip');
        case 'parent symlink':
          backend.links.add('/out');
      }
      await expectLater(publish(), throwsStateError);
      expect(backend.files['/input/source.zip'], original);
      expect(backend.mutations, isEmpty);
    });
  }

  for (final phase in [
    ArchivePublicationPhase.prepared,
    ArchivePublicationPhase.candidateWritten,
    ArchivePublicationPhase.backingUp,
    ArchivePublicationPhase.backedUp,
    ArchivePublicationPhase.installing,
    ArchivePublicationPhase.published,
    ArchivePublicationPhase.cleaningBackup,
  ]) {
    test(
      'destination loss at ${phase.name} preserves original source data',
      () async {
        var fired = false;
        await expectLater(
          publish(
            onPhase: (current) {
              if (!fired && current == phase) {
                fired = true;
                backend.files.remove('/out/destination.zip');
              }
            },
          ),
          throwsA(isA<ArchivePublicationException>()),
        );
        expect(fired, isTrue);
        final record = await reopenRecord();
        final originalAtName = backend.files['/input/source.zip'];
        final originalAtBackup =
            backend.files[record.backupPath(backend.paths)];
        expect(
          originalAtName != null &&
                  sha256.convert(originalAtName) == sha256.convert(original) ||
              originalAtBackup != null &&
                  sha256.convert(originalAtBackup) == sha256.convert(original),
          isTrue,
        );
        final inspection = await publisher.inspect(record);
        expect(inspection.canFinish, isFalse);
        expect(inspection.canRestore, isTrue);
        expect(inspection.message, contains('destination'));
        await publisher.recover(record, ArchiveRecoveryAction.restoreOriginal);
        expect(backend.files['/input/source.zip'], original);
        expect(backend.files.keys, ['/input/source.zip']);
        expect(
          publisher.activeRecord!.phase,
          ArchivePublicationPhase.discarded,
        );
      },
    );
  }

  test('restart finishes a verified source candidate only with its destination intact', () async {
    final record = await interruptAfterStage();
    final inspection = await publisher.inspect(record);
    expect(inspection.canFinish, isTrue);
    final receipt = await publisher.recover(
      record,
      ArchiveRecoveryAction.finishPublication,
    );
    expect(receipt!.record.dependency!.toJson(), dependency.toJson());
    expect(receipt.cleanupPending, isFalse);
    expect(backend.files['/input/source.zip'], candidate);
  });

  test(
    'restart refuses source installation after destination replacement',
    () async {
      final record = await interruptAfterStage();
      backend.put('/out/destination.zip', [0]);
      final before = List<String>.of(backend.mutations);
      await expectLater(
        publisher.recover(record, ArchiveRecoveryAction.finishPublication),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(backend.mutations, before);
      expect(backend.files['/input/source.zip'], original);
      expect(backend.files[record.candidatePath(backend.paths)], candidate);
    },
  );

  test(
    'already installed source candidate cannot bypass a lost destination',
    () async {
      final record = await loseInstallationReply();
      backend.files.remove('/out/destination.zip');
      final inspection = await publisher.inspect(record);
      expect(inspection.canFinish, isFalse);
      expect(inspection.canRestore, isTrue);
      await expectLater(
        publisher.recover(record, ArchiveRecoveryAction.finishPublication),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(backend.files[record.backupPath(backend.paths)], original);
      await publisher.recover(
        publisher.activeRecord!,
        ArchiveRecoveryAction.restoreOriginal,
      );
      expect(backend.files['/input/source.zip'], original);
      expect(backend.files.keys, ['/input/source.zip']);
    },
  );

  test('already installed source candidate confirms safely when destination survives', () async {
    final record = await loseInstallationReply();
    final result = await publisher.recover(
      record,
      ArchiveRecoveryAction.finishPublication,
    );
    expect(result!.record.phase, ArchivePublicationPhase.complete);
    expect(backend.files['/input/source.zip'], candidate);
    expect(backend.files['/out/destination.zip'], destinationBytes);
    expect(
      backend.files.containsKey(record.backupPath(backend.paths)),
      isFalse,
    );
  });

  test(
    'explicit guarded restore can retain the destination as a copy',
    () async {
      final record = await loseInstallationReply();
      await publisher.recover(record, ArchiveRecoveryAction.restoreOriginal);
      expect(backend.files['/input/source.zip'], original);
      expect(backend.files['/out/destination.zip'], destinationBytes);
      expect(publisher.activeRecord!.published, isNull);
      expect(publisher.activeRecord!.phase, ArchivePublicationPhase.discarded);
    },
  );

  for (final failedMove in ['retain candidate', 'restore backup']) {
    test('lost $failedMove reply retains restart recovery', () async {
      final record = await loseInstallationReply();
      backend.files.remove('/out/destination.zip');
      var fired = false;
      backend.after = (action, path, destination) {
        if (action != 'move') return;
        final wanted = failedMove == 'retain candidate'
            ? path == '/input/source.zip' && destination!.endsWith('.candidate')
            : path.endsWith('.original') && destination == '/input/source.zip';
        if (!fired && action == 'move' && wanted) {
          fired = true;
          throw StateError('Lost restoration acknowledgement.');
        }
      };
      try {
        await publisher.recover(record, ArchiveRecoveryAction.restoreOriginal);
      } on ArchivePublicationException {
        // A physical move may have succeeded despite the lost reply.
      }
      expect(fired, isTrue);
      backend.after = null;
      final latest = await reopenRecord();
      if (!latest.isFinished) {
        final inspection = await publisher.inspect(latest);
        expect(inspection.canRestore, isTrue);
        await publisher.recover(latest, ArchiveRecoveryAction.restoreOriginal);
      }
      expect(backend.files['/input/source.zip'], original);
      expect(backend.files.keys, ['/input/source.zip']);
    });
  }

  test(
    'restore never overwrites an unrelated replacement at the source name',
    () async {
      final record = await loseInstallationReply();
      backend.put('/input/source.zip', [42]);
      final inspection = await publisher.inspect(record);
      expect(inspection.canFinish, isFalse);
      expect(inspection.canRestore, isFalse);
      await expectLater(
        publisher.recover(record, ArchiveRecoveryAction.restoreOriginal),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(backend.files['/input/source.zip'], [42]);
      expect(backend.files[record.backupPath(backend.paths)], original);
    },
  );

  test(
    'occupied retained-candidate path prevents installed source restoration',
    () async {
      final record = await loseInstallationReply();
      backend.put(record.candidatePath(backend.paths), [42]);
      final inspection = await publisher.inspect(record);
      expect(inspection.canRestore, isFalse);
      await expectLater(
        publisher.recover(record, ArchiveRecoveryAction.restoreOriginal),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(backend.files[record.candidatePath(backend.paths)], [42]);
      expect(backend.files[record.backupPath(backend.paths)], original);
    },
  );

  test('retry cannot discard a persisted dependency', () async {
    final record = await interruptAfterStage();
    final downgraded = Map<String, dynamic>.of(record.toJson())
      ..remove('dependency')
      ..['version'] = 1;
    final ordinary = ArchivePublicationRecord.fromJson(downgraded);
    await expectLater(publish(retry: ordinary), throwsStateError);
    expect(backend.files['/input/source.zip'], original);
    final latest = await reopenRecord();
    expect(latest.dependency!.toJson(), dependency.toJson());
  });

  test('retry preserves its stored dependency when caller omits it', () async {
    final record = await interruptAfterStage();
    final receipt = await publish(retry: record);
    expect(receipt.record.dependency!.toJson(), dependency.toJson());
    expect(backend.files['/input/source.zip'], candidate);
  });

  test(
    'recovery refuses an altered dependency in a stale caller record',
    () async {
      final record = await interruptAfterStage();
      final modified =
          jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;
      (modified['dependency'] as Map)['sha256'] = '0' * 64;
      final stale = ArchivePublicationRecord.fromJson(modified);
      await expectLater(
        publisher.recover(stale, ArchiveRecoveryAction.finishPublication),
        throwsStateError,
      );
      expect(backend.files['/input/source.zip'], original);
    },
  );

  test('dependency cannot refer to another storage', () async {
    final record = await interruptAfterStage();
    final modified =
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;
    (modified['dependency'] as Map)['storage'] = const StorageReference(
      kind: 'remote',
      provider: 'other',
      accountKey: 'other',
    ).toJson();
    expect(
      () => ArchivePublicationRecord.fromJson(modified),
      throwsFormatException,
    );
  });

  test('dependency cannot refer to the source itself', () async {
    final record = await interruptAfterStage();
    final modified =
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;
    ((modified['dependency'] as Map)['file'] as Map)['path'] =
        '/input/source.zip';
    expect(
      () => ArchivePublicationRecord.fromJson(modified),
      throwsFormatException,
    );
  });

  test(
    'a pending guarded cleanup blocks another publication of the source',
    () async {
      backend.conditionalCleanup = false;
      final result = await publish();
      expect(result.cleanupPending, isTrue);
      expect(result.record.isFinished, isFalse);
      final second = ArchiveContainerPublisher(backend, journal);
      await expectLater(
        second.publish(
          original: (await backend.stat('/input/source.zip'))!,
          originalSha256: sha256.convert(candidate).toString(),
          bytes: Uint8List.fromList([6]),
        ),
        throwsStateError,
      );
      expect(backend.files[result.record.backupPath(backend.paths)], original);
    },
  );

  test(
    'a completed source receipt is invalid after its destination changes',
    () async {
      final receipt = await publish();
      backend.put('/out/destination.zip', [0]);
      await expectLater(publisher.verifyReceipt(receipt), throwsStateError);
    },
  );
}
