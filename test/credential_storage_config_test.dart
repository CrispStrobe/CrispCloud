import 'dart:convert';

import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _legacyModeKey = 'credential_storage_mode_v1';
const _legacyPathKey = 'custom_keychain_path';
const _selectionKey = CredentialStorageConfig.selectionKey;

String _selection({
  String? mode = 'systemKeychain',
  String? path = '/synthetic/selected.keychain-db',
}) => jsonEncode({'version': 2, 'mode': mode, 'customKeychainPath': path});

String _v3Selection({
  String? mode = 'encryptedFile',
  String? path,
  bool createFileVault = true,
}) => jsonEncode({
  'version': 3,
  'mode': mode,
  'customKeychainPath': path,
  'createFileVault': createFileVault,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  group('selection decoding', () {
    test('every explicit mode survives a strict v2 snapshot', () {
      for (final mode in CredentialStorageMode.values) {
        final selection = CredentialStorageConfig.decodeSelection(
          _selection(mode: mode.name),
        );
        expect(selection.mode, mode);
        expect(selection.customKeychainPath, '/synthetic/selected.keychain-db');
        expect(selection.createFileVault, isFalse);
      }
    });

    test(
      'null mode and path preserve absence rather than inventing a choice',
      () {
        final selection = CredentialStorageConfig.decodeSelection(
          _selection(mode: null, path: null),
        );
        expect(selection.mode, isNull);
        expect(selection.customKeychainPath, isNull);
      },
    );

    test('malformed or ambiguous v2 structures are rejected', () {
      final malformed = [
        '',
        '{',
        'null',
        '[]',
        '{}',
        '{"version":2,"mode":"systemKeychain"}',
        '{"version":2,"customKeychainPath":null}',
        '{"version":2,"mode":"systemKeychain","customKeychainPath":null,"extra":true}',
        '{"version":1,"mode":"systemKeychain","customKeychainPath":null}',
        '{"version":"2","mode":"systemKeychain","customKeychainPath":null}',
        '{"version":2.0,"mode":"systemKeychain","customKeychainPath":null}',
        '{"version":2,"mode":false,"customKeychainPath":null}',
        '{"version":2,"mode":"unknown-mode","customKeychainPath":null}',
        '{"version":2,"mode":"","customKeychainPath":null}',
        '{"version":2,"mode":"systemKeychain","customKeychainPath":42}',
        _selection(path: ''),
        _selection(path: '   '),
        _selection(path: ' /synthetic/keychain.keychain-db'),
        _selection(path: '/synthetic/keychain.keychain-db '),
        _selection(path: '/synthetic/keychain\u0000.keychain-db'),
      ];
      for (final raw in malformed) {
        expect(
          () => CredentialStorageConfig.decodeSelection(raw),
          throwsFormatException,
          reason: raw,
        );
      }
    });

    test(
      'v3 creation intent is explicit and only valid for an encrypted file',
      () {
        final authorized = CredentialStorageConfig.decodeSelection(
          _v3Selection(),
        );
        expect(authorized.mode, CredentialStorageMode.encryptedFile);
        expect(authorized.createFileVault, isTrue);
        for (final mode in [
          null,
          ...CredentialStorageMode.values.map((m) => m.name),
        ]) {
          final existing = CredentialStorageConfig.decodeSelection(
            _v3Selection(mode: mode, createFileVault: false),
          );
          expect(existing.createFileVault, isFalse);
        }
        for (final mode in [null, 'systemKeychain', 'sessionOnly']) {
          expect(
            () => CredentialStorageConfig.decodeSelection(
              _v3Selection(mode: mode),
            ),
            throwsFormatException,
          );
        }
      },
    );

    test('malformed v3 intent never authorizes creation', () {
      final valid = jsonDecode(_v3Selection()) as Map<String, dynamic>;
      final malformed = [
        {...valid}..remove('createFileVault'),
        {...valid, 'createFileVault': null},
        {...valid, 'createFileVault': 'true'},
        {...valid, 'createFileVault': 1},
        {...valid, 'version': 3.0},
        {...valid, 'version': 2},
        {...valid, 'unrecognized': true},
      ];
      for (final value in malformed) {
        expect(
          () => CredentialStorageConfig.decodeSelection(jsonEncode(value)),
          throwsFormatException,
        );
      }
    });
  });

  group('stored selection and legacy compatibility', () {
    test(
      'missing configuration differs from an explicitly selected default',
      () async {
        expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
        expect(
          await CredentialStorageConfig.readMode(),
          CredentialStorageMode.systemKeychain,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(_selectionKey), isFalse);
        expect(prefs.containsKey(_legacyModeKey), isFalse);

        await CredentialStorageConfig.writeSelection(
          mode: CredentialStorageMode.systemKeychain,
        );
        expect(
          await CredentialStorageConfig.readModeIfConfigured(),
          CredentialStorageMode.systemKeychain,
        );
        expect(prefs.containsKey(_selectionKey), isTrue);
      },
    );

    test(
      'legacy mode/path stay readable without an implicit migration write',
      () async {
        for (final mode in CredentialStorageMode.values) {
          final platform = _installPreferences({
            _legacyModeKey: mode.name,
            _legacyPathKey: '  /synthetic/legacy.keychain-db  ',
            'unrelated.preference': 'preserve',
          });
          final before = await platform.getAll();
          final selection = await CredentialStorageConfig.readSelection();
          expect(selection.mode, mode);
          expect(selection.customKeychainPath, '/synthetic/legacy.keychain-db');
          expect(await CredentialStorageConfig.readModeIfConfigured(), mode);
          expect(platform.writes, isEmpty);
          expect(await platform.getAll(), before);
        }
      },
    );

    test('legacy path alone does not become an explicit mode', () async {
      SharedPreferences.setMockInitialValues({
        _legacyPathKey: '/synthetic/legacy.keychain-db',
      });
      expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
      expect(
        await CredentialStorageConfig.readCustomKeychainPath(),
        '/synthetic/legacy.keychain-db',
      );
      expect(
        await CredentialStorageConfig.readMode(),
        CredentialStorageMode.systemKeychain,
      );
    });

    test(
      'invalid explicit legacy settings cannot fall back to a default',
      () async {
        for (final values in <Map<String, Object>>[
          {_legacyModeKey: 'unknown-mode'},
          {_legacyModeKey: 123},
          {_legacyModeKey: true},
          {_legacyPathKey: 123},
          {_legacyPathKey: '/synthetic/bad\u0000path.keychain-db'},
        ]) {
          SharedPreferences.setMockInitialValues(values);
          await expectLater(
            CredentialStorageConfig.readSelection(),
            throwsFormatException,
          );
          await expectLater(
            CredentialStorageConfig.readMode(),
            throwsFormatException,
          );
        }
      },
    );

    test('valid v2 selection supersedes incompatible legacy keys', () async {
      SharedPreferences.setMockInitialValues({
        _selectionKey: _selection(mode: 'encryptedFile', path: null),
        _legacyModeKey: 'invalid-legacy-mode',
        _legacyPathKey: 42,
      });
      final selection = await CredentialStorageConfig.readSelection();
      expect(selection.mode, CredentialStorageMode.encryptedFile);
      expect(selection.customKeychainPath, isNull);
    });

    test(
      'malformed v2 selection never falls back to otherwise valid legacy keys',
      () async {
        for (final raw in <Object>[
          false,
          7,
          ['not', 'a', 'selection'],
          '{bad',
          '{"version":2,"mode":"missing","customKeychainPath":null}',
        ]) {
          SharedPreferences.setMockInitialValues({
            _selectionKey: raw,
            _legacyModeKey: 'systemKeychain',
            _legacyPathKey: '/synthetic/legacy.keychain-db',
          });
          await expectLater(
            CredentialStorageConfig.readSelection(),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'readSelection reloads one complete externally changed snapshot',
      () async {
        final platform = _installPreferences({
          _selectionKey: _selection(mode: 'systemKeychain'),
        });
        expect(
          (await CredentialStorageConfig.readSelection()).mode,
          CredentialStorageMode.systemKeychain,
        );
        await platform.setValue(
          'String',
          'flutter.$_selectionKey',
          _selection(
            mode: 'encryptedFile',
            path: '/synthetic/next.keychain-db',
          ),
        );
        final selection = await CredentialStorageConfig.readSelection();
        expect(selection.mode, CredentialStorageMode.encryptedFile);
        expect(selection.customKeychainPath, '/synthetic/next.keychain-db');
      },
    );
  });

  group('atomic selection persistence', () {
    test('one preference write saves the pair and leaves legacy/profile data intact', () async {
      final original = <String, Object>{
        _legacyModeKey: 'systemKeychain',
        _legacyPathKey: '/synthetic/legacy.keychain-db',
        'provider': 'filen',
        'unrelated.preference': 'preserve',
      };
      final platform = _installPreferences(original);
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
        customKeychainPath: '  /synthetic/new.keychain-db  ',
      );
      expect(platform.writes.length, 1);
      expect(platform.writes.single.key, 'flutter.$_selectionKey');
      expect(platform.writes.single.type, 'String');
      final persisted = await platform.getAll();
      for (final entry in original.entries) {
        expect(persisted['flutter.${entry.key}'], entry.value);
      }
      expect(jsonDecode(platform.writes.single.value as String), {
        'version': 3,
        'mode': 'encryptedFile',
        'customKeychainPath': '/synthetic/new.keychain-db',
        'createFileVault': false,
      });
      final selection = await CredentialStorageConfig.readSelection();
      expect(selection.mode, CredentialStorageMode.encryptedFile);
      expect(selection.customKeychainPath, '/synthetic/new.keychain-db');
      expect(selection.createFileVault, isFalse);
    });

    test(
      'mode update retains a legacy custom keychain in the new snapshot',
      () async {
        SharedPreferences.setMockInitialValues({
          _legacyModeKey: 'systemKeychain',
          _legacyPathKey: '/synthetic/legacy.keychain-db',
        });
        await CredentialStorageConfig.writeMode(
          CredentialStorageMode.sessionOnly,
        );
        final selection = await CredentialStorageConfig.readSelection();
        expect(selection.mode, CredentialStorageMode.sessionOnly);
        expect(selection.customKeychainPath, '/synthetic/legacy.keychain-db');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(_legacyModeKey), 'systemKeychain');
        expect(
          prefs.getString(_legacyPathKey),
          '/synthetic/legacy.keychain-db',
        );
      },
    );

    test('path-only setup preserves missing mode and clears paths without resurrecting legacy', () async {
      SharedPreferences.setMockInitialValues({
        _legacyPathKey: '/synthetic/legacy.keychain-db',
      });
      await CredentialStorageConfig.writeCustomKeychainPath(
        '/synthetic/next.keychain-db',
      );
      expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
      expect(
        await CredentialStorageConfig.readCustomKeychainPath(),
        '/synthetic/next.keychain-db',
      );
      await CredentialStorageConfig.writeCustomKeychainPath('  ');
      expect(await CredentialStorageConfig.readModeIfConfigured(), isNull);
      expect(await CredentialStorageConfig.readCustomKeychainPath(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_legacyPathKey), '/synthetic/legacy.keychain-db');
    });

    test('NUL path rejection makes no preference write', () async {
      final platform = _installPreferences({_selectionKey: _selection()});
      final before = await platform.getAll();
      await expectLater(
        () => CredentialStorageConfig.writeSelection(
          mode: CredentialStorageMode.systemKeychain,
          customKeychainPath: '/synthetic/bad\u0000path.keychain-db',
        ),
        throwsFormatException,
      );
      await expectLater(
        CredentialStorageConfig.writeCustomKeychainPath(
          '/synthetic/bad\u0000path.keychain-db',
        ),
        throwsFormatException,
      );
      expect(platform.writes, isEmpty);
      expect(await platform.getAll(), before);
    });

    for (final behavior in [
      _WriteBehavior.reject,
      _WriteBehavior.acknowledgeWithoutSaving,
      _WriteBehavior.throwBeforeSaving,
      _WriteBehavior.readbackFailure,
    ]) {
      test(
        '${behavior.name} preserves durable selection and clears optimistic cache',
        () async {
          final original = _selection();
          final platform = _installPreferences({
            _selectionKey: original,
            _legacyModeKey: 'sessionOnly',
            _legacyPathKey: '/synthetic/legacy.keychain-db',
            'provider': 'internxt',
          }, behavior: behavior);
          final prefs = await SharedPreferences.getInstance();
          final before = await platform.getAll();
          expect(prefs.getString(_selectionKey), original);

          await expectLater(
            CredentialStorageConfig.writeSelection(
              mode: CredentialStorageMode.encryptedFile,
              customKeychainPath: '/synthetic/rejected.keychain-db',
            ),
            throwsStateError,
          );

          // Read the existing object before invoking config again: reload must
          // have repaired the optimistic SharedPreferences cache on failure.
          expect(prefs.getString(_selectionKey), original);
          expect(await platform.getAll(), before);
          final selection = await CredentialStorageConfig.readSelection();
          expect(selection.mode, CredentialStorageMode.systemKeychain);
          expect(
            selection.customKeychainPath,
            '/synthetic/selected.keychain-db',
          );
          expect(platform.writes.length, 1);
          expect(platform.writes.single.key, 'flutter.$_selectionKey');
        },
      );
    }
  });

  group('single-use vault creation authorization', () {
    test('legacy and ordinary mode changes never grant creation', () async {
      for (final values in <Map<String, Object>>[
        {},
        {_legacyModeKey: 'encryptedFile'},
        {_selectionKey: _selection(mode: 'encryptedFile', path: null)},
      ]) {
        SharedPreferences.setMockInitialValues(values);
        expect(
          await CredentialStorageConfig.readFileVaultCreationAllowed(),
          isFalse,
        );
        await CredentialStorageConfig.writeMode(
          CredentialStorageMode.encryptedFile,
        );
        expect(
          await CredentialStorageConfig.readFileVaultCreationAllowed(),
          isFalse,
        );
      }
    });

    test(
      'explicit grant is persisted with the selected backend in one write',
      () async {
        final platform = _installPreferences({'profile_setting': 'preserve'});
        await CredentialStorageConfig.writeSelection(
          mode: CredentialStorageMode.encryptedFile,
          customKeychainPath: '/synthetic/old.keychain-db',
          createFileVault: true,
        );
        expect(platform.writes.length, 1);
        expect(jsonDecode(platform.writes.single.value as String), {
          'version': 3,
          'mode': 'encryptedFile',
          'customKeychainPath': '/synthetic/old.keychain-db',
          'createFileVault': true,
        });
        expect(
          await CredentialStorageConfig.readFileVaultCreationAllowed(),
          isTrue,
        );
        expect(
          (await platform.getAll())['flutter.profile_setting'],
          'preserve',
        );
      },
    );

    test('non-file backend cannot receive a creation grant', () async {
      final platform = _installPreferences({});
      for (final mode in [
        CredentialStorageMode.systemKeychain,
        CredentialStorageMode.sessionOnly,
      ]) {
        await expectLater(
          CredentialStorageConfig.writeSelection(
            mode: mode,
            createFileVault: true,
          ),
          throwsFormatException,
        );
      }
      expect(platform.writes, isEmpty);
    });

    test(
      'consumption clears only the grant and rejects a stale second startup',
      () async {
        final platform = _installPreferences({
          _selectionKey: _v3Selection(path: '/synthetic/original.keychain-db'),
          _legacyModeKey: 'systemKeychain',
          'profile_setting': 'existing-profile',
        });
        final expected = await CredentialStorageConfig.readSelection();
        await CredentialStorageConfig.consumeFileVaultCreation(
          expected: expected,
        );
        final current = await CredentialStorageConfig.readSelection();
        expect(current.mode, expected.mode);
        expect(current.customKeychainPath, expected.customKeychainPath);
        expect(current.createFileVault, isFalse);
        expect(platform.writes.length, 1);
        await expectLater(
          CredentialStorageConfig.consumeFileVaultCreation(expected: expected),
          throwsStateError,
        );
        await expectLater(
          CredentialStorageConfig.consumeFileVaultCreation(expected: current),
          throwsStateError,
        );
        expect(platform.writes.length, 1);
        expect(
          (await platform.getAll())['flutter.profile_setting'],
          'existing-profile',
        );
        expect(
          (await platform.getAll())['flutter.$_legacyModeKey'],
          'systemKeychain',
        );
      },
    );

    test('changed selection rejects consumption without changing the new selection', () async {
      const expected = CredentialStorageSelection(
        mode: CredentialStorageMode.encryptedFile,
        customKeychainPath: '/synthetic/original.keychain-db',
        createFileVault: true,
      );
      for (final changed in [
        _v3Selection(path: '/synthetic/other.keychain-db'),
        _v3Selection(path: expected.customKeychainPath, createFileVault: false),
        _v3Selection(
          mode: 'sessionOnly',
          path: expected.customKeychainPath,
          createFileVault: false,
        ),
      ]) {
        final platform = _installPreferences({_selectionKey: changed});
        final before = await platform.getAll();
        await expectLater(
          CredentialStorageConfig.consumeFileVaultCreation(expected: expected),
          throwsStateError,
        );
        expect(platform.writes, isEmpty);
        expect(await platform.getAll(), before);
      }
    });

    test(
      'concurrent same-isolate consumers cannot spend the same grant twice',
      () async {
        final platform = _installPreferences({_selectionKey: _v3Selection()});
        final expected = await CredentialStorageConfig.readSelection();
        Future<bool> consume() async {
          try {
            await CredentialStorageConfig.consumeFileVaultCreation(
              expected: expected,
            );
            return true;
          } on StateError {
            return false;
          }
        }

        final outcomes = await Future.wait([consume(), consume()]);
        expect(outcomes.where((value) => value).length, 1);
        expect(platform.writes.length, 1);
        expect(
          await CredentialStorageConfig.readFileVaultCreationAllowed(),
          isFalse,
        );
      },
    );

    for (final behavior in [
      _WriteBehavior.reject,
      _WriteBehavior.acknowledgeWithoutSaving,
      _WriteBehavior.throwBeforeSaving,
      _WriteBehavior.readbackFailure,
      _WriteBehavior.saveThenReadbackFailure,
    ]) {
      test('${behavior.name} consumption cannot authorize a creator', () async {
        final platform = _installPreferences({
          _selectionKey: _v3Selection(),
        }, behavior: behavior);
        final expected = await CredentialStorageConfig.readSelection();
        var creations = 0;
        await expectLater(() async {
          await CredentialStorageConfig.consumeFileVaultCreation(
            expected: expected,
          );
          creations++;
        }, throwsStateError);
        expect(creations, 0);
        expect(platform.writes.length, 1);
        if (behavior == _WriteBehavior.saveThenReadbackFailure) {
          expect(
            await CredentialStorageConfig.readFileVaultCreationAllowed(),
            isFalse,
          );
          await expectLater(
            CredentialStorageConfig.consumeFileVaultCreation(
              expected: expected,
            ),
            throwsStateError,
          );
          expect(platform.writes.length, 1);
        }
      });
    }

    test(
      'leaving encrypted-file mode retires an outstanding creation grant',
      () async {
        SharedPreferences.setMockInitialValues({_selectionKey: _v3Selection()});
        await CredentialStorageConfig.writeMode(
          CredentialStorageMode.systemKeychain,
        );
        await CredentialStorageConfig.writeMode(
          CredentialStorageMode.encryptedFile,
        );
        expect(
          await CredentialStorageConfig.readFileVaultCreationAllowed(),
          isFalse,
        );
      },
    );
  });
}

enum _WriteBehavior {
  accept,
  reject,
  acknowledgeWithoutSaving,
  throwBeforeSaving,
  readbackFailure,
  saveThenReadbackFailure,
}

_TestPreferences _installPreferences(
  Map<String, Object> values, {
  _WriteBehavior behavior = _WriteBehavior.accept,
}) {
  // Reset the singleton first, then install the controlled durable platform.
  SharedPreferences.setMockInitialValues({});
  final platform = _TestPreferences(values, behavior: behavior);
  SharedPreferencesStorePlatform.instance = platform;
  return platform;
}

class _TestPreferences extends InMemorySharedPreferencesStore {
  _TestPreferences(Map<String, Object> values, {required this.behavior})
    : super.withData({
        for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
      });

  final _WriteBehavior behavior;
  final writes = <({String type, String key, Object value})>[];
  bool _failNextRead = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add((type: valueType, key: key, value: value));
    switch (behavior) {
      case _WriteBehavior.accept:
        return super.setValue(valueType, key, value);
      case _WriteBehavior.reject:
        return false;
      case _WriteBehavior.acknowledgeWithoutSaving:
        return true;
      case _WriteBehavior.throwBeforeSaving:
        throw StateError('Injected preference write failure');
      case _WriteBehavior.readbackFailure:
        _failNextRead = true;
        return true;
      case _WriteBehavior.saveThenReadbackFailure:
        final result = await super.setValue(valueType, key, value);
        _failNextRead = true;
        return result;
    }
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (_failNextRead) {
      _failNextRead = false;
      throw StateError('Injected preference verification read failure');
    }
    return super.getAll();
  }
}
