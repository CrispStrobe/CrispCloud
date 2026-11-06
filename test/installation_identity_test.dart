import 'dart:async';

import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firstId = 'd21919e9-f558-4726-8bdd-aaef7429ae7b';
const _secondId = 'ed237c77-31e8-4050-9ddb-7769b4aab9aa';

class _Store implements InstallationIdentityStore {
  String? value;
  bool accept = true;
  bool failRead = false;
  bool failWrite = false;
  bool discardWrite = false;
  int reads = 0;
  int writes = 0;
  Completer<void>? readGate;

  @override
  Future<String?> read() async {
    reads++;
    await readGate?.future;
    if (failRead) throw StateError('Preference storage unavailable');
    return value;
  }

  @override
  Future<bool> write(String input) async {
    writes++;
    if (failWrite) throw StateError('Preference write failed');
    if (accept && !discardWrite) value = input;
    return accept;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uninitialized services have distinct nonpersistent session identities',
    () {
      final first = InstallationIdentityService(store: _Store());
      final second = InstallationIdentityService(store: _Store());
      expect(first.current.persistent, isFalse);
      expect(second.current.persistent, isFalse);
      expect(first.current.key, startsWith('session:'));
      expect(first.current.key, isNot(second.current.key));
    },
  );

  test(
    'acknowledged installation identity survives a new service instance',
    () async {
      final store = _Store();
      final first = InstallationIdentityService(
        store: store,
        createId: () => _firstId,
      );
      final value = await first.initialize();
      expect(value.persistent, isTrue);
      expect(value.key, 'installation:$_firstId');
      expect(store.writes, 1);
      final restarted = InstallationIdentityService(
        store: store,
        createId: () => _secondId,
      );
      expect((await restarted.initialize()).key, value.key);
      expect(store.writes, 1);
    },
  );

  test(
    'separate installation stores cannot alias identical local paths',
    () async {
      final first = await InstallationIdentityService(
        store: _Store(),
        createId: () => _firstId,
      ).initialize();
      final second = await InstallationIdentityService(
        store: _Store(),
        createId: () => _secondId,
      ).initialize();
      final a = FileReference(
        storage: StorageReference(
          kind: 'local',
          provider: 'linux',
          accountKey: first.key,
        ),
        path: '/same/report.txt',
      );
      final b = FileReference(
        storage: StorageReference(
          kind: 'local',
          provider: 'linux',
          accountKey: second.key,
        ),
        path: '/same/report.txt',
      );
      expect(a.id, isNot(b.id));
      expect(a.storage, isNot(b.storage));
    },
  );

  test('concurrent initialization shares one persistence attempt', () async {
    final store = _Store()..readGate = Completer<void>();
    final service = InstallationIdentityService(
      store: store,
      createId: () => _firstId,
    );
    final first = service.initialize();
    final second = service.initialize();
    expect(identical(first, second), isTrue);
    store.readGate!.complete();
    final values = await Future.wait([first, second]);
    expect(values[0].key, values[1].key);
    expect(store.writes, 1);
  });

  test(
    'invalid stored identity is replaced only after an acknowledged write',
    () async {
      final store = _Store()..value = 'device';
      final service = InstallationIdentityService(
        store: store,
        createId: () => _firstId,
      );
      expect((await service.initialize()).key, 'installation:$_firstId');
      expect(store.value, _firstId);
      expect(store.writes, 1);
    },
  );

  test(
    'rejected persistence remains session-only without rebinding later',
    () async {
      final store = _Store()..accept = false;
      final service = InstallationIdentityService(
        store: store,
        createId: () => _firstId,
      );
      final original = service.current;
      expect(await service.initialize(), same(original));
      expect(service.current.persistent, isFalse);
      store.accept = true;
      expect(await service.initialize(), same(original));
      expect(store.writes, 1);
    },
  );

  test('read failure retains an independent session identity', () async {
    final store = _Store()..failRead = true;
    final service = InstallationIdentityService(
      store: store,
      createId: () => _firstId,
    );
    final original = service.current;
    expect(await service.initialize(), same(original));
    expect(service.current.persistent, isFalse);
    expect(store.writes, 0);
  });

  test(
    'write exceptions and missing readback never claim persistent storage',
    () async {
      for (final store in [
        _Store()..failWrite = true,
        _Store()..discardWrite = true,
      ]) {
        final service = InstallationIdentityService(
          store: store,
          createId: () => _firstId,
        );
        expect((await service.initialize()).persistent, isFalse);
        expect(service.current.key, startsWith('session:'));
      }
    },
  );

  test(
    'preferences store is acknowledged and reread by a subsequent launch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = await InstallationIdentityService(createId: () => _firstId)
          .initialize();
      final second = await InstallationIdentityService(
        createId: () => _secondId,
      ).initialize();
      expect(first.persistent, isTrue);
      expect(second.key, first.key);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(
          PreferencesInstallationIdentityStore.preferenceKey,
        ),
        _firstId,
      );
    },
  );

  test('local references and pre-created backends use the initialized installation', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final before = storageReferenceForSource(const LocalPanelSource('/same'));
    expect(before.persistent, isFalse);
    expect(backend.canRecover, isFalse);
    expect(backend.identity, before.id);
    await InstallationIdentityService.instance.initialize();
    final after = storageReferenceForSource(const LocalPanelSource('/same'));
    expect(after.persistent, isTrue);
    expect(after, isNot(before));
    expect(backend.identity, after.id);
    expect(backend.canRecover, isTrue);
    expect(
      storageReferenceForSource(const LocalPanelSource('/elsewhere')),
      after,
    );
    expect(StorageReference.fromJson(after.toJson()), after);
    expect(after.accountKey, isNot('device'));
  });
}
