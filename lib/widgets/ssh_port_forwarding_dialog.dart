import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../l10n/ssh_port_forwarding_strings.dart';
import '../services/ssh_forwarding_profiles.dart';
import '../services/ssh_port_forwarding.dart';

/// Edits listeners owned by this exact SSH connection and, when supplied, the
/// saved recipes for its exact route. Closing this dialog leaves listeners and
/// the connection-owned profile coordinator active.
class SshPortForwardingDialog extends StatefulWidget {
  const SshPortForwardingDialog({
    super.key,
    required this.forwarding,
    this.profiles,
  });

  final SshPortForwarding forwarding;
  final SshForwardingProfileSession? profiles;

  @override
  State<SshPortForwardingDialog> createState() =>
      _SshPortForwardingDialogState();
}

class _SshPortForwardingDialogState extends State<SshPortForwardingDialog> {
  final Set<String> _stopping = {};
  final Set<String> _updatingProfiles = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    assert(
      widget.profiles == null ||
          identical(widget.profiles!.forwarding, widget.forwarding),
    );
    unawaited(widget.profiles?.refresh());
  }

  Future<void> _add() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddSshPortForwardDialog(
        forwarding: widget.forwarding,
        profiles: widget.profiles,
      ),
    );
  }

  Future<void> _editProfile({
    SshForwardingProfile? profile,
    SshPortForwardSpec? spec,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddSshPortForwardDialog(
        forwarding: widget.forwarding,
        profiles: widget.profiles,
        profile: profile,
        initialSpec: spec,
        saveOnly: true,
      ),
    );
  }

  Future<void> _profileAction(
    SshForwardingProfile profile, {
    bool delete = false,
  }) async {
    if (!_updatingProfiles.add(profile.id)) return;
    setState(() => _error = null);
    try {
      if (delete) {
        await widget.profiles!.delete(profile);
      } else {
        await widget.profiles!.start(profile.id);
      }
    } catch (error) {
      if (mounted)
        setState(() => _error = sshForwardingProfileErrorMessage(error));
    } finally {
      _updatingProfiles.remove(profile.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _stop(String id) async {
    if (!_stopping.add(id)) return;
    setState(() => _error = null);
    try {
      final profiles = widget.profiles;
      if (profiles == null) {
        await widget.forwarding.stop(id);
      } else {
        await profiles.stop(id);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SshPortForwardException
              ? error.message
              : 'Could not stop forwarding.',
        );
      }
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
      animation: Listenable.merge([
        widget.forwarding,
        if (widget.profiles != null) widget.profiles!,
      ]),
      builder: (context, _) {
        final forwards = widget.forwarding.forwards;
        final profiles = widget.profiles;
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
                          profiles == null
                              ? 'Listeners stop on disconnect and are not restored automatically.'
                              : 'Listeners stop on disconnect.',
                        ),
                      ),
                      if (profiles != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            context.sshForwardTr(
                              'Saved profiles with Auto-start restart after a verified connection.',
                            ),
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
                                OverflowBar(
                                  alignment: MainAxisAlignment.end,
                                  spacing: 8,
                                  children: [
                                    if (profiles != null)
                                      TextButton.icon(
                                        key: ValueKey(
                                          'ssh-forward-save-${forward.id}',
                                        ),
                                        onPressed:
                                            profiles.error != null ||
                                                profiles.profiles.any(
                                                  (profile) =>
                                                      sshForwardingSpecsEqual(
                                                        profile.spec,
                                                        forward.spec,
                                                      ),
                                                )
                                            ? null
                                            : () => _editProfile(
                                                spec: forward.spec,
                                              ),
                                        icon: const Icon(
                                          Icons.bookmark_add_outlined,
                                        ),
                                        label: Text(
                                          context.sshForwardTr(
                                            'Save as profile',
                                          ),
                                        ),
                                      ),
                                    TextButton.icon(
                                      onPressed: _stopping.contains(forward.id)
                                          ? null
                                          : () => _stop(forward.id),
                                      icon: const Icon(
                                        Icons.stop_circle_outlined,
                                      ),
                                      label: Text(context.sshForwardTr('Stop')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (profiles != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          context.sshForwardTr('Saved for this SSH route'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.sshForwardTr(
                            'Profiles match the exact server, user, gateway and jump route. Credentials are not saved.',
                          ),
                        ),
                        if (profiles.error != null) ...[
                          Text(
                            context.sshForwardTr(profiles.error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: profiles.refresh,
                              child: Text(context.sshForwardTr('Retry')),
                            ),
                          ),
                        ] else if (profiles.profiles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              context.sshForwardTr(
                                'No saved forwarding profiles',
                              ),
                            ),
                          ),
                        for (final profile in profiles.profiles)
                          _profileCard(profile, profiles, available),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: const ValueKey('ssh-forward-new-profile'),
                            onPressed:
                                profiles.error != null ||
                                    profiles.profiles.length >=
                                        SshForwardingProfiles
                                            .maximumProfilesPerRoute
                                ? null
                                : () => _editProfile(),
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(
                              context.sshForwardTr('New saved profile'),
                            ),
                          ),
                        ),
                      ],
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

  Widget _profileCard(
    SshForwardingProfile profile,
    SshForwardingProfileSession profiles,
    bool available,
  ) {
    final listener = profiles.listenerFor(profile);
    final busy =
        _updatingProfiles.contains(profile.id) ||
        profiles.isStarting(profile.id);
    final running =
        listener != null && listener.status != SshPortForwardStatus.failed;
    final error = profiles.profileError(profile.id);
    return Card(
      key: ValueKey('ssh-forward-profile-${profile.id}'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              '${_kind(profile.spec.kind)} · ${profile.spec.bindHost}:${profile.spec.bindPort}',
            ),
            if (profile.spec.kind != SshPortForwardKind.dynamic)
              Text(
                '${context.sshForwardTr('Destination')}: ${profile.spec.targetHost}:${profile.spec.targetPort}',
              ),
            if (profile.autoStart)
              Text(
                context.sshForwardTr('Auto-start after a verified connection'),
              ),
            if (listener != null)
              Text(
                '${_status(listener.status)} · ${listener.spec.bindHost}:${listener.port}',
              ),
            if (error != null)
              Text(
                context.sshForwardTr(error),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey('ssh-forward-profile-start-${profile.id}'),
                  onPressed:
                      !available || busy || running || profiles.error != null
                      ? null
                      : () => _profileAction(profile),
                  child: Text(
                    context.sshForwardTr(busy ? 'Starting' : 'Start'),
                  ),
                ),
                TextButton(
                  key: ValueKey('ssh-forward-profile-edit-${profile.id}'),
                  onPressed: busy || profiles.error != null
                      ? null
                      : () => _editProfile(profile: profile),
                  child: Text(context.sshForwardTr('Edit')),
                ),
                TextButton(
                  key: ValueKey('ssh-forward-profile-delete-${profile.id}'),
                  onPressed: busy || profiles.error != null
                      ? null
                      : () => _profileAction(profile, delete: true),
                  child: Text(context.sshForwardTr('Delete and stop')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddSshPortForwardDialog extends StatefulWidget {
  const AddSshPortForwardDialog({
    super.key,
    required this.forwarding,
    this.profiles,
    this.profile,
    this.initialSpec,
    this.saveOnly = false,
  });
  final SshPortForwarding forwarding;
  final SshForwardingProfileSession? profiles;
  final SshForwardingProfile? profile;
  final SshPortForwardSpec? initialSpec;
  final bool saveOnly;

  @override
  State<AddSshPortForwardDialog> createState() =>
      _AddSshPortForwardDialogState();
}

class _AddSshPortForwardDialogState extends State<AddSshPortForwardDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _bindPort = TextEditingController(text: '0');
  final _targetHost = TextEditingController(text: '127.0.0.1');
  final _targetPort = TextEditingController();
  SshPortForwardKind _kind = SshPortForwardKind.local;
  String _bindHost = '127.0.0.1';
  bool _busy = false;
  bool _autoStart = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    assert(!widget.saveOnly || widget.profiles != null);
    final profile = widget.profile;
    final spec = profile?.spec ?? widget.initialSpec;
    if (spec != null) {
      _kind = spec.kind;
      _bindHost = spec.bindHost;
      _bindPort.text = '${spec.bindPort}';
      _targetHost.text = spec.targetHost ?? '127.0.0.1';
      _targetPort.text = spec.targetPort?.toString() ?? '';
    }
    if (profile != null) {
      _name.text = profile.name;
      _autoStart = profile.autoStart;
    }
  }

  @override
  void dispose() {
    _name.dispose();
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
        (!widget.saveOnly && widget.forwarding.isClosed)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final spec = SshPortForwardSpec(
        kind: _kind,
        bindHost: _bindHost,
        bindPort: int.parse(_bindPort.text.trim()),
        targetHost: _kind == SshPortForwardKind.dynamic
            ? null
            : _targetHost.text.trim(),
        targetPort: _kind == SshPortForwardKind.dynamic
            ? null
            : int.parse(_targetPort.text.trim()),
      );
      if (widget.saveOnly) {
        await widget.profiles!.save(
          SshForwardingProfile(
            id: widget.profile?.id ?? const Uuid().v4(),
            name: _name.text.trim(),
            route: widget.profiles!.route,
            spec: spec,
            autoStart: _autoStart,
          ),
          replacing: widget.profile,
        );
      } else {
        final duplicate = widget.forwarding.forwards.any(
          (listener) =>
              sshForwardingSpecsEqual(listener.spec, spec) &&
              listener.status != SshPortForwardStatus.failed,
        );
        if (duplicate) {
          throw const SshForwardingProfileException(
            'This forwarding configuration is already running.',
          );
        }
        await widget.forwarding.start(spec);
      }
      if (mounted) {
        setState(() => _busy = false);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is SshForwardingProfileException || widget.saveOnly
              ? sshForwardingProfileErrorMessage(error)
              : error is SshPortForwardException
              ? error.message
              : 'Could not start forwarding. Check the listener and destination.',
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
        title: Text(
          context.sshForwardTr(
            widget.saveOnly
                ? widget.profile == null
                      ? 'Save forwarding profile'
                      : 'Edit forwarding profile'
                : 'Add forwarding',
          ),
        ),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.saveOnly) ...[
                  TextFormField(
                    key: const ValueKey('ssh-forward-profile-name'),
                    controller: _name,
                    enabled: !_busy,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: context.sshForwardTr('Profile name'),
                    ),
                    validator: (value) =>
                        SshForwardingProfile.isValidName(value?.trim() ?? '')
                        ? null
                        : context.sshForwardTr(
                            'Enter a profile name of 1 to 80 characters.',
                          ),
                  ),
                  SwitchListTile(
                    key: const ValueKey('ssh-forward-profile-auto'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.sshForwardTr('Auto-start')),
                    subtitle: Text(
                      context.sshForwardTr(
                        'Start on the next verified connection to this exact route, including reconnects.',
                      ),
                    ),
                    value: _autoStart,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _autoStart = value),
                  ),
                  Text(
                    context.sshForwardTr(
                      'Saving does not start a listener. Use Start when you are ready.',
                    ),
                  ),
                  if (widget.profile != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        context.sshForwardTr(
                          'Changing the forwarding settings stops this profile’s active listeners.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
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
            onPressed: _busy || (!widget.saveOnly && widget.forwarding.isClosed)
                ? null
                : _start,
            child: Text(
              context.sshForwardTr(
                widget.saveOnly
                    ? _busy
                          ? 'Saving'
                          : 'Save'
                    : _busy
                    ? 'Starting'
                    : 'Start',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
