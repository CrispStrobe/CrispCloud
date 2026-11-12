import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../providers/bookmarks_provider.dart';
import '../providers/panel_provider.dart';

StorageReference? bookmarkStorage(PanelNotifier panel) {
  try {
    return panel.captureCurrentOrigin().storageReference;
  } catch (_) {
    return null;
  }
}

bool isPanelBookmarked(BookmarksNotifier bookmarks, PanelNotifier panel) {
  final storage = bookmarkStorage(panel);
  final collectionId = panel.showingSearchResults
      ? panel.activeTab?.collectionId
      : null;
  if (storage == null && collectionId == null) return false;
  return bookmarks.isBookmarked(
    panel.currentPath,
    panel.side,
    storage: storage,
    collectionId: collectionId,
  );
}

void _report(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

Future<void> togglePanelBookmark(
  BuildContext context,
  WidgetRef ref,
  PanelSide side, {
  String? path,
  String? label,
}) async {
  try {
    final panel = ref.read(panelProvider(side));
    final location = path ?? panel.currentPath;
    final capturedTab = panel.activeTab;
    final capturedLabel = capturedTab?.label ?? location;
    StorageReference? storage;
    String? collectionId;
    if (panel.showingSearchResults && location == panel.currentPath) {
      storage = bookmarkStorage(panel) ?? capturedTab?.storage;
      await panel.exportTabs();
      if (!context.mounted) return;
      collectionId = capturedTab?.collectionId;
      if (collectionId == null) {
        throw StateError(
          context.commanderTr('Save this file list before bookmarking it.'),
        );
      }
    } else {
      storage = panel.captureCurrentOrigin().storageReference;
    }
    final bookmarks = ref.read(bookmarksProvider);
    await bookmarks.ready;
    if (bookmarks.isBookmarked(
      location,
      side,
      storage: storage,
      collectionId: collectionId,
    )) {
      await bookmarks.remove(
        location,
        side,
        storage: storage,
        collectionId: collectionId,
      );
    } else {
      await bookmarks.add(
        label ?? capturedLabel,
        location,
        side,
        storage: storage,
        collectionId: collectionId,
      );
    }
  } catch (error) {
    if (context.mounted) _report(context, error);
  }
}

Future<void> openBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark bookmark, {
  PanelSide? side,
  bool newTab = false,
}) async {
  try {
    if (!bookmark.isBound) {
      throw StateError(
        context.commanderTr(
          'This older bookmark has no saved account. Bind it to its original source in Commander workspaces before opening it.',
        ),
      );
    }
    await ref
        .read(panelProvider(side ?? bookmark.side))
        .openSavedLocation(bookmark.toTabJson(), newTab: newTab);
  } catch (error) {
    if (context.mounted) _report(context, error);
  }
}

Future<void> removeBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark bookmark,
) async {
  try {
    await ref
        .read(bookmarksProvider)
        .remove(
          bookmark.path,
          bookmark.side,
          storage: bookmark.storage,
          collectionId: bookmark.collectionId,
        );
  } catch (error) {
    if (context.mounted) _report(context, error);
  }
}

Future<void> bindLegacyBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark bookmark,
  PanelSide side,
) async {
  try {
    if (bookmark.isBound) return;
    final panel = ref.read(panelProvider(side));
    final origin = panel.captureCurrentOrigin();
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.commanderTr("Bind older bookmark")),
        content: Text(
          context.commanderTr(
            "Use {0} as the original source for this bookmark?\n\n{1}\n{2}",
            [
              panel.storageDisplayName(origin.storageReference),
              bookmark.name,
              bookmark.path,
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.commanderTr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.commanderTr("Bind to this source")),
          ),
        ],
      ),
    );
    if (accept != true || !context.mounted) return;
    if (!origin.isCurrent) {
      throw StateError(
        'The chosen account disconnected. Reconnect it before binding the bookmark.',
      );
    }
    await ref
        .read(bookmarksProvider)
        .replace(
          bookmark,
          Bookmark(
            name: bookmark.name,
            path: bookmark.path,
            side: bookmark.side,
            storage: origin.storageReference,
            group: bookmark.group,
          ),
        );
  } catch (error) {
    if (context.mounted) _report(context, error);
  }
}
