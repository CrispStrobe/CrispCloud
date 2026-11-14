# Final Office host acceptance — 2026-11-14

All eight focused host tests passed on the pushed app checkpoint `ccba883b3a042582d3fd80f75772c20bff9e2c4b`. Three separate successful collections bound their logs, raw LCOV and results to exactly the same 4,743 source/generated inputs. Every collection and subsequent receipt verification restored the committed pubspec bytes and found no input drift. The requested Flutter analysis of the ribbon and both host test files also passed with no issues against that same input map.

| Collection | Host tests passed | Authored XLSX inputs | Actual uploaded XLSX files | Total retained packages |
| --- | ---: | ---: | ---: | ---: |
| Worksheet state and grid history | 5 | 1 | 16 | 17 |
| Ribbon styling history | 2 | 1 | 5 | 6 |
| Three-save native-fill overlap | 1 | 1 | 3 | 4 |
| **Total** | **8** | **3** | **24** | **27** |

## Behaviors verified

- Right-to-left and freeze-only edits from a clean workbook trigger the real close confirmation. Cancel retains the edit, and Save, Undo and Redo produce the expected native `sheetViews` state. Selection-based freezing, top-row freezing, first-column freezing and unfreezing each have captured uploads.
- Right-to-left and freeze edits made during separate delayed Save-and-Close uploads advance the document revision, remain pending after the older upload completes, and survive their own subsequent close/save operation.
- Deleting a Budget row, navigating to Reference, and using the real Undo/Redo menu targets Budget throughout. Actual uploads retain the expected contents of both worksheets.
- Ribbon styling Undo/Redo targets its original worksheet after navigation. Same-sheet styling Undo/Redo preserves independently authored gradient/pattern fills, native font theme/tint metadata, explicit versus implicit style provenance, and cell values. The native assertions compare uploaded XML against authored source definitions.
- The existing native-fill preservation case passes through three fresh real host uploads against the same final app source.

Only worksheet navigation uses public `setActiveSheet`, because the host exposes no worksheet selector. The new setting/style/history/save cases use actual ribbon and menu controls. The existing native-fill case uses the real host save callback. The cases are headless Flutter host regressions with genuine native hooks and captured cloud uploads; they do not claim manual interaction with an external Office application.

The independent SDK agent separately confirmed zero OpenXML schema errors in all 27 exact packages, with a validator self-test before each cohort and stable artifact/source hashes. Its independent receipts are retained separately from this host execution bundle.

## Evidence layout

Each collection has `execution/` and `coverage/` directories. Execution retains the full native test log, exact command and environment, source/input map, generated dependency/config bytes, committed and collected pubspec views, successful run/verification status, exact workbook bytes, and their SHA-256 manifest. Coverage retains the original successful `collection-receipt.json`, the full scoped coverage report, and gzip-compressed byte-exact raw `lcov.info`. `receipt.json` records the uncompressed LCOV hash and size, so decompression reproduces the original collected bytes.

All three original input maps are identical, as are all three collected input maps. The sole original-versus-collected difference is the explicitly recorded temporary system-SQLite hook in `pubspec.yaml`. The committed helper restores it after each run, and coverage verification recreates that exact collected view. Coverage reports describe their individual cohorts; overlapping line counts are not additive and are not an overall application coverage claim.

`analysis/` binds the final three-file analyzer command, log and zero-issue result to the same input tree. `run_validation.py` and `analyze_final.py` retain the capture commands, while `environment-source-receipt.json` and `native-launchers/` retain their task-local environment recipe. The guarded `replay_recorded_run.py` verifies a prepared checkout against a recorded map before replaying a command into a fresh build destination. Toolchain/dependency paths document the actual workspace rather than a hermetic or portable build.

Earlier outputs were archived verbatim before these fresh artifact roots were created; `preserved-prior-artifacts.json` records their hashes. The negative controls remain in the separate baseline bundles. `manifest.json` binds every retained file in this final host bundle.
