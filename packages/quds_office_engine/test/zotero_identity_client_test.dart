import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

const _databaseHeaders = {
  'Zotero-Server-ID': 'original-database',
  'Last-Modified-Version': '42',
  'Total-Results': '2',
};

Uri _localUri(String key, {String profile = 'aBcD1234'}) =>
    Uri.parse('http://zotero.org/users/local/$profile/items/$key');

Map<String, Object?> _localSource(
  String key, {
  String profile = 'aBcD1234',
  String? cslId,
}) => {
  'key': key,
  'library': {'type': 'user', 'id': 0},
  'data': {'key': key, 'itemType': 'book', 'title': 'Local source $key'},
  'csljson': {
    'id': cslId ?? _localUri(key, profile: profile).toString(),
    'type': 'book',
    'title': 'Local source $key',
  },
  'citation': '<span>(Local 2026)</span>',
};

Map<String, Object?> _remoteSource(String key) => {
  'key': key,
  'library': {'type': 'user', 'id': 1234},
  'data': {'key': key, 'itemType': 'book', 'title': 'Remote source $key'},
  'csljson': {'id': key, 'type': 'book', 'title': 'Remote source $key'},
};

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
  final local = ZoteroLibrary.localUser();
  final remote = ZoteroLibrary.user(1234);
  final expected = {
    'ABCD1234': _localUri('ABCD1234'),
    'EFGH5678': _localUri('EFGH5678'),
  };

  test('local preview proves an unsynced identity in the same response', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (request) async {
        calls++;
        expect(request.uri.path, '/api/users/0/items/ABCD1234');
        expect(request.uri.queryParameters['style'], 'chicago-author-date');
        expect(request.uri.queryParameters['locale'], 'de-DE');
        expect(request.headers['Zotero-API-Key'], isNull);
        // Older desktop versions need no server ID for same-response checks.
        return _json(_localSource('ABCD1234'));
      },
    );
    final item = await client.item(
      local,
      'ABCD1234',
      expectedCitationUri: _localUri('ABCD1234'),
      style: 'chicago-author-date',
      locale: 'de-DE',
    );
    expect(item.citationUri, _localUri('ABCD1234'));
    expect(item.citationHtml, '<span>(Local 2026)</span>');
    expect(calls, 1);
  });

  test('known URI scheme and hostname aliases normalize consistently', () async {
    for (final scheme in ['http', 'https']) {
      for (final host in ['zotero.org', 'www.zotero.org']) {
        final alias =
            '$scheme://$host/users/local/aBcD1234/items/ABCD1234';
        final client = ZoteroClient.local(
          transport: (_) async => _json(
            _localSource('ABCD1234', cslId: alias),
          ),
        );
        final item = await client.item(
          local,
          'ABCD1234',
          expectedCitationUri: Uri.parse(alias),
        );
        expect(item.citationUri, _localUri('ABCD1234'));
      }
    }
  });

  test('a colliding key from another local profile cannot refresh or preview', () async {
    final client = ZoteroClient.local(
      transport: (_) async => _json(
        _localSource('ABCD1234', profile: 'other123'),
      ),
    );
    await expectLater(
      client.item(
        local,
        'ABCD1234',
        expectedCitationUri: _localUri('ABCD1234'),
      ),
      throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
    );
  });

  test('citation keys and missing CSL IDs cannot prove a linked local identity', () async {
    for (final id in [null, 'Hassan2026', 'https://example.org/ABCD1234']) {
      final client = ZoteroClient.local(
        transport: (_) async => _json({
          ..._localSource('ABCD1234'),
          'csljson': {'id': id, 'type': 'book', 'title': 'Unlinked source'},
        }),
      );
      await expectLater(
        client.item(
          local,
          'ABCD1234',
          expectedCitationUri: _localUri('ABCD1234'),
        ),
        throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
      );
    }
  });

  test('invalid identity arguments fail before any request', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async {
        calls++;
        return _json(_localSource('ABCD1234'));
      },
    );
    for (final value in [
      'http://zotero.org/users/0/items/ABCD1234',
      'http://zotero.org/users/local/aBcD1234/items/EFGH5678',
      'http://zotero.org/users/local/short/items/ABCD1234',
      'http://zotero.org/users/local/aBcD1234/items/ABCD1234?key=secret',
      'http://zotero.org/users/local/aBcD1234/items/ABCD1234#fragment',
      'http://user@zotero.org/users/local/aBcD1234/items/ABCD1234',
      'http://zotero.org:8080/users/local/aBcD1234/items/ABCD1234',
      'https://example.org/users/local/aBcD1234/items/ABCD1234',
      'ftp://zotero.org/users/local/aBcD1234/items/ABCD1234',
      'http://zotero.org/groups/1234/items/ABCD1234',
    ]) {
      await expectLater(
        client.item(
          local,
          'ABCD1234',
          expectedCitationUri: Uri.parse(value),
        ),
        throwsArgumentError,
        reason: value,
      );
    }
    expect(calls, 0);
  });

  test('cloud routes refuse local identities before sending credentials', () async {
    var calls = 0;
    final client = ZoteroClient(
      apiKey: 'online-secret',
      transport: (_) async {
        calls++;
        return _json([]);
      },
    );
    await expectLater(
      client.item(
        remote,
        'ABCD1234',
        expectedCitationUri: _localUri('ABCD1234'),
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.exportItems(
        remote,
        ['ABCD1234'],
        expectedItemUris: {'ABCD1234': _localUri('ABCD1234')},
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.bibliography(
        remote,
        itemKeys: ['ABCD1234'],
        expectedItemUris: {'ABCD1234': _localUri('ABCD1234')},
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('all export formats verify exact local identities before raw output', () async {
    for (final format in ZoteroExportFormat.values) {
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient.local(
        transport: (request) async {
          requests.add(request);
          expect(request.uri.path, '/api/users/0/items');
          expect(request.uri.queryParameters['itemKey'], 'ABCD1234,EFGH5678');
          expect(request.uri.queryParameters['limit'], '2');
          expect(request.headers['Zotero-API-Key'], isNull);
          if (requests.length == 1) {
            expect(request.uri.queryParameters['format'], 'json');
            expect(request.uri.queryParameters['include'], 'data,csljson');
            return _json(
              // Zotero can return a different order.
              [_localSource('EFGH5678'), _localSource('ABCD1234')],
              headers: _databaseHeaders,
            );
          }
          expect(request.headers['Zotero-Server-ID'], 'original-database');
          expect(request.uri.queryParameters['format'], format.apiValue);
          return ZoteroHttpResponse(
            statusCode: 200,
            body: 'العربية café 東京',
            headers: _databaseHeaders,
          );
        },
      );
      expect(
        await client.exportItems(
          local,
          ['ABCD1234', 'EFGH5678', 'ABCD1234'],
          format: format,
          expectedItemUris: expected,
        ),
        'العربية café 東京',
      );
      expect(requests, hasLength(2));
    }
  });

  test('bibliography verifies once then renders one complete selection', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (request) async {
        calls++;
        if (calls == 1) {
          return _json(
            [_localSource('ABCD1234'), _localSource('EFGH5678')],
            headers: _databaseHeaders,
          );
        }
        expect(request.uri.queryParameters['format'], 'bib');
        expect(request.uri.queryParameters['itemKey'], 'ABCD1234,EFGH5678');
        expect(request.uri.queryParameters['style'], 'vancouver');
        expect(request.uri.queryParameters['locale'], 'fr-FR');
        expect(request.uri.queryParameters.containsKey('limit'), isFalse);
        expect(request.headers['Zotero-Server-ID'], 'original-database');
        return ZoteroHttpResponse(
          statusCode: 200,
          body: '<div>One complete bibliography</div>',
          headers: _databaseHeaders,
        );
      },
    );
    expect(
      await client.bibliography(
        local,
        itemKeys: ['ABCD1234', 'EFGH5678'],
        expectedItemUris: expected,
        style: 'vancouver',
        locale: 'fr-FR',
      ),
      '<div>One complete bibliography</div>',
    );
    expect(calls, 2);
  });

  test('aggregate expectations reject incomplete, extra and mixed profile maps before I/O', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async {
        calls++;
        return _json([]);
      },
    );
    final invalid = <Map<String, Uri>>[
      {},
      {'ABCD1234': _localUri('ABCD1234')},
      {...expected, 'IJKL9012': _localUri('IJKL9012')},
      {
        'ABCD1234': _localUri('ABCD1234'),
        'EFGH5678': _localUri('EFGH5678', profile: 'other123'),
      },
      {
        'ABCD1234': _localUri('EFGH5678'),
        'EFGH5678': _localUri('ABCD1234'),
      },
    ];
    for (final identities in invalid) {
      await expectLater(
        client.exportItems(
          local,
          ['ABCD1234', 'EFGH5678'],
          expectedItemUris: identities,
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.bibliography(
          local,
          itemKeys: ['ABCD1234', 'EFGH5678'],
          expectedItemUris: identities,
        ),
        throwsArgumentError,
      );
    }
    expect(calls, 0);
  });

  test('invalid bibliography formatting fails before the identity preflight', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async {
        calls++;
        return _json([]);
      },
    );
    await expectLater(
      client.bibliography(
        local,
        itemKeys: expected.keys.toList(),
        expectedItemUris: expected,
        style: 'https://example.org/style',
      ),
      throwsArgumentError,
    );
    await expectLater(
      client.bibliography(
        local,
        itemKeys: expected.keys.toList(),
        expectedItemUris: expected,
        locale: 'en-US&key=secret',
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('missing, duplicate, unexpected and substituted records stop before raw output', () async {
    final responses = <List<Map<String, Object?>>>[
      [],
      [_localSource('ABCD1234')],
      [_localSource('ABCD1234'), _localSource('ABCD1234')],
      [_localSource('ABCD1234'), _localSource('IJKL9012')],
      [
        _localSource('ABCD1234'),
        _localSource('EFGH5678', profile: 'other123'),
      ],
      [
        _localSource('ABCD1234'),
        _localSource('EFGH5678', cslId: 'CitationKey2026'),
      ],
    ];
    for (final response in responses) {
      for (final bibliography in [false, true]) {
        var calls = 0;
        final client = ZoteroClient.local(
          transport: (request) async {
            calls++;
            expect(request.uri.queryParameters['format'], 'json');
            return _json(response, headers: _databaseHeaders);
          },
        );
        await expectLater(
          bibliography
              ? client.bibliography(
                  local,
                  itemKeys: expected.keys.toList(),
                  expectedItemUris: expected,
                )
              : client.exportItems(
                  local,
                  expected.keys.toList(),
                  expectedItemUris: expected,
                ),
          throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
        );
        expect(calls, 1);
      }
    }
  });

  test('older desktops without a database pin refuse aggregate linked output', () async {
    for (final bibliography in [false, true]) {
      var calls = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          calls++;
          return _json([
            _localSource('ABCD1234'),
            _localSource('EFGH5678'),
          ]);
        },
      );
      await expectLater(
        bibliography
            ? client.bibliography(
                local,
                itemKeys: expected.keys.toList(),
                expectedItemUris: expected,
              )
            : client.exportItems(
                local,
                expected.keys.toList(),
                expectedItemUris: expected,
              ),
        throwsA(
          isA<ZoteroApiException>()
              .having((error) => error.kind, 'kind', ZoteroApiErrorKind.unavailable)
              .having((error) => error.message, 'recovery', contains('Zotero 10')),
        ),
      );
      expect(calls, 1);
    }
  });

  test('database changes between preflight and formatting never return output', () async {
    for (final status in [200, 412]) {
      var calls = 0;
      final client = ZoteroClient.local(
        transport: (request) async {
          calls++;
          if (calls == 1) {
            return _json(
              [_localSource('ABCD1234'), _localSource('EFGH5678')],
              headers: _databaseHeaders,
            );
          }
          expect(request.headers['Zotero-Server-ID'], 'original-database');
          return ZoteroHttpResponse(
            statusCode: status,
            body: 'Unrelated private bibliography',
            headers: {'Zotero-Server-ID': 'another-database'},
          );
        },
      );
      await expectLater(
        client.bibliography(
          local,
          itemKeys: expected.keys.toList(),
          expectedItemUris: expected,
        ),
        throwsA(_error(ZoteroApiErrorKind.unavailable)),
      );
      expect(calls, 2);
    }
  });

  test('preflight backoff prevents an immediate export request', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (_) async {
        calls++;
        return _json(
          [_localSource('ABCD1234'), _localSource('EFGH5678')],
          headers: {..._databaseHeaders, 'Backoff': '5'},
        );
      },
    );
    await expectLater(
      client.exportItems(
        local,
        expected.keys.toList(),
        expectedItemUris: expected,
      ),
      throwsA(_error(ZoteroApiErrorKind.rateLimited)),
    );
    expect(calls, 1);
  });

  test('numeric cloud identities use the same complete-selection verification', () async {
    var calls = 0;
    final client = ZoteroClient(
      transport: (request) async {
        calls++;
        expect(request.uri.path, '/users/1234/items');
        if (calls == 1) {
          return _json([_remoteSource('ABCD1234')]);
        }
        return ZoteroHttpResponse(statusCode: 200, body: 'verified RIS');
      },
    );
    expect(
      await client.exportItems(
        remote,
        ['ABCD1234'],
        format: ZoteroExportFormat.ris,
        expectedItemUris: {
          'ABCD1234': Uri.parse(
            'https://www.zotero.org/users/1234/items/ABCD1234',
          ),
        },
      ),
      'verified RIS',
    );
    expect(calls, 2);
  });

  test('returned CSL identities reject explicit ports before URI normalization', () async {
    for (final value in [
      'http://zotero.org:80/users/local/aBcD1234/items/ABCD1234',
      'https://zotero.org:443/users/local/aBcD1234/items/ABCD1234',
      'http://zotero.org:8080/users/local/aBcD1234/items/ABCD1234',
    ]) {
      final client = ZoteroClient.local(
        transport: (_) async => _json(
          _localSource('ABCD1234', cslId: value),
        ),
      );
      await expectLater(
        client.item(
          local,
          'ABCD1234',
          expectedCitationUri: _localUri('ABCD1234'),
        ),
        throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
        reason: value,
      );
    }
  });
  test('local aggregate output requires a usable preflight library version', () async {
    for (final version in [null, '-1', 'invalid']) {
      var calls = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          calls++;
          return _json(
            [_localSource('ABCD1234'), _localSource('EFGH5678')],
            headers: {
              'Zotero-Server-ID': 'original-database',
              'Last-Modified-Version': ?version,
            },
          );
        },
      );
      await expectLater(
        client.exportItems(
          local,
          expected.keys.toList(),
          expectedItemUris: expected,
        ),
        throwsA(
          _error(
            version == null
                ? ZoteroApiErrorKind.unavailable
                : ZoteroApiErrorKind.invalidResponse,
          ),
        ),
      );
      expect(calls, 1);
    }
  });

  test('deletion or modification between verification and output is detected', () async {
    for (final headers in <Map<String, String>>[
      {..._databaseHeaders, 'Last-Modified-Version': '43'},
      {'Zotero-Server-ID': 'original-database', 'Total-Results': '2'},
      {..._databaseHeaders, 'Total-Results': '1'},
      {..._databaseHeaders, 'Total-Results': 'invalid'},
    ]) {
      for (final bibliography in [false, true]) {
        var calls = 0;
        final client = ZoteroClient.local(
          transport: (_) async {
            calls++;
            return calls == 1
                ? _json(
                    [_localSource('ABCD1234'), _localSource('EFGH5678')],
                    headers: _databaseHeaders,
                  )
                : ZoteroHttpResponse(
                    statusCode: 200,
                    body: 'Incomplete or changed selection',
                    headers: headers,
                  );
          },
        );
        await expectLater(
          bibliography
              ? client.bibliography(
                  local,
                  itemKeys: expected.keys.toList(),
                  expectedItemUris: expected,
                )
              : client.exportItems(
                  local,
                  expected.keys.toList(),
                  expectedItemUris: expected,
                ),
          throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
        );
        expect(calls, 2);
      }
    }
  });

  test('metadata refresh requests no style and still proves local identity', () async {
    var calls = 0;
    final client = ZoteroClient.local(
      transport: (request) async {
        calls++;
        expect(request.uri.path, '/api/users/0/items/ABCD1234');
        expect(request.uri.queryParameters, {'include': 'data,csljson'});
        return _json(_localSource('ABCD1234'));
      },
    );
    final item = await client.item(
      local,
      'ABCD1234',
      expectedCitationUri: _localUri('ABCD1234'),
      includeFormatted: false,
      // These values are irrelevant when no formatting is requested.
      style: 'https://example.org/not-a-style',
      locale: 'not-a-locale!',
    );
    expect(item.citationUri, _localUri('ABCD1234'));
    expect(item.cslJson?['title'], 'Local source ABCD1234');
    expect(calls, 1);

    final wrongProfile = ZoteroClient.local(
      transport: (_) async => _json(
        _localSource('ABCD1234', profile: 'other123'),
      ),
    );
    await expectLater(
      wrongProfile.item(
        local,
        'ABCD1234',
        expectedCitationUri: _localUri('ABCD1234'),
        includeFormatted: false,
      ),
      throwsA(_error(ZoteroApiErrorKind.invalidResponse)),
    );
  });

}
