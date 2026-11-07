# Crypto audit and store-release engineering

Review date: **2026-11-07**. Initial source: `c1dc32161ed5a429c356c06e930966954faa4fbf`.
The feature branch also incorporates main's iOS shell/folder-access changes
through `c4847d284665ad04b253ce925dbf387ff7123402`.

This is a source review with targeted security regressions. It is not an
independent certification of every dependency, a penetration test of provider
servers, or a government export classification. The legal release decision is
in [export-compliance.md](export-compliance.md). The machine-readable scope is
[crypto-inventory.json](crypto-inventory.json); exact dependency provenance is
in [crypto-dependencies.md](crypto-dependencies.md).

## Product decision

Retain Filen and Internxt client-side encryption in the common iOS, macOS and
Android application. Keep the optional AES-GCM file wrapper and published
vault-format primitives. Do not introduce a weak-key mode, a plaintext provider
fallback, or an Apple-OS-only declaration. The proposed no-BIS-report/no-CCATS
route is an eligible **finished mass-market application**, with an internal
classification record and truthful Apple questionnaire answers. Public-source
availability is an additional, separately evaluated route.

No build flag in this branch removes either mandatory provider. Their file
encryption formats, login key derivation and transfer APIs are preserved.

## Findings corrected on this branch

| Finding at the initial revision | Effect | Correction and evidence |
| --- | --- | --- |
| `ProxyHttpOverrides.badCertificateCallback` trusted `validateCertificate == true` for unpinned hosts. The custom-CA fallback compared issuer strings; the purported SPKI calculation hashed the whole certificate. | Enabling the optional pinning setting could accept a system-rejected certificate, exposing credentials and transfers to interception. Valid but unpinned certificates were not actually checked either. | Remove the permissive callback and bogus pin implementation. Native TLS verifies signatures, hostname and validity with system roots and explicitly imported CAs. Validate CA input before persistence; enforce the selected minimum TLS version. Disable and migrate the unsupported pinning preference with an honest UI explanation. `test/tls_verification_test.dart` performs actual loopback handshakes, including forged issuer, wrong-host and expired certificates. |
| Native Internxt `ConfigService` used the SDK's default file storage, whose legacy envelope has a public static wrapping secret. Some web paths also used unencrypted preferences. | Recoverable credentials/mnemonic outside the application's intended secure-storage boundary. | All production constructors inject `InternxtSecureConfigStorage`, using the host Keychain/Keystore or unlocked browser vault. Read old envelopes only for migration, verify the secure write before cleanup, and retain a tombstone after logout so cleanup failure cannot resurrect credentials. Clear SDK auth and the cached login response on logout. `test/internxt_secure_config_test.dart` covers migration, failure, restart, namespaces and SDK persistence. |
| `CryptomatorService` labelled a custom truncated-HMAC/AES-CTR construction AES-SIV; directory and content-key helpers did not follow the format. Vault config was read without authenticating its JWT. | Incompatible filenames/paths and misleading standards claims; untrusted configuration could influence unlock behavior. | Implement RFC 5297 CMAC/S2V and correctly masked AES-CTR, authenticate the tag, use Cryptomator's NFC/base64url filenames, directory hash and shortened-name metadata, verify the vault JWT and version MAC, and extract content keys only from an authenticated GCM header. Bound hostile scrypt parameters. Use independent RFC 5297 vectors, independently generated AES-SIV vectors and an upstream Cryptomator header fixture. |
| VeraCrypt parser read geometry and algorithm IDs from incorrect offsets and accepted decrypted magic without checking both header CRCs. It advertised algorithms it did not implement. | Incorrect metadata, false acceptance of damaged headers, and inaccurate supported-feature claims. | Use the published layout, check both CRCs, header version and geometry, resolve algorithms from the successful decryption attempt, and reject unsupported KDFs. Restrict advertised parser support to AES-XTS and implemented KDFs. Independent AES-XTS/PBKDF2 fixtures and corruption tests are in `test/veracrypt_header_vectors_test.dart`. CRC remains a format check, not an authentication tag. |
| Backup encryption silently returned plaintext when a codec callback or key was missing, and serialized backup passphrases into ordinary preferences. | A plan marked encrypted could upload plaintext; saved passphrases were recoverable from settings. | Fail before file I/O without an encryptor/decryptor and key. Store keys separately in `SecureStorage`, verify migration before rewriting metadata, preserve legacy recovery data on failure/conflict, and keep ordinary plaintext plans independent of the keychain. `test/backup_encryption_security_test.dart` tests plaintext-upload prevention, destination preservation and key persistence. |
| The Office Agile decryptor parsed integrity fields but did not verify the encrypted package's HMAC. | CBC document ciphertext and the stream-size header could be changed without the integrity check required by the format. | Verify HMAC over the complete `EncryptedPackage` before returning decrypted document bytes. Reject missing, malformed or mismatched integrity metadata. Negative tests cover modified package data, stream size and missing integrity metadata in `packages/quds_office_engine/test/office_crypto_test.dart`. |

The original optional file wrapper uses standard AES-256-GCM, verifies its tag
and draws nonces/salts from `Random.secure()`. The streaming path privately
spools plaintext until tag verification. This branch preserves that existing
wire format. Cross-backend tests cover PointyCastle, `cryptography` and available
native implementations; real-device acceleration remains a separate test.

## Existing feature boundaries, not new removals

The names of service classes overstate what the initial app actually exposed:

