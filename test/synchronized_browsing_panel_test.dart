import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/synchronized_browsing_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/services/synchronized_browsing_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends CloudStorageClient {
  _Cloud(this.account, this.folder);
  final String account;
  final String folder;
  bool authenticated = true;
  final listed = <String>[];
  @override
  String get providerName => 'Test storage';
  @override
  String get userId => account;
  @override
  String get bucketId => 'bucket';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> logout() async {
    authenticated = false;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    listed.add(path);
    return {
      'files': <Map<String, Object>>[],
      'folders': [
        if (path == '/') {'name': folder, 'uuid': '$account-root'},
        if (path == '/$folder') {'name': 'a', 'uuid': '$account-a'},
        if (path == '/$folder/a') {'name': 'b', 'uuid': '$account-b'},
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => client.authenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => '${client.account}@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake
    implements LocalFileService, LocalDirectorySnapshotReader {
  Future<bool> Function(String)? access;
  Future<List<FileSystemEntity>?> Function(String)? snapshot;
  int accessRequests = 0;
  int ensureRequests = 0;
  @override
  String currentPath = '/';
  @override
  String get grantedBasePath => '/';
  @override
  Future<String> getInitialPath() async => '/';
  @override
  Future<String> getSafeFallbackDirectory() async => '/';
  @override
  Future<bool> hasAccessToPath(String path) async =>
      access == null ? true : await access!(path);
  @override
  Future<bool> ensureAccess(String path) async {
    ensureRequests++;
    return true;
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    accessRequests++;
    return initialDirectory;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async =>
      snapshot == null
      ? await Directory(path).list(followLinks: false).toList()
      : await snapshot!(path);
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Cloud a;
  late _Cloud b;
  late PanelNotifier left;
  late PanelNotifier right;
  late SynchronizedBrowsingService link;
  late _Local local;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    a = _Cloud('a', 'source');
    b = _Cloud('b', 'target');
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(a)),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'b',
          label: 'Second storage',
          provider: CloudProvider.s3,
          client: b,
        );
    left = container.read(panelProvider(PanelSide.local));
    right = container.read(panelProvider(PanelSide.remote));
    await left.refresh();
    await right.refresh();
    await left.navigateToPath(
      '/source',
      origin: left.resolveStorageReference(
        storageReferenceForClient(a),
        '/source',
      ),
    );
    await right.navigateToPath(
      '/target',
      origin: right.resolveStorageReference(
        storageReferenceForClient(b),
        '/target',
      ),
    );
    link = container.read(synchronizedBrowsingProvider);
  });
  tearDown(() => container.dispose());

  Future<Directory> localTarget() async {
    final directory = await Directory.systemTemp.createTemp('linked-race-');
    addTearDown(() => directory.delete(recursive: true));
    await Directory('${directory.path}/a').create();
    await Directory('${directory.path}/manual').create();
    await left.navigateToPath(
      directory.path,
      origin: left.captureLocalClipboardOrigin(directory.path),
    );
    return directory;
  }

  test('real panel navigation mirrors the original second account without moving focus', () async {
    container.read(activePanelProvider.notifier).state = PanelSide.local;
    expect(link.start(), isTrue);
    await left.navigateToPath('/source/a');
    await _settle();
    expect(right.currentPath, '/target/a');
    expect(
      (right.captureCurrentOrigin().source as RemotePanelSource).client,
      same(b),
    );
    expect(container.read(activePanelProvider), PanelSide.local);
    expect(link.enabled, isTrue);
    expect(link.busy, isFalse);
    await right.navigateToPath('/target/a/b');
    await _settle();
    expect(left.currentPath, '/source/a/b');
    expect(
      (left.captureCurrentOrigin().source as RemotePanelSource).client,
      same(a),
    );
  });

  test('missing counterpart does not attempt target navigation', () async {
    expect(link.start(), isTrue);
    await left.navigateToPath('/source/only-here');
    await _settle();
    expect(right.currentPath, '/target');
    expect(b.listed, isNot(contains('/target/only-here')));
    expect(link.issue, BrowsingLinkIssue.missingFolder);
  });

  test('account replacement with the same path stops the old link', () async {
    expect(link.start(), isTrue);
    await right.navigateToPath(
      '/target',
      origin: right.resolveStorageReference(
        storageReferenceForClient(a),
        '/target',
      ),
    );
    await _settle();
    expect(link.enabled, isFalse);
    expect(link.issue, BrowsingLinkIssue.changed);
    expect(left.currentPath, '/source');
  });

  test(
    'local source can mirror into a remote pane using real path checks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'linked-browsing-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await Directory('${directory.path}/a').create();
      await left.navigateToPath(
        directory.path,
        origin: left.captureLocalClipboardOrigin(directory.path),
      );
      expect(link.start(), isTrue);
      await right.navigateToPath('/target/a');
      await _settle();
      expect(left.currentPath, '${directory.path}/a');
      expect(left.captureCurrentOrigin().source, isA<LocalPanelSource>());
      expect(link.enabled, isTrue);
    },
  );

  test(
    'manual local intent wins before its access check changes the path',
    () async {
      final root = await localTarget();
      final checked = Completer<void>();
      final allowCheck = Completer<void>();
      final manualAccess = Completer<void>();
      final allowManual = Completer<void>();
      local.snapshot = (path) async {
        checked.complete();
        await allowCheck.future;
        return [];
      };
      local.access = (path) async {
        if (path.endsWith('/manual')) {
          manualAccess.complete();
          await allowManual.future;
        }
        return true;
      };
      expect(link.start(), isTrue);
      await right.navigateToPath('/target/a');
      await checked.future;
      final manual = left.navigateToPath('${root.path}/manual');
      await manualAccess.future;
      allowCheck.complete();
      await _settle();
      expect(left.currentPath, root.path);
      expect(link.enabled, isFalse);
      allowManual.complete();
      await manual;
      expect(left.currentPath, '${root.path}/manual');
    },
  );

  for (final cancelWithSourceNavigation in [false, true]) {
    test(
      'pending local follow is cancelled by ${cancelWithSourceNavigation ? 'source navigation' : 'stop'}',
      () async {
        final root = await localTarget();
        var reads = 0;
        final dispatched = Completer<void>();
        final allowNavigation = Completer<void>();
        local.snapshot = (path) async {
          if (++reads == 2) {
            dispatched.complete();
            await allowNavigation.future;
          }
          return [];
        };
        expect(link.start(), isTrue);
        await right.navigateToPath('/target/a');
        await dispatched.future;
        if (cancelWithSourceNavigation) {
          await right.navigateToPath('/target/a/b');
        } else {
          link.stop();
        }
        allowNavigation.complete();
        await _settle();
        expect(left.currentPath, root.path);
        expect(link.enabled, isFalse);
        expect(local.accessRequests, 0);
        expect(local.ensureRequests, 0);
      },
    );
  }

  test('denied linked access never requests a new folder grant', () async {
    final root = await localTarget();
    local.snapshot = (path) async =>
        throw PathAccessException(path, const OSError('Denied', 13));
    expect(link.start(), isTrue);
    await right.navigateToPath('/target/a');
    await _settle();
    expect(left.currentPath, root.path);
    expect(link.issue, BrowsingLinkIssue.failed);
    expect(local.accessRequests, 0);
    expect(local.ensureRequests, 0);
  });
}
