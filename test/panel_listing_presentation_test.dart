import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/workflow_fake_client.dart';

class _ReadGate {
  final started = Completer<void>();
  final released = Completer<void>();
  void release() {
    if (!released.isCompleted) released.complete();
  }
}

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account) {
    put('/initial.txt', [1]);
    for (final path in ['/broken', '/slow', '/shared', '/healthy']) {
      put('$path/$account.txt', [1, 2, 3]);
    }
  }

  final String account;
  final requests = <String>[];
  final failures = <String>{};
  final gates = <String, _ReadGate>{};

  @override
  String get providerName => 'Presentation storage';
  @override
  String get userId => account;
  @override
  String get bucketId => 'presentation-bucket';

  _ReadGate pause(String path) {
    final gate = _ReadGate();
    gates[path] = gate;
    return gate;
  }

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    requests.add(path);
    final gate = gates[path];
    if (gate != null) {
      if (!gate.started.isCompleted) gate.started.complete();
      await gate.released.future;
    }
    if (failures.contains(path)) {
      throw StateError('$account listing failed: $path');
    }
    return super.listPath(path);
  }
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => client.current;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => '${client.account}@example.test';

  void disconnect() {
    client.current = false;
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
  Future<bool> hasAccessToPath(String path) async => true;
  @override
  Future<List<FileSystemEntity>> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Cloud primary;
  late _Cloud secondary;
  late _Auth auth;
  late ProviderContainer container;
  late PanelNotifier panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    primary = _Cloud('primary');
    secondary = _Cloud('secondary');
    auth = _Auth(primary);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    container
        .read(multiCloudProvider)
        .addConnection(
          id: 'secondary',
          label: 'Secondary account',
          provider: CloudProvider.s3,
          client: secondary,
        );
    panel = container.read(panelProvider(PanelSide.remote));
    await panel.refresh();
    expect(panel.hasVerifiedDirectoryListing, isTrue);
  });

  tearDown(() => container.dispose());

  for (final pending in [false, true]) {
    test(
      'an offline restored tab does not inherit a ${pending ? 'pending' : 'failed'} listing',
      () async {
        final originalTab = panel.activeTabId;
        final path = pending ? '/slow' : '/broken';
        primary.failures.add(path);
        final gate = pending ? primary.pause(path) : null;
        if (gate != null) addTearDown(gate.release);
        final previousRequest = panel.navigateToPath(path);
        if (gate == null) {
          await previousRequest;
          expect(panel.directoryListingError?.message, contains(path));
        } else {
          await gate.started.future;
          expect(panel.isLoading, isTrue);
        }
        expect(panel.directoryStorage, storageReferenceForClient(primary));

        secondary.current = false;
        final storage = storageReferenceForClient(secondary);
        final primaryReads = primary.requests.length;
        await panel.restoreTabs([
          {'path': '/private', 'storage': storage.toJson()},
        ]);
        final restoredTab = panel.activeTabId;
        expect(restoredTab, isNot(originalTab));

        void expectUnavailableOriginal() {
          expect(panel.activeTabId, restoredTab);
          expect(panel.currentPath, '/private');
          expect(panel.directoryStorage, storage);
          expect(panel.directorySource, isNull);
          expect(panel.directorySourceAvailable, isFalse);
          expect(panel.hasVerifiedDirectoryListing, isFalse);
          expect(panel.directoryListingError, isNull);
          expect(panel.isLoading, isFalse);
          expect(panel.files, isEmpty);
          expect(primary.requests.length, primaryReads);
        }

        expectUnavailableOriginal();
        if (gate != null) {
          gate.release();
          await previousRequest;
          expectUnavailableOriginal();
          expect(
            container
                .read(errorProvider)
                .errors
                .any(
                  (error) =>
                      error.message.contains('primary listing failed: /slow'),
                ),
            isFalse,
          );
        }
      },
    );
  }

  test(
    'a stale failure cannot replace another account at the same path',
    () async {
      primary.failures.add('/shared');
      final gate = primary.pause('/shared');
      addTearDown(gate.release);
      final previousRequest = panel.navigateToPath('/shared');
      await gate.started.future;
      expect(panel.isLoading, isTrue);
      expect(panel.directoryStorage, storageReferenceForClient(primary));
      expect(panel.directoryListingError, isNull);

      final storage = storageReferenceForClient(secondary);
      await panel.navigateToPath(
        '/shared',
        origin: panel.resolveStorageReference(storage, '/shared')!,
      );
      final successfulRows = panel.files;
      final published = panel.files!.singleWhere(
        (file) => file.name == 'secondary.txt',
      );
      gate.release();
      await previousRequest;

      expect(panel.currentPath, '/shared');
      expect(panel.directoryStorage, storage);
      expect(
        (panel.directorySource as RemotePanelSource).client,
        same(secondary),
      );
      expect(panel.directorySourceAvailable, isTrue);
      expect(panel.hasVerifiedDirectoryListing, isTrue);
      expect(panel.directoryListingError, isNull);
      expect(panel.isLoading, isFalse);
      expect(panel.files, same(successfulRows));
      expect(panel.originForOperation(published)?.storageReference, storage);
      expect(container.read(errorProvider).hasErrors, isFalse);
    },
  );

  test(
    'another pane clearing global errors retains the owning directory failure',
    () async {
      final other = container.read(panelProvider(PanelSide.local));
      final storage = storageReferenceForClient(secondary);
      await other.navigateToPath(
        '/healthy',
        origin: other.resolveStorageReference(storage, '/healthy')!,
      );
      primary.failures.add('/broken');
      await panel.navigateToPath('/broken');
      final failure = panel.directoryListingError;
      expect(failure, isNotNull);
      expect(failure!.message, contains('primary listing failed: /broken'));
      expect(container.read(errorProvider).hasErrors, isTrue);

      await other.refresh();
      expect(container.read(errorProvider).hasErrors, isFalse);
      expect(other.directoryListingError, isNull);
      expect(other.hasVerifiedDirectoryListing, isTrue);
      expect(panel.directoryListingError, same(failure));
      expect(panel.directoryStorage, storageReferenceForClient(primary));
      expect(panel.directorySourceAvailable, isTrue);
      expect(panel.hasVerifiedDirectoryListing, isFalse);

      primary.failures.remove('/broken');
      await panel.refresh();
      expect(panel.directoryListingError, isNull);
      expect(panel.hasVerifiedDirectoryListing, isTrue);
    },
  );

  test(
    'a connected secondary source remains available after primary disconnect',
    () async {
      auth.disconnect();
      expect(auth.isConnected, isFalse);
      final storage = storageReferenceForClient(secondary);
      await panel.navigateToPath(
        '/shared',
        origin: panel.resolveStorageReference(storage, '/shared')!,
      );
      expect(panel.directoryStorage, storage);
      expect(
        (panel.directorySource as RemotePanelSource).client,
        same(secondary),
      );
      expect(panel.directorySourceAvailable, isTrue);
      expect(panel.hasVerifiedDirectoryListing, isTrue);
      expect(panel.directoryListingError, isNull);
      expect(panel.isLoading, isFalse);
      expect(panel.files!.any((file) => file.name == 'secondary.txt'), isTrue);
      expect(primary.requests, isNot(contains('/shared')));
    },
  );
}
