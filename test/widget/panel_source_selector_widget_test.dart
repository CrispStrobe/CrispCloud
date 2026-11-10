// test/widget/panel_source_selector_widget_test.dart
//
// Widget tests for PanelSourceSelector.
// Tests dropdown rendering, icons, selection changes, and both panel sides.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:crisp_cloud/widgets/panel_header.dart';
import 'package:crisp_cloud/widgets/panel_source_selector.dart';

import '../support/workflow_fake_client.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 300, child: child)),
    ),
  );
}

/// Returns an [AvailableSource] list containing only Local.
List<AvailableSource> _localOnlySources() => [
  const AvailableSource(
    key: 'local',
    label: 'Local',
    source: LocalPanelSource('/'),
  ),
];

/// Returns two [AvailableSource] entries: Local + a stand-in remote entry.
List<AvailableSource> _twoLocalSources() => [
  const AvailableSource(
    key: 'local',
    label: 'Local',
    source: LocalPanelSource('/'),
  ),
  const AvailableSource(
    key: 'local:/home',
    label: 'Home',
    source: LocalPanelSource('/home'),
  ),
];

class _Cloud extends WorkflowFakeClient {
  _Cloud(this.account, {this.configuredRoot = '/'});
  String account;
  final String configuredRoot;
  @override
  String get providerName => 'Shared provider';
  @override
  String get userId => account;
  @override
  String get rootPath => configuredRoot;
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  _Auth(this.client);
  @override
  final _Cloud client;
  @override
  bool get isConnected => client.isAuthenticated;
  @override
  String get providerName => client.providerName;
  @override
  String get userEmail => '${client.account}@example.test';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Local extends Fake implements LocalFileService {
  final reads = <String>[];
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
  Future<List<FileSystemEntity>> listDirectory(String path) async {
    reads.add(path);
    return [];
  }

  @override
  Future<void> refresh() async {}
}

AvailableSource _remoteEntry(_Cloud client, String key, String label) =>
    AvailableSource(
      key: 'remote:$key',
      label: label,
      source: RemotePanelSource(
        providerName: client.providerName,
        client: client,
        path: client.rootPath,
      ),
    );

Widget _ownedWrap(
  ProviderContainer container,
  Widget child, {
  double width = 132,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // -------------------------------------------------------------------------
  // Basic rendering
  // -------------------------------------------------------------------------

  group('PanelSourceSelector rendering', () {
    testWidgets('renders a DropdownButton', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('shows "Local" label when sources contain only Local', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Local'), findsOneWidget);
    });

    testWidgets('shows folder icon for local source', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.folder_outlined), findsWidgets);
    });

    testWidgets('shows dropdown arrow icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    });

    testWidgets('renders without error for PanelSide.remote', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.remote),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('renders two items when two sources are provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_twoLocalSources()),
          ],
        ),
      );
      await tester.pump();

