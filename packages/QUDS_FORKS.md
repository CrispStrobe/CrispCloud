# Quds forks

Vendored copies of the MIT-licensed Quds Office engine and editor, used by
CrispCloud for Word, Excel, PowerPoint and PDF handling.

- Upstream: https://github.com/MohammedAsaadAsaad/quds_office_suite
- Fork (canonical for our fixes): https://github.com/CrispStrobe/quds_office_suite, branch `main`
  (the old `crispcloud` branch is fully contained in it)
- Current fidelity continuation in both repositories:
  `feature/office-fidelity-completion-20261111`. The app's exact source pin below
  is authoritative while this work is reviewed on feature branches.

## Why we carry local copies

CrispCloud resolves both packages through `path` overrides in `pubspec.yaml`,
so builds are reproducible offline. The consequence is that a fix made only in
the fork never reaches the app, and a fix made only here never reaches the
fork. The rule is therefore: fix in one place, sync to the other, and let a hash
guard fail loudly if they drift.

The goal of the fixes is simple: opening a real Word, LibreOffice, Excel or
PowerPoint file, editing it and saving it must not silently change or lose
content.

## State (11 November 2026)

- Pinned fork revision: `14fa25f5e0775cc6468fc08d064cbb476d942215`, integrated in
  app checkpoint `78e65b9`. The continuation retains the prior `3146e63` work
  now merged into both main branches. `tool/office_fidelity_manifest.json`
  records the source commit and SHA-256 values for all 142 shared files;
  `tool/verify_office_fidelity.py` fails when a shared file differs. Unrelated
  vendor changes are allowed.
- The app gate passes 136 selected engine tests, 84 engine Python controls,
  all 43 public scripted operations and the exact 111-file engine inventory.
  Full engine/editor suite and renderer results belong to their separately
  recorded source checkpoints; see the fork's fidelity audit.
- CrispCloud host checks (`tool/check_office_fidelity.sh`, Flutter 3.47.8) pass
  97 actual host tests, eight inventory controls and four coverage-report
  controls. All 14 expected actual-host DOCX files are present. Office-host
  LCOV records 1,952/3,557 instrumented lines (54.9%) across all nine matching
  host files; the detailed report records source hashes and unhit lines.
- Open XML SDK validation of an immutable snapshot passes all 14 actual-host
  packages and all 125 combined engine/host exports with zero errors. Its
  positive and negative self-test controls pass. These are local verification
  results; the app milestone's remote Actions run was queued when recorded.
- A final source followup for imported-note formatting, style transitions,
  paragraph borders/spacing and drawing distances is pending. Those changes
  require a new immutable source pin and host verification before integration.

## What the local patches do

### Engine

- Footnotes and endnotes keep their identity, kind, formatting, hyperlinks and
  media relationships through editing, splitting, undo/redo and repeated saves.
  Mixed and multiple notes per paragraph render; multiline bodies, styled runs,
  tables and drawings in notes survive.
- Note layout reserves its band while the body is laid out; long notes continue
  on extra pages instead of overlapping or vanishing. Reference marks import as
  superscript, and separator/continuation chrome is recreated on save.
- Untouched paragraph, character and table styles, defaults, numbering
  definitions, table borders and opaque package parts are retained instead of
  regenerated. Explicit direct defaults (black, 11pt, zero spacing, left) are
  treated as set.
- List commands allocate document-local definitions, so they cannot collide
  with imported IDs; start values and Roman, alphabetic and padded-decimal
  formats are honored. List restart overrides survive repeated saves and
  continue only the intended list segment.
- Word child elements are emitted in ECMA-376 order and `w:highlight` maps back
  to Word's named values.
- PDF watermarks rotate as one marked line; the feature-showcase detail band
  fits its table.
- Sparse Word styles resolve through document defaults, `basedOn` chains,
  theme fonts/colours and character/table-region styles without freezing the
  inherited values into direct formatting.
- Spreadsheet saves keep source cell style records, pivot tables and live chart
  formulas instead of regenerating or flattening them.
- PowerPoint exports keep the imported slide masters, layouts and theme, and
  add any missing master/layout/theme and notes-size parts. Pictures and charts
  are namespaced to the slide that owns them, so editing or reordering one
  slide cannot overwrite another slide's media. Independent python-pptx and
  openpyxl fixtures (`native.pptx`, `native.xlsx`) test import against files
  this code did not write.
- Relocated Word parts follow owning relationships, compatibility markup
  selects one supported branch, and section/page-number/grid/history metadata
  survives edits and cloning. Cloned historical section IDs remain unique and
  stable, as checked by actual host exports and the external schema validator.
- Real Word break/tab tokens, note-story media ownership, authored comment
  threads and retained external-content payloads have dedicated multi-cycle
  regressions. Payload retention does not imply rendering or edit support.

