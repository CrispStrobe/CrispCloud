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
