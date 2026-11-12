import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/models/gathering_stack.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/gathering_stack_service.dart';
import 'package:crisp_cloud/services/gathering_stack_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/gathering_stack_fixture.dart';

class _FailingStorage extends MemoryFileCollectionStorage {
  bool fail = false;
  bool failAfterCommit = false;
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    if (fail) throw StateError('Write unavailable');
    final result = await super.compareAndSwap(key, expected, value);
    if (failAfterCommit) throw StateError('Acknowledgement lost');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryFileCollectionStorage storage;
  late GatheringStackStore store;
  late GatheringStackService service;
  late GatheringMemoryBackend a, b, target;

  setUp(() async {
    storage = MemoryFileCollectionStorage();
    store = GatheringStackStore(storage: storage);
    service = GatheringStackService(store);
    a = GatheringMemoryBackend(gatheringAccountA);
    b = GatheringMemoryBackend(gatheringAccountB);
    target = GatheringMemoryBackend(gatheringTarget)..directory('/target ');
    await store.ready;
  });
  tearDown(() => store.dispose());

  GatheringSourceBinding? resolve(StorageReference reference, String path) {
    if (reference == a.reference) return a.binding();
    if (reference == b.reference) return b.binding();
    return null;
  }

  Future<void> add(
    GatheringMemoryBackend backend,
    String path, {
    bool sessionBound = false,
  }) async => service.add([
    GatheringAddition(
      file: backend.items[path]!,
      source: backend.binding(),
      sessionBound: sessionBound,
    ),
  ]);

  Future<GatheringReview> review() => service.verify(
    service.capture(
      resolve: resolve,
      destination: target.destination('/target '),
    ),
    control: FileOperationControl(),
  );

  Future<FileOperationPlan> plan(
    GatheringReview review,
    GatheringMemoryBackend backend, {
    FileOperationOptions options = const FileOperationOptions(),
  }) => const FileOperationService().prepare(
    files: [
      for (final item in review.capture.entries)
        if (item.reference.storage == backend.reference)
          review.verified[item.id]!.file,
    ],
    source: backend,
    destination: target,
    targetDirectory: '/target ',
    options: options,
    protectedDestinationPaths: [
      for (final item in review.capture.entries)
        if (item.reference.storage == target.reference) item.reference.path,
    ],
  );

  test('same names, paths, and object IDs on independent accounts persist separately', () async {
    a.file('/in/same.txt', 'A', objectId: 'same-object');
    b.file('/in/same.txt', 'B', objectId: 'same-object');
    await add(a, '/in/same.txt');
    await add(b, '/in/same.txt');
    expect(store.entries, hasLength(2));
    final reopened = GatheringStackStore(storage: storage);
    await reopened.ready;
    expect(reopened.entries.map((entry) => entry.reference.storage), [
      a.reference,
      b.reference,
    ]);
    expect(reopened.entries.map((entry) => entry.reference.path), [
      '/in/same.txt',
      '/in/same.txt',
    ]);
    reopened.dispose();
  });

  test(
    'dedup uses original object or exact path and retains case-distinct paths',
    () async {
      a.file('/one/name.txt', 'one', objectId: 'object-1');
      a.file('/two/name.txt', 'two', objectId: 'object-2');
      a.file('/case/A.txt', 'upper');
      a.file('/case/a.txt', 'lower');
      await add(a, '/one/name.txt');
      final oldTicket = store.entries.single.id;
      await add(a, '/one/name.txt');
      expect(store.entries.single.id, isNot(oldTicket));
      await add(a, '/two/name.txt');
      await add(a, '/case/A.txt');
      await add(a, '/case/a.txt');
      expect(store.entries, hasLength(4));
      a.file('/renamed.txt', 'one', objectId: 'object-1');
      await add(a, '/renamed.txt');
      expect(store.entries, hasLength(4));
      expect(store.entries.first.reference.path, '/renamed.txt');
      await store.move(store.entries.last.id, -3);
      final order = store.entries.map((entry) => entry.reference.path).toList();
      final restored = GatheringStackStore(storage: storage);
      await restored.ready;
      expect(restored.entries.map((entry) => entry.reference.path), order);
      await restored.remove(restored.entries.first.id);
      expect(restored.entries, hasLength(3));
      expect(a.items.containsKey('/case/a.txt'), isTrue);
      restored.dispose();
    },
  );

