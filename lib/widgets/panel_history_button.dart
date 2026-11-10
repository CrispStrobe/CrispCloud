import 'package:flutter/material.dart';

import '../l10n/navigation_strings.dart';
import '../providers/panel_provider.dart';

/// History choices retain their original tab and storage while the menu is open.
class PanelHistoryButton extends StatelessWidget {
  const PanelHistoryButton({super.key, required this.panel, this.compact = false});
  final PanelNotifier panel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final entries = panel.navigationHistory;
    final activeIndex = panel.navigationHistoryIndex;
    final tabId = panel.activeTabId;
    return SizedBox(
      width: compact ? 30 : 48,
      height: compact ? 30 : 48,
      child: PopupMenuButton<int>(
        tooltip: NavigationStrings(context).text('history'),
        enabled: entries.isNotEmpty,
        padding: EdgeInsets.zero,
        icon: Icon(Icons.history, size: compact ? 17 : 20),
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
        onSelected: (index) {
          final current = panel.navigationHistory;
          if (panel.activeTabId == tabId &&
              index < current.length &&
              current[index].sameLocation(entries[index])) {
            panel.navigateToHistoryEntry(index);
          }
        },
        itemBuilder: (context) => [
          for (var index = entries.length - 1; index >= 0; index--)
            CheckedPopupMenuItem<int>(
              value: index,
              checked: index == activeIndex,
              enabled: index != activeIndex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entries[index].path,
                    textDirection: TextDirection.ltr,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(panel.storageDisplayName(entries[index].storage),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
