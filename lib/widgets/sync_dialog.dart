// lib/widgets/sync_dialog.dart
//
// Dialog for managing sync pairs: create, edit, delete, trigger sync.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/background_sync_service.dart';
import '../services/sync_database.dart';
import '../l10n/app_localizations.dart';

// Auto-evict options: 0=disabled, then days
const _kAutoEvictOptions = [0, 7, 14, 30, 60, 90];

void showSyncDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _SyncManagerDialog(),
  );
}

class _SyncManagerDialog extends ConsumerWidget {
  const _SyncManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.sync),
          const SizedBox(width: 8),
          const Text('Sync Pairs'),
          const Spacer(),
          // Watch toggle
          IconButton(
            icon: Icon(
              sync.isWatchEnabled ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: sync.isWatchEnabled ? Colors.green : null,
            ),
            tooltip: sync.isWatchEnabled ? 'Disable Auto-Sync' : 'Enable Auto-Sync (watch for changes)',
            onPressed: () {
              if (sync.isWatchEnabled) {
                ref.read(syncProvider).disableWatch();
              } else {
                ref.read(syncProvider).enableWatch();
              }
            },
          ),
          if (sync.isSyncing)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.sync, size: 20),
              tooltip: 'Sync All',
              onPressed: sync.pairs.isEmpty ? null : () => ref.read(syncProvider).syncAll(),
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
                  'Last sync: ${sync.lastResult!.uploaded} up, ${sync.lastResult!.downloaded} down, '
                  '${sync.lastResult!.conflicts} conflicts, ${sync.lastResult!.errors} errors',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Background sync toggle (Android / iOS only)
            if (BackgroundSyncService.isSupported) ...[
              _BackgroundSyncTile(sync: sync),
              const Divider(height: 20),
            ],
            // Auto-evict setting (applies to all pairs with placeholders)
            _AutoEvictTile(sync: sync),
            const Divider(height: 20),
            if (sync.pairs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.sync_disabled, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('No sync pairs configured'),
                    SizedBox(height: 4),
                    Text('Add a pair to keep local and remote folders in sync.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sync.pairs.length,
                  itemBuilder: (context, index) {
                    final pair = sync.pairs[index];
                    return _SyncPairTile(pair: pair);
                  },
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
          label: const Text('Replay Offline'),
          onPressed: sync.isSyncing ? null : () async {
            final result = await ref.read(syncProvider).replayOfflineQueue();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(
                  result.hasChanges || result.errors > 0
                      ? 'Replayed: ${result.uploaded + result.downloaded} ops, ${result.errors} errors'
                      : 'No offline operations to replay',
                )),
              );
            }
          },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Pair'),
          onPressed: () => _showAddPairDialog(context, ref),
        ),
      ],
    );
  }

  void _showAddPairDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final localController = TextEditingController();
    final remoteController = TextEditingController(text: '/');
    final includeController = TextEditingController();
    final excludeController = TextEditingController();
    var policy = ConflictPolicy.newestWins;
    var direction = SyncDirection.twoWay;
    var usePlaceholders = false;

    final auth = ref.read(authProvider);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New Sync Pair'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g., Documents Sync',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: localController,
                    decoration: const InputDecoration(
                      labelText: 'Local Folder Path',
                      hintText: '/home/user/Documents',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.folder),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remoteController,
                    decoration: const InputDecoration(
                      labelText: 'Remote Folder Path',
                      hintText: '/Documents',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.cloud),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ConflictPolicy>(
                    initialValue: policy,
                    decoration: const InputDecoration(
                      labelText: 'Conflict Policy',
                      border: OutlineInputBorder(),
                    ),
                    items: ConflictPolicy.values.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(_policyLabel(p)),
                    )).toList(),
                    onChanged: (v) => setState(() => policy = v ?? policy),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SyncDirection>(
                    initialValue: direction,
                    decoration: const InputDecoration(
                      labelText: 'Direction',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: SyncDirection.twoWay, child: Text('Two-Way')),
                      DropdownMenuItem(value: SyncDirection.uploadOnly, child: Text('Upload Only')),
                      DropdownMenuItem(value: SyncDirection.downloadOnly, child: Text('Download Only')),
                    ],
                    onChanged: (v) => setState(() => direction = v ?? direction),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: includeController,
                    decoration: const InputDecoration(
                      labelText: 'Include Patterns (optional)',
                      hintText: '*.dart, *.yaml, lib/**',
                      helperText: 'Comma-separated globs. Empty = all files.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.filter_alt),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: excludeController,
                    decoration: const InputDecoration(
                      labelText: 'Exclude Patterns (optional)',
                      hintText: '.git/**, *.tmp, node_modules/**',
                      helperText: 'Comma-separated globs to skip.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.filter_alt_off),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Cloud-only files'),
                    subtitle: const Text(
                      'New remote files appear as lightweight stubs. '
                      'Download on demand to save disk space.',
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.cancel)),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || localController.text.isEmpty) return;
                await ref.read(syncProvider).addPair(
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
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  String _policyLabel(ConflictPolicy p) {
    switch (p) {
      case ConflictPolicy.newestWins: return 'Newest Wins';
      case ConflictPolicy.localWins: return 'Local Wins';
      case ConflictPolicy.remoteWins: return 'Remote Wins';
      case ConflictPolicy.keepBoth: return 'Keep Both';
      case ConflictPolicy.manual: return 'Ask Me';
    }
  }
}

