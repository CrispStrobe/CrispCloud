// lib/widgets/terminal_process_stub.dart
//
// Web stub — terminal is not available on web.

/// Abstract shell process handle.
class ShellProcess {
  Stream<String> get outputStream => const Stream.empty();
  void writeln(String command) {}
  void kill() {}
}

/// On web, always returns null (terminal not supported).
Future<ShellProcess?> startShell(String workingDirectory) async => null;
