# Remote refresh and local qualification — 15 November 2026

## Saved reconciliation

The incoming audit covers every observed branch in CrispCloud (17), Quds (13)
and the legacy parser (8), plus current PR heads. Main was fetched before work.
Historical supersession proofs are retained for branches whose changes were
previously integrated under different commits; obsolete versions are not reapplied.

CrispCloud preserves its latest passing receipts and current main 68631862.
Canonical Quds 6e4c3b16 joins main 6d7c696e with comment author indexing and
constant-default cleanup from c17098d6. New incoming behavior includes the
10,000-comment admission bound and strict covered-cell tokens, plus reviewed
Linux Word golden references. Canonical parser 08296edb joins main ea82b13d
with continuation 57442c79. Its production bytes are unchanged; one regression
case from main is retained. Both source mirrors and their exact pins are synced.

## Local acceptance plan

Fresh app and engine cohorts validate the ODS admission changes in the host.
The editor cohort expands from 9 to 11 suites to include the incoming Word
page goldens. Strict analysis includes those two new test sources. The parser
full 144-suite inventory is qualified separately on its saved merge. Existing
raw receipts and visual navigation review remain attributed to their original
source; no old test count becomes a fresh result.

Each gate runs on a saved commit with stable before/after source, resolution
and tool hashes. Preserve failures and completed receipts remotely before
continuing. Do not await, poll or restart GitHub Actions. New commits use
[skip ci]. Final status will be populated from actual completed raw results.
