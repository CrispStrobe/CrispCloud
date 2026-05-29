// widgets/file_toolbar.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart' show formatBytes;
import 'file_context_menu.dart' show showCopyDialog, showMoveDialog, confirmDelete;
import 'search_dialogs.dart' show showSearchDialog, showFindDialog;

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

    return Container(
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

          // View mode toggle
          Builder(builder: (context) {
            final viewMode = side == PanelSide.local
                ? ref.watch(localViewModeProvider)
                : ref.watch(remoteViewModeProvider);
            return IconButton(
              icon: Icon(
                viewMode == ViewMode.list ? Icons.grid_view : Icons.view_list,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              tooltip: viewMode == ViewMode.list ? 'Grid View' : 'List View',
              onPressed: () {
                final notifier = side == PanelSide.local
                    ? ref.read(localViewModeProvider.notifier)
                    : ref.read(remoteViewModeProvider.notifier);
                notifier.state = viewMode == ViewMode.list ? ViewMode.grid : ViewMode.list;
              },
            );
          }),

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
    );
  }

  void _handleSortMenuAction(PanelNotifier panel, String action) {
    switch (action) {
      case 'name': panel.setSortBy(SortBy.name); break;
      case 'size': panel.setSortBy(SortBy.size); break;
      case 'date': panel.setSortBy(SortBy.date); break;
      case 'extension': panel.setSortBy(SortBy.extension); break;
      case 'toggle_order': panel.toggleSortOrder(); break;
      case 'select_all': panel.selectAll(); break;
      case 'clear_selection': panel.clearSelection(); break;
    }
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

class FileBreadcrumbs extends ConsumerWidget {
  final PanelSide side;
  final String currentPath;

  const FileBreadcrumbs({
    super.key,
    required this.side,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.read(panelProvider(side));

    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS && side == PanelSide.local && currentPath.contains('Containers')) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 16, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'Sandboxed path - Use Browse button to select a real folder',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      );
    }

    List<Map<String, String>> breadcrumbs = [];

    if (side == PanelSide.local) {
      if (!kIsWeb && Platform.isWindows) {
        final parts = currentPath.split('\\');
        String accumulated = '';
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          accumulated = i == 0 ? parts[i] : '$accumulated\\${parts[i]}';
          breadcrumbs.add({'name': parts[i], 'path': accumulated});
        }
      } else {
        final parts = currentPath.split('/');
        String accumulated = '';
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty && i != 0) continue;
          if (i == 0) {
            breadcrumbs.add({'name': '/', 'path': '/'});
            accumulated = '';
          } else {
            accumulated = accumulated.isEmpty ? '/${parts[i]}' : '$accumulated/${parts[i]}';
            breadcrumbs.add({'name': parts[i], 'path': accumulated});
          }
        }
      }
    } else {
      if (currentPath == '/') {
        breadcrumbs.add({'name': '/', 'path': '/'});
      } else {
        final parts = currentPath.split('/');
        breadcrumbs.add({'name': '/', 'path': '/'});
        String accumulated = '';
        for (int i = 1; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          accumulated = accumulated.isEmpty ? '/${parts[i]}' : '$accumulated/${parts[i]}';
          breadcrumbs.add({'name': parts[i], 'path': accumulated});
        }
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (side == PanelSide.local) {
                if (!kIsWeb) {
                  panel.navigateToPath(Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');
                }
              } else {
                panel.navigateToPath('/');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.home, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ...breadcrumbs.asMap().entries.map((entry) {
            final index = entry.key;
            final crumb = entry.value;
            final isLast = index == breadcrumbs.length - 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                InkWell(
                  onTap: isLast ? null : () => panel.navigateToPath(crumb['path']!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      crumb['name']!,
                      style: TextStyle(
                        color: isLast ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class FileSelectionBar extends ConsumerWidget {
  final PanelSide side;
  final Set<FileItem> selection;

  const FileSelectionBar({
    super.key,
    required this.side,
    required this.selection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.read(panelProvider(side));
    final auth = ref.watch(authProvider);
    final transfers = ref.read(transferProvider);

    final totalSize = selection.fold<int>(0, (sum, file) => sum + (file.size ?? 0));
    final files = selection.toList();
    final theme = Theme.of(context);

    Widget responsiveButton({
      required IconData icon,
      required String label,
      required String tooltip,
      required VoidCallback onPressed,
      required bool showLabel,
    }) {
      if (showLabel) {
        return TextButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(label),
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSecondaryContainer),
        );
      } else {
        return IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          color: theme.colorScheme.onSecondaryContainer,
          onPressed: onPressed,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.secondaryContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool showLabels = MediaQuery.of(context).size.width > 600;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 20, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text('${selection.length} selected',
                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSecondaryContainer)),
                if (totalSize > 0) ...[
                  const SizedBox(width: 8),
                  Text('• ${formatBytes(totalSize)}',
                      style: TextStyle(color: theme.colorScheme.onSecondaryContainer)),
                ],
                const SizedBox(width: 16),

                if (side == PanelSide.local && auth.isConnected)
                  responsiveButton(
                    icon: Icons.upload, label: 'Upload', tooltip: 'Upload', showLabel: showLabels,
                    onPressed: () => transfers.uploadFiles(files),
                  ),

                if (side == PanelSide.remote)
                  responsiveButton(
                    icon: Icons.download, label: 'Download', tooltip: 'Download', showLabel: showLabels,
                    onPressed: () => transfers.downloadFiles(files),
                  ),

                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.content_copy, size: 20),
                  tooltip: 'Copy to...',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => showCopyDialog(context, ref, side, files),
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move, size: 20),
                  tooltip: 'Move to...',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => showMoveDialog(context, ref, side, files),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: 'Delete',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => confirmDelete(context, ref, side, files),
                ),

                const SizedBox(width: 16),
                responsiveButton(
                  icon: Icons.clear, label: 'Clear', tooltip: 'Clear selection', showLabel: showLabels,
                  onPressed: () => panel.clearSelection(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
