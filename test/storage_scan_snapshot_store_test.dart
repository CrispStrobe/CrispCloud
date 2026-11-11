import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_analysis.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/storage_scan_snapshot_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

StorageNode _file(String path, int? size, {bool link = false}) => StorageNode(
  item: FileItem(
    name: path.split('/').last,
    path: path,
    isFolder: false,
    size: size,
    isSymlink: link,
    symlinkTarget: link ? '/elsewhere' : null,
    updatedAt: DateTime.utc(2026, 11, 7),
    uuid: 'inert-object-id',
    metadata: {'accessToken': 'never-save-this'},
    storageId: 'untrusted-item-scope',
  ),
  bytes: link ? 0 : size ?? 0,
  fileCount: link ? 0 : 1,
  folderCount: 0,
  skippedLinkCount: link ? 1 : 0,
  unknownSizeCount: !link && size == null ? 1 : 0,
  isComplete: link || size != null,
);

StorageNode _folder(String path, List<StorageNode> children) => StorageNode(
  item: FileItem(
    name: path == '/' ? '/' : path.split('/').last,
    path: path,
    isFolder: true,
  ),
  children: children,
  bytes: children.fold(0, (sum, child) => sum + child.bytes),
  fileCount: children.fold(0, (sum, child) => sum + child.fileCount),
  folderCount: children.fold(
    0,
    (sum, child) => sum + child.folderCount + (child.isFolder ? 1 : 0),
  ),
  unknownSizeCount: children.fold(
    0,
    (sum, child) => sum + child.unknownSizeCount,
  ),
  skippedLinkCount: children.fold(
    0,
    (sum, child) => sum + child.skippedLinkCount,
  ),
  isComplete: children.every((child) => child.isComplete),
);

StorageScanResult _result({int count = 1}) => StorageScanResult(
  root: _folder('/資料', [
    _folder('/資料/空', []),
    for (var i = 0; i < count; i++) _file('/資料/文書-$i.txt', i),
    _file('/資料/unknown', null),
    _file('/資料/link', 999, link: true),
  ]),
  cancelled: true,
  limited: false,
  sourceChanged: false,
  startedAt: DateTime.utc(2026, 11, 7, 8),
  completedAt: DateTime.utc(2026, 11, 7, 9),
  suppressedIssueCount: 1234,
  issues: const [
    StorageScanIssue(
      path: '/資料/不明',
      code: StorageScanIssueCode.unreadableDirectory,
      message: 'Permission denied — 読み取り',
    ),
  ],
);

Future<StorageScanSnapshotSummary> _save(
  StorageScanSnapshotStore store, {
  int count = 1,
}) => store.save(
  result: _result(count: count),
  storageId: 'opaque-source',
  sourceLabel: 'Travel archive 📁',
);

class _FailingStorage extends MemoryFileCollectionStorage {
  bool failPages = false;
  bool throwAfterCommit = false;
  bool blindAfterCommit = false;
  bool blind = false;

  @override
  Future<void> write(String key, String value) async {
    if (failPages && key.endsWith(':page:1')) throw StateError('Disk full');
    await super.write(key, value);
  }

  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    if (blind) throw StateError('Temporarily unavailable');
    return super.read(key, maxBytes: maxBytes);
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final accepted = await super.compareAndSwap(key, expected, value);
    if (accepted && throwAfterCommit) {
      if (blindAfterCommit) blind = true;
      throw StateError('Acknowledgement lost');
    }
    return accepted;
  }
}

class _BatchSnapshotStorage extends MemoryFileCollectionStorage
    implements FileCollectionStorageBatchWriter {
  final batches = <List<FileCollectionStorageRecord>>[];
  Future<void> Function()? beforeBatch;
  void Function(String)? afterWrite;
  void Function()? afterCommit;
  bool failBatch = false;
  bool loseCommitReply = false;

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    afterWrite?.call(key);
  }

  @override
  Future<void> writeBatch(List<FileCollectionStorageRecord> records) async {
    FileCollectionStorageBatch.validate(records);
    batches.add(List.of(records));
    final callback = beforeBatch;
    beforeBatch = null;
    await callback?.call();
    for (final record in records) {
      await write(record.key, record.value);
    }
    if (failBatch) throw StateError('Injected batch failure.');
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final committed = await super.compareAndSwap(key, expected, value);
    if (committed) {
      afterCommit?.call();
      if (loseCommitReply) throw StateError('Lost committed acknowledgement.');
    }
    return committed;
  }
}

