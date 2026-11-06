import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String? get grantedBasePath => '/';
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => true;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async =>
      initialDirectory;
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) async =>
      Uint8List(0);
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

class _Cloud extends Fake implements CloudStorageClient {
  @override
  bool get isAuthenticated => false;
  @override
  String get providerName => 'Test';
  @override
  String? get userId => null;
  @override
  String? get bucketId => null;
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final CloudStorageClient client = _Cloud();
  @override
  bool get isConnected => false;
  @override
  String? get userEmail => null;
  @override
  String get providerName => 'Test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('swapping pane views exchanges both directions', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [
        localFileServiceProvider.overrideWithValue(_Local()),
        authProvider.overrideWith((_) => _Auth()),
      ],
    );
    addTearDown(container.dispose);
    final left = container.read(panelProvider(PanelSide.local));
    final right = container.read(panelProvider(PanelSide.remote));

    await left.navigateToPath('/alpha');
    await right.navigateToPath('/beta');
    expect(left.currentPath, '/alpha');
    expect(right.currentPath, '/beta');

    left.swapViewWith(right);

    expect(left.currentPath, '/beta');
    expect(right.currentPath, '/alpha');
  });
}
