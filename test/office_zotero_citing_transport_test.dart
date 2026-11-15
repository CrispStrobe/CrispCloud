import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/services/office_zotero_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart';

class _Client extends http.BaseClient {
  _Client(this.handle);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handle;
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handle(request);

  @override
  void close() => closeCount++;
}

const _headers = {
  'Content-Type': 'application/json',
  'Zotero-Allowed-Request': '1',
};

ZoteroHttpRequest _request({
  String uri = 'http://localhost:23119/connector/document/execCommand',
  String method = 'POST',
  String? body = '{"command":"refresh","documentID":"test-document"}',
  Map<String, String> headers = _headers,
  Duration? timeout,
}) => ZoteroHttpRequest(
  uri: Uri.parse(uri),
  method: method,
  body: body,
  headers: headers,
  timeout: timeout,
);

http.StreamedResponse _ok() => http.StreamedResponse(
  Stream.value(utf8.encode('{"command":"Document.complete","arguments":[]}')),
  200,
);

void main() {
  for (final route in ['execCommand', 'respond']) {
    test(
      'citing $route sends only local UTF-8 JSON without redirects',
      () async {
        var localClients = 0;
        var cloudClients = 0;
        final payload = jsonEncode({'text': 'Köln العربية', 'ok': true});
        final client = _Client((outbound) async {
          expect(outbound.method, 'POST');
          expect(outbound.url.path, '/connector/document/$route');
          expect(outbound.headers, _headers);
          expect(outbound.followRedirects, isFalse);
          expect(outbound.maxRedirects, 0);
          expect(utf8.decode((outbound as http.Request).bodyBytes), payload);
          return _ok();
        });
        final transport = OfficeZoteroTransport(
          createClient: () {
            cloudClients++;
            throw StateError('Do not send document content to the proxy.');
          },
          createLocalClient: () {
            localClients++;
            return client;
          },
        );
        addTearDown(transport.dispose);
        final response = await transport.send(
          _request(
            uri: 'http://localhost:23119/connector/document/$route',
            body: payload,
          ),
        );
        expect(response.statusCode, 200);
        expect(response.body, contains('Document.complete'));
        expect(cloudClients, 0);
        expect(localClients, 1);
        expect(client.closeCount, 1);
      },
    );
  }

  test(
    'citing rejects other origins and protocol routes before sending',
    () async {
      var clients = 0;
      http.Client create() {
        clients++;
        throw StateError('must not send');
      }

      final transport = OfficeZoteroTransport(
        createClient: create,
        createLocalClient: create,
      );
      addTearDown(transport.dispose);
      for (final uri in [
        'https://api.zotero.org/connector/document/execCommand',
        'https://localhost:23119/connector/document/execCommand',
        'http://127.0.0.1:23119/connector/document/execCommand',
        'http://localhost.evil.test:23119/connector/document/execCommand',
        'http://localhost:23120/connector/document/execCommand',
        'http://secret@localhost:23119/connector/document/execCommand',
        'http://localhost:23119/connector/document/execCommand#fragment',
        'http://localhost:23119/connector/document/execCommand?key=secret',
        'http://localhost:23119/connector/document/respond?',
        'http://localhost:23119/connector/document/execCommand/',
        'http://localhost:23119/connector/document/respond/extra',
        'http://localhost:23119/connector/document/%2565xecCommand',
        'http://localhost:23119/connector/document%2FexecCommand',
        'http://localhost:23119/connector/document/execCommand%5Cextra',
        'http://localhost:23119/connector/ping',
        'http://localhost:23119/api/users/0/items',
      ]) {
        await expectLater(
          transport.send(_request(uri: uri)),
          throwsA(isA<OfficeZoteroException>()),
        );
      }
      expect(clients, 0);
    },
  );

  test(
    'citing requires POST and rejects cloud or catalog request bodies',
    () async {
      var clients = 0;
      http.Client create() {
        clients++;
        throw StateError('must not send');
      }

      final transport = OfficeZoteroTransport(
        createClient: create,
        createLocalClient: create,
      );
      addTearDown(transport.dispose);
      for (final request in [
        _request(method: 'GET'),
        _request(method: 'post'),
        _request(method: 'DELETE'),
        _request(uri: 'http://localhost:23119/api/', method: 'GET'),
        _request(uri: 'https://api.zotero.org/users/1/items', method: 'GET'),
      ]) {
        await expectLater(
          transport.send(request),
          throwsA(isA<OfficeZoteroException>()),
        );
      }
      expect(clients, 0);
    },
  );

  test(
    'citing accepts case-insensitive names but no secrets or extra headers',
    () async {
      var clients = 0;
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () {
          clients++;
          return _Client((_) async => _ok());
        },
      );
      addTearDown(transport.dispose);
      await transport.send(
        _request(
          headers: const {
            'content-type': 'application/json',
            'ZOTERO-ALLOWED-REQUEST': '1',
          },
        ),
      );
      for (final headers in <Map<String, String>>[
        {..._headers, 'Zotero-API-Key': 'secret'},
        {..._headers, 'authorization': 'secret'},
        {..._headers, 'Cookie': 'secret'},
        {..._headers, 'Proxy-Authorization': 'secret'},
        {..._headers, 'Host': 'outside.invalid'},
        {..._headers, 'Origin': 'outside.invalid'},
        {..._headers, 'Zotero-API-Version': '3'},
        {..._headers, 'Zotero-Server-ID': 'privateDatabase'},
        {..._headers, 'Content-Type': 'text/plain'},
        {..._headers, 'Content-Type': 'application/json\r\nX-Secret: secret'},
        {..._headers, 'Zotero-Allowed-Request': '0'},
        {..._headers, 'zotero-allowed-request': '1'},
        const {'Content-Type': 'application/json'},
        const {'Zotero-Allowed-Request': '1'},
        const {},
      ]) {
        await expectLater(
          transport.send(_request(headers: headers)),
          throwsA(
            isA<OfficeZoteroException>().having(
              (e) => e.message,
              'safe rejection',
              isNot(contains('secret')),
            ),
          ),
        );
      }
      expect(clients, 1);
    },
  );

  test(
    'citing request bodies are valid JSON with a UTF-8 byte bound',
    () async {
      var clients = 0;
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () {
          clients++;
          return _Client((_) async => _ok());
        },
        maxRequestBytes: 8,
      );
      addTearDown(transport.dispose);
      for (final body in <String?>[
        null,
        '',
        'secret',
        '{"x":',
        '"1234567"',
        '"éééé"',
      ]) {
        await expectLater(
          transport.send(_request(body: body)),
          throwsA(isA<OfficeZoteroException>()),
        );
      }
      expect(clients, 0);
      for (final body in ['null', 'true', '[]', '"ééé"']) {
        await transport.send(_request(body: body));
      }
      expect(clients, 4);
    },
  );

  test(
    'citing redirects return once without forwarding document data',
    () async {
      var sends = 0;
      final client = _Client((outbound) async {
        sends++;
        expect(outbound.followRedirects, isFalse);
        return http.StreamedResponse(
          const Stream.empty(),
          307,
          headers: const {'location': 'https://outside.invalid/'},
        );
      });
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => client,
      );
      addTearDown(transport.dispose);
      expect((await transport.send(_request())).statusCode, 307);
      expect(sends, 1);
      expect(client.closeCount, 1);
    },
  );

  test('citing responses reject declared and streamed excess bytes', () async {
    for (final declared in [true, false]) {
      var canceled = false;
      final body = StreamController<List<int>>(onCancel: () => canceled = true);
      final client = _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          200,
          contentLength: declared ? 6 : null,
        ),
      );
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => client,
        maxResponseBytes: 5,
      );
      addTearDown(transport.dispose);
      final response = transport.send(_request());
      final rejected = expectLater(
        response,
        throwsA(
          isA<OfficeZoteroException>().having(
            (e) => e.message,
            'size',
            contains('too large'),
          ),
        ),
      );
      body.add(utf8.encode('123'));
      body.add(utf8.encode('456'));
      await rejected;
      expect(canceled, isTrue);
      expect(client.closeCount, 1);
      await body.close();
    }
  });

  test('native dialog uses its own longer timeout', () async {
    final client = _Client((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return _ok();
    });
    final transport = OfficeZoteroTransport(
      createClient: () => throw StateError('must not use proxy'),
      createLocalClient: () => client,
      requestTimeout: const Duration(milliseconds: 5),
      integrationTimeout: const Duration(seconds: 1),
    );
    addTearDown(transport.dispose);
    expect((await transport.send(_request())).statusCode, 200);
    expect(client.closeCount, 1);
  });

  test('request timeout can shorten but cannot extend host limit', () async {
    for (final requested in [
      const Duration(milliseconds: 5),
      const Duration(hours: 1),
    ]) {
      final client = _Client((_) => Completer<http.StreamedResponse>().future);
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => client,
        integrationTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(transport.dispose);
      await expectLater(
        transport.send(_request(timeout: requested)),
        throwsA(
          isA<OfficeZoteroException>().having(
            (e) => e.message,
            'native dialog timeout',
            contains('Finish or cancel'),
          ),
        ),
      );
      expect(client.closeCount, 1);
    }
  });

  test(
    'dispose settles pending citing immediately and ignores late response',
    () async {
      final pending = Completer<http.StreamedResponse>();
      final client = _Client((_) => pending.future);
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => client,
      );
      final rejected = expectLater(
        transport.send(_request()),
        throwsA(
          isA<OfficeZoteroException>().having(
            (e) => e.message,
            'closed',
            contains('closed'),
          ),
        ),
      );
      transport.dispose();
      await rejected;
      expect(client.closeCount, 1);
      var canceled = false;
      final lateBody = StreamController<List<int>>(
        onCancel: () => canceled = true,
      );
      pending.complete(http.StreamedResponse(lateBody.stream, 200));
      await Future<void>.delayed(Duration.zero);
      expect(canceled, isTrue);
      await lateBody.close();
      await expectLater(
        transport.send(_request()),
        throwsA(isA<OfficeZoteroException>()),
      );
      transport.dispose();
      expect(client.closeCount, 1);
    },
  );

  test('dispose cancels a response body already being read', () async {
    var canceled = false;
    final body = StreamController<List<int>>(onCancel: () => canceled = true);
    final client = _Client(
      (_) async => http.StreamedResponse(body.stream, 200),
    );
    final transport = OfficeZoteroTransport(
      createClient: () => throw StateError('must not use proxy'),
      createLocalClient: () => client,
    );
    final rejected = expectLater(
      transport.send(_request()),
      throwsA(isA<OfficeZoteroException>()),
    );
    await Future<void>.delayed(Duration.zero);
    transport.dispose();
    await rejected;
    expect(canceled, isTrue);
    expect(client.closeCount, 1);
    await body.close();
  });

  test(
    'citing network failures never expose document or credential data',
    () async {
      final client = _Client(
        (_) async =>
            throw http.ClientException('secret citation text and API key'),
      );
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => client,
      );
      addTearDown(transport.dispose);
      await expectLater(
        transport.send(_request()),
        throwsA(
          isA<OfficeZoteroException>().having(
            (e) => e.message,
            'sanitized failure',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(client.closeCount, 1);
    },
  );

  test('citing and catalog limits must be positive before client creation', () {
    http.Client create() => throw StateError('must not send');
    expect(
      () => OfficeZoteroTransport(
        createClient: create,
        integrationTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => OfficeZoteroTransport(createClient: create, maxRequestBytes: 0),
      throwsArgumentError,
    );
    expect(
      () => OfficeZoteroTransport(createClient: create, maxResponseBytes: 0),
      throwsArgumentError,
    );
  });
}
