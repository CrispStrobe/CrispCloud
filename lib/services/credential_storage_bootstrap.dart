import 'credential_storage_config.dart';
import 'secure_storage_service.dart';
import 'secure_storage_web.dart';

/// A selected backend and the gate it needs before any provider is created.
class CredentialStorageBootstrapResult {
  const CredentialStorageBootstrapResult({
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

  Future<CredentialStorageBootstrapResult> open({
    required CredentialStorageMode mode,
    String? customKeychainPath,
  }) async {
    final SecureStorage storage;
    var requiresUnlock = false;
    switch (mode) {
      case CredentialStorageMode.systemKeychain:
        storage = await openKeychain(customKeychainPath);
        await _migrate(storage);
      case CredentialStorageMode.encryptedFile:
        storage = await openFileVault();
        requiresUnlock =
            storage is! WebEncryptedStorage || !storage.isInitialized;
        // First-run creation can return an already unlocked vault. Complete
        // migration before skipping the password gate; ordinary reopen waits
        // for that gate to unlock the store before importing anything.
        if (!requiresUnlock) await _migrate(storage);
      case CredentialStorageMode.sessionOnly:
        // No import of durable credentials or global migration marker.
        storage = InMemorySecureStorage();
    }
    return CredentialStorageBootstrapResult(
      storage: storage,
      mode: mode,
      requiresUnlock: requiresUnlock,
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
      'it, then retry.';
}
