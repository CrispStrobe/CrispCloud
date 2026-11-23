import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/widgets/windows_platform_menu_bar.dart';

void main() {
  testWidgets('Windows editor menu opens below the toolbar and uses Ctrl hints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1050, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saved = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            title: WindowsPlatformMenuBar(
              menus: [
                PlatformMenu(
                  label: 'File',
                  menus: [
                    PlatformMenuItem(
                      label: 'Save',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyS,
                        meta: true,
                      ),
                      onSelected: () => saved++,
                    ),
                    const PlatformMenuItem(label: 'Unavailable'),
                  ],
                ),
                PlatformMenu(
                  label: 'Edit',
                  menus: [
                    PlatformMenuItem(
                      label: 'Undo',
                      onSelected: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('windows-context-menu-toolbar')),
      findsOneWidget,
    );
    final opener = find.byKey(const ValueKey('windows-context-menu-File'));
    expect(
      tester.widget<SubmenuButton>(opener).menuStyle!.alignment,
      AlignmentDirectional.bottomStart,
    );
    expect(
      tester.widget<MenuAcceleratorLabel>(
        find.descendant(
          of: opener,
          matching: find.byType(MenuAcceleratorLabel),
        ),
      ).label,
      '&File',
    );
    await tester.tap(opener);
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('windows-context-item-Save'));
    expect(
      tester.getTopLeft(save).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(opener).dy - 1),
    );
    final accelerator = tester.widget<MenuItemButton>(save).shortcut
        as SingleActivator;
    expect(accelerator.control, isTrue);
    expect(accelerator.meta, isFalse);
    expect(accelerator.trigger, LogicalKeyboardKey.keyS);
    expect(
      tester.widget<MenuItemButton>(
        find.byKey(const ValueKey('windows-context-item-Unavailable')),
      ).onPressed,
      isNull,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('context menus remain reachable when the window is narrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: WindowsPlatformMenuBar(
              menus: [
                PlatformMenu(
                  label: 'File',
                  menus: [
                    PlatformMenuItem(
                      label: 'Save',
                      onSelected: () => called = true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('windows-context-compact')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('windows-context-compact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('windows-context-menu-File')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('windows-context-item-Save')));
    await tester.pumpAndSettle();
    expect(called, isTrue);
  });
}
