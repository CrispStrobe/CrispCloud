import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ListingGate {
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/';

  @override
  String? get grantedBasePath => '/';

  @override
  Future<String> getInitialPath() async => currentPath;

  @override
  Future<String> getSafeFallbackDirectory() async => '/';

  int refreshCalls = 0;
  final listedPaths = <String>[];
  _ListingGate? nextListing;

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    listedPaths.add(path);
    final gate = nextListing;
    nextListing = null;
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
    }
    return [];
  }
}

class _Cloud extends Fake implements CloudStorageClient {
  @override
  String? get userId => null;

  @override
  String? get bucketId => null;
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final client = _Cloud();

  @override
  bool get isConnected => false;

  @override
  String? get userEmail => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Local local;
  late ProviderContainer container;
  late PanelNotifier panel;
  var disposed = false;

  void disposeContainer() {
    if (disposed) return;
    disposed = true;
    container.dispose();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    disposed = false;
    local = _Local();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth()),
        localFileServiceProvider.overrideWithValue(local),
      ],
    );
    panel = container.read(panelProvider(PanelSide.local));
    await panel.refresh();
  });

  tearDown(disposeContainer);

  test('queued refresh stops after the panel is disposed', () async {
    final gate = _ListingGate();
    local.nextListing = gate;
    final activeRefresh = panel.refresh();
    await gate.entered.future;

    // The first listing owns the lock, so this request cannot start until the
    // gate is released. Disposal must be checked again when it gets the lock.
    final queuedRefresh = panel.refresh();
    final completion = expectLater(
      Future.wait([activeRefresh, queuedRefresh]),
      completes,
    );
    final listingsBeforeDisposal = List.of(local.listedPaths);
    final refreshesBeforeDisposal = local.refreshCalls;
    disposeContainer();
    gate.release.complete();

    await completion;
    expect(local.listedPaths, listingsBeforeDisposal);
    expect(local.refreshCalls, refreshesBeforeDisposal);
  });

  test('refresh called after disposal completes without I/O', () async {
    final listingsBeforeDisposal = List.of(local.listedPaths);
    final refreshesBeforeDisposal = local.refreshCalls;
    disposeContainer();

    await expectLater(panel.refresh(), completes);

    expect(local.listedPaths, listingsBeforeDisposal);
    expect(local.refreshCalls, refreshesBeforeDisposal);
  });

  test('closing an active tab leaves no unhandled refresh after disposal', () async {
    final originalTab = panel.activeTabId;
    panel.addTab(path: '/second');
    await panel.refresh();
    final closingTab = panel.activeTabId;

    final gate = _ListingGate();
    local.nextListing = gate;
    final activeRefresh = panel.refresh();
    await gate.entered.future;
    final uncaught = <Object>[];

    // closeTab -> selectTab intentionally starts an unawaited refresh. Keep
    // that request's asynchronous errors observable without relying on timing.
    runZonedGuarded<void>(
      () => panel.closeTab(closingTab),
      (error, _) => uncaught.add(error),
    );
    expect(panel.activeTabId, originalTab);
    expect(panel.tabs, hasLength(1));
    final listingsBeforeDisposal = List.of(local.listedPaths);
    final refreshesBeforeDisposal = local.refreshCalls;
    disposeContainer();
    gate.release.complete();

    await activeRefresh;
    // Drain queued lock continuations and their unhandled-error callbacks.
    await Future<void>.delayed(Duration.zero);

    expect(uncaught, isEmpty);
    expect(local.listedPaths, listingsBeforeDisposal);
    expect(local.refreshCalls, refreshesBeforeDisposal);
  });
}
