> **Continuation update:** observed incoming commit `3e9560c9` adds comment-part namespace/relationship handling. The earlier local gates below belong to source `96634597`. Final source qualification is pending the reviewed comment correction and a new source freeze; these earlier counts are not acceptance for changed source.

# Local qualification plan — isolated continuation, 15 November 2026

**Status: local qualification in progress on saved source `966345971a50ef93bcb67ed32060c8176b4d2949`. Only completed receipts establish passing results.**

This evidence base is for `integration/storage-carving-local-20261115124645`, created from observed app commit `41885d7d1d67348f5abe3579b99d9d2951fc909f`. Managed synchronization and app/CLI/engine/editor offline resolution are complete, committed lockfiles are unchanged, and the source is saved remotely before the first gate. `source-checkpoint.json` records its exact identity. The app strict-analysis gate has passed; remaining gates are pending.

The intended canonical source pins are Quds `9bb71983a4ae6bc7bb3372fd931e724ddd102fc8` and parser `08296edbee08da013a8ff718798972552ccd03f7`. Quds restores the three currency/padding/geometry ODS regressions removed by the observed upstream reconciliation. The new ODS covered-cell and 10,000-comment admission behavior, Linux golden references, and parser regression remain incorporated. Source mirrors and graph setup must finish before qualification.

## Exact selected scope

| Group | Manifest entries |
| --- | ---: |
| App tests | 65 suites |
| Engine tests | 22 suites |
| Editor tests | 11 suites |
| App strict analysis | 76 files |
| Engine strict analysis | 16 files |
| Editor strict analysis | 6 files |
| CLI strict analysis | 1 file |
| Navigation capture | 1 separate suite |

The editor additions are `office_fidelity_golden_test.dart` and `office_structure_goldens_test.dart`, included in both test and strict-analysis manifests. They exercise five exact Linux references through four test cases and 18 image comparisons. Those are scope expectations only; completed raw machine events determine the eventual test count.

The parser's production/dependency/unchanged-test identity preserves the prior 144-suite, 4,131-test full run. Fresh qualification at the observed pin passes the changed 18-test suite (the previous 17 plus one) and strict analysis of that changed file; no fresh full 4,132-test run is claimed. Exact linkage is saved in `canonical-parser-observed-pin/`. The host graph remains independently covered by the host cohorts. Both optional private Documents/Downloads corpus scanners are excluded and do not contribute empty-input passes.

## Execution order and checkpoint discipline

Run the four strict groups, then app, engine, editor, independent Office oracle, source integrity, portable PNG, navigation capture, and independent navigation review. Each gate is a separate action: save the completed receipt remotely before starting the next. Preserve failures and use a fresh retry label; never overwrite receipts. The JSON plan contains the exact inventory counts and expected inputs, and `gate-commands.json` contains one argument array per gate.

The runner and wrappers derive current manifests, scripts, receipt outputs and artifact outputs from this new evidence base. The source-integrity gate uses sibling checkouts `QudsCanonical` and `ParserCanonical`, whose HEADs must match the final app pins. Fixed historical recorder/source-integrity/semantic-reader helpers remain intentional dependencies and are hashed by the runner. No historical receipt is modified or counted as current acceptance.

Existing safeguards remain intact: pinned Dart and Flutter executables, resolved and hashed Node, helper and prerequisite hashes, clean saved source, stable before/after source and resolution inputs, fresh artifact paths, generated-file binding immediately after a passed engine/capture run, and failed qualification if output postprocessing fails. Dependent gates require exact generator labels and hashes. The 12 produced Office documents and six navigation workbooks must be retained with their bound receipts.

Resolve and freeze every required package graph before beginning. Do not disable native hooks, substitute fake libraries, alter source or tools while a gate runs, use `--update-goldens`, relax the golden comparator, skip new goldens, or poll/wait for GitHub Actions. Save incremental commits with `[skip ci]` on the isolated remote branch.

## Linux goldens and review scope

The existing pinned Linux Flutter 3.47.8 / Dart 3.13.7 toolchain will compare the exact saved references. The imported provenance claims a matching Flutter 3.47.8 run, but it does not contain an immutable capture source SHA; that claim is not substituted for fresh source-bound results. All five Linux reference hashes and dimensions were independently checked in the incoming review, and all five images were visually inspected. No reference was generated or changed for this preflight.

If comparison fails, preserve the raw failed receipt and any `packages/quds_office_editor/test/failures/` images and `build/fidelity-diagnostics/` files before correction or retry. These local golden tests do not establish external Microsoft Word rendering or cross-platform release acceptance. Navigation's two actual PNGs still require their separate visual inspection after capture; its repeated suite is not added again to the primary host count.

## Previous evidence and this plan's verification

The prior acceptance applies to production source `20ee83ff965d5433aeb528ae84debdb304edcf4a` and was preserved remotely at `6a5603236c9f3f9e186c5eb3ba5fd76a085b1df6`. Its counts and common digest remain historical evidence. The new ODS source, parser pin/mirrored evidence and golden files change the combined snapshot; only new completed receipts qualify this continuation.

`historical/readiness-review.json` and `historical/provenance-overlay-manifest.json` are byte-for-byte inherited reports about an earlier source/overlay. They are retained under explicitly historical names. `incoming-review/` describes immutable app `41885d7d`, before the three ODS tests were restored by intended Quds pin `9bb71983`; the present plan supersedes its pending-restoration note.

`plan-readiness.json` records only static preparation: unique manifest entries, Python syntax parsing, shell syntax checking, corrected canonical paths and preserved helper bytes. No app source was modified by the reviewer, no repository HEAD was moved, and no runtime test was executed while preparing this package. The final app source commit and acceptance results remain pending root's subsequent source checkpoint and gates.
