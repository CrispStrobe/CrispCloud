# Fifth-pass evidence: interrupted upload

The implementation and test fixes were committed before the session stopped.
The evidence upload stopped after data archive 004. This directory preserves
exactly the uploaded historical archive bytes; it is not a complete bundle.

## Available files

| Archive | Bytes | Manifest entries |
| --- | ---: | ---: |
| `bundle/evidence-000-control.zip` | 1,184,077 | Control metadata only |
| `bundle/evidence-001.zip` | 1,899,876 | 572 |
| `bundle/evidence-002.zip` | 1,899,958 | 879 |
| `bundle/evidence-003.zip` | 1,898,512 | 1,029 |
| `bundle/evidence-004.zip` | 1,899,514 | 644 |

The control ZIP contains `manifest.json`, `SHA256SUMS` and
`partition-plan.json`. The plan specifies 17 data archives. Archives
`evidence-005.zip` through `evidence-017.zip` are absent.

On 14 November 2026, all five available ZIPs passed CRC checks and all 3,124
available data members matched their manifest SHA-256 values. The manifest
contains 14,103 data files, leaving 10,979 missing. This is an availability
failure, not a hash failure in the retained subset. The
[recovery inventory](../parser-audit-20261114/recovery-inventory.json) records
this distinction in machine-readable form.

## Useful retained records

Data archive 001 contains:

- `metadata/evidence-interpretation.json` and
  `metadata/source-identities/final.json`.
- `runs/final/acceptance/portable-receipt.json`,
  `schema-receipt.json`, their command logs and targeted validation reports.
- Resolved dependency and independent-validator source records.
- The start of the final generated corpus, continued in archives 002–004.

The final receipts identify
`6b57d176fccd6f4b8b11bae2e7168f73e870e9dc`. They record passing portable and
SDK acceptance and unchanged source identities for that runtime. They do not
prove acceptance of later changes. The [reconstructed fifth-pass report](../../parser-audit-20261113-fifth-pass.md)
summarizes those historical results and the saved runtime fixes.

The missing archive range includes most preflight and exploratory runs, the
principal native field/list comparisons and reruns, source snapshots and
supporting harness material. A full manifest replay cannot pass with this
partial upload. Do not silently skip absent files, regenerate historical
native bytes under their old names, or describe a new run as recovery of the
original bundle.

## Read the retained receipts without extracting the archive

From the repository root:

```sh
python3 - <<'PY'
from zipfile import ZipFile

path = "doc/evidence/parser-audit-20261113-fifth-pass/bundle/evidence-001.zip"
with ZipFile(path) as archive:
    for name in (
        "metadata/evidence-interpretation.json",
        "runs/final/acceptance/portable-receipt.json",
        "runs/final/acceptance/schema-receipt.json",
    ):
        print(name)
        print(archive.read(name).decode("utf-8"))
PY
```

The old control manifest is retained unchanged so that recovered original
parts, if supplied later, can be authenticated against the original inventory.
New validation should be saved separately with its own source and output
identities.
