# Worksheet navigation and rename continuation — 14 November 2026

Branch: `codex/office-recovery-20261114` in CrispCloud and Quds.
Starting app checkpoint: `f974b9911b1547c806279279a87f2b21a1ac4357`.
Starting suite checkpoint: `a85a977a8ab95bcf42214eb6dd05c73e2fcb5243`.

## Scope

The app can open multi-worksheet workbooks but currently exposes no worksheet
selector or rename control. This increment adds a persistent worksheet bar with
a keyboard-accessible selector and a rename dialog, using the canonical editor
APIs and a repaired `navigationBuilder` hook.

| Task | Acceptance | Status |
| --- | --- | --- |
| NAV-01 | Canonical switching retains rejected cell drafts and commits valid drafts to their original worksheet. Effective same-sheet navigation is a no-op. | In progress in Quds |
| NAV-02 | The sheet navigation hook renders and follows controller changes. | In progress in Quds |
| NAV-03 | Actual selector and rename actions work with host saves, localized errors, undo/redo, narrow layouts and read-only navigation. Invalid or cancelled rename leaves data unchanged. | In progress |
| NAV-04 | New exact workbook captures have explicit schema scope in the CI inventory, retain source-bound execution receipts and pass independent OpenXML validation. | Planned |

The rename dialog keeps invalid input available for correction and remains
bound to its original worksheet. The bar uses the application locale direction
and existing grid focus owner. Existing native rename guards remain in force.
Add/delete/reorder/hide controls and persistent active-tab state are outside
this increment.

All existing 149 rendered and 27 schema-scoped artifact requirements remain
intact. Earlier evidence is retained at its original source; new cases and
captures receive their own acceptance record. Implementation and evidence are
saved incrementally to the remote branch. Hosted CI was queued at the initial
read and is not treated as a passing result.
