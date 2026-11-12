# Crypto audit and store-release engineering

Initial review: **2026-11-07**. Initial source: `c1dc32161ed5a429c356c06e930966954faa4fbf`.
The feature branch also incorporates main's iOS shell/folder-access changes
through `c4847d284665ad04b253ce925dbf387ff7123402`.

This is a source review with targeted security regressions. It is not an
independent certification of every dependency, a penetration test of provider
servers, or a government export classification. The legal release decision is
in [export-compliance.md](export-compliance.md). The machine-readable scope is
[crypto-inventory.json](crypto-inventory.json); exact dependency provenance is
in [crypto-dependencies.md](crypto-dependencies.md).

## 8 November 2026 follow-up: concrete defects and release controls

The follow-up starts from main `7985a1fb77ccda59e9636f16ad964f453e0f8d7c`
on remote branch `security/crypto-export-compliance-2026-11-08`, with changes
saved incrementally in [PR 34](https://github.com/CrispStrobe/CrispCloud/pull/34).
The branch incorporates main's subsequent PR 35 build-10 distribution record
through `5a63e7be85f60122ed8ea6a72cce37c50157d519` without treating that
historical record as live account or binary verification.
The audited source advances to `1.1.0+11`, because the repository records a
prior upload of build 10. The fixes require a new artifact; the existing upload
does not acquire them. TestFlight selection must match both version and build
counter from this reviewed checkout.
It found additional implementation and evidence defects; the presence of
AES-GCM or a previous audit did not establish that every path was correct.

| Finding | Correction | Regression evidence |
| --- | --- | --- |
| Both OpenSSL bindings allocated the supplied key length but selected `EVP_aes_256_gcm`, which reads 32 bytes. Short keys could read beyond the native allocation; long keys were truncated. BCrypt could accept a different AES strength. | Reject every non-32-byte key before native cipher use in both application and Filen copies. No remote exploit is asserted. | `native_ffi_crypto_test.dart` checks both copies on Linux/Windows; the Apple path keeps external OpenSSL disabled. |
| Filen decoded 64-character hexadecimal keys as base64 first, producing 48 incorrect bytes; portable backends did not consistently enforce AES-256. | Preserve the provider's raw 32-character convention, recognize exact hexadecimal first, and require decoded 32-byte keys in every backend. | `filen_crypto_validation_test.dart` covers encodings, same-ciphertext decryption, wrong lengths and truncated envelopes. |
| Filen buffered and destination-file downloads bypassed whole-file checks, concatenating individually valid GCM chunks. Those tags do not bind a chunk's position. | Consume the existing size/hash-verified stream to completion before returning bytes; stage file output privately before publication. Bad hash, truncation, duplication, reordering and account changes leave destinations intact. | `filen_bounded_transfer_test.dart` exercises valid and adversarial chunk sequences and destination preservation. |
| Generic file encryption generated a fresh salt and session key while the file envelope carried no recovery parameters. The UI could activate without backup confirmation; active-key import silently did nothing while reporting success. | Require re-entry of the exact 24-word recovery phrase before new connection activation, reject empty passphrases, and install the same prepared key after login. Reject a different key import while active; copy imported/exported key material defensively and retire it on logout/provider switch. | `file_encryption_recovery_test.dart` includes an independently verified AES-GCM ciphertext and all nine locales; `encryption_key_lifecycle_test.dart` covers mutation, wrong keys, import refusal and session retirement. |
| Encrypted backup keys could be migrated or published into a session-only store despite persistent plan/snapshot metadata. Readback alone does not prove restart recovery. | Require `SecureStorage.isPersistent` before key-bearing plan hydration, migration, publication or key persistence. Preserve old recovery material and keep key-free plaintext plans usable. | `backup_encryption_security_test.dart` covers ephemeral refusal before secret I/O, migration preservation and plaintext operation; persistent failure/readback cases remain. |
| The Apple source gate treated two Markdown substrings as evidence, never inspected the submitted plist, and never verified live French availability. The guide overinterpreted a declaration API 409. | Use a structured policy bound to inventory, resolved dependency lock and reviewed source hashes; inspect actual IPA/ZIP/pkg metadata; require a separate GET-only live check immediately before upload. Retain pending history/channel facts explicitly. | `test_apple_export_preflight.py` covers stale policy/source, tampered metadata, exact app/build/platform, France/history/approval checks, pagination and token-origin boundaries. Existing release-evidence tests cover the integration. |
| External TestFlight distribution could select or create a group by name and mutate build metadata without verifying the audience's separate French coverage. Storefront exclusion does not restrict beta recipients. | Require a completed channel review and exact external-group allowlist; deny public links on the no-France route. Recheck the live group, uploaded build and any required approved declaration before each allowed mutation. Remove implicit group creation and keep account access out of import-time code. | `test_testflight_export_guard.rb` covers pending reviews, ambiguous/unreviewed groups, public links, changed state between writes, wrong builds and unapproved declarations. The CLI's JWT lifetime now includes its clock-skew allowance within Apple's limit. |

The valid `nonce (12 bytes) | ciphertext | GCM tag (16 bytes)` file format is
unchanged. Previously encrypted files require their original raw key, mnemonic
or backup bundle. Re-entering the passphrase alone creates a different salt/key;
this patch cannot recover already-lost keys. The backup bundle contains the
raw-key mnemonic in readable JSON and must be protected as a secret.

Filen's official SDK declares `FileMetadata.hash` optional
([pinned source](https://github.com/FilenCloudDienste/filen-sdk-ts/blob/6f272ffac11802d5d1a64fb8796871b402db6a71/src/types.ts)).
For hash-absent metadata, chunk authentication and file size still work, but
same-sized chunk reordering cannot be detected. Streaming consumers must read
to completion and handle the final error; individual yielded chunks are not a
complete-file integrity result. The hardened buffered/file application paths
honor that distinction. Standalone vendored SDK CLI/WebDAV download methods
remain outside this application-path fix and must not be described as audited
or fixed by it.

### Follow-up validation status

The local Python checks passed: **37 Apple preflight tests**, and **39 release-
evidence tests with 2 additional macOS-only tests skipped**. Source policy,
plist parsing, workflow YAML parsing and whitespace checks also passed at the
checkpoint. These results use synthetic API fixtures and an ephemeral local
OpenSSL signing key, not App Store Connect credentials. Actual macOS package
expansion, native crypto, Flutter widgets and platform builds must pass the
final PR checks. Dart/Flutter and Ruby are absent from this review workspace;
no local device or live-provider pass is claimed. The prior review's different
bootstrap limitation below is historical, not a new approval rejection.
The Ruby TestFlight failure-path tests are wired into the source-evidence CI
job; a pending or queued workflow is not a passing result.

The distribution history and future external TestFlight audience have not
been established from this repository. The policy deliberately retains pending
facts. No France availability change, Apple submission, ANSSI declaration or
BIS filing was performed. See [the export guide](export-compliance.md) for the
specific evidence needed to complete a release.

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
| Backup encryption silently returned plaintext when a codec callback or key was missing, serialized backup passphrases into ordinary preferences, and allowed encryption changes that invalidated existing snapshots. | A plan marked encrypted could upload plaintext; saved passphrases were recoverable from settings; retained snapshots could lose their decryption key or be restored as ciphertext. | Fail before file I/O without an encryptor/decryptor and key. Store keys separately in `SecureStorage`, verify migration before rewriting metadata, preserve legacy recovery data on failure/conflict, and keep ordinary plaintext plans independent of the keychain. Reject mode/key changes while snapshots exist or a backup is active. `test/backup_encryption_security_test.dart` tests plaintext-upload prevention, destination preservation, key persistence and original-key recovery after a denied update. |
| The Office Agile decryptor parsed integrity fields but did not verify the encrypted package's HMAC. | CBC document ciphertext and the stream-size header could be changed without checking the integrity metadata already present. | Verify HMAC over the complete `EncryptedPackage` before returning decrypted document bytes. Reject missing, malformed or mismatched integrity metadata. Accept the standard `KeyData.saltSize` HMAC key length and existing writer's `hashSize` length only when the full HMAC verifies. An independent short-key fixture and negative tests cover package data, stream size and missing integrity metadata in `packages/quds_office_engine/test/office_crypto_test.dart`. |

The original optional file wrapper uses standard AES-256-GCM, verifies its tag
and draws nonces/salts from `Random.secure()`. The streaming path privately
spools plaintext until tag verification. This branch preserves that existing
wire format. Cross-backend tests cover PointyCastle, `cryptography` and available
native implementations; real-device acceleration remains a separate test.

## PR26 follow-up: credential-storage backends

The follow-up review includes PR26 source `f2536648aed5c3b4050de92cce22235f0143d58e`
and the concurrently added first-run/create-keychain UI at
`dcba7255a6c5015a145e2ecb15950b193ba75500`, plus the later recovery and Filen
persistence changes through `8316994`. The scope here is backend selection,
credential preservation, local cryptographic storage and its application gates;
it is not a fresh audit of every provider or dependency. The integrated behavior
is described in [credential-storage.md](credential-storage.md).

| Finding in the PR26 inputs | Correction and regression scope |
| --- | --- |
| Custom file-keychain selection called `SecKeychainSetDefault` and replaced the user's search list, including at startup independently of the active mode. A failed custom selection could still probe the default store, and the generic Flutter service was not an app-specific namespace in a file keychain. | Remove the global setters/duplicate channel. Use explicit keychain references for every SecItem operation and `com.crispcloud.credentials.v1` for the custom backend. Leave experimental generic-service entries untouched. Browse retains a security-scoped bookmark; creation rejects occupied/alias/symlink/reserved paths and checks unlock plus scoped read/write/delete. Native temporary-keychain tests check creation and CRUD without changing default/search-list preferences or foreign services. |
| The encrypted-file backend cached whole-file state, permitting stale instances to lose writes, and could treat malformed/empty existing data as a new store. Unlock failures and unauthenticated values could become apparent absence. | Reload committed state inside an OS-locked transaction, stage/flush and atomically replace without deleting the previous file, reject unsupported paths and corruption, and invalidate stale vault generations. Validate metadata/KDF bounds before derivation and keep failed unlocks locked. File/codec tests cover overlapping writers, separate-isolate contention, failed publication, restart, corruption, metadata changes and independent legacy data. |
| Credential AES-GCM authenticated a value without binding its storage key. Copying a valid record to a different credential/policy key could change its meaning without breaking the GCM tag. | New `v2:` writes encrypt and authenticate the key together with the value. An inner binary marker prevents a prefix-stripping downgrade to legacy UTF-8. Transposition/prefix-tampering tests exercise the check. Existing unbound values remain readable and become bound on rewrite; the patch does not claim that untouched legacy entries gained binding. |
| Automatic backend fallback or treating an unreadable lock policy as disabled could expose an existing profile without its policy. Settings could label a different pending mode as already active, and separately saved mode/path preferences could split one intended selection. | Existing or ambiguous profiles retry the configured store. A separately checked fresh-profile path retains first-run choice. App Lock policy errors stop the gate; session-only cannot enable a persistent lock. Settings keeps active/pending state distinct, rechecks App Lock before saving a change, and writes/reloads a single versioned selection record. Bootstrap, gate, config and chooser regressions cover these boundaries. |
| A later startup recovery action offered replacement storage while the existing store and its App Lock policy were unreadable. A warning cannot establish that changing stores is authorized by the old policy. | Restrict recovery to regranting access to the same configured macOS file keychain. Native code validates canonical path plus readable file/volume identities before replacing its bookmark; cancellation or a different/missing file does not mutate bookmarks. Recheck selection before/after the picker, then retry the original policy gate. Default OS stores retain OS repair guidance and Retry. Pure service, Dart bridge and native helper regressions cover the boundary; interactive sandbox access still needs a signed-app smoke test. |
| Treating an absent vault as first use could create an empty replacement after the original vault and its App Lock metadata disappeared. Retaining a creation grant after a completed or failed attempt could let a stale startup recreate it later. | Version-3 selection records carry an explicit creation grant; existing version-2 selections imply no grant. Only verified fresh setup or an authenticated switch from another backend grants creation. Check the selection snapshot, consume through a verified preference write before the creator runs, and never regrant after failure. Existing unlock also retires unused intent. Browser fresh setup requires empty preferences and browser storage. Config/bootstrap/gate tests cover stale grants, failed consumption, creation ordering and blocked missing existing vaults. |
| Generic and Internxt migrations could import persistent credentials into a session store, delete the durable source or mark migration complete after only an in-memory write. | `SecureStorage.isPersistent` distinguishes ephemeral stores. Session mode skips those imports/cleanup markers. Persistent migration verifies readback before legacy deletion and preserves conflicting secure values. Secure-storage and Internxt regressions check session isolation and preservation on failure. |
| The Filen SDK could use its default credential file independently of the app's selected host store. Later cleanup trusted an unverified write and could delete durable legacy credentials in session mode; native cleanup also leaked into browser paths. | Inject the same host-store adapter into the production SDK. Verify exact credential readback before persistent cleanup; preserve legacy files/preferences in session mode. Reject corrupt reads and failed writes with fixed errors, serialize app/SDK credential operations, and keep filesystem cleanup behind a native-only implementation. Config, adapter and browser regressions cover failed writes, preservation, error redaction and SDK persistence. |

Filen logout now propagates a safe error when saved-credential deletion or its
readback cannot be verified. It discards session keys, preserves the adapter for
retry, and shows cleanup failure instead of a success message. Persistent
logout removes retained legacy preferences and the old SDK credential file
before the secure entry to prevent reimport; ephemeral logout does not touch
those durable sources. Config, adapter,
auth-state and dialog regressions are in `test/filen_adapter_test.dart`.

Fresh-profile detection now preserves filesystem inspection failures instead
of trusting `FileSystemEntity.type`'s ambiguous `notFound` result. It rejects
unavailable ancestors, symlink suffixes and parent traversal, rechecks the
preferences snapshot after asynchronous filesystem inspection, and revalidates
freshness before accepting a first-run chooser result. Settings retains its
operation guard through the modal and the subsequent save; cancelling a pending
switch back to the active file vault does not authorize recreating that vault.
Credential startup, recovery and vault errors use fixed messages before unlock
rather than displaying arbitrary storage exceptions.

For this post-`8316994` review, locally completed checks were:

- Dart 3.13.0 parsing/formatting of the changed Dart files. The standalone SDK
  does not provide the Flutter framework, analysis dependencies or widget test
  runtime, so this is not a `flutter analyze` or Flutter-test success claim.
- The release-evidence tool's 36 tests: 34 passed, with two Apple `plutil` tests
  skipped on Linux. The source-input check retained both Filen and Internxt.
- An isolated Dart harness importing the real Filen legacy-cleanup helper and
  the locked public `path` 1.9.1 dependency: 21 Linux filesystem checks passed,
  including real permission errors, link-target preservation, normalized
  suffixes and parent-traversal refusal. The initial run reproduced a
  trailing-separator symlink deletion bug; the corrected helper passes those
  cases, which are also represented in the committed config-service tests.

The focused Flutter/browser/native tests are wired into CI and the Apple store
preflight workflows. Their results must be checked at the PR's final commit;
earlier local build claims and queued CI runs do not validate these changes.

Filen and Internxt retain their foreground account and transfer protocols. The
new backend choice does not remove their encryption or require a plaintext
provider mode. It also does not create an OS-only application: the shared vault
and other bundled implementations remain in the inventory. The conditional
export-release analysis is unchanged; this follow-up supplies engineering
evidence, not an additional BIS or Apple classification.

Important limits remain:

- **App Lock and the password vault are different mechanisms.** App Lock retains
  its legacy 10,000-round SHA-256 salt/PIN verifier format; this review does not
  replace it with a modern password KDF. The credential vault separately uses
  PBKDF2-HMAC-SHA256 and AES-256-GCM. App Lock is an application access gate, not
  a guarantee against an attacker controlling the user's process or profile.
- **File transactions do not supply anti-rollback or full-map authentication.**
  Storage-key names/sizes remain visible, deleted entries are not detected as a
  cryptographic failure, and old valid records/vaults can be restored. Legacy
  unbound records retain their old limitation. Browser localStorage has no
  native file transaction spanning multiple tabs. OS/device failures can also
  defeat durability; a post-replacement sync error reports an uncertain commit.
- **Consuming creation permission can leave a blocked interrupted setup.**
  The grant is retired before vault initialization. A crash or failure before
  vault publication can require restoring the vault or an authorized return to
  the prior backend; startup does not automatically grant another attempt.
  Selection verification and serialization apply within one isolate, not as
  cross-process compare-and-swap or a transaction across browser tabs. Editable
  preferences are not cryptographic authorization against a local attacker.
- **Password/session modes require foreground availability.** A separate
  background worker cannot unlock the file vault or inherit session memory.
  The mobile worker refuses those modes instead of using stale OS credentials;
  its existing supported providers remain FTP/FTPS and WebDAV. This does not add
  unattended Filen or Internxt sync.
- **Native helper tests are bounded.** They use temporary keychains and test
  scope, failure and preference preservation. Interactive save/open panels,
  bookmark persistence across signed sandbox launches, OS ACL prompts and live
  provider accounts still need platform smoke testing. Consult the final CI
  revision for actual native/Dart results; source inspection is not a test pass.

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
   Agile implementation's password-key-field IV/padding handling and secret-key
   block constant differ from the published specification. It also conflates
   the package and password-wrapping key lengths, which may differ in valid
   files. The HMAC fix preserves existing library output and does not silently
   change its encryption format. Its independent fixture isolates package
   integrity while retaining this library's existing password wrapping; it is
   not a Microsoft-produced file. Existing round trips alone do not prove
   Microsoft Office interoperability. Treat these as open compatibility issues
   when claiming support for password-protected documents.
   The [Agile schema](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/87020a34-e73f-4139-99bc-bbdf6cf6fa55) permits omitting `dataIntegrity`; this reader deliberately
   rejects that unauthenticated variant so stripping the element cannot bypass
   authentication. [Microsoft documents](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/6b4a08cb-195a-442e-b31c-7c94624a8c29) that Office-generated Agile documents
   include the element. This is a compatibility policy, not a claim that every
   schema-valid Agile file contains an HMAC.
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
6. **Native SMB has an exceptional desktop RNG-failure path.** The pinned
   library ignores the random-generator failure status when creating CCM
   nonces and can fall back to a weak PRNG after desktop entropy sources fail.
   The published Apple/Android configuration excludes that fallback. CCM needs
   nonce uniqueness; predictability alone is not a break. Repetition risk under
   local entropy failure needs upstream hardening. No fault-injection exploit
   or remote trigger was established; see the pinned sources in the dependency
   review.
7. **Archive compatibility includes published legacy crypto.** Traditional
   PKWARE ZipCrypto decoding is active through `koni_zip`, alongside AES ZIP,
   7z and RAR formats with published format-specific key derivation. ZipCrypto
   is a distinct legacy cipher, not AES framing. New encrypted ZIP output uses
   AES-256 AE-2. Retaining compatibility does not justify describing every
   active algorithm as internationally standardized. Equally, lack of a formal
   standard does not alone establish the legal category "non-standard
   cryptography"; use the full published inventory and export guide.

No production credentials were used, no live provider account was mutated,
and no government notification/report, CCATS request or store submission was
made by the audit workflow.

## 11 November 2026: batch-command source binding review

Reviewed [source ef3ca3c038bab1a2af7765eb09d395d994431e99](https://github.com/CrispStrobe/CrispCloud/tree/ef3ca3c038bab1a2af7765eb09d395d994431e99)
against the previously covered
[e9dd5dbbb8581e16f228d4f51239adf7d0b22660](https://github.com/CrispStrobe/CrispCloud/tree/e9dd5dbbb8581e16f228d4f51239adf7d0b22660).
The [source comparison](https://github.com/CrispStrobe/CrispCloud/compare/e9dd5dbbb8581e16f228d4f51239adf7d0b22660...ef3ca3c038bab1a2af7765eb09d395d994431e99)
changes exactly two of the inventory's 128 reviewed files:

| Reviewed file | Source finding |
| --- | --- |
| `cli/lib/commands/connect.dart` | Only the line wrapping of the existing SFTP host-key help string changes. Its text, option, defaults and validation remain identical. |
| `lib/widgets/command_palette.dart` | Adds the batch-scan dialog import and an explicitly selected command that opens its review flow. Existing account, encryption and key-management commands remain unchanged. |

The reachable batch flow captures verified marked-folder origins, retains
their existing client/grant checks, reads source metadata and persists inert
full reports through existing snapshot storage. Its source-label lookup is
display-only and requires matching client identity before using active-account
information. Snapshot publication keeps uncertain commits distinct from
cancellation and preserves their candidate pages. These additions introduce
no cipher, key derivation, transport, authentication mode or credential store.
No source-file content transfer or source-file mutation is added by this flow.

All 128 exact current inputs were fetched and checked against their Git blob
identities. The canonical sorted path-to-SHA-256 map, using the previous bytes
of the two changed inputs, reproduces the policy's existing fingerprint:

`72be43025ae190ec5734c2b877481361a318a4b234407558004b2fda703e866a`

Updating only those two inputs yields:

`1be5e3187053a515c775c136e8424c4f11b1616a5978ed8856e54223476a7ad8`

The other 126 reviewed inputs, inventory and dependency lock are unchanged.
The policy refresh changes only `reviewed_source_sha256`; validators,
dependency provenance, encryption declarations, documentation decisions,
compliance-code and distribution settings are unchanged. This source binding
review does not renew external approvals or establish a signed artifact's
correspondence to source.

[CI job 130573305765](https://github.com/CrispStrobe/CrispCloud/actions/runs/43035543238/job/130573305765)
checked merge `e1c8d92c3013bf12b01b5789f1f0b33339647ca1`, whose tree is
identical to the reviewed source. Its validator suites completed with 41 tests
(two Apple-only skips) and 37 tests, then `crypto_release_evidence.py --check`
correctly rejected the stale source fingerprint. The refreshed policy still
requires a successful hosted source-evidence check at its committed revision;
the hash review alone is not recorded as a passing hosted gate.

## 12 November 2026: ebook technical inventory extension

This review adds the ebook core, bundled reader and native/browser Kindle
metadata paths to [the source inventory](crypto-inventory.json). It records
implemented algorithms and the application paths that reach or reject them.
The existing provider records and export-policy decisions are retained. The
per-feature `source_reviewed_on` dates identify this bounded addition; the
inventory's earlier review date remains the date of its pre-existing records.
This is not a renewed audit of unrelated application cryptography or a legal
classification of the extended application.

### Algorithms used by supported operations

| Operation | Verified implementation and purpose | Reachability |
| --- | --- | --- |
| EPUB identifiers, prose edits and local annotations | [`document.dart`](../packages/crisp_ebook/lib/src/document.dart), [`prose.dart`](../packages/crisp_ebook/lib/src/prose.dart) and [`ebook_annotations.dart`](../lib/services/ebook_annotations.dart) use Dart `crypto.sha256` for publication identifier suffixes, stale-edit fingerprints, and a document-identity plus exact-source-version preference key. | Normal creation/editing and annotation persistence. These hashes do not encrypt the publication or its annotations; annotations use `SharedPreferences`. |
| Reader bridge session | [`reader.dart`](../packages/crisp_ebook_reader/lib/src/reader.dart) generates 24 random bytes using `Random.secure()`, then base64url-encodes them. | Each embedded reader session, together with the native/web host's message-source checks. This is an unpredictable session identifier, not an ebook encryption key. |
| EPUB font compatibility | `EpubDocument.readDecodedBytes`, foliate's [`deobfuscators`](../packages/crisp_ebook_reader/assets/foliate/epub.js), and Kindling's [`fonts::deobfuscate`](../packages/crisp_ebook_conversion/native/vendor/kindling/src/fonts.rs) implement IDPF SHA-1/1040-byte XOR and Adobe UUID-key/1024-byte XOR. Dart uses `crypto.sha1`, foliate uses WebCrypto `subtle.digest('SHA-1')`, and Kindling has its own full SHA-1 implementation. | Supported font-resource reading/import/export. Original Dart document bytes remain obfuscated; native Kindle output writes compressed FONT records without XOR. Unknown encryption methods are rejected, and native EPUB export also rejects `META-INF/rights.xml`. |
| MOBI font compatibility | [`mobi.js`'s `getFont`](../packages/crisp_ebook_reader/assets/foliate/mobi.js) reads the XOR key from the FONT record and reverses XOR over 1024 bytes when the key length is 16, otherwise 1040 bytes, before decompression. | Font resources in supported unencrypted MOBI/KF8 books. The reader rejects nonzero PalmDOC encryption before book decompression. |
| Kindle format hashes | Kindling's [`exth.rs`](../packages/crisp_ebook_conversion/native/vendor/kindling/src/exth.rs), [`mobi.rs`](../packages/crisp_ebook_conversion/native/vendor/kindling/src/mobi.rs) and [`mobi_rewrite.rs`](../packages/crisp_ebook_conversion/native/vendor/kindling/src/mobi_rewrite.rs) contain full MD5 implementations. Uses include EXTH 542's first four MD5 bytes of the title, native export identifiers, and font-signature ordering. | Native export and title metadata changes. The browser byte API also reaches `md5_first4` when it changes a title. These are compatibility fields, not authentication checks or confidentiality protection. |

The portable Linux search, bookmarks and appearance changes add no cipher,
password derivation or credential store. ZIP CRC-32 checks in the core and
reader are format-integrity checks and are not cryptographic authentication.
The font compatibility functions above do not implement general DRM decryption.

### Crypto present in ZIP dependencies but blocked by ebook entry points

The pinned [zip.js asset](../packages/crisp_ebook_reader/assets/foliate/vendor/zip.js)
contains the SJCL-derived `sha1`, `hmacSha1`, `pbkdf2`, `aes` and `ctrGladman`
implementations. The WinZip path selects 16-, 24- or 32-byte AES keys, uses
PBKDF2-HMAC-SHA1 with 1,000 iterations, and truncates HMAC-SHA1 to 10 bytes.
PBKDF2 first tries WebCrypto and has a JavaScript fallback. Traditional PKWARE
ZipCrypto is also present. The bundled encryption stream uses
`crypto.getRandomValues` when available and contains a `Math.random`-based
fallback. That fallback is not a secure RNG and is not used by a supported
ebook operation.

[`view.js`'s `makeZipLoader`](../packages/crisp_ebook_reader/assets/foliate/view.js)
inspects all central-directory entries and rejects `entry.encrypted` before
calling any entry's `getData`. It never supplies a password, and disables the
zip.js worker path. The package therefore still ships the password-crypto
code as asset bytes while its ebook loading path rejects access to it. The
Dart [ZIP container](../packages/crisp_ebook/lib/src/zip_container.dart)
independently rejects encrypted flags. This differs from the existing archive
viewer, whose reachable password compatibility remains inventoried separately.

The native bridge and vendored Kindling manifests use Rust `zip` 9.3.0 with
default features disabled and DEFLATE features selected; `aes-crypto` is not
enabled. The resolved native and Wasm locks do not contain the optional `aes`,
`hmac`, `pbkdf2` or `sha1` crates. Rust `zip` nevertheless contains ZipCrypto
source. Inspection of its pinned source confirms that passwordless reads reject
encrypted entries in `ZipFileData::make_reader`; the bridge uses those
passwordless `by_index` calls. Disabled AES is not evidence that all source in
the dependency is free of cryptography. The exact Rust crate archive checksum
is recorded in the [native lock](../packages/crisp_ebook_conversion/native/Cargo.lock)
and [Wasm lock](../packages/crisp_ebook_conversion/wasm/Cargo.lock).

### Browser metadata artifact and dependency scope

The [Wasm entry point](../packages/crisp_ebook_conversion/wasm/src/lib.rs) calls
`rewrite_mobi_metadata_bytes`, with `doc_type` and `cover_image` set to `None`.
It therefore does not call font conversion or the optional embedded source-ZIP
extraction path. The shared rewriter rejects nonzero PalmDOC encryption and
DRM EXTH records 401/402/403 in either the primary or KF8 section before writing
output. It retains the MD5 title-hash operation described above.

The broader resolved dependency graph still includes `ahash` 0.8.12,
`getrandom` 0.3.4 and 0.4.3, `rand` 0.8.8, `rand_core` 0.6.4, and
`wasm-bindgen` 0.2.121. The [Wasm manifest](../packages/crisp_ebook_conversion/wasm/Cargo.toml)
enables `getrandom` 0.3.4's `wasm_js` feature so the upstream graph can compile.
This dependency presence does not establish that an RNG is called by the
metadata operation. Direct inspection with `WebAssembly.Module.imports` returned
an empty list for the bundled `kindling_metadata.wasm`; the
[runtime](../packages/crisp_ebook_conversion/assets/metadata_runtime.js) also
rejects any module with imports before instantiation. This verifies the absence
of browser/WASI imports for that artifact, not the absence of internal MD5 or
every possible algorithm in transitive source.

The [worker](../packages/crisp_ebook_conversion/assets/metadata_worker.js) loads
the sibling bundled Wasm asset. The default Dart backend requires a same-origin
worker URL. [WASM.json](../packages/crisp_ebook_conversion/WASM.json) binds the
asset, runtime, worker and build inputs; the inventory additionally lists those
exact files and both Cargo locks for the source-evidence fingerprint. Native
prebuilt/executable/library overrides and custom worker assets require their
own content/provenance review. Matching a version or ABI string does not prove
an override has the reviewed implementation.

### Resolved reader-plugin and build-hook delta

The [dated source review](crypto-source-review-2026-11-12.md#resolved-dependency-delta)
records the exact [root lock](../pubspec.lock) comparison with main `4946a9a`.
Alongside the three local ebook packages, it adds `flutter_inappwebview` 6.1.5,
Android 1.1.3, iOS/macOS/web 1.1.2, Windows 0.6.0, platform interface 1.3.0+1
and internal annotations 1.3.0; `code_assets` changes from 2.1.0 to 2.2.0.
No other locked package entry changes. The added Dart manifests declare no
new `crypto`, `cryptography`, ASN.1 or X.509 package dependency. This does not
mean that the plugin family has no certificate-related code.

The following observations use the exact cached package versions above. Paths
are relative to each named package's source archive, whose checksum is recorded
in the root lock.

| Source examined | Technical finding |
| --- | --- |
| `flutter_inappwebview_platform_interface`: `lib/src/x509_certificate/` | The package includes its own ASN.1 DER decoder, sequence-encoding helper, OID tables and X.509 field/extension accessors. `X509PublicKey` extracts encoded EC bytes or an RSA modulus; these branches do not perform elliptic-curve or RSA operations. `X509Certificate.checkValidity` compares dates only. No signature verification, certificate-chain validation, cipher, digest or key-derivation implementation was found in these helpers. Algorithm names in the OID table describe encoded certificate fields. |
| `flutter_inappwebview_android`: `android/build.gradle`, `android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/Util.java`, and `webview/in_app_webview/InAppWebViewClient.java` under that Java source root | Client-certificate loading calls Java `KeyStore`; certificate decoding calls `CertificateFactory.getInstance("X.509")`. SSL errors and client-certificate responses are passed to Android WebView APIs. The Gradle manifest declares AndroidX WebKit 1.12.0, Browser 1.8.0, AppCompat 1.6.1 and SwipeRefreshLayout 1.1.0, with no explicit third-party crypto-library dependency. |
| `flutter_inappwebview_ios` and `flutter_inappwebview_macos`: their platform `.podspec`, `Classes/Types/URLProtectionSpace.swift`, `Classes/Types/SecCertificate.swift`, and `Classes/InAppWebView/InAppWebView.swift` | The implementations use WebKit/Foundation/Security objects: `SecTrustEvaluate`, `SecCertificateCopyData`, `SecPKCS12Import`, and `URLCredential` with trust or client identity. The podspecs declare Flutter/FlutterMacOS and OrderedSet `~>6.0.3`; they do not declare a separate crypto pod or vendored crypto framework. |
| `flutter_inappwebview_windows`: `windows/CMakeLists.txt` and `windows/in_app_webview/in_app_webview.cpp` | The plugin uses WebView2, including its `Network.getCertificate` protocol method. CMake fetches Microsoft.Web.WebView2 1.0.2792.45, Microsoft.Windows.ImplementationLibrary 1.0.231216.1 and nlohmann.json 3.11.2. Its explicit bundled-library list is empty. These facts describe the adapter and declared build inputs, not the internals of the WebView2 runtime. |
| `flutter_inappwebview_web`: `lib/web/in_app_web_view_web_element.dart`; `flutter_inappwebview_internal_annotations`: `lib/src/` | The web adapter uses browser iframe and `XMLHttpRequest` APIs. The annotations package contains generator annotations and supporting constants; it has no runtime package dependencies. Neither replaces the browser's transport implementation. |

The Android and Apple adapters expose callbacks capable of accepting a server
trust challenge or supplying a client identity. Platform delegation alone is
therefore not a claim that every possible plugin configuration enforces the
same trust policy. The current [native ebook host](../packages/crisp_ebook_reader/lib/src/hosts/host_native.dart)
does not configure those callbacks.

`code_assets` 2.2.0 provides build/link-hook protocol models and output
validation: see `lib/code_assets.dart`, `lib/src/code_assets/extension.dart`,
`code_asset.dart`, `link_mode.dart` and `native_library_validation.dart` within
that package. Its direct dependencies are `collection`, `hooks` and `logging`.
The 2.2.0 change adds complete Apple deployment-version representation. The
ebook converter imports this API in its [build hook](../packages/crisp_ebook_conversion/hook/build.dart)
and hook configuration helper; the converter's runtime exports do not import
that helper. The package describes and validates native-library assets rather
than implementing the conversion or its cryptography. Libraries emitted by
hooks still require their own review, as the Kindling paths do above.

This is a source/manifests review of the pinned adapter packages. Downloaded
Gradle/CocoaPods/NuGet transitive artifacts, platform TLS implementations,
WebView runtimes and final application binaries were not rebuilt or audited
by this dependency-delta check. Their contents cannot be inferred solely from
the absence of a newly named Dart crypto dependency.

### Meaning of the existing export-policy status

`documentation.status: not_required` in the existing Apple policy records the
conditional source assessment described in its reference. It is not an Apple
approval or a government decision; `compliance_code` remains absent. This
technical addition changes no encryption declaration, documentation decision,
France setting, TestFlight audience or distribution-history record.

The source preflight binds three separate inputs: the inventory JSON, the
resolved root `pubspec.lock`, and a canonical SHA-256 map of every
`reviewed_files` entry. Its previous stale-lock failure is therefore expected
after a dependency change. These bindings must reflect the completed reviewed
source and resolved lock; merely copying fresh hashes does not establish a
classification or release approval. Artifact inspection and any required live
submission checks remain separate from this technical inventory.

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
python3 tool/crypto_release_evidence.py --platform android --require-clean --record-generated-metadata \
  --artifact path/to/app.aab --dependencies build/export-compliance/dependencies.json
```

The script records facts; it cannot decide an ECCN, verify store territories,
prove remote source availability, or grant an exemption. Keep an internal
decision for the exact artifacts using the template in the export guide.

`--require-clean` normally rejects every tracked change. Release workflows use
`--record-generated-metadata` to preserve the target's regenerated CocoaPods
lockfile and the Android plugin registrant that `pub get` can regenerate even
on Apple hosts, including each file's original identity, actual
contents, SHA-256 and diff. Authored code, `pubspec.lock`, Podfiles and the macOS
project remain strict. For the iOS project only, Apple's `plutil` must establish
that the complete parsed project data is unchanged before a reserialization can
be recorded. Dictionary ordering and comments may differ; array ordering,
scalar types, build settings, scripts and references must match. Exact original
and built bytes and their diff remain in the evidence. This describes Xcode
project data for this build, not equivalence for every text-based source tool.
Parser failures or changed project data stop the release. Apple build workflows
retain separate source diagnostics on failure so the rejected delta can be
reviewed. A changed native dependency graph still needs release review and
corresponding public source; recording it does not approve it.
The CI target builds exercise this evidence path on their actual artifacts.
The Apple CI builds use the same CocoaPods setting as the store workflows to
avoid unreviewed automatic Swift Package Manager project migrations.

## Technical reference sources

- [RFC 5297: AES-SIV and independent appendix A vectors](https://www.rfc-editor.org/rfc/rfc5297).
- [Cryptomator format architecture](https://docs.cryptomator.org/en/latest/security/architecture/) and [upstream cryptolib](https://github.com/cryptomator/cryptolib).
- [VeraCrypt volume format specification](https://veracrypt.io/en/VeraCrypt%20Volume%20Format%20Specification.html).
- [Dart HttpClient badCertificateCallback semantics](https://api.dart.dev/dart-io/HttpClient/badCertificateCallback.html) and [SecurityContext](https://api.dart.dev/dart-io/SecurityContext-class.html).
- [Microsoft Office cryptography specification](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/).
- [Exact provider/native source provenance](crypto-dependencies.md) and [Filen local patch provenance](../packages/filen_client/UPSTREAM.md).
