# ADR 006: Secure Credential Storage

**Status**: Accepted

---

## Context

CrispCloud stores credentials for up to 11 cloud providers per user: email addresses, passwords, OAuth2 access and refresh tokens, S3 access keys, SFTP private key paths, and encryption passphrases. These credentials provide full access to users' cloud storage. Storing them insecurely is a critical vulnerability.

The original implementation used `SharedPreferences` to store credentials as plaintext key-value pairs. On Android, `SharedPreferences` writes to a world-readable (in some contexts) XML file in the app's data directory. On macOS and Windows, it writes to plaintext preference files that any process running as the same user can read. This is unacceptable for security-sensitive data.

We needed:
1. **Encrypted at rest**: credentials encrypted using OS-managed keys that are not accessible to other processes.
2. **Cross-platform**: works on macOS, Windows, Linux, Android, iOS, and Web.
3. **Test-friendly**: a test double that behaves identically but does not touch the OS keychain.
4. **Migratable**: existing users on `SharedPreferences` can be migrated without re-entering credentials.

---

## Decision

### Native Platforms: `flutter_secure_storage`

On all native platforms, credentials are stored using `flutter_secure_storage` (`pub.dev/packages/flutter_secure_storage`), which maps to:

| Platform | Backend |
|----------|---------|
| macOS | Keychain (kSecClassGenericPassword) |
| iOS | Keychain (kSecClassGenericPassword) |
| Android | Android Keystore + EncryptedSharedPreferences |
| Windows | Windows Credential Manager (DPAPI-encrypted) |
| Linux | libsecret (GNOME Keyring or KDE Wallet via the Secret Service API) |

Each credential is stored as a named item in the OS keychain, scoped to the CrispCloud app bundle identifier. Other processes cannot read these values even as the same OS user.

### Web: Encrypted localStorage

`flutter_secure_storage` does not support Web — there is no OS keychain in a browser. We implement a custom `WebEncryptedStorage` class that:

1. Prompts the user for a master password on first launch.
2. Derives a 256-bit AES-GCM key from the master password using PBKDF2-HMAC-SHA256 (100,000 iterations) and a random salt stored in `localStorage`.
3. Encrypts all credential values with AES-256-GCM before writing them to `localStorage`.
4. Decrypts on read using the same derived key.
5. Holds the derived key in JavaScript memory only; it is not persisted.

This means a web session requires the master password on each app load. The master password is never stored.

### `SecureStorage` Abstraction

To avoid scattering `flutter_secure_storage` calls throughout the codebase and to enable testing, all credential access goes through a `SecureStorage` abstract interface:

```dart
abstract class SecureStorage {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
  Future<Map<String, String>> readAll();
  Future<void> deleteAll();
}
```

Production code uses `FlutterSecureStorageAdapter` (which wraps `flutter_secure_storage`) on native and `WebEncryptedStorage` on Web. Tests use `InMemorySecureStorage` — a plain `Map<String, String>` in memory with no platform channel calls.

### Biometric Unlock

The master password / passphrase can optionally be unlocked via biometric authentication (Face ID, Touch ID, fingerprint) using the `local_auth` package. When enabled:
- The passphrase is stored in the OS keychain (protected by biometric policy).
- On app resume after lock, `local_auth.authenticate()` is called.
- On success, the passphrase is read from the keychain and used to derive keys.
- On failure, the manual entry form is shown.

This means users do not need to re-type a long passphrase on every app open, while the credential is still protected by the device's secure enclave.

### Migration from SharedPreferences

`CredentialMigration.migrateIfNeeded()` is called at app startup. It:
1. Reads all known credential keys from `SharedPreferences`.
2. If any are found (legacy install), writes them to `SecureStorage` and deletes them from `SharedPreferences`.
3. Records a migration flag in `SharedPreferences` to prevent re-running.

The migration is idempotent: running it multiple times on the same installation is a no-op.

---

## Consequences

**Positive:**

- Credentials at rest are encrypted using OS-managed keys tied to the app's identity. Extracting them requires either root access or breaking the OS keychain implementation.
- The `SecureStorage` abstraction means every config service, adapter, and test uses the same interface. Swapping the backend (e.g., to a hardware-backed key store) requires changing only the concrete implementation.
- `InMemorySecureStorage` makes all 55+ test files fast and hermetic. Tests do not touch the OS keychain, do not require device pairing, and run on any CI host.
- The migration path ensures existing users are not required to reconnect all providers after upgrading from the `SharedPreferences` version.

**Negative / Trade-offs:**

- On Linux with no Secret Service daemon running (headless servers, minimal environments), `flutter_secure_storage` falls back to writing an encrypted file using a machine-derived key — less secure than a user-session keychain but still encrypted at rest.
- The Web encrypted localStorage implementation relies on the user's master password. If the user forgets the master password, all credentials stored in the browser are irrecoverable.
- Biometric unlock on Windows uses Windows Hello, which requires hardware TPM. Devices without TPM cannot use biometric unlock.
- The `local_auth` package requires additional platform-specific configuration (entitlements on iOS, activity result handling on Android, Windows Hello SDK linkage) that adds build complexity.
- Auto-login at startup retrieves the OAuth2 refresh token from the keychain and attempts a token refresh. If the OS keychain is locked (e.g., the user just booted and has not logged in to the keychain), the read fails and the user must reconnect manually. This is a known behavior on macOS with "first unlock" keychain policies.
