import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/backup_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingSecretStore extends InMemorySecureStorage {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('Keychain unavailable');
  }
}

class _UnavailableSecretStore extends InMemorySecureStorage {
  @override
  Future<String?> read(String key) async => throw StateError('Keychain locked');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Keychain locked');

  @override
  Future<void> delete(String key) async => throw StateError('Keychain locked');
}

BackupPlan _legacyPlan(String source) => BackupPlan(
  id: 'legacy-plan',
  name: 'Legacy encrypted backup',
  sourcePath: source,
  destinationPath: '/backup',
  provider: 'filen',
  schedule: '0 2 * * *',
  encryptionEnabled: true,
  encryptionKey: 'legacy-test-passphrase',
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late InMemorySecureStorage secure;
  late BackupService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('backup-encryption-');
    secure = InMemorySecureStorage();
    service = BackupService(secureStorage: secure);
  });

  tearDown(() async => temp.delete(recursive: true));

  Future<BackupPlan> createEncryptedPlan() async => service.createPlan(
    name: 'Encrypted',
    sourcePath: temp.path,
    destinationPath: '/backup',
    provider: 'filen',
    encryptionEnabled: true,
    encryptionKey: 'new-test-passphrase',
  );

  test(
    'missing encrypt callback never uploads plaintext or records success',
    () async {
      await File('${temp.path}/secret.txt').writeAsString('private data');
      final plan = await createEncryptedPlan();
      var uploads = 0;
      await expectLater(
        service.runBackup(
          plan.id,
          uploadFile: (path, bytes) async {
            uploads++;
            return '/backup/$path';
          },
        ),
        throwsStateError,
      );
      expect(uploads, 0);
      expect(await service.getSnapshots(plan.id), isEmpty);
      expect(service.isRunning, isFalse);
    },
  );

  test('missing key never invokes the encrypt or upload callbacks', () async {
    final plan = await createEncryptedPlan();
    await secure.delete('backup_plan_key_${plan.id}');
    var touched = false;
    await expectLater(
      service.runBackup(
        plan.id,
        uploadFile: (path, bytes) async {
          touched = true;
          return path;
        },
        encryptBytes: (bytes, key) {
          touched = true;
          return bytes;
        },
      ),
      throwsStateError,
    );
    expect(touched, isFalse);
  });

  test('missing decrypt callback preserves destination and does not download', () async {
    await File('${temp.path}/secret.txt').writeAsString('private data');
    final plan = await createEncryptedPlan();
    final snapshot = await service.runBackup(
      plan.id,
      uploadFile: (path, bytes) async => '/backup/$path',
      // The callback contract is external; this reversible transform is a test
      // fixture only. It verifies preflight behavior before any file I/O.
      encryptBytes: (bytes, key) => bytes.map((b) => b ^ 0xff).toList(),
    );
    final target = Directory('${temp.path}/restore');
    await target.create();
    final destination = File('${target.path}/secret.txt');
    await destination.writeAsString('keep existing contents');
    var downloads = 0;
    await expectLater(
      service.restoreSnapshot(
        snapshot.id,
        target.path,
        downloadFile: (_) async {
          downloads++;
          return [1, 2, 3];
        },
      ),
      throwsStateError,
    );
    expect(downloads, 0);
    expect(await destination.readAsString(), 'keep existing contents');
  });

  test('new keys survive restart without appearing in plan JSON', () async {
    final plan = await createEncryptedPlan();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('backup_plans')!;
    expect(stored, isNot(contains('new-test-passphrase')));
    expect(stored, isNot(contains('encryptionKey')));
    expect(
      await secure.read('backup_plan_key_${plan.id}'),
      'new-test-passphrase',
    );
    final restarted = BackupService(secureStorage: secure);
    expect(
      (await restarted.getPlan(plan.id))!.encryptionKey,
      'new-test-passphrase',
    );
    await restarted.deletePlan(plan.id);
    expect(await secure.read('backup_plan_key_${plan.id}'), isNull);
  });

  test('ordinary unencrypted plans do not require keychain access', () async {
    final ordinary = BackupService(secureStorage: _UnavailableSecretStore());
    final plan = await ordinary.createPlan(
      name: 'Plain',
      sourcePath: temp.path,
      destinationPath: '/backup',
      provider: 'filen',
    );
    expect((await ordinary.getPlan(plan.id))!.encryptionEnabled, isFalse);
    await ordinary.deletePlan(plan.id);
    expect(await ordinary.getPlans(), isEmpty);
  });

  test(
    'metadata updates preserve a key retained by a disabled encrypted plan',
    () async {
      final plan = await createEncryptedPlan();
      await service.updatePlan(plan.copyWith(encryptionEnabled: false));
      final restarted = BackupService(secureStorage: secure);
      final loaded = (await restarted.getPlan(plan.id))!;
      expect(loaded.encryptionEnabled, isFalse);
      expect(loaded.encryptionKey, 'new-test-passphrase');
      await restarted.updatePlan(loaded.copyWith(name: 'Renamed'));
      expect(
        (await service.getPlan(plan.id))!.encryptionKey,
        'new-test-passphrase',
      );
    },
  );

  test(
    'legacy plaintext keys migrate only after a verified secure write',
    () async {
      final plan = _legacyPlan(temp.path);
      final legacy = jsonEncode([
        {...plan.toJson(), 'encryptionKey': plan.encryptionKey},
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backup_plans', legacy);
      expect(
        (await service.getPlan(plan.id))!.encryptionKey,
        plan.encryptionKey,
      );
      expect(
        await secure.read('backup_plan_key_${plan.id}'),
        plan.encryptionKey,
      );
      expect(
        prefs.getString('backup_plans'),
        isNot(contains('legacy-test-passphrase')),
      );
      final restarted = BackupService(secureStorage: secure);
      expect(
        (await restarted.getPlan(plan.id))!.encryptionKey,
        plan.encryptionKey,
      );
    },
  );

  test('failed migration preserves legacy recovery data and does not replace plans', () async {
    final plan = _legacyPlan(temp.path);
    final legacy = jsonEncode([
      {...plan.toJson(), 'encryptionKey': plan.encryptionKey},
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backup_plans', legacy);
    final blocked = BackupService(secureStorage: _FailingSecretStore());
    await expectLater(blocked.getPlans(), throwsStateError);
    await expectLater(
      blocked.createPlan(
        name: 'Another',
        sourcePath: '/src',
        destinationPath: '/dst',
        provider: 'filen',
      ),
      throwsStateError,
    );
    expect(prefs.getString('backup_plans'), legacy);
    expect((await service.getPlan(plan.id))!.encryptionKey, plan.encryptionKey);
  });

  test(
    'conflicting legacy and secure keys are retained for recovery',
    () async {
      final plan = _legacyPlan(temp.path);
      final legacy = jsonEncode([
        {...plan.toJson(), 'encryptionKey': plan.encryptionKey},
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backup_plans', legacy);
      await secure.write('backup_plan_key_${plan.id}', 'different-saved-key');
      await expectLater(service.getPlans(), throwsStateError);
      expect(prefs.getString('backup_plans'), legacy);
      expect(
        await secure.read('backup_plan_key_${plan.id}'),
        'different-saved-key',
      );
    },
  );
}
