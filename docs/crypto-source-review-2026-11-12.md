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
and adds **30**, for **207** unique paths. The isolated Linux startup review
below adds **six**, producing a 213-path checkpoint. The concurrent main
synchronization contributes **16** more reviewed paths; the combined
[inventory](crypto-inventory.json) at that checkpoint contains **229** unique
paths. The final consolidation below retains those paths, adds the shared
search controller and excludes the superseded alternate Linux variant, for
**230** current paths. The initial exact-byte comparison against the main baseline
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

## Isolated Linux startup review

The next delta starts from `67ee2af`. Exactly three of its 207 bound inputs
change: the native plugin, its package CMake file, and `linux_host_probe.dart`.
The plugin now waits for a separate startup helper before either `probe` or
direct `create` can enable an in-process reader. Dynamic WebKit loading,
version checks, browser settings and the fixed-label trace helper move into a
shared header. The Dart probe allows 16 seconds for the bounded native attempt.
The root dependency lock and production Dart dependencies are unchanged.

Six paths are newly bound:

| Path | Reviewed role |
| --- | --- |
| `packages/crisp_ebook_reader/linux/webkit_runtime.h` | Shared system WebKit/JSC symbol loading, minimum version, settings and opt-in diagnostics. |
| `packages/crisp_ebook_reader/linux/reader_canary.cc` | Fresh sandboxed WebKit worker, fixed loopback document, bounded HTTP request, exact JavaScript reply and local cleanup. |
| `packages/crisp_ebook_reader/linux/reader_canary_probe.h` | Asynchronous helper launch, bounded proof capture, timeout/cancellation, coalesced requests and cached availability. |
| `packages/crisp_ebook_reader/linux/reader_canary_supervisor.h` | Direct worker spawning, bounded proof/exit checks, child-subreaper cleanup and termination handling. |
| `linux/CMakeLists.txt` | Unchanged root installation order, reviewed to confirm Flutter bundle cleanup precedes the helper install. |
| `packages/crisp_ebook_reader/tool/prepare_linux_host_smoke.py` | Unchanged standalone integration-project and fixture setup, reviewed as the second installation context. |

The two existing installation/test inputs were inspected and added to the
binding; they were not edited. The package CMake file requires CMake 3.19 for
the enhanced host and directly defers a constant-argument `install(TARGETS)`
call to the root directory. This schedules the executable helper's mode-0755
installation after Flutter's bundle cleanup in both application contexts.
WebKit and JavaScriptCore remain system dependencies, with no copied runtime
and no direct WebKit/JSC link added to the plugin or helper.

