# Worksheet navigation evidence — 15 November 2026

## Current evidence map

The [acceptance document](../../office-worksheet-navigation-20261115.md)
identifies current results, source identities and UI status.

| Directory | Evidence |
| --- | --- |
| `integration/` | Original guarded canonical sync and host analysis |
| `resume/inventory-repair-baseline/` | Unmodified inventory and original collisions |
| `resume/inventory-repair-validation/` | 32 controls, exact 57-collision replay and repaired 182-file inventory |
| `resume/hosted-7e5af83c/` | Successful source-bound hosted acceptance, original ZIPs, full logs, reports and independent verification |
| `resume/local-preview-20261115/` | Local locked-resolution, format and analysis results; disk-exhausted native build before tests; recovery boundary |

The successful run validates 540 packages and renders 149 files, including
36 save-cycle and three reference comparisons. All five retained archive
digests, 1,843 extracted files, 540 SDK input hashes, six navigation workbook
semantics and 201 rendered PNG pixel fingerprints are independently checked.
See [retention and replay instructions](resume/hosted-7e5af83c/README.md).

The six navigation workbooks remain schema-scoped. Initial UI captures have
verified geometry but known test-font limitations; readable replacements are
a separate execution and visual-inspection gate. Original failed run
`43681914471`, successful run `43685477823`, and the preview-only rerun retain
separate identities.

## Original inventory/validator checkpoint (historical)

`inventory/` retains 23 passing host-artifact controls and a synthetic inventory
check. The previous 146 actual rendered outputs, three independent references,
and 27 schema-scoped artifacts remain required. Six new worksheet-navigation
artifacts bring the inventory to 182 files: 149 rendering/reference and 33
schema-scoped. Synthetic files establish inventory behavior only.

`validator/` records the unchanged OpenXML validator build, exact dependency
hashes and successful valid/invalid/type-mismatch self-tests. The compiler
response file and helper scripts describe this workspace execution; rerunning
them elsewhere requires choosing the local toolchain path. Actual host artifact
validation is pending at this checkpoint.

Historical results from the interrupted conversation are not relabeled as
current acceptance. Baseline, implementation and positive runs are retained
separately with their source and input receipts.
