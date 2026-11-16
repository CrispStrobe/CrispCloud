# Canonical integration qualification, 16 November 2026

All accepted tests passed on the combined source. Terminal unit/widget: 1,077
passed, two platform skips. Actual disposable OpenSSH: 25 passed, zero skips.
Actual tmux 3.8: one passed. Combined Office/ODS, Zotero and four hex-package
suites: 169 passed. ODS/Zotero engine: 538 passed. Local ODS import: one passed.

See summary.json and final-integrated-execution.json for source identities and
commands. All watched production/test inputs match the accepted unit source
at delivery, including the later parent-preserving named-expression merges.
All 2,413 managed Office files and the independent parser pin pass their guard.
Analysis has no errors/warnings and three existing informational style lints;
formatting passes for 165 targets. No new full app/web build is claimed.

The external cache/toolchain volumes disappeared during qualification. Exact
locked hosted archives were restored and SHA-256 checked; Git packages retained
the exact production pins. The same pinned Flutter 3.47.8 / Dart 3.13.7 snapshot
ran with relocated cache paths and a restored Rust 1.100.0 toolchain. Production
constraints and lockfile remain unchanged. Reproduction helpers and harness
identities are included. Failed pre-test cache attempts and the initial seven
resize regression failures are preserved separately and excluded from accepted
counts. The resize fix uses callback geometry before xterm commits its size.

ODS import/validation/metadata regressions pass. Dynamic validation links,
arbitrary conditions, advanced conditional formats and complete ODF fidelity
remain partial. Editing ODS creates an XLSX copy and preserves the original.
No private corpus content was copied. No GitHub Actions checks were queried,
awaited or rerun. Canonical branches are updated with fast-forward pushes.
