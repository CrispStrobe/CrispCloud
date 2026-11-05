import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/b2_client_adapter.dart';
import 'package:crisp_cloud/services/b2_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _partSize = 10 * 1024 * 1024;

void main() {
  late B2ClientAdapter adapter;
  late B2ConfigService config;
  late _B2Fixture fixture;
  setUp(() async {
    config = B2ConfigService(secureStorage: InMemorySecureStorage());
    await config.saveCredentials(
      keyId: 'key',
      applicationKey: 'synthetic-key',
      bucketId: 'bucket-id',
      bucketName: 'chosen-bucket',
    );
    adapter = B2ClientAdapter(config: config);
    fixture = _B2Fixture();
  });
  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(() async {
        await adapter.login('key', 'synthetic-key');
        await body();
      }, () => fixture);

  Stream<List<int>> largeSource({
    List<int> tail = const [7, 8, 9],
    void Function()? afterFirstPart,
  }) async* {
    for (var i = 0; i < _partSize ~/ 65536; i++) {
      yield Uint8List(65536)..fillRange(0, 65536, i % 256);
    }
    afterFirstPart?.call();
    yield tail;
  }

  test(
    'small and empty uploads validate SHA1 and exact completed identity',
    () => run(() async {
      final progress = <(int, int)>[];
      await adapter.uploadStream(
        Stream.value([1, 2, 3]),
        3,
        'file #1.bin',
        '/folder/',
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(fixture.smallUploads.single.$1, 'folder/file #1.bin');
      expect(fixture.smallUploads.single.$2, 3);
      expect(progress, [(3, 3)]);
      await adapter.uploadStream(const Stream.empty(), 0, 'empty', '/');
      expect(fixture.smallUploads.last, (
        'empty',
        0,
        sha1.convert([]).toString(),
      ));
      expect(adapter.transferCapabilities.boundedUpload, isTrue);
      expect(adapter.transferCapabilities.noReplaceCopy, isFalse);
    }),
  );

  test(
    'large files upload one spooled part at a time with bounded HTTP chunks',
    () => run(() async {
      var sawConfirmedPart = false;
      final progress = <(int, int)>[];
      await adapter.uploadStream(
        largeSource(
          afterFirstPart: () {
            expect(fixture.parts.keys, [1]);
            sawConfirmedPart = true;
          },
        ),
        _partSize + 3,
        'large.bin',
        '/folder',
        onProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(sawConfirmedPart, isTrue);
      expect(fixture.parts.values.map((part) => part.$1), [_partSize, 3]);
      expect(fixture.maxUploadChunk, lessThanOrEqualTo(65536));
      expect(fixture.finished, isTrue);
      expect(
        fixture.finishHashes,
        fixture.parts.values.map((part) => part.$2).toList(),
      );
      expect(progress, [
        (_partSize, _partSize + 3),
        (_partSize + 3, _partSize + 3),
      ]);
      expect(fixture.cancelled, isEmpty);
    }),
  );

  for (final size in [0, 2, 4]) {
    test(
      'small declared length $size mismatch never starts an upload',
      () => run(() async {
        await expectLater(
          adapter.uploadStream(Stream.value([1, 2, 3]), size, 'file', '/'),
          throwsStateError,
        );
        expect(fixture.uploadUrlRequests, 0);
        expect(fixture.smallUploads, isEmpty);
      }),
    );
  }

  for (final tail in [
    <int>[],
    [1, 2],
  ]) {
    test(
      'wrong last-part length ${tail.length} cancels only this unfinished upload',
      () => run(() async {
        await expectLater(
          adapter.uploadStream(
            largeSource(tail: tail),
            _partSize + 1,
            'large.bin',
            '/',
          ),
          throwsStateError,
        );
        expect(fixture.finished, isFalse);
        expect(fixture.cancelled, ['new-upload']);
        expect(fixture.parts.keys, [1]);
      }),
    );
  }

  test(
    'wrong part checksum prevents finish and removes the private spool',
    () => run(() async {
      final temp = await Directory.systemTemp.createTemp('b2-spool-test-');
      addTearDown(() => temp.delete(recursive: true));
      fixture.wrongPartChecksum = true;
      await IOOverrides.runZoned(() async {
        await expectLater(
          adapter.uploadStream(largeSource(), _partSize + 3, 'large', '/'),
          throwsStateError,
        );
        expect(await temp.list().toList(), isEmpty);
      }, getSystemTempDirectory: () => temp);
      expect(fixture.cancelled, ['new-upload']);
      expect(fixture.finished, isFalse);
    }),
  );

  test(
    'a definite temporary upload failure obtains a new part URL and replays its spool',
    () => run(() async {
      fixture.rejectFirstPart = true;
      await adapter.uploadStream(largeSource(), _partSize + 3, 'large', '/');
      expect(fixture.partAttempts, [1, 1, 2]);
      expect(fixture.partUrlRequests, 3);
      expect(fixture.finished, isTrue);
      expect(fixture.requestTokens.take(2).toSet().length, 2);
    }),
  );

  test(
    'lost finish acknowledgement reconciles the exact completed file ID',
    () => run(() async {
      fixture.loseFinishReply = true;
      await adapter.uploadStream(largeSource(), _partSize + 3, 'large', '/');
      expect(fixture.fileInfoRequests, ['new-upload']);
      expect(fixture.finished, isTrue);
      expect(fixture.cancelled, isEmpty);
    }),
  );

  test(
    'wrong completed identity is not treated as a successful upload',
    () => run(() async {
      fixture.wrongCompletedName = true;
      await expectLater(
        adapter.uploadStream(Stream.value([1]), 1, 'file', '/'),
        throwsStateError,
      );
    }),
  );

  test(
    'an account change prevents later parts and cleanup against another account',
    () => run(() async {
      fixture.afterFirstPart = adapter.logout;
      await expectLater(
        adapter.uploadStream(largeSource(), _partSize + 3, 'large', '/'),
        throwsStateError,
      );
      expect(fixture.parts.keys, [1]);
      expect(fixture.cancelled, isEmpty);
      expect(fixture.finished, isFalse);
    }),
  );

  test(
    'download URL preserves names, streams response chunks and closes on cancellation',
    () => run(() async {
      expect(
        await adapter.downloadStream('/folder/a #1.bin ').take(1).toList(),
        [
          [1, 2],
        ],
      );
      expect(fixture.downloadRequest!.url.pathSegments, [
        'file',
        'chosen-bucket',
        'folder',
        'a #1.bin ',
      ]);
      expect(
        fixture.downloadRequest!.headers['authorization'],
        'synthetic-token',
      );
      expect(fixture.downloadReads, 1);
      expect(fixture.closedClients, greaterThan(0));
    }),
  );

  test(
    'truncated downloads fail their content length check',
    () => run(() async {
      fixture.downloadLength = 5;
      await expectLater(
        adapter.downloadStream('/file').toList(),
        throwsStateError,
      );
    }),
  );
}

class _HashSink implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest value) {
    digest = value;
  }

  @override
  void close() {}
}

