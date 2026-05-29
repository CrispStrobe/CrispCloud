// widgets/file_context_menu.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../services/app_state.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import 'package:path/path.dart' as p;
import 'file_list_view.dart' show getFileIcon, formatBytes, formatDateFull;

void showFileContextMenu(BuildContext context, AppState appState, PanelSide side, FileItem file, Offset position) {
  final selection = side == PanelSide.local
      ? appState.localSelection
      : appState.remoteSelection;

  final files = selection.contains(file) && selection.isNotEmpty
      ? selection.toList()
      : [file];

  if (!selection.contains(file)) {
    appState.clearSelection(side);
    appState.toggleSelection(side, file);
  }

  final isMultiSelect = files.length > 1;
  final isSingleFolder = files.length == 1 && files.first.isFolder;

  // Build items list dynamically
  final items = <PopupMenuEntry<dynamic>>[];

  // Open (folders only)
  if (isSingleFolder) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.folder_open),
            SizedBox(width: 8),
            Text('Open'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => appState.navigateInto(side, file),
        ),
      ),
    );
  }

  // Upload to Remote
  if (side == PanelSide.local && appState.isConnected) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.upload),
            const SizedBox(width: 8),
            Text('Upload${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => appState.uploadFiles(files),
        ),
      ),
    );
  }

  // Download to Local
  if (side == PanelSide.remote) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.download),
            const SizedBox(width: 8),
            Text('Download${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => appState.downloadFiles(files),
        ),
      ),
    );
  }

  // Share (mobile platforms only)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && side == PanelSide.local) {
    items.add(
      PopupMenuItem(
        child: Row(
          children: [
            const Icon(Icons.share),
            const SizedBox(width: 8),
            Text('Share${isMultiSelect ? ' (${files.length})' : ''}'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => appState.shareFiles(files),
        ),
      ),
    );
  }

  // Divider
  if ((side == PanelSide.local && appState.isConnected) ||
      side == PanelSide.remote) {
    items.add(const PopupMenuDivider());
  }

  // Copy to...
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.content_copy),
          const SizedBox(width: 8),
          Text('Copy to...${isMultiSelect ? ' (${files.length})' : ''}'),
        ],
      ),
      onTap: () => Future.delayed(
        Duration.zero,
        () => _showCopyDialog(context, appState, side, files),
      ),
    ),
  );

  // Move to...
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          const Icon(Icons.drive_file_move),
          const SizedBox(width: 8),
          Text('Move to...${isMultiSelect ? ' (${files.length})' : ''}'),
        ],
      ),
      onTap: () => Future.delayed(
        Duration.zero,
        () => _showMoveDialog(context, appState, side, files),
      ),
    ),
  );

  // Rename (single item only)
  if (!isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.edit),
            SizedBox(width: 8),
            Text('Rename (F2)'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => showRenameDialog(context, appState, side, file),
        ),
      ),
    );
  }

  items.add(const PopupMenuDivider());

  // Properties / Info
  if (!isMultiSelect) {
    items.add(
      PopupMenuItem(
        child: const Row(
          children: [
            Icon(Icons.info_outline),
            SizedBox(width: 8),
            Text('Properties'),
          ],
        ),
        onTap: () => Future.delayed(
          Duration.zero,
          () => _showPropertiesDialog(context, file),
        ),
      ),
    );
  }

  items.add(const PopupMenuDivider());

  // Delete
  items.add(
    PopupMenuItem(
      child: Row(
        children: [
          Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Text(
            'Delete${isMultiSelect ? ' (${files.length})' : ''}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
      onTap: () => Future.delayed(
        Duration.zero,
        () => confirmDelete(context, appState, side, files),
      ),
    ),
  );

  showMenu(
    context: context,
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
    items: items,
  );
}

void showRenameDialog(BuildContext context, AppState appState, PanelSide side, FileItem file) {
  final controller = TextEditingController(text: file.name);

  // Select filename without extension
  final dotIndex = file.name.lastIndexOf('.');
  if (dotIndex > 0 && !file.isFolder) {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);
  } else {
    controller.selection = TextSelection(baseOffset: 0, extentOffset: file.name.length);
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'New name',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
        ),
        autofocus: true,
        onSubmitted: (value) async {
          if (value.isNotEmpty && value != file.name) {
            await appState.renameFile(side, file, value);
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
            if (controller.text.isNotEmpty && controller.text != file.name) {
              await appState.renameFile(side, file, controller.text);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}

void _showCopyDialog(BuildContext context, AppState appState, PanelSide side, List<FileItem> files) {
  _showPathDialog(context, appState, side, files, 'Copy', appState.copyFiles);
}

void _showMoveDialog(BuildContext context, AppState appState, PanelSide side, List<FileItem> files) {
  _showPathDialog(context, appState, side, files, 'Move', appState.moveFiles);
}

void showCopyDialog(BuildContext context, AppState appState, PanelSide side, List<FileItem> files) {
  _showCopyDialog(context, appState, side, files);
}

void showMoveDialog(BuildContext context, AppState appState, PanelSide side, List<FileItem> files) {
  _showMoveDialog(context, appState, side, files);
}

void _showPathDialog(
  BuildContext context,
  AppState appState,
  PanelSide side,
  List<FileItem> files,
  String operation,
  Future<void> Function(PanelSide, List<FileItem>, String) action,
) {
  final controller = TextEditingController(
    text: side == PanelSide.local ? appState.localPath : appState.remotePath,
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$operation ${files.length} item(s)'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ...files.take(3).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  f.isFolder ? Icons.folder : Icons.insert_drive_file,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )),
          if (files.length > 3)
            Text(
              '... and ${files.length - 3} more',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Target path',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder_open),
            ),
            autofocus: true,
            onSubmitted: (value) async {
              if (value.isNotEmpty) {
                await action(side, files, value);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty) {
              await action(side, files, controller.text);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: Text(operation),
        ),
      ],
    ),
  );
}

void confirmDelete(BuildContext context, AppState appState, PanelSide side, List<FileItem> files) {
  final totalSize = files.fold<int>(0, (sum, file) => sum + (file.size ?? 0));

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.warning,
        color: Theme.of(context).colorScheme.error,
        size: 48,
      ),
      title: const Text('Confirm Delete'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you sure you want to delete ${files.length} item(s)?',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          if (totalSize > 0)
            Text(
              'Total size: ${formatBytes(totalSize)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            await appState.deleteFiles(side, files);
            if (context.mounted) Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

void _showPropertiesDialog(BuildContext context, FileItem file) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(file.isFolder ? Icons.folder : Icons.insert_drive_file),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propertyRow(context, 'Type', file.isFolder ? 'Folder' : 'File'),
            if (file.size != null)
              _propertyRow(context, 'Size', formatBytes(file.size!)),
            if (file.path != null)
              _propertyRow(context, 'Path', file.path!, mono: true),
            if (file.uuid != null)
              _propertyRow(context, 'UUID', file.uuid!, mono: true),
            if (file.updatedAt != null)
              _propertyRow(
                context,
                'Modified',
                formatDateFull(file.updatedAt!),
              ),
            if (!file.isFolder && file.name.contains('.'))
              _propertyRow(
                context,
                'Extension',
                file.name.split('.').last.toUpperCase(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _propertyRow(BuildContext context, String label, String value, {bool mono = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: TextStyle(
            fontFamily: mono ? 'monospace' : null,
            fontSize: mono ? 12 : null,
          ),
        ),
      ],
    ),
  );
}

void showSearchDialog(BuildContext context, AppState appState) {
  final controller = TextEditingController();
  final BuildContext panelContext = context;

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Fuzzy Search (All Files)'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Search query',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.search),
        ),
        autofocus: true,
        onSubmitted: (value) async {
          if (value.isNotEmpty) {
            Navigator.pop(dialogContext);
            final results = await appState.searchFiles(value);
            if (panelContext.mounted) {
              _showSearchResultsDialog(panelContext, appState, value, results['folders'] ?? [], results['files'] ?? []);
            }
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty) {
              Navigator.pop(dialogContext);
              final results = await appState.searchFiles(controller.text);
              if (panelContext.mounted) {
                _showSearchResultsDialog(panelContext, appState, controller.text, results['folders'] ?? [], results['files'] ?? []);
              }
            }
          },
          child: const Text('Search'),
        ),
      ],
    ),
  );
}

