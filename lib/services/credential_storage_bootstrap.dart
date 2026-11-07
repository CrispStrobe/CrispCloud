import 'credential_storage_config.dart';
import 'secure_storage_service.dart';
import 'secure_storage_web.dart';

/// A selected backend and the gate it needs before any provider is created.
class CredentialStorageBootstrapResult {
  const CredentialStorageBootstrapResult({
    required this.storage,
    required this.mode,
    required this.requiresUnlock,
    this.createFileVault = false,
    this.consumeFileVaultCreation,
  });

  final SecureStorage storage;
  final CredentialStorageMode mode;
  final bool requiresUnlock;
  final bool createFileVault;

  /// Only a still-pending authorized creation attempt has this callback. The
  /// password gate must consume it before creating any missing vault metadata.
  final Future<void> Function()? consumeFileVaultCreation;
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
    bool createFileVault = false,
    bool createFileVaultImmediately = false,
    Future<void> Function()? consumeFileVaultCreation,
  }) async {
    if ((createFileVault || createFileVaultImmediately) &&
        mode != CredentialStorageMode.encryptedFile) {
      throw const CredentialStorageUnavailable();
    }
    if (createFileVault != (consumeFileVaultCreation != null) ||
        (createFileVaultImmediately && !createFileVault)) {
      throw const CredentialStorageUnavailable();
    }
    final SecureStorage storage;
    var requiresUnlock = false;
    var pendingCreation = createFileVault;
    switch (mode) {
      case CredentialStorageMode.systemKeychain:
        storage = await openKeychain(customKeychainPath);
        await _migrate(storage);
      case CredentialStorageMode.encryptedFile:
        if (createFileVaultImmediately) {
          // The factory may create metadata as soon as it receives the initial
          // password. Retire durable permission first; never regrant it when
          // opening, initialization or migration later fails.
          await consumeFileVaultCreation!();
          pendingCreation = false;
        }
        storage = await openFileVault();
        requiresUnlock =
            storage is! WebEncryptedStorage || !storage.isInitialized;
        // First-run creation can return an already unlocked vault. Complete
        // migration before skipping the password gate; ordinary reopen waits
        // for that gate to unlock the store before importing anything.
        if (!requiresUnlock) {
          // An already-existing unlocked vault no longer needs creation intent.
          // Retire any pending grant before exposing this profile as well.
          if (pendingCreation) {
            await consumeFileVaultCreation!();
            pendingCreation = false;
          }
          await _migrate(storage);
        }
      case CredentialStorageMode.sessionOnly:
        // No import of durable credentials or global migration marker.
        storage = InMemorySecureStorage();
    }
    return CredentialStorageBootstrapResult(
      storage: storage,
      mode: mode,
      requiresUnlock: requiresUnlock,
      createFileVault: pendingCreation,
      consumeFileVaultCreation: pendingCreation
          ? consumeFileVaultCreation
          : null,
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