The [technical appendix](crypto-audit.md#isolated-linux-startup-readiness-check)
records the complete scope and limits. The helper accepts application identity
strings, not publication bytes, credentials or an arbitrary destination. Its
fixed document has a loopback URL whose GLib UUID uses the documented `GRand`
guarantees; it is not a cryptographic secret or a replacement for production
reader sessions. Both native entry points require exact proof, a successful
helper exit and completed descendant cleanup. Supervisor and worker separately
disable their own dumpability; this does not establish the policy of every
separately executed system browser process.

The final review removed raw PID/group signaling from the GTK timeout callback:
GLib may already have reaped that process in a background thread before the
callback runs. The callback now uses only GLib's serialized force-exit API.
The separate supervisor retains its own unreaped-worker ownership checks for
group/descendant cleanup. This distinction avoids signaling a reused process
identifier from the application's asynchronous callback.

The supervisor's local regression suite exercised 16 actual process cases,
including malformed/missing proof, crash/timeout, cancellation/parent death,
escaped-descendant cleanup and the bounded `/proc` fallback. These checks
validate the supervision code without requiring GTK. The revised native
workflow separately requires real rendering, tests an installed runtime that
cannot start safely, checks portable-only behavior and missing-runtime startup,
and inspects helper installation and dynamic dependencies. Its cleanup check
reads process IDs and names, without command arguments, environment or memory.
These new hosted native checks have not yet established a passing result for
this candidate. Previously passing browser/application checks are recorded
separately in the [parity recovery record](recovery/ebook-parity-2026-11-12.md).

Readiness is cached for the plugin lifetime, so a prerequisite repair requires
an application restart. The actual reader remains in process; the isolated
test contains startup failures observed in that helper, not all future
renderer failures or changes in system conditions. Neither this review nor
the new source hashes constitutes a native release qualification.

### Isolated startup fingerprints and validation

The final reviewed inputs include the race-safe GLib termination callback and
the frozen supervisor tested above. The prior 207-path canonical source map
reproduces the preceding `1e143af4` fingerprint. Comparing that map with these
inputs finds only the three changed bound paths listed above, plus the six
newly bound paths. The root pubspec matches its committed contents.

```json
{
  "inventory_sha256": "11c8f1a9230692151df75dc434c4097d36c48f9584072caf151afb97744ed765",
  "pubspec_lock_sha256": "3b1a93697f3b0c8b43fb436989247219524baa00b6f2357c75bac8fabb0a9673",
  "reviewed_source_sha256": "5780117a9e14998062768652c44773e52ed1824b8ff0d40ea61bace0a33326f5"
}
```

The unchanged gates were rerun against this candidate:

- `test_crypto_release_evidence.py`: 41 tests completed, with the same two
  platform-dependent skips.
- `test_apple_export_preflight.py`: all 37 tests passed.
- `crypto_release_evidence.py --check`: passed against all 213 reviewed paths,
  the inventory and the complete root lockfile.
- `git diff --check`: passed for the four review/policy files.

A structural comparison confirms that all prior 14 feature records and 207
paths remain intact. One feature record and six paths are appended. Only the
policy's inventory and reviewed-source digests change; its root-lock digest,
application identity, review date, encryption declaration, documentation
status and evidence, France records and TestFlight records remain exactly
unchanged. No validator or acceptance rule was modified.

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

## Concurrent branch reconciliation

The saved Linux startup checkpoint `0ba63f3` is reconciled with incoming
`5e0b6f94c542a41db232eb62ec19d21a9ddacffb`, whose main synchronization is
recorded immediately above. Both historical review sections and their
fingerprints are retained. The current policy binds their combined tree.

The incoming inventory contains 223 paths and 14 feature records. Its Filen
and Internxt entries preserve their earlier fields and add Rust-engine
sections; those complete incoming records and its `2026-11-12` inventory date
are retained. The Linux checkpoint contributes its canary feature record and
six additional paths. The result has **229 unique paths and 15 feature
records**, preserving every path from both parents and every incoming record.
The incoming Rust-cloud review is inherited here; this reconciliation does
not claim a new independent audit of those provider implementations.

The incoming commit's source map reproduces its recorded
`1eaaa2689cadc29fb891301601b692fbb76cf8212e8a79e2bc1c7f76db8cef97`
fingerprint. An exact-byte comparison of the combined tree then establishes:

| Bound inputs | Source identity |
| --- | --- |
| 220 incoming paths | Match `5e0b6f9` byte for byte, including its already-reviewed `lib/main.dart` merge and all 16 additional Rust-cloud paths. |
| Three existing Linux paths | The plugin, package CMake file and Dart probe match the saved, reviewed `0ba63f3` checkpoint. |
| Six additional startup/installation paths | Match the saved, reviewed `0ba63f3` checkpoint. |

Every bound source therefore matches a recorded parent revision. This merge
introduces no further source combination among those 229 paths. The root
lock is unchanged. All non-digest policy fields agree between the parents;
the combined policy starts from the incoming file and replaces only the
inventory and reviewed-source digest values.

```json
{
  "inventory_sha256": "1d1a6e710e0abb486c5e9c3e6ad38ca78ad7980db5d11f34f984326057cc9812",
  "pubspec_lock_sha256": "3b1a93697f3b0c8b43fb436989247219524baa00b6f2357c75bac8fabb0a9673",
  "reviewed_source_sha256": "81272b66c3ccec1c436686fb3a524309409be2627b9e57d193305748204a37db"
}
```

Validation against the combined tree used the unchanged gates:

- `test_crypto_release_evidence.py`: 41 tests completed, with the same two
  platform-dependent skips.
- `test_apple_export_preflight.py`: all 37 tests passed.
- `crypto_release_evidence.py --check`: passed against the 229-path inventory,
  complete root lock and combined source fingerprint.
- `git diff --check`: passed for the four review/policy files; their contents
  contain no merge-conflict markers.

These results establish source-binding consistency for the combined tree.
The inherited review boundaries, pending native runtime qualification, and
separate artifact/live distribution requirements remain in effect.

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

## Consolidated recovery implementation

The isolated recovery branch consolidates saved checkpoint
`13667db48cde44435d486d6cf0842a89563190b8` with incoming
`e2231a963ae3e5bad6e5164a38bd8006f53b8619`. It retains the canary/supervisor
implementation reviewed above and the shared lifecycle corrections from
`ae0ef0b`. The incoming source review's alternate Linux implementation remains
recorded in `e2231a9`; it is not an additional shipped helper in this tree.

The current inventory preserves all 229 paths from the saved checkpoint and
adds `packages/crisp_ebook_reader/assets/reader_search.js`, for **230 unique
paths and 15 feature records**. Three alternate runtime bindings are retired
because the corresponding files are absent:

- `packages/crisp_ebook_reader/linux/reader_runtime_probe.h`
- `packages/crisp_ebook_reader/linux/reader_webkit_settings.h`
- `packages/crisp_ebook_reader/linux/webkit_runtime_probe.cc`

The existing shared-reader feature retains the incoming search/discard/resource
description, while its obsolete helper description and source references are
removed. The separate canary feature and all six of its reviewed bindings
remain. All other incoming feature records, provider sections and inventory
metadata are retained exactly. This makes the inventory describe the current
implementation while preserving the superseded review in its saved commit.

Both parent source maps reproduce their committed policy fingerprints before
consolidation: `81272b66` for the saved recovery checkpoint and `97b9a522` for
the incoming branch. Exact-byte comparison confirms that the incoming editor,
reader/search/resource changes and their nine runtime/test files are preserved.
Their earlier verification evidence is inherited with the limits stated above.

The root lock changes only the existing `shared_preferences_platform_interface`
entry from transitive to direct development classification; its version remains
**2.4.2**. The root manifest's new development constraint is `^2.4.2`. Both
manifest and lock match the incoming commit byte for byte. Offline dependency
resolution completed without changing the lock. This is a test dependency for
the transient persistence-failure regression, with no production dependency or
package-version change. The earlier lifecycle review and its historical
fingerprints are retained.

### Retained helper paint and process-coexistence checks

The canary worker now requires a snapshot of its fixed loopback page containing
the known background color, in addition to the exact JavaScript reply and load
completion. It accepts only successful Cairo image surfaces with ARGB32/RGB24
format, bounded dimensions and stride, then scans their native-endian color
words. A plain white or merely allocated snapshot cannot establish readiness.
The snapshot callback uses a weak worker reference; close cancels pending work
and prevents a late callback from publishing success. A monotonic failure
latch prevents a paint callback from overwriting a timeout, load failure or
process termination even within the same event-loop iteration. Pre-loop
failure is handled without starting a loop that already resolved. The worker's
existing timeout and the supervisor's proof/exit/cleanup limits remain in force.

The native probe names GLib's result `reported_clean_exit_` to distinguish it
from the actual worker status checked inside the fresh supervisor. Dart's
process reaper may collect the outer helper before GLib observes its status.
The exact supervisor proof is therefore the independent evidence that the
worker exited successfully and that owned descendants were reaped; the outer
reported status remains an additional guard. The application creates no view
without the proof and completed stdout handling.

The integration regression verifies an initial response from a real Dart
`Process` child, keeps it alive across concurrent probes and a native
create/dispose, then closes its input and verifies normal exit. This covers
coexistence rather than inferring it from the standalone supervisor tests.
The new paint/coexistence checks remain explicit test requirements; their
actual hosted result remains separate from this
source review and its fingerprints.

The plugin's two `Evaluate` call sites are bridge expressions. The wrapper now
evaluates the expression followed by `null`, avoiding WebKit's
unsupported Promise-result conversion for asynchronous `receive()` calls.
Synchronous JavaScript errors still reach the native evaluation error path;
asynchronous command results and errors use the existing session-checked
message bridge. This targeted fix does not change the bridge's allowed origin,
session validation or publication sanitization.

The final allocation adjustment changes only the plugin among the 230 bound
paths. `Evaluate` takes its temporary call-expression string by value and
appends `; null` to the owned buffer, avoiding a separate statement string
containing the entire potentially large message. Both current call sites
remain expressions; the message-size limit and synchronous-error behavior are
unchanged. The preceding `604c1902` source map differs only in this reviewed
plugin file, whose updated bytes match the owner's final freeze.

### Consolidated fingerprints and validation

The final source comparison binds the frozen paint/failure-latch, reported
exit-status and evaluation-result changes above. Of the 230 current paths,
221 match incoming `e2231a9` byte for byte. Six match the retained recovery
checkpoint: root Linux CMake, the Dart probe, package Linux CMake, supervisor,
shared WebKit runtime header and smoke-project preparer. The remaining three
are the specifically reviewed native delta: `reader_canary.cc`,
`reader_canary_probe.h` and `crisp_ebook_reader_plugin.cc`. Their bytes match
the owners' final source freeze. No other bound path has an unreviewed merged
version.

```json
{
  "inventory_sha256": "5a0e614d3da63acc7d2ac2720788aadf20cfa7ef86e3f82fa641496b7091030a",
  "pubspec_lock_sha256": "5df7dcfb50f5ffc6c1649adaad649c8d7c577ece5aac6eb8ba1753c7e75703fe",
  "reviewed_source_sha256": "5b7aae2d8a6f0468431847b5eee661945cb09d51e9a072a2fb0a1470d7c4a52c"
}
```

The two unchanged validator suites passed against the preceding consolidated
source. After the final single-file allocation adjustment, the source check
and whitespace check were repeated:

- `test_crypto_release_evidence.py`: 41 tests completed, with the same two
  platform-dependent skips.
- `test_apple_export_preflight.py`: all 37 tests passed.
- `crypto_release_evidence.py --check`: passed for the 230-path inventory,
  incoming complete root lock and consolidated source fingerprint.
- `git diff --check`: passed for all four review/policy files, whose contents
  contain no merge-conflict markers.

The current inventory retains every saved recovery path and removes only the
three unused alternate runtime paths from the incoming inventory. Its
remaining provider records and metadata are preserved. The policy is copied
from incoming `e2231a9`, changing only inventory and reviewed-source digest
values; its incoming root-lock digest is already correct. All non-digest
application, legal and distribution fields remain byte-for-byte unchanged,
as do the validator sources and acceptance rules. Actual native rendering,
the new process-coexistence regression, finished artifacts and live submission
evidence remain separate gates with their own recorded results.

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

## PR 84 base synchronization

This reconciliation combines saved canary checkpoint
`3ccfee41d139485d48b4d5ad7d90e500e31bfea2` with integrated base
`5dce28e8c64b2557d3e42ef305da916e3bfcd91f`. The incoming KeePass, file-manager,
office, provider and dependency review records above are inherited with their
original scope and evidence. This section verifies source identity for the
combined tree; it does not claim a new independent audit of those unrelated
implementations or renew their historical acceptance results.

The verified inventory contains **295 unique paths and 20 feature records**.
It preserves every one of the saved canary branch's 230 paths and every active
incoming path. The only incoming exclusions are the three alternate Linux
runtime files already retired in the previous consolidation and still absent
from this tree. Incoming inventory metadata, crypto-package entries and all
other feature records are retained exactly. The shared-reader description
continues to describe the retained implementation, alongside the unchanged
canary feature record; obsolete helper descriptions are not reintroduced.

Both parent source maps reproduce their recorded policy fingerprints:
`5b7aae2d` for `3ccfee41` and `c1077a5e` for `5dce28e8`. Comparison of every
current bound file establishes:

| Current inputs | Source identity |
| --- | --- |
| 286 paths | Match the integrated base byte for byte. |
| Nine Linux/runtime/installation paths | Match the saved canary checkpoint byte for byte: the Dart Linux probe, plugin CMake, plugin, shared WebKit header, canary worker, canary probe, supervisor, root Linux CMake and smoke-project preparer. |
| Newly combined source versions | None among the 295 bound paths. |

The incoming three-line `InAppWebViewPlatform.instance` guard in
`host_native.dart` is retained exactly. An unavailable browser platform reaches
the existing host error/fallback flow; it adds no cryptographic operation,
permission or destination. The Linux runtime source remains the saved
canary implementation. The complete root manifest and lock match the incoming
base, including its already-recorded production dependency resolution and the
existing direct development dependency used by the persistence regression.

The current binding is:

```json
{
  "inventory_sha256": "8b2e21808e50a7fb6a64749a87ff6ce448c8c88f947233f61eaaf1d17e68f82d",
  "pubspec_lock_sha256": "e4af3d0674ff75b84ea258f7ed72a3d89c071eaad7cabac37d40b6997b32a9f1",
  "reviewed_source_sha256": "f4569c98d4ce6a923a48c83e2a353116fa42318fc694e52270379abec138a316"
}
```

The source check uses the incoming validator implementation and passes against
these exact inventory, lock and source bytes. The four review/policy files
also pass `git diff --check` and contain no conflict markers. Existing
historical test results remain attached to the revisions on which they ran;
no unrelated test suite or cryptographic classification was repeated for this
source-identity reconciliation.

The policy starts from the incoming file. Only its inventory and reviewed-source
digests are replaced; its root-lock digest already matches the inherited lock.
All non-digest application, declaration, documentation, France and TestFlight
fields remain byte-for-byte unchanged. Validator rules are unchanged. Hosted
native and application/build results, artifact inspection and live distribution
evidence continue to have their own revision-specific records.

## Native input diagnostic checkpoint

This source delta starts from saved `e20e2cc4e6c50b791048b87c07867a0d3d931076`.
Only `packages/crisp_ebook_reader/linux/crisp_ebook_reader_plugin.cc` changes
among the existing 295 bound paths. Its frozen SHA-256 is
`61424ba807e92aeffa1881cf74141ad64ea883ebd7dcf572b17bdaf77c8fa77b`.
The other 294 source files, inventory and dependency lock are unchanged.

The added `inputState` method requires an already-loaded trusted reader
document and runs a fixed read-only JavaScript expression. It inspects at most
eight current book documents and returns only section indices, focus flags,
selection-range counts and collapsed-selection flags. The native result path
rejects replies larger than 4,096 bytes and retains the existing closed-view
and evaluation-error handling. The caller cannot supply JavaScript, a selector
or a destination. The reply contains no book text, DOM serialization,
publication URL, selection contents, account value or credential.

The existing native statistics additionally expose the view identifier,
mapped/viewable flags and aggregate pointer/key/SelectAll counters. Counter
increments leave input dispatch unchanged. No WebKit setting, sandbox option,
dynamic symbol, browser script, cryptographic operation or network destination
changes in this delta.

The integration test now observes actual book-document focus and non-collapsed
selection before retaining its existing Foliate-CFI assertion. The new focused
Flutter regression exercises the first shortcut immediately after pointer
focus with a mocked native channel; it does not substitute for WebProcess
verification. Its owner reported one passing widget test and clean analysis of
both test files. These are diagnostic assertions for the observed native
selection failure, not a product keyboard-behavior fix or a passing native
selection result. Both test paths are outside the runtime source inventory;
no new runtime path needs a binding.

The current fingerprints are:

```json
{
  "inventory_sha256": "8b2e21808e50a7fb6a64749a87ff6ce448c8c88f947233f61eaaf1d17e68f82d",
  "pubspec_lock_sha256": "e4af3d0674ff75b84ea258f7ed72a3d89c071eaad7cabac37d40b6997b32a9f1",
  "reviewed_source_sha256": "dbe95c84ba7ec2ed1f7789ee558a35f2751450a9be2bebaaa1394d8976fca442"
}
```

The existing source `--check` passes with this single-file delta, and the two
changed review/policy files pass `git diff --check`. Only the policy's
reviewed-source digest changes; every other policy byte, inventory entry,
validator source and acceptance rule is preserved. Broader test suites were
not repeated for this diagnostic source-binding update. Native integration
results remain attached to their actual checkpoint and runner.

## Parent selection observation and native page keys

This delta starts from saved diagnostic checkpoint
`7e20b40c1b797d463704106c881b9e84415f4fd7`. The observed native view was
focused and had a non-collapsed DOM selection, but its child-document event
path did not report a Foliate CFI. The reviewed change observes that selection
from the trusted reader parent while retaining the existing publication-script
restrictions. It also routes native bare Left/Right keys through the shared
reader's navigation command path.

The inventory retains all 295 previous paths and all 20 feature records. Only
`packages/crisp_ebook_reader/assets/reader_selection.js` is added, producing
**296 unique paths**. The preceding canonical source map reproduces the
recorded `dbe95c84` fingerprint. Of its entries, exactly four change:

| Runtime source | Reviewed change |
| --- | --- |
| `packages/crisp_ebook_reader/assets/reader.js` | Creates and disposes the parent selection observer; adds the allowlisted `hostKey` method to the existing ordered navigation queue. |
| `packages/crisp_ebook_reader/assets/reader_controls.js` | Maps only unmodified Left/Right arrow names to the existing direction-aware Foliate methods. |
| `packages/crisp_ebook_reader/lib/src/hosts/host_linux.dart` | Tracks forwarded keys, delivers their matching releases despite later modifier changes, and releases held keys before blur. |
| `packages/crisp_ebook_reader/linux/crisp_ebook_reader_plugin.cc` | Retains the validated session for fixed native page-key commands and keeps each key's initial parent/native route until release. |
| New `packages/crisp_ebook_reader/assets/reader_selection.js` | Observes current sanitized documents with bounded initial text extraction, unchanged-endpoint deduplication and explicit disposal. |

The observer samples at most eight current documents, with their section
indices supplied by the trusted renderer's load events. It compares the first
range's endpoints before performing text extraction or CFI conversion. A
changed range's DOM-text scan has a 20,000 UTF-16-code-unit limit and a
4,096-step traversal budget, including parent ascents. Large text nodes are
read through bounded `substringData`, without first materializing their full
contents. Native rendered-whitespace conversion is used only after a completed
bounded scan and only when the selection has exactly one range. Multi-range
quotes use the bounded first range that the CFI describes; later ranges cannot
trigger an unbounded `Selection.toString()` call. Long or highly fragmented
quotes are prefixes, not a promise to export the complete selected text.

The 150 ms event debounce and 200 ms parent poll share the same deduplication
state. Weak maps retain no strong collection of old documents. Current-view
checks suppress callbacks after replacement, including checks after CFI
conversion. Disposal stops both timers, removes the view and current-document
listeners, clears document state and drops references to the view/current
predicate. Publication scripts remain disabled. Existing native copy behavior
is unaffected; the observer emits the existing selection event with text,
CFI and section index rather than adding an external destination.

The native adapter interpolates only the already-validated base64url session
and fixed arrow names into a fixed `hostKey` command. It uses the existing
session and channel checks and serialized navigation queue. Request ID `-1`
is separate from Dart's incrementing positive request IDs; its reply is ignored
when no pending request matches. The native path requires focus and the trusted
reader document. Bare-arrow presses and releases stay on the parent route,
while modified keys retain the existing GTK route; changing modifiers during
a held key cannot create a mismatched release. Dart's tracked-key map is
bounded by its existing key allowlist. Held-key state is cleared on blur,
and release messages precede native focus loss.

All five runtime files match their authors' final frozen hashes, including the
revised selection helper SHA-256
`e7c428073c4eb6bc0b948a55a97de30a1d4e124f648400fe0ef88eeb04ea54be`.
The other 291 previously bound files are unchanged. Direct source comparison
also confirms unchanged vendor bytes, sanitization, CSP, asset-server routing,
WebKit runtime settings, package manifests, dependency lock and validators.
The delta adds no cryptographic primitive, dependency, credential flow or
network destination. Earlier unrelated review records retain their original
scope and evidence.

The browser owner reported passing normal and forced-fallback parser runs,
including all five Kindle fixtures, parent observation without child callbacks,
large/fragmented text bounds, the multi-range regression, and replacement and
disposal checks. The multi-range regression makes `Selection.toString()` throw
and still asserts delivery of the correct first-range quote and section. The
native owner reported one passing focused widget test and clean analysis;
its mocked channel covers first-shortcut focus, modifier changes and exactly
one release before blur. These results do not substitute for actual browser
or native selection/navigation execution, whose new checkpoint gates remain
pending at this source review.

The current fingerprints are:

```json
{
  "inventory_sha256": "c4a59bd1eb0da60134d3a016a8bcca5d5f2d2bbe5c3d2ba1b9f36dbc9ebc134f",
  "pubspec_lock_sha256": "e4af3d0674ff75b84ea258f7ed72a3d89c071eaad7cabac37d40b6997b32a9f1",
  "reviewed_source_sha256": "d289823b13be0039398ee4c2193aaceb74764dde80451de5819d82c3c57c717a"
}
```

Only the inventory and reviewed-source fingerprint values change in the policy;
every other policy byte is retained, including the root-lock fingerprint and
all application, declaration, documentation, France and TestFlight fields.
Validator sources and acceptance rules are unchanged.

The existing `crypto_release_evidence.py --check` passed against these exact
296-path inventory, dependency-lock and reviewed-source bindings. All four
review/policy files pass `git diff --check` and contain no conflict markers.
Structural checks preserve every previous inventory path, the historical
source-review text and every policy byte except the two fingerprint values.
No unrelated test suite was repeated for this source-review update.
