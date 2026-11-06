import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:crisp_cloud/services/internxt_client_adapter.dart';
import 'package:crisp_cloud/services/internxt_streaming_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:internxt_client/internxt_client.dart' as sdk;

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _bucket = '0123456789abcdef01234567';

sdk.InternxtClient session() =>
    sdk.InternxtClient(
      config: sdk.ConfigService(
        configPath: '/unused',
        storage: sdk.InMemoryConfigStorage(),
      ),
      driveApiUrl: 'https://drive.example.test',
      networkUrl: 'https://network.example.test',
    )..setAuth({
      'userId': 'fixture-account',
      'bucketId': _bucket,
      'rootFolderId': 'root-folder',
      'newToken': 'synthetic-token',
      'bridgeUser': 'fixture-bridge',
      'userIdForAuth': 'fixture-account',
      'mnemonic': _mnemonic,
    });

class _Fixture extends http.BaseClient {
  _Fixture(this.plain) {
    final encrypted = sdk.encryptStream(plain, _mnemonic, _bucket);
    cipher = encrypted['data'] as Uint8List;
    index = encrypted['index'] as String;
  }
  final Uint8List plain;
  late Uint8List cipher;
  late String index;
  String? checksumOverride;
  Object? listingBody;
  int listingStatus = 200;
  int? declaredDownloadSize;
  int downloadChunk = 65536;
  int? truncateDownloadAt;
  bool extraDownloadByte = false, missingEtag = false;
  bool failStart = false, failFinish = false, failRegister = false;
  bool wrongUploadMetadata = false, oversizeStart = false;
  String? unsafeDownloadUrl, unsafeUploadUrl;
  Future<void> Function()? afterMetadata, afterUploadPart, afterDownloadChunk;
  int starts = 0,
      finishes = 0,
      registrations = 0,
      downloadReads = 0,
      closed = 0;
  final partLengths = <int>[];
  final uploadChunkLengths = <int>[];
  final uploadedCipher = BytesBuilder(copy: false);
  final requests = <http.BaseRequest>[];
  Map<String, dynamic>? finishBody, registeredBody;
  int? partCount;
  int get total => declaredDownloadSize ?? plain.length;

  Map<String, dynamic> get downloadMeta => {
    'uuid': 'download-file',
    'plainName': 'file',
    'type': 'bin',
    'size': total,
    'bucket': _bucket,
    'fileId': 'network-file',
    'folderUuid': 'root-folder',
  };
  http.StreamedResponse jsonResponse(Object body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    expect(request.followRedirects, isFalse);
    if (request.url.host == 'objects.example.test') {
      expect(request.headers['authorization'], isNull);
      if (request.method == 'GET') {
        Stream<List<int>> data() async* {
          final actual = truncateDownloadAt == null
              ? cipher
              : cipher.sublist(0, truncateDownloadAt!);
          for (var start = 0; start < actual.length; start += downloadChunk) {
            downloadReads++;
            yield actual.sublist(
              start,
              (start + downloadChunk).clamp(0, actual.length),
            );
            await afterDownloadChunk?.call();
          }
          if (extraDownloadByte) yield [99];
        }

        return http.StreamedResponse(data(), 200, contentLength: cipher.length);
      }
      var size = 0;
      await for (final bytes in request.finalize()) {
        uploadChunkLengths.add(bytes.length);
        uploadedCipher.add(bytes);
        size += bytes.length;
      }
      expect(size, request.contentLength);
      partLengths.add(size);
      await afterUploadPart?.call();
      return http.StreamedResponse(
        const Stream.empty(),
        200,
        headers: missingEtag ? {} : {'etag': '"part-${partLengths.length}"'},
      );
    }
    final network = request.url.host == 'network.example.test';
    expect(
      request.headers['authorization'],
      network ? startsWith('Basic ') : 'Bearer synthetic-token',
    );
    final path = request.url.path;
    if (path == '/folders/content/root-folder/folders') {
      return jsonResponse(listingBody ?? {'result': []}, listingStatus);
    }
    if (path == '/folders/content/root-folder/files') {
      return jsonResponse({
        'result': [
          downloadMeta,
          if (registeredBody != null)
            {...registeredBody!, 'uuid': 'uploaded-file'},
        ],
      });
    }
    if (path == '/files/download-file/meta') {
      await afterMetadata?.call();
      return jsonResponse(downloadMeta);
    }
    if (path.endsWith('/files/network-file/info')) {
      return jsonResponse({
        'index': index,
        'shards': [
          {
            'url': unsafeDownloadUrl ?? 'https://objects.example.test/file',
            'hash':
                checksumOverride ?? crypto.sha256.convert(cipher).toString(),
          },
        ],
      });
    }
    if (path.endsWith('/files/start')) {
      starts++;
      partCount = int.parse(request.url.queryParameters['multiparts']!);
      final body =
          jsonDecode(utf8.decode(await request.finalize().toBytes())) as Map;
      expect((body['uploads'] as List).single['index'], 0);
      if (failStart) return jsonResponse({'error': 'synthetic-token'}, 503);
      if (oversizeStart) {
        return http.StreamedResponse(
          Stream.value(Uint8List(256 * 1024 + 1)),
          200,
        );
      }
      return jsonResponse({
        'uploads': [
          {
            'uuid': 'shard-uuid',
            if (partCount == 1)
              'url': unsafeUploadUrl ?? 'https://objects.example.test/single',
            if (partCount! > 1) ...{
              'UploadId': 'multipart-session',
              'urls': [
                for (var i = 0; i < partCount!; i++)
                  'https://objects.example.test/part/$i',
              ],
            },
          },
        ],
      });
    }
    if (path.endsWith('/files/finish')) {
      finishes++;
      finishBody = jsonDecode(
        utf8.decode(await request.finalize().toBytes()),
      ) as Map<String, dynamic>;
      if (failFinish) return jsonResponse({'error': 'synthetic-token'}, 503);
      return jsonResponse({'id': 'uploaded-network-file'});
    }
    if (path == '/files' && request.method == 'POST') {
      registrations++;
      registeredBody = jsonDecode(
        utf8.decode(await request.finalize().toBytes()),
      ) as Map<String, dynamic>;
      if (failRegister) return jsonResponse({'error': 'synthetic-token'}, 503);
      return jsonResponse({'uuid': 'uploaded-file'}, 201);
    }
    if (path == '/files/uploaded-file/meta') {
      return jsonResponse({
        ...registeredBody!,
        'uuid': 'uploaded-file',
        if (wrongUploadMetadata) 'fileId': 'some-other-network-file',
      });
    }
    throw StateError(
      'Unexpected fixture request ${request.method} ${request.url.path}',
    );
  }

