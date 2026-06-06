// lib/screens/keyboard_shortcuts.dart
//
// Keyboard shortcut definitions for the file browser.
// Extracted from file_browser_screen.dart for maintainability.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart' show panelSourceProvider;
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../services/panel_swap_service.dart';
import '../widgets/command_palette.dart';
import '../widgets/file_toolbar.dart' show showPanelFilterDialog;
import 'screen_dialogs.dart';

/// Handles all keyboard events for the file browser screen.
///
/// Returns [KeyEventResult.handled] if the event was consumed,
/// [KeyEventResult.ignored] otherwise.
///
/// [onPanelSwitch] is called when Tab is pressed on narrow screens
/// to sync the mobile panel tab state.
KeyEventResult handleKeyEvent(
  BuildContext context,
  WidgetRef ref,
  KeyEvent event, {
  void Function(PanelSide)? onPanelSwitch,
}) {
  // Allow key-repeat only for navigation keys; block for everything else
  if (event is KeyRepeatEvent) {
    final k = event.logicalKey;
    if (k != LogicalKeyboardKey.arrowDown &&
        k != LogicalKeyboardKey.arrowUp &&
        k != LogicalKeyboardKey.space &&
        k != LogicalKeyboardKey.insert) {
      return KeyEventResult.ignored;
    }
  } else if (event is! KeyDownEvent) {
    return KeyEventResult.ignored;
  }

  final isCtrl = HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  final isShift = HardwareKeyboard.instance.isShiftPressed;
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));

  // Ctrl+Shift+P - Command palette
  if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyP) {
    showCommandPalette(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+Z - Undo last action
  if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
    _undoLastAction(context, ref, activePanel);
    return KeyEventResult.handled;
  }

  // Ctrl+T - New tab
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyT) {
    panel.addTab();
    return KeyEventResult.handled;
  }

  // Ctrl+W - Close tab
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyW) {
    panel.closeTab(panel.activeTabId);
    return KeyEventResult.handled;
  }

  // Ctrl+Tab / Ctrl+PgDn - Next tab
  // Ctrl+Shift+Tab / Ctrl+PgUp - Previous tab
  if (isCtrl && (event.logicalKey == LogicalKeyboardKey.tab ||
      event.logicalKey == LogicalKeyboardKey.pageDown)) {
    if (isShift || event.logicalKey == LogicalKeyboardKey.pageUp) {
      panel.previousTab();
    } else {
      panel.nextTab();
    }
    return KeyEventResult.handled;
  }
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.pageUp) {
    panel.previousTab();
    return KeyEventResult.handled;
  }

  // Ctrl+F - Filter files
  if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyF) {
    showPanelFilterDialog(context, panel);
    return KeyEventResult.handled;
  }

  // Alt+Left - Navigate back in history
  if (!isCtrl && HardwareKeyboard.instance.isAltPressed &&
      event.logicalKey == LogicalKeyboardKey.arrowLeft) {
    panel.navigateBack();
    return KeyEventResult.handled;
  }

  // Alt+Right - Navigate forward in history
  if (!isCtrl && HardwareKeyboard.instance.isAltPressed &&
      event.logicalKey == LogicalKeyboardKey.arrowRight) {
    panel.navigateForward();
    return KeyEventResult.handled;
  }

  // Ctrl+= - Sync opposite panel to current panel's path (DC convention)
  if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.equal) {
    final oppositePanel = activePanel == PanelSide.local ? PanelSide.remote : PanelSide.local;
    ref.read(panelProvider(oppositePanel)).navigateToPath(panel.currentPath);
    return KeyEventResult.handled;
  }

  // Ctrl+Shift+C - Copy selected file paths to clipboard
  if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyC) {
    _copySelectionToClipboard(ref, panel, namesOnly: false);
    return KeyEventResult.handled;
  }

  // Ctrl+Shift+N - Copy selected file names to clipboard
  if (isCtrl && isShift && event.logicalKey == LogicalKeyboardKey.keyN) {
    _copySelectionToClipboard(ref, panel, namesOnly: true);
    return KeyEventResult.handled;
  }

  // Ctrl+G - Go to path
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyG) {
    showGoToDialog(context, ref);
    return KeyEventResult.handled;
  }

  // Arrow Up / Down — move cursor
  if (!isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.arrowDown) {
    panel.moveCursor(1);
    return KeyEventResult.handled;
  }
  if (!isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.arrowUp) {
    panel.moveCursor(-1);
    return KeyEventResult.handled;
  }

  // Home / End — jump to first / last
  if (event.logicalKey == LogicalKeyboardKey.home) {
    panel.moveCursorTo(0);
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.end) {
    panel.moveCursorTo((panel.filteredFiles?.length ?? 1) - 1);
    return KeyEventResult.handled;
  }

  // Page Up / Down — jump by ~15 rows (fixed fallback; FileListView uses exact viewport)
  if (event.logicalKey == LogicalKeyboardKey.pageDown) {
    panel.moveCursor(15);
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.pageUp) {
    panel.moveCursor(-15);
    return KeyEventResult.handled;
  }

  // Shift+Arrow — extend selection
  if (isShift && event.logicalKey == LogicalKeyboardKey.arrowDown) {
    panel.shiftMoveCursor(1);
    return KeyEventResult.handled;
  }
  if (isShift && event.logicalKey == LogicalKeyboardKey.arrowUp) {
    panel.shiftMoveCursor(-1);
    return KeyEventResult.handled;
  }

  // Space / Insert — DC-style: toggle mark on cursor item, advance
  if (!isCtrl && !isShift &&
      (event.logicalKey == LogicalKeyboardKey.space ||
       event.logicalKey == LogicalKeyboardKey.insert)) {
    panel.spaceSelectAndAdvance();
    return KeyEventResult.handled;
  }

  // Enter — open cursor item
  if (!isCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
    final item = panel.cursorItem;
    if (item != null) panel.navigateInto(item);
    return KeyEventResult.handled;
  }

  // Ctrl+Enter — open cursor item in opposite panel (DC: navigate other panel to same path)
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
    final item = panel.cursorItem;
    if (item != null && item.isFolder) {
      final targetPath = item.path ?? (panel.currentPath + '/' + item.name);
      final oppPanel = activePanel == PanelSide.local ? PanelSide.remote : PanelSide.local;
      ref.read(panelProvider(oppPanel)).navigateToPath(targetPath);
    }
    return KeyEventResult.handled;
  }

  // Ctrl+A - Select All
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
    panel.selectAll();
    return KeyEventResult.handled;
  }

  // Numpad * - Invert selection (DC orthodox FM convention)
  if (event.logicalKey == LogicalKeyboardKey.numpadMultiply) {
    panel.invertSelection();
    return KeyEventResult.handled;
  }

  // Numpad + - Select by pattern (e.g. *.dart)
  if (event.logicalKey == LogicalKeyboardKey.numpadAdd) {
    _showPatternDialog(context, panel, select: true);
    return KeyEventResult.handled;
  }

  // Numpad - - Deselect by pattern
  if (event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
    _showPatternDialog(context, panel, select: false);
    return KeyEventResult.handled;
  }

  // Escape - Clear selection
  if (event.logicalKey == LogicalKeyboardKey.escape) {
    panel.clearSelection();
    return KeyEventResult.handled;
  }

  // Delete - Delete selected files
  if (event.logicalKey == LogicalKeyboardKey.delete) {
    confirmDeleteSelected(context, ref);
    return KeyEventResult.handled;
  }

  // F1 - Show keyboard shortcuts help
  if (event.logicalKey == LogicalKeyboardKey.f1) {
    showKeyboardShortcutsHelp(context);
    return KeyEventResult.handled;
  }

  // F2 - In-place rename of cursor item (falls back to dialog if item can't rename inline)
  if (event.logicalKey == LogicalKeyboardKey.f2) {
    final cursor = panel.cursorItem;
    if (cursor != null && cursor.name != '..') {
      panel.startRename(cursor);
    } else {
      showRenameDialog(context, ref);
    }
    return KeyEventResult.handled;
  }

  // F3 - View file with internal viewer / preview pane
  if (event.logicalKey == LogicalKeyboardKey.f3) {
    viewSelectedFile(context, ref);
    return KeyEventResult.handled;
  }

  // F4 - Edit file in internal editor
  if (event.logicalKey == LogicalKeyboardKey.f4) {
    editSelectedFile(context, ref);
    return KeyEventResult.handled;
  }

  // F5 - Copy (DC orthodox FM convention; Ctrl+R stays as Refresh)
  if (!isCtrl && event.logicalKey == LogicalKeyboardKey.f5) {
    showCopyDialogFromSelection(context, ref);
    return KeyEventResult.handled;
  }

  // F6 - Move
  if (event.logicalKey == LogicalKeyboardKey.f6) {
    showMoveDialogFromSelection(context, ref);
    return KeyEventResult.handled;
  }

  // F7 - New folder
  if (event.logicalKey == LogicalKeyboardKey.f7) {
    showCreateFolderDialog(context, ref, activePanel);
    return KeyEventResult.handled;
  }

  // F8 - Delete
  if (event.logicalKey == LogicalKeyboardKey.f8) {
    confirmDeleteSelected(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+C - Copy to...
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
    showCopyDialogFromSelection(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+X - Move
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
    showMoveDialogFromSelection(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+N - New folder
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyN) {
    showCreateFolderDialog(context, ref, activePanel);
    return KeyEventResult.handled;
  }

  // Ctrl+R - Refresh (F5 = Copy per DC orthodox FM convention)
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyR) {
    panel.refresh();
    return KeyEventResult.handled;
  }

  // Backspace - Navigate up
  if (event.logicalKey == LogicalKeyboardKey.backspace) {
    panel.navigateUp();
    return KeyEventResult.handled;
  }

  // Tab (without Ctrl) - Switch panels
  if (!isCtrl && event.logicalKey == LogicalKeyboardKey.tab) {
    final newPanel = activePanel == PanelSide.local ? PanelSide.remote : PanelSide.local;
    ref.read(activePanelProvider.notifier).state = newPanel;
    onPanelSwitch?.call(newPanel);
    return KeyEventResult.handled;
  }

  // Ctrl+U - Swap panel sources (orthodox FM convention, like Midnight Commander)
  if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyU) {
    const service = PanelSwapService();
    final leftSrc = ref.read(panelSourceProvider(PanelSide.local));
    final rightSrc = ref.read(panelSourceProvider(PanelSide.remote));
    if (service.canSwap(leftSrc, rightSrc)) {
      final (newLeft, newRight) = service.swap(leftSrc, rightSrc);
      ref.read(panelSourceProvider(PanelSide.local).notifier).setSource(newLeft);
      ref.read(panelSourceProvider(PanelSide.remote).notifier).setSource(newRight);
    }
    return KeyEventResult.handled;
  }

  // Ctrl+D - Download
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD && ref.read(authProvider).isConnected) {
    downloadSelected(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+1 - Brief view mode for active panel
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit1) {
    ref.read(panelViewModeProvider(activePanel).notifier)
        .setMode(PanelViewMode.brief);
    return KeyEventResult.handled;
  }

  // Ctrl+2 - Full view mode for active panel
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit2) {
    ref.read(panelViewModeProvider(activePanel).notifier)
        .setMode(PanelViewMode.full);
    return KeyEventResult.handled;
  }

  // Ctrl+3 - Tree view mode for active panel
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.digit3) {
    ref.read(panelViewModeProvider(activePanel).notifier)
        .setMode(PanelViewMode.tree);
    return KeyEventResult.handled;
  }

  // Space - Toggle preview pane
  if (event.logicalKey == LogicalKeyboardKey.space && !isCtrl) {
    ref.read(showPreviewProvider.notifier).state = !ref.read(showPreviewProvider);
    return KeyEventResult.handled;
  }

  return KeyEventResult.ignored;
}

