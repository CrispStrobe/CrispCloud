# Credential storage backends

CrispCloud supports three persistence modes, selectable in
**Settings → Credentials → Credential storage**. The choice is stored in
SharedPreferences; secrets are never stored there.

| Mode | Where secrets live | Survives restart | Requires OS keychain |
| --- | --- | --- | --- |
| System keychain | macOS/iOS Keychain, Android Keystore, Windows Credential Manager, libsecret | Yes | Yes |
| Encrypted file | `credential-vault.json` in the app support directory, AES-256-GCM with a PBKDF2 key from a master password | Yes, after entering the master password | No |
| This session only | Process memory | No | No |

## System keychain

`PlatformSecureStorage` uses `flutter_secure_storage`. On macOS, the default is
the data-protection keychain. If startup probing fails — locked login keychain,
missing keychain service, sandbox denial — the app automatically switches to the
encrypted file vault, shows the master-password gate, and records that fallback
mode so credentials do not disappear on the next launch.

### Custom keychain on macOS

A non-default keychain path (for example a dedicated Brickwright keychain) can
be entered in Settings. On the next launch, `AppDelegate` opens that keychain
and makes it the process default before Flutter starts. The secure-storage
plugin is then configured with `useDataProtectionKeyChain: false`, so its
generic-password items use the selected keychain.

The keychain must be unlocked (for example in Keychain Access) before the
startup probe. If it cannot be opened or written, the app falls back to the
encrypted file vault rather than failing every credential operation.

## Encrypted file vault

`EncryptedFileStorage` reuses the same AES-256-GCM/PBKDF2 vault format as the
web vault:

- PBKDF2-HMAC-SHA256, 600,000 iterations for new vaults
- non-extractable WebCrypto key on the web; native CryptoKit/OpenSSL/CNG
  provider on native
- ciphertext only in the file
- file mode `0600`
- unencrypted salt, iteration count and verification token only

The master password is entered at launch and is never stored. Losing it means
the vault cannot be recovered.

## Session-only

Credentials are kept in an `InMemorySecureStorage` instance. This is useful when
no keychain is available and the user does not want a master password, but every
restart requires reconnecting providers.

## Migration behaviour

Changing the backend in Settings does not silently copy secrets between
backends. The app asks for a restart and warns that credentials may need to be
entered again. Provider-specific legacy migration (Internxt file/preferences,
old SharedPreferences keys) still runs once the selected backend is unlocked.