class _PausedSnapshotReads extends _BatchSnapshotStorage {
  bool pause = false;
  final entered = Completer<void>();
  final gates = List.generate(4, (_) => Completer<void>());
  final requested = <int>[];
  final finished = <int>[];
  var active = 0;
  var maximumActive = 0;

  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    if (pause && key.contains(':page:')) {
      final index = int.parse(key.split(':').last);
      requested.add(index);
      if (index < gates.length) {
        active++;
        if (active > maximumActive) maximumActive = active;
        if (active == gates.length && !entered.isCompleted) entered.complete();
        try {
          await gates[index].future;
          finished.add(index);
        } finally {
          active--;
        }
      }
    }
    return super.read(key, maxBytes: maxBytes);
  }
}

class _SynchronousSnapshotReadFailure extends _BatchSnapshotStorage {
  bool fail = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  var delayedFinished = false;

  @override
  Future<String?> read(String key, {required int maxBytes}) {
    if (fail && key.contains(':page:')) {
      final page = int.parse(key.split(':').last);
      if (page == 1) throw StateError('Synchronous adapter failure.');
      if (page == 0) {
        entered.complete();
        return release.future.then((_) {
          delayedFinished = true;
          return super.read(key, maxBytes: maxBytes);
        });
      }
    }
    return super.read(key, maxBytes: maxBytes);
  }
}

