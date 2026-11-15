# Public macOS and Android signing

GitHub binaries use the existing signing identities; this work does not create
or revoke a production certificate or replace an Android key. The setup follows
the account's local `appstore.md` signing playbook and CrispSorter's inside-out
Developer ID signing/notarization workflow. App Store signing remains separate.
Windows signing is pending.

## macOS GitHub app and DMG

The public Release workflow now requires:

- `MACOS_DEVELOPER_ID_P12_BASE64`, `MACOS_DEVELOPER_ID_P12_PASSWORD`,
  `MACOS_DEVELOPER_ID_SHA1`.
- `MACOS_DEVELOPER_ID_PROFILE_BASE64` and
  `MACOS_DEVELOPER_ID_FINDEREXT_PROFILE_BASE64` for the app and Finder extension.
- Existing `ASC_API_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_TEAM_ID`
  for notarization.

These secrets are configured. The retained Developer ID Application certificate
is `6C20CDED5C54E9E7B7A2871DEBD1EEF1AF966D4D`, team `N9XSJ4M3GT`, with certificate
expiry 2027-02-01. Both new `MAC_APP_DIRECT` profiles authorize that certificate
and the existing bundle identifiers. Keeping the application identifier in the
signature matters for Data Protection Keychain access; using an ad-hoc signature
or the App Store distribution identity for direct downloads is not a substitute.

`tool/macos_public_signing.py prepare` validates the profiles, imports the existing
identity into a temporary restricted keychain, and checks notarization access
before the app build. Temporary credentials are removed by an always-run cleanup
step. Search-list cleanup removes only its own entry and preserves other work.
Errors do not print private-key payloads or password-bearing command arguments.

The signer signs Mach-O code inside-out with secure timestamps and hardened
runtime. It preserves the FUSE helper's scoped loader entitlement, retains the
Finder extension's sandbox, embeds each correct profile and supplies each
application identifier. It checks the final signed GitHub profile, notarizes and
staples the app, and then packages that app into the ZIP and DMG. The DMG is
signed, notarized and stapled separately. Gatekeeper acceptance is checked.
Notarization receipts are retained with the release assets.

## Standalone macOS CLI

Published macOS CLI archives use the same retained Developer ID certificate and
notarization key. PR/compile-only artifacts do not receive signing credentials.
Each native library is signed, and the signed CLI is exercised from an extracted
ZIP before notarization/publication. The archive's acceptance receipt is retained.
ZIPs/standalone tools cannot be stapled, so this route uses Apple's online ticket
rather than claiming an attached offline ticket.

Pinned Dart 3.13.7 AOT executables need
`com.apple.security.cs.allow-unsigned-executable-memory` when hardened runtime
is enabled: the native probe otherwise passed signature verification and
notarization but was killed when executing snapshot code. MAP_JIT permission
and disabling library validation did not fix that case. The exception is scoped
to the Dart CLI entrypoint through `macos/Runner/Cli.entitlements`; it is not
applied to libraries, the GUI host or App Store apps. Store verification rejects
that entitlement. See [Apple's hardened runtime settings](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime).

## Android

CrispCloud keeps its existing per-app `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`. Other
apps' Android keys are not substituted. The Gradle release variant no longer
falls back to a debug key when signing configuration is absent.

`android/release-signing-cert.sha256` records the certificate published with
[CrispCloud v1.2.8](https://github.com/CrispStrobe/CrispCloud/releases/download/v1.2.8/crispcloud-android-signing-cert.sha256.txt).
Release, repair and nightly workflows export the configured alias's public
certificate and compare it with that historical identity before building.
`tool/verify_android_signing.py` then verifies the APK and requires its exact
signer to match, rejecting debug, missing, multiple or changed signers. The
public SHA-256 accompanies published APKs. A future intentional key rotation
requires a separate reviewed update/migration; it is not inferred automatically.
Google Play may use its separate Play App Signing key for delivered APKs; the
upload key alone does not guarantee cross-channel update compatibility.

PR CI builds explicitly labelled debug APKs without production signing secrets.
Nightly release APKs retain the real update key. Windows signing remains pending.

## Observed acceptance and limits

- 13 focused signing controls passed, including profile identity/expiry, password
  redaction, search-list preservation, exact Android signer and key substitution.
- Real Developer ID native app: temporary Data Protection Keychain create/read/
  delete passed. No existing credential values were read or changed.
- The actual universal FUSE helper and a native Finder-extension stub were signed. Apple accepted
  the native probe's app ZIP and DMG; stapling and Gatekeeper acceptance passed.
- A real Dart AOT executable using FFI passed signed execution, archive extraction
  and notarization with the CLI-only runtime exception.
- An actual generated APK passed the expected signer/pin check and rejected an
  unrelated public certificate. Production Android signing material was unchanged.

These are native acceptance fixtures, not a claim that a newly built complete
CrispCloud application or all hosted platform jobs have passed. Evidence is in
[evidence/public-signing-20261115.json](evidence/public-signing-20261115.json).
The optional local `tool/macos_public_signing_live_probe.py` reruns the native
app probe after preparing its environment; it needs an unlocked macOS session.

Existing tags, including queued `v1.3.4` builds, retain their original recipes.
This signing pipeline applies to subsequent builds of this source.