  test('different namespace roots never deduplicate', () async {
    final other = GatheringMemoryBackend(
      const StorageReference(
        kind: 'remote',
        provider: 'Memory',
        accountKey: 'account-a',
        root: '/other',
      ),
    );
    a.file('/same', 'A', objectId: 'id');
    other.file('/same', 'B', objectId: 'id');
    await add(a, '/same');
    await add(other, '/same');
    expect(store.entries, hasLength(2));
  });

  test('missing, replaced, and offline references cannot prepare a transfer or adopt a new baseline', () async {
    a.file('/missing', 'old', objectId: 'missing');
    a.file('/replaced', 'old', objectId: 'old');
    b.file('/offline', 'B', objectId: 'offline');
    await add(a, '/missing');
    await add(a, '/replaced');
    await add(b, '/offline');
    a.items.remove('/missing');
    a.file('/replaced', 'new', objectId: 'new');
    b.current = false;
    final result = await review();
    expect(result.canTransfer, isFalse);
    expect(store.entries.map((entry) => store.stateFor(entry.id)), [
      GatheringReferenceState.missing,
      GatheringReferenceState.replaced,
      GatheringReferenceState.offline,
    ]);
    expect(store.entries[1].reference.objectId, 'old');
    expect(
      (await review()).states[store.entries[1].id],
      GatheringReferenceState.replaced,
    );
    expect(target.writes, isEmpty);
  });

  test('all source sessions are captured before the first await', () async {
    a.file('/a', 'A');
    b.file('/b', 'B');
    await add(a, '/a');
    await add(b, '/b');
    final captured = service.capture(
      resolve: resolve,
      destination: target.destination('/target '),
    );
    final before = b;
    b = GatheringMemoryBackend(gatheringAccountB)..file('/b', 'replacement');
    before.current = false;
    final result = await service.verify(
      captured,
      control: FileOperationControl(),
    );
    expect(result.canTransfer, isFalse);
    expect(
      result.states[store.entries.last.id],
      GatheringReferenceState.offline,
    );
    expect(b.listings, isEmpty);
  });

  test('a restored session-bound reference cannot resolve to a same-named new grant', () async {
    a.file('/Photos/name.jpg', 'original');
    await add(a, '/Photos/name.jpg', sessionBound: true);
    final restored = GatheringStackStore(storage: storage);
    await restored.ready;
    var resolverCalls = 0;
    final restarted = GatheringStackService(restored);
    final result = await restarted.verify(
      restarted.capture(
        resolve: (storage, path) {
          resolverCalls++;
          return a.binding();
        },
      ),
      control: FileOperationControl(),
    );
    expect(resolverCalls, 0);
    expect(result.states.values, [GatheringReferenceState.sessionOnly]);
    expect(restored.entries, hasLength(1));
    restored.dispose();
  });

