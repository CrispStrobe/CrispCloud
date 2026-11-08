import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/providers/auth_provider.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/encrypted_storage_wrapper.dart';
import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late AuthNotifier auth;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureStorage();
    container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthNotifier(
        ref,
        initialProvider: CloudProvider.filen,
        config: FilenConfigService(
          configPath: '/tmp/crypto-key-lifecycle', secureStorage: secure),
        configPath: '/tmp/crypto-key-lifecycle',
        secureStorage: secure,
      )),
    ]);
    auth = container.read(authProvider);
  });

  tearDown(() => container.dispose());

  test('import and export snapshots cannot mutate the active recovery key', () {
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final salt = Uint8List.fromList(List.generate(16, (i) => i + 1));
    final expectedKey = Uint8List.fromList(key);
    final expectedSalt = Uint8List.fromList(salt);
    auth.enableEncryptionWithKey(key, salt);
    key.fillRange(0, key.length, 0xff);
    salt.fillRange(0, salt.length, 0xff);
    auth.encryptionKey!.fillRange(0, 32, 0);
    auth.encryptionSalt!.fillRange(0, 16, 0);
    expect(auth.encryptionKey, expectedKey);
    expect(auth.encryptionSalt, expectedSalt);

    final plain = Uint8List.fromList(utf8.encode('survives recovery'));
    final encrypted = EncryptionService.encrypt(plain, expectedKey);
    final phrase = EncryptionService.generateMnemonic(
      auth.encryptionKey!, auth.encryptionSalt!)['mnemonic']!;
    auth.disableEncryption();
    final recovered = EncryptionService.recoverKeyFromMnemonic(phrase);
    expect(EncryptionService.decrypt(encrypted, recovered), plain);
  });

  test('import cannot silently claim a different active key was installed', () {
    final key = Uint8List(32);
    final salt = Uint8List(16);
    auth.enableEncryptionWithKey(key, salt);
    final originalClient = auth.client;
    expect(() => auth.enableEncryptionWithKey(
      Uint8List.fromList(List.filled(32, 1)), salt),
      throwsA(isA<EncryptionFormatException>().having(
        (error) => error.code, 'code',
        EncryptionFormatError.encryptionAlreadyEnabled)));
    expect(auth.client, same(originalClient));
    expect(auth.encryptionKey, key);
    // Re-importing the actual active key is an idempotent operation.
    auth.enableEncryptionWithKey(Uint8List.fromList(key), salt);
    expect(auth.client, same(originalClient));
  });

  test('invalid file keys fail before activation or AES backend use', () {
    final inner = auth.client;
    final encrypted = EncryptionService.encrypt(Uint8List(0), Uint8List(32));
    for (final length in [0, 1, 16, 24, 31, 33, 48, 64]) {
      final key = Uint8List(length);
      expect(() => auth.enableEncryptionWithKey(key, Uint8List(16)),
        throwsArgumentError);
      expect(() => EncryptedStorageWrapper(inner: inner, encryptionKey: key),
        throwsArgumentError);
      expect(() => EncryptionService.encrypt(Uint8List(0), key),
        throwsArgumentError);
      expect(() => EncryptionService.decrypt(encrypted, key),
        throwsArgumentError);
    }
    expect(auth.isEncryptionEnabled, isFalse);
    expect(auth.encryptionKey, isNull);
    expect(auth.client, same(inner));
    expect(() => auth.enableEncryption(''), throwsArgumentError);
  });

  test('successful logout discards the session wrapper and recovery state', () async {
    final inner = auth.client;
    auth.enableEncryptionWithKey(Uint8List(32), Uint8List(16));
    await auth.logout();
    expect(auth.client, same(inner));
    expect(auth.isEncryptionEnabled, isFalse);
    expect(auth.encryptionKey, isNull);
    expect(auth.encryptionSalt, isNull);
  });

  test('switching a disconnected provider retires recovered session keys', () async {
    auth.enableEncryptionWithKey(Uint8List(32), Uint8List(16));
    expect(auth.isConnected, isFalse);
    await auth.switchProvider(CloudProvider.s3);
    expect(auth.currentProvider, CloudProvider.s3);
    expect(auth.isEncryptionEnabled, isFalse);
    expect(auth.encryptionKey, isNull);
    expect(auth.encryptionSalt, isNull);
  });
}
