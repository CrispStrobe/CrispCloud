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
import '../widgets/internal_viewer_dialog.dart' show showInternalViewer;
import '../l10n/app_localizations.dart';
import '../l10n/command_strings.dart';
import '../l10n/undo_presentation.dart';
import '../l10n/screen_dialog_strings.dart';
import '../l10n/shortcut_strings.dart';
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
      title: Text(ScreenDialogStrings(context).text('logoutTitle')),
      content: Text(ScreenDialogStrings(context).text('logoutConfirm')),
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
                SnackBar(content: Text(CommandStrings(context).text('loggedOut'))),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: Text(AppLocalizations.of(context)!.logout),
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
      title: Text(AppLocalizations.of(context)!.keyboardShortcuts),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // F-keys (DC orthodox FM)
            _shortcutRow('F1', ShortcutStrings(context).description(0)),
            _shortcutRow('F2', ShortcutStrings(context).description(1)),
            _shortcutRow('F3', ShortcutStrings(context).description(2)),
            _shortcutRow('F4', ShortcutStrings(context).description(3)),
            _shortcutRow('Shift+F4', ShortcutStrings(context).description(4)),
            _shortcutRow('F5 / Ctrl+C', ShortcutStrings(context).description(5)),
            _shortcutRow('Ctrl+R', ShortcutStrings(context).description(6)),
            _shortcutRow('F6 / Ctrl+X', ShortcutStrings(context).description(7)),
            _shortcutRow('F7 / Ctrl+N', ShortcutStrings(context).description(8)),
            _shortcutRow('F8 / Delete', ShortcutStrings(context).description(9)),
            const Divider(),
            // Navigation
            _shortcutRow('Alt+← / Alt+→', ShortcutStrings(context).description(10)),
            _shortcutRow('Backspace', ShortcutStrings(context).description(11)),
            _shortcutRow('Enter', ShortcutStrings(context).description(12)),
            _shortcutRow('Ctrl+Enter', ShortcutStrings(context).description(13)),
            _shortcutRow('Tab', ShortcutStrings(context).description(14)),
            _shortcutRow('Ctrl+G', ShortcutStrings(context).description(15)),
            _shortcutRow('Ctrl+F', ShortcutStrings(context).description(16)),
            _shortcutRow(ShortcutStrings(context).keyLabel('type'), ShortcutStrings(context).description(17)),
            _shortcutRow(ShortcutStrings(context).keyLabel('arrows'), ShortcutStrings(context).description(18)),
            const Divider(),
            // Selection
            _shortcutRow('Ctrl+A', ShortcutStrings(context).description(19)),
            _shortcutRow('Numpad *', ShortcutStrings(context).description(20)),
            _shortcutRow('Numpad +', ShortcutStrings(context).description(21)),
            _shortcutRow('Numpad -', ShortcutStrings(context).description(22)),
            _shortcutRow('Space / Insert', ShortcutStrings(context).description(23)),
            _shortcutRow('Shift+↑/↓', ShortcutStrings(context).description(24)),
            _shortcutRow('Escape', ShortcutStrings(context).description(25)),
            const Divider(),
            // File operations
            _shortcutRow('Ctrl+C', ShortcutStrings(context).description(5)),
            _shortcutRow('Ctrl+Z', ShortcutStrings(context).description(26)),
            _shortcutRow('Ctrl+Shift+C', ShortcutStrings(context).description(27)),
            _shortcutRow('Ctrl+Shift+N', ShortcutStrings(context).description(28)),
            _shortcutRow('Ctrl+=', ShortcutStrings(context).description(29)),
            const Divider(),
            // Sort
            _shortcutRow('Ctrl+F3', ShortcutStrings(context).description(30)),
            _shortcutRow('Ctrl+F4', ShortcutStrings(context).description(31)),
            _shortcutRow('Ctrl+F5', ShortcutStrings(context).description(32)),
            _shortcutRow('Ctrl+F6', ShortcutStrings(context).description(33)),
            _shortcutRow('Ctrl+.', ShortcutStrings(context).description(34)),
            _shortcutRow('Ctrl+B', ShortcutStrings(context).description(35)),
            _shortcutRow('Ctrl+I / Alt+Enter', ShortcutStrings(context).description(36)),
            const Divider(),
            // View / Tabs
            _shortcutRow('Ctrl+1', ShortcutStrings(context).description(37)),
            _shortcutRow('Ctrl+2', ShortcutStrings(context).description(38)),
            _shortcutRow('Ctrl+3', ShortcutStrings(context).description(39)),
            _shortcutRow('Ctrl+T', ShortcutStrings(context).description(40)),
            _shortcutRow('Ctrl+W', ShortcutStrings(context).description(41)),
            _shortcutRow('Ctrl+Tab', ShortcutStrings(context).description(42)),
            _shortcutRow('Ctrl+Shift+Tab', ShortcutStrings(context).description(43)),
            _shortcutRow('Ctrl+Shift+P', ShortcutStrings(context).description(44)),
            const Divider(),
            // Transfer
            _shortcutRow('Ctrl+U', ShortcutStrings(context).description(45)),
            _shortcutRow('Ctrl+D', ShortcutStrings(context).description(46)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close)),
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
      title: Text(AppLocalizations.of(context)!.confirmDeleteTitle),
      content: Text(AppLocalizations.of(context)!.confirmDeleteMessage(panel.selection.length)),
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
                ScreenDialogStrings(context).value('deleted', files.length),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: Text(AppLocalizations.of(context)!.delete),
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
        _showUndoSnackBar(context, ref, activePanel, ScreenDialogStrings(context).value('renamed', '${file.name} → $value'));
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.rename),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: AppLocalizations.of(context)!.newName, border: const OutlineInputBorder()),
        autofocus: true,
        onSubmitted: doRename,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () => doRename(controller.text),
          child: Text(AppLocalizations.of(context)!.rename),
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
  final target = panel.cursorItem ??
      (panel.selection.isNotEmpty ? panel.selection.first : null);
  if (target == null || target.isFolder) return;
  // Full-screen DC-style viewer: text/ASCII/binary/hex/image/markdown/PDF/
  // media/font/CSV/office/archive with streaming hex for huge local files.
  showInternalViewer(context, file: target, side: activePanel);
}

