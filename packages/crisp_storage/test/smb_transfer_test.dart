import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/crisp_storage.dart';
import 'package:test/test.dart';

void main() {
  final python = Platform.environment['CRISPER_SMB_PYTHON'];
  test(
    'failed open retries; bounded downloads preserve resume and revision checks',
    () async {
      final root = await Directory.systemTemp.createTemp('smb-transfer-');
      final outputDir = await Directory.systemTemp.createTemp('smb-output-');
      final reservation = await ServerSocket.bind('127.0.0.1', 0);
      final port = reservation.port;
      await reservation.close();
      final connection = RemoteConnection(
        id: 'fixture',
        name: 'fixture',
        kind: 'smb',
        url: 'smb://127.0.0.1:$port/books/',
        username: 'reader',
        secret: 'fixture-password',
        // The hermetic fixture offers SMB2 only. Production defaults stay on.
        requireEncryption: false,
      );
      final session = SmbSession(connection);
      Process? server;
      try {
        // No server exists yet. Caching this failed Future would poison every
        // subsequent operation, even after the server comes back online.
        await expectLater(session.browse(''), throwsA(isA<RemoteException>()));
        server = await Process.start(python!, [
          'tool/smb_fixture.py',
          root.path,
          '$port',
        ]);
        final errors = StringBuffer();
        final stderr = server.stderr
            .transform(utf8.decoder)
            .listen(errors.write);
        addTearDown(stderr.cancel);
        final ready = await server.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 15));
        expect((jsonDecode(ready) as Map)['port'], port, reason: '$errors');

        final data = Uint8List.fromList(
          List.generate(2 * 1024 * 1024 + 17, (i) => i % 251),
        );
        final source = File('${root.path}/chapter.bin');
        await source.writeAsBytes(data);
        // Concurrent callers must reuse the retried connection successfully.
        final listings = await Future.wait([
          session.browse(''),
          session.browse(''),
        ]);
        expect(
          listings.every((entries) => entries.single.name == 'chapter.bin'),
          isTrue,
        );
        final output = File('${outputDir.path}/chapter.bin');
        final path = session.urlForPath('chapter.bin');
        await expectLater(
          session.download(
            path,
            output,
            limit: data.length,
            onBytes: (bytes) {
              if (bytes > 0) throw StateError('pause fixture');
            },
          ),
          throwsStateError,
        );
        final prefix = await output.length();
        expect(prefix, inExclusiveRange(0, data.length));
        expect(await output.readAsBytes(), data.sublist(0, prefix));

        final progress = <int>[];
        await session.download(
          path,
          output,
          limit: data.length,
          onBytes: progress.add,
        );
        expect(progress.first, prefix);
        expect(progress.last, data.length);
        expect(await output.readAsBytes(), data);

        // An incompatible source must truncate, not append to the old output.
        await source.writeAsBytes([9, 8, 7]);
        progress.clear();
        await session.download(
          path,
          output,
          limit: data.length,
          onBytes: progress.add,
        );
        expect(progress.first, 0);
        expect(await output.readAsBytes(), [9, 8, 7]);
        await expectLater(
          session.download(path, output, limit: 2),
          throwsA(isA<RemoteException>()),
        );
        expect(await output.readAsBytes(), [9, 8, 7]);

        session.close();
        await expectLater(session.browse(''), throwsA(isA<RemoteException>()));
      } finally {
        session.close();
        server?.kill();
        await server?.exitCode.timeout(const Duration(seconds: 10));
        await root.delete(recursive: true);
        await outputDir.delete(recursive: true);
      }
    },
    skip: python == null
        ? 'Set CRISPER_SMB_PYTHON to a Python with impacket.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
