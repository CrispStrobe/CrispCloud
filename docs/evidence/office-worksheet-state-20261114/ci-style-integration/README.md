# Final CI artifact scope and staging controls

Validated source: app `ccba883b3a042582d3fd80f75772c20bff9e2c4b`.
This is a separate final record. The earlier 170-file checkpoint in
`../ci-integration/` remains unchanged.

## Required files

The final exact inventory requires **176 files**:

- **149 rendered artifacts:** the unchanged 146 existing host outputs and three
  pinned independent references.
- **27 explicitly scoped schema-only artifacts:** three authored inputs and
  24 actual captured uploads, across the worksheet-state (17), style-history
  (6), and native-fill (4) roots.

The new style-history root contains exactly `source.xlsx`,
`cross-sheet-applied.xlsx`, `cross-sheet-undo.xlsx`, `cross-sheet-redo.xlsx`,
`native-undo.xlsx`, and `native-redo.xlsx`. Its two UI cases are in the already
included `office_native_workflow_test.dart`; the gate also includes the five
worksheet-state cases.

`scope-preservation.json` proves structural equality, including order, of all
146 old outputs and three pinned references against app
`5454096520802adac784282ee3d4d06d77564ba5`. It also proves that the prior 21
schema-only entries are unchanged. Only the six explicitly named style-history
files were added. Old rendered-root files cannot be reclassified into the new
manifest section.

Artifact validation scope is separate from the renderer's qualified
native-import exception mechanism. This change creates no visual-pass or
importer-limitation claim for the new roots.

## Results

All **23 focused inventory unit tests passed** at the pushed final source.
The controls require missing-file rejection and unexpected-file rejection in
each of the three roots, including duplicate or unexpected artifacts inside a
separate wrapper. The three authored inputs must have explicit input roles.
Gate shell syntax, the preserved baseline rejection replay, and the scoped
diff check also passed. Exact CI, test, and pinned-reference inputs remained
unchanged; the unrelated live SQLite/pubspec override was neither captured nor
modified by these Python controls.

The actual inventory CLI accepted a complete **176/176-file synthetic OPC
integrity tree**. The exact workflow staging script copied **149/149** original
rendered files with matching bytes and staged none of the 27 separately scoped
files. Removing each acceptance root made the CLI return exit code 1:

| Removed root | Missing files | Required old rendered files still present |
| --- | ---: | ---: |
| Native fill | 4 | 149 |
| Worksheet state | 17 | 149 |
| Style history | 6 | 149 |

The synthetic tree establishes inventory and staging behavior; it is not a
host-run, SDK schema, or rendered acceptance result. Actual current host bytes
and SDK receipts are preserved separately in `../external-final/`.

## Retained evidence and reproduction

`candidate-inputs.json`, `focused-validation.json`, and `commands.json` retain
source hashes and command/return-code bindings. Raw outputs are retained in the
log files. `baseline/` preserves the preceding two-root verifier and a probe
showing that it rejects an explicitly declared third root.
`artifact-flow-control/` contains the complete positive inventory, all three
rejecting inventories, raw logs, the exact workflow staging script, and the
flow receipt. The temporary synthetic package trees are excluded.

At the recorded source:

```sh
python3 -m unittest discover -s tool -p test_office_host_evidence.py -v
bash -n tool/check_office_fidelity.sh
```

The baseline probe runs with
`python3 baseline/reproduce_third_root_rejection.py`. The CLI/staging control
uses the existing package fixture builder and PyYAML:

```sh
python3 run_artifact_flow_control.py --app /path/to/CrispCloud --output /path/to/fresh-control-directory
```

The replay output directory must be new. Keep the original receipts intact.
