# Follow-up audit evidence — 14 November 2026

All final local gates passed on clean source commit
**`a25e4ea824886327b97bde2873e6ef175a5ab971`**. Later commits add documentation
and this evidence. See the [audit report](../../parser-audit-20261114-followup.md)
for the six repaired discrepancy families.

- [Final machine-readable receipt](final-receipt.json)
- [Compact evidence archive](evidence.zip)

## Results

| Gate | Result |
| --- | --- |
| Dart tests | 3,903 passed |
| Python tests | 197 passed |
| Compiled JavaScript | 38 acceptance groups passed |
| Analysis and formatting | No issues; 353 files checked, zero formatting changes |
| Retained corpus oracle | 24 source hashes and OOXML package graphs verified |
| Open XML SDK 3.3.0 / Office2019 | 1,114 DOC-derived plus 419 public-model packages; 1,533 total, zero errors |
| SDK controls and determinism | Self-test and positive/negative controls passed; 3,028 files repeated exactly across ten corpus groups |
| Package dry run | Zero warnings; no publication |

The Python log includes deliberately failed gate controls. Its final unittest
result is `OK`. Similarly, the SDK negative-control stage exits one because
both deliberately malformed packages are rejected. Neither is a failure of
the completed acceptance run. Controls are additional to the 1,533 outputs.

## Archive inventory

`evidence.zip` is **1,106,620 bytes**, with **398 members**. `manifest.json`
records the length and SHA-256 of each of the other 397 members. ZIP CRC,
exact member inventory and all member hashes were verified before upload.

Archive SHA-256:

```text
b04be7342342bfa4ee879495fce6e8d26f6fd8e5e07dc9d975bba4585e015146
```

The archive contains:

- `run-metadata.json`: source identity, exact commands, tool versions, counts,
  controls and retention scope.
- `logs/`: all eight final command logs and their zero exit statuses.
- `focused/`: original failures and focused repair/gate logs. These are
  intermediate worktree runs, whose counts are distinct from final acceptance.
- `sdk/`: the full SDK receipt, all twelve validation reports, forty stage
  logs, compiler arguments, validator controls and both generations' corpus
  metadata. Report/log hashes were independently rechecked.
- `sdk/corpus/binary-contracts/`: 57 positive DOC/DOCX pairs, twelve malformed
  DOC inputs and their manifest.
- New public outputs: nine cell-shading, 21 bookmark and twenty textbox DOCX
  packages. Together with the binary group, all 107 new positive packages are
  retained.
- `source/`: a 749-file maintained-source SHA-256 manifest pinned to the tested
  commit, plus the resolved Dart lock file and package configuration.

The preceding 1,426 output packages and validator dependency assemblies are
not duplicated in this compact archive. Their exact hashes, complete SDK
reports and reproducible source inventory remain in the saved receipt.

## Provenance and scope

The full SDK receipt is `sdk/report.json`. Its SHA-256 is:

```text
3e5af3b66057f41f48b99734f2b925498f963f00ef45b70aa6c8d2b1c70b30ce
```

It records a clean worktree and 485 selected gate-input hashes, unchanged
through validation. Their aggregate SHA-256 is:

```text
aa65a8821e8026c81d34f414438f6ae0a26210818e39eba4dab6466c835ec496
```

The validator was freshly built using .NET SDK 8.0.428's direct C# compiler
path with hash-pinned NuGet archives, unchanged validator source and the full
control suite. This pass used the existing fallback without reattempting
ordinary MSBuild. Dart 3.14.0, Python 3.12.14 and Node 24.22.1 are recorded in
the final receipt. Instructions for both SDK build paths are in the
[validation guide](../../../tool/office-validation/README.md).

These are portable conversion, deterministic-output and Office2019
schema/semantic results. The 419 public-model outputs are not binary-DOC
inputs. The oracle verifies retained hashes and package graphs, not a new
native rendering run. No new Word/LibreOffice pagination or editor review
acceptance is claimed, and missing historical native artifacts remain outside
this bundle. Hosted CI status is reported separately from local execution.
