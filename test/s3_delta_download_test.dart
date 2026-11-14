import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _block = 64 * 1024;

Future<S3ClientAdapter> _adapter({String account = 'test-access'}) async {
  final config = S3ConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'accessKey': account,
    'secretKey': 'fixture-secret',
    'endpoint': 'https://s3.amazonaws.com',
    'bucket': 'bucket',
    'region': 'us-east-1',
  });
  final adapter = S3ClientAdapter(config: config);
  expect(await adapter.restoreCredentials(), isTrue);
  adapter.deltaSyncEnabled = true;
  return adapter;
}

class _S3Fixture {
  _S3Fixture(this.bytes);
  Uint8List bytes;
  String version = '"revision-1"';
  String? badResponse;
  int heads = 0;
  final ranges = <String>[];
  final validators = <String?>[];
  Future<void> Function()? afterGet;
  void Function()? beforeHead;

  http.Client client() => MockClient((request) async {
    if (request.method == 'HEAD') {
      heads++;
      beforeHead?.call();
      return http.Response(
        '',
        200,
        headers: {'etag': version, 'content-length': '${bytes.length}'},
      );
    }
    expect(request.method, 'GET');
    final range = request.headers['range']!;
    ranges.add(range);
    validators.add(request.headers['if-match']);
    if (request.headers['if-match'] != version) {
      return http.Response('', 412);
    }
    final parts = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range)!;
    final start = int.parse(parts.group(1)!);
    final end = int.parse(parts.group(2)!);
    final body = bytes.sublist(start, end + 1).toList();
    var contentRange = 'bytes $start-$end/${bytes.length}';
    var responseVersion = version;
    var status = 206;
    switch (badResponse) {
      case 'ignored':
        status = 200;
      case 'start':
        contentRange = 'bytes ${start + 1}-$end/${bytes.length}';
      case 'end':
        contentRange = 'bytes $start-${end + 1}/${bytes.length}';
      case 'total':
        contentRange = 'bytes $start-$end/${bytes.length + 1}';
      case 'short':
        body.removeLast();
      case 'long':
        body.add(0);
      case 'digest':
        body[0] ^= 255;
      case 'version':
        responseVersion = '"another-version"';
    }
    await afterGet?.call();
    return http.Response.bytes(
      body,
      status,
      headers: {
        'content-range': contentRange,
        'content-length': '${body.length}',
        'etag': responseVersion,
        if (badResponse == 'encoding') 'content-encoding': 'gzip',
      },
    );
  });
}

