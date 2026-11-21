import 'dart:convert';

import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/nextcloud_endpoint.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _server = 'https://cloud.example/nextcloud';
const _password = 'fixture-not-for-logs';

String _principal(String href, {int status = 200}) =>
    '''
<d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop>
<d:current-user-principal><d:href>$href</d:href></d:current-user-principal>
</d:prop><d:status>HTTP/1.1 $status Status</d:status></d:propstat></d:response></d:multistatus>''';

NextcloudConfigService _config() => NextcloudConfigService(
  configPath: '',
  secureStorage: InMemorySecureStorage(),
);

void main() {
  group('installation URLs pasted from the browser', () {
    for (final (input, expected) in const [
      ('https://cloud.example/index.php/apps/files/?dir=/&fileid=5',
          'https://cloud.example'),
      ('https://cloud.example/nextcloud/index.php/apps/files',
          'https://cloud.example/nextcloud'),
      ('https://cloud.example/apps/files/files/12?dir=/Docs',
          'https://cloud.example'),
      ('https://cloud.example/login?redirect_url=/', 'https://cloud.example'),
      ('https://cloud.example/nextcloud/', 'https://cloud.example/nextcloud'),
      ('https://cloud.example:8443/', 'https://cloud.example:8443'),
      ('https://cloud.example/remote.php/dav/files/a%40b.example/',
          'https://cloud.example/remote.php/dav/files/a%40b.example'),
    ]) {
      test(input, () {
        expect(NextcloudEndpoint.installationUrl(input), expected);
      });
    }

    test('server root cuts a DAV suffix', () {
      expect(
        NextcloudEndpoint.serverRoot(
          'https://cloud.example/sub/remote.php/dav/files/me/',
        ).toString(),
        'https://cloud.example/sub',
      );
    });
  });

  for (final (input, expected) in [
    ('$_server/', '$_server/remote.php/dav/files/person%40example.test/'),
    (
      '$_server/remote.php/dav/',
      '$_server/remote.php/dav/files/person%40example.test/',
    ),
    (
      '$_server/remote.php/dav/files/actual-id/',
      '$_server/remote.php/dav/files/actual-id/',
    ),
    ('$_server/remote.php/webdav/', '$_server/remote.php/webdav/'),
  ]) {
    test(
      'pasted endpoint authenticates and restores the same home: $input',
      () async {
        final config = _config();
        await http.runWithClient(
          () async {
            final client = NextcloudClientAdapter(config: config);
            await client.login('person@example.test@$input', _password);
            expect(client.isAuthenticated, isTrue);
            expect(client.bucketId, _server);
            expect((await config.readCredentials())!['davRootUrl'], expected);
            final restored = NextcloudClientAdapter(config: config);
            expect(await restored.restoreCredentials(), isTrue);
            await restored.listPath('/');
          },
          () => MockClient((request) async {
            if (request.method != 'PROPFIND') return http.Response('', 404);
            expect(request.url.toString(), expected);
            expect(request.followRedirects, isFalse);
            expect(
              utf8.decode(
                base64Decode(request.headers['authorization']!.substring(6)),
              ),
              'person@example.test:$_password',
            );
            return http.Response('<d:multistatus xmlns:d="DAV:"/>', 207);
          }),
        );
      },
    );
  }

  for (final status in [401, 403, 404]) {
    test('discovers canonical DAV user for an email/LDAP alias after $status', () async {
      final config = _config();
      final requested = <String>[];
      await http.runWithClient(
        () async {
          final client = NextcloudClientAdapter(config: config);
          await client.login('person@example.test@$_server', _password);
          await client.downloadFileBytes('/café %20.txt');
          final restored = NextcloudClientAdapter(config: config);
          expect(await restored.restoreCredentials(), isTrue);
          expect(
            (await config.readCredentials())!['username'],
            'person@example.test',
          );
          expect(
            (await config.readCredentials())!['davRootUrl'],
            '$_server/remote.php/dav/files/canonical-id/',
          );
        },
        () => MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.endsWith('/api/status')) {
            return http.Response('', 404);
          }
          if (request.url.toString().contains(
            '/files/person%40example.test/',
          )) {
            return http.Response('', status);
          }
          if (request.url.toString() == '$_server/remote.php/dav/') {
            expect(request.body, contains('current-user-principal'));
            return http.Response(
              _principal(
                '/nextcloud/remote.php/dav/principals/users/canonical-id/',
              ),
              207,
            );
          }
          if (request.method == 'GET') {
            expect(
              request.url.toString(),
              '$_server/remote.php/dav/files/canonical-id/caf%C3%A9%20%2520.txt',
            );
            return http.Response('verified', 200);
          }
          expect(
            request.url.toString(),
            '$_server/remote.php/dav/files/canonical-id/',
          );
          return http.Response('<d:multistatus xmlns:d="DAV:"/>', 207);
        }),
      );
      expect(requested, contains('$_server/remote.php/dav/'));
    });
  }

  for (final href in [
    'https://other.example/nextcloud/remote.php/dav/principals/users/user/',
    '/another-installation/remote.php/dav/principals/users/user/',
    '/nextcloud/remote.php/dav/principals/users/../user/',
    '/nextcloud/remote.php/dav/principals/users/user/?redirect=1',
  ]) {
    test('rejects a principal outside the exact installation: $href', () {
      expect(
        NextcloudEndpoint.parse(_server, 'alias').forPrincipal(href),
        isNull,
      );
    });
  }

  test('failed principal properties never select another home', () async {
    final config = _config();
    await http.runWithClient(
      () async {
        final client = NextcloudClientAdapter(config: config);
        await expectLater(
          client.login('alias@$_server', _password),
          throwsException,
        );
        expect(client.isAuthenticated, isFalse);
        expect(await config.readCredentials(), isNull);
      },
      () => MockClient((request) async {
        if (request.url.toString() == '$_server/remote.php/dav/') {
          return http.Response(
            _principal(
              '/nextcloud/remote.php/dav/principals/users/user/',
              status: 404,
            ),
            207,
          );
        }
        expect(request.url.toString(), '$_server/remote.php/dav/files/alias/');
        return http.Response('', 404);
      }),
    );
  });

  test('saved foreign DAV homes do not receive credentials', () async {
    final config = _config();
    await config.saveCredentials({
      'username': 'alias',
      'password': _password,
      'serverUrl': _server,
      'davRootUrl': 'https://other.example/remote.php/dav/files/alias/',
    });
    await http.runWithClient(
      () async {
        expect(
          await NextcloudClientAdapter(config: config).restoreCredentials(),
          isFalse,
        );
      },
      () => MockClient(
        (_) async => fail('Credentials reached an unapproved endpoint'),
      ),
    );
  });

  test(
    'directory response order and encoded paths do not hide files',
    () async {
      final config = _config();
      await http.runWithClient(
        () async {
          final client = NextcloudClientAdapter(config: config);
          await client.login('user@$_server', _password);
          final files = (await client.listPath('/Folder'))['files'] as List;
          expect(files, hasLength(1));
          expect(files.single['name'], 'a%20b.txt');
          expect(files.single['path'], '/Folder/a%20b.txt');
        },
        () => MockClient((request) async {
          if (request.method != 'PROPFIND') return http.Response('', 404);
          if (request.headers['depth'] == '0') {
            return http.Response('<d:multistatus xmlns:d="DAV:"/>', 207);
          }
          return http.Response('''<d:multistatus xmlns:d="DAV:">
<d:response><d:href>$_server/remote.php/dav/files/user/Folder/a%2520b.txt</d:href>
<d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
<d:response><d:href>/nextcloud/remote.php/dav/files/user/Folder/</d:href>
<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
</d:multistatus>''', 207);
        }),
      );
    },
  );
}
