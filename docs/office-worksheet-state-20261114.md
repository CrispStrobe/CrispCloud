# Worksheet state integration — 14 November 2026

Starting app source: `a3897dfbe2d3721e0ec0756a1872132daf9f6b90`.
Canonical starting source: `2d2a7be43e19b478c532025fe1f275ed7b00ef75`.
Checkpoint branch: `codex/office-recovery-20261114` in both repositories.

The next increment makes persisted worksheet RTL/frozen-pane settings participate
in history, dirty state and save revisions. It also addresses grid history that
can target the wrong sheet after navigation. Quds owns these controller fixes;
the app will consume exact reviewed source bytes through the guarded sync.

Actual host acceptance will cover the ribbon/close path, a view change during
an upload, and saved workbook contents after history across worksheet tabs.
The existing native-fill capture directory was absent from the CI upload and
inventory routes. The new routing declares 21 exact schema artifacts: two
authored inputs and 19 actual host outputs across the native-fill and
worksheet-state directories. The existing 146 rendered outputs and three pinned
references remain unchanged. Focused inventory controls are pending.

Five new host cases reproduce missing close prompts for RTL/freeze changes,
missing revision tracking during delayed uploads, and wrong-sheet grid history
in actual saved XLSX bytes. The delayed-upload baseline establishes an unchanged
revision after a confirmed view mutation; its immediate editor-presence assertion
did not fail. Positive host validation awaits the guarded canonical source sync.

The [retained host baseline](evidence/office-worksheet-state-20261114/host-baseline/README.md)
records the final five behavioral failures, all earlier test-harness attempts,
4,740 stable execution inputs, exact workbook bytes and independent validation
of the authored input. Its final test source is committed at `4518e771`.

The previous 52-test host cohort, corrected fill rerun and independent four-file
schema acceptance remain unchanged. New negative controls, implementation and
execution results will be recorded separately. The remote CI jobs have not
acquired runners; their queue is not treated as an executed failure or pass.
