import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/file_view_configuration.dart';
import 'package:crisp_cloud/models/folder_size_measurement.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/toolbar_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/panel_view_mode_service.dart';
import 'package:crisp_cloud/widgets/file_column_view.dart';
import 'package:crisp_cloud/widgets/file_grid_view.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';
import '../support/workspace_fixture.dart';

class _Cloud extends WorkflowFakeClient implements FreshCloudDirectoryReader {
  @override
  Future<Map<String, dynamic>> readDirectoryForEdit(String path) async {
    if (path == '/partial') {
      return {
        'files': [
          {'name': 'known.bin', 'size': 1536},
          {'name': 'unknown.bin'},
        ],
        'folders': [],
        'complete': false,
      };
    }
    return super.listPath(path);
  }
}

class _Auth extends WorkspaceTestAuth {
  _Auth(super.client);
  void disconnect() {
    client.current = false;
    notifyListeners();
  }
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
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

enum _Layout { list, column, tiles }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Cloud cloud;
  late _Auth auth;
  late PanelNotifier panel;
  late ScrollController scroll;

  FileItem folder(String name) =>
      panel.files!.singleWhere((file) => file.isFolder && file.name == name);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud()
      ..put('/partial/known.bin', List.filled(1536, 1))
      ..put('/complete/known.bin', List.filled(2048, 2));
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    scroll = ScrollController();
    panel = container.read(panelProvider(PanelSide.remote));
    await Future<void>.delayed(Duration.zero);
    container
        .read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(
          RemotePanelSource(
            client: cloud,
            providerName: cloud.providerName,
            path: '/',
          ),
        );
    await panel.refresh();
    await container
        .read(panelViewModeProvider(PanelSide.remote).notifier)
        .applyMode(PanelViewMode.full);
    container.read(fileColumnsProvider(PanelSide.remote).notifier).applyColumns(
      [FileColumnDefinition.defaults.first],
    );
    container.read(columnWidthsProvider(PanelSide.remote).notifier).applyWidths(
      {'size': 112},
    );

    // Real scans finish before entering the widget test's fake clock. Neither
    // their observations nor the rendered labels are supplied by test doubles.
    final partial = await panel.calculateFolderSize(folder('partial'));
    final complete = await panel.calculateFolderSize(folder('complete'));
    expect(partial?.phase, FolderSizePhase.partial);
    expect(partial?.unknownSizes, 1);
    expect(folder('partial').calculatedSize, isNull);
    expect(complete?.phase, FolderSizePhase.complete);
    expect(folder('complete').calculatedSize, 2048);
  });

  tearDown(() {
    scroll.dispose();
    container.dispose();
  });

  Future<void> mount(
    WidgetTester tester,
    _Layout layout, {
    double width = 360,
    double textScale = 1.5,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: 650,
                child: Consumer(
                  builder: (context, ref, _) {
                    // The production pane observes account changes even when
                    // the old listing remains visible without new rows.
                    ref.watch(authProvider);
                    final state = ref.watch(panelProvider(PanelSide.remote));
                    final files = state.filteredFiles ?? const <FileItem>[];
                    return switch (layout) {
                      _Layout.list => FileListView(
                        side: PanelSide.remote,
                        files: files,
                        scrollController: scroll,
                      ),
                      _Layout.column => FileColumnView(
                        side: PanelSide.remote,
                        files: files,
                        scrollController: scroll,
                      ),
                      _Layout.tiles => FileGridView(
                        side: PanelSide.remote,
                        files: files,
                        scrollController: scroll,
                        tileLayout: true,
                      ),
                    };
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectPartialDetails(WidgetTester tester) {
    expect(find.text('≥ 1.5 KB'), findsOneWidget);
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.contains('partial') ?? false) &&
          (widget.properties.label?.contains('Partial results') ?? false),
    );
    expect(row, findsOneWidget);
    final label = tester.getSemantics(row).getSemanticsData().label;
    expect(label, contains('Partial results'));
    expect(label, contains('2 files · 0 folders · 1.5 KB'));
    expect(label, contains('1 files have unknown sizes'));
    expect(label, contains('known portion of this folder'));
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'compact list renders a measured lower bound and accessible detail',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester, _Layout.list);
        expect(find.byType(CompactFileTile), findsNWidgets(2));
        expectPartialDetails(tester);
      } finally {
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('current directory column renders its real partial measurement', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, _Layout.column);
      expect(find.byKey(const ValueKey('file-column:/')), findsOneWidget);
      expectPartialDetails(tester);
    } finally {
      semantics.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets(
    'narrow tiles retain measured sizes and readable partial detail',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(tester, _Layout.tiles, width: 320, textScale: 1.6);
        expect(find.byType(GridView), findsOneWidget);
        expectPartialDetails(tester);
      } finally {
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'expanded rows remove a stale exact size after source invalidation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await container
            .read(panelViewModeProvider(PanelSide.remote).notifier)
            .applyMode(PanelViewMode.brief);
        await mount(tester, _Layout.list);
        expect(find.byType(FileListTile), findsNWidgets(2));
        expect(find.text('2.0 KB'), findsOneWidget);
        auth.disconnect();
        await tester.pumpAndSettle();
        expect(panel.folderSizeFor(folder('complete'))?.sourceChanged, isTrue);
        expect(find.text('2.0 KB'), findsNothing);
        final row = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.contains('Folder complete') ?? false),
        );
        expect(row, findsOneWidget);
        final label = tester.getSemantics(row).getSemanticsData().label;
        expect(label, contains('The original storage connection changed'));
        expect(label, isNot(contains('2.0 KB')));
        expect(cloud.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
