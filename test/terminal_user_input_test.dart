import 'dart:async';

import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/terminal_user_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late TerminalSession session;
  late _Connection connection;

  setUp(() async {
    session = TerminalSession();
    connection = _Connection();
    await session.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
    );
  });

  tearDown(() async {
    session.dispose();
    await _events();
  });

  test('only explicit input produces user events; terminal replies stay local', () async {
    final inputs = <TerminalUserInput>[];
    session.onUserInput = inputs.add;
    connection.outputController.add('\x1b[c\x1b[0c\x1b[4;7H\x1b[6n');
    await _events();
    // Focus and mouse reports also go directly to onOutput.
    session.terminal.onOutput?.call('\x1b[I');
    session.terminal.onOutput?.call('\x1b[<0;3;4M');
    expect(inputs, isEmpty);

    session.terminal.textInput('中🙂');
    session.terminal.keyInput(TerminalKey.enter);
    session.terminal.charInput(99, ctrl: true);
    session.terminal.paste('one\ntwo');
    await _events();

    expect(inputs, hasLength(4));
    expect(connection.writes, containsAllInOrder([
      '\x1b[?6c',
      '\x1b[?6c',
      '\x1b[4;7R',
      '\x1b[I',
      '\x1b[<0;3;4M',
      '中🙂',
      '\r',
      '\x03',
      'one\rtwo',
    ]));
  });

  test('replayed paste uses recipient bracketed-paste mode without recursion', () async {
    final inputs = <TerminalUserInput>[];
    session.onUserInput = inputs.add;
    connection.outputController.add('\x1b[?2004h');
    await _events();
    session.sendUserInput(TerminalUserInput.paste('one\ntwo'));
    await _events();
    expect(connection.writes, ['\x1b[200~one\ntwo\x1b[201~']);
    expect(inputs, isEmpty);
  });

  test('replayed key uses recipient application cursor mode', () async {
    connection.outputController.add('\x1b[?1h');
    await _events();
    session.sendUserInput(TerminalUserInput.key(TerminalKey.arrowUp));
    await _events();
    expect(connection.writes, ['\x1bOA']);
  });

  test('revoked broadcast lease drops input already waiting in the write queue', () async {
    connection.writeGate = Completer<void>();
    session.terminal.textInput('first');
    await _events();
    var current = true;
    session.sendUserInput(
      TerminalUserInput.text('stale'),
      isCurrent: () => current,
    );
    current = false;
    connection.writeGate!.complete();
    await _events();
    expect(connection.writes, ['first']);
  });

  test('locked or disconnected input is not broadcast', () async {
    final inputs = <TerminalUserInput>[];
    session.onUserInput = inputs.add;
    connection.outputController.add('\x1b[2h');
    await _events();
    session.terminal.textInput('locked');
    session.terminal.keyInput(TerminalKey.enter);
    session.terminal.charInput(99, ctrl: true);
    session.terminal.paste('locked paste');
    await _events();
    expect(inputs, isEmpty);
    expect(connection.writes, isEmpty);

    await session.disconnect();
    session.sendUserInput(TerminalUserInput.text('disconnected'));
    session.terminal.textInput('disconnected');
    await _events();
    expect(inputs, isEmpty);
    expect(connection.writes, isEmpty);
  });

  test('reconnect replaces the input identity and command history', () async {
    final original = session.connectionIdentity;
    connection.outputController.add(
      '\x1b]133;A\x07\$ \x1b]133;B\x07echo first\r\n'
      '\x1b]133;C\x07first\r\n\x1b]133;D;0\x07',
    );
    await _events();
    expect(session.shellIntegration.commands, hasLength(1));
    final replacement = _Connection();
    await session.connect(
      (_, __) async => replacement,
      kind: TerminalSessionKind.ssh,
    );
    expect(identical(session.connectionIdentity, original), isFalse);
    expect(session.shellIntegration.commands, isEmpty);
    expect(connection.closes, 1);
  });

  test('failed transport stays owned until asynchronous cleanup settles', () async {
    connection.closeGate = Completer<void>();
    connection.outputController.addError(StateError('transport failed'));
    await _events();
    expect(session.status, TerminalSessionStatus.failed);
    expect(session.canDisconnect, isTrue);
    expect(connection.closes, 1);
    connection.closeGate!.complete();
    await _events();
    expect(session.canDisconnect, isFalse);
  });

  test('replacement waits for pending failed-transport cleanup', () async {
    connection.closeGate = Completer<void>();
    connection.outputController.addError(StateError('transport failed'));
    await _events();
    var opened = false;
    final replacement = _Connection();
    final replacing = session.connect((_, __) async {
      opened = true;
      return replacement;
    }, kind: TerminalSessionKind.ssh);
    await _events();
    expect(opened, isFalse);
    expect(session.isConnecting, isTrue);
    connection.closeGate!.complete();
    await replacing;
    expect(opened, isTrue);
    expect(session.isConnected, isTrue);
    expect(connection.closes, 1);
  });

  test('cancelled late opener stays owned while its close is pending', () async {
    await session.disconnect();
    final pending = Completer<TerminalConnection>();
    final lateConnection = _Connection()..closeGate = Completer<void>();
    final opening = session.connect(
      (_, __) => pending.future,
      kind: TerminalSessionKind.ssh,
    );
    await _events();
    await session.disconnect();
    expect(session.canDisconnect, isTrue);
    pending.complete(lateConnection);
    await _events();
    expect(lateConnection.closes, 1);
    expect(session.canDisconnect, isTrue);
    lateConnection.closeGate!.complete();
    await opening;
    expect(session.canDisconnect, isFalse);
    expect(session.status, TerminalSessionStatus.disconnected);
  });

  test('input origin can be consumed only once per explicit operation', () {
    final terminal = InputAwareTerminal();
    final inputs = <TerminalUserInput>[];
    terminal.onOutput = (_) {
      final first = terminal.takeUserInput();
      if (first != null) inputs.add(first);
      expect(terminal.takeUserInput(), isNull);
    };
    terminal.textInput('hello');
    terminal.paste('world');
    expect(inputs, hasLength(2));
    expect(terminal.takeUserInput(), isNull);
    terminal.dispose();
  });
}

Future<void> _events() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Connection implements TerminalConnection {
  final outputController = StreamController<String>();
  final writes = <String>[];
  Completer<void>? writeGate;
  Completer<void>? closeGate;
  int closes = 0;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => outputController.stream;
  @override
  Future<int?> get exitCode async => 0;
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> write(String data) async {
    writes.add(data);
    await writeGate?.future;
  }
  @override
  Future<void> close() async {
    closes++;
    await closeGate?.future;
    unawaited(outputController.close());
  }
}
