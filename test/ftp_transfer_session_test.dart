import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/ftp_transfer_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FtpServer server;
  setUp(() async => server = await _FtpServer.open());
  tearDown(() => server.close());

  Future<FtpTransferSession> connect() async {
    final session = FtpTransferSession(
      host: '127.0.0.1',
      port: server.listener.port,
      username: 'fixture',
      password: 'synthetic-password',
      secure: false,
      isCurrent: () => true,
      timeout: const Duration(seconds: 3),
    );
    addTearDown(session.close);
    await session.connect();
    return session;
  }

  test(
    'uploads bounded chunks and waits for the final server confirmation',
    () async {
      final release = Completer<void>();
      server.beforeCompletion = release.future;
      final session = await connect();
      var completed = false;
      final operation = session
          .upload(
            '/media/file.bin',
            Stream.fromIterable(
              List.generate(20, (index) => List.filled(5000, index)),
            ),
            100000,
          )
          .then((_) => completed = true);
      await server.uploadReceived.future;
      expect(server.uploads.single.length, 100000);
      expect(server.commands, contains('STOR /media/file.bin'));
      expect(completed, isFalse);
      release.complete();
      await operation;
    },
  );

  test(
    'download validates the declared size and a multiline final reply',
    () async {
      server.payload = Uint8List.fromList(
        List.generate(170000, (index) => index % 256),
      );
      server.multilineFinal = true;
      final progress = <(int, int)>[];
      final session = await connect();
      final bytes = await session
          .download(
            '/with spaces/file.bin',
            onProgress: (value, total) => progress.add((value, total)),
          )
          .expand((chunk) => chunk)
          .toList();
      expect(bytes, server.payload);
      expect(progress.last, (170000, 170000));
      expect(server.commands, contains('RETR /with spaces/file.bin'));
    },
  );

  test('a failed final reply never reports a completed upload', () async {
    server.finalCode = 451;
    final session = await connect();
    await expectLater(
      session.upload('/file', Stream.value([1, 2, 3]), 3),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'final reply',
          contains('451'),
        ),
      ),
    );
  });

  test('a failed final reply never reports a completed download', () async {
    server.finalCode = 426;
    final session = await connect();
    await expectLater(session.download('/file').toList(), throwsStateError);
  });

  for (final expectedSize in [2, 4]) {
    test(
      'download rejects an actual length different from $expectedSize',
      () async {
        server.declaredSize = expectedSize;
        final session = await connect();
        await expectLater(session.download('/file').toList(), throwsStateError);
      },
    );
  }

  for (final expectedSize in [2, 4]) {
    test(
      'upload rejects a declared length of $expectedSize before releasing final data',
      () async {
        final session = await connect();
        await expectLater(
          session.upload('/file', Stream.value([1, 2, 3]), expectedSize),
          throwsStateError,
        );
        await server.uploadReceived.future;
        expect(server.uploads.single, isEmpty);
      },
    );
  }

  test(
    'PASV uses the control peer instead of a third-party server address',
    () async {
      server.useEpsv = false;
      final session = await connect();
      expect(
        await session.download('/file').expand((chunk) => chunk).toList(),
        [1, 2, 3],
      );
      expect(server.commands, containsAll(['EPSV', 'PASV']));
    },
  );

  test(
    'two active transfers retain independent control and data sessions',
    () async {
      final first = await connect();
      final second = await connect();
      final results = await Future.wait([
        first.download('/one').expand((chunk) => chunk).toList(),
        second.download('/two').expand((chunk) => chunk).toList(),
      ]);
      expect(results, [
        [1, 2, 3],
        [1, 2, 3],
      ]);
      expect(server.connectionCount, 2);
    },
  );

  test(
    'arguments cannot inject commands into the control connection',
    () async {
      final session = await connect();
      await expectLater(
        session.upload('/file\r\nDELE /other', Stream.value([1]), 1),
        throwsArgumentError,
      );
      expect(
        server.commands.where((command) => command.startsWith('STOR')),
        isEmpty,
      );
    },
  );

  test(
    'closing the captured session interrupts a stalled source download',
    () async {
      server.beforeData = Completer<void>();
      final session = await connect();
      final assertion = expectLater(
        session.download('/file').toList(),
        throwsA(anything),
      );
      await server.retrStarted.future;
      session.close();
      await assertion;
      server.beforeData!.complete();
    },
  );
}

class _FtpServer {
  _FtpServer(this.listener) {
    listener.listen((socket) {
      connectionCount++;
      sockets.add(socket);
      unawaited(
        _serve(socket).catchError((Object _) {}).whenComplete(() {
          sockets.remove(socket);
          socket.destroy();
        }),
      );
    });
  }
  final ServerSocket listener;
  final sockets = <Socket>{};
  final passiveListeners = <ServerSocket>{};
  final commands = <String>[];
  final uploads = <List<int>>[];
  final uploadReceived = Completer<void>();
  final retrStarted = Completer<void>();
  Uint8List payload = Uint8List.fromList([1, 2, 3]);
  int? declaredSize;
  bool useEpsv = true;
  bool multilineFinal = false;
  int finalCode = 226;
  int connectionCount = 0;
  Future<void>? beforeCompletion;
  Completer<void>? beforeData;

  static Future<_FtpServer> open() async =>
      _FtpServer(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> _serve(Socket control) async {
    void reply(String value) => control.add(utf8.encode('$value\r\n'));
    reply('220-fixture FTP server');
    reply('220 Ready');
    ServerSocket? passive;
    Future<Socket>? nextData;
    await for (final command
        in control
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      commands.add(command);
      final verb = command.split(' ').first;
      switch (verb) {
        case 'USER':
          reply('331 Password required');
        case 'PASS':
          reply('230 Logged in');
        case 'TYPE':
          reply('200 Binary');
        case 'SIZE':
          reply('213 ${declaredSize ?? payload.length}');
        case 'EPSV' || 'PASV':
          if (verb == 'EPSV' && !useEpsv) {
            reply('502 EPSV unavailable');
            continue;
          }
          passive = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
          passiveListeners.add(passive);
          nextData = passive.first;
          reply(
            verb == 'EPSV'
                ? '229 Entering Extended Passive Mode (|||${passive.port}|)'
                : '227 Entering Passive Mode (192,0,2,15,${passive.port ~/ 256},${passive.port % 256})',
          );
        case 'STOR':
          reply('150 Opening data connection');
          final data = await nextData!;
          sockets.add(data);
          final bytes = await data.expand((chunk) => chunk).toList();
          uploads.add(bytes);
          if (!uploadReceived.isCompleted) uploadReceived.complete();
          await data.close();
          await beforeCompletion;
          reply('$finalCode Transfer complete');
          await passive?.close();
        case 'RETR':
          reply('150 Opening data connection');
          final data = await nextData!;
          sockets.add(data);
          if (!retrStarted.isCompleted) retrStarted.complete();
          await beforeData?.future;
          await data.addStream(Stream.value(payload));
          await data.flush();
          await data.close();
          await beforeCompletion;
          if (multilineFinal) reply('$finalCode-Transfer summary');
          reply('$finalCode Transfer complete');
          await passive?.close();
        default:
          reply('502 Unknown command');
      }
    }
  }

  Future<void> close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    for (final passive in passiveListeners) {
      await passive.close();
    }
    await listener.close();
  }
}
