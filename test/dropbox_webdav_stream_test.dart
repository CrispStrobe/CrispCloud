import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_config_service.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Future<DropboxClientAdapter> dropbox() async {
  final config = DropboxConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'app_key': 'fixture-key',
    'refresh_token': 'fixture-refresh',
    'email': 'fixture@example.test',
  });
  final adapter = DropboxClientAdapter(config: config);
  expect(await adapter.restoreCredentials(), isTrue);
  return adapter;
}

http.Response? setupDropbox(http.Request request) {
  if (request.url.path == '/oauth2/token') {
    return jsonResponse({'access_token': 'fixture-access', 'expires_in': 3600});
  }
  if (request.url.path.endsWith('/start')) {
    return jsonResponse({'session_id': 'fixture-session'});
  }
  return null;
}

class _StreamDio extends Fake implements webdav.WdDio {
  final sizes = <int>[];
  final closeRequests = <bool>[];
  int uploaded = 0;
  String? destination;
  Future<void> Function()? firstPart;
  @override
  void close({bool force = false}) => closeRequests.add(force);

  @override
  Future<void> wdWriteWithStream(
    webdav.Client self,
    String path,
    Stream<List<int>> data,
    int length, {
    void Function(int, int)? onProgress,
    dynamic cancelToken,
  }) async {
    destination = path;
    await for (final chunk in data) {
      sizes.add(chunk.length);
      if (sizes.length == 1) await firstPart?.call();
      uploaded += chunk.length;
      onProgress?.call(uploaded, length);
    }
    expect(uploaded, length);
  }
}

class _DavClient extends Fake implements webdav.Client {
  _DavClient(this.c);
  @override
  final _StreamDio c;
  @override
  void setHeaders(Map<String, dynamic> headers) {}
}

