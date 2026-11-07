import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/terminal_workspace_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/terminal_workspace_service.dart';
import 'package:crisp_cloud/widgets/terminal_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Local extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  int leases = 0;
  @override
  String currentPath = '/Documents';
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
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    leases++;
    try {
      return await action();
    } finally {
      leases--;
    }
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final CloudStorageClient client;
  @override
  bool isConnected = true;
  @override
  String? get userEmail => 'owner@example.test';
  @override
  String get providerName => client.providerName;
  void disconnect() {
    isConnected = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Workspaces extends Fake implements TerminalWorkspaceService {
  CloudStorageClient? stagedClient;
  CloudStorageClient? uploadedClient;
  List<FileItem>? stagedItems;
  bool Function()? current;
  Completer<TerminalWorkspace>? pending;
  TerminalWorkspace? workspace;
  @override
  bool get isSupported => true;
  @override
  List<String> get warnings => const [];
  @override
  Future<TerminalWorkspace> stage({
    required CloudStorageClient client,
    required String remoteRoot,
    required List<FileItem> items,
    required bool Function() isCurrent,
    StorageReference? storage,
    String? title,
    bool Function()? isCancelled,
    void Function(int, int)? onProgress,
  }) async {
    stagedClient = client;
    stagedItems = items;
    current = isCurrent;
    expect(isCurrent(), isTrue);
    expect(isCancelled?.call(), isFalse);
    onProgress?.call(1, 1);
    workspace = TerminalWorkspace(
      id: 'ws-123e4567-e89b-12d3-a456-426614174000',
      title: 'Cloud project',
      storage: storage!,
      remoteRoot: remoteRoot,
      remoteRootFingerprint: TerminalWorkspaceFingerprint(isDirectory: true),
      directoryPath: '/Documents/workspaces/project/files',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 1,
      status: TerminalWorkspaceStatus.ready,
      entries: const [],
    );
    return pending == null ? workspace! : pending!.future;
  }

  @override
  Future<List<TerminalWorkspace>> list({StorageReference? storage}) async => [
    if (workspace != null) workspace!,
  ];
  @override
  Future<TerminalWorkspace?> load(String id) async =>
      workspace?.id == id ? workspace : null;
  @override
  Future<List<TerminalWorkspaceChange>> inspect(
    String id, {
    bool Function()? isCancelled,
  }) async => [
    TerminalWorkspaceChange(
      workspaceId: id,
      manifestRevision: 1,
      relativePath: 'input.txt',
      remotePath: '/input.txt',
      kind: TerminalWorkspaceChangeKind.modified,
      digest: 'a' * 64,
      size: 3,
    ),
  ];
  @override
  Future<TerminalWorkspaceUploadResult> uploadReviewed({
    required String workspaceId,
    required CloudStorageClient client,
    required List<TerminalWorkspaceChange> changes,
    required bool Function() isCurrent,
    bool Function()? isCancelled,
  }) async {
    expect(isCurrent(), isTrue);
    expect(changes.single.relativePath, 'input.txt');
    uploadedClient = client;
    return TerminalWorkspaceUploadResult(
      workspace: workspace!,
      uploadedPaths: const ['input.txt'],
      skippedPaths: const [],
      failures: const {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('crisp_ios_shell/control');
  late WorkflowFakeClient cloud;
  late _Auth auth;
  late _Local local;
  late _Workspaces workspaces;
  late ProviderContainer container;
  late TerminalSession session;
  late Completer<Map<String, Object?>> output;
  late bool cleanupFails;
  String? shellDirectory;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloud = WorkflowFakeClient()..put('/input.txt', [1, 2, 3]);
    auth = _Auth(cloud);
    local = _Local();
    workspaces = _Workspaces();
    session = TerminalSession();
    output = Completer<Map<String, Object?>>();
    cleanupFails = false;
    shellDirectory = null;
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        localFileServiceProvider.overrideWithValue(local),
        terminalWorkspaceServiceProvider.overrideWithValue(workspaces),
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'start':
              shellDirectory =
                  (call.arguments as Map)['workingDirectory'] as String;
              return {'sessionId': 'native-test'};
            case 'read':
              return output.future;
            case 'close':
              if (cleanupFails) {
                throw PlatformException(code: 'cleanup_unconfirmed');
              }
              if (!output.isCompleted) {
                output.complete({'data': Uint8List(0), 'exitCode': 0});
              }
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    cleanupFails = false;
    await session.disconnect();
    session.dispose();
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester) async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    panel.toggleSelection(
      panel.files!.singleWhere((file) => file.name == 'input.txt'),
    );
    container.read(activePanelProvider.notifier).state = PanelSide.remote;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: TerminalPanel(session: session)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> action(WidgetTester tester, String title) async {
    await tester.tap(find.byKey(const ValueKey('terminal-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pump();
  }

  testWidgets(
    'stage opens the native shell and reviewed uploads keep the original account',
    (tester) async {
      await mount(tester);
      await action(tester, 'Stage selected files');
      await tester.pumpAndSettle();
      expect(workspaces.stagedClient, same(cloud));
      expect(workspaces.stagedItems!.single.path, '/input.txt');
      expect(shellDirectory, '/Documents/workspaces/project/files');
      expect(session.kind, TerminalSessionKind.ios);
      expect(local.leases, 1);
      expect(find.text('iOS shell · Cloud project'), findsOneWidget);

      container.read(activePanelProvider.notifier).state = PanelSide.local;
      await action(tester, 'Review uploads');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload selected'));
      await tester.pumpAndSettle();
      expect(workspaces.uploadedClient, same(cloud));
      expect(find.text('Uploaded: input.txt'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // The pending native reply was created by setUp on the real event loop.
      // Flush both clocks before awaiting the close future; awaiting it solely
      // inside FakeAsync prevents its read/close handshake from progressing.
      var disconnected = false;
      final disconnecting = session.disconnect().then((_) {
        disconnected = true;
      });
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(disconnected, isTrue);
      await disconnecting;
      expect(local.leases, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('cleanup failure stays visible with a working disconnect retry', (
    tester,
  ) async {
    await mount(tester);
    await action(tester, 'Stage selected files');
    await tester.pumpAndSettle();
    expect(local.leases, 1);

    cleanupFails = true;
    await action(tester, 'Disconnect');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('Shell cleanup failed'), findsOneWidget);
    expect(session.status, TerminalSessionStatus.failed);
    expect(local.leases, 1);

    await tester.tap(find.byKey(const ValueKey('terminal-actions')));
    await tester.pumpAndSettle();
    final disconnectItem = find.ancestor(
      of: find.text('Disconnect'),
      matching: find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem<dynamic>,
      ),
    );
    expect(
      tester.widget<PopupMenuItem<dynamic>>(disconnectItem).enabled,
      isTrue,
    );
    cleanupFails = false;
    await tester.tap(find.text('Disconnect'));
    // The original pending native read belongs to setUp's real event loop;
    // flush it as well as the widget clock to finish the retry handshake.
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.textContaining('Shell cleanup failed'), findsNothing);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(session.error, isNull);
    expect(session.canDisconnect, isFalse);
    expect(local.leases, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'account disconnection invalidates a staging request without opening a shell',
    (tester) async {
      workspaces.pending = Completer<TerminalWorkspace>();
      await mount(tester);
      await action(tester, 'Stage selected files');
      await tester.pump();
      expect(workspaces.current!(), isTrue);
      auth.disconnect();
      expect(workspaces.current!(), isFalse);
      workspaces.pending!.completeError(
        const TerminalWorkspaceException('Original account disconnected.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original account disconnected.'), findsOneWidget);
      expect(shellDirectory, isNull);
      expect(local.leases, 0);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
