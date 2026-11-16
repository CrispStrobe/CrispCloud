import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/services/tmux_control_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late _Server server;
  late TmuxControlClient client;

  setUp(() {
    server = _Server();
    client = server.client();
  });
  tearDown(() async {
    await client.close();
    client.dispose();
  });

  test(
    'starts after the unsolicited guard and maps native panes and geometry',
    () async {
      server.addSplit();
      await server.start(client);
      expect(client.ready, isTrue);
      expect(client.windows.single.id, '@0');
      expect(client.windows.single.paneIds, ['%0', '%1']);
      expect(client.activeWindowId, '@0');
      expect(client.activePaneId, '%0');
      expect(client.panes['%1']!.x, 41);
      expect(client.panes['%1']!.width, 39);
      expect(client.panes['%0']!.session.terminal.viewWidth, 40);
      expect(
        client.panes['%0']!.session.terminal.buffer.getText(),
        contains('captured %0'),
      );
      expect(
        client.panes['%1']!.session.terminal.buffer.getText(),
        contains('captured %1'),
      );
      expect(server.commands.first, "display-message -p '#{version}'");
      expect(
        server.commands.where((command) => command.contains('capture-pane')),
        hasLength(6),
      );
    },
  );

  test(
    'snapshot publishes before output in the same transport chunk',
    () async {
      server.afterCapture = ' + fresh';
      await server.start(client);
      expect(
        client.panes['%0']!.session.terminal.buffer.getText().trim(),
        'captured %0 + fresh',
      );
    },
  );

  test('UTF-8 split between records is independent for every pane', () async {
    server.addSplit();
    await server.start(client);
    server.paneOutput('%0', [0xf0, 0x9f]);
    server.paneOutput('%1', utf8.encode(' second 中 '));
    server.paneOutput('%0', [0x8c, 0x8d]);
    expect(
      client.panes['%0']!.session.terminal.buffer.getText(),
      contains('captured %0🌍'),
    );
    expect(
      client.panes['%1']!.session.terminal.buffer.getText(),
      contains('captured %1 second 中 '),
    );
    expect(
      client.panes['%0']!.session.terminal.buffer.getText(),
      isNot(contains('�')),
    );
  });

  test('control-looking captured lines stay screen content', () async {
    server.captureText = '%output %9 fake\n%begin 1 2 1\n%end 1 3 1';
    server.cursorY = 2;
    server.cursorX = 10;
    await server.start(client);
    expect(client.panes, hasLength(1));
    expect(
      client.panes['%0']!.session.terminal.buffer.getText(),
      contains('%output %9 fake'),
    );
    expect(
      client.panes['%0']!.session.terminal.buffer.getText(),
      contains('%end 1 3 1'),
    );
  });

  test(
    'explicit input is hex encoded while emulator replies are suppressed',
    () async {
      await server.start(client);
      final terminal = client.panes['%0']!.session.terminal;
      server.paneOutput('%0', utf8.encode('\x1b[c\x1b[6n\x1b[?2004h'));
      await _events();
      expect(
        server.commands.where((command) => command.startsWith('send-keys')),
        isEmpty,
      );
      terminal.paste('Grüße; kill-server\n#{}');
      await _events();
      final input = server.inputBytes;
      expect(utf8.decode(input), '\x1b[200~Grüße; kill-server\n#{}\x1b[201~');
      final sent = server.commands.lastWhere(
        (command) => command.startsWith('send-keys'),
      );
      expect(sent, matches(RegExp(r'^send-keys -H -t %0 (?:[0-9a-f]{2} ?)+$')));
      expect(server.commands, isNot(contains('kill-server')));
    },
  );

  test('captured cursor and keyboard modes govern the first input', () async {
    server.cursorMode = true;
    server.bracketMode = true;
    await server.start(client);
    final terminal = client.panes['%0']!.session.terminal;
    terminal.keyInput(TerminalKey.arrowUp);
    terminal.paste('hello');
    await _events();
    expect(utf8.decode(server.inputBytes), '\x1bOA\x1b[200~hello\x1b[201~');
    server.paneOutput('%0', ascii.encode('x'));
    expect(terminal.buffer.getText().trim(), 'captured %0x');
  });

  test(
    'attaching in the alternate screen preserves the saved primary screen',
    () async {
      server.alternate = true;
      server.captureText = 'editor buffer';
      server.savedCaptureText = 'shell before editor';
      await server.start(client);
      final terminal = client.panes['%0']!.session.terminal;
      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.buffer.getText().trim(), 'editor buffer');
      server.paneOutput('%0', ascii.encode('\x1b[?1049l'));
      expect(terminal.isUsingAltBuffer, isFalse);
      expect(terminal.buffer.getText().trim(), 'shell before editor');
    },
  );

  test(
    'a parser sequence pending at capture is completed by live output',
    () async {
      server.pendingBytes = r'\033[32';
      await server.start(client);
      server.paneOutput('%0', ascii.encode('mgreen\x1b[0m'));
      final terminal = client.panes['%0']!.session.terminal;
      expect(terminal.buffer.getText().trim(), 'captured %0green');
      expect(terminal.buffer.lines[0].getForeground(11), isNot(0));
    },
  );

  test(
    'select, split and create use validated IDs and update server topology',
    () async {
      await server.start(client);
      final original = client.panes['%0']!.session;
      await client.splitPane('%0', horizontal: true);
      expect(client.panes, hasLength(2));
      expect(client.panes['%0']!.session, same(original));
      await client.selectPane('%1');
      expect(client.activePaneId, '%1');
      await client.newWindow();
      expect(client.windows, hasLength(2));
      expect(client.activeWindowId, '@1');
      await client.selectWindow('@0');
      expect(client.activeWindowId, '@0');
      expect(client.activePaneId, '%1');
      await expectLater(
        client.selectPane('%0 ; kill-server'),
        throwsArgumentError,
      );
      await expectLater(client.selectWindow('@900'), throwsArgumentError);
      expect(
        server.commands.any((command) => command.contains('kill-')),
        isFalse,
      );
    },
  );

  test(
    'external topology change reconciles without recreating retained panes',
    () async {
      await server.start(client);
      final first = client.panes['%0']!.session;
      server.addSplit();
      server.notification('%layout-change @0 ignored-layout-format');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(client.panes, hasLength(2));
      expect(client.panes['%0']!.session, same(first));
      server.panes.removeLast();
      server.panes.first.width = 80;
      server.notification('%layout-change @0 ignored-layout-format');
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(client.panes.keys, ['%0']);
      expect(first.isConnected, isTrue);
    },
  );

  test(
    'capture retains literal backslashes and restored cell colors',
    () async {
      server.captureText = r'\033[31mC:\\tmp\\033\033[0m';
      server.cursorX = 10;
      await server.start(client);
      final terminal = client.panes['%0']!.session.terminal;
      expect(terminal.buffer.getText().trim(), r'C:\tmp\033');
      expect(terminal.buffer.lines[0].getForeground(0), isNot(0));
    },
  );

  test(
    'input queue admission revokes remaining chunks after a stalled reply',
    () async {
      await server.start(client);
      final session = client.panes['%0']!.session;
      server.holdPrefix = 'send-keys';
      session.terminal.textInput('a' * 5000);
      await _events();
      expect(
        server.commands.where((command) => command.startsWith('send-keys')),
        hasLength(1),
      );
      session.terminal.textInput('b' * 12000);
      expect(session.isConnected, isFalse);
      expect(session.error.toString(), contains('Pending terminal input'));
      server.replyToHeld();
      await _events();
      expect(
        server.commands.where((command) => command.startsWith('send-keys')),
        hasLength(1),
      );
      expect(client.ready, isTrue);
    },
  );

  test(
    'early cleanup errors are observed while source cancellation is pending',
    () async {
      await server.start(client);
      server.cancelGate = Completer<void>();
      server.failClose = true;
      final closing = client.close();
      final expected = expectLater(closing, throwsStateError);
      await _events();
      server.cancelGate!.complete();
      await expected;
      expect(client.error.toString(), contains('cleanup failure'));
      server.failClose = false;
      await client.close();
      expect(server.closeCount, 2);
    },
  );

  test(
    'hook guards cannot consume the pending user command response',
    () async {
      await server.start(client);
      server.injectHook = true;
      await client.selectWindow('@0');
      expect(client.ready, isTrue);
      expect(client.activeWindowId, '@0');
    },
  );

  test('resize coalesces rapid changes and uses client size policy', () async {
    await server.start(client);
    final a = client.resize(100, 30);
    final b = client.resize(120, 36);
    final c = client.resize(140, 42);
    await Future.wait([a, b, c]);
    final resizes = server.commands
        .where((command) => command.startsWith('refresh-client -C'))
        .toList();
    expect(resizes, ['refresh-client -C 80x24', 'refresh-client -C 140x42']);
    expect(client.windows.single.width, 140);
    expect(client.panes['%0']!.session.terminal.viewWidth, 140);
  });

  test('close revokes queued input and keeps read-only pane buffers', () async {
    await server.start(client);
    final session = client.panes['%0']!.session;
    session.terminal.textInput('should be canceled');
    final closing = client.close();
    session.terminal.textInput('late');
    await closing;
    await _events();
    expect(server.closeCount, 1);
    expect(server.inputBytes, isEmpty);
    expect(client.isClosed, isTrue);
    expect(session.terminal.buffer.getText(), contains('captured %0'));
    expect(session.isConnected, isFalse);
    await client.close();
    expect(server.closeCount, 1);
  });

  test(
    'detach sends only the client detach command and preserves remote panes',
    () async {
      await server.start(client);
      await client.detach();
      expect(server.commands.last, 'detach-client');
      expect(server.panes, hasLength(1));
      expect(
        server.commands.any((command) => command.contains('kill-')),
        isFalse,
      );
      expect(await client.done, 0);
    },
  );

  test(
    'unsupported tmux version and malformed metadata fail before publication',
    () async {
      server.version = '3.1c';
      await expectLater(
        server.start(client),
        throwsA(isA<TmuxControlException>()),
      );
      expect(client.ready, isFalse);
      expect(client.panes, isEmpty);
      expect(server.closeCount, 1);
    },
  );

  test(
    'duplicate IDs, overlapping geometry and excessive sizes fail closed',
    () async {
      server.addSplit();
      server.panes.last.x = 0;
      await expectLater(server.start(client), throwsA(isA<Exception>()));
      expect(client.ready, isFalse);
      expect(server.closeCount, 1);
    },
  );

  test('startup cancellation owns late protocol events and does not resurrect panes', () async {
    final starting = client.start();
    final expected = expectLater(
      starting,
      throwsA(isA<TmuxControlException>()),
    );
    await client.close();
    await expected;
    expect(client.panes, isEmpty);
    expect(server.closeCount, 1);
  });

  test(
    'a timed out command closes the stream instead of reusing late replies',
    () async {
      await client.close();
      client.dispose();
      server = _Server();
      client = server.client(commandTimeout: const Duration(milliseconds: 50));
      await server.start(client);
      server.holdPrefix = 'select-window';
      await expectLater(
        client.selectWindow('@0'),
        throwsA(isA<TmuxControlException>()),
      );
      expect(client.isClosed, isTrue);
      expect(server.closeCount, 1);
    },
  );

  test(
    'unknown unbounded output is not retained before pane discovery',
    () async {
      await server.start(client);
      for (var i = 0; i < 100; i++) {
        server.paneOutput('%999', List.filled(2048, 120));
      }
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(client.ready, isTrue);
      expect(client.panes.keys, ['%0']);
      expect(
        client.panes['%0']!.session.terminal.buffer.getText(),
        isNot(contains('xxxx')),
      );
    },
  );

  test(
    'a failed multi-command capture aborts before any later response is reused',
    () async {
      server.failPrefix = 'capture-pane';
      await expectLater(
        server.start(client),
        throwsA(isA<TmuxControlException>()),
      );
      expect(client.ready, isFalse);
      expect(client.isClosed, isTrue);
      expect(server.closeCount, 1);
    },
  );

  test(
    'natural EOF with a partial guard is a visible protocol failure',
    () async {
      await server.start(client);
      server.output.add(ascii.encode('%begin 10 20 1\ntruncated'));
      server.exit.complete(7);
      await server.output.close();
      await client.done;
      expect(client.error.toString(), contains('ended early'));
      expect(client.isClosed, isTrue);
    },
  );
}

