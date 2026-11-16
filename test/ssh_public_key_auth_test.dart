// Exercise the authentication state machine through decoded packet dispatch.
// This fixture supplies a session ID; it does not bypass verification in the
// production connection path or claim to perform a cryptographic handshake.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_service.dart';
import 'package:dartssh2/src/message/msg_userauth.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mismatch in ['algorithm', 'key']) {
    test(
      'PK_OK rejects a different $mismatch before invoking the signer',
      () async {
        final identity = _Identity();
        final harness = _AuthHarness([identity.identity]);
        addTearDown(harness.close);
        harness.begin();
        harness.accept(
          identity,
          algorithm: mismatch == 'algorithm' ? 'rsa-sha2-256' : null,
          key: mismatch == 'key' ? Uint8List.fromList([1, 2, 3]) : null,
        );
        // A second reply in the same input turn must not revive the bad probe.
        harness.accept(identity);
        await _events();
        expect(identity.challenges, isEmpty);
        expect(harness.authRequests, 1);
        expect(harness.client.isClosed, isTrue);
        expect(
          harness.transportError,
          isA<SSHInternalError>().having(
            (error) => error.error,
            'protocol failure',
            isA<SSHPacketError>(),
          ),
        );
      },
    );
  }

  for (final algorithm in ['ssh-ed25519', 'rsa-sha2-256', 'rsa-sha2-512']) {
    test(
      'matching $algorithm probe signs its local challenge exactly once',
      () async {
        final identity = _Identity(algorithm: algorithm);
        final harness = _AuthHarness([identity.identity]);
        addTearDown(harness.close);
        harness.begin();
        expect(identity.challenges, isEmpty);
        harness.accept(identity);
        harness.accept(identity);
        await _events();
        expect(identity.challenges, [_challenge(algorithm, identity.key)]);
        expect(harness.authRequests, 1);
        identity.succeed(0);
        await _events();
        expect(harness.authRequests, 2);
        expect(harness.client.isClosed, isFalse);
      },
    );
  }

  test(
    'PK_OK is checked against the key bytes actually sent in the probe',
    () async {
      final identity = _Identity();
      final harness = _AuthHarness([identity.identity]);
      addTearDown(harness.close);
      final original = Uint8List.fromList(identity.key);
      harness.begin();
      identity.key[identity.key.length - 1] ^= 1;
      harness.accept(identity, key: original);
      await _events();
      expect(identity.challenges, [_challenge(identity.algorithm, original)]);
      identity.succeed(0);
      await _events();
      expect(harness.authRequests, 2);
      expect(harness.client.isClosed, isFalse);
    },
  );

  for (final probe in [true, false]) {
    final mode = probe ? 'probed' : 'direct';
    for (final lateError in [false, true]) {
      final outcome = lateError ? 'error' : 'signature';
      test(
        '$mode signer late $outcome cannot affect the next key attempt',
        () async {
          final identity = _Identity(probe: probe);
          // Reuse the same object to ensure identity equality alone cannot
          // authorize completion from an earlier attempt (including MFA retry).
          final harness = _AuthHarness([identity.identity, identity.identity]);
          addTearDown(harness.close);
          harness.begin();
          if (probe) harness.accept(identity);
          await _events();
          expect(identity.challenges.length, 1);
          harness.failAuthentication();
          if (probe) harness.accept(identity);
          await _events();
          expect(identity.challenges.length, 2);
          final before = harness.authRequests;
          if (lateError) {
            identity.fail(0);
          } else {
            identity.succeed(0);
          }
          await _events();
          expect(harness.authRequests, before);
          expect(harness.client.isClosed, isFalse);
          identity.succeed(1);
          await _events();
          expect(harness.authRequests, before + 1);
          expect(harness.transportError, isNull);
        },
      );

      test(
        '$mode signer late $outcome cannot affect an authenticated connection',
        () async {
          final identity = _Identity(probe: probe);
          final harness = _AuthHarness([identity.identity]);
          addTearDown(harness.close);
          harness.begin();
          if (probe) harness.accept(identity);
          await _events();
          harness.client.handlePacket(SSH_Message_Userauth_Success().encode());
          await harness.client.authenticated;
          final before = harness.authRequests;
          if (lateError) {
            identity.fail(0);
          } else {
            identity.succeed(0);
          }
          await _events();
          expect(harness.authRequests, before);
          expect(harness.client.isClosed, isFalse);
          expect(harness.transportError, isNull);
        },
      );
    }

    test(
      '$mode signer late completion is discarded after transport close',
      () async {
        final identity = _Identity(probe: probe);
        final harness = _AuthHarness([identity.identity]);
        addTearDown(harness.close);
        harness.begin();
        if (probe) harness.accept(identity);
        await _events();
        final before = harness.authRequests;
        await harness.close();
        identity.succeed(0);
        await _events();
        expect(harness.authRequests, before);
      },
    );

    test('$mode current signer error still aborts authentication', () async {
      final identity = _Identity(probe: probe);
      final harness = _AuthHarness([identity.identity]);
      addTearDown(harness.close);
      harness.begin();
      if (probe) harness.accept(identity);
      await _events();
      identity.fail(0);
      await _events();
      expect(harness.client.isClosed, isTrue);
      expect(harness.transportError, isA<SSHInternalError>());
      expect(harness.authError, isA<SSHAuthAbortError>());
    });
  }

  test(
    'authentication success ignores subsequent PK_OK and failure packets',
    () async {
      final identity = _Identity();
      final harness = _AuthHarness([identity.identity, identity.identity]);
      addTearDown(harness.close);
      harness.begin();
      harness.client.handlePacket(SSH_Message_Userauth_Success().encode());
      await harness.client.authenticated;
      harness.accept(identity);
      harness.failAuthentication();
      await _events();
      expect(identity.challenges, isEmpty);
      expect(harness.authRequests, 1);
      expect(harness.client.isClosed, isFalse);
    },
  );
}

