import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/providers/multi_cloud_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final next in [CloudProvider.sftp, CloudProvider.nextcloud]) {
    test(
      'opening $next retains the connected Nextcloud session and credentials',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = InMemorySecureStorage();
        final config = NextcloudConfigService(
          configPath: '',
          secureStorage: store,
        );
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              (ref) => AuthNotifier(
                ref,
                initialProvider: CloudProvider.nextcloud,
                config: config,
                configPath: '',
                secureStorage: store,
              ),
            ),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await Future<void>.delayed(Duration.zero);
          expect(
            await config.readCredentials(),
            isNotNull,
            reason: 'Closing the application must not log out saved accounts',
          );
        });
        await http.runWithClient(
          () async {
            final auth = container.read(authProvider);
            await Future<void>.delayed(Duration.zero);
            await auth.login('alice@https://one.example.com', 'secret', null);
            final first = auth.client;
            auth.enableEncryption('local file encryption key');
            final wrapped = auth.client;
            await auth.switchProvider(next, newConnection: true);
            expect(auth.client, isNot(same(first)));
            expect(auth.client, isNot(same(wrapped)));
            expect(auth.isConnected, isFalse);
            expect(auth.isEncryptionEnabled, isFalse);
            expect(first.isAuthenticated, isTrue);
            expect(wrapped.isAuthenticated, isTrue);
            expect((await config.readCredentials())!['username'], 'alice');
            final retained = container
                .read(multiCloudProvider)
                .connections
                .single;
            expect(retained.client, same(wrapped));
            expect(retained.provider, CloudProvider.nextcloud);
            expect(retained.label, contains('alice'));
            if (next == CloudProvider.nextcloud) {
              await auth.login('bob@https://two.example.com', 'other', null);
              expect(first.userId, 'alice');
              expect(first.bucketId, 'https://one.example.com');
              expect(auth.client.userId, 'bob');
              expect(auth.client.bucketId, 'https://two.example.com');
              expect(wrapped.isAuthenticated, isTrue);
            }
          },
          () => MockClient(
            (request) async =>
                http.Response('', request.method == 'PROPFIND' ? 207 : 404),
          ),
        );
      },
    );
  }
}
