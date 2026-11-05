import 'dart:typed_data';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class _LegacyClient extends CloudStorageClient {
  int byteDownloads = 0;
  final uploads = <List<int>>[];
  String account = 'original';
  @override
  bool get isAuthenticated => true;
  @override
  String get userId => account;
  @override
  String? get bucketId => null;
  @override
  Future<void> uploadFile(
    List<int> fileData,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    uploads.add(fileData);
  }

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    byteDownloads++;
    throw StateError('Whole-file byte downloads must not be used.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StreamingClient extends _LegacyClient {
  _StreamingClient(this.source);
  Stream<List<int>> Function() source;
  @override
  Stream<List<int>> downloadStream(
    String remotePath, {
    Function(int, int)? onProgress,
  }) => source();
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'files': [
      {'name': 'source.txt', 'size': 1},
    ],
  };
}

void main() {
  test('legacy download rejects before calling the whole-file API', () async {
    final client = _LegacyClient();
    await expectLater(
      client.downloadStream('/source').drain<void>(),
      throwsUnsupportedError,
    );
    expect(client.byteDownloads, 0);
  });

  for (final declared in [-1, CloudStorageClient.maxBufferedUploadBytes + 1]) {
    test(
      'unsupported declaration $declared does not consume the source',
      () async {
        var consumed = false;
        Stream<List<int>> source() async* {
          consumed = true;
          yield [1];
        }

        final client = _LegacyClient();
        await expectLater(
          client.uploadStream(source(), declared, 'target', '/'),
          throwsUnsupportedError,
        );
        expect(consumed, isFalse);
        expect(client.uploads, isEmpty);
      },
    );
  }

  for (final declared in [0, 2, 4]) {
    test(
      'legacy upload rejects actual length differing from $declared',
      () async {
        final client = _LegacyClient();
        await expectLater(
          client.uploadStream(
            Stream.fromIterable([
              [1],
              [2, 3],
            ]),
            declared,
            'target',
            '/',
          ),
          throwsStateError,
        );
        expect(client.uploads, isEmpty);
      },
    );
  }

  test(
    'copy compatibility path uses streams and an exact private spool',
    () async {
      final client = _StreamingClient(
        () => Stream.fromIterable([
          [1, 2],
          [3],
        ]),
      );
      await client.copyPath('/source.bin', '/target');
      expect(client.uploads.single, [1, 2, 3]);
      expect(client.byteDownloads, 0);
    },
  );

  test('account changes while spooling cannot reach the upload API', () async {
    late _StreamingClient client;
    Stream<List<int>> source() async* {
      yield [1];
      client.account = 'other';
      yield [2];
    }

    client = _StreamingClient(source);
    await expectLater(client.copyPath('/source', '/target'), throwsStateError);
    expect(client.uploads, isEmpty);
  });

  test(
    'fallback text search cancels an unexpectedly growing source at its cap',
    () async {
      var consumed = 0;
      var closed = false;
      Stream<List<int>> source() async* {
        try {
          for (var i = 0; i < 10; i++) {
            consumed++;
            yield Uint8List(512 * 1024)..fillRange(0, 512 * 1024, 65);
          }
        } finally {
          closed = true;
        }
      }

      final client = _StreamingClient(source);
      expect(await client.fullTextSearch('AAA', '/'), isEmpty);
      expect(consumed, 3);
      expect(closed, isTrue);
      expect(client.byteDownloads, 0);
    },
  );
}