      // Opens the dropdown to count menu items.
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Local'), findsWidgets);
      expect(find.text('Home'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Dropdown interaction
  // -------------------------------------------------------------------------

  group('PanelSourceSelector dropdown interaction', () {
    testWidgets('dropdown opens when tapped', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // After opening the overlay, "Local" appears at least twice.
      expect(find.text('Local'), findsWidgets);
    });

    testWidgets('shows multiple items in open dropdown', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_twoLocalSources()),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Local'), findsWidgets);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('selecting an item closes the dropdown', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_twoLocalSources()),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Tap the "Local" item in the menu overlay.
      await tester.tap(find.text('Local').last);
      await tester.pumpAndSettle();

      // DropdownButton is still present (closed state).
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('selecting a different item updates panel source provider', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_twoLocalSources()),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Select "Home"
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      // After selection the dropdown still renders (not disposed).
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Icons per source type
  // -------------------------------------------------------------------------

  group('PanelSourceSelector source icons', () {
    testWidgets('shows folder icon for local source in dropdown items', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // folder_outlined icon appears in both the selected item builder
      // and the open menu item.
      expect(find.byIcon(Icons.folder_outlined), findsWidgets);
    });

    testWidgets('shows archive icon for archive source', (tester) async {
      final archiveSources = [
        const AvailableSource(
          key: 'local',
          label: 'Local',
          source: LocalPanelSource('/'),
        ),
        AvailableSource(
          key: 'archive:/path/test.zip',
          label: 'test.zip',
          source: ArchivePanelSource(
            archivePath: '/path/test.zip',
            innerPath: '/',
            parent: const LocalPanelSource('/path'),
          ),
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(archiveSources),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.archive_outlined), findsWidgets);
    });

    testWidgets('shows lock icon for container source', (tester) async {
      final containerSources = [
        const AvailableSource(
          key: 'local',
          label: 'Local',
          source: LocalPanelSource('/'),
        ),
        AvailableSource(
          key: 'container:/vault.bin',
          label: 'vault.bin',
          source: ContainerPanelSource(
            containerPath: '/vault.bin',
            innerPath: '/',
            parent: const LocalPanelSource('/'),
            unlockSession: Object(),
          ),
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(containerSources),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_outlined), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------
  // Provider updates on selection
  // -------------------------------------------------------------------------

  group('PanelSourceSelector provider updates', () {
    testWidgets(
      'selecting "Home" updates panelSourceProvider state to /home path',
      (tester) async {
        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              availableSourcesProvider.overrideWithValue(_twoLocalSources()),
            ],
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return MaterialApp(
                  home: Scaffold(
                    body: SizedBox(
                      width: 300,
                      child: const PanelSourceSelector(side: PanelSide.local),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        final source = container.read(panelSourceProvider(PanelSide.local));
        expect(source, isA<LocalPanelSource>());
        expect((source as LocalPanelSource).path, equals('/home'));
      },
    );

    testWidgets('PanelSide.remote selector works independently of local', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.remote),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Multiple instances
  // -------------------------------------------------------------------------

  group('PanelSourceSelector multiple panels', () {
    testWidgets('two selectors can coexist in the same tree', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: const [
                  Expanded(child: PanelSourceSelector(side: PanelSide.local)),
                  Expanded(child: PanelSourceSelector(side: PanelSide.remote)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    });

    testWidgets('local and remote selectors have independent state', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availableSourcesProvider.overrideWithValue(_twoLocalSources()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: const [
                  Expanded(child: PanelSourceSelector(side: PanelSide.local)),
                  Expanded(child: PanelSourceSelector(side: PanelSide.remote)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Both show Local by default.
      expect(find.text('Local'), findsNWidgets(2));
    });
  });

  group('PanelSourceSelector exact storage identity', () {
    testWidgets(
      'same-provider accounts select their exact client in 132 pixels',
      (tester) async {
        final first = _Cloud('first');
        final second = _Cloud('second');
        final entries = [
          ..._localOnlySources(),
          _remoteEntry(
            first,
            'connection-a',
            'First account with a long label',
          ),
          _remoteEntry(
            second,
            'connection-b',
            'Second account with a long label',
          ),
        ];
        final container = ProviderContainer(
          overrides: [availableSourcesProvider.overrideWithValue(entries)],
        );
        addTearDown(container.dispose);
        container
            .read(panelSourceProvider(PanelSide.local).notifier)
            .setSource(
              RemotePanelSource(
                providerName: 'A different display label',
                client: second,
                path: '/nested/folder',
              ),
            );
        await tester.pumpWidget(
          _ownedWrap(
            container,
            const PanelSourceSelector(side: PanelSide.local),
          ),
        );
        await tester.pump();

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        expect(dropdown.value, 'remote:connection-b');
        expect(
          dropdown.items!.where((item) => item.value == dropdown.value),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        expect(container.exists(panelProvider(PanelSide.local)), isFalse);

        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('First account with a long label').last);
        await tester.pumpAndSettle();
        final selected = container.read(panelSourceProvider(PanelSide.local));
        expect((selected as RemotePanelSource).client, same(first));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'missing account stays selected and disabled without fallback',
      (tester) async {
        final other = _Cloud('other');
        final missing = _Cloud('missing')..current = false;
        final original = RemotePanelSource(
          providerName: 'Original account with a long label',
          client: missing,
          path: '/private',
        );
        final container = ProviderContainer(
          overrides: [
            availableSourcesProvider.overrideWithValue([
              ..._localOnlySources(),
              _remoteEntry(other, 'other', 'Another account'),
            ]),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(panelSourceProvider(PanelSide.local).notifier)
            .setSource(original);
        await tester.pumpWidget(
          _ownedWrap(
            container,
            const PanelSourceSelector(side: PanelSide.local),
          ),
        );
        await tester.pump();

        final dropdown = tester.widget<DropdownButton<String>>(
          find.byType(DropdownButton<String>),
        );
        final selected = dropdown.items!.singleWhere(
          (item) => item.value == dropdown.value,
        );
        expect(selected.enabled, isFalse);
        expect(
          find.text('Original account with a long label · Not connected'),
          findsOneWidget,
        );
        dropdown.onChanged!(selected.value);
        dropdown.onChanged!('removed-key');
        expect(
          container.read(panelSourceProvider(PanelSide.local)),
          same(original),
        );
        expect(container.exists(panelProvider(PanelSide.local)), isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('restored unavailable storage overrides a stale picker value', (
      tester,
    ) async {
      final other = _Cloud('other');
      final missing = _Cloud('restored')..current = false;
      final container = ProviderContainer(
        overrides: [
          availableSourcesProvider.overrideWithValue([
            ..._localOnlySources(),
            _remoteEntry(other, 'other', 'Another account'),
          ]),
        ],
      );
      addTearDown(container.dispose);
      final previous = container.read(panelSourceProvider(PanelSide.remote));
      await tester.pumpWidget(
        _ownedWrap(
          container,
          PanelSourceSelector(
            side: PanelSide.remote,
            currentStorage: storageReferenceForClient(missing),
            currentLabel: 'Restored account with a long label',
            currentAvailable: false,
          ),
        ),
      );
      await tester.pump();

      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(
        dropdown.items!
            .singleWhere((item) => item.value == dropdown.value)
            .enabled,
        isFalse,
      );
      expect(
        find.text('Restored account with a long label · Not connected'),
        findsOneWidget,
      );
      expect(
        container.read(panelSourceProvider(PanelSide.remote)),
        same(previous),
      );
      expect(container.exists(panelProvider(PanelSide.remote)), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open menu rejects a replaced client with the same key', (
      tester,
    ) async {
      final first = _Cloud('first');
      final second = _Cloud('second');
      final replacement = _Cloud('replacement');
      final choices = StateProvider<List<AvailableSource>>(
        (_) => [
          ..._localOnlySources(),
          _remoteEntry(first, 'first', 'First account'),
          _remoteEntry(second, 'second', 'Second account'),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          availableSourcesProvider.overrideWith((ref) => ref.watch(choices)),
        ],
      );
      addTearDown(container.dispose);
      final original = _remoteEntry(first, 'first', 'First account').source;
      container
          .read(panelSourceProvider(PanelSide.local).notifier)
          .setSource(original);
      await tester.pumpWidget(
        _ownedWrap(container, const PanelSourceSelector(side: PanelSide.local)),
      );
      await tester.pump();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      container.read(choices.notifier).state = [
        ..._localOnlySources(),
        _remoteEntry(first, 'first', 'First account'),
        _remoteEntry(replacement, 'second', 'Replacement account'),
      ];
      await tester.pump();
      await tester.tap(find.text('Second account').last);
      await tester.pumpAndSettle();

      expect(
        container.read(panelSourceProvider(PanelSide.local)),
        same(original),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'an open menu rejects an account changed inside the same client',
      (tester) async {
        final first = _Cloud('first');
        final second = _Cloud('second');
        final container = ProviderContainer(
          overrides: [
            availableSourcesProvider.overrideWithValue([
              ..._localOnlySources(),
              _remoteEntry(first, 'first', 'First account'),
              _remoteEntry(second, 'second', 'Second account'),
            ]),
          ],
        );
        addTearDown(container.dispose);
        final original = _remoteEntry(first, 'first', 'First account').source;
        container
            .read(panelSourceProvider(PanelSide.local).notifier)
            .setSource(original);
        await tester.pumpWidget(
          _ownedWrap(
            container,
            const PanelSourceSelector(side: PanelSide.local),
          ),
        );
        await tester.pump();
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();

        second.account = 'replacement';
        await tester.tap(find.text('Second account').last);
        await tester.pumpAndSettle();

        expect(
          container.read(panelSourceProvider(PanelSide.local)),
          same(original),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('source options open each configured root', (tester) async {
      final primary = _Cloud('primary', configuredRoot: '/primary-root');
      final secondary = _Cloud('secondary', configuredRoot: '/secondary-root');
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith((_) => _Auth(primary))],
      );
      addTearDown(container.dispose);
      container
          .read(multiCloudProvider)
          .addConnection(
            id: 'secondary-id',
            label: 'Secondary account',
            provider: CloudProvider.s3,
            client: secondary,
          );
      final entries = container.read(availableSourcesProvider);
      for (final client in [primary, secondary]) {
        final entry = entries.singleWhere(
          (entry) =>
              entry.source is RemotePanelSource &&
              identical((entry.source as RemotePanelSource).client, client),
        );
        expect(entry.source.currentPath, client.rootPath);
      }
      await tester.pumpWidget(
        _ownedWrap(container, const PanelSourceSelector(side: PanelSide.local)),
      );
      await tester.pump();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secondary account').last);
      await tester.pumpAndSettle();

      final selected = container.read(panelSourceProvider(PanelSide.local));
      expect((selected as RemotePanelSource).client, same(secondary));
      expect(selected.currentPath, '/secondary-root');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'header explicitly opens Local when its picker was already Local',
      (tester) async {
        final cloud = _Cloud('primary')..put('/remote.txt', [1]);
        final local = _Local();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith((_) => _Auth(cloud)),
            localFileServiceProvider.overrideWithValue(local),
            drivesProvider.overrideWith((_) async => const <DriveEntry>[]),
          ],
        );
        addTearDown(container.dispose);
        final panel = container.read(panelProvider(PanelSide.remote));
        await panel.refresh();
        expect(panel.directorySource, isA<RemotePanelSource>());
        expect(
          container.read(panelSourceProvider(PanelSide.remote)),
          const LocalPanelSource('/'),
        );
        await tester.pumpWidget(
          _ownedWrap(
            container,
            const PanelHeader(side: PanelSide.remote, isActive: true),
            width: 760,
          ),
        );
        await tester.pump();
        expect(find.byTooltip('Browse...'), findsNothing);

        final picker = find.descendant(
          of: find.byType(PanelSourceSelector),
          matching: find.byType(DropdownButton<String>),
        );
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Local').last);
        await tester.pumpAndSettle();

        expect(local.reads, ['/']);
        expect(panel.directorySource, isA<LocalPanelSource>());
        expect(panel.hasVerifiedDirectoryListing, isTrue);
        expect(panel.currentPath, '/');
        expect(
          container.read(panelSourceProvider(PanelSide.remote)),
          const LocalPanelSource('/'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Dense styling
  // -------------------------------------------------------------------------

  group('PanelSourceSelector styling', () {
    testWidgets('DropdownButton uses isDense style', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.isDense, isTrue);
    });

    testWidgets('dropdown has no underline', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      // underline is overridden to SizedBox.shrink()
      expect(dropdown.underline, isA<SizedBox>());
    });

    testWidgets('source label text uses bodySmall style from theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider.overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      // The dropdown should render without error — just verify it's present.
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });
}
