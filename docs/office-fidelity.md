# Office import/edit/export fidelity

CrispCloud resolves `quds_office_engine` and `quds_office_editor` through local
path overrides. These vendored packages need explicit synchronization with the
Quds fork; changing the upstream branch alone cannot update the running app.
The host also has its own save, preview and content-search behavior, which is
tested separately from the engine.

`tool/office_fidelity_manifest.json` records the authoritative source commit and
SHA-256 hashes for the selected shared implementation, scenario, fixture and
golden files. The guard checks only those files, preserving unrelated host
changes. Revision IDs and counts in the historical evidence below identify
their original snapshots, not the current manifest.

## Host expansion on 2026-11-12

The [host paragraph/style/reference/layout audit](office-host-fidelity-20261112.md)
records the new actual-dialog regressions, independent authored XML expectations,
repeated exports, exact artifact inventory and coverage-completeness controls.
It closes host precision loss, collateral formatting changes, active-story
confusion, missing custom styles and hyperlink-history integration gaps. Read
the current manifest and this branch's execution evidence when evaluating the
new checkpoint; earlier coverage percentages do not measure changed code.

## Previously verified vendor revision (2026-11-11)

The previously verified vendor manifest selected
Quds commit
[`692a326`](https://github.com/CrispStrobe/quds_office_suite/commit/692a326aae2e8133b793570344028a1ceffddbdc)
and **154 shared files**. The sync compared every existing selected app file
with its bytes at the previous `14fa25f` pin before copying immutable Git blobs:
26 existing files changed, 11 files were added, and no host customization
conflicts were found. New files include the table-property helper, authored
table-border fixture/oracle, transition and picture-distance regressions, editor
split-identity tests and coverage-report controls. A subsequent three-file sync
from `a7e1a207` to the final pin adds the reviewed first story-page PNG, its
explicit paragraph-spacing assertion and a coverage-helper docstring correction.
No production source changed in that followup. The expanded hash guard passes.

This revision includes the imported-note formatting, style-transition,
table-border/paragraph-spacing and drawing-distance followup. The complete host
gate and the external schema gate pass against the production bytes from
`a7e1a207`, identical to the final pin. The source repository reviewed the story
page after the intended correction to imported styleless-paragraph spacing and
passed its full editor suite with the final PNG. The app gate does not regenerate
those reviewed images.

The previous integrated milestone was app checkpoint
[`78e65b9`](https://github.com/CrispStrobe/CrispCloud/commit/78e65b9eecd7861c95433819d11ac39375c40f9c)
with Quds source commit
[`14fa25f`](https://github.com/CrispStrobe/quds_office_suite/commit/14fa25f5e0775cc6468fc08d064cbb476d942215).
Its 125-package SDK snapshot remains separate from the new 131-package snapshot.
Both repositories use `feature/office-fidelity-completion-20261111`, preserving
their earlier fidelity work. App documentation checkpoint `faa444b` also carries
the updated main-branch ancestry through `e70f24c`.

The following results were verified locally for **source `a7e1a207`**, with
production-byte identity and the expanded guard rechecked at **`692a326`**, on
2026-11-11:

| Evidence | Result |
| --- | --- |
| Vendor guard | All 154 pinned files match |
| Portable engine regression selection | 163 Dart tests pass |
| Executable operation catalog | All 43 public operations appear in committed scenarios |
| Engine semantic/mutation/inventory controls | 113 Python tests pass |
| Engine output inventory | All 117 required Office files exist and are checked |
| Actual app controller, widget, preview, search and service cohort | 97 Flutter tests pass |
| Host inventory controls | 8 Python tests pass |
| Host coverage-report controls | 4 Python tests pass |
| Actual host DOCX inventory | All 14 required files exist and are checked |
| External Open XML SDK: actual host files | 14 packages, zero validation errors |
| External Open XML SDK: combined engine and host snapshot | 131 packages, zero validation errors |
| Office host line execution | 1,952 / 3,557 instrumented lines, 54.9%; all 9 matching source files instrumented |

The SDK's valid and deliberately invalid self-test controls also pass. These
are local results. GitHub Actions run
[`43101519120`](https://github.com/CrispStrobe/CrispCloud/actions/runs/43101519120)
was queued when the earlier app milestone was recorded; it does not establish
remote CI success for this newer source pin. Check the continuation branch's
latest Actions run separately.

The committed [host execution-gap report](office-host-coverage-gaps.json) lists
every uncovered instrumented line, file totals and source hashes. The nine host
source hashes are unchanged from the previous measurement; the new full run
reproduces the same counts. The report records its app source commit and scoped
dirty-state metadata. The 54.9% figure measures line execution in this cohort;
it does not measure branch correctness or completeness of Office format support.
Each run's original build report remains attached to its own source metadata.

## Run the integration gate

From the repository root, using the app's Flutter **3.47.8** toolchain:

```sh
flutter pub get
bash tool/check_office_fidelity.sh
```

The script checks vendored hashes, runs the independent DOCX/XLSX/PPTX corpus,
runs 16 root host regressions and independently inspects the asynchronous-save
DOCX produced by the controller. It includes the app's existing formatting,
minimal-edit round-trip, header editing and select-all checks.
The script checks the pinned files, runs the portable DOCX/XLSX/PPTX corpus and
independent semantic oracles, requires every engine output, then runs the host
cohort with fresh LCOV. It verifies the exact host output inventory and checks
the unchanged controller export with the independent ZIP/XML oracle. It deletes
only the expected host artifacts and the intended LCOV before the relevant
tests, preventing stale output from satisfying a missing test.

On Linux, native hooks need a C/C++ compiler. CI installs clang and SQLite
development files and uses the existing system-SQLite wrapper:

```sh
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

The GitHub workflow `.github/workflows/office-fidelity.yml` runs this command and
uploads exported files and JSON oracle reports. The latest local root suite
passed all 16 tests with GCC and system SQLite; temporary compiler discovery
settings were restored afterward. CI uses clang.

The portable corpus also passed under the app toolchain. The Open XML SDK 3.3.0
independently validated all 57 app-generated Office files, including the actual
asynchronous host save, with zero schema/semantic errors. The committed
[schema evidence](office-schema-evidence.json) pins the tested revisions and
SHA-256 hashes of every input.
The wrapper restores the app's `pubspec.yaml` after the command. Keep its
temporary native-hook override out of commits.

With .NET 8 available, the independent schema checks can run locally too:

```sh
dotnet run --project tool/office-validation -- --self-test
dotnet run --no-build --project tool/office-validation -- build/fidelity-host build/external/host-schema-report.json
dotnet run --no-build --project tool/office-validation -- build/fidelity build/external/controller-schema-report.json
dotnet run --no-build --project tool/office-validation -- packages/quds_office_engine/build build/external/engine-schema-report.json
```

The validator recursively finds Office packages below its input directory. The
first host directory contains 13 outputs; the unchanged controller document is
the fourteenth and lives in `build/fidelity/`. CI validates both together with
the engine exports after downloading the exact evidence artifact.

## Actual host saves and command history

[The save widget tests](../test/widget/office_save_fidelity_test.dart) open the
real `OfficeEditorDialog` through a verified remote file listing and delay its
upload using an in-memory storage client. They inspect the **actual attempted
upload bytes** using independent ZIP/XML readers. The four cases cover:

- Text, heading/style, paragraph, note and picture edits made while an older
  snapshot is uploading. The old success leaves the newer revision dirty;
  the second save contains those changes and cleans that revision.
- Save and Close during a pending edit. The dialog stays open until the newer
  revision has been saved.
- Selection/caret/render notifications during upload. These do not create
  document edits or prevent a successful clean save.
- A failed upload followed by a successful retry. The original bytes and
  unsaved changes remain available, and the retry writes the intended content.

The host records command revisions separately from rendering notifications.
Only a successful write to the captured original target can mark the captured
revision clean. This cohort exercises actual app loading, serialization,
target selection and dirty/close state with deterministic storage. Live storage
provider behavior requires separate provider tests.

[The section/text command tests](../test/office_section_break_fidelity_test.dart)
start with independently authored source XML and use the actual host controller
to insert a `nextPage` section break, edit body/header text with LF/CRLF/CR/tabs,
insert a footnote, undo and redo. Each scenario is saved and reopened three
times. The assertions read exported XML directly, retaining page-number starts,
grids, gutters, line-number settings, all six header/footer variants, historical
section metadata, note identity and real Word break/tab tokens.

The external schema check exposed a defect that content assertions alone
missed: cloned historical section properties reused a `sectPrChange` ID. The
pinned engine now allocates stable unique IDs while preserving the source
history. The host regression requires both uniqueness and stability across all
three saves, and all resulting packages pass SDK validation.

The [host artifact manifest](../tool/office_host_evidence.json) declares exactly
14 documents: seven snapshots from the four save cases, three section exports,
three text-break exports and one unchanged-controller export. The inventory
helper requires the full expected paths, verifies ZIP/main-part integrity and
records sizes/SHA-256 values. Missing, duplicate, ambiguous, unexpected or
escaping-symlink evidence fails the gate. Its controls also cover the wrapper
directory introduced by GitHub artifact downloads.

## F3 preview and content-search fidelity

[The preview tests](../test/office_preview_fidelity_test.dart) author ZIP/XML
fixtures independently of Quds. F3 preview honors explicit false bold/italic,
retains tabs and hard line breaks, resolves main-part and note relationships,
and includes referenced footnote/endnote bodies. Repeated references keep the
same preview marker; a footnote and endnote with the same stored ID remain
distinct. Preview markers follow a shared reading-order sequence; custom Word
note numbering and pagination remain outside this preview model.

Spreadsheet previews follow workbook relationship order and authored names,
including empty sheets and relocated shared strings. They exclude unrelated
worksheet files and external or escaping targets. Only packages without a
workbook part use a naturally sorted filename fallback. Authored names remain
document content; localization applies to generated `Sheet N` headings.

[The content-search tests](../test/office_search_fidelity_test.dart) cover the
corresponding package graph independently. DOCX search includes the owning
main part, referenced headers/footers and referenced footnote/endnote bodies.
XLSX search follows workbook order and resolves used shared strings. PPTX
search follows presentation order and each selected slide's owning notes.
Unrelated XML, orphan stories and external relationships are excluded. Search
accepts Transitional and Strict namespace variants; that scoped test does not
claim full Strict editing support in the engine or preview.

All selected XML reads share a cumulative byte budget, with repeated reads
cached. Emitted UTF-8 text has a separate limit of the same size, checked before
accumulation. A small shared-string part referenced by many cells therefore
cannot expand into unbounded search text. Authored positive and negative controls
cover that amplification, malformed selected XML, canonical fallback, relocated
parts and archive-boundary restrictions. The existing recursive search caller
tests remain in the integration gate.

## Scripted edits, oracles and goldens

The [scenario guide](../packages/quds_office_engine/tool/fidelity/README.md)
documents inspection/import, export, JSON modification scripts and repeated
save/reopen commands. The catalog has **25 Word, 10 spreadsheet and 8
presentation operations**. It includes heading/style definitions, explicit
run/paragraph formatting, caret notes and rich note stories, paragraph
split/insert/delete, list restarts, table text, pictures and six header/footer
variants, sections, cell values/formulas/formatting/dimensions/order, slide
text/geometry/notes/transitions/order and picture replacement.

Every public operation appears in a committed executable scenario. Unknown
fields, invalid types/ranges and unsupported operations fail before an existing
output is replaced. Expectations come from authored XML/JSON, native producer
fixtures and decoded image pixels. The Python readers inspect exported ZIP/XML
without importing the Quds serializer's interpretation. Mutation controls
damage valid outputs and require rejection; normal checks do not regenerate
expected values.

The portable corpus includes repeated unchanged and edited saves and targeted
note, style, list, media, compatibility, section, comment and opaque-content
cases. The source repository also runs full engine/editor suites, rendering
checks and reviewed Flutter PNG goldens. Its original rich-note page and three
first/even/default header/footer pages are tested under pinned Flutter
**3.44.0 on Linux**. Do not refresh those PNGs using the app's different SDK.

## CI evidence and remaining boundaries

The [integration workflow](../.github/workflows/office-fidelity.yml) runs on
`main`, on `feature/office-fidelity-*` pushes and on pull requests changing the
packages, relevant host code/tests/helpers or toolchain. Per-branch/PR
concurrency cancels superseded runs. The dependent external-schema job verifies
the downloaded host inventory, proves the SDK detects a deliberately invalid
control, then validates the engine exports and actual host bytes together.

| Evidence | Local path or Actions artifact |
| --- | --- |
| Exact host inventory and SHA receipt | `build/fidelity-host/inventory.json` |
| Fresh host LCOV and detailed gaps | `build/fidelity-host/coverage/lcov.info`, `build/fidelity-host/coverage/gaps.json` |
| Actual upload and controller documents | `build/fidelity-host/`, `build/fidelity/` |
| Engine semantic reports and exports | `packages/quds_office_engine/build/fidelity*` |
| Shared engine/host evidence artifact | `office-host-fidelity-evidence` |
| Downloaded host inventory and combined SDK report | `build/external/host-inventory.json`, `build/external/schema-report.json` |
| External schema artifact | `office-host-schema-evidence` |

The [source audit](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-completion-20261111/docs/office-fidelity-audit.md)
and [gap ledger](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-completion-20261111/docs/office-fidelity-gaps.json)
map scoped fixes to regressions and record remaining limitations. Their branch
may advance beyond this app's immutable pin; consult the manifest before
attributing a source fix to the app. Richer editable content-control/bookmark
models, referenced sheet renaming, slide-section rewrites and broader OS/font/
layout combinations remain acceptance boundaries. Retaining an opaque payload
does not establish that the editor can render or edit it.

Open XML SDK validity checks structural conformance. LibreOffice repeated-save
comparisons check stability in that renderer. Neither establishes pixel identity
with Microsoft Office or native application certification. The local host
cohort and explicit execution gaps provide narrower, reproducible evidence.

## Synchronizing the next source checkpoint

Copy only from a known source commit. Compare each existing app path with its
bytes at the previous manifest pin before applying the new source version; flag
host customizations for review. Include new shared helpers, tests and fixtures
in the manifest union, update the hashes and source commit together, then run
the vendor guard, host gate and external schema gate.

When a sibling checkout is at the selected source revision, compare it too:

```sh
python3 tool/verify_office_fidelity.py --source ../quds_office_suite
```

## Scripted edits and goldens

See [the scenario guide](../packages/quds_office_engine/tool/fidelity/README.md)
for developer commands to inspect/import/export a DOCX, execute JSON edit steps,
and maintain independent semantic goldens. Steps cover heading/style/text,
paragraph/run formatting, footnotes/endnotes and image resizing/replacement.

The shared corpus has three unchanged and three edited save/reopen cycles for
each of DOCX, XLSX and PPTX. Python checks actual ZIP/XML, relationships and
picture/opaque-part hashes against authored expectations. Nine oracle self-tests, including negative controls,
exercise the oracles themselves. The twelve reviewed editor PNGs are tested by the fork
under its pinned Flutter 3.44.0 environment; do not silently refresh it using the
app's different SDK.

## Fixes and limits

The integrated fixes now include dense-page footnote reservation and continuation,
rich note stories, tall table paragraphs with late notes, inherited style toggles,
sparse style definitions, document-local numbering, opaque Word body blocks,
atomic script output, native spreadsheet styles/pivots/live chart references,
and PowerPoint templates, media ownership, sections, notes and motion. The fork
also runs RTL, columns, sections, page breaks and table/notes page goldens.

The [fork audit](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-oracles/docs/office-fidelity-audit.md)
records current verification counts, external Open XML SDK/LibreOffice checks,
and explicitly separates covered cases from unsupported Office features. Coverage
is an inventory of executed lines, not a claim of complete OOXML support.

When syncing another change, review each source diff against host customizations,
copy the selected files, update their hashes and source commit together, then
run the guard and host suite. Do not update the manifest to conceal unexplained
source drift, or regenerate goldens merely to make a failing test pass.
Keep the old snapshot receipts attached to their original revision. Regenerate
coverage only from matching source/LCOV, and retain its source hashes and dirty
state. Do not change the manifest to conceal unexplained drift or regenerate a
golden merely because a failing exporter produced a different result.
