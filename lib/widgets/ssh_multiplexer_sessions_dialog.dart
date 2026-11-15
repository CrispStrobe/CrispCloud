import 'package:flutter/material.dart';

import '../l10n/ssh_multiplexer_strings.dart';
import '../l10n/terminal_strings.dart';
import '../models/ssh_multiplexer_session.dart';

/// Picks from an already authenticated, bounded server snapshot. Selecting an
/// entry returns attach-only options; this dialog never sends shell input.
class SshMultiplexerSessionsDialog extends StatefulWidget {
  const SshMultiplexerSessionsDialog({
    super.key,
    required this.kind,
    required this.sessions,
  });

  final SshMultiplexer kind;
  final List<SshMultiplexerSession> sessions;

  @override
  State<SshMultiplexerSessionsDialog> createState() =>
      _SshMultiplexerSessionsDialogState();
}

class _SshMultiplexerSessionsDialogState
    extends State<SshMultiplexerSessionsDialog> {
  late final List<SshMultiplexerSession> _sessions;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _sessions = List.unmodifiable(
      widget.sessions
          .where((session) => session.kind == widget.kind)
          .take(sshMultiplexerMaxSessions),
    );
  }

  String _description(SshMultiplexerSession session) {
    final state = session.state == SshMultiplexerSessionState.unavailable
        ? 'Unavailable'
        : !session.selectable
        ? 'Unsupported session name'
        : session.state == SshMultiplexerSessionState.attached
        ? 'Attached'
        : 'Detached';
    return [
      context.sshMultiplexerTr(state),
      if (session.windowCount != null)
        context
            .sshMultiplexerTr('{n} windows')
            .replaceAll('{n}', '${session.windowCount}'),
      if (session.attachedClients != null)
        context
            .sshMultiplexerTr('{n} attached clients')
            .replaceAll('{n}', '${session.attachedClients}'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final visible = _sessions.where((session) {
      return _filter.isEmpty ||
          session.target.toLowerCase().contains(_filter) ||
          session.name.toLowerCase().contains(_filter);
    }).toList(growable: false);
    final media = MediaQuery.of(context);
    final height = (
      media.size.height -
      media.viewInsets.bottom -
      media.padding.vertical -
      220
    ).clamp(100.0, 420.0).toDouble();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        context.sshMultiplexerTr(
          widget.kind == SshMultiplexer.tmux
              ? 'tmux sessions'
              : 'screen sessions',
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 480,
        height: height,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('ssh-multiplexer-filter'),
              maxLength: 128,
              decoration: InputDecoration(
                labelText: context.sshMultiplexerTr('Filter sessions'),
                prefixIcon: const Icon(Icons.search),
                counterText: '',
              ),
              onChanged: (value) => setState(() {
                _filter = value.toLowerCase();
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('ssh-multiplexer-list'),
                itemCount: visible.isEmpty ? 2 : visible.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        context.sshMultiplexerTr(
                          'Choose a session to attach. Other clients stay connected.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }
                  if (visible.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        context.sshMultiplexerTr(
                          _sessions.isEmpty
                              ? 'No sessions found.'
                              : 'No sessions match this filter.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final session = visible[index - 1];
                  return ListTile(
                    key: ValueKey('ssh-multiplexer-session-${session.target}'),
                    enabled: session.selectable,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.terminal),
                    title: Text(
                      session.label,
                      textDirection: TextDirection.ltr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_description(session)),
                    trailing: session.selectable
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: session.selectable
                        ? () => Navigator.of(context).pop(session)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('ssh-multiplexer-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.terminalTr('Cancel')),
        ),
      ],
    );
  }
}
