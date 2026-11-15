# Final observed ODS source reconciliation: ddaca stage

The canonical merge reconciles saved integration head
`0ca0d31bd757da4db6b6ef45764ff9de33990a2f` with final observed production
commit `ddaca09c88895c56480dae5b506dc4f0b4cf120f` (09:37:28 UTC).
The robust 0ca reader remains the foundation. The incoming reader was not
accepted wholesale because it would remove namespace checks, expansion budgets,
style inheritance, sparse row handling and existing coordinate corrections.
The incoming edge fixture is byte-identical to its ddaca Git blob.

## Reconciled behavior

- Effective cell styles follow explicit cell, row default, then column default
  precedence. A repeated cell is split into adjacent runs of equal effective
  style so differing column defaults survive at each coordinate. Values and
  formulas are parsed once per XML element. Column default bookkeeping uses the
  existing workbook dimension budget, and bounded style-run scans use the
  existing style-work budget. Huge empty `Default` runs remain sparse.
- Absolute sheet markers are removed only from the sheet component. Absolute
  cell coordinates and quoted sheet identifiers remain intact.
- Namespace-aware time components map hour/minute, minute/second, full clock
  and elapsed hour/minute/second styles to the shared formatter. The separately
  reviewed formatter correction preserves uppercase dates and resolves minute
  context without treating `mm:ss` as a month. Elapsed formats retain totals.
- All 35 previous ODS cases remain. The two incoming edge cases and 12 focused
  default-style, formula and time cases bring the ODS suite to 49. Standard
  explicit/repeated covered-cell behavior, merge overlap refusal, omitted-cell
  compatibility, deferred trailing heights, quoted formula text, namespace and
  workbook-limit controls are retained.

The CHANGELOG distinguishes omitted horizontal covered placeholders as an
existing compatibility extension: ODF 1.3 Part 3 sections 9.1.5 and 19.680
require covered elements for spanned physical positions. This extension does
not permit overlapping merges. This remains a bounded import profile, not
arbitrary ODF feature or formatting preservation.

## Raw development verification

| Run | Result |
| --- | --- |
| Saved 0ca reader + union regressions + corrected shared formatter | 37 passed, 12 failed, zero errors/skips |
| Reconciled ODS + formatter + formula + authored-format suites | 85 passed, zero failures/errors/skips |
| Strict analysis of both production files and both affected test files | Exit 0, no issues |
| Patch whitespace check | Exit 0 |

The 85 passing cases comprise 49 ODS, 8 time-format, 26 formula and 2 authored
number-format cases. `coverage-and-source-review.json` records exact names and
confirms that every previous ODS case is retained. No failed run was overwritten.

Each run records its exact command, HEAD, MERGE_HEAD, UTC time, exit status and
SHA256 identities of source, fixture, lockfile, package configuration and graph
before/after. Those identities did not change during any run. Baseline and final
source/resolution snapshots are retained separately as compressed tar archives.
The runner uses the real pinned Dart toolchain and normal package graph; no
dependency constraint, native hook or production mirror was changed for testing.

These are scoped development receipts for an uncommitted canonical merge. They
do not replace the final clean app source, full managed inventory or runtime
qualification gates. The root agent will publish the canonical merge, perform
the guarded mirror sync, and qualify that saved app revision.

`incoming-reader-baseline-*` and `incoming-reader-baseline.*` are immutable once
handed off. The passing run uses distinct `reconciled-*` filenames. The parent
directory's earlier 35-pass fbe receipts remain unchanged.