### Editor

- Selection uses the theme selection colour (it was white-on-white).
- Header/footer edits force a full relayout.
- Footnote insertion follows the caret; paragraph splits keep rich runs;
  paragraph formatting no longer mutates history snapshots; list commands
  undo/redo.
- Report font tests match the supported italic/bold-italic slots.
- Later-page painting initializes the replacement viewport's layout; three
  reviewed PNGs cover first/even/default header and footer pictures before and
  after an asynchronous save.

### CrispCloud host

- Edits during an asynchronous upload remain dirty; Save and Close waits for
  the newer revision. Selection-only notifications and retry after failure
  have separate real-dialog regressions that inspect the attempted upload bytes.
- F3 previews honor explicit false formatting, tabs, breaks, note references
  and bodies, plus workbook order/names and relocated shared strings.
- Content search follows the DOCX/XLSX/PPTX relationship graph, excludes orphan
  and external parts, and bounds both XML reads and emitted text. Authored
  controls cover Strict namespace variants and shared-string amplification.

## Verification

Expected values come from authored XML/JSON, not from our own serializer
output, and negative tests prove the oracles reject damaged files.

```bash
# Needs Flutter >= 3.47 (the app requires Dart 3.13). CI uses 3.47.8.
export PATH=$HOME/flutter-3.47.8/bin:$PATH
bash tool/check_office_fidelity.sh
```

That script runs the vendor hash guard, the Python/Dart fidelity oracles in
`packages/quds_office_engine/tool/fidelity`, actual controller/widget/service
tests, fresh host LCOV, exact export inventories and the saved DOCX oracle.
On Linux, CI invokes it through `python3 tool/with_ci_system_sqlite.py` after
installing clang and SQLite development files. The app workflow additionally
validates the downloaded engine exports and actual host bytes with the Open XML
SDK (`tool/office-validation`), after proving that missing evidence and invalid
XML are rejected. Details and scoped limits: [office-fidelity.md](../docs/office-fidelity.md).

Known limit: the full-page golden is reviewed on Linux with Flutter 3.44.0. On
other platforms it can differ by about 0.6% of pixels from font rendering. Do
not regenerate it from another platform.

## Independent Word verification

```bash
~/miniconda3/bin/python tool/verify_word_roundtrip.py \
  build/quds_roundtrip/unedited.docx \
  build/quds_roundtrip/minimal.docx
```

The harness stages files in Word’s own sandbox container
(`~/Library/Containers/com.microsoft.Word/Data/tmp/crispcloud-word-verify`) so
Word does not repeatedly request folder access. It opens/saves/exports through
Microsoft Word, then checks paragraph text, footnote count/text, `footnoteRef`
markers, separator chrome and PDF text.

The previously recorded untouched and minimal-edit outputs both passed. Word
rendered correctly formatted superscript note numbers. This native application
result predates the current continuation checkpoint; it was not rerun for the
local Linux milestone above. Excel round-trips use
`tool/verify_excel_roundtrip.py` and passed for a Quds-generated workbook.
PowerPoint’s AppleScript surface lacks equivalent save-as support; use
python-pptx structural checks plus UI automation/LibreOffice for a native
render check. See `docs/office-engine-strategy.md` for the full verification
stack, BetterOffice status and remaining work.

## Upstream contribution rules

Follow
[CONTRIBUTING.md](https://github.com/MohammedAsaadAsaad/quds_office_suite/blob/main/CONTRIBUTING.md):

- engine and editor fixes are separate commits;
- engine code stays pure Dart (no Flutter or `dart:ui`);
- editor document surfaces stay `RenderBox`/`LeafRenderObjectWidget` only;
- tests live next to the behavior they cover;
- package CHANGELOGs get an `Unreleased` entry for user-visible changes;
- do not bump versions outside a release.

## Syncing

The app resolves these packages through local `path` overrides in
`pubspec.yaml`, so builds are reproducible offline.

Checkpoint source changes on a feature branch, then copy the intended files
from that immutable source commit. Before overwriting an existing app file,
compare it with the previous pinned source bytes so host customizations are
reviewed. Add new shared helpers/tests/fixtures to the manifest union and update
their hashes and source commit together. Do not copy unrelated working-tree
edits or build artifacts.

```bash
# With the sibling source checkout at the exact selected source commit:
python3 tool/verify_office_fidelity.py --source ../quds_office_suite
python3 tool/with_ci_system_sqlite.py bash tool/check_office_fidelity.sh
```

Run the external schema gate over the complete evidence as well, then push the
app feature checkpoint. Keep commits small and add a CrispCloud regression test
for every host-visible bug. Do not rewrite packages during sync or regenerate
goldens simply to accept changed output.
