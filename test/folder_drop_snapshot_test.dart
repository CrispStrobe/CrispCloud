import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_drag_data.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/folder_drop_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/local_file_service_native.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account) {
    directories.addAll([
      '/vault',
      '/vault/active',
      '/vault/active/deep',
      '/vault/drop',
      '/vault/source',
      '/vault/source/folder',
      '/vault/source/folder/child',
    ]);
    put('/vault/source/a.txt', [1, 2]);
    put('/vault/source/b.txt', [3, 4]);
    put('/vault/active/deep/inside.txt', [5]);
  }

  final String account;
  final reads = <String>[];
  final objectIds = <String, String>{};
  final versions = <String, String>{};
  final deniedPaths = <String>{};
  Completer<void>? readGate;
  Completer<void>? readStarted;
  String gatedPath = '/vault';

  @override
  String get providerName => 'Snapshot drop fixture';
  @override
  String get userId => account;
  @override
  String get rootPath => '/vault';
  @override
  String get bucketId => 'snapshot-bucket';

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    reads.add(path);
    final gate = path == gatedPath ? readGate : null;
    if (gate != null) {
      if (!(readStarted?.isCompleted ?? true)) readStarted!.complete();
      await gate.future;
    }
    if (deniedPaths.contains(path)) {
      throw const FileSystemException('Directory access is denied.');
    }
    final result = await super.listPath(path);
    for (final group in ['files', 'folders']) {
      for (final row in result[group] as List) {
        final itemPath = row['path'] as String;
        row['uuid'] = objectIds[itemPath] ?? '$account:$itemPath';
        row['etag'] = versions[itemPath] ?? 'revision-1';
      }
    }
    return result;
  }

  void blockRead() {
    readGate = Completer<void>();
    readStarted = Completer<void>();
  }

  void releaseRead() {
    final gate = readGate;
    readGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? get userEmail => '${client.account}@example.test';
  @override
  String get providerName => client.providerName;

  void replace(_Cloud next) {
    client = next;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A virtual grant backed by real fixture directories. Snapshot reads have no
/// navigation, permission-request or shared-cache side effects.
class _GrantedLocal extends Fake
    implements
        LocalFileService,
        LocalFileSourceIdentity,
        LocalDirectorySnapshotReader {
  _GrantedLocal(this.root) : currentPath = p.join(root, 'active', 'deep');

  final String root;
  Object identity = Object();
  final identityOverrides = <String, Object>{};
  int interactiveReads = 0;
  int accessRequests = 0;
  int snapshots = 0;
  bool denySnapshot = false;
  List<FileSystemEntity>? snapshotEntries;
  Completer<void>? snapshotGate;
  Completer<void>? snapshotStarted;

  String path(String relative) => p.join(root, relative);

  @override
  String currentPath;
  @override
  String? get grantedBasePath => root;
  @override
  Object? sourceIdentityForPath(String path) {
    final normalized = p.normalize(path);
    if (normalized != root && !p.isWithin(root, normalized)) return null;
    return identityOverrides[normalized] ?? identity;
  }

  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => root;
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> hasAccessToPath(String path) async =>
      sourceIdentityForPath(path) != null;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    interactiveReads++;
    currentPath = path;
    return Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async {
    snapshots++;
    final gate = snapshotGate;
    if (gate != null) {
      if (!(snapshotStarted?.isCompleted ?? true)) snapshotStarted!.complete();
      await gate.future;
    }
    if (denySnapshot) {
      throw PathAccessException(path, const OSError('Access denied', 13));
    }
    return snapshotEntries ??
        await Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<bool> ensureAccess(String path) async {
    accessRequests++;
    throw StateError('A drop verification must not request a grant.');
  }

  void blockSnapshot() {
    snapshotGate = Completer<void>();
    snapshotStarted = Completer<void>();
  }

  void releaseSnapshot() {
    final gate = snapshotGate;
    snapshotGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}

class _NativeBookmarks extends Fake implements SecureBookmarks {
  final started = <String>[];
  final stopped = <String>[];

  @override
  Future<bool> startAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    started.add(entity.path);
    return true;
  }

  @override
  Future<bool> stopAccessingSecurityScopedResource(
    FileSystemEntity entity,
  ) async {
    stopped.add(entity.path);
    return true;
  }
}

class _NativeLocal extends MacosFileService {
  _NativeLocal(Directory first, Directory second, _NativeBookmarks bookmarks)
    : selectedRoot = first.path,
      super(
        bookmarks: bookmarks,
        resolveBookmarks: () async => [first, second],
      ) {
    currentPath = first.path;
  }

  // Selecting another native root changes presentation, while the real
  // scoped-read implementation can still use either saved bookmark.
  String selectedRoot;
  int accessRequests = 0;

  @override
  String get grantedBasePath => selectedRoot;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    accessRequests++;
    throw StateError('An existing native scope must not request a picker.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = FolderDropService();
  late Directory localRoot;
  late _GrantedLocal local;
  late _Cloud cloud;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier source;
  late PanelNotifier destination;
  late PanelFileOrigin ancestorOrigin;
  late FileItem ancestorFolder;

  FileItem row(PanelNotifier panel, String path) =>
      panel.files!.singleWhere((file) => file.path == path);

  PanelDragData drag({PanelNotifier? panel, List<FileItem>? files}) {
    final host = panel ?? source;
    return PanelDragData(
      sourceSide: host.side,
      files: files ?? [row(host, '/vault/source/a.txt')],
    )..captureFrom(host);
  }

  CapturedFolderDropTarget? snapshot({
    PanelNotifier? panel,
    PanelFileOrigin? origin,
    FileItem? folder,
    String parent = '/vault',
    bool Function()? isCurrent,
  }) => service.captureSnapshot(
    panel ?? destination,
    folder ?? ancestorFolder,
    local,
    snapshotOrigin: origin ?? ancestorOrigin,
    directoryPath: parent,
    snapshotIsCurrent: isCurrent ?? () => true,
  );

  Matcher failure(PanelDragFailure value) => isA<PanelDragException>().having(
    (error) => error.failure,
    'failure',
    value,
  );

  Future<void> showSource(PanelNotifier panel, PanelSource source) async {
    container.read(panelSourceProvider(panel.side).notifier).setSource(source);
    await panel.refresh();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    localRoot = await Directory.systemTemp.createTemp('snapshot-drop-');
    for (final path in ['active/deep', 'drop', 'source']) {
      await Directory(p.join(localRoot.path, path)).create(recursive: true);
    }
    await File(p.join(localRoot.path, 'source', 'local.txt'))
        .writeAsString('a');
    local = _GrantedLocal(localRoot.path);
    cloud = _Cloud('first');
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    source = container.read(panelProvider(PanelSide.local));
    destination = container.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    await showSource(
      source,
      RemotePanelSource(
        providerName: cloud.providerName,
        client: cloud,
        path: '/vault/source',
      ),
    );
    await showSource(
      destination,
      RemotePanelSource(
        providerName: cloud.providerName,
        client: cloud,
        path: '/vault',
      ),
    );
    ancestorOrigin = destination.captureCurrentOrigin();
    ancestorFolder = row(destination, '/vault/drop');
    await destination.navigateToPath('/vault/active/deep');
  });

  tearDown(() async {
    cloud.releaseRead();
    local.releaseSnapshot();
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    await localRoot.delete(recursive: true);
  });

  test(
    'a remote ancestor requests its exact folder without navigating',
    () async {
      final data = drag(
        files: [
          row(source, '/vault/source/a.txt'),
          row(source, '/vault/source/b.txt'),
        ],
      );
      final beforePath = destination.currentPath;
      final beforeRows = destination.files;
      final beforeTab = destination.activeTabId;
      final target = snapshot()!;
      expect(destination.originForOperation(ancestorFolder), isNull);
      final reads = cloud.reads.length;
      final prepared = await service.prepare(
        data,
        target,
        kind: FileOperationKind.copy,
      );
      expect(prepared.destination.path, '/vault/drop');
      expect(prepared.groups, same(data.capturedGroups));
      expect(prepared.files.map((file) => file.path), [
        '/vault/source/a.txt',
        '/vault/source/b.txt',
      ]);
      expect(cloud.reads.skip(reads), ['/vault']);
      expect(destination.currentPath, beforePath);
      expect(destination.files, same(beforeRows));
      expect(destination.activeTabId, beforeTab);
      expect(destination.originForOperation(ancestorFolder), isNull);
      expect(cloud.writes, isEmpty);
    },
  );

  test('same-pane ancestor moves preserve the live source selection', () async {
    final file = row(destination, '/vault/active/deep/inside.txt');
    destination.toggleSelection(file);
    final data = drag(panel: destination, files: [file]);
    final prepared = await service.prepare(
      data,
      snapshot()!,
      kind: FileOperationKind.move,
    );
    expect(prepared.kind, FileOperationKind.move);
    expect(prepared.files.single, same(file));
    expect(prepared.destination.path, '/vault/drop');
    expect(destination.currentPath, '/vault/active/deep');
    expect(destination.selection.single, same(file));
    expect(data.isCurrent, isTrue);
    expect(cloud.writes, isEmpty);
  });

  test(
    'a destination capability survives navigation after review only',
    () async {
      final target = snapshot()!;
      final prepared = await service.prepare(
        drag(),
        target,
        kind: FileOperationKind.copy,
      );
      await destination.navigateToPath('/vault/active');
      expect(target.isCurrent, isFalse);
      expect(prepared.destination.origin.isCurrent, isTrue);
      expect(prepared.destination.backend.isCurrent, isTrue);
      auth.replace(_Cloud('replacement'));
      expect(prepared.destination.origin.isCurrent, isFalse);
      expect(prepared.destination.backend.isCurrent, isFalse);
    },
  );

  test('snapshot rows cannot escape the configured root or their parent', () {
    final cases = <({String parent, FileItem folder})>[
      (
        parent: '/',
        folder: FileItem(name: 'outside', path: '/outside', isFolder: true),
      ),
      (
        parent: '/vault',
        folder: FileItem(
          name: 'outside',
          path: '/vault/../../outside',
          isFolder: true,
        ),
      ),
      (
        parent: '/vault/source',
        folder: FileItem(
          name: 'folder',
          path: '/vault/source/folder',
          isFolder: true,
        ),
      ),
      (
        parent: '/vault/active/deep',
        folder: FileItem(
          name: 'nested',
          path: '/vault/active/deep/nested',
          isFolder: true,
        ),
      ),
      (
        parent: '/vault',
        folder: FileItem(name: 'drop', path: 'drop', isFolder: true),
      ),
      (
        parent: '/vault',
        folder: FileItem(
          name: 'drop',
          path: '/vault/drop\u0000',
          isFolder: true,
        ),
      ),
      (
        parent: '/vault',
        folder: FileItem(name: 'other', path: '/vault/drop', isFolder: true),
      ),
      (
        parent: '/vault',
        folder: FileItem(name: '..', path: '/vault/..', isFolder: true),
      ),
      (
        parent: '/vault',
        folder: FileItem(name: '.', path: '/vault/.', isFolder: true),
      ),
      (parent: '/vault', folder: FileItem(name: 'drop', isFolder: true)),
      (
        parent: '/vault',
        folder: FileItem(
          name: 'drop',
          path: '/vault/drop',
          isFolder: true,
          isSymlink: true,
        ),
      ),
      (
        parent: '/vault',
        folder: FileItem(name: 'drop', path: '/vault/drop', isFolder: false),
      ),
    ];
    for (final candidate in cases) {
      expect(
        snapshot(parent: candidate.parent, folder: candidate.folder),
        isNull,
        reason:
            '${candidate.parent} / ${candidate.folder.path} / ${candidate.folder.name}',
      );
    }
    expect(cloud.writes, isEmpty);
  });

  test('a same-account origin from another client is rejected', () async {
    final other = _Cloud(cloud.account);
    final otherContainer = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(other)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    addTearDown(otherContainer.dispose);
    final panel = otherContainer.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    otherContainer
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(
          RemotePanelSource(
            providerName: other.providerName,
            client: other,
            path: '/vault',
          ),
        );
    await panel.refresh();
    final otherOrigin = panel.captureCurrentOrigin();
    expect(otherOrigin.isCurrent, isTrue);
    expect(otherOrigin.storageReference, ancestorOrigin.storageReference);
    expect(snapshot(origin: otherOrigin), isNull);
    expect(cloud.writes, isEmpty);
    expect(other.writes, isEmpty);
  });

  test('removed snapshots and virtual result panes cannot become targets', () {
    expect(snapshot(isCurrent: () => false), isNull);
    destination.showSearchResults([
      ancestorFolder,
    ], origin: destination.captureCurrentOrigin());
    expect(snapshot(), isNull);
    expect(cloud.writes, isEmpty);
  });

  for (final mutation in ['refresh', 'tab', 'account', 'snapshot']) {
    test(
      '$mutation changes during verification reject the original drop',
      () async {
        var present = true;
        final target = snapshot(isCurrent: () => present)!;
        final data = drag();
        cloud.blockRead();
        final preparation = service.prepare(
          data,
          target,
          kind: FileOperationKind.copy,
        );
        final assertion = expectLater(
          preparation,
          throwsA(isA<PanelDragException>()),
        );
        await cloud.readStarted!.future;
        switch (mutation) {
          case 'refresh':
            await destination.refresh();
          case 'tab':
            destination.addTab(path: '/vault/active/deep');
            await destination.refresh();
          case 'account':
            auth.replace(_Cloud('replacement'));
          case 'snapshot':
            present = false;
        }
        expect(target.isCurrent, isFalse);
        cloud.releaseRead();
        await assertion;
        expect(cloud.writes, isEmpty);
      },
    );
  }

  for (final changed in ['object', 'version', 'removed']) {
    test(
      'fresh ancestor verification rejects a $changed destination',
      () async {
        final target = snapshot()!;
        if (changed == 'object') {
          cloud.objectIds['/vault/drop'] = 'replacement-object';
        } else if (changed == 'version') {
          cloud.versions['/vault/drop'] = 'revision-2';
        } else {
          cloud.directories.remove('/vault/drop');
        }
        await expectLater(
          service.prepare(drag(), target, kind: FileOperationKind.copy),
          throwsA(failure(PanelDragFailure.destinationChanged)),
        );
        expect(cloud.writes, isEmpty);
      },
    );
  }

  test('a denied fresh ancestor read fails without writing', () async {
    final target = snapshot()!;
    cloud.deniedPaths.add('/vault');
    await expectLater(
      service.prepare(drag(), target, kind: FileOperationKind.copy),
      throwsA(failure(PanelDragFailure.unavailable)),
    );
    expect(cloud.writes, isEmpty);
  });

  Future<CapturedFolderDropTarget> localTarget({FileItem? folder}) async {
    await showSource(destination, LocalPanelSource(local.path('active/deep')));
    final origin = destination.captureCurrentOrigin();
    return snapshot(
      origin: origin,
      parent: local.root,
      folder:
          folder ??
          FileItem(
            name: 'drop',
            path: local.path('drop'),
            isFolder: true,
            // Virtual folder listings historically used a presentation fallback.
            // It must not be mistaken for a real filesystem version.
            updatedAt: DateTime.utc(1999),
          ),
    )!;
  }

  test('virtual local verification reads a fresh snapshot without navigation or prompts', () async {
    final target = await localTarget();
    final currentPath = local.currentPath;
    final interactiveReads = local.interactiveReads;
    final prepared = await service.prepare(
      drag(),
      target,
      kind: FileOperationKind.copy,
    );
    expect(prepared.destination.path, local.path('drop'));
    expect(local.snapshots, 1);
    expect(local.interactiveReads, interactiveReads);
    expect(local.currentPath, currentPath);
    expect(local.accessRequests, 0);
    expect(cloud.writes, isEmpty);
    expect(await Directory(local.path('drop')).list().isEmpty, isTrue);
  });

  test('same-name local grant replacement invalidates the destination during verification', () async {
    final target = await localTarget();
    final oldGrantPath = local.grantedBasePath;
    local.blockSnapshot();
    final preparation = service.prepare(
      drag(),
      target,
      kind: FileOperationKind.copy,
    );
    final assertion = expectLater(
      preparation,
      throwsA(isA<PanelDragException>()),
    );
    await local.snapshotStarted!.future;
    local.identity = Object();
    expect(local.grantedBasePath, oldGrantPath);
    expect(target.isCurrent, isFalse);
    local.releaseSnapshot();
    await assertion;
    expect(local.accessRequests, 0);
    expect(cloud.writes, isEmpty);
  });

  test(
    'local source grant replacement invalidates a drag before remote review',
    () async {
      await showSource(source, LocalPanelSource(local.path('source')));
      final file = row(source, local.path('source/local.txt'));
      final data = drag(files: [file]);
      final target = snapshot()!;
      cloud.blockRead();
      final preparation = service.prepare(
        data,
        target,
        kind: FileOperationKind.copy,
      );
      final assertion = expectLater(
        preparation,
        throwsA(isA<PanelDragException>()),
      );
      await cloud.readStarted!.future;
      local.identity = Object();
      expect(data.isCurrent, isFalse);
      cloud.releaseRead();
      await assertion;
      expect(local.accessRequests, 0);
      expect(cloud.writes, isEmpty);
    },
  );

  test(
    'local snapshot permission denial fails closed without a picker',
    () async {
      final target = await localTarget();
      local.denySnapshot = true;
      final interactiveReads = local.interactiveReads;
      await expectLater(
        service.prepare(drag(), target, kind: FileOperationKind.copy),
        throwsA(failure(PanelDragFailure.unavailable)),
      );
      expect(local.interactiveReads, interactiveReads);
      expect(local.accessRequests, 0);
      expect(cloud.writes, isEmpty);
    },
  );

  for (final invalid in ['missing', 'duplicate', 'file', 'link', 'outside']) {
    test(
      'local snapshot $invalid entries never authorize a folder target',
      () async {
        final target = await localTarget();
        final path = local.path('drop');
        local.snapshotEntries = switch (invalid) {
          'missing' => [],
          'duplicate' => [Directory(path), Directory(path)],
          'file' => [File(path)],
          'link' => [Link(path)],
          _ => [Directory(p.join(p.dirname(local.root), 'drop'))],
        };
        await expectLater(
          service.prepare(drag(), target, kind: FileOperationKind.copy),
          throwsA(isA<PanelDragException>()),
        );
        expect(local.accessRequests, 0);
        expect(cloud.writes, isEmpty);
      },
    );
  }

  test(
    'local ancestors cannot cross grant identities or leave the grant root',
    () async {
      await showSource(
        destination,
        LocalPanelSource(local.path('active/deep')),
      );
      final origin = destination.captureCurrentOrigin();
      final folder = FileItem(
        name: 'drop',
        path: local.path('drop'),
        isFolder: true,
      );
      local.identityOverrides[local.path('drop')] = Object();
      expect(
        snapshot(origin: origin, parent: local.root, folder: folder),
        isNull,
      );
      local.identityOverrides.clear();
      expect(
        snapshot(
          origin: origin,
          parent: p.dirname(local.root),
          folder: FileItem(
            name: p.basename(local.root),
            path: local.root,
            isFolder: true,
          ),
        ),
        isNull,
      );
      expect(local.snapshots, 0);
      expect(local.accessRequests, 0);
    },
  );

  test(
    'a reviewed native target survives choosing another available grant',
    () async {
      final first = Directory(await localRoot.resolveSymbolicLinks());
      final otherTemporary = await Directory.systemTemp.createTemp(
        'other-native-grant-',
      );
      addTearDown(() => otherTemporary.delete(recursive: true));
      final second = Directory(await otherTemporary.resolveSymbolicLinks());
      final bookmarks = _NativeBookmarks();
      final native = _NativeLocal(first, second, bookmarks);
      final nativeContainer = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => _Auth(cloud)),
          localFileServiceProvider.overrideWithValue(native),
        ],
      );
      addTearDown(nativeContainer.dispose);
      final nativePanel = nativeContainer.read(panelProvider(PanelSide.local));
      await Future<void>.delayed(Duration.zero);
      await nativePanel.navigateToPath(
        first.path,
        origin: nativePanel.captureLocalClipboardOrigin(first.path),
      );
      final targetPath = p.join(first.path, 'drop');
      final target = service.capture(
        nativePanel,
        row(nativePanel, targetPath),
        native,
      )!;
      final prepared = await service.prepare(
        drag(),
        target,
        kind: FileOperationKind.copy,
      );

      native.selectedRoot = second.path;
      expect(await native.hasAccessToPath(targetPath), isTrue);
      expect(prepared.destination.origin.isCurrent, isTrue);
      expect(prepared.destination.backend.isCurrent, isTrue);
      final fresh = await prepared.destination.backend.stat(targetPath);
      expect(fresh?.path, targetPath);
      expect(fresh?.isFolder, isTrue);
      expect(bookmarks.started, contains(first.path));
      expect(bookmarks.stopped, bookmarks.started);
      expect(native.grantedBasePath, second.path);
      expect(native.accessRequests, 0);
      expect(cloud.writes, isEmpty);
      expect(await Directory(targetPath).list().isEmpty, isTrue);
    },
  );
}
