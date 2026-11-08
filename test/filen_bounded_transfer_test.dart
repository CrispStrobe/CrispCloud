import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:filen_client/filen_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/filen_stream_transfer.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

const _chunkSize = 1024 * 1024;
const _master = 'test-only-master-key';
const _fileKey = '0123456789abcdefghijklmnopqrstuv';

void main() {
  late Directory directory;
  late FilenClient client;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('filen-stream-test-');
    requests = [];
    respond = (_) async => http.Response('{"status":true}', 200);
    client =
        FilenClient(
          config: ConfigService(configPath: directory.path),
          httpClient: MockClient((request) async {
            requests.add(request);
            expect(request.followRedirects, isFalse);
            return respond(request);
          }),
        )..setAuth({
          'apiKey': 'fixture-token',
          'masterKeys': _master,
          'baseFolderUUID': 'root-id',
          'email': 'fixture@example.test',
        });
  });

  tearDown(() async {
    client.api.client.close();
    await directory.delete(recursive: true);
  });

  Future<void> prepareDownload(
    List<int> plain, {
    String? hash,
    int? size,
    bool includeHash = true,
    int? reportedChunks,
    List<int>? chunkOrder,
  }) async {
    final metadata = await client.crypto.encryptMetadata002(
      jsonEncode({
        'name': 'source.bin',
        'size': size ?? plain.length,
        'key': _fileKey,
        if (includeHash) 'hash': hash ?? sha512.convert(plain).toString(),
      }),
      _master,
    );
    final chunks = <Uint8List>[];
    for (var offset = 0; offset < plain.length; offset += _chunkSize) {
      chunks.add(
        await client.crypto.encryptData(
          Uint8List.fromList(
            plain.sublist(offset, (offset + _chunkSize).clamp(0, plain.length)),
          ),
          Uint8List.fromList(utf8.encode(_fileKey)),
        ),
      );
    }
    respond = (request) async {
      if (request.url.path == '/v3/file') {
        expect(request.headers['authorization'], 'Bearer fixture-token');
        expect(jsonDecode(request.body), {'uuid': 'source-id'});
        return http.Response(
          jsonEncode({
            'status': true,
            'data': {
              'uuid': 'source-id',
              'metadata': metadata,
              'chunks': reportedChunks ?? chunks.length,
              'region': 'region',
              'bucket': 'bucket',
            },
          }),
          200,
        );
      }
      expect(request.url.host, 'egest.filen.io');
      expect(request.headers['authorization'], isNull);
      final index = int.parse(request.url.pathSegments.last);
      return http.Response.bytes(
        chunks[chunkOrder?[index] ?? index],
        200,
      );
    };
  }

  Stream<List<int>> download({void Function()? check}) => readFilenStream(
    client,
    'source-id',
    token: 'fixture-token',
    masterKeys: [_master],
    checkCurrent: check ?? () {},
  );

  FilenClientAdapter downloadAdapter() {
    client.cache.pathCache['source.bin'] = {
      'type': 'file',
      'uuid': 'source-id',
    };
    return FilenClientAdapter.withClient(
      client,
      config: FilenConfigService(
        configPath: directory.path,
        secureStorage: InMemorySecureStorage(),
      ),
    );
  }

  Future<void> upload(
    Stream<List<int>> source,
    int length, {
    void Function()? check,
  }) => writeFilenStream(
    client,
    source,
    length,
    'résumé %20.bin',
    'root-id',
    token: 'fixture-token',
    masterKeys: [_master],
    email: 'fixture@example.test',
    checkCurrent: check ?? () {},
  );

  test(
    'download yields verified chunks without requesting later chunks',
    () async {
      final plain = Uint8List.fromList(
        List.generate(_chunkSize + 7, (i) => i % 251),
      );
      await prepareDownload(plain);
      final iterator = StreamIterator(download());
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, plain.sublist(0, _chunkSize));
      expect(requests.length, 2);
      await iterator.cancel();
      expect(requests.length, 2);
    },
  );

  test(
    'download verifies final plaintext hash and exact total length',
    () async {
      await prepareDownload([1, 2, 3]);
      expect(await download().expand((chunk) => chunk).toList(), [1, 2, 3]);
      await prepareDownload([1, 2, 3], hash: 'wrong');
      await expectLater(download().drain<void>(), throwsStateError);
      await prepareDownload([1, 2, 3], size: 4);
      await expectLater(download().drain<void>(), throwsStateError);
    },
  );

  test('buffered adapter rejects reordered or duplicated valid GCM chunks', () async {
    final plain = Uint8List(_chunkSize * 2)
      ..fillRange(0, _chunkSize, 0x11)
      ..fillRange(_chunkSize, _chunkSize * 2, 0x22);
    final adapter = downloadAdapter();
    for (final order in [[1, 0], [0, 0]]) {
      await prepareDownload(plain, chunkOrder: order);
      await expectLater(
        adapter.downloadFileBytes('/source.bin'),
        throwsStateError,
      );
    }
  });

  test('buffered adapter rejects truncated manifests and wrong hashes', () async {
    final adapter = downloadAdapter();
    await prepareDownload(Uint8List(_chunkSize + 1), reportedChunks: 1);
    await expectLater(adapter.downloadFileBytes('/source.bin'), throwsStateError);
    expect(requests.length, 1, reason: 'Reject a changed count before chunk I/O');
    await prepareDownload([1, 2, 3], hash: 'wrong');
    await expectLater(adapter.downloadFileBytes('/source.bin'), throwsStateError);
    await prepareDownload([1, 2, 3], size: 4);
    await expectLater(adapter.downloadFileBytes('/source.bin'), throwsStateError);
  });

  test('file adapter preserves the destination until final verification', () async {
    final adapter = downloadAdapter();
    final destination = File('${directory.path}/destination.bin');
    await destination.writeAsBytes([9, 8, 7]);
    await prepareDownload([1, 2, 3], hash: 'wrong');
    await expectLater(
      adapter.downloadFileByPath('/source.bin', destination.path),
      throwsStateError,
    );
    expect(await destination.readAsBytes(), [9, 8, 7]);
    expect(
      await directory.list().where((entry) => entry is Directory).toList(),
      isEmpty,
      reason: 'Failed authenticated downloads must remove private staging',
    );

    await prepareDownload([1, 2, 3]);
    await adapter.downloadFileByPath('/source.bin', destination.path);
    expect(await destination.readAsBytes(), [1, 2, 3]);
  });

  test('failed file verification does not create a new destination', () async {
    final adapter = downloadAdapter();
    final destination = File('${directory.path}/new-destination.bin');
    await prepareDownload([1, 2, 3], hash: 'wrong');
    await expectLater(
      adapter.downloadFileByPath('/source.bin', destination.path),
      throwsStateError,
    );
    expect(await destination.exists(), isFalse);
  });

  test('adapter readers retain size-checked legacy files without a hash', () async {
    final adapter = downloadAdapter();
    final destination = File('${directory.path}/legacy.bin');
    await prepareDownload([1, 2, 3], includeHash: false);
    expect(await adapter.downloadFileBytes('/source.bin'), [1, 2, 3]);
    await adapter.downloadFileByPath('/source.bin', destination.path);
    expect(await destination.readAsBytes(), [1, 2, 3]);
    await prepareDownload([1, 2, 3], includeHash: false, size: 4);
    await expectLater(adapter.downloadFileBytes('/source.bin'), throwsStateError);
  });

  test('account changes cannot publish a file after its last chunk', () async {
    final adapter = downloadAdapter();
    final destination = File('${directory.path}/destination.bin');
    await destination.writeAsBytes([9]);
    await prepareDownload([1, 2, 3]);
    await expectLater(
      adapter.downloadFileByPath(
        '/source.bin',
        destination.path,
        onProgress: (_, _) => client.apiKey = 'different-account-token',
      ),
      throwsStateError,
    );
    expect(await destination.readAsBytes(), [9]);
  });

  test(
    'download rejects oversized encrypted chunks before decrypting',
    () async {
      await prepareDownload([1]);
      final metadataReply = respond;
      respond = (request) => request.url.path == '/v3/file'
          ? metadataReply(request)
          : Future.value(
              http.Response.bytes(Uint8List(_chunkSize + 1025), 200),
            );
      await expectLater(download().drain<void>(), throwsStateError);
    },
  );

  test('download checks the captured account before the next chunk', () async {
    await prepareDownload(Uint8List(_chunkSize + 1));
    var available = true;
    final iterator = StreamIterator(
      download(
        check: () {
          if (!available) throw StateError('Account changed');
        },
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    available = false;
    await expectLater(iterator.moveNext(), throwsStateError);
    expect(requests.length, 2);
    await iterator.cancel();
  });

  test(
    'uploads use bounded encrypted chunks and compatible verified metadata',
    () async {
      final plain = Uint8List.fromList(
        List.generate(_chunkSize + 13, (i) => i % 239),
      );
      await upload(
        Stream.fromIterable([plain.sublist(0, 500000), plain.sublist(500000)]),
        plain.length,
      );
      expect(requests.length, 3);
      expect(requests[0].bodyBytes.length, _chunkSize + 28);
      expect(requests[1].bodyBytes.length, 13 + 28);
      expect(requests[2].url.path, '/v3/upload/done');
      final commit = jsonDecode(requests[2].body) as Map;
      expect(commit['chunks'], 2);
      final metadata = jsonDecode(
        await client.crypto.tryDecrypt(commit['metadata'], [_master]),
      ) as Map;
      expect(metadata['name'], 'résumé %20.bin');
      expect(metadata['size'], plain.length);
      expect(metadata['hash'], sha512.convert(plain).toString());
      final key = client.crypto.decodeUniversalKey(metadata['key']);
      final restored = BytesBuilder();
      for (final request in requests.take(2)) {
        expect(request.url.queryParameters['parent'], 'root-id');
        expect(request.url.queryParameters['uuid'], commit['uuid']);
        expect(
          request.url.queryParameters['hash'],
          sha512.convert(request.bodyBytes).toString(),
        );
        restored.add(await client.crypto.decryptData(request.bodyBytes, key));
      }
      expect(restored.takeBytes(), plain);
    },
  );

  for (final declared in [0, 2, 4]) {
    test('wrong source length $declared cannot commit a file', () async {
      await expectLater(
        upload(Stream.value([1, 2, 3]), declared),
        throwsStateError,
      );
      expect(requests, isEmpty);
    });
  }

  test(
    'empty file upload waits for source EOF and uses empty-file protocol',
    () async {
      final source = StreamController<List<int>>();
      final pending = upload(source.stream, 0);
      await Future<void>.delayed(Duration.zero);
      expect(requests, isEmpty);
      await source.close();
      await pending;
      expect(requests.single.url.path, '/v3/upload/empty');
      expect(jsonDecode(requests.single.body)['parent'], 'root-id');
    },
  );

  test('rejected chunk or oversized acknowledgement cannot finalize', () async {
    respond = (_) async => http.Response('{"status":false}', 200);
    await expectLater(upload(Stream.value([1]), 1), throwsStateError);
    expect(requests.single.url.host, 'ingest.filen.io');
    requests.clear();
    respond = (_) async => http.Response('x' * (256 * 1024 + 1), 200);
    await expectLater(upload(Stream.value([1]), 1), throwsStateError);
    expect(requests.length, 1);
  });

  test('remote path resolution preserves literal edge whitespace', () async {
    client.cache.pathCache[' source '] = {
      'type': 'file',
      'uuid': 'spaced-name-id',
    };
    expect((await client.resolvePath('/ source '))['uuid'], 'spaced-name-id');
    expect(requests, isEmpty);
  });

  test(
    'adapter account switch during source consumption prevents all writes',
    () async {
      final adapter = FilenClientAdapter.withClient(
        client,
        config: FilenConfigService(
          configPath: directory.path,
          secureStorage: InMemorySecureStorage(),
        ),
      );
      Stream<List<int>> source() async* {
        client.apiKey = 'different-account-token';
        yield [1];
      }

      expect(adapter.supportsStreaming, isTrue);
      expect(adapter.transferCapabilities.boundedUpload, isTrue);
      expect(adapter.transferCapabilities.boundedDownload, isTrue);
      await expectLater(
        adapter.uploadStream(source(), 1, 'target.bin', '/'),
        throwsStateError,
      );
      expect(requests, isEmpty);
    },
  );
}
