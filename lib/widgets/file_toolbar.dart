// widgets/file_toolbar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../providers/panel_source_provider.dart' show panelSourceProvider;
import '../providers/toolbar_provider.dart' show panelViewModeProvider;
import '../services/custom_toolbar_command_service.dart';
import '../services/panel_view_mode_service.dart' show PanelViewMode;
import 'search_dialogs.dart' show showSearchDialog, showFindDialog;

// Re-export decomposed widgets for backward compatibility
export 'file_breadcrumbs.dart';
export 'file_selection_bar.dart';

/// Provider for custom toolbar commands.
final customToolbarCommandServiceProvider =
    ChangeNotifierProvider<CustomToolbarCommandService>((ref) {
  final service = CustomToolbarCommandService();
  service.load();
  return service;
});

class FileToolbar extends ConsumerWidget {
  final PanelSide side;
  final String currentPath;

  const FileToolbar({
    super.key,
    required this.side,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final panel = ref.watch(panelProvider(side));
    final auth = ref.watch(authProvider);
    final search = ref.watch(searchProvider);
    final sortBy = panel.sortBy;
    final sortOrder = panel.sortOrder;

    // Show Browse button when panel is in local mode (either side).
    final panelSource = ref.watch(panelSourceProvider(side));
    final isLocalSource = panelSource.isLocal;

    // Build the list of toolbar action buttons (scrollable section)
    final actionButtons = <Widget>[
      if (isLocalSource || (side == PanelSide.local))
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: l.browseTooltip,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          onPressed: () => panel.pickLocalDirectory(),
        ),

      IconButton(
        icon: const Icon(Icons.arrow_upward),
        tooltip: l.upTooltip,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        onPressed: () => panel.navigateUp(),
      ),
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: l.refreshTooltip,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        onPressed: () => panel.refresh(),
      ),
      IconButton(
        icon: const Icon(Icons.create_new_folder),
        tooltip: l.newFolderTooltip,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        onPressed: () => _showCreateFolderDialog(context, panel),
      ),

      if (side == PanelSide.remote && auth.isConnected) ...[
        IconButton(
          icon: search.isSearching
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search),
          tooltip: l.searchAllFiles,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          onPressed: search.isSearching ? null : () => showSearchDialog(context, ref),
        ),
        IconButton(
          icon: search.isSearching
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.find_in_page),
          tooltip: l.findByPattern,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          onPressed: search.isSearching ? null : () => showFindDialog(context, ref),
        ),
      ],

      // Density toggle: compact (desktop) ↔ comfortable (touch/iPad)
      Builder(builder: (context) {
        final density = ref.watch(panelViewModeProvider(side));
        final isCompact = density == PanelViewMode.full;
        return IconButton(
          icon: Icon(
            isCompact ? Icons.density_large : Icons.density_small,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          tooltip: isCompact ? l.touchFriendlyView : l.compactView,
          onPressed: () {
            ref.read(panelViewModeProvider(side).notifier).setMode(
              isCompact ? PanelViewMode.brief : PanelViewMode.full,
            );
          },
        );
      }),

      // View mode toggle (cycles: list -> grid -> column -> list)
      Builder(builder: (context) {
        final viewMode = side == PanelSide.local
            ? ref.watch(localViewModeProvider)
            : ref.watch(remoteViewModeProvider);
        IconData icon;
        String tooltip;
        switch (viewMode) {
          case ViewMode.list:
            icon = Icons.grid_view;
            tooltip = l.gridView;
            break;
          case ViewMode.grid:
            icon = Icons.view_column;
            tooltip = l.columnView;
            break;
          case ViewMode.column:
            icon = Icons.view_list;
            tooltip = l.listView;
            break;
        }
        return IconButton(
          icon: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
          tooltip: tooltip,
          onPressed: () {
            final notifier = side == PanelSide.local
                ? ref.read(localViewModeProvider.notifier)
                : ref.read(remoteViewModeProvider.notifier);
            switch (viewMode) {
              case ViewMode.list:
                notifier.state = ViewMode.grid;
                break;
              case ViewMode.grid:
                notifier.state = ViewMode.column;
                break;
              case ViewMode.column:
                notifier.state = ViewMode.list;
                break;
            }
          },
        );
      }),

      // Incremental filter toggle
      IconButton(
        icon: Icon(
          panel.filterQuery.isEmpty ? Icons.filter_list : Icons.filter_list_off,
          color: panel.filterQuery.isNotEmpty
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        tooltip: panel.filterQuery.isEmpty ? l.filterFilesShortcut : l.clearFilter,
        onPressed: () {
          if (panel.filterQuery.isNotEmpty) {
            panel.clearFilter();
          } else {
            _showFilterBar(context, panel);
          }
        },
      ),

      // Flat view toggle (local panel only)
      if (side == PanelSide.local)
        IconButton(
          icon: Icon(
            Icons.layers,
            color: panel.isFlatView
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          tooltip: panel.isFlatView ? l.exitFlatView : l.flatView,
          onPressed: () => panel.toggleFlatView(),
        ),

      // Hidden files toggle (local panel only) — Ctrl+.
      if (side == PanelSide.local)
        IconButton(
          icon: Icon(
            panel.showHiddenFiles ? Icons.visibility : Icons.visibility_off,
            color: panel.showHiddenFiles
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          tooltip: panel.showHiddenFiles ? '${l.hideHiddenFiles} (Ctrl+.)' : '${l.showHiddenFiles} (Ctrl+.)',
          onPressed: () => panel.toggleShowHiddenFiles(),
        ),

      PopupMenuButton<String>(
        icon: Icon(Icons.sort, color: Theme.of(context).colorScheme.onPrimaryContainer),
        tooltip: l.sort,
        onSelected: (value) => _handleSortMenuAction(panel, value),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'name', child: Row(children: [
            Icon(sortBy == SortBy.name ? Icons.check : Icons.sort_by_alpha),
            const SizedBox(width: 8), Text(l.sortByName),
          ])),
          PopupMenuItem(value: 'size', child: Row(children: [
            Icon(sortBy == SortBy.size ? Icons.check : Icons.data_usage),
            const SizedBox(width: 8), Text(l.sortBySize),
          ])),
          PopupMenuItem(value: 'date', child: Row(children: [
            Icon(sortBy == SortBy.date ? Icons.check : Icons.access_time),
            const SizedBox(width: 8), Text(l.sortByDate),
          ])),
          PopupMenuItem(value: 'extension', child: Row(children: [
            Icon(sortBy == SortBy.extension ? Icons.check : Icons.category),
            const SizedBox(width: 8), Text(l.sortByExtension),
          ])),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'toggle_order', child: Row(children: [
            Icon(sortOrder == SortOrder.ascending ? Icons.arrow_upward : Icons.arrow_downward),
            const SizedBox(width: 8),
            Text(sortOrder == SortOrder.ascending ? l.ascending : l.descending),
          ])),
          const PopupMenuDivider(),
          // Secondary sort
          PopupMenuItem(
            enabled: false,
            child: Text(l.secondarySort, style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            )),
          ),
          PopupMenuItem(value: 'secondary_none', child: Row(children: [
            Icon(panel.secondarySortBy == null ? Icons.check : Icons.remove),
            const SizedBox(width: 8), Text(l.none),
          ])),
          PopupMenuItem(value: 'secondary_name', child: Row(children: [
            Icon(panel.secondarySortBy == SortBy.name ? Icons.check : Icons.sort_by_alpha),
            const SizedBox(width: 8), Text(l.byName),
          ])),
          PopupMenuItem(value: 'secondary_size', child: Row(children: [
            Icon(panel.secondarySortBy == SortBy.size ? Icons.check : Icons.data_usage),
            const SizedBox(width: 8), Text(l.bySize),
          ])),
          PopupMenuItem(value: 'secondary_date', child: Row(children: [
            Icon(panel.secondarySortBy == SortBy.date ? Icons.check : Icons.access_time),
            const SizedBox(width: 8), Text(l.byDate),
          ])),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'select_all', child: Row(children: [
            const Icon(Icons.select_all), const SizedBox(width: 8), Text(l.selectAll),
          ])),
          PopupMenuItem(value: 'clear_selection', child: Row(children: [
            const Icon(Icons.clear), const SizedBox(width: 8), Text(l.clearSelection),
          ])),
        ],
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(
            side == PanelSide.local ? Icons.folder : Icons.cloud,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              currentPath,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Scrollable action buttons area
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: actionButtons,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSortMenuAction(PanelNotifier panel, String action) {
    switch (action) {
      case 'name': panel.setSortBy(SortBy.name); break;
      case 'size': panel.setSortBy(SortBy.size); break;
      case 'date': panel.setSortBy(SortBy.date); break;
      case 'extension': panel.setSortBy(SortBy.extension); break;
      case 'toggle_order': panel.toggleSortOrder(); break;
      case 'secondary_none': panel.setSecondarySortBy(null); break;
      case 'secondary_name': panel.setSecondarySortBy(SortBy.name); break;
      case 'secondary_size': panel.setSecondarySortBy(SortBy.size); break;
      case 'secondary_date': panel.setSecondarySortBy(SortBy.date); break;
      case 'select_all': panel.selectAll(); break;
      case 'clear_selection': panel.clearSelection(); break;
    }
  }

  void _showFilterBar(BuildContext context, PanelNotifier panel) =>
      showPanelFilterDialog(context, panel);

  void _showCreateFolderDialog(BuildContext context, PanelNotifier panel) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.newFolder),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.folderName,
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.folder),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              await panel.createFolder(value);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await panel.createFolder(controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
  }
}

/// Show the panel filter dialog — also callable from keyboard shortcuts (Ctrl+F).
void showPanelFilterDialog(BuildContext context, PanelNotifier panel) {
  final controller = TextEditingController(text: panel.filterQuery);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.filterFiles),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context)!.typeToFilter,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.filter_list),
        ),
        autofocus: true,
        onChanged: (value) => panel.setFilter(value),
        onSubmitted: (_) => Navigator.pop(context),
      ),
      actions: [
        TextButton(
          onPressed: () {
            panel.clearFilter();
            Navigator.pop(context);
          },
          child: Text(AppLocalizations.of(context)!.clear),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.done),
        ),
      ],
    ),
  );
}
