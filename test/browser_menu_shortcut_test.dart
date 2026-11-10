import 'package:crisp_cloud/services/browser_menu_shortcut.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('native default accelerators follow the platform primary modifier', () {
    final service = KeyboardShortcutService();
    final mac = browserMenuShortcut(service, ShortcutAction.newTab)!;
    expect(mac.trigger, LogicalKeyboardKey.keyT);
    expect(mac.meta, isTrue);
    expect(mac.control, isFalse);
    final desktop = browserMenuShortcut(
      service,
      ShortcutAction.newTab,
      macOS: false,
    )!;
    expect(desktop.control, isTrue);
    expect(desktop.meta, isFalse);
  });

  test(
    'native menus use exact custom modifiers and discard old defaults',
    () async {
      final service = KeyboardShortcutService();
      await service.setBinding(
        ShortcutAction.newTab,
        const ShortcutBinding(key: 'F9', ctrl: true, shift: true),
      );
      final shortcut = browserMenuShortcut(service, ShortcutAction.newTab)!;
      expect(shortcut.trigger, LogicalKeyboardKey.f9);
      expect(shortcut.control, isTrue);
      expect(shortcut.shift, isTrue);
      expect(shortcut.meta, isFalse);
    },
  );

  test('space and unknown imported labels are handled safely', () async {
    final service = KeyboardShortcutService();
    await service.setBinding(
      ShortcutAction.refresh,
      const ShortcutBinding(key: ' '),
    );
    expect(
      browserMenuShortcut(service, ShortcutAction.refresh)!.trigger,
      LogicalKeyboardKey.space,
    );
    await service.setBinding(
      ShortcutAction.refresh,
      const ShortcutBinding(key: 'NoSuchHardwareKey'),
    );
    expect(browserMenuShortcut(service, ShortcutAction.refresh), isNull);
  });

  test(
    'imported modifier-only bindings cannot create native accelerators',
    () async {
      final service = KeyboardShortcutService();
      for (final key in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.metaRight,
      ]) {
        await service.setBinding(
          ShortcutAction.refresh,
          ShortcutBinding(key: key.keyLabel),
        );
        expect(browserMenuShortcut(service, ShortcutAction.refresh), isNull);
      }
    },
  );

  test(
    'imported collisions keep native menus aligned with custom priority',
    () async {
      final service = KeyboardShortcutService();
      await service.setBinding(
        ShortcutAction.rename,
        const ShortcutBinding(key: 'W', meta: true),
      );
      expect(browserMenuShortcut(service, ShortcutAction.closeTab), isNull);
      final rename = browserMenuShortcut(service, ShortcutAction.rename)!;
      expect(rename.trigger, LogicalKeyboardKey.keyW);
      expect(rename.meta, isTrue);
      expect(rename.includeRepeats, isFalse);
    },
  );

  testWidgets('browser accelerators yield while a text field owns focus', (
    tester,
  ) async {
    final browserFocus = FocusNode();
    addTearDown(browserFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TextField(autofocus: true),
              Focus(focusNode: browserFocus, child: const Text('Files')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(browserTextInputHasFocus(), isTrue);
    browserFocus.requestFocus();
    await tester.pump();
    expect(browserTextInputHasFocus(), isFalse);
  });
}