void main() {
  test(
    'snapshot writes bounded four-page batches without changing the format',
    () async {
      final storage = _BatchSnapshotStorage();
      final store = StorageScanSnapshotStore(storage: storage);
      final saved = await _save(store, count: 2100);
      expect(storage.batches.map((batch) => batch.length), [4, 1]);
      for (final batch in storage.batches) {
        expect(
          batch.fold<int>(0, (size, record) => size + record.bytes.length),
          lessThanOrEqualTo(FileCollectionStorageBatch.maxBytes),
        );
        for (final record in batch) {
          expect(
            record.bytes.length,
            lessThanOrEqualTo(StorageScanSnapshotStore.pageByteLimit),
          );
          expect(utf8.decode(record.bytes), record.value);
          expect((jsonDecode(record.value) as Map)['version'], 1);
        }
      }
      final loaded = await store.load(saved.id);
      expect(loaded.result.root.fileCount, 2101);
      expect(loaded.result.root.children[2100].item.name, '文書-2099.txt');
      expect(loaded.result.root.skippedLinkCount, 1);
      expect(loaded.result.root.unknownSizeCount, 1);
    },
  );

  test(
    'a failed page batch drains and preserves the earlier published snapshot',
    () async {
      final storage = _BatchSnapshotStorage();
      final store = StorageScanSnapshotStore(storage: storage);
      final saved = await _save(store);
      final before = Map<String, String>.of(storage.values);
      storage.failBatch = true;
      await expectLater(_save(store, count: 2100), throwsStateError);
      expect(storage.values, before);
      expect((await store.load(saved.id)).result.root.fileCount, 2);
    },
  );

  test('cancelling an outstanding save waits for the batch then removes staged pages', () async {
    final storage = _BatchSnapshotStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    await _save(store);
    final before = Map<String, String>.of(storage.values);
    final entered = Completer<void>();
    final release = Completer<void>();
    storage.beforeBatch = () async {
      entered.complete();
      await release.future;
    };
    var cancelled = false;
    var returned = false;
    final checked = expectLater(
      store.save(
        result: _result(count: 2100),
        storageId: 'original',
        sourceLabel: 'Original',
        isCancelled: () => cancelled,
      ),
      throwsStateError,
    ).then((_) => returned = true);
    await entered.future;
    cancelled = true;
    try {
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
    } finally {
      release.complete();
    }
    await checked;
    expect(storage.values, before);
  });

  test(
    'cancellation after manifest staging cannot publish a snapshot',
    () async {
      final storage = _BatchSnapshotStorage();
      final store = StorageScanSnapshotStore(storage: storage);
      var cancelled = false;
      storage.afterWrite = (key) {
        if (key.contains(':manifest')) cancelled = true;
      };
      await expectLater(
        store.save(
          result: _result(),
          storageId: 'original',
          sourceLabel: 'Original',
          isCancelled: () => cancelled,
        ),
        throwsStateError,
      );
      expect(storage.values, isEmpty);
    },
  );

  for (final loseReply in [false, true]) {
    test(
      'committed save remains successful after cancellation with lostReply=$loseReply',
      () async {
        final storage = _BatchSnapshotStorage()..loseCommitReply = loseReply;
        final store = StorageScanSnapshotStore(storage: storage);
        var cancelled = false;
        storage.afterCommit = () => cancelled = true;
        final saved = await store.save(
          result: _result(),
          storageId: 'original',
          sourceLabel: 'Original',
          isCancelled: () => cancelled,
        );
        expect(cancelled, isTrue);
        expect((await store.load(saved.id)).result.root.fileCount, 2);
        expect((await store.list()).single.id, saved.id);
      },
    );
  }

  test(
    'bounded read-ahead preserves parent order when pages finish in reverse',
    () async {
      final storage = _PausedSnapshotReads();
      final store = StorageScanSnapshotStore(storage: storage);
      final saved = await _save(store, count: 2100);
      storage.pause = true;
      final loading = store.load(saved.id);
      await storage.entered.future;
      expect(storage.requested, [0, 1, 2, 3]);
      for (final gate in storage.gates.reversed) {
        gate.complete();
      }
      final loaded = await loading;
      expect(storage.finished, [3, 2, 1, 0]);
      expect(storage.requested, [0, 1, 2, 3, 4]);
      expect(storage.maximumActive, 4);
      expect(storage.active, 0);
      expect(loaded.result.root.fileCount, 2101);
      expect(loaded.result.root.children.first.path, '/資料/空');
      expect(loaded.result.root.children[2100].path, '/資料/文書-2099.txt');
    },
  );

  test('cancelled read-ahead drains the current group without reading further pages', () async {
    final storage = _PausedSnapshotReads();
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store, count: 2100);
    final before = Map<String, String>.of(storage.values);
    storage.pause = true;
    var cancelled = false;
    final checked = expectLater(
      store.load(saved.id, isCancelled: () => cancelled),
      throwsStateError,
    );
    await storage.entered.future;
    cancelled = true;
    for (final gate in storage.gates) {
      gate.complete();
    }
    await checked;
    expect(storage.requested, [0, 1, 2, 3]);
    expect(storage.active, 0);
    expect(storage.values, before);
  });

  test(
    'a synchronous page-read failure still drains earlier submitted reads',
    () async {
      final storage = _SynchronousSnapshotReadFailure();
      final store = StorageScanSnapshotStore(storage: storage);
      final saved = await _save(store, count: 2100);
      storage.fail = true;
      var returned = false;
      final checked = expectLater(
        store.load(saved.id),
        throwsStateError,
      ).then((_) => returned = true);
      await storage.entered.future;
      try {
        await Future<void>.delayed(Duration.zero);
        expect(returned, isFalse);
        expect(storage.delayedFinished, isFalse);
      } finally {
        storage.release.complete();
      }
      await checked;
      expect(storage.delayedFinished, isTrue);
    },
  );

  test('full history rejects before preparing or writing any candidate pages', () async {
    final storage = _BatchSnapshotStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    await _save(store);
    final catalog =
        jsonDecode(storage.values[StorageScanSnapshotStore.indexKey]!) as Map;
    final original = (catalog['snapshots'] as List).single as Map;
    catalog['snapshots'] = [
      for (
        var index = 0;
        index < StorageScanSnapshotStore.maxSnapshots;
        index++
      )
        {
          ...original,
          'id':
              '00000000-0000-0000-0000-${index.toRadixString(16).padLeft(12, '0')}',
        },
    ];
    storage.values[StorageScanSnapshotStore.indexKey] = jsonEncode(catalog);
    final before = Map<String, String>.of(storage.values);
    storage.batches.clear();
    await expectLater(_save(store, count: 2100), throwsFormatException);
    expect(storage.batches, isEmpty);
    expect(storage.values, before);
  });

  test(
    'canonical-child fast path rejects aliases and retains platform name rules',
    () async {
      StorageScanResult result(String root, String name, String path) {
        final child = StorageNode(
          item: FileItem(name: name, path: path, isFolder: false, size: 1),
          bytes: 1,
          fileCount: 1,
          folderCount: 0,
        );
        return StorageScanResult(
          root: StorageNode(
            item: FileItem(name: root, path: root, isFolder: true),
            children: [child],
            bytes: 1,
            fileCount: 1,
            folderCount: 0,
          ),
          startedAt: DateTime.utc(2026),
          completedAt: DateTime.utc(2026),
          cancelled: false,
          limited: false,
          sourceChanged: false,
        );
      }

      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      for (final (style, root, name, path) in [
        (p.Style.posix, '/root', 'escape', '/root/../escape'),
        (p.Style.posix, '/root', 'item', '/rooted/item'),
        (p.Style.posix, '/root', '.', '/root/.'),
        (p.Style.posix, '/root', 'a/b', '/root/a/b'),
        (p.Style.posix, '/', 'item', '//item'),
        (p.Style.windows, r'C:\root', 'escape', r'C:\root\..\escape'),
        (p.Style.windows, r'C:\root', 'item', r'C:\rooted\item'),
        (p.Style.windows, r'C:\root', r'a\b', r'C:\root\a\b'),
      ]) {
        await expectLater(
          store.save(
            result: result(root, name, path),
            storageId: 'source',
            sourceLabel: 'Invalid child',
            pathStyle: style,
          ),
          throwsFormatException,
          reason: path,
        );
      }
      for (final (style, root, name, path) in [
        (p.Style.posix, '/', '.hidden', '/.hidden'),
        (p.Style.posix, '/root', r'a\b', r'/root/a\b'),
        (p.Style.windows, 'C:\\', '資料', r'C:\資料'),
        (p.Style.windows, r'\\server\share', '資料', r'\\server\share\資料'),
      ]) {
        final saved = await store.save(
          result: result(root, name, path),
          storageId: 'source',
          sourceLabel: 'Canonical child',
          pathStyle: style,
        );
        expect(
          (await store.load(saved.id)).result.root.children.single.path,
          path,
        );
      }
    },
  );

  test(
    'single-pass totals still rejects every inconsistent aggregate',
    () async {
      final original = _result();
      final root = original.root;
      final storage = MemoryFileCollectionStorage();
      final store = StorageScanSnapshotStore(storage: storage);
      for (final field in [
        'bytes',
        'files',
        'folders',
        'unknown',
        'links',
        'complete',
      ]) {
        final invalid = StorageScanResult(
          root: StorageNode(
            item: root.item,
            children: root.children,
            bytes: root.bytes + (field == 'bytes' ? 1 : 0),
            fileCount: root.fileCount + (field == 'files' ? 1 : 0),
            folderCount: root.folderCount + (field == 'folders' ? 1 : 0),
            unknownSizeCount:
                root.unknownSizeCount + (field == 'unknown' ? 1 : 0),
            skippedLinkCount:
                root.skippedLinkCount + (field == 'links' ? 1 : 0),
            isComplete: field == 'complete' || root.isComplete,
          ),
          startedAt: original.startedAt,
          completedAt: original.completedAt,
          cancelled: original.cancelled,
          limited: original.limited,
          sourceChanged: original.sourceChanged,
        );
        await expectLater(
          store.save(result: invalid, storageId: 'source', sourceLabel: field),
          throwsFormatException,
          reason: field,
        );
        expect(storage.values, isEmpty);
      }
    },
  );

  test('round trip preserves Unicode, empty directories, zero/unknown sizes, links and diagnostics', () async {
    final storage = MemoryFileCollectionStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final summary = await _save(store);
    final snapshot = await store.load(summary.id);
    expect(snapshot.summary.sourceLabel, 'Travel archive 📁');
    expect(snapshot.summary.storageId, 'opaque-source');
    expect(snapshot.result.root.path, '/資料');
    expect(snapshot.result.root.children.map((node) => node.name), [
      '空',
      '文書-0.txt',
      'unknown',
      'link',
    ]);
    expect(snapshot.result.root.children.first.children, isEmpty);
    expect(snapshot.result.root.children[1].item.size, 0);
    expect(snapshot.result.root.children[2].item.size, isNull);
    expect(snapshot.result.root.children[3].item.symlinkTarget, '/elsewhere');
    expect(snapshot.result.root.unknownSizeCount, 1);
    expect(snapshot.result.root.skippedLinkCount, 1);
    expect(snapshot.result.cancelled, isTrue);
    expect(snapshot.result.suppressedIssueCount, 1234);
    expect(snapshot.result.issues.single.message, 'Permission denied — 読み取り');
    expect(
      snapshot.result.issues.single.code,
      StorageScanIssueCode.unreadableDirectory,
    );
    expect(snapshot.result.startedAt, DateTime.utc(2026, 11, 7, 8));
    expect(snapshot.result.root.children[1].item.metadata, isNull);
    expect(snapshot.result.root.children[1].item.storageId, isNull);
    expect(storage.values.values.join(), isNot(contains('never-save-this')));
    expect(storage.values.values.join(), isNot(contains('accessToken')));
    expect(
      storage.values.values.join(),
      isNot(contains('untrusted-item-scope')),
    );
  });

  test('history reads only a small index; large snapshots use bounded independent pages', () async {
    final storage = MemoryFileCollectionStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store, count: 1200);
    final pageKeys = storage.values.keys
        .where((key) => key.contains(':page:'))
        .toList();
    expect(pageKeys.length, 3);
    for (final key in pageKeys) {
      expect(
        utf8.encode(storage.values[key]!).length,
        lessThanOrEqualTo(StorageScanSnapshotStore.pageByteLimit),
      );
    }
    storage.reads.clear();
    expect((await store.list()).single.nodeCount, 1204);
    expect(storage.reads, [StorageScanSnapshotStore.indexKey]);
    final loaded = await store.load(saved.id);
    expect(loaded.result.root.fileCount, 1201);
    expect(loaded.result.root.bytes, 719400);
  });

  test(
    'failed page write keeps the previous published scan readable',
    () async {
      final storage = _FailingStorage();
      final store = StorageScanSnapshotStore(storage: storage);
      final previous = await _save(store);
      final committed = storage.values[StorageScanSnapshotStore.indexKey];
      storage.failPages = true;
      await expectLater(_save(store, count: 1200), throwsStateError);
      expect(storage.values[StorageScanSnapshotStore.indexKey], committed);
      expect((await store.load(previous.id)).result.root.fileCount, 2);
      expect((await store.list()).length, 1);
      expect(
        storage.values.keys.where((key) => key.contains(':page:')).length,
        1,
      );
    },
  );

  test('commit acknowledgement loss is resolved by readback without deleting published pages', () async {
    final storage = _FailingStorage()..throwAfterCommit = true;
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store);
    expect((await store.load(saved.id)).result.root.fileCount, 2);
  });

  test('unknown commit outcome retains candidate pages until storage can be read again', () async {
    final storage = _FailingStorage()
      ..throwAfterCommit = true
      ..blindAfterCommit = true;
    final store = StorageScanSnapshotStore(storage: storage);
    await expectLater(_save(store), throwsStateError);
    storage.blind = false;
    final saved = (await store.list()).single;
    expect((await store.load(saved.id)).result.root.fileCount, 2);
  });

  test(
    'concurrent saves merge through CAS rather than losing either scan',
    () async {
      final storage = MemoryFileCollectionStorage();
      final first = StorageScanSnapshotStore(storage: storage);
      final second = StorageScanSnapshotStore(storage: storage);
      await Future.wait([_save(first), _save(second, count: 2)]);
      final history = await first.list();
      expect(history.length, 2);
      expect(history.map((entry) => entry.fileCount).toSet(), {2, 3});
      for (final saved in history) {
        await first.load(saved.id);
      }
    },
  );

  test('missing or modified pages are rejected instead of returning partial fake totals', () async {
    final storage = MemoryFileCollectionStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store);
    final key = storage.values.keys.singleWhere(
      (key) => key.contains(':page:'),
    );
    final original = storage.values[key]!;
    storage.values[key] = original.replaceFirst('文書', 'altered');
    await expectLater(store.load(saved.id), throwsFormatException);
    storage.values.remove(key);
    await expectLater(store.load(saved.id), throwsFormatException);
  });

  test('unsupported versions and node-limit violations are rejected before page reads', () async {
    final storage = MemoryFileCollectionStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store);
    final original = storage.values[StorageScanSnapshotStore.indexKey]!;
    final index = jsonDecode(original) as Map<String, dynamic>;
    index['version'] = 99;
    storage.values[StorageScanSnapshotStore.indexKey] = jsonEncode(index);
    await expectLater(store.list(), throwsFormatException);
    index['version'] = 1;
    (index['snapshots'] as List).first['nodes'] = 200002;
    storage.values[StorageScanSnapshotStore.indexKey] = jsonEncode(index);
    storage.reads.clear();
    await expectLater(store.load(saved.id), throwsFormatException);
    expect(storage.reads, [StorageScanSnapshotStore.indexKey]);
  });

  test('valid page digest cannot disguise invalid parent references or numeric precision', () async {
    final storage = MemoryFileCollectionStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store);
    final pageKey = storage.values.keys.singleWhere(
      (key) => key.contains(':page:'),
    );
    final manifestKey = storage.values.keys.singleWhere(
      (key) => key.contains(':manifest'),
    );
    final page = jsonDecode(storage.values[pageKey]!) as Map<String, dynamic>;
    final manifest =
        jsonDecode(storage.values[manifestKey]!) as Map<String, dynamic>;
    void commitCorruption() {
      final raw = jsonEncode(page);
      storage.values[pageKey] = raw;
      final descriptor =
          (manifest['pages'] as List).first as Map<String, dynamic>;
      descriptor['bytes'] = utf8.encode(raw).length;
      descriptor['sha256'] = sha256.convert(utf8.encode(raw)).toString();
      storage.values[manifestKey] = jsonEncode(manifest);
    }

    final node = (page['nodes'] as List)[1] as Map<String, dynamic>;
    node['parent'] = 1;
    commitCorruption();
    await expectLater(store.load(saved.id), throwsFormatException);
    node['parent'] = 0;
    node['bytes'] = '9007199254740992';
    commitCorruption();
    await expectLater(store.load(saved.id), throwsFormatException);
    node['bytes'] = 0;
    commitCorruption();
    await expectLater(store.load(saved.id), throwsFormatException);
  });

  test(
    'maximum exact byte count survives decimal encoding without rounding',
    () async {
      const bytes = 9007199254740991;
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final result = StorageScanResult(
        root: _folder('/', [_file('/huge', bytes)]),
        cancelled: false,
        limited: false,
        sourceChanged: false,
        startedAt: DateTime.utc(2026),
        completedAt: DateTime.utc(2026),
      );
      final saved = await store.save(
        result: result,
        storageId: 'test',
        sourceLabel: 'Exact',
      );
      expect((await store.load(saved.id)).result.root.bytes, bytes);
    },
  );

  test(
    'Windows roots and Unicode empty folders round trip on every host',
    () async {
      final store = StorageScanSnapshotStore(
        storage: MemoryFileCollectionStorage(),
      );
      final root = StorageNode(
        item: FileItem(name: '資料', path: r'C:\資料', isFolder: true),
        children: [
          StorageNode(
            item: FileItem(name: '空', path: r'C:\資料\空', isFolder: true),
            bytes: 0,
            fileCount: 0,
            folderCount: 0,
          ),
        ],
        bytes: 0,
        fileCount: 0,
        folderCount: 1,
      );
      final result = StorageScanResult(
        root: root,
        cancelled: false,
        limited: false,
        sourceChanged: false,
        startedAt: DateTime.utc(2026),
        completedAt: DateTime.utc(2026),
      );
      final saved = await store.save(
        result: result,
        storageId: 'win',
        sourceLabel: 'Windows',
        pathStyle: p.Style.windows,
      );
      expect(
        (await store.load(saved.id)).result.root.children.single.path,
        r'C:\資料\空',
      );
    },
  );

  test('deleting one historical snapshot leaves another readable', () async {
    final storage = MemoryFileCollectionStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final first = await _save(store);
    final second = await _save(store, count: 2);
    await store.delete(first.id);
    expect((await store.list()).single.id, second.id);
    expect((await store.load(second.id)).result.root.fileCount, 3);
    await expectLater(store.load(first.id), throwsFormatException);
  });

  test(
    'deletion acknowledges an already committed CAS after a lost reply',
    () async {
      final storage = _FailingStorage();
      final store = StorageScanSnapshotStore(storage: storage);
      final saved = await _save(store);
      storage.throwAfterCommit = true;
      await store.delete(saved.id);
      expect(await store.list(), isEmpty);
      expect(
        storage.values.keys.where((key) => key.contains(':page:')),
        isEmpty,
      );
    },
  );

  test('uncertain deletion outcome never removes candidate pages', () async {
    final storage = _FailingStorage();
    final store = StorageScanSnapshotStore(storage: storage);
    final saved = await _save(store);
    storage.throwAfterCommit = true;
    storage.blindAfterCommit = true;
    await expectLater(store.delete(saved.id), throwsStateError);
    expect(
      storage.values.keys.where((key) => key.contains(':page:')),
      isNotEmpty,
    );
    storage.blind = false;
    expect(await store.list(), isEmpty);
  });
}
