import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm2/xterm.dart';

import '../l10n/terminal_strings.dart';
import '../l10n/terminal_controls_strings.dart';
import '../l10n/terminal_key_binding_strings.dart';
import '../l10n/terminal_trigger_strings.dart';
import '../l10n/ssh_port_forwarding_strings.dart';
import '../l10n/terminal_shell_strings.dart';
import '../l10n/ssh_multiplexer_strings.dart';
import '../l10n/screen_terminal_strings.dart';
import '../l10n/terminal_mount_error_strings.dart';
import '../l10n/terminal_workspace_strings.dart';
import '../models/panel_side.dart';
import '../models/ssh_multiplexer_session.dart';
import '../models/terminal_arrangement.dart';
import '../providers/providers.dart';
import '../providers/terminal_workspace_provider.dart';
import '../providers/terminal_key_bindings_provider.dart';
import '../providers/terminal_triggers_provider.dart';
import '../providers/ssh_terminal_profiles_provider.dart';
import '../providers/ssh_forwarding_profiles_provider.dart';
import '../providers/focus_area_provider.dart';
import '../services/ssh_terminal_service.dart';
import '../services/ssh_forwarding_profiles.dart';
import '../services/terminal_backends.dart';
import '../services/terminal_menu.dart';
import '../services/keyboard_shortcut_service.dart';
import '../services/terminal_session.dart';
import '../services/tmux_control_client.dart';
import '../services/tmux_terminal_connection.dart';
import '../services/terminal_user_input.dart';
import '../services/terminal_shell_integration.dart';
import '../services/terminal_mount_failure.dart';
import '../services/terminal_directory.dart';
import '../services/panel_source_service.dart';
import '../services/terminal_workspace_service.dart';
import 'terminal_workspace_dialog.dart';
import 'external_terminal_dialog.dart';
import 'ssh_terminal_connect_dialog.dart';
import 'ssh_terminal_profiles_dialog.dart';
import 'ssh_multiplexer_sessions_dialog.dart';
import 'terminal_tabs.dart';
import 'terminal_search_bar.dart';
import 'terminal_command_history_dialog.dart';
import 'terminal_shell_setup_dialog.dart';
import 'tmux_control_workspace.dart';
import 'terminal_key_bindings_dialog.dart';
import 'terminal_triggers_dialog.dart';
import 'ssh_port_forwarding_dialog.dart';
import '../l10n/external_terminal_strings.dart';

export '../models/ssh_terminal_config.dart';
export 'ssh_terminal_connect_dialog.dart';

final _terminalFocusOwnerProvider = StateProvider<Object?>((ref) => null);

/// Mounts the terminal on first use, then preserves its session while hidden.
class TerminalPanelHost extends ConsumerStatefulWidget {
  const TerminalPanelHost({super.key, this.session});

  /// An injected session is owned by the caller and never autostarted here.
  final TerminalSession? session;

  @override
  ConsumerState<TerminalPanelHost> createState() => _TerminalPanelHostState();
}

class _TerminalPanelHostState extends ConsumerState<TerminalPanelHost> {
  bool _wasShown = false;

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(showTerminalProvider);
    if (visible) _wasShown = true;
    if (!_wasShown) return const SizedBox.shrink();

    return Visibility(
      visible: visible,
      maintainState: true,
      child: ExcludeFocus(
        excluding: !visible,
        child: TerminalTabs(visible: visible, session: widget.session),
      ),
    );
  }
}

class TerminalPanel extends ConsumerStatefulWidget {
  const TerminalPanel({
    super.key,
    this.session,
    this.visible = true,
    this.active = true,
    this.embedded = false,
    this.autoStart = false,
    this.focusRequest = 0,
    this.isActivePane,
    this.onActivate,
    this.onWorkspaceKey,
    this.initialPaneState,
    this.onPaneStateChanged,
  });

  /// An injected session remains caller-owned and is not automatically opened.
  final TerminalSession? session;
  final bool visible;
  final bool active;
  final bool embedded;
  final bool autoStart;
  final int focusRequest;
  final bool Function()? isActivePane;
  final VoidCallback? onActivate;
  final KeyEventResult Function(KeyEvent event)? onWorkspaceKey;
  final TerminalPaneState? initialPaneState;
  final ValueChanged<TerminalPaneState>? onPaneStateChanged;

  @override
  ConsumerState<TerminalPanel> createState() => _TerminalPanelState();
}

enum _PanelAction {
  local,
  reconnect,
  profiles,
  browseTmux,
  browseScreen,
  saveProfile,
  external,
  stage,
  workspaces,
  review,
  copy,
  paste,
  find,
  history,
  previousCommand,
  nextCommand,
  addMark,
  selectOutput,
  notifyCommand,
  shellSetup,
  keyBindings,
  triggers,
  forwarding,
  zoomIn,
  zoomOut,
  zoomReset,
  disconnect,
  hide,
}

class _TerminalPanelState extends ConsumerState<TerminalPanel> {
  final _focus = FocusNode(debugLabel: 'Terminal input');
  final _controller = TerminalController();
  final _scroll = ScrollController();
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _menuOwner = Object();
  late TerminalSession _session;
  late bool _ownsSession;
  late final SshTerminalService _ssh;
  late final StateController<TerminalMenuActions?> _menuState;
  late final StateController<bool> _inputFocusedState;
  late final StateController<Object?> _focusOwnerState;
  late final StateController<FocusArea> _focusAreaState;
  Terminal? _observedTerminal;
  void Function(String)? _previousTitleHandler;
  void Function(String)? _titleHandler;
  String? _title;
  bool _menuUpdateScheduled = false;
  TerminalWorkspace? _workspace;
  // Reconnect remembers the destination and session mode, never credentials.
  SshTerminalConfig? _lastSshConfig;
  SshForwardingProfileSession? _forwardingProfiles;
  final _forwardingDialogLeases = <SshForwardingProfileSession, int>{};
  Terminal? _tmuxTerminal;
  TmuxControlClient? _tmuxControl;
  Terminal? _tmuxControlTerminal;
  bool _tmuxPaneFocused = false;
  Terminal? _screenTerminal;
  bool _showSearch = false;
  bool _searchFits = true;
  bool _preferSearchFocus = false;
  int _searchFocusRequest = 0;
  double _fontSize = 13;
  int _connectionRequest = 0;
  int _shellNotificationSerial = 0;
  int _triggerNotificationSerial = 0;
  bool _triggerNoticeScheduled = false;
  CellAnchor? _commandNavigationAnchor;
  bool _revealingCommand = false;
  Set<PhysicalKeyboardKey> get _mappedKeyPresses =>
      ref.read(terminalKeyBindingPressesProvider);