// ---------------------------------------------------------------------------
// Background sync tile
// ---------------------------------------------------------------------------

class _BackgroundSyncTile extends ConsumerStatefulWidget {
  final SyncNotifier sync;
  const _BackgroundSyncTile({required this.sync});

  @override
  ConsumerState<_BackgroundSyncTile> createState() => _BackgroundSyncTileState();
}

class _BackgroundSyncTileState extends ConsumerState<_BackgroundSyncTile> {
  late int _intervalMinutes;

  @override
  void initState() {
    super.initState();
    _intervalMinutes = widget.sync.backgroundSyncIntervalMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncProvider);
    final enabled = sync.isBackgroundSyncEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sync_lock),
          title: const Text('Background Sync'),
          subtitle: Text(
            enabled
                ? 'Syncing every $_intervalMinutes min'
                : 'Sync only when the app is open',
            style: const TextStyle(fontSize: 12),
          ),
          value: enabled,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) async {
            if (v) {
              await ref.read(syncProvider).enableBackgroundSync(
                    intervalMinutes: _intervalMinutes,
                  );
            } else {
              await ref.read(syncProvider).disableBackgroundSync();
            }
          },
        ),
        if (enabled)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                const Text('Interval:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _intervalMinutes,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 15, child: Text('15 min')),
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                    DropdownMenuItem(value: 60, child: Text('1 hour')),
                    DropdownMenuItem(value: 120, child: Text('2 hours')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _intervalMinutes = v);
                    await ref.read(syncProvider).enableBackgroundSync(
                          intervalMinutes: v,
                        );
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
    final sync = ref.watch(syncProvider);
    final isActive = sync.isSyncing && sync.currentPairName == pair.name;

    return ListTile(
      leading: Icon(
        pair.enabled ? Icons.sync : Icons.sync_disabled,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Row(
        children: [
          Text(pair.name),
          if (pair.usePlaceholders) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Cloud-only mode: files download on demand',
              child: Icon(Icons.cloud_outlined, size: 14,
                  color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${pair.localPath} ↔ ${pair.remotePath}\n'
        'Last sync: ${pair.lastSyncAt != null ? _formatTime(pair.lastSyncAt!) : 'Never'}',
        style: const TextStyle(fontSize: 11),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pair.usePlaceholders)
            IconButton(
              icon: const Icon(Icons.cloud_download, size: 18),
              tooltip: 'Download All Cloud-Only Files',
              onPressed: isActive ? null : () async {
                final count = await ref.read(syncProvider).hydrateAllPlaceholders(pair.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Downloaded $count files')),
                  );
                }
              },
            ),
          Switch(
            value: pair.enabled,
            onChanged: (v) => ref.read(syncProvider).togglePair(pair.id, v),
          ),
          IconButton(
            icon: const Icon(Icons.sync, size: 18),
            tooltip: 'Sync Now',
            onPressed: isActive ? null : () => ref.read(syncProvider).syncOne(pair.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18),
            tooltip: 'Remove',
            onPressed: () => ref.read(syncProvider).removePair(pair.id),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
    final days = ref.watch(syncProvider).autoEvictDays;

    return Row(
      children: [
        const Icon(Icons.auto_delete_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Auto-evict cloud-only files',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text(
                days == 0
                    ? 'Disabled — synced files are kept locally'
                    : 'Free up space after $days days without access',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        DropdownButton<int>(
          value: days,
          isDense: true,
          items: _kAutoEvictOptions.map((d) => DropdownMenuItem(
            value: d,
            child: Text(d == 0 ? 'Off' : '${d}d'),
          )).toList(),
          onChanged: (v) {
            if (v != null) ref.read(syncProvider).setAutoEvictDays(v);
          },
        ),
      ],
    );
  }
}
