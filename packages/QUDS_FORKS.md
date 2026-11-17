# Quds forks

Vendored copies of the MIT-licensed Quds Office engine and editor, used by
CrispCloud for Word, Excel, PowerPoint and PDF handling.

- Upstream: https://github.com/MohammedAsaadAsaad/quds_office_suite
- Fork (canonical for our fixes): https://github.com/CrispStrobe/quds_office_suite, branch `main`
  (the old `crispcloud` branch is fully contained in it)
- Current integrated sources are pinned in `tool/office_fidelity_manifest.json`.
  Feature acceptance records retain their original qualified source identities.

## Why we carry local copies

CrispCloud resolves both packages through `path` overrides in `pubspec.yaml`,
so builds are reproducible offline. The consequence is that a fix made only in
the fork never reaches the app, and a fix made only here never reaches the
fork. The rule is therefore: fix in one place, sync to the other, and let a hash
guard fail loudly if they drift.

The goal of the fixes is simple: opening a real Word, LibreOffice, Excel or
PowerPoint file, editing it and saving it must not silently change or lose
content.

## Current integrated state (17 November 2026)

The app mirrors the canonical Quds source and the standalone legacy parser.
Exact revisions, source boundaries and the complete managed-file inventory are
recorded in [the fidelity manifest](../tool/office_fidelity_manifest.json).
The current canonical checkpoint is `ec5ecbff742580c0e7d1136507b953e8cc877e4c`;
the managed inventory contains 2,606 files: 749 canonical files and the unchanged
1,857-file standalone parser. The 17 November continuation reconciles the
captured Office, morphology and proofing-tool branches and their bounded late
arrivals. It preserves the original six bundled notices and adds the complete
Unicode Inflection notice for German morphology to the app's license registry.

The latest reconciliation merges captured host main `1cd2a18f7bc2455eabc5ec8e22767c849a833305` and synchronizes the canonical union through the guard. It retains the bounded German noun-agreement work, custom ODT tab stops, table row minimum-height semantics and decoration normalization. The optional native German proofing AOT package remains outside the existing host managed-package boundary. New tests exercise the actual ODT/ODP export menus, annotation privacy, semantic output and destination outcomes; their local execution evidence is recorded separately from prior qualifications in `docs/validation/office-reconcile-20261117/`.

ODF annotations retain their raw XML and comment-model content while body
extraction, search and host previews exclude them. Note references inside
comments preserve their marks without claiming a visible body note definition.
The [resumed continuation record](../docs/validation/office-resume-20261117/README.md)
binds the fixed incoming inventory, source preservation and local qualification
to exact commits. The pinned runtime and unchanged locked dependency workspaces
are restored. Fresh focused host qualification passed at `511361a4623e6ddf787b5cccfaed4ba14ae1899f`: 96 Dart/Flutter cases and 28 Python controls, with no host failures or skips; all 11 gates and independent review passed. Runtime/test/tool/manifest inputs remain identical in the final documentation checkpoint. Earlier qualification
counts retain their original source attribution. The incoming [German grammar options report](../docs/validation/german-options-20261117/README.md) retains its separate source-bound evidence. This continuation retains the completed Zotero recovery,
English hyphenation, proofing and ranked/average spreadsheet work, including
conditional-format differential-style preservation, current proofing/rendering branches,
and the ODT/ODP writers from canonical main. The host
bundles all six original Office notices, including the American English
`LicenseRef-Kuiken-permissive` grant and the British English MIT notice.
The [previous completed qualification](../docs/validation/zotero-recovery-20261116/README.md)
retains its original implementation identities; its totals are not a fresh
qualification of this newer integrated source. The host now exposes a sheet-only
**Export as ODS** action backed by `OdsSheetWriter`; ordinary Save and the
legacy-Excel path still produce new XLSX copies.
Managed files must match those sources; the guarded sync and verifier enforce
that requirement. New work includes supported BIFF8/HTML/ODS spreadsheet imports, shared
formulas, explicit and inherited wrap-text styles, and cell font families, guarded worksheet navigation and HTML table captions/headers; Word-like selection, inline picture placement inside its line, inline field preservation, revision
performance fixes and opaque unsupported headers. Integration regressions cover
header revision ownership, field isolation across stories and non-text field
results. Legacy DOC preview/conversion explicitly enables parser recovery and
reports limitations; converted legacy documents save separately as OOXML.

