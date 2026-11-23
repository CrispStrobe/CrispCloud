import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/browser_menu_strings.dart';
import '../models/browser_menu_layout.dart';
import '../models/custom_toolbar_command.dart';
import '../models/panel_side.dart';
import '../providers/custom_command_provider.dart';
import '../providers/providers.dart';
import '../services/macos_app_store.dart';
import 'custom_command_dialog.dart';

class BrowserMenuCommandBinding {
  const BrowserMenuCommandBinding({
    required this.id,
    required this.label,
    this.onSelected,
    this.shortcut,
  });
  final String id, label;
  final VoidCallback? onSelected;
  final MenuSerializableShortcut? shortcut;
  bool get enabled => onSelected != null;

  PlatformMenuItem platform({bool accelerator = true}) => PlatformMenuItem(
    label: label,
    onSelected: onSelected,
    shortcut: accelerator && enabled ? shortcut : null,
  );
}

/// A saved user command remains a reference. Capturing a menu cannot start a
/// process; selecting it uses the normal command review and its original paths.
BrowserMenuCommandBinding userBrowserMenuCommand(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  CustomToolbarCommand command, {
  required bool Function() ownsInput,
}) {
  final id = 'user:${command.id}';
  final unavailable = BrowserMenuCommandBinding(id: id, label: command.label);
  if (kIsWeb ||
      !const {
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform) ||
      defaultTargetPlatform == TargetPlatform.macOS && isMacAppStoreBuild() ||
      command.requiresReview) {
    return unavailable;
  }
  try {
    final panel = ref.read(panelProvider(side));
    final current = panel.captureOperationSession();
    final navigation = panel.navigationIntentRevision;
    final captured = captureCommandContext(ref, side);
    final service = ref.read(customToolbarCommandServiceProvider);
    service.prepare(command, captured);
    bool valid() {
      if (!context.mounted ||
          !ownsInput() ||
          !current() ||
          panel.navigationIntentRevision != navigation ||
          ref.read(activePanelProvider) != side ||
          !captured.isCurrent() ||
          captured.targetIsCurrent?.call() == false) {
        return false;
      }
      try {
        final now = captureCommandContext(ref, side);
        return now.storage == captured.storage &&
            now.currentPath == captured.currentPath &&
            now.targetPath == captured.targetPath &&
            listEquals(now.selectedPaths, captured.selectedPaths) &&
            service.commands.any((saved) => identical(saved, command));
      } catch (_) {
        return false;
      }
    }

    return BrowserMenuCommandBinding(
      id: id,
      label: command.label,
      onSelected: !valid()
          ? null
          : () {
              if (valid()) {
                showCustomCommandRunDialog(context, ref, side, command);
              }
            },
    );
  } catch (_) {
    return unavailable;
  }
}

List<PlatformMenuItem> configuredPlatformMenus(
  BrowserMenuLayout layout,
  Map<String, BrowserMenuCommandBinding> commands,
  BrowserMenuStrings strings,
) {
  final accelerators = <String>{};
  List<PlatformMenuItem> children(List<BrowserMenuNode> entries) {
    final groups = <PlatformMenuItem>[];
    var run = <PlatformMenuItem>[];
    void flush() {
      if (run.isNotEmpty) {
        groups.add(PlatformMenuItemGroup(members: run));
        run = [];
      }
    }

    for (final entry in entries) {
      switch (entry.kind) {
        case BrowserMenuNodeKind.separator:
          flush();
        case BrowserMenuNodeKind.submenu:
          run.add(
            PlatformMenu(
              label: strings.title(entry),
              menus: children(entry.children),
            ),
          );
        case BrowserMenuNodeKind.command:
          final command = commands[entry.commandId];
          run.add(
            command == null
                ? PlatformMenuItem(label: strings.unavailable(entry.commandId!))
                : command.platform(accelerator: accelerators.add(command.id)),
          );
      }
    }
    if (groups.isEmpty) return run;
    flush();
    return groups;
  }

  return [
    for (final menu in layout.menus)
      PlatformMenu(label: strings.title(menu), menus: children(menu.children)),
  ];
}

