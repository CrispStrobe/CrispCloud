import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/archive_container_publisher.dart';
import 'package:crisp_cloud/services/archive_directory_snapshot.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NativeDirectoryPublicationBackend extends LocalOperationBackend {
  _NativeDirectoryPublicationBackend(bool Function() current)
    : super(LocalFileService(), isCurrent: current);

  FutureOr<void> Function(FileItem file, String destination)? afterMove;
  final moves = <String>[];

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    final moved = await super.moveNoReplace(file, destination);
    if (moved) {
      moves.add('${file.path}:$destination');
      await afterMove?.call(file, destination);
    }
    return moved;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });

  final originalBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
  final candidateBytes = Uint8List.fromList([1, 2, 7]);
  late Directory root;
  late Directory source;
  late File input;
  late File target;
  late FileItem original;
  late bool current;
  late _NativeDirectoryPublicationBackend backend;
  late MemoryFileCollectionStorage storage;
  late ArchivePublicationJournal journal;
  late ArchiveContainerPublisher publisher;
  late ArchivePublicationDirectoryDependency dependency;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crisp-archive-directory-');
    source = await Directory('${root.path}/source').create();
    await Directory('${source.path}/empty').create();
    input = File('${source.path}/data.txt');
    await input.writeAsBytes([4, 5, 6], flush: true);
    await Directory('${root.path}/output').create();
    target = File('${root.path}/output/data.tar');
    await target.writeAsBytes(originalBytes, flush: true);
    current = true;
    backend = _NativeDirectoryPublicationBackend(() => current);
    original = (await backend.stat(target.path))!;
    dependency = (await captureArchiveDirectorySnapshot(
      backend,
      source.path,
      forbiddenContainer: original,
    )).dependency;
    storage = MemoryFileCollectionStorage();
    journal = ArchivePublicationJournal(storage: storage);
    publisher = ArchiveContainerPublisher(backend, journal);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<ArchivePublicationReceipt> publish({
    ArchivePublicationRecord? retry,
    void Function(ArchivePublicationPhase)? onPhase,
    bool Function()? isCancelled,
  }) => publisher.publish(
    original: retry?.original ?? original,
    originalSha256: sha256.convert(originalBytes).toString(),
    bytes: candidateBytes,
    retry: retry,
    directoryDependency: retry == null ? dependency : null,
    onPhase: onPhase,
    isCancelled: isCancelled,
  );

  Future<ArchivePublicationRecord> reopenRecord() async {
    journal = ArchivePublicationJournal(storage: storage);
    await journal.initialize();
    publisher = ArchiveContainerPublisher(backend, journal);
    return journal.records.single;
  }

  Future<ArchivePublicationRecord> interruptAfterStage() async {
    await expectLater(
      publish(
        onPhase: (phase) {
          if (phase == ArchivePublicationPhase.candidateWritten) {
            throw StateError('Stop after durable staging.');
          }
        },
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    return reopenRecord();
  }

  Future<ArchivePublicationRecord> loseInstallationReply() async {
    var fired = false;
    backend.afterMove = (file, destination) {
      if (!fired &&
          file.path!.endsWith('.candidate') &&
          destination == target.path) {
        fired = true;
        throw StateError('Lost installation acknowledgement.');
      }
    };
    await expectLater(publish(), throwsA(isA<ArchivePublicationException>()));
    expect(fired, isTrue);
    backend.afterMove = null;
    final record = await reopenRecord();
    expect(await target.readAsBytes(), candidateBytes);
    expect(
      await File(record.backupPath(backend.paths)).readAsBytes(),
      originalBytes,
    );
    return record;
  }

  void changeSource() {
    final modified = input.lastModifiedSync();
    input.writeAsBytesSync([7, 8, 9], flush: true);
    input.setLastModifiedSync(modified);
  }

  Future<bool> containsOriginal(String path) async {
    final file = File(path);
    return await file.exists() &&
        sha256.convert(await file.readAsBytes()) ==
            sha256.convert(originalBytes);
  }

  ArchivePublicationRecord newRecord() => ArchivePublicationRecord(
    id: '00000000-0000-4000-8000-000000000001',
    storage: backend.storageReference,
    original: original,
    originalSha256: sha256.convert(originalBytes).toString(),
    candidateSha256: sha256.convert(candidateBytes).toString(),
    candidateBytes: candidateBytes.length,
    phase: ArchivePublicationPhase.prepared,
    createdAt: DateTime.utc(2026, 11, 12),
    directoryDependency: dependency,
  );

  test('v3 publication persists its bounded source-tree dependency', () async {
    final receipt = await publish();
    expect(receipt.cleanupPending, isFalse);
    expect(receipt.record.phase, ArchivePublicationPhase.complete);
    expect(receipt.record.toJson()['version'], 3);
    expect(receipt.record.dependency, isNull);
    expect(receipt.record.directoryDependency!.toJson(), dependency.toJson());
    expect(await target.readAsBytes(), candidateBytes);
    expect(await input.readAsBytes(), [4, 5, 6]);
    expect(await Directory('${source.path}/empty').exists(), isTrue);
    await publisher.verifyReceipt(receipt);
    final reloaded = await reopenRecord();
    expect(reloaded.directoryDependency!.toJson(), dependency.toJson());
  });

  test('directory dependency round-trip retains only recognized immutable metadata', () {
    final metadata = <String, dynamic>{
      'revision': 'v2',
      'etag': 'fixed',
      'password': 'fixture-secret-not-for-journal',
    };
    final captured = ArchivePublicationDirectoryDependency(
      storage: dependency.storage,
      directory: dependency.directory.copyWith(metadata: metadata),
      sha256: dependency.sha256,
      entryCount: dependency.entryCount,
      totalBytes: dependency.totalBytes,
    );
    metadata['revision'] = 'changed';
    final encoded = jsonEncode(captured.toJson());
    final decoded = ArchivePublicationDirectoryDependency.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(decoded.toJson(), captured.toJson());
    expect(decoded.directory.metadata!['revision'], 'v2');
    expect(encoded, isNot(contains('fixture-secret-not-for-journal')));
    expect(decoded.directory.metadata!.containsKey('password'), isFalse);
    expect(
      () => decoded.directory.metadata!['revision'] = 'new',
      throwsUnsupportedError,
    );
    expect(sameArchiveFile(captured.directory, decoded.directory), isTrue);
  });

  for (final invalid in [
    'v1 with directory',
    'v2 with directory',
    'v3 without directory',
    'v3 with both dependencies',
    'future version',
    'negative count',
    'too many entries',
    'too many bytes',
    'invalid hash',
    'non-directory source',
    'symlink source',
    'different storage',
  ]) {
    test('durable directory authority refuses $invalid', () {
      final json =
          jsonDecode(jsonEncode(newRecord().toJson())) as Map<String, dynamic>;
      final directory = json['directoryDependency'] as Map<String, dynamic>;
      switch (invalid) {
        case 'v1 with directory':
          json['version'] = 1;
        case 'v2 with directory':
          json['version'] = 2;
        case 'v3 without directory':
          json.remove('directoryDependency');
        case 'v3 with both dependencies':
          json['dependency'] = <String, dynamic>{};
        case 'future version':
          json['version'] = 4;
        case 'negative count':
          directory['entryCount'] = -1;
        case 'too many entries':
          directory['entryCount'] = 200001;
        case 'too many bytes':
          directory['totalBytes'] = 256 * 1024 * 1024 + 1;
        case 'invalid hash':
          directory['sha256'] = 'bad';
        case 'non-directory source':
          (directory['directory'] as Map)['isFolder'] = false;
        case 'symlink source':
          (directory['directory'] as Map)['isSymlink'] = true;
        case 'different storage':
          directory['storage'] = const StorageReference(
            kind: 'remote',
            provider: 'other',
            accountKey: 'other',
          ).toJson();
      }
      expect(
        () => ArchivePublicationRecord.fromJson(json),
        throwsFormatException,
      );
    });
  }

  for (final change in [
    'same-size contents',
    'added file',
    'missing file',
    'empty directory',
    'missing directory',
    'symlink',
  ]) {
    test('changed source $change refuses publication before staging', () async {
      switch (change) {
        case 'same-size contents':
          changeSource();
        case 'added file':
          await File('${source.path}/added.txt').writeAsString('new');
        case 'missing file':
          await input.delete();
        case 'empty directory':
          await Directory('${source.path}/added').create();
        case 'missing directory':
          await Directory('${source.path}/empty').delete();
        case 'symlink':
          await Link('${source.path}/alias').create(target.path);
      }
      await expectLater(publish(), throwsA(isA<Object>()));
      expect(await target.readAsBytes(), originalBytes);
      expect(backend.moves, isEmpty);
      expect(journal.records, isEmpty);
    }, skip: change == 'symlink' && Platform.isWindows);
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
      'source change at ${phase.name} retains recoverable original archive',
      () async {
        var fired = false;
        await expectLater(
          publish(
            onPhase: (value) {
              if (!fired && value == phase) {
                fired = true;
                changeSource();
              }
            },
          ),
          throwsA(isA<ArchivePublicationException>()),
        );
        expect(fired, isTrue);
        final record = await reopenRecord();
        expect(
          await containsOriginal(target.path) ||
              await containsOriginal(record.backupPath(backend.paths)),
          isTrue,
        );
        final inspection = await publisher.inspect(record);
        expect(inspection.canFinish, isFalse);
        expect(inspection.canRestore, isTrue);
        await publisher.recover(record, ArchiveRecoveryAction.restoreOriginal);
        expect(await target.readAsBytes(), originalBytes);
        expect(await input.readAsBytes(), [7, 8, 9]);
        expect(
          await File(record.candidatePath(backend.paths)).exists(),
          isFalse,
        );
        expect(await File(record.backupPath(backend.paths)).exists(), isFalse);
        expect(
          publisher.activeRecord!.phase,
          ArchivePublicationPhase.discarded,
        );
      },
    );
  }

  test(
    'restart finishes a staged synchronization while its source still matches',
    () async {
      final record = await interruptAfterStage();
      expect((await publisher.inspect(record)).canFinish, isTrue);
      final receipt = await publisher.recover(
        record,
        ArchiveRecoveryAction.finishPublication,
      );
      expect(
        receipt!.record.directoryDependency!.toJson(),
        dependency.toJson(),
      );
      expect(receipt.record.phase, ArchivePublicationPhase.complete);
      expect(await target.readAsBytes(), candidateBytes);
    },
  );

  test('restart cannot install a mirror candidate after its source namespace changes', () async {
    final record = await interruptAfterStage();
    await File('${source.path}/newly-present.txt').writeAsString('present');
    final moves = List<String>.of(backend.moves);
    await expectLater(
      publisher.recover(record, ArchiveRecoveryAction.finishPublication),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.moves, moves);
    expect(await target.readAsBytes(), originalBytes);
    expect(
      await File(record.candidatePath(backend.paths)).readAsBytes(),
      candidateBytes,
    );
  });

  test('already installed candidate still requires its original directory dependency', () async {
    final record = await loseInstallationReply();
    changeSource();
    final inspection = await publisher.inspect(record);
    expect(inspection.canFinish, isFalse);
    expect(inspection.canRestore, isTrue);
    await expectLater(
      publisher.recover(record, ArchiveRecoveryAction.finishPublication),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(
      await File(record.backupPath(backend.paths)).readAsBytes(),
      originalBytes,
    );
    await publisher.recover(
      publisher.activeRecord!,
      ArchiveRecoveryAction.restoreOriginal,
    );
    expect(await target.readAsBytes(), originalBytes);
    expect(publisher.activeRecord!.published, isNull);
  });

  test(
    'lost installation reply can finish when the captured source is unchanged',
    () async {
      final record = await loseInstallationReply();
      final receipt = await publisher.recover(
        record,
        ArchiveRecoveryAction.finishPublication,
      );
      expect(receipt!.record.phase, ArchivePublicationPhase.complete);
      expect(await target.readAsBytes(), candidateBytes);
      expect(await File(record.backupPath(backend.paths)).exists(), isFalse);
    },
  );

  test(
    'explicit restore never overwrites a foreign file at the archive name',
    () async {
      final record = await loseInstallationReply();
      await target.writeAsBytes([42]);
      expect((await publisher.inspect(record)).canRestore, isFalse);
      await expectLater(
        publisher.recover(record, ArchiveRecoveryAction.restoreOriginal),
        throwsA(isA<ArchivePublicationException>()),
      );
      expect(await target.readAsBytes(), [42]);
      expect(
        await File(record.backupPath(backend.paths)).readAsBytes(),
        originalBytes,
      );
    },
  );

  test(
    'retry cannot downgrade or replace its persisted directory authority',
    () async {
      final record = await interruptAfterStage();
      final downgraded = Map<String, dynamic>.of(record.toJson())
        ..remove('directoryDependency')
        ..['version'] = 1;
      await expectLater(
        publish(retry: ArchivePublicationRecord.fromJson(downgraded)),
        throwsStateError,
      );
      final changed =
          jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;
      (changed['directoryDependency'] as Map)['sha256'] = '0' * 64;
      await expectLater(
        publisher.recover(
          ArchivePublicationRecord.fromJson(changed),
          ArchiveRecoveryAction.finishPublication,
        ),
        throwsStateError,
      );
      expect(await target.readAsBytes(), originalBytes);
      expect(
        (await reopenRecord()).directoryDependency!.sha256,
        dependency.sha256,
      );
    },
  );

  test(
    'retry retains a persisted directory dependency when the caller omits it',
    () async {
      final record = await interruptAfterStage();
      final receipt = await publish(retry: record);
      expect(receipt.record.directoryDependency!.toJson(), dependency.toJson());
      expect(await target.readAsBytes(), candidateBytes);
    },
  );

  test(
    'a source directory containing the target is rejected before mutation',
    () async {
      final broad = (await captureArchiveDirectorySnapshot(
        backend,
        root.path,
      )).dependency;
      await expectLater(
        publisher.publish(
          original: original,
          originalSha256: sha256.convert(originalBytes).toString(),
          bytes: candidateBytes,
          directoryDependency: broad,
        ),
        throwsStateError,
      );
      expect(journal.records, isEmpty);
      expect(backend.moves, isEmpty);
      expect(await target.readAsBytes(), originalBytes);
    },
  );

  test(
    'guarded pending cleanup blocks a new edit at the same archive path',
    () async {
      final receipt = await publish(
        onPhase: (phase) {
          if (phase == ArchivePublicationPhase.cleaningBackup) {
            throw StateError('Cleanup is unavailable.');
          }
        },
      );
      expect(receipt.cleanupPending, isTrue);
      expect(receipt.record.published, isNotNull);
      await expectLater(
        ArchiveContainerPublisher(backend, journal).publish(
          original: (await backend.stat(target.path))!,
          originalSha256: sha256.convert(candidateBytes).toString(),
          bytes: Uint8List.fromList([8]),
        ),
        throwsStateError,
      );
      expect(
        await File(receipt.record.backupPath(backend.paths)).readAsBytes(),
        originalBytes,
      );
    },
  );

  test(
    'receipt validation detects a changed captured source directory',
    () async {
      final receipt = await publish();
      changeSource();
      await expectLater(publisher.verifyReceipt(receipt), throwsStateError);
    },
  );

  test('recovery inspection and finish honor cancellation', () async {
    final record = await interruptAfterStage();
    await expectLater(
      publisher.inspect(record, isCancelled: () => true),
      throwsA(isA<FileOperationCancelled>()),
    );
    final moves = List<String>.of(backend.moves);
    await expectLater(
      publisher.recover(
        record,
        ArchiveRecoveryAction.finishPublication,
        isCancelled: () => true,
      ),
      throwsA(isA<ArchivePublicationException>()),
    );
    expect(backend.moves, moves);
    expect(await target.readAsBytes(), originalBytes);
  });
}
