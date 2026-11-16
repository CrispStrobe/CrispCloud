@Tags(['live-ssh'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/models/ssh_jump_host.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The companion runner supplies disposable OpenSSH servers and client keys.
/// All listeners and destinations are loopback; no external host is contacted.
void main() {
  final environment = Platform.environment;
  final keyPath = environment['CRISPCLOUD_LIVE_SSH_KEY'];
  final enabled = keyPath != null;
  final jumpPort = int.tryParse(
    environment['CRISPCLOUD_LIVE_SSH_JUMP_PORT'] ?? '',
  );
  final targetPort = int.tryParse(
    environment['CRISPCLOUD_LIVE_SSH_TARGET_PORT'] ?? '',
  );
  final username = environment['CRISPCLOUD_LIVE_SSH_USER'];

  group(
    'real OpenSSH forwarding through a verified jump route',
    () {
      late SshTerminalService service;
      late SshSession session;
      late SshPortForwarding manager;
      final targets = <_ReplyAfterEof>[];
      final sockets = <Socket>[];

      setUp(() async {
        final prompts = <String>[];
        service = SshTerminalService(
          secureStorage: InMemorySecureStorage(),
          confirmHostKey: (endpoint, fingerprint) async {
            prompts.add(endpoint);
            expect(fingerprint, startsWith('SHA256:'));
            return true;
          },
        );
        session = await service
            .connectWithKey(
              '127.0.0.1',
              targetPort!,
              username!,
              await File(keyPath!).readAsString(),
              jumpHosts: [
                SshJumpHost(
                  host: '127.0.0.1',
                  port: jumpPort!,
                  username: username,
                  authentication: SshTerminalAuthentication.privateKey,
                  privateKey: await File(keyPath).readAsString(),
                ),
              ],
            )
            .timeout(const Duration(seconds: 20));
        expect(prompts, ['127.0.0.1:$jumpPort', '127.0.0.1:$targetPort']);
        manager = service.forwarding(session.id);
      });
      tearDown(() async {
        await service.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        sockets.clear();
        for (final target in targets) {
          await target.close();
        }
        targets.clear();
      });

      Future<_ReplyAfterEof> target() async {
        final value = await _ReplyAfterEof.create();
        targets.add(value);
        return value;
      }

      Future<Socket> connect(int port) async {
        final value = await Socket.connect('127.0.0.1', port);
        sockets.add(value);
        return value;
      }

      // Exceeds dartssh2's initial 2 MiB channel window in both directions.
      final payload = Uint8List.fromList([
        ...utf8.encode('forward-✓-日本語\n'),
        ...List<int>.generate(3 * 1024 * 1024, (index) => index % 256),
      ]);

      for (final kind in [
        SshPortForwardKind.local,
        SshPortForwardKind.remote,
      ]) {
        test(
          '${kind.name} allocates a listener, drains binary response after half-close, and cancels',
          () async {
            final echo = await target();
            final forward = await manager.start(
              SshPortForwardSpec(
                kind: kind,
                targetHost: '127.0.0.1',
                targetPort: echo.port,
              ),
            );
            expect(forward.port, inInclusiveRange(1, 65535));
            final socket = await connect(forward.port);
            final response = socket.fold<BytesBuilder>(
              BytesBuilder(copy: false),
              (all, chunk) => all..add(chunk),
            );
            socket.add(payload);
            await socket.close();
            final received = (await response.timeout(
              const Duration(seconds: 20),
            )).takeBytes();
            expect(received, payload);
            await manager.stop(forward.id);
            expect(manager.forwards, isEmpty);
            await expectLater(
              Socket.connect(
                '127.0.0.1',
                forward.port,
                timeout: const Duration(seconds: 2),
              ),
              throwsA(isA<SocketException>()),
            );
            expect(
              await service.execute(session.id, 'printf shell-still-connected'),
              'shell-still-connected',
            );
          },
        );
      }

      test('SOCKS domain request and pipelined binary payload survive request half-close', () async {
        final echo = await target();
        final forward = await manager.start(
          SshPortForwardSpec(kind: SshPortForwardKind.dynamic),
        );
        final socket = await connect(forward.port);
        final response = socket.fold<BytesBuilder>(
          BytesBuilder(copy: false),
          (all, chunk) => all..add(chunk),
        );
        final host = ascii.encode('localhost');
        socket.add([
          5,
          1,
          0,
          5,
          1,
          0,
          3,
          host.length,
          ...host,
          echo.port >> 8,
          echo.port & 255,
          ...payload,
        ]);
        await socket.close();
        final received = (await response.timeout(const Duration(seconds: 20)))
            .takeBytes();
        expect(received.take(2), [5, 0]);
        expect(received.sublist(2, 4), [5, 0]);
        expect(received.sublist(12), payload);
        await manager.stop(forward.id);
        expect(
          await service.execute(session.id, 'printf socks-stopped'),
          'socks-stopped',
        );
      });

      test('disconnect closes active client sockets and both local and remote listeners', () async {
        final echo = await target();
        final local = await manager.start(
          SshPortForwardSpec(
            kind: SshPortForwardKind.local,
            targetHost: '127.0.0.1',
            targetPort: echo.port,
          ),
        );
        final remote = await manager.start(
          SshPortForwardSpec(
            kind: SshPortForwardKind.remote,
            targetHost: '127.0.0.1',
            targetPort: echo.port,
          ),
        );
        final first = await connect(local.port);
        final second = await connect(remote.port);
        final drained = [first.drain<void>(), second.drain<void>()];
        first.add([1]);
        second.add([2]);
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (manager.forwards.any((item) => item.activeConnections == 0)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Forwarded clients did not connect');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await service.disconnect(session.id);
        await Future.wait(drained).timeout(const Duration(seconds: 5));
        expect(manager.isClosed, isTrue);
        expect(manager.forwards, isEmpty);
        for (final port in [local.port, remote.port]) {
          await expectLater(
            Socket.connect(
              '127.0.0.1',
              port,
              timeout: const Duration(seconds: 2),
            ),
            throwsA(isA<SocketException>()),
          );
        }
      });
    },
    skip: !enabled
        ? 'Run tool/run_terminal_live_smoke.py for disposable OpenSSH fixtures.'
        : false,
  );
}

class _ReplyAfterEof {
  _ReplyAfterEof(this.server) {
    subscription = server.listen((socket) {
      clients.add(socket);
      final bytes = BytesBuilder(copy: false);
      socket.listen(
        bytes.add,
        onDone: () async {
          try {
            socket.add(bytes.takeBytes());
            await socket.close();
          } catch (_) {
            socket.destroy();
          }
        },
        onError: (Object _) => socket.destroy(),
      );
    });
  }
  static Future<_ReplyAfterEof> create() async =>
      _ReplyAfterEof(await ServerSocket.bind('127.0.0.1', 0));
  final ServerSocket server;
  final clients = <Socket>[];
  late final StreamSubscription<Socket> subscription;
  int get port => server.port;
  Future<void> close() async {
    await server.close();
    await subscription.cancel();
    for (final socket in clients) {
      socket.destroy();
    }
  }
}
