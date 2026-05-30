// lib/widgets/sync_dialog.dart
//
// Dialog for managing sync pairs: create, edit, delete, trigger sync.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/sync_database.dart';

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
          child: const Text('Close'),
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
                    value: policy,
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
                    value: direction,
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
      title: Text(pair.name),
      subtitle: Text(
        '${pair.localPath} ↔ ${pair.remotePath}\n'
        'Last sync: ${pair.lastSyncAt != null ? _formatTime(pair.lastSyncAt!) : 'Never'}',
        style: const TextStyle(fontSize: 11),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
