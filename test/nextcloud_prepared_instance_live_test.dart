@Tags(['live'])
@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/multi_cloud_provider.dart';
import 'package:crisp_cloud/providers/panel_provider.dart';
import 'package:crisp_cloud/providers/panel_source_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class _Local extends Fake implements LocalFileService {
  @override
  String currentPath = '/tmp';
  @override
  String? get grantedBasePath => '/tmp';
  @override
  Future<String> getInitialPath() async => currentPath;
  @override
  Future<String> getSafeFallbackDirectory() async => currentPath;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async => [];
  @override
  Future<void> refresh() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['CRISPCLOUD_NEXTCLOUD_TEST_CONFIG'];
  final unavailable = path == null
      ? 'Requires private prepared-instance test config.'
      : false;
  late Map<String, dynamic> settings;
  final originalHttpOverrides = HttpOverrides.current;
  tearDownAll(() => HttpOverrides.global = originalHttpOverrides);
  setUpAll(() {
    HttpOverrides.global = null;
    if (path != null) {
      settings =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('real prepared Nextcloud authenticates, lists DAV and detects the updated delta app', () async {
    final config = NextcloudConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    final client = NextcloudClientAdapter(config: config);
    await client.login(
      '${settings['username']}@${settings['url']}',
      settings['password'] as String,
    );
    expect(client.isAuthenticated, isTrue);
    expect(client.userId, settings['username']);
    expect(
      client.deltaSyncServerAppUrl,
      '${settings['url']}/index.php/apps/crispcloud_delta',
    );
    final listing = await client.listPath('/');
    expect(listing['files'], isA<List>());
    expect(listing['folders'], isA<List>());
    expect((await config.readCredentials())!['username'], settings['username']);
  }, skip: unavailable);

  for (final generic in [false, true]) {
    test(
      'two real accounts retain their panes and swap correctly (WebDAV first: $generic)',
      () async {
        expect(settings['second_created'], isTrue);
        final suffix = DateTime.now().microsecondsSinceEpoch;
        final markers = [
          'crisp96-left-$suffix.txt',
          'crisp96-right-$suffix.txt',
        ];
        for (var account = 0; account < 2; account++) {
          final username =
              settings[account == 0 ? 'username' : 'second_username'] as String;
          final password =
              settings[account == 0 ? 'password' : 'second_password'] as String;
          final uri = Uri.parse(
            '${settings['url']}/remote.php/dav/files/${Uri.encodeComponent(username)}/${markers[account]}',
          );
          final headers = {
            'Authorization':
                'Basic ${base64Encode(utf8.encode('$username:$password'))}',
          };
          final created = await http.put(
            uri,
            headers: headers,
            body: markers[account],
          );
          expect(created.statusCode, 201);
          addTearDown(() async {
            expect((await http.delete(uri, headers: headers)).statusCode, 204);
          });
        }
        final store = InMemorySecureStorage();
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (ref) => AuthNotifier(
                ref,
                initialProvider: generic
                    ? CloudProvider.webdav
                    : CloudProvider.nextcloud,
                config: generic
                    ? WebDavConfigService(configPath: '', secureStorage: store)
                    : NextcloudConfigService(
                        configPath: '',
                        secureStorage: store,
                      ),
                configPath: '',
                secureStorage: store,
              ),
            ),
            localFileServiceProvider.overrideWithValue(_Local()),
          ],
        );
        addTearDown(container.dispose);
        final auth = container.read(authProvider);
        await Future<void>.delayed(Duration.zero);
        await auth.login(
          generic
              ? '${settings['username']}@${settings['url']}/remote.php/dav/files/${Uri.encodeComponent(settings['username'] as String)}/'
              : '${settings['username']}@${settings['url']}',
          settings['password'] as String,
          null,
        );
        final first = auth.client;
        final left = container.read(panelProvider(PanelSide.local));
        container
            .read(panelSourceProvider(PanelSide.local).notifier)
            .setSource(
              RemotePanelSource(
                providerName: first.providerName,
                client: first,
                path: '/',
              ),
            );
        await left.refresh();
        await auth.switchProvider(CloudProvider.nextcloud, newConnection: true);
        await auth.login(
          '${settings['second_username']}@${settings['url']}',
          settings['second_password'] as String,
          null,
        );
        final second = auth.client;
        final right = container.read(panelProvider(PanelSide.remote));
        container
            .read(panelSourceProvider(PanelSide.remote).notifier)
            .setSource(
              RemotePanelSource(
                providerName: second.providerName,
                client: second,
                path: '/',
              ),
            );
        await right.refresh();
        await left.refresh();
        expect(left.directoryListingError, isNull);
        expect(right.directoryListingError, isNull);
        expect(left.hasVerifiedDirectoryListing, isTrue);
        expect(right.hasVerifiedDirectoryListing, isTrue);
        expect(left.files?.any((file) => file.name == markers[0]), isTrue);
        expect(right.files?.any((file) => file.name == markers[1]), isTrue);
        expect(first.isAuthenticated, isTrue);
        expect(second.isAuthenticated, isTrue);
        expect(first.userId, settings['username']);
        expect(second.userId, settings['second_username']);
        final leftOrigin = left.captureCurrentOrigin();
        final rightOrigin = right.captureCurrentOrigin();
        expect((leftOrigin.source as RemotePanelSource).client, same(first));
        expect((rightOrigin.source as RemotePanelSource).client, same(second));
        expect(leftOrigin.isCurrent, isTrue);
        expect(rightOrigin.isCurrent, isTrue);
        expect(
          leftOrigin.storageReference,
          isNot(rightOrigin.storageReference),
        );
        expect(
          container.read(multiCloudProvider).connections.single.client,
          same(first),
        );
        expect(await left.swapViewWith(right), isTrue);
        await left.refresh();
        await right.refresh();
        expect(left.directoryListingError, isNull);
        expect(right.directoryListingError, isNull);
        expect(left.files?.any((file) => file.name == markers[1]), isTrue);
        expect(right.files?.any((file) => file.name == markers[0]), isTrue);
      },
      skip: unavailable,
    );
  }
}
