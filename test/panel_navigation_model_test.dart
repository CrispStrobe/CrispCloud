import 'package:crisp_cloud/models/panel_navigation.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:flutter_test/flutter_test.dart';

const _accountA = StorageReference(
  kind: 'remote',
  provider: 'Cloud',
  accountKey: 'a',
);
const _accountB = StorageReference(
  kind: 'remote',
  provider: 'Cloud',
  accountKey: 'b',
);

PanelNavigationEntry _entry(
  String path, [
  StorageReference storage = _accountA,
]) => PanelNavigationEntry(path: path, storage: storage);

void main() {
  test('same paths on different accounts remain separate routes', () {
    final history = PanelNavigationHistory()
      ..push(_entry('/shared'))
      ..push(_entry('/shared', _accountB));
    expect(history.entries, hasLength(2));
    expect(history.canGoBack, isTrue);
    expect(history.current!.storage, _accountB);
  });

  test(
    'refreshing current route retains forward history; a new route replaces it',
    () {
      final history = PanelNavigationHistory()
        ..push(_entry('/one'))
        ..push(_entry('/two'))
        ..push(_entry('/three'))
        ..select(1)
        ..push(_entry('/two'));
      expect(history.canGoForward, isTrue);
      expect(history.entries, hasLength(3));
      history.push(_entry('/different'));
      expect(history.entries.map((entry) => entry.path), [
        '/one',
        '/two',
        '/different',
      ]);
      expect(history.canGoForward, isFalse);
    },
  );

  test('tab serialization retains history index and cursor without sharing mutable stacks', () {
    final tab = PanelTab(id: 'original', path: '/two', storage: _accountA);
    tab.navigation
      ..push(_entry('/one'))
      ..push(_entry('/two'))
      ..select(0)
      ..rememberCursor(
        const PanelNavigationEntry(
          path: '/one',
          storage: _accountA,
          cursorPath: '/one/document.txt',
          cursorObjectId: 'item-1',
        ),
      );
    final restored = PanelTab.fromJson('restored', tab.toJson());
    expect(restored.navigation.index, 0);
    expect(restored.navigation.current!.cursorObjectId, 'item-1');
    restored.navigation.push(_entry('/new'));
    expect(tab.navigation.entries.last.path, '/two');
    expect(tab.navigation.canGoForward, isTrue);
  });

  test('history is bounded while preserving the current recent route', () {
    final history = PanelNavigationHistory();
    for (var i = 0; i < 130; i++) {
      history.push(_entry('/folder-$i'));
    }
    expect(history.entries, hasLength(PanelNavigationHistory.maxEntries));
    expect(history.entries.first.path, '/folder-30');
    expect(history.current!.path, '/folder-129');
  });

  test(
    'corrupt or unscoped routes cannot erase good routes or acquire an account',
    () {
      final history = PanelNavigationHistory.fromJson({
        'entries': [
          _entry('/one').toJson(),
          {'path': '/unscoped'},
          {'path': 'relative', 'storage': _accountA.toJson()},
          _entry('/two', _accountB).toJson(),
        ],
        'index': 2,
      });
      expect(history.entries.map((entry) => entry.path), ['/one', '/two']);
      expect(history.index, 0);
      expect(history.canGoForward, isTrue);
      expect(history.entries.last.storage, _accountB);
    },
  );
}
