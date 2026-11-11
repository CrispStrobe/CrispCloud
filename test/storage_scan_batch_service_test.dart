import 'dart:async';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/storage_scan_batch_service.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:crisp_cloud/services/storage_scan_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileItem _file(String path, int? size) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: false,
  size: size,
);

FileItem _folder(String path) => FileItem(
  name: p.posix.basename(path),
  path: path,
  isFolder: true,
);

class _Source implements StorageScanSource {
  _Source(this.account, this.tree);

  final String account;
  final Map<String, List<FileItem>> tree;
  @override
  final Object identity = Object();
  bool current = true;
  final stats = <String>[];
  final reads = <String>[];
  final blocked = <String, Completer<void>>{};
  final entered = <String, Completer<void>>{};
  int activeReads = 0;
  int maxActiveReads = 0;

  @override
  bool get isCurrent => current;
  @override
  p.Context get paths => p.posix;
  @override
  bool get supportsSymbolicLinks => false;
  @override
  String pathKey(String path) => paths.normalize(path);
  @override
  bool samePath(String a, String b) => paths.equals(a, b);
  @override
  bool isWithin(String parent, String child) => paths.isWithin(parent, child);

  @override
  Future<FileItem?> stat(String path) async {
    stats.add(path);
    return tree.containsKey(path) ? _folder(path) : null;
  }

  @override
  Future<List<FileItem>> list(String path) async {
    reads.add(path);
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    final signal = entered[path];
    if (signal != null && !signal.isCompleted) signal.complete();
    try {
      await blocked[path]?.future;
      return tree[path] ?? (throw StateError('Missing folder'));
    } finally {
      activeReads--;
    }
  }

  Future<void> hold(String path) {
    blocked[path] = Completer<void>();
    return (entered[path] = Completer<void>()).future;
  }

  void release() {
    for (final gate in blocked.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

StorageScanBatchRoot _root(
  _Source source,
  String path, {
  Object? serialKey,
}) => StorageScanBatchRoot(
  source: source,
  rootPath: path,
  storage: StorageReference(
    kind: 'remote',
    provider: 'memory',
    accountKey: source.account,
  ),
  sourceLabel: source.account,
  serialReadKey: serialKey,
);

class _GatedStore extends StorageScanSnapshotStore {
  _GatedStore({this.holdFirst = false, this.failPath})
    : super(storage: MemoryFileCollectionStorage());

  final bool holdFirst;
  final String? failPath;
  final firstEntered = Completer<void>();
  final firstRelease = Completer<void>();
  int calls = 0;
  final savedPaths = <String>[];
  int active = 0;
  int maxActive = 0;

  @override
  Future<StorageScanSnapshotSummary> save({
    required StorageScanResult result,
    required String storageId,
    required String sourceLabel,
    p.Style? pathStyle,
    bool Function()? isCancelled,
  }) async {
    final call = ++calls;
    savedPaths.add(result.root.path);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      if (call == 1) {
        firstEntered.complete();
        if (holdFirst) await firstRelease.future;
      }
      if (result.root.path == failPath) throw StateError('Disk full');
      return await super.save(
        result: result,
        storageId: storageId,
        sourceLabel: sourceLabel,
        pathStyle: pathStyle,
        isCancelled: isCancelled,
      );
    } finally {
      active--;
    }
  }
}

class _CommitGate extends MemoryFileCollectionStorage {
  final committed = Completer<void>();
  final acknowledged = Completer<void>();

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final accepted = await super.compareAndSwap(key, expected, value);
    if (accepted && key == StorageScanSnapshotStore.indexKey) {
      committed.complete();
      await acknowledged.future;
    }
    return accepted;
  }
}

class _UnconfirmedCommit extends MemoryFileCollectionStorage {
  final committed = Completer<void>();
  final acknowledge = Completer<void>();
  bool indexUnavailable = false;

