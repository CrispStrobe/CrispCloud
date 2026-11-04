// lib/widgets/sync_dialog.dart
//
// Dialog for managing sync pairs: create, edit, delete, trigger sync.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/background_sync_service.dart';
import '../services/sync_database.dart';
import '../l10n/app_localizations.dart';
import '../l10n/sync_dialog_strings.dart';

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
    final t = SyncDialogStrings(context);
    final sync = ref.watch(syncProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.sync),
          const SizedBox(width: 8),
          Text(t.text('pairs')),
          const Spacer(),
          // Watch toggle
          IconButton(
            icon: Icon(
              sync.isWatchEnabled ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: sync.isWatchEnabled ? Colors.green : null,
            ),
            tooltip: sync.isWatchEnabled
                ? t.text('disableWatch')
                : t.text('enableWatch'),
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
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.sync, size: 20),
              tooltip: t.text('syncAll'),
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
                  t.text('lastResult', {
                    'up': sync.lastResult!.uploaded,
                    'down': sync.lastResult!.downloaded,
                    'conflicts': sync.lastResult!.conflicts,
                    'errors': sync.lastResult!.errors
                  }),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const Icon(Icons.sync_disabled,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(t.text('empty')),
                    const SizedBox(height: 4),
                    Text(t.text('emptyHelp'),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
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
          label: Text(t.text('replay')),
          onPressed: sync.isSyncing
              ? null
              : () async {
                  final result =
                      await ref.read(syncProvider).replayOfflineQueue();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                        result.hasChanges || result.errors > 0
                            ? t.text('replayed', {
                                'count': result.uploaded + result.downloaded,
                                'errors': result.errors
                              })
                            : t.text('noReplay'),
                      )),
                    );
                  }
                },
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(t.text('add')),
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

    final auth = ref.read(authProvider);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t.text('new')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: t.text('name'),
                      hintText: t.text('nameHint'),
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: localController,
                    decoration: InputDecoration(
                      labelText: t.text('localPath'),
                      hintText: '/home/user/Documents',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.folder),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remoteController,
                    decoration: InputDecoration(
                      labelText: t.text('remotePath'),
                      hintText: '/Documents',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.cloud),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ConflictPolicy>(
                    initialValue: policy,
                    decoration: InputDecoration(
                      labelText: t.text('policy'),
                      border: const OutlineInputBorder(),
                    ),
                    items: ConflictPolicy.values
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(_policyLabel(p, t)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => policy = v ?? policy),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SyncDirection>(
                    initialValue: direction,
                    decoration: InputDecoration(
                      labelText: t.text('direction'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: SyncDirection.twoWay,
                          child: Text(t.text('twoWay'))),
                      DropdownMenuItem(
                          value: SyncDirection.uploadOnly,
                          child: Text(t.text('uploadOnly'))),
                      DropdownMenuItem(
                          value: SyncDirection.downloadOnly,
                          child: Text(t.text('downloadOnly'))),
                    ],
                    onChanged: (v) =>
                        setState(() => direction = v ?? direction),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: includeController,
                    decoration: InputDecoration(
                      labelText: t.text('include'),
                      hintText: '*.dart, *.yaml, lib/**',
                      helperText: t.text('includeHelp'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.filter_alt),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: excludeController,
                    decoration: InputDecoration(
                      labelText: t.text('exclude'),
                      hintText: '.git/**, *.tmp, node_modules/**',
                      helperText: t.text('excludeHelp'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.filter_alt_off),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(t.text('cloud')),
                    subtitle: Text(t.text('cloudHelp')),
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
                child: Text(AppLocalizations.of(context)!.cancel)),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || localController.text.isEmpty)
                  return;
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
              child: Text(AppLocalizations.of(context)!.create),
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

class _BackgroundSyncTile extends ConsumerStatefulWidget {
  final SyncNotifier sync;
  const _BackgroundSyncTile({required this.sync});

  @override
  ConsumerState<_BackgroundSyncTile> createState() =>
      _BackgroundSyncTileState();
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
    final t = SyncDialogStrings(context);
    final sync = ref.watch(syncProvider);
    final enabled = sync.isBackgroundSyncEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.sync_lock),
          title: Text(t.text('background')),
          subtitle: Text(
            enabled
                ? t.text('every', {'count': _intervalMinutes})
                : t.text('openOnly'),
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
                Text(t.text('interval'), style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _intervalMinutes,
                  isDense: true,
                  items: [
                    DropdownMenuItem(
                        value: 15,
                        child: Text(t.text('minutes', {'count': 15}))),
                    DropdownMenuItem(
                        value: 30,
                        child: Text(t.text('minutes', {'count': 30}))),
                    DropdownMenuItem(value: 60, child: Text(t.text('hour1'))),
                    DropdownMenuItem(value: 120, child: Text(t.text('hour2'))),
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
    final t = SyncDialogStrings(context);
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
              message: t.text('cloudTooltip'),
              child: Icon(Icons.cloud_outlined,
                  size: 14, color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${pair.localPath} ↔ ${pair.remotePath}\n${t.text('lastTime', {
              'time': pair.lastSyncAt != null
                  ? _formatTime(pair.lastSyncAt!, t)
                  : t.text('never')
            })}',
        style: const TextStyle(fontSize: 11),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pair.usePlaceholders)
            IconButton(
              icon: const Icon(Icons.cloud_download, size: 18),
              tooltip: t.text('downloadAll'),
              onPressed: isActive
                  ? null
                  : () async {
                      final count = await ref
                          .read(syncProvider)
                          .hydrateAllPlaceholders(pair.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(t.text('downloaded', {'count': count}))),
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
            tooltip: t.text('now'),
            onPressed:
                isActive ? null : () => ref.read(syncProvider).syncOne(pair.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18),
            tooltip: t.text('remove'),
            onPressed: () => ref.read(syncProvider).removePair(pair.id),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt, SyncDialogStrings t) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return t.text('justNow');
    if (diff.inHours < 1)
      return t.text('agoMinutes', {'count': diff.inMinutes});
    if (diff.inDays < 1) return t.text('agoHours', {'count': diff.inHours});
    return t.text('agoDays', {'count': diff.inDays});
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

    return Row(
      children: [
        const Icon(Icons.auto_delete_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.text('evict'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              Text(
                days == 0
                    ? t.text('evictOff')
                    : t.text('evictAfter', {'count': days}),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        DropdownButton<int>(
          value: days,
          isDense: true,
          items: _kAutoEvictOptions
              .map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(
                        d == 0 ? t.text('off') : t.text('days', {'count': d})),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) ref.read(syncProvider).setAutoEvictDays(v);
          },
        ),
      ],
    );
  }
}