  @override
  void close() => closed++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late sdk.InternxtClient client;
  late InternxtClientAdapter adapter;
  late _Fixture fixture;
  late Directory temp;
  setUp(() async {
    temp = await Directory.current.createTemp('internxt_transfer_test_');
    client = session();
    adapter = InternxtClientAdapter.withClient(client);
    fixture = _Fixture(
      Uint8List.fromList(List.generate(150003, (index) => index % 251)),
    );
  });
  tearDown(() => temp.delete(recursive: true));
  Future<void> run(Future<void> Function() body) => IOOverrides.runZoned(
    () => http.runWithClient(body, () => fixture),
    getSystemTempDirectory: () => temp,
  );
  Future<void> clean() async => expect(await temp.list().toList(), isEmpty);

  test(
    'missing paths are distinct from denied or malformed directory responses',
    () => run(() async {
      expect(await adapter.resolvePath('/not-present.bin'), isNull);
      fixture.listingStatus = 403;
      await expectLater(
        adapter.resolvePath('/not-present.bin'),
        throwsStateError,
      );
      await expectLater(adapter.listPath('/'), throwsStateError);
      fixture.listingStatus = 200;
      fixture.listingBody = {'error': 'not a directory listing'};
      await expectLater(
        adapter.resolvePath('/not-present.bin'),
        throwsStateError,
      );
      await expectLater(adapter.listPath('/'), throwsStateError);
      expect(fixture.starts, 0);
    }),
  );

  test(
    'CTR download yields bounded plaintext identical to one-shot SDK crypto',
    () => run(() async {
      fixture.downloadChunk = 100003;
      final chunks = await adapter.downloadStream('/file.bin').toList();
      expect(chunks.every((bytes) => bytes.length <= 65536), isTrue);
      expect(chunks.expand((bytes) => bytes), fixture.plain);
      expect(fixture.closed, greaterThanOrEqualTo(3));
      expect(adapter.transferCapabilities.boundedDownload, isTrue);
      expect(adapter.transferCapabilities.boundedUpload, isTrue);
      expect(adapter.transferCapabilities.noReplaceMove, isFalse);
    }),
  );

  test(
    'download cancellation stops before reading later ciphertext chunks',
    () => run(() async {
      final chunks = await adapter.downloadStream('/file.bin').take(1).toList();
      expect(chunks.single.length, 65536);
      expect(fixture.downloadReads, 1);
      expect(fixture.closed, greaterThanOrEqualTo(3));
    }),
  );