Future<void> _events() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Pane {
  _Pane(
    this.id,
    this.windowId, {
    this.width = 80,
    this.x = 0,
    this.active = true,
  });
  final String id;
  final String windowId;
  int width, x;
  int height = 24, y = 0;
  bool active;
}

class _Server {
  _Server() {
    output = StreamController<List<int>>(
      sync: true,
      onCancel: () => cancelGate?.future,
    );
  }
  late final StreamController<List<int>> output;
  final exit = Completer<int?>();
  final commands = <String>[];
  final inputBytes = <int>[];
  final panes = [_Pane('%0', '@0')];
  String activeWindow = '@0';
  String version = '3.3a';
  String? holdPrefix,
      failPrefix,
      captureText,
      afterCapture,
      savedCaptureText,
      pendingBytes;
  int cursorX = 11, cursorY = 0;
  bool cursorMode = false, bracketMode = false;
  bool alternate = false;
  int serial = 100;
  int closeCount = 0;
  Completer<void>? cancelGate;
  bool failClose = false, injectHook = false;
  int? heldSerial;

  TmuxControlClient client({
    Duration commandTimeout = const Duration(seconds: 3),
  }) => TmuxControlClient(
    output: output.stream,
    write: write,
    close: close,
    exitCode: exit.future,
    commandTimeout: commandTimeout,
  );
  Future<void> start(TmuxControlClient client) async {
    final starting = client.start();
    output.add(
      ascii.encode('%begin 1 99 0\n%end 1 99 0\n%session-changed \$0 work\n'),
    );
    await starting;
  }

