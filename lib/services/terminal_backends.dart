import '../widgets/terminal_process_stub.dart'
    if (dart.library.io) '../widgets/terminal_process_native.dart'
    as local;
import 'ssh_terminal_service.dart';
import 'terminal_connection.dart';

Future<TerminalConnection> openLocalTerminal(
  String directory,
  int columns,
  int rows,
) async {
  final process = await local.startShell(
    directory,
    columns: columns,
    rows: rows,
  );
  if (process == null) {
    throw UnsupportedError(
      'Local shells are available on desktop. Use SSH on mobile.',
    );
  }
  return _LocalTerminalConnection(process);
}

class _LocalTerminalConnection implements TerminalConnection {
  _LocalTerminalConnection(this.process);
  final local.ShellProcess process;

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
