import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_content_strategy.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/verified_s3_fixture.dart';

const _block = 4 * 1024 * 1024;
const _tail = 64 * 1024;

Uint8List _source([int length = 2 * _tail]) => Uint8List.fromList(
  List.generate(length, (i) => (i * 7 + i ~/ _tail) % 251),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String cacheDirectory;
  late File local;
  late LocalOperationBackend backend;
  late VerifiedS3Fixture server;
  late S3ClientAdapter adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('s3-verified-contents-');
    cacheDirectory = p.join(directory.path, 'maps');
    local = File(p.join(directory.path, 'image.bin'));
    backend = LocalOperationBackend(LocalFileService(), isCurrent: () => true);
    server = VerifiedS3Fixture(_source());
    adapter = await verifiedS3Adapter(cacheDirectory: cacheDirectory);
  });
  tearDown(() async => directory.delete(recursive: true));

  FileItem reviewedSource([S3ClientAdapter? source]) => FileItem(
    name: 'image.bin',
    path: '/image.bin',
    isFolder: false,
    size: server.bytes.length,
    storageId: storageReferenceForClient(source ?? adapter).id,
    metadata: {'etag': server.version},
  );

  String cachePath([S3ClientAdapter? source]) =>
      DeltaSyncService().blockMapCachePath(
        cacheDirectory,
        'image.bin',
        's3',
        storageId: storageReferenceForClient(source ?? adapter).id,
      );

  Future<void> inServer(Future<void> Function() action) =>
      http.runWithClient(action, server.client);

  Future<void> expectInstalled(List<int> expected) async {
    expect(await local.readAsBytes(), expected);
    expect(await local.length(), expected.length);
    expect(
      directory
          .listSync(recursive: true)
          .where(
            (entry) => p.basename(entry.path).startsWith('.crisp-transfer-'),
          ),
      isEmpty,
    );
  }

  Future<int> copy({
    S3ClientAdapter? source,
    FileItem? reviewed,
    FileOperationControl? control,
    Future<void> Function()? beforeCommit,
    Future<void> Function()? afterAcknowledgement,
    TransferBandwidthContext? consumeContext,
  }) async {
    final currentSource = source ?? adapter;
    final currentControl = control ?? FileOperationControl();
    final existing = await backend.stat(local.path);
    return currentSource.withVerifiedBlockContents<int>(
      sourceFile: reviewed ?? reviewedSource(currentSource),
      destination: backend,
      destinationPath: local.path,
      existingDestination: existing,
      control: currentControl,
      consume: (contents) {
        Future<int> publish() async {
          var logicalBytes = 0;
          final logicalStream = contents.openRead().map((bytes) {
            logicalBytes += bytes.length;
            return bytes;
          });
          await backend.writePreparedFile(
            local.path,
            logicalStream,
            contents.length,
            replace: existing != null,
            verifyStaged: contents.verifyStaged,
            checkpoint: (state) async {
              if (state['phase'] == 'committed') {
                await afterAcknowledgement?.call();
                return;
              }
              if (state['phase'] == 'committing') {
                await beforeCommit?.call();
                await currentControl.checkpoint();
                await contents.revalidateBeforePublication();
                return;
              }
              await currentControl.checkpoint();
            },
          );
          await contents.committed();
          return logicalBytes;
        }

        return consumeContext == null ? publish() : consumeContext.run(publish);
      },
    );
  }

  test(
    'native capability does not activate the legacy global toggle',
    () async {
      expect(adapter.deltaSyncEnabled, isFalse);
      expect(adapter.supportsVerifiedBlockContentsTo(backend), isTrue);
      expect(
        adapter.supportsVerifiedBlockContentsTo(
          CloudOperationBackend(adapter, isCurrent: () => true),
        ),
        isFalse,
      );
      adapter.encryption = S3Encryption.sseC;
      expect(adapter.supportsVerifiedBlockContentsTo(backend), isFalse);
      await inServer(() async {
        await expectLater(copy(), throwsUnsupportedError);
        expect(server.heads, 0);
        expect(server.ranges, isEmpty);
        expect(await local.exists(), isFalse);
      });
    },
  );

  test(
    'first copy transfers each source byte once and seeds after publication',
    () => inServer(() async {
      server.bytes = _source(_block + _tail);
      var cacheExistedAtCommit = true;
      expect(
        await copy(
          beforeCommit: () async {
            cacheExistedAtCommit = await File(cachePath()).exists();
          },
        ),
        server.bytes.length,
      );
      expect(cacheExistedAtCommit, isFalse);
      expect(server.fullReads, 0);
      expect(server.ranges, ['bytes=0-4194303', 'bytes=4194304-4259839']);
      expect(server.validators, everyElement(server.version));
      expect(server.requestedBytes, server.bytes.length);
      await expectInstalled(server.bytes);
      final map = await DeltaSyncService().loadBlockMap(cachePath());
      expect(map, isNotNull);
      expect(map!.identity!.version, server.version);
      expect(map.identity!.storageId, storageReferenceForClient(adapter).id);
      expect(map.totalSize, server.bytes.length);
      expect(map.signatures, hasLength(2));
      expect(adapter.deltaSyncEnabled, isFalse);
    }),
  );

  test(
    'warm copy reuses proven blocks while logical progress stays complete',
    () => inServer(() async {
      server.bytes = _source(_block + _tail);
      await copy();
      final changed = Uint8List.fromList(server.bytes)..[_block] ^= 255;
      await local.writeAsBytes(changed);
      server.resetRequests();
      final allocator = TransferBandwidthAllocator();
      final context = allocator.openContext('verified-s3-reuse');
      try {
        expect(await context.run(copy), server.bytes.length);
        expect(server.ranges, ['bytes=4194304-4259839']);
        expect(server.requestedBytes, _tail);
        expect(allocator.snapshot.downloadBytes, _tail);
        expect(allocator.snapshot.uploadBytes, 0);
        await expectInstalled(server.bytes);
      } finally {
        context.close();
        allocator.dispose();
      }
    }),
  );

  test(
    'a new adapter reads the complete version despite a persisted map',
    () => inServer(() async {
      await copy();
      final freshAdapter = await verifiedS3Adapter(
        cacheDirectory: cacheDirectory,
      );
      server.resetRequests();
      expect(await copy(source: freshAdapter), server.bytes.length);
      expect(server.requestedBytes, server.bytes.length);
      expect(server.ranges, ['bytes=0-131071']);
      server.resetRequests();
      expect(await copy(source: freshAdapter), server.bytes.length);
      expect(server.ranges, isEmpty);
      await expectInstalled(server.bytes);
    }),
  );

  test(
    'a freshly reviewed revision uses one complete transfer and replaces cache',
    () => inServer(() async {
      await copy();
      server.bytes = _source(_tail)..[0] ^= 255;
      server.version = '"revision-2"';
      server.resetRequests();
      expect(await copy(), _tail);
      expect(server.requestedBytes, _tail);
      expect(server.ranges, ['bytes=0-65535']);
      expect(server.validators, [server.version]);
      await expectInstalled(server.bytes);
      final map = await DeltaSyncService().loadBlockMap(cachePath());
      expect(map!.identity!.version, server.version);
      expect(map.totalSize, _tail);
    }),
  );

  for (final mismatch in ['version', 'length']) {
    test(
      'reviewed $mismatch mismatch rejects before reading data or consuming',
      () => inServer(() async {
        final original = _source(31);
        await local.writeAsBytes(original);
        final reviewed = reviewedSource();
        final stale = mismatch == 'version'
            ? reviewed.copyWith(metadata: {'etag': '"old-revision"'})
            : reviewed.copyWith(size: server.bytes.length + 1);
        var consumed = false;
        await expectLater(
          adapter.withVerifiedBlockContents<void>(
            sourceFile: stale,
            destination: backend,
            destinationPath: local.path,
            existingDestination: await backend.stat(local.path),
            control: FileOperationControl(),
            consume: (_) async => consumed = true,
          ),
          throwsStateError,
        );
        expect(consumed, isFalse);
        expect(server.ranges, isEmpty);
        expect(server.fullReads, 0);
        await expectInstalled(original);
      }),
    );
  }

  for (final path in [
    '/folder/../image.bin',
    '/image%2Ebin',
    '//image.bin',
    'image.bin',
  ]) {
    test(
      'source path alias $path rejects before HEAD',
      () => inServer(() async {
        await expectLater(
          copy(reviewed: reviewedSource().copyWith(path: path)),
          throwsArgumentError,
        );
        expect(server.heads, 0);
        expect(server.ranges, isEmpty);
        expect(await local.exists(), isFalse);
      }),
    );
  }

  test(
    'destination path alias rejects before HEAD',
    () => inServer(() async {
      await expectLater(
        adapter.withVerifiedBlockContents<void>(
          sourceFile: reviewedSource(),
          destination: backend,
          destinationPath: '${directory.path}/nested/../image.bin',
          existingDestination: null,
          control: FileOperationControl(),
          consume: (_) async => fail('Alias must not reach the writer.'),
        ),
        throwsArgumentError,
      );
      expect(server.heads, 0);
      expect(server.ranges, isEmpty);
    }),
  );

  test(
    'well-formed cache tampering cannot authorize local block reuse',
    () => inServer(() async {
      await copy();
      final wrong = Uint8List.fromList(server.bytes)..[0] ^= 255;
      await local.writeAsBytes(wrong);
      final service = DeltaSyncService();
      final map = (await service.loadBlockMap(cachePath()))!;
      final forged = BlockMap(
        filePath: map.filePath,
        totalSize: map.totalSize,
        blockSize: map.blockSize,
        blockCount: map.blockCount,
        signatures: [
          BlockSignature(
            blockIndex: 0,
            offset: 0,
            size: wrong.length,
            weakHash: service.adler32(wrong),
            strongHash: service.sha256Hex(wrong),
          ),
        ],
        createdAt: map.createdAt,
        identity: map.identity,
      );
      await service.saveBlockMap(forged, cachePath());
      server.resetRequests();
      expect(await copy(), server.bytes.length);
      expect(server.requestedBytes, server.bytes.length);
      expect(server.ranges, ['bytes=0-131071']);
      await expectInstalled(server.bytes);
    }),
  );

  test(
    'failed publication does not issue a first-copy cache receipt',
    () => inServer(() async {
      final original = _source(23);
      await local.writeAsBytes(original);
      await expectLater(
        copy(beforeCommit: () async => throw StateError('Journal unavailable')),
        throwsStateError,
      );
      await expectInstalled(original);
      expect(await File(cachePath()).exists(), isFalse);
      server.resetRequests();
      await copy();
      expect(server.requestedBytes, server.bytes.length);
      await expectInstalled(server.bytes);
    }),
  );

  test(
    'short first-copy ranges fail without changing original or seeding',
    () => inServer(() async {
      final original = _source(17);
      await local.writeAsBytes(original);
      server.badResponse = 'short';
      await expectLater(copy(), throwsStateError);
      await expectInstalled(original);
      expect(await File(cachePath()).exists(), isFalse);
    }),
  );

  test(
    'changed source after range reads fails final proof without seeding',
    () => inServer(() async {
      final original = _source(17);
      await local.writeAsBytes(original);
      server.afterRange = () async => server.version = '"changed-after-read"';
      await expectLater(copy(), throwsStateError);
      await expectInstalled(original);
      expect(await File(cachePath()).exists(), isFalse);
    }),
  );

  test(
    'cache write failure after acknowledgement remains a successful copy',
    () => inServer(() async {
      final blocker = File(p.join(directory.path, 'not-a-cache-directory'));
      await blocker.writeAsString('Keep this file.');
      final uncached = await verifiedS3Adapter(cacheDirectory: blocker.path);
      expect(await copy(source: uncached), server.bytes.length);
      expect(await blocker.readAsString(), 'Keep this file.');
      await expectInstalled(server.bytes);
      server.resetRequests();
      await copy(source: uncached);
      expect(server.requestedBytes, server.bytes.length);
    }),
  );

  test(
    'transport accounting stays bound to the original consumer scope',
    () => inServer(() async {
      final originalAllocator = TransferBandwidthAllocator();
      final laterAllocator = TransferBandwidthAllocator();
      final original = originalAllocator.openContext('original-copy');
      final later = laterAllocator.openContext('later-consumer');
      try {
        expect(
          await original.run(() => copy(consumeContext: later)),
          server.bytes.length,
        );
        expect(originalAllocator.snapshot.downloadBytes, server.bytes.length);
        expect(laterAllocator.snapshot.downloadBytes, 0);
        expect(originalAllocator.snapshot.uploadBytes, 0);
        expect(laterAllocator.snapshot.uploadBytes, 0);
      } finally {
        original.close();
        later.close();
        originalAllocator.dispose();
        laterAllocator.dispose();
      }
    }),
  );

  test(
    'pause inside an admitted range prevents publication until resumed',
    () => inServer(() async {
      final control = FileOperationControl();
      final paused = Completer<void>();
      server.afterRange = () async {
        control.pause();
        paused.complete();
      };
      var completed = false;
      final pending = copy(control: control).then((value) {
        completed = true;
        return value;
      });
      await paused.future;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(await local.exists(), isFalse);
      control.resume();
      expect(await pending, server.bytes.length);
      await expectInstalled(server.bytes);
    }),
  );

  test(
    'cancellation aborts a pending HEAD without entering the writer',
    () => inServer(() async {
      final control = FileOperationControl();
      final entered = Completer<void>();
      final release = Completer<void>();
      server.beforeHead = () async {
        entered.complete();
        await release.future;
      };
      final pending = copy(control: control);
      await entered.future;
      control.cancel();
      try {
        await expectLater(
          pending.timeout(const Duration(seconds: 2)),
          throwsA(isA<FileOperationCancelled>()),
        );
      } finally {
        release.complete();
      }
      expect(server.ranges, isEmpty);
      expect(await local.exists(), isFalse);
      expect(await File(cachePath()).exists(), isFalse);
    }),
  );

  test(
    'cancellation aborts a pending range body and keeps the original',
    () => inServer(() async {
      final original = _source(17);
      await local.writeAsBytes(original);
      final control = FileOperationControl();
      final listening = Completer<void>();
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onListen: () => listening.complete(),
        onCancel: () => cancelled.complete(),
      );
      server.responseBody = (_) => body.stream;
      final pending = copy(control: control);
      await listening.future;
      control.cancel();
      await expectLater(
        pending.timeout(const Duration(seconds: 2)),
        throwsA(isA<FileOperationCancelled>()),
      );
      await cancelled.future.timeout(const Duration(seconds: 2));
      await body.close();
      await expectInstalled(original);
      expect(await File(cachePath()).exists(), isFalse);
    }),
  );

  test(
    'transport errors racing cancellation keep the cancelled classification',
    () => inServer(() async {
      final control = FileOperationControl();
      server.beforeHead = () async {
        control.cancel();
        throw http.ClientException('The request was aborted by its control.');
      };
      await expectLater(
        copy(control: control),
        throwsA(isA<FileOperationCancelled>()),
      );
      expect(server.ranges, isEmpty);
      expect(await local.exists(), isFalse);
    }),
  );

  test(
    'owned source chunks remain correct when the transport reuses its buffer',
    () => inServer(() async {
      server.responseBody = (bytes) async* {
        final reused = Uint8List(_tail);
        for (var offset = 0; offset < bytes.length; offset += _tail) {
          reused.setRange(0, _tail, bytes, offset);
          yield reused;
        }
        reused.fillRange(0, reused.length, 0);
      };
      expect(await copy(), server.bytes.length);
      await expectInstalled(server.bytes);
      server.resetRequests();
      expect(await copy(), server.bytes.length);
      expect(server.ranges, isEmpty);
    }),
  );

  test(
    'acknowledged copy stays successful after late cancellation',
    () => inServer(() async {
      final control = FileOperationControl();
      expect(
        await copy(
          control: control,
          afterAcknowledgement: () async => control.cancel(),
        ),
        server.bytes.length,
      );
      await expectInstalled(server.bytes);
      expect(await File(cachePath()).exists(), isTrue);
    }),
  );

  test(
    'authentication transition after acknowledgement cannot resurrect a receipt',
    () => inServer(() async {
      expect(
        await copy(
          afterAcknowledgement: () async {
            expect(await adapter.restoreCredentials(), isTrue);
          },
        ),
        server.bytes.length,
      );
      await expectInstalled(server.bytes);
      expect(await File(cachePath()).exists(), isFalse);
      server.resetRequests();
      await copy();
      expect(server.requestedBytes, server.bytes.length);
    }),
  );

  test(
    'empty source still verifies and publishes the exact zero length',
    () => inServer(() async {
      await local.writeAsBytes(_source(17));
      server.bytes = Uint8List(0);
      expect(await copy(), 0);
      expect(server.ranges, isEmpty);
      expect(server.requestedBytes, 0);
      await expectInstalled(const []);
      final map = await DeltaSyncService().loadBlockMap(cachePath());
      expect(map!.totalSize, 0);
      expect(map.signatures, isEmpty);
    }),
  );

  test(
    'prepared capability cannot escape its scoped consumer',
    () => inServer(() async {
      PreparedFileContents? escaped;
      await adapter.withVerifiedBlockContents<void>(
        sourceFile: reviewedSource(),
        destination: backend,
        destinationPath: local.path,
        existingDestination: null,
        control: FileOperationControl(),
        consume: (contents) async => escaped = contents,
      );
      expect(() => escaped!.openRead(), throwsStateError);
      expect(server.ranges, isEmpty);
      expect(await File(cachePath()).exists(), isFalse);
    }),
  );
}
