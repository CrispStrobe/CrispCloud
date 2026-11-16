import 'dart:async';

import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late TerminalSession session;

  setUp(() => session = TerminalSession());
  tearDown(() => session.dispose());

  Future<_Connection> connect() async {
    final connection = _Connection();
    await session.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.local,
    );
    return connection;
  }

  test(
    'interprets cursor controls, color and alternate screen from the transport',
    () async {
      final connection = await connect();
      connection.controller.add('working…\r\x1b[2K\x1b[32mready\x1b[0m');
      await _events();
      expect(session.terminal.buffer.getText().trim(), 'ready');
      expect(session.terminal.buffer.lines[0].getForeground(0), isNot(0));

      connection.controller.add('\x1b[?1049h\x1b[2J\x1b[Hfull screen');
      await _events();
      expect(session.terminal.isUsingAltBuffer, isTrue);
      expect(session.terminal.buffer.getText().trim(), 'full screen');
      connection.controller.add('\x1b[?1049l');
      await _events();
      expect(session.terminal.buffer.getText().trim(), 'ready');
    },
  );

  test('keys and bracketed paste reach the PTY without line submission or local echo', () async {
    final connection = await connect();
    session.terminal.keyInput(TerminalKey.arrowUp);
    session.terminal.keyInput(TerminalKey.tab);
    session.terminal.keyInput(TerminalKey.keyC, ctrl: true);
    session.terminal.keyInput(TerminalKey.enter);
    connection.controller.add('\x1b[?2004h');
    await _events();
    session.terminal.paste('Grüße 中 🌍\necho done');
    await _events();
    expect(connection.writes, [
      '\x1b[A',
      '\t',
      '\x03',
      '\r',
      '\x1b[200~Grüße 中 🌍\necho done\x1b[201~',
    ]);
    expect(session.terminal.buffer.getText().trim(), isEmpty);
  });

  test('terminal answers device-attribute and cursor queries over its transport', () async {
    final connection = await connect();
    // ConPTY can wait for primary device attributes during startup. Both DA1
    // forms and cursor reports must return to the owned transport automatically.
    connection.controller.add('\x1b[c\x1b[0c\x1b[4;7H\x1b[6n');
    await _events();
    expect(connection.writes, ['\x1b[?6c', '\x1b[?6c', '\x1b[4;7R']);
  });

  test(
    'uses initial size and catches layout changes during connection',
    () async {
      session.terminal.resize(132, 43);
      final pending = Completer<TerminalConnection>();
      final connection = _Connection();
      (int, int)? initialSize;
      final starting = session.connect((columns, rows) {
        initialSize = (columns, rows);
        return pending.future;
      }, kind: TerminalSessionKind.local);
      await _events();
      expect(initialSize, (132, 43));
      session.terminal.resize(91, 27);
      pending.complete(connection);
      await starting;
      await _events();
      expect(connection.sizes.last, (91, 27));
      session.terminal.resize(100, 30);
      await _events();
      expect(connection.sizes.last, (100, 30));
    },
  );

  test(
    'resize bursts retain only the latest geometry behind an in-flight request',
    () async {
      final connection = await connect();
      await _events();
      connection.sizes.clear();
      final gate = connection.resizeGate = Completer<void>();
      session.terminal.resize(90, 25);
      await _events();
      for (var width = 91; width <= 290; width++) {
        session.terminal.resize(width, 26);
      }
      await _events();
      expect(connection.sizes, [(90, 25)]);

      connection.resizeGate = null;
      gate.complete();
      await _events();
      expect(connection.sizes, [(90, 25), (290, 26)]);
      expect(session.status, TerminalSessionStatus.connected);
    },
  );

  test('a resize reversal restores the last completed geometry', () async {
    final connection = await connect();
    session.terminal.resize(80, 24);
    await _events();
    connection.sizes.clear();
    final gate = connection.resizeGate = Completer<void>();
    session.terminal.resize(120, 40);
    await _events();
    session.terminal.resize(80, 24);
    connection.resizeGate = null;
    gate.complete();
    await _events();
    expect(connection.sizes, [(120, 40), (80, 24)]);
  });

  test('same-turn resizing sends one final size without duplicate transport calls', () async {
    final connection = await connect();
    await _events();
    connection.sizes.clear();
    session.terminal.resize(90, 25);
    session.terminal.resize(100, 30);
    session.terminal.resize(110, 35);
    await _events();
    expect(connection.sizes, [(110, 35)]);
    // xterm may suppress identical dimensions, so invoke its transport callback
    // directly to exercise repeated layout notifications as well.
    session.terminal.onResize?.call(110, 35, 0, 0);
    await _events();
    expect(connection.sizes, [(110, 35)]);
  });

  test('late resize failure cannot clear a replacement session resize', () async {
    final old = await connect();
    await _events();
    final oldGate = old.resizeGate = Completer<void>();
    session.terminal.resize(90, 25);
    await _events();
    session.terminal.resize(100, 30);
    await session.disconnect();

    final current = await connect();
    await _events();
    current.sizes.clear();
    final currentGate = current.resizeGate = Completer<void>();
    session.terminal.resize(120, 40);
    await _events();
    session.terminal.resize(132, 43);
    oldGate.completeError(StateError('old connection closed'));
    await _events();
    expect(session.status, TerminalSessionStatus.connected);
    expect(current.sizes, [(120, 40)]);
    current.resizeGate = null;
    currentGate.complete();
    await _events();
    expect(current.sizes, [(120, 40), (132, 43)]);
    expect(old.sizes, isNot(contains((100, 30))));
  });

  test('disconnect revokes a pending resize without waiting for its reply', () async {
    final connection = await connect();
    await _events();
    connection.sizes.clear();
    final gate = connection.resizeGate = Completer<void>();
    session.terminal.resize(90, 25);
    await _events();
    session.terminal.resize(100, 30);
    await session.disconnect();
    gate.complete();
    await _events();
    expect(connection.sizes, [(90, 25)]);
    expect(session.status, TerminalSessionStatus.disconnected);
    expect(connection.closeCount, 1);
  });

  test('resize errors fail the owned session and close its transport', () async {
    final connection = await connect();
    await _events();
    final gate = connection.resizeGate = Completer<void>();
    session.terminal.resize(90, 25);
    await _events();
    gate.completeError(StateError('window-change failed'));
    await _events();
    expect(session.status, TerminalSessionStatus.failed);
    expect(session.error.toString(), contains('window-change failed'));
    expect(connection.closeCount, 1);
  });

  test(
    'restart rejects a late connection and never mixes its output',
    () async {
      final pending = Completer<TerminalConnection>();
      final old = _Connection();
      final newConnection = _Connection();
      final first = session.connect(
        (_, __) => pending.future,
        kind: TerminalSessionKind.local,
      );
      await _events();
      await session.connect(
        (_, __) async => newConnection,
        kind: TerminalSessionKind.ssh,
        label: 'alice@host',
      );
      old.controller.add('old shell');
      newConnection.controller.add('new shell');
      pending.complete(old);
      await first;
      await _events();
      expect(old.closeCount, 1);
      expect(newConnection.closeCount, 0);
      expect(session.label, 'alice@host');
      expect(session.terminal.buffer.getText().trim(), 'new shell');
    },
  );

  test('disconnect during connection disposes the eventual process', () async {
    final pending = Completer<TerminalConnection>();
    final connection = _Connection();
    final starting = session.connect(
      (_, __) => pending.future,
      kind: TerminalSessionKind.local,
    );
    await _events();
    await session.disconnect();
    pending.complete(connection);
    await starting;
    expect(connection.closeCount, 1);
    expect(session.status, TerminalSessionStatus.disconnected);
  });

  test('disposal during connection cannot revive a session', () async {
    final pending = Completer<TerminalConnection>();
    final connection = _Connection();
    final starting = session.connect(
      (_, __) => pending.future,
      kind: TerminalSessionKind.local,
    );
    await _events();
    session.dispose();
    pending.complete(connection);
    await starting;
    expect(connection.closeCount, 1);
  });

  test('finished shell preserves trailing output and exit code', () async {
    final connection = await connect();
    connection.code = 7;
    connection.controller.add('last output\r\n');
    await connection.controller.close();
    await _events();
    expect(session.status, TerminalSessionStatus.exited);
    expect(session.exitCode, 7);
    expect(session.canDisconnect, isFalse);
    expect(session.terminal.buffer.getText().trim(), 'last output');
    expect(connection.closeCount, 1);
    session.terminal.keyInput(TerminalKey.enter);
    await _events();
    expect(connection.writes, isEmpty);
  });

  test(
    'disconnect can close a process after output EOF but before its exit',
    () async {
      final connection = await connect();
      connection.exitGate = Completer<int?>();
      await connection.controller.close();
      await _events();
      expect(session.status, TerminalSessionStatus.waitingForExit);
      expect(session.isConnected, isFalse);
      expect(session.canDisconnect, isTrue);
      session.terminal.keyInput(TerminalKey.enter);
      await _events();
      expect(connection.writes, isEmpty);
      await session.disconnect();
      expect(session.canDisconnect, isFalse);
      expect(connection.closeCount, 1);
      connection.exitGate!.complete(0);
      await _events();
      expect(session.status, TerminalSessionStatus.disconnected);
      expect(connection.closeCount, 1);
    },
  );

  test(
    'transport errors close the session and retain output for inspection',
    () async {
      final connection = await connect();
      connection.controller.add('before failure');
      connection.controller.addError(StateError('socket lost'));
      await _events();
      expect(session.status, TerminalSessionStatus.failed);
      expect(session.error.toString(), contains('socket lost'));
      expect(connection.closeCount, 1);
      expect(session.terminal.buffer.getText().trim(), 'before failure');
    },
  );

  test(
    'asynchronous input failure is handled rather than escaping the event loop',
    () async {
      final connection = await connect();
      connection.writeError = StateError('broken pipe');
      session.terminal.keyInput(TerminalKey.enter);
      await _events();
      expect(session.status, TerminalSessionStatus.failed);
      expect(session.error.toString(), contains('broken pipe'));
      expect(connection.closeCount, 1);
    },
  );

  test('queued input from a closed shell never reaches a new one', () async {
    final first = await connect();
    first.writeGate = Completer<void>();
    session.terminal.keyInput(TerminalKey.keyC, ctrl: true);
    await _events();
    session.terminal.paste('old input');
    await session.disconnect();
    final second = await connect();
    first.writeGate!.complete();
    session.terminal.paste('new input');
    await _events();
    expect(first.writes, ['\x03']);
    expect(second.writes, ['new input']);
  });

  test(
    'client platform is set and Windows reflow applies only to local PTYs',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await connect();
      expect(
        session.terminal.platform,
        kIsWeb ? TerminalTargetPlatform.web : TerminalTargetPlatform.windows,
      );
      expect(session.terminal.windowsPtyMode, !kIsWeb);
      final remote = _Connection();
      await session.connect(
        (_, __) async => remote,
        kind: TerminalSessionKind.ssh,
      );
      expect(session.terminal.windowsPtyMode, isFalse);
    },
  );

  test('scrollback remains bounded for long-running jobs', () async {
    final connection = await connect();
    connection.controller.add(List.generate(10020, (i) => '$i\r\n').join());
    await _events();
    expect(session.terminal.buffer.height, lessThanOrEqualTo(10000));
    expect(session.terminal.buffer.getText(), contains('10019'));
  });
}

Future<void> _events() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Connection implements TerminalConnection {
  final controller = StreamController<String>();
  final writes = <String>[];
  final sizes = <(int, int)>[];
  int closeCount = 0;
  int? code = 0;
  Object? writeError;
  Completer<void>? writeGate;
  Completer<void>? resizeGate;
  Completer<int?>? exitGate;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode async =>
      exitGate == null ? code : await exitGate!.future;
  @override
  Future<void> write(String data) async {
    if (writeError case final error?) throw error;
    writes.add(data);
    await writeGate?.future;
  }

  @override
  Future<void> resize(int columns, int rows) async {
    sizes.add((columns, rows));
    await resizeGate?.future;
  }
  @override
  Future<void> close() async {
    closeCount++;
    unawaited(controller.close());
  }
}