  void addSplit() {
    panes.first.width = 40;
    panes.add(_Pane('%1', '@0', width: 39, x: 41, active: false));
  }

  void notification(String record) {
    if (!output.isClosed) output.add(utf8.encode('$record\n'));
  }

  void paneOutput(String id, List<int> bytes) {
    final escaped = <int>[];
    for (final byte in bytes) {
      if (byte < 32 || byte == 92) {
        escaped.addAll(
          ascii.encode('\\${byte.toRadixString(8).padLeft(3, '0')}'),
        );
      } else {
        escaped.add(byte);
      }
    }
    if (!output.isClosed) {
      output.add([...ascii.encode('%output $id '), ...escaped, 10]);
    }
  }

  Future<void> close() async {
    closeCount++;
    if (failClose) throw StateError('cleanup failure');
    if (!exit.isCompleted) exit.complete(0);
    if (!output.isClosed) unawaited(output.close());
  }

  Future<void> write(String value) async {
    for (final command in value.trimRight().split(' ; ')) {
      if (output.isClosed) return;
      commands.add(command);
      final number = ++serial;
      if (holdPrefix != null && command.startsWith(holdPrefix!)) {
        heldSerial = number;
        return;
      }
      var body = <String>[];
      var failure = false;
      if (failPrefix != null && command.startsWith(failPrefix!)) {
        body = ['forced failure'];
        failure = true;
      } else if (command == "display-message -p '#{version}'") {
        body = [version];
      } else if (command.startsWith('list-windows')) {
        body = panes.map((pane) => pane.windowId).toSet().map((id) {
          final children = panes.where((pane) => pane.windowId == id);
          final active = children.firstWhere((pane) => pane.active);
          final width = children
              .map((pane) => pane.x + pane.width)
              .reduce((a, b) => a > b ? a : b);
          final height = children
              .map((pane) => pane.y + pane.height)
              .reduce((a, b) => a > b ? a : b);
          return '$id ${id.substring(1)} $width $height ${id == activeWindow ? 1 : 0} ${active.id} 0 window ${id.substring(1)}';
        }).toList();
      } else if (command.startsWith('list-panes')) {
        body = panes
            .map(
              (pane) =>
                  '${pane.windowId} ${pane.id} ${pane.width} ${pane.height} ${pane.x} ${pane.y} ${pane.active ? 1 : 0}',
            )
            .toList();
      } else if (command.startsWith('capture-pane')) {
        final id = RegExp(r'-t (%\d+)').firstMatch(command)![1]!;
        final pane = panes.firstWhere((pane) => pane.id == id);
        if (command.contains(' -P ')) {
          body = pendingBytes == null ? [] : [pendingBytes!];
        } else if (command.contains(' -a ')) {
          body = alternate ? (savedCaptureText ?? '').split('\n') : [];
          if (alternate) {
            while (body.length < pane.height) {
              body.add('');
            }
          }
        } else {
          body = (captureText ?? 'captured $id').split('\n');
          while (body.length < pane.height) {
            body.add('');
          }
        }
      } else if (command.startsWith('display-message -p -t')) {
        final id = RegExp(r'-t (%\d+)').firstMatch(command)![1]!;
        final pane = panes.firstWhere((pane) => pane.id == id);
        body = [
          '$cursorX $cursorY ${alternate ? 1 : 0} 1 ${cursorMode ? 1 : 0} 0 0 1 0 ${bracketMode ? 1 : 0} 0 ${pane.height - 1} 0 0',
        ];
      } else if (command.startsWith('send-keys')) {
        inputBytes.addAll(
          command
              .split(' ')
              .skip(4)
              .map((value) => int.parse(value, radix: 16)),
        );
      } else if (command.startsWith('select-window')) {
        activeWindow = command.split(' ').last;
      } else if (command.startsWith('select-pane')) {
        final selected = panes.firstWhere(
          (pane) => pane.id == command.split(' ').last,
        );
        for (final pane in panes.where(
          (pane) => pane.windowId == selected.windowId,
        )) {
          pane.active = identical(pane, selected);
        }
      } else if (command.startsWith('split-window')) {
        addSplit();
      } else if (command == 'new-window') {
        activeWindow = '@1';
        panes.add(_Pane('%2', '@1'));
      } else if (command.startsWith('refresh-client -C')) {
        final size = command.split(' ').last.split('x').map(int.parse).toList();
        if (panes.length == 1) {
          panes.first.width = size[0];
          panes.first.height = size[1];
        }
      }
      final response = StringBuffer('%begin 1 $number 1\n');
      for (final line in body) {
        response.writeln(line);
      }
      response.writeln('%${failure ? 'error' : 'end'} 1 $number 1');
      if (command.endsWith(':continue') && afterCapture != null) {
        final id = RegExp(r'(%\d+):continue').firstMatch(command)![1]!;
        response.writeln('%output $id $afterCapture');
      }
      if (injectHook) {
        injectHook = false;
        output.add(ascii.encode('%begin 1 999 0\nhook output\n%end 1 999 0\n'));
      }
      output.add(utf8.encode(response.toString()));
      if (failure) return;
    }
  }

  void replyToHeld() {
    final number = heldSerial!;
    output.add(ascii.encode('%begin 1 $number 1\n%end 1 $number 1\n'));
    heldSerial = null;
    holdPrefix = null;
  }
}
