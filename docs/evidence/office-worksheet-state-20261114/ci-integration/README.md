# CI artifact and schema integration controls

The five CI integration files were validated at app commit
`4518e7719e6d4a78c19386ea4f9dd30933bd6931`, after that source was pushed.
`candidate-inputs.json` and `focused-validation.json` bind the workflow,
verifier, manifest, unit controls, gate script, host test, and pinned reference
fixtures by SHA-256. All captured inputs stayed unchanged during validation.

## Required artifact set

The manifest keeps all **146 existing host outputs and 3 pinned independent
references** in the rendered set. Its explicitly enumerated new section adds
**21 schema-only artifacts**: two authored inputs and nineteen actual uploads.
Four belong to `build/office-fill-host-acceptance`; seventeen belong to
`build/office-sheet-state-acceptance`. Both roots are uploaded, cleaned before
the gate, and required by the exact inventory before the SDK runs.

This manifest scope is separate from the renderer's qualified native-import
exception mechanism. It makes no visual-pass or importer-limitation claim.
Old rendered-root paths cannot be moved into the new section. Their package,
reference-hash, missing-file, unexpected-file, and rendering checks remain
mandatory.

`legacy-rendered-set-preservation.json` compares the complete outputs and
references arrays against app `5454096520802adac784282ee3d4d06d77564ba5`.
Both arrays are exactly equal, including order and every reference field.

## Executed controls

- All **23 focused inventory unit tests passed**. Raw output is in
  `inventory-unittests.log`. They cover absent acceptance directories,
  unexpected Office files, duplicated files under separate wrappers, an
  isolated wrapper containing only an unexpected acceptance file, invalid
  manifest roles/paths, and attempted reclassification of old rendered files.
- `bash -n tool/check_office_fidelity.sh` and the scoped diff check passed.
- The preserved original verifier rejects either new root when declared as an
  ordinary output. `baseline/` contains the original source, original
  manifest/tests, receipt, and a small reproduction script.
- The actual inventory CLI accepted a complete **170/170-file** synthetic
  integrity-control tree. The exact Python staging block extracted from the
  workflow copied **149/149** original rendered files with identical bytes.
  It staged none of the 21 separately scoped files.
- Removing the native-fill directory made the CLI fail with exactly **4**
  missing artifacts and exit code 1. Removing the worksheet-state directory
  made it fail with exactly **17** missing artifacts and exit code 1. Both
  controls kept the old rendered set complete.

`artifact-flow-control/` preserves the complete positive inventory, the two
rejecting inventories, raw CLI logs, exact extracted workflow script, and the
flow receipt. The temporary synthetic package trees are not publication
artifacts. These controls establish artifact integrity and staging behavior;
actual host output and SDK acceptance are recorded separately in
`../external-validation/`.

## Reproduce

At the tested source, run:

```sh
python3 -m unittest discover -s tool -p test_office_host_evidence.py -v
bash -n tool/check_office_fidelity.sh
```

The preserved root-rejection control can be replayed with
`python3 baseline/reproduce_root_rejection.py`. The full CLI/staging control
uses the existing unit package builder and PyYAML:

```sh
python3 run_artifact_flow_control.py --app /path/to/CrispCloud --output /path/to/new-control-directory
```

The control creates a fresh output directory and records its commands, package
hashes, source identities, and return codes. The selected source manifest must
match the recorded 170-file contract. Original receipts should remain intact.
