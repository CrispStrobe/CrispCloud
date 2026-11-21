// lib/widgets/commander_hotkey_dialogs.dart
//
// Keyboard-first popups for Total Commander / Double Commander habits:
// directory history (Ctrl+H / Alt+Down) and the open-tab list (Ctrl+Shift+A).

import 'package:flutter/material.dart';

import '../l10n/commander_strings.dart';
import '../models/panel_tab.dart';
import '../providers/panel_provider.dart';

RelativeRect _centeredMenuPosition(BuildContext context) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final size = overlay.size;
  final anchor = Offset(size.width / 2 - 160, size.height / 4);
  return RelativeRect.fromRect(
    Rect.fromLTWH(anchor.dx, anchor.dy, 0, 0),
    Offset.zero & size,
  );
}

Widget _menuHeader(BuildContext context, String title) => Text(
  title,
  style: Theme.of(context).textTheme.labelLarge
      ?.copyWith(fontWeight: FontWeight.w600),
);

/// Ctrl+H / Alt+Down: the pane's visited folders (back and forward history),
/// newest first. Choosing one jumps there within the captured tab.
Future<void> showDirectoryHistoryMenu(
  BuildContext context,
  PanelNotifier panel,
) async {
  final entries = panel.navigationHistory;
  final active = panel.navigationHistoryIndex;
  final tabId = panel.activeTabId;
  final index = await showMenu<int>(
    context: context,
    position: _centeredMenuPosition(context),
    constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
    items: [
      PopupMenuItem<int>(
        enabled: false,
        child: _menuHeader(context, context.commanderTr('Directory history')),
      ),
      if (entries.isEmpty)
        PopupMenuItem<int>(
          enabled: false,
          child: Text(context.commanderTr('No folders visited yet')),
        ),
      for (var i = entries.length - 1; i >= 0; i--)
        CheckedPopupMenuItem<int>(
          key: ValueKey('directory-history-$i'),
          value: i,
          checked: i == active,
          enabled: i != active,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entries[i].path,
                textDirection: TextDirection.ltr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                panel.storageDisplayName(entries[i].storage),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
    ],
  );
  if (index == null || panel.activeTabId != tabId) return;
  final current = panel.navigationHistory;
  if (index < current.length && current[index].sameLocation(entries[index])) {
    await panel.navigateToHistoryEntry(index);
  }
}

/// Ctrl+Shift+A: list the pane's open tabs and switch to the chosen one.
Future<void> showOpenTabsMenu(BuildContext context, PanelNotifier panel) async {
  final tabs = List<PanelTab>.of(panel.tabs);
  final active = panel.activeTabId;
  final id = await showMenu<String>(
    context: context,
    position: _centeredMenuPosition(context),
    constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        child: _menuHeader(context, context.commanderTr('Open tabs')),
      ),
      for (var i = 0; i < tabs.length; i++)
        CheckedPopupMenuItem<String>(
          key: ValueKey('open-tab-${tabs[i].id}'),
          value: tabs[i].id,
          checked: tabs[i].id == active,
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  i < 9 ? '${i + 1}' : '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (tabs[i].isProtected)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: Icon(Icons.push_pin_outlined, size: 14),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tabs[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      tabs[i].path,
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (id == null || id == panel.activeTabId) return;
  if (panel.tabs.any((tab) => tab.id == id)) await panel.selectTab(id);
}

/// Ctrl+Shift+F5: confirm creating symbolic links for several items.
Future<bool> confirmSymbolicLinks(
  BuildContext context,
  int count,
  String directory,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.commanderTr('Create symbolic links')),
        content: Text(
          dialogContext.commanderTr('Create {0} symbolic links in {1}?', [
            count,
            directory,
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.commanderTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.commanderTr('Create')),
          ),
        ],
      ),
    ) ??
    false;
