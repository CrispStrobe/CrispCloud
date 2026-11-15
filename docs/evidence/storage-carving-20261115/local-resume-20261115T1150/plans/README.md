# Post-integration qualification plan

This is a command plan, not execution evidence. Apply the proposed ODS viewer
test overlay and manifests after reconciling the incoming application and
canonical branches. Resolve dependencies with the pinned environment, preserve
app and CLI locks, then save the complete source remotely before starting gates.

The selected cohorts grow from 49/7/17 to **63 app / 9 editor / 20 engine suites**.
Strict analysis covers **72 app / 15 engine / 4 editor / 1 CLI files**. The added
files and concrete reasons are recorded in `gate-plan.json`. Two optional local
corpus scanners are preserved as source but excluded from mandatory execution;
their no-input behavior is not qualification evidence.

## Source-bound execution

Use `docs/evidence/storage-carving-20261115/record_gate.py` around every command.
The runner takes `--repo`, `--output`, `--head`, optional `--cwd`, and optional
`--suites`. Add `--tool` for the manifest, the actual Dart/Flutter launcher and
Dart binary, the environment launcher, and any extra Python gate driver. CLI
analysis also needs explicit `--tool cli/.dart_tool/package_config.json` and
`--tool cli/.dart_tool/package_graph.json`, because the current recorder's
snapshot explicitly adds only the app/Office/parser package graphs.

Each gate uses the exact new current remote-saved HEAD. Wait for that local gate
to finish, preserve its complete result including failures, commit/push with
`[skip ci]`, verify the remote ref, and only then start the next gate. Never run
dependency resolution, checkout alignment, source changes or commits during a
recorded gate. A rejected/failed gate remains visible and is followed by a
separately named retry after a saved correction.

Commands below are argument lists to execute inside the recorded gate, with
paths from the prepared manifest expanded as separate arguments. They must run
under the genuine pinned toolchain; native hooks remain enabled.

| Gate | Working directory | Command and acceptance |
| --- | --- | --- |
| analysis-app | app | `dart analyze --fatal-infos --fatal-warnings` plus `analysis-app-files.txt` |
| analysis-engine | app | Same, using `analysis-engine-files.txt`; these are root-relative paths and use the host's stricter rules |
| analysis-editor | app | Same, using `analysis-editor-files.txt` |
| analysis-cli | app | Same, using `analysis-cli-files.txt`, with explicit CLI graph/config hashes |
| app | app | `flutter --no-version-check --suppress-analytics test --no-pub --reporter json --concurrency=2` plus `app-suites.txt` |
| editor | `packages/quds_office_editor` | Same Flutter test command, converting all `editor-suites.txt` paths to absolute paths; recorder's suite manifest stays repository-relative |
| engine | `packages/quds_office_engine` | `dart test --reporter json --concurrency=2` plus absolute paths from `engine-suites.txt` |
| scripted-oracle | app | `python3 docs/evidence/storage-carving-20261115/local-resume-20261115T1010/run_scripted_oracle.py --repo REPO --output NEW_OUTPUT_DIR`; requires the engine gate's actual `build/fidelity-scripted` outputs and retains all 12 files plus 17 controls |
| source-integrity | app | `python3 docs/evidence/storage-carving-20261115/local-resume-20261115T1010/source-integrity/run_source_only_controls.py --repo REPO --quds CANONICAL_REPO --parser PARSER_REPO --output NEW_OUTPUT_DIR`; verifies current pins/source/modes plus the existing 82 controls |
| bundled-notices | app | `python3 tool/verify_bundled_notices.py`, then `python3 -m unittest discover -s tool -p test_bundled_notice_guards.py -v`; retain both commands and raw results, three positive/negative controls |
| png-portable | app | `python3 docs/evidence/storage-carving-20261115/run_portable.py --repo REPO --launcher LAUNCHER --output NEW_OUTPUT_DIR`; launcher contract is `LAUNCHER dart ARGS...`; preserve real compiled JS, VM/JS payloads and both independent Python reports |
| navigation-capture | app | `env OFFICE_NAVIGATION_PREVIEW=1 flutter --no-version-check --suppress-analytics test --no-pub --reporter json --concurrency=1 test/widget/office_sheet_navigation_workflow_test.dart`; recorder uses `navigation-suites.txt`; expect all 12 tests without errors/skips |

Use fresh output directories for every gate. The application navigation suite
also runs during the regular app cohort, but the preview invocation remains a
separate 12-case execution and must not inflate the app acceptance count.

## Navigation artifact review

Before the preview gate, move any already-produced
`build/office-sheet-navigation-acceptance` and
`build/office-sheet-navigation-preview` directories to a separately retained
scratch location, so the next six workbooks and two images must come from this
invocation. Do not delete original evidence. The preview writes:

- `rename-validation.png`, 1600 × 1000, English complete render view with the
  invalid duplicate-name dialog and the editor behind it.
- `worksheet-arabic-narrow.png`, 390 × 1000, Arabic RTL host with worksheet
  selector/rename controls.
- Each image's JSON receipt records source hashes and six real font assets
  (Roboto regular/medium/bold, Noto Naskh Arabic regular/bold and MaterialIcons).
- Six workbooks exercise source, committed draft on switch, corrected rejected
  draft, rename, undo and redo. Their cell identities, reference formulas,
  defined name and decimal validation are checked independently.

After the capture gate succeeds, run:

```bash
python3 PATH/verify_navigation_capture.py \
  --repo REPO \
  --capture-receipt PATH_TO_NAVIGATION_RECORDED_GATE \
  --output NEW_RETAINED_NAVIGATION_DIR
```

This verifies source/font/dimension receipts and imports only the pure
`semantic_workbook` function from the already-saved independent ZIP/XML reader.
It retains all original outputs and creates an exact artifact hash manifest.
Inspect both actual PNGs: readable real glyphs and icons, complete invalid-name
dialog with its error message, and a legible narrow Arabic worksheet toolbar.
Record that visual observation separately from numeric verification. The old
hosted captures explicitly had font deficiencies and are historical references,
not the new preview acceptance.

## Acceptance boundaries

The recovered 996-case receipts, original Office oracle, source checks and
VM/compiled-JS PNG proof were independently revalidated at their exact prior
source. They remain useful predecessor evidence, but the new ODS, Word and
notice and newly discovered standalone parser PR14–18 changes require this new scoped qualification. Test totals must be read
from completed raw machine reports, never predicted from the prior counts.
Native macOS toolbar execution, other platforms, external Office rendering and
broad Open XML schema certification remain separate scopes. No GitHub Actions
run needs to be awaited, polled or restarted for this plan.

## Legacy Word recovery integration

Apply the separately reviewed host overlay only after the canonical parser
reconciliation is synced. It connects the new `recoveredTextOnly` result to
copy classification, explicit recovery review and localized full-loss consent.
Strict source feature inspection remains unchanged; an unreadable source is
represented as unknown, not as a source without macros or auxiliary stories.
Word 6/95 and directory-damaged files may choose a bounded text-only DOCX route;
DOCM/native choices remain unavailable when the source inventory is unknown.

`host-focus-suites.txt` is a six-suite targeted correction check, separate from
the final app cohort. The final 63-suite app run includes all six, so targeted
counts must not be added to the acceptance total. The overlay adds generated
fixtures and nine regression cases across existing suites, plus localization
assertions; final counts come from raw machine events.
