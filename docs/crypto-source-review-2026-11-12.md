# KeePass crypto source and export-evidence review

Review date: **2026-11-12**. Implementation baseline:
`77a63a08da6913b444a634b95fe79e62143776c5`.
Previous policy-binding commit:
`01f4b50c215a70a7c6e75adab8eafdf98ef770f6`.
Merged-main reconciliation on the same date:
`977b5037f133cb2d33c57db761864183455a705e`, onto the feature checkpoint
`f8465976e8eea93c7f7d42417d6122303c3d2d3b`.

This record updates source facts and release controls after adding KeePass
database viewing/editing. It is not a government classification, a new Apple
questionnaire result, a live store/distribution check, or verification of a
signed IPA/PKG. Historical store and TestFlight facts retain their original
dates in the policy and export guide.

## Scope and dependency delta

The root lockfile adds one package: path dependency `kpasslib` 1.1.2. Its MIT
upstream is pinned at `81d51d9f3575f72136441ea5a271f6748e3ca77c`; local patches,
copyright notices and the KdbxWeb origin are documented in
[`packages/kpasslib/UPSTREAM.md`](../packages/kpasslib/UPSTREAM.md). PointyCastle
4.0.0 and the other support packages were already resolved. No dependency was
upgraded to add this feature.

The new app path decrypts existing KDBX 3.0/3.1/4.0/4.1 databases using a password,
key file or both, exposes standard entry fields, and encrypts modified databases.
The reachable algorithms and precise distinction between KDBX3 checks and
KDBX4 authentication are recorded in
[crypto-dependencies.md](crypto-dependencies.md#keepass-kdbx-databases).
Argon2d/Argon2id now has an explicit database-unlock/save path through the
existing PointyCastle library; KPassLib supplies the AES/ChaCha20/Salsa20
implementation used by its default pure-Dart engine. Retained upstream FFI
adapter source is not activated by the app. No KPassLib native binary is added.

The app adapters restrict accepted format/KDF values, reject excessive work
before derivation, preserve unedited XML/history/attachments, and save with
fresh encryption randomness. The dedicated UI keeps lock checkpoints encrypted
in memory, saves to the captured original target, and does not use plaintext
text-editor recovery storage. These are source and targeted-test findings, not
a claim of guaranteed process-memory erasure or an independent crypto audit.
See [keepass.md](keepass.md) for the supported subset and limits.

The initial KeePass review increased the inventory from **128 to 191 bound files**:

- All 47 vendored Dart runtime files, including unused/conditional adapters,
  plus the vendor manifest, provenance record and two license notices.
- Ten app files covering the backend, UI/localization, viewer/editor routing,
  byte loading, captured source targets, save coordination and storage references.
- The optional Rust SMB build hook and library-location helper, previously
  outside the bound set and now reached by an existing reviewed loader.

Binding a retained source file does not assert that it is used by every platform
or that its complete implementation was independently security-audited. It
prevents a later local change from retaining this exact source fingerprint.

## Intervening changes in previously bound files

The prior 128-file fingerprint was reproduced exactly from Git objects at
`01f4b50`. The following source differences were inspected before refreshing it:

| Previously bound path or group | Change and crypto implication |
| --- | --- |
| `pubspec.yaml` | Adds only the pinned local KPassLib dependency; `pubspec.lock` adds its path/version record. |
| `lib/widgets/internal_viewer_dialog.dart` | Routes KDBX to the dedicated read-only viewer and adds bounded decoded email viewing/search plus legacy Word conversion actions. The KeePass path delegates crypto to the dedicated session, rather than editing encrypted bytes as decoded text. |
| `rust_smb_session.dart`, `smb_session.dart`, `smb_session_web.dart` | Adds bundled-library discovery/diagnostics, an eight-handle queue and corrected progress reporting. The optional loader can find a bridge built by the source hook; explicit developer library overrides already existed. No cipher or authentication suite is changed in this delta. |
| Rust `native/crisp_smb/src/lib.rs` and bridge `rust/src/api/mod.rs` | Adds a progress-started flag and encodes progress as zero before initialization, then bytes plus one. No new crypto operation. |
| `packages/crisp_storage/pubspec.yaml` | Adds already-resolved `code_assets` and `hooks` support for the optional Rust bridge build hook. |
| `tool/testflight_export_guard.rb` | Now independently rejects missing/pending documentation decisions and inconsistent no-documentation codes before API reads/writes. The entry script already invoked the stricter Python submission validation. |

The newly bound SMB hook is disabled unless `rust_smb` is enabled by the app.
When enabled it uses locked Cargo inputs, or a configured prebuilt library.
No `rust_smb` or prebuilt-library override is present in the reviewed root
manifest. The new helper and hook are source-bound because they affect which
native code may be packaged or loaded; an enabled or replaced binary still
requires the existing artifact/dependency evidence review. No Apple Rust-SMB
artifact was built or inspected in this update.

## Reconciliation with current main

The subsequent merge retains the Rust Filen/Internxt engine inventory from
`main` at `977b5037f133cb2d33c57db761864183455a705e` (PRs #57 and #56), alongside
the KeePass entry and package. Main's recorded **144-file** source fingerprint,
last refreshed in `62e438e6836949207b4541b818c1c261bb7104fe`, was reproduced
exactly from its Git objects. The feature branch's **191-file** fingerprint was
also reproduced before the merge. The combined inventory contains their union:
**207 unique bound files**, retaining all 16 main-only Rust cloud paths and all
63 feature-only additions.

The Rust engine algorithm/dependency descriptions are inherited source records,
not a new independent audit of that implementation. Main's changes to the
already-bound build hook and library-location helper were inspected: they add
the optional `rust_cloud` bridge alongside `rust_smb`, retain explicit enabling,
locked Cargo builds/prebuilt-library choices, and select bridge-specific library
names. Neither hook is enabled in the root manifest. Root `pubspec.lock` remains
identical to the KeePass checkpoint; main's separate CLI dependency/source
changes remain part of its inherited evidence. No Rust cloud native artifact
was built or checked by this reconciliation.

The policy keeps `documentation.status: unreviewed`, the proposed false plist
declaration and a null compliance code. It does not restore main's older
`not_required` decision. Historical France/TestFlight facts remain unchanged.
The merged whole-app questionnaire/classification decision and exact release
artifact still require their existing checks; reproducing source hashes is not
approval to distribute.

## Declarations and regulatory review

Apple's export overview, documentation table and plist guidance were read on
2026-11-12. The BIS Part 740 page displayed a current-eCFR date of 2026-11-11;
the 2021 reporting-change table and BIS's March 2017 FAQ were checked to avoid
equating older broad overview wording with the current reporting rule. Exact
links are retained in [the export guide](export-compliance.md#official-sources).

KeePass is a confidentiality feature. Neither an authentication-only nor an
Apple-OS-only description matches this source. A dependency's MIT license or
published format does not classify the complete application. The finished-app
mass-market route remains a proposal requiring reassessment; adding the vault
feature does not on its own establish mandatory CCATS or annual reporting.
The guide distinguishes current §740.17(e)(3) reporting scope from the former
Category 5 Part 2 Note 4 ancillary-use exclusion.

There is **no retained post-KeePass Apple questionnaire result**. Consequently:

- `documentation.status` changes from `not_required` to `unreviewed` and its
  reference identifies this missing decision.
- The source plist values and `uses_non_exempt_encryption` stay `false` as the
  proposed declaration. No code, filing reference or exemption is invented.
- France availability/history and TestFlight recipient settings are unchanged;
  their recorded November 8 evidence is not renewed by this source review.
- Source-evidence collection is allowed, while Apple upload and external
  TestFlight distribution reject the pending questionnaire state.

Before submission, retain the updated whole-app classification rationale and
actual App Store Connect questionnaire outcome. If documentation is required,
obtain it and the Apple-issued compliance code before changing the policy and
packaged plist values together. The exact artifact and live-account gates
still apply. This review made no store API mutation and filed no declaration.

## Evidence fingerprints

The source fingerprint uses the existing validator's SHA-256 of compact sorted
JSON mapping each reviewed path to the SHA-256 of its bytes. No hashing rule or
source-consistency check is relaxed.

| Input | Reviewed SHA-256 |
| --- | --- |
| Previous 128-file source fingerprint, reproduced from Git | `3a9b99d368b1614c26fba27a3e8cb70d5f358521f4451ab2df7db2ce1c8c7fe3` |
| Initial KeePass `docs/crypto-inventory.json` | `cce8b35595fc1351cc672987af20d893b4db88debd5a109196d70acaaf3963b4` |
| Current `pubspec.lock` | `eb7003cf2ea16082c263ca8912090b362a5065640f7fb2e42383ef8da0021a2f` |
| Initial KeePass 191-file source fingerprint, reproduced before merge | `8c74e512381d59c43f98a0dd5227cdbed24a72f62649189aa3214bfe0c4b7734` |
| Main's 144-file source fingerprint, reproduced at `977b503` | `80a040a7b19c93c0203c2612168a698a07cfcc2a3333e5af09be30116e82f8cc` |
| Merged `docs/crypto-inventory.json` | `87daa40bfe8f76ab097c19896902f6189a597c91d65bce505ad132024a593013` |
| Merged 207-file source fingerprint | `0fc9c45bca156ff7924ceceb333a004111dde6efa4a61b25fa95069ae74fcf9c` |

These identify source facts. They do not renew external approvals or establish
correspondence with a signed or uploaded binary.

## Validation of this update

- `test_apple_export_preflight.py`: **38 passed**, including pending-questionnaire
  rejection before any live API read while offline artifact inspection remains
  available.
- `test_crypto_release_evidence.py`: **40 passed, 2 skipped**. The skips require
  Apple's actual `plutil`; the new case permits source evidence without claiming
  distribution approval while the questionnaire is pending.
- Ruby guard regressions were added for pending documentation and inconsistent
  false/code combinations. **Not run locally:** Ruby is not installed in this
  environment. The existing CI Ruby step must run them at the committed revision.
- The CI desktop crypto gate and iOS/macOS/Play crypto test lists now include
  `keepass_crypto_test.dart` and `keepass_service_test.dart`. Their earlier
  feature-validation results are in [crypto-audit.md](crypto-audit.md); this
  documentation update does not relabel them as a new hosted run.

After writing the fingerprints, `crypto_release_evidence.py --check` passed,
both source plists matched the proposed policy, and submission validation failed
with the expected request to complete the Apple encryption questionnaire. All
four edited workflow files parsed successfully and included both KeePass tests;
`git diff --check` passed. A clean committed checkout and successful hosted
checks are still required before producing release evidence.

After the merged-main reconciliation, both Python suites were rerun with the
same results (**38 passed**; **40 passed, 2 platform skips**).
`crypto_release_evidence.py --check` passed against the 207-file binding. Both
source plists still matched the proposed declaration, and submission validation
again rejected the missing questionnaire result. No live Apple API was called.

---

# Ebook source and dependency review — 12 November 2026

This engineering review records the ebook additions on
`feature/ebook-reader-editor`, including the portable reader, EPUB text
correction, native Kindle conversion and browser metadata worker. It updates
the exact source bindings used by
[apple-export-policy.json](apple-export-policy.json). The baseline for the
delta is main at
[`4946a9a29b4cec0dd8a2efd3cb0b3200d620f39c`](https://github.com/CrispStrobe/CrispCloud/commit/4946a9a29b4cec0dd8a2efd3cb0b3200d620f39c).

The policy's application identity, encryption declaration, documentation
decision, France records and TestFlight records retain their existing values
and their dated evidence. The review date here describes this source review.
No live distribution review, Apple approval, legal classification, upload or
deployment was performed. The existing artifact and live submission checks
remain separate requirements.

## Source delta

The [inventory](crypto-inventory.json) retains all **128** previously reviewed
paths and adds **49**, for **177** unique paths. Exact-byte comparison against
the baseline found changes in three previously listed files; the other 125
match it.

| Existing input | Reviewed change |
| --- | --- |
| `lib/main.dart` | Registers the bundled ebook dependency notices with Flutter's license registry. |
| `lib/widgets/internal_viewer_dialog.dart` | Routes recognized ebook inputs to the ebook dialog, retaining the captured source, supplied bytes and adjacent-file navigation. |
| `pubspec.yaml` | Adds the three local ebook packages. Temporary local test hooks are removed before binding this file. |

The new inventory paths cover the EPUB container and editing logic, annotation
identity, embedded-reader session and hosts, bundled Foliate/ZIP code, native
conversion entry points, shared metadata engine, browser worker and Wasm
artifact, and their pinned manifests, locks and provenance. The exact path list
is in `reviewed_files`; it does not claim that every application or dependency
source file received a new audit.

The [technical audit](crypto-audit.md#12-november-2026-ebook-technical-inventory-extension)
records algorithm use and reachability:

- SHA-256 identifies source versions and rejects stale text edits; it does not
  encrypt annotations or ebooks. Embedded-reader sessions use `Random.secure()`.
- Standard EPUB and MOBI font compatibility uses the recorded SHA-1/XOR or
  record-key XOR mechanisms. It does not add general ebook DRM decryption.
- Kindling contains MD5 compatibility hashes, including the title hash reached
  by native and browser metadata correction.
- Bundled zip.js contains AES, PBKDF2-HMAC-SHA1, HMAC and ZipCrypto code. The
  ebook loader rejects encrypted entries before requesting their data. The
  native Rust ZIP dependency has AES features disabled and passwordless reads
  reject encryption, while ZipCrypto source remains in the dependency.
- The bundled metadata Wasm has no host imports. Its broader locked source
  graph still contains random-number and wasm-bindgen dependencies; an empty
  import list does not establish an absence of internal hashes or algorithms.

The worker's default asset path is same-origin, and every request uses a fresh
worker and a private input snapshot. Timeout and cancellation terminate that
worker. Native library/executable overrides and custom worker assets require
separate provenance; a matching version string cannot establish their bytes.

## Resolved dependency delta

The complete root `pubspec.lock` is bound separately. Relative to the baseline,
it adds the three local ebook packages and eight pinned
`flutter_inappwebview`-family packages, and updates `code_assets` from 2.1.0 to
2.2.0. Other locked entries are unchanged. The new WebView family is:

| Package | Locked version |
| --- | --- |
| `flutter_inappwebview` | 6.1.5 |
| `flutter_inappwebview_android` | 1.1.3 |
| `flutter_inappwebview_ios` | 1.1.2 |
| `flutter_inappwebview_macos` | 1.1.2 |
| `flutter_inappwebview_web` | 1.1.2 |
| `flutter_inappwebview_windows` | 0.6.0 |
| `flutter_inappwebview_platform_interface` | 1.3.0+1 |
| `flutter_inappwebview_internal_annotations` | 1.3.0 |

The exact native and Wasm Cargo graphs are separately locked and included in
the source binding. Their reviewed license union and vendored source hashes
are checked by the converter's existing verification tools. This scope also
includes the browser asset itself and `WASM.json`, which binds the build
inputs, worker/runtime source and output checksum.

The [reader-plugin appendix](crypto-audit.md#resolved-reader-plugin-and-build-hook-delta)
records inspection of the exact newly resolved package sources. It distinguishes
the Dart DER/X.509 accessors from certificate and TLS operations delegated to
Android, Apple, WebView2 or the browser, and identifies the native dependency
manifests examined. `code_assets` provides build/link-hook models and validation;
the converter's runtime exports do not import its hook helper. This dependency
review does not inspect downloaded native transitive artifacts, platform TLS
internals or a finished application binary.

## Binding and validation

The policy records SHA-256 fingerprints for the inventory's exact bytes, the
complete root lockfile, and a canonical sorted map from every reviewed source
path to its file digest. These values use the existing
[`apple_export_preflight.py`](../tool/apple_export_preflight.py) implementation;
the validator and its acceptance rules are unchanged.

Any later edit to a bound source, dependency lock or inventory requires another
delta review. These source checks establish consistency with this technical
record. Artifact verification and live distribution checks are still required
for a release; a source fingerprint does not establish either result.

Local validation retained the existing failure-path tests and acceptance rules:

- `test_crypto_release_evidence.py`: 41 tests completed, with its two existing
  platform-dependent skips.
- `test_apple_export_preflight.py`: all 37 tests passed.
- `crypto_release_evidence.py --check`: passed against the reviewed source,
  inventory and complete root lockfile.

These results describe source inputs only. Hosted checks for the final branch
revision and target-device verification have their own status in the
[ebook recovery record](recovery/ebook-extension-2026-11-12.md).

## Refreshed fingerprints

These exact inputs include the shared Kindle metadata fixes and rebuilt Wasm
from checkpoint `47e83b0`. The root pubspec matches its committed bytes.

```json
{
  "inventory_sha256": "72775c1d906199251ad1893e8dfbd46c4bf3c9752c1369e73a6d79dbd23d7008",
  "pubspec_lock_sha256": "3b1a93697f3b0c8b43fb436989247219524baa00b6f2357c75bac8fabb0a9673",
  "reviewed_source_sha256": "0f3fea3dfbeff4838ea640ab408c438a8a355e03fc92b3ebdf9a3ab781ada19d"
}
```


# KeePass crypto source and export-evidence review

Review date: **2026-11-12**. Implementation baseline:
`77a63a08da6913b444a634b95fe79e62143776c5`.
Previous policy-binding commit:
`01f4b50c215a70a7c6e75adab8eafdf98ef770f6`.
Merged-main reconciliation on the same date:
`977b5037f133cb2d33c57db761864183455a705e`, onto the feature checkpoint
`f8465976e8eea93c7f7d42417d6122303c3d2d3b`.

This record updates source facts and release controls after adding KeePass
database viewing/editing. It is not a government classification, a new Apple
questionnaire result, a live store/distribution check, or verification of a
signed IPA/PKG. Historical store and TestFlight facts retain their original
dates in the policy and export guide.

## Scope and dependency delta

The root lockfile adds one package: path dependency `kpasslib` 1.1.2. Its MIT
upstream is pinned at `81d51d9f3575f72136441ea5a271f6748e3ca77c`; local patches,
copyright notices and the KdbxWeb origin are documented in
[`packages/kpasslib/UPSTREAM.md`](../packages/kpasslib/UPSTREAM.md). PointyCastle
4.0.0 and the other support packages were already resolved. No dependency was
upgraded to add this feature.

The new app path decrypts existing KDBX 3.0/3.1/4.0/4.1 databases using a password,
key file or both, exposes standard entry fields, and encrypts modified databases.
The reachable algorithms and precise distinction between KDBX3 checks and
KDBX4 authentication are recorded in
[crypto-dependencies.md](crypto-dependencies.md#keepass-kdbx-databases).
Argon2d/Argon2id now has an explicit database-unlock/save path through the
existing PointyCastle library; KPassLib supplies the AES/ChaCha20/Salsa20
implementation used by its default pure-Dart engine. Retained upstream FFI
adapter source is not activated by the app. No KPassLib native binary is added.

The app adapters restrict accepted format/KDF values, reject excessive work
before derivation, preserve unedited XML/history/attachments, and save with
fresh encryption randomness. The dedicated UI keeps lock checkpoints encrypted
in memory, saves to the captured original target, and does not use plaintext
text-editor recovery storage. These are source and targeted-test findings, not
a claim of guaranteed process-memory erasure or an independent crypto audit.
See [keepass.md](keepass.md) for the supported subset and limits.

The initial KeePass review increased the inventory from **128 to 191 bound files**:

- All 47 vendored Dart runtime files, including unused/conditional adapters,
  plus the vendor manifest, provenance record and two license notices.
- Ten app files covering the backend, UI/localization, viewer/editor routing,
  byte loading, captured source targets, save coordination and storage references.
- The optional Rust SMB build hook and library-location helper, previously
  outside the bound set and now reached by an existing reviewed loader.

Binding a retained source file does not assert that it is used by every platform
or that its complete implementation was independently security-audited. It
prevents a later local change from retaining this exact source fingerprint.

## Intervening changes in previously bound files

The prior 128-file fingerprint was reproduced exactly from Git objects at
`01f4b50`. The following source differences were inspected before refreshing it:

| Previously bound path or group | Change and crypto implication |
| --- | --- |
| `pubspec.yaml` | Adds only the pinned local KPassLib dependency; `pubspec.lock` adds its path/version record. |
| `lib/widgets/internal_viewer_dialog.dart` | Routes KDBX to the dedicated read-only viewer and adds bounded decoded email viewing/search plus legacy Word conversion actions. The KeePass path delegates crypto to the dedicated session, rather than editing encrypted bytes as decoded text. |
| `rust_smb_session.dart`, `smb_session.dart`, `smb_session_web.dart` | Adds bundled-library discovery/diagnostics, an eight-handle queue and corrected progress reporting. The optional loader can find a bridge built by the source hook; explicit developer library overrides already existed. No cipher or authentication suite is changed in this delta. |
| Rust `native/crisp_smb/src/lib.rs` and bridge `rust/src/api/mod.rs` | Adds a progress-started flag and encodes progress as zero before initialization, then bytes plus one. No new crypto operation. |
| `packages/crisp_storage/pubspec.yaml` | Adds already-resolved `code_assets` and `hooks` support for the optional Rust bridge build hook. |
| `tool/testflight_export_guard.rb` | Now independently rejects missing/pending documentation decisions and inconsistent no-documentation codes before API reads/writes. The entry script already invoked the stricter Python submission validation. |

The newly bound SMB hook is disabled unless `rust_smb` is enabled by the app.
When enabled it uses locked Cargo inputs, or a configured prebuilt library.
No `rust_smb` or prebuilt-library override is present in the reviewed root
manifest. The new helper and hook are source-bound because they affect which
native code may be packaged or loaded; an enabled or replaced binary still
requires the existing artifact/dependency evidence review. No Apple Rust-SMB
artifact was built or inspected in this update.

## Reconciliation with current main

The subsequent merge retains the Rust Filen/Internxt engine inventory from
`main` at `977b5037f133cb2d33c57db761864183455a705e` (PRs #57 and #56), alongside
the KeePass entry and package. Main's recorded **144-file** source fingerprint,
last refreshed in `62e438e6836949207b4541b818c1c261bb7104fe`, was reproduced
exactly from its Git objects. The feature branch's **191-file** fingerprint was
also reproduced before the merge. The combined inventory contains their union:
**207 unique bound files**, retaining all 16 main-only Rust cloud paths and all
63 feature-only additions.

The Rust engine algorithm/dependency descriptions are inherited source records,
not a new independent audit of that implementation. Main's changes to the
already-bound build hook and library-location helper were inspected: they add
the optional `rust_cloud` bridge alongside `rust_smb`, retain explicit enabling,
locked Cargo builds/prebuilt-library choices, and select bridge-specific library
names. Neither hook is enabled in the root manifest. Root `pubspec.lock` remains
identical to the KeePass checkpoint; main's separate CLI dependency/source
changes remain part of its inherited evidence. No Rust cloud native artifact
was built or checked by this reconciliation.

The policy keeps `documentation.status: unreviewed`, the proposed false plist
declaration and a null compliance code. It does not restore main's older
`not_required` decision. Historical France/TestFlight facts remain unchanged.
The merged whole-app questionnaire/classification decision and exact release
artifact still require their existing checks; reproducing source hashes is not
approval to distribute.

## Declarations and regulatory review

### KeePass editing follow-up

The subsequent editor increment adds group creation/renaming/moving/deletion,
entry moves, custom-field viewing/editing (including protected values), and
history inspection/restoration. It continues to operate on existing databases
through the same retained XML document, KPassLib engine and PointyCastle Argon2
adapter. There is no new cipher, KDF, cryptographic dependency, native binary,
master-key change or format downgrade. Saves retain the existing vault's
version/cipher/compression/KDF parameters and use the established fresh-randomness
encryption path. History restoration retains the displaced current entry;
custom-field protection uses the existing inner protected-value mechanism.

Source-bound encrypted saves and encrypted in-memory lock checkpoints still
apply. Protected custom values and historical passwords require explicit reveal
or copy; history/group dialogs close on lock. New service/widget regressions
exercise encrypted round trips and preservation. These are implementation tests,
not a fresh independent cryptographic audit or an export classification. The
expanded editing surface does not resolve the pending whole-app questionnaire.
Its changed bound files are included in the refreshed source fingerprint
below. Earlier fingerprints remain historical checkpoints; the updated source
binding does not approve distribution.

### Retained classification and store state

Apple's export overview, documentation table and plist guidance were read on
2026-11-12. The BIS Part 740 page displayed a current-eCFR date of 2026-11-11;
the 2021 reporting-change table and BIS's March 2017 FAQ were checked to avoid
equating older broad overview wording with the current reporting rule. Exact
links are retained in [the export guide](export-compliance.md#official-sources).

KeePass is a confidentiality feature. Neither an authentication-only nor an
Apple-OS-only description matches this source. A dependency's MIT license or
published format does not classify the complete application. The finished-app
mass-market route remains a proposal requiring reassessment; adding the vault
feature does not on its own establish mandatory CCATS or annual reporting.
The guide distinguishes current §740.17(e)(3) reporting scope from the former
Category 5 Part 2 Note 4 ancillary-use exclusion.

There is **no retained post-KeePass Apple questionnaire result**. Consequently:

- `documentation.status` changes from `not_required` to `unreviewed` and its
  reference identifies this missing decision.
- The source plist values and `uses_non_exempt_encryption` stay `false` as the
  proposed declaration. No code, filing reference or exemption is invented.
- France availability/history and TestFlight recipient settings are unchanged;
  their recorded November 8 evidence is not renewed by this source review.
- Source-evidence collection is allowed, while Apple upload and external
  TestFlight distribution reject the pending questionnaire state.

Before submission, retain the updated whole-app classification rationale and
actual App Store Connect questionnaire outcome. If documentation is required,
obtain it and the Apple-issued compliance code before changing the policy and
packaged plist values together. The exact artifact and live-account gates
still apply. This review made no store API mutation and filed no declaration.

## Evidence fingerprints

The source fingerprint uses the existing validator's SHA-256 of compact sorted
JSON mapping each reviewed path to the SHA-256 of its bytes. No hashing rule or
source-consistency check is relaxed.

| Input | Reviewed SHA-256 |
| --- | --- |
| Previous 128-file source fingerprint, reproduced from Git | `3a9b99d368b1614c26fba27a3e8cb70d5f358521f4451ab2df7db2ce1c8c7fe3` |
| Initial KeePass `docs/crypto-inventory.json` | `cce8b35595fc1351cc672987af20d893b4db88debd5a109196d70acaaf3963b4` |
| Current `pubspec.lock` | `eb7003cf2ea16082c263ca8912090b362a5065640f7fb2e42383ef8da0021a2f` |
| Initial KeePass 191-file source fingerprint, reproduced before merge | `8c74e512381d59c43f98a0dd5227cdbed24a72f62649189aa3214bfe0c4b7734` |
| Main's 144-file source fingerprint, reproduced at `977b503` | `80a040a7b19c93c0203c2612168a698a07cfcc2a3333e5af09be30116e82f8cc` |
| Merged `docs/crypto-inventory.json` | `87daa40bfe8f76ab097c19896902f6189a597c91d65bce505ad132024a593013` |
| Merged 207-file source fingerprint | `0fc9c45bca156ff7924ceceb333a004111dde6efa4a61b25fa95069ae74fcf9c` |
| Extended editing/viewer inventory | `4d8ef6d4c9a55f9cb5a1cbfabb317c7cb6f34e70d8604c863c8d92e81f92e810` |
| Extended editing/viewer 207-file source fingerprint | `80ad902d45a2de4458d10d412b43684e6ac082122876d7ffa40c79b216e32857` |

These identify source facts. They do not renew external approvals or establish
correspondence with a signed or uploaded binary.

## Validation of this update

- `test_apple_export_preflight.py`: **38 passed**, including pending-questionnaire
  rejection before any live API read while offline artifact inspection remains
  available.
- `test_crypto_release_evidence.py`: **40 passed, 2 skipped**. The skips require
  Apple's actual `plutil`; the new case permits source evidence without claiming
  distribution approval while the questionnaire is pending.
- Ruby guard regressions were added for pending documentation and inconsistent
  false/code combinations. **Not run locally:** Ruby is not installed in this
  environment. The existing CI Ruby step must run them at the committed revision.
- The CI desktop crypto gate and iOS/macOS/Play crypto test lists now include
  `keepass_crypto_test.dart` and `keepass_service_test.dart`. Their earlier
  feature-validation results are in [crypto-audit.md](crypto-audit.md); this
  documentation update does not relabel them as a new hosted run.

After writing the fingerprints, `crypto_release_evidence.py --check` passed,
both source plists matched the proposed policy, and submission validation failed
with the expected request to complete the Apple encryption questionnaire. All
four edited workflow files parsed successfully and included both KeePass tests;
`git diff --check` passed. A clean committed checkout and successful hosted
checks are still required before producing release evidence.

After the merged-main reconciliation, both Python suites were rerun with the
same results (**38 passed**; **40 passed, 2 platform skips**).
`crypto_release_evidence.py --check` passed against the 207-file binding. Both
source plists still matched the proposed declaration, and submission validation
again rejected the missing questionnaire result. No live Apple API was called.


## Validation of the further extensions

The group, protected custom-field and history UI is covered by **46 unique
KeePass checks** across focused runs: 26 backend/crypto, 19 widget and one
localization test. The new backend suite is also included in the desktop, iOS,
macOS and Play crypto gates. No dependency, vendor crypto implementation,
accepted cipher/KDF or retained vault parameter changed in this increment.

The updated viewer integration and KeePass files remain in the same **207-file**
binding. The current inventory and source fingerprints appear above; the
resolved root lockfile remains unchanged. Both Python suites passed again
(**38 passed**; **40 passed, 2 Apple-plutil skips**), the source evidence check
passed, and both source plists matched the existing proposed declaration.
Submission validation still rejects the missing whole-app questionnaire
result. No Apple API call, store declaration, distribution change or filing
was made.

The existing workspace CI gate formats every Dart file changed by the PR,
including the new vendored package. The Dart 3.13.7 formatter normalized the
remaining vendor and authored-file layout; this is recorded in KPassLib's
provenance file. It changes no algorithms or copyright/license notices. All
141 PR Dart files then passed the formatter without changes, and all 26
KeePass backend/crypto tests passed again. The current source fingerprint
includes those exact formatted bytes and the updated provenance record.

A final dialog-lifecycle review found that Flutter can continue painting a
popped history dialog during its reverse animation. A route-local notifier
now removes its sensitive content on lock even when the route is no longer
active. Both KeePass widget suites passed **19 tests**, including explicit
password/custom-field reveal, Close without settling, an inactive event, and
the first rendered frame. The source fingerprint below the historical entries
includes this correction; no crypto algorithm or release declaration changed.

## Structured binary Word follow-up

The built-in DOC/DOT parser and structured DOCX conversion add no crypto
algorithm, KDF, provider, or runtime dependency. The only changed file in the
existing 207-file bound inventory is `lib/widgets/preview_pane.dart`: DOC/DOT
now use the same generated-HTML preview route as the other portable formats.
The source-account/token checks and KeePass branch are unchanged. The JSDoc
0BSD parsing adaptations and their license are documented separately.

The inventory and lockfile hashes remain unchanged. The updated 207-file
source fingerprint is `d089a2d5138e8a53f5bcdbc0a2fefc709d886805223aeb2ff9c21560f4fe4237`. This records the current source bytes; Apple
documentation remains `unreviewed`, and submission still requires the completed
questionnaire result. No store declaration, territory setting or filing was
changed by this document-format work.


# Ebook source and dependency review — 12 November 2026

This engineering review records the ebook additions on
`feature/ebook-reader-editor` and their subsequent extension on
`checkpoint/ebook-parity-2026-11-12`. It covers the portable reader, EPUB text
correction, native Kindle conversion and browser metadata worker, followed by
reading-data transfer, the local library, shared controls and the optional
Linux WebKitGTK host. It updates the exact source bindings used by
[apple-export-policy.json](apple-export-policy.json). The baseline for the
delta is main at
[`4946a9a29b4cec0dd8a2efd3cb0b3200d620f39c`](https://github.com/CrispStrobe/CrispCloud/commit/4946a9a29b4cec0dd8a2efd3cb0b3200d620f39c).

The policy's application identity, encryption declaration, documentation
decision, France records and TestFlight records retain their existing values
and their dated evidence. The review date here describes this source review.
No live distribution review, Apple approval, legal classification, upload or
deployment was performed. The existing artifact and live submission checks
remain separate requirements.

## Source delta

The initial ebook review retained all **128** previously reviewed paths and
added **49**, for **177** unique paths. The follow-on review retains all 177
and adds **30**, bringing the [inventory](crypto-inventory.json) to **207**
unique paths. The initial exact-byte comparison against the main baseline
found changes in three of its previously listed files; the other 125 matched.

| Existing input | Reviewed change |
| --- | --- |
| `lib/main.dart` | Registers the bundled ebook dependency notices with Flutter's license registry. |
| `lib/widgets/internal_viewer_dialog.dart` | Routes recognized ebook inputs to the ebook dialog, retaining the captured source, supplied bytes and adjacent-file navigation. |
| `pubspec.yaml` | Adds the three local ebook packages. Temporary local test hooks are removed before binding this file. |

The initial 49 added paths cover the EPUB container and editing logic, annotation
identity, embedded-reader session and hosts, bundled Foliate/ZIP code, native
conversion entry points, shared metadata engine, browser worker and Wasm
artifact, and their pinned manifests, locks and provenance. The exact path list
is in `reviewed_files`; it does not claim that every application or dependency
source file received a new audit.

The [technical audit](crypto-audit.md#12-november-2026-ebook-technical-inventory-extension)
records algorithm use and reachability:

- SHA-256 identifies source versions and rejects stale text edits; it does not
  encrypt annotations or ebooks. Embedded-reader sessions use `Random.secure()`.
- Standard EPUB and MOBI font compatibility uses the recorded SHA-1/XOR or
  record-key XOR mechanisms. It does not add general ebook DRM decryption.
- Kindling contains MD5 compatibility hashes, including the title hash reached
  by native and browser metadata correction.
- Bundled zip.js contains AES, PBKDF2-HMAC-SHA1, HMAC and ZipCrypto code. The
  ebook loader rejects encrypted entries before requesting their data. The
  native Rust ZIP dependency has AES features disabled and passwordless reads
  reject encryption, while ZipCrypto source remains in the dependency.
- The bundled metadata Wasm has no host imports. Its broader locked source
  graph still contains random-number and wasm-bindgen dependencies; an empty
  import list does not establish an absence of internal hashes or algorithms.

The worker's default asset path is same-origin, and every request uses a fresh
worker and a private input snapshot. Timeout and cancellation terminate that
worker. Native library/executable overrides and custom worker assets require
separate provenance; a matching version string cannot establish their bytes.

## Follow-on reader source delta

The second review starts from `8893689`, after the first ebook source binding.
Six of the 177 previously bound paths change in this increment:

| Previously bound path | Reviewed extension |
| --- | --- |
| `lib/services/ebook_annotations.dart` | Explicit content/renderer binding, transfer snapshots and preview fingerprints, atomic import publication, and an in-process stale-instance write guard. |
| `lib/widgets/ebook_editor_dialog.dart` | Library recording, import/export preview and recovery, shared appearance/navigation controls, and runtime selection. Sidecars are flushed before opening the library and reloaded afterward; failed local saves leave a rescue-export path. |
| `packages/crisp_ebook_reader/pubspec.yaml` | Linux plugin registration and the SDK `integration_test` development dependency; no added production Dart dependency. |
| `packages/crisp_ebook_reader/assets/reader.js` | Bounded appearance settings, renderer capability/history events, serialized navigation, guarded rendering during iframe creation, and the compatibility-module import. |
| `packages/crisp_ebook_reader/lib/src/reader.dart` | Appearance updates and navigation-history events under the existing session/message checks. |
| `packages/crisp_ebook_reader/lib/src/hosts/host_native.dart` | Routes Linux to the native host; other native hosts retain their existing WebView path. |

The 30 newly bound paths include transfer/library services and dialogs, the
source-reference and lock helpers they use, portable locator/control code,
public reader models/controller/host routing, both new JavaScript modules,
the Linux plugin/CMake/header sources, generated application registration,
and Debian runtime recommendations. Some were existing helpers newly inspected
for these call paths. This is a bounded review of their role in the extension,
not a claim that all unrelated code in those files has received a fresh audit.

The [reading-data audit](crypto-audit.md#reading-data-exchange-library-identities-and-shared-reader-controls)
records three new uses of the existing SHA-256 implementation: exact content
identity, canonical snapshot fingerprints, and catalog IDs derived from source
or attachment tuples. The format is plain JSON, without account, source-path
or credential fields; its digest does not authenticate the sender. Imports
require the exact content hash, byte length and renderer, and their complete
validated result is persisted before it replaces the live model. A local
index may retain exact persistent file references, but they confer no access.
Reopening resolves the original account/root and rechecks it after stat.

The source checks enforce a 2 MiB transfer limit, a 16-level nesting bound,
500 bookmarks/highlights per collection, and a separate 1,000-entry/4 MiB
catalog limit. The same-process preference lock/stale checks are not a
cross-process or cross-tab transaction, encryption, or authenticated storage.
No provider-side sync is introduced. Appearance accepts bounded values and
allowlisted choices, and the grouping compatibility helpers perform no I/O
or cryptography. Existing CSP, publication sanitization, font compatibility
and encrypted-archive rejection remain in place.

The [Linux adapter review](crypto-audit.md#optional-linux-webkitgtk-host)
records the dynamically loaded system `libwebkit2gtk-4.1.so.0` runtime
(version 2.48.4 or newer), GTK3/gmodule and optional epoxy linkage, ephemeral
context, required WebKit sandbox, session-scoped loopback bridge, bounded
snapshots and engine-lifetime texture pool. The package bundles no WebKit
runtime. The Debian script recommends the system runtime; it does not pin
its bytes. Installed WebKit/JavaScriptCore and their transitive TLS/crypto
libraries are outside this source-only check. Runtime capability probing and
source tests do not establish that a finished native build works on every
Linux distribution or on the oldest permitted WebKit version.

## Resolved dependency delta

The complete root `pubspec.lock` is bound separately. Relative to the baseline,
it adds the three local ebook packages and eight pinned
`flutter_inappwebview`-family packages, and updates `code_assets` from 2.1.0 to
2.2.0. Other locked entries are unchanged. The new WebView family is:

| Package | Locked version |
| --- | --- |
| `flutter_inappwebview` | 6.1.5 |
| `flutter_inappwebview_android` | 1.1.3 |
| `flutter_inappwebview_ios` | 1.1.2 |
| `flutter_inappwebview_macos` | 1.1.2 |
| `flutter_inappwebview_web` | 1.1.2 |
| `flutter_inappwebview_windows` | 0.6.0 |
| `flutter_inappwebview_platform_interface` | 1.3.0+1 |
| `flutter_inappwebview_internal_annotations` | 1.3.0 |

The exact native and Wasm Cargo graphs are separately locked and included in
the source binding. Their reviewed license union and vendored source hashes
are checked by the converter's existing verification tools. This scope also
includes the browser asset itself and `WASM.json`, which binds the build
inputs, worker/runtime source and output checksum.

The [reader-plugin appendix](crypto-audit.md#resolved-reader-plugin-and-build-hook-delta)
records inspection of the exact newly resolved package sources. It distinguishes
the Dart DER/X.509 accessors from certificate and TLS operations delegated to
Android, Apple, WebView2 or the browser, and identifies the native dependency
manifests examined. `code_assets` provides build/link-hook models and validation;
the converter's runtime exports do not import its hook helper. This dependency
review does not inspect downloaded native transitive artifacts, platform TLS
internals or a finished application binary.

The follow-on reader extension leaves the root `pubspec.lock` unchanged from
the initial ebook review. The Linux system dependencies above are additional
native build/runtime inputs, not newly resolved Dart packages.

## Binding and validation

The policy records SHA-256 fingerprints for the inventory's exact bytes, the
complete root lockfile, and a canonical sorted map from every reviewed source
path to its file digest. These values use the existing
[`apple_export_preflight.py`](../tool/apple_export_preflight.py) implementation;
the validator and its acceptance rules are unchanged.

Any later edit to a bound source, dependency lock or inventory requires another
delta review. These source checks establish consistency with this technical
record. Artifact verification and live distribution checks are still required
for a release; a source fingerprint does not establish either result.

The initial binding retained the existing failure-path tests and acceptance rules:

- `test_crypto_release_evidence.py`: 41 tests completed, with its two existing
  platform-dependent skips.
- `test_apple_export_preflight.py`: all 37 tests passed.
- `crypto_release_evidence.py --check`: passed against the reviewed source,
  inventory and complete root lockfile.

These results describe source inputs only. Hosted checks for the final branch
revision and target-device verification have their own status in the
[ebook recovery record](recovery/ebook-extension-2026-11-12.md).

## Initial ebook fingerprints

These exact inputs include the shared Kindle metadata fixes and rebuilt Wasm
from checkpoint `47e83b0`. The root pubspec matches its committed bytes.

```json
{
  "inventory_sha256": "72775c1d906199251ad1893e8dfbd46c4bf3c9752c1369e73a6d79dbd23d7008",
  "pubspec_lock_sha256": "3b1a93697f3b0c8b43fb436989247219524baa00b6f2357c75bac8fabb0a9673",
  "reviewed_source_sha256": "0f3fea3dfbeff4838ea640ab408c438a8a355e03fc92b3ebdf9a3ab781ada19d"
}
```

## Extended reader fingerprints and validation

This binding extends the initial review to all 207 paths, including the native
host from `5061673`, the shared integration refinements and the grouping
compatibility module, followed by the diagnostic delta below. The root
`pubspec.yaml` matches its committed contents;
temporary test hooks are removed. The unchanged root lock retains the same
digest as the initial ebook review.

```json
{
  "inventory_sha256": "62a167e261c14ea0daa5a18f2a5d5b2ad03b5faf2891e6ec791e4a599edb453d",
  "pubspec_lock_sha256": "3b1a93697f3b0c8b43fb436989247219524baa00b6f2357c75bac8fabb0a9673",
  "reviewed_source_sha256": "1e143af4c222a875689389cf8f6a437442b655c6438893285d0457b8122bddd2"
}
```

The existing validation was repeated against this extension:

- `test_crypto_release_evidence.py`: 41 tests completed, with the same two
  platform-dependent skips.
- `test_apple_export_preflight.py`: all 37 tests passed.
- `crypto_release_evidence.py --check`: passed for the 207-path inventory,
  source fingerprint and complete root lockfile.
- `git diff --check`: passed for the four review/policy files.

A structural comparison confirmed that all previous inventory feature records
and the original 177 paths are retained. The policy changes only its inventory
and reviewed-source digests. Application identity, review date, encryption
declaration, documentation status and evidence, France records and TestFlight
records are exactly unchanged; so are all validator code and acceptance rules.
The generated Linux registration and Debian runtime recommendation are source
inputs in this binding, not evidence of a completed native artifact review.
Hosted/native/browser test status remains in the recovery records.

### Native diagnostic checkpoint delta

The next source comparison identified exactly two changed bound inputs:
`crisp_ebook_reader_plugin.cc` adds an opt-in `CRISP_EBOOK_HOST_TRACE=1`
helper and calls containing fixed lifecycle labels only, while
`ebook_editor_dialog.dart` adds braces around two existing mounted checks.
The trace calls include no book content, URLs, environment values or dynamic
error strings; neither change adds an algorithm, dependency or storage path.
Reconstructing the previous contents of those two inputs reproduced the
preceding source fingerprint, confirming that no other bound source changed.
The intermediate fingerprint included this delta, and the source check passed
again. At that point the inventory and root-lock digests were unchanged.

The accompanying Linux workflow and integration-test changes were also
inspected. Synthetic pointer input now explicitly uses the mouse device.
CI enables the fixed trace labels and uses a time-limited GDB command with
automatic loading disabled and frame arguments suppressed to extract function
backtraces; it then deletes raw cores, which are absent from uploaded paths.
These diagnostic changes do not relax the crypto/export validators. They are
intended to investigate the first enhanced native run's early process exit,
not to record a passing enhanced-host runtime result.


The final diagnostic candidate also writes those same fixed labels to a
CI-selected file, because the integration-test driver does not forward native
stderr. This is opt-in host diagnostics, with no publication, session URL,
credential, argument or environment values written. The runtime/build minimum
and Debian recommendation were raised consistently to **WebKitGTK 2.48.4**:
[upstream explicitly fixed an offscreen-WebView crash in that release](https://webkitgtk.org/2025/07/30/webkitgtk2.48.4-released.html).
The inventory's newly added host description now records that minimum. This
requires refreshed inventory and source digests; the root lock and all
non-digest policy fields remain unchanged. The first hosted 2.52.6 application
exit is still under investigation and is not explained or declared fixed by
this older-version guard. The current fingerprint block includes these final
native CMake, probe/trace, packaging and descriptive changes.


## Integration source binding

The integration combines the recorded KeePass and ebook inventories without changing the stored distribution decisions. Duplicate reviewed paths are removed. The Word parser now lives in the shared Quds engine; it parses and serializes user documents without introducing cryptographic operations. The new directory selection comparison uses names, sizes and timestamps, and the new clipboard commands only copy names or paths. Fingerprints bind the merged inventory, resolved lockfile and exact reviewed source bytes. They do not represent a new Apple approval or distribution review.

The macOS transfer cleanup reconciliation uses the same existing root-owned system-link exception as normal file writes. It changes filesystem parent validation only; user-directory links remain refused. The ebook host now reports an absent browser platform plugin through its existing fallback path. Neither change adds cryptographic operations or network destinations.


### Fatal-launch diagnostic refinement

The next delta changes only the native plugin among the 207 bound paths. With
`CRISP_EBOOK_HOST_TRACE=1`, a process-wide GLib log handler classifies fatal
messages using a fixed list of process-launch prefixes. Only the matched
literal or a fixed unclassified label is appended to the selected trace file;
the native message's path, argument and error-detail suffix is not copied.
The handler delegates the original message to GLib's built-in default handler
and does not change fatal masks or suppress termination. It does not retain a
previously installed custom default handler; this interception is opt-in
diagnostic behavior.

The accompanying workflow explicitly installs bubblewrap and runs an actual
namespace probe before the reader test. It reports the probe result, leaves
sandbox policy unchanged, and still runs the reader test after a failed probe.
No crypto/export gate is relaxed. Replacing the plugin digest with its
`1d08158` contents reproduces the preceding reviewed-source fingerprint;
inventory bytes, the root lock, and every non-source-digest policy field remain
unchanged. The updated fingerprint above passes the existing source check.
This is diagnostic evidence preparation, not a resolved WebKit startup failure.

## Standalone Word package extraction



## Standalone Word package after integration

The refreshed source fingerprint is `ecd507bf7e68c1e08b67d96e752b09e26601cda58a5cf3e16862c32b284079dd`. The root lockfile fingerprint
is `51287d8e323b58ad8cc86b300540e0c5c5700a6cc9135925126a4d69c3b06dbe`. This binds the reviewed parser dependency without changing the
existing source plist declarations, Apple documentation status (`unreviewed`),
questionnaire requirement, territory decisions or distribution controls.
The source evidence check passed; submission validation still rejects the
missing questionnaire result. No Apple API call or filing was made.

## Interrupted-session recovery: main synchronization

Merged `main` at `977b5037f133cb2d33c57db761864183455a705e` into the recovered ebook branch at `280f55167f43f227068d8a462a88aabc18e56afb`. The combined inventory retains all 207 ebook-branch paths and all 16 additional Rust-cloud paths from main (223 unique paths). Of those, 222 source files match one parent byte for byte. The remaining file, `lib/main.dart`, retains the ebook license import and registration from the feature branch plus the native secure-storage initialization call to `PlatformSecureStorage.detectMacOsKeychain()` from main; both parent diffs were inspected. Both inventories and their component descriptions remain present. All non-digest export-policy fields agree between the parents and remain unchanged.

The committed merge-specific source was used for these bindings so concurrent, uncommitted follow-up fixes are not incorrectly covered by this checkpoint:

```json
{
  "inventory_sha256": "1b8932cf629788fc5d3fb261155e6d515ca22900f61caebd9482204fb25e186a",
  "pubspec_lock_sha256": "3b1a93697f3b0c8b43fb436989247219524baa00b6f2357c75bac8fabb0a9673",
  "reviewed_source_sha256": "1eaaa2689cadc29fb891301601b692fbb76cf8212e8a79e2bc1c7f76db8cef97"
}
```

This source identity check preserves the scope of each parent review; it does not establish native Linux readiness or alter distribution approval. Follow-up source changes require their own reviewed bindings.

## Reading lifecycle corrections after recovery

Reviewed explicit-discard handling in the editor, the section resource loader, and the host-owned search adapter. Explicit discard now suppresses the final best-effort write and relocation callbacks during closing. The resource loader shares in-flight work, retains only immutable sanitized search snapshots across unload, and releases late resources. The search adapter bounds inputs, serializes mutable Foliate iterators, returns cancellation promptly and suppresses stale overlays/events without modifying pinned vendor code. Search hit section numbers are resolved from their CFIs. No new network, cryptographic or credential capability is introduced. The only root dependency change promotes the already-locked shared_preferences_platform_interface 2.4.2 to a direct development dependency for the one-shot write-failure regression.

The inventory adds reader_search.js (224 total paths). Default and forced missing-grouping/raw-DEFLATE parser regressions, vendor integrity and focused Dart analysis passed. The actual browser regression is committed for CI; local application tests are awaiting the restored native build toolchain. These bindings use staged source and exclude the temporary local SQLite test configuration and still-uncommitted Linux-host work. All non-digest policy values remain unchanged.

```json
{
  "inventory_sha256": "51e68885d5401faac89272c84af86753e5627a5bad6ed6ab14e5925a11e3d3f4",
  "pubspec_lock_sha256": "5df7dcfb50f5ffc6c1649adaad649c8d7c577ece5aac6eb8ba1753c7e75703fe",
  "reviewed_source_sha256": "62a74997da1d2566bc728dd26d9918a9821d08aa2737268cd92b79531a7407a0"
}
```

## Isolated Linux WebKit startup and owned process cleanup

Reviewed the native plugin, fixed-page helper, shared settings, bounded child runner, CMake packaging and Dart deadline. Before creating a view, the plugin asynchronously requires the helper to demonstrate script execution and an actual painted snapshot with the same ephemeral context, enabled sandbox and view settings. No publication or account input enters the helper; its fixed document disallows network resources. The helper alone has a direct system-WebKit dependency. Missing runtimes/helpers, denied startup, crashes and timeouts produce an unavailable-host result. The app performs no browser load in that failure path.

The runner coalesces up to 32 callers, caches for two seconds, invalidates after real reader errors, and enforces an eight-second parent deadline. The child gets its own process group, closes inherited descriptors, discards standard streams and disables core dumps. waitid with WNOWAIT retains ownership of an exited leader PID while residual group members are stopped; only then does waitpid reap it. A foreign reaper causes a closed failure without signaling an unowned PID. No browser sandbox or host policy is disabled. The added system process primitives do not add cryptography, a network capability or a credential store. All non-digest policy fields remain unchanged.

Seven actual subprocess regression scenarios passed with warnings treated as errors. The helper also passed syntax compilation against real GTK 3.24.49 and WebKitGTK 2.52.6 headers. Full linking, deferred executable installation and enhanced publication rendering remain hosted gates at this checkpoint. CI distinguishes required enhanced rendering on Ubuntu 22.04, blocked-startup recovery on the existing Ubuntu 24.04 runner, and portable-only launch. The 22.04 distribution provides maintained WebKitGTK 4.1 above the existing minimum; no acceptance assertion or browser setting is weakened.

The inventory adds three helper/runner/settings files, for 227 paths. Index-based bindings exclude the temporary local test configuration:

```json
{
  "inventory_sha256": "2b459148f02ecba0abefa23f749366e27fa76f0d28371724a3e1cb2056c87302",
  "pubspec_lock_sha256": "5df7dcfb50f5ffc6c1649adaad649c8d7c577ece5aac6eb8ba1753c7e75703fe",
  "reviewed_source_sha256": "97b9a5222922a789157c67f138c24aa4ee72f6959870f0cb51c5f76c83c9aec8"
}
```

## Integration source binding

The integration combines the recorded KeePass and ebook inventories without changing the stored distribution decisions. Duplicate reviewed paths are removed. The Word parser now lives in the shared Quds engine; it parses and serializes user documents without introducing cryptographic operations. The new directory selection comparison uses names, sizes and timestamps, and the new clipboard commands only copy names or paths. Fingerprints bind the merged inventory, resolved lockfile and exact reviewed source bytes. They do not represent a new Apple approval or distribution review.

The macOS transfer cleanup reconciliation uses the same existing root-owned system-link exception as normal file writes. It changes filesystem parent validation only; user-directory links remain refused. The ebook host now reports an absent browser platform plugin through its existing fallback path. Neither change adds cryptographic operations or network destinations.

## Ebook recovery synchronized with integrated main

Merged `main` at `02be67fe` into the recovered ebook feature at `04429947`, preserving its integrated office, file-manager, provider and ebook-platform changes. Both inventory path sets and all source-review narrative sections are retained, with duplicate paths removed. Of the 292 inventoried files, every file except pubspec.yaml matches at least one parent exactly. The combined pubspec equals main plus the already-reviewed direct development dependency shared_preferences_platform_interface 2.4.2; production constraints and pins come unchanged from main. The native browser-platform fallback and macOS dependency resolution from main are retained. All non-digest export-policy fields agreed between parents and remain unchanged.

The merged source now requires its own application/build verification. Historical acceptance remains tied to the source revision that produced it. Exact merged bindings:

```json
{
  "inventory_sha256": "6d74f0fa232f6d73ea3a934005e4f60b65627eb724b2e571595171a8fa640602",
  "pubspec_lock_sha256": "e4af3d0674ff75b84ea258f7ed72a3d89c071eaad7cabac37d40b6997b32a9f1",
  "reviewed_source_sha256": "c1077a5e50563e81a56c326e1100595d10e943d16268ab52350b4a3af99426f8"
}
```

This continuation uses merged main `02be67fecad5be2a040e6dcd1579a2a54fa51933`
as its source baseline and preserves its **288-file** inventory and every
non-digest policy field. The earlier 207-file and pending-questionnaire
paragraphs record historical checkpoints; they do not replace the current
main policy's stored decisions or evidence references. This update makes no
release, live-store, classification or distribution decision.

CrispCloud's DOC/DOT preview and conversion routes now call the standalone
MPL-2.0 `legacy_doc_parser` package at Git commit `80e9683c0d60553f7198ca89a64aa927d619c684`. The shared Quds
engine keeps its existing legacy APIs for other consumers; the temporary
`packages/legacy_doc_parser` extraction mirror is removed. The app's copy
model and create-only captured storage target remain app-owned.

Compared with this merged-main baseline, the only changed source in the
288-file binding is `pubspec.yaml`. The resolved lock adds only the new
parser Git dependency. Its only runtime dependency is the already-resolved
`archive` package. It rejects encrypted/obfuscated DOC input before parsing
and writes unencrypted Word ZIP/XML output. Keeping opaque objects, VBA or
signature bytes adds no encryption, signature validation, cipher, KDF or
cryptographic provider. Other resolved package versions and the native
provider inventory remain unchanged.

The refreshed reviewed-source fingerprint is `31729566c3e14851b493270ae3efb96fa3dde66a88a0935423f197016dbf19fa`; the root lockfile
fingerprint is `30d89e6ff313698a76f2ffa25ac4fbd3eeb5f91fb88b4e4cbfcdf9091a6eb19b`. The inventory fingerprint remains
`508a2646b34d1db60933c7723abf9a4db3655c4e1875a3859dcc57f52581b4c2`. The source evidence check and source plist consistency checks
passed. These bind this dependency update while retaining the current
policy's documentation status, declaration, France/TestFlight decisions
and artifact/live evidence controls. No Apple API call or filing was made.


## Final integration binding

The maintained MPL-2.0 legacy DOC parser is pinned in its own upstream record and consumed through Quds compatibility exports. Its only runtime package dependency is archive. It parses existing signature markers and can retain signature bytes as inert evidence; it does not verify signatures, decrypt protected Word files, execute VBA, or claim signature validity for a converted copy. DOCM output is an explicit reviewed choice. The native parser and JavaScript acceptance checks remain separate from native Word visual certification.

Retained external-tool drafts, conditional Dropbox publication, archive publication/recovery, source unlink checks, and viewer spooling reuse existing content digests and private staging. Their exact inputs are included in the merged source binding. Existing Apple/store decisions retain their original dated evidence. The new technical hashes do not constitute a new distribution approval.

## FictionBook output and native keyboard qualification

The shared FictionBook writer produces an explicit separate FB2/FBZ copy from a
validated EPUB snapshot. Its bounded XML/resource conversion rejects unsupported
media and foreign/active markup, checks emitted internal links, and retains
supported structural text, Unicode, notes and raster images. The existing Dart
SHA-256 implementation supplies a fallback format identifier from title and
authors when necessary; it is not an exact-content binding, cipher, signature or
access grant. Base64 image encoding and passwordless ZIP output add no crypto
implementation or network capability. The unmodified author's schemas are
development-only validation evidence with their pinned BSD notice.

The Linux change forwards Tab/Shift+Tab to WebKit links and reserves Ctrl+Tab
and Ctrl+Shift+Tab for escape to Flutter controls. The same tab setting is used
in the guarded helper and production view. A content-surface semantics hint
describes the controls; it does not expose book text to assistive technology.
The added desktop/mobile CI applications exercise the actual existing hosts and
converter. A workflow definition is not a platform pass. Browser sandboxing,
resource policy and enhanced-runtime assertions remain enabled.

This checkpoint binds 293 staged source paths and excludes concurrent reader,
browser-converter and temporary local test-hook changes. All non-digest policy
values remain unchanged:

```json
{
  "inventory_sha256": "3a7ca748564e8e6db84b1d32d3ce923ec5570a4270b238dfade06e37e8126de3",
  "pubspec_lock_sha256": "e4af3d0674ff75b84ea258f7ed72a3d89c071eaad7cabac37d40b6997b32a9f1",
  "reviewed_source_sha256": "83c558c0ebbaa2d429e53821e8d5022457ff13e2bd95d33a61dd178deaa07e7e"
}
```

## Legacy Word fidelity continuation source binding

The parser mirror and Git declaration now identify upstream
`b295a3c1ddb542b0f161ecafdcdaba3762dc7535`, synchronized through Quds
`9fb8bf12703f32a487609a673f342a5ae0003de1`. The active dependency remains the
reviewed local path mirror. The new table-model/style/text and shape-writer
files are included in the 350-file source inventory. Their changes parse
bounded Word properties and serialize document formatting, geometry, revision
history and inert ink evidence. They add no cipher, key derivation, signature
verification, native provider or network operation. Encrypted/obfuscated Word
input is still rejected, and the runtime dependency remains `archive`.

The root lockfile is unchanged. Only the exact inventory/source fingerprints
are refreshed; existing declaration, questionnaire and distribution decisions
retain their recorded evidence. No release or external filing is made by this
source update. Temporary test hooks have been removed before calculating:

```json
{
  "inventory_sha256": "bee7a3b1c69c300ee7c5731dd77fed4bdef97ccf8906a5f9641dd697a4cffe7c",
  "pubspec_lock_sha256": "03e00c2707eb12fab41ab917c1d4e60ee05c1002e38c77adb02accd38bf9c247",
  "reviewed_source_sha256": "4356cfd922144f46b5baa410c562e75a382ee6d4e1cf9756ed54a71f0fe1e903"
}
```

The CrisperBooks extraction replaces application-owned reusable ebook code with the pinned facade and matching reader packages. It retains the same storage boundary and cryptographic dependencies. Foreground speech accepts only voices explicitly marked local by the platform; publication text is not sent to an added network service. The audio wrapper recognizes bounded inert ID3 prefixes before FLAC and never rewrites source metadata; it adds no cryptographic function. These consumer inputs are included in the technical source binding; existing distribution decisions are unchanged.

### Reconciliation with app main 467c4a3

The combined tree retains both the preceding parser review and main's
CrisperBooks/audio review. Their reviewed path sets are combined without
duplicates (361 paths). All non-digest policy fields are identical in the two
parents and remain unchanged. The resolved lock contains main's pinned local
CrisperBooks package; the DOC parser's runtime dependency is unchanged. The 99
focused Word workflow tests and both guarded source-mirror checks pass on this
combined tree. Source bindings after restoring the test configuration:

```json
{
  "inventory_sha256": "b22c2916adab5c1078ec4ff7c8e4ab8ca39f2a7bdedacf3637f38680c62e8973",
  "pubspec_lock_sha256": "2a8c1f83455844560fb694c51d15f1b875f83a8a15b84ce083482568af4c7139",
  "reviewed_source_sha256": "9e7a47c431be1c90a31bdb59a41aa3faa6f6d77a01ebe5c441f7ac36b654a00a"
}
```
