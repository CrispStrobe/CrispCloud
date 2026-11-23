import 'dart:convert';

import 'package:crisp_cloud/services/connection_profiles.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/settings_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStorage extends InMemorySecureStorage {
  String? failKey;
  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    if (key == failKey) {
      failKey = null;
      throw StateError('injected failure after write');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late InMemorySecureStorage source;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'app_theme': 'dark',
      'font_size': 15.0,
      'cloud_provider': 's3',
      'provider_S3_timeout': 50,
      'provider_S3_headers': 'Authorization: bearer-secret',
      'analytics_install_id': 'installation-id',
      'ftp_credentials': '{"password":"legacy-secret"}',
    });
    prefs = await SharedPreferences.getInstance();
    source = InMemorySecureStorage();
    await source.writeMap('s3_credentials', {'secretKey': 's3-secret'});
    await source.write('app_lock_pin', 'local-lock');
    await ConnectionProfileService(source).save(
      const ConnectionProfile(
        name: 'Bucket',
        provider: 's3',
        fields: {
          'bucket': 'reports',
          'endpoint': 'https://user:private@host.test/?secret=query',
          'accessKey': 'profile-secret',
        },
      ),
    );
  });

  test(
    'basic and cloud-only backups omit credentials and installation data',
    () async {
      final basic = await SettingsBackup.capture(
        prefs,
        includeCloud: false,
        includeCredentials: false,
      );
      expect(basic.hasCloud, isFalse);
      final cloud = await SettingsBackup.capture(
        prefs,
        storage: source,
        includeCloud: true,
        includeCredentials: false,
      );
      final file = await cloud.encode();
      final json = utf8.decode(file);
      expect(json, contains('reports'));
      for (final secret in [
        'secret',
        'private',
        'local-lock',
        'installation-id',
      ]) {
        expect(json, isNot(contains(secret)));
      }
      final restored = await SettingsBackup.decode(file);
      expect(restored.hasCredentials, isFalse);
      expect(restored.preferences['font_size'], 15.0);
      expect(restored.cloud['provider_S3_timeout'], 50);
      final destination = InMemorySecureStorage();
      await ConnectionProfileService(destination).save(
        const ConnectionProfile(
          name: 'Bucket',
          provider: 's3',
          fields: {'accessKey': 'existing-key'},
        ),
      );
      await restored.restore(
        prefs,
        storage: destination,
        includeCloud: true,
        includeCredentials: false,
      );
      final profiles = await ConnectionProfileService(destination).getAll();
      expect(profiles.single.fields, {
        'bucket': 'reports',
        'accessKey': 'existing-key',
      });
    },
  );

  test(
    'password backup authenticates and restores only selected sections',
    () async {
      final backup = await SettingsBackup.capture(
        prefs,
        storage: source,
        includeCloud: true,
        includeCredentials: true,
      );
      final bytes = await backup.encode(password: 'test password');
      expect(SettingsBackup.isEncrypted(bytes), isTrue);
      expect(utf8.decode(bytes), isNot(contains('s3-secret')));
      await expectLater(
        SettingsBackup.decode(bytes, password: 'wrong password'),
        throwsA(isA<Exception>()),
      );
      final restored = await SettingsBackup.decode(
        bytes,
        password: 'test password',
      );
      expect(restored.hasCredentials, isTrue);
      expect(
        restored.credentials['provider_S3_headers'],
        'Authorization: bearer-secret',
      );
      await prefs.setString('app_theme', 'light');
      await prefs.setInt('provider_S3_timeout', 5);
      final destination = InMemorySecureStorage();
      await restored.restore(
        prefs,
        storage: destination,
        includeCloud: false,
        includeCredentials: true,
      );
      expect(prefs.getString('app_theme'), 'dark');
      expect(prefs.getInt('provider_S3_timeout'), 5);
      expect(await destination.readMap('s3_credentials'), {
        'secretKey': 's3-secret',
      });
      expect(await destination.read('app_lock_pin'), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a partial credential write is rolled back before settings change',
    () async {
      final backup = await SettingsBackup.capture(
        prefs,
        storage: source,
        includeCloud: false,
        includeCredentials: true,
      );
      final target = _FailingStorage();
      await target.writeMap('s3_credentials', {'secretKey': 'original'});
      target.failKey = 'connection_profiles';
      await prefs.setString('app_theme', 'system');
      await expectLater(
        backup.restore(
          prefs,
          storage: target,
          includeCloud: false,
          includeCredentials: true,
        ),
        throwsA(
          isA<SettingsRestoreException>().having(
            (e) => e.rollbackFailed,
            'rollback failed',
            false,
          ),
        ),
      );
      expect(await target.readMap('s3_credentials'), {'secretKey': 'original'});
      expect(await target.read('connection_profiles'), isNull);
      expect(prefs.getString('app_theme'), 'system');
    },
  );
}
