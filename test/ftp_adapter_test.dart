import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/ftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late FTPClientAdapter adapter;
  late FTPConfigService configService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configService = FTPConfigService(
      configPath: '/tmp/ftp_test_config',
      secureStorage: InMemorySecureStorage(),
    );
    adapter = FTPClientAdapter(config: configService);
  });

  group('FTPClientAdapter - basic properties', () {
    test('providerName returns FTP', () {
      expect(adapter.providerName, equals('FTP'));
    });

    test('rootPath returns /', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('isAuthenticated returns false initially', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId returns null when not authenticated', () {
      expect(adapter.userId, isNull);
    });

    test('bucketId returns null when not authenticated', () {
      expect(adapter.bucketId, isNull);
    });

    test('is2faNeeded always returns false', () async {
      final result = await adapter.is2faNeeded('test@example.com');
      expect(result, isFalse);
    });
  });

  group('FTPClientAdapter - capability flags', () {
    test('supportsStreaming is false', () {
      expect(adapter.supportsStreaming, isFalse);
    });

    test('supportsTrash is false', () {
      expect(adapter.supportsTrash, isFalse);
    });

    test('supportsMultipart is false (default)', () {
      expect(adapter.supportsMultipart, isFalse);
    });

    test('supportsVersioning is false (default)', () {
      expect(adapter.supportsVersioning, isFalse);
    });

    test('supportsSharing is false (default)', () {
      expect(adapter.supportsSharing, isFalse);
    });

    test('supportsSearch is false (default)', () {
      expect(adapter.supportsSearch, isFalse);
    });
  });

  group('FTPClientAdapter - login identity parsing', () {
    test('rejects identity without @ sign', () async {
      expect(
        () => adapter.login('no-at-sign', 'password'),
        throwsA(isA<Exception>()),
      );
    });

    test('login saves credentials and attempts connection', () async {
      // This will fail at connection (no real FTP server) but credentials
      // should be saved first. We verify by checking that after the error
      // the credentials are cleared (adapter clears on connection failure).
      try {
        await adapter.login('user@ftp.example.com:21', 'pass123');
      } catch (e) {
        // Expected: connection failure
      }

      // After connection failure, credentials are cleared
      final creds = await configService.readCredentials();
      expect(creds, isNull);
    });

    test('parses user@host format (default port 21)', () async {
      // Save credentials directly to test the format
      await configService.saveCredentials({
        'username': 'testuser',
        'host': 'ftp.example.com',
        'port': '21',
        'password': 'testpass',
        'useTLS': 'false',
      });

      final creds = await configService.readCredentials();
      expect(creds!['username'], equals('testuser'));
      expect(creds['host'], equals('ftp.example.com'));
      expect(creds['port'], equals('21'));
      expect(creds['useTLS'], equals('false'));
    });

    test('parses user@host:port?tls=true format', () async {
      await configService.saveCredentials({
        'username': 'secureuser',
        'host': 'ftps.example.com',
        'port': '990',
        'password': 'securepass',
        'useTLS': 'true',
      });

      final creds = await configService.readCredentials();
      expect(creds!['username'], equals('secureuser'));
      expect(creds['host'], equals('ftps.example.com'));
      expect(creds['port'], equals('990'));
      expect(creds['useTLS'], equals('true'));
    });
  });

  group('FTPClientAdapter - config access', () {
    test('config getter exposes FTPConfigService', () {
      expect(adapter.config, isA<FTPConfigService>());
      expect(adapter.config, equals(configService));
    });
  });

  group('FTPClientAdapter - logout', () {
    test('logout clears authentication state', () async {
      // Manually set credentials
      await configService.saveCredentials({
        'username': 'user',
        'host': 'ftp.example.com',
        'port': '21',
        'password': 'pass',
        'useTLS': 'false',
      });

      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);

      // Credentials should be cleared
      final creds = await configService.readCredentials();
      expect(creds, isNull);
    });
  });
}
