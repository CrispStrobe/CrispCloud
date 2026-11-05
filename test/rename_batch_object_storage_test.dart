import 'dart:async';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/rename_batch.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/rename_batch_service.dart';
import 'package:crisp_cloud/services/rename_batch_storage.dart';
import 'package:crisp_cloud/services/rename_batch_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _ObjectClient extends CloudStorageClient
    with CloudTransferOperations
    implements ObjectStorageNamespace {
  final Map<String, ({String bytes, String? version})> objects = {
    '/a.txt': (bytes: 'original', version: 'v1'),
  };
  final Set<String> folders = {};
  int copies = 0;
  int deletes = 0;
  bool supported = true;
  bool rejectDelete = false;
  bool failAfterDelete = false;
  FutureOr<void> Function()? afterCopy;
  FutureOr<void> Function()? beforeDelete;

  @override
  bool get isAuthenticated => true;
  @override
  String get providerName => 'Object test';
  @override
  String get userId => 'account';
  @override
  String get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  StorageTransferCapabilities get transferCapabilities =>
      StorageTransferCapabilities(
        caseSensitivity: StorageCaseSensitivity.sensitive,
        nativeCopy: supported,
        noReplaceCopy: supported,
        conditionalCopy: supported,
        conditionalDelete: supported,
      );

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'files': [
      for (final entry in objects.entries)
        if (p.posix.dirname(entry.key) == path)
          {
            'name': p.posix.basename(entry.key),
            'path': entry.key,
            'uuid': entry.key,
            'size': entry.value.bytes.length,
            if (entry.value.version != null) 'etag': entry.value.version,
          },
    ],
    'folders': [
      for (final folder in folders)
        if (p.posix.dirname(folder) == path)
          {'name': p.posix.basename(folder), 'path': folder, 'uuid': folder},
    ],
  };

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
    final source = objects[sourcePath]!;
    expect(expectedSourceVersion, source.version);
    if (objects.containsKey(destinationPath)) {
      throw StateError('Exclusive copy conflict');
    }
    await checkpoint?.call();
    final version = 'copy-${++copies}';
    objects[destinationPath] = (bytes: source.bytes, version: version);
    await afterCopy?.call();
    return CloudTransferResult(
      path: destinationPath,
      version: version,
      size: source.bytes.length,
    );
  }

  @override
  Future<void> deleteTransferFile(
    String path, {
    String? expectedVersion,
  }) async {
    await beforeDelete?.call();
    if (rejectDelete) throw StateError('Deletion temporarily unavailable');
    if (objects[path]?.version != expectedVersion) {
      throw StateError('Conditional deletion conflict');
    }
    objects.remove(path);
    deletes++;
    if (failAfterDelete) throw StateError('Connection lost after deletion');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected legacy operation: ${invocation.memberName}');
}

