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

  test(
    'empty native installation records a resumable first-setup marker',
    () async {
      expect(await capture(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(CredentialStorageFirstSetup.pendingKey), isTrue);
      expect(await capture(), isTrue);
      await CredentialStorageConfig.writeMode(
        CredentialStorageMode.encryptedFile,
      );
      expect(await capture(), isTrue);

      await CredentialStorageFirstSetup.complete();

      expect(
        prefs.containsKey(CredentialStorageFirstSetup.pendingKey),
        isFalse,
      );
      expect(
        await CredentialStorageConfig.readMode(),
        CredentialStorageMode.encryptedFile,
      );
      expect(await capture(), isFalse);
    },
  );

  test('profile preferences appearing during native evidence invalidate first setup', () async {
    final captured = await CredentialStorageFirstSetup.capture(
      profileIsEmpty: (_) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'installation_id',
          'concurrently-created-profile',
        );
        return true;
      },
    );
    expect(captured, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CredentialStorageFirstSetup.pendingKey), isFalse);
    expect(prefs.getString('installation_id'), 'concurrently-created-profile');
  });

  test(
    'a pending native setup cannot overwrite a concurrently changed selection',
    () async {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
      });
      final captured = await CredentialStorageFirstSetup.capture(
        profileIsEmpty: (_) async {
          await CredentialStorageConfig.writeSelection(
            mode: CredentialStorageMode.systemKeychain,
            customKeychainPath: '/synthetic/other-profile.keychain-db',
          );
          return true;
        },
      );
      expect(captured, isFalse);
      final selection = await CredentialStorageConfig.readSelection();
      expect(
        selection.customKeychainPath,
        '/synthetic/other-profile.keychain-db',
      );
      expect(selection.createFileVault, isFalse);
    },
  );

  test(
    'an older profile does not become fresh because the new mode is absent',
    () async {
      SharedPreferences.setMockInitialValues({'cloud_provider': 'filen'});
      expect(await capture(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(CredentialStorageFirstSetup.pendingKey),
        isFalse,
      );
    },
  );

  test(
    'legacy config, including an empty existing directory, blocks first setup',
    () async {
      await Directory(legacy).create();
      expect(await capture(), isFalse);
    },
  );

  test('unavailable support path cannot be mistaken for a missing profile', () async {
    final blockingFile = File(p.join(root.path, 'not-a-directory'));
    await blockingFile.writeAsString('preserve existing data');
    support = Directory(p.join(blockingFile.path, 'support'));
    // This is a real lookup error masked as notFound by type(), without
    // relying on chmod (tests can run with privileges that bypass permissions).
    expect(
      await FileSystemEntity.type(support.path, followLinks: false),
      FileSystemEntityType.notFound,
    );

    expect(await capture(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CredentialStorageFirstSetup.pendingKey), isFalse);
    expect(await blockingFile.readAsString(), 'preserve existing data');
  });

  test('unavailable legacy parent cannot authorize first setup', () async {
    final blockingFile = File(p.join(root.path, 'not-a-directory'));
    await blockingFile.writeAsString('preserve legacy parent');
    legacy = p.join(blockingFile.path, '.cloud-storage-config');
    expect(
      await FileSystemEntity.type(legacy, followLinks: false),
      FileSystemEntityType.notFound,
    );

    expect(await capture(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CredentialStorageFirstSetup.pendingKey), isFalse);
    expect(await blockingFile.readAsString(), 'preserve legacy parent');
  });

  test(
    'genuinely absent parent directories still permit a fresh profile',
    () async {
      legacy = p.join(root.path, 'missing-parent', '.cloud-storage-config');
      support = Directory(p.join(root.path, 'other-missing-parent', 'support'));

      expect(await capture(), isTrue);

      expect(await support.exists(), isFalse);
      expect(await Directory(p.dirname(legacy)).exists(), isFalse);
    },
  );

  test(
    'symlinked support and legacy entries cannot authorize first setup',
    () async {
      final emptyTarget = Directory(p.join(root.path, 'target'));
      await emptyTarget.create();
      final supportLink = support.path;
      await Link(supportLink).create(emptyTarget.path);
      for (final path in [supportLink, '$supportLink${p.separator}']) {
        support = Directory(path);
        expect(await capture(), isFalse);
      }

      support = Directory(supportLink);
      await Link(supportLink).delete();
      await Link(legacy).create(p.join(root.path, 'missing-target'));
      expect(await capture(), isFalse);
      legacy = '$legacy${p.separator}';
      expect(await capture(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(CredentialStorageFirstSetup.pendingKey),
        isFalse,
      );
    },
    skip: Platform.isWindows,
  ); // Symlink creation needs extra privileges there.

  test(
    'parent traversal cannot change the inspected profile during normalization',
    () async {
      final target = Directory(p.join(root.path, 'actual', 'nested'));
      await target.create(recursive: true);
      final protectedSupport = Directory(
        p.join(root.path, 'actual', 'support'),
      );
      await protectedSupport.create();
      final vault = File(
        p.join(protectedSupport.path, 'credential-vault.json'),
      );
      await vault.writeAsString('preserve protected profile');
      final alias = p.join(root.path, 'alias');
      await Link(alias).create(target.path);
      support = Directory(p.join(alias, '..', 'support'));

      expect(await capture(), isFalse);
      expect(await vault.readAsString(), 'preserve protected profile');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(CredentialStorageFirstSetup.pendingKey),
        isFalse,
      );
    },
    skip: Platform.isWindows,
  );

  test(
    'existing support data blocks first setup even with a pending marker',
    () async {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
      });
      await support.create();
      final vault = File(p.join(support.path, 'credential-vault.json'));
      await vault.writeAsString('existing-protected-data');
      expect(await capture(), isFalse);
      expect(await vault.readAsString(), 'existing-protected-data');
    },
  );

  test(
    'an unrelated preference invalidates an interrupted first setup',
    () async {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
        'installation_id': 'existing-profile',
      });
      expect(await capture(), isFalse);
    },
  );

  test(
    'an explicit keychain path can resume interrupted fresh setup',
    () async {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
        'custom_keychain_path': '/synthetic/keychains/selected.keychain-db',
      });
      expect(await capture(), isTrue);
      await CredentialStorageFirstSetup.complete();
      expect(await capture(), isFalse);
    },
  );

  test(
    'atomic selection intent resumes only when its complete schema is valid',
    () async {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
      });
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
      );
      expect(await capture(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'credential_storage_selection_v2',
        jsonEncode({
          'version': 2,
          'mode': 'encryptedFile',
          'customKeychainPath': null,
          'unrecognized': 'existing-profile-data',
        }),
      );
      expect(await capture(), isFalse);
    },
  );

  test(
    'unknown or malformed pending choices do not authorize a fallback',
    () async {
      for (final value in ['unknown', 123]) {
        SharedPreferences.setMockInitialValues({
          CredentialStorageFirstSetup.pendingKey: true,
          'credential_storage_mode_v1': value,
        });
        expect(await capture(), isFalse);
      }
    },
  );

  test(
    'filesystem evidence failure is not interpreted as an empty profile',
    () async {
      expect(
        await CredentialStorageFirstSetup.capture(
          profileIsEmpty: (_) async =>
              throw FileSystemException('Synthetic failure'),
        ),
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(CredentialStorageFirstSetup.pendingKey),
        isFalse,
      );
    },
  );

  test(
    'desktop preference file is allowed only for the exact checked setup',
    () async {
      SharedPreferences.setMockInitialValues({
        CredentialStorageFirstSetup.pendingKey: true,
      });
      await support.create();
      final file = File(p.join(support.path, 'shared_preferences.json'));
      await file.writeAsString(
        jsonEncode({'flutter.${CredentialStorageFirstSetup.pendingKey}': true}),
      );
      expect(await capture(), isTrue);

      await file.writeAsString(
        jsonEncode({
          'flutter.${CredentialStorageFirstSetup.pendingKey}': true,
          'unrecognized_profile_data': 'existing',
        }),
      );
      expect(await capture(), isFalse);
    },
    skip: !(Platform.isLinux || Platform.isWindows),
  );

  group('browser vault provisioning', () {
    test(
      'empty preferences and storage create one durable pending intent',
      () async {
        final selected =
            await CredentialStorageFirstSetup.captureWebVaultCreation(
              readVaultKeys: () async => [],
            );
        expect(selected.mode, CredentialStorageMode.encryptedFile);
        expect(selected.createFileVault, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {CredentialStorageConfig.selectionKey});
        expect(
          jsonDecode(prefs.getString(CredentialStorageConfig.selectionKey)!),
          {
            'version': 3,
            'mode': 'encryptedFile',
            'customKeychainPath': null,
            'createFileVault': true,
          },
        );
      },
    );

    test('existing or ambiguous preferences never grant creation for a missing vault', () async {
      for (final values in <Map<String, Object>>[
        {'installation_id': 'existing-profile'},
        {'cloud_provider': 'filen'},
        {CredentialStorageFirstSetup.pendingKey: true},
        {'credential_storage_mode_v1': 'encryptedFile'},
        {
          CredentialStorageConfig.selectionKey: jsonEncode({
            'version': 2,
            'mode': 'encryptedFile',
            'customKeychainPath': null,
          }),
        },
      ]) {
        SharedPreferences.setMockInitialValues(values);
        final selected =
            await CredentialStorageFirstSetup.captureWebVaultCreation(
              readVaultKeys: () async => [],
            );
        expect(selected.createFileVault, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect({
          for (final key in prefs.getKeys()) key: prefs.get(key),
        }, values);
      }
    });

    test(
      'any existing storage data blocks new creation even without preferences',
      () async {
        for (final keys in [
          ['crisp_enc_salt', 'crisp_enc_verify'],
          ['crisp_enc_orphan_credential'],
          ['unrecognized.profile.data'],
        ]) {
          final selected =
              await CredentialStorageFirstSetup.captureWebVaultCreation(
                readVaultKeys: () async => keys,
              );
          expect(selected.createFileVault, isFalse);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getKeys(), isEmpty);
        }
      },
    );

    test('an interrupted authorized setup resumes despite later profile writes', () async {
      await CredentialStorageConfig.writeSelection(
        mode: CredentialStorageMode.encryptedFile,
        createFileVault: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'installation_id',
        'created-after-authorized-setup',
      );
      final selected =
          await CredentialStorageFirstSetup.captureWebVaultCreation(
            readVaultKeys: () async => throw StateError(
              'Existing intent needs no fresh-profile proof',
            ),
          );
      expect(selected.createFileVault, isTrue);
      await CredentialStorageConfig.consumeFileVaultCreation(
        expected: selected,
      );
      // An interruption after consumption, or later deletion of the vault,
      // must never turn the existing profile into a new unauthenticated vault.
      final restarted =
          await CredentialStorageFirstSetup.captureWebVaultCreation(
            readVaultKeys: () async => [],
          );
      expect(restarted.mode, CredentialStorageMode.encryptedFile);
      expect(restarted.createFileVault, isFalse);
      expect(
        prefs.getString('installation_id'),
        'created-after-authorized-setup',
      );
    });

    test('consumed creation cannot be renewed even with otherwise empty preferences', () async {
      final selected =
          await CredentialStorageFirstSetup.captureWebVaultCreation(
            readVaultKeys: () async => [],
          );
      await CredentialStorageConfig.consumeFileVaultCreation(
        expected: selected,
      );
      final restarted =
          await CredentialStorageFirstSetup.captureWebVaultCreation(
            readVaultKeys: () async => [],
          );
      expect(restarted.createFileVault, isFalse);
    });

    test(
      'unreadable browser evidence never writes creation permission',
      () async {
        await expectLater(
          CredentialStorageFirstSetup.captureWebVaultCreation(
            readVaultKeys: () async =>
                throw StateError('Synthetic unavailable browser storage'),
          ),
          throwsStateError,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), isEmpty);
      },
    );

    test(
      'profile data appearing during the evidence check prevents a grant',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final selected =
            await CredentialStorageFirstSetup.captureWebVaultCreation(
              readVaultKeys: () async {
                await prefs.setString('installation_id', 'concurrent-profile');
                return [];
              },
            );
        expect(selected.createFileVault, isFalse);
        expect(prefs.getKeys(), {'installation_id'});
        expect(prefs.getString('installation_id'), 'concurrent-profile');
      },
    );

    test(
      'malformed selection fails without being replaced by fresh setup',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(CredentialStorageConfig.selectionKey, '{bad');
        await expectLater(
          CredentialStorageFirstSetup.captureWebVaultCreation(
            readVaultKeys: () async => [],
          ),
          throwsFormatException,
        );
        expect(prefs.getString(CredentialStorageConfig.selectionKey), '{bad');
      },
    );
  });
}
