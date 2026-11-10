import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/file_column_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account);
  final String account;
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

  @override
  String get providerName => 'Test cloud';
  @override
  String get userId => account;
  @override
  String get bucketId => 'test-bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    reads.add(path);
    if (path == delayedPath) await delay?.future;
    return {
      'files': [
        for (final name in fileNames[path] ?? const <String>[])
          {'name': name, 'size': 12, 'uuid': '$account:$path/$name'},
      ],
      'folders': [
        for (final name in folderNames[path] ?? const <String>[])
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
  late ProviderContainer container;
  late _Cloud cloud;
  late PanelNotifier panel;
  late ScrollController scroll;
  final parentKeys = <LogicalKeyboardKey>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud('first');
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
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
    addTearDown(semantics.dispose);
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
    panel.addTab(path: '/other');
    await tester.pumpAndSettle();
    expect(panel.activeTabId, isNot(first));
    expect(panel.currentPath, '/other');
    expect(column('/other'), findsOneWidget);
    expect(column('/docs'), findsNothing);
    expect(column('/'), findsNothing);
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
