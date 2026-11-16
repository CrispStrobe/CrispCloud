import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/screen_terminal_strings.dart';
import '../l10n/ssh_jump_strings.dart';
import '../l10n/ssh_agent_strings.dart';
import '../l10n/terminal_strings.dart';
import '../models/screen_session_options.dart';
import '../models/ssh_terminal_config.dart';
import '../models/tmux_session_options.dart';
import '../services/ssh_gateway.dart';
import '../services/ssh_agent.dart';

export '../models/ssh_terminal_config.dart';

enum _SessionMode { shell, createOrAttach, attach, createScreen, attachScreen }

/// Native apps connect directly; browsers require a user-supplied gateway.
/// Reconnect details prefill the form without restoring any credentials.
class SshTerminalConnectDialog extends StatefulWidget {
  const SshTerminalConnectDialog({
    super.key,
    this.requiresGateway = kIsWeb,
    this.initialConfig,
    this.jumpHostOnly = false,
    this.showSessionOptions = true,
    this.agentSupported,
    this.agentAvailable,
  });

  final bool requiresGateway;
  final SshTerminalConfig? initialConfig;

  /// Reuse the credential form for a single hop without nested routes.
  final bool jumpHostOnly;

  /// Discovery selects an existing session after authentication instead.
  final bool showSessionOptions;
  final bool? agentSupported;
  final bool? agentAvailable;

  @override
  State<SshTerminalConnectDialog> createState() => _SshConnectDialogState();
}

