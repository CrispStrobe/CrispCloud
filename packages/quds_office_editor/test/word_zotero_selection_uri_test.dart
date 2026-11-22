import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/embed/word_zotero_format.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

ZoteroCitationItem _stored(List<String> uris) => ZoteroCitationItem.fromJson({
  'id': 'embedded-research',
  'uris': uris,
  'itemData': {'type': 'book', 'title': 'Example'},
});

ZoteroItem _catalog(ZoteroLibrary library, String key) => ZoteroItem(
  library: library,
  key: key,
  title: 'Example',
  itemType: 'book',
);

void main() {
  group('Zotero desktop item selection', () {
    test('selects active local catalog items, even without an exported URI', () {
      final item = _catalog(ZoteroLibrary.localUser(), 'ABCD1234');
      expect(item.citationUri, isNull);
      expect(
        zoteroCatalogItemSelectionUri(item).toString(),
        'zotero://select/library/items/ABCD1234',
      );
    });

    test('selects catalog groups by library ID, not by a source title', () {
      final item = _catalog(ZoteroLibrary.group(731), 'ABCD1234');
      expect(
        zoteroCatalogItemSelectionUri(item).toString(),
        'zotero://select/groups/731/items/ABCD1234',
      );
    });

    test('does not conflate a remote personal library with the active profile', () {
      expect(
        zoteroCatalogItemSelectionUri(
          _catalog(ZoteroLibrary.user(42), 'ABCD1234'),
        ),
        isNull,
      );
    });

    test('links stored desktop items and groups using validated identities', () {
      expect(
        zoteroStoredItemSelectionUri(_stored([
          'http://zotero.org/users/local/LOCALKEY/items/ABCD1234',
          'https://www.zotero.org/users/local/LOCALKEY/items/ABCD1234',
        ])).toString(),
        'zotero://select/library/items/ABCD1234',
      );
      expect(
        zoteroStoredItemSelectionUri(_stored([
          'https://zotero.org/groups/731/items/EFGH5678',
        ])).toString(),
        'zotero://select/groups/731/items/EFGH5678',
      );
    });

    test('refuses ambiguous groups and local Zotero profiles', () {
      expect(
        zoteroStoredItemSelectionUri(_stored([
          'http://zotero.org/groups/731/items/ABCD1234',
          'http://zotero.org/groups/732/items/ABCD1234',
        ])),
        isNull,
      );
      expect(
        zoteroStoredItemSelectionUri(_stored([
          'http://zotero.org/users/local/LOCALKEY/items/ABCD1234',
          'http://zotero.org/users/local/OTHERKEY/items/ABCD1234',
        ])),
        isNull,
      );
    });

    test('never launches arbitrary URLs, offline IDs, or personal web identities', () {
      for (final value in [
        'javascript:alert(1)',
        'file:///tmp/ABCD1234',
        'zotero://select/library/items/ABCD1234',
        'http://zotero.org/groups/1/items/ABCD1234?token=secret',
        'http://zotero.org/groups/1/items/../ABCD1234',
        'https://zotero.org/users/42/items/ABCD1234',
      ]) {
        expect(zoteroStoredItemSelectionUri(_stored([value])), isNull);
      }
      expect(zoteroStoredItemSelectionUri(_stored([])), isNull);
    });
  });
}
