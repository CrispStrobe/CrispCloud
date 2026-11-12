# Office integration follow-up — 12 November 2026

The continuation is saved on feature/office-fidelity-followup-20261112 in both
repositories. This host branch starts from the recovered
9cd18e7c704937897d037b1051d38341d4928bf5 checkpoint in
[PR 68](https://github.com/CrispStrobe/CrispCloud/pull/68).
[PR 79](https://github.com/CrispStrobe/CrispCloud/pull/79) is stacked on that
consolidation; [Quds PR 2](https://github.com/CrispStrobe/quds_office_suite/pull/2)
contains the reusable implementation.

## Shared source and host behavior

Host implementation b7edb919def85ef78d6d34ba6eb7c74d61e0bd4d pins **366 managed
files** to Quds 7641d9cfa167987216134ebfc4772918cc945d97. The guarded sync and
per-file hashes passed before and after acceptance. Quds owns native Normal-font
resolution, loaded-font measurement, column provenance and resize history,
explicit native style-zero preservation, logical-grid Word table addressing and
the reusable custom tab-stop control. CrispCloud owns localization, dialogs,
cloud I/O and save coordination.

The paragraph dialog and ribbon use the shared tab control for custom positions,
four alignments and four modeled leaders. Invalid drafts cannot apply; no-op
changes preserve clean history. Real upload tests choose center/dot and
decimal/underscore through those controls and inspect the native values after
three saves. The CI artifact declaration and strict host inventory now require
the three new dialog exports, bringing the host inventory to **62 files**.

The [source report](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-followup-20261112/docs/office-fidelity-followup-20261112.md)
documents the independent regression findings: explicit pixel widths could
regain stale native provenance after font changes, and dropping an explicit
style-zero attribute changed a native spreadsheet's font and pagination.
Both are fixed upstream. Word table evidence separates unchanged native rows
from deliberately edited rows with independently authored expected XML.

## Final acceptance

The existing host gate ran once at the clean implementation commit and passed.

| Check | Result |
| --- | --- |
| Vendored engine cases | 921 passed, no skips |
| Host Flutter cases across the 26-file gate | 143 passed, no skips |
| Python controls | 7 sync, 344 engine fidelity, 10 host inventory, 9 coverage; all passed |
| Exact output inventories | 296 engine + 62 actual host files |
| Open XML SDK | All 358 files valid; every receipt matches the captured bytes |
| Native upload probe | Eleven actual XLSX/PPTX/DOCM/DOTX/DOTM uploads, 23 pages, no failures |
| Custom-tab native checks | Three dialog exports and three captured ribbon uploads; both three-save groups passed exact text, page and decoded RGB comparisons |
| Host line coverage | 2,216/3,549 instrumented lines (62.4%); all ten scoped integration files instrumented |
| Restoration | All 4,732 tracked files unchanged; all 366 managed files identical; pubspec and lock files restored |

The [complete summary](evidence/office-fidelity-followup-20261112/final-host/summary.json),
[gate receipt](evidence/office-fidelity-followup-20261112/final-host/host-acceptance.json),
[SDK/native receipt](evidence/office-fidelity-followup-20261112/final-host/external-acceptance.json)
and [custom-tab native receipt](evidence/office-fidelity-followup-20261112/final-host/tabs-native-summary.json)
retain commands, source fingerprints, exact input hashes and limits.
Raw gate/probe logs and LCOV are preserved in the evidence archive. The identical
before/after tracked snapshots are stored once as a compressed JSON file.

The source's separate full acceptance passed 1,384 engine and 478 editor tests
with one existing conditional skip in each, plus all mandatory oracles. Its
321-package SDK capture and 314-file/614-page native render passed, retaining
seven pre-existing schema/native-XML-only comment-control fixtures. Those
source figures overlap the host's vendored engine scope and are not additional
host cases.

## Boundaries and remote status

FID-057 is closed within its supported logical-grid contract, with unsafe and
omitted-row mutations guarded. FID-029 remains partial for unresolved/unknown
fonts and implicit 64-pixel defaults. FID-068 remains partial for character and
custom style editing, table-style selection and unmodeled native tab variants.
The selected seventeen host native files do not establish complete native
equivalence for every host capture or Microsoft Office.

The earlier [Office integration run](https://github.com/CrispStrobe/CrispCloud/actions/runs/43209357326)
was already successful at recovery. The new PR workflows were queued at the
[implementation audit](evidence/office-fidelity-followup-20261112/final-host/remote-implementation-audit.json);
the receipts above establish local acceptance. Broader historic CLI,
source-review, formatting and moving-SDK migration issues remain separate.
No diagnostic suppression, golden regeneration or new renderer exemption was
used for this continuation.

The concurrent [resumption checkpoint](https://github.com/CrispStrobe/CrispCloud/commit/a62e396ce2e3966555f224a0cc234061fe8e72ce)
is preserved. Its earlier runner and status remain historical; the full passing
runner is archived separately as
[run_host_acceptance_verified.py](evidence/office-fidelity-followup-20261112/runtime/run_host_acceptance_verified.py).
The final evidence commit follows that checkpoint without overwriting it.
