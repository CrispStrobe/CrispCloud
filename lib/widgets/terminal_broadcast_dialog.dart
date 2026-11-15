import 'package:flutter/material.dart';

import '../l10n/terminal_broadcast_strings.dart';
import '../l10n/terminal_strings.dart';
import '../services/terminal_broadcast.dart';

/// Returns only the exact connections explicitly reviewed in this dialog.
class TerminalBroadcastDialog extends StatefulWidget {
  const TerminalBroadcastDialog({
    super.key,
    required this.candidates,
    this.initiallySelected = const {},
  });

  final List<TerminalBroadcastTarget> candidates;
  final Set<Object> initiallySelected;

  @override
  State<TerminalBroadcastDialog> createState() =>
      _TerminalBroadcastDialogState();
}

class _TerminalBroadcastDialogState extends State<TerminalBroadcastDialog> {
  late final Set<Object> _selected;
  bool _changedConnection = false;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final target in widget.candidates)
        if (target.isCurrent && widget.initiallySelected.contains(target.id))
          target.id,
    };
    for (final target in widget.candidates) {
      target.session.addListener(_connectionsChanged);
    }
  }

  void _connectionsChanged() {
    if (!mounted) return;
    setState(() {
      for (final target in widget.candidates) {
        if (!target.isCurrent && _selected.remove(target.id)) {
          _changedConnection = true;
        }
      }
    });
  }

  void _confirm() {
    final selected = widget.candidates
        .where((target) => _selected.contains(target.id))
        .toList();
    if (selected.length < 2 ||
        selected.length > TerminalBroadcast.maximumMembers ||
        selected.any((target) => !target.isCurrent)) {
      setState(() => _changedConnection = true);
      return;
    }
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.terminalBroadcastTr('Broadcast input')),
    content: SizedBox(
      width: 480,
      height: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.terminalBroadcastTr(
              'Typed keys and pasted text will be sent to every selected terminal.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.terminalBroadcastTr(
              _changedConnection
                  ? 'Connections changed. Choose the broadcast group again.'
                  : 'Select at least two connected terminals.',
            ),
            style: _changedConnection
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final target in widget.candidates)
                  CheckboxListTile(
                    key: ValueKey('terminal-broadcast-target-${target.id}'),
                    title: Text(
                      target.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: target.isCurrent
                        ? null
                        : Text(
                            context.terminalBroadcastTr('Connection changed'),
                          ),
                    value: _selected.contains(target.id),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: target.isCurrent
                        ? (value) => setState(() {
                            if (value == true) {
                              _selected.add(target.id);
                            } else {
                              _selected.remove(target.id);
                            }
                          })
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.terminalTr('Cancel')),
      ),
      FilledButton(
        key: const ValueKey('terminal-start-broadcast'),
        onPressed: _selected.length < 2 ? null : _confirm,
        child: Text(context.terminalBroadcastTr('Start broadcasting')),
      ),
    ],
  );

  @override
  void dispose() {
    for (final target in widget.candidates) {
      target.session.removeListener(_connectionsChanged);
    }
    super.dispose();
  }
}
