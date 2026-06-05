// lib/widgets/terminal_process_native.dart
//
// Native (non-web) shell process using dart:io.

import 'dart:async';
import 'dart:io';

/// Shell process wrapper.
class ShellProcess {
  final Process _process;
  late final Stream<String> _outputStream;

  ShellProcess._(this._process) {
    final controller = StreamController<String>.broadcast();
    _process.stdout.listen((data) => controller.add(String.fromCharCodes(data)));
    _process.stderr.listen((data) => controller.add(String.fromCharCodes(data)));
    _process.exitCode.then((_) => controller.close());
    _outputStream = controller.stream;
  }

  Stream<String> get outputStream => _outputStream;

  void writeln(String command) {
    _process.stdin.writeln(command);
  }

  void kill() {
    _process.kill();
  }
}

/// Start a local shell process.
Future<ShellProcess?> startShell(String workingDirectory) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }

  final shell = Platform.isWindows
      ? 'cmd.exe'
      : Platform.environment['SHELL'] ?? '/bin/bash';
  final args = Platform.isWindows ? <String>[] : <String>['--login'];

  final process = await Process.start(
    shell, args,
    workingDirectory: workingDirectory,
    environment: Platform.environment,
  );

  return ShellProcess._(process);
}
