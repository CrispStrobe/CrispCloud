# Archive container runtime verification

## Retained source and completed hosted gate

The archive checkpoint `5b303280f1149051ef3ecd8c36a6ba3ec651936b` is retained in
`main`. Merge commit
[`6795916c576fe537a6d041d4cca41bc6d6dd0a34`](https://github.com/CrispStrobe/CrispCloud/commit/6795916c576fe537a6d041d4cca41bc6d6dd0a34)
has that checkpoint as its second parent. The GitHub comparison with
`794bde82693e07a6e04ed1490bfa228f154e6e5c` reports 20 commits ahead, zero behind,
and the archive checkpoint as the merge base. The associated-PR endpoints for
both SHAs returned empty lists; the merge commit and Actions runs provide the
evidence independently of a PR.

The first workflow on the checkpoint itself was
[Shared encrypted providers, run 43331655510](https://github.com/CrispStrobe/CrispCloud/actions/runs/43331655510).
It passed provider and CLI tests; it did not establish the archive runtime gate.

The completed archive runtime evidence is
[CI run 43347170438](https://github.com/CrispStrobe/CrispCloud/actions/runs/43347170438)
at commit `d56dfe9f7bc1d3e764af0f3ee383ccc235f039bc`. Its
[Analyze + Test (Linux) job 131629212597](https://github.com/CrispStrobe/CrispCloud/actions/runs/43347170438/job/131629212597)
passed analysis and the full deterministic application test suite. The downloaded
job log ends its application test step with this exact result:

```text
2026-11-13T02:22:07.0556947Z 🎉 11080 tests passed, 43 skipped.
```

That log contains **1,769 distinct passing tests in archive-named test files**,
zero failing archive tests, and five skipped archive tests. Selected suites are:

| Suite | Passed | Skipped |
| --- | ---: | ---: |
| `test/archive_streamed_creation_test.dart` | 36 | 3 |
| `test/archive_streamed_endpoint_test.dart` | 11 | 0 |
| `test/archive_streamed_publication_test.dart` | 11 | 0 |
| `test/archive_streamed_workspace_test.dart` | 9 | 1 |
| `test/archive_streamed_extraction_test.dart` | 16 | 0 |
| `test/widget/archive_container_viewer_test.dart` | 19 | 0 |
| `test/widget/archive_creation_dialog_test.dart` | 45 | 0 |
| `test/archive_large_tar_creation_test.dart` | 24 | 0 |

The successful log explicitly records:

- ZIP, 7z and TAR.GZ creation with real member data and output above 64 MiB,
  at `01:58:27.9509289Z`, `01:59:13.6224978Z` and `02:00:20.8994584Z`.
- ZIP, 7z and TGZ extraction of a 65 MiB member, at `01:56:19.4208389Z`,
  `01:56:33.5283276Z` and `01:56:48.2380687Z`.
- Native ZIP import beyond the old 64 MiB boundary at `01:57:56.0755755Z`.
- Native F3 checking a 65 MiB member while previews remain bounded at
  `02:13:12.9786064Z`.
- Native protected ZIP reopening fresh borrowed sources at
  `02:13:14.5556141Z`, plus encrypted-header password retry and lifetime tests.
- Native ZIP, 7z, TAR and TGZ folder edits publishing a streamed review and
  reopening, between `02:16:34.8892021Z` and `02:16:36.5534645Z`.
- Streamed TAR above 256 MiB and CBT above 64 MiB with verified readback at
  `02:03:42.6553468Z`.

All times in this section are UTC on 2026-11-13 and refer to the linked Linux
job. These are hosted Flutter runtime results, superseding the earlier
static-only status of the normal application tests.

## Earlier failures and the fixes that passed

The previous main CI run,
[43334515720 at `8638e655`](https://github.com/CrispStrobe/CrispCloud/actions/runs/43334515720),
exposed two archive defects:

1. [Web build job 131587203147](https://github.com/CrispStrobe/CrispCloud/actions/runs/43334515720/job/131587203147)
   failed at `2026-11-13T00:20:04Z` in
   `lib/services/archive_sevenz_metadata.dart:737:49`:

   ```text
   Error: The integer literal 253402300799999999 can't be represented exactly in JavaScript.
   ```

2. [Linux test job 131587203319](https://github.com/CrispStrobe/CrispCloud/actions/runs/43334515720/job/131587203319)
   recorded the failing test `cancellation before destination publication has
   no physical mutations` at `2026-11-13T00:31:51Z`:

   ```text
   Expected: throws <Instance of 'FileOperationCancelled'>
   Which: threw ArchiveViewException:<Archive opening was cancelled.>
   ```

   The stack reached `ArchiveWorkspace._verifyPacked` through
   `openStreamedArchiveSource`. This job was ultimately cancelled and does not
   constitute a completed application test pass.

Commit
[`d56dfe9f7bc1d3e764af0f3ee383ccc235f039bc`](https://github.com/CrispStrobe/CrispCloud/commit/d56dfe9f7bc1d3e764af0f3ee383ccc235f039bc)
changed the timestamp check to the exactly representable exclusive year-10000
bound and preserved `FileOperationCancelled` at the workspace verification
boundary. Its subsequent CI passed both the web build and Linux tests. The same
archive move cancellation test has an explicit passing log entry at
`2026-11-13T01:53:26.0756118Z` in job `131629212597`.

The earlier integration fix,
[`524d353322854e0daf41e7c9afb6c2e2dfa66f3d`](https://github.com/CrispStrobe/CrispCloud/commit/524d353322854e0daf41e7c9afb6c2e2dfa66f3d),
also preserved encrypted 7z header password retries, advanced the widget test's
fake clock while waiting for native I/O, and extended the main Linux CI job
budget to 45 minutes. The normal gate above includes those changes.

## Completed hosted acceptance above 2 GiB

The normal main CI run above skipped the five opt-in archive cases above
2 GiB. The subsequent focused
[Archive containers run 43364516899](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899)
**completed successfully in all six jobs** at commit
[`80fbf6f2978accc3521b06ee6449d4c52c814b90`](https://github.com/CrispStrobe/CrispCloud/commit/80fbf6f2978accc3521b06ee6449d4c52c814b90).
Attempt 1 started at `2026-11-13T04:17:13Z`; GitHub reports the completed run at
`2026-11-13T04:32:02Z`. Each job's logs confirm Flutter 3.47.8, restored
dependency inputs, a successful receipt check and a successful evidence upload.

These are the receipt summaries printed by the jobs, with the exact UTC
timestamp of each summary on 2026-11-13:

| Acceptance case | Hosted job | Passed | Failed | Skipped | Receipt timestamp |
| --- | --- | ---: | ---: | ---: | --- |
| Normal archive regression suite | [131685656432](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/job/131685656432) | 1,769 | 0 | 5 | `04:26:16.3503945Z` |
| ZIP creation above 2 GiB | [131685656801](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/job/131685656801) | 1 | 0 | 0 | `04:23:28.9057829Z` |
| 7z creation above 2 GiB | [131685656763](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/job/131685656763) | 1 | 0 | 0 | `04:25:03.5222981Z` |
| TGZ creation above 2 GiB | [131685656817](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/job/131685656817) | 1 | 0 | 0 | `04:31:58.7452729Z` |
| TGZ editing and publication above 2 GiB | [131685656785](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/job/131685656785) | 1 | 0 | 0 | `04:31:52.8468361Z` |
| ZIP, TGZ and 7z writers above 2 GiB | [131685656802](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/job/131685656802) | 1 | 0 | 0 | `04:29:54.5707058Z` |

The normal job's five skipped large cases are therefore covered separately by
five completed, explicitly enabled acceptance jobs. The combined writer job
contains one test that exercises all three formats.

### What the completed large cases establish

The ZIP, 7z and TGZ
[creation tests at the tested commit](https://github.com/CrispStrobe/CrispCloud/blob/80fbf6f2978accc3521b06ee6449d4c52c814b90/test/archive_streamed_creation_test.dart)
use a real source file of **2,147,487,745 bytes** (`2 GiB + 4,097`), explicitly
select stored/uncompressed output, assert that the published archive itself
exceeds 2 GiB, reopen and verify its members, and require no staged files to
remain. Their passing assertions also cap observed storage reads at 65,536
bytes and upload chunks at 262,144 bytes.

The
[TGZ workspace test](https://github.com/CrispStrobe/CrispCloud/blob/80fbf6f2978accc3521b06ee6449d4c52c814b90/test/archive_streamed_workspace_test.dart)
opens a **2,147,483,665-byte member** (`2 GiB + 17`), renames it, produces a
sealed streamed review, publishes it, reopens the published archive and checks
every decoded byte and the exact length. It also checks that the buffered
member read and buffered review-byte access are refused for this large path.

The combined writer job prints these measured results:

| Writer | Source bytes | Packed bytes | Elapsed | Reported RSS growth | Largest output chunk |
| --- | ---: | ---: | ---: | ---: | ---: |
| ZIP | 2,147,483,665 | 2,087,412 | 12,266 ms | 48,570,368 bytes | 4,109 bytes |
| TGZ | 2,147,483,665 | 2,087,347 | 12,071 ms | 16,216,064 bytes | 4,160 bytes |
| 7z | 2,147,483,665 | 925,824 | 40,415 ms | 27,762,688 bytes | 262,144 bytes |

The exact writer evidence appears at `04:29:01.9409102Z`,
`04:29:14.0121915Z` and `04:29:54.4278184Z` in the linked writer job.
These compressible fixtures demonstrate streaming of an expanded member above
2 GiB; the separate creation cases establish published containers above 2 GiB.
RSS growth is the value reported by the test in that runner, not a universal
process-memory guarantee.

### Retained baseline artifacts

GitHub lists all six uploaded artifacts as unexpired, with retention through
2026-11-27. Their names use the complete tested commit and attempt 1:

| Case | Artifact |
| --- | --- |
| Normal | [archive-normal-80fbf6f2978accc3521b06ee6449d4c52c814b90-1](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/artifacts/14010057198) |
| ZIP creation | [archive-creation-zip-2g-80fbf6f2978accc3521b06ee6449d4c52c814b90-1](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/artifacts/14009823470) |
| 7z creation | [archive-creation-7z-2g-80fbf6f2978accc3521b06ee6449d4c52c814b90-1](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/artifacts/14009652964) |
| TGZ creation | [archive-creation-tgz-2g-80fbf6f2978accc3521b06ee6449d4c52c814b90-1](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/artifacts/14010039265) |
| TGZ editing | [archive-workspace-tgz-2g-80fbf6f2978accc3521b06ee6449d4c52c814b90-1](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/artifacts/14009754689) |
| Common writers | [archive-writers-2g-80fbf6f2978accc3521b06ee6449d4c52c814b90-1](https://github.com/CrispStrobe/CrispCloud/actions/runs/43364516899/artifacts/14010501256) |

The counts above were read from decoded job logs and cross-checked against
successful receipt and upload steps and the run's artifact listing. The binary
artifact archives were not independently downloaded during this audit.

## Integrated ISO, RAR and DMG acceptance gate

The
[archive-containers workflow](../.github/workflows/archive-containers.yml)
now defines **ten independently reported cases** on relevant pushes to
`feature/archive-iso-rar-dmg-20261113` and on `workflow_dispatch`. The normal case
runs all `test/archive_*_test.dart` and `test/widget/archive_*_test.dart` files,
including the new ISO/RAR/DMG suites. Nine large cases select these exact test
names and their source-declared opt-ins:

| Case | Test selection | Enablement |
| --- | --- | --- |
| ZIP creation | `ZIP publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| 7z creation | `7z publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| TGZ creation | `TAR.GZ publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| TGZ editing | `native TGZ can review, publish and reopen a member larger than 2 GiB` | `CRISP_RUN_LARGE_ARCHIVE_TESTS=1` |
| Common writers | `ZIP, TGZ and 7z stream a source larger than 2GiB with bounded memory` | `CRISP_STREAMING_ARCHIVE_LARGE=1` |
| RAR5 Store creation | `RAR5 Store publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| ISO editing and publication | `ISO data image creates, edits and publishes beyond 2 GiB` | `CRISP_RUN_LARGE_ARCHIVE_TESTS=1` |
| RAR5 Store editing and publication | `RAR5 Store creates, edits and publishes beyond 2 GiB` | `CRISP_RUN_LARGE_ARCHIVE_TESTS=1` |
| DMG editing and publication | `DMG (HFSX data volume) creates, edits and publishes beyond 2 GiB` | `CRISP_RUN_LARGE_ARCHIVE_TESTS=1` |

The new ISO/RAR/DMG workflow cases use `2 GiB + 4,097` bytes, require a published
outer container above 2 GiB, apply folder changes and member additions/removals,
verify that cancellation leaves the original unchanged, then publish, reopen
and compare the complete streamed member SHA-256. DMG uses bounded nonzero
input blocks because UDIF represents all-zero blocks without payload even when
zlib compression is disabled.

Every case uses Flutter 3.47.8 on Ubuntu, the repository's native-assets Rust
setup, the existing private dependency authentication convention, and the
tested system-SQLite wrapper. Dependency resolution enforces the lockfile.
Large cases use `--concurrency=1`; up to three isolated matrix runners operate
in parallel. With the completed baseline preserved, the final integration gate
cancels superseded runs on the same branch so that partial codec checkpoints
do not delay validation of the latest integrated commit. A cancelled run does
not count as a pass. Push path filters exclude documentation-only checkpoints.
Each job has a 45-minute cap, with a 35-minute test-step cap to leave time for
cleanup and evidence upload. No deployment or release actions are included.

The normal command uses the main CI's deterministic-test exclusions and four
test workers. Each large command names its exact case with `--plain-name`.
Both produce an expanded human-readable log and an additional JSON event
report; these CLI options are supported by the
[pinned Flutter test command](https://github.com/flutter/flutter/blob/3.47.8/packages/flutter_tools/lib/src/commands/test.dart).

Before its runtime suite, the normal job validates the help guides, runs Dart
analysis over the archive integration and test globs, and compiles
[`verify_archive_portable_data_codecs.dart`](../test/support/verify_archive_portable_data_codecs.dart)
with `dart compile js -O1`. Node executes the compiled probe and verifies the
complete small ISO, RAR and DMG payloads. This is a portable codec smoke test;
native publication and large browser writes are outside its scope. The normal
receipt now explicitly requires the native-container workflow, DMG rewrite,
streamed ISO and stored-RAR suites as well as the existing streamed suites.

Each job retains a 14-day artifact named
`archive-<case>-<commit>-<attempt>`, including:

- The exact command, selected test files, commit SHA and Flutter version.
- Dependency, SQLite-wrapper and expanded test logs, plus JSON test events.
- Help-validation, analysis and portable JavaScript compile/runtime logs in
  the normal case.
- `receipt.json` and `SUMMARY.md` with final test counts and completion status.
- Before/after dependency hashes and disk information.

The receipt check requires a completed successful test run and restoration of
the original `pubspec.yaml` and `pubspec.lock`. A large case must report its
exact selected test as passed with zero skipped tests; a skipped or unmatched
opt-in cannot produce a green acceptance result. Missing required streamed
suites also fail the normal case. Logs are retained through failure paths,
known authentication tokens are redacted before upload, and Git configuration
or environment dumps are not uploaded.

**Verified status:** the common ZIP/7z/TGZ baseline passed both its normal
hosted regression suite and all five explicit hosted cases above 2 GiB at
`80fbf6f2978accc3521b06ee6449d4c52c814b90`. The expanded ten-case gate must be
assessed at its own integrated commit before claiming hosted ISO/RAR/DMG
acceptance; the completed baseline does not prove those subsequent changes.
