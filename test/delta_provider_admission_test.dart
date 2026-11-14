import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/pcloud_client_adapter.dart';
import 'package:crisp_cloud/services/pcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _legacyPlan = BlockTransferPlan(
  filePath: '/original.bin',
  blockSize: 64 * 1024,
  changedBlockIndices: [0],
  totalSize: 1,
  transferSize: 1,
  operations: [
    BlockOperation(
      type: BlockOperationType.upload,
      blockIndex: 0,
      offset: 0,
      size: 1,
    ),
  ],
);

class _CredentialGuard extends InMemorySecureStorage {
  bool reject = true;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    if (reject) {
      throw StateError('Delta admission attempted credential access.');
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (reject) throw StateError('Delta admission attempted credential write.');
    await super.write(key, value);
  }
}

class _NetworkGuard extends http.BaseClient {
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Delta admission attempted a network request.');
  }
}

class _IoGuard {
  final network = _NetworkGuard();
  int fileAccesses = 0;
  int directoryAccesses = 0;

  Future<void> run(Future<void> Function() body) =>
      IOOverrides.runZoned<Future<void>>(
        () => http.runWithClient(body, () => network),
        createFile: (path) {
          fileAccesses++;
          throw StateError('Delta admission attempted local file access.');
        },
        createDirectory: (path) {
          directoryAccesses++;
          throw StateError('Delta admission attempted cache directory access.');
        },
      );

  void expectUntouched() {
    expect(network.requests, 0);
    expect(fileAccesses, 0);
    expect(directoryAccesses, 0);
  }
}

PCloudClientAdapter _pcloud(_CredentialGuard secure) => PCloudClientAdapter(
  config: PCloudConfigService(configPath: '', secureStorage: secure),
);

