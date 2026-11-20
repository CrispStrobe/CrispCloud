import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// Runs `tool/macros/office_macro.dart` in a child Dart VM for CLI tests.
//
// The CLI is compiled to kernel once per test file, so each invocation skips
// front-end compilation of the whole engine and per-test time stays bounded.
// Every child has a hard deadline and is killed on timeout and on test
// teardown (including a test-level timeout), so no orphan survives its test.
//
// Call [registerOfficeMacroCliCleanup] from `main` to remove the compiled
// kernel after the file's tests.

/// Per-invocation deadline. Generous for slow CI runners; a hang still fails.
const Duration officeMacroCliTimeout = Duration(minutes: 2);

/// Per-test timeout for tests that start several CLI processes.
const Timeout officeMacroCliTestTimeout = Timeout(Duration(minutes: 5));

final Set<Process> _live = <Process>{};
Future<String>? _entry;
Directory? _kernelDirectory;

/// Registers removal of the compiled kernel and of any leftover process.
void registerOfficeMacroCliCleanup() {
  tearDownAll(() {
    _killAll();
    final directory = _kernelDirectory;
    _kernelDirectory = null;
    _entry = null;
    if (directory != null && directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
}

/// Runs the office macro CLI with [args] and returns its decoded result.
Future<ProcessResult> runOfficeMacroCli(
  List<String> args, {
  Duration timeout = officeMacroCliTimeout,
}) async {
  final entry = await (_entry ??= _compile());
  return _run(_dartExecutable(), <String>[
    if (entry.endsWith('.dart')) ..._packagesArgument(),
    entry,
    ...args,
  ], timeout);
}

const String _script = 'tool/macros/office_macro.dart';

List<String> _packagesArgument() => <String>[
  if (Platform.packageConfig case final String packages) '--packages=$packages',
];

/// Kernel when the toolchain can produce it; otherwise the source script.
Future<String> _compile() async {
  final directory = Directory.systemTemp.createTempSync('quds-office-macro-');
  _kernelDirectory = directory;
  final kernel = '${directory.path}${Platform.pathSeparator}office_macro.dill';
  final result = await _run(_dartExecutable(), <String>[
    'compile',
    'kernel',
    ..._packagesArgument(),
    _script,
    '-o',
    kernel,
  ], const Duration(minutes: 3));
  if (result.exitCode == 0 && File(kernel).existsSync()) return kernel;
  return _script;
}

/// A Dart VM, also when the tests themselves run under `flutter_tester`.
///
/// `flutter_tester` does not exit when a script's `main` returns, so it must
/// never be used to host the CLI.
String _dartExecutable() {
  final executable = Platform.resolvedExecutable;
  final name = executable.split(Platform.pathSeparator).last.toLowerCase();
  if (name == 'dart' || name == 'dart.exe') return executable;
  final dartName = Platform.isWindows ? 'dart.exe' : 'dart';
  var directory = File(executable).parent;
  while (directory.parent.path != directory.path) {
    final candidate = File(
      [
        directory.path,
        'dart-sdk',
        'bin',
        dartName,
      ].join(Platform.pathSeparator),
    );
    if (candidate.existsSync()) return candidate.path;
    directory = directory.parent;
  }
  return dartName;
}

Future<ProcessResult> _run(
  String executable,
  List<String> args,
  Duration timeout,
) async {
  final process = await Process.start(executable, args);
  _live.add(process);
  try {
    addTearDown(() => _kill(process));
  } on StateError {
    // Outside a test body; [registerOfficeMacroCliCleanup] still kills it.
  }
  final stdoutText = process.stdout.transform(utf8.decoder).join();
  final stderrText = process.stderr.transform(utf8.decoder).join();
  final int code;
  try {
    code = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    _kill(process);
    fail(
      'office_macro ${args.join(' ')} did not exit within $timeout and was '
      'killed',
    );
  }
  _live.remove(process);
  return ProcessResult(process.pid, code, await stdoutText, await stderrText);
}

void _kill(Process process) {
  if (_live.remove(process)) process.kill(ProcessSignal.sigkill);
}

void _killAll() {
  for (final process in _live.toList()) {
    _kill(process);
  }
}