// ---------------------------------------------------------------------------
// Clipboard helpers
// ---------------------------------------------------------------------------

/// Copy names or full paths of the current selection to the system clipboard.
void _copySelectionToClipboard(WidgetRef ref, dynamic panel, {required bool namesOnly}) {
  final selection = panel.selection as Set;
  final items = selection.isEmpty
      ? (panel.cursorItem != null ? {panel.cursorItem} : <dynamic>{})
      : selection;
  if (items.isEmpty) return;
  final lines = items.map((f) => namesOnly ? f.name : (f.path ?? f.name)).join('\n');
  Clipboard.setData(ClipboardData(text: lines));
}

// ---------------------------------------------------------------------------
// Undo helper
// ---------------------------------------------------------------------------

/// Undo the most-recent action from [ActionHistoryNotifier] and show a
/// SnackBar with the result.
void _undoLastAction(BuildContext context, WidgetRef ref, PanelSide activePanel) {
  final historyNotifier = ref.read(actionHistoryProvider.notifier);
  final last = historyNotifier.lastAction;
  if (last == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nothing to undo'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  if (!historyNotifier.canUndo(last)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cannot undo: ${last.description}'),
        duration: const Duration(seconds: 3),
      ),
    );
    return;
  }

  // Build undo context from the active panel's provider.
  final undoCtx = _buildUndoContext(ref, activePanel);

  historyNotifier.undo(last.id, undoCtx).then((result) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 3),
        backgroundColor: result.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
    if (result.success) {
      // Refresh the active panel so changes are visible.
      ref.read(panelProvider(activePanel)).refresh();
    }
  });
}

