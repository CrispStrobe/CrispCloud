// test/archive_viewer_integration_test.dart
//
// Regression coverage for viewing archive members through F3 and leaving
// archive mode when a real directory is opened.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

class _ArchiveFileService implements LocalFileService {
  _ArchiveFileService(this.zipPath, this.bytes);

  final String zipPath;
  final Uint8List bytes;

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
  Future<List<FileSystemEntity>?> listDirectory(String path) async => const [];

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
  }) async =>
      const <FileItem>[];
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
    tempDir = await Directory.systemTemp.createTemp('archive_viewer_');
    zipPath = p.join(tempDir.path, 'sample.zip');

    final archive = Archive()
      ..addFile(ArchiveFile('hello.txt', 5, [72, 101, 108, 108, 111]));
    zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    await File(zipPath).writeAsBytes(zipBytes);

    secureStorage = InMemorySecureStorage();
    configService = FilenConfigService(
      configPath: '/tmp/archive_viewer_test_config',
      secureStorage: secureStorage,
    );
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(secureStorage),
      configPathProvider.overrideWithValue('/tmp/archive_viewer_test_config'),
      localFileServiceProvider.overrideWithValue(
        _ArchiveFileService(zipPath, zipBytes),
      ),
      authProvider.overrideWith((ref) => AuthNotifier(
            ref,
            initialProvider: CloudProvider.filen,
            config: configService,
            configPath: '/tmp/archive_viewer_test_config',
            secureStorage: secureStorage,
          )),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await tempDir.delete(recursive: true);
  });

  test('F3 can read a member from an opened archive', () async {
    final panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await panel.enterArchive(
      FileItem(name: 'sample.zip', path: zipPath, isFolder: false),
    );

    expect(panel.isInArchive, isTrue);
    final member = panel.files!.firstWhere((f) => f.name == 'hello.txt');
    final bytes = await panel.readArchiveMember(member);
    expect(String.fromCharCodes(bytes), 'Hello');
  });


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

    await panel.enterArchive(
      FileItem(name: 'sample.zip', path: zipPath, isFolder: false),
    );
    expect(panel.isInArchive, isTrue);

    await panel.navigateToPath(tempDir.path);

    expect(panel.isInArchive, isFalse);
    expect(panel.currentPath, tempDir.path);
  });
}
