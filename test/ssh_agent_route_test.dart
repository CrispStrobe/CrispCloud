import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/ssh_jump_host.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_agent.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_agent_fixture.dart';

const _jump = SshJumpHost(
  host: 'jump.example',
  username: 'jump-user',
  authentication: SshTerminalAuthentication.agent,
);

void main() {
  late _RouteFixture fixture;
  setUp(() => fixture = _RouteFixture());
  tearDown(() async => fixture.service.dispose());

  test(
    'each agent-authenticated hop verifies its host before signing',
    () async {
      final session = await fixture.service.connectWithAgent(
        'final.example',
        22,
        'user',
        jumpHosts: [_jump],
        forwardAgent: true,
      );
      expect(fixture.events, [
        'verify jump.example',
        'sign jump.example',
        'verify final.example',
        'sign final.example',
      ]);
      expect(fixture.passwords, [null, null]);
      expect(fixture.agents, hasLength(1));
      expect(fixture.agent.requests.map((request) => request.first), [
        11,
        13,
        13,
      ]);
      expect(fixture.handlers['jump.example'], isNull);
      expect(fixture.handlers['final.example'], same(fixture.agents.single));
      expect(session.host, 'final.example');
      await fixture.service.disconnect(session.id);
      expect(fixture.agents.single.isClosed, isTrue);
    },
  );

  test('agent authentication alone never forwards the agent', () async {
    await fixture.service.connectWithAgent(
      'final.example',
      22,
      'user',
      jumpHosts: [_jump],
    );
    expect(fixture.handlers.values, everyElement(isNull));
    expect(fixture.agent.requests.map((request) => request.first), [
      11,
      13,
      13,
    ]);
  });

  test('password authentication forwards only after explicit permission at final host', () async {
    final session = await fixture.service.connect(
      'final.example',
      22,
      'user',
      'secret',
      jumpHosts: [
        const SshJumpHost(
          host: 'jump.example',
          username: 'jump',
          password: 'hop-secret',
        ),
      ],
      forwardAgent: true,
    );
    expect(fixture.passwords, ['hop-secret', 'secret']);
    expect(fixture.events, ['verify jump.example', 'verify final.example']);
    expect(fixture.handlers['jump.example'], isNull);
    final handler = fixture.handlers['final.example']!;
    expect((await handler.handleRequest(Uint8List.fromList([11]))).first, 12);
    expect(fixture.agent.requests, hasLength(1));
    await fixture.service.disconnect(session.id);
    expect(await handler.handleRequest(Uint8List.fromList([11])), [5]);
  });

  test(
    'published route retains agent access after the opener lease ends',
    () async {
      var opening = true;
      final session = await fixture.service.connectWithAgent(
        'final.example',
        22,
        'user',
        forwardAgent: true,
        isCurrent: () => opening,
      );
      opening =
          false; // TerminalSession is now connected, no longer connecting.
      final handler = fixture.handlers['final.example']!;
      final request = agentSignRequest(
        fixtureAgentKey.toPublicKey().encode(),
        Uint8List.fromList(utf8.encode('remote SSH challenge')),
      );
      expect((await handler.handleRequest(request)).first, 14);
      await fixture.service.disconnect(session.id);
      expect(await handler.handleRequest(request), [5]);
      expect(
        fixture.agent.transports.every((transport) => transport.destroyed),
        isTrue,
      );
    },
  );

  test('outer host-key rejection never requests an agent signature', () async {
    fixture.rejectedHost = 'jump.example';
    await expectLater(
      fixture.service.connectWithAgent(
        'final.example',
        22,
        'user',
        jumpHosts: [_jump],
        forwardAgent: true,
      ),
      throwsA(isA<TerminalMountException>()),
    );
    expect(fixture.agent.requests.map((request) => request.first), [11]);
    expect(fixture.events, ['verify jump.example']);
    expect(fixture.agents.single.isClosed, isTrue);
    expect(fixture.service.getActiveSessions(), isEmpty);
    expect(fixture.clients.every((client) => client.isClosed), isTrue);
  });

  test(
    'final host-key rejection allows only the already verified jump signature',
    () async {
      fixture.rejectedHost = 'final.example';
      await expectLater(
        fixture.service.connectWithAgent(
          'final.example',
          22,
          'user',
          jumpHosts: [_jump],
        ),
        throwsA(isA<TerminalMountException>()),
      );
      expect(fixture.agent.requests.map((request) => request.first), [11, 13]);
      expect(fixture.events, [
        'verify jump.example',
        'sign jump.example',
        'verify final.example',
      ]);
      expect(fixture.agents.single.isClosed, isTrue);
      expect(fixture.service.getActiveSessions(), isEmpty);
    },
  );

  test('ordinary password routes never create an agent capability', () async {
    await fixture.service.connect('final.example', 22, 'user', 'secret');
    expect(fixture.agents, isEmpty);
    expect(fixture.agent.requests, isEmpty);
    expect(fixture.handlers.values, everyElement(isNull));
  });

  test('mixed agent jump and password final target do not change authentication intent', () async {
    await fixture.service.connect(
      'final.example',
      22,
      'user',
      'secret',
      jumpHosts: [_jump],
    );
    expect(fixture.passwords, [null, 'secret']);
    expect(fixture.events, [
      'verify jump.example',
      'sign jump.example',
      'verify final.example',
    ]);
    expect(fixture.handlers.values, everyElement(isNull));
  });

  test(
    'dispose cancels pending agent open and closes the late transport',
    () async {
      fixture.agent.opening = Completer<void>();
      final connecting = fixture.service.connectWithAgent(
        'final.example',
        22,
        'user',
      );
      final failed = expectLater(connecting, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await fixture.service.dispose();
      await failed;
      fixture.agent.opening!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.agent.transports.single.destroyed, isTrue);
      expect(fixture.agent.requests, isEmpty);
      expect(fixture.clients, isEmpty);
    },
  );

  test(
    'dispose during signature revokes local requests and publishes no session',
    () async {
      final signatureStarted = Completer<void>();
      final response = Completer<Uint8List>();
      fixture.agent.respond = (request) async {
        if (request.first == 11) {
          return fixture.agent.handler.handleRequest(request);
        }
        signatureStarted.complete();
        return response.future;
      };
      final connecting = fixture.service.connectWithAgent(
        'final.example',
        22,
        'user',
      );
      final failed = expectLater(connecting, throwsStateError);
      await signatureStarted.future;
      await fixture.service.dispose();
      await failed;
      response.complete(Uint8List.fromList([5]));
      expect(fixture.agents.single.isClosed, isTrue);
      expect(fixture.service.getActiveSessions(), isEmpty);
      expect(
        fixture.agent.transports.every((transport) => transport.destroyed),
        isTrue,
      );
    },
  );

  test('remote closure immediately revokes forwarding authority', () async {
    await fixture.service.connectWithAgent(
      'final.example',
      22,
      'user',
      forwardAgent: true,
    );
    final handler = fixture.handlers['final.example']!;
    await fixture.clients.single.close();
    await Future<void>.delayed(Duration.zero);
    expect(await handler.handleRequest(Uint8List.fromList([11])), [5]);
    expect(fixture.agents.single.isClosed, isTrue);
  });

  test('already canceled attempt never opens the local agent', () async {
    await expectLater(
      fixture.service.connectWithAgent(
        'final.example',
        22,
        'user',
        isCurrent: () => false,
      ),
      throwsStateError,
    );
    expect(fixture.agents, isEmpty);
    expect(fixture.agent.transports, isEmpty);
    expect(fixture.clients, isEmpty);
  });
}

