import 'package:flutter/material.dart';

import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_recovery_strings.dart';
import '../l10n/terminal_strings.dart';
import '../models/terminal_workspace_recovery.dart';

/// Edits recovery preferences without replacing or disconnecting live tabs.
/// The workspace owns persistence and passes callbacks bound to its lease.
class TerminalWorkspaceRecoveryDialog extends StatefulWidget {
  const TerminalWorkspaceRecoveryDialog({
    super.key,
    required this.initialRecord,
    this.initialError,
    required this.onSave,
    required this.onForget,
    required this.onRetry,
  });

  final TerminalWorkspaceRecoveryRecord? initialRecord;
  final String? initialError;
  final Future<TerminalWorkspaceRecoveryRecord> Function(
    bool enabled,
    bool relaunchLocalShells,
  )
  onSave;
  final Future<TerminalWorkspaceRecoveryRecord> Function() onForget;
  final Future<TerminalWorkspaceRecoveryRecord> Function() onRetry;

  @override
  State<TerminalWorkspaceRecoveryDialog> createState() =>
      _TerminalWorkspaceRecoveryDialogState();
}

class _TerminalWorkspaceRecoveryDialogState
    extends State<TerminalWorkspaceRecoveryDialog> {
  TerminalWorkspaceRecoveryRecord? _record;
  String? _error;
  bool _enabled = false;
  bool _relaunch = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _setRecord(widget.initialRecord);
    _error = widget.initialError;
    if (_record == null && _error == null) {
      _error = 'Could not load session recovery. Saved data was kept.';
    }
  }

  void _setRecord(TerminalWorkspaceRecoveryRecord? value) {
    _record = value;
    _enabled = value?.enabled ?? false;
    _relaunch = _enabled && (value?.relaunchLocalShells ?? false);
  }

  Future<void> _save() async {
    if (_busy || _record == null) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(_enabled, _enabled && _relaunch);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save session recovery.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final record = await widget.onRetry();
      if (!mounted) return;
      setState(() {
        _setRecord(record);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load session recovery. Saved data was kept.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(context.terminalRecoveryTr('Forget saved workspace?')),
          content: Text(
            context.terminalRecoveryTr(
              'This turns off recovery and clears the saved workspace. Your current terminals stay open.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.terminalTr('Cancel')),
            ),
            FilledButton(
              key: const ValueKey('terminal-recovery-confirm-forget'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.terminalRecoveryTr('Forget')),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final record = await widget.onForget();
      if (!mounted) return;
      setState(() {
        _setRecord(record);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not forget saved workspace.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      key: const ValueKey('terminal-recovery-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: Text(context.terminalRecoveryTr('Session recovery')),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(
                context.terminalRecoveryTr(_error!),
                key: const ValueKey('terminal-recovery-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('terminal-recovery-retry'),
                  onPressed: _busy ? null : _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.terminalRecoveryTr('Retry')),
                ),
              ),
            ],
            Text(
              context.terminalRecoveryTr(
                'Restore tabs, panes, names, font sizes and SSH destinations when you next open the terminal.',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('terminal-recovery-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.terminalRecoveryTr('Remember terminal workspace'),
              ),
              value: _enabled,
              onChanged: _busy || _record == null
                  ? null
                  : (value) => setState(() {
                      _enabled = value;
                      if (!value) _relaunch = false;
                    }),
            ),
            SwitchListTile(
              key: const ValueKey('terminal-recovery-relaunch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.terminalRecoveryTr('Relaunch local shells')),
              value: _relaunch,
              onChanged: _busy || _record == null || !_enabled
                  ? null
                  : (value) => setState(() => _relaunch = value),
            ),
            Text(
              context.terminalRecoveryTr(
                'Start new local shells in the current local folder. Previous commands and working directories are not restored.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.terminalRecoveryTr(
                'SSH connections still ask for authentication. Passwords, terminal output and running processes are not saved.',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('terminal-recovery-forget'),
                onPressed: _busy ? null : _forget,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  context.terminalRecoveryTr('Forget saved workspace'),
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.terminalTr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('terminal-recovery-save'),
          onPressed: _busy || _record == null ? null : _save,
          child: Text(context.terminalControlsTr('Save')),
        ),
      ],
    ),
  );
}
