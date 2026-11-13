# Portable and schema acceptance at 48bf3a

The final portable gates passed at runtime commit
`48bf3a84e822b960e369f0134d597e025c775a41`, tree
`a952a0b5930baf97728120e6f34062586df89d11`. Open XML SDK 3.3.0
validated all 229 generated DOCX packages with zero errors. Two independent
generation runs produced the same 486 files, including their source DOC files,
case inventories and media, byte for byte.

This folder records portable execution and Office2019 schema/semantic
validation. It makes **no native rendering, review rendering, pagination or
layout-fidelity claim**. The native corpus evidence is recorded separately.
There is no additional table-only gate in this bundle; this continuation did
not change table runtime code. Existing table cases remain in the required
229-case schema corpus.

## Recorded results

| Gate | Recorded result |
| --- | --- |
| Source integrity | Clean worktree before/after; all 807 captured input hashes unchanged |
| Dart | SDK 3.13.7; 192 files formatted with zero changes; analysis found no issues |
| Dart tests | 934 passed |
| Python oracle controls | 162 passed |
| Fixture integrity | 24 source hashes and OOXML package graphs verified |
| JavaScript | Actual legacy DOC conversion acceptance plus 51 media checks passed |
| Package dry run | Zero warnings; no package publication |
| Schema build | .NET SDK 8.0.428, runtime 8.0.34, compiler 4.11.0-3.25569.22 |
| Validator | Open XML SDK 3.3.0, Office2019 validation; original vendored validator source retained |
| Validator self-test | 8 valid Word packages, 4 invalid XML cases, 12 mismatched types and exact discovery passed |
| External controls | One valid DOCX accepted; both deliberately malformed DOCX files rejected with their expected schema errors |
| Schema corpus | 229 DOCX files accepted, zero errors |
| Deterministic generation | Both complete 486-file inventories and every file's bytes match |

The portable Python log contains deliberate compile-failure and rejected-control
messages from its negative tests; its final result is `Ran 162 tests` / `OK`.
The schema `negative-controls` stage intentionally exits 1. Its two reports
contain the expected invalid-child and invalid-`noWrap` schema errors, with no
validator exceptions. The verifier checks this expected failure rather than
requiring every command to return zero.

## Retained bytes and provenance

`validation-artifacts.tar.xz` contains **1,174 regular files**, totaling
**21,365,840 uncompressed bytes**, in a **1,287,572-byte** archive. Its SHA256 is
`88ee44728ee2d7b950aab1596cf0e7a0c0adff14ecee9150ceec4f60a1f4b5de`.
`validation-artifacts.manifest.json` lists every archive path, byte length and
SHA256, plus the omitted binary inventory and verifier source hash.

| Archive prefix | Contents |
| --- | --- |
| `portable/` | All eight stage logs and the complete before/after source receipt |
| `schema/` | Unmodified gate report, SDK JSON reports, all thirteen stage logs, controls, compiler response file, generated implicit imports, runtime configuration and both complete corpora |
| `source/` | All 165 files in the schema gate's captured source snapshot, including the parser, fixture generators, input fixtures, validator source/provenance, lockfile and package configuration |
| `source-identity/` | Exact Git commit and root-tree object bytes, verifiable against the pinned object IDs |
| `toolchains/` | Exact Dart, .NET SDK and NuGet recovery receipts, including download URLs and recorded hashes |

Only four reproducible validator DLLs are omitted: `OfficeValidation.dll`,
`DocumentFormat.OpenXml.dll`, `DocumentFormat.OpenXml.Framework.dll` and
`System.IO.Packaging.dll`. Their exact sizes and SHA256 values remain in the
manifest and are cross-checked against the original build report. The report
also retains compiler, host executable, reference-assembly, NuGet archive and
assembly hashes. SDK installations and executable archives are not copied into
this bundle. No incidental .NET home caches are included.

The source receipt covers all 805 files tracked at the pinned commit, plus
`pubspec.lock` and `.dart_tool/package_config.json`. Those two generated files
are retained under `source/`; the other tracked files remain available from the
pinned Git history. The 165 retained schema sources match both gates' source
receipts. Absolute paths in original logs, commands, package configuration and
SDK reports are preserved as historical provenance, not rewritten for this
archive.

## Verify the delivered archive

From the repository root, using Python 3:

```sh
python3 doc/evidence/continuation-48bf3a/seal_validation_evidence.py --self-test
```

To additionally compare every captured tracked source file against the actual
Git objects at the pinned runtime commit:

```sh
python3 doc/evidence/continuation-48bf3a/seal_validation_evidence.py \
  --repository . --self-test
```

The verifier reads the serialized archive and checks its checksum, exact member
inventory, safe regular-file paths, every member's size/hash, both complete
486-file corpus inventories and bytes, all 21 stage log hashes and exit codes,
source snapshots, all case source/output hashes, complete SDK output coverage,
intended negative-control errors, retained build configuration and omitted
binary hashes. It also verifies the Git commit/tree object IDs. The repository
option independently checks all 805 captured tracked inputs against their
pinned Git blobs; it does not depend on the current worktree being at that
commit.

Nine in-memory corruption controls exercise omitted non-DOCX repeat inputs,
changed source DOC bytes in both runs, a missing schema stage, accepted negative
controls, an incorrect SDK output hash, modified retained source, inconsistent
before/after source receipts, an incorrect omitted binary hash and a changed
build log. All must be rejected. Checks remain active under `python3 -O`.
These checks verify retained evidence and provenance; they do not rerun Dart,
the compiler or the SDK validator. The manifest and hashes are an integrity
record, not a cryptographic signature by an external attestor.

To reproduce the original gates, use the recorded commands in
`portable/receipt.json` and `schema/report.json` with the pinned source and
toolchain versions. The portable runner is
`doc/evidence/continuation-0c3e596/run_parser_gate.py`; the schema gate is
`tool/fidelity/schema.py`. No source fixture or expected rendering was changed
to create this evidence.