/// Build an [UndoContext] with remote callbacks from the active panel's client.
UndoContext _buildUndoContext(WidgetRef ref, PanelSide side) {
  if (side == PanelSide.local) {
    // Local undo uses dart:io directly inside ActionHistoryService — no callbacks needed.
    return const UndoContext();
  }
  final client = ref.read(authProvider).client;
  return UndoContext(
    remoteRename: (currentPath, name) => client.renamePath(currentPath, name),
    remoteMove: (currentPath, targetDir) => client.movePath(currentPath, targetDir),
    remoteDelete: (path) => client.deletePath(path),
  );
}

void _showPatternDialog(BuildContext context, PanelNotifier panel, {required bool select}) {
  final ctrl = TextEditingController(text: '*.*');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(select ? 'Select by pattern' : 'Deselect by pattern'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'e.g. *.dart, doc*, *test*'),
        onSubmitted: (v) {
          if (select) {
            panel.selectByPattern(v);
          } else {
            panel.deselectByPattern(v);
          }
          Navigator.pop(ctx);
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (select) {
              panel.selectByPattern(ctrl.text);
            } else {
              panel.deselectByPattern(ctrl.text);
            }
            Navigator.pop(ctx);
          },
          child: Text(select ? 'Select' : 'Deselect'),
        ),
      ],
    ),
  );
}
