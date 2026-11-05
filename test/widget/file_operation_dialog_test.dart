import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/file_operation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => '/landing';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

/// In-memory provider with actual stream, staging and rename semantics. The
/// production dialog, planner, backend and transfer queue all remain in use.
class _Cloud extends Fake implements CloudStorageClient {
  final files = <String, List<int>>{
    '/one.txt': utf8.encode('one\n'),
    '/two.bin': [0, 1, 2, 3],
  };
  final folders = <String>{'/', '/target'};
  final reads = <String>[];
  final uploads = <String>[];
  final deleted = <String>[];
  final renamed = <String>[];
  String account = 'first-account';

  @override
  String get providerName => 'Fixture cloud';
  @override
  String get rootPath => '/';
  @override
  String? get userId => account;
  @override
  String? get bucketId => 'fixture-bucket';
  @override
  bool get isAuthenticated => true;

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    if (!folders.contains(path)) throw StateError('No such folder: $path');
    return {
      'folders': [
        for (final folder in folders)
          if (folder != '/' && p.posix.dirname(folder) == path)
            {'name': p.posix.basename(folder)},
      ],
      'files': [
        for (final entry in files.entries)
          if (p.posix.dirname(entry.key) == path)
            {
              'name': p.posix.basename(entry.key),
              'path': entry.key,
              'size': entry.value.length,
              'lastModified': '2026-01-01T00:00:00Z',
            },
      ],
    };
  }

  @override
  Stream<List<int>> downloadStream(
    String path, {
    Function(int, int)? onProgress,
  }) async* {
    reads.add(path);
    final bytes = files[path];
    if (bytes == null) throw StateError('No such file: $path');
    yield List.of(bytes);
  }

  @override
  Future<void> uploadStream(
    Stream<List<int>> dataStream,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (!folders.contains(targetPath)) throw StateError('Missing parent');
    final path = p.posix.join(targetPath, fileName);
    final bytes = <int>[];
    await for (final chunk in dataStream) {
      bytes.addAll(chunk);
    }
    files[path] = bytes;
    uploads.add(path);
  }

  @override
  Future<void> createFolderPath(String path) async => folders.add(path);

  @override
  Future<void> renamePath(String path, String name) async {
    final target = p.posix.join(p.posix.dirname(path), name);
    if (!files.containsKey(path) || files.containsKey(target)) {
      throw StateError('Missing source or occupied destination');
    }
    files[target] = files.remove(path)!;
    renamed.add(path);
  }

  @override
  Future<void> deletePath(String path) async {
    files.remove(path);
    deleted.add(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => true;
  @override
  String? userEmail = 'first@example.test';
  @override
  String get providerName => client.providerName;

  void changeAccount() {
    client.account = 'replacement-account';
    userEmail = 'replacement@example.test';
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late _Auth auth;
  late ProviderContainer container;
  late List<FileItem> files;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    final remote = container.read(panelProvider(PanelSide.remote));
    await remote.refresh();
    files = remote.files!.where((file) => !file.isFolder).toList();
    final local = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    container
        .read(panelSourceProvider(PanelSide.local).notifier)
        .setSource(const LocalPanelSource('/landing'));
    await local.refresh();
  });

  tearDown(() => container.dispose());

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  Finder start(FileOperationKind kind) => find.widgetWithText(
    FilledButton,
    kind == FileOperationKind.copy ? 'Start Copy' : 'Start Move',
  );

  Future<void> open(
    WidgetTester tester, {
    FileOperationKind kind = FileOperationKind.copy,
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
          home: Scaffold(
            body: FileOperationDialog(
              side: PanelSide.remote,
              files: files,
              kind: kind,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> useCloudDestination(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<PanelSide>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This panel · Fixture cloud').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Destination directory'), '/target');
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester, String label) async {
    final row = find
        .ancestor(of: find.text(label), matching: find.byType(Row))
        .first;
    final checkbox = find.descendant(of: row, matching: find.byType(Checkbox));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
  }

  Future<void> runOperation(WidgetTester tester, FileOperationKind kind) async {
    final transfers = container.read(transferProvider);
    // Streaming jobs can advance outside the widget clock. Await the actual
    // transfer notification instead of mistaking a settled UI for completion.
    await tester.runAsync(() async {
      final completed = Completer<void>();
      void check() {
        if (transfers.operations.isNotEmpty &&
            !transfers.hasActiveOperations &&
            !completed.isCompleted) {
          completed.complete();
        }
      }

      transfers.addListener(check);
      try {
        await tester.tap(start(kind));
        check();
        await completed.future.timeout(const Duration(seconds: 5));
      } finally {
        transfers.removeListener(check);
      }
    });
    await tester.pumpAndSettle();
    expect(
      transfers.hasActiveOperations,
      isFalse,
      reason:
          'Transfer states: ${transfers.operations.map((op) => '${op.status}/${op.currentBytes}/${op.error}')}; '
          'reads: ${cloud.reads}; uploads: ${cloud.uploads}; renames: ${cloud.renamed}',
    );
  }

  testWidgets('default destination is the verified opposite storage and path', (
    tester,
  ) async {
    await open(tester);
    expect(
      tester
          .widget<DropdownButtonFormField<PanelSide>>(
            find.byType(DropdownButtonFormField<PanelSide>),
          )
          .initialValue,
      PanelSide.local,
    );
    expect(
      tester.widget<TextField>(field('Destination directory')).controller!.text,
      '/landing',
    );
    expect(
      find.text('From Fixture cloud · original item paths'),
      findsOneWidget,
    );
    expect(
      tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
      isNull,
    );
    expect(cloud.uploads, isEmpty);
  });

  testWidgets(
    'preview shows original paths and changing options invalidates it',
    (tester) async {
      await open(tester);
      await useCloudDestination(tester);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('/one.txt → /target/one.txt'), findsOneWidget);
      expect(find.text('/two.bin → /target/two.bin'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
        isNotNull,
      );
      expect(cloud.uploads, isEmpty);
      await tester.ensureVisible(field('File filter'));
      await tester.enterText(field('File filter'), '*.txt');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
        isNull,
      );
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('1 files in preview · 2 total rows'), findsOneWidget);
      expect(cloud.uploads, isEmpty);
    },
  );

  testWidgets(
    'an invalid regular expression cannot produce an executable plan',
    (tester) async {
      await open(tester);
      await useCloudDestination(tester);
      await toggle(tester, 'Regular expression');
      await tester.ensureVisible(field('File filter'));
      await tester.enterText(field('File filter'), '(');
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
        isNull,
      );
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(cloud.uploads, isEmpty);
    },
  );

  testWidgets(
    'copy combines keep-both, file filters and SHA-256 verification',
    (tester) async {
      final existing = utf8.encode('existing target');
      cloud.files['/target/one.txt'] = existing;
      await open(tester);
      await useCloudDestination(tester);
      await tester.tap(
        find.byType(DropdownButtonFormField<FileConflictPolicy>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep both (number new copies)').last);
      await tester.pumpAndSettle();
      await tester.enterText(field('File filter'), '*.txt');
      await toggle(tester, 'Verify contents (SHA-256)');
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await runOperation(tester, FileOperationKind.copy);
      expect(cloud.files['/target/one.txt'], existing);
      expect(cloud.files['/target/one (1).txt'], utf8.encode('one\n'));
      expect(cloud.files.containsKey('/target/two.bin'), isFalse);
      expect(cloud.files['/one.txt'], utf8.encode('one\n'));
      expect(cloud.reads, contains('/target/one (1).txt'));
      expect(
        find.text('1 completed · 1 skipped/filtered · 0 failed'),
        findsOneWidget,
      );
      expect(container.read(transferProvider).operations.single.error, isNull);
    },
  );

  testWidgets('move deletes only files that pass the configured filter', (
    tester,
  ) async {
    await open(tester, kind: FileOperationKind.move);
    await useCloudDestination(tester);
    await tester.enterText(field('File filter'), '*.txt');
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    await runOperation(tester, FileOperationKind.move);
    expect(cloud.files.containsKey('/one.txt'), isFalse);
    expect(cloud.files['/target/one.txt'], utf8.encode('one\n'));
    expect(cloud.files['/two.bin'], [0, 1, 2, 3]);
    expect(cloud.deleted, ['/one.txt']);
    expect(
      find.text('1 completed · 1 skipped/filtered · 0 failed'),
      findsOneWidget,
    );
  });

  testWidgets('a single-panel plan is blocked after its account changes', (
    tester,
  ) async {
    container.read(showDualPanelProvider.notifier).state = false;
    await open(tester);
    await useCloudDestination(tester);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    auth.changeAccount();
    await tester.pumpAndSettle();
    await runOperation(tester, FileOperationKind.copy);
    expect(cloud.uploads, isEmpty);
    expect(cloud.renamed, isEmpty);
    expect(cloud.deleted, isEmpty);
    expect(container.read(transferProvider).operations.single.error, isNotNull);
    expect(find.textContaining('storage account changed'), findsOneWidget);
  });

  testWidgets('options and preview fit a narrow window without layout errors', (
    tester,
  ) async {
    await open(tester, size: const Size(390, 740));
    expect(tester.takeException(), isNull);
    await useCloudDestination(tester);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('2 files in preview · 2 total rows'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
      isNotNull,
    );
  });
}
