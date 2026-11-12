import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/file_search_query.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_profiles.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/saved_search_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
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
  Future<void> Function(String)? beforeDelete;
  Future<void> Function(String)? beforeList;
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
    await beforeList?.call(path);
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
    await beforeDelete?.call(path);
    files.remove(path);
    deleted.add(path);
  }
}

class _JournalStorage extends MemoryTransferJournalStorage {
  bool failWrites = false;
  @override
  Future<void> append(String line) async {
    if (failWrites) throw StateError('Transfer history could not be saved');
    await super.append(line);
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
  late _JournalStorage journalStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud();
    auth = _Auth(cloud);
    journalStorage = _JournalStorage();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
        transferJournalProvider.overrideWithValue(
          TransferJournal(journalStorage),
        ),
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
    Locale locale = const Locale('en'),
    double textScale = 1,
    FileOperationBackend? sourceBackend,
    PanelFileOrigin? sourceOrigin,
    bool inRoute = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dialog = FileOperationDialog(
      side: PanelSide.remote,
      files: files,
      kind: kind,
      sourceBackend: sourceBackend,
      sourceOrigin: sourceOrigin,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: inRoute
                ? Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => dialog,
                      ),
                      child: const Text('Open transfer'),
                    ),
                  )
                : dialog,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (inRoute) {
      await tester.tap(find.text('Open transfer'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> useCloudDestination(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<PanelSide>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This panel · Fixture cloud').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Destination directory'), '/target');
    await tester.pumpAndSettle();
  }

  Future<({BuildContext context, WidgetRef ref})> mountReviewHost(
    WidgetTester tester,
    FocusNode inputFocus,
  ) async {
    late BuildContext invocationContext;
    late WidgetRef invocationRef;
    final local = container.read(panelProvider(PanelSide.local));
    final remote = container.read(panelProvider(PanelSide.remote));
    container.read(activePanelProvider.notifier).state = PanelSide.local;
    container.read(focusAreaProvider.notifier).state = FocusArea.local;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                invocationContext = context;
                invocationRef = ref;
                return Column(
                  children: [
                    Focus(
                      focusNode: local.listFocusNode,
                      autofocus: true,
                      child: const Text('Local browser'),
                    ),
                    Focus(
                      focusNode: remote.listFocusNode,
                      child: const Text('Remote browser'),
                    ),
                    TextField(focusNode: inputFocus),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(local.listFocusNode.hasFocus, isTrue);
    return (context: invocationContext, ref: invocationRef);
  }

  testWidgets('a paste review returns focus to its invoking destination pane', (
    tester,
  ) async {
    final inputFocus = FocusNode();
    addTearDown(inputFocus.dispose);
    final host = await mountReviewHost(tester, inputFocus);
    final local = container.read(panelProvider(PanelSide.local));
    final remote = container.read(panelProvider(PanelSide.remote));
    final review = showFileOperationDialog(
      host.context,
      host.ref,
      PanelSide.remote,
      files,
      kind: FileOperationKind.copy,
      sourceOrigin: remote.captureOperationOrigin(files),
      destinationOrigin: local.captureCurrentOrigin(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await review;
    expect(local.listFocusNode.hasFocus, isTrue);
    expect(remote.listFocusNode.hasFocus, isFalse);
    expect(container.read(activePanelProvider), PanelSide.local);
    expect(container.read(focusAreaProvider), FocusArea.local);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a closing review does not reclaim changed input ownership', (
    tester,
  ) async {
    final inputFocus = FocusNode();
    addTearDown(inputFocus.dispose);
    final host = await mountReviewHost(tester, inputFocus);
    final local = container.read(panelProvider(PanelSide.local));
    final remote = container.read(panelProvider(PanelSide.remote));
    final review = showFileOperationDialog(
      host.context,
      host.ref,
      PanelSide.remote,
      files,
      kind: FileOperationKind.copy,
      sourceOrigin: remote.captureOperationOrigin(files),
      destinationOrigin: local.captureCurrentOrigin(),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(FileOperationDialog))).pop();
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    inputFocus.requestFocus();
    await tester.pumpAndSettle();
    await review;
    expect(inputFocus.hasFocus, isTrue);
    expect(local.listFocusNode.hasFocus, isFalse);
    expect(remote.listFocusNode.hasFocus, isFalse);
    expect(container.read(focusAreaProvider), FocusArea.terminal);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'translated transfer controls remain scrollable with large RTL text',
    (tester) async {
      await open(
        tester,
        size: const Size(320, 740),
        locale: const Locale('ar'),
        textScale: 1.8,
      );
      expect(tester.takeException(), isNull);
      final method = find.byKey(const ValueKey('transfer-copy-method'));
      await tester.ensureVisible(method);
      await tester.pumpAndSettle();
      expect(Directionality.of(tester.element(method)), TextDirection.rtl);
      expect(find.text('طريقة النسخ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final filters = field('فلتر الملفات');
      await tester.ensureVisible(filters);
      await tester.enterText(filters, '*.txt|Cancel.txt');
      expect(
        tester.widget<TextField>(filters).controller!.text,
        '*.txt|Cancel.txt',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy method options explain capabilities and survive profile saving',
    (tester) async {
      await open(tester);
      await useCloudDestination(tester);
      final method = find.byKey(const ValueKey('transfer-copy-method'));
      await tester.ensureVisible(method);
      final dropdown = tester.widget<DropdownButton<FileCopyMethod>>(
        find.descendant(
          of: method,
          matching: find.byType(DropdownButton<FileCopyMethod>),
        ),
      );
      expect(
        dropdown.items!
            .singleWhere((item) => item.value == FileCopyMethod.copyOnWrite)
            .enabled,
        isFalse,
      );
      expect(
        find.text('This destination cannot reserve physical disk space.'),
        findsOneWidget,
      );
      final allocationRow = find
          .ancestor(
            of: find.text('Reserve destination disk space before copying'),
            matching: find.byType(Row),
          )
          .first;
      final allocation = tester.widget<Checkbox>(
        find.descendant(of: allocationRow, matching: find.byType(Checkbox)),
      );
      expect(allocation.onChanged, isNull);

      await tester.tap(method);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stream all data').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save as defaults'));
      await tester.tap(find.text('Save as defaults'));
      await tester.pumpAndSettle();
      final saved = await FileOperationProfiles().load();
      expect(saved['@default:copy']!.copyMethod, FileCopyMethod.stream);
      expect(saved['@default:copy']!.preallocate, isFalse);
      expect(cloud.uploads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'planning reports progress and supports pause and cancellation before writes',
    (tester) async {
      cloud.folders.add('/large');
      cloud.files['/large/nested.txt'] = [1, 2, 3];
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      files = [panel.files!.singleWhere((file) => file.path == '/large')];
      await open(tester);
      await useCloudDestination(tester);
      final listing = Completer<void>();
      cloud.beforeList = (path) async {
        if (path == '/large') await listing.future;
      };
      await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Preparing preview · 1 items checked'), findsOneWidget);
      expect(find.text('/large'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, 'Pause'));
      await tester.pump();
      expect(find.widgetWithText(TextButton, 'Resume'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel operation'));
      listing.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
        isNull,
      );
      expect(cloud.uploads, isEmpty);
      expect(cloud.deleted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

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
    // Provider startup loads its durable journal. Initialize it in the real
    // async zone used by stream jobs, not the widget's suspended fake clock.
    final transfers = await tester.runAsync(() async {
      final notifier = container.read(transferProvider);
      await notifier.ready;
      return notifier;
    });
    // Streaming jobs can advance outside the widget clock. Await the actual
    // transfer notification instead of mistaking a settled UI for completion.
    await tester.runAsync(() async {
      final completed = Completer<void>();
      void check() {
        if (transfers!.operations.isNotEmpty &&
            !transfers.hasActiveOperations &&
            !completed.isCompleted) {
          completed.complete();
        }
      }

      transfers!.addListener(check);
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
      transfers!.hasActiveOperations,
      isFalse,
      reason:
          'Transfer states: ${transfers.operations.map((op) => '${op.status}/${op.currentBytes}/${op.error}')}; '
          'reads: ${cloud.reads}; uploads: ${cloud.uploads}; renames: ${cloud.renamed}',
    );
  }

  testWidgets(
    'a cancelled transfer preview preserves the preceding selection memory',
    (tester) async {
      final panel = container.read(panelProvider(PanelSide.remote));
      panel.toggleSelection(
        files.singleWhere((file) => file.path == '/one.txt'),
      );
      panel.rememberSelection();
      panel.clearSelection();
      panel.toggleSelection(
        files.singleWhere((file) => file.path == '/two.bin'),
      );
      files = panel.selection.toList();
      await open(tester, inRoute: true);
      await useCloudDestination(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      panel.clearSelection();
      expect(panel.restoreSelection(), 1);
      expect(panel.selection.single.path, '/one.txt');
      expect(cloud.uploads, isEmpty);
    },
  );

  testWidgets(
    'an accepted transfer remembers the marks captured before its review',
    (tester) async {
      final panel = container.read(panelProvider(PanelSide.remote));
      panel.toggleSelection(
        files.singleWhere((file) => file.path == '/one.txt'),
      );
      panel.rememberSelection();
      panel.clearSelection();
      panel.toggleSelection(
        files.singleWhere((file) => file.path == '/two.bin'),
      );
      files = panel.selection.toList();
      await open(tester);
      await useCloudDestination(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
      await tester.pumpAndSettle();
      // Changes to the live marks while reviewing cannot alter the captured set.
      panel.clearSelection();
      await runOperation(tester, FileOperationKind.copy);
      panel.clearSelection();
      expect(panel.restoreSelection(), 1);
      expect(panel.selection.single.path, '/two.bin');
      expect(cloud.files['/target/two.bin'], [0, 1, 2, 3]);
      expect(cloud.files.containsKey('/target/one.txt'), isFalse);
    },
  );

  testWidgets('snapshot source copies through the captured read backend', (
    tester,
  ) async {
    final snapshot = _Cloud();
    snapshot.files.clear();
    snapshot.files['/member.txt'] = utf8.encode('from archive');
    final origin = container
        .read(panelProvider(PanelSide.remote))
        .captureCurrentOrigin();
    files = [
      FileItem(
        name: 'member.txt',
        path: '/member.txt',
        isFolder: false,
        size: 12,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    await open(
      tester,
      sourceBackend: CloudOperationBackend(snapshot, isCurrent: () => true),
      sourceOrigin: origin,
    );
    await useCloudDestination(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.pumpAndSettle();
    await runOperation(tester, FileOperationKind.copy);
    expect(cloud.files['/target/member.txt'], utf8.encode('from archive'));
    expect(snapshot.reads, contains('/member.txt'));
    expect(cloud.reads, isNot(contains('/member.txt')));
    expect(find.text('Queue in background'), findsNothing);
  });

  testWidgets('saved search metadata criteria filter the reviewed transfer', (
    tester,
  ) async {
    await SavedSearchService().save(
      SavedSearch(
        name: 'Small text files',
        query: '*',
        createdAt: DateTime.utc(2026),
        settings: const FileSearchQuery(extensions: ['txt'], maxSize: 8),
      ),
    );
    await open(tester);
    await useCloudDestination(tester);
    final choose = find.widgetWithText(
      OutlinedButton,
      'Use saved search criteria',
    );
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Small text files'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Preview'));
    await tester.pumpAndSettle();
    await runOperation(tester, FileOperationKind.copy);
    expect(cloud.files['/target/one.txt'], utf8.encode('one\n'));
    expect(cloud.files.containsKey('/target/two.bin'), isFalse);
  });

  testWidgets(
    'content criteria remain explicit instead of being silently omitted',
    (tester) async {
      await SavedSearchService().save(
        SavedSearch(
          name: 'Search file contents',
          query: '*',
          createdAt: DateTime.utc(2026),
          settings: const FileSearchQuery(contentPattern: 'needle'),
        ),
      );
      await open(tester);
      final choose = find.widgetWithText(
        OutlinedButton,
        'Use saved search criteria',
      );
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search file contents'));
      await tester.pumpAndSettle();
      expect(find.textContaining('content'), findsWidgets);
      expect(find.text('Clear saved criteria'), findsNothing);
      expect(cloud.uploads, isEmpty);
    },
  );

  testWidgets('snapshot override cannot authorize a move or omit its account', (
    tester,
  ) async {
    await open(
      tester,
      kind: FileOperationKind.move,
      sourceBackend: CloudOperationBackend(cloud, isCurrent: () => true),
    );
    expect(
      find.textContaining('requires its captured source account'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Preview'),
          )
          .onPressed,
      isNull,
    );
  });

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
    'unsupported preservation settings from defaults can be cleared',
    (tester) async {
      await FileOperationProfiles().save(
        '@default:copy',
        const FileOperationOptions(
          preservePermissions: true,
          preserveOwnership: true,
          preserveExtendedAttributes: true,
          preserveAcl: true,
          preserveWindowsAttributes: true,
        ),
      );
      await open(tester);
      await useCloudDestination(tester);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
        isNull,
      );
      expect(
        find.textContaining(
          'Some selected preservation settings are unavailable',
        ),
        findsOneWidget,
      );
      for (final label in [
        'Preserve permissions',
        'Preserve owner/group',
        'Preserve extended attributes',
        'Preserve ACL',
        'Preserve Windows attributes',
      ]) {
        final row = find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first;
        final checkbox = find.descendant(
          of: row,
          matching: find.byType(Checkbox),
        );
        expect(tester.widget<Checkbox>(checkbox).value, isTrue);
        expect(tester.widget<Checkbox>(checkbox).onChanged, isNotNull);
        await toggle(tester, label);
        expect(tester.widget<Checkbox>(checkbox).value, isFalse);
        expect(tester.widget<Checkbox>(checkbox).onChanged, isNull);
      }
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(start(FileOperationKind.copy)).onPressed,
        isNotNull,
      );
      expect(cloud.uploads, isEmpty);
      // Clearing incompatible settings for this job does not rewrite a profile.
      final defaults = (await FileOperationProfiles().load())['@default:copy']!;
      expect(defaults.preservePermissions, isTrue);
      expect(defaults.preserveOwnership, isTrue);
      expect(defaults.preserveExtendedAttributes, isTrue);
      expect(defaults.preserveAcl, isTrue);
      expect(defaults.preserveWindowsAttributes, isTrue);
    },
  );

  test('an unanswered background conflict is reported as incomplete', () async {
    cloud.files['/target/one.txt'] = utf8.encode('retain existing file');
    final backend = CloudOperationBackend(cloud, isCurrent: () => true);
    final plan = await const FileOperationService().prepare(
      files: files,
      source: backend,
      destination: backend,
      targetDirectory: '/target',
    );
    expect(plan.canExecute, isTrue);
    final transfers = container.read(transferProvider);
    await transfers
        .runFileOperation(plan, control: FileOperationControl())
        .timeout(const Duration(seconds: 5));
    final operation = transfers.operations.single;
    expect(operation.status, OperationStatus.waitingForDecision);
    expect(operation.error, isNull);
    expect(operation.isComplete, isFalse);
    expect(operation.failedFiles, 0);
    expect(plan.entries.first.outcome, FileOperationOutcome.needsDecision);
    expect(plan.entries.last.outcome, FileOperationOutcome.pending);
    expect(
      operation.files!.first.statusLabel,
      'Waiting for a conflict decision',
    );
    expect(
      operation.files!.last.statusLabel,
      'Not started (awaiting conflict decision)',
    );
    expect(operation.files!.every((file) => !file.isComplete), isTrue);
    expect(cloud.files['/target/one.txt'], utf8.encode('retain existing file'));
    expect(cloud.files.containsKey('/target/two.bin'), isFalse);
    expect(cloud.uploads, isEmpty);
    expect(cloud.deleted, isEmpty);
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
      await tester.enterText(
        find.byKey(const ValueKey('transfer-duplicate-name-template')),
        '{name}_copy-{counter:000}{ext}',
      );
      await tester.enterText(field('File filter'), '*.txt');
      await toggle(tester, 'Verify contents (SHA-256)');
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await runOperation(tester, FileOperationKind.copy);
      expect(cloud.files['/target/one.txt'], existing);
      expect(cloud.files['/target/one_copy-001.txt'], utf8.encode('one\n'));
      expect(cloud.files.containsKey('/target/two.bin'), isFalse);
      expect(cloud.files['/one.txt'], utf8.encode('one\n'));
      expect(cloud.reads, contains('/target/one_copy-001.txt'));
      expect(
        find.text('1 completed · 1 skipped/filtered · 0 failed'),
        findsOneWidget,
      );
      expect(container.read(transferProvider).operations.single.error, isNull);
    },
  );

  testWidgets(
    'Ask can queue in background and waits without failing or copying later rows',
    (tester) async {
      cloud.files['/target/one.txt'] = utf8.encode('existing');
      await open(tester, inRoute: true);
      await useCloudDestination(tester);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      final queue = find.byKey(const ValueKey('transfer-queue-background'));
      expect(tester.widget<TextButton>(queue).onPressed, isNotNull);
      await tester.tap(queue);
      await tester.pumpAndSettle();
      expect(find.byType(FileOperationDialog), findsNothing);
      final transfers = container.read(transferProvider);
      expect(
        transfers.operations.single.status,
        OperationStatus.waitingForDecision,
      );
      expect(transfers.operations.single.error, isNull);
      expect(transfers.hasActiveOperations, isFalse);
      expect(
        transfers.savedJobs.single.status,
        TransferJobStatus.waitingForDecision,
      );
      expect(cloud.files['/target/one.txt'], utf8.encode('existing'));
      expect(cloud.files.containsKey('/target/two.bin'), isFalse);
      expect(cloud.uploads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('background dialog stays open if saving the queued plan fails', (
    tester,
  ) async {
    final panel = container.read(panelProvider(PanelSide.remote));
    panel.toggleSelection(files.singleWhere((file) => file.path == '/one.txt'));
    panel.rememberSelection();
    panel.clearSelection();
    panel.toggleSelection(files.singleWhere((file) => file.path == '/two.bin'));
    files = panel.selection.toList();
    await open(tester, inRoute: true);
    await useCloudDestination(tester);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    journalStorage.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('transfer-queue-background')));
    await tester.pumpAndSettle();
    expect(find.byType(FileOperationDialog), findsOneWidget);
    expect(
      find.textContaining('Transfer history could not be saved'),
      findsOneWidget,
    );
    expect(cloud.uploads, isEmpty);
    expect(container.read(transferProvider).operations, isEmpty);
    panel.clearSelection();
    expect(panel.restoreSelection(), 1);
    expect(panel.selection.single.path, '/one.txt');
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate templates load, save and reject invalid defaults', (
    tester,
  ) async {
    await FileOperationProfiles().save(
      '@default:copy',
      const FileOperationOptions(
        duplicateNameTemplate: '{name}-backup{counter}{ext}',
      ),
    );
    await open(tester);
    final template = find.byKey(
      const ValueKey('transfer-duplicate-name-template'),
    );
    expect(
      tester.widget<TextField>(template).controller!.text,
      '{name}-backup{counter}{ext}',
    );
    await tester.enterText(template, '{name}_copy-{counter:000}{ext}');
    await tester.ensureVisible(find.text('Save as defaults'));
    await tester.tap(find.text('Save as defaults'));
    await tester.pumpAndSettle();
    expect(
      (await FileOperationProfiles().load())['@default:copy']!
          .duplicateNameTemplate,
      '{name}_copy-{counter:000}{ext}',
    );
    await tester.enterText(template, '../{counter}');
    await tester.ensureVisible(find.text('Save as defaults'));
    await tester.tap(find.text('Save as defaults'));
    await tester.pumpAndSettle();
    expect(
      (await FileOperationProfiles().load())['@default:copy']!
          .duplicateNameTemplate,
      '{name}_copy-{counter:000}{ext}',
    );
    expect(find.textContaining('FormatException'), findsOneWidget);
    expect(cloud.uploads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'client streaming rate loads and saves exact fractional KiB values',
    (tester) async {
      await FileOperationProfiles().save(
        '@default:copy',
        const FileOperationOptions(clientBytesPerSecond: 512),
      );
      await open(tester);
      final rate = find.byKey(const ValueKey('transfer-client-rate'));
      expect(tester.widget<TextField>(rate).controller!.text, '0.5');
      expect(
        find.text(
          'Limits bytes fed to the copy stream. Verification and native/server-side copies are not limited; buffered uploads may still burst.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(rate);
      await tester.enterText(rate, '1.25');
      await tester.ensureVisible(find.text('Save as defaults'));
      await tester.tap(find.text('Save as defaults'));
      await tester.pumpAndSettle();
      expect(
        (await FileOperationProfiles().load())['@default:copy']!
            .clientBytesPerSecond,
        1280,
      );
      await tester.ensureVisible(rate);
      await tester.enterText(rate, '0');
      await tester.ensureVisible(find.text('Save as defaults'));
      await tester.tap(find.text('Save as defaults'));
      await tester.pumpAndSettle();
      expect(
        (await FileOperationProfiles().load())['@default:copy']!
            .clientBytesPerSecond,
        1280,
      );
      expect(
        find.textContaining('positive client streaming rate'),
        findsOneWidget,
      );
      await tester.ensureVisible(rate);
      await tester.enterText(rate, '');
      await tester.ensureVisible(find.text('Save as defaults'));
      await tester.tap(find.text('Save as defaults'));
      await tester.pumpAndSettle();
      expect(
        (await FileOperationProfiles().load())['@default:copy']!
            .clientBytesPerSecond,
        isNull,
      );
      expect(cloud.uploads, isEmpty);
      expect(tester.takeException(), isNull);
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

  testWidgets(
    'move completion updates its saved list and preserves another storage same-path row',
    (tester) async {
      final panel = container.read(panelProvider(PanelSide.remote));
      panel.showSearchResults(
        files,
        origin: panel.captureOperationOrigin(files),
      );
      files = List<FileItem>.of(panel.files!);
      final originalTab = panel.activeTabId;
      String? localTab;
      cloud.beforeDelete = (path) async {
        if (path != '/one.txt') return;
        panel.addTab(path: '/');
        await panel.refresh();
        final localOrigin = container
            .read(panelProvider(PanelSide.local))
            .captureCurrentOrigin();
        panel.showSearchResults([
          FileItem(
            name: 'one.txt',
            path: '/one.txt',
            isFolder: false,
            size: 77,
          ),
        ], origin: localOrigin);
        panel.selectAll();
        localTab = panel.activeTabId;
      };
      await open(tester, kind: FileOperationKind.move);
      await useCloudDestination(tester);
      await tester.enterText(field('File filter'), '*.txt');
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await runOperation(tester, FileOperationKind.move);

      expect(cloud.deleted, ['/one.txt']);
      expect(cloud.files['/target/one.txt'], utf8.encode('one\n'));
      expect(panel.files!.single.path, '/one.txt');
      expect(panel.files!.single.size, 77);
      expect(panel.selection.single.path, '/one.txt');
      expect(panel.captureCurrentOrigin().source, isA<LocalPanelSource>());
      panel.selectTab(originalTab);
      expect(panel.files!.single.path, '/two.bin');
      panel.selectTab(localTab!);
      expect(panel.files!.single.path, '/one.txt');
      expect(panel.files!.single.size, 77);
      expect(container.read(transferProvider).operations.single.error, isNull);
    },
  );

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
