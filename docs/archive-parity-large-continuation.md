# Large writable archives and commander parity

Date: 13 November 2026. Branch: `feature/archive-parity-large-20261113`.
Baseline: current `main` plus the preserved archive sync / native TAR continuation.

> Historical implementation checkpoint: the runtime limitations below describe
> the original local session. Subsequent hosted verification completed all six
> common-format jobs, including the five explicit cases above 2 GiB. The newer
> ISO/RAR/DMG candidate also passed 1,856 normal archive tests and all nine
> separately enabled cases above 2 GiB. The completed ten-job hosted workflow,
> exact tested revision and durable receipts are recorded in
> [current runtime verification](archive-containers-runtime-verification.md).
> See [writable ISO, RAR and DMG](archive-iso-rar-dmg.md) for the newer data-image
> creation and editing profiles. The earlier local Flutter restriction remains
> historical evidence, not the current hosted runtime result.

## Requested outcome

Treat ZIP, 7z and TGZ as writable folders, including large members and containers
of at least 2 GiB. Compare Double Commander and Total Commander capabilities and
preserve incremental implementation checkpoints on the remote branch.

## Implemented native foreground scope

The previous workspace collected its container and every replacement in memory:
64 MiB per member and 256 MiB per archive/aggregate. Increasing those constants
would not establish large-file support. This continuation adds native streamed
readers, writers, private file snapshots, streamed imports and publication. Its
explicit native resource budget is 8 GiB for containers and expanded contents;
buffered editors, browsers, protected and nested profiles retain separate bounds.

The branch implements the following native local path for eligible unencrypted
ZIP/CBZ, 7z/CB7, TAR/CBT and TGZ/TAR.GZ archives:

- Open a captured private file snapshot, with bounded metadata and decoded
  members. TGZ validates and spools its TAR stream; it does not collect the
  expanded TAR in memory. The 7z reader uses bounded LZMA/LZMA2 dictionaries.
- Add or replace files through sealed, hash-checked private spools. Create
  folders, rename, move within the archive and remove members in the existing
  draft workspace. Buffered member editors retain their separate limit.
- Build a streamed candidate, reopen it, compare the complete namespace and
  supported metadata, and hash every member against the captured source.
- Publish exactly that reviewed candidate through the existing journal, lease,
  staged and installed readback, exclusive moves and recovery workflow. The
  publisher checks the stream length and digest independently of its producer.
- Copy between eligible archives and prepare ordered two-container moves using
  the streamed workspace budgets. Source removal remains dependent on the exact
  verified destination. Import/copy deadlines scale with bytes while retaining
  inactivity deadlines and cancellation.
- Create ZIP/CBZ, 7z/CB7 Store/LZMA2 and TGZ/TAR.GZ from native selections with
  the larger bound. Fresh TAR/CBT and data-image creation retain their existing
  separate 2 GiB output contracts. Default 7z creation uses the LZMA2 profile.
- Native extraction stages each decoded file, requires decoder EOF/checksum
  completion, independently re-reads its staged SHA-256, and commits only after
  source/destination checks. Cancellation discards the active stage and retains
  already completed extractions. Buffered preview APIs retain their limits.
- Native F3 opens eligible top-level common formats with the streamed reader,
  allowing its integrity action to use the larger member budget. Source grants
  and viewer lifetime checks remain captured. Mislabeled or unsupported writable
  profiles can use the existing bounded read-only fallback with a fresh source;
  nested previews and buffered member viewing retain their separate bounds.

The explicit native budget is **8,589,934,592 bytes (8 GiB)** for a member,
container and total expanded content. TGZ's intermediate TAR must also fit,
including headers and padding. Paths, metadata, dictionaries, entries and depth
have independent bounds. Temporary copies and staged publication require disk
space in addition to the original. This is not an unlimited-size claim.

The first checkpoint preserves existing one-way directory synchronization,
two-container moves and streamed TAR work. Subsequent remote commits preserve
the implementation incrementally. They are development checkpoints, not a
release or a claim of complete runtime acceptance.

## Commander capability comparison

