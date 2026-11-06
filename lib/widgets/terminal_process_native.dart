// Local desktop shells run in a real PTY, including ConPTY on Windows.
// Keep this import behind terminal_process_stub.dart's conditional import so
// web builds never load the FFI backend.

import 'dart:async';
import 'dart:io';

import 'package:flutter_pty2/flutter_pty2.dart';

/// An owned local shell and its terminal transport.
///
/// [outputStream] is single-subscription. The PTY buffers startup output until
/// the consumer attaches, and applies backpressure while the consumer pauses.
/// Input and output are UTF-8; the streaming decoder retains partial codepoints
/// between native reads. Escape sequences are deliberately left untouched.
class ShellProcess {
  ShellProcess._(this._session) : pid = _session.pid {
    _outputStream = _session.utf8Output();
    _exitCode = _waitForExit();
    // Keep a transport failure from becoming an unhandled asynchronous error
    // before the UI installs its exit listener. Awaiting exitCode still receives
    // the original error.
    unawaited(
      _exitCode.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  final PtySession _session;
  final int pid;
  late final Stream<String> _outputStream;
  late final Future<int> _exitCode;
  Future<void>? _closeFuture;

  Stream<String> get outputStream => _outputStream;

  /// Completes after the process exits, its final output drains, and native
  /// resources have been released. Signal exits use the usual 128 + signal.
  Future<int> get exitCode => _exitCode;

  /// Writes terminal input verbatim, including control and escape sequences.
  Future<void> write(String input) async {
    if (_closeFuture != null) throw StateError('The local shell has closed.');
    await _session.input.writeUtf8(input);
  }

  /// Compatibility helper for callers that intentionally submit a whole line.
  Future<void> writeln(String command) => write('$command\r');

  void resize(int columns, int rows) {
    if (_closeFuture != null) return;
    _session.resize(PtySize(columns: columns, rows: rows));
  }

  /// Terminates the session and releases its native handles. Idempotent.
  ///
  /// Explicit disposal can discard output; normal exit instead waits for
  /// [PtySession.done] before closing, preserving the last prompt or error.
  Future<void> dispose() => _closeFuture ??= _session.close();

  /// Compatibility helper. Prefer awaiting [dispose] when changing sessions.
  void kill() {
    unawaited(dispose().catchError((Object _) {}));
  }

  Future<int> _waitForExit() async {
    try {
      final exit = await _session.done;
      return switch (exit) {
        PtyExitCode(:final code) => code,
        PtySignalExit(:final signal) => 128 + signal,
      };
    } finally {
      await dispose();
    }
  }
}

/// Starts the user's local desktop shell with an initial terminal geometry.
///
/// Local process spawning is deliberately unavailable on Android and iOS;
/// those platforms use the SSH transport. Sandboxed desktop builds may reject
/// process creation, and the caller presents that error with the SSH option.
Future<ShellProcess?> startShell(
  String workingDirectory, {
  int columns = 80,
  int rows = 24,
}) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }

  final size = PtySize(columns: columns, rows: rows)..validate();
  final shell = await _shellExecutable();
  final directory = await _workingDirectory(workingDirectory);
  final options = PtySpawnOptions(
    executable: shell,
    // Unlike --login, -l is understood by sh, bash, zsh, fish and the csh family.
    // A PTY makes the shell interactive without constructing a command string.
    arguments: Platform.isWindows ? const [] : const ['-l'],
    workingDirectory: directory,
    environment: const PtyEnvironment.inherit(
      overrides: {
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
        'TERM_PROGRAM': 'CrispCloud',
      },
    ),
    size: size,
  );
  try {
    return ShellProcess._(await Pty.spawn(options));
  } on PtyException catch (error) {
    final nativeError = error.nativeError;
    if (nativeError == null) rethrow;
    // PtyException.toString omits this OS detail. Preserve it so callers can
    // distinguish a sandbox denial from a missing shell or working directory.
    throw ProcessException(
      shell,
      options.arguments,
      '${error.message}: ${nativeError.message}',
      nativeError.code,
    );
  }
}

Future<String> _shellExecutable() async {
  final environment = Platform.environment;
  if (Platform.isWindows) {
    // COMSPEC is the user's configured command interpreter. The native backend
    // uses CreateProcess directly; paths containing spaces need no quoting.
    final configured = environment['COMSPEC'] ?? environment['ComSpec'];
    return configured?.isNotEmpty == true ? configured! : 'cmd.exe';
  }

  final configured = environment['SHELL'];
  for (final candidate in [
    if (configured != null && configured.isNotEmpty) configured,
    if (Platform.isMacOS) '/bin/zsh',
    '/bin/bash',
    '/bin/sh',
  ]) {
    if (await File(candidate).exists()) return candidate;
  }
  // Let the PTY return its structured executable-not-found error.
  return '/bin/sh';
}

Future<String> _workingDirectory(String requested) async {
  final environment = Platform.environment;
  for (final candidate in [
    requested,
    if (Platform.isWindows) environment['USERPROFILE'] ?? '',
    if (!Platform.isWindows) environment['HOME'] ?? '',
    Directory.current.path,
  ]) {
    if (candidate.isEmpty) continue;
    try {
      final directory = Directory(candidate);
      if (await directory.exists()) return directory.absolute.path;
    } on FileSystemException {
      // A virtual, deleted or inaccessible browser directory must not prevent
      // opening a terminal in the user's home directory.
    }
  }
  return Directory.current.path;
}
