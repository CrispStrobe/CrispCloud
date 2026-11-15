import 'package:flutter/material.dart';

import '../l10n/terminal_shell_strings.dart';
import '../l10n/terminal_strings.dart';
import '../services/terminal_shell_integration.dart';

class TerminalCommandHistoryDialog extends StatefulWidget {
  const TerminalCommandHistoryDialog({super.key, required this.integration});

  final TerminalShellIntegration integration;

  @override
  State<TerminalCommandHistoryDialog> createState() =>
      _TerminalCommandHistoryDialogState();
}

class _TerminalCommandHistoryDialogState
    extends State<TerminalCommandHistoryDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.integration,
    builder: (context, _) {
      final marks = widget.integration.marks.reversed.where((mark) {
        final text = '${mark.command ?? ''}\n${mark.directory ?? ''}'
            .toLowerCase();
        return text.contains(_query.toLowerCase());
      }).toList();
      return AlertDialog(
        title: Text(context.terminalShellTr('Command history')),
        content: SizedBox(
          width: 560,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.terminalShellTr(
                  'Commands stay in this tab. Select an entry to scroll to it.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('terminal-command-filter'),
                maxLength: 256,
                decoration: InputDecoration(
                  labelText: context.terminalShellTr('Filter commands'),
                  prefixIcon: const Icon(Icons.search),
                  counterText: '',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: marks.isEmpty
                    ? SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            widget.integration.detected
                                ? context.terminalShellTr('No command marks')
                                : context.terminalShellTr(
                                    'Enable shell integration on the host to see prompts, commands and exit status. Manual marks work without setup.',
                                  ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: marks.length,
                        itemBuilder: (context, index) {
                          final mark = marks[index];
                          final status = mark.running
                              ? context.terminalShellTr('Running')
                              : mark.startedAt == null
                              ? ''
                              : mark.exitCode == null
                              ? context.terminalShellTr('Status unknown')
                              : '${context.terminalShellTr('Exit status')}: ${mark.exitCode}';
                          final elapsed = mark.elapsed;
                          return ListTile(
                            key: ValueKey('terminal-command-${mark.id}'),
                            enabled: widget.integration.contains(mark),
                            leading: Icon(
                              mark.manual
                                  ? Icons.bookmark_border
                                  : mark.running
                                  ? Icons.hourglass_top
                                  : mark.exitCode != null && mark.exitCode != 0
                                  ? Icons.error_outline
                                  : Icons.terminal,
                            ),
                            title: Text(
                              mark.command ??
                                  context.terminalShellTr(
                                    mark.manual
                                        ? 'Manual mark'
                                        : 'Shell prompt',
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (mark.directory != null) mark.directory!,
                                if (status.isNotEmpty) status,
                                if (elapsed != null)
                                  '${(elapsed.inMilliseconds / 1000).clamp(0, double.infinity).toStringAsFixed(1)} s',
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, mark),
                          );
                        },
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
        ],
      );
    },
  );
}
