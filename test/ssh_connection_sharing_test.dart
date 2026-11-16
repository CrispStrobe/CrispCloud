import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/ssh_jump_host.dart';
import 'package:crisp_cloud/models/tmux_session_options.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_agent.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

import 'support/ssh_agent_fixture.dart';

final Uri? _gateway = kIsWeb ? Uri.parse('wss://gateway.example/ssh') : null;

void main() {
  group('explicit SSH connection sharing', () {
    late SshTerminalService service;
    late List<_Client> clients;

    setUp(() {
      clients = [];
      service = SshTerminalService(
        secureStorage: InMemorySecureStorage(),
        clientConnector:
            (_, __, {required username, password, identities, gateway}) async {
              final client = _Client();
              clients.add(client);
              return client;
            },
      );
    });
    tearDown(() async => service.dispose());

    Future<SshSession> connect([String host = 'shared.example']) =>
        service.connect(host, 2222, 'alice', 'never-copied', gateway: _gateway);

    test(
      'copies endpoint metadata into a fresh ID without another login',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        expect(clients, hasLength(1));
        expect(sibling.id, isNot(source.id));
        expect(sibling.host, source.host);
        expect(sibling.port, source.port);
        expect(sibling.username, source.username);
        expect(sibling.connected, isTrue);
        expect(jsonEncode(sibling.toJson()), isNot(contains('never-copied')));
        expect(service.getActiveSessions().map((s) => s.id).toSet(), {
          source.id,
          sibling.id,
        });
        expect(service.connectionSessionCount(source.id), 2);
        expect(service.connectionSessionCount(sibling.id), 2);
      },
    );

    test(
      'sharing reserves its lease before yielding to source disconnect',
      () async {
        final source = await connect();
        final sharing = service.shareSession(source.id);
        expect(service.connectionSessionCount(source.id), 2);
        await service.disconnect(source.id);
        final sibling = await sharing;
        expect(clients.single.isClosed, isFalse);
        expect(service.canShareSession(source.id), isFalse);
        expect(service.canShareSession(sibling.id), isTrue);
        expect(await service.execute(sibling.id, 'survivor'), 'survivor');
      },
    );

    test(
      'identical destinations remain independent unless explicitly shared',
      () async {
        final first = await connect();
        final second = await connect();
        expect(clients, hasLength(2));
        expect(service.connectionSessionCount(first.id), 1);
        expect(service.connectionSessionCount(second.id), 1);
        await service.disconnect(first.id);
        expect(clients.first.isClosed, isTrue);
        expect(clients.last.isClosed, isFalse);
        expect(await service.execute(second.id, 'other-login'), 'other-login');
      },
    );

    test(
      'sibling shells isolate Unicode output, input, geometry, and exits',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final first = await service.startShell(
          source.id,
          width: 93,
          height: 27,
        );
        final second = await service.startShell(
          sibling.id,
          width: 121,
          height: 39,
        );
        final firstText = first.join();
        final secondText = second.join();
        final client = clients.single;
        expect(client.ptyRequests.map((p) => (p!.width, p.height)), [
          (93, 27),
          (121, 39),
        ]);
        final left = client.shells[0];
        final right = client.shells[1];
        final leftBytes = utf8.encode('left-✓-日本語\r\n');
        final rightBytes = utf8.encode('right-Grüße-🌍\r\n');
        for (var i = 0; i < leftBytes.length || i < rightBytes.length; i++) {
          if (i < leftBytes.length) {
            left.output.add(Uint8List.fromList([leftBytes[i]]));
          }
          if (i < rightBytes.length) {
            right.output.add(Uint8List.fromList([rightBytes[i]]));
          }
        }
        await service.writeToShell(source.id, 'left\x1b[A\r');
        await service.writeToShell(sibling.id, 'right-✓\t\r');
        await service.resizeTerminal(source.id, 77, 23);
        await service.resizeTerminal(sibling.id, 109, 33);
        await _flush();
        expect(
          left.received.expand((bytes) => bytes),
          utf8.encode('left\x1b[A\r'),
        );
        expect(
          right.received.expand((bytes) => bytes),
          utf8.encode('right-✓\t\r'),
        );
        expect(left.resizes, [(77, 23)]);
        expect(right.resizes, [(109, 33)]);

        await left.finish(7);
        expect(await firstText, utf8.decode(leftBytes));
        expect(await (first as SshShellOutput).exitCode, 7);
        await _flush();
        expect(client.isClosed, isFalse);
        expect(service.getActiveSessions().single.id, sibling.id);
        await service.writeToShell(sibling.id, 'still-here\r');
        await _flush();
        expect(right.received.last, utf8.encode('still-here\r'));
        await right.finish(3);
        expect(await secondText, utf8.decode(rightBytes));
        expect(await (second as SshShellOutput).exitCode, 3);
        await _flush();
        expect(client.closeCalls, 1);
        expect(service.getActiveSessions(), isEmpty);
      },
    );

    test(
      'canceling one output subscription releases only that shell lease',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final first = (await service.startShell(source.id)).listen((_) {});
        final second = (await service.startShell(sibling.id)).listen((_) {});
        await first.cancel();
        expect(clients.single.shells.first.closed, isTrue);
        expect(clients.single.shells.last.closed, isFalse);
        expect(clients.single.isClosed, isFalse);
        await service.writeToShell(sibling.id, 'survives\r');
        await _flush();
        expect(
          clients.single.shells.last.received.single,
          utf8.encode('survives\r'),
        );
        await second.cancel();
        expect(clients.single.closeCalls, 1);
      },
    );

    test(
      'EOF and late exit status release one shell without disturbing a peer',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final stream = await service.startShell(source.id);
        final text = stream.join();
        final channel = clients.single.shells.single;
        channel.output.add(Uint8List.fromList(utf8.encode('final-✓')));
        await Future.wait([channel.output.close(), channel.errors.close()]);
        expect(await text, 'final-✓');
        expect(service.getActiveSessions(), hasLength(2));
        expect(
          await service.execute(sibling.id, 'before-status'),
          'before-status',
        );
        channel.completeChannel(17);
        expect(await (stream as SshShellOutput).exitCode, 17);
        await _flush();
        expect(service.getActiveSessions().single.id, sibling.id);
        expect(clients.single.isClosed, isFalse);
      },
    );

    test(
      'failed sibling channel setup preserves the source and route capacity',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final pending = Completer<SSHSession>();
        clients.single.pendingShell = pending.future;
        final starting = service.startShell(sibling.id);
        final failed = expectLater(starting, throwsStateError);
        await _flush();
        pending.completeError(StateError('server refused a second PTY'));
        await failed;
        expect(service.getActiveSessions().single.id, source.id);
        expect(service.connectionSessionCount(source.id), 1);
        expect(clients.single.isClosed, isFalse);
        expect(
          await service.execute(source.id, 'source-still-live'),
          'source-still-live',
        );
      },
    );

    test(
      'source can close while the independently leased sibling channel opens',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final pending = Completer<SSHSession>();
        clients.single.pendingShell = pending.future;
        final starting = service.startShell(sibling.id);
        await _flush();
        await service.disconnect(source.id);
        expect(clients.single.isClosed, isFalse);
        final channel = _Shell();
        pending.complete(channel);
        final subscription = (await starting).listen((_) {});
        await service.writeToShell(sibling.id, 'late-but-owned\r');
        await _flush();
        expect(channel.closed, isFalse);
        expect(channel.received.single, utf8.encode('late-but-owned\r'));
        await subscription.cancel();
        expect(clients.single.closeCalls, 1);
      },
    );

    test('canceling a pending sibling closes its late channel but keeps the source', () async {
      final source = await connect();
      final sibling = await service.shareSession(source.id);
      final pending = Completer<SSHSession>();
      clients.single.pendingShell = pending.future;
      final starting = service.startShell(sibling.id);
      final rejected = expectLater(starting, throwsStateError);
      await _flush();
      await service.disconnect(sibling.id);
      await rejected.timeout(const Duration(seconds: 2));
      final late = _Shell();
      pending.complete(late);
      await _flush();
      expect(late.closed, isTrue);
      expect(clients.single.isClosed, isFalse);
      expect(service.connectionSessionCount(source.id), 1);
      expect(await service.execute(source.id, 'not-canceled'), 'not-canceled');
    });

    test(
      'replacement rejects a pending opener before its late shell arrives',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final pending = Completer<SSHSession>();
        clients.single.pendingShell = pending.future;
        final oldOpening = service.startShell(source.id);
        final rejected = expectLater(oldOpening, throwsStateError);
        await _flush();
        final replacement = (await service.startShell(source.id))
            .listen((_) {});
        await rejected.timeout(const Duration(seconds: 2));
        final late = _Shell();
        pending.complete(late);
        await _flush();
        expect(late.closed, isTrue);
        await service.writeToShell(source.id, 'replacement-input');
        await _flush();
        expect(
          clients.single.shells.first.received.single,
          utf8.encode('replacement-input'),
        );
        expect(
          await service.execute(sibling.id, 'sibling-remains'),
          'sibling-remains',
        );
        expect(clients.single.isClosed, isFalse);
        await replacement.cancel();
        expect(clients.single.isClosed, isFalse);
      },
    );

    test('native control cancellation rejects promptly and closes its late channel', () async {
      final source = await connect();
      final sibling = await service.shareSession(source.id);
      final pending = Completer<SSHSession>();
      clients.single.pendingExecution = pending.future;
      final opening = service.startTmuxControl(
        source.id,
        tmux: const TmuxSessionOptions(sessionName: 'work', controlMode: true),
      );
      final rejected = expectLater(opening, throwsStateError);
      await _flush();
      await service.disconnect(source.id);
      await rejected.timeout(const Duration(seconds: 2));
      final late = _Shell();
      pending.complete(late);
      await _flush();
      expect(late.closed, isTrue);
      expect(clients.single.isClosed, isFalse);
      expect(
        await service.execute(sibling.id, 'shell-survives-control-cancel'),
        'shell-survives-control-cancel',
      );
    });

    test(
      'replacing one shell cannot close its peer or its own replacement',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final old = await service.startShell(source.id);
        final oldDrained = old.drain<void>();
        final peer = (await service.startShell(sibling.id)).listen((_) {});
        final next = (await service.startShell(source.id)).listen((_) {});
        await oldDrained;
        expect(clients.single.shells.map((shell) => shell.closed), [
          true,
          false,
          false,
        ]);
        await service.writeToShell(source.id, 'replacement\r');
        await service.writeToShell(sibling.id, 'peer\r');
        await _flush();
        expect(clients.single.shells[1].received.single, utf8.encode('peer\r'));
        expect(
          clients.single.shells[2].received.single,
          utf8.encode('replacement\r'),
        );
        await next.cancel();
        expect(clients.single.isClosed, isFalse);
        await peer.cancel();
        expect(clients.single.closeCalls, 1);
      },
    );

    test(
      'native tmux lease and ordinary shell have independent teardown',
      () async {
        final source = await connect();
        final control = await service.startTmuxControl(
          source.id,
          tmux: const TmuxSessionOptions(
            sessionName: 'work',
            controlMode: true,
          ),
        );
        final controlSubscription = control.output.listen((_) {});
        final sibling = await service.shareSession(source.id);
        final shell = (await service.startShell(sibling.id)).listen((_) {});
        expect(clients.single.commands, [
          "exec tmux -C new-session -A -s 'work'",
        ]);
        expect(clients.single.ptyRequests.first, isNull);
        expect(clients.single.ptyRequests.last, isNotNull);
        await control.close();
        expect(clients.single.isClosed, isFalse);
        await service.writeToShell(sibling.id, 'plain-shell\r');
        await _flush();
        expect(
          clients.single.shells.last.received.single,
          utf8.encode('plain-shell\r'),
        );
        await controlSubscription.cancel();
        await shell.cancel();
        expect(clients.single.closeCalls, 1);
      },
    );

    test(
      'forwarding manager belongs to the route until its final lease closes',
      () async {
        final source = await connect();
        final manager = service.forwarding(source.id);
        final sibling = await service.shareSession(source.id);
        expect(service.forwarding(sibling.id), same(manager));
        await service.disconnect(source.id);
        expect(manager.isClosed, isFalse);
        expect(service.forwarding(sibling.id), same(manager));
        await service.disconnect(sibling.id);
        expect(manager.isClosed, isTrue);
        expect(clients.single.closeCalls, 1);
      },
      skip: !SshPortForwarding.supported,
    );

    test(
      'unknown, disconnected and canceled sources cannot grant a lease',
      () async {
        final source = await connect();
        expect(service.canShareSession('unknown'), isFalse);
        expect(service.connectionSessionCount('unknown'), 0);
        await expectLater(
          service.shareSession('unknown'),
          throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
        );
        await expectLater(
          service.shareSession(source.id, isCurrent: () => false),
          throwsStateError,
        );
        expect(service.connectionSessionCount(source.id), 1);
        await service.disconnect(source.id);
        expect(service.canShareSession(source.id), isFalse);
        await expectLater(
          service.shareSession(source.id),
          throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
        );
        expect(service.getActiveSessions(), isEmpty);
        expect(clients, hasLength(1));
      },
    );

    test(
      'eight logical sessions per route still allow five distinct connections',
      () async {
        final groups = <List<SshSession>>[];
        for (var route = 0; route < SshTerminalService.maxSessions; route++) {
          final source = await connect('route-$route.example');
          final sessions = [source];
          for (var i = 1; i < SshTerminalService.maxSharedSessions; i++) {
            sessions.add(await service.shareSession(source.id));
          }
          groups.add(sessions);
          expect(
            service.connectionSessionCount(source.id),
            SshTerminalService.maxSharedSessions,
          );
          expect(service.canShareSession(source.id), isFalse);
          await expectLater(service.shareSession(source.id), throwsStateError);
        }
        expect(clients, hasLength(SshTerminalService.maxSessions));
        expect(service.getActiveSessions(), hasLength(40));
        await expectLater(connect('sixth.example'), throwsStateError);
        await service.disconnect(groups.first.first.id);
        await expectLater(connect('still-sixth.example'), throwsStateError);
        for (final session in groups.first.skip(1)) {
          await service.disconnect(session.id);
        }
        expect(clients.first.closeCalls, 1);
        final replacement = await connect('replacement.example');
        expect(replacement.connected, isTrue);
        expect(clients, hasLength(6));
      },
    );

    test(
      'parallel share calls reserve capacity before awaiting their results',
      () async {
        final source = await connect();
        final shares = [
          for (var i = 1; i < SshTerminalService.maxSharedSessions; i++)
            service.shareSession(source.id),
        ];
        await expectLater(service.shareSession(source.id), throwsStateError);
        final siblings = await Future.wait(shares);
        expect(siblings.map((s) => s.id).toSet(), hasLength(7));
        expect(service.connectionSessionCount(source.id), 8);
        expect(clients, hasLength(1));
      },
    );

    test(
      'closing a logical session cancels its active execute channel only',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        clients.single.holdNextExecution = true;
        final executing = service.execute(source.id, 'hold-source');
        final canceled = expectLater(
          executing,
          throwsA(anyOf(isA<StateError>(), isA<TerminalMountException>())),
        );
        await _flush();
        final channel = clients.single.shells.single;
        await service.disconnect(source.id);
        await canceled;
        expect(channel.closed, isTrue);
        expect(clients.single.isClosed, isFalse);
        expect(
          await service.execute(sibling.id, 'independent-execute'),
          'independent-execute',
        );
      },
    );

    test(
      'a late execute channel is released when only its session was closed',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final pending = Completer<SSHSession>();
        clients.single.pendingExecution = pending.future;
        final executing = service.execute(source.id, 'pending-source');
        final canceled = expectLater(
          executing,
          throwsA(anyOf(isA<StateError>(), isA<TerminalMountException>())),
        );
        await _flush();
        await service.disconnect(source.id);
        await canceled.timeout(const Duration(seconds: 2));
        final late = _Shell();
        pending.complete(late);
        await _flush();
        expect(late.closed, isTrue);
        expect(clients.single.isClosed, isFalse);
        expect(
          await service.execute(sibling.id, 'peer-still-owns-route'),
          'peer-still-owns-route',
        );
      },
    );

    test(
      'activity on one sibling keeps every lease until the route idles',
      () async {
        final time = _ManualIdleClock();
        await service.dispose();
        await time.run(() async {
          service = SshTerminalService(
            secureStorage: InMemorySecureStorage(),
            clock: () => time.now,
            clientConnector:
                (
                  _,
                  __, {
                  required username,
                  password,
                  identities,
                  gateway,
                }) async {
                  final client = _Client();
                  clients.add(client);
                  return client;
                },
          );
          final source = await connect();
          final sibling = await service.shareSession(source.id);
          final output = (await service.startShell(sibling.id)).listen((_) {});
          time.advance(const Duration(minutes: 29));
          await service.writeToShell(sibling.id, 'activity');
          time.advance(const Duration(minutes: 29));
          time.sweep();
          await _flush();
          expect(service.getActiveSessions(), hasLength(2));
          expect(clients.single.isClosed, isFalse);
          time.advance(const Duration(minutes: 2));
          time.sweep();
          await _flush();
          await service.disconnect(sibling.id);
          expect(service.getActiveSessions(), isEmpty);
          expect(clients.single.closeCalls, 1);
          await output.cancel();
          await service.dispose();
        });
      },
    );

    test(
      'forwarding activity refreshes the route after its creator closes',
      () async {
        final time = _ManualIdleClock();
        await service.dispose();
        await time.run(() async {
          service = SshTerminalService(
            secureStorage: InMemorySecureStorage(),
            clock: () => time.now,
            clientConnector:
                (
                  _,
                  __, {
                  required username,
                  password,
                  identities,
                  gateway,
                }) async {
                  final client = _Client();
                  clients.add(client);
                  return client;
                },
          );
          final source = await connect();
          final manager = service.forwarding(source.id);
          final sibling = await service.shareSession(source.id);
          await service.disconnect(source.id);
          time.advance(const Duration(minutes: 29));
          await manager.start(
            SshPortForwardSpec(
              kind: SshPortForwardKind.remote,
              targetHost: '127.0.0.1',
              targetPort: 9999,
            ),
          );
          time.advance(const Duration(minutes: 29));
          time.sweep();
          await _flush();
          expect(service.getActiveSessions().single.id, sibling.id);
          expect(manager.isClosed, isFalse);
          time.advance(const Duration(minutes: 2));
          time.sweep();
          await _flush();
          expect(service.getActiveSessions(), isEmpty);
          expect(manager.isClosed, isTrue);
          await service.disconnect(sibling.id);
          expect(clients.single.closeCalls, 1);
          await service.dispose();
        });
      },
      skip: !SshPortForwarding.supported,
    );

    test('disconnectAll releases every shared route exactly once', () async {
      final first = await connect('one.example');
      final firstSibling = await service.shareSession(first.id);
      final second = await connect('two.example');
      final secondSibling = await service.shareSession(second.id);
      final subscriptions = [
        for (final session in [first, firstSibling, second, secondSibling])
          (await service.startShell(session.id)).listen((_) {}),
      ];
      await service.disconnectAll();
      expect(service.getActiveSessions(), isEmpty);
      expect(clients.map((client) => client.closeCalls), [1, 1]);
      expect(
        clients.expand((client) => client.shells).every((s) => s.closed),
        isTrue,
      );
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await service.disconnectAll();
      expect(clients.map((client) => client.closeCalls), [1, 1]);
    });

    test(
      'transport failure revokes all leases while each output drains',
      () async {
        final source = await connect();
        final sibling = await service.shareSession(source.id);
        final first = (await service.startShell(source.id)).join();
        final second = (await service.startShell(sibling.id)).join();
        final client = clients.single;
        client.endTransport();
        await _flush();
        expect(service.getActiveSessions(), isEmpty);
        expect(service.canShareSession(source.id), isFalse);
        expect(service.canShareSession(sibling.id), isFalse);
        client.shells[0].output.add(
          Uint8List.fromList(utf8.encode('source final-✓')),
        );
        client.shells[1].output.add(
          Uint8List.fromList(utf8.encode('sibling final-日本語')),
        );
        await Future.wait([for (final shell in client.shells) shell.finish()]);
        expect(await first, 'source final-✓');
        expect(await second, 'sibling final-日本語');
        await _flush();
        expect(client.closeCalls, 1);
      },
    );
  });

  group('shared SSH agent authority', () {
    test('sharing never reauthenticates and retains final-host permission to last lease', () async {
      final fixture = _AgentHarness();
      addTearDown(fixture.service.dispose);
      final source = await fixture.service.connectWithAgent(
        'final.example',
        22,
        'alice',
        gateway: _gateway,
        forwardAgent: true,
        jumpHosts: [
          const SshJumpHost(
            host: 'jump.example',
            username: 'jump-user',
            authentication: SshTerminalAuthentication.agent,
          ),
        ],
      );
      final sibling = await fixture.service.shareSession(source.id);
      expect(fixture.clients, hasLength(2));
      expect(fixture.events, [
        'verify jump.example',
        'sign jump.example',
        'verify final.example',
        'sign final.example',
      ]);
      expect(fixture.agent.requests.map((request) => request.first), [
        11,
        13,
        13,
      ]);
      expect(fixture.handlers['jump.example'], isNull);
      final handler = fixture.handlers['final.example']!;
      await fixture.service.disconnect(source.id);
      expect(fixture.agents.single.isClosed, isFalse);
      expect(fixture.clients.every((client) => !client.isClosed), isTrue);
      final request = agentSignRequest(
        fixtureAgentKey.toPublicKey().encode(),
        Uint8List.fromList(utf8.encode('sibling-authorized-challenge')),
      );
      expect((await handler.handleRequest(request)).first, 14);
      await fixture.service.disconnect(sibling.id);
      expect(fixture.agents.single.isClosed, isTrue);
      expect(await handler.handleRequest(request), [5]);
      expect(fixture.clients.map((client) => client.closeCalls), [1, 1]);
      expect(
        fixture.agent.transports.every((transport) => transport.destroyed),
        isTrue,
      );
    });

    test(
      'sharing an unforwarded route cannot grant agent forwarding',
      () async {
        final fixture = _AgentHarness();
        addTearDown(fixture.service.dispose);
        final source = await fixture.service.connectWithAgent(
          'final.example',
          22,
          'alice',
          gateway: _gateway,
        );
        final sibling = await fixture.service.shareSession(source.id);
        expect(fixture.handlers.values, everyElement(isNull));
        expect(fixture.agent.requests.map((request) => request.first), [
          11,
          13,
        ]);
        await fixture.service.disconnect(source.id);
        expect(fixture.agents.single.isClosed, isFalse);
        await fixture.service.disconnect(sibling.id);
        expect(fixture.agents.single.isClosed, isTrue);
      },
    );
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Client implements SSHClient {
  _Client([this.routeSocket]);
  final _Socket? routeSocket;
  final shells = <_Shell>[];
  final ptyRequests = <SSHPtyConfig?>[];
  final commands = <String>[];
  final _finished = Completer<void>();
  Future<SSHSession>? pendingShell;
  Future<SSHSession>? pendingExecution;
  bool holdNextExecution = false;
  bool _closed = false;
  int closeCalls = 0;

  @override
  SSHSocket get socket => routeSocket!;
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
    ptyRequests.add(pty);
    final pending = pendingShell;
    pendingShell = null;
    if (pending != null) {
      final channel = await pending;
      if (channel is _Shell) shells.add(channel);
      return channel;
    }
    final channel = _Shell();
    shells.add(channel);
    return channel;
  }

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    ptyRequests.add(pty);
    final pending = pendingExecution;
    pendingExecution = null;
    if (pending != null) {
      final channel = await pending;
      if (channel is _Shell) shells.add(channel);
      return channel;
    }
    final channel = _Shell();
    shells.add(channel);
    final hold = holdNextExecution;
    holdNextExecution = false;
    if (pty == null && !command.startsWith('exec tmux -C') && !hold) {
      scheduleMicrotask(() {
        channel.output.add(Uint8List.fromList(utf8.encode(command)));
        unawaited(channel.finish(0));
      });
    }
    return channel;
  }

  @override
  Future<Uint8List> run(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async => Uint8List.fromList(utf8.encode(command));

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async => _Socket(remoteHost);

  @override
  Future<SSHRemoteForward?> forwardRemote({
    String? host,
    int? port,
    SSHRemoteConnectionFilter? filter,
  }) async => _Remote();

  @override
  Future<bool> cancelForwardRemote(SSHRemoteForward forward) async {
    (forward as _Remote).close();
    return true;
  }

  void endTransport() {
    _closed = true;
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    endTransport();
    routeSocket?.destroy();
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
  ]) => resizes.add((width, height));

  void completeChannel([int? code]) {
    if (_finished.isCompleted) return;
    _exitCode = code;
    _finished.complete();
  }

  Future<void> finish([int? code]) async {
    completeChannel(code);
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

class _AgentHarness {
  final agent = AgentFixture();
  final agents = <SshAgentConnection>[];
  final clients = <_Client>[];
  final handlers = <String, SSHAgentHandler?>{};
  final events = <String>[];

  late final service = SshTerminalService(
    secureStorage: InMemorySecureStorage(),
    confirmHostKey: (_, __) async => true,
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

// A no-I/O remote listener lets the idle test exercise the production manager's
// activity callback without wall-clock delays or real sockets in a widget zone.
class _Remote implements SSHRemoteForward {
  final _connections = StreamController<SSHForwardChannel>();
  @override
  String get host => '127.0.0.1';
  @override
  int get port => 39217;
  @override
  Stream<SSHForwardChannel> get connections => _connections.stream;
  @override
  void close() => unawaited(_connections.close());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Override only the service's one-minute sweep timer. All stream/channel
// microtasks and timeouts keep the ordinary test zone, so clock-controlled
// lifecycle assertions need neither wall-clock waiting nor widget pumping.
class _ManualIdleClock {
  DateTime now = DateTime.utc(2026, 11, 16);
  _ManualTimer? timer;
  void advance(Duration duration) => now = now.add(duration);
  void sweep() => timer!.fire();
  Future<void> run(Future<void> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        if (duration != const Duration(minutes: 1)) {
          return parent.createPeriodicTimer(zone, duration, callback);
        }
        return timer = _ManualTimer(zone, callback);
      },
    ),
  );
}

class _ManualTimer implements Timer {
  _ManualTimer(this.zone, this.callback);
  final Zone zone;
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    tick++;
    zone.runGuarded(() => callback(this));
  }
}
