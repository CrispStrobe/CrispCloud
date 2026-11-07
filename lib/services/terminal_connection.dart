/// A single interactive terminal transport. The emulator owns no process.
abstract interface class TerminalConnection {
  /// True when this is the pure-Dart, sandbox-safe shell rather than a host
  /// process. The UI uses it to label the session honestly.
  bool get isSandbox;

  /// Buffered until listened to; closes only after final output has drained.
  Stream<String> get output;

  /// Null when the transport does not expose a process exit status.
  Future<int?> get exitCode;

  Future<void> write(String data);
  Future<void> resize(int columns, int rows);
  Future<void> close();
}

/// The engine behind a connection, independent of the terminal viewport.
enum TerminalBackend { host, sandbox, ios, ssh }

/// Optional metadata keeps existing transports and test doubles compatible.
///
/// The embedded iOS engine runs inside the application sandbox, but it is not
/// the limited pure-Dart command interpreter identified by [isSandbox].
abstract interface class TerminalConnectionMetadata {
  TerminalBackend get backend;
}

extension TerminalConnectionBackend on TerminalConnection {
  TerminalBackend get terminalBackend => this is TerminalConnectionMetadata
      ? (this as TerminalConnectionMetadata).backend
      : isSandbox
      ? TerminalBackend.sandbox
      : TerminalBackend.host;
}

typedef TerminalConnectionFactory = Future<TerminalConnection> Function(
  int columns,
  int rows,
);
