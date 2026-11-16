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
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:crisp_storage/crisp_storage.dart' show openVerifiedSsh;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uses the runner's disposable keys and loopback servers. The actual socket,
/// host-key verifier, authentication, SSH channels, and listeners are retained;
/// the opener seam only counts transports so extra login cannot go unnoticed.
void main() {
  final environment = Platform.environment;
  final keyPath = environment['CRISPCLOUD_LIVE_SSH_KEY'];
  final jumpPort = int.tryParse(
    environment['CRISPCLOUD_LIVE_SSH_JUMP_PORT'] ?? '',
  );
  final targetPort = int.tryParse(
    environment['CRISPCLOUD_LIVE_SSH_TARGET_PORT'] ?? '',
  );
  final username = environment['CRISPCLOUD_LIVE_SSH_USER'];
  final enabled =
      keyPath != null &&
      jumpPort != null &&
      targetPort != null &&
      username != null;
  final ptyEnabled = environment['CRISPCLOUD_LIVE_SSH_PTY'] == '1';

  group(
    'real OpenSSH shared connection',
    () {
      late _LiveHarness harness;
      late SshSession source;
      final targets = <_ReplyAfterEof>[];
      final sockets = <Socket>[];

      setUp(() async {
        harness = _LiveHarness();
        final key = await File(keyPath!).readAsString();
        source = await harness.service
            .connectWithKey(
              '127.0.0.1',
              targetPort!,
              username!,
              key,
              jumpHosts: [
                SshJumpHost(
                  host: '127.0.0.1',
                  port: jumpPort!,
                  username: username,
                  authentication: SshTerminalAuthentication.privateKey,
                  privateKey: key,
                ),
              ],
            )
            .timeout(const Duration(seconds: 20));
        expect(harness.prompts, [
          '127.0.0.1:$jumpPort',
          '127.0.0.1:$targetPort',
        ]);
        expect(harness.socketOpens, 1);
        expect(harness.clients, hasLength(2));
      });

      tearDown(() async {
        await harness.service.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        sockets.clear();
        for (final target in targets) {
          await target.close();
        }
        targets.clear();
      });

      void stillOneRoute() {
        expect(harness.socketOpens, 1);
        expect(harness.clients, hasLength(2));
        expect(harness.prompts, [
          '127.0.0.1:$jumpPort',
          '127.0.0.1:$targetPort',
        ]);
      }

      test('parallel commands share one verified transport and survive source closure', () async {
        final service = harness.service;
        final sibling = await service.shareSession(source.id);
        final results = await Future.wait([
          service.execute(
            source.id,
            "printf 'source-✓-日本語\\n'; printf '%s' \"\$SSH_CONNECTION\"",
          ),
          service.execute(
            sibling.id,
            "printf 'sibling-Grüße-🌍\\n'; printf '%s' \"\$SSH_CONNECTION\"",
          ),
        ]).timeout(const Duration(seconds: 15));
        expect(results[0].split('\n').first, 'source-✓-日本語');
        expect(results[1].split('\n').first, 'sibling-Grüße-🌍');
        expect(results[0].split('\n').last, isNotEmpty);
        expect(
          results[1].split('\n').last,
          results[0].split('\n').last,
          reason:
              'Both remote commands report the identical TCP connection tuple.',
        );
        stillOneRoute();

        // Begin the sibling channel before releasing its originating logical
        // session. The new channel owns a lease regardless of opener timing.
        final pending = service.execute(
          sibling.id,
          "sleep 0.1; printf 'surviving-sibling-✓'",
        );
        await service.disconnect(source.id);
        expect(
          await pending.timeout(const Duration(seconds: 10)),
          'surviving-sibling-✓',
        );
        expect(service.connectionSessionCount(sibling.id), 1);
        expect(harness.clients.every((client) => !client.isClosed), isTrue);
        stillOneRoute();
        await service.disconnect(sibling.id);
        expect(harness.clients.every((client) => client.isClosed), isTrue);
        expect(service.getActiveSessions(), isEmpty);
      });

      test(
        'canceling a command session preserves a concurrently running sibling',
        () async {
          final service = harness.service;
          final sibling = await service.shareSession(source.id);
          final sourceCommand = service.execute(
            source.id,
            "sleep 1; printf 'closed-source'",
          );
          final sourceCanceled = expectLater(
            sourceCommand,
            throwsA(isA<TerminalMountException>()),
          );
          final peerCommand = service.execute(
            sibling.id,
            "sleep 0.1; printf 'concurrent-peer-✓'",
          );
          await service.disconnect(source.id);
          await sourceCanceled.timeout(const Duration(seconds: 5));
          expect(
            await peerCommand.timeout(const Duration(seconds: 10)),
            'concurrent-peer-✓',
          );
          expect(
            await service.execute(sibling.id, 'printf peer-again'),
            'peer-again',
          );
          stillOneRoute();
          expect(harness.clients.every((client) => !client.isClosed), isTrue);
        },
      );

      // Exceeds the initial 2 MiB SSH channel window. The response comes only
      // after request EOF, so route ownership must survive both large transfers
      // and half-close after the originating tab has disappeared.
      const transferTimeout = Duration(seconds: 60);
      final payload = Uint8List.fromList([
        ...utf8.encode('shared-route-✓-日本語\n'),
        ...List<int>.generate(3 * 1024 * 1024, (index) => index % 256),
      ]);

      for (final kind in SshPortForwardKind.values) {
        test(
          '${kind.name} forwards remain live through source closure and stop at last lease',
          () async {
            final service = harness.service;
            final manager = service.forwarding(source.id);
            final sibling = await service.shareSession(source.id);
            expect(service.forwarding(sibling.id), same(manager));
            final target = await _ReplyAfterEof.create();
            targets.add(target);
            final forward = await manager.start(
              SshPortForwardSpec(
                kind: kind,
                targetHost: kind == SshPortForwardKind.dynamic
                    ? null
                    : '127.0.0.1',
                targetPort: kind == SshPortForwardKind.dynamic
                    ? null
                    : target.port,
              ),
            );
            await service.disconnect(source.id);
            expect(manager.isClosed, isFalse);
            expect(service.forwarding(sibling.id), same(manager));
            final socket = await Socket.connect('127.0.0.1', forward.port);
            sockets.add(socket);
            unawaited(
              socket.done.then<void>(
                (_) {},
                onError: (Object _, StackTrace __) {},
              ),
            );
            final response = socket.fold<BytesBuilder>(
              BytesBuilder(copy: false),
              (all, chunk) => all..add(chunk),
            );
            if (kind == SshPortForwardKind.dynamic) {
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
                target.port >> 8,
                target.port & 255,
              ]);
            }
            socket.add(payload);
            await socket.close();
            final received = (await response.timeout(transferTimeout))
                .takeBytes();
            if (kind == SshPortForwardKind.dynamic) {
              expect(received.take(2), [5, 0]);
              expect(received.sublist(2, 4), [5, 0]);
              expect(received.sublist(12), payload);
            } else {
              expect(received, payload);
            }
            expect(
              await service.execute(
                sibling.id,
                'printf shared-route-still-connected',
              ),
              'shared-route-still-connected',
            );
            stillOneRoute();
            await service.disconnect(sibling.id);
            expect(manager.isClosed, isTrue);
            expect(manager.forwards, isEmpty);
            expect(harness.clients.every((client) => client.isClosed), isTrue);
            await expectLater(
              Socket.connect(
                '127.0.0.1',
                forward.port,
                timeout: const Duration(seconds: 2),
              ),
              throwsA(isA<SocketException>()),
            );
          },
        );
      }

      test(
        'independent PTYs preserve sizes, output and peer input after exit',
        () async {
          final service = harness.service;
          final sibling = await service.shareSession(source.id);
          final first = await service.startShell(
            source.id,
            width: 91,
            height: 31,
          );
          final second = await service.startShell(
            sibling.id,
            width: 107,
            height: 37,
          );
          final sourceOutput = _OutputProbe(first);
          final peerOutput = _OutputProbe(second);
          addTearDown(sourceOutput.close);
          addTearDown(peerOutput.close);
          await service.writeToShell(
            source.id,
            "stty -echo; printf 'source-%s\\n' 'ready'; stty size\n",
          );
          await service.writeToShell(
            sibling.id,
            "stty -echo; printf 'peer-%s\\n' 'ready'; stty size\n",
          );
          await Future.wait([
            sourceOutput.waitFor('source-ready'),
            sourceOutput.waitFor('31 91'),
            peerOutput.waitFor('peer-ready'),
            peerOutput.waitFor('37 107'),
          ]);
          await service.resizeTerminal(sibling.id, 113, 41);
          await service.writeToShell(sibling.id, 'stty size\n');
          await peerOutput.waitFor('41 113');
          await service.writeToShell(
            source.id,
            "printf 'source-final-%s\\n' '✓'; exit 7\n",
          );
          await sourceOutput.waitFor('source-final-✓');
          expect(
            await (first as SshShellOutput).exitCode.timeout(
              const Duration(seconds: 10),
            ),
            7,
          );
          await service.writeToShell(
            sibling.id,
            "printf 'surviving-peer-%s\\n' '日本語'\n",
          );
          await peerOutput.waitFor('surviving-peer-日本語');
          expect(peerOutput.text, isNot(contains('source-final-✓')));
          stillOneRoute();
          await service.writeToShell(sibling.id, 'exit 3\n');
          expect(
            await (second as SshShellOutput).exitCode.timeout(
              const Duration(seconds: 10),
            ),
            3,
          );
        },
        skip: !ptyEnabled
            ? 'Use --with-pty with an sshd allowed to write login records.'
            : false,
      );
    },
    skip: !enabled
        ? 'Run tool/run_terminal_live_smoke.py for disposable OpenSSH fixtures.'
        : false,
  );
}

