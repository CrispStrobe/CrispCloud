import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/terminal_shell_strings.dart';
import '../l10n/terminal_strings.dart';
import '../services/terminal_shell_setup.dart';

class TerminalShellSetupDialog extends StatefulWidget {
  const TerminalShellSetupDialog({super.key});

  @override
  State<TerminalShellSetupDialog> createState() =>
      _TerminalShellSetupDialogState();
}

class _TerminalShellSetupDialogState extends State<TerminalShellSetupDialog> {
  var _shell = TerminalShellSetup.bash;
  bool _copied = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.terminalShellTr('Shell integration setup')),
    content: SizedBox(
      width: 620,
      height: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.terminalShellTr(
            'Copy the script, then paste and run it in the chosen shell. It enables integration for that session and preserves existing prompt hooks.',
          )),
          const SizedBox(height: 12),
          DropdownButtonFormField<TerminalShellSetup>(
            key: const ValueKey('terminal-setup-shell'),
            initialValue: _shell,
            items: const [
              DropdownMenuItem(
                value: TerminalShellSetup.bash,
                child: Text('Bash 4.4+'),
              ),
              DropdownMenuItem(
                value: TerminalShellSetup.zsh,
                child: Text('Zsh'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _shell = value;
                  _copied = false;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SingleChildScrollView(
                child: SelectableText(
                  terminalShellSetupScript(_shell),
                  style: const TextStyle(fontFamily: 'AppMono', fontSize: 12),
                ),
              ),
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
      FilledButton.icon(
        key: const ValueKey('terminal-copy-shell-setup'),
        onPressed: () async {
          await Clipboard.setData(
            ClipboardData(text: terminalShellSetupScript(_shell)),
          );
          if (mounted) setState(() => _copied = true);
        },
        icon: Icon(_copied ? Icons.check : Icons.copy),
        label: Text(
          context.terminalShellTr(_copied ? 'Copied' : 'Copy setup script'),
        ),
      ),
    ],
  );
}
