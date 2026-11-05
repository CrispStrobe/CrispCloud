// lib/widgets/code_editor_find_panel.dart
//
// Find/replace panel for the Re-Editor based code editor.
//
// Re-Editor supplies the search logic and controller but deliberately no UI.
// This panel is theme-aware, works on narrow/mobile widths, and exposes the
// regex and case-sensitivity toggles that the controller supports.

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../services/search_replace.dart';

class CodeEditorFindPanel extends StatelessWidget
    implements PreferredSizeWidget {
  const CodeEditorFindPanel({
    super.key,
    required this.controller,
    required this.editingController,
    required this.readOnly,
  });

  static const double _rowHeight = 44;

  final CodeFindController controller;
  final CodeLineEditingController editingController;
  final bool readOnly;

  @override
  Size get preferredSize => Size(
    double.infinity,
    controller.value == null
        ? 0
        : (controller.value!.replaceMode ? _rowHeight * 2 : _rowHeight),
  );

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Container(
        height: preferredSize.height,
        // Foreground decoration does not inset the rows, so the panel stays
        // exactly [preferredSize] high instead of overflowing by the border.
        foregroundDecoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: _rowHeight, child: _buildFindRow(context, value)),
            if (value.replaceMode)
              SizedBox(
                height: _rowHeight,
                child: _buildReplaceRow(context, value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindRow(BuildContext context, CodeFindValue value) {
    final theme = Theme.of(context);
    final result = value.result;
    final invalidRegex = value.option.regex && value.option.regExp == null;
    final String status;
    if (invalidRegex) {
      status = 'Invalid regex';
    } else if (value.searching) {
      status = 'Searching…';
    } else if (result == null) {
      status = '0/0';
    } else {
      status = '${result.index + 1}/${result.matches.length}';
    }

    return Row(
      children: [
        const SizedBox(width: 8),
        Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Find',
            ),
            onSubmitted: (_) {
              if (result != null && result.matches.isNotEmpty) {
                controller.nextMatch();
              }
            },
          ),
        ),
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            color: invalidRegex
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _ToggleTextButton(
          label: 'Aa',
          tooltip: 'Match case',
          selected: value.option.caseSensitive,
          onPressed: controller.toggleCaseSensitive,
        ),
        _ToggleTextButton(
          label: '.*',
          tooltip: 'Use regular expression',
          selected: value.option.regex,
          onPressed: controller.toggleRegex,
        ),
        _IconAction(
          icon: Icons.arrow_upward,
          tooltip: 'Previous match',
          onPressed: result == null || result.matches.isEmpty
              ? null
              : controller.previousMatch,
        ),
        _IconAction(
          icon: Icons.arrow_downward,
          tooltip: 'Next match',
          onPressed: result == null || result.matches.isEmpty
              ? null
              : controller.nextMatch,
        ),
        _IconAction(
          icon: Icons.swap_vert,
          tooltip: value.replaceMode ? 'Hide replace' : 'Show replace',
          onPressed: controller.toggleMode,
        ),
        _IconAction(
          icon: Icons.close,
          tooltip: 'Close find',
          onPressed: controller.close,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildReplaceRow(BuildContext context, CodeFindValue value) {
    final result = value.result;
    final canReplace = !readOnly && result != null && result.matches.isNotEmpty;
    return Row(
      children: [
        const SizedBox(width: 8),
        Icon(
          Icons.find_replace,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Replace',
            ),
          ),
        ),
        if (readOnly)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('Read only', style: TextStyle(fontSize: 12)),
          )
        else
          _IconAction(
            icon: Icons.done,
            tooltip: 'Replace',
            onPressed: canReplace ? _replaceCurrent : null,
          ),
        if (!readOnly)
          _IconAction(
            icon: Icons.done_all,
            tooltip: 'Replace all',
            onPressed: canReplace ? _replaceAll : null,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  void _replaceCurrent() {
    final option = controller.value?.option;
    final regExp = option?.regExp;
    final selection = controller.currentMatchSelection;
    if (regExp == null || selection == null) {
      controller.replaceMatch();
      return;
    }

    editingController.selection = selection;
    final selected = editingController.selectedText;
    final match = regExp.firstMatch(selected);
    final replacement = match == null
        ? controller.replaceInputController.text
        : expandReplacementTemplate(
            controller.replaceInputController.text,
            match,
          );
    editingController.replaceSelection(replacement, selection);
  }

  void _replaceAll() {
    final option = controller.value?.option;
    final regExp = option?.regExp;
    if (regExp == null) {
      controller.replaceAllMatches();
      return;
    }
    final source = editingController.text;
    final replacement = replaceAllWithExpansion(
      source,
      regExp,
      controller.replaceInputController.text,
    );
    if (replacement == source) return;
    editingController.text = replacement;
  }
}

class _ToggleTextButton extends StatelessWidget {
  const _ToggleTextButton({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: selected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
    );
  }
}
