import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/captured_file_target.dart';
import 'package:crisp_cloud/services/file_bytes_loader.dart';
import 'package:crisp_cloud/services/hex_edit_session.dart';

import 'support/hex_memory_backend.dart';

void main() {
  Future<HexEditSession> open(
    HexMemoryBackend backend, {
    bool memory = true,
  }) async {
    final session = await HexEditSession.open(
      backend: backend,
      file: (await backend.stat('/sample.bin'))!,
      inMemory: memory,
    );
    addTearDown(session.close);
    return session;
  }

  for (final memory in [true, false]) {
    test(
      '${memory ? 'memory' : 'disk'} source stays immutable after save and undo',
      () async {
        final backend = HexMemoryBackend([1, 2, 3, 4]);
        final session = await open(backend, memory: memory);
        session.document.overwrite(1, [9]);
        expect(session.isDirty, isTrue);
        expect((await session.save()).isSuccess, isTrue);
        expect(backend.bytes, [1, 9, 3, 4]);
        expect(session.isDirty, isFalse);
        session.document.undo();
        expect(await session.document.read(0, 4), [1, 2, 3, 4]);
        expect(session.isDirty, isTrue);
        expect((await session.save()).isSuccess, isTrue);
        expect(backend.bytes, [1, 2, 3, 4]);
        expect(session.isDirty, isFalse);
      },
    );
  }

  test('save failure keeps original and editable history', () async {
    final backend = HexMemoryBackend([1, 2, 3])..failWrite = true;
    final session = await open(backend);
    session.document.insert(2, [8, 9]);
    final failed = await session.save();
    expect(failed.isSuccess, isFalse);
    expect(session.isDirty, isTrue);
    expect(backend.bytes, [1, 2, 3]);
    expect(await session.document.read(0, 5), [1, 2, 8, 9, 3]);
    backend.failWrite = false;
    expect((await session.save()).isSuccess, isTrue);
    expect(backend.bytes, [1, 2, 8, 9, 3]);
    expect(session.isDirty, isFalse);
  });

  test(
    'detects same-size and same-timestamp source changes by content',
    () async {
      final backend = HexMemoryBackend([1, 2, 3]);
      final session = await open(backend);
      session.document.overwrite(0, [8]);
      backend.bytes = [4, 5, 6];
      final result = await session.save();
      expect(result.isSuccess, isFalse);
      expect(result.error, isA<FileTargetConflict>());
      expect(backend.writesStarted, 0);
      expect(backend.bytes, [4, 5, 6]);
      expect(session.isDirty, isTrue);
    },
  );

  test('checks original again after upload and before commit', () async {
    final backend = HexMemoryBackend([1, 2, 3]);
    final session = await open(backend);
    session.document.overwrite(0, [8]);
    backend.afterStage = () async {
      backend.bytes = [5, 6, 7];
    };
    final result = await session.save();
    expect(result.isSuccess, isFalse);
    expect(result.error, isA<FileTargetConflict>());
    expect(backend.commits, 0);
    expect(backend.bytes, [5, 6, 7]);
    expect(session.isDirty, isTrue);
  });

  test(
    'staged corruption is rejected without replacing the original',
    () async {
      final backend = HexMemoryBackend([1, 2, 3])..corruptStage = true;
      final session = await open(backend);
      session.document.delete(1, 1);
      final result = await session.save();
      expect(result.isSuccess, isFalse);
      expect(result.error, isA<FileTargetConflict>());
      expect(backend.commits, 0);
      expect(backend.bytes, [1, 2, 3]);
      expect(session.isDirty, isTrue);
    },
  );

  test(
    'edits during save remain dirty and the next save captures them',
    () async {
      final backend = HexMemoryBackend([1, 2, 3]);
      final session = await open(backend);
      final staged = Completer<void>();
      final resume = Completer<void>();
      backend.afterStage = () async {
        staged.complete();
        await resume.future;
      };
      session.document.overwrite(0, [8]);
      final saving = session.save();
      await staged.future;
      session.document.overwrite(1, [9]);
      session.documentChanged();
      resume.complete();
      expect((await saving).isSuccess, isTrue);
      expect(backend.bytes, [8, 2, 3]);
      expect(await session.document.read(0, 3), [8, 9, 3]);
      expect(session.isDirty, isTrue);
      backend.afterStage = null;
      expect((await session.save()).isSuccess, isTrue);
      expect(backend.bytes, [8, 9, 3]);
      expect(session.isDirty, isFalse);
    },
  );

  test('queued save waits and writes the latest document revision', () async {
    final backend = HexMemoryBackend([1, 2, 3]);
    final session = await open(backend);
    final staged = Completer<void>();
    final resume = Completer<void>();
    backend.afterStage = () async {
      backend.afterStage = null;
      staged.complete();
      await resume.future;
    };
    session.document.overwrite(0, [8]);
    final first = session.save();
    await staged.future;
    session.document.insert(3, [9]);
    final second = session.save();
    resume.complete();
    expect((await first).isSuccess, isTrue);
    expect((await second).isSuccess, isTrue);
    expect(backend.commits, 2);
    expect(backend.bytes, [8, 2, 3, 9]);
    expect(session.isDirty, isFalse);
  });

  test('disconnection during upload preserves edits and original', () async {
    final backend = HexMemoryBackend([1, 2, 3]);
    final session = await open(backend);
    session.document.overwrite(0, [8]);
    backend.afterStage = () async {
      backend.current = false;
    };
    final result = await session.save();
    expect(result.isSuccess, isFalse);
    expect(result.error, isA<FileTargetConflict>());
    expect(backend.commits, 0);
    expect(backend.bytes, [1, 2, 3]);
    expect(session.isDirty, isTrue);
  });

  for (final memory in [true, false]) {
    test(
      '${memory ? 'memory' : 'disk'} preparation pins the initial backend identity',
      () async {
        final backend = HexMemoryBackend([1, 2, 3]);
        backend.beforeRead = () => backend.identity = Object();
        await expectLater(
          HexEditSession.open(
            backend: backend,
            file: (await backend.stat('/sample.bin'))!,
            inMemory: memory,
          ),
          throwsA(isA<FileTargetConflict>()),
        );
        expect(backend.writesStarted, 0);
      },
    );
  }

  test(
    'disconnected or replaced backend identity cannot redirect a save',
    () async {
      final backend = HexMemoryBackend([1, 2, 3]);
      final session = await open(backend);
      session.document.overwrite(0, [8]);
      backend.identity = Object();
      expect(session.save, throwsA(isA<FileTargetConflict>()));
      expect(backend.writesStarted, 0);
      expect(session.isDirty, isTrue);
    },
  );

  test('unsafe backend fallback is rejected before it writes', () async {
    final backend = HexMemoryBackend([1, 2, 3])..verifiedStaging = false;
    final session = await open(backend);
    session.document.overwrite(0, [8]);
    expect((await session.save()).isSuccess, isFalse);
    expect(backend.writesStarted, 0);
    expect(backend.bytes, [1, 2, 3]);
  });

  test(
    'a post-commit metadata failure does not report a failed save',
    () async {
      final backend = HexMemoryBackend([1, 2, 3])..failStatAfterCommit = true;
      final session = await open(backend);
      session.document.overwrite(0, [8]);
      expect((await session.save()).isSuccess, isTrue);
      expect(backend.bytes, [8, 2, 3]);
      expect(session.isDirty, isFalse);
      expect(session.savedFile, isNull);
      backend.failStatAfterCommit = false;
      session.document.overwrite(1, [9]);
      expect((await session.save()).isSuccess, isTrue);
      expect(backend.bytes, [8, 9, 3]);
    },
  );

  test('browser refuses oversized input before streaming it', () async {
    final backend = HexMemoryBackend([1])
      ..reportedLength = hexBrowserEditingLimit + 1;
    await expectLater(
      HexEditSession.open(
        backend: backend,
        file: (await backend.stat('/sample.bin'))!,
        inMemory: true,
      ),
      throwsA(isA<FileBytesLoadException>()),
    );
    expect(backend.readCalls, 0);
  });

  test(
    'disk adapter supports reads larger than the viewer cache window',
    () async {
      final expected = List<int>.generate(320 * 1024, (i) => i % 251);
      final backend = HexMemoryBackend(expected);
      final session = await open(backend, memory: false);
      expect(await session.document.read(0, expected.length), expected);
      final snapshot = session.document.snapshot();
      await session.close();
      expect(await snapshot.read(65530, 20), expected.sublist(65530, 65550));
      await snapshot.close();
    },
  );
}
