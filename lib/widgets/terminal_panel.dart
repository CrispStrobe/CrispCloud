// lib/widgets/terminal_panel.dart
//
// VS Code-style embedded terminal panel below the dual-pane file browser.
// Supports local shell (desktop) and SSH terminal (SFTP connections).

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/terminal_provider.dart';

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
  Process? _process;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
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
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      _appendOutput('[Terminal not available on this platform]\n');
      return;
    }

    try {
      final shell = Platform.isWindows ? 'cmd.exe' : Platform.environment['SHELL'] ?? '/bin/bash';
      final panel = ref.read(panelProvider(PanelSide.local));
      final workDir = panel.currentPath;

      _process = await Process.start(
        shell,
        Platform.isWindows ? [] : ['--login'],
        workingDirectory: workDir,
        environment: Platform.environment,
      );

      _isRunning = true;
      _appendOutput('Shell started: $shell\n\$ ');

      _stdoutSub = _process!.stdout.listen((data) {
        _appendOutput(String.fromCharCodes(data));
      });

      _stderrSub = _process!.stderr.listen((data) {
        _appendOutput(String.fromCharCodes(data));
      });

      _process!.exitCode.then((code) {
        if (mounted) {
          _appendOutput('\n[Process exited with code $code]\n');
          setState(() => _isRunning = false);
        }
      });
    } catch (e) {
      _appendOutput('[Failed to start shell: $e]\n');
    }
  }

  void _appendOutput(String text) {
    if (!mounted) return;
    setState(() {
      _output.write(text);
    });
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputController.hasClients) {
        _outputController.jumpTo(_outputController.position.maxScrollExtent);
      }
    });
  }

  void _sendCommand(String command) {
    if (_process == null || !_isRunning) return;
    _process!.stdin.writeln(command);
    _inputController.clear();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill();
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
        // Drag handle
        GestureDetector(
          onVerticalDragUpdate: (details) {
            final newHeight = height - details.delta.dy;
            ref.read(terminalHeightProvider.notifier).state =
                newHeight.clamp(100.0, 600.0);
          },
          child: Container(
            height: 6,
            color: theme.dividerColor,
            child: Center(
              child: Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        // Terminal header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 16),
              const SizedBox(width: 8),
              Text('Terminal', style: theme.textTheme.labelMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.restart_alt, size: 16),
                tooltip: 'Restart',
                onPressed: () {
                  _process?.kill();
                  _output.clear();
                  _startShell();
                },
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Close',
                onPressed: () {
                  ref.read(showTerminalProvider.notifier).state = false;
                },
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        // Terminal output
        SizedBox(
          height: height - 46, // subtract header + handle height
          child: Container(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFF5F5F5),
            child: Column(
              children: [
                Expanded(
                  child: SelectableText(
                    _output.toString(),
                    scrollPhysics: const ClampingScrollPhysics(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                      color: theme.brightness == Brightness.dark
                          ? const Color(0xFFD4D4D4)
                          : const Color(0xFF1E1E1E),
                    ),
                  ),
                ),
                // Input line
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '\$ ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (cmd) {
                            _sendCommand(cmd);
                            _inputFocusNode.requestFocus();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
