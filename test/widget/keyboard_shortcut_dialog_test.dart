import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/workspace_ux_strings.dart';
import 'package:crisp_cloud/providers/keyboard_shortcut_provider.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:crisp_cloud/widgets/keyboard_shortcut_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String locale = 'en',
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: KeyboardShortcutDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('recorded shortcut persists and its row updates', (tester) async {
    final container = await open(tester);
    await tester.enterText(find.byType(TextField), 'refresh');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shortcut-refresh')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key,
      'F10',
    );
    expect(find.text('F10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicting shortcut cannot be saved', (tester) async {
    final container = await open(tester);
    await tester.enterText(find.byType(TextField), 'refresh');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shortcut-refresh')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.textContaining('Already assigned to'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(
      container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key,
      'R',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('Already assigned to'), findsNothing);
  });

  testWidgets('recording can be saved using only the keyboard', (tester) async {
    final container = await open(tester);
    await tester.enterText(find.byType(TextField), 'refresh');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shortcut-refresh')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    expect(
      container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key,
      'F10',
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['de', 'ar']) {
    testWidgets('shortcut editor remains usable in narrow $locale layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, locale: locale);
      expect(find.byType(ListTile), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editor lists commander actions with every default chord', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'directory history');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('shortcut-directoryHistory')),
      findsOneWidget,
    );
    expect(find.text('Ctrl+H / Alt+↓'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Shift+F4');
    await tester.pump();
    expect(find.byKey(const ValueKey('shortcut-newTextFile')), findsOneWidget);
    expect(find.byKey(const ValueKey('shortcut-chooseEditor')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recording reports the new owner of a changed default', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'refresh');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shortcut-refresh')));
    await tester.pumpAndSettle();
    // Ctrl+PgDn is "open under cursor" now, not "next tab".
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      find.textContaining('Open folder or archive under cursor'),
      findsOneWidget,
    );
    expect(find.textContaining('Next tab'), findsNothing);
  });

  for (final locale in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('commander action names are translated in $locale', (
      tester,
    ) async {
      final container = await open(tester, locale: locale);
      container.read(shortcutBindingsProvider);
      final context = tester.element(find.byType(KeyboardShortcutDialog));
      final strings = WorkspaceUxStrings(context);
      for (final (action, english) in [
        (ShortcutAction.newTextFile, 'New text file'),
        (ShortcutAction.copySameFolder, 'Copy in this folder'),
        (ShortcutAction.directoryHistory, 'Directory history'),
        (ShortcutAction.tabList, 'List open tabs'),
        (ShortcutAction.deletePermanently, 'Delete permanently'),
        (ShortcutAction.calculateFolderSizes, 'Calculate all folder sizes'),
        (ShortcutAction.openInNewTab, 'Open folder in new tab'),
        (ShortcutAction.activateLastTab, 'Switch to last tab'),
      ]) {
        expect(strings.action(action), isNot(english), reason: locale);
      }
      expect(strings.action(ShortcutAction.activateTab3), contains('3'));
    });
  }
}
