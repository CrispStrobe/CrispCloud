# Archive container runtime verification

The subsequent [archive queue and background packing continuation](archive-operation-queue.md)
passed 2,067 archive/transfer/widget regressions and three separate worker cases
above 2 GiB at `6eab6a33ffd374bfc9343a692b3df43c85758a1b`. This document retains
the earlier physical-container and complete creation/publication acceptance.

## Commander workflow continuation

The later `feature/archive-commander-parity-20261113` branch and
[PR #97](https://github.com/CrispStrobe/CrispCloud/pull/97) build on the shared
operation queue and add batch workflows, installed packers, SFX and numbered-7z
reading. Their source and verification record is in the
[Commander workflow guide](archive-commander-workflows.md). Verification of the
combined source is pending its final frozen-revision gate. The hosted runs below
continue to qualify their recorded revisions; their earlier pass counts are
not tests of every new workflow or option.

## Current integrated commit

The integrated candidate is
[`f1a03e807b1261361a17f66a37fa94858481e1e7`](https://github.com/CrispStrobe/CrispCloud/commit/f1a03e807b1261361a17f66a37fa94858481e1e7)
on `feature/archive-iso-rar-dmg-20261113`. Its
[Archive containers run 43369528217](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217)
**completed successfully in all ten matrix cases**. GitHub reports attempt 2
as `completed` with conclusion `success`, updated at
`2026-11-13T06:03:13Z`, on that exact application revision.

The normal archive suite passed **1,856 tests with zero failures and ten
explicit large-case skips**. All **nine separately enabled large cases passed
with zero failures and zero skips**. These cover ZIP, 7z, TGZ and RAR5 Store
creation; ISO, DMG, RAR5 Store and TGZ editing/publication; and the combined
ZIP/TGZ/7z streaming-writer case. The completed common-format baseline below
remains independent evidence at its own earlier commit.

The repository retains a
[compact machine-readable hosted receipt](evidence/archive-hosted-acceptance-f1a03e.json)
with the exact production revision, attempts, completed test counts and
selected names, verification/restoration results, job and artifact identifiers,
download-verified artifact hashes, timestamps and explicit pending cases. This
preserves the acceptance summary beyond the uploaded artifacts' retention;
the final receipt contains ten completed cases and an empty pending list.

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
successful receipt and upload steps and the run's artifact listing. These six
baseline artifact archives were not independently downloaded during this audit;
the final integrated artifacts below were downloaded and digest-checked.

## Integrated ISO, RAR and DMG acceptance gate

### Completed normal regression result

The final candidate's
[normal job 131701898537](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131701898537)
completed successfully at `2026-11-13T05:13:58Z`, with these exact log lines:

```text
2026-11-13T05:13:52.0983548Z 06:08 +1856 ~10: All tests passed!
2026-11-13T05:13:52.3656185Z PASS — 1856 passed, 0 failed, 10 skipped.
```

The
[normal evidence artifact 14012002987](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14012002987)
was independently downloaded and its `receipt.json`, JSON test events, analysis,
help and portable-runtime logs were inspected. Its receipt identifies the exact
candidate SHA and attempt 1, with `verified: true`, `completed: true`, successful
test outcome and dependency restoration, no missing required suites and no
malformed event lines. GitHub records the artifact's SHA-256 as
`be9adff2dc8bede22e04a64f9540ebd3591d94805ab37fc08a56b2e1a288ad07`
and retention through `2026-11-27T05:13:52Z`.

Selected new suites in that completed JSON event report are:

| Suite | Passed | Skipped |
| --- | ---: | ---: |
| `archive_dmg_rewrite_test.dart` | 29 | 0 |
| `archive_dmg_transfer_names_test.dart` | 6 | 0 |
| `archive_dmg_workspace_test.dart` | 5 | 0 |
| `archive_iso_streamed_test.dart` | 13 | 0 |
| `archive_native_container_workflows_test.dart` | 3 | 3 |
| `archive_rar_stored_test.dart` | 3 | 1 |
| `archive_rar_workspace_test.dart` | 9 | 0 |

The same job verified three offline help guides with 23 matching topics each.
Its Dart analysis succeeded with two pre-existing informational lints only:
`curly_braces_in_flow_control_structures` in
`archive_container_publisher_test.dart:533` and `prefer_const_constructors` in
`archive_operations_test.dart:82`. The compiled JavaScript probe passed complete
payload verification for ISO (61,440 packed bytes), RAR (8,264 packed bytes) and
DMG (4,548 packed bytes). These are small portable-codec checks; they do not
establish browser UI or large browser publication coverage.

Attempt 1 was cancelled at `2026-11-13T05:14:38Z`, after the normal job had
finished. The branch still identified the same candidate; the available
metadata did not explain the cancellation. The ISO and DMG large jobs had no
reported assertion failures before cancellation, but neither completed a test.
Their receipts correctly reported `FAIL / incomplete`, with zero completed,
failed or skipped tests. Interrupted dependency restoration also failed in
those cancelled jobs. These are incomplete runs, not large-file acceptance.
The other seven large jobs had not executed.

Only unsuccessful jobs were requested again on the unchanged candidate;
attempt 2 was queued at `2026-11-13T05:17:04Z`. The normal result above remains
the completed attempt-1 result, rather than a newly executed normal suite.
The latest attempt lists that retained result as
[job 131706501139](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706501139)
with its original execution timestamps. The original job and attempt-1
artifact remain the evidence for its actual test execution.

### Completed integrated large results

All nine explicit large cases completed successfully in attempt 2 on the same
candidate. The final API snapshot at `2026-11-13T06:03:45Z` shows all ten matrix
jobs successful, including the retained normal result. No large case is
pending, skipped or incomplete.

| Acceptance case | Hosted job | Passed | Failed | Skipped | Receipt timestamp (UTC, 2026-11-13) | Artifact |
| --- | --- | ---: | ---: | ---: | --- | --- |
| DMG creation, editing and publication above 2 GiB | [131706499666](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499666) | 1 | 0 | 0 | `05:42:48.5728523Z` | [14013223215](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14013223215) |
| RAR5 Store creation, editing and publication above 2 GiB | [131706499653](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499653) | 1 | 0 | 0 | `05:46:09.1470867Z` | [14013084191](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14013084191) |
| ISO creation, editing and publication above 2 GiB | [131706499639](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499639) | 1 | 0 | 0 | `05:48:50.4612951Z` | [14013228194](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14013228194) |
| RAR5 Store creation above 2 GiB | [131706499674](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499674) | 1 | 0 | 0 | `05:48:56.1120506Z` | [14013622486](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14013622486) |
| ZIP creation above 2 GiB | [131706499337](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499337) | 1 | 0 | 0 | `05:53:51.3373811Z` | [14013868533](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14013868533) |
| 7z creation above 2 GiB | [131706499584](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499584) | 1 | 0 | 0 | `05:57:24.1050025Z` | [14014810213](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14014810213) |
| TGZ creation above 2 GiB | [131706499622](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499622) | 1 | 0 | 0 | `05:57:44.2062639Z` | [14013264411](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14013264411) |
| ZIP, TGZ and 7z writers above 2 GiB | [131706499761](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499761) | 1 | 0 | 0 | `06:00:48.1535543Z` | [14014282046](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14014282046) |
| TGZ editing and publication above 2 GiB | [131706499669](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/job/131706499669) | 1 | 0 | 0 | `06:03:08.5057334Z` | [14014631642](https://github.com/CrispStrobe/CrispCloud/actions/runs/43369528217/artifacts/14014631642) |

The DMG job logged `19:19 +1: All tests passed!` at
`2026-11-13T05:42:48.3316452Z` and completed at `05:42:54Z`. Its downloaded
artifact receipt identifies the exact selected test,
`DMG (HFSX data volume) creates, edits and publishes beyond 2 GiB`, with
`verified: true`, `completed: true`, `skipped: false`, successful test outcome
and dependency restoration, and no malformed event lines. The downloaded ZIP's
SHA-256 matches GitHub's recorded digest:
`57ac98544f99bae0468af7796fcaf0543fc09982883734e81a851e5dca084498`.
The artifact is named
`archive-dmg-workflow-2g-f1a03e807b1261361a17f66a37fa94858481e1e7-2`
and is retained through `2026-11-27T05:42:48Z`.

This completed application test establishes the full DMG fixture described
below, including initial, reviewed and installed outer images above 2 GiB,
cancellation without replacing the original, complete reopened member hashing,
source retention and staging cleanup.

The RAR workflow job logged `18:12 +1: All tests passed!` at
`2026-11-13T05:46:08.6384316Z` and completed at `05:46:14Z`. Its downloaded
receipt confirms the exact selected test,
`RAR5 Store creates, edits and publishes beyond 2 GiB`, passed without a skip,
with successful dependency restoration and a completed verified receipt. Its
ZIP SHA-256 matches GitHub's digest
`fcdfd5dabf291cd87a8f7da205e603b0c42523e8c16d67b937704a5997b842e5`;
artifact retention runs through `2026-11-27T05:46:09Z`. This establishes the RAR
application workflow above 2 GiB in addition to the separate direct codec
proof described below.

The ISO job logged `22:11 +1: All tests passed!` at
`2026-11-13T05:48:50.2686186Z` and completed at `05:48:54Z`. The RAR creation
job logged `03:38 +1: All tests passed!` at `05:48:55.9796007Z` and completed
at `05:49:00Z`. Their downloaded receipts each identify the exact selected
test, with one passed test, zero failures, zero skips, completed verification
and successful dependency restoration. Both downloaded ZIP digests match
GitHub metadata. The durable JSON receipt records those hashes and each
artifact's retention timestamp, together with the normal, DMG and RAR workflow
receipts.

ZIP creation logged `04:46 +1: All tests passed!` at
`2026-11-13T05:53:51.1622969Z` and completed at `05:53:55Z`. Its downloaded
receipt confirms the selected large test passed with successful restoration
and verification; the downloaded artifact digest matches GitHub metadata.
The durable receipt also preserves the workflow's literal 16 required normal
suite names and the empty missing-suite result from the completed normal job.
The 7z and TGZ creation receipts were also downloaded: both confirm the exact
selected test, one pass, zero failures, zero skips, completed verification and
successful input restoration. Both artifact digests match GitHub metadata.

The combined writer job logged `00:46 +1: All tests passed!` at
`2026-11-13T06:00:48.0342855Z` and completed at `06:00:53Z`. TGZ
editing/publication logged `04:53 +1: All tests passed!` at
`06:03:08.3414872Z` and completed at `06:03:12Z`. Both downloaded receipts
confirm the exact selected case, one pass, zero failures, zero skips,
successful restoration and completed verification. Their artifact digests
also match GitHub metadata. All ten completed artifacts, including the normal
attempt-1 artifact, were independently downloaded and digest-checked.

The final combined writer job reports these measurements on the tested
application revision:

| Writer | Source bytes | Packed bytes | Elapsed | Reported RSS growth | Largest output chunk |
| --- | ---: | ---: | ---: | ---: | ---: |
| ZIP | 2,147,483,665 | 2,087,412 | 8,547 ms | 46,002,176 bytes | 4,109 bytes |
| TGZ | 2,147,483,665 | 2,087,347 | 8,557 ms | 15,601,664 bytes | 4,160 bytes |
| 7z | 2,147,483,665 | 925,824 | 29,504 ms | 28,246,016 bytes | 262,144 bytes |

These exact lines occur at `06:00:09.9460975Z`, `06:00:18.5040747Z` and
`06:00:48.0092446Z` in the linked writer job and are retained in the durable
JSON receipt. This fixture proves streaming of compressible expanded members
above 2 GiB. The separate creation cases establish actual outer containers
above 2 GiB. The measured RSS growth is specific to that runner and test; it
is not a universal memory ceiling.

### Exact normal skips and large-case coverage

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

Those nine test names are nine of the ten exact skips in the final normal
artifact, and each now has a completed passing hosted case on the same
application revision. The normal JSON records `skip: true` and
`skipReason: null` for all ten;
the opt-in explanations in the table come from the tested source declarations,
not a reason string emitted by the runner. Creation and native workflow cases
also require native exclusive-rename support, which is available in these
Ubuntu jobs. Ordinary runs deliberately omit their large-case opt-ins.

The remaining normal skip is
`RAR5 Store writes and fully reads a container larger than 2 GiB` in
`test/archive_rar_stored_test.dart`, enabled by `CRISP_RAR_STORED_LARGE=1`.
It has no dedicated matrix job. The same `verifyRarStoredLarge` function was
executed directly on Dart, with an independent libarchive/Python check, as
documented in
[archive-rar-store-verification.md](archive-rar-store-verification.md) and
[its structured receipt](evidence/archive-rar-store-verification.json).
That check wrote a dense 2,147,483,788-byte RAR5 Store archive, fully verified its
2,147,483,665-byte member and its trailing member, and observed payload chunks
no larger than 262,144 bytes. This is separate direct codec evidence; it is not
an additional hosted Flutter pass. The two dedicated hosted RAR cases exercise
application creation and editing/publication respectively.

### Scope of the integrated large fixtures

The new ISO/RAR/DMG workflow cases use `2 GiB + 4,097` bytes, require a published
outer container above 2 GiB, and also require the sealed edited review and the
installed container to remain above 2 GiB. They apply folder changes and member
additions/removals, verify that cancellation leaves the original outer SHA-256
unchanged, then publish, reopen and compare the complete streamed member
SHA-256. They assert reopened member chunks no larger than 256 KiB, retain the
source file and check that staging files are gone.

DMG uses deterministic high-entropy 256 KiB blocks because UDIF represents
all-zero blocks without payload, and the review writer can compress repeated
low-entropy bytes. The final fixture's block is larger than zlib's history
window; the resulting raw-run choice keeps the edited outer image above
2 GiB. The explicit size assertions cover the initial image, review and
installed result, so a highly compressed output cannot substitute for that
outer-container proof.

These application fixtures use the native local backend on Ubuntu. The small
normal cases also extract the edited member through the shared extraction
entry point; the large variants verify every reopened member byte through the
workspace stream instead of repeating extraction to another large file. The
implemented 8 GiB bounds are guards, not a measurement of every size through
8 GiB or a claim of unlimited size. This gate does not benchmark remote
providers or establish large-file behavior on every desktop platform.

A separate direct Dart probe on the same frozen production revision completed
DMG creation and rewriting through the production file spools in 187,275 ms.
Its 2,147,487,745-byte member produced an original outer image of
2,148,753,423 bytes and an edited image of 2,147,601,376 bytes. Both passed the
canonical HFSX profile and UDIF CRC inspections, and complete generated,
original-on-rewrite and reopened-candidate payload hashes matched. The
[DMG streaming verification](archive-dmg-streaming-verification.md) retains the
exact reproducer, structured receipt, bounded-I/O measurements, metadata,
source-lifetime and cleanup checks. This is direct codec and spool evidence;
the separate completed hosted DMG receipt above establishes the application
creation, editing and publication path.

### Workflow and evidence contract

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
receipt now requires 16 named suites, including the native-container workflow,
DMG rewrite, streamed ISO, stored RAR, exact RAR workspace, DMG workspace and
DMG transfer-name suites, as well as the existing streamed suites.

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

### Interim failures and the final normal pass

The cancelled interim runs exposed real failures before cancellation. Their
partial counts are retained for provenance and do not represent completed
normal-suite results:

| Interim source and run | Observed normal result before cancellation | Correction included in final candidate |
| --- | --- | --- |
| `17b36e2478a13ea620f8ed677549b7b8ac38eb76`, [run 43367522239](https://github.com/CrispStrobe/CrispCloud/actions/runs/43367522239), job `131695452205` | Partial receipt: 1,803 passed, 10 failed, 10 skipped. Nine locales failed `distinguishes native archive and data image limits at narrow large text` with `StateError: Bad state: No element` in the format-selection helper at `archive_creation_dialog_test.dart:153`. | The widget helper now waits for the updated scroll layout, targets the actual popup list and its scrollable, starts from its real minimum extent, and verifies the chosen format. These were test interaction failures, not layout-overflow reports. |
| Same interim run and job | `a native 80 MiB ISO lists and reopens without releasing its viewer source` failed its first listing wait at `archive_container_viewer_test.dart:382`; the viewer remained at `Preparing view…`. | Native read-only ISO viewing skips the write-preservation scan and returns an explicit read-only inspection. Workspace opens and candidate verification retain the complete preservation scan. This avoids reading an entire opaque padded tail before listing, without authorizing edits. |
| `8c8eb16c9eedc18f9e8d66193b64a718df3e4e37`, [run 43368576022](https://github.com/CrispStrobe/CrispCloud/actions/runs/43368576022), job `131698839603` | Partial receipt: 1,599 passed, one failed, eight skipped. `buffered unsupported RAR fallback remains read-only, encrypted=true` expected `hello, rar!`, but the fixture correctly decoded `hello, rar!\n`, at `archive_rar_workspace_test.dart:206`. | Final commit `f1a03e807b1261361a17f66a37fa94858481e1e7` corrects only this expected fixture literal. Its production code is identical to parent `07248aaa277fdecf3462190f87fb341d8fddf7e8`. |

The completed final normal job includes all of these regression cases and has
zero failed tests. The same source also includes the reviewed buffered-RAR
timestamp-preservation fix and HFSX Unicode normalization in workspace,
directory-sync and import-preview matching, with their required regression
suites. Cancelled jobs' later dependency-restoration failures are incomplete
cleanup evidence; they are not additional archive assertion failures.

**Verified status:** the integrated application revision
`f1a03e807b1261361a17f66a37fa94858481e1e7` passed its complete normal archive
suite and all nine explicit hosted cases above 2 GiB. All ten matrix cases are
successful, with no pending large receipt. The common ZIP/7z/TGZ baseline at
`80fbf6f2978accc3521b06ee6449d4c52c814b90` is retained separately; final
acceptance rests on the completed integrated run and the exact skip mapping
above.
