import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final token in <String?>[null, '', '   ']) {
    test(
      'a truncated S3 page with unusable token ($token) stays visibly incomplete',
      () async {
        final adapter = await _adapter();
        var requests = 0;
        final result = await http.runWithClient(
          () => const StorageScanService().scan(
            CloudStorageScanBackend(adapter, isCurrent: () => true),
            '/',
          ),
          () => MockClient((request) async {
            requests++;
            expect(request.url.queryParameters['list-type'], '2');
            return http.Response(
              _page('known.bin', 7, truncated: true, next: token),
              200,
            );
          }),
        );
        expect(requests, 1);
        expect(result.root.bytes, 7);
        expect(result.root.fileCount, 1);
        expect(result.isComplete, isFalse);
        expect(
          result.issues.single.code,
          StorageScanIssueCode.incompleteListing,
        );
      },
    );
  }

  test('a repeated S3 continuation token terminates and preserves a partial result', () async {
    final adapter = await _adapter();
    var requests = 0;
    final listing = await http.runWithClient(
      () => adapter.listPath('/'),
      () => MockClient((request) async {
        requests++;
        if (requests == 1) {
          expect(request.url.queryParameters['continuation-token'], isNull);
          return http.Response(
            _page('first', 3, truncated: true, next: 'again'),
            200,
          );
        }
        expect(requests, 2);
        expect(request.url.queryParameters['continuation-token'], 'again');
        return http.Response(
          _page('second', 5, truncated: true, next: 'again'),
          200,
        );
      }),
    );
    expect(requests, 2);
    expect(listing['files'], hasLength(2));
    expect(listing['isTruncated'], isTrue);
  });

  test(
    'complete S3 pagination retains its existing listing shape and all bytes',
    () async {
      final adapter = await _adapter();
      var requests = 0;
      final listing = await http.runWithClient(
        () => adapter.listPath('/'),
        () => MockClient((request) async {
          requests++;
          return http.Response(
            requests == 1
                ? _page('first', 3, truncated: true, next: 'page-2')
                : _page('second', 5, truncated: false),
            200,
          );
        }),
      );
      expect(requests, 2);
      expect(listing.keys.toSet(), {'folders', 'files'});
      expect((listing['files'] as List).map((file) => file['size']), [3, 5]);
    },
  );
}

Future<S3ClientAdapter> _adapter() async {
  final config = S3ConfigService(
    configPath: '',
    secureStorage: InMemorySecureStorage(),
  );
  await config.saveCredentials({
    'accessKey': 'fixture-access',
    'secretKey': 'fixture-secret',
    'endpoint': 'https://s3.amazonaws.com',
    'bucket': 'fixture-bucket',
    'region': 'us-east-1',
  });
  final adapter = S3ClientAdapter(config: config);
  expect(await adapter.restoreCredentials(), isTrue);
  return adapter;
}

String _page(String name, int size, {required bool truncated, String? next}) =>
    '''
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Contents><Key>$name</Key><Size>$size</Size></Contents>
  <IsTruncated>$truncated</IsTruncated>
  ${next == null ? '' : '<NextContinuationToken>$next</NextContinuationToken>'}
</ListBucketResult>
''';
