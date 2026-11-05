import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/services/azure_blob_adapter.dart';
import 'package:crisp_cloud/services/azure_config_service.dart';
import 'package:crisp_cloud/services/bounded_transfer_stream.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_config_service.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<S3ClientAdapter> s3({
  String endpoint = 'https://s3.amazonaws.com',
}) async {
  final config = S3ConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'accessKey': 'test-key',
    'secretKey': 'test-secret',
    'endpoint': endpoint,
    'bucket': 'bucket',
    'region': 'us-east-1',
  });
  final adapter = S3ClientAdapter(config: config);
  expect(await adapter.restoreCredentials(), isTrue);
  return adapter;
}

Future<AzureBlobAdapter> azure() async {
  final adapter = AzureBlobAdapter(
    config: AzureConfigService(secureStorage: InMemorySecureStorage()),
  );
  await adapter.loginWithKey(
    accountName: 'account',
    accountKey: base64Encode(utf8.encode('key')),
    container: 'bucket',
  );
  return adapter;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'bounded part splitter preserves data and consumer backpressure',
    () async {
      var reads = 0;
      Stream<List<int>> source() async* {
        reads++;
        yield [1, 2, 3, 4, 5];
        reads++;
        yield [6, 7, 8, 9];
      }

      final parts = StreamIterator(transferParts(source(), 4));
      expect(await parts.moveNext(), isTrue);
      expect(parts.current, [1, 2, 3, 4]);
      expect(reads, 1);
      expect(await parts.moveNext(), isTrue);
      expect(parts.current, [5, 6, 7, 8]);
      expect(await parts.moveNext(), isTrue);
      expect(parts.current, [9]);
      expect(await parts.moveNext(), isFalse);
      await parts.cancel();
      await expectLater(
        transferParts(Stream.value([1]), 0).toList(),
        throwsArgumentError,
      );
    },
  );

  test('S3 copy carries destination and source conditions and confirms XML completion', () async {
    final adapter = await s3();
    var copied = false;
    final client = MockClient((request) async {
      if (request.method == 'HEAD') {
        return http.Response(
          '',
          200,
          headers: {'content-length': '3', 'etag': '"source"'},
        );
      }
      expect(request.method, 'PUT');
      expect(request.url.path, endsWith('/destination'));
      expect(request.headers['if-none-match'], '*');
      expect(request.headers['x-amz-copy-source-if-match'], '"reviewed"');
      expect(request.headers['x-amz-copy-source'], '/bucket/source');
      copied = true;
      return http.Response(
        '<CopyObjectResult><ETag>"copied"</ETag></CopyObjectResult>',
        200,
      );
    });
    await http.runWithClient(() async {
      final result = await adapter.copyToExact(
        '/source',
        '/destination',
        expectedSourceVersion: '"reviewed"',
      );
      expect(copied, isTrue);
      expect(result.path, '/destination');
      expect(result.version, '"copied"');
      expect(result.size, 3);
    }, () => client);
    final compatible = await s3(endpoint: 'https://other.example.invalid');
    expect(compatible.transferCapabilities.noReplaceCopy, isFalse);
    await expectLater(
      compatible.copyToExact('/a', '/b'),
      throwsUnsupportedError,
    );
  });

  test('S3 HTTP 200 with embedded copy error never reports success', () async {
    final adapter = await s3();
    await http.runWithClient(
      () => expectLater(adapter.copyToExact('/a', '/b'), throwsStateError),
      () => MockClient(
        (request) async => request.method == 'HEAD'
            ? http.Response(
                '',
                200,
                headers: {'content-length': '3', 'etag': '"source"'},
              )
            : http.Response('<Error><Code>InternalError</Code></Error>', 200),
      ),
    );
  });

  test(
    'S3 range reads reject a server that ignores the requested range',
    () async {
      final adapter = await s3();
      await http.runWithClient(
        () async {
          await expectLater(
            adapter
                .readTransferRange('/a', 3, expectedVersion: '"old"')
                .toList(),
            throwsStateError,
          );
        },
        () => MockClient((request) async {
          expect(request.headers['range'], 'bytes=3-');
          expect(request.headers['if-match'], '"old"');
          return http.Response('entire object', 200);
        }),
      );
    },
  );

  test('S3 multipart resume skips only digest-verified parts from the same account', () async {
    final adapter = await s3();
    final prefix = Uint8List(S3ClientAdapter.defaultPartSize)
      ..fillRange(0, S3ClientAdapter.defaultPartSize, 7);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'crisp_s3_multipart_session',
      jsonEncode({
        'schema': 2,
        'storageId': storageReferenceForClient(adapter).id,
        'uploadId': 'session',
        'bucket': 'bucket',
        'key': 'target',
        'length': prefix.length + 3,
        'partSize': prefix.length,
        'parts': [
          {
            'partNumber': 1,
            'etag': '"part1"',
            'size': prefix.length,
            'sha256': sha256.convert(prefix).toString(),
          },
        ],
      }),
    );
    final uploaded = <int>[];
    var completed = false;
    final client = MockClient((request) async {
      expect(request.url.queryParameters['uploadId'], 'session');
      if (request.method == 'GET') {
        return http.Response(
          '<ListPartsResult><IsTruncated>false</IsTruncated><Part><PartNumber>1</PartNumber><ETag>"part1"</ETag><Size>${prefix.length}</Size></Part></ListPartsResult>',
          200,
        );
      }
      if (request.method == 'PUT') {
        uploaded.add(int.parse(request.url.queryParameters['partNumber']!));
        expect(request.bodyBytes, [8, 9, 10]);
        return http.Response('', 200, headers: {'etag': '"part2"'});
      }
      expect(request.body, contains('<PartNumber>1</PartNumber>'));
      expect(request.body, contains('<PartNumber>2</PartNumber>'));
      completed = true;
      return http.Response('<CompleteMultipartUploadResult/>', 200);
    });
    await http.runWithClient(() async {
      await adapter.uploadStream(
        Stream.fromIterable([
          prefix,
          [8, 9, 10],
        ]),
        prefix.length + 3,
        'target',
        '/',
      );
    }, () => client);
    expect(uploaded, [2]);
    expect(completed, isTrue);
    expect(await adapter.getInterruptedUploads(), isEmpty);
  });

  test('S3 resume rejects changed prefix and unverifiable legacy session before mutation', () async {
    final adapter = await s3();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'crisp_s3_multipart_session',
      jsonEncode({
        'schema': 2,
        'storageId': storageReferenceForClient(adapter).id,
        'uploadId': 'session',
        'key': 'target',
        'length': 3,
        'partSize': S3ClientAdapter.defaultPartSize,
        'parts': [
          {
            'partNumber': 1,
            'etag': '"part1"',
            'size': 3,
            'sha256': sha256.convert([1, 2, 3]).toString(),
          },
        ],
      }),
    );
    await http.runWithClient(
      () async {
        await expectLater(
          adapter.uploadStream(Stream.value([1, 2, 4]), 3, 'target', '/'),
          throwsStateError,
        );
      },
      () => MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response(
          '<ListPartsResult><IsTruncated>false</IsTruncated><Part><PartNumber>1</PartNumber><ETag>"part1"</ETag><Size>3</Size></Part></ListPartsResult>',
          200,
        );
      }),
    );
    await prefs.setString(
      'crisp_s3_multipart_session',
      jsonEncode({'uploadId': 'session', 'key': 'target', 'parts': []}),
    );
    await expectLater(
      adapter.resumeMultipartUpload('/target', [1, 2, 3]),
      throwsStateError,
    );
  });

  test('Azure pending copy waits for its own completion and signs conditional headers', () async {
    final adapter = await azure();
    var poll = 0;
    var requestCount = 0;
    await http.runWithClient(
      () async {
        final result = await adapter.copyToExact(
          '/bucket/a',
          '/bucket/b',
          expectedSourceVersion: '"source"',
        );
        expect(poll, 1);
        expect(result.version, '"completed"');
        expect(result.size, 4);
      },
      () => MockClient((request) async {
        requestCount++;
        if (request.method == 'PUT') {
          expect(request.headers['if-none-match'], '*');
          expect(request.headers['x-ms-source-if-match'], '"source"');
          final xms =
              request.headers.entries
                  .where((entry) => entry.key.startsWith('x-ms-'))
                  .toList()
                ..sort((a, b) => a.key.compareTo(b.key));
          final signed = [
            'PUT',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '*',
            '',
            '',
            xms.map((entry) => '${entry.key}:${entry.value}').join('\n'),
            '/account/bucket/b',
          ].join('\n');
          expect(
            request.headers['authorization'],
            'SharedKey account:${base64Encode(Hmac(sha256, utf8.encode('key')).convert(utf8.encode(signed)).bytes)}',
          );
          return http.Response(
            '',
            202,
            headers: {'x-ms-copy-id': 'id', 'x-ms-copy-status': 'pending'},
          );
        }
        expect(request.method, 'HEAD');
        poll++;
        return http.Response(
          '',
          200,
          headers: {
            'x-ms-copy-id': 'id',
            'x-ms-copy-status': 'success',
            'etag': '"completed"',
            'content-length': '4',
          },
        );
      }),
    );
    expect(requestCount, 2);
  });

  test('Azure copy error status is not a completed transfer', () async {
    final adapter = await azure();
    await http.runWithClient(
      () => expectLater(
        adapter.copyToExact('/bucket/a', '/bucket/b'),
        throwsStateError,
      ),
      () => MockClient(
        (request) async =>
            http.Response('', 202, headers: {'x-ms-copy-status': 'failed'}),
      ),
    );
  });

  test(
    'Azure upload streams bounded blocks and never commits a length mismatch',
    () async {
      final adapter = await azure();
      final prefix = Uint8List(8 * 1024 * 1024);
      final sizes = <int>[];
      final ids = <String>[];
      var commits = 0;
      await http.runWithClient(
        () async {
          await adapter.uploadStream(
            Stream.fromIterable([
              prefix,
              [1, 2, 3],
            ]),
            prefix.length + 3,
            'file',
            '/bucket',
          );
          expect(sizes, [prefix.length, 3]);
          expect(commits, 1);
          await expectLater(
            adapter.uploadStream(Stream.value([1, 2]), 3, 'short', '/bucket'),
            throwsStateError,
          );
          expect(commits, 1);
        },
        () => MockClient((request) async {
          if (request.url.queryParameters['comp'] == 'block') {
            sizes.add(request.bodyBytes.length);
            ids.add(request.url.queryParameters['blockid']!);
          } else {
            expect(request.url.queryParameters['comp'], 'blocklist');
            for (final id in ids) {
              expect(request.body, contains('<Latest>$id</Latest>'));
            }
            commits++;
          }
          return http.Response('', 201);
        }),
      );
    },
  );

  test('Dropbox exact operations disable autorename and retain the confirmed object id', () async {
    final config = DropboxConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    await config.saveCredentials({
      'app_key': 'app',
      'refresh_token': 'refresh',
      'email': 'test@example.invalid',
    });
    final adapter = DropboxClientAdapter(config: config);
    await http.runWithClient(
      () async {
        expect(await adapter.restoreCredentials(), isTrue);
        final copied = await adapter.copyToExact('/a', '/b');
        final moved = await adapter.moveToExact('/b', '/c');
        expect(copied.path, '/b');
        expect(moved.path, '/c');
        expect(moved.id, 'file-id');
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return http.Response(
            '{"access_token":"token","expires_in":3600}',
            200,
          );
        }
        final body = jsonDecode(request.body) as Map;
        expect(body['autorename'], isFalse);
        return http.Response(
          jsonEncode({
            'metadata': {
              'path_display': body['to_path'],
              'id': 'file-id',
              'rev': 'rev',
            },
          }),
          200,
        );
      }),
    );
  });
}
