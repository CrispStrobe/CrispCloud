import 'dart:async';
import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _parentKey = 'SOURCE01';
const _serverId = 'child-catalog-database';

ZoteroHttpResponse _json(
  Object? value, {
  Map<String, String> headers = const {},
}) => ZoteroHttpResponse(
  statusCode: 200,
  body: jsonEncode(value),
  headers: headers,
);

Map<String, Object?> _child({
  String key = 'CHILD001',
  String parentKey = _parentKey,
  String kind = 'note',
  ZoteroLibrary? library,
  Map<String, Object?> data = const {},
}) {
  final scope = library ?? ZoteroLibrary.user(7);
  return {
    'key': key,
    'version': 12,
    'library': {'type': scope.type.name, 'id': scope.id},
    'data': {
      'key': key,
      'version': 12,
      'parentItem': parentKey,
      'itemType': kind,
      ...data,
    },
  };
}

Map<String, Object?> _parent({bool local = false}) => {
  'key': _parentKey,
  'version': 11,
  'library': {'type': 'user', 'id': local ? 0 : 7},
  'data': {'key': _parentKey, 'itemType': 'book', 'title': 'Parent reference'},
  'csljson': {
    'id': local
        ? 'http://zotero.org/users/local/LOCALKEY/items/$_parentKey'
        : 'http://zotero.org/users/7/items/$_parentKey',
    'type': 'book',
    'title': 'Parent reference',
  },
};

TypeMatcher<ZoteroApiException> get _invalid => isA<ZoteroApiException>()
    .having((error) => error.kind, 'kind', ZoteroApiErrorKind.invalidResponse);

Matcher get _unavailable => isA<ZoteroApiException>().having(
  (error) => error.kind,
  'kind',
  ZoteroApiErrorKind.unavailable,
);

Future<void> _reject(Object? response) async {
  final client = ZoteroClient(transport: (_) async => _json(response));
  await expectLater(
    client.itemChildren(ZoteroLibrary.user(7), _parentKey),
    throwsA(_invalid),
  );
}

