# Credential storage backends

CrispCloud supports three persistence modes. The choice is made on **first
start** and can be changed in **Settings → Credentials → Credential storage**.
The choice is stored in SharedPreferences; secrets are never stored there.

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

### Choosing a keychain on macOS

The first-start and Settings chooser lists the keychains found in
`~/Library/Keychains` and `/Library/Keychains`, including the login keychain.
It also supports:

- another `.keychain-db` file via the file picker
- creating a new keychain with its own password
- the default system/data-protection keychain

The selected keychain is opened through Security.framework and made the
process default and search list. The secure-storage plugin is configured with
`useDataProtectionKeyChain: false`, so generic-password reads, writes and
deletes all resolve to that keychain. The keychain must be unlocked before the
startup probe.

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

The master password is entered at launch and is never stored. Password fields
have an eye button to reveal the text while typing. Losing the master password
means the vault cannot be recovered.

## Session-only

Credentials are kept in an `InMemorySecureStorage` instance. This is useful when
no keychain is available and the user does not want a master password, but every
restart requires reconnecting providers.

## Migration behaviour

Changing the backend in Settings does not silently copy secrets between
backends. The app asks for a restart and warns that credentials may need to be
entered again. Provider-specific legacy migration (Internxt file/preferences,
old SharedPreferences keys) still runs once the selected backend is unlocked.