/// F4: Open cursor item in the file editor.
void editSelectedFile(BuildContext context, WidgetRef ref) {
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final target = panel.cursorItem ??
      (panel.selection.isNotEmpty ? panel.selection.first : null);
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

  _showPathDialog(context, ref, activePanel, panel, panel.selection.toList(), true, panel.copyFiles);
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

  _showPathDialog(context, ref, activePanel, panel, panel.selection.toList(), false, panel.moveFiles);
}

void _showPathDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide activePanel,
  PanelNotifier panel,
  List<FileItem> files,
  bool isCopy,
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
          ScreenDialogStrings(context).value(isCopy ? 'copied' : 'moved', '${files.length} → $value'),
        );
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isCopy ? AppLocalizations.of(context)!.copyNItems(files.length) : AppLocalizations.of(context)!.moveNItems(files.length)),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: AppLocalizations.of(context)!.targetPath, border: const OutlineInputBorder()),
        autofocus: true,
        onSubmitted: doAction,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () => doAction(controller.text),
          child: Text(isCopy ? AppLocalizations.of(context)!.copy : AppLocalizations.of(context)!.move),
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
        _showUndoSnackBar(context, ref, side, ScreenDialogStrings(context).value('folderCreated', value));
      }
    }
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.newFolder),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: AppLocalizations.of(context)!.folderName, border: const OutlineInputBorder()),
        autofocus: true,
        onSubmitted: doCreate,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
          onPressed: () => doCreate(controller.text),
          child: Text(AppLocalizations.of(context)!.create),
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
      title: Text(ScreenDialogStrings(context).text('received')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ScreenDialogStrings(context).value('uploadConfirm', files.length)),
          const SizedBox(height: 8),
          ...files.take(5).map((path) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${p.basename(path)}', style: const TextStyle(fontSize: 12)),
              )),
          if (files.length > 5)
            Text(AppLocalizations.of(context)!.andMore(files.length - 5), style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
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

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ScreenDialogStrings(context).text('goPath')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: ScreenDialogStrings(context).text('path'),
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
    remoteMove: (currentPath, targetDir) => client.movePath(currentPath, targetDir),
    remoteDelete: (path) => client.deletePath(path),
  );
}
