import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

ZoteroHttpResponse _json(
  Object value, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(value),
  headers: {'Zotero-Server-ID': 'desktop-1', ...headers},
);

Map<String, Object?> _search(String key, {String name = 'Research'}) => {
  'key': key,
  'version': 7,
  'data': {'key': key, 'name': name, 'conditions': <Object>[]},
};

Map<String, Object?> _item(
  ZoteroLibrary library,
  String key, {
  String type = 'book',
}) => {
  'key': key,
  'library': {'type': library.type.name, 'id': library.id},
  'data': {'key': key, 'itemType': type, 'title': 'A source'},
  'csljson': {
    'id': library.isLocalUser
        ? 'http://zotero.org/users/local/LOCALKEY/items/$key'
        : library.itemUri(key).toString(),
    'type': 'book',
    'title': 'A source',
  },
};

void main() {
  for (final library in [ZoteroLibrary.localUser(), ZoteroLibrary.group(42)]) {
    test(
      'saved searches use the pinned local ${library.type.name} library',
      () async {
        final requests = <ZoteroHttpRequest>[];
        final client = ZoteroClient.local(
          transport: (request) async {
            requests.add(request);
            if (request.uri.path == '/api/') {
              return ZoteroHttpResponse(
                statusCode: 200,
                body: 'Local API',
                headers: const {
                  'Zotero-API-Version': '3',
                  'Zotero-Server-ID': 'desktop-1',
                },
              );
            }
            expect(request.headers['Zotero-Server-ID'], 'desktop-1');
            expect(request.headers['Zotero-API-Key'], isNull);
            expect(request.headers['Zotero-Allowed-Request'], '1');
            expect(request.followRedirects, isFalse);
            expect(request.method, 'GET');
            expect(request.body, isNull);
            if (request.uri.path.endsWith('/searches')) {
              return _json(
                [_search('SEARCH01', name: 'Quellen & القدس')],
                headers: {'Total-Results': '101', 'Last-Modified-Version': '7'},
              );
            }
            return _json(
              [
                _item(library, 'SOURCE01'),
                {..._item(library, 'SOURCE02', type: 'note'), 'csljson': '[]'},
              ],
              headers: {
                'Total-Results': '103',
                'Link':
                    '<http://localhost:23119/api${library.apiPath}/searches/SEARCH01/items?start=100&limit=50>; rel="next"',
              },
            );
          },
        );
        await client.probeLocal();
        final searches = await client.savedSearches(library, limit: 100);
        expect(searches.items.single.library, library);
        expect(searches.items.single.key, 'SEARCH01');
        expect(searches.items.single.name, 'Quellen & القدس');
        expect(searches.items.single.version, 7);
        expect(searches.nextStart, 100);
        expect(searches.lastModifiedVersion, 7);
        final page = await client.savedSearchItems(
          library,
          searches.items.single.key,
          query: '  Müller & 年  ',
          start: 50,
        );
        expect(page.start, 50);
        expect(page.nextStart, 100);
        expect(page.totalResults, 103);
        expect(page.items.first.isCitable, isTrue);
        expect(page.items.last.isCitable, isFalse);
        expect(page.items.first.citationUri?.path, endsWith('/items/SOURCE01'));
        final request = requests.last;
        expect(request.uri.scheme, 'http');
        expect(request.uri.host, 'localhost');
        expect(request.uri.port, 23119);
        expect(
          request.uri.path,
          '/api${library.apiPath}/searches/SEARCH01/items',
        );
        expect(request.uri.queryParameters, {
          'start': '50',
          'limit': '50',
          'format': 'json',
          'include': 'data,csljson',
          'sort': 'dateModified',
          'direction': 'desc',
          'q': 'Müller & 年',
          'qmode': 'titleCreatorYear',
        });
        expect(requests[1].uri.path, '/api${library.apiPath}/searches');
      },
    );
  }

  test(
    'online connections cannot list or execute the local saved-search workflow',
    () async {
      var calls = 0;
      final client = ZoteroClient(
        apiKey: 'secret',
        transport: (_) async {
          calls++;
          return _json([]);
        },
      );
      await expectLater(
        client.savedSearches(ZoteroLibrary.user(1)),
        throwsStateError,
      );
      await expectLater(
        client.savedSearchItems(ZoteroLibrary.group(1), 'SEARCH01'),
        throwsStateError,
      );
      expect(calls, 0);
    },
  );

  test(
    'saved-search keys and query/page limits are checked before transport',
    () async {
      var calls = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          calls++;
          return _json([]);
        },
      );
      final library = ZoteroLibrary.localUser();
      for (final key in [
        '../items',
        'SEARCH01/items',
        'SEARCH01?key=secret',
        'search01',
        'SEARCH0',
      ]) {
        await expectLater(
          client.savedSearchItems(library, key),
          throwsArgumentError,
        );
      }
      for (final query in ['x' * 1025, 'title\ncreator', 'title\u0000']) {
        await expectLater(
          client.savedSearchItems(library, 'SEARCH01', query: query),
          throwsArgumentError,
        );
      }
      for (final (start, limit) in [(-1, 50), (0, 0), (0, 101)]) {
        await expectLater(
          client.savedSearches(library, start: start, limit: limit),
          throwsArgumentError,
        );
        await expectLater(
          client.savedSearchItems(
            library,
            'SEARCH01',
            start: start,
            limit: limit,
          ),
          throwsArgumentError,
        );
      }
      expect(calls, 0);
      await client.savedSearchItems(
        library,
        'SEARCH01',
        query: 'x' * 1024,
        limit: 100,
      );
      expect(calls, 1);
    },
  );

  test(
    'malformed saved searches do not create ambiguous navigation entries',
    () async {
      for (final response in <Object>[
        {'searches': <Object>[]},
        [
          {'key': 'SEARCH01', 'data': 'invalid'},
        ],
        [_search('../items')],
        [
          {
            ..._search('SEARCH01'),
            'data': {'key': 'SEARCH02', 'name': 'Mismatch'},
          },
        ],
        [_search('SEARCH01'), _search('SEARCH01')],
        [
          {
            ..._search('SEARCH01'),
            'library': {'type': 'user', 'id': 42},
          },
        ],
        [
          {
            ..._search('SEARCH01'),
            'library': {'type': 'group', 'id': 99},
          },
        ],
      ]) {
        final client = ZoteroClient.local(
          transport: (_) async => _json(response),
        );
        await expectLater(
          client.savedSearches(ZoteroLibrary.group(42)),
          throwsA(
            isA<ZoteroApiException>().having(
              (e) => e.kind,
              'kind',
              ZoteroApiErrorKind.invalidResponse,
            ),
          ),
        );
      }
    },
  );

  test(
    'saved-search pagination cannot change search, library, or destination',
    () async {
      for (final path in [
        'http://localhost:23119/api/users/0/searches/SEARCH02/items?start=50',
        'http://localhost:23119/api/groups/42/searches/SEARCH01/items?start=50',
        'https://attacker.invalid/api/users/0/searches/SEARCH01/items?start=50',
        'http://localhost:23119/api/users/0/searches/SEARCH01/items?start=50&key=secret',
        'http://localhost:23119/api/users/0/searches/SEARCH01/items?start=0',
      ]) {
        var calls = 0;
        final client = ZoteroClient.local(
          transport: (_) async {
            calls++;
            return _json([], headers: {'Link': '<$path>; rel="next"'});
          },
        );
        await expectLater(
          client.savedSearchItems(ZoteroLibrary.localUser(), 'SEARCH01'),
          throwsA(
            isA<ZoteroApiException>().having(
              (e) => e.kind,
              'kind',
              ZoteroApiErrorKind.invalidResponse,
            ),
          ),
        );
        expect(calls, 1);
      }
    },
  );

  test('a desktop database switch cannot reuse a saved search key', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (request) async {
        calls++;
        if (calls == 1) return _json([_search('SEARCH01')]);
        expect(request.headers['Zotero-Server-ID'], 'desktop-1');
        return _json([], headers: {'Zotero-Server-ID': 'desktop-2'});
      },
    );
    final library = ZoteroLibrary.localUser();
    await client.savedSearches(library);
    await expectLater(
      client.savedSearchItems(library, 'SEARCH01'),
      throwsA(
        isA<ZoteroApiException>().having(
          (e) => e.message,
          'message',
          contains('Reconnect'),
        ),
      ),
    );
  });

  test(
    'deleted searches return a safe actionable error without a cloud retry',
    () async {
      var calls = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          calls++;
          return ZoteroHttpResponse(
            statusCode: 404,
            body: 'private saved search details',
          );
        },
      );
      await expectLater(
        client.savedSearchItems(ZoteroLibrary.localUser(), 'SEARCH01'),
        throwsA(
          isA<ZoteroApiException>()
              .having((e) => e.kind, 'kind', ZoteroApiErrorKind.notFound)
              .having(
                (e) => e.message,
                'safe error',
                isNot(contains('private')),
              ),
        ),
      );
      expect(calls, 1);
    },
  );
}
