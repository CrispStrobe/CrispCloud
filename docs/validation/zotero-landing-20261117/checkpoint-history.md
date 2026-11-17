# CrispCloud Zotero landing — 17 November 2026

The recovered Zotero implementation and the captured ODF source are saved
remotely with two separate accepted qualification stages.

| Stage | Immutable host source | Canonical source | Accepted results |
| --- | --- | --- | --- |
| Broad host qualification | `96c514eb98f7ba596a385c8f60496bc6c5994307` | `837d06edbde08a2465e99cbbb15927ee4c87d8ac` | 41 host + 39 service + 28 Python tests; two separate writer-to-host probes |
| ODF and covered-cell amendment | `a8cc440260369214fce5cbae8b0230f425a46829` | `f510060e35d580cbc361985a123927705c92ddc4` | 40 service tests; two existing and two new list/Zotero-list probes |

The later stage repeats earlier tests, so the rows are not summed as unique
coverage. All 12 broad gates and all 10 bounded amendment gates passed.
Source, dependency, runtime and harness inputs stayed unchanged, and analyzer
configuration was restored. No unpublished prior-session count is adopted.

The amendment corrects a confirmed preview defect: retained nested covered-cell
text could leak into the visible ODT and ODS previews. The narrow reader change
filters actual ODF covered-cell ancestors, preserving visible nested paragraphs,
foreign-namespace content and the raw source XML. The retained negative control
fails on the old reader; the committed regression passes in the 40-test cohort.

The guarded sync verifies 2,559 managed paths: 702 canonical paths and the
unchanged 1,857-file parser. All 20 host customizations, six original notices
and 12 inherited executable-mode differences are preserved, with no new mode
difference. The complete mode inventory supersedes the earlier incomplete
eight-path inventory without changing any mode to pass the audit.

## Evidence

- [Broad host report](host-full-run.md), [receipt](qualification-receipt.json),
  [supplemental receipt](supplemental-receipt.json),
  [complete broad evidence](host-evidence.tar.xz) and
  [verified archive index](artifact-index.json).
- [ODF amendment report](host-odf-amendment.md),
  [receipt summary](host-odf-receipt-summary.json),
  [complete amendment evidence](host-odf-evidence.tar.xz) and
  [verified archive index](host-odf-index.json). The archive includes raw logs,
  full receipts, exact input maps, probes, negative control, patch and runners.

## Landing status and scope

The original PR #201 was merged at its earlier source checkpoint. Destination
main subsequently added ODP transitions and ODT footnote/endnote export through
`d4524de90dd403c9ce350a1d271ac70ce511256b`. A follow-up integration is in progress
to preserve that work with this verified reader amendment. The companion Quds
note writer is checkpointed at `b2dc226e2ed82cda8f1bada18fb0a1e17347b5fc`.

This is focused local qualification. It does not claim full application builds,
complete viewer or export-dialog acceptance, live Zotero/Word/LibreOffice
interoperability, or native/Wasm Harper acceptance. Incoming release evidence
is retained as authored with its original source attribution.

No GitHub Actions, workflow, check-run or CI-status endpoints were queried or
awaited. The complete source and evidence are checkpointed before landing.
