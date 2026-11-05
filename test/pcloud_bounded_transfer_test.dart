import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/pcloud_client_adapter.dart';
import 'package:crisp_cloud/services/pcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late PCloudClientAdapter adapter;
  late _PCloudFixture fixture;
  late PCloudConfigService config;
  setUp(() async {
    config = PCloudConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    await config.saveCredentials({
      'app_key': 'fixture-key',
      'access_token': 'synthetic-token',
      'email': 'fixture@example.invalid',
    });
    adapter = PCloudClientAdapter(config: config);
    fixture = _PCloudFixture();
  });

  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(() async {
        expect(await adapter.restoreCredentials(), isTrue);
        await body();
      }, () => fixture);

  test(
    'PUT consumes bounded pieces and withholds its last piece until exact EOF',
    () => run(() async {
      final release = Completer<void>();
      var finishedReading = false;
      Stream<List<int>> source() async* {
        yield List.filled(64 * 1024, 1);
        yield List.filled(64 * 1024, 2);
        await release.future;
        finishedReading = true;
      }

      final progress = <(int, int)>[];
      final operation = adapter.uploadStream(
        source(),
        128 * 1024,
        'file #1.bin',
        '/folder with spaces',
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      await fixture.firstUploadPart.future;
      expect(finishedReading, isFalse);
      expect(fixture.uploadChunkSizes, [64 * 1024]);
      release.complete();
      await operation;
      expect(fixture.uploadChunkSizes, [64 * 1024, 64 * 1024]);
      expect(fixture.uploadRequest!.method, 'PUT');
      expect(fixture.uploadRequest!.contentLength, 128 * 1024);
      expect(fixture.uploadRequest!.followRedirects, isFalse);
      expect(
        fixture.uploadRequest!.url.queryParameters,
        containsPair('path', '/folder with spaces'),
      );
      expect(
        fixture.uploadRequest!.url.queryParameters,
        containsPair('filename', 'file #1.bin'),
      );
      expect(
        fixture.uploadRequest!.url.queryParameters,
        containsPair('nopartial', '1'),
      );
      expect(progress.last, (128 * 1024, 128 * 1024));
    }),
  );

  for (final size in [2, 4]) {
    test(
      'source length $size mismatch does not release the final upload bytes',
      () => run(() async {
        await expectLater(
          adapter.uploadStream(Stream.value([1, 2, 3]), size, 'file', '/'),
          throwsStateError,
        );
        expect(fixture.uploadChunkSizes, isEmpty);
        expect(fixture.completedUploads, 0);
      }),
    );
  }

  for (final invalid in [
    'missing result',
    'wrong name',
    'wrong size',
    'empty metadata',
  ]) {
    test(
      'upload rejects $invalid acknowledgement',
      () => run(() async {
        fixture.invalidAcknowledgement = invalid;
        await expectLater(
          adapter.uploadStream(Stream.value([1, 2, 3]), 3, 'file', '/'),
          throwsStateError,
        );
      }),
    );
  }

  test(
    'download streams a captured file ID and verifies final length',
    () => run(() async {
      final bytes = await adapter
          .downloadStream('/folder/file')
          .expand((chunk) => chunk)
          .toList();
      expect(bytes, [1, 2, 3, 4]);
      expect(fixture.statPath, '/folder/file');
      expect(fixture.linkFileId, '9');
      expect(fixture.downloadPartsRead, 2);
      expect(fixture.downloadRequest!.headers['authorization'], isNull);
      expect(fixture.closedClients, greaterThanOrEqualTo(3));
    }),
  );

  test(
    'download cancellation does not read remaining chunks',
    () => run(() async {
      final bytes = await adapter.downloadStream('/file').take(1).toList();
      expect(bytes, [
        [1, 2],
      ]);
      expect(fixture.downloadPartsRead, 1);
      expect(fixture.closedClients, greaterThanOrEqualTo(3));
    }),
  );

  test(
    'download rejects truncation even when the server returns HTTP 200',
    () => run(() async {
      fixture.statLength = 5;
      await expectLater(
        adapter.downloadStream('/file').toList(),
        throwsStateError,
      );
    }),
  );

  test(
    'logout while resolving a transfer cannot request a download under another session',
    () => run(() async {
      fixture.afterStat = adapter.logout;
      await expectLater(
        adapter.downloadStream('/file').toList(),
        throwsStateError,
      );
      expect(fixture.linkFileId, isNull);
      expect(fixture.downloadRequest, isNull);
    }),
  );

  test(
    'even restoring the same token cannot revive an in-flight transfer',
    () => run(() async {
      fixture.afterUploadPart = () async {
        await adapter.logout();
        expect(await adapter.restoreCredentials(), isTrue);
      };
      await expectLater(
        adapter.uploadStream(
          Stream.value(List.filled(100000, 1)),
          100000,
          'file',
          '/',
        ),
        throwsStateError,
      );
      expect(fixture.uploadChunkSizes, [64 * 1024]);
      expect(fixture.completedUploads, 0);
    }),
  );

  test(
    'authenticated connection errors do not expose access tokens',
    () => run(() async {
      fixture.failUploadConnection = true;
      await expectLater(
        adapter.uploadStream(Stream.value([1]), 1, 'file', '/'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'safe diagnostic',
            isNot(contains('synthetic-token')),
          ),
        ),
      );
    }),
  );
}

