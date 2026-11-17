# Office continuation — 17 November 2026

## Current result

The continuation reconciles recent canonical Office/proofing work and repairs
ODF annotation previews. The host pins canonical **`555eb728ce3ea872cb5ceb3e5fd2104b21f932aa`** and manages
**2,587 files: 730 canonical files and the unchanged 1,857-file standalone
parser**. Source and tests are saved incrementally on
`codex/office-continuation-20261117`.

**Runtime qualification is in progress.** The initial command-launch failures
are retained as earlier attempts. The local runtime has recovered; official
Flutter 3.47.8 / Dart 3.13.7 and unchanged locked canonical/host dependency
workspaces are ready. Current source review, remote Git identity checks and the
guarded vendor dry run have completed. Final accepted runtime results will be
recorded separately; historical test evidence keeps its original source.

## Incoming work

[Branch inventory](branches.json), [all PRs](pull-requests.json) and
[reconciliation](reconciliation.json) cover **99 host branches and 212 PRs /
311 refs**. Captured main `fad903782ee45031e26c57cc8a65ccf476b1724d` includes
#221 and #222 after the supplied landing. There were no open host PRs at that
observation.

The accounting is 214 ancestry-covered refs, 94 complete-tree aliases, captured
main, and two branch/PR observations with additive evidence preservation.
The latter case retains every original leaf blob and mode plus 31 TestFlight
evidence files; it is explicitly not classified as whole-tree equality.

The [bounded arrival refresh](arrival-observation.json) initially found no
additional host source, with both main refs unchanged at that observation.
A later [destination-main refresh](section-main-arrival.json) captured Quds #104
and host #223/#224; those exact main commits are retained by this integration. Three canonical branches moved
during this turn. Their exact tips and preserved variants are recorded in the
[canonical continuation](https://github.com/CrispStrobe/quds_office_suite/tree/555eb728ce3ea872cb5ceb3e5fd2104b21f932aa/docs/validation/office-continuation-20261117).
The final source retains all original captured histories and those arrivals.

## What changed

The vendor sync brings in German morphology, updated proofing qualification
material, newer ODT note handling and ODP transition amendments while preserving
the landed Zotero recovery and ODT comment export.

ODF annotations retain their metadata/body in raw XML and models. The host now
excludes them from document body, list, table, note, header/footer and CSV preview
text. Table handling filters both hidden descendant paragraphs and annotation
text nested within an otherwise visible paragraph. Namespace-aware checks retain
foreign lookalikes, CDATA and surrounding text. The canonical extractors and
search fallback carry the same annotation-story boundary.

The section writer now binds first-list and nonparagraph section starts, keeps
continuous sections from forcing a page break, uses valid common style parents,
and retains a default master for an empty document. The independent section
review records explicit limits for synthetic anchors, odd/even page parity and
mid-page geometry/header changes. Twelve new cases cover the section boundaries
and interactions with notes/comments.

The canonical writer also reserves note definitions for visible body references:
references inside comments retain their marks without consuming the definition.
Both footnote/endnote regressions and the independently arriving same-paragraph
case are retained.

German morphology now ships its full Unicode attribution and license through
the app's seventh registered Office notice. The six original notices and the
host package LICENSE remain unchanged. The asset declaration, registry entry and
license regression agree.

## Source and preservation evidence

- [Initial vendor plan and hashes](vendor-sync-initial.json) records the first
  40 source writes and license integration.
- [Second vendor plan](vendor-sync-final.json) records the eight annotation/note
  source writes at canonical 7f116669.
- [Section vendor plan](vendor-sync-sections.json) records five subsequent source
  writes and the final 555eb728 pin; the guarded dry run reports 2,587 files.
- [Pre-section source verification](source-verification-1d1411c5.json) records
  the preceding complete inventory; the final guarded qualification will bind
  this section update to its exact source and host tree.
- [Independent host review](independent-host-review.json) covers the host
  annotation APIs/expectations and the seventh notice.
- [Independent note review](independent-note-review.json) covers the canonical
  comment/note correction, with exact source/test inverse checks.
- [Annotation review](../odf-annotation-visibility-20261117/README.md) contains
  the 11 canonical and eight host authored cases and their read-back identities.

Unchanged SHA-256 values are carried from the prior manifest only where the
immutable source/host blobs are identical. Each changed or added source blob was
freshly checked for Git blob identity, byte size and SHA-256 before upload, and
the upload returned that exact blob ID. The 12 inherited managed executable-mode
differences are preserved; no new managed mode difference is introduced.

Independent preservation review confirms all 50 canonical Zotero paths and the
46 mirrored host paths remain unchanged; four canonical editor-example paths
are intentionally outside the host mirror. All 20 previously audited host
customizations, the original six notice blobs and the standalone parser remain
preserved.

## Validation status and next step

The new regression definitions are **not passed tests**. No executed failing
control or newly accepted runtime result is claimed. Earlier workspace probes failed before process creation; their records are
preserved. The command runner and pinned toolchain subsequently recovered.
Final qualification is running on the immutable source snapshot.

Run [the retained local qualification](PENDING_VALIDATION.md) on this host
snapshot and its exact canonical pin before promoting the draft. Full
application/export-dialog and live Zotero/Word/LibreOffice acceptance remain
separate scopes.

Checkpoint messages use `[skip ci]`, updates are non-force with expected heads,
and remote refs were read back. No GitHub Actions, workflow-run, check-run or
CI-status endpoint was queried or awaited.
