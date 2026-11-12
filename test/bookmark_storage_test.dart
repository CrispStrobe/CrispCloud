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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same-path bookmarks on two accounts stay distinct through persistence',
    () async {
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.add(
        'First reports',
        '/reports',
        PanelSide.remote,
        storage: _first,
      );
      await bookmarks.add(
        'Second reports',
        '/reports',
        PanelSide.remote,
        storage: _second,
      );
      expect(bookmarks.bookmarks, hasLength(2));
      await bookmarks.remove('/reports', PanelSide.remote, storage: _first);
      expect(bookmarks.bookmarks.single.storage, _second);
      final restored = BookmarksNotifier();
      addTearDown(restored.dispose);
      await restored.ready;
      expect(restored.bookmarks.single.storage, _second);
      expect(
        restored.isBookmarked('/reports', PanelSide.remote, storage: _first),
        isFalse,
      );
    },
  );

  test(
    'legacy bookmarks remain unbound including foreign native Windows paths',
    () async {
      SharedPreferences.setMockInitialValues({
        'bookmarks': jsonEncode([
          {'name': 'Old remote', 'path': '/reports', 'side': 'remote'},
          {'name': 'Old local', 'path': r'C:\Photos', 'side': 'local'},
        ]),
      });
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.ready;
      expect(bookmarks.bookmarks, hasLength(2));
      expect(
        bookmarks.bookmarks.every((bookmark) => !bookmark.isBound),
        isTrue,
      );
      expect(bookmarks.bookmarks.last.path, r'C:\Photos');
    },
  );

  test(
    'adding before initial load preserves previous entries and user changes',
    () async {
      SharedPreferences.setMockInitialValues({
        'bookmarks': jsonEncode([
          const Bookmark(
            name: 'Existing',
            path: '/old',
            side: PanelSide.remote,
            storage: _first,
          ).toJson(),
        ]),
      });
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      final save = bookmarks.add(
        'New',
        '/new',
        PanelSide.remote,
        storage: _second,
      );
      expect(bookmarks.bookmarks.single.name, 'New');
      await save;
      expect(bookmarks.bookmarks.map((bookmark) => bookmark.name), [
        'Existing',
        'New',
      ]);
      final persisted = jsonDecode(
        (await SharedPreferences.getInstance()).getString('bookmarks')!,
      ) as List;
      expect(persisted, hasLength(2));
    },
  );

  test(
    'explicit legacy migration retains name and binds only the chosen source',
    () async {
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.add('Legacy', '/reports', PanelSide.remote);
      final old = bookmarks.bookmarks.single;
      await bookmarks.replace(
        old,
        Bookmark(
          name: old.name,
          path: old.path,
          side: old.side,
          storage: _second,
        ),
      );
      expect(bookmarks.bookmarks.single.storage, _second);
      expect(
        bookmarks.bookmarks.single.toTabJson()['storage'],
        _second.toJson(),
      );
      expect(bookmarks.bookmarks.single.name, 'Legacy');
    },
  );

  test(
    'collection bookmarks remain distinct from same-path directory bookmarks',
    () async {
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.add('Folder', '/', PanelSide.remote, storage: _first);
      await bookmarks.add(
        'Results',
        '/',
        PanelSide.remote,
        collectionId: 'saved-list',
      );
      expect(bookmarks.bookmarks, hasLength(2));
      expect(bookmarks.bookmarks.last.isBound, isTrue);
      expect(
        bookmarks.bookmarks.last.toTabJson()['collectionId'],
        'saved-list',
      );
    },
  );

  test(
    'bookmark imports validate the whole document before merging accounts',
    () async {
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.add(
        'First',
        '/reports',
        PanelSide.remote,
        storage: _first,
      );
      final text = await bookmarks.exportText();
      final bad = jsonDecode(text) as Map;
      (bad['bookmarks'] as List).add({'name': 'broken'});
      await expectLater(
        bookmarks.importText(jsonEncode(bad)),
        throwsA(isA<Object>()),
      );
      expect(bookmarks.bookmarks, hasLength(1));
      const second = Bookmark(
        name: 'Second',
        path: '/reports',
        side: PanelSide.remote,
        storage: _second,
      );
      await bookmarks.importText(
        jsonEncode({
          'format': 'crispcloud.bookmarks',
          'version': 2,
          'bookmarks': [second.toJson()],
        }),
      );
      expect(bookmarks.bookmarks.map((bookmark) => bookmark.storage), [
        _first,
        _second,
      ]);
    },
  );

  test(
    'corrupt saved bookmarks are retained rather than overwritten',
    () async {
      SharedPreferences.setMockInitialValues({'bookmarks': 'broken json'});
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.ready;
      await expectLater(
        bookmarks.add('New', '/new', PanelSide.remote, storage: _first),
        throwsStateError,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('bookmarks'),
        'broken json',
      );
      expect(bookmarks.lastError, isNotNull);
    },
  );

  test(
    'disposing during async preference load does not notify disposed listeners',
    () async {
      final bookmarks = BookmarksNotifier();
      bookmarks.dispose();
      await bookmarks.ready;
    },
  );

  test('favorite order persists without changing source identities', () async {
    final bookmarks = BookmarksNotifier();
    addTearDown(bookmarks.dispose);
    await bookmarks.add('First', '/reports', PanelSide.remote, storage: _first);
    await bookmarks.add(
      'Second',
      '/reports',
      PanelSide.local,
      storage: _second,
    );
    await bookmarks.add('Third', '/photos', PanelSide.remote, storage: _first);
    final second = bookmarks.bookmarks[1];
    final identities = bookmarks.bookmarks.map((item) => item.identity).toSet();
    await bookmarks.move(second, -1);
    expect(bookmarks.bookmarks.map((item) => item.name), [
      'Second',
      'First',
      'Third',
    ]);
    await bookmarks.move(second, -1); // First item cannot move past the top.
    expect(bookmarks.bookmarks.first, same(second));
    final restored = BookmarksNotifier();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.bookmarks.map((item) => item.name), [
      'Second',
      'First',
      'Third',
    ]);
    expect(restored.bookmarks.map((item) => item.identity).toSet(), identities);
  });

  test(
    'reordering a removed row cannot move its replacement neighbor',
    () async {
      final bookmarks = BookmarksNotifier();
      addTearDown(bookmarks.dispose);
      await bookmarks.add('First', '/first', PanelSide.remote, storage: _first);
      await bookmarks.add(
        'Second',
        '/second',
        PanelSide.remote,
        storage: _first,
      );
      final removed = bookmarks.bookmarks.first;
      await bookmarks.remove(
        removed.path,
        removed.side,
        storage: removed.storage,
      );
      await expectLater(bookmarks.move(removed, 1), throwsStateError);
      expect(bookmarks.bookmarks.single.name, 'Second');
      await expectLater(
        bookmarks.move(bookmarks.bookmarks.single, 3),
        throwsArgumentError,
      );
    },
  );
}
