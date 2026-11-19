# W7 Cloud PR274 bounded handoff — 2026-11-18

PR: https://github.com/CrispStrobe/CrispCloud/pull/274
Branch: `fix/w7-coverage-binding-20261118`. This checkpoint keeps the PR draft.

## Exact observed source and hosted results

The observed hosted source is `23aaa928b5154b314f282391089d6af8fd2bbca6`.
The single cycle194 snapshot recorded 25 SUCCESS, 1 FAILURE, 18 IN_PROGRESS,
1 QUEUED and 3 SKIPPED. This is a snapshot, not terminal qualification.

- Workspace: job [134994294460](https://github.com/CrispStrobe/CrispCloud/actions/runs/44358846226/job/134994294460) passed all 980 tests and the final formatting gate.
- PDF integration: job [134994296155](https://github.com/CrispStrobe/CrispCloud/actions/runs/44358846469/job/134994296155) passed its 4-test preliminary phase, 210 VM tests and 36 Chrome tests. This is actual hosted evidence for the save shortcut focus repair.
- Linux: job [134994296168](https://github.com/CrispStrobe/CrispCloud/actions/runs/44358846552/job/134994296168) admitted the existing CLI-built SMB bridge, 4,024,560 bytes, SHA-256 `2bca999a12e07ab9fd7683cd4cd5a6bbeb58505db42a62cd45c4309de63ca514`, and passed the actual reconnect/resume test (1 PASS). Four synthetic ELF controls are separate evidence.
- That Linux job then failed root analysis with 1,021 errors: 418 in three archived compiler evidence copies and 603 in seven spaCy test files lacking their package-local `package:test` dependency resolution. It never reached the later root coverage suite; no new root coverage acceptance is claimed.
- Text/hex Linux and Windows contracts were still running in the snapshot. Office host-roundtrip was SUCCESS and external-schema was running. No full current-head Office acceptance or collection readback is substituted from these statuses.

## Current bounded correction

Resolve `packages/quds_proofing_spacy` development dependencies in the existing
vendored dependency step, keeping its actual tests included in root analysis.
Exclude only these three archived evidence copies from root analysis:

- `docs/validation/zotero-fidelity-20261116/full-app-build/environment/flutter-build-system.dart`
- `docs/validation/zotero-fidelity-20261116/full-app-build/environment/flutter-kernel-target.dart`
- `docs/validation/zotero-fidelity-20261116/full-app-build/inputs/dart_tool/flutter_build/dart_plugin_registrant.dart`

The adjacent original evidence README explains that the first two are retained
Flutter implementation excerpts used to establish the old compiler completion
boundary. They are not standalone SDK libraries. Their bytes and the archived
registrant remain untouched. No executable source, test, package-wide path or
new diagnostic category is excluded. Existing analyzer severities, lints and
its errors-fail command are unchanged. No runtime, model, schema, coverage floor,
collection guard, vendor pin or numerical budget is changed. Refresh only the
reviewed source digest in the export policy; all policy decisions remain intact.

Static validation: YAML parses; all pre-existing exclusions and diagnostic/lint
configuration remain; source-policy validation and `git diff --check` pass.
These are source checks. The amended head's analyzer, Dart tests, native gates
and sealed Office collection are **UNRUN/pending normal hosted execution**.
No local heavy build, model inference, consumed panel replay or CI rerun was used.

## Evidence boundaries retained

The prior `82967cf5b9daf1cc868f286529bf86929c3fbb8b` Office evidence remains
separate: SDK 540 files, native 149 files, 18 picture oracles, 36 save cycles;
fresh sealed coverage 4097/6258 over 5596 inputs with 32 verified source hashes
and a byte-identical reviewed/synthetic merge tree. It is not new-head proof.
Old `54feca1a` collection/crop evidence and unverified historical 4094/6132 LCOV
also remain separate. All failed job logs and original private receipts remain
retained; no failed result or cancellation is relabeled as pass.

PR237 Linux scope was previously merged at `73f8a91e`; PR238 at `4e848e5f`.
Quds153 was closed without its own merge commit because its source was already
an ancestor; no duplicate merge or accepted new pin is claimed here. The managed
vendor manifest and renderer/test hashes remain unchanged. Provider default is
OFF. Accepted F32 stays unchanged; F16/Q8/Q4 rejected receipts and original
quality budgets remain. No macOS, app, grammar, quantization, speed or native GPU
qualification is inferred from this CI repair. PCS is outside this lane.

## Remaining blocker and next owner steps

The blocker is exact amended-head normal hosted qualification, including the
root analyzer and downstream tests/coverage not reached by the failed Linux job.
Read the new commit's normal job results and actual failure logs. Preserve exact
head/merge-tree/source binding, required native instrumentation and sealed fresh
collection before any acceptance decision. If additional defects appear, repair
their cause without diagnostic, schema, source-policy or floor waivers. Keep all
failed receipts and provider OFF; no consumed W6/96-panel replay, `ci:full`,
local heavy build, PCS duplication or supervisor merge. This checkpoint makes no
merge claim and starts no watcher. The owner stops after committing/pushing it.
