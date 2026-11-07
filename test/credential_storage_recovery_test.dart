import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/credential_storage_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _originalPath = '/synthetic/original.keychain-db';
const _original = CredentialStorageSelection(
  mode: CredentialStorageMode.systemKeychain,
  customKeychainPath: _originalPath,
);

Matcher _failure(CredentialStorageRecoveryFailure reason) =>
    isA<CredentialStorageRecoveryException>().having(
      (error) => error.reason,
      'reason',
      reason,
    );

Map<String, Object?> _snapshot(SharedPreferences prefs) => {
  for (final key in prefs.getKeys()) key: prefs.get(key),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      CredentialStorageConfig.selectionKey: jsonEncode({
        'version': 2,
        'mode': 'systemKeychain',
        'customKeychainPath': _originalPath,
      }),
      'credential_storage_mode_v1': 'encryptedFile',
      'custom_keychain_path': '/synthetic/legacy.keychain-db',
      'filen_credentials': 'public-test-legacy-credential',
      'profile_setting': 'preserve-existing-profile',
    });
  });

  tearDown(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same-store regrant leaves selection and existing profile untouched',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final before = _snapshot(prefs);
      final calls = <String>[];
      final recovery = CredentialStorageRecovery(
        failedSelection: _original,
        supportsCustomKeychains: true,
        restoreAccess: (originalPath) async {
          calls.add(originalPath);
          return true;
        },
      );

      expect(recovery.canRestoreKeychainAccess, isTrue);
      expect(await recovery.restoreKeychainAccess(), isTrue);
      expect(calls, [_originalPath]);
      await prefs.reload();
      expect(_snapshot(prefs), before);
    },
  );

  test(
    'cancelling access repair leaves the protected selection intact',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final before = _snapshot(prefs);
      final recovery = CredentialStorageRecovery(
        failedSelection: _original,
        supportsCustomKeychains: true,
        restoreAccess: (originalPath) async {
          expect(originalPath, _originalPath);
          return false;
        },
      );

      expect(await recovery.restoreKeychainAccess(), isFalse);
      await prefs.reload();
      expect(_snapshot(prefs), before);
    },
  );

  test(
    'legacy implicit system mode can repair only its configured custom path',
    () async {
      const legacy = CredentialStorageSelection(
        customKeychainPath: _originalPath,
      );
      var called = false;
      final recovery = CredentialStorageRecovery(
        failedSelection: legacy,
        supportsCustomKeychains: true,
        readSelection: () async => legacy,
        restoreAccess: (path) async {
          expect(path, _originalPath);
          called = true;
          return true;
        },
      );
      expect(recovery.canRestoreKeychainAccess, isTrue);
      expect(await recovery.restoreKeychainAccess(), isTrue);
      expect(called, isTrue);
    },
  );

  test('default, file-vault, session, malformed, and unsupported stores cannot regrant', () async {
    final disallowed = <CredentialStorageSelection>[
      const CredentialStorageSelection(),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.systemKeychain,
      ),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.encryptedFile,
        customKeychainPath: _originalPath,
      ),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.sessionOnly,
        customKeychainPath: _originalPath,
      ),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.systemKeychain,
        customKeychainPath: '',
      ),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.systemKeychain,
        customKeychainPath: '  ',
      ),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.systemKeychain,
        customKeychainPath: ' $_originalPath',
      ),
      const CredentialStorageSelection(
        mode: CredentialStorageMode.systemKeychain,
        customKeychainPath: '/bad\u0000path',
      ),
    ];
    for (final selection in disallowed) {
      final recovery = CredentialStorageRecovery(
        failedSelection: selection,
        supportsCustomKeychains: true,
        readSelection: () async =>
            throw StateError('Must not inspect another store'),
        restoreAccess: (_) async =>
            throw StateError('Must not browse another store'),
      );
      expect(recovery.canRestoreKeychainAccess, isFalse);
      await expectLater(
        recovery.restoreKeychainAccess(),
        throwsA(_failure(CredentialStorageRecoveryFailure.unsupported)),
      );
    }
    final unsupported = CredentialStorageRecovery(
      failedSelection: _original,
      supportsCustomKeychains: false,
      readSelection: () async =>
          throw StateError('Must not inspect on this platform'),
      restoreAccess: (_) async =>
          throw StateError('Must not browse on this platform'),
    );
    expect(unsupported.canRestoreKeychainAccess, isFalse);
    await expectLater(
      unsupported.restoreKeychainAccess(),
      throwsA(_failure(CredentialStorageRecoveryFailure.unsupported)),
    );
  });

  test(
    'a changed configured mode or path is rejected before browsing',
    () async {
      for (final changed in [
        const CredentialStorageSelection(
          mode: CredentialStorageMode.sessionOnly,
        ),
        const CredentialStorageSelection(
          mode: CredentialStorageMode.encryptedFile,
        ),
        const CredentialStorageSelection(
          mode: CredentialStorageMode.systemKeychain,
        ),
        const CredentialStorageSelection(
          mode: CredentialStorageMode.systemKeychain,
          customKeychainPath: '/synthetic/different.keychain-db',
        ),
        const CredentialStorageSelection(
          mode: CredentialStorageMode.systemKeychain,
          customKeychainPath: _originalPath,
          createFileVault: true,
        ),
      ]) {
        var calls = 0;
        final recovery = CredentialStorageRecovery(
          failedSelection: _original,
          supportsCustomKeychains: true,
          readSelection: () async => changed,
          restoreAccess: (_) async {
            calls++;
            return true;
          },
        );
        await expectLater(
          recovery.restoreKeychainAccess(),
          throwsA(_failure(CredentialStorageRecoveryFailure.selectionChanged)),
        );
        expect(calls, 0);
      }
    },
  );

  test(
    'selection changed while picker is open is not accepted or rolled back',
    () async {
      final enteredPicker = Completer<void>();
      final finishPicker = Completer<bool>();
      final calls = <String>[];
      final recovery = CredentialStorageRecovery(
        failedSelection: _original,
        supportsCustomKeychains: true,
        restoreAccess: (path) {
          calls.add(path);
          enteredPicker.complete();
          return finishPicker.future;
        },
      );
      final operation = recovery.restoreKeychainAccess();
      final rejected = expectLater(
        operation,
        throwsA(_failure(CredentialStorageRecoveryFailure.selectionChanged)),
      );
      await enteredPicker.future;
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.systemKeychain,
        customKeychainPath: '/synthetic/concurrently-selected.keychain-db',
      );
      final prefs = await SharedPreferences.getInstance();
      final concurrent = _snapshot(prefs);
      finishPicker.complete(true);
      await rejected;
      await prefs.reload();
      expect(_snapshot(prefs), concurrent);
      expect(calls, [_originalPath]);
    },
  );

  test('unreadable selection cannot authorize a native access grant', () async {
    var called = false;
    final recovery = CredentialStorageRecovery(
      failedSelection: _original,
      supportsCustomKeychains: true,
      readSelection: () async =>
          throw const FormatException('PRIVATE_RAW_SELECTION'),
      restoreAccess: (_) async {
        called = true;
        return true;
      },
    );
    await expectLater(
      recovery.restoreKeychainAccess(),
      throwsA(_failure(CredentialStorageRecoveryFailure.unavailable)),
    );
    expect(called, isFalse);
  });

  test(
    'verification read failure after regrant cannot report a successful repair',
    () async {
      var reads = 0;
      var grants = 0;
      final recovery = CredentialStorageRecovery(
        failedSelection: _original,
        supportsCustomKeychains: true,
        readSelection: () async {
          reads++;
          if (reads == 1) return _original;
          throw StateError('PRIVATE_READBACK_DETAILS');
        },
        restoreAccess: (_) async {
          grants++;
          return true;
        },
      );
      await expectLater(
        recovery.restoreKeychainAccess(),
        throwsA(_failure(CredentialStorageRecoveryFailure.unavailable)),
      );
      expect(grants, 1);
      expect(reads, 2);
    },
  );

  test(
    'native errors cannot leak into pre-unlock UI or mutate profile selection',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final before = _snapshot(prefs);
      final recovery = CredentialStorageRecovery(
        failedSelection: _original,
        supportsCustomKeychains: true,
        restoreAccess: (_) async =>
            throw StateError('PRIVATE_TOKEN at /private/account/path'),
      );
      try {
        await recovery.restoreKeychainAccess();
        fail('Expected a safe recovery failure');
      } on CredentialStorageRecoveryException catch (error) {
        expect(error.reason, CredentialStorageRecoveryFailure.unavailable);
        expect(error.toString(), isNot(contains('PRIVATE_TOKEN')));
        expect(error.toString(), isNot(contains('/private/account/path')));
        expect(error.toString(), contains('original file'));
      }
      await prefs.reload();
      expect(_snapshot(prefs), before);
    },
  );
}
