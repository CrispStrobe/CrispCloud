// widgets/file_toolbar.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../services/app_state.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import 'file_context_menu.dart' show showCopyDialog, showMoveDialog, confirmDelete, showSearchDialog, showFindDialog;
import 'file_list_view.dart' show formatBytes;

class FileToolbar extends StatelessWidget {
  final PanelSide side;
  final AppState appState;
  final String currentPath;

  const FileToolbar({
    super.key,
    required this.side,
    required this.appState,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context) {
    final sortBy = appState.getSort(side);
    final sortOrder = appState.getSortOrder(side);

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
              onPressed: () => appState.pickLocalDirectory(),
            ),

          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Up (Backspace)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => appState.navigateUp(side),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (F5)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => appState.refreshPanel(side),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'New Folder (Ctrl+N)',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            onPressed: () => _showCreateFolderDialog(context, appState),
          ),

          if (side == PanelSide.remote && appState.isConnected) ...[
            IconButton(
              icon: appState.isSearching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              tooltip: 'Fuzzy search all files',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: appState.isSearching ? null : () => showSearchDialog(context, appState),
            ),
            IconButton(
              icon: appState.isSearching
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.find_in_page),
              tooltip: 'Find files by pattern in this folder (e.g. *.pdf)',
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              onPressed: appState.isSearching ? null : () => showFindDialog(context, appState),
            ),
          ],

          PopupMenuButton<String>(
            icon: Icon(
              Icons.sort,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            tooltip: 'Sort',
            onSelected: (value) => _handleSortMenuAction(appState, value),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'name',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.name ? Icons.check : Icons.sort_by_alpha,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Name'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'size',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.size ? Icons.check : Icons.data_usage,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Size'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'date',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.date ? Icons.check : Icons.access_time,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Date'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'extension',
                child: Row(
                  children: [
                    Icon(
                      sortBy == SortBy.extension ? Icons.check : Icons.category,
                    ),
                    const SizedBox(width: 8),
                    const Text('Sort by Extension'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'toggle_order',
                child: Row(
                  children: [
                    Icon(
                      sortOrder == SortOrder.ascending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sortOrder == SortOrder.ascending
                          ? 'Ascending'
                          : 'Descending',
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'select_all',
                child: Row(
                  children: [
                    Icon(Icons.select_all),
                    SizedBox(width: 8),
                    Text('Select All'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'clear_selection',
                child: Row(
                  children: [
                    Icon(Icons.clear),
                    SizedBox(width: 8),
                    Text('Clear Selection'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleSortMenuAction(AppState appState, String action) {
    switch (action) {
      case 'name':
        appState.setSortBy(side, SortBy.name);
        break;
      case 'size':
        appState.setSortBy(side, SortBy.size);
        break;
      case 'date':
        appState.setSortBy(side, SortBy.date);
        break;
      case 'extension':
        appState.setSortBy(side, SortBy.extension);
        break;
      case 'toggle_order':
        appState.toggleSortOrder(side);
        break;
      case 'select_all':
        appState.selectAll(side);
        break;
      case 'clear_selection':
        appState.clearSelection(side);
        break;
    }
  }

  void _showCreateFolderDialog(BuildContext context, AppState appState) {
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
              await appState.createFolder(side, value);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await appState.createFolder(side, controller.text);
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

class FileBreadcrumbs extends StatelessWidget {
  final PanelSide side;
  final AppState appState;
  final String currentPath;

  const FileBreadcrumbs({
    super.key,
    required this.side,
    required this.appState,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS && side == PanelSide.local && currentPath.contains('Containers')) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              size: 16,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'Sandboxed path - Use Browse button to select a real folder',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
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

          accumulated = i == 0
              ? parts[i]
              : '$accumulated\\${parts[i]}';

          breadcrumbs.add({
            'name': parts[i],
            'path': accumulated,
          });
        }
      } else {
        final parts = currentPath.split('/');
        String accumulated = '';

        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty && i != 0) continue;

          if (i == 0) {
            breadcrumbs.add({
              'name': '/',
              'path': '/',
            });
            accumulated = '';
          } else {
            accumulated = accumulated.isEmpty
                ? '/${parts[i]}'
                : '$accumulated/${parts[i]}';

            breadcrumbs.add({
              'name': parts[i],
              'path': accumulated,
            });
          }
        }
      }
    } else {
      if (currentPath == '/') {
        breadcrumbs.add({
          'name': '/',
          'path': '/',
        });
      } else {
        final parts = currentPath.split('/');
        String accumulated = '';

        breadcrumbs.add({
          'name': '/',
          'path': '/',
        });

        for (int i = 1; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;

          accumulated = accumulated.isEmpty
              ? '/${parts[i]}'
              : '$accumulated/${parts[i]}';

          breadcrumbs.add({
            'name': parts[i],
            'path': accumulated,
          });
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
                  appState.navigateToPath(PanelSide.local, Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/');
                }
              } else {
                appState.navigateToPath(PanelSide.remote, '/');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(
                Icons.home,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          ...breadcrumbs.asMap().entries.map((entry) {
            final index = entry.key;
            final crumb = entry.value;
            final isLast = index == breadcrumbs.length - 1;

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                InkWell(
                  onTap: isLast ? null : () {
                    debugPrint('🔗 Breadcrumb clicked: ${crumb['name']} -> ${crumb['path']}');
                    appState.navigateToPath(side, crumb['path']!);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      crumb['name']!,
                      style: TextStyle(
                        color: isLast
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }
}

class FileSelectionBar extends StatelessWidget {
  final PanelSide side;
  final AppState appState;
  final Set<FileItem> selection;

  const FileSelectionBar({
    super.key,
    required this.side,
    required this.appState,
    required this.selection,
  });

  @override
  Widget build(BuildContext context) {
    final totalSize = selection.fold<int>(
      0,
      (sum, file) => sum + (file.size ?? 0),
    );
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
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSecondaryContainer,
          ),
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
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  '${selection.length} selected',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                if (totalSize > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${formatBytes(totalSize)}',
                    style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
                const SizedBox(width: 16),

                if (side == PanelSide.local && appState.isConnected)
                  responsiveButton(
                    icon: Icons.upload,
                    label: 'Upload',
                    tooltip: 'Upload',
                    showLabel: showLabels,
                    onPressed: () => appState.uploadFiles(files),
                  ),

                if (side == PanelSide.remote)
                  responsiveButton(
                    icon: Icons.download,
                    label: 'Download',
                    tooltip: 'Download',
                    showLabel: showLabels,
                    onPressed: () => appState.downloadFiles(files),
                  ),

                const SizedBox(width: 8),

                IconButton(
                  icon: const Icon(Icons.content_copy, size: 20),
                  tooltip: 'Copy to...',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => showCopyDialog(context, appState, side, files),
                ),
                IconButton(
                  icon: const Icon(Icons.drive_file_move, size: 20),
                  tooltip: 'Move to...',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => showMoveDialog(context, appState, side, files),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  tooltip: 'Delete',
                  color: theme.colorScheme.onSecondaryContainer,
                  onPressed: () => confirmDelete(context, appState, side, files),
                ),

                const SizedBox(width: 16),
                responsiveButton(
                  icon: Icons.clear,
                  label: 'Clear',
                  tooltip: 'Clear selection',
                  showLabel: showLabels,
                  onPressed: () => appState.clearSelection(side),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
