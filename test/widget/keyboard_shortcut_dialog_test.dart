import 'package:crisp_cloud/l10n/app_localizations.dart';
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

  Future<ProviderContainer> open(WidgetTester tester, {String locale = 'en'}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: KeyboardShortcutDialog()),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('recorded shortcut persists and its row updates', (tester) async {
    final container = await open(tester);
    await tester.enterText(find.byType(TextField), 'refresh');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('shortcut-refresh')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key, 'F9');
    expect(find.text('F9'), findsOneWidget);
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
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    expect(container.read(shortcutBindingsProvider)[ShortcutAction.refresh]!.key, 'R');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('Already assigned to'), findsNothing);
  });

  for (final locale in ['de', 'ar']) {
    testWidgets('shortcut editor remains usable in narrow $locale layout', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, locale: locale);
      expect(find.byType(ListTile), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