class _PCloudFixture extends http.BaseClient {
  final firstUploadPart = Completer<void>();
  final uploadChunkSizes = <int>[];
  http.BaseRequest? uploadRequest;
  http.BaseRequest? downloadRequest;
  String? statPath;
  String? linkFileId;
  int completedUploads = 0;
  int downloadPartsRead = 0;
  int closedClients = 0;
  int statLength = 4;
  String? invalidAcknowledgement;
  bool failUploadConnection = false;
  Future<void> Function()? afterStat;
  Future<void> Function()? afterUploadPart;

  http.StreamedResponse jsonResponse(Map<String, dynamic> value) =>
      http.StreamedResponse(Stream.value(utf8.encode(json.encode(value))), 200);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    switch (request.url.path) {
      case '/userinfo':
        return jsonResponse({'result': 0, 'email': 'fixture@example.invalid'});
      case '/uploadfile':
        uploadRequest = request;
        if (failUploadConnection) {
          throw http.ClientException('private', request.url);
        }
        var bytes = 0;
        await for (final part in request.finalize()) {
          uploadChunkSizes.add(part.length);
          bytes += part.length;
          if (!firstUploadPart.isCompleted) firstUploadPart.complete();
          await afterUploadPart?.call();
        }
        completedUploads++;
        return jsonResponse({
          if (invalidAcknowledgement != 'missing result') 'result': 0,
          'metadata': invalidAcknowledgement == 'empty metadata'
              ? []
              : [
                  {
                    'fileid': 11,
                    'name': invalidAcknowledgement == 'wrong name'
                        ? 'another-file'
                        : request.url.queryParameters['filename'],
                    'size': invalidAcknowledgement == 'wrong size'
                        ? bytes + 1
                        : bytes,
                    'isfolder': false,
                  },
                ],
        });
      case '/stat':
        statPath = request.url.queryParameters['path'];
        await afterStat?.call();
        return jsonResponse({
          'result': 0,
          'metadata': {'fileid': 9, 'size': statLength, 'isfolder': false},
        });
      case '/getfilelink':
        linkFileId = request.url.queryParameters['fileid'];
        return jsonResponse({
          'result': 0,
          'hosts': ['download.example.invalid'],
          'path': '/download',
        });
      case '/download':
        downloadRequest = request;
        Stream<List<int>> response() async* {
          downloadPartsRead++;
          yield Uint8List.fromList([1, 2]);
          downloadPartsRead++;
          yield Uint8List.fromList([3, 4]);
        }
        return http.StreamedResponse(response(), 200, contentLength: 4);
      default:
        throw StateError('Unexpected request: ${request.url.path}');
    }
  }

  @override
  void close() {
    closedClients++;
  }
}
