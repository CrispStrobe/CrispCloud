import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/rename_batch.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/action_history_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/rename_batch_store.dart';
import 'package:crisp_cloud/widgets/batch_rename_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
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
  final paths = <String>{'/first.txt', '/second.txt'};
  final renames = <String>[];
  final rejectedRenames = <String>{};
  final sizes = <String, int>{};
  Future<void> Function(String path)? afterRename;
  String account = 'rename-account';
  bool pathUuids = false;
  @override
  String get providerName => 'Rename test';
  @override
  String get rootPath => '/';
  @override
  String? get userId => account;
  @override
  String? get bucketId => 'rename-bucket';
  @override
  bool get isAuthenticated => true;

  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      for (final file in paths)
        if (p.posix.dirname(file) == path)
          {
            'name': p.posix.basename(file),
            'path': file,
            'size': sizes[file] ?? 5,
            if (pathUuids) 'uuid': file,
          },
    ],
  };

  @override
  Future<void> renamePath(String path, String newName) async {
    if (rejectedRenames.contains(path)) {
      throw StateError('Rename refused before mutation');
    }
    final target = p.posix.join(p.posix.dirname(path), newName);
    if (!paths.contains(path) || paths.contains(target)) {
      throw StateError('Missing source or occupied destination');
    }
    paths.remove(path);
    paths.add(target);
    renames.add(path);
    await afterRename?.call(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? get userEmail => 'rename@example.test';
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late ProviderContainer container;
  late List<FileItem> files;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(_Local()),
        renameBatchStoreProvider.overrideWithValue(MemoryRenameBatchStore()),
      ],
    );
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    files = panel.files!.where((file) => !file.isFolder).toList();
  });

  tearDown(() => container.dispose());

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1100, 1000),
  }) async {
    tester.view.physicalSize = size;
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
            body: Consumer(
              builder: (context, ref, _) => BatchRenameDialog(
                parentRef: ref,
                side: PanelSide.remote,
                files: files,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('preview uses the real engine, with no write before applying', (
    tester,
  ) async {
    await open(tester);
    final apply = find.byKey(const ValueKey('rename-apply'));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'Trip_[C]',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-preview')));
    expect(find.text('→ Trip_001.txt'), findsOneWidget);
    expect(find.text('→ Trip_002.txt'), findsOneWidget);
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(cloud.renames, isEmpty);

    await tester.ensureVisible(find.byKey(const ValueKey('rename-name-mask')));
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'same',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(
      find.text('Resolve the marked preview errors before renaming.'),
      findsOneWidget,
    );
    expect(cloud.renames, isEmpty);
  });

  testWidgets(
    'applying the dialog renames on its captured source and reports success',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_new',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/first_new.txt', '/second_new.txt'});
      expect(cloud.renames, ['/first.txt', '/second.txt']);
      expect(
        find.text('2 renamed, 0 failed, 0 unchanged, 0 not run.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('rename-apply')), findsNothing);
    },
  );

  testWidgets('occupied destinations leave the entire batch untouched', (
    tester,
  ) async {
    cloud.paths.add('/second_new.txt');
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.renames, isEmpty);
    expect(cloud.paths, {'/first.txt', '/second.txt', '/second_new.txt'});
    expect(
      find.text(
        'Nothing was renamed. Resolve the path errors shown in the preview.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('changed source metadata blocks the batch before any rename', (
    tester,
  ) async {
    await open(tester);
    cloud.sizes['/second.txt'] = 9;
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.renames, isEmpty);
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(
      find.text(
        'Nothing was renamed. Resolve the path errors shown in the preview.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('presets persist and restore the actual mask settings', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'Trip_[C]',
    );
    await tester.tap(find.text('Save preset'));
    await tester.pumpAndSettle();
    final presetName = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Preset name',
    );
    await tester.enterText(presetName, 'Trip names');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('commander.multiRenamePresets.v1'),
      contains('Trip_[C]'),
    );
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('rename-name-mask')))
          .controller!
          .text,
      '[N]',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trip names').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('rename-name-mask')))
          .controller!
          .text,
      'Trip_[C]',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tool remains usable on a narrow window', (tester) async {
    await open(tester, size: const Size(390, 700));
    expect(find.text('Multi-rename (2 items)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_[C]',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-preview')));
    await tester.pumpAndSettle();
    expect(find.text('→ first_001.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual names stay attached to original paths after reordering', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('rename-edit-names')));
    await tester.tap(find.byKey(const ValueKey('rename-edit-names')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-names-input')),
      'manual-first.txt\nmanual-second.txt',
    );
    await tester.tap(find.byKey(const ValueKey('rename-names-apply')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reverse'));
    await tester.tap(find.text('Reverse'));
    await tester.pumpAndSettle();
    expect(cloud.renames, isEmpty);
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.renames, ['/second.txt', '/first.txt']);
    expect(cloud.paths, {'/manual-first.txt', '/manual-second.txt'});
  });

  testWidgets('a completed batch is one source-bound undo action', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    final history = container.read(actionHistoryProvider);
    expect(history.history, hasLength(1));
    expect(history.history.single.description, 'Renamed batch of 2 items');
    // Closing the dialog must not invalidate the captured undo callback.
    await tester.pumpWidget(const SizedBox.shrink());
    final undone = await history.undoLast(const UndoContext());
    expect(undone?.success, isTrue);
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(history.history, isEmpty);
  });

  testWidgets('disposing an active dialog retains undo for completed rows', (
    tester,
  ) async {
    final firstRenamed = Completer<void>();
    final continueOperation = Completer<void>();
    cloud.afterRename = (path) async {
      if (path == '/first.txt') {
        firstRenamed.complete();
        await continueOperation.future;
      }
    };
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pump();
    expect(firstRenamed.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    continueOperation.complete();
    await tester.pumpAndSettle();
    expect(cloud.paths, {'/first_new.txt', '/second.txt'});
    final history = container.read(actionHistoryProvider);
    expect(history.history, hasLength(1));
    final undone = await history.undoLast(const UndoContext());
    expect(undone?.success, isTrue);
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during the final rename records one complete undo', (
    tester,
  ) async {
    final lastRenamed = Completer<void>();
    final finishOperation = Completer<void>();
    cloud.afterRename = (path) async {
      if (path == '/second.txt') {
        lastRenamed.complete();
        await finishOperation.future;
      }
    };
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pump();
    expect(lastRenamed.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    finishOperation.complete();
    await tester.pumpAndSettle();
    expect(cloud.paths, {'/first_new.txt', '/second_new.txt'});
    final history = container.read(actionHistoryProvider);
    expect(history.history, hasLength(1));
    final record = (await container.read(renameBatchStoreProvider).list()).single;
    expect(record.isComplete, isTrue);
    expect(history.history.single.metadata['renameBatchId'], record.id);
    expect((await history.undoLast(const UndoContext()))?.success, isTrue);
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(history.history, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a partially failed batch keeps undo for its completed rows', (
    tester,
  ) async {
    cloud.rejectedRenames.add('/second.txt');
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.paths, {'/first_new.txt', '/second.txt'});
    expect(cloud.renames, ['/first.txt']);
    final history = container.read(actionHistoryProvider);
    expect(history.history, hasLength(1));
    final store = container.read(renameBatchStoreProvider);
    final record = (await store.list()).single;
    expect(record.state, RenameBatchState.failed);
    await tester.pumpWidget(const SizedBox.shrink());
    expect((await history.undoLast(const UndoContext()))?.success, isTrue);
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(cloud.renames, ['/first.txt', '/first_new.txt']);
    expect((await store.read(record.id))!.isRestored, isTrue);
    expect(history.history, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one journal-backed undo restores all 75 renamed items', (
    tester,
  ) async {
    final originals = {
      for (var index = 0; index < 75; index++) '/file-$index.txt',
    };
    cloud.paths
      ..clear()
      ..addAll(originals);
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    files = panel.files!.where((file) => !file.isFolder).toList();
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    final history = container.read(actionHistoryProvider);
    expect(history.history, hasLength(1));
    expect(history.history.single.metadata['renameBatchCount'], 75);
    expect(cloud.renames, hasLength(75));
    expect(
      (await container.read(renameBatchStoreProvider).list()).single.items,
      hasLength(75),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect((await history.undoLast(const UndoContext()))?.success, isTrue);
    expect(cloud.paths, originals);
    expect(cloud.renames, hasLength(150));
    expect(history.history, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('excluding a row keeps its file and reallocates the counter', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      'Trip_[C]',
    );
    await tester.pumpAndSettle();
    final exclude = find.byKey(const ValueKey('rename-exclude-/first.txt'));
    await tester.ensureVisible(exclude);
    await tester.tap(exclude);
    await tester.pumpAndSettle();
    expect(find.text('1 excluded from this batch'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.renames, ['/second.txt']);
    expect(cloud.paths, {'/first.txt', '/Trip_001.txt'});
  });

  testWidgets('invalid imported name counts cannot change the preview', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('rename-edit-names')));
    await tester.tap(find.byKey(const ValueKey('rename-edit-names')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-names-input')),
      'one.txt',
    );
    await tester.tap(find.byKey(const ValueKey('rename-names-apply')));
    await tester.pumpAndSettle();
    expect(
      find.text('Expected 2 names in preview order, but found 1.'),
      findsOneWidget,
    );
    expect(cloud.renames, isEmpty);
  });

  testWidgets(
    'successive transformations operate on the previous proposed name',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_trip',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('rename-add-step')));
      await tester.tap(find.byKey(const ValueKey('rename-add-step')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('rename-name-mask')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_[C:2]',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/first_trip_01.txt', '/second_trip_02.txt'});
      expect(cloud.renames.length, 2);
    },
  );

  testWidgets(
    'collision numbering checks siblings before showing final targets',
    (tester) async {
      cloud.paths.add('/same.txt');
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        'same',
      );
      await tester.tap(find.text('Advanced rename rules'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Number colliding targets'));
      await tester.tap(find.text('Number colliding targets'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/same.txt', '/same (1).txt', '/same (2).txt'});
      expect(cloud.renames, ['/first.txt', '/second.txt']);
    },
  );

  testWidgets('case-only plans stage safely and undo as one complete batch', (
    tester,
  ) async {
    cloud.pathUuids = true;
    await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('rename-edit-names')));
    await tester.tap(find.byKey(const ValueKey('rename-edit-names')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-names-input')),
      'FIRST.TXT\nsecond.txt',
    );
    await tester.tap(find.byKey(const ValueKey('rename-names-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.paths, {'/FIRST.TXT', '/second.txt'});
    expect(cloud.renames, hasLength(2));
    final history = container.read(actionHistoryProvider);
    expect(history.history, hasLength(1));
    expect(history.history.single.description, 'Renamed batch of 1 item');
    final records = await container.read(renameBatchStoreProvider).list();
    expect(records.single.steps, hasLength(2));
    expect(records.single.isComplete, isTrue);
    await tester.tap(find.text('Undo batch'));
    await tester.pumpAndSettle();
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(
      (await container.read(renameBatchStoreProvider).list()).single.isRestored,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the global undo entry works after closing the rename widget', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(container.read(actionHistoryProvider).history, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    final result = await container
        .read(actionHistoryProvider.notifier)
        .undoLast(const UndoContext());
    expect(result!.success, isTrue);
    expect(cloud.paths, {'/first.txt', '/second.txt'});
    expect(container.read(actionHistoryProvider).history, isEmpty);
  });

  testWidgets('earlier pipeline steps remain editable and can be reordered', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_first',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-add-step')));
    await tester.tap(find.byKey(const ValueKey('rename-add-step')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-name-mask')));
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_second',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rename-step-0')));
    await tester.tap(find.byKey(const ValueKey('rename-step-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_edited',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Step later'));
    await tester.tap(find.text('Step later'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    expect(cloud.paths, {
      '/first_second_edited.txt',
      '/second_second_edited.txt',
    });
  });

  testWidgets(
    'history restores a saved batch and next batch uses actual current names',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_new',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 items · completed'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restore original names'));
      await tester.tap(find.text('Restore original names'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Restore original names').last,
      );
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/first.txt', '/second.txt'});
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-next-batch')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('rename-name-mask')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_again',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/first_again.txt', '/second_again.txt'});
      final records = await container.read(renameBatchStoreProvider).list();
      expect(records, hasLength(2));
      expect(
        records.where((record) => record.state == RenameBatchState.restored),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a changed account blocks a prepared dialog before creating a journal',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_new',
      );
      await tester.pumpAndSettle();
      cloud.account = 'another-account';
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      expect(cloud.renames, isEmpty);
      expect(await container.read(renameBatchStoreProvider).list(), isEmpty);
      expect(
        find.text(
          'The storage source changed. Close this dialog and select the items again.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('history keeps a different same-path account read-only', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    cloud.account = 'another-account';
    await container.read(panelProvider(PanelSide.remote)).refresh();
    await tester.tap(find.byKey(const ValueKey('rename-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 items · completed'));
    await tester.pumpAndSettle();
    final restore = find.widgetWithText(FilledButton, 'Restore original names');
    expect(tester.widget<FilledButton>(restore).onPressed, isNull);
    expect(cloud.renames, hasLength(2));
  });

  testWidgets(
    'history resolves a connected original account independently of the pane',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('rename-name-mask')),
        '[N]_new',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rename-apply')));
      await tester.pumpAndSettle();
      container
          .read(multiCloudProvider)
          .addConnection(
            id: 'original',
            label: 'Original account',
            provider: CloudProvider.filen,
            client: cloud,
          );
      final other = _Cloud()..account = 'other-account';
      other.paths
        ..clear()
        ..addAll({'/first_new.txt', '/second_new.txt'});
      final auth = container.read(authProvider) as _Auth;
      auth.client = other;
      auth.notifyListeners();
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(
            RemotePanelSource(
              providerName: other.providerName,
              client: other,
              path: '/',
            ),
          );
      await container.read(panelProvider(PanelSide.remote)).refresh();
      await tester.tap(find.byKey(const ValueKey('rename-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 items · completed'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Restore original names'));
      await tester.tap(find.text('Restore original names'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Restore original names').last,
      );
      await tester.pumpAndSettle();
      expect(cloud.paths, {'/first.txt', '/second.txt'});
      expect(other.paths, {'/first_new.txt', '/second_new.txt'});
      expect(other.renames, isEmpty);
    },
  );

  testWidgets('history and report remain usable in a narrow window', (
    tester,
  ) async {
    await open(tester, size: const Size(390, 700));
    await tester.enterText(
      find.byKey(const ValueKey('rename-name-mask')),
      '[N]_new',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rename-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export report'));
    await tester.pumpAndSettle();
    expect(find.text('Rename batch report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