void main() {
  for (final library in [ZoteroLibrary.user(7), ZoteroLibrary.group(42)]) {
    test(
      'online ${library.type.name} child pages request metadata only',
      () async {
        final requests = <ZoteroHttpRequest>[];
        final client = ZoteroClient(
          apiKey: 'child-catalog-secret',
          transport: (request) async {
            requests.add(request);
            return _json(
              [
                _child(
                  library: library,
                  data: {'note': '<p>Research &amp; evidence</p>'},
                ),
                _child(
                  library: library,
                  key: 'CHILD002',
                  kind: 'attachment',
                  data: {
                    'title': 'Full text',
                    'note': '<p>An attachment note</p>',
                    'filename': 'paper.pdf',
                    'contentType': 'application/pdf',
                    'linkMode': 'imported_file',
                    'url': 'https://example.org/paper',
                  },
                ),
              ],
              headers: {'Total-Results': '52', 'Last-Modified-Version': '37'},
            );
          },
        );
        final page = await client.itemChildren(
          library,
          _parentKey,
          expectedLocalServerId: 'never-sent-online',
        );
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.body, isNull);
        expect(request.followRedirects, isFalse);
        expect(request.uri.origin, 'https://api.zotero.org');
        expect(
          request.uri.path,
          '${library.apiPath}/items/$_parentKey/children',
        );
        expect(request.uri.queryParameters, {
          'start': '0',
          'limit': '50',
          'format': 'json',
          'include': 'data',
          'sort': 'dateAdded',
          'direction': 'asc',
        });
        expect(request.headers, {
          'Zotero-API-Version': '3',
          'Zotero-API-Key': 'child-catalog-secret',
        });
        expect(request.toString(), isNot(contains('child-catalog-secret')));
        expect(request.uri.toString(), isNot(contains('never-sent-online')));
        expect(page.start, 0);
        expect(page.limit, 50);
        expect(page.totalResults, 52);
        expect(page.nextStart, 50);
        expect(page.lastModifiedVersion, 37);
        expect(page.items.map((item) => item.kind), [
          ZoteroItemChildKind.note,
          ZoteroItemChildKind.attachment,
        ]);
        final note = page.items.first;
        expect(note.library, library);
        expect(note.parentKey, _parentKey);
        expect(note.version, 12);
        expect(note.title, isEmpty);
        expect(note.noteHtml, '<p>Research &amp; evidence</p>');
        final attachment = page.items.last;
        expect(attachment.title, 'Full text');
        expect(attachment.noteHtml, '<p>An attachment note</p>');
        expect(attachment.filename, 'paper.pdf');
        expect(attachment.contentType, 'application/pdf');
        expect(attachment.linkMode, 'imported_file');
        expect(attachment.url, 'https://example.org/paper');
        expect(() => page.items.clear(), throwsUnsupportedError);
      },
    );
  }

  test('empty pages and omitted optional metadata remain explicit', () async {
    var calls = 0;
    final client = ZoteroClient(
      transport: (_) async => _json(++calls == 1 ? [] : [_child()]),
    );
    final empty = await client.itemChildren(ZoteroLibrary.user(7), _parentKey);
    expect(empty.items, isEmpty);
    expect(empty.totalResults, isNull);
    expect(empty.hasMore, isFalse);
    final note = (await client.itemChildren(
      ZoteroLibrary.user(7),
      _parentKey,
    )).items.single;
    expect(note.title, isEmpty);
    expect(note.noteHtml, isEmpty);
    expect(note.filename, isEmpty);
    expect(note.contentType, isEmpty);
    expect(note.linkMode, isEmpty);
    expect(note.url, isEmpty);
  });

  test('linked-file paths are not substituted for absent filenames', () async {
    final client = ZoteroClient(
      transport: (_) async => _json([
        _child(
          kind: 'attachment',
          data: {
            'linkMode': 'linked_file',
            'path': '/private/research/notes.pdf',
          },
        ),
      ]),
    );
    final child = (await client.itemChildren(
      ZoteroLibrary.user(7),
      _parentKey,
    )).items.single;
    expect(child.linkMode, 'linked_file');
    expect(child.filename, isEmpty);
    expect(child.url, isEmpty);
  });

  test('markup and future attachment modes remain uninterpreted data', () async {
    const html =
        '<p>القدس 📚 &lt; 3</p><script>neverRun()</script><img src="file:///x">';
    final client = ZoteroClient(
      transport: (_) async => _json([
        _child(
          kind: 'attachment',
          data: {
            'note': html,
            'linkMode': 'future_mode',
            'url': 'javascript:neverRun()',
          },
        ),
      ]),
    );
    final child = (await client.itemChildren(
      ZoteroLibrary.user(7),
      _parentKey,
    )).items.single;
    expect(child.noteHtml, html);
    expect(child.linkMode, 'future_mode');
    expect(child.url, 'javascript:neverRun()');
  });

  test(
    'pagination extracts an offset and rebuilds the selected parent route',
    () async {
      final requests = <ZoteroHttpRequest>[];
      final client = ZoteroClient(
        transport: (request) async {
          requests.add(request);
          return _json(
            [_child()],
            headers: {
              if (requests.length == 1)
                'Link':
                    '<https://api.zotero.org/users/7/items/SOURCE01/children?start=75&include=bib>; rel="next"',
            },
          );
        },
      );
      final page = await client.itemChildren(
        ZoteroLibrary.user(7),
        _parentKey,
        start: 25,
        limit: 25,
      );
      expect(page.nextStart, 75);
      await client.itemChildren(
        ZoteroLibrary.user(7),
        _parentKey,
        start: page.nextStart!,
        limit: 25,
      );
      expect(requests.last.uri.queryParameters['start'], '75');
      expect(requests.last.uri.queryParameters['include'], 'data');
      expect(requests.last.uri.path, '/users/7/items/SOURCE01/children');
    },
  );

  for (final next in [
    'https://other.example/users/7/items/SOURCE01/children?start=50',
    'https://api.zotero.org/users/7/items/OTHER001/children?start=50',
    'https://api.zotero.org/users/7/items/SOURCE01/children?start=0',
    'https://api.zotero.org/users/7/items/SOURCE01/children?start=50&key=secret',
  ]) {
    test('rejects an invalid child pagination target $next', () async {
      final client = ZoteroClient(
        transport: (_) async =>
            _json([_child()], headers: {'Link': '<$next>; rel="next"'}),
      );
      await expectLater(
        client.itemChildren(ZoteroLibrary.user(7), _parentKey),
        throwsA(_invalid),
      );
    });
  }

  test('invalid request arguments never reach the transport', () async {
    var requests = 0;
    final client = ZoteroClient(
      transport: (_) async {
        requests++;
        return _json([]);
      },
    );
    final library = ZoteroLibrary.user(7);
    for (final key in ['', 'short', 'lower001', 'SOURCE01/children']) {
      await expectLater(client.itemChildren(library, key), throwsArgumentError);
    }
    for (final (start, limit) in [(-1, 50), (0, 0), (0, 101)]) {
      await expectLater(
        client.itemChildren(library, _parentKey, start: start, limit: limit),
        throwsArgumentError,
      );
    }
    await expectLater(
      client.itemChildren(ZoteroLibrary.localUser(), _parentKey),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  test('a malformed or substituted child refuses the entire page', () async {
    final cases = <Map<String, Object?>>[
      _child(parentKey: 'OTHER001'),
      _child(key: _parentKey),
      _child(kind: 'book'),
      _child(kind: 'annotation'),
      _child(data: {'parentItem': false}),
      _child(data: {'parentItem': 'bad'}),
      _child(data: {'key': 'OTHER001'}),
      _child(data: {'key': 123}),
      _child(data: {'version': 13}),
      // A fractional value stays non-integral after both VM and JS encoding.
      _child(data: {'version': 12.5}),
      _child()..['key'] = 'bad',
      _child()..['version'] = -1,
      _child()..['version'] = '12',
      _child()..remove('version'),
      _child()..['data'] = [],
      _child()..remove('library'),
      _child()..['library'] = {'type': 'group', 'id': 7},
      _child()..['library'] = {'type': 'user', 'id': 8},
      _child()..['library'] = {'type': 'user', 'id': '7'},
    ];
    for (final bad in cases) {
      await _reject([_child(key: 'GOOD0001'), bad]);
    }
  });

  test(
    'duplicate keys, excess records and malformed envelopes are refused',
    () async {
      await _reject([_child(), _child()]);
      await _reject({
        'items': [_child()],
      });
      await _reject([null]);
      await _reject('not a page');
      final client = ZoteroClient(
        transport: (_) async => _json([_child(), _child(key: 'CHILD002')]),
      );
      await expectLater(
        client.itemChildren(ZoteroLibrary.user(7), _parentKey, limit: 1),
        throwsA(_invalid),
      );
    },
  );

  for (final name in [
    'title',
    'note',
    'filename',
    'contentType',
    'linkMode',
    'url',
  ]) {
    test(
      '$name rejects wrong types and malformed Unicode without truncation',
      () async {
        for (final value in <Object?>[
          null,
          42,
          false,
          <String>[],
          '\ud800',
          '\udc00',
        ]) {
          await _reject([
            _child(data: {name: value}),
          ]);
        }
        final bound = name == 'note' ? 1024 * 1024 : 8192;
        await _reject([
          _child(data: {name: 'x' * (bound + 1)}),
        ]);
        final client = ZoteroClient(
          transport: (_) async => _json([
            _child(data: {name: 'x' * bound}),
          ]),
        );
        final page = await client.itemChildren(
          ZoteroLibrary.user(7),
          _parentKey,
        );
        expect(page.items, hasLength(1));
      },
    );
  }

  test(
    'note HTML bound counts UTF-8 bytes without truncating Unicode',
    () async {
      final boundary = '${'€' * (1024 * 1024 ~/ 3)}a';
      expect(utf8.encode(boundary), hasLength(1024 * 1024));
      final client = ZoteroClient(
        transport: (_) async => _json([
          _child(data: {'note': boundary}),
        ]),
      );
      final child = (await client.itemChildren(
        ZoteroLibrary.user(7),
        _parentKey,
      )).items.single;
      expect(child.noteHtml, boundary);
      await _reject([
        _child(data: {'note': '${boundary}a'}),
      ]);
    },
  );

  test(
    'response limit counts UTF-8 bytes before decoding child records',
    () async {
      final body = '€' * (3 * 1024 * 1024);
      expect(body.length, lessThan(8 * 1024 * 1024));
      final client = ZoteroClient(
        transport: (_) async => ZoteroHttpResponse(statusCode: 200, body: body),
      );
      await expectLater(
        client.itemChildren(ZoteroLibrary.user(7), _parentKey),
        throwsA(
          _invalid.having(
            (error) => error.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    },
  );

  test(
    'malformed pagination/version headers and malformed JSON are refused',
    () async {
      for (final header in ['Total-Results', 'Last-Modified-Version']) {
        for (final value in ['-1', 'not-a-number']) {
          final client = ZoteroClient(
            transport: (_) async => _json([_child()], headers: {header: value}),
          );
          await expectLater(
            client.itemChildren(ZoteroLibrary.user(7), _parentKey),
            throwsA(_invalid),
          );
        }
      }
      final client = ZoteroClient(
        transport: (_) async => ZoteroHttpResponse(statusCode: 200, body: '{'),
      );
      await expectLater(
        client.itemChildren(ZoteroLibrary.user(7), _parentKey),
        throwsA(_invalid),
      );
    },
  );

  test('contradictory child totals and empty next pages are refused', () async {
    final cases = <(List<Object?>, Map<String, String>)>[
      ([_child()], {'Total-Results': '0'}),
      ([], {'Total-Results': '51'}),
      (
        [_child()],
        {
          'Total-Results': '1',
          'Link':
              '<https://api.zotero.org/users/7/items/SOURCE01/children?start=50>; rel="next"',
        },
      ),
    ];
    for (final (records, headers) in cases) {
      final client = ZoteroClient(
        transport: (_) async => _json(records, headers: headers),
      );
      await expectLater(
        client.itemChildren(ZoteroLibrary.user(7), _parentKey),
        throwsA(_invalid),
      );
    }
  });

  for (final library in [ZoteroLibrary.localUser(), ZoteroLibrary.group(42)]) {
    test(
      'local ${library.type.name} child reads retain the parent database pin',
      () async {
        final requests = <ZoteroHttpRequest>[];
        final client = ZoteroClient.local(
          transport: (request) async {
            requests.add(request);
            if (request.uri.path == '/api/') {
              return ZoteroHttpResponse(
                statusCode: 200,
                body: 'Local API',
                headers: {
                  'Zotero-API-Version': '3',
                  'Zotero-Server-ID': _serverId,
                },
              );
            }
            return _json(
              [_child(library: library)],
              headers: {'Zotero-Server-ID': _serverId},
            );
          },
        );
        await client.probeLocal();
        final page = await client.itemChildren(
          library,
          _parentKey,
          expectedLocalServerId: _serverId,
          start: 50,
          limit: 25,
        );
        expect(page.items.single.library, library);
        expect(requests.last.uri.origin, 'http://localhost:23119');
        expect(
          requests.last.uri.path,
          '/api${library.apiPath}/items/SOURCE01/children',
        );
        expect(requests.last.uri.queryParameters['start'], '50');
        expect(requests.last.uri.queryParameters['limit'], '25');
        expect(requests.last.headers, {
          'Zotero-API-Version': '3',
          'Zotero-Allowed-Request': '1',
          'Zotero-Server-ID': _serverId,
        });
      },
    );
  }

  test(
    'local alias permits a logged-in numeric user in the child envelope',
    () async {
      final client = ZoteroClient.local(
        transport: (request) async => request.uri.path == '/api/'
            ? ZoteroHttpResponse(
                statusCode: 200,
                body: 'Local API',
                headers: {
                  'Zotero-API-Version': '3',
                  'Zotero-Server-ID': _serverId,
                },
              )
            : _json([_child()], headers: {'Zotero-Server-ID': _serverId}),
      );
      await client.probeLocal();
      expect(
        (await client.itemChildren(
          ZoteroLibrary.localUser(),
          _parentKey,
          expectedLocalServerId: _serverId,
        )).items.single.key,
        'CHILD001',
      );
    },
  );

  test(
    'unidentified local client rejects child reads without a request',
    () async {
      var requests = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          requests++;
          return _json([]);
        },
      );
      for (final expected in <String?>[null, _serverId]) {
        await expectLater(
          client.itemChildren(
            ZoteroLibrary.localUser(),
            _parentKey,
            expectedLocalServerId: expected,
          ),
          throwsA(_unavailable),
        );
      }
      expect(requests, 0);
    },
  );

  test(
    'identified client rejects missing or different parent provenance before dispatch',
    () async {
      var requests = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          requests++;
          return ZoteroHttpResponse(
            statusCode: 200,
            body: 'Local API',
            headers: {'Zotero-API-Version': '3', 'Zotero-Server-ID': _serverId},
          );
        },
      );
      await client.probeLocal();
      for (final expected in <String?>[null, 'other-database']) {
        await expectLater(
          client.itemChildren(
            ZoteroLibrary.localUser(),
            _parentKey,
            expectedLocalServerId: expected,
          ),
          throwsA(_unavailable),
        );
      }
      expect(requests, 1);
    },
  );

  for (final responseId in <String?>[null, 'changed-database']) {
    test(
      'local child reply with database ID $responseId is rejected',
      () async {
        final client = ZoteroClient.local(
          transport: (request) async => request.uri.path == '/api/'
              ? ZoteroHttpResponse(
                  statusCode: 200,
                  body: 'Local API',
                  headers: {
                    'Zotero-API-Version': '3',
                    'Zotero-Server-ID': _serverId,
                  },
                )
              : _json(
                  [_child(library: ZoteroLibrary.localUser())],
                  headers: {'Zotero-Server-ID': ?responseId},
                ),
        );
        await client.probeLocal();
        await expectLater(
          client.itemChildren(
            ZoteroLibrary.localUser(),
            _parentKey,
            expectedLocalServerId: _serverId,
          ),
          throwsA(_unavailable),
        );
      },
    );
  }

  test('local server rejection keeps a 412 database change explicit', () async {
    final client = ZoteroClient.local(
      transport: (request) async => request.uri.path == '/api/'
          ? ZoteroHttpResponse(
              statusCode: 200,
              body: 'Local API',
              headers: {
                'Zotero-API-Version': '3',
                'Zotero-Server-ID': _serverId,
              },
            )
          : ZoteroHttpResponse(
              statusCode: 412,
              body: 'private database details',
            ),
    );
    await client.probeLocal();
    await expectLater(
      client.itemChildren(
        ZoteroLibrary.localUser(),
        _parentKey,
        expectedLocalServerId: _serverId,
      ),
      throwsA(
        isA<ZoteroApiException>()
            .having(
              (error) => error.kind,
              'kind',
              ZoteroApiErrorKind.unavailable,
            )
            .having((error) => error.statusCode, 'status', 412)
            .having(
              (error) => error.message,
              'message',
              isNot(contains('private')),
            ),
      ),
    );
  });

  for (final source in ['page', 'single', 'batch']) {
    test(
      'local $source catalog captures provenance without changing CSL data',
      () async {
        final client = ZoteroClient.local(
          transport: (request) async => _json(
            source == 'single' ? _parent(local: true) : [_parent(local: true)],
            headers: {'Zotero-Server-ID': _serverId},
          ),
        );
        final library = ZoteroLibrary.localUser();
        final ZoteroItem parent;
        if (source == 'page') {
          parent = (await client.items(library)).items.single;
        } else if (source == 'single') {
          parent = await client.item(
            library,
            _parentKey,
            includeFormatted: false,
          );
        } else {
          parent = (await client.metadataItems(
            library,
            expectedItemUris: {
              _parentKey: Uri.parse(
                'http://zotero.org/users/local/LOCALKEY/items/$_parentKey',
              ),
            },
          )).single;
        }
        expect(parent.localServerId, _serverId);
        expect(jsonEncode(parent.cslJson), isNot(contains(_serverId)));
        expect(parent.citationUri.toString(), isNot(contains(_serverId)));
        final citation = ZoteroCitationItem.fromCsl(
          itemData: parent.cslJson!,
          uris: [parent.canonicalUri.toString()],
        );
        expect(jsonEncode(citation.toJson()), isNot(contains(_serverId)));
      },
    );
  }

  test('online catalog ignores a supplied server-ID header', () async {
    final client = ZoteroClient(
      transport: (_) async =>
          _json([_parent()], headers: {'Zotero-Server-ID': _serverId}),
    );
    final parent = (await client.items(ZoteroLibrary.user(7))).items.single;
    expect(parent.localServerId, isNull);
  });

  test(
    'headerless parent stays unidentified after another response pins a database',
    () async {
      var requests = 0;
      final client = ZoteroClient.local(
        transport: (_) async {
          requests++;
          return _json(
            [_parent(local: true)],
            headers: {if (requests > 1) 'Zotero-Server-ID': _serverId},
          );
        },
      );
      final parent = (await client.items(
        ZoteroLibrary.localUser(),
      )).items.single;
      final newer = (await client.items(
        ZoteroLibrary.localUser(),
      )).items.single;
      expect(parent.localServerId, isNull);
      expect(newer.localServerId, _serverId);
      await expectLater(
        client.itemChildren(
          parent.library,
          parent.key,
          expectedLocalServerId: parent.localServerId,
        ),
        throwsA(_unavailable),
      );
      expect(requests, 2);
    },
  );

  test(
    'concurrent catalog replies never borrow another response database ID',
    () async {
      final headerless = Completer<ZoteroHttpResponse>();
      final identified = Completer<ZoteroHttpResponse>();
      var requests = 0;
      final client = ZoteroClient.local(
        transport: (_) =>
            ++requests == 1 ? headerless.future : identified.future,
      );
      final olderFuture = client.items(ZoteroLibrary.localUser());
      final newerFuture = client.items(ZoteroLibrary.localUser());
      headerless.complete(_json([_parent(local: true)]));
      identified.complete(
        _json([_parent(local: true)], headers: {'Zotero-Server-ID': _serverId}),
      );
      final older = (await olderFuture).items.single;
      final newer = (await newerFuture).items.single;
      expect(older.localServerId, isNull);
      expect(newer.localServerId, _serverId);
    },
  );

  test(
    'child requests share the online pause without an automatic retry',
    () async {
      var now = DateTime.utc(2026, 11, 20);
      var requests = 0;
      final state = ZoteroBackoffState();
      final client = ZoteroClient(
        clock: () => now,
        backoffState: state,
        transport: (_) async {
          requests++;
          return ZoteroHttpResponse(
            statusCode: 429,
            body: 'private backend details',
            headers: {'Retry-After': '30'},
          );
        },
      );
      await expectLater(
        client.itemChildren(ZoteroLibrary.user(7), _parentKey),
        throwsA(
          isA<ZoteroApiException>().having(
            (error) => error.kind,
            'kind',
            ZoteroApiErrorKind.rateLimited,
          ),
        ),
      );
      final replacement = ZoteroClient(
        clock: () => now,
        backoffState: state,
        transport: (_) async {
          requests++;
          return _json([]);
        },
      );
      await expectLater(
        replacement.itemChildren(ZoteroLibrary.user(7), _parentKey),
        throwsA(
          isA<ZoteroApiException>().having(
            (error) => error.retryAfter,
            'remaining pause',
            const Duration(seconds: 30),
          ),
        ),
      );
      expect(requests, 1);
      now = now.add(const Duration(seconds: 31));
      expect(
        (await replacement.itemChildren(
          ZoteroLibrary.user(7),
          _parentKey,
        )).items,
        isEmpty,
      );
      expect(requests, 2);
    },
  );

  test('transport failures never expose private exception contents', () async {
    final client = ZoteroClient(
      transport: (_) async => throw StateError('secret API key and note text'),
    );
    await expectLater(
      client.itemChildren(ZoteroLibrary.user(7), _parentKey),
      throwsA(
        isA<ZoteroApiException>()
            .having((error) => error.kind, 'kind', ZoteroApiErrorKind.network)
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret')),
            ),
      ),
    );
  });

  test(
    'public child models reject invalid keys, self parents and versions',
    () {
      for (final (key, parent, version) in [
        ('bad', _parentKey, 0),
        ('CHILD001', 'bad', 0),
        (_parentKey, _parentKey, 0),
        ('CHILD001', _parentKey, -1),
      ]) {
        expect(
          () => ZoteroItemChild(
            library: ZoteroLibrary.user(7),
            key: key,
            parentKey: parent,
            kind: ZoteroItemChildKind.note,
            version: version,
          ),
          throwsArgumentError,
        );
      }
    },
  );
}