  bool get _desktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows => true,
        _ => false,
      };

  bool get _mobile =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  bool get _canDisconnect => _session.canDisconnect;
  bool get _activePane =>
      widget.active && (widget.isActivePane?.call() ?? true);

  bool get _usingTmux =>
      _session.kind == TerminalSessionKind.ssh &&
      identical(_tmuxTerminal, _session.terminal);

  bool get _usingScreen =>
      _session.kind == TerminalSessionKind.ssh &&
      identical(_screenTerminal, _session.terminal);

  TmuxControlClient? get _nativeTmux =>
      identical(_tmuxControlTerminal, _session.terminal) ? _tmuxControl : null;

  void _retireTmuxControl() {
    final client = _tmuxControl;
    _tmuxControl = null;
    _tmuxControlTerminal = null;
    _tmuxPaneFocused = false;
    if (client == null) return;
    // Existing pane views detach before their emulators are disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(client.close().whenComplete(client.dispose));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool get _canCopy =>
      _controller.selectionFor(_session.terminal.buffer) != null;

  @override
  void initState() {
    super.initState();
    _restorePaneState();
    _ssh = ref.read(sshTerminalServiceProvider);
    _menuState = ref.read(terminalMenuProvider.notifier);
    _inputFocusedState = ref.read(terminalInputFocusedProvider.notifier);
    _focusOwnerState = ref.read(_terminalFocusOwnerProvider.notifier);
    _focusAreaState = ref.read(focusAreaProvider.notifier);
    _focus.addListener(_onInputFocusChanged);
    _controller.addListener(_scheduleMenuUpdate);
    _scroll.addListener(_onScrollChanged);
    _attachSession(widget.session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.visible && widget.active) _focus.requestFocus();
      if (_ownsSession || widget.autoStart) {
        unawaited(_startLocal());
      } else {
        _focusIfVisible();
      }
    });
  }

  void _restorePaneState() {
    final state = widget.initialPaneState;
    _fontSize = state?.fontSize ?? 13;
    _lastSshConfig = state?.sshConfig?.withoutSecrets();
  }

  void _publishPaneState() => widget.onPaneStateChanged?.call(
    TerminalPaneState(fontSize: _fontSize, sshConfig: _lastSshConfig),
  );

  void _attachSession(TerminalSession? session) {
    _ownsSession = session == null;
    _session = session ?? TerminalSession();
    _session.addListener(_onSessionChanged);
    _attachTerminal();
  }

  void _detachTitleHandler() {
    final terminal = _observedTerminal;
    if (terminal != null && identical(terminal.onTitleChange, _titleHandler)) {
      terminal.onTitleChange = _previousTitleHandler;
    }
    _observedTerminal = null;
    _titleHandler = null;
    _previousTitleHandler = null;
  }

  void _attachTerminal() {
    _detachTitleHandler();
    _clearCommandNavigation();
    _shellNotificationSerial = 0;
    _triggerNotificationSerial = 0;
    _triggerNoticeScheduled = false;
    final terminal = _session.terminal;
    _observedTerminal = terminal;
    _title = null;
    _controller.clearSelection();
    final previous = terminal.onTitleChange;
    _previousTitleHandler = previous;
    _titleHandler = (value) {
      previous?.call(value);
      if (!mounted || !identical(_session.terminal, terminal)) return;
      // Titles are display text only, never commands or file-browser paths.
      final plain = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
      setState(
        () => _title = plain.length > 200 ? plain.substring(0, 200) : plain,
      );
    };
    terminal.onTitleChange = _titleHandler;
  }

  @override
  void didUpdateWidget(TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _retireTmuxControl();
      _connectionRequest++;
      _clearForwardingProfiles();
      _workspace = null;
      _restorePaneState();
      _session.removeListener(_onSessionChanged);
      _detachTitleHandler();
      if (_ownsSession) _session.dispose();
      _attachSession(widget.session);
      if (_ownsSession || widget.autoStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_startLocal());
        });
      }
    }
    if (!widget.visible || !widget.active) {
      _focus.unfocus();
    } else if (!oldWidget.visible ||
        !oldWidget.active ||
        oldWidget.focusRequest != widget.focusRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusIfVisible());
    }
    _scheduleMenuUpdate();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (_tmuxControl != null &&
        !identical(_tmuxControlTerminal, _session.terminal)) {
      _retireTmuxControl();
    }
    final forwardingProfiles = _forwardingProfiles;
    if (forwardingProfiles != null && !forwardingProfiles.isCurrent) {
      _clearForwardingProfiles();
    }
    if (!identical(_observedTerminal, _session.terminal)) _attachTerminal();
    final shell = _session.shellIntegration;
    if (_session.triggerNotificationSerial != _triggerNotificationSerial &&
        !_triggerNoticeScheduled) {
      _triggerNoticeScheduled = true;
      final identity = _session.connectionIdentity;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerNoticeScheduled = false;
        if (!mounted || !identical(identity, _session.connectionIdentity)) {
          return;
        }
        _triggerNotificationSerial = _session.triggerNotificationSerial;
        final match = _session.triggerNotification;
        if (match == null) return;
        final line = match.line.length > 160
            ? '${match.line.substring(0, 160)}…'
            : match.line;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(content: Text('${match.trigger.name} · $line')),
        );
      });
    }
    if (shell.notificationSerial != _shellNotificationSerial) {
      _shellNotificationSerial = shell.notificationSerial;
      final mark = shell.completionNotification;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            mark == null ||
            !identical(shell, _session.shellIntegration)) {
          return;
        }
        final status = mark.exitCode == null
            ? context.terminalShellTr('Status unknown')
            : '${context.terminalShellTr('Exit status')}: ${mark.exitCode}';
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              '${context.terminalShellTr('Command finished')} · $status',
            ),
          ),
        );
      });
    }
    setState(() {});
    _scheduleMenuUpdate();
  }

  void _focusIfVisible() {
    if (mounted &&
        _nativeTmux == null &&
        widget.visible &&
        _activePane &&
        !(_showSearch && _searchFits && _preferSearchFocus) &&
        _focusAreaState.state == FocusArea.terminal) {
      _focus.requestFocus();
    }
  }

  void _activateInput() {
    if (_preferSearchFocus) setState(() => _preferSearchFocus = false);
    widget.onActivate?.call();
    _focusAreaState.state = FocusArea.terminal;
    if (widget.active && _nativeTmux == null) _focus.requestFocus();
  }

  void _onTmuxPaneFocusChanged(bool focused) {
    if (!mounted) return;
    _tmuxPaneFocused = focused;
    if (focused && widget.visible && _activePane) {
      _focus.unfocus();
      _focusOwnerState.state = _menuOwner;
      _inputFocusedState.state = true;
      _focusAreaState.state = FocusArea.terminal;
    } else if (identical(_focusOwnerState.state, _menuOwner) &&
        !_focus.hasFocus) {
      _focusOwnerState.state = null;
      _inputFocusedState.state = false;
    }
    _scheduleMenuUpdate();
  }

  void _activateSearch() {
    setState(() {
      _preferSearchFocus = true;
      _searchFocusRequest++;
    });
    widget.onActivate?.call();
    _focusAreaState.state = FocusArea.terminal;
  }

  void _onInputFocusChanged() {
    if (!mounted) return;
    if (_focus.hasFocus) {
      _focusOwnerState.state = _menuOwner;
      _inputFocusedState.state = true;
      _focusAreaState.state = FocusArea.terminal;
    } else if (identical(_focusOwnerState.state, _menuOwner)) {
      _focusOwnerState.state = null;
      _inputFocusedState.state = false;
    }
    _scheduleMenuUpdate();
  }

  /// Native menu snapshots are published after layout, never during build.
  void _scheduleMenuUpdate() {
    if (!mounted || _menuUpdateScheduled) return;
    _menuUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _menuUpdateScheduled = false;
      if (!mounted) return;
      final current = _menuState.state;
      if (!widget.visible ||
          !widget.active ||
          (!_focus.hasFocus && !_tmuxPaneFocused)) {
        if (identical(current?.owner, _menuOwner)) _menuState.state = null;
        return;
      }
      final canCopy = _nativeTmux == null && _canCopy;
      final canPaste = _session.acceptsDirectInput;
      final canDisconnect = _canDisconnect;
      if (identical(current?.owner, _menuOwner) &&
          current!.canCopy == canCopy &&
          current.canPaste == canPaste &&
          current.canDisconnect == canDisconnect) {
        return;
      }
      _menuState.state = TerminalMenuActions(
        owner: _menuOwner,
        perform: _performMenuAction,
        canCopy: canCopy,
        canPaste: canPaste,
        canDisconnect: canDisconnect,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _performMenuAction(TerminalMenuAction action) {
    if (!mounted ||
        !widget.visible ||
        !widget.active ||
        (!_focus.hasFocus && !_tmuxPaneFocused)) {
      return;
    }
    switch (action) {
      case TerminalMenuAction.copy:
        if (_nativeTmux == null) unawaited(_copySelection());
      case TerminalMenuAction.paste:
        if (_nativeTmux == null) unawaited(_paste());
      case TerminalMenuAction.disconnect:
        if (_canDisconnect) unawaited(_session.disconnect());
      case TerminalMenuAction.hide:
        _hide();
    }
  }

  List<PanelSource> _localSources() {
    final active = ref.read(activePanelProvider);
    final sources = <PanelSource>[];
    for (final side in {active, PanelSide.local, PanelSide.remote}) {
      try {
        sources.add(
          ref.read(panelProvider(side)).captureCurrentOrigin().source,
        );
      } on StateError {
        // A loading/archived/stale listing cannot authorize a local path.
      }
    }
    return sources;
  }

  Future<void> _startLocal({TerminalWorkspace? workspace}) async {
    if (!mounted) return;
    final request = ++_connectionRequest;
    _workspace = workspace;
    _lastSshConfig = null;
    _publishPaneState();
    final files = ref.read(localFileServiceProvider);
    final sources = workspace == null ? _localSources() : <PanelSource>[];
    final connecting = _session.connect(
      (columns, rows) async {
        final directory =
            workspace?.directoryPath ??
            await resolveTerminalDirectory(
              sources,
              fallback: files.getInitialPath,
            );
        if (!mounted || request != _connectionRequest) {
          throw StateError('Shell connection was cancelled.');
        }
        return kIsWeb
            ? openLocalTerminal(directory, columns, rows)
            : openScopedLocalTerminal(files, directory, columns, rows);
      },
      kind: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? TerminalSessionKind.ios
          : TerminalSessionKind.local,
      label: context.terminalTr('Local shell'),
    );
    final terminal = _session.terminal;
    await connecting;
    if (mounted && identical(_session.terminal, terminal)) {
      // The connected session replaces the idle terminal and rebuilds
      // TerminalView. Request focus after that rebuild, not before it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusIfVisible();
      });
    }
  }

  TerminalWorkspaceBinding? _resolveWorkspace(TerminalWorkspace workspace) {
    if (!mounted) return null;
    final origin = ref
        .read(panelProvider(ref.read(activePanelProvider)))
        .resolveStorageReference(workspace.storage, workspace.remoteRoot);
    final source = origin?.source;
    if (origin == null || source is! RemotePanelSource || !origin.isCurrent) {
      return null;
    }
    return TerminalWorkspaceBinding(
      client: source.client,
      isCurrent: () => origin.isCurrent,
    );
  }

  Future<void> _stageSelected() async {
    final service = ref.read(terminalWorkspaceServiceProvider);
    try {
      final panel = ref.read(panelProvider(ref.read(activePanelProvider)));
      final items = panel.selection.isNotEmpty
          ? panel.selection.toList()
          : [if (panel.cursorItem != null) panel.cursorItem!];
      final origin = panel.captureOperationOrigin(items);
      final source = origin.source;
      if (source is! RemotePanelSource) {
        throw StateError(
          context.workspaceTr('Choose cloud files in the file panel first.'),
        );
      }
      final workspace = await showTerminalWorkspaceTask<TerminalWorkspace>(
        context,
        title: context.workspaceTr('Staging files…'),
        task: (cancelled, progress) => service.stage(
          client: source.client,
          remoteRoot: source.currentPath,
          items: items,
          storage: origin.storageReference,
          isCurrent: () => origin.isCurrent,
          isCancelled: cancelled,
          onProgress: progress,
        ),
      );
      if (mounted && widget.visible && workspace != null) {
        await _startLocal(workspace: workspace);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _showWorkspaces() async {
    final workspace = await showDialog<TerminalWorkspace>(
      context: context,
      builder: (_) => TerminalWorkspacesDialog(
        service: ref.read(terminalWorkspaceServiceProvider),
        resolve: _resolveWorkspace,
      ),
    );
    if (mounted && widget.visible && workspace != null) {
      await _startLocal(workspace: workspace);
    }
  }

  Future<void> _reviewWorkspace() async {
    final workspace = _workspace;
    if (workspace == null) return;
    await reviewTerminalWorkspace(
      context,
      service: ref.read(terminalWorkspaceServiceProvider),
      workspace: workspace,
      resolve: _resolveWorkspace,
    );
  }

  Future<void> _connectSsh({
    bool reconnect = false,
    SshTerminalConfig? initialConfig,
    SshMultiplexer? browse,
  }) async {
    if (_session.isConnecting) return;
    _activateInput();
    final config = await showDialog<SshTerminalConfig>(
      context: context,
      builder: (_) => SshTerminalConnectDialog(
        initialConfig:
            initialConfig ??
            (reconnect || browse != null ? _lastSshConfig : null),
        showSessionOptions: browse == null,
      ),
    );
    if (!mounted || config == null || !widget.visible) return;
    try {
      config.validateSessionOptions();
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.terminalControlsTr('Invalid session settings')),
        ),
      );
      return;
    }
    _connectionRequest++;
    _workspace = null;
    _lastSshConfig = config.withoutSecrets();
    _publishPaneState();

    var launchConfig = config;
    var selectionCancelled = false;
    Terminal? connectingTerminal;
    bool currentAttempt() =>
        mounted &&
        _session.isConnecting &&
        identical(_session.terminal, connectingTerminal);

    String connectionLabel(SshTerminalConfig value) =>
        '${value.username}@${value.host}'
        '${value.tmux == null ? '' : ' · tmux: ${value.tmux!.sessionName}'}'
        '${value.screen == null ? '' : ' · screen: ${value.screen!.sessionName}'}';

    Future<bool> prompt(String endpoint, String fingerprint) async {
      if (!currentAttempt() || !widget.visible) return false;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.terminalTr('Trust SSH host?')),
          content: SingleChildScrollView(
            child: Text(
              TerminalStrings(dialogContext).trust(endpoint, fingerprint),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.terminalTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.terminalTr('Trust & Connect')),
            ),
          ],
        ),
      );
      return accepted == true && currentAttempt();
    }

    final connecting = _session.connect(
      (columns, rows) async {
        final session = await switch (config.authentication) {
          SshTerminalAuthentication.privateKey => _ssh.connectWithKey(
            config.host,
            config.port,
            config.username,
            config.privateKey,
            passphrase: config.passphrase.isEmpty ? null : config.passphrase,
            gateway: config.gateway,
            jumpHosts: config.jumpHosts,
            forwardAgent: config.forwardAgent,
            isCurrent: currentAttempt,
            hostKeyPrompt: prompt,
          ),
          SshTerminalAuthentication.password => _ssh.connect(
            config.host,
            config.port,
            config.username,
            config.password,
            gateway: config.gateway,
            jumpHosts: config.jumpHosts,
            forwardAgent: config.forwardAgent,
            isCurrent: currentAttempt,
            hostKeyPrompt: prompt,
          ),
          SshTerminalAuthentication.agent => _ssh.connectWithAgent(
            config.host,
            config.port,
            config.username,
            gateway: config.gateway,
            jumpHosts: config.jumpHosts,
            forwardAgent: config.forwardAgent,
            isCurrent: currentAttempt,
            hostKeyPrompt: prompt,
          ),
        };
        try {
          if (!currentAttempt()) {
            throw StateError('SSH connection was cancelled');
          }
          final multiplexer = browse;
          if (multiplexer != null) {
            final sessions = await _ssh.listMultiplexerSessions(
              session.id,
              kind: multiplexer,
              isCurrent: () => currentAttempt() && widget.visible,
            );
            if (!currentAttempt() || !widget.visible) {
              selectionCancelled = true;
              throw StateError('SSH session selection was cancelled');
            }
            final selected = await _chooseMultiplexerSession(
              multiplexer,
              sessions,
              isCurrent: currentAttempt,
            );
            if (!currentAttempt() ||
                !widget.visible ||
                selected == null ||
                !selected.selectable ||
                selected.kind != multiplexer) {
              selectionCancelled = true;
              throw StateError('SSH session selection was cancelled');
            }
            launchConfig = SshTerminalConfig(
              host: config.host,
              port: config.port,
              username: config.username,
              password: config.password,
              privateKey: config.privateKey,
              passphrase: config.passphrase,
              authentication: config.authentication,
              forwardAgent: config.forwardAgent,
              gateway: config.gateway,
              jumpHosts: config.jumpHosts,
              tmux: selected.tmuxOptions,
              screen: selected.screenOptions,
            );
            launchConfig.validateSessionOptions();
            _lastSshConfig = launchConfig.withoutSecrets();
            _publishPaneState();
            _session.label = connectionLabel(launchConfig);
            _tmuxTerminal = launchConfig.tmux == null
                ? null
                : connectingTerminal;
            _screenTerminal = launchConfig.screen == null
                ? null
                : connectingTerminal;
          }
          final tmux = launchConfig.tmux;
          if (tmux?.controlMode == true) {
            final raw = await _ssh.startTmuxControl(
              session.id,
              tmux: tmux!,
              width: columns,
              height: rows,
            );
            final client = TmuxControlClient(
              output: raw.output,
              write: raw.write,
              close: raw.close,
              exitCode: raw.exitCode,
            );
            final owner = _session;
            void cancelStaleStart() {
              if (!currentAttempt()) unawaited(client.close());
            }

            owner.addListener(cancelStaleStart);
            try {
              if (!currentAttempt()) {
                throw StateError('tmux control start was cancelled');
              }
              await client.start(columns: columns, rows: rows);
              if (!currentAttempt()) {
                throw StateError('tmux control start was cancelled');
              }
              _tmuxControl = client;
              _tmuxControlTerminal = connectingTerminal;
              return TmuxTerminalConnection(_ssh, session.id, client);
            } catch (error) {
              await client.close();
              client.dispose();
              final diagnostics = raw.diagnostics;
              if (diagnostics.isNotEmpty) {
                throw StateError('$error\n$diagnostics');
              }
              rethrow;
            } finally {
              owner.removeListener(cancelStaleStart);
            }
          }
          final stream = await _ssh.startShell(
            session.id,
            width: columns,
            height: rows,
            tmux: launchConfig.tmux,
            screen: launchConfig.screen,
          );
          return SshTerminalConnection(_ssh, session.id, stream);
        } catch (error) {
          await _ssh.disconnect(session.id);
          if (browse != null && (!currentAttempt() || !widget.visible)) {
            selectionCancelled = true;
          }
          if (error is SshMultiplexerDiscoveryException &&
              mounted &&
              currentAttempt()) {
            throw Exception(context.sshMultiplexerDiscoveryError(error));
          }
          rethrow;
        }
      },
      kind: TerminalSessionKind.ssh,
      label: connectionLabel(config),
    );
    connectingTerminal = _session.terminal;
    _tmuxTerminal = config.tmux == null ? null : connectingTerminal;
    _screenTerminal = config.screen == null ? null : connectingTerminal;
    await connecting;
    if (mounted && identical(_session.terminal, connectingTerminal)) {
      if (selectionCancelled) await _session.disconnect();
      if (_session.isConnected) _startSavedForwarding(launchConfig);
      _focusIfVisible();
    }
  }

  void _clearForwardingProfiles() {
    final previous = _forwardingProfiles;
    _forwardingProfiles = null;
    // Connection identity revokes start authority immediately. An open dialog
    // still owns a live notifier so saved recipes can be edited while offline.
    if (previous != null && !_forwardingDialogLeases.containsKey(previous)) {
      previous.dispose();
    }
  }

  Future<void> _showForwardingDialog() async {
    final forwarding = _session.portForwarding;
    if (forwarding == null) return;
    final profiles = _forwardingProfiles;
    if (profiles != null) {
      _forwardingDialogLeases.update(
        profiles,
        (leases) => leases + 1,
        ifAbsent: () => 1,
      );
    }
    try {
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        builder: (_) =>
            SshPortForwardingDialog(forwarding: forwarding, profiles: profiles),
      );
      await navigator.push(route);
      // A popped dialog remains mounted during its reverse transition.
      await route.completed;
    } finally {
      if (profiles != null) {
        final leases = _forwardingDialogLeases[profiles]! - 1;
        if (leases == 0) {
          _forwardingDialogLeases.remove(profiles);
          if (!identical(_forwardingProfiles, profiles)) profiles.dispose();
        } else {
          _forwardingDialogLeases[profiles] = leases;
        }
      }
    }
  }

  void _startSavedForwarding(SshTerminalConfig config) {
    _clearForwardingProfiles();
    final manager = _session.portForwarding;
    if (manager == null) return;
    final identity = _session.connectionIdentity;
    final profiles = SshForwardingProfileSession(
      store: ref.read(sshForwardingProfilesProvider),
      route: SshForwardingRoute.fromConfig(config),
      forwarding: manager,
      isCurrent: () =>
          mounted &&
          _session.isConnected &&
          identical(identity, _session.connectionIdentity) &&
          identical(manager, _session.portForwarding),
    );
    _forwardingProfiles = profiles;
    // This runs only after the verified shell is published. A canceled session
    // picker, failed authentication or replacement never starts saved listeners.
    // The coordinator cancels pending work when this connection identity ends.
    unawaited(
      profiles.startAutomatic().then((_) {
        if (!mounted || !profiles.isCurrent) return;
        String? error = profiles.error;
        for (final profile in profiles.profiles) {
          error ??= profiles.profileError(profile.id);
        }
        if (error != null) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(context.sshForwardTr(error))));
        }
      }),
    );
  }

  Future<SshMultiplexerSession?> _chooseMultiplexerSession(
    SshMultiplexer kind,
    List<SshMultiplexerSession> sessions, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() || !widget.visible) return null;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<SshMultiplexerSession>(
      context: context,
      builder: (_) =>
          SshMultiplexerSessionsDialog(kind: kind, sessions: sessions),
    );
    // Close only our owned dialog if the connection is replaced or the panel
    // disappears. A late picker result can never attach to a different tab.
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if ((!isCurrent() || !widget.visible) &&
          navigator.mounted &&
          route.isActive) {
        navigator.removeRoute(route);
      }
    });
    try {
      return await navigator.push(route);
    } finally {
      timer.cancel();
    }
  }

  Future<void> _showProfiles() async {
    final config = await showDialog<SshTerminalConfig>(
      context: context,
      builder: (_) => SshTerminalProfilesDialog(
        store: ref.read(sshTerminalProfilesProvider),
      ),
    );
    if (mounted && widget.visible && config != null) {
      await _connectSsh(initialConfig: config.withoutSecrets());
    }
  }

  Future<void> _saveProfile() async {
    final config = _lastSshConfig;
    if (config == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => SaveSshTerminalProfileDialog(
        store: ref.read(sshTerminalProfilesProvider),
        config: config.withoutSecrets(),
      ),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.terminalControlsTr('Saved SSH profile')),
        ),
      );
    }
  }

  Future<void> _copyText(String text) async {
    if (text.isNotEmpty) await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _copySelection() async {
    final terminal = _session.terminal;
    final selection = _controller.selectionFor(terminal.buffer);
    if (selection != null) {
      await _copyText(terminal.buffer.getText(selection, true));
    }
  }

  Future<void> _paste() async {
    if (!_session.isConnected || !widget.visible || !_activePane) return;
    final terminal = _session.terminal;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        !widget.visible ||
        !_activePane ||
        !_focus.hasFocus ||
        _focusAreaState.state != FocusArea.terminal ||
        !_session.isConnected ||
        !identical(terminal, _session.terminal)) {
      return;
    }
    if (data?.text case final text?) {
      terminal.paste(text);
      _controller.clearSelection();
      _focusIfVisible();
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  KeyEventResult _onTerminalKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // A fresh press can use an edited/disabled mapping. Only the repeat and
      // release edges of a mapped press are swallowed, even if modifiers change.
      _mappedKeyPresses.remove(event.physicalKey);
    } else if (_mappedKeyPresses.contains(event.physicalKey)) {
      if (event is KeyUpEvent) _mappedKeyPresses.remove(event.physicalKey);
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    final workspaceResult = widget.onWorkspaceKey?.call(event);
    if (workspaceResult != null && workspaceResult != KeyEventResult.ignored) {
      return workspaceResult;
    }
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command =
        !keyboard.isAltPressed &&
        (apple
            ? keyboard.isMetaPressed && !keyboard.isControlPressed
            : keyboard.isControlPressed &&
                  keyboard.isShiftPressed &&
                  !keyboard.isMetaPressed);
    if (command) {
      final key = event.logicalKey;
      final find = key == LogicalKeyboardKey.keyF;
      final zoomIn =
          key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd;
      final zoomOut =
          key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract;
      final reset =
          key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0;
      if (keyboard.isShiftPressed &&
          (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown)) {
        if (event is KeyDownEvent) {
          _moveCommand(forward: key == LogicalKeyboardKey.arrowDown);
        }
        return KeyEventResult.handled;
      }
      if (find || zoomIn || zoomOut || reset) {
        if (event is KeyDownEvent) {
          if (find) _openSearch();
          if (zoomIn) _setFontSize(_fontSize + 1);
          if (zoomOut) _setFontSize(_fontSize - 1);
          if (reset) _setFontSize(13);
        }
        return KeyEventResult.handled;
      }
    }
    final action = ref
        .read(keyboardShortcutServiceProvider)
        .resolveBrowser(
          event,
          isCtrl: keyboard.isControlPressed,
          isMeta: keyboard.isMetaPressed,
          isShift: keyboard.isShiftPressed,
          isAlt: keyboard.isAltPressed,
        );
    if (action == ShortcutAction.terminal) {
      _hide();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      // Keep Ctrl+C as interrupt even when text is selected. Copy has its
      // explicit Ctrl+Shift+C / Command+C shortcut and toolbar action.
      _session.terminal.keyInput(
        TerminalKey.keyC,
        ctrl: true,
        text: 'c',
        type: switch (event) {
          KeyUpEvent() => TerminalKeyEventType.release,
          KeyRepeatEvent() => TerminalKeyEventType.repeat,
          _ => TerminalKeyEventType.press,
        },
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        !event.synthesized &&
        mounted &&
        widget.visible &&
        _activePane &&
        _focus.hasFocus &&
        _session.isConnected) {
      final mappings = ref.read(terminalKeyBindingListProvider);
      if (!mappings.isLoading && !mappings.hasError) {
        for (final binding in mappings.valueOrNull ?? const []) {
          if (!binding.enabled ||
              binding.chord.isReserved(apple: apple) ||
              !binding.chord.matches(
                event,
                ctrl: keyboard.isControlPressed,
                alt: keyboard.isAltPressed,
                shift: keyboard.isShiftPressed,
                meta: keyboard.isMetaPressed,
              )) {
            continue;
          }
          final terminal = _session.terminal;
          _mappedKeyPresses.add(event.physicalKey);
          final input = binding.input;
          if (terminal is InputAwareTerminal) {
            terminal.submitUserInput(input);
          } else {
            input.applyTo(terminal);
          }
          _controller.clearSelection();
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showKeyBindings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const TerminalKeyBindingsDialog(),
    );
    _focusIfVisible();
  }

  void _setFontSize(double size) {
    final next = size.clamp(8.0, 32.0);
    if (next == _fontSize) return;
    setState(() => _fontSize = next);
    _publishPaneState();
  }

  void _clearCommandNavigation() {
    _commandNavigationAnchor?.dispose();
    _commandNavigationAnchor = null;
  }

  void _onScrollChanged() {
    if (!_revealingCommand) _clearCommandNavigation();
  }

  void _revealCommandLine(int line) {
    final terminal = _session.terminal;
    if (terminal.isUsingAltBuffer ||
        line < 0 ||
        line >= terminal.buffer.lines.length) {
      return;
    }
    _clearCommandNavigation();
    _commandNavigationAnchor = terminal.buffer.createAnchor(0, line);
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final cellHeight = _terminalViewKey.currentState?.renderTerminal.lineHeight;
    if (cellHeight == null || !cellHeight.isFinite || cellHeight <= 0) return;
    final position = _scroll.position;
    final target =
        line * cellHeight - (position.viewportDimension - cellHeight) / 2;
    _revealingCommand = true;
    try {
      _scroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    } finally {
      _revealingCommand = false;
    }
  }

  void _moveCommand({required bool forward}) {
    final terminal = _session.terminal;
    if (terminal.isUsingAltBuffer) return;
    final anchor = _commandNavigationAnchor;
    var line = terminal.buffer.absoluteCursorY;
    if (anchor != null && terminal.buffer.ownsAnchor(anchor)) {
      line = anchor.y;
    } else if (_scroll.hasClients &&
        _scroll.position.hasContentDimensions &&
        _scroll.offset < _scroll.position.maxScrollExtent - 1) {
      final height = _terminalViewKey.currentState?.renderTerminal.lineHeight;
      if (height != null && height.isFinite && height > 0) {
        line = (_scroll.offset / height).floor();
      }
    }
    final target = forward
        ? _session.shellIntegration.lineAfter(line)
        : _session.shellIntegration.lineBefore(line);
    if (target != null) _revealCommandLine(target);
  }

  Future<void> _showCommandHistory() async {
    final shell = _session.shellIntegration;
    final mark = await showDialog<TerminalCommandMark>(
      context: context,
      builder: (_) => TerminalCommandHistoryDialog(integration: shell),
    );
    if (!mounted ||
        !widget.visible ||
        !identical(shell, _session.shellIntegration) ||
        mark == null ||
        !shell.contains(mark)) {
      return;
    }
    _activateInput();
    _revealCommandLine(mark.anchor.y);
  }

  void _selectLastOutput() {
    final shell = _session.shellIntegration;
    final mark = shell.latestCommand;
    if (mark == null) return;
    final range = shell.outputRange(mark);
    if (range == null) return;
    final buffer = _session.terminal.buffer;
    _controller.setSelection(
      buffer.createAnchorFromOffset(range.begin),
      buffer.createAnchorFromOffset(range.end),
    );
    _revealCommandLine(range.begin.y);
  }

  void _openSearch() {
    setState(() => _showSearch = true);
    _activateSearch();
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _preferSearchFocus = false;
    });
    _focusIfVisible();
  }

  void _sendKey(TerminalKey key, {bool ctrl = false}) {
    if (!_session.isConnected) return;
    _activateInput();
    _session.terminal.keyInput(key, ctrl: ctrl);
    _focusIfVisible();
  }

  void _hide() {
    _focus.unfocus();
    setTerminalVisible(ref, false);
    _scheduleMenuUpdate();
  }

  String _statusText() => switch (_session.status) {
    TerminalSessionStatus.idle => context.terminalTr('Terminal'),
    TerminalSessionStatus.connecting => context.terminalTr('Connecting…'),
    TerminalSessionStatus.connected =>
      _session.isSandbox
          ? context.terminalTr('Sandbox shell')
          : _session.kind == TerminalSessionKind.ios
          ? context.workspaceTr('iOS shell')
          : context.terminalTr('Connected'),
    TerminalSessionStatus.disconnected => context.terminalTr('Disconnected'),
    TerminalSessionStatus.waitingForExit => context.terminalTr(
      'Waiting for exit…',
    ),
    TerminalSessionStatus.exited =>
      '${context.terminalTr('Exited')}'
          '${_session.exitCode == null ? '' : ' (${_session.exitCode})'}',
    TerminalSessionStatus.failed => context.terminalTr('Failed'),
  };

  String? _message() {
    final error = _session.error;
    if (error != null) {
      if (error is TerminalCleanupFailure) {
        return '${context.workspaceTr('Shell cleanup failed')}: '
            '${localizedTerminalMountError(context, error.cause)}';
      }
      if (error is TerminalMountFailure) {
        return localizedTerminalMountError(context, error);
      }
      final detail = localizedTerminalMountError(context, error);
      final heading = _session.kind == TerminalSessionKind.ssh
          ? 'SSH connection failed'
          : _session.kind == TerminalSessionKind.sandbox
          ? 'Built-in shell failed to start'
          : 'Shell failed to start';
      return '${context.terminalTr(heading)}: $detail';
    }
    if (kIsWeb && _session.status == TerminalSessionStatus.idle) {
      return context.terminalTr('Starting the built-in browser shell…');
    }
    if (_mobile && _session.status == TerminalSessionStatus.idle) {
      return context.terminalTr('Starting the built-in shell…');
    }
    return null;
  }

  void _performAction(_PanelAction action) {
    _activateInput();
    switch (action) {
      case _PanelAction.local:
        unawaited(_startLocal());
      case _PanelAction.reconnect:
        unawaited(_connectSsh(reconnect: true));
      case _PanelAction.profiles:
        unawaited(_showProfiles());
      case _PanelAction.browseTmux:
        unawaited(_connectSsh(browse: SshMultiplexer.tmux));
      case _PanelAction.browseScreen:
        unawaited(_connectSsh(browse: SshMultiplexer.screen));
      case _PanelAction.saveProfile:
        unawaited(_saveProfile());
      case _PanelAction.external:
        unawaited(showExternalTerminalDialog(context, ref));
      case _PanelAction.stage:
        unawaited(_stageSelected());
      case _PanelAction.workspaces:
        unawaited(_showWorkspaces());
      case _PanelAction.review:
        unawaited(_reviewWorkspace());
      case _PanelAction.copy:
        unawaited(_copySelection());
      case _PanelAction.paste:
        unawaited(_paste());
      case _PanelAction.find:
        _openSearch();
      case _PanelAction.history:
        unawaited(_showCommandHistory());
      case _PanelAction.previousCommand:
        _moveCommand(forward: false);
      case _PanelAction.nextCommand:
        _moveCommand(forward: true);
      case _PanelAction.addMark:
        _session.shellIntegration.addMark();
      case _PanelAction.selectOutput:
        _selectLastOutput();
      case _PanelAction.notifyCommand:
        final shell = _session.shellIntegration;
        shell.notifyOnCompletion = !shell.notifyOnCompletion;
      case _PanelAction.shellSetup:
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const TerminalShellSetupDialog(),
          ),
        );
      case _PanelAction.keyBindings:
        unawaited(_showKeyBindings());
      case _PanelAction.triggers:
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const TerminalTriggersDialog(),
          ),
        );
      case _PanelAction.forwarding:
        unawaited(_showForwardingDialog());
      case _PanelAction.zoomIn:
        _setFontSize(_fontSize + 1);
      case _PanelAction.zoomOut:
        _setFontSize(_fontSize - 1);
      case _PanelAction.zoomReset:
        _setFontSize(13);
      case _PanelAction.disconnect:
        unawaited(_session.disconnect());
      case _PanelAction.hide:
        _hide();
    }
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final backendLabel = _session.kind == TerminalSessionKind.ios
        ? context.workspaceTr('iOS shell')
        : context.terminalTr(
            _session.kind == TerminalSessionKind.sandbox
                ? 'Built-in shell'
                : _desktop
                ? 'Local shell'
                : 'Terminal',
          );
    final connectionLabel = _session.kind == TerminalSessionKind.ssh
        ? _session.label ?? backendLabel
        : _workspace == null
        ? backendLabel
        : '$backendLabel · ${_workspace!.title}';
    // The remote OSC title supplements the trusted endpoint label. It must
    // never replace the host identity shown by the connection UI.
    final title = _title?.isNotEmpty == true
        ? '$connectionLabel: $_title'
        : connectionLabel;
    final focused =
        widget.active && ref.watch(focusAreaProvider) == FocusArea.terminal;
    return GestureDetector(
      onTap: () {
        _activateInput();
      },
      child: Material(
        color: focused
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: SizedBox(
          height: 48,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  const SizedBox(width: 8),
                  if (constraints.maxWidth >= 280) ...[
                    const Icon(Icons.terminal, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Tooltip(
                      message: '$title · ${_statusText()}',
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ),
                  if (constraints.maxWidth >= 480)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _statusText(),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  if (_session.isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  IconButton(
                    key: const ValueKey('terminal-connect-ssh'),
                    tooltip: context.terminalTr('Connect via SSH'),
                    onPressed: _session.isConnecting ? null : _connectSsh,
                    icon: const Icon(Icons.dns_outlined, size: 20),
                  ),
                  PopupMenuButton<_PanelAction>(
                    key: const ValueKey('terminal-actions'),
                    tooltip: context.terminalTr('Terminal actions'),
                    onOpened: _activateInput,
                    onSelected: _performAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _PanelAction.profiles,
                        enabled: !_session.isConnecting,
                        child: Text(
                          context.terminalControlsTr('Saved SSH profiles'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.browseTmux,
                        enabled: !_session.isConnecting,
                        child: Text(
                          context.sshMultiplexerTr('Browse tmux sessions'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.browseScreen,
                        enabled: !_session.isConnecting,
                        child: Text(
                          context.sshMultiplexerTr('Browse screen sessions'),
                        ),
                      ),
                      if (_lastSshConfig != null)
                        PopupMenuItem(
                          value: _PanelAction.saveProfile,
                          child: Text(
                            context.terminalControlsTr('Save SSH profile'),
                          ),
                        ),
                      if (_lastSshConfig != null)
                        PopupMenuItem(
                          value: _PanelAction.reconnect,
                          enabled: !_session.isConnecting,
                          child: Text(context.terminalTr('Reconnect SSH')),
                        ),
                      PopupMenuItem(
                        value: _PanelAction.disconnect,
                        enabled: _canDisconnect,
                        child: Text(
                          _usingScreen
                              ? context.screenTr('Detach from screen')
                              : context.terminalTr(
                                  _usingTmux
                                      ? 'Detach from tmux'
                                      : 'Disconnect',
                                ),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.local,
                        child: Text(
                          context.terminalTr(
                            _workspace != null
                                ? _session.kind == TerminalSessionKind.sandbox
                                      ? 'Start built-in shell'
                                      : 'Start local shell'
                                : _session.kind == TerminalSessionKind.sandbox
                                ? _canDisconnect
                                      ? 'Restart built-in shell'
                                      : 'Start built-in shell'
                                : (_session.kind == TerminalSessionKind.local ||
                                          _session.kind ==
                                              TerminalSessionKind.ios) &&
                                      _canDisconnect
                                ? 'Restart local shell'
                                : _desktop ||
                                      (!kIsWeb &&
                                          defaultTargetPlatform ==
                                              TargetPlatform.iOS)
                                ? 'Start local shell'
                                : 'Start built-in shell',
                          ),
                        ),
                      ),
                      if (ref
                          .read(terminalWorkspaceServiceProvider)
                          .isSupported) ...[
                        PopupMenuItem(
                          value: _PanelAction.stage,
                          child: Text(
                            context.workspaceTr('Stage selected files'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _PanelAction.workspaces,
                          child: Text(context.workspaceTr('Staged workspaces')),
                        ),
                        if (_workspace != null)
                          PopupMenuItem(
                            value: _PanelAction.review,
                            child: Text(context.workspaceTr('Review uploads')),
                          ),
                      ],
                      if (ref.read(externalTerminalServiceProvider).platform !=
                          null)
                        PopupMenuItem(
                          value: _PanelAction.external,
                          child: Text(
                            ExternalTerminalStrings(context).text('open'),
                          ),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.copy,
                          enabled: _canCopy,
                          child: Text(context.terminalTr('Copy selection')),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.paste,
                          enabled: _session.isConnected,
                          child: Text(context.terminalTr('Paste')),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.find,
                          child: Text(
                            context.terminalControlsTr('Find in terminal'),
                          ),
                        ),
                      PopupMenuItem(
                        value: _PanelAction.zoomIn,
                        enabled: _fontSize < 32,
                        child: Text(
                          context.terminalControlsTr('Increase font size'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.zoomOut,
                        enabled: _fontSize > 8,
                        child: Text(
                          context.terminalControlsTr('Decrease font size'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.zoomReset,
                        enabled: _fontSize != 13,
                        child: Text(
                          context.terminalControlsTr('Reset font size'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.keyBindings,
                        child: Text(
                          context.terminalKeyBindingTr('Key bindings'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PanelAction.triggers,
                        child: Text(
                          context.terminalTriggerTr('Output triggers'),
                        ),
                      ),
                      if (_session.kind == TerminalSessionKind.ssh)
                        PopupMenuItem(
                          value: _PanelAction.forwarding,
                          enabled: _session.portForwarding != null,
                          child: Text(context.sshForwardTr('Port forwarding')),
                        ),
                      PopupMenuItem(
                        value: _PanelAction.shellSetup,
                        child: Text(
                          context.terminalShellTr('Shell integration setup'),
                        ),
                      ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.history,
                          child: Text(
                            context.terminalShellTr('Command history'),
                          ),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.previousCommand,
                          enabled:
                              !_session.terminal.isUsingAltBuffer &&
                              _session.shellIntegration.marks.isNotEmpty,
                          child: Text(
                            context.terminalShellTr('Previous command'),
                          ),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.nextCommand,
                          enabled:
                              !_session.terminal.isUsingAltBuffer &&
                              _session.shellIntegration.marks.isNotEmpty,
                          child: Text(context.terminalShellTr('Next command')),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.addMark,
                          enabled: !_session.terminal.isUsingAltBuffer,
                          child: Text(context.terminalShellTr('Add mark')),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.selectOutput,
                          enabled:
                              _session.shellIntegration.latestCommand != null &&
                              _session.shellIntegration.outputRange(
                                    _session.shellIntegration.latestCommand!,
                                  ) !=
                                  null,
                          child: Text(
                            context.terminalShellTr(
                              'Select last command output',
                            ),
                          ),
                        ),
                      if (_nativeTmux == null)
                        PopupMenuItem(
                          value: _PanelAction.notifyCommand,
                          enabled: _session.isConnected,
                          child: Text(
                            context.terminalShellTr(
                              _session.shellIntegration.notifyOnCompletion
                                  ? 'Cancel command notification'
                                  : 'Notify when command finishes',
                            ),
                          ),
                        ),
                      PopupMenuItem(
                        value: _PanelAction.hide,
                        child: Text(context.terminalTr('Hide terminal')),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert, size: 20),
                  ),
                  IconButton(
                    key: const ValueKey('terminal-hide'),
                    tooltip: context.terminalTr('Hide terminal'),
                    onPressed: _hide,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildExtraKeys() {
    const keys = <(String, TerminalKey, bool)>[
      ('Esc', TerminalKey.escape, false),
      ('Tab', TerminalKey.tab, false),
      ('Ctrl+A', TerminalKey.keyA, true),
      ('Ctrl+B', TerminalKey.keyB, true),
      ('Ctrl+C', TerminalKey.keyC, true),
      ('Ctrl+D', TerminalKey.keyD, true),
      ('Ctrl+Z', TerminalKey.keyZ, true),
      ('←', TerminalKey.arrowLeft, false),
      ('↓', TerminalKey.arrowDown, false),
      ('↑', TerminalKey.arrowUp, false),
      ('→', TerminalKey.arrowRight, false),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 48,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (label, key, ctrl) in keys)
                TextButton(
                  onPressed: _session.isConnected
                      ? () => _sendKey(key, ctrl: ctrl)
                      : null,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: Text(label),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShellStatus() {
    final shell = _session.shellIntegration;
    final command = shell.latestCommand;
    final status = command?.running == true
        ? context.terminalShellTr('Running')
        : command?.exitCode == null
        ? ''
        : '${context.terminalShellTr('Exit status')}: ${command!.exitCode}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        key: const ValueKey('terminal-shell-status'),
        onTap: () => unawaited(_showCommandHistory()),
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const Icon(Icons.history, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message:
                        '${context.terminalShellTr('Shell-reported directory')}: ${shell.currentDirectory ?? ''}',
                    child: Text(
                      shell.currentDirectory ??
                          context.terminalShellTr('Command history'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                if (status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                if (shell.notifyOnCompletion)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.notifications_active_outlined, size: 14),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep mappings current across every mounted pane, including hidden tabs.
    // Errors remain in the settings dialog; malformed data never enables input.
    ref.watch(terminalKeyBindingListProvider);
    final triggers = ref.watch(terminalTriggerListProvider);
    _session.updateTriggers(triggers.valueOrNull ?? const []);
    ref.listen<FocusArea>(focusAreaProvider, (_, next) {
      if (next == FocusArea.terminal) {
        _focusIfVisible();
      } else {
        _focus.unfocus();
      }
    });
    final requestedHeight = ref.watch(terminalHeightProvider);
    final media = MediaQuery.of(context);
    final view = View.of(context);
    // Scaffold removes body viewInsets after resizing for the keyboard. Keep
    // the actual view inset so the panel also leaves room for browser chrome.
    final keyboardInset = math.max(
      media.viewInsets.bottom,
      view.viewInsets.bottom / view.devicePixelRatio,
    );
    final message = _message();
    final nativeTmux = _nativeTmux;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave room for browser chrome and adapt when the phone keyboard opens.
        final available = math.max(
          80.0,
          media.size.height - keyboardInset - media.padding.vertical - 160,
        );
        final maximum = math.min(
          600.0,
          constraints.hasBoundedHeight
              ? math.min(available, constraints.maxHeight)
              : available,
        );
        final height = widget.embedded && constraints.hasBoundedHeight
            ? constraints.maxHeight
            : requestedHeight
                  .clamp(math.min(140.0, maximum), maximum)
                  .toDouble();
        final wasSearchVisible = _showSearch && _searchFits;
        _searchFits = height >= (constraints.maxWidth < 300 ? 150 : 110);
        final showSearch = _showSearch && _searchFits;
        if (wasSearchVisible && !showSearch) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _focusIfVisible(),
          );
        }
        final showExtraKeys = _mobile && height >= (showSearch ? 190 : 140);
        return SizedBox(
          key: const ValueKey('terminal-panel'),
          height: height,
          child: Column(
            children: [
              if (!widget.embedded)
                MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      ref
                          .read(terminalHeightProvider.notifier)
                          .state = (height - details.delta.dy)
                          .clamp(math.min(140.0, maximum), maximum)
                          .toDouble();
                    },
                    child: Container(
                      height: 6,
                      color: Theme.of(context).dividerColor,
                      alignment: Alignment.center,
                      child: Container(
                        width: 40,
                        height: 2,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              _buildHeader(),
              if (_showSearch && nativeTmux == null)
                Visibility(
                  visible: showSearch,
                  maintainState: true,
                  child: TerminalSearchBar(
                    active:
                        showSearch &&
                        widget.visible &&
                        widget.active &&
                        ref.watch(focusAreaProvider) == FocusArea.terminal,
                    autofocus: _preferSearchFocus,
                    focusRequest: widget.focusRequest + _searchFocusRequest,
                    onWorkspaceKey: widget.onWorkspaceKey,
                    onActivate: _activateSearch,
                    terminal: _session.terminal,
                    controller: _controller,
                    scrollController: _scroll,
                    lineHeight: () =>
                        _terminalViewKey
                            .currentState
                            ?.renderTerminal
                            .lineHeight ??
                        16,
                    onClose: _closeSearch,
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: nativeTmux != null
                          ? TmuxControlWorkspace(
                              client: nativeTmux,
                              visible: widget.visible,
                              active:
                                  widget.active &&
                                  ref.watch(focusAreaProvider) ==
                                      FocusArea.terminal,
                              fontSize: _fontSize,
                              focusRequest: widget.focusRequest,
                              onActivate: _activateInput,
                              onPaneFocusChanged: _onTmuxPaneFocusChanged,
                              onWorkspaceKey: widget.onWorkspaceKey,
                              onDetach: () => unawaited(_session.disconnect()),
                            )
                          : Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (_) => _activateInput(),
                              child: Focus(
                                canRequestFocus: false,
                                skipTraversal: true,
                                // Unhandled terminal keys must reach the IME, never the file
                                // browser's Enter/F-key/delete handlers higher in the focus tree.
                                onKeyEvent: (_, __) =>
                                    KeyEventResult.skipRemainingHandlers,
                                child: TerminalView(
                                  _session.terminal,
                                  key: _terminalViewKey,
                                  controller: _controller,
                                  focusNode: _focus,
                                  scrollController: _scroll,
                                  readOnly: !_session.isConnected,
                                  autofocus: false,
                                  deleteDetection: _mobile,
                                  keyboardType: TextInputType.multiline,
                                  keyboardAppearance: Brightness.dark,
                                  textStyle: TerminalStyle(
                                    fontFamily: 'AppMono',
                                    fontSize: _fontSize,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  shiftOverridesMouseReporting: true,
                                  dragOverridesMouseReporting: _mobile,
                                  onCopy: _copyText,
                                  onPaste: _paste,
                                  onKeyEvent: _onTerminalKey,
                                ),
                              ),
                            ),
                    ),
                    if (message != null)
                      Positioned.fill(
                        child: Align(
                          alignment: _session.error == null
                              ? Alignment.center
                              : Alignment.topCenter,
                          child: Semantics(
                            liveRegion: true,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: _session.error == null
                                    ? math.max(
                                        0,
                                        height - 54 - (showExtraKeys ? 48 : 0),
                                      )
                                    : 80,
                              ),
                              child: Material(
                                color: _session.error == null
                                    ? const Color(0xff1e1e1e)
                                    : Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      color: _session.error == null
                                          ? const Color(0xffcccccc)
                                          : Theme.of(context)
                                                .colorScheme
                                                .onErrorContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showExtraKeys && nativeTmux == null) _buildExtraKeys(),
              if (nativeTmux == null &&
                  height >= 220 &&
                  !_session.terminal.isUsingAltBuffer &&
                  (_session.shellIntegration.detected ||
                      _session.shellIntegration.currentDirectory != null))
                _buildShellStatus(),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _retireTmuxControl();
    _scroll.removeListener(_onScrollChanged);
    _clearCommandNavigation();
    _connectionRequest++;
    _clearForwardingProfiles();
    _focus.removeListener(_onInputFocusChanged);
    _controller.removeListener(_scheduleMenuUpdate);
    _session.removeListener(_onSessionChanged);
    _detachTitleHandler();
    final menuState = _menuState;
    final focusOwner = _focusOwnerState;
    final inputFocused = _inputFocusedState;
    final owner = _menuOwner;
    scheduleMicrotask(() {
      try {
        if (identical(menuState.state?.owner, owner)) menuState.state = null;
        if (identical(focusOwner.state, owner)) {
          focusOwner.state = null;
          inputFocused.state = false;
        }
      } catch (_) {
        // ProviderScope may have been disposed along with the app.
      }
    });
    if (_ownsSession) _session.dispose();
    _focus.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
