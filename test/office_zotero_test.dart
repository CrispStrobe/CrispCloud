import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/services/office_zotero.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
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

class _Storage extends InMemorySecureStorage {
  bool ignoreWrites = false;
  bool failReads = false;
  int readCount = 0;

  @override
  bool get isPersistent => true;

  @override
  Future<String?> read(String key) async {
    readCount++;
    if (failReads) throw StateError('secret from storage backend');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!ignoreWrites) await super.write(key, value);
  }
}

ZoteroHttpRequest _request([String? uri]) => ZoteroHttpRequest(
  uri: Uri.parse(uri ?? 'https://api.zotero.org/users/1/items?format=json'),
  headers: const {'Zotero-API-Key': 'test-secret', 'Zotero-API-Version': '3'},
);

void main() {
  group('Zotero transport boundary', () {
    test(
      'sends API-key header only to Zotero and never follows redirects',
      () async {
        late http.BaseRequest outbound;
        final client = _Client((request) async {
          outbound = request;
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"ok":true}')),
            200,
            headers: const {'Total-Results': '1'},
          );
        });
        final transport = OfficeZoteroTransport(createClient: () => client);
        final response = await transport.send(_request());
        expect(outbound.method, 'GET');
        expect(outbound.headers['Zotero-API-Key'], 'test-secret');
        expect(outbound.url.queryParameters.containsKey('key'), isFalse);
        expect(outbound.followRedirects, isFalse);
        expect(outbound.maxRedirects, 0);
        expect(response.body, '{"ok":true}');
        expect(response.header('total-results'), '1');
        expect(client.closeCount, 1);
        transport.dispose();
        expect(client.closeCount, 1);
      },
    );

    test('rejects non-Zotero destinations before creating a client', () async {
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not send'),
      );
      for (final uri in [
        'http://api.zotero.org/users/1/items',
        'https://api.zotero.org.evil.test/users/1/items',
        'https://api.zotero.org:8443/users/1/items',
        'https://secret@api.zotero.org/users/1/items',
        'https://api.zotero.org/users/1/items#fragment',
      ]) {
        await expectLater(
          transport.send(_request(uri)),
          throwsA(isA<OfficeZoteroException>()),
        );
      }
    });

    test('passes redirect status for the API client to reject', () async {
      final client = _Client(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: const {'location': 'https://outside.invalid/'},
        ),
      );
      final transport = OfficeZoteroTransport(createClient: () => client);
      expect((await transport.send(_request())).statusCode, 302);
      expect(client.closeCount, 1);
    });

    test('bounds declared and streamed response sizes', () async {
      for (final declared in [true, false]) {
        final client = _Client(
          (_) async => http.StreamedResponse(
            Stream.fromIterable([utf8.encode('123'), utf8.encode('456')]),
            200,
            contentLength: declared ? 6 : null,
          ),
        );
        final transport = OfficeZoteroTransport(
          createClient: () => client,
          maxResponseBytes: 5,
        );
        await expectLater(
          transport.send(_request()),
          throwsA(
            isA<OfficeZoteroException>().having(
              (error) => error.message,
              'safe size error',
              contains('too large'),
            ),
          ),
        );
        expect(client.closeCount, 1);
      }
    });

    test('total request timeout closes the owned client', () async {
      final client = _Client((_) => Completer<http.StreamedResponse>().future);
      final transport = OfficeZoteroTransport(
        createClient: () => client,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        transport.send(_request()),
        throwsA(
          isA<OfficeZoteroException>().having(
            (error) => error.message,
            'safe timeout',
            contains('in time'),
          ),
        ),
      );
      expect(client.closeCount, 1);
    });

    test('HTTP exceptions cannot expose the API key', () async {
      final client = _Client(
        (_) async => throw http.ClientException('Zotero-API-Key: test-secret'),
      );
      final transport = OfficeZoteroTransport(createClient: () => client);
      await expectLater(
        transport.send(_request()),
        throwsA(
          isA<OfficeZoteroException>().having(
            (error) => '$error',
            'redacted diagnostic',
            isNot(contains('test-secret')),
          ),
        ),
      );
      expect(client.closeCount, 1);
    });

    test('timeout cancels a stalled response body subscription', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = _Client(
        (_) async => http.StreamedResponse(body.stream, 200),
      );
      final transport = OfficeZoteroTransport(
        createClient: () => client,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        transport.send(_request()),
        throwsA(isA<OfficeZoteroException>()),
      );
      expect(cancelled, isTrue);
      expect(client.closeCount, 1);
      await body.close();
    });

    test('disposal closes active requests and rejects new requests', () async {
      final pending = Completer<http.StreamedResponse>();
      final client = _Client((_) => pending.future);
      final transport = OfficeZoteroTransport(createClient: () => client);
      final sent = transport.send(_request());
      transport.dispose();
      expect(client.closeCount, 1);
      pending.complete(http.StreamedResponse(const Stream.empty(), 200));
      await expectLater(sent, throwsA(isA<OfficeZoteroException>()));
      await expectLater(
        transport.send(_request()),
        throwsA(isA<OfficeZoteroException>()),
      );
      expect(client.closeCount, 1);
    });
  });

  group('Zotero credential persistence', () {
    test('writes, reads back and forgets only the Zotero entry', () async {
      final storage = _Storage();
      await storage.write('unrelated', 'preserved');
      final credentials = OfficeZoteroCredentials(storage);
      await credentials.save(' api-key ');
      expect(await credentials.load(), 'api-key');
      await credentials.save(null);
      expect(await credentials.load(), isNull);
      expect(await storage.read('unrelated'), 'preserved');
    });

    test('session-only backend never offers persistent credentials', () async {
      final storage = InMemorySecureStorage();
      await storage.write(OfficeZoteroCredentials.storageKey, 'ephemeral-key');
      final credentials = OfficeZoteroCredentials(storage);
      expect(credentials.canPersist, isFalse);
      expect(await credentials.load(), isNull);
      await expectLater(
        credentials.save('new-key'),
        throwsA(isA<OfficeZoteroException>()),
      );
    });

    test(
      'failed read-back never reports a successful remember operation',
      () async {
        final storage = _Storage()..ignoreWrites = true;
        final credentials = OfficeZoteroCredentials(storage);
        await expectLater(
          credentials.save('api-key'),
          throwsA(isA<OfficeZoteroException>()),
        );
      },
    );

    test(
      'backend failures are sanitized and invalid keys are rejected',
      () async {
        final storage = _Storage()..failReads = true;
        final credentials = OfficeZoteroCredentials(storage);
        await expectLater(
          credentials.load(),
          throwsA(
            isA<OfficeZoteroException>().having(
              (error) => '$error',
              'redacted store error',
              isNot(contains('secret from storage backend')),
            ),
          ),
        );
        await expectLater(
          credentials.save('api-key\nheader'),
          throwsA(isA<OfficeZoteroException>()),
        );
      },
    );
  });
}
