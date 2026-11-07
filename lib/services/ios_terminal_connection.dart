import 'dart:async';

import 'package:crisp_ios_shell/crisp_ios_shell.dart';

import 'terminal_connection.dart';

typedef IosShellStarter = Future<IosShellSession> Function({
  required String workingDirectory,
  int columns,
  int rows,
});

/// Connects the bundled Dash runtime to the existing xterm/session boundary.
/// Directory grants are owned by openScopedLocalTerminal until native exit.
class IosTerminalConnection
    implements TerminalConnection, TerminalConnectionMetadata {
  IosTerminalConnection(this.session) {
    // Output may fail before the owner has started awaiting the exit status.
    unawaited(
      session.exitCode.then<void>(
        (_) => _settled(),
        onError: (Object _) => _settled(),
      ),
    );
  }

  // A disposed viewport must not orphan an unacknowledged native shutdown.
  // The next local session retries it before asking the singleton to start.
  static final _pendingCleanup = <IosTerminalConnection>{};
  final IosShellSession session;
  Future<void>? _closing;
  bool _closeRequested = false;
  bool _nativeSettled = false;

  void _settled() {
    _nativeSettled = true;
    _pendingCleanup.remove(this);
  }

  static Future<IosTerminalConnection> open(
    String directory,
    int columns,
    int rows, {
    IosShellStarter? start,
  }) async {
    for (final connection in _pendingCleanup.toList()) {
      await connection.close();
    }
    return IosTerminalConnection(
      await (start ?? IosShellSession.start)(
        workingDirectory: directory,
        columns: columns.clamp(1, 9999),
        rows: rows.clamp(1, 9999),
      ),
    );
  }

  @override
  TerminalBackend get backend => TerminalBackend.ios;
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => session.output;
  @override
  Future<int?> get exitCode => session.exitCode;
  @override
  Future<void> write(String data) async {
    if (!_closeRequested) await session.write(data);
  }

  @override
  Future<void> resize(int columns, int rows) async {
    if (!_closeRequested) {
      await session.resize(columns.clamp(1, 9999), rows.clamp(1, 9999));
    }
  }

  @override
  Future<void> close() {
    _closeRequested = true;
    if (!_nativeSettled) _pendingCleanup.add(this);
    return _closing ??= Future<void>.sync(session.close)
        .then<void>((_) {
          _pendingCleanup.remove(this);
        })
        .onError((Object error, StackTrace stack) {
          _closing = null;
          if (!_nativeSettled) _pendingCleanup.add(this);
          Error.throwWithStackTrace(error, stack);
        });
  }
}
