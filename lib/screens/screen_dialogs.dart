// lib/screens/screen_dialogs.dart
//
// Dialog helpers for the file browser screen.
// All functions are top-level, taking BuildContext and WidgetRef as parameters.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../widgets/azure_connection_dialog.dart';
import '../widgets/b2_connection_dialog.dart';
import '../widgets/connection_dialog.dart';
import '../widgets/file_editor_dialog.dart' show showFileEditorDialog;
import '../widgets/preview_pane.dart' show PreviewPane;
import '../l10n/app_localizations.dart';
import '../services/log_service.dart';

const _log = Log('ScreenDialogs');
void showConnectionDialogScreen(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const ConnectionDialog(),
  );
}

/// Directly open the Azure Blob Storage connection dialog.
void showAzureConnectionDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const AzureConnectionDialog(),
  );
}

/// Directly open the Backblaze B2 connection dialog.
void showB2ConnectionDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const B2ConnectionDialog(),
  );
}

void confirmLogoutRiverpod(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Logout'),
      content: const Text('Are you sure you want to logout from Cloud?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: () async {
            await ref.read(authProvider).logout();
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged out successfully')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Logout'),
        ),
      ],
    ),
  );
}

void showKeyboardShortcutsDialog(BuildContext context) =>
    showKeyboardShortcutsHelp(context);

/// Full keyboard shortcut help dialog (F1 or from menu).
void showKeyboardShortcutsHelp(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // F-keys (DC orthodox FM)
            _shortcutRow('F1', 'This help dialog'),
            _shortcutRow('F2', 'Rename (in-place)'),
            _shortcutRow('F3', 'View file (full-screen)'),
            _shortcutRow('F4', 'Edit file (built-in)'),
            _shortcutRow('Shift+F4', 'Open with system editor'),
            _shortcutRow('F5 / Ctrl+C', 'Copy to…'),
            _shortcutRow('Ctrl+R', 'Refresh'),
            _shortcutRow('F6 / Ctrl+X', 'Move to…'),
            _shortcutRow('F7 / Ctrl+N', 'New folder'),
            _shortcutRow('F8 / Delete', 'Delete selected'),
            const Divider(),
            // Navigation
            _shortcutRow('Alt+← / Alt+→', 'Back / Forward (history)'),
            _shortcutRow('Backspace', 'Navigate up'),
            _shortcutRow('Enter', 'Open folder / file'),
            _shortcutRow('Ctrl+Enter', 'Open folder in opposite panel'),
            _shortcutRow('Tab', 'Switch panels'),
            _shortcutRow('Ctrl+G', 'Go to path'),
            _shortcutRow('Ctrl+F', 'Filter files'),
            const Divider(),
            // Selection
            _shortcutRow('Ctrl+A', 'Select all'),
            _shortcutRow('Numpad *', 'Invert selection'),
            _shortcutRow('Numpad +', 'Select by pattern'),
            _shortcutRow('Numpad -', 'Deselect by pattern'),
            _shortcutRow('Space / Insert', 'Mark + advance'),
            _shortcutRow('Shift+↑/↓', 'Extend selection'),
            _shortcutRow('Escape', 'Clear selection / type-ahead'),
            const Divider(),
            // File operations
            _shortcutRow('Ctrl+C', 'Copy to…'),
            _shortcutRow('Ctrl+Z', 'Undo last action'),
            _shortcutRow('Ctrl+Shift+C', 'Copy paths to clipboard'),
            _shortcutRow('Ctrl+Shift+N', 'Copy names to clipboard'),
            _shortcutRow('Ctrl+=', 'Sync opposite panel to here'),
            const Divider(),
            // Sort
            _shortcutRow('Ctrl+F3', 'Sort by name'),
            _shortcutRow('Ctrl+F4', 'Sort by extension'),
            _shortcutRow('Ctrl+F5', 'Sort by date'),
            _shortcutRow('Ctrl+F6', 'Sort by size'),
            _shortcutRow('Ctrl+.', 'Toggle hidden files'),
            _shortcutRow('Ctrl+B', 'Toggle bookmark for current folder'),
            _shortcutRow('Ctrl+I / Alt+Enter', 'File properties'),
            const Divider(),
            // View / Tabs
            _shortcutRow('Ctrl+1', 'Brief view mode'),
            _shortcutRow('Ctrl+2', 'Full view mode'),
            _shortcutRow('Ctrl+3', 'Tree view mode'),
            _shortcutRow('Ctrl+T', 'New tab'),
            _shortcutRow('Ctrl+W', 'Close tab'),
            _shortcutRow('Ctrl+Tab', 'Next tab'),
            _shortcutRow('Ctrl+Shift+Tab', 'Previous tab'),
            _shortcutRow('Ctrl+Shift+P', 'Command palette'),
            const Divider(),
            // Transfer
            _shortcutRow('Ctrl+U', 'Upload'),
            _shortcutRow('Ctrl+D', 'Download'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}

Widget _shortcutRow(String keys, String description) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(keys, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ),
        Expanded(child: Text(description)),
      ],
    ),
  );
}

