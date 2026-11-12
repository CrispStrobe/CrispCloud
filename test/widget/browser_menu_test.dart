import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/browser_menu_strings.dart';
import 'package:crisp_cloud/models/browser_menu_layout.dart';
import 'package:crisp_cloud/providers/browser_menu_provider.dart';
import 'package:crisp_cloud/services/browser_menu_store.dart';
import 'package:crisp_cloud/widgets/browser_menu_editor.dart';
import 'package:crisp_cloud/widgets/configurable_browser_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/browser_menu_storage.dart';

BrowserMenuLayout sampleMenu({bool unknown = false}) => BrowserMenuLayout([
  BrowserMenuNode(
    id: 'files',
    kind: BrowserMenuNodeKind.submenu,
    labelKey: 'file',
    children: [
      BrowserMenuNode(
        id: 'copy',
        kind: BrowserMenuNodeKind.command,
        commandId: 'action:copy',
      ),
      BrowserMenuNode(id: 'separator', kind: BrowserMenuNodeKind.separator),
      if (unknown)
        BrowserMenuNode(
          id: 'future',
          kind: BrowserMenuNodeKind.command,
          commandId: 'future:unsupported',
        ),
    ],
  ),
]);

void main() {
  late MemoryBrowserMenuStorage storage;
  late BrowserMenuStore store;
  late ProviderContainer container;
  var called = 0;
  late Map<String, BrowserMenuCommandBinding> commands;
  setUp(() async {
    called = 0;
    storage = MemoryBrowserMenuStorage()
      ..values[BrowserMenuStore.currentKey] = sampleMenu().encode();
    store = BrowserMenuStore(storage: storage);
    await store.ready;
    container = ProviderContainer(
      overrides: [browserMenuStoreProvider.overrideWith((_) => store)],
    );
    commands = {
      'action:copy': BrowserMenuCommandBinding(
        id: 'action:copy',
        label: 'Copy files',
        shortcut: const SingleActivator(LogicalKeyboardKey.keyC, control: true),
        onSelected: () => called++,
      ),
      'action:paste': BrowserMenuCommandBinding(
        id: 'action:paste',
        label: 'Paste files',
        onSelected: () => called++,
      ),
    };
  });
  tearDown(() => container.dispose());

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('en'),
    Size size = const Size(1050, 900),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'native and in-app layouts resolve the same stable command with disabled unknown IDs',
    (tester) async {
      late List<PlatformMenuItem> native;
      await mount(
        tester,
        Builder(
          builder: (context) {
            native = configuredPlatformMenus(
              sampleMenu(unknown: true),
              commands,
              BrowserMenuStrings(context),
            );
            return ConfigurableBrowserMenu(
              layout: sampleMenu(unknown: true),
              commands: commands,
              fixedCommands: const [],
            );
          },
        ),
      );
      final entries = menuEntries(native);
      expect(
        entries
            .where((item) => item.label.contains('future:unsupported'))
            .single
            .onSelected,
        isNull,
      );
      entries.where((item) => item.label == 'Copy files').single.onSelected!();
      expect(called, 1);
      await tester.tap(find.byKey(const ValueKey('browser-menu-files')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('browser-menu-entry-future')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('browser-menu-entry-copy')));
      await tester.pumpAndSettle();
      expect(called, 2);
    },
  );

  testWidgets('a repeated native command claims its accelerator only once', (
    tester,
  ) async {
    final layout = sampleMenu().updateChildren('files', [
      BrowserMenuNode(
        id: 'first',
        kind: BrowserMenuNodeKind.command,
        commandId: 'action:copy',
      ),
      BrowserMenuNode(
        id: 'second',
        kind: BrowserMenuNodeKind.command,
        commandId: 'action:copy',
      ),
    ]);
    late List<PlatformMenuItem> native;
    await mount(
      tester,
      Builder(
        builder: (context) {
          native = configuredPlatformMenus(
            layout,
            commands,
            BrowserMenuStrings(context),
          );
          return const SizedBox();
        },
      ),
    );
    final entries = native.single.descendants
        .where((item) => item.label == 'Copy files')
        .toList();
    expect(entries.map((entry) => entry.shortcut != null), [true, false]);
  });

  testWidgets(
    'empty custom menus retain fixed settings, recovery and reset controls',
    (tester) async {
      var selected = '';
      await mount(
        tester,
        ConfigurableBrowserMenu(
          layout: BrowserMenuLayout([]),
          commands: const {},
          fixedCommands: [
            for (final id in ['settings', 'recovery', 'reset'])
              BrowserMenuCommandBinding(
                id: id,
                label: id,
                onSelected: () => selected = id,
              ),
          ],
        ),
      );
      for (final id in ['settings', 'recovery', 'reset']) {
        await tester.tap(find.byKey(const ValueKey('browser-menu-controls')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('browser-menu-fixed-$id')));
        await tester.pumpAndSettle();
        expect(selected, id);
      }
    },
  );

  testWidgets(
    'preview shows unavailable entries and never invokes configured callbacks',
    (tester) async {
      await mount(
        tester,
        ConfigurableBrowserMenu(
          layout: sampleMenu(unknown: true),
          commands: commands,
          fixedCommands: [
            BrowserMenuCommandBinding(
              id: 'reset',
              label: 'Reset',
              onSelected: () => called++,
            ),
          ],
          preview: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('browser-menu-files')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('browser-menu-entry-copy')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('browser-menu-entry-future')),
            )
            .onPressed,
        isNull,
      );
      expect(called, 0);
    },
  );

  Future<void> openEditor(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(1050, 900),
    double scale = 1,
  }) async {
    await mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => BrowserMenuEditor(commands: commands),
          ),
          child: const Text('Configure'),
        ),
      ),
      locale: locale,
      size: size,
      scale: scale,
    );
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'command picker changes a draft and Cancel preserves the saved layout',
    (tester) async {
      final original = store.layout.encode();
      await openEditor(tester);
      await tester.tap(find.byKey(const ValueKey('browser-menu-edit-files')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('browser-menu-add-command')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('browser-menu-command-search')),
        'paste',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('browser-menu-pick-action:paste')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paste files'), findsOneWidget);
      expect(store.layout.encode(), original);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(store.layout.encode(), original);
      expect(storage.writes, isEmpty);
      expect(called, 0);
    },
  );

  testWidgets(
    'invalid import leaves the draft intact and a valid import applies only after Save',
    (tester) async {
      final original = store.layout.encode();
      await openEditor(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Import'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('browser-menu-import-json')),
        '{"version":99,"menus":[]}',
      );
      await tester.tap(find.byKey(const ValueKey('browser-menu-import-apply')));
      await tester.pumpAndSettle();
      expect(store.layout.encode(), original);
      expect(
        find.text(BrowserMenuStrings.messages['invalid']!.first),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('browser-menu-import-json')),
        sampleMenu(unknown: true).encode(),
      );
      await tester.tap(find.byKey(const ValueKey('browser-menu-import-apply')));
      await tester.pumpAndSettle();
      expect(store.layout.encode(), original);
      await tester.tap(find.byKey(const ValueKey('browser-menu-save')));
      await waitForMenu(tester, () => store.layout.find('future') != null);
      await tester.pumpAndSettle();
      expect(store.layout.find('future')!.commandId, 'future:unsupported');
      expect(called, 0);
    },
  );

  testWidgets(
    'save failure keeps the editor open and the previous live layout',
    (tester) async {
      final original = store.layout.encode();
      storage.failKey = BrowserMenuStore.currentKey;
      await openEditor(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Reset menus'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('browser-menu-save')));
      await waitForMenu(
        tester,
        () => find
            .text(BrowserMenuStrings.messages['saveFailed']!.first)
            .evaluate()
            .isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BrowserMenuEditor), findsOneWidget);
      expect(store.layout.encode(), original);
      expect(
        find.text(BrowserMenuStrings.messages['saveFailed']!.first),
        findsOneWidget,
      );
    },
  );

  for (final locale in [const Locale('de'), const Locale('ar')]) {
    testWidgets(
      'scaled narrow ${locale.languageCode} preview stays scrollable and does not execute',
      (tester) async {
        await openEditor(
          tester,
          locale: locale,
          size: const Size(380, 900),
          scale: 1.6,
        );
        final title =
            BrowserMenuStrings.messages['preview']![BrowserMenuStrings.languages
                .indexOf(locale.languageCode)];
        await tester.ensureVisible(find.widgetWithText(TextButton, title));
        await tester.tap(find.widgetWithText(TextButton, title));
        await tester.pumpAndSettle();
        expect(find.byType(ConfigurableBrowserMenu), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('browser-menu-compact')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('browser-menu-compact')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(called, 0);
      },
    );
  }

  test('all new menu text covers the supported locales', () {
    for (final values in BrowserMenuStrings.messages.values) {
      expect(values.length, BrowserMenuStrings.languages.length);
      expect(values.every((value) => value.trim().isNotEmpty), isTrue);
    }
  });
}

Iterable<PlatformMenuItem> menuEntries(List<PlatformMenuItem> entries) sync* {
  for (final entry in entries) {
    yield entry;
    if (entry is PlatformMenu) yield* menuEntries(entry.menus);
    if (entry is PlatformMenuItemGroup) yield* menuEntries(entry.members);
  }
}

Future<void> waitForMenu(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    await tester.pump();
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('The menu action did not finish.');
}
