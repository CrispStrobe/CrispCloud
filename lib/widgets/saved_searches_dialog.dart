// lib/widgets/saved_searches_dialog.dart
//
// Dialog that lists saved searches and lets users run or delete them.
// Also shown when saving the current find-dialog query.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_provider.dart';
import '../services/saved_search_service.dart';
import '../utils/formatters.dart' show formatBytes;
import 'search_dialogs.dart' show showSearchResultsDialog;
import '../l10n/app_localizations.dart';
import '../l10n/saved_search_strings.dart';

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
      title: Text(SavedSearchStrings(ctx).text('saveTitle')),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: SavedSearchStrings(ctx).text('name'),
          hintText: SavedSearchStrings(ctx).text('hint'),
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.bookmark_add_outlined),
        ),
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(AppLocalizations.of(ctx)!.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(AppLocalizations.of(ctx)!.save),
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
        SnackBar(content: Text(SavedSearchStrings(context).value('saved', controller.text.trim()))),
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
      title: Row(
        children: [
          Icon(Icons.bookmarks_outlined),
          SizedBox(width: 8),
          Text(SavedSearchStrings(context).text('title')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: searches.isEmpty
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(SavedSearchStrings(context).text('empty')),
                    SizedBox(height: 4),
                    Text(
                      SavedSearchStrings(context).text('emptyHelp'),
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
            SavedSearchStrings(context).value('query', search.query),
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            localizedSavedSearchFilterSummary(context, search),
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
            tooltip: SavedSearchStrings(context).text('run'),
            onPressed: onRun,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: AppLocalizations.of(context)!.delete,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Formats persisted filter values using labels and date conventions for the UI locale.
String localizedSavedSearchFilterSummary(BuildContext context, SavedSearch search) {
  final strings = SavedSearchStrings(context);
  final parts = <String>[];
  if (search.filterByType.isNotEmpty) {
    final types = search.filterByType.take(3).join(', ');
    parts.add('${strings.text('type')}: $types${search.filterByType.length > 3 ? '…' : ''}');
  }
  if (search.filterByMinSize != null) {
    parts.add('${strings.text('min')}: ${formatBytes(search.filterByMinSize!)}');
  }
  if (search.filterByMaxSize != null) {
    parts.add('${strings.text('max')}: ${formatBytes(search.filterByMaxSize!)}');
  }
  final material = MaterialLocalizations.of(context);
  if (search.filterByDateAfter != null) {
    parts.add('${strings.text('after')}: ${material.formatShortDate(search.filterByDateAfter!)}');
  }
  if (search.filterByDateBefore != null) {
    parts.add('${strings.text('before')}: ${material.formatShortDate(search.filterByDateBefore!)}');
  }
  return parts.isEmpty ? strings.text('noFilters') : parts.join(' · ');
}