- **Cryptomator:** the vault provider has no application UI/import consumer in
  the reviewed code. Filename/path/content-key helpers had test-only callers.
  Corrected primitives are useful building blocks, but a complete cloud vault
  filesystem, chunk content I/O and directory traversal still require work.
  A nested path cannot be derived from cleartext names alone: read the real
  directory metadata. Shortened names need their `name.c9s` reverse mapping.
- **VeraCrypt:** bundled code detects candidates and parses a limited set of
  headers. It does not decrypt a mounted volume filesystem on mobile. Full
  mounting uses the separately installed desktop CLI, which remains unavailable
  in the App Store sandbox/mobile path. No cascade, keyfile, custom PIM or
  arbitrary KDF support is claimed by the bundled parser.
- **Backups:** the reviewed backup provider has no application UI/import caller.
  Its callback API is retained; an encrypted plan now requires a configured
  cipher instead of silently treating missing implementation as success.
- **Pinning:** the previous setting was not functional certificate pinning.
  The current transport provides platform certificate verification and custom
  trust anchors. A future pinning implementation must enforce actual pins
  before credentials are sent and preserve chain/hostname/expiry checks.

The corrected Cryptomator helpers deliberately do not read or write the old
invented HMAC/CTR format as though it were Cryptomator. No production file-I/O
caller was found that wrote that format. If a downstream consumer used these
internal helpers independently, it needs a separate recovery/migration tool;
automatic fallback would conceal format and authentication failures.

## Remaining security and interoperability limits

1. **Internxt's published protocol has legacy constructions.** SDK 0.2.3 uses
   AES-CTR file encryption rather than AEAD, legacy CBC/MD5-derived text wrappers
   and a deterministic GCM private-key wrapper. Repeated key generation with
   the same password can reuse that wrapper's key/nonce. These are upstream
   protocol risks, not repaired by moving local credentials to secure storage.
   A compatible protocol change needs provider coordination and independent
   vectors. Do not market every provider path as authenticated AES-GCM.
2. **Office interoperability needs independent end-to-end fixtures.** The local
   Agile implementation's password-key-field IV/padding handling differs from
   the published specification. The HMAC fix preserves existing library output
   and does not silently change its encryption format. Existing round trips
   alone do not prove Microsoft Office interoperability. Treat this as an open
   compatibility issue when claiming support for password-protected documents.
3. **Password strength and KDF parameters still matter.** The optional file
   wrapper defaults to PBKDF2-HMAC-SHA256 with 100,000 iterations. Changing that
   default alone would derive different keys for existing settings. Any KDF
   upgrade needs versioned parameters and migration; this review does not make
   a blanket password-strength guarantee.
4. **Platform secure storage is not an unlocked-device guarantee.** Malware in
   the app process, a compromised browser profile, or an unlocked device can
   still expose secrets. Browser storage uses the app's unlocked encrypted
   vault and does not gain the same OS isolation as native Keychain/Keystore.
5. **The dependency scope is wider than the four named services.** SSH, SMB,
   archive readers, PDF/Office crypto, provider credentials and native assets
   all belong in release review. A public dependency or AES primitive alone
   does not establish the classification of a whole product or custom protocol.

No production credentials were used, no live provider account was mutated,
and no government notification/report, CCATS request or store submission was
made by the audit workflow.

## Validation and build evidence

The PR's **Crypto release evidence** job checks the inventory and failure paths
for missing providers, unreviewed dependency/native overrides, dirty source,
missing artifacts and altered Apple declarations. The **Crypto gate** on Linux,
macOS and Windows runs published vectors, format/tamper tests and provider
regressions. Full CI also builds iOS, macOS and Android. Passing source tests is
not a substitute for a successful target build or a live-account smoke test.

The local release-evidence Python suite has been run. Local Flutter bootstrap
was blocked by automatic approval review after attempting to contact the
cloud-instance metadata endpoint; Flutter/device results are taken from GitHub
Actions, not inferred from local formatting. Consult the final PR checks for
the exact revision and successful/failed jobs; a queued or cancelled job is
not a passing test.

Store workflows run the crypto/provider regressions, retain the committed
dependency lock, and attach `crypto-evidence.json`, the lockfile, inventory and
export guide to the final signed IPA/package/AAB artifacts. The evidence hashes
the actual artifact after signing. The generic Android release also attaches
the APK evidence. Example for an already built artifact:

```sh
mkdir -p build/export-compliance
dart pub deps --json > build/export-compliance/dependencies.json
python3 tool/crypto_release_evidence.py --platform android --require-clean \
  --artifact path/to/app.aab --dependencies build/export-compliance/dependencies.json
```

The script records facts; it cannot decide an ECCN, verify store territories,
prove remote source availability, or grant an exemption. Keep an internal
decision for the exact artifacts using the template in the export guide.

## Technical reference sources

- [RFC 5297: AES-SIV and independent appendix A vectors](https://www.rfc-editor.org/rfc/rfc5297).
- [Cryptomator format architecture](https://docs.cryptomator.org/en/latest/security/architecture/) and [upstream cryptolib](https://github.com/cryptomator/cryptolib).
- [VeraCrypt volume format specification](https://veracrypt.io/en/VeraCrypt%20Volume%20Format%20Specification.html).
- [Dart HttpClient badCertificateCallback semantics](https://api.dart.dev/dart-io/HttpClient/badCertificateCallback.html) and [SecurityContext](https://api.dart.dev/dart-io/SecurityContext-class.html).
- [Microsoft Office cryptography specification](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/).
- [Exact provider/native source provenance](crypto-dependencies.md) and [Filen local patch provenance](../packages/filen_client/UPSTREAM.md).
