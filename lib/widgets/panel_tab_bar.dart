// lib/widgets/panel_tab_bar.dart
//
// Tab bar widget for file panels. Supports multiple tabs per panel
// with add, close, pin, reorder, and context menu.

import 'package:flutter/material.dart';
import '../models/panel_tab.dart';
import 'file_list_view.dart' show PanelDragData;

class PanelTabBar extends StatelessWidget {
  final List<PanelTab> tabs;
  final String activeTabId;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onNewTab;
  final ValueChanged<String>? onTabPinToggle;
  final void Function(String tabId, List<dynamic> files)? onFilesDroppedOnTab;
  /// Number of selected items in the active tab (shown as [N] badge).
  final int activeSelectionCount;
  final void Function(String tabId, String newLabel)? onTabRenamed;

  const PanelTabBar({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onNewTab,
    this.onTabPinToggle,
    this.onFilesDroppedOnTab,
    this.activeSelectionCount = 0,
    this.onTabRenamed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (tabs.length <= 1) {
      // Don't show tab bar for single tab
      return const SizedBox.shrink();
    }

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isActive = tab.id == activeTabId;

                return DragTarget<PanelDragData>(
                  onAcceptWithDetails: (details) {
                    onFilesDroppedOnTab?.call(tab.id, details.data.files);
                  },
                  builder: (ctx, candidateData, rejectedData) => GestureDetector(
                  onSecondaryTapDown: (details) {
                    _showTabContextMenu(context, tab, details.globalPosition);
                  },
                  child: InkWell(
                    onTap: () => onTabSelected(tab.id),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 180, minWidth: 60),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.surface
                            : Colors.transparent,
                        border: Border(
                          bottom: BorderSide(
                            color: isActive
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
                          if (tab.isPinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 10,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          Flexible(
                            child: Text(
                              isActive && activeSelectionCount > 0
                                  ? '[$activeSelectionCount] ${tab.label}'
                                  : tab.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    isActive ? FontWeight.w600 : FontWeight.normal,
                                color: isActive
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!tab.isPinned && tabs.length > 1) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => onTabClosed(tab.id),
                              borderRadius: BorderRadius.circular(8),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: isActive
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ));
              },
            ),
          ),
          // New tab button
          InkWell(
            onTap: onNewTab,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.add,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _showTabContextMenu(BuildContext context, PanelTab tab, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(tab.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  size: 16),
              const SizedBox(width: 8),
              Text(tab.isPinned ? 'Unpin' : 'Pin Tab'),
            ],
          ),
          onTap: () => onTabPinToggle?.call(tab.id),
        ),
        if (!tab.isPinned && tabs.length > 1)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.close, size: 16),
                SizedBox(width: 8),
                Text('Close Tab'),
              ],
            ),
            onTap: () => onTabClosed(tab.id),
          ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.close_fullscreen, size: 16),
              SizedBox(width: 8),
              Text('Close Other Tabs'),
            ],
          ),
          onTap: () {
            for (final t in tabs) {
              if (t.id != tab.id && !t.isPinned) {
                onTabClosed(t.id);
              }
            }
          },
        ),
        PopupMenuItem(
          onTap: onNewTab,
          child: const Row(
            children: [
              Icon(Icons.content_copy, size: 16),
              SizedBox(width: 8),
              Text('Duplicate Tab'),
            ],
          ),
        ),
        if (onTabRenamed != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.edit, size: 16),
                SizedBox(width: 8),
                Text('Rename Tab'),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              // ignore: use_build_context_synchronously
              () => _showRenameTabDialog(context, tab),
            ),
          ),
      ],
    );
  }

  void _showRenameTabDialog(BuildContext context, PanelTab tab) {
    final ctrl = TextEditingController(text: tab.label);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Tab'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tab name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) onTabRenamed!(tab.id, v.trim());
            Navigator.pop(ctx);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) onTabRenamed!(tab.id, v);
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
