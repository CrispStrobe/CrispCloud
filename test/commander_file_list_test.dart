import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_selection_pattern.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:crisp_cloud/widgets/pattern_selection_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake implements CloudStorageClient {
  @override
  String get providerName => 'Test cloud';
  @override
  String? get userId => 'account-a';
  @override
  String? get bucketId => 'bucket-a';
  @override
  String get rootPath => '/';
  bool authenticated = true;
  @override
  bool get isAuthenticated => authenticated;
  final paths = <String>[];
  final listings = <String, List<String>>{
    '/': ['a.txt', 'b.txt'],
    '/one': ['same.txt'],
    '/two': ['same.txt'],
  };
  Completer<void>? delay;
  Completer<Uint8List>? pendingDownload;
  final downloads = <String>[];
  Uint8List archiveBytes = Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('hello.txt', 5, [72, 101, 108, 108, 111])),
    ),
  );

  @override
  Future<Uint8List> downloadFileBytes(
    String remotePath, {
    Function(int, int)? onProgress,
  }) async {
    downloads.add(remotePath);
    return pendingDownload == null
        ? archiveBytes
        : await pendingDownload!.future;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    paths.add(path);
    await delay?.future;
    return {
      'files': [
        for (final name in listings[path] ?? const <String>[])
          {'name': name, 'size': 10},
      ],
      'folders': <Map<String, dynamic>>[],
    };
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool isConnected = true;
  @override
  String? userEmail = 'a@example.test';
  @override
  String get providerName => client.providerName;
  void connection(bool connected) {
    isConnected = connected;
    client.authenticated = connected;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  String? directory;
  @override
  String? get grantedBasePath => directory ?? '/';
  @override
  Future<String> getInitialPath() async => directory ?? '/';
  @override
  Future<String> getSafeFallbackDirectory() async => directory ?? '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      directory == null
      ? []
      : Directory(path).list(followLinks: false).toList();
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late _Auth auth;
  late _Local local;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    auth = _Auth(cloud);
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
  });

  tearDown(() => container.dispose());

  FileItem item(String path) =>
      FileItem(name: path.split('/').last, path: path, isFolder: false);

  Future<PanelNotifier> remote() async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    return panel;
  }

  test(
    'path-based cloud providers have distinct full-path selection identities',
    () async {
      final panel = await remote();
      panel.selectAll();
      expect(panel.selection.map((file) => file.path).toSet(), {
        '/a.txt',
        '/b.txt',
      });
      expect(panel.captureCurrentOrigin().source, isA<RemotePanelSource>());
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        isA<LocalPanelSource>(),
      );
    },
  );

  test(
    'pattern actions mark visible matches and preserve unmatching marks',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/a.jpg'),
        item('/b.png'),
        item('/thumb.jpg'),
        item('/c.txt'),
      ]);
      panel.applyPatternSelection(FileSelectionPattern('*.jpg;*.png|thumb*'));
      expect(panel.selection.map((file) => file.name).toSet(), {
        'a.jpg',
        'b.png',
      });
      panel.applyPatternSelection(
        FileSelectionPattern('*.png'),
        action: SelectionAction.deselect,
      );
      expect(panel.selection.single.name, 'a.jpg');
      panel.applyPatternSelection(
        FileSelectionPattern('*.jpg'),
        action: SelectionAction.invert,
      );
      expect(panel.selection.single.name, 'thumb.jpg');
      panel.setFilter('b');
      panel.applyPatternSelection(
        FileSelectionPattern('*'),
        action: SelectionAction.replace,
      );
      expect(panel.selection.single.name, 'b.png');
      expect(panel.filterQuery, 'b');
      expect(() => panel.selectByPattern('*|'), throwsFormatException);
      expect(panel.selection.single.name, 'b.png');
    },
  );

  test(
    'unverified same-path objects do not gain operation permission',
    () async {
      final panel = await remote();
      final listed = panel.files!.first;
      expect(panel.captureOperationOrigin([listed]).isCurrent, isTrue);
      expect(
        () => panel.captureOperationOrigin([listed.copyWith()]),
        throwsStateError,
      );
      panel.showSearchResults([listed.copyWith()]);
      expect(
        () => panel.captureOperationOrigin(panel.files!),
        throwsStateError,
      );
    },
  );

  test(
    'feed to panel keeps paths while editor writeback stays restricted',
    () async {
      final panel = await remote();
      final listed = panel.files!.first;
      panel.showSearchResults([listed]);
      final result = panel.files!.single;
      expect(result.path, '/a.txt');
      expect(panel.captureOperationOrigin([result]).isCurrent, isTrue);
      expect(panel.originForFile(result), isNull);
      expect(panel.originForFile(listed), isNull);
    },
  );

  test(
    'result snapshot survives refresh and duplicate basenames remain distinct',
    () async {
      final panel = await remote();
      final origin = panel.captureRemoteSearchOrigin();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: origin);
      final requests = cloud.paths.length;
      panel.selectAll();
      expect(panel.selection.length, 2);
      await panel.refresh();
      expect(cloud.paths.length, requests);
      expect(panel.files!.length, 2);
      expect(panel.exportFileListPaths().split('\n').toSet(), {
        '/one/same.txt',
        '/two/same.txt',
      });
    },
  );

  test(
    'result operations fail closed after disconnect and reconnect',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final pinned = panel.captureOperationOrigin(panel.files!);
      auth.connection(false);
      auth.connection(true);
      expect(pinned.isCurrent, isFalse);
      expect(panel.canOperateOnFileList, isFalse);
      expect(
        () => panel.captureOperationOrigin(panel.files!),
        throwsStateError,
      );
    },
  );

  test('remove-from-list never deletes underlying local files', () async {
    final root = await Directory.systemTemp.createTemp('commander-list-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/one').create();
    await Directory('${root.path}/two').create();
    final a = await File('${root.path}/one/same.txt').writeAsString('one');
    final b = await File('${root.path}/two/same.txt').writeAsString('two');
    local.directory = root.path;
    final panel = container.read(panelProvider(PanelSide.local));
    await panel.navigateToPath(root.path);
    final result = await panel.importFileListPaths('${a.path}\n${b.path}');
    expect(result.loaded, 2);
    final row = panel.files!.firstWhere((file) => file.path == a.path);
    panel.removeFromFileList([row]);
    expect(panel.files!.single.path, b.path);
    expect(await a.readAsString(), 'one');
    expect(await b.readAsString(), 'two');
    expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
  });

  test('import verifies remote paths and reports missing rows', () async {
    final panel = await remote();
    final result = await panel.importFileListPaths(
      '/one/same.txt\n/two/same.txt\n/two/missing.txt',
    );
    expect(result.loaded, 2);
    expect(result.failures.keys, ['/two/missing.txt']);
    expect(panel.files!.map((item) => item.name), ['same.txt', 'same.txt']);
    expect(
      panel.captureOperationOrigin(panel.files!).source,
      isA<RemotePanelSource>(),
    );
  });

  test(
    'account change during import cannot publish an actionable list',
    () async {
      final panel = await remote();
      cloud.delay = Completer<void>();
      final import = panel.importFileListPaths('/one/same.txt');
      await Future<void>.delayed(Duration.zero);
      auth.connection(false);
      auth.connection(true);
      cloud.delay!.complete();
      await expectLater(import, throwsStateError);
      expect(panel.showingSearchResults, isFalse);
    },
  );

  test(
    'list updates are keyed by full source paths, retaining provenance',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      panel.applyFileListChanges({'/one/same.txt': item('/one/new.txt')});
      expect(panel.files!.map((item) => item.path).toSet(), {
        '/one/new.txt',
        '/two/same.txt',
      });
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
      panel.applyFileListChanges({'/one/new.txt': null});
      expect(panel.files!.single.path, '/two/same.txt');
    },
  );

  test('completion updates the saved source list without changing same-path rows in another storage', () async {
    final panel = await remote();
    panel.showSearchResults([
      item('/one/same.txt'),
      item('/two/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());
    panel.selectAll();
    final originalTab = panel.activeTabId;
    final operationOrigin = panel.captureOperationOrigin(panel.files!);
    panel.addTab(path: '/two');
    await panel.refresh();
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/local'));
    await panel.refresh();
    final localOrigin = panel.captureCurrentOrigin();
    expect(localOrigin.source, isA<LocalPanelSource>());
    panel.showSearchResults([
      item('/one/same.txt'),
      item('/two/same.txt'),
    ], origin: localOrigin);
    panel.selectAll();
    final localTab = panel.activeTabId;
    final localRows = List<FileItem>.of(panel.files!);

    expect(operationOrigin.isCurrent, isTrue);
    panel.applyFileListChanges({
      '/one/same.txt': null,
      '/two/same.txt': item('/two/renamed.txt'),
    }, origin: operationOrigin);

    expect(panel.files, localRows);
    expect(panel.selection.length, 2);
    panel.selectTab(originalTab);
    expect(panel.files!.single.path, '/two/renamed.txt');
    expect(panel.selection.single.path, '/two/renamed.txt');
    expect(
      panel.captureOperationOrigin(panel.files!).source,
      isA<RemotePanelSource>(),
    );
    panel.selectTab(localTab);
    expect(panel.files, localRows);
    expect(panel.selection.length, 2);
  });

  test(
    'completion updates an inactive list while a directory tab is active',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final originalTab = panel.activeTabId;
      final operationOrigin = panel.captureOperationOrigin(panel.files!);
      panel.addTab(path: '/two');
      await panel.refresh();
      expect(panel.showingSearchResults, isFalse);
      final activeDirectory = panel.currentPath;
      final directoryRows = List<FileItem>.of(panel.files!);

      panel.applyFileListChanges({
        '/one/same.txt': null,
      }, origin: operationOrigin);

      expect(panel.showingSearchResults, isFalse);
      expect(panel.currentPath, activeDirectory);
      expect(panel.files, directoryRows);
      panel.selectTab(originalTab);
      expect(panel.files!.single.path, '/two/same.txt');
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
    },
  );

  test(
    'captured source updates remain applicable after same-storage navigation',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      final operationOrigin = panel.captureOperationOrigin(panel.files!);
      await panel.navigateToPath('/two');
      final currentOrigin = panel.captureCurrentOrigin();
      expect(operationOrigin.source.currentPath, '/');
      expect(currentOrigin.source.currentPath, '/two');
      panel.showSearchResults([item('/one/same.txt')], origin: currentOrigin);

      panel.applyFileListChanges({
        '/one/same.txt': item('/one/renamed.txt'),
      }, origin: operationOrigin);

      expect(panel.files!.single.path, '/one/renamed.txt');
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
    },
  );

  test('old-account completion cannot change a new session list on the same client', () async {
    final panel = await remote();
    panel.showSearchResults([
      item('/one/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());
    final operationOrigin = panel.captureOperationOrigin(panel.files!);
    auth.connection(false);
    auth.connection(true);
    panel.showSearchResults([
      item('/one/same.txt'),
    ], origin: panel.captureRemoteSearchOrigin());

    panel.applyFileListChanges({
      '/one/same.txt': null,
    }, origin: operationOrigin);

    expect(panel.files!.single.path, '/one/same.txt');
    expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
  });

  test(
    'open containing folder uses the result path and selects that exact file',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/one/same.txt'),
        item('/two/same.txt'),
      ], origin: panel.captureRemoteSearchOrigin());
      await panel.openContainingFolder(
        panel.files!.firstWhere((file) => file.path == '/two/same.txt'),
      );
      expect(panel.showingSearchResults, isFalse);
      expect(cloud.paths.last, '/two');
      expect(panel.currentPath, '/two');
      expect(panel.selection.single.path, '/two/same.txt');
    },
  );

  test(
    'tabs retain virtual lists and their selection in this session',
    () async {
      final panel = await remote();
      panel.showSearchResults(
        [item('/one/same.txt'), item('/two/same.txt')],
        origin: panel.captureRemoteSearchOrigin(),
        title: 'Search: same',
      );
      final listTab = panel.activeTabId;
      panel.toggleSelection(panel.files!.first);
      panel.addTab(path: '/two');
      await panel.refresh();
      expect(panel.showingSearchResults, isFalse);
      panel.selectTab(listTab);
      expect(panel.showingSearchResults, isTrue);
      expect(panel.fileListTitle, 'Search: same');
      expect(panel.files!.length, 2);
      expect(panel.selection.length, 1);
      expect(panel.captureOperationOrigin(panel.files!).isCurrent, isTrue);
    },
  );

  testWidgets('pattern dialog validates regex and applies visible matches', (
    tester,
  ) async {
    final panel = await remote();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () => showPatternSelectionDialog(
                    context,
                    ref,
                    PanelSide.remote,
                  ),
                  child: const Text('Open selection tool'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open selection tool'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regular expression'));
    await tester.enterText(
      find.byKey(const ValueKey('selection-pattern')),
      '[',
    );
    await tester.pump();
    final invalid = tester.widget<FilledButton>(
      find.byKey(const ValueKey('apply-pattern-selection')),
    );
    expect(invalid.onPressed, isNull);
    expect(panel.selection, isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('selection-pattern')),
      r'^[ab]\.txt$',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('apply-pattern-selection')));
    await tester.pumpAndSettle();
    expect(panel.selection.map((item) => item.path).toSet(), {
      '/a.txt',
      '/b.txt',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('numpad plus opens selection instead of entering quick search', (
    tester,
  ) async {
    final panel = await remote();
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: FileListView(
              side: PanelSide.remote,
              files: panel.files!,
              scrollController: scroll,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    panel.focusList();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await tester.pumpAndSettle();
    expect(find.text('Select by pattern'), findsOneWidget);
    expect(panel.filterQuery, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadSubtract);
    await tester.pumpAndSettle();
    expect(find.text('Select by pattern'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'remote archives in a left-pane result list use captured cloud storage',
    () async {
      final panel = container.read(panelProvider(PanelSide.local));
      await Future<void>.delayed(Duration.zero);
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(
            RemotePanelSource(
              providerName: cloud.providerName,
              client: cloud,
              path: '/',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      panel.showSearchResults([
        item('/two/archive.zip'),
      ], origin: panel.captureRemoteSearchOrigin());
      await panel.navigateInto(panel.files!.single);
      expect(cloud.downloads, ['/two/archive.zip']);
      expect(panel.isInArchive, isTrue);
      expect(panel.archiveSource!.parent, isA<RemotePanelSource>());
      final member = panel.files!.single;
      expect(panel.originForFile(member), isNull);
      expect(
        String.fromCharCodes(await panel.readArchiveMember(member)),
        'Hello',
      );
      panel.exitArchive();
      await Future<void>.delayed(Duration.zero);
      expect(panel.isInArchive, isFalse);
      expect(cloud.paths.last, '/two');
      expect(panel.currentPath, '/two');
    },
  );

  test(
    'account change during archive download cannot publish old-account members',
    () async {
      final panel = await remote();
      panel.showSearchResults([
        item('/two/archive.zip'),
      ], origin: panel.captureRemoteSearchOrigin());
      cloud.pendingDownload = Completer<Uint8List>();
      final opening = panel.enterArchive(panel.files!.single);
      await Future<void>.delayed(Duration.zero);
      auth.connection(false);
      auth.connection(true);
      cloud.pendingDownload!.complete(cloud.archiveBytes);
      await opening;
      expect(panel.isInArchive, isFalse);
      expect(cloud.downloads, ['/two/archive.zip']);
    },
  );

  test('refresh follows actual storage in either pane', () async {
    final left = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    container
        .read(panelSourceProvider(PanelSide.local).notifier)
        .setSource(
          RemotePanelSource(
            providerName: cloud.providerName,
            client: cloud,
            path: '/two',
          ),
        );
    await Future<void>.delayed(Duration.zero);
    await left.refresh();
    expect(left.captureCurrentOrigin().source, isA<RemotePanelSource>());
    expect(
      left.files!.where((file) => file.name != '..').single.path,
      '/two/same.txt',
    );

    final right = await remote();
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/tmp'));
    await Future<void>.delayed(Duration.zero);
    final requests = cloud.paths.length;
    await right.refresh();
    expect(right.captureCurrentOrigin().source, isA<LocalPanelSource>());
    expect(cloud.paths.length, requests);
    expect(right.currentPath, '/tmp');
  });
}
