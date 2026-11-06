import 'package:flutter/material.dart';

import '../models/panel_tab.dart';
import 'file_list_view.dart' show PanelDragData;

class PanelTabBar extends StatelessWidget {
  const PanelTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onNewTab,
    this.onTabPinToggle,
    this.onTabLockChanged,
    this.onTabForceClosed,
    this.onTabDuplicated,
    this.onTabReordered,
    this.onCloseDuplicates,
    this.onWorkspace,
    this.onFilesDroppedOnTab,
    this.activeSelectionCount = 0,
    this.onTabRenamed,
  });

  final List<PanelTab> tabs;
  final String activeTabId;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onNewTab;
  final ValueChanged<String>? onTabPinToggle;
  final void Function(String, TabLockMode)? onTabLockChanged;
  final ValueChanged<String>? onTabForceClosed;
  final ValueChanged<String>? onTabDuplicated;
  final void Function(int, int)? onTabReordered;
  final VoidCallback? onCloseDuplicates;
  final VoidCallback? onWorkspace;
  final void Function(String, List<dynamic>)? onFilesDroppedOnTab;
  final int activeSelectionCount;
  final void Function(String, String)? onTabRenamed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) => onTabReordered?.call(
                oldIndex,
                newIndex > oldIndex ? newIndex + 1 : newIndex,
              ),
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final active = tab.id == activeTabId;
                final title = active && activeSelectionCount > 0
                    ? '[$activeSelectionCount] ${tab.label}'
                    : tab.label;
                return DragTarget<PanelDragData>(
                  key: ValueKey(tab.id),
                  onAcceptWithDetails: (details) =>
                      onFilesDroppedOnTab?.call(tab.id, details.data.files),
                  builder: (context, candidates, rejected) => Tooltip(
                    message:
                        '${tab.storage?.provider ?? 'Location'}: ${tab.path}'
                        '${tab.isLocked ? '\n${tab.lockMode.label}' : ''}'
                        '${tab.lockedPath != null && tab.lockedPath != tab.path ? '\nLocked location: ${tab.lockedPath}' : ''}',
                    child: GestureDetector(
                      onSecondaryTapDown: (details) =>
                          _menu(context, tab, details.globalPosition),
                      onLongPressStart: (details) =>
                          _menu(context, tab, details.globalPosition),
                      child: InkWell(
                        onTap: () => onTabSelected(tab.id),
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 72,
                            maxWidth: 220,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: candidates.isNotEmpty
                                ? theme.colorScheme.primaryContainer
                                : active
                                ? theme.colorScheme.surface
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: active
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                              right: BorderSide(
                                color: theme.dividerColor,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (onTabReordered != null)
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 3),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: 12,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ),
                              if (tab.isProtected)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    tab.isLocked
                                        ? Icons.lock_outline
                                        : Icons.push_pin,
                                    size: 12,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (!tab.isProtected && tabs.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: InkWell(
                                    onTap: () => onTabClosed(tab.id),
                                    child: const Icon(Icons.close, size: 14),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'New tab',
            visualDensity: VisualDensity.compact,
            iconSize: 17,
            onPressed: onNewTab,
            icon: const Icon(Icons.add),
          ),
          if (onWorkspace != null)
            IconButton(
              tooltip: 'Workspaces, bookmarks and views',
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              onPressed: onWorkspace,
              icon: const Icon(Icons.dashboard_customize_outlined),
            ),
        ],
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    PanelTab tab,
    Offset position,
  ) async {
    final index = tabs.indexWhere((value) => value.id == tab.id);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (onTabRenamed != null)
          const PopupMenuItem(value: 'rename', child: Text('Rename tab…')),
        const PopupMenuItem(
          value: 'duplicate',
          child: Text('Duplicate this tab'),
        ),
        if (onTabPinToggle != null)
          CheckedPopupMenuItem(
            value: 'pin',
            checked: tab.isPinned,
            child: const Text('Pin tab'),
          ),
        if (onTabLockChanged != null) ...[
          const PopupMenuDivider(),
          for (final mode in TabLockMode.values)
            CheckedPopupMenuItem(
              value: 'lock:${mode.name}',
              checked: tab.lockMode == mode,
              child: Text(mode.label),
            ),
        ],
        if (onTabReordered != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'left',
            enabled: index > 0,
            child: const Text('Move tab left'),
          ),
          PopupMenuItem(
            value: 'right',
            enabled: index < tabs.length - 1,
            child: const Text('Move tab right'),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'close',
          enabled: tabs.length > 1,
          child: Text(tab.isProtected ? 'Close protected tab…' : 'Close tab'),
        ),
        const PopupMenuItem(
          value: 'others',
          child: Text('Close other unprotected tabs'),
        ),
        if (onCloseDuplicates != null)
          const PopupMenuItem(
            value: 'duplicates',
            child: Text('Close duplicate tabs'),
          ),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action.startsWith('lock:')) {
      onTabLockChanged?.call(
        tab.id,
        TabLockMode.values.byName(action.substring(5)),
      );
      return;
    }
    switch (action) {
      case 'rename':
        final value = await showDialog<String>(
          context: context,
          builder: (_) => _TabNameDialog(initial: tab.customLabel ?? tab.label),
        );
        if (value != null) onTabRenamed?.call(tab.id, value);
      case 'duplicate':
        if (onTabDuplicated != null) {
          onTabDuplicated!(tab.id);
        } else {
          onNewTab();
        }
      case 'pin':
        onTabPinToggle?.call(tab.id);
      case 'left':
        onTabReordered?.call(index, index - 1);
      case 'right':
        onTabReordered?.call(index, index + 2);
      case 'close':
        if (!tab.isProtected) {
          onTabClosed(tab.id);
        } else if (onTabForceClosed != null) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Close protected tab?'),
              content: Text('Close "${tab.label}" at ${tab.path}?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Close tab'),
                ),
              ],
            ),
          );
          if (confirmed == true) onTabForceClosed!(tab.id);
        }
      case 'others':
        for (final other in List<PanelTab>.of(tabs)) {
          if (other.id != tab.id && !other.isProtected) onTabClosed(other.id);
        }
      case 'duplicates':
        onCloseDuplicates?.call();
    }
  }
}

class _TabNameDialog extends StatefulWidget {
  const _TabNameDialog({required this.initial});
  final String initial;
  @override
  State<_TabNameDialog> createState() => _TabNameDialogState();
}

class _TabNameDialogState extends State<_TabNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename tab'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Tab title',
        helperText: 'Leave empty to use the folder name.',
      ),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('Use folder name'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
