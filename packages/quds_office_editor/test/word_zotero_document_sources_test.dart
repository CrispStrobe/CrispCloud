import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_sources.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _personal = 'http://zotero.org/users/42/items/SOURCE01';
const _group = 'http://zotero.org/groups/42/items/SOURCE01';
const _local = 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01';

ZoteroCitationItem _item({
  Object id = 'same-id',
  String? title = 'Stored source',
  List<String> uris = const [],
  Map<String, dynamic> extra = const {},
}) => ZoteroCitationItem.fromJson({
  'id': id,
  if (title != null) 'itemData': {'id': id, 'type': 'book', 'title': title},
  if (uris.isNotEmpty) 'uris': uris,
  ...extra,
});

void main() {
  group('reusable document sources', () {
    test('clears occurrence options while preserving unknown source data', () {
      final item = _item(
        uris: [_local, _personal, 'opaque:source-alias'],
        extra: {
          'locator': '12–14',
          'label': 'chapter',
          'prefix': 'see ',
          'suffix': ', especially',
          'suppress-author': true,
          'author-only': true,
          'position': 2,
          'near-note': true,
          'first-reference-note-number': 4,
          'locator-date': '2026-11-18',
          'locator-extra': 'appendix',
          'source-extension': {
            'nested': [7, null, 'القدس'],
          },
          'itemData': {
            'id': 17,
            'type': 'book',
            'title': 'A < B and 東京',
            'page': '1–99',
            'custom': {'b': 2, 'a': 1},
          },
        },
      );
      final before = jsonEncode(item.toJson());

      final reused = zoteroReusableCitationItem(item);

      expect(reused.toJson(), {
        'id': 'same-id',
        'uris': [_local, _personal, 'opaque:source-alias'],
        'source-extension': {
          'nested': [7, null, 'القدس'],
        },
        'itemData': {
          'id': 17,
          'type': 'book',
          'title': 'A < B and 東京',
          'page': '1–99',
          'custom': {'b': 2, 'a': 1},
        },
      });
      expect(jsonEncode(item.toJson()), before);
      expect(identical(reused, item), isFalse);
    });

    test('a later data-less alias bridge unites earlier citations', () {
      final items = [
        _item(title: null, uris: [_local]),
        _item(title: 'First available snapshot', uris: [_personal]),
        _item(title: 'Later snapshot', uris: [_group]),
        _item(title: null, uris: [_local, _personal]),
        _item(title: null, uris: [_personal, _group, 'opaque:alias']),
      ];
      final before = jsonEncode(items.map((item) => item.toJson()).toList());

      final sources = zoteroDocumentReferences(items);

      expect(sources, hasLength(1));
      expect(sources.single.occurrences, 5);
      expect(
        sources.single.item.itemData!['title'],
        'First available snapshot',
      );
      expect(sources.single.item.uris, [
        _local,
        _personal,
        _group,
        'opaque:alias',
      ]);
      expect(jsonEncode(items.map((item) => item.toJson()).toList()), before);
    });

    test('same item key and CSL ID in different libraries remain separate', () {
      final sources = zoteroDocumentReferences([
        _item(uris: [_personal]),
        _item(uris: [_group]),
        _item(uris: [_local]),
        _item(uris: ['http://zotero.org/users/99/items/SOURCE01']),
        _item(),
      ]);

      expect(sources, hasLength(5));
      expect(
        sources.map((source) => source.selectionKey).toSet(),
        hasLength(5),
      );
      expect(sources.map((source) => source.occurrences), everyElement(1));
    });

    test('offline duplicate IDs retain different stored records', () {
      final sources = zoteroDocumentReferences([
        _item(title: 'First record'),
        _item(title: 'Second record'),
        _item(title: 'First record', extra: {'locator': '99'}),
      ]);

      expect(sources.map((source) => source.item.itemData!['title']), [
        'First record',
        'Second record',
      ]);
      expect(sources.map((source) => source.occurrences), [2, 1]);
      expect(sources.first.item.locator, isEmpty);
      expect(
        sources.map((source) => source.selectionKey).toSet(),
        hasLength(2),
      );
    });

    test('map key order does not split identical offline snapshots', () {
      final first = _item(
        extra: {
          'itemData': {
            'id': 42,
            'title': 'Same source',
            'type': 'book',
            'custom': {
              'z': 1,
              'a': [
                {'y': 2, 'x': 3},
              ],
            },
          },
        },
      );
      final second = ZoteroCitationItem.fromJson({
        'itemData': {
          'custom': {
            'a': [
              {'x': 3, 'y': 2},
            ],
            'z': 1,
          },
          'type': 'book',
          'title': 'Same source',
          'id': 42,
        },
        'id': 'same-id',
        'prefix': 'see ',
      });

      final sources = zoteroDocumentReferences([first, second]);

      expect(sources, hasLength(1));
      expect(sources.single.occurrences, 2);
      expect(sources.single.item.itemData, first.itemData);
    });

    test('first-cited order survives later snapshots and aliases', () {
      final sources = zoteroDocumentReferences([
        _item(title: null, uris: [_local]),
        _item(id: 'second', title: 'Second source'),
        _item(title: 'Recovered first title', uris: [_local, _personal]),
        _item(id: 'third', title: 'Third source'),
        _item(id: 'second', title: 'Second source', extra: {'suffix': ' old'}),
      ]);

      expect(sources.map((source) => source.item.itemData!['title']), [
        'Recovered first title',
        'Second source',
        'Third source',
      ]);
      expect(sources.map((source) => source.occurrences), [2, 2, 1]);
    });

    test(
      'linked selection keys remain stable across alias declaration order',
      () {
        final first = zoteroDocumentReferences([
          _item(uris: [_local, _personal, _group]),
        ]).single;
        final second = zoteroDocumentReferences([
          _item(uris: [_group, _personal, _local]),
        ]).single;

        expect(first.selectionKey, second.selectionKey);
        expect(first.item.uris, [_local, _personal, _group]);
        expect(second.item.uris, [_group, _personal, _local]);
      },
    );

    test('missing metadata retains identity without inventing a snapshot', () {
      final source = zoteroDocumentReferences([
        _item(title: null, uris: [_personal]),
        _item(
          title: null,
          uris: [_personal],
          extra: {'itemData': <String, dynamic>{}},
        ),
      ]).single;

      expect(source.occurrences, 2);
      expect(source.item.id, 'same-id');
      expect(source.item.itemData, isNull);
      expect(source.item.uris, [_personal]);
    });

    test('unrecognized URI metadata cannot join separate offline records', () {
      const hostile = 'https://other.example/users/42/items/SOURCE01';
      final sources = zoteroDocumentReferences([
        _item(title: 'First', uris: [hostile]),
        _item(title: 'Second', uris: [hostile]),
        _item(title: 'Linked', uris: [_personal]),
      ]);

      expect(sources, hasLength(3));
      expect(sources.map((source) => source.occurrences), [1, 1, 1]);
      expect(sources.first.item.uris, [hostile]);
    });

    test('empty input returns an immutable empty source list', () {
      final sources = zoteroDocumentReferences([]);

      expect(sources, isEmpty);
      expect(sources.clear, throwsUnsupportedError);
    });
  });
}
