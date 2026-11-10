// lib/screens/keyboard_shortcuts.dart
//
// Keyboard shortcut definitions for the file browser.
// Extracted from file_browser_screen.dart for maintainability.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/command_strings.dart';
import '../l10n/undo_presentation.dart';
import '../l10n/viewer_action_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart' show swapPanelSources;
import '../providers/focus_area_provider.dart';
import '../providers/terminal_provider.dart';
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import '../services/keyboard_shortcut_service.dart';

import 'package:path/path.dart' as p;

import '../services/archive_service.dart';

import '../widgets/command_palette.dart';
import '../widgets/bookmark_actions.dart';
import '../widgets/pattern_selection_dialog.dart';
import '../widgets/file_list_dialog.dart';
import '../widgets/file_clipboard_actions.dart';
import '../widgets/file_context_menu.dart'
    show showPropertiesDialog, showFileContextMenu;
import '../widgets/file_toolbar.dart' show showPanelFilterDialog;
import '../widgets/search_dialogs.dart' show showSearchDialog;
import 'screen_dialogs.dart';

/// Handles all keyboard events for the file browser screen.
///
/// Returns [KeyEventResult.handled] if the event was consumed,
/// [KeyEventResult.ignored] otherwise.
///
/// [onPanelSwitch] is called when Tab is pressed on narrow screens
/// to sync the mobile panel tab state.
bool _isEditingText() {
  final focus = FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null ||
      context.findAncestorStateOfType<EditableTextState>() != null;
}

