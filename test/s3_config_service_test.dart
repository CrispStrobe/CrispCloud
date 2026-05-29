import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late S3ConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    secureStorage = InMemorySecureStorage();
    configService = S3ConfigService(
      configPath: '/tmp/s3_test_config',
      secureStorage: secureStorage,
    );
  });

  group('S3ConfigService', () {
    test('readCredentials returns null when no credentials saved', () async {
      final creds = await configService.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials stores and readCredentials retrieves them', () async {
      final testCreds = {
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'my-test-bucket',
        'region': 'us-east-1',
      };

      await configService.saveCredentials(testCreds);
      final retrieved = await configService.readCredentials();

      expect(retrieved, isNotNull);
      expect(retrieved!['accessKey'], equals('AKIAIOSFODNN7EXAMPLE'));
      expect(retrieved['secretKey'], equals('wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'));
      expect(retrieved['endpoint'], equals('https://s3.amazonaws.com'));
      expect(retrieved['bucket'], equals('my-test-bucket'));
      expect(retrieved['region'], equals('us-east-1'));
    });

    test('clearCredentials removes saved credentials', () async {
      await configService.saveCredentials({
        'accessKey': 'AKIAIOSFODNN7EXAMPLE',
        'secretKey': 'secret',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'bucket',
        'region': 'us-east-1',
      });

      // Verify saved
      expect(await configService.readCredentials(), isNotNull);

      // Clear
      await configService.clearCredentials();

      // Verify cleared
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials overwrites existing credentials', () async {
      await configService.saveCredentials({
        'accessKey': 'OLD_KEY',
        'secretKey': 'OLD_SECRET',
        'endpoint': 'https://old.example.com',
        'bucket': 'old-bucket',
        'region': 'us-west-1',
      });

      await configService.saveCredentials({
        'accessKey': 'NEW_KEY',
        'secretKey': 'NEW_SECRET',
        'endpoint': 'https://new.example.com',
        'bucket': 'new-bucket',
        'region': 'eu-west-1',
      });

      final creds = await configService.readCredentials();
      expect(creds!['accessKey'], equals('NEW_KEY'));
      expect(creds['bucket'], equals('new-bucket'));
      expect(creds['region'], equals('eu-west-1'));
    });

    test('multiple config service instances share same storage', () async {
      final configService2 = S3ConfigService(
        configPath: '/tmp/s3_test_config_2',
        secureStorage: secureStorage,
      );

      await configService.saveCredentials({
        'accessKey': 'SHARED_KEY',
        'secretKey': 'SHARED_SECRET',
        'endpoint': 'https://s3.amazonaws.com',
        'bucket': 'shared-bucket',
        'region': 'us-east-1',
      });

      // Same secure storage key ('s3_credentials'), so second instance sees it
      final creds = await configService2.readCredentials();
      expect(creds, isNotNull);
      expect(creds!['accessKey'], equals('SHARED_KEY'));
    });
  });
}
