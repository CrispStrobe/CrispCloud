import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/access_and_fkey_strings.dart';
import '../l10n/commander_strings.dart';
import '../l10n/navigation_strings.dart';
import '../l10n/panel_error_strings.dart';
import '../models/panel_side.dart';
import '../providers/panel_source_provider.dart';
import '../providers/providers.dart';
import '../screens/screen_dialogs.dart' show showConnectionDialogScreen;
import '../services/panel_source_service.dart';
import '../services/storage_identity.dart';

enum PanelListingState {
  loading,
  chooseFolder,
  disconnected,
  unavailable,
  failed,
  filtered,
  emptyCollection,
  empty,
}

/// Distinguish a real empty directory from a filtered or unavailable listing.
/// The explicit platform argument keeps browser root behavior testable without
/// assuming that a native directory named "/" is a browser grant picker.
PanelListingState? panelListingState(
  PanelNotifier panel, {
  bool isWeb = kIsWeb,
}) {
  final directory =
      !panel.isInArchive && !panel.showingSearchResults && !panel.isFlatView;
  if (directory) {
    final storage = panel.directoryStorage;
    if (storage != null && !panel.directorySourceAvailable) {
      return storage.isLocal
          ? PanelListingState.unavailable
          : PanelListingState.disconnected;
    }
  }
  if (panel.isLoading) return PanelListingState.loading;
  if (directory && panel.directoryListingError != null) {
    return PanelListingState.failed;
  }
  if (directory &&
      isWeb &&
      panel.directoryStorage?.isLocal == true &&
      panel.currentPath == '/' &&
      (panel.files == null || panel.files!.isEmpty)) {
    // Browser grants have named roots (/<selected folder>). The synthetic
    // empty root means no folder was selected, including in visual layouts.
    return PanelListingState.chooseFolder;
  }
  if (directory && !panel.hasVerifiedDirectoryListing) {
    return panel.files == null
        ? PanelListingState.loading
        : PanelListingState.unavailable;
  }
  final files = panel.filteredFiles;
  if (files == null) return PanelListingState.loading;
  if (files.any((file) => file.name != '..')) return null;
  final filtering =
      panel.filterQuery.isNotEmpty &&
      (!panel.isTypeahead || panel.isQuickFilterActive);
  if (filtering) return PanelListingState.filtered;
  return panel.showingSearchResults
      ? PanelListingState.emptyCollection
      : PanelListingState.empty;
}

extension PanelListingStateKind on PanelListingState {
  bool get blocksListing => switch (this) {
    PanelListingState.chooseFolder ||
    PanelListingState.disconnected ||
    PanelListingState.unavailable ||
    PanelListingState.failed => true,
    _ => false,
  };
}

/// Recovery is scoped to this panel and its exact request. Global operation
/// errors never authorize an access grant or a connection change here.
class PanelListingPlaceholder extends ConsumerWidget {
  const PanelListingPlaceholder({
    super.key,
    required this.side,
    required this.state,
    this.dropHint = false,
  });

  final PanelSide side;
  final PanelListingState state;
  final bool dropHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(panelProvider(side));
    final l = AppLocalizations.of(context)!;
    if (state == PanelListingState.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final navigation = NavigationStrings(context);
    final error = panel.directoryListingError;
    final denied =
        error?.code == PanelErrorCode.permissionDenied &&
        panel.directoryStorage?.isLocal == true;
    final (icon, message) = switch (state) {
      PanelListingState.chooseFolder => (Icons.folder_open, l.noFolderSelected),
      PanelListingState.disconnected => (Icons.cloud_off, l.notConnected),
      PanelListingState.unavailable => (
        Icons.folder_off_outlined,
        navigation.text('unavailable'),
      ),
      PanelListingState.failed => (
        denied ? Icons.lock_outline : Icons.error_outline,
        error == null
            ? navigation.text('unavailable')
            : localizedPanelError(context, error),
      ),
      PanelListingState.filtered => (Icons.search_off, l.noResultsFound),
      PanelListingState.emptyCollection => (
        Icons.list_alt,
        context.commanderTr('This file list is empty.'),
      ),
      PanelListingState.empty => (
        dropHint ? Icons.upload_file : Icons.folder_open,
        dropHint ? l.dropFilesToUpload : l.emptyFolder,
      ),
      PanelListingState.loading => (Icons.hourglass_empty, ''),
    };

    final actions = <Widget>[];
    if (state == PanelListingState.chooseFolder) {
      actions.add(
        ElevatedButton.icon(
          onPressed: panel.pickLocalDirectory,
          icon: const Icon(Icons.folder_open),
          label: Text(l.openLocalFolder),
        ),
      );
      final auth = ref.watch(authProvider);
      final client = auth.client;
      final providerName = auth.providerName;
      final storage = storageReferenceForClient(client);
      actions.add(
        OutlinedButton.icon(
          icon: Icon(auth.isConnected ? Icons.cloud_done : Icons.cloud),
          label: Text(
            auth.isConnected
                ? l.browseProvider(providerName)
                : l.connectToCloud,
          ),
          onPressed: auth.isConnected
              ? () {
                  final current = ref.read(authProvider);
                  if (!current.isConnected ||
                      !identical(current.client, client) ||
                      storageReferenceForClient(current.client) != storage) {
                    return;
                  }
                  ref
                      .read(panelSourceProvider(side).notifier)
                      .setSource(
                        RemotePanelSource(
                          providerName: providerName,
                          client: client,
                          path: storage.root,
                        ),
                      );
                }
              : () => showConnectionDialogScreen(context),
        ),
      );
    } else if (state == PanelListingState.disconnected) {
      actions.add(
        ElevatedButton.icon(
          onPressed: () => showConnectionDialogScreen(context),
          icon: const Icon(Icons.login),
          label: Text(l.connectToCloudShort),
        ),
      );
    } else if (state == PanelListingState.failed ||
        state == PanelListingState.unavailable) {
      actions.add(
        ElevatedButton.icon(
          onPressed: denied ? panel.grantAccessToCurrentPath : panel.refresh,
          icon: Icon(denied ? Icons.folder_open : Icons.refresh),
          label: Text(
            denied
                ? AccessAndFKeyStrings(Localizations.localeOf(context))
                      .grantAccess
                : l.retry,
          ),
        ),
      );
    } else if (state == PanelListingState.filtered) {
      actions.add(
        TextButton.icon(
          onPressed: panel.clearFilter,
          icon: const Icon(Icons.filter_alt_off),
          label: Text(l.clearFilter),
        ),
      );
    }

    return Center(
      key: ValueKey('panel-listing-${state.name}'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Tooltip(
                message: message,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (state == PanelListingState.disconnected) ...[
                const SizedBox(height: 8),
                Text(
                  navigation.text('unavailable'),
                  textAlign: TextAlign.center,
                ),
              ],
              for (final action in actions) ...[
                const SizedBox(height: 12),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
