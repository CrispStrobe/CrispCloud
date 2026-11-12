// test/archive_viewer_integration_test.dart
//
// Regression coverage for viewing archive members through F3 and leaving
// archive mode when a real directory is opened.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/widgets/file_list_view.dart';
import 'package:crisp_cloud/providers/toolbar_provider.dart'
    show panelViewModeProvider;
import 'package:crisp_cloud/services/panel_view_mode_service.dart';

class _ArchiveFileService implements LocalFileService {
  _ArchiveFileService(this.zipPath, this.bytes);

  final String zipPath;
  Uint8List bytes;
  bool listPhysicalDirectory = false;

  @override
  String currentPath = Directory.systemTemp.path;

  @override
  String? get grantedBasePath => currentPath;

  @override
  Future<bool> ensureAccess(String path) async => true;

  @override
  Future<bool> beginStreamAccess(String path) async => true;

  @override
  Future<void> endStreamAccess() async {}

  @override
  Future<int?> fileLength(String path) async => bytes.length;

  @override
  Future<String> getInitialPath() async => currentPath;

  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;

  @override
  Future<bool> hasAccessToPath(String path) async => true;

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async =>
      listPhysicalDirectory
      ? Directory(path).list(followLinks: false).toList()
      : [File(zipPath)];

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async =>
      currentPath;

  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async => bytes;

  @override
  Future<void> saveFile(String path, Uint8List data) async {}

  @override
  Future<void> createDirectory(String path) async {}

  @override
  Future<void> deleteEntry(String path, bool isFolder) async {}

  @override
  Future<void> refresh() async {}

  @override
  Map<String, dynamic> getWebMetadata(String path) => {};

  @override
  Object? getWebFileRef(String path) => null;

  @override
  Future<List<FileItem>> walkFiles(
    String path, {
    bool includeHidden = false,
    int maxItems = 10000,
  }) async => const <FileItem>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String zipPath;
  late Uint8List zipBytes;
  late ProviderContainer container;
  late InMemorySecureStorage secureStorage;
  late FilenConfigService configService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
    tempDir = await Directory.systemTemp.createTemp('archive_viewer_');
    zipPath = p.join(tempDir.path, 'sample.zip');

    final archive = Archive()
      ..addFile(ArchiveFile('hello.txt', 5, [72, 101, 108, 108, 111]));
    zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    await File(zipPath).writeAsBytes(zipBytes);

