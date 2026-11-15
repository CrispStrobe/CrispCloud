# Local integration and qualification continuation

## Saved source and observed cutoff

The app contains main through `ab7f1536`, PR #116 at `bda0374b`, the worksheet
and document-workspace branches, and the separate qualification branch through
`8a4cc8b6`. Incoming evidence remains intact under its original directory and
source identity. The initial audit covered 11 branches and 20 recent PRs; the
later audit covered 13 branches and newly merged PR #117.

The final observed production cutoff is **2026-11-15 09:37:28 UTC (10:37 CET)**.
Canonical Quds `b6bdbc27f79448c394a41edfe74039f1194fe471` combines the bounded
ODS import branch through `fbe879e8`, the earlier preservation fixes, and the
last observed `ddaca09c` default-style/time-format update. Its six changed paths
are synchronized into the app with the guarded tool. All 2,225 managed files
match their canonical content; standalone parser remains
`d422fa99a3a84830794f0e2dc332d59f923779f7`.

The workspace has restored capacity and the pinned Flutter 3.47.8 / Dart 3.13.7
toolchain with genuine native compilers. All five package graphs resolve; the
committed app and CLI lockfiles are unchanged. Real native libraries have built
successfully. Environment receipts retain verified downloads, versions,
launchers and compile/link/run probes.

## Development evidence and final gates

The reconciled app service passes 32 focused development cases. The final
canonical reconciliation passes 85: 49 ODS reader cases, eight time-format
cases, 26 formula cases and two authored-format cases. Strict analysis of the
four affected canonical Dart files is clean. All 35 earlier ODS cases remain,
and the incoming edge fixture retains its original Git blob. Failure baselines,
source snapshots and passing runs remain separately identified.

These development results are not final clean-commit host acceptance. The
final source-bound gates are listed in `final-gate-plan.json`: 49 app suites,
seven editor suites, 17 engine suites; strict analysis of 53 app, five engine
and one CLI file; 82 source/inventory controls; the actual scripted Office
output oracle plus 17 controls; PNG VM/compiled-JavaScript/Python checks; and
separate font-backed navigation captures. Each completed gate, including a
failed gate, is saved remotely immediately before the next gate starts.

The earlier source audit verified 10,429 tracked files and 2,223 managed files.
Its aggregate failed because the output-dependent scripted oracle was attempted
before engine-generated artifacts existed. That failure is retained unchanged.
The corrected source-only runner defers the scripted oracle until the engine
cohort has generated its genuine DOCX/XLSX/PPTX edits and roundtrips.

Remote saves use the authenticated GitHub Git-data API because direct Git writes
lack credentials here. Each save preserves the complete local tree and merge
parents, checks the expected remote head, and reads back the updated ref. No
force update is used. All checkpoints use `[skip ci]`; no Actions run is awaited
or restarted. Native macOS toolbar execution, other platforms, external Office
rendering and broad schema acceptance remain outside these Linux gates.