The comparison is about the archive workflow and supported engines, not merely
filename recognition. The linked official manuals/release notes below are the
sources for the competitor columns.

| Capability | Double Commander | Total Commander | CrispCloud on this branch |
| --- | --- | --- | --- |
| Browse an archive as a directory; copy files in/out | Documented archive workflow; writes depend on packer | Documented archive-as-directory workflow | Existing pane/workspace workflow extended to native streamed common formats |
| Add, replace, delete, create directories and save edits | Supported according to archive engine; temporary edit/repack workflow | Archive packing/editing operations; current built-in 7z supports directory rename | Draft mutations, review and verified publication for eligible writer policies; large text/hex buffering remains separately bounded |
| ZIP, 7z and TAR/GZ family writing | Bundled Zip and SevenZip plugins, with platform/backend differences | Built-in ZIP/TAR/GZ and current built-in 7z compression | ZIP/ZIP64, 7z Copy/LZMA2 and TGZ stream natively; TAR already has a writer |
| Large members and containers | Native/external archive engines rather than a small whole-file buffer contract | ZIP64 and large TAR support documented in change history | 8 GiB configured native bound; measured >2 GiB members in all three requested formats, >2 GiB stored ZIP/7z containers and >4 GiB ZIP64 member; see exact evidence below |
| Archive-to-archive transfer | Archive file operations depend on plugins | Explicit archive-to-archive copy support | Captured copies and ordered native two-archive moves; destination verified before source removal |
| Passwords and encryption | Depends on selected engine | Supported archive/packer profiles | Existing supported ZIP AES-256 and 7z encryption retained on the smaller buffered path; large encrypted writes remain open |
| Background packing | File operations/background queues | Documented background packing | Cancellable foreground streaming; durable queued packing/resume is still open |
| Split volumes and packer/plugin ecosystem | External archivers and WCX support | Internal/external packers and WCX ecosystem | No split-volume creation/join or external/WCX adapter in this increment |

Core common-format folder operations now have a native streaming implementation.
Full commander parity is **not closed**: external packers, split archives,
durable background jobs, large protected/nested writes and broader platform
acceptance remain explicit work. Existing container readers are not implicitly
made writers; signed packages and unsupported filesystem metadata stay read-only.

## Verification actually completed

The direct Dart writer and streamed reader each processed a complete
**2,147,483,665-byte member (2 GiB + 17)** in ZIP, TGZ and 7z. Python `zipfile`,
Python `tarfile` and libarchive independently read the generated outputs and
checked every decoded byte. ZIP64 additionally processed a
**4,294,967,313-byte member (4 GiB + 17)** and a 65,536-entry archive. An
independent 7z check caught and led to correction of a missing empty
SubStreamsInfo structure that the same-library round trip had accepted.

The reader checks emitted chunks no larger than 65,536 bytes, with event-loop
heartbeat activity during each large run. These observations establish the
direct native codec path; they are not Flutter UI memory or responsiveness
measurements. The compressed fixtures have small packed sizes. Additional
production-spool checks wrote and completely read a **2,147,483,815-byte stored
ZIP** and a **2,147,483,779-byte Copy-method 7z**, each independently verified.
Those sparse files have real logical lengths and offsets above 2 GiB but used
few allocated disk blocks. These checks do not establish an application-level
multi-gigabyte publication or the full configured 8 GiB limit. See the receipts
for measured runtime/RSS,
software versions, commands, hashes and limitations:

- [Writer and independent decoder evidence](archive-streaming-codec-verification.md)
- [Machine-readable writer measurements](evidence/archive-streaming-codec-verification.json)
- [Streamed reader and workspace status](archive-streaming-reader-verification.md)

The direct offline `test/support/verify_archive_viewer_file.dart` probe also
passed. It checked the native ZIP 8 GiB streaming allowance; bounded fallback
for mismatched ZIP/7z/TAR names and gzip-wrapped ZIP; protected ZIP reopening;
and cancellation after a decoded spool existed, with no scratch files left.
This is a native reader-wrapper check, not an executed Flutter widget test.

