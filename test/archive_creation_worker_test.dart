import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_creation_worker.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory sources;
  late Directory destination;
  late _ScopedFiles local;
  final workers = <ArchiveCreationWorker>[];
  final gates = <Completer<void>>[];

  Completer<void> gate() {
    final value = Completer<void>();
    gates.add(value);
    return value;
  }

  Future<T> checkpoint<T>(ArchiveCreationWorker worker, Future<T> event) =>
      Future.any([
        event,
        worker.result.then<T>(
          (_) => throw StateError(
            'The worker finished before the expected checkpoint.',
          ),
        ),
      ]);

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('archive-worker-');
    root = Directory(await temporary.resolveSymbolicLinks());
    sources = await Directory(p.join(root.path, 'sources')).create();
    destination = await Directory(p.join(root.path, 'output')).create();
    local = _ScopedFiles();
  });

  tearDown(() async {
    for (final value in gates) {
      if (!value.isCompleted) value.complete();
    }
    gates.clear();
    for (final worker in workers) {
      await worker.close();
    }
    workers.clear();
    expect(local.active, isEmpty);
    await root.delete(recursive: true);
  });

  Future<FileItem> file(String name, String contents) async {
    final created = await File(p.join(sources.path, name))
        .writeAsString(contents);
    final backend = LocalOperationBackend(
      DesktopFileService(),
      isCurrent: () => true,
    );
    return (await backend.stat(created.path))!;
  }

  Future<ArchiveCreationWorker> start(
    List<FileItem> files, {
    void Function(ArchiveCreationProgress)? onProgress,
    Future<void> Function(ArchiveCreationPrepared)? onPrepared,
    ArchiveCreationOptions options = const ArchiveCreationOptions(
      name: 'result.zip',
    ),
  }) async {
    final worker = await startArchiveCreationWorker(
      local: local,
      files: files,
      destinationDirectory: destination.path,
      options: options,
      onProgress: onProgress ?? (_) {},
      onPrepared: onPrepared ?? (_) async {},
    );
    workers.add(worker);
    return worker;
  }

  bool outputExists([String name = 'result.zip']) =>
      File(p.join(destination.path, name)).existsSync();

  test(
    'parent scopes and receipt acknowledgement cover native publication',
    () async {
      final selected = await file('snow-雪.txt', 'a worker archive');
      final prepared = Completer<ArchiveCreationPrepared>();
      final permit = gate();
      final parent = Isolate.current.controlPort;
      final phases = <ArchiveCreationPhase>[];
      final worker = await start(
        [selected],
        onProgress: (progress) {
          expect(Isolate.current.controlPort, parent);
          phases.add(progress.phase);
        },
        onPrepared: (receipt) async {
          expect(Isolate.current.controlPort, parent);
          prepared.complete(receipt);
          await permit.future;
        },
      );
      final receipt = await checkpoint(worker, prepared.future);
      expect(outputExists(), isFalse);
      expect(receipt.path, p.join(destination.path, 'result.zip'));
      expect(receipt.entryCount, 1);
      expect(receipt.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(local.active, {sources.path, selected.path!, destination.path});
      expect(local.released, isEmpty);
      permit.complete();
      final result = await worker.result;
      expect(local.active, isEmpty);
      expect(result.path, receipt.path);
      expect(result.bytes, receipt.bytes);
      final bytes = await File(result.path).readAsBytes();
      expect(sha256.convert(bytes).toString(), receipt.sha256);
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      expect(archive.single.name, 'snow-雪.txt');
      expect(
        String.fromCharCodes(archive.single.readBytes()!),
        'a worker archive',
      );
      expect(phases, contains(ArchiveCreationPhase.scanning));
      expect(phases, contains(ArchiveCreationPhase.saving));
      expect(worker.close(), same(worker.close()));
      await worker.close();
    },
  );

  test(
    'a folder grant owns all descendants without passing service objects',
    () async {
      await file('inside.txt', 'nested');
      await Directory(p.join(sources.path, 'empty')).create();
      final selected = FileItem(
        name: 'sources',
        path: sources.path,
        isFolder: true,
      );
      final worker = await start(
        [selected],
        onPrepared: (_) async {
          expect(local.active, {sources.path, destination.path});
        },
      );
      final result = await worker.result;
      final archive = ZipDecoder().decodeBytes(
        await File(result.path).readAsBytes(),
      );
      expect(
        archive.files.map((entry) => entry.name),
        containsAll(['sources/', 'sources/inside.txt', 'sources/empty/']),
      );
    },
  );

  test(
    'failed receipt persistence prevents publication and retains the cause',
    () async {
      final selected = await file('payload.txt', 'preserved');
      final failure = StateError('The receipt could not be persisted.');
      final worker = await start([
        selected,
      ], onPrepared: (_) async => throw failure);
      await expectLater(worker.result, throwsA(same(failure)));
      expect(outputExists(), isFalse);
      expect(await File(selected.path!).readAsString(), 'preserved');
      expect(await destination.list().toList(), isEmpty);
      expect(local.active, isEmpty);
    },
  );

  test('a failing progress callback cancels without publication', () async {
    final selected = await file('payload.txt', 'contents');
    final failure = StateError('Progress persistence failed.');
    var prepared = false;
    final worker = await start(
      [selected],
      onProgress: (_) => throw failure,
      onPrepared: (_) async => prepared = true,
    );
    await expectLater(worker.result, throwsA(same(failure)));
    expect(prepared, isFalse);
    expect(outputExists(), isFalse);
    expect(await destination.list().toList(), isEmpty);
  });

  test(
    'a UTC restored snapshot identifies the same native source instant',
    () async {
      final selected = await file('payload.txt', 'contents');
      final worker = await start([
        selected.copyWith(updatedAt: selected.updatedAt!.toUtc()),
      ]);
      expect((await worker.result).entryCount, 1);
      expect(outputExists(), isTrue);
    },
  );

  test('password protection survives the ephemeral isolate request', () async {
    const password = 'worker secret 🔐';
    final selected = await file('payload.txt', 'protected contents');
    final worker = await start(
      [selected],
      options: const ArchiveCreationOptions(
        name: 'result.zip',
        password: password,
      ),
    );
    final result = await worker.result;
    final bytes = await File(result.path).readAsBytes();
    final opened = await openViewerArchive(
      bytes,
      name: result.path,
      password: password,
    );
    final withoutPassword = await openViewerArchive(bytes, name: result.path);
    try {
      expect(opened.members.single.isEncrypted, isTrue);
      expect(
        String.fromCharCodes(await opened.readMember(opened.members.single)),
        'protected contents',
      );
      await expectLater(
        withoutPassword.readMember(withoutPassword.members.single),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
    } finally {
      await opened.close();
      await withoutPassword.close();
    }
  });

  test(
    'revoked access during progress cannot reach publication acknowledgement',
    () async {
      final selected = await file('payload.txt', 'contents');
      var prepared = false;
      final worker = await start(
        [selected],
        onProgress: (_) => local.granted = false,
        onPrepared: (_) async => prepared = true,
      );
      await expectLater(
        worker.result,
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.sourceUnavailable,
          ),
        ),
      );
      expect(prepared, isFalse);
      expect(outputExists(), isFalse);
      expect(local.active, isEmpty);
    },
  );

  test(
    'changing an access identity while persisting the receipt refuses commit',
    () async {
      final selected = await file('payload.txt', 'contents');
      final worker = await start(
        [selected],
        onPrepared: (_) async {
          local.identity = Object();
        },
      );
      await expectLater(
        worker.result,
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.sourceUnavailable,
          ),
        ),
      );
      expect(outputExists(), isFalse);
    },
  );

  test(
    'source contents are revalidated after parent receipt persistence',
    () async {
      final selected = await file('payload.txt', 'old bytes');
      final worker = await start(
        [selected],
        onPrepared: (_) async {
          await File(selected.path!).writeAsString('new bytes');
        },
      );
      await expectLater(
        worker.result,
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.sourceChanged,
          ),
        ),
      );
      expect(outputExists(), isFalse);
      expect(await File(selected.path!).readAsString(), 'new bytes');
    },
  );

  test(
    'pause holds the prepared worker and resume allows verified publication',
    () async {
      final selected = await file('payload.txt', 'contents');
      final prepared = Completer<void>();
      final permit = gate();
      late ArchiveCreationWorker worker;
      worker = await start(
        [selected],
        onPrepared: (_) async {
          worker.pause();
          worker.pause();
          prepared.complete();
          await permit.future;
        },
      );
      await checkpoint(worker, prepared.future);
      permit.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(outputExists(), isFalse);
      expect(local.active, isNotEmpty);
      worker.resume();
      worker.resume();
      await worker.result;
      expect(outputExists(), isTrue);
    },
  );

  test(
    'cancelling a paused worker resumes it to clean up before releasing grants',
    () async {
      final selected = await file('payload.txt', 'contents');
      final prepared = Completer<void>();
      final permit = gate();
      late ArchiveCreationWorker worker;
      worker = await start(
        [selected],
        onPrepared: (_) async {
          worker.pause();
          prepared.complete();
          await permit.future;
        },
      );
      await checkpoint(worker, prepared.future);
      worker.cancel();
      permit.complete();
      await expectLater(
        worker.result,
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.cancelled,
          ),
        ),
      );
      expect(outputExists(), isFalse);
      expect(await destination.list().toList(), isEmpty);
      expect(local.active, isEmpty);
    },
  );

  test('close requests orderly cancellation and is idempotent', () async {
    final selected = await file('payload.txt', 'contents');
    final prepared = Completer<void>();
    final permit = gate();
    final worker = await start(
      [selected],
      onPrepared: (_) async {
        prepared.complete();
        await permit.future;
      },
    );
    await checkpoint(worker, prepared.future);
    final closing = worker.close();
    expect(worker.close(), same(closing));
    permit.complete();
    await expectLater(
      worker.result,
      throwsA(
        isA<ArchiveCreationException>().having(
          (error) => error.code,
          'code',
          ArchiveCreationError.cancelled,
        ),
      ),
    );
    await closing;
    expect(outputExists(), isFalse);
    expect(local.active, isEmpty);
  });

  test('cancellation immediately after startup cannot publish', () async {
    final selected = await file('payload.txt', 'contents');
    var prepared = false;
    final worker = await start([
      selected,
    ], onPrepared: (_) async => prepared = true);
    worker.cancel();
    await expectLater(
      worker.result,
      throwsA(
        isA<ArchiveCreationException>().having(
          (error) => error.code,
          'code',
          ArchiveCreationError.cancelled,
        ),
      ),
    );
    expect(prepared, isFalse);
    expect(outputExists(), isFalse);
    expect(await destination.list().toList(), isEmpty);
  });

  test(
    'result waits until originating access scopes have fully closed',
    () async {
      final selected = await file('payload.txt', 'contents');
      final releasing = Completer<void>();
      final release = gate();
      local.beforeRelease = (path) async {
        if (path == destination.path) {
          releasing.complete();
          await release.future;
        }
      };
      final worker = await start([selected]);
      var finished = false;
      final result = worker.result.then((value) {
        finished = true;
        return value;
      });
      await checkpoint(worker, releasing.future);
      expect(outputExists(), isTrue);
      expect(finished, isFalse);
      worker.cancel(); // A commit already completed; this cannot erase success.
      release.complete();
      expect((await result).entryCount, 1);
      expect(local.active, isEmpty);
    },
  );

  test(
    'an existing destination remains unchanged after isolated failure',
    () async {
      final selected = await file('payload.txt', 'contents');
      final output = await File(p.join(destination.path, 'result.zip'))
          .writeAsString('original destination');
      final worker = await start([selected]);
      await expectLater(
        worker.result,
        throwsA(
          isA<ArchiveCreationException>().having(
            (error) => error.code,
            'code',
            ArchiveCreationError.destinationExists,
          ),
        ),
      );
      expect(await output.readAsString(), 'original destination');
    },
  );

  test(
    'grant cleanup failure cannot misreport a published output as failed',
    () async {
      final selected = await file('payload.txt', 'contents');
      local.beforeRelease = (path) async {
        if (path == destination.path) throw StateError('Scope cleanup failed.');
      };
      final worker = await start([selected]);
      expect((await worker.result).entryCount, 1);
      expect(outputExists(), isTrue);
      expect(local.active, isEmpty);
    },
  );

  test(
    'failure acquiring a later grant unwinds every acquired scope',
    () async {
      final selected = await file('payload.txt', 'contents');
      local.denyScope = destination.path;
      await expectLater(start([selected]), throwsA(isA<FileSystemException>()));
      expect(outputExists(), isFalse);
      expect(local.active, isEmpty);
      expect(local.released, containsAll([sources.path, selected.path!]));
    },
  );
}

/// The test service contains closures and live scope state on the parent only.
/// Passing it to the child would break that state rather than satisfy the test.
class _ScopedFiles extends DesktopFileService
    implements ScopedLocalFileOperations, LocalFileSourceIdentity {
  final Set<String> active = {};
  final List<String> released = [];
  Object identity = Object();
  bool granted = true;
  String? denyScope;
  Future<void> Function(String)? beforeRelease;

  @override
  Object? sourceIdentityForPath(String path) => identity;

  @override
  Future<bool> hasAccessToPath(String path) async => granted;

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    if (path == denyScope) throw FileSystemException('Access denied.', path);
    expect(active.add(path), isTrue);
    try {
      return await action();
    } finally {
      try {
        await beforeRelease?.call(path);
      } finally {
        expect(active.remove(path), isTrue);
        released.add(path);
      }
    }
  }
}
