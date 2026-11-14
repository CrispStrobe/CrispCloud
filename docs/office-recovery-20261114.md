# Office host preservation continuation — 14 November 2026

Starting app commit: `15a389f57e3a8fe9837f786407ce787fe198386f`.
Starting canonical suite pin: `b0335829428d50968258219c4fdced15d546f7c9`.
Checkpoint branch in both repositories: `codex/office-recovery-20261114`.

The prior interrupted session's newer fixes and final test receipts were not
present in the remote app tree. Its claimed totals are not evidence for this
continuation. Historical coverage/schema/render documents retain their original
scope and source identity.

## Scoped tasks

| ID | Owner | Acceptance | Status |
| --- | --- | --- | --- |
| REC-05 | Host dialog/export adapters | Unsaved Back and Close share one guarded prompt; edits survive failed saves and disconnected targets; recovery copies export independently and leave the original dirty; cancellation/failure/retry are tested. | Planned |
| REC-06 | Host ribbon | Tracking and protection reflect the active controller on import, replacement and history changes; async confirmation cannot mutate a disposed/replaced controller. Depends on suite REC-03. | Planned |
| REC-07 | Source synchronization and host gate | Import reviewed canonical changes only through `tool/sync_office_fidelity.py`; verify every managed hash and run focused real-host tests with pinned Flutter 3.47.8. | Planned |
| REC-08 | Independent workflow evidence | Add independently authored first-save references and inspect actual saved packages; do not accept self-consistency across repeated lossy saves as sufficient evidence. | Open |

Canonical formula, style namespace, Word settings/history and signed-package
work is tracked in the suite's `docs/office-recovery-20261114.md` (REC-01–04).
Do not edit vendored copies separately from that source.

## Validation boundaries

Record executed results and exact source identities as work completes. Browser
execution, physical devices, genuinely signed Office fixtures and independent
schema/render comparisons remain open until their own gates are executed.
Remote commits are incremental backups; they are not a merge or deployment.

## Checkpoints

- Recovery plan and remote baselines recorded before implementation.

## Integrated acceptance on macOS

The integrator brought host checkpoint `9c1eae58` together with canonical Quds
`7d5f8dac922f2771b1ac767f835a3e1d8d536ade`, using Flutter 3.47.8 / Dart 3.13.7.
All **2,167 managed Office files** match the canonical sources; the standalone
legacy parser remains pinned at `544a50e7`.

REC-05 and REC-06 now have executed host regression coverage: unsaved system
Back/Close, Cancel/Discard/Save, pending uploads, disconnected originals,
copy-export cancellation/failure/retry, edits during export, controller
replacement, protection confirmation races, and tracking/protection undo/redo.
Refused signed XLSX/PPTX packages can export their exact original bytes.
The copy action never marks an unsaved original clean.

- Office host/save/formatting/CSV cohort: **46 passed**.
- Latest combined Office lifecycle/ribbon and comparison cohort: **198 passed**.
  These cohorts overlap and their counts must not be added.
- Canonical engine suite: **1,728 passed**, three conditional skips.
- Canonical editor suite: **520 passed**, one conditional skip, 17 pre-existing
  macOS golden failures. The previous main fails the same 17 tests, and all
  27 retained actual golden PNGs match the integration byte for byte. No golden
  references were updated to hide these failures.

Integration also corrected a missing import in the incoming ribbon tests and
waits for actual route disposal in the clean/Discard navigation tests.
REC-07 has source synchronization and local regression evidence; REC-08's
independent first-save/schema/native-render acceptance remains open. These
tests do not certify cryptographic Office signatures or physical-device use.

## Expanded checkpoint acceptance

The later host checkpoint `d6013345` and Quds implementation `36e65201` are also
integrated, together with the canonical source receipts in `ac4889d`. Quds main
is `f9512763347f1fea56462c29d10e78d69d606419`; all **2,168 managed Office files**
match that source. Explicit spreadsheet font-colour intent now survives cloning,
history and saves. Read-only imported Word restrictions and pending-copy chrome
have additional host controls.

Fresh local gates: **1,731 engine passes** with three conditional skips;
**522 editor passes**, one conditional skip and the same 17 baseline golden
failures; **55 host passes**, two platform skips. The latest arrival-specific
comparison/ribbon/file-operation cohort passes **173 tests**. Coverage/evidence
guards pass **17 and 16 Python tests**; render controls pass **72**. Cohorts
overlap and are not additive.

Independently authored Word/XLSX/PPTX references and actual host saves were
rendered by LibreOffice 26.8.2.2: **12 files, 12 pages, three save-cycle groups,
three baseline comparisons, zero failures**. The real browser copy adapter also
compiled and executed in installed Chrome: its downloaded bytes and filename,
anchor cleanup and delayed object-URL revocation passed. The
[retained acceptance receipt](evidence/office-recovery-20261114/integrated-macos/acceptance.json)
links exact render and browser receipts. The native probe did not run a fresh
schema validator. Wider REC-08 coverage and physical-platform acceptance remain
separate work.
