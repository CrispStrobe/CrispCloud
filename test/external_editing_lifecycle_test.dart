import 'dart:async';

import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/external_edit_fakes.dart';

void main() {
  late FakeEditStagingStore store;
  late FakeEditClient client;
  late ExternalRemoteEditingService service;
  final managers = <ExternalRemoteEditingService>[];

  ExternalRemoteEditingService manager() {
    final result = ExternalRemoteEditingService(
      staging: store,
      debounce: const Duration(hours: 1),
      pollInterval: const Duration(hours: 2),
    );
    managers.add(result);
    return result;
  }

  setUp(() {
    store = FakeEditStagingStore();
    client = FakeEditClient();
    service = manager();
  });
  tearDown(() async {
    for (final current in managers.reversed) {
      // Failure-injection tests already assert the shutdown outcome. Repeated
      // callers may observe the same cached error after every lease is released.
      try {
        await current.close();
      } catch (_) {}
    }
    managers.clear();
  });

  test(
    'failed discard leaves surviving edits discoverable in the same manager',
    () async {
      final original = await service.prepare(client.source());
      const edited = [7, 8, 9];
      store.edit(original, edited, notify: false);
      await original.scan();
      store.failDeletionOnce.add(original.id);
      await expectLater(
        original.discard(editorClosed: true),
        throwsA(anything),
      );

      expect(store.bundles.containsKey(original.id), isTrue);
      expect(original.isClosed, isTrue);
      final recovered = (await service.restore()).singleWhere(
        (item) => item.id == original.id,
      );
      expect(identical(recovered, original), isFalse);
      expect(store.bundles[original.id]!.leased, isTrue);
      expect(recovered.isClosed, isFalse);
      expect(recovered.isClosing, isFalse);
      expect(recovered.isBound, isFalse);
      expect(recovered.watching, isFalse);
      final file = await recovered.workingFile(forExport: true);
      expect(file.sha256, editHash(edited));
      expect(
        await recovered.stage.openRead(file).expand((chunk) => chunk).toList(),
        edited,
      );
      expect(client.writes, 0);

      await recovered.discard(editorClosed: true);
      expect(store.bundles.containsKey(original.id), isFalse);
      expect(service.sessions.where((item) => item.id == original.id), isEmpty);
    },
  );

  test('one failed close still stops later watchers and releases every session lease', () async {
    final first = await service.prepare(client.source());
    final second = await service.prepare(client.source());
    await first.watch(autoUpload: true);
    await second.watch(autoUpload: true);
    store.failCloseOnce.add(first.id);

    try {
      await service.close();
    } catch (_) {}
    expect(
      store.failCloseOnce,
      isNot(contains(first.id)),
      reason: 'The configured first-session close failure was exercised.',
    );
    for (final session in [first, second]) {
      expect(session.watching, isFalse, reason: session.id);
      expect(session.autoUpload, isFalse, reason: session.id);
      expect(store.bundles[session.id]!.leased, isFalse, reason: session.id);
    }
    await expectLater(second.scan(), throwsA(isA<ExternalEditException>()));
    expect(client.writes, 0);

    final restarted = manager();
    final recovered = await restarted.restore();
    expect(recovered.map((item) => item.id).toSet(), {first.id, second.id});
    expect(recovered.every((item) => !item.isBound && !item.watching), isTrue);
  });

  test(
    'concurrent manager close callers wait for the same pending shutdown',
    () async {
      final session = await service.prepare(client.source());
      await session.watch(autoUpload: false);
      final entered = Completer<void>(), release = Completer<void>();
      store.beforeClose = (id) async {
        if (id == session.id) {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        }
      };
      final first = service.close();
      await entered.future;
      var secondCompleted = false;
      final second = service.close().then((_) => secondCompleted = true);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(
          secondCompleted,
          isFalse,
          reason: 'An already-started close must not look complete while its lease remains held.',
        );
        expect(store.bundles[session.id]!.leased, isTrue);
      } finally {
        release.complete();
        await Future.wait([first, second]);
      }
      expect(secondCompleted, isTrue);
      expect(store.bundles[session.id]!.leased, isFalse);
      expect(session.watching, isFalse);
      expect(client.writes, 0);
    },
  );

  test(
    'failed pause metadata still stops watchers and releases retained stages',
    () async {
      final first = await service.prepare(client.source());
      final second = await service.prepare(client.source());
      final expectedBytes = <String, List<int>>{
        first.id: [3, 4, 5],
        second.id: [6, 7, 8],
      };
      for (final session in [first, second]) {
        store.edit(session, expectedBytes[session.id]!, notify: false);
        await session.watch(autoUpload: true);
      }
      var failedWrites = 0;
      store.beforeManifest = (manifest) async {
        if (manifest['phase'] == ExternalEditPhase.paused.name) {
          failedWrites++;
          throw StateError('pause metadata failed');
        }
      };

      await expectLater(service.close(), throwsA(isA<StateError>()));
      expect(failedWrites, 2);
      for (final session in [first, second]) {
        expect(session.isClosed, isTrue, reason: session.id);
        expect(session.watching, isFalse, reason: session.id);
        expect(session.autoUpload, isFalse, reason: session.id);
        expect(store.bundles[session.id]!.leased, isFalse, reason: session.id);
        expect(
          store.bundles[session.id]!.files[session.record!.workingName],
          expectedBytes[session.id],
        );
      }
      expect(client.writes, 0);

      store.beforeManifest = null;
      final recovered = await manager().restore();
      expect(
        recovered.map((item) => item.id).toSet(),
        expectedBytes.keys.toSet(),
      );
      for (final session in recovered) {
        expect(session.isBound, isFalse);
        expect(session.watching, isFalse);
        final working = await session.workingFile(forExport: true);
        expect(working.sha256, editHash(expectedBytes[session.id]!));
      }
    },
  );

  test(
    'discard finishing during shutdown does not skip later session cleanup',
    () async {
      client.path = '/work/first.txt';
      final first = await service.prepare(client.source());
      client.path = '/work/discarded.txt';
      final discarded = await service.prepare(client.source());
      client.path = '/work/last.txt';
      final last = await service.prepare(client.source());
      for (final session in [first, discarded, last]) {
        await session.watch(autoUpload: false);
      }

      final discardEntered = Completer<void>();
      final releaseDiscard = Completer<void>();
      final closeEntered = Completer<void>();
      final releaseClose = Completer<void>();
      store.beforeManifest = (manifest) async {
        if (manifest['name'] == discarded.record!.name &&
            manifest['phase'] == ExternalEditPhase.paused.name) {
          if (!discardEntered.isCompleted) discardEntered.complete();
          await releaseDiscard.future;
        }
      };
      store.beforeClose = (id) async {
        if (id == first.id) {
          if (!closeEntered.isCompleted) closeEntered.complete();
          await releaseClose.future;
        }
      };

      final discarding = discarded.discard(editorClosed: true);
      await discardEntered.future;
      final closing = service.close();
      try {
        await closeEntered.future;
        releaseDiscard.complete();
        await discarding;
        expect(store.bundles.containsKey(discarded.id), isFalse);
        expect(store.bundles[last.id]!.leased, isTrue);
        releaseClose.complete();
        await expectLater(closing, completes);
        expect(last.watching, isFalse);
        expect(store.bundles[last.id]!.leased, isFalse);
        expect(client.writes, 0);
      } finally {
        if (!releaseDiscard.isCompleted) releaseDiscard.complete();
        if (!releaseClose.isCompleted) releaseClose.complete();
        await discarding;
        try {
          await closing;
        } catch (_) {}
        // Even a regression must release the last watcher's test timer.
        await last.close();
      }
    },
  );
}
