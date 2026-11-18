import 'dart:convert';

import 'package:quds_office_engine/src/zotero/zotero_client.dart';
import 'package:test/test.dart';

Map<String, Object?> _item(
  ZoteroLibrary library, {
  String key = 'SOURCE01',
  String itemType = 'journalArticle',
  Map<String, Object?> details = const {},
  Map<String, Object?>? csl,
}) => {
  'key': key,
  'version': 7,
  'library': {'type': library.type.name, 'id': library.id},
  'data': {
    'key': key,
    'itemType': itemType,
    'title': 'Research & references',
    ...details,
  },
  'csljson':
      csl ??
      {
        'id': library.isLocalUser
            ? 'http://zotero.org/users/local/LOCALKEY/items/$key'
            : library.itemUri(key).toString(),
        'type': 'article-journal',
        'title': 'Embedded CSL title',
        'custom': {'preserve': true},
      },
};

ZoteroHttpResponse _json(Object value) =>
    ZoteroHttpResponse(statusCode: 200, body: jsonEncode(value));

void main() {
  final personal = ZoteroLibrary.user(42);

  test('new metadata defaults preserve existing model callers', () {
    final item = ZoteroItem(
      library: personal,
      key: 'SOURCE01',
      title: 'Existing source',
      itemType: 'book',
    );
    expect(item.abstractNote, isEmpty);
    expect(item.publicationTitle, isEmpty);
    expect(item.publisher, isEmpty);
    expect(item.tags, isEmpty);
    expect(item.citationUri, personal.itemUri('SOURCE01'));
    expect(item.isCitable, isTrue);
  });

  test('model tag names are exact, ordered, detached and immutable', () {
    final tags = ['Research', 'research', 'Research', '  research  ', 'القدس'];
    final item = ZoteroItem(
      library: personal,
      key: 'SOURCE01',
      title: 'A source',
      itemType: 'book',
      tags: tags,
    );
    tags
      ..clear()
      ..add('replacement');
    expect(item.tags, ['Research', 'research', '  research  ', 'القدس']);
    expect(() => item.tags.add('new'), throwsUnsupportedError);
    expect(() => item.tags[0] = 'changed', throwsUnsupportedError);
  });

  for (final library in [personal, ZoteroLibrary.group(84)]) {
    test(
      'online ${library.type.name} browse exposes details without extra requests',
      () async {
        final requests = <ZoteroHttpRequest>[];
        final source = _item(
          library,
          details: {
            'abstractNote': 'First paragraph.\n\nالقدس & 東京 <i>text</i>',
            'publicationTitle': 'Journal of Studies',
            'publisher': 'Research Press',
            'tags': [
              {'tag': 'Reviewed', 'type': 0},
              {'tag': 'automatic', 'type': 1},
              {'tag': 'Reviewed', 'type': 1},
            ],
          },
        );
        final client = ZoteroClient(
          transport: (request) async {
            requests.add(request);
            return _json([source]);
          },
        );

        final page = await client.items(library, collectionKey: 'COLL0001');
        final item = page.items.single;
        expect(item.abstractNote, 'First paragraph.\n\nالقدس & 東京 <i>text</i>');
        expect(item.publicationTitle, 'Journal of Studies');
        expect(item.publisher, 'Research Press');
        expect(item.tags, ['Reviewed', 'automatic']);
        expect(item.cslJson, source['csljson']);
        expect(item.cslJson!.containsKey('tags'), isFalse);
        expect(item.citationUri, library.itemUri('SOURCE01'));
        expect(item.sourceId, library.itemUri('SOURCE01').toString());
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.body, isNull);
        expect(requests.single.uri.queryParameters['include'], 'data,csljson');
        expect(
          requests.single.uri.path,
          '${library.apiPath}/collections/COLL0001/items/top',
        );
      },
    );
  }

  const publicationFields = {
    'blogPost': 'blogTitle',
    'bookSection': 'bookTitle',
    'conferencePaper': 'proceedingsTitle',
    'dictionaryEntry': 'dictionaryTitle',
    'encyclopediaArticle': 'encyclopediaTitle',
    'forumPost': 'forumTitle',
    'presentation': 'sessionTitle',
    'radioBroadcast': 'programTitle',
    'tvBroadcast': 'programTitle',
    'webpage': 'websiteTitle',
  };
  for (final entry in publicationFields.entries) {
    test('${entry.key} uses its Zotero publication-title field', () async {
      final client = ZoteroClient(
        transport: (_) async => _json(
          _item(
            personal,
            itemType: entry.key,
            details: {
              'publicationTitle': 'Generic fallback',
              for (final field in publicationFields.values)
                field: 'Container from $field',
            },
          ),
        ),
      );
      final item = await client.item(
        personal,
        'SOURCE01',
        includeFormatted: false,
      );
      expect(item.publicationTitle, 'Container from ${entry.value}');
    });
  }

  test('publication aliases fall back only to the generic field', () async {
    for (final value in <Object?>[null, '', 17, <String>[]]) {
      final client = ZoteroClient(
        transport: (_) async => _json(
          _item(
            personal,
            itemType: 'bookSection',
            details: {
              'bookTitle': value,
              'websiteTitle': 'Unrelated field',
              'publicationTitle': 'Compatible generic container',
            },
          ),
        ),
      );
      final item = await client.item(
        personal,
        'SOURCE01',
        includeFormatted: false,
      );
      expect(item.publicationTitle, 'Compatible generic container');
    }
    final client = ZoteroClient(
      transport: (_) async => _json(
        _item(personal, itemType: 'book', details: {'bookTitle': 'Unrelated'}),
      ),
    );
    final item = await client.item(
      personal,
      'SOURCE01',
      includeFormatted: false,
    );
    expect(item.publicationTitle, isEmpty);
  });

  test(
    'missing or malformed optional metadata does not reject a source',
    () async {
      for (final value in <Object?>[
        null,
        '',
        false,
        42,
        {'tag': 'Not a list'},
      ]) {
        final client = ZoteroClient(
          transport: (_) async => _json(
            _item(
              personal,
              details: {
                'abstractNote': value,
                'publicationTitle': value,
                'publisher': value,
                'tags': value,
              },
            ),
          ),
        );
        final item = await client.item(
          personal,
          'SOURCE01',
          includeFormatted: false,
        );
        expect(item.abstractNote, isEmpty);
        expect(item.publicationTitle, isEmpty);
        expect(item.publisher, isEmpty);
        expect(item.tags, isEmpty);
        expect(item.isCitable, isTrue);
        expect(item.cslJson!['title'], 'Embedded CSL title');
      }
    },
  );

  test(
    'invalid tag entries are ignored without normalizing valid names',
    () async {
      final names = [
        'Reviewed',
        'reviewed',
        '  padded  ',
        'two  spaces',
        'القدس & 東京',
        'either || both',
        r'\-literal',
        '-literal',
        'very long ' * 30,
      ];
      final client = ZoteroClient(
        transport: (_) async => _json(
          _item(
            personal,
            details: {
              'tags': [
                null,
                1,
                'not an object',
                <String, Object?>{},
                {'tag': null},
                {'tag': 7},
                {'tag': ''},
                for (final name in names) {'tag': name, 'type': 0},
                for (final name in names) {'tag': name, 'type': 1},
              ],
            },
          ),
        ),
      );
      final item = await client.item(
        personal,
        'SOURCE01',
        includeFormatted: false,
      );
      expect(item.tags, names);
      expect(() => normalizeZoteroTags([item.tags[5]]), throwsFormatException);
      expect(() => normalizeZoteroTags([item.tags[6]]), throwsFormatException);
      expect(
        () => normalizeZoteroTags([item.tags.last]),
        throwsFormatException,
      );
      expect(item.tags[2], '  padded  ');
    },
  );

  test(
    'catalog tag metadata is not limited by the active-filter count',
    () async {
      final names = List.generate(25, (index) => 'Topic $index');
      final client = ZoteroClient(
        transport: (_) async => _json([
          _item(
            personal,
            details: {
              'tags': [
                for (final name in names) {'tag': name},
              ],
            },
          ),
        ]),
      );
      expect((await client.items(personal)).items.single.tags, names);
    },
  );

  test(
    'desktop saved searches retain details and their persistent identity',
    () async {
      final local = ZoteroLibrary.localUser();
      final requests = <ZoteroHttpRequest>[];
      final source = _item(
        local,
        itemType: 'bookSection',
        details: {
          'abstractNote': 'Locally available abstract',
          'bookTitle': 'Collected Research',
          'publisher': 'Desktop Press',
          'tags': [
            {'tag': 'local tag'},
            {'tag': 'automatic', 'type': 1},
          ],
        },
      );
      final client = ZoteroClient.local(
        transport: (request) async {
          requests.add(request);
          return _json([
            {
              ...source,
              'csljson': jsonEncode([source['csljson']]),
            },
          ]);
        },
      );
      final page = await client.savedSearchItems(local, 'SEARCH01');
      final item = page.items.single;
      expect(item.abstractNote, 'Locally available abstract');
      expect(item.publicationTitle, 'Collected Research');
      expect(item.publisher, 'Desktop Press');
      expect(item.tags, ['local tag', 'automatic']);
      expect(item.cslJson, source['csljson']);
      expect(
        item.citationUri.toString(),
        'http://zotero.org/users/local/LOCALKEY/items/SOURCE01',
      );
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/api/users/0/searches/SEARCH01/items');
      expect(requests.single.uri.queryParameters['include'], 'data,csljson');
      expect(requests.single.headers['Zotero-API-Key'], isNull);
    },
  );

  test(
    'details do not invent a persistent URI for an unlinked desktop item',
    () async {
      final local = ZoteroLibrary.localUser();
      final client = ZoteroClient.local(
        transport: (_) async => _json(
          _item(
            local,
            details: {
              'abstractNote': 'Offline abstract',
              'tags': [
                {'tag': 'offline'},
              ],
            },
            csl: {
              'id': 'citation-key',
              'type': 'book',
              'title': 'Offline source',
            },
          ),
        ),
      );
      final item = await client.item(
        local,
        'SOURCE01',
        includeFormatted: false,
      );
      expect(item.abstractNote, 'Offline abstract');
      expect(item.tags, ['offline']);
      expect(item.citationUri, isNull);
      expect(item.cslJson!['id'], 'citation-key');
    },
  );

  test(
    'verified metadata batches expose details without modifying CSL',
    () async {
      final first = _item(
        personal,
        details: {
          'publisher': 'First press',
          'tags': [
            {'tag': 'first'},
          ],
        },
      );
      final second = _item(
        personal,
        key: 'SOURCE02',
        details: {
          'abstractNote': 'Second abstract',
          'tags': [
            {'tag': 'second'},
          ],
        },
      );
      final client = ZoteroClient(
        transport: (_) async => _json([second, first]),
      );
      final items = await client.metadataItems(
        personal,
        expectedItemUris: {
          'SOURCE01': personal.itemUri('SOURCE01'),
          'SOURCE02': personal.itemUri('SOURCE02'),
        },
      );
      expect(items.map((item) => item.key), ['SOURCE01', 'SOURCE02']);
      expect(items.first.publisher, 'First press');
      expect(items.first.tags, ['first']);
      expect(items.last.abstractNote, 'Second abstract');
      expect(items.last.tags, ['second']);
      expect(items.first.cslJson, first['csljson']);
      expect(items.last.cslJson, second['csljson']);
    },
  );

  test('optional details never weaken response identity checks', () async {
    final otherLibrary = ZoteroLibrary.user(99);
    final client = ZoteroClient(
      transport: (_) async => _json(
        _item(
          otherLibrary,
          details: {
            'abstractNote': 'Looks like the requested source',
            'publicationTitle': 'A matching journal',
            'tags': [
              {'tag': 'matching'},
            ],
          },
        ),
      ),
    );
    await expectLater(
      client.item(personal, 'SOURCE01', includeFormatted: false),
      throwsA(
        isA<ZoteroApiException>().having(
          (error) => error.kind,
          'kind',
          ZoteroApiErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test(
    'child records stay noncitable even when they contain details',
    () async {
      final local = ZoteroLibrary.localUser();
      final client = ZoteroClient.local(
        transport: (_) async => _json([
          {
            ..._item(
              local,
              itemType: 'note',
              details: {
                'abstractNote': 'Child metadata',
                'tags': [
                  {'tag': 'annotation'},
                ],
              },
            ),
            'csljson': '[]',
          },
        ]),
      );
      final item = (await client.savedSearchItems(
        local,
        'SEARCH01',
      )).items.single;
      expect(item.isCitable, isFalse);
      expect(item.cslJson, isNull);
      expect(item.abstractNote, 'Child metadata');
      expect(item.tags, ['annotation']);
    },
  );
}
