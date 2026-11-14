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

All repositories now have only their default main branch, except CrispCloud’s recently edited `integration/storage-ntfs-20261114`. Its head is already an ancestor of main; it is retained under the one-hour rule. No tags were removed.

The ready ext/NTFS implementations and standalone CAF crate are integrated. CrispSorter also gained the missing runner-aware check-wait branch, with eight regressions preventing false-green reports for queued workflows, old retries and same-named jobs/workflows. Superseded OCR/model, provider, release-replay and sandbox prototypes were reviewed against their newer main implementations before retirement.

The legacy floating-table checkpoint was superseded by canonical commit `0c3e5968`: its original table-origin test and table/style integration remain in main, with later row-padding and border handling. All 25 focused origin/position tests pass.

CrispCloud PR #102 is merged. The stacked #103 is closed; its NTFS head is integrated through merge `3a3d100d`. No additional pull requests were created. Existing v1.3.1 release workflows were not cancelled or restarted.

Detailed deleted-head inventories are saved in each repository’s Git metadata under `integration-audit/20261114/remote-branch-audit.json`. The [storage validation record](storage-integration-20261114.md) records the local test and platform boundaries.
