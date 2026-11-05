import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import 'commander_review_dialog.dart';
import '../providers/sync_provider.dart';
import '../services/sync_engine.dart';

Future<void> showSyncPlanDialog(BuildContext context, int pairId) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SyncPlanDialog(pairId: pairId),
    );

class _SyncPlanDialog extends ConsumerStatefulWidget {
  const _SyncPlanDialog({required this.pairId});
  final int pairId;
  @override
  ConsumerState<_SyncPlanDialog> createState() => _SyncPlanDialogState();
}

class _SyncPlanDialogState extends ConsumerState<_SyncPlanDialog> {
  SyncPlan? _plan;
  final _decisions = <String, SyncActionType>{};
  bool _busy = true;
  bool _cancel = false;
  String? _error;
  SyncResult? _result;
  String Function(BuildContext) _progress = (context) =>
      context.commanderTr("Comparing directories and file contents…");

  @override
  void initState() {
    super.initState();
    _compare();
  }

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  Future<void> _compare() async {
    setState(() {
      _busy = true;
      _cancel = false;
      _error = null;
      _result = null;
      _progress = (context) =>
          context.commanderTr("Comparing directories and file contents…");
    });
    try {
      final plan = await ref
          .read(syncProvider)
          .planOne(widget.pairId, isCancelled: () => _cancel);
      if (mounted) {
        setState(() {
          _plan = plan;
          _decisions.clear();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute() async {
    final plan = _plan!;
    final deletions = plan.actions
        .where(
          (action) => const [
            SyncActionType.deleteLocal,
            SyncActionType.deleteRemote,
          ].contains(_decisions[action.relativePath] ?? action.type),
        )
        .length;
    if (deletions > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            context.commanderTr("Apply {0} deletion(s)?", [deletions]),
          ),
          content: Text(
            context.commanderTr(
              "Synchronization deletions may be permanent. Review each delete direction before continuing.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.commanderTr("Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.commanderTr("Apply reviewed plan")),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _cancel = false;
      _error = null;
      _progress = (context) =>
          context.commanderTr("Checking the comparison is still current…");
    });
    try {
      final result = await ref
          .read(syncProvider)
          .executeReviewedPlan(
            plan,
            decisions: Map.of(_decisions),
            isCancelled: () => _cancel,
            onProgress: (done, total, path) {
              if (mounted) {
                setState(() => _progress = (_) => '$done / $total: $path');
              }
            },
          );
      if (mounted) {
        setState(() {
          _result = result;
          _plan = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(SyncActionType type) => switch (type) {
    SyncActionType.upload => 'Local → Cloud',
    SyncActionType.download => 'Cloud → Local',
    SyncActionType.keepBoth => 'Keep both versions',
    SyncActionType.skip => 'Skip',
    SyncActionType.deleteLocal => 'Delete local',
    SyncActionType.deleteRemote => 'Delete cloud',
    SyncActionType.createLocalFolder => 'Create local folder',
    SyncActionType.createRemoteFolder => 'Create cloud folder',
    SyncActionType.conflict => 'Unresolved conflict',
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: CommanderReviewDialog(
      title: _plan == null
          ? context.commanderTr("Review synchronization")
          : context.commanderTr("Review {0}", [_plan!.pair.name]),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.commanderTr(
                  "Compare first, choose an action for each row, then apply. Changed files or connections invalidate the plan.",
                ),
              ),
              if (_busy) ...[
                const LinearProgressIndicator(),
                Semantics(liveRegion: true, child: Text(_progress(context))),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_result != null) ...[
                Text(
                  context.commanderTr(
                    "{0} uploaded • {1} downloaded • {2} deleted • {3} unresolved",
                    [
                      _result!.uploaded,
                      _result!.downloaded,
                      _result!.deletedLocal + _result!.deletedRemote,
                      _result!.conflicts,
                    ],
                  ),
                ),
                if (_result!.cancelled)
                  Text(
                    context.commanderTr(
                      "Cancelled; completed actions are retained.",
                    ),
                  ),
                for (final error in _result!.errorMessages) Text(error),
              ],
              if (_plan != null) ...[
                Text(
                  context.commanderTr("{0} planned action(s)", [
                    _plan!.actions.length,
                  ]),
                ),
                if (_plan!.actions.isEmpty)
                  Text(
                    context.commanderTr(
                      "No changes required. Applying will record the verified baseline.",
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (_plan != null)
          SliverList.builder(
            itemCount: _plan!.actions.length,
            itemBuilder: (context, index) {
              final action = _plan!.actions[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.relativePath,
                        textDirection: TextDirection.ltr,
                      ),
                      Text(
                        context.commanderTr("Local: {0}  •  Cloud: {1}", [
                          action.localModified ??
                              context.commanderTr("Unknown"),
                          action.remoteModified ??
                              context.commanderTr("Unknown"),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<SyncActionType>(
                        key: ValueKey('sync-action-${action.relativePath}'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.commanderTr("Action"),
                        ),
                        initialValue:
                            _decisions[action.relativePath] ?? action.type,
                        items: [
                          for (final choice in _plan!.choicesFor(action))
                            DropdownMenuItem(
                              value: choice,
                              child: Text(
                                context.commanderTr(_label(choice)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _decisions[action.relativePath] = value!,
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
      actions: [
        if (_busy)
          TextButton(
            onPressed: () => setState(() => _cancel = true),
            child: Text(context.commanderTr("Stop")),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.commanderTr("Close")),
        ),
        TextButton(
          onPressed: _busy ? null : _compare,
          child: Text(context.commanderTr("Compare again")),
        ),
        FilledButton(
          onPressed: _busy || _plan == null ? null : _execute,
          child: Text(context.commanderTr("Apply reviewed plan")),
        ),
      ],
    ),
  );
}
