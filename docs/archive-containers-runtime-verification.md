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

## Explicit tests above 2 GiB

The successful normal CI run **skipped all five opt-in archive cases above
2 GiB**: three creation cases, one combined writer case, and one TGZ workspace
case. It therefore does not establish hosted completion of those large cases.
The previously recorded standalone large-codec evidence has a different scope.

The focused
[archive-containers workflow](../.github/workflows/archive-containers.yml)
adds six independently reported cases on pushes to
`feature/archive-iso-rar-dmg-20261113` and on `workflow_dispatch`. The normal case
runs all `test/archive_*_test.dart` and `test/widget/archive_*_test.dart` files,
including the streamed suites and subsequent ISO/RAR/DMG regressions using
those naming conventions. Five additional cases select these exact test names
and their source-declared opt-ins:

| Case | Test selection | Enablement |
| --- | --- | --- |
| ZIP creation | `ZIP publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| 7z creation | `7z publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| TGZ creation | `TAR.GZ publishes a member and archive beyond 2 GiB` | `--dart-define=CRISP_RUN_2G_ARCHIVE_TESTS=true` |
| TGZ editing | `native TGZ can review, publish and reopen a member larger than 2 GiB` | `CRISP_RUN_LARGE_ARCHIVE_TESTS=1` |
| Common writers | `ZIP, TGZ and 7z stream a source larger than 2GiB with bounded memory` | `CRISP_STREAMING_ARCHIVE_LARGE=1` |

Every case uses Flutter 3.47.8 on Ubuntu, the repository's native-assets Rust
setup, the existing private dependency authentication convention, and the
tested system-SQLite wrapper. Dependency resolution enforces the lockfile.
Large cases use `--concurrency=1`; up to three isolated matrix runners operate
in parallel. Incremental branch saves do not cancel an active acceptance run. Each job
has a 45-minute cap, with a 35-minute test-step cap to leave time for cleanup
and evidence upload. No deployment or release actions are included.

The normal command uses the main CI's deterministic-test exclusions and four
test workers. Each large command names its exact case with `--plain-name`.
Both produce an expanded human-readable log and an additional JSON event
report; these CLI options are supported by the
[pinned Flutter test command](https://github.com/flutter/flutter/blob/3.47.8/packages/flutter_tools/lib/src/commands/test.dart).

Each job retains a 14-day artifact named
`archive-<case>-<commit>-<attempt>`, including:

- The exact command, selected test files, commit SHA and Flutter version.
- Dependency, SQLite-wrapper and expanded test logs, plus JSON test events.
- `receipt.json` and `SUMMARY.md` with final test counts and completion status.
- Before/after dependency hashes and disk information.

The receipt check requires a completed successful test run and restoration of
the original `pubspec.yaml` and `pubspec.lock`. A large case must report its
exact selected test as passed with zero skipped tests; a skipped or unmatched
opt-in cannot produce a green acceptance result. Missing required streamed
suites also fail the normal case. Logs are retained through failure paths,
known authentication tokens are redacted before upload, and Git configuration
or environment dumps are not uploaded.

**Status when authored:** the normal hosted gate above is verified. The new
focused workflow has been authored for the feature branch; its large-case
receipts must be checked after the workflow runs. No large hosted pass is
claimed by this document before those results exist.
