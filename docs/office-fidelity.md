# Office import/edit/export fidelity

CrispCloud resolves `quds_office_engine` and `quds_office_editor` through local
path overrides. These vendored packages therefore need explicit synchronization
with the `crispcloud` fork; changing the upstream branch alone cannot update the
running app.

`tool/office_fidelity_manifest.json` records the source commit and SHA-256 hashes
for the shared implementation, scenario, fixture and golden files in this
change. The guard reports the current file count and checks only those files,
preserving unrelated host changes.

## Run

From the repository root, using the app's Flutter 3.47.8 toolchain:

```sh
flutter pub get
bash tool/check_office_fidelity.sh
```

The script checks vendored hashes, runs the independent DOCX/XLSX/PPTX corpus,
runs root controller and widget regressions and independently inspects the
asynchronous-save DOCX produced by the controller. It includes the app's
formatting, minimal-edit round-trip, header editing, select-all, preview/PDF
services, ribbon, paragraph-dialog and real host save checks.

On Linux, native hooks need a C/C++ compiler. CI installs clang and SQLite
development files, then uses the existing system-SQLite wrapper:

```sh
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

The GitHub workflow `.github/workflows/office-fidelity.yml` runs this command and
uploads exported files and JSON oracle reports. It runs on `main`, on
`feature/office-fidelity-*` pushes, and on pull requests changing the vendored
packages, Office host, captured save target, relevant tests or toolchain pins.

To compare against a sibling fork checkout as well as the manifest:

```sh
python3 tool/verify_office_fidelity.py --source ../quds_office_suite
```

## Host save fidelity

`test/widget/office_save_fidelity_test.dart` opens the actual `OfficeEditorDialog`
through a verified remote file listing and blocks its upload using an in-memory
storage client. It applies text, heading/style, paragraph, note and picture
changes while the older snapshot is uploading, then checks the uploaded DOCX
directly with independent ZIP/XML readers. The older snapshot must not clear
the newer edits' dirty flag; a second save must include those edits and clean
the document. Save and Close must keep the editor open when newer edits exist.
Selection/caret notifications do not count as edits, and failed uploads preserve
the original bytes and keep the current edits available for retry.

The host tracks command revisions separately from rendering notifications and
only marks the captured revision clean after the original target reports a
successful write. Exported host snapshots are retained in
`build/fidelity-host/`, separately from the unchanged/edited corpus fixtures.
These tests exercise the app's real loading, serialization, save-target and
dirty-state wiring with deterministic storage; they do not claim live-provider
or external Microsoft Office rendering coverage.

## F3 preview fidelity

`test/office_preview_fidelity_test.dart` authors ZIP/XML fixtures independently
of Quds. The preview honors explicit false bold/italic properties, retains tabs
and hard line breaks, resolves the package's main part and note relationships,
and includes referenced footnote/endnote bodies. Repeated references keep the
same preview marker; footnotes and endnotes with the same stored ID remain
distinct. Preview markers use a shared sequence in reading order, so they do
not claim the document's custom Word numbering or pagination.

Spreadsheet previews follow workbook relationship order and authored sheet
names, including empty named sheets and relocated shared-string parts.
Unreferenced worksheet files and external or escaping relationship targets are
excluded. Only packages without a workbook part use the fallback filename scan,
which sorts numbered sheets naturally. Authored sheet names remain document
content; localization still applies only to generated `Sheet N` headings.

## Scripted edits and goldens

See [the scenario guide](../packages/quds_office_engine/tool/fidelity/README.md)
for developer commands to inspect/import/export a DOCX, execute JSON edit steps,
and maintain independent semantic goldens. Steps cover heading/style/text,
paragraph/run formatting, footnotes/endnotes and image resizing/replacement.

The shared corpus has three unchanged and three edited save/reopen cycles for
each of DOCX, XLSX and PPTX. Python checks actual ZIP/XML, relationships and
picture/opaque-part hashes against authored expectations. Eight negative tests
exercise the oracles themselves. The reviewed editor PNG is tested by the fork
under its pinned Flutter 3.44.0 environment; do not silently refresh it using the
app's different SDK.

## Fixes and limits

The integrated fixes preserve note references through rich edits/history,
scope note/header hyperlinks correctly, respect explicit formatting defaults,
retain imported styles/numbering/table borders, split rich paragraphs safely,
insert notes at the caret and render mixed/multiline note bodies. The full fork
suites pass 478 engine tests and 228 editor tests, each with one existing skip.

The [fork audit](https://github.com/CrispStrobe/quds_office_suite/blob/feature/office-fidelity-oracles/docs/office-fidelity-audit.md)
maps fixes to evidence and lists remaining gaps. Its engine coverage report is
79.4% of instrumented lines, not a claim of complete OOXML support. Dense-page
footnote reflow, full rich-note layout, more complete style/list handling,
broader sheet/slide corpus and external Office-renderer validation remain open.

When syncing another change, review each source diff against host customizations,
copy the selected files, update their hashes and source commit together, then
run the guard and host suite. Do not update the manifest to conceal unexplained
source drift, or regenerate goldens merely to make a failing test pass.