ODS metadata imports include print areas, titles, names, auto-filters and
same-workbook list-source snapshots. Validation source expansion shares a
two-million-cell work budget across definitions, checks coordinate bounds before
iteration, and preserves spaces in quoted sheet names. Dynamic validation links
remain outside this snapshot contract.
Shared spreadsheet-level list definitions now apply to every referring sheet,
including blank input cells. Table-local definitions stay isolated, and blank
validation references obey the expanded-cell and grid bounds. The 16 November
integration includes the latest canonical main and rich Zotero/note-ordering
continuation; its source and local checks are recorded under
`docs/validation/repo-integration-20261116/`.

Zotero support adds a shared references workspace, read-only online and desktop clients,
offline CSL import/export, guarded DOCX citation and bibliography fields, and
undoable editing. CrispCloud supplies its selected proxy/TLS transport and
optional existing credential store. See [usage and formatting limits](../docs/zotero.md)
and [source-bound local validation](../docs/zotero-validation.md). This adds
targeted Zotero qualification; earlier storage and spreadsheet results retain
their original source identities.

The preceding source-integration checkpoint brought in the latest Word content-control display imports
and between/not-between spreadsheet conditions. The complete managed inventory
at that checkpoint was compared by Git blob, size and mode to its pinned canonical
sources; the six changed managed files were freshly hashed. See the
[integration receipt](../docs/validation/zotero-local-identity-20261115/recent-integration.json).
No application test or build result is claimed for this source integration.

The completed local-identity checkpoint connects unsynced local references to
individual style previews, metadata-only atomic basic refresh, selected exports
and formatted bibliographies. Every connected operation verifies the expected
source identity. Desktop aggregate output additionally requires the database
identifier and library-version headers provided by Zotero 10 or later; it
refuses changed or incomplete selections. Older desktops can still use
same-response previews and metadata refresh when the returned identity matches.

The continuation adds 39 regression cases across client, model/DOCX, helper and
widget suites. All are committed and source-reviewed; none was executed. No
Dart parser, formatter, analyzer, application build or live Zotero acceptance
is claimed. The final managed inventory contains 2,375 files: six changed files
were freshly hashed in this checkpoint, and 2,369 immutable blobs/modes/sizes
retain prior digest evidence, including the four files freshly hashed at the
[interim engine checkpoint](../docs/validation/zotero-local-identity-20261115/feature-checkpoint.json).
The [source review](../docs/validation/zotero-local-identity-20261115/REVIEW.md)
and [complete source inventory and final receipt](../docs/validation/zotero-local-identity-20261115/final-integration.json)
record the workflow limits, all managed source identities and verification scope.

The latest canonical checkpoint preserves internal repeated ODS blank rows,
counts covered merge placeholders only once, and translates formula syntax
without changing quoted literals or quoted sheet identifiers. Explicit cell, row
default and column default styles retain their precedence; the document Normal
style and default column/row geometry are applied when no explicit style exists.
ODS pictures import as worksheet drawings; conditional formats (numeric, between, contains-text, begins/ends-with and duplicate) and list/range-source, whole, decimal, date, text-length and custom-formula
validations, prompts and error styles are imported; tab colours, cell
hyperlinks, named expressions, outline groups and comparison/empty filter predicates round-trip; conditional formats are painted and serialized with dxf styling. Hidden rows, columns and sheets
survive an ODS→XLSX save. Absolute sheet references, clock components and
elapsed time formats survive XLSX saves. The sheet/ODS development cohort is
514 tests; the ODS reader+writer suite is 115 tests; the last clean full engine run was 2,205 tests, with two unrelated CLI
bookmark/content-control tests currently failing on main. The ODS writer emits
the modeled workbook subset, including pictures, conditional formats,
validations, ranked/average conditional rules, authored page setup and
header/footer sections. The bounded ODT writer now covers headings, formatted
runs, tables, pictures, frames, page geometry and basic headers/footers. The
bounded ODP writer covers slides, positioned text, pictures, tables, fills,
strokes, text links, notes, page geometry and transitions. A host widget test opens an XLSX fixture and reads the exported ODS
back. The combined host qualification remains separately source-bound
in the storage evidence.

The resumed storage qualification also integrates Word inline-picture retention
and Excel wrap-text support. Import preserves the correct wrap flag for each
native style, unwrapped cells cannot reuse wrapped styles, and wrap-only edits
survive new-workbook saves. The scripted Word oracle resolves heading outline
levels through paragraph styles and their inheritance while retaining explicit
override and malformed-style negative controls.

ODS import and table previews preserve merged/covered-cell coordinates and
repeated interior blank rows. Namespace-aware grouped rows and inherited cell
styles are retained. Expansion budgets reject out-of-profile data explicitly;
unsupported repeated/matrix formulas and ambiguous merges are not silently
converted. The editor exports a new XLSX copy and keeps the ODS source intact.
Regression tests cover completed copies, cancellation, browser downloads and
newer edits made while a copy picker is open. The exact supported import profile
and limits are documented in the engine CHANGELOG.

