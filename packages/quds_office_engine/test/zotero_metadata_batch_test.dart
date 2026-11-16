import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

Map<String, Object?> _source(
  String key, {
  String kind = 'user',
  int libraryId = 1234,
  String? cslId,
}) => {
  'key': key,
  'library': {'type': kind, 'id': libraryId},
  'version': 9,
  'data': {'key': key, 'itemType': 'book', 'title': 'Source $key'},
  'csljson': {'id': cslId ?? key, 'type': 'book', 'title': 'Source $key'},
};

Uri _localUri(String key, {String profile = 'aBcD1234'}) =>
    Uri.parse('http://zotero.org/users/local/$profile/items/$key');

ZoteroHttpResponse _json(
  Object body, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(body),
  headers: headers,
);

Matcher _error(ZoteroApiErrorKind kind) =>
    isA<ZoteroApiException>().having((error) => error.kind, 'kind', kind);

void main() {
  final personal = ZoteroLibrary.user(1234);
  final local = ZoteroLibrary.localUser();
  final expected = {
    'ABCD1234': personal.itemUri('ABCD1234'),
    'EFGH5678': personal.itemUri('EFGH5678'),
  };

  test(
    'fifty sources use one bounded metadata request and retain order',
    () async {
      final keys = List.generate(
        50,
        (index) => 'K${index.toString().padLeft(7, '0')}',
      );
      final identities = {for (final key in keys) key: personal.itemUri(key)};
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient(
        apiKey: 'test-key',
        transport: (request) async {
          requests.add(request);
          return _json(
            keys.reversed.map(_source).toList(),
            headers: {'Total-Results': '50'},
          );
        },
      );

      final result = await client.metadataItems(
        personal,
        expectedItemUris: identities,
      );

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.uri.scheme, 'https');
      expect(request.uri.host, 'api.zotero.org');
      expect(request.uri.path, '/users/1234/items');
      expect(request.uri.queryParameters, {
        'itemKey': keys.join(','),
        'format': 'json',
        'include': 'data,csljson',
        'limit': '50',
      });
      expect(request.headers['Zotero-API-Key'], 'test-key');
      expect(request.followRedirects, isFalse);
      expect(result.map((item) => item.key), keys);
      expect(
        result.map((item) => item.cslJson!['title']),
        keys.map((key) => 'Source $key'),
      );
      expect(() => result.clear(), throwsUnsupportedError);
    },
  );

  test('group requests retain their distinct library identity', () async {
    final group = ZoteroLibrary.group(1234);
    final client = ZoteroClient(
      transport: (request) async {
        expect(request.uri.path, '/groups/1234/items');
        return _json([_source('ABCD1234', kind: 'group')]);
      },
    );
    final result = await client.metadataItems(
      group,
      expectedItemUris: {'ABCD1234': group.itemUri('ABCD1234')},
    );
    expect(result.single.citationUri, group.itemUri('ABCD1234'));
    expect(result.single.citationUri, isNot(personal.itemUri('ABCD1234')));
  });

  test(
    'local metadata proves every profile identity without new-version headers',
    () async {
      final client = ZoteroClient.local(
        transport: (request) async {
          expect(
            request.uri.toString(),
            startsWith('http://localhost:23119/api/users/0/items?'),
          );
          expect(request.headers, {
            'Zotero-API-Version': '3',
            'Zotero-Allowed-Request': '1',
          });
          return _json([
            for (final key in expected.keys.toList().reversed)
              _source(
                key,
                libraryId: 0,
                cslId: 'https://www.zotero.org/users/local/aBcD1234/items/$key',
              ),
          ]);
        },
      );
      final result = await client.metadataItems(
        local,
        expectedItemUris: {
          for (final key in expected.keys) key: _localUri(key),
        },
      );
      expect(result.map((item) => item.key), expected.keys);
      expect(
        result.map((item) => item.citationUri),
        expected.keys.map(_localUri),
      );
    },
  );

  test(
    'aliases in expected identities normalize without changing the input',
    () async {
      final uri = Uri.parse('https://www.zotero.org/users/1234/items/ABCD1234');
      final identities = {'ABCD1234': uri};
      final client = ZoteroClient(
        transport: (_) async => _json([_source('ABCD1234')]),
      );
      final result = await client.metadataItems(
        personal,
        expectedItemUris: identities,
      );
      expect(result.single.citationUri, personal.itemUri('ABCD1234'));
      expect(identities['ABCD1234'], uri);
    },
  );

  test('invalid selections fail before any network request', () async {
    var calls = 0;
    final client = ZoteroClient(
      transport: (_) async {
        calls++;
        return _json([]);
      },
    );
    final tooMany = {
      for (var index = 0; index < 51; index++)
        'K${index.toString().padLeft(7, '0')}': personal.itemUri(
          'K${index.toString().padLeft(7, '0')}',
        ),
    };
    for (final identities in <Map<String, Uri>>[
      {},
      tooMany,
      {'BAD?KEY!': personal.itemUri('ABCD1234')},
      {'ABCD1234': personal.itemUri('EFGH5678')},
      {'ABCD1234': ZoteroLibrary.group(1234).itemUri('ABCD1234')},
      {'ABCD1234': _localUri('ABCD1234')},
      {'ABCD1234': Uri.parse('http://zotero.org/users/0/items/ABCD1234')},
      {
        'ABCD1234': Uri.parse(
          'http://zotero.org/users/1234/items/ABCD1234?key=secret',
        ),
      },
    ]) {
      await expectLater(
        client.metadataItems(personal, expectedItemUris: identities),
        throwsArgumentError,
      );
    }
    await expectLater(
      client.metadataItems(
        local,
        expectedItemUris: {'ABCD1234': _localUri('ABCD1234')},
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('two desktop profiles cannot be combined behind users zero', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async {
        calls++;
        return _json([]);
      },
    );
    await expectLater(
      client.metadataItems(
        local,
        expectedItemUris: {
          'ABCD1234': _localUri('ABCD1234'),
          'EFGH5678': _localUri('EFGH5678', profile: 'other123'),
        },
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  for (final (name, records) in <(String, List<Object>)>[
    ('missing source', [_source('ABCD1234')]),
    ('duplicate source', [_source('ABCD1234'), _source('ABCD1234')]),
    (
      'additional source',
      [_source('ABCD1234'), _source('EFGH5678'), _source('IJKL9012')],
    ),
    ('substituted source', [_source('ABCD1234'), _source('IJKL9012')]),
    (
      'wrong library kind',
      [_source('ABCD1234'), _source('EFGH5678', kind: 'group')],
    ),
    (
      'wrong account',
      [_source('ABCD1234'), _source('EFGH5678', libraryId: 5678)],
    ),
    (
      'malformed entry',
      [
        _source('ABCD1234'),
        {'key': 'EFGH5678'},
      ],
    ),
  ]) {
    test('$name refuses the whole batch', () async {
      var calls = 0;
      final client = ZoteroClient(
        transport: (_) async {
          calls++;
          return _json(records);
        },
      );
      await expectLater(
        client.metadataItems(personal, expectedItemUris: expected),
        throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
      );
      expect(calls, 1);
    });
  }

  test(
    'same item keys from another desktop profile refuse the batch',
    () async {
      final client = ZoteroClient.local(
        transport: (_) async => _json([
          _source(
            'ABCD1234',
            libraryId: 0,
            cslId: _localUri('ABCD1234').toString(),
          ),
          _source(
            'EFGH5678',
            libraryId: 0,
            cslId: _localUri('EFGH5678', profile: 'other123').toString(),
          ),
        ]),
      );
      await expectLater(
        client.metadataItems(
          local,
          expectedItemUris: {
            for (final key in expected.keys) key: _localUri(key),
          },
        ),
        throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
      );
    },
  );

  test('a local citation key cannot prove a durable identity', () async {
    final client = ZoteroClient.local(
      transport: (_) async =>
          _json([_source('ABCD1234', libraryId: 0, cslId: 'Hassan2026')]),
    );
    await expectLater(
      client.metadataItems(
        local,
        expectedItemUris: {'ABCD1234': _localUri('ABCD1234')},
      ),
      throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
    );
  });

  test(
    'inconsistent or malformed result totals refuse complete-looking data',
    () async {
      for (final total in ['0', '1', '3', '-1', 'invalid']) {
        final client = ZoteroClient(
          transport: (_) async => _json(
            expected.keys.map(_source).toList(),
            headers: {'Total-Results': total},
          ),
        );
        await expectLater(
          client.metadataItems(personal, expectedItemUris: expected),
          throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
          reason: total,
        );
      }
    },
  );

  test(
    'missing CSL remains visible for the host to refuse atomic refresh',
    () async {
      final client = ZoteroClient(
        transport: (_) async => _json([
          {..._source('ABCD1234'), 'csljson': null},
        ]),
      );
      final result = await client.metadataItems(
        personal,
        expectedItemUris: {'ABCD1234': personal.itemUri('ABCD1234')},
      );
      expect(result.single.cslJson, isNull);
      expect(result.single.citationUri, personal.itemUri('ABCD1234'));
    },
  );

  test(
    'argument mutation while waiting cannot change verified identities',
    () async {
      final response = Completer<ZoteroHttpResponse>();
      final identities = Map<String, Uri>.from(expected);
      final client = ZoteroClient(transport: (_) => response.future);
      final operation = client.metadataItems(
        personal,
        expectedItemUris: identities,
      );
      identities
        ..clear()
        ..['IJKL9012'] = personal.itemUri('IJKL9012');
      response.complete(_json(expected.keys.map(_source).toList()));
      expect((await operation).map((item) => item.key), expected.keys);
    },
  );

  test(
    'metadata requests retain database pinning and reject a switched desktop',
    () async {
      var calls = 0;
      final client = ZoteroClient.local(
        transport: (request) async {
          calls++;
          if (calls == 1) {
            expect(request.uri.path, '/api/');
            return ZoteroHttpResponse(
              statusCode: 200,
              body: 'Zotero API',
              headers: {
                'Zotero-API-Version': '3',
                'Zotero-Server-ID': 'original-database',
              },
            );
          }
          expect(request.headers['Zotero-Server-ID'], 'original-database');
          return _json(
            [
              _source(
                'ABCD1234',
                libraryId: 0,
                cslId: _localUri('ABCD1234').toString(),
              ),
            ],
            headers: {'Zotero-Server-ID': 'another-database'},
          );
        },
      );
      await client.probeLocal();
      await expectLater(
        client.metadataItems(
          local,
          expectedItemUris: {'ABCD1234': _localUri('ABCD1234')},
        ),
        throwsA(_error(ZoteroApiErrorKind.unavailable)),
      );
      expect(calls, 2);
    },
  );

  test('server backoff blocks the next batch without retries', () async {
    var now = DateTime.utc(2026, 11, 16);
    var calls = 0;
    final client = ZoteroClient(
      clock: () => now,
      transport: (_) async {
        calls++;
        return _json(
          expected.keys.map(_source).toList(),
          headers: {'Backoff': '10'},
        );
      },
    );
    expect(
      await client.metadataItems(personal, expectedItemUris: expected),
      hasLength(2),
    );
    await expectLater(
      client.metadataItems(personal, expectedItemUris: expected),
      throwsA(_error(ZoteroApiErrorKind.rateLimited)),
    );
    expect(calls, 1);
    expect(client.retryAfter, const Duration(seconds: 10));
    now = now.add(const Duration(seconds: 11));
    expect(
      await client.metadataItems(personal, expectedItemUris: expected),
      hasLength(2),
    );
    expect(calls, 2);
  });
}
