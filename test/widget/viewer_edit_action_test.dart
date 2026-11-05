import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/internal_viewer_dialog.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  void disconnect() {
    client.current = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late WorkflowFakeClient cloud;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier panel;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = WorkflowFakeClient()
      ..put('/a.txt', 'first file\n'.codeUnits)
      ..put('/b.txt', 'unselected\n'.codeUnits)
      ..put('/c.txt', 'third file\n'.codeUnits)
      ..put('/blob.bin', [0, 1, 2]);
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());

  FileItem item(String name) =>
      panel.files!.firstWhere((file) => file.name == name);

  testWidgets(
    'navigation keeps only selected files and edits the displayed file',
    (tester) async {
      panel.toggleSelection(item('a.txt'));
      panel.toggleSelection(item('c.txt'), ctrlKey: true);
      late Future<InternalViewerAction> result;
      FileItem? viewed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    result = showInternalViewer(
                      context,
                      file: item('a.txt'),
                      side: PanelSide.remote,
                      onFileChanged: (file) => viewed = file,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byTooltip('Edit (F4)'), findsOneWidget);
      await tester.tap(find.byTooltip('Next file (Alt+Right)'));
      await tester.pumpAndSettle();
      expect(find.text('c.txt'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(viewed, same(item('c.txt')));
      await tester.tap(find.byTooltip('Edit (F4)'));
      await tester.pumpAndSettle();
      expect(await result, InternalViewerAction.edit);
    },
  );

  testWidgets(
    'reload and follow use fresh bytes and stop on captured account loss',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InternalViewerDialog(
              file: item('a.txt'),
              side: PanelSide.remote,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      cloud.put('/a.txt', 'reloaded text\n'.codeUnits);
      await tester.tap(find.byTooltip('Reload (F5)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reloaded text'), findsWidgets);
      await tester.tap(find.byTooltip('Follow end of file'));
      await tester.pumpAndSettle();
      cloud.put('/a.txt', 'reloaded text\nnew line\n'.codeUnits);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('new line'), findsWidgets);
      auth.disconnect();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('source changed'), findsWidgets);
      expect(find.byTooltip('Edit (F4)'), findsNothing);
    },
  );

  testWidgets(
    'a remote file in the left pane uses its actual captured source',
    (tester) async {
      final left = container.read(panelProvider(PanelSide.local));
      await tester.pump();
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(
            RemotePanelSource(
              providerName: cloud.providerName,
              client: cloud,
              path: '/',
            ),
          );
      await left.refresh();
      final listed = left.files!.firstWhere((file) => file.name == 'a.txt');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InternalViewerDialog(file: listed, side: PanelSide.local),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('first file'), findsWidgets);
      expect(find.byTooltip('Edit (F4)'), findsOneWidget);
    },
  );

  testWidgets('unverified row copies and binary formats do not expose Edit', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: InternalViewerDialog(
            file: item('a.txt').copyWith(),
            side: PanelSide.remote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('original viewer source is unavailable'),
      findsWidgets,
    );
    expect(find.byTooltip('Edit (F4)'), findsNothing);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: InternalViewerDialog(
            key: const ValueKey('binary'),
            file: item('blob.bin'),
            side: PanelSide.remote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit (F4)'), findsNothing);
  });
}