KeyEventResult handleKeyEvent(
  BuildContext context,
  WidgetRef ref,
  KeyEvent event, {
  void Function(PanelSide)? onPanelSwitch,
}) {
  if (ModalRoute.of(context)?.isCurrent == false ||
      ref.read(focusAreaProvider) == FocusArea.terminal ||
      ref.read(terminalInputFocusedProvider) ||
      _isEditingText()) {
    return KeyEventResult.ignored;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return KeyEventResult.ignored;
  }
  final keyboard = HardwareKeyboard.instance;
  final control = keyboard.isControlPressed;
  final meta = keyboard.isMetaPressed;
  final shift = keyboard.isShiftPressed;
  final alt = keyboard.isAltPressed;
  final primary = control != meta;
  final unmodified = !control && !meta && !shift && !alt;
  final key = event.logicalKey;
  final activePanel = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(activePanel));
  final shortcuts = ref.read(keyboardShortcutServiceProvider);
  final action = shortcuts.resolveBrowser(
    event,
    isCtrl: control,
    isMeta: meta,
    isShift: shift,
    isAlt: alt,
  );
  if (action != null) {
    // A held custom shortcut must not repeatedly perform a file operation or
    // turn into text filtering in a child view after its initial key-down.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (action == ShortcutAction.up &&
        panel.isTypeahead &&
        !shortcuts.isCustomized(ShortcutAction.up) &&
        key == LogicalKeyboardKey.backspace) {
      panel.typeaheadBackspace();
      return KeyEventResult.handled;
    }
    return executeBrowserShortcut(
      context,
      ref,
      action,
      onPanelSwitch: onPanelSwitch,
    );
  }
  if (shortcuts.suppressesDefault(
    event,
    isCtrl: control,
    isMeta: meta,
    isShift: shift,
    isAlt: alt,
  )) {
    return KeyEventResult.handled;
  }
  if (event is KeyRepeatEvent &&
      key != LogicalKeyboardKey.arrowDown &&
      key != LogicalKeyboardKey.arrowUp &&
      key != LogicalKeyboardKey.space &&
      key != LogicalKeyboardKey.insert) {
    return KeyEventResult.ignored;
  }

  // Alternate accelerators are explicit aliases. Service-owned defaults are
  // dispatched above, never through a permissive legacy modifier check.
  if (primary && !alt && !shift) {
    if (key == LogicalKeyboardKey.equal) {
      final opposite = activePanel == PanelSide.local
          ? PanelSide.remote
          : PanelSide.local;
      unawaited(_mirrorLocation(ref, panel, opposite));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyU) {
      unawaited(
        swapPanelSources(ref).then((_) {
          if (context.mounted)
            onPanelSwitch?.call(ref.read(activePanelProvider));
        }),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD && ref.read(authProvider).isConnected) {
      downloadSelected(context, ref);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.digit3) {
      ref
          .read(panelViewModeProvider(activePanel).notifier)
          .setMode(
            key == LogicalKeyboardKey.digit1
                ? PanelViewMode.brief
                : key == LogicalKeyboardKey.digit2
                ? PanelViewMode.full
                : PanelViewMode.tree,
          );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final target = key == LogicalKeyboardKey.enter
          ? (activePanel == PanelSide.local
                ? PanelSide.remote
                : PanelSide.local)
          : key == LogicalKeyboardKey.arrowLeft
          ? PanelSide.local
          : PanelSide.remote;
      unawaited(
        _openCursorInPanel(
          context,
          ref,
          panel,
          activePanel,
          target,
          onPanelSwitch: onPanelSwitch,
        ),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      final item = panel.cursorItem;
      if (item != null && item.name != '..')
        showPropertiesDialog(context, item);
      return KeyEventResult.handled;
    }
  }
  if (primary && shift && !alt) {
    if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.keyN) {
      _copySelectionToClipboard(
        ref,
        panel,
        namesOnly: key == LogicalKeyboardKey.keyN,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      showFileListDialog(context, ref, activePanel, importMode: true);
      return KeyEventResult.handled;
    }
  }
  if (!control && !meta && !alt) {
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final direction = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      if (shift) {
        panel.shiftMoveCursor(direction);
      } else {
        panel.moveCursor(direction);
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.f4) {
      chooseEditorForSelection(context, ref);
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.f6) {
      final cursor = panel.cursorItem;
      if (cursor != null && cursor.name != '..') {
        panel.startRename(cursor, keepExtension: true);
      } else {
        showRenameDialog(context, ref);
      }
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.f10) {
      final item = panel.cursorItem;
      if (item != null && item.name != '..') {
        final size = MediaQuery.sizeOf(context);
        showFileContextMenu(
          context,
          ref,
          activePanel,
          item,
          Offset(size.width / 2, size.height / 2),
        );
      }
      return KeyEventResult.handled;
    }
    if (shift &&
        (key == LogicalKeyboardKey.numpadAdd ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      panel.selectSameExtension(
        action: key == LogicalKeyboardKey.numpadAdd
            ? SelectionAction.select
            : SelectionAction.deselect,
      );
      return KeyEventResult.handled;
    }
  }
  if (!control && !meta && alt && !shift && key == LogicalKeyboardKey.enter) {
    final item = panel.cursorItem;
    if (item != null && item.name != '..') showPropertiesDialog(context, item);
    return KeyEventResult.handled;
  }
  if (unmodified) {
    if (key == LogicalKeyboardKey.f1) {
      showKeyboardShortcutsHelp(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      panel.moveCursorTo(
        key == LogicalKeyboardKey.home
            ? 0
            : (panel.filteredFiles?.length ?? 1) - 1,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.pageUp) {
      panel.moveCursor(key == LogicalKeyboardKey.pageDown ? 15 : -15);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.insert) {
      if (panel.isTypeahead && key == LogicalKeyboardKey.space) {
        panel.typeaheadAppend(' ');
      } else {
        panel.spaceSelectAndAdvance();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final item = panel.cursorItem;
      if (item != null) panel.navigateInto(item);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numpad5) {
      panel.selectAll();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numpadMultiply) {
      panel.invertSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numpadSubtract) {
      showPatternSelectionDialog(
        context,
        ref,
        activePanel,
        initialAction: SelectionAction.deselect,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (panel.isTypeahead) {
        panel.clearTypeahead();
      } else if (panel.renamingItem != null) {
        panel.cancelRename();
      } else if (panel.isInArchive) {
        panel.exitArchive();
      } else {
        panel.clearSelection();
      }
      return KeyEventResult.handled;
    }
  }
  if (!control && !meta && !alt && event is KeyDownEvent) {
    final raw = event.character;
    final label = key.keyLabel;
    final character = raw != null && raw.isNotEmpty
        ? raw
        : (label.length == 1 ? label : null);
    if (character != null &&
        character.isNotEmpty &&
        character != ' ' &&
        ref.read(quickSearchSettingsProvider).mode != QuickSearchMode.off) {
      panel.typeaheadAppend(character);
      return KeyEventResult.handled;
    }
  }
  return KeyEventResult.ignored;
}

Future<void> _mirrorLocation(
  WidgetRef ref,
  PanelNotifier source,
  PanelSide target,
) async {
  try {
    final origin = source.captureCurrentOrigin();
    await ref
        .read(panelProvider(target))
        .navigateToPath(source.currentPath, origin: origin);
  } catch (error) {
    if (ref.context.mounted)
      ref.read(errorProvider).addError(error.toString(), cause: error);
  }
}

/// Shared browser command execution for the binding resolver and command UI.
/// Editor-only actions deliberately remain outside the file-operation host.
KeyEventResult executeBrowserShortcut(
  BuildContext context,
  WidgetRef ref,
  ShortcutAction action, {
  void Function(PanelSide)? onPanelSwitch,
}) {
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  switch (action) {
    case ShortcutAction.newTab:
      panel.addTab();
    case ShortcutAction.closeTab:
      panel.closeTab(panel.activeTabId);
    case ShortcutAction.nextTab:
      panel.nextTab();
    case ShortcutAction.prevTab:
      panel.previousTab();
    case ShortcutAction.reopenClosedTab:
      unawaited(panel.reopenClosedTab());
    case ShortcutAction.commandPalette:
      showCommandPalette(context, ref);
    case ShortcutAction.connect:
      showConnectionDialogScreen(context);
    case ShortcutAction.goToFolder:
      showGoToDialog(context, ref);
    case ShortcutAction.filter:
      showPanelFilterDialog(context, panel);
    case ShortcutAction.selectAll:
      panel.selectAll();
    case ShortcutAction.delete:
      confirmDeleteSelected(context, ref);
    case ShortcutAction.rename:
      final cursor = panel.cursorItem;
      if (cursor != null && cursor.name != '..') {
        panel.startRename(cursor);
      } else {
        showRenameDialog(context, ref);
      }
    case ShortcutAction.newFolder:
      showCreateFolderDialog(context, ref, side);
    case ShortcutAction.refresh:
      unawaited(panel.refresh());
    case ShortcutAction.preview:
      viewSelectedFile(context, ref);
    case ShortcutAction.edit:
      editSelectedFile(context, ref);
    case ShortcutAction.undo:
      _undoLastAction(context, ref, side);
    case ShortcutAction.redo:
      return KeyEventResult.ignored;
    case ShortcutAction.switchPanel:
      final next = side == PanelSide.local ? PanelSide.remote : PanelSide.local;
      ref.read(activePanelProvider.notifier).state = next;
      ref.read(focusAreaProvider.notifier).state = next == PanelSide.local
          ? FocusArea.local
          : FocusArea.remote;
      onPanelSwitch?.call(next);
      ref.read(panelProvider(next)).listFocusNode.requestFocus();
    case ShortcutAction.copy:
      copyFilesToClipboard(context, ref, side);
    case ShortcutAction.cut:
      copyFilesToClipboard(context, ref, side, cut: true);
    case ShortcutAction.paste:
      pasteFilesFromClipboard(context, ref, side);
    case ShortcutAction.toggleTreeView:
      ref.read(showTreeSidebarProvider.notifier).state = !ref.read(
        showTreeSidebarProvider,
      );
    case ShortcutAction.cycleLayout:
      ref.read(panelViewModeProvider(side).notifier).cycleMode();
    case ShortcutAction.search:
      showSearchDialog(context, ref);
    case ShortcutAction.findPattern:
      showPatternSelectionDialog(context, ref, side);
    case ShortcutAction.copyWithOptions:
      showCopyDialogFromSelection(context, ref);
    case ShortcutAction.moveWithOptions:
      showMoveDialogFromSelection(context, ref);
    case ShortcutAction.back:
      unawaited(panel.navigateBack());
    case ShortcutAction.forward:
      unawaited(panel.navigateForward());
    case ShortcutAction.up:
      unawaited(panel.navigateUp());
    case ShortcutAction.togglePreview:
      ref.read(showPreviewProvider.notifier).state = !ref.read(
        showPreviewProvider,
      );
    case ShortcutAction.toggleHidden:
      panel.toggleShowHiddenFiles();
    case ShortcutAction.sortByName:
      panel.setSortBy(SortBy.name);
    case ShortcutAction.sortByExtension:
      panel.setSortBy(SortBy.extension);
    case ShortcutAction.sortByDate:
      panel.setSortBy(SortBy.date);
    case ShortcutAction.sortBySize:
      panel.setSortBy(SortBy.size);
    case ShortcutAction.bookmark:
      togglePanelBookmark(context, ref, side);
    case ShortcutAction.multiRename:
      showMultiRenameFromSelection(context, ref);
  }
  return KeyEventResult.handled;
}

/// Open the cursor item (folder, archive, or file) in [targetSide]. Archives
/// are entered on the target panel, and files are selected in their parent
/// directory so the destination pane lands on the same item.
Future<void> _openCursorInPanel(
  BuildContext context,
  WidgetRef ref,
  PanelNotifier sourcePanel,
  PanelSide sourceSide,
  PanelSide targetSide, {
  void Function(PanelSide)? onPanelSwitch,
}) async {
  final item = sourcePanel.cursorItem;
  if (item == null || item.name == '..') return;
  if (sourcePanel.isInArchive) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ViewerActionStrings(context).archiveOtherPanelUnsupported,
          ),
        ),
      );
    }
    return;
  }

  final path = item.path;
  if (path == null || path.isEmpty) return;
  final targetPanel = ref.read(panelProvider(targetSide));
  try {
    final origin = sourcePanel.captureOperationOrigin([item]);
    final parent = origin.source.isLocal
        ? p.dirname(path)
        : p.posix.dirname(path);
    final destination = item.isFolder ? path : parent;
    final navigation = targetPanel.navigateToPath(
      destination,
      selectItem: item.isFolder ? null : item,
      origin: origin,
    );
    final targetTab = targetPanel.activeTabId;
    await navigation;
    if (!context.mounted ||
        !origin.isCurrent ||
        targetPanel.activeTabId != targetTab ||
        targetPanel.currentPath != destination ||
        ref.read(activePanelProvider) != sourceSide ||
        targetPanel.captureCurrentOrigin().storageReference !=
            origin.storageReference)
      return;
    if (!item.isFolder && ArchiveService.isArchive(item.name)) {
      final fresh = targetPanel.files
          ?.where((file) => file.path == path)
          .firstOrNull;
      if (fresh == null || fresh.isFolder) return;
      await targetPanel.enterArchive(fresh);
    }
    if (!context.mounted || ref.read(activePanelProvider) != sourceSide) return;
    ref.read(activePanelProvider.notifier).state = targetSide;
    ref.read(focusAreaProvider.notifier).state = targetSide == PanelSide.local
        ? FocusArea.local
        : FocusArea.remote;
    onPanelSwitch?.call(targetSide);
    targetPanel.restoreCursorAndFocus(item);
  } catch (error) {
    if (context.mounted)
      ref.read(errorProvider).addError(error.toString(), cause: error);
  }
}

// ---------------------------------------------------------------------------
// Clipboard helpers
// ---------------------------------------------------------------------------

/// Copy names or full paths of the current selection to the system clipboard.
void _copySelectionToClipboard(
  WidgetRef ref,
  PanelNotifier panel, {
  required bool namesOnly,
}) {
  final selection = panel.selection;
  final items = selection.isEmpty
      ? (panel.cursorItem != null ? {panel.cursorItem!} : <FileItem>{})
      : selection;
  if (items.isEmpty) return;
  final lines = items
      .map((f) => namesOnly ? f.name : (f.path ?? f.name))
      .join('\n');
  Clipboard.setData(ClipboardData(text: lines));
}

// ---------------------------------------------------------------------------
// Undo helper
// ---------------------------------------------------------------------------

/// Undo the most-recent action from [ActionHistoryNotifier] and show a
/// SnackBar with the result.
void _undoLastAction(
  BuildContext context,
  WidgetRef ref,
  PanelSide activePanel,
) {
  final historyNotifier = ref.read(actionHistoryProvider.notifier);
  final last = historyNotifier.lastAction;
  if (last == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(CommandStrings(context).text('nothingUndo')),
        duration: const Duration(seconds: 2),
      ),
    );
    return;
  }

  if (!historyNotifier.canUndo(last)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          CommandStrings(context).text('cannotUndo', {
            'action': UndoPresentation(context).description(last),
          }),
        ),
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
        content: Text(UndoPresentation(context).result(result)),
        duration: const Duration(seconds: 3),
        backgroundColor: result.success
            ? null
            : Theme.of(context).colorScheme.error,
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
    remoteMove: (currentPath, targetDir) =>
        client.movePath(currentPath, targetDir),
    remoteDelete: (path) => client.deletePath(path),
  );
}