void uploadSelected(BuildContext context, WidgetRef ref) {
  final panel = ref.read(panelProvider(PanelSide.local));
  if (panel.selection.isEmpty) return;
  ref.read(transferProvider).uploadFiles(panel.selection.toList());
}

void downloadSelected(BuildContext context, WidgetRef ref) {
  final panel = ref.read(panelProvider(PanelSide.remote));
  if (panel.selection.isEmpty) return;
  ref.read(transferProvider).downloadFiles(panel.selection.toList());
}

void confirmDeleteSelected(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  _log.debug('confirmDeleteSelected: ${panel.selection.length} items, side=${activePanel.name}');
  if (panel.selection.isEmpty) return;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Delete'),
      content: Text('Delete ${panel.selection.length} item(s)?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () async {
            final files = panel.selection.toList();
            await panel.deleteFiles(files);
            if (context.mounted) {
              Navigator.pop(context);
              _showUndoSnackBar(
                context,
                ref,
                activePanel,
                'Deleted ${files.length} item(s)',
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

void showRenameDialog(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  if (panel.selection.length != 1) return;

  final file = panel.selection.first;
  final controller = TextEditingController(text: file.name);

  Future<void> doRename(String value) async {
    if (value.isNotEmpty && value != file.name) {
      await panel.renameFile(file, value);
      if (context.mounted) {
        Navigator.pop(context);
        _showUndoSnackBar(context, ref, activePanel, 'Renamed "${file.name}" to "$value"');
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'New name', border: OutlineInputBorder()),
        autofocus: true,
        onSubmitted: doRename,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () => doRename(controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

/// F3: Open cursor item in a full-screen internal viewer dialog.
void viewSelectedFile(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final target = panel.selection.isEmpty ? panel.cursorItem : panel.selection.first;
  if (target == null || target.isFolder) return;
  // Show as full-screen dialog (DC-style F3 viewer)
  showDialog(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(target.name),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(ctx),
          ),
        ),
        body: PreviewPane(file: target, side: activePanel),
      ),
    ),
  );
}

/// F4: Open cursor item in the file editor.
void editSelectedFile(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final target = panel.selection.isEmpty ? panel.cursorItem : panel.selection.first;
  if (target == null || target.isFolder) return;
  showFileEditorDialog(context, ref, target, activePanel);
}

void showCopyDialogFromSelection(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  if (panel.selection.isEmpty) return;

  // On web: if the opposite panel has a local folder open, copy there.
  // Otherwise download via browser.
  if (kIsWeb) {
    final opposite = activePanel == PanelSide.local ? PanelSide.remote : PanelSide.local;
    final oppositePanel = ref.read(panelProvider(opposite));
    final oppPath = oppositePanel.currentPath;
    _log.debug('web copy: active=${activePanel.name} oppPath=$oppPath selection=${panel.selection.length}');

    // If the opposite panel has a local folder open (not just '/'), copy there.
    if (oppPath.length > 1) {
      panel.copyFiles(panel.selection.toList(), oppPath).then((_) {
        oppositePanel.refresh();
      });
      return;
    }
    // Fallback: download via browser.
    _downloadFilesOnWeb(ref, panel.selection.toList());
    return;
  }

  _showPathDialog(context, ref, activePanel, panel, panel.selection.toList(), 'Copy', panel.copyFiles);
}

/// Download local files via browser on web.
void _downloadFilesOnWeb(WidgetRef ref, List<FileItem> files) {
  final localSvc = ref.read(localFileServiceProvider);
  for (final file in files) {
    if (file.isFolder || file.path == null) continue;
    localSvc.readFile(file.path!, fileItem: file).then((bytes) {
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', file.name)
        ..click();
      html.Url.revokeObjectUrl(url);
    }).catchError((_) {});
  }
}

void showMoveDialogFromSelection(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  _log.debug('showMoveDialogFromSelection: ${panel.selection.length} items, side=${activePanel.name}');
  if (panel.selection.isEmpty) return;

  // On web: move to opposite panel's directory automatically.
  if (kIsWeb) {
    final opposite = activePanel == PanelSide.local ? PanelSide.remote : PanelSide.local;
    final oppositePanel = ref.read(panelProvider(opposite));
    final oppPath = oppositePanel.currentPath;
    _log.debug('web move: active=${activePanel.name} oppPath=$oppPath selection=${panel.selection.length}');

    if (oppPath.length > 1) {
      panel.moveFiles(panel.selection.toList(), oppPath).then((_) {
        oppositePanel.refresh();
      });
      return;
    }
  }

  _showPathDialog(context, ref, activePanel, panel, panel.selection.toList(), 'Move', panel.moveFiles);
}

void _showPathDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide activePanel,
  PanelNotifier panel,
  List<FileItem> files,
  String operation,
  Future<void> Function(List<FileItem>, String) action,
) {
  final controller = TextEditingController(text: panel.currentPath);

  Future<void> doAction(String value) async {
    if (value.isNotEmpty) {
      await action(files, value);
      // Refresh opposite panel in case the target path is there.
      final opposite = activePanel == PanelSide.local ? PanelSide.remote : PanelSide.local;
      ref.read(panelProvider(opposite)).refresh();
      if (context.mounted) {
        Navigator.pop(context);
        _showUndoSnackBar(
          context,
          ref,
          activePanel,
          '${operation}d ${files.length} item(s) to $value',
        );
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$operation ${files.length} item(s)'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Target path', border: OutlineInputBorder()),
        autofocus: true,
        onSubmitted: doAction,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () => doAction(controller.text),
          child: Text(operation),
        ),
      ],
    ),
  );
}

void showCreateFolderDialog(BuildContext context, WidgetRef ref, PanelSide side) {
  final panel = ref.read(panelProvider(side));
  final controller = TextEditingController();

  Future<void> doCreate(String value) async {
    if (value.isNotEmpty) {
      await panel.createFolder(value);
      if (context.mounted) {
        Navigator.pop(context);
        _showUndoSnackBar(context, ref, side, 'Created folder "$value"');
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New Folder'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Folder name', border: OutlineInputBorder()),
        autofocus: true,
        onSubmitted: doCreate,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () => doCreate(controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

void showReceivedFilesDialog(BuildContext context, List<String> files) {
  // This dialog is used in non-Riverpod context (system callback).
  // Keep it simple — the caller handles the upload.
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Received Files'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upload ${files.length} file(s) to Cloud?'),
          const SizedBox(height: 8),
          ...files.take(5).map((path) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${p.basename(path)}', style: const TextStyle(fontSize: 12)),
              )),
          if (files.length > 5)
            Text('... and ${files.length - 5} more', style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () {
            // Will be wired when receive service is connected to Riverpod
            Navigator.pop(context);
          },
          child: const Text('Upload'),
        ),
      ],
    ),
  );
}

