import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Transport extends http.BaseClient {
  _Transport(this.handle);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handle;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handle(request);
  @override
  void close() => closed = true;
}

Future<NextcloudClientAdapter> adapter() async {
  final config = NextcloudConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'username': 'fixture',
    'password': 'fixture',
    'serverUrl': 'https://cloud.example.test/base',
  });
  return NextcloudClientAdapter(config: config);
}

http.StreamedResponse response(
  int status, [
  Stream<List<int>>? body,
  Map<String, String> headers = const {},
]) => http.StreamedResponse(
  body ?? const Stream.empty(),
  status,
  headers: headers,
  contentLength: int.tryParse(headers['content-length'] ?? ''),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Nextcloud PUT consumes bounded chunks with exact names and no redirects',
    () async {
      final client = await adapter();
      final sizes = <int>[];
      var total = 0;
      final transport = _Transport((request) async {
        expect(request.method, 'PUT');
        expect(
          request.url.toString(),
          'https://cloud.example.test/base/remote.php/dav/files/fixture/Folder/caf%C3%A9%20%231%2520.bin',
        );
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], startsWith('Basic '));
        expect(request.contentLength, 130001);
        await for (final bytes in request.finalize()) {
          sizes.add(bytes.length);
          total += bytes.length;
        }
        return response(201);
      });
      await http.runWithClient(
        () => client.uploadStream(
          Stream.value(Uint8List(130001)),
          130001,
          'café #1%20.bin',
          '/Folder',
        ),
        () => transport,
      );
      expect(total, 130001);
      expect(sizes.every((size) => size <= 65536), isTrue);
      expect(transport.closed, isTrue);
      expect(client.transferCapabilities.boundedUpload, isTrue);
      expect(client.transferCapabilities.boundedDownload, isTrue);
    },
  );

  for (final bytes in [
    const [1],
    const [1, 2, 3],
  ]) {
    test(
      'Nextcloud rejects a source with ${bytes.length} bytes when two were declared',
      () async {
        final client = await adapter();
        var completed = false;
        final transport = _Transport((request) async {
          await request.finalize().drain<void>();
          completed = true;
          return response(201);
        });
        await http.runWithClient(
          () async => expectLater(
            client.uploadStream(Stream.value(bytes), 2, 'file', '/'),
            throwsStateError,
          ),
          () => transport,
        );
        expect(completed, isFalse);
        expect(transport.closed, isTrue);
      },
    );
  }

  test(
    'Nextcloud never reports a redirected or partial upload as complete',
    () async {
      for (final status in [207, 302]) {
        final client = await adapter();
        await http.runWithClient(
          () async => expectLater(
            client.uploadStream(Stream.value([1]), 1, 'file', '/'),
            throwsStateError,
          ),
          () => _Transport((request) async {
            await request.finalize().drain<void>();
            return response(status);
          }),
        );
      }
    },
  );

  test('Nextcloud account change stops remaining upload chunks', () async {
    final client = await adapter();
    Stream<List<int>> source() async* {
      yield Uint8List(65536);
      await client.logout();
      yield [1];
    }

    final transport = _Transport((request) async {
      await request.finalize().drain<void>();
      return response(201);
    });
    await http.runWithClient(
      () async => expectLater(
        client.uploadStream(source(), 65537, 'file', '/'),
        throwsStateError,
      ),
      () => transport,
    );
    expect(transport.closed, isTrue);
  });

  test('Nextcloud download yields early, closes on cancellation, and keeps auth on original endpoint', () async {
    final client = await adapter();
    final body = StreamController<List<int>>();
    final transport = _Transport((request) async {
      expect(request.method, 'GET');
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], startsWith('Basic '));
      return response(200, body.stream, {'content-length': '6'});
    });
    await http.runWithClient(() async {
      final iterator = StreamIterator(client.downloadStream('/file'));
      final next = iterator.moveNext();
      body.add([1, 2, 3]);
      expect(await next, isTrue);
      expect(iterator.current, [1, 2, 3]);
      await iterator.cancel();
    }, () => transport);
    await body.close();
    expect(transport.closed, isTrue);
  });

  test(
    'Nextcloud detects truncated downloads and oversized response metadata',
    () async {
      final client = await adapter();
      await http.runWithClient(
        () async => expectLater(
          client.downloadStream('/file').drain<void>(),
          throwsStateError,
        ),
        () => _Transport(
          (_) async =>
              response(200, Stream.value([1]), {'content-length': '2'}),
        ),
      );
      await http.runWithClient(
        () async => expectLater(
          client.uploadStream(Stream.value([1]), 1, 'file', '/'),
          throwsStateError,
        ),
        () => _Transport((request) async {
          await request.finalize().drain<void>();
          return response(201, Stream.value(Uint8List(256 * 1024 + 1)));
        }),
      );
    },
  );
}
