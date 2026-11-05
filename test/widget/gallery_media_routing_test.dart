import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/gallery_media_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends Fake implements CloudStorageClient {
  _Cloud(this.providerName);
  @override
  final String providerName;
  @override
  String? get userId => 'account';
  @override
  String? get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  bool get supportsThumbnails => false;
  @override
  bool get supportsStreaming => false;
  @override
  Future<Map<String, dynamic>> listPath(String path) async => {
    'folders': <Map<String, dynamic>>[],
    'files': [{'name': 'photo.png', 'size': 3, 'uuid': 'one-image'}],
  };
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool isConnected = true;
  @override
  String? get userEmail => 'account@example.test';
  @override
  String get providerName => client.providerName;
  void reconnect() => notifyListeners();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService, LocalFileSourceIdentity {
  _Local(this.currentPath, this.file);
  @override
  String currentPath;
  final File file;
  Object rootToken = Object();
  @override
  String? get grantedBasePath => currentPath;
  @override
  Object? sourceIdentityForPath(String path) => rootToken;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [file];
  @override
  Future<void> refresh() async {}
  @override
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<bool> ensureAccess(String path) async => true;
  @override
  Future<int?> fileLength(String path) => file.length();
  @override
  Future<Uint8List> readFile(String path, {FileItem? fileItem}) => file.readAsBytes();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an unknown-revision cloud listing refresh invalidates only thumbnails', (tester) async {
    final cloud = _Cloud('SMB');
    final auth = _Auth(cloud);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((_) => auth),
    ]);
    addTearDown(container.dispose);
    late WidgetRef ref;
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: Consumer(builder: (_, value, __) { ref = value; return const SizedBox(); })));
    final panel = container.read(panelProvider(PanelSide.remote));
    await tester.runAsync(panel.refresh);
    final beforeFile = panel.files!.firstWhere((file) => !file.isFolder);
    expect(beforeFile.updatedAt, isNull);
    final before = captureGalleryMediaRequest(ref, PanelSide.remote, beforeFile);
    expect(before.isRemote, isTrue); // The dropdown still says Local by default.
    await tester.runAsync(panel.refresh);
    final after = captureGalleryMediaRequest(ref, PanelSide.remote,
        panel.files!.firstWhere((file) => !file.isFolder));
    expect(after.assetId, before.assetId);
    expect(after.revisionKey, isNot(before.revisionKey));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ambiguous endpoint reconnects cannot reuse a previous session namespace', (tester) async {
    final auth = _Auth(_Cloud('S3'));
    final container = ProviderContainer(overrides: [authProvider.overrideWith((_) => auth)]);
    addTearDown(container.dispose);
    late WidgetRef ref;
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: Consumer(builder: (_, value, __) { ref = value; return const SizedBox(); })));
    final panel = container.read(panelProvider(PanelSide.remote));
    await tester.runAsync(panel.refresh);
    final file = panel.files!.firstWhere((file) => !file.isFolder);
    final before = captureGalleryMediaRequest(ref, PanelSide.remote, file);
    auth.reconnect();
    await tester.pump();
    expect(before.isCurrent, isFalse);
    final after = captureGalleryMediaRequest(ref, PanelSide.remote, file);
    expect(after.namespaceId, isNot(before.namespaceId));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a same-path folder regrant changes catalog scope and invalidates old reads', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('gallery-root-')))!;
    final file = (await tester.runAsync(() => File('${dir.path}/photo.png').writeAsBytes([1, 2, 3])))!;
    addTearDown(() => dir.delete(recursive: true));
    final local = _Local(dir.path, file);
    final auth = _Auth(_Cloud('Google Drive'))..isConnected = false;
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((_) => auth),
      localFileServiceProvider.overrideWithValue(local),
    ]);
    addTearDown(container.dispose);
    late WidgetRef ref;
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: Consumer(builder: (_, value, __) { ref = value; return const SizedBox(); })));
    final panel = container.read(panelProvider(PanelSide.remote));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(LocalPanelSource(dir.path));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    final listed = panel.files!.firstWhere((file) => !file.isFolder);
    final before = captureGalleryMediaRequest(ref, PanelSide.remote, listed);
    expect(before.isRemote, isFalse);
    local.rootToken = Object();
    final after = captureGalleryMediaRequest(ref, PanelSide.remote, listed);
    expect(before.isCurrent, isFalse);
    expect(after.namespaceId, isNot(before.namespaceId));
    expect(after.assetId, isNot(before.assetId));
    await tester.pumpWidget(const SizedBox());
  });
}
