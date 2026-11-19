import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_format.dart';
import 'package:quds_office_editor/src/embed/word_zotero_snapshot.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

Map<String, Object?> _record({
  Object id = 'offline',
  String title = 'Source',
}) => {
  'id': id,
  'type': 'article-journal',
  'title': title,
  'author': [
    {'family': 'Hassan', 'given': 'Amal'},
  ],
  'issued': {
    'date-parts': [
      [2026, 11, 18],
    ],
  },
};

void main() {
  group('stored selection CSL JSON', () {
    test(
      'preserves offline metadata, literal text and unknown nested values',
      () {
        final data = {
          ..._record(id: 42, title: 'A < B & القدس — <i>Research</i>'),
          'DOI': '10.1234/δοκιμή',
          'URL': 'javascript:alert("inert metadata")',
          'custom': {
            'nested': [true, null, 3.5, '東京'],
          },
        };
        final item = zoteroImportCslJson(jsonEncode(data)).single;
        final before = jsonEncode(item.toJson());

        final output = zoteroSelectionCslJson([item]);

        expect(jsonDecode(output), [data]);
        expect(jsonEncode(item.toJson()), before);
        final restored = zoteroImportCslJson(output).single;
        expect(restored.itemData, data);
        expect(restored.id, 42);
        expect(restored.uris, isEmpty);
      },
    );

    test(
      'keeps explicit selection order and duplicate IDs without collapsing',
      () {
        final items = zoteroImportCslJson(
          jsonEncode([
            _record(id: 'same', title: 'First'),
            _record(id: 'same', title: 'Second'),
            _record(id: 'third', title: 'Third'),
          ]),
        );
        final selected = [items[1], items[2], items[0], items[1]];

        final restored = zoteroImportCslJson(zoteroSelectionCslJson(selected));

        expect(restored.map((item) => item.itemData!['title']), [
          'Second',
          'Third',
          'First',
          'Second',
        ]);
        expect(restored.map((item) => item.id), [
          'same',
          'third',
          'same',
          'same',
        ]);
      },
    );

    test('round-trips mixed personal, group, local and offline references', () {
      const uris = [
        'http://zotero.org/users/42/items/ABCD1234',
        'https://zotero.org/groups/42/items/ABCD1234',
        'http://zotero.org/users/local/LOCALKEY/items/ABCD1234',
      ];
      final items = [
        for (final uri in uris)
          ZoteroCitationItem.fromCsl(itemData: _record(id: 7), uris: [uri]),
        ...zoteroImportCslJson(jsonEncode(_record(id: 7))),
      ];

      final restored = zoteroImportCslJson(zoteroSelectionCslJson(items));

      expect(restored.map((item) => item.id), [...uris, 7]);
      expect(restored.map((item) => item.uris), [
        for (final uri in uris) [uri],
        <String>[],
      ]);
      expect(restored.map((item) => item.id).toSet(), hasLength(4));
    });

    test('retains synced and local aliases plus existing opaque metadata', () {
      const local = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
      const synced = 'https://www.zotero.org/users/42/items/ABCD1234';
      final item = ZoteroCitationItem.fromCsl(
        itemData: {
          ..._record(),
          'uris': ['opaque:stored-alias', local],
          'uri': 'opaque:single-alias',
        },
        uris: [local, synced],
      );
      final before = jsonEncode(item.toJson());

      final output = zoteroSelectionCslJson([item]);
      final decoded = (jsonDecode(output) as List).single as Map;

      expect(decoded['uris'], ['opaque:stored-alias', local, synced]);
      expect(decoded['uri'], 'opaque:single-alias');
      expect(zoteroImportCslJson(output).single.uris, [local, synced]);
      expect(jsonEncode(item.toJson()), before);
    });

    test(
      'copies reference data without turning citation modifiers into CSL',
      () {
        final data = _record();
        final item = ZoteroCitationItem.fromJson({
          'id': 'offline',
          'itemData': data,
          'uris': <String>[],
          'locator': '12–14',
          'label': 'page',
          'prefix': 'see',
          'suffix': 'and following',
          'suppress-author': true,
          'citation-custom': 'preserved in original',
        });
        final before = jsonEncode(item.toJson());

        expect(jsonDecode(zoteroSelectionCslJson([item])), [data]);
        expect(jsonEncode(item.toJson()), before);
      },
    );

    test('supplies the existing item ID when stored metadata has no ID', () {
      final data = _record()..remove('id');
      final item = ZoteroCitationItem.fromJson({'id': 17, 'itemData': data});

      final restored = zoteroImportCslJson(zoteroSelectionCslJson([item]));

      expect(restored.single.id, 17);
      expect(item.itemData!.containsKey('id'), isFalse);
    });

    test(
      'rejects incomplete records atomically instead of silently omitting them',
      () {
        final good = zoteroImportCslJson(jsonEncode(_record())).single;
        for (final data in <Map<String, Object?>?>[
          null,
          {'title': 'Missing type'},
          {'type': 'book'},
          {'type': 'book', 'title': 17},
          {'type': 'book', 'title': 'Invalid ID', 'id': <String, Object?>{}},
        ]) {
          final bad = ZoteroCitationItem.fromJson({
            'id': 'bad',
            'itemData': ?data,
          });
          expect(
            () => zoteroSelectionCslJson([good, bad]),
            throwsFormatException,
          );
        }
      },
    );

    test('refuses malformed linked aliases without replacing unknown data', () {
      const uri = 'http://zotero.org/users/42/items/ABCD1234';
      for (final malformed in <Object>[
        'bad',
        [uri, 7],
        {'unexpected': true},
      ]) {
        final item = ZoteroCitationItem.fromCsl(
          itemData: {..._record(), 'uris': malformed},
          uris: [uri],
        );
        final before = jsonEncode(item.toJson());
        expect(() => zoteroSelectionCslJson([item]), throwsFormatException);
        expect(jsonEncode(item.toJson()), before);
      }
    });

    test('keeps unlinked URI-looking data inert and unchanged', () {
      final data = {
        ..._record(),
        'uri': 'https://attacker.example/users/42/items/ABCD1234',
        'uris': ['http://localhost:23119/api/users/0/items/ABCD1234'],
      };
      final item = zoteroImportCslJson(jsonEncode(data)).single;

      final output = zoteroSelectionCslJson([item]);

      expect(jsonDecode(output), [data]);
      expect(zoteroImportCslJson(output).single.uris, isEmpty);
    });

    test('enforces the record bound and rejects an empty selection', () {
      final item = zoteroImportCslJson(jsonEncode(_record())).single;
      expect(() => zoteroSelectionCslJson([]), throwsFormatException);
      final full = zoteroSelectionCslJson(Iterable.generate(500, (_) => item));
      expect(zoteroImportCslJson(full), hasLength(500));
      expect(
        () => zoteroSelectionCslJson(Iterable.generate(501, (_) => item)),
        throwsFormatException,
      );
    });

    test('enforces the import byte limit for multilingual copied data', () {
      final item = ZoteroCitationItem.fromJson({
        'id': 'large',
        'itemData': _record(title: 'é' * (300 * 1024)),
      });
      expect(() => zoteroSelectionCslJson([item, item]), throwsFormatException);
    });
  });
}
