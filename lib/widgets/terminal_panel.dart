// lib/widgets/terminal_panel.dart
//
// VS Code-style embedded terminal panel below the dual-pane file browser.
// Uses conditional import to avoid dart:io on web.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/terminal_provider.dart';
import 'terminal_process_stub.dart'
    if (dart.library.io) 'terminal_process_native.dart' as proc;

class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({super.key});

  @override
  ConsumerState<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends ConsumerState<TerminalPanel> {
  final _outputController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _output = StringBuffer();
  proc.ShellProcess? _shell;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _startShell();
  }

  Future<void> _startShell() async {
    if (kIsWeb) {
      _appendOutput('[Terminal not available on Web]\n');
      return;
    }

    try {
      final panel = ref.read(panelProvider(PanelSide.local));
      _shell = await proc.startShell(panel.currentPath);
      if (_shell == null) {
        _appendOutput('[Terminal not available on this platform]\n');
        return;
      }

      _isRunning = true;
      _appendOutput('Shell started\n\$ ');

      _shell!.outputStream.listen(
        (data) => _appendOutput(data),
        onDone: () {
          if (mounted) {
            _appendOutput('\n[Shell exited]\n');
            setState(() => _isRunning = false);
          }
        },
      );
    } catch (e) {
      _appendOutput('[Failed to start shell: $e]\n');
    }
  }

  void _appendOutput(String text) {
    if (!mounted) return;
    setState(() => _output.write(text));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputController.hasClients) {
        _outputController.jumpTo(_outputController.position.maxScrollExtent);
      }
    });
  }

  void _sendCommand(String command) {
    if (_shell == null || !_isRunning) return;
    _shell!.writeln(command);
    _inputController.clear();
  }

  @override
  void dispose() {
    _shell?.kill();
    _outputController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = ref.watch(terminalHeightProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragUpdate: (details) {
            ref.read(terminalHeightProvider.notifier).state =
                (height - details.delta.dy).clamp(100.0, 600.0);
          },
          child: Container(
            height: 6,
            color: theme.dividerColor,
            child: Center(child: Container(
              width: 40, height: 3,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(children: [
            const Icon(Icons.terminal, size: 16),
            const SizedBox(width: 8),
            Text('Terminal', style: theme.textTheme.labelMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 16), tooltip: 'Restart',
              onPressed: () { _shell?.kill(); _output.clear(); _startShell(); },
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16), tooltip: 'Close',
              onPressed: () => ref.read(showTerminalProvider.notifier).state = false,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ]),
        ),
        SizedBox(
          height: height - 46,
          child: Container(
            color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
            child: Column(children: [
              Expanded(child: SelectableText(
                _output.toString(),
                scrollPhysics: const ClampingScrollPhysics(),
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4,
                  color: theme.brightness == Brightness.dark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E)),
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(children: [
                  Text('\$ ', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: theme.colorScheme.primary)),
                  Expanded(child: TextField(
                    controller: _inputController, focusNode: _inputFocusNode,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                    onSubmitted: (cmd) { _sendCommand(cmd); _inputFocusNode.requestFocus(); },
                  )),
                ]),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
