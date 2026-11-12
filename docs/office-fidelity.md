# Office import, editing and export fidelity

CrispCloud uses local path overrides for `quds_office_engine` and
`quds_office_editor`. The app must explicitly synchronize source changes.
`tool/office_fidelity_manifest.json` is the authoritative suite commit and
SHA-256 inventory; changing a suite branch alone does not update the app.

The active follow-up branch in both repositories is
`feature/office-fidelity-workflows-20261112`. It retains the newer suite work
already descended from the requested `crispcloud` branch, adds feature-directed
scripts and independent table baselines, and fixes actual-host font, picture
and drawing-history regressions. Local execution results belong to their exact
source hashes. Historical counts and receipts are preserved in
[the previous guide](office-fidelity-before-workflows-20261112.md) and
the named evidence documents; they do not measure this branch's changed code.

## Current vendor revision and follow-up

The [12 November follow-up report](office-fidelity-followup-20261112.md)
records the current source pin, native spreadsheet font geometry, merged-table
addressing, shared custom-tab controls and continuation acceptance.
Reusable parsing, preservation, navigation, search and legacy Word conversion
are maintained in Quds; the app consumes the public APIs and exact source pin.

The [gap-closure report](office-fidelity-gap-closure-20261112.md),
[earlier consolidation report](office-fidelity-consolidation-20261112.md)
and the sections below retain their historical snapshot scope. The manifest is
the authority for the current committed source bytes.

Historical workflow checkpoint (before this integration):

The [workflow acceptance evidence](evidence/office-fidelity-workflows-20261112/README.md)
records the successful app run at
`0bbb7f1fc5ed2a1be8ef7a94acf23ce7c4f7d715`, pinning suite
`c8d5ba3cfddf8c6fd3fa736deab992be1e0cc3aa` through 378 verified files.
It passed 154 actual-host Flutter tests across 21 files, required all 104 host
exports, and passed the vendored 963-test Dart / 389-control Python portable
gate. Open XML SDK accepted all 409 app/engine package instances with zero
errors. Host line execution is 2,540 of 3,782 instrumented lines (67.2%);
all ten scoped files are present, and the report retains all 1,242 unhit lines.
Native rendering and its limitations are recorded separately in that evidence.

## What is checked

| Layer | Scope and evidence |
| --- | --- |
| Shared source | Immutable source commit and every selected vendor file hash |
| Script catalog | 67 named DOCX/XLSX/PPTX operations, each linked to a committed scenario |
| Feature runner | 15 requested feature areas mapped to producer tests, independent package oracles and mutation controls |
| Engine artifacts | 305 required packages: 92 three-save series and 29 standalone source/expected/export files |
| Editor artifacts | 22 required controller/layout exports and separate pinned Flutter PNG comparisons |
| Actual host artifacts | 104 required DOCX/PPTX files, including three-save font and picture scenarios |
| Coverage | Successful exact-input collections, complete instrumented-source inventories and per-line gaps |
| External acceptance | Open XML SDK schema checks and separately reported LibreOffice/Poppler rendering |

A passing semantic oracle checks the declared properties of its corpus. A
passing line proves execution. Neither establishes complete format support or
branch correctness. The source [gap ledger](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-workflows-20261112/docs/office-fidelity-gaps.json)
records scoped fixes, explicit guards and remaining work.

## Run the integration gate

Use the app's pinned Flutter **3.47.8** toolchain from the repository root:

```sh
flutter pub get
bash tool/check_office_fidelity.sh
```

The script checks the pinned files, runs the portable DOCX/XLSX/PPTX corpus and
independent semantic oracles, requires every engine output, then runs the
26-file host cohort with fresh LCOV. It verifies the exact 62-output host
inventory, including custom-tab dialog exports, and checks
the unchanged controller export with the independent ZIP/XML oracle. It deletes
only the expected host artifacts and the intended LCOV before the relevant
tests, preventing stale output from satisfying a missing test.

On Linux, native hooks need a C/C++ compiler. CI installs clang and SQLite
development files and uses the existing system-SQLite wrapper:

On Linux, use the existing system-SQLite hook wrapper with a C/C++ compiler and
SQLite development library installed:

```sh
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

The GitHub workflow `.github/workflows/office-fidelity.yml` runs this command and
uploads exported files and JSON oracle reports. The follow-up report records
the current execution totals and compiler provenance. CI uses clang.

The gate verifies the vendor pin, runs the portable engine corpus and
independent oracles, and requires every engine artifact. It then removes only
the managed host exports, runs the actual app cohort into a new coverage
directory, checks coverage completeness and verifies all 104 host outputs.
It includes loading, actual asynchronous saves, paragraphs, fonts, notes,
headings, tables, TOCs, references, images, slides, previews and content search.
Normal checks never regenerate source expectations or accept new goldens.

Coverage runs use fresh directories under
`build/fidelity-host/coverage/run-*`. `OFFICE_HOST_COVERAGE_DIR` can select a
specific **nonexistent** destination. Existing directories are rejected, so a
failed or interrupted run cannot borrow an earlier LCOV file. The collector
hashes host code, tests, fixtures, shipped assets, relevant configuration and
resolution files, Office tooling and the actual pinned Quds inputs before and
after execution. Only a successful unchanged run receives a receipt.

`office_host_coverage.py` requires that receipt by default and rejects source
or LCOV changes. Its `--allow-unverified` mode is only for explicitly historical
LCOV without a receipt; an invalid existing receipt cannot be bypassed. The
strict gate also requires every matching Office host source to appear in the
instrumentation. Runtime identity is recorded, but installed dependencies and
system libraries are not a hermetic build.

The SQLite wrapper temporarily changes `pubspec.yaml`, and restores it when the
command exits. Collection and strict reporting run inside the same wrapper so
they see identical effective configuration. A later strict recheck must use that
same configuration. Do not commit the temporary native-hook override.

## Inspect, import, modify and export

Run these commands from `packages/quds_office_engine`:

```sh
dart run tool/fidelity/office_steps.dart operations
dart run tool/fidelity/office_steps.dart inspect input.docx
dart run tool/fidelity/office_steps.dart export input.docx output.docx
dart run tool/fidelity/office_steps.dart modify input.docx steps.json edited.docx
dart run tool/fidelity/office_steps.dart roundtrip edited.docx build/my-document 3
```

The same commands accept XLSX and PPTX. `modify` reads a JSON array of steps,
validates fields and writes only after every step succeeds. Invalid steps leave
an existing output unchanged. Use a separate output path to retain the input.
`roundtrip` repeatedly saves and reimports in the original file format.

The [scenario guide](../packages/quds_office_engine/tool/fidelity/README.md)
documents all 49 Word, ten spreadsheet and eight slide operations. They cover
footnotes/endnotes and rich note stories; headings and sparse styles;
paragraph/run formatting, tabs and lists; images and wrapping; table structure
and formatting; TOCs, bookmarks and reference fields; threaded comments;
sections, textflow and positioned frames; sheet values/formulas/dimensions and
ordering; and slide text, geometry, notes, transitions, media and ordering.

For cell text, formatting and unmerge, choose exactly one of physical `column`
or logical `gridColumn`. A logical coordinate inside a merged area selects the
cell owning the visible content. `inspect` exposes both coordinates and merge
origins. Invalid merge chains reject before mutation. Native preferred-width
metadata survives unchanged import/export; explicit point edits and grid-based
merge/unmerge update the intended width.

## Run a feature area

```sh
python3 tool/fidelity/feature_matrix.py list
python3 tool/fidelity/feature_matrix.py plan footnotes headings tables
python3 tool/fidelity/feature_matrix.py run styles references
```

Choose any combination of `footnotes`, `endnotes`, `headings`, `styles`,
`paragraphs`, `images`, `tables`, `tocs`, `textflow`, `placement`, `drawings`,
`references`, `comments`, `spreadsheets` and `slides`.

`plan` prints exact commands and required output paths. `run` validates the
matrix, cleans only its selected managed outputs, executes the required
producers and independent oracles/controls, and records source/output hashes.
A missing producer result, failed process, changed source or simultaneous
feature run fails acceptance. The selected matrix covers 214 outputs;
`check.sh` remains the broader 305-output engine gate.

Editor goldens are listed separately and run in the suite repository under
**Flutter 3.44.0 on Linux**. Do not refresh them using the app's different SDK.
Independent authored source and expected XML define the table-grid scenes;
actual scripted models plus three direct and three isolate reopens must match
the authored reference even during an explicit golden-maintenance run.

## Actual-host regressions

[Font-dialog fidelity](office-font-fidelity-20261112.md) covers exact imported
sizes, unchanged Apply, explicit mixed-selection normalization, preservation
of unrelated properties, active stories, stale targets, undo and redo. Its
17 focused tests require 30 independently inspected DOCX exports.

[Picture insertion and drawing history](office-picture-fidelity-20261112.md)
covers proportional PNG/JPEG/GIF insertion, native extents/transforms, original
bytes and MIME types, bounds, stale picker results and original-slide history.
Its 20 focused tests require 18 DOCX and 12 PPTX exports.

[Paragraph, style, reference and layout regressions](office-host-fidelity-20261112.md)
cover actual host dialogs, precision, formatting preservation, headers,
custom-style discovery, hyperlinks and their command history. Earlier
actual-save regressions delay cloud uploads and inspect the attempted bytes:
newer edits stay dirty, failed uploads retain changes, and Save and Close cannot
close a document with newer unsaved content. Deterministic storage isolates
those editor guarantees; live provider behavior has separate acceptance.

Preview and search tests author ZIP/XML independently. They follow owning
relationships for main parts, headers, footnotes/endnotes, workbook sheets and
slide notes; preserve explicit false formatting and breaks; and exclude orphan
or external content. Cumulative archive and emitted-text budgets reject
amplified input. These readers' Strict-namespace support does not imply full
Strict OOXML editing support.

## External validation and retained evidence

The host artifact checker follows the actual OPC main-part relationship and
requires matching file format, content type and XML root. A renamed Word file
cannot satisfy a slide export. Missing, duplicate, corrupt, ambiguous or
escaping evidence fails. Open XML SDK remains the full schema gate.

With .NET 8 available:

```sh
dotnet run --project tool/office-validation -- --self-test
dotnet run --no-build --project tool/office-validation -- build/fidelity-host build/external/host-schema-report.json
dotnet run --no-build --project tool/office-validation -- build/fidelity build/external/controller-schema-report.json
```

The validator recursively discovers Office packages, validates schema and
records exact input paths and byte hashes. LibreOffice/Poppler reports rendering
separately, comparing repeated saves and declared authored first-save baselines.
A qualified native-only limitation has explicit status and never counts as a
visual pass. Neither validator certifies Microsoft Office pixel equivalence.

| Evidence | Location |
| --- | --- |
| Current source pin and hashes | `tool/office_fidelity_manifest.json` |
| Host exact inventory and SHA receipt | `build/fidelity-host/inventory.json` |
| Successful LCOV plus collection receipt | `build/fidelity-host/coverage/run-*/` |
| Current measured host gaps | `build/fidelity-host/coverage/gaps.json` |
| Actual upload/controller bytes | `build/fidelity-host/`, `build/fidelity/` |
| Engine exports, semantic reports and receipts | `packages/quds_office_engine/build/fidelity*` |
| CI evidence | `office-host-fidelity-evidence`, `office-host-schema-evidence` |

The [workflow](../.github/workflows/office-fidelity.yml) runs feature-branch
checks without deploying the app. After validating downloaded bytes, its
external job stages the exact hash-checked host inventory, renders every host
file and compares repeated saves. Picture-only slide cases require independent
page, rectangle, color and placement measurements; empty extracted text alone
cannot establish a visual pass. Its result must be checked for the exact
commit; queued or cancelled runs do not establish remote CI success.

## Remaining boundaries and synchronization

The host still lacks dedicated Word image wrap/anchor/crop/rotation controls,
Word drawing creation, custom paragraph/character/table-style authoring,
bookmark/citation/cross-reference authoring and custom tab alignment/leader
creation. Native note-menu actions remain separate from the tested Flutter
ribbon. Script support does not imply a corresponding host control exists.
Other operating systems, arbitrary fonts/layouts, full content-control binding,
complex field refresh, arbitrary tracked-change topology and all Office format
combinations require more acceptance evidence. The source ledger states
explicit rejections where an edit would silently corrupt native structure.

To sync a reviewed immutable suite checkpoint:

```sh
python3 tool/sync_office_fidelity.py --source ../quds_office_suite --ref SOURCE_COMMIT --branch feature/office-fidelity-workflows-20261112 --apply
python3 tool/verify_office_fidelity.py
```

The synchronizer checks existing pinned bytes before copying new immutable Git
blobs. It preserves unrelated host changes and updates source revision and
hashes together. Review genuine customizations instead of changing the
manifest to conceal drift. Then run the host and external gates. Preserve old
receipts with their original revisions; do not regenerate expectations merely
because a new exporter produced a different result.
