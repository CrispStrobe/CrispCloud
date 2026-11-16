import 'dart:async';

import 'package:crisp_cloud/models/terminal_trigger.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

TerminalTrigger _trigger({
  TerminalTriggerAction action = TerminalTriggerAction.mark,
  bool once = false,
}) => TerminalTrigger(
  id: 'build',
  name: 'Build result',
  pattern: 'ready',
  action: action,
  cooldownSeconds: 0,
  oncePerSession: once,
);

class _Connection implements TerminalConnection {
  final controller = StreamController<String>();
  final exit = Completer<int?>();
  final writes = <String>[];
  bool closed = false;
  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => controller.stream;
  @override
  Future<int?> get exitCode => exit.future;
  @override
  Future<void> write(String data) async => writes.add(data);
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!exit.isCompleted) exit.complete(0);
    unawaited(controller.close());
  }
}

Future<void> _events() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late TerminalSession session;
  late _Connection connection;

  setUp(() async {
    session = TerminalSession();
    connection = _Connection();
    session.terminal.resize(80, 24);
    await session.connect(
      (_, __) async => connection,
      kind: TerminalSessionKind.ssh,
    );
  });
  tearDown(() async {
    await session.disconnect();
    session.dispose();
  });

  test(
    'marks each matched line within one output chunk without input',
    () async {
      session.updateTriggers([_trigger()]);
      connection.controller.add('ready one\r\nignore\r\nready two\r\n');
      await _events();
      final marks = session.shellIntegration.marks;
      expect(marks.map((mark) => mark.anchor.y), [0, 2]);
      expect(marks.every((mark) => mark.manual), isTrue);
      expect(connection.writes, isEmpty);
      expect(session.terminal.buffer.getText(), contains('ready two'));
    },
  );

  test(
    'fragmented UTF-16, escapes and line terminators retain mark locations',
    () async {
      session.updateTriggers([_trigger()]);
      for (final fragment in [
        '\x1b[3',
        '2mrea',
        'dy 中 ',
        '\ud83c',
        '\udf0d',
        '\x1b[0m\r',
        '\n',
        'ready again',
        '\n',
      ]) {
        connection.controller.add(fragment);
      }
      await _events();
      expect(session.shellIntegration.marks.map((mark) => mark.anchor.y), [
        0,
        1,
      ]);
      expect(connection.writes, isEmpty);
    },
  );

  test(
    'alternate-screen and OSC contents cannot create marks or alerts',
    () async {
      session.updateTriggers([
        _trigger(),
        TerminalTrigger(
          id: 'hidden',
          name: 'Hidden output',
          pattern: 'hidden',
          action: TerminalTriggerAction.notify,
          cooldownSeconds: 0,
        ),
      ]);
      connection.controller.add(
        '\x1b]0;ready\nnot output\x07'
        '\x1b[?1049hready hidden\r\n\x1b[?1049lready visible\r\n',
      );
      await _events();
      expect(session.shellIntegration.marks, hasLength(1));
      expect(session.shellIntegration.marks.single.anchor.y, 0);
      expect(session.triggerNotificationSerial, 0);
    },
  );

  test(
    'notifications do not write, repeat on rebuild, or survive reconnect',
    () async {
      final rule = _trigger(action: TerminalTriggerAction.notify, once: true);
      session.updateTriggers([rule]);
      connection.controller.add('ready first\n');
      await _events();
      expect(session.triggerNotificationSerial, 1);
      expect(session.triggerNotification!.line, 'ready first');
      session.updateTriggers([rule]);
      connection.controller.add('ready repeated\n');
      await _events();
      expect(session.triggerNotificationSerial, 1);
      expect(connection.writes, isEmpty);
      final next = _Connection();
      await session.connect(
        (_, __) async => next,
        kind: TerminalSessionKind.ssh,
      );
      expect(connection.closed, isTrue);
      expect(session.triggerNotification, isNull);
      expect(session.triggerNotificationSerial, 0);
      next.controller.add('ready new connection\n');
      await _events();
      expect(session.triggerNotificationSerial, 1);
      expect(session.triggerNotification!.line, 'ready new connection');
      expect(next.writes, isEmpty);
    },
  );

  test('natural EOF evaluates final partial output once', () async {
    session.updateTriggers([_trigger(action: TerminalTriggerAction.notify)]);
    connection.controller.add('ready final');
    await connection.controller.close();
    await _events();
    expect(session.triggerNotificationSerial, 1);
    expect(session.triggerNotification!.line, 'ready final');
    expect(session.status, TerminalSessionStatus.waitingForExit);
  });

  test('disconnect discards unfinished lines and late output', () async {
    session.updateTriggers([_trigger(action: TerminalTriggerAction.notify)]);
    connection.controller.add('ready unfinished');
    await _events();
    await session.disconnect();
    expect(session.triggerNotificationSerial, 0);
    final next = _Connection();
    await session.connect((_, __) async => next, kind: TerminalSessionKind.ssh);
    next.controller.add(' tail\n');
    await _events();
    expect(session.triggerNotificationSerial, 0);
  });

  test('disabled rules never act on terminal output', () async {
    session.updateTriggers([_trigger().copyWith(enabled: false)]);
    connection.controller.add('ready\n');
    await _events();
    expect(session.shellIntegration.marks, isEmpty);
    expect(session.triggerNotificationSerial, 0);
  });
}
