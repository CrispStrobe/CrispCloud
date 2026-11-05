import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _largePartSize = 80 * 1024 * 1024;
const _largePartHash =
    'd2dc21ece13e1a08e8990cbfc3285630841d0720d4c71cf10a026bc71a4867d9';

Future<S3ClientAdapter> _adapter() async {
  final config = S3ConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'accessKey': 'test-access',
    'secretKey': 'test-secret',
    'endpoint': 'https://s3.amazonaws.com',
    'bucket': 'bucket',
    'region': 'us-east-1',
  });
  final adapter = S3ClientAdapter(config: config);
  expect(await adapter.restoreCredentials(), isTrue);
  return adapter;
}

Stream<List<int>> _repeatBytes(int length, {int value = 7}) async* {
  final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, value);
  var remaining = length;
  while (remaining > 0) {
    final count = remaining.clamp(0, chunk.length);
    yield count == chunk.length
        ? chunk
        : Uint8List.sublistView(chunk, 0, count);
    remaining -= count;
  }
}

Stream<List<int>> _largeSource({
  bool changed = false,
  Future<void> Function(int)? onProduced,
  void Function()? onEnd,
}) async* {
  var produced = 0;
  await for (final chunk in _repeatBytes(
    _largePartSize,
    value: changed ? 8 : 7,
  )) {
    produced += chunk.length;
    await onProduced?.call(produced);
    yield chunk;
  }
  yield [8, 9, 10];
  onEnd?.call();
}

class _RemotePart {
  _RemotePart(this.length, this.digest);
  final int length;
  final String digest;
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.server);
  final _S3Server server;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      server.send(request);
  @override
  void close() => server.closedClients++;
}

/// The transport hashes request chunks without collecting the part body. This
/// catches a buffering regression that MockClient's full-body requests conceal.
class _S3Server {
  final parts = <int, _RemotePart>{};
  final attempts = <int>[];
  int requests = 0;
  int closedClients = 0;
  int initiations = 0;
  int completions = 0;
  int maximumChunk = 0;
  int? failPartOnce;
  String? customerKey;
  String? initiationBody;
  String? listBody;
  Future<void> Function(int, http.BaseRequest)? beforePart;

  http.Client createClient() => _StreamingClient(this);

  http.StreamedResponse _reply(
    String body, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: headers,
  );

