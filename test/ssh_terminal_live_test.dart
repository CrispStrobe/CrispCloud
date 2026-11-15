@Tags(['live-ssh'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/ssh_jump_host.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:crisp_cloud/services/terminal_mount_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in, real loopback OpenSSH coverage. The companion runner creates fresh
/// server/client keys and supplies these paths; no credentials enter the repo.
void main() {
  final environment = kIsWeb ? <String, String>{} : Platform.environment;
  final keyPath = environment['CRISPCLOUD_LIVE_SSH_KEY'];
  final enabled = keyPath != null;
  final ptyEnabled = environment['CRISPCLOUD_LIVE_SSH_PTY'] == '1';
  final jumpPort = int.tryParse(
    environment['CRISPCLOUD_LIVE_SSH_JUMP_PORT'] ?? '',
  );
  final targetPort = int.tryParse(
    environment['CRISPCLOUD_LIVE_SSH_TARGET_PORT'] ?? '',
  );
  final username = environment['CRISPCLOUD_LIVE_SSH_USER'];

  group(
    'real OpenSSH loopback route',
    () {
      late String key;
      late InMemorySecureStorage storage;
      late SshTerminalService service;
      late List<String> prompts;

      setUp(() async {
        key = await File(keyPath!).readAsString();
        storage = InMemorySecureStorage();
        prompts = [];
        service = SshTerminalService(
          secureStorage: storage,
          confirmHostKey: (endpoint, fingerprint) async {
            prompts.add(endpoint);
            expect(fingerprint, startsWith('SHA256:'));
            return true;
          },
        );
      });
      tearDown(() async => service.dispose());

      Future<SshSession> connect() => service
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

      test(
        'verifies both servers and preserves Unicode execution through a jump',
        () async {
          final session = await connect();
          expect(prompts, ['127.0.0.1:$jumpPort', '127.0.0.1:$targetPort']);
          final known =
              jsonDecode((await storage.read('ssh_known_hosts_v1'))!) as Map;
          expect(known, hasLength(2));
          expect(
            known.values.toSet(),
            hasLength(2),
            reason: 'Each endpoint has its own host key',
          );
          expect(
            await service.execute(session.id, "printf 'route-✓-日本語'"),
            'route-✓-日本語',
          );
          await service.disconnect(session.id);
          expect(service.getActiveSessions(), isEmpty);
          prompts.clear();
          final again = await connect();
          expect(
            prompts,
            isEmpty,
            reason: 'Known host keys are verified without reprompting',
          );
          expect(
            await service.execute(again.id, 'printf reconnected'),
            'reconnected',
          );
        },
      );

      test('rejects a changed target host key without trusting or registering the route', () async {
        final session = await connect();
        await service.disconnect(session.id);
        final known = jsonDecode(
          (await storage.read('ssh_known_hosts_v1'))!,
        ) as Map<String, dynamic>;
        known['127.0.0.1:$targetPort'] = 'SHA256:${'A' * 43}';
        await storage.write('ssh_known_hosts_v1', jsonEncode(known));
        prompts.clear();
        await expectLater(connect(), throwsA(isA<TerminalMountException>()));
        expect(prompts, isEmpty);
        expect(service.getActiveSessions(), isEmpty);
        expect(
          jsonDecode(
            (await storage.read('ssh_known_hosts_v1'))!,
          )['127.0.0.1:$targetPort'],
          known['127.0.0.1:$targetPort'],
        );
      });

      test(
        'real PTY receives size changes and preserves final output and exit status',
        () async {
          final session = await connect();
          final stream = await service.startShell(
            session.id,
            width: 91,
            height: 31,
          );
          expect(stream, isA<SshShellOutput>());
          final output = StringBuffer();
          final initialSize = Completer<void>();
          final resized = Completer<void>();
          final subscription = stream.listen((chunk) {
            output.write(chunk);
            final text = output.toString();
            if (text.contains('31 91') && !initialSize.isCompleted) {
              initialSize.complete();
            }
            if (text.contains('37 103') && !resized.isCompleted) {
              resized.complete();
            }
          });
          final drained = subscription.asFuture<void>();
          addTearDown(subscription.cancel);
          await service.writeToShell(session.id, 'stty size\n');
          await initialSize.future.timeout(const Duration(seconds: 10));
          await service.resizeTerminal(session.id, 103, 37);
          await service.writeToShell(session.id, 'stty size\n');
          await resized.future.timeout(const Duration(seconds: 10));
          await service.writeToShell(
            session.id,
            "printf '\\nfinal-✓\\n'; exit 7\n",
          );
          expect(
            await (stream as SshShellOutput).exitCode.timeout(
              const Duration(seconds: 10),
            ),
            7,
          );
          await drained.timeout(const Duration(seconds: 10));
          expect(output.toString(), contains('final-✓'));
        },
        skip: !ptyEnabled
            ? 'Use --with-pty with an sshd allowed to write login records.'
            : false,
      );
    },
    skip: !enabled
        ? 'Run tool/run_terminal_live_smoke.py for isolated OpenSSH fixtures.'
        : false,
  );
}
