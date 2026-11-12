# Native archive moves and UNIX compress verification

Date: 12 November 2026. Baseline:
`19d359ba1dd5730fc01824efe69e309be26f876d`.
Branch: `feature/archive-rearrange-cpio-20261112`.
See the [continuation record](archive-move-compress-continuation.md) for the
incremental remote checkpoints. Existing PR #93 remains closed; subsequent
branch commits are not represented by its frozen review diff.

## Observed gates

| Gate | Observed result |
| --- | --- |
| Complete archive/viewer and affected file-operation/transfer regression | **1,951 tests passed across 78 files** |
| UNIX compress writer, workflow and affected creation/writer regression | **404 tests passed across 12 files** |
| Native archive-to-archive move service | **29 tests passed** |
| Publication dependency, existing publisher and affected transfer recovery | **94 tests passed across five files** |
| Final borrowed-workspace lifecycle regressions | **All three cases passed**; independent final review clean |
| Independent native UNIX compress readback | **All 23 cases passed** |
| Actual Dart2JS/Node execution | **All 18 native-accepted codec profiles passed** |
| Fatal-info static analysis | **All 43 changed Dart files clean**, including standalone reference tools |
| Bundled guide manifest | **Three reviewed guides with 23 matching topics each**, English/German/French |
| Help service/widget regression | **33 tests passed across two files**, against the final reviewed guide bytes |
| Versioned Flutter release web build | **Passed** at `b9619927`, with version `1.2.0+13` and the commit hash embedded |
| Packaged help assets | **All three guide SHA-256 values match the reviewed manifest**; bundled manifest matches its source |

Focused feature counts are subsets of the full 1,951-test gate, not numbers to
add to it. Help tests are a separate asset/reader gate. Formatting and whitespace
checks are clean. Both `pubspec.yaml` and `pubspec.lock` match the baseline
byte-for-byte after validation. The final checkpoint changes only this
verification and continuation documentation; application and bundled guide
bytes are identical to the successful release build.

## Native move transaction and recovery

The service test uses actual native local files and publication backends. It
covers a reviewed ZIP-to-TAR move, independent protected archive passwords,
recursive selection and empty directories, keep-both/replace/skip conflicts,
supported metadata, and retained unselected or skipped descendants. Both
complete candidates are verified before publication. Source-removal drafts
require a private coordinator authority and the verified destination receipt;
ordinary Save cannot publish one through the exposed review workspace.

Tests reject same physical archives, native hard-link aliases, nested routes,
different persistent storage, unsupported source-removal profiles, stale
reviews, mismatched captured bytes and dirty drafts. Review and cancellation
before destination publication begins leave both original files intact. Once
backup or installation begins, interruption can require journal recovery if
best-effort restoration cannot complete. A combined packed candidate limit is
checked before either publication.

The move publishes the destination first. Source-content/identity changes or
cancellation after that publication produce an explicit destination-only result.
Borrowed source draft changes during source publication prevent installation.
Late source installation failures, changed destinations and lost acknowledgements
retain or restore the source through the existing exclusive publication protocol.
An unconfirmed source result never asserts that the original is still present
at its ordinary pathname. Its journal describes the available recovery files.

`archive_publication_dependency_test.dart` adds **38 cases**, alongside the
existing **25 publisher cases**. The remaining 31 tests in the 94-test gate
exercise affected transfer queue/journal storage and background recovery.
The dependency cases cover:

- Version-2 persistence, recognized revision fields, UTC/local time equivalence,
  malformed records and explicit refusal to downgrade guarded records to v1.
- Destination bytes, physical identity, source account and access-policy
  changes; unsafe paths; and refusal to use an unverified receipt as authority.
- Failure at staging, backup, installation, confirmation and cleanup boundaries,
  including an already installed source candidate after a lost acknowledgement.
- Restart completion only while the captured destination still matches, and
  preservation of the dependency across retries even after the destination's
  completed journal entry is pruned.
