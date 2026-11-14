# Storage capability expansion: archive, container and filesystem workbench

Status: library and architecture evaluation in progress. This checkpoint changes
documentation only; it does not claim new runtime support.

## Reconciled baseline

On 2026-11-14 all remote branch heads, tags and `refs/pull/*/head` were fetched.
All **10 existing branch heads** and **90 historical pull-request heads** are
ancestors of `4d65b86dab36ca8f5dcd192c776de369aa5a4932`. There were no open PRs.
No additional merge or recovery of divergent content was necessary.

The previous handoff's merge, `81639c44da5c9c905e5bcbe8d04308fce7bda17a`, is
seven commits behind this baseline. Those commits include viewer long-line
handling, newer canonical Office sources, reader cleanup and release evidence.
They are retained intact.

The working branch is
[`integration/storage-capabilities-20261114`](https://github.com/CrispStrobe/CrispCloud/tree/integration/storage-capabilities-20261114).
Checkpoints are pushed as the assessment develops. Existing branches remain.
The complete source refs and ancestry outcomes are in
[`evidence/storage-capabilities-20261114/ancestry.json`](evidence/storage-capabilities-20261114/ancestry.json).

## Scope and license filter

Evaluate additions for archive inspection/recovery, filesystem and partition
browsing, disk/container formats, structured hex tools and robust copying.
The requested filter accepts MIT, Apache-2.0, BSD, MPL and comparable terms;
excludes GPL and noncommercial restrictions. This assessment also excludes
LGPL-backed additions unless the user changes that constraint explicitly.
Licenses apply to the selected implementation and its runtime dependencies,
not merely its wrapper. A permissive wrapper around a GPL/LGPL engine is not
an accepted implementation.

This is an addition policy, not a relicensing of CrispCloud. The repository's
existing `LICENSE.txt` is GNU AGPL v3; individual existing packages have their
own license and attribution records.

## Assessment checkpoints

1. Preserve the complete current branch/PR baseline and record ancestry.
2. Inspect current archive, binary and transfer services to avoid duplicating
   shipped behavior.
3. Verify primary-source licenses, capabilities and material limitations.
4. Publish a prioritized architecture and acceptance plan on this branch.

Runtime qualification, exact dependency pins and per-platform tests are required
before any recommended library is shipped. Existing verification receipts keep
their original source attribution and are not new results for this assessment.
