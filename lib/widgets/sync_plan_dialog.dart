import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  String _progress = 'Comparing directories and file contents…';

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
    });
    try {
      final plan = await ref
          .read(syncProvider)
          .planOne(widget.pairId, isCancelled: () => _cancel);
      if (mounted)
        setState(() {
          _plan = plan;
          _decisions.clear();
        });
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
          title: Text('Apply $deletions deletion(s)?'),
          content: const Text(
            'Synchronization deletions may be permanent. Review each delete direction before continuing.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply reviewed plan'),
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
      _progress = 'Checking the comparison is still current…';
    });
    try {
      final result = await ref
          .read(syncProvider)
          .executeReviewedPlan(
            plan,
            decisions: Map.of(_decisions),
            isCancelled: () => _cancel,
            onProgress: (done, total, path) {
              if (mounted) setState(() => _progress = '$done / $total: $path');
            },
          );
      if (mounted)
        setState(() {
          _result = result;
          _plan = null;
        });
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
    child: AlertDialog(
      title: Text(
        _plan == null ? 'Review synchronization' : 'Review ${_plan!.pair.name}',
      ),
      content: SizedBox(
        width: 800,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compare first, choose an action for each row, then apply. Changed files or connections invalidate the plan.',
            ),
            if (_busy) ...[const LinearProgressIndicator(), Text(_progress)],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_result != null) ...[
              Text(
                '${_result!.uploaded} uploaded • ${_result!.downloaded} downloaded • '
                '${_result!.deletedLocal + _result!.deletedRemote} deleted • ${_result!.conflicts} unresolved',
              ),
              if (_result!.cancelled)
                const Text('Cancelled; completed actions are retained.'),
              for (final error in _result!.errorMessages) Text(error),
            ],
            if (_plan != null) ...[
              Text('${_plan!.actions.length} planned action(s)'),
              if (_plan!.actions.isEmpty)
                const Text(
                  'No changes required. Applying will record the verified baseline.',
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: _plan!.actions.length,
                  itemBuilder: (context, index) {
                    final action = _plan!.actions[index];
                    return ListTile(
                      title: Text(action.relativePath),
                      subtitle: Text(
                        'Local: ${action.localModified ?? "unknown"}  •  Cloud: ${action.remoteModified ?? "unknown"}',
                      ),
                      trailing: DropdownButton<SyncActionType>(
                        value: _decisions[action.relativePath] ?? action.type,
                        items: [
                          for (final choice in _plan!.choicesFor(action))
                            DropdownMenuItem(
                              value: choice,
                              child: Text(_label(choice)),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _decisions[action.relativePath] = value!,
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_busy)
          TextButton(
            onPressed: () => setState(() => _cancel = true),
            child: const Text('Stop'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _busy ? null : _compare,
          child: const Text('Compare again'),
        ),
        FilledButton(
          onPressed: _busy || _plan == null ? null : _execute,
          child: const Text('Apply reviewed plan'),
        ),
      ],
    ),
  );
}
