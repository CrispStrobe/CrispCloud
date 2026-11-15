import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/services/office_zotero.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quds_office_editor/quds_office_editor.dart'
    show WordEditorController;
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

ZoteroHttpRequest _localRequest({
  String uri = 'http://localhost:23119/api/users/0/items?format=json',
  Map<String, String> headers = const {
    'Zotero-API-Version': '3',
    'Zotero-Allowed-Request': '1',
  },
}) => ZoteroHttpRequest(uri: Uri.parse(uri), headers: headers);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'credential loading target rejects changed documents and selections',
    () {
      final controller = WordEditorController(
        document: WmlDocument.empty(text: 'Original target'),
      );
      addTearDown(controller.dispose);
      final original = officeZoteroEditTarget(controller);
      controller.relayout();
      expect(officeZoteroEditTarget(controller), original);

      controller.caret.logicalIndex = 3;
      expect(officeZoteroEditTarget(controller), isNot(original));
      controller.caret.logicalIndex = 0;
      final unselected = officeZoteroEditTarget(controller);
      controller.caret.selectionAnchor = 4;
      expect(officeZoteroEditTarget(controller), isNot(unselected));
      controller.caret.collapseSelection();

      final beforeEdit = officeZoteroEditTarget(controller);
      controller.insertText('Changed');
      controller.commitPendingEdits();
      expect(officeZoteroEditTarget(controller), isNot(beforeEdit));

      final body = officeZoteroEditTarget(controller);
      controller.beginHeaderFooterEdit(0, footer: false);
      expect(officeZoteroEditTarget(controller), isNot(body));

      final oldDocument = officeZoteroEditTarget(controller);
      controller.document = WmlDocument.empty(text: 'Replaced');
      expect(officeZoteroEditTarget(controller), isNot(oldDocument));
    },
  );

  group('Zotero transport boundary', () {
    test(
      'desktop reads use only the explicitly supplied direct client',
      () async {
        var cloudClients = 0;
        var localClients = 0;
        late http.BaseRequest outbound;
        final client = _Client((request) async {
          outbound = request;
          return http.StreamedResponse(
            Stream.value(utf8.encode('Nothing to see here.')),
            200,
            headers: const {'Zotero-Server-ID': 'localDatabase'},
          );
        });
        final transport = OfficeZoteroTransport(
          createClient: () {
            cloudClients++;
            throw StateError('The proxy must not receive local library data.');
          },
          createLocalClient: () {
            localClients++;
            return client;
          },
        );
        expect(transport.supportsLocal, isTrue);
        final response = await transport.send(
          _localRequest(
            uri: 'http://localhost:23119/api/',
            headers: const {
              'zotero-api-version': '3',
              'ZOTERO-ALLOWED-REQUEST': '1',
              'Zotero-Server-ID': 'localDatabase',
            },
          ),
        );
        expect(cloudClients, 0);
        expect(localClients, 1);
        expect(outbound.url.toString(), 'http://localhost:23119/api/');
        expect(outbound.headers['Zotero-API-Key'], isNull);
        expect(outbound.headers['Authorization'], isNull);
        expect(outbound.headers['Zotero-Server-ID'], 'localDatabase');
        expect(outbound.followRedirects, isFalse);
        expect(outbound.maxRedirects, 0);
        expect(response.body, 'Nothing to see here.');
        expect(client.closeCount, 1);
        transport.dispose();
        expect(client.closeCount, 1);
      },
    );

    test(
      'cloud requests retain the selected proxy factory with local enabled',
      () async {
        var localClients = 0;
        final cloud = _Client((request) async {
          expect(request.url.host, 'api.zotero.org');
          expect(request.headers['Zotero-API-Key'], 'test-secret');
          return http.StreamedResponse(const Stream.empty(), 200);
        });
        final transport = OfficeZoteroTransport(
          createClient: () => cloud,
          createLocalClient: () {
            localClients++;
            throw StateError('Cloud requests must not use the direct factory.');
          },
        );
        await transport.send(_request());
        expect(localClients, 0);
        expect(cloud.closeCount, 1);
      },
    );

    test(
      'desktop access requires host opt-in before creating any client',
      () async {
        var created = 0;
        final transport = OfficeZoteroTransport(
          createClient: () {
            created++;
            throw StateError('must not send');
          },
        );
        expect(transport.supportsLocal, isFalse);
        await expectLater(
          transport.send(_localRequest()),
          throwsA(isA<OfficeZoteroException>()),
        );
        expect(created, 0);
      },
    );

    test(
      'desktop rejects secrets and unexpected headers before client creation',
      () async {
        var created = 0;
        http.Client createClient() {
          created++;
          throw StateError('must not send');
        }

        final transport = OfficeZoteroTransport(
          createClient: createClient,
          createLocalClient: createClient,
        );
        const safe = {'Zotero-API-Version': '3', 'Zotero-Allowed-Request': '1'};
        for (final headers in <Map<String, String>>[
          {...safe, 'Zotero-API-Key': 'test-secret'},
          {...safe, 'zotero-api-key': 'test-secret'},
          {...safe, 'Authorization': 'Bearer test-secret'},
          {...safe, 'Cookie': 'test-secret'},
          {...safe, 'Proxy-Authorization': 'test-secret'},
          {...safe, 'Host': 'outside.invalid'},
          {...safe, 'Zotero-API-Version': '2'},
          {...safe, 'Zotero-Allowed-Request': '0'},
          {...safe, 'Zotero-Server-ID': 'bad\r\nX-Secret: test-secret'},
          {...safe, 'zotero-api-version': '3'},
          const {'Zotero-API-Version': '3'},
          const {},
        ]) {
          await expectLater(
            transport.send(_localRequest(headers: headers)),
            throwsA(
              isA<OfficeZoteroException>().having(
                (error) => '$error',
                'sanitized rejection',
                isNot(contains('test-secret')),
              ),
            ),
          );
        }
        expect(created, 0);
      },
    );

    test(
      'desktop rejects other hosts, ports, paths and URL credentials',
      () async {
        var created = 0;
        http.Client createClient() {
          created++;
          throw StateError('must not send');
        }

        final transport = OfficeZoteroTransport(
          createClient: createClient,
          createLocalClient: createClient,
        );
        for (final uri in [
          'http://127.0.0.1:23119/api/users/0/items',
          'http://localhost.evil.test:23119/api/users/0/items',
          'http://localhost:23120/api/users/0/items',
          'https://localhost:23119/api/users/0/items',
          'http://secret@localhost:23119/api/users/0/items',
          'http://localhost:23119/connector/ping',
          'http://localhost:23119/apievil/users/0/items',
          'http://localhost:23119/api/../connector/ping',
          'http://localhost:23119/api/%2E%2E/connector/ping',
          'http://localhost:23119/api/%252e%252e/connector/ping',
          'http://localhost:23119/api/users%2F0/items',
          'http://localhost:23119/api/users%5C0/items',
          'http://localhost:23119/api/users/0/items#fragment',
          'http://localhost:23119/api/users/0/items?key=test-secret',
          'http://localhost:23119/api/users/0/items?KEY=test-secret',
          'http://localhost:23119/api/users/0/items?%6bey=test-secret',
        ]) {
          await expectLater(
            transport.send(_localRequest(uri: uri)),
            throwsA(isA<OfficeZoteroException>()),
          );
        }
        expect(created, 0);
      },
    );

    test('desktop redirects are returned without another request', () async {
      var sends = 0;
      final local = _Client((request) async {
        sends++;
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: const {'location': 'https://outside.invalid/?key=secret'},
        );
      });
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => local,
      );
      expect((await transport.send(_localRequest())).statusCode, 302);
      expect(sends, 1);
      expect(local.closeCount, 1);
    });

    test('desktop responses retain size and total timeout limits', () async {
      for (final declared in [true, false]) {
        final local = _Client(
          (_) async => http.StreamedResponse(
            Stream.fromIterable([utf8.encode('123'), utf8.encode('456')]),
            200,
            contentLength: declared ? 6 : null,
          ),
        );
        final transport = OfficeZoteroTransport(
          createClient: () => throw StateError('must not use proxy'),
          createLocalClient: () => local,
          maxResponseBytes: 5,
        );
        await expectLater(
          transport.send(_localRequest()),
          throwsA(
            isA<OfficeZoteroException>().having(
              (error) => error.message,
              'safe size error',
              contains('too large'),
            ),
          ),
        );
        expect(local.closeCount, 1);
      }
      final stalled = _Client((_) => Completer<http.StreamedResponse>().future);
      final transport = OfficeZoteroTransport(
        createClient: () => throw StateError('must not use proxy'),
        createLocalClient: () => stalled,
        requestTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        transport.send(_localRequest()),
        throwsA(
          isA<OfficeZoteroException>().having(
            (error) => error.message,
            'safe timeout',
            contains('in time'),
          ),
        ),
      );
      expect(stalled.closeCount, 1);
    });

    test(
      'disposal closes desktop requests and rejects later desktop reads',
      () async {
        final pending = Completer<http.StreamedResponse>();
        final local = _Client((_) => pending.future);
        final transport = OfficeZoteroTransport(
          createClient: () => throw StateError('must not use proxy'),
          createLocalClient: () => local,
        );
        final sent = transport.send(_localRequest());
        transport.dispose();
        expect(local.closeCount, 1);
        pending.complete(http.StreamedResponse(const Stream.empty(), 200));
        await expectLater(sent, throwsA(isA<OfficeZoteroException>()));
        await expectLater(
          transport.send(_localRequest()),
          throwsA(isA<OfficeZoteroException>()),
        );
        expect(local.closeCount, 1);
      },
    );

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
