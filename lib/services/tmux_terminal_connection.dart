import 'dart:async';

import 'ssh_port_forwarding.dart';
import 'ssh_terminal_service.dart';
import 'terminal_connection.dart';
import 'terminal_forwarding_connection.dart';
import 'tmux_control_client.dart';

/// Keeps the outer terminal's lifecycle attached to a native tmux workspace.
/// Pane input and geometry go through the client's individual pane sessions.
class TmuxTerminalConnection
    implements
        TerminalConnection,
        TerminalConnectionMetadata,
        TerminalForwardingConnection,
        TerminalWorkspaceConnection {
  TmuxTerminalConnection(this.service, this.sessionId, this.client) {
    unawaited(
      client.done.then<void>(
        (_) => _finish(),
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
  Future<void> close() => _closing ??= client.close().whenComplete(_finish);
}