Selection screenshot tests retain the original macOS-authored masters and use
separate Linux-host references. The Linux PNGs are exact captures from the
unchanged pre-reconciliation source; independent comparison confirms identical
selection geometry and table borders. No comparison tolerance is relaxed.

The storage continuation retains its earlier combined canonical checkpoint
`01f167cc` in [the reconciliation record](../docs/office-storage-reconciliation-20261115.md).
The current pin above combines the subsequent canonical main, inline-picture
and wrap-text branches, preserves the standalone parser source, and includes
targeted wrap regressions. The source cutoff and new qualification are recorded
in the storage evidence directory; earlier totals below retain their own pins.

## Spreadsheet audit checkpoint (14 November 2026)

- Audited fork revision: `fad26db2d5054c48705d27b0fb4808ed63aada2f` (fork
  `main`), also containing the recovery checkpoint `2d2a7be4`.
- Four spreadsheet defects found by the Excel fidelity audit are fixed and
  regression-tested:
  - cell comments now write a schema-valid `CT_Comments` part (`<authors>`,
    `<commentList>`, `authorId`), the comments content type, and the worksheet
    relationship (`2536169e`);
  - `OfficeIsolateSave.workbook` accepts `recalculate: false`, so a no-edit
    save preserves native formula caches instead of overwriting them with the
    engine's approximate evaluator (`f8983b46`);
  - frozen panes are anchored on `topLeftCell`, not positional `xSplit`, and
    `state="frozenSplit"` is accepted (`f8983b46`, `574f834`);
  - authored custom number formats are emitted as `<numFmts>` entries and merge
    with native collections in schema order (`5d57de3`).
- Sheet cohort: 361 tests pass in the fork and in this checkout.
- Audit harness and recipes: <https://github.com/CrispStrobe/excel-steering>
  (private workbooks are never committed).

## State (14 November 2026, spreadsheet fidelity)

- Pinned fork revision: `9b81058f0e11bf866e3057a6f2f9a6c9a8ece0e2` (fork
  `main`, resolved by the sync tool), also containing the recovery checkpoint
  `2d2a7be4`.
- Four spreadsheet defects found by the Excel fidelity audit are fixed and
  regression-tested:
  - cell comments now write a schema-valid `CT_Comments` part (`<authors>`,
    `<commentList>`, `authorId`), the comments content type, and the worksheet
    relationship (`2536169e`);
  - `OfficeIsolateSave.workbook` accepts `recalculate: false`, so a no-edit
    save preserves native formula caches instead of overwriting them with the
    engine's approximate evaluator (`f8983b46`);
  - frozen panes are anchored on `topLeftCell`, not positional `xSplit`, and
    `state="frozenSplit"` is accepted (`f8983b46`, `574f834`);
  - authored custom number formats are emitted as `<numFmts>` entries and merge
    with native collections in schema order (`5d57de3`);
  - legacy `.xls` workbooks (BIFF8 and HTML tables) import into the shared
    model with typed values, formulas, shared formula groups, formats, merges,
    widths and frozen panes (`cb9eabe`, `fbf3600`, `0918d2e`);
  - fonts carry a family through import/save instead of collapsing to Calibri,
    and XML text encoding drops characters XML 1.0 forbids (`de18049`,
    `fbf3600`).
- Sheet cohort: 361 tests pass in the fork and in this checkout.
- Audit harness and recipes: <https://github.com/CrispStrobe/excel-steering>
  (private workbooks are never committed).

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

## Remaining limits

The engine-side backlog is tracked in the Quds
[office-remaining-gaps.md](https://github.com/CrispStrobe/quds_office_suite/blob/main/docs/office-remaining-gaps.md).
The host-level backlog is
[office-remaining-gaps-20261115.md](../docs/office-remaining-gaps-20261115.md).

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

## Terminal/ODS follow-up (16 November 2026)

The combined source retains shared spreadsheet-level and blank-cell validation
rules alongside the canonical whole-number, decimal, date and text-length
operators. A regression binds a shared numeric rule on a blank input cell to
its XLSX-copy round trip. Fresh qualification passed 507 engine spreadsheet/ODS
tests and 53 host viewer/editor tests; the available local ODS imported without
an unsupported-profile refusal. Dynamic list links, custom/formula-driven rules,
full native prompt/error metadata and native ODS serialization remain outside
this supported profile. Exact source identities and scope are recorded in
`docs/validation/terminal-ods-refresh-20261116/summary.json`.

ODT export also writes modeled list groups, retaining the combined whitespace and visible Zotero-result behavior.
