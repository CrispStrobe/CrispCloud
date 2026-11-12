import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/rename_batch_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  bool failDeletes = false;

  @override
  Future<void> deletePath(String path) async {
    if (failDeletes) throw StateError('Delete refused');
    await super.deletePath(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);

  @override
  final _Cloud client;
  @override
  bool get isConnected => client.current;
  @override
  String? userEmail = 'fixture@example.test';
  @override
  String get providerName => client.providerName;

  void connect(bool value) {
    client.current = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud cloud;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cloud = _Cloud()
      ..put('/a.txt', [1])
      ..put('/b.txt', [2]);
    auth = _Auth(cloud);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
        renameBatchStoreProvider.overrideWithValue(MemoryRenameBatchStore()),
      ],
    );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
  });
  tearDown(() => container.dispose());

  FileItem mark(String name) {
    panel.clearSelection();
    final file = panel.files!.singleWhere((row) => row.name == name);
    panel.toggleSelection(file);
    return file;
  }

  void expectRestore(String name) {
    panel.clearSelection();
    expect(panel.restoreSelection(), 1);
    expect(panel.selection.single.name, name);
  }

  test(
    'operation memory is delayed, captures original marks and publishes once',
    () {
      mark('a.txt');
      panel.rememberSelection();
      final operated = mark('b.txt');
      final accepted = panel.captureSelectionMemoryForOperation([operated]);
      expect(accepted, isNotNull);

      // Reviewing or cancelling has no effect on the preceding memory.
      expectRestore('a.txt');
      accepted!();
      expectRestore('b.txt');

      // A repeated queue notification cannot overwrite a later explicit memory.
      mark('a.txt');
      panel.rememberSelection();
      accepted();
      expectRestore('a.txt');
    },
  );

  test('cursor-only and unrelated rows do not replace a marked selection', () {
    mark('a.txt');
    panel.rememberSelection();
    panel.clearSelection();
    final file = panel.files!.first;
    expect(panel.captureSelectionMemoryForOperation([file]), isNull);
    mark('a.txt');
    expect(panel.captureSelectionMemoryForOperation([file.copyWith()]), isNull);
    expectRestore('a.txt');
  });

  test(
    'an accepted callback cannot replace memory after a listing refresh',
    () async {
      mark('a.txt');
      panel.rememberSelection();
      final accepted = panel.captureSelectionMemoryForOperation([
        mark('b.txt'),
      ])!;
      await panel.refresh();
      accepted();
      expectRestore('a.txt');
    },
  );

  test('an accepted callback cannot write into another tab', () async {
    mark('a.txt');
    panel.rememberSelection();
    final firstTab = panel.activeTabId;
    final accepted = panel.captureSelectionMemoryForOperation([mark('b.txt')])!;
    panel.addTab(path: '/');
    await panel.refresh();
    accepted();
    expect(panel.rememberedSelectionCount, 0);
    panel.selectTab(firstTab);
    await panel.refresh();
    expectRestore('a.txt');
  });

  test(
    'disconnecting and reconnecting invalidates a pending operation memory',
    () async {
      final accepted = panel.captureSelectionMemoryForOperation([
        mark('b.txt'),
      ])!;
      auth.connect(false);
      auth.connect(true);
      await panel.refresh();
      accepted();
      expect(panel.rememberedSelectionCount, 0);
      expect(panel.restorableSelectionCount, 0);
    },
  );

  test('failed deletion preserves the preceding selection memory', () async {
    mark('a.txt');
    panel.rememberSelection();
    final operated = mark('b.txt');
    cloud.failDeletes = true;
    expect(await panel.deleteFiles([operated], permanently: true), 0);
    expectRestore('a.txt');
    expect(cloud.files.containsKey('/b.txt'), isTrue);
  });

  test('successful deletion remembers original paths without selecting substitutes', () async {
    mark('a.txt');
    panel.rememberSelection();
    final operated = mark('b.txt');
    expect(await panel.deleteFiles([operated], permanently: true), 1);
    expect(panel.rememberedSelectionCount, 1);
    expect(panel.restoreSelection(), 0);
    expect(panel.selection, isEmpty);
    // The original location becomes available again after a restore.
    cloud.put('/b.txt', [2]);
    await panel.refresh();
    expectRestore('b.txt');
  });

  test('invalid rename preserves memory and successful rename remembers its original', () async {
    mark('a.txt');
    panel.rememberSelection();
    await panel.renameFile(mark('b.txt'), '../invalid');
    expectRestore('a.txt');
    await panel.renameFile(mark('b.txt'), 'renamed.txt');
    expect(cloud.files.containsKey('/renamed.txt'), isTrue);
    expect(panel.rememberedSelectionCount, 1);
    expect(panel.restoreSelection(), 0);
    expect(panel.selection, isEmpty);
    await cloud.renamePath('/renamed.txt', 'b.txt');
    await panel.refresh();
    expectRestore('b.txt');
  });
}
