import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _local = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
const _account = 'http://zotero.org/users/42/items/ABCD1234';
const _merged = 'http://zotero.org/users/42/items/EFGH5678';

ZoteroCitationItem _source(
  String title,
  List<String> uris, {
  Object id = 17,
  bool hasSnapshot = true,
}) => ZoteroCitationItem.fromJson({
  'id': id,
  'uris': uris,
  if (hasSnapshot)
    'itemData': {
      'id': id,
      'type': 'book',
      'title': title,
      'futureSourceData': {
        'nested': [title, 17],
      },
    },
  'locator': '8–10',
  'label': 'page',
  'prefix': 'see',
  'suffix': 'and following',
  'futureItemData': {'keep': true},
});

WmlDocument _document(List<ZoteroCitationItem> items) {
  final paragraphs = <WmlParagraph>[];
  for (var index = 0; index < items.length; index++) {
    final paragraph = WmlParagraph();
    WordZotero.insertCitation(
      paragraph,
      ZoteroCitation(
        citationId: 'source-$index',
        plainCitation: '(Source $index)',
        items: [items[index]],
      ),
    );
    paragraphs.add(paragraph);
  }
  return WmlDocument(sections: [WmlSection(blocks: paragraphs)]);
}

void main() {
  test('late URI bridge joins previously distinct embedded snapshots', () {
    final sources = [
      _source('Earliest snapshot', [_local]),
      _source('Account snapshot', [_account]),
      _source('Bridge snapshot', [_local, _account]),
    ];
    final before = jsonEncode(sources.map((item) => item.toJson()).toList());
    final result = WordZotero.distinctEmbeddedItems(sources);
    expect(result, hasLength(1));
    expect(result.single, same(sources.first.itemData));
    expect(result.single['futureSourceData'], {
      'nested': ['Earliest snapshot', 17],
    });
    expect(jsonEncode(sources.map((item) => item.toJson()).toList()), before);
  });

  for (final order in <List<int>>[
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ]) {
    test('alias groups retain their first snapshot for order $order', () {
      final sources = [
        _source('Local', [_local]),
        _source('Account', [_account]),
        _source('Both identities', [_local, _account]),
      ];
      final ordered = order.map((index) => sources[index]).toList();
      final result = WordZotero.distinctEmbeddedItems(ordered);
      expect(result, [ordered.first.itemData]);
    });
  }

  test('missing-snapshot bridges resolve transitive aliases', () {
    final first = _source('First usable snapshot', [_local]);
    final unrelated = _source('Independent source', [
      'http://zotero.org/groups/42/items/ABCD1234',
    ]);
    final sources = [
      _source('No snapshot', [_local], hasSnapshot: false),
      first,
      unrelated,
      _source('Account duplicate', [_account]),
      _source('Merged duplicate', [_merged]),
      _source('Local/account bridge', [_local, _account], hasSnapshot: false),
      _source('Account/merged bridge', [_account, _merged], hasSnapshot: false),
    ];
    final result = WordZotero.distinctEmbeddedItems(sources);
    expect(result, [first.itemData, unrelated.itemData]);
  });

  test('source groups keep first-available-snapshot ordering', () {
    final independent = _source('Independent', [_merged]);
    final available = _source('Available later', [_account]);
    expect(
      WordZotero.distinctEmbeddedItems([
        _source('Not available', [_local], hasSnapshot: false),
        independent,
        available,
        _source('Bridge', [_local, _account], hasSnapshot: false),
      ]),
      [independent.itemData, available.itemData],
    );
  });

  test('canonical aliases join while unrelated keys and CSL IDs do not', () {
    final sources = [
      _source('Local', [_local]),
      _source('Local alias', [
        'https://www.zotero.org/users/local/LOCALKEY/items/ABCD1234',
      ]),
      _source('Other local profile', [
        'http://zotero.org/users/local/OTHERKEY/items/ABCD1234',
      ]),
      _source('Account', [_account]),
      _source('Account alias', [
        'HTTPS://WWW.ZOTERO.ORG/users/42/items/ABCD1234',
      ]),
      _source('Group', ['http://zotero.org/groups/42/items/ABCD1234']),
      _source('Other account', ['http://zotero.org/users/99/items/ABCD1234']),
      _source('Other key', [_merged]),
      _source('Offline', []),
      _source('Repeated offline', []),
      _source('Other offline', [], id: 18),
    ];
    expect(
      WordZotero.distinctEmbeddedItems(sources).map((item) => item['title']),
      [
        'Local',
        'Other local profile',
        'Account',
        'Group',
        'Other account',
        'Other key',
        'Offline',
        'Other offline',
      ],
    );
  });

  test('unknown URI values cannot collide with another identity namespace', () {
    final sources = [
      _source('Offline', []),
      _source('Unknown URI', ['id:17']),
      _source('Linked', [_account]),
      _source('Unknown canonical-looking URI', [
        'zotero:/users/42/items/ABCD1234',
      ]),
    ];
    expect(
      WordZotero.distinctEmbeddedItems(sources),
      sources.map((item) => item.itemData),
    );
  });

  test(
    'malformed imported URI paths are not normalized into source aliases',
    () {
      final malformed = [
        'http://zotero.org/users/42/items/%41BCD1234',
        'http://zotero.org/users/42/extra/../items/ABCD1234',
        'https://zotero.org:443/users/42/items/ABCD1234',
        'http://zotero.org/users/42/items/ABCD1234\n',
        'http://zotero.org/users/42/items/ABCD1234?key=value',
        'http://zotero.org/users/42/items/ABCD1234#fragment',
      ];
      final sources = [
        _source('Canonical', [_account]),
        for (var index = 0; index < malformed.length; index++)
          _source('Imported $index', [malformed[index]]),
      ];
      expect(
        WordZotero.distinctEmbeddedItems([
          ...sources,
          _source('Repeated unknown URI', [malformed.first]),
        ]),
        sources.map((item) => item.itemData),
      );
    },
  );

  test('groups without embedded snapshots are omitted', () {
    expect(WordZotero.distinctEmbeddedItems([]), isEmpty);
    expect(
      WordZotero.distinctEmbeddedItems([
        _source('Unavailable', [_local], hasSnapshot: false),
        _source('Bridge', [_local, _account], hasSnapshot: false),
        _source('Offline', [], hasSnapshot: false),
      ]),
      isEmpty,
    );
  });

  test('document export resolves aliases without rewriting saved fields', () {
    final sources = [
      _source('Local snapshot', [_local]),
      _source('Account snapshot', [_account]),
      _source('Merged snapshot', [_merged]),
      _source('Bridge', [_local, _account], hasSnapshot: false),
      _source('Final bridge', [_merged, _account], hasSnapshot: false),
    ];
    var document = _document(sources);
    final instructions = WordZotero.fields(
      document,
    ).map((field) => field.instruction).toList();
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(WordZotero.embeddedItems(document), [sources.first.itemData]);
      expect(
        WordZotero.fields(document).map((field) => field.instruction),
        instructions,
      );
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
    final items = WordZotero.fields(
      document,
    ).map((field) => field.citation!.items.single.toJson()).toList();
    expect(items, sources.map((item) => item.toJson()).toList());
  });
}
