# Incoming branch and canonical reconciliation audit

Initial integration head: `59466d8b48f329362ab88e9da5e195c849557069`.
The machine-readable `branches.json` and `canonical-branches.json` record the
observed immutable heads, ancestry, merge bases and changed paths. PR state is
from the authenticated GitHub REST collections, not cached PR base fields.
No GitHub Actions run was awaited, restarted or used as a gate.

## Application branches

| Branch | Observed head | Disposition |
| --- | --- | --- |
| integration/storage-carving-20261115 | 59466d8b | Initial saved source and receipts. |
| continuation/storage-qualification-20261115T1000 | 0c574677 | Direct descendant of initial integration; five evidence-only commits and eight changed evidence files. Incorporate by fast-forward before source work. |
| main | 4933ffc2 | Merge current main, including merged PRs 118/119 and legal-notice assets, runtime registration and guard checks. Root refreshed main separately; this table retains the original observation. |
| fix/odf-final | 7dec00fb | Preserve ODS grid/fallback and documentation changes plus latest canonical ODS geometry, currency and whitespace changes. PR116 is closed unmerged, so branch contents still require review. |
| integration/storage-carving-local-qualification-20261115 | dacd3e58 | Preserve all independent receipts and parent ancestry. Its ODS parser/time formatting are predecessor implementations, superseded by the reconciled canonical source. Preserve the two app test lint corrections. See detailed patch and policy below. |
| codex/office-recovery-20261115 | d97705da | Already an ancestor of initial integration. |
| feature/new-documents-history-20261115 | ab94bedb | Already an ancestor of initial integration. |
| integrate/legacy-xls-preview-20261115 | eba6c9dc | Already an ancestor of initial integration. |
| integrate/odf-integration-20261115 | a8e350d9 | Already an ancestor of initial integration. |
| integrate/office-goldens-20261115 | 74f97cba | Already an ancestor of initial integration. |
| integrate/word-inline-pictures-20261115 | bb981ec3 | Already an ancestor of initial integration. |
| integration/office-reconcile-storage-20261115 | 59b6a509 | Already an ancestor of initial integration, with zero unique commits. |
| integrate/ods-fixes-20261115 | 5530aff5 | Ancestor of observed current main, incorporated through main. |
| integrate/ods-style-20261115 | f74f1fce | Ancestor of observed current main, incorporated through main. |
| integrate/consistency-20261115 | eab538e7 | Superseded: 20 of 21 changed file blobs appear verbatim in initial integration history. Remaining QUDS_FORKS documentation refers to an older pin. PR113 is closed unmerged. |
| fix/excel-legacy-xls | 7bfe1ed6 | Superseded: 52 of 59 changed file blobs appear verbatim in initial integration history. Remaining application files combine the imported ODS edit/copy-save and legacy grid features with later changes; remaining manifest/fork documentation use newer canonical pins. Review patch retained separately. |

`superseded-path-lineage.json` gives exact matching historical revisions for
the 72 matching file blobs. Seven remaining legacy branch paths are the four
shared application files (`file_editor_dialog`, `office_editor_dialog`,
`internal_viewer_dialog`, `office_document_service`), its service test, and the
source pin/fork documentation. Their feature deltas cover ODS-to-XLSX editing,
typed XLS grid/fallback preview, typed/repeated ODS extraction and richer ODT/ODP
extraction; these are present in the newer integrated implementations.

## Independent qualification branch policy

`local-qualification-source-diff.patch` records the exact noncanonical application
and documentation differences against initial integration. Two useful test-only
fixes remain: use a const string in `document_conversion_test.dart`, and brace
the conditional break in `document_conversion_dialog_test.dart`.

The independent branch requires horizontal covered-cell tokens, whereas the
current integration explicitly accepts producers that omit horizontal covered
placeholders. Retain the current compatibility extension and its regression.
Retain the independent vertical merge collision guard: an ordinary stored cell
inside an earlier vertical merge is ambiguous and must decline. Canonical merge
coverage work remains bounded. Neither strategy should silently truncate rows
or lose stored cell data. Do not replace current formatter/ODS tests with the
older branch copies.

## Canonical Office and parser

The canonical merge starts at Quds `3479cd809ca0e92ef165e8faaf48780720b8f17f`
and preserves these incoming remote parents:

- Main `f90bc0e20e3fa8e4af72a06e8d941faa3677db6d`: ODS sparse padding,
  currency symbols, repeated spaces/line breaks, and corpus test hooks.
- ODS PR24 `e033226bd2d53d1a818c6771ce347c23e6056857`: native default and
  explicit column geometry.
- Word PR25 `b6d27c84a72d622f670a7e646e36ba4bd920cfc8`: all underline enum
  values, OOXML step vocabulary and split-paragraph formatting continuation.
- Independent qualification `cb9f7a5793c9a4e7415cd9e52c91509ea3304252`:
  original receipts, custom identifier boundary regression, vertical merge
  coverage guard, and PDF const lint corrections.

The canonical merge retains existing namespace checks, grid/expansion/work
bounds, style inheritance, per-column defaults, quoted strings/references and
clock/elapsed-time format regressions. Currency symbol extraction now uses the
number namespace and raw symbol text; the cell paragraph walker would otherwise
discard a directly encoded currency symbol. Sparse inherited styles and explicit
formatted blank cells are distinguished.

`canonical-reconciliation.json` records the local resolution commits, final
initial tree and changed source paths. These local commits can be consolidated
as one remote merge retaining all remote parents. The canonical default geometry
copy-save regression is deliberately included before running qualification;
static review found that defaultColWidth was never written for newly constructed
OOXML workbooks. A passing old receipt must not substitute for this new check.

Canonical selection/navigation, inline-picture, heading and shape branches are
already ancestors of the original pin. The old Office-storage reconciliation
branch contributes only a merge commit with no non-merge unique work. The old
Excel import branch has two ODS introduction/format commits superseded by merged
ODF PR23 and the bounded importer.

Standalone parser main remains `d422fa99a3a84830794f0e2dc332d59f923779f7`,
identical to the initial pin, but explicit branch comparisons found additional
unique work. `parser-prs.json`, `parser-incoming.json` and
`parser-branch-comparisons.json` record open PRs14-18: real-format detection
(`9f61e030`), damaged compound text recovery (`a82595a8`), Word98 nFib acceptance
(`3dc1a857`), recoverable comment/bookmark omissions (`89555522`), and stacked
Word6/95 text import (`120a3cc9`). These require canonical integration and
focused qualification before a final source freeze. The earlier inference
from unchanged main alone was withdrawn before qualification started.

## Qualification boundaries

New optional local corpus tests enumerate Downloads/Documents and can pass when
those directories contain no files. Such a pass does not establish corpus
coverage. Use explicit known fixtures or keep that scope separate from mandatory
regressions. Tests for the merged source must use the resolved host graph and
byte-matched canonical sources, with the saved source identity bound to receipts.
