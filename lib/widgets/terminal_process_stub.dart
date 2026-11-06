// lib/widgets/terminal_process_stub.dart
//
// Web stub — terminal is not available on web.

import 'terminal_shell.dart';

/// Abstract shell process handle.
class ShellProcess implements TerminalShell {
  Stream<String> get outputStream => const Stream.empty();
  void writeln(String command) {}
  void kill() {}
}

/// On web, always returns null (terminal not supported).
Future<ShellProcess?> startShell(String workingDirectory) async => null;

/// On web, there is no filesystem-backed built-in shell either.
Future<ShellProcess?> startBuiltInShell(String workingDirectory) async => null;
