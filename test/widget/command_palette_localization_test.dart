import 'dart:io';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/commander_strings.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/command_palette.dart';
import 'package:crisp_cloud/widgets/connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/workflow_fake_client.dart';

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/landing';
  @override
  String? get grantedBasePath => currentPath;
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

class _Auth extends ChangeNotifier implements AuthNotifier {
  @override
  final WorkflowFakeClient client = WorkflowFakeClient()..current = false;
  @override
  bool get isConnected => false;
  @override
  String? userEmail;
  @override
  String get providerName => client.providerName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProviderContainer container;
  late ValueNotifier<Locale> locale;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        transferJournalProvider.overrideWithValue(
          TransferJournal(MemoryTransferJournalStorage()),
        ),
        authProvider.overrideWith((_) => _Auth()),
        localFileServiceProvider.overrideWithValue(_Local()),
      ],
    );
    await container.read(panelProvider(PanelSide.local)).refresh();
    locale = ValueNotifier(const Locale('de'));
  });
  tearDown(() {
    locale.dispose();
    container.dispose();
  });

  String tr(String key) =>
      CommanderStrings.forLanguage(locale.value.languageCode, key);
  Future<void> open(WidgetTester tester, {bool narrow = true}) async {
    tester.view.physicalSize = narrow
        ? const Size(320, 740)
        : const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, language, _) => MaterialApp(
            locale: language,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
              child: child!,
            ),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () => showCommandPalette(context, ref),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final language in ['de', 'ar']) {
    testWidgets(
      'split/combine recovery opens from the keyboard palette in $language',
      (tester) async {
        locale.value = Locale(language);
        await tester.runAsync(() => container.read(transferProvider).ready);
        await open(tester);
        await tester.enterText(
          find.byType(TextField),
          tr('Split/combine recovery'),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.runAsync(
          () => container.read(transferProvider).refreshIntegrityHistory(),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CommandPalette), findsNothing);
        expect(find.text(tr('Split/combine recovery')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'empty command search handles arrows, Enter and Escape in $language',
      (tester) async {
        locale.value = Locale(language);
        await open(tester);
        await tester.enterText(find.byType(TextField), '___no_such_command___');
        await tester.pump();
        expect(find.text(tr('No matching commands')), findsOneWidget);
        for (final key in [
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.enter,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pump();
        }
        expect(find.byType(CommandPalette), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CommandPalette), findsNothing);
      },
    );

    testWidgets(
      'keyboard selection remains visible with large $language text',
      (tester) async {
        locale.value = Locale(language);
        await open(tester);
        for (var i = 0; i < 80; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        final last = find.text(tr('Refresh Right Panel'));
        final viewport = find.descendant(
          of: find.byType(CommandPalette),
          matching: find.byType(SingleChildScrollView),
        );
        final rowBounds = tester.getRect(last);
        final viewBounds = tester.getRect(viewport);
        expect(rowBounds.top, greaterThanOrEqualTo(viewBounds.top - 1));
        expect(rowBounds.bottom, lessThanOrEqualTo(viewBounds.bottom + 1));
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an open command palette rebuilds when the application locale changes',
    (tester) async {
      await open(tester);
      expect(find.text(tr('Refresh Panel')), findsOneWidget);
      final german = tr('Refresh Panel');
      locale.value = const Locale('ar');
      await tester.pumpAndSettle();
      expect(find.text(german), findsNothing);
      expect(find.text(tr('Refresh Panel')), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(tr('Refresh Panel')))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('command manager remains usable after the palette closes', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), tr('Custom commands'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    final add = find.text(tr('Add command'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text(tr('Executable')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connect command opens the connection dialog', (tester) async {
    await open(tester, narrow: false);
    await tester.enterText(find.byType(TextField), tr('Connect to Cloud'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(find.byType(ConnectionDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'live shortcut changes are searchable without reopening the palette',
    (tester) async {
      locale.value = const Locale('en');
      await open(tester, narrow: false);
      await tester.enterText(find.byType(TextField), 'refresh panel');
      await tester.pump();
      expect(find.text('Refresh Panel'), findsOneWidget);
      await container
          .read(shortcutBindingsProvider.notifier)
          .setBinding(ShortcutAction.refresh, const ShortcutBinding(key: 'F9'));
      await tester.pump();
      expect(find.text('F9'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'F9');
      await tester.pump();
      expect(find.text('Refresh Panel'), findsOneWidget);
      expect(find.text('Refresh Left Panel'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable history commands cannot execute', (tester) async {
    locale.value = const Locale('en');
    await open(tester, narrow: false);
    await tester.enterText(find.byType(TextField), 'Go back');
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.button == true &&
            widget.properties.enabled == false,
      ),
      findsWidgets,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(CommandPalette), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch panel command transfers keyboard ownership', (
    tester,
  ) async {
    locale.value = const Locale('en');
    await open(tester, narrow: false);
    await tester.enterText(find.byType(TextField), 'Switch Panel');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    expect(container.read(activePanelProvider), PanelSide.remote);
    expect(container.read(focusAreaProvider), FocusArea.remote);
    expect(tester.takeException(), isNull);
  });
}
