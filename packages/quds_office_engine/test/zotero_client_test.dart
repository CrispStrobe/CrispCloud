import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

Map<String, dynamic> _item(
  String key, {
  String title = 'Research & references',
}) => {
  'key': key,
  'version': 12,
  'data': {
    'key': key,
    'itemType': 'journalArticle',
    'title': title,
    'date': '2024-03-06',
    'DOI': '10.1234/example',
    'creators': [
      {'firstName': 'Amal', 'lastName': 'Hassan', 'creatorType': 'author'},
      {'name': 'Research Council', 'creatorType': 'author'},
    ],
  },
  'csljson': {'id': key, 'type': 'article-journal', 'title': title},
};

ZoteroHttpResponse _json(
  Object body, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(body),
  headers: headers,
);

TypeMatcher<ZoteroApiException> _error(
  ZoteroApiErrorKind kind, {
  int? status,
  int? seconds,
}) => isA<ZoteroApiException>()
    .having((error) => error.kind, 'kind', kind)
    .having((error) => error.statusCode, 'status', status)
    .having((error) => error.retryAfter?.inSeconds, 'retry seconds', seconds);

void main() {
  final personal = ZoteroLibrary.user(1234);
  final group = ZoteroLibrary.group(4321);

  test('key verification uses a header, strips returned secrets and resolves access', () async {
    final requests = <ZoteroHttpRequest>[];
    const secret = 'an-api-key-that-must-not-leak';
    final client = ZoteroClient(
      apiKey: secret,
      transport: (request) async {
        requests.add(request);
        return _json({
          'key': secret,
          'userID': 1234,
          'username': 'reader',
          'access': {
            'user': {'library': true},
            'groups': {
              '4321': {'library': true},
              '9999': {'library': false},
            },
          },
        });
      },
    );
    final info = await client.verifyKey();
    expect(info.userId, 1234);
    expect(info.username, 'reader');
    expect(info.canRead(personal), isTrue);
    expect(info.canRead(group), isTrue);
    expect(info.canRead(ZoteroLibrary.user(2345)), isFalse);
    expect(info.canReadGroup(9999), isFalse);
    expect(
      requests.single.uri.toString(),
      'https://api.zotero.org/keys/current',
    );
    expect(requests.single.headers['Zotero-API-Version'], '3');
    expect(requests.single.headers['Zotero-API-Key'], secret);
    expect(requests.single.followRedirects, isFalse);
    expect(requests.single.toString(), isNot(contains(secret)));
    expect(requests.single.uri.query, isEmpty);
  });

  test(
    'public library reads omit credentials; empty key cannot verify',
    () async {
      final client = ZoteroClient(
        transport: (request) async {
          expect(request.headers.containsKey('Zotero-API-Key'), isFalse);
          return _json([]);
        },
      );
      expect((await client.items(group)).items, isEmpty);
      await expectLater(
        client.verifyKey(),
        throwsA(_error(ZoteroApiErrorKind.authentication)),
      );
    },
  );

  test(
    'search, collection keys and Unicode metadata survive paginated browse',
    () async {
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient(
        transport: (request) async {
          requests.add(request);
          return _json(
            [_item('ABCD1234', title: 'القدس & 東京')],
            headers: {
              'total-results': '104',
              'Last-Modified-Version': '12',
              'LINK': '<https://api.zotero.org/groups/4321/collections/EFGH5678/items/top?limit=100&start=100>; rel="next"',
            },
          );
        },
      );
      final page = await client.items(
        group,
        collectionKey: 'EFGH5678',
        query: 'Smith & Ali/年',
        limit: 100,
      );
      final record = page.items.single;
      expect(record.title, 'القدس & 東京');
      expect(record.creatorSummary, 'Amal Hassan, Research Council');
      expect(record.year, '2024');
      expect(record.isCitable, isTrue);
      expect(
        record.canonicalUri.toString(),
        'http://zotero.org/groups/4321/items/ABCD1234',
      );
      expect(record.cslJson!['title'], 'القدس & 東京');
      expect(page.hasMore, isTrue);
      expect(page.nextStart, 100);
      expect(page.totalResults, 104);
      expect(page.lastModifiedVersion, 12);
      final request = requests.single;
      expect(request.uri.host, 'api.zotero.org');
      expect(request.uri.queryParameters['q'], 'Smith & Ali/年');
      expect(request.uri.queryParameters['qmode'], 'titleCreatorYear');
      expect(request.uri.queryParameters['limit'], '100');
    },
  );

  test(
    'pagination falls back to totals and advances requested offset',
    () async {
      final client = ZoteroClient(
        transport: (_) async => _json([], headers: {'Total-Results': '103'}),
      );
      final first = await client.items(personal, start: 0, limit: 50);
      final middle = await client.items(personal, start: 50, limit: 50);
      final last = await client.items(personal, start: 100, limit: 50);
      expect(first.nextStart, 50);
      expect(middle.nextStart, 100);
      expect(last.hasMore, isFalse);
    },
  );

  test(
    'a pagination URL cannot redirect credentials or switch libraries',
    () async {
      for (final next in [
        'https://attacker.example/users/1234/items/top?start=50',
        'http://api.zotero.org/users/1234/items/top?start=50',
        'https://api.zotero.org/groups/9999/items/top?start=50',
        'https://api.zotero.org/users/1234/items/top?start=50&key=secret',
        'https://api.zotero.org/users/1234/items/top?start=0',
      ]) {
        var calls = 0;
        final client = ZoteroClient(
          apiKey: 'secret',
          transport: (_) async {
            calls++;
            return _json([], headers: {'Link': '<$next>; rel="next"'});
          },
        );
        await expectLater(
          client.items(personal),
          throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
        );
        expect(calls, 1);
      }
    },
  );

  test('same item key is distinct in personal and group libraries', () async {
    final client = ZoteroClient(
      transport: (_) async => _json(_item('ABCD1234')),
    );
    final a = await client.item(personal, 'ABCD1234');
    final b = await client.item(group, 'ABCD1234');
    expect(a.key, b.key);
    expect(a.sourceId, isNot(b.sourceId));
  });

  test(
    'mismatched library or item identifiers are not silently relinked',
    () async {
      for (final record in [
        {
          ..._item('ABCD1234'),
          'library': {'type': 'group', 'id': 1234},
        },
        {
          ..._item('ABCD1234'),
          'library': {'type': 'user', 'id': 9999},
        },
        {
          ..._item('ABCD1234'),
          'data': {'key': 'EFGH5678', 'itemType': 'book'},
        },
      ]) {
        final client = ZoteroClient(transport: (_) async => _json(record));
        await expectLater(
          client.item(personal, 'ABCD1234'),
          throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
        );
      }
    },
  );

  test(
    'collections preserve parent hierarchy; groups use numeric IDs',
    () async {
      final client = ZoteroClient(
        transport: (request) async {
          if (request.uri.path.endsWith('/groups')) {
            return _json([
              {
                'id': 4321,
                'data': {'name': 'Lab', 'description': 'Research'},
              },
            ]);
          }
          return _json([
            {
              'key': 'ABCD1234',
              'version': 3,
              'data': {'name': 'Research', 'parentCollection': false},
            },
            {
              'key': 'EFGH5678',
              'version': 4,
              'data': {'name': 'Sources', 'parentCollection': 'ABCD1234'},
            },
          ]);
        },
      );
      final groups = await client.groups(1234);
      expect(groups.items.single.library, group);
      expect(groups.items.single.name, 'Lab');
      final collections = await client.collections(group);
      expect(collections.items.first.parentKey, isNull);
      expect(collections.items.last.parentKey, 'ABCD1234');
    },
  );

  test(
    'individual citation returns CSL and rendered snapshots with style/locale',
    () async {
      final client = ZoteroClient(
        transport: (request) async {
          expect(
            request.uri.queryParameters['include'],
            'data,csljson,citation,bib',
          );
          expect(request.uri.queryParameters['style'], 'chicago-author-date');
          expect(request.uri.queryParameters['locale'], 'de-DE');
          return _json({
            ..._item('ABCD1234'),
            'citation': '<span>(Hassan 2024)</span>',
            'bib': '<div>Hassan, Amal.</div>',
          });
        },
      );
      final result = await client.item(
        personal,
        'ABCD1234',
        style: 'chicago-author-date',
        locale: 'de-DE',
      );
      expect(result.citationHtml, contains('Hassan 2024'));
      expect(result.bibliographyHtml, contains('Hassan, Amal'));
      expect(result.cslJson!['type'], 'article-journal');
    },
  );

  test(
    'bibliography makes one globally formatted request and deduplicates keys',
    () async {
      var calls = 0;
      final client = ZoteroClient(
        transport: (request) async {
          calls++;
          expect(request.uri.path, '/users/1234/items');
          expect(request.uri.queryParameters['itemKey'], 'ABCD1234,EFGH5678');
          expect(request.uri.queryParameters['format'], 'bib');
          expect(request.uri.queryParameters.containsKey('limit'), isFalse);
          return ZoteroHttpResponse(
            statusCode: 200,
            body: '<div class="csl-bib-body">References</div>',
          );
        },
      );
      final result = await client.bibliography(
        personal,
        itemKeys: ['ABCD1234', 'ABCD1234', 'EFGH5678'],
      );
      expect(result, contains('csl-bib-body'));
      expect(calls, 1);
    },
  );

  test(
    'export passes the requested format and returns Unicode unchanged',
    () async {
      for (final format in ZoteroExportFormat.values) {
        final client = ZoteroClient(
          transport: (request) async {
            expect(request.uri.queryParameters['format'], format.apiValue);
            expect(request.uri.queryParameters['limit'], '1');
            return ZoteroHttpResponse(statusCode: 200, body: 'العربية café 東京');
          },
        );
        expect(
          await client.exportItems(group, ['ABCD1234'], format: format),
          'العربية café 東京',
        );
      }
    },
  );

  test('CSL retrieval unwraps the Web API v3 items envelope', () async {
    final items = [
      {'id': '392648/ABCD1234', 'type': 'book', 'title': 'A source'},
    ];
    for (final payload in [
      {'items': items},
      items,
    ]) {
      final client = ZoteroClient(transport: (_) async => _json(payload));
      final result = await client.cslItems(personal, ['ABCD1234']);
      expect(result.single['id'], '392648/ABCD1234');
      expect(result.single['title'], 'A source');
    }
  });

  test('CSL retrieval rejects malformed export payloads', () async {
    for (final body in ['not-json secret', '{}', '[null]']) {
      final client = ZoteroClient(
        transport: (_) async => ZoteroHttpResponse(statusCode: 200, body: body),
      );
      await expectLater(
        client.cslItems(personal, ['ABCD1234']),
        throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
      );
    }
  });

  test('invalid library IDs, keys, page bounds and oversized selections never send', () async {
    var calls = 0;
    final client = ZoteroClient(
      transport: (_) async {
        calls++;
        return _json([]);
      },
    );
    expect(() => ZoteroLibrary.user(0), throwsArgumentError);
    expect(() => ZoteroLibrary.group(-4), throwsArgumentError);
    final tooMany = List.generate(
      51,
      (index) => index.toString().padLeft(8, 'A'),
    );
    await expectLater(client.items(personal, limit: 101), throwsArgumentError);
    await expectLater(client.items(personal, start: -1), throwsArgumentError);
    await expectLater(
      client.items(personal, collectionKey: '../keys/'),
      throwsArgumentError,
    );
    await expectLater(client.item(personal, 'BAD?KEY!'), throwsArgumentError);
    await expectLater(
      client.item(
        personal,
        'ABCD1234',
        style: 'https://attacker.example/style',
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.item(personal, 'ABCD1234', locale: 'en-US&key=secret'),
      throwsArgumentError,
    );
    await expectLater(
      client.bibliography(personal, itemKeys: tooMany),
      throwsArgumentError,
    );
    await expectLater(
      client.bibliography(personal, itemKeys: []),
      throwsArgumentError,
    );
    await expectLater(
      client.exportItems(personal, tooMany),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test(
    'successful Backoff is honored without waiting, retries or discarding data',
    () async {
      var now = DateTime.utc(2026);
      var calls = 0;
      final client = ZoteroClient(
        clock: () => now,
        transport: (_) async {
          calls++;
          return _json([_item('ABCD1234')], headers: {'Backoff': '10'});
        },
      );
      final page = await client.items(personal);
      expect(page.items.single.key, 'ABCD1234');
      expect(page.backoff, const Duration(seconds: 10));
      await expectLater(
        client.collections(personal),
        throwsA(_error(ZoteroApiErrorKind.rateLimited, seconds: 10)),
      );
      expect(calls, 1);
      now = now.add(const Duration(seconds: 10));
      expect((await client.items(personal)).items, hasLength(1));
      expect(calls, 2);
    },
  );

  test(
    'HTTP errors are typed and never expose response bodies or API keys',
    () async {
      const secret = 'never-show-this-secret';
      for (final (status, kind, seconds) in [
        (403, ZoteroApiErrorKind.authentication, null),
        (404, ZoteroApiErrorKind.notFound, null),
        (429, ZoteroApiErrorKind.rateLimited, 30),
        (503, ZoteroApiErrorKind.unavailable, null),
        (302, ZoteroApiErrorKind.request, null),
      ]) {
        final client = ZoteroClient(
          apiKey: secret,
          transport: (_) async => ZoteroHttpResponse(
            statusCode: status,
            body: '$secret included in upstream error',
          ),
        );
        await expectLater(
          client.items(personal),
          throwsA(
            _error(kind, status: status, seconds: seconds).having(
              (error) => error.toString(),
              'diagnostic',
              isNot(contains(secret)),
            ),
          ),
        );
      }
    },
  );

  test(
    'Retry-After and Backoff choose the longer interval and suppress retries',
    () async {
      var calls = 0;
      final now = DateTime.utc(2026);
      final client = ZoteroClient(
        clock: () => now,
        transport: (_) async {
          calls++;
          return ZoteroHttpResponse(
            statusCode: 429,
            body: '',
            headers: {'Retry-After': '20', 'Backoff': '40'},
          );
        },
      );
      await expectLater(
        client.items(personal),
        throwsA(
          _error(ZoteroApiErrorKind.rateLimited, status: 429, seconds: 40),
        ),
      );
      await expectLater(
        client.items(personal),
        throwsA(_error(ZoteroApiErrorKind.rateLimited, seconds: 40)),
      );
      expect(calls, 1);
    },
  );

  test('concurrent responses cannot shorten a requested Backoff', () async {
    final slow = Completer<ZoteroHttpResponse>();
    final fast = Completer<ZoteroHttpResponse>();
    var calls = 0;
    final now = DateTime.utc(2026);
    final client = ZoteroClient(
      clock: () => now,
      transport: (_) {
        calls++;
        return calls == 1 ? fast.future : slow.future;
      },
    );
    final first = client.items(personal);
    final second = client.collections(personal);
    fast.complete(_json([], headers: {'Backoff': '60'}));
    await first;
    slow.complete(_json([], headers: {'Backoff': '1'}));
    await second;
    expect(client.retryAfter, const Duration(seconds: 60));
    await expectLater(
      client.items(personal),
      throwsA(_error(ZoteroApiErrorKind.rateLimited, seconds: 60)),
    );
    expect(calls, 2);
  });

  test('malformed responses, mismatched keys and transport diagnostics are contained', () async {
    for (final body in ['secret-not-json', '{}', '[{"key":"BAD"}]']) {
      final client = ZoteroClient(
        transport: (_) async => ZoteroHttpResponse(statusCode: 200, body: body),
      );
      await expectLater(
        client.items(personal),
        throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
      );
    }
    final mismatched = ZoteroClient(
      transport: (_) async => _json(_item('EFGH5678')),
    );
    await expectLater(
      mismatched.item(personal, 'ABCD1234'),
      throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
    );
    final broken = ZoteroClient(
      transport: (_) async => throw StateError('Authorization secret'),
    );
    await expectLater(
      broken.items(personal),
      throwsA(
        _error(ZoteroApiErrorKind.network).having(
          (error) => error.toString(),
          'diagnostic',
          isNot(contains('secret')),
        ),
      ),
    );
  });
}
