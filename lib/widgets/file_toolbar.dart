// widgets/file_toolbar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/custom_toolbar_command_service.dart';
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
    final panel = ref.watch(panelProvider(side));
    final auth = ref.watch(authProvider);
    final search = ref.watch(searchProvider);
    final sortBy = panel.sortBy;
    final sortOrder = panel.sortOrder;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Archive / flat view banner
        if (panel.isInArchive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Row(
              children: [
                Icon(Icons.folder_zip, size: 16, color: Theme.of(context).colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inside archive: ${panel.archiveSource?.archiveName ?? ""}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.exit_to_app, size: 14),
                  label: const Text('Exit', style: TextStyle(fontSize: 12)),
                  onPressed: () => panel.exitArchive(),
                ),
              ],
            ),
          ),
        if (panel.isFlatView)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Row(
              children: [
                Icon(Icons.layers, size: 16, color: Theme.of(context).colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Flat view — all subdirectories',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Exit', style: TextStyle(fontSize: 12)),
                  onPressed: () => panel.toggleFlatView(),
                ),
              ],
            ),
          ),
        Container(
      padding: const EdgeInsets.all(12),
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

          if (side == PanelSide.local)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Browse...',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: () => panel.pickLocalDirectory(),
            ),

          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Up (Backspace)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => panel.navigateUp(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (F5)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => panel.refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'New Folder (Ctrl+N)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => _showCreateFolderDialog(context, panel),
          ),

          if (side == PanelSide.remote && auth.isConnected) ...[
            IconButton(
              icon: search.isSearching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              tooltip: 'Fuzzy search all files',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: search.isSearching ? null : () => showSearchDialog(context, ref),
            ),
            IconButton(
              icon: search.isSearching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.find_in_page),
              tooltip: 'Find files by pattern in this folder (e.g. *.pdf)',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: search.isSearching ? null : () => showFindDialog(context, ref),
            ),
          ],

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
                tooltip = 'Grid View';
                break;
              case ViewMode.grid:
                icon = Icons.view_column;
                tooltip = 'Column View';
                break;
              case ViewMode.column:
                icon = Icons.view_list;
                tooltip = 'List View';
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
            tooltip: panel.filterQuery.isEmpty ? 'Filter files (Ctrl+F)' : 'Clear filter',
            onPressed: () {
              if (panel.filterQuery.isNotEmpty) {
                panel.clearFilter();
              } else {
                _showFilterBar(context, panel);
              }
            },
          ),

          // Custom toolbar commands
          ...ref.watch(customToolbarCommandServiceProvider).commands.map((cmd) =>
            IconButton(
              icon: const Icon(Icons.terminal, size: 18),
              tooltip: cmd.label,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: () async {
                final service = ref.read(customToolbarCommandServiceProvider);
                final selectedPaths = panel.selection
                    .where((f) => f.path != null)
                    .map((f) => f.path!)
                    .toList();
                final output = await service.execute(
                  cmd,
                  currentPath: panel.currentPath,
                  selectedPaths: selectedPaths,
                );
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(cmd.label),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          output.isEmpty ? '(no output)' : output,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () { Navigator.pop(ctx); panel.refresh(); },
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
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
              tooltip: panel.isFlatView ? 'Exit Flat View' : 'Flat View (all subdirectories)',
              onPressed: () => panel.toggleFlatView(),
            ),

          PopupMenuButton<String>(
            icon: Icon(Icons.sort, color: Theme.of(context).colorScheme.onPrimaryContainer),
            tooltip: 'Sort',
            onSelected: (value) => _handleSortMenuAction(panel, value),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'name', child: Row(children: [
                Icon(sortBy == SortBy.name ? Icons.check : Icons.sort_by_alpha),
                const SizedBox(width: 8), const Text('Sort by Name'),
              ])),
              PopupMenuItem(value: 'size', child: Row(children: [
                Icon(sortBy == SortBy.size ? Icons.check : Icons.data_usage),
                const SizedBox(width: 8), const Text('Sort by Size'),
              ])),
              PopupMenuItem(value: 'date', child: Row(children: [
                Icon(sortBy == SortBy.date ? Icons.check : Icons.access_time),
                const SizedBox(width: 8), const Text('Sort by Date'),
              ])),
              PopupMenuItem(value: 'extension', child: Row(children: [
                Icon(sortBy == SortBy.extension ? Icons.check : Icons.category),
                const SizedBox(width: 8), const Text('Sort by Extension'),
              ])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'toggle_order', child: Row(children: [
                Icon(sortOrder == SortOrder.ascending ? Icons.arrow_upward : Icons.arrow_downward),
                const SizedBox(width: 8),
                Text(sortOrder == SortOrder.ascending ? 'Ascending' : 'Descending'),
              ])),
              const PopupMenuDivider(),
              // Secondary sort
              PopupMenuItem(
                enabled: false,
                child: Text('Secondary Sort', style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                )),
              ),
              PopupMenuItem(value: 'secondary_none', child: Row(children: [
                Icon(panel.secondarySortBy == null ? Icons.check : Icons.remove),
                const SizedBox(width: 8), const Text('None'),
              ])),
              PopupMenuItem(value: 'secondary_name', child: Row(children: [
                Icon(panel.secondarySortBy == SortBy.name ? Icons.check : Icons.sort_by_alpha),
                const SizedBox(width: 8), const Text('by Name'),
              ])),
              PopupMenuItem(value: 'secondary_size', child: Row(children: [
                Icon(panel.secondarySortBy == SortBy.size ? Icons.check : Icons.data_usage),
                const SizedBox(width: 8), const Text('by Size'),
              ])),
              PopupMenuItem(value: 'secondary_date', child: Row(children: [
                Icon(panel.secondarySortBy == SortBy.date ? Icons.check : Icons.access_time),
                const SizedBox(width: 8), const Text('by Date'),
              ])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'select_all', child: Row(children: [
                Icon(Icons.select_all), SizedBox(width: 8), Text('Select All'),
              ])),
              const PopupMenuItem(value: 'clear_selection', child: Row(children: [
                Icon(Icons.clear), SizedBox(width: 8), Text('Clear Selection'),
              ])),
            ],
          ),
        ],
      ),
    ),
      ],
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

  void _showFilterBar(BuildContext context, PanelNotifier panel) {
    final controller = TextEditingController(text: panel.filterQuery);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Files'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Type to filter...',
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
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(BuildContext context, PanelNotifier panel) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder name',
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await panel.createFolder(controller.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
