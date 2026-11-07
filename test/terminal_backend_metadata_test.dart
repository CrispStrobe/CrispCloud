import 'dart:async';

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _Connection implements TerminalConnection {
  _Connection({this.isSandbox = false});

  @override
  final bool isSandbox;
  final controller = StreamController<String>();
  final ended = Completer<int?>();
  final writes = <String>[];
  final sizes = <(int, int)>[];
  int closes = 0;

  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode => ended.future;
  @override
  Future<void> write(String data) async => writes.add(data);
  @override
  Future<void> resize(int columns, int rows) async =>
      sizes.add((columns, rows));
  @override
  Future<void> close() async {
    closes++;
    if (!ended.isCompleted) ended.complete(0);
    if (!controller.isClosed) unawaited(controller.close());
  }
}

class _EmbeddedConnection extends _Connection
    implements TerminalConnectionMetadata {
  @override
  TerminalBackend get backend => TerminalBackend.ios;
}

class _Files extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  int leases = 0;
  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    leases++;
    try {
      return await action();
    } finally {
      leases--;
    }
  }
}

void main() {
  test('legacy transports retain their declared sandbox distinction', () async {
    final host = _Connection();
    final sandbox = _Connection(isSandbox: true);
    expect(host.terminalBackend, TerminalBackend.host);
    expect(sandbox.terminalBackend, TerminalBackend.sandbox);
    await host.close();
    await sandbox.close();
  });

  test(
    'the iOS engine is distinct from the Dart sandbox interpreter',
    () async {
      final session = TerminalSession();
      final connection = _EmbeddedConnection();
      addTearDown(session.dispose);
      await session.connect(
        (_, _) async => connection,
        kind: TerminalSessionKind.local,
      );
      expect(session.kind, TerminalSessionKind.ios);
      expect(session.isSandbox, isFalse);
      connection.controller.add('\x1b[32mDash ready\x1b[0m');
      await Future<void>.delayed(Duration.zero);
      expect(session.terminal.buffer.getText().trim(), 'Dash ready');
      await session.disconnect();
      expect(connection.closes, 1);
    },
  );

  test(
    'a scoped connection preserves engine identity and transport operations',
    () async {
      final files = _Files();
      final inner = _EmbeddedConnection();
      final connection = await openScopedLocalTerminal(
        files,
        '/workspace',
        80,
        24,
        opener: (_, _, _) async => inner,
      );
      expect(connection.terminalBackend, TerminalBackend.ios);
      expect(connection.isSandbox, isFalse);
      expect(files.leases, 1);
      final output = connection.output.toList();
      inner.controller.add('last output');
      await connection.write('\x03');
      await connection.resize(120, 32);
      expect(inner.writes, ['\x03']);
      expect(inner.sizes, [(120, 32)]);
      await connection.close();
      await connection.close();
      expect(await output, ['last output']);
      expect(await connection.exitCode, 0);
      expect(inner.closes, 1);
      expect(files.leases, 0);
    },
  );
}
