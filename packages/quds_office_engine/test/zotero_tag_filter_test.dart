import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

ZoteroHttpResponse _page({
  bool local = false,
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  headers: {'Total-Results': '101', ...headers},
  body: jsonEncode([
    {
      'key': 'SOURCE01',
      'library': {'type': 'user', 'id': local ? 0 : 42},
      'data': {
        'key': 'SOURCE01',
        'itemType': 'book',
        'title': 'A matching source',
      },
      'csljson': {
        'id': local
            ? 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01'
            : 'http://zotero.org/users/42/items/SOURCE01',
        'type': 'book',
        'title': 'A matching source',
      },
    },
  ]),
);

void main() {
  final library = ZoteroLibrary.user(42);

  test(
    'normalization retains literal identity and returns a detached list',
    () {
      final input = [
        '  Research  ',
        'القدس',
        'Research',
        'research',
        'two  words',
      ];
      final tags = normalizeZoteroTags(input);
      expect(tags, ['Research', 'القدس', 'research', 'two  words']);
      input[0] = 'changed';
      expect(tags.first, 'Research');
      expect(() => tags.add('changed'), throwsUnsupportedError);
      expect(normalizeZoteroTags(const []), isEmpty);
    },
  );

  test(
    'empty tag selections preserve the unfiltered request exactly',
    () async {
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient(
        transport: (request) async {
          requests.add(request);
          return _page();
        },
      );
      await client.items(library, query: 'source');
      await client.items(library, query: 'source', tags: const []);
      expect(requests[1].uri, requests[0].uri);
      expect(requests[0].uri.queryParametersAll.containsKey('tag'), isFalse);
    },
  );

  test(
    'library requests require all tags alongside existing filters',
    () async {
      late ZoteroHttpRequest request;
      final client = ZoteroClient(
        apiKey: 'tag-test-key',
        transport: (value) async {
          request = value;
          return _page();
        },
      );
      final page = await client.items(
        library,
        query: '  archival phrase  ',
        start: 25,
        limit: 25,
        searchMode: ZoteroSearchMode.everything,
        sort: ZoteroItemSort.title,
        direction: ZoteroSortDirection.ascending,
        itemType: 'book',
        tags: ['reviewed', 'primary sources', 'reviewed'],
      );
      expect(request.uri.origin, 'https://api.zotero.org');
      expect(request.uri.path, '/users/42/items/top');
      expect(request.uri.queryParametersAll, {
        'start': ['25'],
        'limit': ['25'],
        'format': ['json'],
        'include': ['data,csljson'],
        'sort': ['title'],
        'direction': ['asc'],
        'itemType': ['book'],
        'q': ['archival phrase'],
        'qmode': ['everything'],
        'tag': ['reviewed', 'primary sources'],
      });
      expect(
        request.uri.query.split('&').where((part) => part.startsWith('tag=')),
        hasLength(2),
      );
      expect(request.headers['Zotero-API-Key'], 'tag-test-key');
      expect(request.uri.toString(), isNot(contains('tag-test-key')));
      expect(request.followRedirects, isFalse);
      expect(request.method, 'GET');
      expect(page.items.single.title, 'A matching source');
      expect(page.totalResults, 101);
      expect(page.nextStart, 50);
    },
  );

  test(
    'collection tags preserve Unicode and URL-reserved literal text',
    () async {
      final tags = [
        'القدس & بُحوث',
        'Müller /年?',
        'C++ #42',
        r'path\to\source',
        r'\topic',
        r'\\-literal',
        'topic|part',
        'x%7C%7Cy',
        '📚 a\u0301',
      ];
      late Uri uri;
      final client = ZoteroClient(
        transport: (request) async {
          uri = request.uri;
          return _page();
        },
      );
      await client.items(library, collectionKey: 'COLL0001', tags: tags);
      expect(uri.path, '/users/42/collections/COLL0001/items/top');
      expect(uri.queryParametersAll['tag'], tags);
      expect(
        uri.queryParametersAll.keys,
        unorderedEquals({
          'start',
          'limit',
          'format',
          'include',
          'sort',
          'direction',
          'tag',
        }),
      );
      expect(uri.hasFragment, isFalse);
      expect(uri.query, contains('x%257C%257Cy'));
    },
  );

  test('leading hyphens are escaped instead of excluding tags', () async {
    late Uri uri;
    final client = ZoteroClient(
      transport: (request) async {
        uri = request.uri;
        return _page();
      },
    );
    await client.items(library, tags: ['-reviewed', '--flag', ' - ']);
    expect(uri.queryParametersAll['tag'], [r'\-reviewed', r'\--flag', r'\-']);
    expect(uri.query, contains('tag=%5C-reviewed'));
  });

  test(
    'tag requests capture caller-owned input before awaiting a response',
    () async {
      final pending = Completer<ZoteroHttpResponse>();
      late Uri uri;
      final client = ZoteroClient(
        transport: (request) {
          uri = request.uri;
          return pending.future;
        },
      );
      final tags = ['reviewed', 'primary'];
      final result = client.items(library, tags: tags);
      tags
        ..clear()
        ..add('different');
      pending.complete(_page());
      await result;
      expect(uri.queryParametersAll['tag'], ['reviewed', 'primary']);
    },
  );

  test(
    'local saved-search tags retain routing and pinned database headers',
    () async {
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient.local(
        transport: (request) async {
          requests.add(request);
          return _page(
            local: true,
            headers: {'Zotero-Server-ID': 'test-server'},
          );
        },
      );
      for (final start in [0, 50]) {
        await client.savedSearchItems(
          ZoteroLibrary.localUser(),
          'SEARCH01',
          start: start,
          query: 'source',
          tags: ['reviewed', '-draft'],
        );
      }
      final request = requests.last;
      expect(request.uri.origin, 'http://localhost:23119');
      expect(request.uri.path, '/api/users/0/searches/SEARCH01/items');
      expect(request.uri.queryParametersAll['tag'], ['reviewed', r'\-draft']);
      expect(request.uri.queryParameters['start'], '50');
      expect(request.headers['Zotero-API-Key'], isNull);
      expect(request.headers['Zotero-Allowed-Request'], '1');
      expect(request.headers['Zotero-Server-ID'], 'test-server');
    },
  );

  for (final scope in ['library', 'collection', 'saved search']) {
    test(
      '$scope refuses ambiguous literal tag syntax before transport',
      () async {
        var requests = 0;
        Future<ZoteroHttpResponse> transport(ZoteroHttpRequest _) async {
          requests++;
          return _page();
        }

        final client = scope == 'saved search'
            ? ZoteroClient.local(transport: transport)
            : ZoteroClient(transport: transport);
        for (final tag in [
          'foo || bar',
          'foo||bar',
          '||',
          r'\-literal',
          r'  \-literal',
        ]) {
          final Future<ZoteroPage<ZoteroItem>> result;
          if (scope == 'saved search') {
            result = client.savedSearchItems(library, 'SEARCH01', tags: [tag]);
          } else {
            result = client.items(
              library,
              collectionKey: scope == 'collection' ? 'COLL0001' : null,
              tags: [tag],
            );
          }
          await expectLater(result, throwsFormatException);
        }
        expect(requests, 0);
      },
    );
  }

  test(
    'invalid tag text is rejected without exposing input or sending a request',
    () async {
      var requests = 0;
      final client = ZoteroClient(
        transport: (_) async {
          requests++;
          return _page();
        },
      );
      for (final tag in [
        '',
        '   ',
        'private\nvalue',
        'private\tvalue',
        'private\u0000value',
        'private\u007fvalue',
        'private\u0085value',
        'private\u2028value',
        'private\u2029value',
        'private\ud800value',
        'private\udc00value',
      ]) {
        await expectLater(
          client.items(library, tags: [tag]),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('private')),
            ),
          ),
        );
      }
      expect(requests, 0);
    },
  );

  test('entry and aggregate bounds admit their exact boundary', () async {
    var requests = 0;
    final client = ZoteroClient(
      transport: (_) async {
        requests++;
        return _page();
      },
    );
    await client.items(library, tags: [for (var i = 0; i < 20; i++) 'tag $i']);
    await client.items(library, tags: ['a' * 256]);
    await client.items(library, tags: List.filled(8, 'a' * 256));
    expect(requests, 3);
    for (final tags in [
      List.filled(21, 'duplicate'),
      ['a' * 257],
      [...List.filled(8, 'a' * 256), 'x'],
    ]) {
      await expectLater(
        client.items(library, tags: tags),
        throwsFormatException,
      );
    }
    expect(requests, 3);
  });

  test(
    'tagged saved searches retain the actionable missing-search error',
    () async {
      final client = ZoteroClient.local(
        transport: (_) async => ZoteroHttpResponse(statusCode: 404, body: ''),
      );
      await expectLater(
        client.savedSearchItems(library, 'SEARCH01', tags: ['reviewed']),
        throwsA(
          isA<ZoteroApiException>()
              .having(
                (error) => error.kind,
                'kind',
                ZoteroApiErrorKind.notFound,
              )
              .having(
                (error) => error.message,
                'message',
                contains('saved search'),
              ),
        ),
      );
    },
  );

  test('tagged responses cannot switch the requested library', () async {
    final client = ZoteroClient(transport: (_) async => _page());
    await expectLater(
      client.items(ZoteroLibrary.user(99), tags: ['reviewed']),
      throwsA(
        isA<ZoteroApiException>().having(
          (error) => error.kind,
          'kind',
          ZoteroApiErrorKind.invalidResponse,
        ),
      ),
    );
  });
}
