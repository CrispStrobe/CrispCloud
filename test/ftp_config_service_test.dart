import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late FTPConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    secureStorage = InMemorySecureStorage();
    configService = FTPConfigService(
      configPath: '/tmp/ftp_test_config',
      secureStorage: secureStorage,
    );
  });

  group('FTPConfigService', () {
    test('readCredentials returns null when no credentials saved', () async {
      final creds = await configService.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials stores and readCredentials retrieves them', () async {
      final testCreds = {
        'host': 'ftp.example.com',
        'port': '21',
        'username': 'ftpuser',
        'password': 'secret123',
        'useTLS': 'true',
      };

      await configService.saveCredentials(testCreds);
      final retrieved = await configService.readCredentials();

      expect(retrieved, isNotNull);
      expect(retrieved!['host'], equals('ftp.example.com'));
      expect(retrieved['port'], equals('21'));
      expect(retrieved['username'], equals('ftpuser'));
      expect(retrieved['password'], equals('secret123'));
      expect(retrieved['useTLS'], equals('true'));
    });

    test('clearCredentials removes saved credentials', () async {
      await configService.saveCredentials({
        'host': 'ftp.example.com',
        'port': '21',
        'username': 'user',
        'password': 'pass',
        'useTLS': 'false',
      });

      expect(await configService.readCredentials(), isNotNull);

      await configService.clearCredentials();

      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials overwrites existing credentials', () async {
      await configService.saveCredentials({
        'host': 'old.example.com',
        'port': '21',
        'username': 'olduser',
        'password': 'oldpass',
        'useTLS': 'false',
      });

      await configService.saveCredentials({
        'host': 'new.example.com',
        'port': '990',
        'username': 'newuser',
        'password': 'newpass',
        'useTLS': 'true',
      });

      final creds = await configService.readCredentials();
      expect(creds!['host'], equals('new.example.com'));
      expect(creds['port'], equals('990'));
      expect(creds['username'], equals('newuser'));
      expect(creds['useTLS'], equals('true'));
    });

    test('multiple config service instances share same storage', () async {
      final configService2 = FTPConfigService(
        configPath: '/tmp/ftp_test_config_2',
        secureStorage: secureStorage,
      );

      await configService.saveCredentials({
        'host': 'shared.example.com',
        'port': '21',
        'username': 'shareduser',
        'password': 'sharedpass',
        'useTLS': 'false',
      });

      // Same secure storage key ('ftp_credentials'), so second instance sees it
      final creds = await configService2.readCredentials();
      expect(creds, isNotNull);
      expect(creds!['host'], equals('shared.example.com'));
    });
  });
}
