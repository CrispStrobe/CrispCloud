/// A single interactive PTY, local or remote. The emulator owns no process.
abstract interface class TerminalConnection {
  /// Buffered until listened to; closes only after final output has drained.
  Stream<String> get output;

  /// Null when the transport does not expose a process exit status.
  Future<int?> get exitCode;

  Future<void> write(String data);
  Future<void> resize(int columns, int rows);
  Future<void> close();
}

typedef TerminalConnectionFactory = Future<TerminalConnection> Function(
  int columns,
  int rows,
);
