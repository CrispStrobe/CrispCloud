// test/hetzner_adapter_test.dart
//
// Unit tests for HetznerStorageBoxAdapter, HetznerConfigService, and helpers.
// All tests are offline — no network calls are made.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/hetzner_adapter.dart';
import 'package:crisp_cloud/services/hetzner_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// Convenience builders
// ---------------------------------------------------------------------------

HetznerConfigService _makeConfig() =>
    HetznerConfigService(secureStorage: InMemorySecureStorage());

HetznerStorageBoxAdapter _makeAdapter() =>
    HetznerStorageBoxAdapter(config: _makeConfig());

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Provider metadata
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerStorageBoxAdapter — provider metadata', () {
    late HetznerStorageBoxAdapter adapter;
    setUp(() => adapter = _makeAdapter());

    test('providerName is "Hetzner Storage Box"', () {
      expect(adapter.providerName, equals('Hetzner Storage Box'));
    });

    test('rootPath is "/"', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('isAuthenticated is false before login', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId is null before login', () {
      expect(adapter.userId, isNull);
    });

    test('bucketId is null before login', () {
      expect(adapter.bucketId, isNull);
    });

    test('is2faNeeded always returns false', () async {
      expect(await adapter.is2faNeeded('u123456'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Hostname generation
  // ─────────────────────────────────────────────────────────────────────────
  group('hetznerHostname()', () {
    test('generates correct hostname for u123456', () {
      expect(hetznerHostname('u123456'),
          equals('u123456.your-storagebox.de'));
    });

    test('generates correct hostname for u1000000', () {
      expect(hetznerHostname('u1000000'),
          equals('u1000000.your-storagebox.de'));
    });

    test('hostname follows pattern uNNNNNN.your-storagebox.de', () {
      final host = hetznerHostname('u987654');
      expect(host, matches(RegExp(r'^u\d+\.your-storagebox\.de$')));
    });

    test('username is preserved verbatim in hostname', () {
      const user = 'u555555';
      expect(hetznerHostname(user), startsWith('$user.'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Port defaults
  // ─────────────────────────────────────────────────────────────────────────
  group('Port defaults', () {
    test('SFTP port constant is 23', () {
      expect(kHetznerSftpPort, equals(23));
    });

    test('WebDAV port constant is 443', () {
      expect(kHetznerWebDavPort, equals(443));
    });

    test('SFTP port is not the standard 22', () {
      expect(kHetznerSftpPort, isNot(equals(22)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. WebDAV URL construction
  // ─────────────────────────────────────────────────────────────────────────
  group('hetznerWebDavUrl()', () {
    test('URL starts with https://', () {
      expect(hetznerWebDavUrl('u123456'), startsWith('https://'));
    });

    test('URL ends with trailing slash', () {
      expect(hetznerWebDavUrl('u123456'), endsWith('/'));
    });

    test('URL contains hostname', () {
      expect(hetznerWebDavUrl('u123456'),
          contains('u123456.your-storagebox.de'));
    });

    test('full URL is correct for u123456', () {
      expect(hetznerWebDavUrl('u123456'),
          equals('https://u123456.your-storagebox.de/'));
    });

    test('full URL is correct for u999999', () {
      expect(hetznerWebDavUrl('u999999'),
          equals('https://u999999.your-storagebox.de/'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. Sub-account username construction
  // ─────────────────────────────────────────────────────────────────────────
  group('hetznerEffectiveUsername()', () {
    test('no sub-account returns username unchanged', () {
      expect(hetznerEffectiveUsername('u123456', null), equals('u123456'));
    });

    test('empty sub-account returns username unchanged', () {
      expect(hetznerEffectiveUsername('u123456', ''), equals('u123456'));
    });

    test('sub-account is appended with dash separator', () {
      expect(hetznerEffectiveUsername('u123456', 'sub1'),
          equals('u123456-sub1'));
    });

    test('sub-account "backup" appended correctly', () {
      expect(hetznerEffectiveUsername('u654321', 'backup'),
          equals('u654321-backup'));
    });

    test('sub-account pattern matches Hetzner docs format', () {
      final result = hetznerEffectiveUsername('u123456', 'sub3');
      expect(result, matches(RegExp(r'^u\d+-\w+$')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. Protocol switching
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerProtocol enum', () {
    test('sftp is the first / default value', () {
      expect(HetznerProtocol.sftp, isA<HetznerProtocol>());
    });

    test('webdav is a distinct value from sftp', () {
      expect(HetznerProtocol.webdav, isNot(equals(HetznerProtocol.sftp)));
    });

    test('enum has exactly two values', () {
      expect(HetznerProtocol.values, hasLength(2));
    });

    test('sftp.name is "sftp"', () {
      expect(HetznerProtocol.sftp.name, equals('sftp'));
    });

    test('webdav.name is "webdav"', () {
      expect(HetznerProtocol.webdav.name, equals('webdav'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 7. Config serialization / deserialization
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerConfigService', () {
    test('readCredentials returns null when nothing saved', () async {
      final cfg = _makeConfig();
      expect(await cfg.readCredentials(), isNull);
    });

    test('saveCredentials persists username', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'secret',
        protocol: HetznerProtocol.sftp,
      );
      final creds = await cfg.readCredentials();
      expect(creds, isNotNull);
      expect(creds!['username'], equals('u123456'));
    });

    test('saveCredentials persists password', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'mypassword',
        protocol: HetznerProtocol.sftp,
      );
      final creds = await cfg.readCredentials();
      expect(creds!['password'], equals('mypassword'));
    });

    test('saveCredentials persists protocol sftp', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'pw',
        protocol: HetznerProtocol.sftp,
      );
      final creds = await cfg.readCredentials();
      expect(creds!['protocol'], equals('sftp'));
    });

    test('saveCredentials persists protocol webdav', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'pw',
        protocol: HetznerProtocol.webdav,
      );
      final creds = await cfg.readCredentials();
      expect(creds!['protocol'], equals('webdav'));
    });

    test('saveCredentials persists optional sub-account', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'pw',
        protocol: HetznerProtocol.sftp,
        subAccount: 'sub2',
      );
      final creds = await cfg.readCredentials();
      expect(creds!['subAccount'], equals('sub2'));
    });

    test('saveCredentials omits subAccount key when null', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'pw',
        protocol: HetznerProtocol.sftp,
      );
      final creds = await cfg.readCredentials();
      expect(creds!.containsKey('subAccount'), isFalse);
    });

    test('clearCredentials removes saved credentials', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u123456',
        password: 'pw',
        protocol: HetznerProtocol.sftp,
      );
      await cfg.clearCredentials();
      expect(await cfg.readCredentials(), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 8. parseProtocol helper
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerConfigService.parseProtocol()', () {
    test('"sftp" parses to HetznerProtocol.sftp', () {
      expect(HetznerConfigService.parseProtocol('sftp'),
          equals(HetznerProtocol.sftp));
    });

    test('"webdav" parses to HetznerProtocol.webdav', () {
      expect(HetznerConfigService.parseProtocol('webdav'),
          equals(HetznerProtocol.webdav));
    });

    test('null defaults to sftp', () {
      expect(HetznerConfigService.parseProtocol(null),
          equals(HetznerProtocol.sftp));
    });

    test('unknown string defaults to sftp', () {
      expect(HetznerConfigService.parseProtocol('ftp'),
          equals(HetznerProtocol.sftp));
    });

    test('empty string defaults to sftp', () {
      expect(HetznerConfigService.parseProtocol(''),
          equals(HetznerProtocol.sftp));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 9. Capability flags (before login — inner adapter is null)
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerStorageBoxAdapter — capability flags (no inner adapter)', () {
    late HetznerStorageBoxAdapter adapter;
    setUp(() => adapter = _makeAdapter());

    test('supportsStreaming defaults to false', () {
      expect(adapter.supportsStreaming, isFalse);
    });

    test('supportsMultipart defaults to false', () {
      expect(adapter.supportsMultipart, isFalse);
    });

    test('supportsVersioning defaults to false', () {
      expect(adapter.supportsVersioning, isFalse);
    });

    test('supportsSharing defaults to false', () {
      expect(adapter.supportsSharing, isFalse);
    });

    test('supportsSearch defaults to false', () {
      expect(adapter.supportsSearch, isFalse);
    });

    test('supportsThumbnails defaults to false', () {
      expect(adapter.supportsThumbnails, isFalse);
    });

    test('supportsTrash defaults to true', () {
      expect(adapter.supportsTrash, isTrue);
    });

    test('supportsNativeShare defaults to false', () {
      expect(adapter.supportsNativeShare, isFalse);
    });

    test('supportsServerSideCopy defaults to false', () {
      expect(adapter.supportsServerSideCopy, isFalse);
    });

    test('supportsFullTextSearch defaults to false', () {
      expect(adapter.supportsFullTextSearch, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 10. Unauthenticated operation raises descriptive error
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerStorageBoxAdapter — unauthenticated operations', () {
    late HetznerStorageBoxAdapter adapter;
    setUp(() => adapter = _makeAdapter());

    test('listPath throws when not connected', () async {
      expect(() => adapter.listPath('/'), throwsException);
    });

    test('resolvePath throws when not connected', () async {
      expect(() => adapter.resolvePath('/'), throwsException);
    });

    test('createFolderPath throws when not connected', () async {
      expect(() => adapter.createFolderPath('/test'), throwsException);
    });

    test('deletePath throws when not connected', () async {
      expect(() => adapter.deletePath('/test.txt'), throwsException);
    });

    test('uploadFile throws when not connected', () async {
      expect(
        () => adapter.uploadFile([], 'file.txt', '/'),
        throwsException,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 11. withMemoryStorage factory
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerStorageBoxAdapter.withMemoryStorage()', () {
    test('creates adapter with correct providerName', () {
      final adapter = HetznerStorageBoxAdapter.withMemoryStorage();
      expect(adapter.providerName, equals('Hetzner Storage Box'));
    });

    test('isAuthenticated is false on fresh instance', () {
      final adapter = HetznerStorageBoxAdapter.withMemoryStorage();
      expect(adapter.isAuthenticated, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 12. Logout clears state
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerStorageBoxAdapter — logout', () {
    test('logout on fresh adapter does not throw', () async {
      final adapter = _makeAdapter();
      await expectLater(adapter.logout(), completes);
    });

    test('isAuthenticated is false after logout', () async {
      final adapter = _makeAdapter();
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId is null after logout', () async {
      final adapter = _makeAdapter();
      await adapter.logout();
      expect(adapter.userId, isNull);
    });

    test('bucketId is null after logout', () async {
      final adapter = _makeAdapter();
      await adapter.logout();
      expect(adapter.bucketId, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 13. Round-trip config: save then read back
  // ─────────────────────────────────────────────────────────────────────────
  group('HetznerConfigService — round-trip', () {
    test('protocol sftp survives save/read cycle', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u111111',
        password: 'pass',
        protocol: HetznerProtocol.sftp,
      );
      final creds = await cfg.readCredentials();
      expect(
        HetznerConfigService.parseProtocol(creds!['protocol']),
        equals(HetznerProtocol.sftp),
      );
    });

    test('protocol webdav survives save/read cycle', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u111111',
        password: 'pass',
        protocol: HetznerProtocol.webdav,
      );
      final creds = await cfg.readCredentials();
      expect(
        HetznerConfigService.parseProtocol(creds!['protocol']),
        equals(HetznerProtocol.webdav),
      );
    });

    test('overwriting saves the new protocol', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u111111',
        password: 'pass',
        protocol: HetznerProtocol.sftp,
      );
      await cfg.saveCredentials(
        username: 'u111111',
        password: 'pass',
        protocol: HetznerProtocol.webdav,
      );
      final creds = await cfg.readCredentials();
      expect(creds!['protocol'], equals('webdav'));
    });

    test('subAccount survives save/read cycle', () async {
      final cfg = _makeConfig();
      await cfg.saveCredentials(
        username: 'u222222',
        password: 'pw',
        protocol: HetznerProtocol.sftp,
        subAccount: 'backup',
      );
      final creds = await cfg.readCredentials();
      expect(creds!['subAccount'], equals('backup'));
    });
  });
}
