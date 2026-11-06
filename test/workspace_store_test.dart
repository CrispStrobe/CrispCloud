import 'dart:convert';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/sort.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/workspace_configuration.dart';
import 'package:crisp_cloud/services/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Persistence implements WorkspacePersistence {
  String? value;
  bool acknowledge = true;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<bool> write(String value) async {
    writes++;
    if (!acknowledge) return false;
    this.value = value;
    return true;
  }
}

const _account = StorageReference(
  kind: 'remote',
  provider: 'webdav',
  accountKey: 'opaque-account',
  root: '/',
);
WorkspaceTabSnapshot _tab({
  StorageReference storage = _account,
  String path = '/',
}) => WorkspaceTabSnapshot.fromJson({
  'path': path,
  'label': 'Work',
  'storage': storage.toJson(),
});
SavedWorkspace _group(String id) => SavedWorkspace(
  id: id,
  name: id,
  left: WorkspacePanelSnapshot(tabs: [_tab()]),
  right: WorkspacePanelSnapshot(tabs: [_tab(path: '/other')]),
);

void main() {
  test(
    'catalog round-trip retains account, locks, columns and active tabs',
    () async {
      final persistence = _Persistence();
      final store = WorkspaceStore(persistence: persistence);
      final tab = _tab().toJson()
        ..['lockMode'] = 'locked'
        ..['lockedPath'] = '/'
        ..['lockedStorage'] = _account.toJson()
        ..['view'] = FileViewConfiguration(
          sortBy: SortBy.size,
          filter: 'report',
        ).toJson();
      final group = SavedWorkspace(
        id: 'work',
        name: 'Reports',
        left: WorkspacePanelSnapshot(
          tabs: [_tab(), WorkspaceTabSnapshot.fromJson(tab)],
          activeIndex: 1,
        ),
        right: WorkspacePanelSnapshot(tabs: [_tab()]),
        layout: const WorkspaceLayout(split: 0.65, tree: true),
      );
      await store.saveGroup(group);
      final restored = (await store.load()).groups.single;
      expect(restored.left.activeIndex, 1);
      final restoredTab = restored.left.tabs[1].toTab('restored');
      expect(restoredTab.storage, _account);
      expect(restoredTab.lockedStorage, _account);
      expect(restoredTab.view!.sortBy, SortBy.size);
      expect(restoredTab.view!.filter, 'report');
      expect(restored.layout.split, 0.65);
      expect(
        WorkspaceStore.decode(await store.exportText()).groups.single.name,
        'Reports',
      );
    },
  );

  test(
    'failed persistence is reported and leaves saved catalog intact',
    () async {
      final persistence = _Persistence();
      final store = WorkspaceStore(persistence: persistence);
      await store.saveGroup(_group('first'));
      persistence.acknowledge = false;
      await expectLater(store.saveGroup(_group('second')), throwsStateError);
      expect((await store.load()).groups.map((item) => item.id), ['first']);
    },
  );

  test(
    'a corrupt catalog is retained instead of replaced by a mutation',
    () async {
      final persistence = _Persistence()..value = '{broken';
      final store = WorkspaceStore(persistence: persistence);
      await expectLater(store.saveGroup(_group('new')), throwsFormatException);
      expect(persistence.value, '{broken');
      expect(persistence.writes, 0);
    },
  );

  test('simultaneous mutations preserve every catalog section', () async {
    final store = WorkspaceStore(persistence: _Persistence());
    await Future.wait([
      store.saveGroup(_group('work')),
      store.savePair(
        PairedBookmark(
          id: 'pair',
          name: 'Pair',
          left: _tab(),
          right: _tab(path: '/backup'),
        ),
      ),
      store.saveProfile(
        SavedViewProfile(
          id: 'view',
          name: 'View',
          configuration: FileViewConfiguration(),
        ),
      ),
    ]);
    final saved = await store.load();
    expect(saved.groups, hasLength(1));
    expect(saved.pairs, hasLength(1));
    expect(saved.profiles, hasLength(1));
  });

  test(
    'imports validate all entries before changing any existing data',
    () async {
      final persistence = _Persistence();
      final store = WorkspaceStore(persistence: persistence);
      await store.saveGroup(_group('first'));
      final before = persistence.value;
      final bad = WorkspaceCatalog(groups: [_group('second')]).toJson();
      (bad['groups'] as List).add({'id': 'broken'});
      await expectLater(
        store.importText(jsonEncode(bad)),
        throwsA(isA<Object>()),
      );
      expect(persistence.value, before);
    },
  );

  test(
    'merge, replacement and ordering use explicit stable item IDs',
    () async {
      final store = WorkspaceStore(persistence: _Persistence());
      await store.saveGroup(_group('a'));
      await store.saveGroup(_group('b'));
      await store.saveGroup(_group('c'));
      await store.reorder('groups', 0, 3);
      expect((await store.load()).groups.map((group) => group.id), [
        'b',
        'c',
        'a',
      ]);
      await store.importText(
        jsonEncode(
          WorkspaceCatalog(groups: [_group('b').renamed('Updated')]).toJson(),
        ),
      );
      expect((await store.load()).groups.first.name, 'Updated');
      await store.importText(
        jsonEncode(WorkspaceCatalog(groups: [_group('only')]).toJson()),
        replaceAll: true,
      );
      expect((await store.load()).groups.map((group) => group.id), ['only']);
    },
  );

  test(
    'foreign installation paths remain bound to the foreign installation',
    () {
      const windows = StorageReference(
        kind: 'local',
        provider: 'windows',
        accountKey: 'other-installation',
      );
      final snapshot = _tab(storage: windows, path: r'C:\Projects');
      expect(snapshot.storage, windows);
      expect(snapshot.path, r'C:\Projects');
      expect(() => _tab(path: '../relative'), throwsFormatException);
      expect(
        () =>
            WorkspaceTabSnapshot.fromJson({'path': '/', 'label': 'No source'}),
        throwsFormatException,
      );
    },
  );

  test('snapshots discard executable unknown fields and are immutable', () {
    final raw = _tab().toJson()..['command'] = 'do-not-execute';
    final snapshot = WorkspaceTabSnapshot.fromJson(raw);
    raw['path'] = '/changed';
    final exposed = snapshot.toJson();
    (exposed['storage'] as Map)['accountKey'] = 'different';
    expect(snapshot.path, '/');
    expect(snapshot.storage, _account);
    expect(snapshot.toJson(), isNot(contains('command')));
  });

  test(
    'column metadata supports numeric sorting without reading file contents',
    () {
      const column = FileColumnDefinition(
        id: 'rating',
        label: 'Rating',
        kind: FileColumnKind.metadata,
        metadataKey: 'image.rating',
      );
      final low = FileItem(
        name: 'low',
        isFolder: false,
        metadata: {
          'image': {'rating': 2},
        },
      );
      final high = FileItem(
        name: 'high',
        isFolder: false,
        metadata: {
          'image': {'rating': 10},
        },
      );
      expect(column.compare(low, high), lessThan(0));
      expect(column.displayValue(high), '10');
      expect(
        column.displayValue(FileItem(name: 'missing', isFolder: false)),
        '',
      );
    },
  );

  test('narrow columns reserve name space and reappear when enlarged', () {
    final view = FileViewConfiguration(
      widths: {'size': 62, 'date': -78, 'ext': 40},
    );
    expect(view.columnsFitting(180), isEmpty);
    expect(view.columnsFitting(300).map((column) => column.id), [
      'size',
      'ext',
    ]);
    expect(
      () => FileViewConfiguration(widths: {'size': double.nan}),
      throwsFormatException,
    );
    expect(
      () => FileViewConfiguration(sortColumnId: 'missing'),
      throwsFormatException,
    );
  });
}
