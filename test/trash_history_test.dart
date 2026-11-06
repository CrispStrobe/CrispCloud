import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/trash_history_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_trash.dart';
import 'package:crisp_cloud/services/trash_history_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake
    implements CloudStorageClient, StorageTrashOperations {
  _Cloud(this.userId);
  @override
  final String userId;
  @override
  String get providerName => 'Trash test';
  @override
  String? get bucketId => null;
  @override
  String get rootPath => '/';
  @override
  bool isAuthenticated = true;
  final files = <String, String>{'/original.txt': 'original-id'};
  final trashed = <String, String>{};
  int trashCalls = 0;
  int restoreCalls = 0;
  int listCalls = 0;
  bool failRestore = false;

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    listCalls++;
    return {
      'folders': <Map<String, dynamic>>[],
      'files': [
        for (final file in files.entries)
          if (path == '/')
            {'name': file.key.substring(1), 'uuid': file.value, 'size': 4},
      ],
    };
  }

  @override
  Future<TrashReceipt> trashPath(String path) async {
    trashCalls++;
    final id = files.remove(path);
    if (id == null) throw StateError('Missing');
    trashed[id] = path;
    return TrashReceipt(originalPath: path, trashId: id);
  }

  @override
  Future<void> restoreTrash(TrashReceipt receipt) async {
    restoreCalls++;
    if (failRestore) throw StateError('Temporary provider error');
    if (files.containsKey(receipt.originalPath)) throw StateError('Occupied');
    if (trashed.remove(receipt.trashId) == null) {
      throw StateError('Missing receipt');
    }
    files[receipt.originalPath] = receipt.trashId;
  }

  @override
  Future<void> deletePermanently(String path) async {
    files.remove(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? get userEmail => '${client.userId}@example.invalid';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String? get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  final containers = <ProviderContainer>[];
  ProviderContainer open(_Cloud client, {TrashHistoryStore? store}) {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(client)),
        localFileServiceProvider.overrideWithValue(_Local()),
        if (store != null) trashHistoryProvider.overrideWith((_) => store),
      ],
    );
    containers.add(container);
    return container;
  }

  Future<String> trash(ProviderContainer container) async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    expect(await panel.deleteFiles(panel.files!.toList()), 1);
    final store = container.read(trashHistoryProvider);
    expect(store.records.single.state, TrashRecordState.trashed);
    return store.records.single.id;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud('account-a');
  });
  tearDown(() {
    for (final container in containers) {
      container.dispose();
    }
    containers.clear();
  });

  test(
    'trash receipt survives restart and restores through its original account',
    () async {
      final first = open(cloud);
      final id = await trash(first);
      expect(cloud.files, isEmpty);
      final restarted = open(cloud);
      final panel = restarted.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      await panel.navigateToPath('/elsewhere');
      await panel.restoreTrashRecord(id);
      expect(cloud.files['/original.txt'], 'original-id');
      expect(cloud.restoreCalls, 1);
      final third = TrashHistoryStore();
      await third.ready;
      expect(third.get(id)!.state, TrashRecordState.restored);
      third.dispose();
    },
  );

  test(
    'another account with the same paths is never used for restore',
    () async {
      final id = await trash(open(cloud));
      final wrong = _Cloud('account-b');
      final container = open(wrong);
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final calls = wrong.listCalls;
      await expectLater(panel.restoreTrashRecord(id), throwsStateError);
      expect(wrong.restoreCalls, 0);
      expect(wrong.listCalls, calls);
      expect(cloud.restoreCalls, 0);
    },
  );

  test(
    'restore refuses an occupied original path without changing either item',
    () async {
      final container = open(cloud);
      final id = await trash(container);
      cloud.files['/original.txt'] = 'replacement-id';
      await expectLater(
        container.read(panelProvider(PanelSide.remote)).restoreTrashRecord(id),
        throwsStateError,
      );
      expect(cloud.files['/original.txt'], 'replacement-id');
      expect(cloud.trashed['original-id'], '/original.txt');
      expect(cloud.restoreCalls, 0);
    },
  );

  test(
    'failed restore keeps the receipt and an explicit retry succeeds',
    () async {
      final container = open(cloud);
      final id = await trash(container);
      final panel = container.read(panelProvider(PanelSide.remote));
      cloud.failRestore = true;
      await expectLater(panel.restoreTrashRecord(id), throwsStateError);
      final reloaded = TrashHistoryStore();
      await reloaded.ready;
      expect(reloaded.get(id)!.state, TrashRecordState.uncertain);
      expect(reloaded.get(id)!.receipt!.trashId, 'original-id');
      cloud.failRestore = false;
      await panel.restoreTrashRecord(id);
      expect(cloud.restoreCalls, 2);
      reloaded.dispose();
    },
  );

  test('intent persistence failure prevents the trash mutation', () async {
    final store = TrashHistoryStore(
      preferences: () async => throw StateError('disk unavailable'),
    );
    final container = open(cloud, store: store);
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    expect(await panel.deleteFiles(panel.files!.toList()), 0);
    expect(cloud.trashCalls, 0);
    expect(cloud.files['/original.txt'], 'original-id');
  });

  test('pending and corrupt records are retained and cannot invent restore receipts', () async {
    final container = open(cloud);
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final store = container.read(trashHistoryProvider);
    final confirmedId = await trash(container);
    final confirmed = store.get(confirmedId)!;
    final pending = await store.begin(
      file: confirmed.file,
      name: confirmed.name,
      isFolder: false,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('commander_trash_v1_corrupt', '{not json');
    final reloaded = TrashHistoryStore();
    await reloaded.ready;
    expect(reloaded.get(pending.id)!.state, TrashRecordState.pending);
    expect(reloaded.get(pending.id)!.receipt, isNull);
    expect(reloaded.errors.single, contains('corrupt'));
    expect(prefs.getString('commander_trash_v1_corrupt'), '{not json');
    await expectLater(panel.restoreTrashRecord(pending.id), throwsStateError);
    expect(cloud.restoreCalls, 0);
    reloaded.dispose();
  });
}
