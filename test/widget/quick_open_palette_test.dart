import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/quick_open_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/services/multi_rename_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/quick_open_service.dart';
import 'package:crisp_cloud/services/rename_preset_store.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crisp_cloud/widgets/batch_rename_dialog.dart';
import 'package:crisp_cloud/widgets/command_palette.dart';
import 'package:crisp_cloud/widgets/drive_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/quick_open_fixture.dart';

void main() {
  late QuickOpenHarness harness;
  setUp(() async {
    harness = await QuickOpenHarness.create(
      overrides: [
        drivesProvider.overrideWith(
          (ref) async => const [
            DriveEntry(
              path: '/drive',
              label: 'Test device',
              icon: Icons.storage,
            ),
          ],
        ),
      ],
    );
  });
  tearDown(() => harness.dispose());

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() completed,
    String description,
  ) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      // Store Futures originate in the fixture's real async zone. Yield that
      // zone as well as a widget frame, then assert the observable outcome.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 25));
      if (completed()) return;
    }
    fail('Did not complete: $description');
  }

  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    bool narrow = false,
  }) async {
    tester.view.physicalSize = narrow
        ? const Size(340, 740)
        : const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showCommandPalette(context, ref),
                child: const Text('Open palette'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open palette'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'favorite search opens the exact saved local path from the keyboard',
    (tester) async {
      await tester.runAsync(
        () => harness.container
            .read(bookmarksProvider)
            .add(
              'Research shortcut',
              '/favorite',
              PanelSide.local,
              storage: storageReferenceForSource(const LocalPanelSource('/')),
            ),
      );
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Research shortcut');
      await tester.pump();
      expect(find.text('Favorite · Local · /favorite'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await waitFor(
        tester,
        () =>
            harness.container
                .read(panelProvider(PanelSide.local))
                .currentPath ==
            '/favorite',
        'saved favorite navigation',
      );
      expect(find.byType(CommandPalette), findsNothing);
      expect(
        harness.container.read(panelProvider(PanelSide.local)).currentPath,
        '/favorite',
      );
      expect(harness.local.accessRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('legacy favorite stays disabled with its recovery instruction', (
    tester,
  ) async {
    await tester.runAsync(
      () => harness.container
          .read(bookmarksProvider)
          .add('Legacy shortcut', '/favorite', PanelSide.local),
    );
    await open(tester, language: 'de', narrow: true);
    await tester.enterText(find.byType(TextField), 'Legacy shortcut');
    await tester.pump();
    expect(
      find.text(
        QuickOpenStrings.forLanguage('de')
            .reason(QuickOpenUnavailable.unboundFavorite),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disconnecting the highlighted source does not select another same-named account',
    (tester) async {
      final second = QuickOpenCloud('account-b');
      harness.container
          .read(multiCloudProvider)
          .addConnection(
            id: 'second',
            label: 'Memory',
            provider: CloudProvider.webdav,
            client: second,
          );
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Memory');
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Memory',
        ),
        findsNWidgets(2),
      );
      harness.cloud.current = false;
      harness.auth.changed();
      await tester.pumpAndSettle();
      expect(
        find.text(
          QuickOpenStrings.forLanguage('en')
              .reason(QuickOpenUnavailable.changed),
        ),
        findsOneWidget,
      );
      final before = second.listingStarted.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(second.listingStarted, hasLength(before));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rename preset opens seeded review and performs no writes', (
    tester,
  ) async {
    harness.container.read(activePanelProvider.notifier).state =
        PanelSide.remote;
    final panel = harness.container.read(panelProvider(PanelSide.remote));
    await tester.runAsync(
      () => panel.navigateToPath(
        '/favorite',
        origin: panel.resolveStorageReference(
          storageReferenceForClient(harness.cloud),
          '/favorite',
        ),
      ),
    );
    panel.toggleSelection(panel.files!.firstWhere((file) => !file.isFolder));
    await tester.runAsync(
      () => RenamePresetStore().save({
        'Review suffix': const MultiRenameOptions(nameMask: '[N]-review'),
      }),
    );
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Review suffix');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      () => find.text('→ a-review.txt').evaluate().isNotEmpty,
      'seeded rename preview',
    );
    expect(find.byType(CommandPalette), findsNothing);
    expect(find.byType(BatchRenameDialog), findsOneWidget);
    expect(find.widgetWithText(TextField, '[N]-review'), findsOneWidget);
    expect(find.text('→ a-review.txt'), findsWidgets);
    expect(harness.cloud.writes, isEmpty);
    expect(harness.cloud.files.keys, contains('/favorite/a.txt'));
    expect(tester.takeException(), isNull);
  });

  test('quick-open strings are complete in all supported languages', () {
    final translations = QuickOpenStrings.translations;
    expect(translations.keys.toSet(), {
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    for (final locale in translations.entries) {
      expect(
        locale.value.keys.toSet(),
        translations['en']!.keys.toSet(),
        reason: locale.key,
      );
      expect(
        locale.value.values.every((value) => value.trim().isNotEmpty),
        isTrue,
      );
      expect(locale.value['reviewCount'], contains('{count}'));
    }
  });
}
