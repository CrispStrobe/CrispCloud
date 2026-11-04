import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/directory_cache_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Local extends Fake implements LocalFileService {
  List<FileSystemEntity> entries = [];
  @override
  String currentPath = '/tmp';
  @override
  String? get grantedBasePath => '/tmp';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => entries;
  @override
  Future<void> refresh() async {}
}

class _Cloud extends Fake implements CloudStorageClient {
  _Cloud(this.providerName);
  @override
  final String providerName;
  @override
  String? get userId => 'account-a';
  @override
  String? get bucketId => 'bucket-a';
  @override
  String get rootPath => '/';
  bool authenticated = true;
  @override
  bool get isAuthenticated => authenticated;
  Completer<Map<String, dynamic>>? pending;
  final paths = <String>[];

  static Map<String, dynamic> get listing => {
    'folders': <Map<String, dynamic>>[],
    'files': [
      {'name': 'sample.pdf', 'size': 500, 'uuid': 'pdf-id'},
    ],
  };

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    paths.add(path);
    return pending == null ? listing : await pending!.future;
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool isConnected = true;
  @override
  String? userEmail = 'account-a@example.test';
  @override
  String get providerName => client.providerName;

  void connection(bool connected) {
    isConnected = connected;
    client.authenticated = connected;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud actual;
  late _Local local;
  late _Auth auth;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    actual = _Cloud('Actual provider');
    local = _Local();
    auth = _Auth(actual);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
  });

  tearDown(() => container.dispose());

  test(
    'native metadata publication records the exact local file origin',
    () async {
      final directory = await Directory.systemTemp.createTemp('pdf-origin-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/sample.pdf')
          .writeAsString('pdf');
      local.entries = [file];
      final panel = container.read(panelProvider(PanelSide.local));
      await panel.refresh();
      final listed = panel.files!.firstWhere((item) => !item.isFolder);
      expect(listed.path, file.path);
      expect(panel.originForFile(listed)!.source, isA<LocalPanelSource>());
      panel.toggleSelection(listed);
      await panel.refresh();
      final refreshed = panel.files!.firstWhere((item) => !item.isFolder);
      expect(refreshed, isNot(same(listed)));
      expect(panel.selection.single, same(refreshed));
      expect(panel.originForFile(panel.selection.single), isNotNull);
      expect(panel.originForFile(listed), isNull);
    },
  );

  test(
    'default local dropdown does not relabel an actual remote listing',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        isA<LocalPanelSource>(),
      );
      await panel.refresh();
      final file = panel.files!.single;
      final origin = panel.originForFile(file)!;
      expect(origin.source, isA<RemotePanelSource>());
      expect((origin.source as RemotePanelSource).client, same(actual));
      expect(origin.source.currentPath, '/');
      expect(origin.isCurrent, isTrue);
      expect(panel.originForFile(file.copyWith()), isNull);
    },
  );

  for (final side in PanelSide.values) {
    test(
      'remote origin in ${side.name} pane is the actual request client',
      () async {
        final panel = container.read(panelProvider(side));
        await Future<void>.delayed(Duration.zero);
        final other = _Cloud('Dropdown provider');
        container
            .read(panelSourceProvider(side).notifier)
            .setSource(
              RemotePanelSource(
                providerName: other.providerName,
                client: other,
                path: '/documents',
              ),
            );
        await Future<void>.delayed(Duration.zero);
        final file = panel.files!.firstWhere((file) => !file.isFolder);
        final origin = panel.originForFile(file)!;
        expect((origin.source as RemotePanelSource).client, same(actual));
        expect(origin.source.currentPath, '/documents');
        expect(actual.paths.last, '/documents');
        expect(other.paths, isEmpty);
      },
    );
  }

  test(
    'disconnect invalidates captured origin even after the same login returns',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final file = panel.files!.single;
      final origin = panel.originForFile(file)!;
      auth.connection(false);
      auth.connection(true);
      expect(origin.isCurrent, isFalse);
      expect(panel.originForFile(file), isNull);
    },
  );

  test(
    'refresh rebinds preview selection to the fresh verified file object',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final old = panel.files!.single;
      panel.toggleSelection(old);
      panel.setCursorToItem(old);
      await panel.refresh();
      final current = panel.files!.single;
      expect(current, isNot(same(old)));
      expect(panel.selection.single, same(current));
      expect(panel.lastSelected, same(current));
      expect(panel.itemToScrollTo, same(current));
      expect(panel.originForFile(panel.selection.single), isNotNull);
      expect(panel.originForFile(old), isNull);
    },
  );

  test(
    'same identifiers after reconnect do not inherit old selection',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final old = panel.files!.single;
      panel.toggleSelection(old);
      auth.connection(false);
      auth.connection(true);
      await panel.refresh();
      expect(panel.files!.single.uuid, old.uuid);
      expect(panel.selection, isEmpty);
      expect(panel.lastSelected, isNull);
      expect(panel.originForFile(old), isNull);
      expect(panel.originForFile(panel.files!.single), isNotNull);
    },
  );

  test(
    'same identifiers in another directory do not inherit selection',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final old = panel.files!.single;
      panel.toggleSelection(old);
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(
            RemotePanelSource(
              providerName: actual.providerName,
              client: actual,
              path: '/elsewhere',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(
        panel.files!.where((file) => !file.isFolder).single.uuid,
        old.uuid,
      );
      expect(panel.selection, isEmpty);
      expect(panel.lastSelected, isNull);
      expect(panel.originForFile(old), isNull);
    },
  );

  test(
    'account changes during listing cannot publish an editable result',
    () async {
      final request = Completer<Map<String, dynamic>>();
      actual.pending = request;
      final panel = container.read(panelProvider(PanelSide.remote));
      final loading = panel.refresh();
      await Future<void>.delayed(Duration.zero);
      auth.connection(false);
      auth.connection(true);
      request.complete(_Cloud.listing);
      await loading;
      expect(panel.files ?? [], isEmpty);
    },
  );

  test(
    'a stale remote response cannot replace a newer local listing',
    () async {
      final request = Completer<Map<String, dynamic>>();
      actual.pending = request;
      final panel = container.read(panelProvider(PanelSide.remote));
      final loading = panel.refresh();
      await Future<void>.delayed(Duration.zero);
      container
          .read(panelSourceProvider(PanelSide.remote).notifier)
          .setSource(const LocalPanelSource('/tmp'));
      await Future<void>.delayed(Duration.zero);
      request.complete(_Cloud.listing);
      await loading;
      expect(panel.files!.any((file) => file.name == 'sample.pdf'), isFalse);
    },
  );

  test(
    'unverified account-shared cache entries stay uneditable after failure',
    () async {
      final cached = FileItem(
        name: 'sample.pdf',
        isFolder: false,
        uuid: 'pdf-id',
      );
      container.read(directoryCacheProvider).put(
        DirectoryCacheService.key('remote:${actual.providerName}', '/'),
        [cached],
      );
      final request = Completer<Map<String, dynamic>>();
      actual.pending = request;
      final panel = container.read(panelProvider(PanelSide.remote));
      final loading = panel.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(panel.files!.single, same(cached));
      expect(panel.originForFile(cached), isNull);
      request.completeError(StateError('offline'));
      await loading;
      expect(panel.originForFile(cached), isNull);
    },
  );

  test(
    'search results cannot inherit a verified identity from a listing',
    () async {
      final panel = container.read(panelProvider(PanelSide.remote));
      await panel.refresh();
      final file = panel.files!.single;
      expect(panel.originForFile(file), isNotNull);
      panel.showSearchResults([file]);
      expect(panel.originForFile(file), isNull);
    },
  );

  test('metadata replacement preserves the exact listed file origin', () async {
    final panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    final original = panel.files!.single;
    final origin = panel.originForFile(original);
    panel.toggleSelection(original);
    panel.updateItemCalculatedSize(original, 1234);
    final replacement = panel.files!.single;
    expect(replacement, isNot(same(original)));
    expect(panel.originForFile(replacement), same(origin));
    expect(panel.originForFile(original), isNull);
    expect(panel.selection.single, same(replacement));
    expect(panel.lastSelected, same(replacement));
  });
}
