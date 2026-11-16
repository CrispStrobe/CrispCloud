import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_format.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

ZoteroCitationItem _citation({
  required String uri,
  required String title,
  String family = 'Hassan',
}) => ZoteroCitationItem.fromJson({
  'id': 17,
  'uris': [uri],
  'itemData': {
    'id': 17,
    'type': 'book',
    'title': title,
    'author': [
      {'family': family, 'given': 'Amal'},
    ],
    'issued': {
      'date-parts': [
        [2024],
      ],
    },
    'futureProperty': {'keep': true},
  },
  'locator': '8–10',
  'prefix': 'see',
});

void main() {
  test('late alias bridges join bibliography entries and keep first data', () {
    const local = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
    const account = 'http://zotero.org/users/42/items/ABCD1234';
    final first = _citation(uri: local, title: 'First embedded snapshot');
    final second = _citation(uri: account, title: 'Later duplicate');
    final bridge = ZoteroCitationItem.fromJson({
      ..._citation(uri: account, title: 'Bridge snapshot').toJson(),
      'uris': [account, local],
    });
    final sources = [first, second, bridge];
    final before = jsonEncode(sources.map((item) => item.toJson()).toList());
    expect(
      zoteroBasicBibliography(sources),
      'Hassan, Amal (2024). First embedded snapshot.',
    );
    expect(jsonEncode(sources.map((item) => item.toJson()).toList()), before);
  });

  test('transitive aliases without CSL still deduplicate the bibliography', () {
    const local = 'http://zotero.org/users/local/LOCALKEY/items/ABCD1234';
    const account = 'http://zotero.org/users/42/items/ABCD1234';
    const merged = 'http://zotero.org/users/42/items/EFGH5678';
    final sources = [
      _citation(uri: local, title: 'First embedded snapshot'),
      _citation(uri: account, title: 'Account duplicate'),
      _citation(uri: merged, title: 'Merged duplicate'),
      ZoteroCitationItem.fromJson({
        'id': 'local-account',
        'uris': [local, account],
      }),
      ZoteroCitationItem.fromJson({
        'id': 'account-merged',
        'uris': [merged, account],
      }),
      _citation(
        uri: 'http://zotero.org/groups/42/items/ABCD1234',
        title: 'Independent group source',
        family: 'Ali',
      ),
    ];
    expect(zoteroBasicBibliography(sources).split('\n\n'), [
      'Ali, Amal (2024). Independent group source.',
      'Hassan, Amal (2024). First embedded snapshot.',
    ]);
  });
}
