import 'dart:async';

import 'ssh_port_forwarding.dart';
import 'ssh_terminal_service.dart';
import 'terminal_backends.dart';
import 'terminal_connection.dart';
import 'terminal_forwarding_connection.dart';
import 'tmux_control_client.dart';

/// Keeps the outer terminal's lifecycle attached to a native tmux workspace.
/// Pane input and geometry go through the client's individual pane sessions.
class TmuxTerminalConnection
    implements
        TerminalConnection,
        TerminalConnectionMetadata,
        TerminalConnectionSharing,
        TerminalForwardingConnection,
        TerminalWorkspaceConnection {
  TmuxTerminalConnection(this.service, this.sessionId, this.client) {
    unawaited(
      client.done.then<void>(
        (_) {
          final error = client.error;
          if (!_finished && error != null) _output.addError(error);
          _finish();
        },
        onError: (Object error, StackTrace stack) {
          if (!_finished) _output.addError(error, stack);
          _finish();
        },
      ),
    );
  }

  final SshTerminalService service;
  final String sessionId;
  final TmuxControlClient client;
  final _output = StreamController<String>();
  bool _finished = false;
  Future<void>? _closing;
  int _viewLeases = 0;
  bool _disposeRequested = false;
  bool _workspaceDisposed = false;

  /// Each mounted panel holds a lease until its child views have unmounted.
  /// A caller-owned session can therefore move between viewports without
  /// closing its SSH route or recreating its pane emulators.
  void retainView() {
    if (_workspaceDisposed || _disposeRequested) {
      throw StateError('The tmux workspace has been released.');
    }
    _viewLeases++;
  }

  void releaseView() {
    if (_viewLeases == 0) return;
    _viewLeases--;
    _disposeIfUnused();
  }

  @override
  TmuxControlClient get workspace => client;

  @override
  void disposeWorkspace() {
    _disposeRequested = true;
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    if (!_disposeRequested || _workspaceDisposed || _viewLeases != 0) return;
    _workspaceDisposed = true;
    client.dispose();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    unawaited(_output.close());
  }

  @override
  bool get isSandbox => false;
  @override
  TerminalBackend get backend => TerminalBackend.ssh;
  @override
  bool get canOpenSibling => service.canShareSession(sessionId);
  @override
  int get sharedSessionCount => service.connectionSessionCount(sessionId);
  @override
  Future<TerminalConnection> openSibling(int columns, int rows) =>
      openSharedSshShell(service, sessionId, columns, rows);
  @override
  bool get acceptsDirectInput => false;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => client.done;
  @override
  SshPortForwarding? get portForwarding =>
      service.canForwardPorts(sessionId) ? service.forwarding(sessionId) : null;

  @override
  Future<void> write(String data) async {
    // The workspace container is never a terminal input recipient.
  }

  @override
  Future<void> resize(int columns, int rows) async {
    // TmuxControlWorkspace measures its own viewport, excluding its controls.
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await client.close();
    } catch (_) {
      // TerminalSession retains failed cleanup and retries it on disconnect.
      // The adapter must not pin a failed client close forever.
      _closing = null;
      rethrow;
    } finally {
      _finish();
    }
  }
}
