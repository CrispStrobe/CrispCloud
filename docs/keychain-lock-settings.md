# Keychain automatic locking

On macOS, **Settings → Credentials** shows two independent switches for the
active custom file keychain:

- **Lock keychain when the Mac sleeps**
- **Lock keychain after inactivity**, with a selectable timeout when enabled

Both automatic locks default off for newly created keychains. Existing keychains
show their actual macOS policy. Changes apply immediately and macOS saves them
on that keychain, so reopening CrispCloud keeps them. They affect every app using
that file. Viewing settings never requests an unlock; an explicit Retry can ask
macOS to unlock a locked keychain. A manually locked keychain or a restart can
still require an unlock. No keychain password is retained by this feature.

The same file-scoped native bridge handles reads and writes; failures never
redirect to another keychain. Pending writes disable the controls, failed writes
are not displayed as success, and switching active stores discards stale UI
completions. All eight existing non-English settings locales include the copy.

The no-timeout value is `INT_MAX`, as specified by
[Apple's lockInterval documentation](https://developer.apple.com/documentation/security/seckeychainsettings/lockinterval).
The native getter derives timer enablement from that value because Apple's
[SecKeychain implementation](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_keychain/lib/SecKeychain.cpp)
does not populate the legacy `useLockInterval` field when copying settings.
