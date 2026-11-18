import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_sources.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _local = 'http://zotero.org/users/local/LOCALKEY/items/SOURCE01';
const _otherLocal = 'http://zotero.org/users/local/OTHERKEY/items/SOURCE01';
const _account = 'http://zotero.org/users/42/items/SOURCE01';
const _merged = 'http://zotero.org/users/42/items/SOURCE02';
const _group = 'http://zotero.org/groups/42/items/SOURCE01';

ZoteroCitationItem _source(List<String> uris, {Object id = 17}) =>
    ZoteroCitationItem.fromJson({
      'id': id,
      'uris': uris,
      'locator': '12–15',
      'prefix': 'see',
      'suffix': 'for details',
      'futureItemSetting': {'keep': true},
    });

void main() {
  test('late local/account alias declarations resolve one online source', () {
    final local = _source([_local]);
    final account = _source([_account]);
    final bridge = _source([_local, _account]);
    final sources = [local, account, bridge];
    final before = jsonEncode(sources.map((item) => item.toJson()).toList());
    final resolver = ZoteroSourceResolver(sources, local: false);
    for (final item in sources) {
      expect(resolver.addressOf(item)!.canonicalUri.toString(), _account);
    }
    expect(jsonEncode(sources.map((item) => item.toJson()).toList()), before);
  });

  test('transitive bridges without snapshots resolve scheme/host aliases', () {
    final sources = [
      _source([_local]),
      _source([_merged]),
      _source([_local, _account]),
      _source(['HTTPS://WWW.ZOTERO.ORG/users/42/items/SOURCE01', _merged]),
    ];
    final resolver = ZoteroSourceResolver(sources, local: false);
    for (final item in sources) {
      expect(resolver.addressOf(item)!.canonicalUri.toString(), _merged);
    }
  });

  test('desktop retains the first declared identity of an alias group', () {
    final sources = [
      _source([_local]),
      _source([_account]),
      _source([_account, _local]),
    ];
    final resolver = ZoteroSourceResolver(sources, local: true);
    for (final item in sources) {
      final address = resolver.addressOf(item)!;
      expect(address.canonicalUri.toString(), _local);
      expect(address.scope, '/users/local/LOCALKEY');
      expect(address.library.apiPath, '/users/0');
    }
  });

  test('unrelated libraries and local profiles keep equal keys separate', () {
    final uris = [_local, _otherLocal, _account, _group];
    final sources = uris.map((uri) => _source([uri])).toList();
    for (final local in [false, true]) {
      final resolver = ZoteroSourceResolver(sources, local: local);
      expect(
        sources.map(
          (item) => resolver.addressOf(item)!.canonicalUri.toString(),
        ),
        uris,
      );
    }
  });

  test('item IDs and opaque or malformed URIs do not declare links', () {
    final sources = [
      _source([_local]),
      _source([_account]),
      _source([_local, 'opaque-alias']),
      _source(['opaque-alias', _account]),
      _source([_local, 'https://zotero.org/users/41/../42/items/SOURCE01']),
      _source([_local, 'https://zotero.org:443/users/42/items/SOURCE01']),
      _source([_local, 'https://zotero.org/users/42/items/%53OURCE01']),
      _source([], id: _account),
    ];
    final resolver = ZoteroSourceResolver(sources, local: false);
    expect(resolver.addressOf(sources[0])!.canonicalUri.toString(), _local);
    expect(resolver.addressOf(sources[1])!.canonicalUri.toString(), _account);
    expect(resolver.addressOf(sources.last), isNull);
  });

  test(
    'online source selection stays deterministic across numeric aliases',
    () {
      final sources = [
        _source([_local]),
        _source([_merged]),
        _source([_local, _account, _merged]),
      ];
      final resolver = ZoteroSourceResolver(sources, local: false);
      expect(
        resolver.addressOf(sources.first)!.canonicalUri.toString(),
        _merged,
      );
      expect(resolver.addressOf(_source([_group])), isNull);
    },
  );

  test('the 10,000 unique alias bound does not count repeated occurrences', () {
    final uris = [
      for (var i = 0; i < 10000; i++)
        'http://zotero.org/users/42/items/K${i.toString().padLeft(7, '0')}',
    ];
    final source = _source(uris);
    final resolver = ZoteroSourceResolver([source, source], local: false);
    expect(resolver.addressOf(source)!.canonicalUri.toString(), uris.first);
    expect(
      () => ZoteroSourceResolver([
        source,
        _source(['http://zotero.org/users/42/items/K0010000']),
      ], local: false),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Resolve at most 10,000 Zotero source aliases at once.',
        ),
      ),
    );
  });
}
