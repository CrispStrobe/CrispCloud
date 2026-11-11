import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_drag_data.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/file_column_view.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:crisp_cloud/widgets/folder_drop_target.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show kSecondaryMouseButton, PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account, {this.root = '/'});
  final String account;
  final String root;
  final fileNames = <String, List<String>>{
    '/': ['root.txt'],
    '/docs': ['keep.txt', 'other.txt'],
    '/docs/nested': ['deep.txt'],
    '/other': ['elsewhere.txt'],
  };
  final folderNames = <String, List<String>>{
    '/': ['docs', 'other'],
    '/docs': ['nested'],
  };
  final reads = <String>[];
  String? delayedPath;
  Completer<void>? delay;
  final failures = <String>{};

  @override
  String get providerName => 'Test cloud';
  @override
  String get userId => account;
  @override
  String get bucketId => 'test-bucket';
  @override
  String get rootPath => root;
  @override
  bool get isAuthenticated => true;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    reads.add(path);
    final listedFiles = List<String>.of(fileNames[path] ?? const []);
    final listedFolders = List<String>.of(folderNames[path] ?? const []);
    final failed = failures.contains(path);
    if (path == delayedPath) await delay?.future;
    if (failed) throw StateError('Ancestor listing unavailable');
    return {
      'files': [
        for (final name in listedFiles)
          {'name': name, 'size': 12, 'uuid': '$account:$path/$name'},
      ],
      'folders': [
        for (final name in listedFolders)
          {'name': name, 'uuid': '$account:$path/$name'},
      ],
    };
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? userEmail = 'primary@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake
    implements LocalFileService, LocalDirectorySnapshotReader {
  String? grantedRoot = '/';
  final snapshots = <String, List<FileSystemEntity>>{};
  final snapshotReads = <String>[];
  final denied = <String>{};
  final snapshotGates = <String, Completer<void>>{};
  final listings = <String, List<FileSystemEntity>>{};
  final directoryReads = <String>[];
  final directoryGates = <String, Completer<void>>{};
  final directoryEntered = <String, Completer<void>>{};
  int accessRequests = 0;
  int ensuredAccess = 0;
  @override
  String currentPath = '/';
  @override
  String? get grantedBasePath => grantedRoot;
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    directoryReads.add(path);
    final result = List<FileSystemEntity>.of(listings[path] ?? const []);
    if (directoryEntered[path] case final entered?) {
      if (!entered.isCompleted) entered.complete();
    }
    if (directoryGates[path] case final gate?) await gate.future;
    return result;
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async {
    snapshotReads.add(path);
    final result = List<FileSystemEntity>.of(snapshots[path] ?? const []);
    if (snapshotGates[path] case final gate?) await gate.future;
    if (denied.contains(path)) throw FileSystemException('Access denied', path);
    return result;
  }

  @override
  Future<bool> ensureAccess(String path) async {
    ensuredAccess++;
    return false;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    accessRequests++;
    return null;
  }
}

class _NamedRootLocal extends _Local implements LocalFileSourceIdentity {
  _NamedRootLocal() {
    grantedRoot = null;
  }
  Object rootIdentity = Object();
  @override
  Object? sourceIdentityForPath(String path) =>
      path == '/Photos' || path.startsWith('/Photos/') ? rootIdentity : null;
}

