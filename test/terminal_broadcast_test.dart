import 'dart:async';

import 'package:crisp_cloud/services/terminal_broadcast.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/services/terminal_user_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late List<TerminalSession> sessions;
  late List<_Connection> connections;
  late TerminalBroadcast broadcast;
  late Object active;
  late bool allowed;

  Future<void> addSession() async {
    final session = TerminalSession();
    final connection = _Connection();
    sessions.add(session);
    connections.add(connection);
    await session.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
    );
  }

  TerminalBroadcastTarget target(int index) => TerminalBroadcastTarget(
    id: index,
    label: 'Terminal ${index + 1}',
    session: sessions[index],
  );

  setUp(() async {
    sessions = [];
    connections = [];
    active = 0;
    allowed = true;
    broadcast = TerminalBroadcast(canSend: (id) => allowed && id == active);
    for (var i = 0; i < 3; i++) {
      await addSession();
    }
  });

  tearDown(() async {
    broadcast.dispose();
    for (final connection in connections) {
      if (connection.writeGate != null && !connection.writeGate!.isCompleted) {
        connection.writeGate!.complete();
      }
    }
    for (final session in sessions) {
      session.dispose();
    }
    await _events();
  });

  test('mirrors explicit input once and re-encodes recipient terminal modes', () async {
    sessions[1].terminal.write('\x1b[?2004h\x1b[?1h');
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.textInput('hello');
    sessions[0].terminal.paste('one\ntwo');
    sessions[0].terminal.keyInput(TerminalKey.arrowUp);
    await _events();
    expect(connections[0].writes, ['hello', 'one\rtwo', '\x1b[A']);
    expect(connections[1].writes, ['hello', '\x1b[200~one\ntwo\x1b[201~', '\x1bOA']);
    expect(connections[2].writes, isEmpty);
  });

  test('active-pane and focus predicates exclude other input surfaces', () async {
    expect(broadcast.start([target(0), target(1)]), isTrue);
    allowed = false;
    sessions[0].terminal.textInput('no focus');
    allowed = true;
    active = 1;
    sessions[0].terminal.textInput('inactive pane');
    sessions[1].terminal.textInput('active pane');
    await _events();
    expect(connections[0].writes, ['no focus', 'inactive pane', 'active pane']);
    expect(connections[1].writes, ['active pane']);
    expect(broadcast.isArmed, isTrue);
  });

  test('device replies, mouse and focus reports never mirror', () async {
    var observed = 0;
    sessions[0].onUserInput = (_) => observed++;
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.write('\x1b[c\x1b[6n\x1b[?1004h');
    sessions[0].terminal.focusInput(false);
    sessions[0].terminal.onOutput!.call('\x1b[<0;1;1M');
    await _events();
    expect(observed, 0);
    expect(connections[0].writes, isNotEmpty);
    expect(connections[1].writes, isEmpty);
    expect(connections[2].writes, isEmpty);
  });

  test('disconnection disarms every member and stale snapshots cannot rearm', () async {
    final old = target(1);
    expect(broadcast.start([target(0), old]), isTrue);
    await sessions[1].disconnect();
    expect(broadcast.isArmed, isFalse);
    expect(broadcast.lastStopReason, TerminalBroadcastStopReason.connectionChanged);
    expect(sessions.every((session) => session.onUserInput == null), isTrue);
    final replacement = _Connection();
    connections.add(replacement);
    await sessions[1].connect((_, __) async => replacement, kind: TerminalSessionKind.ssh);
    expect(broadcast.start([target(0), old]), isFalse);
    sessions[0].terminal.textInput('not inherited');
    await _events();
    expect(replacement.writes, isEmpty);
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.textInput('explicitly rearmed');
    await _events();
    expect(replacement.writes, ['explicitly rearmed']);
  });

  test('reconnecting any selected member stops a pending group immediately', () async {
    expect(broadcast.start([target(0), target(1), target(2)]), isTrue);
    final opening = Completer<TerminalConnection>();
    final pending = sessions[2].connect((_, __) => opening.future, kind: TerminalSessionKind.ssh);
    expect(broadcast.isArmed, isFalse);
    sessions[0].terminal.textInput('single terminal');
    await _events();
    expect(connections[1].writes, isEmpty);
    final replacement = _Connection();
    connections.add(replacement);
    opening.complete(replacement);
    await pending;
  });

  test('oversized input remains on its source and disarms before mirroring', () async {
    expect(broadcast.start([target(0), target(1)]), isTrue);
    final input = 'x' * (TerminalBroadcast.maximumInputLength + 1);
    sessions[0].terminal.textInput(input);
    await _events();
    expect(connections[0].writes.single, input);
    expect(connections[1].writes, isEmpty);
    expect(broadcast.isArmed, isFalse);
    expect(broadcast.lastStopReason, TerminalBroadcastStopReason.inputTooLarge);
  });

  test('stop revokes already queued recipient input before transport delivery', () async {
    connections[1].writeGate = Completer<void>();
    sessions[1].terminal.textInput('already sending');
    await _events();
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.textInput('queued broadcast');
    broadcast.stop();
    connections[1].writeGate!.complete();
    await _events();
    expect(connections[0].writes, ['queued broadcast']);
    expect(connections[1].writes, ['already sending']);
  });

  test('rearm uses a new lease and never revives old queued delivery', () async {
    connections[1].writeGate = Completer<void>();
    sessions[1].terminal.textInput('already sending');
    await _events();
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.textInput('old group input');
    broadcast.stop(reason: TerminalBroadcastStopReason.workspaceHidden);
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.textInput('new group input');
    connections[1].writeGate!.complete();
    await _events();
    expect(connections[1].writes, ['already sending', 'new group input']);
  });

  test('preserves prior callbacks and does not overwrite a later owner', () async {
    var firstEvents = 0;
    var secondEvents = 0;
    void firstHandler(TerminalUserInput _) => firstEvents++;
    void secondHandler(TerminalUserInput _) => secondEvents++;
    sessions[0].onUserInput = firstHandler;
    sessions[1].onUserInput = secondHandler;
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[0].terminal.textInput('a');
    await _events();
    expect(firstEvents, 1);
    expect(secondEvents, 0); // Replaying input does not recurse into observers.
    broadcast.stop();
    expect(sessions[0].onUserInput, same(firstHandler));
    expect(sessions[1].onUserInput, same(secondHandler));
    expect(broadcast.start([target(0), target(1)]), isTrue);
    void laterOwner(TerminalUserInput _) {}
    sessions[0].onUserInput = laterOwner;
    broadcast.stop();
    expect(sessions[0].onUserInput, same(laterOwner));
    expect(sessions[1].onUserInput, same(secondHandler));
  });

  test('unselected and newly created tabs never inherit membership', () async {
    expect(broadcast.start([target(0), target(1)]), isTrue);
    await addSession();
    active = 3;
    sessions[3].terminal.textInput('new tab only');
    await _events();
    expect(connections[0].writes, isEmpty);
    expect(connections[1].writes, isEmpty);
    expect(connections[3].writes, ['new tab only']);
    expect(broadcast.targets, hasLength(2));
    expect(broadcast.includes(3), isFalse);
  });

  test('bounds groups and rejects duplicates without installing callbacks', () async {
    expect(broadcast.start([target(0)]), isFalse);
    expect(broadcast.start([target(0), target(0)]), isFalse);
    expect(broadcast.start([
      target(0),
      TerminalBroadcastTarget(id: 'alias', label: 'Alias', session: sessions[0]),
    ]), isFalse);
    expect(sessions.every((session) => session.onUserInput == null), isTrue);
    while (sessions.length < 9) {
      await addSession();
    }
    expect(broadcast.start([for (var i = 0; i < 9; i++) target(i)]), isFalse);
    expect(broadcast.start([for (var i = 0; i < 8; i++) target(i)]), isTrue);
    sessions[0].terminal.textInput('eight');
    await _events();
    for (var i = 0; i < 8; i++) {
      expect(connections[i].writes, ['eight']);
    }
    expect(connections[8].writes, isEmpty);
  });

  test('a disposed external member invalidates the group before new input', () async {
    expect(broadcast.start([target(0), target(1)]), isTrue);
    sessions[1].dispose();
    sessions[0].terminal.textInput('source only');
    await _events();
    expect(broadcast.isArmed, isFalse);
    expect(connections[1].writes, isEmpty);
  });
}

Future<void> _events() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Connection implements TerminalConnection {
  final _output = StreamController<String>(onCancel: () async {});
  final _exit = Completer<int?>();
  final writes = <String>[];
  Completer<void>? writeGate;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => _output.stream;
  @override
  Future<int?> get exitCode => _exit.future;
  @override
  Future<void> write(String data) async {
    writes.add(data);
    await writeGate?.future;
  }
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (!_exit.isCompleted) _exit.complete(0);
    if (!_output.isClosed) unawaited(_output.close());
  }
}