class _B2Fixture extends http.BaseClient {
  final parts = <int, (int, String)>{};
  final smallUploads = <(String, int, String)>[];
  final cancelled = <String>[];
  final partAttempts = <int>[];
  final requestTokens = <String>[];
  final fileInfoRequests = <String>[];
  List<String> finishHashes = [];
  int uploadUrlRequests = 0;
  int partUrlRequests = 0;
  int maxUploadChunk = 0;
  int closedClients = 0;
  int downloadLength = 4;
  int downloadReads = 0;
  bool rejectFirstPart = false;
  bool wrongPartChecksum = false;
  bool loseFinishReply = false;
  bool wrongCompletedName = false;
  bool finished = false;
  String? uploadName;
  http.BaseRequest? downloadRequest;
  Future<void> Function()? afterFirstPart;

  http.StreamedResponse response(
    Map<String, dynamic> body, {
    int status = 200,
  }) => http.StreamedResponse(
    Stream.value(utf8.encode(json.encode(body))),
    status,
    headers: {'content-type': 'application/json', 'retry-after': '0'},
  );

  Map<String, dynamic> completedFile(
    String name,
    int bytes,
    String checksum, {
    String id = 'new-upload',
  }) => {
    'fileId': id,
    'bucketId': 'bucket-id',
    'action': 'upload',
    'fileName': wrongCompletedName ? 'another-file' : name,
    'contentLength': bytes,
    'contentSha1': checksum,
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/b2_authorize_account')) {
      return response({
        'authorizationToken': 'synthetic-token',
        'accountId': 'account-id',
        'apiUrl': 'https://api.example.invalid',
        'downloadUrl': 'https://download.example.invalid',
      });
    }
    if (request.url.path.startsWith('/file/')) {
      downloadRequest = request;
      Stream<List<int>> data() async* {
        downloadReads++;
        yield [1, 2];
        downloadReads++;
        yield [3, 4];
      }

      return http.StreamedResponse(data(), 200, contentLength: downloadLength);
    }
    if (request.url.path.startsWith('/upload/')) {
      expect(request.followRedirects, isFalse);
      final digest = _HashSink();
      final hash = sha1.startChunkedConversion(digest);
      var bytes = 0;
      await for (final chunk in request.finalize()) {
        maxUploadChunk = chunk.length > maxUploadChunk
            ? chunk.length
            : maxUploadChunk;
        bytes += chunk.length;
        hash.add(chunk);
      }
      hash.close();
      final checksum = digest.digest!.toString();
      expect(request.contentLength, bytes);
      expect(request.headers['x-bz-content-sha1'], checksum);
      final number = int.tryParse(request.headers['x-bz-part-number'] ?? '');
      if (number == null) {
        final name = Uri.decodeComponent(request.headers['x-bz-file-name']!);
        smallUploads.add((name, bytes, checksum));
        return response(
          completedFile(name, bytes, checksum, id: 'small-upload'),
        );
      }
      partAttempts.add(number);
      requestTokens.add(request.headers['authorization']!);
      if (rejectFirstPart && partAttempts.length == 1) {
        return response({'code': 'busy'}, status: 503);
      }
      parts[number] = (bytes, checksum);
      if (number == 1) await afterFirstPart?.call();
      return response({
        'fileId': 'new-upload',
        'partNumber': number,
        'contentLength': bytes,
        'contentSha1': wrongPartChecksum ? 'wrong' : checksum,
      });
    }
    final data = json.decode(
      utf8.decode(await request.finalize().toBytes()),
    ) as Map<String, dynamic>;
    switch (request.url.pathSegments.last) {
      case 'b2_start_large_file':
        uploadName = data['fileName'] as String;
        return response({
          'fileId': 'new-upload',
          'fileName': uploadName,
          'bucketId': data['bucketId'],
          'action': 'start',
        });
      case 'b2_get_upload_url':
        uploadUrlRequests++;
        return response({
          'uploadUrl': 'https://upload.example.invalid/upload/small',
          'authorizationToken': 'small-token',
          'bucketId': 'bucket-id',
        });
      case 'b2_get_upload_part_url':
        partUrlRequests++;
        return response({
          'uploadUrl':
              'https://upload.example.invalid/upload/part$partUrlRequests',
          'authorizationToken': 'part-token$partUrlRequests',
          'fileId': 'new-upload',
        });
      case 'b2_finish_large_file':
        finishHashes = (data['partSha1Array'] as List).cast<String>();
        finished = true;
        if (loseFinishReply) {
          throw http.ClientException('lost reply', request.url);
        }
        return response(
          completedFile(
            uploadName!,
            parts.values.fold(0, (sum, part) => sum + part.$1),
            'none',
          ),
        );
      case 'b2_get_file_info':
        fileInfoRequests.add(data['fileId'] as String);
        return response(
          completedFile(
            uploadName!,
            parts.values.fold(0, (sum, part) => sum + part.$1),
            'none',
          ),
        );
      case 'b2_cancel_large_file':
        cancelled.add(data['fileId'] as String);
        return response({'fileId': 'new-upload'});
      default:
        throw StateError('Unexpected request ${request.url.path}');
    }
  }

  @override
  void close() {
    closedClients++;
  }
}
