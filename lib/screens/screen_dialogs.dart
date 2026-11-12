import '../widgets/file_delete_dialog.dart';
// lib/screens/screen_dialogs.dart
//
// Dialog helpers for the file browser screen.
// All functions are top-level, taking BuildContext and WidgetRef as parameters.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../widgets/azure_connection_dialog.dart';
import '../widgets/b2_connection_dialog.dart';
import '../widgets/connection_dialog.dart';
import '../widgets/editor_chooser_dialog.dart';
import '../widgets/file_editor_dialog.dart' show showFileEditorDialog;
import '../widgets/file_operation_dialog.dart';
import '../widgets/archive_workspace_dialog.dart';
import '../widgets/batch_rename_dialog.dart' show showBatchRenameDialog;
import '../widgets/file_name_dialog.dart';
import '../services/file_operation_service.dart';
import '../services/filen_config_service.dart';
import '../widgets/internal_viewer_dialog.dart'
    show InternalViewerAction, showInternalViewer;
import '../l10n/app_localizations.dart';
import '../l10n/commander_strings.dart';
import '../l10n/command_strings.dart';
import '../l10n/screen_dialog_strings.dart';
import '../l10n/shortcut_strings.dart';
import '../l10n/undo_presentation.dart';
import '../l10n/workspace_ux_strings.dart';
import '../services/keyboard_shortcut_service.dart';
import '../widgets/keyboard_shortcut_dialog.dart';
import '../widgets/help_guide_dialog.dart';
import '../l10n/help_guide_strings.dart';

