import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  final listings = <String, Completer<Map<String, dynamic>>>{};

  @override
  Future<Map<String, dynamic>> listPath(String path) =>
      listings[path]?.future ?? super.listPath(path);
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
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake
    implements LocalFileService, LocalDirectorySnapshotReader {
  _Local(this.currentPath);
  @override
  String currentPath;
  @override
  String get grantedBasePath => p.dirname(currentPath);
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async {
    fallbackRequests++;
    return currentPath;
  }

  final interactiveReads = <String>[];
  final snapshotReads = <String>[];
  final accessReads = <String>[];
  final accessDelays = <String, Completer<bool>>{};
  final snapshotDelays = <String, Completer<List<FileSystemEntity>?>>{};
  final snapshotFailures = <String, FileSystemException>{};
  int grantRequests = 0, ensureRequests = 0, fallbackRequests = 0;
  bool accessible = true;

  @override
  Future<bool> hasAccessToPath(String path) async {
    accessReads.add(path);
    return await accessDelays[path]?.future ?? accessible;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    grantRequests++;
    accessible = true;
    return initialDirectory;
  }

  @override
  Future<bool> ensureAccess(String path) async {
    ensureRequests++;
    return accessible;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    interactiveReads.add(path);
    return Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async {
    snapshotReads.add(path);
    if (snapshotFailures[path] case final failure?) throw failure;
    return snapshotDelays[path]?.future ??
        Directory(path).list(followLinks: false).toList();
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String currentPath, targetPath, manualPath;
  late _Local local;
  late _Cloud cloud;
  late ProviderContainer container;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('guarded-navigation-');
    currentPath = p.join(root.path, 'current');
    targetPath = p.join(root.path, 'target');
    manualPath = p.join(root.path, 'manual');
    for (final path in [currentPath, targetPath, manualPath]) {
      await Directory(path).create();
      await File(p.join(path, '${p.basename(path)}.txt')).writeAsString(path);
    }
    local = _Local(currentPath);
    cloud = _Cloud()..put('/original.txt', [1]);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(cloud)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    panel = container.read(panelProvider(PanelSide.local));
    await Future<void>.delayed(Duration.zero);
    await panel.navigateToPath(
      currentPath,
      origin: panel.captureLocalClipboardOrigin(currentPath),
    );
    expect(panel.currentPath, currentPath);
    local.interactiveReads.clear();
    local.snapshotReads.clear();
    local.accessReads.clear();
    local.grantRequests = 0;
    local.ensureRequests = 0;
    local.fallbackRequests = 0;
  });

  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });

  test('noninteractive navigation uses its captured snapshot without access prompts', () async {
    await panel.navigateToPath(targetPath, allowAccessRequests: false);
    expect(panel.currentPath, targetPath);
    expect(panel.hasVerifiedDirectoryListing, isTrue);
    expect(
      panel.files!.where((row) => row.name != '..').single.name,
      'target.txt',
    );
    expect(local.snapshotReads, [targetPath]);
    expect(local.interactiveReads, isEmpty);
    expect(local.accessReads, isEmpty);
    expect(local.ensureRequests, 0);
    expect(local.grantRequests, 0);
  });

  for (final missing in [false, true]) {
    test(
      'noninteractive ${missing ? 'missing' : 'denied'} folder preserves the current view',
      () async {
        panel.selectAll();
        final selected = panel.selection.single;
        local.snapshotFailures[targetPath] = missing
            ? PathNotFoundException(targetPath, const OSError('Missing', 2))
            : PathAccessException(
                targetPath,
                const OSError('Access denied', 13),
              );
        await expectLater(
          panel.navigateToPath(targetPath, allowAccessRequests: false),
          throwsA(isA<FileSystemException>()),
        );
        expect(panel.currentPath, currentPath);
        expect(panel.hasVerifiedDirectoryListing, isTrue);
        expect(panel.selection.single, same(selected));
        expect(local.interactiveReads, isEmpty);
        expect(local.ensureRequests, 0);
        expect(local.grantRequests, 0);
        expect(local.fallbackRequests, 0);
      },
    );
  }

  test('a rejected continuation does not accept a navigation intent', () async {
    final revision = panel.navigationIntentRevision;
    await panel.navigateToPath(
      targetPath,
      allowAccessRequests: false,
      canContinue: () => false,
    );
    expect(panel.navigationIntentRevision, revision);
    expect(panel.currentPath, currentPath);
    expect(local.snapshotReads, isEmpty);
  });

  test(
    'cancellation during a snapshot cannot change the visible path or marks',
    () async {
      panel.selectAll();
      final selected = panel.selection.single;
      final read = Completer<List<FileSystemEntity>?>();
      local.snapshotDelays[targetPath] = read;
      var current = true;
      final navigation = panel.navigateToPath(
        targetPath,
        allowAccessRequests: false,
        canContinue: () => current,
      );
      expect(local.snapshotReads, [targetPath]);
      current = false;
      read.complete([File(p.join(targetPath, 'target.txt'))]);
      await navigation;
      expect(panel.currentPath, currentPath);
      expect(panel.selection.single, same(selected));
      expect(panel.hasVerifiedDirectoryListing, isTrue);
      expect(local.interactiveReads, isEmpty);
    },
  );

  test(
    'newer manual navigation wins over a pending noninteractive snapshot',
    () async {
      final read = Completer<List<FileSystemEntity>?>();
      local.snapshotDelays[targetPath] = read;
      final pending = panel.navigateToPath(
        targetPath,
        allowAccessRequests: false,
      );
      final linkedRevision = panel.navigationIntentRevision;
      await panel.navigateToPath(manualPath);
      expect(panel.navigationIntentRevision, greaterThan(linkedRevision));
      read.complete([File(p.join(targetPath, 'target.txt'))]);
      await pending;
      expect(panel.currentPath, manualPath);
      expect(
        panel.files!.where((row) => row.name != '..').single.name,
        'manual.txt',
      );
      expect(panel.hasVerifiedDirectoryListing, isTrue);
    },
  );

  test(
    'the intent revision changes before a manual access check finishes',
    () async {
      final access = Completer<bool>();
      local.accessDelays[manualPath] = access;
      final revision = panel.navigationIntentRevision;
      final pending = panel.navigateToPath(manualPath);
      expect(panel.navigationIntentRevision, greaterThan(revision));
      expect(panel.currentPath, currentPath);
      access.complete(true);
      await pending;
      expect(panel.currentPath, manualPath);
    },
  );

  test('manual navigation keeps its existing explicit grant flow', () async {
    local.accessible = false;
    await panel.navigateToPath(manualPath);
    expect(local.grantRequests, 1);
    expect(local.snapshotReads, isEmpty);
    expect(local.interactiveReads, [manualPath]);
    expect(panel.currentPath, manualPath);
    expect(panel.hasVerifiedDirectoryListing, isTrue);
  });

  test('a cancelled remote listing cannot publish its delayed rows', () async {
    final remote = container.read(panelProvider(PanelSide.remote));
    await remote.refresh();
    final listing = Completer<Map<String, dynamic>>();
    cloud.listings['/delayed'] = listing;
    var current = true;
    final pending = remote.navigateToPath(
      '/delayed',
      allowAccessRequests: false,
      canContinue: () => current,
    );
    expect(remote.isLoading, isTrue);
    current = false;
    listing.complete({
      'files': [
        {'name': 'stale.txt', 'size': 1},
      ],
      'folders': <Map<String, Object>>[],
    });
    await pending;
    expect(remote.files!.any((row) => row.name == 'stale.txt'), isFalse);
    expect(remote.hasVerifiedDirectoryListing, isFalse);
    expect(remote.isLoading, isFalse);
  });
}
