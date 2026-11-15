# Final qualification readiness review

**Ready to proceed with the frozen source at `48432b5d0eb22caf365e8659e44ab74cb6aa5a46`.** This is a read-only source/plan/provenance review, not fresh runtime acceptance. Root applied and saved the five-file provenance patch after review; this reviewer made no app writes during readiness review.

## Coverage

The actual manifests contain **63 app, 9 editor and 22 engine suites**, with strict analysis of **72 app, 4 editor, 16 engine and 1 CLI files**. A direct comparison against the previously qualified app source `59466d8b48f329362ab88e9da5e195c849557069` found no changed production Dart file outside the selected strict-analysis manifests and no changed suite file outside the runtime manifests, apart from the two explicitly excluded local-corpus scanners. Standalone parser paths are intentionally assessed separately.

The late canonical changes are covered by the existing ODS reader and authored-format suites, the new `sml_styles_date_test.dart`, `sheet_normal_font_metrics_test.dart`, and the existing `sheet_comments_schema_test.dart`. These cover authored date order/names, month/minute distinction, escaped literals/semicolons, bounded annotation import, native default geometry, and comment author/relationship serialization. The final map-based author interning correction preserves the existing Alice/Bob/Alice → 0/1/0 regression. No further cohort expansion is recommended.

The host recovery changes are covered by the existing preview, source/output inspection, conversion, copy-target, native-converter and real dialog/routing suites, including nine added deterministic recovery cases and translated recovery-consent assertions. New fixtures are generated in the repository; no private corpus is read.

The stable canonical Office pin is `693dfe543ee0cc2934e23bd53aa3dd72156af1b3`. The standalone parser source pin is `09c8b3731edb60bf6e5309578260af36b9433570`; its owner reports 4,122 passing cases across 143 suites plus strict 17-file analysis, saved through `2341b86397093a2f8d3efb23eb9a8b81006550c3`. Those are separate canonical-graph results, not substitutes for the pending host-graph runs. Root detached the local parser checkout to the stable source pin, preserving the existing exact canonical-HEAD source-integrity requirement.

## Provenance issues found and resolved in the saved patch

1. The old runner hashed a pinned Dart binary while invoking bare `dart`/`flutter` through PATH. The current runner invokes the exact SDK binary/launcher and resolves, invokes and hashes the actual Node executable. The portable launcher also explicitly selects the pinned Dart binary.
2. Some nested verification helpers live under excluded evidence directories. The runner now hashes the actual source-integrity helpers, navigation semantic helper, and every referenced prerequisite receipt file.
3. Fixed auxiliary directory names and fixed prerequisite names were unsafe for retries. Receipt, artifact and retained-build directories now follow the explicit gate label; `--engine-label` and `--capture-label` bind dependent gates to the selected passing attempt. Existing output directories are retained or rejected, never silently replaced.
4. Existing generated Office files could otherwise satisfy an oracle before a current engine run. The runner retains prior engine/navigation outputs before each generator gate, fingerprints the fresh outputs immediately afterwards, and stores `produced-files.json` in the indexed receipt. The independent Office and navigation readers require the exact bound bytes.
5. A dependent gate now verifies the prerequisite artifact index, passing status, generator suite, current source/resolution digest, source Git identities/modes and gate-driver identity. An old successful receipt cannot authorize a new-source oracle run.
6. Portable output previously lacked the recursive artifact index expected by the final auditor. The current-continuation portable copy writes that index after genuine VM, compiled-JavaScript and independent Python checks succeed.
7. Root identified a postprocessing rejection corner case. The final patch marks metadata and suite summary qualification as failed, records the error and exits nonzero if fresh-output binding fails. Successful generator receipts explicitly record postprocessing success and the binding-file hash.

Historical evidence drivers are unchanged. `run_portable_current.py` and `run_scripted_oracle_current.py` are explicit copies under this continuation's plans. The patch passed Python AST parsing, shell syntax validation, and `git apply --check`; these checks establish preparation correctness, not runtime acceptance.

## Output labels for the final independent audit

| Gate label | Receipt directory | Retained output directory |
| --- | --- | --- |
| `engine` | `engine` (includes `produced-files.json`) | Actual generated files remain in the engine build directory until independently retained by the oracle |
| `scripted-oracle` | `scripted-oracle` | `scripted-oracle-artifacts` |
| `source-integrity` | `source-integrity` | `source-integrity-details` (82 source/inventory controls plus 3 bundled-notice controls) |
| `png-portable` | `png-portable` | `png-portable-artifacts` |
| `navigation-capture` | `navigation-capture` (includes `produced-files.json`) | Actual generated workbooks and PNGs remain under build until independently retained |
| `navigation-independent-review` | `navigation-independent-review` | `navigation-independent-review-artifacts` |

Retries replace the label in those paths. For example, an `engine-final-2` receipt is selected by `scripted-oracle --engine-label engine-final-2`; a `navigation-capture-2` receipt is selected by `navigation-independent-review --capture-label navigation-capture-2`. The final independent auditor accepts explicit `--gate` and `--artifact-dir` labels and should name only accepted attempts. Rejected attempts remain saved.

The current gate plan correctly combines bundled notices into `source-integrity`, rather than requesting an unsupported duplicate gate. Navigation's 12-case preview execution remains separate from the app cohort and must not inflate its total. Numeric/font/hash checks still require separate inspection of both genuine PNGs. Native macOS/platform execution, external Office rendering and broad Open XML schema qualification remain outside this local acceptance scope.

Machine-readable coverage and original/new patch hashes are retained in `readiness-review.json` and `overlay-manifest.json`. No remaining readiness blocker was found in the reviewed scope. Acceptance still requires the actual passing local receipts, their saved remote checkpoints, fresh retained outputs and the final independent audit.

## Subsequent strict-analysis finding

The first actual `analysis-app` gate at the reviewed source failed with four nullable-result errors and the `use_rethrow_when_possible` lint in the new recovery dialog, plus a deprecated plugin `enable` call in `main.dart`. The manifest/provenance review above was not a compilation claim. Root is preserving that failed raw gate before saving a correction. A minimal dialog-only patch is prepared in `../host-nullability/fix.patch`: it promotes a stable local recovery value into an explicitly nonnullable conversion result and uses `rethrow`. Root owns the separate deprecation correction. The selected cohorts remain unchanged, and a later saved source must pass fresh strict analysis before acceptance.
