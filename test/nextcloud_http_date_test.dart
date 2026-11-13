import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _entry(String name, String? date, {bool folder = false}) =>
    '''
<d:response><d:href>/remote.php/dav/files/alice/$name</d:href>
<d:propstat><d:prop><d:displayname>$name</d:displayname>
<d:resourcetype>${folder ? '<d:collection/>' : ''}</d:resourcetype>
${date == null ? '' : '<d:getlastmodified>$date</d:getlastmodified>'}
<d:getcontentlength>12</d:getcontentlength></d:prop>
<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>''';

void main() {
  for (final date in [
    'Sun, 06 Nov 1994 08:49:37 GMT',
    'Sunday, 06-Nov-94 08:49:37 GMT',
    'Sun Nov  6 08:49:37 1994',
    '1994-11-06T09:49:37+01:00',
  ]) {
    test(
      'DAV date $date remains readable in listings and exact metadata',
      () async {
        await http.runWithClient(
          () async {
            final client = NextcloudClientAdapter(
              config: NextcloudConfigService(
                configPath: '',
                secureStorage: InMemorySecureStorage(),
              ),
            );
            await client.login('alice@https://cloud.example', 'not-for-logs');
            final listing = await client.listPath('/');
            final folder = (listing['folders'] as List).single as Map;
            final file = (listing['files'] as List).single as Map;
            for (final entry in [folder, file]) {
              expect(entry['modificationTime'], '1994-11-06T08:49:37.000Z');
              expect(
                DateTime.parse(entry['modificationTime'] as String).isUtc,
                isTrue,
              );
            }
            final metadata = await client.resolvePath('/file.txt');
            expect(metadata!['updatedAt'], '1994-11-06T08:49:37.000Z');
          },
          () => MockClient((request) async {
            if (request.method != 'PROPFIND') return http.Response('', 404);
            final entries = request.url.path.endsWith('/file.txt')
                ? _entry('file.txt', date)
                : _entry('', date, folder: true) +
                      _entry('folder/', date, folder: true) +
                      _entry('file.txt', date);
            return http.Response(
              '<d:multistatus xmlns:d="DAV:">$entries</d:multistatus>',
              207,
            );
          }),
        );
      },
    );
  }

  for (final date in <String?>[
    null,
    '',
    'invalid date',
    'Wed, 31 Feb 2026 25:00:00 GMT',
  ]) {
    test(
      'missing or malformed DAV timestamp does not hide a readable file: $date',
      () async {
        await http.runWithClient(
          () async {
            final client = NextcloudClientAdapter(
              config: NextcloudConfigService(
                configPath: '',
                secureStorage: InMemorySecureStorage(),
              ),
            );
            await client.login('alice@https://cloud.example', 'not-for-logs');
            final listing = await client.listPath('/');
            final file = (listing['files'] as List).single as Map;
            expect(file['name'], 'file.txt');
            expect(file['modificationTime'], isNull);
          },
          () => MockClient(
            (request) async => request.method == 'PROPFIND'
                ? http.Response(
                    '<d:multistatus xmlns:d="DAV:">${_entry('', null, folder: true)}${_entry('file.txt', date)}</d:multistatus>',
                    207,
                  )
                : http.Response('', 404),
          ),
        );
      },
    );
  }
}
