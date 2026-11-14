@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_content_strategy.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _blockSize = 64 * 1024;

class _ScopedLocal extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  var active = 0;
  var denied = false;
  final paths = <String>[];

  @override
  Future<bool> hasAccessToPath(String path) async => !denied;

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    paths.add(path);
    if (denied) throw FileSystemException('Access denied.', path);
    active++;
    try {
      return await action();
    } finally {
      active--;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DeltaSyncService service;
  late LocalOperationBackend backend;
  var sequence = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crisp-prepared-delta-');
    service = DeltaSyncService();
    backend = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    sequence = 0;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List bytes(int count, int value) =>
      Uint8List(count)..fillRange(0, count, value);

  Future<File> file(List<int> data) async {
    final result = File(p.join(root.path, 'file-${sequence++}.bin'));
    await result.writeAsBytes(data, flush: true);
    return result;
  }

  BlockMapIdentity identity(int length, {String version = '"v1"'}) =>
      BlockMapIdentity(
        storageId: 's3|original-account|bucket',
        objectPath: '/remote.bin',
        version: version,
        totalSize: length,
      );

  BlockMap remoteMap(List<int> data, {BlockMapIdentity? bound}) {
    final signatures = <BlockSignature>[];
    for (var offset = 0; offset < data.length; offset += _blockSize) {
      final end = (offset + _blockSize).clamp(0, data.length);
      final block = data.sublist(offset, end);
      signatures.add(
        BlockSignature(
          blockIndex: signatures.length,
          offset: offset,
          size: block.length,
          weakHash: service.adler32(block),
          strongHash: service.sha256Hex(block),
        ),
      );
    }
    return BlockMap(
      filePath: '/remote.bin',
      totalSize: data.length,
      blockSize: _blockSize,
      blockCount: signatures.length,
      signatures: signatures,
      createdAt: DateTime.utc(2026, 11, 14),
      identity: bound ?? identity(data.length),
    );
  }

  Future<void> publish(
    PreparedFileContents contents,
    File destination, {
    bool replace = true,
    Future<void> Function(String stagedPath)? committing,
    void Function()? acknowledged,
  }) async {
    String? stagedPath;
    await backend.writeConfiguredFile(
      destination.path,
      contents.openRead(),
      contents.length,
      replace: replace,
      verifyStaged: contents.verifyStaged,
      checkpoint: (state) async {
        if (state['phase'] == 'staging') {
          stagedPath = state['stagedPath'] as String;
        }
        if (state['phase'] == 'committing') {
          // This await models the real service's durable journal + pause gate.
          await committing?.call(stagedPath!);
          await contents.revalidateBeforePublication();
        }
        if (state['phase'] == 'committed') acknowledged?.call();
      },
    );
    await contents.committed();
  }

  Future<T> full<T>(
    File destination,
    List<int> data, {
    required Future<T> Function(PreparedFileContents) consume,
    bool destinationExists = true,
    FileItem? existingDestination,
    BlockMap? baselineMap,
    BlockMap? completedMap,
    Stream<List<int>> Function()? openRead,
    void Function()? onMap,
    Future<void> Function()? revalidateSource,
    Future<void> Function()? checkpoint,
    bool Function()? isCancelled,
    Future<void> Function()? onCommitted,
  }) async {
    var eof = false;
    Stream<List<int>> input() async* {
      if (openRead != null) {
        yield* openRead();
      } else {
        for (var offset = 0; offset < data.length; offset += _blockSize) {
          yield data.sublist(
            offset,
            (offset + _blockSize).clamp(0, data.length),
          );
        }
      }
      eof = true;
    }

    return service.withPreparedVerifiedDownload(
      destination.path,
      destinationBackend: backend,
      sourceIdentity: identity(data.length),
      destinationExists: destinationExists,
      existingDestination: existingDestination,
      baselineMap: baselineMap,
      openRead: input,
      sourceMap: () {
        expect(
          eof,
          isTrue,
          reason: 'The map is not available before exact EOF.',
        );
        onMap?.call();
        return completedMap ?? remoteMap(data);
      },
      revalidateSource: revalidateSource ?? () async {},
      checkpoint: checkpoint,
      isCancelled: isCancelled,
      onCommitted: onCommitted,
      consume: consume,
    );
  }

  Future<BlockTransferPlan> deltaPlan(File source, File destination) async {
    final sourceMap = await service.computeBlockMap(
      source.path,
      blockSize: _blockSize,
    );
    final baseline = await service.computeBlockMap(
      destination.path,
      blockSize: _blockSize,
    );
    return service.createTransferPlan(
      service.compareBlockMaps(sourceMap, baseline),
      TransferDirection.download,
      sourceMap,
    );
  }

  Future<void> noStages() async {
    expect(
      (await root.list().toList()).where(
        (entry) => p.basename(entry.path).startsWith('.crisp-transfer-'),
      ),
      isEmpty,
    );
  }

  test('first-use full stream supplies its map only after exact EOF', () async {
    final destination = await file(bytes(_blockSize, 0x11));
    final desired = bytes(_blockSize + 17, 0x22);
    var maps = 0;
    var revisions = 0;
    var committed = 0;
    await full<void>(
      destination,
      desired,
      onMap: () => maps++,
      revalidateSource: () async {
        revisions++;
      },
      onCommitted: () async {
        committed++;
      },
      consume: (contents) => publish(contents, destination),
    );
    expect(await destination.readAsBytes(), desired);
    expect(maps, 1);
    expect(revisions, 3);
    expect(committed, 1);
    await noStages();
  });

  for (final length in [0, _blockSize + 3]) {
    test(
      'first-use creates an absent destination of exactly $length bytes',
      () async {
        final destination = File(p.join(root.path, 'new.bin'));
        final desired = bytes(length, 0x33);
        await full<void>(
          destination,
          desired,
          destinationExists: false,
          consume: (contents) => publish(contents, destination, replace: false),
        );
        expect(await destination.readAsBytes(), desired);
        expect(await destination.length(), length);
        await noStages();
      },
    );
  }

  test('a delayed durable checkpoint cannot hide a changed original', () async {
    final original = bytes(_blockSize, 0x11);
    final changed = bytes(_blockSize, 0x77);
    final destination = await file(original);
    final reached = Completer<void>();
    final release = Completer<void>();
    final attempt = full<void>(
      destination,
      bytes(_blockSize, 0x22),
      consume: (contents) => publish(
        contents,
        destination,
        committing: (_) async {
          reached.complete();
          await release.future;
        },
      ),
    );
    final rejected = expectLater(attempt, throwsStateError);
    await reached.future;
    await destination.writeAsBytes(changed, flush: true);
    release.complete();
    await rejected;
    expect(await destination.readAsBytes(), changed);
    await noStages();
  });

  test('candidate is re-read after the awaited committing callback', () async {
    final original = bytes(_blockSize, 0x11);
    final destination = await file(original);
    await expectLater(
      full<void>(
        destination,
        bytes(_blockSize, 0x22),
        consume: (contents) => publish(
          contents,
          destination,
          committing: (path) async {
            await File(path).writeAsBytes(bytes(_blockSize, 0x66), flush: true);
          },
        ),
      ),
      throwsStateError,
    );
    expect(await destination.readAsBytes(), original);
    await noStages();
  });

  test('remote revision is renewed after the durable checkpoint', () async {
    final original = bytes(_blockSize, 0x11);
    final destination = await file(original);
    var sourceChanged = false;
    await expectLater(
      full<void>(
        destination,
        bytes(_blockSize, 0x22),
        revalidateSource: () async {
          if (sourceChanged) throw StateError('Remote revision changed.');
        },
        consume: (contents) => publish(
          contents,
          destination,
          committing: (_) async {
            sourceChanged = true;
          },
        ),
      ),
      throwsStateError,
    );
    expect(await destination.readAsBytes(), original);
    await noStages();
  });

  test(
    'captured local source is renewed after the durable checkpoint',
    () async {
      final original = bytes(_blockSize, 0x11);
      final destination = await file(original);
      final source = await file(bytes(_blockSize, 0x22));
      final plan = await deltaPlan(source, destination);
      await expectLater(
        service.withPreparedDelta<void>(
          plan,
          destination.path,
          destinationBackend: backend,
          remoteReadBlock: (_, offset, size) async =>
              (await source.readAsBytes()).sublist(offset, offset + size),
          consume: (contents) => publish(
            contents,
            destination,
            committing: (_) async {
              await source.writeAsBytes(bytes(_blockSize, 0x66), flush: true);
            },
          ),
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    },
  );

  test('new destination appearance during checkpoint is retained', () async {
    final destination = File(p.join(root.path, 'new.bin'));
    final external = bytes(13, 0x77);
    await expectLater(
      full<void>(
        destination,
        bytes(_blockSize, 0x22),
        destinationExists: false,
        consume: (contents) => publish(
          contents,
          destination,
          replace: false,
          committing: (_) async {
            await destination.writeAsBytes(external, flush: true);
          },
        ),
      ),
      throwsStateError,
    );
    expect(await destination.readAsBytes(), external);
    await noStages();
  });

  test(
    'cancellation during durable checkpoint preserves the original',
    () async {
      final original = bytes(_blockSize, 0x11);
      final destination = await file(original);
      var cancelled = false;
      await expectLater(
        full<void>(
          destination,
          bytes(_blockSize, 0x22),
          isCancelled: () => cancelled,
          consume: (contents) => publish(
            contents,
            destination,
            committing: (_) async {
              cancelled = true;
            },
          ),
        ),
        throwsA(isA<DeltaSyncCancelled>()),
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    },
  );

  test('backend disconnect during checkpoint preserves the original', () async {
    final original = bytes(_blockSize, 0x11);
    final destination = await file(original);
    var current = true;
    backend = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => current,
    );
    await expectLater(
      full<void>(
        destination,
        bytes(_blockSize, 0x22),
        consume: (contents) => publish(
          contents,
          destination,
          committing: (_) async {
            current = false;
          },
        ),
      ),
      throwsStateError,
    );
    expect(await destination.readAsBytes(), original);
    await noStages();
  });

  test(
    'late cancellation and auxiliary cache error do not undo success',
    () async {
      final destination = await file(bytes(_blockSize, 0x11));
      final desired = bytes(_blockSize, 0x22);
      var cancelled = false;
      var attemptedCache = false;
      await full<void>(
        destination,
        desired,
        isCancelled: () => cancelled,
        onCommitted: () async {
          attemptedCache = true;
          throw const FileSystemException('Cache disk unavailable.');
        },
        consume: (contents) => publish(
          contents,
          destination,
          acknowledged: () {
            cancelled = true;
          },
        ),
      );
      expect(cancelled, isTrue);
      expect(attemptedCache, isTrue);
      expect(await destination.readAsBytes(), desired);
      await noStages();
    },
  );

  for (final difference in [-1, 1]) {
    test(
      'a full stream length difference of $difference rejects before map access',
      () async {
        final original = bytes(_blockSize, 0x11);
        final destination = await file(original);
        var maps = 0;
        await expectLater(
          full<void>(
            destination,
            bytes(_blockSize, 0x22),
            openRead: () => Stream.value(bytes(_blockSize + difference, 0x22)),
            onMap: () {
              maps++;
            },
            consume: (contents) => publish(contents, destination),
          ),
          throwsStateError,
        );
        expect(maps, 0);
        expect(await destination.readAsBytes(), original);
        await noStages();
      },
    );
  }

  test(
    'invalid stream byte values are not truncated into admissible bytes',
    () async {
      final original = bytes(_blockSize, 0x11);
      final destination = await file(original);
      await expectLater(
        full<void>(
          destination,
          bytes(_blockSize, 0x22),
          openRead: () => Stream.value(List.filled(_blockSize, 0x122)),
          consume: (contents) => publish(contents, destination),
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    },
  );

  for (final invalid in ['identity', 'hash']) {
    test('a completed map with the wrong $invalid never publishes', () async {
      final original = bytes(_blockSize, 0x11);
      final destination = await file(original);
      final desired = bytes(_blockSize, 0x22);
      final incorrect = invalid == 'identity'
          ? remoteMap(desired, bound: identity(desired.length, version: '"v2"'))
          : remoteMap(bytes(_blockSize, 0x33));
      await expectLater(
        full<void>(
          destination,
          desired,
          completedMap: incorrect,
          consume: (contents) => publish(contents, destination),
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    });
  }

  test('prepared stream is single-use and proof order is enforced', () async {
    final destination = await file(bytes(_blockSize, 0x11));
    await full<void>(
      destination,
      bytes(_blockSize, 0x22),
      consume: (contents) async {
        await expectLater(
          contents.revalidateBeforePublication(),
          throwsStateError,
        );
        await expectLater(contents.committed(), throwsStateError);
        final stream = contents.openRead();
        expect(contents.openRead, throwsStateError);
        await expectLater(
          contents.verifyStaged(
            FileItem(
              name: 'unwritten',
              path: destination.path,
              isFolder: false,
            ),
          ),
          throwsStateError,
        );
        await stream.drain<void>();
        await expectLater(
          contents.revalidateBeforePublication(),
          throwsStateError,
        );
      },
    );
    await noStages();
  });

  test('partial consumption never grants a complete-map proof', () async {
    final destination = await file(bytes(_blockSize, 0x11));
    var maps = 0;
    await full<void>(
      destination,
      bytes(_blockSize * 2, 0x22),
      onMap: () {
        maps++;
      },
      consume: (contents) async {
        await contents.openRead().take(1).drain<void>();
        await expectLater(
          contents.verifyStaged(
            FileItem(name: 'partial', path: destination.path, isFolder: false),
          ),
          throwsStateError,
        );
      },
    );
    expect(maps, 0);
    await noStages();
  });

  test(
    'prepared objects and deferred streams expire with their access scope',
    () async {
      final destination = await file(bytes(_blockSize, 0x11));
      late PreparedFileContents escaped;
      late Stream<List<int>> deferred;
      await full<void>(
        destination,
        bytes(_blockSize, 0x22),
        consume: (contents) async {
          escaped = contents;
          deferred = contents.openRead();
        },
      );
      expect(() => escaped.length, throwsStateError);
      expect(escaped.openRead, throwsStateError);
      await expectLater(deferred.drain<void>(), throwsStateError);
      await expectLater(
        escaped.revalidateBeforePublication(),
        throwsStateError,
      );
      await expectLater(escaped.committed(), throwsStateError);
      await noStages();
    },
  );

  test(
    'a deserialized supplied baseline cannot replace a fresh local scan',
    () async {
      final destination = await file(bytes(_blockSize, 0x11));
      final baseline = BlockMap.fromJson(
        (await service.computeBlockMap(
          destination.path,
          blockSize: _blockSize,
        )).toJson(),
      );
      var consumed = false;
      await expectLater(
        full<void>(
          destination,
          bytes(_blockSize, 0x22),
          baselineMap: baseline,
          consume: (_) async {
            consumed = true;
          },
        ),
        throwsFormatException,
      );
      expect(consumed, isFalse);
      await noStages();
    },
  );

  test(
    'the reviewed destination snapshot is checked before baseline capture',
    () async {
      final destination = await file(bytes(_blockSize, 0x11));
      final reviewed = await backend.stat(destination.path);
      final replacement = bytes(17, 0x77);
      await destination.writeAsBytes(replacement, flush: true);
      var consumed = false;
      await expectLater(
        full<void>(
          destination,
          bytes(_blockSize, 0x22),
          existingDestination: reviewed,
          consume: (_) async {
            consumed = true;
          },
        ),
        throwsStateError,
      );
      expect(consumed, isFalse);
      expect(await destination.readAsBytes(), replacement);
      await noStages();
    },
  );

  test(
    'captured local access is held through reads, verification and commit',
    () async {
      final destination = await file(bytes(_blockSize, 0x11));
      final access = _ScopedLocal();
      backend = LocalOperationBackend(access, isCurrent: () => true);
      var sourceChecks = 0;
      await full<void>(
        destination,
        bytes(_blockSize, 0x22),
        revalidateSource: () async {
          expect(access.active, greaterThan(0));
          sourceChecks++;
        },
        onMap: () {
          expect(access.active, greaterThan(0));
        },
        onCommitted: () async {
          expect(access.active, greaterThan(0));
        },
        consume: (contents) => publish(contents, destination),
      );
      expect(sourceChecks, 3);
      expect(access.active, 0);
      expect(access.paths.first, destination.path);
      await noStages();
    },
  );

  test('denied captured access never invokes source or consumer', () async {
    final destination = await file(bytes(_blockSize, 0x11));
    final access = _ScopedLocal()..denied = true;
    backend = LocalOperationBackend(access, isCurrent: () => true);
    var callbacks = 0;
    await expectLater(
      full<void>(
        destination,
        bytes(_blockSize, 0x22),
        revalidateSource: () async {
          callbacks++;
        },
        consume: (_) async {
          callbacks++;
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(callbacks, 0);
    expect(access.active, 0);
    await noStages();
  });
}
