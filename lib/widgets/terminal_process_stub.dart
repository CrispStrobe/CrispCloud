// Web has no local process API. The terminal UI uses this matching interface
// without importing dart:io or the native PTY library.

class ShellProcess {
  Stream<String> get outputStream => const Stream.empty();
  Future<int> get exitCode async => 0;
  int get pid => 0;
  Future<void> write(String input) async {}
  Future<void> writeln(String command) async {}
  void resize(int columns, int rows) {}
  Future<void> dispose() async {}
  void kill() {}
}

Future<ShellProcess?> startShell(
  String workingDirectory, {
  int columns = 80,
  int rows = 24,
}) async => null;
