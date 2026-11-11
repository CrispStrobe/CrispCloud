import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:test/test.dart';

void main() {
  final python = Platform.environment['CRISPER_SMB_PYTHON'];
  final library = Platform.environment['CRISP_SMB_LIBRARY'];
  test(
    'Rust bridge: CRUD, bounded reads, resume, security refusal, cancellation',
    () async {
      final root = await Directory.systemTemp.createTemp('rust-smb-fixture-');
      final outputDir = await Directory.systemTemp.createTemp(
        'rust-smb-output-',
      );
      final server = await Process.start(
        python!,
        ['tool/smb_fixture.py', root.path],
        environment: {'CRISP_SMB_FIXTURE_DELAY': '0.015'},
      );
      final stderr = server.stderr.drain<void>();
      final ready = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      final port = (jsonDecode(ready) as Map)['port'];
      final sessions = <SmbSession>[];
      SmbSession session({
        bool encrypted = false,
        String password = 'fixture-password',
        String rootPath = '',
      }) {
        final s = SmbSession(
          RemoteConnection(
            id: 'test',
            name: 'test',
            kind: 'smb',
            url: 'smb://127.0.0.1:$port/books/$rootPath',
            username: 'reader',
            secret: password,
            requireEncryption: encrypted,
          ),
          backend: SmbBackend.auto,
        );
        sessions.add(s);
        return s;
      }

      try {
        final s = session();
        await s.mkdir(s.urlForPath('folder'));
        final scoped = session(rootPath: 'folder/');
        final path = scoped.urlForPath('Chapter #1.bin');
        final data = Uint8List.fromList(
          List.generate(4 * 1024 * 1024 + 17, (i) => i % 251),
        );
        await scoped.write(path, data);
        expect(scoped.effectiveBackend, SmbBackend.rust);
        expect((await scoped.browse('')).single.path, path);
        expect((await scoped.stat(path))!.size, data.length);
        expect(await scoped.stat(scoped.urlForPath('missing')), isNull);
        final result = BytesBuilder(copy: false);
        await for (final bytes in scoped.stream(path)) {
          expect(bytes.length, lessThanOrEqualTo(256 * 1024));
          result.add(bytes);
        }
        expect(result.takeBytes(), data);
        await expectLater(
          scoped.browse('../'),
          throwsA(isA<RemoteException>()),
        );
        await expectLater(
          scoped.delete('', directory: true),
          throwsA(isA<RemoteException>()),
        );
        final output = File('${outputDir.path}/staging');
        await expectLater(
          scoped.download(
            path,
            output,
            limit: data.length,
            onBytes: (n) {
              if (n > 0) throw StateError('pause fixture');
            },
          ),
          throwsStateError,
        );
        scoped.close();
        final prefix = await output.length();
        expect(prefix, inExclusiveRange(0, data.length));
        expect(await output.readAsBytes(), data.sublist(0, prefix));
        final resumed = session(rootPath: 'folder/');
        final progress = <int>[];
        await resumed.download(
          path,
          output,
          limit: data.length,
          onBytes: progress.add,
        );
        expect(progress.first, greaterThanOrEqualTo(prefix));
        expect(progress.last, data.length);
        expect(await output.readAsBytes(), data);
        // A foreign libsmb2 validator must restart rather than concatenate.
        await output.writeAsBytes([99]);
        await File('${output.path}.resume').writeAsString(
          jsonEncode({'source': path, 'validator': 'libsmb2-validator'}),
        );
        await resumed.download(path, output, limit: data.length);
        expect(await output.readAsBytes(), data);
        await resumed.write(path, Uint8List.fromList([9, 8, 7]));
        await resumed.download(path, output, limit: data.length);
        expect(await output.readAsBytes(), [9, 8, 7]);
        await expectLater(
          resumed.download(path, output, limit: 2),
          throwsA(isA<RemoteException>()),
        );
        expect(await output.readAsBytes(), [9, 8, 7]);
        final renamed = resumed.urlForPath('renamed');
        await resumed.rename(path, renamed);
        await resumed.delete(renamed, directory: false);
        expect(await resumed.browse(''), isEmpty);
        final encryption = session(encrypted: true);
        await expectLater(
          encryption.browse(''),
          throwsA(isA<RemoteException>()),
        );
        expect(
          encryption.effectiveBackend,
          SmbBackend.rust,
          reason: 'No downgrade on an SMB2-only server',
        );
        final wrong = session(password: 'wrong-password');
        await expectLater(wrong.browse(''), throwsA(isA<RemoteException>()));
        expect(
          wrong.effectiveBackend,
          SmbBackend.rust,
          reason: 'No second authentication through libsmb2',
        );
        s.close();
        await expectLater(s.browse(''), throwsA(isA<RemoteException>()));
      } finally {
        for (final s in sessions) {
          s.close();
        }
        server.kill();
        await server.exitCode.timeout(const Duration(seconds: 10));
        await stderr;
        await root.delete(recursive: true);
        await outputDir.delete(recursive: true);
      }
    },
    skip: python == null || library == null
        ? 'Set CRISPER_SMB_PYTHON and CRISP_SMB_LIBRARY.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
