import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/status_bar_strings.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/widgets/status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account) {
    put('/shared/one/file.txt', [1, 2, 3]);
    put('/shared/two/file.txt', [4]);
  }
  String account;
  final requests = <Completer<Map<String, int>?>>[];
  Completer<Map<String, dynamic>>? pendingListing;
  @override
  String get providerName => 'Shared storage';
  @override
  String get userId => account;
  @override
  String get rootPath => '/shared';
  @override
  Future<Map<String, dynamic>> listPath(String path) =>
      pendingListing?.future ?? super.listPath(path);
  @override
  Future<Map<String, int>?> getQuota() {
    final request = Completer<Map<String, int>?>();
    requests.add(request);
    return request.future;
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
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Transfers extends ChangeNotifier implements TransferNotifier {
  @override
  List<OperationProgress> get operations => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sync extends ChangeNotifier implements SyncNotifier {
  @override
  bool get isSyncing => false;
  @override
  SyncResult? get lastResult => null;
  @override
  List<SyncPair> get pairs => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  _Fixture() {
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => _Auth(primary)),
        localFileServiceProvider.overrideWithValue(_Local()),
        transferProvider.overrideWith((_) => _Transfers()),
        syncProvider.overrideWith((_) => _Sync()),
      ],
    );
    register(primary, 'first', 'First account');
    register(secondary, 'second', 'Second account');
  }

  final primary = _Cloud('first');
  final secondary = _Cloud('second');
  late final ProviderContainer container;

  void register(_Cloud client, String id, String label) => container
      .read(multiCloudProvider)
      .addConnection(
        id: id,
        label: label,
        provider: CloudProvider.s3,
        client: client,
      );

  Future<void> remote(
    WidgetTester tester,
    PanelSide side,
    _Cloud client, {
    String path = '/shared',
  }) async {
    final panel = container.read(panelProvider(side));
    container
        .read(panelSourceProvider(side).notifier)
        .setSource(
          RemotePanelSource(
            providerName: client.providerName,
            client: client,
            path: path,
          ),
        );
    await tester.runAsync(panel.refresh);
  }

  Future<void> local(WidgetTester tester, PanelSide side) async {
    final panel = container.read(panelProvider(side));
    const source = LocalPanelSource('/');
    final origin = panel.resolveStorageReference(
      storageReferenceForSource(source),
      source.currentPath,
    );
    expect(origin, isNotNull);
    // Match the header's explicit source choice even when its backing picker
    // already says Local while the legacy right-pane listing is still remote.
    await tester.runAsync(
      () => panel.navigateToPath(source.currentPath, origin: origin!),
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(bottomNavigationBar: StatusBar()),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'left secondary account owns quota; right local pane never borrows it',
    (tester) async {
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.secondary);
      await f.local(tester, PanelSide.remote);
      await f.mount(tester);
      expect(find.text('Second account (Shared storage)'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
      expect(f.primary.requests, isEmpty);
      expect(f.secondary.requests, hasLength(1));
      f.secondary.requests.single.complete({'used': 2048, 'total': 8192});
      await tester.pump();
      expect(find.text('2.0 KB / 8.0 KB'), findsOneWidget);
      expect(
        find.byTooltip('Second account (Shared storage)\n/shared\n/shared'),
        findsOneWidget,
      );

      f.container.read(activePanelProvider.notifier).state = PanelSide.remote;
      await tester.pump();
      expect(find.text('Local'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.text('2.0 KB / 8.0 KB'), findsNothing);
      expect(find.byKey(const ValueKey('status-quota-refresh')), findsNothing);
      expect(f.primary.requests, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    'same-provider account switch starts new quota without waiting for the old request',
    (tester) async {
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.primary);
      await f.remote(tester, PanelSide.remote, f.secondary);
      await f.mount(tester);
      expect(f.primary.requests, hasLength(1));
      f.container.read(activePanelProvider.notifier).state = PanelSide.remote;
      await tester.pump();
      expect(f.secondary.requests, hasLength(1));
      f.secondary.requests.single.complete({'used': 20, 'total': 200});
      await tester.pump();
      f.primary.requests.single.complete({'used': 99, 'total': 100});
      await tester.pump();
      expect(find.text('20 B / 200 B'), findsOneWidget);
      expect(find.text('99 B / 100 B'), findsNothing);
      expect(find.text('Second account (Shared storage)'), findsOneWidget);
      await f.close(tester);
    },
  );

  testWidgets(
    'duplicate live sessions keep the displayed client quota and label during navigation',
    (tester) async {
      final f = _Fixture();
      final secondSession = _Cloud('first');
      f.register(secondSession, 'first-session-2', 'Second session');
      expect(
        storageReferenceForClient(secondSession),
        storageReferenceForClient(f.primary),
      );
      await f.remote(tester, PanelSide.local, f.primary);
      await f.remote(tester, PanelSide.remote, secondSession);
      await f.mount(tester);
      expect(f.primary.requests, hasLength(1));
      expect(secondSession.requests, isEmpty);

      f.container.read(activePanelProvider.notifier).state = PanelSide.remote;
      await tester.pump();
      final panel = f.container.read(panelProvider(PanelSide.remote));
      expect(
        (panel.directoryPresentationOrigin!.source as RemotePanelSource).client,
        same(secondSession),
      );
      expect(secondSession.requests, hasLength(1));
      expect(find.text('Second session (Shared storage)'), findsOneWidget);
      secondSession.requests.single.complete({'used': 7, 'total': 70});
      await tester.pump();
      f.primary.requests.single.complete({'used': 9, 'total': 90});
      await tester.pump();
      expect(find.text('7 B / 70 B'), findsOneWidget);
      expect(find.text('9 B / 90 B'), findsNothing);

      final pending = Completer<Map<String, dynamic>>();
      secondSession.pendingListing = pending;
      final navigation = panel.navigateToPath('/shared/one');
      await tester.pump();
      expect(panel.isLoading, isTrue);
      expect(panel.hasVerifiedDirectoryListing, isFalse);
      expect(panel.directoryPresentationOrigin!.isCurrent, isTrue);
      expect(
        (panel.directoryPresentationOrigin!.source as RemotePanelSource).client,
        same(secondSession),
      );
      expect(find.text('7 B / 70 B'), findsOneWidget);
      expect(secondSession.requests, hasLength(1));
      expect(panel.captureCurrentOrigin, throwsStateError);

      pending.complete({'files': <dynamic>[], 'folders': <dynamic>[]});
      await navigation;
      secondSession.pendingListing = null;
      await tester.pump();
      expect(panel.hasVerifiedDirectoryListing, isTrue);
      expect(secondSession.requests, hasLength(1));
      expect(find.text('7 B / 70 B'), findsOneWidget);
      expect(
        find.byTooltip('Second session (Shared storage)\n/shared\n/shared/one'),
        findsOneWidget,
      );
      final original = panel.directoryPresentationOrigin!;
      await f.container
          .read(multiCloudProvider)
          .removeConnection('first-session-2');
      await tester.pump();
      expect(original.isCurrent, isFalse);
      expect(panel.directoryPresentationOrigin, same(original));
      expect(panel.directorySourceAvailable, isFalse);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.byKey(const ValueKey('status-quota-refresh')), findsNothing);
      expect(f.primary.requests, hasLength(1));
      await f.close(tester);
    },
  );

  testWidgets(
    'replacing a client for the same account discards the old session quota',
    (tester) async {
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.secondary);
      await f.mount(tester);
      final replacement = _Cloud('second');
      f.register(replacement, 'second', 'Second account');
      await f.remote(tester, PanelSide.local, replacement);
      await tester.pump();
      expect(replacement.requests, hasLength(1));
      replacement.requests.single.complete({'used': 7, 'total': 70});
      await tester.pump();
      f.secondary.requests.single.complete({'used': 8, 'total': 80});
      await tester.pump();
      expect(find.text('7 B / 70 B'), findsOneWidget);
      expect(find.text('8 B / 80 B'), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'unavailable original account cannot borrow a connected account quota',
    (tester) async {
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.secondary);
      await f.mount(tester);
      await f.container.read(multiCloudProvider).removeConnection('second');
      await tester.pump();
      f.secondary.requests.single.complete({'used': 8, 'total': 80});
      await tester.pump();
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('First account (Shared storage)'), findsNothing);
      expect(find.byKey(const ValueKey('status-quota-refresh')), findsNothing);
      expect(f.primary.requests, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets(
    'quota failure stays visible without request loops and retries explicitly',
    (tester) async {
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.secondary);
      await f.mount(tester);
      f.secondary.requests.single.completeError(StateError('offline'));
      await tester.pump();
      expect(find.text('Storage usage unavailable'), findsOneWidget);
      expect(
        find.byTooltip('Could not load storage usage. Retry.'),
        findsOneWidget,
      );
      await f.container
          .read(panelProvider(PanelSide.local))
          .navigateToPath('/shared/one');
      await tester.pump();
      expect(f.secondary.requests, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('status-quota-refresh')));
      await tester.pump();
      expect(f.secondary.requests, hasLength(2));
      f.secondary.requests.last.complete({'used': 0});
      await tester.pump();
      expect(find.text('0 B used'), findsOneWidget);
      expect(find.textContaining('/ 0 B'), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'search results stop quota ownership and exclude the parent row from counts',
    (tester) async {
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.secondary, path: '/shared/one');
      await f.mount(tester);
      expect(find.text('1 items'), findsOneWidget);
      final panel = f.container.read(panelProvider(PanelSide.local));
      panel.showSearchResults([
        FileItem(name: 'one.txt', path: '/shared/one/one.txt', isFolder: false),
      ]);
      await tester.pump();
      f.secondary.requests.single.complete({'used': 5, 'total': 50});
      await tester.pump();
      expect(find.text('Search results'), findsOneWidget);
      expect(find.text('5 B / 50 B'), findsNothing);
      expect(find.byKey(const ValueKey('status-quota-refresh')), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'selection bytes distinguish calculated folders and unknown sizes',
    (tester) async {
      final f = _Fixture();
      await f.local(tester, PanelSide.local);
      final panel = f.container.read(panelProvider(PanelSide.local));
      panel.showSearchResults([
        FileItem(
          name: 'known.txt',
          path: '/known.txt',
          isFolder: false,
          size: 10,
        ),
        FileItem(
          name: 'folder',
          path: '/folder',
          isFolder: true,
          size: 999,
          calculatedSize: 100,
        ),
        FileItem(name: 'unknown', path: '/unknown', isFolder: false, size: -1),
        FileItem(
          name: 'unmeasured folder',
          path: '/unmeasured',
          isFolder: true,
          size: 700,
        ),
      ]);
      panel.selectAll();
      await f.mount(tester);
      expect(find.text('4 selected (≥ 110 B)'), findsOneWidget);
      expect(f.primary.requests, isEmpty);
      expect(f.secondary.requests, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets('a quota completion after disposal has no widget callback', (
    tester,
  ) async {
    final f = _Fixture();
    await f.remote(tester, PanelSide.local, f.secondary);
    await f.mount(tester);
    await f.close(tester);
    f.secondary.requests.single.complete({'used': 9, 'total': 90});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final language in ['de', 'ar']) {
    testWidgets('narrow $language status with large text stays scrollable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _Fixture();
      await f.remote(tester, PanelSide.local, f.secondary);
      await f.mount(tester, locale: Locale(language), scale: 1.6);
      f.secondary.requests.single.complete(null);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          StatusBarStrings.forLanguage(language).text('quotaUnavailable'),
        ),
        findsOneWidget,
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-150, 0),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await f.close(tester);
    });
  }

  test(
    'status labels cover every supported locale and retain value placeholders',
    () {
      final catalog = StatusBarStrings.translations;
      final keys = catalog['en']!.keys.toSet();
      expect(
        catalog.keys.toSet(),
        AppLocalizations.supportedLocales
            .map((locale) => locale.languageCode)
            .toSet(),
      );
      for (final locale in catalog.entries) {
        expect(locale.value.keys.toSet(), keys);
        expect(
          locale.value.values.every((value) => value.trim().isNotEmpty),
          isTrue,
        );
        for (final key in ['quotaUsed', 'quotaTotal']) {
          expect(locale.value[key], contains('{value}'));
        }
      }
    },
  );
}
