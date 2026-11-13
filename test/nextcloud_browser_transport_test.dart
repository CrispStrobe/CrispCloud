import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/nextcloud_operation_failure.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('failed PROPFIND preserves browser diagnosis and never saves a session', () async {
    final config = NextcloudConfigService(
      configPath: '',
      secureStorage: InMemorySecureStorage(),
    );
    final adapter = NextcloudClientAdapter(config: config);
    await http.runWithClient(
      () async {
        await expectLater(
          adapter.login(
            'alice@https://cloud.example/nextcloud/',
            'not-for-logs',
          ),
          throwsA(
            isA<NextcloudOperationFailure>()
                .having(
                  (error) => error.code,
                  'failure category',
                  kIsWeb
                      ? NextcloudOperationCode.browserConnectionFailed
                      : NextcloudOperationCode.propfind,
                )
                .having(
                  (error) => error.arguments['uri'].toString(),
                  'exact installation endpoint',
                  'https://cloud.example/nextcloud/remote.php/dav/files/alice/',
                )
                .having(
                  (error) => error.toString(),
                  'original transport error',
                  contains('Load failed'),
                )
                .having(
                  (error) => error.toString(),
                  'no password disclosure',
                  isNot(contains('not-for-logs')),
                ),
          ),
        );
      },
      () => MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['Depth'], '0');
        throw http.ClientException('Load failed', request.url);
      }),
    );
    expect(adapter.isAuthenticated, isFalse);
    expect(await config.readCredentials(), isNull);
  });
}