class _RouteFixture {
  final agent = AgentFixture();
  final agents = <SshAgentConnection>[];
  final clients = <_Client>[];
  final events = <String>[];
  final passwords = <String?>[];
  final handlers = <String, SSHAgentHandler?>{};
  String? rejectedHost;

  late final service = SshTerminalService(
    secureStorage: InMemorySecureStorage(),
    confirmHostKey: (endpoint, fingerprint) async =>
        !endpoint.startsWith('${rejectedHost ?? 'unused'}:'),
    agentFactory: ({required isCurrent}) {
      final connection = agent.connection(current: isCurrent);
      agents.add(connection);
      return connection;
    },
    socketConnector: (host, port, {gateway}) async => _Socket(host),
    verifiedClientOpener:
        (
          socket, {
          required username,
          password,
          identities,
          agentHandler,
          required verify,
          onCreated,
        }) async {
          final named = socket as _Socket;
          final client = _Client(named);
          clients.add(client);
          onCreated?.call(client);
          handlers[named.host] = agentHandler;
          events.add('verify ${named.host}');
          if (!await verify(
            'ssh-ed25519',
            Uint8List.fromList(utf8.encode('SHA256:${'A' * 43}')),
          )) {
            throw StateError('Host key rejected');
          }
          passwords.add(password);
          if (identities != null) {
            events.add('sign ${named.host}');
            final challenge = Uint8List.fromList(
              utf8.encode('SSH challenge ${named.host}'),
            );
            expect(
              (await identities.single.sign(challenge)).encode(),
              fixtureAgentKey.sign(challenge).encode(),
            );
          }
          return client;
        },
  );
}

class _Socket implements SSHForwardChannel {
  _Socket(this.host);
  final String host;
  bool closed = false;
  @override
  void destroy() => closed = true;
  @override
  Future<void> close() async => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements SSHClient {
  _Client(this.socket);
  @override
  final _Socket socket;
  bool _closed = false;
  final _done = Completer<void>();
  @override
  bool get isClosed => _closed;
  @override
  Future<void> get authenticated => Future.value();
  @override
  Future<void> get done => _done.future;
  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async => _Socket(remoteHost);
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    socket.destroy();
    _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
