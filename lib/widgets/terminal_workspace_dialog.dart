import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/terminal_workspace_strings.dart';
import '../services/cloud_storage_interface.dart';
import '../services/terminal_workspace_service.dart';

/// A newly captured connection to the workspace's original storage identity.
class TerminalWorkspaceBinding {
  const TerminalWorkspaceBinding({
    required this.client,
    required this.isCurrent,
  });
  final CloudStorageClient client;
  final bool Function() isCurrent;
}

typedef TerminalWorkspaceResolver = TerminalWorkspaceBinding? Function(
  TerminalWorkspace workspace,
);

typedef TerminalWorkspaceTask<T> = Future<T> Function(
  bool Function() isCancelled,
  void Function(int completed, int total) onProgress,
);

Future<T?> showTerminalWorkspaceTask<T>(
  BuildContext context, {
  required String title,
  required TerminalWorkspaceTask<T> task,
}) => showDialog<T>(
  context: context,
  barrierDismissible: false,
  builder: (_) => TerminalWorkspaceTaskDialog<T>(title: title, task: task),
);

/// Cancellation stays visible until the service has reached a safe checkpoint.
class TerminalWorkspaceTaskDialog<T> extends StatefulWidget {
  const TerminalWorkspaceTaskDialog({
    super.key,
    required this.title,
    required this.task,
  });
  final String title;
  final TerminalWorkspaceTask<T> task;

  @override
  State<TerminalWorkspaceTaskDialog<T>> createState() => _TaskState<T>();
}

class _TaskState<T> extends State<TerminalWorkspaceTaskDialog<T>> {
  bool _cancelled = false;
  bool _running = true;
  Object? _error;
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    try {
      final result = await widget.task(() => _cancelled || !mounted, (
        completed,
        total,
      ) {
        if (mounted) setState(() => _progress = (completed, total));
      });
      if (mounted) Navigator.of(context).pop<T>(_cancelled ? null : result);
    } catch (error) {
      if (!mounted) return;
      if (_cancelled) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _running = false;
          _error = error;
        });
      }
    }
  }

  void _cancel() {
    if (_running && !_cancelled) setState(() => _cancelled = true);
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: AlertDialog(
      title: Text(
        _error == null
            ? widget.title
            : context.workspaceTr('Workspace operation failed'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: _error != null
              ? SelectableText(_workspaceError(_error!))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LinearProgressIndicator(),
                    if (_progress case final progress?) ...[
                      const SizedBox(height: 12),
                      Text('${progress.$1} / ${progress.$2}'),
                    ],
                    if (_cancelled) ...[
                      const SizedBox(height: 12),
                      Text(context.workspaceTr('Stopping…')),
                    ],
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running
              ? _cancelled
                    ? null
                    : _cancel
              : () => Navigator.of(context).pop(),
          child: Text(context.workspaceTr(_running ? 'Cancel' : 'Close')),
        ),
      ],
    ),
  );
}

String _workspaceError(Object error) =>
    error is TerminalWorkspaceException ? error.message : error.toString();

Future<void> reviewTerminalWorkspace(
  BuildContext context, {
  required TerminalWorkspaceService service,
  required TerminalWorkspace workspace,
  required TerminalWorkspaceResolver resolve,
}) async {
  final changes =
      await showTerminalWorkspaceTask<List<TerminalWorkspaceChange>>(
        context,
        title: context.workspaceTr('Review uploads'),
        task: (cancelled, _) =>
            service.inspect(workspace.id, isCancelled: cancelled),
      );
  if (!context.mounted || changes == null) return;
  final selected = await showDialog<List<TerminalWorkspaceChange>>(
    context: context,
    builder: (_) =>
        TerminalWorkspaceReviewDialog(workspace: workspace, changes: changes),
  );
  if (!context.mounted || selected == null || selected.isEmpty) return;
  // Resolve after review. The active pane/account never replaces this identity.
  final binding = resolve(workspace);
  if (binding == null || !binding.isCurrent()) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          context.workspaceTr(
            'Reconnect the original cloud account to upload.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.workspaceTr('Close')),
          ),
        ],
      ),
    );
    return;
  }
  final result = await showTerminalWorkspaceTask<TerminalWorkspaceUploadResult>(
    context,
    title: context.workspaceTr('Uploading…'),
    task: (cancelled, _) => service.uploadReviewed(
      workspaceId: workspace.id,
      client: binding.client,
      changes: selected,
      isCurrent: binding.isCurrent,
      isCancelled: cancelled,
    ),
  );
  if (!context.mounted || result == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.workspaceTr('Upload results')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final path in result.uploadedPaths)
                Text('${context.workspaceTr('Uploaded')}: $path'),
              for (final path in result.skippedPaths)
                Text('${context.workspaceTr('Kept locally')}: $path'),
              for (final entry in result.failures.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    '${context.workspaceTr('Kept locally')}: ${entry.key}\n${entry.value}',
                  ),
                ),
              for (final warning in result.workspace.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(warning),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.workspaceTr('Close')),
        ),
      ],
    ),
  );
}

class TerminalWorkspaceReviewDialog extends StatefulWidget {
  const TerminalWorkspaceReviewDialog({
    super.key,
    required this.workspace,
    required this.changes,
  });
  final TerminalWorkspace workspace;
  final List<TerminalWorkspaceChange> changes;

