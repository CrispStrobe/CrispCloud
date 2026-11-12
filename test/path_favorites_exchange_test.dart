import 'dart:convert';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/bookmarks_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _first = StorageReference(
  kind: 'remote',
  provider: 'webdav',
  accountKey: 'first',
);
const _second = StorageReference(
  kind: 'remote',
  provider: 'webdav',
  accountKey: 'second',
);

String _exchange(List<Bookmark> bookmarks, {int version = 3}) => jsonEncode({
  'format': 'crispcloud.bookmarks',
  'version': version,
  'bookmarks': bookmarks.map((item) => item.toJson()).toList(),
});

Bookmark _favorite(
  String name,
  String path, {
  StorageReference? storage = _first,
  String group = '',
  PanelSide side = PanelSide.remote,
}) => Bookmark(
  name: name,
  path: path,
  side: side,
  storage: storage,
  group: group,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'groups persist and rename/ungroup without changing destinations',
    () async {
      final store = BookmarksNotifier();
      addTearDown(store.dispose);
      await store.add(
        'One',
        '/one',
        PanelSide.remote,
        storage: _first,
        group: 'Work',
      );
      await store.add(
        'Two',
        '/two',
        PanelSide.remote,
        storage: _second,
        group: 'Work',
      );
      final identities = store.bookmarks.map((item) => item.identity).toList();
      await store.renameGroup('Work', 'Projects');
      expect(store.groups, ['Projects']);
      expect(store.bookmarks.map((item) => item.identity), identities);
      final restored = BookmarksNotifier();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.bookmarks.map((item) => item.group), [
        'Projects',
        'Projects',
      ]);
      await store.renameGroup('Projects', '');
      expect(store.groups, isEmpty);
      expect(store.bookmarks.map((item) => item.storage), [_first, _second]);
      expect(store.bookmarks, hasLength(2));
    },
  );

  test('group reordering does not move favorites in another group', () async {
    final store = BookmarksNotifier();
    addTearDown(store.dispose);
    for (final (name, group) in [
      ('One', 'Work'),
      ('Other', 'Home'),
      ('Two', 'Work'),
    ]) {
      await store.add(
        name,
        '/$name',
        PanelSide.remote,
        storage: _first,
        group: group,
      );
    }
    await store.move(store.bookmarks.last, -1, withinGroup: true);
    expect(store.bookmarks.map((item) => item.name), ['Two', 'Other', 'One']);
    expect(store.groups, ['Work', 'Home']);
  });

  test(
    'preview is non-mutating and merges only new source/path destinations',
    () async {
      final store = BookmarksNotifier();
      addTearDown(store.dispose);
      await store.add(
        'Keep my name',
        '/reports',
        PanelSide.remote,
        storage: _first,
        group: 'Mine',
      );
      final preview = store.previewImport(
        _exchange([
          _favorite(
            'Replace name',
            '/reports',
            group: 'Imported',
            side: PanelSide.local,
          ),
          _favorite(
            'Other account',
            '/reports',
            storage: _second,
            group: 'Office',
          ),
          _favorite('Duplicate file row', '/reports/./', storage: _second),
          _favorite('Old unbound', r'C:\Photos', storage: null),
        ]),
      );
      expect(preview.total, 4);
      expect(preview.duplicates, 2);
      expect(preview.additions.map((item) => item.name), [
        'Other account',
        'Old unbound',
      ]);
      expect(store.bookmarks, hasLength(1));
      expect(await store.mergeImport(preview), 2);
      expect(store.bookmarks.first.name, 'Keep my name');
      expect(store.bookmarks.first.group, 'Mine');
      expect(store.bookmarks[1].storage, _second);
      expect(store.bookmarks[2].storage, isNull);
      expect(store.bookmarks[2].path, r'C:\Photos');
      expect(await store.mergeImport(preview), 0);
    },
  );

  test(
    'merge rechecks a preview when another window adds its destination',
    () async {
      final store = BookmarksNotifier();
      addTearDown(store.dispose);
      await store.ready;
      final preview = store.previewImport(
        _exchange([_favorite('Incoming', '/same')]),
      );
      await store.add(
        'Created while preview open',
        '/same',
        PanelSide.remote,
        storage: _first,
      );
      expect(await store.mergeImport(preview), 0);
      expect(store.bookmarks.single.name, 'Created while preview open');
    },
  );

  test(
    'version 3 export contains only favorites and non-secret source references',
    () async {
      final store = BookmarksNotifier();
      addTearDown(store.dispose);
      await store.add(
        'Work',
        '/reports',
        PanelSide.remote,
        storage: _first,
        group: 'Projects',
      );
      final text = await store.exportText();
      final json = jsonDecode(text) as Map;
      expect(json['version'], 3);
      expect(json.keys, unorderedEquals(['format', 'version', 'bookmarks']));
      final item = (json['bookmarks'] as List).single as Map;
      expect(item['group'], 'Projects');
      expect(
        (item['storage'] as Map).keys,
        unorderedEquals([
          'version',
          'kind',
          'provider',
          'accountKey',
          'root',
          'persistent',
        ]),
      );
      expect(
        BookmarksNotifier.decodeImport(text).single.toJson(),
        store.bookmarks.single.toJson(),
      );
      expect(
        BookmarksNotifier.decodeImport(
          _exchange([_favorite('Old', '/old')], version: 2),
        ).single.group,
        '',
      );
    },
  );

  test(
    'invalid or credential-bearing input rejects the entire merge',
    () async {
      final store = BookmarksNotifier();
      addTearDown(store.dispose);
      await store.add(
        'Existing',
        '/existing',
        PanelSide.remote,
        storage: _first,
      );
      for (final corrupt in <void Function(Map<String, dynamic>)>[
        (item) => item['side'] = 'guess-current-pane',
        (item) => item['path'] = 'relative',
        (item) => item['group'] = 'bad\ngroup',
        (item) => item['password'] = 'must-not-be-accepted',
        (item) =>
            (item['storage'] as Map)['accessToken'] = 'must-not-be-accepted',
        (item) => (item['storage'] as Map)['persistent'] = 'true',
      ]) {
        final malformed = _favorite('Bad', '/bad').toJson();
        corrupt(malformed);
        final text = jsonEncode({
          'format': 'crispcloud.bookmarks',
          'version': 3,
          'bookmarks': [
            _favorite('Valid before bad', '/good').toJson(),
            malformed,
          ],
        });
        expect(() => store.previewImport(text), throwsFormatException);
        await expectLater(store.importText(text), throwsFormatException);
        expect(store.bookmarks.single.name, 'Existing');
      }
    },
  );

  test(
    'same provider/path with a different namespace root is never deduplicated',
    () async {
      final store = BookmarksNotifier();
      addTearDown(store.dispose);
      await store.add('Root A', '/folder', PanelSide.remote, storage: _first);
      final preview = store.previewImport(
        _exchange([
          _favorite(
            'Root B',
            '/folder',
            storage: const StorageReference(
              kind: 'remote',
              provider: 'webdav',
              accountKey: 'first',
              root: '/other-root',
            ),
          ),
        ]),
      );
      expect(preview.additions, hasLength(1));
      expect(preview.duplicates, 0);
    },
  );
}
