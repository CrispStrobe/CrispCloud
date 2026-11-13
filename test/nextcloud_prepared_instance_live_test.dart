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
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test(
    'two real Nextcloud accounts remain independently available in their panes',
    () async {
      expect(settings['second_created'], isTrue);
      final store = InMemorySecureStorage();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref,
              initialProvider: CloudProvider.nextcloud,
              config: NextcloudConfigService(
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
        '${settings['username']}@${settings['url']}',
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
      expect(leftOrigin.storageReference, isNot(rightOrigin.storageReference));
      expect(
        container.read(multiCloudProvider).connections.single.client,
        same(first),
      );
    },
    skip: unavailable,
  );
}