class _LiveHarness {
  final clients = <SSHClient>[];
  final prompts = <String>[];
  int socketOpens = 0;
  late final service = SshTerminalService(
    secureStorage: InMemorySecureStorage(),
    confirmHostKey: (endpoint, fingerprint) async {
      prompts.add(endpoint);
      expect(fingerprint, startsWith('SHA256:'));
      return true;
    },
    socketConnector: (host, port, {gateway}) async {
      expect(gateway, isNull);
      socketOpens++;
      return SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 15),
      );
    },
    verifiedClientOpener:
        (
          socket, {
          required username,
          password,
          identities,
          agentHandler,
          required verify,
          onCreated,
        }) => openVerifiedSsh(
          socket,
          username: username,
          password: password,
          identities: identities,
          agentHandler: agentHandler,
          verify: verify,
          onCreated: (client) {
            clients.add(client);
            onCreated?.call(client);
          },
        ),
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
  final ServerSocket server;
  final clients = <Socket>[];
  late final StreamSubscription<Socket> subscription;
  int get port => server.port;
  static Future<_ReplyAfterEof> create() async =>
      _ReplyAfterEof(await ServerSocket.bind('127.0.0.1', 0));
  Future<void> close() async {
    for (final socket in clients) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
  }
}

class _OutputProbe {
  _OutputProbe(Stream<String> stream) {
    subscription = stream.listen(
      (chunk) {
        output.write(chunk);
        for (final entry in waiting.entries) {
          if (text.contains(entry.key) && !entry.value.isCompleted) {
            entry.value.complete();
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        for (final waiter in waiting.values) {
          if (!waiter.isCompleted) waiter.completeError(error, stack);
        }
      },
    );
  }
  final output = StringBuffer();
  final waiting = <String, Completer<void>>{};
  late final StreamSubscription<String> subscription;
  String get text => output.toString();
  Future<void> waitFor(String marker) {
    if (text.contains(marker)) return Future.value();
    return (waiting[marker] ??= Completer<void>()).future.timeout(
      const Duration(seconds: 10),
    );
  }

  Future<void> close() => subscription.cancel();
}
