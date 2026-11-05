// Regression tests for the save-state race described in the editor evaluation.
//
// The previous implementation always cleared the modified flag after an
// upload, even when the user had typed while the upload was in flight. These
// tests pin the revision-aware behavior.

import 'dart:async';

import 'package:crisp_cloud/services/save_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('SaveCoordinator', () {
    test('an edit during an upload leaves the document dirty', () async {
      final coordinator = SaveCoordinator<String>();
      addTearDown(coordinator.dispose);
      coordinator.markLoaded();

      final upload = Completer<void>();
      var writes = 0;
      final save = coordinator.save(
        snapshot: () => SaveSnapshot<String>(
          revision: coordinator.revision,
          value: 'first',
        ),
        write: (_) async {
          writes++;
          await upload.future;
        },
      );

      expect(coordinator.isSaving, isTrue);
      coordinator.markChanged();
      expect(coordinator.isDirty, isTrue);

      upload.complete();
      final result = await save;

      expect(result.isSuccess, isTrue);
      expect(
        result.isDirty,
        isTrue,
        reason: 'The newest text was not part of the uploaded snapshot.',
      );
      expect(coordinator.isDirty, isTrue);
      // The first save wrote revision 0; the edit made during the upload is
      // revision 1 and remains unsaved.
      expect(coordinator.savedRevision, 0);
      expect(coordinator.revision, 1);
      expect(writes, 1);
    });

    test(
      'a save requested during an upload runs after it with new text',
      () async {
        final coordinator = SaveCoordinator<String>();
        addTearDown(coordinator.dispose);
        coordinator.markLoaded();

        final firstUpload = Completer<void>();
        final secondUpload = Completer<void>();
        final writes = <String>[];

        final first = coordinator.save(
          snapshot: () =>
              SaveSnapshot<String>(revision: coordinator.revision, value: 'v1'),
          write: (snapshot) async {
            writes.add(snapshot.value);
            await firstUpload.future;
          },
        );

        coordinator.markChanged();
        final second = coordinator.save(
          snapshot: () =>
              SaveSnapshot<String>(revision: coordinator.revision, value: 'v2'),
          write: (snapshot) async {
            writes.add(snapshot.value);
            await secondUpload.future;
          },
        );

        expect(writes, <String>['v1']);
        firstUpload.complete();
        await _pump();
        expect(writes, <String>[
          'v1',
          'v2',
        ], reason: 'Queued saves must serialize, not overlap.');

        secondUpload.complete();
        final secondResult = await second;
        expect(secondResult.isSuccess, isTrue);
        expect(secondResult.isDirty, isFalse);
        expect(coordinator.isDirty, isFalse);
        // The first save wrote revision 0, the queued save wrote revision 1.
        expect(coordinator.savedRevision, 1);
        expect(coordinator.revision, 1);

        // The first call completes only once the queued chain is idle.
        final firstResult = await first;
        expect(firstResult.isSuccess, isTrue);
        expect(coordinator.isSaving, isFalse);
      },
    );

    test('writes never overlap', () async {
      final coordinator = SaveCoordinator<String>();
      addTearDown(coordinator.dispose);
      coordinator.markLoaded();

      var active = 0;
      var maxActive = 0;
      final gates = <Completer<void>>[Completer<void>(), Completer<void>()];
      final writes = <String>[];

      final first = coordinator.save(
        snapshot: () =>
            SaveSnapshot<String>(revision: coordinator.revision, value: 'a'),
        write: (snapshot) async {
          writes.add(snapshot.value);
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await gates[0].future;
          active--;
        },
      );
      coordinator.markChanged();
      final second = coordinator.save(
        snapshot: () =>
            SaveSnapshot<String>(revision: coordinator.revision, value: 'b'),
        write: (snapshot) async {
          writes.add(snapshot.value);
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await gates[1].future;
          active--;
        },
      );

      gates[0].complete();
      await _pump();
      gates[1].complete();
      await Future.wait(<Future<EditorSaveResult>>[first, second]);

      expect(maxActive, 1);
      expect(writes, <String>['a', 'b']);
    });

    test(
      'a failed upload keeps the document dirty and records the error',
      () async {
        final coordinator = SaveCoordinator<String>();
        addTearDown(coordinator.dispose);
        coordinator.markLoaded();
        coordinator.markChanged();

        final save = coordinator.save(
          snapshot: () => SaveSnapshot<String>(
            revision: coordinator.revision,
            value: 'text',
          ),
          write: (_) async => throw StateError('network down'),
        );

        final result = await save;
        expect(result.status, EditorSaveStatus.failed);
        expect(result.error, isA<StateError>());
        expect(coordinator.isDirty, isTrue);
        expect(coordinator.lastError, isA<StateError>());
        expect(coordinator.isSaving, isFalse);
      },
    );

    test('queued waiters learn that the upload failed', () async {
      final coordinator = SaveCoordinator<String>();
      addTearDown(coordinator.dispose);
      coordinator.markLoaded();

      final gate = Completer<void>();
      final first = coordinator.save(
        snapshot: () =>
            SaveSnapshot<String>(revision: coordinator.revision, value: 'a'),
        write: (_) async {
          await gate.future;
          throw StateError('upload failed');
        },
      );
      coordinator.markChanged();
      final second = coordinator.save(
        snapshot: () =>
            SaveSnapshot<String>(revision: coordinator.revision, value: 'b'),
        write: (_) async {},
      );

      gate.complete();
      final results = await Future.wait(<Future<EditorSaveResult>>[
        first,
        second,
      ]);
      expect(results[0].status, EditorSaveStatus.failed);
      expect(results[1].status, EditorSaveStatus.failed);
      expect(coordinator.isDirty, isTrue);
    });

    test('markLoaded resets revisions and pending state', () {
      final coordinator = SaveCoordinator<String>();
      addTearDown(coordinator.dispose);

      coordinator.markChanged();
      coordinator.markChanged();
      expect(coordinator.revision, 2);
      expect(coordinator.isDirty, isTrue);

      coordinator.markLoaded();
      expect(coordinator.revision, 0);
      expect(coordinator.savedRevision, 0);
      expect(coordinator.isDirty, isFalse);
      expect(coordinator.hasPendingSave, isFalse);
    });
  });
}
