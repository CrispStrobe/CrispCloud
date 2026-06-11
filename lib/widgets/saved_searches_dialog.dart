// lib/widgets/saved_searches_dialog.dart
//
// Dialog that lists saved searches and lets users run or delete them.
// Also shown when saving the current find-dialog query.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_provider.dart';
import '../services/saved_search_service.dart';
import 'search_dialogs.dart' show showSearchResultsDialog;
import '../l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Public helpers
// ---------------------------------------------------------------------------

/// Open the Saved Searches manager dialog.
void showSavedSearchesDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => _SavedSearchesDialog(panelContext: context, ref: ref),
  );
}

/// Show a dialog asking for a name, then save the current search.
Future<void> showSaveSearchDialog(
  BuildContext context,
  WidgetRef ref, {
  required String query,
}) async {
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Save Search'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Name for this search',
          hintText: 'e.g., Large PDFs, Recent Images…',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.bookmark_add_outlined),
        ),
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (confirmed == true && controller.text.trim().isNotEmpty) {
    await ref.read(searchProvider).saveCurrentSearch(
          name: controller.text.trim(),
          query: query,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search "${controller.text.trim()}" saved')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Main dialog
// ---------------------------------------------------------------------------

class _SavedSearchesDialog extends ConsumerWidget {
  final BuildContext panelContext;
  final WidgetRef ref;

  const _SavedSearchesDialog({
    required this.panelContext,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final searches = widgetRef.watch(searchProvider).savedSearches;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.bookmarks_outlined),
          SizedBox(width: 8),
          Text('Saved Searches'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: searches.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No saved searches yet'),
                    SizedBox(height: 4),
                    Text(
                      'Use the "Save Search" button in the Find dialog\n'
                      'to save your current query and filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: searches.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final search = searches[index];
                    return _SavedSearchTile(
                      search: search,
                      panelContext: panelContext,
                      onRun: () => _runSearch(context, widgetRef, search),
                      onDelete: () =>
                          widgetRef.read(searchProvider).deleteSavedSearch(search.name),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    );
  }

  Future<void> _runSearch(
      BuildContext context, WidgetRef widgetRef, SavedSearch search) async {
    Navigator.pop(context);
    final results = await widgetRef.read(searchProvider).runSavedSearch(search);
    if (panelContext.mounted) {
      showSearchResultsDialog(panelContext, widgetRef, search.query, [], results);
    }
  }
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------

class _SavedSearchTile extends StatelessWidget {
  final SavedSearch search;
  final BuildContext panelContext;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  const _SavedSearchTile({
    required this.search,
    required this.panelContext,
    required this.onRun,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.saved_search_outlined),
      title: Text(search.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Query: "${search.query}"',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            search.filterSummary,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow_outlined),
            tooltip: 'Run',
            onPressed: onRun,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
