import 'package:shared_preferences/shared_preferences.dart';

import 'credential_storage_config.dart';

/// Conservative first-install evidence, captured before startup creates an
/// installation identity, logs, caches, or provider state. Missing new feature
/// preferences alone never establish that an older protected profile is absent.
class CredentialStorageFirstSetup {
  static const pendingKey = 'credential_storage_first_setup_pending_v1';
  static const _modeKey = 'credential_storage_mode_v1';
  static const _keychainPathKey = 'custom_keychain_path';
  static const _selectionKey = 'credential_storage_selection_v2';
  static const _migrationKey = 'secure_storage_migration_v1';
  static const _setupKeys = {
    pendingKey,
    _modeKey,
    _keychainPathKey,
    _selectionKey,
    _migrationKey,
  };

  /// Browser first use has no native directory scanner. Require both the
  /// complete preferences and localStorage inventories to be empty before
  /// recording a single creation attempt; pending v3 intents can resume.
  static Future<CredentialStorageSelection> captureWebVaultCreation({
    required Future<List<String>> Function() readVaultKeys,
  }) => CredentialStorageConfig.captureWebVaultCreation(
    readVaultKeys: readVaultKeys,
  );

  static Future<bool> capture({
    required Future<bool> Function(Map<String, Object?> setupPreferences)
    profileIsEmpty,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pending = prefs.getBool(pendingKey) == true;
      if (pending) {
        // An interrupted selection can contain only data written by this
        // pre-profile setup. Any unrelated preference makes it ambiguous.
        if (prefs.getKeys().any((key) => !_setupKeys.contains(key))) {
          return false;
        }
        final mode = prefs.getString(_modeKey);
        if (mode != null &&
            !CredentialStorageMode.values.any((value) => value.name == mode)) {
          return false;
        }
        final keychainPath = prefs.getString(_keychainPathKey);
        if (keychainPath != null &&
            (keychainPath.trim().isEmpty || keychainPath.contains('\u0000'))) {
          return false;
        }
        final selection = prefs.getString(_selectionKey);
        if (selection != null) {
          CredentialStorageConfig.decodeSelection(selection);
        }
        if (prefs.containsKey(_migrationKey) &&
            prefs.getBool(_migrationKey) != true) {
          return false;
        }
      } else if (prefs.getKeys().isNotEmpty) {
        return false;
      }
      final setupPreferences = {
        for (final key in prefs.getKeys()) key: prefs.get(key),
      };
      if (!await profileIsEmpty(setupPreferences)) return false;
      // Filesystem evidence is asynchronous. A profile or selection created
      // while it was being inspected invalidates the original empty snapshot.
      await prefs.reload();
      if (!_matchesSnapshot(prefs, setupPreferences)) return false;
      if (!pending) {
        if (!await prefs.setBool(pendingKey, true)) return false;
        await prefs.reload();
        if (!_matchesSnapshot(prefs, {...setupPreferences, pendingKey: true})) {
          return false;
        }
      }
      return true;
    } catch (_) {
      // A failed read or unverifiable marker cannot authorize another backend.
      return false;
    }
  }

  static bool _matchesSnapshot(
    SharedPreferences prefs,
    Map<String, Object?> expected,
  ) =>
      prefs.getKeys().length == expected.length &&
      expected.entries.every(
        (entry) =>
            prefs.containsKey(entry.key) && prefs.get(entry.key) == entry.value,
      );

  /// Called before any provider or initialized app profile is exposed.
  static Future<void> complete() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(pendingKey) && !await prefs.remove(pendingKey)) {
      throw StateError('Credential-storage setup could not be completed.');
    }
    await prefs.reload();
    if (prefs.containsKey(pendingKey)) {
      throw StateError('Credential-storage setup could not be completed.');
    }
  }
}
