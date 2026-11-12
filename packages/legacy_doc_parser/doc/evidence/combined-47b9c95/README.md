# Integrated parser acceptance

The clean published source `47b9c95c061178fec69d0d546bf12948ccca0709` passes
**809 Dart tests, 162 Python tests, JavaScript/Node DOC acceptance and 51 media
checks**, whole-package formatting and analysis. The publish dry run has zero
warnings; no package was published.

The independent Open XML SDK 3.3.0 gate accepts **all 218 required DOCX outputs**
with zero errors. It preserves all 194 earlier cases, including the exact
first-header round-trip failure input, and adds all 24 textbox-table controls.
The gate checks the exact required case set, file hashes, deterministic generation
of 464 files, unchanged inputs and positive/negative validator controls.

## Runtime and native evidence

The entire `lib/` tree and dependency manifests are byte-identical to the runtime
in pushed `c3fa95e`. The [complete native run](../e90f38f/README.md) therefore
remains evidence for those exact runtime bytes: 24 initial imports, 72 repeat
imports, 24 equal initial page counts and six exact initial renders. It is not
a new native execution of the optional gzip raster path. Python controls
separately check that option's integrity and failure handling.

The [textbox-table counterexample](../textbox-table-context-20261112/README.md)
and withdrawn depth reset remain preserved. The two native header/table
limitations in that receipt remain failures; the 24 synthetic schema controls
do not change their status.

## Producer-metadata follow-up

A subsequent test-only addition executes the fixture producer and compares
all 24 emitted manifest expectations with actual DOCX textbox and surrounding
anchor-table indentation. Its 13 focused Dart tests, formatting and analysis
pass. The current producer was already corrected in `47b9c95`; no further
producer or runtime change was needed. This checks artifact metadata against
the actual package rather than accepting the manifest as its own oracle.
`summary.json` binds the tested follow-up to its exact test blob and local
source commit. The focused log is retained without claiming an additional
whole-package run.

## Retained receipts

`summary.json` records each compressed and original SHA-256 and size. The GZIP
files retain complete portable output, the full independent schema report,
the validator output and the focused test log without modifying their bytes.
These are validity and regression results, not a certificate of exact
pagination, complete OfficeArt, ink rendering or full revision semantics.
