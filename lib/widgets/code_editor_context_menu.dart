// lib/widgets/code_editor_context_menu.dart
//
// Selection toolbar/context menu for the Re-Editor based code editor.
// Re-Editor implements the interaction plumbing but intentionally leaves the
// visual menu to the host application.

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../l10n/code_search_panel_strings.dart';

class CodeEditorSelectionToolbarController
    implements SelectionToolbarController {
  const CodeEditorSelectionToolbarController();

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final strings = MaterialLocalizations.of(context);
    final selection = controller.selection;
    final hasSelection = !selection.isCollapsed;
    final hasText = controller.selectedText.isNotEmpty;
    showMenu<void>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          anchors.primaryAnchor,
          anchors.primaryAnchor + const Offset(1, 1),
        ),
        Offset.zero & MediaQuery.of(context).size,
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          enabled: hasText,
          onTap: () => controller.copy(),
          child: Text(strings.copyButtonLabel),
        ),
        PopupMenuItem<void>(
          enabled: hasSelection,
          onTap: () => controller.cut(),
          child: Text(strings.cutButtonLabel),
        ),
        PopupMenuItem<void>(
          onTap: () => controller.paste(),
          child: Text(strings.pasteButtonLabel),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          onTap: controller.selectAll,
          child: Text(strings.selectAllButtonLabel),
        ),
        PopupMenuItem<void>(
          enabled: controller.canUndo,
          onTap: controller.undo,
          child: Text(CodeSearchPanelStrings(context).text('undo')),
        ),
        PopupMenuItem<void>(
          enabled: controller.canRedo,
          onTap: controller.redo,
          child: Text(CodeSearchPanelStrings(context).text('redo')),
        ),
      ],
    );
  }

  @override
  void hide(BuildContext context) {
    // The popup route dismisses itself; nothing is retained between shows.
  }
}
