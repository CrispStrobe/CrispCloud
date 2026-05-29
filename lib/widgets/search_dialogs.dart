// lib/widgets/search_dialogs.dart
//
// Search and find dialogs, extracted from file_context_menu.dart.
// Used by both the context menu and the toolbar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import 'file_list_view.dart' show getFileIcon;

void showSearchDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  final panelContext = context;

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
            final results = await ref.read(searchProvider).searchFiles(value);
            if (panelContext.mounted) {
              showSearchResultsDialog(panelContext, ref, value,
                  results['folders'] ?? [], results['files'] ?? []);
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
              final results = await ref.read(searchProvider).searchFiles(controller.text);
              if (panelContext.mounted) {
                showSearchResultsDialog(panelContext, ref,
                    controller.text, results['folders'] ?? [], results['files'] ?? []);
              }
            }
          },
          child: const Text('Search'),
        ),
      ],
    ),
  );
}

void showFindDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  final panelContext = context;
  final remotePath = ref.read(panelProvider(PanelSide.remote)).currentPath;

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Find in "${p.basename(remotePath)}"'),
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
            final results = await ref.read(searchProvider).findFiles(value);
            if (panelContext.mounted) {
              showSearchResultsDialog(
                  panelContext, ref, value, [], results);
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
              final results = await ref.read(searchProvider).findFiles(controller.text);
              if (panelContext.mounted) {
                showSearchResultsDialog(
                    panelContext, ref, controller.text, [], results);
              }
            }
          },
          child: const Text('Find'),
        ),
      ],
    ),
  );
}

void showSearchResultsDialog(BuildContext context, WidgetRef ref,
    String query, List<FileItem> folders, List<FileItem> files) {
  final allItems = [...folders, ...files];

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Search Results for "$query"'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: allItems.isEmpty
            ? const Center(child: Text('No results found.'))
            : ListView.builder(
                itemCount: allItems.length,
                itemBuilder: (context, index) {
                  final item = allItems[index];
                  return ListTile(
                    leading: Icon(item.isFolder
                        ? Icons.folder
                        : getFileIcon(item.name)),
                    title: Text(p.basename(item.name)),
                    subtitle: Text(
                      p.dirname(item.path ?? '/'),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      if (item.path != null) {
                        final parentPath = p.dirname(item.path!);
                        ref.read(panelProvider(PanelSide.remote))
                            .navigateToPath(parentPath, selectItem: item);
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
