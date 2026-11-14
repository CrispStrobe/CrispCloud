@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

const _blockSize = 64 * 1024;

class _InspectingBackend extends LocalOperationBackend {
  _InspectingBackend({this.beforeVerify, this.afterCommit})
    : super(LocalFileService(), isCurrent: () => true);

  final Future<void> Function(FileItem)? beforeVerify;
  final void Function()? afterCommit;

  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem staged)? verifyStaged,
    Future<void> Function(Map<String, dynamic> state)? checkpoint,
  }) => super.writePreparedFile(
    path,
    data,
    length,
    replace: replace,
    verifyStaged: (staged) async {
      await beforeVerify?.call(staged);
      await verifyStaged?.call(staged);
    },
    checkpoint: (state) async {
      if (state['phase'] == 'committed') afterCommit?.call();
      await checkpoint?.call(state);
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DeltaSyncService service;
  late LocalOperationBackend backend;
  var sequence = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crisp-delta-safety-');
    service = DeltaSyncService();
    backend = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    sequence = 0;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Uint8List bytes(int blocks, int value, {int extra = 0}) =>
      Uint8List.fromList(List.filled(blocks * _blockSize + extra, value));

  Future<File> file(List<int> data) async {
    final result = File(p.join(root.path, 'input-${sequence++}.bin'));
    await result.writeAsBytes(data, flush: true);
    return result;
  }

  Future<BlockMap> map(File input) =>
      service.computeBlockMap(input.path, blockSize: _blockSize);

  Future<BlockTransferPlan> downloadPlan(File source, File destination) async {
    final sourceMap = await map(source);
    final baseline = await map(destination);
    return service.createTransferPlan(
      service.compareBlockMaps(sourceMap, baseline),
      TransferDirection.download,
      sourceMap,
    );
  }

  Future<List<int>> readRange(
    File source,
    int _,
    int offset,
    int length,
  ) async => (await source.readAsBytes()).sublist(offset, offset + length);

  Future<void> noStages() async {
    expect(
      (await root.list().toList()).where(
        (entry) => p.basename(entry.path).startsWith('.crisp-transfer-'),
      ),
      isEmpty,
    );
  }

  Map<String, dynamic> copyJson(BlockMap value) =>
      jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>;

  group('validated maps and identities', () {
    test('identity matches exact storage, path, revision and length', () async {
      final original = await map(await file(bytes(1, 0x31)));
      const identity = BlockMapIdentity(
        storageId: 's3|account-a|bucket-a',
        objectPath: '/image.bin',
        version: '"version-a"',
        totalSize: _blockSize,
      );
      expect(original.matchesIdentity(identity), isFalse);
      final bound = original.withIdentity(identity);
      expect(bound.matchesIdentity(identity), isTrue);
      for (final alternate in [
        const BlockMapIdentity(
          storageId: 's3|account-b|bucket-a',
          objectPath: '/image.bin',
          version: '"version-a"',
          totalSize: _blockSize,
        ),
        const BlockMapIdentity(
          storageId: 's3|account-a|bucket-b',
          objectPath: '/image.bin',
          version: '"version-a"',
          totalSize: _blockSize,
        ),
        const BlockMapIdentity(
          storageId: 's3|account-a|bucket-a',
          objectPath: '/Image.bin',
          version: '"version-a"',
          totalSize: _blockSize,
        ),
        const BlockMapIdentity(
          storageId: 's3|account-a|bucket-a',
          objectPath: '/image.bin',
          version: '"version-b"',
          totalSize: _blockSize,
        ),
        const BlockMapIdentity(
          storageId: 's3|account-a|bucket-a',
          objectPath: '/image.bin',
          version: '"version-a"',
          totalSize: _blockSize + 1,
        ),
      ]) {
        expect(bound.matchesIdentity(alternate), isFalse);
      }
      expect(
        BlockMap.fromJson(bound.toJson()).matchesIdentity(identity),
        isTrue,
      );
    });

    test('identity length must match the map', () async {
      final original = await map(await file(bytes(1, 1)));
      expect(
        () => original.withIdentity(
          const BlockMapIdentity(
            storageId: 'account',
            objectPath: '/file',
            version: 'v1',
            totalSize: 0,
          ),
        ),
        throwsFormatException,
      );
    });

    test('legacy maps are validated but have no remote identity', () async {
      final original = await map(await file(bytes(1, 2)));
      final legacy = copyJson(original)..remove('schemaVersion');
      final parsed = BlockMap.fromJson(legacy);
      expect(parsed.identity, isNull);
      expect(parsed.signatures, original.signatures);
      legacy['identity'] = const BlockMapIdentity(
        storageId: 'account',
        objectPath: '/file',
        version: 'v1',
        totalSize: _blockSize,
      ).toJson();
      expect(() => BlockMap.fromJson(legacy), throwsFormatException);
    });

    test('unknown map and identity schema versions are refused', () async {
      final original = await map(await file(bytes(1, 2)));
      expect(
        () => BlockMap.fromJson(copyJson(original)..['schemaVersion'] = 99),
        throwsFormatException,
      );
      expect(
        () => BlockMapIdentity.fromJson({
          'schemaVersion': 99,
          'storageId': 'account',
          'objectPath': '/file',
          'version': 'v1',
          'totalSize': 0,
        }),
        throwsFormatException,
      );
    });

    test(
      'negative, excessive and contradictory map geometry is rejected',
      () async {
        final original = await map(await file(bytes(2, 3)));
        for (final mutation in <void Function(Map<String, dynamic>)>[
          (j) => j['totalSize'] = -1,
          (j) => j['totalSize'] = deltaMaxFileSize + 1,
          (j) => j['blockSize'] = 0,
          (j) => j['blockSize'] = 64 * 1024 * 1024 + 1,
          (j) => j['blockCount'] = 1,
          (j) => (j['signatures'] as List).removeLast(),
          (j) => j['filePath'] = '',
        ]) {
          final json = copyJson(original);
          mutation(json);
          expect(() => BlockMap.fromJson(json), throwsFormatException);
        }
      },
    );

    test(
      'duplicate, overlapping, wrong-sized or invalid signatures are rejected',
      () async {
        final original = await map(await file(bytes(2, 3)));
        for (final mutation in <void Function(Map<String, dynamic>)>[
          (j) => j['blockIndex'] = 0,
          (j) => j['offset'] = 0,
          (j) => j['size'] = _blockSize - 1,
          (j) => j['weakHash'] = -1,
          (j) => j['weakHash'] = 0x100000000,
          (j) => j['strongHash'] = 'abc',
          (j) => j['strongHash'] = List.filled(64, 'g').join(),
        ]) {
          final json = copyJson(original);
          mutation((json['signatures'] as List)[1] as Map<String, dynamic>);
          expect(() => BlockMap.fromJson(json), throwsFormatException);
        }
      },
    );

    test('different block geometries cannot be compared', () async {
      final input = await file(bytes(2, 5));
      final first = await map(input);
      final second = await service.computeBlockMap(
        input.path,
        blockSize: 2 * _blockSize,
      );
      expect(
        () => service.compareBlockMaps(first, second),
        throwsFormatException,
      );
    });

    test('runtime block-size guard runs before opening a file', () async {
      for (final size in [0, -1, _blockSize - 1, 64 * 1024 * 1024 + 1]) {
        await expectLater(
          service.computeBlockMap('/does-not-exist', blockSize: size),
          throwsFormatException,
        );
      }
    });

    test(
      'truncation during map construction cannot hash zero-filled tails',
      () async {
        final input = await file(bytes(2, 7));
        await expectLater(
          service.computeBlockMap(
            input.path,
            blockSize: _blockSize,
            onProgress: (done, _, _) {
              if (done == 1) input.writeAsBytesSync(bytes(1, 7), flush: true);
            },
          ),
          throwsStateError,
        );
      },
    );

    test('growth during map construction invalidates the result', () async {
      final input = await file(bytes(2, 7));
      await expectLater(
        service.computeBlockMap(
          input.path,
          blockSize: _blockSize,
          onProgress: (done, _, _) {
            if (done == 1) {
              input.writeAsBytesSync([1], mode: FileMode.append, flush: true);
            }
          },
        ),
        throwsStateError,
      );
    });

    test('map construction observes cancellation', () async {
      final input = await file(bytes(2, 7));
      var cancelled = false;
      await expectLater(
        service.computeBlockMap(
          input.path,
          blockSize: _blockSize,
          onProgress: (_, _, _) => cancelled = true,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<DeltaSyncCancelled>()),
      );
    });
  });

  group('bounded cache', () {
    test(
      'identity survives save/load and accounts get different cache paths',
      () async {
        final original = (await map(await file(bytes(1, 9)))).withIdentity(
          const BlockMapIdentity(
            storageId: 'account-a',
            objectPath: '/file',
            version: 'v1',
            totalSize: _blockSize,
          ),
        );
        final first = service.blockMapCachePath(
          root.path,
          '/file',
          's3',
          storageId: 'account-a',
        );
        final second = service.blockMapCachePath(
          root.path,
          '/file',
          's3',
          storageId: 'account-b',
        );
        final unbound = service.blockMapCachePath(root.path, '/file', 's3');
        expect(first, isNot(second));
        expect(first, isNot(unbound));
        await service.saveBlockMap(original, first);
        expect(
          (await service.loadBlockMap(first))!
              .matchesIdentity(original.identity!),
          isTrue,
        );
        expect(await Directory(p.dirname(first)).list().length, 1);
      },
    );

    test('oversized cache is refused before parsing', () async {
      final target = File(p.join(root.path, 'too-large.json'));
      final writer = await target.open(mode: FileMode.write);
      await writer.truncate(deltaMaxCacheBytes + 1);
      await writer.close();
      expect(await service.loadBlockMap(target.path), isNull);
    });

    test('invalid replacement map preserves an existing cache', () async {
      final original = await map(await file(bytes(1, 0x33)));
      final path = p.join(root.path, 'map.json');
      await service.saveBlockMap(original, path);
      final before = await File(path).readAsBytes();
      final invalid = BlockMap(
        filePath: original.filePath,
        totalSize: 1,
        blockSize: _blockSize,
        blockCount: 0,
        signatures: const [],
        createdAt: DateTime.now(),
      );
      await expectLater(
        service.saveBlockMap(invalid, path),
        throwsFormatException,
      );
      expect(await File(path).readAsBytes(), before);
    });

    test(
      'symlink caches are neither read nor replaced',
      () async {
        final original = await map(await file(bytes(1, 0x33)));
        final target = await file(utf8.encode('untouched'));
        final link = Link(p.join(root.path, 'map.json'));
        await link.create(target.path);
        expect(await service.loadBlockMap(link.path), isNull);
        await expectLater(
          service.saveBlockMap(original, link.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await target.readAsString(), 'untouched');
      },
      skip: Platform.isWindows
          ? 'Windows symlink privileges are not assumed.'
          : false,
    );
  });

  group('staged download execution', () {
    test(
      'a deserialized local path cannot authorize source file access',
      () async {
        final original = bytes(1, 0x12);
        final destination = await file(original);
        final source = await file(bytes(1, 0x34));
        final parsedSource = BlockMap.fromJson((await map(source)).toJson());
        final plan = service.createTransferPlan(
          service.compareBlockMaps(parsedSource, await map(destination)),
          TransferDirection.download,
          parsedSource,
        );
        var callbacks = 0;
        await expectLater(
          service.applyDelta(
            plan,
            destination.path,
            destinationBackend: backend,
            checkpoint: () async {
              callbacks++;
            },
            remoteReadBlock: (_, _, _) async {
              callbacks++;
              return [];
            },
          ),
          throwsFormatException,
        );
        expect(callbacks, 0);
        expect(await destination.readAsBytes(), original);
        await noStages();
      },
    );

    for (final targetLength in [0, _blockSize, _blockSize + 17]) {
      test(
        'shrink to $targetLength bytes has exact final contents and length',
        () async {
          final destination = await file(bytes(3, 0x44));
          final source = await file(List.filled(targetLength, 0x44));
          final plan = await downloadPlan(source, destination);
          final comparison = service.compareBlockMaps(
            plan.sourceMap!,
            plan.baselineMap!,
          );
          expect(comparison.sizeChanged, isTrue);
          expect(comparison.isIdentical, isFalse);
          var reads = 0;
          await service.applyDelta(
            plan,
            destination.path,
            destinationBackend: backend,
            remoteReadBlock: (index, offset, size) async {
              reads++;
              return readRange(source, index, offset, size);
            },
          );
          expect(await destination.length(), targetLength);
          expect(await destination.readAsBytes(), await source.readAsBytes());
          expect(reads, targetLength % _blockSize == 0 ? 0 : 1);
          await noStages();
        },
      );
    }

    test('growth reconstructs old and new blocks in order', () async {
      final destination = await file(bytes(1, 0x55));
      final source = await file([...bytes(1, 0x55), ...bytes(1, 0x66), 0x77]);
      final plan = await downloadPlan(source, destination);
      await service.applyDelta(
        plan,
        destination.path,
        destinationBackend: backend,
        remoteReadBlock: (index, offset, size) =>
            readRange(source, index, offset, size),
      );
      expect(await destination.readAsBytes(), await source.readAsBytes());
      await noStages();
    });

    for (final response in ['short', 'long', 'wrong', 'invalid-byte']) {
      test(
        '$response range preserves the original and removes its candidate',
        () async {
          final original = bytes(2, 0x12);
          final destination = await file(original);
          final source = await file(bytes(2, 0x34));
          final plan = await downloadPlan(source, destination);
          await expectLater(
            service.applyDelta(
              plan,
              destination.path,
              destinationBackend: backend,
              remoteReadBlock: (index, offset, size) async {
                if (index == 0) return readRange(source, index, offset, size);
                if (response == 'short') return List.filled(size - 1, 0x34);
                if (response == 'long') return List.filled(size + 1, 0x34);
                if (response == 'invalid-byte') return List.filled(size, 0x134);
                return List.filled(size, 0x35);
              },
            ),
            throwsStateError,
          );
          expect(await destination.readAsBytes(), original);
          await noStages();
        },
      );
    }

    test(
      'a read failure after one accepted block preserves the original',
      () async {
        final original = bytes(2, 0x12);
        final destination = await file(original);
        final source = await file(bytes(2, 0x34));
        final plan = await downloadPlan(source, destination);
        await expectLater(
          service.applyDelta(
            plan,
            destination.path,
            destinationBackend: backend,
            remoteReadBlock: (index, offset, size) async {
              if (index == 1) throw const FileSystemException('read error');
              return readRange(source, index, offset, size);
            },
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await destination.readAsBytes(), original);
        await noStages();
      },
    );

    test('changed local skip bytes are rejected before publication', () async {
      final original = bytes(2, 0x12);
      final destination = await file(original);
      final source = await file([...bytes(1, 0x34), ...bytes(1, 0x12)]);
      final plan = await downloadPlan(source, destination);
      final outsideEdit = bytes(2, 0x56);
      await expectLater(
        service.applyDelta(
          plan,
          destination.path,
          destinationBackend: backend,
          remoteReadBlock: (index, offset, size) async {
            await destination.writeAsBytes(outsideEdit, flush: true);
            return readRange(source, index, offset, size);
          },
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), outsideEdit);
      await noStages();
    });

    test(
      'changed destination blocks cannot be overwritten after preparation',
      () async {
        final destination = await file(bytes(1, 0x12));
        final source = await file(bytes(1, 0x34));
        final plan = await downloadPlan(source, destination);
        final outsideEdit = bytes(1, 0x56);
        await expectLater(
          service.applyDelta(
            plan,
            destination.path,
            destinationBackend: backend,
            remoteReadBlock: (index, offset, size) async {
              await destination.writeAsBytes(outsideEdit, flush: true);
              return readRange(source, index, offset, size);
            },
          ),
          throwsStateError,
        );
        expect(await destination.readAsBytes(), outsideEdit);
        await noStages();
      },
    );

    test('complete staged contents are re-read before replacement', () async {
      final original = bytes(1, 0x12);
      final destination = await file(original);
      final source = await file(bytes(1, 0x34));
      final plan = await downloadPlan(source, destination);
      final corrupting = _InspectingBackend(
        beforeVerify: (staged) async {
          await File(staged.path!).writeAsBytes(bytes(1, 0x56), flush: true);
        },
      );
      await expectLater(
        service.applyDelta(
          plan,
          destination.path,
          destinationBackend: corrupting,
          remoteReadBlock: (index, offset, size) =>
              readRange(source, index, offset, size),
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    });

    test(
      'remote revision is revalidated before admission and publication',
      () async {
        final original = bytes(1, 0x12);
        final destination = await file(original);
        final source = await file(bytes(1, 0x34));
        final boundSource = (await map(source)).withIdentity(
          const BlockMapIdentity(
            storageId: 'account',
            objectPath: '/remote',
            version: 'v1',
            totalSize: _blockSize,
          ),
        );
        final plan = service.createTransferPlan(
          service.compareBlockMaps(boundSource, await map(destination)),
          TransferDirection.download,
          boundSource,
        );
        var revalidations = 0;
        await expectLater(
          service.applyDelta(
            plan,
            destination.path,
            destinationBackend: backend,
            revalidateSource: () async {
              revalidations++;
              if (revalidations == 2) {
                throw StateError('Source version changed.');
              }
            },
            remoteReadBlock: (index, offset, size) =>
                readRange(source, index, offset, size),
          ),
          throwsStateError,
        );
        expect(revalidations, 2);
        expect(await destination.readAsBytes(), original);
        await noStages();
      },
    );

    test(
      'remote identity without revalidation is refused before reading',
      () async {
        final destination = await file(bytes(1, 0x12));
        final source = await file(bytes(1, 0x34));
        final bound = (await map(source)).withIdentity(
          const BlockMapIdentity(
            storageId: 'account',
            objectPath: '/remote',
            version: 'v1',
            totalSize: _blockSize,
          ),
        );
        final plan = service.createTransferPlan(
          service.compareBlockMaps(bound, await map(destination)),
          TransferDirection.download,
          bound,
        );
        var reads = 0;
        await expectLater(
          service.applyDelta(
            plan,
            destination.path,
            destinationBackend: backend,
            remoteReadBlock: (_, _, _) async {
              reads++;
              return [];
            },
          ),
          throwsArgumentError,
        );
        expect(reads, 0);
        await noStages();
      },
    );

    test('cancellation after a range returns preserves the original', () async {
      final original = bytes(1, 0x12);
      final destination = await file(original);
      final source = await file(bytes(1, 0x34));
      final plan = await downloadPlan(source, destination);
      var cancelled = false;
      await expectLater(
        service.applyDelta(
          plan,
          destination.path,
          destinationBackend: backend,
          isCancelled: () => cancelled,
          remoteReadBlock: (index, offset, size) async {
            cancelled = true;
            return readRange(source, index, offset, size);
          },
        ),
        throwsA(isA<DeltaSyncCancelled>()),
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    });

    test('lost destination access preserves the original', () async {
      final original = bytes(1, 0x12);
      final destination = await file(original);
      final source = await file(bytes(1, 0x34));
      final plan = await downloadPlan(source, destination);
      var current = true;
      final captured = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => current,
      );
      await expectLater(
        service.applyDelta(
          plan,
          destination.path,
          destinationBackend: captured,
          remoteReadBlock: (index, offset, size) async {
            current = false;
            return readRange(source, index, offset, size);
          },
        ),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), original);
      await noStages();
    });

    test('cancellation after acknowledged commit remains successful', () async {
      final destination = await file(bytes(1, 0x12));
      final source = await file(bytes(1, 0x34));
      final plan = await downloadPlan(source, destination);
      var cancelled = false;
      final captured = _InspectingBackend(afterCommit: () => cancelled = true);
      await service.applyDelta(
        plan,
        destination.path,
        destinationBackend: captured,
        isCancelled: () => cancelled,
        remoteReadBlock: (index, offset, size) =>
            readRange(source, index, offset, size),
      );
      expect(cancelled, isTrue);
      expect(await destination.readAsBytes(), await source.readAsBytes());
      await noStages();
    });

    test('an unbound manually constructed plan runs no callbacks', () async {
      const plan = BlockTransferPlan(
        filePath: '/remote',
        blockSize: _blockSize,
        changedBlockIndices: [0],
        totalSize: _blockSize,
        transferSize: _blockSize,
        operations: [
          BlockOperation(
            type: BlockOperationType.download,
            blockIndex: 0,
            offset: 0,
            size: _blockSize,
          ),
        ],
      );
      var calls = 0;
      await expectLater(
        service.applyDelta(
          plan,
          p.join(root.path, 'unchanged'),
          checkpoint: () async {
            calls++;
          },
          remoteReadBlock: (_, _, _) async {
            calls++;
            return [];
          },
        ),
        throwsFormatException,
      );
      expect(calls, 0);
      expect(await root.list().length, 0);
    });

    test(
      'mixed-direction and altered-digest plans fail before callbacks',
      () async {
        final destination = await file(bytes(1, 0x12));
        final source = await file(bytes(1, 0x34));
        final valid = await downloadPlan(source, destination);
        for (final badOperation in [
          BlockOperation(
            type: BlockOperationType.upload,
            blockIndex: 0,
            offset: 0,
            size: _blockSize,
            expectedSha256: valid.operations.first.expectedSha256,
          ),
          BlockOperation(
            type: BlockOperationType.download,
            blockIndex: 0,
            offset: 0,
            size: _blockSize,
            expectedSha256: List.filled(64, '0').join(),
          ),
        ]) {
          final invalid = BlockTransferPlan(
            filePath: valid.filePath,
            blockSize: valid.blockSize,
            changedBlockIndices: valid.changedBlockIndices,
            totalSize: valid.totalSize,
            transferSize: valid.transferSize,
            operations: [badOperation],
            direction: valid.direction,
            sourceMap: valid.sourceMap,
            baselineMap: valid.baselineMap,
          );
          var calls = 0;
          await expectLater(
            service.applyDelta(
              invalid,
              destination.path,
              destinationBackend: backend,
              remoteReadBlock: (_, _, _) async {
                calls++;
                return [];
              },
            ),
            throwsFormatException,
          );
          expect(calls, 0);
        }
        await noStages();
      },
    );
  });
}