Direct static analysis covers the changed production path and the authored
publication, endpoint, creation, workspace and extraction regression tests.
The final combined SDK analysis of **71 changed Dart files**, including the
preserved archive continuation, completed with **No issues found**. The help
validator verified all three offline guides with 23 matching topics each, and
`git diff --check` passed.
Test registrations include source replacement, changed content with unchanged
size/time, cancellation, late output collisions, corrupt staging, stale reviews,
spool disposal, encrypted fallback and opt-in >2 GiB operations. Authored tests
are not reported as passed unless they were actually run.

## Runtime gate blocked by automatic approval review

The local Flutter test launcher was blocked by automatic approval review. Its
reported reason was an attempted request to the cloud instance-metadata endpoint
`169.254.169.254`, with potential exposure of environment credentials/metadata.
The task does not authorize that access. A second launch with package resolution
disabled, analytics suppressed and `AWS_EC2_METADATA_DISABLED=true` was also
rejected. No further Flutter launches or indirect bypass were attempted.

Consequently the new Flutter workspace, publisher, extraction, creation and
widget tests are **not runtime-qualified in this environment**. Direct Dart
codec checks, offline Python/libarchive oracles, static analysis and help-guide
validation are separate checks that could run. Completion of the remaining
runtime gate requires an approved clean Flutter runner. No release build,
installation, deployment or merge to `main` is claimed.

For an approved clean development runner, the focused remaining gate is:

```sh
flutter test --no-pub --concurrency=2 \
  test/archive_streaming_writer_test.dart \
  test/archive_streamed_creation_test.dart \
  test/archive_streamed_workspace_test.dart \
  test/archive_streamed_endpoint_test.dart \
  test/archive_streamed_publication_test.dart \
  test/archive_streamed_extraction_test.dart \
  test/archive_container_publisher_test.dart \
  test/archive_workspace_test.dart \
  test/archive_browser_session_test.dart \
  test/archive_integrity_service_test.dart \
  test/widget/archive_creation_dialog_test.dart \
  test/widget/archive_container_viewer_test.dart
```

Large workspace acceptance additionally uses
`CRISP_RUN_LARGE_ARCHIVE_TESTS=1`; large creation cases use
`--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true`. Run those deliberately with
adequate temporary storage. Neither opt-in substitutes for normal application
and platform acceptance.

## Retained limits and follow-up scope

- Buffered/encrypted/nested profiles: 64 MiB per member and 256 MiB total/packed,
  with the existing smaller compressed-wrapper limits and eight nesting levels.
- Directory-to-archive synchronization keeps its existing 64 MiB source-member
  and 256 MiB source/aggregate contract; this continuation does not expand that
  comparison engine.
- Browser/remote publication still requires missing backend authority/lease
  contracts. General download/upload support is not enough to enable mutation.
- External 7z filter/metadata combinations are accepted only when preservation
  is understood. Large externally produced solid archives need broader runtime
  qualification; unsupported structures are refused or remain bounded/read-only.
- Split-volume handling, external/WCX packers, a durable packing queue,
  cross-platform app acceptance, large incompressible physical containers and
  the full 8 GiB limit remain separate acceptance items.

## Comparison sources

- Double Commander archive workflow: https://doublecmd.github.io/doc/en/multiarc.html
- Double Commander bundled format plugins: https://doublecmd.github.io/doc/en/plugins.html
- Double Commander file operation commands: https://doublecmd.github.io/doc/en/help.html
- Total Commander features: https://www.ghisler.com/featurel.htm
- Total Commander current 7z capabilities: https://www.ghisler.com/mailing.htm
- Total Commander release history: https://www.ghisler.ch/wiki/index.php/List_of_changes

Both products browse archives as directories and expose writes according to the
selected engine. Current Total Commander has built-in 7z compression; older
plugin-only comparisons are obsolete. Format recognition does not establish
mutation support: many disk images and package formats are read-only. GZ is a
single stream; TGZ is the multi-file TAR hierarchy wrapped in gzip. Neither
product's format list justifies claiming every container writable or unlimited.
