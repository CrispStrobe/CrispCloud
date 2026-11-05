import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../providers/trash_history_provider.dart';
import '../services/trash_history_store.dart';

Future<void> showTrashHistoryDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => TrashHistoryDialog(side: side),
  );
  if (context.mounted) ref.read(panelProvider(side)).focusList();
}

class TrashHistoryDialog extends ConsumerStatefulWidget {
  const TrashHistoryDialog({super.key, required this.side});
  final PanelSide side;
  @override
  ConsumerState<TrashHistoryDialog> createState() => _TrashHistoryDialogState();
}

class _TrashHistoryDialogState extends ConsumerState<TrashHistoryDialog> {
  String? _busy;
  String? _error;

  Future<void> _restore(TrashRecord record) async {
    setState(() {
      _busy = record.id;
      _error = null;
    });
    try {
      await ref.read(panelProvider(widget.side)).restoreTrashRecord(record.id);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(trashHistoryProvider);
    final panel = ref.watch(panelProvider(widget.side));
    final records = store.records;
    return PopScope(
      canPop: _busy == null,
      child: AlertDialog(
        title: Text(context.commanderTr("Trash history and restore")),
        content: SizedBox(
          width: 740,
          height: 500,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.commanderTr(
                        "Restore returns an item to its original path and account. An occupied path is never replaced. System or provider trash retention still applies.",
                      ),
                    ),
                    if (_busy != null) const LinearProgressIndicator(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (store.errors.isNotEmpty)
                      ExpansionTile(
                        title: Text(
                          context.commanderTr(
                            "History storage needs attention",
                          ),
                        ),
                        children: [SelectableText(store.errors.join('\n'))],
                      ),
                    if (records.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.commanderTr("No recorded trash operations."),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final record = records[index];
                  final origin = panel.resolveStorageReference(
                    record.file.storage,
                    record.file.path,
                  );
                  final ready =
                      record.receipt != null &&
                      record.state != TrashRecordState.restored &&
                      origin != null;
                  final status = switch (record.state) {
                    TrashRecordState.pending => 'Interrupted before a receipt was saved; inspect the original path and trash.',
                    TrashRecordState.trashed => 'In trash',
                    TrashRecordState.restoring => 'Restore interrupted; inspect the original path before retrying.',
                    TrashRecordState.restored => 'Restored',
                    TrashRecordState.uncertain => 'Needs review',
                  };
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          SelectableText(record.file.path),
                          Text(
                            '${panel.storageDisplayName(record.file.storage)} · ${context.commanderTr(status)}',
                          ),
                          if (!record.file.storage.persistent)
                            Text(
                              context.commanderTr(
                                "Original source was available for that session only.",
                              ),
                            ),
                          if (origin == null)
                            Text(
                              context.commanderTr(
                                "Reconnect the original account or installation to restore.",
                              ),
                            ),
                          if (record.detail != null) Text(record.detail!),
                          if (record.state != TrashRecordState.restored)
                            TextButton.icon(
                              onPressed: _busy == null && ready
                                  ? () => _restore(record)
                                  : null,
                              icon: const Icon(Icons.restore_from_trash),
                              label: Text(
                                context.commanderTr("Restore original item"),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }, childCount: records.length),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy != null
                ? null
                : () async {
                    try {
                      await store.clearRestored();
                    } catch (error) {
                      if (mounted) setState(() => _error = '$error');
                    }
                  },
            child: Text(context.commanderTr("Clear restored history")),
          ),
          TextButton(
            onPressed: _busy != null ? null : () => Navigator.pop(context),
            child: Text(context.commanderTr("Close")),
          ),
        ],
      ),
    );
  }
}
