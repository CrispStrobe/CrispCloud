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

The failure screen also offers **Choose another credential store…**. It is
never taken automatically: a warning explains that the unavailable store's
saved sign-ins and App Lock are neither used nor deleted, and only after the
user confirms does the chooser open. The choice is written like an
authenticated Settings switch (an encrypted file vault is created only through
the password gate, and only when leaving another mode; an existing vault keeps
its own password and App Lock) and startup retries with it. The new store
starts without the old credentials or App Lock: reconnect accounts and enable
App Lock again, or switch back in Settings once the original store works. This
is a deliberate trade-off: the old store's secrets stay unreadable, while a
local user who can run the app could already reset the profile by deleting its
data (see the fresh-profile caveat above).

For a configured custom macOS keychain, **Restore keychain access**
opens a permission picker for that same existing file. Native validation checks
its canonical path and readable file/volume identities before saving a new
bookmark under the original configured path. A different or missing file is
rejected; restore a moved file to its original location first. Cancellation does
not change the selection or bookmarks. Recovery rechecks the configured
selection before and after the picker, then retries the original store and its
App Lock policy. It cannot select a replacement store, create a new vault or
disable a lock. Default OS stores use their normal OS unlock/repair controls
followed by **Retry**.

**Settings → Credentials → Credential storage** saves a pending next-launch
choice. The running application continues using its active store until restart.
Mode, custom path and any explicit vault-creation intent are written as one
versioned preference record, reloaded and verified before success is reported.
App Lock must be disabled to change
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

### Creation requires explicit authorization

A missing vault in an existing profile blocks startup. It does not authorize
creating an empty replacement that could omit the original App Lock policy.
Native first-run setup can authorize creation after its fresh-profile checks.
An authenticated Settings switch from another storage mode can authorize one
pending encrypted-file creation attempt; creation is deferred until the next
launch. Selecting the already configured encrypted-file mode, or cancelling a
pending switch to return to the currently active file vault, does not grant
replacement permission. Browser first setup records creation intent only when
both the profile preferences and browser storage are empty, checked before
startup writes identity, settings or caches.

Selection format version 3 adds the Boolean `createFileVault` under the same
preference key used for version 2. Existing version-2 selections remain
readable and imply `false`; upgrading or finding a missing file does not grant
permission. A pending grant is bound to the inspected selection. Before any
initialization that can create vault metadata, the code verifies that this
selection still matches, writes the grant as `false` and verifies the persisted
result. Native first-run creation consumes it before invoking the factory;
deferred creation consumes it in the password gate. An existing vault also
retires any outstanding grant before its unlock or exposure to the application.

Older PR26 builds that accept only version 2 cannot read the new selection
record. They reject it instead of falling back to stale legacy preferences.
Keep the updated build after saving version-3 settings; do not delete or edit
selection metadata as a shortcut around a credential-store or App Lock failure.

A stale, already consumed, failed or unverified grant cannot authorize creation.
Creation failure never restores the grant. An interruption after consumption
but before vault publication can therefore leave startup blocked even though
no vault was created. Recovery can require restoring the vault or an authorized
return to the previous backend; retrying startup does not silently issue a new
creation grant. An intent that has not yet been consumed can survive a restart.

These preference checks serialize operations within one isolate and verify
readback. They are not an atomic compare-and-swap across processes or browser
tabs, and they do not authenticate preferences against a local attacker who
can replace the profile. The native vault's separate file transaction controls
its data writes.

### Credential encryption

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
Filen/Internxt legacy handling therefore do not import saved logins, delete
durable legacy entries or mark persistent migration complete for session-only
mode.
Session logout leaves prior stores intact. This is not an incognito mode for
preferences, caches, downloaded files or sync state.

Persistent migration preserves a different existing secure value and reads
back a matching secure copy before deleting a legacy preference. Failed writes
or cleanup are reported. Internxt retains its logout tombstone against failed
legacy deletion. These provider-specific migrations are distinct from copying
accounts between newly selected backends.

