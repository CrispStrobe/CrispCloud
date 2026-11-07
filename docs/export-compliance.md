# Encryption export compliance

`ITSAppUsesNonExemptEncryption` is now `true` in both
`ios/Runner/Info.plist` and `macos/Runner/Info.plist`. That is the honest
setting for the current feature set; leaving it `false` merely avoids the
App Store Connect prompt and does not create an exemption.

This is an engineering note, not legal advice. The final classification
depends on the distributed feature set and should be confirmed with the
company's export-compliance adviser.

## What triggers the question

The shared Dart code and both mobile/desktop builds contain:

- AES-256-GCM file encryption with PBKDF2 key derivation
  (`EncryptionService`, `encrypted_storage_wrapper.dart`, GCM transfer
  streams).
- Cryptomator vault support (`CryptomatorService`): vault detection, filename
  encryption and unlock flow.
- VeraCrypt container detection/creation on mobile and desktop; the desktop
  mount path additionally invokes an external VeraCrypt CLI.
- TLS for HTTPS and standard SSH transport for the remote terminal.

TLS/SSH/authentication are commonly treated as exempt. Client-side
confidentiality encryption and Cryptomator/VeraCrypt support are the parts that
require an export-compliance answer.

## The two legitimate routes

### 1. File and keep supporting documentation (recommended)

For mass-market apps using standard algorithms (AES, PBKDF2, TLS, SSH):

- File a **BIS self-classification report** for the encryption functionality.
  The U.S. Bureau of Industry and Security (BIS) publishes the current
  self-classification report format and submission addresses
  (`crypt@bis.doc.gov` and `enc@nsa.gov`). Keep the submission confirmation.
- In App Store Connect's export-compliance questions, state that the app uses
  non-exempt encryption and provide the self-classification/CCATS reference
  when asked.
- Keep the annual reporting obligation in mind; self-classification is a
  recurring program, not a one-time checkbox.
- If the app is distributed in France, check the ANSSI declaration requirement
  separately.

A **CCATS** (Commodity Classification Automated Tracking System) is the
alternative for non-mass-market or proprietary cryptography. It is usually
slower and more expensive; a standard-algorithm file manager with optional
Cryptomator/VeraCrypt support normally starts with the mass-market
self-classification route.

### 2. Remove the non-exempt features from the App Store binary

If the product does not want to file export documentation:

- Remove the encryption/vault features from the App Store target at build time,
  not merely hide their UI. Tree-shaken code that is absent from the binary is
  the defensible version.
- Keep the direct-download build for the Cryptomator/VeraCrypt functionality.
- Re-check whether the remaining TLS/SSH use is exempt; the answer may still
  require a simple self-classification.

Using Apple CryptoKit/CommonCrypto instead of PointyCastle does **not** by
itself remove the reporting requirement. The question is what the app does with
encryption, not which library implements it.

## App Store Connect behaviour

When `ITSAppUsesNonExemptEncryption` is `true`, App Store Connect asks for
export-compliance information for the build. Upload/review can remain blocked
until that question is answered. This is expected; it is not a code-signing or
entitlement failure.

## Checklist before upload

1. Decide whether Cryptomator/VeraCrypt/client-side AES ship in the App Store
   build.
2. If they ship, obtain and retain the BIS self-classification confirmation
   (or CCATS).
3. Answer the App Store Connect export questions consistently for iOS and
   macOS, using the same distributed feature set.
4. Keep `docs/app-store-readiness.md` and the privacy manifests in sync with the
   final feature set.
5. Repeat the check whenever encryption, vault, or provider features change.

## References

- Apple: export compliance and `ITSAppUsesNonExemptEncryption`
- U.S. BIS: encryption self-classification reporting
- Cryptomator and VeraCrypt algorithm documentation
