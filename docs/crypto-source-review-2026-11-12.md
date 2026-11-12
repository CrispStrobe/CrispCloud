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
