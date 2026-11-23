import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/browser_menu_strings.dart';
import 'windows_menu_accelerators.dart';

/// Renders contextual PlatformMenu items in the Windows window toolbar.
///
/// Flutter's native PlatformMenuBar is a macOS-only integration. This adapter
/// keeps editor actions/disabled states shared with macOS, but uses a normal
/// in-window cascading menu on Windows. macOS Command accelerators become
/// Windows Control accelerators in the displayed hints.
class WindowsPlatformMenuBar extends StatelessWidget {
  const WindowsPlatformMenuBar({super.key, required this.menus});

  final List<PlatformMenuItem> menus;

  @override
  Widget build(BuildContext context) {
    final maxPopupHeight = (MediaQuery.sizeOf(context).height - 48 - 16)
        .clamp(120.0, double.infinity)
        .toDouble();
    final popupStyle = MenuStyle(
      alignment: AlignmentDirectional.bottomStart,
      maximumSize: WidgetStatePropertyAll(
        Size(double.infinity, maxPopupHeight),
      ),
      elevation: const WidgetStatePropertyAll(6),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    );
    final usedAccelerators = <String>{};

    MenuSerializableShortcut? windowsShortcut(
      MenuSerializableShortcut? shortcut,
    ) {
      if (shortcut is SingleActivator && shortcut.meta) {
        return SingleActivator(
          shortcut.trigger,
          control: true,
          shift: shortcut.shift,
          alt: shortcut.alt,
          numLock: shortcut.numLock,
          includeRepeats: shortcut.includeRepeats,
        );
      }
      return shortcut;
    }

    List<Widget> entries(List<PlatformMenuItem> items, {bool topLevel = false}) {
      final widgets = <Widget>[];
      for (final item in items) {
        if (item is PlatformProvidedMenuItem) {
          // The macOS system owns Quit, Hide, Services, etc.
          continue;
        }
        if (item is PlatformMenuItemGroup) {
          final group = entries(item.members);
          if (group.isNotEmpty) {
            if (widgets.isNotEmpty) widgets.add(const Divider(height: 8));
            widgets.addAll(group);
          }
          continue;
        }
        if (item is PlatformMenu) {
          widgets.add(
            SubmenuButton(
              key: ValueKey('windows-context-menu-${item.label}'),
              menuStyle: topLevel ? popupStyle : null,
              style: topLevel
                  ? const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 10),
                      ),
                    )
                  : null,
              menuChildren: entries(item.menus),
              child: topLevel
                  ? MenuAcceleratorLabel(
                      windowsMenuAcceleratorLabel(item.label, usedAccelerators),
                    )
                  : Text(item.label),
            ),
          );
          continue;
        }
        widgets.add(
          MenuItemButton(
            key: ValueKey('windows-context-item-${item.label}'),
            onPressed: item.onSelected,
            shortcut: windowsShortcut(item.shortcut),
            child: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        );
      }
      return widgets;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final menuWidgets = entries(menus, topLevel: !compact);
        if (compact) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: MenuAnchor(
              menuChildren: menuWidgets,
              builder: (context, controller, _) => TextButton.icon(
                key: const ValueKey('windows-context-compact'),
                icon: const Icon(Icons.menu, size: 18),
                label: Text(BrowserMenuStrings(context).text('menus')),
                onPressed: () => controller.isOpen
                    ? controller.close()
                    : controller.open(),
              ),
            ),
          );
        }
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: MenuBar(
            key: const ValueKey('windows-context-menu-toolbar'),
            style: const MenuStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            children: menuWidgets,
          ),
        );
      },
    );
  }
}
