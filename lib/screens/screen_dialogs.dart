// lib/screens/screen_dialogs.dart
//
// Dialog helpers for the file browser screen.
// All functions are top-level, taking BuildContext and WidgetRef as parameters.

import 'dart:async';

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
import '../widgets/file_operation_dialog.dart';
import '../widgets/batch_rename_dialog.dart' show showBatchRenameDialog;
import '../services/file_operation_service.dart';
import '../widgets/internal_viewer_dialog.dart'
    show InternalViewerAction, showInternalViewer;
import '../l10n/app_localizations.dart';
import '../l10n/image_editor_strings.dart';
import '../services/image_edit_session.dart' show isEditableImageFileName;
import '../services/log_service.dart';

const _log = Log('ScreenDialogs');

/// Explicit selection, or the cursor item when nothing is marked. This mirrors
/// Total Commander: F5/F6/F8 operate on the item under the cursor when there
/// is no multi-selection.
List<FileItem> _selectedOrCursor(PanelNotifier panel) {
  if (panel.selection.isNotEmpty) return panel.selection.toList();
  final cursor = panel.cursorItem;
  if (cursor != null && cursor.name != '..') return <FileItem>[cursor];
  return const <FileItem>[];
}

void showConnectionDialogScreen(BuildContext context) {
  showDialog(context: context, builder: (context) => const ConnectionDialog());
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
            _shortcutRow('F2 / Shift+F6', 'Rename (in-place)'),
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
            _shortcutRow('Backspace', 'Navigate up / leave archive'),
            _shortcutRow('Esc (in archive)', 'Exit archive'),
            _shortcutRow('Enter', 'Open folder / file'),
            _shortcutRow('Ctrl+Enter', 'Open item in the other panel'),
            _shortcutRow('Ctrl+← / Ctrl+→', 'Open item in left / right panel'),
            _shortcutRow('Tab', 'Switch panels'),
            _shortcutRow('Ctrl+G / Ctrl+L', 'Go to path'),
            _shortcutRow('Alt+F7', 'Search all files'),
            _shortcutRow('Ctrl+F', 'Filter files'),
            _shortcutRow(
              'Type letters',
              'Quick search / filter (see Settings)',
            ),
            _shortcutRow('↑ / ↓ while searching', 'Previous / next match'),
            const Divider(),
            // Selection
            _shortcutRow('Ctrl+A', 'Select all'),
            _shortcutRow('Numpad *', 'Invert selection'),
            _shortcutRow('Numpad +', 'Select by wildcard or regex'),
            _shortcutRow('Numpad -', 'Deselect by wildcard or regex'),
            _shortcutRow('Space / Insert', 'Mark + advance'),
            _shortcutRow('Numpad 5', 'Select all'),
            _shortcutRow('Shift+↑/↓', 'Extend selection'),
            _shortcutRow('Escape', 'Clear selection / type-ahead'),
            const Divider(),
            // File operations
            _shortcutRow('Ctrl+C', 'Copy with options…'),
            _shortcutRow('Ctrl+M', 'Multi-Rename'),
            _shortcutRow('Ctrl+Shift+L', 'Import file list'),
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
            _shortcutRow('Ctrl+. / Ctrl+H', 'Toggle hidden files'),
            _shortcutRow('Ctrl+B', 'Toggle bookmark for current folder'),
            _shortcutRow('Ctrl+I / Alt+Enter', 'File properties'),
            _shortcutRow('Shift+F10', 'Context menu'),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
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
          child: Text(
            keys,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
        Expanded(child: Text(description)),
      ],
    ),
  );
}

void uploadSelected(BuildContext context, WidgetRef ref) {
  final panel = ref.read(panelProvider(PanelSide.local));
  if (panel.selection.isEmpty) return;
  if (panel.showingSearchResults) {
    showFileOperationDialog(context, ref, PanelSide.local,
        panel.selection.toList(), kind: FileOperationKind.copy);
    return;
  }
  ref.read(transferProvider).uploadFiles(panel.selection.toList());
}

void downloadSelected(BuildContext context, WidgetRef ref) {
  final panel = ref.read(panelProvider(PanelSide.remote));
  if (panel.selection.isEmpty) return;
  if (panel.showingSearchResults) {
    showFileOperationDialog(context, ref, PanelSide.remote,
        panel.selection.toList(), kind: FileOperationKind.copy);
    return;
  }
  ref.read(transferProvider).downloadFiles(panel.selection.toList());
}

