import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/folder_drop_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_drag_data.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/folder_drop_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:crisp_cloud/widgets/file_panel.dart';
import 'package:crisp_cloud/widgets/folder_drop_target.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account) {
    directories.addAll(['/destination', '/parent', '/parent/child']);
    put('/a.txt', [1, 2]);
    put('/b.txt', [3, 4]);
    put('/parent/nested.txt', [5]);
  }
  final String account;
  final objectIds = <String, String>{};
  final versions = <String, String>{};
  final reads = <String>[];
  Completer<void>? readGate;
  Completer<void>? readStarted;

  @override
  String get providerName => 'Folder drop fixture';
  @override
  String get userId => account;
  @override
  String get bucketId => 'fixture-bucket';

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    reads.add(path);
    final gate = readGate;
    if (gate != null) {
      if (!(readStarted?.isCompleted ?? true)) readStarted!.complete();
      await gate.future;
    }
    final result = await super.listPath(path);
    for (final group in ['files', 'folders']) {
      for (final row in result[group] as List) {
        final filePath = row['path'] as String;
        row['uuid'] = objectIds[filePath] ?? '$account:$filePath';
        row['etag'] = versions[filePath] ?? 'revision-1';
      }
    }
    return result;
  }

  @override
  Future<void> createFolderPath(String path) async {
    writes.add('create:$path');
    await super.createFolderPath(path);
  }

  @override
  Future<void> deletePath(String path) async {
    writes.add('delete:$path');
    await super.deletePath(path);
  }

  @override
  Future<void> movePath(String sourcePath, String targetPath) async {
    writes.add('move:$sourcePath:$targetPath');
    await super.movePath(sourcePath, targetPath);
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
  void replace(_Cloud replacement) {
    client = replacement;
    notifyListeners();
  }

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
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = FolderDropService();
  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);
  late ProviderContainer container;
  late _Cloud cloud;
  late _Auth auth;
  late _Local local;
  late PanelNotifier source;
  late PanelNotifier destination;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('desktop_drop'),
          (_) async => null,
        );
    cloud = _Cloud('first');
    auth = _Auth(cloud);
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
        drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
      ],
    );
    source = container.read(panelProvider(PanelSide.local));
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
    await source.refresh();
    destination = container.read(panelProvider(PanelSide.remote));
    await destination.refresh();
  });

  tearDown(() {
    if (cloud.readGate != null && !cloud.readGate!.isCompleted) {
      cloud.readGate!.complete();
    }
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
  });

  FileItem row(PanelNotifier panel, String path) =>
      panel.files!.singleWhere((item) => item.path == path);

  PanelDragData drag(List<FileItem> files, {FileItem? primary}) =>
      PanelDragData(sourceSide: PanelSide.local, files: files)
        ..captureFrom(source, primary: primary);

  CapturedFolderDropTarget target({
    PanelNotifier? panel,
    String path = '/destination',
  }) {
    final host = panel ?? destination;
    return service.capture(host, row(host, path), local)!;
  }

  Matcher failure(PanelDragFailure value) => isA<PanelDragException>().having(
    (error) => error.failure,
    'failure',
    value,
  );

  Future<void> mount(
    WidgetTester tester, {
    PanelSide side = PanelSide.remote,
    bool withList = false,
    Locale? locale,
  }) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final panel = side == PanelSide.local ? source : destination;
    final destinationWidget = FolderDropTarget(
      side: side,
      folder: row(panel, '/destination'),
      child: Container(
        key: const ValueKey('destination-area'),
        width: 300,
        height: 90,
        color: Colors.blue.shade50,
        child: const Text('Destination folder'),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: withList
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 600,
                        child: Consumer(
                          builder: (context, ref, _) {
                            final panel = ref.watch(
                              panelProvider(PanelSide.local),
                            );
                            return FileListView(
                              side: PanelSide.local,
                              files: panel.filteredFiles ?? const [],
                              scrollController: scroll,
                            );
                          },
                        ),
                      ),
                      destinationWidget,
                    ],
                  )
                : Center(child: destinationWidget),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DragTarget<PanelDragData> dropWidget(WidgetTester tester) =>
      tester.widget<DragTarget<PanelDragData>>(
        find.descendant(
          of: find.byType(FolderDropTarget).last,
          matching: find.byType(DragTarget<PanelDragData>),
        ),
      );

  Future<FileOperationDialog> accept(
    WidgetTester tester,
    PanelDragData data,
  ) async {
    final widget = dropWidget(tester);
    final details = DragTargetDetails(data: data, offset: Offset.zero);
    expect(widget.onWillAcceptWithDetails!(details), isTrue);
    widget.onAcceptWithDetails!(details);
    await tester.pumpAndSettle();
    return tester.widget<FileOperationDialog>(find.byType(FileOperationDialog));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cloud.writes, isEmpty);
    expect(container.read(transferProvider).operations, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  test(
    'preparation reads the exact destination and preserves captured groups',
    () async {
      final data = drag([row(source, '/a.txt'), row(source, '/b.txt')]);
      final originalGroups = data.capturedGroups;
      final readsBefore = cloud.reads.length;
      final prepared = await service.prepare(
        data,
        target(),
        kind: FileOperationKind.copy,
      );
      expect(prepared.destination.path, '/destination');
      expect(prepared.groups, same(originalGroups));
      expect(prepared.files.map((file) => file.path), ['/a.txt', '/b.txt']);
      expect(cloud.reads.length, greaterThan(readsBefore));
      expect(cloud.writes, isEmpty);
    },
  );

  test(
    'dragging a marked row keeps marks and an unmarked row stays singular',
    () {
      final a = row(source, '/a.txt');
      final b = row(source, '/b.txt');
      source.toggleSelection(a);
      source.toggleSelection(b, ctrlKey: true);
      expect(drag([a], primary: a).files, [a, b]);
      final folder = row(source, '/parent');
      expect(drag([folder], primary: folder).files, [folder]);
      expect(source.selection, containsAll([a, b]));
    },
  );

  test(
    'self and descendant drops reject the whole captured selection',
    () async {
      final folder = row(source, '/parent');
      final data = drag([folder, row(source, '/a.txt')]);
      expect(
        service.canAccept(
          data,
          target(path: '/parent'),
          FileOperationKind.copy,
        ),
        isFalse,
      );
      await destination.navigateToPath('/parent');
      final descendant = target(path: '/parent/child');
      expect(
        service.canAccept(data, descendant, FileOperationKind.move),
        isFalse,
      );
      await expectLater(
        service.prepare(data, descendant, kind: FileOperationKind.move),
        throwsA(failure(PanelDragFailure.invalidDestination)),
      );
      expect(cloud.writes, isEmpty);
    },
  );

  test(
    'same-panel moves can target another folder but not their present parent',
    () async {
      final data = drag([row(source, '/a.txt')]);
      expect(
        service.canAccept(data, target(panel: source), FileOperationKind.move),
        isTrue,
      );
      await source.navigateToPath('/parent');
      final nested = drag([row(source, '/parent/nested.txt')]);
      expect(
        service.canAccept(
          nested,
          target(path: '/parent'),
          FileOperationKind.move,
        ),
        isFalse,
      );
    },
  );

  test(
    'source refresh and account changes cannot rebind a running drag',
    () async {
      final old = drag([row(source, '/a.txt')]);
      await source.refresh();
      old.captureFrom(source);
      expect(old.isCurrent, isFalse);
      await expectLater(
        old.prepareForDrop(),
        throwsA(failure(PanelDragFailure.sourceChanged)),
      );
      final live = drag([row(source, '/a.txt')]);
      final capturedTarget = target();
      auth.replace(_Cloud('replacement'));
      expect(live.isCurrent, isFalse);
      expect(capturedTarget.isCurrent, isFalse);
      expect(cloud.writes, isEmpty);
    },
  );

  for (final field in ['object', 'version']) {
    test(
      'a changed destination $field is rejected after its fresh read',
      () async {
        final data = drag([row(source, '/a.txt')]);
        final capturedTarget = target();
        if (field == 'object') {
          cloud.objectIds['/destination'] = 'replacement-folder';
        } else {
          cloud.versions['/destination'] = 'revision-2';
        }
        await expectLater(
          service.prepare(data, capturedTarget, kind: FileOperationKind.copy),
          throwsA(failure(PanelDragFailure.destinationChanged)),
        );
        expect(cloud.writes, isEmpty);
      },
    );
  }

  test(
    'a destination tab changed during verification cannot receive the drop',
    () async {
      final data = drag([row(source, '/a.txt')]);
      final capturedTarget = target();
      cloud.readGate = Completer<void>();
      cloud.readStarted = Completer<void>();
      final preparation = service.prepare(
        data,
        capturedTarget,
        kind: FileOperationKind.copy,
      );
      final assertion = expectLater(
        preparation,
        throwsA(failure(PanelDragFailure.destinationChanged)),
      );
      await cloud.readStarted!.future;
      destination.addTab(path: '/parent');
      final gate = cloud.readGate!;
      cloud.readGate = null;
      gate.complete();
      await assertion;
      await Future<void>.delayed(Duration.zero);
      expect(cloud.writes, isEmpty);
    },
  );

  test('virtual destination rows do not become writable folder targets', () {
    final folder = row(destination, '/destination');
    destination.showSearchResults([
      folder,
    ], origin: destination.captureCurrentOrigin());
    expect(service.capture(destination, folder, local), isNull);
  });

  testWidgets(
    'folder review uses the hovered directory with no transfer before preview',
    (tester) async {
      await mount(tester);
      final dialog = await accept(
        tester,
        drag([row(source, '/a.txt'), row(source, '/b.txt')]),
      );
      expect(dialog.kind, FileOperationKind.copy);
      expect(dialog.destinationPath, '/destination');
      expect(
        dialog.sourceOrigin!.storageReference,
        dialog.destinationOrigin!.storageReference,
      );
      expect(dialog.files.map((file) => file.path), ['/a.txt', '/b.txt']);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Start Copy'),
            )
            .onPressed,
        isNull,
      );
      expect(cloud.writes, isEmpty);
      await close(tester);
    },
    variant: desktop,
  );

  testWidgets('Shift requests a reviewed same-panel move', (tester) async {
    await mount(tester, side: PanelSide.local);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final dialog = await accept(tester, drag([row(source, '/a.txt')]));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(dialog.kind, FileOperationKind.move);
    expect(dialog.destinationPath, '/destination');
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Move'))
          .onPressed,
      isNull,
    );
    await close(tester);
  }, variant: desktop);

  testWidgets(
    'a stale hover fails locally and does not reopen another destination',
    (tester) async {
      await mount(tester);
      final widget = dropWidget(tester);
      final data = drag([row(source, '/a.txt')]);
      final details = DragTargetDetails(data: data, offset: Offset.zero);
      expect(widget.onWillAcceptWithDetails!(details), isTrue);
      destination.addTab(path: '/parent');
      widget.onAcceptWithDetails!(details);
      await tester.pumpAndSettle();
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(data.hasFolderTarget, isFalse);
      expect(cloud.writes, isEmpty);
      expect(container.read(transferProvider).operations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets('rejected folder hover stays claimed until it is left', (
    tester,
  ) async {
    await mount(tester);
    final widget = dropWidget(tester);
    final data = drag([row(source, '/destination')]);
    final details = DragTargetDetails(data: data, offset: Offset.zero);
    expect(widget.onWillAcceptWithDetails!(details), isFalse);
    expect(data.hasFolderTarget, isTrue);
    widget.onLeave!(data);
    expect(data.hasFolderTarget, isFalse);
    expect(find.byType(FileOperationDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);

  for (final marked in [true, false]) {
    testWidgets(
      'compact mouse drag captures ${marked ? 'all marks on a marked row' : 'only an unmarked row'}',
      (tester) async {
        final a = row(source, '/a.txt');
        final b = row(source, '/b.txt');
        source.toggleSelection(a);
        if (marked) source.toggleSelection(b, ctrlKey: true);
        await mount(tester, withList: true);
        final draggedName = marked ? 'a.txt' : 'b.txt';
        final origin = tester.getCenter(find.text(draggedName).first);
        final drop = tester.getCenter(
          find.byKey(const ValueKey('destination-area')),
        );
        final gesture = await tester.startGesture(
          origin,
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        await gesture.moveTo(drop);
        await tester.pump();
        expect(find.text('Copy → destination'), findsOneWidget);
        if (marked) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(find.text('Move → destination'), findsOneWidget);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(find.text('Copy → destination'), findsOneWidget);
        }
        await gesture.up();
        await tester.pumpAndSettle();
        final dialog = tester.widget<FileOperationDialog>(
          find.byType(FileOperationDialog),
        );
        expect(
          dialog.files.map((file) => file.path),
          marked ? ['/a.txt', '/b.txt'] : ['/b.txt'],
        );
        expect(dialog.destinationPath, '/destination');
        await close(tester);
      },
      variant: desktop,
    );
  }

  testWidgets(
    'drop failures are translated without exposing low-level errors',
    (tester) async {
      final seen = <String>[];
      for (final language in [
        'en',
        'de',
        'fr',
        'es',
        'pt',
        'zh',
        'ja',
        'ko',
        'ar',
      ]) {
        late String value;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                value = FolderDropStrings(context)
                    .failure(StateError('private-account-token'));
                return Text(value);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(value, isNot(contains('private-account-token')));
        expect(value, isNot(contains('StateError')));
        expect(value, isNotEmpty);
        seen.add(value);
      }
      expect(seen.toSet(), hasLength(9));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  PanelTab inactiveTab({String path = '/destination'}) {
    final tab = PanelTab(
      id: 'background-drop',
      path: path,
      storage: destination.captureCurrentOrigin().storageReference,
    );
    destination.tabs.add(tab);
    return tab;
  }

  test('inactive directory review preserves the active tab and captured groups', () async {
    final tab = inactiveTab();
    final active = destination.activeTabId;
    final path = destination.currentPath;
    final files = destination.files;
    final data = drag([row(source, '/a.txt'), row(source, '/b.txt')]);
    final prepared = await service.prepare(
      data,
      service.captureTab(destination, tab, local)!,
      kind: FileOperationKind.copy,
    );
    expect(prepared.groups, same(data.capturedGroups));
    expect(prepared.destination.path, '/destination');
    expect(prepared.destination.origin.storageReference, tab.storage);
    expect(destination.activeTabId, active);
    expect(destination.currentPath, path);
    expect(destination.files, same(files));
    expect(cloud.writes, isEmpty);

    // Once reviewed, the exact endpoint survives closing its presentation tab.
    destination.closeTab(tab.id);
    expect(prepared.destination.isCurrent, isFalse);
    expect(prepared.destination.origin.isCurrent, isTrue);
    expect(prepared.destination.backend.isCurrent, isTrue);
    expect(prepared.destination.origin.source.currentPath, '/destination');
  });

  test('inactive root verification reads the actual root instead of synthetic stat', () async {
    final tab = inactiveTab(path: '/');
    final reads = cloud.reads.length;
    await service.prepare(
      drag([row(source, '/a.txt')]),
      service.captureTab(destination, tab, local)!,
      kind: FileOperationKind.copy,
    );
    expect(cloud.reads.skip(reads), contains('/'));
    expect(cloud.writes, isEmpty);
  });

  for (final change in ['close', 'path', 'collection', 'account']) {
    test(
      'an inactive tab $change during verification rejects the drop',
      () async {
        final tab = inactiveTab();
        final captured = service.captureTab(destination, tab, local)!;
        final data = drag([row(source, '/a.txt')]);
        cloud.readGate = Completer<void>();
        cloud.readStarted = Completer<void>();
        final result = expectLater(
          service.prepare(data, captured, kind: FileOperationKind.copy),
          throwsA(isA<PanelDragException>()),
        );
        await cloud.readStarted!.future;
        switch (change) {
          case 'close':
            destination.closeTab(tab.id);
          case 'path':
            tab.path = '/parent';
          case 'collection':
            tab.collectionId = 'saved-results';
          case 'account':
            auth.replace(_Cloud('other-account'));
        }
        final gate = cloud.readGate!;
        cloud.readGate = null;
        gate.complete();
        await result;
        expect(cloud.writes, isEmpty);
      },
    );
  }

  test(
    'legacy, archive and transient search tabs cannot supply directory targets',
    () async {
      final tab = inactiveTab();
      final storage = tab.storage;
      tab.storage = null;
      expect(service.captureTab(destination, tab, local), isNull);
      tab.storage = storage;
      tab.path = '/archive.zip:/inside';
      expect(service.captureTab(destination, tab, local), isNull);

      final original = destination.activeTab!;
      destination.showSearchResults([
        row(destination, '/destination'),
      ], origin: destination.captureCurrentOrigin());
      tab.path = '/parent';
      await destination.selectTab(tab.id);
      // An unsaved search retains a normal path and has no collection ID.
      expect(original.collectionId, isNull);
      expect(original.storage, isNotNull);
      expect(service.captureTab(destination, original, local), isNull);
    },
  );

  test('a tab naming a file fails fresh directory verification', () async {
    final tab = inactiveTab(path: '/b.txt');
    await expectLater(
      service.prepare(
        drag([row(source, '/a.txt')]),
        service.captureTab(destination, tab, local)!,
        kind: FileOperationKind.copy,
      ),
      throwsA(failure(PanelDragFailure.destinationChanged)),
    );
    expect(cloud.writes, isEmpty);
  });

  Future<void> mountTabs(WidgetTester tester, PanelDragData data) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Row(
              children: [
                Draggable<PanelDragData>(
                  data: data,
                  feedback: const Material(child: Text('Dragged files')),
                  child: const SizedBox(
                    key: ValueKey('tab-drag-source'),
                    width: 150,
                    height: 80,
                    child: Text('Drag to a tab'),
                  ),
                ),
                Expanded(
                  child: FilePanel(
                    side: PanelSide.remote,
                    isActive: false,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final move in [false, true]) {
    testWidgets(
      'FilePanel reviews an inactive-tab ${move ? 'move' : 'copy'} without selecting it',
      (tester) async {
        final tab = inactiveTab();
        final active = destination.activeTabId;
        final path = destination.currentPath;
        final listed = destination.files;
        final data = drag([row(source, '/a.txt'), row(source, '/b.txt')]);
        await mountTabs(tester, data);
        if (move) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('tab-drag-source'))),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        await gesture.moveTo(
          tester.getCenter(
            find.byKey(ValueKey('tab-folder-drop-remote-${tab.id}')),
          ),
        );
        await tester.pump();
        expect(
          find.text('${move ? 'Move' : 'Copy'} → destination'),
          findsOneWidget,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        if (move) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        final dialog = tester.widget<FileOperationDialog>(
          find.byType(FileOperationDialog),
        );
        expect(
          dialog.kind,
          move ? FileOperationKind.move : FileOperationKind.copy,
        );
        expect(dialog.destinationPath, '/destination');
        expect(dialog.sourceOrigin, same(data.capturedGroups!.keys.single));
        expect(dialog.files.map((file) => file.path), ['/a.txt', '/b.txt']);
        expect(destination.activeTabId, active);
        expect(destination.currentPath, path);
        expect(destination.files, same(listed));
        await close(tester);
      },
      variant: desktop,
    );
  }

  testWidgets(
    'a rejected tab does not redirect the drop into the active pane',
    (tester) async {
      final tab = inactiveTab()..collectionId = 'saved-results';
      final data = drag([row(source, '/a.txt')]);
      await mountTabs(tester, data);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('tab-drag-source'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(ValueKey('tab-folder-drop-remote-${tab.id}')),
        ),
      );
      await tester.pump();
      expect(find.text('Copy → destination'), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(FileOperationDialog), findsNothing);
      expect(cloud.writes, isEmpty);
      expect(container.read(transferProvider).operations, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );
}
