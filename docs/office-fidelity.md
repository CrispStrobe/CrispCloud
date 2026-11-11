# Office import/edit/export fidelity

CrispCloud resolves `quds_office_engine` and `quds_office_editor` through local
path overrides. These vendored packages therefore need explicit synchronization
with the `crispcloud` fork; changing the upstream branch alone cannot update the
running app.

`tool/office_fidelity_manifest.json` records the source commit and SHA-256 hashes
for the 33 shared implementation, scenario, fixture and golden files in this
change. The guard checks only those files, preserving unrelated host changes.

## Run

From the repository root, using the app's Flutter 3.47.8 toolchain:

```sh
flutter pub get
bash tool/check_office_fidelity.sh
```

The script checks vendored hashes, runs the independent DOCX/XLSX/PPTX corpus,
runs 15 root host regressions and independently inspects the asynchronous-save
DOCX produced by the controller. It includes the app's existing formatting,
minimal-edit round-trip, header editing and select-all checks.

On Linux, native hooks need a C/C++ compiler. CI installs clang and SQLite
development files, then uses the existing system-SQLite wrapper:

```sh
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

The GitHub workflow `.github/workflows/office-fidelity.yml` runs this command and
uploads exported files and JSON oracle reports. Local root testing was blocked
by the sandbox's missing clang; the actual native host suite passed on GitHub.

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
