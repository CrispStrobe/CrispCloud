# Archive continuation and complete branch reconciliation

Baseline: `223fb771d2f8980f7425e7e2ecbe5d7953670592` on 13 November 2026.
Initial combined implementation: `5d0814fdf8dfa2257e3000d1d3e3792864a4901e`.
Later concurrent-main input: `e13fb727e4cfe785219c1ef31206d2fbefa8d6c9`.
Final qualified runtime: `a065ee6e7c2aa18574a72ac6232d4d01845bdee9`.
Remote continuation: `integration/archive-containers-20261113`,
[CrispCloud PR #100](https://github.com/CrispStrobe/CrispCloud/pull/100).

## What was integrated

All **12 original live branch heads** and **89 original PR heads** are ancestors
of the combined implementation. At the baseline, 85 of those PR heads were
already ancestors of main; the remaining heads were #14, #84, #95 and #97.
PR #86, referenced in the original continuation handoff, was already merged.

| Branch family | Resolution |
| --- | --- |
| Commander archive workflows, PR #97 | True merge of `cfae329b`, preserving the canonical Operations queue, batch creation/testing/extraction, checked installed packers, SFX reading and numbered 7z sets. |
| Document fonts and previews, PR #95 | True merge of `02160e56`, preserving shared fonts, installed preview, selected engine runtimes and attributed notices. |
| Office oracle/gaps and related checkpoints | Preserve branch ancestry and independent evidence. First reconcile the competing parser pins at canonical `840f8af1`, then retain concurrent main's newer exact parser `0f9f085f` and Quds `05a581de` snapshots. Earlier qualification remains attributed to its tested source. |
| Ebook canary/native-input and PR #84 | Preserve branch ancestry after carrying missing bounded-selection and fixed-layout semantics into canonical Crisperbooks. Pin all four ebook packages to `a18b93c1`, which reconciles the recovery with concurrent canonical-main documentation. The prior extracted package structure remains the owner. |
| Historical PR #14 | Compare each follow-up with current behavior, fix the remaining pending-source Refresh/new-tab cases, then preserve the old PR head as a merge parent. |
| ISO/RAR/DMG, operation queue, app-layout checkpoint | Already included by baseline main. Their original commits and receipts remain reachable. |

The two historical ebook/Commander merges intentionally keep the current tree
after semantic reconciliation. They do not reintroduce obsolete bundled package
directories or replace later pane/source code with historical versions. The
[semantic mapping](legacy-branch-semantics-20261113.md) describes each recovery.
Canonical ebook changes are saved in
[Crisperbooks PR #1](https://github.com/CrispStrobe/crisperbooks/pull/1).
Its final reconciliation has genuine parents `ac9925c4` and canonical main
`c4f64e11`. Only two documentation files differ from `ac9925c4`; runtime,
test, build and license bytes are unchanged. It preserves the separately
recorded Mac Chrome acceptance with its original revision attribution. That
acceptance predates the final disposal cleanup and was not rerun here.

Concurrent app main subsequently incorporated the earlier `5d0814fd` archive
checkpoint and advanced to `e13fb727`. Its shared F3/F4 syntax theme, image-mode
availability, empty-directory parent navigation, newer canonical Office sources
and independent acceptance records are retained by a genuine merge. The final
ebook pin remains `a18b93c1`, which already includes main's `3796381` source and
its later cleanup. The combined technical source inventory retains the union
of both reviewed path sets: **659 files**. Source fingerprints are recalculated
for that merged tree without changing distribution declarations.

The machine-readable [branch ancestry](../evidence/archive-integration-20261113/branch-ancestry.json)
and [PR head cohort](../evidence/archive-integration-20261113/pr-heads.json) retain
exact identities. The PR cohort was reconstructed by a fresh same-session
all-state query, excluding newly created PR #100; it is not presented as a
timestamped API snapshot from the first audit.

## Additional archive capability

- [ADC and XZ/LZMA DMG blocks](../archive-dmg-codecs.md) use bounded positional
  partition reads and feed existing supported HFS+/HFSX/ISO views. Exact decoded
  sizes, malformed input, allocation limits and present integrity checks are
  enforced. New profiles remain read-only.
- [ISO multi-extent regular files](../archive-iso-multiextent.md) appear as one
  logical member and stream sections in directory-record order. Consistency,
  section-count and total-size limits apply. The inspected writer remains on
  its single-extent profile.
- Encrypted numbered 7z members retain their reader after a successful
  password retry. A real F3 regression reproduced cancellation caused by the
  old handle's lifetime guard. The accepted replacement now owns that guard;
  mode/source changes and stale password responses still invalidate reads.

## Source inventories and retained attribution

PR #95 intentionally moved retained notices and regenerated minified runtime
chunks. Its old crypto source inventory still named 113 removed paths. This
integration replaces the old inventory entries for `assets/licenses`,
`assets/runtime` and `notices` with every current tracked file in those three
directories: 3 distributed notices, 43 runtime files and 63 retained notice
sources. The independent runtime manifest and corresponding-source archives
remain guarded. The 23 consolidated license aliases are byte-identical to their
retained originals; authored upstream notes are allowed to describe the new
font/runtime integration.

The full ebook source manifest covers all 283 files at its new immutable pin and
verifies the actual Pub-resolved bytes. Technical inventory, dependency and
source fingerprints are refreshed without changing existing distribution
decisions. Runtime/license mutation tests still reject changed or missing
attribution and source records.

## Verification scope

Historical branch receipts retain their exact source attribution. The combined
candidate has its own gate and receipt under
`docs/evidence/archive-integration-20261113/`; earlier passing totals are not
added together as a synthetic unique count.

The [final merged receipt](../evidence/archive-integration-20261113/README.md)
records **173 passing app tests**, passing source/dependency guards and a
successful original-manifest JavaScript release build at `a065ee6e`. The newer
canonical parser separately passed **1,422 tests**, its Python controls and
actual compiled-JavaScript acceptance. Focused Quds host and engine controls
passed. Expanded app analysis had no errors/warnings and seven documented
inherited style infos; strict canonical analysis was clean.

The initial 165-file combined run retained 3,107 passes, one missed-checkbox-tap
test failure and 13 explicit large-file skips. The interaction was reproduced
and corrected without production recovery changes; it passes in the final
merged gate. Its original failure receipt remains available alongside passing
follow-ups. The final build embeds version `1.2.9+22` and commit `a065ee6e`.

The local profile uses repository-pinned Flutter 3.47.8 / Dart 3.13.7, verified
Clang/SQLite/libsmb2 and real installed packers. It temporarily disables the
unrelated optional native ebook build hook and restores manifests byte-for-byte.
Native ebook rendering and OS device acceptance remain separate. Large physical
archive cases above 2 GiB are explicit opt-in tests; the ISO large-size portable
check exercises a synthetic source and a bounded prefix, not complete physical
extraction. Browser selection assertions remain committed for hosted execution
because this environment prevents Chromium from starting.

All implementation and evidence changes are saved as incremental remote
checkpoints. Every audited original head remains reachable, and this
continuation does not delete source branches.