Uint8List _source([int size = 2 * _block]) =>
    Uint8List.fromList(List.generate(size, (i) => (i * 7 + i ~/ _block) % 251));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File local;
  late _S3Fixture server;
  late S3ClientAdapter adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('s3-delta-test-');
    local = File(p.join(directory.path, 'local.img'));
    server = _S3Fixture(_source());
    adapter = await _adapter();
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<BlockMap> seed() => adapter.seedDeltaBlockMap(
    '/image.bin',
    cacheDir: directory.path,
    blockSize: _block,
  );

  Future<void> inServer(Future<void> Function() action) =>
      http.runWithClient(action, server.client);

  Future<void> expectOriginal(List<int> original) async {
    expect(await local.readAsBytes(), original);
    expect(await local.length(), original.length);
    expect(
      directory.listSync().where(
        (entry) => p.basename(entry.path).startsWith('.crisp-transfer-'),
      ),
      isEmpty,
    );
  }

  test(
    'seed reads each exact conditional range and records full identity',
    () => inServer(() async {
      final map = await seed();
      expect(map.identity!.storageId, storageReferenceForClient(adapter).id);
      expect(map.identity!.objectPath, 'image.bin');
      expect(map.identity!.version, server.version);
      expect(map.identity!.totalSize, server.bytes.length);
      expect(server.ranges, ['bytes=0-65535', 'bytes=65536-131071']);
      expect(server.validators, everyElement(server.version));
      expect(
        map.signatures.last.strongHash,
        DeltaSyncService().sha256Hex(server.bytes.sublist(_block)),
      );
      expect(server.heads, 2);
    }),
  );

  test(
    'download replaces only after complete exact reconstruction',
    () => inServer(() async {
      await seed();
      final before = Uint8List.fromList(server.bytes)..[0] ^= 255;
      await local.writeAsBytes(before);
      server.ranges.clear();
      final result = await adapter.deltaDownload(
        '/image.bin',
        local.path,
        cacheDir: directory.path,
      );
      expect(result!.changedBlocks, [0]);
      expect(server.ranges, ['bytes=0-65535']);
      await expectOriginal(server.bytes);
    }),
  );

  test(
    'changed non-null ETag declines stale cache before ranges or writes',
    () => inServer(() async {
      await seed();
      final before = _source()..[0] ^= 255;
      await local.writeAsBytes(before);
      server.version = '"revision-2"';
      server.ranges.clear();
      expect(
        await adapter.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
        ),
        isNull,
      );
      expect(server.ranges, isEmpty);
      await expectOriginal(before);
    }),
  );

  test(
    'same object path in another account cannot reuse a cached map',
    () => inServer(() async {
      await seed();
      final before = _source();
      await local.writeAsBytes(before);
      final other = await _adapter(account: 'other-access');
      server.ranges.clear();
      expect(
        await other.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
        ),
        isNull,
      );
      expect(server.ranges, isEmpty);
      await expectOriginal(before);
    }),
  );

  for (final size in [_block, 0]) {
    test(
      'shrink to $size bytes is applied even with no changed blocks',
      () => inServer(() async {
        final before = _source();
        await local.writeAsBytes(before);
        server.bytes = Uint8List.fromList(before.sublist(0, size));
        await seed();
        server.ranges.clear();
        final result = await adapter.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
        );
        expect(result!.changedBlocks, isEmpty);
        expect(result.sizeChanged, isTrue);
        expect(result.isIdentical, isFalse);
        expect(server.ranges, isEmpty);
        await expectOriginal(server.bytes);
      }),
    );
  }

  test(
    'an unbound legacy map cannot authorize skipped ranges',
    () => inServer(() async {
      await local.writeAsBytes(_source());
      final service = DeltaSyncService();
      final unbound = await service.computeBlockMap(
        local.path,
        blockSize: _block,
      );
      await service.saveBlockMap(
        unbound,
        service.blockMapCachePath(
          directory.path,
          'image.bin',
          's3',
          storageId: storageReferenceForClient(adapter).id,
        ),
      );
      expect(
        await adapter.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
        ),
        isNull,
      );
      expect(server.ranges, isEmpty);
      await expectOriginal(server.bytes);
    }),
  );

  for (final malformed in [
    'ignored',
    'start',
    'end',
    'total',
    'short',
    'long',
    'digest',
    'version',
    'encoding',
  ]) {
    test(
      '$malformed range failure preserves the whole original',
      () => inServer(() async {
        await seed();
        final before = _source()..[0] ^= 255;
        await local.writeAsBytes(before);
        server.badResponse = malformed;
        await expectLater(
          adapter.deltaDownload(
            '/image.bin',
            local.path,
            cacheDir: directory.path,
          ),
          throwsStateError,
        );
        await expectOriginal(before);
      }),
    );
  }

  test(
    'source replacement after a valid range fails before publication',
    () => inServer(() async {
      await seed();
      final before = _source()..[0] ^= 255;
      await local.writeAsBytes(before);
      server.afterGet = () async => server.version = '"replacement"';
      await expectLater(
        adapter.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
        ),
        throwsStateError,
      );
      await expectOriginal(before);
    }),
  );

  test(
    'cancel after one block preserves original and cleans stage',
    () => inServer(() async {
      await seed();
      final before = _source()..[0] ^= 255;
      await local.writeAsBytes(before);
      var cancelled = false;
      await expectLater(
        adapter.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
          isCancelled: () => cancelled,
          onProgress: (_, __, ___) => cancelled = true,
        ),
        throwsA(isA<DeltaSyncCancelled>()),
      );
      await expectOriginal(before);
    }),
  );

  test(
    'logout during a valid range invalidates the captured operation',
    () => inServer(() async {
      await seed();
      final before = _source()..[0] ^= 255;
      await local.writeAsBytes(before);
      server.afterGet = adapter.logout;
      await expectLater(
        adapter.deltaDownload(
          '/image.bin',
          local.path,
          cacheDir: directory.path,
        ),
        throwsStateError,
      );
      await expectOriginal(before);
    }),
  );

  test(
    'source changes during seeding leave no authorized cache',
    () => inServer(() async {
      server.afterGet = () async => server.version = '"replacement"';
      await expectLater(seed(), throwsStateError);
      expect(
        Directory(p.join(directory.path, 'block_maps')).existsSync(),
        isFalse,
      );
    }),
  );

  test(
    'SSE-C profile is unavailable before any remote range',
    () => inServer(() async {
      adapter.encryption = S3Encryption.sseC;
      await expectLater(seed(), throwsUnsupportedError);
      expect(server.heads, 0);
      expect(server.ranges, isEmpty);
    }),
  );

  test(
    'old full-upload delta path declines before reading files or network',
    () => inServer(() async {
      expect(
        await adapter.deltaUpload('/missing/source', '/image.bin'),
        isNull,
      );
      expect(server.heads, 0);
      expect(server.ranges, isEmpty);
    }),
  );
}
