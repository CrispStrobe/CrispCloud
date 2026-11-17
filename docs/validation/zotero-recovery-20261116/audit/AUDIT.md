# Quds recovery incoming audit

Status: verified against final published implementation **`b87f9d6c3a2532c9695024adf48ca9fbd3c0927a`**, tree `acb1d1060879dc4a8168df8abf3105dc828af360`. This contains the initial rendering merge `c6b9856` and the bounded later main `63194d8`. All 166 frozen incoming refs are accounted for by actual ancestry or the exact dispositions below, with the later main observation recorded separately. Earlier projected receipts remain explicitly historical.

## Frozen scope

GitHub `git/matching-refs` collections were read through **2026-11-16 19:39:07 UTC**. The inventory contains **166 refs** at **113 distinct heads**:

- CrispStrobe fork: 79 branch heads and 79 PR heads.
- Original MohammedAsaadAsaad upstream: four branch heads and four PR heads.
- PR `/merge` refs are excluded. The outgoing recovery branch was created after this inventory and is excluded.

Fork main is `be9eeec9ea3455018de26fff5874c558dbc66798`. Upstream main is `15c5d29b63fb17a93c7fb3426a8fd4d95a32f1ba`. All upstream heads are already ancestors of fork main. The frozen inventory is an explicit cutoff; it does not claim that concurrent branches stopped changing.

The metadata-only ancestry check found **149 ancestor refs and 17 nonancestor refs**; no required Git commit object was missing. No historic raw evidence archives were downloaded for this ancestry check.

## Distinct incoming implementation

The text-rendering branch and PR #72 both point to frozen `6bf486ee0bbcd2025c3a42cae7d7003b8c9324a4`. Four commits beyond the common base remain unmerged into main: two implementation checkpoints and two evidence/tooling checkpoints. They separate PDF CIDs from glyph IDs, preserve shared-glyph Unicode aliases, strengthen TrueType subset structure and retain relevant font metadata.

`git merge-tree --write-tree` of the exact frozen main and rendering head exited **0**, producing tree `754fd323403c79e822f33421d132cdc9c022b0e4`; no conflict was reported. The frozen head is now integrated. Its FontTools MIT notice must be preserved in the guarded CrispCloud inventory and notices. Combined-source local qualification is prepared separately.

Five engine production files change; no Zotero production file or dependency manifest changes. The new notice is `packages/quds_office_engine/third_party/fonttools/LICENSE`; the guarded vendor rules and bundled notices must retain it. Existing direct PDF callers retain the identity encoding API, while Office export uses explicit CID mapping.

The frozen rendering receipt contains **169 passing engine tests**, zero failures/skips, strict analysis and formatting, and unchanged measured source hashes. Independent Poppler raster/text evidence is also present. This is inherited evidence bound to its recorded source, not a fresh combined-source run. The added editor rendering case still needs fresh qualification. The frozen strategy document links a continuation README that was not yet present in that commit; the actual checkpoint and raw receipt paths are available.

Suggested added local coverage is the new font-subset structure, CID and Unicode-alias export tests; existing font/PDF export and ODS writer suites; and `font_subset_render_test.dart` in the editor. The separate recorded 169-test selection lists its exact 17 engine suites.

## Nonancestor alias dispositions

| Incoming head | Integrated counterpart | Finding |
| --- | --- | --- |
| `06828a5` / docs row groups / PR #79 | `be9eeec` | Entire trees identical |
| `1675bbb` / current capabilities / PR #74 | `ba79d47` | Entire trees identical |
| `1deb61c` / ODS filter predicates / PR #76 | `e81650b` | Entire trees identical |
| `2713749` / ODS row groups / PR #78 | `a341752` | Entire trees identical |
| `bb9866d` / filter documentation / PR #77 | `44a56cd` | Entire trees identical |
| `f27e9b0` / ODT registry documentation / PR #75 | `ff873a4` | Entire trees identical |
| `817982d` / corrected vendor filter predicates | `e81650b` | Changed production/test blobs and modes identical |
| `891ccc2` / vendor row groups | `a341752` | Changed production/test blobs and modes identical |
| `928f854` / older vendor filter predicates | corrected `817982d`, integrated `e81650b` | Same production parent/result blobs; test differs only by removal of one unused local binding |

