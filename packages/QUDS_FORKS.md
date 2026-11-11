# Quds forks

Vendored copies of the MIT-licensed Quds Office engine and editor, used by
CrispCloud for Word, Excel, PowerPoint and PDF handling.

- Upstream: https://github.com/MohammedAsaadAsaad/quds_office_suite
- Fork (canonical for our fixes): https://github.com/CrispStrobe/quds_office_suite, branch `main`
  (the old `crispcloud` branch is fully contained in it)

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

- Pinned fork revision: `c9db5a8` ("preserve PowerPoint templates and isolate
  slide media"), now merged into the fork's `main` (`a855d79`) and into
  CrispCloud `main`. `tool/office_fidelity_manifest.json` records that source
  commit and a SHA-256 for every shared file; `tool/verify_office_fidelity.py`
  fails when a shared file differs from it. Unrelated vendor changes are allowed.
- Engine suite in the fork: 493 passed, 3 optional-fixture skips, analysis clean
  with `--fatal-infos`; `quds_reports` clean and passing. Editor analysis clean;
  its only local failure is the Linux-reviewed page golden (font rasterization
  drift on macOS, see Known limits in the fork README).
- CrispCloud host checks (`tool/check_office_fidelity.sh`, Flutter 3.47.8):
  vendor hash guard, engine oracles, host tests and the independent corpus
  verification (DOCX, XLSX and PPTX save/reopen exports) all pass.
- The earlier RTL MultiPage PDF failure noted in the 5 November baseline is not
  reproduced in the fork's current engine suite.

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
  formats are honored.
- Word child elements are emitted in ECMA-376 order and `w:highlight` maps back
  to Word's named values.
- PDF watermarks rotate as one marked line; the feature-showcase detail band
  fits its table.
- PowerPoint exports keep the imported slide masters, layouts and theme, and
  add any missing master/layout/theme and notes-size parts. Pictures and charts
  are namespaced to the slide that owns them, so editing or reordering one
  slide cannot overwrite another slide's media. Independent python-pptx and
  openpyxl fixtures (`native.pptx`, `native.xlsx`) test import against files
  this code did not write.

### Editor

- Selection uses the theme selection colour (it was white-on-white).
- Header/footer edits force a full relayout.
- Footnote insertion follows the caret; paragraph splits keep rich runs;
  paragraph formatting no longer mutates history snapshots; list commands
  undo/redo.
- Report font tests match the supported italic/bold-italic slots.

## Verification

Expected values come from authored XML/JSON, not from our own serializer
output, and negative tests prove the oracles reject damaged files.

```bash
# Needs Flutter >= 3.47 (the app requires Dart 3.13). CI uses 3.47.8.
export PATH=$HOME/flutter-3.47.8/bin:$PATH
bash tool/check_office_fidelity.sh
```

That script runs the vendor hash guard, the Python/Dart fidelity oracles in
`packages/quds_office_engine/tool/fidelity`, the host tests
(`test/office_fidelity_workflow_test.dart`, formatting, round-trip and editor
fix tests) and checks the saved DOCX corpus. The fork additionally validates
exported packages with the Open XML SDK (`tool/office-validation`) in its
`office-fidelity` workflow. Details: `docs/office-fidelity.md`.

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

The untouched and minimal-edit outputs both passed. Word rendered correctly
formatted superscript note numbers. Excel round-trips use
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

```bash
# In the fork checkout on branch main (then update tool/office_fidelity_manifest.json):
rsync -a /path/to/CrispCloud/packages/quds_office_engine/ \
  packages/quds_office_engine/
rsync -a /path/to/CrispCloud/packages/quds_office_editor/ \
  packages/quds_office_editor/
git add packages/quds_office_engine packages/quds_office_editor
git commit -m "CrispCloud: update Quds patches"
git push origin main
```

Keep commits small and add a CrispCloud regression test for every fixed bug.
Do not rewrite the packages during sync; copy only intended files.
