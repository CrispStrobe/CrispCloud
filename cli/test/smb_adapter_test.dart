import 'dart:convert';
import 'dart:io';

import 'package:crisp/adapters/smb_adapter.dart';
import 'package:crisp/adapters/cli_adapter_factory.dart';
import 'package:crisp/adapters/cli_storage_client.dart';
import 'package:crisp/adapters/bounded_download.dart';
import 'package:crisp/cli_app.dart';
import 'package:crisp/config/cli_config.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> config([String backend = 'libsmb2']) => {
    'type': 'smb',
    'url': 'smb://localhost/books/',
    'username': 'reader',
    'password': 'test-only',
    'smbBackend': backend,
  };
  test(
    'factory and parser preserve policy and reject invalid settings',
    () async {
      for (final backend in SmbBackend.values) {
        final adapter =
            createAdapter('nas', config(backend.name)) as SmbCliAdapter;
        expect(adapter.session.backend, backend);
        expect(adapter.connection.requireEncryption, isTrue);
        await adapter.dispose();
      }
      expect(
        () => createAdapter('nas', config('unknown')),
        throwsFormatException,
      );
      expect(
        () => createAdapter('nas', {...config(), 'requireEncryption': 'false'}),
        throwsA(isA<CliConfigException>()),
      );
      expect(
        () => SmbCliAdapter.parseIdentity('reader@https://host', 'secret'),
        throwsA(isA<CliConfigException>()),
      );
    },
  );
  test(
    'CLI saved setting is read by subsequent operations and rejects non-SMB',
    () async {
      final tmp = Directory.systemTemp.createTempSync('smb-settings-');
      try {
        final path = '${tmp.path}/config.yaml';
        final saved = CliConfig(path: path)..saveProvider('nas', config());
        final runner = buildRunner(configPath: path);
        expect(await runner.run(['config', 'smb-backend', 'nas', 'rust']), 0);
        final adapter =
            createAdapter('nas', saved.providerConfig('nas')!) as SmbCliAdapter;
        expect(adapter.session.backend, SmbBackend.rust);
        await adapter.dispose();
        await expectLater(
          runner.run(['config', 'smb-backend', 'nas', 'unknown']),
          throwsFormatException,
        );
        expect(saved.providerConfig('nas')!['smbBackend'], 'rust');
        saved.saveProvider('other', {'type': 's3'});
        await expectLater(
          runner.run(['config', 'smb-backend', 'other', 'auto']),
          throwsA(isA<CliConfigException>()),
        );
      } finally {
        tmp.deleteSync(recursive: true);
      }
    },
  );
  test(
    'saved SMB passwords preserve literal strings when reconnecting',
    () async {
      final tmp = Directory.systemTemp.createTempSync(
        'smb-password-roundtrip-',
      );
      try {
        final path = '${tmp.path}/config.yaml';
        final saved = CliConfig(path: path);
        for (final password in [
          'true',
          'FALSE',
          'null',
          '~',
          '12345',
          '0123',
          '1.25',
          '1e3',
          '.inf',
          'ordinary-fixture-password',
          ' space: #value ',
          r'back\slash\n"quoted"',
          '[list-looking]',
          '{map: looking}',
          '*alias-looking',
        ]) {
          saved.saveProvider('nas', {...config(), 'password': password});
          // Reopen the file rather than checking only the emitter's text.
          final restored = CliConfig(
            path: path,
          ).providerConfig('nas', strict: true)!;
          expect(restored['password'], password);
          final adapter = createAdapter('nas', restored) as SmbCliAdapter;
          expect(adapter.connection.secret, password);
          await adapter.dispose();
        }
      } finally {
        tmp.deleteSync(recursive: true);
      }
    },
  );

  test('persisted invalid credentials stay rejected after round-trip', () {
    final tmp = Directory.systemTemp.createTempSync(
      'smb-invalid-password-roundtrip-',
    );
    try {
      final path = '${tmp.path}/config.yaml';
      final saved = CliConfig(path: path);
      for (final password in ['', 'line\nbreak\rreturn\ttab\u0000']) {
        saved.saveProvider('nas', {...config(), 'password': password});
        final restored = CliConfig(
          path: path,
        ).providerConfig('nas', strict: true)!;
        expect(restored['password'], password);
        expect(
          () => createAdapter('nas', restored),
          throwsA(
            isA<RemoteFormatException>().having(
              (error) => error.code,
              'code',
              RemoteErrorCode.invalidCredentials,
            ),
          ),
        );
      }
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  final python = Platform.environment['CRISPER_SMB_PYTHON'];
  for (final backend in SmbBackend.values) {
    test(
      '${backend.name}: CLI connect, stream upload, download and mutations',
      () async {
        final root = await Directory.systemTemp.createTemp('cli-smb-');
        final local = await Directory.systemTemp.createTemp('cli-smb-output-');
        final server = await Process.start(python!, [
          '../packages/crisp_storage/tool/smb_fixture.py',
          root.path,
        ]);
        final errors = server.stderr.drain<void>();
        SmbCliAdapter? adapter;
        try {
          final ready =
              jsonDecode(
                    await server.stdout
                        .transform(utf8.decoder)
                        .transform(const LineSplitter())
                        .first
                        .timeout(const Duration(seconds: 15)),
                  )
                  as Map;
          final cfg = {
            ...config(backend.name),
            'url': 'smb://127.0.0.1:${ready['port']}/books/',
            'password': 'fixture-password',
            'requireEncryption': false,
          };
          adapter = createAdapter('nas', cfg) as SmbCliAdapter;
          final source = File('${local.path}/source.bin');
          final bytes = List.generate(1024 * 1024 + 3, (i) => i % 251);
          await source.writeAsBytes(bytes);
          await adapter.createDirectory('/folder');
          await uploadLocalFile(adapter, source, 'Chapter #1.bin', '/folder');
          final listing = await adapter.list('/folder');
          expect(listing.single.path, '/folder/Chapter #1.bin');
          expect(listing.single.size, bytes.length);
          await expectLater(
            adapter.downloadBytesBounded(listing.single.path, maxBytes: 4),
            throwsA(isA<CliDownloadLimitException>()),
          );
          final output = File('${local.path}/download.bin');
          await adapter.download(listing.single.path, output.path);
          expect(await output.readAsBytes(), bytes);
          expect(await File('${output.path}.part').exists(), isFalse);
          await adapter.move(listing.single.path, '/folder/renamed');
          expect(await adapter.stat(listing.single.path), isNull);
          await adapter.delete('/folder/renamed');
          await adapter.delete('/folder');
          expect(await adapter.list('/'), isEmpty);
          await expectLater(adapter.list('../escape'), throwsFormatException);
          final strict =
              createAdapter('strict', {...cfg, 'requireEncryption': true})
                  as SmbCliAdapter;
          try {
            await expectLater(
              strict.list('/'),
              throwsA(isA<RemoteException>()),
            );
          } finally {
            await strict.dispose();
          }
        } finally {
          await adapter?.dispose();
          server.kill();
          await server.exitCode;
          await errors;
          await root.delete(recursive: true);
          await local.delete(recursive: true);
        }
      },
      skip:
          python == null ||
              (backend != SmbBackend.libsmb2 &&
                  Platform.environment['CRISP_SMB_LIBRARY'] == null)
          ? 'Set CRISPER_SMB_PYTHON and CRISP_SMB_LIBRARY.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
