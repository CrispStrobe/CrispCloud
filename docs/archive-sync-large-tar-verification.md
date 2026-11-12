# Directory synchronization and streamed TAR verification

Date: 12 November 2026. Baseline:
`efd6969aac4a7e9a9dccd3fbef4abee3f56bba32`.
Branch: `feature/archive-rearrange-cpio-20261112`.

This record covers the native one-way directory/archive synchronization
increment and fresh native plain TAR/CBT creation up to a header-inclusive
2 GiB bound. It does not extend buffered compression, browser creation or
existing-container edit bounds. The [continuation record](archive-sync-large-tar-continuation.md)
lists remote checkpoints; the [endpoint contract](archive-endpoints.md) explains
publication and recovery.

## Toolchain and validation environment

Validation uses the pinned Flutter 3.47.8 / Dart 3.13.7 SDK and existing locked
dependencies on Linux. Local tests use system SQLite and temporarily disable
the unrelated optional native ebook engine through hook user definitions. A
serialized wrapper restores the original manifest after each command. No
dependency configuration, lockfile or dependency cache implementation changes
belong to this increment. A web release build and native Linux tests do not
establish native macOS/Windows acceptance.

## Directory snapshot and selected synchronization

The source scanner uses native type/size/modification-time/change-time/mode
witnesses, full streamed file hashes, sorted logical paths and final re-listing
of every visited directory. It rejects symbolic/special entries, ambiguous
names, path and content overflow, sources containing the destination and
physical aliases to the destination. Selected setuid/setgid imports are refused
when adopting the draft; unselected/equal privileged files can be compared.
Ownership, ACLs and extended attributes are outside this captured source
metadata profile. Snapshots ignore access-time changes caused by reading while
retaining modification/change witnesses. Callback byte buffers are copied when
retained, so a provider cannot mutate previously captured content through a
reused chunk.

Snapshot and service tests cover equal/new/changed/archive-only/type-conflict
rows, explicit empty folders, ZIP and TAR output, an archive subdirectory,
unchanged outside members, exact selected updates, separate removal opt-in,
unchecked descendants, content/namespace/metadata changes in unselected or equal
entries, destination replacement, stale pane authority, encryption, cancellation,
and refusal of nested destinations. All **40 snapshot/service tests passed**.
Atomic workspace adoption must fail before
changing the draft on invalid actions. Ordinary workspace Save cannot bypass
the private synchronization owner or replace its original source dependency.

## Durable source-directory dependency

The publication model uses version 3 only for a directory dependency. Version 1
remains unguarded and version 2 remains the archive-move dependency. Malformed,
mixed, missing, downgraded and unknown-version records are refused. Persisted
source evidence contains only filtered metadata, storage identity, tree digest
and bounded counts; it contains no file bytes, passwords or grants.

The native fault-injection suite changes the source before candidate staging,
after preparation, candidate write, backup intent, backup completion,
installation, published confirmation and cleanup. It also covers process-style
journal reload, lost installation acknowledgement, a foreign replacement,
retry dependency substitution/omission, guarded pending cleanup, receipt
revalidation and cancellation during inspection/recovery. A changed source must
block finishing while retaining the verified original or backup. Explicit
restoration may retain the installed candidate before restoring an original
backup; it may never overwrite an unrelated replacement.

The focused publisher gate passed **101 tests across three files**:

```sh
flutter test --no-pub --reporter expanded \
  test/archive_publication_directory_dependency_test.dart \
  test/archive_publication_dependency_test.dart \
  test/archive_container_publisher_test.dart
```

Independent implementation review checked exact dependency persistence,
retry/restart comparison, native source/path validation, pre-install and
lost-acknowledgement checks, final backup deletion and safe restoration. No
publication/recovery blocker remained in that review.

## Streamed TAR implementation and acceptance

Fresh plain TAR/CBT eligibility requires bounded native-local source and
destination capabilities plus verified staged writes. The writer preflights
the complete output, including ordinary/PAX headers, padding and trailer,
before any source payload read. Its normal 256 MiB default and existing TAR
rewrite limit remain unchanged. The creation service deliberately requests the
larger limit only for eligible fresh TAR/CBT output.

The TAR reader now exposes genuine streamed regular members. Creation requests
the larger member limit explicitly; default buffered viewer reads retain the
64 MiB cap. A lazy virtual member test exceeds that cap without materializing
the member. Additional cases reject reads after close, foreign member handles
and lengths above the chosen stream limit. These three focused reader cases
passed. The existing TAR writer, creation and extended-creation gate passed
**112 tests** before adding the large fixture suite.

Packing hashes bounded source chunks into a private file spool. Verification
streams reopened TAR members, re-reads all sources and hashes packed output.
Saving streams a new destination stage, reads that stage back and checks the
sources once more before exclusive no-overwrite commit. Byte totals include
these repeated reads; progress does not stop at packing. Chunk loops yield to
the event loop and check cancellation. The new native tests exercise
cancellation during seven payload passes, same-length source changes during
later phases, staged corruption, late output collisions, post-commit
cancellation and temporary-output cleanup. Existing creation regressions also
exercise changed folder membership and added children.