- Explicit source restoration after retaining an installed removal candidate,
  lost restoration acknowledgements, occupied recovery paths and changed files.
- Blocking a new source publication while guarded recovery remains unresolved.

The source journal stores the destination receipt ID, credential-free file
snapshot, SHA-256 and access-policy hash. It does not rely on a UI-only flag or
on the completed destination journal remaining present. Native source-backup
cleanup rechecks the destination immediately before its final synchronous source
snapshots and exact unlink. A dependency failure cannot become a success receipt
with only a cleanup warning.

These are two ordered physical publications. They do not provide atomic locking
against unrelated external writers across both files. Dependency checks describe
observed state, and a change after the last observation remains possible. The
[endpoint contract](archive-endpoints.md) states the exact partial-result,
restoration and external-change boundaries.

## Review findings and corrections

Independent implementation review found and corrected these cases:

1. Native file timestamps can use local time while journal JSON restores UTC.
   Comparing the representation rejected an unchanged publication dependency.
   Snapshot matching now compares the same instant, including the existing
   null semantics, with a targeted regression.
2. A recognized `revision` field was absent from the durable snapshot whitelist.
   Every recognized revision field now survives serialization; arbitrary or
   credential-bearing metadata still does not enter the journal.
3. An exposed source review could otherwise be saved outside its paired move.
   Its workspace now binds the coordinator's private authority, persists that
   restriction across draft discard, and requires a destination dependency.
4. Checking a borrowed source draft only between publications was insufficient
   if it changed during source staging. The captured workspace generation is
   now checked throughout source publication and prevents a stale installation.
5. A completed result could be lost on route dismissal, leaving an already open
   source workspace stale. The dialog retains the completed outcome, and the
   borrowed host is invalidated before source publication or pending recovery.
   Idle Escape is handled explicitly; busy Escape cannot dismiss publication.

The three focused host-lifecycle cases pass: completed move dismissed through
Escape, pending source recovery dismissed, and pending source recovery finished.
Both recovery cases close the borrowed host without inventing a new move receipt.
An independent final lifecycle rereview found no remaining concrete issue.

The dedicated move-dialog suite passes 18 cases covering publication,
cancellation, conflicts, separate passwords, both partial outcomes, captured
source invalidation, nested refusal and recovery paths. Controls and results
fit all nine existing languages at 320 px and 1.8x text scaling. Captured-pane
tests additionally exercise F6 and the existing copy/ordinary-operation paths.

## UNIX compress and TAR.Z acceptance

The two creation choices increase the picker from **31 to 33**. The original
bounded LZW encoder emits block streams with 12-, 14- or 16-bit dictionaries
for Fast, Normal or Maximum. Full dictionaries reset when another phrase needs
to be inserted. Empty input emits the valid three-byte header-only stream.
There is no Store or password option. Eligible existing 9–16-bit block/nonblock
streams are rewritten using the normal 14-bit block profile.

Writer/workflow tests cover real dictionary compression, every supported code
width, resets, forward references, input/output bounds, cancellation, byte
identity after decoding, creation format validation and preservation-aware
rewrites. The physical wrapper and immediate-payload requirements also cover
nested compressors, recursively opened containers, renamed wrapped 7z files and
TAR aliases. Unsupported TAR structures remain read-only.

Independent acceptance uses **GNU gzip 1.13**, **libarchive 3.7.4**, a separate
Python LZW framing inspector and Python's TAR reader. All **23 cases** pass:
18 codec cases across the three dictionary profiles, three fresh TAR cases,
one unchanged repack of an external TAR fixture and one edited repack. The
300,000-byte deterministic noise fixture reaches every selected code width and
forces 75, 16 or three dictionary resets. TAR checks compare exact member bytes,
names, entry types, modes, ownership and timestamps.

