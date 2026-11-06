// lib/widgets/terminal_process_native.dart
//
// Native (non-web) shell process using dart:io.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Shell process wrapper.
class ShellProcess {
  final Process _process;
  late final Stream<String> _outputStream;

  ShellProcess._(this._process) {
    final controller = StreamController<String>.broadcast();
    _process.stdout.listen(
      (data) => controller.add(utf8.decode(data, allowMalformed: true)),
    );
    _process.stderr.listen(
      (data) => controller.add(utf8.decode(data, allowMalformed: true)),
    );
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

String _accessibleWorkingDirectory(String requested) {
  bool usable(String path) {
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  if (usable(requested)) return requested;
  final home = Platform.environment['HOME'];
  if (home != null && usable(home)) return home;
  final temp = Directory.systemTemp.path;
  return usable(temp) ? temp : Directory.current.path;
}

/// Start a local shell process.
///
/// A plain [Process.start] has no controlling terminal: interactive shells do
/// not print a prompt, and line editing/job control do not work. On macOS we
/// run the shell under `script`, which allocates a pseudo-terminal. The child
/// still inherits the app sandbox, so paths outside the app's grants remain
/// inaccessible unless the user grants them.
Future<ShellProcess?> startShell(String workingDirectory) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }

  final shell = Platform.isWindows
      ? 'cmd.exe'
      : Platform.environment['SHELL'] ?? '/bin/bash';
  final cwd = _accessibleWorkingDirectory(workingDirectory);

  Process process;
  if (Platform.isMacOS && File('/usr/bin/script').existsSync()) {
    process = await Process.start(
      '/usr/bin/script',
      <String>['-q', '/dev/null', shell, '-i'],
      workingDirectory: cwd,
      environment: Platform.environment,
    );
  } else {
    process = await Process.start(
      shell,
      Platform.isWindows ? <String>[] : <String>['--login', '-i'],
      workingDirectory: cwd,
      environment: Platform.environment,
    );
  }

  return ShellProcess._(process);
}