  @override
  State<TerminalWorkspaceReviewDialog> createState() => _ReviewState();
}

class _ReviewState extends State<TerminalWorkspaceReviewDialog> {
  late final Set<String> _selected = {
    for (final change in widget.changes)
      if (change.canUpload) change.relativePath,
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${context.workspaceTr('Review uploads')} · ${widget.workspace.title}',
    ),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.workspace.storage.provider} · ${widget.workspace.remoteRoot}',
            ),
            const SizedBox(height: 8),
            Text(
              context.workspaceTr(
                'Remote files are never deleted by this workspace.',
              ),
            ),
            if (widget.changes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(context.workspaceTr('No local changes.')),
              ),
            for (final change in widget.changes)
              CheckboxListTile(
                key: ValueKey('workspace-change-${change.relativePath}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(change.relativePath),
                onChanged: !change.canUpload
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(change.relativePath);
                        } else {
                          _selected.remove(change.relativePath);
                        }
                      }),
                title: Text(change.relativePath),
                subtitle: Text(
                  [
                    context.workspaceTr(switch (change.kind) {
                      TerminalWorkspaceChangeKind.added => 'New',
                      TerminalWorkspaceChangeKind.modified => 'Modified',
                      TerminalWorkspaceChangeKind.deleted => 'Deleted locally',
                      TerminalWorkspaceChangeKind.unsafe => 'Blocked',
                    }),
                    if (change.reason != null) change.reason!,
                  ].join(' · '),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.workspaceTr('Close')),
      ),
      FilledButton(
        key: const ValueKey('workspace-upload-selected'),
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.of(context).pop(
                widget.changes
                    .where(
                      (change) =>
                          change.canUpload &&
                          _selected.contains(change.relativePath),
                    )
                    .toList(),
              ),
        child: Text(context.workspaceTr('Upload selected')),
      ),
    ],
  );
}

class TerminalWorkspacesDialog extends StatefulWidget {
  const TerminalWorkspacesDialog({
    super.key,
    required this.service,
    required this.resolve,
  });
  final TerminalWorkspaceService service;
  final TerminalWorkspaceResolver resolve;

  @override
  State<TerminalWorkspacesDialog> createState() => _WorkspacesState();
}

class _WorkspacesState extends State<TerminalWorkspacesDialog> {
  List<TerminalWorkspace>? _workspaces;
  Object? _error;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final workspaces = await widget.service.list();
      if (mounted && generation == _generation) {
        setState(() => _workspaces = workspaces);
      }
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(TerminalWorkspace workspace) async {
    setState(() => _busy = true);
    try {
      final current = await widget.service.load(workspace.id);
      if (!mounted) return;
      if (current == null) {
        await _load();
      } else {
        Navigator.of(context).pop(current);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _busy = false;
        });
      }
    }
  }

  Future<void> _review(TerminalWorkspace workspace) async {
    setState(() => _busy = true);
    try {
      await reviewTerminalWorkspace(
        context,
        service: widget.service,
        workspace: workspace,
        resolve: widget.resolve,
      );
    } finally {
      if (mounted) await _load();
    }
  }

  Future<void> _resume(TerminalWorkspace workspace) async {
    final binding = widget.resolve(workspace);
    if (binding == null || !binding.isCurrent()) {
      setState(
        () => _error = StateError(
          context.workspaceTr(
            'Reconnect the original cloud account to upload.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    await showTerminalWorkspaceTask<TerminalWorkspace>(
      context,
      title: context.workspaceTr('Staging files…'),
      task: (cancelled, _) => widget.service.resumeStage(
        workspaceId: workspace.id,
        client: binding.client,
        isCurrent: binding.isCurrent,
        isCancelled: cancelled,
      ),
    );
    if (mounted) await _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.workspaceTr('Staged workspaces')),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.workspaceTr(
                'Local copies stay available after closing the terminal.',
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) SelectableText(_workspaceError(_error!)),
            for (final warning in widget.service.warnings) Text(warning),
            if (_workspaces?.isEmpty == true)
              Text(context.workspaceTr('No staged workspaces.')),
            for (final workspace in _workspaces ?? <TerminalWorkspace>[])
              ListTile(
                key: ValueKey('workspace-${workspace.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(workspace.title),
                subtitle: Text(
                  '${workspace.storage.provider} · ${workspace.remoteRoot}'
                  '${workspace.error == null ? '' : '\n${workspace.error}'}',
                ),
                onTap: _busy ? null : () => _open(workspace),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (workspace.entries.any(
                      (entry) =>
                          entry.status == TerminalWorkspaceEntryStatus.pending,
                    ))
                      IconButton(
                        tooltip: context.workspaceTr('Resume download'),
                        onPressed: _busy ? null : () => _resume(workspace),
                        icon: const Icon(Icons.download),
                      ),
                    IconButton(
                      tooltip: context.workspaceTr('Review uploads'),
                      onPressed: _busy ? null : () => _review(workspace),
                      icon: const Icon(Icons.upload_outlined),
                    ),
                    IconButton(
                      tooltip: context.workspaceTr('Open shell'),
                      onPressed: _busy ? null : () => _open(workspace),
                      icon: const Icon(Icons.terminal),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : _load,
        child: Text(context.workspaceTr('Refresh')),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.workspaceTr('Close')),
      ),
    ],
  );
}
