import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

ZoteroHttpResponse _page({bool local = false}) => ZoteroHttpResponse(
  statusCode: 200,
  headers: const {'Total-Results': '101'},
  body: jsonEncode([
    {
      'key': 'SOURCE01',
      if (local) 'library': {'type': 'user', 'id': 0},
      'data': {
        'key': 'SOURCE01',
        'itemType': 'book',
        'title': 'A library result',
      },
      'csljson': {
        'id': local
            ? 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01'
            : 'SOURCE01',
        'type': 'book',
        'title': 'A library result',
      },
    },
  ]),
);

void main() {
  final group = ZoteroLibrary.group(42);

  test('default catalog queries preserve the existing wire contract', () async {
    final requests = <ZoteroHttpRequest>[];
    final client = ZoteroClient(
      transport: (request) async {
        requests.add(request);
        return _page();
      },
    );
    await client.items(group, query: '  A title  ');
    expect(requests.single.uri.queryParameters, {
      'start': '0',
      'limit': '50',
      'format': 'json',
      'include': 'data,csljson',
      'sort': 'dateModified',
      'direction': 'desc',
      'q': 'A title',
      'qmode': 'titleCreatorYear',
    });
  });

  test('collection full-text and type filters precede pagination', () async {
    final requests = <ZoteroHttpRequest>[];
    final client = ZoteroClient(
      apiKey: 'catalog-test-key',
      transport: (request) async {
        requests.add(request);
        return _page();
      },
    );
    final page = await client.items(
      group,
      collectionKey: 'COLL0001',
      query: '  القدس & DOI/年?  ',
      start: 25,
      limit: 25,
      searchMode: ZoteroSearchMode.everything,
      sort: ZoteroItemSort.creator,
      direction: ZoteroSortDirection.ascending,
      itemType: 'book',
    );
    final request = requests.single;
    expect(request.uri.origin, 'https://api.zotero.org');
    expect(request.uri.path, '/groups/42/collections/COLL0001/items/top');
    expect(request.uri.queryParameters, {
      'start': '25',
      'limit': '25',
      'format': 'json',
      'include': 'data,csljson',
      'sort': 'creator',
      'direction': 'asc',
      'itemType': 'book',
      'q': 'القدس & DOI/年?',
      'qmode': 'everything',
    });
    expect(request.headers['Zotero-API-Key'], 'catalog-test-key');
    expect(request.uri.query, isNot(contains('catalog-test-key')));
    expect(request.followRedirects, isFalse);
    expect(page.items.single.title, 'A library result');
    expect(page.nextStart, 50);
  });

  test('desktop saved searches accept the same scoped query options', () async {
    final requests = <ZoteroHttpRequest>[];
    final client = ZoteroClient.local(
      transport: (request) async {
        requests.add(request);
        return _page(local: true);
      },
    );
    await client.savedSearchItems(
      ZoteroLibrary.localUser(),
      'SEARCH01',
      query: 'archival phrase',
      start: 50,
      searchMode: ZoteroSearchMode.everything,
      sort: ZoteroItemSort.date,
      direction: ZoteroSortDirection.ascending,
      itemType: 'journalArticle',
    );
    final request = requests.single;
    expect(request.uri.origin, 'http://localhost:23119');
    expect(request.uri.path, '/api/users/0/searches/SEARCH01/items');
    expect(request.uri.queryParameters['start'], '50');
    expect(request.uri.queryParameters['qmode'], 'everything');
    expect(request.uri.queryParameters['sort'], 'date');
    expect(request.uri.queryParameters['direction'], 'asc');
    expect(request.uri.queryParameters['itemType'], 'journalArticle');
    expect(request.headers['Zotero-API-Key'], isNull);
    expect(request.headers['Zotero-Allowed-Request'], '1');
  });

  test(
    'blank search can filter and sort without a quick-search clause',
    () async {
      final client = ZoteroClient(
        transport: (request) async {
          expect(request.uri.queryParameters.containsKey('q'), isFalse);
          expect(request.uri.queryParameters.containsKey('qmode'), isFalse);
          expect(request.uri.queryParameters['itemType'], 'thesis');
          expect(request.uri.queryParameters['sort'], 'title');
          return _page();
        },
      );
      await client.items(
        group,
        query: '   ',
        searchMode: ZoteroSearchMode.everything,
        sort: ZoteroItemSort.title,
        itemType: 'thesis',
      );
    },
  );

  for (final sort in ZoteroItemSort.values) {
    for (final direction in ZoteroSortDirection.values) {
      test('${sort.name} supports ${direction.name} ordering', () async {
        final client = ZoteroClient(
          transport: (request) async {
            expect(request.uri.queryParameters['sort'], sort.name);
            expect(
              request.uri.queryParameters['direction'],
              direction.apiValue,
            );
            return _page();
          },
        );
        await client.items(group, sort: sort, direction: direction);
      });
    }
  }

  test('invalid item-type expressions fail before any request', () async {
    var calls = 0;
    final client = ZoteroClient(
      transport: (_) async {
        calls++;
        return _page();
      },
    );
    for (final itemType in [
      '',
      ' book',
      'book ',
      'book || thesis',
      '-attachment',
      'book&key=secret',
      'book\n',
      'book\u0000',
      '../items',
      'b' * 65,
    ]) {
      await expectLater(
        client.items(group, itemType: itemType),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test('search controls remain bounded on saved-search endpoints', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async {
        calls++;
        return _page(local: true);
      },
    );
    await expectLater(
      client.savedSearchItems(
        ZoteroLibrary.localUser(),
        'SEARCH01',
        query: 'x' * 1025,
        searchMode: ZoteroSearchMode.everything,
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.savedSearchItems(
        ZoteroLibrary.localUser(),
        'SEARCH01',
        itemType: 'book || thesis',
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });
}
