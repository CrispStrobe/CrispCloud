import 'package:crisp_cloud/services/ssh_port_forwarding.dart';
import 'package:crisp_cloud/services/ssh_port_forwarding_stub.dart' as web;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loopback bind and automatic port are explicit defaults', () {
    final spec = SshPortForwardSpec(kind: SshPortForwardKind.dynamic);
    expect(spec.bindHost, '127.0.0.1');
    expect(spec.bindPort, 0);
    expect(spec.targetHost, isNull);
    expect(
      SshPortForwardSpec(
        kind: SshPortForwardKind.dynamic,
        bindHost: '::1',
        bindPort: 65535,
      ).bindPort,
      65535,
    );
  });

  test(
    'non-loopback listeners and malformed destinations reject before IO',
    () {
      for (final host in [
        '0.0.0.0',
        '::',
        'localhost',
        '127.0.0.2',
        'example.com',
        '',
      ]) {
        expect(
          () => SshPortForwardSpec(
            kind: SshPortForwardKind.dynamic,
            bindHost: host,
          ),
          throwsFormatException,
        );
      }
      for (final port in [-1, 65536]) {
        expect(
          () => SshPortForwardSpec(
            kind: SshPortForwardKind.dynamic,
            bindPort: port,
          ),
          throwsFormatException,
        );
      }
      for (final host in [
        '',
        'bad host',
        'a\nb',
        'a\x00b',
        '[::1]',
        'a/b',
        'a@b',
        'a' * 254,
      ]) {
        expect(
          () => SshPortForwardSpec(
            kind: SshPortForwardKind.local,
            targetHost: host,
            targetPort: 80,
          ),
          throwsFormatException,
        );
      }
      for (final port in [null, 0, -1, 65536]) {
        expect(
          () => SshPortForwardSpec(
            kind: SshPortForwardKind.remote,
            targetHost: 'localhost',
            targetPort: port,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => SshPortForwardSpec(
          kind: SshPortForwardKind.dynamic,
          targetHost: 'localhost',
          targetPort: 80,
        ),
        throwsFormatException,
      );
    },
  );

  test('target IPv6 literals and remote DNS names remain exact', () {
    for (final host in ['::1', '2001:db8::4', 'db.internal', '127.0.0.1']) {
      final spec = SshPortForwardSpec(
        kind: SshPortForwardKind.local,
        targetHost: host,
        targetPort: 65535,
      );
      expect(spec.targetHost, host);
    }
  });

  test(
    'browser stub gives an explicit unsupported result and closes idempotently',
    () async {
      expect(web.sshPortForwardingSupported, isFalse);
      final manager = web.createSshPortForwarding(
        _UnusedClient(),
        connectTimeout: const Duration(seconds: 1),
        handshakeTimeout: const Duration(seconds: 1),
      );
      expect(manager.forwards, isEmpty);
      await expectLater(
        manager.start(SshPortForwardSpec(kind: SshPortForwardKind.dynamic)),
        throwsA(isA<SshPortForwardException>()),
      );
      var notifications = 0;
      manager.addListener(() => notifications++);
      await manager.close();
      await manager.close();
      expect(manager.isClosed, isTrue);
      expect(notifications, 1);
      manager.dispose();
    },
  );
}

class _UnusedClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