  void _checkEncryption(http.BaseRequest request) {
    if (customerKey == null) return;
    expect(
      request.headers['x-amz-server-side-encryption-customer-algorithm'],
      'AES256',
    );
    expect(
      request.headers['x-amz-server-side-encryption-customer-key'],
      customerKey,
    );
    expect(
      request.headers['x-amz-server-side-encryption-customer-key-md5'],
      base64Encode(md5.convert(base64Decode(customerKey!)).bytes),
    );
  }

  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    expect(request.followRedirects, isFalse);
    final query = request.url.queryParameters;
    if (query.containsKey('uploads')) {
      initiations++;
      _checkEncryption(request);
      await request.finalize().drain<void>();
      return _reply(
        initiationBody ?? '<InitiateMultipartUploadResult><UploadId>session</UploadId></InitiateMultipartUploadResult>',
      );
    }
    expect(query['uploadId'], 'session');
    if (request.method == 'GET') {
      await request.finalize().drain<void>();
      expect(query['max-parts'], '250');
      return _reply(
        listBody ??
            '<ListPartsResult><IsTruncated>false</IsTruncated>'
                '${parts.entries.map((entry) => '<Part><PartNumber>${entry.key}</PartNumber>'
                    '<ETag>&quot;part-${entry.key}&quot;</ETag><Size>${entry.value.length}</Size>'
                    '<ChecksumSHA256>${entry.value.digest}</ChecksumSHA256></Part>').join()}'
                '</ListPartsResult>',
      );
    }
    if (request.method == 'PUT') {
      final number = int.parse(query['partNumber']!);
      attempts.add(number);
      _checkEncryption(request);
      await beforePart?.call(number, request);
      var received = 0;
      final digest = await sha256
          .bind(
            request.finalize().map((chunk) {
              maximumChunk = chunk.length > maximumChunk
                  ? chunk.length
                  : maximumChunk;
              received += chunk.length;
              return chunk;
            }),
          )
          .first;
      expect(received, request.contentLength);
      expect(request.headers['x-amz-content-sha256'], digest.toString());
      if (failPartOnce == number) {
        failPartOnce = null;
        return _reply('Temporary service failure', status: 503);
      }
      parts[number] = _RemotePart(received, digest.toString());
      return _reply('', headers: {'etag': '"part-$number"'});
    }
    expect(request.method, 'POST');
    final body = await request.finalize().bytesToString();
    expect(body, contains('<CompleteMultipartUpload>'));
    for (final number in parts.keys) {
      expect(body, contains('<PartNumber>$number</PartNumber>'));
    }
    completions++;
    return _reply('<CompleteMultipartUploadResult/>');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryRoot;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporaryRoot = await Directory.systemTemp.createTemp('s3-stream-test-');
  });
  tearDown(() => temporaryRoot.delete(recursive: true));

  Future<T> withSpools<T>(Future<T> Function() action) =>
      IOOverrides.runZoned(action, getSystemTempDirectory: () => temporaryRoot);

  test('large parts stream from private storage and resume by hashing without respooling', () async {
    final adapter = await _adapter();
    final key = base64Encode(List.filled(32, 1));
    adapter.encryption = S3Encryption.sseC;
    adapter.customerEncryptionKey = key;
    final server = _S3Server()
      ..customerKey = key
      ..failPartOnce = 2;
    var produced = 0;
    var sourceEnded = false;
    server.beforePart = (number, request) async {
      final spools = await temporaryRoot.list().toList();
      if (number == 1) {
        expect(produced, _largePartSize);
        expect(spools, hasLength(1));
        expect(
          await File('${spools.single.path}/payload').length(),
          _largePartSize,
        );
      } else {
        expect(sourceEnded, isTrue);
        expect(spools, isEmpty);
      }
    };
    await withSpools(
      () => http.runWithClient(() async {
        await expectLater(
          adapter.uploadStream(
            _largeSource(
              onProduced: (count) async => produced = count,
              onEnd: () => sourceEnded = true,
            ),
            _largePartSize + 3,
            'large.bin',
            '/',
            multipartPartSize: _largePartSize,
          ),
          throwsA(isA<Exception>()),
        );
        expect(server.parts[1]!.digest, _largePartHash);
        final saved = (await adapter.getInterruptedUploads()).single;
        expect(saved['partSize'], _largePartSize);
        expect((saved['parts'] as List).single['sha256'], _largePartHash);
        expect(await temporaryRoot.list().toList(), isEmpty);
        expect(server.completions, 0);

        server.beforePart = (number, request) async {
          expect(number, 2);
          expect(sourceEnded, isTrue);
          expect(await temporaryRoot.list().toList(), isEmpty);
        };
        final beforeChanged = server.attempts.length;
        await expectLater(
          adapter.uploadStream(
            _largeSource(changed: true),
            _largePartSize + 3,
            'large.bin',
            '/',
            multipartPartSize: _largePartSize,
          ),
          throwsStateError,
        );
        expect(server.attempts.length, beforeChanged);
        expect(await temporaryRoot.list().toList(), isEmpty);
        expect(server.initiations, 1);
        expect(
          (await adapter.getInterruptedUploads()).single['parts'],
          hasLength(1),
        );

        sourceEnded = false;
        await adapter.uploadStream(
          _largeSource(
            onProduced: (count) async {
              if (count == 64 * 1024 || count == 64 * 1024 * 1024) {
                expect(await temporaryRoot.list().toList(), isEmpty);
              }
            },
            onEnd: () => sourceEnded = true,
          ),
          _largePartSize + 3,
          'large.bin',
          '/',
          multipartPartSize: _largePartSize,
        );
      }, server.createClient),
    );
    expect(server.attempts, [1, 2, 2]);
    expect(
      server.parts[2]!.digest,
      '6e9fa019228fe1a9d342d4a0085ab80270c9726bd08cd5a35d7626a700b34e2f',
    );
    expect(server.maximumChunk, lessThanOrEqualTo(64 * 1024));
    expect(server.initiations, 1);
    expect(server.completions, 1);
    expect(server.closedClients, server.requests);
    expect(await adapter.getInterruptedUploads(), isEmpty);
    expect(await temporaryRoot.list().toList(), isEmpty);
  });

  test(
    'an oversized final source is rejected before its spooled part is uploaded',
    () async {
      final adapter = await _adapter();
      final server = _S3Server();
      const length = 65 * 1024 * 1024;
      await withSpools(
        () => http.runWithClient(() async {
          await expectLater(
            adapter.uploadStream(
              _repeatBytes(length + 1),
              length,
              'large.bin',
              '/',
              multipartPartSize: _largePartSize,
            ),
            throwsStateError,
          );
        }, server.createClient),
      );
      expect(server.initiations, 1);
      expect(server.attempts, isEmpty);
      expect(server.completions, 0);
      expect(await temporaryRoot.list().toList(), isEmpty);
      expect(server.closedClients, server.requests);
    },
  );

  test('source failures remove partially written private spools', () async {
    final adapter = await _adapter();
    final server = _S3Server();
    Stream<List<int>> source() async* {
      yield Uint8List(64 * 1024);
      throw StateError('Source read failed');
    }

    await withSpools(
      () => http.runWithClient(() async {
        await expectLater(
          adapter.uploadStream(
            source(),
            _largePartSize,
            'large.bin',
            '/',
            multipartPartSize: _largePartSize,
          ),
          throwsStateError,
        );
      }, server.createClient),
    );
    expect(server.attempts, isEmpty);
    expect(server.completions, 0);
    expect(await temporaryRoot.list().toList(), isEmpty);
  });

  test(
    'adaptive sizing reaches the provider limit without allocating a part',
    () async {
      final adapter = await _adapter();
      final server = _S3Server();
      const length =
          S3ClientAdapter.maximumPartSize * S3ClientAdapter.maximumPartCount;
      final sourceFailure = StateError('Stop before generating enormous input');
      await withSpools(
        () => http.runWithClient(() async {
          await expectLater(
            adapter.uploadStream(
              Stream.error(sourceFailure),
              length,
              'large.bin',
              '/',
            ),
            throwsA(same(sourceFailure)),
          );
        }, server.createClient),
      );
      expect(
        (await adapter.getInterruptedUploads()).single['partSize'],
        S3ClientAdapter.maximumPartSize,
      );
      expect(
        await adapter.hasPendingUpload('/large.bin', length: length),
        isTrue,
      );
      expect(server.initiations, 1);
      expect(server.attempts, isEmpty);
      expect(await temporaryRoot.list().toList(), isEmpty);
    },
  );

  test(
    'out of range sizes fail before input consumption or network mutation',
    () async {
      final adapter = await _adapter();
      final server = _S3Server();
      var consumed = false;
      Stream<List<int>> source() async* {
        consumed = true;
        yield [1];
      }

      await http.runWithClient(() async {
        await expectLater(
          adapter.uploadStream(
            source(),
            S3ClientAdapter.maximumPartSize * S3ClientAdapter.maximumPartCount +
                1,
            'large.bin',
            '/',
          ),
          throwsUnsupportedError,
        );
        await expectLater(
          adapter.uploadStream(
            source(),
            1,
            'large.bin',
            '/',
            multipartPartSize: S3ClientAdapter.maximumPartSize + 1,
          ),
          throwsArgumentError,
        );
        await expectLater(
          adapter.uploadStream(
            source(),
            5 * 1024 * 1024 * 10000 + 1,
            'large.bin',
            '/',
            multipartPartSize: 5 * 1024 * 1024,
          ),
          throwsUnsupportedError,
        );
      }, server.createClient);
      expect(consumed, isFalse);
      expect(server.requests, 0);
    },
  );

  test(
    'oversized multipart metadata cannot grow an unbounded response buffer',
    () async {
      final adapter = await _adapter();
      final server = _S3Server()..initiationBody = 'x' * (256 * 1024 + 1);
      var consumed = false;
      Stream<List<int>> source() async* {
        consumed = true;
        yield [1];
      }

      await http.runWithClient(() async {
        await expectLater(
          adapter.uploadStream(source(), 1, 'tiny.bin', '/'),
          throwsStateError,
        );
      }, server.createClient);
      expect(consumed, isFalse);
      expect(server.attempts, isEmpty);
      expect(server.closedClients, server.requests);
    },
  );

  test('repeated multipart pagination cannot loop indefinitely', () async {
    final adapter = await _adapter();
    final server = _S3Server()
      ..listBody =
          '<ListPartsResult><IsTruncated>true</IsTruncated>'
          '<NextPartNumberMarker>1</NextPartNumberMarker></ListPartsResult>';
    await http.runWithClient(() async {
      await expectLater(
        adapter.listParts('large.bin', 'session'),
        throwsStateError,
      );
    }, server.createClient);
    expect(server.requests, 2);
    expect(server.closedClients, server.requests);
  });
}
