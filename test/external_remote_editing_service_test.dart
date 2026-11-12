import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/services/conditional_file_publication.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:crisp_cloud/services/private_tool_staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/external_edit_fakes.dart';

Matcher editFailure(ExternalEditFailure failure) => isA<ExternalEditException>()
    .having((error) => error.failure, 'failure', failure);

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
    for (final manager in managers.reversed) {
      await manager.close();
    }
    managers.clear();
  });

  test('prepare records exact origin and verified baseline without launching or writing', () async {
    final source = client.source();
    final session = await service.prepare(source);
    expect(session.record!.reference.id, source.reference.id);
    expect(session.record!.baseline, client.version);
    expect(session.record!.baselineSha256, editHash(client.bytes));
    expect(session.record!.localSha256, editHash(client.bytes));
    expect(session.record!.launched, isFalse);
    expect(session.watching, isFalse);
    expect(client.writes, 0);
    expect(
      store.bundles[session.id]!.manifest!['reference'],
      source.reference.toJson(),
    );
    expect(
      store.bundles[session.id]!.manifest.toString(),
      isNot(contains('access_token')),
    );
  });

  test(
    'nonpublisher stages retained changes but can never report a remote save',
    () async {
      final other = FakeReadOnlyEditClient();
      final session = await service.prepare(other.source());
      expect(session.record!.phase, ExternalEditPhase.ready);
      expect(session.canPublish, isFalse);
      store.edit(session, [7, 8]);
      await session.watch(autoUpload: false);
      await session.scan();
      expect(session.record!.hasLocalChanges, isTrue);
      expect(session.record!.savedGeneration, 0);
      await expectLater(
        session.upload(),
        throwsA(editFailure(ExternalEditFailure.unsupported)),
      );
      expect((await session.workingFile()).sha256, editHash([7, 8]));
      expect(other.bytes, [1, 2]);
    },
  );

  test(
    'whole preparation deadline rejects a slowly continuing source',
    () async {
      var now = DateTime.utc(2026);
      final bounded = ExternalRemoteEditingService(
        staging: store,
        now: () => now,
      );
      managers.add(bounded);
      client.afterRead = () async {
        now = now.add(const Duration(minutes: 3));
      };
      final session = await bounded.prepare(client.source());
      expect(session.record!.failure, ExternalEditFailure.stagingFailed);
      expect(session.record!.localSha256, isNull);
      expect(client.writes, 0);
    },
  );

  test('fresh materialization revision catches changes absent from listing metadata', () async {
    final captured = client.source();
    client.afterRead = () async {
      client.remoteEdit([8, 9]);
    };
    final session = await service.prepare(captured);
    expect(session.record!.localSha256, isNull);
    expect(session.record!.phase, ExternalEditPhase.paused);
    expect(client.writes, 0);
  });

  test(
    'save bursts coalesce into one complete generation and serial publication',
    () async {
      final session = await service.prepare(client.source());
      await session.watch(autoUpload: true);
      store.edit(session, [3]);
      store.edit(session, [4]);
      store.edit(session, [5]);
      await session.scan();
      expect(client.uploaded, [
        [5],
      ]);
      expect(client.maximumActiveWrites, 1);
      expect(session.record!.generation, 1);
      expect(session.record!.savedGeneration, 1);
      expect(session.record!.attempt, isNull);
      expect(session.record!.hasLocalChanges, isFalse);
    },
  );

  test(
    'new save before commit prevents stale generation publication',
    () async {
      final session = await service.prepare(client.source());
      await session.watch(autoUpload: true);
      store.edit(session, [3]);
      client.beforeCommit = () async {
        store.edit(session, [4]);
      };
      await session.scan();
      expect(client.writes, 0);
      expect(session.record!.phase, ExternalEditPhase.pending);
      client.beforeCommit = null;
      await session.scan();
      expect(client.uploaded, [
        [4],
      ]);
      expect(session.record!.savedGeneration, 2);
    },
  );

  test('save after commit begins stays pending and is uploaded only after prior acknowledgement', () async {
    final session = await service.prepare(client.source());
    store.edit(session, [3]);
    final committed = Completer<void>();
    final acknowledge = Completer<void>();
    client.afterCommit = () async {
      if (!committed.isCompleted) {
        committed.complete();
        await acknowledge.future;
      }
    };
    final first = session.upload();
    await committed.future;
    final pending = store.bundles[session.id]!.manifest!['attempt'] as Map;
    expect(pending['providerHash'], editHash([3]));
    store.edit(session, [4]);
    final second = session.upload();
    expect(client.writes, 1);
    acknowledge.complete();
    await Future.wait([first, second]);
    expect(client.uploaded, [
      [3],
      [4],
    ]);
    expect(client.maximumActiveWrites, 1);
    expect(session.record!.generation, 2);
    expect(session.record!.savedGeneration, 2);
  });

  test('lost acknowledgement survives restart and reconciles without duplicate upload', () async {
    final session = await service.prepare(client.source());
    store.edit(session, [3]);
    client.loseAcknowledgement = true;
    await expectLater(
      session.upload(),
      throwsA(isA<FilePublicationException>()),
    );
    expect(session.record!.phase, ExternalEditPhase.uncertain);
    expect(session.record!.attempt!.providerHash, editHash([3]));
    final snapshotName = session.record!.attempt!.name;
    await service.close();
    final recoveredService = manager();
    final recovered = (await recoveredService.restore()).single;
    expect(recovered.isBound, isFalse);
    expect(recovered.watching, isFalse);
    expect(client.writes, 1);
    client.account = 'different-account-with-the-same-email';
    await expectLater(
      recovered.rebind(client.source()),
      throwsA(editFailure(ExternalEditFailure.sourceChanged)),
    );
    expect(recovered.isBound, isFalse);
    expect(
      store.bundles[recovered.id]!.files.containsKey(snapshotName),
      isTrue,
    );
    client.account = 'original';
    client.loseAcknowledgement = false;
    await recovered.rebind(client.source());
    expect(client.writes, 1);
    expect(recovered.record!.attempt, isNull);
    expect(recovered.record!.savedGeneration, 1);
    expect(recovered.record!.hasLocalChanges, isFalse);
    expect(recovered.watching, isFalse);
    expect(
      store.bundles[recovered.id]!.files.containsKey(snapshotName),
      isFalse,
    );
  });

  test('remote conflict review is single-use and rechecks both remote revision and local generation', () async {
    final session = await service.prepare(client.source());
    store.edit(session, [3]);
    client.remoteEdit([9]);
    await expectLater(
      session.upload(),
      throwsA(isA<FilePublicationException>()),
    );
    expect(session.record!.phase, ExternalEditPhase.conflict);
    expect(client.writes, 0);
    final staleRemote = await session.reviewConflict();
    client.remoteEdit([8]);
    await expectLater(
      session.replaceReviewed(staleRemote),
      throwsA(isA<FilePublicationException>()),
    );
    final staleLocal = await session.reviewConflict();
    store.edit(session, [4]);
    await expectLater(
      session.replaceReviewed(staleLocal),
      throwsA(editFailure(ExternalEditFailure.localChanged)),
    );
    final reviewed = await session.reviewConflict();
    await session.replaceReviewed(reviewed);
    expect(client.bytes, [4]);
    expect(client.writes, 1);
    await expectLater(
      session.replaceReviewed(reviewed),
      throwsA(editFailure(ExternalEditFailure.localChanged)),
    );
  });

  test(
    'replacement object or renamed path cannot be approved as the original',
    () async {
      final session = await service.prepare(client.source());
      store.edit(session, [3]);
      client.objectId = 'id:other';
      await expectLater(
        session.reviewConflict(),
        throwsA(editFailure(ExternalEditFailure.sourceChanged)),
      );
      expect(client.writes, 0);
      expect((await session.workingFile()).sha256, editHash([3]));
    },
  );

  test(
    'failed durable intent prevents original mutation and retains unsent bytes',
    () async {
      final session = await service.prepare(client.source());
      store.edit(session, [3]);
      store.beforeManifest = (manifest) async {
        final attempt = manifest['attempt'];
        if (attempt is Map && attempt['providerHash'] != null) {
          throw StateError('disk full');
        }
      };
      await expectLater(session.upload(), throwsStateError);
      expect(client.writes, 0);
      expect(client.bytes, [1, 2]);
      expect((await session.workingFile()).sha256, editHash([3]));
      expect(session.record!.phase, ExternalEditPhase.pending);
      store.beforeManifest = null;
      await session.upload();
      expect(client.bytes, [3]);
    },
  );

  test(
    'account availability loss never switches source and preserves local work',
    () async {
      final session = await service.prepare(client.source());
      store.edit(session, [3]);
      client.current = false;
      await expectLater(
        session.upload(),
        throwsA(editFailure(ExternalEditFailure.sourceChanged)),
      );
      expect(client.writes, 0);
      expect((await session.workingFile()).sha256, editHash([3]));
    },
  );

  test(
    'close retains; only explicit confirmed cleanup removes the owned stage',
    () async {
      final first = await service.prepare(client.source());
      final second = await service.prepare(client.source());
      await expectLater(
        Future<void>.sync(() => first.discard(editorClosed: false)),
        throwsA(editFailure(ExternalEditFailure.busy)),
      );
      await first.discard(editorClosed: true);
      expect(store.bundles.containsKey(first.id), isFalse);
      expect(store.bundles.containsKey(second.id), isTrue);
      await service.close();
      expect(store.bundles.containsKey(second.id), isTrue);
      expect(store.bundles[second.id]!.leased, isFalse);
    },
  );

  test('invalid recovery instructions never authorize work and remain explicitly removable', () async {
    final session = await service.prepare(client.source());
    await service.close();
    store.bundles[session.id]!.manifest!['workingName'] = '../outside';
    final restored = (await manager().restore()).single;
    expect(restored.record, isNull);
    expect(restored.watching, isFalse);
    expect(client.writes, 0);
    await restored.discard(editorClosed: true);
    expect(store.bundles, isEmpty);
  });

  test('native directory watch observes atomic-save replacement and retains edits after close', () async {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) return;
    final temporary = await Directory.systemTemp.createTemp(
      'external-edit-watch-',
    );
    final native = ExternalRemoteEditingService(
      staging: PrivateToolStagingStore(
        rootDirectory: () async => p.join(temporary.path, 'stages'),
      ),
      debounce: const Duration(milliseconds: 15),
      pollInterval: const Duration(milliseconds: 100),
    );
    managers.add(native);
    try {
      final session = await native.prepare(client.source());
      await session.watch(autoUpload: true);
      final working = await session.workingFile();
      final replacement = File(
        p.join(session.directoryPath, 'editor-save.tmp'),
      );
      await replacement.writeAsBytes([7, 8, 9], flush: true);
      await replacement.rename(working.path);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (client.writes == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(client.uploaded, [
        [7, 8, 9],
      ]);
      await native.close();
      expect(await File(working.path).readAsBytes(), [7, 8, 9]);
    } finally {
      await native.close();
      await temporary.delete(recursive: true);
    }
  });
}
