@Tags(['live'])
library;

// Live Filen/Internxt round trips through the app adapters for both engines.
//
// Opt-in only. Credentials come from the environment and are never printed:
//   CRISP_LIVE_FILEN_EMAIL / CRISP_LIVE_FILEN_PASSWORD
//   CRISP_LIVE_INTERNXT_EMAIL / CRISP_LIVE_INTERNXT_PASSWORD (test account!)
// The Rust engine additionally needs CRISP_CLOUD_LIBRARY (absolute path to
// the built crisp_cloud_bridge library, see `dart run bin/build_cloud.dart`).
// Every run works inside one uniquely named scratch folder and removes it.
import 'dart:io';
import 'dart:math';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/connection_failure.dart';
import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/internxt_client_adapter.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_storage/rust_cloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internxt_client/internxt_client.dart' as inxt;
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryInternxtStorage implements inxt.ConfigStorage {
  final values = <String, String>{};
  @override
  void init(String dataDir, List<String> subDirs) {}
  @override
  Future<bool> exists(String key) async => values.containsKey(key);
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

String? _env(String key) {
  final value = Platform.environment[key];
  return value == null || value.isEmpty ? null : value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every HTTP request with 400; the Dart engines
  // need the real network here.
  HttpOverrides.global = null;
  final rustLibrary = _env('CRISP_CLOUD_LIBRARY');
  final providers = {
    'filen': (_env('CRISP_LIVE_FILEN_EMAIL'), _env('CRISP_LIVE_FILEN_PASSWORD')),
    'internxt': (
      _env('CRISP_LIVE_INTERNXT_EMAIL'),
      _env('CRISP_LIVE_INTERNXT_PASSWORD'),
    ),
  };

  for (final MapEntry(key: provider, value: (email, password))
      in providers.entries) {
    for (final engine in [CloudEngine.dart, CloudEngine.rust]) {
      final skip = email == null || password == null
          ? 'Set CRISP_LIVE_${provider.toUpperCase()}_EMAIL/_PASSWORD'
          : engine == CloudEngine.rust && rustLibrary == null
          ? 'Set CRISP_CLOUD_LIBRARY for the Rust engine'
          : null;
      group('$provider live (${engine.name} engine)', skip: skip, () {
        late CloudStorageClient client;
        late String scratch;
        final payload = List<int>.generate(
          300 * 1024 + 17,
          (i) => (i * 31 + 7) & 0xff,
        );

        setUpAll(() async {
          SharedPreferences.setMockInitialValues({});
          final temp = await Directory.systemTemp.createTemp('live-cfg-');
          if (provider == 'filen') {
            final adapter = FilenClientAdapter(
              config: FilenConfigService(
                configPath: temp.path,
                secureStorage: InMemorySecureStorage(),
              ),
            )..engine = engine;
            await adapter.login(email!, password!);
            expect(adapter.effectiveEngine, engine);
            client = adapter;
          } else {
            final adapter = InternxtClientAdapter(
              config: inxt.ConfigService(
                configPath: temp.path,
                storage: _MemoryInternxtStorage(),
              ),
            )..engine = engine;
            await adapter.login(email!, password!);
            expect(adapter.effectiveEngine, engine);
            client = adapter;
          }
          final suffix = Random.secure().nextInt(1 << 32).toRadixString(16);
          scratch =
              '/crispcloud-live-${engine.name}-'
              '${DateTime.now().millisecondsSinceEpoch}-$suffix';
          await client.createFolderPath(scratch);
        });

        tearDownAll(() async {
          // Only the unique scratch folder is ever removed.
          try {
            if (await client.resolvePath(scratch) != null) {
              await client.deletePath(scratch);
            }
          } finally {
            await client.logout();
          }
        });

        test('scratch folder resolves as a folder', () async {
          final resolved = await client.resolvePath(scratch);
          expect(resolved?['type'], 'folder');
        });

        test('upload, list, download bytes, stream and to file', () async {
          var lastProgress = 0;
          await client.uploadFile(
            payload,
            'blob.bin',
            scratch,
            onProgress: (done, _) => lastProgress = done,
          );
          expect(lastProgress, greaterThan(0));
          final listing = await client.listPath(scratch);
          final files = (listing['files'] as List).cast<Map>();
          final row = files.firstWhere(
            (f) =>
                f['name'] == 'blob.bin' ||
                '${f['name']}.${f['type'] ?? f['fileType'] ?? ''}' ==
                    'blob.bin',
          );
          expect(row['size'], payload.length);
          expect(await client.downloadFileBytes('$scratch/blob.bin'), payload);
          final streamed = await client
              .downloadStream('$scratch/blob.bin')
              .expand((c) => c)
              .toList();
          expect(streamed, payload);
          final out = File(
            '${(await Directory.systemTemp.createTemp('live-out-')).path}/b',
          );
          await client.downloadFileByPath('$scratch/blob.bin', out.path);
          expect(await out.readAsBytes(), payload);
        });

        test('empty file round trip', () async {
          if (provider == 'internxt') {
            // Internxt refuses zero-byte files on every plan.
            await expectLater(
              client.uploadFile(const [], 'empty.txt', scratch),
              throwsA(isA<InternxtEmptyFileUnsupported>()),
            );
            expect(await client.resolvePath('$scratch/empty.txt'), isNull);
            return;
          }
          await client.uploadFile(const [], 'empty.txt', scratch);
          expect(await client.downloadFileBytes('$scratch/empty.txt'), isEmpty);
        });

        test('nested folders, rename, move and delete', () async {
          await client.createFolderPath('$scratch/a/b');
          expect((await client.resolvePath('$scratch/a/b'))?['type'], 'folder');
          await client.uploadFile([1, 2, 3], 'note.txt', '$scratch/a');
          await client.renamePath('$scratch/a/note.txt', 'renamed.txt');
          expect(await client.resolvePath('$scratch/a/note.txt'), isNull);
          await client.movePath('$scratch/a/renamed.txt', '$scratch/a/b');
          expect(
            await client.downloadFileBytes('$scratch/a/b/renamed.txt'),
            [1, 2, 3],
          );
          await client.renamePath('$scratch/a/b', 'c');
          expect((await client.resolvePath('$scratch/a/c'))?['type'], 'folder');
          await client.deletePath('$scratch/a/c/renamed.txt');
          expect(await client.resolvePath('$scratch/a/c/renamed.txt'), isNull);
        });

        test('missing paths resolve to null', () async {
          expect(await client.resolvePath('$scratch/does-not-exist'), isNull);
        });
      });
    }
  }
}