void showGoToDialog(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final controller = TextEditingController(text: panel.currentPath);

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Go to Path'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Path',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.folder_open),
        ),
        onSubmitted: (value) {
          if (value.isNotEmpty) {
            panel.navigateToPath(value);
            Navigator.pop(ctx);
          }
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () {
            if (controller.text.isNotEmpty) {
              panel.navigateToPath(controller.text);
              Navigator.pop(ctx);
            }
          },
          child: const Text('Go'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Undo SnackBar helper
// ---------------------------------------------------------------------------

/// Show a SnackBar confirming [message] with an "Undo" action button.
///
/// Pressing "Undo" undoes the most-recent action in the history for [side].
void _showUndoSnackBar(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
  String message,
) {
  final historyNotifier = ref.read(actionHistoryProvider.notifier);
  final last = historyNotifier.lastAction;
  final canUndo = last != null && historyNotifier.canUndo(last);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      action: canUndo
          ? SnackBarAction(
              label: 'Undo',
              onPressed: () {
                final undoCtx = _buildUndoCtx(ref, side);
                historyNotifier.undo(last.id, undoCtx).then((result) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.message),
                      duration: const Duration(seconds: 3),
                      backgroundColor: result.success
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  );
                  if (result.success) {
                    ref.read(panelProvider(side)).refresh();
                  }
                });
              },
            )
          : null,
    ),
  );
}

/// Build an [UndoContext] for [side] using the current auth client.
UndoContext _buildUndoCtx(WidgetRef ref, PanelSide side) {
  if (side == PanelSide.local) return const UndoContext();
  final client = ref.read(authProvider).client;
  return UndoContext(
    remoteRename: (currentPath, name) => client.renamePath(currentPath, name),
    remoteMove: (currentPath, targetDir) => client.movePath(currentPath, targetDir),
    remoteDelete: (path) => client.deletePath(path),
  );
}
