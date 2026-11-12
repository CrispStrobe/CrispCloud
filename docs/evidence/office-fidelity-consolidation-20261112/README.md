# Consolidated host acceptance evidence — 12 November 2026

The tested app implementation is `e226859cbde21af0b3d70b755c350978161a73c9`.
All 309 managed source files match suite
`3ff2e15823c86cda88d3369dc4bbabf42f45290a`. The final application tree was clean
when the expanded host gate completed; temporary native-test dependency settings
were restored and no lockfile changed.

## Measured results

- 146 mandatory Office host tests pass.
- 299 focused incoming-feature and affected integration tests pass.
- 598 shared engine tests, 308 Python controls, and all 67 public operations pass.
- Seven vendor-sync controls and 17 host inventory/coverage controls pass.
- The exact inventories contain 241 engine exports and 59 actual host saves:
  48 DOCX, four XLSX, four PPTX, and one DOCM/DOTX/DOTM each.
- All 300 frozen packages pass independent Open XML SDK validation, including
  filename/native Word-type checks. Every schema receipt matches its input hash.
- All 11 novel native host captures convert successfully with the stable
  LibreOffice 24.2.7.2 engine, producing 23 pages. This is a conversion proof,
  not a repeated-save-series claim.
- Fresh coverage is 2,605/3,948 instrumented lines (66.0%) across the 12 declared
  Office sources, including the new Word-preservation, legacy Word and CFB helpers.
  Zero declared files are absent. This is not whole-app or branch coverage.

## Receipt roles

`host-test-acceptance.json` is the immutable test-stage summary. Its external
validation field was still pending when that stage finished.
`external-acceptance.json` is the subsequent completed 300-file schema and
11-file native acceptance, bound to the same app commit and unchanged outputs.
The two are sequential receipts, not competing final results.

`host-coverage.json` contains per-file hashes, exact unhit instrumented lines and
coverage scope. The inventory files identify each required output. `app-inputs.json`
records the hash manifest for the 300 frozen packages; `app-schema.json` contains all SDK
results. `host-native-render.json` records the eleven native conversions and
page fingerprints. `consolidated-ancestry.json` proves inclusion of the eight
selected remote heads in each repository and records the separate draft work.

The provenance files identify the exact validator, official SDK/runtime,
official stable renderer and its documented LibreOfficeKit entry point. The
small supplemental probe script is archived byte-for-byte. The shared renderer
adapter and full source-corpus proof are preserved in the
[source acceptance evidence](https://github.com/CrispStrobe/quds_office_suite/tree/3ff2e15823c86cda88d3369dc4bbabf42f45290a/docs/evidence/office-fidelity-consolidation-20261112).
`artifact-hashes.json` binds all archived data/runtime files.

Absolute paths in raw receipts identify the execution workspace. The frozen
export aggregate lives outside the app checkout so a second copied
`build/fidelity-host` tree cannot satisfy or confuse the exact inventory gate.
The full 300-file input hashes were rechecked after native conversion.
Generated Office/PDF binaries and runtime packages are not duplicated in Git.

The [consolidation report](../../office-fidelity-consolidation-20261112.md)
explains merge decisions, new host behavior, runtime scope, and remaining limits.
Historical top-level coverage/schema JSONs retain their earlier source pins and
are not the acceptance for this combined implementation.