  test(
    'ciphertext checksum mismatch prevents a completed download',
    () => run(() async {
      fixture.checksumOverride = '0' * 64;
      await expectLater(
        adapter.downloadStream('/file.bin').drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('checksum'),
          ),
        ),
      );
      expect(fixture.downloadReads, 3);
    }),
  );

  for (final mode in ['truncated', 'extra', 'metadata-size']) {
    test(
      'download rejects $mode content instead of padding or truncating',
      () => run(() async {
        if (mode == 'truncated') fixture.truncateDownloadAt = 65537;
        if (mode == 'extra') fixture.extraDownloadByte = true;
        if (mode == 'metadata-size') {
          fixture.declaredDownloadSize = fixture.plain.length + 1;
        }
        await expectLater(
          adapter.downloadStream('/file.bin').drain<void>(),
          throwsStateError,
        );
      }),
    );
  }

  test(
    'download account change after metadata prevents requesting a signed link',
    () => run(() async {
      fixture.afterMetadata = () async {
        client.userId = 'replacement';
      };
      await expectLater(
        adapter.downloadStream('/file.bin').drain<void>(),
        throwsStateError,
      );
      expect(
        fixture.requests.any(
          (request) => request.url.host == 'network.example.test',
        ),
        isFalse,
      );
    }),
  );

  test(
    'download account change between chunks stops remaining plaintext',
    () => run(() async {
      fixture.afterDownloadChunk = () async {
        client.mnemonic = 'replacement mnemonic';
      };
      await expectLater(
        adapter.downloadStream('/file.bin').drain<void>(),
        throwsStateError,
      );
      expect(fixture.downloadReads, lessThan(3));
    }),
  );

  test(
    'upload encrypts split input once, hashes ciphertext and verifies created identity',
    () => run(() async {
      final progress = <(int, int)>[];
      await adapter.uploadStream(
        Stream.fromIterable([
          fixture.plain.sublist(0, 3),
          fixture.plain.sublist(3, 65539),
          fixture.plain.sublist(65539),
        ]),
        fixture.plain.length,
        'report #1.bin',
        '/',
        onProgress: (done, total) => progress.add((done, total)),
      );
      final encrypted = fixture.uploadedCipher.takeBytes();
      final index = fixture.finishBody!['index'] as String;
      expect(
        sdk.decryptStream(encrypted, _mnemonic, _bucket, index),
        fixture.plain,
      );
      expect(
        (fixture.finishBody!['shards'] as List).single['hash'],
        crypto.sha256.convert(encrypted).toString(),
      );
      expect(fixture.uploadChunkLengths.every((size) => size <= 65536), isTrue);
      expect(fixture.registeredBody, containsPair('plainName', 'report #1'));
      expect(fixture.registeredBody, containsPair('encryptVersion', 'Aes03'));
      expect(progress.last, (fixture.plain.length, fixture.plain.length));
      await clean();
      final refreshed = await adapter.listPath('/');
      expect(
        (refreshed['files'] as List).any(
          (file) => file['uuid'] == 'uploaded-file',
        ),
        isTrue,
      );
    }),
  );

  test(
    'multipart slices retain continuous CTR state and ordered ETags',
    () => run(() async {
      adapter = InternxtClientAdapter.withClient(
        client,
        streaming: const InternxtStreamingTransfer(
          multipartMinimum: 1,
          preferredPartSize: 50001,
        ),
      );
      await adapter.uploadStream(
        Stream.value(fixture.plain),
        fixture.plain.length,
        'file.bin',
        '/',
      );
      expect(fixture.partLengths, [50001, 50001, 50001]);
      final shard = (fixture.finishBody!['shards'] as List).single;
      expect(shard['UploadId'], 'multipart-session');
      expect(shard['parts'], [
        for (var i = 1; i <= 3; i++) {'PartNumber': i, 'ETag': 'part-$i'},
      ]);
      expect(
        sdk.decryptStream(
          fixture.uploadedCipher.takeBytes(),
          _mnemonic,
          _bucket,
          fixture.finishBody!['index'] as String,
        ),
        fixture.plain,
      );
      await clean();
    }),
  );

  test(
    'multipart missing ETag prevents finalization and drive registration',
    () => run(() async {
      fixture.missingEtag = true;
      adapter = InternxtClientAdapter.withClient(
        client,
        streaming: const InternxtStreamingTransfer(
          multipartMinimum: 1,
          preferredPartSize: 50001,
        ),
      );
      await expectLater(
        adapter.uploadStream(
          Stream.value(fixture.plain),
          fixture.plain.length,
          'file.bin',
          '/',
        ),
        throwsStateError,
      );
      expect(fixture.partLengths, hasLength(1));
      expect(fixture.finishes, 0);
      expect(fixture.registrations, 0);
      await clean();
    }),
  );

  test(
    'multipart adapts part size to keep URL and completion metadata bounded',
    () => run(() async {
      adapter = InternxtClientAdapter.withClient(
        client,
        streaming: const InternxtStreamingTransfer(
          multipartMinimum: 1,
          preferredPartSize: 1,
        ),
      );
      await adapter.uploadStream(
        Stream.value(fixture.plain),
        fixture.plain.length,
        'file.bin',
        '/',
      );
      expect(fixture.partCount, 128);
      expect(fixture.partLengths, hasLength(128));
      expect(fixture.partLengths.reduce((a, b) => a + b), fixture.plain.length);
      expect(fixture.finishes, 1);
      expect(fixture.registrations, 1);
      await clean();
    }),
  );

  for (final declared in [2, 4]) {
    test(
      'declared source length $declared mismatch performs no upload mutation',
      () => run(() async {
        await expectLater(
          adapter.uploadStream(
            Stream.value([1, 2, 3]),
            declared,
            'file.bin',
            '/',
          ),
          throwsStateError,
        );
        expect(fixture.starts, 0);
        expect(fixture.registrations, 0);
        await clean();
      }),
    );
  }

  test(
    'empty files use an exact zero-byte ciphertext and still verify registration',
    () => run(() async {
      await adapter.uploadStream(const Stream.empty(), 0, 'empty.bin', '/');
      expect(fixture.partLengths, [0]);
      expect(fixture.registeredBody!['size'], 0);
      expect(
        (fixture.finishBody!['shards'] as List).single['hash'],
        crypto.sha256.convert([]).toString(),
      );
      await clean();
    }),
  );

  test(
    'same credentials restored after logout cannot revive a running upload',
    () => run(() async {
      fixture.afterUploadPart = () async {
        await adapter.logout();
        adapter.setAuth({
          'userId': 'fixture-account',
          'bucketId': _bucket,
          'rootFolderId': 'root-folder',
          'newToken': 'synthetic-token',
          'bridgeUser': 'fixture-bridge',
          'userIdForAuth': 'fixture-account',
          'mnemonic': _mnemonic,
        });
      };
      await expectLater(
        adapter.uploadStream(Stream.value([1, 2]), 2, 'file.bin', '/'),
        throwsStateError,
      );
      expect(fixture.finishes, 0);
      expect(fixture.registrations, 0);
      await clean();
    }),
  );

  for (final stage in ['start', 'finish', 'register']) {
    test(
      '$stage failure is not retried and cannot expose credentials',
      () => run(() async {
        fixture.failStart = stage == 'start';
        fixture.failFinish = stage == 'finish';
        fixture.failRegister = stage == 'register';
        await expectLater(
          adapter.uploadStream(Stream.value([1, 2]), 2, 'file.bin', '/'),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'redacted diagnostic',
              isNot(contains('synthetic-token')),
            ),
          ),
        );
        expect(fixture.starts, 1);
        expect(fixture.finishes, lessThanOrEqualTo(1));
        expect(fixture.registrations, lessThanOrEqualTo(1));
        await clean();
      }),
    );
  }

  test(
    'mismatching created file identity cannot report successful upload',
    () => run(() async {
      fixture.wrongUploadMetadata = true;
      await expectLater(
        adapter.uploadStream(Stream.value([1, 2]), 2, 'file.bin', '/'),
        throwsStateError,
      );
      await clean();
    }),
  );

  test(
    'oversized protocol metadata is rejected and staged ciphertext is removed',
    () => run(() async {
      fixture.oversizeStart = true;
      await expectLater(
        adapter.uploadStream(Stream.value([1, 2]), 2, 'file.bin', '/'),
        throwsStateError,
      );
      expect(fixture.partLengths, isEmpty);
      await clean();
    }),
  );

  test(
    'signed URLs cannot downgrade to insecure HTTP or receive account headers',
    () => run(() async {
      fixture.unsafeUploadUrl = 'http://objects.example.test/file';
      await expectLater(
        adapter.uploadStream(Stream.value([1, 2]), 2, 'file.bin', '/'),
        throwsStateError,
      );
      fixture.unsafeDownloadUrl = 'http://objects.example.test/file';
      await expectLater(
        adapter.downloadStream('/file.bin').drain<void>(),
        throwsStateError,
      );
      expect(
        fixture.requests.any((request) => request.url.scheme == 'http'),
        isFalse,
      );
      await clean();
    }),
  );

  test(
    'buffered preview refuses oversized file before ciphertext download',
    () => run(() async {
      fixture.declaredDownloadSize = 32 * 1024 * 1024 + 1;
      await expectLater(
        adapter.downloadFileBytes('/file.bin'),
        throwsStateError,
      );
      expect(fixture.downloadReads, 0);
    }),
  );

  test(
    'truncated encrypted download preserves an existing destination',
    () => run(() async {
      final target = File('${temp.path}/existing.bin');
      await target.writeAsBytes([9, 8, 7]);
      fixture.truncateDownloadAt = 65537;
      await expectLater(
        adapter.downloadFileByPath('/file.bin', target.path),
        throwsStateError,
      );
      expect(await target.readAsBytes(), [9, 8, 7]);
      expect((await temp.list().toList()).map((item) => item.path), [
        target.path,
      ]);
    }),
  );
}
