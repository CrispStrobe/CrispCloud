import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_file_io.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credential storage mode is persisted outside the vault', () async {
    SharedPreferences.setMockInitialValues({});
    expect(
      await CredentialStorageConfig.readMode(),
      CredentialStorageMode.systemKeychain,
    );
    await CredentialStorageConfig.writeMode(
      CredentialStorageMode.encryptedFile,
    );
    expect(
      await CredentialStorageConfig.readMode(),
      CredentialStorageMode.encryptedFile,
    );
    await CredentialStorageConfig.writeCustomKeychainPath(
      '/tmp/brickwright.keychain-db',
    );
    expect(
      await CredentialStorageConfig.readCustomKeychainPath(),
      '/tmp/brickwright.keychain-db',
    );
  });

  test('encrypted file vault persists values across instances', () async {
    final directory = Directory.systemTemp.createTempSync('crisp-vault-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/credential-vault.json');

    final first = WebEncryptedStorage(
      FileStorageBackend(file),
      newVaultIterations: 1000,
    );
    await first.initialize('correct horse battery staple');
    await first.write('internxt', 'secret-value');

    final second = WebEncryptedStorage(
      FileStorageBackend(file),
      newVaultIterations: 1000,
    );
    await second.initialize('correct horse battery staple');
    expect(await second.read('internxt'), 'secret-value');
    expect(await file.exists(), isTrue);
    if (!Platform.isWindows) {
      expect(FileStat.statSync(file.path).mode & 0x1ff, 0x180);
    }
  });
}
