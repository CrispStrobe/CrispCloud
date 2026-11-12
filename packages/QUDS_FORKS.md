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

## State (12 November 2026)

- Pinned fork revision: `84b11839126a9577b6688b6acf80edd3cc2601ee` (fork
  `main`), which merges both fidelity branches: bookmarks, content controls,
  exact note-marker placement (completion) and inline fields, tracked-change
  hyperlinks, replayable structure edits (coverage), plus footnote editing in
  the notes pane. The SHA-256 guard covers 237 shared files, including the new
  engine model/serial files, tests, fixtures and oracles.
- Header/footer page-number content controls (`docPartObj` or bare wrappers)
  import again; data-carrying header/footer controls still fail closed.
- Insert > Footnote…/Endnote… prompts for the text and opens the notes pane;
  View toggles the notes pane. Unedited saves keep imported note-body markers
  exactly as in the source (none are invented).
- Local verification at this pin: fork engine 774 tests; host
  `tool/check_office_fidelity.sh` passes (all exports match goldens/oracles).
  The editor's page-image goldens are reviewed on Linux CI; six differ on
  macOS fonts only.

## Earlier state (11 November 2026)

- Pinned fork revision: `431bffa31a4f007d88cbb9b19d59bd5dcd04bdff`.
  The exact SHA-256 guard now covers 158 shared files. This adds the canvas
  image-cache lifecycle fix to the previously verified `692a326` revision:
  decoded images are released when an editor closes, and late decoding cannot
  repaint a disposed Word, Sheet or Slide canvas. Two deterministic source
  tests and the real host's three-save/reopen picture workflow pass.
- CrispCloud now exposes Footnote and Endnote in the Word Insert tab and menu,
  with translations, cancellation/read-only checks, undo/redo and preserved
  whitespace. The 15-test targeted ribbon/save/localization cohort passes.
  Its authored export assertions cover headings, explicit unbold, paragraph
  settings, note bodies/IDs and both imported and inserted picture payloads.
  The exact host inventory has grown from 14 to 17 documents; the full gate
  will regenerate all of them together before final integration is recorded.
- The prior broad milestone (source `692a326`, app `2203f2b`) passed 163
  selected engine tests, 113 engine Python controls, all 43 public scripted
  operations and 117 required engine outputs. Its actual host cohort passed
  97 tests, with eight inventory controls and four coverage controls. Its
  immutable 14-host/131-combined package snapshot passed Open XML SDK checks.
  Those counts describe the earlier checkpoint, not the current expanded suite.
- That earlier host cohort executed 1,952/3,557 instrumented lines (54.9%)
  across all nine selected host files. The report will be refreshed after the
  complete expanded cohort runs. Source full-suite, golden and renderer evidence
  remains documented separately in the fork. Remote Actions status must be
  checked separately; locally passing gates do not imply remote CI success.

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

## Consolidated continuation — 12 November 2026

`feature/office-fidelity-consolidation-20261112` combines current app main with
the newer Office coverage branch. The vendor manifest now pins 309 shared files
to suite commit `3ff2e15823c86cda88d3369dc4bbabf42f45290a` on the same feature
branch. This retains both source histories and their independent regression
corpora, and integrates the monotonic content revision used to protect pending
Word note, spreadsheet cell, and slide text drafts during uploads.

The acceptance inventory requires 241 engine exports and 59 actual host saves
(48 DOCX, 4 XLSX, 4 PPTX, and one DOCM/DOTX/DOTM each).
See [the consolidation report](../docs/office-fidelity-consolidation-20261112.md)
for current validation status; the earlier measurements above remain historical.
