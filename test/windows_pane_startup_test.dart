import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/models/panel_tab.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/panel_listing_placeholder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  _Local(this.currentPath);
  @override
  String currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<bool> hasAccessToPath(String path) => Directory(path).exists();
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) =>
      Directory(path).list(followLinks: false).toList();
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final WorkflowFakeClient client;
  @override
  bool get isConnected => client.current;
  @override
  String get providerName => client.providerName;
  @override
  String? get userEmail => isConnected ? 'windows@example.test' : null;
  void connect() {
    client.current = true;
    notifyListeners();
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Timed out waiting for panel startup');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory home;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier left;
  late PanelNotifier right;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    home = await Directory.systemTemp.createTemp('crisp-windows-home-');
    await File('${home.path}${Platform.pathSeparator}from-home.txt')
        .writeAsString('home');
    final cloud = WorkflowFakeClient()..current = false;
    cloud.put('/from-cloud.txt', [1]);
    auth = _Auth(cloud);
    container = ProviderContainer(overrides: [
      authProvider.overrideWith((_) => auth),
      localFileServiceProvider.overrideWithValue(_Local(home.path)),
    ]);
    left = container.read(panelProvider(PanelSide.local));
    right = container.read(panelProvider(PanelSide.remote));
    await until(() => left.hasVerifiedDirectoryListing &&
        panelListingState(right) == PanelListingState.disconnected);
  });

  tearDown(() async {
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
    await home.delete(recursive: true);
  });

  test('fresh Windows workspace has local Home on the left only', () {
    expect(left.currentPath, home.path);
    expect(left.directoryStorage?.isLocal, isTrue);
    expect(left.files!.any((file) => file.name == 'from-home.txt'), isTrue);
    expect(left.activeTab?.isCloudSetup, isFalse);
    expect(right.activeTab?.isCloudSetup, isTrue);
    expect(right.directoryStorage?.isLocal, isFalse);
    expect(right.files, isEmpty);
    expect(container.read(panelSourceProvider(PanelSide.remote)),
        isA<RemotePanelSource>());
  });

  test('connecting fills the right cloud pane without replacing local Home',
      () async {
    auth.connect();
    await until(() => right.hasVerifiedDirectoryListing &&
        right.files!.any((file) => file.name == 'from-cloud.txt'));
    expect(right.directoryStorage?.isLocal, isFalse);
    expect(right.activeTab?.isCloudSetup, isFalse);
    expect(left.currentPath, home.path);
    expect(left.directoryStorage?.isLocal, isTrue);
    expect(left.files!.any((file) => file.name == 'from-home.txt'), isTrue);
  });

  test('an explicit local choice on the right replaces the setup placeholder',
      () async {
    final origin = right.resolveStorageReference(
      storageReferenceForSource(LocalPanelSource(home.path)),
      home.path,
    )!;
    await right.navigateToPath(home.path, origin: origin);
    expect(right.hasVerifiedDirectoryListing, isTrue);
    expect(right.directoryStorage?.isLocal, isTrue);
    expect(right.activeTab?.isCloudSetup, isFalse);
    expect(right.currentPath, home.path);
  });

  test('only explicit setup tabs may reopen without storage identity', () {
    final setup = PanelTab(id: 'setup', path: '/', isCloudSetup: true);
    final restored = PanelTab.fromJson('restored', setup.toJson());
    expect(restored.storage, isNull);
    expect(restored.isCloudSetup, isTrue);
    final legacy = PanelTab.fromJson('legacy', {'path': '/old'});
    expect(legacy.isCloudSetup, isFalse);
    expect(legacy.storage, isNull);
  });
}