The last test difference is exactly `final a1 = sheet.cellA1('A1')` becoming `sheet.cellA1('A1')`. The full 221-line test otherwise matches byte-for-byte. No assertions, test data or production behavior are missing from the corrected integrated version. Whole-branch tree equivalence is not claimed for the three vendor branches.

The actual final accounting at `b87f9d6` is **151 ancestor refs, 12 exact whole-tree squash aliases, two source/test-equivalent vendor aliases, and one superseded vendor head**. These categories sum to 166. `final-ancestry.json` records the actual result and `final-dispositions.json` binds the remaining aliases to their comparisons. The initial `c6b9856` integration differed from its projected tree only by recovery documentation; the final `b87f9d6` implementation additionally contains the separately recorded late-main changes.

## Bounded later main observation

Creating the recovery PR exposed later main `63194d8e482892f284eaccb95ce48a8a8132376d` before qualification began. Its five commits through PR #84 add modeled worksheet page setup and ODS header/footer round-trips, changing four sheet implementation files, two tests and two documentation files. The parent approved one bounded integration; no additional moving branch/PR inventory was queried.

The exact late main merged cleanly with initial `c6b9856`, producing the final published tree above. It changes no Zotero/font/PDF implementation or dependency manifest. The original 166-ref cutoff remains unchanged; this later main is an additional observation, not a claim that all later branch heads were inventoried. Qualification adds `sheet_save_cache_and_freeze_test.dart` and the six changed Dart analysis/format targets; the ODS reader/writer suites were already selected. See `late-main-review.json`.

## Preserved Zotero work and historical evidence gap

Quds PR #63 is already merged, as is companion CrispCloud PR #176. The old Quds branch remains at `2480f0988167068d9aeddf6573b9c2c6871a8481`. The original final qualified production source was `9de43669088c3719d541c9fe1c7dcb3ffbf86df3`.

The four optimized Zotero production files are identical across the historical qualified source, frozen current main and projected integration tree. Read-only review found no concrete regression in the alias DSU, first-snapshot ordering, one-scan document tab or shared maximum backoff deadline. Existing focused regression tests cover transitive aliases without CSL snapshots, unrelated library/profile identities, DOCX metadata persistence, reconnect/reopen behavior and independent local clients.

The historical `post-pr-canonical/` and `post-pr-host/` final raw archives were not published at the old checkpoint. The published 923-test summary records that interruption explicitly. The existing `final-canonical/` archive belongs to the earlier 825-case canonical source `8e017e8c`; it must retain that attribution. A new source-bound qualification can close the evidence gap with fresh logs, but cannot be represented as recovery of the missing old raw logs.

## Compact artifacts and reproduction

- `incoming-refs.json`: exact frozen refs and SHAs.
- `main-ancestry.json`: every grouped head checked against frozen main.
- `squash-comparison.json`: exact whole-tree and changed-file blob/mode comparisons.
- `main-dispositions.json`: machine-readable findings and projected counts.
- `projected-ancestry.json`: historical union of ancestry under the two proposed merge parents, explicitly projected.
- `integrated-ancestry.json` and `integrated-dispositions.json`: verified initial integration at c6b9856.
- `final-ancestry.json`, `final-dispositions.json` and `late-main-review.json`: final b87f9d6 accounting and bounded later main.
- `canonical-invocation.json`: prepared source-pinned local qualification command; not a passing result.
- `zotero-preservation.json`: four original/main/projected production blob identities.
- `audit_incoming.py`: read-only ancestry runner. The optional patch-equivalence mode is not needed for these exact-tree/blob proofs and may cause promisor blob downloads.

Run the ancestry runner with `--repo`, `--inventory`, `--head` set to the actual final commit and `--output` set to a new receipt path. No GitHub Actions, workflow jobs, CI statuses, logs or artifacts were queried, awaited or rerun.
