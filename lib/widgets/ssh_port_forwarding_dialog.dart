import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/ssh_port_forwarding_strings.dart';
import '../services/ssh_port_forwarding.dart';

/// Edits only the listeners owned by this exact SSH connection. Closing the
/// dialog leaves them active; reconnecting never recreates them implicitly.
class SshPortForwardingDialog extends StatefulWidget {
  const SshPortForwardingDialog({super.key, required this.forwarding});

  final SshPortForwarding forwarding;

  @override
  State<SshPortForwardingDialog> createState() =>
      _SshPortForwardingDialogState();
}

class _SshPortForwardingDialogState extends State<SshPortForwardingDialog> {
  final Set<String> _stopping = {};
  String? _error;

  Future<void> _add() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddSshPortForwardDialog(forwarding: widget.forwarding),
    );
  }

  Future<void> _stop(String id) async {
    if (!_stopping.add(id)) return;
    setState(() => _error = null);
    try {
      await widget.forwarding.stop(id);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not stop forwarding.');
    } finally {
      _stopping.remove(id);
      if (mounted) setState(() {});
    }
  }

  String _kind(SshPortForwardKind kind) => context.sshForwardTr(switch (kind) {
    SshPortForwardKind.local => 'Local',
    SshPortForwardKind.remote => 'Remote',
    SshPortForwardKind.dynamic => 'SOCKS5',
  });

  String _status(SshPortForwardStatus status) =>
      context.sshForwardTr(switch (status) {
        SshPortForwardStatus.starting => 'Starting',
        SshPortForwardStatus.active => 'Listening',
        SshPortForwardStatus.stopping => 'Stopping',
        SshPortForwardStatus.failed => 'Failed',
      });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.forwarding,
      builder: (context, _) {
        final forwards = widget.forwarding.forwards;
        final available =
            SshPortForwarding.supported && !widget.forwarding.isClosed;
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 600,
            height: math.min(520, MediaQuery.sizeOf(context).height - 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    context.sshForwardTr('Port forwarding'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      Text(
                        context.sshForwardTr(
                          'Listeners stop on disconnect and are not restored automatically.',
                        ),
                      ),
                      if (!available)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            context.sshForwardTr(
                              SshPortForwarding.supported
                                  ? 'This SSH connection has ended.'
                                  : 'Port forwarding requires the native app.',
                            ),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            context.sshForwardTr(_error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (forwards.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Text(
                              context.sshForwardTr('No active forwarding'),
                            ),
                          ),
                        ),
                      for (final forward in forwards)
                        Card(
                          key: ValueKey('ssh-forward-${forward.id}'),
                          margin: const EdgeInsets.only(top: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_kind(forward.spec.kind)} · ${_status(forward.status)}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  '${forward.spec.bindHost}:${forward.port}',
                                ),
                                if (forward.spec.kind !=
                                    SshPortForwardKind.dynamic)
                                  Text(
                                    '${context.sshForwardTr('Destination')}: '
                                    '${forward.spec.targetHost}:${forward.spec.targetPort}',
                                  ),
                                Text(
                                  context
                                      .sshForwardTr('Connections: {count}')
                                      .replaceAll(
                                        '{count}',
                                        '${forward.activeConnections}',
                                      ),
                                ),
                                if (forward.error != null)
                                  Text(
                                    context.sshForwardTr(forward.error!),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton.icon(
                                    onPressed: _stopping.contains(forward.id)
                                        ? null
                                        : () => _stop(forward.id),
                                    icon: const Icon(
                                      Icons.stop_circle_outlined,
                                    ),
                                    label: Text(context.sshForwardTr('Stop')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: OverflowBar(
                    spacing: 8,
                    overflowSpacing: 4,
                    alignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('ssh-forward-add'),
                        onPressed:
                            available &&
                                forwards.length <
                                    SshPortForwarding.maximumForwards
                            ? _add
                            : null,
                        icon: const Icon(Icons.add),
                        label: Text(context.sshForwardTr('Add forwarding')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.sshForwardTr('Done')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AddSshPortForwardDialog extends StatefulWidget {
  const AddSshPortForwardDialog({super.key, required this.forwarding});
  final SshPortForwarding forwarding;

  @override
  State<AddSshPortForwardDialog> createState() =>
      _AddSshPortForwardDialogState();
}

class _AddSshPortForwardDialogState extends State<AddSshPortForwardDialog> {
  final _form = GlobalKey<FormState>();
  final _bindPort = TextEditingController(text: '0');
  final _targetHost = TextEditingController(text: '127.0.0.1');
  final _targetPort = TextEditingController();
  SshPortForwardKind _kind = SshPortForwardKind.local;
  String _bindHost = '127.0.0.1';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _bindPort.dispose();
    _targetHost.dispose();
    _targetPort.dispose();
    super.dispose();
  }

  String? _port(String? value, {bool zero = false}) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port < (zero ? 0 : 1) || port > 65535) {
      return context.sshForwardTr(
        zero ? 'Use a port from 0 to 65535.' : 'Use a port from 1 to 65535.',
      );
    }
    return null;
  }

  Future<void> _start() async {
    if (_busy ||
        !_form.currentState!.validate() ||
        widget.forwarding.isClosed) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.forwarding.start(
        SshPortForwardSpec(
          kind: _kind,
          bindHost: _bindHost,
          bindPort: int.parse(_bindPort.text.trim()),
          targetHost: _kind == SshPortForwardKind.dynamic
              ? null
              : _targetHost.text.trim(),
          targetPort: _kind == SshPortForwardKind.dynamic
              ? null
              : int.parse(_targetPort.text.trim()),
        ),
      );
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not start forwarding. Check the listener and destination.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AnimatedBuilder(
      animation: widget.forwarding,
      builder: (context, _) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.all(16),
        title: Text(context.sshForwardTr('Add forwarding')),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SshPortForwardKind>(
                  key: const ValueKey('ssh-forward-kind'),
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.sshForwardTr('Type'),
                  ),
                  items: [
                    for (final kind in SshPortForwardKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(
                          context.sshForwardTr(switch (kind) {
                            SshPortForwardKind.local => 'Local',
                            SshPortForwardKind.remote => 'Remote',
                            SshPortForwardKind.dynamic => 'SOCKS5',
                          }),
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _kind = value!),
                ),
                const SizedBox(height: 8),
                Text(
                  context.sshForwardTr(switch (_kind) {
                    SshPortForwardKind.local => 'Listen on this device. Reach the destination from the SSH server.',
                    SshPortForwardKind.remote => 'Listen on the SSH server. Reach the destination from this device.',
                    SshPortForwardKind.dynamic => 'Listen on this device as a SOCKS5 proxy through the SSH server.',
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _bindHost,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.sshForwardTr('Loopback address'),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '127.0.0.1',
                      child: Text('127.0.0.1 (IPv4)'),
                    ),
                    DropdownMenuItem(value: '::1', child: Text('::1 (IPv6)')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _bindHost = value!),
                ),
                TextFormField(
                  key: const ValueKey('ssh-forward-bind-port'),
                  controller: _bindPort,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: InputDecoration(
                    labelText: context.sshForwardTr(
                      'Listening port (0 = automatic)',
                    ),
                  ),
                  validator: (value) => _port(value, zero: true),
                ),
                if (_kind != SshPortForwardKind.dynamic) ...[
                  TextFormField(
                    key: const ValueKey('ssh-forward-target-host'),
                    controller: _targetHost,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 253,
                    decoration: InputDecoration(
                      labelText: context.sshForwardTr('Destination host'),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? context.sshForwardTr('Enter a destination host.')
                        : null,
                  ),
                  TextFormField(
                    key: const ValueKey('ssh-forward-target-port'),
                    controller: _targetPort,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    decoration: InputDecoration(
                      labelText: context.sshForwardTr('Destination port'),
                    ),
                    validator: _port,
                  ),
                ],
                if (widget.forwarding.isClosed)
                  Text(context.sshForwardTr('This SSH connection has ended.')),
                if (_error != null)
                  Text(
                    context.sshForwardTr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(context.sshForwardTr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('ssh-forward-start'),
            onPressed: _busy || widget.forwarding.isClosed ? null : _start,
            child: Text(context.sshForwardTr(_busy ? 'Starting' : 'Start')),
          ),
        ],
      ),
    ),
  );
}
