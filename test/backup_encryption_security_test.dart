import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/backup_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A test double for the persistent-storage contract. Keeping this instance
// across service reconstruction models stored state without using a real keychain.
class _PersistentSecretStore extends InMemorySecureStorage {
  @override
  bool get isPersistent => true;
}

class _FailingSecretStore extends _PersistentSecretStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('Keychain unavailable');
  }
}

class _UnavailableSecretStore extends _PersistentSecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('Keychain locked');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('Keychain locked');

  @override
  Future<void> delete(String key) async => throw StateError('Keychain locked');
}

class _BlockingSecretStore extends _PersistentSecretStore {
  final writeEntered = Completer<void>();
  final allowWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (value == 'replacement-passphrase') {
      writeEntered.complete();
      await allowWrite.future;
    }
    await super.write(key, value);
  }
}

class _SessionSecretStore extends InMemorySecureStorage {
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await super.write(key, value);
  }
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
    secure = _PersistentSecretStore();
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

  test('session storage cannot publish an encrypted or key-bearing plan', () async {
    final session = _SessionSecretStore();
    final ephemeral = BackupService(secureStorage: session);
    final prefs = await SharedPreferences.getInstance();
    for (final enabled in [true, false]) {
      await expectLater(
        ephemeral.createPlan(
          name: 'Must remain recoverable',
          sourcePath: temp.path,
          destinationPath: '/backup',
          provider: 'filen',
          encryptionEnabled: enabled,
          encryptionKey: 'test-only-recovery-key',
        ),
        throwsStateError,
      );
    }
    expect(prefs.getString('backup_plans'), isNull);
    expect(session.reads, 0);
    expect(session.writes, 0);
  });

  test('session storage preserves legacy recovery keys and preferences', () async {
    final plan = _legacyPlan(temp.path);
    final legacy = jsonEncode([
      {...plan.toJson(), 'encryptionKey': plan.encryptionKey},
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backup_plans', legacy);
    await prefs.setString('backup_snapshots_${plan.id}', '[{}]');
    final session = _SessionSecretStore();
    final ephemeral = BackupService(secureStorage: session);
    await expectLater(ephemeral.getPlans(), throwsStateError);
    await expectLater(
      ephemeral.updatePlan(plan.copyWith(name: 'Must not migrate')),
      throwsStateError,
    );
    expect(prefs.getString('backup_plans'), legacy);
    expect(prefs.getString('backup_snapshots_${plan.id}'), '[{}]');
    expect(session.reads, 0);
    expect(session.writes, 0);
    expect(await session.containsKey('backup_plan_key_${plan.id}'), isFalse);
    // The original recovery key is still available to a persistent backend.
    expect((await service.getPlan(plan.id))!.encryptionKey, plan.encryptionKey);
  });

  test('a matching session key cannot authorize an encrypted backup', () async {
    final plan = await createEncryptedPlan();
    final prefs = await SharedPreferences.getInstance();
    final originalPlans = prefs.getString('backup_plans');
    final session = _SessionSecretStore();
    await session.write('backup_plan_key_${plan.id}', plan.encryptionKey!);
    final ephemeral = BackupService(secureStorage: session);
    var invoked = false;
    await expectLater(
      ephemeral.runBackup(
        plan.id,
        uploadFile: (path, bytes) async {
          invoked = true;
          return path;
        },
        encryptBytes: (bytes, key) {
          invoked = true;
          return bytes;
        },
      ),
      throwsStateError,
    );
    expect(invoked, isFalse);
    expect(ephemeral.isRunning, isFalse);
    expect(prefs.getString('backup_plans'), originalPlans);
    expect(prefs.getString('backup_snapshots_${plan.id}'), isNull);
    expect(session.reads, 0);
    expect(session.writes, 1, reason: 'Only the deliberate fixture setup write');
  });

  test('session storage supports plaintext plans but cannot enable encryption', () async {
    final session = _SessionSecretStore();
    final ephemeral = BackupService(secureStorage: session);
    await File('${temp.path}/plain.txt').writeAsString('ordinary plaintext');
    final plan = await ephemeral.createPlan(
      name: 'Plain',
      sourcePath: temp.path,
      destinationPath: '/backup',
      provider: 'filen',
    );
    final prefs = await SharedPreferences.getInstance();
    final originalPlans = prefs.getString('backup_plans');
    await expectLater(
      ephemeral.updatePlan(
        plan.copyWith(encryptionEnabled: true, encryptionKey: 'session-key'),
      ),
      throwsStateError,
    );
    expect(prefs.getString('backup_plans'), originalPlans);
    var uploads = 0;
    final snapshot = await ephemeral.runBackup(
      plan.id,
      uploadFile: (path, bytes) async {
        uploads++;
        expect(utf8.decode(bytes), 'ordinary plaintext');
        return '/backup/$path';
      },
    );
    expect(snapshot.status, BackupSnapshotStatus.completed);
    expect(uploads, 1);
    expect(session.reads, 0);
    expect(session.writes, 0);
  });

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

  for (final change in ['disable encryption', 'replace key']) {
    test('cannot $change while snapshots need the original key', () async {
      const cleartext = 'private data that must remain recoverable';
      await File('${temp.path}/secret.txt').writeAsString(cleartext);
      final plan = await createEncryptedPlan();
      final uploaded = <String, List<int>>{};
      final snapshot = await service.runBackup(
        plan.id,
        uploadFile: (path, bytes) async {
          uploaded['/backup/$path'] = List<int>.from(bytes);
          return '/backup/$path';
        },
        // A reversible test fixture, not a production encryption algorithm.
        encryptBytes: (bytes, key) => bytes.map((b) => b ^ 0xff).toList(),
      );
      final prefs = await SharedPreferences.getInstance();
      final savedPlans = prefs.getString('backup_plans');
      final savedSnapshots = prefs.getString('backup_snapshots_${plan.id}');
      final updated = change == 'disable encryption'
          ? plan.copyWith(encryptionEnabled: false)
          : plan.copyWith(encryptionKey: 'replacement-passphrase');
      await expectLater(service.updatePlan(updated), throwsStateError);
      expect(prefs.getString('backup_plans'), savedPlans);
      expect(prefs.getString('backup_snapshots_${plan.id}'), savedSnapshots);
      expect(
        await secure.read('backup_plan_key_${plan.id}'),
        'new-test-passphrase',
      );

      final target = await Directory('${temp.path}/restore').create();
      final destination = File('${target.path}/secret.txt');
      await destination.writeAsString('keep existing contents');
      var downloads = 0;
      Future<List<int>> download(String path) async {
        downloads++;
        return uploaded[path]!;
      }

      // The denied update must not let restore treat ciphertext as plaintext.
      await expectLater(
        service.restoreSnapshot(
          snapshot.id,
          target.path,
          downloadFile: download,
        ),
        throwsStateError,
      );
      expect(downloads, 0);
      expect(await destination.readAsString(), 'keep existing contents');
      expect(
        await service.restoreSnapshot(
          snapshot.id,
          target.path,
          downloadFile: download,
          decryptBytes: (bytes, key) {
            expect(key, 'new-test-passphrase');
            return bytes.map((b) => b ^ 0xff).toList();
          },
        ),
        1,
      );
      expect(await destination.readAsString(), cleartext);
    });
  }

  test('plaintext snapshots cannot be relabelled as encrypted', () async {
    final plan = await service.createPlan(
      name: 'Plain',
      sourcePath: temp.path,
      destinationPath: '/backup',
      provider: 'filen',
    );
    await service.runBackup(plan.id, uploadFile: (path, bytes) async => path);
    final prefs = await SharedPreferences.getInstance();
    final savedPlans = prefs.getString('backup_plans');
    await expectLater(
      service.updatePlan(
        plan.copyWith(encryptionEnabled: true, encryptionKey: 'new-key'),
      ),
      throwsStateError,
    );
    expect(prefs.getString('backup_plans'), savedPlans);
    expect(await secure.read('backup_plan_key_${plan.id}'), isNull);
  });

  test('snapshots do not block name, schedule or enabled updates', () async {
    final plan = await createEncryptedPlan();
    await service.runBackup(
      plan.id,
      uploadFile: (path, bytes) async => path,
      encryptBytes: (bytes, key) => bytes.map((b) => b ^ 0xff).toList(),
    );
    final current = (await service.getPlan(plan.id))!;
    await service.updatePlan(
      current.copyWith(name: 'Renamed', schedule: '0 3 * * *', enabled: false),
    );
    final updated = (await service.getPlan(plan.id))!;
    expect(updated.name, 'Renamed');
    expect(updated.schedule, '0 3 * * *');
    expect(updated.enabled, isFalse);
    expect(updated.encryptionEnabled, isTrue);
    expect(updated.encryptionKey, 'new-test-passphrase');
    expect(await service.getSnapshots(plan.id), hasLength(1));
  });

  test(
    'backup cannot start during an asynchronous encryption-key update',
    () async {
      final blocked = _BlockingSecretStore();
      secure = blocked;
      service = BackupService(secureStorage: blocked);
      await File('${temp.path}/secret.txt').writeAsString('private data');
      final plan = await createEncryptedPlan();
      final updating = service.updatePlan(
        plan.copyWith(encryptionKey: 'replacement-passphrase'),
      );
      await blocked.writeEntered.future.timeout(const Duration(seconds: 5));
      var touched = false;
      try {
        await expectLater(
          service.runBackup(
            plan.id,
            uploadFile: (path, bytes) async {
              touched = true;
              return path;
            },
            encryptBytes: (bytes, key) {
              touched = true;
              return bytes.map((b) => b ^ 0xff).toList();
            },
          ),
          throwsStateError,
        );
        expect(touched, isFalse);
        expect(await service.getSnapshots(plan.id), isEmpty);
      } finally {
        blocked.allowWrite.complete();
        await updating;
      }
      // Releasing the update exclusion makes a new backup use the new key.
      final snapshot = await service.runBackup(
        plan.id,
        uploadFile: (path, bytes) async => path,
        encryptBytes: (bytes, key) {
          expect(key, 'replacement-passphrase');
          return bytes.map((b) => b ^ 0xff).toList();
        },
      );
      expect(snapshot.status, BackupSnapshotStatus.completed);
    },
  );

  test(
    'rejected legacy update preserves settings and secure store untouched',
    () async {
      final plan = _legacyPlan(temp.path);
      final legacy = jsonEncode([
        {...plan.toJson(), 'encryptionKey': plan.encryptionKey},
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backup_plans', legacy);
      // Any retained snapshot blocks changes, regardless of its status.
      await prefs.setString('backup_snapshots_${plan.id}', '[{}]');
      await expectLater(
        service.updatePlan(plan.copyWith(encryptionKey: 'replacement')),
        throwsStateError,
      );
      expect(prefs.getString('backup_plans'), legacy);
      expect(prefs.getString('backup_snapshots_${plan.id}'), '[{}]');
      expect(await secure.read('backup_plan_key_${plan.id}'), isNull);
    },
  );

  test(
    'damaged snapshot metadata cannot authorize an encryption change',
    () async {
      final plan = await createEncryptedPlan();
      final prefs = await SharedPreferences.getInstance();
      final savedPlans = prefs.getString('backup_plans');
      await prefs.setString('backup_snapshots_${plan.id}', 'damaged JSON');
      await expectLater(
        service.updatePlan(plan.copyWith(encryptionKey: 'replacement')),
        throwsFormatException,
      );
      expect(prefs.getString('backup_plans'), savedPlans);
      expect(
        await secure.read('backup_plan_key_${plan.id}'),
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
