# Credential storage backends

Review date: **2026-11-07**. This describes the integrated PR26 implementation,
including first-run setup and scoped macOS keychain creation. It does not change
provider encryption protocols or determine export classification; the conditional
release analysis remains in [export-compliance.md](export-compliance.md).

| Native mode | Persistence and protection | Availability after restart |
| --- | --- | --- |
| System keychain | `flutter_secure_storage` with platform credential protection; macOS defaults to the data-protection keychain | Subject to OS availability, unlock state and access controls |
| Custom macOS keychain, within system-keychain mode | Explicitly selected file keychain through `Security.framework`, under a CrispCloud-specific service | The selected file must remain accessible and unlocked |
| Encrypted file | `credential-vault.json` in application support; AES-256-GCM values and a password-derived key | Requires foreground master-password entry |
| This session only | `InMemorySecureStorage`; this backend does not persist credentials | Sign in again for each new session |

Filen and Internxt use the selected host storage in each mode. Browser builds
continue to use the encrypted browser vault, without the native backend chooser.

## Startup and changing stores

A verified fresh profile gets the first-run chooser. Missing the new preference
alone is insufficient: `CredentialStorageFirstSetup` checks preferences, the
native support directory and legacy configuration, and validates interrupted
setup. Ambiguous or unreadable profile state does not authorize a new backend.
These local installation checks do not protect against a local user deliberately
replacing application data.

An existing profile opens its configured store. Failure shows a retry screen;
there is **no automatic fallback** to another keychain, an empty vault or memory.
Unreadable vault metadata or App Lock policy is an error, not an empty profile
or a disabled lock. Otherwise, changing stores could bypass the old store's
policy and hide saved credentials.

**Settings → Credentials → Credential storage** saves a pending next-launch
choice. The running application continues using its active store until restart.
Mode and custom path are written as one versioned preference record, reloaded
and verified before success is reported. App Lock must be disabled to change
stores; its state is checked both before and after the chooser. A policy-read
error blocks the change. Re-enable App Lock after restarting with the intended
persistent store. Session-only storage cannot enable persistent App Lock.

Changing backends does not copy or delete the previous store's credentials.
Reconnect if the destination does not already contain that account. Selection
preferences contain mode/path information, not passwords or provider secrets.

## System and custom keychains

The default OS option retains `PlatformSecureStorage` and its existing plugin
configuration. On macOS it leaves the custom path unset and uses the
data-protection keychain. It does not select the file-based login keychain as a
substitute.

`MacOsCustomKeychainStorage` uses a separate native adapter. Reads, updates,
enumeration and deletion explicitly supply the selected keychain through
`kSecMatchSearchList`; insertion supplies `kSecUseKeychain`. Initialization
probes a unique temporary item in that same file. Missing, locked, inaccessible
or invalid files fail explicitly, without retrying in the default keychain.

The custom service is **`com.crispcloud.credentials.v1`**. File keychains use
their own ACL model, not the data-protection keychain's app access group
isolation. The service name scopes queries; it is not itself an OS security
boundary. `readAll`/`deleteAll` affect only this service in the selected file.
Experimental PR26 entries under `flutter_secure_storage_service` and entries
under other services remain untouched. No automatic import or deletion of that
generic namespace occurs; reconnect if needed. The default OS namespace is
unchanged.

Listing files is read-only discovery and grants no sandbox access. **Browse**
uses `NSOpenPanel` and retains a path-keyed security-scoped bookmark; native
operations acquire/release that access. Invalid bookmarks fail explicitly.
Manual paths work only with existing permission. App Store builds generally
need Browse and the saved bookmark for an external file; OS ACL and filesystem
denials still apply.

**Create a new keychain** uses `NSSavePanel`, passes the exact password to
`SecKeychainCreate`, checks unlock success, probes the returned keychain and
bookmarks its actual path. New save-panel files use `.keychain-db` to avoid an
upgraded sibling outside the selected file permission. Creation refuses occupied
destinations, symlinks, corresponding `.keychain`/`.keychain-db` aliases and
reserved login/System paths. Neither creation nor selection calls
`SecKeychainSetDefault` or `SecKeychainSetSearchList`. Cancelling returns no
selection. Browsing/creating alone does not save the app's mode/path. If a later
probe/bookmark operation fails after creation, the new file is retained rather
than deleted as error recovery.

## Encrypted file and browser vaults

