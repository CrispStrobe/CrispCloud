// lib/screens/keyboard_shortcuts.dart
//
// Keyboard shortcut definitions for the file browser.
// Extracted from file_browser_screen.dart for maintainability.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../widgets/command_palette.dart';
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
  if (event is! KeyDownEvent) return KeyEventResult.ignored;

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

  // Ctrl+Tab - Next tab / Ctrl+Shift+Tab - Previous tab
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.tab) {
    if (isShift) {
      panel.previousTab();
    } else {
      panel.nextTab();
    }
    return KeyEventResult.handled;
  }

  // Ctrl+G - Go to path
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyG) {
    showGoToDialog(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+A - Select All
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
    panel.selectAll();
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

  // F2 - Rename (if single file selected)
  if (event.logicalKey == LogicalKeyboardKey.f2) {
    showRenameDialog(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+C - Copy
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

  // Ctrl+R or F5 - Refresh
  if ((isCtrl && event.logicalKey == LogicalKeyboardKey.keyR) ||
      event.logicalKey == LogicalKeyboardKey.f5) {
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

  // Ctrl+U - Upload
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyU && ref.read(authProvider).isConnected) {
    uploadSelected(context, ref);
    return KeyEventResult.handled;
  }

  // Ctrl+D - Download
  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD && ref.read(authProvider).isConnected) {
    downloadSelected(context, ref);
    return KeyEventResult.handled;
  }

  // Space - Toggle preview pane
  if (event.logicalKey == LogicalKeyboardKey.space && !isCtrl) {
    ref.read(showPreviewProvider.notifier).state = !ref.read(showPreviewProvider);
    return KeyEventResult.handled;
  }

  return KeyEventResult.ignored;
}
