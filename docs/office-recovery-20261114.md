# Office host preservation continuation — 14 November 2026

Starting app commit: `15a389f57e3a8fe9837f786407ce787fe198386f`.
Starting canonical suite pin: `b0335829428d50968258219c4fdced15d546f7c9`.
Checkpoint branch in both repositories: `codex/office-recovery-20261114`.

The original recovery started because an interrupted session's newer fixes and
test receipts were absent from the remote app tree. Subsequent checkpoints
preserved the implementation, and macOS integration added separate acceptance
results. The final native archive was published in the canonical suite, but its
app-side index and task statuses were left unfinished. The
[publication audit](evidence/office-recovery-resume-20261114/README.md) now links
and verifies those saved bytes. Each result retains its measured source identity;
historical totals are not tests of later source changes.

## Scoped tasks

| ID | Owner | Acceptance | Status |
| --- | --- | --- | --- |
| REC-05 | Host dialog/export adapters | Unsaved Back and Close share one guarded prompt; edits survive failed saves and disconnected targets; recovery copies export independently and leave the original dirty; cancellation/failure/retry are tested. | Implemented; native and macOS checkpoint acceptance recorded below |
| REC-06 | Host ribbon | Tracking and protection reflect the active controller on import, replacement and history changes; async confirmation cannot mutate a disposed/replaced controller. Depends on suite REC-03. | Implemented; controller/history/race acceptance recorded below |
| REC-07 | Source synchronization and host gate | Import reviewed canonical changes only through `tool/sync_office_fidelity.py`; verify every managed hash and run focused real-host tests with pinned Flutter 3.47.8. | Checkpoint acceptance recorded; recovered tracked-input hashes independently verified |
| REC-08 | Independent workflow evidence | Add independently authored first-save references and inspect actual saved packages; do not accept self-consistency across repeated lossy saves as sufficient evidence. | Historical scoped acceptance complete; exact 149-file native schema and 16-file render evidence recovered |

Canonical formula, style namespace, Word settings/history and signed-package
work is tracked in the suite's `docs/office-recovery-20261114.md` (REC-01–04).
Do not edit vendored copies separately from that source.

## Validation boundaries

Record executed results and exact source identities as work completes. Browser
adapter execution and native schema/render comparisons now have separate
checkpoint receipts. Physical devices, live-provider journeys and authentic
signed Office fixtures remain open. Historical acceptance does not certify a
later merged or modified source tree.
Remote commits are incremental backups; they are not a merge or deployment.

## Checkpoints

- Recovery plan and remote baselines recorded before implementation.
- Final native app measurement: `05905b86ca3a7fc8db3df131620842da3e134061`,
  with suite pin `c85c9f0a81a75a4afb5103d397c1816f0140eb00`.
- Canonical evidence publication: `41072ce7fac74eb54cdbc5e3803a45e605533b06`
  in `CrispStrobe/quds_office_suite`.
- Main integration preserved in this branch by merge
  `4e50879728e05bf73fcf4454512a2ebb78919f32`; this merge itself is not a test run.

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
At this early checkpoint REC-07 had source synchronization and local regression
evidence; REC-08's independent first-save/schema/native-render acceptance was
still open. The later scoped evidence below addresses that gap. These
tests do not certify cryptographic Office signatures or physical-device use.

## Expanded checkpoint acceptance

The later host checkpoint `d6013345` and Quds implementation `36e65201` were also
integrated, together with the canonical source receipts in `ac4889d`. At that
measurement Quds main was `f9512763347f1fea56462c29d10e78d69d606419`; all
**2,168 managed Office files** matched that source. Explicit spreadsheet
font-colour intent survives cloning,
history and saves. Read-only imported Word restrictions and pending-copy chrome
have additional host controls.

Local gates at that checkpoint: **1,731 engine passes** with three conditional skips;
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

## Recovered native evidence and publication completion

The [immutable native receipt](https://github.com/CrispStrobe/quds_office_suite/blob/41072ce7fac74eb54cdbc5e3803a45e605533b06/docs/evidence/office-recovery-20261114/external/external-validation.json)
binds app `05905b86` and suite `c85c9f0a` to **149 schema-valid host/reference
packages**: 146 actual outputs and three independently authored references.
LibreOffice 24.2.7.2 rendered 16 inputs: nine app saves, their three references,
three namespace saves and their reference. Four independent first-save
comparisons and all four three-save groups matched page count, text and pixels.
The separate namespace schema scope contains four files already included in the
suite's 350-file inventory.

The [fresh archive audit](evidence/office-recovery-resume-20261114/archive-audit.json)
checks every archived entry, binds historical schema reports to the exact saved
packages, recomputes saved PNG/text comparisons, and verifies 4,727 tracked
input hashes against the measured app commit. Five additional generated inputs
have preserved hashes only. It also verifies the integrated macOS report hashes
and browser entrypoint/wrapper/adapter source hashes without rerunning those
tools.

The successful collection receipt and source snapshot were recovered. Raw LCOV
and the full native host log were not present in the archive, so the previously
recorded **241 host tests** and **65.4% line coverage** are historical totals,
not newly recalculated results. The app's publication step is complete; new
implementation changes need their own current-source checks. Physical devices,
live providers, and authentic signed-file acceptance remain separate gates.
