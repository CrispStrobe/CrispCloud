import 'package:crisp_cloud/services/browser_menu_shortcut.dart';
import 'package:crisp_cloud/services/keyboard_shortcut_service.dart';
import 'package:flutter/foundation.dart';
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

  test('macOS accelerators leave Cmd+H, Cmd+M and Cmd+Q to the system', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = KeyboardShortcutService();
    final rename = browserMenuShortcut(service, ShortcutAction.multiRename)!;
    expect(rename.trigger, LogicalKeyboardKey.keyM);
    expect(rename.meta, isTrue);
    expect(rename.shift, isTrue);
    final history = browserMenuShortcut(
      service,
      ShortcutAction.directoryHistory,
    )!;
    expect(history.trigger, LogicalKeyboardKey.keyH);
    expect(history.control, isTrue);
    expect(history.meta, isFalse);
    final hotlist = browserMenuShortcut(service, ShortcutAction.pathFavorites)!;
    expect(hotlist.trigger, LogicalKeyboardKey.keyD);
    expect(hotlist.meta, isTrue);
    final bookmark = browserMenuShortcut(service, ShortcutAction.bookmark)!;
    expect(bookmark.trigger, LogicalKeyboardKey.keyD);
    expect(bookmark.shift, isTrue);
    final reserved = {
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.keyQ,
    };
    for (final action in browserShortcutActions) {
      final shortcut = browserMenuShortcut(service, action);
      if (shortcut == null || !shortcut.meta) continue;
      final plainCommand =
          !shortcut.shift && !shortcut.alt && !shortcut.control;
      expect(
        plainCommand && reserved.contains(shortcut.trigger),
        isFalse,
        reason: action.name,
      );
    }
  });

  test('flat view, view modes and new file expose their accelerators', () {
    final service = KeyboardShortcutService();
    final flat = browserMenuShortcut(
      service,
      ShortcutAction.flatView,
      macOS: false,
    )!;
    expect(flat.trigger, LogicalKeyboardKey.keyB);
    expect(flat.control, isTrue);
    final brief = browserMenuShortcut(
      service,
      ShortcutAction.viewBrief,
      macOS: false,
    )!;
    expect(brief.trigger.keyLabel, '1');
    final newFile = browserMenuShortcut(
      service,
      ShortcutAction.newTextFile,
      macOS: false,
    )!;
    expect(newFile.trigger, LogicalKeyboardKey.f4);
    expect(newFile.shift, isTrue);
  });
}
