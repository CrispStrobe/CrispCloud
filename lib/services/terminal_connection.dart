/// A single interactive terminal transport. The emulator owns no process.
abstract interface class TerminalConnection {
  /// True when this is the pure-Dart, sandbox-safe shell rather than a host
  /// process. The UI uses it to label the session honestly.
  bool get isSandbox;

  /// Buffered until listened to; closes only after final output has drained.
  Stream<String> get output;

  /// Null when the transport does not expose a process exit status.
  /// For a scoped local transport, this must settle only after the owned
  /// runtime has released its resources, even when it reports a transport
  /// error: the wrapper releases its folder grant at that point. A failed
  /// [close] leaves it pending while native cleanup is unconfirmed.
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

/// An optional capability to open an independent shell on the exact verified
/// transport already owned by this connection. This never looks up a different
/// connection by destination or copies a remote multiplexer launch command.
abstract interface class TerminalConnectionSharing {
  bool get canOpenSibling;

  /// Logical terminals currently retaining this transport, including this one.
  int get sharedSessionCount;

  /// Reserves a new transport lease before awaiting the remote shell channel.
  /// The returned connection owns that lease independently of its source.
  Future<TerminalConnection> openSibling(int columns, int rows);
}

/// A transport may own a workspace whose individual panes receive input.
/// The outer connection must not be offered as a broadcast destination: its
/// active pane can change without replacing the verified SSH connection.
abstract interface class TerminalWorkspaceConnection {
  bool get acceptsDirectInput;

  /// View state owned by the session rather than one mounted viewport.
  /// It remains available for read-only inspection after disconnect.
  Object get workspace;

  /// Releases retained buffers when the session is replaced or disposed.
  /// Implementations may defer actual disposal until mounted views detach.
  void disposeWorkspace();
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
