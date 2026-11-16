import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ssh_agent.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_agent_fixture.dart';

Matcher agentError(String message) => isA<SshAgentException>().having(
  (error) => error.message,
  'message',
  message,
);

void main() {
  final data = Uint8List.fromList(utf8.encode('SSH challenge 日本語'));

  test('agent identities probe before signing and return actual Ed25519 signatures', () async {
    final fixture = AgentFixture();
    final agent = fixture.connection();
    addTearDown(agent.close);
    final identities = await agent.loadIdentities();
    expect(identities, hasLength(1));
    final identity = identities.single;
    expect(identity.type, 'ssh-ed25519');
    expect(identity.shouldProbe, isTrue);
    expect(
      identity.toPublicKey().encode(),
      fixtureAgentKey.toPublicKey().encode(),
    );
    expect(fixture.requests.map((request) => request.first), [11]);
    expect(
      (await identity.sign(data)).encode(),
      fixtureAgentKey.sign(data).encode(),
    );
    expect(fixture.requests.map((request) => request.first), [11, 13]);
    expect(fixture.transports.every((socket) => socket.destroyed), isTrue);
  });

  test('identity and signature frames survive every split and bytewise fragmentation', () async {
    final answer = await AgentFixture().handler.handleRequest(
      Uint8List.fromList([11]),
    );
    final length = agentFrame(answer).length;
    for (var split = 0; split <= length; split++) {
      final fixture = AgentFixture()
        ..chunks = (bytes) {
          final point = split.clamp(0, bytes.length);
          return [bytes.sublist(0, point), bytes.sublist(point)];
        };
      final agent = fixture.connection();
      final identity = (await agent.loadIdentities()).single;
      expect(
        (await identity.sign(data)).encode(),
        fixtureAgentKey.sign(data).encode(),
      );
      agent.close();
    }
    final fixture = AgentFixture()
      ..chunks = (bytes) => bytes.map((byte) => [byte]).toList();
    final agent = fixture.connection();
    final identity = (await agent.loadIdentities()).single;
    expect(
      (await identity.sign(data)).encode(),
      fixtureAgentKey.sign(data).encode(),
    );
    agent.close();
  });

  test(
    'empty signing payloads retain normal agent protocol semantics',
    () async {
      final fixture = AgentFixture();
      final agent = fixture.connection();
      final identity = (await agent.loadIdentities()).single;
      final empty = Uint8List(0);
      expect(
        (await identity.sign(empty)).encode(),
        fixtureAgentKey.sign(empty).encode(),
      );
      final request = agentSignRequest(identity.toPublicKey().encode(), empty);
      expect(
        await agent.handleRequest(request),
        await fixture.handler.handleRequest(request),
      );
      agent.close();
    },
  );

  test('parallel identity reads share one frozen snapshot', () async {
    final fixture = AgentFixture();
    final agent = fixture.connection();
    final values = await Future.wait([
      agent.loadIdentities(),
      agent.loadIdentities(),
    ]);
    expect(identical(values.first, values.last), isTrue);
    expect(fixture.requests, hasLength(1));
    final public = fixtureAgentKey.toPublicKey().encode();
    fixture.respond = (_) async => agentIdentityResponse([
      public,
      Uint8List.fromList([...public.take(public.length - 1), public.last ^ 1]),
    ]);
    final forwarded = await agent.handleRequest(Uint8List.fromList([11]));
    expect(ByteData.sublistView(forwarded, 1, 5).getUint32(0), 1);
    expect(fixture.requests, hasLength(1));
    agent.close();
  });

  test(
    'unknown key families skip and duplicate public keys are exposed once',
    () async {
      final fixture = AgentFixture()
        ..respond = (_) async => agentIdentityResponse([
          agentString(utf8.encode('unsupported-key')),
          fixtureAgentKey.toPublicKey().encode(),
          fixtureAgentKey.toPublicKey().encode(),
        ]);
      final agent = fixture.connection();
      expect(await agent.loadIdentities(), hasLength(1));
      agent.close();
    },
  );

  test(
    'empty agents and unsupported-only agents fail without password fallback',
    () async {
      for (final keys in <List<Uint8List>>[
        [],
        [agentString(utf8.encode('ssh-dss'))],
      ]) {
        final fixture = AgentFixture()
          ..respond = (_) async => agentIdentityResponse(keys);
        final agent = fixture.connection();
        await expectLater(
          agent.loadIdentities(),
          throwsA(agentError(SshAgentException.empty)),
        );
        expect(fixture.requests.map((request) => request.first), [11]);
        agent.close();
      }
    },
  );

  test('malformed identity responses reject before exposing any key', () async {
    final valid = agentIdentityResponse([
      fixtureAgentKey.toPublicKey().encode(),
    ]);
    for (final payload in <List<int>>[
      [],
      [5],
      [12, 0, 0, 0],
      [12, ...agentUint32(65)],
      [
        12,
        ...agentUint32(1),
        ...agentUint32(SshAgentConnection.maximumKeyLength + 1),
      ],
      [
        12,
        ...agentUint32(1),
        ...agentString([0]),
      ],
      [
        12,
        ...agentUint32(1),
        ...agentString(fixtureAgentKey.toPublicKey().encode()),
        ...agentUint32(1025),
      ],
      [...valid, 0],
      [
        12,
        ...agentUint32(1),
        ...agentString(fixtureAgentKey.toPublicKey().encode()),
        ...agentString([255]),
      ],
    ]) {
      final fixture = AgentFixture()
        ..respond = (_) async => Uint8List.fromList(payload);
      final agent = fixture.connection();
      await expectLater(
        agent.loadIdentities(),
        throwsA(agentError(SshAgentException.invalid)),
      );
      expect(await agent.handleRequest(Uint8List.fromList([11])), [5]);
      expect(fixture.transports.every((socket) => socket.destroyed), isTrue);
      agent.close();
    }
  });

  test(
    'oversized, zero, truncated and trailing frame bytes are rejected',
    () async {
      for (final frame in <Uint8List Function(Uint8List)>[
        (_) => agentUint32(0),
        (_) => agentUint32(SshAgentConnection.maximumFrameLength + 1),
        (_) => Uint8List.fromList([0, 0, 1]),
        (_) => Uint8List.fromList([...agentUint32(3), 12]),
        (payload) => Uint8List.fromList([...agentFrame(payload), 0]),
      ]) {
        final fixture = AgentFixture()
          ..frame = frame
          ..closeAfterResponse = true;
        final agent = fixture.connection();
        await expectLater(
          agent.loadIdentities(),
          throwsA(agentError(SshAgentException.invalid)),
        );
        expect(fixture.transports.every((socket) => socket.destroyed), isTrue);
        agent.close();
      }
    },
  );

  test(
    'RSA uses SHA2 authentication algorithms and exact agent signing flags',
    () async {
      final key = Uint8List.fromList([
        ...agentString(utf8.encode('ssh-rsa')),
        ...agentString([1, 0, 1]),
        ...agentString([0, ...List.filled(256, 128)]),
      ]);
      final fixture = AgentFixture()
        ..respond = (request) async {
          if (request.first == 11) return agentIdentityResponse([key]);
          final flags = ByteData.sublistView(
            request,
            request.length - 4,
          ).getUint32(0);
          final type = flags == 4 ? 'rsa-sha2-512' : 'rsa-sha2-256';
          return _signature(type, List.filled(256, 1));
        };
      final agent = fixture.connection();
      final identities = await agent.loadIdentities();
      expect(identities.map((identity) => identity.type), [
        'rsa-sha2-512',
        'rsa-sha2-256',
      ]);
      for (final identity in identities) {
        expect(
          SSHSignature.getType((await identity.sign(data)).encode()),
          identity.type,
        );
        expect(identity.toPublicKey().encode(), key);
      }
      expect(
        fixture.requests
            .skip(1)
            .map(
              (request) => ByteData.sublistView(
                request,
                request.length - 4,
              ).getUint32(0),
            ),
        [4, 2],
      );
      for (final flags in [0, 1, 3, 6, 8]) {
        expect(
          await agent.handleRequest(agentSignRequest(key, data, flags: flags)),
          [5],
        );
      }
      expect(fixture.requests, hasLength(3));
      agent.close();
    },
  );

  test(
    'ECDSA curves validate their point geometry and signature components',
    () async {
      for (final (curve, size) in [
        ('nistp256', 65),
        ('nistp384', 97),
        ('nistp521', 133),
      ]) {
        final key = Uint8List.fromList([
          ...agentString(utf8.encode('ecdsa-sha2-$curve')),
          ...agentString(utf8.encode(curve)),
          ...agentString([4, ...List.filled(size - 1, 1)]),
        ]);
        final fixture = AgentFixture()
          ..respond = (request) async => request.first == 11
              ? agentIdentityResponse([key])
              : _signature('ecdsa-sha2-$curve', [
                  ...agentString([1]),
                  ...agentString([2]),
                ]);
        final agent = fixture.connection();
        final identity = (await agent.loadIdentities()).single;
        expect(
          SSHSignature.getType((await identity.sign(data)).encode()),
          'ecdsa-sha2-$curve',
        );
        agent.close();
      }
    },
  );

  test(
    'sign refusal is distinct; wrong types, lengths and trailing bytes reject',
    () async {
      for (final (reply, error) in <(Uint8List, String)>[
        (Uint8List.fromList([5]), SshAgentException.refused),
        (
          _signature('rsa-sha2-512', List.filled(64, 1)),
          SshAgentException.invalid,
        ),
        (
          _signature('ssh-ed25519', List.filled(63, 1)),
          SshAgentException.invalid,
        ),
        (
          Uint8List.fromList([14, ...agentUint32(99999)]),
          SshAgentException.invalid,
        ),
        (Uint8List.fromList([5, 0]), SshAgentException.invalid),
        (
          Uint8List.fromList([
            ..._signature('ssh-ed25519', List.filled(64, 1)),
            0,
          ]),
          SshAgentException.invalid,
        ),
      ]) {
        final fixture = AgentFixture();
        final agent = fixture.connection();
        final identity = (await agent.loadIdentities()).single;
        fixture.respond = (_) async => reply;
        await expectLater(
          Future(() => identity.sign(data)),
          throwsA(agentError(error)),
        );
        expect(
          await agent.handleRequest(
            agentSignRequest(identity.toPublicKey().encode(), data),
          ),
          [5],
        );
        agent.close();
      }
    },
  );

  test(
    'forwarding allows only frozen keys, list and sign with exact flags',
    () async {
      final fixture = AgentFixture();
      final agent = fixture.connection();
      final identity = (await agent.loadIdentities()).single;
      for (final request in <List<int>>[
        [],
        [11, 0],
        [13],
        [17],
        [18],
        [19],
        [20],
        [22],
        [23],
        [27],
        [255],
        agentSignRequest(Uint8List.fromList([1, 2, 3]), data),
        agentSignRequest(identity.toPublicKey().encode(), data, flags: 4),
        [...agentSignRequest(identity.toPublicKey().encode(), data), 0],
      ]) {
        expect(await agent.handleRequest(Uint8List.fromList(request)), [5]);
      }
      expect(fixture.requests, hasLength(1));
      final result = await agent.handleRequest(
        agentSignRequest(identity.toPublicKey().encode(), data),
      );
      expect(
        result,
        await fixture.handler.handleRequest(
          agentSignRequest(identity.toPublicKey().encode(), data),
        ),
      );
      expect(fixture.requests, hasLength(2));
      agent.close();
      expect(await agent.handleRequest(Uint8List.fromList([11])), [5]);
    },
  );

  test(
    'forwarding rate limit resets and identity listing never queries new keys',
    () async {
      var now = DateTime.utc(2026);
      final fixture = AgentFixture();
      final agent = fixture.connection(clock: () => now);
      await agent.loadIdentities();
      for (
        var i = 0;
        i < SshAgentConnection.maximumForwardRequestsPerSecond;
        i++
      ) {
        expect((await agent.handleRequest(Uint8List.fromList([11]))).first, 12);
      }
      expect(await agent.handleRequest(Uint8List.fromList([11])), [5]);
      now = now.add(const Duration(seconds: 1));
      expect((await agent.handleRequest(Uint8List.fromList([11]))).first, 12);
      expect(fixture.requests, hasLength(1));
      agent.close();
    },
  );

  test(
    'oversized signing data is rejected before touching the agent',
    () async {
      final fixture = AgentFixture();
      final agent = fixture.connection();
      final identity = (await agent.loadIdentities()).single;
      for (final input in [
        Uint8List(SshAgentConnection.maximumSigningDataLength + 1),
      ]) {
        await expectLater(
          Future(() => identity.sign(input)),
          throwsA(agentError(SshAgentException.invalid)),
        );
      }
      expect(fixture.requests, hasLength(1));
      agent.close();
    },
  );

  test('local request concurrency cap includes pending connections', () async {
    final fixture = AgentFixture();
    final agent = fixture.connection();
    final identity = (await agent.loadIdentities()).single;
    final release = Completer<void>();
    fixture.opening = release;
    final pending = [
      for (var i = 0; i < 4; i++)
        Future<SSHSignature>.value(identity.sign(data)),
    ];
    await expectLater(
      Future(() => identity.sign(data)),
      throwsA(agentError(SshAgentException.busy)),
    );
    release.complete();
    expect(await Future.wait(pending), hasLength(4));
    agent.close();
    expect(fixture.transports.every((socket) => socket.destroyed), isTrue);
  });

  test('timeout destroys active sockets and reports a stable error', () async {
    final fixture = AgentFixture()
      ..respond = (_) => Completer<Uint8List>().future;
    final agent = fixture.connection(timeout: const Duration(milliseconds: 30));
    await expectLater(
      agent.loadIdentities(),
      throwsA(agentError(SshAgentException.timeout)),
    );
    expect(fixture.transports.single.destroyed, isTrue);
    agent.close();
  });

  test(
    'cancel during pending open closes its late socket without writing',
    () async {
      final gate = Completer<void>();
      final fixture = AgentFixture()..opening = gate;
      final agent = fixture.connection();
      final load = agent.loadIdentities();
      final failed = expectLater(
        load,
        throwsA(agentError(SshAgentException.closed)),
      );
      agent.close();
      await failed;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transports.single.destroyed, isTrue);
      expect(fixture.requests, isEmpty);
    },
  );

  test(
    'timeout during open closes a late socket without using its response',
    () async {
      final gate = Completer<void>();
      final fixture = AgentFixture()..opening = gate;
      final agent = fixture.connection(
        timeout: const Duration(milliseconds: 30),
      );
      await expectLater(
        agent.loadIdentities(),
        throwsA(agentError(SshAgentException.timeout)),
      );
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transports.single.destroyed, isTrue);
      expect(fixture.requests, isEmpty);
      agent.close();
    },
  );

  test(
    'cancel during signature immediately revokes future authority',
    () async {
      final fixture = AgentFixture();
      final agent = fixture.connection();
      final identity = (await agent.loadIdentities()).single;
      final reply = Completer<Uint8List>();
      fixture.respond = (_) => reply.future;
      final pending = identity.sign(data);
      final failed = expectLater(
        Future<SSHSignature>.value(pending),
        throwsA(agentError(SshAgentException.closed)),
      );
      agent.close();
      await failed;
      reply.complete(_signature('ssh-ed25519', List.filled(64, 1)));
      await Future<void>.delayed(Duration.zero);
      expect(fixture.transports.every((socket) => socket.destroyed), isTrue);
      await expectLater(
        Future(() => identity.sign(data)),
        throwsA(agentError(SshAgentException.closed)),
      );
      expect(await agent.handleRequest(Uint8List.fromList([11])), [5]);
    },
  );

  test('expired caller lease refuses signing without a socket', () async {
    var current = true;
    final fixture = AgentFixture();
    final agent = fixture.connection(current: () => current);
    final identity = (await agent.loadIdentities()).single;
    current = false;
    await expectLater(
      Future(() => identity.sign(data)),
      throwsA(agentError(SshAgentException.closed)),
    );
    expect(await agent.handleRequest(Uint8List.fromList([11])), [5]);
    expect(fixture.requests, hasLength(1));
    agent.close();
  });

  test('connection failures hide transport details and socket paths', () async {
    final agent = SshAgentConnection(
      connect: () async => throw StateError('/private/ssh-agent-secret-path'),
      isCurrent: () => true,
    );
    await expectLater(
      agent.loadIdentities(),
      throwsA(agentError(SshAgentException.connection)),
    );
    agent.close();
  });
}

Uint8List _signature(String type, List<int> bytes) => Uint8List.fromList([
  14,
  ...agentString([...agentString(utf8.encode(type)), ...agentString(bytes)]),
]);
