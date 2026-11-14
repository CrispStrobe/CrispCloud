# Branch integration and cleanup — 14 November 2026

Audited all remote heads in six repositories. Removed **144** merged, patch-equivalent or reviewed superseded topic branches. Branch deletion used expected-head leases; original commit objects are retained locally under `refs/integration-audit/20261114/`. Existing local branches, worktrees and their edits were left intact.

| Repository | Audited main checkpoint | Remote branches removed |
| --- | --- | --- |
| CrispCloud | `436c7926` | 11 |
| quds_office_suite | `b0335829` | 0 |
| legacy-doc-parser | `544a50e7` | 6 |
| crisperbooks | `505d3d7b` | 1 |
| CrispSorter | `9566ba0c` | 125 |
| Catfish | `f3181089` | 1 |

The first cleanup left only the default main branches, except CrispCloud’s recently edited `integration/storage-ntfs-20261114`. Its head was already an ancestor of main and was retained under the one-hour rule. No tags were removed. The later continuation below records newly published branches.

The ready ext/NTFS implementations and standalone CAF crate are integrated. CrispSorter also gained the missing runner-aware check-wait branch, with eight regressions preventing false-green reports for queued workflows, old retries and same-named jobs/workflows. Superseded OCR/model, provider, release-replay and sandbox prototypes were reviewed against their newer main implementations before retirement.

The legacy floating-table checkpoint was superseded by canonical commit `0c3e5968`: its original table-origin test and table/style integration remain in main, with later row-padding and border handling. All 25 focused origin/position tests pass.

CrispCloud PR #102 is merged. The stacked #103 is closed; its NTFS head is integrated through merge `3a3d100d`. No additional pull requests were created. Existing v1.3.1 release workflows were not cancelled or restarted.

Detailed deleted-head inventories are saved in each repository’s Git metadata under `integration-audit/20261114/remote-branch-audit.json`. The [storage validation record](storage-integration-20261114.md) records the local test and platform boundaries.

## Evening continuation

Refetched all six repositories and reviewed both remote and local branch heads.
New work was published on CrispCloud's `integration/storage-binary-20261114`
(`542c1c8b`) and the coordinated `codex/office-recovery-20261114` branches
(CrispCloud `9c1eae58`, Quds `67139a78`). All three checkpoints are incorporated
in the new integration; Quds main is now `7d5f8da` and the host's exact-source
manifest pins that commit.

The parser (`544a50e7`), ebooks (`505d3d7b`), CrispSorter (`9566ba0c`) and
Catfish (`f3181089`) have no new remote work at this check. CrispCloud's old
local `local/macos-build` has only two additional merge commits, no additional
ordinary commits; its SMB workflow/document conflict choices are superseded by
main. The previously reviewed local CrispSorter OCR/TestFlight prototypes remain
superseded by current main. Those historical local branches were preserved.

The comparison integration captures and verifies both inputs, keeps account
scope, bounds navigation and releases private copies on cancellation/disposal.
Integration testing caught and repaired a borrowed-provider-buffer corruption
bug and incoming test compilation/animation issues. The combined native
comparison/Office lifecycle cohort passes **198 tests**; see the
[Office recovery record](office-recovery-20261114.md) for canonical suite results
and the remaining pre-existing macOS golden failures.

The final captured-comparison/browser cohort passes **27 tests in Chrome**.
The source-synchronization guard has **eight passing Python tests**, exact
source verification passes, and changed host/library analyzers are clean.
Open PR review found only CrispCloud #104, whose `542c1c8b` head is included.

No additional PRs or release tags were created. Recent topic branches were not
deleted, and existing queued release builds were not cancelled or restarted.

Subsequent arrivals were integrated too: binary comparison `e52ea1f9`, host
Office `d6013345`, and canonical Office evidence `ac4889d`. Quds main is now
`f9512763`. The final arrival-specific native cohort passes 173 tests, including
reusable-buffer scans, protected imports, ribbon state and queued file
operations. The expanded Office record retains independent LibreOffice and
actual browser-download acceptance. GitHub marked PR #104 merged when its head
became an ancestor of main; its branch was retained.
