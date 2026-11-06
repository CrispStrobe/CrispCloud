import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/rename_batch.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/screens/screen_dialogs.dart' as screens;
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/native_file_primitives.dart';
import 'package:crisp_cloud/services/rename_batch_store.dart';
import 'package:crisp_cloud/widgets/file_context_menu.dart' as menus;
import 'package:crisp_cloud/widgets/file_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
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
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() work,
  ) => work();
}

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account);
  final String account;
  final created = <String>[];
  final renames = <String>[];
  bool failCreate = false;
  Completer<void>? pendingCreate;
  Completer<void>? pendingList;
  @override
  String? get userId => account;
  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    await pendingList?.future;
    return super.listPath(path);
  }

  @override
  Future<void> createFolderPath(String path) async {
    if (failCreate) throw StateError('Fixture denied creation');
    created.add(path);
    await pendingCreate?.future;
    return super.createFolderPath(path);
  }

  @override
  Future<void> renamePath(String path, String name) async {
    renames.add(path);
    return super.renamePath(path, name);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  _Cloud client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;
  @override
  CloudProvider get currentProvider => CloudProvider.sftp;
  void replace(_Cloud next) {
    client = next;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Cloud cloud;
  late _Auth auth;
  late _Local local;
  late ProviderContainer container;
  late PanelNotifier panel;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud('original')..put('/old.txt', [1, 2, 3, 4]);
    cloud.directories.add('/elsewhere');
    auth = _Auth(cloud);
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
        renameBatchStoreProvider.overrideWithValue(MemoryRenameBatchStore()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());
  FileItem getFile() =>
      panel.files!.firstWhere((file) => file.path == '/old.txt');

  Future<void> open(
    WidgetTester tester,
    void Function(BuildContext, WidgetRef) action,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => action(context, ref),
                child: const Text('Open prompt'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open prompt'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const ValueKey('file-name-input')), name);
    await tester.tap(find.byKey(const ValueKey('file-name-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('new folder keeps its captured parent after panel navigation', (
    tester,
  ) async {
    await open(
      tester,
      (context, ref) =>
          screens.showCreateFolderDialog(context, ref, PanelSide.remote),
    );
    await panel.navigateToPath('/elsewhere');
    await submit(tester, 'created');
    expect(cloud.created, ['/created']);
    expect(cloud.directories, isNot(contains('/elsewhere/created')));
    expect(find.byType(FileNameDialog), findsNothing);
    expect(find.text('Created folder "created"'), findsOneWidget);
  });

  testWidgets(
    'new folder refuses an account switch made while the prompt is open',
    (tester) async {
      await open(
        tester,
        (context, ref) =>
            screens.showCreateFolderDialog(context, ref, PanelSide.remote),
      );
      final replacement = _Cloud('replacement');
      auth.replace(replacement);
      await panel.refresh();
      await submit(tester, 'created');
      expect(cloud.created, isEmpty);
      expect(replacement.created, isEmpty);
      expect(find.byType(FileNameDialog), findsOneWidget);
      expect(
        find.textContaining('original storage disconnected'),
        findsOneWidget,
      );
      expect(find.text('Created folder "created"'), findsNothing);
      expect(container.read(actionHistoryProvider).history, isEmpty);
    },
  );

  testWidgets('failed creation stays open and keyboard retry runs once', (
    tester,
  ) async {
    cloud.failCreate = true;
    await open(
      tester,
      (context, ref) =>
          screens.showCreateFolderDialog(context, ref, PanelSide.remote),
    );
    await submit(tester, 'created');
    expect(find.textContaining('Fixture denied creation'), findsOneWidget);
    expect(find.text('Created folder "created"'), findsNothing);
    cloud.failCreate = false;
    cloud.pendingCreate = Completer<void>();
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('file-name-input')),
    );
    input.onSubmitted!('created');
    input.onSubmitted!('created');
    await tester.pump();
    expect(cloud.created, ['/created']);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('file-name-submit')))
          .onPressed,
      isNull,
    );
    cloud.pendingCreate!.complete();
    await tester.pumpAndSettle();
    expect(cloud.created, ['/created']);
    expect(find.byType(FileNameDialog), findsNothing);
  });

  for (final contextMenu in [false, true]) {
    testWidgets(
      '${contextMenu ? 'context' : 'keyboard'} rename rejects a same-size replacement after its prompt opens',
      (tester) async {
        final file = getFile();
        panel.setCursorOnly(file);
        container.read(activePanelProvider.notifier).state = PanelSide.remote;
        await open(
          tester,
          (context, ref) => contextMenu
              ? menus.showRenameDialog(context, ref, PanelSide.remote, file)
              : screens.showRenameDialog(context, ref),
        );
        cloud.put('/old.txt', [9, 8, 7, 6], date: file.updatedAt);
        await submit(tester, 'new.txt');
        expect(cloud.renames, isEmpty);
        expect(cloud.files['/old.txt'], [9, 8, 7, 6]);
        expect(cloud.files['/new.txt'], isNull);
        expect(find.byType(FileNameDialog), findsOneWidget);
        expect(find.textContaining('original item changed'), findsOneWidget);
        expect(find.text('Renamed "old.txt" to "new.txt"'), findsNothing);
        expect(await container.read(renameBatchStoreProvider).list(), isEmpty);
      },
    );
  }

  testWidgets(
    'pending rename can be cancelled and retried without mutating its source',
    (tester) async {
      final file = getFile();
      await open(
        tester,
        (context, ref) =>
            menus.showRenameDialog(context, ref, PanelSide.remote, file),
      );
      cloud.pendingList = Completer<void>();
      await tester.enterText(
        find.byKey(const ValueKey('file-name-input')),
        'new.txt',
      );
      await tester.tap(find.byKey(const ValueKey('file-name-submit')));
      await tester.pump();
      await tester.tap(find.text('Cancel operation'));
      cloud.pendingList!.complete();
      await tester.pumpAndSettle();
      expect(cloud.renames, isEmpty);
      expect(cloud.files['/old.txt'], [1, 2, 3, 4]);
      expect(find.textContaining('Rename cancelled'), findsOneWidget);
      expect(find.byType(FileNameDialog), findsOneWidget);
      cloud.pendingList = null;
      await tester.tap(find.byKey(const ValueKey('file-name-submit')));
      await tester.pumpAndSettle();
      expect(cloud.files['/new.txt'], [1, 2, 3, 4]);
      expect(find.byType(FileNameDialog), findsNothing);
    },
  );

  test('rename fingerprints retain every supplied provider version and content hash', () {
    for (final key in [
      'version',
      'eTag',
      'etag',
      'versionId',
      'revision',
      'rev',
      'cTag',
      'generation',
      'content_hash',
    ]) {
      FileItem file(String evidence) => FileItem(
        name: 'same.txt',
        path: '/same.txt',
        isFolder: false,
        size: 4,
        metadata: {key: evidence},
      );
      final before = RenameFingerprint.fromFile(file('original'));
      final restored = RenameFingerprint.fromJson(before.toJson());
      expect(
        restored.matches(RenameFingerprint.fromFile(file('replacement'))),
        isFalse,
        reason: key,
      );
      expect(
        restored.matches(RenameFingerprint.fromFile(file('original'))),
        isTrue,
        reason: key,
      );
    }
    expect(
      RenameFingerprint.fromFile(
        FileItem(
          name: 'empty.txt',
          path: '/empty.txt',
          isFolder: false,
          metadata: {'content_hash': ''},
        ),
      ).canReconcile,
      isFalse,
    );
  });

  test(
    'case-only single rename uses the shared staging and undo path',
    () async {
      await panel.renameFile(getFile(), 'OLD.txt', rethrowErrors: true);
      final record =
          (await container.read(renameBatchStoreProvider).list()).single;
      expect(record.steps, hasLength(2));
      expect(record.isComplete, isTrue);
      expect(cloud.files['/OLD.txt'], [1, 2, 3, 4]);
      expect(
        cloud.files.keys.where((path) => path.contains('.crisp-rename-')),
        isEmpty,
      );
      final history = container.read(actionHistoryProvider);
      final result = await history.undo(
        history.lastAction!.id,
        const UndoContext(),
      );
      expect(result.success, isTrue);
      expect(cloud.files['/old.txt'], [1, 2, 3, 4]);
    },
  );

  test(
    'single rename is journalled and undo refuses a replacement object',
    () async {
      final file = getFile();
      var cancelled = false;
      await panel.renameFile(
        file,
        'new.txt',
        rethrowErrors: true,
        isCancelled: () => cancelled,
      );
      cancelled = true; // The finished prompt token must not invalidate Undo.
      expect(cloud.files['/new.txt'], [1, 2, 3, 4]);
      final store = container.read(renameBatchStoreProvider);
      final record = (await store.list()).single;
      expect(record.isComplete, isTrue);
      final history = container.read(actionHistoryProvider);
      final action = history.lastAction!;
      expect(action.metadata['renameBatchId'], record.id);
      cloud.put('/new.txt', [9, 8, 7, 6]);
      final undo = await history.undo(action.id, const UndoContext());
      expect(undo.success, isFalse);
      expect(cloud.renames, ['/old.txt']);
      expect(cloud.files['/new.txt'], [9, 8, 7, 6]);
      expect(cloud.files['/old.txt'], isNull);
      expect(history.history, hasLength(1));
      cloud.put('/new.txt', [1, 2, 3, 4]);
      final retry = await history.undo(action.id, const UndoContext());
      expect(retry.success, isTrue);
      expect(cloud.files['/old.txt'], [1, 2, 3, 4]);
      expect((await store.read(record.id))!.isRestored, isTrue);
    },
  );

  test(
    'native undo verifies same-size content even when timestamps are retained',
    () async {
      final directory = await Directory.systemTemp.createTemp('single-rename-');
      addTearDown(() => directory.delete(recursive: true));
      final original = await File('${directory.path}/old.txt')
          .writeAsString('old!');
      local.directory = directory.path;
      final localPanel = container.read(panelProvider(PanelSide.local));
      await localPanel.navigateToPath(directory.path);
      final file = localPanel.files!.firstWhere(
        (file) => file.path == original.path,
      );
      await localPanel.renameFile(file, 'new.txt', rethrowErrors: true);
      final renamed = File('${directory.path}/new.txt');
      final stat = await renamed.stat();
      await renamed.writeAsString('new!');
      await renamed.setLastModified(stat.modified);
      final history = container.read(actionHistoryProvider);
      final result = await history.undo(
        history.lastAction!.id,
        const UndoContext(),
      );
      expect(result.success, isFalse);
      expect(await renamed.readAsString(), 'new!');
      expect(await original.exists(), isFalse);
    },
    skip: !supportsNativeExclusiveRename,
  );

  test(
    'native fingerprint checks cancellation while streaming file content',
    () async {
      final directory = await Directory.systemTemp.createTemp('rename-cancel-');
      addTearDown(() => directory.delete(recursive: true));
      final original = await File('${directory.path}/file.bin')
          .writeAsBytes(List.filled(1024 * 1024, 65));
      local.directory = directory.path;
      final localPanel = container.read(panelProvider(PanelSide.local));
      await localPanel.navigateToPath(directory.path);
      final file = localPanel.files!.firstWhere(
        (file) => file.path == original.path,
      );
      var cancelled = false;
      final storage = localPanel.createRenameStorage(
        localPanel.captureOperationOrigin([file]),
        isCancelled: () => cancelled,
      );
      final digest = storage.contentDigest(file);
      cancelled = true;
      await expectLater(digest, throwsStateError);
      expect(await original.length(), 1024 * 1024);
    },
    skip: !supportsNativeExclusiveRename,
  );
}
