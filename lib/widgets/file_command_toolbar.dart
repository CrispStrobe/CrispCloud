import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/command_extension.dart';
import '../models/panel_side.dart';
import '../providers/command_extension_provider.dart';
import '../providers/custom_command_provider.dart';
import '../providers/panel_provider.dart';
import '../providers/plugin_provider.dart';
import 'command_extension_actions.dart';
import 'custom_command_dialog.dart';

/// The live panel host for configured custom commands and extension actions.
/// Managers remain available in Settings when this empty bar is hidden.
class FileCommandToolbar extends ConsumerWidget {
  const FileCommandToolbar({super.key, required this.side});
  final PanelSide side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(panelProvider(side));
    final commands = ref.watch(customToolbarCommandServiceProvider).commands;
    final extensions = ref.watch(commandExtensionStoreProvider);
    final plugins = ref.watch(pluginRegistryProvider);
    try {
      captureExtensionContext(ref, side);
    } on StateError {
      return const SizedBox.shrink();
    }
    final actions = extensions.actions(CommandExtensionCapability.toolbar);
    final buttons = plugins
        .getToolbarButtons()
        .where((button) => button.onPressed != null)
        .toList();
    if (commands.isEmpty && actions.isEmpty && buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      key: const ValueKey('file-command-toolbar'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            for (final command in commands)
              TextButton.icon(
                key: ValueKey('custom-toolbar-${command.id}'),
                icon: const Icon(Icons.terminal, size: 18),
                label: Text(command.label),
                onPressed: command.requiresReview
                    ? () => showCustomCommandsDialog(context, ref, side)
                    : () => showCustomCommandRunDialog(
                        context,
                        ref,
                        side,
                        command,
                      ),
              ),
            for (final action in actions)
              Tooltip(
                message: action.extensionName,
                child: TextButton.icon(
                  key: ValueKey(
                    'extension-toolbar-${action.extensionId}-${action.command.id}',
                  ),
                  icon: const Icon(Icons.extension, size: 18),
                  label: Text(action.command.label),
                  onPressed: () =>
                      showCommandExtensionRunDialog(context, ref, side, action),
                ),
              ),
            for (final button in buttons)
              Tooltip(
                message: button.tooltip,
                child: TextButton.icon(
                  key: ValueKey('compiled-extension-toolbar-${button.id}'),
                  icon: const Icon(Icons.extension_outlined, size: 18),
                  label: Text(button.label),
                  onPressed: () =>
                      runCompiledToolbarAction(context, ref, side, button),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
