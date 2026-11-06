/// Shared interface for real and built-in terminal backends.
abstract interface class TerminalShell {
  Stream<String> get outputStream;
  void writeln(String command);
  void kill();
}