  @override
  Future<String?> read(String key, {required int maxBytes}) async {
    if (indexUnavailable && key == StorageScanSnapshotStore.indexKey) {
      throw StateError('History is temporarily unavailable');
    }
    return super.read(key, maxBytes: maxBytes);
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    final accepted = await super.compareAndSwap(key, expected, value);
    if (accepted && key == StorageScanSnapshotStore.indexKey) {
      indexUnavailable = true;
      committed.complete();
      await acknowledge.future;
      throw StateError('The commit acknowledgement was lost');
    }
    return accepted;
  }
}

Future<void> _until(
  StorageScanBatchService batch,
  bool Function() ready,
) {
  if (ready()) return Future.value();
  final done = Completer<void>();
  void changed() {
    if (!ready()) return;
    batch.removeListener(changed);
    done.complete();
  }
  batch.addListener(changed);
  return done.future;
}

void main() {
  test('review accepts at most 32 captured roots and starts no reads', () {
    final source = _Source('original', {'/one': []});
    final root = _root(source, '/one');
    expect(
      () => StorageScanBatchService(roots: []),
      throwsArgumentError,
    );
    expect(
      () => StorageScanBatchService(roots: List.filled(33, root)),
      throwsArgumentError,
    );
    var consumed = 0;
    Iterable<StorageScanBatchRoot> largeInput() sync* {
      for (var i = 0; i < 1000; i++) {
        consumed++;
        yield root;
      }
    }
    expect(
      () => StorageScanBatchService(roots: largeInput()),
      throwsArgumentError,
    );
    expect(consumed, StorageScanBatchService.maxRoots + 1);
    final batch = StorageScanBatchService(roots: List.filled(32, root));
    addTearDown(batch.dispose);
    expect(batch.jobs, hasLength(32));
    expect(
      batch.jobs.map((job) => job.phase),
      everyElement(StorageScanBatchPhase.ready),
    );
    expect(source.stats, isEmpty);
    expect(source.reads, isEmpty);
  });

  test('two slots include pending saves and all saves are serialized', () async {
    final first = _Source('first', {
      '/one': [_file('/one/a', 1)],
    });
    final second = _Source('second', {
      '/two': [_file('/two/b', 2)],
    });
    final third = _Source('third', {
      '/three': [_file('/three/c', 3)],
    });
    final secondEntered = second.hold('/two');
    final store = _GatedStore(holdFirst: true);
    final batch = StorageScanBatchService(
      roots: [
        _root(first, '/one'),
        _root(second, '/two'),
        _root(third, '/three'),
      ],
      snapshots: store,
    );
    addTearDown(batch.dispose);
    final done = batch.start();
    await secondEntered;
    await store.firstEntered.future;
    second.release();
    await _until(
      batch,
      () => batch.jobs[1].phase == StorageScanBatchPhase.saving,
    );
    expect(store.calls, 1);
    expect(third.stats, isEmpty);
    expect(third.reads, isEmpty);
    store.firstRelease.complete();
    await done;
    expect(store.calls, 3);
    expect(store.maxActive, 1);
    expect(await store.list(), hasLength(3));
    expect(
      batch.jobs.map((job) => job.phase),
      everyElement(StorageScanBatchPhase.saved),
    );
  });

  test(
    'roots using one stateful client never overlap directory reads',
    () async {
      final source = _Source('shared', {
        '/one': [_file('/one/a', 1)],
        '/two': [_file('/two/b', 2)],
      });
      final entered = source.hold('/one');
      final batch = StorageScanBatchService(
        roots: [
          _root(source, '/one', serialKey: source),
          _root(source, '/two', serialKey: source),
        ],
        snapshots: _GatedStore(),
      );
      addTearDown(batch.dispose);
      final done = batch.start();
      await entered;
      expect(source.stats, ['/one']);
      source.release();
      await done;
      expect(source.maxActiveReads, 1);
      expect(source.reads, ['/one', '/two']);
      expect(batch.jobs.map((job) => job.snapshot!.bytes), [1, 2]);
    },
  );

  test(
    'identical root paths on separate accounts keep separate full reports',
    () async {
      final first = _Source('first', {
        '/data': [_file('/data/a', 3)],
      });
      final second = _Source('second', {
        '/data': [_file('/data/b', 19)],
      });
      final store = _GatedStore();
      final batch = StorageScanBatchService(
        roots: [_root(first, '/data'), _root(second, '/data')],
        snapshots: store,
      );
      addTearDown(batch.dispose);
      await batch.start();
      final firstSaved = batch.jobs[0].snapshot!;
      final secondSaved = batch.jobs[1].snapshot!;
      expect(firstSaved.storageId, 'remote:memory:first');
      expect(secondSaved.storageId, 'remote:memory:second');
      final firstReport = await store.load(firstSaved.id);
      final secondReport = await store.load(secondSaved.id);
      expect(firstReport.result.root.children.single.name, 'a');
      expect(secondReport.result.root.children.single.name, 'b');
      expect(firstReport.result.root.bytes, 3);
      expect(secondReport.result.root.bytes, 19);
    },
  );

  test(
    'partial reports retain unknown sizes and remain partial in history',
    () async {
      final source = _Source('partial', {
        '/data': [_file('/data/known', 7), _file('/data/unknown', null)],
      });
      final store = _GatedStore();
      final batch = StorageScanBatchService(
        roots: [_root(source, '/data')],
        snapshots: store,
      );
      addTearDown(batch.dispose);
      await batch.start();
      final job = batch.jobs.single;
      expect(job.phase, StorageScanBatchPhase.partial);
      expect(job.summary!.unknownSizeCount, 1);
      expect(job.snapshot!.isComplete, isFalse);
      final report = await store.load(job.snapshot!.id);
      expect(report.result.root.bytes, 7);
      expect(report.result.root.unknownSizeCount, 1);
      expect(report.result.root.children, hasLength(2));
      expect(report.result.isComplete, isFalse);
    },
  );

  test(
    'stop retains measured totals, discards late rows and never starts queued roots',
    () async {
      final first = _Source('first', {
        '/one': [_file('/one/known', 5), _folder('/one/blocked')],
        '/one/blocked': [_file('/one/blocked/late', 900)],
      });
      final second = _Source('second', {
        '/two': [_file('/two/late', 100)],
      });
      final third = _Source('third', {
        '/three': [_file('/three/never', 99)],
      });
      final firstEntered = first.hold('/one/blocked');
      final secondEntered = second.hold('/two');
      final store = _GatedStore();
      final batch = StorageScanBatchService(
        roots: [
          _root(first, '/one'),
          _root(second, '/two'),
          _root(third, '/three'),
        ],
        snapshots: store,
      );
      addTearDown(batch.dispose);
      final done = batch.start();
      await Future.wait([firstEntered, secondEntered]);
      batch.cancel();
      expect(batch.jobs[0].phase, StorageScanBatchPhase.stopping);
      expect(batch.jobs[2].phase, StorageScanBatchPhase.cancelled);
      first.release();
      second.release();
      await done;
      expect(batch.jobs[0].summary!.bytes, 5);
      expect(batch.jobs[0].summary!.isComplete, isFalse);
      expect(batch.jobs[1].summary!.bytes, 0);
      expect(third.stats, isEmpty);
      expect(third.reads, isEmpty);
      expect(store.calls, 0);
      expect(await store.list(), isEmpty);
    },
  );

  test(
    'source loss during a read rejects late data and other roots continue',
    () async {
      final lost = _Source('lost', {
        '/lost': [_file('/lost/late', 900)],
      });
      final healthy = _Source('healthy', {
        '/healthy': [_file('/healthy/kept', 4)],
      });
      final entered = lost.hold('/lost');
      final store = _GatedStore();
      final batch = StorageScanBatchService(
        roots: [_root(lost, '/lost'), _root(healthy, '/healthy')],
        snapshots: store,
      );
      addTearDown(batch.dispose);
      final done = batch.start();
      await entered;
      lost.current = false;
      lost.release();
      await done;
      expect(batch.jobs.first.phase, StorageScanBatchPhase.sourceChanged);
      expect(batch.jobs.first.snapshot, isNull);
      expect(batch.jobs.first.summary!.bytes, 0);
      expect(batch.jobs.last.snapshot!.bytes, 4);
      expect(await store.list(), hasLength(1));
    },
  );

  for (final failAcceptedSave in [false, true]) {
    test(
      'accepted history survives later source loss; save failure=$failAcceptedSave',
      () async {
        final first = _Source('first', {
          '/one': [_file('/one/a', 1)],
        });
        final original = _Source('original', {
          '/accepted': [_file('/accepted/b', 8)],
          '/unstarted': [_file('/unstarted/c', 99)],
        });
        final healthy = _Source('healthy', {
          '/healthy': [_file('/healthy/d', 3)],
        });
        final store = _GatedStore(
          holdFirst: true,
          failPath: failAcceptedSave ? '/accepted' : null,
        );
        final batch = StorageScanBatchService(
          roots: [
            _root(first, '/one'),
            _root(original, '/accepted', serialKey: original),
            _root(original, '/unstarted', serialKey: original),
            _root(healthy, '/healthy'),
          ],
          snapshots: store,
        );
        addTearDown(batch.dispose);
        final done = batch.start();
        await store.firstEntered.future;
        await _until(
          batch,
          () => batch.jobs[1].phase == StorageScanBatchPhase.saving,
        );
        expect(store.savedPaths, ['/one']);
        original.current = false;
        store.firstRelease.complete();
        await done;
        final accepted = batch.jobs[1];
        if (failAcceptedSave) {
          expect(accepted.phase, StorageScanBatchPhase.failed);
          expect(accepted.error, contains('Disk full'));
          expect(accepted.snapshot, isNull);
        } else {
          expect(accepted.phase, StorageScanBatchPhase.saved);
          expect(accepted.snapshot!.storageId, 'remote:memory:original');
          final report = await store.load(accepted.snapshot!.id);
          expect(report.result.root.children.single.path, '/accepted/b');
          expect(report.result.root.bytes, 8);
        }
        expect(batch.jobs[2].phase, StorageScanBatchPhase.sourceChanged);
        expect(original.stats, isNot(contains('/unstarted')));
        expect(batch.jobs.first.snapshot!.bytes, 1);
        expect(batch.jobs.last.snapshot!.bytes, 3);
        expect(await store.list(), hasLength(failAcceptedSave ? 2 : 3));
      },
    );
  }

  test(
    'Stop during catalog acknowledgement preserves the committed report',
    () async {
      final memory = _CommitGate();
      final store = StorageScanSnapshotStore(storage: memory);
      final source = _Source('original', {
        '/data': [_file('/data/file', 6)],
      });
      final batch = StorageScanBatchService(
        roots: [_root(source, '/data')],
        snapshots: store,
      );
      addTearDown(batch.dispose);
      final done = batch.start();
      await memory.committed.future;
      batch.cancel();
      memory.acknowledged.complete();
      await done;
      expect(batch.jobs.single.phase, StorageScanBatchPhase.saved);
      expect(batch.jobs.single.snapshot!.bytes, 6);
      expect(await store.list(), hasLength(1));
    },
  );

  test(
    'Stop cannot turn an unconfirmed commit into a claim that nothing was saved',
    () async {
      final memory = _UnconfirmedCommit();
      final store = StorageScanSnapshotStore(storage: memory);
      final source = _Source('original', {
        '/data': [_file('/data/file', 13)],
      });
      final batch = StorageScanBatchService(
        roots: [_root(source, '/data')],
        snapshots: store,
      );
      addTearDown(batch.dispose);
      final done = batch.start();
      await memory.committed.future;
      batch.cancel();
      memory.acknowledge.complete();
      await done;
      expect(batch.jobs.single.phase, StorageScanBatchPhase.unconfirmed);
      expect(batch.jobs.single.snapshot, isNull);
      expect(batch.jobs.single.summary!.bytes, 13);
      expect(batch.jobs.single.error, isNull);
      await expectLater(store.list(), throwsStateError);
      memory.indexUnavailable = false;
      final history = await store.list();
      expect(history, hasLength(1));
      expect(history.single.storageId, 'remote:memory:original');
      final report = await store.load(history.single.id);
      expect(report.result.root.children.single.path, '/data/file');
      expect(report.result.root.bytes, 13);
      expect(report.result.isComplete, isTrue);
    },
  );
}
