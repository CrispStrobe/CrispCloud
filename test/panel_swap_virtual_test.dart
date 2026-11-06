import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/models/file_collection.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/file_collection_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_collection_store.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  final objectIds = <String, String>{};

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    final result = await super.listPath(path);
    return {
      ...result,
      'files': [
        for (final row in result['files'] as List)
          {...row as Map<String, dynamic>, 'uuid': objectIds[row['path']]},
      ],
    };
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);

  @override
  final _Cloud client;
  @override
  bool get isConnected => client.isAuthenticated;
  @override
  String get userEmail => 'swap@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  _Local(this.currentPath);

  @override
  String currentPath;
  @override
  String get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => true;
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) =>
      Directory(path).list(followLinks: false).toList();
  @override
  Future<void> refresh() async {}
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() operation,
  ) => operation();
}

Future<void> _eventually(bool Function() condition, String reason) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: reason);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory leftDirectory;
  late Directory rightDirectory;
  late Directory spoolDirectory;
  late _Cloud cloud;
  late FileCollectionStore store;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('panel_swap_virtual_');
    leftDirectory = await Directory(p.join(root.path, 'left')).create();
    rightDirectory = await Directory(p.join(root.path, 'right')).create();
    spoolDirectory = await Directory(p.join(root.path, 'spools')).create();
    cloud = _Cloud();
    store = FileCollectionStore(storage: MemoryFileCollectionStorage());
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local(leftDirectory.path)),
        fileCollectionStoreProvider.overrideWith((_) => store),
      ],
    );
    await store.ready;
  });

  tearDown(() async {
    container.dispose();
    // Panel disposal closes archive handles asynchronously. Let those owners
    // finish before removing the enclosing test directory.
    await _eventually(
      () => spoolDirectory.listSync().isEmpty,
      'Every archive spool must be released by its owning pane.',
    );
    await root.delete(recursive: true);
  });

  Future<(PanelNotifier, PanelNotifier)> localPanes() async {
    final left = container.read(panelProvider(PanelSide.local));
    final right = container.read(panelProvider(PanelSide.remote));
    await _eventually(
      () => !left.isLoading && left.files != null,
      'The initial local listing must finish before opening an archive.',
    );
    await left.navigateToPath(leftDirectory.path);
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(LocalPanelSource(rightDirectory.path));
    await right.navigateToPath(
      rightDirectory.path,
      origin: left.captureCurrentOrigin(),
    );
    expect(left.captureCurrentOrigin().source, isA<LocalPanelSource>());
    expect(right.captureCurrentOrigin().source, isA<LocalPanelSource>());
    return (left, right);
  }

  Future<void> openNestedArchive(PanelNotifier panel) async {
    final inner = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile.bytes('member.txt', 'inside'.codeUnits)),
    );
    final outer = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('outer.txt', 'outside'.codeUnits))
        ..addFile(ArchiveFile.bytes('folder/inner.zip', inner)),
    );
    final archive = File(p.join(leftDirectory.path, 'outer.zip'));
    await archive.writeAsBytes(outer);
    await panel.refresh();
    await panel.enterArchive(
      panel.files!.singleWhere((row) => row.path == archive.path),
    );
    await panel.navigateInto(
      panel.files!.singleWhere((row) => row.name == 'folder'),
    );
    await panel.navigateInto(panel.files!.single);
    expect(panel.currentPath, 'outer.zip!/folder/inner.zip:/');
    expect(
      String.fromCharCodes(await panel.readArchiveMember(panel.files!.single)),
      'inside',
    );
    expect(spoolDirectory.listSync().whereType<Directory>(), hasLength(2));
  }

  test(
    'swapped transient collections retain missing and replacement references',
    () async {
      for (final name in ['kept', 'missing', 'replaced']) {
        final path = '/collection/$name.txt';
        cloud.put(path, name.codeUnits);
        cloud.objectIds[path] = 'original-$name';
      }
      final (left, right) = await localPanes();
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(
            RemotePanelSource(
              providerName: cloud.providerName,
              client: cloud,
              path: '/collection',
            ),
          );
      await right.refresh();
      final origin = right.captureCurrentOrigin();
      right.showSearchResults(
        right.files!.where((row) => !row.isFolder).toList(),
        origin: origin,
        title: 'Transient search',
      );
      right.toggleSelection(
        right.files!.singleWhere((row) => row.name == 'kept.txt'),
        ctrlKey: true,
      );
      cloud.files.remove('/collection/missing.txt');
      cloud.objectIds['/collection/replaced.txt'] = 'new-replaced-object';
      await right.refreshCollectionItems();
      expect(right.isPagedCollection, isFalse);
      expect(right.currentPath, '/collection');
      expect(right.collectionReplacements.map((row) => row.name), [
        'replaced.txt',
      ]);
      final originalCollection = right.activeTab!.collectionId!;

      expect(await left.swapViewWith(right), isTrue);
      expect(left.showingSearchResults, isTrue);
      expect(left.isPagedCollection, isFalse);
      expect(left.currentPath, '/collection');
      expect(left.collectionReplacements.map((row) => row.name), [
        'replaced.txt',
      ]);
      for (final name in ['missing.txt', 'replaced.txt']) {
        final row = left.files!.singleWhere((row) => row.name == name);
        expect(
          left.originForOperation(row),
          isNull,
          reason: 'Saved references cannot authorize unavailable originals.',
        );
      }
      final kept = left.files!.singleWhere((row) => row.name == 'kept.txt');
      expect(
        (left.originForOperation(kept)!.source as RemotePanelSource).client,
        same(cloud),
      );
      expect(left.selection.map((row) => row.name), ['kept.txt']);

      // Both operations need the transferred saved entry for rows whose
      // unavailable original intentionally has no live operation origin.
      await left.refreshCollectionItems();
      expect(left.activeTab!.collectionId, originalCollection);
      expect(left.currentPath, '/collection');
      final savedId = await left.saveCurrentCollection(
        'After swapping panes',
        createNew: true,
      );
      final saved = await store.load(savedId);
      final byName = {
        for (final entry in saved.entries) entry.file.name: entry,
      };
      expect(
        byName.keys,
        unorderedEquals(['kept.txt', 'missing.txt', 'replaced.txt']),
      );
      expect(byName['missing.txt']!.state, CollectionItemState.missing);
      expect(byName['missing.txt']!.reference.objectId, 'original-missing');
      expect(byName['replaced.txt']!.replacement, isTrue);
      expect(byName['replaced.txt']!.reference.objectId, 'original-replaced');
      expect(saved.selectedKeys, {byName['kept.txt']!.key});

      // Saving reopens this as a paged collection. Its return location still
      // names the containing directory, never the first saved member's path.
      expect(left.currentPath, '/collection');
      await left.clearSearchResults();
      expect(left.showingSearchResults, isFalse);
      expect(left.currentPath, '/collection');
      expect(left.captureCurrentOrigin().source.currentPath, '/collection');
      expect(
        left.files!.where((row) => !row.isFolder).map((row) => row.name),
        unorderedEquals(['kept.txt', 'replaced.txt']),
      );
    },
  );

  test(
    'nested archive handles move with the pane and close on leaving',
    () async {
      await IOOverrides.runZoned(() async {
        final (left, right) = await localPanes();
        await openNestedArchive(left);

        expect(await left.swapViewWith(right), isTrue);
        expect(left.isInArchive, isFalse);
        expect(right.isInArchive, isTrue);
        expect(right.currentPath, 'outer.zip!/folder/inner.zip:/');
        expect(
          String.fromCharCodes(
            await right.readArchiveMember(right.files!.single),
          ),
          'inside',
        );
        expect(spoolDirectory.listSync().whereType<Directory>(), hasLength(2));

        await right.navigateToPath(
          rightDirectory.path,
          origin: right.captureArchiveOrigin(),
        );
        expect(right.isInArchive, isFalse);
        await _eventually(
          () => spoolDirectory.listSync().isEmpty,
          'Leaving the receiving pane must close both transferred ZIP handles.',
        );
      }, getSystemTempDirectory: () => spoolDirectory);
    },
  );

  test('disposing the receiver during swap releases unclaimed archive handles', () async {
    await IOOverrides.runZoned(() async {
      final (left, right) = await localPanes();
      await openNestedArchive(left);
      var invalidated = false;
      void invalidateReceiver() {
        if (invalidated || !left.isLoading || left.isInArchive) return;
        invalidated = true;
        // Dispose the receiver from the other pane's notification, before it
        // restores the pending archive. It is not notifying its own listeners.
        container.invalidate(panelProvider(PanelSide.remote));
      }

      left.addListener(invalidateReceiver);
      try {
        expect(await left.swapViewWith(right), isFalse);
      } finally {
        left.removeListener(invalidateReceiver);
      }

      expect(invalidated, isTrue);
      expect(left.isInArchive, isFalse);
      expect(right.isInArchive, isFalse);
      expect(
        spoolDirectory.listSync(),
        isEmpty,
        reason: 'An unclaimed archive must be closed before swap completes.',
      );
      expect(container.read(errorProvider).errors, isEmpty);
    }, getSystemTempDirectory: () => spoolDirectory);
  });
}
