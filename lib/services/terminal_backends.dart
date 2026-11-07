import 'dart:async';

import 'package:flutter/foundation.dart';

import '../widgets/terminal_process_stub.dart'
    if (dart.library.io) '../widgets/terminal_process_native.dart'
    as local;
import 'macos_app_store.dart';
import 'local_file_service.dart';
import 'sandbox_shell.dart';
import 'sandbox_shell_connection.dart';
import 'ssh_terminal_service.dart';
import 'terminal_connection.dart';
import 'ios_terminal_connection.dart';

typedef HostShellStarter = Future<local.ShellProcess?> Function(
  String directory, {
  int columns,
  int rows,
});

typedef LocalTerminalOpener = Future<TerminalConnection> Function(
  String directory,
  int columns,
  int rows,
);

/// Keep a separate filesystem grant alive until this connection has settled.
/// The older begin/end-stream API has one shared slot and cannot safely own a
/// long-lived shell alongside a transfer or a terminal restart.
Future<TerminalConnection> openScopedLocalTerminal(
  LocalFileService files,
  String directory,
  int columns,
  int rows, {
  LocalTerminalOpener? opener,
}) async {
  Future<TerminalConnection> attempt(
    String path, {
    required bool allowFallback,
  }) async {
    final opened = Completer<TerminalConnection>();
    final release = Completer<void>();
    final scopeEnded = Completer<void>();
    var scopeEntered = false;
    // The caller may fail to open a shell before a connection can observe this.
    unawaited(scopeEnded.future.then<void>((_) {}, onError: (Object _) {}));
    unawaited(() async {
      try {
        await files.withFileOperationAccess(path, () async {
          scopeEntered = true;
          final inner = await (opener ?? openLocalTerminal)(
            path,
            columns,
            rows,
          );
          opened.complete(
            _ScopedTerminalConnection(inner, () {
              if (!release.isCompleted) release.complete();
              return scopeEnded.future;
            }),
          );
          await release.future;
        });
        scopeEnded.complete();
      } catch (error, stack) {
        if (!opened.isCompleted) opened.completeError(error, stack);
        scopeEnded.completeError(error, stack);
      }
    }());
    try {
      return await opened.future;
    } catch (_) {
      if (scopeEntered || !allowFallback) rethrow;
      final fallback = await files.getSafeFallbackDirectory();
      if (fallback == path) rethrow;
      return attempt(fallback, allowFallback: false);
    }
  }

  return attempt(directory, allowFallback: true);
}

class _ScopedTerminalConnection
    implements TerminalConnection, TerminalConnectionMetadata {
  _ScopedTerminalConnection(this.inner, this.release) {
    _exitCode = _waitForExit();
    unawaited(_exitCode.then<void>((_) {}, onError: (Object _) {}));
  }

  final TerminalConnection inner;
  final Future<void> Function() release;
  late final Future<int?> _exitCode;
  Future<void>? _releaseFuture;
  Future<void>? _closeFuture;

  Future<void> _release() => _releaseFuture ??= release();

  Future<int?> _waitForExit() async {
    try {
      return await inner.exitCode;
    } finally {
      await _release();
    }
  }

  @override
  bool get isSandbox => inner.isSandbox;
  @override
  TerminalBackend get backend => inner.terminalBackend;
  @override
  Stream<String> get output => inner.output;
  @override
  Future<int?> get exitCode => _exitCode;
  @override
  Future<void> write(String data) => inner.write(data);
  @override
  Future<void> resize(int columns, int rows) => inner.resize(columns, rows);
  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    try {
      await inner.close();
    } finally {
      await _release();
    }
  }
}

Future<TerminalConnection> openLocalTerminal(
  String directory,
  int columns,
  int rows, {
  HostShellStarter? startHostShell,
  LocalTerminalOpener? startIosShell,
}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    // Native startup errors are actionable (including a busy engine). Do not
    // silently substitute a different interpreter after a failed iOS start.
    return (startIosShell ?? IosTerminalConnection.open)(
      directory,
      columns,
      rows,
    );
  }
  Object? hostFailure;
  final appStore = isMacAppStoreBuild();
  if (!appStore) {
    try {
      final process = await (startHostShell ?? local.startShell)(
        directory,
        columns: columns,
        rows: rows,
      );
      if (process != null) return _LocalTerminalConnection(process);
    } catch (error) {
      hostFailure = error;
    }
  }

  // App Sandbox denies PTY terminal attributes; Android cannot spawn a host
  // shell. The built-in shell keeps a useful terminal available on every
  // platform without weakening the sandbox. Real host shells remain available
  // in an unsandboxed desktop build and real remote shells over SSH.
  final shell = await SandboxShell.create(startPath: directory);
  if (appStore) {
    shell.startupNotice =
        'This App Store build uses the built-in sandbox shell. '
        'Use SSH for a full remote shell.';
  } else if (hostFailure != null) {
    shell.startupNotice =
        'Host shell unavailable in this build; using the built-in sandbox '
        'shell. Use SSH for a full remote shell.';
  }
  return SandboxShellConnection(shell);
}

class _LocalTerminalConnection implements TerminalConnection {
  _LocalTerminalConnection(this.process);
  final local.ShellProcess process;

  @override
  bool get isSandbox => false;

  @override
  Stream<String> get output => process.outputStream;
  @override
  Future<int?> get exitCode => process.exitCode;
  @override
  Future<void> write(String data) => process.write(data);
  @override
  Future<void> resize(int columns, int rows) async =>
      process.resize(columns, rows);
  @override
  Future<void> close() => process.dispose();
}

class SshTerminalConnection
    implements TerminalConnection, TerminalConnectionMetadata {
  SshTerminalConnection(this.service, this.sessionId, this.output);
  final SshTerminalService service;
  final String sessionId;
  @override
  final Stream<String> output;

  @override
  bool get isSandbox => false;

  @override
  TerminalBackend get backend => TerminalBackend.ssh;

  // The service can reap a shell after its channels drain but before the UI
  // consumes their buffered output. Late layout/input must not turn that
  // normal exit into an "unknown session" error.
  bool get _active =>
      service.getActiveSessions().any((session) => session.id == sessionId);

  @override
  Future<int?> get exitCode async => null;
  @override
  Future<void> write(String data) async {
    if (_active) await service.writeToShell(sessionId, data);
  }

  @override
  Future<void> resize(int columns, int rows) async {
    if (_active) await service.resizeTerminal(sessionId, columns, rows);
  }

  @override
  Future<void> close() => service.disconnect(sessionId);
}
