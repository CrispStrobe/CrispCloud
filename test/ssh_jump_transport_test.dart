import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/ssh_jump_host.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

final _gateway = Uri.parse('wss://gateway.example/ssh');
const _first = SshJumpHost(
  host: 'outer.example',
  port: 2222,
  username: 'outer',
  password: 'outer-secret',
);
const _second = SshJumpHost(
  host: 'inner.example',
  username: 'inner',
  password: 'inner-secret',
);

void main() {
  late _Harness harness;
  late SshTerminalService service;

  setUp(() {
    harness = _Harness();
    service = harness.service();
  });
  tearDown(() async => service.dispose());

  Future<SshSession> connect([
    List<SshJumpHost> jumps = const [_first, _second],
  ]) => service.connect(
    'target.example',
    2200,
    'target',
    'target-secret',
    gateway: _gateway,
    jumpHosts: jumps,
  );

  test(
    'opens one outer socket, authenticates each hop, executes at final host',
    () async {
      final session = await connect();
      expect(harness.outerConnections, [('outer.example', 2222, _gateway)]);
      expect(harness.forwards, [
        ('outer.example:2222', 'inner.example', 22),
        ('inner.example:22', 'target.example', 2200),
      ]);
      expect(harness.prompts, [
        'outer.example:2222',
        'inner.example:22',
        'target.example:2200',
      ]);
      expect(harness.credentials.map((item) => item.$1), [
        'outer',
        'inner',
        'target',
      ]);
      expect(harness.credentials.map((item) => item.$2), [
        'outer-secret',
        'inner-secret',
        'target-secret',
      ]);
      expect(harness.credentials.every((item) => item.$3 == null), isTrue);
      expect(session.host, 'target.example');
      expect(session.port, 2200);
      expect(service.getActiveSessions(), hasLength(1));
      expect(await service.execute(session.id, 'pwd'), 'target.example:2200');
      expect(
        harness.clients.where((client) => client.runs.isNotEmpty).single.name,
        'target.example:2200',
      );

      await service.disconnect(session.id);
      expect(harness.closedClients, [
        'target.example:2200',
        'inner.example:22',
        'outer.example:2222',
      ]);
      expect(harness.sockets.every((socket) => socket.closed), isTrue);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'direct connections still use verified socket path when no seam is set',
    () async {
      final session = await connect([]);
      expect(harness.outerConnections, [('target.example', 2200, _gateway)]);
      expect(harness.forwards, isEmpty);
      expect(harness.prompts, ['target.example:2200']);
      await service.disconnect(session.id);
      expect(harness.closedClients, ['target.example:2200']);
    },
  );

  test(
    'mixed hop key authentication never sends a passphrase as a password',
    () async {
      await connect([
        _first,
        const SshJumpHost(
          host: 'inner.example',
          username: 'inner',
          authentication: SshTerminalAuthentication.privateKey,
          privateKey: _encryptedTestKey,
          passphrase: _testPassphrase,
          password: 'ignored-password',
        ),
      ]);
      expect(harness.credentials[1].$2, isNull);
      expect(harness.credentials[1].$3, hasLength(1));
      expect(
        (harness.credentials[1].$3!.single as SSHKeyPair).name,
        'ssh-ed25519',
      );
      expect(harness.credentials.last.$2, 'target-secret');
    },
  );

  test(
    'invalid key at any later hop fails before opening the outer socket',
    () async {
      await expectLater(
        connect([
          _first,
          const SshJumpHost(
            host: 'inner.example',
            username: 'inner',
            authentication: SshTerminalAuthentication.privateKey,
            privateKey: _encryptedTestKey,
            passphrase: 'incorrect',
          ),
        ]),
        throwsA(isA<TerminalMountFormatException>()),
      );
      expect(harness.outerConnections, isEmpty);
      expect(harness.clients, isEmpty);
    },
  );

  test(
    'private-key targets retain the password-authenticated jump route',
    () async {
      await service.connectWithKey(
        'target.example',
        2200,
        'target',
        _encryptedTestKey,
        passphrase: _testPassphrase,
        gateway: _gateway,
        jumpHosts: [_first, _second],
      );
      expect(harness.credentials.first.$2, 'outer-secret');
      expect(harness.credentials.last.$2, isNull);
      expect(harness.credentials.last.$3, hasLength(1));
      expect(harness.prompts, [
        'outer.example:2222',
        'inner.example:22',
        'target.example:2200',
      ]);
    },
  );

  test(
    'disconnect releases channels without waiting for a remote close reply',
    () async {
      harness.waitForDestroy = true;
      final session = await connect();
      await service.disconnect(session.id);
      expect(harness.closedClients, [
        'target.example:2200',
        'inner.example:22',
        'outer.example:2222',
      ]);
      expect(harness.sockets.every((socket) => socket.destroyed), isTrue);
    },
  );

  test(
    'rejecting a middle host key prevents downstream auth and closes route',
    () async {
      harness.rejectEndpoint = 'inner.example:22';
      await expectLater(connect(), throwsA(isA<TerminalMountException>()));
      expect(harness.prompts, ['outer.example:2222', 'inner.example:22']);
      expect(harness.clients.map((client) => client.name), [
        'outer.example:2222',
        'inner.example:22',
      ]);
      expect(harness.closedClients, ['inner.example:22', 'outer.example:2222']);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'changed middle host key fails closed without offering a trust override',
    () async {
      await harness.storage.write(
        'ssh_known_hosts_v1',
        jsonEncode({'inner.example:22': 'SHA256:${'Z' * 43}'}),
      );
      await expectLater(connect(), throwsA(isA<TerminalMountException>()));
      expect(harness.prompts, ['outer.example:2222']);
      expect(harness.closedClients, ['inner.example:22', 'outer.example:2222']);
      final saved = jsonDecode(
        (await harness.storage.read('ssh_known_hosts_v1'))!,
      );
      expect(saved['inner.example:22'], 'SHA256:${'Z' * 43}');
    },
  );

  test('forwarding failure releases already authenticated hops', () async {
    harness.failForwardTo = 'target.example';
    await expectLater(connect(), throwsA(isA<TerminalMountException>()));
    expect(harness.closedClients, ['inner.example:22', 'outer.example:2222']);
    expect(harness.prompts, ['outer.example:2222', 'inner.example:22']);
    expect(service.getActiveSessions(), isEmpty);
  });

  test(
    'final authentication failure closes the final client and its ancestors',
    () async {
      harness.failAuthenticationAt = 'target.example:2200';
      await expectLater(connect(), throwsA(isA<TerminalMountException>()));
      expect(harness.closedClients, [
        'target.example:2200',
        'inner.example:22',
        'outer.example:2222',
      ]);
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test(
    'disconnectAll closes a client while its host-key prompt is pending',
    () async {
      final approval = Completer<bool>();
      harness.promptGateEndpoint = 'inner.example:22';
      harness.promptGate = approval.future;
      final connecting = connect();
      final failed = expectLater(connecting, throwsStateError);
      await _flush();
      expect(harness.prompts, ['outer.example:2222', 'inner.example:22']);
      await service.disconnectAll();
      expect(harness.closedClients, ['inner.example:22', 'outer.example:2222']);
      approval.complete(true);
      await failed;
      final saved = jsonDecode(
        (await harness.storage.read('ssh_known_hosts_v1'))!,
      );
      expect(saved.containsKey('inner.example:22'), isFalse);
      expect(harness.clients, hasLength(2));
      expect(service.getActiveSessions(), isEmpty);
    },
  );

  test('cancellation closes a forwarded socket that arrives later', () async {
    final lateForward = Completer<SSHForwardChannel>();
    harness.pendingForwardTo = 'inner.example';
    harness.pendingForward = lateForward.future;
    final connecting = connect();
    final failed = expectLater(connecting, throwsStateError);
    await _flush();
    expect(harness.clients, hasLength(1));
    await service.disconnectAll();
    final socket = _Socket('inner.example:22');
    lateForward.complete(socket);
    await failed;
    await _flush();
    expect(socket.closed, isTrue);
    expect(harness.clients, hasLength(1));
    expect(harness.closedClients, ['outer.example:2222']);
  });

  test(
    'dispose closes an outer socket that arrives after cancellation',
    () async {
      final lateSocket = Completer<SSHSocket>();
      harness.pendingOuter = lateSocket.future;
      final connecting = connect();
      final failed = expectLater(connecting, throwsStateError);
      await service.dispose();
      final socket = _Socket('outer.example:2222');
      lateSocket.complete(socket);
      await failed;
      await _flush();
      expect(socket.closed, isTrue);
      expect(harness.clients, isEmpty);
    },
  );

  test(
    'route snapshot cannot change while the first connection awaits I/O',
    () async {
      final lateSocket = Completer<SSHSocket>();
      harness.pendingOuter = lateSocket.future;
      final jumps = [_first, _second];
      final connecting = connect(jumps);
      jumps[1] = const SshJumpHost(host: 'different.example', username: 'bad');
      jumps.clear();
      lateSocket.complete(_Socket('outer.example:2222'));
      await connecting;
      expect(harness.prompts, [
        'outer.example:2222',
        'inner.example:22',
        'target.example:2200',
      ]);
    },
  );

  test(
    'each attempt retains its captured host-key prompt for every hop',
    () async {
      final lateSocket = Completer<SSHSocket>();
      harness.pendingOuter = lateSocket.future;
      final captured = <String>[];
      service.confirmHostKey = (endpoint, _) async {
        captured.add(endpoint);
        return true;
      };
      final connecting = connect();
      service.confirmHostKey = (_, __) async => false;
      lateSocket.complete(_Socket('outer.example:2222'));
      await connecting;
      expect(captured, [
        'outer.example:2222',
        'inner.example:22',
        'target.example:2200',
      ]);
    },
  );

  test(
    'invalid duplicate or oversized routes fail before network I/O',
    () async {
      for (final jumps in [
        [_first, _first],
        [const SshJumpHost(host: 'TARGET.EXAMPLE', port: 2200, username: 'u')],
        [
          for (var i = 0; i < 4; i++)
            SshJumpHost(host: 'hop$i.example', username: 'u'),
        ],
      ]) {
        await expectLater(connect(jumps), throwsArgumentError);
      }
      expect(harness.outerConnections, isEmpty);
    },
  );

  test(
    'tab cancellation prevents later hops without disconnecting other tabs',
    () async {
      final other = await service.connect(
        'other.example',
        22,
        'other',
        'p',
        gateway: _gateway,
      );
      var current = true;
      harness.afterAuthentication = (endpoint) {
        if (endpoint == 'outer.example:2222') current = false;
      };
      await expectLater(
        service.connect(
          'target.example',
          2200,
          'target',
          'p',
          gateway: _gateway,
          jumpHosts: [_first, _second],
          isCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(harness.forwards, isEmpty);
      expect(harness.closedClients, ['outer.example:2222']);
      expect(service.getActiveSessions().single.id, other.id);
      expect(await service.execute(other.id, 'pwd'), 'other.example:22');
    },
  );

  test('already stale tab attempts never open a socket', () async {
    await expectLater(
      service.connect(
        'target.example',
        2200,
        'target',
        'p',
        gateway: _gateway,
        jumpHosts: [_first],
        isCurrent: () => false,
      ),
      throwsStateError,
    );
    expect(harness.outerConnections, isEmpty);
  });

  test(
    'a route consumes one terminal pool slot and cleanup makes it reusable',
    () async {
      final routed = await connect([
        _first,
        _second,
        const SshJumpHost(host: 'third.example', username: 'third'),
      ]);
      for (var i = 1; i < SshTerminalService.maxSessions; i++) {
        await service.connect(
          'other$i.example',
          22,
          'u',
          'p',
          gateway: _gateway,
        );
      }
      expect(service.getActiveSessions(), hasLength(5));
      await expectLater(connect(), throwsStateError);
      await service.disconnect(routed.id);
      await connect();
      expect(service.getActiveSessions(), hasLength(5));
    },
  );

  test(
    'a failed client constructor closes its socket and previous hops',
    () async {
      harness.failBeforeClientAt = 'inner.example:22';
      await expectLater(connect(), throwsA(isA<TerminalMountException>()));
      expect(harness.sockets.every((socket) => socket.closed), isTrue);
      expect(harness.closedClients, ['outer.example:2222']);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Harness {
  final storage = InMemorySecureStorage();
  final clients = <_Client>[];
  final sockets = <_Socket>[];
  final outerConnections = <(String, int, Uri?)>[];
  final forwards = <(String, String, int)>[];
  final credentials = <(String, String?, List<SSHIdentity>?)>[];
  final prompts = <String>[];
  final closedClients = <String>[];
  String? rejectEndpoint;
  String? failForwardTo;
  String? failAuthenticationAt;
  String? failBeforeClientAt;
  String? pendingForwardTo;
  Future<SSHForwardChannel>? pendingForward;
  Future<SSHSocket>? pendingOuter;
  String? promptGateEndpoint;
  Future<bool>? promptGate;
  void Function(String endpoint)? afterAuthentication;
  bool waitForDestroy = false;

  SshTerminalService service() => SshTerminalService(
    secureStorage: storage,
    confirmHostKey: (endpoint, _) async {
      prompts.add(endpoint);
      if (endpoint == promptGateEndpoint) return promptGate!;
      return endpoint != rejectEndpoint;
    },
    socketConnector: (host, port, {gateway}) async {
      outerConnections.add((host, port, gateway));
      if (pendingOuter != null) return pendingOuter!;
      final socket = _Socket('$host:$port', waitForDestroy: waitForDestroy);
      sockets.add(socket);
      return socket;
    },
    verifiedClientOpener:
        (
          socket, {
          required username,
          password,
          identities,
          required verify,
          onCreated,
        }) async {
          final named = socket as _Socket;
          if (named.name == failBeforeClientAt) {
            throw StateError('Client constructor failed');
          }
          final client = _Client(this, named);
          clients.add(client);
          onCreated?.call(client);
          if (!await verify(
            'ssh-ed25519',
            Uint8List.fromList(utf8.encode('SHA256:${'A' * 43}')),
          )) {
            throw StateError('Host key rejected');
          }
          credentials.add((username, password, identities));
          if (client.name == failAuthenticationAt) {
            throw StateError('Authentication failed');
          }
          await client.authenticated;
          afterAuthentication?.call(client.name);
          return client;
        },
  );
}

class _Socket implements SSHForwardChannel {
  _Socket(this.name, {bool waitForDestroy = false})
    : _closeReply = waitForDestroy ? Completer<void>() : null;
  final String name;
  final Completer<void>? _closeReply;
  bool closed = false;
  bool destroyed = false;

  @override
  Future<void> close() async {
    closed = true;
    await _closeReply?.future;
  }

  @override
  void destroy() {
    closed = true;
    destroyed = true;
    if (_closeReply?.isCompleted == false) _closeReply!.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements SSHClient {
  _Client(this.harness, this.socket);
  final _Harness harness;
  @override
  final _Socket socket;
  final _done = Completer<void>();
  final runs = <String>[];
  bool _closed = false;
  String get name => socket.name;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> get authenticated => Future<void>.value();

  @override
  Future<void> get done => _done.future;

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    harness.forwards.add((name, remoteHost, remotePort));
    if (harness.failForwardTo == remoteHost) {
      throw StateError('Forwarding rejected');
    }
    if (harness.pendingForwardTo == remoteHost) return harness.pendingForward!;
    final next = _Socket(
      '$remoteHost:$remotePort',
      waitForDestroy: harness.waitForDestroy,
    );
    harness.sockets.add(next);
    return next;
  }

  @override
  Future<Uint8List> run(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    runs.add(command);
    return Uint8List.fromList(utf8.encode(name));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    harness.closedClients.add(name);
    await socket.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Test-only identity, copied from the existing direct SSH authentication suite.
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
