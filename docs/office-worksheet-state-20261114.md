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
The existing native-fill capture directory is absent from the current CI upload
and inventory routes. That concrete gap will be closed together with the new
worksheet-state artifacts, keeping schema and rendering scopes explicit.

The previous 52-test host cohort, corrected fill rerun and independent four-file
schema acceptance remain unchanged. New negative controls, implementation and
execution results will be recorded separately. The remote CI jobs have not
acquired runners; their queue is not treated as an executed failure or pass.
