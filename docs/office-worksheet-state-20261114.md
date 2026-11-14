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

Actual host acceptance covers the ribbon/close path, a view change during
an upload, and saved workbook contents after history across worksheet tabs.
The existing native-fill capture directory was absent from the CI upload and
inventory routes. The initial routing declared 21 exact schema artifacts: two
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
artifacts plus 27 schema artifacts (three inputs and 24 uploads). All 23 final
controls pass at `ccba883b`; the CLI accepts the complete 176-file synthetic
tree, stages exactly 149 rendered files, and rejects omission of any new root.
The [final CI controls](evidence/office-worksheet-state-20261114/ci-style-integration/README.md)
retain those results. The original 170-file evidence stays intact.

Five new host cases reproduce missing close prompts for RTL/freeze changes,
missing revision tracking during delayed uploads, and wrong-sheet grid history
in actual saved XLSX bytes. The delayed-upload baseline establishes an unchanged
revision after a confirmed view mutation; its immediate editor-presence assertion
did not fail. All five cases now pass their full positive paths on the final
synced app source, including the second save after each delayed upload.

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
passed independent SDK validation. Positive acceptance completes all eight
selected host cases (five worksheet, two style and one native-fill overlap) and
retains all 27 files against the final synced source.

## Final acceptance

| Check | Result | Executed source |
| --- | --- | --- |
| Canonical editor regression group | 100/100 passed; scoped analysis has no issues; 409 unchanged inputs | Suite `0f935a6f` |
| Actual app host workflows | 8/8 passed; three-file analysis has no issues; all three cohorts share 4,743 unchanged inputs | App `ccba883b` |
| Artifact inventory and staging | 23 controls passed; synthetic inventory 176/176; unchanged rendered set 149/149 | App `ccba883b` |
| Independent OpenXML SDK | 27 exact XLSX files, zero errors; three authored inputs and 24 captured uploads | App `ccba883b`, three separately recorded cohorts |
| Guarded source integration | 2,177 managed file hashes and staged Git bytes verified | Canonical pin `0f935a6f` |

The [acceptance index](evidence/office-worksheet-state-20261114/acceptance.json)
binds the final bundle manifests. The
[host receipt](evidence/office-worksheet-state-20261114/host-acceptance/README.md)
retains full logs, exact commands/configuration, source maps, byte-exact raw
LCOV and all native workbooks. The
[independent schema receipt](evidence/office-worksheet-state-20261114/external-final/README.md)
retains SDK reports, self-tests and exact validated copies with hashes checked
before, during and after validation. Coverage cohorts remain separate; no
combined full-application percentage is inferred.

The host tests exercise actual ribbon/menu actions and capture bytes through
the real save path. Worksheet navigation alone uses public `setActiveSheet`,
because the host currently has no worksheet selector. These are headless app
regressions, with schema acceptance for the new artifact roots; they do not
constitute a fresh external-Office rendering or physical-device run.

At the recorded 20:10:10 UTC
[hosted CI observation](evidence/office-worksheet-state-20261114/hosted-ci/execution-sources.json),
the suite fidelity run for `0f935a6f` and app fidelity run for `ccba883b` were
queued. Every listed job had runner ID zero and no executed steps. This is
pending hosted execution, not a passing or failing CI test result; no queue
cause is inferred.

The previous 52-test host cohort, corrected fill rerun and independent four-file
schema acceptance remain unchanged. New negative controls, implementation and
execution results are recorded separately. Earlier queue observations and prior
acceptance totals retain their original source/time.
