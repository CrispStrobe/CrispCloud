import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/rename_batch.dart';
import '../providers/panel_provider.dart';
import '../services/rename_batch_service.dart';
import '../services/rename_batch_storage.dart';
import '../services/rename_batch_store.dart';
import 'rename_text_dialog.dart';

SourceRenameBatchStorage createPanelRenameStorage(
  WidgetRef ref,
  PanelNotifier panel,
  PanelFileOrigin origin,
) => panel.createRenameStorage(origin);

Future<RenameBatchRecord?> showRenameHistoryDialog(
  BuildContext context,
  WidgetRef ref,
  PanelSide side,
) => showDialog<RenameBatchRecord>(
  context: context,
  barrierDismissible: false,
  builder: (_) => RenameHistoryDialog(side: side),
);

class RenameHistoryDialog extends ConsumerStatefulWidget {
  const RenameHistoryDialog({super.key, required this.side});
  final PanelSide side;
  @override
  ConsumerState<RenameHistoryDialog> createState() =>
      _RenameHistoryDialogState();
}

class _RenameHistoryDialogState extends ConsumerState<RenameHistoryDialog> {
  late final _store = ref.read(renameBatchStoreProvider);
  late final _service = RenameBatchService(_store);
  late final _panel = ref.read(panelProvider(widget.side));
  PanelFileOrigin? _origin;
  SourceRenameBatchStorage? _storage;
  List<RenameBatchRecord>? _records;
  RenameBatchRecord? _lastChanged;
  String? _error;
  bool _busy = false;
  bool _cancel = false;
  RenameBatchProgress? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await _store.list();
      if (mounted) setState(() => _records = records);
    } catch (error) {
      if (mounted) {
        setState(() {
          _records = [];
          _error = 'History could not be read: $error';
        });
      }
    }
  }

  PanelFileOrigin? _resolveOrigin(RenameBatchRecord record) =>
      record.items.isEmpty
      ? null
      : _panel.resolveStorageReference(
          record.storage,
          record.items.first.currentPath,
        );

  bool _available(RenameBatchRecord record) =>
      _resolveOrigin(record)?.isCurrent == true;

  bool _bindStorage(RenameBatchRecord record) {
    final origin = _resolveOrigin(record);
    if (origin == null || !origin.isCurrent) {
      setState(
        () => _error = 'Connect the original storage account before recovering this batch.',
      );
      return false;
    }
    _origin = origin;
    _storage = createPanelRenameStorage(ref, _panel, origin);
    return true;
  }

  Future<bool> _confirm(RenameBatchRecord record, bool restore) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            restore
                ? context.commanderTr("Restore this batch?")
                : context.commanderTr("Resume this batch?"),
          ),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                restore
                    ? context.commanderTr(
                        "Restore {0} original names. Existing destinations and changed source items are checked again.",
                        [record.changedCount],
                      )
                    : context.commanderTr(
                        "Continue the saved physical rename steps on {0}. Completed steps are reconciled before continuing.",
                        [record.storage.provider],
                      ),
              ),
              const SizedBox(height: 12),
              for (final item in record.items.where(
                (item) => item.sourcePath != item.targetPath,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${item.currentPath}\n→ ${restore ? item.sourcePath : item.targetPath}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.commanderTr("Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                restore
                    ? context.commanderTr("Restore original names")
                    : context.commanderTr("Resume"),
              ),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(RenameBatchRecord record, {required bool restore}) async {
    if (!_available(record) || !await _confirm(record, restore) || !mounted) {
      return;
    }
    if (!_bindStorage(record)) return;
    final before = {
      for (final item in record.items) item.sourcePath: item.currentPath,
    };
    setState(() {
      _busy = true;
      _cancel = false;
      _error = null;
    });
    try {
      void progress(RenameBatchProgress value) {
        if (mounted) setState(() => _progress = value);
      }

      if (restore) {
        await _service.restore(
          record,
          _storage!,
          isCancelled: () => _cancel,
          onProgress: progress,
        );
      } else {
        await _service.run(
          record,
          _storage!,
          isCancelled: () => _cancel,
          onProgress: progress,
        );
      }
      _lastChanged = record;
      if (record.message != null && mounted) {
        setState(() => _error = record.message);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _lastChanged = record;
      if (_origin?.isCurrent == true) {
        final changes = <String, FileItem>{
          for (final item in record.items)
            if (before[item.sourcePath] != item.currentPath)
              before[item.sourcePath]!: item.asFile(
                _storage!.paths.basename(item.currentPath),
                storageId: record.storage.id,
              ),
        };
        _panel.applyFileListChanges(changes, origin: _origin);
        await _panel.refresh();
      }
      await _load();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(RenameBatchRecord record) async {
    final step = record.steps
        .where(
          (step) =>
              step.state == RenameStepState.inFlight ||
              step.state == RenameStepState.restoring,
        )
        .firstOrNull;
    if (step == null) return;
    final reverse = step.state == RenameStepState.restoring;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.commanderTr("Verify the observed destination")),
        scrollable: true,
        content: Text(
          context.commanderTr(
            "This provider cannot automatically prove which item survived an interrupted rename. Inspect the destination using your provider before proceeding.\n\nOriginal: {0}\nObserved destination: {1}\n\nOnly confirm if the destination contains the original item. Both paths existing, or a known fingerprint mismatch, will still block recovery.",
            [reverse ? step.to : step.from, reverse ? step.from : step.to],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.commanderTr("Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.commanderTr("I verified this destination")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!_bindStorage(record)) return;
    final before = {
      for (final item in record.items) item.sourcePath: item.currentPath,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.acknowledgeObservedDestination(record, _storage!);
      _lastChanged = record;
      if (_origin?.isCurrent == true) {
        _panel.applyFileListChanges({
          for (final item in record.items)
            if (before[item.sourcePath] != item.currentPath)
              before[item.sourcePath]!: item.asFile(
                _storage!.paths.basename(item.currentPath),
                storageId: record.storage.id,
              ),
        }, origin: _origin);
        await _panel.refresh();
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report(RenameBatchRecord record) => showDialog<String>(
    context: context,
    builder: (_) => RenameTextDialog(
      title: context.commanderTr("Rename batch report"),
      instructions: context.commanderTr(
        "Original, current and intended paths, verified physical steps and any recovery decisions.",
      ),
      initialText: const JsonEncoder.withIndent('  ').convert(record.toJson()),
      submitLabel: context.commanderTr("Close"),
      filename: 'rename-${record.id}.json',
      fileExtensions: const ['json'],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 900,
        height: (MediaQuery.sizeOf(context).height - 32).clamp(300, 780),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.commanderTr("Rename history and recovery"),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.commanderTr(
                  "Every batch retains its complete item list. Resume interrupted work or restore names after reconnecting the original storage account.",
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _records == null
                    ? const Center(child: CircularProgressIndicator())
                    : _records!.isEmpty
                    ? Center(
                        child: Text(
                          context.commanderTr(
                            "No rename batches have been recorded.",
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _records!.length,
                        itemBuilder: (context, index) {
                          final record = _records![index];
                          final available = _available(record) && !_busy;
                          return ExpansionTile(
                            key: ValueKey('rename-history-${record.id}'),
                            title: Text(
                              context.commanderTr("{0} items · {1}", [
                                record.changedCount,
                                context.commanderEnum(record.state),
                              ]),
                            ),
                            subtitle: Text(
                              '${record.created.toLocal()} · ${record.storage.provider}${_available(record) ? '' : ' · ${context.commanderTr("Connect original account")}'}',
                            ),
                            children: [
                              if (!record.exclusiveMoves)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    context.commanderTr(
                                      "This provider checks destinations before each move but does not guarantee an exclusive rename.",
                                    ),
                                  ),
                                ),
                              SizedBox(
                                height: math.min(
                                  240.0,
                                  record.items.length * 78.0,
                                ),
                                child: ListView.builder(
                                  itemCount: record.items.length,
                                  itemBuilder: (context, index) {
                                    final item = record.items[index];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        item.currentPath,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        context.commanderTr(
                                          "Original: {0}\nPlanned: {1}",
                                          [item.sourcePath, item.targetPath],
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      isThreeLine: true,
                                    );
                                  },
                                ),
                              ),
                              if (record.message != null)
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    record.message!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (!record.isComplete && !record.isRestored)
                                    FilledButton.tonal(
                                      onPressed: available
                                          ? () => _run(record, restore: false)
                                          : null,
                                      child: Text(
                                        record.restoring
                                            ? context.commanderTr(
                                                "Continue restore",
                                              )
                                            : context.commanderTr("Resume"),
                                      ),
                                    ),
                                  if (record.canRestore)
                                    FilledButton.tonal(
                                      onPressed: available
                                          ? () => _run(record, restore: true)
                                          : null,
                                      child: Text(
                                        context.commanderTr(
                                          "Restore original names",
                                        ),
                                      ),
                                    ),
                                  if (record.state ==
                                      RenameBatchState.needsReview)
                                    TextButton(
                                      onPressed: available
                                          ? () => _verify(record)
                                          : null,
                                      child: Text(
                                        context.commanderTr(
                                          "Verify observed destination",
                                        ),
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _report(record),
                                    child: Text(
                                      context.commanderTr("Report / export"),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      ),
              ),
              if (_store.warnings.isNotEmpty)
                Text(
                  _store.warnings.join('\n'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress == null || _progress!.total == 0
                      ? null
                      : _progress!.completed / _progress!.total,
                ),
                Text(
                  _cancel
                      ? context.commanderTr(
                          "Stopping after the current operation…",
                        )
                      : _progress?.message ??
                            context.commanderTr("Checking recovery state…"),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? () => setState(() => _cancel = true)
                      : () => Navigator.pop(context, _lastChanged),
                  child: Text(
                    _busy
                        ? context.commanderTr("Stop after current operation")
                        : context.commanderTr("Close"),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
