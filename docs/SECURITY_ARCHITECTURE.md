# Security architecture

## Security goals

CrispCloud is a local file manager. It should send file content and credentials
only to the storage endpoint selected by the user. A compromised cloud account
must not automatically reveal files protected with CrispCloud's optional
client-side encryption. A crash report must not disclose credentials, local
paths, remote object paths, or URL query secrets.

## Trust boundaries

- The Flutter process and platform secure store are trusted on an uncompromised
  device.
- Cloud providers, OAuth pages, configured FTP/SFTP/WebDAV hosts, and optional
  plugins are external trust boundaries.
- File previews and archives are untrusted input. They must remain within the
  application sandbox and configured extraction limits.
- The local automation API is disabled unless configured and requires its
  authentication token.

## Credentials

Native builds store secrets with `flutter_secure_storage`, backed by Keychain,
Keystore, libsecret, or Windows credential protection. Profiles contain
non-secret connection metadata separately. Secrets must never be written to
ordinary preferences, logs, audit events, transfer history, or crash reports.

Web storage cannot provide the same operating-system boundary. Users should
treat the browser profile as part of the trusted computing base and avoid
shared browser profiles.

## File encryption

Optional file encryption uses AES-256-GCM, which provides confidentiality and
integrity. Each encrypted object needs a unique nonce. Native acceleration is
platform-specific; macOS uses the bundled CryptoKit integration. Sandboxed
macOS releases must never dynamically load Homebrew or `/usr/local` OpenSSL.
The regression test in `test/native_ffi_crypto_test.dart` and the launch smoke
test in `tool/macos_startup_smoke.sh` enforce this release invariant.

Encryption does not hide provider-visible metadata such as object size,
transfer timing, or the account being used. Sharing encrypted provider objects
directly is disabled because recipients would receive ciphertext.

## Diagnostics and privacy

Crash diagnostics are local and opt-in. Global Flutter and platform errors are
captured only after values are sanitized. Credential-like keys, filesystem path
fields, home-directory prefixes, and secret query parameters are redacted.
Reports are bounded to the latest 200 entries and can be inspected, copied, or
cleared in the app. No remote telemetry backend is enabled by default.

The audit log records application actions, not file contents or credentials.
Debug logging must follow the same rule.

## macOS distribution

App Store and TestFlight builds run with App Sandbox. Native libraries must be
embedded and signed inside the app bundle. CI launches the release bundle and
fails on early exit, unsafe `libcrypto` loading, selector failures, or aborts.
Release signing and notarization must preserve the entitlements committed under
`macos/Runner`.

## Dependency controls

CI exports the resolved Dart dependency graph as a build artifact and reports
outdated packages. Git and vendored dependencies require the same review as
first-party code. The local `filen_client` patch is intentionally narrow and
must be removed once its macOS sandbox fix is available upstream.

## Non-goals

CrispCloud cannot protect an unlocked device from malware, recover a compromised
provider account, guarantee provider availability, or make FTP secure. Use SFTP
or FTPS when transport confidentiality is required.
