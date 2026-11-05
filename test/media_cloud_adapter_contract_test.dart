import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/azure_blob_adapter.dart';
import 'package:crisp_cloud/services/azure_config_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_config_service.dart';
import 'package:crisp_cloud/services/pcloud_client_adapter.dart';
import 'package:crisp_cloud/services/pcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:filen_client/cache.dart' as filen;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('OneDrive sends the complete encoded copy path for root and nested directories', () async {
    final config = OneDriveConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    await config.saveCredentials({
      'client_id': 'test-app',
      'refresh_token': 'test-refresh',
      'email': 'editor@example.test',
    });
    final adapter = OneDriveClientAdapter(config: config);
    final uploads = <http.Request>[];
    await http.runWithClient(
      () async {
        expect(await adapter.restoreCredentials(), isTrue);
        for (final directory in ['/', '/media', '/media/']) {
          await adapter.uploadFile([1, 2, 3], 'edited #1%20.wav', directory);
        }
      },
      () => MockClient((request) async {
        if (request.url.host == 'login.microsoftonline.com') {
          return _json({'access_token': 'test-access', 'expires_in': 3600});
        }
        expect(request.method, 'PUT');
        expect(request.url.host, 'graph.microsoft.com');
        expect(request.headers['authorization'], 'Bearer test-access');
        uploads.add(request);
        return _json({'id': 'new-copy'});
      }),
    );
    expect(
      uploads.map((request) => Uri.decodeComponent(request.url.path)).toList(),
      [
        '/v1.0/me/drive/root:/edited #1%20.wav:/content',
        '/v1.0/me/drive/root:/media/edited #1%20.wav:/content',
        '/v1.0/me/drive/root:/media/edited #1%20.wav:/content',
      ],
    );
    for (final request in uploads) {
      expect(request.bodyBytes, [1, 2, 3]);
      expect(request.url.fragment, isEmpty);
      expect(request.url.query, isEmpty);
      expect(request.url.toString(), contains('edited%20%231%2520.wav'));
      expect(request.url.path, isNot(contains('::')));
    }
  });

  test('Azure respects explicit upload directories and still accepts legacy full blob paths', () async {
    final adapter = AzureBlobAdapter(
      config: AzureConfigService(secureStorage: InMemorySecureStorage()),
    );
    await adapter.loginWithSas(
      accountName: 'fixture',
      sasTokenOrUrl: 'sig=test',
      container: 'container',
    );
    final paths = <String>[];
    await http.runWithClient(
      () async {
        await adapter.uploadFile([1, 2], 'copy.wav', '/container/media/');
        await adapter.uploadFile([3, 4], 'copy.wav', '/container/');
        await adapter.uploadFile(
          [5, 6],
          'ignored.wav',
          '/container/legacy.wav',
        );
      },
      () => MockClient((request) async {
        expect(request.method, 'PUT');
        paths.add(request.url.path);
        return http.Response('', 201);
      }),
    );
    expect(paths, [
      '/container/media/copy.wav',
      '/container/copy.wav',
      '/container/legacy.wav',
    ]);
  });

  test('Azure exposes a continuation marker rather than implying a partial folder is complete', () async {
    final adapter = AzureBlobAdapter(
      config: AzureConfigService(secureStorage: InMemorySecureStorage()),
    );
    await adapter.loginWithSas(
      accountName: 'fixture',
      sasTokenOrUrl: 'sig=test',
      container: 'container',
    );
    final listing = await http.runWithClient(
      () => adapter.listPathForEdit('/container/media'),
      () => MockClient((request) async {
        expect(request.url.queryParameters['prefix'], 'media/');
        return http.Response('''
<EnumerationResults><Blobs><Blob><Name>media/source.wav</Name><Properties>
<Content-Length>4096</Content-Length></Properties></Blob></Blobs>
<NextMarker>another-page</NextMarker></EnumerationResults>
''', 200);
      }),
    );
    expect(listing['nextMarker'], 'another-page');
    expect((listing['files'] as List).single['name'], 'source.wav');
  });

  test('Google Drive fresh reads replace stale folder IDs and never fall back to root', () async {
    final config = GDriveConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    await config.saveCredentials({
      'client_id': 'test-app',
      'refresh_token': 'test-refresh',
      'email': 'editor@example.test',
    });
    final adapter = GDriveClientAdapter(config: config);
    String? folderId = 'old-folder';
    var folderLookups = 0;
    var rootListings = 0;
    await http.runWithClient(
      () async {
        expect(await adapter.restoreCredentials(), isTrue);
        final original = await adapter.listPath('/Media');
        expect((original['files'] as List).single['uuid'], 'source-old-folder');
        folderId = 'new-folder';
        final fresh = await adapter.listPathForEdit('/Media');
        expect((fresh['files'] as List).single['uuid'], 'source-new-folder');
        folderId = null;
        await expectLater(adapter.listPathForEdit('/Media'), throwsStateError);
      },
      () => MockClient((request) async {
        if (request.url.host == 'oauth2.googleapis.com') {
          return _json({'access_token': 'test-access', 'expires_in': 3600});
        }
        final query = request.url.queryParameters['q'] ?? '';
        if (query.contains("mimeType='application/vnd.google-apps.folder'")) {
          folderLookups++;
          return _json({
            'files': [
              if (folderId != null) {'id': folderId, 'name': 'Media'},
            ],
          });
        }
        if (query.startsWith("'root'")) rootListings++;
        final id = query.contains("'old-folder'") ? 'old-folder' : 'new-folder';
        return _json({
          'files': [
            {
              'id': 'source-$id',
              'name': 'source.wav',
              'mimeType': 'audio/wav',
              'size': '4096',
              'modifiedTime': '2026-01-01T00:00:00Z',
            },
          ],
        });
      }),
    );
    expect(folderLookups, 3);
    expect(rootListings, 0);
  });

  test(
    'pCloud fresh reads invalidate a renamed folder ID before listing files',
    () async {
      final config = PCloudConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      );
      await config.saveCredentials({
        'access_token': 'test-access',
        'email': 'editor@example.test',
      });
      final adapter = PCloudClientAdapter(config: config);
      var folderId = 1;
      var folderLookups = 0;
      await http.runWithClient(
        () async {
          expect(await adapter.restoreCredentials(), isTrue);
          final original = await adapter.listPath('/Media');
          expect((original['files'] as List).single['uuid'], 'f_101');
          folderId = 2;
          final fresh = await adapter.listPathForEdit('/Media');
          expect((fresh['files'] as List).single['uuid'], 'f_102');
        },
        () => MockClient((request) async {
          if (request.url.path == '/userinfo') {
            return _json({'result': 0, 'email': 'editor@example.test'});
          }
          expect(request.url.path, '/listfolder');
          if (request.url.queryParameters['nofiles'] == '1') {
            folderLookups++;
            return _json({
              'result': 0,
              'metadata': {
                'contents': [
                  {'name': 'Media', 'isfolder': true, 'folderid': folderId},
                ],
              },
            });
          }
          final current = int.parse(request.url.queryParameters['folderid']!);
          return _json({
            'result': 0,
            'metadata': {
              'contents': [
                {
                  'name': 'source.wav',
                  'isfolder': false,
                  'fileid': 100 + current,
                  'size': 4096,
                },
              ],
            },
          });
        }),
      );
      expect(folderLookups, 2);
    },
  );

  test('Filen fresh reads evict the source folder but preserve unrelated cached files', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'filen-fresh-test-',
    );
    addTearDown(() async {
      await temporary.delete(recursive: true);
    });
    var requests = 0;
    await http.runWithClient(
      () async {
        final adapter = FilenClientAdapter(
          config: FilenConfigService(
            configPath: temporary.path,
            secureStorage: InMemorySecureStorage(),
          ),
        );
        addTearDown(adapter.client.api.client.close);
        adapter.client.setAuth({
          'apiKey': 'test-key',
          'baseFolderUUID': 'root-folder',
          'email': 'editor@example.test',
        });
        final cache = adapter.client.cache;
        final now = DateTime.now();
        cache.folderCache['root-folder'] = filen.CacheEntry(
          items: <Map<String, dynamic>>[],
          timestamp: now,
        );
        cache.fileCache['root-folder'] = filen.CacheEntry(
          items: [
            {'name': 'stale.wav', 'uuid': 'stale', 'size': 12, 'type': 'file'},
          ],
          timestamp: now,
        );
        final unrelated = filen.CacheEntry(
          items: [
            {'name': 'keep.wav'},
          ],
          timestamp: now,
        );
        cache.fileCache['unrelated-folder'] = unrelated;
        final ordinary = await adapter.listPath('/');
        expect((ordinary['files'] as List).single['name'], 'stale.wav');
        expect(requests, 0);
        final fresh = await adapter.listPathForEdit('/');
        expect(fresh['files'], isEmpty);
        expect(fresh['folders'], isEmpty);
        expect(cache.fileCache['unrelated-folder'], same(unrelated));
      },
      () => MockClient((request) async {
        expect(request.url.path, '/v3/dir/content');
        requests++;
        return _json({
          'status': true,
          'data': {'folders': [], 'uploads': []},
        });
      }),
    );
    expect(requests, 2);
  });
}