Future<WebDavClientAdapter> _dav(_StreamDio transport) async {
  final config = WebDavConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'username': 'fixture',
    'password': 'fixture',
    'host': 'https://dav.example.test/root',
  });
  return WebDavClientAdapter(
    config: config,
    clientFactory: (_, _, _) => _DavClient(transport),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Dropbox session requests stay bounded, sequential and preserve Unicode header names', () async {
    const partSize = 8 * 1024 * 1024;
    const filename = 'café #1 😀.bin';
    const length = partSize + 3;
    var readTail = false;
    var appended = false;
    var finished = false;
    Stream<List<int>> source() async* {
      yield Uint8List(partSize);
      readTail = true;
      yield [1, 2, 3];
    }

    await http.runWithClient(
      () async {
        final adapter = await dropbox();
        await adapter.uploadStream(source(), length, filename, '/');
      },
      () => MockClient((request) async {
        final setup = setupDropbox(request);
        if (setup != null) return setup;
        expect(
          request.headers['dropbox-api-arg']!.codeUnits.every(
            (unit) => unit < 127,
          ),
          isTrue,
        );
        final arg = jsonDecode(request.headers['dropbox-api-arg']!) as Map;
        final cursor = arg['cursor'] as Map;
        expect(cursor['session_id'], 'fixture-session');
        if (request.url.path.endsWith('/append_v2')) {
          expect(readTail, isFalse);
          expect(cursor['offset'], 0);
          expect(request.bodyBytes.length, partSize);
          appended = true;
          return http.Response('', 200);
        }
        expect(request.url.path, endsWith('/finish'));
        expect(appended, isTrue);
        expect(cursor['offset'], partSize);
        expect((arg['commit'] as Map)['path'], '/$filename');
        expect((arg['commit'] as Map)['autorename'], isFalse);
        expect(request.bodyBytes, [1, 2, 3]);
        finished = true;
        return jsonResponse({
          'id': 'file-id',
          'size': length,
          'path_display': '/$filename',
        });
      }),
    );
    expect(finished, isTrue);
  });

  for (final bytes in [
    [1],
    [1, 2, 3],
  ]) {
    test(
      'Dropbox rejects incorrect source length ${bytes.length} before commit',
      () async {
        var finished = false;
        await http.runWithClient(
          () async {
            final adapter = await dropbox();
            await expectLater(
              adapter.uploadStream(Stream.value(bytes), 2, 'x.bin', '/'),
              throwsStateError,
            );
          },
          () => MockClient((request) async {
            final setup = setupDropbox(request);
            if (setup != null) return setup;
            finished = request.url.path.endsWith('/finish');
            return jsonResponse({
              'id': 'file-id',
              'size': 2,
              'path_display': '/x.bin',
            });
          }),
        );
        expect(finished, isFalse);
      },
    );
  }

  test('Dropbox checks the completed path and size', () async {
    await http.runWithClient(
      () async {
        final adapter = await dropbox();
        await expectLater(
          adapter.uploadStream(Stream.value([1, 2]), 2, 'x.bin', '/'),
          throwsStateError,
        );
      },
      () => MockClient(
        (request) async =>
            setupDropbox(request) ??
            jsonResponse({
              'id': 'file-id',
              'size': 2,
              'path_display': '/different.bin',
            }),
      ),
    );
  });

  test(
    'Dropbox zero-byte uploads validate EOF and finish an empty session',
    () async {
      var finished = 0;
      await http.runWithClient(
        () async {
          final adapter = await dropbox();
          await adapter.uploadStream(const Stream.empty(), 0, 'empty', '/');
        },
        () => MockClient((request) async {
          final setup = setupDropbox(request);
          if (setup != null) return setup;
          expect(request.bodyBytes, isEmpty);
          finished++;
          return jsonResponse({
            'id': 'file-id',
            'size': 0,
            'path_display': '/empty',
          });
        }),
      );
      expect(finished, 1);
    },
  );

  test(
    'Dropbox downloads yield before EOF and close on cancellation',
    () async {
      var closed = false;
      Stream<List<int>> source() async* {
        try {
          yield [1, 2];
          fail('Cancellation must stop before consuming the next body chunk.');
        } finally {
          closed = true;
        }
      }

      await http.runWithClient(
        () async {
          final adapter = await dropbox();
          expect(await adapter.downloadStream('/café.bin').first, [1, 2]);
          expect(closed, isTrue);
        },
        () => MockClient.streaming((request, body) async {
          await body.drain<void>();
          if (request.url.path == '/oauth2/token') {
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'access_token': 'fixture-access',
                    'expires_in': 3600,
                  }),
                ),
              ),
              200,
            );
          }
          expect(request.method, 'GET');
          expect(
            jsonDecode(request.headers['dropbox-api-arg']!)['path'],
            '/café.bin',
          );
          return http.StreamedResponse(
            source(),
            200,
            headers: {
              'dropbox-api-result': jsonEncode({'size': 4}),
            },
          );
        }),
      );
    },
  );

  test(
    'Dropbox rejects truncated downloaded content against result metadata',
    () async {
      await http.runWithClient(
        () async {
          final adapter = await dropbox();
          await expectLater(
            adapter.downloadStream('/x.bin').drain<void>(),
            throwsStateError,
          );
        },
        () => MockClient(
          (request) async =>
              setupDropbox(request) ??
              http.Response.bytes(
                [1],
                200,
                headers: {
                  'dropbox-api-result': jsonEncode({'size': 2}),
                },
              ),
        ),
      );
    },
  );

  test(
    'WebDAV streams bounded parts and preserves sink backpressure',
    () async {
      final transport = _StreamDio();
      final adapter = await _dav(transport);
      addTearDown(() async {
        await adapter.logout();
        expect(transport.closeRequests, [true]);
        await adapter.logout();
        expect(transport.closeRequests, [true]);
      });
      var readTail = false;
      transport.firstPart = () async => expect(readTail, isFalse);
      Stream<List<int>> source() async* {
        yield Uint8List(64 * 1024);
        readTail = true;
        yield Uint8List(64 * 1024 + 1);
      }

      await adapter.uploadStream(
        source(),
        128 * 1024 + 1,
        'café #1%20.bin',
        '/folder',
      );
      expect(transport.sizes, [64 * 1024, 64 * 1024, 1]);
      expect(
        Uri.decodeComponent(transport.destination!),
        '/folder/café #1%20.bin',
      );
      expect(Uri.parse(transport.destination!).fragment, isEmpty);
      expect(adapter.transferCapabilities.boundedUpload, isTrue);
    },
  );

  test(
    'WebDAV validates the final bytes before releasing them to the wire',
    () async {
      final transport = _StreamDio();
      final adapter = await _dav(transport);
      addTearDown(() async {
        await adapter.logout();
        expect(transport.closeRequests, [true]);
        await adapter.logout();
        expect(transport.closeRequests, [true]);
      });
      await expectLater(
        adapter.uploadStream(Stream.value([1, 2, 3]), 2, 'x.bin', '/'),
        throwsStateError,
      );
      expect(transport.uploaded, 0);
    },
  );
}
