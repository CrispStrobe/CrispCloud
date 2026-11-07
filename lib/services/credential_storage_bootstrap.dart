import 'credential_storage_config.dart';
import 'secure_storage_service.dart';

/// A selected backend and the gate it needs before any provider is created.
class CredentialStorageSelection {
  const CredentialStorageSelection({
    required this.storage,
    required this.mode,
    required this.requiresUnlock,
  });

  final SecureStorage storage;
  final CredentialStorageMode mode;
  final bool requiresUnlock;
}

/// Opens only the configured backend. An unavailable store must not cause an
/// automatic fallback: another store can lack the existing app-lock policy.
/// Native factories perform their platform-specific availability checks.
class CredentialStorageBootstrap {
  CredentialStorageBootstrap({
    required this.openKeychain,
    required this.openFileVault,
    Future<void> Function(SecureStorage)? migrate,
  }) : _migrate = migrate ?? CredentialMigration.migrateIfNeeded;

  final Future<SecureStorage> Function(String? customPath) openKeychain;
  final Future<SecureStorage> Function() openFileVault;
  final Future<void> Function(SecureStorage) _migrate;

  Future<CredentialStorageSelection> open({
    required CredentialStorageMode mode,
    String? customKeychainPath,
  }) async {
    final SecureStorage storage;
    switch (mode) {
      case CredentialStorageMode.systemKeychain:
        storage = await openKeychain(customKeychainPath);
        await _migrate(storage);
      case CredentialStorageMode.encryptedFile:
        // Migrate only after the master-password gate has unlocked the vault.
        storage = await openFileVault();
      case CredentialStorageMode.sessionOnly:
        // No import of durable credentials or global migration marker.
        storage = InMemorySecureStorage();
    }
    return CredentialStorageSelection(
      storage: storage,
      mode: mode,
      requiresUnlock: mode == CredentialStorageMode.encryptedFile,
    );
  }
}

/// Intentionally does not include platform exceptions, credential contents,
/// custom paths, or other details from a failed secure-store operation.
class CredentialStorageUnavailable implements Exception {
  const CredentialStorageUnavailable();

  @override
  String toString() =>
      'The selected credential store is unavailable. Restore access or unlock '
      'it, then retry. The selected storage and existing credentials have not '
      'been changed.';
}
