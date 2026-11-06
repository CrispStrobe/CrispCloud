// lib/widgets/sync_dialog.dart
//
// Dialog for managing sync pairs: create, edit, delete, trigger sync.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../providers/providers.dart';
import '../services/background_sync_service.dart';
import '../services/sync_database.dart';
import '../services/storage_identity.dart';
import '../l10n/app_localizations.dart';
import 'sync_plan_dialog.dart';
import '../l10n/sync_dialog_strings.dart';

// Auto-evict options: 0=disabled, then days
const _kAutoEvictOptions = [0, 7, 14, 30, 60, 90];

void showSyncDialog(BuildContext context) {
  showDialog(context: context, builder: (_) => const _SyncManagerDialog());
}

class _SyncManagerDialog extends ConsumerWidget {
  const _SyncManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SyncDialogStrings(context);
    final sync = ref.watch(syncProvider);

    return AlertDialog(
      scrollable: true,
      title: Row(
        children: [
          const Icon(Icons.sync),
          const SizedBox(width: 8),
          Expanded(child: Text(context.commanderTr("Sync Pairs"))),
          // Watch toggle
          IconButton(
            icon: Icon(
              sync.isWatchEnabled ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: sync.isWatchEnabled ? Colors.green : null,
            ),
            tooltip: sync.isWatchEnabled
                ? context.commanderTr("Disable Auto-Sync")
                : context.commanderTr("Enable Auto-Sync (watch for changes)"),
            onPressed: () {
              if (sync.isWatchEnabled) {
                ref.read(syncProvider).disableWatch();
              } else {
                ref.read(syncProvider).enableWatch();
              }
            },
          ),
          if (sync.isSyncing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync, size: 20),
              tooltip: context.commanderTr("Sync All"),
              onPressed: sync.pairs.isEmpty
                  ? null
                  : () => ref.read(syncProvider).syncAll(),
            ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sync.lastResult != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: sync.lastResult!.errors > 0
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.commanderTr(
                    "Last sync: {0} up, {1} down, {2} conflicts, {3} errors",
                    [
                      sync.lastResult!.uploaded,
                      sync.lastResult!.downloaded,
                      sync.lastResult!.conflicts,
                      sync.lastResult!.errors,
                    ],
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Background sync toggle (Android / iOS only)
            if (BackgroundSyncService.isSupported) ...[
              const BackgroundSyncSettings(),
              const Divider(height: 20),
            ],
            // Auto-evict setting (applies to all pairs with placeholders)
            _AutoEvictTile(sync: sync),
            const Divider(height: 20),
            if (sync.pairs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.sync_disabled,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    Text(context.commanderTr("No sync pairs configured")),
                    const SizedBox(height: 4),
                    Text(
                      context.commanderTr(
                        "Add a pair to keep local and remote folders in sync.",
                      ),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final pair in sync.pairs) _SyncPairTile(pair: pair),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        TextButton.icon(
          icon: const Icon(Icons.replay, size: 16),
          label: Text(context.commanderTr("Replay Offline")),
          onPressed: sync.isSyncing
              ? null
              : () async {
                  final result = await ref
                      .read(syncProvider)
                      .replayOfflineQueue();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result.hasChanges || result.errors > 0
                              ? context.commanderTr(
                                  "Replayed: {0} ops, {1} errors",
                                  [result.replayed, result.errors],
                                )
                              : context.commanderTr(
                                  "No offline operations to replay",
                                ),
                        ),
                      ),
                    );
                  }
                },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(context.commanderTr("Add Pair")),
          onPressed: () => _showAddPairDialog(context, ref),
        ),
      ],
    );
  }

  void _showAddPairDialog(BuildContext context, WidgetRef ref) {
    final t = SyncDialogStrings(context);
    final nameController = TextEditingController();
    final localController = TextEditingController();
    final remoteController = TextEditingController(text: '/');
    final includeController = TextEditingController();
    final excludeController = TextEditingController();
    var policy = ConflictPolicy.newestWins;
    var direction = SyncDirection.twoWay;
    var usePlaceholders = false;
    String? creationError;
    var creating = false;

    final auth = ref.read(authProvider);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(context.commanderTr("New Sync Pair")),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (creationError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        creationError!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Name"),
                      hintText: context.commanderTr("e.g., Documents Sync"),
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: localController,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Local Folder Path"),
                      hintText: context.commanderTr("/home/user/Documents"),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.folder),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remoteController,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Remote Folder Path"),
                      hintText: context.commanderTr("/Documents"),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.cloud),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ConflictPolicy>(
                    initialValue: policy,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Conflict Policy"),
                      border: const OutlineInputBorder(),
                    ),
                    items: ConflictPolicy.values
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              _policyLabel(p, SyncDialogStrings(context)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => policy = v ?? policy),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SyncDirection>(
                    initialValue: direction,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.commanderTr("Direction"),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: SyncDirection.twoWay,
                        child: Text(context.commanderTr("Two-Way")),
                      ),
                      DropdownMenuItem(
                        value: SyncDirection.uploadOnly,
                        child: Text(context.commanderTr("Upload Only")),
                      ),
                      DropdownMenuItem(
                        value: SyncDirection.downloadOnly,
                        child: Text(context.commanderTr("Download Only")),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => direction = v ?? direction),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: includeController,
                    decoration: InputDecoration(
                      labelText: context.commanderTr(
                        "Include Patterns (optional)",
                      ),
                      hintText: context.commanderTr("*.dart, *.yaml, lib/**"),
                      helperText: context.commanderTr(
                        "Comma-separated globs. Empty = all files.",
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.filter_alt),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: excludeController,
                    decoration: InputDecoration(
                      labelText: context.commanderTr(
                        "Exclude Patterns (optional)",
                      ),
                      hintText: context.commanderTr(
                        ".git/**, *.tmp, node_modules/**",
                      ),
                      helperText: context.commanderTr(
                        "Comma-separated globs to skip.",
                      ),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.filter_alt_off),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(context.commanderTr("Cloud-only files")),
                    subtitle: Text(
                      context.commanderTr(
                        "New remote files appear as lightweight stubs. Download on demand to save disk space.",
                      ),
                    ),
                    secondary: const Icon(Icons.cloud_outlined),
                    value: usePlaceholders,
                    onChanged: (v) => setState(() => usePlaceholders = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            ElevatedButton(
              onPressed: creating
                  ? null
                  : () async {
                      if (nameController.text.isEmpty ||
                          localController.text.isEmpty) {
                        return;
                      }
                      setState(() {
                        creating = true;
                        creationError = null;
                      });
                      try {
                        await ref
                            .read(syncProvider)
                            .addPair(
                              name: nameController.text,
                              localPath: localController.text,
                              remotePath: remoteController.text,
                              provider: auth.currentProvider.name,
                              conflictPolicy: policy,
                              direction: direction,
                              includePatterns: includeController.text,
                              excludePatterns: excludeController.text,
                              usePlaceholders: usePlaceholders,
                            );
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (error) {
                        if (ctx.mounted) {
                          setState(() {
                            creating = false;
                            creationError = error.toString();
                          });
                        }
                      }
                    },
              child: Text(context.commanderTr("Create")),
            ),
          ],
        ),
      ),
    );
  }

  String _policyLabel(ConflictPolicy p, SyncDialogStrings t) {
    switch (p) {
      case ConflictPolicy.newestWins:
        return t.text('newest');
      case ConflictPolicy.localWins:
        return t.text('localWins');
      case ConflictPolicy.remoteWins:
        return t.text('remoteWins');
      case ConflictPolicy.keepBoth:
        return t.text('keepBoth');
      case ConflictPolicy.manual:
        return t.text('ask');
    }
  }
}

