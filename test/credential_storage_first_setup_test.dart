import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/credential_storage_first_setup.dart';
import 'package:crisp_cloud/services/credential_storage_first_setup_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory support;
  late String legacy;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('crisp-first-setup-test-');
    support = Directory(p.join(root.path, 'support'));
    legacy = p.join(root.path, '.cloud-storage-config');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<bool> capture() => CredentialStorageFirstSetup.capture(
    profileIsEmpty: (preferences) => nativeCredentialProfileIsEmpty(
      supportDirectory: support,
      legacyConfigPath: legacy,
      setupPreferences: preferences,
    ),
  );

  test('empty native installation records a resumable first-setup marker', () async {
    expect(await capture(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(CredentialStorageFirstSetup.pendingKey), isTrue);
    expect(await capture(), isTrue);
    await CredentialStorageConfig.writeMode(CredentialStorageMode.encryptedFile);
    expect(await capture(), isTrue);

    await CredentialStorageFirstSetup.complete();

    expect(prefs.containsKey(CredentialStorageFirstSetup.pendingKey), isFalse);
    expect(await CredentialStorageConfig.readMode(), CredentialStorageMode.encryptedFile);
    expect(await capture(), isFalse);
  });

  test('an older profile does not become fresh because the new mode is absent', () async {
    SharedPreferences.setMockInitialValues({'cloud_provider': 'filen'});
    expect(await capture(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CredentialStorageFirstSetup.pendingKey), isFalse);
  });

  test('legacy config, including an empty existing directory, blocks first setup', () async {
    await Directory(legacy).create();
    expect(await capture(), isFalse);
  });

  test('existing support data blocks first setup even with a pending marker', () async {
    SharedPreferences.setMockInitialValues({
      CredentialStorageFirstSetup.pendingKey: true,
    });
    await support.create();
    final vault = File(p.join(support.path, 'credential-vault.json'));
    await vault.writeAsString('existing-protected-data');
    expect(await capture(), isFalse);
    expect(await vault.readAsString(), 'existing-protected-data');
  });

  test('an unrelated preference invalidates an interrupted first setup', () async {
    SharedPreferences.setMockInitialValues({
      CredentialStorageFirstSetup.pendingKey: true,
      'installation_id': 'existing-profile',
    });
    expect(await capture(), isFalse);
  });

  test('an explicit keychain path can resume interrupted fresh setup', () async {
    SharedPreferences.setMockInitialValues({
      CredentialStorageFirstSetup.pendingKey: true,
      'custom_keychain_path': '/synthetic/keychains/selected.keychain-db',
    });
    expect(await capture(), isTrue);
    await CredentialStorageFirstSetup.complete();
    expect(await capture(), isFalse);
  });

  test('atomic selection intent resumes only when its complete schema is valid', () async {
    SharedPreferences.setMockInitialValues({
      CredentialStorageFirstSetup.pendingKey: true,
    });
    await CredentialStorageConfig.writeSelection(
      mode: CredentialStorageMode.encryptedFile,
    );
    expect(await capture(), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('credential_storage_selection_v2', jsonEncode({
      'version': 2,
      'mode': 'encryptedFile',
      'customKeychainPath': null,
      'unrecognized': 'existing-profile-data',
    }));
    expect(await capture(), isFalse);
  });

  test('unknown or malformed pending choices do not authorize a fallback', () async {
    for (final value in ['unknown', 123]) {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
        'credential_storage_mode_v1': value,
      });
      expect(await capture(), isFalse);
    }
  });

  test('filesystem evidence failure is not interpreted as an empty profile', () async {
    expect(
      await CredentialStorageFirstSetup.capture(
        profileIsEmpty: (_) async => throw FileSystemException('Synthetic failure'),
      ),
      isFalse,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CredentialStorageFirstSetup.pendingKey), isFalse);
  });

  test('desktop preference file is allowed only for the exact checked setup', () async {
    SharedPreferences.setMockInitialValues({
      CredentialStorageFirstSetup.pendingKey: true,
    });
    await support.create();
    final file = File(p.join(support.path, 'shared_preferences.json'));
    await file.writeAsString(jsonEncode({
      'flutter.${CredentialStorageFirstSetup.pendingKey}': true,
    }));
    expect(await capture(), isTrue);

    await file.writeAsString(jsonEncode({
      'flutter.${CredentialStorageFirstSetup.pendingKey}': true,
      'unrecognized_profile_data': 'existing',
    }));
    expect(await capture(), isFalse);
  }, skip: !(Platform.isLinux || Platform.isWindows));

}
