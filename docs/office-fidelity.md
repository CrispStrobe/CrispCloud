# Office import/edit/export fidelity

CrispCloud resolves `quds_office_engine` and `quds_office_editor` through local
path overrides. These vendored packages therefore need explicit synchronization
with the `crispcloud` fork; changing the upstream branch alone cannot update the
running app.

`tool/office_fidelity_manifest.json` records the source commit and SHA-256 hashes
for the 87 shared implementation, scenario, fixture and golden files in this
change. The guard checks only those files, preserving unrelated host changes.

## Run

From the repository root, using the app's Flutter 3.47.8 toolchain:

```sh
flutter pub get
bash tool/check_office_fidelity.sh
```

The script checks vendored hashes, runs the independent DOCX/XLSX/PPTX corpus,
runs 16 root host regressions and independently inspects the asynchronous-save
DOCX produced by the controller. It includes the app's existing formatting,
minimal-edit round-trip, header editing and select-all checks.

On Linux, native hooks need a C/C++ compiler. CI installs clang and SQLite
development files, then uses the existing system-SQLite wrapper:

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

To compare against a sibling fork checkout as well as the manifest:

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