Filen's production SDK client receives an adapter to the same selected host
store. It does not use the SDK's default credential file or create CLI storage
directories. Credential writes verify the exact saved bytes before persistent
mode removes an old `credentials.json` file. Session mode leaves that file
untouched. Native cleanup accepts only a regular file in the expected directory;
unexpected links, directories and access errors are failures, not successful
deletion. Browser builds use a separate no-filesystem cleanup implementation.
Unreadable records and unverifiable saves report fixed, non-sensitive errors
instead of appearing to be an absent login or a successful save.

Filen logout discards its in-memory API key and master keys, then verifies
removal of saved credentials. Persistent mode removes retained legacy
preferences and the old SDK credential file before the secure entry so an old
login cannot migrate back after successful logout; session-only mode leaves
those durable sources untouched. Cleanup failure is shown in the logout dialog
with a retry action and is not
reported as successful logout. The disconnected adapter remains available for
that retry (`test/filen_adapter_test.dart`).

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
Filen/Internxt, App Lock and master-password-gate tests.
`test/credential_storage_recovery_test.dart` checks the immutable configured
selection, cancellation, concurrent preference changes and sanitized errors.
Config/bootstrap regressions check version-2 compatibility, strict consumption,
failed readback, stale attempts, consumption before the creator and preservation
of a consumed state after creation failure. Password-gate and Settings tests
exercise the fresh/existing-profile boundary and deferred creation.
The macOS bridge tests check the restricted method arguments and explicit
failure replies. In particular,
`test/native/custom_keychain_store_test.swift` uses temporary keychains to check
creation, scoped CRUD, collisions, foreign-service preservation, locked/missing
paths, same-file recovery validation and unchanged user preferences. Filen
config/adapter tests cover verified writes and cleanup failures; its focused
browser test covers the injected SDK store without native filesystem access.
Consult CI for the exact tested revision.
This helper test does not establish interactive bookmark behavior in every
signed sandbox environment or live provider login behavior.

- [Apple: keychain implementations (TN3137)](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).
- [Apple: macOS App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- [Apple Security source: private-keychain search-list behavior](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/StorageManager.cpp).

## Startup and unlock failure recovery

Startup verifies the selected backend and reads the existing App Lock policy
before exposing the file browser. The unlock and resume gates use the same
recovery screen if a later read fails. A failed policy read never disables App
Lock or creates a replacement vault.

Recovery identifies the active backend and the selected keychain or vault's
absolute path. OS-managed backends identify their service; a physical pathname
is shown only when the backend exposes one. Diagnostics retain the failed
operation, native error code/OSStatus, and original Dart stack trace. The details
can be selected and copied; credential values and native query payloads are
excluded. These reports contain local paths, so review them before sharing.

Retry keeps the current store. On macOS, Restore keychain access grants access
to the same selected file. Choose another credential store is also available
from policy and vault failures: after an explicit confirmation, choose an OS
store, an encrypted file vault, or memory for this session. The original store
and its saved sign-ins and App Lock policy remain intact. A persistent vault
still requires its own master password; an existing vault is never overwritten
to recover access. Session mode imports no persistent credentials.

The macOS startup smoke test waits for credential preflight, an authorized vault
unlock screen, or verified first-run setup. Rendering the application shell by
itself no longer qualifies as a successful launch.

### Saved file permission and keychain unlock are separate

A custom-keychain file grant is retained as a security-scoped bookmark. Locking
the encrypted keychain, including macOS lock-on-sleep, does not erase that grant.
CrispCloud now requests Security.framework's own unlock dialog when the selected
file is locked, then retries the same operation once. The password stays inside
macOS. Concurrent reads share the request; cancellation preserves the selection
and suppresses further automatic prompts until an explicit Retry.

The app does not change the keychain's sleep/timeout policy, default keychain or
search list. A file picker is offered only for an actual missing file-access
grant. Missing files, permission errors inside the keychain and cancelled unlocks
retain their native diagnostics instead of being misclassified as a new grant.
During resume, the protected browser remains covered until its policy is read.
