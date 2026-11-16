import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/screen_session_options.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/ssh_tmux_control_output.dart';
import 'package:crisp_cloud/services/terminal_backends.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

// Exercise the real platform/gateway validation in both VM and browser tests.
// The injected client below prevents any actual TCP or WebSocket connection.
final Uri? _fixtureGateway = kIsWeb
    ? Uri.parse('wss://gateway.example/ssh')
    : null;

void main() {
  late _Client client;
  late SshTerminalService service;
  late SshSession session;

  setUp(() async {
    client = _Client();
    service = _service((
      _,
      __, {
      required username,
      password,
      identities,
      gateway,
    }) async {
      return client;
    });
    session = await service.connect(
      'test.example',
      22,
      'alice',
      'password',
      gateway: _fixtureGateway,
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  test(
    'requests the actual terminal geometry and resizes the active PTY',
    () async {
      await service.startShell(session.id, width: 132, height: 43);
      expect(client.shellRequests, 1);
      expect(client.commands, isEmpty);
      expect(client.pty!.type, 'xterm-256color');
      expect(client.pty!.width, 132);
      expect(client.pty!.height, 43);

      await service.resizeTerminal(session.id, 95, 31);
      expect(client.shells.single.resizes, [(95, 31)]);
    },
  );

  test(
    'starts tmux through an exec PTY and preserves input and resize',
    () async {
      await service.startShell(
        session.id,
        width: 132,
        height: 43,
        tmux: const TmuxSessionOptions(sessionName: 'build_2-linux'),
      );
      expect(client.commands, ["exec tmux new-session -A -s 'build_2-linux'"]);
      expect(client.shellRequests, 0);
      expect(client.pty!.type, 'xterm-256color');
      expect(client.pty!.width, 132);
      expect(client.pty!.height, 43);
      expect(client.shells.single.received, isEmpty);

      await service.writeToShell(session.id, '\x02%'); // Prefix + split pane.
      await service.resizeTerminal(session.id, 95, 31);
      await _flushEvents();
      expect(client.shells.single.received.single, [2, 37]);
      expect(client.shells.single.resizes, [(95, 31)]);
    },
  );

  test(
    'attach uses an exact tmux target and never creates a fallback shell',
    () async {
      await service.startShell(
        session.id,
        tmux: const TmuxSessionOptions(
          sessionName: 'build',
          mode: TmuxSessionMode.attach,
        ),
      );
      expect(client.commands, ["exec tmux attach-session -t '=build'"]);
      expect(client.shellRequests, 0);
    },
  );

  test(
    'native control cleanup remains retryable after transport failure',
    () async {
      final stdout = StreamController<List<int>>();
      final stderr = StreamController<List<int>>();
      var closes = 0;
      final output = SshTmuxControlOutput(
        stdout: stdout.stream,
        stderr: stderr.stream,
        exitCode: Future<int?>.value(),
        write: (_) async {},
        close: () async {
          closes++;
          if (closes == 1) throw StateError('temporary cleanup failure');
        },
      );
      final subscription = output.output.listen((_) {});
      await expectLater(output.close(), throwsStateError);
      await output.close();
      await output.close();
      expect(closes, 2);
      await output.dispose();
      await subscription.cancel();
      await stdout.close();
      await stderr.close();
    },
  );

  test(
    'native cancellation releases its route even if a stream fails',
    () async {
      final stdout = StreamController<List<int>>(
        onCancel: () => throw StateError('failed stdout cancellation'),
      );
      final stderr = StreamController<List<int>>();
      var closes = 0;
      final output = SshTmuxControlOutput(
        stdout: stdout.stream,
        stderr: stderr.stream,
        exitCode: Future<int?>.value(),
        write: (_) async {},
        close: () async => closes++,
      );
      final subscription = output.output.listen((_) {});
      await expectLater(subscription.cancel(), throwsStateError);
      expect(closes, 1);
      await stdout.close();
      await stderr.close();
    },
  );

  test(
    'native tmux preserves raw stdout and separates stderr without a PTY',
    () async {
      final output = await service.startTmuxControl(
        session.id,
        tmux: const TmuxSessionOptions(
          sessionName: 'work',
          mode: TmuxSessionMode.attach,
          controlMode: true,
        ),
      );
      expect(client.commands, ["exec tmux -C attach-session -t '=work'"]);
      expect(client.pty, isNull);
      expect(client.shellRequests, 0);
      final shell = client.shells.single;
      final expected = <int>[
        ...utf8.encode('%output %1 '),
        0xe2,
        ...utf8.encode('\n%output %1 '),
        0x82,
        0xac,
        10,
      ];
      for (final byte in expected) {
        shell.output.add(Uint8List.fromList([byte]));
      }
      shell.errors.add(
        Uint8List.fromList(utf8.encode('%exit forged stderr\n')),
      );
      await _flushEvents();
      final received = <int>[];
      final done = Completer<void>();
      output.output.listen(received.addAll, onDone: done.complete);
      await output.write('list-windows\n');
      await _flushEvents();
      expect(shell.received.single, utf8.encode('list-windows\n'));
      shell.completeChannel(23);
      await shell.output.close();
      await _flushEvents();
      expect(done.isCompleted, isFalse);
      await shell.errors.close();
      await done.future;
      expect(received, expected);
      expect(output.diagnostics, '%exit forged stderr');
      expect(await output.exitCode, 23);
    },
  );

  test(
    'raw tmux validates mode and name before replacing a running shell',
    () async {
      await service.startShell(session.id);
      final shell = client.shells.single;
      for (final tmux in [
        const TmuxSessionOptions(sessionName: 'work'),
        const TmuxSessionOptions(
          sessionName: 'work;kill-server',
          controlMode: true,
        ),
      ]) {
        await expectLater(
          service.startTmuxControl(session.id, tmux: tmux),
          throwsArgumentError,
        );
        expect(shell.closed, isFalse);
      }
      await expectLater(
        service.startShell(
          session.id,
          tmux: const TmuxSessionOptions(
            sessionName: 'work',
            controlMode: true,
          ),
        ),
        throwsArgumentError,
      );
      expect(shell.closed, isFalse);
      expect(client.commands, isEmpty);
    },
  );

  test('disconnect during native tmux startup closes a late channel', () async {
    final pending = Completer<SSHSession>();
    client.pendingExecution = pending.future;
    final starting = service.startTmuxControl(
      session.id,
      tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
    );
    final rejected = expectLater(starting, throwsStateError);
    await _flushEvents();
    await service.disconnect(session.id);
    final late = _Shell();
    pending.complete(late);
    await rejected;
    expect(late.closed, isTrue);
    expect(service.getActiveSessions(), isEmpty);
  });

  test(
    'replaced native controller cannot write to or close its replacement',
    () async {
      final output = await service.startTmuxControl(
        session.id,
        tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
      );
      final firstDone = output.output.drain<void>();
      final oldShell = client.shells.single;
      final next = await service.startShell(session.id);
      final subscription = next.listen((_) {});
      await firstDone;
      await output.close();
      await expectLater(output.write('kill-server\n'), throwsStateError);
      expect(oldShell.closed, isTrue);
      expect(client.isClosed, isFalse);
      await service.writeToShell(session.id, 'still the new shell\r');
      await _flushEvents();
      expect(
        client.shells.last.received.single,
        utf8.encode('still the new shell\r'),
      );
      await subscription.cancel();
    },
  );

  test(
    'native control cancellation releases channel, route and pool slot',
    () async {
      final output = await service.startTmuxControl(
        session.id,
        tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
      );
      final subscription = output.output.listen((_) {});
      await subscription.cancel();
      expect(client.shells.single.closed, isTrue);
      expect(client.isClosed, isTrue);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test('native startup output is bounded before the client listens', () async {
    final output = await service.startTmuxControl(
      session.id,
      tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
    );
    client.shells.single.errors.add(
      Uint8List.fromList(List.filled(20000, 120)),
    );
    client.shells.single.output.add(Uint8List(1024 * 1024 + 1));
    await _flushEvents();
    final errors = <Object>[];
    final done = Completer<void>();
    output.output.listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    await _flushEvents();
    expect(errors.single, isStateError);
    expect(output.diagnostics.length, lessThanOrEqualTo(16 * 1024));
    expect(client.isClosed, isTrue);
  });

  test('invalid tmux names leave an existing shell untouched', () async {
    await service.startShell(session.id);
    final shell = client.shells.single;
    await expectLater(
      service.startShell(
        session.id,
        tmux: const TmuxSessionOptions(sessionName: "x'; kill-server; #"),
      ),
      throwsArgumentError,
    );
    expect(client.commands, isEmpty);
    expect(shell.closed, isFalse);
    expect(client.isClosed, isFalse);
    await service.writeToShell(session.id, 'still here\r');
    await _flushEvents();
    expect(shell.received.single, utf8.encode('still here\r'));
  });

  test('screen uses an exec PTY and preserves input and geometry', () async {
    const screen = ScreenSessionOptions(sessionName: 'build');
    await service.startShell(
      session.id,
      width: 132,
      height: 43,
      screen: screen,
    );
    expect(client.commands, [screen.command]);
    expect(client.shellRequests, 0);
    expect(client.pty!.type, 'xterm-256color');
    expect(client.pty!.width, 132);
    expect(client.pty!.height, 43);
    await service.writeToShell(session.id, '\x01c');
    await service.resizeTerminal(session.id, 95, 31);
    await _flushEvents();
    expect(client.shells.single.received.single, [1, 99]);
    expect(client.shells.single.resizes, [(95, 31)]);
  });

  test(
    'invalid or conflicting screen options preserve the running shell',
    () async {
      await service.startShell(session.id);
      final shell = client.shells.single;
      for (final options in [
        const ScreenSessionOptions(sessionName: "x'; id; #"),
        const ScreenSessionOptions(sessionName: 'work'),
      ]) {
        await expectLater(
          service.startShell(
            session.id,
            screen: options,
            tmux: options.sessionName == 'work'
                ? const TmuxSessionOptions(sessionName: 'work')
                : null,
          ),
          throwsArgumentError,
        );
        expect(client.commands, isEmpty);
        expect(shell.closed, isFalse);
        expect(client.isClosed, isFalse);
      }
      await service.writeToShell(session.id, 'still here\r');
      await _flushEvents();
      expect(shell.received.single, utf8.encode('still here\r'));
    },
  );

  test('disconnect during screen startup closes the late channel', () async {
    final pending = Completer<SSHSession>();
    client.pendingExecution = pending.future;
    final starting = service.startShell(
      session.id,
      screen: const ScreenSessionOptions(
        sessionName: '123.work',
        mode: ScreenSessionMode.attach,
      ),
    );
    final failed = expectLater(starting, throwsStateError);
    await _flushEvents();
    await service.disconnect(session.id);
    final lateShell = _Shell();
    pending.complete(lateShell);
    await failed;
    expect(lateShell.closed, isTrue);
    expect(service.getActiveSessions(), isEmpty);
    expect(client.shellRequests, 0);
  });

  test(
    'failed screen exec closes its pool slot without shell fallback',
    () async {
      final pending = Completer<SSHSession>();
      client.pendingExecution = pending.future;
      final starting = service.startShell(
        session.id,
        screen: const ScreenSessionOptions(sessionName: 'work'),
      );
      final failed = expectLater(starting, throwsStateError);
      await _flushEvents();
      pending.completeError(StateError('Exec request rejected'));
      await failed;
      expect(client.isClosed, isTrue);
      expect(client.shellRequests, 0);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'closing screen disconnects only this SSH client without remote commands',
    () async {
      const screen = ScreenSessionOptions(
        sessionName: '123.work',
        mode: ScreenSessionMode.attach,
      );
      final output = await service.startShell(session.id, screen: screen);
      final connection = SshTerminalConnection(service, session.id, output);
      await connection.close();
      expect(client.isClosed, isTrue);
      expect(client.shells.single.closed, isTrue);
      expect(client.shells.single.received, isEmpty);
      expect(client.commands, [screen.command]);
      expect(client.runCommands, isEmpty);
    },
  );

  test('disconnect during tmux startup closes its late exec channel', () async {
    final pending = Completer<SSHSession>();
    client.pendingExecution = pending.future;
    final starting = service.startShell(
      session.id,
      tmux: const TmuxSessionOptions(sessionName: 'build'),
    );
    final failed = expectLater(starting, throwsStateError);
    await _flushEvents();
    expect(client.commands, hasLength(1));
    await service.disconnect(session.id);
    final lateShell = _Shell();
    pending.complete(lateShell);
    await failed;
    expect(lateShell.closed, isTrue);
    expect(service.getActiveSessions(), isEmpty);
  });

  test(
    'failed tmux exec releases its pool slot without shell fallback',
    () async {
      final pending = Completer<SSHSession>();
      client.pendingExecution = pending.future;
      final starting = service.startShell(
        session.id,
        tmux: const TmuxSessionOptions(sessionName: 'build'),
      );
      final failed = expectLater(starting, throwsStateError);
      await _flushEvents();
      pending.completeError(StateError('Exec request rejected'));
      await failed;
      expect(client.shellRequests, 0);
      expect(client.isClosed, isTrue);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'disconnect closes only the tmux client without sending kill or exit',
    () async {
      final output = await service.startShell(
        session.id,
        tmux: const TmuxSessionOptions(sessionName: 'build'),
      );
      final connection = SshTerminalConnection(service, session.id, output);
      await connection.close();
      expect(client.isClosed, isTrue);
      expect(client.shells.single.closed, isTrue);
      expect(client.shells.single.received, isEmpty);
      expect(client.commands, ["exec tmux new-session -A -s 'build'"]);
      expect(client.runCommands, isEmpty);
    },
  );

  test('preserves remote exit status without losing final tmux output', () async {
    final output = await service.startShell(
      session.id,
      tmux: const TmuxSessionOptions(sessionName: 'build'),
    );
    final connection = SshTerminalConnection(service, session.id, output);
    var exited = false;
    unawaited(connection.exitCode.then((_) => exited = true));
    await _flushEvents();
    expect(exited, isFalse);

    final shell = client.shells.single;
    shell.completeChannel(127);
    // SSH channel completion can precede delivery of its final buffered output.
    shell.output.add(Uint8List.fromList(utf8.encode('final screen\r\n')));
    shell.errors.add(Uint8List.fromList(utf8.encode('tmux: not found\r\n')));
    final collected = output.join();
    await shell.finish();
    expect(await connection.exitCode, 127);
    expect(
      await collected,
      allOf(contains('final screen'), contains('not found')),
    );
    expect(client.shellRequests, 0);
  });

  test(
    'output EOF waits for the later SSH exit status before cleanup',
    () async {
      final output = await service.startShell(
        session.id,
        tmux: const TmuxSessionOptions(sessionName: 'build'),
      );
      final connection = SshTerminalConnection(service, session.id, output);
      var exited = false;
      unawaited(connection.exitCode.then((_) => exited = true));
      final shell = client.shells.single;
      final collected = output.join();
      shell.output.add(Uint8List.fromList(utf8.encode('final screen\r\n')));
      shell.errors.add(Uint8List.fromList(utf8.encode('final diagnostic\r\n')));
      // SSH EOF and exit-status/channel-close are separate protocol messages.
      // Do not use finish(), which deliberately completes the channel first.
      await Future.wait([shell.output.close(), shell.errors.close()]);
      expect(
        await collected,
        allOf(contains('final screen'), contains('final diagnostic')),
      );
      await _flushEvents();
      expect(exited, isFalse);
      expect(client.isClosed, isFalse);
      expect(shell.closed, isFalse);
      expect(service.getActiveSessions(), hasLength(1));

      shell.completeChannel(23);
      expect(await connection.exitCode, 23);
      await _flushEvents();
      expect(client.isClosed, isTrue);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'explicit disconnect still closes SSH while waiting after output EOF',
    () async {
      final output = await service.startShell(session.id);
      final connection = SshTerminalConnection(service, session.id, output);
      final collected = output.drain<void>();
      final shell = client.shells.single;
      await Future.wait([shell.output.close(), shell.errors.close()]);
      await collected;
      expect(client.isClosed, isFalse);

      await connection.close().timeout(const Duration(seconds: 2));
      expect(client.isClosed, isTrue);
      expect(shell.closed, isTrue);
      expect(service.getActiveSessions(), isEmpty);
      expect(await connection.exitCode, isNull);
    },
  );

  test(
    'observes early channel errors and preserves them for the exit reader',
    () async {
      final output = await service.startShell(session.id);
      final connection = SshTerminalConnection(service, session.id, output);
      final failure = StateError('SSH channel failed');
      client.shells.single.failChannel(failure);
      await _flushEvents(); // No status consumer has attached yet.
      await expectLater(connection.exitCode, throwsA(same(failure)));
    },
  );

  test(
    'plain output streams remain compatible without exit metadata',
    () async {
      final connection = SshTerminalConnection(
        service,
        session.id,
        const Stream<String>.empty(),
      );
      expect(await connection.exitCode, isNull);
    },
  );

  test(
    'decrypts an encrypted key without sending its passphrase as a password',
    () async {
      List<SSHIdentity>? sentIdentities;
      String? sentPassword;
      final keyedService = _service((
        _,
        __, {
        required username,
        password,
        identities,
        gateway,
      }) async {
        sentIdentities = identities;
        sentPassword = password;
        return _Client();
      });
      addTearDown(keyedService.dispose);
      final connected = await keyedService.connectWithKey(
        'key.example',
        22,
        'alice',
        _encryptedTestKey,
        passphrase: _testPassphrase,
        gateway: _fixtureGateway,
      );
      expect(connected.connected, isTrue);
      expect(sentPassword, isNull);
      expect(sentIdentities, hasLength(1));
      expect((sentIdentities!.single as SSHKeyPair).name, 'ssh-ed25519');
    },
  );

  test(
    'rejects missing or incorrect key passphrases before connecting',
    () async {
      var connections = 0;
      final keyedService = _service((
        _,
        __, {
        required username,
        password,
        identities,
        gateway,
      }) async {
        connections++;
        return _Client();
      });
      addTearDown(keyedService.dispose);
      for (final passphrase in [null, '', 'incorrect']) {
        await expectLater(
          keyedService.connectWithKey(
            'key.example',
            22,
            'alice',
            _encryptedTestKey,
            passphrase: passphrase,
            gateway: _fixtureGateway,
          ),
          throwsA(isA<TerminalMountFormatException>()),
        );
      }
      expect(connections, 0);
      expect(keyedService.getActiveSessions(), isEmpty);
    },
  );

  test('accepts unencrypted keys with omitted or empty passphrases', () async {
    final pem = SSHKeyPair.fromPem(
      _encryptedTestKey,
      _testPassphrase,
    ).first.toPem();
    for (final passphrase in [null, '']) {
      final connected = await service.connectWithKey(
        'key.example',
        22,
        'alice',
        pem,
        passphrase: passphrase,
        gateway: _fixtureGateway,
      );
      expect(connected.connected, isTrue);
    }
  });

  test('writes UTF-8, arrow keys, tab and control characters without line buffering', () async {
    await service.startShell(session.id);
    const input = 'Grüße 中 👩‍💻\x1b[A\t\x03\r';
    await service.writeToShell(session.id, input);
    await _flushEvents();
    expect(
      client.shells.single.received.expand((bytes) => bytes),
      utf8.encode(input),
    );
  });

  test(
    'buffers initial prompt and decodes UTF-8 split across packets',
    () async {
      final output = await service.startShell(session.id);
      final shell = client.shells.single;
      const text = '\x1b[32mGrüße 中 👩‍💻\x1b[0m\r\n\$ ';
      for (final byte in utf8.encode(text)) {
        shell.output.add(Uint8List.fromList([byte]));
      }
      await _flushEvents(); // Initial output arrives before the UI subscribes.

      final collected = output.join();
      await shell.finish();
      expect(await collected, text);
      await _flushEvents();
      expect(service.getActiveSessions(), isEmpty);
      expect(client.isClosed, isTrue);
    },
  );

  test(
    'waits for stderr after stdout EOF and keeps its UTF-8 decoder separate',
    () async {
      final output = await service.startShell(session.id);
      final shell = client.shells.single;
      final received = <String>[];
      final finished = Completer<void>();
      output.listen(received.add, onDone: finished.complete);

      shell.output.add(Uint8List.fromList([0xc3])); // First byte of é.
      shell.errors.add(Uint8List.fromList(utf8.encode('warning: ')));
      shell.output.add(Uint8List.fromList([0xa9]));
      await shell.output.close();
      await _flushEvents();
      expect(finished.isCompleted, isFalse);
      expect(client.isClosed, isFalse);

      for (final byte in utf8.encode('最後\r\n')) {
        shell.errors.add(Uint8List.fromList([byte]));
      }
      await shell.errors.close();
      await finished.future;
      expect(received.join(), contains('é'));
      expect(received.join(), contains('warning: '));
      expect(received.join(), endsWith('最後\r\n'));
      expect(received.join(), isNot(contains('\uFFFD')));
    },
  );

  test(
    'reports channel errors instead of silently swallowing stderr errors',
    () async {
      final output = await service.startShell(session.id);
      final errors = <Object>[];
      final finished = Completer<void>();
      output.listen((_) {}, onError: errors.add, onDone: finished.complete);
      final failure = StateError('channel failed');
      client.shells.single.errors.addError(failure);
      await client.shells.single.finish();
      await finished.future;
      expect(errors, hasLength(1));
      expect(errors.single, same(failure));
    },
  );

  test('disconnect completes before any output consumer attaches', () async {
    final output = await service.startShell(session.id);
    client.shells.single.output.add(
      Uint8List.fromList(utf8.encode('prompt> ')),
    );
    await _flushEvents();

    await service.disconnect(session.id).timeout(const Duration(seconds: 2));
    expect(client.isClosed, isTrue);
    expect(await output.join(), 'prompt> ');
  });

  test(
    'cancelling the terminal subscription closes the SSH connection',
    () async {
      final output = await service.startShell(session.id);
      final subscription = output.listen((_) {});
      await subscription.cancel();
      expect(client.shells.single.closed, isTrue);
      expect(client.isClosed, isTrue);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'restart closes the old shell without disconnecting the replacement',
    () async {
      final firstOutput = await service.startShell(session.id);
      final firstDone = firstOutput.drain<void>();
      final firstShell = client.shells.single;
      final secondOutput = await service.startShell(
        session.id,
        width: 100,
        height: 30,
      );
      final secondSubscription = secondOutput.listen((_) {});

      await firstDone;
      expect(firstShell.closed, isTrue);
      expect(client.isClosed, isFalse);
      expect(service.getActiveSessions(), hasLength(1));
      await service.writeToShell(session.id, 'next\r');
      await _flushEvents();
      expect(client.shells.last.received.single, utf8.encode('next\r'));
      await secondSubscription.cancel();
    },
  );

  test('disconnect during shell setup closes the late shell', () async {
    final pending = Completer<SSHSession>();
    client.pendingShell = pending.future;
    final starting = service.startShell(session.id);
    final failed = expectLater(starting, throwsStateError);
    await _flushEvents();
    await service.disconnect(session.id);
    final lateShell = _Shell();
    pending.complete(lateShell);
    await failed;
    expect(lateShell.closed, isTrue);
    expect(service.getActiveSessions(), isEmpty);
  });

  test(
    'failed shell setup releases the connection and its pool slot',
    () async {
      final pending = Completer<SSHSession>();
      client.pendingShell = pending.future;
      final starting = service.startShell(session.id);
      final failed = expectLater(starting, throwsStateError);
      await _flushEvents();
      pending.completeError(StateError('PTY rejected'));
      await failed;
      expect(client.isClosed, isTrue);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'transport completion does not discard output still queued in channels',
    () async {
      final output = await service.startShell(session.id);
      final collected = output.join();
      client.endTransport();
      await _flushEvents();
      expect(service.getActiveSessions(), isEmpty);

      final shell = client.shells.single;
      shell.output.add(Uint8List.fromList(utf8.encode('last screen\r\n')));
      shell.errors.add(Uint8List.fromList(utf8.encode('last error\r\n')));
      await shell.finish();
      final text = await collected;
      expect(text, contains('last screen\r\n'));
      expect(text, contains('last error\r\n'));
    },
  );

  test('noninteractive execute also decodes UTF-8', () async {
    final executing = service.execute(session.id, 'pwd');
    await _flushEvents();
    final command = client.shells.single;
    final bytes = utf8.encode('日本語\n');
    command.output.add(Uint8List.fromList(bytes.sublist(0, 2)));
    command.output.add(Uint8List.fromList(bytes.sublist(2)));
    await command.finish();
    expect(await executing, '日本語\n');
    expect(client.pty, isNull);
    expect(command.closed, isTrue);
  });

  test(
    'validates actual start and resize entry points before requesting a PTY',
    () async {
      await expectLater(
        service.startShell(session.id, width: 0),
        throwsArgumentError,
      );
      await expectLater(
        service.startShell(session.id, height: -1),
        throwsArgumentError,
      );
      expect(client.shells, isEmpty);
      await service.startShell(session.id);
      await expectLater(
        service.resizeTerminal(session.id, -1, 24),
        throwsArgumentError,
      );
      expect(client.shells.single.resizes, isEmpty);
    },
  );

  test(
    'dispose rejects and closes a connection that completes later',
    () async {
      final pending = Completer<SSHClient>();
      final connectingService = _service(
        (_, __, {required username, password, identities, gateway}) =>
            pending.future,
      );
      addTearDown(connectingService.dispose);
      final connecting = connectingService.connect(
        'late.example',
        22,
        'u',
        'p',
        gateway: _fixtureGateway,
      );
      final failed = expectLater(connecting, throwsStateError);
      await connectingService.dispose();
      final lateClient = _Client();
      pending.complete(lateClient);
      await failed;
      expect(lateClient.isClosed, isTrue);
      expect(connectingService.getActiveSessions(), isEmpty);
    },
  );

  test('pool limit includes connections still authenticating', () async {
    final attempts = <Completer<SSHClient>>[];
    final connectingService = _service((
      _,
      __, {
      required username,
      password,
      identities,
      gateway,
    }) {
      final attempt = Completer<SSHClient>();
      attempts.add(attempt);
      return attempt.future;
    });
    addTearDown(connectingService.dispose);
    final connections = [
      for (var i = 0; i < SshTerminalService.maxSessions; i++)
        connectingService.connect(
          'host$i',
          22,
          'u',
          'p',
          gateway: _fixtureGateway,
        ),
    ];
    await expectLater(
      connectingService.connect(
        'over-capacity',
        22,
        'u',
        'p',
        gateway: _fixtureGateway,
      ),
      throwsStateError,
    );
    expect(attempts, hasLength(SshTerminalService.maxSessions));
    for (final attempt in attempts) {
      attempt.complete(_Client());
    }
    final connected = await Future.wait(connections);
    expect(connected.map((session) => session.id).toSet(), hasLength(5));
    expect(connectingService.getActiveSessions(), hasLength(5));
  });
}

SshTerminalService _service(SshClientConnector connector) => SshTerminalService(
  secureStorage: InMemorySecureStorage(),
  clientConnector: connector,
);

Future<void> _flushEvents() => Future<void>.delayed(Duration.zero);

/// Only the SSH I/O boundary is fake; all service lifecycle and encoding logic
/// above executes the production implementation.
class _Client implements SSHClient {
  final shells = <_Shell>[];
  final commands = <String>[];
  final runCommands = <String>[];
  int shellRequests = 0;
  final _finished = Completer<void>();
  SSHPtyConfig? pty;
  Future<SSHSession>? pendingShell;
  Future<SSHSession>? pendingExecution;
  Uint8List runOutput = Uint8List(0);
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> get done => _finished.future;

  @override
  Future<SSHSession> shell({
    SSHPtyConfig? pty = const SSHPtyConfig(),
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    shellRequests++;
    this.pty = pty;
    if (pendingShell != null) return pendingShell!;
    final shell = _Shell();
    shells.add(shell);
    return shell;
  }

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    this.pty = pty;
    if (pendingExecution != null) return pendingExecution!;
    final shell = _Shell();
    shells.add(shell);
    return shell;
  }

  @override
  Future<Uint8List> run(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    runCommands.add(command);
    return runOutput;
  }

  void endTransport() {
    _closed = true;
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  Future<void> close() async {
    endTransport();
    for (final shell in shells) {
      shell.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shell implements SSHSession {
  _Shell() {
    _input.stream.listen(received.add);
  }

  final output = StreamController<Uint8List>();
  final errors = StreamController<Uint8List>();
  final _input = StreamController<Uint8List>();
  final _finished = Completer<void>();
  final received = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool closed = false;
  int? _exitCode;

  @override
  Future<void> get done => _finished.future;

  @override
  int? get exitCode => _exitCode;

  void completeChannel([int? code]) {
    if (_finished.isCompleted) return;
    _exitCode = code;
    _finished.complete();
  }

  void failChannel(Object error) => _finished.completeError(error);

  @override
  StreamSink<Uint8List> get stdin => _input.sink;

  @override
  Stream<Uint8List> get stdout => output.stream;

  @override
  Stream<Uint8List> get stderr => errors.stream;

  @override
  void resizeTerminal(
    int width,
    int height, [
    int pixelWidth = 0,
    int pixelHeight = 0,
  ]) {
    resizes.add((width, height));
  }

  Future<void> finish() async {
    completeChannel();
    await Future.wait([output.close(), errors.close()]);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    completeChannel();
    unawaited(output.close());
    unawaited(errors.close());
    unawaited(_input.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Generated solely for this test; never used for real SSH access. One bcrypt
// round keeps decryption checks fast while exercising the encrypted PEM path.
const _testPassphrase = 'crispcloud-test-passphrase';
const _encryptedTestKey = '''
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABAoYfP/LZ
tDShpmPjf8G8L7AAAAAQAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAINR9AQwqTdqM7g8v
19usIcpplj5aGaoM/BCreHqnbpe3AAAAoPvLGz4G2zfyGs8dl2noKWWfBlmmmbn3EUDCH4
40usQZfpxZQaLbXqPfqqqBcVh7KNeAEaV9iw5W/DEGTW6qA66Uy3666v6ZySWljBZ8TQIQ
RaLNMkGeO6gAwnZ/8O3NOQnX7EuwplK/m0iDZHd8+F8fZYNkuwrrOpno4YkaXiZo+g91KL
T8grtMNHPPk2CpjDDrOaMjdL55Ng7I3S1wQkY=
-----END OPENSSH PRIVATE KEY-----
''';