/// Both the wide menu bar and compact menu button use the same layout and
/// callback registry as native browser menus. Fixed controls are supplied by
/// the host and are never read from the imported tree.
class ConfigurableBrowserMenu extends StatelessWidget {
  const ConfigurableBrowserMenu({
    super.key,
    required this.layout,
    required this.commands,
    required this.fixedCommands,
    this.preview = false,
    this.inToolbar = false,
  });
  final BrowserMenuLayout layout;
  final Map<String, BrowserMenuCommandBinding> commands;
  final List<BrowserMenuCommandBinding> fixedCommands;
  final bool preview;

  /// Windows displays its application menus inside the top AppBar, not in
  /// a second Material menu row. Other platforms retain the existing layout.
  final bool inToolbar;

  @override
  Widget build(BuildContext context) {
    final strings = BrowserMenuStrings(context);
    Widget command(BrowserMenuCommandBinding binding, String key) =>
        MenuItemButton(
          key: ValueKey(key),
          onPressed: preview ? null : binding.onSelected,
          shortcut: preview ? null : binding.shortcut,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Text(
              binding.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
    // Limit top-level popups to the space below the Windows menu strip.
    // Otherwise Flutter flips a long menu above its anchor and obscures the
    // entire toolbar, which feels like a modal instead of a desktop dropdown.
    final maxPopupHeight = (MediaQuery.sizeOf(context).height - 48 - 16)
        .clamp(120.0, double.infinity)
        .toDouble();
    final toolbarPopupStyle = inToolbar
        ? MenuStyle(
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
          )
        : null;
    final usedAccelerators = <String>{};
    String acceleratorLabel(String label) {
      for (var i = 0; i < label.length; i++) {
        final letter = label[i].toLowerCase();
        if (RegExp(r'[a-z]').hasMatch(letter) &&
            usedAccelerators.add(letter)) {
          return '${label.substring(0, i)}&${label.substring(i)}';
        }
      }
      return label;
    }

    List<Widget> children(
      List<BrowserMenuNode> entries, {
      bool topLevel = false,
    }) => [
      for (final entry in entries)
        switch (entry.kind) {
          BrowserMenuNodeKind.separator => const Divider(height: 8),
          BrowserMenuNodeKind.submenu => SubmenuButton(
            key: ValueKey('browser-menu-${entry.id}'),
            menuStyle: topLevel ? toolbarPopupStyle : null,
            style: topLevel && inToolbar
                ? const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(0, 36)),
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 10),
                    ),
                  )
                : null,
            menuChildren: children(entry.children),
            child: topLevel && inToolbar
                ? MenuAcceleratorLabel(acceleratorLabel(strings.title(entry)))
                : Text(
                    strings.title(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          BrowserMenuNodeKind.command => command(
            commands[entry.commandId] ??
                BrowserMenuCommandBinding(
                  id: entry.commandId!,
                  label: strings.unavailable(entry.commandId!),
                ),
            'browser-menu-entry-${entry.id}',
          ),
        },
    ];
    List<Widget> menusFor({required bool toolbarMode}) => [
      ...children(layout.menus, topLevel: toolbarMode),
      if (fixedCommands.isNotEmpty)
        SubmenuButton(
          key: const ValueKey('browser-menu-controls'),
          menuStyle: toolbarMode ? toolbarPopupStyle : null,
          style: toolbarMode
              ? const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 36)),
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                )
              : null,
          menuChildren: [
            for (final binding in fixedCommands)
              command(binding, 'browser-menu-fixed-${binding.id}'),
          ],
          child: toolbarMode
              ? MenuAcceleratorLabel(
                  acceleratorLabel(strings.text('controls')),
                )
              : Text(strings.text('controls')),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < (inToolbar ? 600 : 650);
        final menus = menusFor(toolbarMode: inToolbar && !compact);
        if (compact) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: MenuAnchor(
              menuChildren: menus,
              builder: (context, controller, _) => TextButton.icon(
                key: const ValueKey('browser-menu-compact'),
                icon: const Icon(Icons.menu, size: 18),
                label: Text(strings.text('menus')),
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          );
        }
        if (inToolbar) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: MenuBar(
              key: const ValueKey('browser-menu-toolbar'),
              style: const MenuStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
                backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                elevation: WidgetStatePropertyAll(0),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
              ),
              children: menus,
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MenuBar(children: menus),
        );
      },
    );
  }
}
