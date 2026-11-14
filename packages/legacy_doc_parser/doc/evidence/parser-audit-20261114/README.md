# Parser audit evidence — 14 November 2026

## Final acceptance

[`final-receipt.json`](final-receipt.json) records clean executable commit
`2f8a307f6066401445109b41466e367dcc94cb99`: 3,688 Dart tests, 195 Python
controls, 34 compiled-JavaScript groups, 24 retained source/package checks,
clean formatting/analysis, a passing package dry run, and 1,426 Open XML SDK
package validations with zero schema errors.

[`final-validation.zip`](final-validation.zip) is a complete compact bundle
with 129 members, including its own SHA-256 member manifest. Archive size:
612,434 bytes. Archive SHA-256:
`e86e9fdf94a3ac505fe81f040a5cbee9fc49c0b7ed999cef5afab6f7b7e5bce5`.
ZIP CRCs, exact member inventory and every member hash were checked before
upload; the uploaded Git blob hash was also matched to the local bytes.

It contains:

- All final command logs/statuses, the resolved dependency lockfile, and hashes
  for 734 maintained source/fixture files.
- The section-range reproduction, its failing regression run and passing
  focused run.
- The complete SDK gate receipt, every per-group SDK report and stage log,
  compiler arguments, generator manifests, and independent validator controls.
- All 44 new section-geometry DOCX outputs.
- The failed normal .NET build's receipt/log, documenting the named-mutex
  environment issue before the successful source-built fallback.

The other generated corpus packages are reproducible from the pinned sources;
their individual hashes and exact repeated-generation manifests are retained
in the SDK receipt, but their package bytes are not duplicated in this compact
archive. The expanded CI job retains all first-generation corpora as artifacts.

## Earlier checkpoint and recovery

`portable-receipt.json`, `portable-source-hashes.json` and
`portable-logs.zip` retain the earlier `64901c6` checkpoint: 3,667 Dart tests,
34 JavaScript groups, 24 source/package checks, and the original geometry,
sink and comment before/after reproductions. The final receipt above
supersedes these counts for the final executable commit; the original files
remain unchanged.

`recovery-inventory.json` and `recovery-recheck.json` independently record the
interrupted fifth-pass archive recovery. Both checks verified 3,124 retained
manifest members. Parts 005–017, containing 10,979 declared files, are absent.
See the [historical recovery index](../parser-audit-20261113-fifth-pass/README.md)
for that exact evidence boundary.

No new native Office rendering or review acceptance is claimed. Scalar bounds,
schema validity and package-graph checks are distinct from native layout.
The [audit report](../../parser-audit-20261114.md) records the fixes, controls,
validation scope and remaining gaps.
