// Runs on both the VM and Chromium: only the SSH client boundary is fake.
import 'dart:async';

import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/ssh_terminal_service.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'browser requires an explicit gateway; native defaults to direct TCP',
    () async {
      var calls = 0;
      Uri? selected;
      final service = SshTerminalService(
        secureStorage: InMemorySecureStorage(),
        clientConnector:
            (
              host,
              port, {
              required username,
              password,
              identities,
              gateway,
            }) async {
              calls++;
              selected = gateway;
              return _Client();
            },
      );
      addTearDown(service.dispose);

      final connecting = service.connect(
        'target.example',
        22,
        'alice',
        'password',
      );
      if (kIsWeb) {
        await expectLater(connecting, throwsArgumentError);
        expect(calls, 0);
      } else {
        await connecting;
        expect(calls, 1);
        expect(selected, isNull);
      }
    },
  );

  test(
    'gateway URL stays separate from the real SSH server and username',
    () async {
      (String, int, String, Uri?)? request;
      final service = SshTerminalService(
        secureStorage: InMemorySecureStorage(),
        clientConnector:
            (
              host,
              port, {
              required username,
              password,
              identities,
              gateway,
            }) async {
              request = (host, port, username, gateway);
              return _Client();
            },
      );
      addTearDown(service.dispose);
      final gateway = Uri.parse('wss://relay.example:8443/forward/ssh');
      final session = await service.connect(
        'target.example',
        2222,
        'alice',
        'password',
        gateway: gateway,
      );
      expect(request, ('target.example', 2222, 'alice', gateway));
      expect(session.host, 'target.example');
      expect(session.port, 2222);
      expect(session.username, 'alice');
    },
  );

  test(
    'invalid gateway fails before opening an SSH connection on any platform',
    () async {
      var calls = 0;
      final service = SshTerminalService(
        secureStorage: InMemorySecureStorage(),
        clientConnector:
            (
              host,
              port, {
              required username,
              password,
              identities,
              gateway,
            }) async {
              calls++;
              return _Client();
            },
      );
      addTearDown(service.dispose);
      for (final address in [
        'ws://relay.example/ssh',
        'wss://alice:secret@relay.example/ssh',
        'wss://relay.example/ssh?token=secret',
        'wss://relay.example/ssh#secret',
      ]) {
        await expectLater(
          service.connect(
            'target.example',
            22,
            'alice',
            'password',
            gateway: Uri.parse(address),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'safe validation message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
      expect(calls, 0);
    },
  );
}

class _Client implements SSHClient {
  final _finished = Completer<void>();
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> get authenticated async {}

  @override
  Future<void> get done => _finished.future;

  @override
  Future<void> close() async {
    _closed = true;
    if (!_finished.isCompleted) _finished.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
