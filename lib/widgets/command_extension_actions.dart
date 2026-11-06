import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/command_extension.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/command_extension_provider.dart';
import '../providers/custom_command_provider.dart';
import '../providers/panel_provider.dart';
import '../providers/plugin_provider.dart';
import '../services/custom_toolbar_command_service.dart';
import 'custom_command_dialog.dart';

/// Captures the exact clicked/selected rows. Raw provider paths are never passed
/// to an external program or a path-only first-party callback.
CommandInvocationContext captureExtensionContext(
  WidgetRef ref,
  PanelSide side, {
  List<FileItem>? files,
  bool Function()? actionIsCurrent,
}) {
  final panel = ref.read(panelProvider(side));
  final selected = List<FileItem>.of(
    files ??
        (panel.selection.isNotEmpty
            ? panel.selection.toList()
            : [
                if (panel.cursorItem case final item? when item.name != '..')
                  item,
              ]),
  );
  final origin = selected.isEmpty
      ? panel.captureCurrentOrigin()
      : panel.captureOperationOrigin(selected);
  if (selected.any((file) => file.path == null || file.name == '..')) {
    throw StateError('Commands require verified absolute local paths.');
  }
  PanelFileOrigin? target;
  try {
    final other = ref
        .read(
          panelProvider(
            side == PanelSide.local ? PanelSide.remote : PanelSide.local,
          ),
        )
        .captureCurrentOrigin();
    if (other.storageReference.isLocal) target = other;
  } on StateError {
    // The opposite panel is required only for a command using {TARGET}.
  }
  final captured = CommandInvocationContext(
    storage: origin.storageReference,
    currentPath: origin.source.currentPath,
    selectedPaths: selected.map((file) => file.path!).toList(),
    isCurrent: () => origin.isCurrent && (actionIsCurrent?.call() ?? true),
    targetPath: target?.source.currentPath,
    targetIsCurrent: target == null ? null : () => target!.isCurrent,
  );
  captured.validate();
  return captured;
}

void _report(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        CommanderStrings.translate(context, 'Command failed: {0}', [error]),
      ),
    ),
  );
}

Future<void> showCommandExtensionRunDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  CommandExtensionAction action, {
  CommandInvocationContext? captured,
}) async {
  try {
    final store = ref.read(commandExtensionStoreProvider);
    if (!store.isActionCurrent(action)) {
      throw StateError('This extension action changed. Open it again.');
    }
    final origin =
        captured ??
        captureExtensionContext(
          ref,
          side,
          actionIsCurrent: () => store.isActionCurrent(action),
        );
    // Also wrap externally supplied menu snapshots. The runner revalidates this
    // guard immediately before spawning, after the review has been displayed.
    final guarded = CommandInvocationContext(
      storage: origin.storage,
      currentPath: origin.currentPath,
      selectedPaths: origin.selectedPaths,
      isCurrent: () => origin.isCurrent() && store.isActionCurrent(action),
      targetPath: origin.targetPath,
      targetIsCurrent: origin.targetIsCurrent,
    );
    final service = ref.read(customToolbarCommandServiceProvider);
    final prepared = service.prepare(action.command, guarded);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommandRunDialog(
        command: action.command,
        captured: guarded,
        prepared: prepared,
        service: service,
      ),
    );
  } catch (error) {
    if (context.mounted) _report(context, error);
  }
}

/// Includes command manifests and trusted compiled callbacks. Both use the
/// exact supplied rows, even when a context menu was opened on an unmarked row.
/// Unverified/cloud rows are excluded before any path-only plugin hook runs.
List<PopupMenuEntry<T>> buildCommandExtensionMenuItems<T>(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  List<FileItem> files,
) {
  final CommandInvocationContext captured;
  try {
    captured = captureExtensionContext(ref, side, files: files);
  } on StateError {
    return const [];
  }
  final result = <PopupMenuEntry<T>>[];
  final actions = ref
      .read(commandExtensionStoreProvider)
      .actions(CommandExtensionCapability.contextMenu);
  for (final action in actions) {
    result.add(
      PopupMenuItem<T>(
        key: ValueKey(
          'extension-menu-${action.extensionId}-${action.command.id}',
        ),
        onTap: () => unawaited(
          Future<void>.delayed(Duration.zero, () async {
            if (context.mounted) {
              await showCommandExtensionRunDialog(
                context,
                ref,
                side,
                action,
                captured: captured,
              );
            }
          }),
        ),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.extension, size: 20),
          title: Text(
            action.command.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            action.extensionName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
  final pluginItems = ref
      .read(pluginRegistryProvider)
      .getContextMenuItems(captured.selectedPaths);
  for (final item in pluginItems) {
    if (!item.enabled || item.onSelected == null) continue;
    result.add(
      PopupMenuItem<T>(
        key: ValueKey('compiled-extension-menu-${item.id}'),
        onTap: () => unawaited(
          Future<void>.delayed(Duration.zero, () {
            if (!context.mounted) return;
            try {
              captured.validate();
              item.onSelected!(captured.selectedPaths);
            } catch (error) {
              _report(context, error);
            }
          }),
        ),
        child: Row(
          children: [
            const Icon(Icons.extension, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
  return result.isEmpty ? result : [const PopupMenuDivider(), ...result];
}

void runCompiledToolbarAction(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  PluginToolbarButton button,
) {
  try {
    final captured = captureExtensionContext(ref, side);
    captured.validate();
    button.onPressed?.call(captured.selectedPaths);
  } catch (error) {
    _report(context, error);
  }
}
