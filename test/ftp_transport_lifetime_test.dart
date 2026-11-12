import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/ftp_security_mode.dart';
import 'package:crisp_cloud/services/ftp_transfer_session.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:ftpconnect/ftp_transport.dart';

import 'support/ftp_control_stall_fixture.dart';
import 'support/ftp_tls_fixture.dart';

void main() {
  const observationLimit = Duration(seconds: 3);

  test('raw stream cancellation consumes an upstream cleanup error', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <Socket>[];
    server.listen(peers.add);
    final transport = FtpSocketTransport();
    addTearDown(() async {
      transport.close();
      for (final peer in peers) {
        peer.destroy();
      }
      await server.close();
    });
    await transport.connect(
      '127.0.0.1',
      server.port,
      timeout: observationLimit,
    );
    final listening = Completer<void>();
    final source = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () =>
          Future<void>.error(StateError('Synthetic cleanup failure')),
    );
    final socket = transport.socket;
    final failed = expectLater(
      socket.addStream(source.stream),
      throwsA(isA<SocketException>()),
    );
    await listening.future;
    transport.close();
    await failed.timeout(observationLimit);
    await socket.done.timeout(observationLimit);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test(
    'cancellation before native TCP setup returns observes its late completion',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      server.listen(peers.add);
      addTearDown(() async {
        for (final peer in peers) peer.destroy();
        await server.close();
      });
      final transport = FtpSocketTransport();
      final failed = expectLater(
        transport.connect('127.0.0.1', server.port, timeout: observationLimit),
        throwsA(isA<SocketException>()),
      );
      transport.close();
      await failed;
      // Any late native result must be consumed without an unhandled error.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(transport.isClosed, isTrue);
      await expectLater(
        transport.secure('127.0.0.1', timeout: observationLimit),
        throwsA(isA<SocketException>()),
      );
    },
  );

  Future<FtpControlStallFixture> controlPeer(bool implicit) async {
    final peer = await FtpControlStallFixture.open(implicit: implicit);
    addTearDown(() async {
      await peer.close();
      expect(peer.errors, isEmpty);
    });
    return peer;
  }

  Future<FtpTlsFixture> dataPeer() async {
    final peer = await FtpTlsFixture.open();
    peer.stallDataHandshake = true;
    addTearDown(() async {
      await peer.close();
      expect(peer.errors, isEmpty);
    });
    return peer;
  }

  FtpTransferSession transfer(
    int port, {
    bool implicit = false,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final session = FtpTransferSession(
      host: '127.0.0.1',
      port: port,
      username: 'fixture',
      password: 'synthetic-password',
      securityMode: implicit
          ? FtpSecurityMode.implicitTls
          : FtpSecurityMode.explicitTls,
      securityContext: FtpTlsFixture.trustedContext(),
      timeout: timeout,
      isCurrent: () => true,
    );
    addTearDown(session.close);
    return session;
  }

  FTPConnect metadata(int port, {bool implicit = false, int timeout = 30}) {
    final client = FTPConnect(
      '127.0.0.1',
      port: port,
      user: 'fixture',
      pass: 'synthetic-password',
      securityType: implicit ? SecurityType.ftps : SecurityType.ftpes,
      securityContext: FtpTlsFixture.trustedContext(),
      timeout: timeout,
    );
    addTearDown(client.disconnect);
    return client;
  }

  Future<FTPClientAdapter> adapter(int port, {bool implicit = false}) async {
    final config = FTPConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    await config.saveCredentials({
      'host': '127.0.0.1',
      'port': '$port',
      'username': 'fixture',
      'password': 'synthetic-password',
      'securityMode':
          (implicit ? FtpSecurityMode.implicitTls : FtpSecurityMode.explicitTls)
              .name,
    });
    final client = FTPClientAdapter(
      config: config,
      securityContext: FtpTlsFixture.trustedContext(),
    );
    addTearDown(client.logout);
    return client;
  }

  Future<void> controlClosed(FtpControlStallFixture peer) async {
    await peer.handshakeStarted.future.timeout(observationLimit);
    expect(
      peer.helloPrefix.first,
      22,
      reason: 'The peer received a TLS ClientHello record.',
    );
    await peer.peerClosed.future.timeout(observationLimit);
    expect(peer.commands, peer.implicit ? isEmpty : ['AUTH TLS']);
  }

  Future<void> dataClosed(FtpTlsFixture peer) async {
    await peer.dataHandshakeStarted.future.timeout(observationLimit);
    expect(peer.stalledDataPrefix.first, 22);
    await peer.dataPeerClosed.future.timeout(observationLimit);
    expect(peer.dataTlsConnections, 0);
    expect(peer.uploads, isEmpty);
    expect(peer.cleartextCommands, everyElement('AUTH TLS'));
  }

  for (final implicit in [false, true]) {
    final mode = implicit ? 'implicit' : 'explicit';
    test(
      'transfer $mode control timeout closes the stalled TLS peer',
      () async {
        final peer = await controlPeer(implicit);
        final session = transfer(
          peer.port,
          implicit: implicit,
          timeout: const Duration(seconds: 1),
        );
        await expectLater(session.connect(), throwsA(isA<TimeoutException>()));
        await controlClosed(peer);
      },
    );

    test(
      'transfer $mode control cancellation closes the stalled TLS peer',
      () async {
        final peer = await controlPeer(implicit);
        final session = transfer(peer.port, implicit: implicit);
        final failed = expectLater(session.connect(), throwsA(anything));
        await peer.handshakeStarted.future.timeout(observationLimit);
        session.close();
        await failed.timeout(observationLimit);
        await controlClosed(peer);
      },
    );

    test(
      'metadata $mode control timeout closes the stalled TLS peer',
      () async {
        final peer = await controlPeer(implicit);
        final client = metadata(peer.port, implicit: implicit, timeout: 1);
        await expectLater(
          client.connect(),
          throwsA(
            predicate((error) => '$error'.toLowerCase().contains('timed out')),
          ),
        );
        await controlClosed(peer);
      },
    );

    test('metadata $mode disconnect closes the stalled TLS peer', () async {
      final peer = await controlPeer(implicit);
      final client = metadata(peer.port, implicit: implicit);
      final failed = expectLater(client.connect(), throwsA(anything));
      await peer.handshakeStarted.future.timeout(observationLimit);
      await client.disconnect().timeout(observationLimit);
      await failed.timeout(observationLimit);
      await controlClosed(peer);
    });

    test(
      'adapter $mode logout owns and closes an initial stalled TLS connection',
      () async {
        final peer = await controlPeer(implicit);
        final client = await adapter(peer.port, implicit: implicit);
        final failed = expectLater(client.restoreSession(), throwsA(anything));
        await peer.handshakeStarted.future.timeout(observationLimit);
        await client.logout().timeout(observationLimit);
        await failed.timeout(observationLimit);
        await controlClosed(peer);
        expect(client.isAuthenticated, isFalse);
      },
    );
  }

  for (final direction in ['upload', 'download']) {
    for (final cancel in [false, true]) {
      test(
        'transfer $direction data ${cancel ? 'cancellation' : 'timeout'} closes the stalled TLS peer',
        () async {
          final peer = await dataPeer();
          final session = transfer(
            peer.port,
            timeout: Duration(seconds: cancel ? 30 : 1),
          );
          await session.connect();
          final operation = direction == 'upload'
              ? session.upload('/file', Stream.value([1, 2, 3]), 3)
              : session.download('/file').drain<void>();
          final failed = expectLater(operation, throwsA(anything));
          await peer.dataHandshakeStarted.future.timeout(observationLimit);
          if (cancel) session.close();
          await failed.timeout(observationLimit);
          await dataClosed(peer);
        },
      );
    }
  }

  for (final operation in ['listing', 'upload', 'download']) {
    for (final cancel in [false, true]) {
      test(
        'metadata $operation data ${cancel ? 'disconnect' : 'timeout'} closes the stalled TLS peer',
        () async {
          final peer = await dataPeer();
          final client = metadata(peer.port, timeout: cancel ? 30 : 1);
          await client.connect();
          final directory = await Directory.systemTemp.createTemp(
            'ftp-lifetime-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final input = File('${directory.path}/input')
            ..writeAsBytesSync([1, 2, 3]);
          final output = File('${directory.path}/output');
          final pending = switch (operation) {
            'listing' => client.listDirectoryContent(),
            'upload' => client.uploadFile(input, sRemoteName: 'file'),
            _ => client.downloadFile('/file', output),
          };
          final failed = expectLater(pending, throwsA(anything));
          await peer.dataHandshakeStarted.future.timeout(observationLimit);
          if (cancel) await client.disconnect().timeout(observationLimit);
          await failed.timeout(observationLimit);
          await dataClosed(peer);
          expect(output.existsSync(), isFalse);
        },
      );
    }
  }

  test(
    'adapter logout cancels metadata data-channel TLS before returning',
    () async {
      final peer = await dataPeer();
      final client = await adapter(peer.port);
      await client.restoreSession();
      final failed = expectLater(client.listPath('/'), throwsA(anything));
      await peer.dataHandshakeStarted.future.timeout(observationLimit);
      await client.logout().timeout(observationLimit);
      await failed.timeout(observationLimit);
      await dataClosed(peer);
      expect(client.isAuthenticated, isFalse);
    },
  );

  test('legacy download closes its output sink after a post-handshake receive timeout', () async {
    final peer = await dataPeer();
    peer.stallDataHandshake = false;
    peer.stallAfterDownloadChunk = true;
    final client = metadata(peer.port, timeout: 1);
    await client.connect();
    final output = _ObservedOutput();
    await expectLater(
      client.downloadFile('/file', output),
      throwsA(isA<TimeoutException>()),
    );
    expect(output.consumer.bytes, peer.payload.take(3));
    expect(output.consumer.closed, isTrue);
    expect(peer.dataTlsConnections, 1);
  });
}

class _ObservedOutput extends Fake implements File {
  final consumer = _ObservedFileConsumer();
  @override
  String get path => '/synthetic-output';
  @override
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => IOSink(consumer, encoding: encoding);
}

class _ObservedFileConsumer implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  bool closed = false;
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async => closed = true;
}
