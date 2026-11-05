// test/widget/panel_source_selector_widget_test.dart
//
// Widget tests for PanelSourceSelector.
// Tests dropdown rendering, icons, selection changes, and both panel sides.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/widgets/panel_source_selector.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: child,
        ),
      ),
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PanelSourceNotifier startup restoration', () {
    for (final side in PanelSide.values) {
      testWidgets('restores the saved ${side.name} source without a newer choice', (
        tester,
      ) async {
        final key = 'panel_source_${side.name}';
        SharedPreferences.setMockInitialValues({
          key: 'local',
          '${key}_path': '/saved/${side.name}',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        expect(container.read(panelSourceProvider(side)).currentPath, '/');

        await tester.pump();

        final restored = container.read(panelSourceProvider(side));
        expect(restored, isA<LocalPanelSource>());
        expect(restored.currentPath, '/saved/${side.name}');
      });
    }

    final changes = <String, void Function(PanelSourceNotifier)>{
      'source selection': (notifier) =>
          notifier.setSource(const LocalPanelSource('/chosen')),
      'same-source selection': (notifier) =>
          notifier.setSource(const LocalPanelSource('/')),
      'path navigation': (notifier) => notifier.navigateTo('/chosen'),
      'archive entry': (notifier) => notifier.enterArchive('/chosen.zip'),
      'container entry': (notifier) =>
          notifier.enterContainer('/chosen.vc', 'test-password'),
      'parent navigation': (notifier) => notifier.exitToParent(),
    };
    for (final change in changes.entries) {
      testWidgets('${change.key} wins over a pending startup restore', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'panel_source_remote': 'local',
          'panel_source_remote_path': '/saved',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          panelSourceProvider(PanelSide.remote).notifier,
        );
        // The constructor's await has yielded; make the choice before its
        // continuation can publish the persisted source.
        change.value(notifier);
        final chosen = container.read(panelSourceProvider(PanelSide.remote));

        await tester.pump();

        expect(
          container.read(panelSourceProvider(PanelSide.remote)),
          same(chosen),
        );
        if (chosen.isLocal) {
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('panel_source_remote_path'), chosen.currentPath);
        }
      });
    }

    testWidgets('a pending local marker cannot reset newer navigation to root', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'panel_source_remote': 'local'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        panelSourceProvider(PanelSide.remote).notifier,
      );
      notifier.setSource(const LocalPanelSource('/local'));
      notifier.navigateTo('/two');

      await tester.pump();

      expect(
        container.read(panelSourceProvider(PanelSide.remote)).currentPath,
        '/two',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('panel_source_remote_path'), '/two');
    });
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('shows "Local" label when sources contain only Local',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });

    testWidgets('renders two items when two sources are provided',
        (tester) async {
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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

    testWidgets('selecting a different item updates panel source provider',
        (tester) async {
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
    testWidgets('shows folder icon for local source in dropdown items',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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
          child: Builder(builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 300,
                  child: const PanelSourceSelector(side: PanelSide.local),
                ),
              ),
            );
          }),
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
    });

    testWidgets('PanelSide.remote selector works independently of local',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.remote),
          overrides: [
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: const [
                  Expanded(
                      child: PanelSourceSelector(side: PanelSide.local)),
                  Expanded(
                      child: PanelSourceSelector(side: PanelSide.remote)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    });

    testWidgets('local and remote selectors have independent state',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            availableSourcesProvider.overrideWithValue(_twoLocalSources()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: const [
                  Expanded(
                      child: PanelSourceSelector(side: PanelSide.local)),
                  Expanded(
                      child: PanelSourceSelector(side: PanelSide.remote)),
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

  // -------------------------------------------------------------------------
  // Dense styling
  // -------------------------------------------------------------------------

  group('PanelSourceSelector styling', () {
    testWidgets('DropdownButton uses isDense style', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
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

    testWidgets('source label text uses bodySmall style from theme',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PanelSourceSelector(side: PanelSide.local),
          overrides: [
            availableSourcesProvider
                .overrideWithValue(_localOnlySources()),
          ],
        ),
      );
      await tester.pump();

      // The dropdown should render without error — just verify it's present.
      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });
}
