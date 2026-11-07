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
    unawaited(session.exitCode.then<void>((_) {}, onError: (Object _) {}));
  }

  final IosShellSession session;
  Future<void>? _closing;

  static Future<IosTerminalConnection> open(
    String directory,
    int columns,
    int rows, {
    IosShellStarter? start,
  }) async => IosTerminalConnection(
    await (start ?? IosShellSession.start)(
      workingDirectory: directory,
      columns: columns.clamp(1, 9999),
      rows: rows.clamp(1, 9999),
    ),
  );

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
    if (_closing == null) await session.write(data);
  }

  @override
  Future<void> resize(int columns, int rows) async {
    if (_closing == null) {
      await session.resize(columns.clamp(1, 9999), rows.clamp(1, 9999));
    }
  }

  @override
  Future<void> close() => _closing ??= session.close();
}
