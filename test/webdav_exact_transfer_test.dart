import 'dart:async';
import 'dart:typed_data';

import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

class _Transport implements dio.HttpClientAdapter {
  _Transport(this.respond);
  final Future<dio.ResponseBody> Function(dio.RequestOptions) respond;
  @override
  Future<dio.ResponseBody> fetch(
    dio.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

Future<WebDavClientAdapter> _adapter(
  Future<dio.ResponseBody> Function(dio.RequestOptions) respond,
) async {
  final config = WebDavConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'host': 'https://dav.example.test/base',
    'username': 'fixture',
    'password': 'fixture',
  });
  return WebDavClientAdapter(
    config: config,
    clientFactory: (host, user, password) {
      final client = webdav.newClient(host, user: user, password: password);
      client.c.httpClientAdapter = _Transport(respond);
      return client;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final move in [false, true]) {
    test(
      'WebDAV ${move ? 'MOVE' : 'COPY'} encodes exact paths and prohibits replacement',
      () async {
        dio.RequestOptions? observed;
        final adapter = await _adapter((request) async {
          observed = request;
          return dio.ResponseBody.fromString('', 201);
        });
        addTearDown(adapter.logout);
        final result = move
            ? await adapter.moveToExact(
                '/café #1%20.bin',
                '/folder/renamed #1%20.bin',
              )
            : await adapter.copyToExact(
                '/café #1%20.bin',
                '/folder/renamed #1%20.bin',
              );
        expect(observed!.method, move ? 'MOVE' : 'COPY');
        expect(
          observed!.uri.toString(),
          'https://dav.example.test/base/caf%C3%A9%20%231%2520.bin',
        );
        expect(observed!.uri.fragment, isEmpty);
        expect(
          observed!.headers['destination'],
          'https://dav.example.test/base/folder/renamed%20%231%2520.bin',
        );
        expect(observed!.headers['overwrite'], 'F');
        expect(result.path, '/folder/renamed #1%20.bin');
      },
    );
  }

  test('Multi-Status is not accepted as a completed native move', () async {
    var requests = 0;
    final adapter = await _adapter((request) async {
      requests++;
      return dio.ResponseBody.fromString(
        '<d:multistatus xmlns:d="DAV:"><d:response><d:href>/b</d:href>'
        '<d:status>HTTP/1.1 507 Insufficient Storage</d:status></d:response></d:multistatus>',
        207,
      );
    });
    addTearDown(adapter.logout);
    await expectLater(adapter.moveToExact('/a', '/b'), throwsStateError);
    expect(requests, 1);
  });

  test('native transfer cannot redirect its credentials or destination to another host', () async {
    var requests = 0;
    final adapter = await _adapter((request) async {
      requests++;
      expect(request.uri.host, 'dav.example.test');
      return dio.ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://other.example.test/b'],
        },
      );
    });
    addTearDown(adapter.logout);
    await expectLater(adapter.copyToExact('/a', '/b'), throwsStateError);
    expect(requests, 1);
  });

  test(
    'a basic authentication challenge retains exact reviewed paths',
    () async {
      var requests = 0;
      final adapter = await _adapter((request) async {
        requests++;
        expect(request.uri.path, '/base/a');
        if (requests == 1) {
          return dio.ResponseBody.fromString(
            '',
            401,
            headers: {
              'www-authenticate': ['Basic realm="fixture"'],
            },
          );
        }
        expect(request.headers['authorization'], startsWith('Basic '));
        return dio.ResponseBody.fromString('', 204);
      });
      addTearDown(adapter.logout);
      await adapter.moveToExact('/a', '/b');
      expect(requests, 2);
    },
  );
}
