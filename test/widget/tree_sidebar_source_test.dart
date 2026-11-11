import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/multi_cloud_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/tree_sidebar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends CloudStorageClient {
  _Cloud(this.account);
  final String account;
  bool authenticated = true;
  final requests = <String>[];
  final delays = <String, Completer<void>>{};
  final failures = <String>{};
  @override
  String get providerName => 'Tree cloud';
  @override
  String get userId => account;
  @override
  String get rootPath => '/';
  @override
  String? get bucketId => null;
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> logout() async {
    authenticated = false;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    requests.add(path);
    if (delays[path] case final delayed?) await delayed.future;
    if (failures.contains(path))
      throw StateError('Directory temporarily unavailable');
    return {
      'files': <Map<String, Object>>[],
      'folders': [
        if (path == '/') ...[
          {'name': 'shared'},
          {'name': '$account-only'},
          {'name': '.hidden'},
        ],
        if (path == '/shared') {'name': '$account-child'},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => client.authenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => '${client.account}@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  String? allowedRoot;
  final operations = <Future<void>>[];
  final denied = <String>{};
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => allowedRoot ?? '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => !denied.contains(path);
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      allowedRoot != null && path.startsWith(allowedRoot!)
      ? Directory(path).list().toList()
      : [];
  @override
  Future<void> refresh() async {}
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    if (allowedRoot == null || !path.startsWith(allowedRoot!)) {
      throw FileSystemException('Outside the selected test folder', path);
    }
    final operation = action();
    operations.add(operation.then<void>((_) {}));
    return operation;
  }
}

void main() {
  late _Cloud first;
  late _Cloud second;
  late _Local local;
  late ProviderContainer container;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    first = _Cloud('a');
    second = _Cloud('b');
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(first)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'b',
          label: 'Second account',
          provider: CloudProvider.s3,
          client: second,
        );
    for (final side in PanelSide.values) {
      await container.read(panelProvider(side)).refresh();
    }
  });
  tearDown(() => container.dispose());

  Future<PanelNotifier> open(
    PanelSide side,
    _Cloud client, [
    String path = '/',
  ]) async {
    final panel = container.read(panelProvider(side));
    final origin = panel.resolveStorageReference(
      storageReferenceForClient(client),
      path,
    )!;
    await panel.navigateToPath(path, origin: origin);
    container.read(activePanelProvider.notifier).state = side;
    return panel;
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: TreeSidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expand(
    WidgetTester tester,
    StorageReference storage,
    String path,
  ) async {
    final node = find.byKey(ValueKey('tree:${storage.id}:$path'));
    await tester.ensureVisible(node);
    await tester.tap(
      find.descendant(of: node, matching: find.byTooltip('Expand folder')),
    );
    await tester.pump();
  }

  testWidgets('left pane tree expands its selected secondary account', (
    tester,
  ) async {
    final panel = await open(PanelSide.local, second);
    await mount(tester);
    expect(find.text('b-only'), findsOneWidget);
    expect(find.text('a-only'), findsNothing);
    await expand(tester, storageReferenceForClient(second), '/shared');
    await tester.pumpAndSettle();
    expect(find.text('b-child'), findsOneWidget);
    expect(second.requests, contains('/shared'));
    expect(first.requests, isNot(contains('/shared')));
    await tester.tap(find.text('b-child'));
    await tester.pumpAndSettle();
    expect(panel.currentPath, '/shared/b-child');
    expect(
      panel.captureCurrentOrigin().storageReference,
      storageReferenceForClient(second),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-path caches are cleared when the account changes', (
    tester,
  ) async {
    await open(PanelSide.remote, first);
    await mount(tester);
    await expand(tester, storageReferenceForClient(first), '/shared');
    await tester.pumpAndSettle();
    expect(find.text('a-child'), findsOneWidget);
    await open(PanelSide.remote, second);
    await tester.pumpAndSettle();
    expect(find.text('a-child'), findsNothing);
    expect(find.text('a-only'), findsNothing);
    await expand(tester, storageReferenceForClient(second), '/shared');
    await tester.pumpAndSettle();
    expect(find.text('b-child'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late expansion responses cannot publish into a replacement source',
    (tester) async {
      await open(PanelSide.remote, first);
      await mount(tester);
      final delayed = Completer<void>();
      first.delays['/shared'] = delayed;
      await expand(tester, storageReferenceForClient(first), '/shared');
      await open(PanelSide.remote, second);
      await tester.pump();
      delayed.complete();
      await tester.pumpAndSettle();
      expect(find.text('a-child'), findsNothing);
      expect(find.text('b-only'), findsOneWidget);
      expect(find.text('Could not load folders. Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable account shows no old hierarchy or current-account substitute',
    (tester) async {
      final panel = await open(PanelSide.remote, first);
      await mount(tester);
      final requests = first.requests.length;
      await panel.restoreTabs([
        {
          'path': '/private',
          'storage': const StorageReference(
            kind: 'remote',
            provider: 'Tree cloud',
            accountKey: 'unavailable',
          ).toJson(),
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('a-only'), findsNothing);
      expect(find.text('shared'), findsNothing);
      expect(
        find.text('Open an available folder to browse its tree.'),
        findsOneWidget,
      );
      expect(first.requests.length, requests);
    },
  );

  testWidgets(
    'child-list failures expose retry without poisoning the cached directory',
    (tester) async {
      await open(PanelSide.remote, second);
      second.failures.add('/shared');
      await mount(tester);
      await expand(tester, storageReferenceForClient(second), '/shared');
      await tester.pumpAndSettle();
      expect(find.text('Could not load folders. Retry'), findsOneWidget);
      second.failures.clear();
      await tester.tap(find.text('Could not load folders. Retry'));
      await tester.pumpAndSettle();
      expect(find.text('b-child'), findsOneWidget);
      expect(find.text('Could not load folders. Retry'), findsNothing);
    },
  );

  testWidgets(
    'right pane local tree reads local folders while a cloud remains connected',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('tree-source-'),
      ))!;
      addTearDown(() => temp.delete(recursive: true));
      await tester.runAsync(
        () =>
            Directory('${temp.path}/local-folder/child')
                .create(recursive: true),
      );
      local.allowedRoot = temp.path;
      final panel = container.read(panelProvider(PanelSide.remote));
      await tester.runAsync(
        () => panel.navigateToPath(
          temp.path,
          origin: panel.captureLocalClipboardOrigin(temp.path),
        ),
      );
      container.read(activePanelProvider.notifier).state = PanelSide.remote;
      await mount(tester);
      final requestCount = first.requests.length;
      final storage = panel.captureCurrentOrigin().storageReference;
      expect(find.byKey(ValueKey('tree:${storage.id}:/')), findsNothing);
      expect(
        find.byKey(ValueKey('tree:${storage.id}:${temp.path}')),
        findsOneWidget,
      );
      local.denied.add('${temp.path}/local-folder');
      await expand(tester, storage, '${temp.path}/local-folder');
      await tester.pumpAndSettle();
      expect(find.text('Could not load folders. Retry'), findsOneWidget);
      // A background tree read must not invoke a scope operation that could
      // ask the OS for a new grant when the route is inaccessible.
      expect(local.operations, isEmpty);
      local.denied.clear();
      // Start the native read in the real async zone as well as awaiting it.
      // Waiting here on a read created by fakeAsync would prevent its
      // continuations from running and deadlock the widget test.
      await tester.runAsync(() async {
        await tester.tap(find.text('Could not load folders. Retry'));
        await Future.wait(local.operations);
      });
      await tester.pumpAndSettle();
      expect(find.text('child'), findsOneWidget);
      expect(first.requests.length, requestCount);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden folder preference applies to every loaded tree branch', (
    tester,
  ) async {
    final panel = await open(PanelSide.remote, second);
    await mount(tester);
    expect(find.text('.hidden'), findsNothing);
    panel.toggleShowHiddenFiles();
    await tester.pumpAndSettle();
    expect(find.text('.hidden'), findsOneWidget);
  });
}