/// Explicit selection, or the cursor item when nothing is marked. File actions
/// operate on that item when there is no multi-selection.
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
  // The command palette closes its own route before this dialog is used.
  // Capture the root-scoped notifier while its WidgetRef is still usable.
  final auth = ref.read(authProvider);
  String? cleanupError;
  var busy = false;
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(ScreenDialogStrings(context).text('logoutTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ScreenDialogStrings(context).text('logoutConfirm')),
            if (cleanupError != null) ...[
              const SizedBox(height: 12),
              Text(
                cleanupError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await auth.logout();
                    } on FilenCredentialDeletionFailure catch (error) {
                      if (context.mounted) {
                        setState(() {
                          cleanupError = error.toString();
                          busy = false;
                        });
                      }
                      return;
                    } catch (_) {
                      if (context.mounted) setState(() => busy = false);
                      rethrow;
                    }
                    if (context.mounted) {
                      final messenger = ScaffoldMessenger.of(context);
                      final message = CommandStrings(context).text('loggedOut');
                      Navigator.pop(context);
                      messenger.showSnackBar(SnackBar(content: Text(message)));
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(
              cleanupError == null
                  ? AppLocalizations.of(context)!.logout
                  : AppLocalizations.of(context)!.retry,
            ),
          ),
        ],
      ),
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
      title: Text(AppLocalizations.of(context)!.keyboardShortcuts),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File action keys.
            _shortcutRow('F1', 'This help dialog'),
            _shortcutRow('F2 / Shift+F6', 'Rename (in-place)'),
            _shortcutRow('F3', 'View file (full-screen)'),
            _shortcutRow('F4', 'Edit file (built-in)'),
            _shortcutRow('Shift+F4', 'Choose editor (text, hex, system)'),
            _shortcutRow('F5', 'Copy with options…'),
            _shortcutRow('Ctrl+R', 'Refresh'),
            _shortcutRow('F6', 'Move with options…'),
            _shortcutRow('F7 / Ctrl+N', 'New folder'),
            _shortcutRow('F8 / Delete', 'Delete selected'),
            const Divider(),
            // Navigation
            _shortcutRow('Alt+← / Alt+→', 'Back / Forward (history)'),
            _shortcutRow('Backspace', 'Navigate up / leave archive'),
            _shortcutRow(
              'Esc (${ShortcutStrings(context).extra('archive')})',
              'Exit archive',
            ),
            _shortcutRow('Enter', 'Open folder / file'),
            _shortcutRow('Ctrl+Enter', 'Open item in the other panel'),
            _shortcutRow('Ctrl+← / Ctrl+→', 'Open item in left / right panel'),
            _shortcutRow('Tab', 'Switch panels'),
            _shortcutRow('Ctrl+G / Ctrl+L', 'Go to path'),
            _shortcutRow('Alt+F7', 'Search all files'),
            _shortcutRow('Ctrl+F', 'Filter files'),
            _shortcutRow(
              ShortcutStrings(context).keyLabel('type'),
              'Quick search / filter (see Settings)',
            ),
            _shortcutRow(
              ShortcutStrings(context).keyLabel('arrows'),
              'Previous / next match',
            ),
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
            _shortcutRow('Ctrl+C / Ctrl+X', 'Copy / cut files to clipboard'),
            _shortcutRow('Ctrl+V', 'Paste files with options…'),
            _shortcutRow('Ctrl+M', 'Multi-Rename'),
            _shortcutRow('Ctrl+Shift+L', 'Import file list'),
            _shortcutRow('Ctrl+Z', 'Undo last action'),
            _shortcutRow('Ctrl+Shift+C', 'Copy paths to clipboard'),
            _shortcutRow('Ctrl+Shift+N', 'Copy names to clipboard'),
            _shortcutRow('Ctrl+=', 'Sync opposite panel to here'),
            const Divider(),
            // Sort
            _shortcutRow('Ctrl+F3', ShortcutStrings(context).description(30)),
            _shortcutRow('Ctrl+F4', ShortcutStrings(context).description(31)),
            _shortcutRow('Ctrl+F5', ShortcutStrings(context).description(32)),
            _shortcutRow('Ctrl+F6', ShortcutStrings(context).description(33)),
            _shortcutRow(
              'Ctrl+. / Ctrl+H',
              ShortcutStrings(context).description(34),
            ),
            _shortcutRow('Ctrl+B', ShortcutStrings(context).description(35)),
            _shortcutRow(
              'Ctrl+I / Alt+Enter',
              ShortcutStrings(context).description(36),
            ),
            _shortcutRow(
              'Shift+F10',
              ShortcutStrings(context).extra('contextMenu'),
            ),
            const Divider(),
            // View / Tabs
            _shortcutRow('Ctrl+1', ShortcutStrings(context).description(37)),
            _shortcutRow('Ctrl+2', ShortcutStrings(context).description(38)),
            _shortcutRow('Ctrl+3', ShortcutStrings(context).description(39)),
            _shortcutRow('Ctrl+T', ShortcutStrings(context).description(40)),
            _shortcutRow('Ctrl+W', ShortcutStrings(context).description(41)),
            _shortcutRow('Ctrl+Tab', ShortcutStrings(context).description(42)),
            _shortcutRow(
              'Ctrl+Shift+Tab',
              ShortcutStrings(context).description(43),
            ),
            _shortcutRow(
              'Ctrl+Shift+P',
              ShortcutStrings(context).description(44),
            ),
            const Divider(),
            // Transfer
            _shortcutRow('Ctrl+U', context.commanderTr('Swap Panels')),
            _shortcutRow('Ctrl+D', ShortcutStrings(context).description(46)),
            _shortcutRow(
              'Ctrl+Shift+T',
              WorkspaceUxStrings(context).text('reopen'),
            ),
            _shortcutRow('Ctrl+Alt+P', context.commanderTr('Toggle Preview')),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('keyboard-help-user-guide'),
          onPressed: () =>
              showUserGuide(context, topicId: 'keyboard-shortcuts'),
          child: Text(HelpGuideStrings(context).text('title')),
        ),
        TextButton(
          onPressed: () => showKeyboardShortcutSettings(context),
          child: Text(WorkspaceUxStrings(context).text('customize')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    ),
  );
}