`EncryptedFileStorage` shares the `WebEncryptedStorage` credential codec:

- AES-256-GCM, with a fresh 12-byte nonce and a 16-byte authentication tag.
  Native encryption uses the available reviewed provider; browser encryption
  uses WebCrypto. Native keys can exist in application memory. A browser
  non-extractable key does not protect against malicious code running inside
  the unlocked application.
- PBKDF2-HMAC-SHA256 with a 16-byte random salt and 600,000 iterations for new
  vaults. Complete legacy salt/verification records without an iteration field
  keep their 100,000-iteration interpretation. Explicit stored counts must be
  positive and at most 2,000,000; this compatibility range is not a password
  strength guarantee for every accepted legacy value.
- New `v2:` credential writes authenticate an encrypted envelope containing the
  storage key and value. Moving its ciphertext to another key is rejected.
  An encrypted binary marker prevents stripping `v2:` to reinterpret the value
  as legacy UTF-8. Existing legacy values remain readable and gain key binding
  when rewritten; unlocking alone does not rewrite all entries.

Storage-key names, value sizes, salt, iteration count, record version markers
and the encrypted verification token remain visible. Secret values are encrypted.
This is not whole-vault rollback protection or authenticated membership of
every entry: entry deletion and restoring old valid state remain possible, and
legacy values lack key binding.

Missing/malformed metadata, an incorrect password, failed authentication,
unsupported work factors and generation changes are errors. They do not reset
the vault or report a damaged credential as absent. A failed unlock leaves the
handle locked. The gate verifies that new/existing state still matches its
inspection before initializing. Passwords are not trimmed or persisted; reveal
controls affect display only. This backend has no password-recovery mechanism.

### Native file transactions

Each operation reloads committed state under an OS lock. Local serialization
and POSIX `flock`/Windows handle locks prevent cooperating instances and isolates
from overwriting each other's transactions. Cross-isolate/process contention
fails explicitly and can be retried. The persistent empty `.lock` file must not
be unlinked during normal use.

Writes stage the complete JSON in a private directory on the same filesystem,
flush it, and atomically replace the destination without deleting the old file
first. POSIX staging directories/files use `0700`/`0600` before ciphertext is
written; published files and locks use `0600`. Windows inherits application-data
ACLs. Vault/lock symlinks and POSIX parents writable by other users are refused.
Empty, truncated or malformed existing files are preserved as corruption. File
vaults have a 16 MiB limit.

A failed action/replacement preserves the previous committed vault. A directory
sync error after replacement reports that replacement already happened; inspect
or retry the existing file rather than assuming no change occurred. Interrupted
writes can leave private encrypted staging files. This does not defeat
filesystem/device failure or another process with the same user's access to
application directories/memory. Browser `localStorage` does not gain these
native transaction guarantees across tabs.

## Session-only and migration

`InMemorySecureStorage.isPersistent` is false. Generic credential migration and
Internxt legacy handling therefore do not import saved logins, delete durable
legacy entries or mark persistent migration complete for session-only mode.
Session logout leaves prior stores intact. This is not an incognito mode for
preferences, caches, downloaded files or sync state.

Persistent migration preserves a different existing secure value and reads
back a matching secure copy before deleting a legacy preference. Failed writes
or cleanup are reported. Internxt retains its logout tombstone against failed
legacy deletion. These provider-specific migrations are distinct from copying
accounts between newly selected backends.

## Foreground and background limits

A file vault requires foreground master-password entry; that password is not
saved for unattended unlock. A separate worker cannot reuse session memory.
The mobile background client builder refuses encrypted-file/session-only modes
instead of reading stale credentials left in the system keychain. Its existing
supported providers are FTP/FTPS and WebDAV; this change does not add unattended
Filen or Internxt sync. Both required providers remain available in the
foreground once the selected store is ready.

## Validation and references

Focused regressions are in the secure-storage, bootstrap, first-setup, chooser,
Internxt, App Lock and master-password-gate tests. In particular,
`test/native/custom_keychain_store_test.swift` uses temporary keychains to check
creation, scoped CRUD, collisions, foreign-service preservation, locked/missing
paths and unchanged user preferences. Consult CI for the exact tested revision.
This helper test does not establish interactive bookmark behavior in every
signed sandbox environment or live provider login behavior.

- [Apple: keychain implementations (TN3137)](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).
- [Apple: macOS App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- [Apple Security source: private-keychain search-list behavior](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/StorageManager.cpp).
