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
  final activePanel = ref.read(activePanelProvider);
  final remotePath = ref.read(panelProvider(PanelSide.remote)).currentPath;
  var useRegex = false;

  showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        Future<void> doFind() async {
          if (controller.text.isEmpty) return;
          Navigator.pop(dialogContext);

          if (useRegex) {
            // Regex filter: filter the current panel's files client-side
            try {
              final regex = RegExp(controller.text, caseSensitive: false);
              final panel = ref.read(panelProvider(activePanel));
              final files = panel.files?.where((f) => regex.hasMatch(f.name)).toList() ?? [];
              if (panelContext.mounted) {
                showSearchResultsDialog(panelContext, ref, controller.text, [], files);
              }
            } catch (e) {
              if (panelContext.mounted) {
                ScaffoldMessenger.of(panelContext).showSnackBar(
                  SnackBar(content: Text('Invalid regex: $e')),
                );
              }
            }
          } else {
            final results = await ref.read(searchProvider).findFiles(controller.text);
            if (panelContext.mounted) {
              showSearchResultsDialog(panelContext, ref, controller.text, [], results);
            }
          }
        }

        return AlertDialog(
          title: Text('Find in "${p.basename(remotePath)}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: useRegex ? 'Regex pattern' : 'Pattern (e.g. *.pdf, report-*)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.find_in_page),
                ),
                autofocus: true,
                onSubmitted: (_) => doFind(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: useRegex,
                    onChanged: (v) => setState(() => useRegex = v ?? false),
                  ),
                  const Text('Use regex', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  if (useRegex)
                    Text('Filters current listing',
                        style: TextStyle(fontSize: 11, color: Theme.of(dialogContext).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: doFind,
              child: const Text('Find'),
            ),
          ],
        );
      },
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
