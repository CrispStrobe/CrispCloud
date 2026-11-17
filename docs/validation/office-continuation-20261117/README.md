# Office continuation — 17 November 2026

## Current result

The continuation reconciles recent canonical Office/proofing work and repairs
ODF annotation previews. The host pins canonical **`7f116669d2512cf660c86d3c83feb64ab6b707fb`** and manages
**2,586 files: 729 canonical files and the unchanged 1,857-file standalone
parser**. Source and tests are saved incrementally on
`codex/office-continuation-20261117`.

**Runtime qualification is pending.** Local execution fails before a command
starts. No Dart/Flutter tests, analyzer, formatter or executable vendor guard
ran in this turn. Git-object comparisons, byte/hash checks and independent source
review have completed. Historical test evidence retains its original source.

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

The [bounded arrival refresh](arrival-observation.json) found no additional host
source, and both main refs remained unchanged. Three canonical branches moved
during this turn. Their exact tips and preserved variants are recorded in the
[canonical continuation](https://github.com/CrispStrobe/quds_office_suite/tree/7f116669d2512cf660c86d3c83feb64ab6b707fb/docs/validation/office-continuation-20261117).
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
- [Final vendor plan](vendor-sync-final.json) records the final eight source
  writes, source pin and hashes.
- [Final source verification](final-source-verification.json) binds the remote
  tree, every managed file and the unchanged parser/customizations to their
  observed blobs and modes.
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
control or newly accepted runtime result is claimed. The final workspace probe
still failed before process creation with an unavailable exec-server.

Run [the retained local qualification](PENDING_VALIDATION.md) on this host
snapshot and its exact canonical pin before promoting the draft. Full
application/export-dialog and live Zotero/Word/LibreOffice acceptance remain
separate scopes.

Checkpoint messages use `[skip ci]`, updates are non-force with expected heads,
and remote refs were read back. No GitHub Actions, workflow-run, check-run or
CI-status endpoint was queried or awaited.
