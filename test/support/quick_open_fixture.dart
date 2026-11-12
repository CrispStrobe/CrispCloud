import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_collection_page.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/workspace_provider.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/workspace_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'workflow_fake_client.dart';

class QuickOpenCloud extends WorkflowFakeClient {
  QuickOpenCloud(this.account);
  final String account;
  final listingStarted = <String>[];
  final gates = <String, Completer<void>>{};
  final failPaths = <String>{};
  @override
  String get userId => account;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    listingStarted.add(path);
    await gates[path]?.future;
    if (failPaths.contains(path)) throw StateError('Folder unavailable: $path');
    return super.listPath(path);
  }
}

class QuickOpenAuth extends ChangeNotifier implements AuthNotifier {
  QuickOpenAuth(this.client);
  @override
  QuickOpenCloud client;
  @override
  bool get isConnected => client.isAuthenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => client.account;
  void changed() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuickOpenLocal extends Fake
    implements LocalFileService, LocalDirectorySnapshotReader {
  @override
  String currentPath = '/start';
  final paths = <String>{'/', '/start', '/favorite', '/drive', '/newer'};
  final snapshots = <String>[];
  final gates = <String, Completer<void>>{};
  int accessRequests = 0;
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => '/start';
  @override
  Future<bool> hasAccessToPath(String path) async => paths.contains(path);
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    accessRequests++;
    return null;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async {
    snapshots.add(path);
    await gates[path]?.future;
    if (!paths.contains(path)) {
      throw FileSystemException('Missing or inaccessible folder', path);
    }
    return [];
  }

  @override
  Future<void> refresh() async {}
}

class QuickOpenWorkspacePersistence implements WorkspacePersistence {
  String? value;
  Completer<void>? gate;
  @override
  Future<String?> read() async {
    await gate?.future;
    return value;
  }

  @override
  Future<bool> write(String value) async {
    this.value = value;
    return true;
  }
}

class QuickOpenCollections extends FileCollectionStore {
  QuickOpenCollections() : super(storage: MemoryFileCollectionStorage());
  Completer<void>? marksGate;
  final marksStarted = Completer<void>();

  @override
  Future<FileCollectionManifest> updateMarks(
    FileCollectionManifest expected,
    Map<int, Set<String>> selections, {
    bool Function()? isCancelled,
  }) async {
    if (marksGate != null) {
      if (!marksStarted.isCompleted) marksStarted.complete();
      await marksGate!.future;
    }
    return super.updateMarks(expected, selections, isCancelled: isCancelled);
  }
}

class QuickOpenHarness {
  QuickOpenHarness._(
    this.container,
    this.local,
    this.cloud,
    this.auth,
    this.persistence,
    this.collections,
  );
  final ProviderContainer container;
  final QuickOpenLocal local;
  final QuickOpenCloud cloud;
  final QuickOpenAuth auth;
  final QuickOpenWorkspacePersistence persistence;
  final QuickOpenCollections collections;

  static Future<QuickOpenHarness> create({
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final local = QuickOpenLocal();
    final cloud = QuickOpenCloud('account-a')
      ..put('/favorite/a.txt', [1])
      ..put('/left/a.txt', [2])
      ..put('/right/b.txt', [3]);
    final auth = QuickOpenAuth(cloud);
    final persistence = QuickOpenWorkspacePersistence();
    final collections = QuickOpenCollections();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
        fileCollectionStoreProvider.overrideWith((_) => collections),
        workspaceStoreProvider.overrideWithValue(
          WorkspaceStore(persistence: persistence),
        ),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        transferJournalProvider.overrideWithValue(
          TransferJournal(MemoryTransferJournalStorage()),
        ),
        ...overrides,
      ],
    );
    for (final side in PanelSide.values) {
      await container.read(panelProvider(side)).refresh();
    }
    await container.read(bookmarksProvider).ready;
    return QuickOpenHarness._(
      container,
      local,
      cloud,
      auth,
      persistence,
      collections,
    );
  }

  void dispose() => container.dispose();
}