class _Store extends MemoryRenameBatchStore {
  FutureOr<void> Function(RenameBatchRecord)? afterSave;
  bool rejectCopyCheckpoint = false;
  @override
  Future<void> save(RenameBatchRecord record) async {
    if (rejectCopyCheckpoint && record.steps.any((s) => s.copied != null)) {
      throw StateError('Journal disk full');
    }
    await super.save(record);
    await afterSave?.call(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _ObjectClient client;
  late _Store store;
  late SourceRenameBatchStorage storage;
  late RenameBatchService service;
  setUp(() {
    client = _ObjectClient();
    store = _Store();
    service = RenameBatchService(store);
    storage = SourceRenameBatchStorage(
      reference: const StorageReference(
        kind: 'remote',
        provider: 'Object test',
        accountKey: 'account',
      ),
      source: RemotePanelSource(
        providerName: client.providerName,
        client: client,
        path: '/',
      ),
      local: LocalFileService(),
      isCurrent: () => true,
      fallbackRename: (_, _) =>
          throw StateError('Object storage must never use legacy rename'),
    );
  });

  Future<RenameBatchRecord> prepare([Map<String, String>? names]) async {
    names ??= {'/a.txt': 'b.txt'};
    final files = <FileItem>[
      for (final path in names.keys) (await storage.stat(path))!,
    ];
    final plan = const MultiRenameService().preview(
      files,
      const MultiRenameOptions(),
      directory: '/',
      pathContext: p.posix,
      caseSensitivePaths: storage.caseSensitivePaths,
      allowDependencies: true,
      targetNames: names,
    );
    return service.prepare(plan, storage);
  }

  test(
    'exclusive versioned copy is journalled before conditional deletion',
    () async {
      final batch = await prepare();
      client.beforeDelete = () async {
        final persisted = (await store.read(batch.id))!;
        expect(persisted.steps.single.state, RenameStepState.inFlight);
        expect(persisted.steps.single.copied!.version, 'copy-1');
        expect(client.objects['/a.txt']!.bytes, 'original');
      };
      await service.run(batch, storage);
      expect(batch.isComplete, isTrue, reason: batch.message);
      expect(client.objects.keys, ['/b.txt']);
      expect(client.objects['/b.txt']!.bytes, 'original');
      expect(client.copies, 1);
      expect(client.deletes, 1);
      expect(storage.exclusiveMoves, isTrue);
    },
  );

  test(
    'interrupted deletion resumes from a persisted copy without recopying',
    () async {
      client.rejectDelete = true;
      final batch = await prepare();
      await service.run(batch, storage);
      expect(batch.isComplete, isFalse);
      expect(client.objects.length, 2);
      final reopened = (await store.read(batch.id))!;
      client.rejectDelete = false;
      await service.run(reopened, storage);
      expect(reopened.isComplete, isTrue, reason: reopened.message);
      expect(client.objects.keys, ['/b.txt']);
      expect(client.copies, 1);
    },
  );

  test(
    'changed source after copy is retained and never conditionally deleted',
    () async {
      client.afterCopy = () {
        client.objects['/a.txt'] = (bytes: 'new data', version: 'external');
      };
      final batch = await prepare();
      await service.run(batch, storage);
      expect(batch.state, RenameBatchState.needsReview);
      expect(client.objects['/a.txt']!.bytes, 'new data');
      expect(client.objects['/b.txt']!.bytes, 'original');
      expect(client.deletes, 0);
    },
  );

  test(
    'changed copied destination after persistence retains the original',
    () async {
      store.afterSave = (batch) {
        if (batch.steps.any((s) => s.copied != null)) {
          client.objects['/b.txt'] = (bytes: 'replaced', version: 'external');
        }
      };
      final batch = await prepare();
      await service.run(batch, storage);
      expect(batch.state, RenameBatchState.needsReview);
      expect(client.objects['/a.txt']!.bytes, 'original');
      expect(client.deletes, 0);
    },
  );

  test(
    'copy checkpoint persistence failure leaves both objects for review',
    () async {
      final batch = await prepare();
      store.rejectCopyCheckpoint = true;
      await expectLater(
        service.run(batch, storage),
        throwsA(isA<RenameBatchPersistenceException>()),
      );
      expect(client.objects.length, 2);
      expect(client.deletes, 0);
      final reopened = (await store.read(batch.id))!;
      expect(reopened.steps.single.copied, isNull);
      store.rejectCopyCheckpoint = false;
      await service.run(reopened, storage);
      expect(reopened.state, RenameBatchState.needsReview);
      expect(client.deletes, 0);
    },
  );

  test(
    'a lost delete response reconciles using the recorded destination version',
    () async {
      client.failAfterDelete = true;
      final batch = await prepare();
      await service.run(batch, storage);
      expect(batch.isComplete, isTrue, reason: batch.message);
      expect(client.objects.keys, ['/b.txt']);
      expect(client.copies, 1);
    },
  );

  test(
    'whole-batch restore uses versioned copy and conditional deletion again',
    () async {
      final batch = await prepare();
      await service.run(batch, storage);
      await service.restore(batch, storage);
      expect(batch.isRestored, isTrue, reason: batch.message);
      expect(client.objects.keys, ['/a.txt']);
      expect(client.objects['/a.txt']!.bytes, 'original');
      expect(client.copies, 2);
      expect(client.deletes, 2);
    },
  );

  test('case-only rename can stage and restore object keys', () async {
    final batch = await prepare({'/a.txt': 'A.txt'});
    expect(batch.steps.length, 2);
    await service.run(batch, storage);
    expect(batch.isComplete, isTrue, reason: batch.message);
    expect(client.objects.keys, ['/A.txt']);
    await service.restore(batch, storage);
    expect(batch.isRestored, isTrue, reason: batch.message);
    expect(client.objects.keys, ['/a.txt']);
  });

  test(
    'virtual folders block the entire plan before its first file mutation',
    () async {
      client.folders.add('/folder');
      await expectLater(
        prepare({'/a.txt': 'b.txt', '/folder': 'renamed'}),
        throwsA(isA<MultiRenamePreflightException>()),
      );
      expect(client.copies, 0);
      expect(client.deletes, 0);
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'unsupported conditional semantics are rejected before any copy',
    () async {
      client.supported = false;
      await expectLater(
        prepare(),
        throwsA(isA<MultiRenamePreflightException>()),
      );
      expect(client.copies, 0);
      expect(client.deletes, 0);
    },
  );

  test('unversioned objects are rejected before any copy', () async {
    client.objects['/a.txt'] = (bytes: 'original', version: null);
    await expectLater(prepare(), throwsA(isA<MultiRenamePreflightException>()));
    expect(client.copies, 0);
    expect(client.deletes, 0);
  });
}