Widget _shortcutRow(String keys, String description) => Consumer(
  builder: (context, ref, _) {
    ref.watch(shortcutBindingsProvider);
    final service = ref.watch(keyboardShortcutServiceProvider);
    String key(ShortcutAction action) => service.browserDisplay(action);
    String withAlias(ShortcutAction action, String alias) =>
        service.isCustomized(action) ? key(action) : '${key(action)} / $alias';
    final liveKeys = switch (keys) {
      'F2 / Shift+F6' => '${key(ShortcutAction.rename)} / Shift+F6',
      'F3' => key(ShortcutAction.preview),
      'F4' => key(ShortcutAction.edit),
      'F5' => key(ShortcutAction.copyWithOptions),
      'F6' => key(ShortcutAction.moveWithOptions),
      'F7 / Ctrl+N' => withAlias(ShortcutAction.newFolder, 'Ctrl+N'),
      'F8 / Delete' => withAlias(ShortcutAction.delete, 'F8'),
      'Alt+← / Alt+→' =>
        '${key(ShortcutAction.back)} / ${key(ShortcutAction.forward)}',
      'Backspace' => key(ShortcutAction.up),
      'Tab' => key(ShortcutAction.switchPanel),
      'Ctrl+G / Ctrl+L' => withAlias(ShortcutAction.goToFolder, 'Ctrl+L'),
      'Alt+F7' => key(ShortcutAction.search),
      'Ctrl+F' => key(ShortcutAction.filter),
      'Ctrl+A' => key(ShortcutAction.selectAll),
      'Numpad +' => key(ShortcutAction.findPattern),
      'Ctrl+C / Ctrl+X' =>
        '${key(ShortcutAction.copy)} / ${key(ShortcutAction.cut)}',
      'Ctrl+V' => key(ShortcutAction.paste),
      'Ctrl+M' => key(ShortcutAction.multiRename),
      'Ctrl+Z' => key(ShortcutAction.undo),
      'Ctrl+R' => key(ShortcutAction.refresh),
      'Ctrl+F3' => key(ShortcutAction.sortByName),
      'Ctrl+F4' => key(ShortcutAction.sortByExtension),
      'Ctrl+F5' => key(ShortcutAction.sortByDate),
      'Ctrl+F6' => key(ShortcutAction.sortBySize),
      'Ctrl+. / Ctrl+H' => withAlias(ShortcutAction.toggleHidden, 'Ctrl+H'),
      'Ctrl+B' => key(ShortcutAction.bookmark),
      'Ctrl+T' => key(ShortcutAction.newTab),
      'Ctrl+W' => key(ShortcutAction.closeTab),
      'Ctrl+Tab' => key(ShortcutAction.nextTab),
      'Ctrl+Shift+Tab' => key(ShortcutAction.prevTab),
      'Ctrl+Shift+P' => key(ShortcutAction.commandPalette),
      'Ctrl+Shift+T' => key(ShortcutAction.reopenClosedTab),
      'Ctrl+Alt+P' => key(ShortcutAction.togglePreview),
      _ => keys,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              liveKeys,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(ShortcutStrings(context).descriptionFor(description)),
          ),
        ],
      ),
    );
  },
);

void uploadSelected(BuildContext context, WidgetRef ref) {
  final panel = ref.read(panelProvider(PanelSide.local));
  if (panel.selection.isEmpty) return;
  showFileOperationDialog(
    context,
    ref,
    PanelSide.local,
    panel.selection.toList(),
    kind: FileOperationKind.copy,
  );
}

void downloadSelected(BuildContext context, WidgetRef ref) {
  final panel = ref.read(panelProvider(PanelSide.remote));
  if (panel.selection.isEmpty) return;
  showFileOperationDialog(
    context,
    ref,
    PanelSide.remote,
    panel.selection.toList(),
    kind: FileOperationKind.copy,
  );
}

void confirmDeleteSelected(BuildContext context, WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  showFileDeleteDialog(context, ref, side, _selectedOrCursor(panel));
}

