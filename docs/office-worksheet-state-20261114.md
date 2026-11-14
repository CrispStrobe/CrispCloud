# Worksheet state integration — 14 November 2026

Starting app source: `a3897dfbe2d3721e0ec0756a1872132daf9f6b90`.
Canonical starting source: `2d2a7be43e19b478c532025fe1f275ed7b00ef75`.
Checkpoint branch: `codex/office-recovery-20261114` in both repositories.

This increment makes persisted worksheet RTL/frozen-pane settings participate
in history, dirty state and save revisions. It also addresses grid history that
can target the wrong sheet after navigation. Quds owns these controller fixes.
The app now pins canonical implementation `0f935a6f24ae11aa9851a5cc3498808554194446`
through the guarded sync. All 2,177 managed files match their declared hashes
and staged Git bytes. The final canonical eight-file regression group passes all
100 tests, with zero issues in the scoped analysis.

Actual host acceptance will cover the ribbon/close path, a view change during
an upload, and saved workbook contents after history across worksheet tabs.
The existing native-fill capture directory was absent from the CI upload and
inventory routes. The new routing declares 21 exact schema artifacts: two
authored inputs and 19 actual host outputs across the native-fill and
worksheet-state directories. The existing 146 rendered outputs and three pinned
references remain unchanged. All 23 focused inventory controls pass at
`4518e771`. The actual inventory CLI also verifies a complete 170-file control
tree; the workflow's staging code copies exactly the original 149 rendered files.
Removing either new acceptance directory fails the check. The
[CI integration receipt](evidence/office-worksheet-state-20261114/ci-integration/README.md)
keeps the synthetic integrity controls separate from actual host/schema evidence.
The style-history extension adds six exact files in a third explicit acceptance
root, bringing the current contract to 176 files: the unchanged 149 rendered
artifacts plus 27 schema artifacts (three inputs and 24 uploads). Final controls
for this extension are pending; the original 170-file evidence stays intact.

Five new host cases reproduce missing close prompts for RTL/freeze changes,
missing revision tracking during delayed uploads, and wrong-sheet grid history
in actual saved XLSX bytes. The delayed-upload baseline establishes an unchanged
revision after a confirmed view mutation; its immediate editor-presence assertion
did not fail. Positive host validation is pending against the synced source.

The [retained host baseline](evidence/office-worksheet-state-20261114/host-baseline/README.md)
records the final five behavioral failures, all earlier test-harness attempts,
4,740 stable execution inputs, exact workbook bytes and independent validation
of the authored input. Its final test source is committed at `4518e771`.

The [integration receipt](evidence/office-worksheet-state-20261114/integration/receipt.json)
retains the guarded plan, applied result and full source/index verification.
That initial sync is followed by the
[ribbon integration receipt](evidence/office-worksheet-state-20261114/integration-style/receipt.json),
which records the final typed formatting APIs, third regression file and source
pin. The app routes bold, font size, alignment, fill, font color and its existing
six-field Clear formatting action through canonical Quds commands. The duplicate
app `_CellStyleCommand` and its separate snapshot implementation are removed.

The [style-history baseline](evidence/office-worksheet-state-20261114/host-style-baseline/README.md)
retains two more actual host failures from the old ribbon command: wrong-sheet
Bold undo and loss of an authored gradient after same-sheet Bold undo. It also
keeps direct inspection of the saved native pattern, theme/tint and style-index
changes separate from assertions that were reached. The exact authored source
passed independent SDK validation. Positive acceptance will complete all eight
selected host cases (five worksheet, two style and one native-fill overlap) and
emit all 27 files against the final synced source.

The previous 52-test host cohort, corrected fill rerun and independent four-file
schema acceptance remain unchanged. New negative controls, implementation and
execution results are recorded separately. Hosted CI acceptance will be recorded
at completion; earlier queue observations retain their original source/time.
