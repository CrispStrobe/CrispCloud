import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

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
    session = await service.connect('test.example', 22, 'alice', 'password');
  });

  tearDown(() async {
    await service.dispose();
  });

  test(
    'requests the actual terminal geometry and resizes the active PTY',
    () async {
      await service.startShell(session.id, width: 132, height: 43);
      expect(client.pty!.type, 'xterm-256color');
      expect(client.pty!.width, 132);
      expect(client.pty!.height, 43);

      await service.resizeTerminal(session.id, 95, 31);
      expect(client.shells.single.resizes, [(95, 31)]);
    },
  );

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
    client.runOutput = Uint8List.fromList(utf8.encode('日本語\n'));
    expect(await service.execute(session.id, 'pwd'), '日本語\n');
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
        connectingService.connect('host$i', 22, 'u', 'p'),
    ];
    await expectLater(
      connectingService.connect('over-capacity', 22, 'u', 'p'),
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
  final _finished = Completer<void>();
  SSHPtyConfig? pty;
  Future<SSHSession>? pendingShell;
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
    this.pty = pty;
    if (pendingShell != null) return pendingShell!;
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
  }) async => runOutput;

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
  final received = <Uint8List>[];
  final resizes = <(int, int)>[];
  bool closed = false;

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
    await Future.wait([output.close(), errors.close()]);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(output.close());
    unawaited(errors.close());
    unawaited(_input.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
