import '../widgets/terminal_process_stub.dart'
    if (dart.library.io) '../widgets/terminal_process_native.dart'
    as local;
import 'macos_app_store.dart';
import 'sandbox_shell.dart';
import 'sandbox_shell_connection.dart';
import 'ssh_terminal_service.dart';
import 'terminal_connection.dart';

typedef HostShellStarter = Future<local.ShellProcess?> Function(
  String directory, {
  int columns,
  int rows,
});

Future<TerminalConnection> openLocalTerminal(
  String directory,
  int columns,
  int rows, {
  HostShellStarter? startHostShell,
}) async {
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

  // App Sandbox denies PTY terminal attributes; iOS/Android have no process
  // spawn at all. The built-in shell keeps a useful terminal available on every
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

class SshTerminalConnection implements TerminalConnection {
  SshTerminalConnection(this.service, this.sessionId, this.output);
  final SshTerminalService service;
  final String sessionId;
  @override
  final Stream<String> output;

  @override
  bool get isSandbox => false;

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
