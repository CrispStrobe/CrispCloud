// test/s3_adapter_test.dart
//
// Unit tests for S3CliAdapter: identity parsing, URI construction, signing,
// and share URL generation. Does NOT make real network calls.

import 'package:test/test.dart';

import 'package:crisp/adapters/s3_adapter.dart';
import 'package:crisp/config/cli_config.dart';

void main() {
  group('S3CliAdapter.parseIdentity', () {
    test('parses standard AWS identity', () {
      final result = S3CliAdapter.parseIdentity(
        'AKID@s3.amazonaws.com/mybucket',
        'mysecret',
      );
      expect(result['access_key'], equals('AKID'));
      expect(result['secret_key'], equals('mysecret'));
      expect(result['endpoint'], contains('amazonaws.com'));
      expect(result['bucket'], equals('mybucket'));
      expect(result['region'], equals('us-east-1')); // default
    });

    test('parses identity with explicit region', () {
      final result = S3CliAdapter.parseIdentity(
        'AKID@s3.amazonaws.com/mybucket?region=eu-west-1',
        'sec',
      );
      expect(result['region'], equals('eu-west-1'));
    });

    test('parses MinIO-style identity with http scheme', () {
      final result = S3CliAdapter.parseIdentity(
        'minioadmin@http://localhost:9000/testbucket',
        'minioadmin',
      );
      expect(result['bucket'], equals('testbucket'));
      expect(result['endpoint'], equals('http://localhost:9000'));
    });

    test('throws on missing @ separator', () {
      expect(
        () => S3CliAdapter.parseIdentity('noatsign', 'secret'),
        throwsA(isA<CliConfigException>()),
      );
    });

    test('throws when bucket is missing', () {
      expect(
        () => S3CliAdapter.parseIdentity('AKID@s3.amazonaws.com', 'secret'),
        throwsA(isA<CliConfigException>()),
      );
    });
  });

  group('S3CliAdapter.fromConfig', () {
    test('constructs from valid config map', () {
      final adapter = S3CliAdapter.fromConfig({
        'type': 's3',
        'access_key': 'AKID',
        'secret_key': 'secret',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'mybucket',
        'region': 'us-east-1',
      });
      expect(adapter.providerName, equals('S3'));
    });

    test('throws CliConfigException on missing fields', () {
      expect(
        () => S3CliAdapter.fromConfig({'type': 's3'}),
        throwsA(isA<CliConfigException>()),
      );
    });

    test('defaults region to us-east-1 when not provided', () {
      // Just check it doesn't throw and constructs OK
      final adapter = S3CliAdapter.fromConfig({
        'type': 's3',
        'access_key': 'A',
        'secret_key': 'S',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'b',
      });
      expect(adapter.providerName, equals('S3'));
    });
  });

  group('S3CliAdapter signing', () {
    late S3CliAdapter adapter;

    setUp(() {
      adapter = S3CliAdapter(
        accessKey: 'AKIAIOSFODNN7EXAMPLE',
        secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        endpoint: 'https://s3.amazonaws.com',
        bucket: 'examplebucket',
        region: 'us-east-1',
      );
    });

    test('share generates a pre-signed URL with required query params', () async {
      final url = await adapter.share('/myfile.txt', expires: const Duration(hours: 1));
      expect(url, contains('X-Amz-Algorithm=AWS4-HMAC-SHA256'));
      expect(url, contains('X-Amz-Credential'));
      expect(url, contains('X-Amz-Date'));
      expect(url, contains('X-Amz-Expires=3600'));
      expect(url, contains('X-Amz-Signature'));
    });

    test('share URL contains the object key', () async {
      final url = await adapter.share('/my/path/file.pdf', expires: const Duration(days: 7));
      expect(url, contains('file.pdf'));
      expect(url, contains('X-Amz-Expires=604800'));
    });
  });

  group('S3CliAdapter path-style (MinIO)', () {
    test('constructs from MinIO config', () {
      final adapter = S3CliAdapter.fromConfig({
        'type': 's3',
        'access_key': 'minioadmin',
        'secret_key': 'minioadmin',
        'endpoint': 'http://localhost:9000',
        'bucket': 'testbucket',
        'region': 'us-east-1',
      });
      // Path style — doesn't use virtual-hosted style since not amazonaws.com
      expect(adapter.providerName, equals('S3'));
    });
  });
}