  test('canceling a stuck provider read completes promptly and discards late results', () async {
    a.file('/a', 'A');
    await add(a, '/a');
    final gate = Completer<void>();
    a.beforeList = (_) => gate.future;
    final control = FileOperationControl();
    final future = service.verify(
      service.capture(resolve: resolve),
      control: control,
    );
    await Future<void>.delayed(Duration.zero);
    control.cancel();
    await expectLater(
      future,
      throwsA(
        isA<GatheringException>().having(
          (error) => error.failure,
          'failure',
          GatheringFailure.cancelled,
        ),
      ),
    );
    expect(store.entries, hasLength(1));
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      store.stateFor(store.entries.single.id),
      GatheringReferenceState.unchecked,
    );
    expect(target.writes, isEmpty);
  });

  test('a newer stack intent invalidates an in-flight check', () async {
    a.file('/a', 'A');
    await add(a, '/a');
    final gate = Completer<void>();
    a.beforeList = (_) => gate.future;
    final future = service.verify(
      service.capture(resolve: resolve),
      control: FileOperationControl(),
    );
    await Future<void>.delayed(Duration.zero);
    await store.remove(store.entries.single.id);
    gate.complete();
    await expectLater(
      future,
      throwsA(
        isA<GatheringException>().having(
          (error) => error.failure,
          'failure',
          GatheringFailure.changed,
        ),
      ),
    );
    expect(store.entries, isEmpty);
  });

  test('destination account, exact whitespace path, and navigation intent stay pinned', () async {
    a.file('/a', 'A');
    await add(a, '/a');
    var current = true;
    final destination = target.destination(
      '/target ',
      isCurrent: () => current,
    );
    final result = await service.verify(
      service.capture(resolve: resolve, destination: destination),
      control: FileOperationControl(),
    );
    final prepared = await plan(result, a);
    result.validatePlan(prepared);
    expect(prepared.targetDirectory, '/target ');
    final wrongTarget = GatheringMemoryBackend(gatheringAccountB)
      ..directory('/target ');
    final wrong = await const FileOperationService().prepare(
      files: [a.items['/a']!],
      source: a,
      destination: wrongTarget,
      targetDirectory: '/target ',
    );
    expect(
      () => result.validatePlan(wrong),
      throwsA(isA<GatheringException>()),
    );
    current = false;
    expect(
      () => result.validatePlan(prepared),
      throwsA(
        isA<GatheringException>().having(
          (error) => error.failure,
          'failure',
          GatheringFailure.destinationChanged,
        ),
      ),
    );
    expect(target.writes, isEmpty);
    expect(wrongTarget.writes, isEmpty);
  });

  test('replacement after overview is rejected before the ordinary preview executes', () async {
    a.file('/a', 'original', objectId: 'old', version: '1');
    await add(a, '/a');
    final result = await review();
    a.file('/a', 'replacement', objectId: 'new', version: '2');
    final prepared = await plan(result, a);
    expect(
      () => result.validatePlan(prepared),
      throwsA(
        isA<GatheringException>().having(
          (error) => error.failure,
          'failure',
          GatheringFailure.changed,
        ),
      ),
    );
    expect(target.writes, isEmpty);
  });

  test('same-named accounts use ordinary collisions and canceled later groups keep their references', () async {
    a.file('/a/same.txt', 'A', objectId: 'a');
    b.file('/b/same.txt', 'B', objectId: 'b');
    await add(a, '/a/same.txt');
    await add(b, '/b/same.txt');
    final result = await review();
    final first = await plan(result, a);
    result.validatePlan(first);
    await const FileOperationService().execute(
      first,
      control: FileOperationControl(),
    );
    expect(await service.reconcile(result, first), 1);
    expect(store.entries.single.reference.storage, b.reference);
    final second = await plan(result, b);
    result.validatePlan(second);
    var conflicts = 0;
    await const FileOperationService().execute(
      second,
      control: FileOperationControl(),
      resolveConflict: (entry, existing) async {
        conflicts++;
        return FileConflictDecision.cancel;
      },
    );
    expect(conflicts, 1);
    expect(await service.reconcile(result, second), 0);
    expect(utf8.decode(target.contents['/target /same.txt']!), 'A');
    expect(store.entries.single.reference.storage, b.reference);
  });

  test(
    'partial failure removes only confirmed successful independent files',
    () async {
      for (final name in ['good', 'bad', 'untouched']) {
        a.file('/$name', name, objectId: name);
        await add(a, '/$name');
      }
      target.failWrites.add('/target /bad');
      final result = await review();
      final prepared = await plan(result, a);
      result.validatePlan(prepared);
      await const FileOperationService().execute(
        prepared,
        control: FileOperationControl(),
      );
      expect(prepared.entries.map((entry) => entry.outcome), [
        FileOperationOutcome.copied,
        FileOperationOutcome.failed,
        FileOperationOutcome.cancelled,
      ]);
      expect(await service.reconcile(result, prepared), 1);
      expect(store.entries.map((entry) => entry.reference.path), [
        '/bad',
        '/untouched',
      ]);
      expect(await service.reconcile(result, prepared), 0);
    },
  );

  test('skipped and filtered references stay in the stack', () async {
    a.file('/skip', 'A');
    a.file('/filtered', 'B');
    await add(a, '/skip');
    await add(a, '/filtered');
    target.file('/target /skip', 'Existing');
    final result = await review();
    final prepared = await plan(
      result,
      a,
      options: const FileOperationOptions(
        fileConflict: FileConflictPolicy.skip,
        minimumSize: 1,
      ),
    );
    prepared.entries.last.outcome = FileOperationOutcome.filtered;
    await const FileOperationService().execute(
      prepared,
      control: FileOperationControl(),
    );
    expect(await service.reconcile(result, prepared), 0);
    expect(store.entries, hasLength(2));
  });

  test('a partially copied directory remains while an independently gathered completed child is removed', () async {
    a.file('/tree/good', 'good', objectId: 'good');
    a.file('/tree/bad', 'bad', objectId: 'bad');
    await add(a, '/tree');
    await add(a, '/tree/good');
    target.failWrites.add('/target /tree/bad');
    final result = await review();
    final prepared = await plan(
      result,
      a,
      options: const FileOperationOptions(stopOnError: false),
    );
    result.validatePlan(prepared);
    await const FileOperationService().execute(
      prepared,
      control: FileOperationControl(),
    );
    expect(
      prepared.entries
          .singleWhere((entry) => entry.source.path == '/tree/good')
          .outcome,
      FileOperationOutcome.copied,
    );
    expect(await service.reconcile(result, prepared), 1);
    expect(store.entries.single.reference.path, '/tree');
  });

  test(
    'move cleanup requires confirmed removal of the original folder',
    () async {
      a.file('/tree/child', 'child');
      await add(a, '/tree');
      final result = await review();
      final prepared = await plan(
        result,
        a,
        options: const FileOperationOptions(kind: FileOperationKind.move),
      );
      result.validatePlan(prepared);
      await const FileOperationService().execute(
        prepared,
        control: FileOperationControl(),
      );
      expect(prepared.entries.first.outcome, FileOperationOutcome.moved);
      expect(await service.reconcile(result, prepared), 1);
      expect(store.entries, isEmpty);
      expect(a.items.containsKey('/tree'), isFalse);
    },
  );

  test(
    'late completion cannot remove an explicitly re-gathered original',
    () async {
      a.file('/a', 'A', objectId: 'a');
      await add(a, '/a');
      final result = await review();
      final prepared = await plan(result, a);
      await const FileOperationService().execute(
        prepared,
        control: FileOperationControl(),
      );
      final previous = store.entries.single.id;
      await add(a, '/a');
      expect(store.entries.single.id, isNot(previous));
      expect(await service.reconcile(result, prepared), 0);
      expect(store.entries, hasLength(1));
    },
  );

  test('save failures preserve the last stack and successful commit acknowledgement loss is recovered', () async {
    final backing = _FailingStorage();
    final saved = GatheringStackStore(storage: backing);
    final writer = GatheringStackService(saved);
    await saved.ready;
    a.file('/a', 'A');
    final input = GatheringAddition(file: a.items['/a']!, source: a.binding());
    await writer.add([input]);
    final before = backing.values[GatheringStackStore.recordKey];
    backing.fail = true;
    await expectLater(
      saved.remove(saved.entries.single.id),
      throwsA(isA<GatheringException>()),
    );
    expect(saved.entries, hasLength(1));
    expect(backing.values[GatheringStackStore.recordKey], before);
    backing.fail = false;
    backing.failAfterCommit = true;
    await saved.remove(saved.entries.single.id);
    expect(saved.entries, isEmpty);
    saved.dispose();
  });

  test('corrupt persisted records are not overwritten by an add', () async {
    final backing = MemoryFileCollectionStorage()
      ..values[GatheringStackStore.recordKey] = '{broken';
    final saved = GatheringStackStore(storage: backing);
    await saved.ready;
    expect(saved.loadError, isNotNull);
    a.file('/a', 'A');
    await expectLater(
      GatheringStackService(saved)
          .add([GatheringAddition(file: a.items['/a']!, source: a.binding())]),
      throwsA(isA<GatheringException>()),
    );
    expect(backing.values[GatheringStackStore.recordKey], '{broken');
    saved.dispose();
  });

  test('late cleanup from a superseded operation invalidates a newer overview of those references', () async {
    a.file('/a', 'A');
    b.file('/b', 'B');
    await add(a, '/a');
    await add(b, '/b');
    final previous = await review();
    final completed = await plan(previous, a);
    await const FileOperationService().execute(
      completed,
      control: FileOperationControl(),
    );
    final newer = await review();
    expect(newer.canTransfer, isTrue);
    expect(await service.reconcile(previous, completed), 1);
    expect(newer.canTransfer, isFalse);
    expect(
      newer.capture.check,
      throwsA(
        isA<GatheringException>().having(
          (error) => error.failure,
          'failure',
          GatheringFailure.changed,
        ),
      ),
    );
    expect(store.entries.single.reference.storage, b.reference);
    expect(target.writes, ['/target /a']);
  });

  test('reference count is bounded before persistence and canceled checks write no data', () async {
    final additions = <GatheringAddition>[];
    for (var index = 0; index <= GatheringStackStore.maximumEntries; index++) {
      final item = a.file('/$index', 'x');
      additions.add(GatheringAddition(file: item, source: a.binding()));
    }
    await expectLater(
      service.add(additions),
      throwsA(
        isA<GatheringException>().having(
          (error) => error.failure,
          'failure',
          GatheringFailure.limit,
        ),
      ),
    );
    expect(store.entries, isEmpty);
    expect(storage.values, isEmpty);
  });
}