void main() {
  late ProviderContainer container;
  late _Cloud cloud;
  late _Local local;
  late PanelNotifier panel;
  late ScrollController scroll;
  final parentKeys = <LogicalKeyboardKey>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud('first');
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    scroll = ScrollController();
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
    container.read(focusAreaProvider.notifier).state = FocusArea.remote;
    parentKeys.clear();
  });

  tearDown(() {
    scroll.dispose();
    container.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) parentKeys.add(event.logicalKey);
                return KeyEventResult.handled;
              },
              child: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(panelProvider(PanelSide.remote));
                  return FileColumnView(
                    side: PanelSide.remote,
                    files: state.filteredFiles ?? const [],
                    scrollController: scroll,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder column(String path) => find.byKey(ValueKey('file-column:$path'));
  Finder row(String directory, String path) =>
      find.byKey(ValueKey('column-item:$directory:$path'));

  Future<void> tapRow(
    WidgetTester tester,
    String directory,
    String path,
  ) async {
    await tester.ensureVisible(row(directory, path));
    await tester.tap(row(directory, path));
    // A file row also accepts a double tap; let the single-tap recognizer win.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> openLocal(_Local service, String path) async {
    container.dispose();
    local = service;
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(service),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.navigateToPath(
      path,
      origin: panel.captureLocalClipboardOrigin(path),
    );
    expect(panel.hasVerifiedDirectoryListing, isTrue);
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
    container.read(focusAreaProvider.notifier).state = FocusArea.remote;
  }

  testWidgets(
    'a direct deep location hydrates parents without blocking its live column',
    (tester) async {
      final originalRootRow = panel.files!.firstWhere(
        (file) => file.name == 'root.txt',
      );
      await panel.navigateToPath('/docs/nested');
      final liveRows = panel.files;
      final liveReads = cloud.reads
          .where((path) => path == '/docs/nested')
          .length;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      cloud.delayedPath = '/';
      cloud.delay = gate;
      await mount(tester);
      expect(column('/docs/nested'), findsOneWidget);
      expect(row('/docs/nested', '/docs/nested/deep.txt'), findsOneWidget);
      expect(column('/docs'), findsOneWidget);
      expect(column('/'), findsNothing);
      expect(panel.files, same(liveRows));
      expect(panel.isLoading, isFalse);

      gate.complete();
      await tester.pumpAndSettle();
      expect(column('/'), findsOneWidget);
      expect(row('/', '/root.txt'), findsOneWidget);
      expect(
        cloud.reads.where((path) => path == '/docs/nested'),
        hasLength(liveReads),
      );
      expect(panel.currentPath, '/docs/nested');
      expect(panel.files, same(liveRows));
      final ancestorReads = cloud.reads.where((path) => path == '/').length;
      await tapRow(tester, '/', '/root.txt');
      expect(
        cloud.reads.where((path) => path == '/'),
        hasLength(ancestorReads + 1),
      );
      expect(panel.currentPath, '/');
      expect(panel.cursorItem?.name, 'root.txt');
      expect(panel.cursorItem, isNot(same(originalRootRow)));
      expect(panel.originForOperation(originalRootRow), isNull);
      expect(panel.originForOperation(panel.cursorItem!), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a refreshed listing rejects older ancestor hydration', (
    tester,
  ) async {
    await panel.navigateToPath('/docs/nested');
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    cloud.delayedPath = '/';
    cloud.delay = gate;
    await mount(tester);
    expect(column('/'), findsNothing);
    cloud.delayedPath = null;
    cloud.fileNames['/'] = ['fresh-root.txt'];
    await panel.refresh();
    await tester.pumpAndSettle();
    expect(row('/', '/fresh-root.txt'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(row('/', '/fresh-root.txt'), findsOneWidget);
    expect(row('/', '/root.txt'), findsNothing);
    expect(panel.currentPath, '/docs/nested');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ancestor hydration stays with the original account at identical paths',
    (tester) async {
      await panel.navigateToPath('/docs/nested');
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      cloud.delayedPath = '/';
      cloud.delay = gate;
      await mount(tester);
      final other = _Cloud('second')
        ..fileNames['/'] = ['second-root.txt']
        ..fileNames['/docs'] = ['second-parent.txt'];
      container
          .read(multiCloudProvider)
          .addConnection(
            id: 'second',
            label: 'Second account',
            provider: CloudProvider.s3,
            client: other,
          );
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(
            RemotePanelSource(
              providerName: other.providerName,
              client: other,
              path: '/docs/nested',
            ),
          );
      await tester.pumpAndSettle();
      expect(row('/', '/second-root.txt'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(row('/', '/root.txt'), findsNothing);
      expect(row('/docs', '/docs/second-parent.txt'), findsOneWidget);
      expect(
        (panel.captureCurrentOrigin().source as RemotePanelSource).client,
        same(other),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable ancestors stay skipped until an explicit refresh', (
    tester,
  ) async {
    await panel.navigateToPath('/docs/nested');
    cloud.failures.add('/docs');
    await mount(tester);
    expect(column('/'), findsOneWidget);
    expect(column('/docs'), findsNothing);
    expect(column('/docs/nested'), findsOneWidget);
    final reads = cloud.reads.where((path) => path == '/docs').length;
    panel.setFilter('deep');
    await tester.pumpAndSettle();
    expect(cloud.reads.where((path) => path == '/docs'), hasLength(reads));
    expect(container.read(errorProvider).hasErrors, isFalse);
    cloud.failures.clear();
    await panel.refresh();
    await tester.pumpAndSettle();
    expect(column('/docs'), findsOneWidget);
    expect(panel.filterQuery, 'deep');
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote ancestors stop at the advertised source root', (
    tester,
  ) async {
    final scoped = _Cloud('scoped', root: '/sandbox')
      ..folderNames['/sandbox'] = ['docs']
      ..folderNames['/sandbox/docs'] = ['nested']
      ..fileNames['/sandbox/docs/nested'] = ['scoped.txt'];
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'scoped',
          label: 'Scoped account',
          provider: CloudProvider.s3,
          client: scoped,
        );
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(
          RemotePanelSource(
            providerName: scoped.providerName,
            client: scoped,
            path: '/sandbox/docs/nested',
          ),
        );
    await panel.refresh();
    await mount(tester);
    expect(column('/sandbox'), findsOneWidget);
    expect(column('/sandbox/docs'), findsOneWidget);
    expect(column('/sandbox/docs/nested'), findsOneWidget);
    expect(column('/'), findsNothing);
    expect(scoped.reads, isNot(contains('/')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local ancestor reads preserve shared state and stay inside the grant',
    (tester) async {
      final service = _Local()..grantedRoot = '/selected';
      service.snapshots['/selected'] = [
        Directory('/selected/docs'),
        File('/selected/root.txt'),
        File('/outside/escape.txt'),
      ];
      service.denied.add('/selected/docs');
      await openLocal(service, '/selected/docs/deep');
      service.currentPath = '/another-pane';
      await mount(tester);
      expect(column('/selected'), findsOneWidget);
      expect(column('/selected/docs'), findsNothing);
      expect(column('/selected/docs/deep'), findsOneWidget);
      expect(column('/'), findsNothing);
      expect(row('/selected', '/outside/escape.txt'), findsNothing);
      expect(service.snapshotReads.toSet(), {'/selected', '/selected/docs'});
      expect(service.currentPath, '/another-pane');
      expect(service.grantedBasePath, '/selected');
      expect(service.ensuredAccess, 0);
      expect(service.accessRequests, 0);
      expect(container.read(errorProvider).hasErrors, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('named local roots reject snapshots from a replaced grant', (
    tester,
  ) async {
    final service = _NamedRootLocal();
    service.snapshots['/Photos'] = [File('/Photos/old.txt')];
    service.snapshots['/Photos/docs'] = [Directory('/Photos/docs/deep')];
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    service.snapshotGates['/Photos'] = gate;
    await openLocal(service, '/Photos/docs/deep');
    await mount(tester);
    expect(column('/Photos'), findsNothing);
    service.rootIdentity = Object();
    service.snapshotGates.clear();
    service.snapshots['/Photos'] = [File('/Photos/new.txt')];
    await panel.refresh();
    await tester.pumpAndSettle();
    expect(row('/Photos', '/Photos/new.txt'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(row('/Photos', '/Photos/new.txt'), findsOneWidget);
    expect(row('/Photos', '/Photos/old.txt'), findsNothing);
    expect(service.snapshotReads, isNot(contains('/')));
    expect(column('/'), findsNothing);
    expect(service.accessRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a replaced local grant discards already published ancestor rows',
    (tester) async {
      final service = _NamedRootLocal();
      service.snapshots['/Photos'] = [File('/Photos/old.txt')];
      service.snapshots['/Photos/docs'] = [Directory('/Photos/docs/deep')];
      await openLocal(service, '/Photos/docs/deep');
      await mount(tester);
      expect(row('/Photos', '/Photos/old.txt'), findsOneWidget);
      service.rootIdentity = Object();
      service.snapshots['/Photos'] = [File('/Photos/replacement.txt')];
      await panel.refresh();
      await tester.pumpAndSettle();
      expect(row('/Photos', '/Photos/replacement.txt'), findsOneWidget);
      expect(row('/Photos', '/Photos/old.txt'), findsNothing);
      expect(column('/'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a replaced local grant rejects an ancestor action before rebuilding',
    (tester) async {
      final service = _NamedRootLocal();
      service.snapshots['/Photos'] = [File('/Photos/target.txt')];
      await openLocal(service, '/Photos/docs/deep');
      await mount(tester);
      final action = tester
          .widget<Semantics>(row('/Photos', '/Photos/target.txt'))
          .properties
          .onTap!;
      service.directoryReads.clear();
      service.rootIdentity = Object();
      // Invoke the mounted row before a provider notification can rebuild it.
      action();
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/Photos/docs/deep');
      expect(service.directoryReads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a grant replaced during ancestor reload cannot select its matching row',
    (tester) async {
      final service = _NamedRootLocal();
      service.snapshots['/Photos'] = [File('/Photos/target.txt')];
      service.listings['/Photos'] = [
        File('/Photos/a-other.txt'),
        File('/Photos/target.txt'),
      ];
      await openLocal(service, '/Photos/docs/deep');
      await mount(tester);
      final action = tester
          .widget<Semantics>(row('/Photos', '/Photos/target.txt'))
          .properties
          .onTap!;
      await tester.runAsync(() async {
        final gate = Completer<void>();
        final entered = Completer<void>();
        service.directoryGates['/Photos'] = gate;
        service.directoryEntered['/Photos'] = entered;
        final loaded = Completer<void>();
        void observe() {
          if (entered.isCompleted &&
              !panel.isLoading &&
              panel.currentPath == '/Photos') {
            if (!loaded.isCompleted) loaded.complete();
          }
        }

        panel.addListener(observe);
        try {
          action();
          // Navigation checks access asynchronously before starting its read.
          await entered.future;
          expect(panel.isLoading, isTrue);
          expect(service.directoryReads.last, '/Photos');
          service.rootIdentity = Object();
        } finally {
          if (!gate.isCompleted) gate.complete();
          try {
            await loaded.future;
            // Drain the loader and row action even if a preceding assertion
            // fails, before returning to fake time or disposing the fixture.
            await Future<void>.delayed(Duration.zero);
          } finally {
            panel.removeListener(observe);
            service.directoryGates.remove('/Photos');
            service.directoryEntered.remove('/Photos');
          }
        }
      });
      expect(
        panel.files!.any((file) => file.path == '/Photos/target.txt'),
        isFalse,
      );
      expect(panel.hasVerifiedDirectoryListing, isFalse);
      expect(panel.isLoading, isFalse);
      expect(panel.cursorItem?.path, isNot('/Photos/target.txt'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'very deep navigation keeps root context with bounded ancestor work',
    (tester) async {
      final path = '/${List.generate(150, (index) => 'level$index').join('/')}';
      await panel.navigateToPath(path);
      cloud.reads.clear();
      await mount(tester);
      expect(column(path), findsOneWidget);
      expect(column('/'), findsOneWidget);
      expect(cloud.reads.length, lessThanOrEqualTo(128));
      expect(cloud.reads, isNot(contains(path)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps ancestor listings and renders actual horizontal columns', (
    tester,
  ) async {
    await mount(tester);
    await tapRow(tester, '/', '/docs');
    expect(panel.currentPath, '/docs');
    expect(column('/'), findsOneWidget);
    expect(column('/docs'), findsOneWidget);
    expect(row('/', '/root.txt'), findsOneWidget);
    expect(row('/docs', '/docs/keep.txt'), findsOneWidget);
    expect(
      tester.getTopLeft(column('/docs')).dx,
      greaterThan(tester.getTopLeft(column('/')).dx),
    );
    await tapRow(tester, '/docs', '/docs/nested');
    expect(column('/docs/nested'), findsOneWidget);
    expect(column('/'), findsOneWidget);
    expect(column('/docs'), findsOneWidget);
    expect(row('/docs/nested', '/docs/nested/deep.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final move in [false, true]) {
    testWidgets(
      'dragging into a hydrated ancestor folder reviews ${move ? 'move' : 'copy'} without navigating',
      (tester) async {
        await panel.navigateToPath('/docs/nested');
        await mount(tester);
        final liveRows = panel.files;
        final sourceRow = row('/docs/nested', '/docs/nested/deep.txt');
        final ancestorRow = row('/', '/other');
        final gesture = await tester.startGesture(
          tester.getCenter(sourceRow),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        if (move) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await gesture.moveTo(tester.getCenter(ancestorRow));
        await tester.pump();
        expect(find.text('${move ? 'Move' : 'Copy'} → other'), findsOneWidget);
        await gesture.up();
        if (move) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        final dialog = tester.widget<FileOperationDialog>(
          find.byType(FileOperationDialog),
        );
        expect(dialog.destinationPath, '/other');
        expect(
          dialog.kind,
          move ? FileOperationKind.move : FileOperationKind.copy,
        );
        expect(dialog.files.single.path, '/docs/nested/deep.txt');
        expect(
          dialog.destinationOrigin!.storageReference,
          panel.captureCurrentOrigin().storageReference,
        );
        expect(panel.currentPath, '/docs/nested');
        expect(panel.files, same(liveRows));
        expect(cloud.writes, isEmpty);
        expect(container.read(transferProvider).operations, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(
                  FilledButton,
                  move ? 'Start Move' : 'Start Copy',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets('a removed ancestor folder cannot receive a captured drop', (
    tester,
  ) async {
    await panel.navigateToPath('/docs/nested');
    await mount(tester);
    final target = find.byWidgetPredicate(
      (widget) => widget is FolderDropTarget && widget.folder.path == '/other',
    );
    final drop = tester.widget<DragTarget<PanelDragData>>(
      find.descendant(
        of: target,
        matching: find.byType(DragTarget<PanelDragData>),
      ),
    );
    final file = panel.files!.singleWhere((item) => item.name == 'deep.txt');
    final data = PanelDragData(sourceSide: PanelSide.remote, files: [file])
      ..captureFrom(panel);
    final details = DragTargetDetails(data: data, offset: Offset.zero);
    expect(drop.onWillAcceptWithDetails!(details), isTrue);
    cloud.folderNames['/'] = ['docs'];
    drop.onAcceptWithDetails!(details);
    await tester.pumpAndSettle();
    expect(find.byType(FileOperationDialog), findsNothing);
    expect(data.hasFolderTarget, isFalse);
    expect(panel.currentPath, '/docs/nested');
    expect(cloud.writes, isEmpty);
    expect(container.read(transferProvider).operations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancestor destinations cannot become drag sources', (
    tester,
  ) async {
    await panel.navigateToPath('/docs/nested');
    await mount(tester);
    expect(
      find.ancestor(
        of: row('/', '/other'),
        matching: find.byType(FolderDropTarget),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: row('/', '/other'),
        matching: find.byType(PanelFileDragSource),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: row('/', '/root.txt'),
        matching: find.byType(PanelFileDragSource),
      ),
      findsNothing,
    );
    final target = tester.widget<FolderDropTarget>(
      find.byWidgetPredicate(
        (widget) =>
            widget is FolderDropTarget && widget.folder.path == '/other',
      ),
    );
    final captured = target.captureDestination!();
    expect(captured, isNotNull);
    await panel.refresh();
    expect(captured!.isCurrent, isFalse);
  });

  testWidgets('filters the live column without replacing ancestor snapshots', (
    tester,
  ) async {
    await mount(tester);
    await tapRow(tester, '/', '/docs');
    panel.setFilter('keep');
    await tester.pumpAndSettle();
    expect(row('/docs', '/docs/keep.txt'), findsOneWidget);
    expect(row('/docs', '/docs/other.txt'), findsNothing);
    expect(row('/', '/root.txt'), findsOneWidget);
    expect(column('/'), findsOneWidget);
    expect(column('/docs'), findsOneWidget);
    await panel.refresh();
    await tester.pumpAndSettle();
    expect(row('/docs', '/docs/other.txt'), findsNothing);
    expect(column('/'), findsOneWidget);
  });

  testWidgets('ancestor selection reloads and selects the exact fresh row', (
    tester,
  ) async {
    await mount(tester);
    final old = panel.files!.firstWhere((file) => file.name == 'root.txt');
    await tapRow(tester, '/', '/docs');
    await tapRow(tester, '/', '/root.txt');
    expect(panel.currentPath, '/');
    expect(column('/docs'), findsNothing);
    final fresh = panel.cursorItem!;
    expect(fresh.path, '/root.txt');
    expect(identical(fresh, old), isFalse);
    expect(panel.originForOperation(fresh)?.source, isA<RemotePanelSource>());
    expect(panel.originForOperation(old), isNull);
    expect(panel.listFocusNode.hasFocus, isTrue);
  });

  testWidgets('ancestor context menu captures the original directory and row', (
    tester,
  ) async {
    await mount(tester);
    final old = panel.files!.firstWhere((file) => file.name == 'root.txt');
    await tapRow(tester, '/', '/docs');
    await tester.tap(row('/', '/root.txt'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/');
    expect(panel.selection.single.path, '/root.txt');
    expect(identical(panel.selection.single, old), isFalse);
    final origin = panel.originForOperation(panel.selection.single)!;
    expect((origin.source as RemotePanelSource).client, same(cloud));
    expect(origin.source.currentPath, '/');
    expect(find.text('Properties'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('a missing ancestor item cannot open a stale context menu', (
    tester,
  ) async {
    await mount(tester);
    await tapRow(tester, '/', '/docs');
    cloud.fileNames['/'] = [];
    await tester.tap(row('/', '/root.txt'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/');
    expect(panel.selection, isEmpty);
    expect(find.text('Properties'), findsNothing);
    expect(row('/', '/root.txt'), findsNothing);
  });

  testWidgets('modifier clicks mark a folder without navigating', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tapRow(tester, '/', '/docs');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(panel.currentPath, '/');
    expect(panel.selection.single.path, '/docs');
    expect(column('/docs'), findsNothing);
    expect(container.read(activePanelProvider), PanelSide.remote);
  });

  testWidgets('keyboard navigation keeps focus and forwards modified Enter', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester);
      final folder = panel.files!.firstWhere((file) => file.name == 'docs');
      panel.setCursorOnly(folder);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(row('/', '/docs')).getSemanticsData().label,
        contains('Folder docs'),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(parentKeys, contains(LogicalKeyboardKey.enter));
      expect(panel.currentPath, '/');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/docs');
      expect(panel.listFocusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(panel.currentPath, '/');
      expect(column('/docs'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'inline rename uses the shared editor and keeps text keys local',
    (tester) async {
      await mount(tester);
      final file = panel.files!.firstWhere((file) => file.name == 'root.txt');
      panel.startRename(file, keepExtension: true);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'root.txt');
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(panel.currentPath, '/');
      expect(panel.renamingItem, same(file));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(panel.renamingItem, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing tabs does not reuse another tabs ancestor snapshots', (
    tester,
  ) async {
    await mount(tester);
    await tapRow(tester, '/', '/docs');
    final first = panel.activeTabId;
    cloud.fileNames['/'] = ['new-root.txt'];
    panel.addTab(path: '/other');
    await tester.pumpAndSettle();
    expect(panel.activeTabId, isNot(first));
    expect(panel.currentPath, '/other');
    expect(column('/other'), findsOneWidget);
    expect(column('/docs'), findsNothing);
    expect(column('/'), findsOneWidget);
    expect(row('/', '/new-root.txt'), findsOneWidget);
    expect(row('/', '/root.txt'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed ancestor action cannot cross an account switch', (
    tester,
  ) async {
    await mount(tester);
    await tapRow(tester, '/', '/docs');
    final gate = Completer<void>();
    cloud.delayedPath = '/';
    cloud.delay = gate;
    await tester.tap(row('/', '/root.txt'), buttons: kSecondaryMouseButton);
    await tester.pump();
    expect(panel.isLoading, isTrue);
    final other = _Cloud('second')..fileNames['/'] = ['second.txt'];
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'second',
          label: 'Second account',
          provider: CloudProvider.gdrive,
          client: other,
        );
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(
          RemotePanelSource(
            providerName: other.providerName,
            client: other,
            path: '/',
          ),
        );
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    await panel.refresh();
    await tester.pumpAndSettle();
    expect(panel.selection, isEmpty);
    expect(column('/docs'), findsNothing);
    expect(row('/', '/second.txt'), findsOneWidget);
    expect(row('/', '/root.txt'), findsNothing);
    expect(find.text('Properties'), findsNothing);
    expect(
      (panel.captureCurrentOrigin().source as RemotePanelSource).client,
      same(other),
    );
    expect(tester.takeException(), isNull);
  });
}