Future<void> showRenameDialog(BuildContext context, WidgetRef ref) async {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  var targets = _selectedOrCursor(panel);
  if (targets.length != 1) return;
  try {
    targets = await panel.prepareOperationFiles(targets);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
    return;
  }
  if (!context.mounted) return;
  final file = targets.first;
  final name = await showCapturedRenameDialog(context, panel, file);
  if (name != null && name != file.name && context.mounted) {
    _showUndoSnackBar(
      context,
      ref,
      activePanel,
      context.commanderTr('Renamed "{0}" to "{1}"', [file.name, name]),
    );
  }
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
  var viewedFile = target;
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
      action = await showInternalViewer(
        context,
        file: target,
        side: side,
        onFileChanged: (file) => viewedFile = file,
      );
    }
    if (action == InternalViewerAction.edit && context.mounted) {
      await _editFile(context, ref, panel, side, viewedFile);
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
    panel.restoreCursorAndFocus(viewedFile);
  }
}

/// Shift+F4: choose the text/code editor, hex editor or system editor.
void chooseEditorForSelection(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final target =
      panel.cursorItem ??
      (panel.selection.isNotEmpty ? panel.selection.first : null);
  if (target == null || target.isFolder) return;
  unawaited(showEditorChooser(context, ref, target, activePanel));
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
      await showCurrentArchiveWorkspaceDialog(
        context,
        ref,
        side,
        action: ArchiveWorkspaceAction.edit,
        focusedMember: target,
      );
      return;
    }
    await showFileEditorDialog(context, ref, target, side);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open editor: $error')));
    }
  } finally {
    panel.restoreCursorAndFocus(target);
  }
}

void showCopyDialogFromSelection(BuildContext context, WidgetRef ref) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  final opposite = side == PanelSide.local ? PanelSide.remote : PanelSide.local;
  if (panel.isInArchive && !ref.read(panelProvider(opposite)).isInArchive) {
    unawaited(
      showCurrentArchiveWorkspaceDialog(
        context,
        ref,
        side,
        action: ArchiveWorkspaceAction.copyOut,
      ),
    );
    return;
  }
  final files = _selectedOrCursor(panel);
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
  final panel = ref.read(panelProvider(side));
  final opposite = side == PanelSide.local ? PanelSide.remote : PanelSide.local;
  if (panel.isInArchive && !ref.read(panelProvider(opposite)).isInArchive) {
    unawaited(
      showCurrentArchiveWorkspaceDialog(
        context,
        ref,
        side,
        action: ArchiveWorkspaceAction.moveOut,
      ),
    );
    return;
  }
  final files = _selectedOrCursor(panel);
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
  final files = _selectedOrCursor(panel);
  if (files.isNotEmpty) showBatchRenameDialog(context, ref, side, files);
}

Future<void> showCreateFolderDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  final panel = ref.read(panelProvider(side));
  final name = await showCapturedCreateFolderDialog(context, panel);
  if (name != null && context.mounted) {
    _showUndoSnackBar(
      context,
      ref,
      side,
      context.commanderTr('Created folder "{0}"', [name]),
    );
  }
}

void showReceivedFilesDialog(BuildContext context, List<String> files) {
  // This dialog is used in non-Riverpod context (system callback).
  // Keep it simple — the caller handles the upload.
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(ScreenDialogStrings(context).text('received')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ScreenDialogStrings(context).value('uploadConfirm', files.length),
          ),
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
          child: Text(AppLocalizations.of(context)!.upload),
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
      title: Text(ScreenDialogStrings(context).text('goPath')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: ScreenDialogStrings(context).text('path'),
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.folder_open),
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
          child: Text(ScreenDialogStrings(context).text('go')),
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
              label: ScreenDialogStrings(context).text('undo'),
              onPressed: () {
                final undoCtx = _buildUndoCtx(ref, side);
                historyNotifier.undo(last.id, undoCtx).then((result) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(UndoPresentation(context).result(result)),
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