void confirmDeleteSelected(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final targets = _selectedOrCursor(panel);
  _log.debug(
    'confirmDeleteSelected: ${targets.length} items, side=${activePanel.name}',
  );
  if (targets.isEmpty) return;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Delete'),
      content: Text('Delete ${targets.length} item(s)?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: () async {
            final files = targets;
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
  final targets = _selectedOrCursor(panel);
  if (targets.length != 1) return;

  final file = targets.first;
  final controller = TextEditingController(text: file.name);

  Future<void> doRename(String value) async {
    if (value.isNotEmpty && value != file.name) {
      await panel.renameFile(file, value);
      if (context.mounted) {
        Navigator.pop(context);
        _showUndoSnackBar(
          context,
          ref,
          activePanel,
          'Renamed "${file.name}" to "$value"',
        );
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'New name',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: doRename,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
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
  // TC/DC view the file under the cursor, not the selection set.
  final target =
      panel.cursorItem ??
      (panel.selection.isNotEmpty ? panel.selection.first : null);
  if (target == null || target.isFolder) return;
  // Full-screen DC-style viewer: text/ASCII/binary/hex/image/markdown/PDF/
  // media/font/CSV/office/archive with streaming hex for huge local files.
  unawaited(_viewFile(context, ref, panel, activePanel, target));
}

Future<void> _viewFile(
  BuildContext context,
  WidgetRef ref,
  PanelNotifier panel,
  PanelSide side,
  FileItem target,
) async {
  try {
    InternalViewerAction action = InternalViewerAction.close;
    if (panel.isInArchive) {
      // Archive members have no host-file path; extract them first and hand
      // the bytes to the viewer. This is what makes F3 work inside ZIPs.
      final bytes = await panel.readArchiveMember(target);
      if (!context.mounted) return;
      await showInternalViewer(
        context,
        file: target,
        side: side,
        bytesOverride: bytes,
        displayName: target.name,
      );
    } else {
      action = await showInternalViewer(context, file: target, side: side);
    }
    if (action == InternalViewerAction.edit && context.mounted) {
      await _editFile(context, ref, panel, side, target);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cannot view ${target.name}: $e')));
    }
  } finally {
    // Keep the file selected and the panel keyboard-focused after the viewer
    // closes, so F3/F4 can be pressed again immediately.
    panel.restoreCursorAndFocus(target);
  }
}

/// F4: Open cursor item in the file editor.
void editSelectedFile(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final target =
      panel.cursorItem ??
      (panel.selection.isNotEmpty ? panel.selection.first : null);
  if (target == null || target.isFolder) return;
  unawaited(_editFile(context, ref, panel, activePanel, target));
}

Future<void> _editFile(
  BuildContext context,
  WidgetRef ref,
  PanelNotifier panel,
  PanelSide side,
  FileItem target,
) async {
  try {
    if (panel.isInArchive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditableImageFileName(target.name)
                  ? context.imageTr(
                      'Extract this file from its archive or container before editing.',
                    )
                  : 'Editing files inside an archive is not supported. '
                        'Extract the file first.',
            ),
          ),
        );
      }
      return;
    }
    await showFileEditorDialog(context, ref, target, side);
  } finally {
    panel.restoreCursorAndFocus(target);
  }
}

void showCopyDialogFromSelection(BuildContext context, WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final files = _selectedOrCursor(ref.read(panelProvider(side)));
  showFileOperationDialog(
    context,
    ref,
    side,
    files,
    kind: FileOperationKind.copy,
  );
}

void showMoveDialogFromSelection(BuildContext context, WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final files = _selectedOrCursor(ref.read(panelProvider(side)));
  showFileOperationDialog(
    context,
    ref,
    side,
    files,
    kind: FileOperationKind.move,
  );
}

void showMultiRenameFromSelection(BuildContext context, WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  final files = panel.selection.isEmpty
      ? _selectedOrCursor(panel)
      : (panel.displayedFiles ?? const <FileItem>[])
            .where((item) => panel.selection.contains(item))
            .toList();
  if (files.isNotEmpty) showBatchRenameDialog(context, ref, side, files);
}

void showCreateFolderDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) {
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
        decoration: const InputDecoration(
          labelText: 'Folder name',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: doCreate,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
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
          ...files
              .take(5)
              .map(
                (path) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${p.basename(path)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          if (files.length > 5)
            Text(
              '... and ${files.length - 5} more',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
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
  // Select the current path so typing replaces it instead of appending
  // (which produced paths like .../Downloads/Users/me/Downloads).
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );

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
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
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
    remoteMove: (currentPath, targetDir) =>
        client.movePath(currentPath, targetDir),
    remoteDelete: (path) => client.deletePath(path),
  );
}