All **18 codec profiles** are also compiled by Dart 3.13.7 to JavaScript and
executed by **Node.js 24.22.1**. Their output hashes match the independently
accepted native outputs before they are decoded in that runtime. This verifies
actual JavaScript integer/bit-packing behavior beyond compiling the application.

The profile manifest, commands, deterministic fixture recipes and primary
format references are saved in
[UNIX_COMPRESS_WRITER_PROFILES.md](../test/fixtures/archives/UNIX_COMPRESS_WRITER_PROFILES.md).
GNU gzip and libarchive are independent checkers, not added runtime dependencies.
No VaultExplorer implementation source, tests, assets or dependencies were
inspected or imported.

UNIX compress stores neither a payload checksum nor a decoded length. Structural
validation cannot detect every corruption or valid-prefix truncation. Creation
and rewriting compare the entire decoded candidate with the captured source;
the reader and Test archive report retain the underlying format's limits.
Compressed input and decoded output are independently capped at 64 MiB.

## Reproduction and environment

Validation uses pinned **Flutter 3.47.8 / Dart 3.13.7** on Linux, the existing
locked dependency cache, Clang 19.1.7 and a writable temporary directory.
`CI=true` suppresses Flutter's automatic cloud metadata probe;
`FLUTTER_SUPPRESS_ANALYTICS=true` disables analytics. The pinned Dart executable
is on PATH and is provided to the existing background-journal worker fixture
through `CRISP_DART_EXECUTABLE`.

The local validation wrapper serializes Flutter commands, temporarily selects
system SQLite for the existing native hook, and disables the unrelated optional
native ebook conversion engine. It restores the original `pubspec.yaml` bytes
in a `finally` block. These settings are not application changes or committed
dependency updates. The optional ebook engine's build/runtime is outside this
archive validation.

The complete archive/viewer/affected-operation gate is:

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
  test/widget/screen_dialog_localization_test.dart \
  test/transfer_queue_test.dart test/background_transfer_journal_test.dart \
  test/transfer_journal_storage_io_test.dart

flutter test --no-pub --reporter expanded \
  test/help_guide_test.dart test/widget/help_guide_dialog_test.dart

python3 tool/check_help_guides.py
```

Static analysis uses `dart analyze --fatal-infos` for every changed Dart file
relative to the baseline, including standalone reference emitters and portable
checks. The release web build uses `--release --no-pub --no-wasm-dry-run`, with
the built git checkpoint and app version supplied through `GIT_HASH` and
`APP_VERSION`. Those values and all three packaged help asset hashes are checked
in the build output.

The successful release command was:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=GIT_HASH=b9619927 --dart-define=APP_VERSION=1.2.0+13
```

It completed in 188.2 seconds. Both define values are present in the compiled
JavaScript. Each bundled guide's SHA-256 matches both its source bytes and the
reviewed manifest; the bundled manifest itself also matches. GitHub Actions
returned no workflow runs for the release-build checkpoint. The table records
observed local gates and does not claim completed GitHub CI or full platform
acceptance. The closed state of PR #93 is preserved.

## Acceptance boundaries

Cross-container moves require distinct writable top-level native local archives
on the same persistent storage. Nested cross-container routes, remote/browser
publication, replacement-only package sources and single-payload source wrappers
are outside this move workflow. Existing copy and same-workspace member moves
retain their separate contracts.

Interactive edits retain 64 MiB per-member and 256 MiB container/aggregate
limits; the paired move also limits its combined packed candidates to 256 MiB.
Path, entry-count, depth, metadata and original-access-policy constraints remain
in force. Unsupported container structures do not gain write access merely
because a new compressor can encode their bytes.

Directory/archive synchronization, durable background packing, backend-specific
remote/browser publication and existing disk-filesystem rewriting remain separate
work. Linux native tests and a standard JavaScript release web build do not
establish macOS mounting, full platform release acceptance, live provider behavior
or WebAssembly acceptance. Nothing is merged or deployed by this increment.
