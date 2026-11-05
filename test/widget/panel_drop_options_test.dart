import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:crisp_cloud/widgets/file_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Cloud extends Fake implements CloudStorageClient {
  @override
  String get providerName => 'Drop test cloud';
  @override
  String get rootPath => '/';
  @override
  String? get userId => 'drop-account';
  @override
  String? get bucketId => 'drop-bucket';
  @override
  bool get isAuthenticated => true;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      if (path == '/') {'name': 'source.txt', 'size': 12},
    ],
  };
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? get userEmail => 'drop@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late PanelNotifier source;
  late PanelNotifier destination;
  late FileItem file;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), (_) async => null);
    final cloud = _Cloud();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
        drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
      ],
    );
    source = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    container.read(panelSourceProvider(PanelSide.local).notifier).setSource(
      RemotePanelSource(providerName: cloud.providerName, client: cloud, path: '/'),
    );
    await source.refresh();
    file = source.files!.singleWhere((item) => !item.isFolder);
    destination = container.read(panelProvider(PanelSide.remote));
    await destination.refresh();
    container.read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/landing'));
    await destination.refresh();
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('desktop_drop'), null);
  });

  Future<void> host(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 900);
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
            body: FilePanel(
              side: PanelSide.remote,
              isActive: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DragTargetDetails<PanelDragData> details(FileItem item) => DragTargetDetails(
    data: PanelDragData(sourceSide: PanelSide.local, files: [item]),
    offset: Offset.zero,
  );

  testWidgets('a normal-folder drop opens copy options with actual swapped sources', (
    tester,
  ) async {
    expect(source.showingSearchResults, isFalse);
    expect(source.captureCurrentOrigin().source, isA<RemotePanelSource>());
    expect(destination.captureCurrentOrigin().source, isA<LocalPanelSource>());
    await host(tester);
    final target = tester.widget<DragTarget<PanelDragData>>(
      find.byType(DragTarget<PanelDragData>),
    );
    expect(target.onWillAcceptWithDetails!(details(file)), isTrue);
    target.onAcceptWithDetails!(details(file));
    await tester.pumpAndSettle();

    final dialog = tester.widget<FileOperationDialog>(find.byType(FileOperationDialog));
    expect(dialog.files.single.path, '/source.txt');
    expect(dialog.sourceOrigin!.source, isA<RemotePanelSource>());
    expect(dialog.destinationOrigin!.source, isA<LocalPanelSource>());
    expect(dialog.destinationPath, '/landing');
    expect(find.text('Copy 1 selected item(s)'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start Copy')).onPressed,
      isNull,
    );
    expect(container.read(transferProvider).operations, isEmpty);

    container.read(panelSourceProvider(PanelSide.remote).notifier)
        .setSource(const LocalPanelSource('/elsewhere'));
    await tester.pumpAndSettle();
    final destinationField = find.byWidgetPredicate(
      (widget) => widget is TextField &&
          widget.decoration?.labelText == 'Destination directory',
    );
    expect(tester.widget<TextField>(destinationField).controller!.text, '/landing');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(transferProvider).operations, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('stale drag rows and virtual-list destinations are rejected', (
    tester,
  ) async {
    await host(tester);
    var target = tester.widget<DragTarget<PanelDragData>>(
      find.byType(DragTarget<PanelDragData>),
    );
    expect(target.onWillAcceptWithDetails!(details(file.copyWith())), isFalse);
    destination.showSearchResults([], origin: destination.captureCurrentOrigin());
    await tester.pumpAndSettle();
    target = tester.widget<DragTarget<PanelDragData>>(
      find.byType(DragTarget<PanelDragData>),
    );
    expect(target.onWillAcceptWithDetails!(details(file)), isFalse);
    expect(find.byType(FileOperationDialog), findsNothing);
    expect(container.read(transferProvider).operations, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a collection keeps list headers and empty state with Gallery selected', (
    tester,
  ) async {
    container.read(remoteViewModeProvider.notifier).state = ViewMode.gallery;
    destination.showSearchResults(
      [file],
      origin: source.captureOperationOrigin([file]),
      title: 'Gallery collection',
    );
    await host(tester);

    // The name column includes the active sort-direction indicator.
    final originalPathHeader = find.textContaining(
      RegExp(r'^Original path(?: [↑↓])?$'),
    );
    expect(container.read(remoteViewModeProvider), ViewMode.gallery);
    expect(find.byType(FileListView), findsOneWidget);
    expect(originalPathHeader, findsOneWidget);
    expect(find.byTooltip('File list actions'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from list (keep files)'));
    await tester.pumpAndSettle();

    expect(destination.files, isEmpty);
    expect(destination.showingSearchResults, isTrue);
    expect(originalPathHeader, findsOneWidget);
    expect(find.text('This file list is empty.'), findsOneWidget);
    expect(find.byTooltip('File list actions'), findsOneWidget);
    expect(find.byTooltip('Return to folder'), findsOneWidget);
    expect(container.read(remoteViewModeProvider), ViewMode.gallery);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