The complete focused large TAR gate passed **24 tests**. Independent readback
with **Python 3.12.14 `tarfile` and GNU tar 1.35** passed both complete outputs,
including exact content hashes and the applicable namespace/type/size/time/mode
checks. Expected input content is regenerated from deterministic patterns,
independent of the application's archive writer and reader.

| Observed fixture | Plain TAR | CBT |
| --- | ---: | ---: |
| Complete archive bytes | 269,489,664 | 68,159,488 |
| Regular-file payload bytes | 269,485,142 | 68,157,773 |
| Largest member bytes | 201,327,369 | 68,157,773 |
| Largest source/staged read chunk | 65,536 | 65,536 |
| Largest output-transfer chunk | 262,144 | 262,144 |
| Sampled RSS increase | 45,486,080 bytes / 43.38 MiB | 33,275,904 bytes / 31.73 MiB |

For `N` source bytes and `S` output bytes, packing reached `N`, verification
reached `2N + S`, and saving reached `N + 2S`. A 5 ms timer fired throughout
each substantial phase in both runs. Input files were read three times:
packing, the pre-staging source check and the final source check. See the
[saved measurements](../test/fixtures/archives/native-streamed-tar-acceptance.json)
and [reproduction/provenance record](../test/fixtures/archives/NATIVE_STREAMED_TAR.md).

An earlier acceptance attempt exhausted disk space while starting the CBT
stage after TAR had succeeded. The service disposed its private spool/stage;
test teardown removed only its generated source fixtures.
After disposable build output was removed, the full 24-test gate and both
independent readbacks passed. Generated large archives are not committed;
their manifests, deterministic input specification and checker are preserved.

The combined regression results and release-build evidence are recorded below.
The configured 2 GiB output ceiling is distinct from the sizes actually
measured. The source/output chunk limits and sampled RSS are evidence for this
Linux run, not a promised process-memory ceiling on every platform. Fresh
creation needs space for source files, a private packed spool and destination
staging; insufficient space is an explicit failure, not a successful archive.

## UI, help and release acceptance

The comparison entry point captures both pane orientations. The dialog keeps
all rows by default, distinguishes content statuses, provides explicit update
selection and removal opt-in, and presents the full verified candidate before
publication. Recovery identifies the source directory and destination archive.
A forced dialog dismissal waits for in-flight publication to settle and retains
its actual receipt or recovery outcome. UI tests cover native publication,
review cancellation, stale captures, source changes, type conflicts, password
cancellation, recovery and nine locales at a narrow width with enlarged text.

The complete synchronization dialog gate passed **25 tests**. The creation
dialog's focused gate passed **45 tests**, including all nine localized native
TAR/CBT guidance cases. The English, German and French bundled guides and their
source/hash manifest are updated together. All **33 help service/dialog tests**
passed; the manifest validator checked **three guides with 23 topics each**.
The complete combined gates are recorded below.

## Combined regression and release gates

The combined command includes **84 test files**, covering archive readers,
writers, workspaces, publication/recovery, all archive widgets, affected viewer
and file-operation workflows, the transfer queue and ordinary directory
comparison:

```sh
flutter test --no-pub --concurrency=1 --reporter expanded \
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
  test/transfer_journal_storage_io_test.dart \
  test/directory_comparison_service_test.dart
```

The complete serial regression passed **2,094 tests across all 84 files** in
11 minutes 57 seconds, including the new native large TAR/CBT case and all
synchronization widgets. All **23 changed Dart files** passed fatal-info
analysis and formatting.
Whitespace validation and Python reference-checker compilation passed. The
English/German/French guide validator checks both exact content hashes and
matching topic anchors. An initial parallel combined run exhausted the shared
test filesystem when large image and TAR fixtures overlapped; that interrupted
run is not accepted as a regression pass. The complete gate runs with one test
file at a time to keep fixture storage within the available disk budget.

The versioned release command uses the checkpoint containing all application
code and bundled-guide changes:

```sh
flutter build web --release --no-pub --no-wasm-dry-run \
  --dart-define=GIT_HASH=d84c9db5 \
  --dart-define=APP_VERSION=1.2.0+13
```

Release output verification is pending in this intermediate documentation
checkpoint.

## Remaining boundaries

- Directory synchronization is native, one-way, selected-action based and
  limited to eligible top-level destinations. Two-way baselines, nested routes,
  remote/browser publication and general directory mirroring remain separate.
- Source scans observe complete state but cannot exclude independent external
  changes after the final observation. Archive publication retains its two
  exclusive moves and possible temporary absence of the original pathname.
- Synchronization and existing workspace edits retain 64 MiB/member and
  256 MiB source/container budgets. Streamed fresh TAR creation does not enlarge
  those limits or promise larger extraction/preview support.
- Durable queued packing, process restart of a half-packed new archive and
  background worker lifecycle are not implemented by this foreground increment.
- TAR has no stored payload checksum. New output is verified against captured
  source SHA-256 values; a later standalone integrity test still needs trusted
  expected values to establish payload identity.
- No native release/device or live remote-provider acceptance is implied by
  local Linux tests and a release web build. Existing PR #93 remains closed.

No external packer is shipped, no dependency is added or upgraded, and no
VaultExplorer implementation, tests, assets or dependencies were inspected,
copied or imported.
