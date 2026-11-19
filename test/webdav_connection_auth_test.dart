import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

const _listing = '''<d:multistatus xmlns:d="DAV:">
<d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/dav/file.txt</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>4</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>''';

class _Transport implements dio.HttpClientAdapter {
  _Transport(this.respond);
  final dio.ResponseBody Function(dio.RequestOptions) respond;
  bool closed = false;
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
  void close({bool force = false}) => closed = true;
}

void main() {
  test('a Digest challenge still replaces initial Basic authentication and survives login', () async {
    var calls = 0;
    var clients = 0;
    final config = WebDavConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    final adapter = WebDavClientAdapter(
      config: config,
      clientFactory: (url, user, password) {
        clients++;
        final client = webdav.newClient(url, user: user, password: password);
        client.c.httpClientAdapter = _Transport((request) {
          final auth =
              request.headers.entries
                      .where(
                        (entry) => entry.key.toLowerCase() == 'authorization',
                      )
                      .single
                      .value
                  as String;
          if (calls++ == 0) {
            expect(auth, startsWith('Basic '));
            return dio.ResponseBody.fromString(
              '',
              401,
              headers: {
                'www-authenticate': [
                  'Digest realm="fixture", nonce="test-nonce", qop="auth"',
                ],
              },
            );
          }
          expect(auth, startsWith('Digest '));
          expect(auth, contains('username="person"'));
          return dio.ResponseBody.fromString(
            _listing,
            207,
            headers: {
              'content-type': ['application/xml'],
            },
          );
        });
        return client;
      },
    );
    await adapter.login('person@https://dav.example/dav/', 'fixture');
    expect((await adapter.listPath('/'))['files'], hasLength(1));
    expect(clients, 1);
    expect(calls, 3);
    await adapter.logout();
  });

  test(
    'byte downloads and uploads do not require an OPTIONS 200 probe',
    () async {
      final methods = <String>[];
      final config = WebDavConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      );
      final adapter = WebDavClientAdapter(
        config: config,
        clientFactory: (url, user, password) {
          final client = webdav.newClient(url, user: user, password: password);
          client.c.httpClientAdapter = _Transport((request) {
            methods.add(request.method);
            if (request.method == 'PROPFIND') {
              return dio.ResponseBody.fromString(
                _listing,
                207,
                headers: {
                  'content-type': ['application/xml'],
                },
              );
            }
            expect(
              request.uri.toString(),
              'https://dav.example/dav/caf%C3%A9%20%231%2520.txt',
            );
            if (request.method == 'PUT') {
              return dio.ResponseBody.fromString('', 201);
            }
            expect(request.method, 'GET');
            return dio.ResponseBody.fromString('exact bytes', 200);
          });
          return client;
        },
      );
      await adapter.login('person@https://dav.example/dav/', 'fixture');
      await adapter.uploadFile(
        utf8.encode('exact bytes'),
        'café #1%20.txt',
        '/',
      );
      expect(
        utf8.decode(await adapter.downloadFileBytes('/café #1%20.txt')),
        'exact bytes',
      );
      expect(methods, ['PROPFIND', 'PUT', 'GET']);
      await adapter.logout();
    },
  );

  test('browser-hidden authentication challenge is unnecessary and verified client is retained', () async {
    final config = WebDavConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    var clients = 0;
    var calls = 0;
    final transport = _Transport((request) {
      calls++;
      final header = request.headers.entries
          .where((entry) => entry.key.toLowerCase() == 'authorization')
          .single
          .value;
      expect(
        header,
        'Basic ${base64Encode(utf8.encode('person@example.test:fixture'))}',
      );
      expect(request.uri.origin, 'https://dav.example');
      return dio.ResponseBody.fromString(
        _listing,
        207,
        headers: {
          'content-type': ['application/xml'],
        },
      );
    });
    final adapter = WebDavClientAdapter(
      config: config,
      clientFactory: (url, user, password) {
        clients++;
        final client = webdav.newClient(url, user: user, password: password);
        client.c.httpClientAdapter = transport;
        return client;
      },
    );
    await adapter.login(
      'person@example.test@https://dav.example/dav/',
      'fixture',
    );
    expect((await adapter.listPath('/'))['files'], hasLength(1));
    expect((await adapter.listPath('/'))['files'], hasLength(1));
    expect(clients, 1);
    expect(calls, 3);
    expect(transport.closed, isFalse);
    await adapter.logout();
    expect(transport.closed, isTrue);
  });

  test('login cannot follow a redirect with supplied credentials', () async {
    final config = WebDavConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    var calls = 0;
    final transport = _Transport((request) {
      calls++;
      expect(request.uri.host, 'dav.example');
      return dio.ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://other.example/dav/'],
        },
      );
    });
    final adapter = WebDavClientAdapter(
      config: config,
      clientFactory: (url, user, password) {
        final client = webdav.newClient(url, user: user, password: password);
        client.c.httpClientAdapter = transport;
        return client;
      },
    );
    await expectLater(
      adapter.login('person@https://dav.example/dav/', 'fixture'),
      throwsException,
    );
    expect(calls, 1);
    expect(transport.closed, isTrue);
    expect(adapter.isAuthenticated, isFalse);
    expect(await config.readCredentials(), isNull);
  });
}