Uint8List _challenge(String algorithm, Uint8List key) {
  final writer = SSHMessageWriter()
    ..writeString(_AuthHarness.sessionId)
    ..writeUint8(SSH_Message_Userauth_Request.messageId)
    ..writeUtf8('fixture')
    ..writeUtf8('ssh-connection')
    ..writeUtf8('publickey')
    ..writeBool(true)
    ..writeUtf8(algorithm)
    ..writeString(key);
  return writer.takeBytes();
}

class _Identity {
  _Identity({this.algorithm = 'ssh-ed25519', bool probe = true}) {
    final writer = SSHMessageWriter();
    if (algorithm.startsWith('rsa-sha2-')) {
      writer
        ..writeUtf8('ssh-rsa')
        ..writeMpint(BigInt.from(65537))
        ..writeMpint((BigInt.one << 2047) + BigInt.one);
    } else {
      writer
        ..writeUtf8('ssh-ed25519')
        ..writeString(Uint8List.fromList(List.filled(32, 7)));
    }
    key = writer.takeBytes();
    identity = SSHIdentity.custom(
      type: algorithm,
      publicKey: SSHRawHostKey(key),
      shouldProbe: probe,
      signer: (data) {
        challenges.add(Uint8List.fromList(data));
        final pending = Completer<SSHSignature>();
        replies.add(pending);
        return pending.future;
      },
    );
  }

  final String algorithm;
  late final Uint8List key;
  late final SSHIdentity identity;
  final challenges = <Uint8List>[];
  final replies = <Completer<SSHSignature>>[];

  void succeed(int index) => replies[index].complete(
    SSHRawSignature(Uint8List.fromList([1, 2, 3, 4])),
  );
  void fail(int index) =>
      replies[index].completeError(StateError('fixture signer refused'));
}

class _AuthHarness {
  _AuthHarness(List<SSHIdentity> identities) {
    client = SSHClient(
      _Socket(),
      username: 'fixture',
      identities: identities,
      keepAliveInterval: null,
      printTrace: (message) => traces.add(message ?? ''),
    )..sessionId = sessionId;
    unawaited(
      client.authenticated.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) => authError = error,
      ),
    );
    unawaited(
      client.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) => transportError = error,
      ),
    );
  }

  static final sessionId = Uint8List.fromList(List.filled(32, 9));
  late final SSHClient client;
  final traces = <String>[];
  Object? authError;
  Object? transportError;
  int get authRequests => traces
      .where(
        (line) =>
            line.startsWith('-> ') &&
            line.contains('SSH_Message_Userauth_Request('),
      )
      .length;

  void begin() =>
      client.handlePacket(SSH_Message_Service_Accept('ssh-userauth').encode());
  void accept(_Identity identity, {String? algorithm, Uint8List? key}) =>
      client.handlePacket(
        SSH_Message_Userauth_PK_Ok(
          publicKeyAlgorithm: algorithm ?? identity.algorithm,
          publicKey: key ?? identity.key,
        ).encode(),
      );
  void failAuthentication() => client.handlePacket(
    SSH_Message_Userauth_Failure(methodsLeft: ['publickey']).encode(),
  );
  Future<void> close() => client.close();
}

Future<void> _events() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Socket implements SSHSocket {
  _Socket() {
    _output.stream.listen((_) {});
  }
  final _input = StreamController<Uint8List>();
  final _output = StreamController<List<int>>();
  @override
  Stream<Uint8List> get stream => _input.stream;
  @override
  StreamSink<List<int>> get sink => _output.sink;
  @override
  Future<void> get done => _input.done;
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {
    await _input.close();
    await _output.close();
  }

  @override
  void destroy() => unawaited(close());
}