// ---------------------------------------------------------------------------
// Background sync tile
// ---------------------------------------------------------------------------

/// Mobile background scheduling controls, reflecting acknowledged service state.
class BackgroundSyncSettings extends ConsumerStatefulWidget {
  const BackgroundSyncSettings({super.key});

  @override
  ConsumerState<BackgroundSyncSettings> createState() =>
      _BackgroundSyncSettingsState();
}

class _BackgroundSyncSettingsState
    extends ConsumerState<BackgroundSyncSettings> {
  bool _updating = false;

  Future<void> _changeSchedule({bool? enabled, int? interval}) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final sync = ref.read(syncProvider);
      if (enabled == false) {
        await sync.disableBackgroundSync();
      } else {
        await sync.enableBackgroundSync(
          intervalMinutes: interval ?? sync.backgroundSyncIntervalMinutes,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.commanderTr("Background sync could not be updated: {0}", [
                error,
              ]),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SyncDialogStrings(context);
    final sync = ref.watch(syncProvider);
    final enabled = sync.isBackgroundSyncEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sync_lock),
          title: Text(context.commanderTr("Background Sync")),
          subtitle: Text(
            enabled
                ? context.commanderTr(
                    "Background sync requested every {0} min",
                    [sync.backgroundSyncIntervalMinutes],
                  )
                : context.commanderTr("Sync only when the app is open"),
            style: const TextStyle(fontSize: 12),
          ),
          value: enabled,
          contentPadding: EdgeInsets.zero,
          onChanged: _updating
              ? null
              : (value) => _changeSchedule(enabled: value),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.commanderTr(
              "FTP/FTPS and WebDAV only. The operating system decides when tasks run.",
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.commanderTr("Interval:"),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: sync.backgroundSyncIntervalMinutes,
                  isDense: true,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: 15,
                      child: Text(context.commanderTr("15 min")),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text(context.commanderTr("30 min")),
                    ),
                    DropdownMenuItem(
                      value: 60,
                      child: Text(context.commanderTr("1 hour")),
                    ),
                    DropdownMenuItem(
                      value: 120,
                      child: Text(context.commanderTr("2 hours")),
                    ),
                  ],
                  onChanged: _updating
                      ? null
                      : (value) {
                          if (value != null) _changeSchedule(interval: value);
                        },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sync pair tile
// ---------------------------------------------------------------------------

class _SyncPairTile extends ConsumerWidget {
  final SyncPair pair;
  const _SyncPairTile({required this.pair});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SyncDialogStrings(context);
    final sync = ref.watch(syncProvider);
    final auth = ref.watch(authProvider);
    final bound = sync.isPairBound(pair);
    final isActive = sync.isSyncing && sync.currentPairName == pair.name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  pair.enabled ? Icons.sync : Icons.sync_disabled,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(pair.name)),
                if (pair.usePlaceholders) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: context.commanderTr(
                      "Cloud-only mode: files download on demand",
                    ),
                    child: Icon(
                      Icons.cloud_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            Text(
              context.commanderTr("{0} ↔ {1}\nLast sync: {2}", [
                pair.localPath,
                pair.remotePath,
                pair.lastSyncAt != null
                    ? _formatTime(context, pair.lastSyncAt!)
                    : context.commanderTr("Never"),
              ]),
              style: const TextStyle(fontSize: 11),
            ),
            if (!bound)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.commanderTr(
                    'Account review required. Connect the saved account or bind this pair again.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (pair.usePlaceholders)
                  IconButton(
                    icon: const Icon(Icons.cloud_download, size: 18),
                    tooltip: context.commanderTr(
                      "Download All Cloud-Only Files",
                    ),
                    onPressed: sync.isSyncing || !bound
                        ? null
                        : () async {
                            final count = await ref
                                .read(syncProvider)
                                .hydrateAllPlaceholders(pair.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    context.commanderTr(
                                      "Downloaded {0} files",
                                      [count],
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                Semantics(
                  label: context.commanderTr("Enabled"),
                  child: Switch(
                    value: pair.enabled,
                    onChanged: (v) =>
                        ref.read(syncProvider).togglePair(pair.id, v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.sync, size: 18),
                  tooltip: context.commanderTr("Compare and Review"),
                  onPressed: sync.isSyncing || !bound
                      ? null
                      : () => showSyncPlanDialog(context, pair.id),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(context.commanderTr('Bind to connected account')),
                  onPressed:
                      sync.isSyncing ||
                          !auth.client.isAuthenticated ||
                          auth.currentProvider.name != pair.provider
                      ? null
                      : () => _rebind(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  tooltip: context.commanderTr("Remove"),
                  onPressed: () => ref.read(syncProvider).removePair(pair.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rebind(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authProvider);
    final client = auth.client;
    final reviewedRemote = storageReferenceForClient(client);
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.commanderTr('Bind sync sources')),
        content: Text(
          context.commanderTr(
            'Use this device and {0} account {1} for this pair?\nLocal: {2}\nRemote: {3}\nThe old comparison baseline is cleared. Existing queued operations keep their original account binding and must be reviewed again.',
            [
              client.providerName,
              client.userId ?? '',
              pair.localPath,
              pair.remotePath,
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.commanderTr('Bind sources')),
          ),
        ],
      ),
    );
    if (approved != true || !context.mounted) return;
    try {
      if (!identical(ref.read(authProvider).client, client)) {
        throw StateError('The connected account changed during review.');
      }
      await ref
          .read(syncProvider)
          .rebindPair(pair.id, reviewedRemote: reviewedRemote);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  String _formatTime(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return context.commanderTr("Just now");
    if (diff.inHours < 1) {
      return context.commanderTr("{0} min ago", [diff.inMinutes]);
    }
    if (diff.inDays < 1) {
      return context.commanderTr("{0} h ago", [diff.inHours]);
    }
    return context.commanderTr("{0} d ago", [diff.inDays]);
  }
}

// ---------------------------------------------------------------------------
// Auto-evict tile
// ---------------------------------------------------------------------------

class _AutoEvictTile extends ConsumerWidget {
  final SyncNotifier sync;
  const _AutoEvictTile({required this.sync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SyncDialogStrings(context);
    final days = ref.watch(syncProvider).autoEvictDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_delete_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.commanderTr("Auto-evict cloud-only files"),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    days == 0
                        ? context.commanderTr(
                            "Disabled — synced files are kept locally",
                          )
                        : context.commanderTr(
                            "Free up space after {0} days without access",
                            [days],
                          ),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        DropdownButton<int>(
          value: days,
          isDense: true,
          isExpanded: true,
          items: _kAutoEvictOptions
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                    d == 0
                        ? context.commanderTr("Off")
                        : context.commanderTr("{0} d", [d]),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) ref.read(syncProvider).setAutoEvictDays(v);
          },
        ),
      ],
    );
  }
}
