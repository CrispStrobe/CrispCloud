import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

ZoteroHttpResponse _json(
  Object? value, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(value),
  headers: headers,
);

Matcher get _invalidResponse => isA<ZoteroApiException>().having(
  (error) => error.kind,
  'kind',
  ZoteroApiErrorKind.invalidResponse,
);

void main() {
  for (final library in [ZoteroLibrary.user(7), ZoteroLibrary.group(42)]) {
    test('online ${library.type.name} tags keep a read-only request', () async {
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient(
        apiKey: 'tag-catalog-secret',
        transport: (request) async {
          requests.add(request);
          return _json(
            [
              {
                'tag': 'Research',
                'meta': {'type': 0, 'numItems': 12},
              },
              {
                'tag': 'Research',
                'meta': {'type': 1, 'numItems': 8},
              },
            ],
            headers: {'Last-Modified-Version': '37'},
          );
        },
      );
      final page = await client.tags(library);
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.body, isNull);
      expect(request.followRedirects, isFalse);
      expect(request.uri.origin, 'https://api.zotero.org');
      expect(request.uri.path, '${library.apiPath}/tags');
      expect(request.uri.queryParameters, {
        'start': '0',
        'limit': '50',
        'format': 'json',
      });
      expect(request.headers['Zotero-API-Key'], 'tag-catalog-secret');
      expect(request.headers['Zotero-API-Version'], '3');
      expect(request.headers.containsKey('Zotero-Allowed-Request'), isFalse);
      expect(request.uri.toString(), isNot(contains('tag-catalog-secret')));
      expect(request.toString(), isNot(contains('tag-catalog-secret')));
      expect(page.items.map((tag) => tag.name), ['Research', 'Research']);
      expect(page.items.map((tag) => tag.type), [0, 1]);
      expect(page.items.map((tag) => tag.numItems), [12, 8]);
      expect(page.lastModifiedVersion, 37);
      expect(page.start, 0);
      expect(page.limit, 50);
      expect(page.hasMore, isFalse);
      expect(() => page.items.clear(), throwsUnsupportedError);
    });
  }

  for (final searchMode in ZoteroTagSearchMode.values) {
    test('collection tag ${searchMode.name} query uses qmode', () async {
      final client = ZoteroClient(
        transport: (request) async {
          expect(request.uri.path, '/groups/42/collections/COLL0001/tags');
          expect(request.uri.queryParameters, {
            'start': '25',
            'limit': '25',
            'format': 'json',
            'q': 'القدس & DOI/年? 📚',
            'qmode': searchMode.name,
          });
          return _json(
            [
              {'tag': 'القدس & DOI/年? 📚'},
            ],
            headers: {'Total-Results': '101'},
          );
        },
      );
      final page = await client.tags(
        ZoteroLibrary.group(42),
        collectionKey: 'COLL0001',
        query: '  القدس & DOI/年? 📚  ',
        searchMode: searchMode,
        start: 25,
        limit: 25,
      );
      expect(page.nextStart, 50);
      expect(page.totalResults, 101);
    });
  }

  // Zotero's desktop /tags handler does not apply q. Its Items handler
  // implements tag q/qmode and registers collection/items/tags routes:
  // https://github.com/zotero/zotero/blob/b589b7ff2f9fa5f1fea2a69b61a9e583e50d8cb8/chrome/content/zotero/xpcom/server/server_localAPI.js
  for (final library in [ZoteroLibrary.localUser(), ZoteroLibrary.group(42)]) {
    for (final collection in <String?>[null, 'COLL0001']) {
      test(
        'desktop ${library.type.name} tags query the ${collection ?? 'library'} items scope',
        () async {
          final requests = <ZoteroHttpRequest>[];
          final client = ZoteroClient.local(
            transport: (request) async {
              requests.add(request);
              expect(request.headers['Zotero-API-Key'], isNull);
              expect(request.headers['Zotero-Allowed-Request'], '1');
              expect(request.method, 'GET');
              expect(request.body, isNull);
              expect(request.followRedirects, isFalse);
              if (request.uri.path == '/api/') {
                return ZoteroHttpResponse(
                  statusCode: 200,
                  body: 'Local API',
                  headers: {
                    'Zotero-API-Version': '3',
                    'Zotero-Server-ID': 'desktop-catalog-1',
                  },
                );
              }
              expect(request.headers['Zotero-Server-ID'], 'desktop-catalog-1');
              return _json(
                [
                  {'tag': 'Research'},
                ],
                headers: {'Zotero-Server-ID': 'desktop-catalog-1'},
              );
            },
          );
          await client.probeLocal();
          await client.tags(
            library,
            collectionKey: collection,
            query: 'Res',
            searchMode: ZoteroTagSearchMode.startsWith,
          );
          final request = requests.last;
          expect(request.uri.origin, 'http://localhost:23119');
          final scope = collection == null ? '' : '/collections/$collection';
          expect(request.uri.path, '/api${library.apiPath}$scope/items/tags');
          expect(request.uri.queryParameters['q'], 'Res');
          expect(request.uri.queryParameters['qmode'], 'startsWith');
          expect(request.uri.queryParameters.containsKey('itemQ'), isFalse);
        },
      );
    }
  }

  test('blank tag searches omit both q and qmode', () async {
    final client = ZoteroClient(
      transport: (request) async {
        expect(request.uri.queryParameters.containsKey('q'), isFalse);
        expect(request.uri.queryParameters.containsKey('qmode'), isFalse);
        return _json([]);
      },
    );
    await client.tags(ZoteroLibrary.user(7), query: '   ');
  });

  test(
    'names retain exact case, whitespace and unsupported filter syntax',
    () async {
      final names = [
        'Research',
        'research',
        ' padded ',
        'a || b',
        r'\-literal',
        '-literal',
        'é',
        'e\u0301',
        'القدس 📚',
        'x' * 257,
      ];
      final client = ZoteroClient(
        transport: (_) async => _json([
          for (final name in names) {'tag': name},
        ]),
      );
      final page = await client.tags(ZoteroLibrary.user(7));
      expect(page.items.map((tag) => tag.name), names);
      expect(page.items.every((tag) => tag.numItems == null), isTrue);
      expect(page.items.every((tag) => tag.type == null), isTrue);
      expect(
        () => normalizeZoteroTags([page.items[3].name]),
        throwsFormatException,
      );
    },
  );

  test(
    'missing metadata stays unknown while zero and future types survive',
    () async {
      final client = ZoteroClient(
        transport: (_) async => _json([
          {'tag': 'Unknown'},
          {'tag': 'Empty metadata', 'meta': <String, Object>{}},
          {
            'tag': 'Zero',
            'meta': {'type': 0, 'numItems': 0},
          },
          {
            'tag': 'Future type',
            'meta': {'type': 2},
          },
        ]),
      );
      final tags = (await client.tags(ZoteroLibrary.user(7))).items;
      expect(tags.map((tag) => tag.type), [null, null, 0, 2]);
      expect(tags.map((tag) => tag.numItems), [null, null, 0, null]);
    },
  );

  test(
    'invalid query, scope and page inputs fail before network access',
    () async {
      var calls = 0;
      final client = ZoteroClient(
        transport: (_) async {
          calls++;
          return _json([]);
        },
      );
      final library = ZoteroLibrary.user(7);
      for (final query in [
        'x' * 1025,
        'name\nother',
        'name\u0000',
        'name\u007f',
        'name\u0085',
        'name\u2028',
        'name\u2029',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
        '${String.fromCharCode(0xd800)}x',
      ]) {
        await expectLater(
          client.tags(library, query: query),
          throwsArgumentError,
        );
      }
      for (final key in [
        '../tags',
        'coll0001',
        'COLL0001/tags',
        'COLL0001?q=x',
      ]) {
        await expectLater(
          client.tags(library, collectionKey: key),
          throwsArgumentError,
        );
      }
      for (final (start, limit) in [(-1, 50), (0, 0), (0, 101)]) {
        await expectLater(
          client.tags(library, start: start, limit: limit),
          throwsArgumentError,
        );
      }
      await expectLater(
        client.tags(ZoteroLibrary.localUser()),
        throwsArgumentError,
      );
      expect(calls, 0);
      await client.tags(library, query: 'x' * 1024, limit: 100);
      await client.tags(library, query: '📚' * 512, limit: 100);
      expect(calls, 2);
    },
  );

  test(
    'malformed tag arrays and metadata fail without partial results',
    () async {
      for (final payload in <Object?>[
        null,
        {'tags': <Object>[]},
        [null],
        ['Research'],
        [<String, Object>{}],
        [
          {'tag': ''},
        ],
        [
          {'tag': 7},
        ],
        [
          {'tag': String.fromCharCode(0xd800)},
        ],
        [
          {'tag': 'Research', 'meta': null},
        ],
        [
          {'tag': 'Research', 'meta': <Object>[]},
        ],
        for (final key in ['type', 'numItems'])
          for (final value in <Object?>[null, '1', -1, 1.5, true])
            [
              {'tag': 'Valid first record'},
              {
                'tag': 'Invalid metadata',
                'meta': {key: value},
              },
            ],
      ]) {
        final client = ZoteroClient(transport: (_) async => _json(payload));
        await expectLater(
          client.tags(ZoteroLibrary.user(7)),
          throwsA(_invalidResponse),
        );
      }
    },
  );

  test('a response exceeding the requested page limit is rejected', () async {
    final client = ZoteroClient(
      transport: (_) async => _json([
        {'tag': 'First'},
        {'tag': 'Second'},
      ]),
    );
    await expectLater(
      client.tags(ZoteroLibrary.user(7), limit: 1),
      throwsA(_invalidResponse),
    );
  });

  test(
    'pagination preserves records and uses the validated next offset',
    () async {
      final client = ZoteroClient(
        transport: (_) async => _json(
          [
            {'tag': 'Research'},
          ],
          headers: {
            'Total-Results': '140',
            'Link':
                '<https://api.zotero.org/users/7/tags?start=75&limit=25>; rel="next"',
          },
        ),
      );
      final page = await client.tags(
        ZoteroLibrary.user(7),
        start: 25,
        limit: 25,
      );
      expect(page.nextStart, 75);
      expect(page.totalResults, 140);
    },
  );

  for (final next in [
    'https://other.example/users/7/tags?start=50',
    'http://api.zotero.org/users/7/tags?start=50',
    'https://user@api.zotero.org/users/7/tags?start=50',
    'https://api.zotero.org/users/8/tags?start=50',
    'https://api.zotero.org/users/7/items?start=50',
    'https://api.zotero.org/users/7/tags?start=0',
    'https://api.zotero.org/users/7/tags?start=bad',
    'https://api.zotero.org/users/7/tags?start=50&key=secret',
    'https://api.zotero.org/users/7/tags?start=50#fragment',
  ]) {
    test('tag pagination rejects an invalid next link: $next', () async {
      final client = ZoteroClient(
        transport: (_) async =>
            _json([], headers: {'Link': '<$next>; rel="next"'}),
      );
      await expectLater(
        client.tags(ZoteroLibrary.user(7)),
        throwsA(_invalidResponse),
      );
    });
  }

  test('tag requests honor shared backoff without a retry loop', () async {
    var now = DateTime.utc(2026, 11, 19);
    var calls = 0;
    final backoff = ZoteroBackoffState();
    Future<ZoteroHttpResponse> transport(ZoteroHttpRequest request) async {
      calls++;
      return _json([], headers: calls == 1 ? {'Backoff': '3'} : {});
    }

    final first = ZoteroClient(
      transport: transport,
      clock: () => now,
      backoffState: backoff,
    );
    final second = ZoteroClient(
      transport: transport,
      clock: () => now,
      backoffState: backoff,
    );
    expect(
      (await first.tags(ZoteroLibrary.user(7))).backoff,
      const Duration(seconds: 3),
    );
    await expectLater(
      second.tags(ZoteroLibrary.group(42)),
      throwsA(
        isA<ZoteroApiException>().having(
          (error) => error.kind,
          'kind',
          ZoteroApiErrorKind.rateLimited,
        ),
      ),
    );
    expect(calls, 1);
    now = now.add(const Duration(seconds: 4));
    await second.tags(ZoteroLibrary.group(42));
    expect(calls, 2);
  });

  test('desktop tag pages reject a changed database identity', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async => _json(
        [],
        headers: {
          'Zotero-Server-ID': ++calls == 1 ? 'desktop-one' : 'desktop-two',
        },
      ),
    );
    await client.tags(ZoteroLibrary.localUser());
    await expectLater(
      client.tags(ZoteroLibrary.localUser(), start: 50),
      throwsA(
        isA<ZoteroApiException>().having(
          (error) => error.kind,
          'kind',
          ZoteroApiErrorKind.unavailable,
        ),
      ),
    );
  });

  test('transport failures and malformed JSON retain safe errors', () async {
    for (final malformedJson in [false, true]) {
      final client = ZoteroClient(
        apiKey: 'private-key',
        transport: (_) async {
          if (!malformedJson) throw StateError('private-key credential');
          return ZoteroHttpResponse(
            statusCode: 200,
            body: 'private-key not JSON',
          );
        },
      );
      await expectLater(
        client.tags(ZoteroLibrary.user(7)),
        throwsA(
          isA<ZoteroApiException>()
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('private-key')),
              )
              .having(
                (error) => error.kind,
                'kind',
                malformedJson
                    ? ZoteroApiErrorKind.invalidResponse
                    : ZoteroApiErrorKind.network,
              ),
        ),
      );
    }
  });
}