    secureStorage = InMemorySecureStorage();
    configService = FilenConfigService(
      configPath: '/tmp/archive_viewer_test_config',
      secureStorage: secureStorage,
    );
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(secureStorage),
        configPathProvider.overrideWithValue('/tmp/archive_viewer_test_config'),
        localFileServiceProvider.overrideWithValue(
          _ArchiveFileService(zipPath, zipBytes),
        ),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref,
            initialProvider: CloudProvider.filen,
            config: configService,
            configPath: '/tmp/archive_viewer_test_config',
            secureStorage: secureStorage,
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await tempDir.delete(recursive: true);
  });

  for (final side in PanelSide.values) {
    for (final empty in [false, true]) {
      testWidgets(
        'leaving ${empty ? 'empty' : 'populated'} ZIP restores a visible selected row in ${side.name} pane',
        (tester) async {
          final local =
              container.read(localFileServiceProvider) as _ArchiveFileService;
          local.listPhysicalDirectory = true;
          local.currentPath = tempDir.path;
          late PanelNotifier panel;
          await tester.runAsync(() async {
            await Future.wait(
              List.generate(
                120,
                (index) => File(
                  p.join(
                    tempDir.path,
                    'a${index.toString().padLeft(3, '0')}.txt',
                  ),
                ).writeAsString(''),
              ),
            );
            if (empty) {
              local.bytes = Uint8List.fromList(ZipEncoder().encode(Archive()));
              await File(zipPath).writeAsBytes(local.bytes);
            }
            panel = container.read(panelProvider(side));
            await panel.navigateToPath(
              tempDir.path,
              origin: panel.captureLocalClipboardOrigin(tempDir.path),
            );
          });
          container.read(panelViewModeProvider(side).notifier).state =
              PanelViewMode.full;
          final scroll = ScrollController();
          addTearDown(scroll.dispose);
          Widget listing() => UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    key: const ValueKey('archive-return-viewport'),
                    width: 700,
                    height: 220,
                    child: Consumer(
                      builder: (context, ref, _) {
                        final current = ref.watch(panelProvider(side));
                        return FileListView(
                          side: side,
                          files: current.displayedFiles ?? [],
                          scrollController: scroll,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(listing());
          await tester.pumpAndSettle();
          final archive = panel.files!.firstWhere((row) => row.path == zipPath);
          panel.setCursorOnly(archive);
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(0));
          await tester.runAsync(() => panel.enterArchive(archive));
          await tester.pumpAndSettle();
          expect(panel.isInArchive, isTrue);
          // Loading/replacing the pane can detach its list before parent rows arrive.
          await tester.pumpWidget(const SizedBox.shrink());
          final parent = panel.files!.firstWhere((row) => row.name == '..');
          await tester.runAsync(() => panel.navigateInto(parent));
          expect(panel.isInArchive, isFalse);
          expect(panel.currentPath, tempDir.path);
          expect(panel.cursorItem?.path, zipPath);
          expect(panel.selection.map((row) => row.path), [zipPath]);
          await tester.pumpWidget(listing());
          await tester.pumpAndSettle();
          final tile = find.byWidgetPredicate(
            (widget) =>
                widget is CompactFileTile && widget.file.path == zipPath,
          );
          expect(tile, findsOneWidget);
          expect(tester.widget<CompactFileTile>(tile).isCursor, isTrue);
          expect(tester.widget<CompactFileTile>(tile).isSelected, isTrue);
          final viewport = tester.getRect(
            find.byKey(const ValueKey('archive-return-viewport')),
          );
          final row = tester.getRect(tile);
          expect(row.top, greaterThanOrEqualTo(viewport.top - 1));
          expect(row.bottom, lessThanOrEqualTo(viewport.bottom + 1));
          expect(scroll.offset, greaterThan(0));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  test('F3 can read a member from an opened archive', () async {
    final panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await panel.refresh();
    await panel.enterArchive(
      panel.files!.firstWhere((file) => file.path == zipPath),
    );

    expect(panel.isInArchive, isTrue);
    final member = panel.files!.firstWhere((f) => f.name == 'hello.txt');
    final bytes = await panel.readArchiveMember(member);
    expect(String.fromCharCodes(bytes), 'Hello');
  });

  test('nested navigation restores the parent directory and rejects stale or substituted members', () async {
    final inner = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('same.txt', 'inside'.codeUnits))
        ..addFile(ArchiveFile.bytes('folder/other.txt', [7])),
    );
    final outer = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('same.txt', 'outside'.codeUnits))
        ..addFile(ArchiveFile.bytes('nested/inner.zip', inner)),
    );
    await File(zipPath).writeAsBytes(outer);
    final panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await panel.refresh();
    await panel.enterArchive(
      panel.files!.firstWhere((file) => file.path == zipPath),
    );
    final staleOuter = panel.files!.firstWhere(
      (file) => file.name == 'same.txt',
    );
    await panel.navigateInto(
      panel.files!.firstWhere((file) => file.name == 'nested'),
    );
    final nested = panel.files!.singleWhere((file) => file.name == 'inner.zip');
    await panel.navigateInto(nested.copyWith());
    expect(panel.archiveSource!.archiveName, 'sample.zip');
    await panel.navigateInto(nested);
    expect(panel.archiveSource!.parent, isA<ArchivePanelSource>());
    expect(panel.currentPath, 'sample.zip!/nested/inner.zip:/');
    final current = panel.files!.firstWhere((file) => file.name == 'same.txt');
    expect(
      String.fromCharCodes(await panel.readArchiveMember(current)),
      'inside',
    );
    await expectLater(
      panel.readArchiveMember(staleOuter),
      throwsA(isA<ArchiveViewException>()),
    );
    await expectLater(
      panel.readArchiveMember(current.copyWith()),
      throwsA(isA<ArchiveViewException>()),
    );
    final location = panel.captureArchiveWorkspaceLocation();
    expect(location.file.path, zipPath);
    expect(location.nestedMembers, ['nested/inner.zip']);
    await panel.navigateUpArchive();
    expect(panel.archiveSource!.archiveName, 'sample.zip');
    expect(panel.archiveSource!.innerPath, 'nested/');
    expect(panel.cursorItem!.name, 'inner.zip');
    expect(location.isCurrent(), isFalse);
    await panel.navigateUpArchive();
    expect(panel.archiveSource!.innerPath, '');
    panel.exitArchive();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(panel.currentPath, tempDir.path);
  });

  test(
    'refresh after a nested workspace save opens the updated physical snapshot',
    () async {
      final inner = ZipEncoder().encode(
        Archive()..addFile(ArchiveFile.bytes('edit.txt', [1])),
      );
      await File(zipPath).writeAsBytes(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile.bytes('inner.zip', inner)),
        ),
      );
      final panel = container.read(panelProvider(PanelSide.local));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await panel.refresh();
      await panel.enterArchive(
        panel.files!.firstWhere((file) => file.path == zipPath),
      );
      await panel.navigateInto(
        panel.files!.singleWhere((file) => file.name == 'inner.zip'),
      );
      final stale = panel.files!.singleWhere((file) => file.name == 'edit.txt');
      final location = panel.captureArchiveWorkspaceLocation();
      final origin = panel.captureArchiveOrigin();
      final backend = fileOperationBackend(
        source: origin.source,
        local: container.read(localFileServiceProvider),
        isCurrent: () => origin.isCurrent,
      );
      final workspace = await ArchiveWorkspace.openNested(
        backend,
        location.file,
        location.nestedMembers,
        expectedOuterFingerprint: location.fingerprint,
      );
      workspace.replace('/edit.txt', Uint8List.fromList([2, 3]));
      await workspace.save();
      await workspace.close();
      await panel.refresh();
      expect(panel.archiveSource!.archiveName, 'inner.zip');
      expect(
        await panel.readArchiveMember(
          panel.files!.singleWhere((file) => file.name == 'edit.txt'),
        ),
        [2, 3],
      );
      await expectLater(
        panel.readArchiveMember(stale),
        throwsA(isA<ArchiveViewException>()),
      );
    },
  );

  test('repairs a path with the home directory appended twice', () async {
    final home = Platform.environment['HOME']!;
    final panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await panel.navigateToPath('${tempDir.path}$home/Downloads');

    expect(panel.currentPath, p.normalize('$home/Downloads'));
  });

  test('opening a real directory leaves archive mode', () async {
    final panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await panel.refresh();
    await panel.enterArchive(
      panel.files!.firstWhere((file) => file.path == zipPath),
    );
    expect(panel.isInArchive, isTrue);

    await panel.navigateToPath(tempDir.path);

    expect(panel.isInArchive, isFalse);
    expect(panel.currentPath, tempDir.path);
  });

  test(
    'a local archive in the right pane reads and returns to local storage',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(LocalPanelSource(tempDir.path));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final file = panel.files!.firstWhere((file) => file.path == zipPath);
      expect(panel.originForFile(file)!.source, isA<LocalPanelSource>());
      await panel.enterArchive(file);
      expect(panel.archiveSource!.parent, isA<LocalPanelSource>());
      final member = panel.files!.firstWhere(
        (file) => file.name == 'hello.txt',
      );
      expect(
        String.fromCharCodes(await panel.readArchiveMember(member)),
        'Hello',
      );
      await expectLater(
        panel.readArchiveMember(member, maxBytes: 4),
        throwsException,
      );
      panel.exitArchive();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(panel.isInArchive, isFalse);
      expect(panel.currentPath, tempDir.path);
      expect(panel.files!.any((file) => file.path == zipPath), isTrue);
    },
  );
}