class _SshConnectDialogState extends State<SshTerminalConnectDialog> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  final _gateway = TextEditingController();
  final _tmuxName = TextEditingController(text: 'crispcloud');
  final _screenName = TextEditingController(text: 'crispcloud');
  SshTerminalAuthentication _authentication =
      SshTerminalAuthentication.password;
  _SessionMode _sessionMode = _SessionMode.shell;
  bool _showPrivateKey = false;
  bool _keyPasteFailed = false;
  int _keyPasteRequest = 0;
  late final bool _showGateway;
  final _jumpHosts = <SshJumpHost>[];
  final _credentialledJumps = <SshJumpHost>{};
  String? _routeError;
  bool _forwardAgent = false;
  String? _agentError;

  bool get _agentSupported =>
      widget.agentSupported ?? SshAgentConnection.supported;
  bool get _agentAvailable =>
      _agentSupported &&
      (widget.agentAvailable ?? SshAgentConnection.available);
  String get _agentUnavailableMessage => _agentSupported
      ? SshAgentException.unavailable
      : SshAgentException.unsupported;
  bool _hasJumpCredentials(SshJumpHost jump) =>
      jump.authentication == SshTerminalAuthentication.agent
      ? _agentAvailable
      : _credentialledJumps.contains(jump);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig?.withoutSecrets();
    _showGateway =
        !widget.jumpHostOnly &&
        (widget.requiresGateway || initial?.gateway != null);
    if (initial == null) return;
    _host.text = initial.host;
    _port.text = initial.port.toString();
    _username.text = initial.username;
    _gateway.text = initial.gateway?.toString() ?? '';
    _authentication = initial.authentication;
    _forwardAgent = !widget.jumpHostOnly && initial.forwardAgent;
    if (!widget.jumpHostOnly) _jumpHosts.addAll(initial.jumpHosts);
    final tmux = widget.showSessionOptions ? initial.tmux : null;
    if (tmux != null) {
      _tmuxName.text = tmux.sessionName;
      _sessionMode = tmux.mode == TmuxSessionMode.attach
          ? _SessionMode.attach
          : _SessionMode.createOrAttach;
    }
    final screen = widget.showSessionOptions ? initial.screen : null;
    if (screen != null && tmux == null) {
      _screenName.text = screen.sessionName;
      _sessionMode = screen.mode == ScreenSessionMode.attach
          ? _SessionMode.attachScreen
          : _SessionMode.createScreen;
    }
  }

  void _submit() {
    if (_form.currentState?.validate() != true) return;
    if ((_authentication == SshTerminalAuthentication.agent ||
            _forwardAgent ||
            _jumpHosts.any(
              (jump) => jump.authentication == SshTerminalAuthentication.agent,
            )) &&
        !_agentAvailable) {
      setState(() => _agentError = _agentUnavailableMessage);
      return;
    }
    if (_jumpHosts.any((jump) => !_hasJumpCredentials(jump))) {
      setState(() => _routeError = 'Enter credentials for each jump host.');
      return;
    }
    final usesKey = _authentication == SshTerminalAuthentication.privateKey;
    final gateway = _gateway.text.trim();
    final config = SshTerminalConfig(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      authentication: _authentication,
      forwardAgent: !widget.jumpHostOnly && _forwardAgent,
      password: _authentication == SshTerminalAuthentication.password
          ? _password.text
          : '',
      privateKey: usesKey ? _privateKey.text : '',
      passphrase: usesKey ? _passphrase.text : '',
      gateway: _showGateway && gateway.isNotEmpty ? Uri.parse(gateway) : null,
      jumpHosts: List.unmodifiable(_jumpHosts),
      tmux:
          _sessionMode == _SessionMode.attach ||
              _sessionMode == _SessionMode.createOrAttach
          ? TmuxSessionOptions(
              sessionName: _tmuxName.text.trim(),
              mode: _sessionMode == _SessionMode.attach
                  ? TmuxSessionMode.attach
                  : TmuxSessionMode.createOrAttach,
            )
          : null,
      screen:
          _sessionMode == _SessionMode.createScreen ||
              _sessionMode == _SessionMode.attachScreen
          ? ScreenSessionOptions(
              sessionName: _screenName.text.trim(),
              mode: _sessionMode == _SessionMode.attachScreen
                  ? ScreenSessionMode.attach
                  : ScreenSessionMode.create,
            )
          : null,
    );
    try {
      config.validateSessionOptions();
    } on ArgumentError {
      setState(
        () => _routeError = 'Jump hosts and the destination must be distinct.',
      );
      return;
    }
    Navigator.pop(context, config);
  }

  Future<void> _editJump([int? index]) async {
    if (index == null && _jumpHosts.length >= SshJumpHost.maxJumpHosts) return;
    final previous = index == null ? null : _jumpHosts[index];
    final result = await showDialog<SshTerminalConfig>(
      context: context,
      builder: (_) => SshTerminalConnectDialog(
        requiresGateway: false,
        jumpHostOnly: true,
        agentSupported: widget.agentSupported,
        agentAvailable: widget.agentAvailable,
        initialConfig: previous == null
            ? null
            : SshTerminalConfig(
                host: previous.host,
                port: previous.port,
                username: previous.username,
                authentication: previous.authentication,
              ),
      ),
    );
    if (!mounted || result == null) return;
    if (index != null &&
        (index >= _jumpHosts.length ||
            !identical(_jumpHosts[index], previous))) {
      return;
    }
    final jump = SshJumpHost(
      host: result.host,
      port: result.port,
      username: result.username,
      authentication: result.authentication,
      password: result.password,
      privateKey: result.privateKey,
      passphrase: result.passphrase,
    );
    setState(() {
      if (index == null) {
        _jumpHosts.add(jump);
      } else {
        _jumpHosts[index] = jump;
        _credentialledJumps.remove(previous);
      }
      _credentialledJumps.add(jump);
      _routeError = null;
    });
  }

  Widget _jumpRoute() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.sshJumpTr('Jump hosts'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Text(
        context.sshJumpTr(
          'Connect through up to three SSH servers, in the order shown. Credentials are requested for every server.',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      for (var i = 0; i < _jumpHosts.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${i + 1}. ${_jumpHosts[i].username}@${_jumpHosts[i].host}:${_jumpHosts[i].port}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _jumpHosts[i].authentication == SshTerminalAuthentication.agent
                ? context.sshAgentTr('Uses the local SSH agent')
                : context.sshJumpTr(
                    _hasJumpCredentials(_jumpHosts[i])
                        ? 'Credentials entered'
                        : 'Credentials needed',
                  ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: ValueKey('terminal-ssh-jump-$i-edit'),
                tooltip: context.sshJumpTr('Edit jump host'),
                onPressed: () => _editJump(i),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: ValueKey('terminal-ssh-jump-$i-remove'),
                tooltip: context.sshJumpTr('Remove jump host'),
                onPressed: () => setState(() {
                  _credentialledJumps.remove(_jumpHosts.removeAt(i));
                  _routeError = null;
                }),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('terminal-ssh-add-jump'),
          onPressed: _jumpHosts.length < SshJumpHost.maxJumpHosts
              ? () => _editJump()
              : null,
          icon: const Icon(Icons.add),
          label: Text(context.sshJumpTr('Add jump host')),
        ),
      ),
      if (_showGateway && _jumpHosts.isNotEmpty)
        Text(
          context.sshJumpTr('The gateway must forward to the first jump host.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (_routeError != null)
        Text(
          context.sshJumpTr(_routeError!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );

  void _selectAuthentication(SshTerminalAuthentication? value) {
    if (value == null || value == _authentication) return;
    setState(() {
      _authentication = value;
      _password.clear();
      _privateKey.clear();
      _passphrase.clear();
      _showPrivateKey = false;
      _keyPasteFailed = false;
      _keyPasteRequest++;
      _agentError = null;
    });
  }

  Future<void> _pastePrivateKey() async {
    final request = ++_keyPasteRequest;
    bool current() =>
        mounted &&
        request == _keyPasteRequest &&
        _authentication == SshTerminalAuthentication.privateKey;
    try {
      // Read only after this explicit user action. Assigning the controller
      // preserves PEM newlines that a single-line field's formatter removes.
      final clipboard = await Clipboard.getData('text/plain');
      if (!current()) return;
      final text = clipboard?.text;
      if (text != null && text.isNotEmpty) {
        _privateKey.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      setState(() => _keyPasteFailed = false);
    } catch (_) {
      if (current()) setState(() => _keyPasteFailed = true);
    }
  }

  String? _required(String? value) =>
      value?.trim().isNotEmpty == true ? null : context.terminalTr('Required');

  String? _validateGateway(String? value) {
    final text = value?.trim() ?? '';
    final gateway = Uri.tryParse(text);
    final message = text.isNotEmpty && gateway == null
        ? 'Use a complete wss:// URL with a valid host and port.'
        : sshGatewayValidationMessage(
            text.isEmpty ? null : gateway,
            required: widget.requiresGateway,
            rawUrl: text,
          );
    return message == null ? null : context.terminalTr(message);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(16),
    title: Text(
      widget.jumpHostOnly
          ? context.sshJumpTr('SSH jump host')
          : context.terminalTr('Connect via SSH'),
    ),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.requiresGateway && !widget.jumpHostOnly) ...[
                Text(
                  context.terminalTr(
                    'Enter a secure WebSocket gateway that forwards to this SSH server. CrispCloud does not provide a gateway.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const ValueKey('terminal-ssh-host'),
                controller: _host,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.terminalTr('Host'),
                ),
                validator: (value) =>
                    SshJumpHost.isValidHost(value?.trim() ?? '')
                    ? null
                    : context.sshJumpTr(
                        'Enter a valid host name or IP address.',
                      ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('terminal-ssh-username'),
                      controller: _username,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: context.terminalTr('Username'),
                      ),
                      validator: (value) =>
                          SshJumpHost.isValidUsername(value?.trim() ?? '')
                          ? null
                          : context.sshJumpTr('Enter a valid username.'),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      key: const ValueKey('terminal-ssh-port'),
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: context.terminalTr('Port'),
                        errorMaxLines: 3,
                      ),
                      validator: (value) {
                        final port = int.tryParse(value?.trim() ?? '');
                        return port == null || port < 1 || port > 65535
                            ? context.terminalTr('Enter a port from 1 to 65535')
                            : null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_showGateway) ...[
                TextFormField(
                  key: const ValueKey('terminal-ssh-gateway'),
                  controller: _gateway,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: context.terminalTr('WebSocket gateway'),
                    hintText: 'wss://gateway.example/ssh',
                    errorMaxLines: 4,
                  ),
                  validator: _validateGateway,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<SshTerminalAuthentication>(
                key: const ValueKey('terminal-ssh-authentication'),
                initialValue: _authentication,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.terminalTr('Authentication'),
                ),
                items: [
                  DropdownMenuItem(
                    value: SshTerminalAuthentication.password,
                    child: Text(
                      context.terminalTr('Password'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SshTerminalAuthentication.privateKey,
                    child: Text(
                      context.terminalTr('Private key'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: SshTerminalAuthentication.agent,
                    child: Text(
                      context.sshAgentTr('SSH agent'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: _selectAuthentication,
              ),
              const SizedBox(height: 8),
              if (_authentication == SshTerminalAuthentication.password)
                TextFormField(
                  key: const ValueKey('terminal-ssh-password'),
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: null,
                  decoration: InputDecoration(
                    labelText: context.terminalTr('Password'),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                )
              else if (_authentication ==
                  SshTerminalAuthentication.privateKey) ...[
                TextFormField(
                  key: const ValueKey('terminal-ssh-private-key'),
                  controller: _privateKey,
                  // Obscured multiline input is unsupported, and ordinary
                  // single-line paste strips PEM newlines. Keep the masked
                  // view read-only; the explicit paste action preserves them.
                  // Revealing the key enables normal multiline editing.
                  obscureText: !_showPrivateKey,
                  readOnly: !_showPrivateKey,
                  enableInteractiveSelection: _showPrivateKey,
                  minLines: _showPrivateKey ? 3 : 1,
                  maxLines: _showPrivateKey ? 6 : 1,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: null,
                  decoration: InputDecoration(
                    labelText: context.terminalTr('Private key'),
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(
                      key: const ValueKey('terminal-ssh-reveal-key'),
                      tooltip: context.terminalTr(
                        _showPrivateKey
                            ? 'Hide private key'
                            : 'Show private key',
                      ),
                      onPressed: () => setState(() {
                        _showPrivateKey = !_showPrivateKey;
                        _keyPasteFailed = false;
                      }),
                      icon: Icon(
                        _showPrivateKey
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: _required,
                  onChanged: (_) {
                    // A newer manual edit takes precedence over an earlier
                    // paste that is still awaiting clipboard permission.
                    _keyPasteRequest++;
                    if (_keyPasteFailed) {
                      setState(() => _keyPasteFailed = false);
                    }
                  },
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('terminal-ssh-paste-key'),
                    onPressed: _pastePrivateKey,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: Text(context.terminalTr('Paste private key')),
                  ),
                ),
                if (_keyPasteFailed)
                  Text(
                    context.terminalTr('Could not read the clipboard.'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('terminal-ssh-passphrase'),
                  controller: _passphrase,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  autofillHints: null,
                  decoration: InputDecoration(
                    labelText: context.terminalTr('Key passphrase (optional)'),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
              if (_authentication == SshTerminalAuthentication.agent)
                Text(
                  context.sshAgentTr(
                    _agentAvailable
                        ? 'Use keys from the local SSH agent. Private keys stay in the agent.'
                        : _agentUnavailableMessage,
                  ),
                ),
              if (!widget.jumpHostOnly &&
                  (_agentSupported || _forwardAgent)) ...[
                CheckboxListTile(
                  key: const ValueKey('terminal-ssh-forward-agent'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  titleAlignment: ListTileTitleAlignment.top,
                  value: _forwardAgent,
                  onChanged: (value) => setState(() {
                    _forwardAgent = value ?? false;
                    _agentError = null;
                  }),
                  title: Text(context.sshAgentTr('Forward SSH agent')),
                  subtitle: Text(
                    context.sshAgentTr(
                      'Programs on the final SSH server can request signatures from these agent keys while connected. Jump hosts do not receive agent access.',
                    ),
                  ),
                ),
              ],
              if (_agentError != null)
                Text(
                  context.sshAgentTr(_agentError!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!widget.jumpHostOnly) ...[
                const SizedBox(height: 16),
                _jumpRoute(),
              ],
              if (!widget.jumpHostOnly && widget.showSessionOptions) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<_SessionMode>(
                  key: const ValueKey('terminal-ssh-session-mode'),
                  initialValue: _sessionMode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.terminalTr('Session'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _SessionMode.shell,
                      child: Text(
                        context.terminalTr('Remote shell'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _SessionMode.createOrAttach,
                      child: Text(
                        context.terminalTr('Create or attach tmux'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _SessionMode.attach,
                      child: Text(
                        context.terminalTr('Attach existing tmux'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _SessionMode.createScreen,
                      child: Text(
                        context.screenTr('Create new screen'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: _SessionMode.attachScreen,
                      child: Text(
                        context.screenTr('Attach existing screen'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sessionMode = value);
                  },
                ),
                if (_sessionMode == _SessionMode.createOrAttach ||
                    _sessionMode == _SessionMode.attach) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('terminal-ssh-tmux-name'),
                    controller: _tmuxName,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: context.terminalTr('tmux session name'),
                      errorMaxLines: 4,
                    ),
                    validator: (value) =>
                        TmuxSessionOptions.isValidSessionName(
                          value?.trim() ?? '',
                        )
                        ? null
                        : context.terminalTr(
                            'Use 1–64 ASCII letters, digits, _ or -; do not start with -.',
                          ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.terminalTr(
                      'tmux must be installed on the server. Sessions keep running when you disconnect.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_sessionMode == _SessionMode.createScreen ||
                    _sessionMode == _SessionMode.attachScreen) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('terminal-ssh-screen-name'),
                    controller: _screenName,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: context.screenTr(
                        _sessionMode == _SessionMode.attachScreen
                            ? 'screen session name or PID.name'
                            : 'screen session name',
                      ),
                      errorMaxLines: 5,
                    ),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (_sessionMode == _SessionMode.attachScreen) {
                        return ScreenSessionOptions.isValidAttachTarget(name)
                            ? null
                            : context.screenTr(
                                'Use a session name (1–64 ASCII letters, digits, _ or -), or a full PID.name.',
                              );
                      }
                      return ScreenSessionOptions.isValidSessionName(name)
                          ? null
                          : context.terminalTr(
                              'Use 1–64 ASCII letters, digits, _ or -; do not start with -.',
                            );
                    },
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.screenTr(
                      _sessionMode == _SessionMode.attachScreen
                          ? 'Attach uses an exact name or full PID.name from screen -ls. Other displays stay connected.'
                          : 'screen must be installed on the server. New sessions keep running when you disconnect.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.terminalTr('Cancel')),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(
          widget.jumpHostOnly
              ? context.sshJumpTr('Use jump host')
              : context.terminalTr('Connect'),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    _passphrase.dispose();
    _gateway.dispose();
    _tmuxName.dispose();
    _screenName.dispose();
    super.dispose();
  }
}
