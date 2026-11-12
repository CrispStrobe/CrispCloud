# Archive rearrangement and CPIO profile verification

Date: 12 November 2026. Baseline:
`7cb65d768f2b096230f8bd32afc6c954baae7416` (PR #92).
Implementation checkpoint:
[`a68ad875a4f69e38c03e263f0bb61662f0f95636`](https://github.com/CrispStrobe/CrispCloud/commit/a68ad875a4f69e38c03e263f0bb61662f0f95636).
Review: [draft PR #93](https://github.com/CrispStrobe/CrispCloud/pull/93), stacked
on the preceding workflow/codec branch. See the
[continuation record](archive-rearrange-cpio-continuation.md) for remote checkpoints.

## Observed gates

| Gate | Observed result |
| --- | --- |
| Full archive/viewer and affected file-operation regression | **1,773 tests passed across 70 files** |
| Fatal-info static analysis | **All 21 changed Dart files clean** |
| CPIO writer/profile focused gate | **102 passed**, comprising 42 profile and 60 package-writer tests |
| Grouped move service | **57 passed** |
| Grouped move UI | **21 passed**, including native review/publication and all nine narrow translated layouts |
| Creation integration and UI | **101 passed** across five affected files |
| Native libarchive CPIO readback | **All nine cases passed** after the final root-order fix |
| Dart2JS and actual Node execution | **Passed** for all three new profiles, rewrite identity, high odc timestamps and binary overflow refusal |
| Bundled guide manifest | **Three guides with 23 matching topics**; reviewed English/German/French bytes |
| Help service/widget regression | **33 tests passed** across two files |
| Standard versioned Flutter release web build | Pending final build at this documentation checkpoint |

The focused feature counts are subsets of the full 1,773-test gate, not numbers
to add to it. Help tests are a separate asset/reader gate. Formatting and
whitespace checks are clean. No application dependency or lockfile change is
required by this increment.

## Grouped member moves

The service preflights every selected root and collision decision before one
draft mutation. Tests cover recursive and empty folders, implicit directories,
overlapping selections, deterministic keep-both names, whole-subtree skip,
same-parent no-ops, missing paths, self/descendant destinations and path/depth/
aggregate-name limits. A failed batch leaves its prior draft/revision unchanged.

Original member references retain supported metadata and source ordering. The
suite reopens and compares protected ZIP/7z, USTAR/GNU/PAX, newc/odc/binary CPIO
and XAR outputs, including successive saves. Nested cases retain outer siblings.
Active review/publication, stale reviews, changed source storage and late install
failures exercise existing rejection/recovery behavior. A failed physical save
cannot be reported as a published move.

The picker captures immutable member paths/names and workspace generations.
Confirmation checks its capture immediately before the synchronous service call.
Tests cover cancellation, lost source authority, changed caller selections,
stale drafts, collision retry, no-ops and unsupported single-payload profiles.
All nine languages fit at 320 px with 1.8x text scaling. A real native widget
case stages a move, proves original bytes are still unchanged, reviews and
publishes the candidate, then reopens moved and unrelated contents.

Independent review checked batch adoption, collision conservatism, metadata
identity, ancestor publication guards, nested revision chains and the existing
physical source/publication validation. No unresolved blocking finding remained.

## CPIO profile preservation and independent verification

Three explicit creation profiles extend the picker from 28 to 31 choices:
portable ASCII/odc, modern binary little-endian and modern binary big-endian.
All use `.cpio`; fresh creation defaults to newc. During a rewrite, the original
inspection controls the profile even if the caller supplies another creation
preference. Existing compatible mixed newc/CRC records remain supported.

The tests cover raw legacy device IDs, inode allocation, UID/GID, link counts,
permissions, whole-second times, member order, unchanged stored-name spelling,
root/trailer records, padding, exact byte order and repeated saves. Malformed
headers, incompatible layouts, hard links, special entries, duplicate identities,
unknown metadata, numeric overflow, unsafe paths, output limits, cancellation,
and short/growing member streams are refused.

Review found that inserting a root record at its old numeric index could move
it behind a surviving later member after an earlier member was removed. The
fix anchors root placement relative to surviving original member order. The
same issue existed in the earlier newc/CRC writer; the shared fix has five
targeted cases covering newc, CRC, odc and both binary byte orders.

Independent acceptance uses native **libarchive 3.7.4** plus a separate Python
physical-header parser. Nine outputs cover fresh creation, unchanged rewrite
and edited rewrite in each of the three legacy profiles. Checks compare every
payload SHA-256, name, size, permission mode, UID/GID, timestamp, raw device ID,
inode/link value, physical profile, alignment and trailer boundary. Unchanged
native reference fixtures reproduce their bytes exactly. All nine cases were
re-emitted and checked after the final shared root-order fix.

The portable test runs compiled JavaScript in **Node.js 24.22.1**. Fresh bytes
match the three native-accepted output hashes, unchanged rewrites retain those
hashes, odc's 33-bit timestamp keeps its high bits, and binary ownership overflow
is refused. This is actual codec execution, separate from the app web build.
See [CPIO writer provenance and commands](../test/fixtures/archives/CPIO_WRITER_PROFILES.md).

## Reproduction and environment

Validation uses pinned **Flutter 3.47.8 / Dart 3.13.7** on Linux and the existing
locked dependency cache. `CI=true` suppresses Flutter's automatic cloud metadata
probe; `FLUTTER_SUPPRESS_ANALYTICS=true` disables analytics. A recovered Clang
19.1.7 toolchain and a writable temporary directory support existing native test
hooks. System SQLite 3.46.1 is available for the existing test configuration.

The local wrapper temporarily sets the SQLite hook to its system source and
disables the unrelated optional native ebook conversion engine. It serializes
commands and restores `pubspec.yaml` byte-for-byte in a `finally` block. These
temporary settings are not application changes and are not committed. The
optional ebook engine's own build/runtime is outside this archive gate.

The complete archive gate is:

```sh
flutter test --no-pub --concurrency=4 --reporter expanded \
  test/archive*_test.dart test/widget/archive*_test.dart \
  test/internal_viewer_test.dart test/panel_source_test.dart \
  test/viewer_search_service_test.dart test/viewer_streaming_service_test.dart \
  test/viewer_spool_lifecycle_test.dart test/file_operation_service_test.dart \
  test/file_clipboard_test.dart test/widget/internal_viewer_widget_test.dart \
  test/widget/internal_viewer_localization_test.dart \
  test/widget/file_operation_dialog_test.dart \
  test/widget/file_operations_localization_test.dart \
  test/widget/screen_dialog_localization_test.dart

flutter test --no-pub --reporter expanded \
  test/help_guide_test.dart test/widget/help_guide_dialog_test.dart

python3 tool/check_help_guides.py
```

Static analysis covers every changed Dart file relative to the baseline,
including standalone reference emitters and portable test entry points, with
`dart analyze --fatal-infos`. Native and portable commands are recorded with
their fixture provenance. The release web build uses `--release --no-pub
--no-wasm-dry-run` and includes the current git hash and application version
through `GIT_HASH` and `APP_VERSION` Dart defines.

## Acceptance boundaries

Grouped moves operate within one captured workspace and one nested route.
They do not coordinate separately opened aliases or different inner routes,
and they do not implement a two-container move transaction. The existing
same-physical-outer/hard-link refusal on two-endpoint copying remains unchanged.

Ordinary edits retain 64 MiB/member and 256 MiB container/aggregate limits.
Path/count/depth limits remain enforced after rearrangement. Legacy CPIO fields
can impose smaller metadata/count limits; odc/binary have no stored payload
checksum or encryption. Read-only enclosing packages do not gain write access
because their inner CPIO profile now has a writer.

Remote/browser publication and creation, directory synchronization, durable
background packing and existing disk-filesystem rewriting retain their separate
implementation requirements. This Linux test suite and standard JavaScript web
build do not establish macOS mounting, six-platform native release acceptance,
live remote/provider behavior or WebAssembly acceptance. No VaultExplorer
implementation source, tests, assets or dependencies were inspected or imported.