NextcloudClientAdapter _nextcloud(_CredentialGuard secure) =>
    NextcloudClientAdapter(
      config: NextcloudConfigService(configPath: '', secureStorage: secure),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final enabled in [false, true]) {
    test(
      'pCloud delta enabled=$enabled declines before any side effect',
      () async {
        final secure = _CredentialGuard();
        final adapter = _pcloud(secure)..deltaSyncEnabled = enabled;
        final guard = _IoGuard();
        var progressCalls = 0;

        await guard.run(() async {
          expect(
            await adapter.deltaUpload(
              '/source-not-opened.bin',
              '/original.bin',
              cacheDir: '/cache-not-opened',
              onProgress: (_, _, _) => progressCalls++,
            ),
            isNull,
          );
        });

        guard.expectUntouched();
        expect(secure.reads, 0);
        expect(secure.writes, 0);
        expect(progressCalls, 0);
        expect(adapter.isAuthenticated, isFalse);
      },
    );

    for (final serverApp in [false, true]) {
      test(
        'Nextcloud delta enabled=$enabled app=$serverApp declines without I/O',
        () async {
          final secure = _CredentialGuard();
          final adapter = _nextcloud(secure)
            ..deltaSyncEnabled = enabled
            ..deltaSyncMinSize = 0
            ..deltaSyncServerAppUrl = serverApp
                ? 'https://cloud.example.test/index.php/apps/crispcloud_delta'
                : null;
          final guard = _IoGuard();
          var progressCalls = 0;

          await guard.run(() async {
            expect(
              await adapter.deltaUpload(
                '/source-not-opened.bin',
                '/original.bin',
                cacheDir: '/cache-not-opened',
                onProgress: (_, _, _) => progressCalls++,
              ),
              isNull,
            );
            expect(
              await adapter.deltaDownload(
                '/original.bin',
                '/local-not-opened.bin',
                cacheDir: '/cache-not-opened',
                onProgress: (_, _, _) => progressCalls++,
              ),
              isNull,
            );
            await expectLater(
              adapter.uploadDeltaBlocks(
                '/original.bin',
                '/source-not-opened.bin',
                _legacyPlan,
              ),
              throwsA(isA<UnsupportedError>()),
            );
          });

          guard.expectUntouched();
          expect(secure.reads, 0);
          expect(secure.writes, 0);
          expect(progressCalls, 0);
          expect(adapter.isAuthenticated, isFalse);
        },
      );
    }
  }

  test(
    'authenticated delta refusal preserves original files and cache bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'delta-admission-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final original = File('${directory.path}/original.bin');
      final cache = File('${directory.path}/block-map.json');
      final originalBytes = List<int>.generate(257, (index) => index & 255);
      final cacheBytes = utf8.encode(
        'an untrusted map must not even be parsed',
      );
      await original.writeAsBytes(originalBytes);
      await cache.writeAsBytes(cacheBytes);

      final pcloudSecure = _CredentialGuard()..reject = false;
      final nextcloudSecure = _CredentialGuard()..reject = false;
      final pcloud = _pcloud(pcloudSecure)..deltaSyncEnabled = true;
      final nextcloud = _nextcloud(nextcloudSecure)
        ..deltaSyncEnabled = true
        ..deltaSyncMinSize = 0
        ..deltaSyncServerAppUrl =
            'https://cloud.example.test/index.php/apps/crispcloud_delta';
      await pcloud.config.saveCredentials({
        'app_key': 'fixture',
        'access_token': 'synthetic-token',
        'email': 'fixture@example.test',
      });
      await nextcloud.config.saveCredentials({
        'username': 'fixture',
        'password': 'fixture',
        'serverUrl': 'https://cloud.example.test',
      });
      await http.runWithClient(
        () async {
          expect(await pcloud.restoreCredentials(), isTrue);
          expect(await nextcloud.restoreCredentials(), isTrue);
        },
        () => MockClient((request) async {
          if (request.url.path == '/userinfo') {
            return http.Response(
              jsonEncode({'result': 0, 'email': 'fixture@example.test'}),
              200,
            );
          }
          expect(request.method, 'PROPFIND');
          return http.Response('', 207);
        }),
      );
      for (final secure in [pcloudSecure, nextcloudSecure]) {
        secure
          ..reject = true
          ..reads = 0
          ..writes = 0;
      }

      final guard = _IoGuard();
      await guard.run(() async {
        expect(
          await pcloud.deltaUpload(
            original.path,
            '/original.bin',
            cacheDir: directory.path,
          ),
          isNull,
        );
        expect(
          await nextcloud.deltaUpload(
            original.path,
            '/original.bin',
            cacheDir: directory.path,
          ),
          isNull,
        );
        expect(
          await nextcloud.deltaDownload(
            '/original.bin',
            original.path,
            cacheDir: directory.path,
          ),
          isNull,
        );
        await expectLater(
          nextcloud.uploadDeltaBlocks(
            '/original.bin',
            original.path,
            _legacyPlan,
          ),
          throwsA(isA<UnsupportedError>()),
        );
      });

      guard.expectUntouched();
      for (final secure in [pcloudSecure, nextcloudSecure]) {
        expect(secure.reads, 0);
        expect(secure.writes, 0);
      }
      expect(await original.readAsBytes(), originalBytes);
      expect(await cache.readAsBytes(), cacheBytes);
      expect(await directory.list().length, 2);
      expect(pcloud.isAuthenticated, isTrue);
      expect(nextcloud.isAuthenticated, isTrue);
    },
  );

  Map<String, Object> emptyMap() => {
    'filePath': '/original.bin',
    'totalSize': 0,
    'blockSize': 64 * 1024,
    'blockCount': 0,
    'signatures': <Object>[],
    'createdAt': '2026-11-14T00:00:00Z',
  };

  for (final malformed in [false, true]) {
    test(
      'Nextcloud informational map validates geometry malformed=$malformed',
      () async {
        final secure = _CredentialGuard()..reject = false;
        final adapter = _nextcloud(secure)
          ..deltaSyncServerAppUrl =
              'https://cloud.example.test/index.php/apps/crispcloud_delta';
        await adapter.config.saveCredentials({
          'username': 'fixture',
          'password': 'fixture',
          'serverUrl': 'https://cloud.example.test',
        });
        final map = emptyMap();
        if (malformed) map['blockCount'] = 1;
        var requests = 0;
        final result = await http.runWithClient(
          () => adapter.fetchServerBlockMap('/original.bin'),
          () => MockClient((request) async {
            requests++;
            expect(request.method, 'GET');
            return http.Response(jsonEncode(map), 200);
          }),
        );
        expect(requests, 1);
        if (malformed) {
          expect(result, isNull);
        } else {
          expect(result, isNotNull);
          expect(result!.totalSize, 0);
          expect(result.identity, isNull);
        }
      },
    );
  }
}
