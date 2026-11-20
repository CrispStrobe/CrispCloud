# Window lifecycle and local signing acceptance

The App Lock resume check replaced the browser with a checking scaffold, disposing its local scroll and focus state. CredentialContentGate now mounts the workspace after authorization and retains it behind a non-interactive security cover. The previous background timestamp is consumed once. Lock and failure paths remain closed to input; private notifications cannot move onto the security cover.

The attached Mac run passes 18 tests: three actual AppLockGate lifecycle cases, three content-gate cases, six credential diagnostics, and six notification policy cases. Repeated hidden/resumed, inactive/resumed, geometry changes, timeout locking, storage failure, focus restoration, selection and scroll are covered. A negative control using the original scaffold replacement failed because the workspace was disposed.

The unreadable notification footer merged the surface text color into an inverse-surface snackbar. Only the compact font size is now overridden. Both light and dark theme contrast tests pass.

Local builds now use the stable certificate/team/bundle signing wrapper. A disposable synthetic-keychain experiment confirmed a changed executable signed with the stable requirement can read the first executable’s item without interaction; a changed ad hoc executable was denied. No user credential entries or keychain locking settings were changed. Six build-wrapper tests pass.

This evidence precedes the new integrated binary; its separate build receipt records the exact Office pin and executable.

Folder grants now remain active for the whole application session and reuse each resolved native URL across listing, metadata probes, F3 and F4. Resolving a fresh native URL for the same path previously replaced the plugin's cached URL while other operations could still hold it. Bookmark operations and persistence updates are serialized, including concurrent grants; transient resolution failures retain the saved data. Removing/clearing grants releases session holds. Concurrent stream readers retain their batch scopes until the last reader finishes, balancing all acquisitions rather than overwriting one shared slot.

26 Mac bookmark/local-file/symlink tests and a separate concurrent-stream regression pass. The new session-specific controls are explicitly macOS-only. No OS privacy database or credential ACL was changed. Stable signing addresses rebuild identity; session scopes address access across features.
