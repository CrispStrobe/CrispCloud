import 'dart:async';
import 'dart:typed_data';

import 'package:crisperbooks/crisperbooks.dart';
import 'package:flutter_test/flutter_test.dart';

EpubDocument _openedBook() =>
    EpubDocument.open(EpubDocument.create(title: 'Original title').toBytes());

EbookEditSession _session({int maxHistoryEntries = 24}) {
  final session = EbookEditSession(
    _openedBook(),
    maxHistoryEntries: maxHistoryEntries,
  );
  addTearDown(session.dispose);
  return session;
}

void main() {
  test('opened books start clean and newly created books need saving', () {
    final opened = _session();
    final created = EbookEditSession(EpubDocument.create(title: 'New book'));
    addTearDown(created.dispose);
    expect(opened.isDirty, isFalse);
    expect(created.isDirty, isTrue);
    expect(created.canUndo, isFalse);
  });

  test('undo and redo restore package snapshots and the saved state', () async {
    final session = _session();
    final originalBytes = session.exportBytes();
    session.mutate((book) => book.updateMetadata(title: 'Saved revision'));
    final savedState = session.stateId;
    await session.save((_) async => EbookSaveOutcome.savedOriginal);
    expect(session.isDirty, isFalse);
    expect(session.document.dirty, isFalse);

    session.mutate((book) => book.addChapter(title: 'Another chapter'));
    expect(session.document.chapters, hasLength(2));
    session.undo();
    expect(session.stateId, savedState);
    expect(session.document.chapters, hasLength(1));
    expect(session.document.title, 'Saved revision');
    expect(session.isDirty, isFalse);
    session.undo();
    expect(session.document.title, 'Original title');
    expect(session.exportBytes(), originalBytes);
    expect(session.isDirty, isTrue);
    session.redo();
    expect(session.stateId, savedState);
    expect(session.isDirty, isFalse);
    session.redo();
    expect(session.document.chapters, hasLength(2));
    expect(session.isDirty, isTrue);
  });

  test('editing after undo creates a distinct branch and drops redo', () async {
    final session = _session();
    session.mutate((book) => book.updateMetadata(title: 'First branch'));
    final savedState = session.stateId;
    await session.save((_) async => EbookSaveOutcome.savedOriginal);
    session.undo();
    expect(session.canRedo, isTrue);
    session.mutate((book) => book.updateMetadata(title: 'New branch'));
    expect(session.stateId, isNot(savedState));
    expect(session.canRedo, isFalse);
    expect(session.isDirty, isTrue);
  });

  test(
    'direct document edits cannot reuse a saved state or redo branch',
    () async {
      final session = _session();
      session.mutate((book) => book.updateMetadata(title: 'Saved branch'));
      final savedState = session.stateId;
      await session.save((_) async => EbookSaveOutcome.savedOriginal);
      session.undo();
      expect(session.canRedo, isTrue);

      session.document.updateMetadata(title: 'Direct edit');
      expect(session.isDirty, isTrue);
      expect(session.canRedo, isFalse);
      expect(session.stateId, isNot(savedState));
      session.redo();
      expect(session.document.title, 'Direct edit');
      await session.save((bytes) async {
        expect(EpubDocument.open(bytes).title, 'Direct edit');
        return EbookSaveOutcome.savedOriginal;
      });
      expect(session.isDirty, isFalse);
    },
  );

  test('direct edits during an upload remain dirty after completion', () async {
    final session = _session();
    session.mutate((book) => book.updateMetadata(title: 'Uploaded version'));
    final upload = Completer<EbookSaveOutcome>();
    final saving = session.save((_) => upload.future);
    session.document.updateMetadata(title: 'Unsubmitted direct edit');
    upload.complete(EbookSaveOutcome.savedOriginal);
    await saving;
    expect(session.isDirty, isTrue);
    expect(session.document.dirty, isTrue);
    session.mutate((book) => book.updateMetadata(title: 'Tracked next edit'));
    session.undo();
    expect(session.document.title, 'Unsubmitted direct edit');
    expect(session.isDirty, isTrue);
  });

  test(
    'an asynchronous save submits immutable bytes and keeps newer edits dirty',
    () async {
      final session = _session();
      session.mutate((book) => book.updateMetadata(title: 'Uploaded revision'));
      final submittedState = session.stateId;
      final upload = Completer<EbookSaveOutcome>();
      late Uint8List submitted;
      final saving = session.save((bytes) {
        submitted = bytes;
        return upload.future;
      });
      expect(session.isSaving, isTrue);
      expect(() => submitted[0] = 0, throwsUnsupportedError);
      session.mutate((book) => book.updateMetadata(title: 'Later revision'));
      expect(EpubDocument.open(submitted).title, 'Uploaded revision');
      upload.complete(EbookSaveOutcome.savedOriginal);
      await saving;
      expect(session.isSaving, isFalse);
      expect(session.isDirty, isTrue);
      expect(session.document.dirty, isTrue);
      expect(session.document.title, 'Later revision');
      session.undo();
      expect(session.stateId, submittedState);
      expect(session.isDirty, isFalse);
      expect(session.document.title, 'Uploaded revision');
    },
  );

  test(
    'save completion cannot mark an undo-and-edit branch as saved',
    () async {
      final session = _session();
      session.mutate((book) => book.updateMetadata(title: 'Uploading'));
      final upload = Completer<EbookSaveOutcome>();
      final saving = session.save((_) => upload.future);
      session.undo();
      session.mutate((book) => book.updateMetadata(title: 'Different branch'));
      upload.complete(EbookSaveOutcome.savedOriginal);
      await saving;
      expect(session.document.title, 'Different branch');
      expect(session.isDirty, isTrue);
      expect(session.canRedo, isFalse);
    },
  );

  for (final outcome in [
    EbookSaveOutcome.savedCopy,
    EbookSaveOutcome.downloadedCopy,
  ]) {
    test('$outcome leaves the original revision dirty', () async {
      final session = _session();
      session.mutate((book) => book.updateMetadata(title: 'Exported copy'));
      expect(await session.save((_) async => outcome), outcome);
      expect(session.isDirty, isTrue);
      expect(session.document.dirty, isTrue);
      session.undo();
      expect(session.isDirty, isFalse);
    });
  }

  test(
    'copy-only imports never acknowledge the source as overwritten',
    () async {
      final session = EbookEditSession(
        EpubDocument.create(title: 'Converted ebook'),
        copyOnly: true,
      );
      addTearDown(session.dispose);
      await session.save((_) async => EbookSaveOutcome.savedOriginal);
      expect(session.isDirty, isTrue);
      expect(session.document.dirty, isTrue);
    },
  );

  test(
    'overlapping saves fail and a failed write preserves edits for retry',
    () async {
      final session = _session();
      session.mutate(
        (book) => book.updateMetadata(title: 'Retry this revision'),
      );
      final upload = Completer<EbookSaveOutcome>();
      final saving = session.save((_) => upload.future);
      var secondWriterCalled = false;
      await expectLater(
        session.save((_) async {
          secondWriterCalled = true;
          return EbookSaveOutcome.savedOriginal;
        }),
        throwsStateError,
      );
      expect(secondWriterCalled, isFalse);
      final failure = StateError('Offline');
      final failed = expectLater(saving, throwsA(same(failure)));
      upload.completeError(failure);
      await failed;
      expect(session.isSaving, isFalse);
      expect(session.isDirty, isTrue);
      expect(session.document.title, 'Retry this revision');
      await session.save((bytes) async {
        expect(EpubDocument.open(bytes).title, 'Retry this revision');
        return EbookSaveOutcome.savedOriginal;
      });
      expect(session.isDirty, isFalse);
    },
  );

  test('failed composite mutations restore content, revision and history', () {
    final session = _session();
    final before = session.exportBytes();
    final revision = session.document.revision;
    var notifications = 0;
    session.addListener(() => notifications++);
    expect(
      () => session.mutate((book) {
        book.updateMetadata(title: 'Must be rolled back');
        book.addChapter(title: 'Also rolled back');
        throw StateError('Action failed');
      }),
      throwsStateError,
    );
    expect(session.document.title, 'Original title');
    expect(session.document.chapters, hasLength(1));
    expect(session.document.revision, revision);
    expect(session.exportBytes(), before);
    expect(session.stateId, 0);
    expect(session.isDirty, isFalse);
    expect(session.canUndo, isFalse);
    expect(notifications, 0);
  });

  test('reentrant session commands roll back the entire composite edit', () {
    final session = _session();
    session.mutate((book) => book.updateMetadata(title: 'First edit'));
    session.undo();
    final originalState = session.stateId;
    var notifications = 0;
    session.addListener(() => notifications++);
    for (final command in <void Function()>[
      () => session.mutate((book) => book.addChapter(title: 'Nested edit')),
      session.undo,
      session.redo,
      session.exportBytes,
      session.dispose,
    ]) {
      expect(
        () => session.mutate((book) {
          book.updateMetadata(title: 'Uncommitted edit');
          command();
        }),
        throwsStateError,
      );
      expect(session.document.title, 'Original title');
      expect(session.document.chapters, hasLength(1));
      expect(session.stateId, originalState);
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isFalse);
      expect(session.canRedo, isTrue);
    }
    expect(notifications, 0);
    session.redo();
    expect(session.document.title, 'First edit');
  });

  test(
    'async mutation callbacks cannot commit partial or delayed edits',
    () async {
      final session = _session();
      final resume = Completer<void>();
      expect(
        () => session.mutate((book) async {
          book.updateMetadata(title: 'Premature edit');
          await resume.future;
          book.updateMetadata(title: 'Delayed edit');
          throw StateError('The rejected async operation failed');
        }),
        throwsArgumentError,
      );
      expect(session.document.title, 'Original title');
      expect(session.isDirty, isFalse);
      expect(session.canUndo, isFalse);
      resume.complete();
      await Future<void>.delayed(Duration.zero);
      expect(session.document.title, 'Original title');
      expect(session.isDirty, isFalse);
      session.mutate((book) => book.updateMetadata(title: 'Synchronous edit'));
      expect(session.isDirty, isTrue);
    },
  );

  test(
    'source validation prevents a writer from receiving broken XHTML',
    () async {
      final session = _session();
      session.mutate(
        (book) => book.updateText(book.chapters.first.path, '<html>'),
      );
      var called = false;
      await expectLater(
        session.save((_) async {
          called = true;
          return EbookSaveOutcome.savedOriginal;
        }),
        throwsA(isA<EpubException>()),
      );
      expect(called, isFalse);
      expect(session.isSaving, isFalse);
      expect(session.isDirty, isTrue);
      session.undo();
      expect(session.isDirty, isFalse);
      expect(
        session.document.validate().where((issue) => issue.isError),
        isEmpty,
      );
    },
  );

  test('bounded history retains the most recent snapshots', () {
    final session = _session(maxHistoryEntries: 2);
    for (var i = 1; i <= 3; i++) {
      session.mutate((book) => book.updateMetadata(title: 'Revision $i'));
    }
    session.undo();
    expect(session.document.title, 'Revision 2');
    session.undo();
    expect(session.document.title, 'Revision 1');
    expect(session.canUndo, isFalse);
    session.redo();
    expect(session.document.title, 'Revision 2');
  });

  test('history limits reject negatives and allow explicit zero retention', () {
    expect(
      () => EbookEditSession(_openedBook(), maxHistoryEntries: -1),
      throwsRangeError,
    );
    expect(
      () => EbookEditSession(_openedBook(), maxHistoryBytes: -1),
      throwsRangeError,
    );
    final session = _session(maxHistoryEntries: 0);
    session.mutate((book) => book.updateMetadata(title: 'No undo allocation'));
    expect(session.canUndo, isFalse);
    expect(session.isDirty, isTrue);
  });

  test(
    'completion after disposal is safe and new mutations are rejected',
    () async {
      final session = EbookEditSession(_openedBook());
      session.mutate((book) => book.updateMetadata(title: 'Closing'));
      final upload = Completer<EbookSaveOutcome>();
      final saving = session.save((_) => upload.future);
      session.dispose();
      upload.complete(EbookSaveOutcome.savedOriginal);
      await expectLater(saving, completion(EbookSaveOutcome.savedOriginal));
      expect(() => session.mutate((_) {}), throwsStateError);
      expect(session.undo, throwsStateError);
      expect(session.exportBytes, throwsStateError);
    },
  );
}
