# Filen client source provenance

## Published source

- Package: [`filen_client` 0.2.2](https://pub.dev/packages/filen_client/versions/0.2.2).
- Upstream repository: <https://github.com/CrispStrobe/filen-dart>.
- Exact published source archive:
  <https://pub.dev/api/archives/filen_client-0.2.2.tar.gz>.
- Archive SHA-256:
  `89823f6add3a86aeafee8bc942de43544431ed21faa6cc851a4d6758a0473b05`.
- License: Mozilla Public License 2.0. The checked-in `LICENSE` is byte-for-byte
  identical to the published archive's license.

The archive is the versioned upstream reference; the repository's moving
`main` branch is not a substitute. CrispCloud uses this directory as a path
dependency and publishes its local changes in the same public repository as
the application. No private implementation of the Filen encryption protocol is
needed to build this dependency.

## Local changes

Compared on 7 November 2026 against the published archive, with CrispCloud
baseline `c1dc32161ed5a429c356c06e930966954faa4fbf`:

| File | Change from 0.2.2 | Reason |
| --- | --- | --- |
| `lib/openssl_aesgcm.dart` | Return an empty OpenSSL candidate list on macOS. | Avoid probing Homebrew libraries from a signed sandboxed app. The AES-GCM wire format is unchanged. |
| `lib/drive.dart` | Preserve leading and trailing whitespace in remote paths. | Whitespace is part of a Filen filename. |
| `lib/config.dart` | Replace the `chmod` subprocess with `chmodPath`. | Set POSIX permissions without launching a helper executable. |
| `lib/posix_chmod.dart`, `lib/posix_chmod_io.dart`, `lib/posix_chmod_stub.dart` | Add a conditional libc binding and a non-FFI stub. | Keep native permission handling compatible with sandboxed and web builds. |
| `lib/memory_gate.dart` | Stop invoking `vm_stat` on macOS. | Retain the fixed transfer byte budget without a subprocess. |
| `pubspec.yaml` | Add `publish_to: none` and a final newline. | Keep this application fork from accidental publication. |

All other upstream `lib/` files and the license remain unchanged at that
baseline. The vendored tree includes the runtime sources; upstream examples,
tests, command wrappers, and project planning documents were not all copied.
`CRISPCLOUD_PATCH.md` records the original macOS patch; this document records
the complete current source differences.

The credential-storage follow-up additionally changes `lib/config.dart` to
skip CLI directory creation and permission handling when a host supplies a
`ConfigStorage`. CrispCloud injects the same verified `FilenConfigService`
backend into the SDK; session-only and browser logins therefore do not attempt
native filesystem initialization. Default standalone CLI storage behavior and
the Filen credential fields/wire formats are unchanged. This difference is
covered by the application's `config_services_test.dart` and
`filen_adapter_test.dart` regressions.

### 8 November 2026: validate file keys before cipher use

The follow-up to source `7985a1fb77ccda59e9636f16ad964f453e0f8d7c`
adds these local changes without changing valid Filen ciphertext, login
derivation, metadata encryption or chunk framing:

| File | Additional change | Reason |
| --- | --- | --- |
| `lib/openssl_aesgcm.dart` | Reject keys whose length is not exactly 32 bytes before allocation/native initialization. | `EVP_aes_256_gcm` consumes 32 bytes without receiving the Dart allocation length. Short keys could cause an out-of-bounds native read; long keys were silently truncated. |
| `lib/bcrypt_aesgcm.dart` | Reject non-32-byte keys before both native encryption and decryption. | Enforce the AES-256 API consistently instead of accepting a different AES key size. |
| `lib/aes_gcm_backend.dart` | Validate AES-256 keys in the portable backends; explicitly reject truncated PointyCastle input. | Malformed input must fail before cipher processing on every backend. |
| `lib/crypto.dart` | Enforce key size at the public chunk API and decode only complete AES-256 keys. Preserve raw 32-character keys; recognize 64-character hexadecimal keys before base64; support padded/unpadded base64 and base64url. | A hex key is also valid base64 text but decodes to 48 incorrect bytes through that route. No key is truncated or padded to fit. |

The corresponding application OpenSSL/CNG copies have the same boundary
guards. The application also routes its buffered and destination-file Filen
downloads through the existing size/hash-checked stream. Destination writes
are privately staged until stream completion, preserving existing files on
authentication, final-hash or account-change failures. The standalone SDK's
`lib/download.dart` API is unchanged; this application correction is not an
assertion that every standalone SDK download path now validates whole-file
integrity. Legacy metadata without a file hash remains readable: per-chunk
GCM tags and total size are verified, but a missing hash cannot authenticate
the ordering of same-sized chunks.

Regression coverage is in `test/native_ffi_crypto_test.dart`,
`test/filen_crypto_validation_test.dart` and
`test/filen_bounded_transfer_test.dart` in the application. It covers native
short/long key rejection, representation interoperability, invalid decoded
lengths, reordered/duplicated chunks, truncated manifests, destination
preservation and legacy compatibility. Check CI at the release commit for
actual execution results; this note does not claim a live-provider test.

Relevant CrispCloud history:

- [Initial vendoring and macOS loader guard](https://github.com/CrispStrobe/CrispCloud/commit/c5ca26dabaf64e2d8d21103e5f93dba67e792f01).
- [Remote filename preservation](https://github.com/CrispStrobe/CrispCloud/commit/91af07f20f858f457740dc36940c23516e7a6a0e).
- [Native permission and memory-probe changes](https://github.com/CrispStrobe/CrispCloud/commit/58178625d494d79aa922f360715a1d055da4eb70).
- [Conditional FFI import for web builds](https://github.com/CrispStrobe/CrispCloud/commit/da7c3e940d022dd585708beac2de2cd5c3d10be2).
- [AES-256 native boundary validation](https://github.com/CrispStrobe/CrispCloud/commit/df9eaa225662853a7018307205b8c9884b123e7d).
- [Filen key representations and portable backend validation](https://github.com/CrispStrobe/CrispCloud/commit/9ffefa737815c742418c1ed205fb9771bc99557a).
- [Verified application downloads and destination preservation](https://github.com/CrispStrobe/CrispCloud/commit/732954f49d9593a7bec7a0007714a7ff0f1956a6).

## Cryptographic implementation boundary

`lib/crypto.dart` implements the published Filen protocol using standard
primitives: AES-256-GCM for metadata and file chunks,
PBKDF2-HMAC-SHA512 for authentication key derivation, HMAC-SHA256 for filename
hashes, and SHA-512 for file hashes. The protocol's serialization and key
derivation parameters are preserved for compatibility with existing accounts
and files.

Metadata encryption and key derivation execute Dart cryptographic code.
File chunks use `lib/aes_gcm_backend.dart`: system OpenSSL on supported
desktop targets, Windows CNG when available, or `package:cryptography`.
CrispCloud enables `cryptography_flutter` on native platforms, allowing that
last backend to use platform crypto with a Dart fallback. Apple builds do not
load an external Homebrew OpenSSL library, but the application still contains
cryptographic implementations beyond Apple's OS facilities. This source
provenance does not justify an "OS encryption only" declaration.

`lib/credential_crypto.dart` and `lib/config.dart` also contain the upstream
CLI's AES-256-GCM/PBKDF2 credential wrapper. Its default public static wrapping
secret is explicitly described as obfuscation. The application's Filen adapter
persists account credentials through `FilenConfigService` and the application's
`SecureStorage`, rather than that standalone CLI credential file.

## Release verification

1. Resolve this path dependency using the application's committed
   `pubspec.lock` and publish the same source revision as the distributed build.
2. When refreshing the vendored source, download the versioned archive, verify
   its SHA-256, compare all runtime files, and update the change table above.
3. Retain the license and the public source URLs with the release's dependency
   inventory. A new upstream version or local crypto modification needs a new
   review; this note does not attest to future revisions automatically.
4. Run the application's Filen adapter, key-validation and bounded-transfer
   tests, plus the native crypto and cross-backend interoperability tests.
   These are local fixtures; credentialed live-provider tests are separate.

For the application's export-compliance decision and release procedure, see
[`docs/export-compliance.md`](../../docs/export-compliance.md).
