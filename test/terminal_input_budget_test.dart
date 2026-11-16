import 'dart:async';

import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bounded input fails before scheduling an overflowing queued operation',
    () async {
      final session = TerminalSession(
        maxLines: 500,
        maximumPendingInputCodeUnits: 8,
      );
      final connection = _Connection(block: true);
      addTearDown(session.dispose);
      await session.connect(
        (_, __) async => connection,
        kind: TerminalSessionKind.ssh,
      );
      session.terminal.textInput('12345678');
      await _events();
      expect(connection.writes, ['12345678']);
      session.terminal.textInput('overflow');
      expect(session.status, TerminalSessionStatus.failed);
      await _events();
      expect(connection.closed, isTrue);
      expect(connection.writes, ['12345678']);
    },
  );

  test(
    'successful writes release capacity for later user operations',
    () async {
      final session = TerminalSession(maximumPendingInputCodeUnits: 4);
      final connection = _Connection();
      addTearDown(session.dispose);
      await session.connect(
        (_, __) async => connection,
        kind: TerminalSessionKind.ssh,
      );
      for (var i = 0; i < 12; i++) {
        session.terminal.textInput('1234');
        await _events();
      }
      expect(session.isConnected, isTrue);
      expect(connection.writes, hasLength(12));
    },
  );

  test(
    'a new connection gets its own budget after pending old writes close',
    () async {
      final session = TerminalSession(maximumPendingInputCodeUnits: 8);
      final first = _Connection(block: true);
      addTearDown(session.dispose);
      await session.connect(
        (_, __) async => first,
        kind: TerminalSessionKind.ssh,
      );
      session.terminal.textInput('12345678');
      await _events();
      final second = _Connection();
      await session.connect(
        (_, __) async => second,
        kind: TerminalSessionKind.ssh,
      );
      session.terminal.textInput('abcdefgh');
      await _events();
      expect(session.isConnected, isTrue);
      expect(second.writes, ['abcdefgh']);
      session.terminal.textInput('123456789');
      expect(session.status, TerminalSessionStatus.failed);
      await _events();
      expect(second.writes, ['abcdefgh']);
    },
  );
}

Future<void> _events() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Connection implements TerminalConnection {
  _Connection({bool block = false}) : gate = block ? Completer<void>() : null;
  final Completer<void>? gate;
  final _output = StreamController<String>();
  final _exit = Completer<int?>();
  final writes = <String>[];
  bool closed = false;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  @override
  Future<void> write(String data) async {
    writes.add(data);
    await gate?.future;
  }

  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    closed = true;
    if (gate != null && !gate!.isCompleted) gate!.complete();
    if (!_exit.isCompleted) _exit.complete(null);
    if (!_output.isClosed) unawaited(_output.close());
  }
}
