// lib/widgets/terminal_panel.dart
//
// VS Code-style embedded terminal panel below the dual-pane file browser.
// Uses conditional import to avoid dart:io on web.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/terminal_strings.dart';
import '../l10n/terminal_mount_error_strings.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../providers/terminal_provider.dart';
import 'terminal_process_stub.dart'
    if (dart.library.io) 'terminal_process_native.dart'
    as proc;

typedef TerminalShellStarter = Future<proc.ShellProcess?> Function(
  String workingDirectory,
);

class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({super.key, this.shellStarter});

  /// Test/embedding hook; defaults to the platform backend.
  final TerminalShellStarter? shellStarter;

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
  String? _shellError;
  String? _sshSessionId;
  String? _sshLabel;
  bool _sshConnecting = false;
  bool _scopeHeld = false;
  TextSelection? _outputSelection;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_onInputFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocusNode.requestFocus();
      _startShell();
    });
  }

  void _onInputFocusChanged() {
    if (!mounted) return;
    ref.read(terminalInputFocusedProvider.notifier).state =
        _inputFocusNode.hasFocus;
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _output.toString()));
  }

  void _copySelection() {
    final selection = _outputSelection;
    final text = _output.toString();
    if (selection != null &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= text.length) {
      Clipboard.setData(
        ClipboardData(text: text.substring(selection.start, selection.end)),
      );
    } else {
      _copyAll();
    }
  }

  Future<void> _startShell() async {
    final strings = TerminalStrings(context);
    if (kIsWeb) {
      _shellError = strings.text('web');
      _appendOutput('[${strings.text('web')}]\n');
      return;
    }

    _shellError = null;
    try {
      final panel = ref.read(panelProvider(PanelSide.local));
      final local = ref.read(localFileServiceProvider);
      // Hold the app's security-scoped grant for the whole shell session.
      // Child processes inherit the active sandbox extension; without this the
      // shell can only see the app container even when the panel has access.
      _scopeHeld = await local.beginStreamAccess(panel.currentPath);
      final cwd = _scopeHeld
          ? panel.currentPath
          : await local.getSafeFallbackDirectory();
      _shell =
          await (widget.shellStarter ?? proc.startShell)(cwd) ??
          await proc.startBuiltInShell(cwd);
      if (_shell == null) {
        _shellError = strings.text('platform');
        _appendOutput('[${strings.text('platform')}]\n');
        return;
      }

      _isRunning = true;
      _appendOutput('${strings.text('started')}\n\$ ');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocusNode.requestFocus();
      });

      _shell!.outputStream.listen(
        (data) => _appendOutput(data),
        onDone: () {
          if (mounted) {
            _appendOutput('\n[${strings.text('exited')}]\n');
            setState(() => _isRunning = false);
          }
        },
      );
    } catch (e) {
      try {
        final panel = ref.read(panelProvider(PanelSide.local));
        _shell = await proc.startBuiltInShell(panel.currentPath);
      } catch (_) {
        _shell = null;
      }
      if (_shell != null) {
        _isRunning = true;
        _appendOutput(
          '[${strings.text('builtIn')}]\n${strings.text('started')}\n\$ ',
        );
        _shell!.outputStream.listen(
          (data) => _appendOutput(data),
          onDone: () {
            if (mounted) setState(() => _isRunning = false);
          },
        );
        return;
      }
      _shellError = _friendlyShellError(e, strings);
      _appendOutput('[${strings.value('shellError', e)}]\n');
    }
  }

  String _friendlyShellError(Object error, TerminalStrings strings) {
    final text = error.toString();
    if (text.contains('Operation not permitted') ||
        text.toLowerCase().contains('sandbox')) {
      return strings.text('sandbox');
    }
    return strings.value('shellError', text);
  }

  Future<void> _connectSsh() async {
    final config = await showDialog<_SshConfig>(
      context: context,
      builder: (_) => const _SshConnectDialog(),
    );
    if (config == null || !mounted) return;

    setState(() {
      _sshConnecting = true;
      _shellError = null;
    });
    final service = ref.read(sshTerminalServiceProvider);
    service.confirmHostKey = (endpoint, fingerprint) async {
      if (!mounted) return false;
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(TerminalStrings(dialogContext).text('trustTitle')),
              content: Text(
                TerminalStrings(dialogContext).trust(endpoint, fingerprint),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(TerminalStrings(context).text('cancel')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(TerminalStrings(dialogContext).text('trust')),
                ),
              ],
            ),
          ) ??
          false;
    };

    try {
      final session = await service.connect(
        config.host,
        config.port,
        config.username,
        config.password,
      );
      final stream = await service.startShell(session.id);
      if (!mounted) {
        await service.disconnect(session.id);
        return;
      }
      _sshSessionId = session.id;
      _sshLabel = '${config.username}@${config.host}';
      _isRunning = true;
      _appendOutput(
        '${TerminalStrings(context).value('connected', _sshLabel!)}\n',
      );
      stream.listen(
        (data) => _appendOutput(_stripAnsi(data)),
        onDone: () {
          if (!mounted) return;
          setState(() => _isRunning = false);
          _appendOutput('\n[${TerminalStrings(context).text('closed')}]\n');
        },
        onError: (Object error) {
          if (!mounted) return;
          _appendOutput(
            '\n[${TerminalStrings(context).value('sshError', localizedTerminalMountError(context, error))}]\n',
          );
          setState(() => _isRunning = false);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _shellError = TerminalStrings(context)
              .value('connectError', localizedTerminalMountError(context, e));
          _isRunning = false;
        });
      }
    } finally {
      if (mounted) setState(() => _sshConnecting = false);
    }
  }

  static String _stripAnsi(String input) =>
      input.replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), '');

  void _appendOutput(String text) {
    if (!mounted) return;
    setState(() => _output.write(_stripAnsi(text).replaceAll('\r', '')));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputController.hasClients) {
        _outputController.jumpTo(_outputController.position.maxScrollExtent);
      }
    });
  }

  void _sendCommand(String command) {
    if (!_isRunning) {
      _appendOutput(
        _shellError != null
            ? '\n[${TerminalStrings(context).text('unavailable')}: $_shellError]\n'
            : '\n[${TerminalStrings(context).text('notRunning')}]\n',
      );
      return;
    }
    final sshId = _sshSessionId;
    if (sshId != null) {
      ref.read(sshTerminalServiceProvider).writeToShell(sshId, '$command\n');
      _inputController.clear();
      return;
    }
    final shell = _shell;
    if (shell == null) return;
    shell.writeln(command);
    _inputController.clear();
  }

  @override
  void deactivate() {
    ref.read(terminalInputFocusedProvider.notifier).state = false;
    if (_scopeHeld) {
      _scopeHeld = false;
      unawaited(ref.read(localFileServiceProvider).endStreamAccess());
    }
    final sshId = _sshSessionId;
    _sshSessionId = null;
    if (sshId != null) {
      try {
        ref.read(sshTerminalServiceProvider).disconnect(sshId);
      } catch (_) {
        // Provider may already be disposed.
      }
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_onInputFocusChanged);
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onVerticalDragUpdate: (details) {
            ref.read(terminalHeightProvider.notifier).state =
                (height - details.delta.dy).clamp(100.0, 600.0);
          },
          child: Container(
            height: 6,
            color: theme.dividerColor,
            child: Center(
              child: Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 16),
              const SizedBox(width: 8),
              Text(
                _sshLabel ?? TerminalStrings(context).text('terminal'),
                style: theme.textTheme.labelMedium,
              ),
              const Spacer(),
              IconButton(
                icon: _sshConnecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.dns_outlined, size: 16),
                tooltip: TerminalStrings(context).text('connectSsh'),
                onPressed: _sshConnecting ? null : _connectSsh,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.copy_all, size: 16),
                tooltip: TerminalStrings(context).text('copyAll'),
                onPressed: _copyAll,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt, size: 16),
                tooltip: TerminalStrings(context).text('restart'),
                onPressed: () {
                  _shell?.kill();
                  final sshId = _sshSessionId;
                  _sshSessionId = null;
                  _sshLabel = null;
                  if (sshId != null) {
                    ref.read(sshTerminalServiceProvider).disconnect(sshId);
                  }
                  _output.clear();
                  _shellError = null;
                  _isRunning = false;
                  if (_scopeHeld) {
                    _scopeHeld = false;
                    unawaited(
                      ref.read(localFileServiceProvider).endStreamAccess(),
                    );
                  }
                  _startShell();
                },
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: TerminalStrings(context).text('close'),
                onPressed: () =>
                    ref.read(showTerminalProvider.notifier).state = false,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        SizedBox(
          height: height - 46,
          child: Container(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : const Color(0xFFF5F5F5),
            child: Column(
              children: [
                if (_shellError != null)
                  Container(
                    width: double.infinity,
                    color: theme.colorScheme.errorContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _shellError!,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _outputController,
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        _output.toString(),
                        textAlign: TextAlign.left,
                        onSelectionChanged: (selection, cause) {
                          _outputSelection = selection;
                        },
                        contextMenuBuilder: (context, editableTextState) {
                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: editableTextState.contextMenuAnchors,
                            buttonItems: [
                              ...editableTextState.contextMenuButtonItems,
                              ContextMenuButtonItem(
                                label: TerminalStrings(context).text('copyAll'),
                                onPressed: () {
                                  _copyAll();
                                  editableTextState.hideToolbar();
                                },
                              ),
                            ],
                          );
                        },
                        style: TextStyle(
                          fontFamily: 'AppMono',
                          fontFamilyFallback: const [
                            'Menlo',
                            'Consolas',
                            'monospace',
                          ],
                          fontSize: 12,
                          height: 1.4,
                          color: theme.brightness == Brightness.dark
                              ? const Color(0xFFD4D4D4)
                              : const Color(0xFF1E1E1E),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
                          enabled: true,
                          autofocus: true,
                          style: const TextStyle(
                            fontFamily: 'AppMono',
                            fontFamilyFallback: [
                              'Menlo',
                              'Consolas',
                              'monospace',
                            ],
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: _isRunning
                                ? null
                                : TerminalStrings(context).text('starting'),
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

class _SshConfig {
  final String host;
  final int port;
  final String username;
  final String password;

  const _SshConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });
}

class _SshConnectDialog extends StatefulWidget {
  const _SshConnectDialog();

  @override
  State<_SshConnectDialog> createState() => _SshConnectDialogState();
}

class _SshConnectDialogState extends State<_SshConnectDialog> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final username = _username.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    if (host.isEmpty || username.isEmpty) return;
    Navigator.pop(
      context,
      _SshConfig(
        host: host,
        port: port,
        username: username,
        password: _password.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(TerminalStrings(context).text('connectSsh')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _host,
              autofocus: true,
              decoration: InputDecoration(
                labelText: TerminalStrings(context).text('host'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _username,
                    decoration: InputDecoration(
                      labelText: TerminalStrings(context).text('username'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: TerminalStrings(context).text('port'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: TerminalStrings(context).text('password'),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(TerminalStrings(context).text('cancel')),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(TerminalStrings(context).text('connect')),
        ),
      ],
    );
  }
}