void showFindDialog(BuildContext context, AppState appState) {
  final controller = TextEditingController();
  final BuildContext panelContext = context;

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Find in "${p.basename(appState.remotePath)}"'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Pattern (e.g. *.pdf, report-*)',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.find_in_page),
        ),
        autofocus: true,
        onSubmitted: (value) async {
          if (value.isNotEmpty) {
            Navigator.pop(dialogContext);
            final results = await appState.findFiles(value);
            if (panelContext.mounted) {
              _showSearchResultsDialog(panelContext, appState, value, [], results);
            }
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (controller.text.isNotEmpty) {
              Navigator.pop(dialogContext);
              final results = await appState.findFiles(controller.text);
              if (panelContext.mounted) {
                _showSearchResultsDialog(panelContext, appState, controller.text, [], results);
              }
            }
          },
          child: const Text('Find'),
        ),
      ],
    ),
  );
}

void _showSearchResultsDialog(BuildContext context, AppState appState, String query, List<FileItem> folders, List<FileItem> files) {
  final allItems = [...folders, ...files];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Search Results for "$query"'),
      content: Container(
        width: double.maxFinite,
        height: 400,
        child: allItems.isEmpty
            ? const Center(child: Text('No results found.'))
            : ListView.builder(
                itemCount: allItems.length,
                itemBuilder: (context, index) {
                  final item = allItems[index];
                  return ListTile(
                    leading: Icon(item.isFolder ? Icons.folder : getFileIcon(item.name)),
                    title: Text(p.basename(item.name)),
                    subtitle: Text(
                      p.dirname(item.path ?? '/'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      if (item.path != null) {
                        final parentPath = p.dirname(item.path!);
                        appState.navigateToPath(PanelSide.remote, parentPath, selectItem: item);
                        Navigator.pop(context);
                      }
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
